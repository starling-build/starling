// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import FlutterSwiftBridge
import OfficeText
@testable import OfficeApp

/// The shared Find and Replace dialog and Symbol picker, wired in Sheets.
final class SheetsFindHookTests: XCTestCase {
    private func book() -> WorkbookController {
        let c = WorkbookController()
        c.setInput("apple pie", at: CellAddress("A1")!)
        c.setInput("apple", at: CellAddress("B2")!)
        c.setInput("Apple", at: CellAddress("A3")!)
        c.addSheet()
        c.setInput("apple", at: CellAddress("A1")!)
        c.activeSheet = 0
        c.select(CellAddress("A1")!)
        return c
    }

    func testEntireCellAndCaseAndScope() throws {
        let c = book()
        let whole = try TextPattern("apple", FindOptions(matchCase: true, entireCell: true))
        XCTAssertEqual(c.replaceAll(whole, with: "pear", scope: 0), 1)       // only B2 on this sheet
        XCTAssertEqual(c.input(CellAddress("A1")!), "apple pie")
        XCTAssertEqual(c.input(CellAddress("B2")!), "pear")
        let any = try TextPattern("apple", FindOptions())
        XCTAssertEqual(c.replaceAll(any, with: "fig", scope: 1), 3)          // A1, A3 here and the other sheet's A1
        c.undo()
        XCTAssertEqual(c.input(CellAddress("A1")!), "apple pie")             // one undo step brings all back
        XCTAssertEqual(c.input(CellAddress("A3")!), "Apple")
    }

    func testRegexTemplate() throws {
        let c = book()
        let p = try TextPattern("(\\w+) pie", FindOptions(mode: .regex))
        XCTAssertEqual(c.replaceAll(p, with: "$1 tart", scope: 0), 1)
        XCTAssertEqual(c.input(CellAddress("A1")!), "apple tart")
    }

    func testFindNextWalksTheSheetOrTheWorkbook() throws {
        let c = book()
        let p = try TextPattern("apple", FindOptions())
        XCTAssertTrue(c.findNext(p, scope: 0)); XCTAssertEqual(c.active, CellAddress("B2")!)
        XCTAssertTrue(c.findNext(p, scope: 0)); XCTAssertEqual(c.active, CellAddress("A3")!)
        XCTAssertTrue(c.findNext(p, scope: 0)); XCTAssertEqual(c.active, CellAddress("A1")!)   // wraps round
        XCTAssertTrue(c.findNext(p, scope: 1, backwards: true)); XCTAssertEqual(c.activeSheet, 1)
    }

    func testGoTo() {
        let c = book()
        XCTAssertNil(c.goTo("$C5"))
        XCTAssertEqual(c.active, CellAddress("C5")!)
        XCTAssertNil(c.goTo("Sheet2!B3"))
        XCTAssertEqual(c.activeSheet, 1)
        XCTAssertNotNil(c.goTo("nonsense"))
        XCTAssertNotNil(c.goTo("Nope!A1"))
    }

    func testCtrlFAndTheSymbolCommandOpenTheSharedDialogs() {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
            home: SheetsShell(initialPath: nil, onSwitch: { _, _ in }), title: "Test"), size: Size(1280, 800))
        addTeardownBlock { ui.replace(with: SizedBox(width: 1, height: 1)) }
        guard let shell = ui.state(SheetsShellState.self) else { return XCTFail("no shell") }
        shell.session.onFind?(false)
        ui.pump()
        XCTAssertNotNil(ui.state(FindReplaceDialogState.self))
        ui.press(.escape); ui.pump()
        XCTAssertNil(ui.state(FindReplaceDialogState.self))
        shell.wb.onCommand?(.symbol)
        ui.pump()
        XCTAssertNotNil(ui.state(SymbolPickerState.self))
    }
}
