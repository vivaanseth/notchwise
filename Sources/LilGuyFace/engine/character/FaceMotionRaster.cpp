#include "FaceMotionRaster.h"

#include <math.h>
#include <string.h>

#include "CreatureEyeStyle.h"

namespace FaceMotionRaster {
namespace {
using FaceMotion::Eye;
using FaceMotion::Family;
using FaceMotion::Frame;
using FaceMotion::Motif;
using FaceMotion::PoseId;
using CreatureEyeStyle::Rgb;

constexpr float kPi = 3.14159265358979323846F;
constexpr float kDegreesToRadians = kPi / 180.0F;

float clamp(float value, float lo, float hi) {
  return value < lo ? lo : value > hi ? hi : value;
}

Rgb blend(const Rgb& from, const Rgb& to, float amount) {
  const float t = clamp(amount, 0, 1);
  return {static_cast<uint8_t>(from.r + (to.r - from.r) * t),
          static_cast<uint8_t>(from.g + (to.g - from.g) * t),
          static_cast<uint8_t>(from.b + (to.b - from.b) * t)};
}

bool inRoundDisplay(int x, int y) {
  // Match the host and round target's exact pixel-center convention:
  // center (119.5,119.5), radius 119.5. Integer doubled coordinates avoid
  // a sqrt/float on every pixel and prevent a one-pixel colored fringe.
  const int dx = 2 * x - 239, dy = 2 * y - 239;
  return dx * dx + dy * dy <= 239 * 239;
}

bool heart(float x, float y) {
  // Standard implicit heart in its local frame; screen Y points downward.
  const float yy = -y;
  const float a = x * x + yy * yy - 1.0F;
  return a * a * a - x * x * yy * yy * yy <= 0.0F;
}

bool polygonContains(float x, float y, const float* points, unsigned count) {
  bool inside = false;
  for (unsigned i = 0, j = count - 1; i < count; j = i++) {
    const float xi = points[2 * i], yi = points[2 * i + 1];
    const float xj = points[2 * j], yj = points[2 * j + 1];
    if ((yi > y) != (yj > y) &&
        x < (xj - xi) * (y - yi) / (yj - yi) + xi)
      inside = !inside;
  }
  return inside;
}

bool motifContains(Motif motif, float x, float y) {
  if (fabsf(x) > 1.2F || fabsf(y) > 1.2F) return false;
  switch (motif) {
    case Motif::Dot:
    case Motif::Oval:
      return x * x + y * y <= 1.0F;
    case Motif::Heart:
      return heart(x * 1.06F, y * 1.12F);
    case Motif::Bolt: {
      // A solid authored zig-zag, never a rotated/compressed ellipse.
      static constexpr float kBolt[] = {
          .05F, -1.00F, -.58F, -.08F, -.08F, -.08F,
          -.46F, 1.00F, .64F, -.22F, .12F, -.22F,
          .45F, -1.00F};
      return polygonContains(x, y, kBolt, 7);
    }
    case Motif::Spiral: {
      const float radius = sqrtf(x * x + y * y);
      if (radius > .97F) return false;
      // Two turns of a stroked Archimedean spiral, evaluated by the nearest
      // equivalent angular turn. This remains eye-local during movement.
      const float angle = atan2f(y, x);
      const float turn = (angle + kPi) / (2.0F * kPi);
      const float first = .07F + .43F * turn;
      const float second = first + .43F;
      return fabsf(radius - first) < .10F ||
             fabsf(radius - second) < .10F;
    }
    case Motif::Flower: {
      const float radius = sqrtf(x * x + y * y);
      if (radius < .27F) return true;
      if (radius > .98F) return false;
      const float angle = atan2f(y, x);
      return radius <= .60F + .29F * cosf(5.0F * angle);
    }
    case Motif::None:
      return false;
  }
  return false;
}

bool outerContains(Family family, float x, float y, float width,
                   float height) {
  const float hw = width * .5F, hh = height * .5F;
  if (hw < 1 || hh < 1) return false;
  const float u = x / hw, v = y / hh;
  switch (family) {
    case Family::Round:
    case Family::Multi:
    case Family::Collage:
      return u * u + v * v <= 1.0F;
    case Family::Capsule: {
      // True stadium contour, with rounded ends and a straight middle.
      if (width >= height) {
        const float cx = fmaxf(0.0F, fabsf(x) - (hw - hh));
        return cx * cx + y * y <= hh * hh;
      }
      const float cy = fmaxf(0.0F, fabsf(y) - (hh - hw));
      return x * x + cy * cy <= hw * hw;
    }
    case Family::Arc: {
      // Happy close is an UPWARD arch. It is a stroked curve and contains no
      // pupil; a flattened ellipse would have the wrong semantic silhouette.
      if (fabsf(u) > 1.0F) return false;
      const float archY = hh * (.65F - 1.4F * (1.0F - u * u));
      const float halfStroke = fmaxf(2.5F, hh * .18F);
      return fabsf(y - archY) <= halfStroke;
    }
    case Family::Slit: {
      const float cap = fminf(hh, hw);
      const float cx = fmaxf(0.0F, fabsf(x) - (hw - cap));
      return cx * cx + y * y <= cap * cap;
    }
    case Family::Petal: {
      const float r = sqrtf(u * u + v * v);
      if (r > 1.0F) return false;
      const float angle = atan2f(v, u);
      return r <= .79F + .18F * cosf(5.0F * angle);
    }
  }
  return false;
}

struct EyeSampler {
  const Eye* eye;
  Family family;
  Motif motif;
  Rgb outer;
  Rgb inner;
  CreatureEyeStyle::Family lookFamily;
  float cosine, sine;
  float motifCosine, motifSine;
  float pupilWidth, pupilHeight;
  float pupilX, pupilY;
  int x0, x1;
  bool pupilVisible;
  bool stylePupil;
};

Rgb specialOuter(const Frame& frame, const Rgb& original,
                 uint8_t eyeIndex) {
  // Transition frames often carry T07/T09 pose IDs while already displaying
  // the destination's new family and motif. Key local reaction accents to
  // those channels, not to the temporary pose ID, to avoid a color snap at
  // the end of an authored gate/settle.
  if (frame.motif == Motif::Spiral) return {177, 159, 247};
  if (frame.motif == Motif::Bolt) return {104, 222, 105};
  if (frame.family == Family::Collage &&
      (frame.effects & FaceMotion::Collision)) return {242, 237, 224};
  if (frame.family == Family::Petal && frame.eyeCount == 4)
    return eyeIndex % 2 == 0 ? Rgb{245, 244, 230}
                             : Rgb{172, 223, 222};
  if (frame.family == Family::Petal && frame.motif == Motif::Flower)
    return {246, 139, 182};
  if (frame.family == Family::Multi && frame.motif == Motif::Oval)
    return eyeIndex % 2 == 0 ? original : Rgb{172, 158, 249};
  if (frame.family == Family::Multi && frame.pose == PoseId::S02 &&
      eyeIndex >= 2) {
    // The S01 contact phrase contains one geometry-compatible mixed exchange
    // beat. Tint its receiver pair in/out; no topology or look ID is swapped.
    const float p = clamp(frame.effectPhase, 0, 1);
    const float enter = (p - .55F) / .07F;
    const float leave = (.82F - p) / .07F;
    return blend(original, {172, 158, 249}, fminf(enter, leave));
  }
  if (frame.motif == Motif::None &&
      (frame.effects & FaceMotion::WarmAccent)) return {248, 108, 69};
  return original;
}

Rgb specialInner(const Frame& frame, const Rgb& original) {
  if (frame.family == Family::Collage &&
      (frame.effects & FaceMotion::Collision))
    return {215, 77, 197};
  switch (frame.motif) {
    case Motif::Heart: return {240, 79, 76};
    case Motif::Bolt: return {248, 81, 56};
    case Motif::Spiral: return {65, 43, 150};
    case Motif::Flower: return {251, 191, 83};
    default: break;
  }
  if ((frame.effects & FaceMotion::WarmAccent) != 0)
    return {244, 109, 75};
  return original;
}

EyeSampler samplerFor(const Frame& frame, const CreatureEyeStyle::Style& look,
                      uint8_t index) {
  const Eye& eye = frame.eyes[index];
  const float radians = eye.rotation * kDegreesToRadians;
  const float c = cosf(radians), s = sinf(radians);
  const float motifRadians = frame.motif == Motif::Spiral
      ? clamp(frame.effectPhase, 0, 1) * (2.0F * kPi) : 0.0F;
  const float halfX = fabsf(c) * eye.width * .5F +
                      fabsf(s) * eye.height * .5F + 2.0F;
  const bool hasPupil = frame.motif != Motif::None &&
                        frame.family != Family::Arc &&
                        frame.family != Family::Slit &&
                        frame.coverage < .88F;
  // The behavior pose owns gaze and reaction scale. For ordinary pupils, the
  // selected Creature look still owns its measured Circle/Dot/Cat/Acorn pupil
  // dimensions, resting offset, and silhouette. Symbolic motifs deliberately
  // replace that cosmetic pupil only during their authored reaction.
  const bool stylePupil = frame.motif == Motif::Dot ||
                          frame.motif == Motif::Oval;
  float pupilWidth = fmaxf(1.0F, eye.pupilWidth);
  float pupilHeight = fmaxf(1.0F, eye.pupilHeight);
  float pupilX = eye.pupilX, pupilY = eye.pupilY;
  if (stylePupil) {
    const float behaviorScale = clamp(eye.pupilWidth /
        fmaxf(1.0F, eye.width * .39F), .10F, 1.6F);
    pupilWidth = fmaxf(1.0F, look.geometry.width *
        eye.width / 127.0F * behaviorScale);
    pupilHeight = fmaxf(1.0F, look.geometry.height *
        eye.height / 144.0F * behaviorScale);
    const bool isLeft = index % 2 == 0;
    const float measuredX = isLeft ? look.geometry.leftX
                                   : look.geometry.rightX;
    const float measuredY = isLeft ? look.geometry.leftY
                                   : look.geometry.rightY;
    const float authoredNeutralX = (isLeft ? 1.0F : -1.0F) *
                                   eye.width * .04F;
    pupilX += measuredX * eye.width / 127.0F - authoredNeutralX;
    pupilY += measuredY * eye.height / 144.0F;
  }
  // Re-clamp using the actual look-dependent motif dimensions. The engine
  // clamps its pose channel too, but it intentionally does not know looks.
  const float maxX = fmaxf(0.0F, eye.width * .45F - pupilWidth * .5F);
  const float maxY = fmaxf(0.0F, eye.height *
      (.45F - (eye.lidTop + eye.lidBottom) * .20F) - pupilHeight * .5F);
  if (maxX < 1 || maxY < 1) {
    pupilX = pupilY = 0;
  } else {
    const float v = pupilX * pupilX / (maxX * maxX) +
                    pupilY * pupilY / (maxY * maxY);
    if (v > 1.0F) {
      const float scale = 1.0F / sqrtf(v);
      pupilX *= scale;
      pupilY *= scale;
    }
  }
  return {&eye, frame.family, frame.motif,
          specialOuter(frame, look.outer, index),
          specialInner(frame, look.pupil), look.family, c, s,
          cosf(motifRadians), sinf(motifRadians),
          pupilWidth, pupilHeight, pupilX, pupilY,
          static_cast<int>(floorf((eye.x - halfX) * .5F)),
          static_cast<int>(ceilf((eye.x + halfX) * .5F)),
          hasPupil, stylePupil};
}

// Returns 0 for background, 1 for outer eye, 2 for inner motif. The motif is
// evaluated after all lid and outer clipping; it can never leak outside an eye.
uint8_t sampleEye(const EyeSampler& sampler, float logicalX,
                  float logicalY) {
  const Eye& eye = *sampler.eye;
  const float dx = logicalX - eye.x, dy = logicalY - eye.y;
  const float x = sampler.cosine * dx + sampler.sine * dy;
  const float y = -sampler.sine * dx + sampler.cosine * dy;
  if (y < -eye.height * (.5F - clamp(eye.lidTop, 0, 1)) ||
      y > eye.height * (.5F - clamp(eye.lidBottom, 0, 1)))
    return 0;
  if (!outerContains(sampler.family, x, y, eye.width, eye.height)) return 0;
  if (!sampler.pupilVisible) return 1;
  const float px = (x - sampler.pupilX) * 2.0F / sampler.pupilWidth;
  const float py = (y - sampler.pupilY) * 2.0F / sampler.pupilHeight;
  const float motifX = sampler.motif == Motif::Spiral
      ? sampler.motifCosine * px + sampler.motifSine * py : px;
  const float motifY = sampler.motif == Motif::Spiral
      ? -sampler.motifSine * px + sampler.motifCosine * py : py;
  const bool inner = sampler.stylePupil
      ? CreatureEyeStyle::pupilContains(sampler.lookFamily, px, py)
      : motifContains(sampler.motif, motifX, motifY);
  return inner ? 2 : 1;
}

bool sparkleAt(const Frame& frame, float x, float y) {
  if ((frame.effects & FaceMotion::Sparkle) == 0) return false;
  const float phase = clamp(frame.effectPhase, 0, 1);
  const float sx = frame.eyeCount >= 2
                       ? (frame.eyes[0].x + frame.eyes[1].x) * .5F
                       : 240.0F;
  const float sy = (frame.eyeCount ? frame.eyes[0].y - 75.0F : 163.0F)
                   - phase * 15.0F;
  const float dx = x - sx, dy = y - sy;
  return (fabsf(dx) < 2.3F && fabsf(dy) < 15.0F) ||
         (fabsf(dy) < 2.3F && fabsf(dx) < 15.0F) ||
         (fabsf(dx - dy) < 2.4F && fabsf(dx) < 9.0F) ||
         (fabsf(dx + dy) < 2.4F && fabsf(dx) < 9.0F);
}

bool detachedHeartsAt(const Frame& frame, float x, float y) {
  if ((frame.effects & FaceMotion::Hearts) == 0) return false;
  // Three bounded screen-space hearts drift upward on the authored effect
  // phase; no bitmap, particle array, or heap allocation is used.
  static constexpr float kHeartCenters[3][3] = {
      {130.0F, 157.0F, 13.0F}, {350.0F, 179.0F, 10.0F},
      {245.0F, 336.0F, 9.0F}};
  for (const auto& item : kHeartCenters) {
    const float size = item[2] * (.75F + .25F * clamp(frame.intensity, 0, 1));
    if (heart((x - item[0]) / size,
              (y - item[1] + clamp(frame.effectPhase, 0, 1) * 26.0F) / size))
      return true;
  }
  return false;
}

Rgb collisionColor(float x, float y) {
  // Screen-space fragmented sectors, bounded to the circular target. The
  // ordinary eyes are painted afterward and remain continuity anchors.
  const float dx = x - 240.0F, dy = y - 240.0F;
  // Eight coarse wedges and staggered diamond bands avoid transcendental
  // math on every pixel during a brief impact cover on the ESP32-C3.
  const int quadrant = (dx >= 0 ? 1 : 0) + (dy >= 0 ? 2 : 0);
  const int sector = quadrant * 2 + (fabsf(dx) > fabsf(dy) ? 1 : 0);
  const int band = static_cast<int>((fabsf(dx) + fabsf(dy) +
                                     ((sector & 1) ? 24.0F : 0.0F)) / 70.0F);
  static constexpr Rgb kFragments[] = {
      {211, 88, 205}, {109, 220, 215}, {169, 244, 213},
      {249, 118, 91}, {174, 153, 242}, {240, 240, 227}};
  return kFragments[(sector + band + 12) % 6];
}

void writeColor(lv_color_t* pixel, const Rgb& color) {
  *pixel = lv_color_make(color.r, color.g, color.b);
}
}  // namespace

void render240Row(const Frame& frame, uint16_t physicalY,
                  lv_color_t* output240) {
  static_assert(sizeof(lv_color_t) == 2, "RGB565 scanline expected");
  if (!output240) return;
  memset(output240, 0, 240 * sizeof(lv_color_t));
  if (physicalY >= 240) return;

  const float logicalY = physicalY * 2.0F;
  if ((frame.effects & FaceMotion::Flash) != 0) {
    for (int x = 0; x < 240; ++x) {
      if (inRoundDisplay(x, physicalY))
        writeColor(&output240[x], {249, 249, 242});
    }
    return;
  }

  if ((frame.effects & FaceMotion::Collision) != 0) {
    for (int x = 0; x < 240; ++x) {
      if (inRoundDisplay(x, physicalY))
        writeColor(&output240[x], collisionColor(x * 2.0F, logicalY));
    }
  }

  const CreatureEyeStyle::Style& look = CreatureEyeStyle::get(
      static_cast<CreatureEyeStyle::Id>(frame.lookId));
  const uint8_t eyeCount = frame.eyeCount > 4 ? 4 : frame.eyeCount;
  for (uint8_t i = 0; i < eyeCount; ++i) {
    const EyeSampler sampler = samplerFor(frame, look, i);
    const float halfY = fabsf(sampler.sine) * sampler.eye->width * .5F +
                        fabsf(sampler.cosine) * sampler.eye->height * .5F + 2;
    if (logicalY < sampler.eye->y - halfY ||
        logicalY > sampler.eye->y + halfY) continue;
    const int x0 = sampler.x0 < 0 ? 0 : sampler.x0;
    const int x1 = sampler.x1 > 239 ? 239 : sampler.x1;
    for (int x = x0; x <= x1; ++x) {
      if (!inRoundDisplay(x, physicalY)) continue;
      const uint8_t region = sampleEye(sampler, x * 2.0F, logicalY);
      if (region != 0)
        writeColor(&output240[x], region == 2 ? sampler.inner : sampler.outer);
    }
  }

  if ((frame.effects & (FaceMotion::Sparkle | FaceMotion::Hearts)) != 0) {
    for (int x = 0; x < 240; ++x) {
      if (!inRoundDisplay(x, physicalY)) continue;
      const float logicalX = x * 2.0F;
      if (sparkleAt(frame, logicalX, logicalY))
        writeColor(&output240[x], {250, 245, 209});
      else if (detachedHeartsAt(frame, logicalX, logicalY))
        writeColor(&output240[x], {244, 91, 91});
    }
  }
}
}  // namespace FaceMotionRaster
