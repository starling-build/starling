// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// LibreOffice's tdf170381 files: a table nested in a cell, parted over a
/// page break between its rows, as Word's print of them (two pages each).
final class NestedTableLayoutTests: XCTestCase {
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
