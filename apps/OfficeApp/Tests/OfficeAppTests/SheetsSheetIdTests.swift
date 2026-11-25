import XCTest
@testable import OfficeApp

final class SheetsSheetIdTests: XCTestCase {
    func testEachSheetKeepsItsOwnId() throws {
        let wc = WorkbookController()
        wc.addSheet(); wc.addSheet()
        wc.book.sheets[0].sheetId = 7; wc.book.sheets[1].sheetId = 3
        let again = WorkbookController(); again.load(try Xlsx.read(try Xlsx.write(wc.book)))
        XCTAssertEqual(again.book.sheets.map(\.sheetId), [7, 3, 8], "a sheet made here gets the next free id")
        let twice = WorkbookController(); twice.load(try Xlsx.read(try Xlsx.write(again.book)))
        XCTAssertEqual(twice.book.sheets.map(\.sheetId), [7, 3, 8])
    }
}
