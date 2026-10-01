// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeApp

final class SheetsDynamicArrayTests: XCTestCase {
    /// A1:B6 — Name | Score: Ann 10, Bob 30, Cid 20, Ann 40, Dee 5.
    private func table() -> WorkbookController {
        let c = WorkbookController()
        let rows = [["Name", "Score"], ["Ann", "10"], ["Bob", "30"], ["Cid", "20"], ["Ann", "40"], ["Dee", "5"]]
        var items: [(CellAddress, String)] = []
        for (r, row) in rows.enumerated() { for (k, v) in row.enumerated() { items.append((CellAddress(row: r, col: k), v)) } }
        c.setInputs(items)
        return c
    }
    private func v(_ c: WorkbookController, _ a: String) -> CellValue { c.engine.value(c.activeSheet, CellAddress(a)!) }

    func testSpillsAndReadsBack() {
        let c = table()
        c.setInputs([(CellAddress("D1")!, "=SEQUENCE(3,2,10,5)")])
        XCTAssertEqual(c.sheet.cells[CellAddress("D1")!]?.spillRange, CellRange("D1:E3"))
        XCTAssertEqual(v(c, "D1"), .number(10))
        XCTAssertEqual(v(c, "E1"), .number(15))
        XCTAssertEqual(v(c, "D3"), .number(30))
        // Other formulas read spilled cells, and the spill as a whole.
        c.setInputs([(CellAddress("G1")!, "=E3*2"), (CellAddress("G2")!, "=SUM(D1#)"), (CellAddress("G3")!, "=ROWS(D1#)")])
        XCTAssertEqual(v(c, "G1"), .number(70))
        XCTAssertEqual(v(c, "G2"), .number(10 + 15 + 20 + 25 + 30 + 35))
        XCTAssertEqual(v(c, "G3"), .number(3))
        // The spill grows: the readers follow.
        c.setInputs([(CellAddress("D1")!, "=SEQUENCE(4,2,10,5)")])
        XCTAssertEqual(v(c, "G3"), .number(4))
    }

    func testFilterSortUnique() {
        let c = table()
        c.setInputs([(CellAddress("D1")!, "=FILTER(A2:B6,B2:B6>15)")])
        XCTAssertEqual(c.sheet.cells[CellAddress("D1")!]?.spillRange, CellRange("D1:E3"))
        XCTAssertEqual([v(c, "D1"), v(c, "D2"), v(c, "D3")], [.text("Bob"), .text("Cid"), .text("Ann")])
        XCTAssertEqual(v(c, "E3"), .number(40))
        c.setInputs([(CellAddress("G1")!, "=SORT(UNIQUE(A2:A6))")])
        XCTAssertEqual([v(c, "G1"), v(c, "G2"), v(c, "G3"), v(c, "G4")], [.text("Ann"), .text("Bob"), .text("Cid"), .text("Dee")])
        c.setInputs([(CellAddress("I1")!, "=SORTBY(A2:A6,B2:B6,-1)")])
        XCTAssertEqual([v(c, "I1"), v(c, "I5")], [.text("Ann"), .text("Dee")])
        c.setInputs([(CellAddress("K1")!, "=FILTER(A2:A6,B2:B6>100)"), (CellAddress("K3")!, "=FILTER(A2:A6,B2:B6>100,\"none\")")])
        XCTAssertEqual(v(c, "K1"), .error(.calc))
        XCTAssertEqual(v(c, "K3"), .text("none"))
        // Elementwise maths in a typed formula.
        c.setInputs([(CellAddress("M1")!, "=SUM(B2:B6*2)"), (CellAddress("N1")!, "=B2:B4+1")])
        XCTAssertEqual(v(c, "M1"), .number(210))
        XCTAssertEqual(v(c, "N3"), .number(21))
    }

    func testBlockedSpill() {
        let c = table()
        c.setInputs([(CellAddress("D3")!, "in the way"), (CellAddress("D1")!, "=SEQUENCE(4)")])
        XCTAssertEqual(v(c, "D1"), .error(.spill))
        XCTAssertNil(c.sheet.spilled[CellAddress("D2")!])
        c.setInputs([(CellAddress("D3")!, "")])               // cleared: it spills
        XCTAssertEqual(v(c, "D1"), .number(1))
        XCTAssertEqual(v(c, "D4"), .number(4))
        c.setInputs([(CellAddress("D2")!, "typed over")])     // typed into it: blocked again
        XCTAssertEqual(v(c, "D1"), .error(.spill))
        XCTAssertNil(c.sheet.spilled[CellAddress("D4")!])
    }

    func testLegacyFormulasKeepImplicitIntersection() {
        let c = table()
        // A file's ordinary formula over a range picks its own row (no spill).
        var cell = Cell(input: "=B2:B6*2")
        cell.formula = try? Formula.parse("=B2:B6*2")
        c.sheet.cells[CellAddress("C3")!] = cell
        c.engine.recalculate()
        XCTAssertEqual(v(c, "C3"), .number(60))
        XCTAssertNil(c.sheet.cells[CellAddress("C3")!]?.spillRange)
    }

    func testSpillRoundTripsThroughXlsx() throws {
        let c = table()
        c.setInputs([(CellAddress("D1")!, "=SORT(B2:B6)")])
        let data = try Xlsx.write(c.book)
        let sheet = String(decoding: try XCTUnwrap(try Zip.read(data).first { $0.name == "xl/worksheets/sheet1.xml" }).data, as: UTF8.self)
        XCTAssertTrue(sheet.containsSubstring("<f t=\"array\" ref=\"D1:D5\">_xlfn.SORT(B2:B6)</f>"), sheet)
        XCTAssertTrue(sheet.containsSubstring("<c r=\"D5\"><v>40</v></c>"), sheet)
        let back = WorkbookController()
        back.load(try Xlsx.read(data))
        XCTAssertEqual(back.sheet.cells[CellAddress("D1")!]?.spillRange, CellRange("D1:D5"))
        XCTAssertEqual(back.engine.value(0, CellAddress("D5")!), .number(40))
        back.setInputs([(CellAddress("B6")!, "50")])
        XCTAssertEqual(back.engine.value(0, CellAddress("D5")!), .number(50))
    }
}

extension SheetsDynamicArrayTests {
    func testLetAndShapers() {
        let c = table()
        func e(_ f: String) -> CellValue { c.engine.evaluate(f, sheet: 0, at: CellAddress("Z1")!) }
        XCTAssertEqual(e("=LET(x,B2,y,B3,x*y+1)"), .number(301))
        XCTAssertEqual(e("=LET(total,SUM(B2:B6),total/5)"), .number(21))
        c.setInputs([
            (CellAddress("D1")!, "=VSTACK(A2:A3,A5:A6)"),
            (CellAddress("F1")!, "=TAKE(SORT(B2:B6,1,-1),2)"),
            (CellAddress("H1")!, "=CHOOSECOLS(A1:B3,2,1)"),
            (CellAddress("Q1")!, "=TOROW(B2:B4)"),
            (CellAddress("K3")!, "=WRAPROWS(SEQUENCE(5),2,0)"),
            (CellAddress("M1")!, "=TEXTSPLIT(\"a,b;c,d\",\",\",\";\")"),
            (CellAddress("O1")!, "=DROP(A1:B6,1,1)"),
        ])
        XCTAssertEqual([v(c, "D1"), v(c, "D4")], [.text("Ann"), .text("Dee")])
        XCTAssertEqual([v(c, "F1"), v(c, "F2")], [.number(40), .number(30)])
        XCTAssertEqual([v(c, "H1"), v(c, "I1"), v(c, "H2")], [.text("Score"), .text("Name"), .number(10)])
        XCTAssertEqual([v(c, "Q1"), v(c, "S1"), v(c, "M1")], [.number(10), .number(20), .text("a")])
        XCTAssertEqual([v(c, "K5"), v(c, "L5")], [.number(5), .number(0)])
        XCTAssertEqual([v(c, "N2"), v(c, "O5")], [.text("d"), .number(5)])
    }
}
