#pragma once

#include <stdint.h>

// Screen-space reconstruction of the observed Circle Eyes + OG swatch.
// No 3D coordinates or projection are used. The corresponding desktop model
// and measurements live in tools/lilguy-clone and LILGUY_EXACT_CLONE_NOTES.md.
class ExactEyeModel {
 public:
  struct Eye {
    float x, y, width, height;
    float pupilX, pupilY, pupilWidth, pupilHeight;
    float shear;
    float rotationDegrees = 0;
  };
  struct Frame {
    Eye left, right;
    float closure;
  };

  void begin(uint32_t nowMs);
  void update(uint32_t nowMs);
  void setPointer(float x, float y);
  void setPupilPointer(float x, float y);
  void blink(uint32_t nowMs);
  void cancelBlink();
  Frame frame() const;
  void setAutonomous(bool enabled) { autonomous_ = enabled; }
  bool autonomous() const { return autonomous_; }

 private:
  float targetX_ = 240, targetY_ = 240;
  float pupilTargetX_ = 240, pupilTargetY_ = 240;
  float actualX_ = 240, actualY_ = 240;
  float pupilX_ = 240, pupilY_ = 240;
  uint32_t lastMs_ = 0;
  uint32_t elapsedMs_ = 0;
  uint32_t nextBlinkMs_ = 0;
  uint32_t blinkStartMs_ = UINT32_MAX;
  uint16_t blinkHoldMs_ = 150;
  bool autonomous_ = true;
};
