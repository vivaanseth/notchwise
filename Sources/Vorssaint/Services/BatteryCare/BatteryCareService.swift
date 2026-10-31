// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

/// Battery Care in the app: it reads the battery itself, asks the root helper
/// for what it is doing, sends the person's choices, runs the schedule and
/// tells what happened. The helper keeps the limit when the app is closed.
@MainActor
final class BatteryCareService: ObservableObject {
    static let shared = BatteryCareService()

    enum HelperState: Equatable {
        case notInstalled, outdated, running, unreachable
    }

    @Published private(set) var reading: BatteryCareReading?
    @Published private(set) var status: BatteryCareStatus?
    @Published private(set) var helperState: HelperState = .notInstalled
    @Published private(set) var capabilities: BatteryCareCapabilities
    @Published private(set) var settings: BatteryCareSettings
    @Published private(set) var isInstalling = false
    @Published private(set) var message: String?
    @Published private(set) var otherLimiter: NSRunningApplication?
    @Published private(set) var tasks: [BatteryScheduleTask]
    @Published private(set) var history: [BatteryScheduleRun]
    @Published private(set) var energyApps: [ProcessUsage] = []
    /// The last time the battery could not keep the Mac running, and at what charge.
    @Published private(set) var weakBattery: (date: Date, percent: Int)?

    private var connection: NSXPCConnection?
    private var timer: Timer?
    private var viewers = 0
    private var started = false
    private var pendingPushes = 0
    private var sleepControlStartedHere = false
    private var lastEnergyRefresh = Date.distantPast
    private var wakeObserver: NSObjectProtocol?

    private init() {
        capabilities = BatteryCareHardware()?.capabilities ?? BatteryCareCapabilities()
        settings = Self.savedSettings()
        tasks = Self.decode([BatteryScheduleTask].self, key: DefaultsKey.batteryCareSchedule) ?? []
        history = Self.decode([BatteryScheduleRun].self, key: DefaultsKey.batteryCareScheduleHistory) ?? []
    }

    static var isSupported: Bool { PowerSampler.hasInternalBattery }

    var helperInstalled: Bool {
        FileManager.default.fileExists(atPath: BatteryCareIdentifiers.launchDaemon)
    }

    var state: BatteryCareState {
        guard helperState == .running, let status else {
            guard let reading else { return .off }
            return reading.adapterConnected ? (reading.isCharging ? .charging : .paused) : .onBattery
        }
        return status.state
    }

    var activity: BatteryCareActivity { status?.activity ?? .none }

    // MARK: Lifecycle

    func start() {
        guard Self.isSupported, !started else { return }
        started = true
        importAlDenteOnce()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        refresh()
        rescheduleTimer()
    }

    func viewAppeared() {
        viewers += 1
        refresh()
        rescheduleTimer()
    }

    func viewDisappeared() {
        viewers = max(0, viewers - 1)
        rescheduleTimer()
    }

    private func rescheduleTimer() {
        timer?.invalidate()
        guard Self.isSupported else { return }
        let interval: TimeInterval = viewers > 0 ? 3 : 30
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer?.tolerance = interval / 4
    }

    func refresh() {
        reading = BatteryCareReader.read()
        otherLimiter = NSWorkspace.shared.runningApplications.first {
            ($0.bundleIdentifier ?? "").hasPrefix("com.apphousekitchen.aldente")
        }
        if helperInstalled {
            requestStatus()
        } else {
            helperState = .notInstalled
            status = nil
        }
        runDueTasks()
        endSleepControlIfUnplugged()
        if viewers > 0, Date().timeIntervalSince(lastEnergyRefresh) >= 10 { refreshEnergyApps() }
    }

    // MARK: The helper

    private func proxy(onFailure: @escaping @MainActor () -> Void) -> BatteryCareXPCProtocol? {
        if connection == nil {
            let connection = NSXPCConnection(machServiceName: BatteryCareIdentifiers.helperID, options: .privileged)
            connection.remoteObjectInterface = NSXPCInterface(with: BatteryCareXPCProtocol.self)
            connection.setCodeSigningRequirement("identifier \"\(BatteryCareIdentifiers.helperID)\"")
            connection.invalidationHandler = { [weak self] in
                Task { @MainActor in self?.connection = nil }
            }
            connection.resume()
            self.connection = connection
        }
        return connection?.remoteObjectProxyWithErrorHandler { _ in
            Task { @MainActor in onFailure() }
        } as? BatteryCareXPCProtocol
    }

    private func requestStatus() {
        proxy { [weak self] in self?.helperDidFail() }?.status { data in
            let status = BatteryCareIPC.decode(BatteryCareStatus.self, from: data)
            Task { @MainActor in self.receive(status, pushed: false) }
        }
    }

    private func send(_ command: BatteryCareCommand) {
        guard helperInstalled else { return }
        let isPush: Bool
        if case .apply = command { isPush = true } else { isPush = false }
        if isPush { pendingPushes += 1 }
        let failed: @MainActor () -> Void = { [weak self] in
            if isPush { self?.pendingPushes = max(0, (self?.pendingPushes ?? 1) - 1) }
            self?.helperDidFail()
        }
        proxy(onFailure: failed)?.perform(BatteryCareIPC.encode(command)) { data in
            let status = BatteryCareIPC.decode(BatteryCareStatus.self, from: data)
            Task { @MainActor in
                if isPush { self.pendingPushes = max(0, self.pendingPushes - 1) }
                self.receive(status, pushed: isPush)
            }
        }
    }

    private func helperDidFail() {
        connection?.invalidate()
        connection = nil
        helperState = helperInstalled ? .unreachable : .notInstalled
    }

    private func receive(_ status: BatteryCareStatus?, pushed: Bool) {
        guard let status else { helperDidFail(); return }
        let firstContact = self.status == nil
        self.status = status
        capabilities = status.capabilities
        if let reading = status.reading { self.reading = reading }
        helperState = status.helperVersion < BatteryCareIdentifiers.helperVersion ? .outdated : .running
        if pendingPushes == 0 {
            if firstContact, !pushed, status.settings == BatteryCareSettings(), status.settings != settings {
                // A freshly installed helper starts from the choices made in the app.
                send(.apply(settings))
            } else if status.settings != settings {
                settings = status.settings
                save(settings)
            }
        }
        tell(status.events)
    }

    // MARK: Choices and actions

    func update(_ change: (inout BatteryCareSettings) -> Void) {
        var next = settings
        change(&next)
        next = next.validated()
        guard next != settings else { return }
        settings = next
        save(next)
        send(.apply(next))
    }

    func discharge(to target: Int? = nil) { send(.discharge(target: target ?? settings.limit)) }
    func stopActivity() { send(.stop) }
    func topUp(_ on: Bool) { send(.topUp(on)) }
    func calibrate() { send(.calibrate) }
    func fixReading() { send(.fixReading) }
    func setLED(_ color: BatteryLEDColor) { send(.led(color)) }
    func setLowPowerMode(_ on: Bool) { send(.lowPowerMode(on)) }

    /// AlDente's Pause Charging: the limit becomes the charge right now.
    func pauseHere() {
        guard let percent = reading?.percent else { return }
        update { $0.limit = percent }
        if case .discharge = activity { stopActivity() }
    }

    func quitOtherLimiter() {
        otherLimiter?.terminate()
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            self?.refresh()
        }
    }

    // MARK: Installing

    func installHelper() {
        guard !isInstalling else { return }
        let source = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LaunchServices/\(BatteryCareIdentifiers.helperID)")
        guard FileManager.default.isExecutableFile(atPath: source.path) else {
            message = FeatureStrings.batteryCare(L10n.shared.language).installFailed
            return
        }
        isInstalling = true
        message = nil
        let strings = FeatureStrings.batteryCare(L10n.shared.language)
        AdminShell.run(BatteryCareInstaller.installCommand(helper: source.path),
                       prompt: "\(strings.title): \(strings.installHelper)") { ok in
            Task { @MainActor in
                self.isInstalling = false
                self.connection?.invalidate()
                self.connection = nil
                if !ok { self.message = strings.installFailed }
                // launchd starts the helper a moment later.
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                self.status = nil
                self.refresh()
                if ok { self.send(.apply(self.settings)) }
            }
        }
    }

    func removeHelper() {
        guard !isInstalling else { return }
        isInstalling = true
        let strings = FeatureStrings.batteryCare(L10n.shared.language)
        AdminShell.run(BatteryCareInstaller.removeCommand(),
                       prompt: "\(strings.title): \(strings.removeHelper)") { _ in
            Task { @MainActor in
                self.isInstalling = false
                self.connection?.invalidate()
                self.connection = nil
                self.status = nil
                self.refresh()
            }
        }
    }

    // MARK: Notifications

    private func tell(_ events: [BatteryCareStatusEvent]) {
        let defaults = UserDefaults.standard
        var last = defaults.integer(forKey: DefaultsKey.batteryCareLastEventSerial)
        let newest = events.map(\.serial).max() ?? 0
        // A reinstalled helper counts from one again.
        if newest < last { last = 0 }
        for event in events where event.serial > last {
            if event.event == .weakBattery { weakBattery = (event.date, event.percent) }
            // Only news: nothing older than ten minutes, as after a restart.
            guard defaults.bool(forKey: DefaultsKey.batteryCareNotifications),
                  Date().timeIntervalSince(event.date) < 600 else { continue }
            Notifier.post(title: FeatureStrings.batteryCare(L10n.shared.language).title,
                          body: Self.text(for: event))
        }
        if newest != last { defaults.set(newest, forKey: DefaultsKey.batteryCareLastEventSerial) }
    }

    static func text(for event: BatteryCareStatusEvent) -> String {
        let s = FeatureStrings.batteryCare(L10n.shared.language)
        switch event.event {
        case .limitReached: return String(format: s.notifyLimitFormat, event.percent)
        case .dischargeFinished: return String(format: s.notifyDischargeFormat, event.percent)
        case .dischargeStoppedLowVoltage: return String(format: s.notifyDischargeStoppedFormat, event.percent)
        case .calibrationFinished: return s.notifyCalibration
        case .readingFixStarted: return s.notifyFixStarted
        case .readingFixFinished: return s.notifyFixFinished
        case .heatPaused: return s.notifyHeat
        case .weakBattery: return String(format: s.notifyWeakFormat, event.percent)
        }
    }

    // MARK: Schedule

    func addTask(_ task: BatteryScheduleTask) {
        tasks.append(task)
        saveTasks()
    }

    func updateTask(_ task: BatteryScheduleTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index] = task
        saveTasks()
    }

    func removeTask(_ id: UUID) {
        tasks.removeAll { $0.id == id }
        saveTasks()
    }

    private func runDueTasks() {
        let now = Date()
        let catchUp = UserDefaults.standard.bool(forKey: DefaultsKey.batteryCareCatchUp)
        var changed = false
        for index in tasks.indices {
            guard let due = BatteryScheduleSupport.dueOccurrence(of: tasks[index], now: now, catchUp: catchUp) else {
                continue
            }
            perform(tasks[index].action)
            tasks[index].lastRun = now
            history.insert(BatteryScheduleRun(taskID: tasks[index].id, action: tasks[index].action, date: now,
                                              caughtUp: now.timeIntervalSince(due) > BatteryScheduleSupport.onTimeGrace),
                           at: 0)
            changed = true
        }
        guard changed else { return }
        history = Array(history.prefix(30))
        saveTasks()
        UserDefaults.standard.set(Self.encode(history), forKey: DefaultsKey.batteryCareScheduleHistory)
    }

    func perform(_ action: BatteryScheduleAction) {
        switch action {
        case .setLimit(let percent):
            update { $0.limit = percent }
        case .calibrate:
            calibrate()
        case .topUp:
            topUp(true)
        case .pauseCharging:
            pauseHere()
        case .dischargeTo(let percent):
            update { $0.limit = percent }
            if let current = reading?.percent, current > percent { discharge(to: percent) }
        case .lowPowerOn:
            setLowPowerMode(true)
        case .lowPowerOff:
            setLowPowerMode(false)
        }
    }

    private func saveTasks() {
        UserDefaults.standard.set(Self.encode(tasks), forKey: DefaultsKey.batteryCareSchedule)
    }

    // MARK: Sleep control

    func keepAwake(minutes: Int) {
        sleepControlStartedHere = true
        KeepAwakeManager.shared.activate(minutes: minutes)
    }

    func letSleep() {
        sleepControlStartedHere = false
        KeepAwakeManager.shared.deactivate(reason: .manual)
    }

    private func endSleepControlIfUnplugged() {
        guard sleepControlStartedHere, KeepAwakeManager.shared.isActive else {
            sleepControlStartedHere = sleepControlStartedHere && KeepAwakeManager.shared.isActive
            return
        }
        guard UserDefaults.standard.bool(forKey: DefaultsKey.batteryCareSleepStopUnplugged),
              let reading, !reading.adapterConnected else { return }
        letSleep()
    }

    // MARK: Energy

    private func refreshEnergyApps() {
        lastEnergyRefresh = Date()
        let cpu = SystemMonitor.shared.snapshot.cpuUsage.map { $0 * 100 }
        let gpu = SystemMonitor.shared.snapshot.gpuUsage.map { $0 * 100 }
        DispatchQueue.global(qos: .utility).async {
            let rows = ProcessUsageService.shared.top(.energy, limit: 12, sampleInterval: 2,
                                                      cpuPercentage: cpu, gpuPercentage: gpu)
            Task { @MainActor in
                // Apps only: background processes rarely quit safely.
                self.energyApps = Array(rows.filter { row in
                    row.value >= 2 && NSRunningApplication(processIdentifier: row.pid)?.activationPolicy == .regular
                }.prefix(5))
            }
        }
    }

    func quitApp(_ pid: pid_t) {
        NSRunningApplication(processIdentifier: pid)?.terminate()
        energyApps.removeAll { $0.pid == pid }
    }

    // MARK: Saving

    private func save(_ settings: BatteryCareSettings) {
        UserDefaults.standard.set(Self.encode(settings), forKey: DefaultsKey.batteryCareSettings)
    }

    private static func savedSettings() -> BatteryCareSettings {
        decode(BatteryCareSettings.self, key: DefaultsKey.batteryCareSettings) ?? BatteryCareSettings()
    }

    private static func encode<T: Encodable>(_ value: T) -> String {
        String(decoding: BatteryCareIPC.encode(value), as: UTF8.self)
    }

    private static func decode<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let text = UserDefaults.standard.string(forKey: key), !text.isEmpty else { return nil }
        return BatteryCareIPC.decode(type, from: Data(text.utf8))
    }

    /// Starts from AlDente's choices once, so replacing it keeps the limit
    /// and modes the person picked there.
    private func importAlDenteOnce() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: DefaultsKey.batteryCareImportedAlDente) else { return }
        defaults.set(true, forKey: DefaultsKey.batteryCareImportedAlDente)
        guard (defaults.string(forKey: DefaultsKey.batteryCareSettings) ?? "").isEmpty else { return }
        for domain in ["com.apphousekitchen.aldente-pro", "com.apphousekitchen.aldente"] {
            guard let aldente = UserDefaults(suiteName: domain),
                  let limit = aldente.object(forKey: "chargeVal") as? Int else { continue }
            var imported = BatteryCareSettings()
            imported.limit = limit
            imported.sailing = aldente.bool(forKey: "sailingMode")
            imported.heatProtection = aldente.bool(forKey: "heatProtectMode")
            imported.automaticDischarge = aldente.bool(forKey: "automaticDischarge")
            imported.stopChargingWhenSleeping = aldente.bool(forKey: "sleepInhibitCharge")
            settings = imported.validated()
            save(settings)
            return
        }
    }
}
