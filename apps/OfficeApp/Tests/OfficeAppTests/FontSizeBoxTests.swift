// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import FlutterSwiftBridge
import OfficeText
@testable import OfficeApp

/// W-CH-1: the size box takes any size from 1 to 1638, in half points.
final class FontSizeBoxTests: XCTestCase {
    func testParse() {
        XCTAssertEqual(FontSizeBox.parse("10.5"), 10.5)
        XCTAssertEqual(FontSizeBox.parse(" 13 "), 13)
        XCTAssertEqual(FontSizeBox.parse("12.3"), 12.5, "rounds to a half point")
        XCTAssertEqual(FontSizeBox.parse("1638"), 1638)
        XCTAssertNil(FontSizeBox.parse("1639")); XCTAssertNil(FontSizeBox.parse("0"))
        XCTAssertNil(FontSizeBox.parse("abc")); XCTAssertNil(FontSizeBox.parse(""))
    }

    func testTypingASizeAppliesItInOneUndo() {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "t"))
        let c = ui.state(OfficeShellState.self)!.session.controller
        c.insertText("hello"); c.selectAll(); ui.pump()
        XCTAssertTrue(ui.tap(id: "font-size"))
        for _ in 0..<4 { ui.press(.backspace) }
        ui.type("10.5"); ui.press(.enter)
        XCTAssertEqual(c.currentCharStyle.fontSize, 10.5)
        c.undo()
        XCTAssertNotEqual(c.currentCharStyle.fontSize, 10.5)
    }
}
