import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp
@testable import OfficeText

/// W-FN-1: a section's own footnote and endnote options (Footnote and Endnote > Apply changes to: This section).
final class NoteSectionTests: XCTestCase {
    static let firstSect = "<w:sectPr><w:footerReference w:type=\"default\" r:id=\"rId9\"/><w:pgSz w:w=\"12240\" w:h=\"15840\"/></w:sectPr>"

    /// Two sections: "One" (its mark "1") ends the first, "Two three" (marks "2", "3") is the last.
    private func twoSections() -> RichDocumentController {
        var a = RichParagraph(text: "One"); a.style.sectionXML = Self.firstSect; a.style.sectionPage = .letter
        let c = RichDocumentController(document: RichDocument(paragraphs: [a, RichParagraph(text: "Two three")]))
        for (p, o) in [(0, 3), (1, 3), (1, 9)] {
            c.moveTo(RichPosition(paragraph: p, offset: o + (p == 1 && o == 9 ? 1 : 0)), extend: false)
            c.insertNote(.footnote)
        }
        return c
    }

    private func marks(_ d: RichDocument) -> [String] {
        d.paragraphs.flatMap { p -> [String] in
            let u = Array(p.text.utf16)
            var at = 0
            return p.runs.compactMap { r in
                defer { at += r.length }
                return r.style.note == nil ? nil : String(decoding: u[at ..< at + r.length], as: UTF16.self)
            }
        }
    }

    private func part(_ bytes: Data, _ name: String) throws -> String {
        String(decoding: try XCTUnwrap(Zip.read(bytes).first { $0.name == name }).data, as: UTF8.self)
    }

    func testLastSectionOwnOptionsRenumberSaveReadAndUndo() throws {
        let c = twoSections()
        XCTAssertEqual(marks(c.document), ["1", "2", "3"])
        c.moveTo(RichPosition(paragraph: 1, offset: 0), extend: false)
        var o = c.sectionNoteOptions(.footnote)
        o.format = .lowerRoman; o.restart = "eachSect"
        c.setNoteOptions(.footnote, o, thisSection: true)
        XCTAssertEqual(marks(c.document), ["1", "i", "ii"])
        XCTAssertEqual(c.document.sectionNotesXML, "<w:footnotePr><w:numFmt w:val=\"lowerRoman\"/><w:numRestart w:val=\"eachSect\"/></w:footnotePr>")
        XCTAssertNil(c.document.footnotePropertiesXML, "the document's own stay Word's defaults")
        XCTAssertTrue(c.sectionHasOwnNoteOptions(.footnote))
        XCTAssertEqual(c.sectionNoteOptions(.footnote).format, .lowerRoman)
        XCTAssertEqual(c.sectionNoteOptions(.footnote, paragraph: 0).format, .decimal)

        let bytes = try DocxFormat.write(c.document, pageSetup: .letter)
        let doc = try part(bytes, "word/document.xml")
        // (CT_SectPr: the note properties before the page size.)
        XCTAssertTrue(doc.containsSubstring("<w:footnotePr><w:numFmt w:val=\"lowerRoman\"/><w:numRestart w:val=\"eachSect\"/></w:footnotePr><w:pgSz"), doc)
        let back = try DocxFormat.read(bytes).document
        XCTAssertEqual(marks(back), ["1", "i", "ii"], "the reader numbers each section in its own form")
        XCTAssertEqual(back.sectionNotesXML, c.document.sectionNotesXML)
        XCTAssertEqual(back.footnotes.values.compactMap { $0.first?.text.first.map(String.init) }.sorted(), ["1", "i", "i"])

        c.undo()
        XCTAssertEqual(marks(c.document), ["1", "2", "3"])
        XCTAssertNil(c.document.sectionNotesXML)
    }

    func testEarlierSectionOwnOptionsGoInItsSectPrAndWholeDocumentClearsThem() throws {
        let c = twoSections()
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        var o = c.sectionNoteOptions(.footnote)
        o.format = .upperLetter
        c.setNoteOptions(.footnote, o, thisSection: true)
        XCTAssertEqual(marks(c.document), ["A", "2", "3"], "the count runs on into the next section")
        XCTAssertEqual(c.document.paragraphs[0].style.sectionXML,
                       "<w:sectPr><w:footerReference w:type=\"default\" r:id=\"rId9\"/><w:footnotePr><w:numFmt w:val=\"upperLetter\"/></w:footnotePr><w:pgSz w:w=\"12240\" w:h=\"15840\"/></w:sectPr>")
        let back = try DocxFormat.read(try DocxFormat.write(c.document, pageSetup: .letter)).document
        XCTAssertEqual(marks(back), ["A", "2", "3"])

        var whole = c.noteOptions(.footnote)
        whole.format = .lowerLetter
        c.setNoteOptions(.footnote, whole)
        XCTAssertEqual(marks(c.document), ["a", "b", "c"])
        XCTAssertEqual(c.document.paragraphs[0].style.sectionXML, Self.firstSect)
        XCTAssertFalse(c.sectionHasOwnNoteOptions(.footnote))
        c.undo()
        XCTAssertEqual(marks(c.document), ["A", "2", "3"])
    }

    /// Word (lab fnsect-first): a first section in capitals from 3, restarting, then a section running on prints
    /// C, D | 3, 4: the running-on count starts from the document's first number, not the earlier section's.
    func testRunningOnSectionCountsFromTheDocumentStart() throws {
        let c = twoSections()
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        var o = c.sectionNoteOptions(.footnote)
        o.format = .upperLetter; o.start = 3; o.restart = "eachSect"
        c.setNoteOptions(.footnote, o, thisSection: true)
        XCTAssertEqual(marks(c.document), ["C", "2", "3"])
        let back = try DocxFormat.read(try DocxFormat.write(c.document, pageSetup: .letter)).document
        XCTAssertEqual(marks(back), ["C", "2", "3"])
    }

    func testNoteElementPlacement() {
        typealias C = RichDocumentController
        let fn = "<w:footnotePr><w:numFmt w:val=\"lowerRoman\"/></w:footnotePr>"
        let en = "<w:endnotePr><w:numFmt w:val=\"decimal\"/></w:endnotePr>"
        XCTAssertEqual(C._replacingNoteElement(in: "<w:sectPr/>", "footnotePr", with: fn), "<w:sectPr>\(fn)</w:sectPr>")
        let both = C._replacingNoteElement(in: C._replacingNoteElement(in: Self.firstSect, "endnotePr", with: en), "footnotePr", with: fn)
        XCTAssertEqual(both, "<w:sectPr><w:footerReference w:type=\"default\" r:id=\"rId9\"/>\(fn)\(en)<w:pgSz w:w=\"12240\" w:h=\"15840\"/></w:sectPr>")
        XCTAssertEqual(C.sectionNoteElements(both), fn + en)
        XCTAssertEqual(C._replacingNoteElement(in: both, "footnotePr", with: nil), C._replacingNoteElement(in: Self.firstSect, "endnotePr", with: en))
        // The last section's own, alone: footnotePr first.
        XCTAssertEqual(C._replacingNoteElement(in: en, "footnotePr", with: fn), fn + en)
        XCTAssertEqual(C._replacingNoteElement(in: fn, "endnotePr", with: en), fn + en)
    }

    /// Through the window: the dialog opens on "This section" where the section has its own, and applies there.
    func testDialogAppliesToThisSection() throws {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(1600, 2000))
        let s = ui.state(OfficeShellState.self)!.session
        let c = twoSections()
        s.controller.load(c.document)
        s.controller.moveTo(RichPosition(paragraph: 1, offset: 0), extend: false)
        ui.pump()
        s.onNoteOptions?(); ui.pump()
        var st = try XCTUnwrap(ui.state(FootnoteDialogState.self))
        XCTAssertFalse(st.thisSection)
        XCTAssertTrue(ui.tap(text: "This section")); ui.pump()
        XCTAssertTrue(ui.tap(text: "i, ii, iii")); ui.pump()
        XCTAssertTrue(ui.tap(text: "Apply")); ui.pump()
        XCTAssertEqual(marks(s.controller.document), ["1", "ii", "iii"])
        XCTAssertNotNil(s.controller.document.sectionNotesXML)
        s.onNoteOptions?(); ui.pump()
        st = try XCTUnwrap(ui.state(FootnoteDialogState.self))
        XCTAssertTrue(st.thisSection, "a section with its own opens on This section")
        XCTAssertEqual(st.options.format, .lowerRoman)
    }

    /// Writes the Word lab files (only when NOTE_SECTION_OUT names a folder).
    func testWriteWordLabFiles() throws {
        guard let out = ProcessInfo.processInfo.environment["NOTE_SECTION_OUT"] else { return }
        func make(_ name: String, _ steps: (RichDocumentController) -> Void) throws {
            var a = RichParagraph(text: "First section, with a footnote here and one more."); a.style.sectionXML = "<w:sectPr><w:pgSz w:w=\"12240\" w:h=\"15840\"/><w:pgMar w:top=\"1440\" w:right=\"1440\" w:bottom=\"1440\" w:left=\"1440\" w:header=\"720\" w:footer=\"720\" w:gutter=\"0\"/></w:sectPr>"
            a.style.sectionPage = .letter; a.style.sectionBreaksPage = true
            var b = RichParagraph(text: "Second section, with a footnote here and one more."); b.style.pageBreakBefore = true
            let c = RichDocumentController(document: RichDocument(paragraphs: [a, b]))
            var id = 0
            for p in [0, 1] {
                let text = c.document.paragraphs[p].text
                for k in 0 ..< 2 {
                    let o = k == 0 ? Array(text.utf16).count - " here and one more.".utf16.count : Array(c.document.paragraphs[p].text.utf16).count
                    c.moveTo(RichPosition(paragraph: p, offset: o), extend: false)
                    c.insertNote(.footnote); id += 1
                    _ = c.setNoteText(NoteReference(kind: .footnote, id: id), "Note \(id).")
                }
            }
            steps(c)
            try DocxFormat.write(c.document, pageSetup: .letter).write(to: URL(fileURLWithPath: out + "/" + name))
        }
        // The last section in lowercase roman, restarting; the first section in capitals, from 3.
        try make("fnsect-last.docx") { c in
            c.moveTo(RichPosition(paragraph: 1, offset: 0), extend: false)
            var o = c.sectionNoteOptions(.footnote); o.format = .lowerRoman; o.restart = "eachSect"
            c.setNoteOptions(.footnote, o, thisSection: true)
        }
        try make("fnsect-first.docx") { c in
            c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
            var o = c.sectionNoteOptions(.footnote); o.format = .upperLetter; o.start = 3; o.restart = "eachSect"
            c.setNoteOptions(.footnote, o, thisSection: true)
        }
    }
}
