#pragma once
#include <stdbool.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct LGFace LGFace;
LGFace *lg_face_create(uint32_t nowMs);
void lg_face_destroy(LGFace *face);
void lg_face_update(LGFace *face, uint32_t nowMs);
void lg_face_set_state(LGFace *face, uint8_t state, uint32_t nowMs);
void lg_face_react(LGFace *face, uint8_t state, uint32_t nowMs);
bool lg_face_gesture(LGFace *face, uint8_t gesture, uint32_t nowMs);
bool lg_face_play_clip(LGFace *face, uint8_t clip, bool mirror, uint32_t nowMs);
void lg_face_look_at(LGFace *face, float x, float y, uint32_t holdMs, uint32_t nowMs);
void lg_face_look_center(LGFace *face, uint32_t nowMs);
void lg_face_blink(LGFace *face, uint32_t nowMs);
void lg_face_sleep(LGFace *face, uint32_t nowMs);
void lg_face_wake(LGFace *face, uint32_t nowMs);
void lg_face_activity(LGFace *face, uint32_t nowMs);
void lg_face_set_sleep_after(LGFace *face, uint32_t milliseconds);
uint8_t lg_face_state(const LGFace *face);
uint32_t lg_face_next_change(const LGFace *face, uint32_t nowMs);
void lg_face_render(LGFace *face, uint32_t nowMs, uint32_t *rgba240);
#ifdef __cplusplus
}
#endif
