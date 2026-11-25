import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

/// The Format Background pane: solid, gradient and picture fills, one slide or all, and the file they save to.
final class SlideFormatBackgroundTests: XCTestCase {
    private func settle(_ ui: WidgetTester) {
        for _ in 0 ..< 3 { ui.pump(); for cb in FrameCallbackScheduler.shared.takePostFrameCallbacks() { cb(.zero) } }
        ui.pump()
    }

    private func pane(_ deck: DeckController, picture: @escaping () -> Void = {}) -> WidgetTester {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: FormatBackgroundPane(deck: deck, onPicture: picture, onClose: {}), title: "Test"),
                              size: Size(1280, 800))
        settle(ui)
        return ui
    }

    private func enter(_ ui: WidgetTester, _ id: String, _ text: String) {
        ui.tap(id: id)
        for _ in 0 ..< 10 { ui.press(.backspace) }
        ui.type(text); ui.press(.enter); settle(ui)
    }

    func testSolidThenGradientFromThePane() throws {
        let deck = DeckController()
        let ui = pane(deck)
        ui.tap(id: "bg.kind.solid"); settle(ui)
        XCTAssertNotNil(deck.currentSlide.background?.color)
        enter(ui, "bg.color", "336699")
        XCTAssertEqual((deck.currentSlide.background?.color?.value ?? 0) & 0xFFFFFF, 0x336699)
        ui.tap(id: "bg.kind.gradient"); settle(ui)
        XCTAssertGreaterThanOrEqual(deck.currentSlide.background?.stops.count ?? 0, 2)
        enter(ui, "bg.stop2", "FF0000")
        XCTAssertEqual((deck.currentSlide.background?.stops.last?.color.value ?? 0) & 0xFFFFFF, 0xFF0000)
        enter(ui, "bg.angle", "45")
        XCTAssertEqual(deck.currentSlide.background?.angle ?? 0, 45, accuracy: 0.01)
        ui.tap(id: "bg.kind.theme"); settle(ui)
        XCTAssertNil(deck.currentSlide.background)
    }

    func testApplyToAllSlidesAndPictureButton() throws {
        let deck = DeckController()
        _ = deck.addSlide()
        deck.select(0)
        var asked = 0
        let ui = pane(deck, picture: { asked += 1 })
        ui.tap(id: "bg.kind.solid"); settle(ui)
        enter(ui, "bg.color", "00AA00")
        ui.tap(id: "bg.all"); settle(ui)
        XCTAssertTrue(deck.slides.allSatisfy { ($0.background?.color?.value ?? 0) & 0xFFFFFF == 0x00AA00 })
        ui.tap(id: "bg.kind.picture"); settle(ui)
        XCTAssertEqual(asked, 1)
    }

    func testGradientBackgroundSurvivesASave() throws {
        let deck = DeckController()
        deck.setBackground(FormatBackgroundPaneState.gradient(from: Color(0xFF336699)))
        let (state, _, _) = try Pptx.read(Pptx.write(deck))
        let f = try XCTUnwrap(state.slides[0].background)
        XCTAssertGreaterThanOrEqual(f.stops.count, 2)
        XCTAssertEqual(f.angle, 90, accuracy: 0.5)
    }
}
