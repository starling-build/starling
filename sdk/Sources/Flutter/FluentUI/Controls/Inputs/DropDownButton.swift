// Ported from: fluent_ui/lib/src/controls/inputs/drop_down_button.dart
//
// A button that opens a MenuFlyout dropdown when pressed. Displays an
// optional title/leading widget and a chevron indicator.

import FlutterSwiftBridge

// MARK: - DropDownButton

/// A button that, when pressed, opens a `MenuFlyout` dropdown.
///
/// The button displays an optional title and leading widget, along with a
/// chevron arrow indicating that pressing the button will reveal a menu.
///
/// Usage:
/// ```swift
/// DropDownButton(
///     title: Text("Options"),
///     items: [
///         MenuFlyoutItem(text: Text("Cut"), onPressed: { ... }),
///         MenuFlyoutSeparator(),
///         MenuFlyoutItem(text: Text("Paste"), onPressed: { ... }),
///     ]
/// )
/// ```
public class DropDownButton: StatefulWidget {
    /// The content displayed as the button label.
    public let title: Widget?

    /// An optional leading widget displayed before the title.
    public let leading: Widget?

    /// The menu items to display when the dropdown is opened.
    public let items: [MenuFlyoutItemBase]

    /// Whether this button is disabled.
    public let disabled: Bool

    /// Where to position the flyout menu. Hangs from the button's left edge
    /// by default, as WinUI's `BottomEdgeAlignedLeft`.
    public let placement: FlyoutPlacement

    /// Whether to close the flyout after an item is clicked. Defaults to `true`.
    public let closeAfterClick: Bool

    /// Creates a drop down button.
    public init(
        key: (any Key)? = nil,
        title: Widget? = nil,
        leading: Widget? = nil,
        items: [MenuFlyoutItemBase] = [],
        disabled: Bool = false,
        placement: FlyoutPlacement = .bottomEdgeAlignedLeft,
        closeAfterClick: Bool = true
    ) {
        self.title = title
        self.leading = leading
        self.items = items
        self.disabled = disabled
        self.placement = placement
        self.closeAfterClick = closeAfterClick
        super.init(key: key)
    }

    public override func createState() -> State<StatefulWidget> {
        return _DropDownButtonState()
    }
}

// MARK: - _DropDownButtonState

class _DropDownButtonState: State<StatefulWidget> {
    private let _flyoutController = FlyoutController()

    private var dropDownButton: DropDownButton {
        return widget as! DropDownButton
    }

    override func build(_ context: any BuildContext) -> Widget {
        let w = dropDownButton
        let theme = FluentTheme.of(context)

        // Build the button content row
        var rowChildren: [Widget] = []

        if let leading = w.leading {
            rowChildren.append(
                Padding(
                    padding: EdgeInsets(right: 8),
                    child: leading
                )
            )
        }

        // The title sits in the row at its own width: an `Expanded` here has
        // nothing to expand into (the row is min-sized and often unbounded),
        // and collapsed the whole button to nothing.
        if let title = w.title {
            rowChildren.append(title)
        }

        // Chevron indicator (downward arrow)
        let chevron: Widget = Padding(
            padding: EdgeInsets(left: 6),
            child: FluentGlyph(
                .chevronDown, size: 12,
                color: w.disabled
                    ? theme.resources.textFillColorDisabled
                    : theme.resources.textFillColorSecondary)
        )
        rowChildren.append(chevron)

        let buttonContent: Widget = Row(
            mainAxisSize: .min,
            children: rowChildren
        )

        let button: Widget = Button(
            onPressed: w.disabled ? nil : { [weak self] in
                self?._openFlyout(context)
            },
            child: buttonContent
        )

        return FlyoutTarget(
            controller: _flyoutController,
            child: button
        )
    }

    private func _openFlyout(_ context: any BuildContext) {
        let w = dropDownButton
        _flyoutController.showFlyout(
            builder: { ctx in
                MenuFlyout(items: w.items)
            },
            placement: w.placement
        )
    }
}
