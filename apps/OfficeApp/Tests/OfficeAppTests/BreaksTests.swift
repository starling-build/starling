import XCTest
@testable import OfficeApp
@testable import OfficeText

/// W-PA-6: Layout > Breaks and Ctrl+Shift+Enter put a column break at the caret, held and saved as Word's own.
final class BreaksTests: XCTestCase {
    func testAColumnBreakSplitsTheParagraphAndIsOneUndoStep() {
        let c = RichDocumentController(document: RichDocument(plainText: "leftright"))
        c.selection = RichSelection(caret: RichPosition(paragraph: 0, offset: 4))
        c.insertColumnBreak()
        XCTAssertEqual(c.document.paragraphs.map(\.text), ["left", "right"])
        let s = c.document.paragraphs[1].style
        XCTAssertTrue(s.columnBreak && s.pageBreakBefore && s.breakEndsPrevious && !s.pageBreakInline)
        XCTAssertEqual(c.selection.focus, RichPosition(paragraph: 1, offset: 0))
        c.undo()
        XCTAssertEqual(c.document.paragraphs.map(\.text), ["leftright"])
    }

    func testTheSavedColumnBreakIsWordsAndReadsBack() throws {
        let c = RichDocumentController(document: RichDocument(plainText: "leftright"))
        c.selection = RichSelection(caret: RichPosition(paragraph: 0, offset: 4))
        c.insertColumnBreak()
        var setup = PageSetup.letter; setup.columns = 2
        let data = try DocxFormat.write(c.document, pageSetup: setup)
        let body = String(decoding: try XCTUnwrap(try Zip.read(data).first { $0.name == "word/document.xml" }).data, as: UTF8.self)
        let br = try XCTUnwrap(body.rangeOfSubstring("<w:br w:type=\"column\"/>"), "a Word column break")
        let left = try XCTUnwrap(body.rangeOfSubstring(">left<")), right = try XCTUnwrap(body.rangeOfSubstring(">right<"))
        XCTAssertTrue(left.upperBound < br.lowerBound && br.upperBound < right.lowerBound)
        XCTAssertEqual(body[left.upperBound ..< right.lowerBound].components(separatedBy: "<w:p>").count
                       + body[left.upperBound ..< right.lowerBound].components(separatedBy: "<w:p ").count, 3, "it ends the first paragraph")
        let back = try DocxFormat.read(data).document.paragraphs
        XCTAssertEqual(back.map(\.text), ["left", "right"])
        XCTAssertTrue(back[1].style.columnBreak && back[1].style.pageBreakBefore)
    }

    func testTheTextAfterAColumnBreakStartsTheNextColumn() {
        let c = RichDocumentController(document: RichDocument(plainText: "leftright"))
        c.selection = RichSelection(caret: RichPosition(paragraph: 0, offset: 4))
        c.insertColumnBreak()
        let theme = RichTextTheme(fontFamily: OfficeFonts.serif)
        theme.wordRules = true
        let layout = RichLayout(theme: theme, paragraphCount: c.document.paragraphs.count)
        var setup = PageSetup.letter; setup.columns = 2
        layout.pageSetup = setup
        layout.width = setup.columnWidth * theme.pixelsPerPoint
        layout.ensureLaidOut(c.document)
        let slot = { (k: Int) in layout.pieces.firstIndex { $0.contains { $0.paragraph == k } } }
        XCTAssertEqual(slot(0), 0)
        XCTAssertEqual(slot(1), 1, "the second column of the first page")
    }
}
