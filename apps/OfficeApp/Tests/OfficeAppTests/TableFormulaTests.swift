import XCTest
@testable import OfficeApp
@testable import OfficeText

/// W-TB-6: Layout > Formula.
final class TableFormulaTests: XCTestCase {
    private func table(_ rows: [[String]]) -> RichDocumentController {
        let c = RichDocumentController(plainText: "")
        c.insertTable(rows: rows.count, columns: rows[0].count)
        let idx = c.document.paragraphs.indices.filter { c.document.paragraphs[$0].cell != nil }
        for (k, i) in idx.enumerated() where !rows[k / rows[0].count][k % rows[0].count].isEmpty {
            c.moveTo(RichPosition(paragraph: i, offset: 0), extend: false)
            c.insertText(rows[k / rows[0].count][k % rows[0].count])
        }
        return c
    }
    private func goTo(_ c: RichDocumentController, row: Int, column: Int) {
        let i = c.document.paragraphs.firstIndex { $0.cell?.row == row && $0.cell?.column == column }!
        c.moveTo(RichPosition(paragraph: i, offset: 0), extend: false)
    }

    func testSumAboveStopsAtTheFirstEmptyCellAndSkipsText() {
        let f = TableFormula(grid: [["9"], [""], ["Item"], ["1,200.50"], ["3"], [""]], row: 5, column: 0)
        XCTAssertEqual(f.evaluate("=SUM(ABOVE)"), 1203.5)
    }

    /// Word's own prints of the formula lab (2026-11-25).
    func testWordSkipsLeadingBlanksAndTextThenStopsAtTheNextBlankOrText() {
        XCTAssertEqual(TableFormula(grid: [["100"], [""], ["50"], [""]], row: 3, column: 0).evaluate("=SUM(ABOVE)"), 50)
        XCTAssertEqual(TableFormula(grid: [["100"], [""], ["50"], ["x"], [""]], row: 4, column: 0).evaluate("=SUM(ABOVE)"), 50)
        XCTAssertEqual(TableFormula(grid: [["Head"], ["3"], ["x"], ["2"], [""]], row: 4, column: 0).evaluate("=SUM(ABOVE)"), 2)
        XCTAssertEqual(TableFormula(grid: [["Head", "3", "2", "x", "5", ""]], row: 0, column: 5).evaluate("=SUM(LEFT)"), 5)
        XCTAssertEqual(TableFormula(grid: [["", "x", "3", "2", ""]], row: 0, column: 4).evaluate("=SUM(LEFT)"), 5)
        let f = TableFormula(grid: [["1", "2"], ["3", "4"]], row: 1, column: 1)
        XCTAssertEqual(f.evaluate("=A1+B2"), 5)
        XCTAssertEqual(f.evaluate("=SUM(A1:B2)"), 10)
        XCTAssertEqual(f.evaluate("=AVERAGE(A1:B2)"), 2.5)
        XCTAssertEqual(f.evaluate("=MAX(A1:B2)-MIN(A1:B2)"), 3)
        XCTAssertEqual(f.evaluate("=5/2"), 2.5)
    }

    func testFunctionsAndReferences() {
        let f = TableFormula(grid: [["1", "2", "3"], ["4", "5", ""]], row: 1, column: 2)
        XCTAssertEqual(f.evaluate("=SUM(LEFT)"), 9)
        XCTAssertEqual(f.evaluate("=PRODUCT(ABOVE)"), 3)
        XCTAssertEqual(f.evaluate("=AVERAGE(A1:B2)"), 3)
        XCTAssertEqual(f.evaluate("=MAX(A1:C1)+MIN(A2,B2)"), 7)
        XCTAssertEqual(f.evaluate("=(A1+B1)*C1/2"), 4.5)
        XCTAssertNil(f.evaluate("=SUM(NOPE)"))
        XCTAssertNil(f.evaluate("=1/0"))
    }

    func testNumberPictures() {
        XCTAssertEqual(TableFormula.format(1234.5, picture: "0.00"), "1234.50")
        XCTAssertEqual(TableFormula.format(1234.5, picture: "#,##0.00"), "1,234.50")
        XCTAssertEqual(TableFormula.format(0.256, picture: "0%"), "0%")
        XCTAssertEqual(TableFormula.format(-5, picture: "$#,##0.00;($#,##0.00)"), "($   5.00)")
        XCTAssertEqual(TableFormula.format(12, picture: ""), "12")
        XCTAssertEqual(TableFormula.format(2.5, picture: ""), "2.5")
        XCTAssertEqual(TableFormula.format(7, picture: "000"), "007")
    }

    func testTheFormulaIsAFieldWordCanUpdateAndSurvivesASave() throws {
        let c = table([["10"], ["20"], [""]])
        goTo(c, row: 2, column: 0)
        XCTAssertEqual(c.suggestedFormula, "=SUM(ABOVE)")
        XCTAssertTrue(c.insertFormula("=SUM(ABOVE)", picture: "0.00"))
        let cell = c.document.paragraphs.first { $0.cell?.row == 2 }!
        XCTAssertEqual(cell.text, "30.00")
        XCTAssertEqual(cell.runs.first?.style.field, "=SUM(ABOVE) \\# \"0.00\"")
        let xml = String(decoding: try Zip.read(try DocxFormat.write(c.document, pageSetup: .letter)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(xml.contains("=SUM(ABOVE) \\# &quot;0.00&quot;") || xml.contains("=SUM(ABOVE) \\# \"0.00\""))
        c.undo()
        XCTAssertEqual(c.document.paragraphs.first { $0.cell?.row == 2 }!.text, "")
    }

    func testNoFormulaOutsideATableOrWhenItCannotBeWorkedOut() {
        let plain = RichDocumentController(plainText: "x")
        XCTAssertFalse(plain.insertFormula("=SUM(ABOVE)"))
        let c = table([["a"], [""]])
        goTo(c, row: 1, column: 0)
        XCTAssertTrue(c.insertFormula("=SUM(ABOVE)"))
        XCTAssertEqual(c.document.paragraphs.first { $0.cell?.row == 1 }!.text, "0")
    }
}
