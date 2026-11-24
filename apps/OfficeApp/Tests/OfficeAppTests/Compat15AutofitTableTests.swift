// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

/// An autofit table whose grid outgrows the text column by less than its cell margins: before compat 15 Word keeps
/// the grid, from compat 15 it sets the table's edge at the column and shrinks the grid to fit.
final class Compat15AutofitTableTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        _ = TestText.icuLoaded
        _ = OfficeFonts.register()
    }

    /// Where the second column's text stands past the first's, in points.
    private func secondColumnOffset(compat: Int?, indent: Double = 0) -> Double {
        let was = RichTextTheme.wordWindowsPages
        RichTextTheme.wordWindowsPages = true
        defer { RichTextTheme.wordWindowsPages = was }
        var a = RichParagraph(text: "A", style: RichParagraphStyle(spaceAfter: 0))
        a.cell = CellRef(table: "T", row: 0, column: 0)
        var b = RichParagraph(text: "B", style: RichParagraphStyle(spaceAfter: 0))
        b.cell = CellRef(table: "T", row: 0, column: 1)
        var document = RichDocument(paragraphs: [a, b])
        document.compatibilityMode = compat
        let column = PageSetup.letter.columnWidth
        document.tableColumns["T"] = [column / 2 + 4.8, column / 2]
        var table = TableStyle(borders: false)
        table.indent = indent
        document.tableStyles["T"] = table
        let theme = RichTextTheme(fontFamily: OfficeFonts.serif)
        theme.wordRules = true
        let layout = RichLayout(theme: theme, paragraphCount: 2)
        layout.pageSetup = PageSetup.letter
        layout.width = column * theme.pixelsPerPoint
        layout.ensureLaidOut(document)
        return (layout.geometry(1).textLeft - layout.geometry(0).textLeft) / theme.pixelsPerPoint
    }

    func testGridOverTheColumnIsShrunkOnlyFromCompat15() {
        let before = secondColumnOffset(compat: 12)
        let from15 = secondColumnOffset(compat: 15)
        XCTAssertGreaterThan(before - from15, 1.5, "the compat-15 table is shrunk to the column; the older one keeps its grid")
    }

    func testGridThatFitsWithItsOutdentStandsAtCompat15() {
        let fits = secondColumnOffset(compat: 15, indent: -4.8)
        let over = secondColumnOffset(compat: 15)
        XCTAssertGreaterThan(fits - over, 1.5, "outdented by the overhang the grid stands; without the outdent it is shrunk")
    }
}
