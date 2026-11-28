// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeText
@testable import OfficeApp

/// W-FD-1: Insert → Quick Parts → Field, F9 for every kind of field the app knows, and Ctrl+Shift+F9 (unlink).
final class FieldDialogTests: XCTestCase {
    private func shell() -> (WidgetTester, OfficeShellState) {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(1280, 800))
        return (ui, ui.state(OfficeShellState.self)!)
    }

    private let f9 = KeyData(timeStamp: 0, type: .down, physical: 0, logical: 0x1_0000_0809, character: nil, synthesized: false)

    func testEnterInsertsADateFieldThatKeepsFormatting() {
        let (ui, state) = shell()
        state.session.onFieldDialog?(); ui.pump()
        ui.press(.enter); ui.pump()
        let c = state.session.controller
        XCTAssertFalse(c.document.paragraphs[0].text.isEmpty)
        let instr = c.fieldSpans().first?.instruction ?? ""
        XCTAssertTrue(instr.hasPrefix(" DATE \\@ \"M/d/yyyy\""), instr)
        XCTAssertTrue(instr.contains("MERGEFORMAT"), instr)
        c.undo()
        XCTAssertEqual(c.document.paragraphs[0].text, "")
    }

    func testEscapeInsertsNothing() {
        let (ui, state) = shell()
        state.session.onFieldDialog?(); ui.pump()
        ui.press(.escape); ui.pump()
        XCTAssertEqual(state.session.controller.document.paragraphs[0].text, "")
    }

    func testInstructions() {
        XCTAssertEqual(FieldDialog.instruction("Time", picture: "HH:mm", preserve: false), " TIME \\@ \"HH:mm\" ")
        XCTAssertEqual(FieldDialog.instruction("NumPages", picture: "HH:mm", preserve: true), " NUMPAGES \\* MERGEFORMAT ")
    }

    func testFileName() {
        XCTAssertEqual(FieldEvaluator.evaluate(" FILENAME ", shown: "", clock: nil, properties: [:], path: "/home/a/Report.docx"), "Report.docx")
        XCTAssertEqual(FieldEvaluator.evaluate(" FILENAME \\p ", shown: "", clock: nil, properties: [:], path: "/home/a/Report.docx"), "/home/a/Report.docx")
        XCTAssertNil(FieldEvaluator.evaluate(" FILENAME ", shown: "x", clock: nil, properties: [:], path: nil))
    }

    /// F9 at the caret reaches both the layout's fields (PAGE) and the clock's (DATE); Shift+F9 still shows the code.
    func testF9UpdatesPageAndDateAndShiftF9ShowsTheCode() {
        let (_, state) = shell()
        let c = state.session.controller
        c.insertField(" PAGE ", result: "7")
        c.insertText(" ")
        c.insertField(" DATE \\@ \"yyyy\" ", result: "1999")
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: true)
        XCTAssertTrue(state._shortcut(f9, []))
        let year = FieldClock.current().map { String($0.year) } ?? "1999"
        XCTAssertEqual(c.document.paragraphs[0].text, "1 " + year)
        c.moveTo(RichPosition(paragraph: 0, offset: 1), extend: false)
        XCTAssertTrue(state._shortcut(f9, [.shift]))
        XCTAssertTrue(c.document.paragraphs[0].text.hasPrefix("{ PAGE } "), c.document.paragraphs[0].text)
    }

    func testCtrlShiftF9UnlinksTheFieldAtTheCaret() {
        let (_, state) = shell()
        let c = state.session.controller
        c.insertField(" PAGE ", result: "4")
        c.insertText(" of ")
        c.insertField(" NUMPAGES ", result: "9")
        c.moveTo(RichPosition(paragraph: 0, offset: 1), extend: false)
        XCTAssertTrue(state._shortcut(f9, [.primary, .shift]))
        XCTAssertEqual(c.document.paragraphs[0].text, "4 of 9")
        XCTAssertEqual(c.fieldSpans().map { $0.instruction }, [" NUMPAGES "])
        c.undo()
        XCTAssertEqual(c.fieldSpans().count, 2)
    }

    /// Sends `logical` down and up through the focus manager with `held` (modifier keysyms) pressed around it.
    private func send(_ ui: WidgetTester, _ logical: Int64, held: [Int64]) {
        func k(_ t: KeyEventType, _ l: Int64) { _ = FocusManager.instance.dispatchKeyData(KeyData(timeStamp: 0, type: t, physical: 0, logical: l, character: nil, synthesized: false)) }
        for h in held { k(.down, h) }
        k(.down, logical); k(.up, logical)
        for h in held.reversed() { k(.up, h) }
        ui.pump()
    }

    /// Shift+F9 and Alt+F9 from the keyboard, with the caret at the end of a field the dialog put in.
    func testShiftF9AndAltF9KeysShowTheCodeOfADialogField() {
        let (ui, state) = shell()
        state.session.onFieldDialog?(); ui.pump()
        ui.press(.enter); ui.pump()
        let c = state.session.controller
        XCTAssertEqual(c.selection.focus.offset, c.document.paragraphs[0].text.utf16.count)
        send(ui, 0x1_0000_0809, held: [0xFFE1])
        XCTAssertTrue(c.document.paragraphs[0].text.hasPrefix("{ DATE"), c.document.paragraphs[0].text)
        send(ui, 0x1_0000_0809, held: [0xFFE1])
        XCTAssertFalse(c.document.paragraphs[0].text.hasPrefix("{"), c.document.paragraphs[0].text)
        send(ui, 0x1_0000_0809, held: [0xFFE9])
        XCTAssertTrue(c.document.paragraphs[0].text.hasPrefix("{ DATE"), c.document.paragraphs[0].text)
    }
}
