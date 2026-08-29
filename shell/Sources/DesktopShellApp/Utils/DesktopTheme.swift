// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge

// MARK: - Desktop Theme Constants

/// Shared constants for the Desktop Shell PoC layout and colors.
enum DesktopTheme {

    // MARK: Layout

    static let kMinWindowWidth: Double = 300.0
    static let kMinWindowHeight: Double = 200.0
    static let kDefaultWindowWidth: Double = 600.0
    static let kDefaultWindowHeight: Double = 400.0

    // MARK: Layout that the ACTIVE STYLE decides
    //
    // These five were constants until the desktop grew a second style. They
    // forward to `shellMetrics` now, so every existing reader picks up the
    // style's numbers without knowing there is a style. The `kDock*` names
    // are the macOS-era spellings of "the bottom bar" — a taskbar answers to
    // them too. See ShellStyle.swift.

    static var kTitleBarHeight: Double { shellMetrics.titleBarHeight }
    static var kWindowCornerRadius: Double { shellMetrics.windowCornerRadius }
    /// The strip along the top. 0 in a style that has no top bar.
    static var kStatusBarHeight: Double { shellMetrics.topInset }
    static var kDockHeight: Double { shellMetrics.bottomBarHeight }
    static var kDockBottomMargin: Double { shellMetrics.bottomBarMargin }
    static var kDockContainerHeight: Double { shellMetrics.bottomBarContainerHeight }

    // macOS-style dock (bottom, centered) — geometry only that style draws.
    static let kDockIconSize: Double = 56.0
    static let kDockIconPadding: Double = 6.0
    static let kDockIconCornerRadius: Double = 12.0
    static let kDockCornerRadius: Double = 32.0
    static let kDockHorizontalPadding: Double = 14.0

    // macOS-style hover magnification. Icons swell with a cosine falloff
    // centered on the cursor; the row grows upward from a fixed baseline.
    static let kDockMagnifyMaxScale: Double = 1.5
    static let kDockMagnifyRadius: Double = 150.0  // falloff reach, px from cursor
    /// Gap between an icon's bottom edge and the pill's bottom edge; the
    /// running-indicator dot lives in this strip (as on macOS).
    static let kDockIconBottomInset: Double = 10.0
    static let kDockIndicatorSize: Double = 4.0
    /// Baseline (bottom offset) of the hovered app-name label bubble:
    /// icon inset + max magnified icon + gap.
    static let kDockLabelBottom: Double = kDockIconBottomInset
        + kDockIconSize * kDockMagnifyMaxScale + 8.0

    // Floating Google-style search pill at the top of the desktop
    static let kSearchPillWidth: Double = 520.0
    static let kSearchPillHeight: Double = 48.0
    static let kSearchPillTopMargin: Double = 96.0
    static let kSearchPillLeftMargin: Double = 56.0

    // MARK: Colors

    /// Semi-transparent dark background for the taskbar.
    static let taskbarBackground = Color(0xE61C1C1C)

    /// Title bar color when the window is focused (translucent glass).
    static let titleBarActive = Color(0xD0303030)

    /// Title bar color when the window is not focused (translucent glass, dimmer).
    static let titleBarInactive = Color(0xB0383838)

    /// Accent color used for focused-window indicators and highlights.
    static let accent = Color(0xFF0A84FF)

    /// Soft-white dock tint — translucent so the wallpaper shows through
    /// (approximates frosted glass since DRM/GLES backend can't blur).
    static let dockBackground = Color(0x60FFFFFF)

    /// Subtle hairline border for the dock.
    static let dockBorder = Color(0x20000000)

    /// Floating search pill background (dark translucent).
    static let searchPillBackground = Color(0xCC1F1F1F)

    /// Search pill border / hairline outline.
    static let searchPillBorder = Color(0x30FFFFFF)

    /// Gaussian blur sigma for the macOS-style frosted backdrop (currently unused).
    static let kDockBlurSigma: Double = 24.0
}

// MARK: - ShellMaterial

/// What a translucent chrome surface is made of. The two desktops disagree
/// in kind here, not in degree: macOS's glass boosts the saturation of what
/// it blurs so the wallpaper reads through vivid, and Windows' acrylic pulls
/// colour out so the tint dominates. It is one of the clearest tells of which
/// desktop you are looking at, and the reason a Fluent palette painted onto
/// glass still reads as macOS.
enum ShellMaterial {
    case glass
    case acrylic
}

// MARK: - ShellTheme

/// The switchable look of the desktop chrome. Every shell-drawn color
/// routes through the active theme's semantic tokens; layout metrics stay
/// in DesktopTheme.
///
/// Deliberately NOT themed: traffic lights (red/yellow/green are the
/// brand), wallpaper presets, dock app-icon brand colors, the fullscreen
/// reserved strip (always black), and the frame-tick pixel.
struct ShellTheme {
    /// Menu label ("Dark" / "Light").
    let name: String
    let isDark: Bool

    // Foreground on chrome surfaces (menu bar, popups, dock labels).
    let fgPrimary: Color
    let fgSecondary: Color
    let fgTertiary: Color

    // Menu bar (top status bar) — tint over the blur, hairline below.
    let barTint: Color
    let barHairline: Color
    /// Hover/pressed fill behind bar items and popup action rows.
    let hoverFill: Color

    // Status-bar popup panels (over the liquid-glass refraction).
    let popupTint: Color
    let popupInnerBorder: Color
    let popupDivider: Color
    let popupShadow: Color

    // Dock: glass pill gradient + rim, running dots, hover name bubble.
    let dockGradientTop: Color
    let dockGradientBottom: Color
    let dockRim: Color
    let dockShadow: Color
    let dockIndicator: Color
    let dockIndicatorRim: Color
    let dockLabelTint: Color
    let dockLabelBorder: Color
    let dockLabelText: Color

    // Window chrome.
    /// Tint over the frosted backdrop the shell draws under every window
    /// (the liquid-glass layer apps show through translucent backgrounds).
    let windowGlassTint: Color
    let titleBarActive: Color
    let titleBarInactive: Color
    let titleTextActive: Color
    let titleTextInactive: Color
    let windowBorderFocused: Color
    let windowBorderUnfocused: Color
    let trafficLightInactive: Color

    // Full-screen overlays (app launcher, Mission Control). The scrim
    // darkens the wallpaper in BOTH themes (macOS keeps overview labels
    // white on the dimmed wallpaper even in light mode).
    let overlayScrim: Color
    let overlayText: Color
    let overlayTextDim: Color

    let accent: Color

    // MARK: Tokens the Fluent chrome adds
    //
    // The macOS chrome never reads these. They live on the shared struct
    // anyway so that switching style is a value swap and not a type change —
    // one `shellTheme` global, one set of call sites, whatever is active.
    // The names are the ROLE each colour plays, not Windows' own names.

    /// Fill of a bar that sits ON the screen edge and is opaque, as opposed
    /// to the translucent tint a floating bar gets over its blur.
    let barFill: Color
    /// The wash a hovered bar tile or menu row takes.
    let barHover: Color
    /// The line under a running app's tile, and the same line for the window
    /// that currently has focus.
    let runningIndicator: Color
    let runningIndicatorActive: Color
    /// Caption buttons. Close is separate because it alone goes red, and its
    /// glyph turns white on that red in BOTH appearances.
    let captionHover: Color
    let captionCloseHover: Color
    let captionCloseInk: Color
    /// Flyout and menu bodies — Start, Quick Settings, context menus.
    let panelFill: Color
    let panelStroke: Color
    /// Controls sitting on those panels: tiles, buttons, fields.
    let controlFill: Color
    let controlStroke: Color
    let controlHover: Color
    /// Foreground ON the accent. Not reliably white: Fluent's dark-mode
    /// accent is a LIGHT blue and takes black glyphs. This is the one token
    /// where light and dark disagree in kind rather than in degree.
    let accentInk: Color
    /// The unfilled part of a slider track.
    let trackRest: Color

    /// The face the chrome sets its text in, and the heavier cut for the few
    /// things that are emphasised. nil means the engine's default, which is
    /// what the macOS style wants.
    ///
    /// Typeface is most of what a desktop's "feel" is — the same layout in
    /// the wrong face still reads as the wrong desktop — which is why the
    /// Fluent style ships Selawik, Segoe UI's metric-compatible stand-in,
    /// rather than borrowing whatever the system happens to default to.
    let fontFamily: String?
    let fontFamilyStrong: String?

    /// Glass or acrylic — see `ShellMaterial`.
    let material: ShellMaterial

    /// The shipped dark look.
    static let macosDark = ShellTheme(
        name: "Dark",
        isDark: true,
        fgPrimary: Color(0xFFFFFFFF),
        fgSecondary: Color(0xFFCCCCCC),
        fgTertiary: Color(0xFF8E8E93),
        barTint: Color(0x2E101014),
        barHairline: Color(0x14FFFFFF),
        hoverFill: Color(0x40FFFFFF),
        popupTint: Color(0x59202020),
        popupInnerBorder: Color(0x40FFFFFF),
        popupDivider: Color(0x30FFFFFF),
        popupShadow: Color(0x60000000),
        dockGradientTop: Color(0x12FFFFFF),
        dockGradientBottom: Color(0x05FFFFFF),
        dockRim: Color(0x59FFFFFF),
        dockShadow: Color(0x40000000),
        dockIndicator: Color(0xF2FFFFFF),
        dockIndicatorRim: Color(0x59000000),
        dockLabelTint: Color(0xD9262626),
        dockLabelBorder: Color(0x30FFFFFF),
        dockLabelText: Color(0xFFF2F2F2),
        windowGlassTint: Color(0x3D262A32),
        // Translucent enough that the window frost reads through the bar.
        titleBarActive: Color(0xA62E323A),
        titleBarInactive: Color(0x8C34383F),
        titleTextActive: Color(0xFFFFFFFF),
        titleTextInactive: Color(0x80FFFFFF),
        windowBorderFocused: Color(0x40FFFFFF),
        windowBorderUnfocused: Color(0x20FFFFFF),
        trafficLightInactive: Color(0x40FFFFFF),
        overlayScrim: Color(0xA80E0E12),
        overlayText: Color(0xE6FFFFFF),
        overlayTextDim: Color(0x99FFFFFF),
        // iOS-family dark system blue — the same accent family the light
        // theme and the in-app controls (toggles, sliders) use, so the
        // whole desktop highlights with one blue.
        accent: Color(0xFF0A84FF),
        barFill: Color(0xFF1C1C1E),
        barHover: Color(0x14FFFFFF),
        runningIndicator: Color(0x99FFFFFF),
        runningIndicatorActive: Color(0xFF0A84FF),
        captionHover: Color(0x1AFFFFFF),
        captionCloseHover: Color(0xFFC42B1C),
        captionCloseInk: Color(0xFFFFFFFF),
        panelFill: Color(0xF22C2C2E),
        panelStroke: Color(0x26FFFFFF),
        controlFill: Color(0xFF3A3A3C),
        controlStroke: Color(0x1FFFFFFF),
        controlHover: Color(0xFF48484A),
        accentInk: Color(0xFFFFFFFF),
        trackRest: Color(0x4DFFFFFF),
        fontFamily: nil,
        fontFamilyStrong: nil,
        material: .glass
    )

    /// macOS-style light appearance (Big Sur+): crisp near-opaque white
    /// frost chrome so panels read as white over any wallpaper, solid
    /// light title bars, dark-gray dock dots.
    static let macosLight = ShellTheme(
        name: "Light",
        isDark: false,
        fgPrimary: Color(0xD9000000),
        fgSecondary: Color(0x8C000000),
        fgTertiary: Color(0x59000000),
        // Menu bar: strong white frost (macOS light bar is nearly solid
        // white with just a hint of wallpaper through the blur).
        barTint: Color(0xCCF6F6F6),
        barHairline: Color(0x21000000),
        hoverFill: Color(0x1F000000),
        // Popovers: near-opaque white like NSPopover in light mode.
        popupTint: Color(0xD9F4F4F6),
        popupInnerBorder: Color(0xB3FFFFFF),
        popupDivider: Color(0x1A000000),
        popupShadow: Color(0x40000000),
        // Dock: solid-feeling white frost pill.
        dockGradientTop: Color(0xB3FCFCFC),
        dockGradientBottom: Color(0x8CF2F2F4),
        dockRim: Color(0xBFFFFFFF),
        dockShadow: Color(0x30000000),
        dockIndicator: Color(0xE6474747),
        dockIndicatorRim: Color(0x40FFFFFF),
        dockLabelTint: Color(0xF2F6F6F6),
        dockLabelBorder: Color(0x1F000000),
        dockLabelText: Color(0xE6262626),
        windowGlassTint: Color(0x59F2F2F5),
        // Near-opaque in light mode (macOS keeps light bars solid), with a
        // hint of the frost through them.
        titleBarActive: Color(0xE6EDEDEF),
        titleBarInactive: Color(0xE6F7F7F8),
        titleTextActive: Color(0xD9000000),
        titleTextInactive: Color(0x59000000),
        windowBorderFocused: Color(0x30000000),
        windowBorderUnfocused: Color(0x1F000000),
        trafficLightInactive: Color(0x33000000),
        overlayScrim: Color(0x800E0E12),
        overlayText: Color(0xE6FFFFFF),
        overlayTextDim: Color(0x99FFFFFF),
        // Deeper blue than the dark theme's — the pale cyan washes out on
        // light frost panels.
        accent: Color(0xFF007AFF),
        barFill: Color(0xFFF6F6F6),
        barHover: Color(0x14000000),
        runningIndicator: Color(0x99000000),
        runningIndicatorActive: Color(0xFF007AFF),
        captionHover: Color(0x14000000),
        captionCloseHover: Color(0xFFC42B1C),
        captionCloseInk: Color(0xFFFFFFFF),
        panelFill: Color(0xF2F4F4F6),
        panelStroke: Color(0x1A000000),
        controlFill: Color(0xFFFBFBFB),
        controlStroke: Color(0x1F000000),
        controlHover: Color(0xFFF0F0F0),
        accentInk: Color(0xFFFFFFFF),
        trackRest: Color(0x59000000),
        fontFamily: nil,
        fontFamilyStrong: nil,
        material: .glass
    )
}

/// The active theme — the ACTIVE STYLE's dark or light half. Main-thread only
/// (same discipline as _shellState); switch via the shell's setState so every
/// tree rebuilds. The style it comes from is `shellStyle` (ShellStyle.swift).
nonisolated(unsafe) var shellTheme: ShellTheme = .macosDark

// MARK: - ShellPalette

extension Color {
    /// Linear per-channel mix toward `other` by `t` (0 = self, 1 = other);
    /// alpha is kept from self.
    func mixed(toward other: Color, by t: Double) -> Color {
        Color(alpha: a,
              red: r + (other.r - r) * t,
              green: g + (other.g - g) * t,
              blue: b + (other.b - b) * t)
    }
}

/// Shared treatment for app-icon tiles. The dock and the launcher grid both
/// draw tiles through this, so every icon — whatever its base hue — gets the
/// identical top-lit vertical gradient and reads as one icon family.
enum ShellPalette {
    static func tileGradient(_ base: Color) -> LinearGradient {
        LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [base.mixed(toward: Color(0xFFFFFFFF), by: 0.12),
                     base.mixed(toward: Color(0xFF000000), by: 0.10)]
        )
    }

    /// Windows' **Acrylic**: a heavier blur that DESATURATES what it blurs,
    /// with the surface's translucent tint painted over it.
    ///
    /// The saturation figure is the whole difference from `frostFilter`, and
    /// it is not a tuning detail. macOS's glass boosts saturation, so the
    /// wallpaper reads through it vivid; Windows' acrylic pulls colour out,
    /// so it reads through muted and the tint dominates. Painting a Fluent
    /// palette onto a saturated blur is what made the first cut of this style
    /// look like macOS in grey.
    static func acrylicFilter(blurSigma: Double = 30) -> any ImageFilter {
        frostFilter(blurSigma: blurSigma, saturation: 0.75)
    }

    /// The active style's chrome blur. Anything drawing shell chrome should
    /// reach for this rather than for either material directly.
    static func chromeFilter(blurSigma: Double) -> any ImageFilter {
        switch shellTheme.material {
        case .glass:   return frostFilter(blurSigma: blurSigma)
        case .acrylic: return acrylicFilter(blurSigma: blurSigma * 1.6)
        }
    }

    /// Standard chrome frost: blur + gentle saturation boost. The window
    /// glass backdrop uses this directly; the dock/status chrome layers the
    /// liquid-glass refraction shader on top of the same base.
    static func frostFilter(blurSigma: Double, saturation: Double = 1.15) -> any ImageFilter {
        ImageFilterFactory.compose(
            outer: ColorFilter(matrix: saturationMatrix(saturation)),
            inner: ImageFilterFactory.blur(sigmaX: blurSigma, sigmaY: blurSigma)
        )
    }

    /// 5x4 color matrix scaling saturation around Rec.709 luma.
    static func saturationMatrix(_ s: Double) -> [Double] {
        let lr = 0.213, lg = 0.715, lb = 0.072
        return [
            lr + (1 - lr) * s,  lg - lg * s,        lb - lb * s,        0, 0,
            lr - lr * s,        lg + (1 - lg) * s,  lb - lb * s,        0, 0,
            lr - lr * s,        lg - lg * s,        lb + (1 - lb) * s,  0, 0,
            0,                  0,                  0,                  1, 0,
        ]
    }
}
