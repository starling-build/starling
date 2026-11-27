// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp
@testable import OfficeText

/// W-PA-1d: Word's paragraph keys. Ctrl+M / Ctrl+Shift+M step the left indent a default tab stop, Ctrl+T / Ctrl+Shift+T
/// hang the paragraph, Ctrl+1 / 2 / 5 set single, double and 1.5 line spacing; each is one undo step and survives a save.
final class ParagraphKeysTests: XCTestCase {
    private func shell() -> (WidgetTester, OfficeShellState) {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: OfficeShell(initialPath: nil, startBlank: true), title: "T"),
                              size: Size(1280, 800))
        return (ui, ui.state(OfficeShellState.self)!)
    }

    private func key(_ logical: Int64) -> KeyData {
        KeyData(timeStamp: 0, type: .down, physical: 0, logical: logical, character: nil, synthesized: false)
    }

    func testIndentKeysStepByTheDefaultTabStop() throws {
        let (ui, state) = shell()
        let c = state.session.controller
        c.insertText("one")
        XCTAssertTrue(state._shortcut(key(0x6D), [.primary])); ui.pump()                 // Ctrl+M
        XCTAssertEqual(c.document.paragraphs[0].style.indentLeft, 36)
        XCTAssertTrue(state._shortcut(key(0x6D), [.primary])); ui.pump()
        XCTAssertEqual(c.document.paragraphs[0].style.indentLeft, 72)
        XCTAssertTrue(state._shortcut(key(0x6D), [.primary, .shift])); ui.pump()         // Ctrl+Shift+M
        XCTAssertEqual(c.document.paragraphs[0].style.indentLeft, 36)
        c.undo()
        XCTAssertEqual(c.document.paragraphs[0].style.indentLeft, 72, "one undo per key")
        // A left indent between stops goes to the next stop, not one stop further.
        c.setIndents(left: 50)
        c.stepIndent(forward: true, hanging: false)
        XCTAssertEqual(c.document.paragraphs[0].style.indentLeft, 72)
        c.stepIndent(forward: false, hanging: false)
        XCTAssertEqual(c.document.paragraphs[0].style.indentLeft, 36)
        // The first line moves with Ctrl+M.
        c.setIndents(left: 0, firstLine: 18)
        c.stepIndent(forward: true, hanging: false)
        XCTAssertEqual(c.document.paragraphs[0].style.firstLineIndent, 18)
    }

    func testHangingKeysKeepTheFirstLineInPlace() throws {
        let (ui, state) = shell()
        let c = state.session.controller
        c.insertText("one")
        XCTAssertTrue(state._shortcut(key(0x74), [.primary])); ui.pump()                 // Ctrl+T
        var s = c.document.paragraphs[0].style
        XCTAssertEqual(s.indentLeft, 36); XCTAssertEqual(s.firstLineIndent, -36)
        XCTAssertTrue(state._shortcut(key(0x74), [.primary])); ui.pump()
        s = c.document.paragraphs[0].style
        XCTAssertEqual(s.indentLeft, 72); XCTAssertEqual(s.firstLineIndent, -72)
        let back = try DocxFormat.read(DocxFormat.write(c.document, pageSetup: .letter)).document.paragraphs[0].style
        XCTAssertEqual(back.indentLeft, 72); XCTAssertEqual(back.firstLineIndent, -72)
        XCTAssertTrue(state._shortcut(key(0x74), [.primary, .shift])); ui.pump()         // Ctrl+Shift+T
        s = c.document.paragraphs[0].style
        XCTAssertEqual(s.indentLeft, 36); XCTAssertEqual(s.firstLineIndent, -36)
        c.stepIndent(forward: false, hanging: true)
        c.stepIndent(forward: false, hanging: true)                                      // stops where the hang runs out
        s = c.document.paragraphs[0].style
        XCTAssertEqual(s.indentLeft, 0); XCTAssertEqual(s.firstLineIndent, 0)
        // A first-line indent is not turned into a hang by Ctrl+Shift+T.
        c.setIndents(left: 0, firstLine: 36)
        c.stepIndent(forward: false, hanging: true)
        s = c.document.paragraphs[0].style
        XCTAssertEqual(s.indentLeft, 0); XCTAssertEqual(s.firstLineIndent, 36)
    }

    func testLineSpacingKeys() throws {
        let (ui, state) = shell()
        let c = state.session.controller
        c.insertText("one")
        c.setParagraphFormat(.init(lineRule: .exactly(20)))
        XCTAssertTrue(state._shortcut(key(0x32), [.primary])); ui.pump()                 // Ctrl+2
        XCTAssertEqual(c.document.paragraphs[0].style.lineSpacing, 2)
        XCTAssertNil(c.document.paragraphs[0].style.lineHeightPoints)
        XCTAssertTrue(state._shortcut(key(0x35), [.primary])); ui.pump()                 // Ctrl+5
        XCTAssertEqual(c.document.paragraphs[0].style.lineSpacing, 1.5)
        let back = try DocxFormat.read(DocxFormat.write(c.document, pageSetup: .letter)).document.paragraphs[0].style
        XCTAssertEqual(back.lineSpacing, 1.5)
        XCTAssertTrue(state._shortcut(key(0x31), [.primary])); ui.pump()                 // Ctrl+1
        XCTAssertEqual(c.document.paragraphs[0].style.lineSpacing, 1)
        c.undo()
        XCTAssertEqual(c.document.paragraphs[0].style.lineSpacing, 1.5, "one undo per key")
    }
}
