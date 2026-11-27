import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// X-DA-6c: Goal Seek finds the input that makes a formula reach a value, in one undo step.
final class SheetsGoalSeekTests: XCTestCase {
    private func controller() -> WorkbookController {
        let c = WorkbookController()
        c.load(Workbook(sheets: [Worksheet(name: "Data")]))
        c.setInputs([(CellAddress("A1")!, "3"), (CellAddress("B1")!, "=A1*A1+2*A1")])
        return c
    }

    func testFindsTheInputAndUndoPutsItBack() throws {
        let c = controller()
        let out = c.goalSeek(set: CellAddress("B1")!, to: 24, changing: CellAddress("A1")!)   // x^2+2x=24 -> x=4
        XCTAssertNil(out.problem)
        let r = try XCTUnwrap(out.result)
        XCTAssertEqual(r.value, 4, accuracy: 0.001)
        XCTAssertEqual(r.reached, 24, accuracy: 0.001)
        if case .number(let n) = c.sheet.value(CellAddress("A1")!) { XCTAssertEqual(n, 4, accuracy: 0.001) } else { XCTFail("A1 not a number") }
        c.undo()
        XCTAssertEqual(c.input(CellAddress("A1")!), "3")
        if case .number(let n) = c.sheet.value(CellAddress("B1")!) { XCTAssertEqual(n, 15, accuracy: 1e-9) } else { XCTFail() }
    }

    func testAMissLeavesTheSheetAsItWasAndTakesNoUndoStep() {
        let c = controller()
        let out = c.goalSeek(set: CellAddress("B1")!, to: -50, changing: CellAddress("A1")!)   // x^2+2x >= -1: never -50
        XCTAssertNil(out.result)
        if case .noSolution? = out.problem {} else { XCTFail("\(String(describing: out.problem))") }
        XCTAssertEqual(c.input(CellAddress("A1")!), "3")
        c.undo()
        XCTAssertEqual(c.input(CellAddress("B1")!), "", "the undo went to the setup, not a Goal Seek step")
    }

    func testRefusesWhatCannotWork() {
        let c = controller()
        XCTAssertEqual(c.goalSeek(set: CellAddress("A1")!, to: 1, changing: CellAddress("C1")!).problem, .setNotFormula)
        XCTAssertEqual(c.goalSeek(set: CellAddress("B1")!, to: 1, changing: CellAddress("B1")!).problem, .sameCell)
        c.setInputs([(CellAddress("C1")!, "=A1+1")])
        XCTAssertEqual(c.goalSeek(set: CellAddress("B1")!, to: 1, changing: CellAddress("C1")!).problem, .changingNotConstant)
    }

    func testTheDialogRunsIt() {
        let c = controller()
        var closed = false
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: GoalSeekDialog(controller: c, onClose: { closed = true }), title: "T"), size: Size(1280, 800))
        addTeardownBlock { ui.replace(with: SizedBox(width: 1, height: 1)) }
        ui.pump()
        let st = ui.state(GoalSeekDialogState.self)!
        st.setCell.text = "B1"; st.toValue.text = "24"; st.changing.text = "A1"
        st.apply()
        XCTAssertTrue(closed)
        if case .number(let n) = c.sheet.value(CellAddress("A1")!) { XCTAssertEqual(n, 4, accuracy: 0.001) } else { XCTFail() }
    }
}
