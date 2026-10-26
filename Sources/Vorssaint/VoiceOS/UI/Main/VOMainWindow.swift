// SPDX-License-Identifier: GPL-3.0-or-later
// Ported from VoiceOS Clone (UI/Main/MainWindow.swift) into Vorssaint + VoiceOS.

import AppKit
import SwiftUI

/// Opens VoiceOS's pages. They live in Vorssaint's Settings window, as the
/// VoiceOS section of its sidebar, instead of a window of their own.
@MainActor
enum VOMainWindow {
    /// Brings the Settings window forward. The app delegate owns it; the
    /// snapshot tool runs without that delegate and supplies its own.
    static var presentSettings: () -> Void = {
        (NSApp.delegate as? AppDelegate)?.openSettingsWindow()
    }

    static func show(_ page: VOPage? = nil) {
        SettingsRouter.shared.request(FeatureSettingsDestination(.voiceOS(page ?? currentPage ?? .dashboard)))
        presentSettings()
    }

    /// The VoiceOS page Settings is on, if it is on one.
    static var currentPage: VOPage? {
        if case .voiceOS(let page) = SettingsRouter.shared.page { return page }
        return nil
    }
}

/// One VoiceOS page in the Settings detail. VoiceOS keeps the dark look it
/// had in its own window, and its first-run guide covers the dashboard until
/// it is done, as it covered that window.
struct VOSettingsPage: View {
    let page: VOPage
    @ObservedObject private var settings = VOSettings.shared

    var body: some View {
        ZStack {
            VOTheme.content
            content
            if !settings.onboardingDone && page == .dashboard {
                VOOnboardingView().transition(.opacity)
            }
        }
        // The page's own scheme only: the window keeps Vorssaint's appearance.
        .environment(\.colorScheme, .dark)
        .foregroundColor(.white)
        .animation(.easeInOut(duration: 0.3), value: settings.onboardingDone)
    }

    @ViewBuilder private var content: some View {
        switch page {
        case .dashboard: VODashboardView()
        case .insights: VOInsightsView()
        case .history: VOHistoryView()
        case .dictation: VODictationSettingsView()
        case .assistant: VOAssistantSettingsView()
        case .apps: VOAppsView()
        }
    }
}

/// The profile menu VoiceOS kept at the foot of its sidebar, now beside the
/// dashboard's title. Dock and login choices are the app's, in Vorssaint's
/// General settings; launch at login stays one choice for the whole app.
struct VOProfileButton: View {
    @ObservedObject private var settings = VOSettings.shared
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var showProfile = false

    var body: some View {
        Button { showProfile.toggle() } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(LinearGradient(colors: [Color(hex: 0x8DB8FF), Color(hex: 0x3D6FE0)], startPoint: .top, endPoint: .bottom))
                    Text(String(settings.displayName.prefix(1))).font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                }
                .frame(width: 26, height: 26)
                Text(settings.displayName).font(.system(size: 14, weight: .medium)).foregroundColor(.white).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundColor(.white.opacity(0.6))
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(showProfile ? Color.white.opacity(0.08) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showProfile, arrowEdge: .bottom) { profileMenu }
    }

    private var profileMenu: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(settings.displayName).font(.system(size: 14, weight: .semibold))
            menuToggle("Show notch when idle", $settings.showIdleNotch)
            menuToggle("Show dictation bar when idle", $settings.showIdlePill)
            menuToggle("Launch at login", Binding(get: { launchAtLogin }, set: { on in
                LaunchAtLogin.setEnabled(on) { registration, _ in launchAtLogin = registration == .enabled }
            }))
            Divider().overlay(Color.white.opacity(0.08))
            menuButton("Run setup again", "arrow.counterclockwise") { settings.onboardingDone = false }
            menuButton("Open data folder", "folder") { NSWorkspace.shared.open(VOStorage.directory) }
        }
        .padding(16)
        .frame(width: 280)
        .preferredColorScheme(.dark)
    }

    private func menuToggle(_ title: String, _ binding: Binding<Bool>) -> some View {
        HStack {
            Text(title).font(.system(size: 13.5))
            Spacer()
            VOToggle(isOn: binding).scaleEffect(0.8)
        }
    }

    private func menuButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            showProfile = false
            action()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol).frame(width: 16).foregroundColor(VOTheme.secondary)
                Text(title).font(.system(size: 13.5)).foregroundColor(.white)
                Spacer()
            }
            .frame(height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Standard page layout: big title, then cards.
struct VOPageScaffold<Trailing: View, Content: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .center) {
                    Text(title).font(.system(size: 27, weight: .bold)).foregroundColor(.white)
                    Spacer()
                    trailing
                }
                .padding(.bottom, 6)
                content
            }
            .padding(.horizontal, 40)
            .padding(.top, 30)
            .padding(.bottom, 48)
            .frame(maxWidth: 1000)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
    }
}

extension VOPageScaffold where Trailing == EmptyView {
    init(title: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, trailing: { EmptyView() }, content: content)
    }
}

struct VOSectionLabel: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 17, weight: .semibold)).foregroundColor(.white).padding(.top, 6)
    }
}
