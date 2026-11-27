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
    /// What the host was handed. A box, not the test case: a print whose PDF is still being written when its
    /// test ends (Slides and Sheets write theirs in a Task) must land somewhere that still exists, not in a
    /// freed test case (on macOS that crashed the NEXT test, signal 10/11).
    private final class Printed { var all: [(Data, String)] = [] }
    private var savedFile: ((String) -> Void)?
    private var savedBytes: ((Data, String) -> Void)?
    private var box = Printed()
    private var printed: [(Data, String)] { box.all }
    private var testers: [WidgetTester] = []

    override func setUp() {
        savedFile = hostPrintPDF; savedBytes = hostPrintPDFBytes
        hostPrintPDF = nil
        box = Printed()
        let box = self.box
        hostPrintPDFBytes = { data, name in box.all.append((data, name)) }
    }

    override func tearDown() {
        // Let any print still in flight finish while its shell is mounted, then unmount every shell (their
        // timers, flush hooks and debug hooks go with them), and run what that queued, before the next test.
        let deadline = Date().addingTimeInterval(0.3)
        while Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        for ui in testers { ui.dispose() }
        testers = []
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        hostPrintPDF = savedFile; hostPrintPDFBytes = savedBytes
    }

    private func mount(_ home: Widget) -> WidgetTester {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: home, title: "Test"),
                              size: Size(1280, 800))
        testers.append(ui)
        return ui
    }

    private func shell() -> (WidgetTester, OfficeSession) {
        let ui = mount(OfficeShell(initialPath: nil, startBlank: true))
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
        let ui = mount(SlidesShell(initialPath: nil, onSwitch: { _, _ in }))
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
        let ui = mount(SheetsShell(initialPath: nil, onSwitch: { _, _ in }))
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
