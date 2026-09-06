// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Acrylic: Windows' translucent material for transient surfaces — flyouts,
// menus, Start, anything light-dismiss. Frosted glass, tinted.
//
// This is the real recipe, not a tinted rectangle: the backdrop is blurred,
// the tint's LIGHTNESS is blended onto it (a luminosity blend, which is what
// keeps a dark acrylic dark over a white window and a light one light over
// a dark wallpaper), then the tint itself is painted over at its own opacity.
// The ingredients are `FluentMaterialRecipe` (Styles/FluentMaterials.swift),
// verbatim from WinUI's brush resources; this file only composes them.
//
// Two things Windows does that this does not: the 2% noise texture (not
// visible at UI scale, and a texture asset the framework would have to ship),
// and going solid when the window deactivates (a window's business, not a
// surface's — see `FluentMaterialSettings` for the switch a host can throw).
//
// The blur is a `BackdropFilter`, and a 30-sigma blur is not free: this is
// for surfaces that come and go, as the guidance says, not for a window's
// body. `Mica` is the material for that.

import FlutterSwiftBridge

// MARK: - Acrylic

/// A surface of acrylic material behind `child`.
///
/// ```swift
/// Acrylic(borderRadius: FluentCorners.overlayRadius) {
///     Padding(padding: EdgeInsets(all: 8), child: menuItems)
/// }
/// ```
///
/// The recipe defaults to the thin `acrylicDefault` of the current theme;
/// pass `recipe:` for `acrylicBase` (denser, for Start-sized panels) or an
/// accent acrylic, and any of the four ingredient overrides to tune one.
public class Acrylic: StatelessWidget {

    /// The widget below this widget in the tree.
    public let child: Widget?

    /// The material. nil picks the theme's default acrylic, or the one an
    /// enclosing `AcrylicTheme` chose.
    public let recipe: FluentMaterialRecipe?

    /// Overrides for single ingredients of whichever recipe applies.
    public let tintColor: Color?
    public let tintOpacity: Double?
    public let luminosityOpacity: Double?
    public let blurAmount: Double?

    /// The surface's corners. The blur is clipped to them.
    public let borderRadius: any BorderRadiusGeometry

    /// Draw the material, or its fallback colour. nil follows
    /// `FluentMaterialSettings`.
    public let enabled: Bool?

    public init(
        key: (any Key)? = nil,
        child: Widget? = nil,
        recipe: FluentMaterialRecipe? = nil,
        tintColor: Color? = nil,
        tintOpacity: Double? = nil,
        luminosityOpacity: Double? = nil,
        blurAmount: Double? = nil,
        borderRadius: any BorderRadiusGeometry = BorderRadius.zero,
        enabled: Bool? = nil
    ) {
        self.child = child
        self.recipe = recipe
        self.tintColor = tintColor
        self.tintOpacity = tintOpacity
        self.luminosityOpacity = luminosityOpacity
        self.blurAmount = blurAmount
        self.borderRadius = borderRadius
        self.enabled = enabled
        super.init(key: key)
    }

    /// The recipe this widget will draw with at `context`, overrides applied.
    public func resolvedRecipe(_ context: any BuildContext) -> FluentMaterialRecipe {
        let theme = FluentTheme.of(context)
        let base = recipe
            ?? AcrylicTheme.of(context).recipe
            ?? FluentMaterialRecipe.acrylicDefault(theme.brightness)
        return base.copyWith(
            tintColor: tintColor,
            tintOpacity: tintOpacity,
            luminosityOpacity: luminosityOpacity,
            blurAmount: blurAmount)
    }

    public override func build(_ context: any BuildContext) -> Widget {
        let r = resolvedRecipe(context)
        let live = enabled ?? FluentMaterialSettings.of(context).transparencyEffects
        let content = child ?? SizedBox(width: 0, height: 0)

        guard live, r.blurAmount > 0 || r.luminosityOpacity > 0 || r.tintOpacity > 0 else {
            return DecoratedBox(
                decoration: BoxDecoration(color: r.fallbackColor, borderRadius: borderRadius),
                child: content)
        }

        // Bottom to top: the blurred backdrop with the luminosity layer
        // blended onto it, the tint over that, and the child. `Positioned`
        // fills size the layers to the child rather than the other way
        // round, so an acrylic panel is as big as what it holds.
        var layers: [Widget] = []
        let luminosity: Widget = DecoratedBox(
            decoration: BoxDecoration(
                color: r.tintColor.withValues(alpha: r.luminosityOpacity),
                backgroundBlendMode: .luminosity),
            child: SizedBox(expand: ()))
        if r.blurAmount > 0 {
            layers.append(Positioned(fill: (), child: BackdropFilter(
                filter: ImageFilterFactory.blur(sigmaX: r.blurAmount, sigmaY: r.blurAmount),
                child: luminosity)))
        } else {
            layers.append(Positioned(fill: (), child: luminosity))
        }
        if r.tintOpacity > 0 {
            layers.append(Positioned(fill: (), child: DecoratedBox(
                decoration: BoxDecoration(color: r.tintColor.withValues(alpha: r.tintOpacity)),
                child: SizedBox(expand: ()))))
        }
        layers.append(content)

        return ClipRRect(borderRadius: borderRadius, child: Stack(children: layers))
    }
}

// MARK: - AcrylicThemeData

/// Theme data for the default appearance of `Acrylic` widgets below an
/// `AcrylicTheme`: a whole recipe, and/or single ingredients over it.
public class AcrylicThemeData {
    public let recipe: FluentMaterialRecipe?
    public let tintColor: Color?
    public let tintOpacity: Double?
    public let luminosityOpacity: Double?
    public let blurAmount: Double?

    public init(
        recipe: FluentMaterialRecipe? = nil,
        tintColor: Color? = nil,
        tintOpacity: Double? = nil,
        luminosityOpacity: Double? = nil,
        blurAmount: Double? = nil
    ) {
        self.recipe = recipe
        self.tintColor = tintColor
        self.tintOpacity = tintOpacity
        self.luminosityOpacity = luminosityOpacity
        self.blurAmount = blurAmount
    }

    /// The standard theme data: nothing overridden, so `Acrylic` falls
    /// through to the theme's own default acrylic.
    public static func standard(_ theme: FluentThemeData) -> AcrylicThemeData {
        AcrylicThemeData()
    }

    /// Merge this theme data with another, the other taking precedence.
    public func merge(_ other: AcrylicThemeData?) -> AcrylicThemeData {
        guard let other else { return self }
        return AcrylicThemeData(
            recipe: other.recipe ?? recipe,
            tintColor: other.tintColor ?? tintColor,
            tintOpacity: other.tintOpacity ?? tintOpacity,
            luminosityOpacity: other.luminosityOpacity ?? luminosityOpacity,
            blurAmount: other.blurAmount ?? blurAmount
        )
    }
}

// MARK: - AcrylicTheme

/// An inherited theme that controls how descendant `Acrylic` widgets look.
public class AcrylicTheme: InheritedTheme {
    public let data: AcrylicThemeData

    public init(key: (any Key)? = nil, data: AcrylicThemeData, child: Widget) {
        self.data = data
        super.init(key: key, child: child)
    }

    /// The closest `AcrylicThemeData` enclosing `context`, with the
    /// ingredient overrides already folded into `recipe` when one was set.
    public static func of(_ context: any BuildContext) -> AcrylicThemeData {
        let theme = FluentTheme.of(context)
        let inherited = context.dependOnInheritedWidgetOfExactType(AcrylicTheme.self)
        let merged = AcrylicThemeData.standard(theme).merge(inherited?.data)
        guard merged.tintColor != nil || merged.tintOpacity != nil
            || merged.luminosityOpacity != nil || merged.blurAmount != nil else {
            return merged
        }
        let base = merged.recipe ?? FluentMaterialRecipe.acrylicDefault(theme.brightness)
        return AcrylicThemeData(recipe: base.copyWith(
            tintColor: merged.tintColor,
            tintOpacity: merged.tintOpacity,
            luminosityOpacity: merged.luminosityOpacity,
            blurAmount: merged.blurAmount))
    }

    public override func updateShouldNotify(_ oldWidget: InheritedWidget) -> Bool {
        guard let old = oldWidget as? AcrylicTheme else { return true }
        return data !== old.data
    }

    public override func wrap(_ context: any BuildContext, _ child: Widget) -> Widget {
        return AcrylicTheme(data: data, child: child)
    }
}
