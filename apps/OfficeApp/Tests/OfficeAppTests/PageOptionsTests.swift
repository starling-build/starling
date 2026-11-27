import XCTest
@testable import OfficeApp
@testable import OfficeText

/// W-HF-2: different first page, different odd and even pages and the first page number, set from the
/// Page Setup dialog's Layout tab and kept by the saved file.
final class PageOptionsTests: XCTestCase {
    private func text(_ parts: [ZipEntry], _ name: String) throws -> String {
        String(decoding: try XCTUnwrap(parts.first { $0.name == name }).data, as: UTF8.self)
    }

    func testThePageOptionsAreOneUndoStep() {
        let c = RichDocumentController(document: RichDocument(paragraphs: [RichParagraph()]))
        let before = c.pageOptions(sectionMark: -1)
        let new = RichDocumentController.PageOptions(titlePage: true, evenAndOdd: true, pageNumberStart: 5)
        c.changePageOptions(allSections: false, new, lastSetup: .letter)
        XCTAssertEqual(c.pageOptions(sectionMark: -1), new)
        c.undo()
        XCTAssertEqual(c.pageOptions(sectionMark: -1), before)
    }

    func testTheSavedFileKeepsTheLastSectionsOptions() throws {
        var d = RichDocument(paragraphs: [RichParagraph()])
        d.titlePage = true; d.evenAndOddHeaders = true; d.pageNumberStart = 5
        let parts = try Zip.read(DocxFormat.write(d, pageSetup: .letter))
        let body = try text(parts, "word/document.xml")
        XCTAssertTrue(body.containsSubstring("<w:titlePg/>"))
        XCTAssertTrue(body.containsSubstring("<w:pgNumType w:start=\"5\"/>"), "the first page number")
        // (No section has an even header: Word still leaves the even pages bare, so the setting stays.)
        XCTAssertTrue(try text(parts, "word/settings.xml").containsSubstring("<w:evenAndOddHeaders/>"))
    }

    func testTheFirstPageNumberKeepsTheFilesOtherNumbering() {
        let lead = "<w:pgNumType w:fmt=\"lowerRoman\" w:start=\"3\"/>"
        XCTAssertEqual(DocxFormat._leadPatched(lead, start: 7, format: "lowerRoman", chapterStyle: nil, chapterSeparator: nil), "<w:pgNumType w:fmt=\"lowerRoman\" w:start=\"7\"/>")
        XCTAssertEqual(DocxFormat._leadPatched(lead, start: nil, format: "lowerRoman", chapterStyle: nil, chapterSeparator: nil), "<w:pgNumType w:fmt=\"lowerRoman\"/>")
        XCTAssertEqual(DocxFormat._leadPatched(lead, start: 3, format: "lowerRoman", chapterStyle: nil, chapterSeparator: nil), lead)
        XCTAssertNil(DocxFormat._leadPatched(nil, start: nil, format: nil, chapterStyle: nil, chapterSeparator: nil))
    }

    func testAKeptSectionTakesItsFirstPageAndNumberInSchemaOrder() {
        let w = "xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\""
        let sect = "<w:sectPr \(w)><w:pgSz w:w=\"12240\" w:h=\"15840\"/><w:pgMar w:top=\"1440\" w:right=\"1440\" w:bottom=\"1440\" w:left=\"1440\" w:header=\"720\" w:footer=\"720\" w:gutter=\"0\"/><w:cols w:space=\"720\"/><w:docGrid w:linePitch=\"360\"/></w:sectPr>"
        var page = PageSetup.letter
        page.marginTop = 72; page.marginBottom = 72; page.marginLeft = 72; page.marginRight = 72
        page.headerDistance = 36; page.footerDistance = 36
        page.titlePage = true; page.pageNumberStart = 2
        let out = DocxFormat._sectionXML(sect, patchedTo: page)
        let order = ["<w:pgMar", "<w:pgNumType w:start=\"2\"", "<w:cols", "<w:titlePg", "<w:docGrid"].map { out.rangeOfSubstring($0)?.lowerBound }
        XCTAssertFalse(order.contains(where: { $0 == nil }), out)
        XCTAssertEqual(order.compactMap { $0 }, order.compactMap { $0 }.sorted(), out)
        page.titlePage = false; page.pageNumberStart = nil
        let back = DocxFormat._sectionXML(out, patchedTo: page)
        XCTAssertFalse(back.containsSubstring("titlePg") || back.containsSubstring("pgNumType"), back)
    }

    func testThePageNumberFormatIsOneUndoStepAndSaved() throws {
        let c = RichDocumentController(document: RichDocument(paragraphs: [RichParagraph()]))
        var new = c.pageOptions(sectionMark: -1); new.pageNumberFormat = "lowerRoman"
        c.changePageOptions(allSections: false, new, lastSetup: .letter)
        XCTAssertEqual(c.document.pageNumberFormat, "lowerRoman")
        let body = try text(try Zip.read(DocxFormat.write(c.document, pageSetup: .letter)), "word/document.xml")
        XCTAssertTrue(body.containsSubstring("<w:pgNumType w:fmt=\"lowerRoman\"/>"), "the number format")
        c.undo()
        XCTAssertNil(c.document.pageNumberFormat)
    }

    func testTheNumberFormatPatchesTheFilesNumbering() {
        let lead = "<w:pgNumType w:fmt=\"lowerRoman\" w:start=\"3\" w:chapStyle=\"1\"/>"
        XCTAssertEqual(DocxFormat._leadPatched(lead, start: 3, format: "upperLetter", chapterStyle: 1, chapterSeparator: nil),
                       "<w:pgNumType w:fmt=\"upperLetter\" w:start=\"3\" w:chapStyle=\"1\"/>")
        XCTAssertEqual(DocxFormat._leadPatched(lead, start: 3, format: "lowerRoman", chapterStyle: 1, chapterSeparator: nil), lead)
        XCTAssertEqual(DocxFormat._leadPatched("<w:pgNumType w:fmt=\"lowerRoman\"/>", start: nil, format: nil, chapterStyle: nil, chapterSeparator: nil), nil)
        XCTAssertEqual(DocxFormat._leadPatched(nil, start: 2, format: "upperRoman", chapterStyle: nil, chapterSeparator: nil), "<w:pgNumType w:fmt=\"upperRoman\" w:start=\"2\"/>")
        let w = "xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\""
        let sect = "<w:sectPr \(w)><w:pgSz w:w=\"12240\" w:h=\"15840\"/><w:pgNumType w:fmt=\"lowerRoman\"/><w:cols w:space=\"720\"/></w:sectPr>"
        var page = PageSetup.letter
        page.pageNumberFormat = "lowerRoman"
        XCTAssertEqual(DocxFormat._sectionXML(sect, patchedTo: page), sect, "an untouched format writes back as it was")
        page.pageNumberFormat = "upperRoman"
        XCTAssertTrue(DocxFormat._sectionXML(sect, patchedTo: page).containsSubstring("<w:pgNumType w:fmt=\"upperRoman\"/>"))
        page.pageNumberFormat = nil
        XCTAssertFalse(DocxFormat._sectionXML(sect, patchedTo: page).containsSubstring("pgNumType"))
    }

    func testTheChapterNumberIsSavedAndUndone() throws {
        let c = RichDocumentController(document: RichDocument(paragraphs: [RichParagraph()]))
        var new = c.pageOptions(sectionMark: -1); new.chapterStyle = 2; new.chapterSeparator = "emDash"
        c.changePageOptions(allSections: false, new, lastSetup: .letter)
        let body = try text(try Zip.read(DocxFormat.write(c.document, pageSetup: .letter)), "word/document.xml")
        XCTAssertTrue(body.containsSubstring("<w:pgNumType w:chapStyle=\"2\" w:chapSep=\"emDash\"/>"), body)
        let back = try DocxFormat.read(DocxFormat.write(c.document, pageSetup: .letter))
        XCTAssertEqual(back.document.chapterStyle, 2); XCTAssertEqual(back.document.chapterSeparator, "emDash")
        c.undo()
        XCTAssertNil(c.document.chapterStyle)
        let w = "xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\""
        let sect = "<w:sectPr \(w)><w:pgSz w:w=\"12240\" w:h=\"15840\"/><w:pgNumType w:start=\"1\"/></w:sectPr>"
        var page = PageSetup.letter; page.pageNumberStart = 1; page.chapterStyle = 1; page.chapterSeparator = "period"
        let out = DocxFormat._sectionXML(sect, patchedTo: page)
        XCTAssertTrue(out.containsSubstring("w:chapStyle=\"1\"") && out.containsSubstring("w:chapSep=\"period\"") && out.containsSubstring("w:start=\"1\""), out)
    }

    /// Three sections: the first names header A, the second names none (so shows A), the last names header C.
    private func threeSections() throws -> RichDocument {
        var d = RichDocument(paragraphs: [RichParagraph(text: "one"), RichParagraph(text: "two"), RichParagraph(text: "three")])
        d.header = "A"
        var entries = try Zip.read(DocxFormat.write(d, pageSetup: .letter))
        let c = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<w:hdr xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:p><w:r><w:t>C</w:t></w:r></w:p></w:hdr>"
        entries.append(ZipEntry(name: "word/header9.xml", data: Data(c.utf8)))
        let ri = entries.firstIndex { $0.name == "word/_rels/document.xml.rels" }!
        entries[ri] = ZipEntry(name: entries[ri].name, data: Data(String(decoding: entries[ri].data, as: UTF8.self).replacingAll("</Relationships>", with: "<Relationship Id=\"rIdC\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/header\" Target=\"header9.xml\"/></Relationships>").utf8))
        let ci = entries.firstIndex { $0.name == "[Content_Types].xml" }!
        entries[ci] = ZipEntry(name: entries[ci].name, data: Data(String(decoding: entries[ci].data, as: UTF8.self).replacingAll("</Types>", with: "<Override PartName=\"/word/header9.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml\"/></Types>").utf8))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        let xml = String(decoding: entries[di].data, as: UTF8.self)
        let open = try XCTUnwrap(xml.rangeOfSubstring("<w:body>")), close = try XCTUnwrap(xml.rangeOfSubstring("</w:body>"))
        let page = "<w:pgSz w:w=\"12240\" w:h=\"15840\"/><w:pgMar w:top=\"1440\" w:right=\"1440\" w:bottom=\"1440\" w:left=\"1440\" w:header=\"720\" w:footer=\"720\" w:gutter=\"0\"/>"
        func p(_ t: String, _ sect: String) -> String { "<w:p><w:pPr><w:sectPr>\(sect)\(page)</w:sectPr></w:pPr><w:r><w:t>\(t)</w:t></w:r></w:p>" }
        let body = p("one", "<w:headerReference w:type=\"default\" r:id=\"rIdHeader\"/>") + p("two", "")
            + "<w:p><w:r><w:t>three</w:t></w:r></w:p><w:sectPr><w:headerReference w:type=\"default\" r:id=\"rIdC\"/>\(page)</w:sectPr>"
        entries[di] = ZipEntry(name: "word/document.xml", data: Data((String(xml[..<open.upperBound]) + body + String(xml[close.lowerBound...])).utf8))
        return try DocxFormat.read(try Zip.write(entries)).document
    }
    private func shown(_ d: RichDocument) -> [String] {
        (0..<3).map { s in d.headerFooters.first { $0.kind == .header && $0.type == "default" && $0.section == s }?.paragraphs.map(\.text).joined() ?? "-" }
    }

    func testLinkToPreviousShowsAndSavesTheSectionBeforesHeader() throws {
        let d = try threeSections()
        XCTAssertEqual(shown(d), ["A", "A", "C"])
        let c = RichDocumentController(document: d)
        XCTAssertNil(c.linkedToPrevious(paragraph: 0, kind: .header), "the first section has nothing before it")
        XCTAssertEqual(c.linkedToPrevious(paragraph: 1, kind: .header), true)
        XCTAssertEqual(c.linkedToPrevious(paragraph: 2, kind: .header), false)
        XCTAssertEqual(c.linkedToPrevious(paragraph: 2, kind: .footer), true)
        // Linking the last section: its pages show A, and the saved file names no header there.
        XCTAssertTrue(c.setLinkToPrevious(true, paragraph: 2, kind: .header))
        XCTAssertEqual(shown(c.document), ["A", "A", "A"])
        XCTAssertEqual(c.linkedToPrevious(paragraph: 2, kind: .header), true)
        var back = try DocxFormat.read(try DocxFormat.write(c.document, pageSetup: .letter)).document
        XCTAssertEqual(shown(back), ["A", "A", "A"])
        c.undo()
        XCTAssertEqual(shown(c.document), ["A", "A", "C"], "one undo step")
        XCTAssertEqual(c.document.keptHeaderFooters, d.keptHeaderFooters)
        // Unlinking the second: it names A itself, and keeps showing it after a save.
        XCTAssertTrue(c.setLinkToPrevious(false, paragraph: 1, kind: .header))
        XCTAssertEqual(c.linkedToPrevious(paragraph: 1, kind: .header), false)
        XCTAssertFalse(c.setLinkToPrevious(false, paragraph: 1, kind: .header), "already its own")
        back = try DocxFormat.read(try DocxFormat.write(c.document, pageSetup: .letter)).document
        XCTAssertEqual(shown(back), ["A", "A", "C"])
        XCTAssertEqual(RichDocumentController(document: back).linkedToPrevious(paragraph: 1, kind: .header), false)
        // And linking it again drops that reference.
        XCTAssertTrue(c.setLinkToPrevious(true, paragraph: 1, kind: .header))
        XCTAssertFalse(c.document.paragraphs[1].style.sectionXML?.containsSubstring("headerReference") ?? true)
        XCTAssertFalse(c.setLinkToPrevious(false, paragraph: 0, kind: .header), "nothing before the first section")
    }
}
