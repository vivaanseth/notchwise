// SPDX-License-Identifier: GPL-3.0-or-later
// Ported from VoiceOS Clone (AI/CLIRunner.swift) into Vorssaint + VoiceOS.

import Foundation

struct VOCLIResult {
    let stdout: String
    let stderr: String
    let status: Int32
    let timedOut: Bool
}

/// Runs the provider CLIs (claude / codex / gemini) the same way a terminal would, so they use
/// the user's own signed-in subscription instead of an API key.
enum VOCLIRunner {
    /// PATH from the user's login shell, captured once. Falls back to the usual install locations.
    private static let shellPath: String = {
        let home = NSHomeDirectory()
        var parts = ["\(home)/.local/bin", "\(home)/.npm-global/bin", "\(home)/.bun/bin", "\(home)/.volta/bin",
                     "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        let nvm = "\(home)/.nvm/versions/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvm) {
            parts += versions.sorted().reversed().map { "\(nvm)/\($0)/bin" }
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-ilc", "printf '__PATH__%s' \"$PATH\""]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        if (try? p.run()) != nil {
            let deadline = Date().addingTimeInterval(4)
            while p.isRunning && Date() < deadline { usleep(20_000) }
            if p.isRunning { p.terminate() }
            let s = String(data: out.fileHandleForReading.availableData, encoding: .utf8) ?? ""
            if let r = s.range(of: "__PATH__") {
                let shell = s[r.upperBound...].split(separator: ":").map(String.init)
                parts = shell + parts
            }
        }
        var seen = Set<String>()
        return parts.filter { !$0.isEmpty && seen.insert($0).inserted }.joined(separator: ":")
    }()

    /// A minimal environment: no inherited API keys or host-app variables, so each CLI falls back
    /// to its own OAuth / subscription login.
    static var cleanEnvironment: [String: String] {
        let src = ProcessInfo.processInfo.environment
        var env: [String: String] = [:]
        for key in ["HOME", "USER", "LOGNAME", "SHELL", "TMPDIR", "LANG", "LC_ALL", "LC_CTYPE", "SSH_AUTH_SOCK",
                    "XDG_CONFIG_HOME", "CODEX_HOME", "NVM_DIR", "__CF_USER_TEXT_ENCODING"] {
            if let v = src[key] { env[key] = v }
        }
        env["HOME"] = env["HOME"] ?? NSHomeDirectory()
        env["USER"] = env["USER"] ?? NSUserName()
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        env["PATH"] = shellPath
        env["TERM"] = "dumb"
        env["NO_COLOR"] = "1"
        env["FORCE_COLOR"] = "0"
        env["MAX_THINKING_TOKENS"] = "0"   // Claude Code: no extended thinking for quick voice turns
        return env
    }

    static func warmUp() { DispatchQueue.global(qos: .utility).async { _ = shellPath } }

    private static let debugLock = NSLock()
    static func debug(_ line: String, to path: String) {
        debugLock.lock(); defer { debugLock.unlock() }
        let data = Data((line + "\n").utf8)
        if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write(data); try? h.close() }
        else { try? data.write(to: URL(fileURLWithPath: path)) }
    }

    static func resolve(_ name: String) -> String? {
        for dir in shellPath.split(separator: ":") {
            let path = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    static func scratchDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("VoiceOS-cli", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Runs a process, streaming stdout line by line to `onLine`.
    static func run(_ executable: String, _ args: [String], stdin: Data? = nil, cwd: URL? = nil,
                    timeout: TimeInterval = 60, onLine: ((String) -> Void)? = nil) async throws -> VOCLIResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.environment = cleanEnvironment
        process.currentDirectoryURL = cwd ?? scratchDirectory()

        let outPipe = Pipe(), errPipe = Pipe(), inPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = stdin == nil ? FileHandle.nullDevice : inPipe

        let started = Date()
        let debugLog = ProcessInfo.processInfo.environment["VOICEOS_DEBUG_LOG"]
        let tag = ([URL(fileURLWithPath: executable).lastPathComponent] + args.prefix(3)).joined(separator: " ")
        let collector = VOOutputCollector(onLine: debugLog == nil ? onLine : { line in
            Self.debug("+\(String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), Date().timeIntervalSince(started)))s \(tag) │ \(line.prefix(140))", to: debugLog!)
            onLine?(line)
        })
        outPipe.fileHandleForReading.readabilityHandler = { h in
            let data = h.availableData
            if !data.isEmpty { collector.appendOut(data) }
        }
        errPipe.fileHandleForReading.readabilityHandler = { h in
            let data = h.availableData
            if !data.isEmpty { collector.appendErr(data) }
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<VOCLIResult, Error>) in
                let timer = DispatchWorkItem { [weak process] in
                    collector.markTimedOut()
                    process?.terminate()
                }
                process.terminationHandler = { p in
                    timer.cancel()
                    outPipe.fileHandleForReading.readabilityHandler = nil
                    errPipe.fileHandleForReading.readabilityHandler = nil
                    collector.appendOut(outPipe.fileHandleForReading.readDataToEndOfFile())
                    collector.appendErr(errPipe.fileHandleForReading.readDataToEndOfFile())
                    collector.flush()
                    if let debugLog {
                        Self.debug("=\(String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), Date().timeIntervalSince(started)))s \(tag) exit \(p.terminationStatus)", to: debugLog)
                    }
                    cont.resume(returning: VOCLIResult(stdout: collector.out, stderr: collector.err,
                                                     status: p.terminationStatus, timedOut: collector.timedOut))
                }
                do {
                    try process.run()
                } catch {
                    cont.resume(throwing: VOError("Couldn't launch \(executable): \(error.localizedDescription)"))
                    return
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
                if let stdin {
                    DispatchQueue.global().async {
                        inPipe.fileHandleForWriting.write(stdin)
                        try? inPipe.fileHandleForWriting.close()
                    }
                }
            }
        } onCancel: {
            process.terminate()
        }
    }
}

/// Thread-safe accumulator that also splits stdout into lines as they arrive.
private final class VOOutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var outData = Data()
    private var errData = Data()
    private var lineBuffer = Data()
    private(set) var timedOut = false
    private let onLine: ((String) -> Void)?

    init(onLine: ((String) -> Void)?) { self.onLine = onLine }

    var out: String { lock.lock(); defer { lock.unlock() }; return String(decoding: outData, as: UTF8.self) }
    var err: String { lock.lock(); defer { lock.unlock() }; return String(decoding: errData, as: UTF8.self) }

    func markTimedOut() { lock.lock(); timedOut = true; lock.unlock() }

    func appendOut(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        outData.append(data)
        var lines: [String] = []
        if onLine != nil {
            lineBuffer.append(data)
            while let nl = lineBuffer.firstIndex(of: 0x0A) {
                let lineData = lineBuffer[lineBuffer.startIndex..<nl]
                lines.append(String(decoding: lineData, as: UTF8.self))
                lineBuffer.removeSubrange(lineBuffer.startIndex...nl)
            }
        }
        lock.unlock()
        lines.forEach { onLine?($0) }
    }

    func appendErr(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock(); errData.append(data); lock.unlock()
    }

    func flush() {
        lock.lock()
        let rest = lineBuffer.isEmpty ? nil : String(decoding: lineBuffer, as: UTF8.self)
        lineBuffer.removeAll()
        lock.unlock()
        if let rest { onLine?(rest) }
    }
}
