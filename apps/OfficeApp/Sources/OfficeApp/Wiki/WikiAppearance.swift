// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge

/// The document-management visual language, scoped to the Wiki shell.
/// Page formatting continues to come from the Writer document.
enum WikiAppearance {
    static let blue = Color(0xFF2449DF), ink = Color(0xFF132442), muted = Color(0xFF536782)
    static let paper = Color(0xFFF7F9FF), line = Color(0xFFE3E9FA), white = Color(0xFFFFFFFF)
    static let selection = Color(0xFFEAF0FF)
    static let accent = AccentColor(swatch: [
        "darkest": Color(0xFF142B92), "darker": Color(0xFF1D3BB7),
        "dark": blue, "normal": blue, "light": Color(0xFF6C85EA),
        "lighter": Color(0xFFA9B8F3), "lightest": selection,
    ])
    static func text(_ size: Double = 15, bold: Bool = false, color: Color = ink) -> Flutter.TextStyle {
        Flutter.TextStyle(color: color, fontSize: size, fontWeight: bold ? .w700 : .w400, fontFamily: "Carlito")
    }
    static var theme: FluentThemeData {
        FluentThemeData(brightness: .light, typography: Typography(
            title: text(30, bold: true), subtitle: text(22, bold: true),
            bodyStrong: text(15, bold: true), body: text(), caption: text(13, color: muted)),
            fontFamily: "Carlito", accentColor: accent, scaffoldBackgroundColor: paper,
            menuColor: white, selectionColor: selection)
    }
    static func button(primary: Bool = false) -> ButtonStyle {
        ButtonStyle(
            textStyle: WidgetStatePropertyAll<Flutter.TextStyle?>(text(15, bold: true)),
            backgroundColor: WidgetStatePropertyHelper.resolveWith { states -> Color? in
                if states.isDisabled { return primary ? Color(0xFF9AAAEF) : paper }
                if states.isPressed { return primary ? Color(0xFF1D3BB7) : selection }
                if states.isHovered { return primary ? Color(0xFF3157E6) : paper }
                return primary ? blue : white
            },
            foregroundColor: WidgetStatePropertyHelper.resolveWith { states -> Color? in
                primary ? white : states.isDisabled ? muted : ink
            },
            padding: WidgetStatePropertyAll<EdgeInsets?>(EdgeInsets(horizontal: 16, vertical: 11)),
            shape: WidgetStatePropertyAll<(any ShapeBorder)?>(RoundedRectangleBorder(
                side: BorderSide(color: line), borderRadius: BorderRadius.circular(7))))
    }
    static let buttons = ButtonThemeData(defaultButtonStyle: button(), filledButtonStyle: button(primary: true))
    static func field(_ controller: TextEditingController, placeholder: String, obscure: Bool = false,
                      autofocus: Bool = false, enabled: Bool = true, onChanged: ((String) -> Void)? = nil,
                      onSubmitted: ((String) -> Void)? = nil) -> Widget {
        SizedBox(height: 46, child: FluentTextBox(controller: controller, placeholderText: placeholder,
            onChanged: onChanged, onSubmitted: onSubmitted, enabled: enabled, style: text(17),
            padding: EdgeInsets(horizontal: 12, vertical: 11), obscureText: obscure,
            decoration: BoxDecoration(color: white, border: Border.all(color: line), borderRadius: BorderRadius.circular(6)),
            focusedDecoration: BoxDecoration(color: white, border: Border.all(color: blue), borderRadius: BorderRadius.circular(6)),
            showFocusRing: false, autofocus: autofocus))
    }
}
