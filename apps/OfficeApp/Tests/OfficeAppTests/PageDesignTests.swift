import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp
@testable import OfficeText

/// W-PG-3: Design > Page Color, Watermark, Page Borders; Layout > Line Numbers.
final class PageDesignTests: XCTestCase {
    private func controller(_ texts: [String] = ["One", "Two"]) -> RichDocumentController {
        let c = RichDocumentController()
        c.load(RichDocument(paragraphs: texts.map { RichParagraph(text: $0) }))
        return c
    }

    private func roundTrip(_ d: RichDocument, _ page: PageSetup = .letter) throws -> (RichDocument, [String: Data]) {
        let data = try DocxFormat.write(d, pageSetup: page)
        let parts = Dictionary(try Zip.read(data).map { ($0.name, $0.data) }, uniquingKeysWith: { a, _ in a })
        return (try DocxFormat.read(data).document, parts)
    }

    private func text(_ parts: [String: Data], _ name: String) -> String { parts[name].map { String(decoding: $0, as: UTF8.self) } ?? "" }

    func testPageColorSavesWithDisplaySettingAndUndoes() throws {
        let c = controller()
        c.setPageColor(0xFFF2CC)
        XCTAssertEqual(c.document.backgroundColor, 0xFFF2CC)
        let (back, parts) = try roundTrip(c.document)
        XCTAssertEqual(back.backgroundColor, 0xFFF2CC)
        XCTAssertTrue(text(parts, "word/document.xml").containsSubstring("<w:background w:color=\"FFF2CC\"/>"))
        XCTAssertTrue(text(parts, "word/settings.xml").containsSubstring("<w:displayBackgroundShape/>"))
        c.setPageColor(nil)
        XCTAssertNil(c.document.backgroundColor)
        c.undo()
        XCTAssertEqual(c.document.backgroundColor, 0xFFF2CC)
        c.undo()
        XCTAssertNil(c.document.backgroundColor)
        XCTAssertFalse(text(try roundTrip(c.document).1, "word/settings.xml").containsSubstring("displayBackgroundShape"))
    }

    func testDisplayBackgroundShapeGoesAfterZoom() {
        let s = DocxFormat._displayBackgroundShapeSetting("<w:settings x=\"1\"><w:zoom w:percent=\"100\"/><w:defaultTabStop w:val=\"720\"/></w:settings>")
        XCTAssertEqual(s, "<w:settings x=\"1\"><w:zoom w:percent=\"100\"/><w:displayBackgroundShape/><w:defaultTabStop w:val=\"720\"/></w:settings>")
        XCTAssertEqual(DocxFormat._displayBackgroundShapeSetting(s), s)
    }

    func testPageBordersRoundTripAndScopes() throws {
        let c = controller()
        var b = PageBorders()
        b.style = "double"; b.width = 6; b.color = 0x2F5496
        c.setPageBorders(b, scope: .wholeDocument)
        XCTAssertEqual(c.sectionPageBorders(), b)
        let (back, parts) = try roundTrip(c.document)
        XCTAssertTrue(text(parts, "word/document.xml").containsSubstring("<w:pgBorders w:offsetFrom=\"page\"><w:top w:val=\"double\" w:sz=\"6\" w:space=\"24\" w:color=\"2F5496\"/>"))
        XCTAssertEqual(back.pageBordersXML.flatMap(PageBorders.init(xml:)), b)
        c.setPageBorders(b, scope: .thisSectionFirstPage)
        XCTAssertTrue(c.document.pageBordersXML?.containsSubstring("w:display=\"firstPage\"") == true)
        c.setPageBorders(nil, scope: .wholeDocument)
        XCTAssertNil(c.document.pageBordersXML)
        c.undo()
        XCTAssertNotNil(c.document.pageBordersXML)
        // From the text: Word's own distances.
        XCTAssertEqual(PageBorders.defaultSpace(from: "text")[.left], 4)
        XCTAssertEqual(PageBorders.replacing(in: "<w:sectPr><w:pgSz w:w=\"1\"/><w:pgMar w:top=\"1\"/><w:cols/></w:sectPr>", with: "<w:pgBorders/>"),
                       "<w:sectPr><w:pgSz w:w=\"1\"/><w:pgMar w:top=\"1\"/><w:pgBorders/><w:cols/></w:sectPr>")
    }

    /// A section made by a break in the last one is saved as a copy of it; its own borders (or none) must still be saved.
    func testPageBordersOnASectionMadeByABreak() throws {
        let c = controller((1...6).map { "P\($0)" })
        c.moveTo(RichPosition(paragraph: 3, offset: 0), extend: false)
        c.insertSectionBreak(.nextPage, lastSetup: .letter)
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        var b = PageBorders(); b.style = "double"
        c.setPageBorders(b, scope: .thisSectionFirstPage)
        var doc = text(try roundTrip(c.document).1, "word/document.xml")
        var sects = doc.components(separatedBy: "<w:sectPr")
        XCTAssertEqual(sects.count, 3)
        XCTAssertTrue(sects[1].containsSubstring("w:display=\"firstPage\"><w:top w:val=\"double\""), sects[1])
        XCTAssertFalse(sects[2].containsSubstring("pgBorders"))
        XCTAssertEqual(c.sectionPageBorders()?.display, "firstPage")
        // Borders on the last section only: the first keeps its own; then none on the first while the last has them.
        c.moveTo(RichPosition(paragraph: c.document.paragraphs.count - 1, offset: 0), extend: false)
        b.style = "single"
        c.setPageBorders(b, scope: .thisSection)
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        c.setPageBorders(nil, scope: .thisSection)
        XCTAssertNil(c.sectionPageBorders())
        doc = text(try roundTrip(c.document).1, "word/document.xml")
        sects = doc.components(separatedBy: "<w:sectPr")
        XCTAssertFalse(sects[1].containsSubstring("pgBorders"), sects[1])
        XCTAssertFalse(doc.containsSubstring("x-none"))
        XCTAssertTrue(sects[2].containsSubstring("<w:pgBorders w:offsetFrom=\"page\"><w:top w:val=\"single\""), sects[2])
    }

    func testLineNumbersWriteAndSuppress() throws {
        let c = controller(["a", "b", "c"])
        var n = LineNumbering()
        n.countBy = 5; n.start = 3; n.restart = .continuous
        c.setLineNumbers(n, lastSetup: .letter)
        let page = c.document.lastSectionPage ?? .letter
        XCTAssertEqual(page.lineNumbers, n)
        let (back, parts) = try roundTrip(c.document, page)
        XCTAssertTrue(text(parts, "word/document.xml").containsSubstring("<w:lnNumType w:countBy=\"5\" w:start=\"2\" w:restart=\"continuous\"/>"))   // zero-based: Word shows 3 first (lab/pg3)
        _ = back
        XCTAssertEqual(try DocxFormat.read(try DocxFormat.write(c.document, pageSetup: page)).pageSetup?.lineNumbers, n)
        c.moveTo(RichPosition(paragraph: 1, offset: 0), extend: false)
        c.toggleSuppressLineNumbers()
        XCTAssertTrue(c.lineNumbersSuppressed)
        let saved = text(try roundTrip(c.document, page).1, "word/document.xml")
        XCTAssertTrue(saved.containsSubstring("<w:suppressLineNumbers/>") || saved.containsSubstring("<w:suppressLineNumbers w:val=\"1\"/>"))
        c.toggleSuppressLineNumbers()
        XCTAssertFalse(c.lineNumbersSuppressed)
        // Unchanged numbering keeps the file's element byte for byte.
        XCTAssertEqual(DocxFormat._lineNumbersPatched("<w:lnNumType w:restart=\"continuous\" w:countBy=\"1\"/>", {
            var l = LineNumbering(); l.restart = .continuous; return l }()), "<w:lnNumType w:restart=\"continuous\" w:countBy=\"1\"/>")
        XCTAssertNil(DocxFormat._lineNumbersPatched("<w:lnNumType w:countBy=\"1\"/>", nil))
        XCTAssertEqual(DocxFormat._lineNumbersPatched("<w:pgNumType w:start=\"2\"/>", LineNumbering()), "<w:lnNumType w:countBy=\"1\"/><w:pgNumType w:start=\"2\"/>")
    }

    /// Word (lab/pg3): w:start="3" starts the count at 4; no w:start starts at 1.
    func testLineNumberStartIsZeroBasedInTheFile() throws {
        func read(_ el: String) throws -> LineNumbering {
            try DocxFormat._readLineNumbers(XCTUnwrap(XNode.parse(Data(el.utf8))))
        }
        XCTAssertEqual(try read("<w:lnNumType w:countBy=\"5\" w:start=\"3\"/>").start, 4)
        XCTAssertEqual(try read("<w:lnNumType w:countBy=\"1\"/>").start, 1)
        var n = LineNumbering(); n.start = 4
        XCTAssertEqual(DocxFormat._lineNumbersXML(n), "<w:lnNumType w:countBy=\"1\" w:start=\"3\"/>")
        n.start = 1
        XCTAssertEqual(DocxFormat._lineNumbersXML(n), "<w:lnNumType w:countBy=\"1\"/>")
        // The file's element is kept byte for byte when it already says the same.
        n.start = 4
        XCTAssertEqual(DocxFormat._lineNumbersPatched("<w:lnNumType w:countBy=\"1\" w:start=\"3\"/>", n), "<w:lnNumType w:countBy=\"1\" w:start=\"3\"/>")
    }

    func testTextWatermarkInEveryHeaderAndRemoved() throws {
        let c = controller()
        var t = WordWatermark.TextMark()
        t.text = "DRAFT"
        let d = try WordWatermark.setting(.text(t), in: c.document, page: .letter)
        c.replaceDocument(with: d)
        XCTAssertTrue(WordWatermark.has(in: c.document))
        XCTAssertEqual(WordWatermark.current(in: c.document)?.text, "DRAFT")
        XCTAssertEqual(WordWatermark.current(in: c.document)?.diagonal, true)
        let (_, parts) = try roundTrip(c.document)
        let doc = text(parts, "word/document.xml")
        XCTAssertTrue(doc.containsSubstring("<w:headerReference w:type=\"default\""))
        let header = parts.keys.filter { $0.hasPrefix("word/header") }.map { text(parts, $0) }.joined()
        XCTAssertTrue(header.containsSubstring("string=\"DRAFT\""), header)
        XCTAssertTrue(header.containsSubstring("rotation:315"))
        // Replaced, not doubled; then removed; undo brings it back.
        t.text = "SAMPLE"; t.diagonal = false
        c.replaceDocument(with: try WordWatermark.setting(.text(t), in: c.document, page: .letter))
        let h2 = try roundTrip(c.document).1.filter { $0.key.hasPrefix("word/header") }.map { text([$0.key: $0.value], $0.key) }.joined()
        XCTAssertFalse(h2.containsSubstring("DRAFT"))
        XCTAssertEqual(h2.components(separatedBy: "PowerPlusWaterMarkObject").count - 1, 1, h2)
        XCTAssertFalse(h2.containsSubstring("rotation:315"))
        c.replaceDocument(with: try WordWatermark.setting(nil, in: c.document, page: .letter))
        XCTAssertFalse(WordWatermark.has(in: c.document))
        c.undo()
        XCTAssertEqual(WordWatermark.current(in: c.document)?.text, "SAMPLE")
    }

    func testTextWatermarkKeepsTheHeaderText() throws {
        let c = controller()
        var d = c.document
        d.header = "Company"
        c.load(d)
        let w = try WordWatermark.setting(.text(WordWatermark.TextMark()), in: c.document, page: .letter)
        let (back, parts) = try roundTrip(w)
        let header = parts.keys.filter { $0.hasPrefix("word/header") }.map { text(parts, $0) }.joined()
        XCTAssertTrue(header.containsSubstring("Company"), header)
        XCTAssertTrue(header.containsSubstring("CONFIDENTIAL"))
        XCTAssertTrue(WordWatermark.has(in: back))
    }

    func testPictureWatermarkWritesMediaAndRels() throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + Array(repeating: UInt8(0), count: 32))
        let p = WordWatermark.PictureMark(data: png, ext: "png", name: "logo", naturalWidth: 100, naturalHeight: 50, scale: 2, washout: true)
        let d = try WordWatermark.setting(.picture(p), in: controller().document, page: .letter)
        let (_, parts) = try roundTrip(d)
        XCTAssertEqual(parts["word/media/watermark1.png"], png)
        let header = parts.keys.filter { $0.hasPrefix("word/header") && $0.hasSuffix(".xml") }.map { text(parts, $0) }.joined()
        XCTAssertTrue(header.containsSubstring("WordPictureWatermark"))
        XCTAssertTrue(header.containsSubstring("width:200pt;height:100pt"))
        XCTAssertTrue(header.containsSubstring("gain=\"19661f\" blacklevel=\"22938f\""))
        let rels = parts.keys.filter { $0.hasPrefix("word/_rels/header") }.map { text(parts, $0) }.joined()
        XCTAssertTrue(rels.containsSubstring("Target=\"media/watermark1.png\""), rels)
        let types = text(parts, "[Content_Types].xml")
        XCTAssertTrue(types.containsSubstring("Extension=\"png\"") || types.containsSubstring("PartName=\"/word/media/watermark1.png\" ContentType=\"image/png\""), types)
    }

    func testDialogsApplyLineNumbersBordersAndWatermark() {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(1280, 800))
        let state = ui.state(OfficeShellState.self)!
        let c = state.session.controller
        c.insertText("Hello")
        XCTAssertEqual(RibbonTab.strip(for: .document)[2], .design)
        // Layout > Line Numbers > Line Numbering Options…: on, count by 5.
        state.session.onLineNumbersDialog?()
        ui.pump()
        let ln = ui.state(LineNumbersDialogState.self)!
        XCTAssertFalse(ln.on)
        ln.on = true; ln.n.countBy = 5
        ln.ok()
        ui.pump()
        XCTAssertNil(ui.state(LineNumbersDialogState.self))
        XCTAssertEqual(state.session.sectionSetup().lineNumbers?.countBy, 5)
        XCTAssertEqual(state.session.pageSetup.lineNumbers?.countBy, 5)
        // Design > Page Borders: a double box.
        state.session.onPageBordersDialog?()
        ui.pump()
        let pb = ui.state(PageBordersDialogState.self)!
        pb.setting = .box; pb.b.style = "double"
        pb.ok()
        ui.pump()
        XCTAssertEqual(c.sectionPageBorders()?.style, "double")
        // Design > Watermark: a preset, then removed.
        state.session.onWatermark?(.text({ var t = WordWatermark.TextMark(); t.text = "DRAFT"; return t }()))
        ui.pump()
        XCTAssertEqual(WordWatermark.current(in: c.document)?.text, "DRAFT")
        state.session.onWatermark?(WatermarkChoice.none)
        ui.pump()
        XCTAssertFalse(WordWatermark.has(in: c.document))
        // The custom dialog shows the current mark.
        state.session.onWatermarkDialog?()
        ui.pump()
        let wm = ui.state(WatermarkDialogState.self)!
        wm.text.text = "SAMPLE"; wm.mark.diagonal = false
        wm.ok()
        ui.pump()
        XCTAssertEqual(WordWatermark.current(in: c.document)?.diagonal, false)
        XCTAssertEqual(WordWatermark.current(in: c.document)?.text, "SAMPLE")
    }
}

/// Writes the W-PG-3 Word lab into the folder PG3_LAB_OUT names (skipped otherwise): line numbers (start 3, each restart,
/// count by 5, a suppressed paragraph, two sections), page colour, page borders, text and picture watermarks.
final class PageDesignLab: XCTestCase {
    private func body(_ n: Int) -> [RichParagraph] {
        (1...n).map { i in
            RichParagraph(text: i % 10 == 4
                ? "Paragraph \(i) is a long one that wraps onto a second and a third line, so the lab shows whether Word numbers every line of a paragraph or only its first line, and how count-by skips them."
                : "Paragraph \(i).")
        }
    }

    private func save(_ d: RichDocument, _ page: PageSetup, _ dir: String, _ name: String) throws {
        try DocxFormat.write(d, pageSetup: page).write(to: URL(fileURLWithPath: dir + "/" + name + ".docx"))
    }

    private func numbered(_ n: LineNumbering, suppress: Int? = nil) -> (RichDocument, PageSetup) {
        let c = RichDocumentController()
        c.load(RichDocument(paragraphs: body(110)))
        c.setLineNumbers(n, lastSetup: .letter)
        if let s = suppress {
            c.moveTo(RichPosition(paragraph: s, offset: 0), extend: false)
            c.toggleSuppressLineNumbers()
        }
        // Section 2 starts at paragraph 71 (a next-page break), with the same numbering.
        c.moveTo(RichPosition(paragraph: 70, offset: 0), extend: false)
        c.insertSectionBreak(.nextPage, lastSetup: c.document.lastSectionPage ?? .letter)
        return (c.document, c.document.lastSectionPage ?? .letter)
    }

    func testWriteLab() throws {
        guard let dir = ProcessInfo.processInfo.environment["PG3_LAB_OUT"] else { throw XCTSkip("no PG3_LAB_OUT") }
        var n = LineNumbering()
        n.start = 3; n.countBy = 1; n.restart = .continuous
        var r = numbered(n, suppress: 5); try save(r.0, r.1, dir, "pg3-lines-continuous-start3")
        n.restart = .newPage
        r = numbered(n); try save(r.0, r.1, dir, "pg3-lines-page-start3")
        n.restart = .newSection; n.countBy = 5
        r = numbered(n); try save(r.0, r.1, dir, "pg3-lines-section-by5")

        // Page colour and a double blue box on the whole document.
        var c = RichDocumentController()
        c.load(RichDocument(paragraphs: body(80)))
        c.setPageColor(0xFFF2CC)
        var b = PageBorders(); b.style = "double"; b.width = 6; b.color = 0x2F5496
        c.setPageBorders(b, scope: .wholeDocument)
        try save(c.document, .letter, dir, "pg3-color-double-box")
        // A single border on the first page only, measured from the text, top and bottom only.
        c = RichDocumentController()
        c.load(RichDocument(paragraphs: body(80)))
        var f = PageBorders(); f.style = "single"; f.width = 12; f.color = 0xC00000
        f.offsetFrom = "text"; f.space = PageBorders.defaultSpace(from: "text"); f.sides = [.top, .bottom, .left]
        c.moveTo(RichPosition(paragraph: 40, offset: 0), extend: false)
        c.insertSectionBreak(.nextPage, lastSetup: .letter)
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        c.setPageBorders(f, scope: .thisSectionFirstPage)
        try save(c.document, .letter, dir, "pg3-border-first-page-from-text")

        // Watermarks.
        let plain = RichDocument(paragraphs: body(30))
        try save(try WordWatermark.setting(.text(WordWatermark.TextMark()), in: plain, page: .letter), .letter, dir, "pg3-wm-confidential-auto-diagonal")
        var t = WordWatermark.TextMark(); t.text = "DRAFT"; t.size = 80; t.color = 0xFF0000; t.semitransparent = false; t.diagonal = false
        try save(try WordWatermark.setting(.text(t), in: plain, page: .letter), .letter, dir, "pg3-wm-draft-80-horizontal")
        var a = WordWatermark.TextMark(); a.text = "SAMPLE"; a.font = "Times New Roman"; a.diagonal = false
        try save(try WordWatermark.setting(.text(a), in: plain, page: .letter), .letter, dir, "pg3-wm-sample-auto-horizontal-times")
        let png = try Data(contentsOf: URL(fileURLWithPath: dir + "/checker.png"))
        try save(try WordWatermark.setting(.picture(.init(data: png, ext: "png", name: "checker", naturalWidth: 180, naturalHeight: 90, scale: nil, washout: true)), in: plain, page: .letter), .letter, dir, "pg3-wm-picture-auto-washout")
        try save(try WordWatermark.setting(.picture(.init(data: png, ext: "png", name: "checker", naturalWidth: 180, naturalHeight: 90, scale: 2, washout: false)), in: plain, page: .letter), .letter, dir, "pg3-wm-picture-200-plain")
    }
}
