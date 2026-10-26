// SPDX-License-Identifier: GPL-3.0-or-later
// Ported from VoiceOS Clone (UI/Brand.swift) into Vorssaint + VoiceOS.

import SwiftUI

struct VODownTriangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let radius = r.width * 0.08
        p.move(to: CGPoint(x: r.minX + radius, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - radius, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - radius * 0.4, y: r.minY + radius * 1.1), control: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.midX + radius * 0.6, y: r.maxY - radius * 0.6))
        p.addQuadCurve(to: CGPoint(x: r.midX - radius * 0.6, y: r.maxY - radius * 0.6), control: CGPoint(x: r.midX, y: r.maxY + radius * 0.2))
        p.addLine(to: CGPoint(x: r.minX + radius * 0.4, y: r.minY + radius * 1.1))
        p.addQuadCurve(to: CGPoint(x: r.minX + radius, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
        p.closeSubpath()
        return p
    }
}

/// "▼oice●s" — the wordmark, drawn rather than shipped as an image.
struct VoiceOSWordmark: View {
    var height: CGFloat = 28
    var color: Color = .white

    var body: some View {
        let x = height * 0.56 // x-height of the heavy system face
        HStack(alignment: .lastTextBaseline, spacing: height * 0.015) {
            VODownTriangle().fill(color)
                .frame(width: x * 1.12, height: x * 0.98)
                .alignmentGuide(.lastTextBaseline) { d in d[.bottom] }
            Text("oice").font(.system(size: height, weight: .heavy)).kerning(-height * 0.02)
            Circle().fill(color)
                .frame(width: x * 1.02, height: x * 1.02)
                .alignmentGuide(.lastTextBaseline) { d in d[.bottom] - height * 0.012 }
            Text("s").font(.system(size: height, weight: .heavy))
        }
        .foregroundColor(color)
        .fixedSize()
    }
}

/// The "VO" mark: a down-triangle and a circle.
struct VOMark: View {
    var size: CGFloat = 20
    var color: Color = .white
    var body: some View {
        HStack(spacing: size * 0.1) {
            VODownTriangle().fill(color).frame(width: size * 0.92, height: size * 0.8)
            Circle().fill(color).frame(width: size * 0.86, height: size * 0.86)
        }
    }
}

struct VOProBadge: View {
    var body: some View {
        Text("PRO")
            .font(.system(size: 9.5, weight: .bold))
            .kerning(0.6)
            .foregroundColor(VOTheme.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.white.opacity(0.08)))
            .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
    }
}

/// The glass orb with sky and clouds inside.
struct VOOrb: View {
    var size: CGFloat = 40
    var level: CGFloat = 0
    @State private var drift = false

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Color(hex: 0xBFE0FF), Color(hex: 0x5AA2F0), Color(hex: 0x2C6FD6)],
                                         startPoint: .top, endPoint: .bottom))
            // clouds
            Group {
                Ellipse().fill(Color.white.opacity(0.95)).frame(width: size * 0.55, height: size * 0.26).offset(x: drift ? -size * 0.08 : -size * 0.14, y: size * 0.12)
                Ellipse().fill(Color.white.opacity(0.9)).frame(width: size * 0.36, height: size * 0.24).offset(x: drift ? size * 0.16 : size * 0.1, y: size * 0.04)
                Ellipse().fill(Color.white.opacity(0.75)).frame(width: size * 0.42, height: size * 0.18).offset(x: size * 0.18, y: size * 0.26)
                Ellipse().fill(Color.white.opacity(0.55)).frame(width: size * 0.3, height: size * 0.12).offset(x: -size * 0.22, y: -size * 0.2)
            }
            .blur(radius: size * 0.035)
            // glass highlight + rim
            Circle().fill(RadialGradient(colors: [Color.white.opacity(0.85), Color.white.opacity(0)], center: .init(x: 0.32, y: 0.22),
                                         startRadius: 0, endRadius: size * 0.42))
                .blendMode(.screen)
            Circle().stroke(LinearGradient(colors: [Color.white.opacity(0.9), Color.white.opacity(0.15), Color.white.opacity(0.6)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: max(1, size * 0.03))
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .scaleEffect(1 + level * 0.12)
        .shadow(color: Color(hex: 0x4A90E2).opacity(0.45), radius: size * 0.18, y: size * 0.06)
        .onAppear { withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) { drift = true } }
    }
}

/// The "Jarvis" voice glyph: a ring of dots around a hollow core.
struct VOJarvisGlyph: View {
    var size: CGFloat = 22
    var active = false
    var color: Color = .white
    @State private var spin = false

    var body: some View {
        ZStack {
            ForEach(0..<12, id: \.self) { i in
                Circle().fill(color)
                    .frame(width: size * 0.13, height: size * 0.13)
                    .offset(y: -size * 0.42)
                    .rotationEffect(.degrees(Double(i) * 30))
                    .opacity(active ? (i % 2 == 0 ? 1 : 0.55) : 0.9)
            }
            Circle().stroke(color, lineWidth: size * 0.09).frame(width: size * 0.5, height: size * 0.5)
            Circle().fill(color.opacity(0.9)).frame(width: size * 0.18, height: size * 0.18)
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(spin ? 360 : 0))
        .shadow(color: color.opacity(active ? 0.7 : 0.3), radius: active ? size * 0.25 : size * 0.1)
        .onChange(of: active) { _, on in updateSpin(on) }
        .onAppear { updateSpin(active) }
    }

    private func updateSpin(_ on: Bool) {
        if on {
            withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) { spin = true }
        } else {
            withAnimation(.easeOut(duration: 0.4)) { spin = false }
        }
    }
}

/// Simple vector stand-ins for each AI's logo.
struct VOProviderLogo: View {
    let provider: VOProviderID
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous).fill(background)
            switch provider {
            case .ollama:
                Image(systemName: "cpu")
                    .font(.system(size: size * 0.5, weight: .medium))
                    .foregroundStyle(LinearGradient(colors: [.white, Color(hex: 0xBFD7FF)], startPoint: .top, endPoint: .bottom))
            case .claude:
                ZStack {
                    ForEach(0..<10, id: \.self) { i in
                        Capsule().fill(Color.white)
                            .frame(width: size * 0.09, height: size * (i % 2 == 0 ? 0.62 : 0.5))
                            .rotationEffect(.degrees(Double(i) * 18))
                    }
                }
            case .chatgpt:
                ZStack {
                    ForEach(0..<6, id: \.self) { i in
                        RoundedRectangle(cornerRadius: size * 0.1, style: .continuous)
                            .stroke(Color.white, lineWidth: size * 0.065)
                            .frame(width: size * 0.22, height: size * 0.46)
                            .offset(y: -size * 0.1)
                            .rotationEffect(.degrees(Double(i) * 60))
                    }
                }
            case .gemini:
                VOGeminiStar()
                    .fill(LinearGradient(colors: [Color(hex: 0x4285F4), Color(hex: 0x9B72CB), Color(hex: 0xD96570)],
                                         startPoint: .bottomLeading, endPoint: .topTrailing))
                    .frame(width: size * 0.62, height: size * 0.62)
            }
        }
        .frame(width: size, height: size)
    }

    private var background: Color {
        switch provider {
        case .ollama: return Color(hex: 0x2B3550)
        case .claude: return Color(hex: 0xD97757)
        case .chatgpt: return Color(hex: 0x0F0F10)
        case .gemini: return Color(hex: 0xF4F6FB)
        }
    }
}

struct VOGeminiStar: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY)
        p.move(to: CGPoint(x: c.x, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: c.y), control: c)
        p.addQuadCurve(to: CGPoint(x: c.x, y: r.maxY), control: c)
        p.addQuadCurve(to: CGPoint(x: r.minX, y: c.y), control: c)
        p.addQuadCurve(to: CGPoint(x: c.x, y: r.minY), control: c)
        p.closeSubpath()
        return p
    }
}

/// Live audio bars used in the pill and the notch.
struct VOWaveform: View {
    var level: Float
    var bars = 7
    var color: Color = .white
    var height: CGFloat = 18
    var barWidth: CGFloat = 3.2

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: barWidth * 0.8) {
                ForEach(0..<bars, id: \.self) { i in
                    let wobble = (sin(t * 9 + Double(i) * 1.3) + 1) / 2
                    let center = 1 - abs(Double(i) - Double(bars - 1) / 2) / Double(bars)
                    let amp = 0.18 + Double(level) * (0.45 + 0.55 * wobble) * (0.6 + 0.4 * center)
                    Capsule().fill(color)
                        .frame(width: barWidth, height: max(barWidth, height * CGFloat(min(1, amp))))
                }
            }
            .frame(height: height)
        }
    }
}

/// Three dots that breathe while VoiceOS is thinking.
struct VOThinkingDots: View {
    var color: Color = .white
    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle().fill(color)
                        .frame(width: 5, height: 5)
                        .opacity(0.35 + 0.65 * (sin(t * 5 - Double(i) * 0.8) + 1) / 2)
                }
            }
        }
    }
}

/// Text with a light sweeping across it.
struct VOShimmerText: View {
    let text: String
    var size: CGFloat = 15
    var body: some View {
        TimelineView(.animation) { tl in
            let phase = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
            Text(text)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(
                    LinearGradient(stops: [.init(color: .white.opacity(0.35), location: 0),
                                           .init(color: .white.opacity(0.95), location: max(0, min(1, phase))),
                                           .init(color: .white.opacity(0.35), location: 1)],
                                   startPoint: .leading, endPoint: .trailing))
        }
    }
}
