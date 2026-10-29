// SPDX-License-Identifier: GPL-3.0-or-later
// Ported from VoiceOS Clone (Speech/SpeechVoice.swift) into Vorssaint + VoiceOS.

import AVFoundation

struct VOVoicePersona: Identifiable, Hashable {
    let id: String
    let name: String
    let tagline: String
    let systemVoice: String
    let language: String
    /// Its Kokoro voice, when it has one: Kokoro v1.0's number for it and
    /// the accent its words are looked up in.
    var kokoro: VOKokoroVoice? = nil
}

struct VOKokoroVoice: Hashable {
    let sid: Int
    let accent: String
}

/// Spoken agent replies: Kokoro's natural voice when it is installed and on,
/// else the system voices. Publishes how far it has spoken so the notch can
/// paint words white as they're said and leave the rest grey.
@MainActor
final class VOAssistantVoice: NSObject, ObservableObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    static let shared = VOAssistantVoice()

    static let personas: [VOVoicePersona] = [
        VOVoicePersona(id: "jarvis", name: "Jarvis", tagline: "Authoritative and strong", systemVoice: "Daniel", language: "en-GB",
                       kokoro: VOKokoroVoice(sid: 26, accent: "gb")),      // bm_george
        VOVoicePersona(id: "samantha", name: "Samantha", tagline: "Warm and friendly", systemVoice: "Samantha", language: "en-US",
                       kokoro: VOKokoroVoice(sid: 3, accent: "us")),       // af_heart
        VOVoicePersona(id: "karen", name: "Karen", tagline: "Bright and upbeat", systemVoice: "Karen", language: "en-AU",
                       kokoro: VOKokoroVoice(sid: 2, accent: "us")),       // af_bella
        VOVoicePersona(id: "moira", name: "Moira", tagline: "Calm and soothing", systemVoice: "Moira", language: "en-IE",
                       kokoro: VOKokoroVoice(sid: 21, accent: "gb")),      // bf_emma
        VOVoicePersona(id: "rishi", name: "Rishi", tagline: "Clear and steady", systemVoice: "Rishi", language: "en-IN",
                       kokoro: VOKokoroVoice(sid: 16, accent: "us")),      // am_michael
        VOVoicePersona(id: "tessa", name: "Tessa", tagline: "Crisp and professional", systemVoice: "Tessa", language: "en-ZA",
                       kokoro: VOKokoroVoice(sid: 22, accent: "gb")),      // bf_isabella
        // Fred is robotic on purpose.
        VOVoicePersona(id: "fred", name: "Fred", tagline: "Classic and robotic", systemVoice: "Fred", language: "en-US"),
    ]

    @Published var spokenUpTo: Int = 0       // characters spoken so far
    @Published var speaking = false
    @Published var currentText = ""

    private let synth = AVSpeechSynthesizer()
    private var onFinish: (() -> Void)?
    /// A streamed answer: how much of `currentText` has gone to the voice,
    /// where each queued sentence starts in it (by utterance, or by Kokoro
    /// sentence), and whether more may come.
    private var handedOff = 0
    private var offsets: [AnyHashable: Int] = [:]
    private var streaming = false

    /// Kokoro's sentences in speaking order, the first playing or next: the
    /// next is rendered while one plays. One it could not render is spoken
    /// by the system voice in its turn.
    private struct Sentence {
        let id: Int
        let start: Int
        let text: String
        let voice: VOKokoroVoice
        var audio: URL?
        var failed = false
    }
    private var sentences: [Sentence] = []
    private var sentenceCount = 0
    private var rendering = false
    private var player: AVAudioPlayer?
    private var playing: Int?
    private var progress: Timer?
    /// Bumped by `stop`, so a sentence rendered for an answer that was stopped is dropped.
    private var generation = 0

    override init() {
        super.init()
        synth.delegate = self
    }

    static func persona(_ id: String) -> VOVoicePersona { personas.first { $0.id == id } ?? personas[0] }

    /// The Kokoro voice to speak in: the persona's, while Kokoro is installed and on.
    static func kokoroVoice(for persona: VOVoicePersona) -> VOKokoroVoice? {
        guard VOSettings.shared.agentNaturalVoice, VOKokoro.isInstalled else { return nil }
        return persona.kokoro
    }

    /// Loads Kokoro while the question is still being asked or answered.
    func warmUp() {
        guard VOSettings.shared.agentVoiceEnabled, let voice = Self.kokoroVoice(for: Self.persona(VOSettings.shared.agentVoice)) else { return }
        VOKokoro.shared.warmUp(accent: voice.accent)
    }

    static func voice(for persona: VOVoicePersona) -> AVSpeechSynthesisVoice? {
        let all = AVSpeechSynthesisVoice.speechVoices().filter { $0.name == persona.systemVoice }
        return all.max(by: { $0.quality.rawValue < $1.quality.rawValue }) ?? AVSpeechSynthesisVoice(language: persona.language)
    }

    // MARK: Streaming

    /// A new answer is being written: anything still speaking stops, and the
    /// sentences that follow are spoken as each one is complete.
    func beginStream() {
        stop()
        warmUp()
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
        say(chunk, at: start, persona: Self.persona(VOSettings.shared.agentVoice))
    }

    /// Kokoro takes it a sentence at a time, so the first is heard while
    /// the rest render; the system voice takes it whole.
    private func say(_ chunk: String, at start: Int, persona: VOVoicePersona) {
        speaking = true
        guard let voice = Self.kokoroVoice(for: persona) else {
            let u = utterance(chunk, persona: persona)
            offsets[ObjectIdentifier(u)] = start
            synth.speak(u)
            return
        }
        var from = 0
        let characters = Array(chunk)
        while from < characters.count {
            let to = Self.firstSentenceEnd(in: characters, from: from)
            let text = String(characters[from..<to])
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sentenceCount += 1
                sentences.append(Sentence(id: sentenceCount, start: start + from, text: text, voice: voice))
                offsets[sentenceCount] = start + from
            }
            from = to
        }
        renderNext()
        playNext()
    }

    /// Past the first full stop, question or exclamation mark after `from` that whitespace follows.
    private static func firstSentenceEnd(in characters: [Character], from: Int) -> Int {
        var index = from
        while index < characters.count - 1 {
            if ".!?\n".contains(characters[index]), characters[index + 1].isWhitespace { return index + 1 }
            index += 1
        }
        return characters.count
    }

    private func renderNext() {
        guard !rendering, let next = sentences.first(where: { $0.audio == nil && !$0.failed }) else { return }
        rendering = true
        let generation = generation
        let speed = VOSettings.shared.agentVoiceSpeed.kokoroSpeed
        Task {
            let audio = try? await VOKokoro.shared.render(next.text, sid: next.voice.sid, accent: next.voice.accent, speed: speed)
            guard generation == self.generation else {
                if let audio { try? FileManager.default.removeItem(at: audio) }
                return
            }
            self.rendering = false
            if let index = self.sentences.firstIndex(where: { $0.id == next.id }) {
                if let audio { self.sentences[index].audio = audio } else { self.sentences[index].failed = true }
            }
            self.playNext()
            self.renderNext()
        }
    }

    /// The first sentence, once it is rendered: played, or handed to the
    /// system voice if Kokoro could not render it.
    private func playNext() {
        guard player == nil, playing == nil, let first = sentences.first else { return }
        if first.failed {
            sentences.removeFirst()
            offsets.removeValue(forKey: first.id)
            let u = utterance(first.text, persona: Self.persona(VOSettings.shared.agentVoice))
            offsets[ObjectIdentifier(u)] = first.start
            playing = first.id
            synth.speak(u)
            return
        }
        guard let audio = first.audio, let player = try? AVAudioPlayer(contentsOf: audio) else { return }
        player.delegate = self
        self.player = player
        playing = first.id
        player.play()
        let progress = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.showProgress() }
        }
        RunLoop.main.add(progress, forMode: .common)
        self.progress = progress
    }

    /// Words light up as the sentence plays, at the pace it is spoken.
    private func showProgress() {
        guard let player, let sentence = sentences.first, sentence.id == playing, player.duration > 0 else { return }
        let share = min(1, player.currentTime / player.duration)
        spokenUpTo = max(spokenUpTo, sentence.start + Int(Double(sentence.text.count) * share))
    }

    private func sentenceEnded() {
        progress?.invalidate()
        progress = nil
        player = nil
        guard let id = playing else { return }
        playing = nil
        if let index = sentences.firstIndex(where: { $0.id == id }) {
            if let audio = sentences[index].audio { try? FileManager.default.removeItem(at: audio) }
            sentences.remove(at: index)
        }
        finished(id)
    }

    /// One queued sentence or utterance is done: the next goes on, or the voice waits for more, or it is through.
    private func finished(_ key: AnyHashable) {
        guard offsets.removeValue(forKey: key) != nil else { return }
        if let base = offsets.values.min() { spokenUpTo = base; playNext(); return }
        // Between sentences of an answer still being written, the voice waits.
        if streaming { spokenUpTo = handedOff; return }
        finishSpeaking()
    }

    private func utterance(_ text: String, persona: VOVoicePersona) -> AVSpeechUtterance {
        let u = AVSpeechUtterance(string: text)
        u.voice = Self.voice(for: persona)
        u.rate = VOSettings.shared.agentVoiceSpeed.rate
        u.pitchMultiplier = persona.id == "jarvis" ? 0.92 : 1.0
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
        handedOff = text.count
        say(text, at: 0, persona: Self.persona(s.agentVoice))
    }

    func preview(_ personaID: String) {
        let p = Self.persona(personaID)
        stop()
        let sample = "Hi, I'm \(p.name). What can I do for you?"
        currentText = sample
        say(sample, at: 0, persona: p)
    }

    func stop() {
        streaming = false
        offsets.removeAll()
        onFinish = nil
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        generation += 1
        rendering = false
        progress?.invalidate()
        progress = nil
        player?.stop()
        player = nil
        playing = nil
        for sentence in sentences { if let audio = sentence.audio { try? FileManager.default.removeItem(at: audio) } }
        sentences.removeAll()
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
            // A sentence Kokoro could not render, spoken in its turn.
            if self.playing != nil, self.player == nil { self.playing = nil }
            self.finished(id)
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard player === self.player else { return }
            self.sentenceEnded()
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            guard player === self.player else { return }
            self.sentenceEnded()
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
