// SPDX-License-Identifier: GPL-3.0-or-later
// Ported from VoiceOS Clone (Dictation/TextCleaner.swift) into Vorssaint + VoiceOS.

import Foundation

/// Fast on-device cleanup that runs on every dictation, before (or instead of) AI polish.
enum VOTextCleaner {
    private static let fillerPattern = #"(?i)(^|[\s,])(?:um+|uh+|uhm+|erm+|er|ah+|hmm+|mm+|you know,)(?=[\s,.!?]|$)[,]?"#

    static func clean(_ raw: String, dictionary: [VODictionaryEntry], removeFillers: Bool) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return s }

        if removeFillers {
            s = s.replacingOccurrences(of: fillerPattern, with: "$1", options: .regularExpression)
            // Immediate word repeats: "the the" → "the"
            s = s.replacingOccurrences(of: #"(?i)\b(\w+)(\s+\1\b)+"#, with: "$1", options: .regularExpression)
        }

        // Spoken formatting commands.
        s = s.replacingOccurrences(of: #"(?i)\s*\bnew paragraph\b[,.]?\s*"#, with: "\n\n", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)\s*\bnew line\b[,.]?\s*"#, with: "\n", options: .regularExpression)

        s = applyDictionary(s, dictionary)

        // Tidy whitespace and punctuation spacing.
        s = s.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+([,.!?;:])"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"^[,.\s]+"#, with: "", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)

        if let first = s.first, first.isLowercase {
            s = first.uppercased() + s.dropFirst()
        }
        return s
    }

    static func applyDictionary(_ text: String, _ dictionary: [VODictionaryEntry]) -> String {
        var s = text
        for entry in dictionary where !entry.spoken.isEmpty {
            let escaped = NSRegularExpression.escapedPattern(for: entry.spoken)
            let template = NSRegularExpression.escapedTemplate(for: entry.written)
            s = s.replacingOccurrences(of: "(?i)\\b\(escaped)\\b", with: template, options: .regularExpression)
        }
        return s
    }

    static func wordCount(_ s: String) -> Int {
        s.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }
}

/// How dictated text should be shaped for the app it lands in.
enum VOAppStyle {
    case email, chat, notes, code, document, general

    static func detect(bundleID: String?, appName: String, windowTitle: String?) -> VOAppStyle {
        let b = (bundleID ?? "").lowercased()
        let title = (windowTitle ?? "").lowercased()
        if b.contains("com.apple.mail") || b.contains("outlook") || b.contains("superhuman") || b.contains("spark")
            || title.contains("gmail") || title.contains("inbox") || title.contains("outlook") { return .email }
        if b.contains("mobilesms") || b.contains("slack") || b.contains("discord") || b.contains("whatsapp")
            || b.contains("telegram") || b.contains("messenger") || b.contains("signal") || title.contains("slack") { return .chat }
        if b.contains("notes") || b.contains("notion") || b.contains("obsidian") || b.contains("bear") || b.contains("craft")
            || b.contains("reminders") { return .notes }
        if b.contains("vscode") || b.contains("cursor") || b.contains("xcode") || b.contains("terminal") || b.contains("iterm")
            || b.contains("jetbrains") || b.contains("zed") || b.contains("warp") || b.contains("ghostty") || b.contains("claude") { return .code }
        if b.contains("pages") || b.contains("word") || title.contains("google docs") { return .document }
        return .general
    }

    func instruction(firstName: String) -> String {
        switch self {
        case .email:
            return "The text goes into an email. Format it as a ready-to-send email body: a greeting line if the user addressed someone, short paragraphs, and a sign-off" + (firstName.isEmpty ? "." : " with the name \(firstName).") + " Do not invent a subject line."
        case .chat:
            return "The text goes into a chat message. Keep it short and casual like a real text: no greeting or sign-off, lowercase is fine, minimal punctuation, no trailing period."
        case .notes:
            return "The text goes into a notes app. If the user lists several items or tasks, format them as a '- ' bulleted list; otherwise clean sentences."
        case .code:
            return "The text goes into a code editor, terminal, or AI coding prompt. Keep technical terms, file names, identifiers and CLI flags exact; write a clear, precise prompt or comment."
        case .document:
            return "The text goes into a document. Write polished, well-punctuated prose with paragraphs."
        case .general:
            return "Write clean, natural, well-punctuated text."
        }
    }
}
