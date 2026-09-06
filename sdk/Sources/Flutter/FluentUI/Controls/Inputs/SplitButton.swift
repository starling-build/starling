// Ported from: fluent_ui/lib/src/controls/inputs/split_button.dart
//
// A two-part button: the left side performs a primary action and the right side
// opens a flyout dropdown. A vertical separator divides the two areas.

import FlutterSwiftBridge

// MARK: - SplitButton

/// A split button with a primary action on the left and a dropdown arrow on the
/// right that opens a flyout.
///
/// The left area triggers `onPressed`, while the right area opens the provided
/// `flyout` content via a `FlyoutController`.
///
/// Usage:
/// ```swift
/// SplitButton(
///     child: Text("Save"),
///     onPressed: { save() },
///     flyout: MenuFlyout(items: [
///         MenuFlyoutItem(text: Text("Save As..."), onPressed: { saveAs() }),
///     ])
/// )
/// ```
public class SplitButton: StatefulWidget {
    /// The primary button content (left side).
    public let child: Widget

    /// The flyout content displayed when the dropdown arrow is pressed.
    public let flyout: FlyoutContent?

    /// Called when the primary (left) side is pressed.
    public let onPressed: (() -> Void)?

    /// Whether the entire split button is disabled.
    public let disabled: Bool

    /// Where to position the flyout. Defaults to `.auto`.
    public let placement: FlyoutPlacement

    /// Creates a split button.
    public init(
        key: (any Key)? = nil,
        child: Widget,
        flyout: FlyoutContent? = nil,
        onPressed: (() -> Void)? = nil,
        disabled: Bool = false,
        placement: FlyoutPlacement = .auto
    ) {
        self.child = child
        self.flyout = flyout
        self.onPressed = onPressed
        self.disabled = disabled
        self.placement = placement
        super.init(key: key)
    }

    public override func createState() -> State<StatefulWidget> {
        return _SplitButtonState()
    }
}

// MARK: - _SplitButtonState

class _SplitButtonState: State<StatefulWidget> {
    private let _flyoutController = FlyoutController()

    private var splitButton: SplitButton {
        return widget as! SplitButton
    }

    override func build(_ context: any BuildContext) -> Widget {
        let w = splitButton
        let theme = FluentTheme.of(context)
        let res = theme.resources
        let isDisabled = w.disabled || (w.onPressed == nil && w.flyout == nil)

        let borderColor = isDisabled
            ? res.controlStrokeColorDefault
            : res.controlStrokeColorDefault
        let borderRadius = BorderRadius.circular(4)

        // -- Primary button (left side) --
        let primaryButton: Widget = HoverButton(
            builder: { context, states in
                let bgColor: Color = Set<WidgetState>.forStates(
                    states,
                    disabled: res.controlFillColorDisabled,
                    none: res.controlFillColorDefault,
                    pressed: res.controlFillColorTertiary,
                    hovering: res.controlFillColorSecondary
                )
                let fgColor: Color = isDisabled
                    ? res.textFillColorDisabled
                    : res.textFillColorPrimary

                return _SplitButtonDecoratedBox(
                    decoration: BoxDecoration(
                        color: bgColor,
                        border: Border.all(color: borderColor),
                        borderRadius: BorderRadius.only(
                            topLeft: borderRadius.topLeft,
                            bottomLeft: borderRadius.bottomLeft
                        )
                    ),
                    child: Padding(
                        padding: EdgeInsets(left: 11, top: 5, right: 11, bottom: 6),
                        child: DefaultTextStyle(
                            style: TextStyle(color: fgColor, fontSize: 14),
                            child: Center(
                                widthFactor: 1,
                                heightFactor: 1,
                                child: w.child
                            )
                        )
                    )
                )
            },
            onPressed: isDisabled ? nil : w.onPressed
        )

        // -- Vertical separator --
        let separator: Widget = SizedBox(
            width: 1,
            child: ColoredBox(color: borderColor)
        )

        // -- Dropdown arrow button (right side) --
        let arrowButton: Widget = HoverButton(
            builder: { context, states in
                let bgColor: Color = Set<WidgetState>.forStates(
                    states,
                    disabled: res.controlFillColorDisabled,
                    none: res.controlFillColorDefault,
                    pressed: res.controlFillColorTertiary,
                    hovering: res.controlFillColorSecondary
                )
                let arrowColor: Color = isDisabled
                    ? res.textFillColorDisabled
                    : res.textFillColorSecondary

                return _SplitButtonDecoratedBox(
                    decoration: BoxDecoration(
                        color: bgColor,
                        border: Border.all(color: borderColor),
                        borderRadius: BorderRadius.only(
                            topRight: borderRadius.topRight,
                            bottomRight: borderRadius.bottomRight
                        )
                    ),
                    child: Padding(
                        padding: EdgeInsets(left: 6, top: 5, right: 6, bottom: 6),
                        child: Center(
                            widthFactor: 1,
                            heightFactor: 1,
                            child: FluentGlyph(.chevronDown, size: 12, color: arrowColor)
                        )
                    )
                )
            },
            onPressed: (isDisabled || w.flyout == nil) ? nil : { [weak self] in
                self?._openFlyout(context)
            }
        )

        // Assemble the split button as a Row inside a FlyoutTarget
        let row: Widget = IntrinsicHeight(
            child: Row(
                mainAxisSize: .min,
                crossAxisAlignment: .stretch,
                children: [
                    primaryButton,
                    separator,
                    arrowButton,
                ]
            )
        )

        return FlyoutTarget(
            controller: _flyoutController,
            child: row
        )
    }

    private func _openFlyout(_ context: any BuildContext) {
        let w = splitButton
        guard let flyout = w.flyout else { return }
        _flyoutController.showFlyout(
            builder: { _ in
                flyout
            },
            placement: w.placement
        )
    }
}

// MARK: - _SplitButtonDecoratedBox

/// A decorated box used by the SplitButton halves.
private class _SplitButtonDecoratedBox: SingleChildRenderObjectWidget {
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
