// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// Web parity 2 for Sheets: a workbook edited in a browser tab keeps its recovery copy in the page (IndexedDB), as
/// Writer's document and Slides' deck do. An in-memory stand-in plays the page.
final class BrowserSheetsRecoveryTests: XCTestCase {
    private final class Page {
        var mine: (kind: String, name: String, data: Data)?
        var orphans: [(kind: String, name: String, data: Data)] = []
        var keeps = 0
    }
    private var page = Page()
    private var saved: OfficeHost.BrowserRecovery?

    override func setUp() {
        saved = OfficeHost.browserRecovery
        page = Page()
        let page = self.page
        OfficeHost.browserRecovery = .init(
            keep: { kind, name, data in page.mine = (kind, name, data); page.keeps += 1 },
            discard: { page.mine = nil },
            take: { kind in
                guard let i = page.orphans.firstIndex(where: { $0.kind == kind }) else { return nil }
                let row = page.orphans.remove(at: i)
                page.mine = row
                return (row.name, row.data)
            })
    }

    override func tearDown() { OfficeHost.browserRecovery = saved }

    private func shell(_ path: String? = nil) -> (WidgetTester, SheetsShellState) {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SheetsShell(initialPath: path, onSwitch: { _, _ in }), title: "Test"),
                              size: Size(1280, 800))
        ui.pump()
        return (ui, ui.state(SheetsShellState.self)!)
    }

    private func waitForCopy(_ ui: WidgetTester) {
        let deadline = Date().addingTimeInterval(4)
        while page.mine == nil, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05)); ui.pump()
        }
    }

    private func bytes(_ text: String) throws -> Data {
        let wb = WorkbookController()
        wb.setInputs([(CellAddress(row: 0, col: 0), text)])
        return try Xlsx.write(wb.book)
    }

    private func a1(_ data: Data) throws -> CellValue {
        try Workbook.open(data, name: "x.xlsx").sheets[0].value(CellAddress(row: 0, col: 0))
    }

    func testAnEditIsCopiedAfterThePause() throws {
        let (ui, state) = shell()
        state.wb.setInputs([(CellAddress(row: 0, col: 0), "kept by the page")])
        ui.pump()
        waitForCopy(ui)
        guard let row = page.mine else { return XCTFail("no recovery copy reached the page") }
        XCTAssertEqual(row.kind, "xlsx")
        XCTAssertTrue(row.name.hasSuffix(".xlsx"), row.name)
        XCTAssertEqual(try a1(row.data), .text("kept by the page"))
    }

    func testACopyLeftByAClosedTabIsRestored() throws {
        page.orphans = [("pptx", "Talk.pptx", Data("not a deck".utf8)), ("xlsx", "Budget.xlsx", try bytes("restored"))]
        let (_, state) = shell()
        XCTAssertEqual(state.wb.sheet.value(CellAddress(row: 0, col: 0)), .text("restored"))
        XCTAssertEqual(state.session.path, "Budget.xlsx")
        XCTAssertTrue(state.session.dirty, "a restored workbook is unsaved")
        XCTAssertEqual(page.orphans.count, 1, "Sheets took only the Sheets copy")
        XCTAssertEqual(page.mine?.name, "Budget.xlsx", "the restored copy is now this tab's")
        XCTAssertEqual(page.keeps, 0, "the restored copy was written back unchanged")
    }

    /// A tab always starts in Writer: with only a workbook's copy waiting, Writer hands it to Sheets, which opens it
    /// unsaved under its name.
    func testWriterHandsAWorkbooksCopyToSheets() throws {
        page.orphans = [("xlsx", "Budget.xlsx", try bytes("handed on"))]
        var switched: (DocumentKind, String?)?
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: OfficeShell(initialPath: nil, onSwitch: { switched = ($0, $1) }),
                                        title: "Test"),
                              size: Size(1280, 800))
        ui.pump(); ui.pump()
        XCTAssertEqual(switched?.0, .workbook)
        XCTAssertEqual(switched?.1, "Budget.xlsx")
        XCTAssertTrue(page.orphans.isEmpty)
        // What OfficeRoot builds next for that switch.
        let (_, state) = shell("Budget.xlsx")
        XCTAssertEqual(state.wb.sheet.value(CellAddress(row: 0, col: 0)), .text("handed on"))
        XCTAssertEqual(state.session.path, "Budget.xlsx")
        XCTAssertTrue(state.session.dirty, "a restored workbook is unsaved")
    }

    func testAnUnchangedWorkbookIsNotCopiedAgain() throws {
        let (ui, state) = shell()
        state.wb.setInputs([(CellAddress(row: 0, col: 0), "once")])
        ui.pump()
        waitForCopy(ui)
        XCTAssertEqual(page.keeps, 1)
        // The page hiding asks every window to flush: nothing changed since the copy.
        OfficeScene.flushAll()
        XCTAssertEqual(page.keeps, 1, "an unchanged workbook was copied again")
        state.wb.setInputs([(CellAddress(row: 1, col: 0), "twice")])
        ui.pump()
        OfficeScene.flushAll()
        XCTAssertEqual(page.keeps, 2, "a page hide did not copy the new edit at once")
    }

    func testSavingDropsTheCopy() throws {
        let (ui, state) = shell()
        state.wb.setInputs([(CellAddress(row: 0, col: 0), "saved")])
        ui.pump()
        page.mine = ("xlsx", "Book1.xlsx", Data())
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("browser-sheets-recovery-\(getpid())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        state.session.path = dir.appendingPathComponent("Saved.xlsx").path
        state.session.onSave?(); ui.pump()
        XCTAssertFalse(state.session.dirty)
        XCTAssertNil(page.mine, "the saved workbook's recovery copy is still kept")
    }
}
