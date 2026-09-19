// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import Flutter
import FlutterSwiftBridge

final class StarlingPaletteTests: XCTestCase {
    func testCitySurfacesAndInkAreOpaque() {
        let p = StarlingPalette.city
        for color in [p.canvas, p.sidebar, p.surface, p.fieldFill,
                      p.textPrimary, p.textSecondary, p.accent, p.accentInk] {
            XCTAssertEqual(color.a, 1)
        }
        XCTAssertFalse(p.isDark)
        XCTAssertEqual(p.canvas, Color(0xFFE8DFC9))
        XCTAssertEqual(p.accent, Color(0xFF52766A))
    }

    func testCityTextContrast() {
        func luminance(_ c: Color) -> Double {
            func linear(_ v: Double) -> Double {
                v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
        }
        func contrast(_ a: Color, _ b: Color) -> Double {
            let x = luminance(a), y = luminance(b)
            return (max(x, y) + 0.05) / (min(x, y) + 0.05)
        }
        let p = StarlingPalette.city
        XCTAssertGreaterThanOrEqual(contrast(p.textPrimary, p.canvas), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(p.textSecondary, p.sidebar), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(p.accentInk, p.accent), 4.5)
    }

    func testCityThemeCarriesThePalette() {
        let p = StarlingPalette.city
        let t = p.macosTheme()
        XCTAssertEqual(t.brightness, .light)
        XCTAssertEqual(t.canvasColor, p.canvas)
        XCTAssertEqual(t.primaryColor, p.accent)
        XCTAssertEqual(t.dividerColor, p.hairline)
        XCTAssertEqual(t.pushButtonTheme.color, p.accent)
        XCTAssertEqual(t.pushButtonTheme.secondaryColor, p.surface)
        XCTAssertEqual(t.typography.body.color, p.textPrimary)
    }

    func testFlatPalettesRemainSeparate() {
        XCTAssertTrue(StarlingPalette.macos(dark: true).isDark)
        XCTAssertFalse(StarlingPalette.macos(dark: false).isDark)
        XCTAssertEqual(StarlingPalette.macos(dark: false).accent, Color(0xFF007AFF))
        XCTAssertNotEqual(StarlingPalette.macos(dark: false).canvas, StarlingPalette.city.canvas)
    }
}
