#include "ExactEyeRenderer.h"
#include "FaceMotionRaster.h"

#include <math.h>
#include <cmath>
#include <string.h>
#include <esp_heap_caps.h>

namespace {
constexpr int kLeft = 50, kTop = 80, kWidth = 380, kHeight = 320;
using CreatureEyeStyle::Family;
using CreatureEyeStyle::Rgb;
using CreatureEyeStyle::Style;

float clamp(float x, float lo, float hi) {
  return x < lo ? lo : x > hi ? hi : x;
}

struct Pupil {
  float x, y, width, height;
};

// Exclusive right/bottom bounds match the paint loops exactly. Keeping both
// the previous and new bounds is essential when a blink narrows the eye: the
// pixels outside the new shape still have to be erased and flushed.
struct Bounds {
  int x0, y0, x1, y1;
};

Bounds eyeBounds(const ExactEyeModel::Eye& eye) {
  return {
      static_cast<int>(clamp(floorf(eye.x - eye.width * .5F - 24),
                             kLeft, kLeft + kWidth)),
      static_cast<int>(clamp(floorf(eye.y - eye.height * .5F - 14),
                             kTop, kTop + kHeight)),
      static_cast<int>(clamp(ceilf(eye.x + eye.width * .5F + 24),
                             kLeft, kLeft + kWidth)),
      static_cast<int>(clamp(ceilf(eye.y + eye.height * .5F + 14),
                             kTop, kTop + kHeight)),
  };
}

Bounds join(const Bounds& a, const Bounds& b) {
  return {a.x0 < b.x0 ? a.x0 : b.x0,
          a.y0 < b.y0 ? a.y0 : b.y0,
          a.x1 > b.x1 ? a.x1 : b.x1,
          a.y1 > b.y1 ? a.y1 : b.y1};
}

Pupil pupilFor(const ExactEyeModel::Eye& eye, const Style& style, bool isLeft,
               const CreatureEyeStyle::RenderParams& params) {
  const float scale = clamp(params.pupilScale, 0.5F, 1.5F);
  if (style.family == Family::Circle) {
    // Preserve the already validated Circle OG clone *exactly*, including its
    // live pupil geometry/phase. Circle Pool is the same observed family with
    // a different verified palette, so it inherits that geometry too.
    return {eye.pupilX + params.pupilOffsetX,
            eye.pupilY + params.pupilOffsetY,
            eye.pupilWidth * scale, eye.pupilHeight * scale};
  }
  const float sx = eye.width / 127.0F;
  const float sy = eye.height / 144.0F;
  const float x = isLeft ? style.geometry.leftX : style.geometry.rightX;
  const float y = isLeft ? style.geometry.leftY : style.geometry.rightY;
  // Keep the live pointer-follow motion supplied by ExactEyeModel, replacing
  // only the captured Circle OG resting offset with this family's measured one.
  const float circleX = isLeft ? 22.0F : -25.0F;
  const float px = eye.pupilX + (x - circleX) * sx + params.pupilOffsetX;
  const float py = eye.pupilY + (y - 5.0F) * sy + params.pupilOffsetY;
  return {px, py, style.geometry.width * sx * scale,
          style.geometry.height * sy * scale};
}

// 0 = black, 1 = outer eye, 2 = colored pupil. Antialias only pixels near
// contours; every frame still uses the single RGB565 PSRAM canvas.
uint8_t sampleAt(const ExactEyeModel::Eye& eye, const Pupil& pupil,
                 Family family, float closure, float x, float y,
                 float cosine, float sine, bool* nearEdge = nullptr,
                 float taperedHalfWidth = -1.0F) {
  // Inverse-rotate sample coordinates around the eye center. Rotation is a
  // screen-space 2D pose only; canonical Circle OG has zero rotation.
  const float dx = x - eye.x, dy = y - eye.y;
  x = eye.x + cosine * dx + sine * dy;
  y = eye.y - sine * dx + cosine * dy;
  const float rx = eye.width * 0.5F;
  const float ry = eye.height * 0.5F;
  const float localX = x - eye.x - eye.shear * (y - eye.y);
  const float effectiveRx = rx * (1 - 0.16F * closure);
  const float u = localX / effectiveRx;
  if (fabsf(u) >= 1) {
    if (nearEdge != nullptr) *nearEdge = fabsf(u) < 1.04F;
    return 0;
  }
  const float root = sqrtf(fmaxf(0, 1 - u * u));
  const float upper = eye.y - ry * root;
  const float lower = eye.y + ry * root;
  const float arc = eye.y + eye.height * 0.33F + 17 * (1 - u * u);
  const float top = upper + (arc - 1.5F - upper) * closure;
  const float bottom = lower + (arc + 1.5F - lower) * closure;
  bool edge = fabsf(u) > .96F || fabsf(y - top) < 1.5F ||
              fabsf(y - bottom) < 1.5F;
  if (y < top || y > bottom) {
    if (nearEdge != nullptr) *nearEdge = edge;
    return 0;
  }
  if (closure >= 0.96F) {
    if (nearEdge != nullptr) *nearEdge = edge;
    return 1;
  }
  const float px = (x - pupil.x) / (pupil.width * 0.5F);
  const float py = (y - pupil.y) / (pupil.height * 0.5F);
  const bool inPupilBox = fabsf(px) <= 1.1F && fabsf(py) <= 1.1F;
  if (inPupilBox) {
    if (family == Family::Cat || family == Family::Acorn)
      edge = edge || fabsf(px) > 0.4F || fabsf(py) > 0.8F;
    else
      edge = edge || fabsf(px * px + py * py - 1) <
                         (family == Family::Dot ? 0.30F : 0.06F);
  }
  if (nearEdge != nullptr) *nearEdge = edge;
  const bool insidePupil = taperedHalfWidth >= 0 &&
                              (family == Family::Cat || family == Family::Acorn)
                           ? fabsf(px) < taperedHalfWidth
                           : CreatureEyeStyle::pupilContains(family, px, py);
  return insidePupil ? 2 : 1;
}

Rgb sampleColor(uint8_t region, const Style& style) {
  return region == 1 ? style.outer : region == 2 ? style.pupil : Rgb{0, 0, 0};
}

void paintEye(lv_color_t* pixels, const ExactEyeModel::Eye& eye,
              const Pupil& pupil, const Style& style, float closure,
              int onlyY = -1, int sampleStep = 1) {
  const float radians = eye.rotationDegrees * 0.01745329252F;
  const float cosine = cosf(radians), sine = sinf(radians);
  const Bounds bounds = eyeBounds(eye);
  const int firstY = onlyY < 0 ? bounds.y0 :
      (onlyY > bounds.y0 ? onlyY : bounds.y0);
  const int lastY = onlyY < 0 ? bounds.y1 :
      (onlyY + 1 < bounds.y1 ? onlyY + 1 : bounds.y1);
  for (int y = firstY; y < lastY; ++y) {
    lv_color_t* row = pixels + (onlyY < 0 ? y - kTop : 0) * kWidth;
    // With zero rotation, normalized pupil Y is constant across a scanline.
    // Cat/Acorn's measured taper profile is relatively costly, so reuse the
    // exact same function result for each of the three sample heights.
    const bool tapered = eye.rotationDegrees == 0 &&
                         (style.family == Family::Cat ||
                          style.family == Family::Acorn);
    const float invPupilRy = 2.0F / pupil.height;
    const auto rowWidth = [&](float sampleY) {
      return tapered ? CreatureEyeStyle::taperedPupilHalfWidth(
                           style.family, (sampleY - pupil.y) * invPupilRy)
                     : -1.0F;
    };
    const float middleWidth = rowWidth(y + .5F);
    const float upperWidth = rowWidth(y + .25F);
    const float lowerWidth = rowWidth(y + .75F);
    const int firstX = sampleStep == 1 ? bounds.x0 :
        (bounds.x0 & 1 ? bounds.x0 + 1 : bounds.x0);
    for (int x = firstX; x < bounds.x1; x += sampleStep) {
      bool nearEdge = false;
      const uint8_t center = sampleAt(eye, pupil, style.family, closure,
                                      x + .5F, y + .5F, cosine, sine, &nearEdge,
                                      middleWidth);
      if (!nearEdge) {
        if (center != 0) {
          const Rgb color = sampleColor(center, style);
          row[x - kLeft] = lv_color_make(color.r, color.g, color.b);
        }
        continue;
      }
      const Rgb a = sampleColor(sampleAt(eye, pupil, style.family, closure,
                        x + .25F, y + .25F, cosine, sine, nullptr,
                        upperWidth), style);
      const Rgb b = sampleColor(sampleAt(eye, pupil, style.family, closure,
                        x + .75F, y + .25F, cosine, sine, nullptr,
                        upperWidth), style);
      const Rgb c = sampleColor(sampleAt(eye, pupil, style.family, closure,
                        x + .25F, y + .75F, cosine, sine, nullptr,
                        lowerWidth), style);
      const Rgb d = sampleColor(sampleAt(eye, pupil, style.family, closure,
                        x + .75F, y + .75F, cosine, sine, nullptr,
                        lowerWidth), style);
      row[x - kLeft] = lv_color_make((a.r + b.r + c.r + d.r) / 4,
                                     (a.g + b.g + c.g + d.g) / 4,
                                     (a.b + b.b + c.b + d.b) / 4);
    }
  }
}
}  // namespace

void ExactEyeRenderer::render240Row(
    const ExactEyeModel::Frame& frame,
    const CreatureEyeStyle::RenderParams& params,
    uint16_t physicalY, lv_color_t* output240) {
  static_assert(sizeof(lv_color_t) == 2, "RGB565 scanline expected");
  if (output240 == nullptr) return;
  // 480 logical pixels fit 240 physical pixels at exactly 0.5 scale. Sample
  // the same RGB565 logical pixels as the retained LVGL canvas path. No panel
  // controller, pin assignment, PSRAM, or physical flush policy is assumed.
  const int logicalY = static_cast<int>(physicalY) * 2;
  if (physicalY >= 240 || logicalY < kTop || logicalY >= kTop + kHeight) {
    memset(output240, 0, 240 * sizeof(lv_color_t));
    return;
  }
  lv_color_t logicalRow[kWidth]{};
  const Style style = CreatureEyeStyle::resolve(params);
  paintEye(logicalRow, frame.left,
           pupilFor(frame.left, style, true, params), style, frame.closure,
           logicalY, 2);
  paintEye(logicalRow, frame.right,
           pupilFor(frame.right, style, false, params), style, frame.closure,
           logicalY, 2);
  for (int x = 0; x < 240; ++x) {
    const int logicalX = x * 2;
    output240[x].full = logicalX >= kLeft && logicalX < kLeft + kWidth
                            ? logicalRow[logicalX - kLeft].full : 0;
  }
}

void ExactEyeRenderer::render240Row(const FaceMotion::Frame& frame,
                                    uint16_t physicalY,
                                    lv_color_t* output240) {
  FaceMotionRaster::render240Row(frame, physicalY, output240);
}

bool ExactEyeRenderer::begin(lv_obj_t* parent) {
  static_assert(sizeof(lv_color_t) == 2, "RGB565 canvas expected");
  lv_obj_update_layout(parent);
  viewport_ = Core::LogicalViewport::fit(lv_obj_get_width(parent),
                                         lv_obj_get_height(parent));
  pixels_ = static_cast<lv_color_t*>(heap_caps_malloc(
      kWidth * kHeight * sizeof(lv_color_t), MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT));
  if (pixels_ == nullptr) return false;
  memset(pixels_, 0, kWidth * kHeight * sizeof(lv_color_t));
  hasLastPainted_ = false;
  canvas_ = lv_canvas_create(parent);
  lv_canvas_set_buffer(canvas_, pixels_, kWidth, kHeight, LV_IMG_CF_TRUE_COLOR);
  const auto position = viewport_.toPhysical(kLeft, kTop);
  lv_obj_set_pos(canvas_, static_cast<lv_coord_t>(roundf(position.x)),
                 static_cast<lv_coord_t>(roundf(position.y)));
  if (viewport_.lvglZoom() != 256) {
    lv_img_set_pivot(canvas_, 0, 0);
    lv_img_set_zoom(canvas_, viewport_.lvglZoom());
  }
  lv_obj_clear_flag(canvas_, LV_OBJ_FLAG_CLICKABLE | LV_OBJ_FLAG_SCROLLABLE);
  return true;
}

void ExactEyeRenderer::draw(const ExactEyeModel::Frame& frame) {
  draw(frame, CreatureEyeStyle::RenderParams{});
}

void ExactEyeRenderer::draw(const ExactEyeModel::Frame& frame,
                            const CreatureEyeStyle::RenderParams& params) {
  if (canvas_ == nullptr) return;
  const Style style = CreatureEyeStyle::resolve(params);
  const Bounds current = join(eyeBounds(frame.left), eyeBounds(frame.right));
  Bounds dirty = current;
  if (hasLastPainted_) {
    const Bounds previous = {lastPainted_.x1, lastPainted_.y1,
                             lastPainted_.x2 + 1, lastPainted_.y2 + 1};
    dirty = join(current, previous);
  }
  // Bounds are clipped to this canvas by eyeBounds(). Clearing each full row
  // segment, including old geometry, eliminates stale pixels during the
  // open -> U-arc -> reopen transition without invalidating the full canvas.
  for (int y = dirty.y0; y < dirty.y1; ++y) {
    memset(pixels_ + (y - kTop) * kWidth + dirty.x0 - kLeft, 0,
           (dirty.x1 - dirty.x0) * sizeof(lv_color_t));
  }
  paintEye(pixels_, frame.left, pupilFor(frame.left, style, true, params),
           style, frame.closure);
  paintEye(pixels_, frame.right, pupilFor(frame.right, style, false, params),
           style, frame.closure);
  const lv_area_t changed = {static_cast<lv_coord_t>(dirty.x0),
                             static_cast<lv_coord_t>(dirty.y0),
                             static_cast<lv_coord_t>(dirty.x1 - 1),
                             static_cast<lv_coord_t>(dirty.y1 - 1)};
  if (viewport_.isIdentity()) lv_obj_invalidate_area(canvas_, &changed);
  else lv_obj_invalidate(canvas_);
  lastPainted_ = {static_cast<lv_coord_t>(current.x0),
                  static_cast<lv_coord_t>(current.y0),
                  static_cast<lv_coord_t>(current.x1 - 1),
                  static_cast<lv_coord_t>(current.y1 - 1)};
  hasLastPainted_ = true;
}

void ExactEyeRenderer::draw(const FaceMotion::Frame& frame) {
  if (canvas_ == nullptr) return;
  Bounds current{kLeft + kWidth, kTop + kHeight, kLeft, kTop};
  const bool hasEffects = (frame.effects & (FaceMotion::Sparkle |
                                            FaceMotion::Hearts |
                                            FaceMotion::Flash |
                                            FaceMotion::Collision)) != 0;
  if (hasEffects) {
    // Particle/collision/flash extents are not eye-bound. The full round
    // scanline renderer is used by the C3/host target for actual full-disc
    // output; here the retained legacy canvas is only its central crop.
    current = {kLeft, kTop, kLeft + kWidth, kTop + kHeight};
  } else {
    const uint8_t eyeCount = frame.eyeCount > 4 ? 4 : frame.eyeCount;
    for (uint8_t i = 0; i < eyeCount; ++i) {
      const FaceMotion::Eye& eye = frame.eyes[i];
      const float radians = eye.rotation * 0.01745329252F;
      const float c = fabsf(cosf(radians)), s = fabsf(sinf(radians));
      const float halfX = (c * eye.width + s * eye.height) * .5F + 4;
      const float halfY = (s * eye.width + c * eye.height) * .5F + 4;
      const Bounds box{
          static_cast<int>(clamp(floorf(eye.x - halfX), kLeft, kLeft + kWidth)),
          static_cast<int>(clamp(floorf(eye.y - halfY), kTop, kTop + kHeight)),
          static_cast<int>(clamp(ceilf(eye.x + halfX), kLeft, kLeft + kWidth)),
          static_cast<int>(clamp(ceilf(eye.y + halfY), kTop, kTop + kHeight)),
      };
      current = i == 0 ? box : join(current, box);
    }
  }

  Bounds dirty = current;
  if (hasLastPainted_) {
    const Bounds previous = {lastPainted_.x1, lastPainted_.y1,
                             lastPainted_.x2 + 1, lastPainted_.y2 + 1};
    dirty = join(current, previous);
  }
  if (dirty.x0 >= dirty.x1 || dirty.y0 >= dirty.y1) {
    hasLastPainted_ = false;
    return;
  }

  // A physical row is expanded 2x into this 480-logical canvas, while the
  // native round display uses FaceMotionRaster::render240Row directly. Work
  // and LVGL invalidation stay limited to old/new geometry unless an effect
  // deliberately spans the central crop.
  lv_color_t physicalRow[240];
  int sampledY = -1;
  for (int y = dirty.y0; y < dirty.y1; ++y) {
    const int physicalY = y / 2;
    if (sampledY != physicalY) {
      FaceMotionRaster::render240Row(frame,
                                     static_cast<uint16_t>(physicalY),
                                     physicalRow);
      sampledY = physicalY;
    }
    lv_color_t* row = pixels_ + (y - kTop) * kWidth;
    for (int x = dirty.x0; x < dirty.x1; ++x)
      row[x - kLeft] = physicalRow[x / 2];
  }
  const lv_area_t changed = {static_cast<lv_coord_t>(dirty.x0),
                             static_cast<lv_coord_t>(dirty.y0),
                             static_cast<lv_coord_t>(dirty.x1 - 1),
                             static_cast<lv_coord_t>(dirty.y1 - 1)};
  if (viewport_.isIdentity()) lv_obj_invalidate_area(canvas_, &changed);
  else lv_obj_invalidate(canvas_);
  lastPainted_ = {static_cast<lv_coord_t>(current.x0),
                  static_cast<lv_coord_t>(current.y0),
                  static_cast<lv_coord_t>(current.x1 - 1),
                  static_cast<lv_coord_t>(current.y1 - 1)};
  hasLastPainted_ = current.x0 < current.x1 && current.y0 < current.y1;
}

void ExactEyeRenderer::render240Row(const VectorFace::Frame& frame,
                                   uint16_t physicalY,
                                   lv_color_t* output240) {
  VectorFace::render240RowAntialiased(frame, physicalY, output240);
}

void ExactEyeRenderer::draw(const VectorFace::Frame& frame) {
  if (canvas_ == nullptr) return;
  Bounds current{kLeft + kWidth, kTop + kHeight, kLeft, kTop};
  const size_t count = frame.shapeCount > VectorFace::kMaxShapes
                           ? VectorFace::kMaxShapes : frame.shapeCount;
  bool hasShape = false;
  if (frame.background565) {
    current = {kLeft, kTop, kLeft + kWidth, kTop + kHeight};
    hasShape = true;
  }
  for (size_t s = 0; s < count; ++s) {
    const VectorFace::Shape& shape = frame.shapes[s];
    const size_t vertices = shape.vertexCount > VectorFace::kMaxVertices
                               ? VectorFace::kMaxVertices : shape.vertexCount;
    for (size_t p = 0; p < vertices; ++p) {
      const float x = shape.vertices[p].x * 2;
      const float y = shape.vertices[p].y * 2;
      if (!std::isfinite(x) || !std::isfinite(y)) continue;
      const Bounds point{
          static_cast<int>(clamp(floorf(x - 2), kLeft, kLeft + kWidth)),
          static_cast<int>(clamp(floorf(y - 2), kTop, kTop + kHeight)),
          static_cast<int>(clamp(ceilf(x + 2), kLeft, kLeft + kWidth)),
          static_cast<int>(clamp(ceilf(y + 2), kTop, kTop + kHeight))};
      current = hasShape ? join(current, point) : point;
      hasShape = true;
    }
  }
  Bounds dirty = current;
  if (hasLastPainted_) {
    const Bounds previous{lastPainted_.x1, lastPainted_.y1,
                          lastPainted_.x2 + 1, lastPainted_.y2 + 1};
    dirty = hasShape ? join(current, previous) : previous;
  }
  if (dirty.x0 >= dirty.x1 || dirty.y0 >= dirty.y1) {
    hasLastPainted_ = false;
    return;
  }
  lv_color_t physicalRow[240];
  int sampledY = -1;
  for (int y = dirty.y0; y < dirty.y1; ++y) {
    if (sampledY != y / 2) {
      render240Row(frame, static_cast<uint16_t>(y / 2), physicalRow);
      sampledY = y / 2;
    }
    lv_color_t* row = pixels_ + (y - kTop) * kWidth;
    for (int x = dirty.x0; x < dirty.x1; ++x)
      row[x - kLeft] = physicalRow[x / 2];
  }
  const lv_area_t changed{static_cast<lv_coord_t>(dirty.x0),
                          static_cast<lv_coord_t>(dirty.y0),
                          static_cast<lv_coord_t>(dirty.x1 - 1),
                          static_cast<lv_coord_t>(dirty.y1 - 1)};
  if (viewport_.isIdentity()) lv_obj_invalidate_area(canvas_, &changed);
  else lv_obj_invalidate(canvas_);
  lastPainted_ = {static_cast<lv_coord_t>(current.x0),
                  static_cast<lv_coord_t>(current.y0),
                  static_cast<lv_coord_t>(current.x1 - 1),
                  static_cast<lv_coord_t>(current.y1 - 1)};
  hasLastPainted_ = hasShape && current.x0 < current.x1 && current.y0 < current.y1;
}
