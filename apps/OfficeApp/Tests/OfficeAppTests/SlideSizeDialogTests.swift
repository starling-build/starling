import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

/// Slide Size: Maximize and Ensure Fit, and the dialog that asks for them.
final class SlideSizeDialogTests: XCTestCase {
    private func settle(_ ui: WidgetTester) {
        for _ in 0 ..< 3 { ui.pump(); for cb in FrameCallbackScheduler.shared.takePostFrameCallbacks() { cb(.zero) } }
        ui.pump()
    }

    func testEnsureFitKeepsProportionsAndCentre() {
        let deck = DeckController()
        let s = deck.currentSlide.shapes[0]
        let b = s.frame
        let old = deck.slideSize
        deck.setSlideSize(Size(720, 540), scaling: .ensureFit)
        let k = min(720 / old.width, 540 / old.height)
        XCTAssertEqual(s.frame.width, b.width * k, accuracy: 0.001)
        XCTAssertEqual(s.frame.height, b.height * k, accuracy: 0.001)
        XCTAssertEqual(s.frame.left + s.frame.width / 2, (b.left + b.width / 2) * 720 / old.width, accuracy: 0.001)
        XCTAssertEqual(s.frame.top + s.frame.height / 2, (b.top + b.height / 2) * 540 / old.height, accuracy: 0.001)
    }

    func testMaximizeScalesByTheLargerRatio() {
        let deck = DeckController()
        let s = deck.currentSlide.shapes[0]
        let b = s.frame
        let old = deck.slideSize
        deck.setSlideSize(Size(720, 540), scaling: .maximize)
        let k = max(720 / old.width, 540 / old.height)
        XCTAssertEqual(s.frame.width, b.width * k, accuracy: 0.001)
    }

    func testDialogAppliesTypedSizeAndChoice() {
        var got: (Size, DeckController.SlideScaling)?
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
            home: SlideSizeDialog(size: Size(960, 540), onApply: { got = ($0, $1) }, onCancel: {}), title: "T"),
            size: Size(1280, 800))
        settle(ui)
        ui.tap(id: "size.preset.0"); settle(ui)
        ui.tap(id: "size.maximize"); settle(ui)
        ui.tap(id: "size.ok"); settle(ui)
        XCTAssertEqual(got?.0, Size(720, 540))
        XCTAssertEqual(got?.1, .maximize)
    }

    func testDialogRefusesASizeOutOfRange() {
        var applied = false
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
            home: SlideSizeDialog(size: Size(960, 540), onApply: { _, _ in applied = true }, onCancel: {}), title: "T"),
            size: Size(1280, 800))
        settle(ui)
        ui.tap(id: "size.width")
        for _ in 0 ..< 10 { ui.press(.backspace) }
        ui.type("100"); settle(ui)
        ui.tap(id: "size.ok"); settle(ui)
        XCTAssertFalse(applied)
    }
}
