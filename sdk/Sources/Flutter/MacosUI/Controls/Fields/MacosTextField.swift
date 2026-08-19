// MacosTextField ported from macos_ui/lib/src/fields/text_field.dart

import FlutterSwiftBridge

// MARK: - MacosTextField

/// A macOS-style text field with rounded borders and focus state styling.
public class MacosTextField: StatefulWidget {
    public let controller: TextEditingController?
    public let placeholder: String?
    public let prefix: Widget?
    public let suffix: Widget?
    public let enabled: Bool
    public let maxLines: Int
    public let minLines: Int
    public let onChanged: ((String) -> Void)?
    public let onSubmitted: ((String) -> Void)?
    public let style: TextStyle?
    public let padding: EdgeInsets
    public let decoration: BoxDecoration?

    /// Whether the focus ring is drawn. Off for a field whose surroundings
    /// already draw the chrome — see FluentTextBox.showFocusRing.
    public let showFocusRing: Bool
    /// Renders every character as `obscuringCharacter` — a password field.
    /// The editing underneath is unchanged; only what is painted differs.
    public let obscureText: Bool
    public let obscuringCharacter: String
    /// Takes the keyboard as soon as it is mounted — see `FluentTextBox`.
    public let autofocus: Bool

    public init(
        key: (any Key)? = nil,
        controller: TextEditingController? = nil,
        placeholder: String? = nil,
        prefix: Widget? = nil,
        suffix: Widget? = nil,
        enabled: Bool = true,
        maxLines: Int = 1,
        minLines: Int = 1,
        onChanged: ((String) -> Void)? = nil,
        onSubmitted: ((String) -> Void)? = nil,
        style: TextStyle? = nil,
        padding: EdgeInsets = EdgeInsets(horizontal: 6, vertical: 4),
        decoration: BoxDecoration? = nil,
        showFocusRing: Bool = true,
        obscureText: Bool = false,
        obscuringCharacter: String = "\u{2022}",
        autofocus: Bool = false
    ) {
        self.controller = controller
        self.placeholder = placeholder
        self.prefix = prefix
        self.suffix = suffix
        self.enabled = enabled
        self.maxLines = maxLines
        self.minLines = minLines
        self.onChanged = onChanged
        self.onSubmitted = onSubmitted
        self.style = style
        self.padding = padding
        self.decoration = decoration
        self.showFocusRing = showFocusRing
        self.obscureText = obscureText
        self.obscuringCharacter = obscuringCharacter
        self.autofocus = autofocus
        super.init(key: key)
    }

    public override func createState() -> State<StatefulWidget> {
        return _MacosTextFieldState()
    }
}

class _MacosTextFieldState: State<StatefulWidget> {
    private var field: MacosTextField {
        return widget as! MacosTextField
    }

    override func build(_ context: any BuildContext) -> Widget {
        let theme = MacosTheme.of(context)
        let isDark = theme.brightness == .dark

        let bgDecoration = field.decoration ?? BoxDecoration(
            color: isDark
                ? Color(rgbo: 30, 30, 30, 1.0)
                : MacosColors.white,
            border: Border.all(
                color: isDark
                    ? Color(rgbo: 255, 255, 255, 0.15)
                    : Color(rgbo: 0, 0, 0, 0.15),
                width: 0.5
            ),
            borderRadius: BorderRadius.all(Radius(circular: 5)),
            boxShadow: isDark
                ? []
                : [BoxShadow(
                    color: Color(rgbo: 0, 0, 0, 0.06),
                    offset: Offset(0, 0.5),
                    blurRadius: 1
                  )]
        )

        // The macOS focus ring: accent-colored border on the same shape.
        let focusedDecoration = field.decoration ?? BoxDecoration(
            color: isDark
                ? Color(rgbo: 30, 30, 30, 1.0)
                : MacosColors.white,
            border: Border.all(color: theme.primaryColor, width: 1.5),
            borderRadius: BorderRadius.all(Radius(circular: 5))
        )

        // Editing (focus, caret, key handling, placeholder logic) comes from
        // the Fluent text box; only the chrome above is macOS. A FluentTheme
        // ancestor is required by that widget — MacosApp installs one, and the
        // fallback keeps the field usable outside it.
        let fluentData = FluentTheme.maybeOf(context)
            ?? (isDark ? FluentThemeData.dark() : FluentThemeData.light())

        return FluentTheme(
            data: fluentData,
            child: FluentTextBox(
                controller: field.controller,
                placeholderText: field.placeholder,
                onChanged: field.onChanged,
                onSubmitted: field.onSubmitted,
                maxLines: field.maxLines,
                enabled: field.enabled,
                style: field.style ?? theme.typography.body,
                padding: field.padding,
                obscureText: field.obscureText,
                obscuringCharacter: field.obscuringCharacter,
                decoration: bgDecoration,
                focusedDecoration: focusedDecoration,
                showFocusRing: field.showFocusRing,
                prefix: field.prefix,
                suffix: field.suffix,
                autofocus: field.autofocus
            )
        )
    }
}

// MARK: - MacosSearchField

/// A macOS-style search field with a magnifying glass icon.
public class MacosSearchField: StatelessWidget {
    public let controller: TextEditingController?
    public let placeholder: String
    public let onChanged: ((String) -> Void)?
    public let onSubmitted: ((String) -> Void)?
    public let enabled: Bool

    public init(
        key: (any Key)? = nil,
        controller: TextEditingController? = nil,
        placeholder: String = "Search",
        onChanged: ((String) -> Void)? = nil,
        onSubmitted: ((String) -> Void)? = nil,
        enabled: Bool = true
    ) {
        self.controller = controller
        self.placeholder = placeholder
        self.onChanged = onChanged
        self.onSubmitted = onSubmitted
        self.enabled = enabled
        super.init(key: key)
    }

    public override func build(_ context: any BuildContext) -> Widget {
        let theme = MacosTheme.of(context)
        let isDark = theme.brightness == .dark

        return MacosTextField(
            controller: controller,
            placeholder: placeholder,
            prefix: Text(
                "\u{2315}",
                style: TextStyle(color: MacosColors.placeholderTextColor, fontSize: 12)
            ),
            enabled: enabled,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
            decoration: BoxDecoration(
                color: isDark
                    ? Color(rgbo: 30, 30, 30, 1.0)
                    : MacosColors.white,
                border: Border.all(
                    color: isDark
                        ? Color(rgbo: 255, 255, 255, 0.15)
                        : Color(rgbo: 0, 0, 0, 0.15),
                    width: 0.5
                ),
                borderRadius: BorderRadius.all(Radius(circular: 7))
            )
        )
    }
}
