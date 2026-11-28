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
}
