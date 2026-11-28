// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import FlutterSwiftBridge
import OfficeText
@testable import OfficeApp

/// W-ST-1: Alt+Ctrl+Shift+S opens the Styles pane; the Modify Style strip sets underline, justify, indents, line spacing
/// and the next style. The strip is one undo step and the style survives a save.
final class ModifyStyleStripTests: XCTestCase {
    private func shell() -> (WidgetTester, OfficeShellState) {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: OfficeShell(initialPath: nil, startBlank: true), title: "T"),
                              size: Size(1440, 932))
        return (ui, ui.state(OfficeShellState.self)!)
    }

    func testStylesPaneKey() {
        let (ui, state) = shell()
        let s = KeyData(timeStamp: 0, type: .down, physical: 0, logical: 0x73, character: nil, synthesized: false)
        XCTAssertFalse(state.session.showStyles)
        XCTAssertTrue(state._shortcut(s, [.primary, .alt, .shift])); ui.pump()
        XCTAssertTrue(state.session.showStyles)
        XCTAssertTrue(state._shortcut(s, [.primary, .alt, .shift])); ui.pump()
        XCTAssertFalse(state.session.showStyles)
    }

    func testStripSetsTheStyleInOneStepAndSaves() throws {
        let (ui, state) = shell()
        let c = state.session.controller
        c.insertText("styled")
        let id = RichNamedStyle.headingId(2)
        let before = try XCTUnwrap(c.document.styles[id])
        state.session.onModifyStyle?(id); ui.pump()
        XCTAssertTrue(ui.tap(id: "ms-underline")); ui.pump()
        XCTAssertTrue(ui.tap(id: "ms-justify")); ui.pump()
        // The spinners and boxes go through the same entry edit; set the rest as they do.
        var e = try XCTUnwrap(c.document.styles[id])
        e.paragraph.indentLeft = 36; e.paragraph.firstLineIndent = -18
        e.paragraph.lineSpacing = 1.5; e.paragraph.lineHeightPoints = nil
        e.next = "Heading3"
        c.setStyleEntry(e, coalescing: true)
        let after = try XCTUnwrap(c.document.styles[id])
        XCTAssertTrue(after.char.underline)
        XCTAssertEqual(after.paragraph.alignment, .justify)
        let back = try XCTUnwrap(DocxFormat.read(DocxFormat.write(c.document, pageSetup: .letter)).document.styles[id])
        XCTAssertTrue(back.char.underline)
        XCTAssertEqual(back.paragraph.alignment, .justify)
        XCTAssertEqual(back.paragraph.indentLeft, 36, accuracy: 0.05)
        XCTAssertEqual(back.paragraph.firstLineIndent, -18, accuracy: 0.05)
        XCTAssertEqual(back.paragraph.lineSpacing, 1.5, accuracy: 0.01)
        XCTAssertEqual(back.next, "Heading3")
        c.undo()
        XCTAssertEqual(c.document.styles[id], before, "the strip is one undo step")
    }

    /// Word's Normal spacing (259/240 = 1.0791…) shows as 1.08, and a 10.5 pt size as 10.5 pt, never the raw double.
    func testNumbersShowToTwoDecimals() throws {
        let (ui, state) = shell()
        let c = state.session.controller
        var e = try XCTUnwrap(c.document.styles[RichNamedStyle.normalId])
        e.paragraph.lineSpacing = 259.0 / 240; e.paragraph.lineHeightPoints = nil
        e.char.fontSize = 10.5
        c.setStyleEntry(e, coalescing: false)
        state.session.onModifyStyle?(RichNamedStyle.normalId); ui.pump()
        let shown = ui.texts()
        XCTAssertTrue(shown.contains("1.08"), "\(shown)")
        XCTAssertTrue(shown.contains("10.5 pt"), "\(shown)")
        XCTAssertFalse(shown.contains { $0.containsSubstring("1.079") })
        e.paragraph.lineSpacing = 1.3333333; c.setStyleEntry(e, coalescing: false); ui.pump()
        XCTAssertTrue(ui.texts().contains("1.33"))
    }
}
