// skwasm's paths, contour measures and vertices: path.cpp,
// contour_measure.cpp, vertices.cpp, plus the SkData calls used to hand over
// buffers too large for skwasm's stack.
#ifndef STARLING_SKWASM_PATH_H
#define STARLING_SKWASM_PATH_H

#include "skwasm_base.h"

// --- path.cpp ---------------------------------------------------------------
// Angles are in DEGREES throughout (SkPath's convention); dart:ui's are
// radians and the caller converts.
SKWASM(path_create) sk_ptr path_create(void);
SKWASM(path_dispose) void path_dispose(sk_ptr path);
SKWASM(path_copy) sk_ptr path_copy(sk_ptr path);
SKWASM(path_setFillType) void path_setFillType(sk_ptr path, int32_t fillType);
SKWASM(path_getFillType) int32_t path_getFillType(sk_ptr path);
SKWASM(path_moveTo) void path_moveTo(sk_ptr path, float x, float y);
SKWASM(path_relativeMoveTo) void path_relativeMoveTo(sk_ptr path, float x, float y);
SKWASM(path_lineTo) void path_lineTo(sk_ptr path, float x, float y);
SKWASM(path_relativeLineTo) void path_relativeLineTo(sk_ptr path, float x, float y);
SKWASM(path_quadraticBezierTo)
void path_quadraticBezierTo(sk_ptr path, float x1, float y1, float x2, float y2);
SKWASM(path_relativeQuadraticBezierTo)
void path_relativeQuadraticBezierTo(sk_ptr path, float x1, float y1, float x2,
                                    float y2);
SKWASM(path_cubicTo)
void path_cubicTo(sk_ptr path, float x1, float y1, float x2, float y2, float x3,
                  float y3);
SKWASM(path_relativeCubicTo)
void path_relativeCubicTo(sk_ptr path, float x1, float y1, float x2, float y2,
                          float x3, float y3);
SKWASM(path_conicTo)
void path_conicTo(sk_ptr path, float x1, float y1, float x2, float y2, float w);
SKWASM(path_relativeConicTo)
void path_relativeConicTo(sk_ptr path, float x1, float y1, float x2, float y2,
                          float w);
// rect: 4 floats, LTRB.
SKWASM(path_arcToOval)
void path_arcToOval(sk_ptr path, sk_ptr rect, float startAngle, float sweepAngle,
                    bool forceMoveTo);
// arcSize: SkPath::ArcSize (0 small, 1 large). pathDirection: SkPathDirection
// (0 clockwise, 1 counter-clockwise).
SKWASM(path_arcToRotated)
void path_arcToRotated(sk_ptr path, float rx, float ry, float xAxisRotate,
                       int32_t arcSize, int32_t pathDirection, float x, float y);
SKWASM(path_relativeArcToRotated)
void path_relativeArcToRotated(sk_ptr path, float rx, float ry, float xAxisRotate,
                               int32_t arcSize, int32_t pathDirection, float x,
                               float y);
SKWASM(path_addRect) void path_addRect(sk_ptr path, sk_ptr rect);
SKWASM(path_addOval) void path_addOval(sk_ptr path, sk_ptr oval);
SKWASM(path_addArc)
void path_addArc(sk_ptr path, sk_ptr oval, float startAngle, float sweepAngle);
// points: count * 2 floats, x then y.
SKWASM(path_addPolygon)
void path_addPolygon(sk_ptr path, sk_ptr points, int32_t count, bool close);
// rrectValues: 12 floats — LTRB, then x,y radii for TL, TR, BR, BL.
SKWASM(path_addRRect) void path_addRRect(sk_ptr path, sk_ptr rrectValues);
// matrix33: 9 floats, row-major (SkMatrix order). extendPath:
// SkPath::AddPathMode (0 append, 1 extend).
SKWASM(path_addPath)
void path_addPath(sk_ptr path, sk_ptr other, sk_ptr matrix33, int32_t extendPath);
SKWASM(path_close) void path_close(sk_ptr path);
SKWASM(path_reset) void path_reset(sk_ptr path);
SKWASM(path_contains) bool path_contains(sk_ptr path, float x, float y);
// Transforms in place.
SKWASM(path_transform) void path_transform(sk_ptr path, sk_ptr matrix33);
SKWASM(path_getBounds) void path_getBounds(sk_ptr path, sk_ptr outRect);
// A NEW path, or 0 when the operation fails.
SKWASM(path_combine)
sk_ptr path_combine(int32_t operation, sk_ptr path1, sk_ptr path2);

// --- contour_measure.cpp ----------------------------------------------------
SKWASM(contourMeasureIter_create)
sk_ptr contourMeasureIter_create(sk_ptr path, bool forceClosed, float resScale);
// The next contour's measure (the caller disposes it), or 0 at the end.
SKWASM(contourMeasureIter_next) sk_ptr contourMeasureIter_next(sk_ptr iter);
SKWASM(contourMeasureIter_dispose) void contourMeasureIter_dispose(sk_ptr iter);
SKWASM(contourMeasure_dispose) void contourMeasure_dispose(sk_ptr measure);
SKWASM(contourMeasure_length) float contourMeasure_length(sk_ptr measure);
SKWASM(contourMeasure_isClosed) bool contourMeasure_isClosed(sk_ptr measure);
// outPosition, outTangent: 2 floats each.
SKWASM(contourMeasure_getPosTan)
bool contourMeasure_getPosTan(sk_ptr measure, float distance, sk_ptr outPosition,
                              sk_ptr outTangent);
// A NEW path, or 0 when there is no such segment.
SKWASM(contourMeasure_getSegment)
sk_ptr contourMeasure_getSegment(sk_ptr measure, float startD, float stopD,
                                 bool startWithMoveTo);

// --- vertices.cpp -----------------------------------------------------------
// positions and textureCoordinates: vertexCount * 2 floats. colors:
// vertexCount ARGB words. indices: indexCount uint16. All but positions may
// be 0. The arrays are copied; they need not outlive the call.
SKWASM(vertices_create)
sk_ptr vertices_create(int32_t vertexMode, int32_t vertexCount, sk_ptr positions,
                       sk_ptr textureCoordinates, sk_ptr colors,
                       int32_t indexCount, sk_ptr indices);
SKWASM(vertices_dispose) void vertices_dispose(sk_ptr vertices);

// --- data.cpp ---------------------------------------------------------------
SKWASM(skData_create) sk_ptr skData_create(uint32_t size);
SKWASM(skData_getPointer) sk_ptr skData_getPointer(sk_ptr data);
SKWASM(skData_dispose) void skData_dispose(sk_ptr data);

#endif  // STARLING_SKWASM_PATH_H
