import XCTest
@testable import OfficeApp
@testable import OfficeText
/// A saved document always carries its core and extended properties; a loaded file keeps its own.
final class DocxCorePropertiesTests: XCTestCase {
    func testNewDocumentGetsPropertyParts() throws {
        let entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .letter))
        let names = entries.map(\.name)
        XCTAssertTrue(names.contains("docProps/core.xml")); XCTAssertTrue(names.contains("docProps/app.xml"))
        let types = String(decoding: entries.first { $0.name == "[Content_Types].xml" }!.data, as: UTF8.self)
        XCTAssertTrue(types.contains("/docProps/core.xml")); XCTAssertTrue(types.contains("/docProps/app.xml"))
        let rels = String(decoding: entries.first { $0.name == "_rels/.rels" }!.data, as: UTF8.self)
        XCTAssertTrue(rels.contains("docProps/core.xml")); XCTAssertTrue(rels.contains("docProps/app.xml"))
        XCTAssertEqual(rels.components(separatedBy: "Id=\"rId1\"").count - 1, 1)
        // and a second save keeps exactly one of each
        let again = try DocxFormat.write(try DocxFormat.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .letter)).document, pageSetup: .letter)
        XCTAssertEqual(try Zip.read(again).filter { $0.name == "docProps/core.xml" }.count, 1)
        let r2 = String(decoding: try Zip.read(again).first { $0.name == "_rels/.rels" }!.data, as: UTF8.self)
        XCTAssertEqual(r2.components(separatedBy: "docProps/core.xml").count - 1, 1)
    }
}
