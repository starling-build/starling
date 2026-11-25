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

    /// A 3-row table in a named style: header row black, odd bands grey, even bands white.
    private func styled() throws -> RichDocumentController {
        var ps: [RichParagraph] = []
        for r in 0 ..< 3 { var p = RichParagraph(text: "r\(r)"); p.cell = CellRef(table: "T", row: r, column: 0); ps.append(p) }
        ps.append(RichParagraph(text: ""))
        var doc = RichDocument(paragraphs: ps)
        doc.tableColumns["T"] = [100]
        var entries = try Zip.read(try DocxFormat.write(doc, pageSetup: .letter))
        let si = entries.firstIndex { $0.name == "word/styles.xml" }!
        var styles = String(decoding: entries[si].data, as: UTF8.self)
        styles = styles.replacingAll("</w:styles>", with: "<w:style w:type=\"table\" w:styleId=\"G4\"><w:name w:val=\"G4\"/><w:tblStylePr w:type=\"firstRow\"><w:tcPr><w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"000000\"/></w:tcPr></w:tblStylePr><w:tblStylePr w:type=\"band1Horz\"><w:tcPr><w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"CCCCCC\"/></w:tcPr></w:tblStylePr></w:style></w:styles>")
        entries[si] = ZipEntry(name: "word/styles.xml", data: Data(styles.utf8))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        xml = xml.replacingAll("<w:tblPr><w:tblW w:w=\"0\" w:type=\"auto\"/>", with: "<w:tblPr><w:tblStyle w:val=\"G4\"/><w:tblW w:w=\"0\" w:type=\"auto\"/>")
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let back = try DocxFormat.read(try Zip.write(entries)).document
        return RichDocumentController(document: back)
    }

    private func fills(_ c: RichDocumentController) -> [Color?] { c.document.paragraphs.compactMap { $0.cell }.map { $0.fill } }

    func testHeaderAndBandFillsFollowTheSwitchesInOneUndo() throws {
        let c = try styled()
        let black = Color(0xFF000000), grey = Color(0xFFCCCCCC)
        XCTAssertEqual(fills(c), [black, grey, nil])
        c.selection = RichSelection(anchor: RichPosition(paragraph: 0, offset: 0), focus: RichPosition(paragraph: 0, offset: 0))
        c.setTableLook(TableLook.firstRow, on: false)
        XCTAssertEqual(fills(c), [grey, nil, grey], "no header row: the bands start at the top")
        c.setTableLook(TableLook.noRowBands, on: true)
        XCTAssertEqual(fills(c), [nil, nil, nil])
        c.undo()
        XCTAssertEqual(fills(c), [grey, nil, grey])
        c.undo()
        XCTAssertEqual(fills(c), [black, grey, nil])
    }

    func testStyleFillsAreNotWrittenAsDirectShadingAndAShadingOfMyOwnIsKept() throws {
        let c = try styled()
        c.selection = RichSelection(anchor: RichPosition(paragraph: 1, offset: 0), focus: RichPosition(paragraph: 1, offset: 0))
        c.setCellShading(Color(0xFFFFFF00))
        c.setTableLook(TableLook.firstRow, on: false)
        XCTAssertEqual(fills(c)[1], Color(0xFFFFFF00), "a direct shading stays through a switch")
        let xml = String(decoding: try Zip.read(try DocxFormat.write(c.document, pageSetup: .letter)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertEqual(xml.components(separatedBy: "w:shd ").count - 1, 1, "only the cell's own shading is written")
        XCTAssertTrue(xml.containsSubstring("FFFF00"))
    }
}
