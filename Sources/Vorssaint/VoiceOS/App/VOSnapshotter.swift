// SPDX-License-Identifier: GPL-3.0-or-later
// Ported from VoiceOS Clone (App/Snapshotter.swift) into Vorssaint + VoiceOS.

import AppKit
import CoreGraphics

/// Developer aid: `VOICEOS_SNAPSHOT=/some/dir open VoiceOS.app` renders every screen to PNGs and quits.
/// Apps may always capture their own windows, so this works without Screen Recording permission.
@MainActor
enum VOSnapshotter {
    static func runIfRequested() -> Bool {
        guard let dir = ProcessInfo.processInfo.environment["VOICEOS_SNAPSHOT"], !dir.isEmpty else { return false }
        let out = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        Task { await run(out) }
        return true
    }

    private static func pause(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000)) }

    private static func run(_ out: URL) async {
        let settings = VOSettings.shared
        let wasOnboarded = settings.onboardingDone
        let wasHistory = settings.saveHistory
        // The VoiceOS pages, in Vorssaint's Settings window with its sidebar.
        VOMainWindow.show(.dashboard)
        await pause(2)
        guard let main = NSApp.windows.first(where: { $0 is SettingsWindow && $0.isVisible }) else { NSApp.terminate(nil); return }

        settings.onboardingDone = false
        await pause(1)
        capture(main, out.appendingPathComponent("00-onboarding.png"))
        settings.onboardingDone = true
        await pause(0.6)
        for (i, page) in VOPage.allCases.enumerated() {
            VOMainWindow.show(page)
            await pause(1.0)
            capture(main, out.appendingPathComponent(String(format: "%02d-%@.png", i + 1, page.rawValue)))
        }
        main.orderOut(nil)

        // The island: Vorssaint's one panel, with the assistant as its home.
        let agent = VOAssistantController.shared
        let island = NotchService.shared
        guard let notch = VOIsland.window else { NSApp.terminate(nil); return }
        // The panel is a stage as large as the display; only the island's
        // corner of it is captured.
        let area = islandArea()
        var log = ""
        func shot(_ name: String) {
            log += "\(name): expanded=\(island.expanded) selected=\(island.selected.rawValue) "
                + "size=\(island.surfaceSize) activity=\(island.compactActivity?.rawValue ?? "none")\n"
            capture(notch, out.appendingPathComponent(name), backdrop: true, area: area)
        }
        await pause(1.2)
        shot("10-island-idle.png")
        agent.open(focus: false)
        await pause(1.0)
        shot("11-assistant-empty.png")
        agent.phase = .listening
        agent.live = "Can you find his LinkedIn"
        agent.level = 0.6
        await pause(0.6)
        shot("12-assistant-listening.png")
        agent.loadDemo()
        await pause(1.4)
        shot("13-assistant-conversation.png")
        agent.close()
        await pause(0.9)
        shot("14-island-after-close.png")

        // The assistant at work with its page closed: the closed island's strip.
        var working = VOAssistantTurn(query: "What's the weather in Lisbon?", provider: .ollama)
        working.thinking = true
        agent.turns = [working]
        await pause(1.2)
        shot("15-island-voice-strip.png")
        agent.turns = []
        await pause(0.8)

        // Vorssaint's own pages still open in the same island.
        island.open(.controls)
        await pause(1.0)
        shot("16-island-controls.png")
        island.open(sections: true)
        await pause(1.0)
        shot("17-island-sections.png")
        island.collapse()
        await pause(0.9)

        // Animation timeline (open → close) with the island's sizes logged.
        let marks: [Double] = [0.1, 0.3, 0.6, 1.0, 1.6, 2.5]
        agent.open(focus: false)
        var t = 0.0
        for (i, m) in marks.enumerated() {
            await pause(m - t); t = m
            shot("30-open-\(i).png")
        }
        agent.close()
        t = 0
        for (i, m) in marks.enumerated() {
            await pause(m - t); t = m
            shot("31-close-\(i).png")
        }
        try? log.write(to: out.appendingPathComponent("timeline.txt"), atomically: true, encoding: .utf8)

        // Dictation pill states
        let dictation = VODictationController.shared
        let pill = NSApp.windows.first { $0.frame.width == 560 && $0.frame.height == 80 }
        dictation.appIcon = VOAppIcons.icon(bundleID: "com.apple.Notes")
        dictation.level = 0.7
        dictation.state = .listening
        await pause(0.7)
        if let pill { capture(pill, out.appendingPathComponent("20-pill-listening.png"), backdrop: true) }
        dictation.state = .processing
        await pause(0.6)
        if let pill { capture(pill, out.appendingPathComponent("21-pill-processing.png"), backdrop: true) }
        dictation.state = .message("Inserted without AI polish — Claude: Credit balance is too low", isError: true)
        await pause(0.6)
        if let pill { capture(pill, out.appendingPathComponent("22-pill-message.png"), backdrop: true) }
        dictation.state = .hidden

        settings.onboardingDone = wasOnboarded
        settings.saveHistory = wasHistory
        await pause(0.3)
        NSApp.terminate(nil)
    }

    /// The island hangs at the top centre of its panel, a stage as large as
    /// the display; only that corner is kept.
    private static func islandArea() -> CGSize { CGSize(width: 820, height: 640) }

    /// Draws the window's content in this process. The window server's own
    /// capture returns nothing without Screen Recording permission, which an
    /// ad-hoc build never keeps; drawing our own views needs none.
    private static func capture(_ window: NSWindow, _ url: URL, backdrop: Bool = false, area: CGSize? = nil) {
        guard let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard var img = rep.cgImage else { return }
        if let area {
            let scale = CGFloat(img.width) / max(1, view.bounds.width)
            let width = min(area.width, view.bounds.width) * scale
            let height = min(area.height, view.bounds.height) * scale
            if let cropped = img.cropping(to: CGRect(x: (CGFloat(img.width) - width) / 2, y: 0,
                                                     width: width, height: height).integral) {
                img = cropped
            }
        }
        var final = img
        if backdrop, let ctx = CGContext(data: nil, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            let colors = [CGColor(red: 0.62, green: 0.80, blue: 1, alpha: 1), CGColor(red: 0.25, green: 0.52, blue: 0.9, alpha: 1)] as CFArray
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: CGFloat(img.height)), end: .zero, options: [])
            }
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
            if let composed = ctx.makeImage() { final = composed }
        }
        let out = NSBitmapImageRep(cgImage: final)
        try? out.representation(using: .png, properties: [:])?.write(to: url)
    }
}


extension VOAssistantController {
    /// Sample conversation used by the snapshot tool.
    func loadDemo() {
        var t1 = VOAssistantTurn(query: "What's on my calendar tomorrow?", provider: .claude)
        t1.say = "You've got three things tomorrow, starting with the design review at eleven."
        t1.detail = "- **11:00** Design review\n- **12:30** Lunch with Sarah\n- **3:00 PM** 1:1 with PM"
        t1.thinking = false
        var t2 = VOAssistantTurn(query: "Tell Maya I'll send the deck after lunch", provider: .claude)
        t2.say = "Drafted a message to Maya — take a look before I send it."
        t2.thinking = false
        t2.actions = [VOAssistantActionItem(action: VOAssistantAction(type: "send_message", fields: ["to": "Maya", "body": "Hey! I'll send the deck over right after lunch."]),
                                      state: .needsConfirm),
                      VOAssistantActionItem(action: VOAssistantAction(type: "create_reminder", fields: ["title": "Send Maya the deck"]),
                                      state: .done("Reminder set · Today, 1:30 PM"))]
        turns = [t1, t2]
        expanded = true
        phase = .answered
        VOAssistantVoice.shared.currentText = t2.say
        VOAssistantVoice.shared.spokenUpTo = 24
    }
}
