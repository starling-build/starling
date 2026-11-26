// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import OfficeText
@testable import OfficeApp

/// The save adds no style the file did not have unless the saved text uses it; a style the writer itself
/// refers to (Hyperlink on a new link, TOC 1..9, the note reference and text styles) must then be there,
/// or Word draws that text plain.
final class ReferencedStylesOnSaveTests: XCTestCase {
    static let w = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"

    static func sample() throws -> Data {
        let styles = "<?xml version=\"1.0\"?><w:styles xmlns:w=\"\(w)\">"
            + "<w:style w:type=\"paragraph\" w:default=\"1\" w:styleId=\"Normal\"><w:name w:val=\"Normal\"/></w:style>"
            + "<w:style w:type=\"paragraph\" w:styleId=\"Heading1\"><w:name w:val=\"heading 1\"/><w:basedOn w:val=\"Normal\"/><w:pPr><w:outlineLvl w:val=\"0\"/></w:pPr></w:style>"
            + "</w:styles>"
        let body = "<?xml version=\"1.0\"?><w:document xmlns:w=\"\(w)\"><w:body>"
            + "<w:p><w:pPr><w:pStyle w:val=\"Heading1\"/></w:pPr><w:r><w:t>Intro</w:t></w:r></w:p>"
            + "<w:p><w:r><w:t>see the site here</w:t></w:r></w:p>"
            + "<w:sectPr><w:pgSz w:w=\"12240\" w:h=\"15840\"/></w:sectPr></w:body></w:document>"
        let types = "<?xml version=\"1.0\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/><Override PartName=\"/word/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml\"/></Types>"
        let rels = "<?xml version=\"1.0\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/></Relationships>"
        let drels = "<?xml version=\"1.0\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/></Relationships>"
        return try Zip.write([ZipEntry(name: "[Content_Types].xml", data: Data(types.utf8)), ZipEntry(name: "_rels/.rels", data: Data(rels.utf8)),
                              ZipEntry(name: "word/document.xml", data: Data(body.utf8)), ZipEntry(name: "word/styles.xml", data: Data(styles.utf8)),
                              ZipEntry(name: "word/_rels/document.xml.rels", data: Data(drels.utf8))])
    }

    func testStylesTheWriterRefersToAreAddedWhenUsed() throws {
        let c = RichDocumentController()
        c.load(try DocxFormat.read(Self.sample()).document)
        c.moveTo(RichPosition(paragraph: 1, offset: 8), extend: false)
        c.moveTo(RichPosition(paragraph: 1, offset: 12), extend: true)
        c.setLink("https://a.dev")
        c.moveTo(RichPosition(paragraph: 1, offset: 17), extend: false)
        c.insertNote(.footnote)
        c.insertNote(.endnote)
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        XCTAssertTrue(c.insertTableOfContents(ContentsOptions(), width: 400, pageOf: { _ in "1" }))

        let entries = try Zip.read(try DocxFormat.write(c.document, pageSetup: .letter))
        func part(_ name: String) -> String { entries.first { $0.name == name }.map { String(decoding: $0.data, as: UTF8.self) } ?? "" }
        let styles = part("word/styles.xml")
        let defined = Set(styles.components(separatedBy: "w:styleId=\"").dropFirst().map { String($0.prefix { $0 != "\"" }) })
        var used: [String: Set<String>] = [:]
        for name in ["word/document.xml", "word/footnotes.xml", "word/endnotes.xml"] {
            for tag in ["<w:pStyle w:val=\"", "<w:rStyle w:val=\""] {
                for s in part(name).components(separatedBy: tag).dropFirst() { used[String(s.prefix { $0 != "\"" }), default: []].insert(name) }
            }
        }
        for (id, parts) in used.sorted(by: { $0.key < $1.key }) {
            XCTAssertTrue(defined.contains(id), "\(id) is used in \(parts.sorted()) but styles.xml does not define it")
        }
        let rStyles = Set(part("word/document.xml").components(separatedBy: "<w:rStyle w:val=\"").dropFirst().map { String($0.prefix { $0 != "\"" }) })
        let pStyles = Set(part("word/document.xml").components(separatedBy: "<w:pStyle w:val=\"").dropFirst().map { String($0.prefix { $0 != "\"" }) })
        XCTAssertTrue(rStyles.contains("Hyperlink"), "the new link carries the Hyperlink style: \(rStyles.sorted())")
        XCTAssertTrue(pStyles.contains("TOC1"), "the contents entry carries TOC 1: \(pStyles.sorted())")
        XCTAssertTrue(rStyles.contains("FootnoteReference") && rStyles.contains("EndnoteReference"), "note marks: \(rStyles.sorted())")
        XCTAssertFalse(defined.contains("Title") || defined.contains("Quote"), "styles nobody used are not added")
    }
}
