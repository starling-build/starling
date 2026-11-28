import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp
@testable import OfficeText

/// AutoFit and Distribute Rows.
final class TableAutoFitMenuTests: XCTestCase {
    private func table() -> RichDocumentController {
        let c = RichDocumentController(plainText: "")
        c.insertTable(rows: 3, columns: 2)
        let i = c.document.paragraphs.firstIndex { $0.cell != nil }!
        c.moveTo(RichPosition(paragraph: i, offset: 0), extend: false)
        return c
    }

    func testAutoFitVariants() {
        let c = table()
        c.autoFitTable(.fixed)
        XCTAssertTrue(c.currentTableStyle!.fixedLayout)
        c.autoFitTable(.window)
        XCTAssertFalse(c.currentTableStyle!.fixedLayout)
        XCTAssertEqual(c.currentTableStyle!.widthPercent, 100)
        c.autoFitTable(.contents)
        XCTAssertNil(c.currentTableStyle!.widthPercent)
        XCTAssertNil(c.currentTableStyle!.width)
    }

    func testDistributeRowsGivesEveryRowTheTallest() {
        let c = table()
        let cells = c.document.paragraphs.indices.filter { c.document.paragraphs[$0].cell != nil }
        let heights = [20.0, 50.0, 30.0]
        c.rowHeightProbe = { i in c.document.paragraphs[i].cell.map { heights[$0.row] } }
        c.distributeRows()
        let s = c.currentTableStyle!
        XCTAssertEqual([0, 1, 2].map { s.rowHeights[$0] }, [50, 50, 50])
        c.undo()
        XCTAssertNil(c.currentTableStyle?.rowHeights[0])
        _ = cells
    }
}
