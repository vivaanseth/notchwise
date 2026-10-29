// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Vorssaint + VoiceOS has a bundle id of its own, so it installs next to the
/// standalone apps and starts with an empty preferences domain. Its first
/// launch copies their saved choices once: Vorssaint's as they are, VoiceOS
/// Clone's under the "voiceos." keys. Nothing is copied back, and the
/// standalone apps' own preferences are only read. The island then starts
/// as VoiceOS's: a notch hanging from the top edge, home to the assistant.
enum MergedSettingsImport {
    static let mergedBundleID = "com.vorssaint.voiceos"
    static let vorssaintDomain = "com.vorssaint.utils"
    static let importedKey = "mergedSettingsImported"

    /// Keys that record the standalone install rather than a choice: the
    /// fan helper registered for its bundle, a sleep setting it changed and
    /// must restore itself, and its login item, which would otherwise start
    /// both apps at login.
    static let skippedKeys: Set<String> = [
        DefaultsKey.fanControlHelperVersion,
        DefaultsKey.fanControlRecoveryNeeded,
        DefaultsKey.sleepDisabledFlag,
        DefaultsKey.launchAtLoginWanted,
    ]

    static let voiceOSIsland: [String: Any] = [
        AppFeature.voiceAssistant.availabilityKey: true,
        DefaultsKey.notchSilhouette: NotchSilhouette.notch.rawValue,
        DefaultsKey.notchReturnHome: true,
        DefaultsKey.notchHomeModule: NotchModule.voice.rawValue,
        // First in the sections, the rest in their usual order after it.
        DefaultsKey.notchModuleOrder: NotchModule.voice.rawValue,
    ]

    /// Hovering opens the island's home, its dashboard, and a click opens
    /// the page that fits the moment. The pointer rests a little longer
    /// before a hover opens it, the bars follow the music playing, and the
    /// buttons around the island start with Home and a suggestion. Set once,
    /// when it arrived; Settings changes any of it afterwards.
    static let hoverHomeKey = "mergedIslandHoverHomeApplied"
    static let hoverDelay = 0.45
    static let islandButtons = NotchQuickAccessConfiguration(buttons: [
        NotchQuickButton(action: .home, side: .left),
        NotchQuickButton(action: .explore, side: .left),
        NotchQuickButton(action: .module(.agents), side: .left),
        NotchQuickButton(action: .suggested, side: .right),
        NotchQuickButton(action: .module(.timer), side: .right),
        NotchQuickButton(action: .module(.mixer), side: .right),
        NotchQuickButton(action: .module(.music), side: .bottom),
        NotchQuickButton(action: .module(.notifications), side: .bottom),
        NotchQuickButton(action: .module(.clipboard), side: .bottom),
    ])

    static func applyHoverHomeOnce(_ defaults: UserDefaults = .standard,
                                   bundleID: String? = Bundle.main.bundleIdentifier) {
        guard bundleID == mergedBundleID, !defaults.bool(forKey: hoverHomeKey) else { return }
        // Hidden until hover already opens on hover, and stays as chosen.
        if defaults.object(forKey: DefaultsKey.notchHideUntilHover) as? Bool != true {
            defaults.set(true, forKey: DefaultsKey.notchOpenOnHover)
            defaults.set(true, forKey: DefaultsKey.notchHoverExpands)
        }
        if defaults.object(forKey: DefaultsKey.notchHoverDelay) == nil {
            defaults.set(hoverDelay, forKey: DefaultsKey.notchHoverDelay)
        }
        if defaults.object(forKey: DefaultsKey.notchLiveEqualizer) == nil {
            defaults.set(true, forKey: DefaultsKey.notchLiveEqualizer)
        }
        defaults.set(islandButtons.encoded, forKey: DefaultsKey.notchQuickAccessLayout)
        defaults.set(true, forKey: hoverHomeKey)
    }

    /// A full-screen app has the display to itself: the island leaves the
    /// display it covers, and comes back with the desktop. Set once.
    static let fullscreenKey = "mergedIslandHidesInFullscreen"

    static func hideInFullscreenOnce(_ defaults: UserDefaults = .standard,
                                     bundleID: String? = Bundle.main.bundleIdentifier) {
        guard bundleID == mergedBundleID, !defaults.bool(forKey: fullscreenKey) else { return }
        if defaults.object(forKey: DefaultsKey.notchHideInFullscreen) == nil {
            defaults.set(true, forKey: DefaultsKey.notchHideInFullscreen)
        }
        defaults.set(true, forKey: fullscreenKey)
    }

    /// Everything the app controls has a tile on the island's Controls page:
    /// All controls, hidden until now, joins the panel's own sections there.
    /// Set once, after `Defaults.register()`, so a first launch's migrations
    /// still see an island nobody has set up.
    static let allControlsKey = "mergedIslandShowsAllControls"

    static func showAllControlsOnce(_ defaults: UserDefaults = .standard,
                                    bundleID: String? = Bundle.main.bundleIdentifier) {
        guard bundleID == mergedBundleID, !defaults.bool(forKey: allControlsKey) else { return }
        let hidden = (defaults.string(forKey: DefaultsKey.notchHiddenControls) ?? NotchControlItem.defaultHidden)
            .split(separator: ",").map(String.init).filter { $0 != NotchControlItem.panel.rawValue }
        defaults.set(hidden.joined(separator: ","), forKey: DefaultsKey.notchHiddenControls)
        defaults.set(true, forKey: allControlsKey)
    }

    /// Runs before `Defaults.register()`, so the migrations there see the
    /// copied values the way the standalone app saved them.
    static func runOnce(_ defaults: UserDefaults = .standard,
                        bundleID: String? = Bundle.main.bundleIdentifier) {
        guard bundleID == mergedBundleID, !defaults.bool(forKey: importedKey) else { return }
        if let vorssaint = defaults.persistentDomain(forName: vorssaintDomain) {
            for (key, value) in vorssaint where !skippedKeys.contains(key) && defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
        }
        VOSettings.importStandaloneApp(into: defaults,
                                       from: defaults.persistentDomain(forName: VOSettings.standaloneDomain))
        // The assistant is installed, and the island is VoiceOS's: on a display
        // without a camera it hangs from the top edge as the black notch VoiceOS
        // drew there, and it opens on the assistant, its home page. Each only
        // where no choice was saved.
        for (key, value) in voiceOSIsland where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
        defaults.set(true, forKey: importedKey)
    }
}
