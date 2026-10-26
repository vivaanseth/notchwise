// SPDX-License-Identifier: GPL-3.0-or-later
// Ported from VoiceOS Clone (AI/AIBackends.swift) into Vorssaint + VoiceOS.

import Foundation

struct VOAIRequest {
    var system: String
    var prompt: String
    var images: [URL] = []
    var model: String = ""
    var timeout: TimeInterval = 45
    var jsonSchema: [String: Any]? = nil   // Ollama structured output
    var maxTokens: Int? = nil
}

protocol VOAIBackend {
    func send(_ request: VOAIRequest, onPartial: ((String) -> Void)?) async throws -> String
}

func voImageMediaType(_ url: URL) -> String {
    ["jpg", "jpeg"].contains(url.pathExtension.lowercased()) ? "image/jpeg" : "image/png"
}

// MARK: - Subscription mode (official CLIs)

/// Claude Code in print mode. Hooks, plugins, MCP servers and tools are switched off so it starts
/// in ~2s and behaves like a plain chat completion billed to the user's Claude plan.
struct VOClaudeCLIBackend: VOAIBackend {
    /// Keep one booted Claude process waiting so the next request skips CLI startup.
    var keepWarm = true

    func send(_ request: VOAIRequest, onPartial: ((String) -> Void)?) async throws -> String {
        guard let exe = VOCLIRunner.resolve("claude") else {
            throw VOError("Claude Code isn't installed. Run: \(VOProviderID.claude.installCommand)")
        }
        // The request's own instructions travel inside the message, so a pre-booted process can serve it.
        var content: [[String: Any]] = request.images.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return ["type": "image", "source": ["type": "base64", "media_type": voImageMediaType(url), "data": data.base64EncodedString()]]
        }
        content.append(["type": "text", "text": "<instructions>\n\(request.system)\n</instructions>\n\n\(request.prompt)"])
        let msg: [String: Any] = ["type": "user", "message": ["role": "user", "content": content]]
        var stdin = try JSONSerialization.data(withJSONObject: msg)
        stdin.append(0x0A)

        let proc: VOClaudeProc
        if keepWarm, let warm = VOClaudeWarmPool.shared.take(model: request.model) {
            proc = warm
        } else {
            proc = try VOClaudeProc(executable: exe, args: VOClaudeWarmPool.args(model: request.model))
        }
        let debugLog = ProcessInfo.processInfo.environment["VOICEOS_DEBUG_LOG"]
        let started = Date()
        let state = VOStreamState()
        proc.attach { line in
            if let debugLog {
                VOCLIRunner.debug("+\(String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), Date().timeIntervalSince(started)))s claude(warm=\(Date().timeIntervalSince(proc.born) > 1)) │ \(line.prefix(120))", to: debugLog)
            }
            guard let obj = Self.json(line) else { return }
            switch obj["type"] as? String {
            case "stream_event":
                if let event = obj["event"] as? [String: Any], event["type"] as? String == "content_block_delta",
                   let delta = event["delta"] as? [String: Any], delta["type"] as? String == "text_delta",
                   let t = delta["text"] as? String {
                    onPartial?(state.append(t))
                }
            case "assistant":
                if let m = obj["message"] as? [String: Any], let blocks = m["content"] as? [[String: Any]] {
                    let text = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined()
                    if !text.isEmpty { state.setAssistant(text) }
                }
            case "result":
                state.setResult(obj["result"] as? String ?? "", isError: obj["is_error"] as? Bool ?? false)
            default: break
            }
        }
        proc.send(stdin)
        let (status, timedOut) = await proc.waitForExit(timeout: request.timeout)
        if keepWarm { VOClaudeWarmPool.shared.prewarm(executable: exe, model: request.model) }

        if timedOut { throw VOError("Claude took too long to answer.") }
        if state.isError { throw VOError(Self.friendly(state.result)) }
        let text = state.result.isEmpty ? (state.assistant.isEmpty ? state.partial : state.assistant) : state.result
        if text.isEmpty {
            let err = proc.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw VOError(err.isEmpty ? "Claude returned no answer (exit \(status))." : Self.friendly(err))
        }
        return text
    }

    static func friendly(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.localizedCaseInsensitiveContains("credit balance") {
            return "Claude: \(s). Your Claude Code login has no Pro/Max plan attached; sign in with a subscribed account (Apps → Claude → Sign in)."
        }
        if s.localizedCaseInsensitiveContains("not logged in") || s.localizedCaseInsensitiveContains("/login") {
            return "Claude isn't signed in. Open Apps → Claude → Sign in."
        }
        return s.count > 400 ? String(s.prefix(400)) + "…" : s
    }

    static func json(_ line: String) -> [String: Any]? {
        guard line.first == "{", let data = line.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

/// OpenAI Codex CLI, signed in with ChatGPT. Reasoning effort is forced low so voice replies stay quick.
struct VOCodexCLIBackend: VOAIBackend {
    func send(_ request: VOAIRequest, onPartial: ((String) -> Void)?) async throws -> String {
        guard let exe = VOCLIRunner.resolve("codex") else {
            throw VOError("Codex CLI isn't installed. Run: \(VOProviderID.chatgpt.installCommand)")
        }
        let dir = VOCLIRunner.scratchDirectory()
        let outFile = dir.appendingPathComponent("codex-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: outFile) }

        var args = ["exec", "--skip-git-repo-check", "--ephemeral", "--sandbox", "read-only", "--json",
                    "-c", "model_reasoning_effort=\"low\"", "-o", outFile.path]
        if !request.model.isEmpty { args += ["-m", request.model] }
        for img in request.images { args += ["-i", img.path] }
        args.append("-")

        let prompt = "<instructions>\n\(request.system)\n</instructions>\n\n\(request.prompt)"
        let state = VOStreamState()
        let result = try await VOCLIRunner.run(exe, args, stdin: Data(prompt.utf8), cwd: dir, timeout: request.timeout) { line in
            guard let obj = VOClaudeCLIBackend.json(line) else { return }
            let type = obj["type"] as? String ?? ""
            if type.hasPrefix("item."), let item = obj["item"] as? [String: Any],
               (item["type"] as? String) == "agent_message", let t = item["text"] as? String {
                state.setAssistant(t)
                onPartial?(t)
            } else if type == "error", let m = obj["message"] as? String {
                state.setError(m)
            } else if type == "turn.failed", let e = obj["error"] as? [String: Any], let m = e["message"] as? String {
                state.setError(m)
            }
        }
        if result.timedOut { throw VOError("ChatGPT took too long to answer.") }
        let fileText = (try? String(contentsOf: outFile, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let text = fileText.isEmpty ? state.assistant : fileText
        if !text.isEmpty { return text }
        let err = state.errorMessage.isEmpty ? result.stderr : state.errorMessage
        throw VOError(Self.friendly(err, status: result.status))
    }

    static func friendly(_ raw: String, status: Int32) -> String {
        let lines = raw.split(separator: "\n").map(String.init)
        let errLine = lines.last(where: { $0.contains("ERROR") || $0.localizedCaseInsensitiveContains("error") }) ?? lines.last ?? ""
        if raw.localizedCaseInsensitiveContains("refresh token") || raw.contains("401") || raw.localizedCaseInsensitiveContains("log in") {
            return "ChatGPT sign-in expired. Open Apps → ChatGPT → Sign in to log in again."
        }
        if raw.localizedCaseInsensitiveContains("usage limit") || raw.localizedCaseInsensitiveContains("rate limit") {
            return "ChatGPT usage limit reached for now. \(errLine)"
        }
        let s = errLine.replacingOccurrences(of: #"^\S+Z\s+ERROR\s+\S+:\s*"#, with: "", options: .regularExpression)
        return s.isEmpty ? "ChatGPT returned no answer (exit \(status))." : "ChatGPT: \(s.prefix(300))"
    }
}

/// Google Gemini CLI, signed in with a Google account.
struct VOGeminiCLIBackend: VOAIBackend {
    func send(_ request: VOAIRequest, onPartial: ((String) -> Void)?) async throws -> String {
        guard let exe = VOCLIRunner.resolve("gemini") else {
            throw VOError("Gemini CLI isn't installed. Run: \(VOProviderID.gemini.installCommand)")
        }
        // Without cached Google credentials the CLI waits forever for a browser login — fail fast instead.
        if case .signedOut = await VOProviderManager.shared.status[.gemini] ?? .unknown,
           !FileManager.default.fileExists(atPath: NSHomeDirectory() + "/.gemini/oauth_creds.json"),
           ProcessInfo.processInfo.environment["GEMINI_API_KEY"] == nil {
            throw VOError("Gemini isn't signed in — Google sign-in not finished. Open Apps → Gemini → Sign in and choose \"Login with Google\".")
        }
        // Gemini reads images through @file references inside its workspace.
        let dir = VOCLIRunner.scratchDirectory().appendingPathComponent("gemini-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var refs = ""
        for (i, img) in request.images.enumerated() {
            let name = "screen\(i).\(img.pathExtension.isEmpty ? "png" : img.pathExtension)"
            try? FileManager.default.copyItem(at: img, to: dir.appendingPathComponent(name))
            refs += " @\(name)"
        }
        let prompt = "<instructions>\n\(request.system)\n</instructions>\n\n\(request.prompt)\(refs.isEmpty ? "" : "\n\nScreenshot:\(refs)")"
        var args = ["-p", prompt, "-o", "json"]
        if !request.model.isEmpty { args += ["-m", request.model] }

        let result = try await VOCLIRunner.run(exe, args, cwd: dir, timeout: request.timeout)
        if result.timedOut { throw VOError("Gemini took too long to answer.") }
        let out = result.stdout
        if let start = out.firstIndex(of: "{"), let data = String(out[start...]).data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let r = obj["response"] as? String, !r.isEmpty { return r }
            if let e = obj["error"] as? [String: Any], let m = e["message"] as? String { throw VOError(Self.friendly(m)) }
        }
        let err = (result.stderr + "\n" + out).trimmingCharacters(in: .whitespacesAndNewlines)
        throw VOError(Self.friendly(err.isEmpty ? "Gemini returned no answer (exit \(result.status))." : err))
    }

    static func friendly(_ raw: String) -> String {
        if raw.localizedCaseInsensitiveContains("auth method") || raw.localizedCaseInsensitiveContains("login") {
            return "Gemini isn't signed in. Open Apps → Gemini → Sign in and choose \"Login with Google\"."
        }
        if raw.contains("429") || raw.localizedCaseInsensitiveContains("quota") {
            return "Gemini quota reached for now."
        }
        let line = raw.split(separator: "\n").last.map(String.init) ?? raw
        return "Gemini: \(line.prefix(300))"
    }
}

/// Accumulates streamed output from a CLI across reader threads.
final class VOStreamState: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var partial = ""
    private(set) var assistant = ""
    private(set) var result = ""
    private(set) var isError = false
    private(set) var errorMessage = ""

    func append(_ t: String) -> String { lock.lock(); defer { lock.unlock() }; partial += t; return partial }
    func setAssistant(_ t: String) { lock.lock(); assistant = t; lock.unlock() }
    func setResult(_ t: String, isError e: Bool) { lock.lock(); result = t; isError = e; lock.unlock() }
    func setError(_ m: String) { lock.lock(); errorMessage = m; lock.unlock() }
}

// MARK: - API key mode

struct VOAnthropicAPIBackend: VOAIBackend {
    let key: String
    func send(_ request: VOAIRequest, onPartial: ((String) -> Void)?) async throws -> String {
        var content: [[String: Any]] = request.images.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return ["type": "image", "source": ["type": "base64", "media_type": voImageMediaType(url), "data": data.base64EncodedString()]]
        }
        content.append(["type": "text", "text": request.prompt])
        let body: [String: Any] = ["model": request.model, "max_tokens": 1500, "system": request.system,
                                   "messages": [["role": "user", "content": content]]]
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = request.timeout
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let obj = try await VOHTTP.json(req)
        if let blocks = obj["content"] as? [[String: Any]] {
            return blocks.compactMap { $0["text"] as? String }.joined()
        }
        throw VOError(VOHTTP.errorMessage(obj, provider: "Claude"))
    }
}

struct VOOpenAIAPIBackend: VOAIBackend {
    let key: String
    func send(_ request: VOAIRequest, onPartial: ((String) -> Void)?) async throws -> String {
        var userContent: [[String: Any]] = [["type": "text", "text": request.prompt]]
        for url in request.images {
            if let data = try? Data(contentsOf: url) {
                userContent.append(["type": "image_url", "image_url": ["url": "data:\(voImageMediaType(url));base64,\(data.base64EncodedString())"]])
            }
        }
        let body: [String: Any] = ["model": request.model,
                                   "messages": [["role": "system", "content": request.system],
                                                ["role": "user", "content": userContent]]]
        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.timeoutInterval = request.timeout
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let obj = try await VOHTTP.json(req)
        if let choices = obj["choices"] as? [[String: Any]], let msg = choices.first?["message"] as? [String: Any],
           let text = msg["content"] as? String {
            return text
        }
        throw VOError(VOHTTP.errorMessage(obj, provider: "ChatGPT"))
    }
}

struct VOGeminiAPIBackend: VOAIBackend {
    let key: String
    func send(_ request: VOAIRequest, onPartial: ((String) -> Void)?) async throws -> String {
        var parts: [[String: Any]] = [["text": request.prompt]]
        for url in request.images {
            if let data = try? Data(contentsOf: url) {
                parts.append(["inline_data": ["mime_type": voImageMediaType(url), "data": data.base64EncodedString()]])
            }
        }
        let body: [String: Any] = ["systemInstruction": ["parts": [["text": request.system]]],
                                   "contents": [["role": "user", "parts": parts]]]
        let model = request.model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? request.model
        var req = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!)
        req.httpMethod = "POST"
        req.timeoutInterval = request.timeout
        req.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let obj = try await VOHTTP.json(req)
        if let cands = obj["candidates"] as? [[String: Any]], let content = cands.first?["content"] as? [String: Any],
           let ps = content["parts"] as? [[String: Any]] {
            return ps.compactMap { $0["text"] as? String }.joined()
        }
        throw VOError(VOHTTP.errorMessage(obj, provider: "Gemini"))
    }
}

enum VOHTTP {
    static func json(_ req: URLRequest) async throws -> [String: Any] {
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw VOError("Unexpected response: \(String(decoding: data.prefix(200), as: UTF8.self))")
        }
        return obj
    }

    static func errorMessage(_ obj: [String: Any], provider: String) -> String {
        if let e = obj["error"] as? [String: Any], let m = e["message"] as? String { return "\(provider): \(m)" }
        if let m = obj["error"] as? String { return "\(provider): \(m)" }
        return "\(provider) returned an unexpected response."
    }
}
