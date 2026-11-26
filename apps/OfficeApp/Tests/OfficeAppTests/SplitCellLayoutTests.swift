// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

final class SplitCellLayoutTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        _ = TestText.icuLoaded
        _ = OfficeFonts.register()
    }

    func testShortCellAlignsWithTheKeptLineOfAnotherCentredCell() throws {
        for alignment in ["center", "bottom"] {
            var line = RichParagraphStyle(spaceAfter: 0, lineSpacing: 1)
            line.lineHeightPoints = 12
            line.widowControl = false
            var prefix = line
            prefix.lineHeightPoints = 60
            var paragraphs = [RichParagraph(text: "Before", style: prefix)]
            for (column, text) in ["Short", "First\nSecond", "One\nTwo\nThree\nFour\nFive"].enumerated() {
                var p = RichParagraph(text: text, style: line)
                p.cell = CellRef(table: "T", row: 0, column: column, verticalAlign: column == 0 ? alignment : "center")
                paragraphs.append(p)
            }
            var document = RichDocument(paragraphs: paragraphs)
            document.compatibilityMode = 15
            document.tableColumns["T"] = [90, 90, 90]
            var table = TableStyle(borders: false)
            table.cellMarginTop = 0
            table.cellMarginBottom = 0
            document.tableStyles["T"] = table
            var page = PageSetup.letter
            page.height = 100
            page.marginTop = 10
            page.marginBottom = 10
            let theme = RichTextTheme(fontFamily: OfficeFonts.serif)
            theme.wordRules = true
            let layout = RichLayout(theme: theme, paragraphCount: paragraphs.count)
            layout.pageSetup = page
            layout.width = page.columnWidth * theme.pixelsPerPoint
            layout.ensureLaidOut(document)
            func baseline(_ paragraph: Int, _ line: Int = 0) throws -> (page: Int, y: Double) {
                let geometry = layout.geometry(paragraph)
                let metrics = geometry.painter.computeLineMetrics()
                let metric = try XCTUnwrap(metrics.indices.contains(line) ? metrics[line] : nil,
                    "\(alignment): paragraph \(paragraph) needs line \(line), but has \(metrics.count) line metrics; ICU loaded: \(TestText.icuLoaded)")
                let flowY = geometry.textTop + metric.baseline
                let piece = try XCTUnwrap(layout.pieces.flatMap { $0 }.first {
                    $0.paragraph == paragraph && $0.part != .rules && flowY >= $0.flowTop && flowY < $0.flowBottom
                })
                return (piece.page, piece.pageY + flowY - piece.flowTop)
            }
            let short = try baseline(1), first = try baseline(2), second = try baseline(2, 1)
            XCTAssertEqual(first.page, 0)
            XCTAssertEqual(second.page, 1)
            XCTAssertEqual(short.page, first.page)
            XCTAssertEqual(short.y, first.y, accuracy: 0.5, "\(alignment): the row keeps one line, despite spare room below it")
        }
    }

    /// In a spaced table (compat 15) the text of an outset-bordered cell stands half the cell line further in than under a plain border
    /// (dx2 8ba99a6d: outset 0.75 pt lines, text 0.39 pt further in in Word's print).
    func testOutsetCellBordersMoveTheTextInByHalfTheLine() throws {
        RichTextTheme.wordWindowsPages = true
        defer { RichTextTheme.wordWindowsPages = false }
        func textBox(_ style: String) throws -> (left: Double, width: Double) {
            var p = RichParagraph(text: "Cell", style: RichParagraphStyle(spaceAfter: 0, lineSpacing: 1))
            p.cell = CellRef(table: "T", row: 0, column: 0)
            var document = RichDocument(paragraphs: [p])
            document.compatibilityMode = 15
            document.tableColumns["T"] = [200]
            var table = TableStyle(borders: true)
            table.cellSpacing = 2
            table.borderWidth = 0.75
            table.borderStyle = style
            document.tableStyles["T"] = table
            let theme = RichTextTheme(fontFamily: OfficeFonts.serif)
            theme.wordRules = true
            let layout = RichLayout(theme: theme, paragraphCount: 1)
            layout.pageSetup = .letter
            layout.width = PageSetup.letter.columnWidth * theme.pixelsPerPoint
            layout.ensureLaidOut(document)
            let g = layout.geometry(0)
            return (g.textLeft / theme.pixelsPerPoint, g.textWidth / theme.pixelsPerPoint)
        }
        let (o, s) = (try textBox("outset"), try textBox("single"))
        XCTAssertEqual(o.left - s.left, 0.375, accuracy: 0.01)
        // The line moves the text; it does not narrow the room (dx2 8ba99a6d wrapped one line too many when it did).
        XCTAssertEqual(o.width, s.width, accuracy: 0.01)
    }

    /// A table that states its cell spacing (even none) rules each cell on its own, so the table's top line framing the row that opens a
    /// continued page stands over the row's own top line: the page opens a line lower than without the statement
    /// (zh-15f60bacd, dx2 af62a100da33: every continued page opened 0.5 pt higher in ours than in Word's print).
    func testASpacedTablesContinuedPageOpensALineLower() throws {
        RichTextTheme.wordWindowsPages = true
        defer { RichTextTheme.wordWindowsPages = false }
        func secondPageTop(spacing: Double?) throws -> Double {
            var line = RichParagraphStyle(spaceAfter: 0, lineSpacing: 1)
            line.lineHeightPoints = 20
            var paragraphs: [RichParagraph] = []
            for r in 0 ..< 8 {
                var p = RichParagraph(text: "Row \(r)", style: line)
                p.cell = CellRef(table: "T", row: r, column: 0)
                p.cell?.bordersXML = "<w:tcBorders><w:top w:val=\"single\" w:sz=\"4\"/></w:tcBorders>"
                paragraphs.append(p)
            }
            var document = RichDocument(paragraphs: paragraphs)
            document.compatibilityMode = 15
            document.tableColumns["T"] = [200]
            var table = TableStyle(borders: true)
            table.cellSpacing = spacing
            table.cellMarginTop = 0
            table.cellMarginBottom = 0
            document.tableStyles["T"] = table
            var page = PageSetup.letter
            page.height = 100
            page.marginTop = 10
            page.marginBottom = 10
            let theme = RichTextTheme(fontFamily: OfficeFonts.serif)
            theme.wordRules = true
            let layout = RichLayout(theme: theme, paragraphCount: paragraphs.count)
            layout.pageSetup = page
            layout.width = page.columnWidth * theme.pixelsPerPoint
            layout.ensureLaidOut(document)
            let first = try XCTUnwrap(layout.pieces.flatMap { $0 }.first { $0.page == 1 && $0.part != .rules })
            return first.pageY / theme.pixelsPerPoint
        }
        let plain = try secondPageTop(spacing: nil), stated = try secondPageTop(spacing: 0)
        XCTAssertEqual(stated - plain, 0.5, accuracy: 0.05)
    }

    /// A row split at a page's foot, in a table ruled at the table level only (no cell spacing, no cell top line):
    /// its part on the page closes on the table's bottom line, so the page keeps a line of it only if the line fits
    /// too. zh-89385c94 (Table Grid) kept one 22 pt line more than Word's print and ran a line late on every later
    /// page; gv-30930cbf (lines between rows only) prints its part's last line on the foot with no line there.
    func testASplitRowLeavesRoomAtTheFootForTheTablesBottomLine() throws {
        RichTextTheme.wordWindowsPages = true
        defer { RichTextTheme.wordWindowsPages = false }
        func linesOnFirstPage(bottomLine: Bool, pageHeight: Double) -> Int {
            var line = RichParagraphStyle(spaceAfter: 0, lineSpacing: 1)
            line.lineHeightPoints = 20
            var paragraphs: [RichParagraph] = []
            for r in 0 ..< 2 {
                for k in 0 ..< 6 {
                    var p = RichParagraph(text: "Row \(r) line \(k)", style: line)
                    p.cell = CellRef(table: "T", row: r, column: 0)
                    paragraphs.append(p)
                }
            }
            var document = RichDocument(paragraphs: paragraphs)
            document.compatibilityMode = 14
            document.tableColumns["T"] = [200]
            var table = TableStyle(borders: true)
            if !bottomLine { table.edges = BorderEdges(bottom: false) }
            table.cellMarginTop = 0
            table.cellMarginBottom = 0
            document.tableStyles["T"] = table
            var page = PageSetup.letter
            page.height = pageHeight
            page.marginTop = 10
            page.marginBottom = 10
            let theme = RichTextTheme(fontFamily: OfficeFonts.serif)
            theme.wordRules = true
            let layout = RichLayout(theme: theme, paragraphCount: paragraphs.count)
            layout.pageSetup = page
            layout.width = page.columnWidth * theme.pixelsPerPoint
            layout.ensureLaidOut(document)
            return layout.pieces.flatMap { $0 }.filter { $0.page == 0 && $0.part != .rules }.count
        }
        // The smallest page that holds four lines of the first row: with a bottom line it is that line taller.
        func fitsFour(_ bottomLine: Bool) -> Double {
            var h = 95.0
            while h < 110, linesOnFirstPage(bottomLine: bottomLine, pageHeight: h) < 4 { h += 0.05 }
            return h
        }
        let ruled = fitsFour(true), open = fitsFour(false)
        XCTAssertLessThan(open, 110)
        XCTAssertEqual(ruled - open, 0.5, accuracy: 0.1, "ruled \(ruled) open \(open)")
    }
}
