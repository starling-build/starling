// Ported from: fluent_ui/lib/src/controls/surfaces/expander.dart

import FlutterSwiftBridge

// MARK: - ExpanderDirection

/// The direction in which an `Expander` expands.
public enum ExpanderDirection {
    /// The expander expands downward.
    case down

    /// The expander expands upward.
    case up
}

// MARK: - Expander

/// A control that lets you show or hide less important content related to a
/// piece of primary content that is always visible.
///
/// Items in the `header` are always visible. The user can expand and
/// collapse the `content` area by interacting with the header.
public class Expander: StatefulWidget {

    /// A widget displayed before the header text.
    public let leading: Widget?

    /// The primary content of the expander header (always visible).
    public let header: Widget

    /// The content revealed when the expander is expanded.
    public let content: Widget

    /// A custom icon widget replacing the default chevron.
    public let icon: Widget?

    /// A widget displayed after the header, before the chevron icon.
    public let trailing: Widget?

    /// The expand/collapse animation duration.
    /// If nil, defaults to `FluentThemeData.mediumAnimationDuration`.
    public let animationDuration: Duration?

    /// The expand/collapse animation curve.
    /// If nil, defaults to `FluentThemeData.animationCurve`.
    public let animationCurve: (any Curve)?

    /// The direction the expander expands.
    /// Defaults to `.down`.
    public let direction: ExpanderDirection

    /// Whether the expander is initially expanded.
    /// Defaults to `false`.
    public let initiallyExpanded: Bool

    /// Called when the expanded state changes. `true` when open, `false` when closed.
    public let onStateChanged: ((Bool) -> Void)?

    /// Whether the expander is enabled.
    /// Defaults to `true`.
    public let enabled: Bool

    /// The background color of the content area.
    public let contentBackgroundColor: Color?

    /// Padding applied to the content area.
    /// Defaults to `EdgeInsets(all: 16)`.
    public let contentPadding: EdgeInsets

    public init(
        key: (any Key)? = nil,
        header: Widget,
        content: Widget,
        leading: Widget? = nil,
        icon: Widget? = nil,
        trailing: Widget? = nil,
        animationDuration: Duration? = nil,
        animationCurve: (any Curve)? = nil,
        direction: ExpanderDirection = .down,
        initiallyExpanded: Bool = false,
        onStateChanged: ((Bool) -> Void)? = nil,
        enabled: Bool = true,
        contentBackgroundColor: Color? = nil,
        contentPadding: EdgeInsets = EdgeInsets(all: 16)
    ) {
        self.header = header
        self.content = content
        self.leading = leading
        self.icon = icon
        self.trailing = trailing
        self.animationDuration = animationDuration
        self.animationCurve = animationCurve
        self.direction = direction
        self.initiallyExpanded = initiallyExpanded
        self.onStateChanged = onStateChanged
        self.enabled = enabled
        self.contentBackgroundColor = contentBackgroundColor
        self.contentPadding = contentPadding
        super.init(key: key)
    }

    public override func createState() -> State<StatefulWidget> {
        return ExpanderState()
    }
}

// MARK: - ExpanderState

/// The state for an `Expander` widget.
///
/// Because `SizeTransition`, `RotationTransition`, and `AnimatedBuilder` are
/// not yet available in flutter_swift, the expand/collapse animation is
/// approximated by toggling the content visibility. When the animation system
/// has frame-callback support the `AnimationController` wiring here will
/// drive smooth transitions automatically.
class ExpanderState: State<StatefulWidget>, TickerProvider {

    private var _isExpanded: Bool = false
    private var _controller: AnimationController?

    private var expander: Expander {
        return widget as! Expander
    }

    // MARK: - TickerProvider

    func createTicker(_ onTick: @escaping TickerCallback) -> Ticker {
        return Ticker(onTick)
    }

    // MARK: - Lifecycle

    override func initState() {
        super.initState()
        _isExpanded = expander.initiallyExpanded
        _controller = AnimationController(
            duration: expander.animationDuration ?? .milliseconds(250),
            vsync: self
        )
        if _isExpanded {
            _controller!.value = 1.0
        }
    }

    override func dispose() {
        _controller?.dispose()
        _controller = nil
        super.dispose()
    }

    // MARK: - Interaction

    private func _handlePressed() {
        let theme = FluentTheme.of(context!)

        if _isExpanded {
            _controller?.animateTo(
                0,
                duration: expander.animationDuration ?? theme.mediumAnimationDuration,
                curve: expander.animationCurve ?? theme.animationCurve
            )
            _isExpanded = false
        } else {
            _controller?.animateTo(
                1,
                duration: expander.animationDuration ?? theme.mediumAnimationDuration,
                curve: expander.animationCurve ?? theme.animationCurve
            )
            _isExpanded = true
        }
        expander.onStateChanged?(_isExpanded)
        if mounted {
            setState {}
        }
    }

    private var _isDown: Bool {
        return expander.direction == .down
    }

    // MARK: - Build

    override func build(_ context: any BuildContext) -> Widget {
        let theme = FluentTheme.of(context)
        let w = expander

        // -- Chevron icon --
        let chevronAngle: Double = _isExpanded ? Double.pi : 0.0

        let chevronWidget: Widget = w.icon ?? Transform(
            transform: Matrix4.rotationZ(chevronAngle),
            alignment: Alignment.center,
            child: FluentGlyph(_isDown ? .chevronDown : .chevronUp, size: 12,
                               color: theme.resources.textFillColorPrimary)
        )

        // -- Header --
        let headerWidget: Widget = HoverButton(
            builder: { [self] _, states in
                let bgColor = theme.resources.cardBackgroundFillColorDefault

                let headerBorderRadius: BorderRadius
                if _isExpanded {
                    headerBorderRadius = BorderRadius.only(
                        topLeft: Radius(circular: 6),
                        topRight: Radius(circular: 6),
                        bottomLeft: Radius(circular: 0),
                        bottomRight: Radius(circular: 0)
                    )
                } else {
                    headerBorderRadius = BorderRadius.all(Radius(circular: 6))
                }

                let headerDecoration = BoxDecoration(
                    color: bgColor,
                    border: Border.all(color: theme.resources.cardStrokeColorDefault),
                    borderRadius: headerBorderRadius
                )

                // Build row children
                var rowChildren: [Widget] = []

                if let leading = w.leading {
                    rowChildren.append(
                        Padding(
                            padding: EdgeInsets(left: 0, top: 0, right: 10, bottom: 0),
                            child: leading
                        )
                    )
                }

                rowChildren.append(Expanded(child: w.header))

                if let trailing = w.trailing {
                    rowChildren.append(
                        Padding(
                            padding: EdgeInsets(left: 20, top: 0, right: 0, bottom: 0),
                            child: trailing
                        )
                    )
                }

                // Chevron button area
                let chevronBgColor: Color = {
                    if states.isPressed {
                        return theme.resources.subtleFillColorTertiary
                    } else if states.isHovered {
                        return theme.resources.subtleFillColorSecondary
                    } else {
                        return theme.resources.subtleFillColorTransparent
                    }
                }()

                let chevronBox: Widget = _ExpanderDecoratedBox(
                    decoration: BoxDecoration(
                        color: chevronBgColor,
                        borderRadius: BorderRadius.all(Radius(circular: 6))
                    ),
                    child: Padding(
                        padding: EdgeInsets(all: 10),
                        child: chevronWidget
                    )
                )

                let chevronPadding = EdgeInsets(
                    left: w.trailing != nil ? 8.0 : 20.0,
                    top: 8,
                    right: 8,
                    bottom: 8
                )

                rowChildren.append(
                    Padding(padding: chevronPadding, child: chevronBox)
                )

                let row: Widget = Row(
                    mainAxisSize: .min,
                    children: rowChildren
                )

                var result: Widget = Padding(
                    padding: EdgeInsets(left: 16, top: 0, right: 0, bottom: 0),
                    child: Align(
                        alignment: Alignment.centerLeft,
                        child: row
                    )
                )

                result = ConstrainedBox(
                    constraints: BoxConstraints(minHeight: 42),
                    child: _ExpanderDecoratedBox(decoration: headerDecoration, child: result)
                )

                return result
            },
            onPressed: w.enabled ? { [weak self] in self?._handlePressed() } : nil
        )

        // -- Content --
        let contentDecoration = BoxDecoration(
            color: w.contentBackgroundColor ?? theme.resources.cardBackgroundFillColorSecondary,
            border: Border.all(color: theme.resources.cardStrokeColorDefault),
            borderRadius: BorderRadius.only(
                topLeft: Radius(circular: 0),
                topRight: Radius(circular: 0),
                bottomLeft: Radius(circular: 6),
                bottomRight: Radius(circular: 6)
            )
        )

        let contentWidget: Widget = _ExpanderDecoratedBox(
            decoration: contentDecoration,
            child: SizedBox(
                width: Double.infinity,
                child: Padding(
                    padding: w.contentPadding,
                    child: w.content
                )
            )
        )

        // -- Assemble --
        // When not expanded, we hide the content using Offstage.
        // When animation support is complete, this will use SizeTransition instead.
        let contentOrHidden: Widget = _isExpanded
            ? contentWidget
            : Offstage(offstage: true, child: contentWidget)

        var children: [Widget]
        if _isDown {
            children = [headerWidget, contentOrHidden]
        } else {
            children = [contentOrHidden, headerWidget]
        }

        return Column(
            mainAxisSize: .min,
            crossAxisAlignment: .start,
            children: children
        )
    }
}

// MARK: - _ExpanderDecoratedBox (private helper)

/// A widget that paints a `Decoration` behind its child.
private class _ExpanderDecoratedBox: SingleChildRenderObjectWidget {
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
