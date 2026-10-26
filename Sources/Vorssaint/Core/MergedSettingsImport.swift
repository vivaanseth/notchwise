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
