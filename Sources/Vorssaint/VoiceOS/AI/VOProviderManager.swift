// SPDX-License-Identifier: GPL-3.0-or-later
// Ported from VoiceOS Clone (AI/ProviderManager.swift) into Vorssaint + VoiceOS.

import Foundation
import AppKit

enum VOProviderStatus: Equatable {
    case unknown, checking, notInstalled, signedOut(String), ready(String), failed(String)

    var isReady: Bool { if case .ready = self { return true }; return false }

    var label: String {
        switch self {
        case .unknown: return "Not checked"
        case .checking: return "Checking…"
        case .notInstalled: return "CLI not installed"
        case .signedOut(let s): return s
        case .ready(let s): return s
        case .failed(let s): return s
        }
    }
}

struct VOTestResult: Equatable {
    var ok: Bool
    var message: String
    var seconds: Double
    var date = Date()
}

/// One meter from a provider's plan (e.g. 5-hour session, weekly).
struct VOPlanMeter: Identifiable, Equatable {
    var id: String { label }
    var label: String
    var usedPercent: Double
    var resets: String?
}

struct VOPlanUsage: Equatable {
    var meters: [VOPlanMeter] = []
    var note: String?
    var updated = Date()
}

/// Knows whether each AI is installed and signed in, runs requests through the right backend, and
/// keeps track of usage — both plan limits (via CodexBar when present) and what VoiceOS itself sent.
@MainActor
final class VOProviderManager: ObservableObject {
    static let shared = VOProviderManager()

    @Published var status: [VOProviderID: VOProviderStatus] = [:]
    @Published var tests: [VOProviderID: VOTestResult] = [:]
    @Published var testing: Set<VOProviderID> = []
    @Published var planUsage: [VOProviderID: VOPlanUsage] = [:]
    @Published var loadingUsage = false
    @Published var local: [String: LocalUsage] = [:]   // "provider|yyyy-MM-dd" → counters

    private let settings = VOSettings.shared

    struct LocalUsage: Codable, Equatable {
        var requests = 0
        var failures = 0
        var inputChars = 0
        var outputChars = 0
        var seconds = 0.0
    }

    private init() {
        loadLocal()
    }

    // MARK: - Request routing

    func backend(for p: VOProviderID) throws -> VOAIBackend {
        if p == .ollama { return VOOllamaBackend() }
        if settings.mode(for: p) == .apiKey {
            guard let key = VOKeychain.get("api-\(p.rawValue)"), !key.isEmpty else {
                throw VOError("No \(p.displayName) API key saved. Add one in Apps → \(p.displayName), or switch to Subscription.")
            }
            switch p {
            case .claude: return VOAnthropicAPIBackend(key: key)
            case .chatgpt: return VOOpenAIAPIBackend(key: key)
            case .gemini: return VOGeminiAPIBackend(key: key)
            case .ollama: return VOOllamaBackend()
            }
        }
        switch p {
        case .ollama: return VOOllamaBackend()
        case .claude: return VOClaudeCLIBackend(keepWarm: settings.keepClaudeWarm)
        case .chatgpt: return VOCodexCLIBackend()
        case .gemini: return VOGeminiCLIBackend()
        }
    }

    func model(for p: VOProviderID) -> String {
        if p == .ollama { return settings.localModel }
        return settings.mode(for: p) == .apiKey ? settings.apiModel(for: p) : settings.cliModel(for: p)
    }

    /// Sends a request and records usage. `onPartial` is called on the main actor.
    func complete(_ p: VOProviderID, system: String, prompt: String, images: [URL] = [],
                  model modelOverride: String? = nil, jsonSchema: [String: Any]? = nil, maxTokens: Int? = nil,
                  timeout: TimeInterval? = nil, onPartial: ((String) -> Void)? = nil) async throws -> String {
        let req = VOAIRequest(system: system, prompt: prompt, images: images, model: modelOverride ?? model(for: p),
                            timeout: timeout ?? settings.aiTimeout, jsonSchema: jsonSchema, maxTokens: maxTokens)
        let start = Date()
        do {
            let b = try backend(for: p)
            let text = try await b.send(req) { partial in
                if let onPartial { Task { @MainActor in onPartial(partial) } }
            }
            record(p, ok: true, input: system.count + prompt.count, output: text.count, seconds: Date().timeIntervalSince(start))
            if !(status[p]?.isReady ?? false) { refreshStatus(p) }
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            record(p, ok: false, input: system.count + prompt.count, output: 0, seconds: Date().timeIntervalSince(start))
            let msg = error.localizedDescription.lowercased()
            if msg.contains("sign-in expired") || msg.contains("isn't signed in") || msg.contains("sign-in not finished") {
                status[p] = .signedOut("Sign-in needed")
            }
            throw error
        }
    }

    /// Boot a Claude process ahead of time when Claude handles dictation or the agent.
    func prewarmIfUseful() {
        let usesClaude = settings.agentProvider == .claude || settings.polishEngine == .claude
        guard settings.keepClaudeWarm, usesClaude, settings.mode(for: .claude) == .subscription,
              let exe = VOCLIRunner.resolve("claude") else { return }
        let model = settings.cliModel(for: .claude)
        DispatchQueue.global(qos: .utility).async { VOClaudeWarmPool.shared.prewarm(executable: exe, model: model) }
    }

    // MARK: - Status

    func refreshAll() {
        for p in VOProviderID.allCases { refreshStatus(p) }
    }

    func refreshStatus(_ p: VOProviderID) {
        if p == .ollama {
            status[p] = .checking
            Task {
                let lm = VOLocalModels.shared
                await lm.refresh()
                let model = settings.localModel
                if lm.running {
                    status[p] = lm.has(model) ? .ready("\(model) · on this Mac") : .signedOut("\(model) not downloaded")
                } else {
                    status[p] = VOLocalModels.isInstalled ? .signedOut("Ollama isn't running") : .notInstalled
                }
            }
            return
        }
        if settings.mode(for: p) == .apiKey {
            let has = !(VOKeychain.get("api-\(p.rawValue)") ?? "").isEmpty
            status[p] = has ? .ready("API key saved") : .signedOut("No API key")
            return
        }
        status[p] = .checking
        Task.detached(priority: .utility) {
            let s = await Self.probe(p)
            await MainActor.run { self.status[p] = s }
        }
    }

    nonisolated private static func probe(_ p: VOProviderID) async -> VOProviderStatus {
        guard let exe = VOCLIRunner.resolve(p.cliName) else { return .notInstalled }
        switch p {
        case .ollama:
            return .unknown // handled in refreshStatus via VOLocalModels
        case .claude:
            guard let r = try? await VOCLIRunner.run(exe, ["auth", "status"], timeout: 15) else { return .failed("Couldn't run claude") }
            guard let data = r.stdout.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return r.stdout.localizedCaseInsensitiveContains("not") ? .signedOut("Signed out") : .failed(r.stdout.prefix(120).description)
            }
            guard obj["loggedIn"] as? Bool == true else { return .signedOut("Signed out") }
            let email = obj["email"] as? String ?? ""
            let plan = (obj["subscriptionType"] as? String).map { $0.capitalized } ?? "no plan"
            return .ready(email.isEmpty ? "Signed in · \(plan)" : "\(email) · \(plan)")
        case .chatgpt:
            guard let r = try? await VOCLIRunner.run(exe, ["login", "status"], timeout: 15) else { return .failed("Couldn't run codex") }
            let text = (r.stdout + r.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
            if text.localizedCaseInsensitiveContains("logged in using chatgpt") { return .ready("Signed in with ChatGPT") }
            if text.localizedCaseInsensitiveContains("api key") && text.localizedCaseInsensitiveContains("logged in") { return .ready("Signed in with API key") }
            return .signedOut("Signed out")
        case .gemini:
            let home = NSHomeDirectory()
            let settingsURL = URL(fileURLWithPath: "\(home)/.gemini/settings.json")
            var authType = ""
            if let data = try? Data(contentsOf: settingsURL),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let sec = obj["security"] as? [String: Any], let auth = sec["auth"] as? [String: Any] {
                    authType = auth["selectedType"] as? String ?? ""
                }
                if authType.isEmpty { authType = obj["selectedAuthType"] as? String ?? "" }
            }
            let creds = FileManager.default.fileExists(atPath: "\(home)/.gemini/oauth_creds.json")
            if authType == "oauth-personal" {
                guard creds else { return .signedOut("Google sign-in not finished") }
                var email = ""
                if let data = try? Data(contentsOf: URL(fileURLWithPath: "\(home)/.gemini/google_accounts.json")),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    email = obj["active"] as? String ?? ""
                }
                return .ready(email.isEmpty ? "Signed in with Google" : email)
            }
            if !authType.isEmpty { return .ready("Auth: \(authType)") }
            return .signedOut("Signed out")
        }
    }

    // MARK: - Test

    func test(_ p: VOProviderID) {
        testing.insert(p)
        let start = Date()
        Task {
            do {
                let r = try await complete(p, system: "You are a connectivity check. Follow the instruction exactly.",
                                           prompt: "Reply with exactly the word: Connected", timeout: 60)
                tests[p] = VOTestResult(ok: true, message: r.prefix(60).description, seconds: Date().timeIntervalSince(start))
            } catch {
                tests[p] = VOTestResult(ok: false, message: error.localizedDescription, seconds: Date().timeIntervalSince(start))
            }
            testing.remove(p)
        }
    }

    // MARK: - Sign in

    /// Opens VOTerminal with the provider's own login command (OAuth in the browser).
    func signIn(_ p: VOProviderID) {
        if p == .ollama {
            if VOLocalModels.isInstalled {
                Task {
                    await VOLocalModels.shared.start()
                    if !VOLocalModels.shared.has(settings.localModel) { VOLocalModels.shared.pull(settings.localModel) }
                    refreshStatus(.ollama)
                }
            } else {
                NSWorkspace.shared.open(URL(string: "https://ollama.com/download/mac")!)
            }
            return
        }
        let installed = VOCLIRunner.resolve(p.cliName) != nil
        let cmd = installed ? p.loginCommand : p.installCommand + " && " + p.loginCommand
        let note: String
        switch p {
        case .ollama: note = ""
        case .claude: note = "Sign in with the Claude account that has your Pro or Max plan."
        case .chatgpt: note = "Choose \"Sign in with ChatGPT\" to use your ChatGPT plan."
        case .gemini: note = "Pick \"Login with Google\", finish in the browser, then type /quit."
        }
        VOTerminal.run(cmd, banner: "Notchwise · Connect \(p.displayName)\n\(note)")
    }

    // MARK: - Plan usage (CodexBar)

    var codexbarPath: String? { VOCLIRunner.resolve("codexbar") }

    func refreshUsage() {
        planUsage[.ollama] = VOPlanUsage(note: "Free — runs on this Mac, no limits.")
        guard let exe = codexbarPath else {
            for p in VOProviderID.allCases where !p.isLocal { planUsage[p] = VOPlanUsage(note: "Install CodexBar to see plan limits: brew install codexbar") }
            return
        }
        loadingUsage = true
        Task.detached(priority: .utility) {
            var results: [VOProviderID: VOPlanUsage] = [:]
            await withTaskGroup(of: (VOProviderID, VOPlanUsage).self) { group in
                for p in VOProviderID.allCases where !p.isLocal {
                    group.addTask {
                        let name = p == .chatgpt ? "codex" : p.rawValue
                        let r = try? await VOCLIRunner.run(exe, ["usage", "--format", "json", "--provider", name, "--no-color"], timeout: 40)
                        return (p, Self.parseUsage(r?.stdout ?? "", stderr: r?.stderr ?? ""))
                    }
                }
                for await (p, u) in group { results[p] = u }
            }
            results[.ollama] = VOPlanUsage(note: "Free — runs on this Mac, no limits.")
            let snapshot = results
            await MainActor.run {
                self.planUsage = snapshot
                self.loadingUsage = false
            }
        }
    }

    nonisolated static func parseUsage(_ stdout: String, stderr: String) -> VOPlanUsage {
        guard let start = stdout.firstIndex(where: { $0 == "[" || $0 == "{" }),
              let data = String(stdout[start...]).data(using: .utf8),
              let any = try? JSONSerialization.jsonObject(with: data) else {
            let msg = stderr.split(separator: "\n").last.map(String.init) ?? "No usage data"
            return VOPlanUsage(note: msg)
        }
        let root: Any = (any as? [Any])?.first ?? any
        if let obj = root as? [String: Any], let err = obj["error"] as? [String: Any] {
            return VOPlanUsage(note: err["message"] as? String ?? "Usage unavailable")
        }
        var meters: [VOPlanMeter] = []
        func walk(_ v: Any, _ key: String) {
            if let d = v as? [String: Any] {
                let pct = (d["usedPercent"] ?? d["used_percent"] ?? d["percentUsed"] ?? d["utilization"]) as? Double
                if let pct {
                    let window = d["windowMinutes"] as? Double ?? d["window_minutes"] as? Double
                    let reset = d["resetDescription"] as? String ?? d["resetsAt"] as? String ?? d["resets_at"] as? String
                    meters.append(VOPlanMeter(label: Self.meterLabel(key, window: window), usedPercent: pct, resets: reset))
                }
                for (k, sub) in d.sorted(by: { $0.key < $1.key }) { walk(sub, k) }
            } else if let a = v as? [Any] {
                for sub in a { walk(sub, key) }
            }
        }
        walk(root, "")
        return VOPlanUsage(meters: meters, note: meters.isEmpty ? "Signed in — no limits reported" : nil)
    }

    nonisolated private static func meterLabel(_ key: String, window: Double?) -> String {
        if let w = window {
            if w <= 360 { return "Session (\(Int(w / 60))h)" }
            if w >= 10_000 { return "Weekly" }
        }
        switch key.lowercased() {
        case "primary", "five_hour", "session": return "Session"
        case "secondary", "seven_day", "weekly": return "Weekly"
        case "tertiary", "seven_day_opus", "opus": return "Weekly (Opus)"
        default: return key.isEmpty ? "Usage" : key.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    // MARK: - Local usage counters

    private var localURL: URL { VOStorage.directory.appendingPathComponent("usage.json") }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    private func record(_ p: VOProviderID, ok: Bool, input: Int, output: Int, seconds: Double) {
        let key = "\(p.rawValue)|\(Self.dayFormatter.string(from: Date()))"
        var u = local[key] ?? LocalUsage()
        u.requests += 1
        if !ok { u.failures += 1 }
        u.inputChars += input
        u.outputChars += output
        u.seconds += seconds
        local[key] = u
        saveLocal()
    }

    func totals(for p: VOProviderID, days: Int = 30) -> LocalUsage {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        var t = LocalUsage()
        for (k, v) in local {
            let parts = k.split(separator: "|")
            guard parts.count == 2, parts[0] == p.rawValue, let d = Self.dayFormatter.date(from: String(parts[1])), d >= cutoff else { continue }
            t.requests += v.requests; t.failures += v.failures; t.inputChars += v.inputChars
            t.outputChars += v.outputChars; t.seconds += v.seconds
        }
        return t
    }

    func todayRequests(_ p: VOProviderID) -> Int {
        local["\(p.rawValue)|\(Self.dayFormatter.string(from: Date()))"]?.requests ?? 0
    }

    private func loadLocal() {
        if let data = try? Data(contentsOf: localURL), let d = try? JSONDecoder().decode([String: LocalUsage].self, from: data) {
            local = d
        }
    }

    private func saveLocal() {
        if let data = try? JSONEncoder().encode(local) { try? data.write(to: localURL, options: .atomic) }
    }
}

/// Opens VOTerminal.app running a command, via a throwaway .command script (no Automation prompt).
enum VOTerminal {
    static func run(_ command: String, banner: String? = nil, cwd: String? = nil) {
        let url = VOCLIRunner.scratchDirectory().appendingPathComponent("voiceos-\(UUID().uuidString.prefix(8)).command")
        var script = "#!/bin/zsh -l\nclear\n"
        if let banner {
            for line in banner.split(separator: "\n") { script += "echo \(shellQuote(String(line)))\n" }
            script += "echo\n"
        }
        if let cwd { script += "cd \(shellQuote(cwd)) || exit 1\n" }
        script += "\(command)\n"
        script += "echo\necho 'Done. You can close this window and return to Notchwise.'\n"
        try? script.write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open([url], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
    }

    static func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}
