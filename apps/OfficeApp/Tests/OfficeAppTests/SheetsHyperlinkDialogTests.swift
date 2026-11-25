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

    func testEditingShowsTheCurrentLinkAndOKReportsIt() {
        var got: SheetLink?
        var closed = false
        let ui = WidgetTester(theme(HyperlinkPanel(current: .url("https://one.example"), onDone: { l, _ in got = l },
                                                   onRemove: {}, onClose: { closed = true })), size: Size(1280, 800))
        XCTAssertTrue(ui.has(text: "Edit Hyperlink"))
        XCTAssertTrue(ui.has(id: "link-remove"))
        XCTAssertTrue(ui.tap(text: "OK"))
        XCTAssertEqual(got, .url("https://one.example"))
        XCTAssertTrue(closed)
    }

    func testNewLinkHasNoRemoveAndPlaceKindIsChoosable() {
        let ui = WidgetTester(theme(HyperlinkPanel(current: nil, onDone: { _, _ in }, onRemove: nil, onClose: {})), size: Size(1280, 800))
        XCTAssertTrue(ui.has(text: "Insert Hyperlink"))
        XCTAssertFalse(ui.has(id: "link-remove"))
        XCTAssertTrue(ui.tap(id: "link-place"))
        XCTAssertTrue(ui.has(text: "Cell reference or name:"))
    }
}
