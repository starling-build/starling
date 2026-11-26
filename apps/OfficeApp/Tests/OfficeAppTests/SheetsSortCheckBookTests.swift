import XCTest
@testable import OfficeApp

/// With STARLING_DATA_CHECK_DIR: sort-on.xlsx for Excel. Each sheet holds the original block on the left
/// and the same block sorted here on the right; row 1 of each sheet says which Excel sort to run on the
/// left block so the two can be compared.
final class SheetsSortCheckBookTests: XCTestCase {
    func testWriteSortCheckBook() throws {
        guard let out = ProcessInfo.processInfo.environment["STARLING_DATA_CHECK_DIR"] else { throw XCTSkip("no STARLING_DATA_CHECK_DIR") }
        try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        let c = WorkbookController()
        c.load(Workbook(sheets: ["Colour", "Days", "LeftToRight", "Case"].map { Worksheet(name: $0) }))
        func fill(_ rows: [[String]], top: Int, col0: Int) {
            for (r, row) in rows.enumerated() { for (k, t) in row.enumerated() { c.setInput(t, at: CellAddress(row: top + r, col: col0 + k)) } }
        }
        func both(_ rows: [[String]], right: Int) { fill(rows, top: 2, col0: 0); fill(rows, top: 2, col0: right) }

        // Colour: red fill on top, then by Score ascending.
        c.activeSheet = 0
        c.setInput("Sort A3:B8 by Name, Cell Color #FFC7CE On Top, then by Score, Smallest to Largest. Expected: D3:E8.", at: CellAddress(row: 0, col: 0))
        let scores = [["Name", "Score"], ["a", "3"], ["b", "1"], ["c", "2"], ["d", "0"], ["e", "5"]]
        both(scores, right: 3)
        for r in [4, 6, 7] { for k in [0, 3] { c.select(CellAddress(row: r, col: k)); c.setStyle { $0.fill = 0xFFC7CE } } }
        XCTAssertNil(c.sortRange(CellRange(top: 2, left: 3, bottom: 7, right: 4),
                                 keys: [SortKey(col: 3, on: .cellColor, color: 0xFFC7CE), SortKey(col: 4)], hasHeader: true))

        // Days: the Sun, Mon, … custom list; values not in it follow.
        c.activeSheet = 1
        c.setInput("Sort A3:A9 by Day, Order: custom list Sun, Mon, Tue, Wed, Thu, Fri, Sat. Expected: C3:C9.", at: CellAddress(row: 0, col: 0))
        both([["Day"], ["Wed"], ["foo"], ["Mon"], ["Sun"], ["tue"], ["Sat"]], right: 2)
        XCTAssertNil(c.sortRange(CellRange(top: 2, left: 2, bottom: 8, right: 2), keys: [SortKey(col: 2, custom: SortKey.builtinLists[0])], hasHeader: true))

        // Left to right: the columns of B3:E4 reorder by row 4 (A holds the row labels, outside the range).
        c.activeSheet = 2
        c.setInput("Select B3:E4, Sort, Options: Sort left to right, by Row 4, Smallest to Largest. Expected: B7:E8.", at: CellAddress(row: 0, col: 0))
        let wide = [["k", "b", "c", "a", "d"], ["v", "2", "3", "1", "0"]]
        fill(wide, top: 2, col0: 0); fill(wide, top: 6, col0: 0)
        XCTAssertNil(c.sortRange(CellRange(top: 6, left: 1, bottom: 7, right: 4), keys: [SortKey(col: 7)], hasHeader: false, byColumns: true))

        // Case sensitive: lower case before upper case.
        c.activeSheet = 3
        c.setInput("Sort A3:A8 by Word, A to Z, Options: Case sensitive. Expected: C3:C8.", at: CellAddress(row: 0, col: 0))
        both([["Word"], ["B"], ["a"], ["A"], ["b"], ["c"]], right: 2)
        XCTAssertNil(c.sortRange(CellRange(top: 2, left: 2, bottom: 7, right: 2), keys: [SortKey(col: 2)], hasHeader: true, caseSensitive: true))

        let data = try Xlsx.write(c.book)
        let back = WorkbookController(); back.load(try Xlsx.read(data))
        back.activeSheet = 0
        XCTAssertEqual((3 ... 7).map { back.input(CellAddress(row: $0, col: 3)) }, ["d", "b", "e", "c", "a"])
        back.activeSheet = 1
        XCTAssertEqual((3 ... 8).map { back.input(CellAddress(row: $0, col: 2)) }, ["Sun", "Mon", "tue", "Wed", "Sat", "foo"])
        back.activeSheet = 2
        XCTAssertEqual((1 ... 4).map { back.input(CellAddress(row: 6, col: $0)) }, ["d", "a", "b", "c"])
        back.activeSheet = 3
        XCTAssertEqual((3 ... 7).map { back.input(CellAddress(row: $0, col: 2)) }, ["a", "A", "b", "B", "c"])
        try data.write(to: URL(fileURLWithPath: out + "/sort-on.xlsx"))
    }
}
