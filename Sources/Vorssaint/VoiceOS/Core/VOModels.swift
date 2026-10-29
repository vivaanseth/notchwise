// SPDX-License-Identifier: GPL-3.0-or-later
// Ported from VoiceOS Clone (Core/Models.swift) into Vorssaint + VoiceOS.

import Foundation

// MARK: - AI providers

enum VOProviderID: String, CaseIterable, Codable, Identifiable {
    case ollama, claude, chatgpt, gemini

    var isLocal: Bool { self == .ollama }

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ollama: return "Local AI"
        case .claude: return "Claude"
        case .chatgpt: return "ChatGPT"
        case .gemini: return "Gemini"
        }
    }

    var company: String {
        switch self {
        case .ollama: return "Ollama"
        case .claude: return "Anthropic"
        case .chatgpt: return "OpenAI"
        case .gemini: return "Google"
        }
    }

    /// Executable name of the official CLI that carries the user's subscription login.
    var cliName: String {
        switch self {
        case .ollama: return "ollama"
        case .claude: return "claude"
        case .chatgpt: return "codex"
        case .gemini: return "gemini"
        }
    }

    var cliDisplayName: String {
        switch self {
        case .ollama: return "Ollama"
        case .claude: return "Claude Code"
        case .chatgpt: return "Codex CLI"
        case .gemini: return "Gemini CLI"
        }
    }

    var planName: String {
        switch self {
        case .ollama: return "free models on this Mac"
        case .claude: return "Claude Pro / Max"
        case .chatgpt: return "ChatGPT Plus / Pro"
        case .gemini: return "Google account / AI Pro"
        }
    }

    /// Command opened in VOTerminal so the user can sign in with their subscription.
    var loginCommand: String {
        switch self {
        case .ollama: return "open -a Ollama"
        case .claude: return "claude auth login"
        case .chatgpt: return "codex login"
        case .gemini: return "gemini"
        }
    }

    var installCommand: String {
        switch self {
        case .ollama: return "brew install --cask ollama"
        case .claude: return "curl -fsSL https://claude.ai/install.sh | bash"
        case .chatgpt: return "npm install -g @openai/codex"
        case .gemini: return "brew install gemini-cli"
        }
    }

    var apiKeyPlaceholder: String {
        switch self {
        case .ollama: return ""
        case .claude: return "sk-ant-..."
        case .chatgpt: return "sk-..."
        case .gemini: return "AIza..."
        }
    }

    var apiKeyHelpURL: URL {
        switch self {
        case .ollama: return URL(string: "https://ollama.com/library")!
        case .claude: return URL(string: "https://console.anthropic.com/settings/keys")!
        case .chatgpt: return URL(string: "https://platform.openai.com/api-keys")!
        case .gemini: return URL(string: "https://aistudio.google.com/apikey")!
        }
    }

    /// Model choices offered in the UI for subscription (CLI) mode. Empty id = CLI default.
    var cliModels: [VOModelOption] {
        switch self {
        case .ollama: return VOLocalModelCatalog.recommended.map { VOModelOption($0.name, $0.name) }
        case .claude:
            return [VOModelOption("", "Default"), VOModelOption("haiku", "Haiku · fastest"),
                    VOModelOption("sonnet", "Sonnet · balanced"), VOModelOption("opus", "Opus · smartest")]
        case .chatgpt:
            return [VOModelOption("", "Default (from ~/.codex/config.toml)"), VOModelOption("gpt-6-astra", "GPT-6 Astra"),
                    VOModelOption("gpt-5.5", "GPT-5.5"), VOModelOption("gpt-5", "GPT-5")]
        case .gemini:
            return [VOModelOption("", "Default"), VOModelOption("gemini-2.5-flash", "Gemini 2.5 Flash · fast"),
                    VOModelOption("gemini-3-flash-preview", "Gemini 3 Flash"), VOModelOption("gemini-3.5-flash", "Gemini 3.5 Flash"),
                    VOModelOption("gemini-2.5-pro", "Gemini 2.5 Pro"), VOModelOption("gemini-3.1-pro-preview", "Gemini 3.1 Pro")]
        }
    }

    var apiModels: [VOModelOption] {
        switch self {
        case .ollama: return []
        case .claude:
            return [VOModelOption("claude-haiku-5-5", "Claude Haiku 5.5"), VOModelOption("claude-sonnet-5-5", "Claude Sonnet 5.5"),
                    VOModelOption("claude-opus-5-5", "Claude Opus 5.5")]
        case .chatgpt:
            return [VOModelOption("gpt-5-mini", "GPT-5 mini"), VOModelOption("gpt-5", "GPT-5"), VOModelOption("gpt-4.1-mini", "GPT-4.1 mini")]
        case .gemini:
            return [VOModelOption("gemini-2.5-flash", "Gemini 2.5 Flash"), VOModelOption("gemini-3-flash-preview", "Gemini 3 Flash"),
                    VOModelOption("gemini-2.5-pro", "Gemini 2.5 Pro")]
        }
    }
}

struct VOModelOption: Hashable, Identifiable {
    let id: String
    let label: String
    init(_ id: String, _ label: String) { self.id = id; self.label = label }
}

enum VOConnectionMode: String, Codable, CaseIterable, Identifiable {
    case subscription, apiKey
    var id: String { rawValue }
    var label: String { self == .subscription ? "Subscription" : "API key" }
}

/// Which brain cleans up dictation. `.local` is rule-based cleanup only; `.ollama` is a local model.
/// Neither leaves the Mac.
enum VOPolishEngine: String, Codable, CaseIterable, Identifiable {
    case local, ollama, claude, chatgpt, gemini
    var id: String { rawValue }
    var provider: VOProviderID? { VOProviderID(rawValue: rawValue) }
    var label: String {
        switch self {
        case .local: return "Basic (no AI)"
        case .ollama: return "Local AI"
        case .claude: return "Claude"
        case .chatgpt: return "ChatGPT"
        case .gemini: return "Gemini"
        }
    }
}

// MARK: - Speech

enum VOSpeechEngine: String, Codable, CaseIterable, Identifiable {
    case apple, whisper
    var id: String { rawValue }
    var label: String { self == .apple ? "Apple on-device" : "Whisper (local)" }
    var detail: String {
        self == .apple
            ? "Streams as you talk. Runs offline on this Mac."
            : "whisper.cpp on this Mac. Words appear as you talk, and it knows names far better."
    }
}

enum VOWhisperModel: String, CaseIterable, Identifiable, Codable {
    case tinyEn = "tiny.en", baseEn = "base.en", smallEn = "small.en", base = "base", small = "small"
    var id: String { rawValue }
    var fileName: String { "ggml-\(rawValue).bin" }
    var sizeLabel: String {
        switch self {
        case .tinyEn: return "75 MB"
        case .baseEn, .base: return "142 MB"
        case .smallEn, .small: return "466 MB"
        }
    }
    var label: String {
        switch self {
        case .tinyEn: return "Tiny (English)"
        case .baseEn: return "Base (English)"
        case .smallEn: return "Small (English)"
        case .base: return "Base (multilingual)"
        case .small: return "Small (multilingual)"
        }
    }
    var downloadURL: URL { URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(fileName)")! }
}

// MARK: - Shortcuts

enum VODictationTrigger: String, Codable, CaseIterable, Identifiable {
    case fn, rightOption, rightControl
    var id: String { rawValue }
    var label: String {
        switch self {
        case .fn: return "fn"
        case .rightOption: return "right ⌥"
        case .rightControl: return "right ⌃"
        }
    }
}

enum VOAssistantTrigger: String, Codable, CaseIterable, Identifiable {
    case rightCommand, leftCommand, eitherCommand, rightOption
    var id: String { rawValue }
    var label: String {
        switch self {
        case .rightCommand: return "right ⌘"
        case .leftCommand: return "left ⌘"
        case .eitherCommand: return "either ⌘"
        case .rightOption: return "right ⌥"
        }
    }
    var keycap: String {
        switch self {
        case .rightOption: return "option"
        default: return "command"
        }
    }
}

enum VOVoiceSpeed: String, Codable, CaseIterable, Identifiable {
    case slow, normal, fast
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var rate: Float {
        switch self {
        case .slow: return 0.44
        case .normal: return 0.5
        case .fast: return 0.57
        }
    }
}

struct VODictionaryEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var spoken: String
    var written: String
}

// MARK: - Agent actions that can be switched on/off

enum VOAssistantCapability: String, CaseIterable, Identifiable, Codable {
    case pointAndAsk, createPrompt, editSelection, reminders, messages, email, calendar, notes, webSearch, findFiles, openApps, shortcuts, claudeCode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pointAndAsk: return "Point and ask about your screen"
        case .createPrompt: return "Create prompt"
        case .editSelection: return "Edit selected text"
        case .reminders: return "Set reminders"
        case .messages: return "Send messages"
        case .email: return "Send emails"
        case .calendar: return "Schedule events"
        case .notes: return "Take notes"
        case .webSearch: return "Search the web"
        case .findFiles: return "Find files"
        case .openApps: return "Open apps & links"
        case .shortcuts: return "Run Shortcuts"
        case .claudeCode: return "Start coding tasks"
        }
    }

    var subtitle: String {
        switch self {
        case .pointAndAsk: return "Point your cursor at anything on screen and ask about it."
        case .createPrompt: return "Turn a rambling thought into a clean prompt for any AI tool."
        case .editSelection: return "Rewrite, translate, or fix highlighted text by voice."
        case .reminders: return "Remind you at a time you pick (e.g. \"remind me at 5\")."
        case .messages: return "Draft and send iMessages to your contacts."
        case .email: return "Write and send email through Apple Mail."
        case .calendar: return "Put meetings and events on your calendar."
        case .notes: return "Save notes straight into Apple Notes."
        case .webSearch: return "Look things up without leaving what you're doing."
        case .findFiles: return "Find that PDF, deck, or screenshot with Spotlight."
        case .openApps: return "Open any app, website, or folder by name."
        case .shortcuts: return "Trigger your Shortcuts automations by voice."
        case .claudeCode: return "Hand coding tasks to Claude Code in Terminal."
        }
    }

    var symbol: String {
        switch self {
        case .pointAndAsk: return "cursorarrow.rays"
        case .createPrompt: return "text.badge.plus"
        case .editSelection: return "text.alignleft"
        case .reminders: return "clock"
        case .messages: return "message"
        case .email: return "envelope"
        case .calendar: return "calendar"
        case .notes: return "note.text"
        case .webSearch: return "globe"
        case .findFiles: return "doc.text.magnifyingglass"
        case .openApps: return "square.grid.2x2"
        case .shortcuts: return "square.stack.3d.up"
        case .claudeCode: return "chevron.left.forwardslash.chevron.right"
        }
    }
}

// MARK: - History

enum VOSessionMode: String, Codable, CaseIterable {
    case dictation, edit, agent
    var label: String {
        switch self {
        case .dictation: return "Dictation Mode"
        case .edit: return "Edit Mode"
        case .agent: return "Assistant Mode"
        }
    }
}

struct VOHistoryItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var date = Date()
    var mode: VOSessionMode
    var appName: String
    var bundleID: String?
    var transcript: String
    var output: String
    var provider: String?
    var duration: Double
    var words: Int
    var polished: Bool
    var error: String?
}

// MARK: - Errors

struct VOError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}


// MARK: - Local models

struct VOLocalModelInfo: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let size: String
    let note: String
}

enum VOLocalModelCatalog {
    /// Small models that run acceptably on an 8 GB Intel Mac (CPU only), best first.
    static let recommended: [VOLocalModelInfo] = [
        VOLocalModelInfo(name: "qwen2.5:1.5b", size: "1.0 GB", note: "Recommended · good at JSON and cleanup, ~10 tokens/s on an i5"),
        VOLocalModelInfo(name: "gemma3:1b", size: "0.8 GB", note: "Fastest · fine for dictation, weaker at actions"),
        VOLocalModelInfo(name: "llama3.2:3b", size: "2.0 GB", note: "Smarter · slower, needs ~3 GB free RAM"),
        VOLocalModelInfo(name: "qwen2.5:3b", size: "1.9 GB", note: "Smarter actions · slower, needs ~3 GB free RAM"),
    ]
}
