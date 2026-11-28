import XCTest
@testable import OfficeApp

/// A cut and paste moves what the cells carry with them, as Excel does: notes, merged cells and their place in
/// validation and conditional format rules; formulas that read the moved cells follow them.
final class SheetsCutPasteTests: XCTestCase {
    private func a(_ s: String) -> CellAddress { CellAddress(s)! }
    private func r(_ s: String) -> CellRange { CellRange(s)! }
    private func book(_ names: [String] = ["Data"]) -> WorkbookController {
        let c = WorkbookController()
        c.load(Workbook(sheets: names.map { Worksheet(name: $0) }))
        c.setInput("2", at: a("A1")); c.setInput("=A1*10", at: a("B1"))
        c.setInput("5", at: a("A2")); c.setInput("=A2+1", at: a("G1"))
        return c
    }
    private func roundTrip(_ c: WorkbookController) throws -> WorkbookController {
        let c2 = WorkbookController(); c2.load(try Xlsx.read(try Xlsx.write(c.book))); return c2
    }
    private func dress(_ c: WorkbookController) {
        c.setNote("check this", at: a("A1"))
        XCTAssertNil(c.setValidation(ValidationRule(ranges: [r("A1:A3")], type: "custom", op: "between", formula1: nil, formula2: nil,
                                                    allowBlank: true, refuses: true, arrow: true, errorTitle: nil, error: nil),
                                     formula1: "A1<B1"))
        XCTAssertNil(c.addConditionalFormat(CFSpec(kind: .expression("A1>1"), look: DxfStyle(fill: 0xFFFFC7CE)), on: [r("A1:A9")]))
        c.select(range: r("A3:B3"), active: a("A3")); c.merge(.cells)
    }

    func testACutMovesNotesValidationConditionalFormatsAndMerges() throws {
        let c = book()
        dress(c)
        // The target's own (as the plain paste lab): a note, a rule and validation where the block lands.
        c.setNote("old", at: a("E2"))
        XCTAssertNil(c.addConditionalFormat(CFSpec(kind: .expression("D1<10"), look: DxfStyle(fill: 0xFFC6EFCE)), on: [r("D1:D9")]))
        XCTAssertNil(c.setValidation(ValidationRule(ranges: [r("E1")], type: "whole", op: "between", formula1: nil, formula2: nil,
                                                    allowBlank: true, refuses: true, arrow: true, errorTitle: nil, error: nil),
                                     formula1: "1", formula2: "9"))
        c.select(range: r("A1:B3"), active: a("A1"))
        let clip = c.clip(cut: true, text: "")
        c.select(a("D1")); c.paste(clip)
        func check(_ c: WorkbookController) {
            XCTAssertNil(c.sheet.cells[a("A1")])
            XCTAssertEqual(c.sheet.cells[a("E1")]?.formula.map(Formula.text), "=D1*10")
            XCTAssertEqual(c.sheet.cells[a("G1")]?.formula.map(Formula.text), "=D2+1", "a reader of a moved cell follows it")
            XCTAssertEqual(c.note(at: a("D1"))?.body, "check this")
            XCTAssertNil(c.note(at: a("A1")), "the note went with its cell")
            XCTAssertNil(c.note(at: a("E2")), "the landing cells' own notes go")
            XCTAssertEqual(c.validationRules(over: r("D1")).first?.ranges, [r("D1:D3")])
            XCTAssertEqual(c.validationRules(over: r("D1")).first?.formula1.map(Formula.print), "D1<E1")
            XCTAssertTrue(c.validationRules(over: r("A1:A3")).isEmpty)
            XCTAssertTrue(c.validationRules(over: r("E1")).isEmpty, "E1's own rule goes")
            // The block's rule keeps its cells outside the block and gains the moved ones, in that order (Excel's
            // "A4:A9,D1:D3"); the target's own rule stays whole on a cut, so D1:D3 sit under both (the cut lab).
            XCTAssertEqual(c.conditionalRules(over: r("A5")).first?.ranges, [r("A4:A9"), r("D1:D3")])
            XCTAssertEqual(c.conditionalRules(over: r("D5")).first?.ranges, [r("D1:D9")])
            XCTAssertEqual(c.conditionalRules(over: r("D2")).count, 2)
            let moved = c.sheet.keptElements.first { $0.name == "conditionalFormatting" && $0.text.containsSubstring("A4:A9") }?.text ?? ""
            XCTAssertTrue(moved.containsSubstring("<formula>A4&gt;1</formula>"), moved)
            XCTAssertTrue(c.sheet.merges.contains(r("D3:E3")))
            XCTAssertFalse(c.sheet.merges.contains(r("A3:B3")))
        }
        check(c)
        check(try roundTrip(c))
        c.undo()
        XCTAssertEqual(c.note(at: a("A1"))?.body, "check this")
        XCTAssertEqual(c.note(at: a("E2"))?.body, "old")
        XCTAssertTrue(c.sheet.merges.contains(r("A3:B3")))
        XCTAssertEqual(c.conditionalRules(over: r("A1")).first?.ranges, [r("A1:A9")])
        XCTAssertEqual(c.validationRules(over: r("A1")).first?.ranges, [r("A1:A3")])
        XCTAssertEqual(c.sheet.cells[a("G1")]?.formula.map(Formula.text), "=A2+1")
    }

    /// The moved rule is one rule over "A4:A9 D1:D3" whose formula is written for A4, its first area's corner, so
    /// every cell in both areas tests itself (=A4>1 at A4, D2>1 at D2).
    func testTheMovedRuleTestsEachCellInBothAreas() {
        let c = book()
        dress(c)
        c.select(range: r("A1:B3"), active: a("A1"))
        let clip = c.clip(cut: true, text: "")
        c.select(a("D1")); c.paste(clip)
        c.setInput("5", at: a("A4")); c.setInput("0", at: a("A5")); c.setInput("0", at: a("D3"))
        func fill(_ s: String) -> UInt32? { c.conditionalFormats()?.look(a(s))?.dxf.fill }
        XCTAssertNotNil(fill("A4"), "A4 is 5")
        XCTAssertNil(fill("A5"), "A5 is 0")
        XCTAssertNotNil(fill("D1"), "D1 is 2 (A1's)")
        XCTAssertNotNil(fill("D2"), "D2 is 5 (A2's)")
        XCTAssertNil(fill("D3"), "D3 is 0")
        XCTAssertNil(fill("A1"), "A1 left the rule")
    }

    func testACutFromAnotherSheetLeavesNothingBehind() throws {
        let c = book(["Data", "Two"])
        dress(c)
        c.select(range: r("A1:B3"), active: a("A1"))
        let clip = c.clip(cut: true, text: "")
        c.activeSheet = 1
        c.select(a("C2")); c.paste(clip)
        XCTAssertEqual(c.note(at: a("C2"))?.body, "check this")
        XCTAssertEqual(c.validationRules(over: r("C2")).first?.ranges, [r("C2:C4")])
        XCTAssertTrue(c.sheet.merges.contains(r("C4:D4")))
        XCTAssertEqual(c.conditionalRules(over: r("C2")).first?.ranges, [r("C2:C4")])
        c.activeSheet = 0
        XCTAssertNil(c.note(at: a("A1")))
        XCTAssertTrue(c.validationRules(over: r("A1:A3")).isEmpty)
        XCTAssertTrue(c.sheet.merges.isEmpty)
        XCTAssertEqual(c.conditionalRules(over: r("A5")).first?.ranges, [r("A4:A9")])
        XCTAssertEqual(c.sheet.cells[a("G1")]?.formula, try Formula.parse("=Two!C3+1"))
    }

    func testACutOverPartOfAMergedCellIsRefused() {
        let c = book()
        c.select(range: r("E2:F2"), active: a("E2")); c.merge(.cells)
        var said: [String] = []
        c.onCommand = { if case .status(let m) = $0 { said.append(m) } }
        c.select(range: r("A1:B2"), active: a("A1"))
        let clip = c.clip(cut: true, text: "")
        let was = c.dataRevision
        c.select(a("D1")); c.paste(clip)
        XCTAssertEqual(said, [WorkbookController.partOfAMergeMessage])
        XCTAssertEqual(c.dataRevision, was)
        XCTAssertEqual(c.sheet.cells[a("A1")]?.value, .number(2))
    }

}
