#include "VectorFaceRaster.h"

#include <cmath>
#include <cstring>

namespace VectorFace {
namespace {
constexpr float kRadians = 0.01745329251994329577F;
float mix(float a, float b, float t) { return a + (b - a) * t; }
bool valid(const PackedShape& shape) {
  return shape.vertexCount >= 3 && shape.vertexCount <= kMaxVertices &&
         shape.width64 >= 0 && shape.height64 >= 0 &&
         shape.clipShape >= -1 && shape.clipShape < static_cast<int>(kMaxShapes);
}
bool valid(const Shape& shape, size_t index) {
  if (shape.vertexCount < 3 || shape.vertexCount > kMaxVertices ||
      shape.clipShape < -1 || shape.clipShape >= static_cast<int>(index) ||
      !std::isfinite(shape.centerX) || !std::isfinite(shape.centerY) ||
      !std::isfinite(shape.width) || !std::isfinite(shape.height) ||
      !std::isfinite(shape.rotation) || shape.width < 0 || shape.height < 0)
    return false;
  for (size_t i = 0; i < shape.vertexCount; ++i)
    if (!std::isfinite(shape.vertices[i].x) ||
        !std::isfinite(shape.vertices[i].y) ||
        std::fabs(shape.vertices[i].x) > 65536 ||
        std::fabs(shape.vertices[i].y) > 65536) return false;
  return true;
}
uint16_t colorMix(uint16_t a, uint16_t b, float t) {
  const auto channel = [t](unsigned x, unsigned y) {
    return static_cast<unsigned>(std::lround(mix(static_cast<float>(x),
                                                static_cast<float>(y), t)));
  };
  return static_cast<uint16_t>((channel(a >> 11, b >> 11) << 11) |
      (channel((a >> 5) & 63, (b >> 5) & 63) << 5) |
      channel(a & 31, b & 31));
}
bool inRound(int x, int y) {
  const int dx = 2 * x - 239, dy = 2 * y - 239;
  return dx * dx + dy * dy <= 239 * 239;
}
}  // namespace

bool interpolate(const PackedShape& from, const PackedShape& to,
                 float amount, Shape& shape) {
  if (!valid(from) || !valid(to) || !std::isfinite(amount) ||
      from.vertexCount != to.vertexCount || from.clipShape != to.clipShape)
    return false;
  const float t = amount < 0 ? 0 : amount > 1 ? 1 : amount;
  shape.centerX = mix(from.centerX64, to.centerX64, t) / 64;
  shape.centerY = mix(from.centerY64, to.centerY64, t) / 64;
  shape.width = mix(from.width64, to.width64, t) / 64;
  shape.height = mix(from.height64, to.height64, t) / 64;
  shape.rotation = mix(from.rotation64, to.rotation64, t) / 64;
  shape.vertexCount = from.vertexCount;
  shape.clipShape = from.clipShape;
  shape.color565 = colorMix(from.color565, to.color565, t);
  const float radians = shape.rotation * kRadians;
  const float c = std::cos(radians), s = std::sin(radians);
  for (size_t i = 0; i < shape.vertexCount; ++i) {
    const float x = mix(from.points[2 * i], to.points[2 * i], t) *
                    shape.width / 254;
    const float y = mix(from.points[2 * i + 1], to.points[2 * i + 1], t) *
                    shape.height / 254;
    shape.vertices[i] = {shape.centerX + c * x - s * y,
                         shape.centerY + s * x + c * y};
  }
  return true;
}

bool unpack(const PackedShape& packed, Shape& shape) {
  return interpolate(packed, packed, 0, shape);
}

GeometryBounds measureBounds(const Frame& frame) {
  GeometryBounds result{119.5F, 0, 0};
  const size_t count = frame.shapeCount > kMaxShapes ? kMaxShapes : frame.shapeCount;
  if (frame.shapeCount > kMaxShapes) ++result.invalidShapes;
  for (size_t i = 0; i < count; ++i) {
    const Shape& shape = frame.shapes[i];
    if (!valid(shape, i)) { ++result.invalidShapes; continue; }
    for (size_t j = 0; j < shape.vertexCount; ++j) {
      const Point& point = shape.vertices[j];
      const float margin = 119.5F - std::hypot(point.x - 119.5F,
                                             point.y - 119.5F);
      if (margin < result.minimumRoundMargin) result.minimumRoundMargin = margin;
      if (margin < 0) ++result.verticesOutside;
    }
  }
  return result;
}

namespace {
template<unsigned SamplesPerPixel>
void renderSamples(const Frame& frame, float y, lv_color_t* output) {
  static_assert(sizeof(lv_color_t) == 2, "RGB565 scanline expected");
  static_assert(kMaxShapes <= 16, "Membership mask has sixteen bits");
  static_assert(SamplesPerPixel == 1 || SamplesPerPixel == 2,
                "Only binary or 2x2 coverage is supported");
  constexpr unsigned sampleCount = 240 * SamplesPerPixel;
  constexpr float firstSample = SamplesPerPixel == 1 ? 0 : -.25F;
  for (size_t x = 0; x < sampleCount; ++x) output[x].full = frame.background565;
  // One bit per shape records coverage including parent clipping. A later
  // motif can therefore clip to an earlier eye without any framebuffer mask.
  uint16_t membership[sampleCount]{};
  float intersections[kMaxVertices];
  const size_t count = frame.shapeCount > kMaxShapes ? kMaxShapes : frame.shapeCount;
  for (size_t index = 0; index < count; ++index) {
    const Shape& shape = frame.shapes[index];
    if (!valid(shape, index) || shape.width == 0 || shape.height == 0) continue;
    size_t hits = 0;
    for (size_t i = 0, j = shape.vertexCount - 1; i < shape.vertexCount; j = i++) {
      const Point& a = shape.vertices[i];
      const Point& b = shape.vertices[j];
      if ((a.y > y) != (b.y > y)) {
        const float x = a.x + (b.x - a.x) * (y - a.y) / (b.y - a.y);
        // Insertion sort keeps fixed storage and handles concave polygons.
        size_t at = hits++;
        while (at > 0 && intersections[at - 1] > x) {
          intersections[at] = intersections[at - 1]; --at;
        }
        intersections[at] = x;
      }
    }
    const uint16_t bit = static_cast<uint16_t>(1U << index);
    const uint16_t parent = shape.clipShape < 0 ? 0 :
        static_cast<uint16_t>(1U << shape.clipShape);
    for (size_t at = 0; at + 1 < hits; at += 2) {
      const float left = (intersections[at] - firstSample) * SamplesPerPixel;
      const float right = (intersections[at + 1] - firstSample) * SamplesPerPixel;
      if (left >= sampleCount || right <= 0) continue;
      const int start = left <= 0 ? 0 : static_cast<int>(std::ceil(left));
      const int end = right >= sampleCount ? sampleCount :
          static_cast<int>(std::ceil(right));
      for (int x = start; x < end; ++x) {
        if (parent && !(membership[x] & parent)) continue;
        membership[x] |= bit;
        output[x].full = shape.color565;
      }
    }
  }
}
}  // namespace

void render240Row(const Frame& frame, uint16_t y, lv_color_t* output,
                  bool maskRound) {
  if (!output) return;
  if (y >= 240) {
    std::memset(output, 0, 240 * sizeof(*output));
    return;
  }
  renderSamples<1>(frame, y, output);
  if (maskRound)
    for (int x = 0; x < 240; ++x) if (!inRound(x, y)) output[x].full = 0;
}

void render240RowAntialiased(const Frame& frame, uint16_t y,
                             lv_color_t* output, bool maskRound) {
  if (!output) return;
  if (y >= 240) {
    std::memset(output, 0, 240 * sizeof(*output));
    return;
  }
  // 1920 bytes for both subrows plus the helper's 1088-byte membership and
  // intersection arrays. No framebuffer, allocator or per-shape mask needed.
  lv_color_t samples[2][480];
  renderSamples<2>(frame, y - .25F, samples[0]);
  renderSamples<2>(frame, y + .25F, samples[1]);
  for (int x = 0; x < 240; ++x) {
    if (maskRound && !inRound(x, y)) { output[x].full = 0; continue; }
    unsigned red = 0, green = 0, blue = 0;
    for (unsigned row = 0; row < 2; ++row) {
      for (unsigned column = 0; column < 2; ++column) {
        const uint16_t color = samples[row][2 * x + column].full;
        red += color >> 11;
        green += (color >> 5) & 63;
        blue += color & 31;
      }
    }
    output[x].full = static_cast<uint16_t>(((red + 2) / 4 << 11) |
                                          ((green + 2) / 4 << 5) |
                                          ((blue + 2) / 4));
  }
}
}  // namespace VectorFace
