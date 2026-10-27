// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices

/// Ranks the island's pages for the hub and the hover dock, from what is
/// going on and from the pages the person picked before in moments like this
/// one: the app in front, the kind of window it shows, the time of day.
/// It only reads: bundle ids, a window title reduced to one word, and the
/// times of the last copy and capture, never their contents. What it learns
/// stays in this Mac's preferences, and Settings can forget it.
final class NotchIntentService: ObservableObject {
    static let shared = NotchIntentService()

    @Published private(set) var suggestions: [NotchIntentSuggestion] = []

    /// A page counts as chosen once it stays on screen this long, so
    /// stepping through pages with Control-Tab teaches nothing.
    private static let dwell: TimeInterval = 1.5
    private static let modelKey = "notchIntentModel"

    private var model: NotchIntentModel
    private var front: (id: String, name: String)?
    private var scene: NotchIntentScene?
    private var sceneSerial = 0
    private var activationObserver: NSObjectProtocol?
    private var choiceWork: DispatchWorkItem?
    private let queue = DispatchQueue(label: "com.vorssaint.voiceos.notch-intent", qos: .userInitiated)

    private init() {
        model = UserDefaults.standard.data(forKey: Self.modelKey)
            .flatMap { try? JSONDecoder().decode(NotchIntentModel.self, from: $0) } ?? NotchIntentModel()
    }

    /// Learning and the habits it draws on; live signals rank pages either way.
    var learns: Bool { UserDefaults.standard.bool(forKey: DefaultsKey.notchSuggestions) }

    func syncWithPreferences() {
        guard activationObserver == nil else { return }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            self?.noteFront(note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
        }
        noteFront(NSWorkspace.shared.frontmostApplication)
    }

    func stop() {
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        activationObserver = nil
        choiceWork?.cancel(); choiceWork = nil
    }

    /// The pointer reached the island: the front window may have changed
    /// since its app came forward, so its kind is read again before the
    /// dock or the hub asks.
    func prepare() {
        noteFront(NSWorkspace.shared.frontmostApplication)
    }

    /// Ranks `modules` for this moment and publishes the ones worth showing.
    @discardableResult
    func refresh(modules: [NotchModule], limit: Int = 3) -> [NotchIntentSuggestion] {
        let context = context()
        let ranked = learns ? model.rank(modules, in: context)
            // Without learning, only what is going on decides.
            : NotchIntentModel().rank(modules, in: NotchIntentContext(date: context.date, signals: context.signals))
        let notable = NotchIntentModel.notable(ranked, limit: limit)
        let shown = learns ? notable : notable.filter { if case .live = $0.reason { return true }; return false }
        if suggestions != shown { suggestions = shown }
        return shown
    }

    /// The person opened `module`; once it stays, the moment it was opened
    /// in is learned.
    func chose(_ module: NotchModule) {
        choiceWork?.cancel(); choiceWork = nil
        guard learns else { return }
        let context = context()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.learns else { return }
            let island = NotchService.shared
            guard island.expanded, island.selected == module, !island.showingSections else { return }
            self.model.learn(module, in: context)
            self.save()
        }
        choiceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.dwell, execute: work)
    }

    func forget() {
        choiceWork?.cancel(); choiceWork = nil
        model = NotchIntentModel()
        UserDefaults.standard.removeObject(forKey: Self.modelKey)
        suggestions = []
    }

    /// How many choices the model has learned, for Settings.
    var learnedChoices: Int { model.choices }

    private func save() {
        guard let data = try? JSONEncoder().encode(model) else { return }
        UserDefaults.standard.set(data, forKey: Self.modelKey)
    }

    private func context(now: Date = Date()) -> NotchIntentContext {
        let island = NotchService.shared
        var signals = Set<NotchIntentSignal>()
        if island.hasMusicActivity { signals.insert(.playing) }
        if island.hasTimerActivity { signals.insert(.timer) }
        if island.hasDownloadActivity { signals.insert(.downloading) }
        if island.hasAgentActivity { signals.insert(.agents) }
        if island.hasWatchActivity { signals.insert(.watching) }
        if let countdown = NotchCalendarService.shared.countdown, !countdown.event.allDay {
            if countdown.ongoing, countdown.event.start <= now, countdown.event.end > now { signals.insert(.meetingNow) }
            else if !countdown.ongoing, countdown.event.start > now,
                    countdown.event.start.timeIntervalSince(now) <= 15 * 60 { signals.insert(.meetingSoon) }
        }
        if let copied = ClipboardHistoryService.shared.entries.lazy.map(\.copiedAt).max(),
           now.timeIntervalSince(copied) < 90 { signals.insert(.copied) }
        if let captured = RecentCaptureService.shared.entries.lazy.map(\.createdAt).max(),
           now.timeIntervalSince(captured) < 180 { signals.insert(.captured) }
        return NotchIntentContext(app: learns ? front?.id : nil, appName: front?.name,
                                  scene: learns ? scene : nil, date: now, signals: signals)
    }

    /// The minutes until the next event, for the hub's calendar card.
    var meetingMinutes: Int? {
        guard let countdown = NotchCalendarService.shared.countdown, !countdown.ongoing else { return nil }
        let seconds = countdown.event.start.timeIntervalSinceNow
        return seconds > 0 ? Int((seconds / 60).rounded(.up)) : nil
    }

    private func noteFront(_ app: NSRunningApplication?) {
        guard let app, let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier else { return }
        if front?.id != id { scene = nil }
        front = (id, app.localizedName ?? id)
        readScene(pid: app.processIdentifier, app: id)
    }

    /// The front window's title is read off the main thread, so an app slow
    /// to answer Accessibility never holds the island up, and only the word
    /// it reduces to is kept.
    private func readScene(pid: pid_t, app: String) {
        guard learns else { scene = nil; return }
        sceneSerial += 1
        let serial = sceneSerial
        guard AXIsProcessTrusted() else {
            scene = NotchIntentScene.classify(title: nil, app: app)
            return
        }
        queue.async { [weak self] in
            let element = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(element, 0.25)
            var window: CFTypeRef?
            var title: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &window) == .success,
               let window, CFGetTypeID(window) == AXUIElementGetTypeID() {
                // The type was checked just above.
                _ = AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &title)
            }
            let scene = NotchIntentScene.classify(title: title as? String, app: app)
            DispatchQueue.main.async {
                guard let self, self.sceneSerial == serial else { return }
                self.scene = scene
            }
        }
    }
}
