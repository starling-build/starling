import XCTest
@testable import OfficeApp
import Flutter
import FlutterSwiftBridge

/// Tertiary text (3.3:1 in light) and the accent as TEXT (4.1:1 light, 3.6:1 dark) are Fluent's own and fail AA: the desktop shell
/// raises its tertiary text in ShellTheme.fluent, and the accent is only drawn as a fill or an icon (3:1).
/// WCAG 2.x AA over the Fluent tokens the chrome is drawn with: text 4.5:1, icons and control edges 3:1.
final class ContrastAuditTests: XCTestCase {
    static func ratio(_ fg: Color, _ bg: Color) -> Double {
        let f = Color.alphaBlend(foreground: fg, background: bg)
        let a = f.computeLuminance() + 0.05, b = bg.computeLuminance() + 0.05
        return max(a, b) / min(a, b)
    }

    func audit() -> [(String, Double, Double)] {
        var out: [(String, Double, Double)] = []
        for (mode, t) in [("light", FluentThemeData.light()), ("dark", FluentThemeData.dark())] {
            let r = t.resources
            let surfaces: [(String, Color)] = [("base", r.solidBackgroundFillColorBase), ("secondary", r.solidBackgroundFillColorSecondary), ("tertiary", r.solidBackgroundFillColorTertiary)]
            for (sn, bg) in surfaces {
                out.append(("\(mode) primary text on \(sn)", Self.ratio(r.textFillColorPrimary, bg), 4.5))
                out.append(("\(mode) secondary text on \(sn)", Self.ratio(r.textFillColorSecondary, bg), 4.5))
                out.append(("\(mode) strong control edge on \(sn)", Self.ratio(r.controlStrongStrokeColorDefault, bg), 3))
                out.append(("\(mode) secondary icon on \(sn)", Self.ratio(r.textFillColorSecondary, bg), 3))
            }
            let field = Color.alphaBlend(foreground: r.controlFillColorDefault, background: r.solidBackgroundFillColorBase)
            out.append(("\(mode) text in a control", Self.ratio(r.textFillColorPrimary, field), 4.5))
            out.append(("\(mode) text on accent button", Self.ratio(r.textOnAccentFillColorPrimary, t.accentColor.normal), 4.5))
        }
        return out
    }

    func testAccentAsIconMeetsThreeToOne() {
        for t in [FluentThemeData.light(), FluentThemeData.dark()] {
            XCTAssertGreaterThanOrEqual(Self.ratio(t.accentColor.normal, t.resources.solidBackgroundFillColorBase), 3)
        }
    }

    func testChromeTokensMeetWCAGAA() {
        var bad: [String] = []
        for (name, got, want) in audit() where got < want { bad.append("\(name): \(String(Int(got * 100)))/100 < \(want)") }
        XCTAssertEqual(bad, [])
    }
}

/// The chrome follows the system's text size, Increase Contrast and Bold Text settings.
final class SystemDisplayChromeTests: XCTestCase {
    override func tearDown() { SystemDisplay.resetForTesting(); super.tearDown() }

    func testTextSizeScalesTheChromeUpToItsCap() {
        let big = OfficeAppearance.theme(.light, display: DisplaySettings(textScale: 1.2))
        XCTAssertEqual(big.typography.body?.fontSize ?? 0, 13 * 1.2, accuracy: 0.001)
        let huge = OfficeAppearance.theme(.light, display: DisplaySettings(textScale: 5))
        XCTAssertEqual(huge.typography.body?.fontSize ?? 0, 13 * DisplaySettings.maxChromeTextScale, accuracy: 0.001)
        // A fixed row grows with the text, so it never clips it.
        XCTAssertEqual(OfficeAppearance.rowHeight(30, display: DisplaySettings(textScale: 2)), 60, accuracy: 0.001)
        XCTAssertEqual(OfficeAppearance.rowHeight(30, display: DisplaySettings(textScale: 0.8)), 30, accuracy: 0.001)
        let small = OfficeAppearance.theme(.light, display: DisplaySettings(textScale: 0.8))
        XCTAssertEqual(small.typography.body?.fontSize ?? 0, 13, accuracy: 0.001)
    }

    func testIncreasedContrastGivesSevenToOneTextAndThreeToOneEdges() {
        SystemDisplay.update(DisplaySettings(increasedContrast: true))
        for b in [Brightness.light, .dark] {
            let t = OfficeAppearance.theme(b)
            let surface = OfficeAppearance.surface(t)
            XCTAssertGreaterThanOrEqual(ContrastAuditTests.ratio(OfficeAppearance.ink(t), surface), 7)
            XCTAssertGreaterThanOrEqual(ContrastAuditTests.ratio(OfficeAppearance.secondary(t), surface), 7)
            XCTAssertGreaterThanOrEqual(ContrastAuditTests.ratio(OfficeAppearance.border(t), surface), 3)
            XCTAssertGreaterThanOrEqual(ContrastAuditTests.ratio(OfficeAppearance.border(t), OfficeAppearance.canvas(t)), 3)
        }
    }

    func testBoldTextAndChangeNotification() {
        var fired = 0
        SystemDisplay.onChange = { fired += 1 }
        SystemDisplay.update(DisplaySettings(boldText: true))
        SystemDisplay.update(DisplaySettings(boldText: true))
        XCTAssertEqual(fired, 1)
        XCTAssertEqual(OfficeAppearance.theme(.light).typography.body?.fontWeight, .w700)
    }
}
