import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp
@testable import OfficeText

/// W-TB-7: the Table Style Options (Word's tblLook switches).
final class TableLookTests: XCTestCase {
    private func grid() -> RichDocumentController {
        let c = RichDocumentController(plainText: "")
        c.insertTable(rows: 3, columns: 2)
        return c
    }

    func testSwitchesStartAtWordsDefaultAndEachIsOneUndo() {
        let c = grid()
        let t = c.currentCell!.table
        XCTAssertEqual(c.tableLook(of: t), 0x04A0, "header row, first column, no column bands")
        c.setTableLook(TableLook.lastRow, on: true)
        XCTAssertEqual(c.tableLook(of: t), 0x04E0)
        c.setTableLook(TableLook.noRowBands, on: true)
        XCTAssertEqual(c.tableLook(of: t), 0x06E0)
        c.undo()
        XCTAssertEqual(c.tableLook(of: t), 0x04E0)
        c.undo()
        XCTAssertEqual(c.tableLook(of: t), 0x04A0)
    }

    func testHeaderRowIsALookSwitchAndDoesNotRepeatTheRow() {
        let c = grid()
        let t = c.currentCell!.table
        c.setTableLook(TableLook.firstRow, on: false)
        c.setTableLook(TableLook.firstRow, on: true)
        XCTAssertNotEqual(c.document.tableStyles[t]?.headerRow, true, "repeating is its own setting")
    }

    func testTheLookIsSavedAndReadBack() throws {
        let c = grid()
        c.setTableLook(TableLook.lastColumn, on: true)
        c.setTableLook(TableLook.firstColumn, on: false)
        let saved = try DocxFormat.write(c.document, pageSetup: .letter)
        let zip = try Zip.read(saved)
        let xml = String(decoding: try XCTUnwrap(zip.first { $0.name == "word/document.xml" }?.data), as: UTF8.self)
        XCTAssertTrue(xml.containsSubstring("<w:tblLook w:val=\"0520\" w:firstRow=\"1\" w:lastRow=\"0\" w:firstColumn=\"0\" w:lastColumn=\"1\" w:noHBand=\"0\" w:noVBand=\"1\"/>"))
        let back = try DocxFormat.read(saved).document
        XCTAssertEqual(back.tableStyles.values.first?.look, 0x0520, "the switches come back")
    }
}
