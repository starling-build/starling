import XCTest
@testable import OfficeApp
@testable import OfficeText

/// W-FN-1: the Footnote and Endnote dialog's options: number format, first number, restart and position.
final class NoteOptionsTests: XCTestCase {
    private func twoFootnotes() -> RichDocumentController {
        let c = RichDocumentController()
        c.load(RichDocument(paragraphs: [RichParagraph(text: "Alpha beta gamma")]))
        c.moveTo(RichPosition(paragraph: 0, offset: 5), extend: false)
        c.insertNote(.footnote)
        c.moveTo(RichPosition(paragraph: 0, offset: 12), extend: false)
        c.insertNote(.footnote)
        return c
    }

    private func settings(_ bytes: Data) throws -> String {
        String(decoding: try XCTUnwrap(Zip.read(bytes).first { $0.name == "word/settings.xml" }).data, as: UTF8.self)
    }

    func testFormatAndStartRenumberAndSave() throws {
        let c = twoFootnotes()
        XCTAssertEqual(c.document.paragraphs[0].text, "Alpha1 beta 2gamma")
        XCTAssertEqual(c.noteOptions(.footnote), NoteOptions.defaults(.footnote))
        var o = c.noteOptions(.footnote)
        o.format = .upperRoman; o.start = 3
        c.setNoteOptions(.footnote, o)
        XCTAssertEqual(c.document.paragraphs[0].text, "AlphaIII beta IVgamma")
        XCTAssertEqual(c.document.footnotes.values.map { $0[0].text }.sorted(), ["III ", "IV "])
        XCTAssertEqual(c.noteOptions(.footnote), o)
        let bytes = try DocxFormat.write(c.document, pageSetup: .letter)
        let xml = try settings(bytes)
        XCTAssertTrue(xml.contains("<w:footnotePr><w:numFmt w:val=\"upperRoman\"/><w:numStart w:val=\"3\"/></w:footnotePr>"), xml)
        // (Schema order: before w:compat.)
        let fp = try XCTUnwrap(xml.range(of: "<w:footnotePr")), compat = try XCTUnwrap(xml.range(of: "<w:compat"))
        XCTAssertLessThan(fp.lowerBound, compat.lowerBound)
        let back = try DocxFormat.read(bytes).document
        XCTAssertEqual(back.footnotePropertiesXML, "<w:footnotePr><w:numFmt w:val=\"upperRoman\"/><w:numStart w:val=\"3\"/></w:footnotePr>")
        // One undo takes the options and the renumbering back.
        c.undo()
        XCTAssertEqual(c.document.paragraphs[0].text, "Alpha1 beta 2gamma")
        XCTAssertNil(c.document.footnotePropertiesXML)
    }

    func testRestartEachSection() {
        let c = RichDocumentController()
        var first = RichParagraph(text: "One two")
        first.style.sectionXML = "<w:sectPr/>"
        c.load(RichDocument(paragraphs: [first, RichParagraph(text: "Three four")]))
        c.moveTo(RichPosition(paragraph: 0, offset: 3), extend: false); c.insertNote(.footnote)
        c.moveTo(RichPosition(paragraph: 1, offset: 5), extend: false); c.insertNote(.footnote)
        XCTAssertEqual(c.document.paragraphs.map(\.text), ["One1 two", "Three2 four"])
        var o = c.noteOptions(.footnote); o.restart = "eachSect"
        c.setNoteOptions(.footnote, o)
        XCTAssertEqual(c.document.paragraphs.map(\.text), ["One1 two", "Three1 four"])
        XCTAssertEqual(c.document.footnotePropertiesXML, "<w:footnotePr><w:numRestart w:val=\"eachSect\"/></w:footnotePr>")
    }

    func testEndnotesAtSectionEndAndKeptSeparatorIds() {
        let c = RichDocumentController()
        var d = RichDocument(paragraphs: [RichParagraph(text: "Text")])
        d.endnotePropertiesXML = "<w:endnotePr><w:endnote w:id=\"-1\"/><w:endnote w:id=\"0\"/></w:endnotePr>"
        c.load(d)
        var o = c.noteOptions(.endnote)
        XCTAssertEqual(o.format, .lowerRoman)
        o.position = "sectEnd"
        c.setNoteOptions(.endnote, o)
        XCTAssertTrue(c.document.endnotesAtSectionEnd)
        XCTAssertEqual(c.document.endnotePropertiesXML,
                       "<w:endnotePr><w:pos w:val=\"sectEnd\"/><w:endnote w:id=\"-1\"/><w:endnote w:id=\"0\"/></w:endnotePr>")
        c.undo()
        XCTAssertFalse(c.document.endnotesAtSectionEnd)
    }

    func testUnchangedSettingsKeepTheirNoteProperties() throws {
        let original = "<w:settings xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:footnotePr><w:numFmt w:val=\"lowerLetter\"/></w:footnotePr><w:compat/></w:settings>"
        let node = XNode.parse(Data(original.utf8))
        // Unchanged: left as it is (no second copy).
        XCTAssertEqual(DocxFormat._withNoteProperties(original, footnote: "<w:footnotePr><w:numFmt w:val=\"lowerLetter\"/></w:footnotePr>",
                                                      endnote: nil, original: node), original)
        // Changed: replaced in place.
        let changed = DocxFormat._withNoteProperties(original, footnote: "<w:footnotePr><w:numFmt w:val=\"upperLetter\"/></w:footnotePr>",
                                                     endnote: nil, original: node)
        XCTAssertEqual(changed, original.replacingOccurrences(of: "lowerLetter", with: "upperLetter"))
        // Cleared: removed.
        XCTAssertFalse(DocxFormat._withNoteProperties(original, footnote: nil, endnote: nil, original: node).contains("footnotePr"))
    }

    func testNextFootnote() {
        let c = twoFootnotes()
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        c.goToNextNote(.footnote)
        XCTAssertEqual(c.selection.end.offset, 5)
        c.goToNextNote(.footnote)
        XCTAssertEqual(c.selection.end.offset, 12)
        c.goToNextNote(.footnote)
        XCTAssertEqual(c.selection.end.offset, 5)
    }
}
