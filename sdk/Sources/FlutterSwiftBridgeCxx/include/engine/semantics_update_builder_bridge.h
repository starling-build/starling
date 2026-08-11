// Copyright the Starling authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef FLUTTER_SWIFT_SEMANTICS_UPDATE_BUILDER_BRIDGE_H_
#define FLUTTER_SWIFT_SEMANTICS_UPDATE_BUILDER_BRIDGE_H_

#include "swift_bridge_export.h"

#include <swift/bridging>
#include "intrusive_reference_counted.h"
#include "semantics_flags_bridge.h"
#include "spell_out_string_attribute_bridge.h"
#include "locale_string_attribute_bridge.h"
#include "semantics_update_bridge.h"

#include <cstdint>

namespace flutter::swift_bridge {

// Forward declaration for retain/release functions
class SemanticsUpdateBuilderBridge;

}  // namespace flutter::swift_bridge

// Free functions for SWIFT_SHARED_REFERENCE - must be at global scope
void RetainSemanticsUpdateBuilderBridge(
    flutter::swift_bridge::SemanticsUpdateBuilderBridge* p) noexcept;
void ReleaseSemanticsUpdateBuilderBridge(
    flutter::swift_bridge::SemanticsUpdateBuilderBridge* p) noexcept;

namespace flutter::swift_bridge {

// Forward declaration for pimpl
struct SemanticsUpdateBuilderImpl;

/// C++ bridge wrapping Flutter's SemanticsUpdateBuilder.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/semantics.dart:1685-2081`
/// **Original:** `abstract class SemanticsUpdateBuilder` /
///   `_NativeSemanticsUpdateBuilder`
///
/// Accumulates semantics node updates and custom accessibility action updates,
/// then produces a SemanticsUpdateBridge via Build().
///
/// Architecture:
/// - Swift NativeSemanticsUpdateBuilder class wraps SemanticsUpdateBuilderBridge
/// - SemanticsUpdateBuilderBridge stores SemanticsNode and
///   CustomAccessibilityAction maps via pimpl
/// - Build() produces a SemanticsUpdateBridge
/// - Swift ARC handles lifetime via SWIFT_SHARED_REFERENCE
class FLUTTER_SWIFT_BRIDGE_EXPORT
    SWIFT_SHARED_REFERENCE(RetainSemanticsUpdateBuilderBridge,
                           ReleaseSemanticsUpdateBuilderBridge)
        SemanticsUpdateBuilderBridge
    : public IntrusiveReferenceCounted<SemanticsUpdateBuilderBridge> {
 public:
  /// Creates an empty SemanticsUpdateBuilderBridge.
  ///
  /// **Dart Source:** `semantics.dart:1871-1873`
  /// **Original:** `_NativeSemanticsUpdateBuilder()` calling
  ///   `@Native SemanticsUpdateBuilder::Create`
  SemanticsUpdateBuilderBridge();

  ~SemanticsUpdateBuilderBridge();

  /// Updates a semantics node.
  ///
  /// **Dart Source:** `semantics.dart:1969-2057`
  /// **Original:** `@Native _updateNode(...)` calling
  ///   `SemanticsUpdateBuilder::updateNode`
  ///
  /// The flags_bridge parameter provides the SemanticsFlags for this node.
  /// String attributes are passed as parallel arrays of type and data:
  ///   - type 0 = SpellOut (no extra data)
  ///   - type 1 = Locale (data = locale string)
  ///
  /// @param id Node identifier
  /// @param flags_bridge SemanticsFlagsBridge containing the flags
  /// @param actions Bitmask of SemanticsAction values
  /// @param max_value_length Max length for editable text (-1 = no limit)
  /// @param current_value_length Current length of editable text
  /// @param text_selection_base Selection start (-1 = no selection)
  /// @param text_selection_extent Selection end (-1 = no selection)
  /// @param platform_view_id Platform view ID (-1 = not a platform view)
  /// @param scroll_children Count of scrollable children
  /// @param scroll_index Index of first visible child
  /// @param scroll_position Current scroll position
  /// @param scroll_extent_max Maximum scroll extent
  /// @param scroll_extent_min Minimum scroll extent
  /// @param left/top/right/bottom Node rect in local coordinates
  /// @param identifier Automation identifier string
  /// @param label Accessibility label
  /// @param label_attribute_count Number of label string attributes
  /// @param label_attribute_types Array of attribute types (0=SpellOut, 1=Locale)
  /// @param label_attribute_starts Array of attribute start positions
  /// @param label_attribute_ends Array of attribute end positions
  /// @param label_attribute_locales Array of locale strings (empty for SpellOut)
  /// @param value Accessibility value
  /// @param value_attribute_count, etc. - same pattern for value attributes
  /// @param increased_value, etc. - same pattern for increased value
  /// @param decreased_value, etc. - same pattern for decreased value
  /// @param hint, etc. - same pattern for hint
  /// @param tooltip Tooltip string
  /// @param text_direction 0=unknown, 1=RTL, 2=LTR
  /// @param transform Pointer to 16 doubles (column-major 4x4 matrix)
  /// @param transform_length Number of doubles in transform (must be 16)
  /// @param children_in_traversal_order Pointer to int32 array of child IDs
  /// @param children_in_traversal_order_length Number of children
  /// @param children_in_hit_test_order Pointer to int32 array of child IDs
  /// @param children_in_hit_test_order_length Number of children
  /// @param additional_actions Pointer to int32 array of action IDs
  /// @param additional_actions_length Number of additional actions
  /// @param heading_level Heading level (0 = not a heading, 1-6)
  /// @param link_url URL if this is a link, empty string otherwise
  /// @param role SemanticsRole enum index
  /// @param controls_nodes Comma-separated list of controlled node IDs, or empty
  /// @param has_controls_nodes Whether controls_nodes is present
  /// @param validation_result SemanticsValidationResult enum index
  /// @param input_type SemanticsInputType enum index
  /// @param locale BCP 47 locale string, or empty
  /// Uses const char* instead of std::string to avoid ABI mismatch between
  /// Swift (std::__1::) and Flutter engine (std::_fl::).
  void UpdateNode(
      int32_t id,
      SemanticsFlagsBridge* flags_bridge,
      int32_t actions,
      int32_t max_value_length,
      int32_t current_value_length,
      int32_t text_selection_base,
      int32_t text_selection_extent,
      int32_t platform_view_id,
      int32_t scroll_children,
      int32_t scroll_index,
      double scroll_position,
      double scroll_extent_max,
      double scroll_extent_min,
      double left,
      double top,
      double right,
      double bottom,
      const char* identifier,
      const char* label,
      int32_t label_attribute_count,
      const int32_t* label_attribute_types,
      const int32_t* label_attribute_starts,
      const int32_t* label_attribute_ends,
      const char* const* label_attribute_locales,
      const char* value,
      int32_t value_attribute_count,
      const int32_t* value_attribute_types,
      const int32_t* value_attribute_starts,
      const int32_t* value_attribute_ends,
      const char* const* value_attribute_locales,
      const char* increased_value,
      int32_t increased_value_attribute_count,
      const int32_t* increased_value_attribute_types,
      const int32_t* increased_value_attribute_starts,
      const int32_t* increased_value_attribute_ends,
      const char* const* increased_value_attribute_locales,
      const char* decreased_value,
      int32_t decreased_value_attribute_count,
      const int32_t* decreased_value_attribute_types,
      const int32_t* decreased_value_attribute_starts,
      const int32_t* decreased_value_attribute_ends,
      const char* const* decreased_value_attribute_locales,
      const char* hint,
      int32_t hint_attribute_count,
      const int32_t* hint_attribute_types,
      const int32_t* hint_attribute_starts,
      const int32_t* hint_attribute_ends,
      const char* const* hint_attribute_locales,
      const char* tooltip,
      int32_t text_direction,
      const double* transform,
      int32_t transform_length,
      const int32_t* children_in_traversal_order,
      int32_t children_in_traversal_order_length,
      const int32_t* children_in_hit_test_order,
      int32_t children_in_hit_test_order_length,
      const int32_t* additional_actions,
      int32_t additional_actions_length,
      int32_t heading_level,
      const char* link_url,
      int32_t role,
      const char* controls_nodes,
      bool has_controls_nodes,
      int32_t validation_result,
      int32_t input_type,
      const char* locale);

  /// Updates a custom accessibility action.
  ///
  /// **Dart Source:** `semantics.dart:2064-2067`
  /// **Original:** `@Native _updateCustomAction(int id, String label,
  ///   String hint, int overrideId)`
  ///
  /// @param id Action identifier
  /// @param label Action label (displayed to user)
  /// @param hint Action hint (describes what happens)
  /// @param override_id If >= 0, overrides a standard SemanticsAction
  /// Uses const char* instead of std::string to avoid ABI mismatch.
  void UpdateCustomAction(int32_t id,
                          const char* label,
                          const char* hint,
                          int32_t override_id);

  /// Builds the SemanticsUpdate from accumulated nodes and actions.
  ///
  /// **Dart Source:** `semantics.dart:2070-2074`
  /// **Original:** `SemanticsUpdate build()` calling `@Native _build`
  ///
  /// Creates a SemanticsUpdateBridge containing all accumulated node and
  /// action updates. After calling Build(), this builder should not be used.
  ///
  /// @return New SemanticsUpdateBridge containing the accumulated updates
  SemanticsUpdateBridge* Build() SWIFT_RETURNS_RETAINED;

 private:
  SemanticsUpdateBuilderBridge(const SemanticsUpdateBuilderBridge&) = delete;
  SemanticsUpdateBuilderBridge& operator=(
      const SemanticsUpdateBuilderBridge&) = delete;

  // Pimpl - holds SemanticsNodeUpdates and CustomAccessibilityActionUpdates
  SemanticsUpdateBuilderImpl* impl_;
};

}  // namespace flutter::swift_bridge

// Inline definitions for global retain/release functions
inline void RetainSemanticsUpdateBuilderBridge(
    flutter::swift_bridge::SemanticsUpdateBuilderBridge* p) noexcept {
  p->Retain();
}
inline void ReleaseSemanticsUpdateBuilderBridge(
    flutter::swift_bridge::SemanticsUpdateBuilderBridge* p) noexcept {
  p->Release();
}

#endif  // FLUTTER_SWIFT_SEMANTICS_UPDATE_BUILDER_BRIDGE_H_
