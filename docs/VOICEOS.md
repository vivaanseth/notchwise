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

- **Hover opens home, a click opens what fits.** The combined app starts on "Expand on hover"
  (set once; Settings → Dynamic Island → Behavior changes it). Resting the pointer on the closed
  island opens the home page, the dashboard, without taking the keyboard, and leaving closes it
  again. A click (or ⌃⌥⌘I) opens what the closed island shows first: a song (Spotify, Netflix in
  a browser), a timer, the agents at work. With nothing showing, it opens on the page that
  clearly fits the moment: AI agents with Claude, Terminal or a code editor in front, the player
  with a music app, Calendar just before an event, a page picked a few minutes ago. When nothing
  clearly leads, a near tie included, it opens the home page as a hover does.
  `NotchService.reopeningDestination` → `NotchIntentService.fittingPage`; Settings → Suggestions
  → "Open on the page that fits" turns that step off.
- **No accidental opens.** A hover opens the island only when the pointer comes to rest on it
  (`NotchHoverIntent`: under 5 points of drift over the last 0.2 s) with no mouse button held,
  after the activation time, which the combined app sets to 0.45 s. A pointer still crossing it,
  on its way along the menu bar for instance, starts a fresh wait instead. A click before the
  wait ends opens the page that fits; closing the island under the pointer keeps it closed until
  the pointer leaves.
- **Leaving closes it.** An island opened by the pointer, by hover or by a click on it, closes
  when the pointer leaves, after the close delay, unless something typed in it is still there
  (the assistant's field, Scratchpad, a search). One opened by a shortcut or the assistant's key
  waits for a click away, as before.
- **Full screen.** The combined app turns on "Hide in full screen" once: while a full-screen app
  covers a display, the island leaves that display (on one without a camera notch it is gone
  entirely) and comes back with the desktop. The assistant's key still opens it there.
- **Home.** The assistant's page, before anything is asked, is the island's home
  (`NotchHubView`): under the field, a calendar card (the date and the next three events,
  "In 8 min" on one about to start, each a click from its place on the Calendar page), a small
  camera mirror that starts on a click and stops when the home closes, six colour-coded quick
  controls (screenshot, recording, Keep Awake, microphone mute, Scratchpad, Command Bar; lit
  while on), and the song playing, tinted by its cover, with previous, play/pause and next.
  With text selected in the app in front it offers Summarize, Explain and Improve. Listening or
  answering, the home steps aside for the conversation.
- **Every control.** The Controls page has a tile for each of the menu panel's controls the
  island had no way to: **Fan Control** (with the fans' speed on it, lit while the app holds them
  up; it opens the fan card), **Quick Toggles**, **Features** (the panel's switches for the app's
  own features) and **Wallpaper**, each opening that panel section inside the island, and **All
  controls**, the whole panel with its tabs for every section (Keep Awake, Brightness, Sound,
  System, Network, Disk, Power, Fans, Utilities, Features, Toggles, Wallpaper). The combined app
  shows All controls once (`MergedSettingsImport.showAllControlsOnce`); the rest show on their own
  when their feature is installed. Fan Control and Quick Toggles are on the home's quick controls
  too, and any of them can be a button around the island (Settings → Dynamic Island → Layout).
- **Page switcher.** The home's top row holds every page as a coloured icon; a dot marks the
  ones the moment suggests. Beside a physical camera, where fewer fit, the last one opens the
  sections.
- **Buttons around the island.** Two new kinds of button: **Home** (the house, back to the
  dashboard from any page) and **Suggested**, which shows and opens the likeliest page that is
  neither on screen nor a button already, in that page's colour with a spark. The combined app
  starts with Home, All pages and AI agents on the left; Suggested, Timer and Mixer on the
  right; Music, Notifications and Clipboard below (set once; Settings → Dynamic Island → Layout
  changes them). Settings stays on the island's right-click menu and ⌘,.
- **Live equalizer.** The music bars follow the playing app's sound (Vorssaint's live
  equalizer, now on in the combined app): a private Core Audio tap on the player and its helper
  processes, read only while it plays. macOS asks once for permission to record other apps'
  audio; without it, the bars keep their animation.
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

## Lil Guy, the island's character

Vorssaint's robot companion is gone; in its place is Lil Guy, the character from the
`LilGuyFaces` package (an ESP32 project's eyes on a round black screen). His C++ face engine is
vendored in `Sources/LilGuyFace` and built by `build.sh` into a static library the app links;
Swift drives it through a small C interface (`LilGuyFace.h`) and shows his face in a layer
(`LilGuyFace.swift`). The black of his screen is clear, so he sits on the island's own black.

- **Where he lives.** Everywhere the companion did: resting in the closed island's wing, walking
  through on visits, coming out over an activity to react, and in its Settings preview. The
  robot's hops, squashes and strolls carry him; his own engine blinks, glances, follows the
  pointer and dozes off after a long rest. Settings → Companion keeps its behaviour options; the
  robot's styles, shapes and colours are gone.
- **What he does.** The island's moments play his measured clips and states: a finished task or
  download celebrates with sparkles, charging or petting him brings floating hearts, a timer
  ending startles him, a screenshot is a long blink, a failure makes him dizzy, unlocking wakes
  him, Keep Awake makes him yawn or go wide-eyed, an event starting pulses bolts in his pupils,
  a timer starting gets a smug blink and music a smiling streak.
- **The assistant's face.** He replaces the VoiceOS mark in the island: in the assistant page's
  top row, in the closed island's strip while it works, and in "Ask VoiceOS" under the pointer.
  He listens, looks up while it thinks, squints while an action runs, then smiles with a
  sparkle when it answers or goes red-eyed when it fails.
- **The open island.** He sits in the top row of every page and reacts to each page he sees:
  hearts on the player while a song plays, bolts in his pupils on Calendar before an event,
  sweat on System while the processor is busy, a squint on Captures, thinking dots on Agents, a
  smug blink on Timer, wide eyes at the camera. Holding him pets him (hearts).
- **Big.** Asked something out loud, he comes out of his corner at four times the size to
  listen, swelling a little with your voice, and goes back once the answer shows. A click on his
  face in any page's top row opens **his room** (`LilGuyRoom.swift`): Lil Guy as big as the page
  allows, in a softly breathing light, his eyes following the pointer around him, with Pet,
  Tickle, Wink, Spin, Nap or Wake up, and Surprise me (any of his clips, sometimes mirrored).
  There a click pokes him (a giggle, now and then a wink), four quick ones make him dizzy, and
  holding him pets him. Escape, the way back, or another page puts him back.
- **The screen.** While he is on screen (`LilGuyDirector`): his eyes follow the pointer around
  him; an app coming forward gets a glance that fits it (a call, music,
  code, writing, Finder, a browser); a copy gets a quick blink; a busy processor makes him sweat
  and then cool off; a low battery makes him sad or worried; after 11 pm his fidgets turn
  sleepy; five minutes with nobody at the Mac and he sleeps, waking with a peek, or a startle
  after a long time away. Every minute or two he fidgets from about twenty idle clips.
- **Variety.** Joy, love, anger, sadness, startles, dizziness, waking, yawns and perks each draw
  from a set of clips. 62 of the 66 clips are used; the rest are holds and exit transitions.
- **Cost.** He draws only when his face changes: between blinks and glances the engine says
  when he next moves and nothing runs until then. Moving, a frame is about 1.5 ms on this Mac;
  out of sight he stops.

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

Changed in the combined app:

- **Lookups are searches.** "Find Keshav's LinkedIn", "look up…", "search for…", "google…" and
  "pull up… on YouTube" skip the model and open the search at once (LinkedIn's people search,
  YouTube's results or a web search), so nothing is claimed that was never looked up
  (`VOBrainRouter.lookup`). A lookup about someone on screen ("find his LinkedIn") still goes
  to the model and the screen. The local prompt also says it cannot browse and must search.
- **People land on their profile.** "Find Keshav Arun on LinkedIn" (GitHub, Instagram and X
  too) asks Bing's plain results page for the name and the site, and opens the first profile
  there whose title or address carries every word of the name, with up to three others listed
  as links and LinkedIn's own search beside them (`VOWebLookup`). With no such profile, or no
  answer within 5 s, it opens the site's people search as before. Only the name and the site's
  name go to Bing, as a typed search would. `VOICEOS_NO_MODELS=1` runs the dry-run self-test on
  lookups without starting a local model.
- **Spoken as it's written.** Each sentence of an answer goes to the voice as soon as it is
  complete, while the model still writes the rest and its actions
  (`VOAssistantVoice.stream`/`finishStream`); the words still light up as they're said.
- **Names heard right.** Apple's recognizer gets the names in Contacts (when the app may read
  them) and the dictionary as hints. With Whisper on this Mac (`whisper-cli` and a model,
  VoiceOS's own or one MacWhisper downloaded), the words still appear live from Apple's
  recognizer, and Whisper hears the recording again, with the same names as its prompt, for the
  final text (Dictation → Speech recognition → "Check with Whisper"; on by default).
- **Whisper instead of Apple.** Where `whisper-cli` and a Whisper model are installed, Whisper
  (whisper.cpp) is the speech engine by default, for dictation and the assistant alike;
  Dictation → Speech recognition switches back to Apple. Its words appear as you talk: while the
  key is held it hears the recording so far again whenever half a second more has come in with
  speech in it, so a pause before letting go gets one pass and none over the silence after; the
  last pass, if it heard all the speech, is the final text at once. The model stays
  loaded in whisper.cpp's own server (`VOWhisperServer`: `whisper-server` on 127.0.0.1, a
  random port, six threads, no text carried from one pass to the next), which stops after ten
  idle minutes and with the app. Whisper reads its full thirty-second window on every pass: a
  window the recording's size is several times faster but makes the base model loop on made-up
  words for up to forty seconds about one pass in four. On this Mac (a 2019 i5) the base model
  takes about three seconds a pass, so the live words come in steps that far apart, and the
  final text up to a pass after the key is let go; a smaller model (Tiny, in the model list) is
  faster and a little less exact. Live passes decode once, greedily; the final one may retry
  warmer. A recording that never reached speech level gives no text, so Whisper's made-up
  "Thank you." over silence never lands. MacWhisper's models count as installed in the model
  list. The self-test takes `VOICEOS_TEST_AUDIO` (a 16 kHz mono WAV) and logs each pass.

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
