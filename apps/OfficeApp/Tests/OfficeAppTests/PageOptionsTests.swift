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
        XCTAssertEqual(DocxFormat._leadPatched(lead, start: 7), "<w:pgNumType w:fmt=\"lowerRoman\" w:start=\"7\"/>")
        XCTAssertEqual(DocxFormat._leadPatched(lead, start: nil), "<w:pgNumType w:fmt=\"lowerRoman\"/>")
        XCTAssertEqual(DocxFormat._leadPatched(lead, start: 3), lead)
        XCTAssertNil(DocxFormat._leadPatched(nil, start: nil))
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
}
