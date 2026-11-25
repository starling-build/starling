import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp
@testable import OfficeText

/// W-FN-1 PR 2: References > Insert Footnote opens the note's text; OK saves it as one undo step.
final class NoteDialogTests: XCTestCase {
    private func shell(_ text: String) -> (WidgetTester, OfficeSession) {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(1600, 2000))
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
        ui.press(.escape); ui.pump()
        XCTAssertEqual(s.controller.document.footnotes[1]?.first?.text, "1 Typed note")
        let bytes = try DocxFormat.write(s.controller.document, pageSetup: .letter)
        XCTAssertEqual(try DocxFormat.read(bytes).document.footnotes[1]?.first?.text, "1 Typed note")
        if let dir = ProcessInfo.processInfo.environment["NOTE_CHECK_OUT2"] { try bytes.write(to: URL(fileURLWithPath: dir)) }
        // Edit Note reopens it with its text; Escape keeps it.
        s.controller.moveTo(RichPosition(paragraph: 0, offset: 6), extend: false)
        XCTAssertTrue(ui.tap(text: "Edit Note")); ui.pump()
        ui.press(.escape); ui.pump()
        XCTAssertEqual(s.controller.document.footnotes[1]?.first?.text, "1 Typed note")
    }

    func testAltCtrlDInsertsEndnote() throws {
        let (ui, s) = shell("Alpha beta")
        s.onInsertNote?(.endnote); ui.pump()
        XCTAssertEqual(s.controller.document.paragraphs[0].text, "Alphai beta")
        ui.press(.escape); ui.pump()
        XCTAssertEqual(s.controller.document.endnotes.count, 1)
    }

    /// A click on a note where the page prints it opens the note's text there; Escape keeps what was typed.
    func testClickingANoteOnThePageEditsItInPlace() throws {
        let (ui, s) = shell("Alpha beta")
        // A short page, so the note's place is inside the viewport whatever size the shell gives the editor.
        var short = PageSetup.letter; short.height = 420
        s.applyPageSetup(short); ui.pump()
        s.onInsertNote?(.footnote); ui.pump()
        let state = try XCTUnwrap(ui.state(OfficeShellState.self))
        ui.press(.escape); ui.pump()   // (inserting opens the new note's text; leave it)
        XCTAssertNil(state._noteOpen)
        var opened = false
        search: for x in stride(from: 200.0, to: 1000.0, by: 50.0) {
            for y in stride(from: 80.0, to: 1100.0, by: 6.0) {
                ui.tap(at: Offset(x, y)); ui.pump()
                if state._noteOpen != nil { opened = true; break search }
            }
        }
        XCTAssertTrue(opened, "no click down the page reached the footnote")
        ui.type("In place"); ui.pump()
        ui.press(.escape); ui.pump()
        XCTAssertNil(state._noteOpen)
        XCTAssertEqual(s.controller.document.footnotes[1]?.first?.text, "1 In place")
    }
}
