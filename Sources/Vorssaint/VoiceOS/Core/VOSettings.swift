// SPDX-License-Identifier: GPL-3.0-or-later
// Ported from VoiceOS Clone (Core/Settings.swift) into Vorssaint + VoiceOS.

import Foundation
import Combine

/// All user preferences, persisted to UserDefaults on every change.
final class VOSettings: ObservableObject {
    static let shared = VOSettings()
    /// VoiceOS keys share Vorssaint's preferences domain, so each one is
    /// namespaced: "playSounds" or "onboardingDone" can never meet a key of
    /// Vorssaint's own.
    static let prefix = "voiceos."
    /// The standalone VoiceOS Clone app, whose choices the first launch copies.
    static let standaloneDomain = "com.local.voiceos-clone"
    private let d = UserDefaults.standard

    // Profile
    @Published var onboardingDone: Bool { didSet { d.set(onboardingDone, forKey: Self.prefix + "onboardingDone") } }
    @Published var firstName: String { didSet { d.set(firstName, forKey: Self.prefix + "firstName") } }
    @Published var lastName: String { didSet { d.set(lastName, forKey: Self.prefix + "lastName") } }
    @Published var memories: [String] { didSet { save(memories, "memories") } }

    // Shortcuts
    @Published var dictationTrigger: VODictationTrigger { didSet { d.set(dictationTrigger.rawValue, forKey: Self.prefix + "dictationTrigger") } }
    @Published var agentTrigger: VOAssistantTrigger { didSet { d.set(agentTrigger.rawValue, forKey: Self.prefix + "agentTrigger") } }
    @Published var doubleTapHandsFree: Bool { didSet { d.set(doubleTapHandsFree, forKey: Self.prefix + "doubleTapHandsFree") } }

    // Dictation
    @Published var languageCode: String { didSet { d.set(languageCode, forKey: Self.prefix + "languageCode") } }
    @Published var speechEngine: VOSpeechEngine { didSet { d.set(speechEngine.rawValue, forKey: Self.prefix + "speechEngine") } }
    @Published var whisperModel: VOWhisperModel { didSet { d.set(whisperModel.rawValue, forKey: Self.prefix + "whisperModel") } }
    @Published var polishEngine: VOPolishEngine { didSet { d.set(polishEngine.rawValue, forKey: Self.prefix + "polishEngine") } }
    @Published var removeFillers: Bool { didSet { d.set(removeFillers, forKey: Self.prefix + "removeFillers") } }
    @Published var appAwareStyle: Bool { didSet { d.set(appAwareStyle, forKey: Self.prefix + "appAwareStyle") } }
    @Published var playSounds: Bool { didSet { d.set(playSounds, forKey: Self.prefix + "playSounds") } }
    @Published var dictionary: [VODictionaryEntry] { didSet { save(dictionary, "dictionary") } }
    @Published var microphoneUID: String { didSet { d.set(microphoneUID, forKey: Self.prefix + "microphoneUID") } }
    @Published var showIdlePill: Bool { didSet { d.set(showIdlePill, forKey: Self.prefix + "showIdlePill") } }

    // Agent
    @Published var agentProvider: VOProviderID { didSet { d.set(agentProvider.rawValue, forKey: Self.prefix + "agentProvider") } }
    @Published var agentVoiceEnabled: Bool { didSet { d.set(agentVoiceEnabled, forKey: Self.prefix + "agentVoiceEnabled") } }
    @Published var agentVoiceSpeed: VOVoiceSpeed { didSet { d.set(agentVoiceSpeed.rawValue, forKey: Self.prefix + "agentVoiceSpeed") } }
    @Published var agentVoice: String { didSet { d.set(agentVoice, forKey: Self.prefix + "agentVoice") } }
    @Published var capabilities: [String: Bool] { didSet { d.set(capabilities, forKey: Self.prefix + "capabilities") } }

    // Providers
    @Published var connectionModes: [String: String] { didSet { d.set(connectionModes, forKey: Self.prefix + "connectionModes") } }
    @Published var cliModels: [String: String] { didSet { d.set(cliModels, forKey: Self.prefix + "cliModels") } }
    @Published var apiModels: [String: String] { didSet { d.set(apiModels, forKey: Self.prefix + "apiModels") } }
    @Published var aiTimeout: Double { didSet { d.set(aiTimeout, forKey: Self.prefix + "aiTimeout") } }
    @Published var localModel: String { didSet { d.set(localModel, forKey: Self.prefix + "localModel") } }
    @Published var localDictationModel: String { didSet { d.set(localDictationModel, forKey: Self.prefix + "localDictationModel") } }
    @Published var escalationEnabled: Bool { didSet { d.set(escalationEnabled, forKey: Self.prefix + "escalationEnabled") } }
    @Published var escalationProvider: VOProviderID { didSet { d.set(escalationProvider.rawValue, forKey: Self.prefix + "escalationProvider") } }
    @Published var escalationModel: String { didSet { d.set(escalationModel, forKey: Self.prefix + "escalationModel") } }
    @Published var escalationDailyLimit: Int { didSet { d.set(escalationDailyLimit, forKey: Self.prefix + "escalationDailyLimit") } }
    @Published var keepClaudeWarm: Bool { didSet { d.set(keepClaudeWarm, forKey: Self.prefix + "keepClaudeWarm"); if !keepClaudeWarm { VOClaudeWarmPool.shared.drain() } } }

    // Privacy & general
    @Published var saveHistory: Bool { didSet { d.set(saveHistory, forKey: Self.prefix + "saveHistory") } }
    @Published var saveAudio: Bool { didSet { d.set(saveAudio, forKey: Self.prefix + "saveAudio") } }
    @Published var neverTrain: Bool { didSet { d.set(neverTrain, forKey: Self.prefix + "neverTrain") } }
    @Published var diagnostics: Bool { didSet { d.set(diagnostics, forKey: Self.prefix + "diagnostics") } }
    @Published var showIdleNotch: Bool { didSet { d.set(showIdleNotch, forKey: Self.prefix + "showIdleNotch") } }

    private init() {
        let fullName = NSFullUserName().split(separator: " ").map(String.init)
        onboardingDone = d.bool(forKey: Self.prefix + "onboardingDone")
        firstName = d.string(forKey: Self.prefix + "firstName") ?? (fullName.first ?? "")
        lastName = d.string(forKey: Self.prefix + "lastName") ?? (fullName.count > 1 ? fullName.dropFirst().joined(separator: " ") : "")
        memories = Self.load([String].self, "memories", d) ?? []

        dictationTrigger = VODictationTrigger(rawValue: d.string(forKey: Self.prefix + "dictationTrigger") ?? "") ?? .fn
        agentTrigger = VOAssistantTrigger(rawValue: d.string(forKey: Self.prefix + "agentTrigger") ?? "") ?? .rightCommand
        doubleTapHandsFree = d.object(forKey: Self.prefix + "doubleTapHandsFree") as? Bool ?? true

        languageCode = d.string(forKey: Self.prefix + "languageCode") ?? (Locale.current.identifier.replacingOccurrences(of: "_", with: "-").hasPrefix("en") ? Locale.current.identifier.replacingOccurrences(of: "_", with: "-") : "en-US")
        speechEngine = VOSpeechEngine(rawValue: d.string(forKey: Self.prefix + "speechEngine") ?? "") ?? .apple
        whisperModel = VOWhisperModel(rawValue: d.string(forKey: Self.prefix + "whisperModel") ?? "") ?? .baseEn
        polishEngine = VOPolishEngine(rawValue: d.string(forKey: Self.prefix + "polishEngine") ?? "") ?? .ollama
        removeFillers = d.object(forKey: Self.prefix + "removeFillers") as? Bool ?? true
        appAwareStyle = d.object(forKey: Self.prefix + "appAwareStyle") as? Bool ?? true
        playSounds = d.object(forKey: Self.prefix + "playSounds") as? Bool ?? true
        dictionary = Self.load([VODictionaryEntry].self, "dictionary", d) ?? [
            VODictionaryEntry(spoken: "super base", written: "Supabase"),
            VODictionaryEntry(spoken: "voice os", written: "VoiceOS"),
        ]
        microphoneUID = d.string(forKey: Self.prefix + "microphoneUID") ?? ""
        showIdlePill = d.object(forKey: Self.prefix + "showIdlePill") as? Bool ?? false

        agentProvider = VOProviderID(rawValue: d.string(forKey: Self.prefix + "agentProvider") ?? "") ?? .ollama
        agentVoiceEnabled = d.object(forKey: Self.prefix + "agentVoiceEnabled") as? Bool ?? true
        agentVoiceSpeed = VOVoiceSpeed(rawValue: d.string(forKey: Self.prefix + "agentVoiceSpeed") ?? "") ?? .normal
        agentVoice = d.string(forKey: Self.prefix + "agentVoice") ?? "jarvis"
        capabilities = d.dictionary(forKey: Self.prefix + "capabilities") as? [String: Bool] ?? [:]

        connectionModes = d.dictionary(forKey: Self.prefix + "connectionModes") as? [String: String] ?? [:]
        cliModels = d.dictionary(forKey: Self.prefix + "cliModels") as? [String: String] ?? ["claude": "haiku", "gemini": "gemini-2.5-flash"]
        apiModels = d.dictionary(forKey: Self.prefix + "apiModels") as? [String: String] ?? [:]
        aiTimeout = d.object(forKey: Self.prefix + "aiTimeout") as? Double ?? 45
        keepClaudeWarm = d.object(forKey: Self.prefix + "keepClaudeWarm") as? Bool ?? false
        localModel = d.string(forKey: Self.prefix + "localModel") ?? "qwen2.5:1.5b"
        localDictationModel = d.string(forKey: Self.prefix + "localDictationModel") ?? "qwen2.5:1.5b"
        escalationEnabled = d.object(forKey: Self.prefix + "escalationEnabled") as? Bool ?? true
        escalationProvider = VOProviderID(rawValue: d.string(forKey: Self.prefix + "escalationProvider") ?? "") ?? .claude
        escalationModel = d.string(forKey: Self.prefix + "escalationModel") ?? "haiku"
        escalationDailyLimit = d.object(forKey: Self.prefix + "escalationDailyLimit") as? Int ?? 25

        saveHistory = d.object(forKey: Self.prefix + "saveHistory") as? Bool ?? true
        saveAudio = d.object(forKey: Self.prefix + "saveAudio") as? Bool ?? false
        neverTrain = d.object(forKey: Self.prefix + "neverTrain") as? Bool ?? true
        diagnostics = d.object(forKey: Self.prefix + "diagnostics") as? Bool ?? false
        showIdleNotch = d.object(forKey: Self.prefix + "showIdleNotch") as? Bool ?? true

        // One-time switch to local-first: Ollama by default, Claude only when needed.
        if !d.bool(forKey: Self.prefix + "migratedLocalFirst") {
            agentProvider = .ollama
            if polishEngine.provider?.isLocal == false { polishEngine = .ollama }
            keepClaudeWarm = false
            d.set(agentProvider.rawValue, forKey: Self.prefix + "agentProvider")
            d.set(polishEngine.rawValue, forKey: Self.prefix + "polishEngine")
            d.set(false, forKey: Self.prefix + "keepClaudeWarm")
            d.set(true, forKey: Self.prefix + "migratedLocalFirst")
        }
    }

    /// Copies the standalone app's saved choices under this app's keys, once.
    /// Window frames and the Dock choice belong to that app's own windows, and
    /// a key this app already saved is never overwritten.
    static func importStandaloneApp(into defaults: UserDefaults, from source: [String: Any]?) {
        guard let source else { return }
        for (key, value) in source where !key.hasPrefix("NS") && key != "showDockIcon"
            && defaults.object(forKey: prefix + key) == nil {
            defaults.set(value, forKey: prefix + key)
        }
    }

    // MARK: helpers

    func isEnabled(_ cap: VOAssistantCapability) -> Bool { capabilities[cap.rawValue] ?? true }
    func setEnabled(_ cap: VOAssistantCapability, _ on: Bool) { capabilities[cap.rawValue] = on }

    func mode(for p: VOProviderID) -> VOConnectionMode { VOConnectionMode(rawValue: connectionModes[p.rawValue] ?? "") ?? .subscription }
    func setMode(_ m: VOConnectionMode, for p: VOProviderID) { connectionModes[p.rawValue] = m.rawValue }

    func cliModel(for p: VOProviderID) -> String { cliModels[p.rawValue] ?? "" }
    func setCliModel(_ m: String, for p: VOProviderID) { cliModels[p.rawValue] = m }

    func apiModel(for p: VOProviderID) -> String { apiModels[p.rawValue] ?? p.apiModels.first!.id }
    func setApiModel(_ m: String, for p: VOProviderID) { apiModels[p.rawValue] = m }

    var displayName: String {
        let n = [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
        return n.isEmpty ? "You" : n
    }

    func addMemory(_ fact: String) {
        let f = fact.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !f.isEmpty, !memories.contains(where: { $0.caseInsensitiveCompare(f) == .orderedSame }) else { return }
        memories.append(f)
        if memories.count > 60 { memories.removeFirst(memories.count - 60) }
    }

    private func save<T: Encodable>(_ v: T, _ key: String) {
        if let data = try? JSONEncoder().encode(v) { d.set(data, forKey: Self.prefix + key) }
    }

    private static func load<T: Decodable>(_ t: T.Type, _ key: String, _ d: UserDefaults) -> T? {
        guard let data = d.data(forKey: prefix + key) else { return nil }
        return try? JSONDecoder().decode(t, from: data)
    }
}
