import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp
@testable import OfficeText

/// W-TB-2: borders and shading, per cell and per side.
final class CellBordersTests: XCTestCase {
    private func grid() -> RichDocumentController {
        let c = RichDocumentController(plainText: "")
        c.insertTable(rows: 2, columns: 3)
        return c
    }
    private func cell(_ c: RichDocumentController, _ r: Int, _ k: Int) -> CellRef {
        c.document.paragraphs.compactMap(\.cell).first { $0.row == r && $0.column == k }!
    }
    private func selectAll(_ c: RichDocumentController) {
        let last = c.document.paragraphs.lastIndex { $0.cell != nil }!
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        c.moveTo(RichPosition(paragraph: last, offset: 0), extend: true)
    }

    func testShadingAndOuterBordersOfTheSelectedCellsAreOneUndo() {
        let c = grid()
        selectAll(c)
        let before = c.document.paragraphs
        c.setCellShading(Color(0xFFFFE699))
        XCTAssertTrue(c.document.paragraphs.compactMap(\.cell).allSatisfy { $0.fill == Color(0xFFFFE699) })
        c.undo()
        XCTAssertEqual(c.document.paragraphs, before)
        c.setCellBorders([.top: CellBorderLine(style: "double", width: 2.25, color: Color(0xFFFF0000)), .insideV: CellBorderLine()])
        XCTAssertTrue(cell(c, 0, 1).bordersXML!.containsSubstring("<w:top w:val=\"double\" w:sz=\"18\""))
        XCTAssertNil(cell(c, 1, 1).bordersXML.flatMap { $0.containsSubstring("<w:top") ? $0 : nil }, "only the block's top row gets the top line")
        XCTAssertTrue(cell(c, 0, 0).bordersXML!.containsSubstring("<w:right "), "inside verticals: right of the first column")
        XCTAssertFalse(cell(c, 0, 0).bordersXML!.containsSubstring("<w:left "))
        XCTAssertTrue(cell(c, 0, 2).bordersXML!.containsSubstring("<w:left "))
        c.undo()
        XCTAssertEqual(c.document.paragraphs, before, "one undo takes all the cells back")
    }

    func testOneCellOnlyAndNoneRemovesALine() {
        let c = grid()
        c.moveTo(RichPosition(paragraph: 1, offset: 0), extend: false)
        let here = c.currentCell!
        c.setCellBorders([.bottom: CellBorderLine(style: "dashed", width: 1)])
        c.setCellBorders([.bottom: .none, .left: CellBorderLine()])
        let xml = c.currentCell!.bordersXML!
        XCTAssertTrue(xml.containsSubstring("<w:bottom w:val=\"nil\"/>"))
        XCTAssertTrue(xml.firstRange(of: "<w:left ")!.lowerBound < xml.firstRange(of: "<w:bottom ")!.lowerBound, "schema order")
        let others = c.document.paragraphs.compactMap(\.cell).filter { !$0.sameCell(as: here) }
        XCTAssertTrue(others.allSatisfy { $0.bordersXML == nil })
    }

    func testBordersAndShadingSurviveASaveWithTheirNeighbours() throws {
        let c = grid()
        c.insertText("a"); c.moveToAdjacentCell(forward: true); c.insertText("b")
        selectAll(c)
        c.setCellBorders([.bottom: CellBorderLine(style: "single", width: 1.5, color: Color(0xFF00AA00))])
        c.setCellShading(Color(0xFFDDEEFF))
        let saved = try DocxFormat.write(c.document, pageSetup: .letter)
        let back = try DocxFormat.read(saved).document
        XCTAssertEqual(back.paragraphs.map(\.text).filter { !$0.isEmpty }, ["a", "b"])
        let cells = back.paragraphs.compactMap(\.cell)
        XCTAssertTrue(cells.allSatisfy { $0.fill == Color(0xFFDDEEFF) })
        let bottomRow = cells.filter { $0.row == 1 }
        XCTAssertTrue(bottomRow.allSatisfy { $0.bordersXML?.containsSubstring("w:sz=\"12\" w:val=\"single\"") == true && $0.bordersXML?.containsSubstring("00AA00") == true })
        XCTAssertTrue(cells.filter { $0.row == 0 }.allSatisfy { $0.bordersXML == nil })
        XCTAssertEqual(Set(cells.map(\.table)).count, 1)
        XCTAssertEqual(back.tableColumns.values.first?.count, 3, "the grid is untouched")
    }

    func testHeavyBorderIsASingleLineWithItsWidth() throws {
        let c = grid()
        c.insertText("a")
        c.setCellBorders([.right: CellBorderLine(style: "single", width: 4.5, color: nil)])
        let back = try DocxFormat.read(try DocxFormat.write(c.document, pageSetup: .letter)).document
        let xml = back.paragraphs.compactMap(\.cell).first { $0.row == 0 && $0.column == 0 }?.bordersXML ?? ""
        XCTAssertTrue(xml.containsSubstring("w:sz=\"36\""))
        XCTAssertFalse(xml.containsSubstring("thick"))
        XCTAssertEqual(CellBorderLine(style: "thick", width: 1).style, "single", "an unknown style is a single line")
        XCTAssertEqual(CellBorderLine(width: 4).width, 4.5, "Word rounds 4 pt to 4.5")
        XCTAssertEqual(CellBorderLine(width: 2).width, 2.25)
        XCTAssertEqual(CellBorderLine(width: 12).width, 6)
    }

    func testVerticalAlignmentOfASelectedRowSetsEveryCell() throws {
        let c = grid()
        c.moveTo(RichPosition(paragraph: c.document.paragraphs.firstIndex { $0.cell?.row == 1 }!, offset: 0), extend: false)
        c.selectRow()
        c.setCellVerticalAlignment("center")
        let back = try DocxFormat.read(try DocxFormat.write(c.document, pageSetup: .letter)).document
        let cells = back.paragraphs.compactMap(\.cell)
        XCTAssertEqual(cells.filter { $0.row == 1 }.map(\.verticalAlign), ["center", "center", "center"])
        XCTAssertTrue(cells.filter { $0.row == 0 }.allSatisfy { $0.verticalAlign == nil })
    }

    func testSelectColumnAndTableAndInsertTableFit() {
        let c = grid()
        c.selectColumn()
        c.setCellShading(Color(0xFFDDEEFF))
        XCTAssertEqual(c.document.paragraphs.compactMap(\.cell).filter { $0.fill != nil }.map(\.column), [0, 0])
        c.selectTable()
        c.setCellShading(Color(0xFF112233))
        XCTAssertTrue(c.document.paragraphs.compactMap(\.cell).allSatisfy { $0.fill == Color(0xFF112233) })
        let d = RichDocumentController(plainText: "")
        d.insertTable(rows: 2, columns: 2, fit: .window)
        let id = d.document.paragraphs.compactMap(\.cell).first!.table
        XCTAssertEqual(d.document.tableStyles[id]?.widthPercent, 100)
        d.undo()
        XCTAssertTrue(d.document.paragraphs.compactMap(\.cell).isEmpty)
    }

    func testTwoTablesNeverTouch() throws {
        let c = RichDocumentController(plainText: "")
        c.insertTable(rows: 2, columns: 2)
        c.insertTable(rows: 2, columns: 3, fit: .window)   // caret is in the first table
        c.moveTo(RichPosition(paragraph: c.document.paragraphs.count - 1, offset: 0), extend: false)
        c.insertTable(rows: 1, columns: 1)                 // on the empty paragraph after a table
        let ps = c.document.paragraphs
        for i in 1 ..< ps.count where ps[i].cell != nil && ps[i - 1].cell != nil {
            XCTAssertEqual(ps[i].cell!.table, ps[i - 1].cell!.table, "a paragraph sits between tables")
        }
        XCTAssertEqual(Set(ps.compactMap(\.cell).map(\.table)).count, 3)
        // The writer also guards a document that already has them touching.
        var d = c.document
        d.paragraphs.removeAll { $0.cell == nil }
        let xml = try DocxFormat.write(d, pageSetup: .letter)
        let back = try DocxFormat.read(xml).document
        XCTAssertEqual(Set(back.paragraphs.compactMap(\.cell).map(\.table)).count, 3, "Word would merge them into one")
    }
}
