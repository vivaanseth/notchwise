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

## Getting around the island

- **Opening on the page that fits.** A click (or ⌃⌥⌘I) opens what the closed island shows
  first, as before: a song, a timer, the agents at work. With nothing showing, it opens on the
  page that clearly fits the moment: AI agents with Claude, Terminal or a code editor in front,
  the player with a music app, Calendar just before an event, a page picked a few minutes ago.
  When nothing clearly leads, a near tie included, it opens on the home page.
  `NotchService.reopeningDestination` → `NotchIntentService.fittingPage`. Settings → Dynamic
  Island → Behavior → Suggestions → "Open on the page that fits" turns it off.
- **Home.** The assistant's page, before anything is asked, is the island's home
  (`NotchHubView`): under the field, a calendar card (the date and the next three events,
  "In 8 min" on one about to start, each a click from its place on the Calendar page), a small
  camera mirror that starts on a click and stops when the home closes, six colour-coded quick
  controls (screenshot, recording, Keep Awake, microphone mute, Scratchpad, Command Bar; lit
  while on), and the song playing, tinted by its cover, with previous, play/pause and next.
  With text selected in the app in front it offers Summarize, Explain and Improve. Listening or
  answering, the home steps aside for the conversation.
- **Page switcher.** The home's top row holds every page as a coloured icon; a dot marks the
  ones the moment suggests. Beside a physical camera, where fewer fit, the last one opens the
  sections. The buttons around the island (Settings → Dynamic Island → Layout) are unchanged.
- **Swipe.** Two fingers sideways on an open page, away from its own scrolling lists, turn to the
  next or previous page in the sections' order; on the player they still skip tracks.
- **Hover dock.** With "Preview on hover" chosen, the pointer resting on the closed island grows
  it into a dock of every page, the likeliest first (`NotchHubPeek`). The combined app opens on
  a click, as Vorssaint does.
- **Suggestions** (`NotchIntentSupport.swift`, `NotchIntentService.swift`). A small naive Bayes
  model learns which page is opened in which moment: the app in front (bundle id), the kind of
  window it shows (one word, *meeting*, *media*, *code* or *writing*, read from the title,
  which is never stored), the part of the day and weekday or weekend. A page counts as chosen
  once it stays open 1.5 s; pages the island opened on by itself teach nothing. Until it has
  learned about eight choices, it leans on built-in pairings of kinds of apps with pages (a
  browser with Clipboard and Downloads, a code editor with AI agents usage and Scratchpad, a
  call with Camera and Mixer). On top, what's going on right now counts: a song playing, a
  running timer, an event within 15 minutes, a download, working agents, and, as hints only, a
  copy in the last 90 s or a capture in the last 3 minutes (only their times are read, never
  their contents). Counts fade with each new choice. The model is a few kilobytes in the app's
  preferences; Settings → Suggestions turns learning off or forgets it. It runs no screen
  capture and loads no second AI model.

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
- **Menu bar**: one item, Vorssaint's. VoiceOS's menu (open, ask, provider and cleanup switches, history, settings) is its VoiceOS submenu, on a secondary click.

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
Tools/voiceos-harness.sh snapshot /tmp/shots # island states, hover dock, pill, VoiceOS settings pages
Tools/voiceos-harness.sh selftest /tmp/st.txt
```

The harness runs a copy with a throwaway bundle id and only the island, the assistant and the
settings window: no Vorssaint system features, global hotkeys or menu bar items, and actions are
never executed. Snapshots draw the app's own views, so they need no Screen Recording permission,
and they load no Ollama model and start no Claude session; the self-test does both.

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
