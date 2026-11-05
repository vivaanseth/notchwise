// SPDX-License-Identifier: GPL-3.0-or-later
// Ported from VoiceOS Clone (AI/ClaudeWarmPool.swift) into Vorssaint + VoiceOS.

import Foundation

/// One `claude -p --input-format stream-json` process that has already booted and is waiting on stdin.
/// Writing a request to it skips the 2–4s CLI startup, so a reply arrives in well under a second.
final class VOClaudeProc: @unchecked Sendable {
    let process = Process()
    let born = Date()
    private let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
    private let lock = NSLock()
    private var lineBuf = Data()
    private var pending: [String] = []
    private var onLine: ((String) -> Void)?
    private var errData = Data()
    private var exitStatus: Int32?
    private var waiter: CheckedContinuation<Int32, Never>?

    init(executable: String, args: [String]) throws {
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.environment = VOCLIRunner.cleanEnvironment
        process.currentDirectoryURL = VOCLIRunner.scratchDirectory()
        process.standardInput = inPipe
        process.standardOutput = outPipe
        process.standardError = errPipe
        outPipe.fileHandleForReading.readabilityHandler = { [weak self] h in self?.ingest(h.availableData) }
        errPipe.fileHandleForReading.readabilityHandler = { [weak self] h in self?.appendErr(h.availableData) }
        process.terminationHandler = { [weak self] p in self?.finished(p.terminationStatus) }
        try process.run()
    }

    var isAlive: Bool { process.isRunning }
    var stderr: String { lock.lock(); defer { lock.unlock() }; return String(decoding: errData, as: UTF8.self) }

    func attach(_ handler: @escaping (String) -> Void) {
        lock.lock()
        onLine = handler
        let queued = pending
        pending.removeAll()
        lock.unlock()
        queued.forEach(handler)
    }

    func send(_ data: Data) {
        let fh = inPipe.fileHandleForWriting
        DispatchQueue.global().async {
            fh.write(data)
            try? fh.close()
        }
    }

    func waitForExit(timeout: TimeInterval) async -> (status: Int32, timedOut: Bool) {
        let flag = VOTimeoutFlag()
        let timer = DispatchWorkItem { [weak self] in
            flag.set()
            self?.kill()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
        let status = await withTaskCancellationHandler {
            await withCheckedContinuation { (c: CheckedContinuation<Int32, Never>) in
                lock.lock()
                if let s = exitStatus { lock.unlock(); c.resume(returning: s) } else { waiter = c; lock.unlock() }
            }
        } onCancel: { [weak self] in self?.kill() }
        timer.cancel()
        return (status, flag.value)
    }

    func kill() { if process.isRunning { process.terminate() } }

    private func ingest(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        lineBuf.append(data)
        var lines: [String] = []
        while let nl = lineBuf.firstIndex(of: 0x0A) {
            lines.append(String(decoding: lineBuf[lineBuf.startIndex..<nl], as: UTF8.self))
            lineBuf.removeSubrange(lineBuf.startIndex...nl)
        }
        let handler = onLine
        if handler == nil { pending += lines; lines.removeAll() }
        lock.unlock()
        lines.forEach { handler?($0) }
    }

    private func appendErr(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock(); errData.append(data); lock.unlock()
    }

    private func finished(_ status: Int32) {
        outPipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil
        ingest(outPipe.fileHandleForReading.readDataToEndOfFile())
        appendErr(errPipe.fileHandleForReading.readDataToEndOfFile())
        lock.lock()
        if !lineBuf.isEmpty {
            let rest = String(decoding: lineBuf, as: UTF8.self)
            lineBuf.removeAll()
            if onLine == nil { pending.append(rest) } else { let h = onLine; lock.unlock(); h?(rest); lock.lock() }
        }
        exitStatus = status
        let w = waiter
        waiter = nil
        lock.unlock()
        w?.resume(returning: status)
    }
}

private final class VOTimeoutFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    func set() { lock.lock(); fired = true; lock.unlock() }
    var value: Bool { lock.lock(); defer { lock.unlock() }; return fired }
}

/// Keeps at most one warm Claude process (≈350 MB) and retires it after 10 idle minutes.
final class VOClaudeWarmPool: @unchecked Sendable {
    static let shared = VOClaudeWarmPool()

    /// Every request carries its own <instructions>, so one warm process can serve dictation, edits and the agent.
    static let systemPrompt = "You are the AI engine inside Notchwise, a voice assistant for Mac. Each request begins with <instructions> that define your role and exact output format for that request. Follow them precisely and output nothing else."

    private let lock = NSLock()
    private var warm: VOClaudeProc?
    private var warmModel = ""
    private var expiry: DispatchWorkItem?

    static func args(model: String) -> [String] {
        var a = ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose", "--include-partial-messages",
                 "--setting-sources", "", "--settings", #"{"alwaysThinkingEnabled":false}"#,
                 "--strict-mcp-config", "--tools", "", "--no-session-persistence",
                 "--system-prompt", systemPrompt]
        if !model.isEmpty { a += ["--model", model] }
        return a
    }

    func take(model: String) -> VOClaudeProc? {
        lock.lock(); defer { lock.unlock() }
        guard let w = warm else { return nil }
        warm = nil
        expiry?.cancel()
        guard w.isAlive, warmModel == model, Date().timeIntervalSince(w.born) < 600 else { w.kill(); return nil }
        return w
    }

    func prewarm(executable: String, model: String) {
        lock.lock(); defer { lock.unlock() }
        if let w = warm, w.isAlive, warmModel == model { return }
        warm?.kill()
        warm = try? VOClaudeProc(executable: executable, args: Self.args(model: model))
        warmModel = model
        expiry?.cancel()
        let e = DispatchWorkItem { [weak self] in self?.drain() }
        expiry = e
        DispatchQueue.global().asyncAfter(deadline: .now() + 600, execute: e)
    }

    func drain() {
        lock.lock(); defer { lock.unlock() }
        warm?.kill()
        warm = nil
        expiry?.cancel()
    }
}
