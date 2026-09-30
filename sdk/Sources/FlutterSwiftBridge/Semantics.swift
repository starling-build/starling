// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(ucrt)
// Windows: the C library module is ucrt. Without this branch the file gets no
// platform C declarations at all, which is how M_E went missing here.
import ucrt
#elseif os(WASI)
// strdup and free, for the locale arrays handed to UpdateNode.
import WASILibc
#endif
import FlutterSwiftBridgeCxx

// MARK: - SemanticsAction

/// The possible actions that can be conveyed from the operating system
/// accessibility APIs to a semantics node.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/semantics.dart`
/// **Original Name:** `SemanticsAction`
/// **Lines:** 7-356
///
/// DIFFERENCE FROM DART: Using struct instead of class with const constructor.
/// REASON: Swift structs with static let properties are the idiomatic equivalent
/// of Dart classes with static const fields for value-type semantics.
public struct SemanticsAction: Hashable, Sendable, CustomStringConvertible {
  /// The numerical value for this action.
  ///
  /// Each action has one bit set in this bit field.
  ///
  /// **Dart Source:** `semantics.dart:20`
  public let index: Int

  /// A human-readable name for this flag, used for debugging purposes.
  ///
  /// **Dart Source:** `semantics.dart:23`
  public let name: String

  /// **Dart Source:** `semantics.dart:15`
  /// **Original:** `const SemanticsAction._(this.index, this.name);`
  private init(index: Int, name: String) {
    self.index = index
    self.name = name
  }

  // MARK: - Private index constants

  /// **Dart Source:** `semantics.dart:25`
  private static let _kTapIndex: Int = 1 << 0
  /// **Dart Source:** `semantics.dart:26`
  private static let _kLongPressIndex: Int = 1 << 1
  /// **Dart Source:** `semantics.dart:27`
  private static let _kScrollLeftIndex: Int = 1 << 2
  /// **Dart Source:** `semantics.dart:28`
  private static let _kScrollRightIndex: Int = 1 << 3
  /// **Dart Source:** `semantics.dart:29`
  private static let _kScrollUpIndex: Int = 1 << 4
  /// **Dart Source:** `semantics.dart:30`
  private static let _kScrollDownIndex: Int = 1 << 5
  /// **Dart Source:** `semantics.dart:31`
  private static let _kIncreaseIndex: Int = 1 << 6
  /// **Dart Source:** `semantics.dart:32`
  private static let _kDecreaseIndex: Int = 1 << 7
  /// **Dart Source:** `semantics.dart:33`
  private static let _kShowOnScreenIndex: Int = 1 << 8
  /// **Dart Source:** `semantics.dart:34`
  private static let _kMoveCursorForwardByCharacterIndex: Int = 1 << 9
  /// **Dart Source:** `semantics.dart:35`
  private static let _kMoveCursorBackwardByCharacterIndex: Int = 1 << 10
  /// **Dart Source:** `semantics.dart:36`
  private static let _kSetSelectionIndex: Int = 1 << 11
  /// **Dart Source:** `semantics.dart:37`
  private static let _kCopyIndex: Int = 1 << 12
  /// **Dart Source:** `semantics.dart:38`
  private static let _kCutIndex: Int = 1 << 13
  /// **Dart Source:** `semantics.dart:39`
  private static let _kPasteIndex: Int = 1 << 14
  /// **Dart Source:** `semantics.dart:40`
  private static let _kDidGainAccessibilityFocusIndex: Int = 1 << 15
  /// **Dart Source:** `semantics.dart:41`
  private static let _kDidLoseAccessibilityFocusIndex: Int = 1 << 16
  /// **Dart Source:** `semantics.dart:42`
  private static let _kCustomActionIndex: Int = 1 << 17
  /// **Dart Source:** `semantics.dart:43`
  private static let _kDismissIndex: Int = 1 << 18
  /// **Dart Source:** `semantics.dart:44`
  private static let _kMoveCursorForwardByWordIndex: Int = 1 << 19
  /// **Dart Source:** `semantics.dart:45`
  private static let _kMoveCursorBackwardByWordIndex: Int = 1 << 20
  /// **Dart Source:** `semantics.dart:46`
  private static let _kSetTextIndex: Int = 1 << 21
  /// **Dart Source:** `semantics.dart:47`
  private static let _kFocusIndex: Int = 1 << 22
  /// **Dart Source:** `semantics.dart:48`
  private static let _kScrollToOffsetIndex: Int = 1 << 23
  /// **Dart Source:** `semantics.dart:49`
  private static let _kExpandIndex: Int = 1 << 24
  /// **Dart Source:** `semantics.dart:50`
  private static let _kCollapseIndex: Int = 1 << 25

  // MARK: - Public action constants

  /// The equivalent of a user briefly tapping the screen with the finger
  /// without moving it.
  ///
  /// **Dart Source:** `semantics.dart:60`
  public static let tap = SemanticsAction(index: _kTapIndex, name: "tap")

  /// The equivalent of a user pressing and holding the screen with the finger
  /// for a few seconds without moving it.
  ///
  /// **Dart Source:** `semantics.dart:64`
  public static let longPress = SemanticsAction(index: _kLongPressIndex, name: "longPress")

  /// The equivalent of a user moving their finger across the screen from right
  /// to left.
  ///
  /// **Dart Source:** `semantics.dart:71`
  public static let scrollLeft = SemanticsAction(index: _kScrollLeftIndex, name: "scrollLeft")

  /// The equivalent of a user moving their finger across the screen from left
  /// to right.
  ///
  /// **Dart Source:** `semantics.dart:78`
  public static let scrollRight = SemanticsAction(index: _kScrollRightIndex, name: "scrollRight")

  /// The equivalent of a user moving their finger across the screen from
  /// bottom to top.
  ///
  /// **Dart Source:** `semantics.dart:85`
  public static let scrollUp = SemanticsAction(index: _kScrollUpIndex, name: "scrollUp")

  /// The equivalent of a user moving their finger across the screen from top
  /// to bottom.
  ///
  /// **Dart Source:** `semantics.dart:92`
  public static let scrollDown = SemanticsAction(index: _kScrollDownIndex, name: "scrollDown")

  /// A request to scroll the scrollable container to a given scroll offset.
  ///
  /// **Dart Source:** `semantics.dart:103-106`
  public static let scrollToOffset = SemanticsAction(
    index: _kScrollToOffsetIndex, name: "scrollToOffset")

  /// A request to increase the value represented by the semantics node.
  ///
  /// **Dart Source:** `semantics.dart:111`
  public static let increase = SemanticsAction(index: _kIncreaseIndex, name: "increase")

  /// A request to decrease the value represented by the semantics node.
  ///
  /// **Dart Source:** `semantics.dart:116`
  public static let decrease = SemanticsAction(index: _kDecreaseIndex, name: "decrease")

  /// A request to fully show the semantics node on screen.
  ///
  /// **Dart Source:** `semantics.dart:122-125`
  public static let showOnScreen = SemanticsAction(
    index: _kShowOnScreenIndex, name: "showOnScreen")

  /// Move the cursor forward by one character.
  ///
  /// **Dart Source:** `semantics.dart:133-136`
  public static let moveCursorForwardByCharacter = SemanticsAction(
    index: _kMoveCursorForwardByCharacterIndex, name: "moveCursorForwardByCharacter")

  /// Move the cursor backward by one character.
  ///
  /// **Dart Source:** `semantics.dart:144-147`
  public static let moveCursorBackwardByCharacter = SemanticsAction(
    index: _kMoveCursorBackwardByCharacterIndex, name: "moveCursorBackwardByCharacter")

  /// Replaces the current text in the text field.
  ///
  /// **Dart Source:** `semantics.dart:155`
  public static let setText = SemanticsAction(index: _kSetTextIndex, name: "setText")

  /// Set the text selection to the given range.
  ///
  /// **Dart Source:** `semantics.dart:166-169`
  public static let setSelection = SemanticsAction(
    index: _kSetSelectionIndex, name: "setSelection")

  /// Copy the current selection to the clipboard.
  ///
  /// **Dart Source:** `semantics.dart:172`
  public static let copy = SemanticsAction(index: _kCopyIndex, name: "copy")

  /// Cut the current selection and place it in the clipboard.
  ///
  /// **Dart Source:** `semantics.dart:175`
  public static let cut = SemanticsAction(index: _kCutIndex, name: "cut")

  /// Paste the current content of the clipboard.
  ///
  /// **Dart Source:** `semantics.dart:178`
  public static let paste = SemanticsAction(index: _kPasteIndex, name: "paste")

  /// Indicates that the node has gained accessibility focus.
  ///
  /// **Dart Source:** `semantics.dart:195-198`
  public static let didGainAccessibilityFocus = SemanticsAction(
    index: _kDidGainAccessibilityFocusIndex, name: "didGainAccessibilityFocus")

  /// Indicates that the node has lost accessibility focus.
  ///
  /// **Dart Source:** `semantics.dart:211-214`
  public static let didLoseAccessibilityFocus = SemanticsAction(
    index: _kDidLoseAccessibilityFocusIndex, name: "didLoseAccessibilityFocus")

  /// Indicates that the user has invoked a custom accessibility action.
  ///
  /// **Dart Source:** `semantics.dart:220-223`
  public static let customAction = SemanticsAction(
    index: _kCustomActionIndex, name: "customAction")

  /// A request that the node should be dismissed.
  ///
  /// **Dart Source:** `semantics.dart:232`
  public static let dismiss = SemanticsAction(index: _kDismissIndex, name: "dismiss")

  /// Move the cursor forward by one word.
  ///
  /// **Dart Source:** `semantics.dart:240-243`
  public static let moveCursorForwardByWord = SemanticsAction(
    index: _kMoveCursorForwardByWordIndex, name: "moveCursorForwardByWord")

  /// Move the cursor backward by one word.
  ///
  /// **Dart Source:** `semantics.dart:251-254`
  public static let moveCursorBackwardByWord = SemanticsAction(
    index: _kMoveCursorBackwardByWordIndex, name: "moveCursorBackwardByWord")

  /// Move the input focus to the respective widget.
  ///
  /// **Dart Source:** `semantics.dart:301`
  public static let focus = SemanticsAction(index: _kFocusIndex, name: "focus")

  /// A request that the node should be expanded.
  ///
  /// **Dart Source:** `semantics.dart:306`
  public static let expand = SemanticsAction(index: _kExpandIndex, name: "expand")

  /// A request that the node should be collapsed.
  ///
  /// **Dart Source:** `semantics.dart:311`
  public static let collapse = SemanticsAction(index: _kCollapseIndex, name: "collapse")

  // MARK: - Action lookup

  /// The possible semantics actions.
  ///
  /// The map's key is the `index` of the action and the value is the action
  /// itself.
  ///
  /// **Dart Source:** `semantics.dart:317-344`
  private static let _kActionById: [Int: SemanticsAction] = [
    _kTapIndex: tap,
    _kLongPressIndex: longPress,
    _kScrollLeftIndex: scrollLeft,
    _kScrollRightIndex: scrollRight,
    _kScrollUpIndex: scrollUp,
    _kScrollDownIndex: scrollDown,
    _kScrollToOffsetIndex: scrollToOffset,
    _kIncreaseIndex: increase,
    _kDecreaseIndex: decrease,
    _kShowOnScreenIndex: showOnScreen,
    _kMoveCursorForwardByCharacterIndex: moveCursorForwardByCharacter,
    _kMoveCursorBackwardByCharacterIndex: moveCursorBackwardByCharacter,
    _kSetSelectionIndex: setSelection,
    _kCopyIndex: copy,
    _kCutIndex: cut,
    _kPasteIndex: paste,
    _kDidGainAccessibilityFocusIndex: didGainAccessibilityFocus,
    _kDidLoseAccessibilityFocusIndex: didLoseAccessibilityFocus,
    _kCustomActionIndex: customAction,
    _kDismissIndex: dismiss,
    _kMoveCursorForwardByWordIndex: moveCursorForwardByWord,
    _kMoveCursorBackwardByWordIndex: moveCursorBackwardByWord,
    _kSetTextIndex: setText,
    _kFocusIndex: focus,
    _kExpandIndex: expand,
    _kCollapseIndex: collapse,
  ]

  /// The list of all semantics actions.
  ///
  /// **Dart Source:** `semantics.dart:348`
  /// **Original:** `static List<SemanticsAction> get values => _kActionById.values.toList(growable: false);`
  public static var values: [SemanticsAction] {
    Array(_kActionById.values)
  }

  /// Returns the `SemanticsAction` for the given `index`, or `nil` if not found.
  ///
  /// **Dart Source:** `semantics.dart:352`
  /// **Original:** `static SemanticsAction? fromIndex(int index) => _kActionById[index];`
  public static func fromIndex(_ index: Int) -> SemanticsAction? {
    _kActionById[index]
  }

  // MARK: - CustomStringConvertible

  /// **Dart Source:** `semantics.dart:354-355`
  /// **Original:** `String toString() => 'SemanticsAction.$name';`
  public var description: String {
    "SemanticsAction.\(name)"
  }
}

// MARK: - SemanticsRole

/// An enum to describe the role for a semantics node.
///
/// The roles are translated into native accessibility roles in each platform.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/semantics.dart`
/// **Original Name:** `SemanticsRole`
/// **Lines:** 358-556
public enum SemanticsRole: Sendable {
  /// Does not represent any role.
  ///
  /// **Dart Source:** `semantics.dart:363`
  case none

  /// A tab button.
  ///
  /// **Dart Source:** `semantics.dart:370`
  case tab

  /// Contains tab buttons.
  ///
  /// **Dart Source:** `semantics.dart:377`
  case tabBar

  /// The main display for a tab.
  ///
  /// **Dart Source:** `semantics.dart:380`
  case tabPanel

  /// A pop up dialog.
  ///
  /// **Dart Source:** `semantics.dart:383`
  case dialog

  /// An alert dialog.
  ///
  /// **Dart Source:** `semantics.dart:386`
  case alertDialog

  /// A table structure containing data arranged in rows and columns.
  ///
  /// **Dart Source:** `semantics.dart:393`
  case table

  /// A cell in a table that does not contain column or row header information.
  ///
  /// **Dart Source:** `semantics.dart:400`
  case cell

  /// A row of cells or column headers in a table.
  ///
  /// **Dart Source:** `semantics.dart:407`
  case row

  /// A cell in a table that contains header information for a column.
  ///
  /// **Dart Source:** `semantics.dart:414`
  case columnHeader

  /// A control used for dragging across content.
  ///
  /// **Dart Source:** `semantics.dart:419`
  case dragHandle

  /// A control to cycle through content on tap.
  ///
  /// **Dart Source:** `semantics.dart:424`
  case spinButton

  /// A input field with a dropdown list box attached.
  ///
  /// **Dart Source:** `semantics.dart:429`
  case comboBox

  /// A presentation of menu that usually remains visible and is usually
  /// presented horizontally.
  ///
  /// **Dart Source:** `semantics.dart:435`
  case menuBar

  /// A permanently visible list of controls or a widget that can be made to
  /// open and close.
  ///
  /// **Dart Source:** `semantics.dart:441`
  case menu

  /// An item in a dropdown created by menu or menuBar.
  ///
  /// **Dart Source:** `semantics.dart:451`
  case menuItem

  /// An item with a checkbox in a dropdown created by menu or menuBar.
  ///
  /// **Dart Source:** `semantics.dart:458`
  case menuItemCheckbox

  /// An item with a radio button in a dropdown created by menu or menuBar.
  ///
  /// **Dart Source:** `semantics.dart:465`
  case menuItemRadio

  /// A container to display multiple listItems in vertical or horizontal
  /// layout.
  ///
  /// **Dart Source:** `semantics.dart:471`
  case list

  /// An item in a list.
  ///
  /// **Dart Source:** `semantics.dart:474`
  case listItem

  /// An area that represents a form.
  ///
  /// **Dart Source:** `semantics.dart:477`
  case form

  /// A pop up displayed when hovering over a component to provide contextual
  /// explanation.
  ///
  /// **Dart Source:** `semantics.dart:481`
  case tooltip

  /// A graphic object that spins to indicate the application is busy.
  ///
  /// **Dart Source:** `semantics.dart:486`
  case loadingSpinner

  /// A graphic object that shows progress with a numeric number.
  ///
  /// **Dart Source:** `semantics.dart:491`
  case progressBar

  /// A keyboard shortcut field that allows the user to enter a combination or
  /// sequence of keystrokes.
  ///
  /// **Dart Source:** `semantics.dart:497`
  case hotKey

  /// A group of radio buttons.
  ///
  /// **Dart Source:** `semantics.dart:500`
  case radioGroup

  /// A component to provide advisory information that is not important to
  /// justify an alert.
  ///
  /// **Dart Source:** `semantics.dart:506`
  case status

  /// A component to provide important and usually time-sensitive information.
  ///
  /// **Dart Source:** `semantics.dart:517`
  case alert

  /// A supporting section that relates to the main content.
  ///
  /// **Dart Source:** `semantics.dart:525`
  case complementary

  /// A section for a footer, containing identifying information such as
  /// copyright information, navigation links and privacy statements.
  ///
  /// **Dart Source:** `semantics.dart:532`
  case contentInfo

  /// The primary content of a document.
  ///
  /// **Dart Source:** `semantics.dart:541`
  case main

  /// A region of a web page that contains navigation links.
  ///
  /// **Dart Source:** `semantics.dart:547`
  case navigation

  /// A section of content sufficiently important but cannot be described by one
  /// of the other landmark roles.
  ///
  /// **Dart Source:** `semantics.dart:555`
  case region
}

// MARK: - SemanticsInputType

/// Describe the type of data for an input field.
///
/// This is typically used to complement text fields.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/semantics.dart`
/// **Original Name:** `SemanticsInputType`
/// **Lines:** 558-579
public enum SemanticsInputType: Sendable {
  /// The default for non text field.
  ///
  /// **Dart Source:** `semantics.dart:563`
  case none

  /// Describes a generic text field.
  ///
  /// **Dart Source:** `semantics.dart:566`
  case text

  /// Describes a url text field.
  ///
  /// **Dart Source:** `semantics.dart:569`
  case url

  /// Describes a text field for phone input.
  ///
  /// **Dart Source:** `semantics.dart:572`
  case phone

  /// Describes a text field that act as a search box.
  ///
  /// **Dart Source:** `semantics.dart:575`
  case search

  /// Describes a text field for email input.
  ///
  /// **Dart Source:** `semantics.dart:578`
  case email
}

// MARK: - CheckedState

/// Checked state of a semantics node.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/semantics.dart`
/// **Original Name:** `CheckedState`
/// **Lines:** 1077-1113
///
/// DIFFERENCE FROM DART: Using `Int` raw value type instead of Dart's
/// enhanced enum with `value` field.
/// REASON: Swift enums with raw values are the idiomatic equivalent
/// of Dart enhanced enums with a single value field.
public enum CheckedState: Int, Sendable {
  /// The semantics node does not have a check state.
  ///
  /// **Dart Source:** `semantics.dart:1080`
  case none = 0

  /// The semantics node is checked.
  ///
  /// **Dart Source:** `semantics.dart:1083`
  case isTrue = 1

  /// The semantics node is not checked.
  ///
  /// **Dart Source:** `semantics.dart:1086`
  case isFalse = 2

  /// The semantics node represents a tristate checkbox in a mixed state.
  ///
  /// **Dart Source:** `semantics.dart:1089`
  case mixed = 3

  /// If two semantics nodes both have check state, they have conflict
  /// and can't be merged.
  ///
  /// **Dart Source:** `semantics.dart:1098`
  /// **Original:** `bool hasConflict(CheckedState other) => this != CheckedState.none && other != CheckedState.none;`
  public func hasConflict(_ other: CheckedState) -> Bool {
    self != .none && other != .none
  }

  /// Semantics nodes will only be merged when they are not in conflict.
  ///
  /// **Dart Source:** `semantics.dart:1101-1112`
  /// **Original:** `CheckedState merge(CheckedState other) { ... }`
  public func merge(_ other: CheckedState) -> CheckedState {
    if self == .mixed || other == .mixed {
      return .mixed
    }
    if self == .isTrue || other == .isTrue {
      return .isTrue
    }
    if self == .isFalse || other == .isFalse {
      return .isFalse
    }
    return .none
  }
}

// MARK: - Tristate

/// Tristate flags for a semantics node.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/semantics.dart`
/// **Original Name:** `Tristate`
/// **Lines:** 1115-1157
///
/// DIFFERENCE FROM DART: Using `Int` raw value type instead of Dart's
/// enhanced enum with `value` field.
/// REASON: Swift enums with raw values are the idiomatic equivalent
/// of Dart enhanced enums with a single value field.
public enum Tristate: Int, Sendable {
  /// The property is not applicable to this semantics node.
  ///
  /// **Dart Source:** `semantics.dart:1118`
  case none = 0

  /// The property is applicable and its state is "true" or "on".
  ///
  /// **Dart Source:** `semantics.dart:1121`
  case isTrue = 1

  /// The property is applicable and its state is "false" or "off".
  ///
  /// **Dart Source:** `semantics.dart:1124`
  case isFalse = 2

  /// If two semantics nodes both have this property, they have conflict
  /// and can't be merged.
  ///
  /// **Dart Source:** `semantics.dart:1133`
  /// **Original:** `bool hasConflict(Tristate other) => this != Tristate.none && other != Tristate.none;`
  public func hasConflict(_ other: Tristate) -> Bool {
    self != .none && other != .none
  }

  /// Semantics nodes will only be merged when they are not in conflict.
  ///
  /// **Dart Source:** `semantics.dart:1136-1144`
  /// **Original:** `Tristate merge(Tristate other) { ... }`
  public func merge(_ other: Tristate) -> Tristate {
    if self == .isTrue || other == .isTrue {
      return .isTrue
    }
    if self == .isFalse || other == .isFalse {
      return .isFalse
    }
    return .none
  }

  /// Convert a Tristate flag to bool or null.
  ///
  /// **Dart Source:** `semantics.dart:1147-1156`
  /// **Original:** `bool? toBoolOrNull() { ... }`
  public func toBoolOrNull() -> Bool? {
    switch self {
    case .none:
      return nil
    case .isTrue:
      return true
    case .isFalse:
      return false
    }
  }
}

// MARK: - SemanticsFlag

/// A Boolean value that can be associated with a semantics node.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/semantics.dart`
/// **Original Name:** `SemanticsFlag`
/// **Lines:** 581-1075
///
/// DIFFERENCE FROM DART: Using struct instead of class with const constructor.
/// REASON: Swift structs with static let properties are the idiomatic equivalent
/// of Dart classes with static const fields for value-type semantics.
public struct SemanticsFlag: Hashable, Sendable, CustomStringConvertible {
  /// The numerical value for this flag.
  ///
  /// Each flag has one bit set in this bit field.
  ///
  /// **Dart Source:** `semantics.dart:594`
  public let index: Int

  /// A human-readable name for this flag, used for debugging purposes.
  ///
  /// **Dart Source:** `semantics.dart:597`
  public let name: String

  /// **Dart Source:** `semantics.dart:589`
  /// **Original:** `const SemanticsFlag._(this.index, this.name);`
  private init(index: Int, name: String) {
    self.index = index
    self.name = name
  }

  // MARK: - Private index constants

  /// **Dart Source:** `semantics.dart:599`
  private static let _kHasCheckedStateIndex: Int = 1 << 0
  /// **Dart Source:** `semantics.dart:600`
  private static let _kIsCheckedIndex: Int = 1 << 1
  /// **Dart Source:** `semantics.dart:601`
  private static let _kIsSelectedIndex: Int = 1 << 2
  /// **Dart Source:** `semantics.dart:602`
  private static let _kIsButtonIndex: Int = 1 << 3
  /// **Dart Source:** `semantics.dart:603`
  private static let _kIsTextFieldIndex: Int = 1 << 4
  /// **Dart Source:** `semantics.dart:604`
  private static let _kIsFocusedIndex: Int = 1 << 5
  /// **Dart Source:** `semantics.dart:605`
  private static let _kHasEnabledStateIndex: Int = 1 << 6
  /// **Dart Source:** `semantics.dart:606`
  private static let _kIsEnabledIndex: Int = 1 << 7
  /// **Dart Source:** `semantics.dart:607`
  private static let _kIsInMutuallyExclusiveGroupIndex: Int = 1 << 8
  /// **Dart Source:** `semantics.dart:608`
  private static let _kIsHeaderIndex: Int = 1 << 9
  /// **Dart Source:** `semantics.dart:609`
  private static let _kIsObscuredIndex: Int = 1 << 10
  /// **Dart Source:** `semantics.dart:610`
  private static let _kScopesRouteIndex: Int = 1 << 11
  /// **Dart Source:** `semantics.dart:611`
  private static let _kNamesRouteIndex: Int = 1 << 12
  /// **Dart Source:** `semantics.dart:612`
  private static let _kIsHiddenIndex: Int = 1 << 13
  /// **Dart Source:** `semantics.dart:613`
  private static let _kIsImageIndex: Int = 1 << 14
  /// **Dart Source:** `semantics.dart:614`
  private static let _kIsLiveRegionIndex: Int = 1 << 15
  /// **Dart Source:** `semantics.dart:615`
  private static let _kHasToggledStateIndex: Int = 1 << 16
  /// **Dart Source:** `semantics.dart:616`
  private static let _kIsToggledIndex: Int = 1 << 17
  /// **Dart Source:** `semantics.dart:617`
  private static let _kHasImplicitScrollingIndex: Int = 1 << 18
  /// **Dart Source:** `semantics.dart:618`
  private static let _kIsMultilineIndex: Int = 1 << 19
  /// **Dart Source:** `semantics.dart:619`
  private static let _kIsReadOnlyIndex: Int = 1 << 20
  /// **Dart Source:** `semantics.dart:620`
  private static let _kIsFocusableIndex: Int = 1 << 21
  /// **Dart Source:** `semantics.dart:621`
  private static let _kIsLinkIndex: Int = 1 << 22
  /// **Dart Source:** `semantics.dart:622`
  private static let _kIsSliderIndex: Int = 1 << 23
  /// **Dart Source:** `semantics.dart:623`
  private static let _kIsKeyboardKeyIndex: Int = 1 << 24
  /// **Dart Source:** `semantics.dart:624`
  private static let _kIsCheckStateMixedIndex: Int = 1 << 25
  /// **Dart Source:** `semantics.dart:625`
  private static let _kHasExpandedStateIndex: Int = 1 << 26
  /// **Dart Source:** `semantics.dart:626`
  private static let _kIsExpandedIndex: Int = 1 << 27
  /// **Dart Source:** `semantics.dart:627`
  private static let _kHasSelectedStateIndex: Int = 1 << 28
  /// **Dart Source:** `semantics.dart:628`
  private static let _kHasRequiredStateIndex: Int = 1 << 29
  /// **Dart Source:** `semantics.dart:629`
  private static let _kIsRequiredIndex: Int = 1 << 30

  // MARK: - Public flag constants

  /// The semantics node has the quality of either being "checked" or "unchecked".
  ///
  /// **Dart Source:** `semantics.dart:663-666`
  public static let hasCheckedState = SemanticsFlag(
    index: _kHasCheckedStateIndex, name: "hasCheckedState")

  /// Whether a semantics node that `hasCheckedState` is checked.
  ///
  /// **Dart Source:** `semantics.dart:681`
  public static let isChecked = SemanticsFlag(
    index: _kIsCheckedIndex, name: "isChecked")

  /// Whether a tristate checkbox is in its mixed state.
  ///
  /// **Dart Source:** `semantics.dart:694-697`
  public static let isCheckStateMixed = SemanticsFlag(
    index: _kIsCheckStateMixedIndex, name: "isCheckStateMixed")

  /// The semantics node has the quality of either being "selected" or "unselected".
  ///
  /// **Dart Source:** `semantics.dart:709-712`
  public static let hasSelectedState = SemanticsFlag(
    index: _kHasSelectedStateIndex, name: "hasSelectedState")

  /// Whether a semantics node is selected.
  ///
  /// **Dart Source:** `semantics.dart:724`
  public static let isSelected = SemanticsFlag(
    index: _kIsSelectedIndex, name: "isSelected")

  /// Whether the semantic node represents a button.
  ///
  /// **Dart Source:** `semantics.dart:733`
  public static let isButton = SemanticsFlag(
    index: _kIsButtonIndex, name: "isButton")

  /// Whether the semantic node represents a text field.
  ///
  /// **Dart Source:** `semantics.dart:741`
  public static let isTextField = SemanticsFlag(
    index: _kIsTextFieldIndex, name: "isTextField")

  /// Whether the semantic node represents a slider.
  ///
  /// **Dart Source:** `semantics.dart:746`
  public static let isSlider = SemanticsFlag(
    index: _kIsSliderIndex, name: "isSlider")

  /// Whether the semantic node represents a keyboard key.
  ///
  /// **Dart Source:** `semantics.dart:751`
  public static let isKeyboardKey = SemanticsFlag(
    index: _kIsKeyboardKeyIndex, name: "isKeyboardKey")

  /// Whether the semantic node is read only.
  ///
  /// **Dart Source:** `semantics.dart:758`
  public static let isReadOnly = SemanticsFlag(
    index: _kIsReadOnlyIndex, name: "isReadOnly")

  /// Whether the semantic node is an interactive link.
  ///
  /// **Dart Source:** `semantics.dart:767`
  public static let isLink = SemanticsFlag(
    index: _kIsLinkIndex, name: "isLink")

  /// Whether the semantic node is able to hold the user's focus.
  ///
  /// **Dart Source:** `semantics.dart:774`
  public static let isFocusable = SemanticsFlag(
    index: _kIsFocusableIndex, name: "isFocusable")

  /// Whether the semantic node currently holds the user's focus.
  ///
  /// **Dart Source:** `semantics.dart:781`
  public static let isFocused = SemanticsFlag(
    index: _kIsFocusedIndex, name: "isFocused")

  /// The semantics node has the quality of either being "enabled" or "disabled".
  ///
  /// **Dart Source:** `semantics.dart:791-794`
  public static let hasEnabledState = SemanticsFlag(
    index: _kHasEnabledStateIndex, name: "hasEnabledState")

  /// Whether a semantic node that `hasEnabledState` is currently enabled.
  ///
  /// **Dart Source:** `semantics.dart:803`
  public static let isEnabled = SemanticsFlag(
    index: _kIsEnabledIndex, name: "isEnabled")

  /// Whether a semantic node is in a mutually exclusive group.
  ///
  /// **Dart Source:** `semantics.dart:811-814`
  public static let isInMutuallyExclusiveGroup = SemanticsFlag(
    index: _kIsInMutuallyExclusiveGroupIndex, name: "isInMutuallyExclusiveGroup")

  /// Whether a semantic node is a header that divides content into sections.
  ///
  /// **Dart Source:** `semantics.dart:823`
  public static let isHeader = SemanticsFlag(
    index: _kIsHeaderIndex, name: "isHeader")

  /// Whether the value of the semantics node is obscured.
  ///
  /// **Dart Source:** `semantics.dart:831`
  public static let isObscured = SemanticsFlag(
    index: _kIsObscuredIndex, name: "isObscured")

  /// Whether the value of the semantics node is coming from a multi-line text field.
  ///
  /// **Dart Source:** `semantics.dart:840`
  public static let isMultiline = SemanticsFlag(
    index: _kIsMultilineIndex, name: "isMultiline")

  /// Whether the semantics node is the root of a subtree for which a route name
  /// should be announced.
  ///
  /// **Dart Source:** `semantics.dart:867`
  public static let scopesRoute = SemanticsFlag(
    index: _kScopesRouteIndex, name: "scopesRoute")

  /// Whether the semantics node label is the name of a visually distinct route.
  ///
  /// **Dart Source:** `semantics.dart:882`
  public static let namesRoute = SemanticsFlag(
    index: _kNamesRouteIndex, name: "namesRoute")

  /// Whether the semantics node is considered hidden.
  ///
  /// **Dart Source:** `semantics.dart:906`
  public static let isHidden = SemanticsFlag(
    index: _kIsHiddenIndex, name: "isHidden")

  /// Whether the semantics node represents an image.
  ///
  /// **Dart Source:** `semantics.dart:914`
  public static let isImage = SemanticsFlag(
    index: _kIsImageIndex, name: "isImage")

  /// Whether the semantics node is a live region.
  ///
  /// **Dart Source:** `semantics.dart:930`
  public static let isLiveRegion = SemanticsFlag(
    index: _kIsLiveRegionIndex, name: "isLiveRegion")

  /// The semantics node has the quality of either being "on" or "off".
  ///
  /// **Dart Source:** `semantics.dart:943-946`
  public static let hasToggledState = SemanticsFlag(
    index: _kHasToggledStateIndex, name: "hasToggledState")

  /// If true, the semantics node is "on". If false, the semantics node is "off".
  ///
  /// **Dart Source:** `semantics.dart:958`
  public static let isToggled = SemanticsFlag(
    index: _kIsToggledIndex, name: "isToggled")

  /// Whether the platform can scroll the semantics node when the user attempts
  /// to move focus to an offscreen child.
  ///
  /// **Dart Source:** `semantics.dart:969-972`
  public static let hasImplicitScrolling = SemanticsFlag(
    index: _kHasImplicitScrollingIndex, name: "hasImplicitScrolling")

  /// The semantics node has the quality of either being "expanded" or "collapsed".
  ///
  /// **Dart Source:** `semantics.dart:983-986`
  public static let hasExpandedState = SemanticsFlag(
    index: _kHasExpandedStateIndex, name: "hasExpandedState")

  /// Whether a semantics node is expanded.
  ///
  /// **Dart Source:** `semantics.dart:1000`
  public static let isExpanded = SemanticsFlag(
    index: _kIsExpandedIndex, name: "isExpanded")

  /// The semantics node has the quality of either being required or not.
  ///
  /// **Dart Source:** `semantics.dart:1009-1012`
  public static let hasRequiredState = SemanticsFlag(
    index: _kHasRequiredStateIndex, name: "hasRequiredState")

  /// Whether a semantics node is required.
  ///
  /// **Dart Source:** `semantics.dart:1026`
  public static let isRequired = SemanticsFlag(
    index: _kIsRequiredIndex, name: "isRequired")

  // MARK: - Flag lookup

  /// The possible semantics flags.
  ///
  /// The map's key is the `index` of the flag and the value is the flag itself.
  ///
  /// **Dart Source:** `semantics.dart:1031-1063`
  private static let _kFlagById: [Int: SemanticsFlag] = [
    _kHasCheckedStateIndex: hasCheckedState,
    _kIsCheckedIndex: isChecked,
    _kHasSelectedStateIndex: hasSelectedState,
    _kIsSelectedIndex: isSelected,
    _kIsButtonIndex: isButton,
    _kIsTextFieldIndex: isTextField,
    _kIsFocusedIndex: isFocused,
    _kHasEnabledStateIndex: hasEnabledState,
    _kIsEnabledIndex: isEnabled,
    _kIsInMutuallyExclusiveGroupIndex: isInMutuallyExclusiveGroup,
    _kIsHeaderIndex: isHeader,
    _kIsObscuredIndex: isObscured,
    _kScopesRouteIndex: scopesRoute,
    _kNamesRouteIndex: namesRoute,
    _kIsHiddenIndex: isHidden,
    _kIsImageIndex: isImage,
    _kIsLiveRegionIndex: isLiveRegion,
    _kHasToggledStateIndex: hasToggledState,
    _kIsToggledIndex: isToggled,
    _kHasImplicitScrollingIndex: hasImplicitScrolling,
    _kIsMultilineIndex: isMultiline,
    _kIsReadOnlyIndex: isReadOnly,
    _kIsFocusableIndex: isFocusable,
    _kIsLinkIndex: isLink,
    _kIsSliderIndex: isSlider,
    _kIsKeyboardKeyIndex: isKeyboardKey,
    _kIsCheckStateMixedIndex: isCheckStateMixed,
    _kHasExpandedStateIndex: hasExpandedState,
    _kIsExpandedIndex: isExpanded,
    _kHasRequiredStateIndex: hasRequiredState,
    _kIsRequiredIndex: isRequired,
  ]

  /// The list of all semantics flags.
  ///
  /// **Dart Source:** `semantics.dart:1067`
  /// **Original:** `static List<SemanticsFlag> get values => _kFlagById.values.toList(growable: false);`
  public static var values: [SemanticsFlag] {
    Array(_kFlagById.values)
  }

  /// Returns the `SemanticsFlag` for the given `index`, or `nil` if not found.
  ///
  /// **Dart Source:** `semantics.dart:1071`
  /// **Original:** `static SemanticsFlag? fromIndex(int index) => _kFlagById[index];`
  public static func fromIndex(_ index: Int) -> SemanticsFlag? {
    _kFlagById[index]
  }

  // MARK: - CustomStringConvertible

  /// **Dart Source:** `semantics.dart:1073-1074`
  /// **Original:** `String toString() => 'SemanticsFlag.$name';`
  public var description: String {
    "SemanticsFlag.\(name)"
  }
}

// MARK: - SemanticsValidationResult

/// The validation result of a form field.
///
/// The type, shape, and correctness of the value is specific to the kind of
/// form field used. For example, a phone number text field may check that the
/// value is a properly formatted phone number, and/or that the phone number has
/// the right area code. A group of radio buttons may validate that the user
/// selected at least one radio option.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/semantics.dart`
/// **Original Name:** `SemanticsValidationResult`
/// **Lines:** 1552-1574
public enum SemanticsValidationResult: Sendable {
  /// The node has no validation information attached to it.
  ///
  /// This is the default value. Most semantics nodes do not contain validation
  /// information. Typically, only nodes that are part of an input form - text
  /// fields, checkboxes, radio buttons, dropdowns - are validated and attach
  /// validation results to their corresponding semantics nodes.
  ///
  /// **Dart Source:** `semantics.dart:1566`
  case none

  /// The entered value is valid, and no error should be displayed to the user.
  ///
  /// **Dart Source:** `semantics.dart:1569`
  case valid

  /// The entered value is invalid, and an error message should be communicated
  /// to the user.
  ///
  /// **Dart Source:** `semantics.dart:1573`
  case invalid
}

// MARK: - SemanticsFlags

/// Represents a collection of boolean flags that convey semantic information
/// about a widget's accessibility state and properties.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/semantics.dart`
/// **Original Name:** `SemanticsFlags`
/// **Lines:** 1159-1550
///
/// DIFFERENCE FROM DART: Using a Swift class with a C++ bridge instead of
/// extending NativeFieldWrapperClass1.
/// REASON: Swift uses SWIFT_SHARED_REFERENCE for C++ interop instead of
/// Dart's NativeFieldWrapperClass1 pattern.
public class SemanticsFlags: Equatable, Hashable {
  /// The C++ bridge object - Swift ARC handles lifetime via SWIFT_SHARED_REFERENCE
  internal let bridge: flutter.swift_bridge.SemanticsFlagsBridge

  // MARK: - Tristate/Checked fields

  /// **Dart Source:** `semantics.dart:1279`
  public let isChecked: CheckedState

  /// **Dart Source:** `semantics.dart:1282`
  public let isSelected: Tristate

  /// **Dart Source:** `semantics.dart:1285`
  public let isEnabled: Tristate

  /// **Dart Source:** `semantics.dart:1288`
  public let isToggled: Tristate

  /// **Dart Source:** `semantics.dart:1291`
  public let isExpanded: Tristate

  /// **Dart Source:** `semantics.dart:1294`
  public let isRequired: Tristate

  /// **Dart Source:** `semantics.dart:1297`
  public let isFocused: Tristate

  // MARK: - Boolean fields

  /// **Dart Source:** `semantics.dart:1300`
  public let isButton: Bool

  /// **Dart Source:** `semantics.dart:1303`
  public let isTextField: Bool

  /// **Dart Source:** `semantics.dart:1306`
  public let isInMutuallyExclusiveGroup: Bool

  /// **Dart Source:** `semantics.dart:1309`
  public let isHeader: Bool

  /// **Dart Source:** `semantics.dart:1312`
  public let isObscured: Bool

  /// **Dart Source:** `semantics.dart:1315`
  public let scopesRoute: Bool

  /// **Dart Source:** `semantics.dart:1318`
  public let namesRoute: Bool

  /// **Dart Source:** `semantics.dart:1321`
  public let isHidden: Bool

  /// **Dart Source:** `semantics.dart:1324`
  public let isImage: Bool

  /// **Dart Source:** `semantics.dart:1327`
  public let isLiveRegion: Bool

  /// **Dart Source:** `semantics.dart:1330`
  public let hasImplicitScrolling: Bool

  /// **Dart Source:** `semantics.dart:1333`
  public let isMultiline: Bool

  /// **Dart Source:** `semantics.dart:1336`
  public let isReadOnly: Bool

  /// **Dart Source:** `semantics.dart:1339`
  public let isLink: Bool

  /// **Dart Source:** `semantics.dart:1342`
  public let isSlider: Bool

  /// **Dart Source:** `semantics.dart:1345`
  public let isKeyboardKey: Bool

  /// Creates a set of semantics flags that describe various states of a widget.
  /// All flags default to their "none"/false values unless specified.
  ///
  /// **Dart Source:** `semantics.dart:1167-1218`
  /// **Original:** `SemanticsFlags({...})`
  public init(
    isChecked: CheckedState = .none,
    isSelected: Tristate = .none,
    isEnabled: Tristate = .none,
    isToggled: Tristate = .none,
    isExpanded: Tristate = .none,
    isRequired: Tristate = .none,
    isFocused: Tristate = .none,
    isButton: Bool = false,
    isTextField: Bool = false,
    isInMutuallyExclusiveGroup: Bool = false,
    isHeader: Bool = false,
    isObscured: Bool = false,
    scopesRoute: Bool = false,
    namesRoute: Bool = false,
    isHidden: Bool = false,
    isImage: Bool = false,
    isLiveRegion: Bool = false,
    hasImplicitScrolling: Bool = false,
    isMultiline: Bool = false,
    isReadOnly: Bool = false,
    isLink: Bool = false,
    isSlider: Bool = false,
    isKeyboardKey: Bool = false
  ) {
    self.isChecked = isChecked
    self.isSelected = isSelected
    self.isEnabled = isEnabled
    self.isToggled = isToggled
    self.isExpanded = isExpanded
    self.isRequired = isRequired
    self.isFocused = isFocused
    self.isButton = isButton
    self.isTextField = isTextField
    self.isInMutuallyExclusiveGroup = isInMutuallyExclusiveGroup
    self.isHeader = isHeader
    self.isObscured = isObscured
    self.scopesRoute = scopesRoute
    self.namesRoute = namesRoute
    self.isHidden = isHidden
    self.isImage = isImage
    self.isLiveRegion = isLiveRegion
    self.hasImplicitScrolling = hasImplicitScrolling
    self.isMultiline = isMultiline
    self.isReadOnly = isReadOnly
    self.isLink = isLink
    self.isSlider = isSlider
    self.isKeyboardKey = isKeyboardKey

    // Call C++ bridge constructor
    // **Dart Source:** `semantics.dart:1192-1217` (_initSemanticsFlags call)
    self.bridge = flutter.swift_bridge.SemanticsFlagsBridge(
      Int32(isChecked.rawValue),
      Int32(isSelected.rawValue),
      Int32(isEnabled.rawValue),
      Int32(isToggled.rawValue),
      Int32(isExpanded.rawValue),
      Int32(isRequired.rawValue),
      Int32(isFocused.rawValue),
      isButton,
      isTextField,
      isInMutuallyExclusiveGroup,
      isHeader,
      isObscured,
      scopesRoute,
      namesRoute,
      isHidden,
      isImage,
      isLiveRegion,
      hasImplicitScrolling,
      isMultiline,
      isReadOnly,
      isLink,
      isSlider,
      isKeyboardKey
    )
  }

  /// The set of semantics flags with every flag set to false.
  ///
  /// **Dart Source:** `semantics.dart:1276`
  /// **Original:** `static SemanticsFlags none = SemanticsFlags();`
  public nonisolated(unsafe) static let none = SemanticsFlags()

  // MARK: - Methods

  /// Combines two sets of flags, such that if a flag is set to true in any
  /// of the two sets, the resulting set contains that flag set to true.
  ///
  /// **Dart Source:** `semantics.dart:1348-1374`
  /// **Original:** `SemanticsFlags merge(SemanticsFlags other) { ... }`
  public func merge(_ other: SemanticsFlags) -> SemanticsFlags {
    return SemanticsFlags(
      isChecked: isChecked.merge(other.isChecked),
      isSelected: isSelected.merge(other.isSelected),
      isEnabled: isEnabled.merge(other.isEnabled),
      isToggled: isToggled.merge(other.isToggled),
      isExpanded: isExpanded.merge(other.isExpanded),
      isRequired: isRequired.merge(other.isRequired),
      isFocused: isFocused.merge(other.isFocused),
      isButton: isButton || other.isButton,
      isTextField: isTextField || other.isTextField,
      isInMutuallyExclusiveGroup: isInMutuallyExclusiveGroup || other.isInMutuallyExclusiveGroup,
      isHeader: isHeader || other.isHeader,
      isObscured: isObscured || other.isObscured,
      scopesRoute: scopesRoute || other.scopesRoute,
      namesRoute: namesRoute || other.namesRoute,
      isHidden: isHidden || other.isHidden,
      isImage: isImage || other.isImage,
      isLiveRegion: isLiveRegion || other.isLiveRegion,
      hasImplicitScrolling: hasImplicitScrolling || other.hasImplicitScrolling,
      isMultiline: isMultiline || other.isMultiline,
      isReadOnly: isReadOnly || other.isReadOnly,
      isLink: isLink || other.isLink,
      isSlider: isSlider || other.isSlider,
      isKeyboardKey: isKeyboardKey || other.isKeyboardKey
    )
  }

  /// Copy the semantics flags, with some of them optionally replaced.
  ///
  /// **Dart Source:** `semantics.dart:1377-1427`
  /// **Original:** `SemanticsFlags copyWith({...}) { ... }`
  public func copyWith(
    isChecked: CheckedState? = nil,
    isSelected: Tristate? = nil,
    isEnabled: Tristate? = nil,
    isToggled: Tristate? = nil,
    isExpanded: Tristate? = nil,
    isRequired: Tristate? = nil,
    isFocused: Tristate? = nil,
    isButton: Bool? = nil,
    isTextField: Bool? = nil,
    isInMutuallyExclusiveGroup: Bool? = nil,
    isHeader: Bool? = nil,
    isObscured: Bool? = nil,
    scopesRoute: Bool? = nil,
    namesRoute: Bool? = nil,
    isHidden: Bool? = nil,
    isImage: Bool? = nil,
    isLiveRegion: Bool? = nil,
    hasImplicitScrolling: Bool? = nil,
    isMultiline: Bool? = nil,
    isReadOnly: Bool? = nil,
    isLink: Bool? = nil,
    isSlider: Bool? = nil,
    isKeyboardKey: Bool? = nil
  ) -> SemanticsFlags {
    return SemanticsFlags(
      isChecked: isChecked ?? self.isChecked,
      isSelected: isSelected ?? self.isSelected,
      isEnabled: isEnabled ?? self.isEnabled,
      isToggled: isToggled ?? self.isToggled,
      isExpanded: isExpanded ?? self.isExpanded,
      isRequired: isRequired ?? self.isRequired,
      isFocused: isFocused ?? self.isFocused,
      isButton: isButton ?? self.isButton,
      isTextField: isTextField ?? self.isTextField,
      isInMutuallyExclusiveGroup: isInMutuallyExclusiveGroup ?? self.isInMutuallyExclusiveGroup,
      isHeader: isHeader ?? self.isHeader,
      isObscured: isObscured ?? self.isObscured,
      scopesRoute: scopesRoute ?? self.scopesRoute,
      namesRoute: namesRoute ?? self.namesRoute,
      isHidden: isHidden ?? self.isHidden,
      isImage: isImage ?? self.isImage,
      isLiveRegion: isLiveRegion ?? self.isLiveRegion,
      hasImplicitScrolling: hasImplicitScrolling ?? self.hasImplicitScrolling,
      isMultiline: isMultiline ?? self.isMultiline,
      isReadOnly: isReadOnly ?? self.isReadOnly,
      isLink: isLink ?? self.isLink,
      isSlider: isSlider ?? self.isSlider,
      isKeyboardKey: isKeyboardKey ?? self.isKeyboardKey
    )
  }

  // MARK: - Equatable

  /// **Dart Source:** `semantics.dart:1429-1456`
  /// **Original:** `bool operator ==(Object other) => ...`
  public static func == (lhs: SemanticsFlags, rhs: SemanticsFlags) -> Bool {
    return lhs.isChecked == rhs.isChecked
      && lhs.isSelected == rhs.isSelected
      && lhs.isEnabled == rhs.isEnabled
      && lhs.isToggled == rhs.isToggled
      && lhs.isExpanded == rhs.isExpanded
      && lhs.isRequired == rhs.isRequired
      && lhs.isFocused == rhs.isFocused
      && lhs.isButton == rhs.isButton
      && lhs.isTextField == rhs.isTextField
      && lhs.isInMutuallyExclusiveGroup == rhs.isInMutuallyExclusiveGroup
      && lhs.isHeader == rhs.isHeader
      && lhs.isObscured == rhs.isObscured
      && lhs.scopesRoute == rhs.scopesRoute
      && lhs.namesRoute == rhs.namesRoute
      && lhs.isHidden == rhs.isHidden
      && lhs.isImage == rhs.isImage
      && lhs.isLiveRegion == rhs.isLiveRegion
      && lhs.hasImplicitScrolling == rhs.hasImplicitScrolling
      && lhs.isMultiline == rhs.isMultiline
      && lhs.isReadOnly == rhs.isReadOnly
      && lhs.isLink == rhs.isLink
      && lhs.isSlider == rhs.isSlider
      && lhs.isKeyboardKey == rhs.isKeyboardKey
  }

  // MARK: - Hashable

  /// **Dart Source:** `semantics.dart:1458-1483`
  /// **Original:** `int get hashCode => Object.hashAll([...])`
  public func hash(into hasher: inout Hasher) {
    hasher.combine(isChecked)
    hasher.combine(isSelected)
    hasher.combine(isEnabled)
    hasher.combine(isToggled)
    hasher.combine(isExpanded)
    hasher.combine(isRequired)
    hasher.combine(isFocused)
    hasher.combine(isButton)
    hasher.combine(isTextField)
    hasher.combine(isInMutuallyExclusiveGroup)
    hasher.combine(isHeader)
    hasher.combine(isObscured)
    hasher.combine(scopesRoute)
    hasher.combine(namesRoute)
    hasher.combine(isHidden)
    hasher.combine(isImage)
    hasher.combine(isLiveRegion)
    hasher.combine(hasImplicitScrolling)
    hasher.combine(isMultiline)
    hasher.combine(isReadOnly)
    hasher.combine(isLink)
    hasher.combine(isSlider)
    hasher.combine(isKeyboardKey)
  }

  /// Convert flags to a list of strings.
  ///
  /// **Dart Source:** `semantics.dart:1486-1520`
  /// **Original:** `List<String> toStrings() { ... }`
  public func toStrings() -> [String] {
    var result: [String] = []
    if isChecked != .none { result.append("hasCheckedState") }
    if isChecked == .isTrue { result.append("isChecked") }
    if isSelected == .isTrue { result.append("isSelected") }
    if isButton { result.append("isButton") }
    if isTextField { result.append("isTextField") }
    if isFocused == .isTrue { result.append("isFocused") }
    if isEnabled != .none { result.append("hasEnabledState") }
    if isEnabled == .isTrue { result.append("isEnabled") }
    if isInMutuallyExclusiveGroup { result.append("isInMutuallyExclusiveGroup") }
    if isHeader { result.append("isHeader") }
    if isObscured { result.append("isObscured") }
    if scopesRoute { result.append("scopesRoute") }
    if namesRoute { result.append("namesRoute") }
    if isHidden { result.append("isHidden") }
    if isImage { result.append("isImage") }
    if isLiveRegion { result.append("isLiveRegion") }
    if isToggled != .none { result.append("hasToggledState") }
    if isToggled == .isTrue { result.append("isToggled") }
    if hasImplicitScrolling { result.append("hasImplicitScrolling") }
    if isMultiline { result.append("isMultiline") }
    if isReadOnly { result.append("isReadOnly") }
    if isFocused != .none { result.append("isFocusable") }
    if isLink { result.append("isLink") }
    if isSlider { result.append("isSlider") }
    if isKeyboardKey { result.append("isKeyboardKey") }
    if isChecked == .mixed { result.append("isCheckStateMixed") }
    if isExpanded != .none { result.append("hasExpandedState") }
    if isExpanded == .isTrue { result.append("isExpanded") }
    if isSelected != .none { result.append("hasSelectedState") }
    if isRequired != .none { result.append("hasRequiredState") }
    if isRequired == .isTrue { result.append("isRequired") }
    return result
  }

  /// Checks if any of the boolean semantic flags are set to true
  /// in both this instance and the other instance.
  ///
  /// **Dart Source:** `semantics.dart:1524-1549`
  /// **Original:** `bool hasRepeatedFlags(SemanticsFlags other) { ... }`
  public func hasRepeatedFlags(_ other: SemanticsFlags) -> Bool {
    return isChecked.hasConflict(other.isChecked)
      || isSelected.hasConflict(other.isSelected)
      || isEnabled.hasConflict(other.isEnabled)
      || isToggled.hasConflict(other.isToggled)
      || isEnabled.hasConflict(other.isEnabled)
      || isExpanded.hasConflict(other.isExpanded)
      || isRequired.hasConflict(other.isRequired)
      || isFocused.hasConflict(other.isFocused)
      || (isButton && other.isButton)
      || (isTextField && other.isTextField)
      || (isInMutuallyExclusiveGroup && other.isInMutuallyExclusiveGroup)
      || (isHeader && other.isHeader)
      || (isObscured && other.isObscured)
      || (scopesRoute && other.scopesRoute)
      || (namesRoute && other.namesRoute)
      || (isHidden && other.isHidden)
      || (isImage && other.isImage)
      || (isLiveRegion && other.isLiveRegion)
      || (hasImplicitScrolling && other.hasImplicitScrolling)
      || (isMultiline && other.isMultiline)
      || (isReadOnly && other.isReadOnly)
      || (isLink && other.isLink)
      || (isSlider && other.isSlider)
      || (isKeyboardKey && other.isKeyboardKey)
  }
}

// MARK: - StringAttribute

/// An abstract interface for string attributes that affects how assistive
/// technologies, e.g. VoiceOver or TalkBack, treat the text.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/semantics.dart`
/// **Original Name:** `StringAttribute`
/// **Lines:** 1584-1608
///
/// DIFFERENCE FROM DART: Using protocol instead of abstract base class.
/// REASON: Swift doesn't have abstract classes; protocol is the idiomatic
/// equivalent for defining an interface that concrete classes must implement.
///
/// See also:
///  * `SpellOutStringAttribute`, which causes the assistive technologies to
///    spell out the string character by character when announcing the string.
///  * `LocaleStringAttribute`, which causes the assistive technologies to
///    treat the string in the specific language.
public protocol StringAttribute: AnyObject {
  /// The range of the text to which this attribute applies.
  ///
  /// **Dart Source:** `semantics.dart:1598`
  /// **Original:** `final TextRange range;`
  var range: TextRange { get }

  /// Creates a new attribute with all properties copied except for range, which
  /// is updated to the specified value.
  ///
  /// For example, the `LocaleStringAttribute` specifies a `Locale` for its
  /// range of characters. Copying it will result in a new
  /// `LocaleStringAttribute` that has the same locale but an updated
  /// `TextRange`.
  ///
  /// **Dart Source:** `semantics.dart:1607`
  /// **Original:** `StringAttribute copy({required TextRange range});`
  func copy(range: TextRange) -> any StringAttribute
}

// MARK: - SpellOutStringAttribute

/// A string attribute that causes the assistive technologies, e.g. VoiceOver,
/// to spell out the string character by character.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/semantics.dart`
/// **Original Name:** `SpellOutStringAttribute`
/// **Lines:** 1610-1643
///
/// DIFFERENCE FROM DART: Using a Swift class conforming to StringAttribute protocol
/// with a C++ bridge instead of extending NativeFieldWrapperClass1.
/// REASON: Swift uses SWIFT_SHARED_REFERENCE for C++ interop instead of
/// Dart's NativeFieldWrapperClass1 pattern.
///
/// See also:
///  * `LocaleStringAttribute`, which causes the assistive technologies to
///    treat the string in the specific language.
public class SpellOutStringAttribute: StringAttribute, CustomStringConvertible {
  /// The C++ bridge object - Swift ARC handles lifetime via SWIFT_SHARED_REFERENCE
  private let bridge: flutter.swift_bridge.SpellOutStringAttributeBridge

  /// The range of the text to which this attribute applies.
  ///
  /// **Dart Source:** `semantics.dart:1598` (inherited from StringAttribute)
  public let range: TextRange

  /// Creates a string attribute that denotes the text in `range` must be
  /// spelled out when the assistive technologies announce the string.
  ///
  /// **Dart Source:** `semantics.dart:1621-1623`
  /// **Original:** `SpellOutStringAttribute({required TextRange range}) : super._(range: range) { _initSpellOutStringAttribute(this, range.start, range.end); }`
  public init(range: TextRange) {
    self.range = range
    // Call C++ bridge constructor
    // **Dart Source:** `semantics.dart:1625-1632` (_initSpellOutStringAttribute)
    // Maps to NativeStringAttribute::initSpellOutStringAttribute in the engine.
    self.bridge = flutter.swift_bridge.SpellOutStringAttributeBridge(
      Int32(range.start),
      Int32(range.end)
    )
  }

  /// Creates a new attribute with all properties copied except for range, which
  /// is updated to the specified value.
  ///
  /// **Dart Source:** `semantics.dart:1634-1637`
  /// **Original:** `StringAttribute copy({required TextRange range}) { return SpellOutStringAttribute(range: range); }`
  public func copy(range: TextRange) -> any StringAttribute {
    return SpellOutStringAttribute(range: range)
  }

  // MARK: - CustomStringConvertible

  /// **Dart Source:** `semantics.dart:1639-1642`
  /// **Original:** `String toString() => 'SpellOutStringAttribute($range)';`
  public var description: String {
    "SpellOutStringAttribute(\(range))"
  }
}

// MARK: - LocaleStringAttribute

/// A string attribute that causes the assistive technologies, e.g. VoiceOver,
/// to treat string as a certain language.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/semantics.dart`
/// **Original Name:** `LocaleStringAttribute`
/// **Lines:** 1645-1683
///
/// DIFFERENCE FROM DART: Using a Swift class conforming to StringAttribute protocol
/// with a C++ bridge instead of extending NativeFieldWrapperClass1.
/// REASON: Swift uses SWIFT_SHARED_REFERENCE for C++ interop instead of
/// Dart's NativeFieldWrapperClass1 pattern.
///
/// See also:
///  * `SpellOutStringAttribute`, which causes the assistive technologies to
///    spell out the string character by character when announcing the string.
public class LocaleStringAttribute: StringAttribute, CustomStringConvertible {
  /// The C++ bridge object - Swift ARC handles lifetime via SWIFT_SHARED_REFERENCE
  private let bridge: flutter.swift_bridge.LocaleStringAttributeBridge

  /// The range of the text to which this attribute applies.
  ///
  /// **Dart Source:** `semantics.dart:1598` (inherited from StringAttribute)
  public let range: TextRange

  /// The language of this attribute.
  ///
  /// **Dart Source:** `semantics.dart:1663`
  /// **Original:** `final Locale locale;`
  public let locale: Locale

  /// Creates a string attribute that denotes the text in `range` must be
  /// treated as the language specified by the `locale` when the assistive
  /// technologies announce the string.
  ///
  /// **Dart Source:** `semantics.dart:1657-1659`
  /// **Original:** `LocaleStringAttribute({required TextRange range, required this.locale}) : super._(range: range) { _initLocaleStringAttribute(this, range.start, range.end, locale.toLanguageTag()); }`
  public init(range: TextRange, locale: Locale) {
    self.range = range
    self.locale = locale
    // **Dart Source:** `semantics.dart:1665-1673` (_initLocaleStringAttribute)
    // Maps to NativeStringAttribute::initLocaleStringAttribute in the engine.
    // C++ bridge now uses const char* to avoid std::string ABI mismatch.
    self.bridge = locale.toLanguageTag().withCString { localePtr in
      flutter.swift_bridge.LocaleStringAttributeBridge(
        Int32(range.start),
        Int32(range.end),
        localePtr
      )
    }
  }

  /// Creates a new attribute with all properties copied except for range, which
  /// is updated to the specified value.
  ///
  /// **Dart Source:** `semantics.dart:1676-1678`
  /// **Original:** `StringAttribute copy({required TextRange range}) { return LocaleStringAttribute(range: range, locale: locale); }`
  public func copy(range: TextRange) -> any StringAttribute {
    return LocaleStringAttribute(range: range, locale: locale)
  }

  // MARK: - CustomStringConvertible

  /// **Dart Source:** `semantics.dart:1680-1682`
  /// **Original:** `String toString() => 'LocaleStringAttribute($range, ${locale.toLanguageTag()})';`
  public var description: String {
    "LocaleStringAttribute(\(range), \(locale.toLanguageTag()))"
  }
}

// MARK: - SemanticsUpdate

/// An opaque object representing a batch of semantics updates.
///
/// To create a SemanticsUpdate object, use a `SemanticsUpdateBuilder`.
///
/// Semantics updates can be applied to the system's retained semantics tree
/// using the `PlatformDispatcher.updateSemantics` method.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/semantics.dart`
/// **Original Name:** `SemanticsUpdate`
/// **Lines:** 2083-2098
///
/// DIFFERENCE FROM DART: Using protocol instead of abstract class.
/// REASON: Swift doesn't have abstract classes; protocol is the idiomatic
/// equivalent for defining an interface that concrete classes must implement.
public protocol SemanticsUpdate: AnyObject {
  /// Releases the resources used by this semantics update.
  ///
  /// After calling this function, the semantics update cannot be used
  /// further.
  ///
  /// **Dart Source:** `semantics.dart:2090-2097`
  /// **Original:** `void dispose();`
  func dispose()
}

// MARK: - SemanticsUpdateBuilder

/// An object that creates `SemanticsUpdate` objects.
///
/// Once created, the `SemanticsUpdate` objects can be passed to
/// `PlatformDispatcher.updateSemantics` to update the semantics conveyed to the
/// user.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/semantics.dart`
/// **Original Name:** `SemanticsUpdateBuilder`
/// **Lines:** 1685-1867
///
/// DIFFERENCE FROM DART: Using protocol instead of abstract class.
/// REASON: Swift doesn't have abstract classes; protocol is the idiomatic
/// equivalent for defining an interface that concrete classes must implement.
///
/// DIFFERENCE FROM DART: Factory constructor `SemanticsUpdateBuilder() = _NativeSemanticsUpdateBuilder`
/// is handled by a separate `SemanticsUpdateBuilders` factory namespace enum (Task 6.1).
/// REASON: Swift protocols cannot have factory constructors.
public protocol SemanticsUpdateBuilder: AnyObject {
  /// Update the information associated with the node with the given `id`.
  ///
  /// The semantics nodes form a tree, with the root of the tree always having
  /// an id of zero. The `childrenInTraversalOrder` and `childrenInHitTestOrder`
  /// are the ids of the nodes that are immediate children of this node. The
  /// former enumerates children in traversal order, and the latter enumerates
  /// the same children in the hit test order. The two lists must have the same
  /// length and contain the same ids. They may only differ in the order the
  /// ids are listed in.
  ///
  /// The system retains the nodes that are currently reachable from the root.
  /// A given update need not contain information for nodes that do not change
  /// in the update. If a node is not reachable from the root after an update,
  /// the node will be discarded from the tree.
  ///
  /// **Dart Source:** `semantics.dart:1694-1840`
  /// **Original:** `void updateNode({...})`
  func updateNode(
    id: Int,
    flags: SemanticsFlags,
    actions: Int,
    maxValueLength: Int,
    currentValueLength: Int,
    textSelectionBase: Int,
    textSelectionExtent: Int,
    platformViewId: Int,
    scrollChildren: Int,
    scrollIndex: Int,
    scrollPosition: Double,
    scrollExtentMax: Double,
    scrollExtentMin: Double,
    rect: Rect,
    identifier: String,
    label: String,
    labelAttributes: [any StringAttribute],
    value: String,
    valueAttributes: [any StringAttribute],
    increasedValue: String,
    increasedValueAttributes: [any StringAttribute],
    decreasedValue: String,
    decreasedValueAttributes: [any StringAttribute],
    hint: String,
    hintAttributes: [any StringAttribute],
    tooltip: String,
    textDirection: TextDirection?,
    transform: [Double],
    childrenInTraversalOrder: [Int32],
    childrenInHitTestOrder: [Int32],
    additionalActions: [Int32],
    headingLevel: Int,
    linkUrl: String,
    role: SemanticsRole,
    controlsNodes: [String]?,
    validationResult: SemanticsValidationResult,
    inputType: SemanticsInputType,
    locale: Locale?
  )

  /// Update the custom semantics action associated with the given `id`.
  ///
  /// The name of the action exposed to the user is the `label`. For overridden
  /// standard actions this value is ignored.
  ///
  /// The `hint` should describe what happens when an action occurs, not the
  /// manner in which a tap is accomplished. For example, use "delete" instead
  /// of "double tap to delete".
  ///
  /// The text direction of the `hint` and `label` is the same as the global
  /// window.
  ///
  /// For overridden standard actions, `overrideId` corresponds with a
  /// `SemanticsAction.index` value. For custom actions this argument should not be
  /// provided.
  ///
  /// **Dart Source:** `semantics.dart:1842-1857`
  /// **Original:** `void updateCustomAction({required int id, String? label, String? hint, int overrideId = -1});`
  func updateCustomAction(id: Int, label: String?, hint: String?, overrideId: Int)

  /// Creates a `SemanticsUpdate` object that encapsulates the updates recorded
  /// by this object.
  ///
  /// The returned object can be passed to `PlatformDispatcher.updateSemantics`
  /// to actually update the semantics retained by the system.
  ///
  /// This object is unusable after calling build.
  ///
  /// **Dart Source:** `semantics.dart:1859-1867`
  /// **Original:** `SemanticsUpdate build();`
  func build() -> any SemanticsUpdate
}

// MARK: - NativeSemanticsUpdate

/// Concrete implementation of SemanticsUpdate wrapping a C++ SemanticsUpdateBridge.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/semantics.dart`
/// **Original Name:** `_NativeSemanticsUpdate`
/// **Lines:** 2100-2113
///
/// DIFFERENCE FROM DART: Class is named `NativeSemanticsUpdate` (no underscore prefix).
/// REASON: Swift uses `public`/`internal` access control instead of underscore-prefix
/// naming convention for internal types.
///
/// DIFFERENCE FROM DART: Does not extend NativeFieldWrapperClass1.
/// REASON: Swift layer calls C++ directly via SemanticsUpdateBridge with
/// SWIFT_SHARED_REFERENCE for automatic memory management.
public class NativeSemanticsUpdate: SemanticsUpdate, CustomStringConvertible {
  /// The C++ bridge object - Swift ARC handles lifetime via SWIFT_SHARED_REFERENCE
  ///
  /// **Dart Source:** `semantics.dart:2100`
  /// **Original:** `_NativeSemanticsUpdate extends NativeFieldWrapperClass1`
  internal let bridge: flutter.swift_bridge.SemanticsUpdateBridge

  /// Creates a NativeSemanticsUpdate wrapping a SemanticsUpdateBridge.
  ///
  /// **Dart Source:** `semantics.dart:2105`
  /// **Original:** `_NativeSemanticsUpdate._()`
  ///
  /// DIFFERENCE FROM DART: Takes a SemanticsUpdateBridge parameter instead of being
  /// engine-created via NativeFieldWrapperClass1.
  /// REASON: Swift creates the wrapper directly around the C++ bridge object.
  internal init(_ bridge: flutter.swift_bridge.SemanticsUpdateBridge) {
    self.bridge = bridge
  }

  /// Releases the resources used by this semantics update.
  ///
  /// After calling this function, the semantics update cannot be used further.
  ///
  /// **Dart Source:** `semantics.dart:2107-2109`
  /// **Original:** `@Native<Void Function(Pointer<Void>)>(symbol: 'SemanticsUpdate::dispose') external void dispose();`
  public func dispose() {
    bridge.Dispose()
  }

  // MARK: - CustomStringConvertible

  /// **Dart Source:** `semantics.dart:2111-2112`
  /// **Original:** `String toString() => 'SemanticsUpdate';`
  public var description: String {
    "SemanticsUpdate"
  }
}

// MARK: - NativeSemanticsUpdateBuilder

/// Concrete implementation of SemanticsUpdateBuilder wrapping a C++
/// SemanticsUpdateBuilderBridge.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/semantics.dart`
/// **Original Name:** `_NativeSemanticsUpdateBuilder`
/// **Lines:** 1869-2081
///
/// DIFFERENCE FROM DART: Class is named `NativeSemanticsUpdateBuilder` (no underscore prefix).
/// REASON: Swift uses `public`/`internal` access control instead of underscore-prefix
/// naming convention for internal types.
///
/// DIFFERENCE FROM DART: Does not extend NativeFieldWrapperClass1.
/// REASON: Swift layer calls C++ directly via SemanticsUpdateBuilderBridge with
/// SWIFT_SHARED_REFERENCE for automatic memory management.
public class NativeSemanticsUpdateBuilder: SemanticsUpdateBuilder, CustomStringConvertible {
  /// The C++ bridge object - Swift ARC handles lifetime via SWIFT_SHARED_REFERENCE
  ///
  /// **Dart Source:** `semantics.dart:1869-1870`
  /// **Original:** `_NativeSemanticsUpdateBuilder extends NativeFieldWrapperClass1`
  private let bridge: flutter.swift_bridge.SemanticsUpdateBuilderBridge

  /// Creates an empty SemanticsUpdateBuilder.
  ///
  /// **Dart Source:** `semantics.dart:1871-1873`
  /// **Original:** `_NativeSemanticsUpdateBuilder() { _constructor(); }`
  /// where `_constructor` is `@Native SemanticsUpdateBuilder::Create`
  public init() {
    self.bridge = flutter.swift_bridge.SemanticsUpdateBuilderBridge()
  }

  /// Update the information associated with the node with the given `id`.
  ///
  /// **Dart Source:** `semantics.dart:1878-1967`
  /// **Original:** `void updateNode({...})` which validates then calls `_updateNode(...)`
  ///
  /// DIFFERENCE FROM DART: String attributes are flattened into parallel arrays
  /// (types, starts, ends, locales) before passing to the C++ bridge.
  /// REASON: The C++ bridge accepts primitive arrays rather than Dart List<StringAttribute>.
  /// Swift handles the conversion from [StringAttribute] to flattened arrays.
  public func updateNode(
    id: Int,
    flags: SemanticsFlags,
    actions: Int,
    maxValueLength: Int,
    currentValueLength: Int,
    textSelectionBase: Int,
    textSelectionExtent: Int,
    platformViewId: Int,
    scrollChildren: Int,
    scrollIndex: Int,
    scrollPosition: Double,
    scrollExtentMax: Double,
    scrollExtentMin: Double,
    rect: Rect,
    identifier: String,
    label: String,
    labelAttributes: [any StringAttribute],
    value: String,
    valueAttributes: [any StringAttribute],
    increasedValue: String,
    increasedValueAttributes: [any StringAttribute],
    decreasedValue: String,
    decreasedValueAttributes: [any StringAttribute],
    hint: String,
    hintAttributes: [any StringAttribute],
    tooltip: String,
    textDirection: TextDirection?,
    transform: [Double],
    childrenInTraversalOrder: [Int32],
    childrenInHitTestOrder: [Int32],
    additionalActions: [Int32],
    headingLevel: Int = 0,
    linkUrl: String = "",
    role: SemanticsRole = .none,
    controlsNodes: [String]?,
    validationResult: SemanticsValidationResult = .none,
    inputType: SemanticsInputType,
    locale: Locale?
  ) {
    // Validation matching Dart source
    // **Dart Source:** `semantics.dart:1919`
    assert(matrix4IsValid(transform))
    // **Dart Source:** `semantics.dart:1920-1923`
    assert(
      headingLevel >= 0 && headingLevel <= 6,
      "Heading level must be between 1 and 6, or 0 to indicate that this node is not a heading."
    )

    // Flatten string attributes into parallel arrays for C++ bridge
    let (labelTypes, labelStarts, labelEnds, labelLocales) =
      NativeSemanticsUpdateBuilder._flattenStringAttributes(labelAttributes)
    let (valueTypes, valueStarts, valueEnds, valueLocales) =
      NativeSemanticsUpdateBuilder._flattenStringAttributes(valueAttributes)
    let (increasedTypes, increasedStarts, increasedEnds, increasedLocales) =
      NativeSemanticsUpdateBuilder._flattenStringAttributes(increasedValueAttributes)
    let (decreasedTypes, decreasedStarts, decreasedEnds, decreasedLocales) =
      NativeSemanticsUpdateBuilder._flattenStringAttributes(decreasedValueAttributes)
    let (hintTypes, hintStarts, hintEnds, hintLocales) =
      NativeSemanticsUpdateBuilder._flattenStringAttributes(hintAttributes)

    // Convert textDirection to int: 0=unknown, 1=RTL, 2=LTR
    // **Dart Source:** `semantics.dart:1954`
    // **Original:** `textDirection != null ? textDirection.index + 1 : 0`
    let textDirectionInt: Int32 = _textDirectionToInt(textDirection)

    // Convert controlsNodes to comma-separated string
    // **Dart Source:** `semantics.dart:1962`
    let controlsNodesStr: String
    let hasControlsNodes: Bool
    if let nodes = controlsNodes {
      controlsNodesStr = nodes.joined(separator: ",")
      hasControlsNodes = true
    } else {
      controlsNodesStr = ""
      hasControlsNodes = false
    }

    // Convert locale to BCP 47 language tag
    // **Dart Source:** `semantics.dart:1965`
    // **Original:** `locale?.toLanguageTag() ?? ''`
    let localeStr = locale?.toLanguageTag() ?? ""

    // Convert enum values to indices
    let roleIndex = Int32(_semanticsRoleIndex(role))
    let validationResultIndex = Int32(_semanticsValidationResultIndex(validationResult))
    let inputTypeIndex = Int32(_semanticsInputTypeIndex(inputType))

    // Build std::string arrays for locale parameters
    let labelLocalesArr = _buildLocaleArray(labelLocales)
    let valueLocalesArr = _buildLocaleArray(valueLocales)
    let increasedLocalesArr = _buildLocaleArray(increasedLocales)
    let decreasedLocalesArr = _buildLocaleArray(decreasedLocales)
    let hintLocalesArr = _buildLocaleArray(hintLocales)

    // Call C++ bridge using withUnsafeBufferPointer for array parameters
    // **Dart Source:** `semantics.dart:1924-1966` (_updateNode call)
    // **Dart Source:** `semantics.dart:2015-2057` (@Native _updateNode)
    _callUpdateNode(
      bridge: bridge,
      id: Int32(id),
      flagsBridge: flags.bridge,
      actions: Int32(actions),
      maxValueLength: Int32(maxValueLength),
      currentValueLength: Int32(currentValueLength),
      textSelectionBase: Int32(textSelectionBase),
      textSelectionExtent: Int32(textSelectionExtent),
      platformViewId: Int32(platformViewId),
      scrollChildren: Int32(scrollChildren),
      scrollIndex: Int32(scrollIndex),
      scrollPosition: scrollPosition,
      scrollExtentMax: scrollExtentMax,
      scrollExtentMin: scrollExtentMin,
      left: rect.left, top: rect.top, right: rect.right, bottom: rect.bottom,
      identifier: identifier, label: label,
      labelTypes: labelTypes, labelStarts: labelStarts, labelEnds: labelEnds,
      labelLocales: labelLocalesArr,
      value: value,
      valueTypes: valueTypes, valueStarts: valueStarts, valueEnds: valueEnds,
      valueLocales: valueLocalesArr,
      increasedValue: increasedValue,
      increasedTypes: increasedTypes, increasedStarts: increasedStarts,
      increasedEnds: increasedEnds, increasedLocales: increasedLocalesArr,
      decreasedValue: decreasedValue,
      decreasedTypes: decreasedTypes, decreasedStarts: decreasedStarts,
      decreasedEnds: decreasedEnds, decreasedLocales: decreasedLocalesArr,
      hint: hint,
      hintTypes: hintTypes, hintStarts: hintStarts, hintEnds: hintEnds,
      hintLocales: hintLocalesArr,
      tooltip: tooltip,
      textDirection: textDirectionInt,
      transform: transform,
      childrenInTraversalOrder: childrenInTraversalOrder,
      childrenInHitTestOrder: childrenInHitTestOrder,
      additionalActions: additionalActions,
      headingLevel: Int32(headingLevel),
      linkUrl: linkUrl,
      role: roleIndex,
      controlsNodes: controlsNodesStr,
      hasControlsNodes: hasControlsNodes,
      validationResult: validationResultIndex,
      inputType: inputTypeIndex,
      locale: localeStr
    )
  }

  /// Update the custom semantics action associated with the given `id`.
  ///
  /// **Dart Source:** `semantics.dart:2059-2062`
  /// **Original:** `void updateCustomAction({required int id, String? label, String? hint, int overrideId = -1}) { _updateCustomAction(id, label ?? '', hint ?? '', overrideId); }`
  public func updateCustomAction(id: Int, label: String?, hint: String?, overrideId: Int) {
    // **Dart Source:** `semantics.dart:2061`
    // Dart passes empty string when label/hint is null
    // C++ bridge now uses const char* to avoid std::string ABI mismatch.
    (label ?? "").withCString { labelPtr in
      (hint ?? "").withCString { hintPtr in
        bridge.UpdateCustomAction(
          Int32(id),
          labelPtr,
          hintPtr,
          Int32(overrideId)
        )
      }
    }
  }

  /// Creates a `SemanticsUpdate` object that encapsulates the updates recorded
  /// by this object.
  ///
  /// **Dart Source:** `semantics.dart:2069-2074`
  /// **Original:** `SemanticsUpdate build() { final _NativeSemanticsUpdate semanticsUpdate = _NativeSemanticsUpdate._(); _build(semanticsUpdate); return semanticsUpdate; }`
  ///
  /// DIFFERENCE FROM DART: Dart creates an empty _NativeSemanticsUpdate and passes
  /// it to _build(). Swift calls bridge.Build() which returns a SemanticsUpdateBridge.
  /// REASON: The C++ bridge Build() method creates and returns the update directly,
  /// which is more natural for the Swift/C++ interop pattern.
  public func build() -> any SemanticsUpdate {
    let updateBridge = bridge.Build()!
    return NativeSemanticsUpdate(updateBridge)
  }

  // MARK: - CustomStringConvertible

  /// **Dart Source:** `semantics.dart:2079-2080`
  /// **Original:** `String toString() => 'SemanticsUpdateBuilder';`
  public var description: String {
    "SemanticsUpdateBuilder"
  }

  // MARK: - Private Helpers

  /// Flattens an array of StringAttribute into parallel arrays for the C++ bridge.
  ///
  /// The C++ bridge accepts string attributes as parallel arrays:
  /// - types: 0 = SpellOut, 1 = Locale
  /// - starts: start position of the attribute range
  /// - ends: end position of the attribute range
  /// - locales: locale strings (empty string for SpellOut attributes)
  private static func _flattenStringAttributes(
    _ attributes: [any StringAttribute]
  ) -> ([Int32], [Int32], [Int32], [String]) {
    var types: [Int32] = []
    var starts: [Int32] = []
    var ends: [Int32] = []
    var locales: [String] = []

    for attr in attributes {
      starts.append(Int32(attr.range.start))
      ends.append(Int32(attr.range.end))

      if let localeAttr = attr as? LocaleStringAttribute {
        types.append(1)  // 1 = Locale
        locales.append(localeAttr.locale.toLanguageTag())
      } else {
        // SpellOutStringAttribute or any other type defaults to SpellOut
        types.append(0)  // 0 = SpellOut
        locales.append("")
      }
    }

    return (types, starts, ends, locales)
  }
}

// MARK: - Enum Index Helpers

/// Returns the index of a SemanticsRole enum value.
///
/// **Dart Source:** `semantics.dart:1961`
/// **Original:** `role.index`
///
/// Maps each SemanticsRole case to its ordinal index matching Dart's enum.index.
private func _semanticsRoleIndex(_ role: SemanticsRole) -> Int {
  switch role {
  case .none: return 0
  case .tab: return 1
  case .tabBar: return 2
  case .tabPanel: return 3
  case .dialog: return 4
  case .alertDialog: return 5
  case .table: return 6
  case .cell: return 7
  case .row: return 8
  case .columnHeader: return 9
  case .dragHandle: return 10
  case .spinButton: return 11
  case .comboBox: return 12
  case .menuBar: return 13
  case .menu: return 14
  case .menuItem: return 15
  case .menuItemCheckbox: return 16
  case .menuItemRadio: return 17
  case .list: return 18
  case .listItem: return 19
  case .form: return 20
  case .tooltip: return 21
  case .loadingSpinner: return 22
  case .progressBar: return 23
  case .hotKey: return 24
  case .radioGroup: return 25
  case .status: return 26
  case .alert: return 27
  case .complementary: return 28
  case .contentInfo: return 29
  case .main: return 30
  case .navigation: return 31
  case .region: return 32
  }
}

/// Returns the index of a SemanticsValidationResult enum value.
///
/// **Dart Source:** `semantics.dart:1963`
/// **Original:** `validationResult.index`
private func _semanticsValidationResultIndex(_ result: SemanticsValidationResult) -> Int {
  switch result {
  case .none: return 0
  case .valid: return 1
  case .invalid: return 2
  }
}

/// Returns the index of a SemanticsInputType enum value.
///
/// **Dart Source:** `semantics.dart:1964`
/// **Original:** `inputType.index`
private func _semanticsInputTypeIndex(_ inputType: SemanticsInputType) -> Int {
  switch inputType {
  case .none: return 0
  case .text: return 1
  case .url: return 2
  case .phone: return 3
  case .search: return 4
  case .email: return 5
  }
}

// MARK: - TextDirection Conversion

/// Converts a TextDirection? to an Int32 for the C++ bridge.
///
/// **Dart Source:** `semantics.dart:1954`
/// **Original:** `textDirection != null ? textDirection.index + 1 : 0`
///
/// Returns: 0=unknown/null, 1=RTL, 2=LTR
private func _textDirectionToInt(_ textDirection: TextDirection?) -> Int32 {
  guard let td = textDirection else { return 0 }
  switch td {
  case .rtl: return 1  // Dart TextDirection.rtl.index == 0, + 1 == 1
  case .ltr: return 2  // Dart TextDirection.ltr.index == 1, + 1 == 2
  }
}

// MARK: - Locale Array Builder

/// Converts a Swift [String] array to a [std.string] array for C++ interop.
///
/// Used to pass locale string arrays to the C++ bridge as `const std::string*`.
private func _buildLocaleArray(_ locales: [String]) -> [std.string] {
  return locales.map { std.string($0) }
}

// MARK: - UpdateNode Bridge Call

/// Helper struct to hold flattened string attribute arrays for C++ bridge.
private struct FlattenedAttributes {
  let types: [Int32]
  let starts: [Int32]
  let ends: [Int32]
  let locales: [std.string]
}

/// Calls the C++ bridge UpdateNode method with all parameters.
///
/// This is extracted to a separate function to avoid deeply nested closures
/// which cause the Swift compiler to time out. Uses ContiguousArray and
/// pointer arithmetic to avoid excessive nesting.
private func _callUpdateNode(
  bridge: flutter.swift_bridge.SemanticsUpdateBuilderBridge,
  id: Int32,
  flagsBridge: flutter.swift_bridge.SemanticsFlagsBridge,
  actions: Int32,
  maxValueLength: Int32,
  currentValueLength: Int32,
  textSelectionBase: Int32,
  textSelectionExtent: Int32,
  platformViewId: Int32,
  scrollChildren: Int32,
  scrollIndex: Int32,
  scrollPosition: Double,
  scrollExtentMax: Double,
  scrollExtentMin: Double,
  left: Double, top: Double, right: Double, bottom: Double,
  identifier: String, label: String,
  labelTypes: [Int32], labelStarts: [Int32], labelEnds: [Int32],
  labelLocales: [std.string],
  value: String,
  valueTypes: [Int32], valueStarts: [Int32], valueEnds: [Int32],
  valueLocales: [std.string],
  increasedValue: String,
  increasedTypes: [Int32], increasedStarts: [Int32], increasedEnds: [Int32],
  increasedLocales: [std.string],
  decreasedValue: String,
  decreasedTypes: [Int32], decreasedStarts: [Int32], decreasedEnds: [Int32],
  decreasedLocales: [std.string],
  hint: String,
  hintTypes: [Int32], hintStarts: [Int32], hintEnds: [Int32],
  hintLocales: [std.string],
  tooltip: String,
  textDirection: Int32,
  transform: [Double],
  childrenInTraversalOrder: [Int32],
  childrenInHitTestOrder: [Int32],
  additionalActions: [Int32],
  headingLevel: Int32,
  linkUrl: String,
  role: Int32,
  controlsNodes: String,
  hasControlsNodes: Bool,
  validationResult: Int32,
  inputType: Int32,
  locale: String
) {
  // Extract all array pointers in a flat structure to avoid deeply nested closures
  transform.withUnsafeBufferPointer { transformBuf in
    childrenInTraversalOrder.withUnsafeBufferPointer { traversalBuf in
      childrenInHitTestOrder.withUnsafeBufferPointer { hitTestBuf in
        additionalActions.withUnsafeBufferPointer { actionsBuf in
          labelTypes.withUnsafeBufferPointer { ltBuf in
            labelStarts.withUnsafeBufferPointer { lsBuf in
              labelEnds.withUnsafeBufferPointer { leBuf in
                labelLocales.withUnsafeBufferPointer { llBuf in
                  _callUpdateNodePart2(
                    bridge: bridge, id: id, flagsBridge: flagsBridge,
                    actions: actions, maxValueLength: maxValueLength,
                    currentValueLength: currentValueLength,
                    textSelectionBase: textSelectionBase,
                    textSelectionExtent: textSelectionExtent,
                    platformViewId: platformViewId,
                    scrollChildren: scrollChildren, scrollIndex: scrollIndex,
                    scrollPosition: scrollPosition,
                    scrollExtentMax: scrollExtentMax,
                    scrollExtentMin: scrollExtentMin,
                    left: left, top: top, right: right, bottom: bottom,
                    identifier: identifier, label: label,
                    labelAttrCount: Int32(labelTypes.count),
                    ltPtr: ltBuf.baseAddress, lsPtr: lsBuf.baseAddress,
                    lePtr: leBuf.baseAddress, llPtr: llBuf.baseAddress,
                    value: value,
                    valueTypes: valueTypes, valueStarts: valueStarts,
                    valueEnds: valueEnds, valueLocales: valueLocales,
                    increasedValue: increasedValue,
                    increasedTypes: increasedTypes,
                    increasedStarts: increasedStarts,
                    increasedEnds: increasedEnds,
                    increasedLocales: increasedLocales,
                    decreasedValue: decreasedValue,
                    decreasedTypes: decreasedTypes,
                    decreasedStarts: decreasedStarts,
                    decreasedEnds: decreasedEnds,
                    decreasedLocales: decreasedLocales,
                    hint: hint,
                    hintTypes: hintTypes, hintStarts: hintStarts,
                    hintEnds: hintEnds, hintLocales: hintLocales,
                    tooltip: tooltip, textDirection: textDirection,
                    transformPtr: transformBuf.baseAddress,
                    transformLen: Int32(transform.count),
                    traversalPtr: traversalBuf.baseAddress,
                    traversalLen: Int32(childrenInTraversalOrder.count),
                    hitTestPtr: hitTestBuf.baseAddress,
                    hitTestLen: Int32(childrenInHitTestOrder.count),
                    actionsPtr: actionsBuf.baseAddress,
                    actionsLen: Int32(additionalActions.count),
                    headingLevel: headingLevel, linkUrl: linkUrl,
                    role: role, controlsNodes: controlsNodes,
                    hasControlsNodes: hasControlsNodes,
                    validationResult: validationResult,
                    inputType: inputType, locale: locale
                  )
                }
              }
            }
          }
        }
      }
    }
  }
}

/// Second part of UpdateNode bridge call - extracts value/increased/decreased/hint
/// attribute pointers and calls the bridge.
private func _callUpdateNodePart2(
  bridge: flutter.swift_bridge.SemanticsUpdateBuilderBridge,
  id: Int32, flagsBridge: flutter.swift_bridge.SemanticsFlagsBridge,
  actions: Int32, maxValueLength: Int32, currentValueLength: Int32,
  textSelectionBase: Int32, textSelectionExtent: Int32,
  platformViewId: Int32, scrollChildren: Int32, scrollIndex: Int32,
  scrollPosition: Double, scrollExtentMax: Double, scrollExtentMin: Double,
  left: Double, top: Double, right: Double, bottom: Double,
  identifier: String, label: String,
  labelAttrCount: Int32,
  ltPtr: UnsafePointer<Int32>?, lsPtr: UnsafePointer<Int32>?,
  lePtr: UnsafePointer<Int32>?, llPtr: UnsafePointer<std.string>?,
  value: String,
  valueTypes: [Int32], valueStarts: [Int32],
  valueEnds: [Int32], valueLocales: [std.string],
  increasedValue: String,
  increasedTypes: [Int32], increasedStarts: [Int32],
  increasedEnds: [Int32], increasedLocales: [std.string],
  decreasedValue: String,
  decreasedTypes: [Int32], decreasedStarts: [Int32],
  decreasedEnds: [Int32], decreasedLocales: [std.string],
  hint: String,
  hintTypes: [Int32], hintStarts: [Int32],
  hintEnds: [Int32], hintLocales: [std.string],
  tooltip: String, textDirection: Int32,
  transformPtr: UnsafePointer<Double>?, transformLen: Int32,
  traversalPtr: UnsafePointer<Int32>?, traversalLen: Int32,
  hitTestPtr: UnsafePointer<Int32>?, hitTestLen: Int32,
  actionsPtr: UnsafePointer<Int32>?, actionsLen: Int32,
  headingLevel: Int32, linkUrl: String,
  role: Int32, controlsNodes: String, hasControlsNodes: Bool,
  validationResult: Int32, inputType: Int32, locale: String
) {
  valueTypes.withUnsafeBufferPointer { vtBuf in
    valueStarts.withUnsafeBufferPointer { vsBuf in
      valueEnds.withUnsafeBufferPointer { veBuf in
        valueLocales.withUnsafeBufferPointer { vlBuf in
          increasedTypes.withUnsafeBufferPointer { itBuf in
            increasedStarts.withUnsafeBufferPointer { isBuf in
              increasedEnds.withUnsafeBufferPointer { ieBuf in
                increasedLocales.withUnsafeBufferPointer { ilBuf in
                  _callUpdateNodePart3(
                    bridge: bridge, id: id, flagsBridge: flagsBridge,
                    actions: actions, maxValueLength: maxValueLength,
                    currentValueLength: currentValueLength,
                    textSelectionBase: textSelectionBase,
                    textSelectionExtent: textSelectionExtent,
                    platformViewId: platformViewId,
                    scrollChildren: scrollChildren, scrollIndex: scrollIndex,
                    scrollPosition: scrollPosition,
                    scrollExtentMax: scrollExtentMax,
                    scrollExtentMin: scrollExtentMin,
                    left: left, top: top, right: right, bottom: bottom,
                    identifier: identifier, label: label,
                    labelAttrCount: labelAttrCount,
                    ltPtr: ltPtr, lsPtr: lsPtr, lePtr: lePtr, llPtr: llPtr,
                    value: value,
                    valueAttrCount: Int32(valueTypes.count),
                    vtPtr: vtBuf.baseAddress, vsPtr: vsBuf.baseAddress,
                    vePtr: veBuf.baseAddress, vlPtr: vlBuf.baseAddress,
                    increasedValue: increasedValue,
                    increasedAttrCount: Int32(increasedTypes.count),
                    itPtr: itBuf.baseAddress, isPtr: isBuf.baseAddress,
                    iePtr: ieBuf.baseAddress, ilPtr: ilBuf.baseAddress,
                    decreasedValue: decreasedValue,
                    decreasedTypes: decreasedTypes,
                    decreasedStarts: decreasedStarts,
                    decreasedEnds: decreasedEnds,
                    decreasedLocales: decreasedLocales,
                    hint: hint,
                    hintTypes: hintTypes, hintStarts: hintStarts,
                    hintEnds: hintEnds, hintLocales: hintLocales,
                    tooltip: tooltip, textDirection: textDirection,
                    transformPtr: transformPtr, transformLen: transformLen,
                    traversalPtr: traversalPtr, traversalLen: traversalLen,
                    hitTestPtr: hitTestPtr, hitTestLen: hitTestLen,
                    actionsPtr: actionsPtr, actionsLen: actionsLen,
                    headingLevel: headingLevel, linkUrl: linkUrl,
                    role: role, controlsNodes: controlsNodes,
                    hasControlsNodes: hasControlsNodes,
                    validationResult: validationResult,
                    inputType: inputType, locale: locale
                  )
                }
              }
            }
          }
        }
      }
    }
  }
}

/// Third (final) part of UpdateNode bridge call - uses C-linkage wrapper
/// to avoid std::string ABI mismatch between Flutter's libc++ and Swift's.
private func _callUpdateNodePart3(
  bridge: flutter.swift_bridge.SemanticsUpdateBuilderBridge,
  id: Int32, flagsBridge: flutter.swift_bridge.SemanticsFlagsBridge,
  actions: Int32, maxValueLength: Int32, currentValueLength: Int32,
  textSelectionBase: Int32, textSelectionExtent: Int32,
  platformViewId: Int32, scrollChildren: Int32, scrollIndex: Int32,
  scrollPosition: Double, scrollExtentMax: Double, scrollExtentMin: Double,
  left: Double, top: Double, right: Double, bottom: Double,
  identifier: String, label: String,
  labelAttrCount: Int32,
  ltPtr: UnsafePointer<Int32>?, lsPtr: UnsafePointer<Int32>?,
  lePtr: UnsafePointer<Int32>?, llPtr: UnsafePointer<std.string>?,
  value: String,
  valueAttrCount: Int32,
  vtPtr: UnsafePointer<Int32>?, vsPtr: UnsafePointer<Int32>?,
  vePtr: UnsafePointer<Int32>?, vlPtr: UnsafePointer<std.string>?,
  increasedValue: String,
  increasedAttrCount: Int32,
  itPtr: UnsafePointer<Int32>?, isPtr: UnsafePointer<Int32>?,
  iePtr: UnsafePointer<Int32>?, ilPtr: UnsafePointer<std.string>?,
  decreasedValue: String,
  decreasedTypes: [Int32], decreasedStarts: [Int32],
  decreasedEnds: [Int32], decreasedLocales: [std.string],
  hint: String,
  hintTypes: [Int32], hintStarts: [Int32],
  hintEnds: [Int32], hintLocales: [std.string],
  tooltip: String, textDirection: Int32,
  transformPtr: UnsafePointer<Double>?, transformLen: Int32,
  traversalPtr: UnsafePointer<Int32>?, traversalLen: Int32,
  hitTestPtr: UnsafePointer<Int32>?, hitTestLen: Int32,
  actionsPtr: UnsafePointer<Int32>?, actionsLen: Int32,
  headingLevel: Int32, linkUrl: String,
  role: Int32, controlsNodes: String, hasControlsNodes: Bool,
  validationResult: Int32, inputType: Int32, locale: String
) {
  // Helper to convert std.string array to C string pointers
  func stdStringArrayToCStrings(_ arr: UnsafePointer<std.string>?, count: Int32) -> [UnsafePointer<CChar>?] {
    guard let arr = arr, count > 0 else { return [] }
    var result: [UnsafePointer<CChar>?] = []
    for i in 0..<Int(count) {
      let swiftStr = String(arr[i])
      let cStr = strdup(swiftStr)
      result.append(cStr.map { UnsafePointer($0) })
    }
    return result
  }

  func stdStringVecToCStrings(_ vec: [std.string]) -> [UnsafePointer<CChar>?] {
    return vec.map { str in
      let swiftStr = String(str)
      let cStr = strdup(swiftStr)
      return cStr.map { UnsafePointer($0) }
    }
  }

  func freeCStrings(_ arr: inout [UnsafePointer<CChar>?]) {
    for ptr in arr {
      if let p = ptr {
        free(UnsafeMutablePointer(mutating: p))
      }
    }
    arr.removeAll()
  }

  // Convert all locale arrays
  var llCStrs = stdStringArrayToCStrings(llPtr, count: labelAttrCount)
  var vlCStrs = stdStringArrayToCStrings(vlPtr, count: valueAttrCount)
  var ilCStrs = stdStringArrayToCStrings(ilPtr, count: increasedAttrCount)
  var dlCStrs = stdStringVecToCStrings(decreasedLocales)
  var hlCStrs = stdStringVecToCStrings(hintLocales)

  defer {
    freeCStrings(&llCStrs)
    freeCStrings(&vlCStrs)
    freeCStrings(&ilCStrs)
    freeCStrings(&dlCStrs)
    freeCStrings(&hlCStrs)
  }

  decreasedTypes.withUnsafeBufferPointer { dtBuf in
    decreasedStarts.withUnsafeBufferPointer { dsBuf in
      decreasedEnds.withUnsafeBufferPointer { deBuf in
        dlCStrs.withUnsafeBufferPointer { dlBuf in
          hintTypes.withUnsafeBufferPointer { htBuf in
            hintStarts.withUnsafeBufferPointer { hsBuf in
              hintEnds.withUnsafeBufferPointer { heBuf in
                hlCStrs.withUnsafeBufferPointer { hlBuf in
                  llCStrs.withUnsafeBufferPointer { llBuf in
                    vlCStrs.withUnsafeBufferPointer { vlBuf in
                      ilCStrs.withUnsafeBufferPointer { ilBuf in
                        identifier.withCString { idPtr in
                          label.withCString { labPtr in
                            value.withCString { valPtr in
                              increasedValue.withCString { incPtr in
                                decreasedValue.withCString { decPtr in
                                  hint.withCString { hintPtr in
                                    tooltip.withCString { tipPtr in
                                      linkUrl.withCString { urlPtr in
                                        controlsNodes.withCString { ctrlPtr in
                                          locale.withCString { locPtr in
                                            bridge.UpdateNode(
                                              id, flagsBridge, actions,
                                              maxValueLength, currentValueLength,
                                              textSelectionBase, textSelectionExtent,
                                              platformViewId, scrollChildren, scrollIndex,
                                              scrollPosition, scrollExtentMax, scrollExtentMin,
                                              left, top, right, bottom,
                                              idPtr, labPtr,
                                              labelAttrCount, ltPtr, lsPtr, lePtr, llBuf.baseAddress,
                                              valPtr,
                                              valueAttrCount, vtPtr, vsPtr, vePtr, vlBuf.baseAddress,
                                              incPtr,
                                              increasedAttrCount, itPtr, isPtr, iePtr, ilBuf.baseAddress,
                                              decPtr,
                                              Int32(decreasedTypes.count),
                                              dtBuf.baseAddress, dsBuf.baseAddress,
                                              deBuf.baseAddress, dlBuf.baseAddress,
                                              hintPtr,
                                              Int32(hintTypes.count),
                                              htBuf.baseAddress, hsBuf.baseAddress,
                                              heBuf.baseAddress, hlBuf.baseAddress,
                                              tipPtr, textDirection,
                                              transformPtr, transformLen,
                                              traversalPtr, traversalLen,
                                              hitTestPtr, hitTestLen,
                                              actionsPtr, actionsLen,
                                              headingLevel, urlPtr,
                                              role, ctrlPtr,
                                              hasControlsNodes,
                                              validationResult, inputType, locPtr
                                            )
                                          }
                                        }
                                      }
                                    }
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

// MARK: - SemanticsUpdateBuilders Factory

/// Factory namespace for creating SemanticsUpdateBuilder instances.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/semantics.dart`
/// **Original:** `factory SemanticsUpdateBuilder() = _NativeSemanticsUpdateBuilder;` (line 1692)
///
/// In Dart, `SemanticsUpdateBuilder` has a factory constructor that returns a
/// `_NativeSemanticsUpdateBuilder`. In Swift, protocols cannot have factory
/// initializers, so this enum serves as the factory namespace.
///
/// DIFFERENCE FROM DART: Uses an enum factory namespace instead of factory constructor.
/// REASON: Swift protocols cannot have factory constructors. This pattern provides
/// equivalent ergonomics while maintaining type safety.
public enum SemanticsUpdateBuilders {
  /// Creates a new `SemanticsUpdateBuilder`.
  ///
  /// **Dart Source:** `semantics.dart:1692`
  /// **Original:** `factory SemanticsUpdateBuilder() = _NativeSemanticsUpdateBuilder;`
  ///
  /// Equivalent to Dart's `SemanticsUpdateBuilder()` factory constructor.
  ///
  /// ## Usage
  ///
  /// ```swift
  /// // Dart: let builder = SemanticsUpdateBuilder();
  /// // Swift: let builder = SemanticsUpdateBuilders.create()
  /// let builder = SemanticsUpdateBuilders.create()
  /// builder.updateNode(...)
  /// let update = builder.build()
  /// ```
  public static func create() -> any SemanticsUpdateBuilder {
    return NativeSemanticsUpdateBuilder()
  }
}

// MARK: - Matrix4 Validation

/// Validates a 4x4 transformation matrix.
///
/// **Dart Source:** `painting.dart:45-49` - `_matrix4IsValid`
/// Returns true if validation passes (always true; asserts in debug).
private func matrix4IsValid(_ matrix4: [Double]) -> Bool {
  assert(matrix4.count == 16, "Matrix4 must have 16 entries.")
  assert(matrix4.allSatisfy { $0.isFinite }, "Matrix4 entries must be finite.")
  return true
}
