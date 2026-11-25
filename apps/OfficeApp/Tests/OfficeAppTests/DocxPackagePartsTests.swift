// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Foundation
import OfficeText
@testable import OfficeApp

/// W-P0 (parts): a save carries every package part the editor does not
/// rewrite: properties, custom XML items, web settings, with their rels and
/// content types.
final class DocxPackagePartsTests: XCTestCase {
    private let core = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><cp:coreProperties xmlns:cp=\"http://schemas.openxmlformats.org/package/2006/metadata/core-properties\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:dcterms=\"http://purl.org/dc/terms/\"><dc:title>Quarterly report</dc:title><dc:creator>A. Writer</dc:creator><dcterms:created>2020-01-02T03:04:05Z</dcterms:created></cp:coreProperties>"
    private let app = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Properties xmlns=\"http://schemas.openxmlformats.org/officeDocument/2006/extended-properties\"><Application>Microsoft Office Word</Application><Pages>3</Pages></Properties>"
    private let custom = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Properties xmlns=\"http://schemas.openxmlformats.org/officeDocument/2006/custom-properties\" xmlns:vt=\"http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes\"><property fmtid=\"{D5CDD505-2E9C-101B-9397-08002B2CF9AE}\" pid=\"2\" name=\"Project\"><vt:lpwstr>Atlas</vt:lpwstr></property></Properties>"
    private let item = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><root xmlns=\"urn:example\"><name>Ada</name></root>"
    private let itemProps = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><ds:datastoreItem ds:itemID=\"{11111111-2222-3333-4444-555555555555}\" xmlns:ds=\"http://schemas.openxmlformats.org/officeDocument/2006/customXml\"><ds:schemaRefs/></ds:datastoreItem>"
    private let itemRels = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/customXmlProps\" Target=\"itemProps1.xml\"/></Relationships>"
    private let web = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><w:webSettings xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:optimizeForBrowser/></w:webSettings>"

    private func replacing(_ parts: inout [ZipEntry], _ name: String, _ edit: (String) -> String) throws {
        let i = try XCTUnwrap(parts.firstIndex { $0.name == name })
        parts[i] = ZipEntry(name: name, data: Data(edit(String(decoding: parts[i].data, as: UTF8.self)).utf8))
    }

    private func fixture() throws -> Data {
        var parts = try Zip.read(DocxFormat.write(RichDocument(paragraphs: [RichParagraph()]), pageSetup: .letter))
        let rt = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
        // (A fresh save already carries its own property parts; the fixture brings its own.)
        parts.removeAll { $0.name.hasPrefix("docProps/") }
        try replacing(&parts, "_rels/.rels") { s in
            var out = s
            while let r = out.range(of: "<Relationship Id=\"rIdPkg") { let e = out.range(of: "/>", range: r.upperBound ..< out.endIndex)!; out.removeSubrange(r.lowerBound ..< e.upperBound) }
            return out }
        try replacing(&parts, "[Content_Types].xml") { $0.replacingOccurrences(of: "<Override PartName=\"/docProps/core.xml\" ContentType=\"application/vnd.openxmlformats-package.core-properties+xml\"/><Override PartName=\"/docProps/app.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.extended-properties+xml\"/>", with: "") }
        try replacing(&parts, "_rels/.rels") { $0.replacingOccurrences(of: "</Relationships>", with:
            "<Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties\" Target=\"docProps/core.xml\"/>"
            + "<Relationship Id=\"rId3\" Type=\"\(rt)/extended-properties\" Target=\"docProps/app.xml\"/>"
            + "<Relationship Id=\"rId4\" Type=\"\(rt)/custom-properties\" Target=\"docProps/custom.xml\"/></Relationships>") }
        try replacing(&parts, "word/_rels/document.xml.rels") { $0.replacingOccurrences(of: "</Relationships>", with:
            "<Relationship Id=\"rId77\" Type=\"\(rt)/customXml\" Target=\"../customXml/item1.xml\"/>"
            + "<Relationship Id=\"rId78\" Type=\"\(rt)/webSettings\" Target=\"webSettings.xml\"/></Relationships>") }
        try replacing(&parts, "[Content_Types].xml") { $0.replacingOccurrences(of: "</Types>", with:
            "<Override PartName=\"/docProps/core.xml\" ContentType=\"application/vnd.openxmlformats-package.core-properties+xml\"/>"
            + "<Override PartName=\"/docProps/app.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.extended-properties+xml\"/>"
            + "<Override PartName=\"/docProps/custom.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.custom-properties+xml\"/>"
            + "<Override PartName=\"/customXml/itemProps1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.customXmlProperties+xml\"/>"
            + "<Override PartName=\"/word/webSettings.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.webSettings+xml\"/></Types>") }
        for (n, t) in [("docProps/core.xml", core), ("docProps/app.xml", app), ("docProps/custom.xml", custom), ("customXml/item1.xml", item),
                       ("customXml/itemProps1.xml", itemProps), ("customXml/_rels/item1.xml.rels", itemRels), ("word/webSettings.xml", web)] {
            parts.append(ZipEntry(name: n, data: Data(t.utf8)))
        }
        return try Zip.write(parts)
    }

    func testSaveKeepsPropertiesCustomXmlAndWebSettings() throws {
        var doc = try DocxFormat.read(fixture()).document
        doc.paragraphs[0].insert("edited", at: 0, runs: [])   // an edit
        let saved = try Zip.read(DocxFormat.write(doc, pageSetup: .letter))
        func data(_ n: String) -> String? { saved.first { $0.name == n }.map { String(decoding: $0.data, as: UTF8.self) } }
        XCTAssertEqual(data("docProps/core.xml"), core)
        XCTAssertEqual(data("docProps/app.xml"), app)
        XCTAssertEqual(data("docProps/custom.xml"), custom)
        XCTAssertEqual(data("customXml/item1.xml"), item)
        XCTAssertEqual(data("customXml/itemProps1.xml"), itemProps)
        XCTAssertEqual(data("customXml/_rels/item1.xml.rels"), itemRels)
        XCTAssertEqual(data("word/webSettings.xml"), web)
        let root = try XCTUnwrap(data("_rels/.rels"))
        for t in ["core-properties", "extended-properties", "custom-properties", "officeDocument"] {
            XCTAssertTrue(root.contains("/" + t + "\""), "root rels lack \(t): \(root)")
        }
        XCTAssertEqual(root.components(separatedBy: "Target=\"word/document.xml\"").count, 2, root)
        let docRels = try XCTUnwrap(data("word/_rels/document.xml.rels"))
        XCTAssertTrue(docRels.contains("customXml\" Target=\"../customXml/item1.xml\""), docRels)
        let types = try XCTUnwrap(data("[Content_Types].xml"))
        for o in ["/docProps/core.xml", "/docProps/app.xml", "/docProps/custom.xml", "/customXml/itemProps1.xml", "/word/webSettings.xml"] {
            XCTAssertTrue(types.contains("PartName=\"\(o)\""), "no content type for \(o): \(types)")
        }
        // A second round trip keeps them again (nothing doubled).
        let again = try Zip.read(DocxFormat.write(DocxFormat.read(DocxFormat.write(doc, pageSetup: .letter)).document, pageSetup: .letter))
        XCTAssertEqual(again.first { $0.name == "docProps/core.xml" }.map { String(decoding: $0.data, as: UTF8.self) }, core)
        let root2 = String(decoding: try XCTUnwrap(again.first { $0.name == "_rels/.rels" }).data, as: UTF8.self)
        XCTAssertEqual(root2.components(separatedBy: "core-properties\"").count, 2, root2)
    }
}
