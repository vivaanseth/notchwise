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

        // Reels as the island hears them: each change pauses one video where
        // it got to and plays the next from the start, under the note's name.
        var paused = NotchLeftoverTitle()
        _ = paused.observe(reading(at: 0, elapsed: 0.1))
        _ = paused.observe(reading(at: 9, elapsed: 9.2, playing: false))
        suite.expect(!paused.observe(reading(at: 9.3, elapsed: 0.05)), "one reel change after a pause")
        _ = paused.observe(reading(at: 16, elapsed: 6.8, playing: false))
        suite.expect(paused.observe(reading(at: 16.2, elapsed: 0.02)),
                     "a second reel change after a pause marks the note's name as left over")

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

        var resting = NotchLeftoverTitle()
        _ = resting.observe(reading(at: 0, elapsed: 10, playing: false))
        _ = resting.observe(reading(at: 30, elapsed: 10, playing: false))
        _ = resting.observe(reading(at: 40, elapsed: 10.5))
        suite.expect(!resting.isLeftover, "a song paused and played again where it was is not restarting")

        // Covers, as Edge sent them on 2026-11-01: a note's song by Ken
        // Carson, then the reels under Instagram's own name with no artist.
        func edgeReport(_ title: String?, _ artist: String?, _ cover: [UInt8]?) -> NotchPlayback {
            NotchPlayback(track: RadialNowPlayingSnapshot(title: title, artist: artist, album: nil,
                                                          artworkData: cover.map { Data($0) },
                                                          appBundleIdentifier: "com.microsoft.edgemac", appPID: 785),
                          isPlaying: true, elapsed: 0, duration: 20, rate: 1, sampledAt: start, canSeek: false)
        }
        let ghoul = edgeReport("Ghoul", "Ken Carson", [1, 2, 3])
        var covers = NotchArtworkCache<String>()
        covers.update("ghoul", for: ghoul, now: start)
        covers.update("ghoul", for: edgeReport("Netflix", "Ken Carson", [1, 2, 3]), now: start.addingTimeInterval(0.4))
        covers.update("ghoul", for: edgeReport("Instagram", nil, [1, 2, 3]), now: start.addingTimeInterval(0.8))
        suite.expect(covers.artwork == nil, "a song's cover sent on with the page's own name is not the page's")
        covers.update("ghoul", for: edgeReport("Instagram", nil, [1, 2, 3]), now: start.addingTimeInterval(5))
        suite.expect(covers.artwork == nil, "and stays ignored while the page keeps sending it")
        covers.update("reel", for: edgeReport("Instagram", nil, [7, 8, 9]), now: start.addingTimeInterval(6))
        suite.expect(covers.artwork == "reel", "a cover of the page's own is shown")
        covers = NotchArtworkCache<String>()
        covers.update("ghoul", for: ghoul, now: start)
        covers.update(nil, for: edgeReport("Instagram", nil, nil), now: start.addingTimeInterval(0.2))
        suite.expect(covers.artwork == nil, "a page's name without a cover drops the song's cover at once")
        covers = NotchArtworkCache<String>()
        covers.update("ghoul", for: ghoul, now: start)
        covers.update(nil, for: ghoul.withoutSong(appName: "Microsoft Edge"), now: start.addingTimeInterval(0.2))
        suite.expect(covers.artwork == nil, "a song judged left over takes its cover with it at once")

        let named = reading(at: 0, elapsed: 4)
        let unnamed = named.withoutSong(appName: "Microsoft Edge")
        suite.expect(unnamed.track.title == nil && unnamed.track.artist == "Microsoft Edge"
                     && unnamed.track.appPID == 785 && unnamed.isPlaying && !unnamed.hasPosition
                     && !unnamed.canSeek && unnamed.track.artworkData == nil,
                     "without its song the island names only the app, with no cover or timeline")
    }
}
