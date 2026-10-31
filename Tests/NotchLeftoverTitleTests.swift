// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// A song a page left behind is told from one still playing. The readings
/// are the ones Edge sent on 2026-10-31: a Thriller note on Instagram, then
/// reels playing beneath its name.
enum NotchLeftoverTitleTests {
    static func run(_ suite: TestSuite) {
        let start = Date(timeIntervalSinceReferenceDate: 815_000_000)
        func reading(_ title: String = "Thriller", at seconds: TimeInterval, elapsed: TimeInterval,
                     playing: Bool = true, duration: TimeInterval = 21.709) -> NotchPlayback {
            NotchPlayback(track: RadialNowPlayingSnapshot(title: title, artist: "Michael Jackson", album: nil,
                                                          artworkData: nil, appBundleIdentifier: "com.microsoft.edgemac",
                                                          appPID: 785),
                          isPlaying: playing, elapsed: elapsed, duration: duration, rate: 1,
                          sampledAt: start.addingTimeInterval(seconds), canSeek: false)
        }

        var reels = NotchLeftoverTitle()
        suite.expect(!reels.observe(reading(at: 0, elapsed: 0.09)), "a song is named when it starts")
        suite.expect(!reels.observe(reading(at: 6, elapsed: 0.10)), "one restart could be the person stepping back")
        suite.expect(reels.observe(reading(at: 14, elapsed: 0.02)),
                     "a second restart partway through within a minute marks the name as left over")
        suite.expect(reels.observe(reading(at: 18, elapsed: 0.95)), "and it stays left over")
        suite.expect(!reels.observe(reading("Beat It", at: 20, elapsed: 0.1)), "a new name is trusted again")

        var song = NotchLeftoverTitle()
        var leftover = false
        for second in stride(from: 0.0, through: 60, by: 5) {
            leftover = song.observe(reading(at: second, elapsed: second, duration: 240)) || leftover
        }
        suite.expect(!leftover, "a song that plays on is never left over")

        var loop = NotchLeftoverTitle()
        for round in 0..<4 {
            let base = Double(round) * 21.8
            _ = loop.observe(reading(at: base, elapsed: 0.05))
            _ = loop.observe(reading(at: base + 21, elapsed: 21))
        }
        suite.expect(!loop.isLeftover, "a clip looping at its end is not restarting")

        var paused = NotchLeftoverTitle()
        _ = paused.observe(reading(at: 0, elapsed: 10))
        _ = paused.observe(reading(at: 30, elapsed: 0.1, playing: false))
        _ = paused.observe(reading(at: 40, elapsed: 0.2))
        _ = paused.observe(reading(at: 50, elapsed: 0.1, playing: false))
        suite.expect(!paused.isLeftover, "a paused player moving to the start is not restarting")

        let named = reading(at: 0, elapsed: 4)
        let unnamed = named.withoutSong(appName: "Microsoft Edge")
        suite.expect(unnamed.track.title == nil && unnamed.track.artist == "Microsoft Edge"
                     && unnamed.track.appPID == 785 && unnamed.isPlaying && !unnamed.hasPosition
                     && !unnamed.canSeek && unnamed.track.artworkData == nil,
                     "without its song the island names only the app, with no cover or timeline")
    }
}
