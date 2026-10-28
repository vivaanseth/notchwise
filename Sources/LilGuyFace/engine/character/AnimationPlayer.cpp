#include "AnimationPlayer.h"

#include <cmath>

namespace MotionClips {
namespace {
constexpr uint32_t kBlendUs = 140000;
constexpr uint32_t kGateHalfUs = 80000;
constexpr uint8_t kMaximumSequenceSteps = 4;
struct SequenceStep { ClipId id; uint32_t holdUs; };
constexpr SequenceStep kSequences[4][kMaximumSequenceSteps] = {
    {{ClipId::AttentionShift, 0}, {ClipId::FlowerEnter, 0},
     {ClipId::FlowerHold, 750000}, {ClipId::SoftExit, 0}},
    {{ClipId::FlowerEnter, 0}, {ClipId::FlowerHold, 400000},
     {ClipId::RetreatGesture, 500000}, {ClipId::SoftExit, 0}},
    {{ClipId::DotRise, 0}, {ClipId::RetreatGesture, 0},
     {ClipId::Count, 0}, {ClipId::Count, 0}},
    {{ClipId::FlowerEnter, 0}, {ClipId::FlowerHold, 1000000},
     {ClipId::SoftExit, 0}, {ClipId::Count, 0}}};

float clamp(float value, float lo, float hi) {
  return value < lo ? lo : value > hi ? hi : value;
}

void squash(const VectorFace::Frame& source, float opening,
             VectorFace::Frame& result) {
  result = source;
  if (opening <= 0) {
    result.shapeCount = 0;
    return;
  }
  for (uint8_t s = 0; s < result.shapeCount; ++s) {
    auto& shape = result.shapes[s];
    const auto& original = source.shapes[s];
    int root = s;
    for (uint8_t depth = 0; depth < source.shapeCount; ++depth) {
      const int parent = source.shapes[root].clipShape;
      if (parent < 0 || parent >= root) break;
      root = parent;
    }
    const float originY = source.shapes[root].centerY;
    shape.centerY = originY + (original.centerY - originY) * opening;
    shape.height = original.height * opening;
    for (uint8_t p = 0; p < shape.vertexCount; ++p)
      shape.vertices[p].y = originY +
          (original.vertices[p].y - originY) * opening;
  }
  // Compressing around an off-center eye can move its wide outer edge
  // farther from the panel center. Keep authored gate frames inside the
  // round display, including antialias coverage, without changing the
  // fully open measured pose at the gate's endpoint.
  if (opening < 1) enforceRoundSafety(result);
}

uint16_t blendColor(uint16_t a, uint16_t b, float amount) {
  const auto part = [&](uint16_t mask, unsigned shift) {
    const int start = (a >> shift) & mask;
    const int end = (b >> shift) & mask;
    return static_cast<uint16_t>(start + (end - start) * amount + .5F);
  };
  return static_cast<uint16_t>((part(31, 11) << 11) |
                               (part(63, 5) << 5) | part(31, 0));
}

void blend(const VectorFace::Frame& source, float amount,
            VectorFace::Frame& target) {
  for (uint8_t s = 0; s < target.shapeCount; ++s) {
    const auto& from = source.shapes[s];
    auto& to = target.shapes[s];
    const auto lerp = [&](float a, float b) { return a + (b - a) * amount; };
    to.centerX = lerp(from.centerX, to.centerX);
    to.centerY = lerp(from.centerY, to.centerY);
    to.width = lerp(from.width, to.width);
    to.height = lerp(from.height, to.height);
    to.rotation = lerp(from.rotation, to.rotation);
    to.color565 = blendColor(from.color565, to.color565, amount);
    for (uint8_t p = 0; p < to.vertexCount; ++p) {
      to.vertices[p].x = lerp(from.vertices[p].x, to.vertices[p].x);
      to.vertices[p].y = lerp(from.vertices[p].y, to.vertices[p].y);
    }
  }
}
}  // namespace

const char* phaseName(Phase phase) {
  constexpr const char* names[] = {"inactive", "close catalog", "blend entry",
      "close vector", "open vector", "playing", "held pose", "close exit",
      "open catalog", "prepare catalog"};
  const auto index = static_cast<uint8_t>(phase);
  return index < sizeof(names) / sizeof(names[0]) ? names[index] : "unknown";
}

const char* sequenceName(SequenceId sequence) {
  constexpr const char* names[] = {"Blue Flower", "Flower Retreat",
      "Surprised Retreat", "Purple Flower Curious"};
  const auto index = static_cast<uint8_t>(sequence);
  return index < sizeof(names) / sizeof(names[0]) ? names[index] : "none";
}

void Player::reset(uint32_t nowMs) {
  phase_ = Phase::Inactive;
  sequence_ = SequenceId::Count;
  lastMs_ = nowMs;
  localUs_ = phaseUs_ = 0;
  paused_ = loop_ = completed_ = returnToLegacy_ = finishAfterEntry_ = false;
  subMicrosecond_ = 0;
  current_.frame.shapeCount = 0;
}

bool Player::start(ClipId id, const Parameters& parameters, uint32_t nowMs,
                    const VectorFace::Frame* current, FaceKind currentFace) {
  if (id >= ClipId::Count) return false;
  update(nowMs);
  if (!current && vectorVisible()) {
    current = &current_.frame;
    currentFace = current_.face;
  }
  sequence_ = SequenceId::Count;
  sequenceStep_ = 0;
  lastMs_ = nowMs;
  paused_ = false;
  return beginClip(id, parameters, current, currentFace);
}

bool Player::beginClip(ClipId id, const Parameters& parameters,
                        const VectorFace::Frame* current, FaceKind face) {
  if (id >= ClipId::Count) return false;
  // A zero-shape vector frame is the fully covered midpoint of a legal
  // transition. It is still vector-owned; treating it as catalog ownership
  // would momentarily resurrect a stale catalog face during interruption.
  const bool hadVector = current != nullptr;
  if (hadVector) entry_ = *current;
  else entry_.shapeCount = 0;
  held_ = entry_;
  id_ = id;
  parameters_ = boundedParameters(id, parameters);
  durationUs_ = playbackDurationUs(id, parameters_);
  // sample()/playbackDurationUs include the optional held extension already.
  holdUs_ = 0;
  sourceFace_ = face;
  targetFace_ = definition(id).endsIn;
  localUs_ = phaseUs_ = 0;
  subMicrosecond_ = 0;
  gateHalfUs_ = kGateHalfUs;
  completed_ = returnToLegacy_ = finishAfterEntry_ = false;

  if (id == ClipId::SoftExit) {
    // This is an authored transition, never described as measured source
    // motion. The controller supplies the requested catalog destination.
    gateHalfUs_ = durationUs_ / 2;
    returnToLegacy_ = true;
    phase_ = hadVector ? Phase::CloseExit : Phase::CloseLegacy;
    paintPhase();
    return true;
  }

  if (id == ClipId::RetreatGesture &&
      (!hadVector || !applyRetreat(held_, 0, parameters_, current_))) {
    // A gesture cannot deform arbitrary particle topologies. Resolve through
    // the same legal entry gate to its compatible measured two-eye baseline.
    if (!sample(ClipId::RetreatGesture, 0, parameters_, current_)) return false;
    held_ = current_.frame;
    sourceFace_ = FaceKind::Attentive;
  }
  if (!evaluate(0)) return false;
  const bool canBlend = hadVector && compatible(entry_, current_.frame);
  phase_ = !hadVector ? Phase::CloseLegacy
                     : canBlend ? Phase::BlendEntry : Phase::CloseVector;
  paintPhase();
  return true;
}

bool Player::startSequence(SequenceId sequence, const Parameters& parameters,
                            uint32_t nowMs) {
  if (sequence >= SequenceId::Count) return false;
  update(nowMs);
  sequence_ = sequence;
  sequenceStep_ = 0;
  sequenceParameters_ = parameters;
  if (sequence == SequenceId::BlueFlower)
    sequenceParameters_.palette = PaletteId::Blue;
  if (sequence == SequenceId::PurpleFlowerCurious) {
    sequenceParameters_.palette = PaletteId::Purple;
    sequenceParameters_.gazeX = -.55F;
    sequenceParameters_.gazeY = -.12F;
  }
  paused_ = false;
  lastMs_ = nowMs;
  return beginSequenceStep();
}

bool Player::beginSequenceStep() {
  if (sequence_ >= SequenceId::Count || sequenceStep_ >= kMaximumSequenceSteps)
    return false;
  const auto& step = kSequences[static_cast<uint8_t>(sequence_)][sequenceStep_];
  if (step.id == ClipId::Count) return false;
  Parameters parameters = sequenceParameters_;
  parameters.holdUs = step.holdUs > parameters.holdUs
                          ? step.holdUs : parameters.holdUs;
  const auto* source = vectorVisible() ? &current_.frame : nullptr;
  return beginClip(step.id, parameters, source, current_.face);
}

bool Player::evaluate(uint32_t localUs) {
  const bool result = id_ == ClipId::RetreatGesture
      ? applyRetreat(held_, localUs, parameters_, current_)
      : sample(id_, localUs, parameters_, current_);
  if (result) {
    current_.bounds = VectorFace::measureBounds(current_.frame);
    if (id_ == ClipId::RetreatGesture) current_.face = sourceFace_;
  }
  return result;
}

void Player::paintPhase() {
  switch (phase_) {
    case Phase::CloseLegacy:
    case Phase::OpenLegacy:
    case Phase::Inactive:
    case Phase::PrepareCatalog:
      break;
    case Phase::BlendEntry:
      evaluate(localUs_);
      blend(entry_, clamp(static_cast<float>(phaseUs_) / kBlendUs, 0, 1),
             current_.frame);
      break;
    case Phase::CloseVector:
    case Phase::CloseExit:
      squash(entry_, 1 - clamp(static_cast<float>(phaseUs_) / gateHalfUs_, 0, 1),
              current_.frame);
      break;
    case Phase::OpenVector:
      evaluate(localUs_);
      // held_ is the additive gesture's immutable baseline. entry_ is free
      // to hold this freshly sampled destination while it reopens.
      entry_ = current_.frame;
      squash(entry_, clamp(static_cast<float>(phaseUs_) / gateHalfUs_, 0, 1),
              current_.frame);
      break;
    case Phase::Playing:
    case Phase::Holding:
      evaluate(localUs_);
      break;
  }
  current_.bounds = VectorFace::measureBounds(current_.frame);
}

void Player::nextPhase() {
  phaseUs_ = 0;
  switch (phase_) {
    case Phase::CloseLegacy:
    case Phase::CloseVector:
      phase_ = returnToLegacy_ ? Phase::OpenLegacy : Phase::OpenVector;
      break;
    case Phase::BlendEntry:
    case Phase::OpenVector:
      phase_ = finishAfterEntry_ ? Phase::Holding : Phase::Playing;
      completed_ = finishAfterEntry_;
      break;
    case Phase::Playing:
      phase_ = Phase::Holding;
      completed_ = true;
      break;
    case Phase::Holding:
      if (sequence_ != SequenceId::Count) {
        if (sequenceStep_ + 1 < kMaximumSequenceSteps &&
            kSequences[static_cast<uint8_t>(sequence_)][sequenceStep_ + 1].id !=
                ClipId::Count) {
          ++sequenceStep_;
          beginSequenceStep();
          break;
        }
        if (loop_) {
          sequenceStep_ = 0;
          beginSequenceStep();
          break;
        }
      } else if (loop_) {
        if (id_ == ClipId::RetreatGesture) restartGesture();
        else beginClip(id_, parameters_, &current_.frame, current_.face);
      }
      break;
    case Phase::CloseExit:
      phase_ = Phase::OpenLegacy;
      break;
    case Phase::OpenLegacy:
      phase_ = Phase::Inactive;
      completed_ = true;
      if (loop_ && sequence_ != SequenceId::Count) {
        sequenceStep_ = 0;
        beginSequenceStep();
      }
      break;
    case Phase::Inactive:
    case Phase::PrepareCatalog: break;
  }
  paintPhase();
}

void Player::advance(uint32_t elapsedUs) {
  // Bounded iteration also bounds an unexpectedly late tick. Once there is
  // no next phrase, the final pose remains owned and held without drift.
  for (uint8_t iteration = 0; iteration < 64 && active(); ++iteration) {
    uint32_t phaseDuration = gateHalfUs_;
    if (phase_ == Phase::BlendEntry) phaseDuration = kBlendUs;
    if (phase_ == Phase::Playing) phaseDuration = durationUs_;
    if (phase_ == Phase::Holding) {
      const bool next = sequence_ != SequenceId::Count &&
          sequenceStep_ + 1 < kMaximumSequenceSteps &&
          kSequences[static_cast<uint8_t>(sequence_)][sequenceStep_ + 1].id !=
              ClipId::Count;
      if (!next && !loop_) { paintPhase(); break; }
      phaseDuration = holdUs_;
    }
    const uint32_t remaining = phaseDuration > phaseUs_
                                   ? phaseDuration - phaseUs_ : 0;
    const uint32_t take = elapsedUs < remaining ? elapsedUs : remaining;
    phaseUs_ += take;
    if (phase_ == Phase::Playing) localUs_ = phaseUs_;
    elapsedUs -= take;
    paintPhase();
    if (phaseUs_ >= phaseDuration) nextPhase();
    else break;
    if (!elapsedUs) break;
  }
}

void Player::update(uint32_t nowMs) {
  const uint32_t deltaMs = nowMs - lastMs_;
  lastMs_ = nowMs;
  if (!active() || paused_ || !deltaMs) return;
  // A delayed OS/display tick must not cause minutes of work. Ten seconds
  // advances every non-looping sequence to its deterministic held result.
  const double scaled = (deltaMs > 10000 ? 10000 : deltaMs) * 1000.0 * rate_ +
                        subMicrosecond_;
  const auto elapsed = static_cast<uint32_t>(scaled);
  subMicrosecond_ = scaled - elapsed;
  advance(elapsed);
}

void Player::pause(bool paused, uint32_t nowMs) {
  update(nowMs);
  paused_ = paused;
}

void Player::step(uint32_t deltaUs) {
  paused_ = true;
  advance(deltaUs > 1000000 ? 1000000 : deltaUs);
}

bool Player::seek(uint32_t localUs, uint32_t nowMs) {
  if (!canSeek() || localUs > durationUs_) return false;
  lastMs_ = nowMs;
  localUs_ = localUs;
  completed_ = localUs == durationUs_;
  phase_ = completed_ ? Phase::Holding : Phase::Playing;
  phaseUs_ = completed_ ? 0 : localUs;
  paused_ = true;
  finishAfterEntry_ = false;
  subMicrosecond_ = 0;
  paintPhase();
  return true;
}

void Player::restart(uint32_t nowMs) {
  const bool wasPaused = paused_;
  if (sequence_ != SequenceId::Count) {
    const SequenceId sequence = sequence_;
    const Parameters parameters = sequenceParameters_;
    startSequence(sequence, parameters, nowMs);
  } else if (id_ == ClipId::RetreatGesture && active()) {
    update(nowMs);
    restartGesture();
  } else {
    const ClipId id = id_;
    const Parameters parameters = parameters_;
    start(id, parameters, nowMs);
  }
  paused_ = wasPaused;
}

void Player::restartGesture() {
  // The input face is captured once per instance. Loop/restart replays that
  // same displacement; it must not shrink/translate the prior result again.
  const bool visible = vectorVisible();
  if (visible) entry_ = current_.frame;
  else entry_.shapeCount = 0;
  localUs_ = phaseUs_ = 0;
  completed_ = finishAfterEntry_ = returnToLegacy_ = false;
  evaluate(0);
  phase_ = !visible ? Phase::CloseLegacy
      : compatible(entry_, current_.frame) ? Phase::BlendEntry : Phase::CloseVector;
  paintPhase();
}

void Player::finish(uint32_t nowMs) {
  update(nowMs);
  if (!active() || returnToLegacy_) return;
  // Finishing also resolves topology through a gate; it never snaps from a
  // transient flower fragment to a final face or resets to HOME.
  const bool wasVector = vectorVisible();
  const uint32_t coveredUs = phase_ == Phase::CloseLegacy ? phaseUs_ : 0;
  if (wasVector) entry_ = current_.frame;
  else entry_.shapeCount = 0;
  localUs_ = durationUs_;
  finishAfterEntry_ = true;
  evaluate(localUs_);
  phaseUs_ = wasVector ? 0 : coveredUs;
  phase_ = wasVector
      ? compatible(entry_, current_.frame) ? Phase::BlendEntry : Phase::CloseVector
      : Phase::CloseLegacy;
  paintPhase();
}

void Player::cancel(uint32_t nowMs) {
  update(nowMs);
  if (!active()) return;
  const bool visible = vectorVisible();
  if (visible) entry_ = current_.frame;
  returnToLegacy_ = true;
  sequence_ = SequenceId::Count;
  loop_ = paused_ = false;
  // A legacy entry may itself begin from a previously half-closed catalog
  // snapshot. Finish that close using its exact captured geometry before
  // reopening the destination; reversing its relative opening against the
  // full catalog face would produce an immediate height jump.
  if (!visible) { paintPhase(); return; }
  phase_ = Phase::CloseExit;
  gateHalfUs_ = kGateHalfUs;
  phaseUs_ = 0;
  paintPhase();
}

void Player::setRate(float rate) {
  if (std::isfinite(rate)) rate_ = clamp(rate, .25F, 1.0F);
}

void Player::setGaze(float x, float y) {
  if (!std::isfinite(x) || !std::isfinite(y)) return;
  parameters_.gazeX = x;
  parameters_.gazeY = y;
  parameters_ = boundedParameters(id_, parameters_);
  paintPhase();
}

bool Player::vectorVisible() const {
  return active() && phase_ != Phase::CloseLegacy && phase_ != Phase::OpenLegacy;
}

float Player::legacyOpening() const {
  if (phase_ == Phase::CloseLegacy)
    return 1 - clamp(static_cast<float>(phaseUs_) / gateHalfUs_, 0, 1);
  if (phase_ == Phase::OpenLegacy)
    return clamp(static_cast<float>(phaseUs_) / gateHalfUs_, 0, 1);
  return active() ? 0 : 1;
}

PlayerDiagnostics Player::diagnostics() const {
  PlayerDiagnostics result;
  result.id = id_;
  result.phase = phase_;
  result.sourceFace = sourceFace_;
  result.targetFace = targetFace_;
  result.localUs = localUs_;
  result.durationUs = durationUs_;
  result.paused = paused_;
  const bool hasNext = sequence_ != SequenceId::Count &&
      sequenceStep_ + 1 < kMaximumSequenceSteps &&
      kSequences[static_cast<uint8_t>(sequence_)][sequenceStep_ + 1].id !=
          ClipId::Count;
  result.playing = active() && !paused_ &&
      (phase_ != Phase::Holding || hasNext || loop_);
  result.finished = completed_;
  result.active = active();
  result.vectorVisible = vectorVisible();
  result.legacyOpening = legacyOpening();
  result.loop = loop_;
  result.rate = rate_;
  result.sequence = sequence_;
  result.sequenceStep = sequenceStep_;
  result.parameters = parameters_;
  return result;
}
}  // namespace MotionClips
