#pragma once

#include <cstddef>
#include <cstdint>

namespace MeasuredMotion {
enum Channel : uint8_t {
  GlobalX, GlobalY, Spacing, VerticalMismatch,
  LeftWidth, LeftHeight, RightWidth, RightHeight,
  LeftPupilX, LeftPupilY, RightPupilX, RightPupilY, ChannelCount
};
struct Knot {
  uint32_t timestampUs;
  uint16_t sourceFrame;
  int16_t quarterPixels[ChannelCount];
};
struct Track { const Knot* knots; size_t count; };
struct Sample { float channels[ChannelCount]; uint16_t sourceFrame; };

// Immutable, independent sampled channels. Linear interpolation preserves
// observed reversals/holds; callers do not add a second easing or spring.
bool sample(Track track, uint32_t elapsedUs, Sample& output);
Track curiousAttention();
size_t curiousAttentionBytes();
constexpr uint32_t kAttentionDurationUs = 1066667;
// Product adaptation: at intensity 1, use 60% of measured displacement and
// fractional deformation; the normal 0.5 request uses 30%. Timing stays exact.
constexpr float kProductAmplitude = .60F;
}  // namespace MeasuredMotion
