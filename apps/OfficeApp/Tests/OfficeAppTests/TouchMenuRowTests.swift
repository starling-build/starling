// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// What opens from the ribbon is sized for the pointer that opened it: a menu row is 44 pt after a touch, and its usual height after a mouse.

import XCTest
@testable import OfficeApp
import Flutter
import FlutterSwiftBridge

final class TouchMenuRowTests: XCTestCase {
    override func setUp() { LastPointerKind.reset(); LastPointerKind.touchSizedRows = true }
    override func tearDown() { LastPointerKind.reset(); LastPointerKind.touchSizedRows = false }

    private func rowHeight(after kind: PointerDeviceKind) -> Double {
        let menu: Widget = Align(alignment: Alignment.topLeft, child: SizedBox(width: 240, child: MenuFlyout(items: [
            MenuFlyoutItem(text: Text("Clustered Column"), onPressed: {}),
        ])))
        let first = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: SizedBox(width: 400, height: 400), title: "t"),
                                 size: Size(400, 400))
        first.pump()
        first.tap(at: Offset(390, 390), kind: kind)   // the press that opens a menu: the last input is now `kind`
        first.dispose()
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: menu, title: "t"), size: Size(400, 400))
        ui.pump()
        guard let e = ui.elements().first(where: { $0.widget is FlyoutListTile }),
              let box = e.findRenderObject() as? RenderBox else { XCTFail("no tile"); return 0 }
        return box.size.height
    }

    func testARowIsAFingerTallAfterATouch() {
        XCTAssertGreaterThanOrEqual(rowHeight(after: .touch), 44)
    }

    func testARowKeepsItsHeightAfterAMouse() {
        XCTAssertLessThan(rowHeight(after: .mouse), 36)
    }

    func testTouchSizingCanBeSwitchedOff() {
        LastPointerKind.touchSizedRows = false
        XCTAssertLessThan(rowHeight(after: .touch), 36)
    }
}
