// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeApp
import Flutter
import FlutterSwiftBridge

final class SheetsCreateNamesTests: XCTestCase {
    private func a(_ s: String) -> CellAddress { CellAddress(s)! }
    private func book() -> WorkbookController {
        let c = WorkbookController()
        c.load(Workbook(sheets: [Worksheet(name: "S")]))
        c.setInputs([(a("A1"), "Sales"), (a("B1"), "Unit Cost"), (a("A2"), "1"), (a("A3"), "2"), (a("B2"), "10"), (a("B3"), "20")])
        c.select(range: CellRange(a("A1"), a("B3")))
        return c
    }

    func testTopRowLabelsNameTheColumnsBelow() {
        let c = book()
        XCTAssertTrue(c.defaultNameEdges.top)
        XCTAssertEqual(c.createNames(from: c.defaultNameEdges).made, 2)
        XCTAssertEqual(c.book.names["SALES"], "S!$A$2:$A$3")
        XCTAssertEqual(c.book.names["UNIT_COST"], "S!$B$2:$B$3")
        c.undo()
        XCTAssertNil(c.book.names["SALES"])
    }

    func testLeftColumnAndExistingNamesSkipped() {
        let c = book()
        XCTAssertNil(c.defineName("Sales", refersTo: "S!$A$1"))
        var e = NameEdges(); e.top = true
        let out = c.createNames(from: e)
        XCTAssertEqual(out.made, 1); XCTAssertEqual(out.skipped, 1)
    }

    func testRibbonOpensDialogAndMakesNames() {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: SheetsShell(initialPath: nil, onSwitch: { _, _ in }), title: "t"), size: Size(1280, 800))
        let st = ui.state(SheetsShellState.self)!
        st.wb.setInputs([(a("A1"), "Qty"), (a("A2"), "5")]); st.wb.select(range: CellRange(a("A1"), a("A2")))
        st.wb.onCommand?(.createNames); ui.pump()
        XCTAssertTrue(ui.has(text: "Top row"))
        ui.tap(text: "OK"); ui.pump()
        XCTAssertEqual(st.wb.book.names["QTY"], "Sheet1!$A$2")
    }
}
