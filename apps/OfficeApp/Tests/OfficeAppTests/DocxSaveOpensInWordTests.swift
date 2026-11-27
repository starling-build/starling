// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Foundation
import OfficeText
@testable import OfficeApp

/// Saves Word refused to open (or hung on), one test per cause, each confirmed by Word on a one-fix copy
/// of the refused file (open60 rounds 1-3, 2026-11-26/27).
final class DocxSaveOpensInWordTests: XCTestCase {
    private let rt = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"

    private func text(_ parts: [ZipEntry], _ n: String) -> String? {
        parts.first { $0.name == n }.map { String(decoding: $0.data, as: UTF8.self) }
    }

    /// A fresh save with `body` put at the head of the body, `edit` applied to the document XML, and `extra` parts added.
    private func resave(_ body: String, edit: (String) -> String = { $0 }, extra: [(String, String)] = [],
                        rels: String = "", types: String = "") throws -> [ZipEntry] {
        var parts = try Zip.read(DocxFormat.write(RichDocument(paragraphs: [RichParagraph()]), pageSetup: .letter))
        func replace(_ n: String, _ f: (String) -> String) throws {
            let i = try XCTUnwrap(parts.firstIndex { $0.name == n })
            parts[i] = ZipEntry(name: n, data: Data(f(String(decoding: parts[i].data, as: UTF8.self)).utf8))
        }
        try replace("word/document.xml") { s in
            var x = s
            x.insert(contentsOf: body, at: x.range(of: "<w:body>")!.upperBound)
            return edit(x)
        }
        if !rels.isEmpty { try replace("word/_rels/document.xml.rels") { $0.replacingOccurrences(of: "</Relationships>", with: rels + "</Relationships>") } }
        if !types.isEmpty { try replace("[Content_Types].xml") { $0.replacingOccurrences(of: "</Types>", with: types + "</Types>") } }
        for (n, t) in extra {
            parts.removeAll { $0.name == n }
            parts.append(ZipEntry(name: n, data: Data(t.utf8)))
        }
        let read = try DocxFormat.read(try Zip.write(parts))
        return try Zip.read(DocxFormat.write(read.document, pageSetup: read.pageSetup ?? .letter))
    }

    private func grab(_ s: String, _ pattern: String) -> [String] {
        let re = try! NSRegularExpression(pattern: pattern)
        return re.matches(in: s, range: NSRange(s.startIndex..., in: s)).map { String(s[Range($0.range(at: 1), in: s)!]) }
    }

    /// A chart's theme override sits in word/theme/ beside the theme. Linked from the document as a second theme under
    /// the same relationship id, Word refuses the file (zh-b8de).
    func testThemeOverrideIsNotASecondDocumentThemeRel() throws {
        let theme = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><a:theme xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" name=\"T\"><a:themeElements/></a:theme>"
        let over = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><a:themeOverride xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\"><a:clrScheme name=\"O\"/></a:themeOverride>"
        let saved = try resave("<w:p><w:r><w:t>x</w:t></w:r></w:p>",
                               extra: [("word/theme/theme1.xml", theme), ("word/theme/themeOverride1.xml", over)])
        let rels = try XCTUnwrap(text(saved, "word/_rels/document.xml.rels"))
        let ids = grab(rels, #"Id="([^"]+)""#)
        XCTAssertEqual(ids.count, Set(ids).count, "duplicate relationship ids: \(rels)")
        XCTAssertFalse(rels.contains("themeOverride1.xml"), rels)
        XCTAssertTrue(rels.contains("Target=\"theme/theme1.xml\""), rels)
        let types = try XCTUnwrap(text(saved, "[Content_Types].xml"))
        XCTAssertTrue(types.contains("PartName=\"/word/theme/themeOverride1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.themeOverride+xml\""), types)
    }

    /// The numbering part goes back as read, picture bullets' r:id included, so its rels and the image they name go too:
    /// an r:id with no relationship behind it makes Word refuse the file (f154, sa2).
    func testPictureBulletKeepsNumberingRelsAndImage() throws {
        let numbering = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><w:numbering xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" xmlns:r=\"\(rt)\" xmlns:v=\"urn:schemas-microsoft-com:vml\" xmlns:o=\"urn:schemas-microsoft-com:office:office\">"
            + "<w:numPicBullet w:numPicBulletId=\"0\"><w:pict><v:shape id=\"_x0000_i1025\" type=\"#_x0000_t75\" style=\"width:9pt;height:9pt\" o:bullet=\"t\"><v:imagedata r:id=\"rId1\" o:title=\"\"/></v:shape></w:pict></w:numPicBullet>"
            + "<w:abstractNum w:abstractNumId=\"0\"><w:lvl w:ilvl=\"0\"><w:start w:val=\"1\"/><w:numFmt w:val=\"bullet\"/><w:lvlText w:val=\"\u{F0B7}\"/><w:lvlPicBulletId w:val=\"0\"/><w:lvlJc w:val=\"left\"/><w:pPr><w:ind w:left=\"720\" w:hanging=\"360\"/></w:pPr></w:lvl></w:abstractNum>"
            + "<w:num w:numId=\"1\"><w:abstractNumId w:val=\"0\"/></w:num></w:numbering>"
        let numRels = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"\(rt)/image\" Target=\"media/image1.gif\"/></Relationships>"
        var parts = try Zip.read(DocxFormat.write(RichDocument(paragraphs: [RichParagraph()]), pageSetup: .letter))
        let hasNumbering = parts.contains { $0.name == "word/numbering.xml" }
        parts.removeAll { $0.name == "word/numbering.xml" }
        parts.append(ZipEntry(name: "word/numbering.xml", data: Data(numbering.utf8)))
        parts.append(ZipEntry(name: "word/_rels/numbering.xml.rels", data: Data(numRels.utf8)))
        parts.append(ZipEntry(name: "word/media/image1.gif", data: Data("GIF89a\u{1}\u{0}\u{1}\u{0}".utf8)))
        func replace(_ n: String, _ f: (String) -> String) throws {
            let i = try XCTUnwrap(parts.firstIndex { $0.name == n })
            parts[i] = ZipEntry(name: n, data: Data(f(String(decoding: parts[i].data, as: UTF8.self)).utf8))
        }
        try replace("word/document.xml") { s in
            var x = s
            x.insert(contentsOf: "<w:p><w:pPr><w:numPr><w:ilvl w:val=\"0\"/><w:numId w:val=\"1\"/></w:numPr></w:pPr><w:r><w:t>item</w:t></w:r></w:p>", at: x.range(of: "<w:body>")!.upperBound)
            return x
        }
        if !hasNumbering {
            try replace("word/_rels/document.xml.rels") { $0.replacingOccurrences(of: "</Relationships>", with: "<Relationship Id=\"rId90\" Type=\"\(rt)/numbering\" Target=\"numbering.xml\"/></Relationships>") }
            try replace("[Content_Types].xml") { $0.replacingOccurrences(of: "</Types>", with: "<Override PartName=\"/word/numbering.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml\"/></Types>") }
        }
        try replace("[Content_Types].xml") { $0.contains("Extension=\"gif\"") ? $0 : $0.replacingOccurrences(of: "</Types>", with: "<Default Extension=\"gif\" ContentType=\"image/gif\"/></Types>") }
        let read = try DocxFormat.read(try Zip.write(parts))
        let saved = try Zip.read(DocxFormat.write(read.document, pageSetup: .letter))
        let num = try XCTUnwrap(text(saved, "word/numbering.xml"))
        let used = Set(grab(num, #"r:id="([^"]+)""#))
        guard !used.isEmpty else { return }   // the picture bullet was not written back: nothing can dangle
        let rels = try XCTUnwrap(text(saved, "word/_rels/numbering.xml.rels"), "numbering names \(used) with no rels part")
        for id in used {
            let target = try XCTUnwrap(grab(rels, #"Id="\#(id)"[^>]*Target="([^"]+)""#).first ?? grab(rels, #"Target="([^"]+)"[^>]*Id="\#(id)""#).first, "no rel \(id): \(rels)")
            XCTAssertTrue(saved.contains { $0.name == "word/" + target }, "rel \(id) names word/\(target), not in the package")
        }
    }

    /// A run kept as read can use a prefix the editor's own root never declares, here w16se in an
    /// mc:AlternateContent choice's Requires in a run's properties: the document root must declare it, or Word refuses the file (dx2-a435).
    func testKeptRunsPrefixIsDeclaredOnTheRoot() throws {
        let run = "<w:r><w:rPr><mc:AlternateContent xmlns:mc=\"http://schemas.openxmlformats.org/markup-compatibility/2006\"><mc:Choice Requires=\"w16se\"><w:rFonts w:ascii=\"Comic Sans MS\" w:hAnsi=\"Comic Sans MS\"/></mc:Choice><mc:Fallback><w:rFonts w:ascii=\"Arial\" w:hAnsi=\"Arial\"/></mc:Fallback></mc:AlternateContent><w:b/></w:rPr><w:t>party</w:t></w:r>"
        let saved = try resave("<w:p>\(run)<w:r><w:t>x</w:t></w:r></w:p>",
                               edit: { $0.replacingOccurrences(of: "<w:document ", with: "<w:document xmlns:w16se=\"http://schemas.microsoft.com/office/word/2015/wordml/symex\" ") })
        let xml = try XCTUnwrap(text(saved, "word/document.xml"))
        let at = try XCTUnwrap(xml.range(of: "<w:document ")).lowerBound
        let root = String(xml[at...].prefix { $0 != ">" })
        for p in Set(grab(xml, #"<([A-Za-z0-9]+):"#) + grab(xml, #"Requires="([A-Za-z0-9]+)""#)) where p != "xml" {
            XCTAssertTrue(root.contains("xmlns:\(p)=") || xml.contains("xmlns:\(p)="), "prefix \(p) used, never declared: \(root)")
        }
        XCTAssertTrue(xml.contains("Requires=\"w16se\""), "the run's alternate content is kept: \(xml)")
        XCTAssertTrue(root.contains("xmlns:w16se=\"http://schemas.microsoft.com/office/word/2015/wordml/symex\""), root)
    }

    /// A bookmark that starts before a content control and ends where it ends must close after the control,
    /// not inside it: a bookmark that crosses a control's edge makes Word refuse the file (xa-gv).
    func testBookmarkEndingWithAControlClosesOutsideIt() throws {
        let body = "<w:p><w:bookmarkStart w:id=\"5\" w:name=\"pick\"/><w:r><w:t>Choose: </w:t></w:r>"
            + "<w:sdt><w:sdtPr><w:id w:val=\"7\"/><w:comboBox><w:listItem w:displayText=\"One\" w:value=\"One\"/></w:comboBox></w:sdtPr><w:sdtContent><w:r><w:t>One</w:t></w:r></w:sdtContent></w:sdt>"
            + "<w:bookmarkEnd w:id=\"5\"/><w:r><w:t> after</w:t></w:r></w:p>"
        let saved = try resave(body)
        let xml = try XCTUnwrap(text(saved, "word/document.xml"))
        let s = try XCTUnwrap(xml.range(of: "w:name=\"pick\""), xml)
        let id = try XCTUnwrap(grab(String(xml[..<s.upperBound].suffix(80)), #"w:id="(\d+)""#).last)
        let e = try XCTUnwrap(xml.range(of: "<w:bookmarkEnd w:id=\"\(id)\"/>", range: s.upperBound ..< xml.endIndex), xml)
        let between = String(xml[s.upperBound ..< e.lowerBound])
        XCTAssertTrue(between.contains("<w:sdt>"), "the control is inside the bookmark: \(between)")
        XCTAssertEqual(between.components(separatedBy: "<w:sdt>").count, between.components(separatedBy: "</w:sdt>").count,
                       "the bookmark crosses a control edge: \(between)")
    }

    /// An empty content control opens and closes at one place: it is written whole there, never closed before it
    /// opens (that made the document XML ill-formed; sa1-74e2, round 4 of the fixes above).
    func testEmptyControlIsWrittenWhole() throws {
        let body = "<w:p><w:r><w:t xml:space=\"preserve\">Quanto, </w:t></w:r><w:sdt><w:sdtPr><w:tag w:val=\"t\"/><w:id w:val=\"-11\"/></w:sdtPr><w:sdtEndPr/><w:sdtContent/></w:sdt><w:r><w:t>a fonte.</w:t></w:r></w:p>"
        let saved = try resave(body)
        let xml = try XCTUnwrap(text(saved, "word/document.xml"))
        // Every control closes after it opens: the nesting depth never goes below zero and ends at zero.
        var depth = 0, opened = 0
        for t in grab(xml, #"(</?w:sdt(?:>| ))"#) {
            depth += t.hasPrefix("</") ? -1 : 1
            if !t.hasPrefix("</") { opened += 1 }
            XCTAssertGreaterThanOrEqual(depth, 0, "a control closes before it opens: \(xml)")
        }
        XCTAssertEqual(depth, 0, xml)
        XCTAssertEqual(opened, 1, xml)
    }

    /// Section property changes carry tracked-change ids like any other revision: a new revision's id must not
    /// reuse one, or Word hangs opening the file (lo-lo).
    func testTrackedChangeIdsStayUniqueWithSectionChanges() throws {
        let change = "<w:sectPrChange w:id=\"4\" w:author=\"A\" w:date=\"2024-01-01T00:00:00Z\"><w:sectPr/></w:sectPrChange>"
        let body = "<w:p><w:pPr><w:sectPr><w:pgSz w:w=\"12240\" w:h=\"15840\"/><w:sectPrChange w:id=\"1\" w:author=\"A\" w:date=\"2024-01-01T00:00:00Z\"><w:sectPr/></w:sectPrChange></w:sectPr></w:pPr><w:r><w:t>one</w:t></w:r></w:p>"
            + "<w:p><w:ins w:id=\"3\" w:author=\"A\" w:date=\"2024-01-01T00:00:00Z\"><w:r><w:t>two</w:t></w:r></w:ins></w:p>"
        var parts = try resave(body, edit: { x in
            guard let r = x.range(of: "</w:sectPr>", options: .backwards) else { return x }
            return x.replacingCharacters(in: r, with: change + "</w:sectPr>")
        })
        let first = try XCTUnwrap(text(parts, "word/document.xml"))
        XCTAssertTrue(first.contains("w:sectPrChange"), "the section changes are kept: \(first)")
        // A tracked format change made in the editor, so the save mints a new id beside the kept ones.
        var doc = try DocxFormat.read(try Zip.write(parts)).document
        let i = try XCTUnwrap(doc.paragraphs.firstIndex { $0.text == "one" })
        doc.paragraphs[i].applyStyle(0 ..< 3) { $0.bold = true; $0.formatChange = FormatChange(author: "B", date: "2024-01-02T00:00:00Z", oldRPrXML: "") }
        parts = try Zip.read(DocxFormat.write(doc, pageSetup: .letter))
        let xml = try XCTUnwrap(text(parts, "word/document.xml"))
        let tags = "ins|del|moveFrom|moveTo|rPrChange|pPrChange|sectPrChange|tblPrChange|trPrChange|tcPrChange|tblGridChange|numberingChange|cellIns|cellDel|cellMerge"
        let ids = grab(xml, #"<w:(?:\#(tags))\b[^>]*\bw:id="(\d+)""#)
        XCTAssertGreaterThanOrEqual(ids.count, 3, xml)
        XCTAssertEqual(ids.count, Set(ids).count, "tracked-change ids repeat: \(ids)")
    }

    /// A tracked change to a paragraph's properties (w:pPrChange, with the properties it had before) goes back
    /// with the paragraph: the save dropped all 96 of lo-9f27's.
    func testParagraphPropertyChangeIsKept() throws {
        let saved = try resave("<w:p><w:pPr><w:jc w:val=\"center\"/><w:pPrChange w:id=\"7\" w:author=\"Ann\" w:date=\"2020-01-02T03:04:00Z\"><w:pPr><w:jc w:val=\"right\"/></w:pPr></w:pPrChange></w:pPr><w:r><w:t>x</w:t></w:r></w:p>")
        let doc = try XCTUnwrap(text(saved, "word/document.xml"))
        let change = grab(doc, #"(<w:pPrChange [^>]*>.*?</w:pPrChange>)"#)
        XCTAssertEqual(change.count, 1, doc)
        XCTAssertTrue(change.first?.contains("w:author=\"Ann\"") ?? false, doc)
        XCTAssertTrue(change.first?.contains("<w:pPr><w:jc w:val=\"right\"/></w:pPr>") ?? false, doc)
        XCTAssertTrue(doc.contains("<w:jc w:val=\"center\"/><w:pPrChange"), "the change sits last in w:pPr: \(doc)")
    }

    /// A SmartArt diagram's drawing part is named only from its data part (dsp:dataModelExt relId): the save
    /// dropped the part and its relationship, and the data named an id that no longer existed (xa gv-3db26).
    func testDiagramDrawingPartIsKeptAndItsIdFollows() throws {
        let dgm = "http://schemas.openxmlformats.org/drawingml/2006/diagram"
        let body = "<w:p><w:r><w:drawing><wp:inline><wp:extent cx=\"1270000\" cy=\"635000\"/><wp:docPr id=\"1\" name=\"D\"/><a:graphic xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\"><a:graphicData uri=\"\(dgm)\"><dgm:relIds xmlns:dgm=\"\(dgm)\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" r:dm=\"rIdD1\" r:lo=\"rIdD2\" r:qs=\"rIdD3\" r:cs=\"rIdD4\"/></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>"
        let data = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><dgm:dataModel xmlns:dgm=\"\(dgm)\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\"><dgm:ptLst/><dgm:extLst><a:ext uri=\"http://schemas.microsoft.com/office/drawing/2008/diagram\"><dsp:dataModelExt xmlns:dsp=\"http://schemas.microsoft.com/office/drawing/2008/diagram\" relId=\"rIdD5\" minVer=\"http://schemas.openxmlformats.org/drawingml/2006/diagram\"/></a:ext></dgm:extLst></dgm:dataModel>"
        let drawing = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><dsp:drawing xmlns:dsp=\"http://schemas.microsoft.com/office/drawing/2008/diagram\"><dsp:spTree><dsp:nvGrpSpPr><dsp:cNvPr id=\"0\" name=\"\"/><dsp:cNvGrpSpPr/></dsp:nvGrpSpPr><dsp:grpSpPr/></dsp:spTree></dsp:drawing>"
        func plain(_ root: String) -> String { "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><dgm:\(root) xmlns:dgm=\"\(dgm)\"/>" }
        let od = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/"
        let rels = "<Relationship Id=\"rIdD1\" Type=\"\(od)diagramData\" Target=\"diagrams/data1.xml\"/><Relationship Id=\"rIdD2\" Type=\"\(od)diagramLayout\" Target=\"diagrams/layout1.xml\"/><Relationship Id=\"rIdD3\" Type=\"\(od)diagramQuickStyle\" Target=\"diagrams/quickStyle1.xml\"/><Relationship Id=\"rIdD4\" Type=\"\(od)diagramColors\" Target=\"diagrams/colors1.xml\"/><Relationship Id=\"rIdD5\" Type=\"http://schemas.microsoft.com/office/2007/relationships/diagramDrawing\" Target=\"diagrams/drawing1.xml\"/>"
        let ct = "application/vnd.openxmlformats-officedocument.drawingml.diagram"
        let types = "<Override PartName=\"/word/diagrams/data1.xml\" ContentType=\"\(ct)Data+xml\"/><Override PartName=\"/word/diagrams/layout1.xml\" ContentType=\"\(ct)Layout+xml\"/><Override PartName=\"/word/diagrams/quickStyle1.xml\" ContentType=\"\(ct)Style+xml\"/><Override PartName=\"/word/diagrams/colors1.xml\" ContentType=\"\(ct)Colors+xml\"/><Override PartName=\"/word/diagrams/drawing1.xml\" ContentType=\"application/vnd.ms-office.drawingml.diagramDrawing+xml\"/>"
        let saved = try resave(body, extra: [("word/diagrams/data1.xml", data), ("word/diagrams/layout1.xml", plain("layoutDef")),
                                             ("word/diagrams/quickStyle1.xml", plain("styleDef")), ("word/diagrams/colors1.xml", plain("colorsDef")),
                                             ("word/diagrams/drawing1.xml", drawing)], rels: rels, types: types)
        XCTAssertNotNil(text(saved, "word/diagrams/drawing1.xml"), "drawing part dropped")
        let docRels = try XCTUnwrap(text(saved, "word/_rels/document.xml.rels"))
        let drawingID = try XCTUnwrap(grab(docRels, #"Id="([^"]+)"[^>]*diagramDrawing"#).first, docRels)
        let savedData = try XCTUnwrap(text(saved, "word/diagrams/data1.xml"))
        XCTAssertTrue(savedData.contains("relId=\"\(drawingID)\""), savedData)
        let savedTypes = try XCTUnwrap(text(saved, "[Content_Types].xml"))
        XCTAssertTrue(savedTypes.contains("PartName=\"/word/diagrams/drawing1.xml\" ContentType=\"application/vnd.ms-office.drawingml.diagramDrawing+xml\""), savedTypes)
    }

    /// A theme with a picture fill names the picture through its own rels: the save kept the theme alone, and it
    /// named an id with no relationship (dx2 16de187a).
    func testThemeKeepsItsRelsAndPicture() throws {
        let theme = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><a:theme xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:r=\"\(rt)\" name=\"T\"><a:themeElements><a:fmtScheme name=\"F\"><a:bgFillStyleLst><a:blipFill><a:blip r:embed=\"rId1\"/></a:blipFill></a:bgFillStyleLst></a:fmtScheme></a:themeElements></a:theme>"
        let rels = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"\(rt)/image\" Target=\"../media/image9.jpeg\"/></Relationships>"
        let saved = try resave("<w:p><w:r><w:t>x</w:t></w:r></w:p>",
                               extra: [("word/theme/theme1.xml", theme), ("word/theme/_rels/theme1.xml.rels", rels), ("word/media/image9.jpeg", "JPEG")])
        let savedRels = try XCTUnwrap(text(saved, "word/theme/_rels/theme1.xml.rels"), "theme rels dropped")
        XCTAssertTrue(savedRels.contains("Id=\"rId1\""), savedRels)
        XCTAssertNotNil(text(saved, "word/media/image9.jpeg"), "theme picture dropped")
        let types = try XCTUnwrap(text(saved, "[Content_Types].xml"))
        XCTAssertTrue(types.contains("Extension=\"jpeg\""), types)
    }

    /// Every kind of tracked change goes back as many times as the file had it, the paragraph mark's own format
    /// change included: without it Word split lo-9f27's deletions and format changes at each mark (211 revisions
    /// where the file had 129: deletions 88 against 19, format changes 104 against 44).
    func testTrackedChangesKeepTheirCountsByKind() throws {
        let a = "w:author=\"Jo\""
        func mark(_ id: Int, deleted: Bool) -> String {
            "<w:pPr><w:jc w:val=\"center\"/><w:rPr>\(deleted ? "<w:del w:id=\"\(id)\" \(a) w:date=\"2013-07-17T12:32:00Z\"/>" : "")<w:sz w:val=\"18\"/><w:rPrChange w:id=\"\(id + 1)\" \(a) w:date=\"2013-07-17T12:26:00Z\"><w:rPr>\(deleted ? "<w:del w:id=\"\(id)\" \(a) w:date=\"2013-07-17T12:32:00Z\"/>" : "")</w:rPr></w:rPrChange></w:rPr><w:pPrChange w:id=\"\(id + 2)\" \(a) w:date=\"2013-07-17T12:32:00Z\"><w:pPr/></w:pPrChange></w:pPr>"
        }
        func run(_ id: Int, _ t: String, deleted: Bool) -> String {
            let r = "<w:r><w:rPr><w:sz w:val=\"18\"/><w:rPrChange w:id=\"\(id)\" \(a) w:date=\"2013-07-17T12:26:00Z\"><w:rPr/></w:rPrChange></w:rPr><w:\(deleted ? "delText" : "t")>\(t)</w:\(deleted ? "delText" : "t")></w:r>"
            return deleted ? "<w:del w:id=\"\(id + 1)\" \(a) w:date=\"2013-07-17T12:32:00Z\">\(r)</w:del>" : r
        }
        let body = "<w:p>\(mark(10, deleted: true))\(run(20, "gone", deleted: true))</w:p><w:p>\(mark(30, deleted: true))\(run(40, "also", deleted: true))</w:p>"
            + "<w:p>\(mark(50, deleted: false))\(run(60, "kept", deleted: false))</w:p>"
            // One deletion over two runs that differ (they stay two runs): still one w:del.
            + "<w:p><w:del w:id=\"70\" \(a) w:date=\"2013-07-17T12:32:00Z\"><w:r><w:rPr><w:b/></w:rPr><w:delText>one</w:delText></w:r><w:r><w:delText>two</w:delText></w:r></w:del><w:r><w:t>end</w:t></w:r></w:p>"
        func counts(_ x: String) -> [String: Int] {
            var c: [String: Int] = [:]
            for tag in ["w:del", "w:ins", "w:rPrChange", "w:pPrChange"] { c[tag] = grab(x, "(<\(tag)[ >])").count }
            c["mark rPrChange"] = grab(x, "(<w:pPr>(?:(?!</w:pPr>).)*?<w:rPrChange)").count
            return c
        }
        let doc = try XCTUnwrap(text(try resave(body), "word/document.xml"))
        // A deleted mark's old properties repeat its w:del (Word writes it so): 2 more w:del, and every id unique.
        XCTAssertEqual(counts(doc), ["w:del": 7, "w:ins": 0, "w:rPrChange": 6, "w:pPrChange": 3, "mark rPrChange": 3], doc)
        let ids = grab(doc, "<w:(?:del|ins|rPrChange|pPrChange) w:id=\"(\\d+)\"")
        XCTAssertEqual(Set(ids).count, ids.count, "tracked-change ids repeat: \(ids)")
    }
}
