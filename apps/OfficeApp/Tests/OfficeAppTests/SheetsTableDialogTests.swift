import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// X-DA-5: the Table dialog makes a table, and shows the options of the table under the cell.
final class SheetsTableDialogTests: XCTestCase {
    private func data() -> WorkbookController {
        let c = WorkbookController()
        let rows = [["Item", "Qty"], ["a", "1"], ["b", "2"], ["c", "3"]]
        var items: [(CellAddress, String)] = []
        for (r, row) in rows.enumerated() { for (k, v) in row.enumerated() { items.append((CellAddress(row: r, col: k), v)) } }
        c.setInputs(items)
        c.select(CellAddress("A1")!)
        return c
    }

    private func dialog(_ c: WorkbookController, _ log: @escaping (String) -> Void) -> WidgetTester {
        WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                               home: TableDialog(controller: c, onClose: { log("closed") }), title: "T"),
                     size: Size(1280, 800))
    }

    func testCreateMakesATableFromTheRegionAndOneUndoRemovesIt() {
        let c = data()
        var log: [String] = []
        let ui = dialog(c, { log.append($0) })
        XCTAssertTrue(ui.has(id: "table-source"))
        XCTAssertTrue(ui.has(id: "table-headers"))
        ui.press(.enter)
        XCTAssertEqual(log, ["closed"])
        XCTAssertEqual(c.sheet.tables.count, 1)
        XCTAssertEqual(c.sheet.tables[0].ref.a1, "A1:B4")
        c.undo()
        XCTAssertTrue(c.sheet.tables.isEmpty)
    }

    func testAnEmptyOrBadRangeIsRefusedWithAMessage() {
        let c = WorkbookController()   // nothing on the sheet: the field holds one empty cell
        var log: [String] = []
        let ui = dialog(c, { log.append($0) })
        ui.press(.enter)
        XCTAssertTrue(log.isEmpty)
        XCTAssertFalse(ui.state(TableDialogState.self)!.message.isEmpty)
        XCTAssertTrue(c.sheet.tables.isEmpty)
    }

    func testOptionsToggleTheLookTotalsAndConvert() {
        let c = data()
        XCTAssertNil(c.createTable(CellRange("A1:B4")!, hasHeaders: true, style: "TableStyleMedium2"))
        var log: [String] = []
        let ui = dialog(c, { log.append($0) })
        XCTAssertTrue(ui.has(id: "table-rows"))
        XCTAssertTrue(ui.tap(id: "table-cols"))
        XCTAssertTrue(c.sheet.tables[0].columnStripes)
        XCTAssertTrue(ui.tap(id: "table-first"))
        XCTAssertTrue(c.sheet.tables[0].firstColumn)
        XCTAssertTrue(ui.tap(id: "table-totals"))
        XCTAssertTrue(c.sheet.tables[0].totalsRow)
        XCTAssertEqual(c.sheet.tables[0].ref.a1, "A1:B5")
        XCTAssertTrue(ui.tap(id: "table-totals"))
        XCTAssertEqual(c.sheet.tables[0].ref.a1, "A1:B4")
        ui.state(TableDialogState.self)!.setStyle("TableStyleLight9")
        XCTAssertEqual(c.sheet.tables[0].style, "TableStyleLight9")
        XCTAssertTrue(ui.tap(id: "table-convert"))
        XCTAssertEqual(log, ["closed"])
        XCTAssertTrue(c.sheet.tables.isEmpty)
        XCTAssertEqual(c.sheet.cells[CellAddress("B3")!]?.input, "2")
    }
}
