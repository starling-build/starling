// Ported from: fluent_ui/lib/src/controls/form/combo_box.dart
//
// A drop-down list of items the user can select from. Built on top of the
// Flyout system. Supports non-editable selection (EditableComboBox requires TextBox).

import FlutterSwiftBridge

// MARK: - ComboBoxItem

/// A single item in a `ComboBox`.
///
/// Wraps a value with a display widget. The `value` is used for comparison
/// when determining the selected item.
public class ComboBoxItem<T: Equatable>: MenuFlyoutItemBase {
    /// The value this item represents.
    public let value: T

    /// The widget to display for this item.
    public let child: Widget

    /// Whether this item is enabled.
    public let enabled: Bool

    /// Called when this item is pressed.
    public let onTap: (() -> Void)?

    /// Creates a combo box item.
    public init(
        key: (any Key)? = nil,
        value: T,
        enabled: Bool = true,
        onTap: (() -> Void)? = nil,
        child: Widget
    ) {
        self.value = value
        self.enabled = enabled
        self.onTap = onTap
        self.child = child
        super.init(key: key)
    }

    public override func buildItem(_ context: any BuildContext) -> Widget {
        // Used internally by MenuFlyout rendering
        return child
    }
}

// MARK: - ComboBox

/// A drop-down control for selecting a value from a list.
///
/// When pressed, opens a flyout listing all available items. The selected item
/// is highlighted. When the user picks a different item, `onChanged` is called.
///
/// Usage:
/// ```swift
/// ComboBox<String>(
///     value: selectedItem,
///     items: [
///         ComboBoxItem(value: "A", child: Text("Option A")),
///         ComboBoxItem(value: "B", child: Text("Option B")),
///         ComboBoxItem(value: "C", child: Text("Option C")),
///     ],
///     onChanged: { newValue in
///         setState { selectedItem = newValue }
///     }
/// )
/// ```
public class ComboBox<T: Equatable>: StatefulWidget {
    /// The currently selected value. If nil, the `placeholder` is shown.
    public let value: T?

    /// All the items in this combo box.
    public let items: [ComboBoxItem<T>]

    /// Called when the user selects a different item.
    /// If nil, the combo box is considered disabled.
    public let onChanged: ((T?) -> Void)?

    /// Widget displayed when `value` is nil.
    public let placeholder: Widget?

    /// What the box is called, for key tips and screen readers.
    public let semanticLabel: String?

    /// Whether to close the flyout after selecting an item.
    public let closeAfterClick: Bool

    /// The placement for the flyout popup.
    public let placement: FlyoutPlacement

    /// The icon widget shown on the trailing edge (typically a chevron).
    public let icon: Widget?

    /// Whether the icon is enabled/shown.
    public let iconEnabledColor: Color?

    /// Whether the icon is disabled/shown.
    public let iconDisabledColor: Color?

    /// Additional size for the icon area.
    public let iconSize: Double

    /// Creates a combo box.
    public init(
        key: (any Key)? = nil,
        value: T? = nil,
        items: [ComboBoxItem<T>] = [],
        onChanged: ((T?) -> Void)? = nil,
        placeholder: Widget? = nil,
        closeAfterClick: Bool = true,
        placement: FlyoutPlacement = .bottom,
        icon: Widget? = nil,
        iconEnabledColor: Color? = nil,
        iconDisabledColor: Color? = nil,
        iconSize: Double = 8.0,
        semanticLabel: String? = nil
    ) {
        self.semanticLabel = semanticLabel
        self.value = value
        self.items = items
        self.onChanged = onChanged
        self.placeholder = placeholder
        self.closeAfterClick = closeAfterClick
        self.placement = placement
        self.icon = icon
        self.iconEnabledColor = iconEnabledColor
        self.iconDisabledColor = iconDisabledColor
        self.iconSize = iconSize
        super.init(key: key)
    }

    public override func createState() -> State<StatefulWidget> {
        return _ComboBoxState<T>()
    }
}

// MARK: - _ComboBoxState

class _ComboBoxState<T: Equatable>: State<StatefulWidget> {
    let _flyoutController = FlyoutController()

    private var comboBox: ComboBox<T> {
        widget as! ComboBox<T>
    }

    var isDisabled: Bool {
        comboBox.onChanged == nil
    }

    override func dispose() {
        _flyoutController.closeFlyout()
        super.dispose()
    }

    // MARK: - Open/Close

    func _openPopup() {
        guard !isDisabled else { return }

        _flyoutController.showFlyout(
            builder: { [self] context in
                _buildDropdown(context)
            },
            placement: comboBox.placement,
            additionalOffset: 4.0
        )
    }

    func _buildDropdown(_ context: any BuildContext) -> Widget {
        let menuItems: [MenuFlyoutItemBase] = comboBox.items.map { item in
            let isSelected = comboBox.value != nil && item.value == comboBox.value!
            return _ComboBoxMenuItem(
                text: item.child,
                selected: isSelected,
                enabled: item.enabled,
                onPressed: { [self] in
                    comboBox.onChanged?(item.value)
                    item.onTap?()
                    if comboBox.closeAfterClick {
                        _flyoutController.closeFlyout()
                    }
                }
            )
        }

        return MenuFlyout(items: menuItems)
    }

    // MARK: - Build

    override func build(_ context: any BuildContext) -> Widget {
        let theme = FluentTheme.of(context)

        // Find the selected item's widget for display
        let selectedChild: Widget?
        if let value = comboBox.value {
            selectedChild = comboBox.items.first(where: { $0.value == value })?.child
        } else {
            selectedChild = nil
        }

        // Display content: selected item or placeholder
        let displayWidget: Widget
        if let child = selectedChild {
            displayWidget = child
        } else if let placeholder = comboBox.placeholder {
            displayWidget = DefaultTextStyle(
                style: TextStyle(
                    color: theme.resources.textFillColorSecondary
                ),
                child: placeholder
            )
        } else {
            displayWidget = SizedBox(width: 0, height: 0)
        }

        // Chevron icon
        let chevron: Widget = comboBox.icon ?? _ComboBoxChevron(
            color: isDisabled
                ? (comboBox.iconDisabledColor ?? theme.resources.textFillColorDisabled)
                : (comboBox.iconEnabledColor ?? theme.resources.textFillColorSecondary),
            size: comboBox.iconSize
        )

        // Build the button content
        let content: Widget = Row(children: [
            Expanded(child: displayWidget),
            Padding(
                padding: EdgeInsets(left: 8),
                child: chevron
            ),
        ])

        let buttonContent: Widget = DecoratedBox(
            decoration: BoxDecoration(
                color: isDisabled
                    ? theme.resources.controlFillColorDisabled
                    : theme.resources.controlFillColorDefault,
                border: Border.all(
                    color: theme.resources.controlStrokeColorDefault,
                    width: 1
                ),
                borderRadius: BorderRadius.circular(4)
            ),
            child: Padding(
                padding: EdgeInsets(left: 12, top: 6, right: 8, bottom: 6),
                child: content
            )
        )

        return FlyoutTarget(
            controller: _flyoutController,
            child: HoverButton(
                builder: { context, states in
                    buttonContent
                },
                onPressed: isDisabled ? nil : { [self] in _openPopup() },
                semanticLabel: comboBox.semanticLabel
            )
        )
    }
}

// MARK: - _ComboBoxMenuItem

/// Internal menu item used in the ComboBox dropdown.
private class _ComboBoxMenuItem: MenuFlyoutItemBase {
    let text: Widget
    let selected: Bool
    let enabled: Bool
    let onPressed: () -> Void

    init(
        text: Widget,
        selected: Bool,
        enabled: Bool,
        onPressed: @escaping () -> Void
    ) {
        self.text = text
        self.selected = selected
        self.enabled = enabled
        self.onPressed = onPressed
        super.init()
    }

    override func buildItem(_ context: any BuildContext) -> Widget {
        return FlyoutListTile(
            onPressed: enabled ? { [self] in onPressed() } : nil,
            text: text,
            margin: EdgeInsets(),
            selected: selected,
            showSelectedIndicator: true
        )
    }
}

// MARK: - _ComboBoxChevron

/// A simple chevron/arrow indicator for the ComboBox.
private class _ComboBoxChevron: StatelessWidget {
    let color: Color
    let size: Double

    init(
        color: Color,
        size: Double
    ) {
        self.color = color
        self.size = size
        super.init()
    }

    override func build(_ context: any BuildContext) -> Widget {
        // Simple downward-pointing triangle indicator using a custom-painted widget
        return SizedBox(
            width: size,
            height: size,
            child: CustomPaint(
                painter: _ChevronPainter(color: color)
            )
        )
    }
}

// MARK: - _ChevronPainter

/// Paints a simple downward chevron.
private class _ChevronPainter: CustomPainter {
    let color: Color

    init(color: Color) {
        self.color = color
    }

    override func paint(_ canvas: any Canvas, _ size: Size) {
        let paint = Paint()
        paint.color = color
        paint.strokeWidth = 1.5
        paint.style = .stroke

        let path = Path()
        // Draw a "V" shape for a down chevron
        path.moveTo(0, size.height * 0.25)
        path.lineTo(size.width * 0.5, size.height * 0.75)
        path.lineTo(size.width, size.height * 0.25)

        canvas.drawPath(path, paint)
    }

    override func shouldRepaint(_ oldDelegate: CustomPainter) -> Bool {
        if let old = oldDelegate as? _ChevronPainter {
            return old.color != color
        }
        return true
    }
}
