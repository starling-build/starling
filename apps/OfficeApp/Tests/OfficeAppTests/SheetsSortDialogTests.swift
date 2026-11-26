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

    // MARK: Sort On, Order lists, Options

    private func book(_ rows: [[String]]) -> WorkbookController {
        let c = WorkbookController()
        c.load(Workbook(sheets: [Worksheet(name: "Data")]))
        for (r, row) in rows.enumerated() { for (k, v) in row.enumerated() { c.setInput(v, at: CellAddress(row: r, col: k)) } }
        c.select(CellAddress(row: 1, col: 0))
        return c
    }

    private func dialog(_ c: WorkbookController, range: CellRange, header: Bool) -> (WidgetTester, SortDialogState) {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SortDialog(controller: c, range: range, hasHeader: header, onClose: {}), title: "T"),
                              size: Size(1280, 800))
        return (ui, ui.state(SortDialogState.self)!)
    }

    func testCellColourLevelOffersTheColumnsFillsMostUsedFirstAndSortsThemOnBottom() {
        let c = book([["n"], ["a"], ["b"], ["c"], ["d"]])
        for r in [1, 3] { c.select(CellAddress(row: r, col: 0)); c.setStyle { $0.fill = 0xFFC7CE } }
        c.select(CellAddress(row: 2, col: 0)); c.setStyle { $0.fill = 0xC6EFCE }
        let (ui, s) = dialog(c, range: CellRange(top: 0, left: 0, bottom: 4, right: 0), header: true)
        s.setSortOn(0, .cellColor)
        XCTAssertEqual(s.colors(0), [0xFFC7CE, 0xC6EFCE], "most used first")
        XCTAssertEqual(s.levels[0].color, 0xFFC7CE, "the first colour is picked")
        s.setColorOnTop(0, false)
        ui.press(.enter)
        XCTAssertEqual((0...4).map { c.input(CellAddress(row: $0, col: 0)) }, ["n", "b", "d", "a", "c"])
    }

    func testFontColourLevelWithNoColoursSaysSo() {
        let c = book([["n"], ["a"], ["b"]])
        let (ui, s) = dialog(c, range: CellRange(top: 0, left: 0, bottom: 2, right: 0), header: true)
        s.setSortOn(0, .fontColor)
        ui.pump()
        XCTAssertNil(s.levels[0].color)
        XCTAssertTrue(ui.has(text: "No font colours here."))
    }

    func testBuiltInListOrderBothWays() {
        let c = book([["d"], ["Wed"], ["Mon"], ["Sun"]])
        let (ui, s) = dialog(c, range: CellRange(top: 0, left: 0, bottom: 3, right: 0), header: true)
        s.setOrder(0, SortDialogState.listCode(0, ascending: false))
        XCTAssertEqual(s.levels[0].custom, SortKey.builtinLists[0])
        XCTAssertFalse(s.levels[0].ascending)
        XCTAssertEqual(s.orderCode(0), SortDialogState.listCode(0, ascending: false))
        ui.press(.enter)
        XCTAssertEqual((0...3).map { c.input(CellAddress(row: $0, col: 0)) }, ["d", "Wed", "Mon", "Sun"])
        c.undo()
        let (ui2, s2) = dialog(c, range: CellRange(top: 0, left: 0, bottom: 3, right: 0), header: true)
        s2.setOrder(0, SortDialogState.listCode(0, ascending: true))
        ui2.press(.enter)
        XCTAssertEqual((0...3).map { c.input(CellAddress(row: $0, col: 0)) }, ["d", "Sun", "Mon", "Wed"])
    }

    func testTypedListSortsByItAndAnEmptyOneIsRefused() {
        let c = book([["p"], ["Low"], ["High"], ["Other"], ["Medium"]])
        let (ui, s) = dialog(c, range: CellRange(top: 0, left: 0, bottom: 4, right: 0), header: true)
        s.setOrder(0, SortDialogState.typedList)
        ui.pump()
        XCTAssertEqual(s.orderCode(0), SortDialogState.typedList)
        ui.press(.enter)
        XCTAssertEqual(s.message, "Type the list's entries, separated by commas.")
        XCTAssertEqual(c.input(CellAddress(row: 1, col: 0)), "Low", "nothing sorted")
        s.setTypedList(0, " High, Medium ,Low,")
        ui.press(.enter)
        XCTAssertEqual((0...4).map { c.input(CellAddress(row: $0, col: 0)) }, ["p", "High", "Medium", "Low", "Other"])
    }

    func testLeftToRightNamesRowsAndSortsColumns() {
        let c = book([["k", "b", "c", "a"], ["v", "2", "3", "1"]])
        let (ui, s) = dialog(c, range: CellRange(top: 0, left: 0, bottom: 1, right: 3), header: true)
        XCTAssertTrue(ui.tap(id: "sort-left-to-right"))
        XCTAssertTrue(s.byColumns)
        XCTAssertEqual(s.lines, [0, 1])
        XCTAssertEqual(s.columnLabel(0), "k", "with headers a row is named by its first cell")
        s.setHeader(false)
        XCTAssertEqual(s.columnLabel(1), "Row 2")
        s.setHeader(true)
        ui.press(.enter)
        XCTAssertEqual((0...3).map { c.input(CellAddress(row: 0, col: $0)) }, ["k", "a", "b", "c"])
        XCTAssertEqual((0...3).map { c.input(CellAddress(row: 1, col: $0)) }, ["v", "1", "2", "3"])
    }

    func testCaseSensitiveOptionReachesTheSort() {
        let c = book([["n"], ["A"], ["a"], ["b"]])
        let (ui, s) = dialog(c, range: CellRange(top: 0, left: 0, bottom: 3, right: 0), header: true)
        XCTAssertTrue(ui.tap(id: "sort-case"))
        XCTAssertTrue(s.caseSensitive)
        ui.press(.enter)
        XCTAssertEqual((0...3).map { c.input(CellAddress(row: $0, col: 0)) }, ["n", "a", "A", "b"], "Excel: lower case first")
    }
}
