// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-SE-1: multi-range selection (Ctrl/Cmd+click) and Go To Special.

import XCTest
@testable import OfficeApp
import Flutter
import FlutterSwiftBridge

final class SheetsMultiRangeTests: XCTestCase {
    private func a(_ s: String) -> CellAddress { CellAddress(s)! }
    private func r(_ s: String) -> CellRange {
        let p = s.split(separator: ":").map(String.init)
        return p.count == 1 ? CellRange(a(p[0])) : CellRange(a(p[0]), a(p[1]))
    }
    private func controller(_ cells: [String: String]) -> WorkbookController {
        let c = WorkbookController()
        c.load(Workbook(sheets: [Worksheet(name: "S")]))
        for (k, v) in cells.sorted(by: { $0.key < $1.key }) { c.setInputs([(a(k), v)]) }
        return c
    }

    func testAddRangeKeepsTheOthersAndAPlainClickDropsThem() {
        let c = controller([:])
        c.select(range: r("A1:B2"))
        c.addRange(r("D4"))
        c.select(a("E6"), extend: true)          // a drag or Shift+click grows the newest range only
        XCTAssertEqual(c.selectedRanges, [r("A1:B2"), r("D4:E6")])
        XCTAssertEqual(c.active, a("D4"))
        c.select(a("C3"))
        XCTAssertEqual(c.selectedRanges, [r("C3")])
    }

    func testFormattingGoesToEveryRangeAsOneUndo() {
        let c = controller(["A1": "1", "C3": "2"])
        c.select(range: r("A1"))
        c.addRange(r("C3:C4"))
        c.toggleStyle(\.bold)
        for k in ["A1", "C3", "C4"] { XCTAssertTrue(c.style(at: a(k)).bold, k) }
        XCTAssertFalse(c.style(at: a("B2")).bold)
        c.undo()
        for k in ["A1", "C3", "C4"] { XCTAssertFalse(c.style(at: a(k)).bold, k) }
        // Undo brings back the whole selection the edit was made on, as Excel's does.
        XCTAssertEqual(c.selectedRanges, [r("A1"), r("C3:C4")])
        XCTAssertEqual(c.active, a("C3"))
    }

    func testUndoOfDeleteRestoresTheMultiRangeSelection() {
        let c = controller(["A1": "1", "C1": "3"])
        c.select(range: r("A1"))
        c.addRange(r("C1"))
        c.clearContents()
        c.select(a("E5"))
        c.undo()
        XCTAssertEqual(c.selectedRanges, [r("A1"), r("C1")])
    }

    func testDeleteClearsEveryRange() {
        let c = controller(["A1": "1", "B1": "2", "C1": "3"])
        c.select(range: r("A1"))
        c.addRange(r("C1"))
        c.clearContents()
        XCTAssertNil(c.sheet.cells[a("A1")])
        XCTAssertEqual(c.sheet.cells[a("B1")]?.input, "2")
        XCTAssertNil(c.sheet.cells[a("C1")])
        c.undo()
        XCTAssertEqual(c.sheet.cells[a("C1")]?.input, "3")
    }

    func testRectanglesJoinRowsAndRuns() {
        let cells: Set<CellAddress> = [a("A1"), a("B1"), a("A2"), a("B2"), a("D2"), a("A4")]
        XCTAssertEqual(WorkbookController.rectangles(cells), [r("A1:B2"), r("D2"), r("A4")])
    }

    func testConstantsAndFormulasByValueKind() {
        let c = controller(["A1": "1", "A2": "hi", "A3": "TRUE", "B1": "=A1+1", "B2": "=1/0"])
        var o = GoToSpecialOptions()
        o.kind = .constants
        XCTAssertNil(c.goToSpecial(o))
        XCTAssertEqual(Set(c.selectedRanges), [r("A1:A3")])
        o.text = false
        c.select(a("A1"))
        XCTAssertNil(c.goToSpecial(o))
        XCTAssertEqual(Set(c.selectedRanges), [r("A1"), r("A3")])
        o = GoToSpecialOptions(); o.kind = .formulas; o.numbers = false
        c.select(a("A1"))
        XCTAssertNil(c.goToSpecial(o))
        XCTAssertEqual(c.selectedRanges, [r("B2")])
        XCTAssertEqual(c.active, a("B2"))
    }

    func testBlanksSearchTheSelectionOrTheUsedRange() {
        let c = controller(["A1": "1", "C1": "2", "A3": "3"])
        var o = GoToSpecialOptions(); o.kind = .blanks
        c.select(a("A1"))
        XCTAssertNil(c.goToSpecial(o))
        // Used range A1:C3 less A1, C1 and A3.
        XCTAssertEqual(c.selectedRanges.reduce(0) { $0 + $1.area }, 6)
        c.select(range: r("A1:B1"))
        XCTAssertNil(c.goToSpecial(o))
        XCTAssertEqual(c.selectedRanges, [r("B1")])
        c.select(range: r("A1"))
        c.addRange(r("C1"))
        XCTAssertEqual(c.goToSpecial(o), "No cells were found.")
    }

    func testNotesCurrentRegionAndLastCell() {
        let c = controller(["B2": "1", "C2": "2", "B3": "3", "F9": "x"])
        c.setNote("one", at: a("C2"))
        var o = GoToSpecialOptions(); o.kind = .notes
        c.select(a("A1"))
        XCTAssertNil(c.goToSpecial(o))
        XCTAssertEqual(c.selectedRanges, [r("C2")])
        o.kind = .currentRegion
        c.select(a("B2"))
        XCTAssertNil(c.goToSpecial(o))
        XCTAssertEqual(c.selection, r("B2:C3"))
        o.kind = .lastCell
        XCTAssertNil(c.goToSpecial(o))
        XCTAssertEqual(c.active, a("F9"))
    }

    func testVisibleCellsOnlySkipsHiddenRows() {
        let c = controller([:])
        c.sheet.hiddenRows.insert(2)
        c.select(range: r("A1:B5"))
        var o = GoToSpecialOptions(); o.kind = .visibleOnly
        XCTAssertNil(c.goToSpecial(o))
        XCTAssertEqual(Set(c.selectedRanges), [r("A1:B2"), r("A4:B5")])
    }

    /// In the Sheets window at the Mac driver's size: Go To Special opens from Home, Notes + OK selects the notes;
    /// SCREEN_MARKS_DIR writes the marks and cell centres a Mac script clicks.
    func testGoToSpecialDialogInTheShell() {
        let size = Size(1440, 932)
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
            home: SheetsShell(initialPath: nil, onSwitch: { _, _ in }), title: "Test"), size: size)
        addTeardownBlock { ui.replace(with: SizedBox(width: 1, height: 1)) }
        guard let shell = ui.state(SheetsShellState.self) else { return XCTFail("no shell") }
        let wb = shell.wb
        for row in 0 ..< 8 { for col in 0 ..< 5 { wb.setInputs([(CellAddress(row: row, col: col), String(row + 1))]) } }
        wb.setNote("one", at: a("B2")); wb.setNote("two", at: a("D6"))
        ui.pump()
        var lines = ScreenMarks.lines(root: ui.elements().first, view: size)
        if let g = shell._grid {
            for k in ["A1", "B2", "C3", "D4", "D6", "E8", "B5"] {
                let c = g.global(g.rect(a(k)).center)
                lines.append("cell\t\(k)\t\(c.dx) \(c.dy)\t0 0")
            }
        }
        XCTAssertTrue(ui.tap(text: "Go To Special…")); ui.pump()
        XCTAssertTrue(ui.has(id: "gts-0"))
        XCTAssertEqual(ui.overflowingFlexes(), 0)
        lines += ["# Go To Special open"] + ScreenMarks.lines(root: ui.elements().first, view: size)
        if let dir = ProcessInfo.processInfo.environment["SCREEN_MARKS_DIR"], !dir.isEmpty {
            FileManager.default.createFile(atPath: dir + "/sheets-gotospecial-1440x932.txt", contents: Data((lines.joined(separator: "\n") + "\n").utf8))
        }
        ui.tap(id: "gts-0"); ui.pump()
        ui.tap(text: "OK"); ui.pump()
        XCTAssertFalse(ui.has(id: "gts-0"))
        XCTAssertEqual(Set(wb.selectedRanges), [r("B2"), r("D6")])
    }
}
