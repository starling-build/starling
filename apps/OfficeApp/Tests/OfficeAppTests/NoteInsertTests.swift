import XCTest
@testable import OfficeApp
@testable import OfficeText

/// W-FN-1: insert a footnote or an endnote at the caret.
final class NoteInsertTests: XCTestCase {
    private func controller(_ texts: [String]) -> RichDocumentController {
        let c = RichDocumentController()
        c.load(RichDocument(paragraphs: texts.map { RichParagraph(text: $0) }))
        return c
    }

    func testFootnoteInsertsMarkNoteAndRenumbers() throws {
        let c = controller(["Alpha beta gamma"])
        c.moveTo(RichPosition(paragraph: 0, offset: 11), extend: false)
        c.insertNote(.footnote)          // after "Alpha beta " -> 1
        c.moveTo(RichPosition(paragraph: 0, offset: 5), extend: false)
        c.insertNote(.footnote)          // earlier -> becomes 1, the first becomes 2
        let d = c.document
        XCTAssertEqual(d.paragraphs[0].text, "Alpha1 beta 2gamma")
        XCTAssertEqual(d.footnotes.count, 2)
        let marks = d.paragraphs[0].runs.compactMap { $0.style.note }
        XCTAssertEqual(marks.map(\.id), [2, 1])
        XCTAssertEqual(d.footnotes[2]?.first?.text, "1 ")
        XCTAssertEqual(d.footnotes[1]?.first?.text, "2 ")
        // The file: parts exist, with separators and both notes; reopening reads them.
        let bytes = try DocxFormat.write(d, pageSetup: .letter)
        let part = try XCTUnwrap(Zip.read(bytes).first { $0.name == "word/footnotes.xml" })
        let xml = String(decoding: part.data, as: UTF8.self)
        XCTAssertTrue(xml.contains("w:type=\"separator\""))
        XCTAssertTrue(xml.contains("<w:footnote w:id=\"1\">") && xml.contains("<w:footnote w:id=\"2\">"))
        let back = try DocxFormat.read(bytes).document
        XCTAssertEqual(back.footnotes.count, 2)
        XCTAssertEqual(back.paragraphs[0].runs.compactMap { $0.style.note }.map(\.id), [2, 1])
        // Bodies are mapped by w:id, not by order: ids run 2, 1 in the text.
        XCTAssertEqual(back.footnotes[2]?.first?.text, "1 ")
        XCTAssertEqual(back.footnotes[1]?.first?.text, "2 ")
        // One undo takes back the mark, the note and the renumbering.
        c.undo()
        XCTAssertEqual(c.document.paragraphs[0].text, "Alpha beta 1gamma")
        XCTAssertEqual(c.document.footnotes.count, 1)
        c.undo()
        XCTAssertEqual(c.document.paragraphs[0].text, "Alpha beta gamma")
        XCTAssertTrue(c.document.footnotes.isEmpty)
        XCTAssertNil(c.document.keptParts["word/footnotes.xml"])
    }

    func testEndnoteIsRoman() {
        let c = controller(["Text"])
        c.moveTo(RichPosition(paragraph: 0, offset: 4), extend: false)
        c.insertNote(.endnote)
        XCTAssertEqual(c.document.paragraphs[0].text, "Texti")
        XCTAssertEqual(c.document.endnotes.count, 1)
        XCTAssertNotNil(c.document.keptParts["word/endnotes.xml"])
    }

    /// Writes the file for the Word check (only when NOTE_CHECK_OUT names a path).
    func testWriteWordCheckFile() throws {
        guard let out = ProcessInfo.processInfo.environment["NOTE_CHECK_OUT"] else { return }
        let c = controller(["First paragraph with some words in it.", "Second paragraph, more words here.", "Third paragraph at the end."])
        c.moveTo(RichPosition(paragraph: 1, offset: 9), extend: false)
        c.insertNote(.footnote)          // 1
        c.moveTo(RichPosition(paragraph: 2, offset: 5), extend: false)
        c.insertNote(.footnote)          // 2
        c.moveTo(RichPosition(paragraph: 0, offset: 5), extend: false)
        c.insertNote(.footnote)          // before both: new 1, others 2 and 3
        c.moveTo(RichPosition(paragraph: 2, offset: 15), extend: false)
        c.insertNote(.endnote)           // i
        try DocxFormat.write(c.document, pageSetup: .letter).write(to: URL(fileURLWithPath: out))
    }
}
