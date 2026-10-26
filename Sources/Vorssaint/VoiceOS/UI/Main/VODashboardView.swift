// SPDX-License-Identifier: GPL-3.0-or-later
// Ported from VoiceOS Clone (UI/Main/DashboardView.swift) into Vorssaint + VoiceOS.

import SwiftUI

struct VODashboardView: View {
    @ObservedObject private var settings = VOSettings.shared
    @ObservedObject private var history = VOHistoryStore.shared
    @ObservedObject private var perms = VOPermissions.shared
    @ObservedObject private var providers = VOProviderManager.shared

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        let part = h < 12 ? "Good morning" : (h < 18 ? "Good afternoon" : "Good evening")
        return settings.firstName.isEmpty ? part : "\(part), \(settings.firstName)"
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 14) {
                    VOOrb(size: 38)
                    Text(greeting).font(.system(size: 26, weight: .bold)).foregroundColor(.white)
                    Spacer()
                    Button { settings.onboardingDone = false } label: {
                        Label("Quick guide", systemImage: "book.closed")
                    }
                    .buttonStyle(VOSecondaryButtonStyle())
                    VOProfileButton()
                }
                .padding(.bottom, 4)

                if !perms.essentialsGranted { setupBanner }

                HStack(spacing: 16) {
                    modeCard(symbol: "mic", title: "Dictation Mode", key: settings.dictationTrigger == .fn ? "fn" : settings.dictationTrigger.label,
                             line: "in any text field", sub: "Speak naturally, polished text appears.")
                    modeCard(symbol: "sparkles", title: "Assistant Mode", key: settings.agentTrigger.keycap,
                             line: "to speak", sub: "Ask anything, or trigger an action in Messages, Mail, Calendar and more.")
                }
                .fixedSize(horizontal: false, vertical: true)

                VOSectionLabel(text: "Statistics")
                HStack(spacing: 14) {
                    VOStatTile(symbol: "waveform", title: "Total Sessions", value: "\(history.totalSessions)")
                    VOStatTile(symbol: "text.word.spacing", title: "Total Words", value: history.totalWords.formatted())
                    VOStatTile(symbol: "clock", title: "Time Saved", value: Self.duration(history.timeSavedMinutes))
                }

                HStack(alignment: .top, spacing: 16) {
                    appsUsage.frame(maxHeight: .infinity, alignment: .top)
                    modesUsage.frame(maxHeight: .infinity, alignment: .top)
                }
                .fixedSize(horizontal: false, vertical: true)

                VOSectionLabel(text: "AI connections")
                HStack(spacing: 14) {
                    ForEach(VOProviderID.allCases) { p in providerTile(p) }
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 30)
            .padding(.bottom, 48)
            .frame(maxWidth: 1000)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
    }

    static func duration(_ minutes: Double) -> String {
        if minutes < 1 { return "\(Int(minutes * 60))s" }
        if minutes < 60 { return "\(Int(minutes.rounded()))m" }
        return String(format: "%.1fh", locale: .current, minutes / 60)
    }

    private var setupBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: "hand.raised.fill").foregroundColor(VOTheme.orange).font(.system(size: 18))
            VStack(alignment: .leading, spacing: 3) {
                Text("Finish setting up VoiceOS").font(.system(size: 15, weight: .semibold))
                Text(missingText).font(.system(size: 13)).foregroundColor(VOTheme.secondary)
            }
            Spacer()
            Button("Continue setup") { settings.onboardingDone = false }.buttonStyle(VOPrimaryButtonStyle())
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(VOTheme.orange.opacity(0.09)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VOTheme.orange.opacity(0.28), lineWidth: 1))
    }

    private var missingText: String {
        var m: [String] = []
        if !perms.microphone { m.append("Microphone") }
        if !perms.accessibility { m.append("Accessibility") }
        if !perms.speech && settings.speechEngine == .apple { m.append("Speech Recognition") }
        return "Still needed: " + m.joined(separator: ", ")
    }

    private func modeCard(symbol: String, title: String, key: String, line: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 15)).foregroundColor(.white.opacity(0.85))
                Text(title).font(.system(size: 15.5, weight: .semibold))
            }
            HStack(spacing: 7) {
                Text("Hold").foregroundColor(.white.opacity(0.85))
                VOKeyCap(label: key, size: 13)
                Text(line).foregroundColor(.white.opacity(0.85))
            }
            .font(.system(size: 15))
            Text(sub).font(.system(size: 13)).foregroundColor(VOTheme.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(VOTheme.card))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(VOTheme.border, lineWidth: 1))
    }

    private var appsUsage: some View {
        let apps = history.appUsage(limit: 5)
        let maxCount = Double(apps.first?.count ?? 1)
        return VOCard {
            Text("Apps Usage").font(.system(size: 15, weight: .semibold))
            if apps.isEmpty {
                Text("Your most-used apps will show up here.").font(.system(size: 13)).foregroundColor(VOTheme.secondary)
            }
            ForEach(apps, id: \.app) { a in
                VStack(spacing: 7) {
                    HStack(spacing: 10) {
                        VOAppIconView(bundleID: a.bundleID, symbol: "app", size: 20)
                        Text(a.app).font(.system(size: 13.5))
                        Spacer()
                        Text("\(a.count)").font(.system(size: 13.5, weight: .medium)).foregroundColor(VOTheme.secondary)
                    }
                    VOUsageBar(fraction: Double(a.count) / maxCount, color: .white.opacity(0.85), height: 4)
                }
            }
        }
    }

    private var modesUsage: some View {
        let modes = history.modeUsage()
        let total = Double(max(1, modes.reduce(0) { $0 + $1.count }))
        return VOCard {
            Text("Modes Usage").font(.system(size: 15, weight: .semibold))
            ForEach(modes, id: \.mode) { m in
                VStack(spacing: 7) {
                    HStack {
                        Text(m.mode.label).font(.system(size: 13.5))
                        Spacer()
                        Text("\(m.count)").font(.system(size: 13.5, weight: .medium)).foregroundColor(VOTheme.secondary)
                    }
                    VOUsageBar(fraction: Double(m.count) / total, color: m.mode == .agent ? VOTheme.accent : .white.opacity(0.85), height: 4)
                }
            }
        }
    }

    private func providerTile(_ p: VOProviderID) -> some View {
        let status = providers.status[p] ?? .unknown
        return Button { VOMainWindow.show(.apps) } label: {
            HStack(spacing: 12) {
                VOProviderLogo(provider: p, size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(p.displayName).font(.system(size: 14.5, weight: .semibold)).foregroundColor(.white)
                        if settings.agentProvider == p {
                            Text("ASSISTANT").font(.system(size: 8.5, weight: .bold)).kerning(0.5).foregroundColor(VOTheme.accent)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Capsule().fill(VOTheme.accent.opacity(0.15)))
                        }
                    }
                    HStack(spacing: 6) {
                        VOStatusDot(color: status.color)
                        Text(status.label).font(.system(size: 12)).foregroundColor(VOTheme.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(VOTheme.card))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VOTheme.border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
