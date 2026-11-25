import XCTest
import Flutter
import FlutterSwiftBridge
import OfficeText
@testable import OfficeApp

/// S-SH-3: line weight, dash and arrowheads.
final class SlideLineStyleTests: XCTestCase {
    private func deckWithLine() -> (DeckController, SlideShape) {
        let deck = DeckController()
        let s = deck.addShape(.line)
        deck.selectShapes([s])
        return (deck, s)
    }

    func testArrowheadsDashAndUndo() {
        let (deck, s) = deckWithLine()
        deck.setLineEnd(start: true, kind: "oval")
        deck.setLineEnd(start: false, kind: "triangle")
        deck.setOutlineDash("dash")
        XCTAssertEqual(s.headEnd?.kind, "oval"); XCTAssertEqual(s.tailEnd?.kind, "triangle")
        deck.setLineEnd(start: true, kind: nil)
        XCTAssertNil(s.headEnd)
        deck.undo()
        XCTAssertEqual(s.headEnd?.kind, "oval")
    }

    func testArrowheadsAndDashSurviveSaving() throws {
        let (deck, s) = deckWithLine()
        s.frame = Rect.fromLTWH(100, 100, 300, 0)
        deck.setLineEnd(start: true, kind: "diamond"); deck.setLineEnd(start: false, kind: "stealth")
        deck.setOutlineDash("lgDash"); deck.setOutlineWidth(4.5)
        let (state, _, _) = try Pptx.read(Pptx.write(deck))
        let back = try XCTUnwrap(state.slides[0].shapes.last(where: { $0.headEnd != nil }))
        XCTAssertEqual(back.headEnd?.kind, "diamond")
        XCTAssertEqual(back.tailEnd?.kind, "stealth")
        XCTAssertEqual(back.outlineDash, "lgDash")
        XCTAssertEqual(back.outlineWidth, 4.5, accuracy: 0.01)
    }

    func testAFileLinesOtherArrowStaysWhenOneEndChanges() throws {
        let (deck, s) = deckWithLine()
        deck.setLineEnd(start: false, kind: "triangle")
        let (state, theme, pkg) = try Pptx.read(Pptx.write(deck))
        let again = DeckController(); again.load(state, theme: theme, package: pkg)
        let l = try XCTUnwrap(again.currentSlide.shapes.last(where: { $0.tailEnd != nil }))
        again.selectShapes([l])
        again.setLineEnd(start: true, kind: "oval")
        let (st2, _, _) = try Pptx.read(Pptx.write(again))
        let b = try XCTUnwrap(st2.slides[0].shapes.last(where: { $0.headEnd != nil }))
        XCTAssertEqual(b.headEnd?.kind, "oval"); XCTAssertEqual(b.tailEnd?.kind, "triangle")
        _ = s
    }

    func testThePaneCyclesTheArrowheads() {
        let (deck, s) = deckWithLine()
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: FormatShapePane(deck: deck, onClose: {}), title: "T"), size: Size(1400, 1200))
        XCTAssertTrue(ui.tap(id: "fmt.line.head"))
        XCTAssertEqual(s.headEnd?.kind, "triangle")
        XCTAssertTrue(ui.tap(id: "fmt.line.tail")); XCTAssertTrue(ui.tap(id: "fmt.line.tail"))
        XCTAssertEqual(s.tailEnd?.kind, "arrow")
    }

    func testWritesThePowerPointCheckFile() throws {
        let deck = DeckController()
        let kinds = ["triangle", "arrow", "stealth", "diamond", "oval"]
        for (i, k) in kinds.enumerated() {
            let l = deck.addShape(.line)
            l.frame = Rect.fromLTWH(80, 80 + Double(i) * 70, 400, 0)
            deck.selectShapes([l]); deck.setOutlineWidth(3)
            deck.setLineEnd(start: false, kind: k); deck.setLineEnd(start: true, kind: kinds[(i + 2) % 5])
            deck.setOutlineDash(["dash", "sysDot", "lgDashDot", nil, "dashDot"][i])
        }
        let dir = "/data/s/amd-6/ui-check"
        guard FileManager.default.fileExists(atPath: dir) else { return }
        try Pptx.write(deck).write(to: URL(fileURLWithPath: dir + "/lines.pptx"))
    }
}
