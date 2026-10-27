// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Something happening right now that makes one page the likely next one.
/// Signals are read fresh each time and only weigh the moment: a song
/// playing points at the player whatever the habits say.
enum NotchIntentSignal: String, CaseIterable {
    case playing, timer, meetingSoon, meetingNow, downloading, agents, watching, copied, captured

    /// How much more likely the signal makes each page, as a multiplier
    /// added to its odds. The first page is the one the signal names.
    var targets: [(module: NotchModule, weight: Double)] {
        switch self {
        case .playing: return [(.music, 4)]
        case .timer: return [(.timer, 4)]
        case .meetingSoon: return [(.calendar, 4), (.camera, 1)]
        case .meetingNow: return [(.calendar, 2.5), (.camera, 1.5), (.mixer, 1)]
        case .downloading: return [(.downloads, 3)]
        case .agents: return [(.agents, 2)]
        case .watching: return [(.watch, 2)]
        case .copied: return [(.clipboard, 3)]
        case .captured: return [(.captures, 3)]
        }
    }

    func weight(of module: NotchModule) -> Double {
        targets.first { $0.module == module }?.weight ?? 0
    }

    /// A copy or a capture happens all the time and only hints at a page;
    /// the island suggests it but does not open on it.
    var opensPage: Bool { self != .copied && self != .captured }
}

/// What the front window looks like it is for. It is read from the window's
/// title when the island needs it and kept only as this one word, so the
/// title itself is never stored or learned.
enum NotchIntentScene: String, CaseIterable {
    case meeting, media, code, writing

    static func classify(title: String?, app: String?) -> NotchIntentScene? {
        if let app, NotchIntentPriors.meetingApps.contains(app) { return .meeting }
        let title = title?.lowercased() ?? ""
        guard !title.isEmpty else { return nil }
        func mentions(_ words: [String]) -> Bool { words.contains { title.contains($0) } }
        if mentions(["meet.google", "google meet", "zoom meeting", "microsoft teams", "webex", "huddle", "facetime"]) {
            return .meeting
        }
        if mentions(["youtube", "netflix", "twitch", "vimeo", "spotify", "soundcloud", "prime video", "disney+"]) {
            return .media
        }
        if mentions(["github", "gitlab", "stack overflow", "localhost", ".swift", ".py", ".tsx", ".rs", "pull request"]) {
            return .code
        }
        if mentions(["google docs", "docs.google", "notion", ".md", ".txt", ".docx", ".pages"]) { return .writing }
        return nil
    }

    var targets: [(module: NotchModule, weight: Double)] {
        switch self {
        case .meeting: return [(.camera, 2.5), (.mixer, 2), (.calendar, 1.5)]
        case .media: return [(.mixer, 2), (.music, 1.5), (.controls, 1.5)]
        case .code: return [(.agents, 2), (.scratchpad, 1.5), (.clipboard, 1.5)]
        case .writing: return [(.scratchpad, 2), (.clipboard, 2)]
        }
    }

    func weight(of module: NotchModule) -> Double {
        targets.first { $0.module == module }?.weight ?? 0
    }
}

/// Where a first launch starts before anything is learned: the pages that
/// usually go with a kind of app. Learned choices outweigh these within a
/// dozen or so picks.
enum NotchIntentPriors {
    static let meetingApps: Set<String> = [
        "us.zoom.xos", "com.microsoft.teams", "com.microsoft.teams2", "com.apple.FaceTime",
        "com.cisco.webexmeetingsapp", "com.webex.meetingmanager",
    ]

    private static let groups: [(apps: Set<String>, prefixes: [String], targets: [(NotchModule, Double)])] = [
        (["com.apple.Music", "com.spotify.client", "com.apple.podcasts", "com.tidal.desktop"], [],
         [(.music, 3), (.mixer, 1.5)]),
        (["com.apple.Safari", "com.google.Chrome", "org.mozilla.firefox", "company.thebrowser.Browser",
          "com.microsoft.edgemac", "com.brave.Browser", "com.operasoftware.Opera", "com.vivaldi.Vivaldi"], [],
         [(.clipboard, 2), (.downloads, 2)]),
        (["com.apple.dt.Xcode", "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "com.apple.Terminal",
          "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.mitchellh.ghostty", "dev.zed.Zed",
          "com.sublimetext.4", "com.anthropic.claudefordesktop", "com.openai.chat"], ["com.jetbrains."],
         [(.agents, 2.5), (.scratchpad, 1.5), (.clipboard, 1.5), (.system, 1)]),
        (meetingApps, [], [(.camera, 2.5), (.mixer, 2), (.calendar, 1.5)]),
        (["com.tinyspeck.slackmacgap", "com.apple.MobileSMS", "net.whatsapp.WhatsApp", "com.hnc.Discord",
          "ru.keepcoder.Telegram", "com.apple.mail", "com.microsoft.Outlook"], [],
         [(.clipboard, 2), (.calendar, 1.5), (.notifications, 1.5)]),
        (["com.apple.finder"], [], [(.files, 2.5), (.downloads, 2), (.captures, 1.5)]),
        (["com.apple.iCal", "com.flexibits.fantastical2.mac", "com.apple.reminders"], [],
         [(.calendar, 3), (.timer, 1)]),
        (["com.apple.Notes", "com.apple.TextEdit", "md.obsidian", "notion.id", "com.apple.iWork.Pages",
          "com.microsoft.Word", "com.ulyssesapp.mac", "com.apple.freeform"], [],
         [(.scratchpad, 2.5), (.clipboard, 2)]),
        (["com.figma.Desktop", "com.apple.Preview", "com.bohemiancoding.sketch3", "com.pixelmatorteam.pixelmator.x",
          "com.apple.Photos"], ["com.adobe."],
         [(.captures, 2.5), (.clipboard, 1.5), (.files, 1)]),
        (["com.apple.ActivityMonitor", "com.apple.systempreferences", "com.apple.Console"], [],
         [(.system, 3), (.controls, 1.5)]),
        (["com.apple.QuickTimePlayerX", "org.videolan.vlc", "com.colliderli.iina", "com.apple.TV"], [],
         [(.controls, 2), (.mixer, 1.5), (.music, 1)]),
    ]

    static func weight(of module: NotchModule, app: String) -> Double {
        guard let group = groups.first(where: { group in
            group.apps.contains(app) || group.prefixes.contains { app.hasPrefix($0) }
        }) else { return 0 }
        return group.targets.first { $0.0 == module }?.1 ?? 0
    }
}

/// The moment the island ranks its pages for.
struct NotchIntentContext: Equatable {
    /// The bundle id of the app in front, never this one's.
    var app: String?
    var appName: String?
    var scene: NotchIntentScene?
    var date = Date()
    var signals: Set<NotchIntentSignal> = []

    /// The words the model learns: the app, the window's kind, the part of
    /// the day, weekday or weekend, and what is going on.
    func features(calendar: Calendar = .current) -> [String] {
        var features: [String] = []
        if let app { features.append("app:" + app) }
        if let scene { features.append("scene:" + scene.rawValue) }
        features.append("part:" + Self.dayPart(hour: calendar.component(.hour, from: date)))
        features.append(calendar.isDateInWeekend(date) ? "day:weekend" : "day:weekday")
        features += signals.map { "signal:" + $0.rawValue }.sorted()
        return features
    }

    static func dayPart(hour: Int) -> String {
        switch hour {
        case 6..<12: return "morning"
        case 12..<17: return "afternoon"
        case 17..<22: return "evening"
        default: return "night"
        }
    }
}

/// Why a page is suggested, as the hub and the dock word it.
enum NotchIntentReason: Equatable {
    case live(NotchIntentSignal)
    /// The page last opened, a few minutes ago.
    case resume
    /// Often opened with this app, by habit or by the app's kind; the app's name.
    case app(String)
    case scene(NotchIntentScene)
    case time
    case habit
}

struct NotchIntentSuggestion: Equatable, Identifiable {
    let module: NotchModule
    /// The page's share of the odds across every candidate, 0 to 1.
    let confidence: Double
    let reason: NotchIntentReason
    var id: NotchModule { module }
}

/// A tiny naive Bayes model of which page the person opens in which moment,
/// mixed with the priors above while it has little to go on, and with the
/// live signals on top. Counts fade with every new choice, so a habit that
/// stops fades too. It holds only bundle ids, scene words and counts.
struct NotchIntentModel: Codable, Equatable {
    /// How much each earlier choice still counts once a new one is made:
    /// a habit fades over about a hundred choices once it stops.
    static let decay = 0.99
    /// Each page keeps its strongest features; the rest fade out of the store.
    static let featureLimit = 48
    /// A page opened this recently is offered again first.
    static let resumeWindow: TimeInterval = 15 * 60
    /// Learned choices weigh as much as the priors after this many.
    static let trustHalfway = 8.0

    private(set) var totals: [String: Double] = [:]
    private(set) var counts: [String: [String: Double]] = [:]
    private(set) var choices = 0
    private(set) var last: String?
    private(set) var lastDate: Date?

    mutating func learn(_ module: NotchModule, in context: NotchIntentContext, calendar: Calendar = .current) {
        totals = totals.mapValues { $0 * Self.decay }.filter { $0.value >= 0.05 }
        counts = counts.mapValues { features in features.mapValues { $0 * Self.decay }.filter { $0.value >= 0.05 } }
            .filter { !$0.value.isEmpty }
        totals[module.rawValue, default: 0] += 1
        var features = counts[module.rawValue] ?? [:]
        for feature in context.features(calendar: calendar) { features[feature, default: 0] += 1 }
        if features.count > Self.featureLimit {
            let kept = features.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
                .prefix(Self.featureLimit)
            features = Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
        }
        counts[module.rawValue] = features
        choices += 1
        last = module.rawValue
        lastDate = context.date
    }

    func recent(at date: Date) -> NotchModule? {
        guard let last, let lastDate, date >= lastDate, date.timeIntervalSince(lastDate) <= Self.resumeWindow else { return nil }
        return NotchModule(rawValue: last)
    }

    /// Every candidate with its odds, the likeliest first; ties keep the
    /// candidates' own order.
    func rank(_ candidates: [NotchModule], in context: NotchIntentContext,
              calendar: Calendar = .current) -> [NotchIntentSuggestion] {
        guard !candidates.isEmpty else { return [] }
        let features = context.features(calendar: calendar)
        let recent = recent(at: context.date)
        let total = candidates.reduce(0) { $0 + (totals[$1.rawValue] ?? 0) }
        let learned = Self.normalized(softmax: candidates.map { module in
            let seen = totals[module.rawValue] ?? 0
            let mine = counts[module.rawValue] ?? [:]
            var score = log((seen + 1) / (total + Double(candidates.count)))
            // Laplace-smoothed, so one feature never seen with a page, such as
            // a new time of day, lowers its odds without ruling it out.
            for feature in features { score += log(((mine[feature] ?? 0) + 1) / (seen + 2)) }
            return score
        })
        let prior = Self.normalized(candidates.map { module in
            var weight = 1.0
            if let app = context.app { weight += NotchIntentPriors.weight(of: module, app: app) }
            if let scene = context.scene { weight += scene.weight(of: module) }
            if module == recent { weight += 2 }
            return weight
        })
        let trust = Double(choices) / (Double(choices) + Self.trustHalfway)
        let odds = Self.normalized(candidates.indices.map { index in
            let mixed = trust * learned[index] + (1 - trust) * prior[index]
            let boost = context.signals.reduce(0) { $0 + $1.weight(of: candidates[index]) }
            return mixed * (1 + boost)
        })
        return candidates.indices
            .sorted { odds[$0] == odds[$1] ? $0 < $1 : odds[$0] > odds[$1] }
            .map { index in
                let module = candidates[index]
                return NotchIntentSuggestion(module: module, confidence: odds[index],
                                             reason: reason(for: module, in: context, features: features, recent: recent))
            }
    }

    /// The suggestions worth showing: a live signal, or odds well above an
    /// even share, at most `limit` of them.
    static func notable(_ ranked: [NotchIntentSuggestion], limit: Int) -> [NotchIntentSuggestion] {
        guard !ranked.isEmpty else { return [] }
        let even = 1 / Double(ranked.count)
        return Array(ranked.filter { suggestion in
            if case .live = suggestion.reason { return true }
            return suggestion.confidence >= even * 1.6
        }.prefix(limit))
    }

    /// The page the island opens on without being asked: one that clearly
    /// leads, at twice an even share and a quarter ahead of the next, never
    /// a near tie between two.
    static func opening(_ ranked: [NotchIntentSuggestion]) -> NotchIntentSuggestion? {
        guard ranked.count > 1, let first = ranked.first else { return nil }
        let even = 1 / Double(ranked.count)
        guard first.confidence >= even * 2, first.confidence >= ranked[1].confidence * 1.25 else { return nil }
        return first
    }

    private func reason(for module: NotchModule, in context: NotchIntentContext,
                        features: [String], recent: NotchModule?) -> NotchIntentReason {
        if let signal = context.signals
            .filter({ $0.weight(of: module) > 0 })
            .max(by: { $0.weight(of: module) == $1.weight(of: module) ? $0.rawValue > $1.rawValue
                         : $0.weight(of: module) < $1.weight(of: module) }) {
            return .live(signal)
        }
        if module == recent { return .resume }
        let mine = counts[module.rawValue] ?? [:]
        let seen = totals[module.rawValue] ?? 0
        if let app = context.app,
           (mine["app:" + app] ?? 0) >= 2 || NotchIntentPriors.weight(of: module, app: app) > 0 {
            return .app(context.appName ?? app)
        }
        if let scene = context.scene,
           scene.weight(of: module) > 0 || (mine["scene:" + scene.rawValue] ?? 0) >= 2 {
            return .scene(scene)
        }
        if let part = features.first(where: { $0.hasPrefix("part:") }), seen >= 3, (mine[part] ?? 0) >= seen * 0.6 {
            return .time
        }
        return .habit
    }

    private static func normalized(_ values: [Double]) -> [Double] {
        let sum = values.reduce(0, +)
        guard sum > 0, sum.isFinite else { return values.map { _ in 1 / Double(max(1, values.count)) } }
        return values.map { $0 / sum }
    }

    private static func normalized(softmax scores: [Double]) -> [Double] {
        guard let top = scores.max(), top.isFinite else { return normalized(scores.map { _ in 1 }) }
        return normalized(scores.map { exp($0 - top) })
    }
}
