import XCTest
@testable import OfficeApp
@testable import OfficeText

/// A vertical (tbRl) section is held on the turned page the layout works in; the file, the dialog and the
/// Ribbon see the paper's page.
final class VerticalSectionSaveTests: XCTestCase {
    private let mar = "<w:pgMar w:top=\"1000\" w:right=\"1100\" w:bottom=\"1200\" w:left=\"1300\" w:header=\"720\" w:footer=\"720\" w:gutter=\"0\"/>"
    private let sz = "<w:pgSz w:w=\"11906\" w:h=\"16838\"/>"

    /// A file whose middle and last sections both write top to bottom.
    private func read() throws -> (RichDocument, PageSetup) {
        let mid = "<w:p><w:pPr><w:sectPr>\(sz)\(mar)<w:textDirection w:val=\"tbRl\"/></w:sectPr></w:pPr><w:r><w:t>一</w:t></w:r></w:p>"
        let body = "<w:body>\(mid)<w:p><w:r><w:t>二</w:t></w:r></w:p><w:sectPr>\(sz)\(mar)<w:textDirection w:val=\"tbRl\"/></w:sectPr></w:body>"
        var entries = try Zip.read(try DocxFormat.write(RichDocument(plainText: "a"), pageSetup: .letter))
        let i = try XCTUnwrap(entries.firstIndex { $0.name == "word/document.xml" })
        var s = String(decoding: entries[i].data, as: UTF8.self)
        let a = try XCTUnwrap(s.rangeOfSubstring("<w:body>")), b = try XCTUnwrap(s.rangeOfSubstring("</w:body>"))
        s.replaceSubrange(a.lowerBound ..< b.upperBound, with: body)
        entries[i] = ZipEntry(name: entries[i].name, data: Data(s.utf8))
        let read = try DocxFormat.read(try Zip.write(entries))
        return (read.document, try XCTUnwrap(read.pageSetup))
    }

    private func sections(_ d: RichDocument, _ p: PageSetup) throws -> [String] {
        let out = String(decoding: try XCTUnwrap(try Zip.read(try DocxFormat.write(d, pageSetup: p)).first { $0.name == "word/document.xml" }).data, as: UTF8.self)
        var r: [String] = []; var rest = Substring(out)
        while let x = rest.rangeOfSubstring("<w:sectPr"), let y = rest.rangeOfSubstring("</w:sectPr>") {
            r.append(String(rest[x.lowerBound ..< y.upperBound])); rest = rest[y.upperBound...]
        }
        return r
    }

    private func has(_ s: String, _ attrs: [String], line: UInt = #line) {
        for a in attrs { XCTAssertNotNil(s.rangeOfSubstring(a), "\(a) in \(s)", line: line) }
    }

    func testUntouchedVerticalSectionsSaveTheirPaperPage() throws {
        let (d, p) = try read()
        XCTAssertTrue(p.vertical)
        let out = try sections(d, p)
        XCTAssertEqual(out.count, 2)
        for s in out {
            has(s, ["w:top=\"1000\"", "w:right=\"1100\"", "w:bottom=\"1200\"", "w:left=\"1300\"", "w:w=\"11906\"", "w:h=\"16838\""])
            XCTAssertNotNil(s.rangeOfSubstring("tbRl"), s)
        }
    }

    func testEditedVerticalSectionSavesThePaperMarginItWasGiven() throws {
        let (d, p) = try read()
        let c = RichDocumentController(document: d)
        c.changePageSetup(allSections: true, lastSetup: p) { $0.marginLeft = 50 }
        let mid = try XCTUnwrap(c.document.paragraphs[0].style.sectionPage)
        XCTAssertTrue(mid.vertical)
        XCTAssertEqual(mid.physical.marginLeft, 50)
        XCTAssertEqual(mid.physical.marginTop, 50, "the other paper margins stay")
        for s in try sections(c.document, try XCTUnwrap(c.document.lastSectionPage)) {
            has(s, ["w:top=\"1000\"", "w:right=\"1100\"", "w:bottom=\"1200\"", "w:left=\"1000\"", "w:w=\"11906\""])
        }
    }

    func testPaperAndFlowFramesRoundTrip() {
        var p = PageSetup.a4; p.marginTop = 10; p.marginRight = 20; p.marginBottom = 30; p.marginLeft = 40; p.vertical = true
        let flow = p.transposed()
        XCTAssertEqual(flow.untransposed(), p)
        XCTAssertEqual(flow.physical, p)
        XCTAssertEqual(flow.width, p.height)
    }
}
