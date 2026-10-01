// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Editing that moves cells, against what Excel does: inserting and
// deleting rows and columns (references follow, ranges grow and shrink,
// deleted ones become #REF!), fills and series, Ctrl+Enter, copy and cut,
// and undo over all of it.

import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

final class SheetsEditingTests: XCTestCase {
    private func a(_ s: String) -> CellAddress { CellAddress(s)! }

    private func book(_ cells: [String: String], sheets: [String] = ["Sheet1"]) -> WorkbookController {
        let c = WorkbookController()
        c.load(Workbook(sheets: sheets.map { Worksheet(name: $0) }))
        c.setInputs(cells.map { (CellAddress($0.key)!, $0.value) })
        return c
    }

    func testInsertRowsMovesCellsAndReferences() {
        let c = book(["A1": "1", "A2": "2", "A3": "3", "A4": "=SUM(A1:A3)", "B1": "=A3*10", "B2": "=$A$3"])
        c.insert(.rows, at: 1)                     // a blank row 2
        XCTAssertEqual(c.sheet.value(a("A3")), .number(2))
        XCTAssertEqual(c.input(a("A5")), "=SUM(A1:A4)")   // the range grew around the new row
        XCTAssertEqual(c.input(a("B1")), "=A4*10")
        XCTAssertEqual(c.input(a("B3")), "=$A$4")         // absolute references follow too
        XCTAssertEqual(c.sheet.value(a("A5")), .number(6))
        c.undo()
        XCTAssertEqual(c.input(a("A4")), "=SUM(A1:A3)")
        XCTAssertEqual(c.sheet.value(a("A2")), .number(2))
        c.redo()
        XCTAssertEqual(c.input(a("A5")), "=SUM(A1:A4)")
    }

    func testDeleteRowsShrinksRangesAndBreaksDeletedReferences() {
        let c = book(["A1": "1", "A2": "2", "A3": "3", "A4": "4", "B1": "=SUM(A1:A4)", "B2": "=A3", "C1": "=A2+A4"])
        c.delete(.rows, at: 2)                     // row 3 goes
        XCTAssertEqual(c.input(a("B1")), "=SUM(A1:A3)")
        XCTAssertEqual(c.sheet.value(a("B1")), .number(7))
        XCTAssertEqual(c.input(a("B2")), "=#REF!")
        XCTAssertEqual(c.sheet.value(a("B2")), .error(.ref))
        XCTAssertEqual(c.input(a("C1")), "=A2+A3")         // A4 moved up
        // A range wholly deleted is #REF! too.
        c.setInput("=SUM(A2:A3)", at: a("D1"))
        c.delete(.rows, at: 1, count: 2)
        XCTAssertEqual(c.input(a("D1")), "=SUM(#REF!)")
    }

    func testColumnsAndOtherSheets() {
        let c = book(["A1": "5", "B1": "6", "C1": "=A1+B1"], sheets: ["Data", "Report"])
        c.setInputs([(a("A1"), "=Data!B1*2"), (a("A2"), "=SUM(Data!A1:C1)")], sheet: 1)
        c.insert(.cols, at: 1, count: 2)           // two blank columns before B
        XCTAssertEqual(c.input(a("E1")), "=A1+D1")
        XCTAssertEqual(c.book.sheets[1].cells[a("A1")]?.input, "=Data!D1*2")
        XCTAssertEqual(c.book.sheets[1].cells[a("A2")]?.input, "=SUM(Data!A1:E1)")
        XCTAssertEqual(c.book.sheets[1].value(a("A1")), .number(12))
    }

    func testSizesAndMergesFollow() {
        let c = book(["A1": "x"])
        c.setRowHeight(4, 30)
        c.sheet.merges = [CellRange("B5:C6")!]
        c.insert(.rows, at: 0, count: 3)
        XCTAssertEqual(c.sheet.rowHeight(7), 30)
        XCTAssertEqual(c.sheet.merges, [CellRange("B8:C9")!])
        c.delete(.rows, at: 7)
        XCTAssertEqual(c.sheet.merges, [CellRange("B8:C8")!])  // one row of two columns is still a merge
        c.delete(.cols, at: 2)
        XCTAssertEqual(c.sheet.merges, [])                 // one cell is not
    }

    func testSheetEditsUndo() {
        let c = book(["A1": "=Other!A1"], sheets: ["Sheet1", "Other"])
        c.setInputs([(a("A1"), "9")], sheet: 1)
        c.deleteSheet(1)
        XCTAssertEqual(c.input(a("A1")), "=#REF!")
        c.undo()
        XCTAssertEqual(c.book.sheets.count, 2)
        XCTAssertEqual(c.sheet.value(a("A1")), .number(9))
        c.setColumnWidth(0, 120)
        c.undo()
        XCTAssertEqual(c.sheet.colWidth(0), Worksheet.defaultColWidth)
        c.addSheet()
        XCTAssertEqual(c.book.sheets.count, 3)
        c.undo()
        XCTAssertEqual(c.book.sheets.count, 2)
    }

    func testFillDownAndCtrlEnter() {
        let c = book(["A1": "1", "A2": "2", "A3": "3", "B1": "=A1*2"])
        c.select(range: CellRange("B1:B3")!)
        c.fillDown()
        XCTAssertEqual(c.input(a("B3")), "=A3*2")
        XCTAssertEqual(c.sheet.value(a("B3")), .number(6))
        c.select(range: CellRange("C1:C3")!, active: a("C1"))
        c.fillSelection(with: "=A1+1")
        XCTAssertEqual(c.input(a("C2")), "=A2+1")
        XCTAssertEqual(c.sheet.value(a("C3")), .number(4))
        c.undo()
        XCTAssertNil(c.sheet.cells[a("C2")])
    }

    func testSeriesFill() {
        let c = book(["A1": "1", "A2": "3", "B1": "Jan", "C1": "Item 7", "D1": "1/30/2026", "E1": "5", "F1": "=A1"])
        c.select(range: CellRange("A1:A2")!)
        c.fillSeries(to: CellRange("A1:A5")!)
        XCTAssertEqual((3 ... 5).map { c.sheet.value(CellAddress(row: $0 - 1, col: 0)) }, [.number(5), .number(7), .number(9)])
        c.select(a("B1")); c.fillSeries(to: CellRange("B1:B4")!)
        XCTAssertEqual(c.sheet.value(a("B4")), .text("Apr"))
        c.select(a("C1")); c.fillSeries(to: CellRange("C1:C3")!)
        XCTAssertEqual(c.sheet.value(a("C3")), .text("Item 9"))
        c.select(a("D1")); c.fillSeries(to: CellRange("D1:D3")!)
        XCTAssertEqual(c.sheet.value(a("D3")), .number(46054))    // 1/30/2026 is 46052; two days on, across the month end
        c.select(a("E1")); c.fillSeries(to: CellRange("E1:E3")!)
        XCTAssertEqual(c.sheet.value(a("E3")), .number(5))        // one number copies, as Excel's does
        c.select(a("F1")); c.fillSeries(to: CellRange("F1:F3")!)
        XCTAssertEqual(c.input(a("F3")), "=A3")                   // a formula fills shifted
    }

    func testCopyAndCutPaste() {
        let c = book(["A1": "10", "A2": "=A1*2", "B5": "=A2+A1"])
        c.select(range: CellRange("A1:A2")!)
        let copy = c.clip(cut: false, text: "")
        c.select(a("C3"))
        c.paste(copy)
        XCTAssertEqual(c.input(a("C4")), "=C3*2")                 // shifted by the distance
        XCTAssertEqual(c.sheet.value(a("C4")), .number(20))
        XCTAssertEqual(c.selection, CellRange("C3:C4")!)
        // A cut moves the cells; formulas that pointed at them follow.
        c.select(range: CellRange("A1:A2")!)
        let cut = c.clip(cut: true, text: "")
        c.select(a("D1"))
        c.paste(cut)
        XCTAssertNil(c.sheet.cells[a("A1")])
        XCTAssertEqual(c.input(a("D2")), "=D1*2")                 // the moved formula still reads its neighbour
        XCTAssertEqual(c.input(a("B5")), "=D2+D1")
        XCTAssertEqual(c.sheet.value(a("B5")), .number(30))
        c.undo()
        XCTAssertEqual(c.input(a("B5")), "=A2+A1")
        XCTAssertEqual(c.sheet.value(a("A1")), .number(10))
    }
}

extension SheetsEditingTests {
    func testFindAndReplace() {
        let c = WorkbookController()
        c.load(Workbook(sheets: [Worksheet(name: "One"), Worksheet(name: "Two")]))
        c.setInputs([(CellAddress("A1")!, "apple pie"), (CellAddress("B3")!, "=SUM(A1:A2)"), (CellAddress("C2")!, "Apple")])
        c.setInputs([(CellAddress("D4")!, "pineapple")], sheet: 1)
        c.select(CellAddress("A1")!)
        XCTAssertTrue(c.findNext("apple"))
        XCTAssertEqual(c.active, CellAddress("C2"))            // row by row: C2 comes before nothing else on row 2
        XCTAssertTrue(c.findNext("apple"))
        XCTAssertEqual(c.activeSheet, 1)                        // then the next sheet
        XCTAssertEqual(c.active, CellAddress("D4"))
        XCTAssertTrue(c.findNext("apple"))
        XCTAssertEqual(c.activeSheet, 0)                        // and round again
        XCTAssertEqual(c.active, CellAddress("A1"))
        XCTAssertTrue(c.findNext("sum("))                       // formulas are searched as written
        XCTAssertEqual(c.active, CellAddress("B3"))
        XCTAssertFalse(c.findNext("nothing like this"))
        XCTAssertEqual(c.replaceAll("APPLE", with: "pear"), 3)
        XCTAssertEqual(c.book.sheets[0].value(CellAddress("A1")!), .text("pear pie"))
        XCTAssertEqual(c.book.sheets[1].value(CellAddress("D4")!), .text("pinepear"))
        c.undo()
        XCTAssertEqual(c.book.sheets[0].value(CellAddress("C2")!), .text("Apple"))
    }
}

extension SheetsEditingTests {
    func testHtmlTableFromExcel() throws {
        // The shape Excel puts on the clipboard: classes in a <style> block,
        // conditional comments, &nbsp; and a colspan.
        let html = """
        <html xmlns:x="urn:schemas-microsoft-com:office:excel"><head><meta charset=utf-8>
        <style><!--table {mso-displayed-decimal-separator:"\\.";}
        .xl65 {font-weight:700; color:#C00000;}
        td.xl66 {background:yellow; text-align:center}
        --></style></head><body><!--StartFragment-->
        <table><tr><td class=xl65>Item</td><td class="xl66">Cost</td></tr>
        <tr><td>Rent&nbsp;&amp; bills</td><td x:num="1200" align=right>$1,200.00</td></tr>
        <tr><td colspan=2>Total</td><td>=SUM(C3)</td></tr></table><!--EndFragment--></body></html>
        """
        let rows = try XCTUnwrap(HtmlTable.parse(html))
        XCTAssertEqual(rows.map { $0.map(\.text) }, [["Item", "Cost"], ["Rent & bills", "$1,200.00"], ["Total", "", "=SUM(C3)"]])
        XCTAssertEqual(rows[0][0].style?.bold, true)
        XCTAssertEqual(rows[0][0].style?.color, 0xC00000)
        XCTAssertEqual(rows[0][1].style?.fill, 0xFFFF00)
        XCTAssertEqual(rows[0][1].style?.hAlign, .center)
        XCTAssertEqual(rows[1][1].style?.hAlign, .right)
        XCTAssertNil(rows[1][0].style)

        let c = WorkbookController()
        c.select(CellAddress("B2")!)
        c.pasteTable(rows)
        XCTAssertEqual(c.sheet.value(CellAddress("C3")!), .number(1200))
        XCTAssertTrue(c.style(at: CellAddress("B2")!).bold)
        XCTAssertEqual(c.sheet.value(CellAddress("D4")!), .number(1200))   // a formula goes in as written
        XCTAssertEqual(c.selection, CellRange(top: 1, left: 1, bottom: 3, right: 3))
        c.undo()                                                           // one step takes it all back
        XCTAssertTrue(c.sheet.cells.isEmpty)
    }

    func testHtmlTableRoundTrip() throws {
        let c = WorkbookController()
        c.setInputs([(CellAddress("A1")!, "Name"), (CellAddress("B1")!, "12.5"), (CellAddress("A2")!, "<b> & co")])
        c.select(range: CellRange(top: 0, left: 0, bottom: 0, right: 0))
        c.setStyle { $0.bold = true; $0.fill = 0x00FF00 }
        let r = CellRange(top: 0, left: 0, bottom: 1, right: 1)
        let html = HtmlTable.render(c, r, rows: 0 ... 1, cols: 0 ... 1)
        let rows = try XCTUnwrap(HtmlTable.parse(html))
        XCTAssertEqual(rows.map { $0.map(\.text) }, [["Name", "12.5"], ["<b> & co", ""]])
        XCTAssertEqual(rows[0][0].style?.bold, true)
        XCTAssertEqual(rows[0][0].style?.fill, 0x00FF00)
        XCTAssertEqual(rows[0][1].style?.hAlign, .right)   // numbers go out right-aligned
        XCTAssertNil(HtmlTable.parse("<p>no table here</p>"))
        // Writer pastes it as a table, the bold kept.
        let paras = try XCTUnwrap(HtmlFormat.parse(html))
        let name = try XCTUnwrap(paras.first { $0.text == "Name" })
        XCTAssertNotNil(name.cell)
        XCTAssertTrue(name.style(at: 0).bold)
        XCTAssertNotNil(paras.first { $0.text == "12.5" }?.cell)
    }
}

extension SheetsEditingTests {
    func testEnterAfterTabsReturnsToTheFirstColumn() {
        let c = WorkbookController()
        c.select(CellAddress("B2")!)
        c.advance(rows: 0, cols: 1)
        c.advance(rows: 0, cols: 1)
        XCTAssertEqual(c.active, CellAddress("D2"))
        c.advance(rows: 1, cols: 0)
        XCTAssertEqual(c.active, CellAddress("B3"))     // back under where the Tabs began
        c.advance(rows: 1, cols: 0)
        XCTAssertEqual(c.active, CellAddress("B4"))
        c.advance(rows: 0, cols: 1)
        c.select(CellAddress("E9")!)                      // a click forgets the run
        c.advance(rows: 1, cols: 0)
        XCTAssertEqual(c.active, CellAddress("E10"))
    }
}

extension SheetsEditingTests {
    func testRenamingASheetCarriesItsNames() {
        let c = WorkbookController()
        c.book.names["TOTALS"] = "Sheet1!$A$1:$A$3"
        c.setInputs([(CellAddress("B1")!, "=SUM(Sheet1!A1:A3)")])
        XCTAssertTrue(c.renameSheet(0, "Data"))
        XCTAssertEqual(c.book.names["TOTALS"], "Data!$A$1:$A$3")
        XCTAssertEqual(c.input(CellAddress("B1")!), "=SUM(Data!A1:A3)")
    }
}

extension SheetsEditingTests {
    func testKeptElementsMoveWithTheirCells() {
        let c = WorkbookController()
        c.sheet.keptElements = [
            ("conditionalFormatting", "<conditionalFormatting sqref=\"B2:B10 D5\"><cfRule type=\"expression\" dxfId=\"0\" priority=\"1\"><formula>B2&gt;C$1</formula></cfRule></conditionalFormatting>"),
            ("conditionalFormatting", "<conditionalFormatting sqref=\"A3\"><cfRule type=\"cellIs\" dxfId=\"1\" priority=\"2\" operator=\"greaterThan\"><formula>5</formula></cfRule></conditionalFormatting>"),
            ("dataValidations", "<dataValidations count=\"2\"><dataValidation type=\"list\" sqref=\"E3\"><formula1>$H$1:$H$4</formula1></dataValidation><dataValidation type=\"whole\" sqref=\"F7:F9\"/></dataValidations>"),
            ("hyperlinks", "<hyperlinks><hyperlink ref=\"A3\" r:id=\"rId1\"/></hyperlinks>"),
        ]
        c.insert(.rows, at: 0)
        XCTAssertEqual(c.sheet.keptElements[0].text,
                       "<conditionalFormatting sqref=\"B3:B11 D6\"><cfRule type=\"expression\" dxfId=\"0\" priority=\"1\"><formula>B3&gt;C$2</formula></cfRule></conditionalFormatting>")
        XCTAssertTrue(c.sheet.keptElements[2].text.containsSubstring("sqref=\"E4\"><formula1>$H$2:$H$5</formula1>"))
        XCTAssertTrue(c.sheet.keptElements[3].text.containsSubstring("ref=\"A4\""))
        // Deleting row 4 (A4, E4) takes what lived only there.
        c.delete(.rows, at: 3)
        XCTAssertEqual(c.sheet.keptElements.map(\.name), ["conditionalFormatting", "dataValidations"])
        XCTAssertTrue(c.sheet.keptElements[1].text.hasPrefix("<dataValidations count=\"1\"><dataValidation type=\"whole\" sqref=\"F7:F9\"/>"),
                      c.sheet.keptElements[1].text)
        c.undo()
        XCTAssertEqual(c.sheet.keptElements.count, 4)
    }
}

extension SheetsEditingTests {
    func testExtensionsAndBreaksMoveWithTheirCells() {
        let c = WorkbookController()
        c.load(Workbook(sheets: [Worksheet(name: "Data"), Worksheet(name: "Summary")]))
        let summary = c.book.sheets[1]
        // A sparkline on Summary reads Data; an x14 rule on Data reads Data.
        summary.keptElements = [("extLst", "<extLst><ext><x14:sparklineGroups><x14:sparklineGroup><x14:sparklines><x14:sparkline><xm:f>Data!B2:F2</xm:f><xm:sqref>A1</xm:sqref></x14:sparkline></x14:sparklines></x14:sparklineGroup></x14:sparklineGroups></ext></extLst>")]
        c.sheet.keptElements = [
            ("rowBreaks", "<rowBreaks count=\"2\" manualBreakCount=\"2\"><brk id=\"10\" max=\"16383\" man=\"1\"/><brk id=\"30\" max=\"16383\" man=\"1\"/></rowBreaks>"),
            ("extLst", "<extLst><ext><x14:conditionalFormattings><x14:conditionalFormatting><x14:cfRule type=\"expression\"><xm:f>$B3&gt;0</xm:f></x14:cfRule><xm:sqref>B3:B20</xm:sqref></x14:conditionalFormatting></x14:conditionalFormattings></ext></extLst>"),
        ]
        c.insert(.rows, at: 0, count: 2)                 // on Data
        XCTAssertTrue(summary.keptElements[0].text.containsSubstring("<xm:f>Data!B4:F4</xm:f><xm:sqref>A1</xm:sqref>"), summary.keptElements[0].text)
        XCTAssertTrue(c.sheet.keptElements[1].text.containsSubstring("<xm:f>$B5&gt;0</xm:f></x14:cfRule><xm:sqref>B5:B22</xm:sqref>"), c.sheet.keptElements[1].text)
        XCTAssertTrue(c.sheet.keptElements[0].text.containsSubstring("<brk id=\"12\"") && c.sheet.keptElements[0].text.containsSubstring("<brk id=\"32\""), c.sheet.keptElements[0].text)
        c.delete(.rows, at: 12)                          // the row the first break came before
        XCTAssertTrue(c.sheet.keptElements[0].text.hasPrefix("<rowBreaks count=\"1\" manualBreakCount=\"1\"><brk id=\"31\""), c.sheet.keptElements[0].text)
        _ = c.renameSheet(0, "Figures")
        XCTAssertTrue(summary.keptElements[0].text.containsSubstring("<xm:f>Figures!B4:F4</xm:f>"), summary.keptElements[0].text)
    }
}

extension SheetsEditingTests {
    func testLinks() {
        let c = WorkbookController()
        c.load(Workbook(sheets: [Worksheet(name: "One"), Worksheet(name: "Two Sheet")]))
        c.sheet.linkTargets = ["rId1": "https://example.com/x"]
        c.sheet.keptElements = [("hyperlinks", "<hyperlinks><hyperlink ref=\"A1\" r:id=\"rId1\"/><hyperlink ref=\"B2:B3\" location=\"'Two Sheet'!C5\" display=\"go\"/></hyperlinks>")]
        c.setInputs([(CellAddress("D1")!, "=HYPERLINK(\"https://example.org\",\"Example\")")])
        XCTAssertEqual(c.link(at: CellAddress("A1")!), .url("https://example.com/x"))
        XCTAssertEqual(c.link(at: CellAddress("B3")!), .place("'Two Sheet'!C5"))
        XCTAssertEqual(c.link(at: CellAddress("D1")!), .url("https://example.org"))
        XCTAssertEqual(c.sheet.value(CellAddress("D1")!), .text("Example"))
        XCTAssertNil(c.link(at: CellAddress("C9")!))
        XCTAssertTrue(c.go(to: "'Two Sheet'!C5"))
        XCTAssertEqual(c.activeSheet, 1)
        XCTAssertEqual(c.active, CellAddress("C5"))
        XCTAssertFalse(c.go(to: "Nowhere!Z"))
    }
}

extension SheetsEditingTests {
    func testProtectedSheets() throws {
        let c = WorkbookController()
        // Format 1 unlocks its cells; the sheet is protected, but lets rows be inserted.
        c.book.styleSource = StyleSource(xfs: [StyleSource.Xf(attrs: [:], extra: ""),
                                               StyleSource.Xf(attrs: [:], protection: "<protection locked=\"0\"/>", extra: "")])
        c.book.styles = [CellStyle(baseXf: 0), CellStyle(baseXf: 1)]
        c.sheet.cells[CellAddress("B2")!] = Cell(input: "", style: 1)
        c.sheet.keptElements = [("sheetProtection", "<sheetProtection password=\"CC3D\" sheet=\"1\" objects=\"1\" scenarios=\"1\" insertRows=\"0\"/>")]
        var said: [String] = []
        c.onCommand = { if case .status(let m) = $0 { said.append(m) } }
        c.setInputs([(CellAddress("A1")!, "no")])
        XCTAssertNil(c.sheet.cells[CellAddress("A1")!])
        XCTAssertEqual(said.last, WorkbookController.protectedMessage)
        c.setInputs([(CellAddress("B2")!, "yes")])                   // an unlocked cell
        XCTAssertEqual(c.sheet.value(CellAddress("B2")!), .text("yes"))
        c.select(CellAddress("B2")!)
        c.setStyle { $0.bold = true }                                // formatting is not allowed
        XCTAssertFalse(c.style(at: CellAddress("B2")!).bold)
        c.insert(.rows, at: 0)                                       // inserting rows is
        XCTAssertEqual(c.sheet.value(CellAddress("B3")!), .text("yes"))
        c.delete(.rows, at: 0)                                       // deleting them is not
        XCTAssertEqual(c.sheet.value(CellAddress("B3")!), .text("yes"))
    }
}
