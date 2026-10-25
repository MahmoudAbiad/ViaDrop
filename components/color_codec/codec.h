// SPDX-License-Identifier: MPL-2.0
// Copyright 2026 Mahmoud Abiad
#pragma once
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
// Caller-owned buffers. No files, paths, sockets or retained camera memory.
// 0 success; -1 invalid input; -2 insufficient output; -3 decode/codec failure.
int vd_color_dimensions(int* width, int* height);
int vd_color_encode(const uint8_t* packet, size_t length, uint8_t* rgb,
                    size_t capacity, size_t* written);
int vd_color_decode(const uint8_t* rgb, size_t length, int width, int height,
                    size_t row_stride, int rectified, uint8_t* packet,
                    size_t capacity, size_t* written);
#ifdef __cplusplus
}
#endif
