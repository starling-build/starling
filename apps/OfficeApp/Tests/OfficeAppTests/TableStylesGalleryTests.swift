import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp
@testable import OfficeText

/// W-TB-4: Table Design > Table Styles, and Table Style Options over a named style.
final class TableStylesGalleryTests: XCTestCase {
    /// A 3x3 table whose cells hold "r<row>c<column>".
    private func grid() -> RichDocumentController {
        TableStyleGallery.install()
        let c = RichDocumentController(plainText: "")
        c.insertTable(rows: 3, columns: 3)
        for i in c.document.paragraphs.indices.reversed() {
            guard let cell = c.document.paragraphs[i].cell else { continue }
            c.moveTo(RichPosition(paragraph: i, offset: 0), extend: false)
            c.insertText("r\(cell.row)c\(cell.column)")
        }
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        return c
    }
    private func para(_ d: RichDocument, _ row: Int, _ col: Int) -> RichParagraph {
        d.paragraphs.first { $0.cell?.row == row && $0.cell?.column == col }!
    }
    private func accent(_ d: RichDocument, _ n: Int) -> Color {
        let p = TableStyleGallery.palette(of: d)["accent\(n)"]!
        return Color(0xFF00_0000 | Int64(p.0) << 16 | Int64(p.1) << 8 | Int64(p.2))
    }
    private func part(_ data: Data, _ name: String) throws -> String? {
        try Zip.read(data).first { $0.name == name }.map { String(decoding: $0.data, as: UTF8.self) }
    }

    func testAStyleIsOneUndoStepAndWordReadsItAsItsOwn() throws {
        let c = grid()
        TableStyleGallery.apply("GridTable4-Accent1", to: c)
        let d = c.document
        XCTAssertEqual(d.tableStyleIds.values.first, "GridTable4-Accent1")
        XCTAssertEqual(para(d, 0, 1).cell?.fill, accent(d, 1), "the header row takes the accent")
        XCTAssertEqual(para(d, 0, 1).runs.first?.style.bold, true)
        XCTAssertEqual(para(d, 0, 1).runs.first?.style.color, Color(0xFFFFFFFF), "header text is white")
        XCTAssertNotEqual(para(d, 1, 1).cell?.fill, para(d, 2, 1).cell?.fill, "banded rows")
        XCTAssertNotNil(d.keptParts[NamedTableState.themePath], "the theme the style's colours come from is saved with it")

        let data = try DocxFormat.write(d, pageSetup: .letter)
        let doc = try XCTUnwrap(try part(data, "word/document.xml"))
        XCTAssertTrue(doc.containsSubstring("<w:tblStyle w:val=\"GridTable4-Accent1\"/>"))
        XCTAssertFalse(doc.containsSubstring("<w:tblBorders>"), "the borders are the style's, not written over it")
        XCTAssertTrue(try XCTUnwrap(try part(data, "word/styles.xml")).containsSubstring("w:styleId=\"GridTable4-Accent1\""))
        let back = try DocxFormat.read(data).document
        XCTAssertEqual(para(back, 0, 1).cell?.fill, para(d, 0, 1).cell?.fill, "an opened file looks as the editor drew it")
        XCTAssertEqual(para(back, 1, 1).cell?.fill, para(d, 1, 1).cell?.fill)

        c.undo()
        XCTAssertTrue(c.document.tableStyleIds.isEmpty, "one undo step")
        XCTAssertNil(para(c.document, 0, 1).cell?.fill)
        XCTAssertNotEqual(para(c.document, 0, 1).runs.first?.style.bold, true)
        XCTAssertNil(c.document.keptParts[NamedTableState.themePath])
    }

    func testSwitchingStylesMovesTheStylesLookAndKeepsTheUsers() throws {
        let c = grid()
        // The user's own shading and bold, in a body cell no style part makes bold (a first-column cell's direct bold
        // cannot be told from the style's, since the editor keeps both as the run's own).
        let i = c.document.paragraphs.firstIndex { $0.cell?.row == 1 && $0.cell?.column == 1 }!
        c.moveTo(RichPosition(paragraph: i, offset: 0), extend: false)
        c.setCellShading(Color(0xFFFF0000))
        c.moveTo(RichPosition(paragraph: i, offset: 4), extend: true)
        c.toggleBold()
        TableStyleGallery.apply("GridTable4-Accent2", to: c)
        TableStyleGallery.apply("GridTable1Light", to: c)
        let d = c.document
        XCTAssertEqual(d.tableStyleIds.values.first, "GridTable1Light")
        XCTAssertNil(para(d, 0, 1).cell?.fill, "Grid Table 1 Light has no header fill")
        XCTAssertNil(para(d, 0, 1).runs.first?.style.color, "the white header text went with the old style")
        XCTAssertEqual(para(d, 0, 1).runs.first?.style.bold, true, "the new style's header is bold too")
        XCTAssertEqual(para(d, 1, 1).cell?.fill, Color(0xFFFF0000), "the user's shading is kept")
        XCTAssertEqual(para(d, 1, 1).runs.first?.style.bold, true, "the user's bold is kept")
        TableStyleGallery.apply("TableNormal", to: c)
        XCTAssertNotEqual(para(c.document, 0, 1).runs.first?.style.bold, true, "Clear takes the header bold away")
        XCTAssertEqual(para(c.document, 1, 1).runs.first?.style.bold, true)
    }

    func testHeaderRowOffTakesTheHeaderLookAway() throws {
        let c = grid()
        TableStyleGallery.apply("GridTable4-Accent1", to: c)
        c.setTableLook(TableLook.firstRow, on: false)
        let d = c.document
        XCTAssertNotEqual(para(d, 0, 1).runs.first?.style.bold, true)
        XCTAssertNotEqual(para(d, 0, 1).cell?.fill, accent(d, 1))
        XCTAssertNil(para(d, 0, 1).runs.first?.style.color)
        let back = try DocxFormat.read(try DocxFormat.write(d, pageSetup: .letter)).document
        XCTAssertEqual(para(back, 0, 1).cell?.fill, para(d, 0, 1).cell?.fill, "Word reads the same switches")
        c.undo()
        XCTAssertEqual(para(c.document, 0, 1).cell?.fill, accent(c.document, 1))
    }

    func testTheStylesColoursComeFromTheDocumentsTheme() {
        let x = TableStyleGallery.themed(#"<w:shd w:val="clear" w:color="auto" w:fill="4472C4" w:themeFill="accent1"/><w:color w:val="FFFFFF" w:themeColor="background1"/>"#,
                                         palette: ["accent1": (0x12, 0x34, 0x56), "lt1": (0xFE, 0xFE, 0xFE), "bg1": (0xFE, 0xFE, 0xFE)])
        XCTAssertTrue(x.containsSubstring("w:fill=\"123456\""), x)
        XCTAssertTrue(x.containsSubstring("<w:color w:val=\"FEFEFE\""), x)
    }

    func testTheGalleryListsWordsStyles() {
        let g = TableStyleGallery.groups
        XCTAssertEqual(g.map(\.0), ["Plain Tables", "Grid Tables", "List Tables"])
        XCTAssertEqual(g.map(\.1.count), [7, 49, 49])
        XCTAssertEqual(TableStyleGallery.entry("GridTable4-Accent3")?.name, "Grid Table 4 - Accent 3")
        XCTAssertTrue(TableStyleGallery.xml("ListTable3-Accent5")?.containsSubstring("accent5") == true)
        XCTAssertFalse(TableStyleGallery.xml("ListTable3-Accent5")?.containsSubstring("accent1") == true)
    }

    func testTheRibbonGalleryAppliesAStyle() throws {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(1280, 800))
        let c = try XCTUnwrap(ui.state(OfficeShellState.self)).session.controller
        c.insertTable(rows: 3, columns: 3)
        ui.pump()
        XCTAssertTrue(ui.tap(text: "Table Design"))
        ui.pump()
        XCTAssertTrue(ui.tap(text: "Table Styles"))
        ui.pump()
        XCTAssertTrue(ui.tap(text: "Grid Table 5 Dark"))
        ui.pump()
        XCTAssertTrue(ui.tap(text: "Grid Table 5 Dark - Accent 3"))
        for _ in 0 ..< 20 { ui.pump() }
        XCTAssertEqual(c.document.tableStyleIds.values.first, "GridTable5Dark-Accent3")
        XCTAssertTrue(ui.tap(text: "Header Row"), "Table Style Options sit beside the gallery")
        XCTAssertEqual(c.tableLook(of: c.currentCell!.table) & TableLook.firstRow, 0)
        c.undo()
        c.undo()
        XCTAssertTrue(c.document.tableStyleIds.isEmpty, "the gallery is one undo step")
    }
}
