// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Taking things off the island and putting them back, and the home
/// filling the room of what went.
enum NotchCustomizationTests {
    static func run(_ suite: TestSuite) {
        let name = "com.vorssaint.tests.island-customization-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }

        var layout = NotchCustomization.homeLayout(cameraEnabled: false, in: defaults)
        suite.expect(layout == .init(calendar: true, camera: false, actions: true, actionColumns: 3, actionRows: 4),
                     "the home starts whole: the calendar beside four rows of shortcuts")
        NotchCustomization.remove(.widget(.calendar), in: defaults)
        layout = NotchCustomization.homeLayout(cameraEnabled: false, in: defaults)
        suite.expect(!layout.calendar && layout.actions && layout.actionColumns == 6,
                     "without the calendar the shortcuts spread across its room")
        layout = NotchCustomization.homeLayout(cameraEnabled: true, in: defaults)
        suite.expect(layout.camera && layout.actionColumns == 3 && layout.actionRows == 4,
                     "beside the camera the shortcuts take the rest of the row")
        NotchCustomization.remove(.widget(.actions), in: defaults)
        suite.expect(NotchCustomization.homeLayout(cameraEnabled: false, in: defaults).isEmpty,
                     "with every part removed the home says how to bring them back")

        let first = NotchCustomization.homeActions(in: defaults).first
        if let first {
            NotchCustomization.remove(.homeAction(first), in: defaults)
            suite.expect(NotchCustomization.homeActions(in: defaults).first != first
                         && !NotchCustomization.homeActions(in: defaults).contains(first),
                         "a removed shortcut leaves its place to the next")
        }
        NotchCustomization.remove(.page(.timer), in: defaults)
        NotchCustomization.remove(.page(.timer), in: defaults)
        suite.expect(defaults.string(forKey: DefaultsKey.notchHiddenModules) == "timer",
                     "a page is removed once, in the list Settings shows")
        NotchCustomization.remove(.control(.keepAwake), in: defaults)
        suite.expect((defaults.string(forKey: DefaultsKey.notchHiddenControls) ?? "")
                        .split(separator: ",").contains("keepAwake")
                     && (defaults.string(forKey: DefaultsKey.notchHiddenControls) ?? "")
                        .split(separator: ",").contains("microphone"),
                     "removing a control keeps the controls hidden from the start")

        let addable = NotchCustomization.addable(in: defaults, cameraEnabled: false)
        suite.expect(addable.contains(.widget(.calendar)) && addable.contains(.widget(.actions))
                     && !addable.contains(.widget(.camera)) && !addable.contains(.widget(.nowPlaying)),
                     "the way back lists the home's removed parts, and only those that can show")
        for item in addable { NotchCustomization.restore(item, in: defaults) }
        suite.expect(NotchCustomization.homeLayout(cameraEnabled: false, in: defaults).calendar
                     && NotchCustomization.addable(in: defaults, cameraEnabled: false).isEmpty,
                     "adding everything back restores the home")
    }
}
