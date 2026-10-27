// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum NotchIntentTests {
    static func run(_ suite: TestSuite) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        // A Tuesday morning and a Saturday evening.
        let tuesday = Date(timeIntervalSince1970: 1_793_664_000 + 9 * 3600)
        let saturday = Date(timeIntervalSince1970: 1_794_009_600 + 19 * 3600)
        let pages: [NotchModule] = [.controls, .music, .clipboard, .files, .calendar, .timer, .agents, .scratchpad]

        let morning = NotchIntentContext(app: "com.apple.Safari", appName: "Safari", date: tuesday)
        suite.expect(morning.features(calendar: calendar)
                        == ["app:com.apple.Safari", "part:morning", "day:weekday"],
                     "a context learns from its app, the part of the day and the kind of day")
        suite.expect(NotchIntentContext(date: saturday).features(calendar: calendar) == ["part:evening", "day:weekend"],
                     "a weekend evening is told apart from a weekday morning")
        suite.expect(NotchIntentContext.dayPart(hour: 23) == "night" && NotchIntentContext.dayPart(hour: 5) == "night"
                        && NotchIntentContext.dayPart(hour: 6) == "morning" && NotchIntentContext.dayPart(hour: 12) == "afternoon",
                     "the day splits into four parts")

        let empty = NotchIntentModel()
        let even = empty.rank(pages, in: NotchIntentContext(date: tuesday), calendar: calendar)
        suite.expect(even.map(\.module) == pages && NotchIntentModel.notable(even, limit: 3).isEmpty,
                     "with nothing learned and nothing going on, no page is singled out")

        let playing = empty.rank(pages, in: NotchIntentContext(date: tuesday, signals: [.playing]), calendar: calendar)
        suite.expect(playing.first?.module == .music && playing.first?.reason == .live(.playing),
                     "a song playing puts the player first and says so")
        let meeting = empty.rank(pages, in: NotchIntentContext(date: tuesday, signals: [.meetingSoon, .copied]),
                                 calendar: calendar)
        suite.expect(meeting.prefix(2).map(\.module) == [.calendar, .clipboard],
                     "several live signals rank their pages by how strongly each points")

        let xcode = empty.rank(pages, in: NotchIntentContext(app: "com.apple.dt.Xcode", appName: "Xcode", date: tuesday),
                               calendar: calendar)
        suite.expect(xcode.first?.module == .agents && xcode.first?.reason == .app("Xcode"),
                     "before anything is learned, a coding app suggests the agents' usage")
        suite.expect(NotchIntentModel.opening(xcode)?.module == .agents,
                     "a coding app in front opens the island on the agents' usage")
        let safari = empty.rank(pages + [.downloads],
                                in: NotchIntentContext(app: "com.apple.Safari", appName: "Safari", date: tuesday),
                                calendar: calendar)
        suite.expect(NotchIntentModel.opening(safari) == nil && NotchIntentModel.opening(even) == nil,
                     "a near tie, or nothing at all, leaves the island to open on its home page")
        suite.expect(!NotchIntentSignal.copied.opensPage && !NotchIntentSignal.captured.opensPage
                        && NotchIntentSignal.meetingSoon.opensPage,
                     "a copy or a capture only hints; an event about to start opens its page")
        suite.expect(NotchIntentPriors.weight(of: .agents, app: "com.jetbrains.intellij") > 0,
                     "a family of apps is matched by its bundle id's prefix")

        var model = NotchIntentModel()
        for _ in 0..<8 { model.learn(.files, in: morning, calendar: calendar) }
        model.learn(.music, in: NotchIntentContext(app: "com.spotify.client", appName: "Spotify", date: saturday),
                    calendar: calendar)
        let later = NotchIntentContext(app: "com.apple.Safari", appName: "Safari", date: tuesday.addingTimeInterval(3600))
        let learned = model.rank(pages, in: later, calendar: calendar)
        suite.expect(learned.first?.module == .files && learned.first?.reason == .app("Safari"),
                     "a page opened again and again with an app is suggested with it, over the app's own priors")
        suite.expect(NotchIntentModel.notable(learned, limit: 3).first?.module == .files,
                     "a learned habit is notable enough to show")

        let soon = model.rank(pages, in: NotchIntentContext(app: "com.apple.Safari", appName: "Safari",
                                                            date: tuesday.addingTimeInterval(8 * 3600 + 5 * 60)),
                              calendar: calendar)
        suite.expect(model.recent(at: tuesday.addingTimeInterval(8 * 3600 + 5 * 60)) == nil
                        && model.recent(at: saturday.addingTimeInterval(60)) == .music,
                     "the last page counts as where the person left off for a quarter of an hour")
        suite.expect(soon.first?.module == .files, "habits outlast the quarter hour")

        var fading = NotchIntentModel()
        fading.learn(.calendar, in: morning, calendar: calendar)
        for _ in 0..<400 { fading.learn(.timer, in: NotchIntentContext(date: saturday), calendar: calendar) }
        suite.expect(fading.totals["calendar"] == nil && fading.counts["calendar"] == nil,
                     "a page no longer chosen fades out of the store")
        suite.expect(fading.counts["timer"].map { $0.count <= NotchIntentModel.featureLimit } == true,
                     "each page keeps a bounded set of features")

        let encoded = try? JSONEncoder().encode(model)
        let decoded = encoded.flatMap { try? JSONDecoder().decode(NotchIntentModel.self, from: $0) }
        suite.expect(decoded == model, "the model survives being saved and read back")

        suite.expect(NotchIntentScene.classify(title: "Weekly sync - Google Meet", app: "com.google.Chrome") == .meeting
                        && NotchIntentScene.classify(title: nil, app: "us.zoom.xos") == .meeting
                        && NotchIntentScene.classify(title: "Fix the build · Pull Request #12", app: nil) == .code
                        && NotchIntentScene.classify(title: "Lo-fi beats - YouTube", app: nil) == .media
                        && NotchIntentScene.classify(title: "Groceries", app: "com.apple.Notes") == nil,
                     "a window's title reduces to one word, or to none")
    }
}
