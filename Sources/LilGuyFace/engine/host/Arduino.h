#pragma once

#include <stdint.h>
#include <algorithm>

extern uint32_t testMillis;
inline uint32_t millis() { return testMillis; }
inline uint32_t micros() { return testMillis * 1000; }
template <typename T> inline T constrain(T value, T lo, T hi) {
  return std::max(lo, std::min(value, hi));
}
template <typename T> inline T min(T a, T b) { return std::min(a, b); }
template <typename T> inline T max(T a, T b) { return std::max(a, b); }
struct TestSerial {
  void println(const char*) const {}
  template <typename... Args> void printf(const char*, Args...) const {}
};
inline TestSerial Serial;
