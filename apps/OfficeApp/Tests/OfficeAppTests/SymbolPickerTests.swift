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
        // What is typed next is back in the font it was in, not the symbol's.
        let d = RichDocumentController(plainText: "")
        d.insertSymbol("J", font: "Wingdings")
        d.insertText("x")
        d.insertParagraphBreak(); d.insertText("y")
        // style(at: n) is the character before offset n.
        XCTAssertEqual(d.document.paragraphs[0].style(at: 1).fontFamily, "Wingdings")
        XCTAssertNil(d.document.paragraphs[0].style(at: 2).fontFamily)
        XCTAssertNil(d.document.paragraphs[1].style(at: 1).fontFamily)
    }

    /// Word's Special Characters tab: pick a row, Insert puts it in the current font; the dialog keeps its size.
    func testSpecialCharactersTab() throws {
        let ui = picker()
        let title = ui.centre(ofText: "Symbol")
        XCTAssertEqual(ui.overflowingFlexes(), 0, "symbols tab")
        XCTAssertTrue(ui.tap(id: "sym-tab-special")); ui.pump()
        XCTAssertTrue(ui.has(text: "Nonbreaking Hyphen"))
        XCTAssertTrue(ui.has(text: "Alt+Ctrl+C"))
        XCTAssertEqual(ui.centre(ofText: "Symbol"), title, "the dialog does not move between tabs")
        XCTAssertTrue(ui.tap(id: "spc-2")); ui.tap(text: "Insert")
        XCTAssertEqual(log, ["\u{2011}|-"])
        XCTAssertEqual(SymbolData.specials.count, 20)
        XCTAssertEqual(ui.overflowingFlexes(), 0)
        XCTAssertTrue(ui.tap(id: "sym-tab-symbols")); ui.pump()
        XCTAssertTrue(ui.has(id: "sym-code"))
    }

    /// "from: ASCII (decimal)" shows and reads the code in decimal.
    func testDecimalCodes() throws {
        XCTAssertEqual(SymbolData.parseCode("169", decimal: true), 0xA9)
        XCTAssertNil(SymbolData.parseCode("A9", decimal: true))
        let ui = picker()
        let st = try XCTUnwrap(ui.state(SymbolPickerState.self))
        st.choose(0x20AC); st.setDecimal(true); ui.pump()
        XCTAssertTrue(ui.has(text: "8364"))
        st.setDecimal(false); ui.pump()
        XCTAssertTrue(ui.has(text: "20AC"))
        let ui2 = picker()
        try XCTUnwrap(ui2.state(SymbolPickerState.self)).setDecimal(true); ui2.pump()
        ui2.tap(id: "sym-code"); ui2.type("169"); ui2.tap(text: "Insert")
        XCTAssertEqual(log, ["©|-"])
    }

    /// Picking by code or from Recently used moves Subset to the character's block, as Word.
    func testSubsetFollowsTheCharacter() throws {
        let ui = picker()
        let st = try XCTUnwrap(ui.state(SymbolPickerState.self))
        let closeAt = ui.centre(ofText: "Close")
        st.choose(0x2192); ui.pump()
        XCTAssertEqual(SymbolData.subsets[st.subset].name, "Arrows")
        XCTAssertEqual(ui.centre(ofText: "Close"), closeAt, "the status line does not move the dialog")
        XCTAssertTrue(ui.has(id: "sym-2192"))
        XCTAssertNil(SymbolData.subset(containing: 0x4E00))
    }

    /// The ribbon gallery: recently used first, then Word's defaults, 20 in all, no repeats.
    func testGallery() {
        XCTAssertEqual(SymbolData.gallery([]), SymbolData.galleryDefaults)
        let g = SymbolData.gallery([0x2192, 0xA9])
        XCTAssertEqual(g.count, 20)
        XCTAssertEqual(Array(g.prefix(3)), [0x2192, 0xA9, 0x20AC])
        XCTAssertEqual(Set(g).count, 20)
    }

    /// Every special character survives a save and reopen; the two hyphens are Word's own elements.
    func testSpecialCharactersSaveAsWord() throws {
        let c = RichDocumentController(plainText: "")
        for sp in SymbolData.specials { c.insertSymbol(String(Character(Unicode.Scalar(sp.code)!)), font: nil) }
        let text = c.document.paragraphs[0].text
        let bytes = try DocxFormat.write(c.document, pageSetup: .letter)
        XCTAssertEqual(try DocxFormat.read(bytes).document.paragraphs[0].text, text)
        let xml = String(decoding: try XCTUnwrap(Zip.read(bytes).first { $0.name == "word/document.xml" }).data, as: UTF8.self)
        XCTAssertTrue(xml.containsSubstring("<w:noBreakHyphen/>"))
        XCTAssertTrue(xml.containsSubstring("<w:softHyphen/>"))
    }
}
