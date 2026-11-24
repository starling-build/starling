import XCTest
@testable import OfficeApp

/// X-DA-1: sorting by several columns, each one undo step, and what a save keeps.
final class SheetsSortEditTests: XCTestCase {
    private func controller() -> WorkbookController {
        let c = WorkbookController()
        c.load(Workbook(sheets: [Worksheet(name: "Data")]))
        let rows = [["Team", "Score", "Name"], ["b", "3", "x"], ["a", "5", "y"], ["b", "1", "z"], ["a", "5", "w"]]
        for (r, row) in rows.enumerated() { for (k, v) in row.enumerated() { c.setInput(v, at: CellAddress(row: r, col: k)) } }
        return c
    }
    private func col(_ c: WorkbookController, _ k: Int) -> [String] { (0 ... 4).map { c.input(CellAddress(row: $0, col: k)) } }
    private let all = CellRange(top: 0, left: 0, bottom: 4, right: 2)

    func testTwoKeysHeaderStaysAndUndoIsOneStep() {
        let c = controller()
        XCTAssertNil(c.sortRange(all, keys: [SortKey(col: 0), SortKey(col: 1, ascending: false)], hasHeader: true))
        XCTAssertEqual(col(c, 0), ["Team", "a", "a", "b", "b"])
        XCTAssertEqual(col(c, 1), ["Score", "5", "5", "3", "1"])
        c.undo()
        XCTAssertEqual(col(c, 2), ["Name", "x", "y", "z", "w"])
    }

    func testFirstKeyTiesAreBrokenByTheSecondAndThenKeepOrder() {
        let c = controller()
        XCTAssertNil(c.sortRange(all, keys: [SortKey(col: 1, ascending: false)], hasHeader: true))
        XCTAssertEqual(col(c, 2), ["Name", "y", "w", "x", "z"])
    }

    func testRefusals() {
        let c = controller()
        XCTAssertEqual(c.sortRange(all, keys: [], hasHeader: true), .noKeys)
        XCTAssertEqual(c.sortRange(all, keys: [SortKey(col: 5)], hasHeader: true), .keyOutside)
        XCTAssertEqual(c.sortRange(CellRange(top: 0, left: 0, bottom: 1, right: 2), keys: [SortKey(col: 0)], hasHeader: true), .nothingToSort)
        c.sheet.merges = [CellRange(top: 2, left: 0, bottom: 3, right: 0)]
        XCTAssertEqual(c.sortRange(all, keys: [SortKey(col: 0)], hasHeader: true), .mergedCells)
        XCTAssertEqual(col(c, 0), ["Team", "b", "a", "b", "a"])
    }

    func testFormulasShiftWithTheirRowsAndSurviveASave() throws {
        let c = controller()
        for r in 1 ... 4 { c.setInput("=B\(r + 1)*2", at: CellAddress(row: r, col: 3)) }
        XCTAssertNil(c.sortRange(CellRange(top: 0, left: 0, bottom: 4, right: 3), keys: [SortKey(col: 1)], hasHeader: true))
        XCTAssertEqual(c.input(CellAddress(row: 1, col: 3)), "=B2*2")
        let again = WorkbookController()
        again.load(try Xlsx.read(try Xlsx.write(c.book)))
        XCTAssertEqual(again.input(CellAddress(row: 1, col: 1)), "1")
        XCTAssertEqual(again.input(CellAddress(row: 1, col: 3)), "=B2*2")
    }

    func testRegionGuessSeesTheHeader() {
        let c = controller()
        c.select(CellAddress(row: 2, col: 1))
        let g = c.sortRegion()
        XCTAssertEqual(g?.range, all)
        XCTAssertEqual(g?.hasHeader, true)
    }
}
