// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-FM-6: Format Painter in Sheets.

import XCTest
@testable import OfficeApp
import Flutter
import FlutterSwiftBridge

final class SheetsFormatPainterTests: XCTestCase {
    private func a(_ s: String) -> CellAddress { CellAddress(s)! }

    private func book() -> WorkbookController {
        let c = WorkbookController()
        c.load(Workbook(sheets: [Worksheet(name: "S")]))
        c.setInputs([(a("A1"), "head"), (a("A2"), "body"), (a("C1"), "keep me"), (a("C2"), "2")])
        c.select(range: CellRange(a("A1"), a("A1")))
        c.setStyle { $0.bold = true }
        c.select(range: CellRange(a("A2"), a("A2")))
        c.setStyle { $0.italic = true }
        return c
    }

    func testOneCellTakesTheSourcesSizeAndKeepsValues() {
        let c = book()
        c.select(range: CellRange(a("A1"), a("A2")))
        c.armFormatPainter()
        c.select(a("C1"))
        c.applyFormatPainter()
        XCTAssertTrue(c.style(at: a("C1")).bold)
        XCTAssertTrue(c.style(at: a("C2")).italic)
        XCTAssertEqual(c.input(a("C1")), "keep me")
        XCTAssertNil(c.painterSource)
    }

    func testBiggerSelectionRepeatsThePattern() {
        let c = book()
        c.select(range: CellRange(a("A1"), a("A2")))
        c.armFormatPainter()
        c.select(range: CellRange(a("E1"), a("E5")))
        c.applyFormatPainter()
        XCTAssertTrue(c.style(at: a("E1")).bold); XCTAssertTrue(c.style(at: a("E3")).bold)
        XCTAssertTrue(c.style(at: a("E2")).italic); XCTAssertTrue(c.style(at: a("E4")).italic)
        XCTAssertTrue(c.style(at: a("E5")).bold)
    }

    func testPlainSourceClearsFormatsAndUndoes() {
        let c = book()
        c.select(a("H1")); c.armFormatPainter()
        c.select(a("A1")); c.applyFormatPainter()
        XCTAssertFalse(c.style(at: a("A1")).bold)
        XCTAssertEqual(c.input(a("A1")), "head")
        c.undo()
        XCTAssertTrue(c.style(at: a("A1")).bold)
    }

    func testCancelPutsItDown() {
        let c = book()
        c.armFormatPainter(); XCTAssertNotNil(c.painterSource)
        c.cancelFormatPainter(); XCTAssertNil(c.painterSource)
    }

    func testRibbonButtonArmsIt() {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SheetsShell(initialPath: nil, onSwitch: { _, _ in }), title: "t"),
                              size: Size(1280, 800))
        ui.pump()
        let st = ui.state(SheetsShellState.self)!
        XCTAssertTrue(ui.tap(text: "Format Painter")); ui.pump()
        XCTAssertNotNil(st.wb.painterSource)
        XCTAssertTrue(ui.tap(text: "Painter: pick cells")); ui.pump()
        XCTAssertNil(st.wb.painterSource)
    }
}
