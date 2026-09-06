// Ported from: fluent_ui/lib/src/controls/navigation/tab_view/tab_view.dart
// and fluent_ui/lib/src/controls/navigation/tab_view/tab.dart

import FlutterSwiftBridge

// MARK: - Constants

public let kTabViewMinTileWidth: Double = 80
public let kTabViewMaxTileWidth: Double = 240
public let kTabViewTileHeight: Double = 34
public let kTabViewButtonWidth: Double = 32

// MARK: - CloseButtonVisibilityMode

/// Determines when the close button is visible on a tab.
public enum CloseButtonVisibilityMode {
    /// The close button will never be visible.
    case never

    /// The close button will always be visible.
    case always

    /// The close button will only be shown on hover.
    case onHover
}

// MARK: - TabWidthBehavior

/// Determines how tabs size themselves within a `TabView`.
public enum TabWidthBehavior {
    /// The tab will fit its content.
    case sizeToContent

    /// If not scrollable, the tabs will have the same size.
    case equal

    /// If not selected, the tab's text is hidden. The tab will fit its content.
    case compact
}

// MARK: - Tab

/// Represents a single tab within a `TabView`.
///
/// Each tab has content displayed in the tab strip (`text`) and content
/// displayed in the body area (`body`) when the tab is selected.
public class Tab {
    /// The content that appears inside the tab strip to represent the tab.
    /// Usually a `Text` widget.
    public let text: Widget

    /// The body of the view attached to this tab.
    public let body: Widget

    /// The icon displayed before the tab text. Usually an `Icon` widget.
    public let icon: Widget?

    /// The close icon of the tab. Usually an icon widget.
    public let closeIcon: Widget?

    /// Called when the tab close button is pressed.
    /// If nil, the tab is not closeable and the close button will not be shown.
    public let onClosed: (() -> Void)?

    /// The semantic label for accessibility.
    public let semanticLabel: String?

    /// Whether the tab is disabled.
    public let disabled: Bool

    /// Creates a tab.
    public init(
        text: Widget,
        body: Widget,
        icon: Widget? = nil,
        closeIcon: Widget? = nil,
        onClosed: (() -> Void)? = nil,
        semanticLabel: String? = nil,
        disabled: Bool = false
    ) {
        self.text = text
        self.body = body
        self.icon = icon
        self.closeIcon = closeIcon
        self.onClosed = onClosed
        self.semanticLabel = semanticLabel
        self.disabled = disabled
    }
}

// MARK: - TabView

/// A tabbed interface for displaying multiple pages of content.
///
/// `TabView` provides a familiar tab-based navigation pattern, similar to
/// browser tabs. Users can switch between tabs, and optionally close tabs.
public class TabView: StatefulWidget {
    /// The index of the currently displayed tab.
    public let currentIndex: Int

    /// Called when a different tab is requested to be displayed.
    public let onChanged: ((Int) -> Void)?

    /// The tabs to be displayed.
    public let tabs: [Tab]

    /// Called when the new tab button is pressed.
    /// If nil, the new tab button won't be displayed.
    public let onNewPressed: (() -> Void)?

    /// The minimum width a tab can have.
    public let minTabWidth: Double

    /// The maximum width a tab can have.
    public let maxTabWidth: Double

    /// Indicates the close button visibility mode.
    public let closeButtonVisibility: CloseButtonVisibilityMode

    /// Indicates how a tab will size itself.
    public let tabWidthBehavior: TabWidthBehavior

    /// Displayed before all the tabs and buttons.
    public let header: Widget?

    /// Displayed after all the tabs and buttons.
    public let footer: Widget?

    /// Whether the new button should be displayed.
    public var showNewButton: Bool { onNewPressed != nil }

    public init(
        key: (any Key)? = nil,
        currentIndex: Int,
        tabs: [Tab],
        onChanged: ((Int) -> Void)? = nil,
        onNewPressed: (() -> Void)? = nil,
        minTabWidth: Double = kTabViewMinTileWidth,
        maxTabWidth: Double = kTabViewMaxTileWidth,
        closeButtonVisibility: CloseButtonVisibilityMode = .always,
        tabWidthBehavior: TabWidthBehavior = .equal,
        header: Widget? = nil,
        footer: Widget? = nil
    ) {
        self.currentIndex = currentIndex
        self.tabs = tabs
        self.onChanged = onChanged
        self.onNewPressed = onNewPressed
        self.minTabWidth = minTabWidth
        self.maxTabWidth = maxTabWidth
        self.closeButtonVisibility = closeButtonVisibility
        self.tabWidthBehavior = tabWidthBehavior
        self.header = header
        self.footer = footer
        super.init(key: key)
    }

    public override func createState() -> State<StatefulWidget> {
        return _TabViewState()
    }
}

// MARK: - _TabViewState

class _TabViewState: State<StatefulWidget> {

    private var tabView: TabView {
        return widget as! TabView
    }

    override func build(_ context: any BuildContext) -> Widget {
        let theme = FluentTheme.of(context)
        let w = tabView

        // Build tab strip
        var tabStripChildren: [Widget] = []

        // Header
        if let header = w.header {
            tabStripChildren.append(
                Padding(
                    padding: EdgeInsets(left: 0, top: 0, right: 12, bottom: 0),
                    child: header
                )
            )
        }

        // Tab buttons
        var tabButtons: [Widget] = []
        for i in 0..<w.tabs.count {
            let tab = w.tabs[i]
            let isSelected = i == w.currentIndex

            let tabButton = _buildTabButton(context, index: i, tab: tab, isSelected: isSelected)

            // Add divider between tabs (hidden near selected tab)
            let dividerHidden = (i == w.currentIndex - 1) || (i == w.currentIndex)
            let dividerWidget: Widget = SizedBox(
                height: kTabViewTileHeight,
                child: Divider(
                    direction: .vertical,
                    style: dividerHidden
                        ? DividerThemeData(
                            decoration: BoxDecoration(color: Color(0x00000000))
                        )
                        : nil
                )
            )

            let tabWithDivider: Widget = Row(
                mainAxisSize: .min,
                children: [tabButton, dividerWidget]
            )

            switch w.tabWidthBehavior {
            case .sizeToContent, .compact:
                tabButtons.append(tabWithDivider)
            case .equal:
                tabButtons.append(
                    Expanded(child: tabWithDivider)
                )
            }
        }

        // Wrap tab buttons in a clipped row
        let tabRow: Widget = Row(
            mainAxisSize: w.tabWidthBehavior == .equal ? .max : .min,
            children: tabButtons
        )

        tabStripChildren.append(
            Expanded(
                child: ClipRect(child: tabRow)
            )
        )

        // New tab button
        if w.showNewButton {
            let newButton: Widget = _buildStripButton(
                context,
                icon: Text("+", style: TextStyle(color: theme.inactiveColor, fontSize: 12)),
                onPressed: w.onNewPressed
            )
            tabStripChildren.append(
                Padding(
                    padding: EdgeInsets(left: 3, top: 0, right: 0, bottom: 3),
                    child: newButton
                )
            )
        }

        // Footer
        if let footer = w.footer {
            tabStripChildren.append(
                Padding(
                    padding: EdgeInsets(left: 12, top: 0, right: 0, bottom: 0),
                    child: footer
                )
            )
        }

        // Tab strip
        let tabStrip: Widget = Padding(
            padding: EdgeInsets(left: 8, top: 4, right: 0, bottom: 0),
            child: SizedBox(
                height: kTabViewTileHeight,
                child: Row(children: tabStripChildren)
            )
        )

        // Content area
        let contentArea: Widget
        if !w.tabs.isEmpty && w.currentIndex >= 0 && w.currentIndex < w.tabs.count {
            contentArea = Expanded(
                child: w.tabs[w.currentIndex].body
            )
        } else {
            contentArea = Expanded(child: SizedBox(width: 0, height: 0))
        }

        return Column(
            children: [tabStrip, contentArea]
        )
    }

    // MARK: - Tab Button Builder

    private func _buildTabButton(
        _ context: any BuildContext,
        index: Int,
        tab: Tab,
        isSelected: Bool
    ) -> Widget {
        let theme = FluentTheme.of(context)
        let res = theme.resources
        let w = tabView

        return HoverButton(
            builder: { [self] context, states in
                // Foreground color
                let foregroundColor: Color = {
                    if isSelected {
                        return res.textFillColorPrimary
                    } else if states.isPressed {
                        return res.textFillColorSecondary
                    } else if states.isHovered {
                        return res.textFillColorPrimary
                    } else if states.isDisabled {
                        return res.textFillColorDisabled
                    } else {
                        return res.textFillColorSecondary
                    }
                }()

                // Background color
                let backgroundColor: Color = {
                    if isSelected {
                        return res.solidBackgroundFillColorTertiary
                    } else if states.isPressed {
                        return res.layerOnMicaBaseAltFillColorDefault
                    } else if states.isHovered {
                        return res.layerOnMicaBaseAltFillColorSecondary
                    } else {
                        return res.layerOnMicaBaseAltFillColorTransparent
                    }
                }()

                let borderRadius = BorderRadius.only(
                    topLeft: Radius(circular: 6),
                    topRight: Radius(circular: 6),
                    bottomLeft: Radius(circular: 0),
                    bottomRight: Radius(circular: 0)
                )

                // Build row children for the tab content
                var rowChildren: [Widget] = []

                // Icon
                if let icon = tab.icon {
                    rowChildren.append(
                        Padding(
                            padding: EdgeInsets(left: 0, top: 0, right: 10, bottom: 0),
                            child: IconTheme(
                                data: IconThemeData(size: 16, color: foregroundColor),
                                child: icon
                            )
                        )
                    )
                }

                // Text (hidden in compact mode when not selected)
                let showText = w.tabWidthBehavior != .compact || isSelected
                if showText {
                    rowChildren.append(
                        Expanded(
                            child: Padding(
                                padding: EdgeInsets(left: 0, top: 0, right: 4, bottom: 0),
                                child: DefaultTextStyle(
                                    style: TextStyle(
                                        color: foregroundColor,
                                        fontSize: 12,
                                        fontWeight: isSelected ? .w600 : nil
                                    ),
                                    child: tab.text
                                )
                            )
                        )
                    )
                }

                // Close button
                let showClose: Bool = {
                    guard tab.onClosed != nil else { return false }
                    switch w.closeButtonVisibility {
                    case .always:
                        return true
                    case .onHover:
                        return states.isHovered
                    case .never:
                        return false
                    }
                }()

                if showClose {
                    let closeButton: Widget = SizedBox(
                        width: 24,
                        height: 24,
                        child: IconButton(
                            icon: tab.closeIcon ?? FluentGlyph(.dismiss, size: 10, color: foregroundColor),
                            onPressed: { [weak self] in
                                guard let self = self else { return }
                                let closedTab = self.tabView.tabs[index]
                                closedTab.onClosed?()
                            }
                        )
                    )
                    rowChildren.append(
                        Padding(
                            padding: EdgeInsets(left: 4, top: 0, right: 0, bottom: 0),
                            child: closeButton
                        )
                    )
                }

                // Tab container with decoration
                // When selected, reserve 2px for the accent indicator below
                let tabHeight = isSelected ? kTabViewTileHeight - 2 : kTabViewTileHeight
                let tabPadding = isSelected
                    ? EdgeInsets(left: 9, top: 3, right: 5, bottom: 2)
                    : EdgeInsets(left: 8, top: 3, right: 4, bottom: 3)

                let tabDecoration = BoxDecoration(
                    color: backgroundColor,
                    borderRadius: borderRadius
                )

                var tabContent: Widget = _TabDecoratedBox(
                    decoration: tabDecoration,
                    child: SizedBox(
                        height: tabHeight,
                        child: Padding(
                            padding: tabPadding,
                            child: Row(
                                mainAxisSize: .min,
                                children: rowChildren
                            )
                        )
                    )
                )

                // Selected indicator: accent-colored underline
                if isSelected {
                    let accentColor = theme.accentColor.defaultBrushFor(theme.brightness)
                    let indicator: Widget = _TabDecoratedBox(
                        decoration: BoxDecoration(
                            color: accentColor,
                            borderRadius: BorderRadius.circular(1)
                        ),
                        child: SizedBox(height: 2)
                    )
                    tabContent = Column(
                        mainAxisSize: .min,
                        children: [tabContent, indicator]
                    )
                }

                return tabContent
            },
            onPressed: tab.disabled
                ? nil
                : (w.onChanged == nil
                    ? nil
                    : { [weak self] in
                        guard let self = self else { return }
                        self.tabView.onChanged?(index)
                    })
        )
    }

    // MARK: - Strip Button Builder

    private func _buildStripButton(
        _ context: any BuildContext,
        icon: Widget,
        onPressed: (() -> Void)?
    ) -> Widget {
        let theme = FluentTheme.of(context)

        return SizedBox(
            width: kTabViewButtonWidth,
            height: 28,
            child: HoverButton(
                builder: { context, states in
                    let bgColor: Color = {
                        if states.isDisabled || states.isNone {
                            return Color(0x00000000)
                        } else if states.isPressed {
                            return theme.resources.subtleFillColorTertiary
                        } else if states.isHovered {
                            return theme.resources.subtleFillColorSecondary
                        } else {
                            return Color(0x00000000)
                        }
                    }()

                    return _TabDecoratedBox(
                        decoration: BoxDecoration(
                            color: bgColor,
                            borderRadius: BorderRadius.circular(4)
                        ),
                        child: Center(child: icon)
                    )
                },
                onPressed: onPressed
            )
        )
    }
}

// MARK: - _TabDecoratedBox (private helper)

/// A widget that paints a `Decoration` behind its child.
private class _TabDecoratedBox: SingleChildRenderObjectWidget {
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

// MARK: - TabViewThemeData

/// Theme data for `TabView` widgets.
public class TabViewThemeData {
    /// The background color of the tab strip.
    public let tabStripColor: Color?

    /// The height of individual tabs.
    public let tabHeight: Double?

    /// The minimum width of individual tabs.
    public let minTabWidth: Double?

    /// The maximum width of individual tabs.
    public let maxTabWidth: Double?

    /// The padding inside the tab strip.
    public let tabStripPadding: EdgeInsets?

    public init(
        tabStripColor: Color? = nil,
        tabHeight: Double? = nil,
        minTabWidth: Double? = nil,
        maxTabWidth: Double? = nil,
        tabStripPadding: EdgeInsets? = nil
    ) {
        self.tabStripColor = tabStripColor
        self.tabHeight = tabHeight
        self.minTabWidth = minTabWidth
        self.maxTabWidth = maxTabWidth
        self.tabStripPadding = tabStripPadding
    }

    /// Creates the standard theme data based on the given theme.
    public static func standard(_ theme: FluentThemeData) -> TabViewThemeData {
        return TabViewThemeData(
            tabHeight: kTabViewTileHeight,
            minTabWidth: kTabViewMinTileWidth,
            maxTabWidth: kTabViewMaxTileWidth
        )
    }

    /// Merge this theme data with another, with the other taking precedence.
    public func merge(_ other: TabViewThemeData?) -> TabViewThemeData {
        guard let other = other else { return self }
        return TabViewThemeData(
            tabStripColor: other.tabStripColor ?? tabStripColor,
            tabHeight: other.tabHeight ?? tabHeight,
            minTabWidth: other.minTabWidth ?? minTabWidth,
            maxTabWidth: other.maxTabWidth ?? maxTabWidth,
            tabStripPadding: other.tabStripPadding ?? tabStripPadding
        )
    }
}

// MARK: - TabViewTheme

/// An inherited theme that controls how descendant `TabView` widgets look.
public class TabViewTheme: InheritedTheme {
    /// The theme data for the tab view theme.
    public let data: TabViewThemeData

    public init(key: (any Key)? = nil, data: TabViewThemeData, child: Widget) {
        self.data = data
        super.init(key: key, child: child)
    }

    /// Returns the closest `TabViewThemeData` which encloses the given context.
    public static func of(_ context: any BuildContext) -> TabViewThemeData {
        let theme = FluentTheme.of(context)
        let inherited = context.dependOnInheritedWidgetOfExactType(TabViewTheme.self)
        return TabViewThemeData.standard(theme).merge(inherited?.data)
    }

    public override func updateShouldNotify(_ oldWidget: InheritedWidget) -> Bool {
        guard let old = oldWidget as? TabViewTheme else { return true }
        return data !== old.data
    }

    public override func wrap(_ context: any BuildContext, _ child: Widget) -> Widget {
        return TabViewTheme(data: data, child: child)
    }
}
