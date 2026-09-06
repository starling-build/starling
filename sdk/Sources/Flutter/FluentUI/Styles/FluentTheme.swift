// Fluent UI theme ported from fluent_ui/lib/src/styles/theme.dart

import FlutterSwiftBridge

// MARK: - standardCurve

/// The default animation curve used throughout the Fluent Design System.
nonisolated(unsafe) public let standardCurve: any Curve = Curves.easeInOut

// MARK: - FluentThemeData

/// Defines the configuration for a Fluent Design theme.
///
/// Contains all the colors, typography, and component theme data used to style
/// Fluent UI widgets.
public struct FluentThemeData: Equatable {
    /// The text styles for this theme.
    public let typography: Typography

    /// The primary accent color used throughout the application.
    public let accentColor: AccentColor

    /// The color used for active/selected foreground elements.
    public let activeColor: Color

    /// The color used for inactive/unselected foreground elements.
    public let inactiveColor: Color

    /// The background color for inactive/disabled elements.
    public let inactiveBackgroundColor: Color

    /// The color used for shadows and elevation effects.
    public let shadowColor: Color

    /// The background color for scaffold pages.
    public let scaffoldBackgroundColor: Color

    /// The default background color for acrylic widgets.
    public let acrylicBackgroundColor: Color

    /// The default background color for mica widgets.
    public let micaBackgroundColor: Color

    /// The background color for menus and flyouts.
    public let menuColor: Color

    /// The background color for card widgets.
    public let cardColor: Color

    /// The color used for text selection highlights.
    public let selectionColor: Color

    /// The duration for the fastest animations (83ms).
    public let fasterAnimationDuration: Duration

    /// The duration for fast animations (167ms).
    public let fastAnimationDuration: Duration

    /// The duration for medium animations (250ms).
    public let mediumAnimationDuration: Duration

    /// The duration for slow animations (358ms).
    public let slowAnimationDuration: Duration

    /// The default curve for animations.
    public let animationCurve: any Curve

    /// The overall brightness of this theme.
    public let brightness: Brightness

    /// Theme data for icons.
    public let iconTheme: IconThemeData

    /// The system-level color resources.
    public let resources: ResourceDictionary

    // MARK: - Equatable

    public static func == (lhs: FluentThemeData, rhs: FluentThemeData) -> Bool {
        lhs.brightness == rhs.brightness
            && lhs.accentColor === rhs.accentColor
            && lhs.activeColor == rhs.activeColor
            && lhs.inactiveColor == rhs.inactiveColor
            && lhs.inactiveBackgroundColor == rhs.inactiveBackgroundColor
            && lhs.shadowColor == rhs.shadowColor
            && lhs.scaffoldBackgroundColor == rhs.scaffoldBackgroundColor
            && lhs.acrylicBackgroundColor == rhs.acrylicBackgroundColor
            && lhs.micaBackgroundColor == rhs.micaBackgroundColor
            && lhs.menuColor == rhs.menuColor
            && lhs.cardColor == rhs.cardColor
            && lhs.selectionColor == rhs.selectionColor
            && lhs.typography == rhs.typography
            && lhs.iconTheme == rhs.iconTheme
            && lhs.resources == rhs.resources
    }

    // MARK: - Factory

    /// Creates a new FluentThemeData with sensible defaults.
    public init(
        brightness: Brightness? = nil,
        typography: Typography? = nil,
        fontFamily: String? = nil,
        accentColor: AccentColor? = nil,
        activeColor: Color? = nil,
        inactiveColor: Color? = nil,
        inactiveBackgroundColor: Color? = nil,
        scaffoldBackgroundColor: Color? = nil,
        acrylicBackgroundColor: Color? = nil,
        micaBackgroundColor: Color? = nil,
        shadowColor: Color? = nil,
        menuColor: Color? = nil,
        cardColor: Color? = nil,
        selectionColor: Color? = nil,
        fasterAnimationDuration: Duration? = nil,
        fastAnimationDuration: Duration? = nil,
        mediumAnimationDuration: Duration? = nil,
        slowAnimationDuration: Duration? = nil,
        animationCurve: (any Curve)? = nil,
        iconTheme: IconThemeData? = nil,
        resources: ResourceDictionary? = nil
    ) {
        let resolvedBrightness = brightness ?? .light
        let isLight = resolvedBrightness == .light

        let resolvedResources = resources ?? (isLight
            ? ResourceDictionary.light()
            : ResourceDictionary.dark())
        // Windows' own default accent with Windows' own shades, so a theme
        // that says nothing about its accent looks like a Windows 11 machine
        // that says nothing about its accent.
        let resolvedAccentColor = accentColor ?? FluentColors.windowsBlue
        let resolvedFasterDuration = fasterAnimationDuration ?? .milliseconds(83)
        let resolvedFastDuration = fastAnimationDuration ?? .milliseconds(167)
        let resolvedMediumDuration = mediumAnimationDuration ?? .milliseconds(250)
        let resolvedSlowDuration = slowAnimationDuration ?? .milliseconds(358)
        let resolvedAnimationCurve = animationCurve ?? standardCurve

        var resolvedTypography = Typography.fromBrightness(
            brightness: resolvedBrightness,
            color: resolvedResources.textFillColorPrimary
        ).merge(typography).apply(fontFamily: fontFamily)

        self.brightness = resolvedBrightness
        self.resources = resolvedResources
        self.accentColor = resolvedAccentColor
        self.activeColor = activeColor ?? FluentColors.white
        self.inactiveColor = inactiveColor ?? (isLight ? FluentColors.black : FluentColors.white)
        self.inactiveBackgroundColor = inactiveBackgroundColor ?? (isLight
            ? Color(0xFFd6d6d6)
            : Color(0xFF292929))
        self.shadowColor = shadowColor ?? (isLight ? FluentColors.black : FluentColors.grey[130])
        // A page background has to be OPAQUE. The acrylic layer colours are
        // 0x40ffffff (light) and 0x09ffffff (dark) — 25% and 3.5% white, meant
        // to be composited over something already there. Painting one as the
        // page background composites it over whatever the host cleared to,
        // which in a plain windowed app is black: a light theme then renders
        // as dark grey. `solidBackgroundFillColorTertiary` (#f9f9f9 / #282828)
        // is the opaque page fill, and what fluent_ui uses here.
        self.scaffoldBackgroundColor = scaffoldBackgroundColor
            ?? resolvedResources.solidBackgroundFillColorTertiary
        self.acrylicBackgroundColor = acrylicBackgroundColor ?? (isLight
            ? resolvedResources.layerOnAcrylicFillColorDefault
            : Color(0xFF2c2c2c))
        self.micaBackgroundColor = micaBackgroundColor ?? resolvedResources.solidBackgroundFillColorBase
        self.menuColor = menuColor ?? (isLight ? Color(0xFFf9f9f9) : Color(0xFF2c2c2c))
        self.cardColor = cardColor ?? resolvedResources.cardBackgroundFillColorDefault
        self.selectionColor = selectionColor ?? resolvedAccentColor.normal
        self.fasterAnimationDuration = resolvedFasterDuration
        self.fastAnimationDuration = resolvedFastDuration
        self.mediumAnimationDuration = resolvedMediumDuration
        self.slowAnimationDuration = resolvedSlowDuration
        self.animationCurve = resolvedAnimationCurve
        self.typography = resolvedTypography
        self.iconTheme = iconTheme ?? (isLight
            ? IconThemeData(size: 18, color: FluentColors.black)
            : IconThemeData(size: 18, color: FluentColors.white))
    }

    // MARK: - Raw Init

    /// Creates a FluentThemeData with all values specified directly (no defaults).
    public init(
        brightness: Brightness,
        typography: Typography,
        accentColor: AccentColor,
        activeColor: Color,
        inactiveColor: Color,
        inactiveBackgroundColor: Color,
        shadowColor: Color,
        scaffoldBackgroundColor: Color,
        acrylicBackgroundColor: Color,
        micaBackgroundColor: Color,
        menuColor: Color,
        cardColor: Color,
        selectionColor: Color,
        fasterAnimationDuration: Duration,
        fastAnimationDuration: Duration,
        mediumAnimationDuration: Duration,
        slowAnimationDuration: Duration,
        animationCurve: any Curve,
        iconTheme: IconThemeData,
        resources: ResourceDictionary
    ) {
        self.brightness = brightness
        self.typography = typography
        self.accentColor = accentColor
        self.activeColor = activeColor
        self.inactiveColor = inactiveColor
        self.inactiveBackgroundColor = inactiveBackgroundColor
        self.shadowColor = shadowColor
        self.scaffoldBackgroundColor = scaffoldBackgroundColor
        self.acrylicBackgroundColor = acrylicBackgroundColor
        self.micaBackgroundColor = micaBackgroundColor
        self.menuColor = menuColor
        self.cardColor = cardColor
        self.selectionColor = selectionColor
        self.fasterAnimationDuration = fasterAnimationDuration
        self.fastAnimationDuration = fastAnimationDuration
        self.mediumAnimationDuration = mediumAnimationDuration
        self.slowAnimationDuration = slowAnimationDuration
        self.animationCurve = animationCurve
        self.iconTheme = iconTheme
        self.resources = resources
    }

    // MARK: - Convenience Factories

    /// Creates a default light theme.
    public static func light() -> FluentThemeData {
        FluentThemeData(brightness: .light)
    }

    /// Creates a default dark theme.
    public static func dark() -> FluentThemeData {
        FluentThemeData(brightness: .dark)
    }

    // MARK: - copyWith

    /// Creates a copy of this theme data with the given fields replaced.
    public func copyWith(
        brightness: Brightness? = nil,
        typography: Typography? = nil,
        accentColor: AccentColor? = nil,
        activeColor: Color? = nil,
        inactiveColor: Color? = nil,
        inactiveBackgroundColor: Color? = nil,
        scaffoldBackgroundColor: Color? = nil,
        acrylicBackgroundColor: Color? = nil,
        micaBackgroundColor: Color? = nil,
        shadowColor: Color? = nil,
        menuColor: Color? = nil,
        cardColor: Color? = nil,
        selectionColor: Color? = nil,
        fasterAnimationDuration: Duration? = nil,
        fastAnimationDuration: Duration? = nil,
        mediumAnimationDuration: Duration? = nil,
        slowAnimationDuration: Duration? = nil,
        animationCurve: (any Curve)? = nil,
        iconTheme: IconThemeData? = nil,
        resources: ResourceDictionary? = nil
    ) -> FluentThemeData {
        FluentThemeData(
            brightness: brightness ?? self.brightness,
            typography: self.typography.merge(typography),
            accentColor: accentColor ?? self.accentColor,
            activeColor: activeColor ?? self.activeColor,
            inactiveColor: inactiveColor ?? self.inactiveColor,
            inactiveBackgroundColor: inactiveBackgroundColor ?? self.inactiveBackgroundColor,
            shadowColor: shadowColor ?? self.shadowColor,
            scaffoldBackgroundColor: scaffoldBackgroundColor ?? self.scaffoldBackgroundColor,
            acrylicBackgroundColor: acrylicBackgroundColor ?? self.acrylicBackgroundColor,
            micaBackgroundColor: micaBackgroundColor ?? self.micaBackgroundColor,
            menuColor: menuColor ?? self.menuColor,
            cardColor: cardColor ?? self.cardColor,
            selectionColor: selectionColor ?? self.selectionColor,
            fasterAnimationDuration: fasterAnimationDuration ?? self.fasterAnimationDuration,
            fastAnimationDuration: fastAnimationDuration ?? self.fastAnimationDuration,
            mediumAnimationDuration: mediumAnimationDuration ?? self.mediumAnimationDuration,
            slowAnimationDuration: slowAnimationDuration ?? self.slowAnimationDuration,
            animationCurve: animationCurve ?? self.animationCurve,
            iconTheme: iconTheme ?? self.iconTheme,
            resources: resources ?? self.resources
        )
    }

    // MARK: - lerp

    /// Linearly interpolates between two FluentThemeData objects.
    public static func lerp(_ a: FluentThemeData, _ b: FluentThemeData, _ t: Double) -> FluentThemeData {
        FluentThemeData(
            brightness: t < 0.5 ? a.brightness : b.brightness,
            typography: Typography.lerp(a.typography, b.typography, t),
            accentColor: AccentColor.lerp(a.accentColor, b.accentColor, t),
            activeColor: Color.lerp(a.activeColor, b.activeColor, t)!,
            inactiveColor: Color.lerp(a.inactiveColor, b.inactiveColor, t)!,
            inactiveBackgroundColor: Color.lerp(a.inactiveBackgroundColor, b.inactiveBackgroundColor, t)!,
            shadowColor: Color.lerp(a.shadowColor, b.shadowColor, t)!,
            scaffoldBackgroundColor: Color.lerp(a.scaffoldBackgroundColor, b.scaffoldBackgroundColor, t)!,
            acrylicBackgroundColor: Color.lerp(a.acrylicBackgroundColor, b.acrylicBackgroundColor, t)!,
            micaBackgroundColor: Color.lerp(a.micaBackgroundColor, b.micaBackgroundColor, t)!,
            menuColor: Color.lerp(a.menuColor, b.menuColor, t)!,
            cardColor: Color.lerp(a.cardColor, b.cardColor, t)!,
            selectionColor: Color.lerp(a.selectionColor, b.selectionColor, t)!,
            fasterAnimationDuration: lerpDuration(a.fasterAnimationDuration, b.fasterAnimationDuration, t),
            fastAnimationDuration: lerpDuration(a.fastAnimationDuration, b.fastAnimationDuration, t),
            mediumAnimationDuration: lerpDuration(a.mediumAnimationDuration, b.mediumAnimationDuration, t),
            slowAnimationDuration: lerpDuration(a.slowAnimationDuration, b.slowAnimationDuration, t),
            animationCurve: t < 0.5 ? a.animationCurve : b.animationCurve,
            iconTheme: IconThemeData.lerp(a.iconTheme, b.iconTheme, t),
            resources: ResourceDictionary.lerp(a.resources, b.resources, t)
        )
    }
}

// MARK: - FluentTheme (Widget)

/// Applies a Fluent Design theme to descendant widgets.
///
/// Use `FluentTheme.of(context)` to access the nearest `FluentThemeData`.
public class FluentTheme: StatelessWidget {
    /// The theme data to apply to descendants.
    public let data: FluentThemeData

    /// The widget below this widget in the tree.
    public let child: Widget

    /// Creates a FluentTheme that applies the given theme data to its child.
    public init(key: (any Key)? = nil, data: FluentThemeData, child: Widget) {
        self.data = data
        self.child = child
        super.init(key: key)
    }

    /// Returns the FluentThemeData from the closest FluentTheme ancestor.
    ///
    /// Throws if there is no ancestor. Use `maybeOf` if the theme might not exist.
    public static func of(_ context: any BuildContext) -> FluentThemeData {
        let inherited = context.dependOnInheritedWidgetOfExactType(_FluentThemeInherited.self)
        return inherited!.data
    }

    /// Returns the FluentThemeData from the closest FluentTheme ancestor,
    /// or nil if there is no ancestor.
    public static func maybeOf(_ context: any BuildContext) -> FluentThemeData? {
        let inherited = context.dependOnInheritedWidgetOfExactType(_FluentThemeInherited.self)
        return inherited?.data
    }

    public override func build(_ context: any BuildContext) -> Widget {
        return _FluentThemeInherited(
            data: data,
            child: IconTheme(
                data: data.iconTheme,
                child: DefaultTextStyle(style: data.typography.body!, child: child)
            )
        )
    }
}

// MARK: - _FluentThemeInherited

/// The InheritedWidget that carries the FluentThemeData down the tree.
internal class _FluentThemeInherited: InheritedTheme {
    let data: FluentThemeData

    init(key: (any Key)? = nil, data: FluentThemeData, child: Widget) {
        self.data = data
        super.init(key: key, child: child)
    }

    override func updateShouldNotify(_ oldWidget: InheritedWidget) -> Bool {
        guard let old = oldWidget as? _FluentThemeInherited else { return true }
        return old.data != data
    }

    override func wrap(_ context: any BuildContext, _ child: Widget) -> Widget {
        return _FluentThemeInherited(data: data, child: child)
    }
}
