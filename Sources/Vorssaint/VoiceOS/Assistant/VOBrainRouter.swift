// SPDX-License-Identifier: GPL-3.0-or-later
// Ported from VoiceOS Clone (Agent/Router.swift) into Vorssaint + VoiceOS.

import Foundation

/// Decides when the local model is enough and when a request genuinely needs Claude.
/// Claude is the exception: it's used only for screen questions, long or careful writing,
/// big selections, or when the local model asks for help — and never past the daily limit.
@MainActor
enum VOBrainRouter {
    /// Why this request needs the bigger model, or nil if local can handle it.
    static func reasonToEscalate(query: String, hasImage: Bool, selection: String?) -> String? {
        if hasImage { return "needs to see your screen" }
        if let sel = selection, sel.count > 2500 { return "long selected text" }
        let q = query.lowercased()
        let writing = #"\b(write|draft|compose|prepare|create)\b.*\b(proposal|essay|report|article|blog|post|plan|strategy|letter|cover letter|outline|speech|story|documentation|spec|summary)\b"#
        let lengthCue = #"\b(detailed|in detail|thorough|comprehensive|long|full|step[- ]by[- ]step|\d+[- ]page|pages|paragraphs)\b"#
        let analysis = #"\b(analy[sz]e|compare|contrast|pros and cons|evaluate|critique|review this|debug|refactor|explain why)\b"#
        if q.range(of: writing, options: .regularExpression) != nil { return "long writing" }
        if q.range(of: lengthCue, options: .regularExpression) != nil && q.split(separator: " ").count > 6 { return "a detailed answer" }
        if q.range(of: analysis, options: .regularExpression) != nil { return "careful reasoning" }
        return nil
    }

    /// The cloud AI to fall back to, or nil if escalation is off, over the limit, or unavailable.
    static func escalationTarget() -> (provider: VOProviderID, model: String)? {
        let s = VOSettings.shared
        guard s.escalationEnabled, !s.escalationProvider.isLocal else { return nil }
        let pm = VOProviderManager.shared
        guard pm.todayRequests(s.escalationProvider) < s.escalationDailyLimit else { return nil }
        if case .notInstalled = pm.status[s.escalationProvider] ?? .unknown { return nil }
        let model = s.escalationProvider == .claude ? s.escalationModel : pm.model(for: s.escalationProvider)
        return (s.escalationProvider, model)
    }

    static var escalationBlockedReason: String {
        let s = VOSettings.shared
        if !s.escalationEnabled { return "Using \(s.escalationProvider.displayName) for harder requests is turned off (Assistant → Assistant brain)." }
        if VOProviderManager.shared.todayRequests(s.escalationProvider) >= s.escalationDailyLimit {
            return "Today's \(s.escalationProvider.displayName) limit (\(s.escalationDailyLimit)) is used up."
        }
        return "\(s.escalationProvider.displayName) isn't available."
    }

    /// Small models invent extra actions; keep only ones the user plausibly asked for.
    static func plausible(_ type: String, query: String) -> Bool {
        let q = query.lowercased()
        func has(_ pattern: String) -> Bool { q.range(of: pattern, options: .regularExpression) != nil }
        switch type {
        case "send_message": return has(#"\b(text|message|imessage|tell|let .* know|send)\b"#)
        case "send_email": return has(#"\b(e-?mail|mail)\b"#)
        case "create_event": return has(#"\b(calendar|meeting|schedule|event|book|lunch|dinner|breakfast|appointment|call with)\b"#)
        case "create_reminder": return has(#"\b(remind|reminder|don't let me forget|dont let me forget)\b"#)
        case "create_note": return has(#"\b(note|jot|write down)\b"#)
        case "web_search": return has(#"\b(search|look up|google|find out|look for)\b"#)
        case "open_app", "open_url": return has(#"\b(open|launch|start|go to|show me|pull up)\b"#)
        case "find_files": return has(#"\b(find|where is|locate|look for)\b.*\b(file|pdf|doc|document|deck|folder|photo|screenshot|spreadsheet)s?\b"#)
        case "type_text": return has(#"\b(type|write|draft|reply|respond|insert|paste|put)\b"#)
        default: return true
        }
    }

    /// Small models fumble dates and stuff them into titles. Apple's date detector reads "tomorrow at 5pm"
    /// deterministically, so its answer wins for reminders and events, and the title is tidied.
    static func fixDates(_ actions: [VOAssistantAction], query: String) -> [VOAssistantAction] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return actions }
        let range = NSRange(query.startIndex..., in: query)
        let found = detector.firstMatch(in: query, options: [], range: range)?.date
        let iso = DateFormatter()
        iso.locale = Locale(identifier: "en_US_POSIX")
        iso.dateFormat = "yyyy-MM-dd'T'HH:mm:00"
        return actions.map { a in
            guard a.type == "create_reminder" || a.type == "create_event" else { return a }
            var a = a
            let key = a.type == "create_reminder" ? "due" : "start"
            if let found {
                let current = VODateParse.parse(a[key])
                if current == nil || abs(current!.timeIntervalSince(found)) > 60 { a[key] = iso.string(from: found) }
            }
            var title = a["title"].replacingOccurrences(of: #"\s*\([^)]*\)"#, with: "", options: .regularExpression)
            let tr = NSRange(title.startIndex..., in: title)
            if let m = detector.firstMatch(in: title, options: [], range: tr), let r = Range(m.range, in: title) {
                title.removeSubrange(r)
            }
            title = title.replacingOccurrences(of: #"\s+(at|on|by|for)\s*$"#, with: "", options: [.regularExpression, .caseInsensitive])
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            if !title.isEmpty { a["title"] = title }
            return a
        }
    }

    /// Finding a person, a profile or a page is a search the assistant opens,
    /// never something the local model may claim it did: such a request goes
    /// straight to the search, with nothing for the model to make up. A
    /// person on a site comes with `person`, so the assistant can look for
    /// the profile itself before settling for the site's own search.
    nonisolated static func lookup(_ query: String)
        -> (say: String, action: VOAssistantAction, person: (site: VOWebLookup.Site, name: String)?)? {
        let pattern = #"(?i)^\s*(?:hey\s+\w+[,\s]+)?(?:please\s+)?(?:(?:can|could|would)\s+you\s+)?(?:find|look\s*up|search(?:\s+for)?|google|pull\s+up)\s+(?:me\s+)?(.+?)[\s?.!]*$"#
        guard let match = query.range(of: pattern, options: .regularExpression),
              let regex = try? NSRegularExpression(pattern: pattern),
              let result = regex.firstMatch(in: query, range: NSRange(match, in: query)),
              let range = Range(result.range(at: 1), in: query) else { return nil }
        var subject = String(query[range]).trimmingCharacters(in: .whitespaces)
        // "His LinkedIn" or "this person" points at the screen, which a
        // search for the pronoun would not find.
        if subject.range(of: #"(?i)\b(his|her|hers|their|this|that|these|those|him|them|it)\b"#,
                         options: .regularExpression) != nil { return nil }
        // Files and the Mac's own things belong to their own actions.
        if subject.range(of: #"(?i)\b(file|files|folder|document|pdf|download|downloads|screenshot|my\s+(?:mac|calendar|notes|reminders|messages))\b"#,
                         options: .regularExpression) != nil { return nil }
        func strip(_ words: String) -> String {
            subject.replacingOccurrences(of: #"(?i)\b("# + words + #")\b"#, with: " ", options: .regularExpression)
                .replacingOccurrences(of: #"(?i)['’]s\b"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
        }
        func encoded(_ text: String) -> String {
            text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
        }
        if let site = VOWebLookup.site(in: subject) {
            let who = strip(site.spoken + #"|profile|page|account|handle|on|the|a"#)
            guard !who.isEmpty else { return nil }
            // Names are said as names, however they were typed.
            let name = who.capitalized
            return ("Searching \(site.name) for \(name).",
                    VOAssistantAction(type: "open_url", fields: ["url": site.search(who).absoluteString]),
                    (site, name))
        }
        if subject.range(of: #"(?i)\byou\s*tube\b"#, options: .regularExpression) != nil {
            let what = strip(#"you\s*tube|video|videos|on|the|a"#)
            guard !what.isEmpty else { return nil }
            return ("Searching YouTube for \(what).",
                    VOAssistantAction(type: "open_url",
                                      fields: ["url": "https://www.youtube.com/results?search_query=\(encoded(what))"]), nil)
        }
        subject = strip("online|on the web|on google")
        guard !subject.isEmpty else { return nil }
        return ("Searching the web for \(subject).", VOAssistantAction(type: "web_search", fields: ["query": subject]), nil)
    }

    /// Does arithmetic the small model would get wrong: "15% of 240", "12 times 7", "3.5 + 2".
    static func calculatorHint(_ query: String) -> String? {
        let q = query.lowercased().replacingOccurrences(of: ",", with: "")
        if let m = q.firstMatch(of: #/(\d+(?:\.\d+)?)\s*(?:%|percent)\s+of\s+(\d+(?:\.\d+)?)/#),
           let p = Double(m.1), let n = Double(m.2) {
            return "\(fmt(p))% of \(fmt(n)) = \(fmt(p * n / 100))"
        }
        let words = q.replacingOccurrences(of: "multiplied by", with: "*").replacingOccurrences(of: "times", with: "*")
            .replacingOccurrences(of: "divided by", with: "/").replacingOccurrences(of: "plus", with: "+")
            .replacingOccurrences(of: "minus", with: "-").replacingOccurrences(of: " x ", with: " * ")
        if let m = words.firstMatch(of: #/(\d+(?:\.\d+)?)\s*([+\-*\/])\s*(\d+(?:\.\d+)?)/#),
           let a = Double(m.1), let b = Double(m.3) {
            let r: Double
            switch m.2 {
            case "+": r = a + b
            case "-": r = a - b
            case "*": r = a * b
            default: guard b != 0 else { return nil }; r = a / b
            }
            return "\(fmt(a)) \(m.2) \(fmt(b)) = \(fmt(r))"
        }
        return nil
    }

    private static func fmt(_ d: Double) -> String {
        d.rounded() == d ? String(Int(d)) : String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), d).replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
    }
}
