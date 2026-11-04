// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The island's one visual language, after Apple's own island and the
/// dark system: white type in three strengths on pure black, grey platters
/// with no outline, controls a step lighter. Colour belongs to things, not
/// surfaces: each page and control has one system colour, worn by its glyph
/// or its icon, and filling a control while it is on, as Settings and
/// Control Center do. Every page draws from here, so no two parts of the
/// island disagree. docs/ISLAND_DESIGN.md explains each choice.
enum NotchStyle {
    // MARK: Colour

    /// Text and glyphs, as the dark system's label colours.
    static let primary = Color.white
    static let secondary = Color.white.opacity(0.6)
    static let tertiary = Color.white.opacity(0.36)

    /// A card on the black: a group of related things.
    static let platter = Color.white.opacity(0.08)
    /// A button or tile at rest, on a platter or on the black.
    static let control = Color.white.opacity(0.12)
    /// The wash under the pointer.
    static let hover = Color.white.opacity(0.08)
    /// The current page, or the choice in force.
    static let selected = Color.white.opacity(0.18)
    /// A thin line between rows, and a meter's empty part.
    static let separator = Color.white.opacity(0.12)
    static let track = Color.white.opacity(0.14)
    /// The outline Increase Contrast asks for, where there is none otherwise.
    static let contrastOutline = Color.white.opacity(0.45)

    /// The system's own colours, which the island's dark appearance draws
    /// in their dark variants. One belongs to each page and control; the
    /// rest mark what is live or needs notice. None ever fills a surface.
    enum Tint {
        static let blue = Color.blue
        static let green = Color.green
        static let orange = Color.orange
        static let red = Color.red
        static let yellow = Color.yellow
        static let pink = Color.pink
        static let teal = Color.teal
        static let cyan = Color.cyan
        static let mint = Color.mint
        static let indigo = Color.indigo
        static let purple = Color.purple
        static let gray = Color.gray
    }

    // MARK: Shape

    /// Corners step down from the island inward, so each sits inside the
    /// one around it at an even margin: the island, its cards, the tiles in
    /// them, then capsules for anything a click starts.
    enum Radius {
        static let card: CGFloat = 18
        static let tile: CGFloat = 12
        static let button: CGFloat = 9
        static let small: CGFloat = 6
    }

    /// The gap between cards, and between tiles in a card.
    static let gutter: CGFloat = 10
    static let tileGap: CGFloat = 6

    // MARK: Type

    /// Medium weight and up, as the island's small sizes need; nothing below
    /// eleven points where a page has the room.
    enum Typeface {
        /// A figure the page is about: a percentage, a date, a clock.
        static let display = Font.system(size: 28, weight: .semibold, design: .rounded)
        static let title = Font.system(size: 15, weight: .semibold)
        static let headline = Font.system(size: 13, weight: .semibold)
        static let body = Font.system(size: 13)
        static let callout = Font.system(size: 12, weight: .medium)
        static let caption = Font.system(size: 11, weight: .medium)
        /// A section's name above its rows.
        static let label = Font.system(size: 11, weight: .semibold)
        /// A glyph on a tile, and one in the top row.
        static let tileGlyph = Font.system(size: 15, weight: .semibold)
        static let rowGlyph = Font.system(size: 12, weight: .medium)
    }

    // MARK: Motion

    /// Springs, short and without a swing for anything done often, and every
    /// one interruptible: what replaces a motion starts from where it is.
    enum Motion {
        /// The wash under the pointer, and other highlights.
        static let hover = Animation.smooth(duration: 0.2)
        /// A control giving under a click and springing back.
        static let press = Animation.snappy(duration: 0.22, extraBounce: 0.06)
        /// A state turning over: on or off, a symbol, a figure, a fade.
        static let state = Animation.smooth(duration: 0.3)
        /// Something moving or unfolding to a new place.
        static let layout = Animation.snappy(duration: 0.35)
        /// A reading following a key or a slider, which must keep up.
        static let follow = Animation.smooth(duration: 0.15)
        /// Scrolling to an item.
        static let scroll = Animation.smooth(duration: 0.3)
        /// New content settling in as a page changes.
        static let arrive = Animation.smooth(duration: 0.34)
    }
}

extension View {
    /// A card on the island's black: the platter fill and the island's
    /// continuous corners, outlined only when Increase Contrast is on.
    func notchPlatter(cornerRadius: CGFloat = NotchStyle.Radius.card) -> some View {
        modifier(NotchPlatter(cornerRadius: cornerRadius))
    }

    /// New content settles in when `key` changes: it comes up from a soft
    /// blur as the island's shape springs to its size, as Apple's island
    /// swaps what it shows. The first appearance shows at once, so the
    /// island opening is the shape's motion alone.
    func notchArrival<Key: Hashable>(on key: Key) -> some View {
        modifier(NotchArrival(key: key))
    }
}

struct NotchPlatter: ViewModifier {
    var cornerRadius: CGFloat
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(NotchStyle.platter, in: shape)
            .overlay {
                if contrast == .increased {
                    shape.strokeBorder(NotchStyle.contrastOutline, lineWidth: 0.75).allowsHitTesting(false)
                }
            }
            .clipShape(shape)
    }
}

struct NotchArrival<Key: Hashable>: ViewModifier {
    let key: Key
    @State private var settled: Key
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(key: Key) {
        self.key = key
        _settled = State(initialValue: key)
    }

    func body(content: Content) -> some View {
        // Drawn hidden from the frame the key changes in, so the new content
        // never flashes whole before it settles.
        let arriving = key != settled
        content
            .opacity(arriving ? 0 : 1)
            .blur(radius: arriving && !reduceMotion ? 4 : 0)
            .scaleEffect(arriving && !reduceMotion ? 0.985 : 1, anchor: .top)
            .onChange(of: key) { _, key in
                withAnimation(reduceMotion ? .linear(duration: 0.12) : NotchStyle.Motion.arrive) { settled = key }
            }
    }
}

/// A word on a capsule, for a step a page offers. The step it leads to is
/// filled white with black type, as the system's prominent buttons are on
/// the island; any other sits on the control fill beside it.
struct NotchCapsuleButtonStyle: ButtonStyle {
    var prominent = false
    var height: CGFloat = 28
    @State private var hovered = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(NotchStyle.Typeface.callout.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(prominent ? Color.black : NotchStyle.primary)
            .padding(.horizontal, 14)
            .frame(minHeight: height)
            .background(prominent ? AnyShapeStyle(Color.white) : AnyShapeStyle(NotchStyle.control), in: Capsule())
            .overlay {
                Capsule().fill(Color.white.opacity(hovered && enabled ? (prominent ? 0 : 0.06) : 0))
                    .allowsHitTesting(false)
            }
            .brightness(prominent && hovered && enabled ? -0.06 : 0)
            .contentShape(Capsule())
            .opacity(enabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : NotchStyle.Motion.press, value: configuration.isPressed)
            .animation(reduceMotion ? nil : NotchStyle.Motion.hover, value: hovered)
            .onHover { hovered = $0 }
    }
}

/// A white glyph on a rounded square of its colour, as Settings draws each
/// of its panes and the Dock its apps: the one place a page's colour fills
/// a shape. A light falls from the top, as on the system's own icons.
struct NotchIconChip: View {
    let symbol: String
    let tint: Color
    /// White, or dark on a light colour such as yellow, as Settings draws it.
    var glyph: Color = .white
    var size: CGFloat = 30

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(glyph)
            .frame(width: size, height: size)
            .background {
                shape.fill(tint)
                    .overlay(shape.fill(LinearGradient(colors: [.white.opacity(0.22), .clear],
                                                       startPoint: .top, endPoint: .bottom)))
            }
            .accessibilityHidden(true)
    }
}

private struct NotchTileTintKey: EnvironmentKey {
    static let defaultValue: Color? = nil
}

extension EnvironmentValues {
    /// The colour a shortcut tile's glyph wears at rest, set by the rail
    /// that knows which control the tile is.
    var notchTileTint: Color? {
        get { self[NotchTileTintKey.self] }
        set { self[NotchTileTintKey.self] = newValue }
    }
}
