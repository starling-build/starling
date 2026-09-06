// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Mica and Smoke: the two Windows 11 materials that are NOT a blur.
//
// Mica is the backdrop of a long-lived window: opaque, and leaned toward the
// colour of the desktop wallpaper so a window looks related to the desktop
// it is on instead of being flat grey. Windows samples the wallpaper once,
// blurs it beyond recognition and blends its tint over that, and never
// touches it again — which is why Mica costs nothing per frame, and why one
// colour sample is a faithful stand-in for the whole wallpaper: after that
// much blur there is nothing left of it but its average.
//
// So `Mica` takes a SAMPLE — a colour — and computes its surface from it
// with the material's own arithmetic (`FluentMaterialRecipe.resolve`). Where
// the sample comes from is the host's business: a desktop puts the
// wallpaper's average colour in a `MicaBackdrop` above every app; an app
// running on a plain window has none and gets the documented fallback,
// which is also what Windows shows when the window is inactive, transparency
// is off, or the battery saver is on.
//
// Smoke is the dim under a modal dialog: translucent black in both themes.

import FlutterSwiftBridge

// MARK: - MicaKind

public enum MicaKind: Sendable {
    /// The base material: window backgrounds.
    case base
    /// Stronger tint, for a tabbed title bar or a commanding strip that needs
    /// to stand apart from plain Mica beside it.
    case alt
}

// MARK: - MicaBackdrop

/// What lies behind the window, for `Mica` to lean toward: one colour, the
/// wallpaper's average. Put it above an app's root; every `Mica` below reads
/// it. nil, or absent, means "no wallpaper known".
public class MicaBackdrop: InheritedWidget {
    public let sample: Color?

    public init(key: (any Key)? = nil, sample: Color?, child: Widget) {
        self.sample = sample
        super.init(key: key, child: child)
    }

    /// The sample in force at `context`, or nil.
    public static func of(_ context: any BuildContext) -> Color? {
        context.dependOnInheritedWidgetOfExactType(MicaBackdrop.self)?.sample
    }

    public override func updateShouldNotify(_ oldWidget: InheritedWidget) -> Bool {
        guard let old = oldWidget as? MicaBackdrop else { return true }
        return old.sample != sample
    }
}

// MARK: - Mica

/// An opaque surface of Mica behind `child`.
///
/// ```swift
/// MicaBackdrop(sample: wallpaperAverage) {
///     Mica { pageContent }
/// }
/// ```
public class Mica: StatelessWidget {
    public let child: Widget?
    public let kind: MicaKind

    /// Whether the window this surface belongs to is active. Windows drops
    /// Mica to its fallback colour on an inactive window so the focused one
    /// stands out; pass the window's state here.
    public let active: Bool

    /// A sample to use instead of the enclosing `MicaBackdrop`'s.
    public let sample: Color?

    public init(
        key: (any Key)? = nil,
        child: Widget? = nil,
        kind: MicaKind = .base,
        active: Bool = true,
        sample: Color? = nil
    ) {
        self.child = child
        self.kind = kind
        self.active = active
        self.sample = sample
        super.init(key: key)
    }

    /// The colour a Mica surface of `kind` resolves to, given what it knows.
    /// The widget uses this; so can anything that paints Mica without a
    /// widget tree — a window frame, a title bar.
    public static func color(
        kind: MicaKind,
        brightness: Brightness,
        sample: Color?,
        active: Bool = true,
        transparencyEffects: Bool = true
    ) -> Color {
        let recipe = kind == .base
            ? FluentMaterialRecipe.mica(brightness)
            : FluentMaterialRecipe.micaAlt(brightness)
        guard active, transparencyEffects else { return recipe.fallbackColor }
        return recipe.resolve(over: sample)
    }

    public override func build(_ context: any BuildContext) -> Widget {
        let theme = FluentTheme.of(context)
        let settings = FluentMaterialSettings.of(context)
        let fill = Mica.color(
            kind: kind,
            brightness: theme.brightness,
            sample: sample ?? MicaBackdrop.of(context),
            active: active,
            transparencyEffects: settings.transparencyEffects)
        return ColoredBox(color: fill, child: child)
    }
}

// MARK: - Smoke

/// The dim under a modal surface: `SmokeFillColorDefault`, translucent black
/// whatever the theme. Fills whatever it is given; put the dialog on top.
public class Smoke: StatelessWidget {
    public let child: Widget?

    public init(key: (any Key)? = nil, child: Widget? = nil) {
        self.child = child
        super.init(key: key)
    }

    /// The colour itself, for callers that paint their own barrier.
    public static func color(_ context: any BuildContext) -> Color {
        FluentTheme.maybeOf(context)?.resources.smokeFillColorDefault
            ?? ResourceDictionary.light().smokeFillColorDefault
    }

    public override func build(_ context: any BuildContext) -> Widget {
        ColoredBox(color: Smoke.color(context), child: child ?? SizedBox(expand: ()))
    }
}
