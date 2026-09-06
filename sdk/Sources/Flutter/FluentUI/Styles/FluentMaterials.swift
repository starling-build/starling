// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Windows 11's materials, as recipes rather than as widgets: what Acrylic,
// Mica and Smoke are MADE of, taken from where Microsoft defines them, so the
// widgets in Controls/Surfaces are thin and the numbers are in one place.
//
//   Acrylic   WinUI's AcrylicBrush_themeresources.xaml — every brush is a
//             TintColor, a TintOpacity, a TintLuminosityOpacity and a
//             FallbackColor, and Windows composes them over a 30-DIP
//             Gaussian blur of whatever is behind the surface.
//   Mica      the MicaController defaults (Microsoft.UI.Composition.
//             SystemBackdrops): the same four ingredients minus the blur,
//             applied to the desktop WALLPAPER, sampled once. The documented
//             fallback is SolidBackgroundFillColorBase, and BaseAlt for Mica
//             Alt.
//   Smoke     one colour, SmokeFillColorDefault, the same in both themes.
//
// The composition itself is Windows' own: a LUMINOSITY blend of the tint
// over the backdrop (which keeps the backdrop's hue and saturation and
// replaces its lightness with the tint's — this is what makes a dark acrylic
// dark whatever is behind it), then the tint painted over that at its own
// opacity, then 2% noise. `resolve(over:)` does the same arithmetic on a
// single colour, which is how an opaque Mica can be computed from one
// wallpaper sample at no per-frame cost, and how a caller can know what an
// acrylic will look like over a given backdrop without rendering it.
//
// Nothing here is a widget. `Acrylic`, `Mica` and `Smoke` in
// Controls/Surfaces are the widgets, and they read these.

import FlutterSwiftBridge

// MARK: - FluentMaterialRecipe

/// The ingredients of one material, in Windows' own terms.
public struct FluentMaterialRecipe: Equatable, Sendable {
    /// The colour blended over the backdrop.
    public let tintColor: Color

    /// How much of `tintColor` is painted straight over the backdrop
    /// (`TintOpacity`). 0 means the tint reaches the eye only through the
    /// luminosity layer.
    public let tintOpacity: Double

    /// How strongly the tint's LIGHTNESS replaces the backdrop's
    /// (`TintLuminosityOpacity`). 1.0 means the result has exactly the
    /// tint's lightness and only the backdrop's hue.
    public let luminosityOpacity: Double

    /// What the surface is when the material cannot be drawn: transparency
    /// effects off, battery saver, an inactive window, no backdrop.
    public let fallbackColor: Color

    /// The Gaussian blur under an acrylic, as a standard deviation in
    /// logical pixels. 0 for Mica, which blurs nothing at draw time.
    public let blurAmount: Double

    public init(
        tintColor: Color,
        tintOpacity: Double,
        luminosityOpacity: Double,
        fallbackColor: Color,
        blurAmount: Double
    ) {
        self.tintColor = tintColor
        self.tintOpacity = tintOpacity
        self.luminosityOpacity = luminosityOpacity
        self.fallbackColor = fallbackColor
        self.blurAmount = blurAmount
    }

    /// The same recipe with some ingredients replaced.
    public func copyWith(
        tintColor: Color? = nil,
        tintOpacity: Double? = nil,
        luminosityOpacity: Double? = nil,
        fallbackColor: Color? = nil,
        blurAmount: Double? = nil
    ) -> FluentMaterialRecipe {
        FluentMaterialRecipe(
            tintColor: tintColor ?? self.tintColor,
            tintOpacity: tintOpacity ?? self.tintOpacity,
            luminosityOpacity: luminosityOpacity ?? self.luminosityOpacity,
            fallbackColor: fallbackColor ?? self.fallbackColor,
            blurAmount: blurAmount ?? self.blurAmount
        )
    }

    /// The blur Windows applies under every acrylic.
    public static let acrylicBlurAmount: Double = 30

    // MARK: Acrylic (AcrylicBrush_themeresources.xaml)

    /// `AcrylicBackgroundFillColorDefaultBrush`: the thin acrylic under
    /// flyouts, menus and other light-dismiss surfaces.
    public static func acrylicDefault(_ brightness: Brightness) -> FluentMaterialRecipe {
        switch brightness {
        case .light:
            return FluentMaterialRecipe(
                tintColor: Color(0xFFFCFCFC), tintOpacity: 0.0,
                luminosityOpacity: 0.85, fallbackColor: Color(0xFFF9F9F9),
                blurAmount: acrylicBlurAmount)
        case .dark:
            return FluentMaterialRecipe(
                tintColor: Color(0xFF2C2C2C), tintOpacity: 0.15,
                luminosityOpacity: 0.96, fallbackColor: Color(0xFF2C2C2C),
                blurAmount: acrylicBlurAmount)
        }
    }

    /// `AcrylicBackgroundFillColorBaseBrush`: the denser acrylic for larger
    /// transient surfaces — Start, the notification centre.
    public static func acrylicBase(_ brightness: Brightness) -> FluentMaterialRecipe {
        switch brightness {
        case .light:
            return FluentMaterialRecipe(
                tintColor: Color(0xFFF3F3F3), tintOpacity: 0.0,
                luminosityOpacity: 0.9, fallbackColor: Color(0xFFEEEEEE),
                blurAmount: acrylicBlurAmount)
        case .dark:
            return FluentMaterialRecipe(
                tintColor: Color(0xFF202020), tintOpacity: 0.5,
                luminosityOpacity: 0.96, fallbackColor: Color(0xFF1C1C1C),
                blurAmount: acrylicBlurAmount)
        }
    }

    /// `AccentAcrylicBackgroundFillColorDefaultBrush`: acrylic in the accent
    /// colour. Light uses the accent's Light 3, dark its Dark 1.
    public static func accentAcrylic(_ brightness: Brightness, accent: AccentColor) -> FluentMaterialRecipe {
        switch brightness {
        case .light:
            return FluentMaterialRecipe(
                tintColor: accent.light3, tintOpacity: 0.8,
                luminosityOpacity: 0.9, fallbackColor: accent.light3,
                blurAmount: acrylicBlurAmount)
        case .dark:
            return FluentMaterialRecipe(
                tintColor: accent.dark1, tintOpacity: 0.8,
                luminosityOpacity: 0.8, fallbackColor: accent.dark1,
                blurAmount: acrylicBlurAmount)
        }
    }

    // MARK: Mica (MicaController defaults)

    /// Mica: the material behind a long-lived window. Opaque, and leaned
    /// toward the wallpaper.
    public static func mica(_ brightness: Brightness) -> FluentMaterialRecipe {
        switch brightness {
        case .light:
            return FluentMaterialRecipe(
                tintColor: Color(0xFFF3F3F3), tintOpacity: 0.5,
                luminosityOpacity: 1.0, fallbackColor: Color(0xFFF3F3F3),
                blurAmount: 0)
        case .dark:
            return FluentMaterialRecipe(
                tintColor: Color(0xFF202020), tintOpacity: 0.8,
                luminosityOpacity: 1.0, fallbackColor: Color(0xFF202020),
                blurAmount: 0)
        }
    }

    /// Mica Alt: a stronger lean toward the wallpaper, for tabbed title bars
    /// and anything that needs contrast against plain Mica beside it.
    public static func micaAlt(_ brightness: Brightness) -> FluentMaterialRecipe {
        switch brightness {
        case .light:
            return FluentMaterialRecipe(
                tintColor: Color(0xFFDADADA), tintOpacity: 0.5,
                luminosityOpacity: 1.0, fallbackColor: Color(0xFFDADADA),
                blurAmount: 0)
        case .dark:
            return FluentMaterialRecipe(
                tintColor: Color(0xFF0A0A0A), tintOpacity: 0.0,
                luminosityOpacity: 1.0, fallbackColor: Color(0xFF0A0A0A),
                blurAmount: 0)
        }
    }

    // MARK: Resolving to one colour

    /// What this material looks like over a backdrop of one uniform colour,
    /// as an opaque colour. nil (no backdrop to sample) is the fallback.
    ///
    /// This is the material's own arithmetic — luminosity blend, then tint —
    /// applied to a single sample instead of to every pixel, which is exactly
    /// right for Mica (Windows samples the wallpaper once and never again)
    /// and a faithful preview for acrylic over a flat colour.
    public func resolve(over sample: Color?) -> Color {
        guard let sample else { return fallbackColor }
        let backdrop = sample.withValues(alpha: 1.0)
        // Luminosity layer: the tint's lightness on the backdrop's hue, at
        // `luminosityOpacity` strength.
        let lum = FluentColorMath.luminosityBlend(source: tintColor, backdrop: backdrop)
        let lumLayer = FluentColorMath.mix(backdrop, lum, luminosityOpacity)
        // Tint layer: the tint itself, straight over, at `tintOpacity`.
        return FluentColorMath.over(tintColor.withValues(alpha: tintOpacity), lumLayer)
    }
}

// MARK: - FluentColorMath

/// The colour arithmetic the materials are built from. W3C compositing
/// formulas, on the 0–1 components `Color` already carries.
public enum FluentColorMath {
    /// Relative luminance as the blend-mode spec defines it for the
    /// non-separable modes: 0.3 R + 0.59 G + 0.11 B.
    public static func luminosity(_ c: Color) -> Double {
        0.3 * c.r + 0.59 * c.g + 0.11 * c.b
    }

    /// `c` with its luminosity set to `l`, clipped back into gamut the way
    /// the spec's ClipColor does — so hue and saturation survive.
    public static func setLuminosity(_ c: Color, _ l: Double) -> Color {
        let d = l - luminosity(c)
        var r = c.r + d, g = c.g + d, b = c.b + d
        let lum = 0.3 * r + 0.59 * g + 0.11 * b
        let n = min(r, g, b)
        let x = max(r, g, b)
        if n < 0 {
            let k = lum / (lum - n)
            r = lum + (r - lum) * k
            g = lum + (g - lum) * k
            b = lum + (b - lum) * k
        }
        if x > 1 {
            let k = (1 - lum) / (x - lum)
            r = lum + (r - lum) * k
            g = lum + (g - lum) * k
            b = lum + (b - lum) * k
        }
        return Color(alpha: c.a, red: clamp(r), green: clamp(g), blue: clamp(b),
                     colorSpace: c.colorSpace)
    }

    /// The LUMINOSITY blend mode: the backdrop's hue and saturation with the
    /// source's luminosity. Both are treated as opaque; the caller applies
    /// the source's alpha with `mix`.
    public static func luminosityBlend(source: Color, backdrop: Color) -> Color {
        setLuminosity(backdrop.withValues(alpha: 1.0), luminosity(source))
    }

    /// Straight interpolation from `a` to `b` by `t`, opaque.
    public static func mix(_ a: Color, _ b: Color, _ t: Double) -> Color {
        let t = clamp(t)
        return Color(
            alpha: 1.0,
            red: a.r + (b.r - a.r) * t,
            green: a.g + (b.g - a.g) * t,
            blue: a.b + (b.b - a.b) * t,
            colorSpace: a.colorSpace)
    }

    /// `foreground` painted over an opaque `background` (source-over).
    public static func over(_ foreground: Color, _ background: Color) -> Color {
        mix(background.withValues(alpha: 1.0), foreground.withValues(alpha: 1.0), foreground.a)
    }

    private static func clamp(_ v: Double) -> Double { min(1, max(0, v)) }
}

// MARK: - FluentMaterialSettings

/// The system switches a material honours: Windows' "Transparency effects"
/// (Settings › Personalization › Colors) and "Animation effects"
/// (Accessibility › Visual effects). Off, every acrylic and Mica draws its
/// fallback colour and motion collapses to its end state.
///
/// An inherited widget rather than a theme field so an app can flip it for
/// one subtree — a screenshot preview, a battery-saver mode — and so a
/// desktop can inject the user's setting above every app without the app
/// knowing where it came from. Absent, everything is on.
public class FluentMaterialSettings: InheritedWidget {
    public let transparencyEffects: Bool
    public let animationEffects: Bool

    public init(
        key: (any Key)? = nil,
        transparencyEffects: Bool = true,
        animationEffects: Bool = true,
        child: Widget
    ) {
        self.transparencyEffects = transparencyEffects
        self.animationEffects = animationEffects
        super.init(key: key, child: child)
    }

    /// The settings in force at `context`; all on when nothing set any.
    public static func of(_ context: any BuildContext) -> (transparencyEffects: Bool, animationEffects: Bool) {
        guard let s = context.dependOnInheritedWidgetOfExactType(FluentMaterialSettings.self) else {
            return (true, true)
        }
        return (s.transparencyEffects, s.animationEffects)
    }

    public override func updateShouldNotify(_ oldWidget: InheritedWidget) -> Bool {
        guard let old = oldWidget as? FluentMaterialSettings else { return true }
        return old.transparencyEffects != transparencyEffects
            || old.animationEffects != animationEffects
    }
}
