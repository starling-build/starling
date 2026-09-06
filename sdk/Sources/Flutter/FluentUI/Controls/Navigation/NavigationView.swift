// Ported from: fluent_ui/lib/src/controls/navigation/navigation_view/
//
// Simplified port of NavigationView — the flagship Fluent UI navigation container.
// Supports PaneDisplayMode.open (expanded sidebar), .compact (icons only),
// .minimal (hamburger), and .top (horizontal).

import FlutterSwiftBridge

// MARK: - Constants

/// The minimum height of a pane item.
public let kPaneItemMinHeight: Double = 40.0

/// The minimum width of a pane item in top display mode.
public let kPaneItemTopMinWidth: Double = 40.0

/// The width of the compact navigation pane (icons only).
public let kCompactNavigationPaneWidth: Double = 50.0

/// The width of the open (expanded) navigation pane.
public let kOpenNavigationPaneWidth: Double = 320.0

// MARK: - PaneDisplayMode

/// Defines how the NavigationPane is displayed.
public enum PaneDisplayMode {
    /// Pane is positioned above the content (horizontal navigation at top).
    case top

    /// Pane is expanded with icons and labels, positioned to the left of content.
    case open

    /// Pane shows only icons, positioned to the left of content.
    case compact

    /// Pane is hidden by default, shown via a hamburger button.
    case minimal

    /// Automatically adapts based on available width:
    /// - >= 1008px: open
    /// - 641-1007px: compact
    /// - <= 640px: minimal
    case auto
}

// MARK: - NavigationPaneItem (base class)

/// Base class for items that can be displayed in a NavigationPane.
public class NavigationPaneItem {
    public init() {}
}

// MARK: - PaneItem

/// A standard navigation item with an icon, title, and associated body content.
public class PaneItem: NavigationPaneItem {
    /// The icon displayed for this item.
    public let icon: Widget?

    /// The title displayed next to the icon (in open/minimal modes).
    public let title: Widget?

    /// The body content shown when this item is selected.
    public let body: Widget?

    /// Called when this item is tapped, regardless of selection state.
    public let onTap: (() -> Void)?

    /// An optional info badge displayed on this item.
    public let infoBadge: Widget?

    /// A trailing widget displayed after the title.
    public let trailing: Widget?

    /// Whether this item is enabled.
    public let enabled: Bool

    public init(
        icon: Widget? = nil,
        title: Widget? = nil,
        body: Widget? = nil,
        onTap: (() -> Void)? = nil,
        infoBadge: Widget? = nil,
        trailing: Widget? = nil,
        enabled: Bool = true
    ) {
        self.icon = icon
        self.title = title
        self.body = body
        self.onTap = onTap
        self.infoBadge = infoBadge
        self.trailing = trailing
        self.enabled = enabled
        super.init()
    }

    /// Builds the visual representation of this pane item.
    public func build(
        context: any BuildContext,
        selected: Bool,
        onPressed: (() -> Void)?,
        displayMode: PaneDisplayMode,
        themeData: NavigationPaneThemeData
    ) -> Widget {
        let isTop = displayMode == .top

        let onItemTapped: (() -> Void)? = (!enabled || (onPressed == nil && onTap == nil))
            ? nil
            : {
                onPressed?()
                self.onTap?()
            }

        return HoverButton(
            builder: { [self] context, states in
                let textColor: Color = _resolveTextColor(
                    themeData: themeData,
                    selected: selected,
                    states: states,
                    isTop: isTop
                )

                let tileColor: Color = _resolveTileColor(
                    themeData: themeData,
                    selected: selected,
                    states: states,
                    isTop: isTop
                )

                let textStyle = TextStyle(color: textColor, fontSize: 14)

                let content: Widget
                switch displayMode {
                case .compact:
                    content = _buildCompactContent(themeData: themeData, textColor: textColor)
                case .top:
                    content = _buildTopContent(
                        themeData: themeData,
                        textStyle: textStyle,
                        textColor: textColor
                    )
                default:
                    content = _buildOpenContent(
                        themeData: themeData,
                        textStyle: textStyle,
                        textColor: textColor
                    )
                }

                // Tile decoration with background color
                let tileDecoration = BoxDecoration(
                    color: tileColor,
                    borderRadius: BorderRadius.all(Radius(circular: 4))
                )

                // Compose: margin(Padding) -> decoration(_NavDecoratedBox) -> content
                let decorated: Widget = _NavDecoratedBox(decoration: tileDecoration, child: content)
                let result: Widget = Padding(
                    padding: EdgeInsets(left: 6, top: 0, right: 6, bottom: 0),
                    child: decorated
                )

                return result
            },
            onPressed: onItemTapped,
            forceEnabled: enabled
        )
    }

    // MARK: - Private Build Helpers

    private func _buildCompactContent(themeData: NavigationPaneThemeData, textColor: Color) -> Widget {
        let iconWidget: Widget = icon ?? SizedBox(width: 16, height: 16)
        let styledIcon: Widget = IconTheme(
            data: IconThemeData(size: 16, color: textColor),
            child: iconWidget
        )

        // ConstrainedBox(minHeight) -> Align(center) -> Padding -> icon
        let padded: Widget = Padding(
            padding: EdgeInsets(left: 12, top: 0, right: 12, bottom: 0),
            child: styledIcon
        )
        let aligned: Widget = Align(alignment: Alignment.center, child: padded)
        return ConstrainedBox(
            constraints: BoxConstraints(minHeight: kPaneItemMinHeight),
            child: aligned
        )
    }

    private func _buildOpenContent(
        themeData: NavigationPaneThemeData,
        textStyle: TextStyle,
        textColor: Color
    ) -> Widget {
        let iconWidget: Widget = icon ?? SizedBox(width: 16, height: 16)
        let styledIcon: Widget = IconTheme(
            data: IconThemeData(size: 16, color: textColor),
            child: iconWidget
        )

        var rowChildren: [Widget] = []

        // Icon with padding
        rowChildren.append(
            Padding(
                padding: EdgeInsets(left: 12, top: 0, right: 12, bottom: 0),
                child: styledIcon
            )
        )

        // Title
        if let title = title {
            rowChildren.append(
                Expanded(child: DefaultTextStyle(
                    style: textStyle,
                    child: title
                ))
            )
        } else {
            rowChildren.append(Expanded(child: SizedBox(width: 0, height: 0)))
        }

        // Info badge
        if let infoBadge = infoBadge {
            rowChildren.append(
                Padding(
                    padding: EdgeInsets(left: 0, top: 0, right: 8, bottom: 0),
                    child: infoBadge
                )
            )
        }

        // Trailing
        if let trailing = trailing {
            rowChildren.append(trailing)
        }

        return ConstrainedBox(
            constraints: BoxConstraints(minHeight: kPaneItemMinHeight),
            child: Row(children: rowChildren)
        )
    }

    private func _buildTopContent(
        themeData: NavigationPaneThemeData,
        textStyle: TextStyle,
        textColor: Color
    ) -> Widget {
        let iconWidget: Widget = icon ?? SizedBox(width: 16, height: 16)
        let styledIcon: Widget = IconTheme(
            data: IconThemeData(size: 16, color: textColor),
            child: iconWidget
        )

        var rowChildren: [Widget] = []

        rowChildren.append(
            Padding(
                padding: EdgeInsets(left: 12, top: 0, right: 4, bottom: 0),
                child: styledIcon
            )
        )

        if let title = title {
            rowChildren.append(
                Padding(
                    padding: EdgeInsets(left: 0, top: 0, right: 10, bottom: 0),
                    child: DefaultTextStyle(style: textStyle, child: title)
                )
            )
        }

        return ConstrainedBox(
            constraints: BoxConstraints(minWidth: kPaneItemTopMinWidth, minHeight: kPaneItemMinHeight),
            child: Row(mainAxisSize: .min, children: rowChildren)
        )
    }

    // MARK: - Color Resolution

    private func _resolveTextColor(
        themeData: NavigationPaneThemeData,
        selected: Bool,
        states: Set<WidgetState>,
        isTop: Bool
    ) -> Color {
        if states.isDisabled {
            return themeData.textColorDisabled
        }
        if states.isPressed {
            return themeData.textColorSecondary
        }
        return themeData.textColorPrimary
    }

    private func _resolveTileColor(
        themeData: NavigationPaneThemeData,
        selected: Bool,
        states: Set<WidgetState>,
        isTop: Bool
    ) -> Color {
        if isTop { return Color(0x00000000) }
        if selected {
            if states.isHovered {
                return themeData.subtleFillColorTertiary
            }
            return themeData.subtleFillColorSecondary
        }
        if states.isPressed {
            return themeData.subtleFillColorTertiary
        }
        if states.isHovered {
            return themeData.subtleFillColorSecondary
        }
        return Color(0x00000000)
    }
}

// MARK: - PaneItemSeparator

/// A horizontal divider used to separate groups of navigation items.
public class PaneItemSeparator: NavigationPaneItem {
    public override init() {
        super.init()
    }

    /// Builds the separator widget.
    public func build(context: any BuildContext, axis: Axis = .horizontal) -> Widget {
        let theme = FluentTheme.of(context)
        let color = theme.resources.dividerStrokeColorDefault
        let thickness: Double = 1.0

        if axis == .horizontal {
            return Padding(
                padding: EdgeInsets(left: 0, top: 4, right: 0, bottom: 4),
                child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: thickness),
                    child: ColoredBox(color: color)
                )
            )
        } else {
            return Padding(
                padding: EdgeInsets(left: 4, top: 0, right: 4, bottom: 0),
                child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: thickness),
                    child: ColoredBox(color: color)
                )
            )
        }
    }
}

// MARK: - PaneItemHeader

/// A header label used to group navigation items into sections.
public class PaneItemHeader: NavigationPaneItem {
    /// The header content, typically a `Text` widget.
    public let header: Widget

    public init(header: Widget) {
        self.header = header
        super.init()
    }

    /// Builds the header widget.
    public func build(context: any BuildContext) -> Widget {
        let theme = FluentTheme.of(context)
        let style = TextStyle(
            color: theme.resources.textFillColorSecondary,
            fontSize: 14,
            fontWeight: .bold
        )

        // ConstrainedBox(minHeight) -> Align(centerLeft) -> Padding -> content
        let padded: Widget = Padding(
            padding: EdgeInsets(left: 18, top: 0, right: 18, bottom: 0),
            child: DefaultTextStyle(style: style, child: header)
        )
        let aligned: Widget = Align(alignment: Alignment.centerLeft, child: padded)
        return ConstrainedBox(
            constraints: BoxConstraints(minHeight: kPaneItemMinHeight),
            child: aligned
        )
    }
}

// MARK: - PaneItemExpander

/// An expandable navigation item that groups child items under a collapsible
/// header. In open/minimal modes, clicking the expander toggles visibility of
/// its children. In compact mode, only the icon is shown.
///
/// The expander itself can optionally have a `body` that is shown when selected.
/// Its child items also contribute to the pane's effective items.
public class PaneItemExpander: NavigationPaneItem {
    /// The icon displayed for this expander.
    public let icon: Widget?

    /// The title displayed next to the icon.
    public let title: Widget?

    /// The body content shown when this expander itself is selected.
    public let body: Widget?

    /// The child items grouped under this expander.
    public let items: [NavigationPaneItem]

    /// An optional info badge.
    public let infoBadge: Widget?

    /// A trailing widget displayed after the title.
    public let trailing: Widget?

    /// Whether the expander starts in the expanded state.
    public let initiallyExpanded: Bool

    /// Whether this expander is enabled.
    public let enabled: Bool

    public init(
        icon: Widget? = nil,
        title: Widget? = nil,
        body: Widget? = nil,
        items: [NavigationPaneItem] = [],
        infoBadge: Widget? = nil,
        trailing: Widget? = nil,
        initiallyExpanded: Bool = false,
        enabled: Bool = true
    ) {
        self.icon = icon
        self.title = title
        self.body = body
        self.items = items
        self.infoBadge = infoBadge
        self.trailing = trailing
        self.initiallyExpanded = initiallyExpanded
        self.enabled = enabled
        super.init()
    }
}

// MARK: - PaneItemAction

/// A navigation pane item that performs an action when pressed, without
/// changing the selected page. Useful for items like "Settings" or "Help"
/// that trigger an action rather than navigate.
public class PaneItemAction: NavigationPaneItem {
    /// The icon displayed for this item.
    public let icon: Widget?

    /// The title displayed next to the icon.
    public let title: Widget?

    /// Called when this item is pressed.
    public let onTap: (() -> Void)?

    /// Whether this item is enabled.
    public let enabled: Bool

    public init(
        icon: Widget? = nil,
        title: Widget? = nil,
        onTap: (() -> Void)? = nil,
        enabled: Bool = true
    ) {
        self.icon = icon
        self.title = title
        self.onTap = onTap
        self.enabled = enabled
        super.init()
    }
}

// MARK: - PaneItemWidgetAdapter

/// A navigation pane item that wraps an arbitrary widget.
/// Useful for custom content in the navigation pane.
public class PaneItemWidgetAdapter: NavigationPaneItem {
    /// The custom widget to display in the pane.
    public let child: Widget

    public init(child: Widget) {
        self.child = child
        super.init()
    }
}

// MARK: - NavigationPaneSize

/// Configures the size of the NavigationPane in its various display modes.
public struct NavigationPaneSize {
    /// The height of the pane in top mode.
    public let topHeight: Double

    /// The width of the pane in compact mode.
    public let compactWidth: Double

    /// The width of the pane when open/expanded.
    public let openWidth: Double

    /// The minimum width of the pane when open.
    public let openMinWidth: Double?

    /// The maximum width of the pane when open.
    public let openMaxWidth: Double?

    /// The height of the header in the pane.
    public let headerHeight: Double

    /// Creates a navigation pane size configuration.
    public init(
        topHeight: Double = kOneLineTileHeight,
        compactWidth: Double = kCompactNavigationPaneWidth,
        openWidth: Double = kOpenNavigationPaneWidth,
        openMinWidth: Double? = nil,
        openMaxWidth: Double? = nil,
        headerHeight: Double = kOneLineTileHeight
    ) {
        self.topHeight = topHeight
        self.compactWidth = compactWidth
        self.openWidth = openWidth
        self.openMinWidth = openMinWidth
        self.openMaxWidth = openMaxWidth
        self.headerHeight = headerHeight
    }

    /// The computed open pane width, clamped by min/max constraints.
    public var openPaneWidth: Double {
        let minW = openMinWidth ?? 0
        let maxW = openMaxWidth ?? Double.infinity
        if openWidth < minW { return minW }
        if openWidth > maxW { return maxW }
        return openWidth
    }
}

// MARK: - NavigationPane

/// The navigation pane configuration used by `NavigationView`.
///
/// Contains the list of items, footer items, header, and selection state.
/// The NavigationView uses this to build the sidebar/top bar.
public class NavigationPane {
    /// The currently selected item index (among effective/navigable items).
    public let selected: Int?

    /// Called when the selected item changes.
    public let onChanged: ((Int) -> Void)?

    /// The navigation items displayed in the main area of the pane.
    public let items: [NavigationPaneItem]

    /// The navigation items displayed at the bottom of the pane.
    public let footerItems: [NavigationPaneItem]

    /// An optional header widget displayed at the top of the pane.
    public let header: Widget?

    /// The display mode for the pane.
    public let displayMode: PaneDisplayMode

    /// The sizing configuration for the pane.
    public let size: NavigationPaneSize?

    /// Whether to show a selection indicator on the selected item.
    public let showIndicator: Bool

    /// Creates a navigation pane.
    public init(
        selected: Int? = nil,
        onChanged: ((Int) -> Void)? = nil,
        items: [NavigationPaneItem] = [],
        footerItems: [NavigationPaneItem] = [],
        header: Widget? = nil,
        displayMode: PaneDisplayMode = .auto,
        size: NavigationPaneSize? = nil,
        showIndicator: Bool = true
    ) {
        self.selected = selected
        self.onChanged = onChanged
        self.items = items
        self.footerItems = footerItems
        self.header = header
        self.displayMode = displayMode
        self.size = size
        self.showIndicator = showIndicator
    }

    /// All PaneItems (navigable items only) from both `items` and `footerItems`.
    /// Also includes items nested inside `PaneItemExpander`.
    public var effectiveItems: [PaneItem] {
        var result: [PaneItem] = []
        _collectEffectiveItems(from: items, into: &result)
        _collectEffectiveItems(from: footerItems, into: &result)
        return result
    }

    private func _collectEffectiveItems(from items: [NavigationPaneItem], into result: inout [PaneItem]) {
        for item in items {
            if let paneItem = item as? PaneItem, paneItem.body != nil {
                result.append(paneItem)
            } else if let expander = item as? PaneItemExpander {
                // The expander itself can have a body
                if expander.body != nil {
                    // Create a synthetic PaneItem for the expander's own body
                    let expanderPaneItem = PaneItem(
                        icon: expander.icon,
                        title: expander.title,
                        body: expander.body
                    )
                    result.append(expanderPaneItem)
                }
                // Recurse into children
                _collectEffectiveItems(from: expander.items, into: &result)
            }
        }
    }

    /// Returns the effective index of a given NavigationPaneItem.
    public func effectiveIndexOf(_ item: NavigationPaneItem) -> Int {
        guard let paneItem = item as? PaneItem else { return -1 }
        let items = effectiveItems
        for i in 0..<items.count {
            if items[i] === paneItem { return i }
        }
        return -1
    }

    /// Whether the given item is currently selected.
    public func isSelected(_ item: NavigationPaneItem) -> Bool {
        guard let selected = selected else { return false }
        return effectiveIndexOf(item) == selected
    }

    /// Changes the selection to the given item.
    public func changeTo(_ item: NavigationPaneItem) {
        let index = effectiveIndexOf(item)
        if index >= 0 && index != selected {
            onChanged?(index)
        }
    }
}

// MARK: - NavigationPaneThemeData

/// Theme data for the NavigationPane.
public struct NavigationPaneThemeData {
    /// Background color of the pane.
    public let backgroundColor: Color

    /// The highlight/accent color for the selected indicator.
    public let highlightColor: Color

    /// Primary text color.
    public let textColorPrimary: Color

    /// Secondary text color (pressed state).
    public let textColorSecondary: Color

    /// Disabled text color.
    public let textColorDisabled: Color

    /// Subtle fill color for secondary hover state.
    public let subtleFillColorSecondary: Color

    /// Subtle fill color for tertiary/pressed state.
    public let subtleFillColorTertiary: Color

    /// Creates navigation pane theme data.
    public init(
        backgroundColor: Color,
        highlightColor: Color,
        textColorPrimary: Color,
        textColorSecondary: Color,
        textColorDisabled: Color,
        subtleFillColorSecondary: Color,
        subtleFillColorTertiary: Color
    ) {
        self.backgroundColor = backgroundColor
        self.highlightColor = highlightColor
        self.textColorPrimary = textColorPrimary
        self.textColorSecondary = textColorSecondary
        self.textColorDisabled = textColorDisabled
        self.subtleFillColorSecondary = subtleFillColorSecondary
        self.subtleFillColorTertiary = subtleFillColorTertiary
    }

    /// Creates theme data from a FluentThemeData.
    public static func fromTheme(_ theme: FluentThemeData) -> NavigationPaneThemeData {
        return NavigationPaneThemeData(
            backgroundColor: theme.resources.solidBackgroundFillColorBase,
            highlightColor: theme.accentColor.normal,
            textColorPrimary: theme.resources.textFillColorPrimary,
            textColorSecondary: theme.resources.textFillColorSecondary,
            textColorDisabled: theme.resources.textFillColorDisabled,
            subtleFillColorSecondary: theme.resources.subtleFillColorSecondary,
            subtleFillColorTertiary: theme.resources.subtleFillColorTertiary
        )
    }
}

// MARK: - NavigationPaneTheme (InheritedWidget)

/// An inherited widget that provides NavigationPaneThemeData to descendants.
public class NavigationPaneTheme: InheritedTheme {
    /// The theme data.
    public let data: NavigationPaneThemeData

    public init(key: (any Key)? = nil, data: NavigationPaneThemeData, child: Widget) {
        self.data = data
        super.init(key: key, child: child)
    }

    /// Returns the closest NavigationPaneThemeData ancestor.
    public static func of(_ context: any BuildContext) -> NavigationPaneThemeData {
        let inherited = context.dependOnInheritedWidgetOfExactType(NavigationPaneTheme.self)
        if let inherited = inherited {
            return inherited.data
        }
        let theme = FluentTheme.of(context)
        return NavigationPaneThemeData.fromTheme(theme)
    }

    public override func updateShouldNotify(_ oldWidget: InheritedWidget) -> Bool {
        guard let old = oldWidget as? NavigationPaneTheme else { return true }
        // Always notify since struct comparison is not trivially cheap
        return true
    }

    public override func wrap(_ context: any BuildContext, _ child: Widget) -> Widget {
        return NavigationPaneTheme(data: data, child: child)
    }
}

// MARK: - NavigationViewData (InheritedWidget)

/// An inherited widget that provides NavigationView context data to descendants.
public class NavigationViewData: InheritedWidget {
    /// The current display mode.
    public let displayMode: PaneDisplayMode

    /// The navigation pane configuration.
    public let pane: NavigationPane?

    public init(
        key: (any Key)? = nil,
        displayMode: PaneDisplayMode,
        pane: NavigationPane?,
        child: Widget
    ) {
        self.displayMode = displayMode
        self.pane = pane
        super.init(key: key, child: child)
    }

    /// Returns the closest NavigationViewData ancestor.
    public static func of(_ context: any BuildContext) -> NavigationViewData {
        return context.dependOnInheritedWidgetOfExactType(NavigationViewData.self)!
    }

    /// Returns the closest NavigationViewData ancestor, if any.
    public static func maybeOf(_ context: any BuildContext) -> NavigationViewData? {
        return context.dependOnInheritedWidgetOfExactType(NavigationViewData.self)
    }

    public override func updateShouldNotify(_ oldWidget: InheritedWidget) -> Bool {
        guard let old = oldWidget as? NavigationViewData else { return true }
        return displayMode != old.displayMode || pane !== old.pane
    }
}

// MARK: - NavigationView

/// The flagship Fluent UI navigation widget.
///
/// Provides a sidebar + content layout with support for multiple display modes
/// (open, compact, minimal, top).
///
/// ```swift
/// NavigationView(
///     pane: NavigationPane(
///         selected: selectedIndex,
///         onChanged: { index in setState { selectedIndex = index } },
///         items: [
///             PaneItem(icon: Icon(iconData: someIcon), title: Text("Home"), body: HomePage()),
///             PaneItem(icon: Icon(iconData: someIcon), title: Text("Settings"), body: SettingsPage()),
///         ]
///     )
/// )
/// ```
public class NavigationView: StatefulWidget {
    /// The navigation pane configuration.
    public let pane: NavigationPane?

    /// The content to display (used when `pane` is nil).
    public let content: Widget?

    /// An optional app bar displayed at the top.
    public let appBar: Widget?

    public init(
        key: (any Key)? = nil,
        pane: NavigationPane? = nil,
        content: Widget? = nil,
        appBar: Widget? = nil
    ) {
        self.pane = pane
        self.content = content
        self.appBar = appBar
        super.init(key: key)
    }

    public override func createState() -> State<StatefulWidget> {
        return NavigationViewState()
    }
}

// MARK: - NavigationViewState

class NavigationViewState: State<StatefulWidget> {
    private var _displayMode: PaneDisplayMode = .open

    private var navigationView: NavigationView {
        return widget as! NavigationView
    }

    /// Resolves the display mode based on the pane configuration.
    /// For `.auto` mode, defaults to `.open` (adaptive breakpoints require LayoutBuilder).
    private func _resolveDisplayMode() {
        guard let pane = navigationView.pane else {
            _displayMode = .open
            return
        }
        let mode = pane.displayMode
        if mode == .auto {
            // Without LayoutBuilder constraints, default to .open
            _displayMode = .open
        } else {
            _displayMode = mode
        }
    }

    override func build(_ context: any BuildContext) -> Widget {
        _resolveDisplayMode()

        let theme = FluentTheme.of(context)
        let paneTheme = NavigationPaneThemeData.fromTheme(theme)

        let paneResult: Widget

        if let pane = navigationView.pane {
            // Build the body from selected item
            let body: Widget = _buildBody(pane: pane)
            switch _displayMode {
            case .top:
                paneResult = _buildTopLayout(
                    context: context,
                    pane: pane,
                    body: body,
                    paneTheme: paneTheme
                )
            case .compact:
                paneResult = _buildCompactLayout(
                    context: context,
                    pane: pane,
                    body: body,
                    paneTheme: paneTheme
                )
            case .minimal:
                paneResult = _buildMinimalLayout(
                    context: context,
                    pane: pane,
                    body: body,
                    paneTheme: paneTheme
                )
            case .open, .auto:
                paneResult = _buildOpenLayout(
                    context: context,
                    pane: pane,
                    body: body,
                    paneTheme: paneTheme
                )
            }
        } else if let content = navigationView.content {
            paneResult = _buildContentOnly(content: content)
        } else {
            paneResult = SizedBox(width: 0, height: 0)
        }

        // Wrap in NavigationViewData and NavigationPaneTheme, with background
        let themed: Widget = NavigationPaneTheme(
            data: paneTheme,
            child: ColoredBox(color: paneTheme.backgroundColor, child: paneResult)
        )
        return NavigationViewData(
            displayMode: _displayMode,
            pane: navigationView.pane,
            child: themed
        )
    }

    // MARK: - Body

    private func _buildBody(pane: NavigationPane) -> Widget {
        guard let selected = pane.selected else {
            return SizedBox(width: 0, height: 0)
        }
        let items = pane.effectiveItems
        if selected >= 0 && selected < items.count {
            return items[selected].body ?? SizedBox(width: 0, height: 0)
        }
        return SizedBox(width: 0, height: 0)
    }

    // MARK: - Content Only Layout

    private func _buildContentOnly(content: Widget) -> Widget {
        var children: [Widget] = []
        if let appBar = navigationView.appBar {
            children.append(appBar)
        }
        children.append(Expanded(child: content))
        return Column(children: children)
    }

    // MARK: - Open Layout (Expanded Sidebar)

    private func _buildOpenLayout(
        context: any BuildContext,
        pane: NavigationPane,
        body: Widget,
        paneTheme: NavigationPaneThemeData
    ) -> Widget {
        let paneWidth = pane.size?.openPaneWidth ?? kOpenNavigationPaneWidth

        // Build sidebar
        let sidebar = _buildSidebarPane(
            context: context,
            pane: pane,
            paneTheme: paneTheme,
            width: paneWidth,
            showTitles: true
        )

        // Row: sidebar + content
        // `.stretch`: a page shorter than the window is laid out from the
        // top, not centred in the row -- Row's default cross alignment.
        let rowWidget = Row(crossAxisAlignment: .stretch, children: [
            SizedBox(width: paneWidth, child: sidebar),
            Expanded(child: body)
        ])

        var outerChildren: [Widget] = []
        if let appBar = navigationView.appBar {
            outerChildren.append(appBar)
        }
        outerChildren.append(Expanded(child: rowWidget))

        return Column(children: outerChildren)
    }

    // MARK: - Compact Layout (Icons Only)

    private func _buildCompactLayout(
        context: any BuildContext,
        pane: NavigationPane,
        body: Widget,
        paneTheme: NavigationPaneThemeData
    ) -> Widget {
        let compactWidth = pane.size?.compactWidth ?? kCompactNavigationPaneWidth

        // Build compact sidebar (icons only)
        let sidebar = _buildSidebarPane(
            context: context,
            pane: pane,
            paneTheme: paneTheme,
            width: compactWidth,
            showTitles: false
        )

        let rowWidget = Row(crossAxisAlignment: .stretch, children: [
            SizedBox(width: compactWidth, child: sidebar),
            Expanded(child: body)
        ])

        var outerChildren: [Widget] = []
        if let appBar = navigationView.appBar {
            outerChildren.append(appBar)
        }
        outerChildren.append(Expanded(child: rowWidget))

        return Column(children: outerChildren)
    }

    // MARK: - Minimal Layout (Hidden Pane)

    private func _buildMinimalLayout(
        context: any BuildContext,
        pane: NavigationPane,
        body: Widget,
        paneTheme: NavigationPaneThemeData
    ) -> Widget {
        // Minimal mode: body only (sidebar hidden in simplified port)
        var outerChildren: [Widget] = []
        if let appBar = navigationView.appBar {
            outerChildren.append(appBar)
        }
        outerChildren.append(Expanded(child: body))

        return Column(children: outerChildren)
    }

    // MARK: - Top Layout (Horizontal)

    private func _buildTopLayout(
        context: any BuildContext,
        pane: NavigationPane,
        body: Widget,
        paneTheme: NavigationPaneThemeData
    ) -> Widget {
        let height = pane.size?.topHeight ?? kOneLineTileHeight

        // Build horizontal pane items
        let topBar = _buildTopPane(
            context: context,
            pane: pane,
            paneTheme: paneTheme,
            height: height
        )

        var outerChildren: [Widget] = []
        if let appBar = navigationView.appBar {
            outerChildren.append(appBar)
        }
        outerChildren.append(SizedBox(height: height, child: topBar))
        outerChildren.append(Expanded(child: body))

        return Column(children: outerChildren)
    }

    // MARK: - Sidebar Pane Builder

    private func _buildSidebarPane(
        context: any BuildContext,
        pane: NavigationPane,
        paneTheme: NavigationPaneThemeData,
        width: Double,
        showTitles: Bool
    ) -> Widget {
        let displayMode: PaneDisplayMode = showTitles ? .open : .compact

        var columnChildren: [Widget] = []

        // Header
        if let header = pane.header, showTitles {
            let headerStyle = TextStyle(
                color: paneTheme.textColorSecondary,
                fontSize: 14,
                fontWeight: .bold
            )
            let headerPadded: Widget = Padding(
                padding: EdgeInsets(left: 14, top: 0, right: 14, bottom: 0),
                child: DefaultTextStyle(style: headerStyle, child: header)
            )
            let headerAligned: Widget = Align(
                alignment: Alignment.centerLeft,
                child: headerPadded
            )
            let headerConstrained: Widget = ConstrainedBox(
                constraints: BoxConstraints(minHeight: pane.size?.headerHeight ?? kOneLineTileHeight),
                child: headerAligned
            )
            columnChildren.append(headerConstrained)
        }

        // Main items
        var itemWidgets: [Widget] = []
        for item in pane.items {
            let w = _buildPaneItem(
                item: item,
                context: context,
                pane: pane,
                paneTheme: paneTheme,
                displayMode: displayMode
            )
            itemWidgets.append(w)
        }

        // The items scroll and the footer does not — a pane longer than the
        // window (this is every gallery and most settings apps) must not
        // paint its footer over its last items, and must not lose them.
        columnChildren.append(
            Expanded(child: SingleChildScrollView(child: Column(
                mainAxisSize: .min,
                crossAxisAlignment: .start,
                children: itemWidgets
            )))
        )

        // Footer items
        if !pane.footerItems.isEmpty {
            var footerWidgets: [Widget] = []
            for item in pane.footerItems {
                let w = _buildPaneItem(
                    item: item,
                    context: context,
                    pane: pane,
                    paneTheme: paneTheme,
                    displayMode: displayMode
                )
                footerWidgets.append(w)
            }
            columnChildren.append(
                Column(
                    mainAxisSize: .min,
                    crossAxisAlignment: .start,
                    children: footerWidgets
                )
            )
        }

        return ColoredBox(
            color: paneTheme.backgroundColor,
            child: Column(
                crossAxisAlignment: .start,
                children: columnChildren
            )
        )
    }

    // MARK: - Top Pane Builder

    private func _buildTopPane(
        context: any BuildContext,
        pane: NavigationPane,
        paneTheme: NavigationPaneThemeData,
        height: Double
    ) -> Widget {
        var rowChildren: [Widget] = []

        // Header
        if let header = pane.header {
            rowChildren.append(
                Padding(
                    padding: EdgeInsets(left: 8, top: 6, right: 8, bottom: 6),
                    child: header
                )
            )
        }

        // Main items
        for item in pane.items {
            let w = _buildPaneItem(
                item: item,
                context: context,
                pane: pane,
                paneTheme: paneTheme,
                displayMode: .top
            )
            rowChildren.append(w)
        }

        // Spacer between items and footer
        rowChildren.append(Expanded(child: SizedBox(width: 0, height: 0)))

        // Footer items
        for item in pane.footerItems {
            let w = _buildPaneItem(
                item: item,
                context: context,
                pane: pane,
                paneTheme: paneTheme,
                displayMode: .top
            )
            rowChildren.append(w)
        }

        return ColoredBox(
            color: paneTheme.backgroundColor,
            child: Row(children: rowChildren)
        )
    }

    // MARK: - Pane Item Builder

    private func _buildPaneItem(
        item: NavigationPaneItem,
        context: any BuildContext,
        pane: NavigationPane,
        paneTheme: NavigationPaneThemeData,
        displayMode: PaneDisplayMode
    ) -> Widget {
        if let paneItem = item as? PaneItem {
            let index = pane.effectiveIndexOf(paneItem)
            let selected = index == pane.selected

            let itemWidget = paneItem.build(
                context: context,
                selected: selected,
                onPressed: { pane.changeTo(paneItem) },
                displayMode: displayMode,
                themeData: paneTheme
            )

            // Wrap with selection indicator
            if pane.showIndicator && selected {
                let indicator = _buildSelectionIndicator(
                    paneTheme: paneTheme,
                    displayMode: displayMode
                )
                return Padding(
                    padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 4),
                    child: Stack(children: [itemWidget, indicator])
                )
            }

            return Padding(
                padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 4),
                child: itemWidget
            )
        } else if let expander = item as? PaneItemExpander {
            return _PaneItemExpanderWidget(
                expander: expander,
                pane: pane,
                paneTheme: paneTheme,
                displayMode: displayMode
            )
        } else if let action = item as? PaneItemAction {
            return _buildPaneItemAction(
                action: action,
                context: context,
                paneTheme: paneTheme,
                displayMode: displayMode
            )
        } else if let adapter = item as? PaneItemWidgetAdapter {
            return adapter.child
        } else if let separator = item as? PaneItemSeparator {
            let axis: Axis = displayMode == .top ? .vertical : .horizontal
            return separator.build(context: context, axis: axis)
        } else if let header = item as? PaneItemHeader {
            if displayMode == .compact {
                return SizedBox(width: 0, height: 0)
            }
            return header.build(context: context)
        }
        return SizedBox(width: 0, height: 0)
    }

    // MARK: - PaneItemAction Builder

    private func _buildPaneItemAction(
        action: PaneItemAction,
        context: any BuildContext,
        paneTheme: NavigationPaneThemeData,
        displayMode: PaneDisplayMode
    ) -> Widget {
        let onItemTapped: (() -> Void)? = (!action.enabled || action.onTap == nil)
            ? nil
            : { action.onTap?() }

        return HoverButton(
            builder: { context, states in
                let textColor: Color = states.isDisabled
                    ? paneTheme.textColorDisabled
                    : (states.isPressed ? paneTheme.textColorSecondary : paneTheme.textColorPrimary)

                let tileColor: Color = displayMode == .top
                    ? Color(0x00000000)
                    : (states.isPressed
                        ? paneTheme.subtleFillColorTertiary
                        : (states.isHovered ? paneTheme.subtleFillColorSecondary : Color(0x00000000)))

                let iconWidget: Widget = action.icon ?? SizedBox(width: 16, height: 16)
                let styledIcon: Widget = IconTheme(
                    data: IconThemeData(size: 16, color: textColor),
                    child: iconWidget
                )

                let content: Widget
                if displayMode == .compact {
                    content = Align(
                        alignment: Alignment.center,
                        child: Padding(
                            padding: EdgeInsets(left: 12, top: 0, right: 12, bottom: 0),
                            child: styledIcon
                        )
                    )
                } else {
                    var rowChildren: [Widget] = [
                        Padding(
                            padding: EdgeInsets(left: 12, top: 0, right: 12, bottom: 0),
                            child: styledIcon
                        )
                    ]
                    if let title = action.title {
                        rowChildren.append(Expanded(child: DefaultTextStyle(
                            style: TextStyle(color: textColor, fontSize: 14),
                            child: title
                        )))
                    } else {
                        rowChildren.append(Expanded(child: SizedBox(width: 0, height: 0)))
                    }
                    content = Row(children: rowChildren)
                }

                let decorated: Widget = _NavDecoratedBox(
                    decoration: BoxDecoration(
                        color: tileColor,
                        borderRadius: BorderRadius.all(Radius(circular: 4))
                    ),
                    child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: kPaneItemMinHeight),
                        child: content
                    )
                )

                return Padding(
                    padding: EdgeInsets(left: 6, top: 0, right: 6, bottom: 0),
                    child: decorated
                )
            },
            onPressed: onItemTapped,
            forceEnabled: action.enabled
        )
    }

    // MARK: - Selection Indicator

    private func _buildSelectionIndicator(
        paneTheme: NavigationPaneThemeData,
        displayMode: PaneDisplayMode
    ) -> Widget {
        let isTop = displayMode == .top
        let indicatorColor = paneTheme.highlightColor
        let indicatorDecoration = BoxDecoration(
            color: indicatorColor,
            borderRadius: BorderRadius.all(Radius(circular: 100))
        )

        if isTop {
            // Bottom horizontal indicator for top mode
            return Positioned(
                left: 12,
                right: 12,
                bottom: 0,
                height: 3,
                child: _NavDecoratedBox(decoration: indicatorDecoration)
            )
        } else {
            // Left vertical indicator for sidebar modes
            return Positioned(
                left: 6,
                top: 10,
                bottom: 10,
                width: 3,
                child: _NavDecoratedBox(decoration: indicatorDecoration)
            )
        }
    }
}

// MARK: - _PaneItemExpanderWidget

/// Stateful widget that manages the expanded/collapsed state of a PaneItemExpander.
private class _PaneItemExpanderWidget: StatefulWidget {
    let expander: PaneItemExpander
    let pane: NavigationPane
    let paneTheme: NavigationPaneThemeData
    let displayMode: PaneDisplayMode

    init(
        key: (any Key)? = nil,
        expander: PaneItemExpander,
        pane: NavigationPane,
        paneTheme: NavigationPaneThemeData,
        displayMode: PaneDisplayMode
    ) {
        self.expander = expander
        self.pane = pane
        self.paneTheme = paneTheme
        self.displayMode = displayMode
        super.init(key: key)
    }

    override func createState() -> State<StatefulWidget> {
        return _PaneItemExpanderWidgetState()
    }
}

private class _PaneItemExpanderWidgetState: State<StatefulWidget> {
    private var _isExpanded: Bool = false

    private var expanderWidget: _PaneItemExpanderWidget {
        return widget as! _PaneItemExpanderWidget
    }

    override func initState() {
        super.initState()
        _isExpanded = expanderWidget.expander.initiallyExpanded
    }

    override func build(_ context: any BuildContext) -> Widget {
        let expander = expanderWidget.expander
        let paneTheme = expanderWidget.paneTheme
        let displayMode = expanderWidget.displayMode
        let pane = expanderWidget.pane

        // In compact mode, just show the icon (like a normal compact item)
        if displayMode == .compact {
            return _buildCompactExpander(context: context, expander: expander, paneTheme: paneTheme)
        }

        // Build the header row (clickable to toggle expand)
        let headerWidget = _buildExpanderHeader(
            context: context,
            expander: expander,
            paneTheme: paneTheme,
            displayMode: displayMode
        )

        var columnChildren: [Widget] = [headerWidget]

        // Show children if expanded
        if _isExpanded {
            for childItem in expander.items {
                let childWidget = _buildChildItem(
                    item: childItem,
                    context: context,
                    pane: pane,
                    paneTheme: paneTheme,
                    displayMode: displayMode
                )
                // Indent child items
                columnChildren.append(
                    Padding(
                        padding: EdgeInsets(left: 28, top: 0, right: 0, bottom: 0),
                        child: childWidget
                    )
                )
            }
        }

        return Column(
            mainAxisSize: .min,
            crossAxisAlignment: .start,
            children: columnChildren
        )
    }

    private func _buildCompactExpander(
        context: any BuildContext,
        expander: PaneItemExpander,
        paneTheme: NavigationPaneThemeData
    ) -> Widget {
        let iconWidget: Widget = expander.icon ?? SizedBox(width: 16, height: 16)

        return HoverButton(
            builder: { context, states in
                let textColor: Color = states.isDisabled
                    ? paneTheme.textColorDisabled
                    : (states.isPressed ? paneTheme.textColorSecondary : paneTheme.textColorPrimary)

                let tileColor: Color = states.isPressed
                    ? paneTheme.subtleFillColorTertiary
                    : (states.isHovered ? paneTheme.subtleFillColorSecondary : Color(0x00000000))

                let styledIcon: Widget = IconTheme(
                    data: IconThemeData(size: 16, color: textColor),
                    child: iconWidget
                )

                let decorated: Widget = _NavDecoratedBox(
                    decoration: BoxDecoration(
                        color: tileColor,
                        borderRadius: BorderRadius.all(Radius(circular: 4))
                    ),
                    child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: kPaneItemMinHeight),
                        child: Align(
                            alignment: Alignment.center,
                            child: Padding(
                                padding: EdgeInsets(left: 12, top: 0, right: 12, bottom: 0),
                                child: styledIcon
                            )
                        )
                    )
                )

                return Padding(
                    padding: EdgeInsets(left: 6, top: 0, right: 6, bottom: 0),
                    child: decorated
                )
            },
            onPressed: expander.enabled ? { [self] in
                setState { _isExpanded = !_isExpanded }
            } : nil,
            forceEnabled: expander.enabled
        )
    }

    private func _buildExpanderHeader(
        context: any BuildContext,
        expander: PaneItemExpander,
        paneTheme: NavigationPaneThemeData,
        displayMode: PaneDisplayMode
    ) -> Widget {
        return HoverButton(
            builder: { [self] context, states in
                let textColor: Color = states.isDisabled
                    ? paneTheme.textColorDisabled
                    : (states.isPressed ? paneTheme.textColorSecondary : paneTheme.textColorPrimary)

                let tileColor: Color = states.isPressed
                    ? paneTheme.subtleFillColorTertiary
                    : (states.isHovered ? paneTheme.subtleFillColorSecondary : Color(0x00000000))

                let iconWidget: Widget = expander.icon ?? SizedBox(width: 16, height: 16)
                let styledIcon: Widget = IconTheme(
                    data: IconThemeData(size: 16, color: textColor),
                    child: iconWidget
                )

                var rowChildren: [Widget] = [
                    Padding(
                        padding: EdgeInsets(left: 12, top: 0, right: 12, bottom: 0),
                        child: styledIcon
                    )
                ]

                if let title = expander.title {
                    rowChildren.append(Expanded(child: DefaultTextStyle(
                        style: TextStyle(color: textColor, fontSize: 14),
                        child: title
                    )))
                } else {
                    rowChildren.append(Expanded(child: SizedBox(width: 0, height: 0)))
                }

                // Chevron indicator
                rowChildren.append(
                    Padding(
                        padding: EdgeInsets(left: 0, top: 0, right: 12, bottom: 0),
                        child: FluentGlyph(_isExpanded ? .chevronUp : .chevronDown,
                                           size: 12, color: textColor)
                    )
                )

                let decorated: Widget = _NavDecoratedBox(
                    decoration: BoxDecoration(
                        color: tileColor,
                        borderRadius: BorderRadius.all(Radius(circular: 4))
                    ),
                    child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: kPaneItemMinHeight),
                        child: Row(children: rowChildren)
                    )
                )

                return Padding(
                    padding: EdgeInsets(left: 6, top: 0, right: 6, bottom: 0),
                    child: decorated
                )
            },
            onPressed: expander.enabled ? { [self] in
                setState { _isExpanded = !_isExpanded }
            } : nil,
            forceEnabled: expander.enabled
        )
    }

    private func _buildChildItem(
        item: NavigationPaneItem,
        context: any BuildContext,
        pane: NavigationPane,
        paneTheme: NavigationPaneThemeData,
        displayMode: PaneDisplayMode
    ) -> Widget {
        if let paneItem = item as? PaneItem {
            let index = pane.effectiveIndexOf(paneItem)
            let selected = index == pane.selected

            let itemWidget = paneItem.build(
                context: context,
                selected: selected,
                onPressed: { pane.changeTo(paneItem) },
                displayMode: displayMode,
                themeData: paneTheme
            )

            if pane.showIndicator && selected {
                return Padding(
                    padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 4),
                    child: itemWidget
                )
            }

            return Padding(
                padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 4),
                child: itemWidget
            )
        } else if let separator = item as? PaneItemSeparator {
            return separator.build(context: context, axis: .horizontal)
        } else if let header = item as? PaneItemHeader {
            return header.build(context: context)
        }
        return SizedBox(width: 0, height: 0)
    }
}

// MARK: - _NavDecoratedBox (private helper)

/// A widget that paints a Decoration behind its child.
/// Minimal port matching the pattern used by Card, ListTile, etc.
private class _NavDecoratedBox: SingleChildRenderObjectWidget {
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
