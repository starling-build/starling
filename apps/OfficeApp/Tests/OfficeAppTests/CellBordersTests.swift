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
        let below = cell(c, here.row + 1, here.column)
        XCTAssertTrue(below.bordersXML!.containsSubstring("<w:top w:val=\"nil\"/>"), "the cell below loses the shared line too")
        let others = c.document.paragraphs.compactMap(\.cell).filter { !$0.sameCell(as: here) && !$0.sameCell(as: below) && !($0.row == here.row && $0.column == here.column - 1) }
        XCTAssertTrue(others.allSatisfy { $0.bordersXML == nil })
    }

    func testAnOuterSideAlsoSetsTheFacingSideOfTheNeighbourAcrossItInOneUndo() throws {
        let c = RichDocumentController(plainText: "")
        c.insertTable(rows: 3, columns: 3)
        let middle = c.document.paragraphs.firstIndex { $0.cell?.row == 1 && $0.cell?.column == 1 }!
        c.moveTo(RichPosition(paragraph: middle, offset: 0), extend: false)
        let before = c.document.paragraphs
        let red = CellBorderLine(style: "single", width: 1, color: Color(0xFFFF0000))
        c.setCellBorders([.top: .none, .bottom: red, .left: .none, .right: red])
        XCTAssertTrue(cell(c, 0, 1).bordersXML!.containsSubstring("<w:bottom w:val=\"nil\"/>"))
        XCTAssertTrue(cell(c, 2, 1).bordersXML!.containsSubstring("<w:top w:val=\"single\""))
        XCTAssertTrue(cell(c, 1, 0).bordersXML!.containsSubstring("<w:right w:val=\"nil\"/>"))
        XCTAssertTrue(cell(c, 1, 2).bordersXML!.containsSubstring("<w:left w:val=\"single\""))
        XCTAssertEqual(cell(c, 0, 1).edges?.bottom, false)
        for (r, k) in [(0, 0), (0, 2), (2, 0), (2, 2)] {
            XCTAssertNil(cell(c, r, k).bordersXML, "a corner cell shares no side with the block")
        }
        let saved = try DocxFormat.write(c.document, pageSetup: .letter)
        let back = try DocxFormat.read(saved).document
        let up = back.paragraphs.compactMap(\.cell).first { $0.row == 0 && $0.column == 1 }!
        XCTAssertTrue(up.bordersXML!.containsSubstring("<w:bottom w:val=\"nil\"/>"), "kept on save")
        c.undo()
        XCTAssertEqual(c.document.paragraphs, before, "one undo takes the neighbours back too")
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
        // The file has no theme of its own: the app writes the palette it drew with, so Word shows the same colours.
        let zip = try Zip.read(saved)
        let themeData = try XCTUnwrap(zip.first { $0.name == "word/theme/theme1.xml" }?.data, "a theme-linked colour needs a theme part")
        XCTAssertTrue(String(decoding: themeData, as: UTF8.self).containsSubstring("<a:accent1><a:srgbClr val=\"4472C4\"/>"))
        XCTAssertTrue(String(decoding: try XCTUnwrap(zip.first { $0.name == "[Content_Types].xml" }?.data), as: UTF8.self).containsSubstring("/word/theme/theme1.xml"))
        XCTAssertTrue(String(decoding: try XCTUnwrap(zip.first { $0.name == "word/_rels/document.xml.rels" }?.data), as: UTF8.self).containsSubstring("relationships/theme"))
        XCTAssertEqual(DocxFormat._themeColors["accent1"].map { [$0.0, $0.1, $0.2] }, [0x44, 0x72, 0xC4], "and reads back")
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

    func testThemeColoursPickedInTheDialogKeepTheirThemeLink() throws {
        let c = grid()
        selectAll(c)
        var v = BordersShadingValues()
        v.sides = [.bottom]
        v.pickLine(.theme(slot: 5, lumMod: 75, lumOff: 0))
        v.pickShading(.theme(slot: 4, lumMod: 40, lumOff: 60))
        v.apply(to: c)
        let saved = try DocxFormat.read(try DocxFormat.write(c.document, pageSetup: .letter)).document.paragraphs.compactMap(\.cell)
        XCTAssertTrue(saved.allSatisfy { $0.fillThemeAttrs == " w:themeFill=\"accent1\" w:themeFillTint=\"66\"" })
        XCTAssertTrue(saved.filter { $0.row == 1 }.allSatisfy { $0.bordersXML?.containsSubstring("w:themeColor=\"accent2\" w:themeShade=\"BF\"") == true })
        // A custom colour or "No Color" afterwards drops the link.
        v.pickShading(.rgb(0x123456)); v.pickLine(.rgb(0x654321))
        v.apply(to: c)
        XCTAssertTrue(c.document.paragraphs.compactMap(\.cell).allSatisfy { $0.fillThemeAttrs == nil && $0.fill == Color(0xFF123456) })
        XCTAssertFalse(cell(c, 1, 0).bordersXML!.containsSubstring("themeColor"))
    }

    func testSplitOfAMergedRowCellGivesEqualPiecesAndAddsGridlines() throws {
        let c = RichDocumentController(plainText: "")
        c.insertTable(rows: 2, columns: 3)
        let t = c.currentCell!.table
        let first = c.document.paragraphs.firstIndex { $0.cell != nil }!
        c.moveTo(RichPosition(paragraph: first, offset: 0), extend: false)
        c.moveTo(RichPosition(paragraph: c.document.paragraphs.firstIndex { $0.cell?.column == 2 }!, offset: 0), extend: true)
        c.mergeCells()
        c.moveTo(RichPosition(paragraph: first, offset: 0), extend: false)
        XCTAssertTrue(c.splitCell(columns: 2, rows: 1))
        let w = c.document.tableColumns[t]!
        XCTAssertEqual(w.count, 4, "a gridline is added at the middle of the merged cell")
        XCTAssertEqual(w[0] + w[1], w[2] + w[3], accuracy: 0.01)
        let top = c.document.paragraphs.compactMap(\.cell).filter { $0.row == 0 }
        let pieces = Set(top.map { "\($0.column),\($0.span)" })
        XCTAssertEqual(pieces, ["0,2", "2,2"], "two equal halves")
        let bottom = c.document.paragraphs.compactMap(\.cell).filter { $0.row == 1 }.map { "\($0.column),\($0.span)" }
        XCTAssertEqual(bottom, ["0,1", "1,2", "3,1"], "the row below keeps its cells' places on the finer grid")
        let back = try DocxFormat.read(try DocxFormat.write(c.document, pageSetup: .letter)).document
        XCTAssertEqual(back.columnCount(of: back.paragraphs.compactMap(\.cell).first!.table), 4)
        c.undo()
        XCTAssertEqual(c.document.columnCount(of: t), 3)
    }

    func testSplitCellInATableWithNoStoredWidthsKeepsTheNeighbourWide() {
        let c = RichDocumentController(plainText: "")
        c.insertTable(rows: 2, columns: 2)
        let t = c.currentCell!.table
        XCTAssertNil(c.document.tableColumns[t])
        c.moveTo(RichPosition(paragraph: c.document.paragraphs.firstIndex { $0.cell != nil }!, offset: 0), extend: false)
        XCTAssertTrue(c.splitCell(columns: 3, rows: 1))
        let w = c.document.tableColumns[t]!
        XCTAssertEqual(w.count, 4)
        XCTAssertEqual(w[3], w[0] * 3, accuracy: 0.01, "the old second column stays as wide as the three pieces together")
    }

    func testSplitCellIntoColumnsAndRowsKeepsTheGrid() throws {
        let c = RichDocumentController(plainText: "")
        c.insertTable(rows: 2, columns: 2)
        let t = c.currentCell!.table
        c.setTableColumnWidths(t, [200, 100])
        c.moveTo(RichPosition(paragraph: c.document.paragraphs.firstIndex { $0.cell != nil }!, offset: 0), extend: false)
        c.insertText("a")
        XCTAssertTrue(c.splitCell(columns: 3, rows: 2))
        func check(_ d: RichDocument, _ label: String) {
            let cells = d.paragraphs.compactMap(\.cell)
            let grid = Set(cells.map { "\($0.row),\($0.column),\($0.span),\($0.rowSpan)" })
            // 3 x 2 pieces of the split cell, the top right cell now two rows tall, the old bottom row below.
            let want: Set<String> = ["0,0,1,1", "0,1,1,1", "0,2,1,1", "1,0,1,1", "1,1,1,1", "1,2,1,1",
                                     "0,3,1,2", "2,0,3,1", "2,3,1,1"]
            XCTAssertEqual(grid, want, label)
            XCTAssertEqual(d.columnCount(of: t), 4, label)
        }
        check(c.document, "after split")
        XCTAssertEqual(c.document.tableColumns[t]?.count, 4)
        XCTAssertEqual(c.document.tableColumns[t]![0], 200.0 / 3, accuracy: 0.01)
        XCTAssertEqual(c.document.tableColumns[t]![3], 100, accuracy: 0.01)
        XCTAssertEqual(c.document.paragraphs.first { $0.cell != nil }?.text, "a", "the text stays in the first piece")
        let back = try DocxFormat.read(try DocxFormat.write(c.document, pageSetup: .letter)).document
        let tb = back.paragraphs.compactMap(\.cell).first!.table
        let cells = back.paragraphs.compactMap(\.cell)
        XCTAssertEqual(Set(cells.map { "\($0.row),\($0.column),\($0.span),\($0.rowSpan)" }).count, 9)
        XCTAssertEqual(back.columnCount(of: tb), 4)
        c.undo()
        XCTAssertEqual(c.document.columnCount(of: t), 2)
        XCTAssertEqual(c.document.tableColumns[t], [200, 100])
        XCTAssertEqual(c.document.paragraphs.compactMap(\.cell).count, 4, "one undo puts the cell back")
    }

    func testSplitMergedCellBackIntoItsColumns() {
        let c = RichDocumentController(plainText: "")
        c.insertTable(rows: 2, columns: 3)
        c.moveTo(RichPosition(paragraph: c.document.paragraphs.firstIndex { $0.cell != nil }!, offset: 0), extend: false)
        c.selectRow()
        c.mergeCells()
        XCTAssertEqual(c.currentCell?.span, 3)
        XCTAssertTrue(c.splitCell(columns: 3, rows: 1))
        XCTAssertEqual(c.document.columnCount(of: c.currentCell!.table), 3)
        XCTAssertEqual(Set(c.document.paragraphs.compactMap(\.cell).filter { $0.row == 0 }.map(\.column)).count, 3)
        XCTAssertFalse(c.splitCell(columns: 1, rows: 1))
    }
}
