import XCTest
@testable import OfficeApp
@testable import OfficeText

/// W-P0-4 (fields): a field the editor does not evaluate is saved as the field, with the result the file cached.
final class DocxKeptFieldsTests: XCTestCase {
    private func cf(_ code: String, _ res: String) -> String {
        "<w:r><w:fldChar w:fldCharType=\"begin\"/></w:r><w:r><w:instrText xml:space=\"preserve\"> \(code) </w:instrText></w:r><w:r><w:fldChar w:fldCharType=\"separate\"/></w:r><w:r><w:t>\(res)</w:t></w:r><w:r><w:fldChar w:fldCharType=\"end\"/></w:r>"
    }
    private let fields: [(String, String)] = [
        ("REF bm1 \\h", "refres"), ("SEQ Figure \\* ARABIC", "7"), ("MERGEFIELD Name", "NAMEVAL"), ("PAGE", "3"),
        ("NUMPAGES", "9"), ("DATE \\@ \"d MMMM yyyy\"", "1 May 2024"), ("AUTHOR", "authres"),
    ]

    private func roundTrip(_ body: String) throws -> (doc: RichDocument, xml: String) {
        var parts = try Zip.read(DocxFormat.write(RichDocument(paragraphs: [RichParagraph()]), pageSetup: .letter))
        let di = try XCTUnwrap(parts.firstIndex { $0.name == "word/document.xml" })
        var xml = String(decoding: parts[di].data, as: UTF8.self)
        xml.insert(contentsOf: body, at: try XCTUnwrap(xml.range(of: "<w:body>")).upperBound)
        parts[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let read = try DocxFormat.read(try Zip.write(parts))
        let out = try Zip.read(DocxFormat.write(read.document, pageSetup: .letter))
        return (read.document, String(decoding: try XCTUnwrap(out.first { $0.name == "word/document.xml" }).data, as: UTF8.self))
    }

    func testFieldsAreSavedAsFieldsWithTheirCachedResult() throws {
        // A bookmark so REF has its target.
        let body = "<w:p><w:bookmarkStart w:id=\"1\" w:name=\"bm1\"/><w:r><w:t>target</w:t></w:r><w:bookmarkEnd w:id=\"1\"/></w:p>"
            + fields.map { "<w:p>\(cf($0.0, $0.1))</w:p>" }.joined()
        let (_, xml) = try roundTrip(body)
        for (code, result) in fields {
            XCTAssertTrue(xml.contains("<w:instrText xml:space=\"preserve\"> \(code.replacingOccurrences(of: "\"", with: "&quot;")) </w:instrText>"), "\(code) is still a field")
            // REF and SEQ are evaluated by the editor, so their result is recomputed; the others keep the file's.
            if !code.hasPrefix("REF") && !code.hasPrefix("SEQ") { XCTAssertTrue(xml.contains(">\(result)</w:t>"), "\(code) keeps its result \(result)") }
        }
        XCTAssertEqual(xml.components(separatedBy: "fldCharType=\"begin\"").count - 1, fields.count)
        XCTAssertEqual(xml.components(separatedBy: "fldCharType=\"end\"").count - 1, fields.count)
    }

    func testTextAroundAFieldStaysOutsideIt() throws {
        let (_, xml) = try roundTrip("<w:p><w:r><w:t xml:space=\"preserve\">Figure </w:t></w:r>\(cf("SEQ Figure", "4"))<w:r><w:t>: caption</w:t></w:r></w:p>")
        let begin = try XCTUnwrap(xml.range(of: "fldCharType=\"begin\""))
        let end = try XCTUnwrap(xml.range(of: "fldCharType=\"end\""))
        XCTAssertTrue(xml[..<begin.lowerBound].contains("Figure "))
        XCTAssertTrue(xml[end.upperBound...].contains(": caption"))
        XCTAssertFalse(xml[begin.lowerBound..<end.upperBound].contains("caption"))
    }

    /// Set KEPT_FIELDS_OUT to a path to save the document for a check in Word.
    func testWriteForWordCheck() throws {
        guard let out = ProcessInfo.processInfo.environment["KEPT_FIELDS_OUT"] else { return }
        let body = fields.map { "<w:p><w:r><w:t xml:space=\"preserve\">\($0.0): </w:t></w:r>\(cf($0.0, $0.1))</w:p>" }.joined()
            + "<w:p>\(cf("FILENAME", "name.docx"))</w:p><w:p>\(cf("DOCPROPERTY Company", "Acme"))</w:p>"
        var parts = try Zip.read(DocxFormat.write(RichDocument(paragraphs: [RichParagraph()]), pageSetup: .letter))
        let di = try XCTUnwrap(parts.firstIndex { $0.name == "word/document.xml" })
        var xml = String(decoding: parts[di].data, as: UTF8.self)
        xml.insert(contentsOf: body, at: try XCTUnwrap(xml.range(of: "<w:body>")).upperBound)
        parts[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let read = try DocxFormat.read(try Zip.write(parts))
        try DocxFormat.write(read.document, pageSetup: .letter).write(to: URL(fileURLWithPath: out))
    }
}
