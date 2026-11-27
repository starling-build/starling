import XCTest
@testable import OfficeText

/// Shift+F9 / Alt+F9: a field shows as its instruction in braces and goes back to its result.
final class FieldCodesTests: XCTestCase {
    private func make() -> RichDocumentController {
        var field = CharStyle.plain
        field.preservedField = "PAGE"
        let p = RichParagraph(text: "Page 3 of", runs: [Run(length: 5, style: .plain), Run(length: 1, style: field), Run(length: 3, style: .plain)])
        return RichDocumentController(document: RichDocument(paragraphs: [p]))
    }

    func testAllFieldsShowAndHide() {
        let c = make()
        c.toggleFieldCodes(all: true)
        XCTAssertEqual(c.document.paragraphs[0].text, "Page { PAGE } of")
        XCTAssertTrue(c.showsFieldCodes)
        c.toggleFieldCodes(all: true)
        XCTAssertEqual(c.document.paragraphs[0].text, "Page 3 of")
        XCTAssertEqual(c.document.paragraphs[0].runs.compactMap { $0.style.preservedField }, ["PAGE"])
    }

    func testEditedCodeIsWrittenBack() {
        let c = make()
        c.toggleFieldCodes(all: true)
        let t = c.document.paragraphs[0].text
        let at = t.utf16.count - " } of".utf16.count
        c.moveTo(RichPosition(paragraph: 0, offset: at), extend: false)
        c.insertText("S")
        c.toggleFieldCodes(all: true)
        XCTAssertEqual(c.document.paragraphs[0].runs.compactMap { $0.style.preservedField?.trimmingWhitespace(newlines: true) }, ["PAGES"])
    }

    func testShowingIsOneUndoStep() {
        let c = make()
        c.toggleFieldCodes(all: true)
        c.undo()
        XCTAssertEqual(c.document.paragraphs[0].text, "Page 3 of")
    }
}
