#pragma once

#include <cstddef>
#include <cstdint>
#include <lvgl.h>

// Small procedural polygon renderer shared by host reference tooling and any
// future measured motion primitives. Coordinates are physical 240px pixels.
// The caller owns all storage; decoding, interpolation and rasterization do
// not allocate. This module has no knowledge of a particular source clip.
namespace VectorFace {
constexpr size_t kMaxShapes = 12;
constexpr size_t kMaxVertices = 32;
// Exact fixed working-array storage, excluding the caller's 480-byte output
// row and compiler-dependent scalar temporaries/call frames.
constexpr size_t kBinaryScratchBytes = 240 * sizeof(uint16_t) +
                                        kMaxVertices * sizeof(float);
constexpr size_t kAntialiasedScratchBytes = 2 * 480 * sizeof(lv_color_t) +
    480 * sizeof(uint16_t) + kMaxVertices * sizeof(float);

struct PackedShape {
  int16_t centerX64, centerY64, width64, height64, rotation64;
  uint8_t vertexCount;
  int8_t clipShape;  // -1, or an earlier shape in the same frame.
  uint16_t color565;
  int8_t points[64];  // Normalized x/y pairs: +/-127 = +/-full extent / 2.
};
static_assert(sizeof(PackedShape) == 78, "Measured shape format changed");

struct Point { float x, y; };
struct Shape {
  float centerX, centerY, width, height, rotation;
  uint8_t vertexCount;
  int8_t clipShape;
  uint16_t color565;
  Point vertices[kMaxVertices];  // Transformed physical display coordinates.
};
struct Frame {
  uint8_t shapeCount;
  uint16_t background565 = 0;
  // Optional semantic ownership retained when a pose is held/retargeted.
  // Zero is unknown/background; the raster consumes only resolved RGB565.
  uint8_t colorRoles[kMaxShapes]{};
  Shape shapes[kMaxShapes];
};
struct GeometryBounds {
  float minimumRoundMargin;
  uint16_t verticesOutside;
  uint8_t invalidShapes;
};

bool unpack(const PackedShape& packed, Shape& shape);
bool interpolate(const PackedShape& from, const PackedShape& to,
                 float amount, Shape& shape);
GeometryBounds measureBounds(const Frame& frame);
// false exposes the unmasked geometry for host QA; the physical output uses
// the same (119.5,119.5), radius119.5 mask as the existing Character renderer.
void render240Row(const Frame& frame, uint16_t y, lv_color_t* output,
                  bool maskRound = true);
// Optional 2x2 coverage at +/-0.25px around the existing integer pixel-center
// convention. Ordered drawing and parent clipping are resolved per sample;
// the round device mask is applied to the finished physical pixel.
void render240RowAntialiased(const Frame& frame, uint16_t y,
                             lv_color_t* output, bool maskRound = true);
}  // namespace VectorFace
