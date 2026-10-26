// SPDX-License-Identifier: GPL-3.0-or-later
// Ported from VoiceOS Clone (AI/Ollama.swift) into Vorssaint + VoiceOS.

import Foundation
import AppKit

/// Local models through Ollama's VOHTTP API (http://127.0.0.1:11434). Nothing leaves the Mac.
struct VOOllamaBackend: VOAIBackend {
    static let base = URL(string: "http://127.0.0.1:11434")!

    func send(_ request: VOAIRequest, onPartial: ((String) -> Void)?) async throws -> String {
        guard !request.model.isEmpty else { throw VOError("Pick a local model in Apps → Local AI.") }
        var body: [String: Any] = [
            "model": request.model,
            "stream": true,
            "keep_alive": "30m",
            "messages": [["role": "system", "content": request.system], ["role": "user", "content": request.prompt]],
            "options": ["temperature": 0.1, "num_ctx": 3072, "num_predict": request.maxTokens ?? 400],
        ]
        if let schema = request.jsonSchema { body["format"] = schema }
        var req = URLRequest(url: Self.base.appendingPathComponent("api/chat"))
        req.httpMethod = "POST"
        req.timeoutInterval = request.timeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let deadline = Date().addingTimeInterval(request.timeout)
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await URLSession.shared.bytes(for: req)
        } catch {
            if await VOLocalModels.isInstalled { await VOLocalModels.shared.start() }
            throw VOError(await VOLocalModels.isInstalled ? "Ollama isn't running — starting it now, try again in a few seconds."
                                                        : "Ollama isn't installed. Get it from ollama.com or run: brew install --cask ollama")
        }
        var text = ""
        var errorText = ""
        for try await line in bytes.lines {
            if Date() > deadline { throw VOError("The local model took too long.") }
            guard let data = line.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if let e = obj["error"] as? String { errorText = e; break }
            if let msg = obj["message"] as? [String: Any], let piece = msg["content"] as? String, !piece.isEmpty {
                text += piece
                onPartial?(text)
            }
            if obj["done"] as? Bool == true { break }
        }
        if let log = ProcessInfo.processInfo.environment["VOICEOS_DEBUG_LOG"] {
            VOCLIRunner.debug("ollama \(request.model) → \(text.prefix(600))", to: log)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        if !errorText.isEmpty || status >= 400 {
            if errorText.localizedCaseInsensitiveContains("not found") || status == 404 {
                throw VOError("The local model \(request.model) isn't downloaded. Get it in Apps → Local AI.")
            }
            throw VOError("Local model: \(errorText.isEmpty ? "HTTP \(status)" : errorText)")
        }
        return text
    }
}

/// Installed models, running state, downloads and warm-up for Ollama.
@MainActor
final class VOLocalModels: ObservableObject {
    static let shared = VOLocalModels()

    struct Installed: Identifiable, Hashable {
        var id: String { name }
        let name: String
        let bytes: Int64
        var sizeLabel: String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
    }

    @Published var running = false
    @Published var version = ""
    @Published var installed: [Installed] = []
    @Published var pulling: [String: Double] = [:]
    @Published var pullErrors: [String: String] = [:]
    @Published var warming = false

    nonisolated static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: "/Applications/Ollama.app") || VOCLIRunner.resolve("ollama") != nil
    }

    func refresh() async {
        do {
            var r = URLRequest(url: VOOllamaBackend.base.appendingPathComponent("api/version"))
            r.timeoutInterval = 2
            let (vData, _) = try await URLSession.shared.data(for: r)
            version = ((try? JSONSerialization.jsonObject(with: vData) as? [String: Any])?["version"] as? String) ?? ""
            var t = URLRequest(url: VOOllamaBackend.base.appendingPathComponent("api/tags"))
            t.timeoutInterval = 3
            let (tData, _) = try await URLSession.shared.data(for: t)
            let models = ((try? JSONSerialization.jsonObject(with: tData) as? [String: Any])?["models"] as? [[String: Any]]) ?? []
            installed = models.compactMap { m in
                guard let n = m["name"] as? String else { return nil }
                return Installed(name: n, bytes: (m["size"] as? NSNumber)?.int64Value ?? 0)
            }.sorted { $0.name < $1.name }
            running = true
        } catch {
            running = false
        }
    }

    func has(_ model: String) -> Bool {
        installed.contains { $0.name == model || $0.name == model + ":latest" }
    }

    /// Launches the Ollama app (or `ollama serve`) and waits for the API.
    func start() async {
        if running { return }
        if FileManager.default.fileExists(atPath: "/Applications/Ollama.app") {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Ollama.app"))
        } else if let exe = VOCLIRunner.resolve("ollama") {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: exe)
            p.arguments = ["serve"]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try? p.run()
        } else {
            return
        }
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            await refresh()
            if running { return }
        }
    }

    /// Streams `ollama pull` progress through the API.
    func pull(_ model: String) {
        guard pulling[model] == nil else { return }
        pulling[model] = 0
        pullErrors[model] = nil
        Task {
            if !running { await start() }
            do {
                var req = URLRequest(url: VOOllamaBackend.base.appendingPathComponent("api/pull"))
                req.httpMethod = "POST"
                req.timeoutInterval = 3600
                req.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "stream": true])
                let (bytes, _) = try await URLSession.shared.bytes(for: req)
                for try await line in bytes.lines {
                    guard let data = line.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                    if let e = obj["error"] as? String { pullErrors[model] = e; break }
                    if let total = (obj["total"] as? NSNumber)?.doubleValue, total > 0,
                       let done = (obj["completed"] as? NSNumber)?.doubleValue {
                        pulling[model] = done / total
                    }
                }
            } catch {
                pullErrors[model] = error.localizedDescription
            }
            pulling[model] = nil
            await refresh()
        }
    }

    /// Loads the model and caches the agent's system prompt so the first real request is quick.
    func warmUp() {
        let settings = VOSettings.shared
        guard settings.agentProvider == .ollama || settings.polishEngine == .ollama else { return }
        let model = settings.agentProvider == .ollama ? settings.localModel : settings.localDictationModel
        warming = true
        Task {
            defer { warming = false }
            await refresh()
            guard running, has(model) else { return }
            _ = try? await VOOllamaBackend().send(VOAIRequest(system: VOLocalPrompts.sharedSystem(), prompt: "Job: agent\nUser: hi",
                                                          model: model, timeout: 180, maxTokens: 1), onPartial: nil)
        }
    }
}
