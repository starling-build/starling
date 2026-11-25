// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// A finger on a chart that is not selected scrolls the sheet (a tap selects it); only a drag on a selected one moves it,
// as in Writer and Slides. A mouse keeps pressing and dragging at once.

import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

final class SheetsTouchDrawingTests: XCTestCase {
    /// A sheet with a chart on it, nothing selected, and a window point on the chart.
    private func shell() throws -> (WidgetTester, WorkbookController, Offset) {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SheetsShell(initialPath: nil, onSwitch: { _, _ in }), title: "Test"),
                              size: Size(1280, 800))
        let wb = try XCTUnwrap(ui.state(SheetsShellState.self)).wb
        let rows = [["Month", "Sales", "Costs"], ["Jan", "10", "4"], ["Feb", "20", "8"], ["Mar", "15", "9"]]
        var items: [(CellAddress, String)] = []
        for (r, row) in rows.enumerated() { for (c, v) in row.enumerated() { items.append((CellAddress(row: r, col: c), v)) } }
        wb.setInputs(items)
        wb.select(CellAddress("B2")!)
        XCTAssertTrue(wb.insertChart(.column))
        ui.pump()
        // The window point is found with a mouse: the first point on a 20 pt lattice that selects the chart.
        wb.select(CellAddress("A20")!)
        XCTAssertNil(wb.selectedDrawing)
        var found: Offset?
        search: for y in stride(from: 60.0, to: 760, by: 10) {
            for x in stride(from: 40.0, to: 1260, by: 10) {
                ui.tap(at: Offset(x, y), kind: .mouse)
                if wb.selectedDrawing != nil { found = Offset(x + 40, y + 40); break search }
            }
        }
        let point = try XCTUnwrap(found, "the chart is somewhere in the window")
        wb.select(CellAddress("A20")!)
        XCTAssertNil(wb.selectedDrawing)
        return (ui, wb, point)
    }

    private func origin(_ wb: WorkbookController) -> (x: Double, y: Double) {
        let f = wb.sheet.frame(wb.sheet.drawings[0].anchor)
        return (f.x, f.y)
    }

    func testTheRuleItself() {
        XCTAssertTrue(SheetGridState.drawingPressDrags(touch: false, wasSelected: false))
        XCTAssertFalse(SheetGridState.drawingPressDrags(touch: true, wasSelected: false))
        XCTAssertTrue(SheetGridState.drawingPressDrags(touch: true, wasSelected: true))
    }

    func testAFingerDragOnAnUnselectedChartDoesNotMoveOrSelectIt() throws {
        let (ui, wb, p) = try shell()
        let before = origin(wb)
        ui.drag(from: p, to: Offset(p.dx + 60, p.dy + 40), steps: 6, kind: .touch)
        XCTAssertNil(wb.selectedDrawing, "a drag scrolls; it does not select the chart")
        XCTAssertEqual(origin(wb).x, before.x, accuracy: 0.001)
        XCTAssertEqual(origin(wb).y, before.y, accuracy: 0.001)
    }

    func testATapSelectsItAndThenADragMovesIt() throws {
        let (ui, wb, p) = try shell()
        ui.tap(at: p, kind: .touch)
        XCTAssertEqual(wb.selectedDrawing, 0)
        let before = origin(wb)
        ui.drag(from: p, to: Offset(p.dx + 60, p.dy + 40), steps: 6, kind: .touch)
        XCTAssertGreaterThan(origin(wb).x, before.x + 30, "a selected chart follows the finger")
        XCTAssertGreaterThan(origin(wb).y, before.y + 20)
    }

    func testAMouseDragMovesAnUnselectedChartAtOnce() throws {
        let (ui, wb, p) = try shell()
        let before = origin(wb)
        ui.drag(from: p, to: Offset(p.dx + 60, p.dy + 40), steps: 6, kind: .mouse)
        XCTAssertEqual(wb.selectedDrawing, 0)
        XCTAssertGreaterThan(origin(wb).x, before.x + 30)
    }
}
