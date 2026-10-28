#pragma once

#include <lvgl.h>
#include "ExactEyeModel.h"
#include "FaceMotionEngine.h"
#include "CreatureEyeStyle.h"
#include "VectorFaceRaster.h"
#include "../core/LogicalViewport.h"

// One reusable 380×320 RGB565 LVGL canvas (243,200 bytes PSRAM). Only the
// union of old/new eye bounds is cleared and invalidated on each frame.
class ExactEyeRenderer {
 public:
  bool begin(lv_obj_t* parent);
  void draw(const ExactEyeModel::Frame& frame);
  void draw(const ExactEyeModel::Frame& frame,
            const CreatureEyeStyle::RenderParams& params);
  // Behavioral face vocabulary, composited into the retained LVGL canvas.
  // The 240-row API below is the authoritative full-disc path for the future
  // round target; this legacy canvas intentionally remains 380 x 320.
  void draw(const FaceMotion::Frame& frame);
  // Measured production clips share the same retained canvas and round row
  // raster path. No video frame, secondary framebuffer, or allocation.
  void draw(const VectorFace::Frame& frame);
  static void render240Row(const VectorFace::Frame& frame,
                           uint16_t physicalY, lv_color_t* output240);
  static void render240Row(const FaceMotion::Frame& frame,
                           uint16_t physicalY, lv_color_t* output240);
  // Host-tested streaming reference for the 240x240 Character target. The
  // caller owns a 240-pixel RGB565 row; this function uses only one temporary
  // 380-pixel logical row, never a full eye or display framebuffer. A future
  // verified C3 display adapter may stream these rows to its actual panel.
  static void render240Row(const ExactEyeModel::Frame& frame,
                           const CreatureEyeStyle::RenderParams& params,
                           uint16_t physicalY, lv_color_t* output240);
  bool ready() const { return canvas_ != nullptr; }
  const Core::LogicalViewport& viewport() const { return viewport_; }

 private:
  lv_obj_t* canvas_ = nullptr;
  lv_color_t* pixels_ = nullptr;
  lv_area_t lastPainted_{};
  bool hasLastPainted_ = false;
  Core::LogicalViewport viewport_{};
};
