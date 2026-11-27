// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import OfficeText
@testable import OfficeApp

/// Word for Windows at compat 15: what an autofit column's narrowest is, and how a nested table of a set width takes its room.
final class AutofitNestedRoomTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        _ = TestText.icuLoaded
        _ = OfficeFonts.register()
    }

    private func widths(_ doc: RichDocument) throws -> [Double] {
        let was = RichTextTheme.wordWindowsPages
        RichTextTheme.wordWindowsPages = true
        defer { RichTextTheme.wordWindowsPages = was }
        let theme = RichTextTheme(fontFamily: OfficeFonts.defaultFamily)
        theme.fontFamilyResolver = OfficeFonts.substitute
        theme.faceResolver = OfficeFonts.face
        theme.averageCharWidth = OfficeFonts.averageCharWidth
        theme.wordRules = true
        let l = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
        l.pageSetup = PageSetup.letter
        l.width = PageSetup.letter.contentWidth * theme.pixelsPerPoint
        l.ensureLaidOut(doc)
        return try XCTUnwrap(l.columnWidths(of: "outer"))
    }

    /// An outer table of `columns` holding `first` in its first cell and, in its second, a nested table of `nested` pt
    /// with 0.5 pt rules, or the text `second`.
    private func document(first: String, second: String? = nil, nested: Double? = nil, columns: [Double]) -> RichDocument {
        var left = RichParagraph(text: first)
        left.cell = CellRef(table: "outer", row: 0, column: 0)
        var right = RichParagraph(text: second ?? "")
        if let nested {
            var inner = RichParagraph(text: "a")
            inner.cell = CellRef(table: "inner", row: 0, column: 0)
            var box = RichTextBox(paragraphs: [inner])
            box.growsToFit = true
            box.insetLeft = 0; box.insetRight = 0; box.insetTop = 0; box.insetBottom = 0
            box.tableStyles = ["inner": TableStyle()]
            box.tableColumns = ["inner": [nested]]
            var block = ImageAttachment(data: Data(), width: nested, height: 20, name: "table")
            block.textBox = box
            right = RichParagraph(image: block)
        }
        right.cell = CellRef(table: "outer", row: 0, column: 1)
        var doc = RichDocument(paragraphs: [left, right, RichParagraph(text: "")])
        var outer = TableStyle()
        outer.width = columns.reduce(0, +)
        doc.tableStyles = ["outer": outer]
        doc.tableColumns = ["outer": columns]
        doc.compatibilityMode = 15
        return doc
    }

    func testNestedTableAsksForItsSideRulesAndWidensTheTableByWhatTheOthersCannotGive() throws {
        // dx2 f524a62c: a 9018-twip nested table with 0.5 pt side rules takes its column to 9018 + 216 + 10 twips in
        // Word's grid and print; the first column gives down to its narrowest and the table grows by the rest.
        // (Like it, the outer table is as wide as the text column, and the nested one is set at its grid.)
        let w = try widths(document(first: "x", nested: 450, columns: [40, 430]))
        XCTAssertEqual(w[1], 450 + 10.8 + 0.5, accuracy: 0.05, "the nested table, its cell margins and half of each side rule")
        XCTAssertGreaterThan(w.reduce(0, +), 470 + 5, "the first column cannot give it all, so the table widens")
    }

    func testNestedTableColumnTakesTheMarginOrHalfTheCellsRuleOnEachSide() throws {
        // Lab nestroom2 (Word 16, compat 15, outer cells [100, 300], a 300 pt nested table of 0.5 pt rules and no
        // margins in the second): Word's print gives that column, between rule middles, 300.92 / 301.64 / 303.56 under
        // 0.25 / 1 / 3 pt outer rules over 0 margins, 301.04 under 0.5 over 0.2, 301.76 / 301.88 / 303.56 under
        // 0.5 / 1 / 3 over 0.6 — the nested table and half of each of its rules (300.5), and on each side the margin
        // or half the cell's rule, whichever is more. (Word's print stands 0.06-0.18 wider throughout.)
        for (rule, margin, want) in [(0.25, 0.0, 300.75), (1.0, 0.0, 301.5), (3.0, 0.0, 303.5), (0.5, 0.2, 301.0),
                                     (0.5, 0.6, 301.7), (1.0, 0.6, 301.7), (3.0, 0.6, 303.5)] {
            var doc = document(first: "x", nested: 300, columns: [100, 300])
            doc.tableStyles["outer"]?.cellMarginLeft = margin
            doc.tableStyles["outer"]?.cellMarginRight = margin
            doc.tableStyles["outer"]?.borderWidth = rule
            if case .some(var block) = doc.paragraphs[1].image, var box = block.textBox {
                var inner = TableStyle()
                inner.cellMarginLeft = 0; inner.cellMarginRight = 0
                box.tableStyles["inner"] = inner
                block.textBox = box
                doc.paragraphs[1].image = block
            }
            let w = try widths(doc)
            XCTAssertEqual(w[1], want, accuracy: 0.05, "outer rule \(rule), margin \(margin)")
            XCTAssertEqual(w.reduce(0, +), 400, accuracy: 0.5, "the first column gives it (Word's print: 400.16 in each case)")
        }
    }

    func testSlashBetweenCyrillicLettersIsOnePiece() throws {
        // dx2 f524a62c's header "Д/д" is one piece in Word's print; a space after the slash parts it.
        let whole = try widths(document(first: "Д/д", nested: 450, columns: [40, 430]))
        let parted = try widths(document(first: "Д/ д", nested: 450, columns: [40, 430]))
        XCTAssertGreaterThan(whole[0] - parted[0], 3, "\"Д/д\" is narrowest whole")
    }

    func testHyphenBetweenDigitsPartsAColumnAtCompat15() throws {
        // dx2 89f7d55e: Word keeps the grid of a column narrower than "02.10-12.10.2024", setting it "02.10-" / "12.10.2024".
        let w = try widths(document(first: "x", second: "02.10-12.10.2024", columns: [300, 75]))
        XCTAssertEqual(w[1], 75, accuracy: 0.5, "the date parts after its hyphen; the column keeps its grid")
    }
}
