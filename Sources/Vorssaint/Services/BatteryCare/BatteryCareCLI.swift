// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Battery Care for Shortcuts: the app's own binary answers
/// `VorssaintVoiceOS battery <command>` and exits, so a Run Shell Script
/// action can read the battery or change charging without the app's window.
enum BatteryCareCLI {
    static let commands: [(command: String, summary: String)] = [
        ("percent", "Battery percentage macOS shows"),
        ("limit", "Charge limit"),
        ("state", "What Battery Care is doing"),
        ("temperature", "Battery temperature in °C"),
        ("set-limit 80", "Set the charge limit"),
        ("pause", "Pause charging at the current charge"),
        ("top-up", "Charge to 100% once (top-up off ends it)"),
        ("discharge 60", "Run on battery down to a charge"),
        ("calibrate", "Start Calibration"),
        ("stop", "Stop a discharge or calibration"),
        ("led green", "MagSafe light: green, orange, off or system"),
        ("low-power on", "Low Power Mode on or off"),
    ]

    static func runIfRequestedAndExit() {
        let arguments = CommandLine.arguments
        guard arguments.count >= 2, arguments[1] == "battery" else { return }
        exit(run(Array(arguments.dropFirst(2))))
    }

    static func shellCommand(_ command: String) -> String {
        let binary = Bundle.main.executablePath ?? "/Applications/Notchwise.app/Contents/MacOS/VorssaintVoiceOS"
        return "\(BatteryCareInstaller.quoted(binary)) battery \(command)"
    }

    private static func run(_ arguments: [String]) -> Int32 {
        guard let name = arguments.first else { return usage() }
        let value = arguments.dropFirst().first
        switch name {
        case "percent":
            guard let reading = BatteryCareReader.read() else { return fail("No battery.") }
            print(reading.percent)
        case "temperature":
            guard let temperature = BatteryCareReader.read()?.temperature else { return fail("No reading.") }
            print(String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), temperature))
        case "limit":
            print(call(nil)?.settings.limit ?? savedSettings().limit)
        case "state":
            guard let status = call(nil) else { return fail("Battery Care's helper isn't running.") }
            print(status.state.rawValue)
        case "set-limit":
            guard let percent = value.flatMap(Int.init) else { return usage() }
            return apply { $0.limit = percent }
        case "pause":
            guard let percent = BatteryCareReader.read()?.percent else { return fail("No battery.") }
            return apply { $0.limit = percent }
        case "top-up":
            return send(.topUp(value != "off"))
        case "discharge":
            let target = value.flatMap(Int.init) ?? call(nil)?.settings.limit ?? savedSettings().limit
            return send(.discharge(target: target))
        case "calibrate":
            return send(.calibrate)
        case "stop":
            return send(.stop)
        case "led":
            guard let color = value.flatMap(BatteryLEDColor.init(rawValue:)) else { return usage() }
            return send(.led(color))
        case "low-power":
            guard value == "on" || value == "off" else { return usage() }
            return send(.lowPowerMode(value == "on"))
        default:
            return usage()
        }
        return 0
    }

    private static func apply(_ change: (inout BatteryCareSettings) -> Void) -> Int32 {
        guard let status = call(nil) else { return fail("Battery Care's helper isn't running.") }
        var settings = status.settings
        change(&settings)
        settings = settings.validated()
        // The app reads the same choices, so it shows this change too.
        UserDefaults.standard.set(String(decoding: BatteryCareIPC.encode(settings), as: UTF8.self),
                                  forKey: DefaultsKey.batteryCareSettings)
        return send(.apply(settings))
    }

    private static func send(_ command: BatteryCareCommand) -> Int32 {
        call(command) == nil ? fail("Battery Care's helper isn't running.") : 0
    }

    private static func call(_ command: BatteryCareCommand?) -> BatteryCareStatus? {
        let connection = NSXPCConnection(machServiceName: BatteryCareIdentifiers.helperID, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: BatteryCareXPCProtocol.self)
        connection.setCodeSigningRequirement("identifier \"\(BatteryCareIdentifiers.helperID)\"")
        connection.resume()
        defer { connection.invalidate() }
        let done = DispatchSemaphore(value: 0)
        var result: BatteryCareStatus?
        let proxy = connection.remoteObjectProxyWithErrorHandler { _ in done.signal() } as? BatteryCareXPCProtocol
        let reply: (Data) -> Void = { data in
            result = BatteryCareIPC.decode(BatteryCareStatus.self, from: data)
            done.signal()
        }
        if let command { proxy?.perform(BatteryCareIPC.encode(command), withReply: reply) } else {
            proxy?.status(withReply: reply)
        }
        guard proxy != nil, done.wait(timeout: .now() + 5) == .success else { return nil }
        return result
    }

    private static func savedSettings() -> BatteryCareSettings {
        guard let text = UserDefaults.standard.string(forKey: DefaultsKey.batteryCareSettings), !text.isEmpty else {
            return BatteryCareSettings()
        }
        return BatteryCareIPC.decode(BatteryCareSettings.self, from: Data(text.utf8)) ?? BatteryCareSettings()
    }

    private static func usage() -> Int32 {
        var text = "Usage: VorssaintVoiceOS battery <command>\n"
        for entry in commands { text += "  \(entry.command.padding(toLength: 14, withPad: " ", startingAt: 0))\(entry.summary)\n" }
        FileHandle.standardError.write(Data(text.utf8))
        return 2
    }

    private static func fail(_ message: String) -> Int32 {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        return 1
    }
}
