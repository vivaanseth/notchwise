#pragma once

#include <cstddef>
#include <cstdint>
#include "VectorFaceRaster.h"

// Source-derived geometry has clip-local clocks. Palette, behavior and the
// developer reference sequence are independent of these procedural tracks.
namespace MotionClips {
enum class ClipId : uint8_t {
  OvalHold, AttentionShift, DownLeftTurn, PaletteClosure, FlowerEnter,
  FlowerHold, DotRise, HeartPulse, HeartContinuation, BlinkRecovery,
  GazeHold, Wink, PostWinkSettle, AttentionRetreat,
  RetreatGesture, SoftExit,
  // Existing IDs 0–15 are persisted by controls and the reference showcase.
  HeartStreamFlatten = 16, BoltPupilPulse = 17, SmileStreakBlink = 18,
  DizzyPupilOrbit = 19, SquashCloseRise = 20, AngryGlare = 21,
  ColorSwapBlink = 22, WarmUpColorShift = 23, LongClosedBlink = 24,
  WakeUpPupilDrop = 25, SlowBlinkPupilDrop = 26, QuickBlinkPupilDrop = 27,
  StartleNervousDrift = 28, GrumpyReopen = 29, SquintShut = 30,
  OrangeToWhiteWake = 31, TiltedPairBlink = 32, HappyArcPeekWake = 33,
  HeartEyesFloatAway = 34, SadDroopWake = 35, SadSlump = 36,
  SweatDropWorry = 37, DizzySpiralWobble = 38, SleepyHalfLidWake = 39,
  FlowerToOrangeBlink = 40, CreamFlowerBloom = 41, PeekUpPupilDrop = 42,
  YellowToWhiteBlink = 43, SadEyesSlideOut = 44, SadEyesRiseIn = 45,
  FloatingHeartsLove = 46, PinkArcsToGreenWake = 47, ScowlBlinkSoften = 48,
  GreenBlinkGrowWide = 49, SquintOpenLookLeft = 50, BlinkToHalfLidsUp = 51,
  SleepyLidsToSad = 52, RedEyesTiltDroop = 53, HeatSweatShower = 54, HeatCoolDownOrange = 55,
  BlinkIntoSmug = 56, BlinkTallLookDownLeft = 57, SadBloomYellowFlowers = 58,
  AnnoyedBlinkSideEye = 59, TiltBlinkStraighten = 60, HeartEyesWake = 61,
  CatSlitPupilShift = 62, EyesWrapAround = 63, GrumpyBlinkSkeptical = 64,
  CyanBlinkPupilsShrink = 65,
  Count
};
// Appended values only: existing FaceKind numbers are part of generated data.
enum class FaceKind : uint8_t { Any, Oval, Closed, Flower, Dots, Hearts, HotOval, Attentive, Angry };
enum class PaletteId : uint8_t { Source, Blue, Mint, Purple, Warm, Custom, Count };
enum class ColorRole : uint8_t { Background, Primary, Secondary, Pupil, Accent, Effect, Count };
struct Palette { uint16_t colors[6]{}; };
enum ParameterSupport : uint16_t {
  Intensity = 1, Gaze = 2, Mirror = 4, Hold = 8, Duration = 16,
  Effects = 32, Appearance = 64
};
enum ChannelOwnership : uint16_t {
  Shape = 1, Translation = 2, Dimensions = 4, Spacing = 8,
  MeasuredPupils = 16, ParametricGaze = 32, DecorativeEffects = 64
};
enum class TrackKind : uint8_t { Absolute, Additive, Transition };
struct Parameters {
  PaletteId palette = PaletteId::Source;
  Palette customPalette{};
  float intensity = 1.0F;
  float gazeX = 0.0F, gazeY = 0.0F;
  uint32_t durationUs = 0;  // zero selects the measured duration
  uint32_t holdUs = 0;      // bounded optional extension after natural end
  bool mirror = false;
  bool effects = true;
};
struct Definition {
  ClipId id;
  const char* name;
  FaceKind startsIn, endsIn;
  TrackKind kind;
  uint32_t durationUs, minimumDurationUs, maximumDurationUs, maximumHoldUs;
  uint16_t parameters, ownership;
  uint16_t firstKey, keyCount;
  // Provenance only; evaluators never address global video time.
  uint16_t sourceFirstFrame, sourceLastFrame;
  bool loopSafe;
};
struct Sample {
  VectorFace::Frame frame{};
  VectorFace::GeometryBounds bounds{};
  uint32_t localTimeUs = 0;
  uint16_t keyframe = 0;
  FaceKind face = FaceKind::Any;
  bool finished = false;
};
struct Keyframe {
  uint32_t localUs;
  uint16_t shapeOffset;
  uint8_t shapeCount, flags;
  uint8_t sourcePalette;  // low byte of the source palette index
  // extension[0] is the index's high byte; the rest stay zero. Keys written
  // as {..., n, {0,0,0}} before this widening keep the same 12-byte ABI.
  uint8_t extension[3];
};
constexpr uint16_t sourcePaletteIndex(const Keyframe& key) {
  return static_cast<uint16_t>(key.sourcePalette | key.extension[0] << 8);
}
constexpr size_t kClipCount = static_cast<size_t>(ClipId::Count);
constexpr size_t kBaselineClipCount = 16;
// Source clips in the original Ddjj showcase; corpus clips use other sources.
constexpr size_t kSourceClipCount = 14;

const Definition& definition(ClipId id);
const char* faceName(FaceKind face);
const char* paletteName(PaletteId id);
Palette namedPalette(PaletteId id);
Parameters referenceParameters();
Parameters boundedParameters(ClipId id, const Parameters& parameters);
uint32_t playbackDurationUs(ClipId id, const Parameters& parameters);
// Exact source preset: intensity 1, source colors, no gaze/mirror/time changes.
// Canonical geometry is never edited by appearance choices.
bool sample(ClipId id, double localUs, const Parameters& parameters, Sample& output);
// Adapt the existing measured attention/retreat channels to a compatible held
// two-eye face. The input is captured once, never recursively deformed.
bool applyRetreat(const VectorFace::Frame& held, double localUs,
                  const Parameters& parameters, Sample& output);
bool compatible(const VectorFace::Frame& a, const VectorFace::Frame& b);
void enforceRoundSafety(VectorFace::Frame& frame, float margin = 1.0F);
size_t metadataBytes();
size_t keyframeBytes();
size_t geometryBytes();
size_t paletteBytes();
}  // namespace MotionClips
