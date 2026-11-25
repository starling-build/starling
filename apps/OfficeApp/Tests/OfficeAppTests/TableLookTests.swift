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
        styles = styles.replacingAll("</w:styles>", with: "<w:style w:type=\"table\" w:styleId=\"G4\"><w:name w:val=\"G4\"/><w:tblPr><w:tblStyleRowBandSize w:val=\"1\"/><w:tblStyleColBandSize w:val=\"1\"/></w:tblPr><w:tblStylePr w:type=\"firstRow\"><w:tcPr><w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"000000\"/></w:tcPr></w:tblStylePr><w:tblStylePr w:type=\"band1Horz\"><w:tcPr><w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"CCCCCC\"/></w:tcPr></w:tblStylePr><w:tblStylePr w:type=\"lastRow\"><w:tcPr><w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"FF0000\"/></w:tcPr></w:tblStylePr></w:style></w:styles>")
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

    func testTotalRowFillAppearsWhenTheSwitchIsOn() throws {
        let c = try styled()
        let black = Color(0xFF000000), grey = Color(0xFFCCCCCC), red = Color(0xFFFF0000)
        XCTAssertEqual(fills(c), [black, grey, nil], "Total Row is off in Word's default look")
        c.selection = RichSelection(anchor: RichPosition(paragraph: 0, offset: 0), focus: RichPosition(paragraph: 0, offset: 0))
        c.setTableLook(TableLook.lastRow, on: true)
        XCTAssertEqual(fills(c), [black, grey, red])
        c.undo()
        XCTAssertEqual(fills(c), [black, grey, nil])
    }

    func testEveryConditionalPartIsAppliedInWordsOrder() {
        let f = TableCondFills(byType: ["band1Vert": Color(1), "band2Vert": Color(2), "band1Horz": Color(3), "band2Horz": Color(4),
                                        "firstCol": Color(5), "lastCol": Color(6), "firstRow": Color(7), "lastRow": Color(8),
                                        "nwCell": Color(9), "seCell": Color(10)], rowBandSize: 1, colBandSize: 1)
        let all = TableLook.firstRow | TableLook.lastRow | TableLook.firstColumn | TableLook.lastColumn
        func at(_ r: Int, _ c: Int, _ look: Int) -> Color? { f.fill(look: look, row: r, column: c, lastRow: r == 3, lastColumn: c == 3) }
        XCTAssertEqual(at(0, 0, all), Color(9), "corner over header over first column")
        XCTAssertEqual(at(3, 3, all), Color(10))
        XCTAssertEqual(at(0, 1, all), Color(7))
        XCTAssertEqual(at(3, 1, all), Color(8))
        XCTAssertEqual(at(1, 0, all), Color(5))
        XCTAssertEqual(at(1, 3, all), Color(6))
        XCTAssertEqual(at(1, 1, all), Color(1), "column bands over row bands (Word print); the first band starts after the first column")
        XCTAssertEqual(at(2, 2, all), Color(2))
        XCTAssertEqual(at(1, 1, all | TableLook.noColumnBands), Color(3), "row bands show when column bands are off")
        XCTAssertEqual(at(1, 1, all | TableLook.noRowBands), Color(1), "column bands show when row bands are off")
        XCTAssertEqual(at(1, 2, all | TableLook.noRowBands), Color(2))
        XCTAssertNil(at(1, 1, all | TableLook.noRowBands | TableLook.noColumnBands))
    }

    func testASavedAndReopenedFileHasOneTableNormalStyle() throws {
        let c = try styled()
        let out = try Zip.read(try DocxFormat.write(c.document, pageSetup: .letter))
        let styles = String(decoding: out.first { $0.name == "word/styles.xml" }!.data, as: UTF8.self)
        XCTAssertEqual(styles.components(separatedBy: "w:styleId=\"TableNormal\"").count - 1, 1)
    }

    func testWithoutABandSizeWordDrawsNoBandAndALargerSizeMakesTallerBands() {
        let bands = ["band1Horz": Color(3), "band2Horz": Color(4)]
        let look = TableLook.firstRow
        func at(_ f: TableCondFills, _ r: Int) -> Color? { f.fill(look: look, row: r, column: 1, lastRow: false, lastColumn: false) }
        let none = TableCondFills(byType: bands)
        XCTAssertNil(at(none, 1), "no w:tblStyleRowBandSize: no band")
        let two = TableCondFills(byType: bands, rowBandSize: 2)
        XCTAssertEqual([1, 2, 3, 4, 5].map { at(two, $0) }, [Color(3), Color(3), Color(4), Color(4), Color(3)])
    }
}
