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

    /// 2 pages per sheet and Book fold: one setting each, replacing the other Multiple pages choices; the booklet's pages
    /// and a right-to-left booklet are kept.
    func testMultiplePagesSettingsReplaceEachOther() {
        let c = RichDocumentController(document: RichDocument(paragraphs: [RichParagraph()]))
        c.setMultiplePages(.mirror)
        c.setMultiplePages(.twoOnOne)
        XCTAssertEqual(c.document.marginSettingsXML, "<w:printTwoOnOne/>")
        XCTAssertEqual(c.multiplePages, .twoOnOne)
        c.setMultiplePages(.bookFold(pagesPerBooklet: 8))
        XCTAssertEqual(c.document.marginSettingsXML, "<w:bookFoldPrinting/><w:bookFoldPrintingSheets w:val=\"8\"/>")
        XCTAssertEqual(c.multiplePages, .bookFold(pagesPerBooklet: 8))
        c.undo()
        XCTAssertEqual(c.multiplePages, .twoOnOne, "one undo step each")
        XCTAssertEqual(RichDocumentController._multiplePages("<w:bookFoldRevPrinting/><w:gutterAtTop/>"), .bookFold(pagesPerBooklet: nil))
        let rev = RichDocumentController(document: { var d = RichDocument(paragraphs: [RichParagraph()]); d.marginSettingsXML = "<w:bookFoldRevPrinting/>"; return d }())
        rev.setMultiplePages(.bookFold(pagesPerBooklet: 4))
        XCTAssertEqual(rev.document.marginSettingsXML, "<w:bookFoldRevPrinting/><w:bookFoldPrintingSheets w:val=\"4\"/>")
        XCTAssertEqual(RichDocumentController._multiplePages("<w:printTwoOnOne w:val=\"0\"/>"), .normal)
    }

    /// Each setting is saved where the schema puts it (Word's own book-fold file has w:bookFoldPrinting after the
    /// default tab stop; a lab file with it before could not be printed), in a new file and in a file read back.
    func testMultiplePagesSaveInSchemaOrderAndRoundTrip() throws {
        let c = RichDocumentController(document: RichDocument(paragraphs: [RichParagraph(text: "one")]))
        func settings(_ d: RichDocument) throws -> String { try text(try Zip.read(DocxFormat.write(d, pageSetup: .letter)), "word/settings.xml") }
        func ordered(_ xml: String, _ names: [String]) {
            let at = names.map { xml.rangeOfSubstring($0)?.lowerBound }
            XCTAssertFalse(at.contains(where: { $0 == nil }), xml)
            XCTAssertEqual(at.compactMap { $0 }, at.compactMap { $0 }.sorted(), xml)
        }
        c.setMultiplePages(.bookFold(pagesPerBooklet: 12))
        var xml = try settings(c.document)
        ordered(xml, ["<w:defaultTabStop", "<w:bookFoldPrinting/>", "<w:bookFoldPrintingSheets w:val=\"12\"/>", "<w:characterSpacingControl"])
        let back = try DocxFormat.read(try DocxFormat.write(c.document, pageSetup: .letter))
        let reopened = RichDocumentController(document: back.document)
        XCTAssertEqual(reopened.multiplePages, .bookFold(pagesPerBooklet: 12))
        // A read file keeps its own settings part; the change still reaches it, and only once.
        reopened.setMultiplePages(.twoOnOne)
        xml = try settings(reopened.document)
        ordered(xml, ["<w:characterSpacingControl", "<w:printTwoOnOne/>", "<w:compat"])
        XCTAssertFalse(xml.containsSubstring("bookFold"), xml)
        XCTAssertEqual(xml.components(separatedBy: "<w:printTwoOnOne").count, 2, xml)
        reopened.setMultiplePages(.mirror)
        xml = try settings(reopened.document)
        ordered(xml, ["<w:mirrorMargins/>", "<w:defaultTabStop"])
        XCTAssertFalse(xml.containsSubstring("printTwoOnOne"), xml)
    }

    func testASettingsPartThatAlreadySaysSoIsLeftAsItIs() {
        let w = "<w:settings xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:zoom w:percent=\"140\"/><w:defaultTabStop w:val=\"720\"/><w:bookFoldPrinting/><w:characterSpacingControl w:val=\"doNotCompress\"/></w:settings>"
        XCTAssertEqual(DocxFormat._marginSettings(w, "<w:bookFoldPrinting/>"), w)
        let none = DocxFormat._marginSettings(w, nil)
        XCTAssertFalse(none.containsSubstring("bookFold"), none)
        let mirror = DocxFormat._marginSettings(w, "<w:mirrorMargins/>")
        XCTAssertTrue(mirror.containsSubstring("<w:zoom w:percent=\"140\"/><w:mirrorMargins/><w:defaultTabStop"), mirror)
    }

    /// 2 pages per sheet, from Word's prints (lab pg1c: T72 B36 L90 R54, gutter 18): the pair runs across the sheet's
    /// stated orientation; the first page of each pair mirrors the second, and the gutter goes to the fold.
    func testTwoPagesPerSheetPairsTheMargins() {
        func setup(sheetLandscape: Bool) -> PageSetup {
            var s = PageSetup(width: 792, height: 612, marginTop: 72, marginBottom: 36, marginLeft: 90, marginRight: 54)
            s.gutter = 18
            s.orientAcrossShape = !sheetLandscape
            return s
        }
        func lrtb(_ s: PageSetup) -> [Double] { [s.marginLeft, s.marginRight, s.marginTop, s.marginBottom, s.gutter] }
        var pair = RichLayout._twoUpPair(setup(sheetLandscape: true), gutterAtTop: false)
        XCTAssertEqual(lrtb(pair.first), [72, 90, 72, 36, 0]); XCTAssertEqual(lrtb(pair.second), [90, 72, 72, 36, 0])
        pair = RichLayout._twoUpPair(setup(sheetLandscape: false), gutterAtTop: false)
        XCTAssertEqual(lrtb(pair.first), [90, 54, 54, 72, 0]); XCTAssertEqual(lrtb(pair.second), [90, 54, 72, 54, 0])
        pair = RichLayout._twoUpPair(setup(sheetLandscape: true), gutterAtTop: true)
        XCTAssertEqual(lrtb(pair.first), [72, 72, 90, 36, 0]); XCTAssertEqual(lrtb(pair.second), [90, 54, 90, 36, 0])
    }

    /// A sheet's stated orientation that runs across the page's shape (portrait on a wide page) is read and saved as it was.
    func testTheStatedSheetOrientationAcrossThePageShapeRoundTrips() throws {
        var s = PageSetup(width: 792, height: 612)
        s.orientAcrossShape = true
        XCTAssertFalse(s.sheetLandscape)
        let doc = RichDocument(paragraphs: [RichParagraph(text: "one")])
        let data = try DocxFormat.write(doc, pageSetup: s)
        XCTAssertTrue(try text(try Zip.read(data), "word/document.xml").containsSubstring("w:orient=\"portrait\""))
        let back = try XCTUnwrap(DocxFormat.read(data).pageSetup)
        XCTAssertTrue(back.isLandscape); XCTAssertTrue(back.orientAcrossShape)
        let again = try text(try Zip.read(DocxFormat.write(doc, pageSetup: back)), "word/document.xml")
        XCTAssertTrue(again.containsSubstring("w:orient=\"portrait\""), again)
    }
}
