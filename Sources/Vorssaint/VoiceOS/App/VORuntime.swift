// SPDX-License-Identifier: GPL-3.0-or-later
// Replaces VoiceOS Clone's AppDelegate inside Vorssaint + VoiceOS.

import AppKit
import Combine

/// Starts and stops the VoiceOS services inside Vorssaint: the fn and ⌘
/// hotkeys, the dictation pill, the VoiceOS menu bar item and the local AI
/// warm-up. Vorssaint owns the app itself (its Dock policy, appearance, main
/// menu and island), so none of that is touched here. `FeatureRuntime` runs
/// `syncWithPreferences()` at launch and whenever the Voice Assistant feature
/// is installed or removed in the Features hub.
@MainActor
final class VORuntime: NSObject {
    static let shared = VORuntime()

    let hotkeys = VOHotkeyMonitor()
    private(set) var running = false
    private var pill: VODictationPillController?
    private var bag = Set<AnyCancellable>()
    private var settings: VOSettings { VOSettings.shared }

    /// Called from Vorssaint's (non-isolated) feature bindings on the main thread.
    nonisolated static func syncWithPreferences() {
        MainActor.assumeIsolated { shared.syncWithPreferences() }
    }

    func syncWithPreferences() {
        if AppFeature.voiceAssistant.isAvailable { start() } else { stop() }
    }

    /// `harness` starts what the snapshot and self-test tools exercise: no
    /// global hotkeys and no menu bar item.
    func start(harness: Bool = false) {
        guard !running else { return }
        running = true
        VOCLIRunner.warmUp()
        pill = VODictationPillController()
        if !harness {
            wireHotkeys()
            hotkeys.start()
            VOPermissions.shared.startPolling()
            NotificationCenter.default.publisher(for: .voAccessibilityGranted)
                .sink { [weak self] _ in
                    guard let self, self.running else { return }
                    self.hotkeys.start()
                }
                .store(in: &bag)
        }
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { _ in VOClaudeWarmPool.shared.drain() }
            .store(in: &bag)

        VOProviderManager.shared.refreshAll()
        // The snapshot tool only draws, and a self-test without models only
        // runs lookups, so they leave the models alone: no
        // Ollama model loaded into memory and no Claude session started.
        guard !(harness && (VOSnapshotter.isRequested || VOSelfTest.skipsModels)) else { return }
        // Plan-usage checks (CodexBar) start heavy CLI sessions, so they only run when you open Apps/Insights.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard self?.running == true else { return }
            VOProviderManager.shared.prewarmIfUseful()
        }
        // Local-first: make sure Ollama is up and the model is loaded before the first request.
        Task {
            let usesLocal = settings.agentProvider.isLocal || settings.polishEngine == .ollama
            if usesLocal && VOLocalModels.isInstalled { await VOLocalModels.shared.start() }
            VOProviderManager.shared.refreshStatus(.ollama)
            VOLocalModels.shared.warmUp()
        }
        settings.$localModel.dropFirst().removeDuplicates()
            .sink { _ in
                DispatchQueue.main.async {
                    VOProviderManager.shared.refreshStatus(.ollama)
                    VOLocalModels.shared.warmUp()
                }
            }
            .store(in: &bag)
    }

    func stop() {
        guard running else { return }
        running = false
        bag.removeAll()
        hotkeys.stop()
        VOPermissions.shared.stopPolling()
        VODictationController.shared.cancel()
        VOAssistantController.shared.close()
        VOAssistantVoice.shared.stop()
        VOClaudeWarmPool.shared.drain()
        pill?.close()
        pill = nil
    }

    // MARK: - Shared with Vorssaint

    /// Vorssaint's Mic Mute holds the input silent. VoiceOS says so instead of
    /// listening to nothing.
    static var microphoneIsMuted: Bool {
        AppFeature.micMute.isAvailable && MicMuteService.shared.isMuted
    }

    static let microphoneMutedHint = "Your microphone is muted with Mic Mute. Unmute it to talk, or type instead."

    // MARK: - Hotkeys

    private func wireHotkeys() {
        let dictation = VODictationController.shared
        let agent = VOAssistantController.shared
        hotkeys.onDictationStart = { if !agent.expanded || agent.phase != .listening { dictation.begin() } }
        hotkeys.onDictationStop = { dictation.finish() }
        hotkeys.onDictationCancel = { dictation.cancel() }
        hotkeys.onHandsFreeStart = { dictation.begin(handsFree: true) }
        hotkeys.onAgentStart = { if !dictation.isActive { agent.startListening() } }
        hotkeys.onAgentStop = { agent.stopListening() }
        hotkeys.onAgentCancel = { agent.cancelListening() }
        hotkeys.onEscape = { [weak self] in
            if dictation.isActive {
                dictation.cancel()
                self?.hotkeys.endHandsFree()
                return true
            }
            // With the island holding the keyboard, its own Escape steps back
            // and closes it; this answers the Escape typed in another app.
            if agent.expanded, !VOIsland.isTyping {
                agent.close()
                return true
            }
            return false
        }
    }

    // MARK: - Menu

    /// VoiceOS's menu lives in Vorssaint's own menu bar item, as a VoiceOS
    /// submenu of its secondary-click menu: one icon for the one app.
    nonisolated static func appendMenu(to menu: NSMenu) {
        MainActor.assumeIsolated {
            guard shared.running else { return }
            let submenu = NSMenu()
            shared.fillMenu(submenu)
            let item = NSMenuItem(title: "VoiceOS", action: nil, keyEquivalent: "")
            item.submenu = submenu
            menu.addItem(item)
        }
    }

    private func fillMenu(_ menu: NSMenu) {
        menu.addItem(withTitle: "Open VoiceOS", action: #selector(openMain), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Ask the Assistant…", action: #selector(openAgent), keyEquivalent: "").target = self
        menu.addItem(.separator())

        let agentMenu = NSMenu()
        for p in VOProviderID.allCases {
            let mi = NSMenuItem(title: p.displayName, action: #selector(pickAgent(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = p.rawValue
            mi.state = settings.agentProvider == p ? .on : .off
            agentMenu.addItem(mi)
        }
        let agentItem = NSMenuItem(title: "Assistant AI", action: nil, keyEquivalent: "")
        agentItem.submenu = agentMenu
        menu.addItem(agentItem)

        let polishMenu = NSMenu()
        for e in VOPolishEngine.allCases {
            let mi = NSMenuItem(title: e.label, action: #selector(pickPolish(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = e.rawValue
            mi.state = settings.polishEngine == e ? .on : .off
            polishMenu.addItem(mi)
        }
        let polishItem = NSMenuItem(title: "Dictation cleanup", action: nil, keyEquivalent: "")
        polishItem.submenu = polishMenu
        menu.addItem(polishItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: "History", action: #selector(openHistory), keyEquivalent: "").target = self
        menu.addItem(withTitle: "VoiceOS Settings…", action: #selector(openApps), keyEquivalent: "").target = self
    }

    @objc private func openMain() { VOMainWindow.show() }
    @objc private func openHistory() { VOMainWindow.show(.history) }
    @objc private func openApps() { VOMainWindow.show(.apps) }
    @objc private func openAgent() { VOAssistantController.shared.open(focus: true) }
    @objc private func pickAgent(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let p = VOProviderID(rawValue: raw) { settings.agentProvider = p }
    }
    @objc private func pickPolish(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let e = VOPolishEngine(rawValue: raw) { settings.polishEngine = e }
    }
}
