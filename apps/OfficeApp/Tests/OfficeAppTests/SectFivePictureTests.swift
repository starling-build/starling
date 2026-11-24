// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

final class SectFivePictureTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        _ = TestText.icuLoaded
        _ = OfficeFonts.register()
    }

    /// Lab sect5 (Word's print): a picture alone in the paragraph after a
    /// right-aligned floating table, narrower than the room at the table's
    /// left, stands there level with the table's top, not under its rows.
    func testAPictureAfterAFloatingTableStandsBesideItInTheRoomAtItsLeft() throws {
        RichTextTheme.wordWindowsPages = true
        defer { RichTextTheme.wordWindowsPages = false }
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!
        func top(pictureWidth: Double) -> (picture: Double, tableBottom: Double) {
            var cell = RichParagraph(text: "cell")
            cell.cell = CellRef(table: "t", row: 0, column: 0)
            var cell2 = RichParagraph(text: "cell two")
            cell2.cell = CellRef(table: "t", row: 1, column: 0)
            var pic = RichParagraph(text: "")
            pic.image = ImageAttachment(data: png, width: pictureWidth, height: 60)
            var doc = RichDocument(paragraphs: [RichParagraph(text: "before"), cell, cell2, pic, RichParagraph(text: "after")])
            doc.tableColumns["t"] = [300]
            var ts = TableStyle()
            ts.floatsOverText = true
            ts.floatOffsetY = 18
            ts.alignment = .right
            ts.keptPosition = "<w:tblpPr w:horzAnchor=\"margin\" w:tblpXSpec=\"right\" w:tblpY=\"360\"/>"
            doc.tableStyles["t"] = ts
            let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
            theme.wordRules = true
            let layout = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
            layout.pageSetup = .letter
            layout.width = PageSetup.letter.width * theme.pixelsPerPoint
            layout.ensureLaidOut(doc)
            let px = theme.pixelsPerPoint
            let pictureY = layout.pieces[0].first { $0.paragraph == 3 }?.pageY ?? -1
            let rowY = layout.pieces[0].filter { $0.paragraph == 2 }.map(\.pageY).max() ?? 0
            return (pictureY / px, (rowY + (layout.rowRect(2)?.height ?? 0)) / px)
        }
        let narrow = top(pictureWidth: 100)
        let wide = top(pictureWidth: 400); _ = 0
        XCTAssertLessThan(narrow.picture, narrow.tableBottom - 10, "the picture stands level with the table")
        XCTAssertGreaterThanOrEqual(wide.picture, wide.tableBottom - 0.5, "one that does not fit goes under it")
    }
    /// Lab sect5 (Word's print): the empty paragraph that carries the break into a new continuous section is
    /// not the anchor of the floating table that opens it: the table's offset hangs from the top of the last
    /// line before that paragraph (17.95pt under it), not from under the paragraph before it.
    func testAFloatingTableOpeningAContinuousSectionHangsFromTheLastLineBeforeTheBreak() throws {
        RichTextTheme.wordWindowsPages = true
        defer { RichTextTheme.wordWindowsPages = false }
        func run(_ withBreak: Bool) -> (table: Double, lastLineTop: Double) {
            var bullet = RichParagraph(text: String(repeating: "word ", count: 120))
            bullet.style.spaceAfter = 10
            var brk = RichParagraph(text: "")
            if withBreak {
                brk.style.sectionXML = "<w:sectPr><w:pgSz w:w=\"12240\" w:h=\"15840\"/></w:sectPr>"
                brk.style.sectionBreaksPage = false
            }
            var cell = RichParagraph(text: "cell")
            cell.cell = CellRef(table: "t", row: 0, column: 0)
            var doc = RichDocument(paragraphs: [bullet, brk, cell, RichParagraph(text: "after")])
            doc.tableColumns["t"] = [200]
            var ts = TableStyle()
            ts.floatsOverText = true
            ts.floatOffsetY = 17.95
            ts.alignment = .right
            ts.keptPosition = "<w:tblpPr w:horzAnchor=\"margin\" w:tblpXSpec=\"right\" w:tblpY=\"359\"/>"
            doc.tableStyles["t"] = ts
            let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
            theme.wordRules = true
            let layout = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
            layout.pageSetup = .letter
            layout.width = PageSetup.letter.width * theme.pixelsPerPoint
            layout.ensureLaidOut(doc)
            let px = theme.pixelsPerPoint
            let rowY = layout.pieces[0].first { $0.paragraph == 2 }?.pageY ?? -1
            return (rowY / px, 0)
        }
        let broken = run(true)
        XCTAssertGreaterThan(run(false).table, broken.table + 10, "with no break the paragraph is its anchor, so the table sits lower")
    }

    /// Lab sect5/tblwrap (Word's print): the paragraph just before that floating table is broken again where its last line
    /// reaches the table's left edge, so it takes a line more than it does with no table; it is never shorter.
    func testTheParagraphBeforeASectionOpeningFloatingTableWrapsRoundIt() throws {
        RichTextTheme.wordWindowsPages = true
        defer { RichTextTheme.wordWindowsPages = false }
        func height(words: Int, table: Bool) -> Double {
            var bullet = RichParagraph(text: String(repeating: "word ", count: words))
            bullet.style.alignment = .justify
            bullet.style.spaceAfter = 0
            var brk = RichParagraph(text: "")
            brk.style.sectionXML = "<w:sectPr><w:pgSz w:w=\"12240\" w:h=\"15840\"/></w:sectPr>"
            brk.style.sectionBreaksPage = false
            var cell = RichParagraph(text: "cell")
            cell.cell = CellRef(table: "t", row: 0, column: 0)
            var doc = RichDocument(paragraphs: table ? [bullet, brk, cell, RichParagraph(text: "after")] : [bullet, brk, RichParagraph(text: "after")])
            doc.tableColumns["t"] = [200]
            var ts = TableStyle()
            ts.floatsOverText = true
            ts.floatOffsetY = 17.95
            ts.alignment = .right
            ts.keptPosition = "<w:tblpPr w:leftFromText=\"141\" w:rightFromText=\"141\" w:horzAnchor=\"margin\" w:tblpXSpec=\"right\" w:tblpY=\"359\"/>"
            doc.tableStyles["t"] = ts
            let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
            theme.wordRules = true
            let layout = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
            layout.pageSetup = .letter
            layout.width = PageSetup.letter.width * theme.pixelsPerPoint
            layout.ensureLaidOut(doc)
            let p = layout.pieces[0].first { $0.paragraph == 0 }
            return ((p?.flowBottom ?? 0) - (p?.flowTop ?? 0)) / theme.pixelsPerPoint
        }
        var longer = false
        for words in 100 ... 140 {
            let with = height(words: words, table: true), without = height(words: words, table: false)
            XCTAssertGreaterThanOrEqual(with, without - 0.01)
            if with > without + 5 { longer = true }
        }
        XCTAssertTrue(longer, "some last line reaches the table's edge and is broken before it")
    }
}
