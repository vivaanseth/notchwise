#pragma once
#include <stdint.h>
inline uint32_t esp_random() {
  static uint32_t state = 0x41c64e6d;
  state = state * 1664525U + 1013904223U;
  return state;
}
