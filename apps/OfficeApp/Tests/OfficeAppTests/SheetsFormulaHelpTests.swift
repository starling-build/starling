import XCTest
@testable import OfficeApp
import Flutter
import FlutterSwiftBridge

final class SheetsFormulaHelpTests: XCTestCase {
    func testCompletionOffersNamesAndAcceptAddsParen() {
        let t = Array("=SU")
        let c = FormulaHelp.completion(t, caret: 3, limit: 8)
        XCTAssertNotNil(c)
        XCTAssertTrue(c!.matches.contains("SUM"))
        let r = FormulaHelp.accept("SUM", in: t, from: c!.start, caret: 3)
        XCTAssertEqual(String(r.text), "=SUM(")
        XCTAssertEqual(r.caret, 5)
    }

    func testNoCompletionForPlainText() {
        XCTAssertNil(FormulaHelp.completion(Array("SU"), caret: 2, limit: 8))
    }

    func testHintTracksArgumentAcrossNesting() {
        let t = Array("=IF(A1>0,SUM(B1,")
        let h = FormulaHelp.hint(t, caret: t.count)
        XCTAssertEqual(h?.name, "SUM")
        XCTAssertEqual(h?.index, 1)
        let t2 = Array("=IF(A1>0,\"a,b\",")
        XCTAssertEqual(FormulaHelp.hint(t2, caret: t2.count)?.index, 2)
    }

    func testReferencesGetDistinctColours() {
        let refs = FormulaHelp.references(Array("=A1+B2:C3"))
        XCTAssertEqual(refs.count, 2)
        XCTAssertNotEqual(refs[0].color, refs[1].color)
        XCTAssertEqual(refs[0].range, 1 ..< 3)
    }
}

final class SheetsFormulaHelpShellTests: XCTestCase {
    func testTabAcceptsTheListedFunctionName() {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SheetsShell(initialPath: nil, onSwitch: { _, _ in }), title: "t"),
                              size: Size(1280, 800))
        let st = ui.state(SheetsShellState.self)!
        _ = st
        ui.type("=SUMI"); ui.pump()
        ui.press(.tab); ui.pump()
        ui.press(.enter); ui.pump()
        XCTAssertEqual(st.wb.input(CellAddress("A1")!), "=SUMIF()")
    }
}

final class SheetsUseInFormulaTests: XCTestCase {
    func testUseNameStartsAFormulaAndInsertsIntoOne() {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SheetsShell(initialPath: nil, onSwitch: { _, _ in }), title: "t"),
                              size: Size(1280, 800))
        let st = ui.state(SheetsShellState.self)!
        XCTAssertNil(st.wb.defineName("Rate", refersTo: "Sheet1!$A$1"))
        st.wb.onCommand?(.useName("Rate")); ui.pump()
        ui.type("+1"); ui.pump()
        st.wb.onCommand?(.useName("Rate")); ui.pump()
        ui.press(.enter); ui.pump()
        XCTAssertEqual(st.wb.input(CellAddress("A1")!), "=Rate+1Rate")
    }
}
