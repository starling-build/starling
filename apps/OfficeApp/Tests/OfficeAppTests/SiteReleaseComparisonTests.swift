// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
@testable import OfficeApp

#if !os(WASI)
final class SiteReleaseComparisonTests: XCTestCase {
    private func page(_ entries: [(UInt32, String)]) -> SitePage {
        SitePage(document: RichDocument(paragraphs: entries.map { id, text in
            var paragraph = RichParagraph(text: text)
            paragraph.id = id
            return paragraph
        }), pageSetup: .letter)
    }

    private func compare(_ old: SitePage?, _ new: SitePage?) -> SiteReleaseComparison {
        SiteReleaseComparison(previous: old, current: new,
                              previousTitle: old == nil ? nil : "Chapter", currentTitle: new == nil ? nil : "Chapter")
    }

    func testEditsAdditionsRemovalsAndMovesKeepBothVersionsUntouched() {
        let old = page([(11, "Opening"), (22, "Before"), (33, "Cut this")])
        let new = page([(22, "After 👩🏽‍🚀"), (11, "Opening"), (44, "New ending")])
        let result = compare(old, new)
        XCTAssertEqual(result.passages.map(\.kind), [.edited, .added, .removed])
        XCTAssertEqual(result.passages.map(\.before), ["Before", nil, "Cut this"])
        XCTAssertEqual(result.passages.map(\.after), ["After 👩🏽‍🚀", "New ending", nil])
        XCTAssertEqual(result.passages.map(\.paragraphID), [22, 44, nil])
        XCTAssertEqual(result.passages.map(\.oldNumber), [2, nil, 3])
        XCTAssertEqual(result.passages.map(\.newNumber), [1, 3, nil])
        XCTAssertTrue(result.orderChanged)
        XCTAssertEqual(old.document.paragraphs.map(\.text), ["Opening", "Before", "Cut this"])
        XCTAssertEqual(new.document.paragraphs.map(\.id), [22, 11, 44])
    }

    func testInsertionDoesNotReportEveryFollowingParagraphAsMoved() {
        let result = compare(page([(11, "First"), (22, "Second")]),
                             page([(33, "Inserted"), (11, "First"), (22, "Second")]))
        XCTAssertFalse(result.orderChanged)
        XCTAssertEqual(result.passages.map(\.kind), [.added])
    }

    func testUnchangedLegacyParagraphsDoNotHideDocumentLevelChanges() {
        let old = page([(0, ""), (0, "Repeated"), (0, "Repeated")])
        var new = old
        new.document.footer = "New footer"
        let result = compare(old, new)
        XCTAssertTrue(result.passages.isEmpty)
        XCTAssertFalse(result.orderChanged)
        XCTAssertTrue(result.documentDetailsChanged)
    }

    func testReplacedIdentitiesCanMatchOnlyUniqueExactText() {
        let result = compare(page([(11, "First"), (22, "Second")]), page([(0, "Second"), (0, "First")]))
        XCTAssertTrue(result.orderChanged)
        XCTAssertTrue(result.passages.isEmpty)
        let edited = compare(page([(11, "Before")]), page([(0, "After")]))
        XCTAssertEqual(edited.passages.map(\.kind), [.added, .removed])
        XCTAssertTrue(edited.passages.allSatisfy { $0.paragraphID == nil })
    }

    func testAmbiguousIdentitiesAndRepeatedTextNeverSelectAnArbitraryPassage() {
        let result = compare(page([(11, "Repeated"), (22, "Repeated")]),
                             page([(11, "Repeated"), (11, "Repeated")]))
        XCTAssertEqual(result.passages.map(\.kind), [.added, .added, .removed, .removed])
        XCTAssertTrue(result.passages.allSatisfy { $0.paragraphID == nil })
        let changed = compare(page([(11, "Unique")]), page([(12, "Unique"), (12, "New")]))
        XCTAssertEqual(changed.passages.map(\.kind), [.added])
        XCTAssertNil(changed.passages[0].paragraphID)
    }

    func testLinksFormattingHeadersAndLayoutAreNotMistakenForUnchangedText() {
        let old = page([(11, "Read more"), (22, "Important")])
        var new = old
        new.document.paragraphs[0].runs[0].style.link = "https://example.org/updated"
        new.document.paragraphs[1].applyStyle(0..<9) { $0.bold = true }
        new.document.header = "Revised edition"
        new.pageSetup?.marginLeft += 10
        let result = compare(old, new)
        XCTAssertEqual(result.passages.map(\.kind), [.details, .details])
        XCTAssertTrue(result.documentDetailsChanged)
        XCTAssertTrue(result.pageSetupChanged)
        XCTAssertFalse(result.orderChanged)
        XCTAssertEqual(result.passages[0].before, result.passages[0].after)
    }

    func testNewRemovedAndEmptyParagraphsStayDistinct() {
        let document = page([(11, ""), (22, "Text")])
        let added = compare(nil, document)
        XCTAssertNil(added.previousTitle)
        XCTAssertEqual(added.passages.map(\.kind), [.added, .added])
        XCTAssertEqual(added.passages[0].after, "")
        XCTAssertNil(added.passages[0].before)
        let removed = compare(document, nil)
        XCTAssertNil(removed.currentTitle)
        XCTAssertEqual(removed.passages.map(\.kind), [.removed, .removed])
        XCTAssertEqual(removed.passages[0].before, "")
        XCTAssertTrue(removed.passages.allSatisfy { $0.paragraphID == nil })
    }

    func testLargeManuscriptKeepsSmallCorrectionSmall() {
        let old = page((1...10_000).map { (UInt32($0), "Paragraph \($0)") })
        var new = old
        new.document.paragraphs[5_000] = page([(5_001, "Corrected passage")]).document.paragraphs[0]
        let result = compare(old, new)
        XCTAssertEqual(result.passages.count, 1)
        XCTAssertEqual(result.passages[0].kind, .edited)
        XCTAssertEqual(result.passages[0].oldNumber, 5_001)
        XCTAssertFalse(result.orderChanged)
        XCTAssertFalse(result.documentDetailsChanged)
    }
}
#endif
