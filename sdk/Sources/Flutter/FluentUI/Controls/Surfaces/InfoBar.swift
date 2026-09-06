// Ported from: fluent_ui/lib/src/controls/surfaces/info_bar.dart

import FlutterSwiftBridge

// MARK: - InfoBarSeverity

/// The severity levels that can be applied to an `InfoBar`.
///
/// Each severity level has a distinct visual appearance with an appropriate
/// icon and background color to convey the importance of the message.
public enum InfoBarSeverity {
    /// Informational message with a neutral appearance.
    case info

    /// Warning message with a yellow/orange appearance.
    case warning

    /// Error message with a red appearance.
    case error

    /// Success message with a green appearance.
    case success
}

// MARK: - InfoBar

/// A control for displaying app-wide status messages that are highly visible
/// yet non-intrusive.
///
/// The `InfoBar` supports different severity levels to indicate the type of
/// message (informational, warning, error, or success).
///
/// For info bars with longer content, set `isLong` to `true` to display the
/// content vertically instead of horizontally.
public class InfoBar: StatelessWidget {

    /// The severity of this info bar.
    /// Defaults to `.info`.
    public let severity: InfoBarSeverity

    /// The primary text displayed in the info bar.
    /// Typically a short, descriptive message displayed in bold.
    public let title: Widget

    /// Additional information displayed below or beside the title.
    public let content: Widget?

    /// An optional action widget displayed in the info bar.
    /// Typically a button that allows the user to take action.
    public let action: Widget?

    /// Called when the close button is pressed.
    /// If nil, no close button is displayed.
    public let onClose: (() -> Void)?

    /// Whether the info bar should display content vertically.
    /// When `true`, title, content, and action are arranged in a column.
    /// Defaults to `false`.
    public let isLong: Bool

    /// Whether the severity icon is visible.
    /// Defaults to `true`.
    public let isIconVisible: Bool

    public init(
        key: (any Key)? = nil,
        title: Widget,
        content: Widget? = nil,
        action: Widget? = nil,
        severity: InfoBarSeverity = .info,
        isLong: Bool = false,
        onClose: (() -> Void)? = nil,
        isIconVisible: Bool = true
    ) {
        self.title = title
        self.content = content
        self.action = action
        self.severity = severity
        self.isLong = isLong
        self.onClose = onClose
        self.isIconVisible = isIconVisible
        super.init(key: key)
    }

    public override func build(_ context: any BuildContext) -> Widget {
        let theme = FluentTheme.of(context)

        // -- Severity-based colors --
        let backgroundColor: Color
        let iconColor: Color
        let iconKind: FluentGlyphKind

        switch severity {
        case .info:
            backgroundColor = theme.resources.systemFillColorAttentionBackground
            iconColor = theme.accentColor.defaultBrushFor(theme.brightness)
            iconKind = .info
        case .warning:
            backgroundColor = theme.resources.systemFillColorCautionBackground
            iconColor = theme.resources.systemFillColorCaution
            iconKind = .warning
        case .error:
            backgroundColor = theme.resources.systemFillColorCriticalBackground
            iconColor = theme.resources.systemFillColorCritical
            iconKind = .error
        case .success:
            backgroundColor = theme.resources.systemFillColorSuccessBackground
            iconColor = theme.resources.systemFillColorSuccess
            iconKind = .success
        }

        let decoration = BoxDecoration(
            color: backgroundColor,
            border: Border.all(color: theme.resources.cardStrokeColorDefault),
            borderRadius: BorderRadius.all(Radius(circular: 4))
        )

        // -- Icon --
        // A badge: the severity colour filled, the mark in the on-accent ink,
        // which is what WinUI's InfoBar draws and what stays legible on the
        // caution yellow in both themes.
        let iconWidget: Widget? = isIconVisible ? FluentGlyph(
            iconKind, size: 16, color: iconColor,
            ink: theme.resources.textOnAccentFillColorPrimary) : nil

        // -- Title with bold styling --
        let titleWidget: Widget = Padding(
            padding: EdgeInsets(left: 0, top: 0, right: 6, bottom: 0),
            child: DefaultTextStyle(
                style: (theme.typography.bodyStrong ?? TextStyle()).copyWith(
                    color: theme.resources.textFillColorPrimary
                ),
                child: title
            )
        )

        // -- Content with body styling --
        let contentWidget: Widget? = {
            guard let content = content else { return nil }
            return DefaultTextStyle(
                style: (theme.typography.body ?? TextStyle()).copyWith(
                    color: theme.resources.textFillColorPrimary
                ),
                child: content
            )
        }()

        // -- Close button --
        let closeWidget: Widget? = {
            guard let onClose = onClose else { return nil }
            return Padding(
                padding: EdgeInsets(left: 10, top: 0, right: 0, bottom: 0),
                child: HoverButton(
                    builder: { _, states in
                        let closeBgColor: Color = {
                            if states.isPressed {
                                return theme.resources.subtleFillColorTertiary
                            } else if states.isHovered {
                                return theme.resources.subtleFillColorSecondary
                            } else {
                                return theme.resources.subtleFillColorTransparent
                            }
                        }()
                        return _InfoBarDecoratedBox(
                            decoration: BoxDecoration(
                                color: closeBgColor,
                                borderRadius: BorderRadius.all(Radius(circular: 4))
                            ),
                            child: Padding(
                                padding: EdgeInsets(all: 4),
                                child: FluentGlyph(.dismiss, size: 12,
                                                   color: theme.resources.textFillColorPrimary)
                            )
                        )
                    },
                    onPressed: onClose
                )
            )
        }()

        // -- Layout --
        var rowChildren: [Widget] = []

        // Icon
        if let iconWidget = iconWidget {
            rowChildren.append(
                Padding(
                    padding: EdgeInsets(left: 0, top: 0, right: 14, bottom: 0),
                    child: iconWidget
                )
            )
        }

        if isLong {
            // Vertical layout: title, content, action in a column
            var columnChildren: [Widget] = [titleWidget]

            if let contentWidget = contentWidget {
                columnChildren.append(
                    Padding(
                        padding: EdgeInsets(left: 0, top: 6, right: 0, bottom: 0),
                        child: contentWidget
                    )
                )
            }

            if let action = action {
                columnChildren.append(
                    Padding(
                        padding: EdgeInsets(left: 0, top: 12, right: 0, bottom: 0),
                        child: action
                    )
                )
            }

            rowChildren.append(
                Expanded(child: Column(
                    mainAxisSize: .min,
                    crossAxisAlignment: .start,
                    children: columnChildren
                ))
            )
        } else {
            // Horizontal layout: title, content, action in a row (using Wrap)
            var wrapChildren: [Widget] = [titleWidget]

            if let contentWidget = contentWidget {
                wrapChildren.append(contentWidget)
            }

            if let action = action {
                wrapChildren.append(
                    Padding(
                        padding: EdgeInsets(left: 16, top: 0, right: 0, bottom: 0),
                        child: action
                    )
                )
            }

            rowChildren.append(
                Expanded(child: Wrap(
                    spacing: 6,
                    crossAxisAlignment: .center,
                    children: wrapChildren
                ))
            )
        }

        // Close button
        if let closeWidget = closeWidget {
            rowChildren.append(closeWidget)
        }

        let row = Row(
            mainAxisSize: .min,
            crossAxisAlignment: isLong ? .start : .center,
            children: rowChildren
        )

        return ConstrainedBox(
            constraints: BoxConstraints(minHeight: 48),
            child: _InfoBarDecoratedBox(
                decoration: decoration,
                child: Padding(
                    padding: EdgeInsets(all: 10),
                    child: row
                )
            )
        )
    }
}

// MARK: - _InfoBarDecoratedBox (private helper)

/// A widget that paints a `Decoration` behind its child.
private class _InfoBarDecoratedBox: SingleChildRenderObjectWidget {
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
