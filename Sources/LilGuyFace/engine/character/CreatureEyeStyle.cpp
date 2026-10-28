#include "CreatureEyeStyle.h"

#include <math.h>

namespace CreatureEyeStyle {
namespace {
// RGB triples and 480-pixel geometry are recorded with screenshot links in
// CREATURE_EYE_CATALOG.md. The gallery's moving pupils make the center offsets
// approximate; the family silhouettes and exact palette are the stable parts.
constexpr Style kStyles[] = {
    {Id::CircleOg, Family::Circle, {255, 255, 255}, {0, 0, 0},
     {66, 65, 19.5F, 5, -25, 5}},
    {Id::DotSnowball, Family::Dot, {255, 255, 255}, {90, 121, 243},
     {13, 18, 33, 8, -38.5F, 7}},
    {Id::CatMoon, Family::Cat, {64, 40, 255}, {235, 255, 252},
     {27, 103, 25.5F, 3.5F, -20, 3.5F}},
    {Id::AcornPeach, Family::Acorn, {253, 251, 226}, {247, 110, 93},
     {63, 113, 8, 12, -13.5F, 10}},
    {Id::CirclePool, Family::Circle, {5, 168, 249}, {252, 238, 238},
     {66, 65, 19.5F, 5, -25, 5}},
    {Id::CatLaser, Family::Cat, {255, 255, 255}, {255, 0, 0},
     {27, 103, 25.5F, 3.5F, -20, 3.5F}},
    {Id::DotLadybug, Family::Dot, {195, 17, 14}, {0, 0, 0},
     {13, 18, 33, 8, -38.5F, 7}},
    {Id::AcornSeaglass, Family::Acorn, {251, 251, 251}, {22, 123, 97},
     {63, 113, 8, 12, -13.5F, 10}},
};
static_assert(sizeof(kStyles) / sizeof(kStyles[0]) ==
                  static_cast<unsigned>(Id::Count),
              "Every verified Creature style must be registered");

float clamp01(float value) {
  return value < 0 ? 0 : value > 1 ? 1 : value;
}
float lerp(float a, float b, float t) { return a + (b - a) * t; }
uint8_t channel(uint8_t a, uint8_t b, float t) {
  return static_cast<uint8_t>(lerp(a, b, t) + 0.5F);
}
// The half-width profiles below are derived from 480x480 live captures. At
// 10/25/50/75/90% height, cat width ≈15/22/25/22/14 of max 27 pixels; acorn
// ≈36/51/61/59/50 of max 63 pixels. The cat's pointed end caps are visible;
// the acorn's broad lower end meets the outer eye boundary in the capture, so
// its last measured width is held rather than inventing a lower point.
float profileHalfWidth(Family family, float v) {
  static constexpr float kY[] = {0, 0.10F, 0.25F, 0.50F, 0.75F, 0.90F, 1};
  static constexpr float kCat[] = {0, 15.0F / 27, 22.0F / 27, 25.0F / 27,
                                   22.0F / 27, 14.0F / 27, 0};
  static constexpr float kAcorn[] = {0, 36.0F / 63, 51.0F / 63, 61.0F / 63,
                                     59.0F / 63, 50.0F / 63, 50.0F / 63};
  const float* widths = family == Family::Cat ? kCat : kAcorn;
  // The screenshot samples anchor the silhouette; smooth interpolation avoids
  // turning those samples into visible polygon corners. Rounded upper caps
  // follow the observed oval-like contour rather than a pointed line.
  if (v <= kY[1]) return widths[1] * sqrtf(v / kY[1]);
  if (v >= kY[5]) {
    if (family == Family::Acorn) return widths[5];
    return widths[5] * sqrtf((1.0F - v) / (1.0F - kY[5]));
  }
  const auto slope = [widths](unsigned k) {
    const float before = (widths[k] - widths[k - 1]) /
                         (kY[k] - kY[k - 1]);
    const float after = (widths[k + 1] - widths[k]) /
                        (kY[k + 1] - kY[k]);
    if (before * after <= 0) return 0.0F;
    return 2.0F * before * after / (before + after);
  };
  for (unsigned i = 2; i <= 5; ++i) {
    if (v <= kY[i]) {
      const float span = kY[i] - kY[i - 1];
      const float t = (v - kY[i - 1]) / span;
      const float t2 = t * t, t3 = t2 * t;
      return (2 * t3 - 3 * t2 + 1) * widths[i - 1] +
             (t3 - 2 * t2 + t) * span * slope(i - 1) +
             (-2 * t3 + 3 * t2) * widths[i] +
             (t3 - t2) * span * slope(i);
    }
  }
  return widths[5];
}
}  // namespace

const Style& get(Id id) {
  const auto index = static_cast<unsigned>(id);
  return index < static_cast<unsigned>(Id::Count) ? kStyles[index] : kStyles[0];
}

Style resolve(const RenderParams& params) {
  const Style& from = get(params.from);
  const Style& to = get(params.to);
  const float t = clamp01(params.mix);
  if (from.family != to.family) return t >= 1 ? to : from;
  Style out = from;
  out.outer = {channel(from.outer.r, to.outer.r, t),
               channel(from.outer.g, to.outer.g, t),
               channel(from.outer.b, to.outer.b, t)};
  out.pupil = {channel(from.pupil.r, to.pupil.r, t),
               channel(from.pupil.g, to.pupil.g, t),
               channel(from.pupil.b, to.pupil.b, t)};
  out.geometry = {
      lerp(from.geometry.width, to.geometry.width, t),
      lerp(from.geometry.height, to.geometry.height, t),
      lerp(from.geometry.leftX, to.geometry.leftX, t),
      lerp(from.geometry.leftY, to.geometry.leftY, t),
      lerp(from.geometry.rightX, to.geometry.rightX, t),
      lerp(from.geometry.rightY, to.geometry.rightY, t),
  };
  return out;
}

bool pupilContains(Family family, float x, float y) {
  if (fabsf(y) >= 1 || fabsf(x) >= 1) return false;
  if (family == Family::Dot || family == Family::Circle)
    return x * x + y * y < 1;
  return fabsf(x) < taperedPupilHalfWidth(family, y);
}

float taperedPupilHalfWidth(Family family, float normalizedY) {
  if (normalizedY <= -1 || normalizedY >= 1) return 0;
  return profileHalfWidth(family, (normalizedY + 1) * 0.5F);
}

}  // namespace CreatureEyeStyle
