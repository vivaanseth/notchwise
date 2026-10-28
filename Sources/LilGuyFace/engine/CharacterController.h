#pragma once

#include <Arduino.h>
#include <lvgl.h>

#include "character/CreatureEyeStyle.h"
#include "character/ExactEyeRenderer.h"
#include "character/FaceMotionEngine.h"
#include "character/AnimationPlayer.h"
#include "core/CharacterPort.h"
#include "core/LogicalViewport.h"

// Semantic behavior and cosmetic Creature look are independent. The renderer
// and motion engine live for the lifetime of the Character screen.
class CharacterController : public CharacterPort {
 public:
  void begin(lv_obj_t* parent);
  void update(uint32_t nowMs);
  void setRenderingSuspended(bool suspended);

  void setState(CharacterState state);
  void setPersistentState(CharacterState state) override;
  void playReaction(CharacterState state) override;
  void notifyActivity(uint32_t nowMs = 0) override;
  void setSleeping() override;
  void wake() override;
  void lookAtNormalized(float x, float y, uint32_t holdMs = 1200) override;
  void lookPupilsAtNormalized(float x, float y,
                             uint32_t holdMs = 1200) override;
  void lookAtScreen(int16_t x, int16_t y, uint32_t holdMs = 1200);
  void lookCenter() override;
  void blink() override;
  // Touch gestures relayed from the Dashboard play measured corpus clips.
  bool playGesture(CharacterGesture gesture) override;
  bool isPlayingGesture() const override;
  void previewStyle(CreatureEyeStyle::Id style, uint32_t holdMs = 3500);
  void previewStyleId(uint8_t styleId) override {
    previewStyle(static_cast<CreatureEyeStyle::Id>(styleId));
  }
  CreatureEyeStyle::Id visibleStyle() const { return visualStyle_; }
  void setInactivityTimeoutMs(uint32_t timeoutMs) {
    inactivityTimeoutMs_ = timeoutMs;
  }
  uint32_t inactivityTimeoutMs() const { return inactivityTimeoutMs_; }

  CharacterState state() const override { return currentState_; }
  CharacterState persistentState() const { return persistentState_; }
  bool isPlayingReaction() const override { return temporary_; }
  bool isSleeping() const { return currentState_ == CharacterState::SLEEPING; }

  // Host Face/Motion Lab controls. These do not add on-device UI or allocate.
  void previewPose(FaceMotion::PoseId pose, float intensity = 0.5F);
  void setLook(CreatureEyeStyle::Id style);
  void setIdleEnabled(bool enabled) { motion_.setIdleEnabled(enabled); }
  void freezeIdle(bool frozen) { motion_.freezeIdle(frozen); }
  void pauseMotion(bool paused) {
    if (clipActive()) pauseClip(paused);
    else motion_.pause(paused);
  }
  void stepMotion(uint32_t nowMs) {
    if (clipActive()) stepClip();
    else { motion_.step(nowMs); drawFrame(nowMs); }
  }
  void restartMotionClip(uint32_t nowMs) { motion_.restartClip(nowMs); }
  void scrubMotionTransition(FaceMotion::PoseId source,
                             FaceMotion::PoseId destination,
                             float intensity, uint32_t elapsedMs,
                             uint32_t seed, uint32_t nowMs);
  void closeEyes(FaceMotion::Closure closure);
  void setMotionSeed(uint32_t seed);
  const FaceMotion::Frame& motionFrame() const;
  FaceMotion::Diagnostics motionDiagnostics() const {
    return motion_.diagnostics();
  }
  size_t motionStateBytes() const { return motion_.stateBytes(); }

  // Local semantic/animation API shared by firmware and the developer Lab.
  // No source-video clock or streamed frame data is part of this interface.
  bool playClip(MotionClips::ClipId id,
                 const MotionClips::Parameters& parameters = {});
  bool playClipSequence(MotionClips::SequenceId sequence,
                         const MotionClips::Parameters& parameters = {});
  bool triggerAnimation(MotionClips::SemanticEvent event,
                         const MotionClips::Parameters& parameters = {});
  void pauseClip(bool paused);
  void restartClip();
  void finishClip();
  void cancelClip();
  void stepClip(uint32_t deltaUs = 33333);
  bool seekClip(uint32_t localUs);
  bool canSeekClip() const {
    return pendingSequence_ == MotionClips::SequenceId::Count && clipPlayer_.canSeek();
  }
  void setClipRate(float rate) { clipPlayer_.setRate(rate); }
  void setClipLoop(bool loop) { clipPlayer_.setLoop(loop); }
  bool clipActive() const;
  const VectorFace::Frame& clipFrame() const { return clipPlayer_.frame(); }
  MotionClips::PlayerDiagnostics clipDiagnostics() const;
  size_t clipStateBytes() const { return clipPlayer_.stateBytes(); }
  void render240Row(uint16_t physicalY, lv_color_t* output240,
                    bool maskRound = true) const;
  // Desktop hosts draw rows themselves, with the LVGL canvas suspended; this
  // refreshes the blended face a clip's covered transitions show.
  void prepareRows() { updateClipLegacyFrame(); }

  void handleDevelopmentTap(uint16_t x, uint16_t y);
  static bool isPersistent(CharacterState state);
  static const char* name(CharacterState state);

 private:
  static FaceMotion::PoseId poseFor(CharacterState state);
  void requestStatePose(CharacterState state, uint32_t nowMs);
  void drawFrame(uint32_t nowMs);
  void stopClipForCatalog(uint32_t nowMs);
  void updateClipLegacyFrame();
  void beginPreparedSequence(uint32_t nowMs);

  FaceMotion::Engine motion_;
  MotionClips::Player clipPlayer_;
  FaceMotion::Frame clipLegacySource_{}, clipLegacyFrame_{};
  MotionClips::Parameters pendingSequenceParameters_{};
  MotionClips::SequenceId pendingSequence_ = MotionClips::SequenceId::Count;
  uint32_t sequenceReadyMs_ = 0, sequencePausedMs_ = 0;
  bool sequencePaused_ = false;
  ExactEyeRenderer eyeRenderer_;
  Core::LogicalViewport viewport_{};
  CharacterState currentState_ = CharacterState::IDLE;
  CharacterState persistentState_ = CharacterState::IDLE;
  CreatureEyeStyle::Id visualStyle_ = CreatureEyeStyle::Id::CircleOg;
  bool temporary_ = false;
  bool manualGaze_ = false;
  MotionClips::ClipId gestureClip_ = MotionClips::ClipId::Count;
  uint32_t gestureHeldSinceMs_ = 0;
  bool renderSuspended_ = false;
  uint32_t lastActivityMs_ = 0;
  uint32_t inactivityTimeoutMs_ = 60000;
  uint32_t stateStartedMs_ = 0;
  uint32_t reactionEndsMs_ = 0;
  uint32_t manualGazeEndsMs_ = 0;
  uint32_t lastRenderMs_ = 0;
};
