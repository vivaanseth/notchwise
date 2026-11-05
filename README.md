<h1 align="center">Notchwise</h1>

<p align="center">
  A Dynamic Island for your Mac's notch, a private voice assistant,<br>
  and a menu bar full of the utilities you'd otherwise buy one by one.
</p>

<p align="center">
  <a href="#the-island">The island</a> ·
  <a href="#the-assistant">The assistant</a> ·
  <a href="#everything-it-does">Features</a> ·
  <a href="#build-it">Build it</a> ·
  <a href="#credits">Credits</a>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0--or--later-blue" alt="License GPL 3.0 or later"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-black" alt="macOS 14 and newer">
</p>

Notchwise turns the notch into a place you actually use: music with live audio bars, your calendar, timers, a camera mirror, files, clipboard, battery care and more, all a hover away. A voice assistant lives in the same island, running on a local model first, so most of what you say never leaves your Mac. Around it sits a full set of menu bar utilities. There's no account, no telemetry and no subscription.

## The island

- **One island, many pages.** Home, Controls, Now Playing, Calendar, Timer, Clipboard, Files, Downloads, Captures, Notifications, System, Volume mixer, Battery and more, each a click away from the page bar or the grid of pages.
- **Make it yours.** Right-click to remove any page, home widget, shortcut or control, and add it back later; what stays fills the room.
- **Live activities.** Music, timers, downloads, calendar countdowns and AI agents at work show in the closed island.
- **An Apple-style design.** One set of colours, type and spring animations across every page. See [the island's design](docs/ISLAND_DESIGN.md).
- **Battery care.** A charge limit, sailing, top-ups, calibration, heat protection and a power-flow view, with an admin-installed helper to hold the limit.

## The assistant

- **Hold a key and speak**, or type. It answers in the island, out loud if you like.
- **Local first.** A free local model through [Ollama](https://ollama.com) handles everything it can, and Ollama only opens when it's needed. Cloud AIs you already pay for (Claude, ChatGPT, Gemini) are optional, signed in with your own account.
- **Does things, with your OK.** Drafts messages, emails, notes, reminders and events, and asks before anything is sent or changed.
- **Dictation anywhere**, with on-device cleanup and your own dictionary.

## Everything it does

### Sound

- **Volume mixer.** Set volume per app, boost quiet audio past 100%, and pin or reorder favorites. No audio driver required.
- **Per app output.** Play music through speakers while a call uses your headset.
- **Output switcher.** Switch audio outputs with a shortcut and lower the volume when headphones disconnect.
- **Microphone tools.** Choose a preferred input, adjust its level on supported devices, and mute all microphones with one shortcut.
- **Music app blocker.** Prevent unwanted Music launches after detected playback-button presses. Requires Accessibility.

### Know what your Mac is doing

- **System monitor.** CPU, GPU, memory, temperatures, battery health and power use, with history graphs and a view of energy-hungry apps.
- **Fan Control (beta).** Set manual fan speeds or temperature curves and monitor live RPM.
- **Menu bar readouts.** Put your chosen readings, usage bars, battery time or fan speed directly in the menu bar.
- **Network.** See live traffic, session totals and your local IP address, or run a speed test.
- **Alerts.** Get notified about sustained CPU load, high temperatures, memory pressure, low disk space or low battery.

### Windows and the Dock

- **App switcher.** Switch between apps and windows with live previews, search and display filters. A simpler mode works without screen capture.
- **Window layout.** Snap windows into layouts, move them between displays and restore earlier positions using shortcuts, screen edges or modifier-drag gestures.
- **Dock Preview.** Hover over Dock icons to preview windows across desktops. Switch, close, move or snap them from the preview.
- **Dock clicks.** Click an active app's Dock icon to minimize, hide or cycle through its windows.
- **Maximize windows.** Use the green button to fill the screen without creating another Space.
- **Fixed Space order.** Keep Spaces in the order you set instead of rearranging them by recent use. Turning it off restores your previous setting.
- **Quit on close.** Quit selected apps when their last window closes.
- **Quit and close protection.** Prevent accidental ⌘Q or ⌘W with a hold, double press or extra modifier, per app.

<p align="center">
  <img src="docs/assets/readme/quit-protection-hold.png" width="300" alt="The hold-to-confirm prompt showing progress below the Command-Q quit shortcut hint">
</p>

<p align="center">
  <img src="docs/assets/readme/window-switcher.gif" width="540" alt="The window switcher showing live thumbnails of open windows">
</p>

### Keyboard and mouse

- **Text snippets.** Expand short triggers into text with clipboard, date and time variables, or insert snippets from a searchable menu.
- **Smooth scrolling.** Give your mouse wheel a fluid glide with adjustable speed and response.
- **Pointer acceleration.** Disable mouse acceleration and restore your previous setting when turned off.
- **Linear scrolling.** Make every mouse wheel notch scroll the same number of lines, however fast the wheel spins.
- **Focus follows mouse.** Bring the window under the pointer forward after an adjustable pause.
- **Scroll direction.** Invert vertical and horizontal mouse scrolling independently of the trackpad.
- **Scroll sideways while holding a key.** Turn vertical wheel movement into horizontal scrolling while holding a chosen key.
- **Side buttons.** Use mouse Back and Forward buttons in Finder, browsers and compatible apps.
- **Mouse button shortcuts.** Assign keys to extra buttons and side wheels, or use button-drag gestures for Spaces and Mission Control.
- **Middle click.** Turn a three-finger trackpad press into a middle click.
- **Apps to leave alone.** Exclude chosen apps from mouse enhancements.
- **Extra click filter.** Ignore accidental rapid clicks from worn mouse buttons without delaying normal clicks.
- **Key debounce.** Filter repeated letters caused by a worn keyboard.
- **Super key.** Use Caps Lock or a right-side modifier as a shortcut combination, with a separate tap action and app exclusions.
- **Keyboard shortcuts.** Manage feature shortcuts in one place, including optional takeover of supported macOS shortcuts while a feature is active.

### Clipboard, files and links

- **Clipboard history.** Search local text, image and file history, pin favorites, preview entries and paste with shortcuts.
- **Auto clear clipboard.** Clear the system clipboard after a delay, sleep or lock, while keeping saved history.
- **Paste as plain text.** Paste without formatting while preserving the original clipboard content.
- **Shelf.** Park files, text and links near your cursor while dragging, then drop or share them later.
- **Finder shortcuts.** Move files with ⌘X and ⌘V, rename with F2, or paste copied images as PNG files.
- **Clean URL.** Remove tracking parameters from links, manually or automatically.
- **Disk image installer.** Install an app from a mounted disk image and eject it, with optional download cleanup.

### Everyday tools

- **Dynamic Island.** Keep music, notifications, calendars, timers, downloads and everyday controls around the camera cutout, or a simulated one on other Macs. Customize sections and shortcuts, with optional lyrics, a live equalizer, camera preview and file tools.
- **AI agents.** Follow Claude, Codex, OpenCode and GitHub Copilot in the Dynamic Island: plan limits and when they reset where available, tokens, API value, models, projects and live work, with a notice when a long task finishes. Codex's banked resets can be used from there too, and each extra Codex account (`CODEX_HOME`) can have a limits card of its own. Copilot uses local CLI/app session logs; its token totals update when shutdown metrics arrive, and aggregate API-value estimates use base rates.
- **Command Bar.** Search apps, windows, files, clipboard history, snippets and app menu commands from one field. Calculate, convert units, find emoji or run saved scripts.
- **Quick panel.** Open a floating palette of favorite tools with ⌃⌘V.
- **Quick toggles.** Switch appearance, hide desktop icons, eject disks, empty the Trash, lock the screen and more.
- **Radial menu.** Open a customizable wheel of apps, files, shortcuts and tools around the pointer, with profiles and submenus.
- **Scratchpad.** Keep autosaved notes in tabs, with Markdown preview and export, in a floating window or Dynamic Island.
- **Cleaning Mode.** Lock keyboard input while cleaning, with a black screen or a small visible indicator.

### Capture and create

- **Screen capture.** Switch between screenshots, recording, text recognition and color picking in one selector with a pixel magnifier.
- **Screenshot.** Capture an area, window, screen or scrolling page. Annotate, crop, redact, add backgrounds and watermarks, pin captures, send them through the Share menu or share an expiring link.
- **Screen recording.** Record with separate system-audio and microphone tracks. Trim, cut, add automatic zooms, blur private details and export video or GIFs, or share an expiring link.
- **Camera preview.** Check your camera in a floating mirror or Dynamic Island before a call.
- **Copy text from screen.** Recognize text offline from any screen area, or read a QR code.
- **Color picker.** Copy a screen color as HEX, RGB, HSL or SwiftUI code.
- **Media tools.** Compress and edit videos, batch-convert images, add watermarks, make GIFs and extract text, all locally.

### App management

- **App updates.** Check store apps, package-managed apps and supported developer feeds in one list. Install managed updates together or open an app's own updater.
- **Cleaner.** Remove caches, logs and app leftovers, manually or on a schedule.
- **Messaging downloads.** Review, organize or move messaging downloads to the Trash using retention rules.
- **Uninstaller.** Remove apps and review their related caches, preferences and helpers before moving them to the Trash.
- **Homebrew manager.** Search, install and remove formulae and casks without opening a terminal.
- **Port manager.** Find processes listening on network ports and stop them with Kill Process when installed.

### Energy and display

- **Keep awake.** Keep your Mac working on a timer, with the lid closed, or while selected apps, power or external displays are present.
- **Displays.** Control individual displays and brightness, with hardware control where supported, half or quarter steps for the brightness keys, optional extra dimming below a monitor's minimum, and software dimming as a fallback.
- **Extra brightness.** Use a MacBook Pro XDR display's HDR headroom to go beyond its normal maximum brightness.
- **Bluetooth on sleep.** Disconnect Bluetooth during sleep and restore it on wake only if Notchwise turned it off.

## Build it

```sh
git clone https://github.com/vivaanseth/vorssaint-voiceos.git
cd vorssaint-voiceos
./build.sh                  # builds build/stage/Notchwise.app
./build.sh --test-suite=notch   # runs a test suite
```

Xcode Command Line Tools are the only requirement. Builds work on Intel and Apple Silicon Macs running macOS 14 Sonoma or newer. [Tools/setup-signing.sh](Tools/setup-signing.sh) makes a local signing identity so macOS keeps your permissions across rebuilds.

## Private by default

Notchwise is local-first, with no account, analytics or tracking. The network is touched only by things you can see: the speed test, Homebrew actions, optional online lyric lookup, temporary screenshot or recording links, and the cloud AIs you choose to connect. See the [privacy notes](docs/PRIVACY.md) and the [permissions guide](docs/PERMISSIONS.md).

## Documentation

- [The island's design](docs/ISLAND_DESIGN.md)
- [The assistant](docs/VOICEOS.md)
- [Privacy](docs/PRIVACY.md) and [permissions](docs/PERMISSIONS.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)
- [Contributing](CONTRIBUTING.md), [support](SUPPORT.md) and [security](SECURITY.md)

## Credits

Notchwise is built on **[Vorssaint](https://github.com/vorssaint/vorssaint-utils)**, a free and open-source Mac utility by Vorssaint, licensed under GPL-3.0-or-later. Its menu bar utilities and the original Dynamic Island come from Vorssaint 3.4.2; Notchwise adds the voice assistant, the Intel build, Battery Care, island customization, the redesign and many fixes. Notchwise is an independent project and is not affiliated with or endorsed by Vorssaint.

The assistant's design is inspired by VoiceOS. Notchwise is not affiliated with, endorsed by or connected to VoiceOS or its makers, and uses none of their code or assets.

The app icon is by [@divisionseven](https://github.com/divisionseven), from Vorssaint.

## License

[GPL 3.0 or later](LICENSE). Copyright 2026 Vivaan, and portions copyright 2026 Vorssaint. Files that started in Vorssaint keep their original copyright notice; see [TRADEMARKS.md](TRADEMARKS.md) for names and branding.
