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
