// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

/// A run of keep-with-next paragraphs whose later, two-line member cannot follow on the page parts inside the latest member
/// that can split, as in Word's print of gv-3db26a1d34 (page 4 ends with the "Marchioness" heading and three lines of the
/// five-line paragraph under it; the last two go to page 5 with the kept list items). It used to send the whole run over.
final class KeptRunSplitTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        _ = TestText.icuLoaded
        _ = OfficeFonts.register()
    }

    func testARunPartsInsideItsLatestSplittableMember() throws {
        let layout = try laidOut(mode: 15)
        XCTAssertEqual(try pageOf(layout, 1, 0), 0, "the heading stays on the first page")
        XCTAssertEqual(try pageOf(layout, 2, 0), 0, "the paragraph under it starts there")
        XCTAssertEqual(try pageOf(layout, 2, 2), 0)
        XCTAssertEqual(try pageOf(layout, 2, 3), 1, "its last two lines go on with the items (widow control)")
        XCTAssertEqual(try pageOf(layout, 2, 4), 1)
        XCTAssertEqual(try pageOf(layout, 3, 0), 1)
        XCTAssertEqual(try pageOf(layout, 4, 0), 1)
    }

    /// Older modes (Word 2010's 14 down) send a run that fits a page over whole: the "Marchioness" run of gv-3db26a1d34
    /// opens page 5 in its mode 12 print (lab kncompat).
    func testAnOlderModeSendsTheRunOverWhole() throws {
        let layout = try laidOut(mode: 12)
        XCTAssertEqual(try pageOf(layout, 1, 0), 1, "the heading goes over")
        XCTAssertEqual(try pageOf(layout, 2, 0), 1)
        XCTAssertEqual(try pageOf(layout, 4, 0), 1)
    }

    private func laidOut(mode: Int) throws -> RichLayout {
        let saved = RichTextTheme.wordWindowsPages
        RichTextTheme.wordWindowsPages = true
        defer { RichTextTheme.wordWindowsPages = saved }
        var line = RichParagraphStyle(spaceAfter: 0, lineSpacing: 1)
        line.lineHeightPoints = 12
        line.widowControl = true
        var kept = line
        kept.keepNext = true
        let paragraphs = [
            RichParagraph(text: "a\nb\nc\nd\ne\nf", style: line),
            RichParagraph(text: "Heading", style: kept),
            RichParagraph(text: "one\ntwo\nthree\nfour\nfive", style: kept),
            RichParagraph(text: "item 1\nmore", style: kept),
            RichParagraph(text: "item 2\nmore", style: kept),
            RichParagraph(text: "After", style: line),
        ]
        var document = RichDocument(paragraphs: paragraphs)
        document.compatibilityMode = mode
        var page = PageSetup.letter
        page.height = 200
        page.marginTop = 10
        page.marginBottom = 10
        let theme = RichTextTheme(fontFamily: OfficeFonts.serif)
        theme.wordRules = true
        let layout = RichLayout(theme: theme, paragraphCount: paragraphs.count)
        layout.pageSetup = page
        layout.width = page.columnWidth * theme.pixelsPerPoint
        layout.ensureLaidOut(document)
        return layout
    }

    private func pageOf(_ layout: RichLayout, _ paragraph: Int, _ line: Int) throws -> Int {
        let geometry = layout.geometry(paragraph)
        let metrics = geometry.painter.computeLineMetrics()
        let metric = try XCTUnwrap(metrics.indices.contains(line) ? metrics[line] : nil,
            "paragraph \(paragraph) needs line \(line), has \(metrics.count); ICU loaded: \(TestText.icuLoaded)")
        let flowY = geometry.textTop + metric.baseline
        return try XCTUnwrap(layout.pieces.flatMap { $0 }.first {
            $0.paragraph == paragraph && $0.part != .rules && flowY >= $0.flowTop && flowY < $0.flowBottom
        }).page
    }
}
