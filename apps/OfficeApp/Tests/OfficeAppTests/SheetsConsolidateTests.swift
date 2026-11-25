import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// X-DA-6c: Data → Consolidate.
final class SheetsConsolidateTests: XCTestCase {
    private func book() -> WorkbookController {
        let c = WorkbookController()
        c.load(Workbook(sheets: [Worksheet(name: "Sum"), Worksheet(name: "East"), Worksheet(name: "West")]))
        c.setInputs([(CellAddress("A1")!, "Item"), (CellAddress("B1")!, "Qty"),
                     (CellAddress("A2")!, "Apple"), (CellAddress("B2")!, "5"),
                     (CellAddress("A3")!, "Pear"), (CellAddress("B3")!, "2")], sheet: 1)
        c.setInputs([(CellAddress("A1")!, "Item"), (CellAddress("B1")!, "Qty"),
                     (CellAddress("A2")!, "pear"), (CellAddress("B2")!, "7"),
                     (CellAddress("A3")!, "Plum"), (CellAddress("B3")!, "1")], sheet: 2)
        return c
    }
    private func src(_ c: WorkbookController, _ t: String) -> ConsolidateSource { c.parseConsolidateReference(t)! }
    private func num(_ c: WorkbookController, _ a: String) -> Double? { c.sheet.value(CellAddress(a)!).number }

    func testByLabelsMergesRowsAndWritesValues() throws {
        let c = book()
        let out = c.consolidate([src(c, "East!A1:B3"), src(c, "West!A1:B3")], function: .sum, topRow: true, leftColumn: true, link: false, at: CellAddress("A1")!)
        XCTAssertNil(out.problem)
        XCTAssertEqual(c.input(CellAddress("A2")!), "Apple")
        XCTAssertEqual(c.input(CellAddress("A3")!), "Pear")
        XCTAssertEqual(c.input(CellAddress("A4")!), "Plum")
        XCTAssertEqual(num(c, "B2"), 5); XCTAssertEqual(num(c, "B3"), 9); XCTAssertEqual(num(c, "B4"), 1)
        XCTAssertNil(c.sheet.cells[CellAddress("B3")!]?.formula, "no links: plain values")
    }

    func testLinksKeepFormulasAndFollowTheSource() {
        let c = book()
        _ = c.consolidate([src(c, "East!A1:B3"), src(c, "West!A1:B3")], function: .sum, topRow: true, leftColumn: true, link: true, at: CellAddress("A1")!)
        XCTAssertEqual(c.input(CellAddress("B3")!), "=SUM(East!B3,West!B2)")
        c.setInputs([(CellAddress("B3")!, "10")], sheet: 1)
        XCTAssertEqual(num(c, "B3"), 17)
    }

    func testByPositionAndOtherFunctions() {
        let c = book()
        let out = c.consolidate([src(c, "East!B2:B3"), src(c, "West!B2:B3")], function: .max, topRow: false, leftColumn: false, link: false, at: CellAddress("D1")!)
        XCTAssertNil(out.problem)
        XCTAssertEqual(num(c, "D1"), 7); XCTAssertEqual(num(c, "D2"), 2)
    }

    func testOneUndoStepBringsBackWhatWasThere() {
        let c = book()
        c.setInputs([(CellAddress("D1")!, "keep")])
        _ = c.consolidate([src(c, "East!B2:B3")], function: .sum, topRow: false, leftColumn: false, link: false, at: CellAddress("D1")!)
        XCTAssertEqual(num(c, "D1"), 5)
        c.undo()
        XCTAssertEqual(c.input(CellAddress("D1")!), "keep")
        XCTAssertEqual(c.input(CellAddress("D2")!), "")
    }

    func testRefusals() {
        let c = book()
        XCTAssertEqual(c.consolidate([], function: .sum, topRow: false, leftColumn: false, link: false, at: CellAddress("A1")!).problem, .noSources)
        XCTAssertNil(c.parseConsolidateReference("Nope!A1:B2"))
        XCTAssertEqual(c.consolidate([src(c, "East!A1:B3")], function: .sum, topRow: false, leftColumn: false, link: false, at: CellAddress("D1")!).problem == nil, true)
        c.activeSheet = 1
        XCTAssertEqual(c.consolidate([src(c, "A1:B3")], function: .sum, topRow: false, leftColumn: false, link: true, at: CellAddress("B2")!).problem, .overlapsSource)
        XCTAssertEqual(c.consolidate([src(c, "East!D5:E6")], function: .sum, topRow: false, leftColumn: false, link: false, at: CellAddress("H1")!).problem, .nothingToWrite)
    }

    func testTheDialogRunsIt() {
        let c = book()
        var closed = false
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: ConsolidateDialog(controller: c, onClose: { closed = true }), title: "T"), size: Size(1280, 800))
        addTeardownBlock { ui.replace(with: SizedBox(width: 1, height: 1)) }
        ui.pump()
        let st = ui.state(ConsolidateDialogState.self)!
        st.reference.text = "East!B2:B3"; st.add()
        st.reference.text = "West!B2:B3"
        st.apply()
        XCTAssertTrue(closed)
        XCTAssertEqual(num(c, "A1"), 12)
    }
}
