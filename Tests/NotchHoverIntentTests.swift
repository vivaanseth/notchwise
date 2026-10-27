// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum NotchHoverIntentTests {
    static func run(_ suite: TestSuite) {
        var still = NotchHoverIntent()
        suite.expect(still.rests(at: 10, current: CGPoint(x: 100, y: 890)),
                     "a pointer that has not moved rests on the island")

        var crossing = NotchHoverIntent()
        for step in 0..<10 {
            crossing.record(CGPoint(x: 600 + Double(step) * 12, y: 895), at: 10 + Double(step) * 0.02)
        }
        suite.expect(!crossing.rests(at: 10.19, current: CGPoint(x: 708, y: 895)),
                     "a pointer crossing the island on its way along the menu bar does not open it")
        suite.expect(crossing.rests(at: 10.6, current: CGPoint(x: 708, y: 895)),
                     "once it has stopped for a moment, the same pointer rests")

        var settling = NotchHoverIntent()
        settling.record(CGPoint(x: 700, y: 880), at: 20)
        settling.record(CGPoint(x: 702, y: 881), at: 20.1)
        settling.record(CGPoint(x: 703, y: 881), at: 20.18)
        suite.expect(settling.rests(at: 20.2, current: CGPoint(x: 703, y: 882)),
                     "a hand drifting a few points still rests")

        still.record(CGPoint(x: 0, y: 0), at: 30)
        still.reset()
        suite.expect(still.rests(at: 30.05, current: CGPoint(x: 400, y: 400)),
                     "leaving forgets the moves made over the island")

        suite.expect(NotchQuickAction(id: NotchQuickAction.home.id) == .home
                        && NotchQuickAction(id: NotchQuickAction.suggested.id) == .suggested
                        && NotchQuickAction.optionalActions.prefix(3) == [.home, .explore, .suggested],
                     "Home and the suggestion are buttons the island can be given and keep")
    }
}
