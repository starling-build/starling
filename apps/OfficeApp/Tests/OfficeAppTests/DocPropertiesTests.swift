import XCTest
@testable import OfficeApp
@testable import OfficeText
/// W-FD-1d: the document's properties are edited in place, stamped on save, and read by the fields.
final class DocPropertiesTests: XCTestCase {
    func testSetPropertyEditsInPlaceAndSurvivesSave() throws {
        var doc = RichDocument(paragraphs: [RichParagraph(text: "a")])
        doc.setProperty("title", "A & B")
        doc.setProperty("subject", "Budget")
        doc.setProperty("title", "Plan")
        XCTAssertEqual(doc.property("title"), "Plan")
        let back = try DocxFormat.read(try DocxFormat.write(doc, pageSetup: .letter)).document
        XCTAssertEqual(back.property("title"), "Plan")
        XCTAssertEqual(back.property("subject"), "Budget")
        let core = String(decoding: back.keptParts["docProps/core.xml"]!, as: UTF8.self)
        XCTAssertEqual(core.components(separatedBy: "<dc:title>").count - 1, 1)
        // a file's other elements are kept
        var d2 = back
        d2.setProperty("creator", "Ann")
        XCTAssertEqual(d2.property("subject"), "Budget")
        XCTAssertEqual(d2.property("creator"), "Ann")
        // properties edited before the first save: the file still gets app.xml and a created time
        let saved = try Zip.read(try OfficeFormats.encode(d2, as: "docx"))
        XCTAssertNotNil(saved.first { $0.name == "docProps/app.xml" })
        XCTAssertTrue(String(decoding: saved.first { $0.name == "[Content_Types].xml" }!.data, as: UTF8.self).contains("/docProps/app.xml"))
        XCTAssertTrue(String(decoding: saved.first { $0.name == "docProps/core.xml" }!.data, as: UTF8.self).contains("<dcterms:created"))
    }

    func testSaveStampsModifiedAndLastSavedByButKeepsAuthor() throws {
        setenv("OFFICE_NOW", "2026-03-04T05:06:07", 1); setenv("OFFICE_USER", "bob", 1)
        defer { unsetenv("OFFICE_NOW"); unsetenv("OFFICE_USER") }
        var doc = RichDocument(paragraphs: [RichParagraph(text: "a")])
        doc.setProperty("creator", "Ann")
        doc.setProperty("modified", "2020-01-01T00:00:00Z")
        let saved = try DocxFormat.read(try OfficeFormats.encode(doc, as: "docx")).document
        XCTAssertEqual(saved.property("creator"), "Ann")
        XCTAssertEqual(saved.property("lastModifiedBy"), "bob")
        XCTAssertEqual(saved.property("modified"), "2026-03-04T05:06:07Z")
        // a new document gets its author from the user
        let fresh = try DocxFormat.read(try OfficeFormats.encode(RichDocument(paragraphs: [RichParagraph(text: "a")]), as: "docx")).document
        XCTAssertEqual(fresh.property("creator"), "bob")
        XCTAssertEqual(fresh.property("created"), "2026-03-04T05:06:07Z")
        // and the AUTHOR field reads it
        XCTAssertEqual(FieldEvaluator.evaluate("AUTHOR", shown: "x", clock: nil, properties: FieldEvaluator.properties(keptParts: fresh.keptParts)), "bob")
    }

    /// A file whose core part declares only cp, dc and dcterms (docx4j's) still saves as XML: the stamped dates' xsi:type
    /// brings its namespace onto the root (xa dx4j-d5b6ee0cfa saved with xsi unbound).
    func testStampedDatesDeclareTheirNamespace() throws {
        let core = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<cp:coreProperties xmlns:cp=\"http://schemas.openxmlformats.org/package/2006/metadata/core-properties\" xmlns:dcterms=\"http://purl.org/dc/terms/\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\"><dc:creator>x</dc:creator></cp:coreProperties>"
        var out = DocProperties.setting("created", to: "2026-01-01T00:00:00Z", in: core)
        out = DocProperties.setting("modified", to: "2026-01-01T00:00:00Z", in: out)
        XCTAssertEqual(out.components(separatedBy: "xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"").count - 1, 1)
        XCTAssertNotNil(XNode.parse(Data(out.utf8)))
        let bare = "<cp:coreProperties/>"
        XCTAssertTrue(DocProperties.declaring(bare).hasPrefix("<cp:coreProperties xmlns:cp="))
    }
}
