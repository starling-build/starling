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

    func testTextScalesWithTheShape() {
        let deck = DeckController()
        let s = deck.currentSlide.shapes[0]
        s.text!.insertText("Hello")
        var doc = s.text!.document
        doc.paragraphs[0].runs = [Run(length: 5, style: { var c = CharStyle(); c.fontSize = 40; return c }())]
        doc.paragraphs[0].style.spaceAfter = 10
        doc.paragraphs[0].style.indentLeft = 20
        s.text!.load(doc)
        let size = s.textTheme!.fontSize
        deck.setSlideSize(Size(720, 540), scaling: .ensureFit)
        let p = s.text!.document.paragraphs[0]
        XCTAssertEqual(p.runs[0].style.fontSize ?? 0, 30, accuracy: 0.001)
        XCTAssertEqual(p.style.spaceAfter, 7.5, accuracy: 0.001)
        XCTAssertEqual(p.style.indentLeft, 15, accuracy: 0.001)
        XCTAssertEqual(s.textTheme!.fontSize, size * 0.75, accuracy: 0.001)
        deck.undo()
        XCTAssertEqual(deck.slideSize, Size(960, 540))
        XCTAssertEqual(s.text!.document.paragraphs[0].runs[0].style.fontSize ?? 0, 40, accuracy: 0.001)
    }

    func testTheFilesMasterAndLayoutsScaleToo() {
        let xml = "<p:sp><p:spPr><a:xfrm><a:off x=\"1000\" y=\"2000\"/><a:ext cx=\"4000\" cy=\"600\"/></a:xfrm></p:spPr><p:txBody><a:lstStyle><a:lvl1pPr marL=\"400\" indent=\"-200\"><a:spcBef><a:spcPts val=\"1000\"/></a:spcBef><a:defRPr sz=\"2400\"/></a:lvl1pPr></a:lstStyle></p:txBody></p:sp>"
        let out = PptxWriter._scaledShapes(xml, sx: 0.5, sy: 1, k: 0.5)
        XCTAssertTrue(out.contains("<a:off x=\"500\" y=\"2150\"/>"), out)
        XCTAssertTrue(out.contains("<a:ext cx=\"2000\" cy=\"300\"/>"), out)
        XCTAssertTrue(out.contains("marL=\"200\" indent=\"-100\""), out)
        XCTAssertTrue(out.contains("<a:spcPts val=\"500\"/>"), out)
        XCTAssertTrue(out.contains("sz=\"1200\""), out)
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

/// Writes decks for the PowerPoint check: a 16:9 file taken to 4:3 both ways (STARLING_SLIDESIZE_IN, STARLING_SLIDESIZE_OUT_DIR).
final class SlideSizeCheckDeckTests: XCTestCase {
    func testSaveBothWays() throws {
        let env = ProcessInfo.processInfo.environment
        guard let input = env["STARLING_SLIDESIZE_IN"], let dir = env["STARLING_SLIDESIZE_OUT_DIR"] else { return }
        let data = try Data(contentsOf: URL(fileURLWithPath: input))
        for (name, mode) in [("fit", DeckController.SlideScaling.ensureFit), ("maximize", .maximize)] {
            let (state, theme, pkg) = try Pptx.read(data)
            let deck = DeckController()
            deck.load(state, theme: theme, package: pkg)
            deck.setSlideSize(Size(720, 540), scaling: mode)
            _ = deck.addSlide()   // a new slide: its placeholders must fit the new size
            try Pptx.write(deck).write(to: URL(fileURLWithPath: dir + "/slide-size-\(name).pptx"))
        }
    }
}
