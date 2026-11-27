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

    /// S-VW-1: Ctrl (Cmd) and the wheel over the slide zoom a step of the ladder, away from the user in, towards out;
    /// the wheel alone still pans a zoomed slide. View state only: no undo step, no document change.
    func testCtrlWheelZoomsTheSlide() throws {
        let path = "/data/corpus-cache/test/corpus/pptx/decks/45545_Comment.pptx"
        guard FileManager.default.fileExists(atPath: path) else { throw XCTSkip("deck not in the corpus cache") }
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SlidesShell(initialPath: path, onSwitch: { _, _ in }), title: "Test"),
                              size: Size(1400, 800))
        let deck = try XCTUnwrap(ui.state(SlidesShellState.self)?.session.deck)
        for _ in 0..<4 { for cb in FrameCallbackScheduler.shared.takePostFrameCallbacks() { cb(.zero) }; ui.pump() }
        let revision = deck.revision
        let middle = try XCTUnwrap(ui.centre(id: "backdrop"))
        deck.setViewZoom(percent: 100)
        ui.scroll(at: middle, delta: Offset(0, -40), modifiers: [.control])
        XCTAssertEqual(deck.viewPercent, 125)
        ui.scroll(at: middle, delta: Offset(0, 40), modifiers: [.meta])
        XCTAssertEqual(deck.viewPercent, 100)
        ui.scroll(at: middle, delta: Offset(0, 40), modifiers: [.control])
        XCTAssertEqual(deck.viewPercent, 75)
        deck.setViewZoom(percent: 400)
        ui.scroll(at: middle, delta: Offset(0, 30))
        XCTAssertEqual(deck.viewPercent, 400)
        XCTAssertEqual(deck.viewPan.dy, -30)
        XCTAssertEqual(deck.revision, revision)
    }

    /// S-VW-1: View > Zoom (or a click on the status bar's percent) opens PowerPoint's Zoom dialog: a preset,
    /// the percent stepped, or Fit; Cancel and Esc leave the zoom alone. View state only: no undo step.
    func testZoomDialogFromTheRibbonAndTheStatusBar() throws {
        let path = "/data/corpus-cache/test/corpus/pptx/decks/45545_Comment.pptx"
        guard FileManager.default.fileExists(atPath: path) else { throw XCTSkip("deck not in the corpus cache") }
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SlidesShell(initialPath: path, onSwitch: { _, _ in }), title: "Test"),
                              size: Size(1400, 800))
        let deck = try XCTUnwrap(ui.state(SlidesShellState.self)?.session.deck)
        for _ in 0..<4 { for cb in FrameCallbackScheduler.shared.takePostFrameCallbacks() { cb(.zero) }; ui.pump() }
        let revision = deck.revision
        let fitPercent = deck.viewPercent
        XCTAssertTrue(ui.tap(text: "View"))
        XCTAssertTrue(ui.tap(id: "view.zoom"))
        XCTAssertTrue(ui.has(text: "Zoom to"))
        XCTAssertTrue(ui.tap(id: "zoomdlg.preset.200"))
        XCTAssertTrue(ui.tap(text: "OK"))
        XCTAssertFalse(ui.has(text: "Zoom to"))
        XCTAssertEqual(deck.viewPercent, 200)
        // The status bar's percent opens it too; the arrows step the percent by one.
        XCTAssertTrue(ui.tap(id: "zoom.percent"))
        XCTAssertTrue(ui.has(text: "Zoom to"))
        XCTAssertTrue(ui.tap(id: "zoomdlg.up"))
        XCTAssertTrue(ui.tap(id: "zoomdlg.up"))
        XCTAssertTrue(ui.tap(text: "OK"))
        XCTAssertEqual(deck.viewPercent, 202)
        // Cancel and Esc change nothing.
        XCTAssertTrue(ui.tap(id: "view.zoom"))
        XCTAssertTrue(ui.tap(id: "zoomdlg.preset.33"))
        XCTAssertTrue(ui.tap(text: "Cancel"))
        XCTAssertEqual(deck.viewPercent, 202)
        XCTAssertTrue(ui.tap(id: "view.zoom"))
        ui.press(.escape); ui.pump()
        XCTAssertFalse(ui.has(text: "Zoom to"))
        // Fit goes back to the window's fit.
        XCTAssertTrue(ui.tap(id: "view.zoom"))
        XCTAssertTrue(ui.tap(id: "zoomdlg.preset.0"))
        XCTAssertTrue(ui.tap(text: "OK"))
        XCTAssertTrue(deck.viewIsFit)
        XCTAssertEqual(deck.viewPercent, fitPercent)
        XCTAssertEqual(deck.revision, revision)
    }

    func testZoomDialogParsesPercent() {
        XCTAssertEqual(ZoomDialogState.parse("150"), 150)
        XCTAssertEqual(ZoomDialogState.parse(" 66 %"), 66)
        XCTAssertNil(ZoomDialogState.parse("9"))
        XCTAssertNil(ZoomDialogState.parse("401"))
        XCTAssertNil(ZoomDialogState.parse("1.5"))
    }
}
