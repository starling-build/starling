// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import OfficeText
@testable import OfficeApp

/// U-FR-1, Writer hook: find, replace and replace all by pattern; each replace is one undo.
final class WriterFindPatternTests: XCTestCase {
    private func texts(_ c: RichDocumentController) -> [String] { c.document.paragraphs.map { $0.text } }

    func testFindWalksForwardAndBackAndWraps() throws {
        let c = RichDocumentController(plainText: "cat dog\nbird Cat")
        let p = try TextPattern("cat", FindOptions())
        c.selection = try XCTUnwrap(c.find(p))
        XCTAssertEqual(c.selectedText, "cat")
        c.selection = try XCTUnwrap(c.find(p))
        XCTAssertEqual(c.selectedText, "Cat")
        XCTAssertEqual(c.selection.start.paragraph, 1)
        c.selection = try XCTUnwrap(c.find(p))          // wraps
        XCTAssertEqual(c.selection.start.paragraph, 0)
        c.selection = try XCTUnwrap(c.find(p, backwards: true))   // wraps back
        XCTAssertEqual(c.selection.start.paragraph, 1)
    }

    func testMatchCaseAndWholeWordNarrowTheFind() throws {
        let c = RichDocumentController(plainText: "concat Cat cat")
        let p = try TextPattern("cat", FindOptions(matchCase: true, wholeWord: true))
        XCTAssertEqual(c.countMatches(p), 1)
    }

    func testReplaceAllIsOneUndo() throws {
        let c = RichDocumentController(plainText: "a1 b22\nc333")
        let p = try TextPattern("\\d+", FindOptions(mode: .regex))
        XCTAssertEqual(c.replaceAll(p, with: "<$&>"), 3)
        XCTAssertEqual(texts(c), ["a<1> b<22>", "c<333>"])
        c.undo()
        XCTAssertEqual(texts(c), ["a1 b22", "c333"])
    }

    func testReplaceSelectionOnlyWhenTheSelectionIsAMatch() throws {
        let c = RichDocumentController(plainText: "one two one")
        let p = try TextPattern("one", FindOptions())
        c.selection = try XCTUnwrap(c.find(p))
        XCTAssertTrue(c.replaceSelection(p, with: "1"))
        XCTAssertEqual(texts(c), ["1 two one"])
        XCTAssertFalse(c.replaceSelection(p, with: "x"))   // caret now after "1", nothing selected
        c.undo()
        XCTAssertEqual(texts(c), ["one two one"])
    }
}
