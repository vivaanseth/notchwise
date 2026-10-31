// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

// Shortcuts' Run Shell Script calls the app as `battery <command>`.
BatteryCareCLI.runIfRequestedAndExit()
SuperKeyMappingGuard.runIfRequestedAndExit()
// The combined app starts from the standalone apps' choices, copied once
// before registration so its migrations see them as those apps saved them.
MergedSettingsImport.runOnce()
MergedSettingsImport.applyHoverHomeOnce()
MergedSettingsImport.hideInFullscreenOnce()
Defaults.register()
MergedSettingsImport.showAllControlsOnce()
MergedSettingsImport.removeCompanionOnce()
MergedSettingsImport.showBatteryCareOnce()
NotchControlItem.keyboardLightIsSupported = { BrightnessService.keyboardLightIsSupported }
NotchControlItem.hasBattery = { PowerSampler.hasInternalBattery }
MouseAccelerationGuard.runIfRequestedAndExit()
MouseAccelerationService.recoverPendingAtLaunch()

if CommandLine.arguments.contains("--selftest") {
    SelfTest.runAndExit()
}
if CommandLine.arguments.contains("--sensors") {
    SensorDump.runAndExit()
}
if CommandLine.arguments.contains("--uninstall") {
    Uninstaller.runAndExit()
}

#if VORSSAINT_DEVELOPMENT
// A probe mode on its own would otherwise launch the whole app, and TCC kills
// that from a shell whose host app lacks a Bluetooth usage description. The
// commands above come first, so `--selftest` beside a probe mode runs the
// selftest, not the probe.
if NotchPresentationProbe.isRequested(by: CommandLine.arguments) {
    NotchPresentationProbe.runAndExit()
}
#endif

// VoiceOS's snapshot and self-test tools: only the island and the assistant.
if VOHarness.isRequested {
    VOHarness.runAndExit()
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
