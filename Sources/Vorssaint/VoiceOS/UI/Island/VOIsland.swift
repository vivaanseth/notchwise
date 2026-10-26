// SPDX-License-Identifier: GPL-3.0-or-later
// Replaces VoiceOS Clone's NotchWindowController inside Vorssaint + VoiceOS.

import AppKit
import Combine

/// What the closed island shows of the assistant while it works.
enum VOIslandActivity: Equatable {
    case listening, thinking, confirming, speaking

    var reading: String {
        switch self {
        case .listening: return "Listening…"
        case .thinking: return "Thinking…"
        case .confirming: return "Confirm"
        case .speaking: return "Speaking"
        }
    }
}

/// The assistant's view of the island it lives in. VoiceOS used to own a
/// notch window; the combined app has one island, Vorssaint's, and these
/// calls map the assistant's needs onto it.
@MainActor
enum VOIsland {
    /// The island's panel, for the snapshot tool.
    static var window: NSWindow? { NotchService.shared.presentationWindow }

    /// Whether the island holds the keyboard for the assistant's text field.
    static var isTyping: Bool { NotchService.shared.voiceHoldsKeyboard }

    /// The pointer rests on the open island.
    static var pointerInside: Bool { NotchService.shared.pointerInsideIsland }

    /// Shows the assistant's page, taking the keyboard for typing when
    /// `focus` is set. It takes the island over from any other page.
    static func present(focus: Bool) { NotchService.shared.presentVoice(takeFocus: focus) }

    /// Closes the island when it shows the assistant and nothing keeps it.
    static func dismiss() { NotchService.shared.dismissVoice() }

    /// Lets the island take the keyboard so the assistant's field can be typed in.
    static func focusInput() { NotchService.shared.focusVoiceInput() }

    /// Hands the keyboard back to the app the user was in, which is needed
    /// before typing or pasting into it.
    static func releaseKeyFocus(reactivate pid: pid_t? = nil) {
        guard NotchService.shared.releaseVoiceKeyboard() else { return }
        if let pid, let app = NSRunningApplication(processIdentifier: pid) { app.activate() }
    }
}

/// The island's side of the bridge. Vorssaint's island runs on the main
/// thread without actor annotations, so these calls hop onto the main actor
/// the assistant is isolated to.
enum VOIslandBridge {
    /// The assistant is installed, so the island offers it.
    static var isAvailable: Bool { AppFeature.voiceAssistant.isAvailable }

    /// The island just showed the assistant's page, or left it.
    static func voicePageOpened(focus: Bool) {
        MainActor.assumeIsolated { VOAssistantController.shared.islandDidOpen(focus: focus) }
    }

    static func voicePageClosed() {
        MainActor.assumeIsolated { VOAssistantController.shared.islandDidClose() }
    }

    /// Listening, transcribing, thinking or waiting on a confirmation: the
    /// island keeps the assistant through a click away, a pointer leaving and
    /// another app coming forward, as VoiceOS's notch did.
    static var holdsIsland: Bool {
        MainActor.assumeIsolated { VOAssistantController.shared.holdsIsland }
    }

    /// What the closed island shows while the assistant works, if anything.
    static var activity: VOIslandActivity? {
        guard isAvailable else { return nil }
        return MainActor.assumeIsolated { VOAssistantController.shared.islandActivity }
    }

    /// Calls `refresh` whenever the assistant's island state may have changed.
    static func observe(_ refresh: @escaping () -> Void) -> AnyCancellable {
        var token: AnyCancellable?
        MainActor.assumeIsolated {
            let assistant = VOAssistantController.shared
            let changes: [AnyPublisher<Void, Never>] = [
                assistant.$phase.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
                assistant.$turns.map { _ in () }.eraseToAnyPublisher(),
                assistant.$expanded.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
                VOAssistantVoice.shared.$speaking.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            ]
            token = Publishers.MergeMany(changes)
                .debounce(for: .milliseconds(30), scheduler: RunLoop.main)
                .sink { refresh() }
        }
        return token ?? AnyCancellable {}
    }
}
