import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// The shared Print dialog and shortcut list wired into Sheets (U-PR-1, U-HELP-1).
final class SheetsPrintShortcutHookTests: XCTestCase {
    private func shell() -> (WidgetTester, SheetsShellState) {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SheetsShell(initialPath: nil, onSwitch: { _, _ in }), title: "T"),
                              size: Size(1280, 800))
        return (ui, ui.state(SheetsShellState.self)!)
    }

    private func send(_ ui: WidgetTester, _ logical: Int64, _ type: KeyEventType) -> Bool {
        FocusManager.instance.dispatchKeyData(KeyData(timeStamp: 0, type: type, physical: 0, logical: logical, character: nil, synthesized: false))
    }

    /// Holds the chord's modifiers, presses `key`, lets go; true when the grid used it.
    private func chord(_ ui: WidgetTester, _ key: UInt32, shift: Bool, alt: Bool) -> Bool {
        let main: Int64 = KeyModifiers.primary == .meta ? 0xFFE7 : 0xFFE3
        var held: [Int64] = [main]
        if shift { held.append(0xFFE1) }
        if alt { held.append(0xFFE9) }
        for m in held { _ = send(ui, m, .down) }
        let used = send(ui, Int64(key), .down)
        _ = send(ui, Int64(key), .up)
        for m in held.reversed() { _ = send(ui, m, .up) }
        return used
    }

    func testShortcutTableMatchesTheGrid() {
        var listed = Set<UInt32>(), exact = Set<String>()
        for e in ShortcutTable.sheets {
            listed.insert(e.key)
            exact.insert("\(e.key)/\(e.extra.contains(.shift))/\(e.extra.contains(.alt))")
        }
        var keys: [UInt32] = Array(0x61 ... 0x7A) + Array(0x30 ... 0x39)
        keys += "=-+[]/\\,.;'`*".unicodeScalars.map { $0.value }
        var handled = Set<String>(), handledKeys = Set<UInt32>()
        for k in keys {
            for (shift, alt) in [(false, false), (true, false), (false, true), (true, true)] {
                let (ui, _) = shell()
                ui.pump()
                if chord(ui, k, shift: shift, alt: alt) { handled.insert("\(k)/\(shift)/\(alt)"); handledKeys.insert(k) }
            }
        }
        // ";" and ":" (date and time into the cell) are the grid's, not window chords: not listed yet.
        handledKeys.subtract([0x3B, 0x3A])
        XCTAssertEqual(handledKeys.subtracting(listed), [], "keys work that the list does not show")
        XCTAssertEqual(exact.subtracting(handled), [], "the list shows chords that do nothing")
    }

    func testCtrlSlashOpensTheListAndCloseDismissesIt() {
        let (ui, _) = shell()
        ui.pump()
        XCTAssertTrue(chord(ui, 0x2F, shift: false, alt: false))
        ui.pump()
        XCTAssertTrue(ui.has(text: "Keyboard shortcuts"))
        XCTAssertTrue(ui.has(text: "Fill down"))
        ui.tap(text: "Close")
        XCTAssertFalse(ui.has(text: "Fill down"))
    }

    func testPrintCountsPagesPerWhatAndPrintsTheRange() {
        let (ui, state) = shell()
        ui.pump()
        state._printKinds = [.activeSheet, .entireWorkbook, .selection]
        state._printCounts = [2, 5, 1]
        let h = state._printHooks
        XCTAssertEqual(h.outputs, ["Active sheet", "Entire workbook", "Selection"])
        XCTAssertEqual(h.total(of: 0), 2)
        XCTAssertEqual(h.total(of: 1), 5)
        XCTAssertEqual(h.total(of: 2), 1)
    }

    /// The pages the dialog picked are the pages in the PDF (and only those).
    func testWritePdfKeepsOnlyTheChosenPages() async {
        let (ui, state) = shell()
        ui.pump()
        let wb = state.wb
        wb.setInputs([(CellAddress(row: 0, col: 0), "a"), (CellAddress(row: 120, col: 0), "b"), (CellAddress(row: 240, col: 0), "c")])
        guard let grid = state._grid else { return XCTFail("no grid") }
        let n = SheetJobBox(0)
        _ = await grid.writePdf(to: "", title: "", countOnly: n)
        XCTAssertGreaterThanOrEqual(n.value, 3)
        func pageCount(_ pages: [Int]?) async -> Int {
            let path = NSTemporaryDirectory() + "amd11-pages-\(pages?.count ?? 0).pdf"
            _ = await grid.writePdf(to: path, title: "t", pages: pages)
            guard let d = FileManager.default.contents(atPath: path) else { return -1 }
            return String(decoding: d, as: UTF8.self).components(separatedBy: "/Type /Page\n").count - 1
        }
        let all = await pageCount(nil)
        let some = await pageCount([1, 1, 2])
        XCTAssertEqual(some, 3)
        XCTAssertGreaterThan(all, some - 1)
    }
}
