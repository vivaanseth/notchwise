// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Lil Guy's room: a click on his face in the open island's top row brings
/// him out big, over the page, to be played with. Escape, the way back, or
/// leaving the page puts him back.
final class LilGuyRoom: ObservableObject {
    static let shared = LilGuyRoom()

    @Published private(set) var isOpen = false
    @Published private(set) var asleep = false
    /// The big face, once it is on screen.
    weak var face: LilGuyFace? {
        didSet { asleep = face?.asleep ?? false }
    }
    private var escape: Any?

    private init() {}

    func open() {
        guard !isOpen else { return }
        isOpen = true
        // The island's own Escape would close it; in the room it only leaves the room.
        escape = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53, self?.isOpen == true else { return event }
            self?.close()
            return nil
        }
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        if let escape { NSEvent.removeMonitor(escape) }
        escape = nil
    }

    // MARK: Playing

    func pet() { face?.play(LilGuyRepertoire.love.randomElement()!) }
    func tickle() { face?.gesture(.giggle) }
    func wink() { face?.gesture(.wink) }
    func spin() { face?.play(LilGuyRepertoire.dizzy.randomElement()!) }

    func napOrWake() {
        guard let face else { return }
        if face.asleep {
            face.wake()
            face.play(LilGuyRepertoire.waking.randomElement()!)
        } else {
            face.sleep()
        }
        asleep = face.asleep
    }

    /// Any of his clips that plays on its own: a hold or an exit needs another before it.
    func surprise() {
        let alone = LilGuyClip.allCases.filter { ![.ovalHold, .paletteClosure, .flowerHold, .softExit].contains($0) }
        if face?.asleep == true { napOrWake() }
        face?.play(alone.randomElement()!, mirrored: Bool.random())
    }
}

/// The room itself: Lil Guy as big as the page allows, a soft light behind
/// him that breathes, and a row of things to do with him.
struct LilGuyRoomView: View {
    @ObservedObject var service: NotchService
    let size: CGSize
    @ObservedObject private var room = LilGuyRoom.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false
    private var text: NotchHubStrings { FeatureStrings.notchHub(l10n.language) }

    /// On the assistant's page the island takes its height from what it
    /// shows; elsewhere the room fills the page it covers.
    static let assistantHeight: CGFloat = 330

    private struct Action: Identifiable {
        let id: String
        let symbol: String
        let title: String
        let run: () -> Void
    }

    private var actions: [Action] {
        [Action(id: "pet", symbol: "heart.fill", title: text.pet, run: room.pet),
         Action(id: "tickle", symbol: "hand.point.up.left.fill", title: text.tickle, run: room.tickle),
         Action(id: "wink", symbol: "eye", title: text.wink, run: room.wink),
         Action(id: "spin", symbol: "tornado", title: text.spin, run: room.spin),
         Action(id: "nap", symbol: room.asleep ? "sun.max.fill" : "moon.zzz.fill",
                title: room.asleep ? text.wakeUp : text.nap, run: room.napOrWake),
         Action(id: "surprise", symbol: "sparkles", title: text.surprise, run: room.surprise)]
    }

    var body: some View {
        let height = service.selected == .voice ? Self.assistantHeight : size.height
        let rail = NotchLayout.shortcutHeight
        // Tall enough, he stands over a row of things to do; in a short
        // island they sit beside him, three by two, and he stays big.
        let stacked = height - rail - 58 >= 120
        let face = stacked ? min(176, height - rail - 58) : max(64, min(176, height - 20, size.width - 3 * 84 - 40))
        Group {
            if stacked {
                VStack(spacing: 8) {
                    lilGuy(face)
                    hint
                    NotchRail(items: actions, rows: 1, itemWidth: NotchLayout.shortcutWidth, width: size.width,
                              spacing: NotchLayout.shortcutSpacing, leastSpacing: NotchLayout.shortcutLeastSpacing) { tile($0) }
                        .frame(height: rail)
                }
                .padding(.top, 6)
            } else {
                HStack(spacing: 16) {
                    lilGuy(face)
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(NotchLayout.shortcutWidth), spacing: 4), count: 3),
                              spacing: 4) {
                        ForEach(actions) { tile($0) }
                    }
                    .fixedSize()
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(width: size.width, height: height, alignment: .top)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
            if service.selected == .voice { service.updateVoiceHeight($0) }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { breathing = true }
        }
        .notchBand(leading: {
            NotchBandBackButton(title: "Lil Guy", action: room.close)
        })
        .transition(.opacity)
    }

    private func lilGuy(_ face: CGFloat) -> some View {
        ZStack {
            RadialGradient(colors: [.white.opacity(room.asleep ? 0.05 : 0.11), .clear],
                           center: .center, startRadius: 0, endRadius: face * 0.95)
                .frame(width: face * 2, height: face * 1.5)
                .scaleEffect(breathing ? 1.06 : 0.94)
                .allowsHitTesting(false)
            // Handed over as SwiftUI makes it; the room publishes on the next turn.
            LilGuyView(state: .idle, size: face) { made in DispatchQueue.main.async { room.face = made } }
                .frame(width: face, height: face)
                .help(text.roomHint)
                .accessibilityLabel("Lil Guy")
                .accessibilityAction(named: text.tickle, room.tickle)
                .accessibilityAction(named: text.pet, room.pet)
        }
        .frame(width: face * 1.3, height: face + 14)
    }

    private var hint: some View {
        Text(text.roomHint)
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.45))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private func tile(_ action: Action) -> some View {
        NotchActionTile(symbol: action.symbol, title: action.title, active: action.id == "nap" && room.asleep,
                        action: action.run)
    }
}
