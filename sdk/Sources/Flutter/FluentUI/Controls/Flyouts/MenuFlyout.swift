// Ported from: fluent_ui/lib/src/controls/flyouts/menu_flyout.dart
//
// Menu flyouts display a list of commands or options when triggered by the user.
// Built on top of the Flyout system, MenuFlyout provides standard menu items,
// separators, and hover feedback.

import FlutterSwiftBridge

// MARK: - Constants

/// Default padding for MenuFlyout content.
public let kDefaultMenuFlyoutPadding = EdgeInsets(top: 2, bottom: 2)

/// Default margin around each item in a MenuFlyout.
public let kDefaultMenuFlyoutItemMargin = EdgeInsets(left: 4, top: 2, right: 4, bottom: 2)

// MARK: - MenuFlyoutItemBase

/// Abstract base class for items that can appear in a `MenuFlyout`.
///
/// Subclasses must implement `buildItem(_:)` to produce the widget for the item.
open class MenuFlyoutItemBase {
    /// An optional key for identifying this item.
    public let key: (any Key)?

    /// The menu this item was last built into; set by `MenuFlyout` so the
    /// items can share the one-submenu-at-a-time rule.
    weak var _menu: _MenuFlyoutState?

    /// Creates a menu flyout item base.
    public init(key: (any Key)? = nil) {
        self.key = key
    }

    /// Builds the widget representation of this item.
    open func buildItem(_ context: any BuildContext) -> Widget {
        fatalError("Subclasses must override buildItem(_:)")
    }
}

// MARK: - MenuFlyoutItem

/// A standard interactive menu item for use inside a `MenuFlyout`.
///
/// Displays a text label with optional leading and trailing widgets.
/// Wraps in a `FlyoutListTile` for hover/press feedback.
///
/// Usage:
/// ```swift
/// MenuFlyoutItem(
///     text: Text("Cut"),
///     leading: Icon(Icons.cut),
///     onPressed: { print("Cut tapped") }
/// )
/// ```
public class MenuFlyoutItem: MenuFlyoutItemBase {
    /// The leading widget, displayed before `text`. Typically an icon.
    public let leading: Widget?

    /// The primary text widget.
    public let text: Widget

    /// The trailing widget, displayed after `text`.
    public let trailing: Widget?

    /// Called when the item is pressed. If nil, the item is disabled.
    public let onPressed: (() -> Void)?

    /// Called when the item is long pressed.
    public let onLongPress: (() -> Void)?

    /// Whether this item is selected.
    public let selected: Bool

    /// Whether pressing this item closes the parent flyout.
    public let closeAfterClick: Bool

    /// Whether to use an icon placeholder when no leading is provided.
    /// Set internally by `MenuFlyout` when other items have icons.
    var _useIconPlaceholder: Bool = false

    /// Creates a menu flyout item.
    public init(
        key: (any Key)? = nil,
        text: Widget,
        leading: Widget? = nil,
        trailing: Widget? = nil,
        onPressed: (() -> Void)? = nil,
        onLongPress: (() -> Void)? = nil,
        selected: Bool = false,
        closeAfterClick: Bool = true
    ) {
        self.leading = leading
        self.text = text
        self.trailing = trailing
        self.onPressed = onPressed
        self.onLongPress = onLongPress
        self.selected = selected
        self.closeAfterClick = closeAfterClick
        super.init(key: key)
    }

    public override func buildItem(_ context: any BuildContext) -> Widget {
        let resolvedLeading: Widget? = leading ?? (_useIconPlaceholder ? SizedBox(width: 16, height: 16) : nil)

        let resolvedTrailing: Widget = trailing ?? SizedBox(width: 0, height: 0)

        return FlyoutListTile(
            onPressed: onPressed == nil ? nil : { [weak self] in
                guard let self = self else { return }
                if self.closeAfterClick { _closeMenus(context) }
                self.onPressed?()
            },
            onLongPress: onLongPress,
            icon: resolvedLeading,
            text: text,
            trailing: resolvedTrailing,
            margin: EdgeInsets(),
            selected: selected,
            showSelectedIndicator: false,
            onPointerEnter: { [weak self] _ in
                guard let self else { return }
                self._menu?._hovered(self)
            },
            onPointerExit: { [weak self] _ in
                guard let self else { return }
                self._menu?._left(self)
            }
        )
    }
}

// MARK: - MenuFlyoutSeparator

/// A horizontal divider line for separating groups of items in a `MenuFlyout`.
public class MenuFlyoutSeparator: MenuFlyoutItemBase {
    /// Creates a menu flyout separator.
    public override init(key: (any Key)? = nil) {
        super.init(key: key)
    }

    public override func buildItem(_ context: any BuildContext) -> Widget {
        return Padding(
            padding: EdgeInsets(bottom: 5),
            child: Divider(
                style: DividerThemeData(
                    horizontalMargin: EdgeInsets()
                )
            )
        )
    }
}

// MARK: - MenuFlyout

/// A flyout that displays a list of menu items.
///
/// `MenuFlyout` is designed to be used as the builder content for a
/// `FlyoutController.showFlyout`. It renders a column of `MenuFlyoutItemBase`
/// items inside a styled `FlyoutContent` container.
///
/// Usage:
/// ```swift
/// controller.showFlyout(builder: { context in
///     MenuFlyout(items: [
///         MenuFlyoutItem(text: Text("Open"), onPressed: { ... }),
///         MenuFlyoutSeparator(),
///         MenuFlyoutItem(text: Text("Delete"), onPressed: { ... }),
///     ])
/// })
/// ```
public class MenuFlyout: StatefulWidget {
    /// The list of items to display in the menu.
    public let items: [MenuFlyoutItemBase]

    /// The background color of the menu container.
    public let color: Color?

    /// The shadow color.
    public let shadowColor: Color

    /// The elevation for the shadow.
    public let elevation: Double

    /// Additional constraints for the menu container.
    public let constraints: BoxConstraints

    /// The margin around each menu item.
    public let itemMargin: EdgeInsets

    /// Creates a menu flyout.
    public init(
        key: (any Key)? = nil,
        items: [MenuFlyoutItemBase] = [],
        color: Color? = nil,
        shadowColor: Color = Color(0xFF000000),
        elevation: Double = FluentElevation.flyout,
        constraints: BoxConstraints = kFlyoutMinConstraints,
        itemMargin: EdgeInsets = kDefaultMenuFlyoutItemMargin
    ) {
        self.items = items
        self.color = color
        self.shadowColor = shadowColor
        self.elevation = elevation
        self.constraints = constraints
        self.itemMargin = itemMargin
        super.init(key: key)
    }

    public override func createState() -> State<StatefulWidget> {
        return _MenuFlyoutState()
    }
}

// MARK: - _MenuFlyoutState

class _MenuFlyoutState: State<StatefulWidget> {
    private var menuFlyout: MenuFlyout {
        return widget as! MenuFlyout
    }

    /// The submenu open under this menu, if any. Windows keeps one: hovering
    /// another item for the menu delay closes it, hovering a different
    /// submenu's item swaps it.
    fileprivate weak var _openSub: _MenuFlyoutSubItemWidgetState?
    private let _closeDelay = FluentDelay()

    /// The pointer came onto `item`. An open submenu that is not this
    /// item's closes after the menu delay, so a diagonal move into the
    /// submenu across the items below is not a close.
    func _hovered(_ item: MenuFlyoutItemBase) {
        guard let open = _openSub, open.subItemWidget.subItem !== item else {
            _closeDelay.cancel()
            return
        }
        _closeDelay.schedule(after: FluentMotion.menuShowDelay) { [weak self] in
            self?._openSub?._close()
        }
    }

    /// The pointer left `item` before the delay ran out: nothing closes.
    func _left(_ item: MenuFlyoutItemBase) {
        _closeDelay.cancel()
    }

    fileprivate func _subOpened(_ sub: _MenuFlyoutSubItemWidgetState) {
        if let open = _openSub, open !== sub { open._close() }
        _openSub = sub
        _closeDelay.cancel()
    }

    override func dispose() {
        _closeDelay.cancel()
        super.dispose()
    }

    override func build(_ context: any BuildContext) -> Widget {
        // Check if any items have a leading icon — if so, reserve space for all
        let hasLeading = menuFlyout.items.contains { item in
            if let menuItem = item as? MenuFlyoutItem {
                return menuItem.leading != nil
            }
            if let subItem = item as? MenuFlyoutSubItem {
                return subItem.leading != nil
            }
            if let toggleItem = item as? ToggleMenuFlyoutItem {
                return toggleItem.leading != nil
            }
            if let radioItem = item as? RadioMenuFlyoutItem {
                return radioItem.leading != nil
            }
            return false
        }

        // Build the list of item widgets
        let itemWidgets: [Widget] = menuFlyout.items.map { item in
            item._menu = self
            if let menuItem = item as? MenuFlyoutItem {
                menuItem._useIconPlaceholder = hasLeading
            } else if let subItem = item as? MenuFlyoutSubItem {
                subItem._useIconPlaceholder = hasLeading
            } else if let toggleItem = item as? ToggleMenuFlyoutItem {
                toggleItem._useIconPlaceholder = hasLeading
            } else if let radioItem = item as? RadioMenuFlyoutItem {
                radioItem._useIconPlaceholder = hasLeading
            }
            return Padding(
                padding: menuFlyout.itemMargin,
                child: item.buildItem(context)
            )
        }

        let column: Widget = Column(
            mainAxisSize: .min,
            crossAxisAlignment: .start,
            children: itemWidgets
        )

        let content: Widget = FlyoutContent(
            child: column,
            color: menuFlyout.color,
            padding: kDefaultMenuFlyoutPadding,
            shadowColor: menuFlyout.shadowColor,
            elevation: menuFlyout.elevation,
            constraints: menuFlyout.constraints
        )

        return content
    }
}

// MARK: - MenuFlyoutSubItem

/// A menu item that displays a label and, when hovered or pressed, opens a
/// nested submenu to the right (or left, depending on available space).
///
/// Usage:
/// ```swift
/// MenuFlyoutSubItem(
///     text: Text("Share"),
///     items: [
///         MenuFlyoutItem(text: Text("Email"), onPressed: { ... }),
///         MenuFlyoutItem(text: Text("Copy Link"), onPressed: { ... }),
///     ]
/// )
/// ```
public class MenuFlyoutSubItem: MenuFlyoutItemBase {
    /// The primary text widget.
    public let text: Widget

    /// An optional leading widget, displayed before the text.
    public let leading: Widget?

    /// The submenu items to display when this item is activated.
    public let items: [MenuFlyoutItemBase]

    /// Whether to use an icon placeholder when no leading is provided.
    /// Set internally by `MenuFlyout` when other items have icons.
    var _useIconPlaceholder: Bool = false

    /// Creates a menu flyout sub item.
    public init(
        key: (any Key)? = nil,
        text: Widget,
        leading: Widget? = nil,
        items: [MenuFlyoutItemBase] = []
    ) {
        self.text = text
        self.leading = leading
        self.items = items
        super.init(key: key)
    }

    public override func buildItem(_ context: any BuildContext) -> Widget {
        return _MenuFlyoutSubItemWidget(subItem: self)
    }
}

// MARK: - _MenuFlyoutSubItemWidget

/// Internal stateful widget that manages the submenu flyout for a `MenuFlyoutSubItem`.
private class _MenuFlyoutSubItemWidget: StatefulWidget {
    let subItem: MenuFlyoutSubItem

    init(key: (any Key)? = nil, subItem: MenuFlyoutSubItem) {
        self.subItem = subItem
        super.init(key: key)
    }

    override func createState() -> State<StatefulWidget> {
        return _MenuFlyoutSubItemWidgetState()
    }
}

private class _MenuFlyoutSubItemWidgetState: State<StatefulWidget> {
    private let _flyoutController = FlyoutController()
    private let _openDelay = FluentDelay()

    var subItemWidget: _MenuFlyoutSubItemWidget {
        return widget as! _MenuFlyoutSubItemWidget
    }

    override func dispose() {
        _openDelay.cancel()
        _flyoutController.closeFlyout()
        super.dispose()
    }

    override func build(_ context: any BuildContext) -> Widget {
        let subItem = subItemWidget.subItem

        let resolvedLeading: Widget? = subItem.leading
            ?? (subItem._useIconPlaceholder ? SizedBox(width: 16, height: 16) : nil)

        // Right-pointing chevron to indicate submenu
        let chevron: Widget = FluentGlyph(
            .chevronRight, size: 12,
            color: FluentTheme.of(context).resources.textFillColorSecondary)

        // Windows opens a submenu two ways: a click, at once, or the pointer
        // resting on the item for the menu delay. Leaving early cancels.
        let tile: Widget = FlyoutListTile(
            onPressed: { [weak self] in
                self?._openDelay.cancel()
                self?._openSubmenu()
            },
            icon: resolvedLeading,
            text: subItem.text,
            trailing: chevron,
            margin: EdgeInsets(),
            selected: _flyoutController.isOpen,
            showSelectedIndicator: false,
            onPointerEnter: { [weak self] _ in
                guard let self else { return }
                subItem._menu?._hovered(subItem)
                if !self._flyoutController.isOpen {
                    self._openDelay.schedule(after: FluentMotion.menuShowDelay) { [weak self] in
                        self?._openSubmenu()
                    }
                }
            },
            onPointerExit: { [weak self] _ in
                self?._openDelay.cancel()
                subItem._menu?._left(subItem)
            }
        )

        return FlyoutTarget(
            controller: _flyoutController,
            child: tile
        )
    }

    private func _openSubmenu() {
        let subItem = subItemWidget.subItem
        if _flyoutController.isOpen { return }
        guard _flyoutController.isAttached else { return }
        // Beside the item with their tops level, as WinUI's
        // `RightEdgeAlignedTop`; no barrier of its own, so the parent menu
        // stays live underneath (see `showFlyout(barrier:)`).
        _flyoutController.showFlyout(
            builder: { ctx in
                MenuFlyout(items: subItem.items)
            },
            placement: .rightEdgeAlignedTop,
            additionalOffset: 0,
            barrier: false
        )
        subItem._menu?._subOpened(self)
        // The tile reads as selected while its submenu is open.
        if mounted { setState {} }
    }

    fileprivate func _close() {
        _openDelay.cancel()
        guard _flyoutController.isOpen else { return }
        _flyoutController.closeFlyout()
        if mounted { setState {} }
    }
}

// MARK: - ToggleMenuFlyoutItem

/// A menu item with a checkbox-like toggle indicator.
///
/// Shows a checkmark icon when `isChecked` is true. Toggling the item calls
/// `onChanged` with the new value.
///
/// Usage:
/// ```swift
/// ToggleMenuFlyoutItem(
///     text: Text("Show Toolbar"),
///     isChecked: showToolbar,
///     onChanged: { newValue in setState { showToolbar = newValue } }
/// )
/// ```
public class ToggleMenuFlyoutItem: MenuFlyoutItemBase {
    /// The primary text widget.
    public let text: Widget

    /// An optional leading widget displayed before the text.
    public let leading: Widget?

    /// An optional trailing widget displayed after the text.
    public let trailing: Widget?

    /// Whether this item is currently checked.
    public let isChecked: Bool

    /// Called when the toggle state should change.
    /// If nil, the item is disabled.
    public let onChanged: ((Bool) -> Void)?

    /// Whether pressing this item closes the parent flyout.
    public let closeAfterClick: Bool

    /// Whether to use an icon placeholder when no leading is provided.
    var _useIconPlaceholder: Bool = false

    /// Creates a toggle menu flyout item.
    public init(
        key: (any Key)? = nil,
        text: Widget,
        leading: Widget? = nil,
        trailing: Widget? = nil,
        isChecked: Bool = false,
        onChanged: ((Bool) -> Void)? = nil,
        closeAfterClick: Bool = true
    ) {
        self.text = text
        self.leading = leading
        self.trailing = trailing
        self.isChecked = isChecked
        self.onChanged = onChanged
        self.closeAfterClick = closeAfterClick
        super.init(key: key)
    }

    public override func buildItem(_ context: any BuildContext) -> Widget {
        let theme = FluentTheme.of(context)

        // Checkmark indicator shown when checked
        let checkIcon: Widget? = isChecked
            ? FluentGlyph(.check, size: 14, color: theme.resources.textFillColorPrimary)
            : nil

        // If a leading widget is provided, use it; otherwise use the checkmark
        // as the leading indicator. If neither, use a placeholder if needed.
        let resolvedLeading: Widget?
        if let leading = leading {
            resolvedLeading = leading
        } else if let checkIcon = checkIcon {
            resolvedLeading = SizedBox(
                width: 16,
                height: 16,
                child: Center(child: checkIcon)
            )
        } else if _useIconPlaceholder || isChecked {
            resolvedLeading = SizedBox(width: 16, height: 16)
        } else {
            resolvedLeading = SizedBox(width: 16, height: 16)
        }

        let resolvedTrailing: Widget = trailing ?? SizedBox(width: 0, height: 0)

        return FlyoutListTile(
            onPressed: onChanged == nil ? nil : { [weak self] in
                guard let self = self else { return }
                if self.closeAfterClick { _closeMenus(context) }
                self.onChanged?(!self.isChecked)
            },
            icon: resolvedLeading,
            text: text,
            trailing: resolvedTrailing,
            margin: EdgeInsets(),
            selected: isChecked,
            showSelectedIndicator: false,
            onPointerEnter: { [weak self] _ in
                guard let self else { return }
                self._menu?._hovered(self)
            },
            onPointerExit: { [weak self] _ in
                guard let self else { return }
                self._menu?._left(self)
            }
        )
    }
}

// MARK: - RadioMenuFlyoutItem

/// A menu item with a radio-button style selection indicator.
///
/// Shows a filled circle when `isSelected` is true. Pressing the item calls
/// `onSelected`.
///
/// Usage:
/// ```swift
/// RadioMenuFlyoutItem(
///     text: Text("Small"),
///     isSelected: size == .small,
///     onSelected: { setState { size = .small } }
/// )
/// ```
public class RadioMenuFlyoutItem: MenuFlyoutItemBase {
    /// The primary text widget.
    public let text: Widget

    /// An optional leading widget displayed before the text.
    public let leading: Widget?

    /// Whether this item is currently selected.
    public let isSelected: Bool

    /// Called when this item is pressed to select it.
    /// If nil, the item is disabled.
    public let onSelected: (() -> Void)?

    /// Whether pressing this item closes the parent flyout.
    public let closeAfterClick: Bool

    /// Whether to use an icon placeholder when no leading is provided.
    var _useIconPlaceholder: Bool = false

    /// Creates a radio menu flyout item.
    public init(
        key: (any Key)? = nil,
        text: Widget,
        leading: Widget? = nil,
        isSelected: Bool = false,
        onSelected: (() -> Void)? = nil,
        closeAfterClick: Bool = true
    ) {
        self.text = text
        self.leading = leading
        self.isSelected = isSelected
        self.onSelected = onSelected
        self.closeAfterClick = closeAfterClick
        super.init(key: key)
    }

    public override func buildItem(_ context: any BuildContext) -> Widget {
        let theme = FluentTheme.of(context)

        // Radio indicator: a bullet character when selected
        let radioIcon: Widget? = isSelected
            ? FluentGlyph(.dot, size: 14, color: theme.accentColor.defaultBrushFor(theme.brightness))
            : nil

        // Resolve leading widget
        let resolvedLeading: Widget?
        if let leading = leading {
            resolvedLeading = leading
        } else if let radioIcon = radioIcon {
            resolvedLeading = SizedBox(
                width: 16,
                height: 16,
                child: Center(child: radioIcon)
            )
        } else {
            resolvedLeading = SizedBox(width: 16, height: 16)
        }

        return FlyoutListTile(
            onPressed: onSelected == nil ? nil : { [weak self] in
                guard let self = self else { return }
                if self.closeAfterClick { _closeMenus(context) }
                self.onSelected?()
            },
            icon: resolvedLeading,
            text: text,
            margin: EdgeInsets(),
            selected: isSelected,
            showSelectedIndicator: false,
            onPointerEnter: { [weak self] _ in
                guard let self else { return }
                self._menu?._hovered(self)
            },
            onPointerExit: { [weak self] _ in
                guard let self else { return }
                self._menu?._left(self)
            }
        )
    }
}

// MARK: - Closing

/// Closes the menu an item was chosen from and every menu above it. A menu
/// is an overlay entry, not a route, so the navigator has nothing to pop;
/// the flyout scope is what knows the chain. The pop stays as the fallback
/// for a menu shown some other way.
private func _closeMenus(_ context: any BuildContext) {
    if let scope = FlyoutScope.maybeOf(context) {
        scope.closeAll()
    } else {
        Navigator.maybeOf(context)?.maybePop()
    }
}


