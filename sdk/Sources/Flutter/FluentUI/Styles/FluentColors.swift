// Fluent UI color definitions ported from fluent_ui/lib/src/styles/color.dart

import FlutterSwiftBridge

// MARK: - ShadedColor

/// A color with numbered shade variants (e.g. 10-220).
///
/// Access shades using subscript: `FluentColors.grey[120]`.
public struct ShadedColor: Sendable {
    /// The primary color value.
    public let primary: Color

    /// The swatch mapping shade numbers to colors.
    public let swatch: [Int: Color]

    /// Creates a shaded color with the given primary value and swatch.
    public init(_ primary: Int, _ swatch: [Int: Color]) {
        self.primary = Color(primary)
        self.swatch = swatch
    }

    /// Returns the shade at the given key.
    public subscript(key: Int) -> Color {
        swatch[key]!
    }
}

// MARK: - AccentColor

/// A color with named shade variants: darkest, darker, dark, normal, light, lighter, lightest.
public class AccentColor {
    /// The available shades for this color.
    public let swatch: [String: Color]

    /// The primary shade key.
    public let primary: String

    /// Creates a new accent color from a swatch with "normal" as the default.
    public init(swatch: [String: Color]) {
        self.primary = "normal"
        self.swatch = swatch
    }

    /// Creates a new accent color from a swatch (convenience factory matching Dart).
    public static func swatch(_ swatch: [String: Color]) -> AccentColor {
        AccentColor(swatch: swatch)
    }

    /// The normal (default) shade.
    public var normal: Color { swatch["normal"]! }

    /// The darkest shade.
    public var darkest: Color {
        swatch["darkest"] ?? darker.withValues(alpha: 0.7)
    }

    /// The darker shade.
    public var darker: Color {
        swatch["darker"] ?? dark.withValues(alpha: 0.8)
    }

    /// The dark shade.
    public var dark: Color {
        swatch["dark"] ?? normal.withValues(alpha: 0.9)
    }

    /// The light shade.
    public var light: Color {
        swatch["light"] ?? normal.withValues(alpha: 0.9)
    }

    /// The lighter shade.
    public var lighter: Color {
        swatch["lighter"] ?? light.withValues(alpha: 0.8)
    }

    /// The lightest shade.
    public var lightest: Color {
        swatch["lightest"] ?? lighter.withValues(alpha: 0.7)
    }

    /// Get the default brush for this accent color based on brightness.
    public func defaultBrushFor(_ brightness: Brightness) -> Color {
        switch brightness {
        case .light: return dark
        case .dark: return lighter
        }
    }

    /// Get the secondary brush for this accent color based on brightness.
    public func secondaryBrushFor(_ brightness: Brightness) -> Color {
        defaultBrushFor(brightness).withValues(alpha: 0.9)
    }

    /// Get the tertiary brush for this accent color based on brightness.
    public func tertiaryBrushFor(_ brightness: Brightness) -> Color {
        defaultBrushFor(brightness).withValues(alpha: 0.8)
    }

    /// Linearly interpolate between two accent colors.
    public static func lerp(_ a: AccentColor, _ b: AccentColor, _ t: Double) -> AccentColor {
        return AccentColor.swatch([
            "darkest": Color.lerp(a.darkest, b.darkest, t)!,
            "darker": Color.lerp(a.darker, b.darker, t)!,
            "dark": Color.lerp(a.dark, b.dark, t)!,
            "normal": Color.lerp(a.normal, b.normal, t)!,
            "light": Color.lerp(a.light, b.light, t)!,
            "lighter": Color.lerp(a.lighter, b.lighter, t)!,
            "lightest": Color.lerp(a.lightest, b.lightest, t)!,
        ])
    }
}

// MARK: - FluentColors

/// The Fluent Design color palette.
public enum FluentColors {
    /// The transparent color.
    public static let transparent = Color(0x00000000)

    /// A black opaque color.
    public static let black = Color(0xFF000000)

    /// A white opaque color.
    public static let white = Color(0xFFFFFFFF)

    /// The grey shaded color with 21 shades (10-220).
    public static let grey = ShadedColor(
        0xFF323130,
        [
            220: Color(0xFF11100F),
            210: Color(0xFF161514),
            200: Color(0xFF1B1A19),
            190: Color(0xFF201F1E),
            180: Color(0xFF252423),
            170: Color(0xFF292827),
            160: Color(0xFF323130),
            150: Color(0xFF3B3A39),
            140: Color(0xFF484644),
            130: Color(0xFF605E5C),
            120: Color(0xFF797775),
            110: Color(0xFF8A8886),
            100: Color(0xFF979593),
            90: Color(0xFFA19F9D),
            80: Color(0xFFB3B0AD),
            70: Color(0xFFBEBBB8),
            60: Color(0xFFC8C6C4),
            50: Color(0xFFD2D0CE),
            40: Color(0xFFE1DFDD),
            30: Color(0xFFEDEBE9),
            20: Color(0xFFF3F2F1),
            10: Color(0xFFFAF9F8),
        ]
    )

    // MARK: - Accent Colors

    /// The yellow accent color.
    nonisolated(unsafe) public static let yellow = AccentColor.swatch([
        "darkest": Color(0xFFF9A825),
        "darker": Color(0xFFFBC02D),
        "dark": Color(0xFFFDD835),
        "normal": Color(0xFFFFEB3B),
        "light": Color(0xFFFFEE58),
        "lighter": Color(0xFFFFF176),
        "lightest": Color(0xFFFFF59D),
    ])

    /// The orange accent color.
    nonisolated(unsafe) public static let orange = AccentColor.swatch([
        "darkest": Color(0xFF993D07),
        "darker": Color(0xFFAC4508),
        "dark": Color(0xFFD1540A),
        "normal": Color(0xFFF7630C),
        "light": Color(0xFFF87A30),
        "lighter": Color(0xFFF99154),
        "lightest": Color(0xFFFA9E68),
    ])

    /// The red accent color.
    nonisolated(unsafe) public static let red = AccentColor.swatch([
        "darkest": Color(0xFF8F0A15),
        "darker": Color(0xFFA20B18),
        "dark": Color(0xFFB90D1C),
        "normal": Color(0xFFE81123),
        "light": Color(0xFFEC404F),
        "lighter": Color(0xFFEE5865),
        "lightest": Color(0xFFF06B76),
    ])

    /// The magenta accent color.
    nonisolated(unsafe) public static let magenta = AccentColor.swatch([
        "darkest": Color(0xFF6F0061),
        "darker": Color(0xFF7E006E),
        "dark": Color(0xFF90007E),
        "normal": Color(0xFFB4009E),
        "light": Color(0xFFC333B1),
        "lighter": Color(0xFFCA4CBB),
        "lightest": Color(0xFFD060C2),
    ])

    /// The purple accent color.
    nonisolated(unsafe) public static let purple = AccentColor.swatch([
        "darkest": Color(0xFF472F68),
        "darker": Color(0xFF513576),
        "dark": Color(0xFF644293),
        "normal": Color(0xFF744DA9),
        "light": Color(0xFF8664B4),
        "lighter": Color(0xFF9D82C2),
        "lightest": Color(0xFFA890C9),
    ])

    /// The blue accent color.
    nonisolated(unsafe) public static let blue = AccentColor.swatch([
        "darkest": Color(0xFF004A83),
        "darker": Color(0xFF005494),
        "dark": Color(0xFF0066B4),
        "normal": Color(0xFF0078D4),
        "light": Color(0xFF268CDA),
        "lighter": Color(0xFF4CA0E0),
        "lightest": Color(0xFF60ABE4),
    ])

    /// The teal accent color.
    nonisolated(unsafe) public static let teal = AccentColor.swatch([
        "darkest": Color(0xFF006E5B),
        "darker": Color(0xFF007C67),
        "dark": Color(0xFF00977D),
        "normal": Color(0xFF00B294),
        "light": Color(0xFF26BDA4),
        "lighter": Color(0xFF4CC9B4),
        "lightest": Color(0xFF60CFBC),
    ])

    /// The green accent color.
    nonisolated(unsafe) public static let green = AccentColor.swatch([
        "darkest": Color(0xFF094C09),
        "darker": Color(0xFF0C5D0C),
        "dark": Color(0xFF0E6F0E),
        "normal": Color(0xFF107C10),
        "light": Color(0xFF278927),
        "lighter": Color(0xFF4B9C4B),
        "lightest": Color(0xFF6AAD6A),
    ])

    // MARK: - Status Colors

    /// The primary color for warning.
    public static let warningPrimaryColor = Color(0xFFD83B01)

    /// The secondary color for warning.
    nonisolated(unsafe) public static let warningSecondaryColor = AccentColor.swatch([
        "dark": Color(0xFF433519),
        "normal": Color(0xFFFFF4CE),
    ])

    /// The primary color for error.
    public static let errorPrimaryColor = Color(0xFFA80000)

    /// The secondary color for error.
    nonisolated(unsafe) public static let errorSecondaryColor = AccentColor.swatch([
        "dark": Color(0xFF442726),
        "normal": Color(0xFFFDE7E9),
    ])

    /// The primary color for success.
    public static let successPrimaryColor = Color(0xFF107C10)

    /// The secondary color for success.
    nonisolated(unsafe) public static let successSecondaryColor = AccentColor.swatch([
        "dark": Color(0xFF393D1B),
        "normal": Color(0xFFDFF6DD),
    ])

    /// A list of all the accent colors provided by this library.
    nonisolated(unsafe) public static let accentColors: [AccentColor] = [
        yellow, orange, red, magenta, purple, blue, teal, green,
    ]
}

// MARK: - Color Extension

extension Color {
    /// Creates a new accent color based on this color.
    ///
    /// Shades are generated by lerping this color with black (for dark shades)
    /// and white (for light shades).
    public func toAccentColor(
        darkestFactor: Double = 0.38,
        darkerFactor: Double = 0.30,
        darkFactor: Double = 0.15,
        lightFactor: Double = 0.15,
        lighterFactor: Double = 0.30,
        lightestFactor: Double = 0.38
    ) -> AccentColor {
        return AccentColor.swatch([
            "darkest": Color.lerp(self, FluentColors.black, darkestFactor)!,
            "darker": Color.lerp(self, FluentColors.black, darkerFactor)!,
            "dark": Color.lerp(self, FluentColors.black, darkFactor)!,
            "normal": self,
            "light": Color.lerp(self, FluentColors.white, lightFactor)!,
            "lighter": Color.lerp(self, FluentColors.white, lighterFactor)!,
            "lightest": Color.lerp(self, FluentColors.white, lightestFactor)!,
        ])
    }

    /// Returns a contrasting color based on the luminance of this color.
    ///
    /// If luminance < 0.5, returns `lightColor` (default: white).
    /// If luminance >= 0.5, returns `darkColor` (default: black).
    public func basedOnLuminance(
        darkColor: Color = FluentColors.black,
        lightColor: Color = FluentColors.white
    ) -> Color {
        return computeLuminance() < 0.5 ? lightColor : darkColor
    }
}

// MARK: - Windows accent shades

// Windows names an accent's shades Light 3..1 and Dark 1..3 around the base,
// and WinUI picks from them by theme: `AccentFillColorDefaultBrush` is
// **Dark 1** in the light theme and **Light 2** in the dark theme
// (Common_themeresources_any.xaml). fluent_ui's swatch keys are the same
// seven positions under other names, so the mapping is a rename, and
// `defaultBrushFor` already returns `dark` for light and `lighter` for dark
// — exactly those two.
extension AccentColor {
    /// `SystemAccentColorDark3`.
    public var dark3: Color { darkest }
    /// `SystemAccentColorDark2`.
    public var dark2: Color { darker }
    /// `SystemAccentColorDark1` — the accent of controls in the light theme.
    public var dark1: Color { dark }
    /// `SystemAccentColorLight1`.
    public var light1: Color { light }
    /// `SystemAccentColorLight2` — the accent of controls in the dark theme.
    public var light2: Color { lighter }
    /// `SystemAccentColorLight3`.
    public var light3: Color { lightest }

    /// An accent from the seven shades Windows exposes for it
    /// (`UISettings.GetColorValue`), in Windows' order.
    public static func windows(
        light3: Color, light2: Color, light1: Color, normal: Color,
        dark1: Color, dark2: Color, dark3: Color
    ) -> AccentColor {
        AccentColor.swatch([
            "lightest": light3,
            "lighter": light2,
            "light": light1,
            "normal": normal,
            "dark": dark1,
            "darker": dark2,
            "darkest": dark3,
        ])
    }
}

extension FluentColors {
    /// Windows 11's default accent, "Default blue" (#0078D4), with the exact
    /// shades Windows derives for it. Light-theme controls come out
    /// #0067C0 and dark-theme ones #4CC2FF, which is what a Windows 11
    /// machine measures on its own toggles and Start tiles.
    nonisolated(unsafe) public static let windowsBlue = AccentColor.windows(
        light3: Color(0xFF99EBFF),
        light2: Color(0xFF4CC2FF),
        light1: Color(0xFF0091F8),
        normal: Color(0xFF0078D4),
        dark1: Color(0xFF0067C0),
        dark2: Color(0xFF003E92),
        dark3: Color(0xFF001A68)
    )
}
