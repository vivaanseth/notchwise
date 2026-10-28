// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import LilGuyFace
import SwiftUI

/// Lil Guy's states, in the face engine's order (`CharacterState`).
enum LilGuyState: UInt8 {
    case sleeping, waking, idle, listening, thinking, working, happy, curious, confused, surprised, playful
    case celebrate, success, error, cancelled

    /// Held until another is set; the others play once and return to it.
    var persists: Bool { [.sleeping, .idle, .listening, .thinking, .working].contains(self) }
}

/// What a touch gets back, as on the ESP32 character.
enum LilGuyGesture: UInt8 {
    case giggle, love, wink, dizzy
}

/// One Lil Guy: the face engine and the layer that shows it. It draws only
/// when the face changes; between blinks and glances it is still, and the
/// engine says when it next moves, so a face at rest costs nothing. Out of
/// sight it stops, and comes back where it was.
final class LilGuyFace {
    let layer = CALayer()
    private let face: OpaquePointer
    private let epoch = CACurrentMediaTime()
    private var pixels = [UInt32](repeating: 0, count: LilGuyFace.side * LilGuyFace.side)
    private var timer: Timer?
    private var delayed: [DispatchWorkItem] = []
    private static let side = 240
    /// The part of the round screen the eyes live in, which fills the
    /// layer's box: its centre and side, in the engine's 240-pixel space.
    static let crop = (center: CGPoint(x: 120, y: 128), side: CGFloat(176))

    /// Whether the face is on screen; out of sight nothing is drawn.
    var visible = false {
        didSet {
            guard visible != oldValue else { return }
            if visible { draw() } else { timer?.invalidate(); timer = nil }
            LilGuyDirector.shared.visibilityChanged()
        }
    }

    /// `sleeps`: the engine dozes off after a minute of rest by itself. A
    /// host that decides when it sleeps turns this off.
    init(sleeps: Bool = true) {
        // The engine allocates a few hundred kilobytes; failing that, there is no app to run.
        face = lg_face_create(1)!
        if !sleeps { lg_face_set_sleep_after(face, 0) }
        layer.contentsGravity = .resize
        layer.minificationFilter = .trilinear
        layer.magnificationFilter = .linear
        layer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull(), "frame": NSNull()]
        LilGuyDirector.shared.register(self)
    }

    deinit {
        timer?.invalidate()
        delayed.forEach { $0.cancel() }
        lg_face_destroy(face)
    }

    /// Lays the face out so its eyes fill `box`; what goes past the eyes,
    /// hearts or a sweat drop, reaches beyond it.
    func place(in box: CGRect, scale: CGFloat) {
        let k = box.width / Self.crop.side
        let full = CGFloat(Self.side) * k
        layer.frame = CGRect(x: box.midX - Self.crop.center.x * k, y: box.midY - Self.crop.center.y * k,
                             width: full, height: full)
        layer.contentsScale = scale
        // Under a flipped view the bitmap would draw upside down, turning
        // smiles into frowns; the layer turns it back.
        layer.setAffineTransform(layer.contentsAreFlipped() ? CGAffineTransform(scaleX: 1, y: -1) : .identity)
    }

    private var now: UInt32 { UInt32(max(0, CACurrentMediaTime() - epoch) * 1000) &+ 1 }

    // MARK: What it does

    func set(_ state: LilGuyState) {
        // His smile is two thin arcs, which vanish at the island's size;
        // these clips say the same in colour, a different one each time.
        switch state {
        case .success, .happy: play(LilGuyRepertoire.joy.randomElement()!); return
        case .celebrate: play(LilGuyRepertoire.love.randomElement()!); return
        case .error: play(LilGuyRepertoire.anger.randomElement()!); return
        case .cancelled: play(LilGuyRepertoire.sadness.randomElement()!); return
        case .surprised: play(LilGuyRepertoire.startle.randomElement()!); return
        case .playful: gesture(.wink); return
        default: break
        }
        if state.persists { lg_face_set_state(face, state.rawValue, now) } else { lg_face_react(face, state.rawValue, now) }
        moved()
    }

    func gesture(_ gesture: LilGuyGesture) {
        _ = lg_face_gesture(face, gesture.rawValue, now)
        moved()
    }

    func play(_ clip: LilGuyClip, mirrored: Bool = false) {
        _ = lg_face_play_clip(face, clip.rawValue, mirrored, now)
        moved()
    }

    /// Eyes toward `x`, `y` from −1 to 1, held `hold` seconds.
    func look(x: CGFloat, y: CGFloat, hold: TimeInterval = 1.2) {
        lg_face_look_at(face, Float(max(-1, min(1, x))), Float(max(-1, min(1, y))), UInt32(max(0, hold) * 1000), now)
        moved()
    }

    func lookAhead() { lg_face_look_center(face, now); moved() }
    func sleep() { lg_face_sleep(face, now); moved() }

    /// Up from sleep, with the engine's own waking; awake, it only notes the moment.
    func wake() {
        if asleep { lg_face_wake(face, now) } else { lg_face_activity(face, now) }
        moved()
    }

    var asleep: Bool { LilGuyState(rawValue: lg_face_state(face)) == .sleeping }

    /// In the middle of a clip, a reaction, a blink or a change of face.
    var isBusy: Bool {
        let time = now
        return Int32(bitPattern: lg_face_next_change(face, time) &- time) <= 33
    }

    /// Seeing a page of the open island.
    func enter(_ page: NotchModule) {
        if let clip = LilGuyRepertoire.page(page, hot: LilGuyDirector.shared.processorHot) { play(clip) }
    }

    /// Runs `action` at `time` on the media clock, or now if that has passed.
    func at(_ time: CFTimeInterval, _ action: @escaping () -> Void) {
        let delay = time - CACurrentMediaTime()
        guard delay > 0.01 else { action(); return }
        let work = DispatchWorkItem(block: action)
        delayed.append(work)
        delayed.removeAll { $0.isCancelled }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: The companion's language

    /// A mood the island's companion keeps, as Lil Guy shows it.
    func show(_ mood: NotchMascotMood) {
        switch mood {
        case .sleepy: sleep(); return
        default: if asleep { lg_face_wake(face, now) }
        }
        switch mood {
        case .idle: set(.idle)
        case .happy: set(.happy)
        case .wink: gesture(.wink)
        case .love: gesture(.love)
        case .determined: set(.working)
        case .surprised: set(.surprised)
        case .searching: set(.curious)
        case .thinking: set(.thinking)
        case .confused: set(.confused)
        case .alert: set(.listening)
        case .sleepy: break
        }
    }

    /// A moment the island saw, as Lil Guy answers it.
    func react(_ reaction: NotchMascotReaction) {
        if asleep, reaction != .wakeUp { lg_face_wake(face, now) }
        switch reaction {
        case .celebrate: set(.celebrate)
        case .love: play(LilGuyRepertoire.love.randomElement()!)
        case .surprised: set(.surprised)
        case .flash: play(.squintShut)
        case .confused: play(LilGuyRepertoire.dizzy.randomElement()!)
        case .wakeUp: wake(); play(LilGuyRepertoire.waking.randomElement()!)
        case .yawn: play(LilGuyRepertoire.yawn.randomElement()!)
        case .perk: play(LilGuyRepertoire.perk.randomElement()!)
        case .bounce: play(.boltPupilPulse)
        case .hush: play(.longClosedBlink)
        case .ready: play(.blinkIntoSmug)
        case .groove: play(LilGuyRepertoire.groove.randomElement()!)
        }
    }

    // MARK: Drawing

    private func moved() {
        guard visible else { return }
        schedule(after: 0)
    }

    private func schedule(after delay: TimeInterval) {
        timer?.invalidate()
        let timer = Timer(timeInterval: max(0.016, delay), repeats: false) { [weak self] _ in self?.draw() }
        timer.tolerance = min(0.05, max(0.004, delay * 0.1))
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func draw() {
        guard visible else { return }
        let time = now
        lg_face_update(face, time)
        pixels.withUnsafeMutableBufferPointer { lg_face_render(face, time, $0.baseAddress) }
        layer.contents = image()
        let next = lg_face_next_change(face, time)
        schedule(after: Double(Int32(bitPattern: next &- time)) / 1000)
    }

    private func image() -> CGImage? {
        let data = pixels.withUnsafeBytes { Data($0) } as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(width: Self.side, height: Self.side, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: Self.side * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

/// Lil Guy on his own, at `size` points, in a state: the assistant's face.
struct LilGuyView: NSViewRepresentable {
    var state: LilGuyState
    /// Replayed once each time it changes: a reaction over the state.
    var reaction: (state: LilGuyState, id: Int)? = nil
    /// The open island's page, which he reacts to on seeing it.
    var page: NotchModule? = nil
    var size: CGFloat

    func makeNSView(context: Context) -> LilGuyHostView { LilGuyHostView() }

    func updateNSView(_ view: LilGuyHostView, context: Context) {
        view.size = size
        view.show(state, reaction: reaction)
        view.see(page)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: LilGuyHostView, context: Context) -> CGSize? {
        CGSize(width: size, height: size)
    }
}

final class LilGuyHostView: NSView {
    private let lilGuy = LilGuyFace()
    private var shown: LilGuyState?
    private var reacted: Int?
    private var seen: NotchModule?
    var size: CGFloat = 20 { didSet { needsLayout = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.addSublayer(lilGuy.layer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    func show(_ state: LilGuyState, reaction: (state: LilGuyState, id: Int)?) {
        if state != shown {
            shown = state
            if state == .sleeping { lilGuy.sleep() } else { if lilGuy.asleep { lilGuy.wake() }; lilGuy.set(state) }
        }
        if let reaction, reaction.id != reacted {
            reacted = reaction.id
            lilGuy.set(reaction.state)
        }
    }

    func see(_ page: NotchModule?) {
        guard page != seen else { return }
        seen = page
        if let page { lilGuy.enter(page) }
    }

    // A click pokes him; four quick ones make him dizzy.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { LilGuyDirector.shared.poke(lilGuy) }

    override func layout() {
        super.layout()
        lilGuy.place(in: CGRect(x: (bounds.width - size) / 2, y: (bounds.height - size) / 2, width: size, height: size),
                     scale: window?.backingScaleFactor ?? 2)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self)
        if let window {
            NotificationCenter.default.addObserver(self, selector: #selector(syncVisibility),
                                                   name: NSWindow.didChangeOcclusionStateNotification, object: window)
        }
        needsLayout = true
        syncVisibility()
    }

    override func viewDidHide() { super.viewDidHide(); syncVisibility() }
    override func viewDidUnhide() { super.viewDidUnhide(); syncVisibility() }

    @objc private func syncVisibility() {
        lilGuy.visible = window?.isVisible == true && window?.occlusionState.contains(.visible) == true
            && !isHiddenOrHasHiddenAncestor
    }
}
