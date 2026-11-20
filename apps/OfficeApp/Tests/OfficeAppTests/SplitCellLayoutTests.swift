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
}
