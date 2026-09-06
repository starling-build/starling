// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The Fluent design tokens that are NUMBERS: shape, spacing, stroke, motion
// and elevation. Colours live in `ColorResources.swift` (WinUI's own
// dictionary) and type in `FluentTypography.swift`; this file is the rest of
// the system, so that no Fluent surface anywhere carries a literal `8` or a
// hand-picked `250ms`.
//
// Two sources, and they are kept apart on purpose because they answer
// different questions:
//
//   Fluent 2   (fluent2.microsoft.design; values from @fluentui/tokens)
//              the cross-platform global tokens — the ramp of radii, spacing
//              steps, stroke widths, durations and easing curves that every
//              Microsoft product picks from.
//   Windows 11 (learn.microsoft.com, "signature experiences")
//              which of those a Windows surface uses, by role: 8px on a
//              flyout, 4px on a button, elevation 32 under a flyout and 128
//              under a window, a 167ms "direct entrance" with a decelerate
//              curve.
//
// Nothing here knows about a desktop, a window manager or an app. A caller
// that wants "a flyout's corner" asks for `FluentCorners.overlay`; a caller
// that wants "the second step of the ramp" asks for `FluentCorners.medium`.
// Both are 4 and 8 today, and the names are what keep them from drifting
// when one of them changes.

import FlutterSwiftBridge

// MARK: - Shape

/// Corner radii. Windows 11 uses exactly three: `overlay` for top-level
/// containers (windows, flyouts, dialogs, menus), `control` for in-page
/// elements (buttons, list backplates, tooltips, bars), and none where a
/// straight edge meets another or a window is snapped or maximized.
public enum FluentCorners {
    // Windows 11 roles (signature-experiences/geometry). `ControlCornerRadius`
    // and `OverlayCornerRadius` are WinUI's names for the two resources.
    public static let none: Double = 0
    public static let control: Double = 4
    public static let overlay: Double = 8
    /// Top-level app windows, when floating. Snapped and maximized windows
    /// are not rounded.
    public static let window: Double = 8
    /// ToolTip is the one overlay that stays at 4, because of its size.
    public static let tooltip: Double = 4
    /// Bars and lines: ProgressBar, ScrollBar, Slider tracks.
    public static let bar: Double = 4

    // The Fluent 2 global ramp (borderRadius.ts).
    public static let small: Double = 2
    public static let medium: Double = 4
    public static let large: Double = 6
    public static let xLarge: Double = 8
    public static let xxLarge: Double = 12
    public static let xxxLarge: Double = 16
    /// Large enough to round any box into a pill.
    public static let circular: Double = 10000

    public static var controlRadius: BorderRadius { BorderRadius.circular(control) }
    public static var overlayRadius: BorderRadius { BorderRadius.circular(overlay) }
    public static var windowRadius: BorderRadius { BorderRadius.circular(window) }
    public static var tooltipRadius: BorderRadius { BorderRadius.circular(tooltip) }
}

// MARK: - Spacing

/// The spacing ramp, and the Windows layout rules stated in it.
public enum FluentSpacing {
    // The Fluent 2 global ramp (spacings.ts). The same values apply on both
    // axes; the web tokens only split them so a design tool can override one.
    public static let none: Double = 0
    public static let xxs: Double = 2
    public static let xs: Double = 4
    public static let sNudge: Double = 6
    public static let s: Double = 8
    public static let mNudge: Double = 10
    public static let m: Double = 12
    public static let l: Double = 16
    public static let xl: Double = 20
    public static let xxl: Double = 24
    public static let xxxl: Double = 32

    // Windows 11 layout rules (basics/content-basics).
    /// Between two buttons, a button and its flyout, a control and its header.
    public static let betweenControls: Double = 8
    /// Between a control and its label, and between two content areas.
    public static let controlToLabel: Double = 12
    /// From a surface's edge to the text inside it.
    public static let surfaceInset: Double = 16
    /// The smallest target a finger can be expected to hit.
    public static let minimumTarget: Double = 40
    /// A standard control (Button, TextBox, ComboBox) is 32 tall; the
    /// compact density is 24.
    public static let controlHeight: Double = 32
    public static let compactControlHeight: Double = 24
}

// MARK: - Stroke

/// Stroke widths (strokeWidths.ts). Every Windows surface's outline is `thin`;
/// `thick` is the keyboard focus ring.
public enum FluentStrokeWidth {
    public static let thin: Double = 1
    public static let thick: Double = 2
    public static let thicker: Double = 3
    public static let thickest: Double = 4
}

// MARK: - Motion

/// Durations and curves. The Fluent 2 ramp is the vocabulary; the Windows
/// table at the bottom is which words a Windows surface uses.
public enum FluentMotion {
    // Fluent 2 durations (durations.ts).
    public static let ultraFast: Duration = .milliseconds(50)
    public static let faster: Duration = .milliseconds(100)
    public static let fast: Duration = .milliseconds(150)
    public static let normal: Duration = .milliseconds(200)
    public static let gentle: Duration = .milliseconds(250)
    public static let slow: Duration = .milliseconds(300)
    public static let slower: Duration = .milliseconds(400)
    public static let ultraSlow: Duration = .milliseconds(500)

    // Fluent 2 curves (curves.ts). "Decelerate" curves are for things
    // arriving, "accelerate" for things leaving, "easy ease" for things that
    // stay on screen and move.
    nonisolated(unsafe) public static let accelerateMax: any Curve = Cubic(0.9, 0.1, 1.0, 0.2)
    nonisolated(unsafe) public static let accelerateMid: any Curve = Cubic(1.0, 0.0, 1.0, 1.0)
    nonisolated(unsafe) public static let accelerateMin: any Curve = Cubic(0.8, 0.0, 0.78, 1.0)
    nonisolated(unsafe) public static let decelerateMax: any Curve = Cubic(0.1, 0.9, 0.2, 1.0)
    nonisolated(unsafe) public static let decelerateMid: any Curve = Cubic(0.0, 0.0, 0.0, 1.0)
    nonisolated(unsafe) public static let decelerateMin: any Curve = Cubic(0.33, 0.0, 0.1, 1.0)
    nonisolated(unsafe) public static let easyEaseMax: any Curve = Cubic(0.8, 0.0, 0.2, 1.0)
    nonisolated(unsafe) public static let easyEase: any Curve = Cubic(0.33, 0.0, 0.67, 1.0)
    nonisolated(unsafe) public static let linear: any Curve = Curves.linear

    /// One named animation: how long, and along what curve.
    public struct Spec {
        public let duration: Duration
        public let curve: any Curve
        public init(duration: Duration, curve: any Curve) {
            self.duration = duration
            self.curve = curve
        }
    }

    // Windows 11's own table (signature-experiences/motion). The three
    // durations of an entrance are the three sizes of thing that can enter:
    // a tooltip, a flyout, a page.

    /// Fast in: something appearing where it will stay. Position, scale.
    public static let directEntranceFast = Spec(duration: .milliseconds(167), curve: decelerateMid)

    /// Windows' `MenuShowDelay` (`SPI_GETMENUSHOWDELAY`, 400 ms by default):
    /// how long the pointer rests on a submenu's item before it opens, and
    /// on another item before an open submenu closes.
    public static let menuShowDelay: Duration = .milliseconds(400)
    public static let directEntrance = Spec(duration: .milliseconds(250), curve: decelerateMid)
    public static let directEntranceSlow = Spec(duration: .milliseconds(333), curve: decelerateMid)

    /// Point to point: something already on screen moving somewhere else.
    nonisolated(unsafe) public static let pointToPointCurve: any Curve = Cubic(0.55, 0.55, 0.0, 1.0)
    public static let pointToPointFast = Spec(duration: .milliseconds(167), curve: pointToPointCurve)
    public static let pointToPoint = Spec(duration: .milliseconds(250), curve: pointToPointCurve)
    public static let pointToPointSlow = Spec(duration: .milliseconds(333), curve: pointToPointCurve)

    /// Fast out: something leaving. ALWAYS combined with a fade out.
    public static let directExit = Spec(duration: .milliseconds(167), curve: decelerateMid)

    /// Soft out: a gentler leave, for position and scale.
    public static let gentleExit = Spec(duration: .milliseconds(167), curve: accelerateMid)

    /// The bare minimum: a fade in or out, and nothing else.
    public static let fade = Spec(duration: .milliseconds(83), curve: linear)

    /// Elastic in: three keyframes, played in order. For position and scale.
    public static let strongEntrance: [Spec] = [
        Spec(duration: .milliseconds(167), curve: Cubic(0.85, 0.0, 0.0, 1.0)),
        Spec(duration: .milliseconds(167), curve: Cubic(0.85, 0.0, 0.75, 1.0)),
        Spec(duration: .milliseconds(333), curve: Cubic(0.85, 0.0, 0.0, 1.0)),
    ]
}

// MARK: - Elevation

/// Depth, as shadow. Windows 11 pairs every elevated surface with a 1px
/// stroke as well; the stroke colour is the surface's business
/// (`surfaceStrokeColorFlyout`, `cardStrokeColorDefault`), the shadow is
/// this.
///
/// The shadow is Fluent 2's two-layer recipe (utils/shadows.ts): an AMBIENT
/// layer that is a soft halo straight around the box, and a KEY layer offset
/// downward by half the elevation and blurred by the whole of it. Dark mode
/// doubles the alphas, because a shadow on a dark surface has to be stronger
/// to read at all.
public enum FluentElevation {
    // Windows 11 roles (signature-experiences/layering).
    public static let layer: Double = 1
    public static let control: Double = 2
    /// A pressed control drops to 1.
    public static let controlPressed: Double = 1
    public static let card: Double = 8
    public static let tooltip: Double = 16
    public static let flyout: Double = 32
    public static let dialog: Double = 128
    public static let window: Double = 128

    /// The shadows for a surface at `elevation`, in painting order. Empty at
    /// or below zero.
    ///
    /// `color` is the ink the two layers are made of — black, unless a
    /// coloured surface wants a coloured shadow (Fluent 2's "brand" shadows
    /// do exactly this); the alphas come from the recipe, not from the colour.
    public static func shadows(
        _ elevation: Double,
        brightness: Brightness,
        color: Color = Color(0xFF000000)
    ) -> [BoxShadow] {
        guard elevation > 0 else { return [] }
        let dark = brightness == .dark
        let ambientAlpha: Double = dark ? 0.24 : 0.12
        let keyAlpha: Double = dark ? 0.28 : 0.14
        // The ambient halo widens once past the low ramp: 2px up to and
        // including 16, 8px from 28 up.
        let ambientBlur: Double = elevation >= 28 ? 8 : 2
        return [
            BoxShadow(
                color: color.withValues(alpha: ambientAlpha),
                offset: Offset.zero,
                blurRadius: ambientBlur
            ),
            BoxShadow(
                color: color.withValues(alpha: keyAlpha),
                offset: Offset(0, elevation / 2),
                blurRadius: elevation
            ),
        ]
    }
}
