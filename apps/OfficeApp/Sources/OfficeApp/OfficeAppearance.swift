// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
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

    static func border(_ theme: FluentThemeData) -> Color {
        theme.brightness == .dark ? Color(0xFF364359) : Color(0xFFDDE4EF)
    }

    static func ink(_ theme: FluentThemeData) -> Color {
        theme.brightness == .dark ? Color(0xFFF1F5FF) : Color(0xFF1B2943)
    }

    static func secondary(_ theme: FluentThemeData) -> Color {
        theme.brightness == .dark ? Color(0xFFB0BED6) : Color(0xFF596981)
    }

    static func theme(_ brightness: Brightness) -> FluentThemeData {
        let dark = brightness == .dark
        let ink = dark ? Color(0xFFF1F5FF) : Color(0xFF1B2943)
        return FluentThemeData(
            brightness: brightness,
            typography: Typography(
                bodyStrong: Flutter.TextStyle(color: ink, fontSize: 13, fontWeight: .w600),
                body: Flutter.TextStyle(color: ink, fontSize: 13),
                caption: Flutter.TextStyle(color: ink, fontSize: 11)),
            accentColor: accent,
            scaffoldBackgroundColor: dark ? Color(0xFF202B40) : white,
            menuColor: dark ? Color(0xFF202B40) : white,
            selectionColor: dark ? Color(0xFF344E83) : Color(0xFFDCE7FF))
    }
}
