import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp
@testable import OfficeText

/// W-TB-3: table, row and cell properties, each one undo step and each kept by a save.
final class TablePropertiesTests: XCTestCase {
    private func grid() -> RichDocumentController {
        let c = RichDocumentController(plainText: "")
        c.insertTable(rows: 3, columns: 2)
        return c
    }
    private func roundTrip(_ c: RichDocumentController) throws -> RichDocument {
        try DocxFormat.read(try DocxFormat.write(c.document, pageSetup: .letter)).document
    }
    private func style(_ d: RichDocument) -> TableStyle { d.tableStyles.values.first ?? TableStyle() }

    func testTableLevelPropertiesSurviveASaveWithTheirNeighbours() throws {
        let c = grid()
        c.setTableWidth(percent: 80)
        c.setTableAlignment(.center)
        c.setTableIndent(12)
        c.setTableAutofit(false)
        c.setTableCellMargins(top: 2, left: 7, bottom: 3, right: 8)
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        c.moveTo(RichPosition(paragraph: c.document.paragraphs.lastIndex { $0.cell != nil }!, offset: 0), extend: true)
        c.setCellShading(Color(0xFFDDEEFF))
        let back = try roundTrip(c)
        let s = style(back)
        XCTAssertEqual(s.widthPercent, 80)
        XCTAssertEqual(s.alignment, .center)
        XCTAssertEqual(s.indent, 12)
        XCTAssertTrue(s.fixedLayout)
        XCTAssertEqual([s.cellMarginTop, s.cellMarginLeft, s.cellMarginBottom, s.cellMarginRight], [2, 7, 3, 8])
        XCTAssertTrue(back.paragraphs.compactMap(\.cell).allSatisfy { $0.fill == Color(0xFFDDEEFF) }, "the neighbour (shading) is kept")
        XCTAssertEqual(back.tableColumns.values.first?.count, 2)
        c.setTableWidth(points: 300)
        XCTAssertNil(c.currentTableStyle?.widthPercent)
        XCTAssertEqual(c.currentTableStyle?.width, 300)
        c.undo()
        XCTAssertEqual(c.currentTableStyle?.widthPercent, 80, "one undo per change")
    }

    func testANewTableWidthScalesTheColumnsSoTheCellsAskForIt() throws {
        // Lab tb3: Word opened an 80% table whose three cells each still asked for 156 pt, the full 468 pt text width.
        let c = grid()
        let t = c.currentCell!.table
        let before = c.document.tableColumns[t]
        c.setTableWidth(percent: 80)
        let cols = try XCTUnwrap(c.document.tableColumns[t])
        XCTAssertEqual(cols.reduce(0, +), 468 * 0.8, accuracy: 0.01)
        XCTAssertEqual(cols[0], cols[1], accuracy: 0.01, "the columns keep their proportions")
        let back = try roundTrip(c)
        XCTAssertEqual(back.tableColumns.values.first?.reduce(0, +) ?? 0, 374.4, accuracy: 0.1, "the saved cells ask for the table's width")
        c.setTableWidth(points: 300)
        XCTAssertEqual(c.document.tableColumns[t]?.reduce(0, +) ?? 0, 300, accuracy: 0.01)
        c.undo()
        c.undo()
        XCTAssertEqual(c.document.tableColumns[t], before, "the width and the columns come back in one undo each")
        XCTAssertNil(c.currentTableStyle?.widthPercent)
    }

    func testRowPropertiesApplyToTheSelectedRowsOnly() throws {
        let c = grid()
        c.moveTo(RichPosition(paragraph: 2, offset: 0), extend: false)   // row 1, column 0
        let row = c.currentCell!.row
        c.setRowHeight(40, exact: true)
        c.setRowsMayBreak(false)
        c.setRepeatedHeaderRows(1)
        let s = style(try roundTrip(c))
        XCTAssertEqual(s.rowHeights[row], 40)
        XCTAssertEqual(s.rowsExactHeight, [row])
        XCTAssertEqual(s.rowsCantSplit, [row])
        XCTAssertTrue(s.headerRow)
        XCTAssertNil(s.rowHeights[0], "other rows untouched")
        c.setRowHeight(nil)
        XCTAssertTrue(c.currentTableStyle?.rowHeights.isEmpty == true)
        XCTAssertTrue(c.currentTableStyle?.rowsExactHeight.isEmpty == true)
    }

    func testCellAlignmentAndTextDirectionAreForTheSelectedCellsAndSurviveASave() throws {
        let c = grid()
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        let last = c.document.paragraphs.lastIndex { $0.cell != nil }!
        c.moveTo(RichPosition(paragraph: last, offset: 0), extend: true)
        c.setCellVerticalAlignment("center")
        c.setCellTextDirection(.up)
        let cells = try roundTrip(c).paragraphs.compactMap(\.cell)
        XCTAssertTrue(cells.allSatisfy { $0.verticalAlign == "center" && $0.textDirection == .up })
        c.setCellVerticalAlignment("top")
        XCTAssertTrue(c.document.paragraphs.compactMap(\.cell).allSatisfy { $0.verticalAlign == nil })
        c.undo()
        XCTAssertTrue(c.document.paragraphs.compactMap(\.cell).allSatisfy { $0.verticalAlign == "center" })
    }
}
