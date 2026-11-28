import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// Ctrl/Cmd+Z must ask for a frame: on the Mac the window showed the undone state only at the next pointer move or
/// key, because nothing else asks for one when no input follows the undo.
final class UndoRepaintTests: XCTestCase {
    private func app(_ home: Widget) -> WidgetTester {
        WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: home, title: "Test"), size: Size(1440, 932))
    }

    @discardableResult
    private func send(_ logical: Int64, _ type: KeyEventType) -> Bool {
        FocusManager.instance.dispatchKeyData(KeyData(timeStamp: 0, type: type, physical: 0, logical: logical,
                                                      character: nil, synthesized: false))
    }

    /// Settles every frame, then presses the primary modifier + Z alone: whether that asked for a frame.
    private func undoAsksForAFrame(_ ui: WidgetTester) -> Bool {
        // The app's own wiring (Adapter): a dirty element or render object asks the engine for a frame.
        var asked = false
        ui.buildOwner.onBuildScheduled = { asked = true }
        ui.pipelineOwner.onNeedVisualUpdate = { asked = true }
        for _ in 0 ..< 4 { ui.pump() }
        let main: Int64 = KeyModifiers.primary == .meta ? 0xFFE7 : 0xFFE3
        send(main, .down); ui.pump()
        asked = false
        send(0x7A, .down); send(0x7A, .up)
        let undoAsked = asked
        send(main, .up)
        return undoAsked
    }

    /// The paint of the tree as RGBA pixels (as TypingFrameTests draws it).
    private func pixels(_ tester: WidgetTester) throws -> [UInt8] {
        let (w, h) = (1440, 932)
        let recorder = NativePictureRecorder()
        let canvas = NativeCanvas(recorder: recorder, cullRect: Rect.fromLTWH(0, 0, Double(w), Double(h)))
        func walk(_ layer: Layer) {
            if let p = layer as? PictureLayer, let pic = p.picture { canvas.drawPicture(pic); return }
            guard let c = layer as? ContainerLayer else { return }
            canvas.save()
            if let t = c as? TransformLayer, let m = t.transform { canvas.transform(m.storage) }
            if let l = c as? LeaderLayer { canvas.translate(l.offset.dx, l.offset.dy) }
            if let o = c as? OpacityLayer { canvas.translate(o.offset.dx, o.offset.dy) }
            if let r = c as? ClipRRectLayer, let rr = r.clipRRect { canvas.clipRRect(rr) }
            if let r = c as? ClipRectLayer, let rect = r.clipRect { canvas.clipRect(rect) }
            var child = c.firstChild
            while let k = child { walk(k); child = k.nextSibling }
            canvas.restore()
        }
        if let root = tester.renderView.layer { walk(root) }
        let image = try XCTUnwrap(recorder.endRecording().toImageSync(width: w, height: h))
        return [UInt8](try image.toByteData(format: .rawRgba))
    }

    /// Repaints every render object, as a fresh window would.
    private func repaintAll(_ ui: WidgetTester) {
        func mark(_ r: RenderObject) { r.markNeedsPaint(); r.visitChildren(mark) }
        mark(ui.renderView)
        ui.pump()
    }

    /// After the undo key alone and one frame, the window shows what a full repaint shows.
    private func assertUndoIsDrawn(_ ui: WidgetTester, file: StaticString = #filePath, line: UInt = #line) throws {
        let before = try pixels(ui)
        XCTAssertTrue(undoAsksForAFrame(ui), "the undo asked for a frame", file: file, line: line)
        ui.pump()
        let drawn = try pixels(ui)
        repaintAll(ui)
        let fresh = try pixels(ui)
        let diff = zip(drawn, fresh).filter { $0 != $1 }.count
        XCTAssertEqual(diff, 0, "the frame after the undo is stale", file: file, line: line)
        XCTAssertNotEqual(before, drawn, "the undo changed what the window shows", file: file, line: line)
    }

    func testSlidesUndoOfAnAddedTable() throws {
        let ui = app(SlidesShell(initialPath: nil, startBlank: true, onSwitch: { _, _ in }))
        let deck = try XCTUnwrap(ui.state(SlidesShellState.self)?.session.deck)
        ui.pump()
        let before = deck.slides[0].shapes.count
        deck.addTable(rows: 2, columns: 2); ui.pump()
        XCTAssertEqual(deck.slides[0].shapes.count, before + 1)
        try assertUndoIsDrawn(ui)
        XCTAssertEqual(deck.slides[0].shapes.count, before, "the table is gone")
    }

    func testSlidesUndoOfTypingInATableCell() throws {
        let ui = app(SlidesShell(initialPath: nil, startBlank: true, onSwitch: { _, _ in }))
        let deck = try XCTUnwrap(ui.state(SlidesShellState.self)?.session.deck)
        ui.pump()
        let t = deck.addTable(rows: 2, columns: 2)
        t.frame = Rect.fromLTWH(100, 100, 600, 200)
        deck.selectShapes([t]); ui.pump()
        ui.type("abc"); ui.pump()
        try assertUndoIsDrawn(ui)
    }

    func testSlidesUndoOfTypingAfterLeavingTheCell() throws {
        let ui = app(SlidesShell(initialPath: nil, startBlank: true, onSwitch: { _, _ in }))
        let deck = try XCTUnwrap(ui.state(SlidesShellState.self)?.session.deck)
        ui.pump()
        let t = deck.addTable(rows: 2, columns: 2)
        t.frame = Rect.fromLTWH(100, 100, 600, 200)
        deck.selectShapes([t]); ui.pump()
        ui.type("abc"); ui.pump()
        ui.press(.escape); ui.pump()
        try assertUndoIsDrawn(ui)
    }

    func testWriterUndoOfTyping() throws {
        let ui = app(OfficeShell(initialPath: nil, startBlank: true))
        ui.pump()
        ui.type("abc"); ui.pump()
        try assertUndoIsDrawn(ui)
    }

    func testSheetsUndoOfACellEntry() throws {
        let ui = app(SheetsShell(initialPath: nil, onSwitch: { _, _ in }))
        ui.pump()
        ui.type("12"); ui.press(.enter); ui.pump()
        try assertUndoIsDrawn(ui)
    }
}
