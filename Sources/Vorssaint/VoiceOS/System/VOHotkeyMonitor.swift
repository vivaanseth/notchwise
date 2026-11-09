// SPDX-License-Identifier: GPL-3.0-or-later
// Ported from VoiceOS Clone (System/HotkeyMonitor.swift) into Vorssaint + VoiceOS.

import AppKit

/// Watches modifier keys system-wide:
/// - hold fn (or chosen key) → dictation, double-tap → hands-free
/// - hold right ⌘ (or chosen key) → agent push-to-talk
/// Any other key pressed while a trigger is held cancels it, so normal shortcuts keep working.
final class VOHotkeyMonitor {
    var onDictationStart: (() -> Void)?
    var onDictationStop: (() -> Void)?
    var onDictationCancel: (() -> Void)?
    var onHandsFreeStart: (() -> Void)?
    var onAgentStart: (() -> Void)?
    var onAgentStop: (() -> Void)?
    var onAgentCancel: (() -> Void)?
    var onEscape: (() -> Bool)?    // return true if handled

    private var monitors: [Any] = []
    private let settings = VOSettings.shared

    private var dictKeyDown = false
    private var dictStarted = false
    private var dictPressedAt = Date.distantPast
    private var lastDictTapAt = Date.distantPast
    private(set) var handsFree = false
    private var dictTimer: DispatchWorkItem?

    private var agentKeyDown = false
    private var agentStarted = false
    private var agentTimer: DispatchWorkItem?

    func start() {
        stop()
        if let g = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown], handler: { [weak self] e in self?.handle(e) }) {
            monitors.append(g)
        }
        if let l = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown], handler: { [weak self] e in
            if self?.handle(e) == true { return nil }
            return e
        }) {
            monitors.append(l)
        }
    }

    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
    }

    func endHandsFree() { handsFree = false }

    // MARK: -

    @discardableResult
    private func handle(_ e: NSEvent) -> Bool {
        if e.type == .keyDown {
            if e.keyCode == 53 { // escape
                if handsFree { handsFree = false; dictStarted = false; onDictationCancel?(); return true }
                return onEscape?() ?? false
            }
            // Another key while holding a trigger → it's a normal shortcut, not voice.
            if dictKeyDown { cancelDictationHold() }
            if agentKeyDown { cancelAgentHold() }
            return false
        }
        guard e.type == .flagsChanged else { return false }
        // Off, the keys are the system's again. A press already under way
        // still ends, so nothing is left listening.
        guard triggersEnabled() || dictKeyDown || agentKeyDown || handsFree else { return false }
        handleDictation(e)
        handleAgent(e)
        return false
    }

    /// Whether holding the dictation or assistant key starts listening.
    var triggersEnabled: () -> Bool = { true }

    private func isDictationKey(_ e: NSEvent) -> (matches: Bool, down: Bool) {
        // A modifier Vorssaint's Super Key has taken stays Super Key's.
        if VOHotkeyConflicts.superKeyClaims(keyCode: e.keyCode) { return (false, false) }
        switch settings.dictationTrigger {
        case .fn: return (e.keyCode == 63 || e.keyCode == 179, e.modifierFlags.contains(.function))
        case .rightOption: return (e.keyCode == 61, e.modifierFlags.contains(.option))
        case .rightControl: return (e.keyCode == 62, e.modifierFlags.contains(.control))
        }
    }

    private func isAgentKey(_ e: NSEvent) -> (matches: Bool, down: Bool) {
        if VOHotkeyConflicts.superKeyClaims(keyCode: e.keyCode) { return (false, false) }
        switch settings.agentTrigger {
        case .rightCommand: return (e.keyCode == 54, e.modifierFlags.contains(.command))
        case .leftCommand: return (e.keyCode == 55, e.modifierFlags.contains(.command))
        case .eitherCommand: return (e.keyCode == 54 || e.keyCode == 55, e.modifierFlags.contains(.command))
        case .rightOption: return (e.keyCode == 61, e.modifierFlags.contains(.option))
        }
    }

    private func handleDictation(_ e: NSEvent) {
        let k = isDictationKey(e)
        guard k.matches else {
            // Another modifier joined (e.g. fn+⌃): treat as a shortcut.
            if dictKeyDown && !dictStarted { cancelDictationHold() }
            return
        }
        if k.down && !dictKeyDown {
            dictKeyDown = true
            dictPressedAt = Date()
            if handsFree {
                // A tap while hands-free ends the session.
                handsFree = false
                dictStarted = false
                onDictationStop?()
                dictKeyDown = false
                return
            }
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.dictKeyDown else { return }
                self.dictStarted = true
                self.onDictationStart?()
            }
            dictTimer = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
        } else if !k.down && dictKeyDown {
            dictKeyDown = false
            dictTimer?.cancel()
            let held = Date().timeIntervalSince(dictPressedAt)
            if dictStarted {
                dictStarted = false
                if held < 0.3 {
                    onDictationCancel?()
                } else {
                    onDictationStop?()
                }
            }
            if held < 0.3 && settings.doubleTapHandsFree {
                if Date().timeIntervalSince(lastDictTapAt) < 0.45 {
                    lastDictTapAt = .distantPast
                    handsFree = true
                    onHandsFreeStart?()
                } else {
                    lastDictTapAt = Date()
                }
            }
        }
    }

    private func cancelDictationHold() {
        dictTimer?.cancel()
        dictKeyDown = false
        if dictStarted && !handsFree {
            dictStarted = false
            onDictationCancel?()
        }
    }

    private func handleAgent(_ e: NSEvent) {
        let k = isAgentKey(e)
        guard k.matches else {
            if agentKeyDown { cancelAgentHold() }
            return
        }
        if k.down && !agentKeyDown {
            agentKeyDown = true
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.agentKeyDown else { return }
                self.agentStarted = true
                self.onAgentStart?()
            }
            agentTimer = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: work)
        } else if !k.down && agentKeyDown {
            agentKeyDown = false
            agentTimer?.cancel()
            if agentStarted {
                agentStarted = false
                onAgentStop?()
            }
        }
    }

    private func cancelAgentHold() {
        agentTimer?.cancel()
        agentKeyDown = false
        if agentStarted {
            agentStarted = false
            onAgentCancel?()
        }
    }
}
