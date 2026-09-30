// skwasm's exports, declared as WebAssembly imports.
//
// skwasm is Flutter's own web renderer: Skia and DisplayList compiled with
// Emscripten, exporting a C ABI (engine: lib/web_ui/skwasm/*.cpp, every
// function marked SKWASM_EXPORT). It is a SEPARATE wasm module with its own
// linear memory. That has one consequence that shapes everything here:
//
//   A pointer returned by skwasm is an address in SKWASM's memory.
//   It must never be dereferenced from Swift.
//
// So every handle and every skwasm-side pointer is a plain uint32_t, and
// nothing in this header is a C pointer except the two host copy functions,
// whose Swift-side argument really is an address in our own memory. Buffers
// skwasm reads (a rect, a string) are allocated on skwasm's stack and filled
// with starling_host_write.
//
// The declarations mirror the .cpp signatures by hand, one header per area
// (skwasm_<area>.h), all including skwasm_base.h. C permits the same function
// to be declared twice, so an overlap between headers is harmless.
#ifndef STARLING_SKWASM_H
#define STARLING_SKWASM_H

#include "skwasm_base.h"

// --- surface.cpp ------------------------------------------------------------
SKWASM(surface_create) sk_ptr surface_create(void);
SKWASM(surface_setCallbackHandler)
void surface_setCallbackHandler(sk_ptr surface, uint32_t tableIndex);
SKWASM(surface_renderPictures)
uint32_t surface_renderPictures(sk_ptr surface, sk_ptr pictures, int32_t width,
                                int32_t height, int32_t count);

// --- picture.cpp ------------------------------------------------------------
SKWASM(pictureRecorder_create) sk_ptr pictureRecorder_create(void);
SKWASM(pictureRecorder_dispose) void pictureRecorder_dispose(sk_ptr recorder);
SKWASM(pictureRecorder_beginRecording)
sk_ptr pictureRecorder_beginRecording(sk_ptr recorder, sk_ptr cullRect);
SKWASM(pictureRecorder_endRecording)
sk_ptr pictureRecorder_endRecording(sk_ptr recorder);
SKWASM(picture_dispose) void picture_dispose(sk_ptr picture);

// --- paint.cpp --------------------------------------------------------------
SKWASM(paint_create)
sk_ptr paint_create(bool isAntiAlias, int32_t blendMode, uint32_t color,
                    int32_t style, float strokeWidth, int32_t strokeCap,
                    int32_t strokeJoin, float strokeMiterLimit,
                    bool invertColors);
SKWASM(paint_dispose) void paint_dispose(sk_ptr paint);

// --- canvas.cpp -------------------------------------------------------------
SKWASM(canvas_save) void canvas_save(sk_ptr canvas);
SKWASM(canvas_restore) void canvas_restore(sk_ptr canvas);
SKWASM(canvas_translate) void canvas_translate(sk_ptr canvas, float dx, float dy);
SKWASM(canvas_scale) void canvas_scale(sk_ptr canvas, float sx, float sy);
SKWASM(canvas_drawColor)
void canvas_drawColor(sk_ptr canvas, uint32_t color, int32_t blendMode);
SKWASM(canvas_drawLine)
void canvas_drawLine(sk_ptr canvas, float x1, float y1, float x2, float y2,
                     sk_ptr paint);
SKWASM(canvas_drawRect) void canvas_drawRect(sk_ptr canvas, sk_ptr rect, sk_ptr paint);
SKWASM(canvas_drawRRect)
void canvas_drawRRect(sk_ptr canvas, sk_ptr rrectValues, sk_ptr paint);
SKWASM(canvas_drawCircle)
void canvas_drawCircle(sk_ptr canvas, float x, float y, float radius, sk_ptr paint);
SKWASM(canvas_drawPath) void canvas_drawPath(sk_ptr canvas, sk_ptr path, sk_ptr paint);
SKWASM(canvas_drawParagraph)
void canvas_drawParagraph(sk_ptr canvas, sk_ptr paragraph, float x, float y);

// --- path.cpp ---------------------------------------------------------------
SKWASM(path_create) sk_ptr path_create(void);
SKWASM(path_dispose) void path_dispose(sk_ptr path);
SKWASM(path_moveTo) void path_moveTo(sk_ptr path, float x, float y);
SKWASM(path_lineTo) void path_lineTo(sk_ptr path, float x, float y);
SKWASM(path_cubicTo)
void path_cubicTo(sk_ptr path, float x1, float y1, float x2, float y2, float x3,
                  float y3);
SKWASM(path_close) void path_close(sk_ptr path);

// --- string.cpp -------------------------------------------------------------
SKWASM(skString_allocate) sk_ptr skString_allocate(uint32_t length);
SKWASM(skString_getData) sk_ptr skString_getData(sk_ptr string);
SKWASM(skString_free) void skString_free(sk_ptr string);
SKWASM(skString16_allocate) sk_ptr skString16_allocate(uint32_t length);
SKWASM(skString16_getData) sk_ptr skString16_getData(sk_ptr string);
SKWASM(skString16_free) void skString16_free(sk_ptr string);

// --- fonts.cpp --------------------------------------------------------------
SKWASM(fontCollection_create) sk_ptr fontCollection_create(void);
SKWASM(typeface_create) sk_ptr typeface_create(sk_ptr fontData);
SKWASM(fontCollection_registerTypeface)
void fontCollection_registerTypeface(sk_ptr collection, sk_ptr typeface,
                                     sk_ptr fontName);
SKWASM(skData_dispose) void skData_dispose(sk_ptr data);

// --- text/ ------------------------------------------------------------------
SKWASM(paragraphStyle_create) sk_ptr paragraphStyle_create(void);
SKWASM(paragraphStyle_dispose) void paragraphStyle_dispose(sk_ptr style);
SKWASM(paragraphStyle_setTextStyle)
void paragraphStyle_setTextStyle(sk_ptr style, sk_ptr textStyle);
SKWASM(textStyle_create) sk_ptr textStyle_create(void);
SKWASM(textStyle_dispose) void textStyle_dispose(sk_ptr style);
SKWASM(textStyle_setColor) void textStyle_setColor(sk_ptr style, uint32_t color);
SKWASM(textStyle_setFontSize) void textStyle_setFontSize(sk_ptr style, float size);
SKWASM(textStyle_setFontStyle)
void textStyle_setFontStyle(sk_ptr style, int32_t weight, int32_t slant);
SKWASM(textStyle_addFontFamilies)
void textStyle_addFontFamilies(sk_ptr style, sk_ptr fontFamilies, int32_t count);
SKWASM(paragraphBuilder_create)
sk_ptr paragraphBuilder_create(sk_ptr style, sk_ptr collection);
SKWASM(paragraphBuilder_dispose) void paragraphBuilder_dispose(sk_ptr builder);
SKWASM(paragraphBuilder_pushStyle)
void paragraphBuilder_pushStyle(sk_ptr builder, sk_ptr style);
SKWASM(paragraphBuilder_pop) void paragraphBuilder_pop(sk_ptr builder);
SKWASM(paragraphBuilder_addText)
void paragraphBuilder_addText(sk_ptr builder, sk_ptr text16);
SKWASM(paragraphBuilder_build) sk_ptr paragraphBuilder_build(sk_ptr builder);
SKWASM(paragraph_dispose) void paragraph_dispose(sk_ptr paragraph);
SKWASM(paragraph_layout) void paragraph_layout(sk_ptr paragraph, float width);
SKWASM(paragraph_getHeight) float paragraph_getHeight(sk_ptr paragraph);
SKWASM(paragraph_getLongestLine) float paragraph_getLongestLine(sk_ptr paragraph);

#endif  // STARLING_SKWASM_H
