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
    /// A streamed answer: how much of `currentText` has gone to the voice,
    /// where each queued sentence starts in it, and whether more may come.
    private var handedOff = 0
    private var offsets: [ObjectIdentifier: Int] = [:]
    private var streaming = false

    override init() {
        super.init()
        synth.delegate = self
    }

    static func persona(_ id: String) -> VOVoicePersona { personas.first { $0.id == id } ?? personas[0] }

    static func voice(for persona: VOVoicePersona) -> AVSpeechSynthesisVoice? {
        let all = AVSpeechSynthesisVoice.speechVoices().filter { $0.name == persona.systemVoice }
        return all.max(by: { $0.quality.rawValue < $1.quality.rawValue }) ?? AVSpeechSynthesisVoice(language: persona.language)
    }

    // MARK: Streaming

    /// A new answer is being written: anything still speaking stops, and the
    /// sentences that follow are spoken as each one is complete.
    func beginStream() {
        stop()
        currentText = ""
        spokenUpTo = 0
        handedOff = 0
        streaming = true
    }

    /// The answer so far. Every sentence it now completes is queued, so the
    /// first is heard while the model still writes the rest.
    func stream(_ text: String) {
        guard streaming, VOSettings.shared.agentVoiceEnabled, text.count >= handedOff else { return }
        currentText = text
        guard let end = Self.lastSentenceEnd(in: text, from: handedOff) else { return }
        enqueue(from: handedOff, to: end)
    }

    /// The whole answer: what was not queued yet is spoken, then `completion`
    /// runs once the voice is done.
    func finishStream(_ text: String, completion: (() -> Void)? = nil) {
        guard streaming else { speak(text, completion: completion); return }
        streaming = false
        guard VOSettings.shared.agentVoiceEnabled, !text.isEmpty else {
            currentText = text
            spokenUpTo = text.count
            completion?()
            return
        }
        // The final text may differ from what streamed; the part already
        // queued stays as it was and only what follows it is added.
        let common = zip(currentText.prefix(handedOff), text).prefix { $0 == $1 }.count
        if common < handedOff { handedOff = common }
        currentText = text
        onFinish = completion
        if handedOff < text.count { enqueue(from: handedOff, to: text.count) }
        if offsets.isEmpty { finishSpeaking() }
    }

    /// Where the last complete sentence after `start` ends: past a full stop,
    /// question or exclamation mark that a space or line break follows.
    nonisolated static func lastSentenceEnd(in text: String, from start: Int) -> Int? {
        let characters = Array(text)
        guard characters.count > start + 1 else { return nil }
        var end: Int?
        for index in start..<(characters.count - 1) where ".!?\n".contains(characters[index]) {
            if characters[index + 1].isWhitespace { end = index + 1 }
        }
        return end
    }

    private func enqueue(from start: Int, to end: Int) {
        let chunk = String(Array(currentText)[start..<end])
        handedOff = end
        guard !chunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let u = utterance(chunk)
        offsets[ObjectIdentifier(u)] = start
        speaking = true
        synth.speak(u)
    }

    private func utterance(_ text: String) -> AVSpeechUtterance {
        let s = VOSettings.shared
        let u = AVSpeechUtterance(string: text)
        u.voice = Self.voice(for: Self.persona(s.agentVoice))
        u.rate = s.agentVoiceSpeed.rate
        u.pitchMultiplier = s.agentVoice == "jarvis" ? 0.92 : 1.0
        return u
    }

    private func finishSpeaking() {
        spokenUpTo = currentText.count
        speaking = false
        let f = onFinish
        onFinish = nil
        f?()
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
        let u = utterance(text)
        offsets[ObjectIdentifier(u)] = 0
        handedOff = text.count
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
        streaming = false
        offsets.removeAll()
        onFinish = nil
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        speaking = false
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        let upTo = characterRange.location + characterRange.length
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in
            guard let base = self.offsets[id] else { return }
            self.spokenUpTo = base + upTo
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in
            guard self.offsets.removeValue(forKey: id) != nil else { return }
            if let base = self.offsets.values.min() { self.spokenUpTo = base; return }
            // Between sentences of an answer still being written, the voice waits.
            if self.streaming { self.spokenUpTo = self.handedOff; return }
            self.finishSpeaking()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in
            guard self.offsets.removeValue(forKey: id) != nil else { return }
            self.spokenUpTo = self.currentText.count
            self.speaking = false
        }
    }
}
