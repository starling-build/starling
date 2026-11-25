import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp
@testable import OfficeText

/// W-TB-11: Table Layout > Sort.
final class SortTableTests: XCTestCase {
    private func table(_ rows: [[String]]) -> RichDocumentController {
        let c = RichDocumentController(plainText: "")
        c.insertTable(rows: rows.count, columns: rows[0].count)
        let idx = c.document.paragraphs.indices.filter { c.document.paragraphs[$0].cell != nil }
        for (k, i) in idx.enumerated() {
            let t = rows[k / rows[0].count][k % rows[0].count]
            if t.isEmpty { continue }
            c.moveTo(RichPosition(paragraph: i, offset: 0), extend: false)
            c.insertText(t)
        }
        c.moveTo(RichPosition(paragraph: idx[0], offset: 0), extend: false)
        return c
    }
    private func grid(_ c: RichDocumentController) -> [[String]] {
        let cells = c.document.paragraphs.filter { $0.cell != nil }
        let n = c.document.columnCount(of: cells[0].cell!.table)
        return stride(from: 0, to: cells.count, by: n).map { Array(cells[$0 ..< $0 + n].map(\.text)) }
    }

    func testTextAscendingAndDescendingKeepingTheHeader() {
        let c = table([["Name", "N"], ["pear", "1"], ["Apple", "2"], ["fig", "3"]])
        XCTAssertTrue(c.sortTable(keys: [.init(column: 0)], headerRow: true))
        XCTAssertEqual(grid(c).map { $0[0] }, ["Name", "Apple", "fig", "pear"])
        XCTAssertEqual(grid(c).map { $0[1] }, ["N", "2", "3", "1"], "a row moves whole")
        c.sortTable(keys: [.init(column: 0, ascending: false)], headerRow: true)
        XCTAssertEqual(grid(c).map { $0[0] }, ["Name", "pear", "fig", "Apple"])
    }

    func testNumbersSortByValueNotByText() {
        let c = table([["10"], ["9"], ["$1,200"], ["2.5"]])
        c.sortTable(keys: [.init(column: 0, kind: .number)], headerRow: false)
        XCTAssertEqual(grid(c).map { $0[0] }, ["2.5", "9", "10", "$1,200"])
    }

    func testDatesSortInCalendarOrder() {
        let c = table([["3/5/2024"], ["2023-12-31"], ["Jan 2, 2024"], ["5 March 2023"]])
        c.sortTable(keys: [.init(column: 0, kind: .date)], headerRow: false)
        XCTAssertEqual(grid(c).map { $0[0] }, ["5 March 2023", "2023-12-31", "Jan 2, 2024", "3/5/2024"])
    }

    func testSecondKeyBreaksTiesAndEqualRowsKeepTheirOrder() {
        let c = table([["a", "2", "x"], ["b", "1", "y"], ["a", "1", "z"], ["a", "1", "w"]])
        c.sortTable(keys: [.init(column: 0), .init(column: 1, kind: .number)], headerRow: false)
        XCTAssertEqual(grid(c).map { $0[2] }, ["z", "w", "x", "y"])
    }

    func testOneUndoStepAndTheSortedTableSurvivesASave() throws {
        let c = table([["c"], ["a"], ["b"]])
        c.sortTable(keys: [.init(column: 0)], headerRow: false)
        let back = try DocxFormat.read(try DocxFormat.write(c.document, pageSetup: .letter)).document
        XCTAssertEqual(back.paragraphs.filter { $0.cell != nil }.map(\.text), ["a", "b", "c"])
        c.undo()
        XCTAssertEqual(grid(c).map { $0[0] }, ["c", "a", "b"])
    }

    func testMergedCellsRefuseToSort() {
        let c = table([["a", "b"], ["c", "d"]])
        c.selectRow()
        c.mergeCells()
        XCTAssertFalse(c.canSortTable)
    }
}
