#include "ExactEyeModel.h"

#include <math.h>
#include <esp_random.h>

namespace {
constexpr float kTau = 6.28318530718F;
float clamp(float x, float lo, float hi) {
  return x < lo ? lo : x > hi ? hi : x;
}
float approach(float value, float target, float dt, float tau) {
  return target + (value - target) * expf(-dt / tau);
}
float verticalHeight(float gy) {
  const float y2 = gy * gy;
  return 14 * y2 * y2 - (46.0F / 3) * y2 * gy -
         35.5F * y2 + (71.0F / 6) * gy;
}
float corner(const float (&v)[4], float gx, float gy) {
  const float l = fmaxf(-gx, 0), r = fmaxf(gx, 0);
  const float t = fmaxf(-gy, 0), b = fmaxf(gy, 0);
  return v[0] * l * t + v[1] * r * t + v[2] * l * b + v[3] * r * b;
}
constexpr float kLeftY[4] = {3.8F, -23.2F, -11, -11.7F};
constexpr float kRightY[4] = {-23.5F, 0, 6.5F, -21};
constexpr float kLeftW[4] = {6, 3, 9, -3};
constexpr float kRightW[4] = {3, 7, -2, 5};
constexpr float kLeftH[4] = {-4.5F, -12.5F, 5, 11.5F};
constexpr float kRightH[4] = {-14, -7, -19, 14};
uint32_t randRange(uint32_t lo, uint32_t hi) {
  return lo + esp_random() % (hi - lo + 1);
}
}  // namespace

void ExactEyeModel::begin(uint32_t nowMs) {
  targetX_ = actualX_ = pupilX_ = pupilTargetX_ = 240;
  targetY_ = actualY_ = pupilY_ = pupilTargetY_ = 240;
  lastMs_ = nowMs;
  elapsedMs_ = 0;
  blinkStartMs_ = UINT32_MAX;
  nextBlinkMs_ = randRange(3000, 6000);
}

void ExactEyeModel::setPointer(float x, float y) {
  targetX_ = clamp(x, 0, 480);
  targetY_ = clamp(y, 0, 480);
  setPupilPointer(x, y);
}

void ExactEyeModel::setPupilPointer(float x, float y) {
  pupilTargetX_ = clamp(x, 0, 480);
  pupilTargetY_ = clamp(y, 0, 480);
}

void ExactEyeModel::blink(uint32_t nowMs) {
  (void)nowMs;
  blinkStartMs_ = elapsedMs_;
  blinkHoldMs_ = 150;
  // A scheduled autonomous blink must not restart this explicit blink before
  // its observed close/hold/open sequence has finished.
  nextBlinkMs_ = elapsedMs_ + 650 + randRange(3000, 6000);
}

void ExactEyeModel::cancelBlink() {
  blinkStartMs_ = UINT32_MAX;
  nextBlinkMs_ = elapsedMs_ + randRange(3000, 6000);
}

void ExactEyeModel::update(uint32_t nowMs) {
  // Follow real elapsed time after a slow flush or scheduling delay. Capping
  // dt made blinks and gaze motion run in slow motion whenever frames stalled.
  const uint32_t dt = lastMs_ == 0 ? 0 : nowMs - lastMs_;
  lastMs_ = nowMs;
  elapsedMs_ += dt;
  actualX_ = approach(actualX_, targetX_, dt, 195);
  actualY_ = approach(actualY_, targetY_, dt, 195);
  pupilX_ = approach(pupilX_, pupilTargetX_, dt, 185);
  pupilY_ = approach(pupilY_, pupilTargetY_, dt, 185);
  if (autonomous_ && elapsedMs_ >= nextBlinkMs_) {
    blinkStartMs_ = elapsedMs_;
    blinkHoldMs_ = randRange(80, 220);
    nextBlinkMs_ = elapsedMs_ + randRange(3000, 6000);
  }
}

ExactEyeModel::Frame ExactEyeModel::frame() const {
  const float gx = (actualX_ - 240) / 240;
  const float gy = (actualY_ - 240) / 240;
  const float pgx = (pupilX_ - 240) / 240;
  const float pgy = (pupilY_ - 240) / 240;
  const float t = static_cast<float>(elapsedMs_);
  const float es = autonomous_ ? sinf(kTau * t / 2955 + 2.77F) : 0;
  const float pys = autonomous_ ? sinf(kTau * t / 2955 + 2.909F) : 0;
  const float pxs = autonomous_ ? sinf(kTau * t / 2723 + 1.19F) : 0;
  const float y = 240 + 43 * gy + 9 * gy * gy;
  const float py = 240 + 43 * pgy + 9 * pgy * pgy + 4 + 8.55F * pys;
  const float vh = verticalHeight(gy);
  Eye left{};
  left.x = 171 + 37.75F * gx + 8.25F * gx * gx;
  left.y = y + 9.5F * es + corner(kLeftY, gx, gy);
  left.width = 127 + 19.5F * gx - 17.5F * gx * gx +
               3 * gy + corner(kLeftW, gx, gy);
  left.height = 144 + 12 * gx + gx * gx + vh + corner(kLeftH, gx, gy);
  left.pupilX = 171 + 37.75F * pgx + 8.25F * pgx * pgx +
                22 + 3.3F * pxs;
  left.pupilY = py + corner(kLeftY, pgx, pgy);
  left.pupilWidth = left.width * 0.5F + 2.5F;
  left.pupilHeight = left.height * 0.5F + 2.5F;
  left.shear = 0.10F;
  Eye right{};
  right.x = 308 + 38.25F * gx - 8.25F * gx * gx;
  right.y = y + 9.5F * es + corner(kRightY, gx, gy);
  right.width = 127 - 19.5F * gx - 18.5F * gx * gx +
                3 * gy + corner(kRightW, gx, gy);
  right.height = 144 - 12 * gx + 2 * gx * gx + vh +
                 corner(kRightH, gx, gy);
  right.pupilX = 308 + 38.25F * pgx - 8.25F * pgx * pgx -
                 25 + 3.3F * pxs;
  right.pupilY = py + corner(kRightY, pgx, pgy);
  right.pupilWidth = right.width * 0.5F + 2.5F;
  right.pupilHeight = right.height * 0.5F + 2.5F;
  right.shear = -0.10F;
  float closure = 0;
  if (blinkStartMs_ != UINT32_MAX) {
    const uint32_t e = elapsedMs_ - blinkStartMs_;
    if (e < 180) {
      const float u = 1 - e / 180.0F;
      closure = 1 - u * u;
    } else if (e < 180U + blinkHoldMs_) {
      closure = 1;
    } else if (e < 500U + blinkHoldMs_) {
      const float u = 1 - (e - 180U - blinkHoldMs_) / 320.0F;
      closure = u * u;
    }
  }
  return {left, right, closure};
}
