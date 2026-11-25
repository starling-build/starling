import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp
@testable import OfficeText

/// W-TB-5: dragging a row's bottom border.
final class TableRowDragTests: XCTestCase {
    private func laidOut() -> (RichDocumentController, RichLayout) {
        let c = RichDocumentController(plainText: "")
        c.insertTable(rows: 3, columns: 2)
        let theme = RichTextTheme(fontFamily: OfficeFonts.serif)
        let layout = RichLayout(theme: theme, paragraphCount: c.document.paragraphs.count)
        layout.pageSetup = PageSetup.letter
        layout.width = PageSetup.letter.columnWidth * theme.pixelsPerPoint
        layout.ensureLaidOut(c.document)
        return (c, layout)
    }

    func testTheBottomBorderOfARowIsFoundAndTheMiddleOfItIsNot() throws {
        let (c, layout) = laidOut()
        let i = try XCTUnwrap(c.document.paragraphs.firstIndex { $0.cell?.row == 1 && $0.cell?.column == 0 })
        let g = try XCTUnwrap(layout._cells[i])
        let bottom = g.rowTop + g.rowHeight
        let hit = try XCTUnwrap(layout.rowBorder(at: Offset(g.colLeft + 6, bottom + 1)))
        XCTAssertEqual(hit.row, 1)
        XCTAssertEqual(hit.table, g.table)
        XCTAssertGreaterThan(hit.right, hit.left)
        XCTAssertNil(layout.rowBorder(at: Offset(g.colLeft + 6, g.rowTop + g.rowHeight / 2)))
        XCTAssertNil(layout.rowBorder(at: Offset(g.colLeft - 200, bottom)), "outside the table")
    }

    func testDraggingARowBorderIsOneUndoAndKeepsTheOtherRows() throws {
        let (c, _) = laidOut()
        let t = try XCTUnwrap(c.document.paragraphs.compactMap(\.cell).first?.table)
        c.setRowHeight(table: t, row: 1, points: 48)
        XCTAssertEqual(c.document.tableStyles[t]?.rowHeights[1], 48)
        XCTAssertNil(c.document.tableStyles[t]?.rowHeights[0])
        c.undo()
        XCTAssertNil(c.document.tableStyles[t]?.rowHeights[1])
        let saved = try DocxFormat.read(try { c.setRowHeight(table: t, row: 2, points: 30); return try DocxFormat.write(c.document, pageSetup: .letter) }()).document
        XCTAssertEqual(saved.tableStyles.values.first?.rowHeights[2], 30)
    }
}
