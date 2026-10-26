// SPDX-License-Identifier: GPL-3.0-or-later
// Ported from VoiceOS Clone (UI/Main/AppsView.swift) into Vorssaint + VoiceOS.

import SwiftUI

struct VOAppsView: View {
    enum Tab: Hashable { case ai, mac }
    @State private var tab: Tab = .ai
    @ObservedObject private var providers = VOProviderManager.shared

    var body: some View {
        VOPageScaffold(title: "Apps") {
            VOCard {
                VOCardHeader(symbol: "square.grid.2x2", title: "App Store", subtitle: "Connect apps to use with Assistant Mode") {
                    Button {
                        providers.refreshAll()
                        providers.refreshUsage()
                    } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                        .buttonStyle(VOSecondaryButtonStyle())
                }
                VOSegmentedPill(options: [(Tab.ai, "AI Models"), (Tab.mac, "Mac Apps")], selection: $tab, compact: true)
            }
            if tab == .ai {
                Text("VoiceOS runs on a free local model first. Cloud AIs are only used for requests that need them, through their official apps signed in with your own account — so they count against the plan you already pay for, not an API bill.")
                    .font(.system(size: 13)).foregroundColor(VOTheme.secondary)
                ForEach(VOProviderID.allCases) { p in
                    if p.isLocal { VOLocalAICard() } else { VOProviderCard(provider: p) }
                }
            } else {
                VOMacAppsGrid()
            }
        }
        .onAppear {
            providers.refreshAll()
            if providers.planUsage.isEmpty { providers.refreshUsage() }
        }
    }
}

struct VOProviderCard: View {
    let provider: VOProviderID
    @ObservedObject private var settings = VOSettings.shared
    @ObservedObject private var providers = VOProviderManager.shared
    @State private var apiKey = ""
    @State private var keySaved = false

    private var status: VOProviderStatus { providers.status[provider] ?? .unknown }
    private var mode: VOConnectionMode { settings.mode(for: provider) }

    var body: some View {
        VOCard {
            HStack(spacing: 14) {
                VOProviderLogo(provider: provider, size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(provider.displayName).font(.system(size: 17, weight: .semibold))
                        Text(provider.company).font(.system(size: 13)).foregroundColor(VOTheme.tertiary)
                        if settings.agentProvider == provider { badge("ASSISTANT", VOTheme.accent) }
                        if settings.polishEngine.provider == provider { badge("DICTATION", VOTheme.green) }
                    }
                    HStack(spacing: 6) {
                        if status == .checking { ProgressView().controlSize(.mini) } else { VOStatusDot(color: status.color) }
                        Text(status.label).font(.system(size: 12.5)).foregroundColor(VOTheme.secondary).lineLimit(1)
                    }
                }
                Spacer()
                VOSegmentedPill(options: VOConnectionMode.allCases.map { ($0, $0.label) },
                              selection: Binding(get: { mode }, set: { settings.setMode($0, for: provider); providers.refreshStatus(provider) }),
                              compact: true)
            }

            if mode == .subscription { subscriptionSection } else { apiSection }

            HStack(spacing: 12) {
                Text("Model").font(.system(size: 13.5))
                VODropdown(options: modelOptions,
                           selection: Binding(get: { providers.model(for: provider) },
                                              set: { mode == .subscription ? settings.setCliModel($0, for: provider) : settings.setApiModel($0, for: provider) }),
                           width: 260)
                Spacer()
                Button("Use for Assistant") { settings.agentProvider = provider }
                    .buttonStyle(VOSecondaryButtonStyle()).disabled(settings.agentProvider == provider)
                Button("Use for Dictation") { settings.polishEngine = VOPolishEngine(rawValue: provider.rawValue) ?? .local }
                    .buttonStyle(VOSecondaryButtonStyle()).disabled(settings.polishEngine.provider == provider)
            }

            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Plan usage").font(.system(size: 12, weight: .semibold)).foregroundColor(VOTheme.tertiary)
                    VOPlanUsageView(usage: providers.planUsage[provider])
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Used by VoiceOS").font(.system(size: 12, weight: .semibold)).foregroundColor(VOTheme.tertiary)
                    let t = providers.totals(for: provider)
                    Text("\(providers.todayRequests(provider)) requests today · \(t.requests) in 30 days")
                        .font(.system(size: 12.5)).foregroundColor(VOTheme.secondary)
                    if t.requests > 0 {
                        Text(String(format: "Avg. %.1fs per answer", locale: .current, t.seconds / Double(t.requests))).font(.system(size: 12.5)).foregroundColor(VOTheme.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.03)))
        }
        .onAppear { keySaved = !(VOKeychain.get("api-\(provider.rawValue)") ?? "").isEmpty }
    }

    private var modelOptions: [(String, String)] {
        var opts = (mode == .subscription ? provider.cliModels : provider.apiModels).map { ($0.id, $0.label) }
        let current = providers.model(for: provider)
        if !opts.contains(where: { $0.0 == current }) { opts.append((current, current)) }
        return opts
    }

    private func badge(_ t: String, _ c: Color) -> some View {
        Text(t).font(.system(size: 8.5, weight: .bold)).kerning(0.5).foregroundColor(c)
            .padding(.horizontal, 5).padding(.vertical, 2).background(Capsule().fill(c.opacity(0.15)))
    }

    private var subscriptionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "terminal").foregroundColor(VOTheme.secondary).font(.system(size: 12))
                if let path = VOCLIRunner.resolve(provider.cliName) {
                    Text("Uses your \(provider.planName) through \(provider.cliDisplayName)")
                        .font(.system(size: 13)).foregroundColor(.white.opacity(0.85))
                    Text((path as NSString).abbreviatingWithTildeInPath).font(.system(size: 11.5, design: .monospaced)).foregroundColor(VOTheme.tertiary)
                } else {
                    Text("\(provider.cliDisplayName) isn't installed.").font(.system(size: 13)).foregroundColor(VOTheme.orange)
                    Text(provider.installCommand).font(.system(size: 11.5, design: .monospaced)).foregroundColor(VOTheme.secondary).textSelection(.enabled)
                }
            }
            HStack(spacing: 10) {
                Button(status.isReady ? "Switch account" : (VOCLIRunner.resolve(provider.cliName) == nil ? "Install & sign in" : "Sign in")) {
                    providers.signIn(provider)
                }
                .buttonStyle(VOPrimaryButtonStyle())
                Button {
                    providers.test(provider)
                } label: {
                    HStack(spacing: 6) {
                        if providers.testing.contains(provider) { ProgressView().controlSize(.small) }
                        Text(providers.testing.contains(provider) ? "Testing…" : "Test connection")
                    }
                }
                .buttonStyle(VOSecondaryButtonStyle())
                .disabled(providers.testing.contains(provider))
                Button("Re-check") { providers.refreshStatus(provider) }.buttonStyle(VOSecondaryButtonStyle())
            }
            testResult
            if provider == .claude {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Keep Claude ready for instant replies").font(.system(size: 13.5))
                        Text("Holds one pre-started Claude process (about 350 MB) so answers begin in under a second.")
                            .font(.system(size: 12)).foregroundColor(VOTheme.tertiary)
                    }
                    Spacer()
                    VOToggle(isOn: $settings.keepClaudeWarm)
                }
                .padding(.top, 4)
            }
        }
    }

    private var apiSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pay-as-you-go with your own API key. The key is stored in your macOS Keychain.")
                .font(.system(size: 13)).foregroundColor(VOTheme.secondary)
            HStack(spacing: 10) {
                VODarkField(placeholder: keySaved ? "•••••••••••• saved" : provider.apiKeyPlaceholder, text: $apiKey, secure: true)
                Button("Save") {
                    VOKeychain.set(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), for: "api-\(provider.rawValue)")
                    keySaved = !apiKey.isEmpty
                    apiKey = ""
                    providers.refreshStatus(provider)
                }
                .buttonStyle(VOPrimaryButtonStyle())
                .disabled(apiKey.isEmpty)
                if keySaved {
                    Button("Remove") {
                        VOKeychain.set("", for: "api-\(provider.rawValue)")
                        keySaved = false
                        providers.refreshStatus(provider)
                    }
                    .buttonStyle(VOSecondaryButtonStyle())
                }
            }
            HStack(spacing: 10) {
                Button("Get a key") { NSWorkspace.shared.open(provider.apiKeyHelpURL) }.buttonStyle(VOSecondaryButtonStyle())
                Button("Test connection") { providers.test(provider) }.buttonStyle(VOSecondaryButtonStyle())
                    .disabled(!keySaved || providers.testing.contains(provider))
            }
            testResult
        }
    }

    @ViewBuilder private var testResult: some View {
        if let t = providers.tests[provider] {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: t.ok ? "checkmark.circle.fill" : "xmark.octagon.fill").foregroundColor(t.ok ? VOTheme.green : VOTheme.orange)
                Text(t.ok ? "Connected — answered in \(String(format: "%.1f", locale: .current, t.seconds))s" : t.message)
                    .font(.system(size: 12.5)).foregroundColor(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }
}

struct VOMacAppsGrid: View {
    @ObservedObject private var settings = VOSettings.shared

    private let apps: [(name: String, desc: String, bundle: String?, cap: VOAssistantCapability)] = [
        ("Messages", "Send iMessages to your contacts", "com.apple.MobileSMS", .messages),
        ("Mail", "Write and send email", "com.apple.mail", .email),
        ("Calendar", "View and create calendar events", "com.apple.iCal", .calendar),
        ("Reminders", "Create and complete reminders", "com.apple.reminders", .reminders),
        ("Notes", "Create and append notes", "com.apple.Notes", .notes),
        ("Finder", "Search, read and organize files", "com.apple.finder", .findFiles),
        ("Safari", "Search the web and open links", "com.apple.Safari", .webSearch),
        ("Shortcuts", "Run your automations by voice", "com.apple.shortcuts", .shortcuts),
        ("Claude Code", "Run coding tasks with the Claude Code CLI", "com.apple.Terminal", .claudeCode),
        ("Any app", "Open apps, folders and websites by name", "com.apple.launchpad.launcher", .openApps),
    ]

    var body: some View {
        let connected = apps.filter { settings.isEnabled($0.cap) }
        let available = apps.filter { !settings.isEnabled($0.cap) }
        VStack(alignment: .leading, spacing: 14) {
            if !connected.isEmpty {
                VOSectionLabel(text: "Connected")
                grid(connected)
            }
            if !available.isEmpty {
                VOSectionLabel(text: "Available")
                grid(available)
            }
            Text("Assistant Mode asks before anything is sent, booked or changed. macOS will ask you once per app to allow VoiceOS to control it.")
                .font(.system(size: 12.5)).foregroundColor(VOTheme.tertiary)
        }
    }

    private func grid(_ items: [(name: String, desc: String, bundle: String?, cap: VOAssistantCapability)]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 12) {
            ForEach(items, id: \.name) { a in
                HStack(spacing: 12) {
                    VOAppIconView(bundleID: a.bundle, symbol: a.cap.symbol, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(a.name).font(.system(size: 14.5, weight: .semibold))
                        Text(a.desc).font(.system(size: 12)).foregroundColor(VOTheme.secondary).lineLimit(1)
                    }
                    Spacer()
                    VOToggle(isOn: Binding(get: { settings.isEnabled(a.cap) }, set: { settings.setEnabled(a.cap, $0) }))
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(VOTheme.card))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(VOTheme.border, lineWidth: 1))
            }
        }
    }
}
