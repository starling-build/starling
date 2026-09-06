// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Ported from: fluent_ui/lib/src/controls/flyouts/tooltip.dart

import FlutterSwiftBridge
@preconcurrency import Foundation

// MARK: - DecoratedBox

/// A widget that paints a `Decoration` either before or after its child paints.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/basic.dart`
public class DecoratedBox: SingleChildRenderObjectWidget {

    /// The decoration to paint.
    public let decoration: any Decoration

    /// Whether to paint the decoration behind or in front of the child.
    public let position: DecorationPosition

    /// Creates a decorated box.
    public init(
        key: (any Key)? = nil,
        decoration: any Decoration,
        position: DecorationPosition = .background,
        child: Widget? = nil
    ) {
        self.decoration = decoration
        self.position = position
        super.init(key: key, child: child)
    }

    public override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        return RenderDecoratedBox(decoration: decoration, position: position)
    }

    public override func updateRenderObject(
        _ context: any BuildContext,
        renderObject: RenderObject
    ) {
        let ro = renderObject as! RenderDecoratedBox
        ro.decoration = decoration
        ro.position = position
    }
}

// MARK: - CustomSingleChildLayout

/// A widget that defers the layout of its single child to a delegate.
///
/// The delegate can determine the layout constraints for the child and can
/// decide where to position the child. The delegate can also determine the
/// size of the parent, but the size of the parent cannot depend on the size
/// of the child.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/basic.dart`
public class CustomSingleChildLayout: SingleChildRenderObjectWidget {

    /// The delegate that controls the layout of the child.
    public let delegate: SingleChildLayoutDelegate

    /// Creates a custom single child layout widget.
    public init(
        key: (any Key)? = nil,
        delegate: SingleChildLayoutDelegate,
        child: Widget? = nil
    ) {
        self.delegate = delegate
        super.init(key: key, child: child)
    }

    public override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        return RenderCustomSingleChildLayoutBox(delegate: delegate)
    }

    public override func updateRenderObject(
        _ context: any BuildContext,
        renderObject: RenderObject
    ) {
        let ro = renderObject as! RenderCustomSingleChildLayoutBox
        ro.delegate = delegate
    }
}

// MARK: - horizontalPositionDependentBox

/// Position a child box within a container box, either to the left or right of
/// a target point.
///
/// Similar to `positionDependentBox` but works in the horizontal direction.
///
/// **Dart Source:** `fluent_ui/lib/src/utils.dart`
public func horizontalPositionDependentBox(
    size: Size,
    childSize: Size,
    target: Offset,
    horizontalOffset: Double = 0.0,
    preferLeft: Bool = false,
    margin: Double = 10.0
) -> Offset {
    // HORIZONTAL DIRECTION
    let fitsRight = target.dx + horizontalOffset + childSize.width <= size.width - margin
    let fitsLeft = target.dx - horizontalOffset - childSize.width >= margin
    let tooltipLeft = fitsLeft == fitsRight ? preferLeft : fitsLeft

    let x: Double
    if tooltipLeft {
        x = max(target.dx - horizontalOffset - childSize.width, margin)
    } else {
        x = min(target.dx + horizontalOffset, size.width - margin)
    }

    // VERTICAL DIRECTION -- center on target
    let flexibleSpace = size.height - childSize.height
    let y: Double
    if flexibleSpace <= 2 * margin {
        y = flexibleSpace / 2.0
    } else {
        y = clampDouble(target.dy - childSize.height / 2, margin, flexibleSpace - margin)
    }

    return Offset(x, y)
}

// MARK: - Duration helper

/// Convert a Swift `Duration` to seconds as `Double`.
private func _durationToSeconds(_ duration: Duration) -> Double {
    let components = duration.components
    let microseconds = components.seconds * 1_000_000
        + components.attoseconds / 1_000_000_000_000
    return Double(microseconds) / 1_000_000.0
}

// MARK: - TooltipThemeData

/// Theme data for `Tooltip` widgets.
///
/// This class defines the visual appearance of tooltips, including their
/// size, positioning, colors, and timing behavior.
public struct TooltipThemeData: Equatable {

    /// The height of the tooltip's child.
    public let height: Double?

    /// The vertical gap between the widget and the displayed tooltip.
    public let verticalOffset: Double?

    /// The amount of space by which to inset the tooltip's child.
    public let padding: EdgeInsets?

    /// The empty space that surrounds the tooltip.
    public let margin: EdgeInsets?

    /// Whether the tooltip defaults to being displayed below the widget.
    public let preferBelow: Bool?

    /// Specifies the tooltip's shape and background color.
    public let decoration: BoxDecoration?

    /// The length of time that a pointer must hover over a tooltip's widget
    /// before the tooltip will be shown.
    public let waitDuration: Duration?

    /// The length of time that the tooltip will be shown after a long press
    /// is released or after hover ends.
    public let showDuration: Duration?

    /// The style to use for the message of the tooltip.
    public let textStyle: TextStyle?

    /// If non-nil, the maximum width of the tooltip text before it wraps.
    public let maxWidth: Double?

    /// Creates a theme data for `Tooltip` widgets.
    public init(
        height: Double? = nil,
        verticalOffset: Double? = nil,
        padding: EdgeInsets? = nil,
        margin: EdgeInsets? = nil,
        preferBelow: Bool? = nil,
        decoration: BoxDecoration? = nil,
        showDuration: Duration? = nil,
        waitDuration: Duration? = nil,
        textStyle: TextStyle? = nil,
        maxWidth: Double? = nil
    ) {
        self.height = height
        self.verticalOffset = verticalOffset
        self.padding = padding
        self.margin = margin
        self.preferBelow = preferBelow
        self.decoration = decoration
        self.showDuration = showDuration
        self.waitDuration = waitDuration
        self.textStyle = textStyle
        self.maxWidth = maxWidth
    }

    /// Creates the standard `TooltipThemeData` based on the given theme.
    ///
    /// A ToolTip is the one overlay Windows keeps at the CONTROL radius (4),
    /// at elevation 16, on the flyout surface colour with the flyout stroke
    /// — `menuColor` is the acrylic fallback (#F9F9F9 / #2C2C2C), which is
    /// what a real tooltip measures, and not the white and mid-grey this
    /// used to paint.
    public static func standard(_ theme: FluentThemeData) -> TooltipThemeData {
        let decoration = BoxDecoration(
            color: theme.menuColor,
            border: Border.all(
                color: theme.resources.surfaceStrokeColorFlyout,
                width: FluentStrokeWidth.thin),
            borderRadius: FluentCorners.tooltipRadius,
            boxShadow: FluentElevation.shadows(
                FluentElevation.tooltip, brightness: theme.brightness)
        )

        return TooltipThemeData(
            height: 32,
            verticalOffset: 24,
            padding: EdgeInsets(left: 8, top: 5, right: 8, bottom: 7),
            margin: EdgeInsets.zero,
            preferBelow: false,
            decoration: decoration,
            showDuration: .milliseconds(1500),
            waitDuration: .milliseconds(1000),
            textStyle: theme.typography.caption,
            maxWidth: nil
        )
    }

    /// Merges this `TooltipThemeData` with another, with the other taking precedence.
    public func merge(_ other: TooltipThemeData?) -> TooltipThemeData {
        guard let other = other else { return self }
        return TooltipThemeData(
            height: other.height ?? height,
            verticalOffset: other.verticalOffset ?? verticalOffset,
            padding: other.padding ?? padding,
            margin: other.margin ?? margin,
            preferBelow: other.preferBelow ?? preferBelow,
            decoration: other.decoration ?? decoration,
            showDuration: other.showDuration ?? showDuration,
            waitDuration: other.waitDuration ?? waitDuration,
            textStyle: other.textStyle ?? textStyle,
            maxWidth: other.maxWidth ?? maxWidth
        )
    }

    public static func == (lhs: TooltipThemeData, rhs: TooltipThemeData) -> Bool {
        return lhs.height == rhs.height
            && lhs.verticalOffset == rhs.verticalOffset
            && lhs.padding == rhs.padding
            && lhs.margin == rhs.margin
            && lhs.preferBelow == rhs.preferBelow
            && lhs.showDuration == rhs.showDuration
            && lhs.waitDuration == rhs.waitDuration
            && lhs.textStyle == rhs.textStyle
            && lhs.maxWidth == rhs.maxWidth
    }
}

// MARK: - TooltipTheme

/// An inherited widget that defines the configuration for `Tooltip`s in this
/// widget's subtree.
///
/// Values specified here are used for `Tooltip` properties that are not given
/// an explicit non-nil value.
public class TooltipTheme: InheritedTheme {

    /// The properties for descendant `Tooltip` widgets.
    public let data: TooltipThemeData

    /// Creates a theme that controls how descendant `Tooltip`s should look.
    public init(key: (any Key)? = nil, data: TooltipThemeData, child: Widget) {
        self.data = data
        super.init(key: key, child: child)
    }

    /// Returns the closest `TooltipThemeData` which encloses the given context.
    ///
    /// Resolution order:
    /// 1. Defaults from `TooltipThemeData.standard`
    /// 2. Local `TooltipTheme` ancestor
    public static func of(_ context: any BuildContext) -> TooltipThemeData {
        let theme = FluentTheme.of(context)
        let inherited = context.dependOnInheritedWidgetOfExactType(TooltipTheme.self)
        return TooltipThemeData.standard(theme).merge(inherited?.data)
    }

    public override func wrap(_ context: any BuildContext, _ child: Widget) -> Widget {
        return TooltipTheme(data: data, child: child)
    }

    public override func updateShouldNotify(_ oldWidget: InheritedWidget) -> Bool {
        guard let old = oldWidget as? TooltipTheme else { return true }
        return data != old.data
    }
}

// MARK: - Tooltip

/// A tooltip is a popup that contains additional information about another
/// control or object.
///
/// Tooltips display automatically when the user hovers the pointer over the
/// associated control. The tooltip disappears when the user stops hovering
/// the pointer over the associated control.
///
/// ```swift
/// Tooltip(
///     message: "This is a tooltip",
///     child: someWidget
/// )
/// ```
///
/// **Dart Source:** `fluent_ui/lib/src/controls/flyouts/tooltip.dart`
public class Tooltip: StatefulWidget {

    /// The text to display in the tooltip.
    ///
    /// Only one of `message` and `richMessage` may be non-nil.
    public let message: String?

    /// The rich text to display in the tooltip.
    ///
    /// Only one of `message` and `richMessage` may be non-nil.
    public let richMessage: InlineSpan?

    /// The widget the tooltip will be displayed for when hovered.
    public let child: Widget?

    /// The style of the tooltip. If non-nil, it is merged with the
    /// `TooltipTheme` from the context.
    public let style: TooltipThemeData?

    /// Whether the tooltip's message should be excluded from the
    /// semantics tree.
    public let excludeFromSemantics: Bool

    /// Whether the current mouse position should be used to render the
    /// tooltip on the screen.
    ///
    /// Defaults to true. When true, the tooltip is shown at the current
    /// mouse position.
    public let useMousePosition: Bool

    /// Whether the tooltip should be displayed at the left or right of
    /// the child instead of above or below.
    public let displayHorizontally: Bool

    /// Creates a tooltip.
    ///
    /// Wrap any widget in a `Tooltip` to show a message on mouse hover.
    public init(
        key: (any Key)? = nil,
        message: String? = nil,
        richMessage: InlineSpan? = nil,
        child: Widget? = nil,
        style: TooltipThemeData? = nil,
        excludeFromSemantics: Bool = false,
        useMousePosition: Bool = true,
        displayHorizontally: Bool = false
    ) {
        assert(
            (message == nil) != (richMessage == nil),
            "Either `message` or `richMessage` must be specified"
        )
        self.message = message
        self.richMessage = richMessage
        self.child = child
        self.style = style
        self.excludeFromSemantics = excludeFromSemantics
        self.useMousePosition = useMousePosition
        self.displayHorizontally = displayHorizontally
        super.init(key: key)
    }

    // MARK: - Static tooltip management

    nonisolated(unsafe) static var _openedTooltips: [TooltipState] = []

    /// Causes any current tooltips to be concealed. Only called for mouse hover
    /// enter detections. Will not conceal the supplied tooltip.
    static func _concealOtherTooltips(_ current: TooltipState) {
        if _openedTooltips.isEmpty { return }
        let opened = _openedTooltips
        for state in opened {
            if state === current { continue }
            state._concealTooltip()
        }
    }

    /// Causes the most recently concealed tooltip to be revealed. Only called
    /// for mouse hover exit detections.
    static func _revealLastTooltip() {
        if _openedTooltips.isEmpty { return }
        _openedTooltips.last?._revealTooltip()
    }

    /// Dismiss all of the tooltips that are currently shown on the screen.
    ///
    /// Returns true if it successfully dismisses the tooltips; false if there
    /// were no tooltips shown.
    @discardableResult
    public static func dismissAllToolTips() -> Bool {
        if _openedTooltips.isEmpty { return false }
        let opened = _openedTooltips
        for state in opened {
            state._dismissTooltip(immediately: true)
        }
        return true
    }

    public override func createState() -> State<StatefulWidget> {
        return TooltipState()
    }
}

// MARK: - TooltipState

/// The state for a `Tooltip` widget.
///
/// Manages the tooltip's visibility and positioning.
public class TooltipState: State<StatefulWidget> {

    // MARK: - Defaults

    private static let _defaultVerticalOffset: Double = 24
    private static let _defaultPreferBelow: Bool = true
    private static let _defaultShowDuration: Duration = .milliseconds(1500)
    private static let _defaultWaitDuration: Duration = .milliseconds(1000)

    // MARK: - State

    private var _entry: OverlayEntry?
    private var _dismissTimer: Foundation.Timer?
    private var _showTimer: Foundation.Timer?
    private var _mousePosition: Offset?
    private var _isConcealed: Bool = false
    private var _forceRemoval: Bool = false
    private var _visible: Bool = true
    private var _tooltipTheme: TooltipThemeData = TooltipThemeData()

    private var tooltipWidget: Tooltip {
        return widget as! Tooltip
    }

    private var _showDuration: Duration {
        return _tooltipTheme.showDuration ?? TooltipState._defaultShowDuration
    }

    private var _waitDuration: Duration {
        return _tooltipTheme.waitDuration ?? TooltipState._defaultWaitDuration
    }

    /// The plain text message for this tooltip.
    private var _tooltipMessage: String {
        return tooltipWidget.message ?? tooltipWidget.richMessage!.toPlainText()
    }

    // MARK: - Lifecycle

    public override func initState() {
        super.initState()
        _isConcealed = false
        _forceRemoval = false
    }

    public override func didChangeDependencies() {
        super.didChangeDependencies()
        _tooltipTheme = TooltipTheme.of(context!)
    }

    public override func dispose() {
        _removeEntry()
        super.dispose()
    }

    public override func deactivate() {
        if _entry != nil {
            _dismissTooltip(immediately: true)
        }
        _showTimer?.invalidate()
        _showTimer = nil
        super.deactivate()
    }

    // MARK: - Show / Hide

    private func _handleMouseEnter() {
        _showTooltip()
    }

    private func _handleMouseExit(immediately: Bool = false) {
        _mousePosition = nil
        _dismissTooltip(immediately: _isConcealed || immediately)
    }

    private func _showTooltip(immediately: Bool = false) {
        _dismissTimer?.invalidate()
        _dismissTimer = nil
        if immediately {
            _ensureTooltipVisible()
            return
        }
        _showTimer?.invalidate()
        let waitSeconds = _durationToSeconds(_waitDuration)
        _showTimer = Foundation.Timer.scheduledTimer(
            withTimeInterval: waitSeconds,
            repeats: false,
            block: _sendableTimer { [weak self] (_: Timer) in
                guard let self = self, self.mounted else { return }
                self._ensureTooltipVisible()
            }
        )
    }

    func _dismissTooltip(immediately: Bool = false) {
        _showTimer?.invalidate()
        _showTimer = nil
        if immediately {
            _removeEntry()
            return
        }
        _forceRemoval = true
        _dismissTimer?.invalidate()
        let showSeconds = _durationToSeconds(_showDuration)
        _dismissTimer = Foundation.Timer.scheduledTimer(
            withTimeInterval: showSeconds,
            repeats: false,
            block: _sendableTimer { [weak self] (_: Timer) in
                guard let self = self, self.mounted else { return }
                self._removeEntry()
            }
        )
    }

    func _concealTooltip() {
        if _isConcealed || _forceRemoval { return }
        _isConcealed = true
        _dismissTimer?.invalidate()
        _dismissTimer = nil
        _showTimer?.invalidate()
        _showTimer = nil
        if _entry != nil {
            _entry!.remove()
        }
    }

    func _revealTooltip() {
        if !_isConcealed { return }
        _isConcealed = false
        _dismissTimer?.invalidate()
        _dismissTimer = nil
        _showTimer?.invalidate()
        _showTimer = nil
        if let entry = _entry, !entry.mounted {
            Overlay.of(context!).insert(entry)
        }
    }

    /// Shows the tooltip if it is not already visible.
    ///
    /// Returns `false` when the tooltip was already visible.
    @discardableResult
    public func _ensureTooltipVisible() -> Bool {
        if !_visible { return false }
        _showTimer?.invalidate()
        _showTimer = nil
        _forceRemoval = false
        if _isConcealed {
            Tooltip._concealOtherTooltips(self)
            _revealTooltip()
            return true
        }
        if _entry != nil {
            _dismissTimer?.invalidate()
            _dismissTimer = nil
            return false  // Already visible.
        }
        _createNewEntry()
        return true
    }

    // MARK: - Entry management

    private func _createNewEntry() {
        let ctx = context!
        let overlayState = Overlay.of(ctx)

        let box = ctx.findRenderObject()! as! RenderBox
        let target: Offset
        if tooltipWidget.useMousePosition, let mousePos = _mousePosition {
            target = mousePos
        } else {
            target = box.localToGlobal(
                box.size.center(Offset.zero),
                ancestor: overlayState.context?.findRenderObject()
            )
        }

        // Merge widget style with cached theme
        let tooltipTheme = _tooltipTheme.merge(tooltipWidget.style)

        // Compute default decoration based on current theme
        let theme = FluentTheme.of(ctx)
        let defaultTextStyle = theme.typography.body ?? TextStyle(color: Color(0xFF000000), fontSize: 14)
        let defaultDecoration = BoxDecoration(
            color: theme.menuColor,
            border: Border.all(color: theme.resources.surfaceStrokeColorFlyout,
                               width: FluentStrokeWidth.thin),
            borderRadius: FluentCorners.tooltipRadius,
            boxShadow: FluentElevation.shadows(
                FluentElevation.tooltip, brightness: theme.brightness)
        )

        // Build the overlay widget outside the builder to avoid leaking
        // updated values.
        let overlayWidget = _TooltipOverlay(
            richMessage: tooltipWidget.richMessage ?? TextSpan(text: tooltipWidget.message),
            padding: tooltipTheme.padding ?? EdgeInsets.zero,
            margin: tooltipTheme.margin ?? EdgeInsets.zero,
            decoration: tooltipTheme.decoration ?? defaultDecoration,
            textStyle: tooltipTheme.textStyle ?? defaultTextStyle,
            target: target,
            verticalOffset: tooltipTheme.verticalOffset ?? TooltipState._defaultVerticalOffset,
            preferBelow: tooltipTheme.preferBelow ?? TooltipState._defaultPreferBelow,
            displayHorizontally: tooltipWidget.displayHorizontally,
            maxWidth: tooltipTheme.maxWidth
        )

        _entry = OverlayEntry(builder: { _ in overlayWidget })
        _isConcealed = false
        overlayState.insert(_entry!)

        // Conceal other tooltips so only one shows at a time
        Tooltip._concealOtherTooltips(self)

        assert(!Tooltip._openedTooltips.contains(where: { $0 === self }))
        Tooltip._openedTooltips.append(self)
    }

    private func _removeEntry() {
        Tooltip._openedTooltips.removeAll { $0 === self }
        _dismissTimer?.invalidate()
        _dismissTimer = nil
        _showTimer?.invalidate()
        _showTimer = nil
        if !_isConcealed {
            _entry?.remove()
        }
        _isConcealed = false
        _entry = nil
        Tooltip._revealLastTooltip()
    }

    // MARK: - Build

    public override func build(_ context: any BuildContext) -> Widget {
        // If message is empty then no need to create a tooltip overlay
        if _tooltipMessage.isEmpty {
            return tooltipWidget.child ?? SizedBox(width: 0, height: 0)
        }

        var result: Widget = tooltipWidget.child ?? SizedBox(width: 0, height: 0)

        // Only check for hovering if visible
        if _visible {
            result = MouseRegion(
                onEnter: { [weak self] _ in
                    guard let self = self else { return }
                    self._handleMouseEnter()
                },
                onHover: { [weak self] event in
                    guard let self = self else { return }
                    self._mousePosition = event.position
                },
                onExit: { [weak self] _ in
                    guard let self = self else { return }
                    self._handleMouseExit()
                },
                child: result
            )
        }

        return result
    }
}

// MARK: - _TooltipPositionDelegate

/// A delegate for computing the layout of a tooltip to be displayed above or
/// below (or left/right of) a target specified in the global coordinate system.
private class _TooltipPositionDelegate: SingleChildLayoutDelegate {

    let target: Offset
    let verticalOffset: Double
    let preferBelow: Bool
    let horizontal: Bool

    init(
        target: Offset,
        verticalOffset: Double,
        preferBelow: Bool,
        horizontal: Bool
    ) {
        self.target = target
        self.verticalOffset = verticalOffset
        self.preferBelow = preferBelow
        self.horizontal = horizontal
        super.init()
    }

    override func getConstraintsForChild(_ constraints: BoxConstraints) -> BoxConstraints {
        return constraints.loosen()
    }

    override func getPositionForChild(_ size: Size, _ childSize: Size) -> Offset {
        if horizontal {
            return horizontalPositionDependentBox(
                size: size,
                childSize: childSize,
                target: target,
                horizontalOffset: verticalOffset,
                preferLeft: preferBelow
            )
        } else {
            return positionDependentBox(
                size: size,
                childSize: childSize,
                target: target,
                preferBelow: preferBelow,
                verticalOffset: verticalOffset
            )
        }
    }

    override func shouldRelayout(_ oldDelegate: SingleChildLayoutDelegate) -> Bool {
        guard let old = oldDelegate as? _TooltipPositionDelegate else { return true }
        return target != old.target
            || verticalOffset != old.verticalOffset
            || preferBelow != old.preferBelow
            || horizontal != old.horizontal
    }
}

// MARK: - _TooltipOverlay

/// The overlay widget that renders the tooltip content, positioned relative
/// to the target using `CustomSingleChildLayout`.
private class _TooltipOverlay: StatelessWidget {

    let richMessage: InlineSpan
    let padding: EdgeInsets
    let margin: EdgeInsets
    let decoration: BoxDecoration
    let textStyle: TextStyle
    let target: Offset
    let verticalOffset: Double
    let preferBelow: Bool
    let displayHorizontally: Bool
    let maxWidth: Double?

    init(
        richMessage: InlineSpan,
        padding: EdgeInsets,
        margin: EdgeInsets,
        decoration: BoxDecoration,
        textStyle: TextStyle,
        target: Offset,
        verticalOffset: Double,
        preferBelow: Bool,
        displayHorizontally: Bool = false,
        maxWidth: Double? = nil
    ) {
        self.richMessage = richMessage
        self.padding = padding
        self.margin = margin
        self.decoration = decoration
        self.textStyle = textStyle
        self.target = target
        self.verticalOffset = verticalOffset
        self.preferBelow = preferBelow
        self.displayHorizontally = displayHorizontally
        self.maxWidth = maxWidth
        super.init()
    }

    override func build(_ context: any BuildContext) -> Widget {
        let theme = FluentTheme.of(context)

        // Build the tooltip content
        let content: Widget = IgnorePointer(
            child: DefaultTextStyle(
                style: theme.typography.body ?? TextStyle(color: Color(0xFF000000), fontSize: 14),
                child: DecoratedBox(
                    decoration: decoration,
                    child: Padding(
                        padding: padding,
                        child: ConstrainedBox(
                            constraints: BoxConstraints(
                                maxWidth: maxWidth ?? Double.infinity
                            ),
                            child: Center(
                                widthFactor: 1,
                                heightFactor: 1,
                                child: Text(rich: richMessage, style: textStyle)
                            )
                        )
                    )
                )
            )
        )

        return Positioned(
            fill: (),
            child: CustomSingleChildLayout(
                delegate: _TooltipPositionDelegate(
                    target: target,
                    verticalOffset: verticalOffset,
                    preferBelow: preferBelow,
                    horizontal: displayHorizontally
                ),
                child: content
            )
        )
    }
}
