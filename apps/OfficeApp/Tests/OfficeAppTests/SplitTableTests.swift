import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp
@testable import OfficeText

/// Table > Split Table, and Split Cells' "Merge cells before split".
final class SplitTableTests: XCTestCase {
    private func table(rows: Int = 4, columns: Int = 2) -> RichDocumentController {
        let c = RichDocumentController(plainText: "")
        c.insertTable(rows: rows, columns: columns)
        let idx = c.document.paragraphs.indices.filter { c.document.paragraphs[$0].cell != nil }
        for (k, i) in idx.enumerated() { c.moveTo(RichPosition(paragraph: i, offset: 0), extend: false); c.insertText("t\(k)") }
        return c
    }
    private func goTo(_ c: RichDocumentController, row: Int, column: Int) {
        let i = c.document.paragraphs.firstIndex { $0.cell?.row == row && $0.cell?.column == column }!
        c.moveTo(RichPosition(paragraph: i, offset: 0), extend: false)
    }

    func testSplitMakesTwoTablesWithAParagraphBetween() {
        let c = table()
        c.setRowHeight(30)                       // row 0
        goTo(c, row: 2, column: 1)
        XCTAssertTrue(c.splitTable())
        let ps = c.document.paragraphs
        let ids = Set(ps.compactMap { $0.cell?.table })
        XCTAssertEqual(ids.count, 2)
        let firstEnd = ps.lastIndex { $0.cell?.row == 1 && $0.cell?.column == 1 && $0.text == "t3" }!
        XCTAssertNil(ps[firstEnd + 1].cell)
        XCTAssertEqual(ps[firstEnd + 1].text, "")
        let second = ps.filter { $0.cell != nil && $0.cell!.table != ps.first { $0.cell != nil }!.cell!.table }
        XCTAssertEqual(second.map(\.text), ["t4", "t5", "t6", "t7"])
        XCTAssertEqual(second.first?.cell?.row, 0)
        XCTAssertEqual(c.currentCell?.row, 0)
        XCTAssertEqual(c.currentTableStyle?.rowHeights, [1: 30])   // the caret was in row 3 when it was set
        c.undo()
        XCTAssertEqual(Set(c.document.paragraphs.compactMap { $0.cell?.table }).count, 1)
    }

    func testSplitInTheFirstRowOnlyAddsAParagraphAbove() {
        let c = table()
        goTo(c, row: 0, column: 0)
        XCTAssertTrue(c.splitTable())
        XCTAssertEqual(Set(c.document.paragraphs.compactMap { $0.cell?.table }).count, 1)
        XCTAssertNil(c.document.paragraphs[0].cell)
        XCTAssertEqual(c.currentCell?.row, 0)
    }

    func testNoSplitAcrossAVerticallyMergedCell() {
        let c = table()
        goTo(c, row: 1, column: 0)
        c.moveTo(RichPosition(paragraph: c.document.paragraphs.firstIndex { $0.cell?.row == 2 && $0.cell?.column == 0 }!, offset: 0), extend: true)
        c.mergeCells()
        goTo(c, row: 2, column: 1)
        XCTAssertFalse(c.canSplitTable)
        XCTAssertFalse(c.splitTable())
    }

    func testSplitTableSurvivesASave() throws {
        let c = table()
        goTo(c, row: 2, column: 0)
        c.splitTable()
        let back = try DocxFormat.read(try DocxFormat.write(c.document, pageSetup: .letter)).document
        XCTAssertEqual(Set(back.paragraphs.compactMap { $0.cell?.table }).count, 2)
        XCTAssertEqual(back.paragraphs.filter { $0.cell != nil }.count, 8)
    }

    func testNineAlignButtonsSetBothDirectionsInOneStep() {
        let c = table(rows: 2, columns: 2)
        goTo(c, row: 0, column: 1)
        c.setCellAlignment(vertical: "bottom", horizontal: .right)
        let cell = c.document.paragraphs.first { $0.cell?.row == 0 && $0.cell?.column == 1 }!
        XCTAssertEqual(cell.cell?.verticalAlign, "bottom")
        XCTAssertEqual(cell.style.alignment, .right)
        let other = c.document.paragraphs.first { $0.cell?.row == 0 && $0.cell?.column == 0 }!
        XCTAssertNil(other.cell?.verticalAlign)
        c.setCellAlignment(vertical: "top", horizontal: .center)
        XCTAssertNil(c.document.paragraphs.first { $0.cell?.row == 0 && $0.cell?.column == 1 }!.cell?.verticalAlign)
        c.undo()
        XCTAssertEqual(c.document.paragraphs.first { $0.cell?.row == 0 && $0.cell?.column == 1 }!.cell?.verticalAlign, "bottom")
    }

    func testSplitCellsAfterMergingASelection() {
        let c = table(rows: 2, columns: 2)
        goTo(c, row: 0, column: 0)
        c.moveTo(RichPosition(paragraph: c.document.paragraphs.firstIndex { $0.cell?.row == 0 && $0.cell?.column == 1 }!, offset: 0), extend: true)
        c.mergeCells()
        XCTAssertEqual(c.currentCell?.span, 2)
        XCTAssertTrue(c.splitCell(columns: 3, rows: 1))
        XCTAssertEqual(Set(c.document.paragraphs.filter { $0.cell?.row == 0 }.compactMap { $0.cell?.column }).count, 3)
    }
}

/// Writes the Word lab for Split Table / alignment when SPLIT_LAB_OUT names a file (skipped otherwise).
final class SplitTableLabWriter: XCTestCase {
    func testWriteLab() throws {
        guard let out = ProcessInfo.processInfo.environment["SPLIT_LAB_OUT"] else { throw XCTSkip("no SPLIT_LAB_OUT") }
        let c = RichDocumentController(plainText: "")
        c.insertTable(rows: 4, columns: 2)
        var idx = c.document.paragraphs.indices.filter { c.document.paragraphs[$0].cell != nil }
        for (k, i) in idx.enumerated() { c.moveTo(RichPosition(paragraph: i, offset: 0), extend: false); c.insertText("S\(k)") }
        c.moveTo(RichPosition(paragraph: idx[4], offset: 0), extend: false)
        XCTAssertTrue(c.splitTable())
        c.moveTo(RichPosition(paragraph: c.document.paragraphs.count - 1, offset: 0), extend: false)
        c.insertParagraphBreak()
        c.insertTable(rows: 3, columns: 3)
        idx = c.document.paragraphs.indices.filter { c.document.paragraphs[$0].cell != nil }.suffix(9).map { $0 }
        let v = ["top", "center", "bottom"], h: [ParagraphAlignment] = [.left, .center, .right]
        for (k, i) in idx.enumerated() {
            c.moveTo(RichPosition(paragraph: i, offset: 0), extend: false)
            c.insertText("\(v[k / 3])-\(k % 3)")
            if k % 3 == 0 { c.setRowHeight(48) }
            c.setCellAlignment(vertical: v[k / 3], horizontal: h[k % 3])
        }
        try DocxFormat.write(c.document, pageSetup: .letter).write(to: URL(fileURLWithPath: out))
    }
}
