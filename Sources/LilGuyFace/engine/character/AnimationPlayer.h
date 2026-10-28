#pragma once

#include "AnimationClips.h"

namespace MotionClips {
enum class SequenceId : uint8_t {
  BlueFlower, FlowerRetreat, SurprisedRetreat, PurpleFlowerCurious, Count
};
enum class SemanticEvent : uint8_t {
  Startled, NearbyObjectApproach, Curious, Playful, Success, SocialContact
};
enum class Phase : uint8_t {
  Inactive, CloseLegacy, BlendEntry, CloseVector, OpenVector,
  Playing, Holding, CloseExit, OpenLegacy, PrepareCatalog
};
const char* phaseName(Phase phase);
const char* sequenceName(SequenceId sequence);

struct PlayerDiagnostics {
  ClipId id = ClipId::OvalHold;
  Phase phase = Phase::Inactive;
  FaceKind sourceFace = FaceKind::Any, targetFace = FaceKind::Any;
  uint32_t localUs = 0, durationUs = 0;
  bool paused = false, playing = false, finished = false, active = false;
  bool vectorVisible = false, loop = false;
  float legacyOpening = 1.0F, rate = 1.0F;
  SequenceId sequence = SequenceId::Count;
  uint8_t sequenceStep = 0;
  Parameters parameters{};
};

// A bounded local clock and three fixed vector frames. The held pose is the
// source for later clips/gestures; a production transition never seeks in a
// source-video timeline. All methods are allocation-free, including start.
class Player {
 public:
  bool start(ClipId id, const Parameters& parameters, uint32_t nowMs,
             const VectorFace::Frame* current = nullptr,
             FaceKind currentFace = FaceKind::Any);
  bool startSequence(SequenceId sequence, const Parameters& parameters,
                     uint32_t nowMs);
  void update(uint32_t nowMs);
  void pause(bool paused, uint32_t nowMs);
  void step(uint32_t deltaUs = 33333);
  // Explicit developer preview of this clip's local clock. Production entry
  // and exit gates are unchanged; a scrub pauses on the requested sample.
  bool seek(uint32_t localUs, uint32_t nowMs);
  bool canSeek() const {
    return active() && sequence_ == SequenceId::Count && !returnToLegacy_;
  }
  void restart(uint32_t nowMs);
  void finish(uint32_t nowMs);
  void cancel(uint32_t nowMs);
  void reset(uint32_t nowMs);
  void setRate(float rate);
  void setLoop(bool loop) { loop_ = loop; }
  void setGaze(float x, float y);
  bool active() const { return phase_ != Phase::Inactive; }
  bool vectorVisible() const;
  float legacyOpening() const;
  const VectorFace::Frame& frame() const { return current_.frame; }
  PlayerDiagnostics diagnostics() const;
  size_t stateBytes() const { return sizeof(*this); }

 private:
  Sample current_{};
  VectorFace::Frame entry_{}, held_{};
  Parameters parameters_{}, sequenceParameters_{};
  ClipId id_ = ClipId::OvalHold;
  FaceKind sourceFace_ = FaceKind::Any, targetFace_ = FaceKind::Any;
  Phase phase_ = Phase::Inactive;
  SequenceId sequence_ = SequenceId::Count;
  uint8_t sequenceStep_ = 0;
  uint32_t lastMs_ = 0, localUs_ = 0, phaseUs_ = 0;
  uint32_t durationUs_ = 0, holdUs_ = 0, gateHalfUs_ = 80000;
  float rate_ = 1.0F;
  double subMicrosecond_ = 0;
  bool paused_ = false, loop_ = false, completed_ = false;
  bool returnToLegacy_ = false;
  bool finishAfterEntry_ = false;

  bool beginClip(ClipId id, const Parameters& parameters,
                 const VectorFace::Frame* current, FaceKind face);
  bool beginSequenceStep();
  void restartGesture();
  bool evaluate(uint32_t localUs);
  void advance(uint32_t elapsedUs);
  void paintPhase();
  void nextPhase();
};
}  // namespace MotionClips
