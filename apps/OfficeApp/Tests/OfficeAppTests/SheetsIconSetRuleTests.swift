import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// X-CF-2: Icon Sets in the Conditional Formatting dialog; every set Excel offers is written with its own thresholds.
final class SheetsIconSetRuleTests: XCTestCase {
    private func controller() -> WorkbookController {
        let c = WorkbookController()
        c.load(Workbook(sheets: [Worksheet(name: "Data")]))
        for r in 0 ..< 10 { c.setInput("\(r + 1)", at: CellAddress(row: r, col: 1)) }
        c.select(range: CellRange("B1:B10")!, active: CellAddress("B1")!)
        return c
    }
    private func reopen(_ c: WorkbookController) throws -> WorkbookController {
        let again = WorkbookController()
        again.load(try Xlsx.read(try Xlsx.write(c.book)))
        return again
    }

    func testTheDialogAddsTheChosenIconSetAndASaveKeepsIt() throws {
        let c = controller()
        var closed = false
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: ConditionalFormatDialog(controller: c, onClose: { closed = true }), title: "T"), size: Size(1280, 800))
        let st = ui.state(ConditionalFormatDialogState.self)!
        st.setKind("Icon set")
        XCTAssertFalse(st.highlights)
        st.setVariant("5Quarters")
        ui.pump()
        ui.press(.enter)
        XCTAssertTrue(closed)
        guard case .iconSet(let name, let th, _, let show) = try reopen(c).conditionalRules(over: CellRange("B3")!)[0].kind else { return XCTFail("kind") }
        XCTAssertEqual(name, "5Quarters")
        XCTAssertEqual(th.count, 4)
        XCTAssertTrue(show)
        c.undo()
        XCTAssertTrue(c.conditionalRules(over: CellRange("B1:B10")!).isEmpty)
    }

    func testEverySetIsWrittenWithExcelsThresholds() throws {
        for (_, name) in ConditionalFormatDialogState.iconSets {
            let c = controller()
            XCTAssertNil(c.addConditionalFormat(CFSpec(kind: .iconSet(name)), on: [CellRange("B1:B10")!]))
            guard case .iconSet(let n, let th, _, _) = try reopen(c).conditionalRules(over: CellRange("B1")!)[0].kind else { return XCTFail(name) }
            XCTAssertEqual(n, name)
            let want: [Double] = { switch name.first! { case "3": return [33, 67]; case "4": return [25, 50, 75]; default: return [20, 40, 60, 80] } }()
            XCTAssertEqual(th.map { $0.0.value }, want, name)
        }
    }

    /// For the Excel check: set STARLING_UI_CHECK_DIR and the book is written there.
    func testSaveForExcel() throws {
        guard let dir = ProcessInfo.processInfo.environment["STARLING_UI_CHECK_DIR"] else { throw XCTSkip("no check folder") }
        let c = WorkbookController()
        c.load(Workbook(sheets: [Worksheet(name: "Data")]))
        for (i, (_, name)) in ConditionalFormatDialogState.iconSets.enumerated() {
            for r in 0 ..< 8 { c.setInput("\(r + 1)", at: CellAddress(row: r, col: i)) }
            XCTAssertNil(c.addConditionalFormat(CFSpec(kind: .iconSet(name)), on: [CellRange(CellAddress(row: 0, col: i), CellAddress(row: 7, col: i))]))
        }
        try Xlsx.write(c.book).write(to: URL(fileURLWithPath: dir + "/cf-icon-sets.xlsx"))
    }
}
