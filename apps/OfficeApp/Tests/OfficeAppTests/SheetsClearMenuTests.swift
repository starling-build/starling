// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-CL: the Clear menu (All, Formats, Contents, Comments, Hyperlinks).

import XCTest
@testable import OfficeApp
import Flutter
import FlutterSwiftBridge

final class SheetsClearMenuTests: XCTestCase {
    private func shell() -> (WidgetTester, SheetsShellState) {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SheetsShell(initialPath: nil, onSwitch: { _, _ in }), title: "t"),
                              size: Size(2000, 800))   // (wide enough that the Home tab's Clear button is not folded into its group)
        ui.pump()
        return (ui, ui.state(SheetsShellState.self)!)
    }

    private func dress(_ wb: WorkbookController) {
        let a = wb.active
        wb.setInput("hello", at: a)
        wb.setStyle { $0.bold = true }
        wb.setNote("a note", at: a)
        wb.setLink(CellRange(a, a), .url("https://x.example"))
    }

    func testClearCommentsAndHyperlinksKeepTheRest() {
        let (_, state) = shell()
        let wb = state.wb, a = wb.active
        dress(wb)
        wb.clearComments()
        XCTAssertNil(wb.note(at: a))
        XCTAssertNotNil(wb.link(at: a))
        wb.undo()
        XCTAssertNotNil(wb.note(at: a))
        wb.removeLink(wb.selection)
        XCTAssertNil(wb.link(at: a))
        XCTAssertNotNil(wb.note(at: a))
        XCTAssertEqual(wb.sheet.cells[a]?.input, "hello")
    }

    func testClearAllIsOneUndoStep() {
        let (_, state) = shell()
        let wb = state.wb, a = wb.active
        dress(wb)
        wb.clearAll()
        XCTAssertNil(wb.sheet.cells[a])
        XCTAssertNil(wb.note(at: a))
        XCTAssertNil(wb.link(at: a))
        wb.undo()
        XCTAssertEqual(wb.sheet.cells[a]?.input, "hello")
        XCTAssertNotNil(wb.note(at: a))
        XCTAssertNotNil(wb.link(at: a))
    }

    func testMenuEntriesReachTheCommands() {
        let (ui, state) = shell()
        let wb = state.wb, a = wb.active
        dress(wb)
        XCTAssertTrue(ui.tap(text: "Clear"))
        XCTAssertTrue(ui.has(id: "sheets.clear.Clear Comments"))
        XCTAssertTrue(ui.tap(id: "sheets.clear.Clear Comments")); ui.pump()
        XCTAssertNil(wb.note(at: a))
        XCTAssertTrue(ui.tap(text: "Clear"))
        XCTAssertTrue(ui.tap(id: "sheets.clear.Clear Hyperlinks")); ui.pump()
        XCTAssertNil(wb.link(at: a))
        XCTAssertTrue(ui.tap(text: "Clear"))
        XCTAssertTrue(ui.tap(id: "sheets.clear.Clear All")); ui.pump()
        XCTAssertNil(wb.sheet.cells[a])
    }
}
