// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Every measured clip in Lil Guy's engine, by its id there.
enum LilGuyClip: UInt8, CaseIterable {
    case ovalHold, attentionShift, downLeftTurn, paletteClosure, flowerEnter, flowerHold, dotRise, heartPulse
    case heartContinuation, blinkRecovery, gazeHold, wink, postWinkSettle, attentionRetreat, retreatGesture, softExit
    case heartStreamFlatten, boltPupilPulse, smileStreakBlink, dizzyPupilOrbit, squashCloseRise, angryGlare
    case colorSwapBlink, warmUpColorShift, longClosedBlink, wakeUpPupilDrop, slowBlinkPupilDrop, quickBlinkPupilDrop
    case startleNervousDrift, grumpyReopen, squintShut, orangeToWhiteWake, tiltedPairBlink, happyArcPeekWake
    case heartEyesFloatAway, sadDroopWake, sadSlump, sweatDropWorry, dizzySpiralWobble, sleepyHalfLidWake
    case flowerToOrangeBlink, creamFlowerBloom, peekUpPupilDrop, yellowToWhiteBlink, sadEyesSlideOut, sadEyesRiseIn
    case floatingHeartsLove, pinkArcsToGreenWake, scowlBlinkSoften, greenBlinkGrowWide, squintOpenLookLeft
    case blinkToHalfLidsUp, sleepyLidsToSad, redEyesTiltDroop, heatSweatShower, heatCoolDownOrange, blinkIntoSmug
    case blinkTallLookDownLeft, sadBloomYellowFlowers, annoyedBlinkSideEye, tiltBlinkStraighten, heartEyesWake
    case catSlitPupilShift, eyesWrapAround, grumpyBlinkSkeptical, cyanBlinkPupilsShrink
}

/// The clips a kind of moment draws from, so the same moment rarely looks
/// the same twice.
enum LilGuyRepertoire {
    /// Little things he does on his own during the day.
    static let fidgets: [LilGuyClip] = [
        .attentionShift, .downLeftTurn, .colorSwapBlink, .warmUpColorShift, .slowBlinkPupilDrop, .quickBlinkPupilDrop,
        .orangeToWhiteWake, .tiltedPairBlink, .yellowToWhiteBlink, .pinkArcsToGreenWake, .squintOpenLookLeft,
        .blinkTallLookDownLeft, .annoyedBlinkSideEye, .tiltBlinkStraighten, .catSlitPupilShift, .eyesWrapAround,
        .grumpyBlinkSkeptical, .cyanBlinkPupilsShrink, .gazeHold, .wink, .blinkRecovery,
    ]
    /// Late at night his fidgets are sleepy ones.
    static let nightFidgets: [LilGuyClip] = [
        .longClosedBlink, .sleepyHalfLidWake, .blinkToHalfLidsUp, .sleepyLidsToSad, .squashCloseRise,
    ]
    static let waking: [LilGuyClip] = [.wakeUpPupilDrop, .peekUpPupilDrop, .happyArcPeekWake, .sleepyHalfLidWake]
    static let love: [LilGuyClip] = [.floatingHeartsLove, .heartPulse, .heartEyesFloatAway, .heartStreamFlatten, .heartContinuation]
    static let joy: [LilGuyClip] = [.smileStreakBlink, .heartEyesWake, .creamFlowerBloom, .flowerToOrangeBlink, .flowerEnter,
                                     .sadBloomYellowFlowers]
    static let anger: [LilGuyClip] = [.angryGlare, .grumpyReopen, .scowlBlinkSoften, .redEyesTiltDroop]
    static let sadness: [LilGuyClip] = [.sadEyesSlideOut, .sadSlump, .sadDroopWake, .sadEyesRiseIn]
    static let dizzy: [LilGuyClip] = [.dizzyPupilOrbit, .dizzySpiralWobble]
    static let startle: [LilGuyClip] = [.startleNervousDrift, .attentionRetreat, .retreatGesture]
    static let perk: [LilGuyClip] = [.greenBlinkGrowWide, .cyanBlinkPupilsShrink]
    static let yawn: [LilGuyClip] = [.blinkToHalfLidsUp, .sleepyLidsToSad]
    static let groove: [LilGuyClip] = [.smileStreakBlink, .heartStreamFlatten, .postWinkSettle]

    /// What he does on seeing a page of the open island.
    static func page(_ module: NotchModule, hot: Bool) -> LilGuyClip? {
        switch module {
        case .voice: return nil
        case .controls: return .tiltBlinkStraighten
        case .mixer: return NotchMusicService.shared.playback?.isPlaying == true ? .heartStreamFlatten : .cyanBlinkPupilsShrink
        case .music: return NotchMusicService.shared.playback?.isPlaying == true ? .floatingHeartsLove : .annoyedBlinkSideEye
        case .clipboard: return .quickBlinkPupilDrop
        case .captures: return .squintShut
        case .files: return .peekUpPupilDrop
        case .system: return hot ? .heatSweatShower : .catSlitPupilShift
        case .tools: return .eyesWrapAround
        case .calendar: return NotchIntentService.shared.meetingMinutes.map { $0 <= 15 } == true ? .boltPupilPulse : .blinkTallLookDownLeft
        case .notifications: return .sweatDropWorry
        case .timer: return .blinkIntoSmug
        case .camera: return .greenBlinkGrowWide
        case .downloads: return .wakeUpPupilDrop
        case .scratchpad: return .squintOpenLookLeft
        case .agents: return .dotRise
        case .watch: return .gazeHold
        }
    }

    /// A glance that fits the app that just came forward, if any.
    static func app(_ id: String) -> LilGuyClip? {
        if NotchIntentPriors.meetingApps.contains(id) { return .attentionShift }
        if NotchIntentPriors.weight(of: .music, app: id) >= 3 { return .heartStreamFlatten }
        if NotchIntentPriors.weight(of: .agents, app: id) >= 2 { return [.catSlitPupilShift, .squintOpenLookLeft].randomElement() }
        if NotchIntentPriors.weight(of: .files, app: id) >= 2 { return .peekUpPupilDrop }
        if NotchIntentPriors.weight(of: .scratchpad, app: id) >= 2 { return .blinkTallLookDownLeft }
        if NotchIntentPriors.weight(of: .captures, app: id) >= 2 { return .yellowToWhiteBlink }
        if NotchIntentPriors.weight(of: .downloads, app: id) >= 2 { return .tiltedPairBlink }
        return nil
    }
}

/// Lil Guy's sense of the screen, shared by every face on it. While one
/// shows, his eyes follow the pointer anywhere on the display, an app coming
/// forward gets a glance that fits it, a copy or a hot processor or a low
/// battery gets a face, late nights make him sleepy, and he sleeps while
/// nobody is at the Mac and wakes when they come back. Every so often he
/// fidgets on his own. Nothing here runs while no face is on screen.
final class LilGuyDirector {
    static let shared = LilGuyDirector()

    private let faces = NSHashTable<LilGuyFace>.weakObjects()
    private var monitors: [Any] = []
    private var activation: NSObjectProtocol?
    private var watch: Timer?
    private var fidget: Timer?
    private var lastLook = CGPoint(x: 9, y: 9)
    private var lastLookTime: CFTimeInterval = 0
    private var lastAmbient: CFTimeInterval = 0
    private var pasteboardCount = NSPasteboard.general.changeCount
    private var ticks = 0
    private var hot = false
    private var lowBattery = false
    private var awaySince: Date?
    private var pokes: [CFTimeInterval] = []
    /// Moments of his own wait this long after the last, so he never chatters.
    private static let ambientGap: CFTimeInterval = 15
    /// Nobody at the Mac this long, and he sleeps.
    private static let awayAfter: TimeInterval = 300

    private var shown: [LilGuyFace] { faces.allObjects.filter(\.visible) }

    func register(_ face: LilGuyFace) { faces.add(face) }

    /// A face came into sight or left it.
    func visibilityChanged() {
        if shown.isEmpty { stop() } else { start() }
    }

    /// Whether the processor has been busy lately, which makes him sweat.
    var processorHot: Bool { hot }

    // MARK: Touch

    /// A click on him: a giggle, a wink now and then, and dizzy after four
    /// quick ones.
    func poke(_ face: LilGuyFace) {
        let now = CACurrentMediaTime()
        pokes = pokes.filter { now - $0 < 1.6 } + [now]
        if pokes.count >= 4 {
            pokes = []
            face.play(LilGuyRepertoire.dizzy.randomElement()!)
        } else {
            face.gesture(Int.random(in: 0..<5) == 0 ? .wink : .giggle)
        }
    }

    // MARK: Watching

    private func start() {
        guard monitors.isEmpty else { return }
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: moves, handler: { [weak self] _ in self?.pointerMoved() }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: moves, handler: { [weak self] event in
            self?.pointerMoved()
            return event
        }) { monitors.append(local) }
        activation = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            self?.appCameForward(note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
        }
        let watch = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.look() }
        watch.tolerance = 0.5
        RunLoop.main.add(watch, forMode: .common)
        self.watch = watch
        scheduleFidget()
    }

    private func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        if let activation { NSWorkspace.shared.notificationCenter.removeObserver(activation) }
        activation = nil
        watch?.invalidate(); watch = nil
        fidget?.invalidate(); fidget = nil
    }

    /// His eyes go where the pointer is on the island's display: across it,
    /// and down the farther it is below the island.
    private func pointerMoved() {
        let now = CACurrentMediaTime()
        guard now - lastLookTime > 0.12 else { return }
        lastLookTime = now
        if awaySince != nil { cameBack() }
        let screen = NotchService.shared.geometry.screen
        guard screen.width > 0, screen.height > 0 else { return }
        let point = NSEvent.mouseLocation
        let x = max(-1, min(1, (point.x - screen.midX) / (screen.width / 2)))
        let y = max(-1, min(1, (screen.maxY - point.y) / screen.height * 2.4 - 0.4))
        guard abs(x - lastLook.x) > 0.04 || abs(y - lastLook.y) > 0.04 else { return }
        lastLook = CGPoint(x: x, y: y)
        for face in shown where !face.isBusy { face.look(x: x, y: y, hold: 2.5) }
    }

    private func appCameForward(_ app: NSRunningApplication?) {
        guard let id = app?.bundleIdentifier, id != Bundle.main.bundleIdentifier,
              let clip = LilGuyRepertoire.app(id) else { return }
        ambient(clip)
    }

    /// Every two seconds: the pasteboard; every twenty, the processor, the
    /// battery and whether anybody is still at the Mac.
    private func look() {
        let count = NSPasteboard.general.changeCount
        if count != pasteboardCount {
            pasteboardCount = count
            ambient(.quickBlinkPupilDrop)
        }
        ticks += 1
        guard ticks % 10 == 0 else { return }
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        if idle > Self.awayAfter, awaySince == nil {
            awaySince = Date(timeIntervalSinceNow: -idle)
            shown.forEach { $0.sleep() }
            return
        }
        var load = [0.0, 0.0, 0.0]
        if getloadavg(&load, 3) > 0 {
            let share = load[0] / Double(max(1, ProcessInfo.processInfo.activeProcessorCount))
            if !hot, share > 0.9 { hot = true; moment(.heatSweatShower) }
            else if hot, share < 0.5 { hot = false; moment(.heatCoolDownOrange) }
        }
        let power = NotchService.shared.power
        if let charge = power.chargePercent, !power.externalConnected {
            if !lowBattery, charge <= 15 { lowBattery = true; moment(charge <= 7 ? .sweatDropWorry : .sadSlump) }
        } else if lowBattery { lowBattery = false }
        if let charge = power.chargePercent, charge > 20 { lowBattery = false }
    }

    private func cameBack() {
        guard let since = awaySince else { return }
        awaySince = nil
        let away = Date().timeIntervalSince(since)
        let night = Self.isNight
        let clip: LilGuyClip = away > 1800 ? .startleNervousDrift
            : night ? .sleepyHalfLidWake : LilGuyRepertoire.waking.randomElement()!
        for face in shown {
            face.wake()
            face.play(clip)
        }
    }

    private func scheduleFidget() {
        fidget?.invalidate()
        let fidget = Timer(timeInterval: .random(in: 50...140), repeats: false) { [weak self] _ in
            guard let self else { return }
            if self.awaySince == nil {
                let pool = Self.isNight ? LilGuyRepertoire.nightFidgets : LilGuyRepertoire.fidgets
                self.ambient(pool.randomElement()!)
            }
            self.scheduleFidget()
        }
        fidget.tolerance = 5
        RunLoop.main.add(fidget, forMode: .common)
        self.fidget = fidget
    }

    private static var isNight: Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= 23 || hour < 6
    }

    /// Something he noticed on his own, unless he just did.
    private func ambient(_ clip: LilGuyClip) {
        let now = CACurrentMediaTime()
        guard now - lastAmbient > Self.ambientGap else { return }
        lastAmbient = now
        moment(clip)
    }

    /// Something that happened: every face on screen that is not already
    /// busy, or asleep, shows it.
    private func moment(_ clip: LilGuyClip) {
        for face in shown where !face.isBusy && !face.asleep { face.play(clip) }
    }
}
