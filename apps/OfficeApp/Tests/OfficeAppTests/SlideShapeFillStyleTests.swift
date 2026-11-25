import XCTest
import Flutter
import FlutterSwiftBridge
import OfficeText
@testable import OfficeApp

/// S-SH-4: picture, texture and pattern fills on a shape.
final class SlideShapeFillStyleTests: XCTestCase {
    private func png() -> Data {
        // A 1x1 PNG.
        Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
    }

    private func deckWithShape() -> (DeckController, SlideShape) {
        let deck = DeckController()
        let s = deck.addShape(.rect)
        deck.selectShapes([s])
        return (deck, s)
    }

    func testPatternFillSurvivesSavingAndUndo() throws {
        let (deck, s) = deckWithShape()
        deck.setPatternFill("dkUpDiag", foreground: Color(0xFFC00000), background: Color(0xFFFFFFFF))
        XCTAssertTrue(s.fillStyle?.isPattern == true)
        let (state, _, _) = try Pptx.read(Pptx.write(deck))
        let back = try XCTUnwrap(state.slides[0].shapes.first { $0.fileId == s.fileId } ?? state.slides[0].shapes.last)
        XCTAssertEqual(back.fillStyle?.patternPreset, "dkUpDiag")
        XCTAssertEqual(back.fillStyle?.patternFg, Color(0xFFC00000))
        deck.undo()
        XCTAssertNil(s.fillStyle)
    }

    func testPictureAndTextureFillsSurviveSaving() throws {
        let (deck, s) = deckWithShape()
        deck.setPictureFill(ImageAttachment(data: png(), width: 1, height: 1, name: "dot.png"))
        var (state, _, _) = try Pptx.read(Pptx.write(deck))
        var back = try XCTUnwrap(state.slides[0].shapes.last)
        XCTAssertNotNil(back.fillStyle?.image)
        XCTAssertEqual(back.fillStyle?.tiled, false)
        deck.setPictureFill(ImageAttachment(data: png(), width: 1, height: 1, name: "dot.png"), tiled: true)
        (state, _, _) = try Pptx.read(Pptx.write(deck))
        back = try XCTUnwrap(state.slides[0].shapes.last)
        XCTAssertEqual(back.fillStyle?.tiled, true)
        deck.setFill(Color(0xFF00FF00))
        XCTAssertNil(s.fillStyle, "a plain colour replaces the picture")
    }

    func testWritesThePowerPointCheckFile() throws {
        let (deck, s) = deckWithShape()
        s.frame = Rect.fromLTWH(60, 60, 220, 140)
        deck.setPatternFill("dkUpDiag", foreground: Color(0xFFC00000), background: Color(0xFFFFFFFF))
        let b = deck.addShape(.rect); b.frame = Rect.fromLTWH(320, 60, 220, 140)
        deck.selectShapes([b]); deck.setPictureFill(ImageAttachment(data: png(), width: 1, height: 1, name: "dot.png"))
        let c = deck.addShape(.rect); c.frame = Rect.fromLTWH(60, 260, 220, 140)
        deck.selectShapes([c]); deck.setPictureFill(ImageAttachment(data: png(), width: 1, height: 1, name: "dot.png"), tiled: true)
        let dir = "/data/s/amd-6/ui-check"
        guard FileManager.default.fileExists(atPath: dir) else { return }
        try Pptx.write(deck).write(to: URL(fileURLWithPath: dir + "/fillstyle.pptx"))
    }
}

final class SlideShapeFillStyleUITests: XCTestCase {
    func testShapeFillMenuOffersPictureTextureAndPattern() throws {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SlidesShell(initialPath: nil, startBlank: true, onSwitch: { _, _ in }), title: "Test"),
                              size: Size(1400, 800))
        let session = try XCTUnwrap(ui.state(SlidesShellState.self)?.session)
        let deck = try XCTUnwrap(session.deck)
        let s = deck.addShape(.rect)
        deck.selectShapes([s]); ui.pump()
        var asked: [Bool] = []
        session.onShapeFillPicture = { asked.append($0) }
        XCTAssertTrue(ui.tap(tip: "Shape Fill"))
        XCTAssertTrue(ui.has(id: "shape-fill-picture"))
        XCTAssertTrue(ui.tap(id: "shape-fill-texture"))
        XCTAssertEqual(asked, [true])
        XCTAssertTrue(ui.tap(tip: "Shape Fill"))
        XCTAssertTrue(ui.tap(text: "Pattern"))
        XCTAssertTrue(ui.tap(id: "shape-fill-pattern-smGrid"))
        XCTAssertEqual(s.fillStyle?.patternPreset, "smGrid")
    }
}
