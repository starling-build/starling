import XCTest
@testable import OfficeApp

/// X-DA-3: adding and clearing conditional formats, each one undo step, and what a save keeps.
final class SheetsConditionalFormatEditTests: XCTestCase {
    private func controller() -> WorkbookController {
        let c = WorkbookController()
        c.load(Workbook(sheets: [Worksheet(name: "Data")]))
        return c
    }
    private func range(_ s: String) -> CellRange { CellRange(s)! }
    private func reopen(_ c: WorkbookController) throws -> WorkbookController {
        let again = WorkbookController()
        again.load(try Xlsx.read(try Xlsx.write(c.book)))
        return again
    }
    private var red: DxfStyle { var d = DxfStyle(); d.fill = 0xFFC7CE; d.color = 0x9C0006; return d }

    func testAddedRuleSurvivesSaveAndHasItsLook() throws {
        let c = controller()
        XCTAssertNil(c.addConditionalFormat(CFSpec(kind: .cellIs(op: "greaterThan", "5", nil), look: red), on: [range("A1:A9")]))
        let again = try reopen(c)
        let rules = again.conditionalRules(over: range("A1"))
        XCTAssertEqual(rules.count, 1)
        guard case .cellIs(let op, _, _) = rules[0].kind else { return XCTFail("kind") }
        XCTAssertEqual(op, "greaterThan")
        XCTAssertEqual(again.book.dxfs[rules[0].dxf!].fill, 0xFFC7CE)
        XCTAssertEqual(again.book.dxfs[rules[0].dxf!].color, 0x9C0006)
    }

    func testRefusedRulesChangeNothing() {
        let c = controller()
        XCTAssertEqual(c.addConditionalFormat(CFSpec(kind: .cellIs(op: "between", "1", nil), look: red), on: [range("A1")]), .needsValue)
        XCTAssertEqual(c.addConditionalFormat(CFSpec(kind: .expression("=(("), look: red), on: [range("A1")]), .badFormula)
        XCTAssertEqual(c.addConditionalFormat(CFSpec(kind: .blanks(true)), on: [range("A1")]), .noLook)
        XCTAssertEqual(c.addConditionalFormat(CFSpec(kind: .colorScale([1]), look: red), on: [range("A1")]), .badColors)
        XCTAssertEqual(c.addConditionalFormat(CFSpec(kind: .blanks(true), look: red), on: []), .noCells)
        XCTAssertTrue(c.sheet.keptElements.isEmpty)
        XCTAssertTrue(c.book.dxfs.isEmpty)
    }

    func testEveryKindReadsBackAndUndoIsOneStep() throws {
        let c = controller()
        let kinds: [CFSpec.Kind] = [
            .cellIs(op: "between", "1", "9"), .expression("A1>B1"), .text(op: "beginsWith", "ab"), .text(op: "notContainsText", "x"),
            .blanks(true), .errors(false), .top(rank: 3, percent: false, bottom: true), .average(above: false, equal: true),
            .duplicates(unique: true), .timePeriod("thisMonth"),
            .colorScale([0xFF0000, 0xFFFF00, 0x00FF00]), .dataBar(0x638EC6), .iconSet("3Arrows")]
        for k in kinds { XCTAssertNil(c.addConditionalFormat(CFSpec(kind: k, look: red), on: [range("C2:C20")]), "\(k)") }
        let again = try reopen(c)
        XCTAssertEqual(again.conditionalRules(over: range("C2")).count, kinds.count)
        XCTAssertEqual(again.conditionalRules(over: range("C2")).map { $0.priority }, Array(1 ... kinds.count))
        c.undo()
        XCTAssertEqual(c.conditionalRules(over: range("C2")).count, kinds.count - 1)
        c.redo()
        XCTAssertEqual(c.conditionalRules(over: range("C2")).count, kinds.count)
    }

    func testClearTrimsOnlyTheClearedCells() throws {
        let c = controller()
        XCTAssertNil(c.addConditionalFormat(CFSpec(kind: .cellIs(op: "equal", "1", nil), look: red), on: [range("A1:A10")]))
        XCTAssertNil(c.addConditionalFormat(CFSpec(kind: .cellIs(op: "equal", "2", nil), look: red), on: [range("D1:D10")]))
        XCTAssertNil(c.clearConditionalFormats(on: [range("A6:A10")]))
        XCTAssertEqual(c.conditionalRules(over: range("A1:A5")).count, 1)
        XCTAssertTrue(c.conditionalRules(over: range("A6:A10")).isEmpty)
        XCTAssertEqual(c.conditionalRules(over: range("D1")).count, 1)
        XCTAssertNil(c.clearConditionalFormats(on: [range("A1:A5")]))
        XCTAssertEqual(c.sheet.keptElements.filter { $0.name == "conditionalFormatting" }.count, 1)
        c.undo()
        XCTAssertEqual(c.conditionalRules(over: range("A1:A5")).count, 1)
    }

    func testClearingTheFirstCellsMovesARelativeFormulaWithThem() {
        // Excel's lab (xcl-plainpaste, 2026-11-28): the formula is re-read from the rule's new first cell.
        let c = controller()
        XCTAssertNil(c.addConditionalFormat(CFSpec(kind: .expression("A1>5"), look: red), on: [range("A1:A10")]))
        XCTAssertNil(c.clearConditionalFormats(on: [range("A1:A3")]))
        XCTAssertTrue(c.conditionalRules(over: range("A1")).isEmpty)
        let e = c.sheet.keptElements.first { $0.name == "conditionalFormatting" }?.text ?? ""
        XCTAssertTrue(e.containsSubstring("sqref=\"A4:A10\"") && e.containsSubstring("<formula>A4&gt;5</formula>"), e)
        XCTAssertNil(c.clearConditionalFormats(on: [range("A8:A10")]))
    }

    func testARealFileKeepsItsRulesWhenOneIsAdded() throws {
        let path = "/data/corpus-cache/test/corpus/xlsx/books/conditional_formatting_cell_is.xlsx"
        guard FileManager.default.fileExists(atPath: path) else { throw XCTSkip("corpus file not in the cache") }
        let c = WorkbookController()
        c.load(try Xlsx.read(try Data(contentsOf: URL(fileURLWithPath: path))))
        let before = c.conditionalRules(over: range("A1:Z200"))
        XCTAssertFalse(before.isEmpty)
        XCTAssertNil(c.addConditionalFormat(CFSpec(kind: .duplicates(unique: false), look: red), on: [range("Z90:Z99")]))
        let again = try reopen(c)
        let after = again.conditionalRules(over: range("A1:Z200"))
        XCTAssertEqual(after.count, before.count + 1)
        for r in before { XCTAssertEqual(after.first { $0.priority == r.priority }?.dxf, r.dxf) }
    }

    /// Writes a workbook for opening in Excel by hand; does nothing unless a folder is named.
    func testWriteCheckFile() throws {
        guard let dir = ProcessInfo.processInfo.environment["STARLING_UI_CHECK_DIR"] else { throw XCTSkip("no check folder") }
        let c = controller()
        for r in 1 ... 12 { c.setInput("\(r)", at: CellAddress(row: r - 1, col: 0)); if r % 3 != 0 { c.setInput("item\(r)", at: CellAddress(row: r - 1, col: 1)) } }
        _ = c.addConditionalFormat(CFSpec(kind: .cellIs(op: "greaterThan", "8", nil), look: red), on: [range("A1:A12")])
        _ = c.addConditionalFormat(CFSpec(kind: .top(rank: 3, percent: false, bottom: true), look: red), on: [range("A1:A12")])
        _ = c.addConditionalFormat(CFSpec(kind: .text(op: "beginsWith", "item1"), look: red), on: [range("B1:B12")])
        _ = c.addConditionalFormat(CFSpec(kind: .blanks(true), look: red), on: [range("B1:B12")])
        _ = c.addConditionalFormat(CFSpec(kind: .colorScale([0xF8696B, 0xFFEB84, 0x63BE7B])), on: [range("D1:D12")])
        _ = c.addConditionalFormat(CFSpec(kind: .dataBar(0x638EC6)), on: [range("E1:E12")])
        _ = c.addConditionalFormat(CFSpec(kind: .iconSet("3Arrows")), on: [range("F1:F12")])
        _ = c.addConditionalFormat(CFSpec(kind: .expression("A1<3"), look: red), on: [range("H1:H12")])
        for r in 0 ..< 12 { for col in 3 ... 5 { c.setInput("\(r * (col - 2))", at: CellAddress(row: r, col: col)) } }
        _ = c.clearConditionalFormats(on: [range("A10:A12")])
        try Xlsx.write(c.book).write(to: URL(fileURLWithPath: dir + "/cf-add-clear.xlsx"))
    }
}
