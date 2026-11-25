import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// X-DA-6c: Scenario Manager.
final class SheetsScenarioTests: XCTestCase {
    private func controller() -> WorkbookController {
        let c = WorkbookController()
        c.load(Workbook(sheets: [Worksheet(name: "Plan")]))
        c.setInputs([(CellAddress("B1")!, "100"), (CellAddress("B2")!, "0.1"), (CellAddress("B3")!, "=B1*B2")])
        return c
    }
    private func num(_ c: WorkbookController, _ a: String) -> Double? { c.sheet.value(CellAddress(a)!).number }

    func testAddShowAndUndo() {
        let c = controller()
        XCTAssertNil(c.addScenario(name: "Best", comment: "good year", values: [(CellAddress("B1")!, "200"), (CellAddress("B2")!, "0.3")]))
        XCTAssertNil(c.addScenario(name: "Worst", comment: "", values: [(CellAddress("B1")!, "50"), (CellAddress("B2")!, "0.05")]))
        XCTAssertEqual(c.scenarios().map(\.name), ["Best", "Worst"])
        XCTAssertNil(c.showScenario("Best"))
        XCTAssertEqual(num(c, "B3"), 60)
        c.undo()
        XCTAssertEqual(num(c, "B3"), 10)
        XCTAssertEqual(c.scenarios().count, 2, "showing is undone alone; the scenarios stay")
    }

    func testAddAndDeleteAreOneUndoStepEach() {
        let c = controller()
        _ = c.addScenario(name: "A", comment: "", values: [(CellAddress("B1")!, "1")])
        XCTAssertNil(c.deleteScenario("A"))
        XCTAssertTrue(c.scenarios().isEmpty)
        c.undo()
        XCTAssertEqual(c.scenarios().map(\.name), ["A"])
        c.undo()
        XCTAssertTrue(c.scenarios().isEmpty)
    }

    func testRefusals() {
        let c = controller()
        XCTAssertEqual(c.addScenario(name: " ", comment: "", values: [(CellAddress("B1")!, "1")]), .noName)
        XCTAssertEqual(c.addScenario(name: "x", comment: "", values: []), .noCells)
        XCTAssertEqual(c.addScenario(name: "x", comment: "", values: [(CellAddress("B3")!, "1")]), .hasFormula("B3"))
        _ = c.addScenario(name: "Dup", comment: "", values: [(CellAddress("B1")!, "1")])
        XCTAssertEqual(c.addScenario(name: "dup", comment: "", values: [(CellAddress("B1")!, "2")]), .duplicate("dup"))
        XCTAssertEqual(c.showScenario("nope"), .notFound)
    }

    func testEditReplacesInPlace() {
        let c = controller()
        _ = c.addScenario(name: "A", comment: "old", values: [(CellAddress("B1")!, "1")])
        XCTAssertNil(c.addScenario(name: "A2", comment: "new", values: [(CellAddress("B1")!, "9"), (CellAddress("B2")!, "0.5")], replacing: "A"))
        let s = c.scenarios()
        XCTAssertEqual(s.count, 1); XCTAssertEqual(s[0].name, "A2"); XCTAssertEqual(s[0].cells.count, 2); XCTAssertEqual(s[0].comment, "new")
    }

    func testSurvivesSaveAndReload() throws {
        let c = controller()
        _ = c.addScenario(name: "Best & <more>", comment: "q\"uote", values: [(CellAddress("B1")!, "200"), (CellAddress("B2")!, "0.3")])
        if let out = ProcessInfo.processInfo.environment["SCENARIO_CHECK_OUT"] {   // the file for the Excel check
            _ = c.addScenario(name: "Worst", comment: "slow year", values: [(CellAddress("B1")!, "50"), (CellAddress("B2")!, "0.05")])
            try Xlsx.write(c.book).write(to: URL(fileURLWithPath: out))
        }
        let again = WorkbookController(); again.load(try Xlsx.read(try Xlsx.write(c.book)))
        let s = again.scenarios()
        XCTAssertEqual(s.first?.name, "Best & <more>")
        XCTAssertEqual(s.first?.comment, "q\"uote")
        XCTAssertEqual(s.first?.cells.map(\.value), ["200", "0.3"])
        XCTAssertEqual(s.first?.cells.map(\.ref), ["B1", "B2"])
    }

    func testSummaryListsEveryScenarioAndLeavesTheSheetAlone() {
        let c = controller()
        _ = c.addScenario(name: "Best", comment: "", values: [(CellAddress("B1")!, "200"), (CellAddress("B2")!, "0.3")])
        _ = c.addScenario(name: "Worst", comment: "", values: [(CellAddress("B1")!, "50"), (CellAddress("B2")!, "0.05")])
        let out = c.scenarioSummary(results: [CellAddress("B3")!])
        XCTAssertEqual(out.sheet, "Scenario Summary")
        XCTAssertEqual(c.book.sheets.count, 2)
        let s = c.sheet
        XCTAssertEqual(s.value(CellAddress("D4")!), .text("Best"))
        XCTAssertEqual(s.value(CellAddress("E4")!), .text("Worst"))
        XCTAssertEqual(s.value(CellAddress("D9")!).number, 60)      // Best: result B3
        XCTAssertEqual(s.value(CellAddress("E9")!).number, 2.5)     // Worst
        XCTAssertEqual(s.value(CellAddress("C9")!).number, 10)      // current
        c.activeSheet = 0
        XCTAssertEqual(num(c, "B1"), 100); XCTAssertEqual(num(c, "B3"), 10)
        c.undo()
        XCTAssertEqual(c.book.sheets.count, 1)
    }

    func testTheDialogAddsAndShows() {
        let c = controller()
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: ScenarioDialog(controller: c, onClose: {}), title: "T"), size: Size(1280, 800))
        addTeardownBlock { ui.replace(with: SizedBox(width: 1, height: 1)) }
        ui.pump()
        let st = ui.state(ScenarioDialogState.self)!
        st.startAdd()
        st.name.text = "Best"; st.changing.text = "B1,B2"
        st.next()
        XCTAssertEqual(st.page, .values)
        st.valueBoxes[0].text = "200"; st.valueBoxes[1].text = "0.3"
        st.save()
        XCTAssertEqual(st.page, .list)
        st.select("Best"); st.show()
        XCTAssertEqual(num(c, "B3"), 60)
    }
}
