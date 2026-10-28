#include "MeasuredMotion.h"

namespace MeasuredMotion {
namespace {
// Ddjj1EtSh5U source frames 271..303, frame 271 as time/geometry baseline.
// Provenance: reference/lilguy/analysis/Ddjj1EtSh5U/measurements/raw_frames.json
// PTS: exact integer ticks * 1/15360, rounded to microseconds after subtracting
// frame 271 PTS. Values are measured physical-display pixels in signed Q2.
// This is asymmetric attention/foreshortening, not established 3D retreat or
// shake. Near-circular fitted rotations are uncertain and deliberately absent.
constexpr Knot kAttention[] = {
  {0, 271, {468, 434, 356, 28, 352, 380, 328, 364, 28, 28, -30, 20}},
  {33333, 272, {471, 425, 354, 26, 352, 380, 324, 360, 32, 24, -24, 20}},
  {100000, 274, {482, 413, 352, 30, 360, 384, 312, 356, 36, 22, -14, 18}},
  {166667, 276, {501, 390, 346, 40, 356, 376, 296, 344, 36, 24, -16, 18}},
  {233333, 278, {513, 366, 342, 44, 360, 364, 284, 324, 36, 26, -12, 22}},
  {300000, 280, {518, 349, 340, 54, 356, 352, 276, 308, 42, 36, -8, 22}},
  {366667, 282, {522, 338, 340, 60, 356, 340, 276, 300, 38, 36, -12, 24}},
  {500000, 286, {521, 327, 338, 58, 356, 328, 280, 292, 34, 42, -8, 30}},
  {633333, 290, {521, 323, 338, 62, 356, 324, 280, 288, 34, 44, -8, 30}},
  {900000, 298, {521, 323, 338, 62, 356, 324, 280, 288, 34, 42, -12, 26}},
  {1066667, 303, {521, 325, 338, 62, 356, 320, 280, 292, 40, 40, -16, 28}},
};
static_assert(sizeof(Knot) == 32 && sizeof(kAttention) == 352,
              "Measured attention storage changed");
}  // namespace

Track curiousAttention() { return {kAttention, sizeof(kAttention) / sizeof(kAttention[0])}; }
size_t curiousAttentionBytes() { return sizeof(kAttention); }

bool sample(Track track, uint32_t elapsedUs, Sample& output) {
  if (!track.knots || !track.count) return false;
  size_t lo = 0, hi = track.count;
  while (lo < hi) {
    const size_t middle = lo + (hi - lo) / 2;
    if (track.knots[middle].timestampUs <= elapsedUs) lo = middle + 1;
    else hi = middle;
  }
  const size_t index = lo ? lo - 1 : 0;
  const Knot& a = track.knots[index];
  const Knot& b = track.knots[index + 1 < track.count ? index + 1 : index];
  if (b.timestampUs < a.timestampUs) return false;
  const float t = elapsedUs <= a.timestampUs || b.timestampUs == a.timestampUs ? 0 :
      static_cast<float>(elapsedUs - a.timestampUs) / (b.timestampUs - a.timestampUs);
  for (size_t c = 0; c < ChannelCount; ++c)
    output.channels[c] = (a.quarterPixels[c] +
        (b.quarterPixels[c] - a.quarterPixels[c]) * t) * .25F;
  output.sourceFrame = a.sourceFrame;
  return true;
}
}  // namespace MeasuredMotion
