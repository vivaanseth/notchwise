// SPDX-License-Identifier: GPL-3.0-or-later
// Ported from VoiceOS Clone (Speech/Transcriber.swift) into Vorssaint + VoiceOS.

import Foundation
import Speech
import AVFoundation

/// A single listening session: starts the mic, streams partial text (Apple engine), and produces a
/// final transcript when stopped. Everything here runs on this Mac.
@MainActor
final class VOSpeechSession {
    private let capture = VOAudioCapture()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var latest = ""
    private var finalContinuation: CheckedContinuation<String, Never>?
    private let engine: VOSpeechEngine

    var onPartial: ((String) -> Void)?
    var onLevel: ((Float) -> Void)?

    init(engine: VOSpeechEngine) { self.engine = engine }

    func start() throws {
        let settings = VOSettings.shared
        latest = ""
        if engine == .apple {
            let locale = Locale(identifier: settings.languageCode)
            guard let rec = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")) else {
                throw VOError("Speech recognition isn't available for \(settings.languageCode).")
            }
            recognizer = rec
            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            req.addsPunctuation = true
            if rec.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
            req.contextualStrings = settings.dictionary.map(\.written)
            request = req
            task = rec.recognitionTask(with: req) { [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let isFinal = result?.isFinal ?? false
                Task { @MainActor in
                    guard let self else { return }
                    if let text { self.latest = text; self.onPartial?(text) }
                    if isFinal || error != nil { self.finish() }
                }
            }
            capture.onBuffer = { [weak req] buffer in req?.append(buffer) }
        } else {
            capture.onBuffer = nil
        }
        capture.onLevel = { [weak self] level in
            Task { @MainActor in self?.onLevel?(level) }
        }
        try capture.start(deviceUID: settings.microphoneUID)
    }

    /// Stops listening and returns (transcript, seconds spoken).
    func stop() async -> (text: String, duration: Double) {
        let (samples, duration) = capture.stop()
        switch engine {
        case .apple:
            request?.endAudio()
            let text = await withCheckedContinuation { (c: CheckedContinuation<String, Never>) in
                finalContinuation = c
                // Don't wait forever for the recognizer's final pass.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in self?.finish() }
            }
            task?.cancel()
            return (text, duration)
        case .whisper:
            guard duration > 0.3 else { return ("", duration) }
            do {
                let text = try await VOWhisper.transcribe(samples)
                return (text, duration)
            } catch {
                return ("", duration)
            }
        }
    }

    func cancel() {
        capture.stop()
        task?.cancel()
        finish()
    }

    private func finish() {
        guard let c = finalContinuation else { return }
        finalContinuation = nil
        c.resume(returning: latest)
    }
}

/// whisper.cpp via the `whisper-cli` binary (Homebrew: `brew install whisper-cpp`).
enum VOWhisper {
    static var binary: String? {
        for p in ["/usr/local/bin/whisper-cli", "/opt/homebrew/bin/whisper-cli"] where FileManager.default.isExecutableFile(atPath: p) {
            return p
        }
        return VOCLIRunner.resolve("whisper-cli")
    }

    static func modelURL(_ m: VOWhisperModel) -> URL? {
        let candidates = [VOStorage.modelsDirectory.appendingPathComponent(m.fileName),
                          URL(fileURLWithPath: "/usr/local/share/whisper-cpp/\(m.fileName)"),
                          URL(fileURLWithPath: "/opt/homebrew/share/whisper-cpp/\(m.fileName)"),
                          URL(fileURLWithPath: NSHomeDirectory() + "/.cache/whisper/\(m.fileName)")]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func transcribe(_ samples: [Float]) async throws -> String {
        let settings = VOSettings.shared
        guard let bin = binary else { throw VOError("whisper-cli not found. Install with: brew install whisper-cpp") }
        guard let model = modelURL(settings.whisperModel) else { throw VOError("Download a Whisper model in Dictation settings.") }
        let wav = VOCLIRunner.scratchDirectory().appendingPathComponent("dictation-\(UUID().uuidString).wav")
        try VOAudioCapture.writeWAV(samples, to: wav)
        defer { try? FileManager.default.removeItem(at: wav) }
        let lang = settings.whisperModel.rawValue.hasSuffix(".en") ? "en" : String(settings.languageCode.prefix(2))
        let threads = max(2, ProcessInfo.processInfo.activeProcessorCount - 1)
        var args = ["-m", model.path, "-f", wav.path, "-l", lang, "-nt", "-np", "-t", "\(threads)"]
        let prompt = settings.dictionary.map(\.written).joined(separator: ", ")
        if !prompt.isEmpty { args += ["--prompt", prompt] }
        let r = try await VOCLIRunner.run(bin, args, timeout: 120)
        return r.stdout
            .replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
            .split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Downloads ggml VOWhisper models into Application Support.
@MainActor
final class VOModelDownloader: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = VOModelDownloader()
    @Published var progress: [VOWhisperModel: Double] = [:]
    @Published var errors: [VOWhisperModel: String] = [:]
    private var tasks: [Int: VOWhisperModel] = [:]
    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)

    func download(_ m: VOWhisperModel) {
        guard progress[m] == nil else { return }
        errors[m] = nil
        progress[m] = 0
        let t = session.downloadTask(with: m.downloadURL)
        tasks[t.taskIdentifier] = m
        t.resume()
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64,
                                totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let id = downloadTask.taskIdentifier
        let frac = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0
        MainActor.assumeIsolated {
            if let m = tasks[id] { progress[m] = frac }
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let id = downloadTask.taskIdentifier
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        // Move synchronously before the temp file is deleted.
        let staged = FileManager.default.temporaryDirectory.appendingPathComponent("whisper-\(id).bin")
        try? FileManager.default.removeItem(at: staged)
        try? FileManager.default.moveItem(at: location, to: staged)
        MainActor.assumeIsolated {
            guard let m = tasks[id] else { return }
            if status == 200 {
                let dest = VOStorage.modelsDirectory.appendingPathComponent(m.fileName)
                try? FileManager.default.removeItem(at: dest)
                do { try FileManager.default.moveItem(at: staged, to: dest) } catch { errors[m] = error.localizedDescription }
            } else {
                errors[m] = "Download failed (HTTP \(status))"
            }
            progress[m] = nil
            tasks[id] = nil
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let id = task.taskIdentifier
        MainActor.assumeIsolated {
            if let m = tasks[id] { errors[m] = error.localizedDescription; progress[m] = nil; tasks[id] = nil }
        }
    }
}
