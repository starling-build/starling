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
        c.setCellBorders([.top: CellBorderLine(style: "double", width: 2, color: Color(0xFFFF0000)), .insideV: CellBorderLine()])
        XCTAssertTrue(cell(c, 0, 1).bordersXML!.containsSubstring("<w:top w:val=\"double\" w:sz=\"16\""))
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

    func testThemeColoursOfBordersAndShadingSurviveASave() throws {
        XCTAssertEqual(WordTheme.attrs(slot: 4, lumMod: 100, lumOff: 0, fill: true), " w:themeFill=\"accent1\"")
        XCTAssertEqual(WordTheme.attrs(slot: 5, lumMod: 60, lumOff: 40, fill: true), " w:themeFill=\"accent2\" w:themeFillTint=\"99\"")
        XCTAssertEqual(WordTheme.attrs(slot: 5, lumMod: 75, lumOff: 0, fill: false), " w:themeColor=\"accent2\" w:themeShade=\"BF\"")
        XCTAssertEqual(WordTheme.attrs(slot: 4, lumMod: 20, lumOff: 80, fill: false), " w:themeColor=\"accent1\" w:themeTint=\"33\"")
        let c = grid()
        selectAll(c)
        c.setCellBorders([.bottom: CellBorderLine(style: "single", width: 1, color: Color(0xFFC55A11),
                                                 themeAttrs: WordTheme.attrs(slot: 5, lumMod: 75, lumOff: 0, fill: false))])
        c.setCellShading(Color(0xFFB4C7E7), themeAttrs: WordTheme.attrs(slot: 4, lumMod: 40, lumOff: 60, fill: true))
        let saved = try DocxFormat.write(c.document, pageSetup: .letter)
        let back = try DocxFormat.read(saved).document
        let cells = back.paragraphs.compactMap(\.cell)
        XCTAssertTrue(cells.allSatisfy { $0.fill == Color(0xFFB4C7E7) && $0.fillThemeAttrs == " w:themeFill=\"accent1\" w:themeFillTint=\"66\"" })
        XCTAssertTrue(cells.filter { $0.row == 1 }.allSatisfy { $0.bordersXML?.containsSubstring("w:themeColor=\"accent2\"") == true && $0.bordersXML?.containsSubstring("w:themeShade=\"BF\"") == true })
        // Saving again keeps both.
        let again = try DocxFormat.read(try DocxFormat.write(back, pageSetup: .letter)).document.paragraphs.compactMap(\.cell)
        XCTAssertTrue(again.allSatisfy { $0.fillThemeAttrs?.containsSubstring("accent1") == true })
        // A plain colour afterwards drops the theme link; one undo restores it.
        let d = RichDocumentController(plainText: "")
        d.load(back)
        selectAll(d)
        d.setCellShading(Color(0xFFFF0000))
        XCTAssertTrue(d.document.paragraphs.compactMap(\.cell).allSatisfy { $0.fillThemeAttrs == nil })
        d.undo()
        XCTAssertTrue(d.document.paragraphs.compactMap(\.cell).allSatisfy { $0.fillThemeAttrs != nil })
    }
}
