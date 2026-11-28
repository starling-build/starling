// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import FlutterSwiftBridge
import OfficeText
@testable import OfficeApp

/// X-ED-1: Excel's Find options in Sheets: Look in (formulas, values, notes), Search by rows
/// or by columns, and Find All with its list.
final class SheetsFindLookInTests: XCTestCase {
    private func book() -> WorkbookController {
        let c = WorkbookController()
        c.setInput("=2*3", at: CellAddress("A1")!)      // formula text "=2*3", value 6
        c.setInput("6", at: CellAddress("C1")!)
        c.setInput("6", at: CellAddress("A2")!)
        c.setNote("six apples", at: CellAddress("B3")!)
        c.select(CellAddress("A1")!)
        return c
    }

    private func plain(_ s: String) throws -> TextPattern { try TextPattern(s, FindOptions()) }

    func testLookInFormulasValuesNotes() throws {
        let c = book()
        XCTAssertEqual(c.findAll(try plain("6"), scope: 0, lookIn: .formulas).map(\.at.a1), ["C1", "A2"],
                       "Formulas: A1's text is =2*3, not 6")
        XCTAssertEqual(c.findAll(try plain("6"), scope: 0, lookIn: .values).map(\.at.a1), ["A1", "C1", "A2"],
                       "Values: A1 shows 6")
        XCTAssertEqual(c.findAll(try plain("2*"), scope: 0, lookIn: .values).map(\.at.a1), [])
        XCTAssertEqual(c.findAll(try plain("apples"), scope: 0, lookIn: .notes).map(\.at.a1), ["B3"],
                       "Notes: B3 is an empty cell with a note")
        XCTAssertEqual(c.findAll(try plain("apples"), scope: 0, lookIn: .formulas).map(\.at.a1), [])
    }

    func testSearchByColumnsChangesTheOrder() throws {
        let c = book()
        XCTAssertEqual(c.findAll(try plain("6"), scope: 0, lookIn: .values, byColumns: true).map(\.at.a1), ["A1", "A2", "C1"])
        c.select(CellAddress("A1")!)
        XCTAssertTrue(c.findNext(try plain("6"), scope: 0, lookIn: .values, byColumns: true))
        XCTAssertEqual(c.active.a1, "A2", "by columns, A2 comes before C1")
        XCTAssertTrue(c.findNext(try plain("6"), scope: 0, lookIn: .values, byColumns: false))
        XCTAssertEqual(c.active.a1, "A1", "by rows, A2 is the last match, so it wraps round")
        c.select(CellAddress("C1")!)
        XCTAssertEqual(c.findPosition(try plain("6"), scope: 0, lookIn: .values, byColumns: true)?.index, 3)
    }

    func testFindAllAcrossTheWorkbookAndGoingToAHit() throws {
        let c = book()
        c.addSheet()
        c.setInput("6", at: CellAddress("D4")!)
        c.activeSheet = 0
        let all = c.findAll(try plain("6"), scope: 1, lookIn: .formulas)
        XCTAssertEqual(all.map { "\($0.sheet)!\($0.at.a1)" }, ["0!C1", "0!A2", "1!D4"])
        c.goToHit(all[2])
        XCTAssertEqual(c.activeSheet, 1)
        XCTAssertEqual(c.active.a1, "D4")
    }

    // The dialog, wired by SheetsShell's hooks: the two choices, Find All's list, and a click on a line.
    func testDialogFindAllListsAndGoes() {
        var lookedIn: [FindWhere] = []
        var went = 0
        var hooks = FindHooks(findNext: { _, w, _ in lookedIn.append(w); return "" },
                              replace: { _, _, _ in "" }, replaceAll: { _, _, _ in "" })
        hooks.scopes = ["Sheet", "Workbook"]
        hooks.orders = ["By Rows", "By Columns"]
        hooks.lookIns = ["Formulas", "Values", "Notes"]
        hooks.findAll = { _, w in
            lookedIn.append(w)
            return [FindListHit(place: "Sheet1", cell: "$A$1", value: "6", formula: "=2*3", go: { went += 1 }),
                    FindListHit(place: "Sheet1", cell: "$C$1", value: "6", formula: "", go: { went += 10 })]
        }
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: FindReplaceDialog(
            initialQuery: "6", hooks: hooks, onClose: {}), title: "T"), size: Size(1280, 800))
        ui.pump()
        XCTAssertTrue(ui.has(text: "Look in")); XCTAssertTrue(ui.has(text: "Search"))
        XCTAssertFalse(ui.has(text: "$A$1"), "no list before Find All")
        ui.tap(text: "Find All"); ui.pump()
        XCTAssertTrue(ui.has(text: "2 cells found"))
        XCTAssertTrue(ui.has(text: "$A$1")); XCTAssertTrue(ui.has(text: "=2*3"))
        ui.tap(text: "$C$1"); ui.pump()
        XCTAssertEqual(went, 10)
        XCTAssertEqual(lookedIn, [FindWhere()])
    }

    func testSheetsFindAllInTheRealWindow() {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
            home: SheetsShell(initialPath: nil, onSwitch: { _, _ in }), title: "Test"), size: Size(1440, 932))
        addTeardownBlock { ui.replace(with: SizedBox(width: 1, height: 1)) }
        guard let shell = ui.state(SheetsShellState.self) else { return XCTFail("no shell") }
        shell.wb.setInput("pear", at: CellAddress("B2")!)
        shell.wb.setInput("pear tart", at: CellAddress("D5")!)
        shell.wb.select(CellAddress("A1")!)
        shell.session.onFind?(false)
        ui.pump()
        ui.tap(id: "fr-query"); ui.type("pear"); ui.pump()
        ui.tap(text: "Find All"); ui.pump()
        XCTAssertTrue(ui.has(text: "2 cells found"))
        XCTAssertTrue(ui.has(text: "$B$2")); XCTAssertTrue(ui.has(text: "pear tart"))
        ui.tap(text: "$D$5"); ui.pump()
        XCTAssertEqual(shell.wb.active.a1, "D5")
    }

    func testWriterHasNoneOfTheSheetsChoices() {
        let hooks = FindHooks(findNext: { _, _, _ in "" }, replace: { _, _, _ in "" }, replaceAll: { _, _, _ in "" })
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: FindReplaceDialog(
            initialQuery: "", hooks: hooks, onClose: {}), title: "T"), size: Size(1280, 800))
        ui.pump()
        XCTAssertFalse(ui.has(text: "Look in")); XCTAssertFalse(ui.has(text: "Find All"))
    }
}
