// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-SH-1: the Tab Color and Move or Copy dialogs, and where a dragged tab lands.

import XCTest
@testable import OfficeApp
import Flutter
import FlutterSwiftBridge

final class SheetsTabDialogTests: XCTestCase {
    private func theme(_ home: Widget) -> Widget { FluentApp(theme: OfficeAppearance.theme(.light), home: home, title: "t") }

    func testDropLandsOnTheTabUnderThePointer() {
        let spans: [(index: Int, left: Double, right: Double)] = [(0, 0, 60), (2, 60, 140), (3, 140, 200)]
        XCTAssertEqual(SheetTabDrag.target(spans: spans, x: 100), 2)
        XCTAssertEqual(SheetTabDrag.target(spans: spans, x: -30), 0)
        XCTAssertEqual(SheetTabDrag.target(spans: spans, x: 500), 3)
        XCTAssertNil(SheetTabDrag.target(spans: [], x: 10))
    }

    func testTabColorDialogReportsTheSwatch() {
        var got: UInt32??
        var closed = false
        let ui = WidgetTester(theme(TabColorPanel(sheetName: "Sheet1", current: nil, onPick: { got = .some($0) }, onClose: { closed = true })),
                              size: Size(1280, 800))
        XCTAssertTrue(ui.tap(id: "tabcolor-Red"))
        XCTAssertTrue(ui.tap(text: "OK"))
        XCTAssertEqual(got, .some(0xFF0000))
        XCTAssertTrue(closed)
    }

    func testMoveCopyDialogReportsPositionAndCopy() {
        var got: (Int, Bool)?
        let ui = WidgetTester(theme(MoveCopyPanel(sheetName: "B", sheets: ["A", "B", "C"], canCopy: nil,
                                                  onDone: { got = ($0, $1) }, onClose: {})), size: Size(1280, 800))
        XCTAssertTrue(ui.has(text: "(move to end)"))
        XCTAssertTrue(ui.tap(id: "movecopy-0"))
        XCTAssertTrue(ui.tap(id: "movecopy-copy"))
        XCTAssertTrue(ui.tap(text: "OK"))
        XCTAssertEqual(got?.0, 0)
        XCTAssertEqual(got?.1, true)
    }

    func testMoveCopyDialogSaysWhyACopyIsRefused() {
        let ui = WidgetTester(theme(MoveCopyPanel(sheetName: "B", sheets: ["A", "B"], canCopy: "tables", onDone: { _, _ in }, onClose: {})),
                              size: Size(1280, 800))
        XCTAssertTrue(ui.texts().contains { $0.contains("tables") })
        XCTAssertFalse(ui.has(id: "movecopy-copy"))
    }

    func testSheetMenuOffersMoveCopyAndTabColor() throws {
        let tmp = NSTemporaryDirectory() + "tabs-\(ProcessInfo.processInfo.processIdentifier).xlsx"
        let c = WorkbookController(); c.addSheet()
        try Xlsx.write(c.book).write(to: URL(fileURLWithPath: tmp))
        let ui = WidgetTester(theme(SheetsShell(initialPath: tmp, onSwitch: { _, _ in })), size: Size(1280, 800))
        ui.pump()
        let shell = try XCTUnwrap(ui.state(SheetsShellState.self))
        XCTAssertTrue(shell._tabMenuTitles(0).contains("Move or Copy…"))
        XCTAssertTrue(shell._tabMenuTitles(0).contains("Tab Color…"))
        XCTAssertTrue(shell._tabMenuTitles(1).contains("Protect Sheet…"))
    }

    func testTabMenuProtectSheetOpensTheDialogOnThatSheet() throws {
        let tmp = NSTemporaryDirectory() + "tabs-protect-\(ProcessInfo.processInfo.processIdentifier).xlsx"
        let c = WorkbookController(); c.addSheet()
        try Xlsx.write(c.book).write(to: URL(fileURLWithPath: tmp))
        let ui = WidgetTester(theme(SheetsShell(initialPath: tmp, onSwitch: { _, _ in })), size: Size(1280, 800))
        ui.pump()
        let shell = try XCTUnwrap(ui.state(SheetsShellState.self))
        shell.wb.activeSheet = 0
        shell._runTabMenu(1, "Protect Sheet…"); ui.pump()
        XCTAssertEqual(shell.wb.activeSheet, 1)
        XCTAssertNotNil(ui.state(ProtectDialogState.self), "the Protect Sheet dialog did not open")
    }
}
