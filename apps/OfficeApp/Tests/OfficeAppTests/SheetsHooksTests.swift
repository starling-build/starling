import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// The shared Print dialog and shortcut list wired into Sheets, and the list
/// checked against the real key handler.
final class SheetsHooksTests: XCTestCase {
    private func shell() -> (WidgetTester, SheetsShellState) {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
            home: SheetsShell(initialPath: nil, onSwitch: { _, _ in }), title: "Test"), size: Size(1280, 800))
        addTeardownBlock { ui.replace(with: SizedBox(width: 1, height: 1)) }
        return (ui, ui.state(SheetsShellState.self)!)
    }

    private func send(_ logical: Int64, _ type: KeyEventType) -> Bool {
        FocusManager.instance.dispatchKeyData(
            KeyData(timeStamp: 0, type: type, physical: 0, logical: logical, character: nil, synthesized: false))
    }

    /// Holds Ctrl (and Shift / Alt), presses `key`, and lets everything go. True when the key was handled.
    @discardableResult private func chord(_ ui: WidgetTester, _ key: UInt32, _ extra: KeyModifiers = []) -> Bool {
        var held: [Int64] = [0xFFE3]
        if extra.contains(.shift) { held.append(0xFFE1) }
        if extra.contains(.alt) { held.append(0xFFE9) }
        for m in held { _ = send(m, .down) }
        let used = send(Int64(key), .down)
        _ = send(Int64(key), .up)
        for m in held.reversed() { _ = send(m, .up) }
        ui.pump()
        return used
    }

    func testCtrlPOpensTheSharedPrintDialog() {
        let (ui, _) = shell()
        XCTAssertTrue(chord(ui, 0x70))
        XCTAssertTrue(ui.has(id: "print-copies"))
        XCTAssertTrue(ui.has(text: "Active sheet"))
        ui.press(.escape); ui.pump()
        XCTAssertFalse(ui.has(id: "print-copies"))
    }

    func testPrintOffersTheThreeOutputs() {
        let (_, state) = shell()
        let hooks = state._printHooks
        XCTAssertEqual(hooks.unit, "Sheets")
        XCTAssertEqual(hooks.outputs, ["Active sheet", "Entire workbook", "Selection (A1)"])
    }

    func testCtrlSlashOpensTheShortcutList() {
        let (ui, _) = shell()
        XCTAssertTrue(chord(ui, 0x2F))
        XCTAssertTrue(ui.has(text: "Keyboard shortcuts"))
        XCTAssertTrue(ui.has(text: "Fill down"))
        ui.tap(text: "Close"); ui.pump()
        XCTAssertFalse(ui.has(text: "Fill down"))
    }

    func testBackstageButtonOpensTheList() {
        let (ui, state) = shell()
        state.session.onShortcuts?()
        ui.pump()
        XCTAssertTrue(ui.has(text: "Fill down"))
    }

    func testEveryChordInTheListIsHandled() {
        for e in ShortcutTable.sheets {
            let (ui, _) = shell()
            XCTAssertTrue(chord(ui, e.key, e.extra), "\(e.label()) (\(e.action)) does nothing")
        }
    }

    func testNoChordWorksThatTheListHides() {
        let listed = Set(ShortcutTable.sheets.map { $0.key })
        var keys: [UInt32] = Array(0x61...0x7A) + Array(0x30...0x39)
        keys += "=-+[]\\,.'`*".unicodeScalars.map { $0.value }
        let (ui, _) = shell()
        for k in keys where !listed.contains(k) {
            if chord(ui, k) {
                XCTFail("Ctrl+\(Character(Unicode.Scalar(k)!)) works but the list does not show it")
                break
            }
        }
    }
}
