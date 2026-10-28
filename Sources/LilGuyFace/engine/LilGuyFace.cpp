#include "LilGuyFace.h"
#include "CharacterController.h"

uint32_t testMillis = 0;
lv_color_t* testCanvasPixels = nullptr;

struct LGFace {
  CharacterController controller;
  lv_obj_t parent;
  // A clip played on its own holds its last pose; it is let go this long
  // after it finishes, as the ESP32 project does for its gestures.
  uint32_t clipFinishedMs = 0;
  bool ownsClip = false;
};

namespace {
constexpr uint32_t kClipReleaseMs = 240;
}

namespace {
void at(uint32_t nowMs) { testMillis = nowMs; }
CharacterState state(uint8_t value) {
  return value < static_cast<uint8_t>(CharacterState::COUNT)
      ? static_cast<CharacterState>(value) : CharacterState::IDLE;
}
}

extern "C" {
LGFace *lg_face_create(uint32_t nowMs) {
  at(nowMs);
  auto *face = new LGFace();
  face->controller.begin(&face->parent);
  face->controller.setRenderingSuspended(true);
  return face;
}
void lg_face_destroy(LGFace *face) { delete face; }
void lg_face_update(LGFace *face, uint32_t nowMs) {
  at(nowMs);
  face->controller.update(nowMs);
  if (!face->ownsClip) return;
  if (!face->controller.clipActive()) { face->ownsClip = false; return; }
  if (!face->controller.clipDiagnostics().finished) { face->clipFinishedMs = 0; return; }
  if (face->clipFinishedMs == 0) face->clipFinishedMs = nowMs;
  if (static_cast<int32_t>(nowMs - face->clipFinishedMs) >= static_cast<int32_t>(kClipReleaseMs)) {
    face->controller.cancelClip();
    face->ownsClip = false;
  }
}
void lg_face_set_state(LGFace *face, uint8_t value, uint32_t nowMs) {
  at(nowMs); face->controller.setPersistentState(state(value));
}
void lg_face_react(LGFace *face, uint8_t value, uint32_t nowMs) {
  at(nowMs); face->controller.playReaction(state(value));
}
bool lg_face_gesture(LGFace *face, uint8_t gesture, uint32_t nowMs) {
  at(nowMs);
  if (gesture >= static_cast<uint8_t>(CharacterGesture::Count)) return false;
  return face->controller.playGesture(static_cast<CharacterGesture>(gesture));
}
bool lg_face_play_clip(LGFace *face, uint8_t clip, bool mirror, uint32_t nowMs) {
  at(nowMs);
  if (clip >= static_cast<uint8_t>(MotionClips::ClipId::Count)) return false;
  MotionClips::Parameters parameters{};
  parameters.mirror = mirror;
  const bool started = face->controller.playClip(static_cast<MotionClips::ClipId>(clip), parameters);
  face->ownsClip = started;
  face->clipFinishedMs = 0;
  return started;
}
void lg_face_look_at(LGFace *face, float x, float y, uint32_t holdMs, uint32_t nowMs) {
  at(nowMs); face->controller.lookAtNormalized(x, y, holdMs);
}
void lg_face_look_center(LGFace *face, uint32_t nowMs) { at(nowMs); face->controller.lookCenter(); }
void lg_face_blink(LGFace *face, uint32_t nowMs) { at(nowMs); face->controller.blink(); }
void lg_face_sleep(LGFace *face, uint32_t nowMs) { at(nowMs); face->controller.setSleeping(); }
void lg_face_wake(LGFace *face, uint32_t nowMs) { at(nowMs); face->controller.wake(); }
void lg_face_activity(LGFace *face, uint32_t nowMs) { at(nowMs); face->controller.notifyActivity(nowMs); }
void lg_face_set_sleep_after(LGFace *face, uint32_t milliseconds) {
  face->controller.setInactivityTimeoutMs(milliseconds);
}
uint8_t lg_face_state(const LGFace *face) { return static_cast<uint8_t>(face->controller.state()); }
uint32_t lg_face_next_change(const LGFace *face, uint32_t nowMs) {
  const auto &controller = face->controller;
  const auto motion = controller.motionDiagnostics();
  // Anything moving is drawn at 30 frames a second.
  if (controller.clipActive() || controller.isPlayingReaction() || motion.transitionActive || motion.blinking
      || controller.state() == CharacterState::WAKING)
    return nowMs + 33;
  // Asleep, the face only changes when it is woken, which redraws it.
  if (motion.sleeping || controller.state() == CharacterState::SLEEPING) return nowMs + 2000;
  // At rest it is still until its next blink or glance; a time already gone
  // means none is scheduled, and it looks again shortly.
  uint32_t next = nowMs + 1000;
  for (uint32_t candidate : {motion.nextBlinkMs, motion.nextIdleMs}) {
    const int32_t ahead = static_cast<int32_t>(candidate - nowMs);
    if (ahead > 0 && static_cast<int32_t>(candidate - next) < 0) next = candidate;
  }
  return static_cast<int32_t>(next - nowMs) < 33 ? nowMs + 33 : next;
}
void lg_face_render(LGFace *face, uint32_t nowMs, uint32_t *rgba240) {
  at(nowMs);
  face->controller.prepareRows();
  lv_color_t row[240];
  for (uint16_t y = 0; y < 240; ++y) {
    face->controller.render240Row(y, row, false);
    for (int x = 0; x < 240; ++x) {
      const uint16_t c = row[x].full;
      const uint32_t r = ((c >> 11) & 0x1f) * 255 / 31;
      const uint32_t g = ((c >> 5) & 0x3f) * 255 / 63;
      const uint32_t b = (c & 0x1f) * 255 / 31;
      // Black is the island itself: it stays clear, so the face sits on any surface.
      const uint32_t a = (r | g | b) ? 255 : 0;
      rgba240[y * 240 + x] = r | (g << 8) | (b << 16) | (a << 24);
    }
  }
}
}
