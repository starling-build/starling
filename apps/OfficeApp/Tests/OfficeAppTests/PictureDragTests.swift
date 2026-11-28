// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp
@testable import OfficeText

/// W-OB-1/5: a picture or object that stands in the text (alone in its paragraph, or In Line with Text) moves in the text
/// when dragged, as Word moves it.
final class PictureDragTests: XCTestCase {
    private let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
    private let obj = RichParagraph.inlineImageCharacter

    /// The editor on `c` in a window, with the selected drawing's box in window coordinates.
    private func editor(_ c: RichDocumentController, select: () -> Void) throws -> (WidgetTester, Rect) {
        var rect: Rect?
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: SizedBox(width: 1200, height: 800, child: RichEditable(
            controller: c, onBoxRect: { rect = $0 })), title: "T"), size: Size(1280, 900))
        select()
        for _ in 0 ..< 3 { ui.pump(); RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        let box = try XCTUnwrap(ui.elements().first { $0.widget is RichEditable }?.findRenderObject() as? RenderBox)
        let r = try XCTUnwrap(rect)
        let topLeft = box.localToGlobal(Offset(r.left, r.top))
        return (ui, Rect.fromLTWH(topLeft.dx, topLeft.dy, r.width, r.height))
    }

    func testDraggingAPictureAloneInItsParagraphMovesItIntoTheTextBelow() throws {
        let c = RichDocumentController(document: RichDocument(paragraphs: [
            RichParagraph(text: "one two three"), RichParagraph(image: ImageAttachment(data: png, width: 100, height: 50)),
            RichParagraph(text: "six seven eight nine")]))
        let (ui, r) = try editor(c) { c.selectImage(at: 1) }
        defer { ui.dispose() }
        let before = c.document
        ui.click(at: r.center, kind: .mouse)
        ui.pump()
        XCTAssertEqual(c.document, before, "a press that does not travel only clicks")
        // Dropped a little into the line below it, near its start.
        ui.drag(from: r.center, to: Offset(r.left + 20, r.bottom + 30), kind: .mouse)
        ui.pump(); RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let p = c.document.paragraphs
        XCTAssertEqual(p.count, 3, "its paragraph stays")
        XCTAssertNil(p[1].image)
        XCTAssertEqual(p[1].text, "", "left empty")
        XCTAssertTrue(p[2].text.containsSubstring(obj), "it stands in the line it was dropped on: \(p[2].text)")
        XCTAssertEqual(p[2].text.replacingOccurrences(of: obj, with: ""), "six seven eight nine")
        XCTAssertEqual(p[2].inlineImages.count, 1)
        XCTAssertEqual(c.selectedInlineImage?.id, p[2].inlineImages.keys.first, "the moved picture stays selected")
        let saved = try DocxFormat.read(try DocxFormat.write(c.document, pageSetup: .letter)).document
        XCTAssertEqual(saved.paragraphs[2].inlineImages.count, 1, "it saves in its new line")
        c.undo()
        XCTAssertEqual(c.document, before, "one undo puts it back")
    }

    func testAPictureAloneInItsParagraphDoesNotDropOnItself() {
        let c = RichDocumentController(document: RichDocument(paragraphs: [
            RichParagraph(text: "one"), RichParagraph(image: ImageAttachment(data: png, width: 100, height: 50)), RichParagraph(text: "two")]))
        XCTAssertFalse(c.movePictureParagraph(at: 1, to: RichPosition(paragraph: 1, offset: 0)))
        XCTAssertFalse(c.movePictureParagraph(at: 0, to: RichPosition(paragraph: 2, offset: 0)), "no picture there")
        XCTAssertTrue(c.movePictureParagraph(at: 1, to: RichPosition(paragraph: 0, offset: 3)))
        XCTAssertEqual(c.document.paragraphs[0].text, "one" + obj)
    }

    func testAPictureInLineDraggedToAnotherParagraphTakesItsImageAlong() throws {
        let image = ImageAttachment(data: png, width: 40, height: 20)
        var first = RichParagraph(text: "ab" + obj + "cd")
        var char = CharStyle.plain
        char.inlineImage = image.id
        first.runs = [Run(length: 2), Run(length: 1, style: char), Run(length: 2)]
        first.inlineImages[image.id] = image
        let c = RichDocumentController(document: RichDocument(paragraphs: [first, RichParagraph(text: "efgh")]))
        let before = c.document
        let (ui, r) = try editor(c) { c.selectInlineImage(in: 0, id: image.id) }
        defer { ui.dispose() }
        // Dropped on the next line.
        ui.drag(from: r.center, to: Offset(r.center.dx, r.bottom + 14), kind: .mouse)
        ui.pump(); RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let p = c.document.paragraphs
        XCTAssertEqual(p[0].text, "abcd")
        XCTAssertTrue(p[0].inlineImages.isEmpty)
        XCTAssertTrue(p[1].text.containsSubstring(obj), "moved to the next line: \(p[1].text)")
        XCTAssertEqual(p[1].inlineImages[image.id]?.data, png, "with its picture")
        c.undo()
        XCTAssertEqual(c.document, before)
    }

    /// A picture placed by alignment (centred on the margin, top of the margin) is placed by offset once dragged, as Word
    /// saves it: from the same frames, at the offset where it stood plus the drag.
    func testDraggingAnAlignedPictureMakesItsPositionAnOffset() throws {
        let base = try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "text"), RichParagraph(image: ImageAttachment(data: png, width: 100, height: 50))]), pageSetup: .letter)
        var entries = try Zip.read(base)
        let di = try XCTUnwrap(entries.firstIndex { $0.name == "word/document.xml" })
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let start = try XCTUnwrap(xml.rangeOfSubstring("<w:drawing>")), end = try XCTUnwrap(xml.rangeOfSubstring("</w:drawing>"))
        let embed = try XCTUnwrap(xml.rangeOfSubstring("r:embed=\""))
        let rid = String(xml[embed.upperBound...].prefix { $0 != "\"" })
        xml.replaceSubrange(start.lowerBound ..< end.lowerBound, with: "<w:drawing><wp:anchor distT=\"0\" distB=\"0\" distL=\"114300\" distR=\"114300\" simplePos=\"0\" relativeHeight=\"1\" behindDoc=\"0\" locked=\"0\" layoutInCell=\"1\" allowOverlap=\"1\">"
            + "<wp:simplePos x=\"0\" y=\"0\"/><wp:positionH relativeFrom=\"margin\"><wp:align>center</wp:align></wp:positionH>"
            + "<wp:positionV relativeFrom=\"margin\"><wp:align>top</wp:align></wp:positionV><wp:extent cx=\"1270000\" cy=\"635000\"/>"
            + "<wp:wrapSquare wrapText=\"bothSides\"/><wp:docPr id=\"5\" name=\"Picture 5\"/>"
            + "<a:graphic xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\"><a:graphicData uri=\"http://schemas.openxmlformats.org/drawingml/2006/picture\">"
            + "<pic:pic xmlns:pic=\"http://schemas.openxmlformats.org/drawingml/2006/picture\"><pic:nvPicPr><pic:cNvPr id=\"0\" name=\"p\"/><pic:cNvPicPr/></pic:nvPicPr>"
            + "<pic:blipFill><a:blip r:embed=\"\(rid)\"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>"
            + "<pic:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"1270000\" cy=\"635000\"/></a:xfrm><a:prstGeom prst=\"rect\"/></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:anchor>")
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(1280, 800))
        defer { ui.dispose() }
        let c = try XCTUnwrap(ui.state(OfficeShellState.self)).session.controller
        c.load(try DocxFormat.read(try Zip.write(entries)).document)
        ui.pump()
        let i = try XCTUnwrap(c.document.paragraphs.firstIndex { $0.image?.float != nil })
        XCTAssertNotNil(c.document.paragraphs[i].image?.float?.horizontalAlign)
        let before = c.document
        let probe = try XCTUnwrap(c.pictureCornerProbe)
        let was = try XCTUnwrap(probe(i, nil))
        XCTAssertTrue(c.movePicture(at: i, dx: 10, dy: 20))
        let now = try XCTUnwrap(probe(i, nil))
        XCTAssertEqual(now.x, was.x + 10, accuracy: 0.01, "drawn where it was dropped")
        XCTAssertEqual(now.y, was.y + 20, accuracy: 0.01)
        XCTAssertGreaterThan(was.x, 100, "it was drawn centred, not at the margin: \(was)")
        let f = try XCTUnwrap(c.document.paragraphs[i].image?.float)
        XCTAssertNil(f.horizontalAlign)
        XCTAssertNil(f.verticalAlign)
        let saved = try XCTUnwrap(c.document.paragraphs[i].image?.sourceXML)
        XCTAssertTrue(saved.containsSubstring("<wp:positionH relativeFrom=\"margin\"><wp:posOffset>"), "same frame, by offset: \(saved.prefix(400))")
        XCTAssertTrue(saved.containsSubstring("<wp:positionV relativeFrom=\"margin\"><wp:posOffset>\(20 * 12700)</wp:posOffset>"))
        XCTAssertFalse(saved.containsSubstring("<wp:align>"))
        let back = try DocxFormat.read(try DocxFormat.write(c.document, pageSetup: .letter)).document
        XCTAssertEqual(try XCTUnwrap(back.paragraphs[i].image?.float).x, f.x, accuracy: 0.01, "kept by a save")
        c.undo()
        XCTAssertEqual(c.document, before, "one undo puts it back aligned")
    }
}
