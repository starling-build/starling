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

    func testNoteTextEditsSavesReopensAndUndoes() throws {
        let c = controller(["Alpha beta gamma"])
        c.moveTo(RichPosition(paragraph: 0, offset: 5), extend: false)
        c.insertNote(.footnote)
        let n = try XCTUnwrap(c.noteAtCaret())
        XCTAssertEqual(n.id, 1)
        XCTAssertEqual(c.editableNoteText(n), "")
        XCTAssertTrue(c.setNoteText(n, "See <Smith> & Jones.\nSecond line"))
        XCTAssertEqual(c.editableNoteText(n), "See <Smith> & Jones.\nSecond line")
        XCTAssertEqual(c.document.footnotes[1]?.map(\.text), ["1 See <Smith> & Jones.", "Second line"])
        let back = try DocxFormat.read(try DocxFormat.write(c.document, pageSetup: .letter)).document
        XCTAssertEqual(back.footnotes[1]?.map(\.text), ["1 See <Smith> & Jones.", "Second line"])
        c.undo()
        XCTAssertEqual(c.editableNoteText(n), "")
        c.undo()
        XCTAssertNil(c.document.footnotes[1])
        // A note with formatting the plain editor would lose is refused.
        var d = c.document
        d.keptParts["word/footnotes.xml"] = Data("<w:footnotes xmlns:w=\"x\"><w:footnote w:id=\"1\"><w:p><w:r><w:footnoteRef/></w:r><w:r><w:rPr><w:b/></w:rPr><w:t>x</w:t></w:r></w:p></w:footnote></w:footnotes>".utf8)
        d.footnotes[1] = [RichParagraph(text: "1 x")]
        c.load(d)
        XCTAssertNil(c.editableNoteText(NoteReference(kind: .footnote, id: 1)))
        XCTAssertFalse(c.setNoteText(NoteReference(kind: .footnote, id: 1), "y"))
    }

    /// A note is styled the Word way: Footnote Text / Footnote Reference (and the endnote pair), defined in styles.xml,
    /// with no direct size or superscript on the note's runs.
    func testNotesUseWordStyles() throws {
        let c = controller(["Alpha beta gamma"])
        c.moveTo(RichPosition(paragraph: 0, offset: 5), extend: false)
        c.insertNote(.footnote)
        let n = try XCTUnwrap(c.noteAtCaret())
        XCTAssertTrue(c.setNoteText(n, "First\nSecond"))
        c.moveTo(RichPosition(paragraph: 0, offset: 11), extend: false)
        c.insertNote(.endnote)
        let path = NSTemporaryDirectory() + "notestyles-\(getpid()).docx"
        try DocxFormat.write(c.document, pageSetup: .letter).write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }
        func part(_ name: String) throws -> String {
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip"); p.arguments = ["-p", path, name]
            let pipe = Pipe(); p.standardOutput = pipe; try p.run()
            let d = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
            return String(decoding: d, as: UTF8.self)
        }
        for (file, kind) in [("word/footnotes.xml", "Footnote"), ("word/endnotes.xml", "Endnote")] {
            let xml = try part(file)
            XCTAssertTrue(xml.contains("<w:pStyle w:val=\"\(kind)Text\"/>"), file)
            XCTAssertTrue(xml.contains("<w:rStyle w:val=\"\(kind)Reference\"/>"), file)
            XCTAssertFalse(xml.contains("w:vertAlign"), file)
            XCTAssertFalse(xml.contains("<w:sz "), file)
        }
        XCTAssertFalse(try part("word/document.xml").contains("w:vertAlign"), "the body marks take their raise from the style")
        let styles = try part("word/styles.xml")
        for id in ["FootnoteText", "EndnoteText", "FootnoteReference", "EndnoteReference"] {
            XCTAssertTrue(styles.contains("w:styleId=\"\(id)\""), id)
        }
        if let out = ProcessInfo.processInfo.environment["NOTE_CHECK_OUT3"] {
            try DocxFormat.write(c.document, pageSetup: .letter).write(to: URL(fileURLWithPath: out))
        }
    }

    func testDeletingAMarkDropsItsNoteAndRenumbersInOneStep() throws {
        let c = controller(["Alpha beta gamma delta"])
        for off in [11, 5, 17] { c.moveTo(RichPosition(paragraph: 0, offset: off), extend: false); c.insertNote(.footnote) }
        // Marks in body order: id 2 after "Alpha", id 3 after "Alpha beta" ... find the middle one.
        let ids = c.document.paragraphs[0].runs.compactMap { $0.style.note?.id }
        XCTAssertEqual(ids.count, 3)
        let middle = ids[1]
        var offset = 0, at = 0
        for r in c.document.paragraphs[0].runs { if r.style.note?.id == middle { at = offset }; offset += r.length }
        let before = c.document.paragraphs[0].text
        c.moveTo(RichPosition(paragraph: 0, offset: at), extend: false); c.moveTo(RichPosition(paragraph: 0, offset: at + 1), extend: true)
        c.deleteBackward()
        XCTAssertNil(c.document.footnotes[middle])
        XCTAssertEqual(c.document.footnotes.count, 2)
        XCTAssertEqual(c.document.footnotes.values.compactMap { $0.first?.text.first }.sorted(), ["1", "2"])
        let back = try DocxFormat.read(try DocxFormat.write(c.document, pageSetup: .letter)).document
        XCTAssertEqual(back.footnotes.count, 2)
        c.undo()
        XCTAssertEqual(c.document.footnotes.count, 3)
        XCTAssertEqual(c.document.paragraphs[0].text, before)
    }
}
