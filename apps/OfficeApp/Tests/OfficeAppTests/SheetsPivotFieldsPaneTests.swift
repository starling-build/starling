import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// The PivotTable Fields pane: moving fields between Rows, Columns and Values by model call, by button and by dragging.
final class SheetsPivotFieldsPaneTests: XCTestCase {
    private func book() -> WorkbookController {
        let wc = WorkbookController()
        let rows: [[String]] = [["Region", "Product", "Sales"], ["East", "Pen", "10"], ["West", "Pen", "20"], ["East", "Ink", "5"],
                                ["East", "Pen", "30"], ["West", "Ink", "8"], ["North", "Pen", "7"]]
        var inputs: [(CellAddress, String)] = []
        for (r, row) in rows.enumerated() { for (c, v) in row.enumerated() { inputs.append((CellAddress(row: r, col: c), v)) } }
        wc.setInputs(inputs)
        XCTAssertNil(wc.insertPivotTable(source: "Sheet1!A1:C7", rows: [0], cols: [], data: [PivotDataField(field: 2, function: .sum)], filters: [],
                                         origin: CellAddress("F1")!, newSheet: false))
        wc.select(CellAddress("F2")!)
        return wc
    }
    private func spec(_ wc: WorkbookController) -> PivotSpec { wc.pivotPaneState()!.spec }

    func testStateReadsThePivotUnderTheActiveCell() {
        let wc = book()
        let st = wc.pivotPaneState()
        XCTAssertEqual(st?.fields, ["Region", "Product", "Sales"])
        XCTAssertEqual(st?.numeric, [false, false, true])
        wc.select(CellAddress("A1")!)
        XCTAssertNil(wc.pivotPaneState(), "outside the pivot the pane has nothing to show")
    }

    func testMoveToColumnsAndBack() {
        let wc = book()
        XCTAssertNil(wc.movePivotField(1, to: .columns))
        XCTAssertEqual(spec(wc).cols, [1])
        XCTAssertNil(wc.movePivotField(1, to: .rows, at: 0))
        XCTAssertEqual(spec(wc).rows, [1, 0])
        XCTAssertEqual(spec(wc).cols, [])
    }

    func testRemovingTheLastValueIsRefused() {
        let wc = book()
        XCTAssertEqual(wc.movePivotField(2, to: nil), .needsValues)
        XCTAssertEqual(spec(wc).data.count, 1, "the table is unchanged")
    }

    func testShiftReorders() {
        let wc = book()
        XCTAssertNil(wc.movePivotField(1, to: .rows))
        XCTAssertEqual(spec(wc).rows, [0, 1])
        XCTAssertNil(wc.shiftPivotField(1, in: .rows, by: -1))
        XCTAssertEqual(spec(wc).rows, [1, 0])
    }

    func testTableFollowsTheMove() {
        let wc = book()
        XCTAssertNil(wc.movePivotField(1, to: .columns))
        XCTAssertEqual(wc.sheet.value(CellAddress("G1")!), .text("Column Labels"))
    }

    private func ui(_ wc: WorkbookController) -> WidgetTester {
        WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: PivotFieldsPane(controller: wc, onChange: {}), title: "Test"), size: Size(400, 900))
    }

    func testDragAFieldOntoColumns() throws {
        let wc = book(), t = ui(wc)
        let from = try XCTUnwrap(t.centre(id: "pvf-field-1")), to = try XCTUnwrap(t.centre(id: "pvf-area-1"))
        t.drag(from: from, to: to)
        XCTAssertEqual(spec(wc).cols, [1])
    }

    func testButtonMovesToTheNextArea() throws {
        let wc = book()
        XCTAssertNil(wc.movePivotField(1, to: .columns))
        let t = ui(wc)
        XCTAssertTrue(t.tap(id: "pvf-move-\(PivotArea.columns.rawValue)-1"))
        XCTAssertEqual(spec(wc).rows, [0, 1])
        XCTAssertEqual(spec(wc).cols, [])
    }
}
