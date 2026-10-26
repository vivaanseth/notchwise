// SPDX-License-Identifier: GPL-3.0-or-later
// Ported from VoiceOS Clone (UI/Main/MainWindow.swift) into Vorssaint + VoiceOS.

/// The VoiceOS settings pages, each a row of the VoiceOS section in
/// Vorssaint's Settings. Kept apart from their views so Vorssaint's settings
/// router, and its tests, can name them.
enum VOPage: String, CaseIterable, Identifiable {
    case dashboard, insights, history, dictation, assistant, apps
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .dashboard: return "house"
        case .insights: return "chart.bar"
        case .history: return "clock.arrow.circlepath"
        case .dictation: return "mic"
        case .assistant: return "sparkles"
        case .apps: return "square.grid.2x2"
        }
    }
}
