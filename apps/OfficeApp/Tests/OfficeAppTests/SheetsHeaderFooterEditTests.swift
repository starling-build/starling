// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-PR-1: header and footer text in Page Setup — fields, different first page, odd and even.

import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

final class SheetsHeaderFooterEditTests: XCTestCase {
    private func shell() throws -> (WidgetTester, SheetsShellState) {
        let path = NSTemporaryDirectory() + "hf-ui-\(getpid()).xlsx"
        try Xlsx.write(Workbook()).write(to: URL(fileURLWithPath: path))
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SheetsShell(initialPath: path, onSwitch: { _, _ in }), title: "Test"),
                              size: Size(1280, 800))
        return (ui, try XCTUnwrap(ui.state(SheetsShellState.self)))
    }

    func testDialogSetsHeaderFooterFieldsAndVariantsInOneUndo() throws {
        let (ui, _) = try shell()
        XCTAssertTrue(ui.tap(text: "Layout"))
        XCTAssertTrue(ui.tap(text: "Page Setup"))
        let panel = try XCTUnwrap(ui.state(PageSetupPanelState.self))
        panel.form.hf.differentFirst = true
        panel.form.hf.differentOddEven = true
        panel.boxes["hfOH"]?.text = "&L&F&C&A"
        panel.boxes["hfOF"]?.text = "&RPage &P of &N & &D"
        panel.boxes["hfEH"]?.text = "even"
        panel.boxes["hfFH"]?.text = "first"
        XCTAssertTrue(ui.tap(text: "OK"))
        let wb = try XCTUnwrap(ui.state(SheetsShellState.self)).wb
        let hf = SheetPrintSetup.read(wb.sheet).headerFooter
        XCTAssertEqual(hf.oddHeader, "&L&F&C&A")
        XCTAssertEqual(hf.oddFooter, "&RPage &P of &N & &D")
        XCTAssertEqual(hf.evenHeader, "even")
        XCTAssertEqual(hf.firstHeader, "first")
        XCTAssertTrue(hf.differentFirst && hf.differentOddEven)
        // Saved and read back.
        let back = try Xlsx.read(try Xlsx.write(wb.book))
        XCTAssertEqual(SheetPrintSetup.read(back.sheets[0]).headerFooter, hf)
        wb.undo()
        XCTAssertTrue(SheetPrintSetup.read(wb.sheet).headerFooter.isEmpty)
    }

    func testFieldButtonAddsItsCodeToTheBoxLastTypedIn() throws {
        let (ui, _) = try shell()
        XCTAssertTrue(ui.tap(text: "Layout"))
        XCTAssertTrue(ui.tap(text: "Page Setup"))
        let panel = try XCTUnwrap(ui.state(PageSetupPanelState.self))
        panel.hfTarget = "hfOF"
        XCTAssertTrue(ui.tap(text: "Time"))
        XCTAssertEqual(panel.boxes["hfOF"]?.text, "&T")
    }

    /// Writes the file for the Excel check (only when XCHECK_DIR is set).
    func testWriteExcelCheckFile() throws {
        guard let dir = ProcessInfo.processInfo.environment["XCHECK_DIR"] else { return }
        let c = WorkbookController()
        c.setInput("Report", at: CellAddress(row: 0, col: 0))
        var h = HeaderFooter()
        h.oddHeader = "&L&F&C&A&RPage &P of &N"; h.oddFooter = "&L&D&RCompany & Co".replacingAll("& Co", with: "&& Co")
        h.evenHeader = "EVEN header"; h.firstHeader = "FIRST header"; h.firstFooter = "FIRST footer"
        h.differentOddEven = true; h.differentFirst = true
        var ch = PageSetupChange(); ch.headerFooter = h
        c.setPageSetup(ch)
        c.setPrintTitles(rows: 0...0, cols: 0...0)
        try Xlsx.write(c.book).write(to: URL(fileURLWithPath: dir + "/headerfooter.xlsx"))
    }
}
