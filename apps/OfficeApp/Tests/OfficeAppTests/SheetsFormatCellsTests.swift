// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// X-FM-1: the Format Cells dialog changes only the fields the user touched, in one undo step.
final class SheetsFormatCellsTests: XCTestCase {
    func testOnlyTheChangedFieldApplies() {
        let c = WorkbookController()
        let a = CellAddress("A1")!, b = CellAddress("B1")!
        c.setInput("1", at: a); c.setInput("2", at: b)
        c.select(a); c.setStyle { $0.fontName = "Arial" }
        c.select(b); c.setStyle { $0.fontName = "Courier New" }
        c.select(range: CellRange(a, b), active: a)
        c.formatCells(CellFormatEdit(numberFormat: .set("0.00")))
        XCTAssertEqual(c.style(at: a).numberFormat, "0.00")
        XCTAssertEqual(c.style(at: b).numberFormat, "0.00")
        XCTAssertEqual(c.style(at: a).fontName, "Arial")
        XCTAssertEqual(c.style(at: b).fontName, "Courier New")
    }

    func testManyFieldsAreOneUndoStep() {
        let c = WorkbookController()
        let a = CellAddress("A1")!
        c.setInput("1", at: a); c.select(a)
        c.formatCells(CellFormatEdit(numberFormat: .set("0%"), bold: .set(true), fill: .set(0xFFFF00), borderTop: .set(true)))
        XCTAssertTrue(c.style(at: a).bold)
        XCTAssertTrue(c.style(at: a).borders.top)
        c.undo()
        XCTAssertFalse(c.style(at: a).bold)
        XCTAssertEqual(c.style(at: a).numberFormat, "General")
        XCTAssertNil(c.style(at: a).fill)
        XCTAssertFalse(c.style(at: a).borders.top)
    }

    func testStyleSurvivesASave() throws {
        let c = WorkbookController()
        let a = CellAddress("A1")!, b = CellAddress("B1")!
        c.setInput("1", at: a); c.setInput("2", at: b)
        c.select(b); c.setStyle { $0.italic = true; $0.fill = 0x00FF00 }
        c.select(a)
        c.formatCells(CellFormatEdit(numberFormat: .set("0.00"), bold: .set(true), borderBottom: .set(true)))
        let back = try Xlsx.read(try Xlsx.write(c.book))
        let c2 = WorkbookController(); c2.load(back)
        XCTAssertEqual(c2.style(at: a).numberFormat, "0.00")
        XCTAssertTrue(c2.style(at: a).bold)
        XCTAssertTrue(c2.style(at: a).borders.bottom)
        XCTAssertTrue(c2.style(at: b).italic)
        XCTAssertEqual(c2.style(at: b).fill, 0x00FF00)
    }
}

/// X-FM-3: border line style and colour.
final class SheetsFormatCellsBorderTests: XCTestCase {
    func testPenAppliesToDrawnSidesAndSurvivesASave() throws {
        let c = WorkbookController()
        let a = CellAddress("A1")!, b = CellAddress("B1")!
        c.setInput("1", at: a); c.setInput("2", at: b)
        c.select(a)
        c.formatCells(CellFormatEdit(borderTop: .set(true), borderBottom: .set(true), borderKind: .set("double"), borderColor: .set(0xC00000)))
        XCTAssertEqual(c.style(at: a).borders.kinds["top"], "double")
        XCTAssertEqual(c.style(at: a).borders.colors["bottom"], 0xC00000)
        XCTAssertNil(c.style(at: a).borders.kinds["left"])
        XCTAssertFalse(c.style(at: a).borders.left)
        let c2 = WorkbookController(); c2.load(try Xlsx.read(try Xlsx.write(c.book)))
        XCTAssertEqual(c2.style(at: a).borders.kinds["top"], "double")
        XCTAssertEqual(c2.style(at: a).borders.colors["bottom"], 0xC00000)
        XCTAssertEqual(c2.style(at: b).borders, CellStyle.Borders())
    }

    func testTogglingASideLeavesAMixedPenAlone() {
        var st = CellStyle()
        st.borders.top = true; st.borders.bottom = true
        st.borders.kinds["top"] = "thick"; st.borders.kinds["bottom"] = "dashed"
        let v = CellFormatEdit.Values(st)
        var n = v; n.left = true
        let e = CellFormatEdit.between(v, n)
        XCTAssertEqual(e.borderKind, .keep)
        e.apply(to: &st)
        XCTAssertEqual(st.borders.kinds["top"], "thick")
        XCTAssertEqual(st.borders.kinds["bottom"], "dashed")
        XCTAssertTrue(st.borders.left)
    }

    func testDialogPicksLineStyleAndColour() {
        var got: CellFormatEdit?
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
            home: FormatCellsDialog(start: CellFormatEdit.Values(.plain), onApply: { got = $0 }, onClose: {}), title: "Test"), size: Size(1280, 800))
        addTeardownBlock { ui.replace(with: SizedBox(width: 1, height: 1)) }
        XCTAssertTrue(ui.tap(text: "Border"))
        XCTAssertTrue(ui.tap(id: "fc-border-bottom"))
        XCTAssertTrue(ui.tap(id: "fc-line-Dashed"))
        XCTAssertTrue(ui.tap(id: "fc-line-color-Red"))
        ui.press(.enter)
        XCTAssertEqual(got?.borderKind, .set("dashed"))
        XCTAssertEqual(got?.borderBottom, .set(true))
        XCTAssertNotNil(got?.borderColor)
    }
}

final class SheetsFormatCellsDialogTests: XCTestCase {
    private func dialog(_ applied: @escaping (CellFormatEdit) -> Void, _ closed: @escaping () -> Void) -> WidgetTester {
        let start = CellFormatEdit.Values(.plain)
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
            home: FormatCellsDialog(start: start, onApply: applied, onClose: closed), title: "Test"), size: Size(1280, 800))
        // Dispose the dialog when the test ends, so its Enter/Esc interceptor does not outlive it.
        addTeardownBlock { ui.replace(with: SizedBox(width: 1, height: 1)) }
        return ui
    }

    func testEnterAppliesOnlyWhatWasTouched() {
        var got: CellFormatEdit?
        let ui = dialog({ got = $0 }, {})
        XCTAssertTrue(ui.tap(text: "Font")); XCTAssertTrue(ui.tap(id: "fc-bold"))
        ui.press(.enter)
        XCTAssertEqual(got?.bold, .set(true))
        XCTAssertEqual(got?.italic, CellFieldEdit<Bool>.keep)
    }

    func testEscapeChangesNothing() {
        var got: CellFormatEdit?
        var closed = false
        let ui = dialog({ got = $0 }, { closed = true })
        XCTAssertTrue(ui.tap(text: "Font")); XCTAssertTrue(ui.tap(id: "fc-bold"))
        ui.press(.escape)
        XCTAssertNil(got)
        XCTAssertTrue(closed)
    }

    func testTabsAndNumberChoice() {
        var got: CellFormatEdit?
        let ui = dialog({ got = $0 }, {})
        XCTAssertTrue(ui.tap(text: "Number"))
        XCTAssertTrue(ui.tap(id: "fc-num-Percentage"))
        ui.press(.enter)
        XCTAssertEqual(got?.numberFormat, .set("0.00%"))
    }

    func testTypedCodeIsApplied() {
        var got: CellFormatEdit?
        let ui = dialog({ got = $0 }, {})
        XCTAssertTrue(ui.tap(id: "fc-num-Thousands"))
        XCTAssertTrue(ui.tap(id: "fc-num-code"))
        ui.type(";0")
        ui.press(.enter)
        XCTAssertEqual(got?.numberFormat, .set("#,##0;0"))
    }

    func testBadCodeBlocksOKUntilFixed() {
        var got: CellFormatEdit?
        var closed = false
        let ui = dialog({ got = $0 }, { closed = true })
        XCTAssertTrue(ui.tap(id: "fc-num-Thousands"))
        XCTAssertTrue(ui.tap(id: "fc-num-code"))
        ui.type("\"")
        XCTAssertTrue(ui.has(text: "A quote is not closed."))
        ui.press(.enter)
        XCTAssertNil(got); XCTAssertFalse(closed)
        ui.press(.backspace)
        ui.press(.enter)
        XCTAssertEqual(got?.numberFormat, .set("#,##0"))
    }

    func testControlKeysSetLayoutFields() {
        var got: CellFormatEdit?
        let ui = dialog({ got = $0 }, {})
        XCTAssertTrue(ui.tap(text: "Alignment"))
        XCTAssertTrue(ui.tap(id: "fc-h-Center"))
        XCTAssertTrue(ui.tap(id: "fc-wrap"))
        ui.press(.enter)
        XCTAssertEqual(got?.hAlign, .set(.center))
        XCTAssertEqual(got?.wrap, .set(true))
    }
}

final class SheetsFormatCellsShellTests: XCTestCase {
    func testTheShellOpensTheDialogAndEscapeClosesIt() {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
            home: SheetsShell(initialPath: nil, onSwitch: { _, _ in }), title: "Test"), size: Size(1280, 800))
        addTeardownBlock { ui.replace(with: SizedBox(width: 1, height: 1)) }
        guard let shell = ui.state(SheetsShellState.self) else { return XCTFail("no shell") }
        XCTAssertFalse(ui.has(id: "fc-wrap"))
        shell._openFormatCells()
        ui.pump()
        XCTAssertTrue(ui.has(id: "fc-num-Percentage"))
        ui.press(.escape)
        ui.pump()
        XCTAssertFalse(ui.has(id: "fc-num-Percentage"))
    }
}

/// X-FM-2: custom number formats.
final class SheetsCustomFormatTests: XCTestCase {
    func testWhatACodeMustNotDo() {
        XCTAssertNil(NumberFormat.problem("#,##0.00;[Red]-#,##0.00"))
        XCTAssertNil(NumberFormat.problem("0\" kg\""))
        XCTAssertNil(NumberFormat.problem("[>100]0.0;0"))
        XCTAssertNotNil(NumberFormat.problem(""))
        XCTAssertNotNil(NumberFormat.problem("0\"abc"))
        XCTAssertNotNil(NumberFormat.problem("[Red0"))
        XCTAssertNotNil(NumberFormat.problem("0]"))
        XCTAssertNotNil(NumberFormat.problem("0;0;0;@;0"))
        XCTAssertNotNil(NumberFormat.problem("0\\"))
    }

    func testCustomCodeShowsAndSurvivesASave() throws {
        let c = WorkbookController()
        let a = CellAddress("A1")!
        c.setInput("-1234.5", at: a)
        c.formatCells(CellFormatEdit(numberFormat: .set("#,##0.0;[Red](#,##0.0)")))
        XCTAssertEqual(NumberFormat.display(.number(-1234.5), c.style(at: a).numberFormat).text, "(1,234.5)")
        let c2 = WorkbookController(); c2.load(try Xlsx.read(try Xlsx.write(c.book)))
        XCTAssertEqual(c2.style(at: a).numberFormat, "#,##0.0;[Red](#,##0.0)")
        // With UI_CHECK_DIR set, also leave a workbook for the Excel check.
        if let dir = ProcessInfo.processInfo.environment["UI_CHECK_DIR"] {
            let w = WorkbookController()
            for (i, code) in ["#,##0.0;[Red](#,##0.0)", "0.00\" kg\"", "yyyy-mm-dd", "[h]:mm:ss", "# ?/?"].enumerated() {
                let at = CellAddress("A\(i + 1)")!
                w.setInput(i == 2 ? "45000" : i == 3 ? "1.5" : i == 4 ? "0.75" : "-1234.5", at: at)
                w.select(at); w.formatCells(CellFormatEdit(numberFormat: .set(code)))
            }
            try Xlsx.write(w.book).write(to: URL(fileURLWithPath: dir + "/custom-formats-xfm2.xlsx"))
        }
    }
}
