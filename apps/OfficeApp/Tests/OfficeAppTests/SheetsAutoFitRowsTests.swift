// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// X-AF-1: a row nobody sized grows for larger type and turned text; a row
/// with a set height keeps it.
final class SheetsAutoFitRowsTests: XCTestCase {
    /// The shell's own grid, driven through a shell whose workbook is `c`.
    private func rowHeight(_ c: WorkbookController, _ row: Int) -> Double {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: SizedBox(width: 800, height: 600, child: SheetGrid(
            controller: c, zoom: 1, onEditText: { _ in }, onShortcut: { _, _ in false }, onStatus: { _ in })), title: "T"),
            size: Size(800, 600))
        defer { ui.replace(with: SizedBox(width: 1, height: 1)) }
        return ui.state(SheetGridState.self)?.rows.size(row) ?? -1
    }

    func testLargerFontGrowsUnsizedRowOnly() {
        let c = WorkbookController()
        c.setInput("Big", at: CellAddress(row: 0, col: 0))
        c.setInput("Big", at: CellAddress(row: 1, col: 0))
        let plain = rowHeight(c, 5)
        c.select(range: CellRange("A1:A2")!)
        c.setStyle({ $0.fontSize = 28 })
        c.sheet.rowHeights[1] = plain * 0.75        // row 2 has a set height
        XCTAssertGreaterThan(rowHeight(c, 0), plain + 8)
        XCTAssertEqual(rowHeight(c, 1), plain, accuracy: 0.01)
    }

    func testTurnedTextGrowsRow() {
        let c = WorkbookController()
        c.setInput("A long heading", at: CellAddress(row: 0, col: 0))
        let plain = rowHeight(c, 5)
        c.select(range: CellRange("A1")!)
        c.setStyle({ $0.rotation = 90 })
        XCTAssertGreaterThan(rowHeight(c, 0), plain * 2)
    }

    /// The printed page fits turned text too, so screen and PDF agree.
    func testPrintGrowsTurnedTextRowAndKeepsSetHeight() {
        let c = WorkbookController()
        c.setInput("A long heading", at: CellAddress(row: 0, col: 0))
        c.setInput("A long heading", at: CellAddress(row: 1, col: 0))
        c.select(range: CellRange("A1:A2")!)
        c.setStyle({ $0.rotation = 90 })
        c.sheet.rowHeights[1] = 20
        let g = SheetGridState(headless: c)
        g.printing = true
        XCTAssertGreaterThan(g.rows.size(0), 60)
        XCTAssertEqual(g.rows.size(1), 20, accuracy: 0.5)
        XCTAssertLessThan(g.rows.size(5), 20)
    }
}
