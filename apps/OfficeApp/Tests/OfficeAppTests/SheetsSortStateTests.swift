import XCTest
@testable import OfficeApp

/// X-DA-1: a sort is saved as Excel's <sortState> (on the sheet, or inside the AutoFilter for the filter's
/// data), in the sort's own undo step, and a reopen keeps it.
final class SheetsSortStateTests: XCTestCase {
    private func controller() -> WorkbookController {
        let c = WorkbookController()
        c.load(Workbook(sheets: [Worksheet(name: "Data")]))
        let rows = [["Name", "Score", "Day"], ["b", "3", "Tue"], ["a", "1", "Mon"], ["c", "2", "Sun"], ["d", "2", "Wed"]]
        for (r, row) in rows.enumerated() { for (k, t) in row.enumerated() { c.setInput(t, at: CellAddress(row: r, col: k)) } }
        return c
    }
    private func reopen(_ c: WorkbookController) throws -> WorkbookController {
        let again = WorkbookController()
        again.load(try Xlsx.read(try Xlsx.write(c.book)))
        return again
    }
    private func state(_ c: WorkbookController) -> String? { c.sheet.keptElements.first { $0.name == "sortState" }?.text }

    func testATwoLevelSortIsSavedOnTheSheetAndUndone() throws {
        let c = controller()
        XCTAssertNil(c.sortRange(CellRange("A1:C5")!, keys: [SortKey(col: 1, ascending: false), SortKey(col: 2, custom: SortKey.builtinLists[0])], hasHeader: true))
        let want = "<sortState ref=\"A2:C5\"><sortCondition descending=\"1\" ref=\"B2:B5\"/><sortCondition ref=\"C2:C5\" customList=\"Sun,Mon,Tue,Wed,Thu,Fri,Sat\"/></sortState>"
        XCTAssertEqual(state(c), want)
        XCTAssertEqual(state(try reopen(c)), want)
        c.undo()
        XCTAssertNil(state(c))
        XCTAssertEqual(c.sheet.cells[CellAddress(row: 1, col: 0)]?.input, "b")
    }

    func testANewSortReplacesTheOldRecord() {
        let c = controller()
        _ = c.sortRange(CellRange("A1:C5")!, keys: [SortKey(col: 0)], hasHeader: true)
        _ = c.sortRange(CellRange("A1:C5")!, keys: [SortKey(col: 2)], hasHeader: true, caseSensitive: true)
        XCTAssertEqual(c.sheet.keptElements.filter { $0.name == "sortState" }.map(\.text),
                       ["<sortState caseSensitive=\"1\" ref=\"A2:C5\"><sortCondition ref=\"C2:C5\"/></sortState>"])
    }

    func testAColourLevelNamesItsColourByALook() {
        let c = controller()
        let n = c.book.dxfs.count
        _ = c.sortRange(CellRange("A1:C5")!, keys: [SortKey(col: 0, on: .cellColor, color: 0xFFC7CE, colorOnTop: false)], hasHeader: true)
        XCTAssertEqual(state(c), "<sortState ref=\"A2:C5\"><sortCondition descending=\"1\" sortBy=\"cellColor\" ref=\"A2:A5\" dxfId=\"\(n)\"/></sortState>")
        XCTAssertEqual(c.book.dxfs.last?.fill.map { $0 & 0xFFFFFF }, 0xFFC7CE)
        // "No Fill" cannot be named: the old record goes rather than describe another order.
        _ = c.sortRange(CellRange("A1:C5")!, keys: [SortKey(col: 0, on: .cellColor, color: nil)], hasHeader: true)
        XCTAssertNil(state(c))
    }

    func testLeftToRightIsAColumnSort() {
        let c = controller()
        _ = c.sortRange(CellRange("A1:C5")!, keys: [SortKey(col: 1)], hasHeader: true, byColumns: true)
        XCTAssertEqual(state(c), "<sortState columnSort=\"1\" ref=\"B1:C5\"><sortCondition ref=\"B2:C2\"/></sortState>")
    }

    func testASortOfTheFilterDataGoesInsideTheFilterAndSurvivesAFilterChange() throws {
        let c = controller()
        c.select(CellAddress(row: 0, col: 0))
        c.toggleAutoFilter()
        c.sortFilter(col: 1, ascending: false)
        XCTAssertNil(state(c))
        let inner = "<sortState ref=\"A2:C5\"><sortCondition descending=\"1\" ref=\"B2:B5\"/></sortState>"
        XCTAssertEqual(c.sheet.autoFilter?.sortState, inner)
        let back = try reopen(c)
        XCTAssertEqual(back.sheet.autoFilter?.sortState, inner)
        XCTAssertNil(back.sheet.autoFilter?.raw, "the filter stays editable")
        back.setFilter(col: 0, allowed: ["a", "b"])
        XCTAssertEqual(try reopen(back).sheet.autoFilter?.sortState, inner)
        c.undo()
        XCTAssertNil(c.sheet.autoFilter?.sortState)
    }

    func testAKeptFilterGetsItsSortStateSplicedIn() {
        let raw = "<autoFilter ref=\"A1:C5\"><filterColumn colId=\"0\"><x/></filterColumn><sortState ref=\"A2:C5\"><sortCondition ref=\"A2:A5\"/></sortState></autoFilter>"
        XCTAssertEqual(AutoFilter.withSortState(raw, "<sortState ref=\"A2:C5\"/>"),
                       "<autoFilter ref=\"A1:C5\"><filterColumn colId=\"0\"><x/></filterColumn><sortState ref=\"A2:C5\"/></autoFilter>")
        XCTAssertEqual(AutoFilter.withSortState("<autoFilter ref=\"A1:C5\"/>", "<sortState ref=\"A2:C5\"/>"),
                       "<autoFilter ref=\"A1:C5\"><sortState ref=\"A2:C5\"/></autoFilter>")
        XCTAssertEqual(AutoFilter.withSortState(raw, nil), "<autoFilter ref=\"A1:C5\"><filterColumn colId=\"0\"><x/></filterColumn></autoFilter>")
    }

    func testSortAToZOnTheRibbonIsRecordedToo() {
        let c = controller()
        c.select(CellAddress(row: 2, col: 1))
        c.sortSelection(ascending: true)
        XCTAssertEqual(state(c), "<sortState ref=\"A2:C5\"><sortCondition ref=\"B2:B5\"/></sortState>")
        c.undo()
        XCTAssertNil(state(c))
        XCTAssertEqual(c.sheet.cells[CellAddress(row: 1, col: 0)]?.input, "b")
    }

    /// For the Excel check: set STARLING_UI_CHECK_DIR and the book is written there. Four sheets: a two-level sort
    /// with a custom list, a colour level on the bottom, a left-to-right sort, and a sort of an AutoFilter's data.
    func testSaveForExcel() throws {
        guard let dir = ProcessInfo.processInfo.environment["STARLING_UI_CHECK_DIR"] else { throw XCTSkip("no check folder") }
        let c = WorkbookController()
        c.load(Workbook(sheets: ["TwoLevels", "Colour", "LeftToRight", "Filter"].map { Worksheet(name: $0) }))
        let rows = [["Name", "Score", "Day"], ["b", "3", "Tue"], ["a", "1", "Mon"], ["c", "2", "Sun"], ["d", "2", "Wed"]]
        for s in 0 ..< 4 {
            c.activeSheet = s
            for (r, row) in rows.enumerated() { for (k, t) in row.enumerated() { c.setInput(t, at: CellAddress(row: r, col: k)) } }
        }
        c.activeSheet = 0
        XCTAssertNil(c.sortRange(CellRange("A1:C5")!, keys: [SortKey(col: 1, ascending: false), SortKey(col: 2, custom: SortKey.builtinLists[0])], hasHeader: true))
        c.activeSheet = 1
        XCTAssertNil(c.sortRange(CellRange("A1:C5")!, keys: [SortKey(col: 0, on: .cellColor, color: 0xFFC7CE, colorOnTop: false)], hasHeader: true))
        c.activeSheet = 2
        XCTAssertNil(c.sortRange(CellRange("A1:C5")!, keys: [SortKey(col: 1)], hasHeader: true, byColumns: true))
        c.activeSheet = 3
        c.select(CellAddress(row: 0, col: 0))
        c.toggleAutoFilter()
        c.sortFilter(col: 1, ascending: false)
        c.activeSheet = 0
        try Xlsx.write(c.book).write(to: URL(fileURLWithPath: dir + "/sort-state.xlsx"))
    }
}
