import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp
@testable import OfficeText

/// W-TB-9: Convert Text to Table and Table to Text.
final class ConvertTextTableTests: XCTestCase {
    private func texts(_ c: RichDocumentController) -> [String] { c.document.paragraphs.map(\.text) }
    private func selectAll(_ c: RichDocumentController) {
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        let last = c.document.paragraphs.count - 1
        c.moveTo(RichPosition(paragraph: last, offset: c.document.paragraphs[last].length), extend: true)
    }

    func testTabsMakeRowsAndCellsAndPadShortRows() {
        let c = RichDocumentController(plainText: "a\tb\tc\nd\te")
        selectAll(c)
        XCTAssertTrue(c.convertTextToTable(separator: .tab))
        let cells = c.document.paragraphs.filter { $0.cell != nil }
        XCTAssertEqual(cells.map(\.text), ["a", "b", "c", "d", "e", ""])
        XCTAssertEqual(c.document.columnCount(of: cells[0].cell!.table), 3)
        XCTAssertEqual(cells[5].cell?.row, 1)
        XCTAssertEqual(cells[5].cell?.column, 2)
    }

    func testCommaAndOtherSeparators() {
        let c = RichDocumentController(plainText: "x,y")
        selectAll(c)
        c.convertTextToTable(separator: .comma)
        XCTAssertEqual(c.document.paragraphs.filter { $0.cell != nil }.map(\.text), ["x", "y"])
        let d = RichDocumentController(plainText: "p;q;r")
        selectAll(d)
        d.convertTextToTable(separator: .other(";"))
        XCTAssertEqual(d.document.paragraphs.filter { $0.cell != nil }.map(\.text), ["p", "q", "r"])
    }

    func testParagraphSeparatorFillsRowsByColumnCount() {
        let c = RichDocumentController(plainText: "1\n2\n3\n4\n5")
        selectAll(c)
        c.convertTextToTable(separator: .paragraph, columns: 2)
        let cells = c.document.paragraphs.filter { $0.cell != nil }
        XCTAssertEqual(cells.map(\.text), ["1", "2", "3", "4", "5", ""])
        XCTAssertEqual(cells[2].cell?.row, 1)
        XCTAssertEqual(cells[2].cell?.column, 0)
    }

    func testOneUndoStepAndTheTableSurvivesASave() throws {
        let c = RichDocumentController(plainText: "a\tb\nc\td")
        selectAll(c)
        let before = texts(c)
        c.convertTextToTable(separator: .tab)
        let back = try DocxFormat.read(try DocxFormat.write(c.document, pageSetup: .letter)).document
        XCTAssertEqual(back.paragraphs.filter { $0.cell != nil }.map(\.text), ["a", "b", "c", "d"])
        c.undo()
        XCTAssertEqual(c.document.paragraphs.filter { $0.cell != nil }.count, 0)
        XCTAssertEqual(texts(c), before)
    }

    func testTableToTextWithTabsAndParagraphs() {
        let c = RichDocumentController(plainText: "")
        c.insertTable(rows: 2, columns: 2)
        let idx = c.document.paragraphs.indices.filter { c.document.paragraphs[$0].cell != nil }
        for (k, i) in idx.enumerated() {
            c.moveTo(RichPosition(paragraph: i, offset: 0), extend: false)
            c.insertText("c\(k)")
        }
        c.moveTo(RichPosition(paragraph: idx[0], offset: 0), extend: false)
        XCTAssertTrue(c.convertTableToText(separator: .tab))
        XCTAssertEqual(texts(c).filter { !$0.isEmpty }, ["c0\tc1", "c2\tc3"])
        XCTAssertNil(c.document.paragraphs.first { $0.cell != nil })
        c.undo()
        XCTAssertEqual(c.document.paragraphs.filter { $0.cell != nil }.count, 4)
        c.moveTo(RichPosition(paragraph: idx[0], offset: 0), extend: false)
        c.convertTableToText(separator: .paragraph)
        XCTAssertEqual(texts(c).filter { !$0.isEmpty }, ["c0", "c1", "c2", "c3"])
    }
}
