import XCTest
@testable import OfficeApp
@testable import OfficeText

final class TypingAfterDeletionTests: XCTestCase {
    private func deletedAtEnd() -> RichDocumentController {
        var p = RichParagraph(text: "kept gone")
        var del = CharStyle.plain
        del.revision = RevisionMark(kind: .deleted, author: "Ann", date: "")
        p.runs = [Run(length: 5, style: .plain), Run(length: 4, style: del)]
        let c = RichDocumentController(document: RichDocument(paragraphs: [p]))
        c.moveToDocumentEnd(extend: false)
        return c
    }

    func testTextTypedAfterATrackedDeletionIsNotPartOfIt() {
        let c = deletedAtEnd()
        c.insertText("new")
        let runs = c.document.paragraphs[0].runs
        XCTAssertEqual(c.document.paragraphs[0].text, "kept gonenew")
        XCTAssertNil(runs.last?.style.revision?.kind == .deleted ? runs.last?.style.revision : nil, "typed text must not be marked deleted")
        XCTAssertEqual(runs.filter { $0.style.revision?.kind == .deleted }.map(\.length), [4])
    }
}
