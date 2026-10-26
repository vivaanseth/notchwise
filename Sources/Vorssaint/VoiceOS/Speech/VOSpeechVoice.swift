// SPDX-License-Identifier: GPL-3.0-or-later
// Ported from VoiceOS Clone (Speech/SpeechVoice.swift) into Vorssaint + VoiceOS.

import AVFoundation

struct VOVoicePersona: Identifiable, Hashable {
    let id: String
    let name: String
    let tagline: String
    let systemVoice: String
    let language: String
}

/// Spoken agent replies (local system voices). Publishes how far it has spoken so the notch can
/// paint words white as they're said and leave the rest grey.
@MainActor
final class VOAssistantVoice: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = VOAssistantVoice()

    static let personas: [VOVoicePersona] = [
        VOVoicePersona(id: "jarvis", name: "Jarvis", tagline: "Authoritative and strong", systemVoice: "Daniel", language: "en-GB"),
        VOVoicePersona(id: "samantha", name: "Samantha", tagline: "Warm and friendly", systemVoice: "Samantha", language: "en-US"),
        VOVoicePersona(id: "karen", name: "Karen", tagline: "Bright and upbeat", systemVoice: "Karen", language: "en-AU"),
        VOVoicePersona(id: "moira", name: "Moira", tagline: "Calm and soothing", systemVoice: "Moira", language: "en-IE"),
        VOVoicePersona(id: "rishi", name: "Rishi", tagline: "Clear and steady", systemVoice: "Rishi", language: "en-IN"),
        VOVoicePersona(id: "tessa", name: "Tessa", tagline: "Crisp and professional", systemVoice: "Tessa", language: "en-ZA"),
        VOVoicePersona(id: "fred", name: "Fred", tagline: "Classic and robotic", systemVoice: "Fred", language: "en-US"),
    ]

    @Published var spokenUpTo: Int = 0       // characters spoken so far
    @Published var speaking = false
    @Published var currentText = ""

    private let synth = AVSpeechSynthesizer()
    private var onFinish: (() -> Void)?

    override init() {
        super.init()
        synth.delegate = self
    }

    static func persona(_ id: String) -> VOVoicePersona { personas.first { $0.id == id } ?? personas[0] }

    static func voice(for persona: VOVoicePersona) -> AVSpeechSynthesisVoice? {
        let all = AVSpeechSynthesisVoice.speechVoices().filter { $0.name == persona.systemVoice }
        return all.max(by: { $0.quality.rawValue < $1.quality.rawValue }) ?? AVSpeechSynthesisVoice(language: persona.language)
    }

    func speak(_ text: String, completion: (() -> Void)? = nil) {
        stop()
        let s = VOSettings.shared
        currentText = text
        spokenUpTo = 0
        guard s.agentVoiceEnabled, !text.isEmpty else {
            spokenUpTo = text.count
            completion?()
            return
        }
        onFinish = completion
        let u = AVSpeechUtterance(string: text)
        u.voice = Self.voice(for: Self.persona(s.agentVoice))
        u.rate = s.agentVoiceSpeed.rate
        u.pitchMultiplier = s.agentVoice == "jarvis" ? 0.92 : 1.0
        speaking = true
        synth.speak(u)
    }

    func preview(_ personaID: String) {
        let p = Self.persona(personaID)
        stop()
        let u = AVSpeechUtterance(string: "Hi, I'm \(p.name). What can I do for you?")
        u.voice = Self.voice(for: p)
        u.rate = VOSettings.shared.agentVoiceSpeed.rate
        synth.speak(u)
    }

    func stop() {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        speaking = false
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        let upTo = characterRange.location + characterRange.length
        Task { @MainActor in self.spokenUpTo = upTo }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.spokenUpTo = self.currentText.count
            self.speaking = false
            let f = self.onFinish
            self.onFinish = nil
            f?()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.spokenUpTo = self.currentText.count
            self.speaking = false
            self.onFinish = nil
        }
    }
}
