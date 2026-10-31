// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import EventKit
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
}

extension NotchModule {
    /// One colour per page, muted, so the switcher and the dock read at a
    /// glance; the sections gallery keeps its own.
    var hubTint: Color {
        switch self {
        case .music: return .pink
        case .calendar: return .red
        case .timer: return .orange
        case .voice: return Color(red: 0.55, green: 0.75, blue: 1)
        case .agents: return Color(red: 1, green: 0.62, blue: 0.42)
        case .clipboard: return .teal
        case .files, .downloads: return Color(red: 0.45, green: 0.7, blue: 1)
        case .captures, .camera: return .mint
        case .system: return .green
        case .tools: return .purple
        case .scratchpad: return .yellow
        case .mixer: return .indigo
        case .notifications: return Color(red: 1, green: 0.42, blue: 0.42)
        case .watch: return .cyan
        case .battery: return .green
        case .controls: return .white.opacity(0.85)
        }
    }
}

/// The assistant's page with nothing asked yet is the island's home: the
/// days's events, a small mirror, the controls reached for most and the song
/// playing, with quick asks about text selected in the app in front.
struct NotchHubView: View {
    @ObservedObject var service: NotchService
    /// Text selected in the app in front when the island opened.
    let selection: String?
    let ask: (String) -> Void
    @ObservedObject private var intent = NotchIntentService.shared
    @ObservedObject private var music = NotchMusicService.shared
    @ObservedObject private var l10n = L10n.shared
    private var text: NotchHubStrings { FeatureStrings.notchHub(l10n.language) }
    private static let side: CGFloat = 196
    private static let widgetHeight: CGFloat = 206

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if selection != nil { selectionRow }
            HStack(alignment: .top, spacing: 10) {
                NotchHubCalendarWidget(service: service)
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.widgetHeight)
                VStack(spacing: 8) {
                    if NotchCameraSupport.isEnabled() {
                        NotchHubCameraTile(service: service, size: CGSize(width: Self.side, height: 110))
                    }
                    NotchHubActions(service: service, rows: NotchCameraSupport.isEnabled() ? 2 : 4)
                }
                .frame(width: Self.side, height: Self.widgetHeight, alignment: .top)
            }
            if music.playback != nil, service.modules.contains(.music) {
                NotchHubNowPlaying(service: service)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Ranked again while the home shows, so the switcher's marks follow
        // a song starting or a meeting coming up.
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
}

/// The home's widgets share one card.
private struct NotchHubCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        content()
            .background(.white.opacity(0.06), in: shape)
            .overlay { shape.strokeBorder(.white.opacity(0.06), lineWidth: 1).allowsHitTesting(false) }
            .clipShape(shape)
    }
}

/// Today's date and the next few events, each a click from its place on
/// the Calendar page.
private struct NotchHubCalendarWidget: View {
    @ObservedObject var service: NotchService
    @ObservedObject private var calendar = NotchCalendarService.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var l10n = L10n.shared
    /// The next month of events, read for this card alone: the island keeps
    /// only the week it shows elsewhere.
    @State private var month: [NotchCalendarEvent] = []
    private static let reader = NotchCalendarReader()
    private var text: NotchCalendarStrings { FeatureStrings.notchCalendar(l10n.language) }
    private var locale: Locale { l10n.language.formattingLocale() }

    var body: some View {
        NotchHubCard {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                VStack(alignment: .leading, spacing: 8) {
                    header(context.date)
                    content(context.date)
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .task(id: calendar.events) { await readMonth() }
        .onChange(of: permissions.calendarAccess) { Task { await readMonth() } }
    }

    /// Read again whenever the island reads its week, so an edit in
    /// Calendar reaches the card too.
    private func readMonth() async {
        guard available, permissions.calendarAccess == .fullAccess else { month = []; return }
        let start = Calendar.current.startOfDay(for: Date())
        guard let end = Calendar.current.date(byAdding: .day, value: 31, to: start) else { return }
        let read = await Self.reader.read(interval: DateInterval(start: start, end: end),
                                          excluded: NotchCalendarSupport.excludedCalendars())
        month = NotchCalendarSupport.ordered(read)
    }

    private func header(_ now: Date) -> some View {
        Button { open(nil) } label: {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: -2) {
                    Text(now.formatted(.dateTime.weekday(.wide).locale(locale)).uppercased())
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(.red)
                    Text(now.formatted(.dateTime.day().locale(locale)))
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
                Spacer(minLength: 6)
                if available, permissions.calendarAccess == .fullAccess, !upcoming(now).isEmpty {
                    Text(text.next)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                        .padding(.top, 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!available)
        .help(text.openCalendar)
    }

    private var available: Bool {
        service.modules.contains(.calendar) && NotchCalendarSupport.isEnabled()
    }

    @ViewBuilder private func content(_ now: Date) -> some View {
        if !available {
            Text(now.formatted(.dateTime.hour().minute().locale(locale)))
                .font(.system(size: 34, weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.85))
        } else if permissions.calendarAccess != .fullAccess {
            VStack(alignment: .leading, spacing: 8) {
                let denied = permissions.calendarAccess == .denied || permissions.calendarAccess == .restricted
                Text(denied ? text.denied : text.permission)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                NotchPillButton(title: denied ? text.settings : text.allow, prominent: true) {
                    if denied { permissions.openCalendarSettings() } else { permissions.requestCalendar() }
                }
                .disabled(permissions.requestingCalendar)
            }
        } else {
            let upcoming = upcoming(now)
            if upcoming.isEmpty {
                Label(text.empty, systemImage: "calendar")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // A month ahead, a day at a time, scrolled within the card.
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(days(upcoming, now: now).enumerated()), id: \.offset) { _, day in
                            if day.date.map({ !Calendar.current.isDate($0, inSameDayAs: now) }) ?? false {
                                Text(dayTitle(day.date!, now: now))
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.45))
                                    .padding(.top, 4)
                                    .padding(.leading, 6)
                            }
                            ForEach(day.events) { event in
                                row(event, now: now, first: event.id == upcoming.first?.id)
                            }
                        }
                    }
                    .padding(.bottom, 4)
                }
                .scrollIndicators(.automatic)
                .notchScrollEdgeFade()
            }
        }
    }

    /// Every event still to come in the month read, or in the island's week
    /// until that read arrives.
    private func upcoming(_ now: Date) -> [NotchCalendarEvent] {
        NotchCalendarSupport.upcoming(month.isEmpty ? calendar.events : month, now: now)
    }

    /// The events by the day they start, today's first.
    private func days(_ events: [NotchCalendarEvent], now: Date) -> [(date: Date?, events: [NotchCalendarEvent])] {
        var days: [(date: Date?, events: [NotchCalendarEvent])] = []
        for event in events {
            let day = Calendar.current.startOfDay(for: max(event.start, now))
            if let last = days.last, last.date == day { days[days.count - 1].events.append(event) }
            else { days.append((day, [event])) }
        }
        return days
    }

    private func dayTitle(_ day: Date, now: Date) -> String {
        day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).locale(locale))
    }

    private func row(_ event: NotchCalendarEvent, now: Date, first: Bool) -> some View {
        let ongoing = event.start <= now && event.end > now
        let minutes = Int((event.start.timeIntervalSince(now) / 60).rounded(.up))
        return Button { open(event) } label: {
            HStack(spacing: 8) {
                Capsule()
                    .fill(event.color.color)
                    .frame(width: 3, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title.isEmpty ? text.untitled : event.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(time(event, now: now))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if ongoing {
                    Circle().fill(event.color.color).frame(width: 7, height: 7)
                        .accessibilityLabel(text.ongoing)
                } else if first, !event.allDay, minutes > 0, minutes <= 60 {
                    Text(String(format: FeatureStrings.notchHub(l10n.language).startsIn, minutes))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(event.color.color)
                        .padding(.horizontal, 7)
                        .frame(height: 18)
                        .background(event.color.color.opacity(0.16), in: Capsule())
                }
            }
            .padding(.horizontal, 6)
            .frame(height: 38)
            .background(.white.opacity(first ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 10, lifts: false))
    }

    private func time(_ event: NotchCalendarEvent, now: Date) -> String {
        if event.allDay { return text.allDay }
        // The day's heading names the day; the row needs only the hours.
        if Calendar.current.isDate(event.start, inSameDayAs: event.end) || event.start <= now {
            let range = event.start.formatted(.dateTime.hour().minute().locale(locale)) + " – "
                + event.end.formatted(.dateTime.hour().minute().locale(locale))
            return range
        }
        return NotchCalendarSupport.tileStartText(event.start, now: now, locale: locale)
    }

    private func open(_ event: NotchCalendarEvent?) {
        if let event { calendar.revealing = event.id }
        service.select(.calendar)
    }
}

/// A small mirror: one click starts the camera, and leaving the home or
/// closing the island stops it, as leaving the camera's own page does.
private struct NotchHubCameraTile: View {
    @ObservedObject var service: NotchService
    let size: CGSize
    @ObservedObject private var camera = CameraPreviewService.shared
    @ObservedObject private var l10n = L10n.shared
    private var text: NotchActivityStrings { FeatureStrings.notchActivities(l10n.language) }

    var body: some View {
        Group {
            if camera.isEmbeddedPresented {
                CameraPreviewView(size: size, showsCameraMenu: false)
                    .overlay(alignment: .topTrailing) {
                        HStack(spacing: 4) {
                            control("arrow.up.left.and.arrow.down.right", NotchModule.camera.title(l10n.language)) {
                                service.select(.camera)
                            }
                            control("xmark", text.stopCamera) { camera.hideEmbedded() }
                        }
                        .padding(6)
                    }
            } else {
                Button { camera.showEmbedded() } label: {
                    NotchHubCard {
                        ZStack {
                            LinearGradient(colors: [Color.mint.opacity(0.16), .clear],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                            VStack(spacing: 7) {
                                Image(systemName: "web.camera")
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundStyle(.mint)
                                    .frame(width: 36, height: 36)
                                    .background(Color.mint.opacity(0.14), in: Circle())
                                Text(text.startCamera)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.75))
                                    .lineLimit(1)
                            }
                        }
                        .frame(width: size.width, height: size.height)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(NotchButtonStyle(cornerRadius: 16, lifts: false))
                .help(text.cameraHint)
                .accessibilityLabel(text.startCamera)
            }
        }
        .frame(width: size.width, height: size.height)
        .onDisappear { if service.selected != .camera { camera.hideEmbedded() } }
    }

    private func control(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(.black.opacity(0.55), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 11))
        .help(title)
        .accessibilityLabel(title)
    }
}

/// The controls reached for most, coloured by what they do, lit while on.
private struct NotchHubActions: View {
    @ObservedObject var service: NotchService
    let rows: Int
    @ObservedObject private var awake = KeepAwakeManager.shared
    @ObservedObject private var microphone = MicMuteService.shared
    @ObservedObject private var recorder = ScreenRecorderService.shared
    @ObservedObject private var l10n = L10n.shared
    private static let order: [NotchControlItem] = [
        .screenshot, .recording, .keepAwake, .battery, .fans, .microphone, .scratchpad, .commandBar, .timer, .toggles,
        .speedTest, .mixer, .panel, .calendar, .music,
    ]

    var body: some View {
        let items = Array(Self.order.filter { $0.isAvailable() }.prefix(rows * 3))
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
            ForEach(items) { item in tile(item) }
        }
    }

    private func tile(_ item: NotchControlItem) -> some View {
        let on = active(item)
        let tint = Self.tint(item)
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        let title = item.title(l10n)
        return Button { service.activateQuickAction(.control(item)) } label: {
            Image(systemName: symbol(item, on: on))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(on ? .white : tint)
                .contentTransition(.symbolEffect(.replace))
                .frame(maxWidth: .infinity)
                .frame(height: 41)
                .background(on ? tint.opacity(0.85) : tint.opacity(0.13), in: shape)
                .contentShape(shape)
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 12))
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func active(_ item: NotchControlItem) -> Bool {
        switch item {
        case .keepAwake: return awake.isActive
        case .microphone: return microphone.isMuted
        case .recording: return recorder.isRecording
        default: return false
        }
    }

    private func symbol(_ item: NotchControlItem, on: Bool) -> String {
        switch item {
        case .keepAwake: return on ? "cup.and.saucer.fill" : "cup.and.saucer"
        case .microphone: return on ? "mic.slash.fill" : "mic.fill"
        case .recording: return on ? "stop.circle.fill" : "record.circle"
        default: return item.symbol
        }
    }

    private static func tint(_ item: NotchControlItem) -> Color {
        switch item {
        case .screenshot: return .cyan
        case .recording, .microphone: return Color(red: 1, green: 0.42, blue: 0.42)
        case .keepAwake, .timer: return .orange
        case .scratchpad: return .yellow
        case .commandBar, .panel: return .purple
        case .speedTest: return .green
        case .mixer: return .indigo
        case .calendar: return .red
        case .music: return .pink
        case .fans: return .teal
        case .battery: return .green
        case .toggles: return .blue
        default: return .white
        }
    }
}

/// The song playing, tinted by its cover, with the player's three buttons.
private struct NotchHubNowPlaying: View {
    @ObservedObject var service: NotchService
    @ObservedObject private var music = NotchMusicService.shared
    @ObservedObject private var l10n = L10n.shared
    private var player: RadialMenuFeatureStrings { FeatureStrings.radialMenu(l10n.language) }

    var body: some View {
        let tint = music.artworkTint?.color ?? .pink
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        HStack(spacing: 10) {
            Button { service.select(.music) } label: {
                HStack(spacing: 10) {
                    Group {
                        if let artwork = music.artwork {
                            Image(nsImage: artwork).resizable().scaledToFill()
                        } else {
                            Image(systemName: NotchModule.music.symbol)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(tint)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(tint.opacity(0.16))
                        }
                    }
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(music.playback?.track.title ?? NotchModule.music.title(l10n.language))
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if let artist = music.playback?.track.artist, !artist.isEmpty {
                            Text(artist)
                                .font(.system(size: 10.5))
                                .foregroundStyle(.white.opacity(0.55))
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(NotchModule.music.title(l10n.language))
            if music.playback?.isPlaying == true {
                NotchLiveEqualizerBars(bars: 3, barWidth: 2, height: 11, tint: tint)
                    .accessibilityHidden(true)
            }
            control("backward.fill", player.mediaPrevious, .previous)
            control(music.playback?.isPlaying == true ? "pause.fill" : "play.fill",
                    music.playback?.isPlaying == true ? l10n.s.actionPause : l10n.s.actionPlay, .toggle)
            control("forward.fill", player.mediaNext, .next)
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .frame(height: 52)
        .background {
            LinearGradient(colors: [tint.opacity(0.28), tint.opacity(0.06)], startPoint: .leading, endPoint: .trailing)
        }
        .background(.white.opacity(0.04))
        .clipShape(shape)
        .overlay { shape.strokeBorder(.white.opacity(0.06), lineWidth: 1).allowsHitTesting(false) }
    }

    private func control(_ symbol: String, _ title: String, _ command: NotchMusicService.Command) -> some View {
        NotchIconButton(symbol: symbol, title: title) { _ = music.send(command) }
            .disabled(!music.canPerform(command))
    }
}

/// The home's top row: every page a click away, coloured as the dock is,
/// with a dot on the ones the moment suggests. Where the row has no room
/// for them all, the last place opens the sections.
struct NotchHubPageBar: View {
    @ObservedObject var service: NotchService
    @ObservedObject private var intent = NotchIntentService.shared
    @ObservedObject private var l10n = L10n.shared
    /// The room the row leaves the bar, which it fills with as many pages
    /// as fit; the page's own controls in the row take theirs first.
    @State private var room: CGFloat = 0
    private static let pitch: CGFloat = 28 + 2

    /// On the home every other page; on any other page the home leads them,
    /// so every page is a click from every other.
    private var pages: [NotchModule] {
        service.selected == .voice ? service.hubModules : service.modules
    }

    var body: some View {
        let pages = pages
        let fits = max(0, Int((room - 6 + 2) / Self.pitch))
        let overflows = pages.count > fits
        let shown = overflows ? max(0, fits - 1) : pages.count
        let suggested = Set(intent.suggestions.map(\.module))
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { room = $0 }
            .overlay(alignment: .leading) {
                if fits > 0 {
                    HStack(spacing: 2) {
                        ForEach(pages.prefix(shown)) { module in
                            icon(module, suggested: suggested.contains(module))
                        }
                        if overflows {
                            NotchIconButton(symbol: "ellipsis", title: FeatureStrings.notchHub(l10n.language).allPages,
                                            action: service.toggleSections)
                        }
                    }
                    .padding(.horizontal, 3)
                    .frame(height: 32)
                    .background(.white.opacity(0.05), in: Capsule())
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(FeatureStrings.notchHub(l10n.language).allPages)
                }
            }
    }

    private func icon(_ module: NotchModule, suggested: Bool) -> some View {
        let title = module == .voice ? FeatureStrings.notchHub(l10n.language).home : module.title(l10n.language)
        let current = service.selected == module && !service.showingSections
        return Button { service.select(module) } label: {
            Image(systemName: module == .voice ? "house" : module.symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(module.hubTint)
                .frame(width: 28, height: 26)
                .background(.white.opacity(current ? 0.16 : 0), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(alignment: .bottom) {
                    if suggested {
                        Circle().fill(module.hubTint).frame(width: 3, height: 3).offset(y: 1)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 8))
        .help(title + "  ⌥⌘" + module.shortcutKey.uppercased())
        .accessibilityLabel(title)
        .accessibilityIdentifier("notch.pagebar.\(module.rawValue)")
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
