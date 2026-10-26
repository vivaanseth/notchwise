# Vorssaint + VoiceOS

This tree is Vorssaint 3.4.2 (with the two Intel commits: Intel build, sensors and updates
off; Intel DDC brightness) with the VoiceOS Clone voice assistant built in. It builds one app,
**Vorssaint + VoiceOS** (`com.vorssaint.voiceos`), that installs next to the standalone
Vorssaint instead of replacing it.

## What is where

| | |
|---|---|
| Vorssaint (everything outside the island) | unchanged, `Sources/Vorssaint/…` |
| VoiceOS sources | `Sources/Vorssaint/VoiceOS/` (AI, Assistant, Core, Dictation, Speech, System, UI, App) |
| Startup | `VORuntime` starts the hotkeys, the dictation pill, the VoiceOS menu bar item and the local-AI warm-up behind the **Voice Assistant** feature (`AppFeature.voiceAssistant`, Dynamic Island group in the Features hub) |
| Island bridge | `VOIsland` (assistant → island) and `VOIslandBridge` (island → assistant) in `VoiceOS/UI/Island/VOIsland.swift` |
| Settings | the **VoiceOS** section of Vorssaint's Settings sidebar: Dashboard, Insights, History, Dictation, Assistant, Apps (`SettingsPage.voiceOS(VOPage)`) |
| First launch | `MergedSettingsImport` copies the standalone apps' preferences once |

Every VoiceOS type carries a `VO` prefix (`VOSettings`, `VOTheme`, `VOStorage`, `VOPermissions`,
`VOSounds`, `VOTerminal`, `VORouter`…), and the voice agent's types are *Assistant*
(`VOAssistantController`, `VOAssistantTurn`…), since Vorssaint's *Agents* already means
coding-agent usage. VoiceOS's own source files are prefixed the same way, because `swiftc`
refuses two files with one name. VoiceOS preferences live under `voiceos.` keys in the app's
preferences domain; history, usage counters and Whisper models stay in
`~/Library/Application Support/VoiceOS Clone/`, and API keys in the keychain item VoiceOS used.

## One island

There is one island window, Vorssaint's (`NotchService` / `NotchWindowHost` / `NotchView`).
VoiceOS's own notch window is gone; its look and behaviour live in that island:

- **The assistant is the island's home page** (`NotchModule.voice`, first in the page order,
  ⌥⌘J inside the island). The first launch sets Vorssaint's own "return home" choice to it, so a
  click on the idle island or ⌃⌥⌘I opens it, ready for typing after a click; another home page
  or "restore the last page" can be chosen in the Dynamic Island settings. Its page is VoiceOS's open notch: 620 points wide,
  as tall as the conversation, with the Jarvis mark, new conversation and close in the island's
  top row, the turns with the spoken-word highlight, the Markdown detail, the action and
  confirmation cards (Send / Edit / ✕), the "via" caption, and "Type or hold ⌘ to speak". The
  island's background takes VoiceOS's blue fade on that page.
- **Priority.** Holding the assistant's key takes the island over from any page. While the
  assistant listens, transcribes, thinks or waits on a confirmation, a click away, the pointer
  leaving and another app coming forward don't close it, and an answer with something to
  confirm brings its page back. With its page closed, the assistant at work is the closed
  island's first live activity (`NotchCompactActivity.voice`): the Jarvis mark with the level,
  the thinking dots, the speaking wave or a confirm mark. A click opens the page.
- **Idle notch.** On a display without a camera the island hangs from the top edge as a black
  notch (the combined app starts with that shape; Vorssaint's capsule is still a choice in the
  island's settings). Under the pointer it grows and says "Ask VoiceOS". VoiceOS's "Show notch
  when idle" (Dashboard → profile menu) hides the idle island; activities and notices still show.
- **Keyboard.** The island takes the keyboard only while typing, and hands it back to the app
  that was in front before the assistant pastes or types there.
- All of Vorssaint's 16 pages, its compact strips, notices and HUDs are unchanged, a click on
  the sections button away. Calls other features make into the island (HUDs, captures, shelf
  drops, Command Bar, companion) are untouched.

## Conflicts and how they were resolved

- **Super Key** (right ⌘, ⌥, ⌃ or ⇧ when not Caps Lock): Super Key keeps its key. VoiceOS stands
  down on that key (`VOHotkeyConflicts`) and says so beside its key choice. Other VoiceOS keys,
  such as left ⌘ or fn, keep working.
- **Escape**: VoiceOS acts on it only while dictation runs or its page is open. When the island
  holds the keyboard, the island's own Escape closes it.
- **Mic Mute**: with Vorssaint's Mic Mute on, dictation and the assistant say the microphone is
  muted instead of listening to silence.
- **Full screen**: the idle island follows Vorssaint's full-screen setting; the assistant's key
  still opens the island over a full-screen app, and the dictation pill shows there too.
- **Dock, appearance, login item, main menu**: Vorssaint's. VoiceOS's "Launch at login" toggle
  drives Vorssaint's own login item.
- **Info.plist**: VoiceOS's Microphone, Speech Recognition, AppleEvents, Calendars, Reminders
  and Contacts strings are merged into Vorssaint's; Contacts is added to the entitlements.
- **Menu bar**: the VoiceOS menu bar item (▼●) stays, with its provider and cleanup switches.

## AI

Unchanged from VoiceOS: Ollama `qwen2.5:1.5b` by default for dictation, edits and the
assistant (one shared system prompt, strict JSON schema, action filtering, arithmetic in code,
dates from the system's date detector); Claude only for screen questions, long writing or
analysis, very long selections or when the local model asks, then Haiku with thinking off and a
daily cap (25). CodexBar plan checks only run when you open Apps or Insights. On an 8 GB Mac,
keep one local model for both jobs.

## First launch

The combined app copies the standalone Vorssaint's preferences (`com.vorssaint.utils`) and
VoiceOS Clone's (`com.local.voiceos-clone`) once. It skips what belongs to the standalone
install: the fan helper's registration, a sleep setting Vorssaint must restore itself, and its
login item. Run only one of the apps at a time: two would draw two islands and register the
same shortcuts. macOS asks again for Accessibility, Microphone, Speech Recognition and the
rest, since the combined app has its own identity.

## Building and checking

```sh
./build.sh                                   # build/stage/Vorssaint + VoiceOS.app
./build.sh --test                            # the test suite (about 25 min on an i5)
Tools/voiceos-harness.sh snapshot /tmp/shots # island states, pill, VoiceOS settings pages
Tools/voiceos-harness.sh selftest /tmp/st.txt
```

The harness runs a copy with a throwaway bundle id and only the island, the assistant and the
settings window: no Vorssaint system features, global hotkeys or menu bar items, and actions are
never executed. Snapshots draw the app's own views, so they need no Screen Recording permission.

## Verified, and still to check by hand

Checked on the Intel i5 (macOS 14.7.7) with the harness, dry run:

- Snapshots: the assistant's page empty, listening and in a conversation (turns, spoken-word
  highlight, Markdown detail, Send / Edit / ✕ card, fade), the voice strip on the closed island,
  Vorssaint's Controls page and sections gallery (Assistant first, ⌥⌘J), the dictation pill and
  the six VoiceOS pages in Settings.
- Self-test: dictation cleanup on `qwen2.5:1.5b`; a reminder with arithmetic, "Open Spotify"
  and "Text Maya" answered locally; the long proposal escalated to Claude Haiku ("long
  writing"). No action ran.

Not checkable without you: the physical fn / right-⌘ holds, microphone capture, pasting into
other apps, hover and clicks on the idle island, and the Accessibility, Microphone, Speech and
Automation prompts the new identity asks for.
