// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation
import IOKit
import IOKit.pwr_mgt
import os
import Security

private let log = Logger(subsystem: BatteryCareIdentifiers.helperID, category: "BatteryCare")

/// What the helper keeps across restarts, in a file only root can write.
private struct HelperState: Codable {
    var settings = BatteryCareSettings()
    var activity = BatteryCareActivity.none
    var memory = BatteryCareMemory()
    var appliedLowPower: BatteryLowPowerPreference?
    var sleepDisabledByHelper = false
    var events: [BatteryCareStatusEvent] = []
    var nextSerial = 1
}

/// Battery Care's root helper. It holds the charge limit on its own, so the
/// limit stays while the app is closed, updated or another person is signed
/// in. The app only reads its status and sends the person's choices.
private final class BatteryCareDaemon: NSObject, BatteryCareXPCProtocol {
    private let queue = DispatchQueue(label: "\(BatteryCareIdentifiers.helperID).queue")
    private let hardware = BatteryCareHardware()
    private let stateFile = URL(fileURLWithPath: BatteryCareIdentifiers.stateDirectory)
        .appendingPathComponent("state.json")
    private var state = HelperState()
    private var reading: BatteryCareReading?
    private var decision: BatteryCareDecision?
    private var sleeping = false
    private var assertion: IOPMAssertionID = 0
    private var ledWasManaged = false
    private var timer: DispatchSourceTimer?
    private var rootPort: io_connect_t = 0
    private var notifyPort: IONotificationPortRef?
    private var notifier: io_object_t = 0
    private var error: String?

    private var capabilities: BatteryCareCapabilities { hardware?.capabilities ?? BatteryCareCapabilities() }

    func start() {
        queue.sync {
            load()
            // A sleep switch a crash left on would keep a closed Mac awake in a bag.
            if state.sleepDisabledByHelper { setLidSleep(disabled: false) }
            if hardware == nil { error = "This Mac's charging controller can't be reached." }
            applyLowPowerPreferenceIfNeeded()
            registerForSleep()
            tick()
        }
    }

    // MARK: XPC

    func status(withReply reply: @escaping (Data) -> Void) {
        queue.async { reply(BatteryCareIPC.encode(self.currentStatus())) }
    }

    func perform(_ command: Data, withReply reply: @escaping (Data) -> Void) {
        queue.async {
            if let command = BatteryCareIPC.decode(BatteryCareCommand.self, from: command) {
                self.handle(command)
            }
            reply(BatteryCareIPC.encode(self.currentStatus()))
        }
    }

    private func handle(_ command: BatteryCareCommand) {
        let now = Date()
        switch command {
        case .apply(let settings):
            state.settings = settings.validated()
            if !state.settings.enabled { state.activity = .none }
            applyLowPowerPreferenceIfNeeded()
        case .discharge(let target):
            state.activity = .discharge(target: min(max(target, 5), 100))
        case .stop:
            state.activity = .none
        case .topUp(let on):
            if on { state.activity = .topUp } else if state.activity == .topUp { state.activity = .none }
        case .calibrate:
            state.activity = .calibration(.chargeFull, since: now)
        case .fixReading:
            state.activity = .readingFix(.chargeFull, since: now)
            state.memory.lastReadingFix = now
        case .led(let color):
            hardware?.setLED(color)
        case .lowPowerMode(let on):
            pmset(["-a", "lowpowermode", on ? "1" : "0"])
        }
        tick()
    }

    private func currentStatus() -> BatteryCareStatus {
        BatteryCareStatus(helperVersion: BatteryCareIdentifiers.helperVersion,
                          settings: state.settings,
                          activity: state.activity,
                          state: decision?.state ?? (state.settings.enabled ? .paused : .off),
                          reading: reading,
                          capabilities: capabilities,
                          chargingAllowed: decision?.allowCharging ?? true,
                          adapterEnabled: decision?.adapterEnabled ?? true,
                          preventingSleep: assertion != 0,
                          events: state.events,
                          error: error)
    }

    // MARK: The loop

    private func tick() {
        guard let reading = BatteryCareReader.read() else {
            self.reading = nil
            schedule(after: 30)
            return
        }
        self.reading = reading
        var memory = state.memory
        let decision = BatteryCarePolicy.decide(settings: state.settings, activity: state.activity,
                                                memory: &memory, reading: reading,
                                                capabilities: capabilities, sleeping: sleeping, now: Date())
        let changed = memory != state.memory || decision.activity != state.activity || !decision.events.isEmpty
        state.memory = memory
        state.activity = decision.activity
        for event in decision.events {
            state.events.append(BatteryCareStatusEvent(serial: state.nextSerial, event: event, date: Date(),
                                                       percent: reading.percent))
            state.nextSerial += 1
            log.info("Battery Care: \(event.rawValue, privacy: .public) at \(reading.percent)%")
        }
        state.events = Array(state.events.suffix(30))
        apply(decision)
        self.decision = decision
        if changed { save() }
        // The voltage is watched closely while the battery runs the Mac.
        schedule(after: decision.adapterEnabled ? 5 : 2)
    }

    private func apply(_ decision: BatteryCareDecision) {
        guard let hardware else { return }
        guard state.settings.enabled else {
            hardware.restoreSystemCharging()
            ledWasManaged = false
            setSleepPrevented(false, lid: false)
            return
        }
        // The helper cannot watch a sleeping Mac, so it never discharges then.
        let adapter = decision.adapterEnabled || sleeping
        var ok = hardware.setAdapter(enabled: adapter)
        ok = hardware.setFirmwareLimit(decision.firmwareLimit) && ok
        ok = hardware.setCharging(allowed: decision.allowCharging) && ok
        if state.settings.magSafeLED {
            hardware.setLED(decision.led)
            ledWasManaged = true
        } else if ledWasManaged {
            hardware.setLED(.system)
            ledWasManaged = false
        }
        error = ok ? nil : "The charging controller refused a change."
        setSleepPrevented(decision.preventSleep && !sleeping,
                          lid: decision.preventSleep && state.settings.disableSleepUntilLimit)
    }

    private func schedule(after seconds: Int) {
        timer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .seconds(seconds), leeway: .seconds(1))
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer
    }

    // MARK: Sleep

    private func registerForSleep() {
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        rootPort = IORegisterForSystemPower(refcon, &notifyPort, { refcon, _, messageType, argument in
            guard let refcon else { return }
            Unmanaged<BatteryCareDaemon>.fromOpaque(refcon).takeUnretainedValue()
                .power(messageType, argument)
        }, &notifier)
        if let notifyPort { IONotificationPortSetDispatchQueue(notifyPort, queue) }
    }

    /// Runs on `queue`: the notification port delivers there.
    private func power(_ messageType: natural_t, _ argument: UnsafeMutableRawPointer?) {
        switch messageType {
        case 0xE000_0270: // kIOMessageCanSystemSleep
            IOAllowPowerChange(rootPort, Int(bitPattern: argument))
        case 0xE000_0280: // kIOMessageSystemWillSleep
            sleeping = true
            tick()
            IOAllowPowerChange(rootPort, Int(bitPattern: argument))
        case 0xE000_0300: // kIOMessageSystemHasPoweredOn
            sleeping = false
            tick()
        default:
            break
        }
    }

    private func setSleepPrevented(_ prevent: Bool, lid: Bool) {
        if prevent, assertion == 0 {
            var id: IOPMAssertionID = 0
            let reason = "Battery Care is charging to the limit" as CFString
            if IOPMAssertionCreateWithName(kIOPMAssertionTypePreventSystemSleep as CFString,
                                           IOPMAssertionLevel(kIOPMAssertionLevelOn), reason, &id) == kIOReturnSuccess {
                assertion = id
            }
        } else if !prevent, assertion != 0 {
            IOPMAssertionRelease(assertion)
            assertion = 0
        }
        let wantsLid = prevent && lid
        if wantsLid != state.sleepDisabledByHelper {
            setLidSleep(disabled: wantsLid)
        }
    }

    /// Closing the lid sleeps the Mac despite an assertion, so keeping it
    /// charging with the lid closed needs pmset's switch. Only a switch this
    /// helper turned on is ever turned off.
    private func setLidSleep(disabled: Bool) {
        if pmset(["-a", "disablesleep", disabled ? "1" : "0"]) {
            state.sleepDisabledByHelper = disabled
            save()
        }
    }

    // MARK: Low Power Mode

    private func applyLowPowerPreferenceIfNeeded() {
        let wanted = state.settings.enabled ? state.settings.lowPowerMode : .unchanged
        guard wanted != state.appliedLowPower else { return }
        let ok: Bool
        switch wanted {
        case .unchanged: ok = true
        case .alwaysOff: ok = pmset(["-a", "lowpowermode", "0"])
        case .alwaysOn: ok = pmset(["-a", "lowpowermode", "1"])
        case .onBattery: ok = pmset(["-b", "lowpowermode", "1"]) && pmset(["-c", "lowpowermode", "0"])
        case .onAdapter: ok = pmset(["-b", "lowpowermode", "0"]) && pmset(["-c", "lowpowermode", "1"])
        }
        if ok {
            state.appliedLowPower = wanted
            save()
        }
    }

    @discardableResult
    private func pmset(_ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    // MARK: State

    private func load() {
        guard let data = try? Data(contentsOf: stateFile),
              let saved = BatteryCareIPC.decode(HelperState.self, from: data) else { return }
        state = saved
        state.settings = saved.settings.validated()
    }

    private func save() {
        let directory = stateFile.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o755])
        try? BatteryCareIPC.encode(state).write(to: stateFile, options: .atomic)
    }

    /// Stopping hands charging back to the Mac: uninstalling, updating and
    /// shutting down all end here.
    func stop() {
        queue.sync {
            timer?.cancel()
            hardware?.restoreSystemCharging()
            setSleepPrevented(false, lid: false)
            if state.sleepDisabledByHelper { setLidSleep(disabled: false) }
            save()
        }
    }
}

private final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    let daemon: BatteryCareDaemon
    init(daemon: BatteryCareDaemon) { self.daemon = daemon }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: BatteryCareXPCProtocol.self)
        connection.exportedObject = daemon
        connection.resume()
        return true
    }
}

/// Only the app may talk to the helper. A Developer ID build proves its team;
/// a build signed on this Mac can prove only its name, so the helper accepts
/// nothing but its fixed, bounded commands.
private func clientRequirement() -> String {
    var code: SecCode?
    var staticCode: SecStaticCode?
    var info: CFDictionary?
    if SecCodeCopySelf([], &code) == errSecSuccess, let code,
       SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
       SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
       let team = (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String, !team.isEmpty {
        return "anchor apple generic and certificate leaf[subject.OU] = \"\(team)\" and identifier \"\(BatteryCareIdentifiers.appBundleID)\""
    }
    return "identifier \"\(BatteryCareIdentifiers.appBundleID)\""
}

// MARK: Self-test

/// Runs the policy against made-up readings. It never reads or writes the
/// charging controller, so it is safe on any Mac.
private func selfTest() -> Bool {
    var failures = 0
    func check(_ condition: Bool, _ message: String) {
        if !condition { failures += 1; print("✗ \(message)") }
    }
    let caps = BatteryCareCapabilities(canPauseCharging: true, canDischarge: false, hasFirmwareLimit: true,
                                       hasMagSafeLED: false)
    var settings = BatteryCareSettings()
    settings.limit = 50
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    // This Mac on the day it was written: 89% reported, cells at 3.39 V, plugged in, not charging.
    let wrong = BatteryCareReading(percent: 89, hardwarePercent: 84, adapterConnected: true, isCharging: false,
                                   fullyCharged: false, temperature: 30, voltage: 10187,
                                   cellVoltages: [3386, 3415, 3387], amperage: -4)
    var memory = BatteryCareMemory()
    var decision = BatteryCarePolicy.decide(settings: settings, activity: .none, memory: &memory, reading: wrong,
                                            capabilities: caps, sleeping: false, now: start)
    check(!decision.allowCharging && decision.state == .paused, "holds above the limit at first")
    decision = BatteryCarePolicy.decide(settings: settings, activity: decision.activity, memory: &memory,
                                        reading: wrong, capabilities: caps, sleeping: false,
                                        now: start.addingTimeInterval(180))
    check(decision.allowCharging && decision.state == .fixingReading && decision.firmwareLimit == 100,
          "charges a battery whose cells are empty")
    var healthy = wrong
    healthy.cellVoltages = [4080, 4085, 4079]
    memory = BatteryCareMemory()
    decision = BatteryCarePolicy.decide(settings: settings, activity: .none, memory: &memory, reading: healthy,
                                        capabilities: caps, sleeping: false, now: start.addingTimeInterval(600))
    check(!decision.allowCharging && decision.events.isEmpty, "leaves a battery whose reading is right")
    return failures == 0
}

// MARK: Entry

let arguments = CommandLine.arguments
if arguments.contains("--selftest") {
    let passed = selfTest()
    print(passed ? "✓ battery helper self-test passed" : "✗ battery helper self-test failed")
    exit(passed ? 0 : 1)
}
if arguments.contains("--version") {
    print(BatteryCareIdentifiers.helperVersion)
    exit(0)
}
guard getuid() == 0 else {
    FileHandle.standardError.write(Data("The battery helper runs only as root, from launchd.\n".utf8))
    exit(1)
}

private let daemon = BatteryCareDaemon()
private let delegate = ListenerDelegate(daemon: daemon)
private let listener = NSXPCListener(machServiceName: BatteryCareIdentifiers.helperID)
listener.setConnectionCodeSigningRequirement(clientRequirement())
listener.delegate = delegate
daemon.start()
listener.resume()

signal(SIGTERM, SIG_IGN)
private let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
termination.setEventHandler {
    daemon.stop()
    exit(0)
}
termination.resume()
log.info("Battery Care helper started")
dispatchMain()
