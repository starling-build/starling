// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

final class SpacedTableBoxTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        _ = TestText.icuLoaded
        _ = OfficeFonts.register()
    }


    /// A stated column width is the cell's own box, the spacing's gap added round it (lab tbauto t8, Word for Windows): the
    /// second column's text stands a box and two gaps past the first's, not the stated width less one gap.
    func testFixedSpacedColumnsAreBoxesWithGapsRoundThem() {
        let was = RichTextTheme.wordWindowsPages
        RichTextTheme.wordWindowsPages = true
        defer { RichTextTheme.wordWindowsPages = was }
        var a = RichParagraph(text: "A", style: RichParagraphStyle(spaceAfter: 0))
        a.cell = CellRef(table: "T", row: 0, column: 0)
        var b = RichParagraph(text: "B", style: RichParagraphStyle(spaceAfter: 0))
        b.cell = CellRef(table: "T", row: 0, column: 1)
        var document = RichDocument(paragraphs: [a, b])
        document.compatibilityMode = 15
        document.tableColumns["T"] = [100, 100]
        var table = TableStyle(borders: false)
        table.cellSpacing = 2.5
        table.fixedLayout = true
        document.tableStyles["T"] = table
        let theme = RichTextTheme(fontFamily: OfficeFonts.serif)
        theme.wordRules = true
        let layout = RichLayout(theme: theme, paragraphCount: 2)
        layout.pageSetup = PageSetup.letter
        layout.width = PageSetup.letter.columnWidth * theme.pixelsPerPoint
        layout.ensureLaidOut(document)
        let apart = (layout.geometry(1).textLeft - layout.geometry(0).textLeft) / theme.pixelsPerPoint
        XCTAssertEqual(apart, 105, accuracy: 0.6)
    }
}
