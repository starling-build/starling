import XCTest
@testable import OfficeApp
@testable import OfficeText

/// A document read from a file keeps its own styles part on save; only created, changed or deleted styles
/// are patched (basedOn, link, next, latent styles and rsids survive).
final class StylesKeptOnSaveTests: XCTestCase {
    static let w = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"

    static func sample(normalId: String = "Normal") throws -> Data {
        let styles = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:styles xmlns:w="\(w)"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial"/><w:sz w:val="22"/></w:rPr></w:rPrDefault></w:docDefaults>
        <w:latentStyles w:defLockedState="0" w:count="2"><w:lsdException w:name="Normal" w:uiPriority="0"/><w:lsdException w:name="heading 1" w:uiPriority="9"/></w:latentStyles>
        <w:style w:type="paragraph" w:default="1" w:styleId="\(normalId)"><w:name w:val="Normal"/><w:qFormat/></w:style>
        <w:style w:type="paragraph" w:customStyle="1" w:styleId="Base"><w:name w:val="Base"/><w:basedOn w:val="\(normalId)"/><w:next w:val="Child"/><w:link w:val="BaseChar"/><w:uiPriority w:val="1"/><w:qFormat/><w:rsid w:val="00AB12CD"/><w:pPr><w:spacing w:after="120"/></w:pPr><w:rPr><w:sz w:val="24"/></w:rPr></w:style>
        <w:style w:type="paragraph" w:customStyle="1" w:styleId="Child"><w:name w:val="Child"/><w:basedOn w:val="Base"/><w:qFormat/><w:rPr><w:b/></w:rPr></w:style>
        <w:style w:type="character" w:customStyle="1" w:styleId="BaseChar"><w:name w:val="Base Char"/><w:basedOn w:val="DefaultParagraphFont"/><w:link w:val="Base"/><w:rPr><w:sz w:val="24"/></w:rPr></w:style>
        </w:styles>
        """
        let body = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="\(w)"><w:body><w:p><w:pPr><w:pStyle w:val="Base"/></w:pPr><w:r><w:t>one</w:t></w:r></w:p><w:p><w:pPr><w:pStyle w:val="Child"/></w:pPr><w:r><w:t>two</w:t></w:r></w:p><w:sectPr><w:pgSz w:w="12240" w:h="15840"/></w:sectPr></w:body></w:document>
        """
        let types = "<?xml version=\"1.0\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/><Override PartName=\"/word/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml\"/></Types>"
        let rels = "<?xml version=\"1.0\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/></Relationships>"
        let drels = "<?xml version=\"1.0\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/></Relationships>"
        return try Zip.write([ZipEntry(name: "[Content_Types].xml", data: Data(types.utf8)), ZipEntry(name: "_rels/.rels", data: Data(rels.utf8)),
                              ZipEntry(name: "word/document.xml", data: Data(body.utf8)), ZipEntry(name: "word/styles.xml", data: Data(styles.utf8)),
                              ZipEntry(name: "word/_rels/document.xml.rels", data: Data(drels.utf8))])
    }

    func stylesXML(_ c: RichDocumentController) throws -> String {
        let out = try DocxFormat.write(c.document, pageSetup: .letter)
        let part = try Zip.read(out).first { $0.name == "word/styles.xml" }!
        return String(decoding: part.data, as: UTF8.self)
    }

    func open(dropping drop: String? = nil) throws -> RichDocumentController {
        var doc = try DocxFormat.read(Self.sample()).document
        if let drop { doc.styles.styles.removeAll { $0.id == drop } }   // what Delete Style does to the sheet
        XCTAssertNotNil(doc.styles["Child"])
        let c = RichDocumentController(document: doc)
        c.insertText("x")
        return c
    }

    func testSavedStylesNeverPointAtAMissingNormalAndSkipUnusedBuiltIns() throws {
        var doc = try DocxFormat.read(Self.sample(normalId: "a")).document
        doc.styles.styles.removeAll { $0.id == "Child" }
        let c = RichDocumentController(document: doc)
        c.insertText("x")
        let root = XNode.parse(Data(try stylesXML(c).utf8))!
        let ids = Set(root.children.filter { $0.name == "w:style" }.compactMap { $0["w:styleId"] })
        for st in root.children where st.name == "w:style" {
            for ch in st.children where ch.name == "w:basedOn" || ch.name == "w:next" || ch.name == "w:link" {
                XCTAssertTrue(ids.contains(ch["w:val"] ?? "") || ch["w:val"] == "DefaultParagraphFont", "\(st["w:styleId"] ?? "?") \(ch.name) -> \(ch["w:val"] ?? "")")
            }
        }
        XCTAssertFalse(ids.contains("Title"))
        XCTAssertFalse(ids.contains("Heading1"))
        XCTAssertFalse(ids.contains("Subtitle"))
        XCTAssertFalse(ids.contains("Quote"))
    }

    func testUntouchedStylesKeepEverything() throws {
        let xml = try stylesXML(open())
        XCTAssertTrue(xml.containsSubstring("<w:basedOn w:val=\"Base\""), "Child stays based on Base")
        XCTAssertTrue(xml.containsSubstring("<w:link w:val=\"BaseChar\""))
        XCTAssertTrue(xml.containsSubstring("<w:link w:val=\"Base\""))
        XCTAssertTrue(xml.containsSubstring("<w:next w:val=\"Child\""))
        XCTAssertTrue(xml.containsSubstring("<w:lsdException w:name=\"heading 1\""))
        XCTAssertTrue(xml.containsSubstring("00AB12CD"), "rsid kept")
        XCTAssertTrue(xml.containsSubstring("w:asciiTheme") == false)
    }

    func testModifyBaseReachesChildAndKeepsChain() throws {
        let c = try open()
        let old = c.document.styles["Base"]!
        var new = old; var ps = old.paragraph; ps.spaceAfter = 30; new.paragraph = ps
        c.edit { c.perform(.setStyleEntry(old: old, new: new)) }
        let xml = try stylesXML(c)
        XCTAssertTrue(xml.containsSubstring("w:after=\"600\""), "Base has the new spacing")
        XCTAssertTrue(xml.containsSubstring("<w:basedOn w:val=\"Base\""), "Child still based on Base")
        XCTAssertTrue(xml.containsSubstring("<w:link w:val=\"BaseChar\""))
        let back = try DocxFormat.read(DocxFormat.write(c.document, pageSetup: .letter)).document
        XCTAssertEqual(back.styles["Base"]?.paragraph.spaceAfter, 30)
    }

    func testDeleteBaseRepointsChildNextAndLink() throws {
        let c = try open(dropping: "Base")
        let xml = try stylesXML(c)
        XCTAssertFalse(xml.containsSubstring("w:styleId=\"Base\""))
        XCTAssertTrue(xml.containsSubstring("<w:basedOn w:val=\"Normal\""), "Child re-based on Base's parent")
        XCTAssertFalse(xml.containsSubstring("<w:basedOn w:val=\"Base\""))
        XCTAssertFalse(xml.containsSubstring("<w:link w:val=\"Base\""), "the char style's link is dropped")
    }

    func testCreatedStyleIsAppended() throws {
        let c = try open()
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        XCTAssertEqual(c.createStyleFromSelection(name: "Mine"), "Mine")
        let xml = try stylesXML(c)
        XCTAssertTrue(xml.containsSubstring("w:styleId=\"Mine\""))
        XCTAssertTrue(xml.containsSubstring("<w:basedOn w:val=\"Base\""))
    }

    /// Sweep: five corpus documents with basedOn chains and linked character styles lose none of it.
    func testGlossaryAndStylesWithEffectsStayInTheFile() throws {
        var entries = try Zip.read(Self.sample())
        func edit(_ name: String, _ f: (String) -> String) {
            let k = entries.firstIndex { $0.name == name }!
            entries[k] = ZipEntry(name: name, data: Data(f(String(decoding: entries[k].data, as: UTF8.self)).utf8))
        }
        edit("[Content_Types].xml") { $0.replacingAll("</Types>", with: "<Override PartName=\"/word/stylesWithEffects.xml\" ContentType=\"application/vnd.ms-word.stylesWithEffects+xml\"/><Override PartName=\"/word/glossary/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.glossary+xml\"/><Override PartName=\"/word/glossary/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml\"/></Types>") }
        edit("word/_rels/document.xml.rels") { $0.replacingAll("</Relationships>", with: "<Relationship Id=\"rId90\" Type=\"http://schemas.microsoft.com/office/2007/relationships/stylesWithEffects\" Target=\"stylesWithEffects.xml\"/><Relationship Id=\"rId91\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/glossaryDocument\" Target=\"glossary/document.xml\"/></Relationships>") }
        let w = Self.w
        entries.append(ZipEntry(name: "word/stylesWithEffects.xml", data: Data("<w:styles xmlns:w=\"\(w)\"><w:style w:type=\"paragraph\" w:styleId=\"Fx\"/></w:styles>".utf8)))
        entries.append(ZipEntry(name: "word/glossary/document.xml", data: Data("<w:document xmlns:w=\"\(w)\"><w:docParts><w:docPart/></w:docParts></w:document>".utf8)))
        entries.append(ZipEntry(name: "word/glossary/styles.xml", data: Data("<w:styles xmlns:w=\"\(w)\"/>".utf8)))
        entries.append(ZipEntry(name: "word/glossary/_rels/document.xml.rels", data: Data("<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/></Relationships>".utf8)))
        let doc = try DocxFormat.read(try Zip.write(entries)).document
        let out = try Zip.read(try DocxFormat.write(doc, pageSetup: .letter))
        func text(_ n: String) -> String { out.first { $0.name == n }.map { String(decoding: $0.data, as: UTF8.self) } ?? "" }
        XCTAssertTrue(text("word/stylesWithEffects.xml").containsSubstring("Fx"))
        XCTAssertTrue(text("word/glossary/document.xml").containsSubstring("docPart"))
        XCTAssertTrue(text("word/glossary/styles.xml").containsSubstring("w:styles"))
        XCTAssertTrue(text("word/glossary/_rels/document.xml.rels").containsSubstring("styles.xml"))
        let rels = text("word/_rels/document.xml.rels")
        XCTAssertTrue(rels.containsSubstring("glossaryDocument") && rels.containsSubstring("stylesWithEffects"), rels)
        let types = text("[Content_Types].xml")
        XCTAssertTrue(types.containsSubstring("/word/glossary/document.xml") && types.containsSubstring("/word/glossary/styles.xml") && types.containsSubstring("/word/stylesWithEffects.xml"), types)
    }

    func testCorpusSweepLosesNothing() throws {
        let dir = "/data/corpus-cache/test/corpus/docx"
        let names = ["docs/zh-b711dc644603ae934161a1d969cffa91f50cc823b1bf5974a8c7fa79808b0adf.docx", "lo/docs/lo-4f5353c6f157801c.docx", "docs/58067.docx",
                     "docs/zh-9462c6d65156392156e80372e0f2a78b11720c6a2b28cd788772eabbdab59b26.docx",
                     "docs/zh-64c27df5d3b06bb1729113e99684fabc904c09c31a2c098934803f21154213d5.docx"]
        var ran = 0
        for n in names {
            let path = "\(dir)/\(n)"
            guard let data = FileManager.default.contents(atPath: path) else { continue }
            ran += 1
            let c = RichDocumentController(document: try DocxFormat.read(data).document)
            c.insertText("x")
            let out = try DocxFormat.write(c.document, pageSetup: .letter)
            func count(_ d: Data) -> [Int] {
                let s = ((try? Zip.read(d))?.first { $0.name == "word/styles.xml" }?.data).map { String(decoding: $0, as: UTF8.self) } ?? ""
                func k(_ t: String) -> Int { s.components(separatedBy: t).count - 1 }
                return [k("<w:link "), k("<w:lsdException"), k("<w:rsid "), k("<w:aliases")]
            }
            XCTAssertEqual(count(out), count(data), n)
            XCTAssertNoThrow(try DocxFormat.read(out), n)
        }
        if ran == 0 { throw XCTSkip("no corpus") }
    }
}
