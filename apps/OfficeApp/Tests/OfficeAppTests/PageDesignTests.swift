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

    func testLineNumbersWriteAndSuppress() throws {
        let c = controller(["a", "b", "c"])
        var n = LineNumbering()
        n.countBy = 5; n.start = 3; n.restart = .continuous
        c.setLineNumbers(n, lastSetup: .letter)
        let page = c.document.lastSectionPage ?? .letter
        XCTAssertEqual(page.lineNumbers, n)
        let (back, parts) = try roundTrip(c.document, page)
        XCTAssertTrue(text(parts, "word/document.xml").containsSubstring("<w:lnNumType w:countBy=\"5\" w:start=\"3\" w:restart=\"continuous\"/>"))
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
