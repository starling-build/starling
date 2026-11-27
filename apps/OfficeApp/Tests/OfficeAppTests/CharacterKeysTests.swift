// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp
@testable import OfficeText

/// W-CH-2 keys: Word's Ctrl+Shift+K small caps, Ctrl+Shift+A all caps and Ctrl+Shift+D double underline. Each toggles the
/// selection in one undo step and survives a save; the shifted keys no longer reach ⌘K (link), ⌘A (select all) or ⌘D
/// (the Font dialog).
final class CharacterKeysTests: XCTestCase {
    private func shell() -> (WidgetTester, OfficeShellState) {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: OfficeShell(initialPath: nil, startBlank: true), title: "T"),
                              size: Size(1280, 800))
        return (ui, ui.state(OfficeShellState.self)!)
    }

    private func key(_ logical: Int64) -> KeyData {
        KeyData(timeStamp: 0, type: .down, physical: 0, logical: logical, character: nil, synthesized: false)
    }

    private func style(_ c: RichDocumentController) -> CharStyle { c.document.paragraphs[0].runs[0].style }

    private func saved(_ c: RichDocumentController) throws -> CharStyle {
        try DocxFormat.read(DocxFormat.write(c.document, pageSetup: .letter)).document.paragraphs[0].runs[0].style
    }

    func testSmallCapsKey() throws {
        let (ui, state) = shell()
        let c = state.session.controller
        c.insertText("small caps")
        c.selectAll()
        XCTAssertTrue(state._shortcut(key(0x6B), [.primary, .shift])); ui.pump()          // Ctrl+Shift+K
        XCTAssertTrue(style(c).smallCaps)
        XCTAssertTrue(try saved(c).smallCaps)
        XCTAssertEqual(c.selection.start.offset, 0, "the selection stays")
        XCTAssertEqual(c.selection.end.offset, 10)
        c.undo()
        XCTAssertFalse(style(c).smallCaps, "one undo step")
        c.redo()
        XCTAssertTrue(state._shortcut(key(0x6B), [.primary, .shift])); ui.pump()
        XCTAssertFalse(style(c).smallCaps, "the key toggles off")
    }

    func testAllCapsKeyKeepsTheLettersAndDoesNotSelectAll() throws {
        let (ui, state) = shell()
        let c = state.session.controller
        c.insertText("all caps")
        c.moveTo(RichPosition(paragraph: 0, offset: 3), extend: false)
        c.moveTo(RichPosition(paragraph: 0, offset: 8), extend: true)
        XCTAssertTrue(state._shortcut(key(0x61), [.primary, .shift])); ui.pump()          // Ctrl+Shift+A
        XCTAssertEqual(c.selection.start.offset, 3, "not select-all")
        let runs = c.document.paragraphs[0].runs
        XCTAssertFalse(runs[0].style.caps)
        XCTAssertTrue(runs.last!.style.caps)
        XCTAssertEqual(c.document.paragraphs[0].text, "all caps", "the letters stay as typed")
        let back = try DocxFormat.read(DocxFormat.write(c.document, pageSetup: .letter)).document.paragraphs[0].runs
        XCTAssertTrue(back.last!.style.caps)
        c.undo()
        XCTAssertFalse(c.document.paragraphs[0].runs.contains { $0.style.caps })
    }

    func testDoubleUnderlineKeyAndNotTheFontDialog() throws {
        let (ui, state) = shell()
        let c = state.session.controller
        var opened = false
        state.session.onFontDialog = { opened = true }
        c.insertText("double")
        c.selectAll()
        XCTAssertTrue(state._shortcut(key(0x64), [.primary, .shift])); ui.pump()          // Ctrl+Shift+D
        XCTAssertFalse(opened, "⌘⇧D does not open the Font dialog")
        XCTAssertTrue(style(c).underline)
        XCTAssertEqual(style(c).underlineKind, "double")
        let back = try saved(c)
        XCTAssertTrue(back.underline); XCTAssertEqual(back.underlineKind, "double")
        c.undo()
        XCTAssertFalse(style(c).underline, "one undo step")
        // A single underline becomes double; a double one goes off.
        c.toggleUnderline()
        XCTAssertTrue(state._shortcut(key(0x64), [.primary, .shift])); ui.pump()
        XCTAssertEqual(style(c).underlineKind, "double")
        XCTAssertTrue(state._shortcut(key(0x64), [.primary, .shift])); ui.pump()
        XCTAssertFalse(style(c).underline); XCTAssertNil(style(c).underlineKind)
        // ⌘D alone still opens the Font dialog.
        XCTAssertTrue(state._shortcut(key(0x64), [.primary])); ui.pump()
        XCTAssertTrue(opened)
    }
}
