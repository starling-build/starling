import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// X-DA-1: a Sort level on "Cell Icon" puts the cells showing one conditional-format icon on top (or
/// bottom), offers the icons the column shows, and is saved as Excel's sortBy="icon".
final class SheetsSortIconTests: XCTestCase {
    /// B2:B6 = 1, 9, 5, 2, 8 under 3 arrows (bands at 33% and 67% of 1..9): down, up, side, down, up.
    private func controller() -> WorkbookController {
        let c = WorkbookController()
        c.load(Workbook(sheets: [Worksheet(name: "Data")]))
        let rows = [["Name", "Score"], ["a", "1"], ["b", "9"], ["c", "5"], ["d", "2"], ["e", "8"]]
        for (r, row) in rows.enumerated() { for (k, t) in row.enumerated() { c.setInput(t, at: CellAddress(row: r, col: k)) } }
        XCTAssertNil(c.addConditionalFormat(CFSpec(kind: .iconSet("3Arrows")), on: [CellRange("B2:B6")!]))
        c.select(CellAddress(row: 1, col: 0))
        return c
    }
    private func names(_ c: WorkbookController) -> [String] { (1...5).map { c.input(CellAddress(row: $0, col: 0)) } }
    private func state(_ c: WorkbookController) -> String? { c.sheet.keptElements.first { $0.name == "sortState" }?.text }
    private let up = SortIcon(set: "3Arrows", index: 2), down = SortIcon(set: "3Arrows", index: 0)

    func testTheColumnsIconsAreOfferedMostUsedFirst() {
        let c = controller()
        XCTAssertEqual(c.sortIcons(CellRange("A1:B6")!, line: 1, hasHeader: true, byColumns: false),
                       [up, down, SortIcon(set: "3Arrows", index: 1)])
        XCTAssertEqual(c.sortIcons(CellRange("A1:B6")!, line: 0, hasHeader: true, byColumns: false), [], "no rule on column A")
    }

    func testAnIconOnTopSortsItsRowsFirstAsOneUndoStepAndIsSaved() throws {
        let c = controller()
        XCTAssertNil(c.sortRange(CellRange("A1:B6")!, keys: [SortKey(col: 1, on: .cellIcon, icon: up)], hasHeader: true))
        XCTAssertEqual(names(c), ["b", "e", "a", "c", "d"], "the up arrows first, the rest in their order")
        let want = "<sortState ref=\"A2:B6\"><sortCondition sortBy=\"icon\" ref=\"B2:B6\" iconSet=\"3Arrows\" iconId=\"2\"/></sortState>"
        XCTAssertEqual(state(c), want)
        let again = WorkbookController()
        again.load(try Xlsx.read(try Xlsx.write(c.book)))
        XCTAssertEqual(again.sheet.keptElements.first { $0.name == "sortState" }?.text, want)
        c.undo()
        XCTAssertEqual(names(c), ["a", "b", "c", "d", "e"])
        XCTAssertNil(state(c))
    }

    func testAnIconOnBottomSortsItsRowsLast() {
        let d = controller()
        XCTAssertNil(d.sortRange(CellRange("A1:B6")!, keys: [SortKey(col: 1, on: .cellIcon, colorOnTop: false, icon: down)], hasHeader: true))
        XCTAssertEqual(names(d), ["b", "c", "e", "a", "d"])
        XCTAssertEqual(state(d), "<sortState ref=\"A2:B6\"><sortCondition descending=\"1\" sortBy=\"icon\" ref=\"B2:B6\" iconSet=\"3Arrows\" iconId=\"0\"/></sortState>")
    }

    func testTheDialogOffersCellIconAndSortsByTheFirstIcon() {
        let c = controller()
        var closed = false
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SortDialog(controller: c, range: CellRange("A1:B6")!, hasHeader: true, onClose: { closed = true }), title: "T"),
                              size: Size(1280, 800))
        let s = ui.state(SortDialogState.self)!
        s.setColumn(0, 1)
        s.setSortOn(0, .cellIcon)
        ui.pump()
        XCTAssertEqual(s.icons(0), [up, down, SortIcon(set: "3Arrows", index: 1)])
        XCTAssertEqual(s.levels[0].icon, up, "the most used icon is picked")
        XCTAssertTrue(ui.has(text: "Cell Icon"))
        s.setIcon(0, down)
        s.setColorOnTop(0, false)
        ui.press(.enter)
        XCTAssertTrue(closed)
        XCTAssertEqual(names(c), ["b", "c", "e", "a", "d"])
    }

    func testAColumnWithoutIconsSaysSo() {
        let c = controller()
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SortDialog(controller: c, range: CellRange("A1:B6")!, hasHeader: true, onClose: {}), title: "T"),
                              size: Size(1280, 800))
        let s = ui.state(SortDialogState.self)!
        s.setColumn(0, 0)
        s.setSortOn(0, .cellIcon)
        ui.pump()
        XCTAssertNil(s.levels[0].icon)
        XCTAssertTrue(ui.has(text: "No conditional-format icons here."))
    }

    func testA2010SetOrNoIconCannotBeNamedSoTheRecordGoes() {
        let c = controller()
        _ = c.sortRange(CellRange("A1:B6")!, keys: [SortKey(col: 0)], hasHeader: true)
        XCTAssertNotNil(state(c))
        _ = c.sortRange(CellRange("A1:B6")!, keys: [SortKey(col: 1, on: .cellIcon, icon: SortIcon(set: "3Stars", index: 0))], hasHeader: true)
        XCTAssertNil(state(c))
        _ = c.sortRange(CellRange("A1:B6")!, keys: [SortKey(col: 0)], hasHeader: true)
        _ = c.sortRange(CellRange("A1:B6")!, keys: [SortKey(col: 1, on: .cellIcon, icon: nil)], hasHeader: true)
        XCTAssertNil(state(c))
    }

    /// For the Excel check: set STARLING_UI_CHECK_DIR and the book is written there (up arrows on top).
    func testSaveForExcel() throws {
        guard let dir = ProcessInfo.processInfo.environment["STARLING_UI_CHECK_DIR"] else { throw XCTSkip("no check folder") }
        let c = controller()
        XCTAssertNil(c.sortRange(CellRange("A1:B6")!, keys: [SortKey(col: 1, on: .cellIcon, icon: up), SortKey(col: 1, on: .cellIcon, colorOnTop: false, icon: down)], hasHeader: true))
        try Xlsx.write(c.book).write(to: URL(fileURLWithPath: dir + "/sort-icon.xlsx"))
    }
}
