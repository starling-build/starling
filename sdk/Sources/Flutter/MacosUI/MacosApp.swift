// macOS app wrapper ported from macos_ui/lib/src/macos_app.dart

import FlutterSwiftBridge

// MARK: - MacosApp

/// An application that uses macOS design.
///
/// A convenience widget that wraps a number of widgets commonly required for
/// macOS applications. It resolves the active theme based on [themeMode] and
/// wraps the [home] widget with [AnimatedMacosTheme], [IconTheme], and
/// [DefaultTextStyle].
public class MacosApp: StatefulWidget {

    /// Default visual properties for this app's macOS widgets.
    public let theme: MacosThemeData?

    /// The MacosThemeData to use when a dark mode is active.
    public let darkTheme: MacosThemeData?

    /// Determines which theme will be used.
    public let themeMode: ThemeMode

    /// The primary content of the application.
    public let home: Widget

    /// A short description of the application.
    public let title: String

    public init(
        key: (any Key)? = nil,
        theme: MacosThemeData? = nil,
        darkTheme: MacosThemeData? = nil,
        themeMode: ThemeMode = .system,
        home: Widget,
        title: String = ""
    ) {
        self.theme = theme
        self.darkTheme = darkTheme
        self.themeMode = themeMode
        self.home = home
        self.title = title
        super.init(key: key)
    }

    public override func createState() -> State<StatefulWidget> {
        return _MacosAppState()
    }
}

// MARK: - _MacosAppState

class _MacosAppState: State<StatefulWidget> {

    private var app: MacosApp {
        return widget as! MacosApp
    }

    private func resolveTheme() -> MacosThemeData {
        let useDarkStyle: Bool
        switch app.themeMode {
        case .dark:
            useDarkStyle = true
        case .light:
            useDarkStyle = false
        case .system:
            useDarkStyle = false
        }

        if useDarkStyle {
            return app.darkTheme ?? app.theme ?? MacosThemeData(brightness: .dark)
        } else {
            return app.theme ?? MacosThemeData(brightness: .light)
        }
    }

    override func build(_ context: any BuildContext) -> Widget {
        let themeData = resolveTheme()

        // Include FluentTheme so FluentUI widgets (e.g. Slider) used inside
        // MacosApp can resolve FluentTheme.of(context).
        // In the app's own accent, so a Fluent button beside a Macos one
        // is the same blue rather than Windows'.
        let fluentData = FluentThemeData(
            brightness: themeData.brightness,
            accentColor: themeData.primaryColor.toAccentColor())

        return Directionality(
            textDirection: .ltr,
            child: FluentTheme(
                data: fluentData,
                child: AnimatedMacosTheme(
                    data: themeData,
                    // Navigator (with its own Overlay) so that showDialog /
                    // Navigator.push work inside Macos apps.
                    child: Navigator(home: self.app.home),
                    curve: Curves.easeInOut
                )
            )
        )
    }
}
