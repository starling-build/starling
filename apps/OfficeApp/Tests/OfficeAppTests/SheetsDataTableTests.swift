import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

final class SheetsDataTableTests: XCTestCase {
    private func book() -> WorkbookController {
        let wc = WorkbookController()
        // B1 = rate, B2 = years; B3 = B1*B2
        wc.setInputs([(CellAddress("B1")!, "2"), (CellAddress("B2")!, "3"), (CellAddress("B3")!, "=B1*B2")])
        return wc
    }

    func testOneVariableColumnTable() {
        let wc = book()
        // formula in E1 (top row), inputs down D2:D4
        wc.setInputs([(CellAddress("E1")!, "=B1*10"), (CellAddress("D2")!, "1"), (CellAddress("D3")!, "2"), (CellAddress("D4")!, "5")])
        XCTAssertNil(wc.dataTable(selection: CellRange("D1:E4")!, rowInput: nil, colInput: CellAddress("B1")!))
        XCTAssertEqual(wc.sheet.value(CellAddress("E2")!), .number(10))
        XCTAssertEqual(wc.sheet.value(CellAddress("E4")!), .number(50))
        XCTAssertEqual(wc.sheet.value(CellAddress("B1")!), .number(2), "the input cell is put back")
        XCTAssertTrue(wc.sheet.cells[CellAddress("E2")!]?.rawFormula?.contains("t=\"dataTable\"") ?? false)
        wc.undo()
        XCTAssertTrue(wc.sheet.value(CellAddress("E2")!).isEmpty)
    }

    func testTwoVariableTable() {
        let wc = book()
        wc.setInputs([(CellAddress("D1")!, "=B3"), (CellAddress("E1")!, "1"), (CellAddress("F1")!, "2"),
                      (CellAddress("D2")!, "10"), (CellAddress("D3")!, "20")])
        XCTAssertNil(wc.dataTable(selection: CellRange("D1:F3")!, rowInput: CellAddress("B1")!, colInput: CellAddress("B2")!))
        XCTAssertEqual(wc.sheet.value(CellAddress("F3")!), .number(40))
        XCTAssertEqual(wc.sheet.value(CellAddress("E2")!), .number(10))
    }

    func testProblems() {
        let wc = book()
        XCTAssertEqual(wc.dataTable(selection: CellRange("D1:E4")!, rowInput: nil, colInput: nil), .needsInput)
        XCTAssertEqual(wc.dataTable(selection: CellRange("D1:D4")!, rowInput: nil, colInput: CellAddress("B1")!), .selectionTooSmall)
        XCTAssertEqual(wc.dataTable(selection: CellRange("D1:E4")!, rowInput: nil, colInput: CellAddress("E2")!), .inputInsideTable)
    }

    func testRoundTrip() throws {
        let wc = book()
        wc.setInputs([(CellAddress("D1")!, "=B3"), (CellAddress("E1")!, "1"), (CellAddress("D2")!, "10")])
        XCTAssertNil(wc.dataTable(selection: CellRange("D1:E2")!, rowInput: CellAddress("B1")!, colInput: CellAddress("B2")!))
        let data = try Xlsx.write(wc.book)
        let back = WorkbookController(); back.load(try Xlsx.read(data))
        let c = back.sheet.cells[CellAddress("E2")!]
        XCTAssertTrue(c?.rawFormula?.contains("dt2D=\"1\"") ?? false)
        XCTAssertEqual(back.sheet.value(CellAddress("E2")!), .number(10))
    }

    func testTheDialogRunsIt() {
        let wc = book()
        wc.setInputs([(CellAddress("E1")!, "=B1*10"), (CellAddress("D2")!, "1"), (CellAddress("D3")!, "2")])
        wc.select(range: CellRange("D1:E3")!)
        var closed = false
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: DataTableDialog(controller: wc, onClose: { closed = true }), title: "T"), size: Size(1280, 800))
        addTeardownBlock { ui.replace(with: SizedBox(width: 1, height: 1)) }
        ui.pump()
        let st = ui.state(DataTableDialogState.self)!
        st.apply()
        XCTAssertFalse(closed, "no input cell yet")
        XCTAssertEqual(st.message, DataTableProblem.needsInput.message)
        st.colInput.text = "$B$1"
        st.apply()
        XCTAssertTrue(closed)
        XCTAssertEqual(wc.sheet.value(CellAddress("E3")!), .number(20))
    }

    /// Writes the Excel check book when STARLING_DT_OUT names a file; skipped otherwise.
    func testWriteCheckBook() throws {
        guard let out = ProcessInfo.processInfo.environment["STARLING_DT_OUT"] else { throw XCTSkip("no STARLING_DT_OUT") }
        let wc = book()
        wc.setInputs([(CellAddress("E1")!, "=B1*10"), (CellAddress("D2")!, "1"), (CellAddress("D3")!, "2"), (CellAddress("D4")!, "5"),
                      (CellAddress("H1")!, "=B3"), (CellAddress("I1")!, "1"), (CellAddress("J1")!, "2"),
                      (CellAddress("H2")!, "10"), (CellAddress("H3")!, "20")])
        XCTAssertNil(wc.dataTable(selection: CellRange("D1:E4")!, rowInput: nil, colInput: CellAddress("B1")!))
        XCTAssertNil(wc.dataTable(selection: CellRange("H1:J3")!, rowInput: CellAddress("B1")!, colInput: CellAddress("B2")!))
        try Xlsx.write(wc.book).write(to: URL(fileURLWithPath: out))
    }
}
