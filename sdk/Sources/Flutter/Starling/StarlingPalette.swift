// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The colours a Starling app paints itself in, for whichever desktop style is
// active.
//
// The shell has had switchable styles for a while; the apps had not, and the
// seam showed -- a Windows caption over a macOS-blue app body. Each app had
// grown its own hand-written palette (`FinderColors`, Settings' `Palette`,
// and a few hundred loose `Color(0x...)` literals besides), all of them the
// same SHAPE and none of them shared, so making the apps follow the desktop
// meant either ten parallel edits or one definition. This is the one.
//
// WHERE THE VALUES COME FROM
//
//   macOS   the values the apps already shipped. They were tuned against real
//           macOS and there is no reason to re-derive them; this file is just
//           where they live now.
//   Fluent  WinUI's own resource dictionary (FluentUI/Styles/ColorResources),
//           the same source the shell's Fluent chrome reads. Nothing here is
//           picked by eye.
//
// WHICH ONE IS ACTIVE is the shell's business: it pushes the style down the
// DMA-BUF socket at connect and on every switch, and `GpuDmaBufRenderer`
// latches it. An app that has not been told yet gets macOS, which is the
// desktop's default and the safe answer.

import FlutterSwiftBridge

// MARK: - StarlingStyleId

/// The desktop styles, as the shell indexes them. Deliberately an opaque
/// small integer over the wire -- the shell owns the list, and an app built
/// before a style existed must degrade to the default rather than fail.
public enum StarlingStyleId: Int {
    case macos = 0
    case fluent = 1

    /// What the shell last pushed, or macOS if it has not said.
    public static var current: StarlingStyleId {
        #if os(Linux)
        guard let raw = GpuDmaBufRenderer.lastPushedStyle,
              let s = StarlingStyleId(rawValue: raw) else { return .macos }
        return s
        #else
        return .macos
        #endif
    }
}

// MARK: - StarlingPalette

/// One app-side palette, in semantic roles rather than colours.
///
/// The roles are the union of what the apps already asked for, so adopting it
/// is a rename rather than a redesign. Anything an app needs that is genuinely
/// its own -- a folder blue, a syntax colour -- stays in the app.
public struct StarlingPalette {
    // Text.
    public let textPrimary: Color
    public let textSecondary: Color
    public let textTertiary: Color
    public let textDisabled: Color

    // Surfaces. `canvas` is the window's body, `sidebar` the quieter panel
    // beside it, `surface` a raised card or list on top of either.
    public let canvas: Color
    public let sidebar: Color
    public let surface: Color

    // Lines: the 1px rule between things, and the alternating row wash.
    public let hairline: Color
    public let stripe: Color

    // Controls.
    public let fieldFill: Color
    public let fieldBorder: Color
    public let hover: Color
    public let selection: Color

    /// The accent, and what reads ON it -- which is not always white. Fluent's
    /// dark accent is a light blue and takes black text.
    public let accent: Color
    public let accentInk: Color

    /// The face, or nil for the platform default. macOS has no opinion here;
    /// the Fluent style ships Selawik, Segoe UI's metric-compatible stand-in.
    public let fontFamily: String?
    public let fontFamilyStrong: String?

    public let isDark: Bool

    // MARK: The two palettes

    /// The active style's palette for the given appearance.
    public static func current(dark: Bool) -> StarlingPalette {
        switch StarlingStyleId.current {
        case .macos:  return macos(dark: dark)
        case .fluent: return fluent(dark: dark)
        }
    }

    /// What the apps already shipped, unchanged -- these were tuned against
    /// real macOS and this is only where they now live.
    public static func macos(dark: Bool) -> StarlingPalette {
        StarlingPalette(
            textPrimary:   dark ? Color(0xFFFFFFFF) : Color(0xD9000000),
            textSecondary: dark ? Color(0xC7FFFFFF) : Color(0x8C000000),
            textTertiary:  dark ? Color(0x99FFFFFF) : Color(0x66000000),
            textDisabled:  dark ? Color(0x3AFFFFFF) : Color(0x33000000),
            canvas:        dark ? Color(0xC221252C) : Color(0xCCF4F4F6),
            sidebar:       dark ? Color(0x7A1D2129) : Color(0xA6ECECEF),
            surface:       dark ? Color(0x14FFFFFF) : Color(0x0A000000),
            hairline:      dark ? Color(0x14FFFFFF) : Color(0x1A000000),
            stripe:        dark ? Color(0x08FFFFFF) : Color(0x08000000),
            fieldFill:     dark ? Color(0x1FFFFFFF) : Color(0xFFFFFFFF),
            fieldBorder:   dark ? Color(0x26FFFFFF) : Color(0x26000000),
            hover:         dark ? Color(0x14FFFFFF) : Color(0x0A000000),
            selection:     dark ? Color(0xFF0A84FF) : Color(0xFF007AFF),
            accent:        dark ? Color(0xFF0A84FF) : Color(0xFF007AFF),
            accentInk:     Color(0xFFFFFFFF),
            fontFamily: nil,
            fontFamilyStrong: nil,
            isDark: dark)
    }

    /// WinUI's, by name. Every value below is a token from the resource
    /// dictionary rather than a colour chosen here; the comment on each line
    /// is the role Microsoft gives it.
    public static func fluent(dark: Bool) -> StarlingPalette {
        let theme = dark ? FluentThemeData.dark() : FluentThemeData.light()
        let r = theme.resources
        return StarlingPalette(
            textPrimary:   r.textFillColorPrimary,
            textSecondary: r.textFillColorSecondary,
            textTertiary:  r.textFillColorTertiary,
            textDisabled:  r.textFillColorDisabled,
            // The window body is the chrome grey (#F3F3F3 / #202020) and the
            // list or card on top of it is a shade lifted, which is the way
            // round Explorer has it.
            canvas:        r.solidBackgroundFillColorBase,
            sidebar:       r.solidBackgroundFillColorSecondary,
            surface:       r.solidBackgroundFillColorTertiary,
            hairline:      r.dividerStrokeColorDefault,
            stripe:        r.subtleFillColorSecondary,
            fieldFill:     r.controlFillColorDefault,
            fieldBorder:   r.controlStrokeColorDefault,
            hover:         r.subtleFillColorSecondary,
            selection:     theme.selectionColor,
            accent:        theme.accentColor.normal,
            // The token that exists precisely because white-on-accent is
            // wrong in dark mode.
            accentInk:     r.textOnAccentFillColorPrimary,
            fontFamily: SelawikFontName.regular,
            fontFamilyStrong: SelawikFontName.semibold,
            isDark: dark)
    }

    // MARK: Handing it to the widgets

    /// A `MacosThemeData` carrying these colours.
    ///
    /// The apps stay rooted in `MacosApp` whichever style is active, because
    /// `FluentApp`'s scaffold traps on mount as a DMA-BUF child. That is a
    /// smaller compromise than it sounds: the Macos* controls take their
    /// colours from this theme, so pointing it at WinUI's values gets the
    /// buttons, fields and scrollbars into the right palette without swapping
    /// the widget family underneath a working app.
    public func macosTheme() -> MacosThemeData {
        let base = isDark ? MacosThemeData.dark() : MacosThemeData.light()
        return MacosThemeData(
            brightness: isDark ? .dark : .light,
            primaryColor: accent,
            canvasColor: canvas,
            typography: base.typography,
            dividerColor: hairline,
            pushButtonTheme: base.pushButtonTheme,
            iconButtonTheme: base.iconButtonTheme,
            iconTheme: base.iconTheme,
            accentColor: base.accentColor,
            isMainWindow: base.isMainWindow
        )
    }
}

/// Selawik's family names, without dragging the icon-font target in: the
/// palette only needs to NAME the face, and the app that draws with it has
/// already registered it.
public enum SelawikFontName {
    public static let regular = "Selawik"
    public static let semibold = "Selawik Semibold"
}
