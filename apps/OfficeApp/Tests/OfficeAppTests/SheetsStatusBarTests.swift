// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-ST-1: the status bar's figures for a selection (Average, Count, Numerical Count, Min,
// Max, Sum) and the right-click choice of which ones show.

import XCTest
@testable import OfficeApp
import Flutter
import FlutterSwiftBridge

final class SheetsStatusBarTests: XCTestCase {
    private func theme(_ home: Widget) -> Widget { FluentApp(theme: OfficeAppearance.theme(.light), home: home, title: "t") }

    override func tearDown() { SheetsShellState.statusShown = [.average, .count, .sum] }

    func testSelectionStatsCarryMinAndMax() {
        let c = WorkbookController()
        c.setInputs([(CellAddress(row: 0, col: 0), "3"), (CellAddress(row: 1, col: 0), "5"),
                      (CellAddress(row: 2, col: 0), "x"), (CellAddress(row: 3, col: 0), "-2")])
        c.select(range: CellRange(top: 0, left: 0, bottom: 3, right: 0))
        let s = c.selectionStats
        XCTAssertEqual(s.min, -2)
        XCTAssertEqual(s.max, 5)
        XCTAssertEqual(s.numbers, 3)
        XCTAssertEqual(s.count, 4)
    }

    func testStatusBarShowsTheChosenFigures() throws {
        let tmp = NSTemporaryDirectory() + "status-\(ProcessInfo.processInfo.processIdentifier).xlsx"
        let c = WorkbookController()
        c.setInputs([(CellAddress(row: 0, col: 0), "3"), (CellAddress(row: 1, col: 0), "5"),
                      (CellAddress(row: 2, col: 0), "x"), (CellAddress(row: 3, col: 0), "-2")])
        try Xlsx.write(c.book).write(to: URL(fileURLWithPath: tmp))
        let ui = WidgetTester(theme(SheetsShell(initialPath: tmp, onSwitch: { _, _ in })), size: Size(1440, 932))
        ui.pump()
        let shell = try XCTUnwrap(ui.state(SheetsShellState.self))
        shell.wb.select(range: CellRange(top: 0, left: 0, bottom: 3, right: 0)); ui.pump()
        // Excel's defaults: Average, Count, Sum.
        XCTAssertEqual(shell._statusBarFigures(), ["Average: 2", "Count: 4", "Sum: 6"])
        for f: SheetsShellState.StatusFigure in [.numericalCount, .min, .max] { shell._toggleStatusFigure(f) }
        shell._toggleStatusFigure(.average); ui.pump()
        XCTAssertEqual(shell._statusBarFigures(), ["Count: 4", "Numerical Count: 3", "Min: -2", "Max: 5", "Sum: 6"])
        XCTAssertTrue(ui.has(text: "Min: -2"))
        XCTAssertFalse(ui.has(text: "Average: 2"))
        // A right click on the status bar opens the choice, ticked as shown; picking one toggles it.
        let sum = try XCTUnwrap(ui.centre(ofText: "Sum: 6"))
        ui.click(at: sum, buttons: kSecondaryButton); ui.pump()
        XCTAssertTrue(ui.has(text: "Numerical Count"))
        XCTAssertTrue(ui.has(text: "Maximum"))
        XCTAssertTrue(ui.tap(text: "Minimum")); ui.pump()
        XCTAssertFalse(SheetsShellState.statusShown.contains(.min))
        XCTAssertFalse(ui.has(text: "Min: -2"))
        // One cell: no figures.
        shell.wb.select(CellAddress(row: 0, col: 0)); ui.pump()
        XCTAssertEqual(shell._statusBarFigures(), [])
    }
}
