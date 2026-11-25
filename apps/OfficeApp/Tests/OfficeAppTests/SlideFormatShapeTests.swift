import XCTest
import Flutter
import FlutterSwiftBridge
import OfficeText
@testable import OfficeApp

/// S-SH-6: the Format Shape pane and the size and position it sets.
final class SlideFormatShapeTests: XCTestCase {
    private func settle(_ ui: WidgetTester) {
        for _ in 0 ..< 3 { ui.pump(); for cb in FrameCallbackScheduler.shared.takePostFrameCallbacks() { cb(.zero) } }
        ui.pump()
    }

    func testSizePositionAndTurnAreOneUndoStepEach() {
        let deck = DeckController()
        let a = deck.addShape(.rect)
        a.frame = Rect.fromLTWH(100, 80, 200, 100)
        deck.selectShapes([a])
        deck.setSize(width: 300)
        XCTAssertEqual(a.frame.width, 300); XCTAssertEqual(a.frame.height, 100, "a plain shape is not locked")
        deck.setAspectLock(true)
        deck.setSize(height: 50)
        XCTAssertEqual(a.frame.width, 150, accuracy: 0.01); XCTAssertEqual(a.frame.height, 50, accuracy: 0.01)
        deck.setPosition(left: 10, top: 20)
        XCTAssertEqual(a.frame.left, 10); XCTAssertEqual(a.frame.top, 20)
        deck.setRotation(-90)
        XCTAssertEqual(a.rotation, 270, accuracy: 0.01)
        deck.undo(); XCTAssertEqual(a.rotation, 0, accuracy: 0.01)
        deck.undo(); XCTAssertEqual(a.frame.left, 100)
        deck.undo(); deck.undo()
        XCTAssertEqual(a.frame.width, 300); XCTAssertFalse(a.aspectLocked)
    }

    func testTheLockAndSizeSurviveSaving() throws {
        let deck = DeckController()
        let a = deck.addShape(.rect)
        a.frame = Rect.fromLTWH(100, 80, 200, 100)
        deck.selectShapes([a])
        deck.setAspectLock(true)
        let (state, _, _) = try Pptx.read(Pptx.write(deck))
        let back = try XCTUnwrap(state.slides[0].shapes.first { $0.name == a.name })
        XCTAssertTrue(back.aspectLocked)
        XCTAssertEqual(back.frame.width, 200, accuracy: 0.5)
    }

    func testThePaneAppliesWhatIsTypedOnEnter() throws {
        let deck = DeckController()
        let a = deck.addShape(.rect)
        a.frame = Rect.fromLTWH(100, 80, 200, 100)
        deck.selectShapes([a])
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: FormatShapePane(deck: deck, onClose: {}), title: "Test"),
                              size: Size(1280, 800))
        settle(ui)
        XCTAssertTrue(ui.has(id: "fmt.width"))
        ui.tap(id: "fmt.width")
        for _ in 0 ..< 6 { ui.press(.backspace) }
        ui.type("320")
        ui.press(.enter)
        settle(ui)
        XCTAssertEqual(a.frame.width, 320, accuracy: 0.01)
        ui.tap(id: "fmt.lock"); settle(ui)
        XCTAssertTrue(a.aspectLocked)
    }

    /// Writes the file for the PowerPoint check: a right triangle and an arrow with text, each flipped
    /// across, flipped down, turned 90 and turned 45, so PowerPoint shows whether the facing matches.
    func testWritesTheFlipFacingCheckFile() throws {
        let dir = "/data/s/amd-6/ui-check"
        guard FileManager.default.fileExists(atPath: dir) else { return }
        let deck = DeckController()
        var x = 30.0, y = 30.0
        for preset in [ShapePreset(rawValue: "rtTriangle"), .rightArrow] {
            x = 30
            for (label, h, v, turn) in [("plain", false, false, 0.0), ("flip H", true, false, 0), ("flip V", false, true, 0),
                                        ("turn 90", false, false, 90), ("turn 45", false, false, 45),
                                        ("flip H + turn 90", true, false, 90), ("flip V + turn 45", false, true, 45)] {
                let s = deck.addShape(preset)
                s.frame = Rect.fromLTWH(x, y, 100, 70)
                deck.selectShapes([s])
                if h { deck.flipSelection(horizontal: true) }
                if v { deck.flipSelection(horizontal: false) }
                if turn != 0 { deck.setRotation(turn) }
                s.name = "\(preset.rawValue) \(label)"
                if preset == .rightArrow {
                    s.text?.load(RichDocument(paragraphs: [RichParagraph(text: "Abc", runs: [Run(length: 3, style: CharStyle())], style: RichParagraphStyle())]))
                }
                x += 130
            }
            y += 150
        }
        try Pptx.write(deck).write(to: URL(fileURLWithPath: dir + "/flip-facing.pptx"))
    }

    /// Writes the file for the PowerPoint check: a shape and a picture locked, the same two unlocked, alt text on a picture.
    func testWritesTheFormatShapeCheckFile() throws {
        let dir = "/data/s/amd-6/ui-check"
        guard FileManager.default.fileExists(atPath: dir) else { return }
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
        let deck = DeckController()
        let r1 = deck.addShape(.rect), r2 = deck.addShape(.rect)
        let p1 = deck.addPicture(ImageAttachment(data: png, width: 1, height: 1), naturalSize: Size(100, 100))
        let p2 = deck.addPicture(ImageAttachment(data: png, width: 1, height: 1), naturalSize: Size(100, 100))
        r1.name = "Shape locked"; r2.name = "Shape unlocked"; p1.name = "Picture locked"; p2.name = "Picture unlocked"
        for (i, sh) in [r1, r2, p1, p2].enumerated() { sh.frame = Rect.fromLTWH(40 + Double(i) * 220, 80, 180, 120) }
        deck.selectShapes([r1]); deck.setAspectLock(true)
        deck.selectShapes([r2]); deck.setAspectLock(false)
        deck.selectShapes([p1]); deck.setAspectLock(true); deck.setAltText("A one pixel picture, locked")
        deck.selectShapes([p2]); deck.setAspectLock(false)
        try Pptx.write(deck).write(to: URL(fileURLWithPath: dir + "/format-shape.pptx"))
    }

    /// PowerPoint (flip-facing print): a flipped arrow's text sits in the mirrored text rectangle but is not mirrored;
    /// a shape flipped top to bottom turns its text half round.
    func testFlippedArrowTextRectangleMirrorsAndFlipVTurnsTheText() throws {
        func read(_ h: Bool, _ v: Bool) throws -> ShapeState {
            let deck = DeckController()
            let a = deck.addShape(.rightArrow)
            deck.selectShapes([a])
            if h { deck.flipSelection(horizontal: true) }
            if v { deck.flipSelection(horizontal: false) }
            let (state, _, _) = try Pptx.read(Pptx.write(deck))
            return try XCTUnwrap(state.slides[0].shapes.first { $0.name == a.name })
        }
        let plain = try read(false, false), flipH = try read(true, false), flipV = try read(false, true)
        XCTAssertGreaterThan(plain.insets.right, plain.insets.left, "the arrow's text rectangle leans to the tail")
        XCTAssertEqual(flipH.insets.left, plain.insets.right, accuracy: 0.01)
        XCTAssertEqual(flipH.insets.right, plain.insets.left, accuracy: 0.01)
        XCTAssertEqual(flipH.textSpin, 0)
        XCTAssertEqual(flipV.textSpin, 180)
        let deck = DeckController()
        let b = deck.addShape(.rect); deck.selectShapes([b])
        deck.flipSelection(horizontal: false)
        XCTAssertEqual(b.textSpin, 180, "flipping in the app turns the text as reading it back would")
        deck.flipSelection(horizontal: false)
        XCTAssertEqual(b.textSpin, 0)
    }
}
