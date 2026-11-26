import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// A tooltip up when a dialog opens: the dialog rebuilds the window under it, and the ribbon's
/// drop-downs must still open after the dialog closes (the browser's control walk found them dead).
final class TooltipDialogTests: XCTestCase {
    func testARibbonMenuOpensAfterADialogOpenedUnderATooltip() throws { try run(tooltipWait: 1.3) }
    func testARibbonMenuOpensAfterADialogWithNoTooltip() throws { try run(tooltipWait: 0.1) }

    private func run(tooltipWait: Double) throws {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"),
                              size: Size(1400, 900))
        let tracker = MouseTracker({ position, _ in
            let r = HitTestResult()
            _ = ui.renderView.hitTest(r, position: position)
            return r
        })
        func settle(_ seconds: Double = 0.05) {
            let end = Date().addingTimeInterval(seconds)
            repeat { ui.pump(); tracker.updateAllDevices(); RunLoop.main.run(until: Date().addingTimeInterval(0.02)) } while Date() < end
        }
        func tip(_ message: String) throws -> Offset {
            let e = try XCTUnwrap(ui.elements().first { ($0.widget as? Tooltip)?.message == message }, message)
            let box = try XCTUnwrap(e.findRenderObject() as? RenderBox)
            return box.localToGlobal(Offset(box.size.width / 2, box.size.height / 2))
        }
        func hover(_ p: Offset) { tracker.updateWithEvent(PointerHoverEvent(kind: .mouse, position: p), hitTestResult: nil) }
        settle()
        // The pointer rests on a button until its tooltip shows, then moves to Font… and clicks it.
        hover(try tip("Clear All Formatting")); settle(tooltipWait)
        let font = try tip("Font… (⌘D)")
        hover(font); settle(0.1)
        ui.click(at: font, kind: .mouse); settle(0.3)
        XCTAssertTrue(ui.texts().contains("Font"), "the Font dialog is open")
        ui.press(.escape); settle(0.3)
        let bullets = try tip("Bullet Library")
        hover(bullets); settle(0.1)
        ui.click(at: bullets, kind: .mouse); settle(0.3)
        XCTAssertTrue(ui.texts().contains("Define New Bullet…"), "the Bullet Library drop-down opens")
    }
}

final class MoreColorsTests: XCTestCase {
    /// Font Color → More Colors… opens the colour strip (the browser's walk found it trapping).
    func testMoreColorsOpensTheColourStrip() throws {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"),
                              size: Size(1400, 900))
        func settle() { for _ in 0..<5 { ui.pump(); RunLoop.main.run(until: Date().addingTimeInterval(0.02)) } }
        settle()
        ui.tap(tip: "Font Color"); settle()
        ui.tap(text: "More Colors…"); settle()
        XCTAssertTrue(ui.texts().contains("Standard Colors"))
    }

    /// The web build is wasm32, where Int is 32 bits: `Color(Int(0xFF…))` (any opaque colour
    /// computed as an unsigned number) traps there and crashed More Colors…. Native's 64-bit Int
    /// never shows it, so this checks the source: build such colours with `Color(Int64(…))`.
    func testNoOpaqueColourGoesThroughA32BitInt() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        var hits: [String] = []
        for case let url as URL in files where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            for (n, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            where line.contains("Color(Int(0xFF") || line.contains("Color(Int(0xff") {
                hits.append("\(url.lastPathComponent):\(n + 1)")
            }
        }
        XCTAssertEqual(hits, [], "Color(Int(0xFF…)) traps on wasm32; use Color(Int64(…))")
        XCTAssertEqual(ColorBar.theme.count, 6)
        XCTAssertEqual(ColorBar.theme[0][4].value, 0xFF4472C4)
    }
}
