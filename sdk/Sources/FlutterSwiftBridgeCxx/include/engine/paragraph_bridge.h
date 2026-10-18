// Copyright the Starling authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef FLUTTER_SWIFT_PARAGRAPH_BRIDGE_H_
#define FLUTTER_SWIFT_PARAGRAPH_BRIDGE_H_

#include "swift_bridge_export.h"

#include <cstddef>
#include <cstdint>
#include <swift/bridging>
#include "intrusive_reference_counted.h"

namespace flutter::swift_bridge {

// Forward declaration for retain/release functions
class ParagraphBridge;

}  // namespace flutter::swift_bridge

// Free functions for SWIFT_SHARED_REFERENCE - must be at global scope
void RetainParagraphBridge(flutter::swift_bridge::ParagraphBridge* p) noexcept;
void ReleaseParagraphBridge(
    flutter::swift_bridge::ParagraphBridge* p) noexcept;

namespace flutter::swift_bridge {

// Forward declarations for pimpl and bridge types
struct ParagraphImpl;
class CanvasBridge;

/// C++ bridge wrapping Flutter's Paragraph class.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/text.dart:2966-3149`
/// **Original Name:** `Paragraph` (abstract) / `_NativeParagraph` (impl)
///
/// This bridge wraps a std::unique_ptr<txt::Paragraph> which represents
/// laid out text. The paragraph can be rendered via Canvas.drawParagraph
/// and provides methods for hit testing and metrics.
///
/// Architecture:
/// - Swift NativeParagraph class wraps ParagraphBridge
/// - ParagraphBridge holds std::unique_ptr<txt::Paragraph> via pimpl pattern
/// - Swift ARC handles lifetime via SWIFT_SHARED_REFERENCE
/// - Created by ParagraphBuilderBridge::Build()
///
/// Key methods:
/// - Metrics getters: width, height, longestLine, baselines, etc.
/// - Layout: layout(width)
/// - Hit testing: getPositionForOffset, getWordBoundary, getLineBoundary
/// - Box queries: getBoxesForRange, getBoxesForPlaceholders
/// - Line metrics: computeLineMetrics, getLineMetricsAt, numberOfLines
/// - Glyph info: getGlyphInfoAt, getClosestGlyphInfoForOffset
class FLUTTER_SWIFT_BRIDGE_EXPORT
    SWIFT_SHARED_REFERENCE(RetainParagraphBridge, ReleaseParagraphBridge)
        ParagraphBridge
    : public IntrusiveReferenceCounted<ParagraphBridge> {
 public:
  /// Creates a ParagraphBridge wrapping a txt::Paragraph.
  ///
  /// The paragraph pointer is passed as void* to avoid exposing Flutter engine
  /// types in the Swift-compatible header. The caller must pass a pointer
  /// to a std::unique_ptr<txt::Paragraph>.
  ///
  /// @param paragraph_ptr Opaque pointer to std::unique_ptr<txt::Paragraph>
  explicit ParagraphBridge(void* paragraph_ptr);

  ~ParagraphBridge();

  // MARK: - Metrics Getters

  /// The amount of horizontal space this paragraph occupies.
  ///
  /// **Dart Source:** `text.dart:3161-3162`
  /// **Original:** `@Native<Double Function(Pointer<Void>)>(symbol:
  /// 'Paragraph::width')`
  double GetWidth() const;

  /// The amount of vertical space this paragraph occupies.
  ///
  /// **Dart Source:** `text.dart:3165-3166`
  double GetHeight() const;

  /// The distance from the left edge of the leftmost glyph to the right edge
  /// of the rightmost glyph in the paragraph.
  ///
  /// **Dart Source:** `text.dart:3168-3170`
  double GetLongestLine() const;

  /// The minimum width that this paragraph could be without failing to paint
  /// its contents within itself.
  ///
  /// **Dart Source:** `text.dart:3173-3174`
  double GetMinIntrinsicWidth() const;

  /// Returns the smallest width beyond which increasing the width never
  /// decreases the height.
  ///
  /// **Dart Source:** `text.dart:3177-3178`
  double GetMaxIntrinsicWidth() const;

  /// The distance from the top of the paragraph to the alphabetic
  /// baseline of the first line.
  ///
  /// **Dart Source:** `text.dart:3181-3182`
  double GetAlphabeticBaseline() const;

  /// The distance from the top of the paragraph to the ideographic
  /// baseline of the first line.
  ///
  /// **Dart Source:** `text.dart:3185-3186`
  double GetIdeographicBaseline() const;

  /// True if there is more vertical content, but the text was truncated.
  ///
  /// **Dart Source:** `text.dart:3189-3190`
  bool DidExceedMaxLines() const;

  /// The total number of visible lines in the paragraph.
  ///
  /// **Dart Source:** `text.dart:3350-3351`
  size_t GetNumberOfLines() const;

  // MARK: - Layout

  /// Computes the size and position of each glyph in the paragraph.
  ///
  /// **Dart Source:** `text.dart:3201-3202`
  /// **Original:** `@Native<Void Function(Pointer<Void>, Double)>(symbol:
  /// 'Paragraph::layout')`
  void Layout(double width);

  // MARK: - Box Queries

  /// Returns a list of text boxes that enclose the given text range.
  ///
  /// **Dart Source:** `text.dart:3234-3238`
  /// **Original:** `@Native<Handle Function(Pointer<Void>, Uint32, Uint32,
  /// Uint32, Uint32)>`
  ///
  /// Returns Float32 array encoded as: [left, top, right, bottom, direction]
  /// per box. The array size will be boxes.size() * 5.
  ///
  /// @param start Start index of the range
  /// @param end End index of the range
  /// @param box_height_style BoxHeightStyle enum value (0-5)
  /// @param box_width_style BoxWidthStyle enum value (0-1)
  /// @param out_data Output buffer for box data (caller allocates)
  /// @param out_count Output: number of boxes written
  /// @param max_boxes Maximum number of boxes that can fit in out_data
  void GetBoxesForRange(unsigned start,
                        unsigned end,
                        unsigned box_height_style,
                        unsigned box_width_style,
                        float* out_data,
                        size_t* out_count,
                        size_t max_boxes) const;

  /// Returns the number of boxes for the given range (for pre-allocation).
  size_t GetBoxesForRangeCount(unsigned start,
                               unsigned end,
                               unsigned box_height_style,
                               unsigned box_width_style) const;

  /// Returns a list of text boxes that enclose all placeholders.
  ///
  /// **Dart Source:** `text.dart:3245-3246`
  ///
  /// @param out_data Output buffer for box data
  /// @param out_count Output: number of boxes written
  /// @param max_boxes Maximum number of boxes that can fit in out_data
  void GetBoxesForPlaceholders(float* out_data,
                               size_t* out_count,
                               size_t max_boxes) const;

  /// Returns the number of placeholder boxes (for pre-allocation).
  size_t GetBoxesForPlaceholdersCount() const;

  // MARK: - Hit Testing

  /// Returns the text position closest to the given offset.
  ///
  /// **Dart Source:** `text.dart:3254-3255`
  ///
  /// @param dx X coordinate
  /// @param dy Y coordinate
  /// @param out_offset Output: the character offset
  /// @param out_affinity Output: affinity (0=upstream, 1=downstream)
  void GetPositionForOffset(double dx,
                            double dy,
                            size_t* out_offset,
                            int* out_affinity) const;

  /// Returns word boundary at the given offset.
  ///
  /// **Dart Source:** `text.dart:3283-3284`
  ///
  /// @param offset Character offset
  /// @param out_start Output: start of word
  /// @param out_end Output: end of word
  void GetWordBoundary(unsigned offset,
                       size_t* out_start,
                       size_t* out_end) const;

  /// Returns line boundary at the given offset.
  ///
  /// **Dart Source:** `text.dart:3310-3311`
  ///
  /// @param offset Character offset
  /// @param out_start Output: start of line (-1 if not found)
  /// @param out_end Output: end of line (-1 if not found)
  void GetLineBoundary(unsigned offset,
                       int* out_start,
                       int* out_end) const;

  // MARK: - Glyph Info

  /// Returns the GlyphInfo at the given UTF-16 offset.
  ///
  /// **Dart Source:** `text.dart:3258-3260`
  ///
  /// @param code_unit_offset UTF-16 offset
  /// @param out_bounds_left/top/right/bottom Glyph bounds
  /// @param out_range_start/end Grapheme cluster range
  /// @param out_is_ltr True if left-to-right direction
  /// @return True if glyph was found, false otherwise
  bool GetGlyphInfoAt(unsigned code_unit_offset,
                      double* out_bounds_left,
                      double* out_bounds_top,
                      double* out_bounds_right,
                      double* out_bounds_bottom,
                      size_t* out_range_start,
                      size_t* out_range_end,
                      bool* out_is_ltr) const;

  /// Returns the GlyphInfo closest to the given offset.
  ///
  /// **Dart Source:** `text.dart:3263-3268`
  ///
  /// @return True if glyph was found, false otherwise
  bool GetClosestGlyphInfoForOffset(double dx,
                                    double dy,
                                    double* out_bounds_left,
                                    double* out_bounds_top,
                                    double* out_bounds_right,
                                    double* out_bounds_bottom,
                                    size_t* out_range_start,
                                    size_t* out_range_end,
                                    bool* out_is_ltr) const;

  // MARK: - Line Metrics

  /// Returns all line metrics.
  ///
  /// **Dart Source:** `text.dart:3341-3342`
  ///
  /// Each line is 9 doubles: hard_break, ascent, descent, unscaled_ascent,
  /// height, width, left, baseline, line_number.
  ///
  /// @param out_data Output buffer for metrics data
  /// @param out_count Output: number of lines written
  /// @param max_lines Maximum number of lines that can fit in out_data
  void ComputeLineMetrics(double* out_data,
                          size_t* out_count,
                          size_t max_lines) const;

  /// Returns the number of lines (for pre-allocation).
  size_t ComputeLineMetricsCount() const;

  /// Starling: each line's advance — how far it moves the next line down,
  /// a strut's and a line spacing's room included, where ComputeLineMetrics'
  /// height is the runs' ascent plus descent. The lines' advances add up
  /// to the paragraph's height. Returns the number written.
  size_t ComputeLineAdvances(double* out_data, size_t max_lines) const;

  /// Starling: report each line's height with its fraction (ascent plus
  /// descent, unrounded) — set by the builder for a paragraph whose style
  /// keeps its lines' fractions, so its lines add up to its height.
  void SetFractionalLineHeights(bool value);

  /// Returns the line metrics at the given line number.
  ///
  /// **Dart Source:** `text.dart:3346-3347`
  ///
  /// @param line_number Zero-indexed line number
  /// @param out_hard_break/ascent/descent/etc Output metrics fields
  /// @return True if line was found, false otherwise
  bool GetLineMetricsAt(int line_number,
                        bool* out_hard_break,
                        double* out_ascent,
                        double* out_descent,
                        double* out_unscaled_ascent,
                        double* out_height,
                        double* out_width,
                        double* out_left,
                        double* out_baseline,
                        int* out_line_number) const;

  /// Returns the line number for the given code unit offset.
  ///
  /// **Dart Source:** `text.dart:3359-3360`
  ///
  /// @return Line number, or -1 if not found
  int GetLineNumberAt(size_t code_unit_offset) const;

  // MARK: - Painting

  /// Paints the paragraph onto a canvas at the given offset.
  ///
  /// **Dart Source:** `text.dart:3316-3317`
  /// **Original:** `@Native<Void Function(Pointer<Void>, Pointer<Void>, Double,
  /// Double)>`
  ///
  /// @param canvas_bridge The canvas to paint onto
  /// @param x X offset
  /// @param y Y offset
  void Paint(CanvasBridge* canvas_bridge, double x, double y);

  // MARK: - Lifecycle

  /// Releases the underlying paragraph.
  ///
  /// **Dart Source:** `text.dart:3374-3375`
  void Dispose();

  /// Whether Dispose() has been called.
  bool IsDisposed() const;

 private:
  ParagraphBridge(const ParagraphBridge&) = delete;
  ParagraphBridge& operator=(const ParagraphBridge&) = delete;

  // Pimpl - holds the actual Flutter types (unique_ptr<txt::Paragraph>)
  ParagraphImpl* impl_;
};

}  // namespace flutter::swift_bridge

// Inline definitions for global retain/release functions
inline void RetainParagraphBridge(
    flutter::swift_bridge::ParagraphBridge* p) noexcept {
  p->Retain();
}
inline void ReleaseParagraphBridge(
    flutter::swift_bridge::ParagraphBridge* p) noexcept {
  p->Release();
}

#endif  // FLUTTER_SWIFT_PARAGRAPH_BRIDGE_H_
