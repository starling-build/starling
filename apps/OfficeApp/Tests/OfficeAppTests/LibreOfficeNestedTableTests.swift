// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// LibreOffice's tdf170381 files: a table nested in a cell, parted over a
/// page break between its rows, as Word's print of them (two pages each).
final class LibreOfficeNestedTableTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        _ = TestText.icuLoaded
        _ = OfficeFonts.register()
    }

    private func pages(_ id: String) throws -> Int {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("test/corpus/docx/lo/docs/\(id).docx")
        guard let data = try? Data(contentsOf: file) else { throw XCTSkip("the LibreOffice set is not checked out") }
        let parsed = try DocxFormat.read(data)
        let theme = RichTextTheme(fontFamily: OfficeFonts.serif)
        theme.wordRules = true
        let layout = RichLayout(theme: theme, paragraphCount: parsed.document.paragraphs.count)
        let setup = parsed.pageSetup ?? .letter
        layout.pageSetup = setup
        layout.width = setup.width * 96.0 / 72.0
        layout.ensureLaidOut(parsed.document)
        return layout.pageCount
    }

    /// A table nested in a cell and floating, which the cell grows to hold: LibreOffice's
    /// tdf170477, a row of 3547 twips at least with a floating table down to 184.0pt,
    /// whose text after it starts 184.0pt under the table's first line in Word's print.
    func testRowGrowsToHoldANestedFloatingTable() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("test/corpus/docx/lo/docs/lo-496593e53af2b979.docx")
        guard let data = try? Data(contentsOf: file) else { throw XCTSkip("the LibreOffice set is not checked out") }
        let parsed = try DocxFormat.read(data)
        let doc = parsed.document
        let theme = RichTextTheme(fontFamily: OfficeFonts.serif)
        theme.wordRules = true
        let layout = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
        let setup = parsed.pageSetup ?? .letter
        layout.pageSetup = setup
        layout.width = setup.width * 96.0 / 72.0
        layout.ensureLaidOut(doc)
        func top(_ text: String) throws -> Double {
            let k = try XCTUnwrap(doc.paragraphs.firstIndex { $0.text == text })
            return layout.caretRect(RichPosition(paragraph: k, offset: 0), doc).top / theme.pixelsPerPoint
        }
        XCTAssertEqual(try top("p79") - top("Table4:A1 p1"), 184.0, accuracy: 0.6)
    }

    /// A table placed against the page in the right margin, beside the letter-head table above it
    /// and not under it: LibreOffice's tdf92157 keeps the address block on page 1 with the letter,
    /// and the body after it on that page (six pages in Word's print, seven without).
    func testPageAnchoredTableBesideAnotherStaysOnItsPage() throws {
        XCTAssertEqual(try pages("lo-6a5857f20e8eda1e"), 6)
    }

    /// A table style's own indent: LibreOffice's tdf103976 sets its table in a style that indents
    /// 360 twips, and the list's mark stands 18pt in from the margin in Word's print (108 on a
    /// 90pt margin).
    func testTableStyleIndentIsKept() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("test/corpus/docx/lo/docs/lo-5a78fd37d46a2f88.docx")
        guard let data = try? Data(contentsOf: file) else { throw XCTSkip("the LibreOffice set is not checked out") }
        let parsed = try DocxFormat.read(data)
        let doc = parsed.document
        let theme = RichTextTheme(fontFamily: OfficeFonts.serif)
        theme.wordRules = true
        let layout = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
        let setup = parsed.pageSetup ?? .letter
        layout.pageSetup = setup
        layout.width = setup.width * 96.0 / 72.0
        layout.ensureLaidOut(doc)
        func left(_ text: String) throws -> Double {
            let k = try XCTUnwrap(doc.paragraphs.firstIndex { $0.text.hasPrefix(text) })
            return layout.caretRect(RichPosition(paragraph: k, offset: 0), doc).left / theme.pixelsPerPoint
        }
        // (The caret at the paragraph's start stands at its left indent, 18pt, on the table's 18pt.)
        XCTAssertEqual(try left("."), 36.0, accuracy: 1.5)
    }

    /// A 56-row list of short rows in a cell is a table of its own and parts between its rows:
    /// LibreOffice's tdf170630 takes two pages in Word's print, one flattened.
    func testLongListOfShortRowsInACellTakesTwoPages() throws {
        XCTAssertEqual(try pages("lo-e30957810e467cc8"), 2)
    }

    /// One column in a normal table, floating in name only: parts between its rows.
    func testSplitFloatTableInNormalTableTakesTwoPages() throws {
        XCTAssertEqual(try pages("lo-1e0077c34b69d826"), 2)
    }

    /// A title and a two-column nested table of 28 rows in one row taller than a
    /// page, whose first paragraph keeps with the next: it parts, not runs off.
    func testSplitFloatTableInFloatTableTakesTwoPages() throws {
        XCTAssertEqual(try pages("lo-148591d55e08ca3c"), 2)
    }
}
