#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Runs VoiceOS's developer tools against the built app, dry-run only:
#
#   Tools/voiceos-harness.sh snapshot <dir>    renders the assistant's island
#       states, the dictation pill and the VoiceOS settings pages to PNGs
#   Tools/voiceos-harness.sh selftest <file>   sends a dictation cleanup and a few
#       assistant requests through the real router (voice muted, actions never
#       executed) and logs which brain answered
#
# Extra environment for selftest: VOICEOS_PROVIDER, VOICEOS_QUERY,
# VOICEOS_ESCALATION_LIMIT, VOICEOS_TEST_IMAGE, VOICEOS_NO_MODELS=1 (no local
# model started), VOICEOS_TEST_AUDIO (a 16 kHz mono WAV for Whisper; see
# VOSelfTest.swift).
#
# The tools run in a copy of build/stage's app with a throwaway bundle id, so
# they never read or write the real app's preferences, and in harness mode
# (VOHarness.swift): only the island, the assistant and the settings window
# start. Vorssaint's system features, global hotkeys and menu bar items stay
# off. The copy's preferences are deleted afterwards.
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${1:-}"; OUT="${2:-}"
if [[ "$MODE" != snapshot && "$MODE" != selftest ]] || [[ -z "$OUT" ]]; then
    echo "usage: $0 snapshot <dir> | selftest <file>" >&2
    exit 2
fi
SOURCE_APP="build/stage/Vorssaint + VoiceOS.app"
[[ -d "$SOURCE_APP" ]] || { echo "✗ build the app first (./build.sh)" >&2; exit 1; }

HARNESS_ID="com.vorssaint.voiceos.selftest"
HARNESS_DIR="build/harness"
HARNESS="$HARNESS_DIR/Vorssaint + VoiceOS Harness.app"
mkdir -p "$HARNESS_DIR"
rm -rf "$HARNESS"
ditto --noextattr --noqtn "$SOURCE_APP" "$HARNESS"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $HARNESS_ID" \
    -c "Set :CFBundleName Vorssaint + VoiceOS Harness" \
    -c "Set :CFBundleDisplayName Vorssaint + VoiceOS Harness" "$HARNESS/Contents/Info.plist"
codesign --force --deep --sign - "$HARNESS" >/dev/null 2>&1
# VoiceOS keeps its history and counters under the home folder; the tools get
# a scratch one so a test run leaves the real ones as they were.
SCRATCH_HOME="$(mktemp -d)"
trap 'rm -rf "$SCRATCH_HOME"; defaults delete "$HARNESS_ID" >/dev/null 2>&1 || true' EXIT

OUT="${OUT:A}"
LOG="$HARNESS_DIR/$MODE.log"
ENV_ARGS=(--env "CFFIXED_USER_HOME=$SCRATCH_HOME")
# The Whisper models already on this Mac, seen from the scratch home as from the real one.
for models in "MacWhisper/models" "VoiceOS Clone/models"; do
    if [[ -d "$HOME/Library/Application Support/$models" ]]; then
        mkdir -p "$SCRATCH_HOME/Library/Application Support/${models:h}"
        ln -s "$HOME/Library/Application Support/$models" "$SCRATCH_HOME/Library/Application Support/$models"
    fi
done
if [[ "$MODE" == snapshot ]]; then
    mkdir -p "$OUT"
    ENV_ARGS+=(--env "VOICEOS_SNAPSHOT=$OUT")
else
    mkdir -p "${OUT:h}"
    ENV_ARGS+=(--env "VOICEOS_SELFTEST=$OUT")
fi
for name in VOICEOS_PROVIDER VOICEOS_QUERY VOICEOS_ESCALATION_LIMIT VOICEOS_TEST_IMAGE VOICEOS_DEBUG_LOG VOICEOS_NO_MODELS \
            VOICEOS_TEST_AUDIO; do
    [[ -n "${(P)name:-}" ]] && ENV_ARGS+=(--env "$name=${(P)name}")
done

# Launched by LaunchServices, so the app is its own process, in the background.
open -n -W -g "${ENV_ARGS[@]}" --stdout "$LOG" --stderr "$LOG" "$HARNESS"
echo "✓ $MODE done: $OUT"
