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
    /// ja-caad796afb (Word's print): the line that carries only anchored shapes, after a centred floating table
    /// raised above it, stands level with the table's top plus the raise, not under the table.
    func testAnAnchorLineAfterACentredRaisedTableStandsBesideIt() throws {
        RichTextTheme.wordWindowsPages = true
        defer { RichTextTheme.wordWindowsPages = false }
        var cell = RichParagraph(text: "cell")
        cell.cell = CellRef(table: "t", row: 0, column: 0)
        var cell2 = RichParagraph(text: "cell two")
        cell2.cell = CellRef(table: "t", row: 1, column: 0)
        var anchor = RichParagraph(text: "\u{FFFC}")
        var shape = ImageAttachment(data: Data(), width: 50, height: 50)
        shape.sourceXML = "<wp:anchor/>"
        anchor.inlineImages = ["0": shape]
        var doc = RichDocument(paragraphs: [cell, cell2, anchor, RichParagraph(text: "after")])
        doc.tableColumns["t"] = [200]
        var ts = TableStyle()
        ts.floatsOverText = true
        ts.floatRaiseY = 30
        ts.keptPosition = "<w:tblpPr w:vertAnchor=\"text\" w:tblpXSpec=\"center\" w:tblpY=\"-600\"/>"
        doc.tableStyles["t"] = ts
        let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
        theme.wordRules = true
        let layout = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
        layout.pageSetup = .letter
        layout.width = PageSetup.letter.width * theme.pixelsPerPoint
        layout.ensureLaidOut(doc)
        let px = theme.pixelsPerPoint
        let rowBottom = ((layout.pieces[0].filter { $0.paragraph == 1 }.map(\.pageY).max() ?? 0) + (layout.rowRect(1)?.height ?? 0)) / px
        let anchorY = (layout.pieces[0].first { $0.paragraph == 2 }?.pageY ?? 9999) / px
        XCTAssertLessThan(anchorY, rowBottom - 5, "the anchor line stands beside the table")
    }
    /// sa1 8b5747ec (Word's print): a square picture anchored in an otherwise empty paragraph, a table floating by the
    /// text raised a few points over the paragraph after it: the paragraph stays where it is, with the picture at it,
    /// not set under the table (ours put the picture 87pt too low, under the table).
    func testAParagraphOfOnlyASquarePictureStaysAboveARaisedFloatingTable() throws {
        RichTextTheme.wordWindowsPages = true
        defer { RichTextTheme.wordWindowsPages = false }
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!
        var pic = RichParagraph(text: "")
        var image = ImageAttachment(data: png, width: 200, height: 115)
        var float = ImageFloat()
        float.wraps = true
        float.horizontalFrom = "column"
        float.verticalFrom = "paragraph"
        float.x = 209
        float.y = 1.1
        image.float = float
        pic.image = image
        var cell = RichParagraph(text: "cell")
        cell.cell = CellRef(table: "t", row: 0, column: 0)
        var cell2 = RichParagraph(text: "cell two")
        cell2.cell = CellRef(table: "t", row: 1, column: 0)
        var doc = RichDocument(paragraphs: [RichParagraph(text: "before"), pic, cell, cell2, RichParagraph(text: "after")])
        doc.tableColumns["t"] = [120]
        var ts = TableStyle()
        ts.floatsOverText = true
        ts.floatRaiseY = 3.4
        ts.keptPosition = "<w:tblpPr w:leftFromText=\"141\" w:rightFromText=\"141\" w:vertAnchor=\"text\" w:horzAnchor=\"page\" w:tblpX=\"2834\" w:tblpY=\"-68\"/>"
        doc.tableStyles["t"] = ts
        let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
        theme.wordRules = true
        let layout = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
        layout.pageSetup = .letter
        layout.width = PageSetup.letter.width * theme.pixelsPerPoint
        layout.ensureLaidOut(doc)
        let px = theme.pixelsPerPoint
        let picY = (layout.pieces[0].first { $0.paragraph == 1 }?.pageY ?? 9999) / px
        let rowY = (layout.pieces[0].first { $0.paragraph == 2 }?.pageY ?? 0) / px
        XCTAssertLessThan(picY, rowY, "the picture's paragraph stands above the table: \(picY) against \(rowY)")
    }
    /// Lab table-props (Word's print): text after a centred floating table with room on both sides runs round it on
    /// both, a left piece and a right piece on each line level with the table, then across the page below it.
    func testTextRunsOnBothSidesOfACentredFloatingTable() throws {
        RichTextTheme.wordWindowsPages = true
        defer { RichTextTheme.wordWindowsPages = false }
        var cell = RichParagraph(text: "cell")
        cell.cell = CellRef(table: "t", row: 0, column: 0)
        let body = RichParagraph(text: String(repeating: "word ", count: 150))
        var doc = RichDocument(paragraphs: [cell, body])
        doc.tableColumns["t"] = [200]
        var ts = TableStyle()
        ts.floatsOverText = true
        ts.alignment = .center
        ts.keptPosition = "<w:tblpPr w:leftFromText=\"180\" w:rightFromText=\"180\" w:vertAnchor=\"text\" w:tblpY=\"1\"/>"
        doc.tableStyles["t"] = ts
        let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
        theme.wordRules = true
        let layout = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
        layout.pageSetup = .letter
        layout.width = PageSetup.letter.width * theme.pixelsPerPoint
        layout.ensureLaidOut(doc)
        let px = theme.pixelsPerPoint
        let rects = stride(from: 0, to: 750, by: 5).map { layout.caretRect(RichPosition(paragraph: 1, offset: $0), doc) }
        let tableLeft = (PageSetup.letter.width - 200) / 2
        let first = rects.first!
        XCTAssertLessThan(first.left / px, tableLeft, "the first line starts left of the table")
        XCTAssertTrue(rects.contains { $0.left / px > tableLeft + 200 }, "a right piece stands at its right")
        XCTAssertTrue(rects.allSatisfy { $0.left / px < PageSetup.letter.width }, "no line runs past the margin")
    }
    /// Lab float-offset e (Word's print): a table anchored to the margin, tblpY 1, first in the body, takes the text
    /// beside it as one anchored to the text does: the first line stands level with the table's top.
    func testATableAnchoredToTheMarginAtTheTopTakesTheTextBesideIt() throws {
        let onWin = DocxFormat.wordOnWindows, was = RichTextTheme.wordWindowsPages
        DocxFormat.wordOnWindows = true; RichTextTheme.wordWindowsPages = true
        defer { DocxFormat.wordOnWindows = onWin; RichTextTheme.wordWindowsPages = was }
        func lineTop(_ anchor: String) throws -> Double {
            var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "x")]), pageSetup: .letter))
            let di = entries.firstIndex { $0.name == "word/document.xml" }!
            var xml = String(decoding: entries[di].data, as: UTF8.self)
            let a = xml.range(of: "<w:body>")!, b = xml.range(of: "</w:body>")!
            let body = "<w:tbl><w:tblPr><w:tblpPr w:leftFromText=\"180\" w:rightFromText=\"180\" w:vertAnchor=\"\(anchor)\" w:tblpY=\"1\"/><w:tblW w:w=\"0\" w:type=\"auto\"/><w:jc w:val=\"center\"/></w:tblPr><w:tblGrid><w:gridCol w:w=\"1800\"/><w:gridCol w:w=\"4680\"/></w:tblGrid>" + String(repeating: "<w:tr><w:tc><w:tcPr><w:tcW w:w=\"1800\" w:type=\"dxa\"/></w:tcPr><w:p><w:pPr><w:spacing w:after=\"0\" w:line=\"240\" w:lineRule=\"auto\"/></w:pPr></w:p></w:tc><w:tc><w:tcPr><w:tcW w:w=\"4680\" w:type=\"dxa\"/></w:tcPr><w:p><w:pPr><w:spacing w:after=\"0\" w:line=\"240\" w:lineRule=\"auto\"/></w:pPr></w:p></w:tc></w:tr>", count: 3) + "</w:tbl><w:p><w:r><w:t>\(String(repeating: "word ", count: 150))</w:t></w:r></w:p>"
            xml.replaceSubrange(a.upperBound ..< b.lowerBound, with: body)
            entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
            let doc = try DocxFormat.read(try Zip.write(entries)).document
            let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
            theme.wordRules = true
            let layout = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
            layout.pageSetup = .letter
            layout.width = PageSetup.letter.width * theme.pixelsPerPoint
            layout.ensureLaidOut(doc)
            let at = doc.paragraphs.firstIndex { $0.cell == nil && !$0.text.isEmpty }!
            return layout.caretRect(RichPosition(paragraph: at, offset: 0), doc).top / theme.pixelsPerPoint
        }
        let text = try lineTop("text"), margin = try lineTop("margin")
        XCTAssertEqual(margin, text, accuracy: 0.5)
        XCTAssertLessThan(margin, 100)
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
