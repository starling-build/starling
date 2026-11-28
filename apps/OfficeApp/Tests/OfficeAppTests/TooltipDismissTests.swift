import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// A tooltip goes away when its control is clicked (Reject Change's tip stayed over the ribbon and covered Accept)
/// and when the content under it scrolls (the Shapes panel's tip stayed over a different icon).
final class TooltipDismissTests: XCTestCase {
    private let scroll = ScrollController()
    private var ui: WidgetTester!
    private var tracker: MouseTracker!

    override func setUp() {
        let rows: [Widget] = (0..<30).map { i in
            Tooltip(message: "Tip \(i)", child: SizedBox(width: 300, height: 40))
        }
        ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                    home: SingleChildScrollView(controller: scroll, child: Column(children: rows)),
                                    title: "Test"),
                          size: Size(600, 400))
        let ui = ui!
        tracker = MouseTracker({ position, _ in
            let r = HitTestResult()
            _ = ui.renderView.hitTest(r, position: position)
            return r
        })
    }

    /// Leave no tip open or pending: the list of open tips is shared by every window, and a show timer left running
    /// fires inside a later test's run loop against this test's dead overlay.
    override func tearDown() {
        hover(Offset(590, 390)); settle(0.1)
        Tooltip.dismissAllToolTips()
        settle(0.1)
        ui = nil
        tracker = nil
    }

    private func settle(_ seconds: Double = 0.05) {
        let end = Date().addingTimeInterval(seconds)
        repeat { ui.pump(); tracker.updateAllDevices(); RunLoop.main.run(until: Date().addingTimeInterval(0.02)) } while Date() < end
    }

    private func hover(_ p: Offset) { tracker.updateWithEvent(PointerHoverEvent(kind: .mouse, position: p), hitTestResult: nil) }

    /// The tips on screen: the overlay draws each as a Text holding the message as a span.
    private func shownTips() -> [String] {
        ui.elements().compactMap { e -> String? in
            guard let t = e.widget as? Text, let span = t.textSpan else { return nil }
            let s = span.toPlainText()
            return s.hasPrefix("Tip ") ? s : nil
        }
    }

    func testClickingTheControlTakesItsTipAway() {
        settle()
        hover(Offset(150, 20)); settle(1.3)
        XCTAssertEqual(shownTips(), ["Tip 0"], "the tip shows after the pointer rests")
        ui.click(at: Offset(150, 20), kind: .mouse); settle(0.1)
        XCTAssertEqual(shownTips(), [], "the click takes the tip away")
        settle(1.3)
        XCTAssertEqual(shownTips(), [], "and it does not come back while the pointer stays")
        hover(Offset(150, 60)); settle(1.3)
        XCTAssertEqual(shownTips(), ["Tip 1"], "the next control's tip still shows")
    }

    func testScrollingTakesTheTipAway() {
        settle()
        hover(Offset(150, 20)); settle(1.3)
        XCTAssertEqual(shownTips(), ["Tip 0"])
        scroll.jumpTo(100); settle(0.1)
        XCTAssertEqual(shownTips(), [], "a tip left over a different control after a scroll is gone")
    }
}
