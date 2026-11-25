import XCTest
import Flutter
@testable import OfficeApp
@testable import OfficeText

final class WriterAccessibilityTests: XCTestCase {
    func testTextAndCaretAreFlattenedAcrossParagraphs() {
        let c = RichDocumentController(document: RichDocument(paragraphs: [
            RichParagraph(text: "Hello"), RichParagraph(text: "wörld 😀"), RichParagraph(text: "end")]))
        c.selection = RichSelection(anchor: RichPosition(paragraph: 1, offset: 1),
                                    focus: RichPosition(paragraph: 1, offset: 4))
        let r = WriterAccessibility.reading(of: c)
        XCTAssertEqual(r.text, "Hello\nwörld 😀\nend")
        // "Hello\n" is 6 units, so paragraph 1 offset 1 is 7 and offset 4 is 10.
        XCTAssertEqual(r.selection.baseOffset, 7)
        XCTAssertEqual(r.selection.extentOffset, 10)
    }
}
