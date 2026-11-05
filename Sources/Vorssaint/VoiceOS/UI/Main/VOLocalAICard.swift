// SPDX-License-Identifier: GPL-3.0-or-later
// Ported from VoiceOS Clone (UI/Main/LocalAICard.swift) into Vorssaint + VoiceOS.

import SwiftUI

/// Apps → AI Models: the free on-device brain (Ollama).
struct VOLocalAICard: View {
    @ObservedObject private var settings = VOSettings.shared
    @ObservedObject private var providers = VOProviderManager.shared
    @ObservedObject private var lm = VOLocalModels.shared
    @State private var starting = false

    private var status: VOProviderStatus { providers.status[.ollama] ?? .unknown }

    var body: some View {
        VOCard {
            HStack(spacing: 14) {
                VOProviderLogo(provider: .ollama, size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Local AI").font(.system(size: 17, weight: .semibold))
                        Text(lm.version.isEmpty ? "Ollama" : "Ollama \(lm.version)").font(.system(size: 13)).foregroundColor(VOTheme.tertiary)
                        if settings.agentProvider == .ollama { badge("ASSISTANT", VOTheme.accent) }
                        if settings.polishEngine == .ollama { badge("DICTATION", VOTheme.green) }
                    }
                    HStack(spacing: 6) {
                        if status == .checking || starting { ProgressView().controlSize(.mini) } else { VOStatusDot(color: status.color) }
                        Text(starting ? "Starting Ollama…" : status.label).font(.system(size: 12.5)).foregroundColor(VOTheme.secondary)
                    }
                }
                Spacer()
                if !lm.running {
                    Button(VOLocalModels.isInstalled ? "Start Ollama" : "Get Ollama") {
                        if VOLocalModels.isInstalled {
                            starting = true
                            Task {
                                await lm.start()
                                starting = false
                                providers.refreshStatus(.ollama)
                                lm.warmUp()
                            }
                        } else {
                            NSWorkspace.shared.open(URL(string: "https://ollama.com/download/mac")!)
                        }
                    }
                    .buttonStyle(VOPrimaryButtonStyle())
                }
            }

            Text("Runs free on this Mac's CPU — nothing you say leaves the computer. Notchwise uses it for everything it can, and only hands a request to a cloud AI when it truly needs one (set that up on the Assistant page).")
                .font(.system(size: 13)).foregroundColor(VOTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 18) {
                modelPicker("Assistant & edits", selection: $settings.localModel)
                modelPicker("Dictation", selection: $settings.localDictationModel)
                Spacer()
            }
            if settings.localModel != settings.localDictationModel {
                Label("Two different models both stay in memory. On an 8 GB Mac, using one for both is smoother.",
                      systemImage: "memorychip")
                    .font(.system(size: 12)).foregroundColor(VOTheme.orange)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Recommended for this Mac").font(.system(size: 12, weight: .semibold)).foregroundColor(VOTheme.tertiary)
                ForEach(VOLocalModelCatalog.recommended) { m in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                Text(m.name).font(.system(size: 13.5, weight: .semibold, design: .monospaced))
                                Text(m.size).font(.system(size: 11.5)).foregroundColor(VOTheme.tertiary)
                            }
                            Text(m.note).font(.system(size: 12)).foregroundColor(VOTheme.secondary)
                        }
                        Spacer()
                        if let p = lm.pulling[m.name] {
                            ProgressView(value: p).frame(width: 110)
                            Text("\(Int(p * 100))%").font(.system(size: 12)).foregroundColor(VOTheme.secondary).frame(width: 36)
                        } else if lm.has(m.name) {
                            if settings.localModel == m.name && settings.localDictationModel == m.name {
                                Label("In use", systemImage: "checkmark.circle.fill").font(.system(size: 12.5)).foregroundColor(VOTheme.green)
                            } else {
                                Button("Use") {
                                    settings.localModel = m.name
                                    settings.localDictationModel = m.name
                                }
                                .buttonStyle(VOSecondaryButtonStyle())
                            }
                        } else {
                            Button("Download") { lm.pull(m.name) }
                                .buttonStyle(VOSecondaryButtonStyle())
                                .disabled(!VOLocalModels.isInstalled)
                        }
                    }
                    if let err = lm.pullErrors[m.name] {
                        Text(err).font(.system(size: 11.5)).foregroundColor(VOTheme.orange)
                    }
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.03)))

            HStack(spacing: 10) {
                Button {
                    providers.test(.ollama)
                } label: {
                    HStack(spacing: 6) {
                        if providers.testing.contains(.ollama) { ProgressView().controlSize(.small) }
                        Text(providers.testing.contains(.ollama) ? "Testing…" : "Test local model")
                    }
                }
                .buttonStyle(VOSecondaryButtonStyle())
                .disabled(!lm.running || providers.testing.contains(.ollama))
                Button("Use for Assistant") { settings.agentProvider = .ollama }
                    .buttonStyle(VOSecondaryButtonStyle()).disabled(settings.agentProvider == .ollama)
                Button("Use for Dictation") { settings.polishEngine = .ollama }
                    .buttonStyle(VOSecondaryButtonStyle()).disabled(settings.polishEngine == .ollama)
                Spacer()
                let t = providers.totals(for: .ollama)
                Text("\(providers.todayRequests(.ollama)) local requests today · \(t.requests) in 30 days")
                    .font(.system(size: 12)).foregroundColor(VOTheme.tertiary)
            }
            if let t = providers.tests[.ollama] {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: t.ok ? "checkmark.circle.fill" : "xmark.octagon.fill").foregroundColor(t.ok ? VOTheme.green : VOTheme.orange)
                    Text(t.ok ? "Local model answered in \(String(format: "%.1f", locale: .current, t.seconds))s" : t.message)
                        .font(.system(size: 12.5)).foregroundColor(.white.opacity(0.85))
                }
            }
        }
        .task { await lm.refresh() }
    }

    private func modelPicker(_ title: String, selection: Binding<String>) -> some View {
        var options = lm.installed.map { ($0.name, "\($0.name)  ·  \($0.sizeLabel)") }
        if !options.contains(where: { $0.0 == selection.wrappedValue }) {
            options.append((selection.wrappedValue, "\(selection.wrappedValue) (not downloaded)"))
        }
        return VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundColor(VOTheme.tertiary)
            VODropdown(options: options, selection: selection, width: 250) { _ in
                providers.refreshStatus(.ollama)
                lm.warmUp()
            }
        }
    }

    private func badge(_ t: String, _ c: Color) -> some View {
        Text(t).font(.system(size: 8.5, weight: .bold)).kerning(0.5).foregroundColor(c)
            .padding(.horizontal, 5).padding(.vertical, 2).background(Capsule().fill(c.opacity(0.15)))
    }
}

/// Agent page: when (and how stingily) the cloud AI may be used.
struct VOEscalationSettings: View {
    @ObservedObject private var settings = VOSettings.shared
    @ObservedObject private var providers = VOProviderManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Use a bigger AI only when needed").font(.system(size: 14.5, weight: .semibold))
                    Text("Questions about your screen, long or careful writing, big selections, or when the local model asks for help. Everything else stays on this Mac.")
                        .font(.system(size: 12.5)).foregroundColor(VOTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                VOToggle(isOn: $settings.escalationEnabled)
            }
            if settings.escalationEnabled {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Hand off to").font(.system(size: 12, weight: .semibold)).foregroundColor(VOTheme.tertiary)
                        VODropdown(options: VOProviderID.allCases.filter { !$0.isLocal }.map { ($0, $0.displayName) },
                                   selection: $settings.escalationProvider, width: 150)
                    }
                    if settings.escalationProvider == .claude {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Claude model").font(.system(size: 12, weight: .semibold)).foregroundColor(VOTheme.tertiary)
                            VODropdown(options: [("haiku", "Haiku · cheapest"), ("sonnet", "Sonnet · harder tasks")],
                                       selection: $settings.escalationModel, width: 190)
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Daily limit").font(.system(size: 12, weight: .semibold)).foregroundColor(VOTheme.tertiary)
                        HStack(spacing: 8) {
                            Button { settings.escalationDailyLimit = max(1, settings.escalationDailyLimit - 5) } label: {
                                Image(systemName: "minus").frame(width: 26, height: 26)
                            }
                            .buttonStyle(.plain).background(RoundedRectangle(cornerRadius: 8).fill(VOTheme.field))
                            Text("\(settings.escalationDailyLimit)").font(.system(size: 14, weight: .semibold)).frame(minWidth: 28)
                            Button { settings.escalationDailyLimit = min(500, settings.escalationDailyLimit + 5) } label: {
                                Image(systemName: "plus").frame(width: 26, height: 26)
                            }
                            .buttonStyle(.plain).background(RoundedRectangle(cornerRadius: 8).fill(VOTheme.field))
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        let used = providers.todayRequests(settings.escalationProvider)
                        Text("\(used) of \(settings.escalationDailyLimit) used today").font(.system(size: 12.5, weight: .medium))
                        VOUsageBar(fraction: Double(used) / Double(max(1, settings.escalationDailyLimit)),
                                 color: used >= settings.escalationDailyLimit ? VOTheme.orange : VOTheme.accent, height: 5)
                            .frame(width: 140)
                    }
                }
                Text("Claude runs with extended thinking off and only ever sees the one request it's handed.")
                    .font(.system(size: 12)).foregroundColor(VOTheme.tertiary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(VOTheme.cardRaised))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(VOTheme.border, lineWidth: 1))
    }
}
