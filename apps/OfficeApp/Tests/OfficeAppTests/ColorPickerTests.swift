import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

final class ColorPickerTests: XCTestCase {
    func testTintsMatchWordsOwnTheme() {
        // Values Word shows for the Office theme. Exact where our arithmetic agrees; Word's own rounding differs
        // by one step in a channel for a few (Accent 1 lighter 80 is D9E2F3 there; Text 1 lighter 50 is 7F7F7F),
        // which only moves the drawn swatch: the file keeps the theme link, not these numbers.
        func close(_ a: UInt32, _ b: UInt32, _ line: UInt = #line) {
            for s in [16, 8, 0] as [UInt32] { XCTAssertLessThanOrEqual(abs(Int((a >> s) & 255) - Int((b >> s) & 255)), 1, line: line) }
        }
        XCTAssertEqual(ColorMath.adjusted(0x4472C4, lumMod: 75, lumOff: 0), 0x2F5597)
        XCTAssertEqual(ColorMath.adjusted(0x4472C4, lumMod: 50, lumOff: 0), 0x203864)
        XCTAssertEqual(ColorMath.adjusted(0xED7D31, lumMod: 20, lumOff: 80), 0xFBE5D6)
        XCTAssertEqual(ColorMath.adjusted(0xED7D31, lumMod: 75, lumOff: 0), 0xC55A11)
        XCTAssertEqual(ColorMath.adjusted(0xFFFFFF, lumMod: 85, lumOff: 0), 0xD9D9D9)
        XCTAssertEqual(ColorMath.adjusted(0xFFC000, lumMod: 40, lumOff: 60), 0xFFE699)
        XCTAssertEqual(ColorMath.adjusted(0x5B9BD5, lumMod: 20, lumOff: 80), 0xDEEBF7)
        close(ColorMath.adjusted(0x4472C4, lumMod: 20, lumOff: 80), 0xD9E2F3)
        close(ColorMath.adjusted(0x000000, lumMod: 50, lumOff: 50), 0x7F7F7F)
        close(ColorMath.adjusted(0x70AD47, lumMod: 50, lumOff: 0), 0x375623)
    }

    func testAThemeChoiceKeepsItsLinkAndResolvesAgainstAnyTheme() {
        let c = ColorChoice.theme(slot: 4, lumMod: 20, lumOff: 80)
        XCTAssertEqual(c.resolved(theme: ColorMath.officeTheme), ColorMath.adjusted(0x4472C4, lumMod: 20, lumOff: 80))
        var other = ColorMath.officeTheme; other[4] = 0xFF0000
        XCTAssertNotEqual(c.resolved(theme: other), c.resolved(theme: ColorMath.officeTheme))
        XCTAssertNil(ColorChoice.automatic.resolved(theme: other))
    }

    func testHexParsingAndRecentList() {
        XCTAssertEqual(ColorMath.parseHex("#1a2B3c"), 0x1A2B3C)
        XCTAssertEqual(ColorMath.parseHex("f00"), 0xFF0000)
        XCTAssertNil(ColorMath.parseHex("12345"))
        XCTAssertEqual(ColorMath.hex(0x0A0B0C), "#0A0B0C")
        var r = RecentColors(limit: 3)
        for c: UInt32 in [1, 2, 3, 2, 4] { r.use(c) }
        XCTAssertEqual(r.list, [4, 2, 3])
    }

    private func picker(_ got: @escaping (ColorChoice) -> Void, more: @escaping () -> Void = {}) -> WidgetTester {
        WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: Center(child: ColorPicker(
            recent: [0x123456], automaticLabel: "Automatic", noneLabel: "No Color", onChoose: got, onMore: more)), title: "T"), size: Size(1280, 800))
    }

    func testThePickerChoosesThemeStandardRecentAndSpecial() {
        var got: ColorChoice?
        var more = 0
        let ui = picker({ got = $0 }, more: { more += 1 })
        ui.tap(tip: "Accent 1, Lighter 80%")
        XCTAssertEqual(got, .theme(slot: 4, lumMod: 20, lumOff: 80))
        ui.tap(tip: "Red")
        XCTAssertEqual(got, .rgb(0xFF0000))
        ui.tap(tip: "#123456")
        XCTAssertEqual(got, .rgb(0x123456))
        ui.tap(text: "Automatic"); XCTAssertEqual(got, .automatic)
        ui.tap(text: "No Color"); XCTAssertEqual(got, ColorChoice.none)
        ui.tap(text: "More Colors…"); XCTAssertEqual(more, 1)
    }

    func testTheCustomDialogKeepsHexAndChannelsInStep() {
        var got: UInt32?
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: CustomColorDialog(
            initial: 0x102030, onOK: { got = $0 }, onCancel: {}), title: "T"), size: Size(1280, 800))
        XCTAssertTrue(ui.texts().contains("More Colors"))
        func box(_ i: Int) -> RenderBox {
            ui.elements().filter { $0.widget is FluentTextBox }[i].findRenderObject() as! RenderBox
        }
        let b = box(2) // Green
        ui.tap(at: b.localToGlobal(Offset(b.size.width / 2, b.size.height / 2)))
        for _ in 0..<4 { ui.press(.backspace) }
        ui.type("255")
        XCTAssertEqual(ui.state(CustomColorDialogState.self)?.rgb, 0x10FF30)
        ui.tap(text: "OK")
        XCTAssertEqual(got, 0x10FF30)
    }

    func testASixDigitHexTypedInTheCustomDialogIsKeptWhole() {
        var got: UInt32?
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: CustomColorDialog(
            initial: 0xFFFFFF, onOK: { got = $0 }, onCancel: {}), title: "T"), size: Size(1280, 800))
        let b = ui.elements().filter { $0.widget is FluentTextBox }[0].findRenderObject() as! RenderBox
        ui.tap(at: b.localToGlobal(Offset(b.size.width / 2, b.size.height / 2)))
        for _ in 0..<8 { ui.press(.backspace) }
        ui.type("12AB34")   // "12A" alone is the short form #1122AA; the field must not be rewritten to it
        XCTAssertEqual(ui.state(CustomColorDialogState.self)?.rgb, 0x12AB34)
        ui.tap(text: "OK")
        XCTAssertEqual(got, 0x12AB34)
    }
}
