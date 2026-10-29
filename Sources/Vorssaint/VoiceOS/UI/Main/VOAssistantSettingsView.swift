// SPDX-License-Identifier: GPL-3.0-or-later
// Ported from VoiceOS Clone (UI/Main/AgentSettingsView.swift) into Vorssaint + VoiceOS.

import SwiftUI

struct VOAssistantSettingsView: View {
    @ObservedObject private var settings = VOSettings.shared
    @ObservedObject private var providers = VOProviderManager.shared
    @State private var showMemory = false
    @State private var newMemory = ""

    var body: some View {
        VOPageScaffold(title: "Assistant") {
            VOCard {
                VOCardHeader(symbol: "sparkles", title: "Assistant voice", subtitle: "Choose the voice used for short Assistant Mode confirmations.") {
                    HStack(spacing: 14) {
                        VOSegmentedPill(options: VOVoiceSpeed.allCases.map { ($0, $0.label) }, selection: $settings.agentVoiceSpeed, compact: true)
                        VOToggle(isOn: $settings.agentVoiceEnabled, onColor: .white, knob: .black)
                    }
                }
                let persona = VOAssistantVoice.persona(settings.agentVoice)
                VODropdown(options: VOAssistantVoice.personas.map { ($0.id, "\($0.name) — \($0.tagline)") },
                           selection: $settings.agentVoice,
                           onPick: { VOAssistantVoice.shared.preview($0) }) {
                    HStack(spacing: 12) {
                        VOJarvisGlyph(size: 26)
                        Text(persona.name).font(.system(size: 15.5, weight: .semibold)).foregroundColor(.white)
                        Text(persona.tagline).font(.system(size: 14)).foregroundColor(VOTheme.secondary)
                        Spacer()
                        Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold)).foregroundColor(VOTheme.secondary)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 56)
                    .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(VOTheme.cardRaised))
                    .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(VOTheme.border, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .opacity(settings.agentVoiceEnabled ? 1 : 0.5)
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Natural voice").font(.system(size: 14))
                        Text(VOKokoro.isInstalled
                             ? "Kokoro, a neural voice, on this Mac. Each sentence takes a moment to render; Fred stays robotic."
                             : "Install Kokoro with Tools/install-kokoro.sh to hear a neural voice instead of the system one.")
                            .font(.system(size: 12)).foregroundColor(VOTheme.tertiary)
                    }
                    Spacer()
                    VOToggle(isOn: $settings.agentNaturalVoice)
                        .disabled(!VOKokoro.isInstalled)
                }
                .opacity(settings.agentVoiceEnabled ? 1 : 0.5)
            }

            VOCard {
                VOCardHeader(symbol: "cpu", title: "Assistant brain", subtitle: "Which AI answers when you hold \(settings.agentTrigger.label). Local is free and private; cloud AIs use your own plan.") {
                    Button("Manage") { VOMainWindow.show(.apps) }.buttonStyle(VOSecondaryButtonStyle())
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(VOProviderID.allCases) { p in brainOption(p) }
                }
                if settings.agentProvider.isLocal {
                    VOEscalationSettings()
                }
                HStack {
                    Text("Hold to talk").font(.system(size: 14))
                    Spacer()
                    VOSegmentedPill(options: VOAssistantTrigger.allCases.map { ($0, $0.label) }, selection: $settings.agentTrigger, compact: true)
                }
                if let note = VOHotkeyConflicts.note(for: settings.agentTrigger.keyCodes) {
                    Label(note, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12.5)).foregroundColor(VOTheme.orange)
                }
            }

            VOCard {
                VOCardHeader(symbol: "person", title: "About you", subtitle: "Your name and the things the assistant has learned about you from your conversations.")
                HStack(spacing: 12) {
                    VODarkField(placeholder: "First name", text: $settings.firstName)
                    VODarkField(placeholder: "Last name", text: $settings.lastName)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Button { withAnimation { showMemory.toggle() } } label: {
                        HStack {
                            Text("Memory").font(.system(size: 14.5, weight: .semibold)).foregroundColor(.white)
                            Text("\(settings.memories.count)").font(.system(size: 12)).foregroundColor(VOTheme.tertiary)
                            Spacer()
                            Text(showMemory ? "Hide" : "Show").font(.system(size: 13.5, weight: .medium)).foregroundColor(.white.opacity(0.85))
                            Image(systemName: showMemory ? "chevron.up" : "chevron.down").font(.system(size: 11, weight: .semibold)).foregroundColor(.white.opacity(0.7))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if showMemory {
                        if settings.memories.isEmpty {
                            Text("Nothing yet. Tell the assistant things like “my manager is Tommy” and it'll remember.")
                                .font(.system(size: 12.5)).foregroundColor(VOTheme.tertiary)
                        }
                        ForEach(settings.memories, id: \.self) { m in
                            HStack {
                                Text(m).font(.system(size: 13.5)).foregroundColor(.white.opacity(0.9))
                                Spacer()
                                Button { settings.memories.removeAll { $0 == m } } label: {
                                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundColor(VOTheme.tertiary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 4)
                        }
                        HStack(spacing: 10) {
                            VODarkField(placeholder: "Add something to remember", text: $newMemory)
                            Button("Add") { settings.addMemory(newMemory); newMemory = "" }.buttonStyle(VOPrimaryButtonStyle())
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(VOTheme.cardRaised))
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(VOTheme.border, lineWidth: 1))
            }

            VOCard {
                VOCardHeader(symbol: "bolt", title: "Actions", subtitle: "Common system actions the assistant can perform.")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 26), GridItem(.flexible(), spacing: 26)], spacing: 18) {
                    ForEach(VOAssistantCapability.allCases) { cap in actionTile(cap) }
                }
                if settings.isEnabled(.pointAndAsk) && !VOPermissions.shared.screen {
                    HStack(spacing: 10) {
                        Image(systemName: "rectangle.dashed.badge.record").foregroundColor(VOTheme.orange)
                        Text("Point and ask needs Screen Recording permission.").font(.system(size: 12.5)).foregroundColor(VOTheme.secondary)
                        Spacer()
                        Button("Allow") { VOPermissions.shared.requestScreen() }.buttonStyle(VOSecondaryButtonStyle())
                    }
                }
            }
        }
    }

    private func brainOption(_ p: VOProviderID) -> some View {
        let selected = settings.agentProvider == p
        let st = providers.status[p] ?? .unknown
        return Button { settings.agentProvider = p } label: {
            HStack(spacing: 10) {
                VOProviderLogo(provider: p, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.displayName).font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                    HStack(spacing: 5) {
                        VOStatusDot(color: st.color)
                        Text(st.label).font(.system(size: 11.5)).foregroundColor(VOTheme.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(selected ? VOTheme.accent : VOTheme.tertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(selected ? VOTheme.accent.opacity(0.12) : VOTheme.cardRaised))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(selected ? VOTheme.accent.opacity(0.6) : VOTheme.border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func actionTile(_ cap: VOAssistantCapability) -> some View {
        HStack(spacing: 14) {
            Image(systemName: cap.symbol)
                .font(.system(size: 15))
                .foregroundColor(.white.opacity(0.85))
                .frame(width: 42, height: 42)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(VOTheme.cardRaised))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(VOTheme.border, lineWidth: 1))
            VStack(alignment: .leading, spacing: 2) {
                Text(cap.title).font(.system(size: 14.5, weight: .semibold)).lineLimit(1)
                Text(cap.subtitle).font(.system(size: 12.5)).foregroundColor(VOTheme.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            VOToggle(isOn: Binding(get: { settings.isEnabled(cap) }, set: { settings.setEnabled(cap, $0) }))
        }
    }
}
