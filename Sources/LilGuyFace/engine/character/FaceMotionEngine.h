#pragma once

#include <cstddef>
#include <cstdint>

// Behavioral geometry is authored in the 480 x 480 logical Creature space.
// The caller owns the cosmetic look; this module never selects a palette.
namespace FaceMotion {

enum class PoseId : uint8_t {
  F01, F02, F03, F04, F05, F06, F07, F08, F09, F10, F11, F12, F13, F14,
  R01, R02, R03, R04, R05, R06, R07, R08, R09, R10,
  T01, T02, T03, T04, T05, T06, T07, T08, T09, T10, T11, T12,
  C01, C02, C03, C04,
  S01, S02, S03, S04,
  Count
};
enum class Family : uint8_t { Round, Capsule, Arc, Slit, Petal, Multi, Collage };
enum class Motif : uint8_t { Dot, Oval, Heart, Bolt, Spiral, Flower, None };
enum Effect : uint8_t {
  NoEffect = 0, Sparkle = 1, Hearts = 2, Flash = 4,
  Collision = 8, WarmAccent = 16
};
enum class Stage : uint8_t {
  Rest, Anticipation, Gate, Peak, Overshoot, Settle, Blink, Sleep, Social
};
enum class Closure : uint8_t { Neutral, Happy, Sleepy, Wince };

struct Eye {
  float x, y;                     // Logical screen-space center.
  float width, height;            // Logical full extents.
  float rotation;                 // Degrees, eye-local.
  float pupilX, pupilY;           // Eye-local offset, logical pixels.
  float pupilWidth, pupilHeight;  // Logical full extents.
  float lidTop, lidBottom;        // 0..1 occlusion fractions.
};
struct Frame {
  PoseId pose;
  Family family;
  Motif motif;
  uint8_t eyeCount;
  Eye eyes[4];
  uint8_t lookId;                 // Independent Creature cosmetic look, 0..7.
  uint8_t effects;                // Effect bitmask above.
  float effectPhase;              // Bounded 0..1 transient effect beat.
  float coverage;                 // Pupil coverage 0..1 at topology gates.
  float intensity;                // Clamped request intensity 0..1.
  bool replacementFrame;         // True only at covered atomic topology swap.
};
struct Diagnostics {
  PoseId source;
  PoseId target;
  Stage stage;
  Closure closure;
  uint8_t keyframe;               // 0 rest, 1 lead, 2 gate, 3 peak,
                                  // 4 overshoot, 5 settle, 6 social.
  float stageProgress;
  float settleProgress;
  float gazeTargetX, gazeTargetY;
  uint32_t nextBlinkMs, nextIdleMs;
  uint16_t clipCount, topologySwapCount, mergedBlinkCount;
  bool transitionActive, blinking, sleeping, idleEnabled, idleFrozen, paused;
};

// 44 compact authored definitions. Names/evidence are display and QA metadata.
struct PoseDefinition {
  PoseId id;
  Family family;
  Motif motif;
  uint8_t eyeCount, effects;
  float width, height, spacing, y;
  float asymmetry, tilt, pupilScale, lidTop, lidBottom;
  const char* name;
  const char* evidence;
};

constexpr size_t kPoseCount = static_cast<size_t>(PoseId::Count);
static_assert(kPoseCount == 44, "LilGuy behavioral vocabulary is 44 poses");
const PoseDefinition& poseDefinition(PoseId id);
const char* poseName(PoseId id);
bool isPersistent(PoseId id);
bool isReaction(PoseId id);
bool isTransition(PoseId id);
bool isClosure(PoseId id);
bool isSocial(PoseId id);

class Engine {
 public:
  void begin(uint32_t nowMs, uint32_t seed = 1);
  void update(uint32_t nowMs);
  void request(PoseId pose, float intensity = 0.5F, uint32_t nowMs = 0);
  void setLook(uint8_t lookId);
  void lookAt(float normalizedX, float normalizedY, uint32_t nowMs = 0);
  void centerGaze(uint32_t nowMs = 0);
  void blink(uint32_t nowMs = 0);
  void close(Closure closure, uint32_t nowMs = 0);
  void sleep(uint32_t nowMs = 0);
  void wake(uint32_t nowMs = 0);
  void setIdleEnabled(bool enabled) { idleEnabled_ = enabled; }
  void freezeIdle(bool frozen) { idleFrozen_ = frozen; }
  void pause(bool paused);
  void restartClip(uint32_t nowMs = 0);
  void step(uint32_t nowMs);
  const Frame& frame() const { return frame_; }
  Diagnostics diagnostics() const;
  size_t stateBytes() const { return sizeof(*this); }
  static size_t catalogBytes();

 private:
  Frame frame_{};
  Diagnostics diag_{};
  uint32_t rng_ = 1, lastMs_ = 0, stageStartMs_ = 0;
  uint32_t gazeStartMs_ = 0, gazeHoldMs_ = 0, lastCloseMs_ = 0;
  uint32_t idleStartMs_ = 0, idleEndMs_ = 0, blinkStartMs_ = 0;
  uint32_t pauseStartMs_ = 0, suppressBlinkUntilMs_ = 0;
  uint32_t temporaryUntilMs_ = 0;
  uint32_t measuredStartMs_ = 0;
  PoseId sourcePose_ = PoseId::F01, targetPose_ = PoseId::F01;
  PoseId persistentPose_ = PoseId::F01;
  PoseId pendingPose_ = PoseId::Count;
  Frame sourceFrame_{};
  float gazeFromX_ = 0, gazeFromY_ = 0, gazeX_ = 0, gazeY_ = 0;
  float pupilHandoffX_[2]{}, pupilHandoffY_[2]{};
  float idleX_ = 0, idleY_ = 0, idleAspect_ = 0, idleSpacing_ = 0;
  float clipIntensity_ = 0.5F;
  float pendingIntensity_ = 0.5F;
  bool gateRequired_ = false, swapped_ = false, semanticClose_ = false;
  bool idleEnabled_ = true, idleFrozen_ = false, paused_ = false;
  bool blinkActive_ = false, sleeping_ = false;
  bool gazeLocked_ = false;
  bool temporaryActive_ = false;
  bool measuredAttention_ = false;
  bool pupilHandoff_ = false;
  uint8_t idleEvent_ = 0;
  uint8_t socialBeat_ = 0;
  uint8_t lookId_ = 0;
  uint8_t targetLook_ = 0;
  uint8_t pendingLook_ = 255;
  Closure blinkClosure_ = Closure::Neutral;

  uint32_t random();
  uint32_t randomRange(uint32_t lo, uint32_t hi);
  void scheduleBlink(uint32_t nowMs);
  void scheduleIdle(uint32_t nowMs);
  void startStage(Stage stage, uint32_t nowMs);
  void resolveRequest(PoseId pose, float intensity, uint32_t nowMs);
  void capturePupilHandoff();
  void evaluate(uint32_t nowMs);
};

}  // namespace FaceMotion
