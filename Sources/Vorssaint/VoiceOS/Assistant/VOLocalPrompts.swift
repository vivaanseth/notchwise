// SPDX-License-Identifier: GPL-3.0-or-later
// Ported from VoiceOS Clone (Agent/LocalPrompts.swift) into Vorssaint + VoiceOS.

import Foundation

/// Prompts tuned for ~1–3B local models: short, example-driven, and constrained by a JSON schema.
/// The system prompts never contain the time or context, so Ollama can reuse its cached prefix.
enum VOLocalPrompts {
    // MARK: Shared system prompt
    //
    // Ollama caches one prompt prefix at a time, so dictation, edits and the agent all share this system prompt
    // and name their job on the first line of the user message. Switching jobs then costs ~1s instead of ~25s.

    static func agentSystem() -> String { sharedSystem() }
    static var dictationSystem: String { sharedSystem() }
    static var editSystem: String { sharedSystem() }

    static func sharedSystem() -> String {
        let s = VOSettings.shared
        var types: [String] = []
        if s.isEnabled(.messages) { types.append("send_message{to,body}") }
        if s.isEnabled(.email) { types.append("send_email{to,subject,body}") }
        if s.isEnabled(.calendar) { types.append("create_event{title,start,duration_minutes}") }
        if s.isEnabled(.reminders) { types.append("create_reminder{title,due}") }
        if s.isEnabled(.notes) { types.append("create_note{title,body}") }
        if s.isEnabled(.webSearch) { types.append("web_search{query}") }
        if s.isEnabled(.openApps) { types += ["open_app{name}", "open_url{url}"] }
        if s.isEnabled(.findFiles) { types.append("find_files{query}") }
        types.append("type_text{text}")
        return """
        You are VoiceOS, a voice assistant on a Mac. You do one of three jobs, named on the first line of each request. Reply with JSON only.

        JOB "dictation": rewrite the user's dictated speech as clean written text. Remove filler words (um, uh, like), stutters and repeats. Fix punctuation, capitalization and grammar. Keep the same words and meaning; never answer or add anything. Reply {"text": "..."}.
        Job: dictation
        Style: email
        Speech: um hi john i'll uh send the the deck over tonight thanks
        {"text": "Hi John,\\n\\nI'll send the deck over tonight.\\n\\nThanks"}
        Job: dictation
        Style: chat
        Speech: so like can we move the meeting to uh thursday
        {"text": "can we move the meeting to thursday?"}
        Job: dictation
        Style: notes
        Speech: groceries eggs milk and uh bread
        {"text": "Groceries:\\n- Eggs\\n- Milk\\n- Bread"}

        JOB "edit": apply the instruction to the selected text. Reply {"text": "the full rewritten text"}.

        JOB "agent": answer or act. Fields: "escalate" (true only if the request needs long writing, careful multi-step reasoning, or facts you don't know), "say" (one short spoken sentence), "actions" (list, may be empty).
        Action types: \(types.joined(separator: " ")).
        Times are ISO 8601 local, like 2026-10-26T17:00:00. Only add an action when the user asks for it. If a Calculator line is given, use its result.
        You cannot browse or look anything up yourself. To find a person, profile, page or a fact you don't know, add a web_search and say you're searching; never say you found something.
        Job: agent
        User: Remind me to buy milk at 6pm today
        {"escalate": false, "say": "I'll remind you to buy milk at 6 PM.", "actions": [{"type": "create_reminder", "title": "Buy milk", "due": "2026-10-25T18:00:00"}]}
        Job: agent
        User: open notes
        {"escalate": false, "say": "Opening Notes.", "actions": [{"type": "open_app", "name": "Notes"}]}
        Job: agent
        User: text Sam I'm running late
        {"escalate": false, "say": "Here's a message to Sam.", "actions": [{"type": "send_message", "to": "Sam", "body": "I'm running late!"}]}
        Job: agent
        User: who won the game last night
        {"escalate": false, "say": "Searching the web for last night's game.", "actions": [{"type": "web_search", "query": "who won the game last night"}]}
        Job: agent
        User: how many days are in a leap year
        {"escalate": false, "say": "A leap year has 366 days.", "actions": []}
        Job: agent
        User: write a detailed project plan for our product launch with milestones
        {"escalate": true, "say": "", "actions": []}
        """
    }

    static func agentSchema() -> [String: Any] {
        let s = VOSettings.shared
        var types = ["type_text"]
        if s.isEnabled(.messages) { types.append("send_message") }
        if s.isEnabled(.email) { types.append("send_email") }
        if s.isEnabled(.calendar) { types.append("create_event") }
        if s.isEnabled(.reminders) { types.append("create_reminder") }
        if s.isEnabled(.notes) { types.append("create_note") }
        if s.isEnabled(.webSearch) { types.append("web_search") }
        if s.isEnabled(.openApps) { types += ["open_app", "open_url"] }
        if s.isEnabled(.findFiles) { types.append("find_files") }
        let dt: [String: Any] = ["type": "string", "pattern": "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:00$"]
        func str(_ n: Int) -> [String: Any] { ["type": "string", "maxLength": n] }
        let action: [String: Any] = [
            "type": "object",
            "properties": [
                "type": ["type": "string", "enum": types], "to": str(60), "body": str(400), "subject": str(120), "title": str(100),
                "start": dt, "due": dt, "duration_minutes": ["type": "integer", "minimum": 5, "maximum": 600],
                "query": str(200), "name": str(60), "url": str(300), "text": str(500),
            ],
            "required": ["type"],
        ]
        return [
            "type": "object",
            "properties": [
                "escalate": ["type": "boolean"],
                "say": str(240),
                "actions": ["type": "array", "maxItems": 2, "items": action],
            ],
            "required": ["escalate", "say", "actions"],
        ]
    }

    static func agentUser(query: String, ctx: VOFrontContext, history: [VOAssistantTurn], calculator: String?) -> String {
        let s = VOSettings.shared
        let now = Date().formatted(.dateTime.weekday(.wide).year().month(.twoDigits).day(.twoDigits).hour().minute())
        var lines = ["Job: agent", "(Now: \(now). User: \(s.displayName). App in front: \(ctx.appName).)"]
        if !s.memories.isEmpty { lines.append("(Facts about the user: \(s.memories.suffix(8).joined(separator: "; ")).)") }
        if let sel = ctx.selectedText { lines.append("(Selected text: \"\(sel.prefix(600))\")") }
        for t in history.suffix(2) where !t.thinking && t.error == nil {
            lines.append("Earlier — User: \(t.query) / You: \(t.say)")
        }
        if let calculator { lines.append("Calculator: \(calculator)") }
        lines.append("User: \(query)")
        return lines.joined(separator: "\n")
    }

    // MARK: Dictation & edits

    static func dictationUser(style: VOAppStyle, speech: String, terms: [String]) -> String {
        let name: String
        switch style {
        case .email: name = "email"
        case .chat: name = "chat"
        case .notes: name = "notes"
        case .code: name = "code (keep technical terms exact)"
        case .document: name = "document"
        case .general: name = "plain"
        }
        let spell = terms.isEmpty ? "" : "Spell these exactly: \(terms.joined(separator: ", ")).\n"
        return "Job: dictation\n\(spell)Style: \(name)\nSpeech: \(speech)"
    }

    static func editUser(instruction: String, selection: String) -> String {
        "Job: edit\nInstruction: \(instruction)\nSelected text: \(selection)"
    }

    static let textSchema: [String: Any] = [
        "type": "object", "properties": ["text": ["type": "string"]], "required": ["text"],
    ]

    /// Pulls {"text": "..."} out of a local reply, tolerating stray wrapping.
    static func text(from raw: String) -> String {
        if let obj = VOAssistantController.jsonObjects(in: raw).last, let t = obj["text"] as? String { return t }
        return VODictationController.stripWrapping(raw)
    }
}
