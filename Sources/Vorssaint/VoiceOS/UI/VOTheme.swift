// SPDX-License-Identifier: GPL-3.0-or-later
// Ported from VoiceOS Clone (UI/Theme.swift) into Vorssaint + VoiceOS.

import SwiftUI

enum VOTheme {
    static let content = Color(hex: 0x1A1A1C)
    static let card = Color(hex: 0x232326)
    static let cardRaised = Color(hex: 0x2A2A2E)
    static let border = Color.white.opacity(0.07)
    static let borderStrong = Color.white.opacity(0.12)
    static let field = Color(hex: 0x2B2B2F)
    static let text = Color.white
    static let secondary = Color(hex: 0x9B9BA1)
    static let tertiary = Color(hex: 0x6C6C73)
    static let accent = Color(hex: 0x4F7BFF)
    static let accentDeep = Color(hex: 0x3461F0)
    static let green = Color(hex: 0x34C759)
    static let orange = Color(hex: 0xFF9F0A)
    static let red = Color(hex: 0xFF453A)

    static let sky = LinearGradient(colors: [Color(hex: 0x9CCBFF), Color(hex: 0x4A90E2), Color(hex: 0x1F5FBF)],
                                    startPoint: .top, endPoint: .bottom)
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

extension VOProviderStatus {
    var color: Color {
        switch self {
        case .ready: return VOTheme.green
        case .signedOut, .failed: return VOTheme.orange
        case .notInstalled: return VOTheme.red
        case .checking, .unknown: return VOTheme.tertiary
        }
    }
}
