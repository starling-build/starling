import XCTest
@testable import OfficeApp
@testable import OfficeText

/// W-PA-6: Layout > Breaks and Ctrl+Shift+Enter put a column break at the caret, held and saved as Word's own.
final class BreaksTests: XCTestCase {
    func testAColumnBreakSplitsTheParagraphAndIsOneUndoStep() {
        let c = RichDocumentController(document: RichDocument(plainText: "leftright"))
        c.selection = RichSelection(caret: RichPosition(paragraph: 0, offset: 4))
        c.insertColumnBreak()
        XCTAssertEqual(c.document.paragraphs.map(\.text), ["left", "right"])
        let s = c.document.paragraphs[1].style
        XCTAssertTrue(s.columnBreak && s.pageBreakBefore && s.breakEndsPrevious && !s.pageBreakInline)
        XCTAssertEqual(c.selection.focus, RichPosition(paragraph: 1, offset: 0))
        c.undo()
        XCTAssertEqual(c.document.paragraphs.map(\.text), ["leftright"])
    }

    func testTheSavedColumnBreakIsWordsAndReadsBack() throws {
        let c = RichDocumentController(document: RichDocument(plainText: "leftright"))
        c.selection = RichSelection(caret: RichPosition(paragraph: 0, offset: 4))
        c.insertColumnBreak()
        var setup = PageSetup.letter; setup.columns = 2
        let data = try DocxFormat.write(c.document, pageSetup: setup)
        let body = String(decoding: try XCTUnwrap(try Zip.read(data).first { $0.name == "word/document.xml" }).data, as: UTF8.self)
        let br = try XCTUnwrap(body.rangeOfSubstring("<w:br w:type=\"column\"/>"), "a Word column break")
        let left = try XCTUnwrap(body.rangeOfSubstring(">left<")), right = try XCTUnwrap(body.rangeOfSubstring(">right<"))
        XCTAssertTrue(left.upperBound < br.lowerBound && br.upperBound < right.lowerBound)
        XCTAssertEqual(body[left.upperBound ..< right.lowerBound].components(separatedBy: "<w:p>").count
                       + body[left.upperBound ..< right.lowerBound].components(separatedBy: "<w:p ").count, 3, "it ends the first paragraph")
        let back = try DocxFormat.read(data).document.paragraphs
        XCTAssertEqual(back.map(\.text), ["left", "right"])
        XCTAssertTrue(back[1].style.columnBreak && back[1].style.pageBreakBefore)
    }

    func testTheTextAfterAColumnBreakStartsTheNextColumn() {
        let c = RichDocumentController(document: RichDocument(plainText: "leftright"))
        c.selection = RichSelection(caret: RichPosition(paragraph: 0, offset: 4))
        c.insertColumnBreak()
        let theme = RichTextTheme(fontFamily: OfficeFonts.serif)
        theme.wordRules = true
        let layout = RichLayout(theme: theme, paragraphCount: c.document.paragraphs.count)
        var setup = PageSetup.letter; setup.columns = 2
        layout.pageSetup = setup
        layout.width = setup.columnWidth * theme.pixelsPerPoint
        layout.ensureLaidOut(c.document)
        let slot = { (k: Int) in layout.pieces.firstIndex { $0.contains { $0.paragraph == k } } }
        XCTAssertEqual(slot(0), 0)
        XCTAssertEqual(slot(1), 1, "the second column of the first page")
    }

    private func broken(_ kind: RichDocumentController.SectionBreakKind, header: String = "") -> RichDocumentController {
        var d = RichDocument(plainText: "leftright"); d.header = header
        let c = RichDocumentController(document: d)
        c.selection = RichSelection(caret: RichPosition(paragraph: 0, offset: 4))
        c.insertSectionBreak(kind, lastSetup: .letter)
        return c
    }

    private func pages(_ d: RichDocument) -> [Int] {
        let theme = RichTextTheme(fontFamily: OfficeFonts.serif)
        theme.wordRules = true
        let layout = RichLayout(theme: theme, paragraphCount: d.paragraphs.count)
        layout.pageSetup = d.lastSectionPage ?? .letter
        layout.width = PageSetup.letter.contentWidth * theme.pixelsPerPoint
        layout.ensureLaidOut(d)
        return d.paragraphs.indices.map { layout.pageNumber(ofParagraph: $0) ?? 0 }
    }

    func testASectionBreakEndsASectionAtTheCaretAndIsOneUndoStep() {
        let c = broken(.nextPage)
        XCTAssertEqual(c.document.paragraphs.map(\.text), ["left", "right"])
        XCTAssertNotNil(c.document.paragraphs[0].style.sectionXML)
        XCTAssertEqual(c.document.paragraphs[0].style.sectionBreaksPage, true)
        XCTAssertNil(c.document.paragraphs[1].style.sectionXML)
        XCTAssertTrue(c.document.paragraphs[1].style.pageBreakBefore, "as a file's section that starts a page is read")
        XCTAssertEqual(c.document.sectionTypeXML, "<w:type w:val=\"nextPage\"/>")
        XCTAssertEqual(c.selection.focus, RichPosition(paragraph: 1, offset: 0))
        c.undo()
        XCTAssertEqual(c.document.paragraphs.map(\.text), ["leftright"])
        XCTAssertNil(c.document.paragraphs[0].style.sectionXML)
        XCTAssertNil(c.document.sectionTypeXML)
    }

    func testEachSectionBreakStartsItsSectionWhereWordDoes() {
        XCTAssertEqual(pages(broken(.nextPage).document), [1, 2])
        XCTAssertEqual(pages(broken(.continuous).document), [1, 1])
        XCTAssertEqual(pages(broken(.oddPage).document), [1, 3], "page 2 is even: the section opens on page 3")
        XCTAssertEqual(pages(broken(.evenPage).document), [1, 2])
    }

    /// The new first section names the header too: Word gives a first section that names none no header at all.
    func testTheSavedBreakKeepsTheHeaderOnBothSections() throws {
        let data = try DocxFormat.write(broken(.oddPage, header: "H").document, pageSetup: .letter)
        let body = String(decoding: try XCTUnwrap(try Zip.read(data).first { $0.name == "word/document.xml" }).data, as: UTF8.self)
        let sects = body.components(separatedBy: "<w:sectPr").dropFirst()
        XCTAssertEqual(sects.count, 2, body)
        for s in sects {
            XCTAssertTrue(s.containsSubstring("<w:headerReference w:type=\"default\" r:id=\"rIdHeader\"/>"), s)
            XCTAssertTrue(s.containsSubstring("<w:pgSz w:w=\"12240\" w:h=\"15840\""), s)
        }
        XCTAssertFalse(sects.first!.containsSubstring("<w:type"), "the first section starts as the document did")
        XCTAssertTrue(sects.last!.containsSubstring("<w:type w:val=\"oddPage\"/>"))
        XCTAssertFalse(body.containsSubstring(RichDocumentController.sectionAsLast))
        let back = try DocxFormat.read(data).document
        XCTAssertEqual(back.paragraphs.map(\.text), ["left", "right"])
        XCTAssertEqual(back.paragraphs[0].style.sectionBreaksPage, true)
        XCTAssertEqual(back.header, "H")
    }

    func testABreakInAnEarlierSectionSetsTheStartOfTheRestOfIt() {
        let sect = "<w:sectPr><w:type w:val=\"continuous\"/><w:pgSz w:w=\"12240\" w:h=\"15840\"/></w:sectPr>"
        var a = RichParagraph(text: "onetwo"); a.style.sectionXML = sect; a.style.sectionPage = .letter; a.style.sectionBreaksPage = true
        let c = RichDocumentController(document: RichDocument(paragraphs: [a, RichParagraph(text: "three")]))
        c.selection = RichSelection(caret: RichPosition(paragraph: 0, offset: 3))
        c.insertSectionBreak(.evenPage, lastSetup: .letter)
        let p = c.document.paragraphs
        XCTAssertEqual(p.map(\.text), ["one", "two", "three"])
        XCTAssertEqual(p[0].style.sectionXML, sect, "the first part starts as the section did")
        XCTAssertEqual(p[1].style.sectionXML, "<w:sectPr><w:type w:val=\"evenPage\"/><w:pgSz w:w=\"12240\" w:h=\"15840\"/></w:sectPr>")
        XCTAssertEqual(p[1].style.sectionPage?.sectionStartParity, .even)
        XCTAssertEqual(p[1].style.sectionBreaksPage, true, "the section after it still starts a page")
        XCTAssertNil(p[2].style.sectionXML)
        XCTAssertEqual(RichDocumentController._sectionXML("<w:sectPr><w:headerReference r:id=\"a\"/><w:pgSz/></w:sectPr>", type: "<w:type w:val=\"oddPage\"/>"),
                       "<w:sectPr><w:headerReference r:id=\"a\"/><w:type w:val=\"oddPage\"/><w:pgSz/></w:sectPr>")
    }
}
