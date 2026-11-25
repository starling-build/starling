// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-LK-1: the Insert Hyperlink dialog and what an address means.

import XCTest
@testable import OfficeApp
import Flutter
import FlutterSwiftBridge

final class SheetsHyperlinkDialogTests: XCTestCase {
    private func theme(_ home: Widget) -> Widget { FluentApp(theme: OfficeAppearance.theme(.light), home: home, title: "t") }

    func testAddressMeaning() {
        XCTAssertEqual(HyperlinkInput.link("example.com", place: false), .url("https://example.com"))
        XCTAssertEqual(HyperlinkInput.link("me@example.com", place: false), .url("mailto:me@example.com"))
        XCTAssertEqual(HyperlinkInput.link("http://a.b/c", place: false), .url("http://a.b/c"))
        XCTAssertEqual(HyperlinkInput.link(" Sheet2!A1 ", place: true), .place("Sheet2!A1"))
        XCTAssertNil(HyperlinkInput.link("  ", place: false))
    }

    private func shell() -> (WidgetTester, SheetsShellState) {
        let ui = WidgetTester(theme(SheetsShell(initialPath: nil, onSwitch: { _, _ in })), size: Size(1280, 800))
        ui.pump()
        return (ui, ui.state(SheetsShellState.self)!)
    }

    private func ctrlK(_ ui: WidgetTester) {
        let main: Int64 = KeyModifiers.primary == .meta ? 0xFFE7 : 0xFFE3
        for (t, k) in [(KeyEventType.down, main), (.down, 0x6B), (.up, 0x6B), (.up, main)] {
            _ = FocusManager.instance.dispatchKeyData(KeyData(timeStamp: 0, type: t, physical: 0, logical: k, character: nil, synthesized: false))
        }
        ui.pump()
    }

    func testCtrlKOpensTheSharedDialogAndLinksTheCell() {
        let (ui, state) = shell()
        ctrlK(ui)
        XCTAssertTrue(ui.has(id: "link-address"))
        XCTAssertFalse(ui.has(id: "link-text"), "a cell has no separate display text")
        ui.tap(id: "link-address"); ui.type("example.com")
        ui.press(.enter); ui.pump()
        XCTAssertEqual(state.wb.link(at: state.wb.active), .url("https://example.com"))
    }

    func testPlacesAreSheetsAndDefinedNamesAndPickingOneLinksToIt() {
        let (ui, state) = shell()
        state.wb.book.names["TOTALS"] = "Sheet1!$B$2:$B$9"
        let h = state.wb.hyperlinkHooks(flash: { _ in })
        XCTAssertTrue(h.places.contains { $0.kind == "Cell" })
        XCTAssertTrue(h.places.contains { $0.id == "TOTALS" && $0.kind == "Name" })
        ctrlK(ui)
        XCTAssertTrue(ui.tap(id: "link-place-TOTALS"))
        ui.press(.enter); ui.pump()
        XCTAssertEqual(state.wb.link(at: state.wb.active), .place("TOTALS"))
    }

    func testEditingALinkShowsItAndRemoveTakesItOff() {
        let (ui, state) = shell()
        state.wb.setLink(state.wb.selection, .url("https://one.example"))
        let h = state.wb.hyperlinkHooks(flash: { _ in })
        XCTAssertEqual(h.address, "https://one.example")
        XCTAssertTrue(h.canRemove)
        ctrlK(ui)
        XCTAssertTrue(ui.tap(text: "Remove Link"))
        ui.pump()
        XCTAssertNil(state.wb.link(at: state.wb.active))
    }

    func testTypedHashAddressIsAPlace() {
        let (_, state) = shell()
        let h = state.wb.hyperlinkHooks(flash: { _ in })
        XCTAssertEqual(h.apply("#Sheet1!B5", nil, "", ""), "")
        XCTAssertEqual(state.wb.link(at: state.wb.active), .place("Sheet1!B5"))
    }
}
