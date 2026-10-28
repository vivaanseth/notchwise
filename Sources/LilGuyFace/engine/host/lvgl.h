#pragma once

#include <stdint.h>

struct lv_color_t { uint16_t full; };
struct lv_obj_t { int width = 480; int height = 480; };
using lv_coord_t = int16_t;
struct lv_area_t { lv_coord_t x1, y1, x2, y2; };

constexpr int LV_IMG_CF_TRUE_COLOR = 0;
constexpr int LV_OBJ_FLAG_CLICKABLE = 1;
constexpr int LV_OBJ_FLAG_SCROLLABLE = 2;

extern lv_color_t* testCanvasPixels;
inline uint64_t testInvalidatedPixels = 0;
inline uint32_t testInvalidationCount = 0;

inline lv_obj_t* lv_canvas_create(lv_obj_t*) {
  static lv_obj_t canvas;
  return &canvas;
}
inline void lv_canvas_set_buffer(lv_obj_t*, void* data, int, int, int) {
  testCanvasPixels = static_cast<lv_color_t*>(data);
}
inline void lv_obj_set_pos(lv_obj_t*, int, int) {}
inline void lv_obj_update_layout(lv_obj_t*) {}
inline int lv_obj_get_width(lv_obj_t* object) { return object->width; }
inline int lv_obj_get_height(lv_obj_t* object) { return object->height; }
inline void lv_img_set_pivot(lv_obj_t*, int, int) {}
inline void lv_img_set_zoom(lv_obj_t*, uint16_t) {}
inline void lv_obj_clear_flag(lv_obj_t*, int) {}
inline void lv_obj_invalidate(lv_obj_t*) {
  testInvalidatedPixels += 380 * 320;
  ++testInvalidationCount;
}
inline void lv_obj_invalidate_area(lv_obj_t*, const lv_area_t* area) {
  testInvalidatedPixels +=
      static_cast<uint32_t>(area->x2 - area->x1 + 1) *
      static_cast<uint32_t>(area->y2 - area->y1 + 1);
  ++testInvalidationCount;
}
inline lv_color_t lv_color_make(uint8_t r, uint8_t g, uint8_t b) {
  return {static_cast<uint16_t>(((r >> 3) << 11) |
                                ((g >> 2) << 5) | (b >> 3))};
}
