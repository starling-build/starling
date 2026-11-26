import XCTest
import Flutter
import FlutterSwiftBridge
import OfficeText
@testable import OfficeApp

/// A text box's outline colour, picked on the ribbon, survives a save and a reopen.
final class BoxOutlineRoundTripTests: XCTestCase {
    func testARedBoxOutlineComesBackRed() throws {
        let c = RichDocumentController(document: RichDocument(paragraphs: [RichParagraph(text: "a")]))
        c.insertImage(try XCTUnwrap(TextBoxInsert.make(text: "one")))
        let i = try XCTUnwrap(c.document.paragraphs.firstIndex { $0.image?.textBox != nil })
        XCTAssertTrue(c.setShapeOutline(at: i, Color(0xFFCC0000)))
        XCTAssertEqual(c.document.paragraphs[i].image?.outline?.color?.value, 0xFFCC0000, "the box in memory is red")
        let back = try DocxFormat.read(try DocxFormat.write(c.document, pageSetup: .letter)).document
        let box = try XCTUnwrap(back.paragraphs.compactMap(\.image).first { $0.textBox != nil })
        XCTAssertTrue(box.sourceXML?.containsSubstring("CC0000") == true, "the saved box carries the red line")
        XCTAssertEqual(box.outline?.color?.value, 0xFFCC0000, "the reopened box is red")
    }

    func testAThemeOutlineComesBackInItsColour() throws {
        let c = RichDocumentController(document: RichDocument(paragraphs: [RichParagraph(text: "a")]))
        c.insertImage(try XCTUnwrap(TextBoxInsert.make(text: "one")))
        let i = try XCTUnwrap(c.document.paragraphs.firstIndex { $0.image?.textBox != nil })
        XCTAssertTrue(c.setShapeOutline(at: i, Color(0xFFC00000), theme: (slot: 5, lumMod: 75, lumOff: 0)))
        let back = try DocxFormat.read(try DocxFormat.write(c.document, pageSetup: .letter)).document
        let box = try XCTUnwrap(back.paragraphs.compactMap(\.image).first { $0.textBox != nil })
        XCTAssertTrue(box.sourceXML?.containsSubstring("<a:schemeClr val=\"accent2\"><a:lumMod val=\"75000\"/>") == true, "the line stays linked to its theme slot")
        XCTAssertEqual(box.outline?.color?.value, 0xFFC55A11, "and reopens in that slot's shade (Office accent 2, 25% darker), not black")
    }
}
