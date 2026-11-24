import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

final class SlideZoomTests: XCTestCase {
    func testZoomButtonsStepFitAndPan() throws {
        let path = "/data/corpus-cache/test/corpus/pptx/decks/45545_Comment.pptx"
        guard FileManager.default.fileExists(atPath: path) else { throw XCTSkip("deck not in the corpus cache") }
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SlidesShell(initialPath: path, onSwitch: { _, _ in }), title: "Test"),
                              size: Size(1400, 800))
        let deck = try XCTUnwrap(ui.state(SlidesShellState.self)?.session.deck)
        XCTAssertTrue(deck.viewIsFit)
        // The canvas learns its size, and the status bar its percent, in post-frame callbacks.
        for _ in 0..<4 { for cb in FrameCallbackScheduler.shared.takePostFrameCallbacks() { cb(.zero) }; ui.pump() }
        let fitPercent = deck.viewPercent
        XCTAssertGreaterThan(fitPercent, 10)
        let revision = deck.revision
        XCTAssertTrue(ui.tap(id: "zoom.in"))
        XCTAssertFalse(deck.viewIsFit)
        XCTAssertGreaterThan(deck.viewPercent, fitPercent)
        XCTAssertTrue(ui.tap(id: "zoom.out"))
        XCTAssertLessThanOrEqual(deck.viewPercent, fitPercent)
        deck.setViewZoom(percent: 400)
        XCTAssertEqual(deck.viewPercent, 400)
        deck.panView(dx: 40, dy: 0)
        XCTAssertEqual(deck.viewPan.dx, 40)
        XCTAssertTrue(ui.tap(id: "zoom.fit"))
        XCTAssertTrue(deck.viewIsFit)
        XCTAssertEqual(deck.viewPan, .zero)
        XCTAssertEqual(deck.viewPercent, fitPercent)
        // Zoom is a view setting: no undo step, no document change.
        XCTAssertEqual(deck.revision, revision)
    }
}
