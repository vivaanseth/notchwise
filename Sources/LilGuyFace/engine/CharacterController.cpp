#include "CharacterController.h"

#include <cmath>

#include "PerformanceStats.h"
#include "character/FaceMotionRaster.h"

namespace {
constexpr uint32_t kEyeFrameMs = 30;
constexpr uint32_t kOrdinaryReactionMs = 1900;
constexpr uint32_t kHappyReactionMs = 2100;
constexpr uint32_t kCelebrateReactionMs = 2650;
// Covers the authored reopen, single overshoot, and final settle.
constexpr uint32_t kWakeMs = 1250;

bool valid(CharacterState state) {
  return static_cast<uint8_t>(state) <
         static_cast<uint8_t>(CharacterState::COUNT);
}
bool reached(uint32_t nowMs, uint32_t deadlineMs) {
  return static_cast<int32_t>(nowMs - deadlineMs) >= 0;
}
uint32_t activityTime(uint32_t requestedMs) {
  return requestedMs == 0 ? millis() : requestedMs;
}
}  // namespace

void CharacterController::begin(lv_obj_t* parent) {
  const uint32_t nowMs = millis();
  if (!eyeRenderer_.begin(parent)) {
    Serial.println("[character] eye canvas PSRAM allocation failed");
    return;
  }
  viewport_ = eyeRenderer_.viewport();
  // The engine owns a tiny PRNG; no heap allocation or global random state.
  motion_.begin(nowMs, nowMs ^ 0x5a17e31dU);
  clipPlayer_.reset(nowMs);
  currentState_ = persistentState_ = CharacterState::IDLE;
  visualStyle_ = CreatureEyeStyle::Id::CircleOg;
  motion_.setLook(static_cast<uint8_t>(visualStyle_));
  lastActivityMs_ = stateStartedMs_ = nowMs;
  drawFrame(nowMs);
}

void CharacterController::setRenderingSuspended(bool suspended) {
  if (renderSuspended_ && !suspended) lastRenderMs_ = 0;
  renderSuspended_ = suspended;
}

bool CharacterController::isPersistent(CharacterState state) {
  return isPersistentCharacterState(state);
}

const char* CharacterController::name(CharacterState state) {
  constexpr const char* kNames[] = {
      "SLEEPING", "WAKING", "IDLE", "LISTENING", "THINKING",
      "WORKING", "HAPPY", "CURIOUS", "CONFUSED", "SURPRISED",
      "PLAYFUL", "CELEBRATE", "SUCCESS", "ERROR", "CANCELLED"};
  const uint8_t index = static_cast<uint8_t>(state);
  return index < static_cast<uint8_t>(CharacterState::COUNT)
             ? kNames[index] : "UNKNOWN";
}

FaceMotion::PoseId CharacterController::poseFor(CharacterState state) {
  using Pose = FaceMotion::PoseId;
  switch (state) {
    case CharacterState::SLEEPING: return Pose::F06;
    case CharacterState::WAKING: return Pose::R10;
    case CharacterState::LISTENING: return Pose::F13;
    case CharacterState::THINKING: return Pose::F12;
    case CharacterState::WORKING: return Pose::F14;
    case CharacterState::HAPPY: return Pose::F07;
    case CharacterState::CURIOUS: return Pose::F03;
    case CharacterState::CONFUSED: return Pose::F03;
    case CharacterState::SURPRISED: return Pose::F08;
    case CharacterState::PLAYFUL: return Pose::R04;
    case CharacterState::CELEBRATE:
    case CharacterState::SUCCESS: return Pose::R07;
    case CharacterState::ERROR: return Pose::R09;
    case CharacterState::CANCELLED: return Pose::F11;
    default: return Pose::F01;
  }
}

void CharacterController::requestStatePose(CharacterState state,
                                           uint32_t nowMs) {
  stopClipForCatalog(nowMs);
  const float intensity = state == CharacterState::SURPRISED ||
                                  state == CharacterState::ERROR ||
                                  state == CharacterState::CELEBRATE
                              ? 0.8F : 0.5F;
  motion_.request(poseFor(state), intensity, nowMs);
}

void CharacterController::setState(CharacterState state) {
  if (!valid(state)) return;
  if (isPersistent(state)) setPersistentState(state);
  else playReaction(state);
}

void CharacterController::setPersistentState(CharacterState state) {
  if (!valid(state)) return;
  if (state == CharacterState::SLEEPING) {
    setSleeping();
    return;
  }
  if (!isPersistent(state)) {
    playReaction(state);
    return;
  }
  if (currentState_ == CharacterState::SLEEPING ||
      currentState_ == CharacterState::WAKING) return;
  if (currentState_ == state && !temporary_ && !clipActive()) return;
  persistentState_ = currentState_ = state;
  temporary_ = false;
  manualGaze_ = false;
  stateStartedMs_ = millis();
  requestStatePose(state, stateStartedMs_);
  Serial.printf("[character] %s\n", name(state));
}

void CharacterController::playReaction(CharacterState state) {
  if (!valid(state)) return;
  if (isPersistent(state)) {
    setPersistentState(state);
    return;
  }
  if (state == CharacterState::WAKING) {
    wake();
    return;
  }
  if (currentState_ == CharacterState::SLEEPING ||
      currentState_ == CharacterState::WAKING) return;
  const uint32_t nowMs = millis();
  currentState_ = state;
  temporary_ = true;
  manualGaze_ = false;
  stateStartedMs_ = nowMs;
  requestStatePose(state, nowMs);
  reactionEndsMs_ = nowMs +
      (state == CharacterState::CELEBRATE || state == CharacterState::SUCCESS
           ? kCelebrateReactionMs
           : state == CharacterState::HAPPY ? kHappyReactionMs
                                             : kOrdinaryReactionMs);
  Serial.printf("[character] %s\n", name(state));
}

void CharacterController::previewStyle(CreatureEyeStyle::Id style,
                                       uint32_t holdMs) {
  (void)holdMs;  // A look is an identity setting, independent of an event hold.
  setLook(style);
}

void CharacterController::setLook(CreatureEyeStyle::Id style) {
  if (style >= CreatureEyeStyle::Id::Count) return;
  visualStyle_ = style;
  motion_.setLook(static_cast<uint8_t>(style));
}

void CharacterController::previewPose(FaceMotion::PoseId pose,
                                      float intensity) {
  if (pose >= FaceMotion::PoseId::Count || !std::isfinite(intensity)) return;
  stopClipForCatalog(millis());
  motion_.request(pose, intensity, millis());
}

void CharacterController::setMotionSeed(uint32_t seed) {
  const uint32_t nowMs = millis();
  stopClipForCatalog(nowMs);
  motion_.begin(nowMs, seed);
  motion_.setLook(static_cast<uint8_t>(visualStyle_));
  requestStatePose(currentState_, nowMs);
  lastRenderMs_ = 0;
}

void CharacterController::scrubMotionTransition(
    FaceMotion::PoseId source, FaceMotion::PoseId destination,
    float intensity, uint32_t elapsedMs, uint32_t seed, uint32_t nowMs) {
  if (source >= FaceMotion::PoseId::Count ||
      destination >= FaceMotion::PoseId::Count ||
      !std::isfinite(intensity) || intensity < 0.0F || intensity > 1.0F ||
      elapsedMs > 4000) return;
  clipPlayer_.reset(nowMs);
  pendingSequence_ = MotionClips::SequenceId::Count;
  // Rebuild a deterministic source and clip at 30 ms intervals, anchored so
  // the resulting engine clock equals the live host clock. This is lab-only:
  // no recording, heap allocation, or extra firmware framebuffer is needed.
  const uint32_t base = nowMs - 3000U - elapsedMs;
  motion_.begin(base, seed);
  motion_.setIdleEnabled(false);
  motion_.setLook(static_cast<uint8_t>(visualStyle_));
  for (uint32_t t = 30; t <= 1000; t += 30) motion_.update(base + t);
  motion_.update(base + 1000);
  if (source != FaceMotion::PoseId::F01)
    motion_.request(source, intensity, base + 1000);
  for (uint32_t t = 30; t <= 2000; t += 30)
    motion_.update(base + 1000 + t);
  motion_.update(base + 3000);
  if (destination != source)
    motion_.request(destination, intensity, base + 3000);
  for (uint32_t t = 30; t <= elapsedMs; t += 30)
    motion_.update(base + 3000 + t);
  motion_.update(nowMs);
  motion_.pause(true);
  currentState_ = persistentState_ = CharacterState::IDLE;
  temporary_ = manualGaze_ = false;
  lastActivityMs_ = nowMs;
  drawFrame(nowMs);
}

void CharacterController::notifyActivity(uint32_t nowMs) {
  nowMs = activityTime(nowMs);
  lastActivityMs_ = nowMs;
  if (currentState_ == CharacterState::SLEEPING) wake();
}

void CharacterController::setSleeping() {
  if (currentState_ == CharacterState::SLEEPING) return;
  const uint32_t nowMs = millis();
  stopClipForCatalog(nowMs);
  currentState_ = persistentState_ = CharacterState::SLEEPING;
  temporary_ = false;
  manualGaze_ = false;
  stateStartedMs_ = nowMs;
  lastRenderMs_ = 0;
  motion_.sleep(nowMs);
  Serial.println("[character] SLEEPING");
}

void CharacterController::wake() {
  if (currentState_ == CharacterState::WAKING) return;
  const uint32_t nowMs = millis();
  stopClipForCatalog(nowMs);
  lastActivityMs_ = nowMs;
  currentState_ = CharacterState::WAKING;
  persistentState_ = CharacterState::IDLE;
  temporary_ = true;
  manualGaze_ = false;
  stateStartedMs_ = nowMs;
  lastRenderMs_ = 0;
  motion_.wake(nowMs);
  Serial.println("[character] WAKING");
}

void CharacterController::lookAtNormalized(float x, float y,
                                           uint32_t holdMs) {
  if (clipPlayer_.active() && std::isfinite(x) && std::isfinite(y)) {
    manualGaze_ = true;
    manualGazeEndsMs_ = millis() + holdMs;
    clipPlayer_.setGaze(x, y);
    return;
  }
  if (currentState_ != CharacterState::IDLE || temporary_ ||
      !std::isfinite(x) || !std::isfinite(y)) return;
  const uint32_t nowMs = millis();
  manualGaze_ = true;
  manualGazeEndsMs_ = nowMs + holdMs;
  motion_.lookAt(constrain(x, -1.0F, 1.0F),
                 constrain(y, -1.0F, 1.0F), nowMs);
}

void CharacterController::lookPupilsAtNormalized(float x, float y,
                                                 uint32_t holdMs) {
  lookAtNormalized(x, y, holdMs);
}

void CharacterController::lookAtScreen(int16_t x, int16_t y,
                                       uint32_t holdMs) {
  const auto logical = viewport_.toLogical(x, y);
  lookAtNormalized((logical.x - 240.0F) / 240.0F,
                   (logical.y - 240.0F) / 240.0F,
                   holdMs);
}

void CharacterController::lookCenter() {
  if (clipPlayer_.active()) {
    manualGaze_ = false;
    clipPlayer_.setGaze(0, 0);
    return;
  }
  if (currentState_ != CharacterState::IDLE || temporary_) return;
  manualGaze_ = false;
  motion_.centerGaze(millis());
}

void CharacterController::blink() {
  if (clipActive()) return;  // Clip closure/gaze channels have one owner.
  if (currentState_ == CharacterState::SLEEPING ||
      currentState_ == CharacterState::WAKING) return;
  motion_.blink(millis());
}

void CharacterController::drawFrame(uint32_t nowMs) {
  if (renderSuspended_ || !eyeRenderer_.ready()) return;
  const uint32_t renderStartedUs = micros();
  updateClipLegacyFrame();
  if (clipPlayer_.vectorVisible()) eyeRenderer_.draw(clipPlayer_.frame());
  else eyeRenderer_.draw(motionFrame());
  PerformanceStats::eyeRender(micros() - renderStartedUs);
  lastRenderMs_ = nowMs;
}

void CharacterController::update(uint32_t nowMs) {
  if (!eyeRenderer_.ready()) return;
  if (inactivityTimeoutMs_ != 0 &&
      currentState_ == CharacterState::IDLE && !temporary_ && !clipActive() &&
      reached(nowMs, lastActivityMs_ + inactivityTimeoutMs_)) {
    setSleeping();
  }
  if (currentState_ == CharacterState::WAKING &&
      reached(nowMs, stateStartedMs_ + kWakeMs)) {
    currentState_ = persistentState_ = CharacterState::IDLE;
    temporary_ = false;
    // R10 owns its return to F01 after the overshoot/settle. Do not cut it.
  }
  if (temporary_ && !clipActive() && currentState_ != CharacterState::WAKING &&
      motion_.diagnostics().target == poseFor(persistentState_) &&
      reached(nowMs, stateStartedMs_ + 500)) {
    // The engine has begun a reaction's authored return; keep the semantic
    // state synchronized without submitting a duplicate interrupting clip.
    temporary_ = false;
    currentState_ = persistentState_;
  }
  if (temporary_ && !clipActive() && currentState_ != CharacterState::WAKING &&
      reached(nowMs, reactionEndsMs_)) {
    temporary_ = false;
    currentState_ = persistentState_;
    requestStatePose(currentState_, nowMs);
  }
  if (manualGaze_ && (currentState_ == CharacterState::IDLE || clipActive()) &&
      reached(nowMs, manualGazeEndsMs_)) lookCenter();

  // Time is sampled for every simulation/hardware tick; raster work stays
  // bounded by the display refresh period and can be skipped by overlays.
  motion_.update(nowMs);
  if (pendingSequence_ != MotionClips::SequenceId::Count &&
      !sequencePaused_ && reached(nowMs, sequenceReadyMs_))
    beginPreparedSequence(nowMs);
  const bool wasClipActive = clipPlayer_.active();
  const auto previousClipPhase = clipPlayer_.diagnostics().phase;
  clipPlayer_.update(nowMs);
  // A touch gesture is a flourish, not a new resting face. The player holds
  // a finished clip's last pose, so after a short beat the gesture takes the
  // covered exit back to the living face (motion resumes below).
  if (gestureClip_ != MotionClips::ClipId::Count) {
    const auto gesture = clipPlayer_.diagnostics();
    if (!clipPlayer_.active() || gesture.id != gestureClip_) {
      gestureClip_ = MotionClips::ClipId::Count;
      gestureHeldSinceMs_ = 0;
    } else if (gesture.finished && !gesture.paused &&
               gesture.phase == MotionClips::Phase::Holding) {
      if (gestureHeldSinceMs_ == 0) {
        gestureHeldSinceMs_ = nowMs == 0 ? 1 : nowMs;
      } else if (reached(nowMs, gestureHeldSinceMs_ + 240)) {
        clipPlayer_.cancel(nowMs);
        gestureHeldSinceMs_ = 0;
      }
    }
  }
  const auto clipPhase = clipPlayer_.diagnostics().phase;
  if ((previousClipPhase == MotionClips::Phase::CloseExit ||
       previousClipPhase == MotionClips::Phase::OpenLegacy) &&
      clipPhase != MotionClips::Phase::CloseExit &&
      clipPhase != MotionClips::Phase::OpenLegacy && clipPlayer_.active()) {
    // A looping example has returned to its requested catalog pose and is
    // entering its next first clip. Recapture that exact catalog frame and
    // transfer ownership back to the player before it moves again.
    clipLegacySource_ = motion_.frame();
    motion_.pause(true);
  }
  if ((clipPlayer_.diagnostics().phase == MotionClips::Phase::OpenLegacy &&
       !clipPlayer_.diagnostics().paused) ||
      (wasClipActive && !clipPlayer_.active())) motion_.pause(false);
  updateClipLegacyFrame();
  if (!renderSuspended_ &&
      (lastRenderMs_ == 0 || nowMs - lastRenderMs_ >= kEyeFrameMs)) {
    PerformanceStats::animationUpdate();
    drawFrame(nowMs);
  }
}

void CharacterController::handleDevelopmentTap(uint16_t x, uint16_t y) {
  const bool wasSleeping = isSleeping();
  notifyActivity();
  if (wasSleeping) return;
  const auto logical = viewport_.toLogical(x, y);
  const uint8_t column = min<uint8_t>(logical.x / (480 / 3), 2);
  const uint8_t row = min<uint8_t>(logical.y / (480 / 4), 3);
  setState(static_cast<CharacterState>(row * 3 + column));
}

const FaceMotion::Frame& CharacterController::motionFrame() const {
  return clipPlayer_.active() && !clipPlayer_.vectorVisible()
      ? clipLegacyFrame_ : motion_.frame();
}

void CharacterController::updateClipLegacyFrame() {
  if (!clipPlayer_.active() || clipPlayer_.vectorVisible()) return;
  const auto diagnostics = clipPlayer_.diagnostics();
  clipLegacyFrame_ = diagnostics.phase == MotionClips::Phase::CloseLegacy
      ? clipLegacySource_ : motion_.frame();
  const float opening = diagnostics.legacyOpening;
  clipLegacyFrame_.effects = FaceMotion::NoEffect;
  if (opening <= 0) {
    clipLegacyFrame_.eyeCount = 0;
    return;
  }
  for (uint8_t i = 0; i < clipLegacyFrame_.eyeCount; ++i) {
    auto& eye = clipLegacyFrame_.eyes[i];
    eye.height *= opening;
    eye.pupilY *= opening;
    eye.pupilHeight *= opening;
  }
  // As with the ordinary engine's topology gate, pupils become fully covered
  // before the geometric family or motif changes.
  clipLegacyFrame_.coverage = 1 - opening;
}

void CharacterController::render240Row(uint16_t physicalY,
                                        lv_color_t* output240,
                                        bool maskRound) const {
  if (clipPlayer_.vectorVisible())
    VectorFace::render240RowAntialiased(clipPlayer_.frame(), physicalY,
                                       output240, maskRound);
  else
    FaceMotionRaster::render240Row(motionFrame(), physicalY, output240);
}

bool CharacterController::clipActive() const {
  return pendingSequence_ != MotionClips::SequenceId::Count || clipPlayer_.active();
}

MotionClips::PlayerDiagnostics CharacterController::clipDiagnostics() const {
  auto result = clipPlayer_.diagnostics();
  if (pendingSequence_ != MotionClips::SequenceId::Count) {
    result.phase = MotionClips::Phase::PrepareCatalog;
    result.sequence = pendingSequence_;
    result.sequenceStep = 0;
    result.active = true;
    result.playing = !sequencePaused_;
    result.paused = sequencePaused_;
    result.finished = false;
    result.parameters = pendingSequenceParameters_;
  }
  return result;
}

void CharacterController::stopClipForCatalog(uint32_t nowMs) {
  const bool wasOwned = clipActive();
  gestureClip_ = MotionClips::ClipId::Count;
  gestureHeldSinceMs_ = 0;
  pendingSequence_ = MotionClips::SequenceId::Count;
  sequencePaused_ = false;
  if (clipPlayer_.active()) clipPlayer_.cancel(nowMs);
  if (wasOwned) motion_.pause(false);
}

bool CharacterController::playClip(MotionClips::ClipId id,
                                    const MotionClips::Parameters& parameters) {
  if (id >= MotionClips::ClipId::Count) return false;
  const uint32_t nowMs = millis();
  // Only playGesture() marks a clip as a gesture that returns by itself.
  gestureClip_ = MotionClips::ClipId::Count;
  gestureHeldSinceMs_ = 0;
  pendingSequence_ = MotionClips::SequenceId::Count;
  sequencePaused_ = false;
  motion_.update(nowMs);
  updateClipLegacyFrame();
  if (!clipPlayer_.vectorVisible()) clipLegacySource_ = motionFrame();
  if (!clipPlayer_.start(id, parameters, nowMs)) return false;
  motion_.pause(true);
  lastActivityMs_ = nowMs;
  manualGaze_ = false;
  drawFrame(nowMs);
  return true;
}

bool CharacterController::playClipSequence(
    MotionClips::SequenceId sequence, const MotionClips::Parameters& parameters) {
  if (sequence >= MotionClips::SequenceId::Count) return false;
  const uint32_t nowMs = millis();
  stopClipForCatalog(nowMs);
  currentState_ = persistentState_ =
      sequence == MotionClips::SequenceId::PurpleFlowerCurious
          ? CharacterState::CURIOUS
          : sequence == MotionClips::SequenceId::SurprisedRetreat
              ? CharacterState::SURPRISED : CharacterState::IDLE;
  temporary_ = manualGaze_ = false;
  motion_.request(poseFor(currentState_),
                  currentState_ == CharacterState::SURPRISED ? .8F : .5F, nowMs);
  pendingSequence_ = sequence;
  pendingSequenceParameters_ = parameters;
  // These four examples explicitly request an initial catalog pose. Normal
  // independent clips use their actual displayed pose directly and never
  // insert HOME. The visible lead-in also proves CURIOUS -> flower -> CURIOUS.
  sequenceReadyMs_ = nowMs + 1100;
  sequencePaused_ = false;
  lastActivityMs_ = nowMs;
  return true;
}

void CharacterController::beginPreparedSequence(uint32_t nowMs) {
  const auto sequence = pendingSequence_;
  pendingSequence_ = MotionClips::SequenceId::Count;
  clipLegacySource_ = motion_.frame();
  const bool loop = clipPlayer_.diagnostics().loop;
  clipPlayer_.reset(nowMs);
  clipPlayer_.setLoop(loop);
  clipPlayer_.startSequence(sequence, pendingSequenceParameters_, nowMs);
  motion_.pause(true);
  drawFrame(nowMs);
}

bool CharacterController::playGesture(CharacterGesture gesture) {
  using Clip = MotionClips::ClipId;
  if (currentState_ == CharacterState::SLEEPING ||
      currentState_ == CharacterState::WAKING) return false;
  // Poke: happy arcs peeking open. Pet: pink arcs with floating hearts.
  // Too many pokes: orbiting pupils. Each keeps its measured source colours.
  const Clip clip = gesture == CharacterGesture::Love ? Clip::FloatingHeartsLove
      : gesture == CharacterGesture::Dizzy ? Clip::DizzyPupilOrbit
      : gesture == CharacterGesture::Wink ? Clip::Wink
      : Clip::HappyArcPeekWake;
  if (!playClip(clip)) {
    playReaction(fallbackState(gesture));
    return true;
  }
  gestureClip_ = clip;
  return true;
}

bool CharacterController::isPlayingGesture() const {
  return gestureClip_ != MotionClips::ClipId::Count && clipPlayer_.active() &&
         clipPlayer_.diagnostics().id == gestureClip_;
}

bool CharacterController::triggerAnimation(
    MotionClips::SemanticEvent event, const MotionClips::Parameters& parameters) {
  using Event = MotionClips::SemanticEvent;
  using Clip = MotionClips::ClipId;
  switch (event) {
    case Event::Startled:
    case Event::NearbyObjectApproach: {
      auto resolved = parameters;
      if (resolved.palette == MotionClips::PaletteId::Source &&
          !clipPlayer_.vectorVisible()) {
        // A semantic retreat inherits the displayed catalog identity. The
        // independent Lab SOURCE preset still enters the accepted source
        // palette through playClip(), and explicit color choices win here.
        CreatureEyeStyle::RenderParams look;
        look.from = look.to = static_cast<CreatureEyeStyle::Id>(motionFrame().lookId);
        const auto style = CreatureEyeStyle::resolve(look);
        const auto rgb565 = [](CreatureEyeStyle::Rgb rgb) {
          return static_cast<uint16_t>(((rgb.r >> 3) << 11) |
              ((rgb.g >> 2) << 5) | (rgb.b >> 3));
        };
        resolved.palette = MotionClips::PaletteId::Custom;
        resolved.customPalette.colors[static_cast<uint8_t>(MotionClips::ColorRole::Background)] = 0;
        resolved.customPalette.colors[static_cast<uint8_t>(MotionClips::ColorRole::Primary)] = rgb565(style.outer);
        resolved.customPalette.colors[static_cast<uint8_t>(MotionClips::ColorRole::Secondary)] = rgb565(style.outer);
        resolved.customPalette.colors[static_cast<uint8_t>(MotionClips::ColorRole::Pupil)] = rgb565(style.pupil);
        resolved.customPalette.colors[static_cast<uint8_t>(MotionClips::ColorRole::Accent)] = rgb565(style.pupil);
        resolved.customPalette.colors[static_cast<uint8_t>(MotionClips::ColorRole::Effect)] = rgb565(style.outer);
      }
      return playClip(Clip::RetreatGesture, resolved);
    }
    case Event::Curious: return playClip(Clip::AttentionRetreat, parameters);
    case Event::Playful: return playClip(Clip::FlowerEnter, parameters);
    case Event::Success: return playClip(Clip::HeartPulse, parameters);
    case Event::SocialContact: return playClip(Clip::HeartContinuation, parameters);
  }
  return false;
}

void CharacterController::pauseClip(bool paused) {
  const uint32_t nowMs = millis();
  if (pendingSequence_ != MotionClips::SequenceId::Count) {
    if (paused && !sequencePaused_) sequencePausedMs_ = nowMs;
    if (!paused && sequencePaused_) sequenceReadyMs_ += nowMs - sequencePausedMs_;
    sequencePaused_ = paused;
    motion_.pause(paused);
  }
  clipPlayer_.pause(paused, nowMs);
  if (pendingSequence_ == MotionClips::SequenceId::Count && clipPlayer_.active())
    motion_.pause(paused || clipPlayer_.diagnostics().phase != MotionClips::Phase::OpenLegacy);
  updateClipLegacyFrame();
}

void CharacterController::restartClip() {
  const uint32_t nowMs = millis();
  if (pendingSequence_ != MotionClips::SequenceId::Count) {
    sequenceReadyMs_ = nowMs + 1100;
    sequencePausedMs_ = nowMs;
    return;
  }
  updateClipLegacyFrame();
  if (!clipPlayer_.vectorVisible()) clipLegacySource_ = motionFrame();
  clipPlayer_.restart(nowMs);
  if (clipPlayer_.active()) motion_.pause(true);
  drawFrame(nowMs);
}

void CharacterController::finishClip() {
  const uint32_t nowMs = millis();
  if (pendingSequence_ != MotionClips::SequenceId::Count)
    beginPreparedSequence(nowMs);
  clipPlayer_.finish(nowMs);
  drawFrame(nowMs);
}

void CharacterController::cancelClip() {
  const uint32_t nowMs = millis();
  stopClipForCatalog(nowMs);
  drawFrame(nowMs);
}

void CharacterController::stepClip(uint32_t deltaUs) {
  const uint32_t nowMs = millis();
  if (pendingSequence_ != MotionClips::SequenceId::Count) {
    const uint32_t anchor = sequencePaused_ ? sequencePausedMs_ : nowMs;
    const int32_t remaining = static_cast<int32_t>(sequenceReadyMs_ - anchor);
    sequencePaused_ = true;
    sequencePausedMs_ = nowMs;
    motion_.step(nowMs);
    if (remaining <= static_cast<int32_t>(deltaUs / 1000))
      beginPreparedSequence(nowMs);
    else sequenceReadyMs_ = nowMs + remaining - deltaUs / 1000;
  }
  clipPlayer_.step(deltaUs);
  drawFrame(nowMs);
}

bool CharacterController::seekClip(uint32_t localUs) {
  const uint32_t nowMs = millis();
  if (!canSeekClip() || !clipPlayer_.seek(localUs, nowMs)) return false;
  motion_.pause(true);
  drawFrame(nowMs);
  return true;
}

void CharacterController::closeEyes(FaceMotion::Closure closure) {
  const uint32_t nowMs = millis();
  stopClipForCatalog(nowMs);
  motion_.close(closure, nowMs);
}
