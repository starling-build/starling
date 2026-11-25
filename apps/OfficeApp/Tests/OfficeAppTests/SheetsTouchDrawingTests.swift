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

    /// Two charts apart on the sheet, nothing selected, and a window point on each (by drawing index).
    private func twoCharts() throws -> (WidgetTester, WorkbookController, [Int: Offset]) {
        let (ui, wb, _) = try shell()
        wb.select(CellAddress("B2")!)
        XCTAssertTrue(wb.insertChart(.line))
        XCTAssertEqual(wb.sheet.drawings.count, 2)
        let f = wb.sheet.frame(wb.sheet.drawings[0].anchor)
        wb.setDrawingFrame(1, x: f.x + f.width + 40, y: f.y, width: f.width, height: f.height)
        wb.select(CellAddress("A30")!)
        ui.pump()
        var found: [Int: Offset] = [:]
        search: for y in stride(from: 300.0, to: 760, by: 10) {
            for x in stride(from: 40.0, to: 1260, by: 10) {
                wb.select(CellAddress("A30")!)
                ui.tap(at: Offset(x, y), kind: .mouse)
                if let d = wb.selectedDrawing, found[d] == nil { found[d] = Offset(x + 40, y + 40) }
                if found.count == 2 { break search }
            }
        }
        wb.select(CellAddress("A30")!)
        XCTAssertEqual(Set(found.keys), [0, 1], "both charts are in the window")
        return (ui, wb, found)
    }

    /// Select Multiple: with a chart selected, a finger's tap on another picks it (a second tap drops it); the group moves and
    /// is deleted together, each as one undo step. With it off, the same tap just selects the other chart.
    func testSelectMultipleLetsAFingerPickChartsAndMoveThemTogether() throws {
        let (ui, wb, at) = try twoCharts()
        ui.tap(at: at[0]!, kind: .touch)
        XCTAssertEqual(wb.selectedDrawingIndexes, [0])
        ui.tap(at: at[1]!, kind: .touch)
        XCTAssertEqual(wb.selectedDrawingIndexes, [1], "off: a tap selects the other one alone")
        ui.tap(at: at[0]!, kind: .touch)
        XCTAssertEqual(wb.selectedDrawingIndexes, [0])
        wb.selectMultiple = true
        ui.tap(at: at[1]!, kind: .touch)
        XCTAssertEqual(wb.selectedDrawingIndexes, [0, 1], "on: a tap picks it along with the first")
        ui.tap(at: at[1]!, kind: .touch)
        XCTAssertEqual(wb.selectedDrawingIndexes, [0], "a second tap drops it again")
        ui.tap(at: at[1]!, kind: .touch)
        XCTAssertEqual(wb.selectedDrawingIndexes, [0, 1])
        // A drag on the main one moves both, in one undo step.
        let f0 = wb.sheet.frame(wb.sheet.drawings[0].anchor), f1 = wb.sheet.frame(wb.sheet.drawings[1].anchor)
        ui.drag(from: at[0]!, to: Offset(at[0]!.dx + 30, at[0]!.dy + 50), steps: 6, kind: .touch)
        let g0 = wb.sheet.frame(wb.sheet.drawings[0].anchor), g1 = wb.sheet.frame(wb.sheet.drawings[1].anchor)
        XCTAssertGreaterThan(g0.x - f0.x, 15, "the main one follows the finger")
        XCTAssertEqual(g1.x - f1.x, g0.x - f0.x, accuracy: 0.5, "the other travels the same distance")
        XCTAssertEqual(g1.y - f1.y, g0.y - f0.y, accuracy: 0.5)
        XCTAssertEqual(wb.selectedDrawingIndexes, [0, 1])
        wb.undo()
        XCTAssertEqual(wb.sheet.frame(wb.sheet.drawings[0].anchor).x, f0.x, accuracy: 0.5)
        XCTAssertEqual(wb.sheet.frame(wb.sheet.drawings[1].anchor).x, f1.x, accuracy: 0.5)
        // Delete takes both away in one step.
        wb.deleteSelectedDrawings()
        XCTAssertTrue(wb.sheet.drawings.isEmpty)
        wb.undo()
        XCTAssertEqual(wb.sheet.drawings.count, 2)
    }

    /// A finger drag that starts on an unselected chart still scrolls with Select Multiple on; the tap that never moved picks it.
    func testSelectMultipleKeepsAFingerDragScrolling() throws {
        let (ui, wb, at) = try twoCharts()
        ui.tap(at: at[0]!, kind: .touch)
        wb.selectMultiple = true
        let before = wb.sheet.frame(wb.sheet.drawings[1].anchor)
        ui.drag(from: at[1]!, to: Offset(at[1]!.dx + 40, at[1]!.dy + 30), steps: 6, kind: .touch)
        XCTAssertEqual(wb.selectedDrawingIndexes, [0], "a drag picked nothing")
        XCTAssertEqual(wb.sheet.frame(wb.sheet.drawings[1].anchor).x, before.x, accuracy: 0.001, "and moved nothing")
    }
}
