#pragma once

#include <stdint.h>

// Semantic Character API used by the legacy combined shell. A future
// Dashboard can supply a remote-event adapter without linking the eye model.
enum class CharacterState : uint8_t {
  SLEEPING,
  WAKING,
  IDLE,
  LISTENING,
  THINKING,
  WORKING,
  HAPPY,
  CURIOUS,
  CONFUSED,
  SURPRISED,
  PLAYFUL,
  CELEBRATE,
  SUCCESS,
  ERROR,
  CANCELLED,
  COUNT
};

// Short expressive gestures answering direct touch from the Dashboard (the
// Character itself has no touch). Renderers may map them to measured clips.
enum class CharacterGesture : uint8_t {
  Giggle,  // poked
  Love,    // petted
  Wink,
  Dizzy,   // poked too many times in a row
  Count
};

constexpr CharacterState fallbackState(CharacterGesture gesture) {
  return gesture == CharacterGesture::Love ? CharacterState::HAPPY
       : gesture == CharacterGesture::Dizzy ? CharacterState::CONFUSED
       : gesture == CharacterGesture::Wink ? CharacterState::PLAYFUL
       : CharacterState::HAPPY;
}

constexpr bool isPersistentCharacterState(CharacterState state) {
  return state == CharacterState::SLEEPING ||
         state == CharacterState::IDLE ||
         state == CharacterState::LISTENING ||
         state == CharacterState::THINKING ||
         state == CharacterState::WORKING;
}

class CharacterPort {
 public:
  virtual ~CharacterPort() = default;
  virtual CharacterState state() const = 0;
  virtual bool isPlayingReaction() const = 0;
  virtual void notifyActivity(uint32_t nowMs = 0) = 0;
  virtual void setPersistentState(CharacterState state) = 0;
  virtual void playReaction(CharacterState state) = 0;
  virtual void setSleeping() = 0;
  virtual void wake() = 0;
  virtual void lookAtNormalized(float x, float y, uint32_t holdMs = 1200) = 0;
  virtual void lookPupilsAtNormalized(float x, float y,
                                     uint32_t holdMs = 1200) = 0;
  virtual void lookCenter() = 0;
  virtual void blink() = 0;
  // Default: the closest semantic reaction. Returns false if not shown.
  virtual bool playGesture(CharacterGesture gesture) {
    playReaction(fallbackState(gesture));
    return true;
  }
  virtual bool isPlayingGesture() const { return false; }
  // Legacy development-gallery action; style IDs are opaque to the shell.
  virtual void previewStyleId(uint8_t styleId) = 0;
};
