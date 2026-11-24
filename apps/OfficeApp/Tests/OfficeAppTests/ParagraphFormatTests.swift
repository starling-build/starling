// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Foundation
import OfficeText
@testable import OfficeApp

/// W-PA-1: one controller call sets a paragraph's whole format, undoes in one step,
/// and survives a save.
final class ParagraphFormatTests: XCTestCase {
    func testFormatAppliesUndoesAndSurvivesSave() throws {
        let c = RichDocumentController(plainText: "one\ntwo")
        c.selectAll()
        c.setParagraphFormat(.init(alignment: .justify, indentLeft: 36, indentRight: 18,
                                   firstLineIndent: -18, spaceBefore: 6, spaceAfter: 12,
                                   lineRule: .exactly(20)))
        let s = c.document.paragraphs[1].style
        XCTAssertEqual(s.alignment, .justify)
        XCTAssertEqual(s.indentLeft, 36); XCTAssertEqual(s.firstLineIndent, -18)
        XCTAssertEqual(s.lineHeightPoints, 20); XCTAssertFalse(s.lineHeightIsMinimum)
        let back = try DocxFormat.read(DocxFormat.write(c.document, pageSetup: .letter)).document
        let b = back.paragraphs[0].style
        XCTAssertEqual(b.alignment, .justify); XCTAssertEqual(b.indentRight, 18)
        XCTAssertEqual(b.firstLineIndent, -18); XCTAssertEqual(b.spaceAfter, 12)
        XCTAssertEqual(b.lineHeightPoints, 20); XCTAssertFalse(b.lineHeightIsMinimum)
        c.setParagraphFormat(.init(lineRule: .multiple(1.5)))
        XCTAssertNil(c.document.paragraphs[0].style.lineHeightPoints)
        XCTAssertEqual(c.document.paragraphs[0].style.lineSpacing, 1.5)
        c.setParagraphFormat(.init(lineRule: .atLeast(30)))
        XCTAssertTrue(c.document.paragraphs[0].style.lineHeightIsMinimum)
        c.undo(); c.undo()
        XCTAssertEqual(c.document.paragraphs[0].style.lineHeightPoints, 20)
        c.undo()
        XCTAssertEqual(c.document.paragraphs[0].style.indentLeft, 0)
    }

    /// W-PA-3: tab stops (position, kind, leader) set through the controller undo in one step and survive a save.
    func testTabStopsApplyUndoAndSurviveSave() throws {
        let c = RichDocumentController(plainText: "a\tb")
        var ed = TabStopEditor(stops: [])
        ed.set(at: 144, kind: .right, leader: .dots)
        ed.set(at: 72, kind: .decimal, leader: .none)
        ed.set(at: 216, kind: .bar, leader: .none)
        ed.set(at: 72.2, kind: .center, leader: .dashes)   // the same stop again: replaced, not added
        XCTAssertEqual(ed.stops.map(\.position), [72.2, 144, 216])
        c.setParagraphFormat(.init(tabStops: ed.stops))
        let back = try DocxFormat.read(DocxFormat.write(c.document, pageSetup: .letter)).document.paragraphs[0].style.tabStops
        XCTAssertEqual(back.map(\.position), [72.2, 144, 216])
        XCTAssertEqual(back.map { TabKind($0) }, [.center, .right, .bar])
        XCTAssertEqual(back.map { TabLeader($0) }, [.dashes, .dots, .none])
        ed.clear(at: 144); XCTAssertEqual(ed.stops.count, 2)
        ed.clearAll(); XCTAssertTrue(ed.stops.isEmpty)
        c.setParagraphFormat(.init(tabStops: []))
        XCTAssertTrue(c.document.paragraphs[0].style.tabStops.isEmpty)
        c.undo()
        XCTAssertEqual(c.document.paragraphs[0].style.tabStops.count, 3, "one undo restores the stops")
        c.undo()
        XCTAssertTrue(c.document.paragraphs[0].style.tabStops.isEmpty)
    }
}
