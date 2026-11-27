// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import FlutterSwiftBridge
import OfficeText
@testable import OfficeApp

/// Web parity 1: File > Print where the host prints PDF bytes (the browser,
/// which has no files). The dialog offers Print, and Print hands the host the
/// same PDF as Export, limited to the pages picked.
final class BrowserPrintTests: XCTestCase {
    private var savedFile: ((String) -> Void)?
    private var savedBytes: ((Data, String) -> Void)?
    private var printed: [(Data, String)] = []

    override func setUp() {
        savedFile = hostPrintPDF; savedBytes = hostPrintPDFBytes
        hostPrintPDF = nil
        printed = []
        hostPrintPDFBytes = { [unowned self] data, name in printed.append((data, name)) }
    }

    override func tearDown() {
        hostPrintPDF = savedFile; hostPrintPDFBytes = savedBytes
    }

    private func shell() -> (WidgetTester, OfficeSession) {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"),
                              size: Size(1280, 800))
        return (ui, ui.state(OfficeShellState.self)!.session)
    }

    func testPrintHandsTheHostAPdf() {
        let (ui, session) = shell()
        ui.type("Printed in a browser")
        ui.pump()
        session.onPrint?(); ui.pump()
        ui.press(.enter); ui.pump()
        for _ in 0 ..< 50 where printed.isEmpty {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02)); ui.pump()
        }
        XCTAssertEqual(printed.count, 1, "the host got no PDF to print")
        guard let (data, name) = printed.first else { return }
        XCTAssertTrue(data.starts(with: Array("%PDF".utf8)))
        XCTAssertTrue(name.hasSuffix(".pdf"), name)
    }

    func testBackstagePrintOffersPrintNotExport() {
        XCTAssertTrue(hostCanPrintPDF)
        hostPrintPDFBytes = nil
        XCTAssertFalse(hostCanPrintPDF)
    }

    private func waitForPrint(_ ui: WidgetTester) {
        for _ in 0 ..< 150 where printed.isEmpty {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02)); ui.pump()
        }
    }

    /// Slides: the dialog offers Print, and Print hands the host the chosen slides as a PDF.
    func testSlidesPrintHandsTheHostAPdf() {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SlidesShell(initialPath: nil, onSwitch: { _, _ in }), title: "Test"),
                              size: Size(1280, 800))
        ui.pump()
        let hooks = ui.state(SlidesShellState.self)!._printHooks
        XCTAssertTrue(hooks.hostCanPrint, "Slides offers no Print where the host prints bytes")
        _ = hooks.print([1], 0)
        waitForPrint(ui)
        XCTAssertEqual(printed.count, 1, "the host got no PDF of the deck")
        guard let (data, name) = printed.first else { return }
        XCTAssertTrue(data.starts(with: Array("%PDF".utf8)))
        XCTAssertTrue(name.hasSuffix(".pdf"), name)
    }

    /// Sheets: the dialog offers Print, and Print hands the host the active sheet as a PDF.
    func testSheetsPrintHandsTheHostAPdf() {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SheetsShell(initialPath: nil, onSwitch: { _, _ in }), title: "Test"),
                              size: Size(1280, 800))
        ui.pump()
        let state = ui.state(SheetsShellState.self)!
        state.wb.setInputs([(CellAddress(row: 0, col: 0), "Printed from a browser")])
        state._printKinds = [.activeSheet]
        state._printCounts = [1]
        let hooks = state._printHooks
        XCTAssertTrue(hooks.hostCanPrint, "Sheets offers no Print where the host prints bytes")
        _ = hooks.print([1], 0)
        waitForPrint(ui)
        XCTAssertEqual(printed.count, 1, "the host got no PDF of the sheet")
        guard let (data, name) = printed.first else { return }
        XCTAssertTrue(data.starts(with: Array("%PDF".utf8)))
        XCTAssertTrue(name.hasSuffix(".pdf"), name)
    }
}
