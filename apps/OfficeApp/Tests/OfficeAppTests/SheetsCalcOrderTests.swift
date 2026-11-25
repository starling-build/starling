// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The calculation order is an implementation detail (it varies with the cells' storage order); what must not move is
// every computed value and the set of cells found circular.

import XCTest
import Foundation
@testable import OfficeApp

final class SheetsCalcOrderTests: XCTestCase {
    /// Every value and the circular cells of `b` after a full recalculation, as sorted text lines.
    private func state(_ b: Workbook) -> [String] {
        let e = CalcEngine(b)
        e.recalculate()
        var out: [String] = []
        for (si, ws) in b.sheets.enumerated() {
            for (a, c) in ws.cells { out.append("\(si)!\(a.a1) \(c.value)") }
            for (a, v) in ws.spilled { out.append("\(si)!\(a.a1) spill \(v)") }
        }
        for k in e.circular { out.append("circular \(k.sheet)!\(k.cell.a1)") }
        return out.sorted()
    }

    /// The same cells entered in different orders (so stored in different orders) give the same values and loops:
    /// chains, ranges, a loop through a range, a self-reference, names, a spill read by another cell, two sheets.
    func testValuesAndLoopsDoNotDependOnStorageOrder() {
        var cells: [(Int, String, String)] = []
        for i in 1 ... 40 {
            cells.append((0, "A\(i)", i == 1 ? "1" : "=A\(i - 1)+1"))
            cells.append((0, "B\(i)", "=SUM(A1:A\(i))+C\(i)"))
            cells.append((0, "C\(i)", i % 7 == 0 ? "=D\(i)" : "\(i)"))
            cells.append((0, "D\(i)", i % 7 == 0 ? "=SUM(B\(i):B\(i + 1))" : "=Two!A\(i)*2"))
        }
        cells += [(0, "F1", "=F1+1"), (0, "F2", "=G2"), (0, "G2", "=H2"), (0, "H2", "=SUM(F1:G2)"),
                  (0, "J1", "=SEQUENCE(5)"), (0, "J8", "=SUM(J1:J5)+K1"), (0, "K1", "=Base*2"), (0, "K2", "=SUM(Two!A1:A10)")]
        for i in 1 ... 12 { cells.append((1, "A\(i)", i % 5 == 0 ? "=Sheet1!B\(i)" : "\(i * 3)")) }
        var reference: [String]? = nil
        var seed: UInt64 = 99
        for round in 0 ..< 6 {
            var order = cells
            if round > 0 {
                for i in stride(from: order.count - 1, to: 0, by: -1) {
                    seed = seed &* 6364136223846793005 &+ 1442695040888963407
                    order.swapAt(i, Int(seed >> 33) % (i + 1))
                }
            }
            let b = Workbook()
            b.sheets.append(Worksheet(name: "Two"))
            b.names["Base"] = "Sheet1!$A$5"
            let c = WorkbookController()
            c.load(b)
            for (s, a, t) in order { c.setInputs([(CellAddress(a)!, t)], sheet: s) }
            let st = state(b)
            if let r = reference { XCTAssertEqual(st, r, "round \(round)") } else {
                reference = st
                XCTAssertTrue(st.contains("circular 0!F1"))
                XCTAssertTrue(st.contains("circular 0!H2"))
                XCTAssertFalse(st.contains { $0.hasPrefix("circular 0!A") })
            }
        }
    }

    /// With CALC_VALUES_DUMP=<dir>, writes every computed value and circular cell of the xlsx2 books to <dir>/<book>.txt,
    /// to diff between two builds (the order may differ; these must not). Not a check on its own.
    func testDumpCorpusValues() throws {
        guard let out = ProcessInfo.processInfo.environment["CALC_VALUES_DUMP"] else { throw XCTSkip("no CALC_VALUES_DUMP") }
        let dir = "/data/corpus-cache/test/corpus/xlsx2/books"
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).filter { $0.hasSuffix(".xlsx") }.sorted()
        try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        for (n, name) in names.enumerated() where n % 4 == 0 {
            guard let data = FileManager.default.contents(atPath: dir + "/" + name), data.count < 3_000_000,
                  let book = try? Xlsx.read(data) else { continue }
            try state(book).joined(separator: "\n").write(toFile: out + "/" + name + ".txt", atomically: true, encoding: .utf8)
        }
    }
}
