// Ported from: fluent_ui/lib/src/controls/flyouts/content_dialog.dart

import FlutterSwiftBridge

// MARK: - Default Constraints

/// The default constraints for `ContentDialog`.
///
/// The dialog is constrained to 368 logical pixels wide and 756 logical pixels
/// tall by default, following the Windows design guidelines.
nonisolated(unsafe) public let kDefaultContentDialogConstraints = BoxConstraints(
    maxWidth: 368,
    maxHeight: 756
)

// MARK: - ContentDialog

/// A modal dialog that displays contextual information and requires user action.
///
/// Content dialogs block interactions with the app window until explicitly
/// dismissed. They are typically used to request user confirmation, display
/// important information, or gather input before proceeding.
///
/// Usage:
/// ```swift
/// showDialog(context: context, builder: { ctx in
///     ContentDialog(
///         title: Text("Delete file permanently?"),
///         content: Text("If you delete this file, you won't be able to recover it."),
///         actions: [
///             Button(onPressed: { Navigator.pop(ctx) }, child: Text("Cancel")),
///             FilledButton(onPressed: {
///                 // do delete
///                 Navigator.pop(ctx)
///             }, child: Text("Delete"))
///         ]
///     )
/// })
/// ```
public class ContentDialog: StatelessWidget {

    /// The title of the dialog. Usually a `Text` widget.
    public let title: Widget?

    /// The content of the dialog. Usually a `Text` widget.
    public let content: Widget?

    /// The actions of the dialog. Usually a list of `Button` / `FilledButton` widgets.
    public let actions: [Widget]?

    /// The style used by this dialog. If non-nil, it is merged with the default
    /// `ContentDialogThemeData` resolved from the theme.
    public let style: ContentDialogThemeData?

    /// The constraints of the dialog.
    ///
    /// Defaults to `kDefaultContentDialogConstraints` (max width 368, max height 756).
    public let constraints: BoxConstraints

    /// Creates a content dialog.
    public init(
        key: (any Key)? = nil,
        title: Widget? = nil,
        content: Widget? = nil,
        actions: [Widget]? = nil,
        style: ContentDialogThemeData? = nil,
        constraints: BoxConstraints = kDefaultContentDialogConstraints
    ) {
        self.title = title
        self.content = content
        self.actions = actions
        self.style = style
        self.constraints = constraints
        super.init(key: key)
    }

    public override func build(_ context: any BuildContext) -> Widget {
        let resolvedStyle = ContentDialogTheme.of(context).merge(self.style)

        // -- Title widget --
        var titleAndContentChildren: [Widget] = []

        if let title = title {
            let titleWidget: Widget = Padding(
                padding: resolvedStyle.titlePadding ?? EdgeInsets(),
                child: DefaultTextStyle(
                    style: resolvedStyle.titleStyle ?? TextStyle(),
                    child: title
                )
            )
            titleAndContentChildren.append(titleWidget)
        }

        if let content = content {
            let contentWidget: Widget = Flexible(
                child: Padding(
                    padding: resolvedStyle.bodyPadding ?? EdgeInsets(),
                    child: DefaultTextStyle(
                        style: resolvedStyle.bodyStyle ?? TextStyle(),
                        child: content
                    )
                )
            )
            titleAndContentChildren.append(contentWidget)
        }

        // Inner column: title + content with padding
        let innerColumn: Widget = Column(
            mainAxisSize: .min,
            crossAxisAlignment: .start,
            children: titleAndContentChildren
        )

        let paddedInnerColumn: Widget = Flexible(
            child: Padding(
                padding: resolvedStyle.padding ?? EdgeInsets(),
                child: innerColumn
            )
        )

        // -- Actions row --
        var outerColumnChildren: [Widget] = [paddedInnerColumn]

        if let actions = actions, !actions.isEmpty {
            let actionsWidget: Widget
            if actions.count == 1 {
                // Single action: align to the end
                actionsWidget = Align(
                    alignment: Alignment.centerRight,
                    child: actions[0]
                )
            } else {
                // Multiple actions: expand equally with spacing
                let spacing = resolvedStyle.actionsSpacing ?? 10.0
                var rowChildren: [Widget] = []
                for (index, action) in actions.enumerated() {
                    let rightPadding = index != (actions.count - 1) ? spacing : 0.0
                    rowChildren.append(
                        Expanded(
                            child: Padding(
                                padding: EdgeInsets(left: 0, top: 0, right: rightPadding, bottom: 0),
                                child: action
                            )
                        )
                    )
                }
                actionsWidget = Row(
                    mainAxisSize: .min,
                    children: rowChildren
                )
            }

            // Actions container with decoration and padding
            let actionsContainer: Widget = _ContentDialogDecoratedBox(
                decoration: resolvedStyle.actionsDecoration ?? BoxDecoration(),
                child: Padding(
                    padding: resolvedStyle.actionsPadding ?? EdgeInsets(),
                    child: actionsWidget
                )
            )
            outerColumnChildren.append(actionsContainer)
        }

        // Outer column: paddedInnerColumn + actions
        let outerColumn: Widget = Column(
            mainAxisSize: .min,
            crossAxisAlignment: .start,
            children: outerColumnChildren
        )

        // Constrained and decorated container
        let decoratedDialog: Widget = _ContentDialogDecoratedBox(
            decoration: resolvedStyle.decoration ?? BoxDecoration(),
            child: ConstrainedBox(
                constraints: constraints,
                child: outerColumn
            )
        )

        // Center the dialog on screen
        return Align(
            alignment: Alignment.center,
            child: decoratedDialog
        )
    }
}

// MARK: - showContentDialog

/// Displays a `ContentDialog` above the current contents of the app.
///
/// This is a convenience wrapper around `showDialog()` that pushes a dialog
/// route with a modal barrier.
///
/// - Parameters:
///   - context: The build context used to look up the Navigator.
///   - barrierDismissible: Whether tapping the barrier dismisses the dialog. Defaults to `false`.
///   - barrierColor: The color of the modal barrier. Defaults to Smoke
///     (`SmokeFillColorDefault`), Windows' dim under a modal.
///   - builder: A builder that returns the `ContentDialog` widget.
/// - Returns: The dialog route.
@discardableResult
public func showContentDialog(
    context: any BuildContext,
    barrierDismissible: Bool = false,
    barrierColor: Color? = nil,
    builder: @escaping WidgetBuilder
) -> Route {
    return showDialog(
        context: context,
        barrierDismissible: barrierDismissible,
        barrierColor: barrierColor ?? Smoke.color(context),
        builder: builder
    )
}

// MARK: - ContentDialogTheme

/// An inherited widget that defines the configuration for
/// `ContentDialog` widgets in this widget's subtree.
///
/// Values specified here are used for `ContentDialog` properties that are not
/// given an explicit non-null value.
public class ContentDialogTheme: InheritedTheme {

    /// The properties for descendant `ContentDialog` widgets.
    public let data: ContentDialogThemeData

    /// Creates a theme that controls how descendant `ContentDialog` widgets
    /// should look.
    public init(key: (any Key)? = nil, data: ContentDialogThemeData, child: Widget) {
        self.data = data
        super.init(key: key, child: child)
    }

    /// Returns the closest `ContentDialogThemeData` which encloses the given
    /// context.
    ///
    /// Resolution order:
    /// 1. Defaults from `ContentDialogThemeData.standard`
    /// 2. Local `ContentDialogTheme` ancestor
    public static func of(_ context: any BuildContext) -> ContentDialogThemeData {
        let theme = FluentTheme.of(context)
        let inherited = context.dependOnInheritedWidgetOfExactType(ContentDialogTheme.self)
        return ContentDialogThemeData.standard(theme).merge(inherited?.data)
    }

    public override func updateShouldNotify(_ oldWidget: InheritedWidget) -> Bool {
        guard let old = oldWidget as? ContentDialogTheme else { return true }
        return data !== old.data
    }

    public override func wrap(_ context: any BuildContext, _ child: Widget) -> Widget {
        return ContentDialogTheme(data: data, child: child)
    }
}

// MARK: - ContentDialogThemeData

/// Theme data for `ContentDialog` widgets.
///
/// This class defines the visual appearance of content dialogs, including
/// their decoration, padding, and action button styling.
public class ContentDialogThemeData {

    /// The padding around the entire dialog content (title + body area).
    public let padding: EdgeInsets?

    /// The padding around the title.
    public let titlePadding: EdgeInsets?

    /// The padding around the body content.
    public let bodyPadding: EdgeInsets?

    /// The decoration of the dialog background.
    public let decoration: BoxDecoration?

    /// The color of the barrier behind the dialog.
    public let barrierColor: Color?

    /// The spacing between action buttons.
    public let actionsSpacing: Double?

    /// The decoration of the actions area.
    public let actionsDecoration: BoxDecoration?

    /// The padding around the actions area.
    public let actionsPadding: EdgeInsets?

    /// The text style for the dialog title.
    public let titleStyle: TextStyle?

    /// The text style for the dialog body.
    public let bodyStyle: TextStyle?

    /// Creates content dialog theme data.
    public init(
        padding: EdgeInsets? = nil,
        titlePadding: EdgeInsets? = nil,
        bodyPadding: EdgeInsets? = nil,
        decoration: BoxDecoration? = nil,
        barrierColor: Color? = nil,
        actionsSpacing: Double? = nil,
        actionsDecoration: BoxDecoration? = nil,
        actionsPadding: EdgeInsets? = nil,
        titleStyle: TextStyle? = nil,
        bodyStyle: TextStyle? = nil
    ) {
        self.padding = padding
        self.titlePadding = titlePadding
        self.bodyPadding = bodyPadding
        self.decoration = decoration
        self.barrierColor = barrierColor
        self.actionsSpacing = actionsSpacing
        self.actionsDecoration = actionsDecoration
        self.actionsPadding = actionsPadding
        self.titleStyle = titleStyle
        self.bodyStyle = bodyStyle
    }

    /// Creates the standard `ContentDialogThemeData` based on the given `FluentThemeData`.
    ///
    /// This produces the default appearance matching the Windows design guidelines:
    /// - Overlay corners (`FluentCorners.overlay`, 8px)
    /// - Elevation 128 (`FluentElevation.dialog`) over Smoke
    /// - Dialog background uses `menuColor`
    /// - Actions area uses `micaBackgroundColor`
    /// - Title uses the `title` typography style
    /// - Body uses the `body` typography style
    public static func standard(_ theme: FluentThemeData) -> ContentDialogThemeData {
        return ContentDialogThemeData(
            padding: EdgeInsets(all: 20),
            titlePadding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 12),
            decoration: BoxDecoration(
                color: theme.menuColor,
                border: Border.all(
                    color: theme.resources.surfaceStrokeColorDefault,
                    width: FluentStrokeWidth.thin),
                borderRadius: FluentCorners.overlayRadius,
                boxShadow: FluentElevation.shadows(
                    FluentElevation.dialog, brightness: theme.brightness)
            ),
            barrierColor: theme.resources.smokeFillColorDefault,
            actionsSpacing: 10,
            actionsDecoration: BoxDecoration(
                color: theme.micaBackgroundColor,
                borderRadius: BorderRadius.vertical(
                    bottom: Radius(circular: FluentCorners.overlay)
                )
            ),
            actionsPadding: EdgeInsets(all: 20),
            titleStyle: theme.typography.title,
            bodyStyle: theme.typography.body
        )
    }

    /// Merges this `ContentDialogThemeData` with another, with the other
    /// taking precedence.
    public func merge(_ other: ContentDialogThemeData?) -> ContentDialogThemeData {
        guard let other = other else { return self }
        return ContentDialogThemeData(
            padding: other.padding ?? padding,
            titlePadding: other.titlePadding ?? titlePadding,
            bodyPadding: other.bodyPadding ?? bodyPadding,
            decoration: other.decoration ?? decoration,
            barrierColor: other.barrierColor ?? barrierColor,
            actionsSpacing: other.actionsSpacing ?? actionsSpacing,
            actionsDecoration: other.actionsDecoration ?? actionsDecoration,
            actionsPadding: other.actionsPadding ?? actionsPadding,
            titleStyle: other.titleStyle ?? titleStyle,
            bodyStyle: other.bodyStyle ?? bodyStyle
        )
    }
}

// MARK: - _ContentDialogDecoratedBox (private helper)

/// A widget that paints a `BoxDecoration` behind its child.
///
/// This is a minimal decorated box widget used internally by `ContentDialog`.
private class _ContentDialogDecoratedBox: SingleChildRenderObjectWidget {
    let decoration: BoxDecoration

    init(
        key: (any Key)? = nil,
        decoration: BoxDecoration,
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
