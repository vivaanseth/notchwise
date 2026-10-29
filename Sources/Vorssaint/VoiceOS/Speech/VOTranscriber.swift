// SPDX-License-Identifier: GPL-3.0-or-later
// Ported from VoiceOS Clone (Speech/Transcriber.swift) into Vorssaint + VoiceOS.

import Contacts
import Foundation
import Speech
import AVFoundation

/// Words recognition should hear as written: the dictionary's, then the
/// names in Contacts when the app may read them. Names are what a general
/// recognizer gets wrong most ("Keshav" heard as "case of"). Read at most
/// every few minutes, and never sent anywhere.
enum VOVocabulary {
    private static var cached: (date: Date, names: [String])?

    static func terms(limit: Int) -> [String] {
        var seen = Set<String>()
        var terms: [String] = []
        for term in VOSettings.shared.dictionary.map(\.written) + contactNames() {
            let trimmed = term.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { continue }
            terms.append(trimmed)
            if terms.count >= limit { break }
        }
        return terms
    }

    private static func contactNames() -> [String] {
        if let cached, Date().timeIntervalSince(cached.date) < 600 { return cached.names }
        guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else { return [] }
        var names: [String] = []
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactNicknameKey] as [CNKeyDescriptor]
        try? CNContactStore().enumerateContacts(with: CNContactFetchRequest(keysToFetch: keys)) { contact, _ in
            names += [contact.givenName, contact.familyName, contact.nickname].filter { !$0.isEmpty }
        }
        cached = (Date(), names)
        return names
    }
}

/// A single listening session: starts the mic, streams partial text, and produces a final
/// transcript when stopped. Everything here runs on this Mac. Apple's recognizer streams by
/// itself; Whisper hears the recording so far again about once a second.
@MainActor
final class VOSpeechSession {
    private let capture = VOAudioCapture()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var latest = ""
    private var finalContinuation: CheckedContinuation<String, Never>?
    private let engine: VOSpeechEngine
    /// Whisper's passes while listening, and how many samples the last one heard.
    private var passes: Task<Void, Never>?
    private var heard = 0
    /// The loudest the microphone got: below speech, Whisper's text would be made up.
    private var loudest: Float = 0
    /// How many samples had come in when speech was last heard.
    private var spokeUntil = 0

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
            // Apple suggests no more than a hundred phrases.
            req.contextualStrings = VOVocabulary.terms(limit: 100)
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
        loudest = 0
        heard = 0
        spokeUntil = 0
        capture.onLevel = { [weak self] level in
            Task { @MainActor in
                guard let self else { return }
                self.loudest = max(self.loudest, level)
                if level >= VOWhisper.speechLevel { self.spokeUntil = self.capture.count }
                self.onLevel?(level)
            }
        }
        try capture.start(deviceUID: settings.microphoneUID)
        if engine == .whisper { listenWithWhisper() }
    }

    /// While the key is held: the recording so far, heard again whenever
    /// half a second more of it has come in since the last pass ended and
    /// some of it is speech, up to Whisper's thirty-second window. A pause
    /// before the key is let go gets one pass right away and none over the
    /// silence after, so that pass can stand as the final text; a pass runs
    /// to its end even once listening stops.
    private func listenWithWhisper() {
        passes = Task { [weak self] in
            _ = await VOWhisperServer.shared.prepare()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard let self, !Task.isCancelled else { return }
                let count = self.capture.count
                guard count >= VOWhisper.rate * 8 / 10, count - self.heard >= VOWhisper.rate / 2,
                      count <= VOWhisper.rate * 30, self.spokeUntil > self.heard else { continue }
                let samples = self.capture.snapshot()
                let pass = Task { try? await VOWhisper.transcribe(samples, live: true) }
                guard let text = await pass.value else { continue }
                self.heard = samples.count
                self.latest = text
                if !text.isEmpty { self.onPartial?(text) }
            }
        }
    }

    /// Stops listening and returns (transcript, seconds spoken).
    func stop() async -> (text: String, duration: Double) {
        let (samples, duration) = capture.stop()
        switch engine {
        case .apple:
            request?.endAudio()
            // Apple's recognizer draws the words live; Whisper, when it is on
            // this Mac, hears the whole recording again for the final text,
            // in parallel, and knows names and the vocabulary far better.
            let refines = VOWhisper.canRefine && duration > 0.3
            let refined: Task<String?, Never>? = refines ? Task { try? await VOWhisper.transcribe(samples) } : nil
            let text = await withCheckedContinuation { (c: CheckedContinuation<String, Never>) in
                finalContinuation = c
                // Don't wait forever for the recognizer's final pass.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in self?.finish() }
            }
            task?.cancel()
            // Whisper makes up a "Thank you." over silence; only a recording
            // Apple heard words in takes its text.
            if let refined, let better = await refined.value, !better.isEmpty,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return (better, duration) }
            return (text, duration)
        case .whisper:
            // The pass under way finishes; a pass that heard all the speech,
            // or all but the release of the key, is the final text.
            passes?.cancel()
            await passes?.value
            passes = nil
            guard duration > 0.3, loudest >= VOWhisper.speechLevel else { return ("", duration) }
            if !latest.isEmpty, heard >= spokeUntil || samples.count - heard <= VOWhisper.rate * 4 / 10 {
                return (latest, duration)
            }
            let text = (try? await VOWhisper.transcribe(samples)) ?? latest
            return (text, duration)
        }
    }

    func cancel() {
        passes?.cancel()
        passes = nil
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

/// whisper.cpp via its server, or the `whisper-cli` binary (Homebrew: `brew install whisper-cpp`).
enum VOWhisper {
    /// Samples a second, as it hears them.
    static let rate = 16_000
    /// The microphone's level, 0 to 1, that speech reaches; quieter, there is nothing to hear.
    static let speechLevel: Float = 0.3

    /// whisper-cli and a model on this Mac, looked for where Homebrew and
    /// MacWhisper put them, without asking the shell or the settings.
    static var isInstalled: Bool {
        ["/usr/local/bin/whisper-cli", "/opt/homebrew/bin/whisper-cli"].contains { FileManager.default.isExecutableFile(atPath: $0) }
            && anyModel() != nil
    }

    static var binary: String? {
        for p in ["/usr/local/bin/whisper-cli", "/opt/homebrew/bin/whisper-cli"] where FileManager.default.isExecutableFile(atPath: p) {
            return p
        }
        return VOCLIRunner.resolve("whisper-cli")
    }

    /// Whisper checks Apple's final text when it is installed and allowed.
    static var canRefine: Bool {
        VOSettings.shared.refineWithWhisper && binary != nil && availableModel() != nil
    }

    /// The chosen model, else any other on this Mac: VoiceOS's own, then one
    /// MacWhisper downloaded, which is read in place.
    static func availableModel() -> URL? {
        modelURL(VOSettings.shared.whisperModel) ?? anyModel()
    }

    static func anyModel() -> URL? {
        for model in [VOWhisperModel.baseEn, .smallEn, .tinyEn, .base, .small] {
            if let url = modelURL(model) { return url }
        }
        let macWhisper = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/MacWhisper/models")
        let files = (try? FileManager.default.contentsOfDirectory(at: macWhisper, includingPropertiesForKeys: nil)) ?? []
        let models = files.filter { $0.pathExtension == "bin" && $0.lastPathComponent.hasPrefix("ggml") }
        for size in ["base.en", "base", "small.en", "small", "tiny"] {
            if let url = models.first(where: { $0.lastPathComponent.contains(size) }) { return url }
        }
        return models.first
    }

    static func modelURL(_ m: VOWhisperModel) -> URL? {
        let candidates = [VOStorage.modelsDirectory.appendingPathComponent(m.fileName),
                          URL(fileURLWithPath: "/usr/local/share/whisper-cpp/\(m.fileName)"),
                          URL(fileURLWithPath: "/opt/homebrew/share/whisper-cpp/\(m.fileName)"),
                          URL(fileURLWithPath: NSHomeDirectory() + "/.cache/whisper/\(m.fileName)"),
                          // MacWhisper's own name for the same file.
                          URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/MacWhisper/models/ggml-model-whisper-\(m.rawValue).bin")]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// The words in `samples`, through the server, or the command line when
    /// it cannot run. Whisper reads its full thirty-second window: a smaller
    /// one would be several times faster, but makes it loop on made-up words
    /// for up to forty seconds about one pass in four. A `live` pass decodes
    /// once, greedily; the final text may try again warmer when the first
    /// try reads as a loop. `live` passes go only to the server: the command
    /// line loads the model every time, too slow to keep up.
    static func transcribe(_ samples: [Float], live: Bool = false) async throws -> String {
        let settings = VOSettings.shared
        guard let bin = binary else { throw VOError("whisper-cli not found. Install with: brew install whisper-cpp") }
        guard let model = availableModel() else { throw VOError("Download a Whisper model in Dictation settings.") }
        let lang = model.lastPathComponent.contains(".en") ? "en" : String(settings.languageCode.prefix(2))
        let prompt = VOVocabulary.terms(limit: 60).joined(separator: ", ")
        let wav = VOCLIRunner.scratchDirectory().appendingPathComponent("dictation-\(UUID().uuidString).wav")
        try VOAudioCapture.writeWAV(samples, to: wav)
        defer { try? FileManager.default.removeItem(at: wav) }
        if let data = try? Data(contentsOf: wav) {
            var fields = ["response_format": "json", "temperature": "0.0", "language": lang, "no_timestamps": "true",
                          "beam_size": "1", "best_of": "1"]
            if live { fields["temperature_inc"] = "0.0" }
            if !prompt.isEmpty { fields["prompt"] = prompt }
            if let text = try? await VOWhisperServer.shared.transcribe(wav: data, fields: fields) { return clean(text) }
        }
        guard !live else { throw VOError("Whisper's server isn't running.") }
        let threads = max(2, ProcessInfo.processInfo.activeProcessorCount - 1)
        var args = ["-m", model.path, "-f", wav.path, "-l", lang, "-nt", "-np", "-t", "\(threads)", "-bs", "1", "-bo", "1"]
        if !prompt.isEmpty { args += ["--prompt", prompt] }
        let r = try await VOCLIRunner.run(bin, args, timeout: 120)
        return clean(r.stdout)
    }

    /// Without its markers, "[BLANK_AUDIO]" and the like, and nothing when
    /// all it heard was a sound, "(music)" or "*laughs*".
    static func clean(_ text: String) -> String {
        let words = text
            .replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
            .split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if words.range(of: #"^(\([^)]*\)|\*[^*]*\*)$"#, options: .regularExpression) != nil { return "" }
        return words
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
