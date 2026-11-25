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

    private static let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!

    /// A deck for PowerPoint to open (STARLING_BACKGROUNDS_OUT): every kind of background, one per slide, after one Apply to All.
    func testSaveEveryKindOfBackground() throws {
        let deck = DeckController()
        for _ in 0 ..< 3 { _ = deck.addSlide() }
        deck.select(0)
        deck.setBackground(SlideFill(color: Color(0xFFF2E6D0)), all: true)
        deck.select(0); deck.setBackground(SlideFill(color: Color(0xFF336699)))
        deck.select(1); deck.setBackground(FormatBackgroundPaneState.gradient(from: Color(0xFFCC3333)))
        deck.select(2)
        var pic = SlideFill(image: ImageAttachment(data: Self.png, width: 8, height: 8))
        pic.imageAlpha = 0.6
        pic.tiled = true
        deck.setBackground(pic)
        deck.select(3); deck.setBackground(nil)
        let data = try Pptx.write(deck)
        if let out = ProcessInfo.processInfo.environment["STARLING_BACKGROUNDS_OUT"] { try data.write(to: URL(fileURLWithPath: out)) }
        let (state, _, _) = try Pptx.read(data)
        XCTAssertEqual((state.slides[0].background?.color?.value ?? 0) & 0xFFFFFF, 0x336699)
        XCTAssertGreaterThanOrEqual(state.slides[1].background?.stops.count ?? 0, 2)
        XCTAssertNotNil(state.slides[2].background?.image)
        XCTAssertEqual(state.slides[2].background?.imageAlpha ?? 1, 0.6, accuracy: 0.01)
        XCTAssertTrue(state.slides[2].background?.tiled ?? false)
        XCTAssertNil(state.slides[3].background)
    }
}
