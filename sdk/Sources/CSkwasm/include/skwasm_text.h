// skwasm's text exports: paragraphs, their builders and styles, fonts, and
// the strings and data blobs those take (engine: lib/web_ui/skwasm/text/*.cpp,
// fonts.cpp, string.cpp, data.cpp). Enums cross as int32_t by value and keep
// Skia's numbering, which is dart:ui's index for every one used here.
#ifndef STARLING_SKWASM_TEXT_H
#define STARLING_SKWASM_TEXT_H

#include "skwasm_base.h"

// --- string.cpp -------------------------------------------------------------
SKWASM(skString_allocate) sk_ptr skString_allocate(uint32_t length);
SKWASM(skString_getData) sk_ptr skString_getData(sk_ptr string);
SKWASM(skString_getLength) int32_t skString_getLength(sk_ptr string);
SKWASM(skString_free) void skString_free(sk_ptr string);
SKWASM(skString16_allocate) sk_ptr skString16_allocate(uint32_t length);
SKWASM(skString16_getData) sk_ptr skString16_getData(sk_ptr string);
SKWASM(skString16_free) void skString16_free(sk_ptr string);

// --- data.cpp ---------------------------------------------------------------
// An SkData is reference counted: create returns the first reference and
// dispose drops one, so a typeface made from it keeps the bytes alive.
SKWASM(skData_create) sk_ptr skData_create(uint32_t size);
SKWASM(skData_getPointer) sk_ptr skData_getPointer(sk_ptr data);
SKWASM(skData_getConstPointer) sk_ptr skData_getConstPointer(sk_ptr data);
SKWASM(skData_getSize) uint32_t skData_getSize(sk_ptr data);
SKWASM(skData_dispose) void skData_dispose(sk_ptr data);

// --- fonts.cpp --------------------------------------------------------------
SKWASM(fontCollection_create) sk_ptr fontCollection_create(void);
SKWASM(fontCollection_dispose) void fontCollection_dispose(sk_ptr collection);
// Returns 0 when the bytes are not a font. Like SkData, reference counted.
SKWASM(typeface_create) sk_ptr typeface_create(sk_ptr fontData);
SKWASM(typeface_dispose) void typeface_dispose(sk_ptr typeface);
// fontName is an SkString*, or 0 for the family name inside the font file.
SKWASM(fontCollection_registerTypeface)
void fontCollection_registerTypeface(sk_ptr collection, sk_ptr typeface,
                                     sk_ptr fontName);
SKWASM(fontCollection_clearCaches)
void fontCollection_clearCaches(sk_ptr collection);

// --- text/text_style.cpp ----------------------------------------------------
SKWASM(textStyle_create) sk_ptr textStyle_create(void);
SKWASM(textStyle_copy) sk_ptr textStyle_copy(sk_ptr style);
SKWASM(textStyle_dispose) void textStyle_dispose(sk_ptr style);
SKWASM(textStyle_setColor) void textStyle_setColor(sk_ptr style, uint32_t color);
SKWASM(textStyle_setDecoration)
void textStyle_setDecoration(sk_ptr style, int32_t decoration);
SKWASM(textStyle_setDecorationColor)
void textStyle_setDecorationColor(sk_ptr style, uint32_t color);
SKWASM(textStyle_setDecorationStyle)
void textStyle_setDecorationStyle(sk_ptr style, int32_t decorationStyle);
SKWASM(textStyle_setDecorationThickness)
void textStyle_setDecorationThickness(sk_ptr style, float thickness);
// weight is 100...900, slant 0 upright, 1 italic.
SKWASM(textStyle_setFontStyle)
void textStyle_setFontStyle(sk_ptr style, int32_t weight, int32_t slant);
SKWASM(textStyle_setTextBaseline)
void textStyle_setTextBaseline(sk_ptr style, int32_t baseline);
SKWASM(textStyle_clearFontFamilies) void textStyle_clearFontFamilies(sk_ptr style);
// fontFamilies is an array of SkString*. They go IN FRONT of the families
// the style already has.
SKWASM(textStyle_addFontFamilies)
void textStyle_addFontFamilies(sk_ptr style, sk_ptr fontFamilies, int32_t count);
SKWASM(textStyle_setFontSize) void textStyle_setFontSize(sk_ptr style, float size);
SKWASM(textStyle_setLetterSpacing)
void textStyle_setLetterSpacing(sk_ptr style, float letterSpacing);
SKWASM(textStyle_setWordSpacing)
void textStyle_setWordSpacing(sk_ptr style, float wordSpacing);
SKWASM(textStyle_setHeight) void textStyle_setHeight(sk_ptr style, float height);
SKWASM(textStyle_setHalfLeading)
void textStyle_setHalfLeading(sk_ptr style, bool halfLeading);
SKWASM(textStyle_setLocale) void textStyle_setLocale(sk_ptr style, sk_ptr locale);
// The paint is copied; the caller still owns (and disposes) its own.
SKWASM(textStyle_setBackground)
void textStyle_setBackground(sk_ptr style, sk_ptr paint);
SKWASM(textStyle_setForeground)
void textStyle_setForeground(sk_ptr style, sk_ptr paint);
SKWASM(textStyle_addShadow)
void textStyle_addShadow(sk_ptr style, uint32_t color, float offsetX,
                         float offsetY, float blurSigma);
SKWASM(textStyle_addFontFeature)
void textStyle_addFontFeature(sk_ptr style, sk_ptr featureName, int32_t value);
// axes is an array of four-byte tags (first character in the high byte),
// values an array of floats.
SKWASM(textStyle_setFontVariations)
void textStyle_setFontVariations(sk_ptr style, sk_ptr axes, sk_ptr values,
                                 int32_t count);

// --- text/strut_style.cpp ---------------------------------------------------
SKWASM(strutStyle_create) sk_ptr strutStyle_create(void);
SKWASM(strutStyle_dispose) void strutStyle_dispose(sk_ptr style);
SKWASM(strutStyle_setFontFamilies)
void strutStyle_setFontFamilies(sk_ptr style, sk_ptr fontFamilies, int32_t count);
SKWASM(strutStyle_setFontSize) void strutStyle_setFontSize(sk_ptr style, float fontSize);
SKWASM(strutStyle_setHeight) void strutStyle_setHeight(sk_ptr style, float height);
SKWASM(strutStyle_setHalfLeading)
void strutStyle_setHalfLeading(sk_ptr style, bool halfLeading);
SKWASM(strutStyle_setLeading) void strutStyle_setLeading(sk_ptr style, float leading);
SKWASM(strutStyle_setFontStyle)
void strutStyle_setFontStyle(sk_ptr style, int32_t weight, int32_t slant);
SKWASM(strutStyle_setForceStrutHeight)
void strutStyle_setForceStrutHeight(sk_ptr style, bool forceStrutHeight);

// --- text/paragraph_style.cpp -----------------------------------------------
SKWASM(paragraphStyle_create) sk_ptr paragraphStyle_create(void);
SKWASM(paragraphStyle_dispose) void paragraphStyle_dispose(sk_ptr style);
SKWASM(paragraphStyle_setTextAlign)
void paragraphStyle_setTextAlign(sk_ptr style, int32_t align);
SKWASM(paragraphStyle_setTextDirection)
void paragraphStyle_setTextDirection(sk_ptr style, int32_t direction);
SKWASM(paragraphStyle_setMaxLines)
void paragraphStyle_setMaxLines(sk_ptr style, uint32_t maxLines);
SKWASM(paragraphStyle_setHeight)
void paragraphStyle_setHeight(sk_ptr style, float height);
SKWASM(paragraphStyle_setTextHeightBehavior)
void paragraphStyle_setTextHeightBehavior(sk_ptr style,
                                          bool applyHeightToFirstAscent,
                                          bool applyHeightToLastDescent);
SKWASM(paragraphStyle_setEllipsis)
void paragraphStyle_setEllipsis(sk_ptr style, sk_ptr ellipsis);
SKWASM(paragraphStyle_setStrutStyle)
void paragraphStyle_setStrutStyle(sk_ptr style, sk_ptr strutStyle);
SKWASM(paragraphStyle_setTextStyle)
void paragraphStyle_setTextStyle(sk_ptr style, sk_ptr textStyle);
SKWASM(paragraphStyle_setApplyRoundingHack)
void paragraphStyle_setApplyRoundingHack(sk_ptr style, bool applyRoundingHack);

// --- text/paragraph_builder*.cpp --------------------------------------------
SKWASM(paragraphBuilder_create)
sk_ptr paragraphBuilder_create(sk_ptr style, sk_ptr collection);
SKWASM(paragraphBuilder_dispose) void paragraphBuilder_dispose(sk_ptr builder);
SKWASM(paragraphBuilder_addPlaceholder)
void paragraphBuilder_addPlaceholder(sk_ptr builder, float width, float height,
                                     int32_t alignment, float baselineOffset,
                                     int32_t baseline);
SKWASM(paragraphBuilder_addText)
void paragraphBuilder_addText(sk_ptr builder, sk_ptr text16);
SKWASM(paragraphBuilder_pushStyle)
void paragraphBuilder_pushStyle(sk_ptr builder, sk_ptr style);
SKWASM(paragraphBuilder_pop) void paragraphBuilder_pop(sk_ptr builder);
// Without ICU (the light build) this needs starling_host_segment first.
SKWASM(paragraphBuilder_build) sk_ptr paragraphBuilder_build(sk_ptr builder);

// --- text/paragraph.cpp -----------------------------------------------------
SKWASM(paragraph_dispose) void paragraph_dispose(sk_ptr paragraph);
SKWASM(paragraph_getWidth) float paragraph_getWidth(sk_ptr paragraph);
SKWASM(paragraph_getHeight) float paragraph_getHeight(sk_ptr paragraph);
SKWASM(paragraph_getLongestLine) float paragraph_getLongestLine(sk_ptr paragraph);
SKWASM(paragraph_getMinIntrinsicWidth)
float paragraph_getMinIntrinsicWidth(sk_ptr paragraph);
SKWASM(paragraph_getMaxIntrinsicWidth)
float paragraph_getMaxIntrinsicWidth(sk_ptr paragraph);
SKWASM(paragraph_getAlphabeticBaseline)
float paragraph_getAlphabeticBaseline(sk_ptr paragraph);
SKWASM(paragraph_getIdeographicBaseline)
float paragraph_getIdeographicBaseline(sk_ptr paragraph);
SKWASM(paragraph_getDidExceedMaxLines)
bool paragraph_getDidExceedMaxLines(sk_ptr paragraph);
SKWASM(paragraph_layout) void paragraph_layout(sk_ptr paragraph, float width);
// outAffinity: one int32_t, 0 upstream, 1 downstream.
SKWASM(paragraph_getPositionForOffset)
int32_t paragraph_getPositionForOffset(sk_ptr paragraph, float offsetX,
                                       float offsetY, sk_ptr outAffinity);
// Out parameters: four floats (l, t, r, b), two uint32_t (start, end), one
// bool (is left-to-right).
SKWASM(paragraph_getClosestGlyphInfoAtCoordinate)
bool paragraph_getClosestGlyphInfoAtCoordinate(sk_ptr paragraph, float offsetX,
                                               float offsetY, sk_ptr outRect,
                                               sk_ptr outRange,
                                               sk_ptr outFlags);
SKWASM(paragraph_getGlyphInfoAt)
bool paragraph_getGlyphInfoAt(sk_ptr paragraph, uint32_t index, sk_ptr outRect,
                              sk_ptr outRange, sk_ptr outFlags);
// outRange: two int32_t, start and end.
SKWASM(paragraph_getWordBoundary)
void paragraph_getWordBoundary(sk_ptr paragraph, uint32_t position,
                               sk_ptr outRange);
SKWASM(paragraph_getLineCount) uint32_t paragraph_getLineCount(sk_ptr paragraph);
SKWASM(paragraph_getLineNumberAt)
int32_t paragraph_getLineNumberAt(sk_ptr paragraph, uint32_t characterIndex);
// A NEW LineMetrics the caller disposes, or 0 when there is no such line.
SKWASM(paragraph_getLineMetricsAtIndex)
sk_ptr paragraph_getLineMetricsAtIndex(sk_ptr paragraph, uint32_t lineNumber);
// Both return a new TextBoxList the caller disposes.
SKWASM(paragraph_getBoxesForRange)
sk_ptr paragraph_getBoxesForRange(sk_ptr paragraph, int32_t start, int32_t end,
                                  int32_t heightStyle, int32_t widthStyle);
SKWASM(paragraph_getBoxesForPlaceholders)
sk_ptr paragraph_getBoxesForPlaceholders(sk_ptr paragraph);
SKWASM(textBoxList_dispose) void textBoxList_dispose(sk_ptr list);
SKWASM(textBoxList_getLength) uint32_t textBoxList_getLength(sk_ptr list);
// Writes four floats to outRect and returns the box's text direction.
SKWASM(textBoxList_getBoxAtIndex)
int32_t textBoxList_getBoxAtIndex(sk_ptr list, uint32_t index, sk_ptr outRect);
// Valid only after a layout. With outCodePoints 0, returns the count.
SKWASM(paragraph_getUnresolvedCodePoints)
int32_t paragraph_getUnresolvedCodePoints(sk_ptr paragraph,
                                          sk_ptr outCodePoints,
                                          int32_t outLength);

// --- text/line_metrics.cpp --------------------------------------------------
SKWASM(lineMetrics_dispose) void lineMetrics_dispose(sk_ptr metrics);
SKWASM(lineMetrics_getHardBreak) bool lineMetrics_getHardBreak(sk_ptr metrics);
SKWASM(lineMetrics_getAscent) float lineMetrics_getAscent(sk_ptr metrics);
SKWASM(lineMetrics_getDescent) float lineMetrics_getDescent(sk_ptr metrics);
SKWASM(lineMetrics_getUnscaledAscent)
float lineMetrics_getUnscaledAscent(sk_ptr metrics);
SKWASM(lineMetrics_getHeight) float lineMetrics_getHeight(sk_ptr metrics);
SKWASM(lineMetrics_getWidth) float lineMetrics_getWidth(sk_ptr metrics);
SKWASM(lineMetrics_getLeft) float lineMetrics_getLeft(sk_ptr metrics);
SKWASM(lineMetrics_getBaseline) float lineMetrics_getBaseline(sk_ptr metrics);
SKWASM(lineMetrics_getLineNumber) int32_t lineMetrics_getLineNumber(sk_ptr metrics);
SKWASM(lineMetrics_getStartIndex) uint32_t lineMetrics_getStartIndex(sk_ptr metrics);
SKWASM(lineMetrics_getEndIndex) uint32_t lineMetrics_getEndIndex(sk_ptr metrics);

// --- paint.cpp --------------------------------------------------------------
// Only what a text style's foreground and background need; the rest of the
// paint surface is in the canvas family's header.
SKWASM(paint_create)
sk_ptr paint_create(bool isAntiAlias, int32_t blendMode, uint32_t color,
                    int32_t style, float strokeWidth, int32_t strokeCap,
                    int32_t strokeJoin, float strokeMiterLimit,
                    bool invertColors);
SKWASM(paint_dispose) void paint_dispose(sk_ptr paint);

// --- canvas.cpp -------------------------------------------------------------
SKWASM(canvas_drawParagraph)
void canvas_drawParagraph(sk_ptr canvas, sk_ptr paragraph, float x, float y);

#endif  // STARLING_SKWASM_TEXT_H
