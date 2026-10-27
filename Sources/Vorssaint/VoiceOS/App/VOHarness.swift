// SPDX-License-Identifier: GPL-3.0-or-later
// Runs VoiceOS Clone's developer tools inside Vorssaint + VoiceOS.

import AppKit
import SwiftUI

/// `VOICEOS_SNAPSHOT=<dir>` renders the assistant's island states, the
/// dictation pill and the VoiceOS settings pages to PNGs; `VOICEOS_SELFTEST=<file>`
/// sends a dictation cleanup and a few assistant requests through the real
/// router with the voice muted and actions never executed. Either one starts
/// only what it exercises: the island, the assistant and the settings
/// window. Vorssaint's system features, every global hotkey and the menu bar
/// items stay off, so a test run cannot change anything on the Mac, and the
/// app quits when the tool is done. Run them from a copy with its own bundle
/// id (Tools/voiceos-harness.sh) so even the preferences they touch are throwaway.
enum VOHarness {
    static var isRequested: Bool {
        let env = ProcessInfo.processInfo.environment
        return !(env["VOICEOS_SNAPSHOT"] ?? "").isEmpty || !(env["VOICEOS_SELFTEST"] ?? "").isEmpty
    }

    static func runAndExit() -> Never {
        MainActor.assumeIsolated {
            // Registered, not saved: a real install keeps its own choices.
            UserDefaults.standard.register(defaults: MergedSettingsImport.voiceOSIsland
                .merging(MergedSettingsImport.islandHub) { _, new in new }
                .merging([
                    AppFeature.notch.availabilityKey: true,
                    DefaultsKey.notchEnabled: true,
                ]) { _, new in new })
            let app = NSApplication.shared
            let delegate = VOHarnessDelegate()
            app.delegate = delegate
            withExtendedLifetime(delegate) { app.run() }
        }
        exit(0)
    }
}

@MainActor
private final class VOHarnessDelegate: NSObject, NSApplicationDelegate {
    private var settingsWindow: SettingsWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppAppearanceController.shared.apply()
        NotchService.shared.syncWithPreferences()
        VORuntime.shared.start(harness: true)
        VOMainWindow.presentSettings = { [weak self] in self?.showSettings() }
        // A tool that never finishes must not leave the app running.
        DispatchQueue.main.asyncAfter(deadline: .now() + 900) { exit(2) }
        if !(VOSnapshotter.runIfRequested() || VOSelfTest.runIfRequested()) { NSApp.terminate(nil) }
    }

    /// Vorssaint's Settings window as the app delegate builds it, without
    /// taking focus from the app in front: the snapshot reads its own windows.
    private func showSettings() {
        if settingsWindow == nil {
            let host = NSHostingController(rootView: SettingsView())
            host.sizingOptions = []
            let window = SettingsWindow(contentViewController: host)
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 1080, height: 760))
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            window.title = L10n.shared.s.settingsTitle
            window.center()
            settingsWindow = window
        }
        SettingsWindowVisibility.shared.set(true)
        settingsWindow?.orderFrontRegardless()
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotchService.shared.stop(restoreCapture: false)
    }
}
