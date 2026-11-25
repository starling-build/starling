// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// U-LINK-2: the shared link card (Open, Edit, Remove).
final class LinkCardTests: XCTestCase {
    private var log: [String] = []
    private func card(_ address: String, tip: String = "") -> WidgetTester {
        log = []
        return WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: LinkCard(
            address: address, tip: tip,
            onOpen: { [unowned self] in log.append("open") }, onEdit: { [unowned self] in log.append("edit") },
            onRemove: { [unowned self] in log.append("remove") }, onClose: { [unowned self] in log.append("close") }),
            title: "T"), size: Size(1280, 200))
    }

    func testButtonsCallTheirActions() {
        let ui = card("https://a.example")
        ui.tap(id: "link-card-open"); ui.tap(id: "link-card-edit"); ui.tap(id: "link-card-remove")
        XCTAssertEqual(log, ["open", "edit", "remove"])
    }

    func testShowsTheAddressAndTheTip() {
        let ui = card("https://a.example", tip: "Our site")
        XCTAssertTrue(ui.has(text: "https://a.example")); XCTAssertTrue(ui.has(text: "Our site"))
    }

    func testAPlaceInTheDocumentIsNamedAsSuch() {
        XCTAssertTrue(card("#_Heading0").has(text: "Place in this document"))
    }
}
