import XCTest
@testable import OfficeApp
@testable import OfficeText

/// A HYPERLINK complex field is read as a link and saved as the field, also when it spans paragraphs or has fields inside.
final class HyperlinkFieldTests: XCTestCase {
    private func fc(_ t: String) -> String { "<w:r><w:fldChar w:fldCharType=\"\(t)\"/></w:r>" }
    private func it(_ s: String) -> String { "<w:r><w:instrText xml:space=\"preserve\"> \(s) </w:instrText></w:r>" }
    private func tx(_ s: String) -> String { "<w:r><w:t xml:space=\"preserve\">\(s)</w:t></w:r>" }

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
    private func count(_ xml: String, _ s: String) -> Int { xml.components(separatedBy: s).count - 1 }

    func testTargetParsing() {
        XCTAssertEqual(DocxFormat._hyperlinkFieldTarget("HYPERLINK \"http://a.b/c\"")?.target, "http://a.b/c")
        XCTAssertEqual(DocxFormat._hyperlinkFieldTarget("HYPERLINK \\l \"_Toc1\"")?.target, "#_Toc1")
        XCTAssertEqual(DocxFormat._hyperlinkFieldTarget("HYPERLINK \"http://a.b\" \\l \"x\" \\o \"tip\"")?.target, "http://a.b#x")
        XCTAssertEqual(DocxFormat._hyperlinkFieldTarget("HYPERLINK \"http://a.b\" \\o \"tip\"")?.tip, "tip")
    }

    func testSimpleFieldIsALinkKeptAsField() throws {
        let (doc, xml) = try roundTrip("<w:p>\(tx("see "))\(fc("begin"))\(it("HYPERLINK \\l \"_Toc1\""))\(fc("separate"))\(tx("here"))\(fc("end"))\(tx(" ok"))</w:p>")
        XCTAssertTrue(doc.paragraphs.flatMap(\.runs).contains { $0.style.link == "#_Toc1" })
        XCTAssertEqual(count(xml, "fldCharType=\"begin\""), 1)
        XCTAssertEqual(count(xml, "fldCharType=\"end\""), 1)
        XCTAssertTrue(xml.contains("HYPERLINK \\l &quot;_Toc1&quot; </w:instrText>") || xml.contains("HYPERLINK \\l \"_Toc1\" </w:instrText>"))
        let b = try XCTUnwrap(xml.range(of: "fldCharType=\"begin\""))
        let e = try XCTUnwrap(xml.range(of: "fldCharType=\"end\""))
        XCTAssertTrue(xml[..<b.lowerBound].contains("see "))
        XCTAssertTrue(xml[b.lowerBound..<e.upperBound].contains("here"))
        XCTAssertTrue(xml[e.upperBound...].contains(" ok"))
    }

    func testFieldAcrossParagraphsAndWithNestedField() throws {
        let body = "<w:p>\(fc("begin"))\(it("HYPERLINK \\l \"_Toc9\""))\(fc("separate"))\(tx("one "))"
            + "\(fc("begin"))\(it("PAGEREF _Toc9 \\h"))\(fc("separate"))\(tx("4"))\(fc("end"))</w:p>"
            + "<w:p>\(tx("two"))\(fc("end"))\(tx(" tail"))</w:p>"
        let (doc, xml) = try roundTrip(body)
        XCTAssertEqual(count(xml, "fldCharType=\"begin\""), 2)
        XCTAssertEqual(count(xml, "fldCharType=\"end\""), 2)
        XCTAssertEqual(count(xml, "fldCharType=\"separate\""), 2)
        XCTAssertEqual(count(xml, "HYPERLINK"), 1)
        XCTAssertEqual(count(xml, "PAGEREF"), 1)
        // Reading what was written gives the same link on the same text.
        let again = try roundTrip(xml.components(separatedBy: "<w:body>").last!.components(separatedBy: "</w:body>").first!.replacingOccurrences(of: "<w:sectPr", with: "<w:sectPr"))
        XCTAssertEqual(count(again.xml, "HYPERLINK"), 1)
        _ = doc
    }

    func testFieldLinkIsNotDrawnAsALinkUnlessStyled() throws {
        let (doc, _) = try roundTrip("<w:p>\(fc("begin"))\(it("HYPERLINK \"http://x.y\""))\(fc("separate"))\(tx("plain"))\(fc("end"))</w:p>")
        let r = try XCTUnwrap(doc.paragraphs.flatMap(\.runs).first { $0.style.link != nil })
        XCTAssertNotNil(r.style.linkField)
        XCTAssertNil(r.style.color)
    }
}

extension HyperlinkFieldTests {
    /// HL_CHECK_IN=<docx> HL_CHECK_OUT=<docx>: read a file and save it again, for a check in Word.
    func testSaveForWordCheck() throws {
        let env = ProcessInfo.processInfo.environment
        guard let i = env["HL_CHECK_IN"], let o = env["HL_CHECK_OUT"] else { return }
        let read = try DocxFormat.read(try Data(contentsOf: URL(fileURLWithPath: i)))
        try DocxFormat.write(read.document, pageSetup: read.pageSetup ?? .letter).write(to: URL(fileURLWithPath: o))
    }
}

extension HyperlinkFieldTests {
    func testFieldResultKeepsItsOwnLookWithoutAHyperlinkStyle() throws {
        let (_, xml) = try roundTrip("<w:p>\(fc("begin"))\(it("HYPERLINK \"http://x.y\""))\(fc("separate"))\(tx("plain"))\(fc("end"))</w:p>")
        XCTAssertFalse(xml.contains("w:val=\"Hyperlink\""))
    }
}

extension HyperlinkFieldTests {
    func testHyperlinkElementRunWithoutStyleStaysWithoutStyle() throws {
        let (_, xml) = try roundTrip("<w:p><w:hyperlink w:anchor=\"bm\"><w:r><w:rPr><w:sz w:val=\"28\"/></w:rPr><w:t>plain</w:t></w:r></w:hyperlink></w:p>")
        XCTAssertFalse(xml.contains("w:val=\"Hyperlink\""))
    }
}

extension HyperlinkFieldTests {
    func testHyperlinkElementRunWithHyperlinkStyleKeepsItOnce() throws {
        let (_, xml) = try roundTrip("<w:p><w:hyperlink w:anchor=\"bm\"><w:r><w:rPr><w:rStyle w:val=\"Hyperlink\"/></w:rPr><w:t>styled</w:t></w:r></w:hyperlink></w:p>")
        XCTAssertEqual(xml.components(separatedBy: "<w:rStyle w:val=\"Hyperlink\"/>").count - 1, 1)
    }
}

extension HyperlinkFieldTests {
    func testFieldCodeRunsCarryNoCharacterStyle() throws {
        let (_, xml) = try roundTrip("<w:p>\(fc("begin"))\(it("HYPERLINK \"http://x.y\""))\(fc("separate"))<w:r><w:rPr><w:rStyle w:val=\"Hyperlink\"/></w:rPr><w:t>go</w:t></w:r>\(fc("end"))</w:p>")
        XCTAssertFalse(xml.contains("<w:rPr><w:rStyle w:val=\"Hyperlink\"/></w:rPr><w:fldChar"))
        XCTAssertFalse(xml.contains("<w:rStyle w:val=\"Hyperlink\"/></w:rPr><w:instrText"))
        XCTAssertTrue(xml.contains("<w:rStyle w:val=\"Hyperlink\"/></w:rPr><w:t>go"))
    }
}

extension HyperlinkFieldTests {
    func testNeighbouringRunsOfOneTargetShareOneHyperlink() throws {
        let (_, xml) = try roundTrip("<w:p><w:hyperlink w:anchor=\"bm\"><w:r><w:t>a</w:t></w:r><w:r><w:tab/></w:r><w:r><w:t>b</w:t></w:r></w:hyperlink></w:p>")
        XCTAssertEqual(xml.components(separatedBy: "<w:hyperlink ").count - 1, 1)
    }
}

extension HyperlinkFieldTests {
    /// A table of contents draws its entries in the paragraph's own look, but the save keeps the style name the runs had.
    func testContentsEntryKeepsItsHyperlinkStyleName() throws {
        let (_, xml) = try roundTrip("<w:p>\(fc("begin"))\(it("TOC \\o \"1-3\" \\h"))\(fc("separate"))<w:hyperlink w:anchor=\"bm\"><w:r><w:rPr><w:rStyle w:val=\"Hyperlink\"/></w:rPr><w:t>entry</w:t></w:r></w:hyperlink></w:p><w:p>\(fc("end"))</w:p>")
        XCTAssertTrue(xml.contains("<w:rStyle w:val=\"Hyperlink\"/></w:rPr><w:t>entry"))
    }
}

extension HyperlinkFieldTests {
    func testSaveKeepsWhatTheFileWroteAboutHistory() throws {
        let (_, without) = try roundTrip("<w:p><w:hyperlink w:anchor=\"bm\"><w:r><w:t>a</w:t></w:r></w:hyperlink></w:p>")
        XCTAssertFalse(without.contains("w:history"))
        let (_, with) = try roundTrip("<w:p><w:hyperlink w:anchor=\"bm\" w:history=\"1\"><w:r><w:t>a</w:t></w:r></w:hyperlink></w:p>")
        XCTAssertTrue(with.contains("<w:hyperlink w:anchor=\"bm\" w:history=\"1\">"))
    }

    func testALinkMadeInTheAppIsWrittenWithHistory() throws {
        var s = CharStyle.plain; s.link = "#bm"
        let p = RichParagraph(text: "go", runs: [Run(length: 2, style: s)])
        let data = try DocxFormat.write(RichDocument(paragraphs: [p]), pageSetup: .letter)
        let xml = String(decoding: try Zip.read(data).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(xml.contains("w:history=\"1\""))
    }
}
