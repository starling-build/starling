import XCTest
@testable import OfficeApp
@testable import OfficeText
/// W-FD-2: a table of contents field (its entries are ordinary paragraphs) survives save and reopen as the field.
final class TocFieldTests: XCTestCase {
    func testTocFieldSurvivesSaveAndReopen() throws {
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .letter))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let body = xml.range(of: "<w:body>")!, sect = xml.range(of: "<w:sectPr")!
        let toc1 = "<w:p><w:pPr><w:pStyle w:val=\"TOC1\"/><w:tabs><w:tab w:val=\"right\" w:leader=\"dot\" w:pos=\"9350\"/></w:tabs></w:pPr><w:r><w:fldChar w:fldCharType=\"begin\"/></w:r><w:r><w:instrText xml:space=\"preserve\"> TOC \\o \"1-3\" \\h \\z \\u </w:instrText></w:r><w:r><w:fldChar w:fldCharType=\"separate\"/></w:r><w:hyperlink w:anchor=\"_Toc1\" w:history=\"1\"><w:r><w:t>Intro</w:t></w:r><w:r><w:tab/></w:r><w:r><w:fldChar w:fldCharType=\"begin\"/></w:r><w:r><w:instrText xml:space=\"preserve\"> PAGEREF _Toc1 \\h </w:instrText></w:r><w:r><w:fldChar w:fldCharType=\"separate\"/></w:r><w:r><w:t>1</w:t></w:r><w:r><w:fldChar w:fldCharType=\"end\"/></w:r></w:hyperlink></w:p>"
        let toc2 = "<w:p><w:pPr><w:pStyle w:val=\"TOC1\"/></w:pPr><w:hyperlink w:anchor=\"_Toc2\" w:history=\"1\"><w:r><w:t>Second</w:t></w:r><w:r><w:tab/></w:r><w:r><w:fldChar w:fldCharType=\"begin\"/></w:r><w:r><w:instrText xml:space=\"preserve\"> PAGEREF _Toc2 \\h </w:instrText></w:r><w:r><w:fldChar w:fldCharType=\"separate\"/></w:r><w:r><w:t>2</w:t></w:r><w:r><w:fldChar w:fldCharType=\"end\"/></w:r></w:hyperlink></w:p><w:p><w:r><w:fldChar w:fldCharType=\"end\"/></w:r></w:p>"
        let h1 = "<w:p><w:pPr><w:pStyle w:val=\"Heading1\"/></w:pPr><w:bookmarkStart w:id=\"1\" w:name=\"_Toc1\"/><w:r><w:t>Intro</w:t></w:r><w:bookmarkEnd w:id=\"1\"/></w:p>"
        let h2 = "<w:p><w:pPr><w:pStyle w:val=\"Heading1\"/><w:pageBreakBefore/></w:pPr><w:bookmarkStart w:id=\"2\" w:name=\"_Toc2\"/><w:r><w:t>Second</w:t></w:r><w:bookmarkEnd w:id=\"2\"/></w:p>"
        xml.replaceSubrange(body.upperBound ..< sect.lowerBound, with: toc1 + toc2 + h1 + h2)
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let doc = try DocxFormat.read(try Zip.write(entries)).document
        XCTAssertEqual(doc.paragraphs[0].style.contentsStart, "TOC \\o \"1-3\" \\h \\z \\u")
        XCTAssertNil(doc.paragraphs[1].style.contentsStart)
        XCTAssertTrue(doc.paragraphs[2].style.contentsEnd)
        XCTAssertFalse(doc.paragraphs[0].style.contentsEnd)
        let out = try DocxFormat.write(doc, pageSetup: .letter)
        let o = String(decoding: try Zip.read(out).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertEqual(o.components(separatedBy: "TOC \\o").count - 1, 1)
        let back = try DocxFormat.read(out).document
        XCTAssertEqual(back.paragraphs[0].style.contentsStart, doc.paragraphs[0].style.contentsStart)
        XCTAssertTrue(back.paragraphs[2].style.contentsEnd)
        XCTAssertEqual(back.paragraphs.map(\.text), doc.paragraphs.map(\.text))
        // the field opens before the first entry and closes after the last
        let begin = try XCTUnwrap(o.range(of: "TOC \\o")), firstLink = try XCTUnwrap(o.range(of: "<w:hyperlink"))
        XCTAssertLessThan(begin.lowerBound, firstLink.lowerBound)
    }
}
