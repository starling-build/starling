import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// With STARLING_DATA_CHECK_DIR: books for Excel to open, showing Remove Duplicates and Text to Columns done here.
final class SheetsDataToolsCheckBooksTests: XCTestCase {
    func testWriteCheckBooks() throws {
        guard let out = ProcessInfo.processInfo.environment["STARLING_DATA_CHECK_DIR"] else { throw XCTSkip("no STARLING_DATA_CHECK_DIR") }
        try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        func fill(_ c: WorkbookController, _ rows: [[String]], col0: Int = 0) {
            for (r, row) in rows.enumerated() { for (k, t) in row.enumerated() { c.setInput(t, at: CellAddress(row: r, col: col0 + k)) } }
        }
        // Remove Duplicates: the left block is the original, the right block is the same data after
        // removing on both columns. Expected right block: header, a/X, b/Y, a/Z (3 rows).
        let rows = [["Name", "City"], ["a", "X"], ["A", "x"], ["b", "Y"], ["a", "Z"], ["b", "Y"]]
        let d = WorkbookController(); d.load(Workbook(sheets: [Worksheet(name: "Data")]))
        fill(d, rows); fill(d, rows, col0: 4)
        let r = d.removeDuplicates(CellRange(top: 0, left: 4, bottom: 5, right: 5), columns: [0, 1], hasHeader: true)
        XCTAssertEqual(r.result, DuplicatesResult(removed: 2, remaining: 3))
        try Xlsx.write(d.book).write(to: URL(fileURLWithPath: out + "/remove-duplicates.xlsx"))
        // Text to Columns: column A is the original text; B..D hold the same text split by comma with
        // the quote qualifier (row 2 keeps "x,y" whole), done on a copy in column F.
        let t = WorkbookController(); t.load(Workbook(sheets: [Worksheet(name: "Data")]))
        let lines = ["a,b,c", "\"x,y\",2", "solo", "1,2,3"]
        for (k, s) in lines.enumerated() { t.setInput(s, at: CellAddress(row: k, col: 0)); t.setInput(s, at: CellAddress(row: k, col: 5)) }
        let n = t.textToColumns(CellRange(top: 0, left: 5, bottom: 3, right: 5), options: TextSplitOptions())
        XCTAssertEqual(n.columns, 3)
        try Xlsx.write(t.book).write(to: URL(fileURLWithPath: out + "/text-to-columns.xlsx"))
    }
}
