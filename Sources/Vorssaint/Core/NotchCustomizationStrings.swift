// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Removing things from the island and adding them back. English for now:
/// every language reads these until they are translated.
struct NotchCustomizationFeatureStrings {
    let removeFromHome = "Remove from Home"
    let removeShortcuts = "Remove All Shortcuts from Home"
    let removeFromIsland = "Remove from Island"
    let removeFromControls = "Remove from Controls"
    let removeAssistant = "Remove Assistant from Island"
    let assistant = "Assistant"
    let addToIsland = "Add to Island"
    let home = "Home"
    let pages = "Pages"
    let controls = "Controls"
    let calendar = "Calendar"
    let camera = "Camera"
    let shortcuts = "Shortcuts"
    let nowPlaying = "Now Playing"
    let homeEmpty = "Everything is off the home. Right-click the island and choose Add to Island to bring it back."

    static let enUS = NotchCustomizationFeatureStrings()
}

extension FeatureStrings {
    static func notchCustomization(_ language: AppLanguage) -> NotchCustomizationFeatureStrings {
        .enUS
    }
}
