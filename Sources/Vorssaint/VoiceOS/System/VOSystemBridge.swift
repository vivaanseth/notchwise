// SPDX-License-Identifier: GPL-3.0-or-later
// Ported from VoiceOS Clone (System/SystemBridge.swift) into Vorssaint + VoiceOS.

import AppKit
import ApplicationServices
import ScreenCaptureKit
import CoreGraphics

/// Inserting text into whatever app has focus, reading the selection, and grabbing screen context.
enum VOTextInserter {
    /// Pastes via the clipboard (fast and works in every standard text field), then restores the clipboard.
    static func insert(_ text: String) {
        guard !text.isEmpty else { return }
        let pb = NSPasteboard.general
        let saved: [[NSPasteboard.PasteboardType: Data]] = (pb.pasteboardItems ?? []).map { item in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for t in item.types { if let d = item.data(forType: t) { dict[t] = d } }
            return dict
        }
        pb.clearContents()
        pb.setString(text, forType: .string)
        pb.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        let changeCount = pb.changeCount

        postKey(9, flags: .maskCommand) // V

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard pb.changeCount == changeCount else { return } // user copied something meanwhile
            pb.clearContents()
            let items: [NSPasteboardItem] = saved.map { dict in
                let item = NSPasteboardItem()
                for (t, d) in dict { item.setData(d, forType: t) }
                return item
            }
            if !items.isEmpty { pb.writeObjects(items) }
        }
    }

    static func postKey(_ code: CGKeyCode, flags: CGEventFlags = []) {
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

struct VOFrontContext {
    var appName: String
    var bundleID: String?
    var pid: pid_t?
    var windowTitle: String?
    var selectedText: String?
    var icon: NSImage?
}

enum VOAccessibility {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func prompt() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    static func frontContext() -> VOFrontContext {
        let app = NSWorkspace.shared.frontmostApplication
        var ctx = VOFrontContext(appName: app?.localizedName ?? "Unknown", bundleID: app?.bundleIdentifier,
                               pid: app?.processIdentifier, icon: app?.icon)
        guard isTrusted, let pid = app?.processIdentifier else { return ctx }
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, 0.25)
        if let win: AXUIElement = copy(axApp, kAXFocusedWindowAttribute) {
            ctx.windowTitle = copy(win, kAXTitleAttribute)
        }
        if let focused: AXUIElement = copy(axApp, kAXFocusedUIElementAttribute) {
            if let sel: String = copy(focused, kAXSelectedTextAttribute), !sel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ctx.selectedText = sel
            }
        }
        return ctx
    }

    private static func copy<T>(_ el: AXUIElement, _ attr: String) -> T? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success, let v else { return nil }
        if T.self == AXUIElement.self {
            guard CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
            return (v as! AXUIElement) as? T
        }
        return v as? T
    }
}

enum VOScreenGrab {
    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }
    static func request() { _ = CGRequestScreenCaptureAccess() }

    /// Captures the display under the mouse (excluding VoiceOS windows), marks where the cursor is
    /// pointing, and saves a PNG for the model to look at.
    static func captureAroundCursor() async -> URL? {
        guard hasPermission else { return nil }
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main,
              let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return nil }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else { return nil }
            let mine = content.windows.filter { $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier }
            let filter = SCContentFilter(display: display, excludingWindows: mine)
            let config = SCStreamConfiguration()
            let scale = min(1.0, 1280.0 / screen.frame.width)
            config.width = Int(screen.frame.width * scale * 1.0)
            config.height = Int(screen.frame.height * scale * 1.0)
            config.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

            // Draw a pointer marker where the user is pointing.
            let w = image.width, h = image.height
            guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            let px = (mouse.x - screen.frame.minX) / screen.frame.width * CGFloat(w)
            let py = (mouse.y - screen.frame.minY) / screen.frame.height * CGFloat(h)
            ctx.setStrokeColor(CGColor(red: 1, green: 0.2, blue: 0.2, alpha: 0.95))
            ctx.setLineWidth(4)
            ctx.strokeEllipse(in: CGRect(x: px - 22, y: py - 22, width: 44, height: 44))
            guard let marked = ctx.makeImage() else { return nil }
            let rep = NSBitmapImageRep(cgImage: marked)
            guard let jpg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.72]) else { return nil }
            let url = VOCLIRunner.scratchDirectory().appendingPathComponent("screen-\(UUID().uuidString).jpg")
            try jpg.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}

enum VOSounds {
    static func start() { play("Tink") }
    static func stop() { play("Pop") }
    static func error() { play("Basso") }

    private static func play(_ name: String) {
        guard VOSettings.shared.playSounds else { return }
        let s = NSSound(named: NSSound.Name(name))
        s?.volume = 0.35
        s?.play()
    }
}

enum VOAppIcons {
    static func icon(bundleID: String?) -> NSImage? {
        guard let bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    static func icon(path: String) -> NSImage? {
        FileManager.default.fileExists(atPath: path) ? NSWorkspace.shared.icon(forFile: path) : nil
    }
}

enum VOSystemSettings {
    static func open(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
    static func openKeyboard() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
