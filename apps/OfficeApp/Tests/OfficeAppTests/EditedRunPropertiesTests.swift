import XCTest
@testable import OfficeApp
@testable import OfficeText

/// An edited run keeps the file's run properties the editor's fields cannot say (complex-script twins, character scale,
/// an auto colour...), and the edit itself still wins. (Edit-loss sweep 2026-11-26: bolding a word lost them.)
final class EditedRunPropertiesTests: XCTestCase {
    private func editAndSave(_ rPr: String, _ edit: (inout CharStyle) -> Void) throws -> String {
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .letter))
        let di = try XCTUnwrap(entries.firstIndex { $0.name == "word/document.xml" })
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let body = try XCTUnwrap(xml.range(of: "<w:body>")).upperBound ..< (try XCTUnwrap(xml.range(of: "<w:sectPr"))).lowerBound
        xml.replaceSubrange(body, with: "<w:p><w:r><w:rPr>\(rPr)</w:rPr><w:t>word</w:t></w:r></w:p>")
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        var doc = try DocxFormat.read(try Zip.write(entries)).document
        let i = try XCTUnwrap(doc.paragraphs.firstIndex { $0.text == "word" })
        doc.paragraphs[i].applyStyle(0 ..< 4, edit)
        let out = String(decoding: try XCTUnwrap(try Zip.read(try DocxFormat.write(doc, pageSetup: .letter)).first { $0.name == "word/document.xml" }).data, as: UTF8.self)
        let r = try XCTUnwrap(out.range(of: "<w:r><w:rPr>")).upperBound
        return String(out[r...].prefix { $0 != "\u{0}" }.split(separator: "</w:rPr>", maxSplits: 1, omittingEmptySubsequences: false)[0])
    }

    func testBoldingKeepsTheRunsOtherProperties() throws {
        let rPr = try editAndSave(#"<w:iCs/><w:noProof/><w:color w:val="auto"/><w:spacing w:val="10"/><w:w w:val="90"/><w:szCs w:val="28"/><w:highlight w:val="yellow"/>"#) { $0.bold = true }
        for e in ["<w:b/>", "<w:iCs/>", "<w:noProof/>", #"<w:color w:val="auto"/>"#, #"<w:spacing w:val="10"/>"#, #"<w:w w:val="90"/>"#, #"<w:szCs w:val="28"/>"#] {
            XCTAssertTrue(rPr.contains(e), "\(e) missing from \(rPr)")
        }
        // (Schema order: b before iCs before noProof before color before spacing before w before szCs.)
        let pos = ["<w:b/>", "<w:iCs/>", "<w:noProof/>", "<w:color", "<w:spacing", "<w:w ", "<w:szCs"].map { rPr.range(of: $0)!.lowerBound }
        XCTAssertEqual(pos, pos.sorted(), rPr)
    }

    func testAnEditToAPropertyTheFieldsSayIsNotUndone() throws {
        let rPr = try editAndSave(#"<w:b/><w:bCs/><w:w w:val="90"/>"#) { $0.bold = false; $0.italic = true }
        XCTAssertFalse(rPr.contains("<w:b/>"), rPr)
        XCTAssertTrue(rPr.contains("<w:i/>"), rPr)
        XCTAssertTrue(rPr.contains(#"<w:w w:val="90"/>"#), rPr)
    }
}
