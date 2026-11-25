import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp
@testable import OfficeText

/// W-FN-1 PR 2: References > Insert Footnote opens the note's text; OK saves it as one undo step.
final class NoteDialogTests: XCTestCase {
    private func shell(_ text: String) -> (WidgetTester, OfficeSession) {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(1600, 800))
        let s = ui.state(OfficeShellState.self)!.session
        s.controller.load(RichDocument(paragraphs: [RichParagraph(text: text)]))
        s.controller.moveTo(RichPosition(paragraph: 0, offset: 5), extend: false)
        ui.pump()
        return (ui, s)
    }

    func testRibbonInsertsFootnoteAndDialogSavesTypedText() throws {
        let (ui, s) = shell("Alpha beta")
        XCTAssertTrue(ui.tap(text: "References")); ui.pump()
        XCTAssertTrue(ui.tap(text: "Insert Footnote")); ui.pump()
        XCTAssertEqual(s.controller.document.paragraphs[0].text, "Alpha1 beta")
        XCTAssertTrue(true)
        ui.type("Typed note"); ui.pump()
        XCTAssertTrue(ui.tap(text: "OK")); ui.pump()
        XCTAssertEqual(s.controller.document.footnotes[1]?.first?.text, "1 Typed note")
        let bytes = try DocxFormat.write(s.controller.document, pageSetup: .letter)
        XCTAssertEqual(try DocxFormat.read(bytes).document.footnotes[1]?.first?.text, "1 Typed note")
        if let dir = ProcessInfo.processInfo.environment["NOTE_CHECK_OUT2"] { try bytes.write(to: URL(fileURLWithPath: dir)) }
        // Edit Note reopens it with its text; Cancel changes nothing.
        s.controller.moveTo(RichPosition(paragraph: 0, offset: 6), extend: false)
        XCTAssertTrue(ui.tap(text: "Edit Note")); ui.pump()
        XCTAssertTrue(ui.tap(text: "Cancel")); ui.pump()
        XCTAssertEqual(s.controller.document.footnotes[1]?.first?.text, "1 Typed note")
    }

    func testAltCtrlDInsertsEndnote() throws {
        let (ui, s) = shell("Alpha beta")
        s.onInsertNote?(.endnote); ui.pump()
        XCTAssertEqual(s.controller.document.paragraphs[0].text, "Alphai beta")
        XCTAssertTrue(ui.tap(text: "Cancel")); ui.pump()
        XCTAssertEqual(s.controller.document.endnotes.count, 1)
    }
}
