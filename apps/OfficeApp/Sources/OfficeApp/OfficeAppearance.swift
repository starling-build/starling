// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import OfficeText
import FlutterSwiftBridge

/// Writer's chrome palette. Document formatting remains owned by the document.
enum OfficeAppearance {
    static let brand = Color(0xFF2459EE)
    static let titleBar = Color(0xFF204BC4)
    static let white = Color(0xFFFFFFFF)
    static let accent = AccentColor(swatch: [
        "darkest": Color(0xFF16328A), "darker": Color(0xFF1D43B5),
        "dark": brand, "normal": brand, "light": Color(0xFF638DFF),
        "lighter": Color(0xFF93B2FF), "lightest": Color(0xFFDCE7FF),
    ])

    static func surface(_ theme: FluentThemeData) -> Color {
        theme.brightness == .dark ? Color(0xFF202B40) : white
    }

    static func canvas(_ theme: FluentThemeData) -> Color {
        theme.brightness == .dark ? Color(0xFF151E2E) : Color(0xFFEDF1F7)
    }

    /// Increase Contrast: a control edge must reach 3:1 against its surface, and the text 7:1.
    private static var contrast: Bool { SystemDisplay.current.increasedContrast }

    static func border(_ theme: FluentThemeData) -> Color {
        if contrast { return theme.brightness == .dark ? Color(0xFF8FA0BB) : Color(0xFF6B7A93) }
        return theme.brightness == .dark ? Color(0xFF364359) : Color(0xFFDDE4EF)
    }

    static func ink(_ theme: FluentThemeData) -> Color {
        if contrast { return theme.brightness == .dark ? white : Color(0xFF000000) }
        return theme.brightness == .dark ? Color(0xFFF1F5FF) : Color(0xFF1B2943)
    }

    static func secondary(_ theme: FluentThemeData) -> Color {
        if contrast { return theme.brightness == .dark ? Color(0xFFE3EAF7) : Color(0xFF2B3850) }
        return theme.brightness == .dark ? Color(0xFFB0BED6) : Color(0xFF596981)
    }

    /// `display` is the system's text size, contrast and bold settings (see SystemDisplay); the chrome's text
    /// follows them, up to what its fixed rows can hold.
    static func theme(_ brightness: Brightness, display: DisplaySettings = SystemDisplay.current) -> FluentThemeData {
        let dark = brightness == .dark
        var ink = dark ? Color(0xFFF1F5FF) : Color(0xFF1B2943)
        if display.increasedContrast { ink = dark ? white : Color(0xFF000000) }
        let k = display.chromeTextScale
        let w: FontWeight = display.boldText ? .w700 : .w400
        return FluentThemeData(
            brightness: brightness,
            typography: Typography(
                bodyStrong: Flutter.TextStyle(color: ink, fontSize: 13 * k, fontWeight: display.boldText ? .w800 : .w600),
                body: Flutter.TextStyle(color: ink, fontSize: 13 * k, fontWeight: w),
                caption: Flutter.TextStyle(color: ink, fontSize: 11 * k, fontWeight: w)),
            accentColor: accent,
            scaffoldBackgroundColor: dark ? Color(0xFF202B40) : white,
            menuColor: dark ? Color(0xFF202B40) : white,
            selectionColor: dark ? Color(0xFF344E83) : Color(0xFFDCE7FF))
    }
}
