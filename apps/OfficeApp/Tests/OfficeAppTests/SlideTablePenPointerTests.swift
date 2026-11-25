import XCTest
import Flutter
import FlutterSwiftBridge
import OfficeText
@testable import OfficeApp

/// S-TB-1e: the draw-borders pen and the eraser, driven by real pointer drags over the canvas.
final class SlideTablePenPointerTests: XCTestCase {
    private func canvas(_ deck: DeckController) throws -> (WidgetTester, SlideCanvasState) {
        let c = SlideCanvas(deck: deck, cache: SlideTextCache(), active: nil, onEdit: { _ in },
                            onShortcut: { _, _ in false }, modifiers: { [] }, spellChecker: nil)
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: c, title: "Test"))
        for _ in 0 ..< 3 { ui.pump(); for cb in FrameCallbackScheduler.shared.takePostFrameCallbacks() { cb(.zero) } }
        ui.pump()
        return (ui, try XCTUnwrap(ui.state(SlideCanvasState.self)))
    }

    func testPenDragsAcrossTwoEdgesAndEraserAcrossOne() throws {
        let deck = DeckController()
        deck.slides[0].shapes.removeAll()
        let t = deck.addTable(rows: 3, columns: 3)
        t.frame = Rect.fromLTWH(100, 100, 600, 300)
        deck.selectShapes([t])
        let doc = t.text!.document
        let layout = RichLayout(theme: RichTextTheme(fontFamily: OfficeFonts.sans), paragraphCount: doc.paragraphs.count)
        layout.width = t.frame.width
        layout.ensureLaidOut(doc)
        // Where the vertical edge after column 0 and the one after column 1 sit, along the middle of row 0.
        var ys = 0.0, xs: [Double] = [], rowEdge: [Double] = []
        while ys < 400 {
            if let e = layout.cellEdge(at: Offset(5, ys), tolerance: 1, doc), e.side == .top || e.side == .bottom { rowEdge.append(ys) }
            ys += 0.5
        }
        let midY = (rowEdge.first { $0 > 5 } ?? 40) / 2  // the middle of row 0
        var x = 0.0
        while x < 600 {
            if let e = layout.cellEdge(at: Offset(x, midY), tolerance: 0.5, doc), e.side == .left || e.side == .right {
                if xs.last.map({ x - $0 > 4 }) ?? true { xs.append(x) }
            }
            x += 0.5
        }
        XCTAssertGreaterThanOrEqual(xs.count, 3, "lines \(xs) midY \(midY) rows \(rowEdge.count)")
        let (ui, state) = try canvas(deck)
        func pt(_ x: Double, _ y: Double) -> Offset { state.screenPoint(Offset(t.frame.left + x, t.frame.top + y)) }
        func cell(_ r: Int, _ c: Int) -> CellRef? { t.text!.document.paragraphs.compactMap { $0.cell }.first { $0.row == r && $0.column == c } }

        deck.tablePen = DeckController.TablePen(width: 3, color: Color(0xFFFF0000), dash: "dash")
        deck.tableTool = .draw; state.setState {}; ui.pump()
        // One stroke along the middle of row 0 crosses the line after column 0 and the line after column 1.
        ui.drag(from: pt(xs[1] - 30, midY), to: pt(xs[2] + 30, midY))
        XCTAssertEqual(cell(0, 0)?.borders.right?.width, 3, "first edge drawn")
        XCTAssertEqual(cell(0, 1)?.borders.left?.color, Color(0xFFFF0000), "neighbour shares it")
        XCTAssertEqual(cell(0, 1)?.borders.right?.width, 3, "second edge drawn")

        // The whole stroke, two edges, is one undo step; redo it by drawing again below.
        deck.undo()
        XCTAssertNil(cell(0, 0)?.borders.right, "one undo takes the whole drag back")
        XCTAssertNil(cell(0, 1)?.borders.right)
        ui.drag(from: pt(xs[1] - 30, midY), to: pt(xs[2] + 30, midY))
        XCTAssertEqual(cell(0, 1)?.borders.right?.width, 3)
        deck.tableTool = .erase; state.setState {}; ui.pump()
        ui.drag(from: pt(xs[1] - 30, midY), to: pt(xs[1] + 30, midY))
        XCTAssertEqual(cell(0, 0)?.borders.right, CellRef.CellLine.hidden, "eraser hides the first edge")
        XCTAssertEqual(cell(0, 1)?.borders.right?.width, 3, "other edge untouched")
    }

    func testOnePenStrokeAcrossSeveralEdgesIsOneUndoStep() throws {
        let deck = DeckController()
        deck.slides[0].shapes.removeAll()
        let t = deck.addTable(rows: 3, columns: 3)
        t.frame = Rect.fromLTWH(100, 100, 600, 300)
        deck.selectShapes([t])
        func cell(_ r: Int, _ c: Int) -> CellRef? { t.text!.document.paragraphs.compactMap { $0.cell }.first { $0.row == r && $0.column == c } }
        deck.tablePen = DeckController.TablePen(width: 3, color: Color(0xFF0000FF), dash: "solid")
        deck.tableTool = .draw
        deck.penStroke(true)
        deck.penTouch(t, row: 0, column: 0, side: .right)
        deck.penTouch(t, row: 0, column: 1, side: .right)
        deck.penTouch(t, row: 1, column: 1, side: .bottom)
        deck.penStroke(false)
        XCTAssertEqual(cell(0, 0)?.borders.right?.width, 3)
        XCTAssertEqual(cell(0, 1)?.borders.right?.width, 3)
        XCTAssertEqual(cell(1, 1)?.borders.bottom?.width, 3)
        deck.undo()
        XCTAssertNil(cell(0, 0)?.borders.right, "one undo takes the whole stroke back")
        XCTAssertNil(cell(0, 1)?.borders.right)
        XCTAssertNil(cell(1, 1)?.borders.bottom)
        // A second stroke is its own step.
        deck.penStroke(true)
        deck.penTouch(t, row: 0, column: 0, side: .right)
        deck.penStroke(false)
        deck.penStroke(true)
        deck.penTouch(t, row: 0, column: 1, side: .right)
        deck.penStroke(false)
        deck.undo()
        XCTAssertEqual(cell(0, 0)?.borders.right?.width, 3)
        XCTAssertNil(cell(0, 1)?.borders.right)
    }
}
