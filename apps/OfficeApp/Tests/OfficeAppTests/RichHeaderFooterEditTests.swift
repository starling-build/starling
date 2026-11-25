import XCTest
@testable import OfficeApp
@testable import OfficeText

/// W-HF-1 (model): a formatted header/footer is one undo step and is written as its own part.
final class RichHeaderFooterEditTests: XCTestCase {
    private func formatted() -> [RichParagraph] {
        var bold = CharStyle(); bold.bold = true; bold.fontSize = 14
        var page = CharStyle(); page.field = "PAGE"
        let text = "Report\tPage 7"
        var p = RichParagraph(text: text, runs: [
            Run(length: 6, style: bold), Run(length: 1), Run(length: 5), Run(length: 1, style: page)])
        p.style.alignment = .center
        return [p]
    }

    func testFormattedHeaderRoundTripsAndUndoes() throws {
        let c = RichDocumentController(document: RichDocument(paragraphs: [RichParagraph(text: "body")]))
        c.setRichHeaderFooter(.header, paragraphs: formatted())
        XCTAssertEqual(c.document.headerFooters.first?.paragraphs.first?.text, "Report\tPage 7")
        let out = try DocxFormat.write(c.document, pageSetup: .letter)
        let parts = try Zip.read(out)
        let hdr = try XCTUnwrap(parts.first { $0.name.hasPrefix("word/header") })
        let xml = String(decoding: hdr.data, as: UTF8.self)
        XCTAssertTrue(xml.contains("<w:b/>"), xml)
        XCTAssertTrue(xml.contains("w:instr=\" PAGE \""), xml)
        XCTAssertTrue(xml.contains("<w:jc w:val=\"center\"/>"), xml)
        // Read back: same text and bold.
        let back = try DocxFormat.read(out).document
        let h = try XCTUnwrap(back.headerFooters.first { $0.kind == .header })
        XCTAssertTrue(h.paragraphs[0].text.hasPrefix("Report"))
        XCTAssertTrue(h.paragraphs[0].runs.first?.style.bold == true)
        c.undo()
        XCTAssertTrue(c.document.headerFooters.isEmpty)
        XCTAssertEqual(c.document.header, "")
    }

    /// Set HEADER_EDITED_OUT to a path to save the document for a check in Word.
    func testWriteForWordCheck() throws {
        guard let out = ProcessInfo.processInfo.environment["HEADER_EDITED_OUT"] else { return }
        let c = RichDocumentController(document: RichDocument(paragraphs: [RichParagraph(text: "Body text of the page.")]))
        c.setRichHeaderFooter(.header, paragraphs: formatted())
        var page = CharStyle(); page.field = "PAGE"; page.italic = true
        var f = RichParagraph(text: "Page 3", runs: [Run(length: 5, style: { var s = CharStyle(); s.italic = true; return s }()), Run(length: 1, style: page)])
        f.style.alignment = .right
        c.setRichHeaderFooter(.footer, paragraphs: [f])
        try DocxFormat.write(c.document, pageSetup: .letter).write(to: URL(fileURLWithPath: out))
    }
}
