import XCTest
@testable import OfficeApp
@testable import OfficeText

/// W-PG-1: the Page Setup dialog's gutter and Multiple pages (Mirror margins) on the Margins tab and the vertical
/// alignment on the Layout tab: one undo step for the dialog, kept by the saved file.
final class PageGutterAlignTests: XCTestCase {
    private func text(_ parts: [ZipEntry], _ name: String) throws -> String {
        String(decoding: try XCTUnwrap(parts.first { $0.name == name }).data, as: UTF8.self)
    }

    func testGutterAlignmentAndMirrorAreOneUndoStepAndRoundTrip() throws {
        let c = RichDocumentController(document: RichDocument(paragraphs: [RichParagraph(text: "one")]))
        var v = PageSetupValues(.letter)
        v.gutter = 36; v.verticalAlign = "center"; v.mirror = true
        c.edit {
            c.changePageSetup(allSections: false, lastSetup: .letter) { v.apply(to: &$0) }
            c.setMirrorMargins(v.mirror)
        }
        let page = try XCTUnwrap(c.document.lastSectionPage)
        XCTAssertEqual(page.gutter, 36); XCTAssertEqual(page.verticalAlign, "center"); XCTAssertTrue(c.mirrorMargins)

        let data = try DocxFormat.write(c.document, pageSetup: page)
        let parts = try Zip.read(data)
        let body = try text(parts, "word/document.xml")
        XCTAssertTrue(body.containsSubstring("w:gutter=\"720\""), body)
        XCTAssertTrue(body.containsSubstring("<w:vAlign w:val=\"center\"/>"), body)
        XCTAssertTrue(try text(parts, "word/settings.xml").containsSubstring("<w:mirrorMargins/>"))
        let back = try DocxFormat.read(data)
        XCTAssertEqual(back.pageSetup?.gutter, 36); XCTAssertEqual(back.pageSetup?.verticalAlign, "center")
        XCTAssertTrue(RichDocumentController._mirrorMargins(back.document.marginSettingsXML))

        c.undo()
        XCTAssertFalse(c.mirrorMargins)
        XCTAssertEqual(c.document.lastSectionPage?.gutter ?? 0, 0)
        XCTAssertNil(c.document.lastSectionPage?.verticalAlign)
        XCTAssertFalse(c.canUndo, "the dialog is one step")
    }

    func testTheLastSectionWritesItsAlignmentBeforeTheTitlePageAndTheKeptTailAfter() throws {
        var d = RichDocument(paragraphs: [RichParagraph(text: "one")])
        d.titlePage = true
        d.sectionTailXML = "<w:vAlign w:val=\"bottom\"/><w:textDirection w:val=\"lrTb\"/>"
        var page = PageSetup.letter; page.verticalAlign = "both"
        let body = try text(try Zip.read(DocxFormat.write(d, pageSetup: page)), "word/document.xml")
        XCTAssertFalse(body.containsSubstring("w:val=\"bottom\""), "the page's own alignment replaces the file's")
        let order = ["<w:vAlign w:val=\"both\"/>", "<w:titlePg/>", "<w:textDirection"].map { body.rangeOfSubstring($0)?.lowerBound }
        XCTAssertFalse(order.contains(where: { $0 == nil }), body)
        XCTAssertEqual(order.compactMap { $0 }, order.compactMap { $0 }.sorted(), body)
    }

    func testAKeptSectionTakesItsGutterAndAlignmentInSchemaOrder() {
        let w = "xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\""
        let sect = "<w:sectPr \(w)><w:pgSz w:w=\"12240\" w:h=\"15840\"/><w:pgMar w:top=\"1440\" w:right=\"1440\" w:bottom=\"1440\" w:left=\"1440\" w:header=\"720\" w:footer=\"720\"/><w:cols w:space=\"720\"/><w:titlePg/><w:docGrid w:linePitch=\"360\"/></w:sectPr>"
        var page = PageSetup.letter
        page.marginTop = 72; page.marginBottom = 72; page.marginLeft = 72; page.marginRight = 72
        page.headerDistance = 36; page.footerDistance = 36; page.titlePage = true
        XCTAssertEqual(DocxFormat._sectionXML(sect, patchedTo: page), sect, "no gutter and top alignment: unchanged")
        page.gutter = 18; page.verticalAlign = "bottom"
        let out = DocxFormat._sectionXML(sect, patchedTo: page)
        XCTAssertTrue(out.containsSubstring("w:gutter=\"360\""), out)
        let order = ["<w:cols", "<w:vAlign w:val=\"bottom\"", "<w:titlePg", "<w:docGrid"].map { out.rangeOfSubstring($0)?.lowerBound }
        XCTAssertFalse(order.contains(where: { $0 == nil }), out)
        XCTAssertEqual(order.compactMap { $0 }, order.compactMap { $0 }.sorted(), out)
        page.gutter = 0; page.verticalAlign = nil
        let back = DocxFormat._sectionXML(out, patchedTo: page)
        XCTAssertFalse(back.containsSubstring("vAlign"), back)
        XCTAssertTrue(back.containsSubstring("w:gutter=\"0\""), back)
    }

    func testMirrorMarginsKeepTheFilesGutterPosition() {
        var d = RichDocument(paragraphs: [RichParagraph()])
        d.marginSettingsXML = "<w:gutterAtTop/>"
        let c = RichDocumentController(document: d)
        c.setMirrorMargins(true)
        XCTAssertEqual(c.document.marginSettingsXML, "<w:mirrorMargins/><w:gutterAtTop/>")
        c.setMirrorMargins(false)
        XCTAssertEqual(c.document.marginSettingsXML, "<w:gutterAtTop/>")
        XCTAssertFalse(RichDocumentController._mirrorMargins("<w:mirrorMargins w:val=\"0\"/>"))
    }
}
