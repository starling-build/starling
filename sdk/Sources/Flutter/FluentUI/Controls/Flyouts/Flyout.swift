// Ported from: fluent_ui/lib/src/controls/flyouts/flyout.dart
//               fluent_ui/lib/src/controls/flyouts/flyout_content.dart
//               fluent_ui/lib/src/controls/flyouts/flyout_content_manager.dart
//
// Simplified Flyout system with basic placement modes (top, bottom, left, right, auto).
// Uses OverlayEntry + ModalBarrier for display, CompositedTransformTarget/Follower
// for positioning relative to the trigger widget.

import FlutterSwiftBridge

// MARK: - FlyoutPlacement

/// Defines where a flyout should be positioned relative to its target.
public enum FlyoutPlacement {
    /// Automatically choose the best placement (tries bottom first, flips to top).
    case auto

    /// Position the flyout below the target, centered horizontally.
    case bottom

    /// Position the flyout above the target, centered horizontally.
    case top

    /// Position the flyout to the left of the target, centered vertically.
    case left

    /// Position the flyout to the right of the target, centered vertically.
    case right

    // WinUI's edge-aligned modes: the flyout's edge lines up with the
    // target's instead of their centres. A drop-down button's menu hangs
    // from its left edge (`BottomEdgeAlignedLeft`), a submenu opens beside
    // its item with their tops level (`RightEdgeAlignedTop`).

    /// Below the target, left edges aligned.
    case bottomEdgeAlignedLeft
    /// Below the target, right edges aligned.
    case bottomEdgeAlignedRight
    /// Above the target, left edges aligned.
    case topEdgeAlignedLeft
    /// Above the target, right edges aligned.
    case topEdgeAlignedRight
    /// To the right of the target, top edges aligned.
    case rightEdgeAlignedTop
    /// To the left of the target, top edges aligned.
    case leftEdgeAlignedTop

    /// Whether this placement is horizontal (left or right).
    public var isHorizontal: Bool {
        switch self {
        case .left, .right, .rightEdgeAlignedTop, .leftEdgeAlignedTop: return true
        default: return false
        }
    }
}

// MARK: - FlyoutScope

/// The flyout a widget is inside, so content can close it — a menu item
/// once chosen, a picker's accept button — without holding the controller
/// that opened it. `closeAll` closes the chain: on Windows, choosing an
/// item in a submenu dismisses every menu above it too.
public final class FlyoutScope: InheritedWidget {
    weak var controller: FlyoutController?
    let parent: FlyoutScope?

    init(controller: FlyoutController, parent: FlyoutScope?, child: Widget) {
        self.controller = controller
        self.parent = parent
        super.init(child: child)
    }

    /// The nearest enclosing flyout, or nil outside any.
    public static func maybeOf(_ context: any BuildContext) -> FlyoutScope? {
        context.dependOnInheritedWidgetOfExactType(FlyoutScope.self)
    }

    /// Closes this flyout only; a submenu stays under its open parent.
    public func close() {
        controller?.closeFlyout()
    }

    /// Closes this flyout and every flyout it was opened from.
    public func closeAll() {
        var scope: FlyoutScope? = self
        while let s = scope {
            s.controller?.closeFlyout()
            scope = s.parent
        }
    }

    public override func updateShouldNotify(_ oldWidget: InheritedWidget) -> Bool {
        guard let old = oldWidget as? FlyoutScope else { return true }
        return controller !== old.controller || parent !== old.parent
    }
}

// MARK: - FlyoutController

/// Controls the display and dismissal of flyouts.
///
/// Attach a `FlyoutController` to a `FlyoutTarget` widget, then call
/// `showFlyout(builder:)` to display a popup relative to the target.
///
/// Usage:
/// ```swift
/// let controller = FlyoutController()
///
/// FlyoutTarget(
///     controller: controller,
///     child: Button(child: Text("Open"), onPressed: {
///         controller.showFlyout(
///             builder: { context in
///                 FlyoutContent(child: Text("Hello"))
///             }
///         )
///     })
/// )
/// ```
public class FlyoutController {

    /// Creates a flyout controller.
    public init() {}

    // MARK: - Attachment

    /// The state of the attached FlyoutTarget.
    weak var _attachState: _FlyoutTargetState?

    /// Whether this controller is attached to a `FlyoutTarget`.
    public var isAttached: Bool { return _attachState != nil }

    func _attach(_ state: _FlyoutTargetState) {
        if _attachState === state { return }
        _attachState = state
    }

    func _detach() {
        _attachState = nil
    }

    private func _ensureAttached() {
        assert(isAttached, "FlyoutController must be attached to a FlyoutTarget")
    }

    // MARK: - Open / Close State

    /// Whether a flyout is currently displayed.
    public var isOpen: Bool { return _flyoutEntry != nil }

    private var _barrierEntry: OverlayEntry?
    /// Our place on the Escape stack while the flyout is up.
    private var _dismissToken: DismissStack.Token?
    private var _flyoutEntry: OverlayEntry?

    // MARK: - Show Flyout

    /// Shows a flyout popup relative to the attached `FlyoutTarget`.
    ///
    /// - Parameters:
    ///   - builder: Builds the flyout content widget. Typically returns a `FlyoutContent`.
    ///   - barrierDismissible: Whether tapping outside the flyout closes it. Defaults to `true`.
    ///   - barrierColor: Color of the barrier behind the flyout. Defaults to transparent.
    ///   - placement: Where to position the flyout. Defaults to `.auto`.
    ///   - additionalOffset: Extra spacing between the target and flyout. Defaults to `8`.
    ///   - margin: Minimum margin from screen edges. Defaults to `8`.
    ///   - barrier: Whether to put a barrier under the flyout at all. A
    ///     submenu opens without one: its parent menu must stay live under
    ///     it — hovering the parent's other items is what closes a submenu
    ///     on Windows — and a click anywhere else lands on the parent's own
    ///     barrier, which closes the parent and the submenu with it.
    public func showFlyout(
        builder: @escaping WidgetBuilder,
        barrierDismissible: Bool = true,
        barrierColor: Color? = nil,
        placement: FlyoutPlacement = .auto,
        additionalOffset: Double = 8.0,
        margin: Double = 8.0,
        barrier: Bool = true
    ) {
        _ensureAttached()
        guard let attachState = _attachState else { return }
        guard attachState.mounted else { return }

        // If already open, close first
        if isOpen { closeFlyout() }

        let context = attachState.context!
        let overlayState = Overlay.of(context)

        // The flyout this target sits inside, if any, so the new one can
        // close the chain it hangs from. Read without a dependency: this is
        // a show, not a build.
        let parentScope = context.getElementForInheritedWidgetOfExactType(FlyoutScope.self)?
            .widget as? FlyoutScope

        // Create barrier entry
        let barrierEntry: OverlayEntry? = barrier ? OverlayEntry(builder: { [weak self] _ in
            return ModalBarrier(
                color: barrierColor,
                dismissible: barrierDismissible,
                onDismiss: { [weak self] in
                    self?.closeFlyout()
                }
            )
        }) : nil

        // Create flyout entry using CompositedTransformFollower
        let link = attachState._layerLink
        let flyoutEntry = OverlayEntry(builder: { [weak self] ctx in
            guard let self else {
                return SizedBox(width: 0, height: 0)
            }
            return FlyoutScope(
                controller: self,
                parent: parentScope,
                child: _FlyoutPositioner(
                    link: link,
                    placement: placement,
                    additionalOffset: additionalOffset,
                    margin: margin,
                    targetContext: attachState.context,
                    builder: builder
                ))
        })

        _barrierEntry = barrierEntry
        _flyoutEntry = flyoutEntry

        if let barrierEntry { overlayState.insert(barrierEntry) }
        overlayState.insert(flyoutEntry)
        // Esc closes the newest flyout first; a submenu goes before its
        // parent, which is the order they were pushed in.
        DismissStack.remove(_dismissToken)
        _dismissToken = DismissStack.push { [weak self] in self?.closeFlyout() }
    }

    // MARK: - Close Flyout

    /// Closes the currently open flyout.
    public func closeFlyout() {
        DismissStack.remove(_dismissToken)
        _dismissToken = nil
        _barrierEntry?.remove()
        _barrierEntry?.dispose()
        _barrierEntry = nil

        _flyoutEntry?.remove()
        _flyoutEntry?.dispose()
        _flyoutEntry = nil
    }
}

// MARK: - FlyoutTarget

/// A widget that marks the position a flyout should attach to.
///
/// Wrap your trigger widget with `FlyoutTarget` and provide a `FlyoutController`.
/// When the controller's `showFlyout` method is called, the flyout popup will
/// appear relative to this widget's position.
public class FlyoutTarget: StatefulWidget {
    /// The controller that manages flyout display for this target.
    public let controller: FlyoutController

    /// The trigger widget that the flyout attaches to.
    public let child: Widget

    /// Creates a flyout target.
    public init(
        key: (any Key)? = nil,
        controller: FlyoutController,
        child: Widget
    ) {
        self.controller = controller
        self.child = child
        super.init(key: key)
    }

    public override func createState() -> State<StatefulWidget> {
        return _FlyoutTargetState()
    }
}

// MARK: - _FlyoutTargetState

class _FlyoutTargetState: State<StatefulWidget> {
    let _layerLink = LayerLink()

    private var flyoutTarget: FlyoutTarget {
        return widget as! FlyoutTarget
    }

    override func initState() {
        super.initState()
        flyoutTarget.controller._attach(self)
    }

    override func dispose() {
        flyoutTarget.controller._detach()
        flyoutTarget.controller.closeFlyout()
        super.dispose()
    }

    override func build(_ context: any BuildContext) -> Widget {
        flyoutTarget.controller._attach(self)
        return CompositedTransformTarget(
            link: _layerLink,
            child: flyoutTarget.child
        )
    }
}

// MARK: - _FlyoutPositioner

/// Internal widget that positions the flyout relative to its target using
/// `CompositedTransformFollower`.
///
/// Computes the correct anchor and offset based on the `FlyoutPlacement`.
private class _FlyoutPositioner: StatelessWidget {
    let link: LayerLink
    let placement: FlyoutPlacement
    let additionalOffset: Double
    let margin: Double
    let targetContext: (any BuildContext)?
    let builder: WidgetBuilder

    init(
        key: (any Key)? = nil,
        link: LayerLink,
        placement: FlyoutPlacement,
        additionalOffset: Double,
        margin: Double,
        targetContext: (any BuildContext)?,
        builder: @escaping WidgetBuilder
    ) {
        self.link = link
        self.placement = placement
        self.additionalOffset = additionalOffset
        self.margin = margin
        self.targetContext = targetContext
        self.builder = builder
        super.init(key: key)
    }

    override func build(_ context: any BuildContext) -> Widget {
        // Resolve auto placement
        let resolvedPlacement = _resolvePlacement(context)

        // Compute anchors and offset based on placement
        let targetAnchor: Alignment
        let followerAnchor: Alignment
        let offset: Offset

        switch resolvedPlacement {
        case .bottom:
            targetAnchor = .bottomCenter
            followerAnchor = .topCenter
            offset = Offset(0, additionalOffset)
        case .top:
            targetAnchor = .topCenter
            followerAnchor = .bottomCenter
            offset = Offset(0, -additionalOffset)
        case .left:
            targetAnchor = .centerLeft
            followerAnchor = .centerRight
            offset = Offset(-additionalOffset, 0)
        case .right:
            targetAnchor = .centerRight
            followerAnchor = .centerLeft
            offset = Offset(additionalOffset, 0)
        case .bottomEdgeAlignedLeft:
            targetAnchor = .bottomLeft
            followerAnchor = .topLeft
            offset = Offset(0, additionalOffset)
        case .bottomEdgeAlignedRight:
            targetAnchor = .bottomRight
            followerAnchor = .topRight
            offset = Offset(0, additionalOffset)
        case .topEdgeAlignedLeft:
            targetAnchor = .topLeft
            followerAnchor = .bottomLeft
            offset = Offset(0, -additionalOffset)
        case .topEdgeAlignedRight:
            targetAnchor = .topRight
            followerAnchor = .bottomRight
            offset = Offset(0, -additionalOffset)
        case .rightEdgeAlignedTop:
            targetAnchor = .topRight
            followerAnchor = .topLeft
            offset = Offset(additionalOffset, 0)
        case .leftEdgeAlignedTop:
            targetAnchor = .topLeft
            followerAnchor = .topRight
            offset = Offset(-additionalOffset, 0)
        case .auto:
            // Should not reach here; _resolvePlacement always returns a concrete placement
            targetAnchor = .bottomCenter
            followerAnchor = .topCenter
            offset = Offset(0, additionalOffset)
        }

        // Slide in from the target's side: a flyout below its target comes
        // down from just above its final place.
        let slideFrom: Offset
        switch resolvedPlacement {
        case .top, .topEdgeAlignedLeft, .topEdgeAlignedRight: slideFrom = Offset(0, 8)
        case .left, .leftEdgeAlignedTop: slideFrom = Offset(8, 0)
        case .right, .rightEdgeAlignedTop: slideFrom = Offset(-8, 0)
        default: slideFrom = Offset(0, -8)
        }
        // Loose constraints, on purpose: the overlay lays its entries out
        // TIGHT to its own size, and a follower that fills the overlay anchors
        // by the overlay's centre and paints its content across the whole
        // window. Aligned top-left under loose constraints it is exactly as
        // big as the flyout, so the anchor arithmetic and the paint offset
        // are the flyout's own.
        return Align(
            alignment: Alignment.topLeft,
            child: CompositedTransformFollower(
                link: link,
                showWhenUnlinked: false,
                offset: offset,
                targetAnchor: targetAnchor,
                followerAnchor: followerAnchor,
                // Content-sized inside WinUI's flyout box: the intrinsic
                // wrappers stop a column or a row with `Expanded` from taking
                // every pixel the loose constraints allow.
                child: ConstrainedBox(
                    constraints: kFlyoutThemeConstraints,
                    child: IntrinsicWidth(child: IntrinsicHeight(
                        child: FluentEntrance(child: builder(context), slideFrom: slideFrom))))
            )
        )
    }

    /// Resolves `.auto` placement by checking available space.
    ///
    /// Tries bottom first. If the target is in the bottom half of the screen,
    /// flips to top.
    private func _resolvePlacement(_ context: any BuildContext) -> FlyoutPlacement {
        // The bottom-hanging modes flip above the target when there is no
        // room below, as `.auto` does; every other mode is taken as given.
        let flipped: FlyoutPlacement
        switch placement {
        case .auto: flipped = .top
        case .bottomEdgeAlignedLeft: flipped = .topEdgeAlignedLeft
        case .bottomEdgeAlignedRight: flipped = .topEdgeAlignedRight
        default: return placement
        }
        let wanted: FlyoutPlacement = placement == .auto ? .bottom : placement

        // Try to get the target's position on screen
        guard let targetCtx = targetContext else { return wanted }
        guard let renderBox = targetCtx.findRenderObject() as? RenderBox else { return wanted }

        let targetGlobal = renderBox.localToGlobal(Offset.zero)
        let targetSize = renderBox.size

        // Get the screen size from the nearest ancestor render object
        // Use a simple heuristic: if the target is in the bottom half, place above
        let targetBottom = targetGlobal.dy + targetSize.height

        // Try to find the overlay size by going up to the root
        var screenHeight: Double = 800 // fallback
        if let rootBox = _findRootRenderBox(context) {
            screenHeight = rootBox.size.height
        }

        // If there's less than 200px of space below, or target is in bottom half, flip to top
        let spaceBelow = screenHeight - targetBottom
        let spaceAbove = targetGlobal.dy

        if spaceBelow < spaceAbove && spaceBelow < 200 {
            return flipped
        }
        return wanted
    }

    /// Walk up to find the root render box for screen size estimation.
    private func _findRootRenderBox(_ context: any BuildContext) -> RenderBox? {
        var current: RenderObject? = context.findRenderObject()
        var root: RenderBox?
        while current != nil {
            if let box = current as? RenderBox {
                root = box
            }
            current = (current as? RenderObject)?.parent as? RenderObject
        }
        return root
    }
}

// MARK: - FlyoutContent

/// Default minimum constraints for flyout content.
nonisolated(unsafe) public let kFlyoutMinConstraints = BoxConstraints(minWidth: 118)

/// WinUI's `FlyoutThemeMinWidth/MaxWidth/MinHeight/MaxHeight`: the box a
/// flyout's content is sized within. A flyout is as big as what it holds,
/// never bigger than this, and a long line wraps at 456.
nonisolated(unsafe) public let kFlyoutThemeConstraints = BoxConstraints(
    minWidth: 96, maxWidth: 456, minHeight: 40, maxHeight: 756)

/// The styled container for flyout popup content.
///
/// `FlyoutContent` renders a rounded rectangle with a border, background color,
/// shadow, and padding. Use it as the top-level widget inside a flyout builder.
///
/// Usage:
/// ```swift
/// controller.showFlyout(builder: { context in
///     FlyoutContent(child: Text("Hello flyout"))
/// })
/// ```
public class FlyoutContent: StatelessWidget {
    /// The content to display inside the flyout.
    public let child: Widget

    /// The background color. Defaults to `FluentThemeData.menuColor`.
    public let color: Color?

    /// Padding around the child. Defaults to 8 on each side.
    public let padding: EdgeInsets

    /// Shadow color. Defaults to black.
    public let shadowColor: Color

    /// Elevation for the shadow. Defaults to `FluentElevation.flyout` (32),
    /// the depth Windows gives every flyout; the shadow itself is the token
    /// ramp's two-layer recipe for that depth.
    public let elevation: Double

    /// Box constraints. Defaults to `kFlyoutMinConstraints`.
    public let constraints: BoxConstraints

    /// Creates a flyout content container.
    public init(
        key: (any Key)? = nil,
        child: Widget,
        color: Color? = nil,
        padding: EdgeInsets = EdgeInsets(all: 8),
        shadowColor: Color = Color(0xFF000000),
        elevation: Double = FluentElevation.flyout,
        constraints: BoxConstraints = kFlyoutMinConstraints
    ) {
        self.child = child
        self.color = color
        self.padding = padding
        self.shadowColor = shadowColor
        self.elevation = elevation
        self.constraints = constraints
        super.init(key: key)
    }

    public override func build(_ context: any BuildContext) -> Widget {
        let theme = FluentTheme.of(context)

        let borderColor = theme.resources.surfaceStrokeColorFlyout
        let borderRadius = FluentCorners.overlayRadius
        let shadows = FluentElevation.shadows(
            elevation, brightness: theme.brightness, color: shadowColor)

        var content: Widget = Padding(padding: padding, child: child)
        if let color {
            // A caller's own colour: a solid surface, as before.
            content = _FlyoutDecoratedBox(
                decoration: BoxDecoration(
                    color: color,
                    border: Border.all(color: borderColor, width: FluentStrokeWidth.thin),
                    borderRadius: borderRadius,
                    boxShadow: shadows.isEmpty ? nil : shadows),
                child: content)
        } else {
            // Windows' flyout: acrylic (the thin default recipe, or its solid
            // fallback when transparency is off), the 1px flyout stroke drawn
            // over it, and the elevation shadow under it. The stroke sits in
            // the foreground so the blur does not soften it.
            content = DecoratedBox(
                decoration: BoxDecoration(
                    border: Border.all(color: borderColor, width: FluentStrokeWidth.thin),
                    borderRadius: borderRadius),
                position: .foreground,
                child: content)
            content = Acrylic(child: content, borderRadius: borderRadius)
            if !shadows.isEmpty {
                content = _FlyoutDecoratedBox(
                    decoration: BoxDecoration(borderRadius: borderRadius, boxShadow: shadows),
                    child: content)
            }
        }
        content = ConstrainedBox(constraints: constraints, child: content)

        return content
    }
}

// MARK: - _FlyoutDecoratedBox

/// A decorated box used by FlyoutContent.
private class _FlyoutDecoratedBox: SingleChildRenderObjectWidget {
    let decoration: Decoration

    init(
        key: (any Key)? = nil,
        decoration: Decoration,
        child: Widget? = nil
    ) {
        self.decoration = decoration
        super.init(key: key, child: child)
    }

    override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        return RenderDecoratedBox(decoration: decoration)
    }

    override func updateRenderObject(_ context: any BuildContext, renderObject: RenderObject) {
        let ro = renderObject as! RenderDecoratedBox
        ro.decoration = decoration
    }
}

// MARK: - FlyoutListTile

/// A list tile styled for use inside flyout content.
///
/// Provides hover/press feedback via `HoverButton`. Commonly used for
/// menu items inside a `FlyoutContent` or `MenuFlyout`.
public class FlyoutListTile: StatelessWidget {
    /// Called when the tile is pressed.
    public let onPressed: (() -> Void)?

    /// Called when the tile is long pressed.
    public let onLongPress: (() -> Void)?

    /// The leading icon widget.
    public let icon: Widget?

    /// The text content of the tile.
    public let text: Widget

    /// The trailing widget.
    public let trailing: Widget?

    /// Margin around the tile.
    public let margin: EdgeInsets

    /// Whether this tile is currently selected.
    public let selected: Bool

    /// Whether to show the selected indicator.
    public let showSelectedIndicator: Bool

    /// Called when the pointer enters the tile — a submenu opens from this.
    public let onPointerEnter: PointerEnterEventListener?

    /// Called when the pointer leaves the tile.
    public let onPointerExit: PointerExitEventListener?

    /// Creates a flyout list tile.
    public init(
        key: (any Key)? = nil,
        onPressed: (() -> Void)? = nil,
        onLongPress: (() -> Void)? = nil,
        icon: Widget? = nil,
        text: Widget,
        trailing: Widget? = nil,
        margin: EdgeInsets = EdgeInsets(bottom: 5),
        selected: Bool = false,
        showSelectedIndicator: Bool = true,
        onPointerEnter: PointerEnterEventListener? = nil,
        onPointerExit: PointerExitEventListener? = nil
    ) {
        self.onPressed = onPressed
        self.onLongPress = onLongPress
        self.onPointerEnter = onPointerEnter
        self.onPointerExit = onPointerExit
        self.icon = icon
        self.text = text
        self.trailing = trailing
        self.margin = margin
        self.selected = selected
        self.showSelectedIndicator = showSelectedIndicator
        super.init(key: key)
    }

    public override func build(_ context: any BuildContext) -> Widget {
        return HoverButton(
            builder: { [self] context, states in
                let theme = FluentTheme.of(context)
                let radius = BorderRadius.circular(4)
                let res = theme.resources

                var resolvedStates = states
                if selected {
                    resolvedStates = [.hovered]
                }

                let foregroundColor = ButtonThemeData.buttonForegroundColor(context, resolvedStates)

                let bgColor: Color = {
                    if resolvedStates.isDisabled { return Color(0x00000000) }
                    if resolvedStates.isPressed { return res.subtleFillColorTertiary }
                    if resolvedStates.isHovered { return res.subtleFillColorSecondary }
                    return Color(0x00000000)
                }()

                let bgDecoration = BoxDecoration(
                    color: bgColor,
                    borderRadius: radius
                )

                // Build the row content
                var rowChildren: [Widget] = []

                if let icon = icon {
                    rowChildren.append(
                        Padding(
                            padding: EdgeInsets(right: 10),
                            child: icon
                        )
                    )
                }

                rowChildren.append(
                    Expanded(
                        child: Padding(
                            padding: EdgeInsets(right: 10),
                            child: DefaultTextStyle(
                                style: TextStyle(
                                    color: foregroundColor,
                                    fontSize: 14
                                ),
                                child: text
                            )
                        )
                    )
                )

                if let trailing = trailing {
                    rowChildren.append(
                        DefaultTextStyle(
                            style: TextStyle(
                                color: res.controlStrokeColorDefault,
                                fontSize: 12
                            ),
                            child: trailing
                        )
                    )
                }

                let tileContent: Widget = _FlyoutTileDecoratedBox(
                    decoration: bgDecoration,
                    child: Padding(
                        padding: EdgeInsets(left: 10, top: 4, right: 8, bottom: 4),
                        child: Row(
                            mainAxisSize: .min,
                            children: rowChildren
                        )
                    )
                )

                return Padding(padding: margin, child: tileContent)
            },
            onPressed: onPressed,
            onLongPress: onLongPress,
            onPointerEnter: onPointerEnter,
            onPointerExit: onPointerExit
        )
    }
}

// MARK: - _FlyoutTileDecoratedBox

/// A decorated box for flyout list tiles.
private class _FlyoutTileDecoratedBox: SingleChildRenderObjectWidget {
    let decoration: Decoration

    init(
        key: (any Key)? = nil,
        decoration: Decoration,
        child: Widget? = nil
    ) {
        self.decoration = decoration
        super.init(key: key, child: child)
    }

    override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        return RenderDecoratedBox(decoration: decoration)
    }

    override func updateRenderObject(_ context: any BuildContext, renderObject: RenderObject) {
        let ro = renderObject as! RenderDecoratedBox
        ro.decoration = decoration
    }
}
