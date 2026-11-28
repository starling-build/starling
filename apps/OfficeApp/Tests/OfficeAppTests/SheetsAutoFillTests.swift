// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-FI-1: the Auto Fill Options button and Flash Fill.

import XCTest
@testable import OfficeApp
import Flutter
import FlutterSwiftBridge

final class SheetsAutoFillTests: XCTestCase {
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
    private func inputs(_ c: WorkbookController, _ keys: [String]) -> [String] { keys.map { c.sheet.cells[a($0)]?.input ?? "" } }

    func testCopyCellsAndFillSeriesRemakeTheDragAsOneUndo() {
        let c = controller(["A1": "1", "A2": "2"])
        c.select(range: r("A1:A2"))
        c.fillSeries(to: r("A1:A5"))
        XCTAssertEqual(inputs(c, ["A3", "A4", "A5"]), ["3", "4", "5"])
        XCTAssertEqual(c.fillTicked(c.fillOptions!), .series)
        c.refill(.copy)
        XCTAssertEqual(inputs(c, ["A3", "A4", "A5"]), ["1", "2", "1"])
        XCTAssertEqual(c.fillOptions?.how, .copy)
        XCTAssertEqual(c.selection, r("A1:A5"))
        c.undo()                                  // one step back to before the drag
        XCTAssertNil(c.sheet.cells[a("A3")])
        XCTAssertNil(c.fillOptions)               // the cells changed: no button
    }

    func testFillSeriesCountsUpASingleNumber() {
        let c = controller(["B2": "5"])
        c.select(range: r("B2"))
        c.fillSeries(to: r("B2:D2"))
        XCTAssertEqual(inputs(c, ["C2", "D2"]), ["5", "5"])
        XCTAssertEqual(c.fillTicked(c.fillOptions!), .copy)
        c.refill(.series)
        XCTAssertEqual(inputs(c, ["C2", "D2"]), ["6", "7"])
    }

    func testFormattingOnlyAndWithoutFormatting() {
        let c = controller(["A1": "1", "A2": "x", "A3": "y"])
        c.select(range: r("A1")); c.toggleStyle(\.bold)
        c.select(range: r("A2")); c.toggleStyle(\.italic)
        c.select(range: r("A1"))
        c.fillSeries(to: r("A1:A3"), how: .formatsOnly)
        XCTAssertEqual(inputs(c, ["A2", "A3"]), ["x", "y"])
        XCTAssertTrue(c.style(at: a("A2")).bold)
        XCTAssertFalse(c.style(at: a("A2")).italic)
        c.undo()
        c.select(range: r("A1"))
        c.fillSeries(to: r("A1:A3"), how: .withoutFormatting)
        XCTAssertEqual(inputs(c, ["A2", "A3"]), ["1", "1"])
        XCTAssertTrue(c.style(at: a("A2")).italic)
        XCTAssertFalse(c.style(at: a("A2")).bold)
        XCTAssertFalse(c.style(at: a("A3")).bold)
    }

    func testDatesByDayWeekdayMonthAndYear() {
        let c = controller(["A1": "1/31/2026"])
        guard case .number(let d0)? = c.sheet.cells[a("A1")]?.value else { return XCTFail("not a date") }
        c.select(range: r("A1"))
        c.fillSeries(to: r("A1:A3"))
        XCTAssertEqual(c.fillOptions?.dates, true)
        XCTAssertEqual(WorkbookController.fillChoices(c.fillOptions!).map(\.0).last, "Fill Years")
        func serials() -> [Double] { ["A2", "A3"].map { c.sheet.cells[a($0)]?.value.number ?? -1 } }
        XCTAssertEqual(serials(), [d0 + 1, d0 + 2])
        c.refill(.months)
        XCTAssertEqual(serials(), [ExcelDate.serial(2026, 2, 28), ExcelDate.serial(2026, 3, 31)])
        c.refill(.years)
        XCTAssertEqual(serials(), [ExcelDate.serial(2027, 1, 31), ExcelDate.serial(2028, 1, 31)])
        // 30 Jan 2026 is a Friday: the next weekdays are Monday 2 and Tuesday 3 February.
        c.setInputs([(a("C1"), "1/30/2026")])
        c.select(range: r("C1"))
        c.fillSeries(to: r("C1:C3"), how: .weekdays)
        XCTAssertEqual(["C2", "C3"].map { c.sheet.cells[a($0)]?.value.number ?? -1 },
                       [ExcelDate.serial(2026, 2, 2), ExcelDate.serial(2026, 2, 3)])
    }

    func testFlashFillLearnsFromTheExamplesAndSkipsTheHeading() {
        let c = controller(["A1": "Name", "B1": "Short",
                            "A2": "john smith", "B2": "Smith, J.",
                            "A3": "Mary Ann Jones", "B3": "Jones, M.",
                            "A4": "ann lee", "A5": "BOB DYLAN"])
        c.select(range: r("B4"))
        XCTAssertNil(c.flashFill())
        XCTAssertEqual(inputs(c, ["B4", "B5"]), ["Lee, A.", "Dylan, B."])
        XCTAssertEqual(c.fillOptions?.changed, [a("B4"), a("B5")])
        c.undoFlashFill()
        XCTAssertNil(c.sheet.cells[a("B4")])
    }

    func testFlashFillTakesAPartOfAnEmailAndWritesText() {
        let c = controller(["A1": "john.smith@x.com", "B1": "john",
                            "A2": "mary.jones@y.org", "A3": "007.bond@mi6.uk"])
        c.select(range: r("B1"))
        XCTAssertNil(c.flashFill())
        XCTAssertEqual(inputs(c, ["B2", "B3"]), ["mary", "007"])
        if case .text = c.sheet.cells[a("B3")]?.value {} else { XCTFail("Flash Fill writes text") }
    }

    func testFlashFillWithoutAnExampleSaysSo() {
        let c = controller(["A1": "a b", "A2": "c d"])
        c.select(range: r("B1"))
        XCTAssertEqual(c.flashFill(), WorkbookController.flashFillNoPattern)
    }

    /// In the Sheets window at the Mac driver's size: a drag leaves the Auto Fill Options button, its menu remakes
    /// the fill. SCREEN_MARKS_DIR writes the marks a Mac script clicks.
    func testAutoFillOptionsButtonInTheShell() {
        let size = Size(1440, 932)
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
            home: SheetsShell(initialPath: nil, onSwitch: { _, _ in }), title: "Test"), size: size)
        addTeardownBlock { ui.replace(with: SizedBox(width: 1, height: 1)) }
        guard let shell = ui.state(SheetsShellState.self), let g = shell._grid else { return XCTFail("no shell") }
        let wb = shell.wb
        wb.setInputs([(a("A1"), "1"), (a("A2"), "2")])
        wb.select(range: r("A1:A2"))
        wb.fillSeries(to: r("A1:A6"))
        ui.pump()
        guard let b = g.pasteButton() else { return XCTFail("no Auto Fill Options button") }
        var lines = ScreenMarks.lines(root: ui.elements().first, view: size)
        let at = g.global(b.center)
        lines.append("button\tAuto Fill Options\t\(at.dx) \(at.dy)\t0 0")
        for k in ["A1", "A2", "B1", "B2", "B3", "B4"] {
            let p = g.global(g.rect(a(k)).center)
            lines.append("cell\t\(k)\t\(p.dx) \(p.dy)\t0 0")
        }
        ui.tap(at: at); ui.pump()
        XCTAssertTrue(ui.has(text: "Copy Cells"))
        lines += ["# Auto Fill Options open"] + ScreenMarks.lines(root: ui.elements().first, view: size)
        if let dir = ProcessInfo.processInfo.environment["SCREEN_MARKS_DIR"], !dir.isEmpty {
            FileManager.default.createFile(atPath: dir + "/sheets-autofill-1440x932.txt", contents: Data((lines.joined(separator: "\n") + "\n").utf8))
        }
        ui.tap(text: "Copy Cells"); ui.pump()
        XCTAssertEqual(wb.sheet.cells[a("A3")]?.input, "1")
    }
}
