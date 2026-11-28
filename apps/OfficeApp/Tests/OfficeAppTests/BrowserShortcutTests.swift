// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// Web parity: shortcuts the browser would steal. The page keeps a Ctrl (Cmd) chord from the browser only when the
/// app says it used it, so the app's answer must be right: Save, Open, Print, Find and the formatting chords are
/// used in every app, and a chord no app binds goes back unused (the browser's then: a new tab, zoom).
final class BrowserShortcutTests: XCTestCase {
    private var testers: [WidgetTester] = []
    override func tearDown() { testers.removeAll() }

    private func mount(_ home: Widget) -> WidgetTester {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: home, title: "T"),
                              size: Size(1280, 800))
        ui.pump()
        testers.append(ui)
        return ui
    }

    private func send(_ logical: Int64, _ type: KeyEventType) -> Bool {
        FocusManager.instance.dispatchKeyData(KeyData(timeStamp: 0, type: type, physical: 0, logical: logical,
                                                      character: nil, synthesized: false))
    }

    /// Holds the primary modifier, presses `key`, lets go; whether the app used the key press.
    private func used(_ ui: WidgetTester, _ key: Character) -> Bool {
        let main: Int64 = KeyModifiers.primary == .meta ? 0xFFE7 : 0xFFE3
        _ = send(main, .down)
        let logical = Int64(key.unicodeScalars.first!.value)
        let answer = send(logical, .down)
        _ = send(logical, .up)
        _ = send(main, .up)
        // Close whatever the chord opened (a dialog, a pane), so the next starts from the document.
        _ = send(0x1001B, .down); _ = send(0x1001B, .up)
        ui.pump()
        return answer
    }

    private func check(_ app: String, _ ui: WidgetTester, used keys: String, unused: String,
                       file: StaticString = #filePath, line: UInt = #line) {
        // The unused ones first: a chord that opens a pane or a dialog moves the keyboard there.
        for key in unused { XCTAssertFalse(used(ui, key), "\(app) claims Ctrl+\(key)", file: file, line: line) }
        for key in keys { XCTAssertTrue(used(ui, key), "\(app) did not use Ctrl+\(key)", file: file, line: line) }
    }

    func testWordUsesItsShortcutsAndLeavesTheRest() {
        let ui = mount(OfficeShell(initialPath: nil, startBlank: true))
        ui.tap(at: Offset(640, 450)); ui.pump()
        check("Word", ui, used: "biuspofh", unused: "4")
    }

    func testSlidesUsesItsShortcutsAndLeavesTheRest() {
        let ui = mount(SlidesShell(initialPath: nil, startBlank: true, onSwitch: { _, _ in }))
        check("Slides", ui, used: "spo", unused: "4")
    }

    func testSheetsUsesItsShortcutsAndLeavesTheRest() {
        let ui = mount(SheetsShell(initialPath: nil, onSwitch: { _, _ in }))
        check("Sheets", ui, used: "spofhbiu", unused: "4")
    }
}
