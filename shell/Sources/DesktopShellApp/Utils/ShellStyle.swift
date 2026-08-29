// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The desktop's look, as something you PICK rather than something compiled in.
//
// Three things vary between styles, and they are kept apart on purpose,
// because they cost wildly different amounts to change:
//
//   colours   ShellTheme    already existed, for light vs dark. Each style
//                           now supplies its own dark and light pair, and
//                           `shellTheme` still points at exactly one of them,
//                           so the ~130 existing `shellTheme.fgPrimary`-style
//                           readers never learn that styles exist.
//   metrics   ShellMetrics  the layout numbers everything else reads through
//                           DesktopTheme's `k*` names.
//   shape     ShellChrome   which surfaces exist at all, and where they sit.
//
// Recolouring the menu bar is the first. Replacing the menu bar and the dock
// with one taskbar is the third. A style that only wants to recolour supplies
// a palette and inherits the rest.
//
// Adding a style is one file plus one entry in `ShellStyles.all`. There is
// deliberately no `if style == .fluent` anywhere in the shell: the switch
// happens once, here, when the style is chosen.

import Flutter
import FlutterSwiftBridge
import FluentSystemIcons

// MARK: - ShellMetrics

/// The layout numbers a style owns. Everything else reads these through
/// `DesktopTheme`, which forwards; nothing outside this file should need to
/// know which style it is laying out for.
struct ShellMetrics {
    /// Height of the strip along the TOP of the screen. Windows lay out
    /// below it. 0 in a style with no top bar.
    let topInset: Double

    /// A window's title bar.
    let titleBarHeight: Double

    /// Corner radius of a windowed (non-fullscreen) window.
    let windowCornerRadius: Double

    /// Corner radius of a flyout, menu or panel. macOS rounds these more than
    /// Windows does, and it is one of the cheapest tells of which desktop you
    /// are looking at.
    let panelCornerRadius: Double

    /// The visible height of the bottom bar itself — the dock's pill, or the
    /// taskbar's strip.
    let bottomBarHeight: Double

    /// Gap between the bottom bar and the bottom edge of the screen. A bar
    /// that sits ON the edge has none; the macOS dock floats above it.
    let bottomBarMargin: Double

    /// Height of the bottom bar's whole layout area, which can exceed the
    /// bar: macOS dock icons magnify upward out of theirs, and the hovered
    /// app's name floats above that.
    let bottomBarContainerHeight: Double

    /// How much of the bottom edge a maximized window has to stay clear of.
    /// The floating dock reserves its pill plus both margins; a taskbar
    /// reserves its strip.
    var bottomInset: Double { bottomBarHeight + bottomBarMargin * 2 }

    /// Menu bar on top, floating magnifying dock at the bottom.
    static let macos = ShellMetrics(
        topInset: 32.0,
        titleBarHeight: 38.0,
        windowCornerRadius: 12.0,
        panelCornerRadius: 12.0,
        bottomBarHeight: 76.0,          // unchanged — Chrome height alignment
        bottomBarMargin: 6.0,           // unchanged — Chrome height alignment
        bottomBarContainerHeight: 132.0
    )

    /// One full-width taskbar on the bottom edge and nothing on top. Sized
    /// against Windows' own taskbar (48pt) rather than against a dock: a
    /// floating slab can afford to be tall because wallpaper surrounds it,
    /// and a solid strip across the screen cannot.
    /// The container is twice the strip on purpose: the hovered tile's name
    /// floats ABOVE the bar, and a layout box the size of the strip clips it
    /// away silently. The extra height paints nothing and takes no input.
    static let fluent = ShellMetrics(
        topInset: 0.0,
        titleBarHeight: 32.0,
        windowCornerRadius: 8.0,
        panelCornerRadius: 8.0,
        bottomBarHeight: 48.0,
        bottomBarMargin: 0.0,
        bottomBarContainerHeight: 96.0
    )
}

// MARK: - TitleBarParams

/// Everything a title bar needs, in one value. A title bar is the one piece of
/// chrome that touches no shell state, so styles supply it as a plain function
/// rather than through `ShellChrome` — that is what lets `DesktopWindow` build
/// one without reaching for the shell.
struct TitleBarParams {
    let title: String
    let isFocused: Bool
    let isMaximized: Bool
    let isFullscreen: Bool
    let onMove: ((Offset) -> Void)?
    let onMinimize: (() -> Void)?
    let onMaximize: (() -> Void)?
    let onClose: (() -> Void)?
    /// Toggles maximized. Detected by hand inside the pointer handler, never
    /// through `onDoubleTap` — registering that kills tap AND double-tap on
    /// the DRM embedder.
    let onDoubleTap: (() -> Void)?
}

// MARK: - ShellChrome

/// The surfaces a style draws, and where. One instance per shell state, made
/// by the active style and replaced when the style changes.
///
/// **Every method returns a widget already positioned** in the shell's root
/// `Stack` — a `Positioned`, or something that fills. Placement is part of the
/// shape: a floating dock and an edge-to-edge taskbar do not sit in the same
/// rectangle, so the caller cannot own the geometry.
protocol ShellChrome: AnyObject {
    /// The strip along the top of the screen. nil in a style without one.
    func topBar() -> Widget?

    /// The strip along the bottom, laid out in `output`'s own coordinates.
    /// `opacity` is below 1 while it fades for a space slide or a fullscreen
    /// auto-hide; nil when it should not draw at all.
    ///
    /// Takes an output because a secondary monitor builds its OWN copy of the
    /// chrome in its own tree — one method rather than two keeps the two trees
    /// from drifting into different bars.
    func bottomBar(forOutput output: DisplayOutput, opacity: Double) -> Widget?

    /// The app launcher — full-screen Launchpad, or a panel above the bar.
    func launcher() -> Widget

    /// The panel a status item opens (clock, network, battery, power…).
    func statusFlyout(_ kind: _DesktopShellState.StatusBarPopup) -> Widget

    /// Where that panel's top-left corner lands on screen, given the height it
    /// measured to. `statusFlyout` positions the panel and the liquid-glass
    /// filter refracts the wallpaper underneath it — both read THIS, because
    /// two answers means the glass warps a rectangle the panel is not in.
    func statusFlyoutOrigin(_ kind: _DesktopShellState.StatusBarPopup,
                            height: Double) -> Offset

    /// The desktop's own right-click menu.
    func desktopMenu() -> Widget

    /// The right-click menu on a bottom-bar tile, or nil when there is none
    /// to show.
    func appIconMenu(forOutput output: DisplayOutput) -> Widget?

    /// Global pointer position, for whatever hover effect the bar owns —
    /// dock magnification, taskbar tile highlight. Called for every pointer
    /// move on the desktop, so it must stay cheap.
    func notePointerHover(x: Double, y: Double, outputId: Int)

    /// Every slot on the bottom bar as it is on screen right now: the app id
    /// and the centre of its icon, in `output`'s own coordinates. Slot 0 is
    /// the launcher or Start.
    ///
    /// This is served over the broker so tooling drives the REAL bar rather
    /// than a mirror of its layout — a mirror cannot work when the bar is
    /// centre-aligned and grows a tile for every running app, which is how
    /// `shell-drive.py` once clicked 122px away from the launcher and
    /// reported it as broken. A style that changes the layout must answer
    /// here or every scripted click lands in the wrong place.
    func barSlots(forOutput output: DisplayOutput)
        -> [(app: String, x: Double, y: Double, size: Double)]
}

// MARK: - ShellStyleSpec

/// One complete look. Pure data plus two factories; holds no state, so it is
/// safe to keep in a global and to compare by `id`.
struct ShellStyleSpec {
    /// Stable, lowercase, and PERSISTED — renaming one silently resets every
    /// user of it back to the default.
    let id: String

    /// What the menu calls it.
    let name: String

    let metrics: ShellMetrics

    /// Built on demand rather than stored as two values, because a palette
    /// can depend on things outside itself: the Fluent one is a function of
    /// the WALLPAPER (see `shellMica`), so it has to be re-resolved when the
    /// wallpaper changes rather than baked once at launch.
    let makeTheme: (_ dark: Bool) -> ShellTheme

    let makeTitleBar: (TitleBarParams) -> Widget
    let makeChrome: (_DesktopShellState) -> any ShellChrome

    func theme(dark isDark: Bool) -> ShellTheme { makeTheme(isDark) }
}

/// The wallpaper's average colour — the ingredient Windows' **Mica** leans
/// its chrome toward, and the reason Windows 11 chrome looks related to the
/// desktop behind it instead of being flat grey. nil until the wallpaper
/// decode lands, which simply draws the untinted base.
///
/// Real Mica is the compositor blending a blurred desktop behind translucent
/// window regions. What the eye actually reads off Windows' chrome at rest is
/// the TINT, and that is affordable on any surface, opaque ones included —
/// the same conclusion the Windows shell reached (`Win11.micaTint`).
nonisolated(unsafe) var shellMica: Color? = nil

// MARK: - The registry

// `nonisolated(unsafe)` throughout: a spec carries widget-building closures,
// so it is not Sendable, and the whole style system is main-thread-only by the
// same contract as `shellTheme`. Nothing here is ever mutated after init.
enum ShellStyles {
    /// macOS: menu bar, floating dock, traffic lights, Launchpad.
    nonisolated(unsafe) static let macos = ShellStyleSpec(
        id: "macos",
        name: "macOS",
        metrics: .macos,
        makeTheme: { $0 ? .macosDark : .macosLight },
        makeTitleBar: { p in
            WindowTitleBar(
                title: p.title,
                isFocused: p.isFocused,
                isMaximized: p.isMaximized,
                isFullscreen: p.isFullscreen,
                onMove: p.onMove,
                onMinimize: p.onMinimize,
                onMaximize: p.onMaximize,
                onClose: p.onClose,
                onDoubleTap: p.onDoubleTap
            )
        },
        makeChrome: { MacosChrome(shell: $0) }
    )

    /// Windows 11: one taskbar on the bottom edge, Start, caption buttons on
    /// the right.
    ///
    /// The launcher and the flyout CONTENTS are still the macOS ones — see
    /// `FluentChrome`, which names each one that has not been ported yet.
    nonisolated(unsafe) static let fluent = ShellStyleSpec(
        id: "fluent",
        name: "Windows",
        metrics: .fluent,
        makeTheme: { ShellTheme.fluent(dark: $0, mica: shellMica) },
        makeTitleBar: { p in
            FluentTitleBar(
                title: p.title,
                isFocused: p.isFocused,
                isMaximized: p.isMaximized,
                isFullscreen: p.isFullscreen,
                onMove: p.onMove,
                onMinimize: p.onMinimize,
                onMaximize: p.onMaximize,
                onClose: p.onClose,
                onDoubleTap: p.onDoubleTap
            )
        },
        makeChrome: { FluentChrome(shell: $0) }
    )

    /// Every style the desktop can be switched to, in menu order. The first
    /// is the default for a machine that has never been switched.
    nonisolated(unsafe) static let all: [ShellStyleSpec] = [macos, fluent]

    /// Resolve a persisted id, falling back to the default rather than
    /// failing — an id from a newer build, or a hand-edited config file,
    /// should give you a desktop and not a dead session.
    static func byId(_ id: String) -> ShellStyleSpec {
        all.first { $0.id == id } ?? all[0]
    }
}

/// The active style. Main-thread only, like `shellTheme`; switch it through
/// the shell's `_setStyle` so the tree remounts.
nonisolated(unsafe) var shellStyle: ShellStyleSpec = ShellStyles.all[0]

/// The active style's layout numbers. Computed rather than stored, so it
/// cannot drift out of sync with `shellStyle`.
var shellMetrics: ShellMetrics { shellStyle.metrics }

// MARK: - MacosChrome

/// The look the desktop shipped with. Every method here forwards to a builder
/// that already lives on `_DesktopShellState` — this class exists to name the
/// seam, not to hold logic.
final class MacosChrome: ShellChrome {
    unowned let shell: _DesktopShellState

    init(shell: _DesktopShellState) { self.shell = shell }

    func topBar() -> Widget? { shell.macosTopBar() }

    func bottomBar(forOutput output: DisplayOutput, opacity: Double) -> Widget? {
        shell.macosDock(forOutput: output, opacity: opacity)
    }

    func launcher() -> Widget { shell.macosLauncher() }

    func statusFlyout(_ kind: _DesktopShellState.StatusBarPopup) -> Widget {
        shell.macosStatusFlyout(kind)
    }

    func statusFlyoutOrigin(_ kind: _DesktopShellState.StatusBarPopup,
                            height: Double) -> Offset {
        shell.macosStatusFlyoutOrigin(kind)
    }

    func desktopMenu() -> Widget { shell.macosDesktopMenu() }

    func appIconMenu(forOutput output: DisplayOutput) -> Widget? {
        shell.dockIconMenuWidget(forOutput: output)
    }

    func notePointerHover(x: Double, y: Double, outputId: Int) {
        shell._updateDockHover(x: x, y: y, outputId: outputId)
    }

    func barSlots(forOutput output: DisplayOutput)
        -> [(app: String, x: Double, y: Double, size: Double)] {
        shell.macosDockSlots(forOutput: output)
    }
}

// MARK: - The Fluent palette

// Windows 11's own colours, and not invented ones: these are the values the
// Windows shell in this tree sampled off real Explorer, dark and light
// (`Win11` in sdk/Examples/WinShellBar/Files.swift). Keeping the two in step
// is the point — the same desktop should not disagree with itself about what
// either theme is depending on which OS it is impersonating on.
//
// The colours alone are not the look, which is the trap this style fell into
// first: a Fluent palette painted onto macOS materials still reads as macOS,
// because what the eye actually identifies is the MATERIAL. Two of them here:
//
//   Mica     chrome leans toward the wallpaper's average colour, so a Windows
//            desktop's chrome looks related to the picture behind it rather
//            than being flat grey sitting on top of it.
//   Acrylic  flyouts are a blur that DESATURATES what it blurs, with a
//            translucent tint over it. macOS's glass boosts saturation
//            instead — the two materials pull in opposite directions, and
//            that is one of the clearest tells of which desktop you are on.

extension ShellTheme {
    static func fluent(dark: Bool, mica tint: Color?) -> ShellTheme {
        /// `base` leaned toward the wallpaper's average by `amount`, which is
        /// Mica. Windows leans further in light than in dark.
        func mica(_ base: Color, _ amount: Double) -> Color {
            guard let tint else { return base }
            return base.mixed(toward: tint, by: amount)
        }
        let lean = dark ? 0.15 : 0.20

        // Sampled from Explorer. Named as Windows names them so the mapping
        // to the shell's own token names below stays checkable.
        let windowBg   = mica(dark ? Color(0xFF202020) : Color(0xFFF3F3F3), lean)
        let stroke     = dark ? Color(0xFF383838) : Color(0xFFE5E5E5)
        let text       = dark ? Color(0xFFFFFFFF) : Color(0xFF1B1B1B)
        let textDim    = dark ? Color(0xFFC5C5C5) : Color(0xFF5F5F5F)
        let textFaint  = dark ? Color(0xFF8A8A8A) : Color(0xFF8F8F8F)
        let accent     = dark ? Color(0xFF4CC2FF) : Color(0xFF005FB8)
        let hover      = dark ? Color(0x14FFFFFF) : Color(0x0A000000)
        let fieldFill  = dark ? Color(0xFF2D2D2D) : Color(0xFFFFFFFF)
        let menuBorder = dark ? Color(0xFF454545) : Color(0xFFD4D4D4)
        let menuHover  = dark ? Color(0xFF383838) : Color(0xFFF0F0F0)
        let menuSep    = dark ? Color(0xFF3D3D3D) : Color(0xFFE4E4E4)
        let menuShadow = dark ? Color(0x66000000) : Color(0x2E000000)

        // The acrylic TINT, not the whole surface: every panel that uses
        // these puts a blur underneath, and the alpha is what lets the
        // frosted wallpaper through. Opaque here would be a grey slab.
        let acrylic = mica(dark ? Color(0xE02C2C2C) : Color(0xE0FCFCFC), lean)
        // The taskbar is thinner acrylic than a flyout — Windows lets more of
        // the desktop through the bar than through a menu.
        let barAcrylic = mica(dark ? Color(0xD91F1F1F) : Color(0xD9F3F3F3), lean)

        return ShellTheme(
            name: dark ? "Dark" : "Light",
            isDark: dark,
            fgPrimary: text,
            fgSecondary: textDim,
            fgTertiary: textFaint,
            barTint: barAcrylic,
            barHairline: dark ? Color(0x1FFFFFFF) : Color(0x14000000),
            hoverFill: hover,
            popupTint: acrylic,
            popupInnerBorder: menuBorder,
            popupDivider: menuSep,
            popupShadow: menuShadow,
            // The taskbar paints no pill, but these must still read as
            // something sane if anything reaches for them.
            dockGradientTop: barAcrylic,
            dockGradientBottom: barAcrylic,
            dockRim: dark ? Color(0x1FFFFFFF) : Color(0x14000000),
            dockShadow: menuShadow,
            dockIndicator: textFaint,
            dockIndicatorRim: Color(0x00000000),
            dockLabelTint: acrylic,
            dockLabelBorder: menuBorder,
            dockLabelText: text,
            // Mica, and this is the token that carries it furthest: it is the
            // material behind every window.
            windowGlassTint: windowBg,
            // A Windows caption is the SAME colour as the window under it —
            // not a darker strip laid across the top, which is the macOS
            // shape. An unfocused one only loses its text contrast.
            titleBarActive: windowBg,
            titleBarInactive: windowBg,
            titleTextActive: text,
            titleTextInactive: textFaint,
            windowBorderFocused: stroke,
            windowBorderUnfocused: dark ? Color(0xFF2B2B2B) : Color(0xFFEDEDED),
            trafficLightInactive: dark ? Color(0x40FFFFFF) : Color(0x33000000),
            overlayScrim: dark ? Color(0xA80E0E12) : Color(0x800E0E12),
            overlayText: Color(0xE6FFFFFF),
            overlayTextDim: Color(0x99FFFFFF),
            accent: accent,
            barFill: barAcrylic,
            barHover: dark ? Color(0x1AFFFFFF) : Color(0x0F000000),
            runningIndicator: textFaint,
            runningIndicatorActive: accent,
            captionHover: dark ? Color(0x1AFFFFFF) : Color(0x0F000000),
            captionCloseHover: Color(0xFFC42B1C),
            captionCloseInk: Color(0xFFFFFFFF),
            panelFill: acrylic,
            panelStroke: menuBorder,
            controlFill: fieldFill,
            controlStroke: stroke,
            controlHover: menuHover,
            // Black in dark mode, and that is not a typo: Fluent's dark
            // accent is a LIGHT blue and takes black glyphs.
            accentInk: dark ? Color(0xFF000000) : Color(0xFFFFFFFF),
            trackRest: dark ? Color(0xFF9D9D9D) : Color(0xFF868686),
            fontFamily: SelawikFont.family,
            fontFamilyStrong: SelawikFont.semibold,
            material: .acrylic
        )
    }
}
