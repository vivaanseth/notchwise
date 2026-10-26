// SPDX-License-Identifier: GPL-3.0-or-later
// Ported from VoiceOS Clone (Agent/ActionKit.swift) into Vorssaint + VoiceOS.

import AppKit
import EventKit
import Contacts

/// An action the agent proposed, e.g. {"type":"send_message","to":"Mom","body":"..."}.
struct VOAssistantAction: Identifiable, Equatable {
    let id = UUID()
    var type: String
    var fields: [String: String]

    subscript(_ key: String) -> String {
        get { fields[key] ?? "" }
        set { fields[key] = newValue }
    }

    init(type: String, fields: [String: String]) {
        self.type = type
        self.fields = fields
    }

    init?(json: [String: Any]) {
        guard let t = json["type"] as? String else { return nil }
        type = t
        var f: [String: String] = [:]
        for (k, v) in json where k != "type" {
            if let s = v as? String { f[k] = s }
            else if let n = v as? NSNumber { f[k] = n.stringValue }
            else if let a = v as? [Any] { f[k] = a.map { "\($0)" }.joined(separator: ", ") }
        }
        fields = f
    }
}

struct VOActionOutcome {
    var message: String
    var files: [URL] = []
}

struct VOActionSpec {
    let title: String          // "Send this message?"
    let appName: String
    let bundleID: String?
    let symbol: String
    let fields: [(label: String, key: String, multiline: Bool)]
    let primary: String
    let secondary: String?
    let confirm: Bool
    let capability: VOAssistantCapability?
}

enum VOActionKit {
    static func spec(_ type: String) -> VOActionSpec {
        switch type {
        case "send_message":
            return VOActionSpec(title: "Send this message?", appName: "Messages", bundleID: "com.apple.MobileSMS", symbol: "message.fill",
                              fields: [("To", "to", false), ("Message", "body", true)], primary: "Send", secondary: nil, confirm: true, capability: .messages)
        case "send_email":
            return VOActionSpec(title: "Send this email?", appName: "Mail", bundleID: "com.apple.mail", symbol: "envelope.fill",
                              fields: [("To", "to", false), ("Subject", "subject", false), ("Message Preview", "body", true)],
                              primary: "Send", secondary: "Open Draft", confirm: true, capability: .email)
        case "create_event":
            return VOActionSpec(title: "Add this to your calendar?", appName: "Calendar", bundleID: "com.apple.iCal", symbol: "calendar",
                              fields: [("Event", "title", false), ("When", "start", false), ("Minutes", "duration_minutes", false), ("Where", "location", false)],
                              primary: "Confirm", secondary: nil, confirm: true, capability: .calendar)
        case "create_reminder":
            return VOActionSpec(title: "Set this reminder?", appName: "Reminders", bundleID: "com.apple.reminders", symbol: "checklist",
                              fields: [("Reminder", "title", false), ("When", "due", false)], primary: "Confirm", secondary: nil, confirm: true, capability: .reminders)
        case "create_note":
            return VOActionSpec(title: "Save this note?", appName: "Notes", bundleID: "com.apple.Notes", symbol: "note.text",
                              fields: [("Title", "title", false), ("Note", "body", true)], primary: "Save", secondary: nil, confirm: true, capability: .notes)
        case "run_shortcut":
            return VOActionSpec(title: "Run this shortcut?", appName: "Shortcuts", bundleID: "com.apple.shortcuts", symbol: "square.stack.3d.up.fill",
                              fields: [("Shortcut", "name", false), ("Input", "input", true)], primary: "Run", secondary: nil, confirm: true, capability: .shortcuts)
        case "code_task":
            return VOActionSpec(title: "Start this coding task?", appName: "Claude Code", bundleID: "com.apple.Terminal", symbol: "terminal.fill",
                              fields: [("Task", "prompt", true), ("Folder", "folder", false)], primary: "Start", secondary: nil, confirm: true, capability: .claudeCode)
        case "web_search":
            return VOActionSpec(title: "Searching the web", appName: "Web", bundleID: nil, symbol: "globe", fields: [("Search", "query", false)],
                              primary: "Search", secondary: nil, confirm: false, capability: .webSearch)
        case "open_url":
            return VOActionSpec(title: "Opening link", appName: "Browser", bundleID: nil, symbol: "link", fields: [("URL", "url", false)],
                              primary: "Open", secondary: nil, confirm: false, capability: .openApps)
        case "open_app":
            return VOActionSpec(title: "Opening app", appName: "Finder", bundleID: "com.apple.finder", symbol: "app.fill", fields: [("App", "name", false)],
                              primary: "Open", secondary: nil, confirm: false, capability: .openApps)
        case "find_files":
            return VOActionSpec(title: "Finding files", appName: "Finder", bundleID: "com.apple.finder", symbol: "doc.text.magnifyingglass",
                              fields: [("Search", "query", false)], primary: "Find", secondary: nil, confirm: false, capability: .findFiles)
        case "type_text", "replace_selection":
            return VOActionSpec(title: "Writing it for you", appName: "Text", bundleID: nil, symbol: "keyboard", fields: [("Text", "text", true)],
                              primary: "Insert", secondary: nil, confirm: false, capability: nil)
        case "copy_text":
            return VOActionSpec(title: "Copied to clipboard", appName: "Clipboard", bundleID: nil, symbol: "doc.on.clipboard", fields: [("Text", "text", true)],
                              primary: "Copy", secondary: nil, confirm: false, capability: nil)
        default:
            return VOActionSpec(title: type.replacingOccurrences(of: "_", with: " ").capitalized, appName: "VoiceOS", bundleID: nil, symbol: "sparkles",
                              fields: [], primary: "Run", secondary: nil, confirm: true, capability: nil)
        }
    }

    static let knownTypes: Set<String> = ["send_message", "send_email", "create_event", "create_reminder", "create_note", "run_shortcut",
                                          "code_task", "web_search", "open_url", "open_app", "find_files", "type_text", "replace_selection", "copy_text"]

    // MARK: - Execute

    @MainActor
    static func execute(_ a: VOAssistantAction, secondary: Bool = false) async throws -> VOActionOutcome {
        switch a.type {
        case "send_message":
            let handle = try await VOContactLookup.resolve(a["to"], wantEmail: false)
            try VOAppleScript.run("""
            tell application "Messages"
                set targetService to 1st account whose service type = iMessage
                set targetBuddy to participant "\(VOAppleScript.esc(handle.value))" of targetService
                send "\(VOAppleScript.esc(a["body"]))" to targetBuddy
            end tell
            """)
            return VOActionOutcome(message: "Message sent to \(handle.display)")

        case "send_email":
            let handle = try await VOContactLookup.resolve(a["to"], wantEmail: true)
            if secondary {
                try VOAppleScript.run("""
                tell application "Mail"
                    set m to make new outgoing message with properties {subject:"\(VOAppleScript.esc(a["subject"]))", content:"\(VOAppleScript.esc(a["body"]))", visible:true}
                    tell m to make new to recipient at end of to recipients with properties {address:"\(VOAppleScript.esc(handle.value))"}
                    activate
                end tell
                """)
                return VOActionOutcome(message: "Draft opened in Mail")
            }
            try VOAppleScript.run("""
            tell application "Mail"
                set m to make new outgoing message with properties {subject:"\(VOAppleScript.esc(a["subject"]))", content:"\(VOAppleScript.esc(a["body"]))", visible:false}
                tell m to make new to recipient at end of to recipients with properties {address:"\(VOAppleScript.esc(handle.value))"}
                send m
            end tell
            """)
            return VOActionOutcome(message: "Email sent to \(handle.display)")

        case "create_event":
            let store = EKEventStore()
            guard try await store.requestFullAccessToEvents() else { throw VOError("Calendar access was denied. Allow it in System Settings → Privacy → Calendars.") }
            guard let start = VODateParse.parse(a["start"]) else { throw VOError("I couldn't understand the time \"\(a["start"])\".") }
            let ev = EKEvent(eventStore: store)
            ev.title = a["title"].isEmpty ? "New Event" : a["title"]
            ev.startDate = start
            if let end = VODateParse.parse(a["end"]), end > start { ev.endDate = end }
            else { ev.endDate = start.addingTimeInterval((Double(a["duration_minutes"]) ?? 30) * 60) }
            if !a["location"].isEmpty { ev.location = a["location"] }
            if !a["notes"].isEmpty { ev.notes = a["notes"] }
            ev.calendar = store.defaultCalendarForNewEvents
            try store.save(ev, span: .thisEvent)
            return VOActionOutcome(message: "\"\(ev.title ?? "")\" added · \(VODateParse.friendly(start))")

        case "create_reminder":
            let store = EKEventStore()
            guard try await store.requestFullAccessToReminders() else { throw VOError("Reminders access was denied. Allow it in System Settings → Privacy → Reminders.") }
            let r = EKReminder(eventStore: store)
            r.title = a["title"].isEmpty ? "Reminder" : a["title"]
            r.calendar = store.defaultCalendarForNewReminders()
            if !a["notes"].isEmpty { r.notes = a["notes"] }
            if let due = VODateParse.parse(a["due"]) {
                r.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
                r.addAlarm(EKAlarm(absoluteDate: due))
            }
            try store.save(r, commit: true)
            let when = VODateParse.parse(a["due"]).map { " · " + VODateParse.friendly($0) } ?? ""
            return VOActionOutcome(message: "Reminder set\(when)")

        case "create_note":
            let html = (["<b>\(escapeHTML(a["title"]))</b>"] + a["body"].split(separator: "\n", omittingEmptySubsequences: false).map { escapeHTML(String($0)) })
                .joined(separator: "<br>")
            try VOAppleScript.run("""
            tell application "Notes"
                try
                    make new note at folder "Notes" of default account with properties {body:"\(VOAppleScript.esc(html))"}
                on error
                    make new note with properties {body:"\(VOAppleScript.esc(html))"}
                end try
            end tell
            """)
            return VOActionOutcome(message: "Saved to Notes")

        case "run_shortcut":
            var args = ["run", a["name"]]
            if !a["input"].isEmpty {
                let f = VOCLIRunner.scratchDirectory().appendingPathComponent("shortcut-input.txt")
                try a["input"].write(to: f, atomically: true, encoding: .utf8)
                args += ["-i", f.path]
            }
            let r = try await VOCLIRunner.run("/usr/bin/shortcuts", args, timeout: 120)
            if r.status != 0 { throw VOError(r.stderr.isEmpty ? "Shortcut failed." : r.stderr) }
            return VOActionOutcome(message: r.stdout.isEmpty ? "Ran \"\(a["name"])\"" : r.stdout.prefix(200).description)

        case "code_task":
            var folder = a["folder"].isEmpty ? NSHomeDirectory() : (a["folder"] as NSString).expandingTildeInPath
            if !FileManager.default.fileExists(atPath: folder) { folder = NSHomeDirectory() }
            VOTerminal.run("claude \(VOTerminal.shellQuote(a["prompt"]))", banner: "VoiceOS → Claude Code", cwd: folder)
            return VOActionOutcome(message: "Claude Code started in \((folder as NSString).abbreviatingWithTildeInPath)")

        case "web_search":
            var c = URLComponents(string: "https://www.google.com/search")!
            c.queryItems = [URLQueryItem(name: "q", value: a["query"])]
            if let url = c.url { NSWorkspace.shared.open(url) }
            return VOActionOutcome(message: "Searched for \"\(a["query"])\"")

        case "open_url":
            var s = a["url"].trimmingCharacters(in: .whitespaces)
            if !s.contains("://") { s = "https://" + s }
            guard let url = URL(string: s) else { throw VOError("That link doesn't look right.") }
            NSWorkspace.shared.open(url)
            return VOActionOutcome(message: "Opened \(url.host ?? s)")

        case "open_app":
            guard let url = findApp(a["name"]) else { throw VOError("I couldn't find an app called \"\(a["name"])\".") }
            try await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            return VOActionOutcome(message: "Opened \(url.deletingPathExtension().lastPathComponent)")

        case "find_files":
            let files = await findFiles(a["query"])
            return VOActionOutcome(message: files.isEmpty ? "No files matched \"\(a["query"])\"" : "Found \(files.count) file\(files.count == 1 ? "" : "s")", files: files)

        case "type_text", "replace_selection":
            VOIsland.releaseKeyFocus()
            try await Task.sleep(nanoseconds: 180_000_000)
            VOTextInserter.insert(a["text"])
            return VOActionOutcome(message: "Inserted into \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "your app")")

        case "copy_text":
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(a["text"], forType: .string)
            return VOActionOutcome(message: "Copied to clipboard")

        default:
            throw VOError("I don't know how to do \"\(a.type)\" yet.")
        }
    }

    // MARK: - Helpers

    static func findApp(_ name: String) -> URL? {
        let wanted = name.lowercased().replacingOccurrences(of: ".app", with: "").trimmingCharacters(in: .whitespaces)
        guard !wanted.isEmpty else { return nil }
        let dirs = ["/Applications", "/System/Applications", "/System/Applications/Utilities", "/Applications/Utilities",
                    NSHomeDirectory() + "/Applications"]
        var best: (URL, Int)?
        for dir in dirs {
            guard let items = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            for item in items where item.hasSuffix(".app") {
                let n = item.dropLast(4).lowercased()
                let score = n == wanted ? 3 : (n.hasPrefix(wanted) ? 2 : (n.contains(wanted) ? 1 : 0))
                if score > (best?.1 ?? 0) { best = (URL(fileURLWithPath: dir).appendingPathComponent(item), score) }
            }
        }
        return best?.0
    }

    static func findFiles(_ query: String) async -> [URL] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        var paths: [String] = []
        for args in [["-onlyin", NSHomeDirectory(), "-name", q], ["-onlyin", NSHomeDirectory(), q]] where paths.count < 8 {
            if let r = try? await VOCLIRunner.run("/usr/bin/mdfind", args, timeout: 10) {
                for line in r.stdout.split(separator: "\n").map(String.init)
                where !line.contains("/Library/") && !line.contains("/.") && !paths.contains(line) {
                    paths.append(line)
                    if paths.count >= 8 { break }
                }
            }
        }
        return paths.map { URL(fileURLWithPath: $0) }
    }

    static func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }
}

enum VOAppleScript {
    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    @MainActor
    static func run(_ source: String) throws {
        var err: NSDictionary?
        guard let script = NSAppleScript(source: source) else { throw VOError("Couldn't build the AppleScript.") }
        script.executeAndReturnError(&err)
        if let err {
            let msg = err[NSAppleScript.errorMessage] as? String ?? "AppleScript failed."
            if (err[NSAppleScript.errorNumber] as? Int) == -1743 {
                throw VOError("VoiceOS needs permission to control that app. Allow it in System Settings → Privacy & Security → Automation.")
            }
            throw VOError(msg)
        }
    }
}

enum VOContactLookup {
    struct Handle { let display: String; let value: String }

    /// Turns "Mom" / "David Chen" into a phone number or email using the Contacts app.
    static func resolve(_ who: String, wantEmail: Bool) async throws -> Handle {
        let w = who.trimmingCharacters(in: .whitespaces)
        if w.contains("@") || w.range(of: #"^\+?[\d\s\-\(\)]{6,}$"#, options: .regularExpression) != nil {
            return Handle(display: w, value: w)
        }
        let store = CNContactStore()
        guard try await store.requestAccess(for: .contacts) else {
            throw VOError("Contacts access is needed to find \"\(w)\". Allow it in System Settings → Privacy → Contacts, or say a phone number or email.")
        }
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactNicknameKey, CNContactPhoneNumbersKey, CNContactEmailAddressesKey] as [CNKeyDescriptor]
        var matches = (try? store.unifiedContacts(matching: CNContact.predicateForContacts(matchingName: w), keysToFetch: keys)) ?? []
        if matches.isEmpty {
            // Nicknames like "Mom" live in the nickname field.
            let req = CNContactFetchRequest(keysToFetch: keys)
            try? store.enumerateContacts(with: req) { c, stop in
                if c.nickname.caseInsensitiveCompare(w) == .orderedSame { matches.append(c); stop.pointee = true }
            }
        }
        guard let c = matches.first else { throw VOError("I couldn't find \"\(w)\" in your contacts.") }
        let name = [c.givenName, c.familyName].filter { !$0.isEmpty }.joined(separator: " ")
        if wantEmail {
            guard let e = c.emailAddresses.first?.value as String? else { throw VOError("\(name) has no email address in Contacts.") }
            return Handle(display: name.isEmpty ? e : name, value: e)
        }
        if let p = c.phoneNumbers.first?.value.stringValue { return Handle(display: name.isEmpty ? p : name, value: p) }
        if let e = c.emailAddresses.first?.value as String? { return Handle(display: name.isEmpty ? e : name, value: e) }
        throw VOError("\(name) has no phone number or email in Contacts.")
    }
}

enum VODateParse {
    static func parse(_ s: String) -> Date? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: t) { return d }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: t) { return d }
        for f in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = .current
            df.dateFormat = f
            if let d = df.date(from: t) { return f == "yyyy-MM-dd" ? Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: d) : d }
        }
        return nil
    }

    static func friendly(_ d: Date) -> String {
        let cal = Calendar.current
        let time = d.formatted(date: .omitted, time: .shortened)
        if cal.isDateInToday(d) { return "Today, \(time)" }
        if cal.isDateInTomorrow(d) { return "Tomorrow, \(time)" }
        return d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
    }
}
