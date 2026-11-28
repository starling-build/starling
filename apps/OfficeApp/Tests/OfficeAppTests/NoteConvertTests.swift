import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp
@testable import OfficeText

/// W-FN-1 leftovers: a custom note mark, and Convert (footnotes to endnotes, back, swap).
final class NoteConvertTests: XCTestCase {
    private func controller(_ texts: [String]) -> RichDocumentController {
        let c = RichDocumentController()
        c.load(RichDocument(paragraphs: texts.map { RichParagraph(text: $0) }))
        return c
    }

    private func part(_ bytes: Data, _ name: String) throws -> String {
        String(decoding: try XCTUnwrap(Zip.read(bytes).first { $0.name == name }).data, as: UTF8.self)
    }

    func testCustomMarkTakesNoNumberAndSavesAsWordWritesIt() throws {
        let c = controller(["Alpha beta gamma"])
        c.moveTo(RichPosition(paragraph: 0, offset: 16), extend: false)
        c.insertNote(.footnote)                       // "1" at the end
        c.moveTo(RichPosition(paragraph: 0, offset: 5), extend: false)
        c.insertNote(.footnote, customMark: "*")      // before it: no number, the 1 stays 1
        let d = c.document
        XCTAssertEqual(d.paragraphs[0].text, "Alpha\u{200B}* beta gamma1")
        XCTAssertEqual(d.footnotes[2]?.first?.text, "* ")
        XCTAssertEqual(d.footnotes[1]?.first?.text, "1 ")
        XCTAssertTrue(c.setNoteText(NoteReference(kind: .footnote, id: 2), "Starred"))
        XCTAssertEqual(c.document.footnotes[2]?.first?.text, "* Starred")
        let bytes = try DocxFormat.write(c.document, pageSetup: .letter)
        let doc = try part(bytes, "word/document.xml")
        XCTAssertTrue(doc.contains("<w:footnoteReference w:customMarkFollows=\"1\" w:id=\"2\"/><w:t xml:space=\"preserve\">*</w:t>")
                      || doc.contains("<w:footnoteReference w:customMarkFollows=\"1\" w:id=\"2\"/><w:t>*</w:t>"), doc)
        let notes = try part(bytes, "word/footnotes.xml")
        XCTAssertTrue(notes.contains("<w:footnote w:id=\"2\"><w:p><w:pPr><w:pStyle w:val=\"FootnoteText\"/></w:pPr><w:r><w:rPr><w:rStyle w:val=\"FootnoteReference\"/></w:rPr><w:t xml:space=\"preserve\">*</w:t></w:r>"), notes)
        let back = try DocxFormat.read(bytes).document
        XCTAssertEqual(back.paragraphs[0].text.filter { $0 != "\u{200B}" }, "Alpha* beta gamma1")
        XCTAssertEqual(back.footnotes[2]?.first?.text, "* Starred")
        XCTAssertEqual(back.footnotes[1]?.first?.text, "1 ")
    }

    func testFootnotesToEndnotesMovesNotesRenumbersAndUndoes() throws {
        let c = controller(["One two three"])
        c.moveTo(RichPosition(paragraph: 0, offset: 3), extend: false); c.insertNote(.footnote)
        c.moveTo(RichPosition(paragraph: 0, offset: 8), extend: false); c.insertNote(.footnote)
        XCTAssertTrue(c.setNoteText(NoteReference(kind: .footnote, id: 1), "First"))
        XCTAssertEqual(c.document.paragraphs[0].text, "One1 two2 three")
        c.convertNotes(.footnotesToEndnotes)
        let d = c.document
        XCTAssertEqual(d.paragraphs[0].text, "Onei twoii three")
        XCTAssertTrue(d.footnotes.isEmpty)
        XCTAssertEqual(d.endnotes.count, 2)
        let refs = d.paragraphs[0].runs.compactMap { $0.style.note }
        XCTAssertEqual(refs.map(\.kind), [.endnote, .endnote])
        XCTAssertEqual(d.endnotes[refs[0].id]?.first?.text, "i First")
        let bytes = try DocxFormat.write(d, pageSetup: .letter)
        let en = try part(bytes, "word/endnotes.xml")
        XCTAssertTrue(en.contains("<w:endnote w:id=\"\(refs[0].id)\"><w:p><w:pPr><w:pStyle w:val=\"EndnoteText\"/></w:pPr><w:r><w:rPr><w:rStyle w:val=\"EndnoteReference\"/></w:rPr><w:endnoteRef/></w:r>"), en)
        XCTAssertTrue(en.contains("w:type=\"separator\""))
        let fn = try part(bytes, "word/footnotes.xml")
        XCTAssertFalse(fn.contains("<w:footnote w:id=\"1\">"), fn)
        let back = try DocxFormat.read(bytes).document
        XCTAssertEqual(back.endnotes.count, 2)
        XCTAssertEqual(back.endnotes[refs[0].id]?.first?.text, "i First")
        c.undo()
        XCTAssertEqual(c.document.paragraphs[0].text, "One1 two2 three")
        XCTAssertEqual(c.document.footnotes.count, 2)
        XCTAssertTrue(c.document.endnotes.isEmpty)
    }

    func testSwapAndBackKeepsTheText() throws {
        let c = controller(["Aa bb cc"])
        c.moveTo(RichPosition(paragraph: 0, offset: 2), extend: false); c.insertNote(.footnote)
        c.moveTo(RichPosition(paragraph: 0, offset: 6), extend: false); c.insertNote(.endnote)
        XCTAssertEqual(c.document.paragraphs[0].text, "Aa1 bbi cc")
        c.convertNotes(.swap)
        XCTAssertEqual(c.document.paragraphs[0].text, "Aai bb1 cc")
        XCTAssertEqual(c.document.paragraphs[0].runs.compactMap { $0.style.note?.kind }, [.endnote, .footnote])
        c.convertNotes(.endnotesToFootnotes)
        XCTAssertEqual(c.document.paragraphs[0].text, "Aa1 bb2 cc")
        XCTAssertTrue(c.document.endnotes.isEmpty)
        XCTAssertEqual(c.document.footnotes.count, 2)
        let back = try DocxFormat.read(try DocxFormat.write(c.document, pageSetup: .letter)).document
        XCTAssertEqual(back.paragraphs[0].text, "Aa1 bb2 cc")
        XCTAssertEqual(back.footnotes.count, 2)
    }

    /// Through the window: the dialog's Custom mark and Insert, then Convert… > OK.
    func testDialogInsertsCustomMarkAndConverts() throws {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(1600, 2000))
        let s = ui.state(OfficeShellState.self)!.session
        s.controller.load(RichDocument(paragraphs: [RichParagraph(text: "Alpha beta")]))
        s.controller.moveTo(RichPosition(paragraph: 0, offset: 5), extend: false)
        s.controller.insertNote(.footnote)
        s.controller.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        ui.pump()
        s.onNoteOptions?(); ui.pump()
        let st = try XCTUnwrap(ui.state(FootnoteDialogState.self))
        st._customForTesting("†")
        st._insertForTesting(); ui.pump()
        ui.press(.escape); ui.pump()
        XCTAssertEqual(s.controller.document.paragraphs[0].text, "\u{200B}†Alpha1 beta")
        s.onNoteOptions?(); ui.pump()
        XCTAssertTrue(ui.tap(text: "Convert…")); ui.pump()
        XCTAssertTrue(ui.tap(text: "OK")); ui.pump()
        XCTAssertNil(ui.state(FootnoteDialogState.self))
        XCTAssertEqual(s.controller.document.paragraphs[0].text, "\u{200B}†Alphai beta")
        XCTAssertTrue(s.controller.document.footnotes.isEmpty)
        XCTAssertEqual(s.controller.document.endnotes.count, 2)
    }

    /// Writes the Word lab files (only when NOTE_CONVERT_OUT names a folder).
    func testWriteWordLabFiles() throws {
        guard let out = ProcessInfo.processInfo.environment["NOTE_CONVERT_OUT"] else { return }
        let text = ["First paragraph with some words in it.", "Second paragraph, more words here.", "Third paragraph at the end."]
        func make(_ steps: (RichDocumentController) -> Void, _ name: String) throws {
            let c = controller(text)
            steps(c)
            try DocxFormat.write(c.document, pageSetup: .letter).write(to: URL(fileURLWithPath: out + "/" + name))
        }
        func notes(_ c: RichDocumentController) {
            c.moveTo(RichPosition(paragraph: 0, offset: 5), extend: false); c.insertNote(.footnote)
            _ = c.setNoteText(NoteReference(kind: .footnote, id: 1), "Footnote one.")
            c.moveTo(RichPosition(paragraph: 1, offset: 6), extend: false); c.insertNote(.endnote)
            _ = c.setNoteText(NoteReference(kind: .endnote, id: 1), "Endnote one.")
            c.moveTo(RichPosition(paragraph: 2, offset: 5), extend: false); c.insertNote(.footnote, customMark: "*")
            _ = c.setNoteText(NoteReference(kind: .footnote, id: 2), "Starred note.")
            c.moveTo(RichPosition(paragraph: 2, offset: 26), extend: false); c.insertNote(.footnote)
            _ = c.setNoteText(NoteReference(kind: .footnote, id: 3), "Footnote two.")
        }
        try make(notes, "fncv-custom.docx")
        try make({ notes($0); $0.convertNotes(.footnotesToEndnotes) }, "fncv-to-end.docx")
        try make({ notes($0); $0.convertNotes(.swap) }, "fncv-swap.docx")
    }
}
