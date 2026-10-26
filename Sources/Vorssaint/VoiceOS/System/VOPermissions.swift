// SPDX-License-Identifier: GPL-3.0-or-later
// Ported from VoiceOS Clone (System/Permissions.swift) into Vorssaint + VoiceOS.

import AVFoundation
import Speech
import AppKit

@MainActor
final class VOPermissions: ObservableObject {
    static let shared = VOPermissions()

    @Published var microphone = false
    @Published var speech = false
    @Published var accessibility = false
    @Published var screen = false

    private var timer: Timer?

    private init() { refresh() }

    var essentialsGranted: Bool { microphone && accessibility && (speech || VOSettings.shared.speechEngine == .whisper) }

    func refresh() {
        microphone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        speech = SFSpeechRecognizer.authorizationStatus() == .authorized
        let ax = VOAccessibility.isTrusted
        if ax && !accessibility { NotificationCenter.default.post(name: .voAccessibilityGranted, object: nil) }
        accessibility = ax
        screen = VOScreenGrab.hasPermission
    }

    /// Quick while a grant VoiceOS needs is missing, so it reacts the moment
    /// one is given; slow once they all are, sharing the app with Vorssaint's
    /// own permission checks.
    func startPolling() {
        timer?.invalidate()
        let interval: TimeInterval = essentialsGranted ? 15 : 1.5
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task { @MainActor in
                let p = VOPermissions.shared
                let before = p.essentialsGranted
                p.refresh()
                if p.essentialsGranted != before { p.startPolling() }
            }
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func requestMicrophone() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { _ in Task { @MainActor in self.refresh() } }
        default:
            VOSystemSettings.open("Privacy_Microphone")
        }
    }

    func requestSpeech() {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { _ in Task { @MainActor in self.refresh() } }
        default:
            VOSystemSettings.open("Privacy_SpeechRecognition")
        }
    }

    func requestAccessibility() {
        VOAccessibility.prompt()
        VOSystemSettings.open("Privacy_Accessibility")
    }

    func requestScreen() {
        VOScreenGrab.request()
        VOSystemSettings.open("Privacy_ScreenCapture")
    }
}

extension Notification.Name {
    static let voAccessibilityGranted = Notification.Name("voiceos.accessibilityGranted")
}
