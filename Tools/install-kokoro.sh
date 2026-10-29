#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Installs Kokoro, the assistant's natural voice, where the app looks for it:
#
#   Tools/install-kokoro.sh
#
# Into ~/Library/Application Support/VoiceOS Clone/kokoro: a Python virtual
# environment with sherpa-onnx 1.12.40 (about 13 MB from PyPI) and Kokoro's int8
# multi-language v1.0 model (about 132 MB from k2-fsa/sherpa-onnx's GitHub
# releases). Run again, it only fetches what is missing. Everything runs on
# this Mac; the app speaks through it once it is there.
set -euo pipefail

BASE="$HOME/Library/Application Support/VoiceOS Clone/kokoro"
MODEL="kokoro-int8-multi-lang-v1_0"
# 1.12.40, not 2.x: 2.x reads Kokoro's words only from its word lists and
# skips any other, names included; 1.12.40 sounds those out with espeak-ng.
SHERPA_VERSION="1.12.40"
MODEL_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/$MODEL.tar.bz2"

PYTHON=""
for candidate in python3.12 python3.13 python3.11 python3; do
    if command -v "$candidate" >/dev/null 2>&1; then PYTHON="$(command -v "$candidate")"; break; fi
done
[[ -n "$PYTHON" ]] || { echo "✗ Python 3 is needed (brew install python@3.12)" >&2; exit 1; }

mkdir -p "$BASE"
if [[ ! -x "$BASE/venv/bin/python3" ]]; then
    echo "▸ Creating the Python environment with $PYTHON…"
    "$PYTHON" -m venv "$BASE/venv"
fi
if [[ "$("$BASE/venv/bin/python3" -m pip show sherpa-onnx 2>/dev/null || true)" != *"Version: $SHERPA_VERSION"* ]]; then
    echo "▸ Installing sherpa-onnx $SHERPA_VERSION…"
    "$BASE/venv/bin/python3" -m pip install --quiet --disable-pip-version-check \
        "sherpa-onnx==$SHERPA_VERSION" "sherpa-onnx-core==$SHERPA_VERSION"
fi

if [[ ! -f "$BASE/$MODEL/model.int8.onnx" ]]; then
    echo "▸ Downloading Kokoro ($MODEL, about 132 MB)…"
    DOWNLOAD="$(mktemp -d)"
    trap 'rm -rf "${DOWNLOAD:?}"' EXIT
    curl --fail --location --progress-bar -o "$DOWNLOAD/$MODEL.tar.bz2" "$MODEL_URL"
    tar -xjf "$DOWNLOAD/$MODEL.tar.bz2" -C "$DOWNLOAD"
    [[ -f "$DOWNLOAD/$MODEL/model.int8.onnx" ]] || { echo "✗ The archive has no model.int8.onnx" >&2; exit 1; }
    rm -rf "${BASE:?}/${MODEL:?}"
    mv "$DOWNLOAD/$MODEL" "$BASE/$MODEL"
fi

echo "✓ Kokoro is installed in $BASE"
