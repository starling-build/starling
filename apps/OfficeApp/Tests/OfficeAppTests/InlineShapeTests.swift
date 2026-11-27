// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp
@testable import OfficeText

/// W-OB-4: a shape In Line with Text (`wp:inline` holding a `wps:wsp`) takes the shape tools a floating one takes.
final class InlineShapeTests: XCTestCase {
    /// A document whose paragraph reads "before ", a 72 x 36 blue rectangle in line, " after".
    func inlineShapeDocument(text: Bool = false) throws -> RichDocument {
        let base = try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "before X after")]), pageSetup: .letter)
        var entries = try Zip.read(base)
        let di = try XCTUnwrap(entries.firstIndex { $0.name == "word/document.xml" })
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let drawing = "<w:drawing><wp:inline distT=\"0\" distB=\"0\" distL=\"0\" distR=\"0\"><wp:extent cx=\"914400\" cy=\"457200\"/><wp:effectExtent l=\"0\" t=\"0\" r=\"0\" b=\"0\"/>"
            + "<wp:docPr id=\"3\" name=\"Rectangle 3\"/><wp:cNvGraphicFramePr/>"
            + "<a:graphic xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\"><a:graphicData uri=\"http://schemas.microsoft.com/office/word/2010/wordprocessingShape\">"
            + "<wps:wsp xmlns:wps=\"http://schemas.microsoft.com/office/word/2010/wordprocessingShape\"><wps:cNvSpPr/>"
            + "<wps:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"914400\" cy=\"457200\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom>"
            + "<a:solidFill><a:srgbClr val=\"4472C4\"/></a:solidFill><a:ln w=\"9525\"><a:solidFill><a:srgbClr val=\"000000\"/></a:solidFill></a:ln></wps:spPr>"
            + (text ? "<wps:txbx><w:txbxContent><w:p><w:r><w:t>in</w:t></w:r></w:p></w:txbxContent></wps:txbx>" : "")
            + "<wps:bodyPr rot=\"0\" vert=\"horz\" wrap=\"square\" lIns=\"91440\" tIns=\"45720\" rIns=\"91440\" bIns=\"45720\" anchor=\"ctr\"><a:noAutofit/></wps:bodyPr>"
            + "</wps:wsp></a:graphicData></a:graphic></wp:inline></w:drawing>"
        let t = try XCTUnwrap(xml.rangeOfSubstring("before X after"))
        // Split the run round the X: "before " | drawing | " after".
        guard let rs = xml.rangeOfSubstring("<w:r>", in: xml.startIndex ..< t.lowerBound) ?? xml.rangeOfSubstring("<w:r ", in: xml.startIndex ..< t.lowerBound),
              let re = xml.rangeOfSubstring("</w:r>", in: t.upperBound ..< xml.endIndex) else { throw XCTSkip("no run") }
        _ = rs
        let rStart = xml[..<t.lowerBound].range(of: "<w:r", options: .backwards)!.lowerBound
        xml.replaceSubrange(rStart ..< re.upperBound, with: "<w:r><w:t xml:space=\"preserve\">before </w:t></w:r><w:r>" + drawing + "</w:r><w:r><w:t xml:space=\"preserve\"> after</w:t></w:r>")
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        return try DocxFormat.read(try Zip.write(entries)).document
    }

    private func savedBody(_ doc: RichDocument) throws -> String {
        let entries = try Zip.read(try DocxFormat.write(doc, pageSetup: .letter))
        return String(decoding: try XCTUnwrap(entries.first { $0.name == "word/document.xml" }).data, as: UTF8.self)
    }

    private func shape(_ c: RichDocumentController) throws -> (index: Int, id: String) {
        let i = try XCTUnwrap(c.document.paragraphs.firstIndex { !$0.inlineImages.isEmpty })
        return (i, try XCTUnwrap(c.document.paragraphs[i].inlineImages.keys.sorted().first))
    }

    func testAShapeInLineTakesFillAndOutlineAndStaysInLine() throws {
        let c = RichDocumentController(document: try inlineShapeDocument())
        let (i, id) = try shape(c)
        XCTAssertTrue(c.isInLineShape(at: i, inline: id))
        XCTAssertNil(c.pictureWrap(at: i, inline: id), "a shape in line has no wrap to choose")
        XCTAssertFalse(c.movePicture(at: i, inline: id, dx: 10, dy: 0), "nor a place to be nudged to")
        XCTAssertTrue(c.setShapeFill(at: i, inline: id, Color(0xFFFF_0000)))
        XCTAssertTrue(c.setShapeOutline(at: i, inline: id, nil))
        let xml = try savedBody(c.document)
        XCTAssertTrue(xml.containsSubstring("<a:srgbClr val=\"FF0000\"/>"), "the new fill is written")
        XCTAssertTrue(xml.containsSubstring("<a:ln w=\"9525\"><a:noFill/></a:ln>"), "the outline is gone")
        XCTAssertTrue(xml.containsSubstring("<wp:inline") && !xml.containsSubstring("<wp:anchor"), "it still stands in its line")
        XCTAssertTrue(xml.containsSubstring("before </w:t>") && xml.containsSubstring("> after</w:t>"), "the words round it stay")
        c.undo()
        c.undo()
        XCTAssertTrue(try savedBody(c.document).containsSubstring("<a:srgbClr val=\"4472C4\"/>"), "each change is one undo step")
    }

    func testAShapeInLineTakesWordsThroughASave() throws {
        let c = RichDocumentController(document: try inlineShapeDocument())
        let (i, id) = try shape(c)
        XCTAssertNil(c.textBoxDocument(at: i, inline: id))
        XCTAssertTrue(c.giveShapeText(at: i, inline: id), "entered, a plain shape in line takes a text part")
        let inside = try XCTUnwrap(c.textBoxDocument(at: i, inline: id))
        var words = inside
        var typed = RichParagraph(text: "hello")
        typed.style = words.paragraphs[0].style
        words.paragraphs[0] = typed
        let body = try XCTUnwrap(TextBoxInsert.content(words))
        XCTAssertTrue(c.setTextBoxContent(at: i, inline: id, document: words, contentXML: body.xml, rels: body.rels))
        let back = try DocxFormat.read(try DocxFormat.write(c.document, pageSetup: .letter)).document
        let p = try XCTUnwrap(back.paragraphs.first { !$0.inlineImages.isEmpty })
        let box = try XCTUnwrap(p.inlineImages.inOrder.first?.textBox)
        XCTAssertEqual(box.paragraphs.map(\.text), ["hello"])
        XCTAssertEqual(p.text, "before \u{FFFC} after", "the shape keeps its place in the line")
    }

    func testABoxInLineTakesTheEditTextDialogsWords() throws {
        let c = RichDocumentController(document: try inlineShapeDocument(text: true))
        let (i, id) = try shape(c)
        XCTAssertEqual(c.textBoxText(at: i, inline: id), "in")
        XCTAssertTrue(c.setTextBoxText(at: i, inline: id, "one\ntwo"))
        let back = try DocxFormat.read(try DocxFormat.write(c.document, pageSetup: .letter)).document
        let p = try XCTUnwrap(back.paragraphs.first { !$0.inlineImages.isEmpty })
        XCTAssertEqual(p.inlineImages.inOrder.first?.textBox?.paragraphs.map(\.text), ["one", "two"])
    }

    func testASelectedShapeInLineGetsShapeFormat() throws {
        let session = OfficeSession()
        session.controller.load(try inlineShapeDocument())
        let i = try XCTUnwrap(session.controller.document.paragraphs.firstIndex { !$0.inlineImages.isEmpty })
        let id = try XCTUnwrap(session.controller.document.paragraphs[i].inlineImages.keys.sorted().first)
        XCTAssertEqual(session.imageTab(at: i, inline: id), .shapeFormat)
    }

    /// Layout Options from In Line with Text to Square: the shape floats where it stood (from its own character and line),
    /// wraps square and keeps its name and look; undo puts it back in the line.
    func testAShapeInLineTakesAWrapAndFloatsWhereItStood() throws {
        WriterCharts.installHooks()
        let c = RichDocumentController(document: try inlineShapeDocument())
        let (i, id) = try shape(c)
        XCTAssertTrue(c.isInLine(at: i, inline: id))
        XCTAssertTrue(c.setPictureWrap(at: i, inline: id, .square))
        let f = try XCTUnwrap(c.document.paragraphs[i].inlineImages[id]?.float, "it floats")
        XCTAssertEqual(f.horizontalFrom, "character")
        XCTAssertEqual(f.verticalFrom, "line")
        XCTAssertTrue(f.wraps)
        XCTAssertEqual(c.pictureWrap(at: i, inline: id), .square)
        XCTAssertFalse(c.isInLine(at: i, inline: id))
        let xml = try savedBody(c.document)
        XCTAssertTrue(xml.containsSubstring("<wp:anchor") && !xml.containsSubstring("<wp:inline"), "it is written floating")
        XCTAssertTrue(xml.containsSubstring("<wp:wrapSquare"), "wrapped square")
        XCTAssertTrue(xml.containsSubstring("name=\"Rectangle 3\""), "its name goes with it")
        XCTAssertTrue(xml.containsSubstring("<a:srgbClr val=\"4472C4\"/>"), "and its fill")
        let back = try DocxFormat.read(try DocxFormat.write(c.document, pageSetup: .letter)).document
        XCTAssertNotNil(back.paragraphs.flatMap { [$0.image] + $0.inlineImages.values.map { Optional($0) } }.compactMap { $0 }.first?.float, "it reads back floating")
        c.undo()
        XCTAssertTrue(c.isInLine(at: i, inline: id), "one undo step puts it back in its line")
    }

    /// And back: In Line with Text drops its place and wrap, and it stands in its line again.
    func testAFloatingShapeGoesBackInLine() throws {
        WriterCharts.installHooks()
        let c = RichDocumentController(document: try inlineShapeDocument())
        let (i, id) = try shape(c)
        XCTAssertTrue(c.setPictureWrap(at: i, inline: id, .tight))
        XCTAssertTrue(c.setInLine(at: i, inline: id))
        XCTAssertNil(c.document.paragraphs[i].inlineImages[id]?.float)
        XCTAssertTrue(c.isInLineShape(at: i, inline: id))
        XCTAssertFalse(c.setInLine(at: i, inline: id), "already in its line")
        let xml = try savedBody(c.document)
        XCTAssertTrue(xml.containsSubstring("<wp:inline") && !xml.containsSubstring("<wp:anchor") && !xml.containsSubstring("<wp:wrapTight"), "written in its line")
        XCTAssertTrue(xml.containsSubstring("<wp:extent cx=\"914400\" cy=\"457200\"/>"), "the same size")
        let back = try DocxFormat.read(try DocxFormat.write(c.document, pageSetup: .letter)).document
        XCTAssertTrue(back.paragraphs.contains { $0.inlineImages.values.contains { $0.float == nil && $0.sourceXML?.containsSubstring("<wps:wsp") == true } }, "it reads back in its line")
    }
}
