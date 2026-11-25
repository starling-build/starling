import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// X-DA-1b: the Sort dialog, driven headless — levels, headers and OK reach sortRange; the Data tab opens it.
final class SheetsSortDialogTests: XCTestCase {
    private func controller() -> WorkbookController {
        let c = WorkbookController()
        c.load(Workbook(sheets: [Worksheet(name: "Data")]))
        let rows = [["Team", "Score"], ["b", "2"], ["a", "2"], ["c", "1"]]
        for (r, row) in rows.enumerated() { for (k, v) in row.enumerated() { c.setInput(v, at: CellAddress(row: r, col: k)) } }
        c.select(CellAddress(row: 1, col: 0))
        return c
    }

    private func dialog(_ c: WorkbookController, _ log: @escaping (String) -> Void) -> (WidgetTester, SortDialogState) {
        let region = c.sortRegion()!
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SortDialog(controller: c, range: region.range, hasHeader: region.hasHeader, onClose: { log("closed") }),
                                        title: "T"), size: Size(1280, 800))
        return (ui, ui.state(SortDialogState.self)!)
    }

    private func column(_ c: WorkbookController, _ col: Int) -> [String] { (0...3).map { c.input(CellAddress(row: $0, col: col)) } }

    func testTwoLevelsSortAsOneUndoStepAndTheHeaderStays() {
        let c = controller()
        var log: [String] = []
        let (ui, s) = dialog(c) { log.append($0) }
        XCTAssertTrue(s.hasHeader, "the header guess comes from the region")
        s.setColumn(0, 1)
        XCTAssertTrue(ui.tap(id: "sort-add-level"))
        XCTAssertEqual(s.levels, [SortKey(col: 1), SortKey(col: 0)])
        ui.press(.enter)
        XCTAssertEqual(log, ["closed"])
        XCTAssertEqual(column(c, 0), ["Team", "c", "a", "b"])
        c.undo()
        XCTAssertEqual(column(c, 0), ["Team", "b", "a", "c"])
    }

    func testRemoveLevelAndOrderChoice() {
        let c = controller()
        let (ui, s) = dialog(c) { _ in }
        XCTAssertTrue(ui.tap(id: "sort-add-level"))
        XCTAssertTrue(ui.tap(id: "sort-remove-1"))
        XCTAssertEqual(s.levels.count, 1)
        s.setAscending(0, false)
        ui.press(.enter)
        XCTAssertEqual(column(c, 0), ["Team", "c", "b", "a"])
    }

    func testUntickingHeadersSortsTheFirstRowToo() {
        let c = controller()
        let (ui, s) = dialog(c) { _ in }
        XCTAssertTrue(ui.tap(id: "sort-has-header"))
        XCTAssertFalse(s.hasHeader)
        XCTAssertEqual(s.columnLabel(1), "Column B")
        ui.press(.enter)
        XCTAssertEqual(column(c, 0), ["a", "b", "c", "Team"], "the first row sorts with the rest")
    }

    func testMergedCellsKeepTheDialogOpenWithTheMessage() {
        let c = controller()
        c.sheet.merges = [CellRange("A2:A3")!]
        var log: [String] = []
        let (ui, s) = dialog(c) { log.append($0) }
        ui.press(.enter)
        XCTAssertEqual(log, [])
        XCTAssertEqual(s.message, SortProblem.mergedCells.message)
    }

    func testTheDataTabOpensTheDialogInTheSheetsShell() {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SheetsShell(initialPath: nil, onSwitch: { _, _ in }), title: "T"), size: Size(1280, 800))
        XCTAssertTrue(ui.tap(text: "Data"))
        XCTAssertTrue(ui.tap(text: "Sort…"))
        XCTAssertFalse(ui.has(text: "Add Level"), "an empty sheet has nothing to sort, so no dialog")
    }
}
