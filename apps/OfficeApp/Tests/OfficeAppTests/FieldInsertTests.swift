import XCTest
@testable import OfficeApp
@testable import OfficeText

/// W-FD-1: insert a field at the caret, bring fields up to date, save and read back.
final class FieldInsertTests: XCTestCase {
    private func controller(_ text: String) -> RichDocumentController {
        let c = RichDocumentController()
        c.load(RichDocument(paragraphs: [RichParagraph(text: text)]))
        return c
    }

    func testEnglishNamesInADatePicture() {
        let d = FieldClock(year: 2026, month: 11, day: 25, hour: 14, minute: 5, second: 9)
        XCTAssertEqual(d.format(picture: "dddd, MMMM d, yyyy", english: true), "Wednesday, November 25, 2026")
        XCTAssertEqual(d.format(picture: "ddd d MMM yy", english: true), "Wed 25 Nov 26")
        XCTAssertNil(d.format(picture: "MMMM d"), "names need the app's English")
    }

    func testInsertedFieldIsOneRunSetAndOneUndoStep() throws {
        let c = controller("Today is .")
        c.moveTo(RichPosition(paragraph: 0, offset: 9), extend: false)
        c.insertField("DATE \\@ \"d MMMM yyyy\"", result: "25 November 2026")
        XCTAssertEqual(c.document.paragraphs[0].text, "Today is 25 November 2026.")
        let spans = c.fieldSpans()
        XCTAssertEqual(spans.count, 1)
        XCTAssertEqual(spans[0].instruction, "DATE \\@ \"d MMMM yyyy\"")
        XCTAssertEqual(spans[0].offset, 9)
        XCTAssertEqual(c.selection.focus.offset, 25)
        c.undo()
        XCTAssertEqual(c.document.paragraphs[0].text, "Today is .")
        XCTAssertTrue(c.fieldSpans().isEmpty)
    }

    func testUpdateRewritesOnlyChangedFieldsInOneStep() throws {
        let c = controller("A  B  C")
        c.moveTo(RichPosition(paragraph: 0, offset: 5), extend: false)
        c.insertField("AUTHOR", result: "Ann")
        c.moveTo(RichPosition(paragraph: 0, offset: 2), extend: false)
        c.insertField("DATE \\@ \"yyyy\"", result: "2020")
        let n = c.updateFields { instr, shown in instr.hasPrefix("DATE") ? "2026" : shown }
        XCTAssertEqual(n, 1)
        XCTAssertEqual(c.document.paragraphs[0].text, "A 2026 B Ann C")
        XCTAssertEqual(c.fieldSpans().map(\.shown), ["2026", "Ann"])
        c.undo()
        XCTAssertEqual(c.document.paragraphs[0].text, "A 2020 B Ann C")
    }

    func testFieldSurvivesSaveAndReopen() throws {
        let c = controller("Hello ")
        c.moveTo(RichPosition(paragraph: 0, offset: 6), extend: false)
        c.insertField("AUTHOR", result: "Ann")
        let bytes = try DocxFormat.write(c.document, pageSetup: .letter)
        let part = try XCTUnwrap(Zip.read(bytes).first { $0.name == "word/document.xml" })
        let xml = String(decoding: part.data, as: UTF8.self)
        XCTAssertTrue(xml.contains("<w:instrText xml:space=\"preserve\"> AUTHOR </w:instrText>"))
        let back = RichDocumentController()
        back.load(try DocxFormat.read(bytes).document)
        XCTAssertEqual(back.fieldSpans().map(\.instruction), ["AUTHOR"])
        XCTAssertEqual(back.document.paragraphs[0].text, "Hello Ann")
    }

    func testTypingAfterAFieldIsNotPartOfIt() {
        let c = controller("")
        c.insertField("AUTHOR", result: "Ann")
        c.insertText(" wrote this")
        c.insertParagraphBreak()
        c.insertText("Next")
        XCTAssertEqual(c.fieldSpans().count, 1)
        XCTAssertEqual(c.fieldSpans()[0].shown, "Ann")
        XCTAssertEqual(c.document.paragraphs[1].text, "Next")
        // Inside the result, typing stays in the field.
        c.moveTo(RichPosition(paragraph: 0, offset: 1), extend: false)
        c.insertText("x")
        XCTAssertEqual(c.fieldSpans()[0].shown, "Axnn")
    }
}
