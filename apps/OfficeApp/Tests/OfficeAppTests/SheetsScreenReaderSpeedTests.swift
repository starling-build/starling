import XCTest
import Flutter
@testable import OfficeApp

/// With a screen reader listening, every Sheets edit says where the active cell is and names its header, which
/// needs the data region around it. On a tall table that must stay as quick as an edit with no screen reader.
final class SheetsScreenReaderSpeedTests: XCTestCase {
    override func tearDown() {
        ScreenReader.resetForTesting()
        super.tearDown()
    }

    func testEditOfTallTableStaysQuickWithAScreenReader() {
        ScreenReader.recorded = []
        let c = WorkbookController()
        var items: [(CellAddress, String)] = []
        let n = 50_000
        for r in 0 ..< n {
            items.append((CellAddress(row: r, col: 0), "1"))
            items.append((CellAddress(row: r, col: 1), "=A\(r + 1)*2"))
        }
        c.setInputs(items)
        c.select(CellAddress(row: 2, col: 1))
        let t = Date()
        c.setInputs([(CellAddress("D1")!, "7")])
        XCTAssertLessThan(Date().timeIntervalSince(t), 0.5)
        XCTAssertTrue(ScreenReader.recorded?.last?.hasPrefix("B3") ?? false, "said: \(ScreenReader.recorded ?? [])")
    }

    func testCurrentRegionTakesCellsTouchingAtACorner() {
        let c = WorkbookController()
        c.setInputs([(CellAddress("B2")!, "1"), (CellAddress("B3")!, "2"), (CellAddress("C4")!, "3"),
                     (CellAddress("D5")!, "4"), (CellAddress("F5")!, "5")])
        XCTAssertEqual(c.currentRegion(CellAddress("B2")!), CellRange(top: 1, left: 1, bottom: 4, right: 3))
        XCTAssertEqual(c.currentRegion(CellAddress("F5")!), CellRange(top: 4, left: 5, bottom: 4, right: 5))
    }
}
