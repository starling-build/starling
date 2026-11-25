// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-SH-1b: dragging a sheet tab with the real pointer — plain drag moves, Ctrl+drag copies.

import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

final class SheetsTabPointerTests: XCTestCase {
    private func shell() throws -> (WidgetTester, WorkbookController) {
        let path = NSTemporaryDirectory() + "tab-pointer-\(getpid()).xlsx"
        try Xlsx.write(Workbook()).write(to: URL(fileURLWithPath: path))
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SheetsShell(initialPath: path, onSwitch: { _, _ in }), title: "Test"),
                              size: Size(1280, 800))
        let wb = try XCTUnwrap(ui.state(SheetsShellState.self)).wb
        wb.addSheet(); wb.addSheet()
        wb.activeSheet = 0
        ui.pump()
        return (ui, wb)
    }

    func testDraggingATabMovesItAndCtrlDragCopiesIt() throws {
        let (ui, wb) = try shell()
        let names = wb.book.sheets.map(\.name)
        XCTAssertEqual(names.count, 3)
        let from = try XCTUnwrap(ui.centre(ofText: names[0]))
        let to = try XCTUnwrap(ui.centre(ofText: names[2]))
        ui.drag(from: from, to: Offset(to.dx + 20, to.dy))
        XCTAssertEqual(wb.book.sheets.count, 3, "a plain drag moves")
        XCTAssertEqual(wb.book.sheets.last?.name, names[0])

        let (ui2, wb2) = try shell()
        let a = try XCTUnwrap(ui2.centre(ofText: names[0]))
        let b = try XCTUnwrap(ui2.centre(ofText: names[2]))
        ui2.drag(from: a, to: Offset(b.dx + 20, b.dy), modifiers: [.control])
        XCTAssertEqual(wb2.book.sheets.count, 4, "Ctrl+drag copies")
        XCTAssertEqual(wb2.book.sheets.first?.name, names[0])
    }
}
