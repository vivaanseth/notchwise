// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Ollama opens itself at login through its own launch agent. While the
/// assistant is off nothing here needs it, so the agent is switched off in
/// the person's own launchd domain (no administrator needed), and switched
/// back on when the assistant is, but only if this app switched it off.
enum VOOllamaLogin {
    static let label = "com.ollama.ollama"
    static let disabledKey = "voOllamaLoginDisabledByAssistant"

    static func sync(assistantOn: Bool, defaults: UserDefaults = .standard) {
        let ours = defaults.bool(forKey: disabledKey)
        if assistantOn {
            guard ours else { return }
            if launchctl("enable") { defaults.removeObject(forKey: disabledKey) }
        } else {
            guard !ours, isEnabled() == true else { return }
            if launchctl("disable") { defaults.set(true, forKey: disabledKey) }
        }
    }

    /// Whether launchd will start the agent at login; nil when it cannot say.
    static func isEnabled() -> Bool? {
        guard let output = run(["print-disabled", "gui/\(getuid())"]) else { return nil }
        guard let line = output.split(separator: "\n").first(where: { $0.contains("\"\(label)\"") }) else { return true }
        return !line.contains("disabled")
    }

    private static func launchctl(_ verb: String) -> Bool {
        run([verb, "gui/\(getuid())/\(label)"]) != nil
    }

    private static func run(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
    }
}
