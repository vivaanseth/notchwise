// SPDX-License-Identifier: GPL-3.0-or-later
// Ported from VoiceOS Clone (UI/Main/DictationSettingsView.swift) into Vorssaint + VoiceOS.

import SwiftUI

struct VODictationSettingsView: View {
    @ObservedObject private var settings = VOSettings.shared
    @ObservedObject private var providers = VOProviderManager.shared
    @ObservedObject private var downloader = VOModelDownloader.shared
    @State private var newSpoken = ""
    @State private var newWritten = ""
    @State private var mics: [VOAudioDevices.Device] = []
    @State private var modelsTick = 0

    private let languages: [(String, String)] = [
        ("en-US", "English (US)"), ("en-GB", "English (UK)"), ("en-AU", "English (Australia)"), ("en-IN", "English (India)"),
        ("es-ES", "Español"), ("es-MX", "Español (México)"), ("fr-FR", "Français"), ("de-DE", "Deutsch"), ("it-IT", "Italiano"),
        ("pt-BR", "Português (Brasil)"), ("ja-JP", "日本語"), ("ko-KR", "한국어"), ("zh-CN", "中文 (简体)"), ("nl-NL", "Nederlands"),
    ]

    var body: some View {
        VOPageScaffold(title: "Dictation") {
            VOCard {
                VOCardHeader(symbol: "keyboard", title: "Shortcut", subtitle: "Hold the key, speak, let go. Your words land wherever the cursor is.") {
                    VOSegmentedPill(options: VODictationTrigger.allCases.map { ($0, $0.label) }, selection: $settings.dictationTrigger, compact: true)
                }
                if let note = VOHotkeyConflicts.note(for: settings.dictationTrigger.keyCodes) {
                    Label(note, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12.5)).foregroundColor(VOTheme.orange)
                }
                toggleRow("Double-tap for hands-free", "Tap the key twice to keep listening, tap once more to finish.", $settings.doubleTapHandsFree)
                if settings.dictationTrigger == .fn {
                    HStack(spacing: 12) {
                        Image(systemName: "globe").foregroundColor(VOTheme.secondary)
                        Text("Set System Settings → Keyboard → “Press 🌐 key to” to **Do Nothing** so the fn key doesn't open the emoji picker.")
                            .font(.system(size: 12.5)).foregroundColor(VOTheme.secondary)
                        Spacer()
                        Button("Open Keyboard Settings") { VOSystemSettings.openKeyboard() }.buttonStyle(VOSecondaryButtonStyle())
                    }
                }
            }

            VOCard {
                VOCardHeader(symbol: "waveform", title: "Speech recognition", subtitle: "Runs entirely on this Mac — your audio never leaves it.") {
                    VOSegmentedPill(options: VOSpeechEngine.allCases.map { ($0, $0.label) }, selection: $settings.speechEngine, compact: true)
                }
                Text(settings.speechEngine.detail).font(.system(size: 12.5)).foregroundColor(VOTheme.secondary)
                HStack {
                    Text("Language").font(.system(size: 14))
                    Spacer()
                    VODropdown(options: languages, selection: $settings.languageCode, width: 220)
                }
                if settings.speechEngine == .whisper { whisperSection }
            }

            VOCard {
                VOCardHeader(symbol: "wand.and.stars", title: "AI polish",
                           subtitle: "Removes filler, fixes grammar and formats for the app you're in. Local AI keeps it free and on this Mac.")
                VOSegmentedPill(options: VOPolishEngine.allCases.map { ($0, $0.label) }, selection: $settings.polishEngine)
                if let p = settings.polishEngine.provider {
                    let st = providers.status[p] ?? .unknown
                    HStack(spacing: 8) {
                        VOStatusDot(color: st.color)
                        Text("\(p.displayName): \(st.label)").font(.system(size: 12.5)).foregroundColor(VOTheme.secondary)
                        if !st.isReady {
                            Button("Connect") { VOMainWindow.show(.apps) }.buttonStyle(.plain).foregroundColor(VOTheme.accent).font(.system(size: 12.5, weight: .semibold))
                        }
                    }
                    Text(p.isLocal
                         ? "Phrases under six words skip the model entirely. If the local model is slow, the basic cleanup goes in instead so you're never waiting."
                         : "If \(p.displayName) is slow or unavailable, VoiceOS inserts the on-device cleanup instead so you're never stuck.")
                        .font(.system(size: 12)).foregroundColor(VOTheme.tertiary)
                }
                toggleRow("Remove filler words", "Drops um, uh, repeated words and false starts.", $settings.removeFillers)
                toggleRow("Write to fit the app", "Emails get greetings and sign-offs, chats stay casual, notes become lists.", $settings.appAwareStyle)
                toggleRow("Sound effects", "A soft tick when listening starts and stops.", $settings.playSounds)
            }

            VOCard {
                VOCardHeader(symbol: "mic", title: "Microphone") {
                    VODropdown(options: [("", "System default")] + mics.map { ($0.id, $0.name) },
                               selection: $settings.microphoneUID, width: 260)
                }
            }

            VOCard {
                VOCardHeader(symbol: "character.book.closed", title: "Dictionary",
                           subtitle: "Names, products, acronyms — say them however they come out and VoiceOS writes them your way.")
                VStack(spacing: 8) {
                    ForEach(settings.dictionary) { e in
                        HStack(spacing: 12) {
                            Text("“\(e.spoken)”").font(.system(size: 14)).foregroundColor(VOTheme.secondary).frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "arrow.right").font(.system(size: 11)).foregroundColor(VOTheme.tertiary)
                            Text(e.written).font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity, alignment: .leading)
                            Button { settings.dictionary.removeAll { $0.id == e.id } } label: {
                                Image(systemName: "minus.circle.fill").foregroundColor(VOTheme.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 40)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04)))
                    }
                }
                HStack(spacing: 10) {
                    VODarkField(placeholder: "Sounds like… (e.g. super base)", text: $newSpoken)
                    VODarkField(placeholder: "Write it as… (e.g. Supabase)", text: $newWritten)
                    Button("Add") {
                        let w = newWritten.trimmingCharacters(in: .whitespaces)
                        guard !w.isEmpty else { return }
                        let s = newSpoken.trimmingCharacters(in: .whitespaces)
                        settings.dictionary.append(VODictionaryEntry(spoken: s.isEmpty ? w.lowercased() : s, written: w))
                        newSpoken = ""; newWritten = ""
                    }
                    .buttonStyle(VOPrimaryButtonStyle())
                }
            }

            VOCard {
                VOCardHeader(symbol: "lock", title: "Privacy", subtitle: "What you say stays yours.")
                toggleRow("Save transcripts on this device", "History lives only in ~/Library/Application Support.", $settings.saveHistory)
                toggleRow("Don't save audio anywhere", "Recordings are processed in memory and discarded.", .constant(true)).disabled(true)
                toggleRow("Never use my dictation to train AI models", "Only the transcript text is sent to the AI you pick, and only for cleanup.", $settings.neverTrain)
                toggleRow("Send anonymous diagnostics", "This clone never sends any telemetry — the switch is here for parity.", $settings.diagnostics)
            }
        }
        .onAppear { mics = VOAudioDevices.inputDevices() }
    }

    private var whisperSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if VOWhisper.binary == nil {
                Label("whisper-cli not found — install with: brew install whisper-cpp", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12.5)).foregroundColor(VOTheme.orange)
            }
            let _ = modelsTick
            ForEach(VOWhisperModel.allCases) { m in
                HStack(spacing: 12) {
                    Image(systemName: settings.whisperModel == m ? "largecircle.fill.circle" : "circle")
                        .foregroundColor(settings.whisperModel == m ? VOTheme.accent : VOTheme.tertiary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.label).font(.system(size: 13.5, weight: .medium))
                        Text(m.sizeLabel).font(.system(size: 11.5)).foregroundColor(VOTheme.tertiary)
                    }
                    Spacer()
                    if let p = downloader.progress[m] {
                        ProgressView(value: p).frame(width: 120)
                        Text("\(Int(p * 100))%").font(.system(size: 12)).foregroundColor(VOTheme.secondary).frame(width: 36)
                    } else if VOWhisper.modelURL(m) != nil {
                        Label("Installed", systemImage: "checkmark.circle.fill").font(.system(size: 12.5)).foregroundColor(VOTheme.green)
                    } else {
                        Button("Download") { downloader.download(m) }.buttonStyle(VOSecondaryButtonStyle())
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { settings.whisperModel = m }
                if let err = downloader.errors[m] {
                    Text(err).font(.system(size: 11.5)).foregroundColor(VOTheme.orange)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.03)))
        .onChange(of: downloader.progress) { _, _ in modelsTick += 1 }
    }

    private func toggleRow(_ title: String, _ sub: String, _ binding: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14))
                Text(sub).font(.system(size: 12)).foregroundColor(VOTheme.tertiary)
            }
            Spacer()
            VOToggle(isOn: binding)
        }
    }
}
