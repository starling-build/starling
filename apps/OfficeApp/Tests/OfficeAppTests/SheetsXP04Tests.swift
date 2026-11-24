// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-P0-4: a legacy .xls opens from the UI, and Delete Sheet asks before it throws a sheet with content away.

import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

final class SheetsXP04Tests: XCTestCase {
    func testAnXlsOpensAsAWorkbookFromThePickers() {
        XCTAssertEqual(DocumentKind.kind(forPath: "/tmp/old.XLS"), .workbook)
        XCTAssertTrue(OfficeFormats.pickable.contains("xls"))
    }

    private func twoSheets() -> WorkbookController {
        let c = WorkbookController()
        c.load(Workbook(sheets: [Worksheet(name: "A"), Worksheet(name: "B")]))
        return c
    }

    func testDeletingASheetWithContentWaitsForConfirmation() {
        let c = twoSheets()
        c.setInputs([(CellAddress("A1")!, "keep me")])
        c.requestDeleteSheet(0)
        XCTAssertEqual(c.book.sheets.count, 2, "nothing deleted yet")
        XCTAssertEqual(c.pendingSheetDelete, 0)
        c.cancelSheetDelete()
        XCTAssertNil(c.pendingSheetDelete)
        XCTAssertEqual(c.book.sheets.count, 2)
        c.requestDeleteSheet(0)
        c.confirmSheetDelete()
        XCTAssertEqual(c.book.sheets.map(\.name), ["B"])
        c.undo()
        XCTAssertEqual(c.book.sheets.map(\.name), ["A", "B"], "one undo brings it back")
        XCTAssertEqual(c.sheet.value(CellAddress("A1")!), .text("keep me"))
    }

    func testAnEmptySheetGoesAtOnce() {
        let c = twoSheets()
        c.requestDeleteSheet(1)
        XCTAssertNil(c.pendingSheetDelete)
        XCTAssertEqual(c.book.sheets.map(\.name), ["A"])
    }
}

/// The Delete Sheet question, through the shell's own widgets.
final class SheetsConfirmUITests: XCTestCase {
    private func shell() throws -> (WidgetTester, WorkbookController) {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "karma_performance", withExtension: "xlsx", subdirectory: "Fixtures"))
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: SheetsShell(initialPath: url.path, onSwitch: { _, _ in }), title: "Test"), size: Size(1280, 800))
        let wb = try XCTUnwrap(ui.state(SheetsShellState.self)).wb
        return (ui, wb)
    }

    func testTheQuestionShowsAndCancelKeepsTheSheet() throws {
        let (ui, wb) = try shell()
        let n = wb.book.sheets.count
        wb.requestDeleteSheet(wb.activeSheet)
        ui.pump()
        XCTAssertTrue(ui.texts().contains { $0.hasPrefix("Delete “") })
        XCTAssertTrue(ui.tap(text: "Cancel"))
        XCTAssertEqual(wb.book.sheets.count, n)
        XCTAssertNil(wb.pendingSheetDelete)
    }

    func testDeleteInTheQuestionRemovesTheSheet() throws {
        let (ui, wb) = try shell()
        let n = wb.book.sheets.count
        wb.requestDeleteSheet(wb.activeSheet)
        ui.pump()
        XCTAssertTrue(ui.tap(text: "Delete sheet"))
        XCTAssertEqual(wb.book.sheets.count, n - 1)
    }
}
