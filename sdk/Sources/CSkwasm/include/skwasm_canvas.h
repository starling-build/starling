// canvas.cpp, and what a paint needs from filters.cpp.
#ifndef STARLING_SKWASM_CANVAS_H
#define STARLING_SKWASM_CANVAS_H

#include "skwasm_base.h"

SKWASM(canvas_saveLayer)
void canvas_saveLayer(sk_ptr canvas, sk_ptr rect, sk_ptr paint, sk_ptr backdrop);
SKWASM(canvas_restoreToCount) void canvas_restoreToCount(sk_ptr canvas, int32_t count);
SKWASM(canvas_getSaveCount) int32_t canvas_getSaveCount(sk_ptr canvas);
SKWASM(canvas_rotate) void canvas_rotate(sk_ptr canvas, float degrees);
SKWASM(canvas_skew) void canvas_skew(sk_ptr canvas, float sx, float sy);
SKWASM(canvas_transform) void canvas_transform(sk_ptr canvas, sk_ptr matrix44);
SKWASM(canvas_clipRect)
void canvas_clipRect(sk_ptr canvas, sk_ptr rect, int32_t op, bool antialias);
SKWASM(canvas_clipRRect)
void canvas_clipRRect(sk_ptr canvas, sk_ptr rrectValues, bool antialias);
SKWASM(canvas_clipPath) void canvas_clipPath(sk_ptr canvas, sk_ptr path, bool antialias);
SKWASM(canvas_drawPaint) void canvas_drawPaint(sk_ptr canvas, sk_ptr paint);
SKWASM(canvas_drawDRRect)
void canvas_drawDRRect(sk_ptr canvas, sk_ptr outer, sk_ptr inner, sk_ptr paint);
SKWASM(canvas_drawOval) void canvas_drawOval(sk_ptr canvas, sk_ptr rect, sk_ptr paint);
SKWASM(canvas_drawArc)
void canvas_drawArc(sk_ptr canvas, sk_ptr rect, float startAngleDegrees,
                    float sweepAngleDegrees, bool useCenter, sk_ptr paint);
SKWASM(canvas_drawShadow)
void canvas_drawShadow(sk_ptr canvas, sk_ptr path, float elevation,
                       float devicePixelRatio, uint32_t color,
                       bool transparentOccluder);
SKWASM(canvas_drawPicture) void canvas_drawPicture(sk_ptr canvas, sk_ptr picture);
SKWASM(canvas_drawImage)
void canvas_drawImage(sk_ptr canvas, sk_ptr image, float offsetX, float offsetY,
                      sk_ptr paint, int32_t quality);
SKWASM(canvas_drawImageRect)
void canvas_drawImageRect(sk_ptr canvas, sk_ptr image, sk_ptr sourceRect,
                          sk_ptr destRect, sk_ptr paint, int32_t quality);
SKWASM(canvas_drawImageNine)
void canvas_drawImageNine(sk_ptr canvas, sk_ptr image, sk_ptr centerIRect,
                          sk_ptr destRect, sk_ptr paint, int32_t quality);
SKWASM(canvas_drawVertices)
void canvas_drawVertices(sk_ptr canvas, sk_ptr vertices, int32_t mode, sk_ptr paint);
SKWASM(canvas_drawPoints)
void canvas_drawPoints(sk_ptr canvas, int32_t mode, sk_ptr points,
                       int32_t pointCount, sk_ptr paint);
SKWASM(canvas_drawAtlas)
void canvas_drawAtlas(sk_ptr canvas, sk_ptr atlas, sk_ptr transforms, sk_ptr rects,
                      sk_ptr colors, int32_t spriteCount, int32_t mode,
                      sk_ptr cullRect, sk_ptr paint);
SKWASM(canvas_getTransform) void canvas_getTransform(sk_ptr canvas, sk_ptr outMatrix);
SKWASM(canvas_getLocalClipBounds)
void canvas_getLocalClipBounds(sk_ptr canvas, sk_ptr outRect);
SKWASM(canvas_getDeviceClipBounds)
void canvas_getDeviceClipBounds(sk_ptr canvas, sk_ptr outIRect);

SKWASM(paint_setShader) void paint_setShader(sk_ptr paint, sk_ptr shader);
SKWASM(paint_setImageFilter) void paint_setImageFilter(sk_ptr paint, sk_ptr filter);
SKWASM(paint_setColorFilter) void paint_setColorFilter(sk_ptr paint, sk_ptr filter);
SKWASM(paint_setMaskFilter) void paint_setMaskFilter(sk_ptr paint, sk_ptr filter);
SKWASM(maskFilter_createBlur) sk_ptr maskFilter_createBlur(int32_t blurStyle, float sigma);
SKWASM(maskFilter_dispose) void maskFilter_dispose(sk_ptr filter);

SKWASM(picture_getCullRect) void picture_getCullRect(sk_ptr picture, sk_ptr outRect);
SKWASM(picture_approximateBytesUsed) uint32_t picture_approximateBytesUsed(sk_ptr picture);

#endif  // STARLING_SKWASM_CANVAS_H
