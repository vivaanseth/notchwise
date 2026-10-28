#pragma once

#include <stdint.h>
#include <lvgl.h>

#include "FaceMotionEngine.h"

// Procedural, allocation-free scanline renderer for the 240 x 240 round
// Character target. FaceMotion geometry is in 480 x 480 logical screen space;
// every physical pixel samples logical (2*x, 2*y). No display driver or panel
// geometry beyond the requested 240-pixel output row is assumed here.
namespace FaceMotionRaster {
void render240Row(const FaceMotion::Frame& frame, uint16_t physicalY,
                  lv_color_t* output240);
}
