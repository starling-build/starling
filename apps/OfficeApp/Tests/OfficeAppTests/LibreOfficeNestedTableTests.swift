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

    /// sets "before the middle table:" in a 2000-twip cell, which wraps after "before the" in Word's print.
    func testTableWithoutGridTakesItsCellWidths() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("test/corpus/docx/lo/docs/lo-660753a9df95b5c4.docx")
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
        let k = try XCTUnwrap(doc.paragraphs.firstIndex { $0.text == "before the middle table:" })
        let first = layout.caretRect(RichPosition(paragraph: k, offset: 0), doc).top
        let last = layout.caretRect(RichPosition(paragraph: k, offset: doc.paragraphs[k].text.count), doc).top
        XCTAssertGreaterThan(last, first + 1)
    }

    /// LibreOffice's tdf111550 has "[inner:A1]" straight under "[outer:A2]" in Word's print.
    func testTableInsideAParagraphStandsAfterIt() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("test/corpus/docx/lo/docs/lo-0627e9c1e5b4e7ba.docx")
        guard let data = try? Data(contentsOf: file) else { throw XCTSkip("the LibreOffice set is not checked out") }
        let parsed = try DocxFormat.read(data)
        XCTAssertTrue(parsed.document.paragraphs.contains { p in
            p.image?.textBox?.paragraphs.contains { $0.text.contains("[inner:A1]") } == true })
    }

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
