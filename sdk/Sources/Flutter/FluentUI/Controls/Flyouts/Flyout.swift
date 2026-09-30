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

    /// Top-left corner at the target's bottom-left: a context menu at the
    /// pointer, which is a zero-size target.
    case corner

    /// Position the flyout above the target, centered horizontally.
    case top

    /// Position the flyout to the left of the target, centered vertically.
    case left

    /// Position the flyout to the right of the target, centered vertically.
    case right

    /// Whether this placement is horizontal (left or right).
    public var isHorizontal: Bool {
        return self == .left || self == .right
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
    deinit {
        // A flyout open when its controller goes leaves a barrier nothing
        // can dismiss; take both entries down with it.
        _flyoutEntry?.remove(); _flyoutEntry?.dispose()
        _barrierEntry?.remove(); _barrierEntry?.dispose()
    }


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
    public var isOpen: Bool { return _barrierEntry != nil }

    private var _barrierEntry: OverlayEntry?
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
    public func showFlyout(
        builder: @escaping WidgetBuilder,
        barrierDismissible: Bool = true,
        barrierColor: Color? = nil,
        placement: FlyoutPlacement = .auto,
        additionalOffset: Double = 8.0,
        margin: Double = 8.0
    ) {
        _ensureAttached()
        guard let attachState = _attachState else { return }
        guard attachState.mounted else { return }

        // If already open, close first
        if isOpen { closeFlyout() }

        let context = attachState.context!
        let overlayState = Overlay.of(context)

        // Create barrier entry
        let barrierEntry = OverlayEntry(builder: { [weak self] _ in
            return ModalBarrier(
                color: barrierColor,
                dismissible: barrierDismissible,
                onDismiss: { [weak self] in
                    self?.closeFlyout()
                }
            )
        })

        // The flyout entry: positioned beside the target, and scoped so
        // that what it contains can close it.
        let link = attachState._layerLink
        let flyoutEntry = OverlayEntry(builder: { [weak self] ctx in
            guard let self else {
                return SizedBox(width: 0, height: 0)
            }
            return FlyoutScope(close: { [weak self] in self?.closeFlyout() }, child: _FlyoutPositioner(
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

        overlayState.insert(barrierEntry)
        overlayState.insert(flyoutEntry)
    }

    /// A flyout at a point in `context`'s overlay — a context menu at the
    /// pointer. Needs no target: the point is the target.
    public func showFlyout(in context: any BuildContext, at point: Offset,
                           builder: @escaping WidgetBuilder,
                           barrierDismissible: Bool = true, margin: Double = 8.0) {
        if isOpen { closeFlyout() }
        let overlayState = Overlay.of(context)
        let barrierEntry = OverlayEntry(builder: { [weak self] _ in
            return ModalBarrier(color: nil, dismissible: barrierDismissible,
                                onDismiss: { [weak self] in self?.closeFlyout() })
        })
        let link = LayerLink()
        let flyoutEntry = OverlayEntry(builder: { [weak self] ctx in
            guard let self else { return SizedBox(width: 0, height: 0) }
            return FlyoutScope(close: { [weak self] in self?.closeFlyout() }, child: _FlyoutPositioner(
                link: link, placement: .corner, additionalOffset: 0, margin: margin,
                targetContext: nil, targetRect: { Rect.fromLTWH(point.dx, point.dy, 0, 0) },
                builder: builder))
        })
        _barrierEntry = barrierEntry
        _flyoutEntry = flyoutEntry
        overlayState.insert(barrierEntry)
        overlayState.insert(flyoutEntry)
    }

    // MARK: - Close Flyout

    /// Closes the currently open flyout.
    public func closeFlyout() {
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

// MARK: - FlyoutScope

/// The open flyout around a widget, so a menu item can close it. A flyout
/// is overlay entries, not a route, so `Navigator.pop` does not reach it.
public final class FlyoutScope: InheritedWidget {
    public let close: () -> Void

    public init(key: (any Key)? = nil, close: @escaping () -> Void, child: Widget) {
        self.close = close
        super.init(key: key, child: child)
    }

    /// The nearest enclosing open flyout, or nil outside one.
    public static func maybeOf(_ context: any BuildContext) -> FlyoutScope? {
        context.dependOnInheritedWidgetOfExactType(FlyoutScope.self)
    }

    public override func updateShouldNotify(_ oldWidget: InheritedWidget) -> Bool { false }
}

// MARK: - _FlyoutPositioner

/// Internal widget that positions the flyout relative to its target.
///
/// The target's rectangle is read from its render box, in the overlay's
/// coordinates, and a `CustomSingleChildLayout` places the popup beside it
/// once the popup's own size is known — which is also when `.auto` can
/// decide between below and above, and when the popup can be kept inside
/// the overlay by `margin`. This is how fluent_ui positions flyouts in
/// Dart; the port's `FollowerLayer` is a stub that applies no transform,
/// so a `CompositedTransformFollower` here painted every flyout at the
/// overlay's origin, unbounded.
private class _FlyoutPositioner: StatelessWidget {
    let link: LayerLink
    let placement: FlyoutPlacement
    let additionalOffset: Double
    let margin: Double
    let targetContext: (any BuildContext)?
    /// An explicit target in overlay coordinates, instead of a widget's box.
    let targetRect: (() -> Rect)?
    let builder: WidgetBuilder

    init(
        key: (any Key)? = nil,
        link: LayerLink,
        placement: FlyoutPlacement,
        additionalOffset: Double,
        margin: Double,
        targetContext: (any BuildContext)?,
        targetRect: (() -> Rect)? = nil,
        builder: @escaping WidgetBuilder
    ) {
        self.link = link
        self.placement = placement
        self.additionalOffset = additionalOffset
        self.margin = margin
        self.targetContext = targetContext
        self.targetRect = targetRect
        self.builder = builder
        super.init(key: key)
    }

    override func build(_ context: any BuildContext) -> Widget {
        // The target's box is read when the popup is laid out, not now: a
        // relayout without a rebuild (the window resizing) moves the
        // button, and the popup must move with it.
        let overlayBox = Overlay.of(context).context?.findRenderObject() as? RenderBox
        let targetCtx = targetContext
        let explicit = targetRect
        return CustomSingleChildLayout(
            delegate: _FlyoutLayoutDelegate(
                target: {
                    if let explicit { return explicit() }
                    guard let targetCtx, let box = targetCtx.findRenderObject() as? RenderBox, box.hasSize else { return Rect.zero }
                    let origin = box.localToGlobal(Offset.zero, ancestor: overlayBox)
                    return Rect.fromLTWH(origin.dx, origin.dy, box.size.width, box.size.height)
                },
                placement: placement,
                additionalOffset: additionalOffset,
                margin: margin),
            child: builder(context))
    }
}

/// Places the popup beside `target` per `placement`, flipping `.auto`
/// above when there is more room there, and keeps it `margin` inside the
/// overlay.
private final class _FlyoutLayoutDelegate: SingleChildLayoutDelegate {
    let target: () -> Rect
    let placement: FlyoutPlacement
    let additionalOffset: Double
    let margin: Double

    init(target: @escaping () -> Rect, placement: FlyoutPlacement, additionalOffset: Double, margin: Double) {
        self.target = target
        self.placement = placement
        self.additionalOffset = additionalOffset
        self.margin = margin
        super.init()
    }

    override func getConstraintsForChild(_ constraints: BoxConstraints) -> BoxConstraints {
        BoxConstraints(
            maxWidth: max(0, constraints.maxWidth - 2 * margin),
            maxHeight: max(0, constraints.maxHeight - 2 * margin))
    }

    override func getPositionForChild(_ size: Size, _ childSize: Size) -> Offset {
        let target = self.target()
        var resolved = placement
        if resolved == .auto {
            let below = size.height - target.bottom - additionalOffset - margin
            let above = target.top - additionalOffset - margin
            resolved = childSize.height <= below || below >= above ? .bottom : .top
        }
        var x: Double, y: Double
        switch resolved {
        case .bottom, .auto:
            x = target.center.dx - childSize.width / 2
            y = target.bottom + additionalOffset
        case .corner:
            x = target.left
            y = target.bottom + additionalOffset
            // Flip up or left when the menu would run off the overlay.
            if y + childSize.height > size.height - margin { y = target.top - childSize.height }
            if x + childSize.width > size.width - margin { x = target.left - childSize.width }
        case .top:
            x = target.center.dx - childSize.width / 2
            y = target.top - additionalOffset - childSize.height
        case .left:
            x = target.left - additionalOffset - childSize.width
            y = target.center.dy - childSize.height / 2
        case .right:
            x = target.right + additionalOffset
            y = target.center.dy - childSize.height / 2
        }
        x = min(max(margin, x), max(margin, size.width - childSize.width - margin))
        y = min(max(margin, y), max(margin, size.height - childSize.height - margin))
        return Offset(x, y)
    }

    override func shouldRelayout(_ oldDelegate: SingleChildLayoutDelegate) -> Bool {
        guard let old = oldDelegate as? _FlyoutLayoutDelegate else { return true }
        return old.placement != placement || old.additionalOffset != additionalOffset || old.margin != margin
    }
}

// MARK: - FlyoutContent

/// Default minimum constraints for flyout content.
nonisolated(unsafe) public let kFlyoutMinConstraints = BoxConstraints(minWidth: 118)

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

    /// Elevation for the shadow. Defaults to 8.
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
        elevation: Double = 8.0,
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

        let bgColor = color ?? theme.menuColor
        let borderColor = theme.resources.surfaceStrokeColorFlyout
        let borderRadius = BorderRadius.circular(8)

        let decoration = BoxDecoration(
            color: bgColor,
            border: Border.all(color: borderColor, width: 1),
            borderRadius: borderRadius,
            boxShadow: elevation > 0 ? [
                BoxShadow(
                    color: shadowColor.withOpacity(0.14),
                    offset: Offset(0, elevation / 2),
                    blurRadius: elevation * 2
                )
            ] : nil
        )

        var content: Widget = Padding(padding: padding, child: child)
        content = _FlyoutDecoratedBox(decoration: decoration, child: content)
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
        showSelectedIndicator: Bool = true
    ) {
        self.onPressed = onPressed
        self.onLongPress = onLongPress
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
            onLongPress: onLongPress
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
