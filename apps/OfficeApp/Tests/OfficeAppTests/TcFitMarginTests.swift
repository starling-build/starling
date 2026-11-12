import XCTest
@testable import OfficeText

/// Word's fit text in a cell rounds each side's cell margin UP to a whole 96-dpi pixel (labs fit1, mar1, mar2).
final class TcFitMarginTests: XCTestCase {
    private func slack(_ l: Double?, _ r: Double?) -> Double {
        var doc = RichDocument()
        doc.tableStyles["T"] = TableStyle(cellMarginLeft: l, cellMarginRight: r)
        var p = RichParagraph()
        p.cell = CellRef(table: "T", row: 0, column: 0)
        return RichLayout._tcFitMarginSlack(p, doc)
    }

    func testDefaultMarginRoundsUpToWholePixels() {
        // 5.4 pt = 7.2 px -> 8 px = 6.0 pt each side: the room shrinks by 0.6 pt per side.
        XCTAssertEqual(slack(nil, nil), -1.2, accuracy: 1e-9)
    }

    func testWholePixelMarginsLoseNothing() {
        XCTAssertEqual(slack(6.0, 6.0), 0, accuracy: 1e-9)
        XCTAssertEqual(slack(0.0, 0.0), 0, accuracy: 1e-9)
    }

    func testEachSideRoundsOnItsOwn() {
        XCTAssertEqual(slack(1.4, 0.0), 1.4 - 1.5, accuracy: 1e-9)   // 28 twips = 1.4 pt = 1.87 px -> 2 px = 1.5 pt
    }
}
