// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

/// A table that states its own cell margin and has no default table style stands on the page's margin in Word for Windows:
/// its cell spacing does not set it out (lab tbauto).
final class TableNotSetOutTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        _ = TestText.icuLoaded
        _ = OfficeFonts.register()
    }

    private func textLeft(notSetOut: Bool) -> Double {
        var p = RichParagraph(text: "Cell", style: RichParagraphStyle(spaceAfter: 0))
        p.cell = CellRef(table: "T", row: 0, column: 0)
        var document = RichDocument(paragraphs: [p])
        document.compatibilityMode = 12
        document.tableColumns["T"] = [200]
        var table = TableStyle(borders: false)
        table.cellSpacing = 2.5
        table.cellMarginLeft = 4
        table.cellMarginRight = 4
        table.notSetOut = notSetOut
        document.tableStyles["T"] = table
        let theme = RichTextTheme(fontFamily: OfficeFonts.serif)
        theme.wordRules = true
        let layout = RichLayout(theme: theme, paragraphCount: 1)
        layout.pageSetup = PageSetup.letter
        layout.width = PageSetup.letter.columnWidth * theme.pixelsPerPoint
        layout.ensureLaidOut(document)
        return layout.geometry(0).textLeft
    }

    func testOwnMarginTableIsNotSetOutBySpacing() {
        // Set out, the old-compat table shifts left by its margin and spacing; flagged, it stands on the margin.
        XCTAssertGreaterThan(textLeft(notSetOut: true), textLeft(notSetOut: false) + 1)
    }
}
