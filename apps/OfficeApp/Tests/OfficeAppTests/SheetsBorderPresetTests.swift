import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// X-FM-3: Home > Borders, Excel's presets. A preset draws on the
/// selection's edges, and each is one undo step.
final class SheetsBorderPresetTests: XCTestCase {
    private func r(_ s: String) -> CellRange {
        let p = s.split(separator: ":").map { CellAddress(String($0))! }
        return CellRange(top: p[0].row, left: p[0].col, bottom: p[1].row, right: p[1].col)
    }
    private func b(_ c: WorkbookController, _ a: String) -> CellStyle.Borders {
        guard let cell = c.sheet.cells[CellAddress(a)!] else { return .init() }
        return c.book.style(cell.style).borders
    }

    func testBottomBorderIsTheBottomRowsBottomOnly() {
        let c = WorkbookController()
        c.select(range: r("A1:B3"))
        c.applyBorders(.bottom)
        XCTAssertTrue(b(c, "A3").bottom)
        XCTAssertTrue(b(c, "B3").bottom)
        XCTAssertFalse(b(c, "A1").bottom)
        XCTAssertFalse(b(c, "A2").bottom)
        XCTAssertFalse(b(c, "A3").top)
    }

    func testOutsideBordersDrawTheOutlineAndUndoInOneStep() {
        let c = WorkbookController()
        c.setInput("x", at: CellAddress("B2")!)
        c.select(range: r("A1:C3"))
        c.applyBorders(.thickOutside)
        XCTAssertTrue(b(c, "A1").top && b(c, "A1").left)
        XCTAssertFalse(b(c, "A1").bottom || b(c, "A1").right)
        XCTAssertTrue(b(c, "C3").bottom && b(c, "C3").right)
        XCTAssertEqual(b(c, "B1").kinds["top"], "thick")
        XCTAssertEqual(b(c, "B2"), .init())                       // the inside is untouched
        c.undo()
        XCTAssertEqual(b(c, "A1"), .init())
        XCTAssertEqual(b(c, "C3"), .init())
        XCTAssertEqual(c.sheet.cells[CellAddress("B2")!]?.input, "x") // only the borders went
    }

    func testAllNoneAndTopAndDoubleBottom() {
        let c = WorkbookController()
        c.select(range: r("A1:B2"))
        c.applyBorders(.all)
        for a in ["A1", "B1", "A2", "B2"] {
            let x = b(c, a)
            XCTAssertTrue(x.top && x.left && x.bottom && x.right, a)
        }
        c.applyBorders(.none)
        XCTAssertEqual(b(c, "A1"), .init())
        c.applyBorders(.topAndDoubleBottom)
        XCTAssertTrue(b(c, "B1").top)
        XCTAssertNil(b(c, "B1").kinds["top"])                    // thin
        XCTAssertEqual(b(c, "B2").kinds["bottom"], "double")
        XCTAssertFalse(b(c, "A2").top)
        c.undo()
        XCTAssertEqual(b(c, "A1"), .init())                      // back to No Border
        c.undo()
        XCTAssertTrue(b(c, "A1").bottom)                         // back to All Borders
    }

    func testThickBottomReplacesAThinBottom() {
        let c = WorkbookController()
        c.select(range: r("A1:A1"))
        c.applyBorders(.bottom)
        c.applyBorders(.thickBottom)
        XCTAssertEqual(b(c, "A1").kinds["bottom"], "thick")
        c.applyBorders(.doubleBottom)
        XCTAssertEqual(b(c, "A1").kinds["bottom"], "double")
    }

    func testPresetsRoundTrip() throws {
        let c = WorkbookController()
        c.select(range: r("A1:C3"))
        c.applyBorders(.outside)
        c.select(range: r("E1:E2"))
        c.applyBorders(.topAndThickBottom)
        let back = WorkbookController()
        back.load(try Xlsx.read(try Xlsx.write(c.book)))
        XCTAssertTrue(b(back, "A1").top && b(back, "A1").left)
        XCTAssertTrue(b(back, "C3").bottom && b(back, "C3").right)
        XCTAssertFalse(b(back, "B2").top)
        XCTAssertTrue(b(back, "E1").top)
        XCTAssertEqual(b(back, "E2").kinds["bottom"], "thick")
    }

    /// The real Home ribbon: a preset from the Borders menu reaches the
    /// controller, and More Borders… opens Format Cells on its Border tab.
    func testHomeRibbonBordersMenu() throws {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: SheetsShell(initialPath: nil, onSwitch: { _, _ in }), title: "Test"),
                              size: Size(1440, 900))
        let wb = try XCTUnwrap(ui.state(SheetsShellState.self)).wb
        wb.select(range: r("B2:C3"))
        ui.pump()
        XCTAssertTrue(ui.tap(tip: "Borders"))
        ui.pump()
        XCTAssertTrue(ui.tap(id: "borders.Outside Borders"))
        ui.pump()
        XCTAssertTrue(b(wb, "B2").top && b(wb, "C3").right)
        XCTAssertFalse(b(wb, "B2").bottom)
        XCTAssertTrue(ui.tap(tip: "Borders"))
        ui.pump()
        XCTAssertTrue(ui.tap(id: "borders.More Borders…"))
        ui.pump()
        let d = try XCTUnwrap(ui.state(DialogShellState.self))
        XCTAssertEqual(d.selectedTab, 3)
    }
}
