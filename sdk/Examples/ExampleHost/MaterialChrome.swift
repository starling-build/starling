// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The handful of Material widgets the famous Flutter samples lean on —
// Scaffold, AppBar, FloatingActionButton — recreated from this framework's
// primitives, styled after the classic `flutter create` (Material 2, blue
// primary-swatch) look. The framework carries FluentUI and MacosUI widget
// sets but no Material one; this file is just enough chrome for the ports,
// not a Material library.

#if os(Linux) || os(Windows) || os(macOS)
import Flutter
import FlutterSwiftBridge

/// The Material 2 default palette the classic samples render with.
public enum MaterialColors {
    public static let primary = Color(0xFF2196F3)        // blue 500
    public static let scaffoldBackground = Color(0xFFFAFAFA)
    public static let onPrimary = Color(0xFFFFFFFF)
    public static let body = Color(0xDD000000)           // black87
    public static let headline = Color(0x8A000000)       // black54
    public static let divider = Color(0x1F000000)        // black12
    public static let red = Color(0xFFF44336)            // red 500
}

// MARK: - MaterialScaffold

/// Scaffold: app bar on top, body filling the rest, optional floating
/// action button pinned to the bottom-right.
public class MaterialScaffold: StatelessWidget {
    public let appBar: Widget?
    public let body: Widget
    public let floatingActionButton: Widget?
    public let backgroundColor: Color

    public init(
        key: (any Key)? = nil,
        appBar: Widget? = nil,
        body: Widget,
        floatingActionButton: Widget? = nil,
        backgroundColor: Color = MaterialColors.scaffoldBackground
    ) {
        self.appBar = appBar
        self.body = body
        self.floatingActionButton = floatingActionButton
        self.backgroundColor = backgroundColor
        super.init(key: key)
    }

    public override func build(_ context: any BuildContext) -> Widget {
        var columnChildren: [Widget] = []
        if let appBar = appBar { columnChildren.append(appBar) }
        columnChildren.append(Expanded(child: body))

        var stackChildren: [Widget] = [
            ColoredBox(
                color: backgroundColor,
                child: Column(crossAxisAlignment: .stretch, children: columnChildren)
            )
        ]
        if let fab = floatingActionButton {
            stackChildren.append(Positioned(right: 16, bottom: 16, child: fab))
        }
        return Stack(children: stackChildren)
    }
}

// MARK: - MaterialAppBar

/// AppBar: 56dp toolbar in the primary color with an elevation-4 shadow,
/// optional leading widget (back button) and trailing actions.
public class MaterialAppBar: StatelessWidget {
    public let title: String
    public let leading: Widget?
    public let actions: [Widget]

    public init(
        key: (any Key)? = nil,
        title: String,
        leading: Widget? = nil,
        actions: [Widget] = []
    ) {
        self.title = title
        self.leading = leading
        self.actions = actions
        super.init(key: key)
    }

    public override func build(_ context: any BuildContext) -> Widget {
        var rowChildren: [Widget] = []
        if let leading = leading {
            rowChildren.append(SizedBox(width: 56, height: 56, child: Center(child: leading)))
        } else {
            rowChildren.append(SizedBox(width: 16, height: 56))
        }
        rowChildren.append(Expanded(
            child: Text(
                title,
                style: TextStyle(
                    color: MaterialColors.onPrimary,
                    fontSize: 20,
                    fontWeight: .w500
                ),
                maxLines: 1
            )
        ))
        for action in actions {
            rowChildren.append(SizedBox(width: 48, height: 56, child: Center(child: action)))
        }
        rowChildren.append(SizedBox(width: 8, height: 56))

        return DecoratedBox(
            decoration: BoxDecoration(
                color: MaterialColors.primary,
                boxShadow: [
                    BoxShadow(
                        color: Color(0x33000000),
                        offset: Offset(0, 2),
                        blurRadius: 4
                    )
                ]
            ),
            child: SizedBox(
                height: 56,
                child: Row(crossAxisAlignment: .center, children: rowChildren)
            )
        )
    }
}

// MARK: - MaterialFloatingActionButton

/// FloatingActionButton: the 56dp raised circle.
public class MaterialFloatingActionButton: StatelessWidget {
    public let onPressed: () -> Void
    public let child: Widget

    public init(key: (any Key)? = nil, onPressed: @escaping () -> Void, child: Widget) {
        self.onPressed = onPressed
        self.child = child
        super.init(key: key)
    }

    public override func build(_ context: any BuildContext) -> Widget {
        return GestureDetector(
            onTap: onPressed,
            child: DecoratedBox(
                decoration: BoxDecoration(
                    color: MaterialColors.primary,
                    boxShadow: [
                        BoxShadow(
                            color: Color(0x4D000000),
                            offset: Offset(0, 3),
                            blurRadius: 6
                        )
                    ],
                    shape: .circle
                ),
                child: SizedBox(width: 56, height: 56, child: Center(child: child))
            )
        )
    }
}

// MARK: - MaterialDivider

/// Divider: the 16dp-tall separator with a hairline rule, as `Divider()`
/// renders in the list samples.
public class MaterialDivider: StatelessWidget {
    public override init(key: (any Key)? = nil) {
        super.init(key: key)
    }

    public override func build(_ context: any BuildContext) -> Widget {
        return SizedBox(
            height: 16,
            child: Center(
                child: SizedBox(
                    height: 1,
                    child: ColoredBox(color: MaterialColors.divider, child: SizedBox(expand: ()))
                )
            )
        )
    }
}

// MARK: - MaterialPageRoute

/// A full-screen route for Navigator.push, standing in for the material
/// library's MaterialPageRoute (no transition animation).
public class MaterialPageRoute: ModalRoute {
    private let builder: WidgetBuilder

    public init(builder: @escaping WidgetBuilder) {
        self.builder = builder
        super.init()
    }

    public override var barrierColor: Color? { return nil }

    public override func buildContent(_ context: any BuildContext) -> Widget {
        return builder(context)
    }
}
#endif
