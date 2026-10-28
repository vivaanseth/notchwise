// SPDX-License-Identifier: GPL-3.0-or-later
// VoiceOS's closed-notch states, drawn in Vorssaint's island.

import SwiftUI

extension NotchCapsuleLayout {
    /// The assistant at work in a capsule: its mark, then what it is doing.
    static func voiceSurface(reading: String, geometry: NotchGeometry) -> CGSize {
        surface(content: symbolWidth + spacing + width(reading, font: titleFont),
                maximum: Maximum.activity, geometry: geometry)
    }
}

/// The closed island while the assistant works and its page is not open:
/// the Jarvis mark on one side and, on the other, the level as it listens,
/// the dots as it thinks, the wave as it speaks, or a mark that something
/// waits to be confirmed. A click opens the assistant's page.
struct VOVoiceStrip: View {
    @ObservedObject var service: NotchService
    /// A capsule's size; nil hangs the strip around the camera.
    var capsuleSize: CGSize? = nil
    /// Another display's strip, when the island shows on every display.
    var displayGeometry: NotchGeometry? = nil
    @ObservedObject private var agent = VOAssistantController.shared
    @ObservedObject private var voice = VOAssistantVoice.shared

    private var activity: VOIslandActivity {
        agent.islandActivity ?? .thinking
    }

    var body: some View {
        Button { service.openActivity(.voice) } label: {
            if let capsuleSize { capsule(capsuleSize) } else { hanging }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(FeatureStrings.voiceAssistant(L10n.shared.language).pageTitle)
        .accessibilityValue(activity.reading)
        .accessibilityIdentifier("notch.voice")
    }

    private var hanging: some View {
        let geometry = displayGeometry ?? service.compactActivityGeometry
        let height = geometry.compactActivityContentHeight
        let wing = geometry.compactActivityWingWidth
        let mark = min(15, max(10, height - 10))
        return HStack(spacing: 0) {
            Group {
                // Lil Guy, the assistant's face, shows what it is doing.
                if wing >= 24 { LilGuyView(state: activity.lilGuy, size: mark + 4).frame(width: mark + 4, height: mark + 4) }
            }
            .padding(.leading, geometry.compactActivityEdgeInset(boxHeight: mark, radius: mark / 2))
            .frame(width: wing, height: height, alignment: .leading)
            Color.clear.frame(width: geometry.compactActivityCameraGap)
            Group {
                if wing >= 28 { state(height: min(12, height - 8)) }
            }
            .padding(.trailing, geometry.compactActivityEdgeInset(boxHeight: min(12, height - 8), radius: 0))
            .frame(width: wing, height: height, alignment: .trailing)
        }
        .frame(height: height)
        .padding(.horizontal, geometry.compactActivityHorizontalPadding)
        .padding(.top, geometry.compactActivityTopPadding)
        .contentShape(Rectangle())
    }

    private func capsule(_ size: CGSize) -> some View {
        let geometry = displayGeometry ?? service.geometry
        let side = NotchCapsuleLayout.side(geometry)
        return HStack(spacing: NotchCapsuleLayout.spacing) {
            LilGuyView(state: activity.lilGuy, size: NotchCapsuleLayout.symbolSize + 5)
                .frame(width: NotchCapsuleLayout.symbolWidth, height: NotchCapsuleLayout.symbolSize + 5)
            Text(activity.reading)
                .font(Font(NotchCapsuleLayout.titleFont as CTFont))
                .lineLimit(1).fixedSize()
        }
        .padding(.leading, side + NotchCapsuleLayout.endPadding)
        .padding(.trailing, side + NotchCapsuleLayout.endPadding)
        .frame(width: size.width, height: geometry.stripHeight)
        .foregroundStyle(.white)
        .contentShape(Rectangle())
    }

    @ViewBuilder private func state(height: CGFloat) -> some View {
        switch activity {
        case .listening: VOWaveform(level: agent.level, bars: 5, height: height, barWidth: 2)
        case .thinking: VOThinkingDots().scaleEffect(0.8)
        case .speaking: VOWaveform(level: 0.55, bars: 5, height: height, barWidth: 2)
        case .confirming:
            Image(systemName: "exclamationmark.bubble.fill")
                .font(.system(size: height, weight: .semibold))
                .foregroundStyle(VOTheme.accent)
        }
    }
}

extension VOIslandActivity {
    /// Lil Guy's face for what the assistant is doing.
    var lilGuy: LilGuyState {
        switch self {
        case .listening: return .listening
        case .thinking: return .thinking
        case .speaking: return .idle
        case .confirming: return .curious
        }
    }
}

/// What the idle island grows to show under the pointer, as VoiceOS's idle
/// notch did: Lil Guy perking up, "Ask VoiceOS" and a quiet wave. A click
/// opens the assistant ready for typing.
struct VOAskHoverContent: View {
    let geometry: NotchGeometry
    let size: CGSize

    var body: some View {
        HStack(spacing: 6) {
            LilGuyView(state: .curious, size: 16).frame(width: 16, height: 16)
            Spacer(minLength: 4)
            Text("Ask VoiceOS").font(.system(size: 10.5, weight: .medium)).foregroundColor(.white.opacity(0.6))
                .lineLimit(1).fixedSize()
            Spacer(minLength: 4)
            VOWaveform(level: 0.2, bars: 4, height: 9, barWidth: 2)
        }
        .padding(.horizontal, NotchLayout.shoulder(height: geometry.stripHeight) + 8)
        .frame(width: size.width, height: geometry.stripHeight)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .transition(.opacity)
    }
}
