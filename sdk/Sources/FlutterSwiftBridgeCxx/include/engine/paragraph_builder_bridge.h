// Copyright the Starling authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef FLUTTER_SWIFT_PARAGRAPH_BUILDER_BRIDGE_H_
#define FLUTTER_SWIFT_PARAGRAPH_BUILDER_BRIDGE_H_

#include "swift_bridge_export.h"

#include <cstddef>
#include <cstdint>
#include <swift/bridging>
#include "intrusive_reference_counted.h"

namespace flutter::swift_bridge {

// Forward declaration for retain/release functions
class ParagraphBuilderBridge;

}  // namespace flutter::swift_bridge

// Free functions for SWIFT_SHARED_REFERENCE - must be at global scope
void RetainParagraphBuilderBridge(
    flutter::swift_bridge::ParagraphBuilderBridge* p) noexcept;
void ReleaseParagraphBuilderBridge(
    flutter::swift_bridge::ParagraphBuilderBridge* p) noexcept;

namespace flutter::swift_bridge {

// Forward declarations for pimpl and bridge types
struct ParagraphBuilderImpl;
class ParagraphBridge;

/// C++ bridge wrapping Flutter's ParagraphBuilder class.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/text.dart:3414-3519`
/// **Original Name:** `ParagraphBuilder` (abstract) / `_NativeParagraphBuilder`
/// (impl)
///
/// This bridge wraps txt::ParagraphBuilder which is used to build paragraphs
/// of styled text. It provides methods for pushing styles, adding text,
/// adding placeholders, and building the final paragraph.
///
/// Architecture:
/// - Swift NativeParagraphBuilder class wraps ParagraphBuilderBridge
/// - ParagraphBuilderBridge holds std::unique_ptr<txt::ParagraphBuilder> via
/// pimpl
/// - Swift ARC handles lifetime via SWIFT_SHARED_REFERENCE
/// - Build() produces a ParagraphBridge wrapping the built txt::Paragraph
///
/// Encoding approach:
/// - The constructor takes encoded ParagraphStyle parameters (matches
///   _encodeParagraphStyle from text.dart)
/// - PushStyle takes encoded TextStyle parameters (matches _encodeTextStyle
///   from text.dart)
/// - This allows Swift to pass structured data which the C++ bridge decodes
/// - All encoding constants match those in paragraph_builder.cc
class FLUTTER_SWIFT_BRIDGE_EXPORT SWIFT_SHARED_REFERENCE(
    RetainParagraphBuilderBridge,
    ReleaseParagraphBuilderBridge) ParagraphBuilderBridge
    : public IntrusiveReferenceCounted<ParagraphBuilderBridge> {
 public:
  /// Creates a new ParagraphBuilderBridge with the given ParagraphStyle.
  ///
  /// **Dart Source:** `text.dart:3521-3551`
  /// **Original:** `_NativeParagraphBuilder(ParagraphStyle style)` constructor
  ///
  /// @param encoded_style Int32 array of 7 elements encoding ParagraphStyle
  ///   - [0]: Bitmask indicating which fields are set
  ///   - [1]: textAlign index (if mask & (1<<1))
  ///   - [2]: textDirection index (if mask & (1<<2))
  ///   - [3]: fontWeight index (if mask & (1<<3))
  ///   - [4]: fontStyle index (if mask & (1<<4))
  ///   - [5]: maxLines (if mask & (1<<5))
  ///   - [6]: textHeightBehavior encoded (if mask & (1<<6))
  /// @param font_family Default font family for the paragraph
  /// @param font_size Default font size (0 if not set)
  /// @param height Default height multiplier (0 if not set)
  /// @param ellipsis Ellipsis string (empty if not set)
  /// @param locale Locale string (empty if not set)
  /// @param strut_data ByteData encoding strut style (nullptr if no strut)
  /// @param strut_data_length Length of strut_data in bytes
  /// @param strut_font_families Array of strut font family names
  /// @param strut_font_families_count Number of strut font families
  ParagraphBuilderBridge(const int32_t* encoded_style,
                         size_t encoded_style_length,
                         const char* font_family,
                         double font_size,
                         double height,
                         const char* ellipsis,
                         const char* locale,
                         const uint8_t* strut_data,
                         size_t strut_data_length,
                         const char* const* strut_font_families,
                         size_t strut_font_families_count);

  ~ParagraphBuilderBridge();

  // MARK: - Style Stack

  /// Pushes a TextStyle onto the style stack.
  ///
  /// **Dart Source:** `text.dart:3577-3638`
  /// **Original:** `pushStyle(TextStyle style)` which calls `_pushStyle`
  ///
  /// @param encoded_style Int32 array of 9 elements encoding TextStyle
  ///   - [0]: Bitmask + leadingDistribution in bit 0
  ///   - [1]: color value (if mask & (1<<1))
  ///   - [2]: decoration mask (if mask & (1<<2))
  ///   - [3]: decorationColor value (if mask & (1<<3))
  ///   - [4]: decorationStyle index (if mask & (1<<4))
  ///   - [5]: fontWeight index (if mask & (1<<5))
  ///   - [6]: fontStyle index (if mask & (1<<6))
  ///   - [7]: textBaseline index (if mask & (1<<7))
  ///   - [8]: (unused)
  /// @param font_families Array of font family names
  /// @param font_families_count Number of font families
  /// @param font_size Font size (0 if not set)
  /// @param letter_spacing Letter spacing (0 if not set)
  /// @param word_spacing Word spacing (0 if not set)
  /// @param height Height multiplier (0 if not set)
  /// @param decoration_thickness Decoration thickness (0 if not set)
  /// @param locale Locale string (empty if not set)
  /// @param shadows_data ByteData encoding shadows (nullptr if none)
  ///   Each shadow is 16 bytes: [color:4, x:4, y:4, blur:4]
  /// @param shadows_data_length Length of shadows_data in bytes
  /// @param font_features_data ByteData encoding font features (nullptr if none)
  ///   Each feature is 8 bytes: [tag:4, value:4]
  /// @param font_features_data_length Length of font_features_data in bytes
  /// @param font_variations_data ByteData encoding font variations (nullptr if
  /// none)
  ///   Each variation is 8 bytes: [tag:4, value:4]
  /// @param font_variations_data_length Length of font_variations_data in bytes
  /// @param has_background Whether a background paint is provided
  /// @param has_foreground Whether a foreground paint is provided
  /// @param background_color Background color (used if has_background && not
  /// using paint)
  /// @param foreground_color Foreground color (used if has_foreground && not
  /// using paint)
  void PushStyle(const int32_t* encoded_style,
                 size_t encoded_style_length,
                 const char* const* font_families,
                 size_t font_families_count,
                 double font_size,
                 double letter_spacing,
                 double word_spacing,
                 double height,
                 double decoration_thickness,
                 const char* locale,
                 const uint8_t* shadows_data,
                 size_t shadows_data_length,
                 const uint8_t* font_features_data,
                 size_t font_features_data_length,
                 const uint8_t* font_variations_data,
                 size_t font_variations_data_length,
                 bool has_background,
                 bool has_foreground,
                 uint32_t background_color,
                 uint32_t foreground_color);

  /// Pops the most recent style from the stack.
  ///
  /// **Dart Source:** `text.dart:3681-3683`
  /// **Original:** `pop()`
  void Pop();

  // MARK: - Content

  /// Adds text to the paragraph.
  ///
  /// **Dart Source:** `text.dart:3685-3691`
  /// **Original:** `addText(String text)` which calls `_addText`
  ///
  /// @param text UTF-8 encoded text to add
  /// @return nullptr on success, or error message string if text is malformed
  const char* AddText(const char* text);

  /// Adds text to the paragraph (Swift-safe version).
  ///
  /// **Dart Source:** `text.dart:3685-3691`
  /// **Original:** `addText(String text)` which calls `_addText`
  ///
  /// This version returns a bool instead of a const char*, making it callable
  /// from Swift (Swift C++ interop cannot handle methods returning interior pointers).
  ///
  /// @param text UTF-8 encoded text to add
  /// @return true on success, false if text is malformed or builder is invalid
  bool AddTextSafe(const char* text);

  /// Adds an inline placeholder to the paragraph.
  ///
  /// **Dart Source:** `text.dart:3696-3724`
  /// **Original:** `addPlaceholder(...)` which calls `_addPlaceholder`
  ///
  /// @param width Placeholder width (already scaled)
  /// @param height Placeholder height (already scaled)
  /// @param alignment PlaceholderAlignment index
  /// @param baseline_offset Distance from top to baseline (already scaled)
  /// @param baseline TextBaseline index
  void AddPlaceholder(double width,
                      double height,
                      int alignment,
                      double baseline_offset,
                      int baseline);

  // MARK: - Build

  /// Builds the final Paragraph from the accumulated text and styles.
  ///
  /// **Dart Source:** `text.dart:3737-3742`
  /// **Original:** `build()` which calls `_build`
  ///
  /// After calling Build(), this ParagraphBuilderBridge should not be used
  /// further.
  ///
  /// SWIFT_RETURNS_RETAINED is load bearing: the ParagraphBridge is born with
  /// refcount 1 (IntrusiveReferenceCounted), and this annotation hands that
  /// reference to Swift. Without it, Swift assumes an unretained (+0) return
  /// and adds its own retain — refcount 2, released once by deinit, and the
  /// C++ object (with its txt::Paragraph) never destructs. Constructors do
  /// not need this (interop already treats init as an ownership transfer),
  /// which is why ParagraphBuilderBridge itself was freed correctly while
  /// every built paragraph leaked: [cxx-para] made 200 freed 0 against a
  /// Swift wrapper count of live 47.
  ///
  /// @return New ParagraphBridge wrapping the built txt::Paragraph
  ParagraphBridge* Build() SWIFT_RETURNS_RETAINED;

 private:
  ParagraphBuilderBridge(const ParagraphBuilderBridge&) = delete;
  ParagraphBuilderBridge& operator=(const ParagraphBuilderBridge&) = delete;

  // Pimpl - holds the actual Flutter types (unique_ptr<txt::ParagraphBuilder>)
  ParagraphBuilderImpl* impl_;
};

}  // namespace flutter::swift_bridge

// Inline definitions for global retain/release functions
inline void RetainParagraphBuilderBridge(
    flutter::swift_bridge::ParagraphBuilderBridge* p) noexcept {
  p->Retain();
}
inline void ReleaseParagraphBuilderBridge(
    flutter::swift_bridge::ParagraphBuilderBridge* p) noexcept {
  p->Release();
}

#endif  // FLUTTER_SWIFT_PARAGRAPH_BUILDER_BRIDGE_H_
