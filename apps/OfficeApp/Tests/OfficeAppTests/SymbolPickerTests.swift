// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import FlutterSwiftBridge
import OfficeText
@testable import OfficeApp

/// W-ED-3: the shared Symbol picker (data, the dialog headless, and the Writer insert).
final class SymbolPickerTests: XCTestCase {
    private var log: [String] = []
    private var closed = 0

    override func setUp() {
        super.setUp()
        OfficeSettings.setString(SymbolPickerState.recentKey, "")
    }

    private func picker() -> WidgetTester {
        log = []; closed = 0
        let hooks = SymbolHooks(fonts: ["(current font)", "Calibri", "Consolas"],
                                insert: { [unowned self] t, f in log.append("\(t)|\(f ?? "-")") })
        return WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: SymbolPicker(
            hooks: hooks, onClose: { [unowned self] in closed += 1 }), title: "T"), size: Size(1280, 800))
    }

    func testCodesParse() {
        XCTAssertEqual(SymbolData.parseCode("20AC"), 0x20AC)
        XCTAssertEqual(SymbolData.parseCode(" U+20ac "), 0x20AC)
        XCTAssertEqual(SymbolData.parseCode("0x00A9"), 0xA9)
        XCTAssertNil(SymbolData.parseCode("zz"))
        XCTAssertNil(SymbolData.parseCode(""))
        XCTAssertNil(SymbolData.parseCode("D800"))      // a surrogate is no character
        XCTAssertNil(SymbolData.parseCode("110000"))    // past the end
        XCTAssertEqual(SymbolData.code(0xA9), "U+00A9")
    }

    func testSubsetsHoldOnlyRealCharacters() {
        let latin1 = SymbolData.characters(in: SymbolData.subsets[1].range)
        XCTAssertEqual(latin1.first, 0xA0)              // the no-break space stays; the soft hyphen (a format mark) goes
        XCTAssertFalse(latin1.contains(0xAD))
        XCTAssertTrue(latin1.contains(0xA9))
        let arrows = SymbolData.characters(in: SymbolData.subsets.first { $0.name == "Arrows" }!.range)
        XCTAssertTrue(arrows.contains(0x2192))
    }

    func testRecentKeepsOrderAndLimit() {
        var r: [UInt32] = []
        for v in UInt32(0x41) ... 0x70 { r = SymbolData.remember(v, in: r) }
        XCTAssertEqual(r.count, 24)
        XCTAssertEqual(r.first, 0x70)
        r = SymbolData.remember(0x60, in: r)
        XCTAssertEqual(r.first, 0x60)
        XCTAssertEqual(r.filter { $0 == 0x60 }.count, 1)
        XCTAssertEqual(SymbolData.decodeRecent(SymbolData.encodeRecent(r)), r)
    }

    func testClickingASymbolThenInsertSendsIt() {
        let ui = picker()
        ui.tap(id: "sym-A9"); ui.tap(text: "Insert")
        XCTAssertEqual(log, ["©|-"])
        XCTAssertEqual(SymbolData.decodeRecent(OfficeSettings.string(SymbolPickerState.recentKey)), [0xA9])
        XCTAssertTrue(ui.has(id: "rec-A9"))
    }

    func testTypedCodeInsertsAndFontIsPassed() {
        let ui = picker()
        ui.tap(id: "sym-code"); ui.type("20AC")
        ui.tap(text: "(current font)"); ui.tap(text: "Consolas")
        ui.tap(text: "Insert")
        XCTAssertEqual(log, ["€|Consolas"])
    }

    func testBadCodeAndNothingPickedInsertNothing() {
        let ui = picker()
        ui.tap(text: "Insert")
        XCTAssertEqual(log, [])
        XCTAssertTrue(ui.has(text: "Pick a symbol first"))
        ui.tap(id: "sym-code"); ui.type("zz"); ui.tap(text: "Insert")
        XCTAssertEqual(log, [])
        XCTAssertTrue(ui.has(text: "Not a character code"))
    }

    func testCloseAndEscape() {
        let ui = picker()
        ui.tap(text: "Close"); XCTAssertEqual(closed, 1)
        let ui2 = picker()
        ui2.press(.escape); ui2.pump(); XCTAssertEqual(closed, 1)
    }

    func testWriterInsertSymbolIsOneUndoAndKeepsFont() {
        let c = RichDocumentController(plainText: "")
        c.insertSymbol("€", font: "Consolas")
        XCTAssertEqual(c.document.paragraphs[0].text, "€")
        XCTAssertEqual(c.document.paragraphs[0].runs.first?.style.fontFamily, "Consolas")
        c.undo()
        XCTAssertEqual(c.document.paragraphs[0].text, "")
    }
}
