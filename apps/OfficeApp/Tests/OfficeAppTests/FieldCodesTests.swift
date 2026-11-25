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

    func testF9UpdatesPageAndPageCount() {
        var f = CharStyle.plain; f.preservedField = "PAGE"
        var n = CharStyle.plain; n.preservedField = "NUMPAGES"
        let p = RichParagraph(text: "Page 1 of 1", runs: [Run(length: 5, style: .plain), Run(length: 1, style: f), Run(length: 4, style: .plain), Run(length: 1, style: n)])
        let c = RichDocumentController(document: RichDocument(paragraphs: [p]))
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        XCTAssertEqual(c.updateFields(pageOf: { _ in "4" }, pageCount: 9), 0)   // the caret is on no field
        c.selectAll()
        XCTAssertEqual(c.updateFields(pageOf: { _ in "4" }, pageCount: 9), 1)
        XCTAssertEqual(c.document.paragraphs[0].text, "Page 4 of 9")
        XCTAssertEqual(c.document.paragraphs[0].runs.compactMap { $0.style.preservedField }, ["PAGE", "NUMPAGES"])
        c.undo()
        XCTAssertEqual(c.document.paragraphs[0].text, "Page 1 of 1")
    }

    func testF9PageRefFollowsItsBookmark() {
        var f = CharStyle.plain; f.field = "PAGEREF target"
        var q = RichParagraph(text: "see 1", runs: [Run(length: 4, style: .plain), Run(length: 1, style: f)])
        var t = RichParagraph(text: "here", runs: [Run(length: 4, style: .plain)])
        t.bookmarks = ["Target"]
        let c = RichDocumentController(document: RichDocument(paragraphs: [q, t]))
        c.selectAll()
        c.updateFields(pageOf: { $0 == 1 ? "7" : "2" }, pageCount: 9)
        XCTAssertEqual(c.document.paragraphs[0].text, "see 7")
        q.text = ""
    }

    func testF9RefShowsTheBookmarkedText() {
        var f = CharStyle.plain; f.field = "REF target"
        let q = RichParagraph(text: "see old", runs: [Run(length: 4, style: .plain), Run(length: 3, style: f)])
        var t = RichParagraph(text: "a new text b", runs: [Run(length: 12, style: .plain)])
        t.bookmarks = ["target"]
        t.bookmarkMarkers = [RichBookmarkMarker(id: "1", name: "target", offset: 2), RichBookmarkMarker(id: "1", offset: 10)]
        let c = RichDocumentController(document: RichDocument(paragraphs: [q, t]))
        c.selectAll()
        XCTAssertEqual(c.updateFields(pageOf: { (_: Int) -> String? in nil }, pageCount: 1), 1)
        XCTAssertEqual(c.document.paragraphs[0].text, "see new text")
    }

    func testF9RefNumberGivesTheParagraphNumber() {
        var f = CharStyle.plain; f.field = "REF target \\n"
        let q = RichParagraph(text: "see x", runs: [Run(length: 4, style: .plain), Run(length: 1, style: f)])
        var a = RichParagraph(text: "one", runs: [Run(length: 3, style: .plain)])
        a.style.list = .numbered; a.style.listId = "1"
        var t = RichParagraph(text: "two", runs: [Run(length: 3, style: .plain)])
        t.style.list = .numbered; t.style.listId = "1"
        t.bookmarks = ["target"]
        let c = RichDocumentController(document: RichDocument(paragraphs: [q, a, t]))
        c.selectAll()
        XCTAssertEqual(c.updateFields(pageOf: { (_: Int) -> String? in nil }, pageCount: 1), 1)
        XCTAssertEqual(c.document.paragraphs[0].text, "see 2")
    }
}
