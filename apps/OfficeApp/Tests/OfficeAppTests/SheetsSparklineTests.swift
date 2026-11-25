// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Insert > Sparklines: line, column and win/loss in a cell range, saved in the x14 extLst.

import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

final class SheetsSparklineTests: XCTestCase {
    private func book() -> WorkbookController {
        let c = WorkbookController()
        var items: [(CellAddress, String)] = []
        let rows: [[String]] = [["1", "4", "2", "5"], ["3", "-2", "6", "0"], ["2", "2", "2", "2"]]
        for (r, row) in rows.enumerated() { for (k, v) in row.enumerated() { items.append((CellAddress(row: r, col: k), v)) } }
        c.setInputs(items)
        return c
    }

    func testAddOneSparklinePerRowAndReadBack() throws {
        let c = book()
        XCTAssertNil(c.addSparklines(kind: .line, data: "A1:D3", location: "F1:F3"))
        let g = c.sparklineGroups()
        XCTAssertEqual(g.count, 1)
        XCTAssertEqual(g[0].items.map { $0.f }, ["Sheet1!A1:D1", "Sheet1!A2:D2", "Sheet1!A3:D3"])
        XCTAssertEqual(g[0].items.map { $0.cell.a1 }, ["F1", "F2", "F3"])
        // Saved and read again.
        let back = WorkbookController(); back.load(try Xlsx.read(try Xlsx.write(c.book)))
        XCTAssertEqual(back.sparklineGroups(), g)
        // Undo takes them away.
        c.undo()
        XCTAssertTrue(c.sparklineGroups().isEmpty)
    }

    func testLocationThatDoesNotFitIsRefused() {
        let c = book()
        XCTAssertEqual(c.addSparklines(kind: .line, data: "A1:D3", location: "F1:F5"), .mismatch)
        XCTAssertEqual(c.addSparklines(kind: .line, data: "A1:D3", location: "nope"), .badLocation)
        XCTAssertTrue(c.sparklineGroups().isEmpty)
    }

    func testOtherExtsStayAndOnlyTheSparklineOneChanges() {
        let other = "<ext uri=\"{78C0D931-6437-407d-A8EE-F0AAD7539E65}\" xmlns:x14=\"\(Sparklines.x14)\"><x14:conditionalFormattings/></ext>"
        var g = SparklineGroup.new(kind: .column)
        g.items = [("Sheet1!A1:D1", CellAddress("F1")!)]
        let text = Sparklines.extLst(replacing: "<extLst>" + other + "</extLst>", with: [g])!
        XCTAssertTrue(text.contains("conditionalFormattings"))
        XCTAssertTrue(text.contains("sparklineGroup "))
        XCTAssertTrue(text.contains("type=\"column\""))
        let again = Sparklines.extLst(replacing: text, with: [])!
        XCTAssertEqual(again, "<extLst>" + other + "</extLst>")
        XCTAssertNil(Sparklines.extLst(replacing: Sparklines.extLst(replacing: nil, with: [g]), with: []))
    }

    func testLineLayoutHasMarkersAndGapBreaksTheLine() {
        var g = SparklineGroup.new(kind: .line)
        g.set("high", true); g.set("low", true); g.set("markers", true)
        let s = Sparklines.layout(g, values: [1, 4, nil, 2, 5], lo: 1, hi: 5, width: 80, height: 20)
        let lines = s.filter { if case .line = $0 { return true }; return false }
        XCTAssertEqual(lines.count, 2)   // the empty cell is a gap
        let roles = s.compactMap { shape -> String? in if case .dot(_, let r) = shape { return r }; return nil }
        XCTAssertEqual(roles.filter { $0 == "colorHigh" }.count, 1)
        XCTAssertEqual(roles.filter { $0 == "colorLow" }.count, 1)
        XCTAssertEqual(roles.filter { $0 == "colorMarkers" }.count, 2)
    }

    func testColumnAndWinLossBars() {
        var g = SparklineGroup.new(kind: .column)
        g.set("negative", true)
        let cols = Sparklines.layout(g, values: [3, -2, 6], lo: -2, hi: 6, width: 60, height: 20)
        XCTAssertEqual(cols.count, 3)
        if case .bar(_, let r) = cols[1] { XCTAssertEqual(r, "colorNegative") } else { XCTFail() }
        g.kind = .winLoss
        let wl = Sparklines.layout(g, values: [1, -1, 0, 5], lo: -1, hi: 5, width: 60, height: 20)
        XCTAssertEqual(wl.count, 3)   // zero draws nothing
        if case .bar(let up, _) = wl[0], case .bar(let down, _) = wl[1] {
            XCTAssertEqual(up.height, down.height, accuracy: 0.01)   // all the same size
            XCTAssertLessThan(up.top, down.top)
        } else { XCTFail() }
    }

    func testGroupAxisUsesOneRangeForAllRows() {
        let c = book()
        c.addSparklines(kind: .column, data: "A1:D3", location: "F1:F3")
        c.updateSparklineGroup(at: CellAddress("F1")!) { $0.attrs["minAxisType"] = "group"; $0.attrs["maxAxisType"] = "group" }
        let l1 = c.sparklineLook(CellAddress("F1")!)!, l2 = c.sparklineLook(CellAddress("F2")!)!
        XCTAssertEqual(l1.lo, -2); XCTAssertEqual(l1.hi, 6)
        XCTAssertEqual(l2.lo, -2); XCTAssertEqual(l2.hi, 6)
    }

    func testClearTakesSparklinesOut() {
        let c = book()
        c.addSparklines(kind: .line, data: "A1:D3", location: "F1:F3")
        c.clearSparklines(in: CellRange(top: 1, left: 5, bottom: 1, right: 5))
        XCTAssertEqual(c.sparklineGroups()[0].items.map { $0.cell.a1 }, ["F1", "F3"])
        c.clearSparklines(in: CellRange(top: 0, left: 5, bottom: 2, right: 5))
        XCTAssertTrue(c.sparklineGroups().isEmpty)
    }

    func testWriteExcelCheckFile() throws {
        guard let dir = ProcessInfo.processInfo.environment["XCHECK_DIR"] else { return }
        let c = book()
        c.setInputs([(CellAddress("F5")!, "line"), (CellAddress("G5")!, "column"), (CellAddress("H5")!, "win/loss")])
        c.addSparklines(kind: .line, data: "A1:D3", location: "F1:F3")
        c.updateSparklineGroup(at: CellAddress("F1")!) { $0.set("markers", true); $0.set("high", true); $0.set("low", true); $0.setColor("colorHigh", rgb: 0xC00000); $0.setColor("colorSeries", rgb: 0x2F75B5) }
        c.addSparklines(kind: .column, data: "A1:D3", location: "G1:G3")
        c.updateSparklineGroup(at: CellAddress("G1")!) { $0.set("negative", true); $0.set("displayXAxis", true) }
        c.addSparklines(kind: .winLoss, data: "A1:D3", location: "H1:H3")
        try Xlsx.write(c.book).write(to: URL(fileURLWithPath: dir + "/sparklines.xlsx"))
    }
}
