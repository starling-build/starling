// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import FlutterSwiftBridge
import OfficeText
@testable import OfficeApp

/// U-PR-1: the shared Print dialog (page-range logic, and the dialog driven headless).
final class PrintDialogTests: XCTestCase {
    private var sent: [([Int], Int)] = []
    private var closed = 0

    private func dialog(total: Int = 10, current: Int = 4, selection: [Int]? = nil, outputs: [String] = [],
                        host: Bool = true, reply: String = "") -> WidgetTester {
        sent = []; closed = 0
        let hooks = PrintHooks(unit: outputs.isEmpty ? "Pages" : "Slides", total: total, current: current,
                               selection: selection, outputs: outputs, hostCanPrint: host,
                               print: { [unowned self] p, o in sent.append((p, o)); return reply })
        return WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: PrintDialog(
            hooks: hooks, onClose: { [unowned self] in closed += 1 }), title: "T"), size: Size(1280, 800))
    }

    func testRangesParse() {
        XCTAssertEqual(PrintPlan.parse("1-3, 5, 8-", total: 10), [1, 2, 3, 5, 8, 9, 10])
        XCTAssertEqual(PrintPlan.parse("-2", total: 10), [1, 2])
        XCTAssertEqual(PrintPlan.parse("5,1", total: 10), [5, 1])
        XCTAssertNil(PrintPlan.parse("0", total: 10))
        XCTAssertNil(PrintPlan.parse("11", total: 10))
        XCTAssertNil(PrintPlan.parse("3-2", total: 10))
        XCTAssertNil(PrintPlan.parse("1,,2", total: 10))
        XCTAssertNil(PrintPlan.parse("-", total: 10))
        XCTAssertNil(PrintPlan.parse("a", total: 10))
        XCTAssertNil(PrintPlan.parse("", total: 10))
        XCTAssertEqual(PrintPlan.sheets([1, 2], copies: 3), [1, 2, 1, 2, 1, 2])
    }

    func testEnterPrintsEverythingOnceAndCloses() {
        let ui = dialog(total: 3)
        ui.press(.enter); ui.pump()
        XCTAssertEqual(sent.map { $0.0 }, [[1, 2, 3]])
        XCTAssertEqual(closed, 1)
    }

    func testCurrentPage() {
        let ui = dialog()
        ui.tap(text: "Current (4)"); ui.tap(text: "Print")
        XCTAssertEqual(sent.map { $0.0 }, [[4]])
    }

    func testTypedRangeAndCopies() {
        let ui = dialog()
        ui.tap(id: "print-pages"); ui.type("2-3")
        ui.tap(id: "print-copies"); ui.press(.backspace); ui.type("2")
        ui.tap(text: "Print")
        XCTAssertEqual(sent.map { $0.0 }, [[2, 3, 2, 3]])
    }

    func testBadRangeAndBadCopiesPrintNothing() {
        let ui = dialog()
        ui.tap(id: "print-pages"); ui.type("99")
        ui.tap(text: "Print")
        XCTAssertTrue(sent.isEmpty)
        XCTAssertTrue(ui.has(text: "Type pages like 1-3, 5 (1 to 10)"))
        let ui2 = dialog()
        ui2.tap(id: "print-copies"); ui2.press(.backspace); ui2.type("0")
        ui2.tap(text: "Print")
        XCTAssertTrue(sent.isEmpty)
        XCTAssertTrue(ui2.has(text: "Copies must be 1 to 99"))
    }

    func testSelectionOnlyWhenTheAppHasOne() {
        XCTAssertFalse(dialog().has(text: "Selection"))
        let ui = dialog(selection: [2, 3])
        ui.tap(text: "Selection"); ui.tap(text: "Print")
        XCTAssertEqual(sent.map { $0.0 }, [[2, 3]])
    }

    func testPrintWhatOnlyWhenOffered() {
        XCTAssertFalse(dialog().has(text: "Print what"))
        let ui = dialog(outputs: ["Slides", "Notes Pages", "Handouts"])
        ui.tap(text: "Slides"); ui.tap(text: "Handouts"); ui.tap(text: "Print")
        XCTAssertEqual(sent.first?.1, 2)
    }

    func testNoHostPrintDialogSaysSoAndSendsNothing() {
        let ui = dialog(host: false)
        ui.tap(text: "Print")
        XCTAssertTrue(sent.isEmpty)
        XCTAssertTrue(ui.has(text: "This host has no print dialog; use File > Export for a PDF"))
        XCTAssertEqual(closed, 0)
    }

    func testHookErrorKeepsTheDialogOpen() {
        let ui = dialog(reply: "Could not render")
        ui.tap(text: "Print")
        XCTAssertEqual(closed, 0)
        XCTAssertTrue(ui.has(text: "Could not render"))
    }

    func testCancelAndEscape() {
        let ui = dialog(); ui.tap(text: "Cancel"); XCTAssertEqual(closed, 1)
        let ui2 = dialog(); ui2.press(.escape); ui2.pump(); XCTAssertEqual(closed, 1)
    }
}

/// The Writer side: only the named pages reach the PDF, repeats make copies.
final class PdfPrintPagesTests: XCTestCase {
    private func pageCount(printPages: [Int]?) throws -> Int {
        let c = RichDocumentController(plainText: "one\ntwo\nthree")
        // Put each paragraph on its own page.
        var doc = c.document
        for i in doc.paragraphs.indices { doc.paragraphs[i].style.pageBreakBefore = true }
        let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
        let path = NSTemporaryDirectory() + "print-pages-\(UUID().uuidString).pdf"
        defer { try? FileManager.default.removeItem(atPath: path) }
        XCTAssertTrue(PdfExport.write(doc, pageSetup: .letter, theme: theme, to: path, title: "T", printPages: printPages))
        let data = try XCTUnwrap(FileManager.default.contents(atPath: path))
        let text = String(decoding: data, as: UTF8.self)
        return text.components(separatedBy: "/Type /Page\n").count - 1
    }

    func testPrintPagesPicksAndRepeats() throws {
        XCTAssertEqual(try pageCount(printPages: nil), 3)
        XCTAssertEqual(try pageCount(printPages: [2]), 1)
        XCTAssertEqual(try pageCount(printPages: [3, 1, 3, 1]), 4)
    }
}
