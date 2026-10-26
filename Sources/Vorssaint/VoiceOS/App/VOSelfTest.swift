// SPDX-License-Identifier: GPL-3.0-or-later
// Ported from VoiceOS Clone (App/SelfTest.swift) into Vorssaint + VoiceOS.

import AppKit

/// Developer aid: `VOICEOS_SELFTEST=/path/log.txt` runs one dictation cleanup and one agent request through
/// the real pipeline (voice muted, nothing confirmed), writes what came back, and quits.
@MainActor
enum VOSelfTest {
    static func runIfRequested() -> Bool {
        guard let path = ProcessInfo.processInfo.environment["VOICEOS_SELFTEST"], !path.isEmpty else { return false }
        let provider = VOProviderID(rawValue: ProcessInfo.processInfo.environment["VOICEOS_PROVIDER"] ?? "")
        Task { await run(URL(fileURLWithPath: path), provider: provider) }
        return true
    }

    private static func run(_ out: URL, provider override: VOProviderID?) async {
        let settings = VOSettings.shared
        let voiceWas = settings.agentVoiceEnabled
        let providerWas = settings.agentProvider
        let historyWas = settings.saveHistory
        settings.agentVoiceEnabled = false
        if let override { settings.agentProvider = override }
        settings.saveHistory = false
        let limitWas = settings.escalationDailyLimit
        if let l = ProcessInfo.processInfo.environment["VOICEOS_ESCALATION_LIMIT"], let n = Int(l) { settings.escalationDailyLimit = n }
        let provider = settings.agentProvider
        var log = "assistant: \(VOAssistantController.label(provider, model: nil, reason: nil)) · dictation: \(settings.polishEngine.label)" +
                  " · escalation: \(settings.escalationEnabled ? "\(settings.escalationProvider.displayName) \(settings.escalationModel)" : "off")\n\n"
        // Let launch-time warm-up finish, like real use (the first local load can take ~30s).
        var waited = 0
        while !VOLocalModels.shared.warming && waited < 15 { try? await Task.sleep(nanoseconds: 1_000_000_000); waited += 1 }
        while VOLocalModels.shared.warming && waited < 150 { try? await Task.sleep(nanoseconds: 1_000_000_000); waited += 1 }
        log += "(waited \(waited)s for local warm-up)\n\n"

        // 1. Dictation polish (as if typing into Slack)
        let raw = "um so can you uh take a look at the onboarding bug there's like three things going wrong preya's fix from last night didn't take the the magic link still lands in spam and the postgress logs are full of timeouts so let's move standup to ten"
        let dict = settings.dictionary + [VODictionaryEntry(spoken: "preya", written: "Priya"), VODictionaryEntry(spoken: "postgress", written: "Postgres")]
        let cleaned = VOTextCleaner.clean(raw, dictionary: dict, removeFillers: true)
        log += "== Dictation\nlocal rules: \(cleaned)\n"
        let ctx = VOFrontContext(appName: "Slack", bundleID: "com.tinyspeck.slackmacgap")
        let start = Date()
        do {
            let polished: String
            if settings.polishEngine == .ollama {
                let r = try await VOProviderManager.shared.complete(
                    .ollama, system: VOLocalPrompts.dictationSystem,
                    prompt: VOLocalPrompts.dictationUser(style: .chat, speech: cleaned, terms: dict.map(\.written)),
                    model: settings.localDictationModel, jsonSchema: VOLocalPrompts.textSchema, maxTokens: 160, timeout: 60)
                polished = VOLocalPrompts.text(from: r)
            } else if let p = settings.polishEngine.provider {
                polished = VODictationController.stripWrapping(try await VOProviderManager.shared.complete(
                    p, system: VODictationController.shared.polishSystemPrompt(style: .chat, ctx: ctx), prompt: "Transcript:\n<<<\n\(cleaned)\n>>>"))
            } else {
                polished = cleaned
            }
            log += String(format: "polished:    %@\n(%.1fs)\n\n", locale: Locale(identifier: "en_US_POSIX"), polished, Date().timeIntervalSince(start))
        } catch {
            log += "polish FAILED: \(error.localizedDescription)\n\n"
        }

        // 2. Agent requests through the real router
        let agent = VOAssistantController.shared
        agent.dryRun = true
        defer { agent.dryRun = false }
        let queries = ProcessInfo.processInfo.environment["VOICEOS_QUERY"].map { [$0] } ?? [
            "Remind me to call mom tomorrow at 5pm, and what's 15% of 240?",
            "Open Spotify",
            "Text Maya that I'll be ten minutes late",
            "Write a detailed two-page proposal email to my boss about migrating our database to Postgres, with risks and a timeline",
        ]
        for q in queries {
            agent.turns.removeAll()
            let t0 = Date()
            agent.submit(q)
            while agent.turns.last?.thinking ?? false, Date().timeIntervalSince(t0) < 120 {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            if let turn = agent.turns.last {
                log += String(format: "== Assistant (%.1fs) via %@\nquery:  %@\nsay:    %@\n", locale: Locale(identifier: "en_US_POSIX"), Date().timeIntervalSince(t0), turn.via, q, turn.say)
                if let d = turn.detail { log += "detail: \(d.prefix(200))…\n" }
                if let e = turn.error { log += "error:  \(e)\n" }
                for a in turn.actions { log += "action: \(a.action.type) \(a.action.fields) state=\(a.state)\n" }
                log += "\n"
            }
            agent.close()
        }

        // 3. Image input (uses a supplied test image, never the real screen)
        if let img = ProcessInfo.processInfo.environment["VOICEOS_TEST_IMAGE"] {
            let t1 = Date()
            do {
                let r = try await VOProviderManager.shared.complete(provider, system: "Describe images briefly.",
                                                                  prompt: "Describe this image in under 12 words.",
                                                                  images: [URL(fileURLWithPath: img)])
                log += String(format: "\n== Image (%.1fs)\n%@\n", locale: Locale(identifier: "en_US_POSIX"), Date().timeIntervalSince(t1), r)
            } catch {
                log += "\n== Image FAILED: \(error.localizedDescription)\n"
            }
        }

        settings.agentVoiceEnabled = voiceWas
        if override != nil { settings.agentProvider = providerWas }
        settings.escalationDailyLimit = limitWas
        settings.saveHistory = historyWas
        try? log.write(to: out, atomically: true, encoding: .utf8)
        NSApp.terminate(nil)
    }
}
