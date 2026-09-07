// Ported from: fluent_ui/lib/src/controls/surfaces/command_bar.dart
//
// A command bar displays a horizontal row of command items (buttons, separators)
// with optional overflow into a secondary menu flyout.

import FlutterSwiftBridge

// MARK: - CommandBarItemDisplayMode

/// Determines how a command bar item is rendered based on its location.
public enum CommandBarItemDisplayMode {
    /// The item is displayed in the primary (visible) row.
    case inPrimary

    /// The item is displayed in the secondary (overflow) menu.
    case inSecondary
}

// MARK: - CommandBarItem

/// Abstract base class for items that can appear in a `CommandBar`.
///
/// Subclasses must implement `build(context:displayMode:)` to produce the
/// widget representation of the item.
open class CommandBarItem {
    /// An optional key for identifying this item.
    public let key: (any Key)?

    /// The `CommandBarFlyout` this item is being built for, stamped by that
    /// flyout as `MenuFlyout` stamps its own items. Invoking a command
    /// dismisses the flyout it came from, which is WinUI's behaviour; an
    /// item in a plain `CommandBar` has none and dismisses nothing.
    var _flyout: _CommandBarFlyoutState?

    /// Creates a command bar item.
    public init(key: (any Key)? = nil) {
        self.key = key
    }

    /// Builds the widget for this item in the given display mode.
    ///
    /// - Parameters:
    ///   - context: The build context.
    ///   - displayMode: Whether the item appears in the primary row or the
    ///     secondary overflow menu.
    /// - Returns: A widget representing this item.
    open func build(context: any BuildContext, displayMode: CommandBarItemDisplayMode) -> Widget {
        fatalError("Subclasses must override build(context:displayMode:)")
    }
}

// MARK: - CommandBarButton

/// A command bar item that displays an icon and/or label with an action.
///
/// When displayed in the primary row, it renders as a subtle button with
/// icon and optional label side-by-side. When displayed in the secondary
/// overflow menu, it renders as a `MenuFlyoutItem`.
///
/// Usage:
/// ```swift
/// CommandBarButton(
///     icon: Text("\u{2702}"),
///     label: Text("Cut"),
///     onPressed: { print("Cut") }
/// )
/// ```
public class CommandBarButton: CommandBarItem {
    /// The icon widget. Typically an `Icon` or `Text` with a symbol.
    public let icon: Widget?

    /// The text label displayed beside the icon.
    public let label: Widget?

    /// Called when the button is pressed. If nil, the button is disabled.
    public let onPressed: (() -> Void)?

    /// A tooltip message displayed on hover.
    public let tooltip: String?

    /// Creates a command bar button.
    public init(
        key: (any Key)? = nil,
        icon: Widget? = nil,
        label: Widget? = nil,
        onPressed: (() -> Void)? = nil,
        tooltip: String? = nil
    ) {
        self.icon = icon
        self.label = label
        self.onPressed = onPressed
        self.tooltip = tooltip
        super.init(key: key)
    }

    public override func build(context: any BuildContext, displayMode: CommandBarItemDisplayMode) -> Widget {
        switch displayMode {
        case .inPrimary:
            return _buildPrimaryButton(context)
        case .inSecondary:
            return _buildSecondaryItem(context)
        }
    }

    /// Builds the primary row representation: a subtle button with icon + label.
    private func _buildPrimaryButton(_ context: any BuildContext) -> Widget {
        let theme = FluentTheme.of(context)
        let res = theme.resources

        var button: Widget = HoverButton(
            builder: { [self] context, states in
                let isDisabled = onPressed == nil
                let foregroundColor: Color = {
                    if isDisabled { return res.textFillColorDisabled }
                    if states.isPressed { return res.textFillColorSecondary }
                    return res.textFillColorPrimary
                }()

                let bgColor: Color = {
                    if isDisabled || states.isNone { return Color(0x00000000) }
                    if states.isPressed { return res.subtleFillColorTertiary }
                    if states.isHovered { return res.subtleFillColorSecondary }
                    return Color(0x00000000)
                }()

                // Build icon + label row
                var rowChildren: [Widget] = []

                if let icon = icon {
                    rowChildren.append(
                        IconTheme(
                            data: IconThemeData(size: 16, color: foregroundColor),
                            child: DefaultTextStyle(
                                style: TextStyle(color: foregroundColor, fontSize: 14),
                                child: icon
                            )
                        )
                    )
                }

                if let label = label {
                    if icon != nil {
                        rowChildren.append(SizedBox(width: 8))
                    }
                    rowChildren.append(
                        DefaultTextStyle(
                            style: TextStyle(color: foregroundColor, fontSize: 12),
                            child: label
                        )
                    )
                }

                let content: Widget = Padding(
                    padding: EdgeInsets(left: 10, top: 6, right: 10, bottom: 6),
                    child: Row(
                        mainAxisSize: .min,
                        crossAxisAlignment: .center,
                        children: rowChildren
                    )
                )

                return _CommandBarDecoratedBox(
                    decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(4)
                    ),
                    child: content
                )
            },
            onPressed: _invoke
        )

        if let tooltip = tooltip {
            button = Tooltip(message: tooltip, child: button)
        }

        return button
    }

    /// The press: the command, and then the flyout it was invoked from
    /// goes away, as WinUI's does. nil for a disabled command, so the
    /// button stays inert rather than dismissing on a dead click.
    var _invoke: (() -> Void)? {
        guard let onPressed else { return nil }
        return { [self] in
            onPressed()
            _flyout?.commandInvoked()
        }
    }

    /// Builds the secondary (overflow menu) representation as a MenuFlyoutItem-style tile.
    private func _buildSecondaryItem(_ context: any BuildContext) -> Widget {
        return FlyoutListTile(
            onPressed: _invoke,
            // A fixed 16pt slot, WinUI's icon size: a command with no icon
            // then reserves the same column and every label starts at the
            // same x, which is what `MenuFlyout` does for its own items.
            icon: SizedBox(width: 16, height: 16, child: Center(child: icon ?? SizedBox(width: 0, height: 0))),
            text: label ?? SizedBox(width: 0, height: 0),
            margin: EdgeInsets()
        )
    }
}

// MARK: - CommandBarSeparator

/// A vertical divider used to separate groups of command bar items.
///
/// When displayed in the primary row, renders as a vertical line.
/// When displayed in the secondary overflow menu, renders as a horizontal
/// `MenuFlyoutSeparator`.
public class CommandBarSeparator: CommandBarItem {

    /// Creates a command bar separator.
    public override init(key: (any Key)? = nil) {
        super.init(key: key)
    }

    public override func build(context: any BuildContext, displayMode: CommandBarItemDisplayMode) -> Widget {
        switch displayMode {
        case .inPrimary:
            return Padding(
                padding: EdgeInsets(left: 4, top: 6, right: 4, bottom: 6),
                child: SizedBox(
                    height: 20,
                    child: Divider(
                        direction: .vertical,
                        size: 20
                    )
                )
            )
        case .inSecondary:
            return MenuFlyoutSeparator().buildItem(context)
        }
    }
}

// MARK: - CommandBar

/// A horizontal toolbar that displays a row of command items.
///
/// Primary items are shown in a horizontal `Row`. If `secondaryItems` are
/// provided, an overflow "..." button is appended that opens a `MenuFlyout`
/// with the secondary items rendered in their `.inSecondary` display mode.
///
/// Usage:
/// ```swift
/// CommandBar(
///     primaryItems: [
///         CommandBarButton(icon: Text("N"), label: Text("New"), onPressed: { ... }),
///         CommandBarSeparator(),
///         CommandBarButton(icon: Text("S"), label: Text("Save"), onPressed: { ... }),
///     ],
///     secondaryItems: [
///         CommandBarButton(icon: Text("P"), label: Text("Print"), onPressed: { ... }),
///     ]
/// )
/// ```
public class CommandBar: StatefulWidget {

    /// The items displayed in the primary (visible) row.
    public let primaryItems: [CommandBarItem]

    /// Optional items displayed in the overflow flyout menu.
    ///
    /// If non-nil and non-empty, an overflow button ("...") is appended to
    /// the primary row. Pressing it opens a `MenuFlyout` with these items.
    public let secondaryItems: [CommandBarItem]?

    /// The direction of the primary items layout. Defaults to `.horizontal`.
    public let direction: Axis

    /// The main axis alignment for the primary row. Defaults to `.start`.
    public let mainAxisAlignment: MainAxisAlignment

    /// Creates a command bar.
    public init(
        key: (any Key)? = nil,
        primaryItems: [CommandBarItem] = [],
        secondaryItems: [CommandBarItem]? = nil,
        direction: Axis = .horizontal,
        mainAxisAlignment: MainAxisAlignment = .start
    ) {
        self.primaryItems = primaryItems
        self.secondaryItems = secondaryItems
        self.direction = direction
        self.mainAxisAlignment = mainAxisAlignment
        super.init(key: key)
    }

    public override func createState() -> State<StatefulWidget> {
        return _CommandBarState()
    }
}

// MARK: - _CommandBarState

class _CommandBarState: State<StatefulWidget> {

    private let _overflowController = FlyoutController()

    private var commandBar: CommandBar {
        return widget as! CommandBar
    }

    override func dispose() {
        _overflowController.closeFlyout()
        super.dispose()
    }

    override func build(_ context: any BuildContext) -> Widget {
        let theme = FluentTheme.of(context)
        let res = theme.resources
        let w = commandBar

        // Build primary item widgets
        var rowChildren: [Widget] = w.primaryItems.map { item in
            item.build(context: context, displayMode: .inPrimary)
        }

        // Add overflow button if secondary items exist
        let hasSecondary = w.secondaryItems != nil && !w.secondaryItems!.isEmpty
        if hasSecondary {
            let overflowButton = _buildOverflowButton(context)
            rowChildren.append(overflowButton)
        }

        // Wrap in a decorated bar container
        let barDecoration = BoxDecoration(
            color: res.controlFillColorDefault,
            border: Border.all(
                color: res.controlStrokeColorDefault,
                width: 0.5
            ),
            borderRadius: BorderRadius.circular(4)
        )

        let itemsRow: Widget
        if w.direction == .horizontal {
            itemsRow = Row(
                mainAxisAlignment: w.mainAxisAlignment,
                mainAxisSize: .min,
                crossAxisAlignment: .center,
                children: rowChildren
            )
        } else {
            itemsRow = Column(
                mainAxisAlignment: w.mainAxisAlignment,
                mainAxisSize: .min,
                crossAxisAlignment: .center,
                children: rowChildren
            )
        }

        return _CommandBarDecoratedBox(
            decoration: barDecoration,
            child: Padding(
                padding: EdgeInsets(left: 4, top: 2, right: 4, bottom: 2),
                child: itemsRow
            )
        )
    }

    // MARK: - Overflow Button

    /// Builds the "..." overflow button that opens the secondary items flyout.
    private func _buildOverflowButton(_ context: any BuildContext) -> Widget {
        let theme = FluentTheme.of(context)
        let res = theme.resources

        let button: Widget = HoverButton(
            builder: { context, states in
                let foregroundColor: Color = {
                    if states.isPressed { return res.textFillColorSecondary }
                    return res.textFillColorPrimary
                }()

                let bgColor: Color = {
                    if states.isNone { return Color(0x00000000) }
                    if states.isPressed { return res.subtleFillColorTertiary }
                    if states.isHovered { return res.subtleFillColorSecondary }
                    return Color(0x00000000)
                }()

                return _CommandBarDecoratedBox(
                    decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(4)
                    ),
                    child: Padding(
                        padding: EdgeInsets(left: 10, top: 6, right: 10, bottom: 6),
                        child: FluentGlyph(.more, size: 16, color: foregroundColor)
                    )
                )
            },
            onPressed: { [weak self] in
                self?._showOverflow(context)
            }
        )

        return FlyoutTarget(
            controller: _overflowController,
            child: button
        )
    }

    /// Opens the overflow flyout with secondary items.
    private func _showOverflow(_ context: any BuildContext) {
        guard let secondaryItems = commandBar.secondaryItems, !secondaryItems.isEmpty else {
            return
        }

        _overflowController.showFlyout(
            builder: { [weak self] ctx in
                guard let self = self else { return SizedBox(width: 0, height: 0) }

                // Convert CommandBarItems to MenuFlyoutItemBase for the flyout
                let menuItems: [MenuFlyoutItemBase] = secondaryItems.map { item in
                    _CommandBarMenuAdapter(item: item)
                }

                return MenuFlyout(items: menuItems)
            },
            placement: .bottom
        )
    }
}

// MARK: - _CommandBarMenuAdapter

/// Adapts a `CommandBarItem` for display as a `MenuFlyoutItemBase` inside the
/// overflow flyout. Delegates to the item's `.inSecondary` build method.
private class _CommandBarMenuAdapter: MenuFlyoutItemBase {
    let item: CommandBarItem

    init(item: CommandBarItem) {
        self.item = item
        super.init()
    }

    override func buildItem(_ context: any BuildContext) -> Widget {
        return item.build(context: context, displayMode: .inSecondary)
    }
}

// MARK: - CommandBarThemeData

/// Theme data for controlling the default appearance of `CommandBar` widgets.
public class CommandBarThemeData {
    /// The background color of the command bar.
    public let backgroundColor: Color?

    /// The border color of the command bar.
    public let borderColor: Color?

    /// The border radius of the command bar.
    public let borderRadius: BorderRadius?

    /// The padding inside the command bar.
    public let padding: EdgeInsets?

    /// Creates command bar theme data.
    public init(
        backgroundColor: Color? = nil,
        borderColor: Color? = nil,
        borderRadius: BorderRadius? = nil,
        padding: EdgeInsets? = nil
    ) {
        self.backgroundColor = backgroundColor
        self.borderColor = borderColor
        self.borderRadius = borderRadius
        self.padding = padding
    }

    /// Creates the standard theme data based on the given theme.
    public static func standard(_ theme: FluentThemeData) -> CommandBarThemeData {
        return CommandBarThemeData(
            borderRadius: BorderRadius.circular(4),
            padding: EdgeInsets(left: 4, top: 2, right: 4, bottom: 2)
        )
    }

    /// Merge this theme data with another, with the other taking precedence.
    public func merge(_ other: CommandBarThemeData?) -> CommandBarThemeData {
        guard let other = other else { return self }
        return CommandBarThemeData(
            backgroundColor: other.backgroundColor ?? backgroundColor,
            borderColor: other.borderColor ?? borderColor,
            borderRadius: other.borderRadius ?? borderRadius,
            padding: other.padding ?? padding
        )
    }
}

// MARK: - CommandBarTheme

/// An inherited theme that controls how descendant `CommandBar` widgets look.
public class CommandBarTheme: InheritedTheme {
    /// The theme data for the command bar theme.
    public let data: CommandBarThemeData

    public init(key: (any Key)? = nil, data: CommandBarThemeData, child: Widget) {
        self.data = data
        super.init(key: key, child: child)
    }

    /// Returns the closest `CommandBarThemeData` which encloses the given context.
    public static func of(_ context: any BuildContext) -> CommandBarThemeData {
        let theme = FluentTheme.of(context)
        let inherited = context.dependOnInheritedWidgetOfExactType(CommandBarTheme.self)
        return CommandBarThemeData.standard(theme).merge(inherited?.data)
    }

    public override func updateShouldNotify(_ oldWidget: InheritedWidget) -> Bool {
        guard let old = oldWidget as? CommandBarTheme else { return true }
        return data !== old.data
    }

    public override func wrap(_ context: any BuildContext, _ child: Widget) -> Widget {
        return CommandBarTheme(data: data, child: child)
    }
}

// MARK: - _CommandBarDecoratedBox (private helper)

/// A widget that paints a `Decoration` behind its child.
private class _CommandBarDecoratedBox: SingleChildRenderObjectWidget {
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
