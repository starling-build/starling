// Ported from: fluent_ui menu bar concept
//
// A horizontal menu bar with items that open MenuFlyout dropdowns on click.
// Similar to traditional desktop menu bars (File, Edit, View, Help).

import FlutterSwiftBridge

// MARK: - MenuBarItem

/// A single item in a MenuBar.
///
/// Each item has a text label and a list of `MenuFlyoutItemBase` entries
/// that are displayed as a dropdown when the item is clicked.
///
/// Usage:
/// ```swift
/// MenuBarItem(
///     text: Text("File"),
///     items: [
///         MenuFlyoutItem(text: Text("New"), onPressed: { ... }),
///         MenuFlyoutItem(text: Text("Open"), onPressed: { ... }),
///         MenuFlyoutSeparator(),
///         MenuFlyoutItem(text: Text("Exit"), onPressed: { ... }),
///     ]
/// )
/// ```
public class MenuBarItem {
    /// The text widget displayed as the menu bar button label.
    public let text: Widget

    /// The flyout items shown when this menu bar item is activated.
    public let items: [MenuFlyoutItemBase]

    /// Whether this menu bar item is enabled.
    public let enabled: Bool

    /// Creates a menu bar item.
    public init(
        text: Widget,
        items: [MenuFlyoutItemBase] = [],
        enabled: Bool = true
    ) {
        self.text = text
        self.items = items
        self.enabled = enabled
    }
}

// MARK: - MenuBar

/// A horizontal menu bar that displays a row of `MenuBarItem` entries.
///
/// Each item in the bar opens a `MenuFlyout` dropdown when pressed.
/// This provides a traditional desktop-style menu bar (File, Edit, View, Help).
///
/// Usage:
/// ```swift
/// MenuBar(items: [
///     MenuBarItem(text: Text("File"), items: [
///         MenuFlyoutItem(text: Text("New"), onPressed: { ... }),
///         MenuFlyoutItem(text: Text("Open"), onPressed: { ... }),
///     ]),
///     MenuBarItem(text: Text("Edit"), items: [
///         MenuFlyoutItem(text: Text("Undo"), onPressed: { ... }),
///         MenuFlyoutItem(text: Text("Redo"), onPressed: { ... }),
///     ]),
/// ])
/// ```
public class MenuBar_: StatelessWidget {
    /// The items to display in the menu bar.
    public let items: [MenuBarItem]

    /// Creates a menu bar.
    public init(
        key: (any Key)? = nil,
        items: [MenuBarItem]
    ) {
        self.items = items
        super.init(key: key)
    }

    public override func build(_ context: any BuildContext) -> Widget {
        let theme = FluentTheme.of(context)
        let res = theme.resources

        let itemWidgets: [Widget] = items.map { item in
            return _MenuBarItemWidget(item: item)
        }

        let bar: Widget = Row(
            mainAxisSize: .min,
            children: itemWidgets
        )

        // Wrap in a styled container with a subtle bottom border
        let decoration = BoxDecoration(
            color: res.solidBackgroundFillColorBase,
            border: Border(
                bottom: BorderSide(
                    color: res.surfaceStrokeColorDefault,
                    width: 1
                )
            )
        )

        return _MenuBarDecoratedBox(
            decoration: decoration,
            child: Padding(
                padding: EdgeInsets(left: 4, right: 4),
                child: bar
            )
        )
    }
}

// MARK: - _MenuBarDecoratedBox

/// A decorated box for the menu bar background.
private class _MenuBarDecoratedBox: SingleChildRenderObjectWidget {
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

// MARK: - _MenuBarItemWidget

/// Internal stateful widget for each individual menu bar item.
///
/// Manages its own `FlyoutController` to independently show/hide the dropdown
/// when pressed.
private class _MenuBarItemWidget: StatefulWidget {
    let item: MenuBarItem

    init(key: (any Key)? = nil, item: MenuBarItem) {
        self.item = item
        super.init(key: key)
    }

    override func createState() -> State<StatefulWidget> {
        return _MenuBarItemWidgetState()
    }
}

// MARK: - _MenuBarItemWidgetState

private class _MenuBarItemWidgetState: State<StatefulWidget> {
    private let _flyoutController = FlyoutController()

    private var menuBarItem: _MenuBarItemWidget {
        return widget as! _MenuBarItemWidget
    }

    override func dispose() {
        _flyoutController.closeFlyout()
        super.dispose()
    }

    override func build(_ context: any BuildContext) -> Widget {
        let item = menuBarItem.item

        let button: Widget = HoverButton(
            builder: { [weak self] context, states in
                let theme = FluentTheme.of(context)
                let res = theme.resources

                let isOpen = self?._flyoutController.isOpen ?? false

                let bgColor: Color = {
                    if states.isDisabled { return Color(0x00000000) }
                    if states.isPressed || isOpen { return res.subtleFillColorTertiary }
                    if states.isHovered { return res.subtleFillColorSecondary }
                    return Color(0x00000000)
                }()

                let fgColor: Color = {
                    if states.isDisabled { return res.textFillColorDisabled }
                    if states.isPressed { return res.textFillColorSecondary }
                    return res.textFillColorPrimary
                }()

                let bgDecoration = BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(4)
                )

                return _MenuBarItemDecoratedBox(
                    decoration: bgDecoration,
                    child: Padding(
                        padding: EdgeInsets(left: 10, top: 6, right: 10, bottom: 6),
                        child: DefaultTextStyle(
                            style: TextStyle(color: fgColor, fontSize: 13),
                            child: item.text
                        )
                    )
                )
            },
            onPressed: item.enabled ? { [weak self] in
                self?._openMenu(context)
            } : nil,
            forceEnabled: false
        )

        return FlyoutTarget(
            controller: _flyoutController,
            child: button
        )
    }

    private func _openMenu(_ context: any BuildContext) {
        let item = menuBarItem.item
        if _flyoutController.isOpen {
            _flyoutController.closeFlyout()
            return
        }
        _flyoutController.showFlyout(
            builder: { ctx in
                MenuFlyout(items: item.items)
            },
            placement: .bottomEdgeAlignedLeft,
            additionalOffset: 0
        )
    }
}

// MARK: - _MenuBarItemDecoratedBox

/// A decorated box for individual menu bar item backgrounds.
private class _MenuBarItemDecoratedBox: SingleChildRenderObjectWidget {
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
