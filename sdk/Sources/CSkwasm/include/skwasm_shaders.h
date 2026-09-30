// skwasm's shaders, runtime effects and filters (shaders.cpp, filters.cpp).
//
// Every shader and filter handle here is an `sp_wrapper<T>*`: a heap box
// around a std::shared_ptr. That box is what paint_setShader and friends
// take, and what the *_dispose functions free. The box may hold a null
// shared_ptr — the DisplayList factories return null for a no-op filter (a
// zero-sigma blur, an identity matrix) — and skwasm accepts such a box
// everywhere it accepts a filter.
#ifndef STARLING_SKWASM_SHADERS_H
#define STARLING_SKWASM_SHADERS_H

#include "skwasm_base.h"

// --- shaders.cpp ------------------------------------------------------------
// colors: `count` uint32 ARGB. stops: `count` floats, or 0 for even spacing.
// matrix33: 9 floats, row-major, or 0 for identity. tileMode: DlTileMode
// (clamp, repeat, mirror, decal) — dart:ui's TileMode index.
SKWASM(shader_createLinearGradient)
sk_ptr shader_createLinearGradient(sk_ptr endPoints, sk_ptr colors,
                                   sk_ptr stops, int32_t count,
                                   int32_t tileMode, sk_ptr matrix33);
SKWASM(shader_createRadialGradient)
sk_ptr shader_createRadialGradient(float centerX, float centerY, float radius,
                                   sk_ptr colors, sk_ptr stops, int32_t count,
                                   int32_t tileMode, sk_ptr matrix33);
SKWASM(shader_createConicalGradient)
sk_ptr shader_createConicalGradient(sk_ptr endPoints, float startRadius,
                                    float endRadius, sk_ptr colors,
                                    sk_ptr stops, int32_t count,
                                    int32_t tileMode, sk_ptr matrix33);
// Angles are in degrees.
SKWASM(shader_createSweepGradient)
sk_ptr shader_createSweepGradient(float centerX, float centerY, sk_ptr colors,
                                  sk_ptr stops, int32_t count,
                                  int32_t tileMode, float startAngle,
                                  float endAngle, sk_ptr matrix33);
SKWASM(shader_dispose) void shader_dispose(sk_ptr shader);

// image: an SkImage*. quality: dart:ui's FilterQuality index.
SKWASM(shader_createFromImage)
sk_ptr shader_createFromImage(sk_ptr image, int32_t tileModeX,
                              int32_t tileModeY, int32_t quality,
                              sk_ptr matrix33);

// source: an SkString* of SkSL. Returns 0 when it does not compile.
SKWASM(runtimeEffect_create) sk_ptr runtimeEffect_create(sk_ptr source);
SKWASM(runtimeEffect_dispose) void runtimeEffect_dispose(sk_ptr effect);
SKWASM(runtimeEffect_getUniformSize)
uint32_t runtimeEffect_getUniformSize(sk_ptr effect);

// children: `childCount` shader handles, none of them 0 — skwasm
// dereferences each one.
SKWASM(shader_createRuntimeEffectShader)
sk_ptr shader_createRuntimeEffectShader(sk_ptr runtimeEffect, sk_ptr uniforms,
                                        sk_ptr children, uint32_t childCount);

SKWASM(uniformData_create) sk_ptr uniformData_create(int32_t size);
SKWASM(uniformData_dispose) void uniformData_dispose(sk_ptr data);
SKWASM(uniformData_getPointer) sk_ptr uniformData_getPointer(sk_ptr data);

// --- filters.cpp ------------------------------------------------------------
SKWASM(imageFilter_createBlur)
sk_ptr imageFilter_createBlur(float sigmaX, float sigmaY, int32_t tileMode);
SKWASM(imageFilter_createDilate)
sk_ptr imageFilter_createDilate(float radiusX, float radiusY);
SKWASM(imageFilter_createErode)
sk_ptr imageFilter_createErode(float radiusX, float radiusY);
SKWASM(imageFilter_createMatrix)
sk_ptr imageFilter_createMatrix(sk_ptr matrix33, int32_t quality);
SKWASM(imageFilter_createFromColorFilter)
sk_ptr imageFilter_createFromColorFilter(sk_ptr colorFilter);
SKWASM(imageFilter_compose)
sk_ptr imageFilter_compose(sk_ptr outer, sk_ptr inner);
SKWASM(imageFilter_dispose) void imageFilter_dispose(sk_ptr filter);
// inOutBounds: 4 int32 (left, top, right, bottom), rewritten in place.
SKWASM(imageFilter_getFilterBounds)
void imageFilter_getFilterBounds(sk_ptr filter, sk_ptr inOutBounds);

// color: ARGB. mode: DlBlendMode — dart:ui's BlendMode index.
SKWASM(colorFilter_createMode)
sk_ptr colorFilter_createMode(uint32_t color, int32_t mode);
// matrixData: 20 floats, translation column already scaled to 0...1.
SKWASM(colorFilter_createMatrix) sk_ptr colorFilter_createMatrix(sk_ptr matrixData);
SKWASM(colorFilter_createSRGBToLinearGamma)
sk_ptr colorFilter_createSRGBToLinearGamma(void);
SKWASM(colorFilter_createLinearToSRGBGamma)
sk_ptr colorFilter_createLinearToSRGBGamma(void);
SKWASM(colorFilter_dispose) void colorFilter_dispose(sk_ptr filter);

#endif  // STARLING_SKWASM_SHADERS_H
