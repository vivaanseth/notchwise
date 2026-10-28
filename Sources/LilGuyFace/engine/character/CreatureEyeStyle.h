#pragma once

#include <stdint.h>

// The public Creature gallery identifies shape families and colorways, but it
// does not name emotion presets. These are measured, source-linked styles; the
// application decides which style to use for a semantic event.
namespace CreatureEyeStyle {

enum class Id : uint8_t {
  CircleOg,
  DotSnowball,
  CatMoon,
  AcornPeach,
  CirclePool,
  CatLaser,
  DotLadybug,
  AcornSeaglass,
  Count,
};

enum class Family : uint8_t { Dot, Circle, Cat, Acorn };

struct Rgb {
  uint8_t r, g, b;
};

struct PupilGeometry {
  float width, height;
  float leftX, leftY;    // Center offset from the left outer eye, pixels.
  float rightX, rightY;  // Center offset from the right outer eye, pixels.
};

struct Style {
  Id id;
  Family family;
  Rgb outer;
  Rgb pupil;
  PupilGeometry geometry;
};

struct RenderParams {
  Id from = Id::CircleOg;
  Id to = Id::CircleOg;
  float mix = 0.0F;
  float pupilScale = 1.0F;
  float pupilOffsetX = 0.0F;
  float pupilOffsetY = 0.0F;
};

const Style& get(Id id);
// Interpolates measured palette and pupil geometry only within one family.
// Cross-family changes return the source until mix reaches 1; callers should
// swap families during a closed blink, not create an unreferenced hybrid.
Style resolve(const RenderParams& params);

// Pure, host-testable source-derived pupil silhouettes. x and y are normalized
// to [-1, 1] by each style's measured pupil width and height.
bool pupilContains(Family family, float x, float y);
// Width of a Cat/Acorn pupil at normalized y. Exposing the same profile lets
// the renderer evaluate it once per scanline rather than once per pixel.
float taperedPupilHalfWidth(Family family, float normalizedY);

}  // namespace CreatureEyeStyle
