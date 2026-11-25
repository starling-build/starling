import XCTest
@testable import OfficeApp
@testable import OfficeText

final class FieldShadeTests: XCTestCase {
    func testCaretInsideAFieldGivesTheFieldsRange() {
        var inField = CharStyle.plain
        inField.preservedField = "TITLE"
        let p = RichParagraph(text: "ab12cd", runs: [Run(length: 2, style: .plain), Run(length: 2, style: inField), Run(length: 2, style: .plain)])
        let c = RichDocumentController(document: RichDocument(paragraphs: [p]))
        c.moveTo(RichPosition(paragraph: 0, offset: 3), extend: false)
        let r = c.fieldRangeAtCaret()
        XCTAssertEqual(r?.anchor.offset, 2)
        XCTAssertEqual(r?.focus.offset, 4)
        c.moveTo(RichPosition(paragraph: 0, offset: 1), extend: false)
        XCTAssertNil(c.fieldRangeAtCaret())
        c.moveTo(RichPosition(paragraph: 0, offset: 2), extend: false)
        XCTAssertNil(c.fieldRangeAtCaret())
    }
}
