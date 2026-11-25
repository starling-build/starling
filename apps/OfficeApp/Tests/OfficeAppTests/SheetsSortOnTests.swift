import XCTest
@testable import OfficeApp

/// X-DA-1: Sort On colour, custom lists, left to right, case sensitive.
final class SheetsSortOnTests: XCTestCase {
    private func controller(_ rows: [[String]]) -> WorkbookController {
        let c = WorkbookController()
        c.load(Workbook(sheets: [Worksheet(name: "Data")]))
        for (r, row) in rows.enumerated() { for (k, v) in row.enumerated() { c.setInput(v, at: CellAddress(row: r, col: k)) } }
        return c
    }
    private func col(_ c: WorkbookController, _ k: Int, _ n: Int) -> [String] { (0 ..< n).map { c.input(CellAddress(row: $0, col: k)) } }
    private func row(_ c: WorkbookController, _ r: Int, _ n: Int) -> [String] { (0 ..< n).map { c.input(CellAddress(row: r, col: $0)) } }

    func testCellColourLevelPutsThatFillFirstThenTheNextLevelBreaksTies() {
        let c = controller([["n", "v"], ["a", "3"], ["b", "1"], ["c", "2"], ["d", "0"]])
        for r in [2, 4] { c.select(CellAddress(row: r, col: 0)); c.setStyle { $0.fill = 0xFFC7CE } }
        let k = [SortKey(col: 0, on: .cellColor, color: 0xFFC7CE), SortKey(col: 1)]
        XCTAssertNil(c.sortRange(CellRange(top: 0, left: 0, bottom: 4, right: 1), keys: k, hasHeader: true))
        XCTAssertEqual(col(c, 0, 5), ["n", "d", "b", "c", "a"], "red first (by value), then the rest (by value)")
        c.undo()
        XCTAssertEqual(col(c, 0, 5), ["n", "a", "b", "c", "d"])
    }

    func testColourOnBottomAndNoFill() {
        let c = controller([["n"], ["a"], ["b"], ["c"]])
        c.select(CellAddress(row: 1, col: 0)); c.setStyle { $0.color = 0xFF0000 }
        XCTAssertNil(c.sortRange(CellRange(top: 0, left: 0, bottom: 3, right: 0),
                                 keys: [SortKey(col: 0, on: .fontColor, color: 0xFF0000, colorOnTop: false)], hasHeader: true))
        XCTAssertEqual(col(c, 0, 4), ["n", "b", "c", "a"])
    }

    func testCustomListOrdersByTheListAndOthersFollow() {
        let c = controller([["d"], ["Wed"], ["foo"], ["Mon"], ["Sun"], ["tue"]])
        let days = SortKey.builtinLists[0]
        XCTAssertNil(c.sortRange(CellRange(top: 0, left: 0, bottom: 5, right: 0), keys: [SortKey(col: 0, custom: days)], hasHeader: true))
        XCTAssertEqual(col(c, 0, 6), ["d", "Sun", "Mon", "tue", "Wed", "foo"])
        XCTAssertNil(c.sortRange(CellRange(top: 0, left: 0, bottom: 5, right: 0), keys: [SortKey(col: 0, ascending: false, custom: days)], hasHeader: true))
        XCTAssertEqual(col(c, 0, 6), ["d", "Wed", "tue", "Mon", "Sun", "foo"])
    }

    func testLeftToRightMovesColumnsAndShiftsFormulas() {
        let c = controller([["", "x", "y", "z"], ["k", "3", "1", "2"], ["f", "=B2", "=C2", "=D2"]])
        XCTAssertNil(c.sortRange(CellRange(top: 0, left: 0, bottom: 2, right: 3), keys: [SortKey(col: 1)], hasHeader: true, byColumns: true))
        XCTAssertEqual(row(c, 0, 4), ["", "y", "z", "x"])
        XCTAssertEqual(row(c, 1, 4), ["k", "1", "2", "3"])
        XCTAssertEqual(row(c, 2, 4), ["f", "=B2", "=C2", "=D2"], "each formula still reads the cell above it")
        XCTAssertEqual(c.sheet.value(CellAddress(row: 2, col: 3)), .number(3))
        c.undo()
        XCTAssertEqual(row(c, 1, 4), ["k", "3", "1", "2"])
    }

    func testLeftToRightRefusesAKeyRowOutsideTheRange() {
        let c = controller([["a", "2", "1"], ["b", "1", "2"]])
        XCTAssertEqual(c.sortRange(CellRange(top: 0, left: 0, bottom: 1, right: 2), keys: [SortKey(col: 5)], hasHeader: false, byColumns: true), .keyOutside)
    }

    func testCaseSensitiveSortsLowerCaseFirstOnTies() {
        let c = controller([["t"], ["B"], ["a"], ["A"], ["b"]])
        XCTAssertNil(c.sortRange(CellRange(top: 0, left: 0, bottom: 4, right: 0), keys: [SortKey(col: 0)], hasHeader: true, caseSensitive: true))
        XCTAssertEqual(col(c, 0, 5), ["t", "a", "A", "b", "B"])
    }
}
