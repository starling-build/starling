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

    func testFillAndLineFromThePane() throws {
        let deck = DeckController()
        let a = deck.addShape(.rect)
        deck.selectShapes([a])
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: FormatShapePane(deck: deck, onClose: {}), title: "Test"),
                              size: Size(1280, 800))
        settle(ui)
        func enter(_ id: String, _ text: String) {
            ui.tap(id: id)
            for _ in 0 ..< 10 { ui.press(.backspace) }
            ui.type(text); ui.press(.enter); settle(ui)
        }
        enter("fmt.fill.color", "FF8000")
        XCTAssertEqual((a.fill?.value ?? 0) & 0xFFFFFF, 0xFF8000)
        enter("fmt.fill.transparency", "50")
        XCTAssertEqual(Double(a.fill!.value >> 24), 128, accuracy: 1)
        enter("fmt.fill.color", "#00FF00")
        XCTAssertEqual((a.fill?.value ?? 0) & 0xFFFFFF, 0x00FF00)
        XCTAssertEqual(Double(a.fill!.value >> 24), 128, accuracy: 1, "a new colour keeps the transparency")
        enter("fmt.line.width", "4")
        XCTAssertEqual(a.outlineWidth, 4, accuracy: 0.01)
        enter("fmt.line.color", "0000FF")
        XCTAssertEqual((a.outline?.value ?? 0) & 0xFFFFFF, 0x0000FF)
        ui.tap(id: "fmt.line.none"); settle(ui)
        XCTAssertNil(a.outline)
        ui.tap(id: "fmt.fill.none"); settle(ui)
        XCTAssertNil(a.fill)
        deck.undo(); XCTAssertNotNil(a.fill, "one undo brings the fill back")
        ui.tap(id: "fmt.fill.none"); ui.tap(id: "fmt.fill.none"); settle(ui)
        XCTAssertNotNil(a.fill, "unticking No fill gives a solid fill again")
    }

    func testFillAndLineSurviveSaving() throws {
        let deck = DeckController()
        let a = deck.addShape(.rect)
        deck.selectShapes([a])
        deck.setFill(Color(0xFFFF8000)); deck.setFillTransparency(25); deck.setOutline(Color(0xFF0000FF)); deck.setOutlineWidth(3)
        let (state, _, _) = try Pptx.read(Pptx.write(deck))
        let back = try XCTUnwrap(state.slides[0].shapes.first { $0.name == a.name })
        XCTAssertEqual((back.fill?.value ?? 0) & 0xFFFFFF, 0xFF8000)
        XCTAssertEqual(Double(back.fill!.value >> 24), 191, accuracy: 2)
        XCTAssertEqual((back.outline?.value ?? 0) & 0xFFFFFF, 0x0000FF)
        XCTAssertEqual(back.outlineWidth, 3, accuracy: 0.05)
        let dir = "/data/s/amd-6/ui-check"
        if FileManager.default.fileExists(atPath: dir) { try Pptx.write(deck).write(to: URL(fileURLWithPath: dir + "/fill-line.pptx")) }
        deck.setFill(nil)
        let (s2, _, _) = try Pptx.read(Pptx.write(deck))
        XCTAssertNil(try XCTUnwrap(s2.slides[0].shapes.first { $0.name == a.name }).fill)
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
}
