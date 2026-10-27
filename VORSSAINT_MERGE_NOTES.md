# Vorssaint (Intel) → merge notes (for the Vorssaint + VoiceOS app)

Written by the Vorssaint Intel session on 2026-10-25. These notes cover the Vorssaint side.
The VoiceOS side is in `VOICEOS_MERGE_NOTES.md` next to this file. Read both before starting.

## Goal, in the user's words
- **One app.** Vorssaint features that don't involve the Dynamic Island stay exactly as they are.
- **One island.** Vorssaint's Dynamic Island features go into the VoiceOS island, and every
  VoiceOS feature stays. VoiceOS's whole purpose is being a Dynamic Island, so the voice agent
  is the island's main job and Vorssaint's island pages are extras inside it.

## The Vorssaint source of truth
- Path: `~/Desktop/Intel Vorssaint/vorssaint-utils/` (a git repo, branch `intel-mac-support`).
- Upstream: github.com/vorssaint/vorssaint-utils at `4f510c0` (v3.4.2), plus 2 local commits:
  - `08e11f1` **Build and run on Intel Macs:**
    - `build.sh` builds for the host CPU (`VORSSAINT_ARCH` overrides it).
    - Intel CPU temperatures come from the `TC…` SMC sensors (`CPUTemperaturePlatform.intel`).
    - Self-update is off on Intel builds (`AppInfo.releasesRunOnThisMac`).
    - `--selftest`/`--sensors` use the same sensor selection as the app.
  - `7a94b63` **Control external monitor brightness over DDC on Intel Macs:** adds
    `Services/Display/IntelDDC.swift`, hooked into `BrightnessService` behind `#if arch(x86_64)`.
  - **Keep both commits in the combined app.** Without them it either won't build for Intel or
    will auto-update itself into an Apple Silicon build that can't launch.
- License: GPL-3.0-or-later. The combined app is GPL too.
- Also in that folder: `README.md` (rebuild steps, verified features), `intel-mac-support.patch`,
  `diagnostics/` (sensor/DDC probe programs, build and test logs).

## How Vorssaint builds (important: not `swift build`)
- `./build.sh` calls `swiftc` directly. `Package.swift` exists but isn't what ships.
  - The app compiles the glob `Sources/Vorssaint/**/*.swift`, so **any new file under
    `Sources/Vorssaint/` is picked up automatically**. Putting VoiceOS code in
    `Sources/Vorssaint/VoiceOS/` needs no build-script change.
  - Separate targets: the fan helper (`Sources/FanControlHelper` + 5 named files) and the Now Playing
    dylib (`Sources/NowPlayingAdapter`, loaded by `/usr/bin/perl` through `Resources/now-playing.pl`).
  - C module maps: `-I Sources/VMStatisticsCompat -I Sources/HIDEventSystem`.
  - The bundle is assembled by hand in `build.sh` (Info.plist, entitlements, LaunchDaemon plist,
    lproj folders, GIFs, images). New VoiceOS resources (whisper models, sounds) need copy lines there.
  - Output: `build/stage/Vorssaint.app`, signed ad-hoc (no signing identity on this Mac).
- `./build.sh --test` compiles an **explicit** `TEST_SOURCES` list (Tests/*.swift plus named app
  files), then runs `./build/metrics-tests`. New testable files must be added to that list.
- Timing on this Mac (i5-8257U, 8 GB RAM): clean release build about 34 min, incremental about 2.5 min,
  full tests about 25 min. Run them in the background.
- **Known baseline test failures:** 15 of 113,909 checks fail before any merge work. Don't treat
  them as regressions:
  - `UpdateFeatureTests:1090` (fd inheritance)
  - `ScreenshotScrollingCaptureTests:178` and `RecorderExportRenderingTests:21` (timing)
  - `NotchTests:1611` ×8 (zh-TW/zh-HK label width)
  - `NotchActivityTests:651`, `:653` (ja)
  - `MediaWorkspaceLayoutTests:59`
  - `NotchCompactTests:302`

## What counts as "the island" (merge these) vs. everything else (don't touch)
**Island code: about 36,600 lines in 91 files, plus settings:**
- `Sources/Vorssaint/Services/Notch/`: 50 files, 21,983 lines (state, window, island services)
- `Sources/Vorssaint/UI/Notch/`: 41 files, 14,646 lines (views)
- `Sources/Vorssaint/UI/Settings/Notch*.swift`: settings for the island (`NotchSettings`, `NotchContentEditor`,
  `NotchLayoutEditor`, `NotchMascotSettings`, `NotchAgentsSettings`, `NotchCalendarSelection`,
  `NotchEditorItem`, `NotchSettingsTabRow`)
- `Sources/Vorssaint/Core/Notch*Strings.swift`: island strings in 13 languages
- `Core/Defaults.swift`: about 320 `notch…` preference keys
- Feature flags in `Core/FeatureCatalog.swift`: `notch`, `notchCalendar`, `notchNotifications`,
  `notchGestures`, `notchTimer`, `notchAccessories`, `notchLyrics`, `notchQueue`, `notchLiveEqualizer`,
  `notchDownloads`, `notchAgents`, `notchWatch`, `notchMascot`
- Tests: 55 `Tests/Notch*Tests.swift` files

**Everything else is "non-island" and should stay unchanged:** menu bar panel, settings window, switcher,
window layout, Dock previews, clipboard history, shelf, screenshots/recorder, mixer, displays/brightness,
keep-awake, system monitor, fan control, command bar, quick launcher, uninstaller, Homebrew, and the rest.

## How Vorssaint's island is built
- **`NotchService`** (`Services/Notch/NotchService.swift`, 5,086 lines): `ObservableObject` singleton with all island state.
  - Key `@Published` state: `expanded`, `selected: NotchModule`, `modules`, `notice`, `pinned`,
    `geometry`, `showingSections`, `hiddenInFullscreen`, `panelIsKey`, and mascot state.
  - Entry points: `open(_:pinned:takeFocus:…)`, `collapse()`, `toggle()`, `toggleFromShortcut()`,
    `hover(_:)`, `openActivity(_:)`, `syncWithPreferences()`, `stop(restoreCapture:)`.
- **`NotchWindowHost`** (`Services/Notch/NotchWindowHost.swift`, 1,803 lines): the window layer. One
  `NotchPanel: NSPanel`, sized as a transparent **stage the size of the largest screen** (`NotchStage`),
  with the island drawn inside on a `NotchCanvas`. It handles:
  - Mission Control frame probing, fullscreen hiding and the menu-bar/overlay spaces
  - file drops and the quick-access container
  - key focus: `canBecomeKey` follows `acceptsKeyFocus`
  - content transitions (`reveal/dismiss/depart/replace`)

  Because of this design, the panel doesn't resize per page the way the VoiceOS panel does.
- **`NotchView`** (`UI/Notch/NotchView.swift`): the SwiftUI root.
  - `surface`: the closed island.
  - `activityStrip(_:)` (around line 231): compact strips on the closed island.
  - `page` (around line 326): the open page, switching on `service.selected` (around lines 466, 570, 601).
  - `NotchShape` draws the outline.
- **Pages** = `enum NotchModule` (`Services/Notch/NotchSupport.swift:9`), 16 cases:
  `controls, mixer, music, clipboard, captures, files, system, tools, calendar, notifications, timer,
  camera, downloads, scratchpad, agents, watch`.
- **Compact activities on the closed island** = `enum NotchCompactActivity` (`NotchSupport.swift:825`):
  `timer, watch, downloads, agents, calendar, music, keepAwake`.
- **Notices/HUD** = `NotchNotice`: volume, brightness, keyboard light, mic, metric alerts,
  notifications, agent events, mascot reactions.
- **No notch on this Mac:** the geometry handles non-notched screens (`NotchGeometry.isNotched == false`)
  and draws its own island. Its `layout`, `customWidth/Height` and `floatingGap/Drop` settings control this.
- Startup: `App/FeatureRuntime.swift` calls `NotchService.shared.syncWithPreferences()` when `notch`
  is available. `AppDelegate` calls `stop(restoreCapture:)` on quit.
- Default island shortcut: **⌃⌥⌘I** (`GlobalShortcut.notchDefault`), plus hover-to-open settings
  (`notchOpenOnHover`, `notchHoverExpands`, `notchHoverDelay`).

## Pages that are really other features' views
Most island pages just show another (non-island) feature, and are on only when that feature is installed
(`NotchSupport.swift`, around lines 60–78):

| Page | Needs feature |
|---|---|
| mixer | `mixer` |
| clipboard | `clipboardHistory` |
| files | `shelf` |
| tools | `quickLauncher` |
| camera | `cameraPreview` |
| scratchpad | `scratchpad` |
| timer | `notchTimer` |
| calendar | `notchCalendar` |
| notifications | `notchNotifications` |
| downloads | `notchDownloads` |
| agents | `notchAgents` |
| watch | `notchWatch` |

Those features also **call into the island**. These calls are how "non-island features stay unchanged"
holds, so every one must keep working against the merged island:
- the volume/brightness/keyboard-light/mic HUD:
  - `showVolume`, `showCurrentVolume`, `showBrightness`, `showKeyboardLight`
  - `showMicrophone`, `retractMicrophoneNotice`
  - `acceptsSystemFeedback`, `showsSystemFeedback`
- the shelf and command bar:
  - `fileDragChanged`, `shelfDragMoved`, `openShelf`, `commandBarDropSource`
  - `presentCommandBar`, `dismissCommandBar`
- screenshot/recorder:
  - `presentCapture`, `presentCaptureControls`, `endCaptureControls`, `updateCaptureHeight`
  - `removeCapture`, `captureVisibleWindowIDs`, `protectedWindowIDs`, `isCaptureVisible`
- other panels: `showClipboard`, `showScratchpad`, `openQuickPanel`, `openAppPanel`, `showMetric`
- the mascot: `setMascotInBar`, `reactMascot`, `greetMascot`
- window and input state:
  - `presentationWindow`, `orderBelowIsland`, `expanded`, `selected`, `geometry`
  - `noteOwnLevelAdjustment`, `noteOwnInputSourceSwitch`
- lifecycle: `syncWithPreferences` (17 callers), `open`, `collapse`, `perform`, `running`, `stop`

About 60 files outside the island folders reference island types: menu panel, settings, command bar,
screenshot, recorder, shelf, brightness, clipboard, agent usage, system monitor, wallpaper, scroll, mic mute.
Grep `NotchService.shared\.` before moving anything.

## Recommended merge design
The user asked for Vorssaint's island to go *into* the VoiceOS island, with VoiceOS's purpose
(the voice agent) in charge. Recommendation: make it **look and behave VoiceOS-first, built on
Vorssaint's island host.**
- Vorssaint's host is about 36,600 lines and covers things the VoiceOS controller doesn't: Mission
  Control, fullscreen, multiple displays, drops, capture, HUDs, tests.
- Rebuilding all 16 pages on the 2-file VoiceOS controller would break Vorssaint features that
  depend on it.

Concretely:
1. **Add the VoiceOS agent as a page:** `NotchModule.voice`, plus a `NotchCompactActivity.voice` for
   listening/thinking/speaking. Make it the default/home page and give it priority: while
   `AgentController` is listening, thinking, speaking or awaiting confirmation, the island shows
   the agent and nothing else takes over.
2. **Bring VoiceOS's island look and behaviour across:**
   - the idle black mini-notch that grows on hover; a tap opens the agent
   - the 620-wide expanded agent view: Jarvis glyph, conversation turns, input row with
     "Type or hold [command] to speak"
   - the word-highlighted spoken reply, action/confirmation cards (Send/Edit/✕), the "via" caption
   - click-outside-to-close
   - key focus only while typing (`focusInput`/`releaseKeyFocus` before pasting). Map this onto
     `NotchPanel.acceptsKeyFocus` / `NotchService.panelIsKey`.
3. **Use one window only:** delete VoiceOS's `NotchWindowController`/`NotchPanel`. Its height-driven
   resizing becomes the page's content size inside Vorssaint's stage.
4. **Keep all 16 Vorssaint pages, their strips and notices** reachable from the island's sections
   button/menu, as they are today.
5. Registering a new page touches:
   - the `NotchModule` case and its `symbol`, `shortcutKey`, availability, and `pageTop` (default `.row`)
   - `NotchView`'s page/strip switches
   - the `NotchCompactActivity` case and its title
   - `Core/NotchEditorStrings.swift` (13 languages)
   - `NotchContentEditor`/`NotchSettings`
   - a new `AppFeature` (e.g. `voiceAgent`) in `FeatureCatalog`, so it shows in the Features hub
   - tests that iterate `NotchModule.allCases` or `NotchCompactActivity`

   Copy how `.watch` is wired: `grep -rln '\.watch\b' Sources/Vorssaint`.

## Conflicts to resolve
- **"Agents" means two things.**
  - Vorssaint's `agents` page and `notchAgents` feature show AI **coding-agent usage** (Claude Code,
    Codex, OpenCode… sessions and limits, from `Services/AgentUsage`).
  - VoiceOS's "Agent" is the **voice assistant**.
  - Keep Vorssaint's as is and call the VoiceOS one **Voice** or **Assistant** in code and UI.
- **Type names that already exist in Vorssaint:** `Theme`, `NotchView`, `NotchShape`, `Permissions`,
  `AppDelegate`, `SelfTest`. Rename the VoiceOS ones (e.g. `VO…`). Also check the rest of the VoiceOS
  list (`Router`, `Storage`, `Sounds`, `AppSettings`…) as you go.
- **Hotkeys:**
  - **Super Key** (non-island feature) can be set to **right ⌘** (`SuperKeySource.rightCommand`; the
    default is Caps Lock). That clashes with VoiceOS's hold-right-⌘ agent. Block that choice, or have
    the VoiceOS hotkey stand down while Super Key uses right ⌘. Don't change Super Key's behaviour
    otherwise.
  - Vorssaint's own shortcuts are on ⌃⌥⌘ (island ⌃⌥⌘I). Esc is only handled locally inside Vorssaint
    overlays (screenshot editor, launcher, scratchpad…), so VoiceOS's Esc must also stay local to the
    island/pill.
- **Microphone:**
  - Vorssaint has Mic Mute (`MicMuteService`), the screen recorder (mic audio), and island mic notices.
  - If the user mutes the mic with Vorssaint, VoiceOS dictation hears silence. Show that in the
    VoiceOS UI rather than failing quietly.
- **Fullscreen:** Vorssaint hides the island in fullscreen apps (`hiddenInFullscreen`). The voice agent
  should probably still be summonable by hotkey there; decide and keep it consistent.
- **Bundle identity:**
  - Vorssaint is `com.vorssaint.utils`. Its preferences, TCC grants and the fan-control helper id
    (`<bundle id>.fan-control`) all derive from that.
  - Choose deliberately:
    - keep it, so the user's existing Vorssaint settings carry over, but the merged build replaces
      the installed Vorssaint
    - or use a new id, so the two can coexist, but settings start fresh
  - Don't end the id in `.dev`: `AppInfo.isDeveloperBuild` checks that suffix.
- **Info.plist/entitlements:** add the VoiceOS usage strings (Microphone, Speech Recognition,
  AppleEvents, Calendars/Reminders full access, Contacts) to `Resources/Info.plist`, checking what
  Vorssaint already declares. Keep `Resources/Vorssaint.entitlements` valid.
- **Self-update stays off:** published Vorssaint releases are Apple Silicon only and wouldn't include
  VoiceOS anyway. `AppInfo.releasesRunOnThisMac` already handles this.

## This Mac (constraints from earlier sessions)
- 13" MacBook Pro 2019, Intel i5-8257U, 8 GB RAM, macOS 14.7.7 Sonoma, Xcode 16.2 (Swift 6.0.3, SDK 15.2).
- macOS 26 can't run here, so `#available(macOS 26, *)` Liquid Glass branches never run. The code
  guards them with `#if compiler(>=6.2)`; keep that pattern.
- **No notch.** The island is always drawn by the app.
- The account isn't an admin: install to `~/Applications`. The fan-control helper needs an admin password.
- Ad-hoc signing resets Accessibility/Screen Recording grants after every rebuild.
- External monitor: Dell S2409W via a USB-C adapter. It rejects DDC, so brightness for it uses software
  dimming. That's expected, not a bug.
- 8 GB RAM: don't run the Vorssaint build, the test suite and a local Ollama model at the same time.

## Suggested order of work
1. Copy `~/Desktop/Intel Vorssaint/vorssaint-utils/` into `~/Desktop/Vorssaint + VoiceOS/` as the base.
   Keep its git history, start a new branch, and leave `build/` out. Build it unchanged once to
   confirm the baseline (about 34 min).
2. Add the VoiceOS sources under `Sources/Vorssaint/VoiceOS/`, renaming clashes. Remove the VoiceOS app
   shell, and start its services (hotkeys, dictation pill, agent) from Vorssaint's startup behind a new
   `AppFeature`.
3. Get dictation (the bottom pill, not part of the island) and the VoiceOS settings pages working inside
   Vorssaint's settings window.
4. Make the agent a `NotchModule` + `NotchCompactActivity` with priority, and port the VoiceOS island
   look/behaviour into Vorssaint's island host. Delete the VoiceOS window controller.
5. Resolve the hotkey/mic/fullscreen conflicts above, and merge Info.plist.
6. Build, run `--selftest` and `VOICEOS_SELFTEST` (dry-run only), run the test suite, and compare
   against the 15 known failures.
7. Install to `~/Applications` and have the user check hotkeys, dictation pasting and the island by hand.

## Done means
- Every Vorssaint feature outside the island behaves as before, including every `NotchService.shared…`
  call listed above (HUDs, captures, shelf drops, command bar, mascot).
- One island window: the VoiceOS agent is its home and priority mode, and all 16 Vorssaint pages,
  7 compact strips and notices still work inside it.
- Every VoiceOS feature works: dictation pill, agent, local-first AI rules, history, settings.
- An x86_64 build that passes `--selftest`, with no test failures beyond the 15 known ones.
