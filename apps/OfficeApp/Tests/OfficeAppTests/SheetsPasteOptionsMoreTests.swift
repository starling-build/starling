import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// X-CL-1: the rest of Excel's Paste Options menu (Keep Source Column Widths, No Borders, Values & Number
/// Formatting, Values & Source Formatting, Paste Link), each in place of the first paste, one undo.
final class SheetsPasteOptionsMoreTests: XCTestCase {
    /// A1 = 2 in a bordered, bold, "0.00" cell; B1 = A1*10; column A 30 wide.
    private func copied(_ c: WorkbookController) -> WorkbookController.Clip {
        c.setInput("2", at: CellAddress("A1")!); c.setInput("=A1*10", at: CellAddress("B1")!)
        c.select(range: CellRange("A1:A1")!)
        c.setStyle { $0.bold = true; $0.numberFormat = "0.00"; $0.borders.top = true; $0.borders.bottom = true }
        c.sheet.colWidths[0] = 30
        c.select(range: CellRange("A1:B1")!, active: CellAddress("A1")!)
        return c.clip(cut: false, text: "")
    }
    private func at(_ c: WorkbookController, _ a: String) -> Cell? { c.sheet.cells[CellAddress(a)!] }
    private func style(_ c: WorkbookController, _ a: String) -> CellStyle { c.style(at: CellAddress(a)!) }
    private func pasted(_ how: PasteSpecial) -> WorkbookController {
        let c = WorkbookController()
        let clip = copied(c)
        c.select(CellAddress("D1")!); c.pasteSpecial(clip, PasteSpecial())
        c.repaste(how)
        XCTAssertEqual(c.pasteOptions?.how, how)
        return c
    }

    func testKeepSourceColumnWidths() {
        let c = pasted(PasteSpecial(what: .allWithColumnWidths))
        XCTAssertEqual(c.sheet.colWidth(3), 30)
        XCTAssertNotNil(at(c, "E1")?.formula)
        XCTAssertTrue(style(c, "D1").bold)
        c.undo()
        XCTAssertNotEqual(c.sheet.colWidth(3), 30)
        XCTAssertNil(at(c, "D1"))
    }

    func testNoBordersKeepsTheRestOfTheFormat() {
        let c = pasted(PasteSpecial(what: .allExceptBorders))
        XCTAssertFalse(style(c, "D1").borders.top)
        XCTAssertFalse(style(c, "D1").borders.bottom)
        XCTAssertTrue(style(c, "D1").bold)
        XCTAssertEqual(style(c, "D1").numberFormat, "0.00")
        XCTAssertNotNil(at(c, "E1")?.formula)
    }

    func testValuesAndNumberFormatting() {
        let c = pasted(PasteSpecial(what: .valuesAndNumberFormats))
        XCTAssertNil(at(c, "E1")?.formula)
        XCTAssertEqual(at(c, "E1")?.value, .number(20))
        XCTAssertEqual(style(c, "D1").numberFormat, "0.00")
        XCTAssertFalse(style(c, "D1").bold)
        XCTAssertFalse(style(c, "D1").borders.top)
    }

    func testValuesAndSourceFormatting() {
        let c = pasted(PasteSpecial(what: .valuesAndFormats))
        XCTAssertNil(at(c, "E1")?.formula)
        XCTAssertEqual(at(c, "E1")?.value, .number(20))
        XCTAssertTrue(style(c, "D1").bold)
        XCTAssertTrue(style(c, "D1").borders.top)
    }

    func testPasteLinkRefersToTheSource() {
        let c = pasted(PasteSpecial(link: true))
        XCTAssertEqual(at(c, "D1")?.input, "=A1")
        XCTAssertEqual(at(c, "E1")?.input, "=B1")
        XCTAssertEqual(at(c, "E1")?.value, .number(20))
        c.setInput("3", at: CellAddress("A1")!)
        XCTAssertEqual(at(c, "D1")?.value, .number(3))
        c.undo(); c.undo()
        XCTAssertNil(at(c, "D1"))
    }

    func testPasteLinkFromAnotherSheetNamesIt() {
        let c = WorkbookController()
        let clip = copied(c)
        c.addSheet()
        c.select(CellAddress("A1")!); c.pasteSpecial(clip, PasteSpecial(link: true))
        XCTAssertEqual(at(c, "A1")?.input, "=Sheet1!A1")
        XCTAssertEqual(at(c, "B1")?.value, .number(20))
    }

    func testTheMenuOffersAllEleven() {
        XCTAssertEqual(SheetsShellState.pasteOptionChoices.map(\.0), [
            "Paste", "Formulas", "Formulas & Number Formatting", "Keep Source Column Widths", "No Borders", "Transpose",
            "Values", "Values & Number Formatting", "Values & Source Formatting", "Formatting", "Paste Link",
        ])
    }
}
