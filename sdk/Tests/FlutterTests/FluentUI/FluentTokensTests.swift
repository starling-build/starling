// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The Fluent tokens, materials and ramps, pinned to the values Microsoft
// publishes. Every number here is traceable: WinUI's theme XAML for the
// acrylic recipes and the type ramp, @fluentui/tokens for the shape, motion
// and shadow ramps, the Windows 11 signature-experience pages for the roles,
// and `UISettings.GetColorValue` for the accent shades. A test failing here
// means the SDK drifted from Windows, not that Windows changed.

import XCTest
@testable import Flutter
@testable import FlutterSwiftBridge

final class FluentTokensTests: XCTestCase {

    // MARK: Shape, spacing, stroke

    func testWindowsCornerRoles() {
        XCTAssertEqual(FluentCorners.control, 4)
        XCTAssertEqual(FluentCorners.overlay, 8)
        XCTAssertEqual(FluentCorners.window, 8)
        XCTAssertEqual(FluentCorners.tooltip, 4)
        XCTAssertEqual(FluentCorners.bar, 4)
        XCTAssertEqual(FluentCorners.overlayRadius, BorderRadius.circular(8))
    }

    func testFluent2ShapeRamp() {
        XCTAssertEqual(FluentCorners.small, 2)
        XCTAssertEqual(FluentCorners.medium, 4)
        XCTAssertEqual(FluentCorners.large, 6)
        XCTAssertEqual(FluentCorners.xLarge, 8)
        XCTAssertEqual(FluentCorners.xxLarge, 12)
        XCTAssertEqual(FluentCorners.circular, 10000)
    }

    func testSpacingRampAndWindowsRules() {
        XCTAssertEqual([FluentSpacing.xxs, FluentSpacing.xs, FluentSpacing.sNudge, FluentSpacing.s,
                        FluentSpacing.mNudge, FluentSpacing.m, FluentSpacing.l, FluentSpacing.xl,
                        FluentSpacing.xxl, FluentSpacing.xxxl],
                       [2, 4, 6, 8, 10, 12, 16, 20, 24, 32])
        XCTAssertEqual(FluentSpacing.betweenControls, 8)
        XCTAssertEqual(FluentSpacing.controlToLabel, 12)
        XCTAssertEqual(FluentSpacing.surfaceInset, 16)
        XCTAssertEqual(FluentSpacing.minimumTarget, 40)
        XCTAssertEqual(FluentSpacing.controlHeight, 32)
        XCTAssertEqual(FluentStrokeWidth.thin, 1)
        XCTAssertEqual(FluentStrokeWidth.thick, 2)
    }

    // MARK: Motion

    func testFluent2Durations() {
        XCTAssertEqual(FluentMotion.ultraFast, .milliseconds(50))
        XCTAssertEqual(FluentMotion.normal, .milliseconds(200))
        XCTAssertEqual(FluentMotion.ultraSlow, .milliseconds(500))
    }

    func testWindowsMotionTable() {
        XCTAssertEqual(FluentMotion.directEntranceFast.duration, .milliseconds(167))
        XCTAssertEqual(FluentMotion.menuShowDelay, .milliseconds(400))
        XCTAssertEqual(FluentMotion.directEntrance.duration, .milliseconds(250))
        XCTAssertEqual(FluentMotion.directEntranceSlow.duration, .milliseconds(333))
        XCTAssertEqual(FluentMotion.directExit.duration, .milliseconds(167))
        XCTAssertEqual(FluentMotion.fade.duration, .milliseconds(83))
        XCTAssertEqual(FluentMotion.strongEntrance.map { $0.duration },
                       [.milliseconds(167), .milliseconds(167), .milliseconds(333)])
    }

    /// The curves have to have the SHAPE their names promise: a decelerate
    /// curve is ahead of linear at the midpoint, an accelerate curve behind.
    func testCurveShapes() {
        XCTAssertGreaterThan(FluentMotion.decelerateMid.transform(0.5), 0.8)
        XCTAssertGreaterThan(FluentMotion.decelerateMax.transform(0.5), 0.8)
        XCTAssertLessThan(FluentMotion.accelerateMid.transform(0.5), 0.2)
        XCTAssertLessThan(FluentMotion.accelerateMax.transform(0.5), 0.2)
        XCTAssertEqual(FluentMotion.easyEase.transform(0.5), 0.5, accuracy: 0.05)
        XCTAssertEqual(FluentMotion.linear.transform(0.3), 0.3, accuracy: 1e-9)
        // Direct entrance/exit are the decelerate-mid curve; gentle exit
        // accelerates.
        XCTAssertGreaterThan(FluentMotion.directEntrance.curve.transform(0.5), 0.8)
        XCTAssertLessThan(FluentMotion.gentleExit.curve.transform(0.5), 0.2)
        XCTAssertGreaterThan(FluentMotion.pointToPointCurve.transform(0.5), 0.5)
    }

    // MARK: Elevation

    func testElevationRoles() {
        XCTAssertEqual(FluentElevation.layer, 1)
        XCTAssertEqual(FluentElevation.control, 2)
        XCTAssertEqual(FluentElevation.card, 8)
        XCTAssertEqual(FluentElevation.tooltip, 16)
        XCTAssertEqual(FluentElevation.flyout, 32)
        XCTAssertEqual(FluentElevation.dialog, 128)
        XCTAssertEqual(FluentElevation.window, 128)
    }

    func testShadowRecipe() {
        XCTAssertTrue(FluentElevation.shadows(0, brightness: .light).isEmpty)

        let flyout = FluentElevation.shadows(32, brightness: .light)
        XCTAssertEqual(flyout.count, 2)
        // Ambient: no offset, 8px once past the low ramp, 12% ink.
        XCTAssertEqual(flyout[0].offset, Offset.zero)
        XCTAssertEqual(flyout[0].blurRadius, 8)
        XCTAssertEqual(flyout[0].color.a, 0.12, accuracy: 0.005)
        // Key: half the elevation down, blurred by the whole of it, 14% ink.
        XCTAssertEqual(flyout[1].offset, Offset(0, 16))
        XCTAssertEqual(flyout[1].blurRadius, 32)
        XCTAssertEqual(flyout[1].color.a, 0.14, accuracy: 0.005)

        // The low ramp keeps a tight 2px ambient halo.
        XCTAssertEqual(FluentElevation.shadows(16, brightness: .light)[0].blurRadius, 2)

        // Dark doubles the ink.
        let dark = FluentElevation.shadows(8, brightness: .dark)
        XCTAssertEqual(dark[0].color.a, 0.24, accuracy: 0.005)
        XCTAssertEqual(dark[1].color.a, 0.28, accuracy: 0.005)
    }

    // MARK: Type

    func testTypeRampIsWinUIs() {
        let t = Typography.fromBrightness(brightness: .light)
        XCTAssertEqual(t.caption?.fontSize, 12)
        XCTAssertEqual(t.caption?.fontWeight, .normal, "Caption is Regular in WinUI, not Light")
        XCTAssertEqual(t.caption!.height!, 16.0 / 12.0, accuracy: 1e-9)
        XCTAssertEqual(t.body?.fontSize, 14)
        XCTAssertEqual(t.body?.fontWeight, .normal)
        XCTAssertEqual(t.bodyStrong?.fontWeight, .w600)
        XCTAssertEqual(t.bodyLarge?.fontSize, 18)
        XCTAssertEqual(t.bodyLargeStrong?.fontSize, 18)
        XCTAssertEqual(t.bodyLargeStrong?.fontWeight, .w600)
        XCTAssertEqual(t.subtitle?.fontSize, 20)
        XCTAssertEqual(t.title?.fontSize, 28)
        XCTAssertEqual(t.titleLarge?.fontSize, 40)
        XCTAssertEqual(t.display?.fontSize, 68)
        XCTAssertEqual(t.display!.height!, 92.0 / 68.0, accuracy: 1e-9)
    }

    func testTypographyMergeCarriesBodyLargeStrong() {
        let base = Typography.fromBrightness(brightness: .dark)
        let merged = base.merge(Typography(bodyLargeStrong: TextStyle(fontSize: 19)))
        XCTAssertEqual(merged.bodyLargeStrong?.fontSize, 19)
        XCTAssertEqual(merged.bodyLarge?.fontSize, 18)
    }

    // MARK: Accent

    func testWindowsDefaultAccentShades() {
        let a = FluentColors.windowsBlue
        XCTAssertEqual(a.normal, Color(0xFF0078D4))
        XCTAssertEqual(a.light3, Color(0xFF99EBFF))
        XCTAssertEqual(a.light2, Color(0xFF4CC2FF))
        XCTAssertEqual(a.light1, Color(0xFF0091F8))
        XCTAssertEqual(a.dark1, Color(0xFF0067C0))
        XCTAssertEqual(a.dark2, Color(0xFF003E92))
        XCTAssertEqual(a.dark3, Color(0xFF001A68))
    }

    /// WinUI: AccentFillColorDefault is Dark 1 in the light theme and Light 2
    /// in the dark theme.
    func testAccentBrushFollowsWinUI() {
        let a = FluentColors.windowsBlue
        XCTAssertEqual(a.defaultBrushFor(.light), Color(0xFF0067C0))
        XCTAssertEqual(a.defaultBrushFor(.dark), Color(0xFF4CC2FF))
        XCTAssertTrue(FluentThemeData.light().accentColor === FluentColors.windowsBlue)
        XCTAssertTrue(FluentThemeData.dark().accentColor === FluentColors.windowsBlue)
    }

    // MARK: Materials

    func testAcrylicRecipesAreWinUIs() {
        let l = FluentMaterialRecipe.acrylicDefault(.light)
        XCTAssertEqual(l.tintColor, Color(0xFFFCFCFC))
        XCTAssertEqual(l.tintOpacity, 0.0)
        XCTAssertEqual(l.luminosityOpacity, 0.85)
        XCTAssertEqual(l.fallbackColor, Color(0xFFF9F9F9))
        XCTAssertEqual(l.blurAmount, 30)

        let d = FluentMaterialRecipe.acrylicDefault(.dark)
        XCTAssertEqual(d.tintColor, Color(0xFF2C2C2C))
        XCTAssertEqual(d.tintOpacity, 0.15)
        XCTAssertEqual(d.luminosityOpacity, 0.96)

        let base = FluentMaterialRecipe.acrylicBase(.dark)
        XCTAssertEqual(base.tintColor, Color(0xFF202020))
        XCTAssertEqual(base.tintOpacity, 0.5)
        XCTAssertEqual(base.fallbackColor, Color(0xFF1C1C1C))
        XCTAssertEqual(FluentMaterialRecipe.acrylicBase(.light).fallbackColor, Color(0xFFEEEEEE))
    }

    func testMicaRecipes() {
        let l = FluentMaterialRecipe.mica(.light)
        XCTAssertEqual(l.tintColor, Color(0xFFF3F3F3))
        XCTAssertEqual(l.tintOpacity, 0.5)
        XCTAssertEqual(l.luminosityOpacity, 1.0)
        XCTAssertEqual(l.blurAmount, 0)
        XCTAssertEqual(FluentMaterialRecipe.mica(.dark).tintOpacity, 0.8)
        XCTAssertEqual(FluentMaterialRecipe.micaAlt(.dark).tintOpacity, 0.0)
        // The documented fallbacks: SolidBackgroundFillColorBase and BaseAlt.
        XCTAssertEqual(l.fallbackColor, ResourceDictionary.light().solidBackgroundFillColorBase)
        XCTAssertEqual(FluentMaterialRecipe.micaAlt(.light).fallbackColor,
                       ResourceDictionary.light().solidBackgroundFillColorBaseAlt)
        XCTAssertEqual(FluentMaterialRecipe.micaAlt(.dark).fallbackColor,
                       ResourceDictionary.dark().solidBackgroundFillColorBaseAlt)
    }

    /// One wallpaper sample resolves to an OPAQUE colour that keeps the
    /// tint's lightness (luminosity opacity 1.0) and only leans in hue.
    func testMicaResolvesFromOneSample() {
        let recipe = FluentMaterialRecipe.mica(.light)
        XCTAssertEqual(recipe.resolve(over: nil), Color(0xFFF3F3F3))

        let blue = Color(0xFF3B6FB6)
        let mica = recipe.resolve(over: blue)
        XCTAssertEqual(mica.a, 1.0)
        // Lightness of the result is the tint's: the lum layer is at 1.0
        // and the tint over it is the same lightness again.
        XCTAssertEqual(FluentColorMath.luminosity(mica),
                       FluentColorMath.luminosity(Color(0xFFF3F3F3)), accuracy: 0.02)
        // …but it is not the flat grey: it leans blue.
        XCTAssertGreaterThan(mica.b, mica.r)
        XCTAssertNotEqual(mica, Color(0xFFF3F3F3))

        // Dark leans less (tint opacity 0.8), and is still dark.
        let dark = FluentMaterialRecipe.mica(.dark).resolve(over: blue)
        XCTAssertLessThan(FluentColorMath.luminosity(dark), 0.2)
        XCTAssertGreaterThan(dark.b, dark.r)
    }

    func testMicaWidgetColorHonoursActiveAndTransparency() {
        let blue = Color(0xFF3B6FB6)
        let live = Mica.color(kind: .base, brightness: .light, sample: blue)
        XCTAssertNotEqual(live, Color(0xFFF3F3F3))
        XCTAssertEqual(Mica.color(kind: .base, brightness: .light, sample: blue, active: false),
                       Color(0xFFF3F3F3))
        XCTAssertEqual(Mica.color(kind: .base, brightness: .light, sample: blue,
                                  transparencyEffects: false),
                       Color(0xFFF3F3F3))
        XCTAssertEqual(Mica.color(kind: .alt, brightness: .dark, sample: nil), Color(0xFF0A0A0A))
    }

    // MARK: Colour math

    func testLuminosityBlendKeepsHueTakesLightness() {
        XCTAssertEqual(FluentColorMath.luminosity(Color(0xFFFFFFFF)), 1.0, accuracy: 1e-9)
        XCTAssertEqual(FluentColorMath.luminosity(Color(0xFF000000)), 0.0, accuracy: 1e-9)

        let red = Color(0xFFFF0000)
        let lifted = FluentColorMath.setLuminosity(red, 0.5)
        XCTAssertEqual(FluentColorMath.luminosity(lifted), 0.5, accuracy: 1e-6)
        XCTAssertGreaterThan(lifted.r, lifted.g)   // still red
        XCTAssertGreaterThan(lifted.r, lifted.b)

        // Blending a light tint's luminosity onto a blue backdrop: light, blue.
        let out = FluentColorMath.luminosityBlend(source: Color(0xFFF3F3F3), backdrop: Color(0xFF3B6FB6))
        XCTAssertEqual(FluentColorMath.luminosity(out), FluentColorMath.luminosity(Color(0xFFF3F3F3)), accuracy: 1e-6)
        XCTAssertGreaterThan(out.b, out.r)
    }

    func testOverAndMix() {
        let half = Color(0xFFFFFFFF).withValues(alpha: 0.5)
        let out = FluentColorMath.over(half, Color(0xFF000000))
        XCTAssertEqual(out.r, 0.5, accuracy: 1e-6)
        XCTAssertEqual(out.a, 1.0)
        XCTAssertEqual(FluentColorMath.mix(Color(0xFF000000), Color(0xFFFFFFFF), 0.25).g, 0.25, accuracy: 1e-6)
    }

    // MARK: Surfaces read the tokens

    func testDialogAndTooltipThemesUseTokens() {
        let light = FluentThemeData.light()
        let dialog = ContentDialogThemeData.standard(light)
        XCTAssertEqual(dialog.barrierColor, light.resources.smokeFillColorDefault)
        XCTAssertEqual(dialog.barrierColor, Color(0x4D000000))
        let dec = dialog.decoration as? BoxDecoration
        XCTAssertEqual(dec?.borderRadius as? BorderRadius, FluentCorners.overlayRadius)
        XCTAssertEqual(dec?.boxShadow?.count, 2)
        XCTAssertEqual(dec?.boxShadow?[1].blurRadius, FluentElevation.dialog)

        let tip = TooltipThemeData.standard(FluentThemeData.dark())
        let tipDec = tip.decoration as? BoxDecoration
        XCTAssertEqual(tipDec?.borderRadius as? BorderRadius, FluentCorners.tooltipRadius)
        XCTAssertEqual(tipDec?.color, FluentThemeData.dark().menuColor)
        XCTAssertEqual(tipDec?.boxShadow?[1].blurRadius, FluentElevation.tooltip)
    }
}
