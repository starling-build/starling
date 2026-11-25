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
        let r = d.removeDuplicates(CellRange(top: 0, left: 4, bottom: 5, right: 5), columns: [4, 5], hasHeader: true)   // sheet columns E and F
        XCTAssertNil(r.problem)
        XCTAssertEqual(r.result, DuplicatesResult(removed: 2, remaining: 3))
        // The saved file holds what the sheet holds: E4:F6 are empty, E2:F4 are a/X, b/Y, a/Z.
        let back = WorkbookController(); back.load(try Xlsx.read(try Xlsx.write(d.book)))
        func col(_ k: Int) -> [String] { (0 ... 5).map { back.input(CellAddress(row: $0, col: k)) } }
        XCTAssertEqual(col(4), ["Name", "a", "b", "a", "", ""])
        XCTAssertEqual(col(5), ["City", "X", "Y", "Z", "", ""])
        XCTAssertEqual(col(0), ["Name", "a", "A", "b", "a", "b"], "the left block is untouched")
        try Xlsx.write(d.book).write(to: URL(fileURLWithPath: out + "/remove-duplicates.xlsx"))
        // Text to Columns: column A is the original text; B..D hold the same text split by comma with
        // the quote qualifier (row 2 keeps "x,y" whole), done on a copy in column F.
        let t = WorkbookController(); t.load(Workbook(sheets: [Worksheet(name: "Data")]))
        let lines = ["a,b,c", "\"x,y\",2", "solo", "1,2,3"]
        for (k, s) in lines.enumerated() { t.setInput(s, at: CellAddress(row: k, col: 0)); t.setInput(s, at: CellAddress(row: k, col: 5)) }
        let n = t.textToColumns(CellRange(top: 0, left: 5, bottom: 3, right: 5), options: TextSplitOptions())
        XCTAssertNil(n.problem)
        XCTAssertEqual(n.columns, 3)
        try Xlsx.write(t.book).write(to: URL(fileURLWithPath: out + "/text-to-columns.xlsx"))
    }
}

extension SheetsDataToolsCheckBooksTests {
    /// A plain clear, saved: the cleared cells are gone from the file (a book that came from a file too).
    func testClearedCellsAreNotInTheSavedFile() throws {
        let c = WorkbookController(); c.load(Workbook(sheets: [Worksheet(name: "Data")]))
        for r in 0 ..< 4 { c.setInput("v\(r)", at: CellAddress(row: r, col: 0)); c.setInput("w\(r)", at: CellAddress(row: r, col: 1)) }
        let first = try Xlsx.write(c.book)
        let again = WorkbookController(); again.load(try Xlsx.read(first))      // as if opened from a file
        again.setInput("", at: CellAddress(row: 2, col: 0)); again.setInput("", at: CellAddress(row: 3, col: 1))
        let back = WorkbookController(); back.load(try Xlsx.read(try Xlsx.write(again.book)))
        XCTAssertEqual((0 ..< 4).map { back.input(CellAddress(row: $0, col: 0)) }, ["v0", "v1", "", "v3"])
        XCTAssertEqual((0 ..< 4).map { back.input(CellAddress(row: $0, col: 1)) }, ["w0", "w1", "w2", ""])
    }
}
