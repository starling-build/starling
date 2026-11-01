// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// The full `SemanticsConfiguration` class, migrated from `semantics.dart`.
///
/// **Dart Source:** `packages/flutter/lib/src/semantics/semantics.dart`
/// **Original Name:** `SemanticsConfiguration`
/// **Lines:** 4547-6193

import Foundation
import FlutterSwiftBridge

// MARK: - SemanticsConfiguration

/// Describes the semantic information associated with the owning
/// `RenderObject`.
///
/// The information provided in the configuration is used to generate the
/// semantics tree.
///
/// **Dart Source:** `semantics.dart:4547-6193`
///
/// DIFFERENCE FROM DART: Uses a Swift `class` (reference type).
/// REASON: The Dart class is mutable and passed by reference; Swift `class`
/// is the idiomatic equivalent.
public class SemanticsConfiguration: Hashable {

  public init() {}

  // MARK: - Hashable

  public static func == (lhs: SemanticsConfiguration, rhs: SemanticsConfiguration) -> Bool {
    return lhs === rhs
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(ObjectIdentifier(self))
  }

  // MARK: - Semantic Boundary Behavior
  /// **Dart Source:** `semantics.dart:4548-4638`

  /// Whether the `RenderObject` owner of this configuration wants to own its
  /// own `SemanticsNode`.
  ///
  /// **Dart Source:** `semantics.dart:4563-4568`
  /// **Original:** `bool get isSemanticBoundary => _isSemanticBoundary;`
  public var isSemanticBoundary: Bool {
    get { _isSemanticBoundary }
    set {
      assert(!isMergingSemanticsOfDescendants || newValue)
      _isSemanticBoundary = newValue
    }
  }
  private var _isSemanticBoundary: Bool = false

  /// The locale for widgets in the subtree.
  ///
  /// **Dart Source:** `semantics.dart:4571-4580`
  /// **Original:** `Locale? get localeForSubtree => _localeForSubtree;`
  public var localeForSubtree: FlutterSwiftBridge.Locale? {
    get { _localeForSubtree }
    set {
      assert(
        newValue == nil || _isSemanticBoundary,
        "to set locale for subtree, this configuration must also be a semantics boundary."
      )
      _localeForSubtree = newValue
    }
  }
  private var _localeForSubtree: FlutterSwiftBridge.Locale?

  /// The locale of the resulting semantics node if this configuration formed
  /// one. Used internally to track the inherited locale.
  ///
  /// **Dart Source:** `semantics.dart:4589`
  /// **Original:** `Locale? locale;`
  public var locale: FlutterSwiftBridge.Locale?

  /// Whether to block pointer related user actions for the rendering subtree.
  ///
  /// **Dart Source:** `semantics.dart:4605`
  /// **Original:** `bool isBlockingUserActions = false;`
  public var isBlockingUserActions: Bool = false

  /// Whether the configuration forces all children of the owning `RenderObject`
  /// that want to contribute semantic information to do so as explicit
  /// `SemanticsNode`s.
  ///
  /// **Dart Source:** `semantics.dart:4620`
  /// **Original:** `bool explicitChildNodes = false;`
  public var explicitChildNodes: Bool = false

  /// Whether the owning `RenderObject` makes other `RenderObject`s previously
  /// painted within the same semantic boundary unreachable for accessibility.
  ///
  /// **Dart Source:** `semantics.dart:4637`
  /// **Original:** `bool isBlockingSemanticsOfPreviouslyPaintedNodes = false;`
  public var isBlockingSemanticsOfPreviouslyPaintedNodes: Bool = false

  // MARK: - Annotation Tracking
  /// **Dart Source:** `semantics.dart:4643-4648`

  /// Whether this configuration is empty.
  ///
  /// An empty configuration doesn't contain any semantic information that it
  /// wants to contribute to the semantics tree.
  ///
  /// **Dart Source:** `semantics.dart:4647-4648`
  /// **Original:** `bool get hasBeenAnnotated => _hasBeenAnnotated;`
  public var hasBeenAnnotated: Bool { _hasBeenAnnotated }
  internal var _hasBeenAnnotated: Bool = false

  // MARK: - Actions
  /// **Dart Source:** `semantics.dart:4650-5136`

  /// The actions (with associated action handlers) that this configuration
  /// would like to contribute to the semantics tree.
  ///
  /// **Dart Source:** `semantics.dart:4656-4657`
  /// **Original:** `final Map<SemanticsAction, SemanticsActionHandler> _actions = ...;`
  internal var _actions: [SemanticsAction: SemanticsActionHandler] = [:]

  /// The effective actions bitmask, considering blocked user actions.
  ///
  /// **Dart Source:** `semantics.dart:4659-4660`
  /// **Original:** `int get _effectiveActionsAsBits => ...`
  var _effectiveActionsAsBits: Int {
    isBlockingUserActions ? _actionsAsBits & _kUnblockedUserActions : _actionsAsBits
  }

  /// **Dart Source:** `semantics.dart:4661`
  internal var _actionsAsBits: Int = 0

  /// Adds an `action` to the semantics tree.
  ///
  /// **Dart Source:** `semantics.dart:4667-4671`
  /// **Original:** `void _addAction(SemanticsAction action, SemanticsActionHandler handler)`
  private func _addAction(_ action: SemanticsAction, _ handler: @escaping SemanticsActionHandler) {
    _actions[action] = handler
    _actionsAsBits |= action.index
    _hasBeenAnnotated = true
  }

  /// Adds an `action` to the semantics tree, whose `handler` does not expect
  /// any arguments.
  ///
  /// **Dart Source:** `semantics.dart:4678-4683`
  /// **Original:** `void _addArgumentlessAction(SemanticsAction action, VoidCallback handler)`
  private func _addArgumentlessAction(_ action: SemanticsAction, _ handler: @escaping VoidCallback) {
    _addAction(action) { args in
      assert(args == nil)
      handler()
    }
  }

  // MARK: - Action Handler Setters
  /// **Dart Source:** `semantics.dart:4685-5115`

  /// The handler for `SemanticsAction.tap`.
  ///
  /// **Dart Source:** `semantics.dart:4705-4710`
  /// **Original:** `VoidCallback? get onTap => _onTap;`
  public var onTap: VoidCallback? {
    get { _onTap }
    set {
      _addArgumentlessAction(.tap, newValue!)
      _onTap = newValue
    }
  }
  private var _onTap: VoidCallback?

  /// The handler for `SemanticsAction.longPress`.
  ///
  /// **Dart Source:** `semantics.dart:4720-4725`
  /// **Original:** `VoidCallback? get onLongPress => _onLongPress;`
  public var onLongPress: VoidCallback? {
    get { _onLongPress }
    set {
      _addArgumentlessAction(.longPress, newValue!)
      _onLongPress = newValue
    }
  }
  private var _onLongPress: VoidCallback?

  /// The handler for `SemanticsAction.scrollLeft`.
  ///
  /// **Dart Source:** `semantics.dart:4738-4743`
  /// **Original:** `VoidCallback? get onScrollLeft => _onScrollLeft;`
  public var onScrollLeft: VoidCallback? {
    get { _onScrollLeft }
    set {
      _addArgumentlessAction(.scrollLeft, newValue!)
      _onScrollLeft = newValue
    }
  }
  private var _onScrollLeft: VoidCallback?

  /// The handler for `SemanticsAction.dismiss`.
  ///
  /// **Dart Source:** `semantics.dart:4753-4757`
  /// **Original:** `VoidCallback? get onDismiss => _onDismiss;`
  public var onDismiss: VoidCallback? {
    get { _onDismiss }
    set {
      _addArgumentlessAction(.dismiss, newValue!)
      _onDismiss = newValue
    }
  }
  private var _onDismiss: VoidCallback?

  /// The handler for `SemanticsAction.scrollRight`.
  ///
  /// **Dart Source:** `semantics.dart:4770-4775`
  /// **Original:** `VoidCallback? get onScrollRight => _onScrollRight;`
  public var onScrollRight: VoidCallback? {
    get { _onScrollRight }
    set {
      _addArgumentlessAction(.scrollRight, newValue!)
      _onScrollRight = newValue
    }
  }
  private var _onScrollRight: VoidCallback?

  /// The handler for `SemanticsAction.scrollUp`.
  ///
  /// **Dart Source:** `semantics.dart:4788-4793`
  /// **Original:** `VoidCallback? get onScrollUp => _onScrollUp;`
  public var onScrollUp: VoidCallback? {
    get { _onScrollUp }
    set {
      _addArgumentlessAction(.scrollUp, newValue!)
      _onScrollUp = newValue
    }
  }
  private var _onScrollUp: VoidCallback?

  /// The handler for `SemanticsAction.scrollDown`.
  ///
  /// **Dart Source:** `semantics.dart:4806-4811`
  /// **Original:** `VoidCallback? get onScrollDown => _onScrollDown;`
  public var onScrollDown: VoidCallback? {
    get { _onScrollDown }
    set {
      _addArgumentlessAction(.scrollDown, newValue!)
      _onScrollDown = newValue
    }
  }
  private var _onScrollDown: VoidCallback?

  /// The handler for `SemanticsAction.scrollToOffset`.
  ///
  /// **Dart Source:** `semantics.dart:4825-4834`
  /// **Original:** `ScrollToOffsetHandler? get onScrollToOffset => _onScrollToOffset;`
  ///
  /// DIFFERENCE FROM DART: The action handler unpacks `[Double]` instead of `Float64List`.
  /// REASON: Swift does not have Dart's `Float64List` type; `[Double]` is the equivalent.
  public var onScrollToOffset: ScrollToOffsetHandler? {
    get { _onScrollToOffset }
    set {
      assert(newValue != nil)
      let handler = newValue!
      _addAction(.scrollToOffset) { args in
        let list = args! as! [Double]
        handler(Offset(list[0], list[1]))
      }
      _onScrollToOffset = newValue
    }
  }
  private var _onScrollToOffset: ScrollToOffsetHandler?

  /// The handler for `SemanticsAction.increase`.
  ///
  /// **Dart Source:** `semantics.dart:4847-4852`
  /// **Original:** `VoidCallback? get onIncrease => _onIncrease;`
  public var onIncrease: VoidCallback? {
    get { _onIncrease }
    set {
      _addArgumentlessAction(.increase, newValue!)
      _onIncrease = newValue
    }
  }
  private var _onIncrease: VoidCallback?

  /// The handler for `SemanticsAction.decrease`.
  ///
  /// **Dart Source:** `semantics.dart:4865-4870`
  /// **Original:** `VoidCallback? get onDecrease => _onDecrease;`
  public var onDecrease: VoidCallback? {
    get { _onDecrease }
    set {
      _addArgumentlessAction(.decrease, newValue!)
      _onDecrease = newValue
    }
  }
  private var _onDecrease: VoidCallback?

  /// The handler for `SemanticsAction.copy`.
  ///
  /// **Dart Source:** `semantics.dart:4878-4883`
  /// **Original:** `VoidCallback? get onCopy => _onCopy;`
  public var onCopy: VoidCallback? {
    get { _onCopy }
    set {
      _addArgumentlessAction(.copy, newValue!)
      _onCopy = newValue
    }
  }
  private var _onCopy: VoidCallback?

  /// The handler for `SemanticsAction.cut`.
  ///
  /// **Dart Source:** `semantics.dart:4891-4896`
  /// **Original:** `VoidCallback? get onCut => _onCut;`
  public var onCut: VoidCallback? {
    get { _onCut }
    set {
      _addArgumentlessAction(.cut, newValue!)
      _onCut = newValue
    }
  }
  private var _onCut: VoidCallback?

  /// The handler for `SemanticsAction.paste`.
  ///
  /// **Dart Source:** `semantics.dart:4905-4910`
  /// **Original:** `VoidCallback? get onPaste => _onPaste;`
  public var onPaste: VoidCallback? {
    get { _onPaste }
    set {
      _addArgumentlessAction(.paste, newValue!)
      _onPaste = newValue
    }
  }
  private var _onPaste: VoidCallback?

  /// The handler for `SemanticsAction.showOnScreen`.
  ///
  /// **Dart Source:** `semantics.dart:4921-4926`
  /// **Original:** `VoidCallback? get onShowOnScreen => _onShowOnScreen;`
  public var onShowOnScreen: VoidCallback? {
    get { _onShowOnScreen }
    set {
      _addArgumentlessAction(.showOnScreen, newValue!)
      _onShowOnScreen = newValue
    }
  }
  private var _onShowOnScreen: VoidCallback?

  /// The handler for `SemanticsAction.moveCursorForwardByCharacter`.
  ///
  /// **Dart Source:** `semantics.dart:4935-4944`
  /// **Original:** `MoveCursorHandler? get onMoveCursorForwardByCharacter => ...;`
  public var onMoveCursorForwardByCharacter: MoveCursorHandler? {
    get { _onMoveCursorForwardByCharacter }
    set {
      assert(newValue != nil)
      let handler = newValue!
      _addAction(.moveCursorForwardByCharacter) { args in
        let extendSelection = args! as! Bool
        handler(extendSelection)
      }
      _onMoveCursorForwardByCharacter = newValue
    }
  }
  private var _onMoveCursorForwardByCharacter: MoveCursorHandler?

  /// The handler for `SemanticsAction.moveCursorBackwardByCharacter`.
  ///
  /// **Dart Source:** `semantics.dart:4953-4962`
  /// **Original:** `MoveCursorHandler? get onMoveCursorBackwardByCharacter => ...;`
  public var onMoveCursorBackwardByCharacter: MoveCursorHandler? {
    get { _onMoveCursorBackwardByCharacter }
    set {
      assert(newValue != nil)
      let handler = newValue!
      _addAction(.moveCursorBackwardByCharacter) { args in
        let extendSelection = args! as! Bool
        handler(extendSelection)
      }
      _onMoveCursorBackwardByCharacter = newValue
    }
  }
  private var _onMoveCursorBackwardByCharacter: MoveCursorHandler?

  /// The handler for `SemanticsAction.moveCursorForwardByWord`.
  ///
  /// **Dart Source:** `semantics.dart:4971-4980`
  /// **Original:** `MoveCursorHandler? get onMoveCursorForwardByWord => ...;`
  ///
  /// NOTE: In the original Dart code, the setter mistakenly assigns to
  /// `_onMoveCursorForwardByCharacter`. We replicate that bug for fidelity.
  public var onMoveCursorForwardByWord: MoveCursorHandler? {
    get { _onMoveCursorForwardByWord }
    set {
      assert(newValue != nil)
      let handler = newValue!
      _addAction(.moveCursorForwardByWord) { args in
        let extendSelection = args! as! Bool
        handler(extendSelection)
      }
      // DIFFERENCE FROM DART: Assigns to _onMoveCursorForwardByWord instead of
      // _onMoveCursorForwardByCharacter. The Dart code has a bug where it assigns
      // to the wrong field (line 4979). We fix the bug in the Swift migration.
      _onMoveCursorForwardByWord = newValue
    }
  }
  private var _onMoveCursorForwardByWord: MoveCursorHandler?

  /// The handler for `SemanticsAction.moveCursorBackwardByWord`.
  ///
  /// **Dart Source:** `semantics.dart:4989-4998`
  /// **Original:** `MoveCursorHandler? get onMoveCursorBackwardByWord => ...;`
  ///
  /// NOTE: In the original Dart code, the setter mistakenly assigns to
  /// `_onMoveCursorBackwardByCharacter`. We replicate that bug for fidelity.
  public var onMoveCursorBackwardByWord: MoveCursorHandler? {
    get { _onMoveCursorBackwardByWord }
    set {
      assert(newValue != nil)
      let handler = newValue!
      _addAction(.moveCursorBackwardByWord) { args in
        let extendSelection = args! as! Bool
        handler(extendSelection)
      }
      // DIFFERENCE FROM DART: Assigns to _onMoveCursorBackwardByWord instead of
      // _onMoveCursorBackwardByCharacter. The Dart code has a bug where it assigns
      // to the wrong field (line 4997). We fix the bug in the Swift migration.
      _onMoveCursorBackwardByWord = newValue
    }
  }
  private var _onMoveCursorBackwardByWord: MoveCursorHandler?

  /// The handler for `SemanticsAction.setSelection`.
  ///
  /// **Dart Source:** `semantics.dart:5007-5018`
  /// **Original:** `SetSelectionHandler? get onSetSelection => _onSetSelection;`
  ///
  /// DIFFERENCE FROM DART: Unpacks `[String: Int]` instead of `Map<dynamic, dynamic>`.
  /// REASON: Swift's type system requires explicit casting; the handler receives
  /// a dictionary with "base" and "extent" keys.
  public var onSetSelection: SetSelectionHandler? {
    get { _onSetSelection }
    set {
      assert(newValue != nil)
      let handler = newValue!
      _addAction(.setSelection) { args in
        assert(args != nil)
        let selection = args! as! [String: Int]
        assert(selection["base"] != nil && selection["extent"] != nil)
        handler(TextSelection(baseOffset: selection["base"]!, extentOffset: selection["extent"]!))
      }
      _onSetSelection = newValue
    }
  }
  private var _onSetSelection: SetSelectionHandler?

  /// The handler for `SemanticsAction.setText`.
  ///
  /// **Dart Source:** `semantics.dart:5027-5037`
  /// **Original:** `SetTextHandler? get onSetText => _onSetText;`
  public var onSetText: SetTextHandler? {
    get { _onSetText }
    set {
      assert(newValue != nil)
      let handler = newValue!
      _addAction(.setText) { args in
        assert(args != nil && args is String)
        let text = args! as! String
        handler(text)
      }
      _onSetText = newValue
    }
  }
  private var _onSetText: SetTextHandler?

  /// The handler for `SemanticsAction.didGainAccessibilityFocus`.
  ///
  /// **Dart Source:** `semantics.dart:5056-5061`
  /// **Original:** `VoidCallback? get onDidGainAccessibilityFocus => ...;`
  public var onDidGainAccessibilityFocus: VoidCallback? {
    get { _onDidGainAccessibilityFocus }
    set {
      _addArgumentlessAction(.didGainAccessibilityFocus, newValue!)
      _onDidGainAccessibilityFocus = newValue
    }
  }
  private var _onDidGainAccessibilityFocus: VoidCallback?

  /// The handler for `SemanticsAction.didLoseAccessibilityFocus`.
  ///
  /// **Dart Source:** `semantics.dart:5080-5085`
  /// **Original:** `VoidCallback? get onDidLoseAccessibilityFocus => ...;`
  public var onDidLoseAccessibilityFocus: VoidCallback? {
    get { _onDidLoseAccessibilityFocus }
    set {
      _addArgumentlessAction(.didLoseAccessibilityFocus, newValue!)
      _onDidLoseAccessibilityFocus = newValue
    }
  }
  private var _onDidLoseAccessibilityFocus: VoidCallback?

  /// The handler for `SemanticsAction.focus`.
  ///
  /// **Dart Source:** `semantics.dart:5088-5093`
  /// **Original:** `VoidCallback? get onFocus => _onFocus;`
  public var onFocus: VoidCallback? {
    get { _onFocus }
    set {
      _addArgumentlessAction(.focus, newValue!)
      _onFocus = newValue
    }
  }
  private var _onFocus: VoidCallback?

  /// The handler for `SemanticsAction.expand`.
  ///
  /// **Dart Source:** `semantics.dart:5098-5104`
  /// **Original:** `VoidCallback? get onExpand => _onExpand;`
  public var onExpand: VoidCallback? {
    get { _onExpand }
    set {
      assert(newValue != nil)
      _addArgumentlessAction(.expand, newValue!)
      _onExpand = newValue
    }
  }
  private var _onExpand: VoidCallback?

  /// The handler for `SemanticsAction.collapse`.
  ///
  /// **Dart Source:** `semantics.dart:5109-5115`
  /// **Original:** `VoidCallback? get onCollapse => _onCollapse;`
  public var onCollapse: VoidCallback? {
    get { _onCollapse }
    set {
      assert(newValue != nil)
      _addArgumentlessAction(.collapse, newValue!)
      _onCollapse = newValue
    }
  }
  private var _onCollapse: VoidCallback?

  // MARK: - Child Configurations Delegate
  /// **Dart Source:** `semantics.dart:5117-5136`

  /// A delegate that decides how to handle `SemanticsConfiguration`s produced
  /// in the widget subtree.
  ///
  /// **Dart Source:** `semantics.dart:5128-5136`
  /// **Original:** `ChildSemanticsConfigurationsDelegate? get childConfigurationsDelegate => ...;`
  public var childConfigurationsDelegate: ChildSemanticsConfigurationsDelegate? {
    get { _childConfigurationsDelegate }
    set {
      assert(newValue != nil)
      _childConfigurationsDelegate = newValue
      // Setting the childConfigsDelegate does not annotate any meaningful
      // semantics information of the config.
    }
  }
  private var _childConfigurationsDelegate: ChildSemanticsConfigurationsDelegate?

  // MARK: - getActionHandler

  /// Returns the action handler registered for `action` or nil if none was
  /// registered.
  ///
  /// **Dart Source:** `semantics.dart:5140`
  /// **Original:** `SemanticsActionHandler? getActionHandler(SemanticsAction action) => _actions[action];`
  public func getActionHandler(_ action: SemanticsAction) -> SemanticsActionHandler? {
    _actions[action]
  }

  // MARK: - Sort Key and Index
  /// **Dart Source:** `semantics.dart:5142-5172`

  /// Determines the position of this node among its siblings in the traversal
  /// sort order.
  ///
  /// **Dart Source:** `semantics.dart:5153-5159`
  /// **Original:** `SemanticsSortKey? get sortKey => _sortKey;`
  public var sortKey: SemanticsSortKey? {
    get { _sortKey }
    set {
      assert(newValue != nil)
      _sortKey = newValue
      _hasBeenAnnotated = true
    }
  }
  internal var _sortKey: SemanticsSortKey?

  /// The index of this node within the parent's list of semantic children.
  ///
  /// **Dart Source:** `semantics.dart:5167-5172`
  /// **Original:** `int? get indexInParent => _indexInParent;`
  public var indexInParent: Int? {
    get { _indexInParent }
    set {
      _indexInParent = newValue
      _hasBeenAnnotated = true
    }
  }
  private var _indexInParent: Int?

  // MARK: - Scroll Properties
  /// **Dart Source:** `semantics.dart:5174-5246`

  /// The total number of scrollable children that contribute to semantics.
  ///
  /// **Dart Source:** `semantics.dart:5178-5186`
  /// **Original:** `int? get scrollChildCount => _scrollChildCount;`
  public var scrollChildCount: Int? {
    get { _scrollChildCount }
    set {
      if newValue == scrollChildCount { return }
      _scrollChildCount = newValue
      _hasBeenAnnotated = true
    }
  }
  private var _scrollChildCount: Int?

  /// The index of the first visible scrollable child that contributes to
  /// semantics.
  ///
  /// **Dart Source:** `semantics.dart:5190-5198`
  /// **Original:** `int? get scrollIndex => _scrollIndex;`
  public var scrollIndex: Int? {
    get { _scrollIndex }
    set {
      if newValue == scrollIndex { return }
      _scrollIndex = newValue
      _hasBeenAnnotated = true
    }
  }
  private var _scrollIndex: Int?

  /// The id of the platform view, whose semantics nodes will be added as
  /// children to this node.
  ///
  /// **Dart Source:** `semantics.dart:5202-5210`
  /// **Original:** `int? get platformViewId => _platformViewId;`
  public var platformViewId: Int? {
    get { _platformViewId }
    set {
      if newValue == platformViewId { return }
      _platformViewId = newValue
      _hasBeenAnnotated = true
    }
  }
  internal var _platformViewId: Int?

  /// The maximum number of characters that can be entered into an editable
  /// text field.
  ///
  /// **Dart Source:** `semantics.dart:5220-5228`
  /// **Original:** `int? get maxValueLength => _maxValueLength;`
  public var maxValueLength: Int? {
    get { _maxValueLength }
    set {
      if newValue == maxValueLength { return }
      _maxValueLength = newValue
      _hasBeenAnnotated = true
    }
  }
  internal var _maxValueLength: Int?

  /// The current number of characters that have been entered into an editable
  /// text field.
  ///
  /// **Dart Source:** `semantics.dart:5238-5246`
  /// **Original:** `int? get currentValueLength => _currentValueLength;`
  public var currentValueLength: Int? {
    get { _currentValueLength }
    set {
      if newValue == currentValueLength { return }
      _currentValueLength = newValue
      _hasBeenAnnotated = true
    }
  }
  internal var _currentValueLength: Int?

  // MARK: - Merging Semantics
  /// **Dart Source:** `semantics.dart:5248-5262`

  /// Whether the semantic information provided by the owning `RenderObject` and
  /// all of its descendants should be treated as one logical entity.
  ///
  /// **Dart Source:** `semantics.dart:5256-5262`
  /// **Original:** `bool get isMergingSemanticsOfDescendants => ...;`
  public var isMergingSemanticsOfDescendants: Bool {
    get { _isMergingSemanticsOfDescendants }
    set {
      assert(isSemanticBoundary)
      _isMergingSemanticsOfDescendants = newValue
      _hasBeenAnnotated = true
    }
  }
  private var _isMergingSemanticsOfDescendants: Bool = false

  // MARK: - Custom Semantics Actions
  /// **Dart Source:** `semantics.dart:5264-5289`

  /// The handlers for each supported `CustomSemanticsAction`.
  ///
  /// **Dart Source:** `semantics.dart:5270-5278`
  /// **Original:** `Map<CustomSemanticsAction, VoidCallback> get customSemanticsActions => ...;`
  public var customSemanticsActions: [CustomSemanticsAction: VoidCallback] {
    get { _customSemanticsActions }
    set {
      _hasBeenAnnotated = true
      _actionsAsBits |= SemanticsAction.customAction.index
      _customSemanticsActions = newValue
      _actions[.customAction] = _onCustomSemanticsAction
    }
  }
  internal var _customSemanticsActions: [CustomSemanticsAction: VoidCallback] = [:]

  /// **Dart Source:** `semantics.dart:5280-5289`
  /// **Original:** `void _onCustomSemanticsAction(Object? args)`
  private func _onCustomSemanticsAction(_ args: Any?) {
    let action = CustomSemanticsAction.getAction(args! as! Int)
    guard let action = action else { return }
    let callback = _customSemanticsActions[action]
    if let callback = callback {
      callback()
    }
  }

  // MARK: - Identifier and Role
  /// **Dart Source:** `semantics.dart:5291-5305`

  /// A string identifier for this semantic node.
  ///
  /// **Dart Source:** `semantics.dart:5292-5297`
  /// **Original:** `String get identifier => _identifier;`
  public var identifier: String {
    get { _identifier }
    set {
      _identifier = newValue
      _hasBeenAnnotated = true
    }
  }
  private var _identifier: String = ""

  /// The semantic role of this node.
  ///
  /// **Dart Source:** `semantics.dart:5299-5305`
  /// **Original:** `SemanticsRole get role => _role;`
  public var role: SemanticsRole {
    get { _role }
    set {
      _role = newValue
      _hasBeenAnnotated = true
    }
  }
  internal var _role: SemanticsRole = .none

  /// Starling: the control kind a `Semantics` widget names ("checkbox",
  /// "radio", "switch", ...), which Dart's flags alone cannot say. Read by the
  /// agent endpoint; not part of Flutter's semantics tree.
  public var agentRole: String = "" {
    didSet { _hasBeenAnnotated = true }
  }

  // MARK: - Text Content Properties (AttributedString-backed)
  /// **Dart Source:** `semantics.dart:5307-5507`

  /// A textual description of the owning `RenderObject`.
  /// Setting this attribute will override the `attributedLabel`.
  ///
  /// **Dart Source:** `semantics.dart:5316-5320`
  /// **Original:** `String get label => _attributedLabel.string;`
  public var label: String {
    get { _attributedLabel.string }
    set {
      _attributedLabel = AttributedString(newValue)
      _hasBeenAnnotated = true
    }
  }

  /// A textual description of the owning `RenderObject` in `AttributedString`
  /// format.
  ///
  /// **Dart Source:** `semantics.dart:5336-5341`
  /// **Original:** `AttributedString get attributedLabel => _attributedLabel;`
  public var attributedLabel: AttributedString {
    get { _attributedLabel }
    set {
      _attributedLabel = newValue
      _hasBeenAnnotated = true
    }
  }
  internal var _attributedLabel: AttributedString = AttributedString("")

  /// A textual description for the current value of the owning `RenderObject`.
  /// Setting this attribute will override the `attributedValue`.
  ///
  /// **Dart Source:** `semantics.dart:5356-5360`
  /// **Original:** `String get value => _attributedValue.string;`
  public var value: String {
    get { _attributedValue.string }
    set {
      _attributedValue = AttributedString(newValue)
      _hasBeenAnnotated = true
    }
  }

  /// A textual description for the current value in `AttributedString` format.
  ///
  /// **Dart Source:** `semantics.dart:5380-5385`
  /// **Original:** `AttributedString get attributedValue => _attributedValue;`
  public var attributedValue: AttributedString {
    get { _attributedValue }
    set {
      _attributedValue = newValue
      _hasBeenAnnotated = true
    }
  }
  internal var _attributedValue: AttributedString = AttributedString("")

  /// The value that `value` will have after performing a
  /// `SemanticsAction.increase` action.
  ///
  /// **Dart Source:** `semantics.dart:5401-5405`
  /// **Original:** `String get increasedValue => _attributedIncreasedValue.string;`
  public var increasedValue: String {
    get { _attributedIncreasedValue.string }
    set {
      _attributedIncreasedValue = AttributedString(newValue)
      _hasBeenAnnotated = true
    }
  }

  /// The value that `value` will have after performing a
  /// `SemanticsAction.increase` action in `AttributedString` format.
  ///
  /// **Dart Source:** `semantics.dart:5419-5424`
  /// **Original:** `AttributedString get attributedIncreasedValue => _attributedIncreasedValue;`
  public var attributedIncreasedValue: AttributedString {
    get { _attributedIncreasedValue }
    set {
      _attributedIncreasedValue = newValue
      _hasBeenAnnotated = true
    }
  }
  internal var _attributedIncreasedValue: AttributedString = AttributedString("")

  /// The value that `value` will have after performing a
  /// `SemanticsAction.decrease` action.
  ///
  /// **Dart Source:** `semantics.dart:5438-5442`
  /// **Original:** `String get decreasedValue => _attributedDecreasedValue.string;`
  public var decreasedValue: String {
    get { _attributedDecreasedValue.string }
    set {
      _attributedDecreasedValue = AttributedString(newValue)
      _hasBeenAnnotated = true
    }
  }

  /// The value that `value` will have after performing a
  /// `SemanticsAction.decrease` action in `AttributedString` format.
  ///
  /// **Dart Source:** `semantics.dart:5456-5461`
  /// **Original:** `AttributedString get attributedDecreasedValue => _attributedDecreasedValue;`
  public var attributedDecreasedValue: AttributedString {
    get { _attributedDecreasedValue }
    set {
      _attributedDecreasedValue = newValue
      _hasBeenAnnotated = true
    }
  }
  internal var _attributedDecreasedValue: AttributedString = AttributedString("")

  /// A brief description of the result of performing an action on this node.
  /// Setting this attribute will override the `attributedHint`.
  ///
  /// **Dart Source:** `semantics.dart:5472-5476`
  /// **Original:** `String get hint => _attributedHint.string;`
  public var hint: String {
    get { _attributedHint.string }
    set {
      _attributedHint = AttributedString(newValue)
      _hasBeenAnnotated = true
    }
  }

  /// A brief description of the result of performing an action on this node in
  /// `AttributedString` format.
  ///
  /// **Dart Source:** `semantics.dart:5492-5497`
  /// **Original:** `AttributedString get attributedHint => _attributedHint;`
  public var attributedHint: AttributedString {
    get { _attributedHint }
    set {
      _attributedHint = newValue
      _hasBeenAnnotated = true
    }
  }
  internal var _attributedHint: AttributedString = AttributedString("")

  /// A textual description of the widget's tooltip.
  ///
  /// **Dart Source:** `semantics.dart:5502-5507`
  /// **Original:** `String get tooltip => _tooltip;`
  public var tooltip: String {
    get { _tooltip }
    set {
      _tooltip = newValue
      _hasBeenAnnotated = true
    }
  }
  internal var _tooltip: String = ""

  /// Provides hint values which override the default hints on supported
  /// platforms.
  ///
  /// **Dart Source:** `semantics.dart:5511-5519`
  /// **Original:** `SemanticsHintOverrides? get hintOverrides => _hintOverrides;`
  public var hintOverrides: SemanticsHintOverrides? {
    get { _hintOverrides }
    set {
      if newValue == nil { return }
      _hintOverrides = newValue
      _hasBeenAnnotated = true
    }
  }
  internal var _hintOverrides: SemanticsHintOverrides?

  // MARK: - Flags-Based Properties (Boolean)
  /// **Dart Source:** `semantics.dart:5521-5871`

  /// Whether the semantics node is the root of a subtree for which values
  /// should be announced.
  ///
  /// **Dart Source:** `semantics.dart:5527-5531`
  /// **Original:** `bool get scopesRoute => _flags.scopesRoute;`
  public var scopesRoute: Bool {
    get { _flags.scopesRoute }
    set {
      _flags = _flags.copyWith(scopesRoute: newValue)
      _hasBeenAnnotated = true
    }
  }

  /// Whether the semantics node contains the label of a route.
  ///
  /// **Dart Source:** `semantics.dart:5538-5542`
  /// **Original:** `bool get namesRoute => _flags.namesRoute;`
  public var namesRoute: Bool {
    get { _flags.namesRoute }
    set {
      _flags = _flags.copyWith(namesRoute: newValue)
      _hasBeenAnnotated = true
    }
  }

  /// Whether the semantics node represents an image.
  ///
  /// **Dart Source:** `semantics.dart:5545-5549`
  /// **Original:** `bool get isImage => _flags.isImage;`
  public var isImage: Bool {
    get { _flags.isImage }
    set {
      _flags = _flags.copyWith(isImage: newValue)
      _hasBeenAnnotated = true
    }
  }

  /// Whether the semantics node is a live region.
  ///
  /// **Dart Source:** `semantics.dart:5567-5571`
  /// **Original:** `bool get liveRegion => _flags.isLiveRegion;`
  public var liveRegion: Bool {
    get { _flags.isLiveRegion }
    set {
      _flags = _flags.copyWith(isLiveRegion: newValue)
      _hasBeenAnnotated = true
    }
  }

  /// The reading direction for the text in `label`, `value`, `hint`,
  /// `increasedValue`, and `decreasedValue`.
  ///
  /// **Dart Source:** `semantics.dart:5575-5580`
  /// **Original:** `TextDirection? get textDirection => _textDirection;`
  public var textDirection: TextDirection? {
    get { _textDirection }
    set {
      _textDirection = newValue
      _hasBeenAnnotated = true
    }
  }
  internal var _textDirection: TextDirection?

  /// Whether the owning `RenderObject` is selected (true) or not (false).
  ///
  /// **Dart Source:** `semantics.dart:5588-5592`
  /// **Original:** `bool get isSelected => _flags.isSelected == Tristate.isTrue;`
  public var isSelected: Bool {
    get { _flags.isSelected == .isTrue }
    set {
      _flags = _flags.copyWith(isSelected: tristateFromBoolOrNull(newValue))
      _hasBeenAnnotated = true
    }
  }

  /// If this node has Boolean state that can be controlled by the user, whether
  /// that state is expanded or collapsed.
  ///
  /// **Dart Source:** `semantics.dart:5602-5606`
  /// **Original:** `bool? get isExpanded => _flags.isExpanded.toBoolOrNull();`
  public var isExpanded: Bool? {
    get { _flags.isExpanded.toBoolOrNull() }
    set {
      _flags = _flags.copyWith(isExpanded: tristateFromBoolOrNull(newValue))
      _hasBeenAnnotated = true
    }
  }

  /// Whether the owning `RenderObject` is currently enabled.
  ///
  /// **Dart Source:** `semantics.dart:5623-5627`
  /// **Original:** `bool? get isEnabled => _flags.isEnabled.toBoolOrNull();`
  public var isEnabled: Bool? {
    get { _flags.isEnabled.toBoolOrNull() }
    set {
      _flags = _flags.copyWith(isEnabled: tristateFromBoolOrNull(newValue))
      _hasBeenAnnotated = true
    }
  }

  /// If this node has Boolean state that can be controlled by the user, whether
  /// that state is checked or unchecked.
  ///
  /// **Dart Source:** `semantics.dart:5638-5645`
  /// **Original:** `bool? get isChecked => _flags.isChecked == CheckedState.none ? null : ...;`
  public var isChecked: Bool? {
    get { _flags.isChecked == .none ? nil : _flags.isChecked == .isTrue }
    set {
      if let newValue = newValue {
        _flags = _flags.copyWith(isChecked: newValue ? .isTrue : .isFalse)
      }
      _hasBeenAnnotated = true
    }
  }

  /// If this node has tristate that can be controlled by the user, whether
  /// that state is in its mixed state.
  ///
  /// **Dart Source:** `semantics.dart:5655-5662`
  /// **Original:** `bool? get isCheckStateMixed => ...;`
  public var isCheckStateMixed: Bool? {
    get { _flags.isChecked == .none ? nil : _flags.isChecked == .mixed }
    set {
      if newValue ?? false {
        _flags = _flags.copyWith(isChecked: .mixed)
      }
      _hasBeenAnnotated = true
    }
  }

  /// If this node has Boolean state that can be controlled by the user, whether
  /// that state is on or off.
  ///
  /// **Dart Source:** `semantics.dart:5672-5676`
  /// **Original:** `bool? get isToggled => _flags.isToggled.toBoolOrNull();`
  public var isToggled: Bool? {
    get { _flags.isToggled.toBoolOrNull() }
    set {
      _flags = _flags.copyWith(isToggled: tristateFromBoolOrNull(newValue))
      _hasBeenAnnotated = true
    }
  }

  /// Whether the owning RenderObject corresponds to UI that allows the user to
  /// pick one of several mutually exclusive options.
  ///
  /// **Dart Source:** `semantics.dart:5683-5687`
  /// **Original:** `bool get isInMutuallyExclusiveGroup => _flags.isInMutuallyExclusiveGroup;`
  public var isInMutuallyExclusiveGroup: Bool {
    get { _flags.isInMutuallyExclusiveGroup }
    set {
      _flags = _flags.copyWith(isInMutuallyExclusiveGroup: newValue)
      _hasBeenAnnotated = true
    }
  }

  // NOTE: Deprecated `isFocusable` (lines 5690-5712) is intentionally skipped.

  /// Whether the owning `RenderObject` currently holds the input focus.
  ///
  /// **Dart Source:** `semantics.dart:5715-5719`
  /// **Original:** `bool? get isFocused => _flags.isFocused.toBoolOrNull();`
  public var isFocused: Bool? {
    get { _flags.isFocused.toBoolOrNull() }
    set {
      _flags = _flags.copyWith(isFocused: tristateFromBoolOrNull(newValue))
      _hasBeenAnnotated = true
    }
  }

  /// Whether the owning `RenderObject` is a button (true) or not (false).
  ///
  /// **Dart Source:** `semantics.dart:5722-5726`
  /// **Original:** `bool get isButton => _flags.isButton;`
  public var isButton: Bool {
    get { _flags.isButton }
    set {
      _flags = _flags.copyWith(isButton: newValue)
      _hasBeenAnnotated = true
    }
  }

  /// Whether the owning `RenderObject` is a link (true) or not (false).
  ///
  /// **Dart Source:** `semantics.dart:5729-5733`
  /// **Original:** `bool get isLink => _flags.isLink;`
  public var isLink: Bool {
    get { _flags.isLink }
    set {
      _flags = _flags.copyWith(isLink: newValue)
      _hasBeenAnnotated = true
    }
  }

  /// The URL that the owning `RenderObject` links to.
  ///
  /// **Dart Source:** `semantics.dart:5736-5745`
  /// **Original:** `Uri? get linkUrl => _linkUrl;`
  ///
  /// DIFFERENCE FROM DART: Uses `URL` (Foundation) instead of Dart's `Uri`.
  /// REASON: `URL` is Swift's standard type for URIs.
  public var linkUrl: URL? {
    get { _linkUrl }
    set {
      if newValue == _linkUrl { return }
      _linkUrl = newValue
      _hasBeenAnnotated = true
    }
  }
  internal var _linkUrl: URL?

  /// Whether the owning `RenderObject` is a header (true) or not (false).
  ///
  /// **Dart Source:** `semantics.dart:5748-5752`
  /// **Original:** `bool get isHeader => _flags.isHeader;`
  public var isHeader: Bool {
    get { _flags.isHeader }
    set {
      _flags = _flags.copyWith(isHeader: newValue)
      _hasBeenAnnotated = true
    }
  }

  /// Indicates the heading level in the document structure.
  ///
  /// **Dart Source:** `semantics.dart:5757-5767`
  /// **Original:** `int get headingLevel => _headingLevel;`
  public var headingLevel: Int {
    get { _headingLevel }
    set {
      assert(newValue >= 0 && newValue <= 6)
      if newValue == headingLevel { return }
      _headingLevel = newValue
      _hasBeenAnnotated = true
    }
  }
  internal var _headingLevel: Int = 0

  /// Whether the owning `RenderObject` is a slider (true) or not (false).
  ///
  /// **Dart Source:** `semantics.dart:5770-5774`
  /// **Original:** `bool get isSlider => _flags.isSlider;`
  public var isSlider: Bool {
    get { _flags.isSlider }
    set {
      _flags = _flags.copyWith(isSlider: newValue)
      _hasBeenAnnotated = true
    }
  }

  /// Whether the owning `RenderObject` is a keyboard key (true) or not (false).
  ///
  /// **Dart Source:** `semantics.dart:5778-5782`
  /// **Original:** `bool get isKeyboardKey => _flags.isKeyboardKey;`
  public var isKeyboardKey: Bool {
    get { _flags.isKeyboardKey }
    set {
      _flags = _flags.copyWith(isKeyboardKey: newValue)
      _hasBeenAnnotated = true
    }
  }

  /// Whether the owning `RenderObject` is considered hidden.
  ///
  /// **Dart Source:** `semantics.dart:5800-5804`
  /// **Original:** `bool get isHidden => _flags.isHidden;`
  public var isHidden: Bool {
    get { _flags.isHidden }
    set {
      _flags = _flags.copyWith(isHidden: newValue)
      _hasBeenAnnotated = true
    }
  }

  /// Whether the owning `RenderObject` is a text field.
  ///
  /// **Dart Source:** `semantics.dart:5807-5811`
  /// **Original:** `bool get isTextField => _flags.isTextField;`
  public var isTextField: Bool {
    get { _flags.isTextField }
    set {
      _flags = _flags.copyWith(isTextField: newValue)
      _hasBeenAnnotated = true
    }
  }

  /// Whether the owning `RenderObject` is read only.
  ///
  /// **Dart Source:** `semantics.dart:5816-5820`
  /// **Original:** `bool get isReadOnly => _flags.isReadOnly;`
  public var isReadOnly: Bool {
    get { _flags.isReadOnly }
    set {
      _flags = _flags.copyWith(isReadOnly: newValue)
      _hasBeenAnnotated = true
    }
  }

  /// Whether `value` should be obscured.
  ///
  /// **Dart Source:** `semantics.dart:5827-5831`
  /// **Original:** `bool get isObscured => _flags.isObscured;`
  public var isObscured: Bool {
    get { _flags.isObscured }
    set {
      _flags = _flags.copyWith(isObscured: newValue)
      _hasBeenAnnotated = true
    }
  }

  /// Whether the text field is multiline.
  ///
  /// **Dart Source:** `semantics.dart:5837-5841`
  /// **Original:** `bool get isMultiline => _flags.isMultiline;`
  public var isMultiline: Bool {
    get { _flags.isMultiline }
    set {
      _flags = _flags.copyWith(isMultiline: newValue)
      _hasBeenAnnotated = true
    }
  }

  /// Whether the semantics node has a required state.
  ///
  /// **Dart Source:** `semantics.dart:5854-5858`
  /// **Original:** `bool? get isRequired => _flags.isRequired.toBoolOrNull();`
  public var isRequired: Bool? {
    get { _flags.isRequired.toBoolOrNull() }
    set {
      _flags = _flags.copyWith(isRequired: tristateFromBoolOrNull(newValue))
      _hasBeenAnnotated = true
    }
  }

  /// Whether the platform can scroll the semantics node when the user attempts
  /// to move focus to an offscreen child.
  ///
  /// **Dart Source:** `semantics.dart:5867-5871`
  /// **Original:** `bool get hasImplicitScrolling => _flags.hasImplicitScrolling;`
  public var hasImplicitScrolling: Bool {
    get { _flags.hasImplicitScrolling }
    set {
      _flags = _flags.copyWith(hasImplicitScrolling: newValue)
      _hasBeenAnnotated = true
    }
  }

  // MARK: - Text Selection and Scroll
  /// **Dart Source:** `semantics.dart:5873-5940`

  /// The currently selected text (or the position of the cursor) within
  /// `value` if this node represents a text field.
  ///
  /// **Dart Source:** `semantics.dart:5875-5881`
  /// **Original:** `TextSelection? get textSelection => _textSelection;`
  public var textSelection: TextSelection? {
    get { _textSelection }
    set {
      assert(newValue != nil)
      _textSelection = newValue
      _hasBeenAnnotated = true
    }
  }
  internal var _textSelection: TextSelection?

  /// Indicates the current scrolling position in logical pixels if the node is
  /// scrollable.
  ///
  /// **Dart Source:** `semantics.dart:5893-5899`
  /// **Original:** `double? get scrollPosition => _scrollPosition;`
  public var scrollPosition: Double? {
    get { _scrollPosition }
    set {
      assert(newValue != nil)
      _scrollPosition = newValue
      _hasBeenAnnotated = true
    }
  }
  internal var _scrollPosition: Double?

  /// Indicates the maximum in-range value for `scrollPosition` if the node is
  /// scrollable.
  ///
  /// **Dart Source:** `semantics.dart:5909-5915`
  /// **Original:** `double? get scrollExtentMax => _scrollExtentMax;`
  public var scrollExtentMax: Double? {
    get { _scrollExtentMax }
    set {
      assert(newValue != nil)
      _scrollExtentMax = newValue
      _hasBeenAnnotated = true
    }
  }
  internal var _scrollExtentMax: Double?

  /// Indicates the minimum in-range value for `scrollPosition` if the node is
  /// scrollable.
  ///
  /// **Dart Source:** `semantics.dart:5925-5931`
  /// **Original:** `double? get scrollExtentMin => _scrollExtentMin;`
  public var scrollExtentMin: Double? {
    get { _scrollExtentMin }
    set {
      assert(newValue != nil)
      _scrollExtentMin = newValue
      _hasBeenAnnotated = true
    }
  }
  internal var _scrollExtentMin: Double?

  // MARK: - Controls, Validation, Input Type
  /// **Dart Source:** `semantics.dart:5933-5956`

  /// The `SemanticsNode.identifier`s of widgets controlled by this node.
  ///
  /// **Dart Source:** `semantics.dart:5934-5940`
  /// **Original:** `Set<String>? get controlsNodes => _controlsNodes;`
  public var controlsNodes: Set<String>? {
    get { _controlsNodes }
    set {
      assert(newValue != nil)
      _controlsNodes = newValue
      _hasBeenAnnotated = true
    }
  }
  internal var _controlsNodes: Set<String>?

  /// The validation result for the semantics node.
  ///
  /// **Dart Source:** `semantics.dart:5943-5948`
  /// **Original:** `SemanticsValidationResult get validationResult => _validationResult;`
  public var validationResult: SemanticsValidationResult {
    get { _validationResult }
    set {
      _validationResult = newValue
      _hasBeenAnnotated = true
    }
  }
  internal var _validationResult: SemanticsValidationResult = .none

  /// The input type for the semantics node.
  ///
  /// **Dart Source:** `semantics.dart:5951-5956`
  /// **Original:** `SemanticsInputType get inputType => _inputType;`
  public var inputType: SemanticsInputType {
    get { _inputType }
    set {
      _inputType = newValue
      _hasBeenAnnotated = true
    }
  }
  internal var _inputType: SemanticsInputType = .none

  // MARK: - Tags
  /// **Dart Source:** `semantics.dart:5958-5993`

  /// The set of tags that this configuration wants to add to all child
  /// `SemanticsNode`s.
  ///
  /// **Dart Source:** `semantics.dart:5967`
  /// **Original:** `Iterable<SemanticsTag>? get tagsForChildren => _tagsForChildren;`
  ///
  /// DIFFERENCE FROM DART: Returns `Set<SemanticsTag>?` instead of `Iterable<SemanticsTag>?`.
  /// REASON: The backing store is a `Set`; returning it directly avoids unnecessary type erasure.
  public var tagsForChildren: Set<SemanticsTag>? { _tagsForChildren }

  /// Whether this configuration will tag the child semantics nodes with a
  /// given `SemanticsTag`.
  ///
  /// **Dart Source:** `semantics.dart:5971`
  /// **Original:** `bool tagsChildrenWith(SemanticsTag tag) => _tagsForChildren?.contains(tag) ?? false;`
  public func tagsChildrenWith(_ tag: SemanticsTag) -> Bool {
    _tagsForChildren?.contains(tag) ?? false
  }

  internal var _tagsForChildren: Set<SemanticsTag>?

  /// Specifies a `SemanticsTag` that this configuration wants to apply to all
  /// child `SemanticsNode`s.
  ///
  /// **Dart Source:** `semantics.dart:5990-5993`
  /// **Original:** `void addTagForChildren(SemanticsTag tag) { ... }`
  public func addTagForChildren(_ tag: SemanticsTag) {
    if _tagsForChildren == nil {
      _tagsForChildren = Set<SemanticsTag>()
    }
    _tagsForChildren!.insert(tag)
  }

  // MARK: - Internal Flags Management
  /// **Dart Source:** `semantics.dart:5995-6014`

  /// **Dart Source:** `semantics.dart:5997`
  /// **Original:** `SemanticsFlags _flags = SemanticsFlags.none;`
  internal var _flags: SemanticsFlags = .none

  /// Whether the node has an explicit role (either set directly or inferred
  /// from flags).
  ///
  /// **Dart Source:** `semantics.dart:5999-6014`
  /// **Original:** `bool get _hasExplicitRole { ... }`
  private var _hasExplicitRole: Bool {
    if _role != .none {
      return true
    }
    if _flags.isTextField
      || (_flags.isHeader && kIsWeb)
      || _flags.isSlider
      || _flags.isLink
      || _flags.scopesRoute
      || _flags.isImage
      || _flags.isKeyboardKey
    {
      return true
    }
    return false
  }

  // MARK: - isCompatibleWith
  /// **Dart Source:** `semantics.dart:6016-6049`

  /// Whether this configuration is compatible with the provided `other`
  /// configuration.
  ///
  /// Two configurations are said to be compatible if they can be added to the
  /// same `SemanticsNode` without losing any semantics information.
  ///
  /// **Dart Source:** `semantics.dart:6023-6049`
  /// **Original:** `bool isCompatibleWith(SemanticsConfiguration? other) { ... }`
  public func isCompatibleWith(_ other: SemanticsConfiguration?) -> Bool {
    guard let other = other else { return true }
    if !other.hasBeenAnnotated || !hasBeenAnnotated {
      return true
    }
    if _actionsAsBits & other._actionsAsBits != 0 {
      return false
    }
    if _flags.hasRepeatedFlags(other._flags) {
      return false
    }
    if _platformViewId != nil && other._platformViewId != nil {
      return false
    }
    if _maxValueLength != nil && other._maxValueLength != nil {
      return false
    }
    if _currentValueLength != nil && other._currentValueLength != nil {
      return false
    }
    if !_attributedValue.string.isEmpty && !other._attributedValue.string.isEmpty {
      return false
    }
    if _hasExplicitRole && other._hasExplicitRole {
      return false
    }
    return true
  }

  // MARK: - absorb
  /// **Dart Source:** `semantics.dart:6051-6150`

  /// Absorb the semantic information from `child` into this configuration.
  ///
  /// This adds the semantic information of both configurations and saves the
  /// result in this configuration.
  ///
  /// Only configurations that have `explicitChildNodes` set to false can
  /// absorb other configurations and it is recommended to only absorb compatible
  /// configurations as determined by `isCompatibleWith`.
  ///
  /// **Dart Source:** `semantics.dart:6062-6150`
  /// **Original:** `void absorb(SemanticsConfiguration child) { ... }`
  public func absorb(_ child: SemanticsConfiguration) {
    assert(!explicitChildNodes)

    if !child.hasBeenAnnotated {
      return
    }

    if child.isBlockingUserActions {
      for (key, value) in child._actions {
        if _kUnblockedUserActions & key.index > 0 {
          _actions[key] = value
        }
      }
    } else {
      for (key, value) in child._actions {
        _actions[key] = value
      }
    }
    _actionsAsBits |= child._effectiveActionsAsBits
    for (key, value) in child._customSemanticsActions {
      _customSemanticsActions[key] = value
    }
    _flags = _flags.merge(child._flags)
    _linkUrl = _linkUrl ?? child._linkUrl
    _textSelection = _textSelection ?? child._textSelection
    _scrollPosition = _scrollPosition ?? child._scrollPosition
    _scrollExtentMax = _scrollExtentMax ?? child._scrollExtentMax
    _scrollExtentMin = _scrollExtentMin ?? child._scrollExtentMin
    _hintOverrides = _hintOverrides ?? child._hintOverrides
    _indexInParent = _indexInParent ?? child.indexInParent
    _scrollIndex = _scrollIndex ?? child._scrollIndex
    _scrollChildCount = _scrollChildCount ?? child._scrollChildCount
    _platformViewId = _platformViewId ?? child._platformViewId
    _maxValueLength = _maxValueLength ?? child._maxValueLength
    _currentValueLength = _currentValueLength ?? child._currentValueLength

    _headingLevel = mergeHeadingLevels(
      sourceLevel: child._headingLevel,
      targetLevel: _headingLevel
    )

    _textDirection = _textDirection ?? child.textDirection
    _sortKey = _sortKey ?? child._sortKey
    if _identifier == "" {
      _identifier = child._identifier
    }
    _attributedLabel = concatAttributedString(
      thisAttributedString: _attributedLabel,
      otherAttributedString: child._attributedLabel,
      thisTextDirection: textDirection,
      otherTextDirection: child.textDirection
    )
    if _attributedValue.string == "" {
      _attributedValue = child._attributedValue
    }
    if _attributedIncreasedValue.string == "" {
      _attributedIncreasedValue = child._attributedIncreasedValue
    }
    if _attributedDecreasedValue.string == "" {
      _attributedDecreasedValue = child._attributedDecreasedValue
    }
    if _role == .none {
      _role = child._role
    }
    if _inputType == .none {
      _inputType = child._inputType
    }
    _attributedHint = concatAttributedString(
      thisAttributedString: _attributedHint,
      otherAttributedString: child._attributedHint,
      thisTextDirection: textDirection,
      otherTextDirection: child.textDirection
    )
    if _tooltip == "" {
      _tooltip = child._tooltip
    }

    if _controlsNodes == nil {
      _controlsNodes = child._controlsNodes
    } else if child._controlsNodes != nil {
      _controlsNodes = Set(_controlsNodes!).union(child._controlsNodes!)
    }

    if child._validationResult != _validationResult {
      if child._validationResult == .invalid {
        // Invalid result always takes precedence.
        _validationResult = .invalid
      } else if _validationResult == .none {
        _validationResult = child._validationResult
      }
    }

    _hasBeenAnnotated = _hasBeenAnnotated || child.hasBeenAnnotated
  }

  // MARK: - copy
  /// **Dart Source:** `semantics.dart:6152-6193`

  /// Returns an exact copy of this configuration.
  ///
  /// **Dart Source:** `semantics.dart:6153-6193`
  /// **Original:** `SemanticsConfiguration copy() { ... }`
  public func copy() -> SemanticsConfiguration {
    let result = SemanticsConfiguration()
    result._isSemanticBoundary = _isSemanticBoundary
    result.explicitChildNodes = explicitChildNodes
    result.isBlockingSemanticsOfPreviouslyPaintedNodes = isBlockingSemanticsOfPreviouslyPaintedNodes
    result._hasBeenAnnotated = _hasBeenAnnotated
    result._isMergingSemanticsOfDescendants = _isMergingSemanticsOfDescendants
    result._textDirection = _textDirection
    result._sortKey = _sortKey
    result._identifier = _identifier
    result._attributedLabel = _attributedLabel
    result._attributedIncreasedValue = _attributedIncreasedValue
    result._attributedValue = _attributedValue
    result._attributedDecreasedValue = _attributedDecreasedValue
    result._attributedHint = _attributedHint
    result._hintOverrides = _hintOverrides
    result._tooltip = _tooltip
    result._flags = _flags
    result._tagsForChildren = _tagsForChildren
    result._textSelection = _textSelection
    result._scrollPosition = _scrollPosition
    result._scrollExtentMax = _scrollExtentMax
    result._scrollExtentMin = _scrollExtentMin
    result._actionsAsBits = _actionsAsBits
    result._indexInParent = _indexInParent
    result._scrollIndex = _scrollIndex
    result._scrollChildCount = _scrollChildCount
    result._platformViewId = _platformViewId
    result._maxValueLength = _maxValueLength
    result._currentValueLength = _currentValueLength
    for (key, value) in _actions {
      result._actions[key] = value
    }
    for (key, value) in _customSemanticsActions {
      result._customSemanticsActions[key] = value
    }
    result.isBlockingUserActions = isBlockingUserActions
    result._headingLevel = _headingLevel
    result._linkUrl = _linkUrl
    result._role = _role
    result._controlsNodes = _controlsNodes
    result._validationResult = _validationResult
    result._inputType = _inputType
    return result
  }
}
