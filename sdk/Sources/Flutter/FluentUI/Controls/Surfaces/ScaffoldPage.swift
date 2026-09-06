// Ported from: fluent_ui/lib/src/controls/surfaces/scaffold_page.dart
//
// ScaffoldPage provides a standard Fluent UI page layout with an optional
// header, padding, and scrollable content.

import FlutterSwiftBridge

// MARK: - PageHeader

/// A header widget used at the top of a `ScaffoldPage`.
///
/// Displays a title and optional command bar aligned to the right.
///
/// Usage:
/// ```swift
/// PageHeader(
///     title: Text("Settings"),
///     commandBar: Row(children: [...])
/// )
/// ```
public class PageHeader: StatelessWidget {
    /// The title displayed in the header.
    public let title: Widget

    /// An optional command bar displayed on the trailing side.
    public let commandBar: Widget?

    /// Creates a page header.
    public init(
        key: (any Key)? = nil,
        title: Widget,
        commandBar: Widget? = nil
    ) {
        self.title = title
        self.commandBar = commandBar
        super.init(key: key)
    }

    public override func build(_ context: any BuildContext) -> Widget {
        let theme = FluentTheme.of(context)

        let titleWidget: Widget = DefaultTextStyle(
            style: TextStyle(
                color: theme.resources.textFillColorPrimary,
                fontSize: 28,
                fontWeight: .w600
            ),
            child: title
        )

        var rowChildren: [Widget] = [
            Expanded(child: titleWidget)
        ]

        if let commandBar = commandBar {
            rowChildren.append(commandBar)
        }

        return Padding(
            padding: EdgeInsets(left: 24, top: 16, right: 24, bottom: 16),
            child: Row(
                crossAxisAlignment: .center,
                children: rowChildren
            )
        )
    }
}

// MARK: - ScaffoldPage

/// A standard Fluent UI page layout.
///
/// Provides a consistent page structure with an optional header, content area,
/// and padding. Use `ScaffoldPage.scrollable` for pages with scrollable content.
///
/// Usage:
/// ```swift
/// ScaffoldPage(
///     header: PageHeader(title: Text("My Page")),
///     content: Center(child: Text("Hello!"))
/// )
/// ```
public class ScaffoldPage: StatelessWidget {
    /// An optional header widget displayed at the top of the page.
    public let header: Widget?

    /// The main content of the page.
    public let content: Widget?

    /// The bottom bar widget displayed at the bottom of the page.
    public let bottomBar: Widget?

    /// The padding applied around the content.
    public let padding: EdgeInsets

    /// Creates a scaffold page.
    public init(
        key: (any Key)? = nil,
        header: Widget? = nil,
        content: Widget? = nil,
        bottomBar: Widget? = nil,
        padding: EdgeInsets = EdgeInsets(left: 24, top: 0, right: 24, bottom: 24)
    ) {
        self.header = header
        self.content = content
        self.bottomBar = bottomBar
        self.padding = padding
        super.init(key: key)
    }

    /// Creates a scaffold page with scrollable content.
    ///
    /// The content is automatically wrapped in a `SingleChildScrollView`.
    public static func scrollable(
        key: (any Key)? = nil,
        header: Widget? = nil,
        bottomBar: Widget? = nil,
        padding: EdgeInsets = EdgeInsets(left: 24, top: 0, right: 24, bottom: 24),
        children: [Widget] = []
    ) -> ScaffoldPage {
        let scrollContent: Widget = SingleChildScrollView(
            child: Column(
                crossAxisAlignment: .start,
                children: children
            )
        )

        return ScaffoldPage(
            key: key,
            header: header,
            content: scrollContent,
            bottomBar: bottomBar,
            padding: padding
        )
    }

    public override func build(_ context: any BuildContext) -> Widget {
        var columnChildren: [Widget] = []

        // Header
        if let header = header {
            columnChildren.append(header)
        }

        // Content area with padding
        if let content = content {
            columnChildren.append(
                Expanded(
                    child: Padding(
                        padding: padding,
                        child: content
                    )
                )
            )
        } else {
            columnChildren.append(Expanded(child: SizedBox(width: 0, height: 0)))
        }

        // Bottom bar
        if let bottomBar = bottomBar {
            columnChildren.append(bottomBar)
        }

        // The page paints the theme's background, as fluent_ui's ScaffoldPage
        // does. Nothing above it does: FluentApp supplies the theme, the
        // Directionality and a Navigator, but no paint — the same division as
        // MaterialApp and Scaffold. Without this a page composites onto
        // whatever the host cleared the surface to, which for a plain windowed
        // app is black, and the theme's near-black body text is then invisible
        // on it. A window that renders a button and no text is what that looks
        // like from the outside.
        return ColoredBox(
            color: FluentTheme.of(context).scaffoldBackgroundColor,
            // Stretch, as fluent_ui's ScaffoldPage does: a page's header and
            // content span its width and lay out from the left. A centred
            // column would size the content to its widest line and float it
            // in the middle of the page — a title, a paragraph and a button
            // stacked in the centre of an otherwise empty window.
            child: Column(crossAxisAlignment: .stretch, children: columnChildren)
        )
    }
}
