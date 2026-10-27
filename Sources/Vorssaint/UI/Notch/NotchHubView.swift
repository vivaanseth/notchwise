// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The hub and the hover dock share these measures; the service sizes the
/// peeking island from them.
enum NotchHubLayout {
    static let peekIcon: CGFloat = 28
    static let peekSpacing: CGFloat = 4
    static let peekPillWidth: CGFloat = 124
    /// The rule between the pill and the icons, with its spacing.
    static let peekDividerRoom: CGFloat = 17
    static let peekMaximumWidth: CGFloat = 720
    static let peekRowHeight: CGFloat = 36
    static let dockCellHeight: CGFloat = 50
    static let dockSpacing: CGFloat = 6
    static let dockMinimumCellWidth: CGFloat = 56
    static let cardHeight: CGFloat = 50

    /// The hover dock for `count` pages: its width, how many icons it
    /// shows, and whether the last slot opens all the pages instead.
    static func peek(count: Int, screenWidth: CGFloat, minimumWidth: CGFloat) -> (width: CGFloat, icons: Int, overflows: Bool) {
        let limit = max(minimumWidth, min(screenWidth - 24, peekMaximumWidth))
        let chrome = NotchLayout.horizontalInset * 2 + peekPillWidth + peekDividerRoom
        let pitch = peekIcon + peekSpacing
        let fits = max(1, Int((limit - chrome + peekSpacing) / pitch))
        let overflows = count > fits
        let icons = overflows ? fits - 1 : count
        let slots = CGFloat(icons + (overflows ? 1 : 0))
        return (min(limit, max(minimumWidth, chrome + slots * pitch - peekSpacing)), icons, overflows)
    }

    /// The hub's dock in rows as even as the pages allow.
    static func dockColumns(count: Int, width: CGFloat) -> Int {
        guard count > 0 else { return 1 }
        let widest = max(1, Int((width + dockSpacing) / (dockMinimumCellWidth + dockSpacing)))
        let rows = (count + widest - 1) / widest
        return (count + rows - 1) / rows
    }
}

extension NotchModule {
    /// The sections gallery's colours, so a page looks the same everywhere.
    var hubTint: Color {
        switch self {
        case .music: return .pink
        case .calendar: return .red
        case .timer: return .orange
        case .voice: return Color(red: 0.55, green: 0.75, blue: 1)
        default: return .white.opacity(0.85)
        }
    }
}

/// The assistant's page with nothing asked yet: what is going on and what
/// the person likely wants next, every page one click away, and quick asks
/// about text selected in the app in front.
struct NotchHubView: View {
    @ObservedObject var service: NotchService
    /// Text selected in the app in front when the island opened.
    let selection: String?
    let ask: (String) -> Void
    @ObservedObject private var intent = NotchIntentService.shared
    @ObservedObject private var l10n = L10n.shared
    private var text: NotchHubStrings { FeatureStrings.notchHub(l10n.language) }
    private var width: CGFloat { max(0, service.contentSize.width - 16) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if selection != nil { selectionRow }
            if !intent.suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label(text.forYou, systemImage: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                    HStack(spacing: 8) {
                        ForEach(intent.suggestions) { NotchHubCard(service: service, suggestion: $0) }
                    }
                }
            }
            dock
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Ranked again while the hub shows, so a song starting or a meeting
        // coming up reaches it without reopening the island.
        .task(id: service.hubModules) {
            while !Task.isCancelled {
                intent.refresh(modules: service.hubModules)
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    private var selectionRow: some View {
        HStack(spacing: 6) {
            Label(text.selection, systemImage: "text.cursor")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
            Spacer(minLength: 4)
            chip(text.summarize, "Summarize the selected text.")
            chip(text.explain, "Explain the selected text.")
            chip(text.improve, "Improve the writing of the selected text.")
        }
    }

    private func chip(_ title: String, _ prompt: String) -> some View {
        Button { ask(prompt) } label: {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 11)
                .frame(height: 26)
                .background(.white.opacity(0.1), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 13))
    }

    private var dock: some View {
        let pages = service.hubModules
        let columns = NotchHubLayout.dockColumns(count: pages.count, width: width)
        let suggested = Set(intent.suggestions.map(\.module))
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: NotchHubLayout.dockSpacing), count: columns),
                         spacing: NotchHubLayout.dockSpacing) {
            ForEach(pages) { module in
                NotchHubDockCell(module: module, suggested: suggested.contains(module), language: l10n.language) {
                    service.select(module)
                }
            }
        }
    }
}

/// One page in the hub's dock: its mark and its name.
private struct NotchHubDockCell: View {
    let module: NotchModule
    let suggested: Bool
    let language: AppLanguage
    let action: () -> Void

    var body: some View {
        let title = module.title(language)
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: module.symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(module.hubTint)
                    .frame(height: 19)
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
            .frame(height: NotchHubLayout.dockCellHeight)
            .background(.white.opacity(suggested ? 0.1 : 0.045), in: shape)
            .overlay { shape.strokeBorder(.white.opacity(suggested ? 0.22 : 0), lineWidth: 1) }
            .contentShape(shape)
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 12, lifts: false))
        .help(title + "  ⌥⌘" + module.shortcutKey.uppercased())
        .accessibilityLabel(title)
        .accessibilityIdentifier("notch.hub.\(module.rawValue)")
    }
}

/// A suggested page with what makes it likely now. The player and the timer
/// keep their one control on the card, so pausing needs no trip to the page.
private struct NotchHubCard: View {
    @ObservedObject var service: NotchService
    let suggestion: NotchIntentSuggestion
    @ObservedObject private var music = NotchMusicService.shared
    @ObservedObject private var timer = NotchTimerService.shared
    @ObservedObject private var calendar = NotchCalendarService.shared
    @ObservedObject private var l10n = L10n.shared
    private var module: NotchModule { suggestion.module }
    private var text: NotchHubStrings { FeatureStrings.notchHub(l10n.language) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        ZStack(alignment: .trailing) {
            Button { service.select(module) } label: {
                HStack(spacing: 9) {
                    mark
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        detail
                            .font(.system(size: 10.5))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                    Spacer(minLength: control == nil ? 0 : 30)
                }
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity)
                .frame(height: NotchHubLayout.cardHeight)
                .background(.white.opacity(0.075), in: shape)
                .contentShape(shape)
            }
            .buttonStyle(NotchButtonStyle(cornerRadius: 14, lifts: false))
            .accessibilityLabel(title)
            .accessibilityValue(reason)
            if let control {
                NotchIconButton(symbol: control.symbol, title: control.title, action: control.action)
                    .padding(.trailing, 8)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var mark: some View {
        if module == .music, let artwork = music.artwork {
            Image(nsImage: artwork).resizable().scaledToFill()
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        } else {
            Image(systemName: module.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(module.hubTint)
                .frame(width: 28, height: 28)
                .background(module.hubTint.opacity(0.16), in: Circle())
        }
    }

    private var title: String {
        switch module {
        case .music: return music.playback?.track.title ?? module.title(l10n.language)
        case .calendar: return calendar.countdown?.event.title ?? module.title(l10n.language)
        default: return module.title(l10n.language)
        }
    }

    private var reason: String {
        text.reason(suggestion.reason, minutes: NotchIntentService.shared.meetingMinutes)
    }

    @ViewBuilder private var detail: some View {
        if module == .timer, timer.session.hasSession {
            if timer.session.isRunning {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(NotchTimerSupport.clockText(for: timer.session, at: timer.now)).monospacedDigit()
                }
            } else {
                Text(NotchTimerSupport.clockText(for: timer.session, at: timer.now)).monospacedDigit()
            }
        } else if module == .music, case .live = suggestion.reason, let artist = music.playback?.track.artist {
            Text(artist)
        } else {
            Text(reason)
        }
    }

    private var control: (symbol: String, title: String, action: () -> Void)? {
        let strings = l10n.s
        switch module {
        case .music:
            guard let playback = music.playback else { return nil }
            return (playback.isPlaying ? "pause.fill" : "play.fill",
                    playback.isPlaying ? strings.actionPause : strings.actionPlay, { _ = music.send(.toggle) })
        case .timer:
            guard timer.session.isRunning || timer.session.isPaused else { return nil }
            return (timer.session.isRunning ? "pause.fill" : "play.fill",
                    timer.session.isRunning ? strings.actionPause : strings.actionPlay, { timer.pauseOrResume() })
        default:
            return nil
        }
    }
}

/// The closed island under the pointer: every page one click away, with
/// the likeliest one first and named.
struct NotchHubPeek: View {
    @ObservedObject var service: NotchService
    @ObservedObject private var intent = NotchIntentService.shared
    @ObservedObject private var music = NotchMusicService.shared
    @ObservedObject private var l10n = L10n.shared
    private var text: NotchHubStrings { FeatureStrings.notchHub(l10n.language) }

    var body: some View {
        let pages = service.hubModules
        let layout = NotchHubLayout.peek(count: pages.count, screenWidth: service.geometry.screen.width,
                                         minimumWidth: service.geometry.peek.width)
        let suggested = Set(intent.suggestions.map(\.module))
        HStack(spacing: 8) {
            pill
                .frame(width: NotchHubLayout.peekPillWidth, alignment: .leading)
            Rectangle().fill(.white.opacity(0.16)).frame(width: 1, height: 22)
            HStack(spacing: NotchHubLayout.peekSpacing) {
                ForEach(pages.prefix(layout.icons)) { module in
                    icon(module, suggested: suggested.contains(module))
                }
                if layout.overflows {
                    NotchIconButton(symbol: "square.grid.2x2", title: text.allPages) { service.open(sections: true) }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(height: NotchHubLayout.peekRowHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(text.allPages)
    }

    @ViewBuilder private var pill: some View {
        if let first = intent.suggestions.first {
            Button { service.select(first.module) } label: {
                HStack(spacing: 7) {
                    if first.module == .music, let artwork = music.artwork {
                        Image(nsImage: artwork).resizable().scaledToFill()
                            .frame(width: 22, height: 22)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    } else {
                        Image(systemName: first.module.symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(first.module.hubTint)
                            .frame(width: 22, height: 22)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(first.module == .music ? music.playback?.track.title ?? first.module.title(l10n.language)
                             : first.module.title(l10n.language))
                            .font(.system(size: 11.5, weight: .semibold))
                            .lineLimit(1)
                        Text(text.reason(first.reason, minutes: intent.meetingMinutes))
                            .font(.system(size: 9.5))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 6)
                .frame(height: 32)
                .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(NotchButtonStyle(cornerRadius: 10, lifts: false))
            .accessibilityIdentifier("notch.peek.suggestion")
        } else {
            Button { service.open(sections: true) } label: {
                Label(text.allPages, systemImage: "square.grid.2x2")
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .frame(height: 32)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(NotchButtonStyle(cornerRadius: 10, lifts: false))
        }
    }

    private func icon(_ module: NotchModule, suggested: Bool) -> some View {
        let title = module.title(l10n.language)
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        return Button { service.select(module) } label: {
            Image(systemName: module.symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(module.hubTint)
                .frame(width: NotchHubLayout.peekIcon, height: NotchHubLayout.peekIcon)
                .background(.white.opacity(suggested ? 0.15 : 0.055), in: shape)
                .overlay(alignment: .topTrailing) {
                    if suggested {
                        Circle().fill(.white.opacity(0.85)).frame(width: 4, height: 4).padding(3)
                    }
                }
                .contentShape(shape)
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 9))
        .help(title + "  ⌥⌘" + module.shortcutKey.uppercased())
        .accessibilityLabel(title)
        .accessibilityIdentifier("notch.peek.\(module.rawValue)")
    }
}
