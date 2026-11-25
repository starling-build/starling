import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// X-DA-2: comparison, top or bottom, average and colour filters on a column, and the dialog that sets them.
final class SheetsFilterRuleTests: XCTestCase {
    /// Region | Sales: East 10, West 20, East 30, blank 40, North 50 (rows 2 to 6).
    private func table() -> WorkbookController {
        let c = WorkbookController()
        let rows: [(String, String)] = [("Region", "Sales"), ("East", "10"), ("West", "20"), ("East", "30"), ("", "40"), ("North", "50")]
        var items: [(CellAddress, String)] = []
        for (i, r) in rows.enumerated() {
            items.append((CellAddress(row: i, col: 0), r.0))
            items.append((CellAddress(row: i, col: 1), r.1))
        }
        c.setInputs(items)
        c.select(CellAddress("A1")!)
        c.toggleAutoFilter()
        return c
    }

    private func reread(_ c: WorkbookController) throws -> WorkbookController {
        let again = WorkbookController()
        again.load(try Xlsx.read(try Xlsx.write(c.book)))
        return again
    }

    func testTwoConditionsJoinedByAndSurviveASave() throws {
        let c = table()
        let rule = FilterRule.compare(FilterCondition(op: "greaterThanOrEqual", value: "20"), and: true,
                                      FilterCondition(op: "lessThanOrEqual", value: "40"))
        XCTAssertNil(c.setFilterRule(col: 1, rule))
        XCTAssertEqual(c.sheet.filteredRows, [1, 5])
        XCTAssertEqual(c.filterSummary, "3 of 5 records found")
        XCTAssertEqual(try reread(c).sheet.autoFilter?.rules[1], rule)
        c.undo()
        XCTAssertTrue(c.sheet.filteredRows.isEmpty)
        XCTAssertTrue(c.sheet.autoFilter?.rules.isEmpty ?? false)
    }

    func testATextSearchUsesWildcardsAndOrJoinsTwoConditions() throws {
        let c = table()
        let begins = FilterRule.compare(FilterCondition(op: "equal", value: "E*"), and: false, nil)
        XCTAssertNil(c.setFilterRule(col: 0, begins))
        XCTAssertEqual(c.sheet.filteredRows, [2, 4, 5])
        let either = FilterRule.compare(FilterCondition(op: "equal", value: "?est"), and: false, FilterCondition(op: "equal", value: "North"))
        XCTAssertNil(c.setFilterRule(col: 0, either))
        XCTAssertEqual(c.sheet.filteredRows, [1, 3, 4])
        XCTAssertEqual(try reread(c).sheet.autoFilter?.rules[0], either)
    }

    func testTopBottomAndAverageAndTheTickedListReplaceEachOther() throws {
        let c = table()
        XCTAssertNil(c.setFilterRule(col: 1, .top(top: true, percent: false, count: 2)))
        XCTAssertEqual(c.sheet.filteredRows, [1, 2, 3])
        XCTAssertEqual(try reread(c).sheet.autoFilter?.rules[1], .top(top: true, percent: false, count: 2))
        XCTAssertNil(c.setFilterRule(col: 1, .top(top: false, percent: true, count: 20)))
        XCTAssertEqual(c.sheet.filteredRows, [2, 3, 4, 5])
        XCTAssertNil(c.setFilterRule(col: 1, .average(above: true)))
        XCTAssertEqual(c.sheet.filteredRows, [1, 2, 3])
        XCTAssertEqual(try reread(c).sheet.autoFilter?.rules[1], .average(above: true))
        c.setFilter(col: 1, allowed: ["10"])
        XCTAssertNil(c.sheet.autoFilter?.rules[1])
        XCTAssertEqual(c.sheet.filteredRows, [2, 3, 4, 5])
        XCTAssertEqual(c.setFilterRule(col: 1, .top(top: true, percent: false, count: 0)), .badCount)
    }

    func testAColourFilterKeepsTheCellsWithThatFill() throws {
        let c = table()
        c.select(range: CellRange("B2:B2")!, active: CellAddress("B2")!)
        c.setStyle { $0.fill = 0xFFC7CE }
        c.select(range: CellRange("B4:B4")!, active: CellAddress("B4")!)
        c.setStyle { $0.fill = 0xFFC7CE }
        XCTAssertEqual(c.filterColors(col: 1, fill: true), [0xFFC7CE])
        XCTAssertNil(c.setFilterRule(col: 1, .color(fill: true, 0xFFC7CE)))
        XCTAssertEqual(c.sheet.filteredRows, [2, 4, 5])
        let again = try reread(c)
        XCTAssertEqual(again.sheet.autoFilter?.rules[1], .color(fill: true, 0xFFC7CE))
        XCTAssertEqual(again.sheet.filteredRows, [2, 4, 5])
    }

    func testFiltersAreRefusedWithoutAFilterAndClearedByClear() {
        let c = WorkbookController()
        XCTAssertEqual(c.setFilterRule(col: 0, .average(above: true)), .noFilter)
        let t = table()
        XCTAssertNil(t.setFilterRule(col: 1, .average(above: true)))
        t.clearFilters()
        XCTAssertTrue(t.sheet.filteredRows.isEmpty)
        XCTAssertTrue(t.sheet.autoFilter?.rules.isEmpty ?? false)
    }

    // MARK: The dialog

    private func dialog(_ c: WorkbookController, col: Int, kind: String, _ log: @escaping (String) -> Void) -> WidgetTester {
        WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                               home: FilterDialog(controller: c, col: col, kind: kind, onClose: { log("closed") }), title: "T"),
                     size: Size(1280, 800))
    }

    func testTheNumberDialogSetsAComparisonWithASecondCondition() throws {
        let c = table()
        var log: [String] = []
        let ui = dialog(c, col: 1, kind: "Number") { log.append($0) }
        let state = ui.state(FilterDialogState.self)!
        state.setOp1("greaterThan")
        ui.pump()
        XCTAssertTrue(ui.tap(id: "filter-value1")); ui.type("10")
        state.setJoin("and"); state.setOp2("lessThan")
        ui.pump()
        XCTAssertTrue(ui.tap(id: "filter-value2")); ui.type("50")
        ui.press(.enter)
        XCTAssertEqual(log, ["closed"])
        XCTAssertEqual(c.sheet.autoFilter?.rules[1], .compare(FilterCondition(op: "greaterThan", value: "10"), and: true,
                                                              FilterCondition(op: "lessThan", value: "50")))
        XCTAssertEqual(c.sheet.filteredRows, [1, 5])
    }

    func testTheTextDialogTurnsContainsIntoWildcardsAndABlankValueIsRefused() {
        let c = table()
        var log: [String] = []
        let ui = dialog(c, col: 0, kind: "Text") { log.append($0) }
        let state = ui.state(FilterDialogState.self)!
        state.setOp1("contains")
        ui.press(.enter)
        XCTAssertTrue(log.isEmpty)
        XCTAssertEqual(state.message, FilterProblem.needsValue.message)
        ui.pump()
        XCTAssertTrue(ui.tap(id: "filter-value1")); ui.type("ast")
        ui.press(.enter)
        XCTAssertEqual(log, ["closed"])
        XCTAssertEqual(c.sheet.autoFilter?.rules[0], .compare(FilterCondition(op: "equal", value: "*ast*"), and: true, nil))
        XCTAssertEqual(c.sheet.filteredRows, [2, 4, 5])
    }

    func testTheTopDialogTheColourDialogAndClear() {
        let c = table()
        var ui = dialog(c, col: 1, kind: "Number") { _ in }
        ui.state(FilterDialogState.self)!.setMode("top")
        ui.pump()
        XCTAssertTrue(ui.tap(id: "filter-count")); ui.type("")
        ui.press(.enter)
        XCTAssertEqual(c.sheet.autoFilter?.rules[1], .top(top: true, percent: false, count: 10))
        ui = dialog(c, col: 1, kind: "Colour") { _ in }
        ui.press(.enter)
        XCTAssertEqual(ui.state(FilterDialogState.self)?.message, FilterProblem.noColor.message)
        ui = dialog(c, col: 1, kind: "Date") { _ in }
        XCTAssertTrue(ui.tap(id: "filter-clear"))
        XCTAssertNil(c.sheet.autoFilter?.rules[1])
        XCTAssertTrue(c.sheet.filteredRows.isEmpty)
    }
}
