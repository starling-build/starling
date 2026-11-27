import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// X-FM-4: Home > Merge menu (Merge & Center, Merge Across, Merge Cells,
/// Unmerge Cells) and Increase / Decrease Indent.
final class SheetsMergeMenuTests: XCTestCase {
    private func book() -> WorkbookController {
        let c = WorkbookController()
        for (a, v) in [("A1", "Name"), ("B1", "x"), ("A2", "Two"), ("C2", "y"), ("A3", "Three")] {
            c.setInput(v, at: CellAddress(a)!)
        }
        return c
    }
    private func r(_ s: String) -> CellRange {
        let p = s.split(separator: ":").map { CellAddress(String($0))! }
        return CellRange(top: p[0].row, left: p[0].col, bottom: p[1].row, right: p[1].col)
    }
    private func text(_ c: WorkbookController, _ a: String) -> String? { c.sheet.cells[CellAddress(a)!]?.input }

    func testMergeAcrossMergesEachRowAndKeepsEachRowsFirstValue() {
        let c = book()
        c.select(range: r("A1:C3"))
        c.merge(.across)
        XCTAssertEqual(c.sheet.merges.sorted { $0.top < $1.top }, [r("A1:C1"), r("A2:C2"), r("A3:C3")])
        XCTAssertEqual(text(c, "A1"), "Name")
        XCTAssertNil(text(c, "B1"))
        XCTAssertNil(text(c, "C2"))
        XCTAssertEqual(c.book.style(c.sheet.cells[CellAddress("A1")!]!.style).hAlign, .general)  // not centred
        c.undo()                                                                                     // one step
        XCTAssertTrue(c.sheet.merges.isEmpty)
        XCTAssertEqual(text(c, "B1"), "x")
        XCTAssertEqual(text(c, "C2"), "y")
    }

    func testMergeAcrossOneColumnDoesNothing() {
        let c = book()
        c.select(range: r("A1:A3"))
        c.merge(.across)
        XCTAssertTrue(c.sheet.merges.isEmpty)
        XCTAssertEqual(text(c, "A2"), "Two")
    }

    func testMergeCellsLeavesAlignmentAndMergeCenterCentres() {
        let c = book()
        c.select(range: r("A1:B2"))
        c.merge(.cells)
        XCTAssertEqual(c.sheet.merges, [r("A1:B2")])
        XCTAssertEqual(c.book.style(c.sheet.cells[CellAddress("A1")!]!.style).hAlign, .general)
        c.select(range: r("A3:C3"))
        c.merge(.center)
        XCTAssertEqual(c.book.style(c.sheet.cells[CellAddress("A3")!]!.style).hAlign, .center)
        XCTAssertEqual(c.sheet.merges.count, 2)
    }

    func testUnmergeTakesEveryMergeTheSelectionTouchesInOneStep() {
        let c = book()
        c.select(range: r("A1:C2"))
        c.merge(.across)
        c.select(range: r("B2:B3"))
        c.unmerge()
        XCTAssertEqual(c.sheet.merges, [r("A1:C1")])
        c.undo()
        XCTAssertEqual(c.sheet.merges.count, 2)
    }

    func testToggleUnmergesWhenTheSelectionStartsInAMerge() {
        let c = book()
        c.select(range: r("A1:C1"))
        c.toggleMerge()
        XCTAssertEqual(c.sheet.merges, [r("A1:C1")])
        c.select(range: r("A1:C3"))
        c.toggleMerge()
        XCTAssertTrue(c.sheet.merges.isEmpty)
    }

    func testIndentButtons() {
        let c = book()
        c.select(range: r("A1:A2"))
        c.indent(by: 1)
        c.indent(by: 1)
        let st = c.book.style(c.sheet.cells[CellAddress("A2")!]!.style)
        XCTAssertEqual(st.indent, 2)
        XCTAssertEqual(st.hAlign, .left)
        c.undo()
        XCTAssertEqual(c.book.style(c.sheet.cells[CellAddress("A2")!]!.style).indent, 1)
        c.select(CellAddress("A3")!)
        c.toggleAlign(.right)
        c.indent(by: 1)
        XCTAssertEqual(c.book.style(c.sheet.cells[CellAddress("A3")!]!.style).hAlign, .right)
        c.indent(by: -5)
        XCTAssertEqual(c.book.style(c.sheet.cells[CellAddress("A3")!]!.style).indent, 0)
    }

    func testMergesAndIndentRoundTrip() throws {
        let c = book()
        c.select(range: r("A1:C2"))
        c.merge(.across)
        c.select(CellAddress("A3")!)
        c.indent(by: 3)
        let back = WorkbookController()
        back.load(try Xlsx.read(try Xlsx.write(c.book)))
        XCTAssertEqual(Set(back.sheet.merges.map(\.a1)), ["A1:C1", "A2:C2"])
        let st = back.book.style(back.sheet.cells[CellAddress("A3")!]!.style)
        XCTAssertEqual(st.indent, 3)
        XCTAssertEqual(st.hAlign, .left)
    }

    /// The real Home ribbon: the Merge menu's items and the indent buttons reach the controller.
    func testHomeRibbonMergeMenuAndIndentButtons() throws {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: SheetsShell(initialPath: nil, onSwitch: { _, _ in }), title: "Test"),
                              size: Size(1440, 900))
        let wb = try XCTUnwrap(ui.state(SheetsShellState.self)).wb
        wb.setInput("Name", at: CellAddress("A1")!)
        wb.setInput("Two", at: CellAddress("A2")!)
        wb.select(range: r("A1:C2"))
        ui.pump()
        XCTAssertTrue(ui.tap(tip: "Merge options"))
        ui.pump()
        XCTAssertTrue(ui.tap(id: "merge.Merge Across"))
        ui.pump()
        XCTAssertEqual(wb.sheet.merges.count, 2)
        XCTAssertTrue(ui.tap(tip: "Merge options"))
        ui.pump()
        XCTAssertTrue(ui.tap(id: "merge.Unmerge Cells"))
        ui.pump()
        XCTAssertTrue(wb.sheet.merges.isEmpty)
        XCTAssertTrue(ui.tap(tip: "Increase Indent"))
        ui.pump()
        XCTAssertEqual(wb.book.style(wb.sheet.cells[CellAddress("A1")!]!.style).indent, 1)
        XCTAssertTrue(ui.tap(tip: "Decrease Indent"))
        ui.pump()
        XCTAssertEqual(wb.book.style(wb.sheet.cells[CellAddress("A1")!]!.style).indent, 0)
    }
}
