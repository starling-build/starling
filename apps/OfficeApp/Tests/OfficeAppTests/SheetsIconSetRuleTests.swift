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

    func testTheTwentySetsAreOffered() {
        XCTAssertEqual(ConditionalFormatDialogState.iconSets.count, 20)
        XCTAssertEqual(Set(ConditionalFormatDialogState.iconSets.map { $0.name }).count, 20)
    }

    func testA2010SetIsWrittenOnlyInTheExtensionAndKeepsWhatWasThere() throws {
        let c = controller()
        c.sheet.keptElements.append(("extLst", "<extLst><ext uri=\"{05C60535-1F16-4fd2-B633-F4F36F0B64E0}\" xmlns:x14=\"http://schemas.microsoft.com/office/spreadsheetml/2009/9/main\"><x14:sparklineGroups/></ext></extLst>"))
        XCTAssertNil(c.addConditionalFormat(CFSpec(kind: .iconSet("3Stars")), on: [CellRange("B1:B10")!]))
        XCTAssertNil(c.addConditionalFormat(CFSpec(kind: .iconSet("5Boxes")), on: [CellRange("C1:C10")!]))
        XCTAssertFalse(c.sheet.keptElements.contains { $0.name == "conditionalFormatting" })
        let ext = c.sheet.keptElements.filter { $0.name == "extLst" }
        XCTAssertEqual(ext.count, 1)
        XCTAssertTrue(ext[0].text.contains("x14:sparklineGroups"))
        XCTAssertTrue(ext[0].text.contains("<x14:cfRule type=\"iconSet\" priority=\"1\""))
        let again = try reopen(c)
        guard case .iconSet(let n, let th, _, _) = again.conditionalRules(over: CellRange("C3")!)[0].kind else { return XCTFail("kind") }
        XCTAssertEqual(n, "5Boxes")
        XCTAssertEqual(th.map { $0.0.value }, [20, 40, 60, 80])
        XCTAssertEqual(again.conditionalRules(over: CellRange("B1:C10")!).map { $0.priority }, [1, 2])
        XCTAssertTrue(again.sheet.keptElements.first { $0.name == "extLst" }!.text.contains("x14:sparklineGroups"))
        // Take the stars off: the boxes and the sparklines stay; it is one undo step.
        XCTAssertNil(c.clearConditionalFormats(on: [CellRange("B1:B10")!]))
        XCTAssertEqual(c.conditionalRules(over: CellRange("B1:C10")!).count, 1)
        XCTAssertTrue(c.sheet.keptElements.first { $0.name == "extLst" }!.text.contains("x14:sparklineGroups"))
        c.undo()
        XCTAssertEqual(c.conditionalRules(over: CellRange("B1:C10")!).count, 2)
    }

    func testAnExcelWrittenExtensionIsReadAndPartlyCleared() {
        let c = controller()
        let ext = "<extLst><ext uri=\"{78C0D931-6437-407d-A8EE-F0AAD7539E65}\" xmlns:x14=\"http://schemas.microsoft.com/office/spreadsheetml/2009/9/main\"><x14:conditionalFormattings><x14:conditionalFormatting xmlns:xm=\"http://schemas.microsoft.com/office/excel/2006/main\"><x14:cfRule type=\"iconSet\" priority=\"3\" id=\"{97EC5EB0-8983-415D-A3EF-7990E01C51DC}\"><x14:iconSet iconSet=\"3Triangles\"><x14:cfvo type=\"percent\"><xm:f>0</xm:f></x14:cfvo><x14:cfvo type=\"percent\"><xm:f>33</xm:f></x14:cfvo><x14:cfvo type=\"percent\"><xm:f>67</xm:f></x14:cfvo></x14:iconSet></x14:cfRule><xm:sqref>B2:B5</xm:sqref></x14:conditionalFormatting></x14:conditionalFormattings></ext></extLst>"
        c.sheet.keptElements.append(("extLst", ext))
        guard case .iconSet(let n, let th, _, let show) = c.conditionalRules(over: CellRange("B3")!)[0].kind else { return XCTFail("kind") }
        XCTAssertEqual(n, "3Triangles")
        XCTAssertEqual(th.map { $0.0.value }, [33, 67])
        XCTAssertTrue(show)
        XCTAssertNil(c.clearConditionalFormats(on: [CellRange("B2:B3")!]))
        XCTAssertEqual(c.conditionalRules(over: CellRange("B1:B10")!)[0].ranges, [CellRange("B4:B5")!])
        XCTAssertNil(c.clearConditionalFormats(on: [CellRange("B4:B5")!]))
        XCTAssertTrue(c.conditionalRules(over: CellRange("B1:B10")!).isEmpty)
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
        try Xlsx.write(c.book).write(to: URL(fileURLWithPath: dir + "/cf-icon-sets-20.xlsx"))
    }
}
