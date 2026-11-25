import XCTest
@testable import OfficeApp
@testable import OfficeText

final class NumberingKeptOnSaveTests: XCTestCase {
    static let w = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"

    static func sample() throws -> Data {
        let numbering = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:numbering xmlns:w="\(w)">
        <w:abstractNum w:abstractNumId="0"><w:nsid w:val="1A2B3C4D"/><w:multiLevelType w:val="hybridMultilevel"/><w:tmpl w:val="0F1E2D3C"/>\
        <w:lvl w:ilvl="0" w:tplc="04090001" w:tentative="1"><w:start w:val="1"/><w:numFmt w:val="decimal"/><w:lvlText w:val="%1."/><w:lvlJc w:val="left"/><w:pPr><w:tabs><w:tab w:val="num" w:pos="720"/></w:tabs><w:ind w:left="720" w:hanging="360"/></w:pPr></w:lvl></w:abstractNum>
        <w:abstractNum w:abstractNumId="1"><w:nsid w:val="5E6F7A8B"/><w:multiLevelType w:val="hybridMultilevel"/><w:tmpl w:val="11223344"/>\
        <w:lvl w:ilvl="0" w:tplc="04090003"><w:start w:val="1"/><w:numFmt w:val="bullet"/><w:lvlText w:val="o"/><w:lvlJc w:val="left"/><w:pPr><w:ind w:left="720" w:hanging="360"/></w:pPr></w:lvl></w:abstractNum>
        <w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num><w:num w:numId="2"><w:abstractNumId w:val="1"/></w:num>
        </w:numbering>
        """
        let styles = "<?xml version=\"1.0\"?><w:styles xmlns:w=\"\(w)\"><w:style w:type=\"paragraph\" w:default=\"1\" w:styleId=\"Normal\"><w:name w:val=\"Normal\"/></w:style></w:styles>"
        let body = "<?xml version=\"1.0\"?><w:document xmlns:w=\"\(w)\"><w:body>"
            + "<w:p><w:pPr><w:numPr><w:ilvl w:val=\"0\"/><w:numId w:val=\"1\"/></w:numPr></w:pPr><w:r><w:t>one</w:t></w:r></w:p>"
            + "<w:p><w:pPr><w:numPr><w:ilvl w:val=\"0\"/><w:numId w:val=\"2\"/></w:numPr></w:pPr><w:r><w:t>two</w:t></w:r></w:p>"
            + "<w:sectPr><w:pgSz w:w=\"12240\" w:h=\"15840\"/></w:sectPr></w:body></w:document>"
        let types = "<?xml version=\"1.0\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/><Override PartName=\"/word/numbering.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml\"/><Override PartName=\"/word/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml\"/></Types>"
        let rels = "<?xml version=\"1.0\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/></Relationships>"
        let drels = "<?xml version=\"1.0\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/><Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering\" Target=\"numbering.xml\"/></Relationships>"
        return try Zip.write([ZipEntry(name: "[Content_Types].xml", data: Data(types.utf8)), ZipEntry(name: "_rels/.rels", data: Data(rels.utf8)),
                              ZipEntry(name: "word/document.xml", data: Data(body.utf8)), ZipEntry(name: "word/styles.xml", data: Data(styles.utf8)),
                              ZipEntry(name: "word/numbering.xml", data: Data(numbering.utf8)),
                              ZipEntry(name: "word/_rels/document.xml.rels", data: Data(drels.utf8))])
    }

    func numberingXML(_ doc: RichDocument) throws -> String {
        let out = try DocxFormat.write(doc, pageSetup: .letter)
        return String(decoding: try Zip.read(out).first { $0.name == "word/numbering.xml" }!.data, as: UTF8.self)
    }

    func testUntouchedListsKeepTheirIdentity() throws {
        let xml = try numberingXML(try DocxFormat.read(Self.sample()).document)
        for keep in ["1A2B3C4D", "0F1E2D3C", "5E6F7A8B", "11223344", "w:tplc=\"04090001\"", "w:tentative=\"1\"", "w:tab w:pos=\"720\" w:val=\"num\""] {
            XCTAssertTrue(xml.containsSubstring(keep), "kept \(keep)")
        }
        XCTAssertEqual(xml.components(separatedBy: "<w:num ").count - 1, 2, "no list is invented for a document that does not use it")
    }

    func testChangedListIsRewrittenAndTheRestKept() throws {
        var doc = try DocxFormat.read(Self.sample()).document
        var level = try XCTUnwrap(doc.listFormats["1"]?[0])
        level.text = "%1)"
        doc.listFormats["1"]?[0] = level
        let xml = try numberingXML(doc)
        XCTAssertTrue(xml.containsSubstring("%1)"), "the edit is saved")
        XCTAssertTrue(xml.containsSubstring("5E6F7A8B"), "the other list is untouched")
        XCTAssertTrue(xml.containsSubstring("11223344"))
        let root = try XCTUnwrap(XNode.parse(Data(xml.utf8)))
        let abstracts = Set(root.children.filter { $0.name == "w:abstractNum" }.compactMap { $0["w:abstractNumId"] })
        for n in root.children where n.name == "w:num" {
            let a = n.children.first { $0.name == "w:abstractNumId" }?["w:val"] ?? ""
            XCTAssertTrue(abstracts.contains(a), "num \(n["w:numId"] ?? "?") points at abstract \(a)")
        }
        // abstractNums come before nums, as the schema wants.
        let firstNum = root.children.firstIndex { $0.name == "w:num" }!
        XCTAssertFalse(root.children[firstNum...].contains { $0.name == "w:abstractNum" })
    }
}
