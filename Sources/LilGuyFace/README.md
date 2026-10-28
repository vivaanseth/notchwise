# Lil Guy's face engine

The island's character. `engine/` is the C++ face engine from the `LilGuyFaces` package at the
repository root (itself a copy from the ESP32 project), built into a static library by
`build.sh` and linked into the app.

- `engine/character/`: the engine and every face and clip, unchanged.
- `engine/CharacterController.*`, `engine/core/CharacterPort.h`: the ESP32 project's driver
  (states, reactions, gestures, sleep, gaze, clips). One addition, `prepareRows()`, refreshes the
  blended face a clip's covered transitions show, since the app draws rows itself instead of the
  device's LVGL canvas.
- `engine/host/`: the package's desktop stand-ins for `Arduino.h`, `lvgl.h` and `esp_*`, plus a
  no-op `PerformanceStats.h`. Time reaches the engine through `testMillis`, set by the wrapper
  before each call.
- `engine/LilGuyFace.cpp`, `include/LilGuyFace.h`: the C interface Swift imports as
  `LilGuyFace`. A face renders into a 240 × 240 RGBA buffer in which the black of the round
  screen is clear, so it sits on the island's own black.
