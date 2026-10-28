#pragma once

#include <stdint.h>

namespace Core {

// Creature measurements are authored in a 480x480 logical square. This
// transform fits that square inside any physical display without changing
// measured eye geometry. A round panel's visible mask belongs to its driver.
struct LogicalViewport {
  static constexpr float kReferenceSize = 480.0F;

  struct Point { float x; float y; };

  uint16_t width = 480;
  uint16_t height = 480;
  float scale = 1.0F;
  float offsetX = 0.0F;
  float offsetY = 0.0F;

  static LogicalViewport fit(uint16_t physicalWidth,
                             uint16_t physicalHeight) {
    LogicalViewport result;
    result.width = physicalWidth == 0 ? 1 : physicalWidth;
    result.height = physicalHeight == 0 ? 1 : physicalHeight;
    const float sx = result.width / kReferenceSize;
    const float sy = result.height / kReferenceSize;
    result.scale = sx < sy ? sx : sy;
    result.offsetX = (result.width - kReferenceSize * result.scale) * 0.5F;
    result.offsetY = (result.height - kReferenceSize * result.scale) * 0.5F;
    return result;
  }

  Point toPhysical(float logicalX, float logicalY) const {
    return {offsetX + logicalX * scale, offsetY + logicalY * scale};
  }

  Point toLogical(float physicalX, float physicalY) const {
    const float x = (physicalX - offsetX) / scale;
    const float y = (physicalY - offsetY) / scale;
    return {clamp(x), clamp(y)};
  }

  uint16_t lvglZoom() const {
    const float scaled = scale * 256.0F + 0.5F;
    return static_cast<uint16_t>(scaled < 1.0F ? 1.0F :
                                 scaled > 65535.0F ? 65535.0F : scaled);
  }

  bool isIdentity() const {
    return width == 480 && height == 480;
  }

 private:
  static float clamp(float value) {
    return value < 0.0F ? 0.0F :
           value > kReferenceSize ? kReferenceSize : value;
  }
};

}  // namespace Core
