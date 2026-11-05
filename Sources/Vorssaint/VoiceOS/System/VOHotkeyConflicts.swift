// SPDX-License-Identifier: GPL-3.0-or-later
// Where VoiceOS's hold keys meet Vorssaint's own shortcuts.

import AppKit

/// Vorssaint's Super Key can take over right ⌘, ⌥, ⌃ or ⇧ (Caps Lock by
/// default), the same modifiers VoiceOS holds to listen. Super Key keeps its
/// key: VoiceOS stands down on it and says so beside its own key choice, and
/// the other choices keep working.
enum VOHotkeyConflicts {
    /// The modifier Super Key holds while it runs, or nil when it holds none
    /// VoiceOS could use.
    static var superKeySource: SuperKeySource? {
        let defaults = UserDefaults.standard
        guard AppFeature.superKey.isAvailable, defaults.bool(forKey: DefaultsKey.superKeyEnabled) else { return nil }
        let source = SuperKeySource.sanitized(defaults.string(forKey: DefaultsKey.superKeySource))
        return keyCode(of: source) == nil ? nil : source
    }

    static func keyCode(of source: SuperKeySource) -> UInt16? {
        switch source {
        case .rightCommand: return 54
        case .rightOption: return 61
        case .rightControl: return 62
        case .rightShift: return 60
        case .capsLock: return nil
        }
    }

    /// Whether a press of this key belongs to Super Key rather than VoiceOS.
    static func superKeyClaims(keyCode: UInt16) -> Bool {
        superKeySource.flatMap(keyCode(of:)) == keyCode
    }

    /// The note beside a VoiceOS key choice that Super Key has taken.
    static func note(for keyCodes: [UInt16]) -> String? {
        guard let source = superKeySource, let code = keyCode(of: source), keyCodes.contains(code) else { return nil }
        let name = FeatureStrings.superKey(L10n.shared.language).sourceLabel(source)
        return "Vorssaint's Super Key uses \(name), so Notchwise doesn't listen on it. Choose another key here, or another Super Key key in Settings → Super Key."
    }
}

extension VODictationTrigger {
    var keyCodes: [UInt16] {
        switch self {
        case .fn: return [63, 179]
        case .rightOption: return [61]
        case .rightControl: return [62]
        }
    }
}

extension VOAssistantTrigger {
    var keyCodes: [UInt16] {
        switch self {
        case .rightCommand: return [54]
        case .leftCommand: return [55]
        case .eitherCommand: return [54, 55]
        case .rightOption: return [61]
        }
    }
}
