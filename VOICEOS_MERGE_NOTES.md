# VoiceOS Clone → merge notes (for the Vorssaint + VoiceOS app)

Written by the VoiceOS Clone session on 2026-10-25. These notes cover the VoiceOS side. The Vorssaint session writes its own notes.

## Goal of the merge
- **One app.** Vorssaint is the base app: all of its non-island features stay as they are.
- **One island.** The VoiceOS notch becomes the single island, and Vorssaint's island features (music, lyrics, queue, mixer, files, clipboard, timers, calendar, agents, camera, capture, downloads, scratchpad, lock screen…) move into it as extra views/modes. Every VoiceOS feature stays.

## Both projects are compatible
| | VoiceOS Clone | Vorssaint (`~/Desktop/Intel Vorssaint/vorssaint-utils`) |
|---|---|---|
| Build | SwiftPM, tools 5.9, macOS 14, Swift 5 mode, x86_64 | SwiftPM, tools 5.9, macOS 14, has systemLibrary targets |
| Entry | `App/main.swift` + `AppDelegate` | `Sources/Vorssaint/main.swift` |
| Island code | `UI/Notch/NotchWindowController.swift`, `UI/Notch/NotchView.swift` | `Sources/Vorssaint/UI/Notch/*.swift` (~25 files) |
| License | personal | **GPL-3.0** (the combined app inherits GPL) |

**Recommended approach:** copy Vorssaint's package as the base, then add the VoiceOS sources under `Sources/Vorssaint/VoiceOS/`. Rename any clashing types (see below). Delete VoiceOS's own `main.swift`/app shell, and start the VoiceOS services from Vorssaint's app startup instead.

## VoiceOS source map (`~/Desktop/VoiceOS Clone/Sources/VoiceOS/`)
- `AI/`
  - `CLIRunner` (clean-env process runner)
  - `AIBackends` (Claude/Codex/Gemini CLI plus API-key backends)
  - `Ollama.swift` (`OllamaBackend`, `LocalModels`)
  - `ClaudeWarmPool`
  - `ProviderManager` (status, sign-in, usage)
  - `Keychain`
- `Agent/`
  - `AgentController` (the notch brain: phases, turns, routing, prompts, JSON parsing)
  - `ActionKit` (Messages/Mail/EventKit/Notes/Spotlight/Shortcuts/Claude Code actions)
  - `LocalPrompts` (one shared Ollama system prompt + JSON schema)
  - `Router.swift` (`BrainRouter`: when to escalate to Claude, action filtering, calculator, date fixes)
- `Dictation/`: `DictationController` (fn-hold dictation, edit-selection mode, polish), `TextCleaner`/`AppStyle`
- `Speech/`: `AudioCapture`, `Transcriber` (Apple on-device / whisper.cpp, `ModelDownloader`), `SpeechVoice` (`AgentVoice` TTS with spoken-word highlight)
- `System/`
  - `HotkeyMonitor` (hold fn = dictation, double-tap = hands-free, hold right ⌘ = agent)
  - `Permissions`
  - `SystemBridge` (`TextInserter`, `Accessibility`, `ScreenGrab`, `Sounds`, `AppIcons`)
- `Core/`: `Models`, `Settings` (`AppSettings`, UserDefaults), `HistoryStore` + `Storage` (`~/Library/Application Support/VoiceOS Clone/`)
- `UI/`
  - `Notch/` (the island)
  - `DictationPill` (bottom waveform pill — not an island, keep as-is)
  - `Main/` (settings window: Dashboard, Insights, History, Dictation, Agent, Apps, Onboarding, `LocalAICard`)
  - `Brand`, `Theme`, `Components`
- `App/`: `AppDelegate`, `Snapshotter` (`VOICEOS_SNAPSHOT`), `SelfTest` (`VOICEOS_SELFTEST`, dry-run actions)

## How the VoiceOS island works (what must survive)
- `NotchWindowController`: a borderless non-activating `NotchPanel` at the top center, one level above the menu bar, on all Spaces.
  - Becomes key only when typing (`focusInput()`); `releaseKeyFocus()` hands focus back before pasting.
  - Resizes to the SwiftUI-reported content height. Shrinking is delayed about 0.45 s so the collapse animation can play.
  - On non-notch Intel screens it draws a fake notch (idle width 190, menu-bar height from `NotchMetrics`).
  - A click outside the panel closes the agent.
- `NotchRootView`:
  - Idle: a black mini-notch that grows on hover; a tap opens the agent.
  - Expanded (620 wide): Jarvis glyph, conversation turns, input row "Type or hold [command] to speak".
  - Turns show the user bubble, the spoken reply with a white/grey word highlight, markdown detail, action/confirmation cards (Send/Edit/✕), and a "via" caption showing which brain answered.
- Driven by `AgentController.shared` (`expanded`, `phase`, `turns`, `hovering`, `focusToken`). Hotkeys come from `AppDelegate.wireHotkeys()`.

## Merging the islands
- Make the island a **mode host**, e.g. `enum IslandMode { idle, agent, music, files, clipboard, timer, … }`. VoiceOS's agent is one mode and should take priority while listening, thinking or confirming.
- Idle/hover strip: show Vorssaint's compact strips (now playing, timer, calendar, agent strips) inside the VoiceOS idle notch. Holding right ⌘ or clicking still opens the agent.
- Expanded: add a mode switcher (tabs or swipe) between Agent and the Vorssaint views. Keep a single `NSPanel`; don't create two island windows.
- Share one window controller and one sizing scheme (use Vorssaint's if it's more complete, but keep the VoiceOS behaviours listed above).
- Name clashes to check:
  - `Theme`, `NotchView`/`NotchShape`/`NotchMetrics`, `Router`, `Storage`, `Permissions`, `Sounds`, `AppSettings`, `MainWindowController`, `Terminal`
  - Vorssaint already has `UI/Theme.swift` and `UI/Notch/*`
  - Prefix the VoiceOS ones (e.g. `VO…`) or put them in a namespace.
- Settings: VoiceOS pages (Dictation, Agent, AI apps, History, Insights) become sections inside Vorssaint's settings window. Keep the VoiceOS dark style for those sections, or adopt Vorssaint's theme.
- Hotkeys: watch for conflicts between VoiceOS (fn, right ⌘, Esc) and Vorssaint's own shortcuts.

## Rules to keep from the VoiceOS work
- **Local-first AI:** Ollama `qwen2.5:1.5b` by default. Claude only when needed (screen questions, long writing/analysis, big selections, or `"escalate": true`), and then Haiku, thinking off (`MAX_THINKING_TOKENS=0` plus `alwaysThinkingEnabled:false`), with a daily cap of 25.
- All local jobs share one Ollama system prompt, because Ollama caches only one prefix.
- Never run CodexBar plan checks at launch; they start heavy CLI sessions.
- Self-tests must use dry-run; never execute actions on the user's Mac.
- This Mac has 8 GB of RAM and swaps heavily. Avoid loading two local models, and keep the warm Claude pool off by default.

## Build and permissions
- Build x86_64; ad-hoc signing resets the Accessibility grant on every rebuild. VoiceOS uses `scripts/build.sh`; Vorssaint has its own `build.sh` (honours `VORSSAINT_ARCH`).
- The user's account isn't an admin, so install to `~/Applications`.
- Info.plist needs the VoiceOS usage strings (Microphone, Speech, AppleEvents, Calendars/Reminders full access, Contacts) merged into Vorssaint's.
- Still unverified with the user: live fn / right-⌘ hotkeys and pasting into other apps. Codex needs `codex login`; Gemini's Google sign-in was never finished.
