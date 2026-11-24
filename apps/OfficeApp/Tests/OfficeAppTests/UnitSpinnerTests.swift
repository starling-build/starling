import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

final class UnitSpinnerTests: XCTestCase {
    func testParseConvertsBetweenUnits() {
        XCTAssertEqual(LengthUnit.parse("1", default: .inch)!, 72, accuracy: 1e-9)
        XCTAssertEqual(LengthUnit.parse("2.54 cm", default: .inch)!, 72, accuracy: 1e-9)
        XCTAssertEqual(LengthUnit.parse("1,5cm", default: .pt)!, 1.5 * 72 / 2.54, accuracy: 1e-9)
        XCTAssertEqual(LengthUnit.parse("12 pt", default: .cm)!, 12, accuracy: 1e-9)
        XCTAssertEqual(LengthUnit.parse("2\"", default: .cm)!, 144, accuracy: 1e-9)
        XCTAssertEqual(LengthUnit.parse("1.5 lines", default: .pt, lineHeight: 14)!, 21, accuracy: 1e-9)
        XCTAssertEqual(LengthUnit.parse("96 px", default: .pt)!, 72, accuracy: 1e-9)
        XCTAssertNil(LengthUnit.parse("abc", default: .pt))
        XCTAssertNil(LengthUnit.parse("3 furlongs", default: .pt))
        XCTAssertNil(LengthUnit.parse("", default: .pt))
    }

    func testFormatRoundsAndDropsTrailingZeros() {
        XCTAssertEqual(LengthUnit.inch.format(points: 72), "1 in")
        XCTAssertEqual(LengthUnit.inch.format(points: 90), "1.25 in")
        XCTAssertEqual(LengthUnit.cm.format(points: 72), "2.54 cm")
        XCTAssertEqual(LengthUnit.line.format(points: 18, lineHeight: 12), "1.5 li")
    }

    func testSteppingClampsAndDoesNotDrift() {
        var v = 0.0
        for _ in 0..<10 { v = LengthUnit.inch.stepped(points: v, up: true, min: 0, max: 1000) }
        XCTAssertEqual(v, 72, accuracy: 1e-9, "ten steps of 0.1 in is exactly 1 in")
        XCTAssertEqual(LengthUnit.pt.stepped(points: 0.4, up: false, min: 0, max: 100), 0)
        XCTAssertEqual(LengthUnit.pt.stepped(points: 99.5, up: true, min: 0, max: 100), 100)
    }

    private func spinner(_ value: Double, _ unit: LengthUnit, _ got: @escaping (Double) -> Void) -> WidgetTester {
        WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: Center(child: UnitSpinner(points: value, unit: unit, onChanged: got)), title: "T"), size: Size(600, 300))
    }

    func testButtonsStepTheValue() {
        var got = 72.0
        let ui = spinner(72, .inch) { got = $0 }
        XCTAssertTrue(ui.has(text: "1 in") || ui.has(tip: "Increase"))
        ui.tap(tip: "Increase")
        XCTAssertEqual(got, 79.2, accuracy: 1e-9)
        ui.tap(tip: "Decrease")
        XCTAssertEqual(got, 64.8, accuracy: 1e-9)
    }

    func testTypedValueInAnotherUnitIsConverted() {
        var got = 0.0
        let ui = spinner(72, .inch) { got = $0 }
        let box = ui.elements().first { $0.widget is FluentTextBox }!
        let r = box.findRenderObject() as! RenderBox
        ui.tap(at: r.localToGlobal(Offset(r.size.width / 2, r.size.height / 2)))
        for _ in 0..<10 { ui.press(.backspace) }
        ui.type("2.54 cm")
        ui.press(.enter)
        XCTAssertEqual(got, 72, accuracy: 1e-9)
    }
}
