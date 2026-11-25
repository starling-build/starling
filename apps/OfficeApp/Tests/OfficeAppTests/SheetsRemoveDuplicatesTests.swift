import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// X-DA-6a: Data → Remove Duplicates, model and dialog.
final class SheetsRemoveDuplicatesTests: XCTestCase {
    private func controller() -> WorkbookController {
        let c = WorkbookController(); c.load(Workbook(sheets: [Worksheet(name: "Data")]))
        let rows = [["Name", "City"], ["a", "X"], ["A", "x"], ["b", "Y"], ["a", "Z"], ["b", "Y"]]
        for (r, row) in rows.enumerated() { for (k, t) in row.enumerated() { c.setInput(t, at: CellAddress(row: r, col: k)) } }
        c.setInput("=A4&B4", at: CellAddress(row: 0, col: 3))   // outside the range: stays put
        return c
    }
    private let all = CellRange(top: 0, left: 0, bottom: 5, right: 1)
    private func col(_ c: WorkbookController, _ k: Int) -> [String] { (0 ... 5).map { c.input(CellAddress(row: $0, col: k)) } }

    func testBothColumnsCompareWholeRowsIgnoringCase() {
        let c = controller()
        let out = c.removeDuplicates(all, columns: [0, 1], hasHeader: true)
        XCTAssertEqual(out.result, DuplicatesResult(removed: 2, remaining: 3))
        XCTAssertEqual(col(c, 0), ["Name", "a", "b", "a", "", ""])
        XCTAssertEqual(col(c, 1), ["City", "X", "Y", "Z", "", ""])
        XCTAssertEqual(c.input(CellAddress(row: 0, col: 3)), "=A4&B4", "cells outside the range are left alone")
    }

    func testOneColumnKeepsTheFirstOfEachAndIsOneUndoStep() {
        let c = controller()
        let out = c.removeDuplicates(all, columns: [0], hasHeader: true)
        XCTAssertEqual(out.result?.removed, 3)
        XCTAssertEqual(col(c, 0), ["Name", "a", "b", "", "", ""])
        XCTAssertEqual(col(c, 1), ["City", "X", "Y", "", "", ""])
        c.undo()
        XCTAssertEqual(col(c, 0), ["Name", "a", "A", "b", "a", "b"])
    }

    func testWithoutHeaderTheFirstRowIsCompared() {
        let c = controller()
        let out = c.removeDuplicates(CellRange(top: 1, left: 0, bottom: 5, right: 0), columns: [0], hasHeader: false)
        XCTAssertEqual(out.result?.remaining, 2)
    }

    func testNothingToRemoveChangesNothingAndMakesNoUndoStep() {
        let c = controller()
        let out = c.removeDuplicates(CellRange(top: 3, left: 0, bottom: 4, right: 1), columns: [0, 1], hasHeader: false)
        XCTAssertEqual(out.result?.removed, 0)
        c.undo()   // would undo the setup input, not a no-op "removal"
        XCTAssertEqual(c.input(CellAddress(row: 0, col: 3)), "")
    }

    func testProblemsAreReported() {
        let c = controller()
        XCTAssertEqual(c.removeDuplicates(all, columns: [], hasHeader: true).problem, .noColumns)
        XCTAssertEqual(c.removeDuplicates(all, columns: [5], hasHeader: true).problem, .columnOutside)
        XCTAssertEqual(c.removeDuplicates(CellRange(top: 0, left: 0, bottom: 0, right: 1), columns: [0], hasHeader: true).problem, .nothingToCheck)
    }

    func testAProtectedSheetRefuses() {
        let c = controller()
        c.sheet.keptElements = [("sheetProtection", "<sheetProtection sheet=\"1\"/>")]
        _ = c.removeDuplicates(all, columns: [0, 1], hasHeader: true)
        XCTAssertEqual(col(c, 0), ["Name", "a", "A", "b", "a", "b"])
    }

    func testDialogUntickingAColumnChangesWhatIsRemoved() {
        let c = controller(); var said: [String] = []; var closed = 0
        c.onCommand = { if case .status(let m) = $0 { said.append(m) } }
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
            home: RemoveDuplicatesDialog(controller: c, range: all, hasHeader: true, onClose: { closed += 1 }), title: "T"), size: Size(1280, 800))
        addTeardownBlock { ui.replace(with: SizedBox(width: 1, height: 1)) }
        XCTAssertTrue(ui.has(text: "Name")); XCTAssertTrue(ui.has(text: "City"))
        XCTAssertTrue(ui.tap(id: "dup-col-1"))
        ui.press(.enter)
        XCTAssertEqual(closed, 1)
        XCTAssertEqual(col(c, 0), ["Name", "a", "b", "", "", ""])
        XCTAssertEqual(said.last, "3 duplicate values found and removed; 2 unique values remain.")
    }

    func testDialogWithNoColumnStaysOpen() {
        let c = controller(); var closed = 0
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
            home: RemoveDuplicatesDialog(controller: c, range: all, hasHeader: true, onClose: { closed += 1 }), title: "T"), size: Size(1280, 800))
        addTeardownBlock { ui.replace(with: SizedBox(width: 1, height: 1)) }
        XCTAssertTrue(ui.tap(id: "dup-unselect-all"))
        ui.press(.enter)
        XCTAssertEqual(closed, 0)
        XCTAssertTrue(ui.texts().contains { $0.containsSubstring("at least one column") })
    }
}
