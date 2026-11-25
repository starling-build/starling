import XCTest
import Flutter
import FlutterSwiftBridge
import FluentSystemIcons
@testable import OfficeApp

final class ContextMenuTests: XCTestCase {
    func testRowsPutTheMiniToolbarFirstAndTrimSeparators() {
        let m = ContextMenuBuilder()
        m.separator()                       // leading: dropped
        m.item("Cut") {}
        m.separator(); m.separator()        // doubled: one
        m.item("Paste") {}
        m.separator()                       // trailing: dropped
        m.miniButton(FluentSystemIcons.textBold, "Bold") {}
        let rows = m.rows
        XCTAssertTrue(rows[0] is MiniToolbarRow)
        XCTAssertTrue(rows[1] is MenuFlyoutSeparator)
        XCTAssertEqual(rows.count, 5)
        XCTAssertFalse(rows.last is MenuFlyoutSeparator)
    }

    func testNoMiniButtonsMeansNoToolbarRow() {
        let m = ContextMenuBuilder()
        m.item("Copy") {}
        XCTAssertFalse(m.rows.contains { $0 is MiniToolbarRow })
    }

    func testAMiniButtonRunsItsAction() {
        var bolds = 0
        let m = ContextMenuBuilder()
        m.miniButton(FluentSystemIcons.textBold, "Bold") { bolds += 1 }
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: Center(child: Builder { ctx in m.rows[0].buildItem(ctx) }), title: "T"), size: Size(1280, 800))
        XCTAssertTrue(ui.tap(tip: "Bold"))
        XCTAssertEqual(bolds, 1)
        ui.dispose()
    }
}
