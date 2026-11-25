import XCTest
import Flutter
import FlutterSwiftBridge
import OfficeText
@testable import OfficeApp

/// S-SH-4: the gradient editor for a shape's fill.
final class SlideGradientEditorTests: XCTestCase {
    private func deckWithShape() -> (DeckController, SlideShape) {
        let deck = DeckController()
        let s = deck.addShape(.rect)
        s.frame = Rect.fromLTWH(80, 80, 300, 160)
        deck.selectShapes([s])
        return (deck, s)
    }

    func testStopsAddRemoveReverseAndUndo() throws {
        let (deck, s) = deckWithShape()
        deck.setFill(Color(0xFFC00000))
        deck.editGradient { _ in }
        XCTAssertEqual(s.fillStyle?.stops.count, 2)
        deck.addGradientStop()
        XCTAssertEqual(s.fillStyle?.stops.map(\.position), [0, 0.5, 1])
        deck.editGradient { $0.stops[1].color = Color(0xFF00B050) }
        deck.reverseGradient()
        XCTAssertEqual(s.fillStyle?.stops[1].color, Color(0xFF00B050))
        deck.removeGradientStop(at: 1)
        deck.removeGradientStop(at: 0)
        XCTAssertEqual(s.fillStyle?.stops.count, 2, "a gradient keeps two stops")
        deck.undo(); deck.undo()
        XCTAssertEqual(s.fillStyle?.stops.count, 3)
    }

    func testTransparencyKeepsTheGradientAndItSurvivesSaving() throws {
        let (deck, s) = deckWithShape()
        deck.editGradient { g in g.stops = [.init(position: 0, color: Color(0xFF0070C0)), .init(position: 0.4, color: Color(0xFFFFFFFF)),
                                              .init(position: 1, color: Color(0xFF7030A0))]; g.angle = 45 }
        deck.setFillTransparency(50)
        XCTAssertEqual(s.fillStyle?.stops.count, 3)
        let (state, _, _) = try Pptx.read(Pptx.write(deck))
        let cands = state.slides[0].shapes.filter { $0.fillStyle != nil }
        let back = try XCTUnwrap(cands.last?.fillStyle)
        XCTAssertEqual(back.stops.count, 3)
        XCTAssertEqual(back.stops[1].position, 0.4, accuracy: 0.001)
        XCTAssertEqual(back.angle, 45, accuracy: 0.5)
        XCTAssertEqual(back.stops[2].color.value & 0xFFFFFF, 0x7030A0)
        XCTAssertEqual(Double(back.stops[2].color.value >> 24), 128, accuracy: 2)
    }

    func testThePaneEditsStops() throws {
        let (deck, s) = deckWithShape()
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: FormatShapePane(deck: deck, onClose: {}), title: "T"), size: Size(1400, 900))
        XCTAssertFalse(ui.has(id: "fmt.grad.add"))
        XCTAssertTrue(ui.tap(id: "fmt.grad.on"))
        XCTAssertEqual(s.fillStyle?.stops.count, 2)
        XCTAssertTrue(ui.tap(id: "fmt.grad.add"))
        XCTAssertEqual(s.fillStyle?.stops.count, 3)
        XCTAssertTrue(ui.has(id: "fmt.grad.color.2"))
        XCTAssertTrue(ui.tap(id: "fmt.grad.remove.1"))
        XCTAssertEqual(s.fillStyle?.stops.count, 2)
        XCTAssertTrue(ui.tap(id: "fmt.grad.reverse"))
        XCTAssertTrue(ui.tap(id: "fmt.grad.on"))
        XCTAssertNil(s.fillStyle, "turning it off gives a plain fill again")
    }

    func testWritesThePowerPointCheckFile() throws {
        let (deck, s) = deckWithShape()
        deck.editGradient { g in g.stops = [.init(position: 0, color: Color(0xFF0070C0)), .init(position: 0.4, color: Color(0xFFFFFFFF)),
                                              .init(position: 1, color: Color(0xFFC00000))]; g.angle = 45 }
        let b = deck.addShape(.rect); b.frame = Rect.fromLTWH(420, 80, 300, 160)
        deck.selectShapes([b]); deck.setFill(Color(0xFF00B050)); deck.editGradient { $0.angle = 0 }; deck.setFillTransparency(50)
        _ = s
        let dir = "/data/s/amd-6/ui-check"
        guard FileManager.default.fileExists(atPath: dir) else { return }
        try Pptx.write(deck).write(to: URL(fileURLWithPath: dir + "/gradient.pptx"))
    }
}
