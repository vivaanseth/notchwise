// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

/// whisper.cpp's own server, kept running while Whisper is in use so its
/// model loads once rather than on every pass, often enough to show the
/// words as they are said. It listens on this Mac only, stops after ten
/// idle minutes and with the app, and one a crash left behind is ended at
/// the next start.
@MainActor
final class VOWhisperServer {
    static let shared = VOWhisperServer()

    private var process: Process?
    private var port = 0
    private var model: URL?
    private var starting: Task<Bool, Never>?
    private var idle: DispatchWorkItem?
    private static let idleAfter: TimeInterval = 600
    private static let pidFile = VOStorage.directory.appendingPathComponent("whisper-server.pid")

    private init() {}

    /// Beside `whisper-cli`, as Homebrew installs them.
    static var binary: String? {
        guard let cli = VOWhisper.binary else { return nil }
        let real = URL(fileURLWithPath: cli).resolvingSymlinksInPath()
        let server = real.deletingLastPathComponent().appendingPathComponent("whisper-server").path
        return FileManager.default.isExecutableFile(atPath: server) ? server : nil
    }

    /// Starts the server with the chosen model, or keeps the one running.
    /// False when it cannot run; the caller falls back to `whisper-cli`.
    func prepare() async -> Bool {
        idle?.cancel()
        let wanted = VOWhisper.availableModel()
        if let process, process.isRunning, model == wanted { scheduleIdleStop(); return true }
        if let starting { return await starting.value }
        let task = Task { await launch(wanted) }
        starting = task
        let ok = await task.value
        starting = nil
        if ok { scheduleIdleStop() }
        return ok
    }

    func stop() {
        idle?.cancel()
        starting?.cancel()
        end()
    }

    private func end() {
        if let process, process.isRunning { process.terminate() }
        process = nil
        try? FileManager.default.removeItem(at: Self.pidFile)
    }

    /// The words in `wav` (16 kHz mono), heard with `fields`: the language,
    /// the names to listen for and how much of the audio window to use.
    func transcribe(wav: Data, fields: [String: String]) async throws -> String {
        guard await prepare() else { throw VOError("Whisper's server isn't available.") }
        let boundary = "VoiceOS-\(UUID().uuidString)"
        var body = Data()
        func add(_ text: String) { body.append(Data(text.utf8)) }
        for (name, value) in fields.sorted(by: { $0.key < $1.key }) {
            add("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
        }
        add("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"speech.wav\"\r\nContent-Type: audio/wav\r\n\r\n")
        body.append(wav)
        add("\r\n--\(boundary)--\r\n")
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/inference")!, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String else { throw VOError("Whisper's server didn't answer.") }
        scheduleIdleStop()
        return text
    }

    // MARK: Running it

    private func launch(_ wanted: URL?) async -> Bool {
        end()
        Self.endLeftover()
        guard let binary = Self.binary, let wanted else { return false }
        // A port nothing else holds; a clash shows as the server ending at once, and the next one is tried.
        for _ in 0..<3 {
            let port = Int.random(in: 49_152...64_000)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: binary)
            process.arguments = ["-m", wanted.path, "--host", "127.0.0.1", "--port", "\(port)",
                                 "-t", "\(max(2, ProcessInfo.processInfo.activeProcessorCount - 2))", "-nt",
                                 // Each pass hears its recording alone: the text of the one
                                 // before, which the server would carry over, slows the next.
                                 "-mc", "0"]
            process.environment = VOCLIRunner.cleanEnvironment
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice
            do { try process.run() } catch { return false }
            try? "\(process.processIdentifier)".write(to: Self.pidFile, atomically: true, encoding: .utf8)
            self.process = process
            self.port = port
            self.model = wanted
            if await answers(process, port: port) { return true }
            if process.isRunning { process.terminate() }
            self.process = nil
        }
        try? FileManager.default.removeItem(at: Self.pidFile)
        return false
    }

    /// Waits for the model to load, up to ten seconds.
    private func answers(_ process: Process, port: Int) async -> Bool {
        let url = URL(string: "http://127.0.0.1:\(port)/")!
        for _ in 0..<50 {
            guard process.isRunning, !Task.isCancelled else { return false }
            if let (_, response) = try? await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 1)),
               response is HTTPURLResponse { return true }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return false
    }

    private func scheduleIdleStop() {
        idle?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.stop() }
        idle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.idleAfter, execute: work)
    }

    /// A server the app started before it last quit unexpectedly, if that
    /// process is still a whisper-server.
    private static func endLeftover() {
        guard let text = try? String(contentsOf: pidFile, encoding: .utf8), let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              pid > 0 else { return }
        try? FileManager.default.removeItem(at: pidFile)
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard proc_pidpath(pid, &path, UInt32(path.count)) > 0,
              String(cString: path).hasSuffix("/whisper-server") else { return }
        kill(pid, SIGTERM)
    }
}
