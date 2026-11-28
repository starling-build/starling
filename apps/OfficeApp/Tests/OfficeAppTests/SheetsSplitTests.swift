// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-RC-2: View > Split. Up to four panes, each pair of side-by-side panes sharing its rows' scroll and each pair one
// above the other sharing its columns'; the bars move with the mouse; the file keeps the split as Excel writes it.

import XCTest
@testable import OfficeApp
import Flutter
import FlutterSwiftBridge

final class SheetsSplitTests: XCTestCase {
    private func theme(_ home: Widget) -> Widget { FluentApp(theme: OfficeAppearance.theme(.light), home: home, title: "t") }

    private func open(_ book: Workbook) throws -> (WidgetTester, SheetsShellState, SheetGridState) {
        let tmp = NSTemporaryDirectory() + "split-\(ProcessInfo.processInfo.processIdentifier)-\(UInt32.random(in: 0 ... .max)).xlsx"
        try Xlsx.write(book).write(to: URL(fileURLWithPath: tmp))
        let ui = WidgetTester(theme(SheetsShell(initialPath: tmp, onSwitch: { _, _ in })), size: Size(1440, 932))
        ui.pump()
        let shell = try XCTUnwrap(ui.state(SheetsShellState.self))
        return (ui, shell, try XCTUnwrap(shell._grid))
    }

    private func numbered() -> Workbook {
        let c = WorkbookController()
        var items: [(CellAddress, String)] = []
        for r in 0 ..< 200 { for col in 0 ..< 30 { items.append((CellAddress(row: r, col: col), "\(r + 1)")) } }
        c.setInputs(items)
        return c.book
    }

    func testSplitAtTheActiveCellScrollsEachPaneOnItsOwn() throws {
        let (ui, shell, grid) = try open(numbered())
        shell.wb.select(CellAddress("D6")!); ui.pump()
        let d6 = grid.rect(CellAddress("D6")!)
        shell.wb.onCommand?(.toggleSplit); ui.pump()
        XCTAssertTrue(grid.isSplit)
        // The bars sit above and left of D6; D6 is the bottom-right pane's first cell, and that pane is active.
        XCTAssertEqual(try XCTUnwrap(grid.splitX), d6.left.rounded(), accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(grid.splitY), d6.top.rounded(), accuracy: 1)
        XCTAssertTrue(grid.pane == (1, 1))
        XCTAssertEqual(shell.wb.sheet.splitPane?["topLeftCell"], "D6")
        XCTAssertEqual(shell.wb.sheet.splitPane?["activePane"], "bottomRight")
        // The wheel over the bottom-right pane scrolls it (and the bottom-left one with it) but not the top panes.
        let farBR = grid.global(Offset(grid.size.width - 100, grid.size.height - 60))
        ui.scroll(at: farBR, delta: Offset(0, 400)); ui.pump()
        XCTAssertGreaterThan(grid.scrollY, 300)
        grid.enterPane(0, 0)
        XCTAssertEqual(grid.scrollY, 0)
        XCTAssertEqual(grid.scrollX, 0)
        grid.enterPane(0, 1)
        XCTAssertGreaterThan(grid.scrollY, 300)
        grid.enterPane(1, 1)
        // A click in the top-left pane selects the cell under it there (A1 region) and makes that pane the active one.
        let a2 = grid.rect(CellAddress("A2")!)
        grid.enterPane(0, 0)
        let a2top = grid.rect(CellAddress("A2")!)
        grid.enterPane(1, 1)
        XCTAssertNotEqual(a2.top, a2top.top)
        ui.click(at: grid.global(Offset(a2top.center.dx, a2top.center.dy))); ui.pump()
        XCTAssertEqual(shell.wb.active, CellAddress("A2")!)
        XCTAssertTrue(grid.pane == (0, 0))
        // Split again takes it away.
        shell.wb.onCommand?(.toggleSplit); ui.pump()
        XCTAssertFalse(grid.isSplit)
        XCTAssertNil(shell.wb.sheet.splitPane)
    }

    func testTheBarMovesAndLeavesAtTheEdge() throws {
        let (ui, shell, grid) = try open(numbered())
        shell.wb.select(CellAddress("C1")!); ui.pump()
        shell.wb.onCommand?(.toggleSplit); ui.pump()
        // Row 1 active: a vertical bar only.
        XCTAssertNotNil(grid.splitX)
        XCTAssertNil(grid.splitY)
        let x0 = try XCTUnwrap(grid.splitX)
        let mid = Offset(x0 + SheetGridState.splitBar / 2, 300)
        ui.drag(from: grid.global(mid), to: grid.global(Offset(mid.dx + 200, 300))); ui.pump()
        XCTAssertEqual(try XCTUnwrap(grid.splitX), x0 + 200, accuracy: 2)
        XCTAssertEqual(shell.wb.sheet.splitPane?["xSplit"], String(Int((x0 + 200) * 15)))
        // Dragged onto the row headers, the bar goes.
        let now = Offset(try XCTUnwrap(grid.splitX) + SheetGridState.splitBar / 2, 300)
        ui.drag(from: grid.global(now), to: grid.global(Offset(5, 300))); ui.pump()
        XCTAssertFalse(grid.isSplit)
    }

    func testFreezeReplacesASplit() throws {
        let (ui, shell, grid) = try open(numbered())
        shell.wb.select(CellAddress("D6")!); ui.pump()
        shell.wb.onCommand?(.toggleSplit); ui.pump()
        shell.wb.freeze(at: CellAddress("B2")!); ui.pump()
        XCTAssertFalse(grid.isSplit)
        XCTAssertNil(shell.wb.sheet.splitPane)
        XCTAssertEqual(shell.wb.sheet.freezeRows, 1)
    }

    /// A file split as Excel saves one (twentieths of a point, headers included) opens split, each pane where the
    /// file left it, and saves the split back.
    func testAFileSplitOpensSplitAndSavesIt() throws {
        let book = numbered()
        book.sheets[0].splitPane = ["xSplit": "2175", "ySplit": "1500", "topLeftCell": "E30", "activePane": "bottomRight"]
        let (ui, shell, grid) = try open(book)
        _ = ui
        XCTAssertEqual(try XCTUnwrap(grid.splitX), 145)
        XCTAssertEqual(try XCTUnwrap(grid.splitY), 100)
        XCTAssertTrue(grid.pane == (1, 1))
        XCTAssertEqual(grid.col(atLocal: try XCTUnwrap(grid.splitX) + SheetGridState.splitBar + 1), 4)
        XCTAssertEqual(grid.row(atLocal: try XCTUnwrap(grid.splitY) + SheetGridState.splitBar + 1), 29)
        let back = try Xlsx.read(Xlsx.write(shell.wb.book))
        XCTAssertEqual(back.sheets[0].splitPane?["xSplit"], "2175")
        XCTAssertEqual(back.sheets[0].splitPane?["topLeftCell"], "E30")
    }
}
