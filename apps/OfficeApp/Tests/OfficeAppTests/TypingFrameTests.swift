import XCTest
import Flutter
import FlutterSwiftBridge
import OfficeText
@testable import OfficeApp

/// The frame of a text box being typed into follows the words: painted offscreen, the frame's lower edge sits below the
/// height the box had when it was entered, and nothing of the old edge is left inside.
final class TypingFrameTests: XCTestCase {
    /// The paint of `tester`'s tree as RGBA pixels (its picture layers, under their transforms and clips).
    private func pixels(_ tester: WidgetTester, _ w: Int, _ h: Int) throws -> [UInt8] {
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

    private static func crc(_ data: [UInt8]) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for b in data {
            c ^= UInt32(b)
            for _ in 0 ..< 8 { c = (c & 1) != 0 ? (c >> 1) ^ 0xEDB8_8320 : c >> 1 }
        }
        return ~c
    }

    /// An uncompressed PNG, enough to look at.
    private func png(_ rgba: [UInt8], _ w: Int, _ h: Int) -> Data {
        func be(_ v: UInt32) -> [UInt8] { [UInt8(v >> 24), UInt8((v >> 16) & 255), UInt8((v >> 8) & 255), UInt8(v & 255)] }
        func chunk(_ tag: String, _ body: [UInt8]) -> [UInt8] { be(UInt32(body.count)) + Array(tag.utf8) + body + be(Self.crc(Array(tag.utf8) + body)) }
        var raw: [UInt8] = []
        for y in 0 ..< h { raw.append(0); raw += rgba[(y * w * 4) ..< ((y + 1) * w * 4)] }
        var z: [UInt8] = [0x78, 0x01]
        var i = 0
        while i < raw.count {
            let n = min(65535, raw.count - i), last: UInt8 = i + n >= raw.count ? 1 : 0
            z += [last, UInt8(n & 255), UInt8(n >> 8), UInt8(~n & 255), UInt8((~n >> 8) & 255)] + raw[i ..< (i + n)]
            i += n
        }
        var a: UInt32 = 1, b: UInt32 = 0
        for v in raw { a = (a + UInt32(v)) % 65521; b = (b + a) % 65521 }
        z += be(b << 16 | a)
        return Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + chunk("IHDR", be(UInt32(w)) + be(UInt32(h)) + [8, 6, 0, 0, 0]) + chunk("IDAT", z) + chunk("IEND", []))
    }

    func testTheFrameFollowsTheWordsPastTheOldHeight() throws {
        let (w, h) = (900, 600)
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(Double(w), Double(h)))
        let shell = try XCTUnwrap(ui.state(OfficeShellState.self))
        let c = shell.session.controller
        var box = try XCTUnwrap(TextBoxInsert.make(text: "one"))
        box.outline = ShapeOutline(kind: .box, color: Color(0xFFCC0000), width: 3)
        c.insertImage(box)
        let i = try XCTUnwrap(c.document.paragraphs.firstIndex { $0.image?.textBox != nil })
        XCTAssertTrue(c.textBoxAutoHeight(at: i))
        c.selectImage(at: i)
        for _ in 0 ..< 3 { ui.pump(); RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        // Where the page draws the box now: the bounds of its frame's colour.
        let before = try pixels(ui, w, h)
        var (x0, y0, x1, y1) = (w, h, -1, -1)
        for y in 0 ..< h { for x in 0 ..< w {
            let o = (y * w + x) * 4
            if before[o] > 170, before[o + 1] < 90, before[o + 2] < 90 { x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y) }
        } }
        XCTAssertGreaterThan(x1, x0, "the page draws the box's frame")
        let old = Rect.fromLTRB(Double(x0), Double(y0), Double(x1 + 1), Double(y1 + 1))
        ui.click(at: old.center, kind: .mouse)
        for _ in 0 ..< 3 { ui.pump(); RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        XCTAssertNotNil(shell._boxEdit, "a click on the selected box enters its text")
        let editor = shell.session.controller
        XCTAssertFalse(editor === c, "typing goes into the box's own controller")
        editor.selectAll()
        editor.insertText("a first line\nand a second\nand a third\nand a fourth\nand a fifth")
        for _ in 0 ..< 4 { ui.pump(); RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        let grown = try XCTUnwrap(shell._boxContentHeight) + 7.2
        XCTAssertGreaterThan(grown, old.height + 20, "five lines are taller than the box was")
        let px = try pixels(ui, w, h)
        func at(_ x: Double, _ y: Double) -> (UInt8, UInt8, UInt8) { let o = (Int(y) * w + Int(x)) * 4; return (px[o], px[o + 1], px[o + 2]) }
        func isFrame(_ p: (UInt8, UInt8, UInt8)) -> Bool { p.0 > 170 && p.1 < 90 && p.2 < 90 }
        let mid = old.left + old.width / 2
        // The lowest row of the frame colour down the middle of the box is its lower edge: it moved well past the old one.
        var low = 0
        for y in 0 ..< h where isFrame(at(mid, Double(y))) { low = y }
        XCTAssertGreaterThan(Double(low), old.bottom + 15, "the frame closes the grown box, below where it was")
        XCTAssertGreaterThanOrEqual(Double(low), old.top + grown - 2, "and it reaches at least the grown height")
        // ... and no piece of it is left across the box at the height it had when it was entered.
        XCTAssertFalse((-2 ... 2).contains { isFrame(at(mid, old.bottom + Double($0))) }, "the old lower edge is gone")
        // The strip above the new frame is clean: the page's own (old) frame is not drawn behind the editor, so the
        // frame colour starts at one row and nothing sits above it down the box's middle.
        let rows = (0 ..< h).filter { isFrame(at(mid, Double($0))) }
        var runs = 0
        for (k, y) in rows.enumerated() where k == 0 || y != rows[k - 1] + 1 { runs += 1 }
        XCTAssertEqual(runs, 2, "one frame: a top edge and a bottom edge, no doubled line")
        XCTAssertTrue(ui.has(text: "Paste"), "typing in a box leaves the Home ribbon drawn, not an empty body")
        if let path = ProcessInfo.processInfo.environment["TYPING_FRAME_PNG"] {
            try png(px, w, h).write(to: URL(fileURLWithPath: path))
        }
    }

    func testAShapeGetsShapeFormatAndAPictureKeepsPictureFormat() throws {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(900, 600))
        let shell = try XCTUnwrap(ui.state(OfficeShellState.self))
        let c = shell.session.controller
        c.insertImage(try XCTUnwrap(TextBoxInsert.make(text: "one")))
        let i = try XCTUnwrap(c.document.paragraphs.firstIndex { $0.image?.textBox != nil })
        c.selectImage(at: i)
        for _ in 0 ..< 3 { ui.pump(); RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        XCTAssertEqual(shell.session.imageTab, .shapeFormat)
        XCTAssertTrue(ui.has(text: "Shape Format"))
        XCTAssertFalse(ui.has(text: "Picture Format"))
    }

    /// Typing into one child of a group: the group stays whole in the document, the words land in that child, and the whole
    /// session is one undo step.
    func testTypingIntoAChildOfAGroupKeepsTheGroup() throws {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(900, 600))
        let shell = try XCTUnwrap(ui.state(OfficeShellState.self))
        let c = shell.session.controller
        for (n, preset) in ["rect", "ellipse"].enumerated() {
            c.pendingShape = { x, y, w, h in TextBoxInsert.makeShape(preset: preset, width: w, height: h, number: TextBoxInsert.nextShapeNumber(in: c.document), page: (x, y)) }
            XCTAssertTrue(c.placePendingShape(x: 80 + Double(n) * 120, y: 200, width: 100, height: 60, at: RichPosition(paragraph: 0, offset: 0)))
        }
        let shapes = c.document.paragraphs.indices.filter { c.document.paragraphs[$0].image != nil }
        c.selectImage(at: shapes[0])
        c.toggleShapePick(at: shapes[1])
        let group = try XCTUnwrap(ShapeGroups.group(c.pickedShapeIndexes.compactMap { c.document.paragraphs[$0].image }, number: 5))
        XCTAssertTrue(c.replaceImageParagraphs(c.pickedShapeIndexes, with: [group]))
        let gi = try XCTUnwrap(c.selectedImageIndex)
        XCTAssertTrue(c.pickGroupChild(at: gi, point: Offset(10, 10)))
        for _ in 0 ..< 3 { ui.pump(); RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        shell._enterBox(gi, nil, Rect.fromLTWH(100, 200, 100, 60))
        let editor = shell.session.controller
        XCTAssertFalse(editor === c, "typing goes into the child's own controller")
        editor.insertText("hello child")
        shell._leaveBox()
        XCTAssertTrue(shell.session.controller === c)
        let image = try XCTUnwrap(c.document.paragraphs[gi].image)
        XCTAssertTrue(ShapeGroups.isGroup(image), "the group is still one group")
        XCTAssertEqual(c.document.paragraphs.filter { $0.image != nil }.count, 1)
        XCTAssertTrue(image.sourceXML!.containsSubstring("hello child"))
        c.undo()
        XCTAssertFalse(try XCTUnwrap(c.document.paragraphs[gi].image).sourceXML!.containsSubstring("hello child"), "one undo takes the whole edit out")
    }

    /// mac-ipad (macOS, main 523f1a82e): a text box that came from an opened file is selected by a click on it, the same
    /// as one made with Insert > Text Box.
    func testAClickSelectsATextBoxFromAnOpenedFile() throws {
        var doc = RichDocument(paragraphs: [RichParagraph(text: "before")])
        var box = try XCTUnwrap(TextBoxInsert.make(text: "one"))
        box.outline = ShapeOutline(kind: .box, color: Color(0xFFCC0000), width: 3)
        var p = RichParagraph(text: "")
        p.image = box
        doc.paragraphs.append(p)
        doc.paragraphs.append(RichParagraph(text: "after"))
        let path = NSTemporaryDirectory() + "typing-frame-\(ProcessInfo.processInfo.processIdentifier).docx"
        defer { try? FileManager.default.removeItem(atPath: path) }
        try OfficeFormats.write(doc, to: path, pageSetup: .letter)
        let (w, h) = (900, 600)
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: path), title: "Test"), size: Size(Double(w), Double(h)))
        for _ in 0 ..< 3 { ui.pump(); RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        let shell = try XCTUnwrap(ui.state(OfficeShellState.self))
        let c = shell.session.controller
        let i = try XCTUnwrap(c.document.paragraphs.firstIndex { $0.image != nil }, "the opened file holds the box")
        let px = try pixels(ui, w, h)
        // The frame: the rows with a long dark run, below the title bar and ribbon (the page starts under y 240).
        var (x0, y0, x1, y1) = (w, h, -1, -1)
        for y in 240 ..< h - 50 {
            let dark = (0 ..< w).filter { let o = (y * w + $0) * 4; return px[o] < 80 && px[o + 1] < 80 && px[o + 2] < 80 }
            if dark.count > 120, let l = dark.first, let r = dark.last { x0 = min(x0, l); x1 = max(x1, r); y0 = min(y0, y); y1 = max(y1, y) }
        }
        XCTAssertGreaterThan(x1, x0, "the page draws the box's frame")
        // Just inside the frame, on the box, clear of its words.
        ui.click(at: Offset(Double(x1) - 6, Double(y1) - 6), kind: .mouse)
        for _ in 0 ..< 3 { ui.pump(); RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        XCTAssertEqual(shell.session.controller.selectedImageIndex, i, "a click on the opened box selects it")
    }

    /// A picture inside a text box that is open for typing is picked by a click on it, as one on the page is, so the
    /// Picture Format tab and the handles act on it.
    func testAClickPicksAPictureInsideAnOpenTextBox() throws {
        let (w, h) = (900, 600)
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(Double(w), Double(h)))
        let shell = try XCTUnwrap(ui.state(OfficeShellState.self))
        let c = shell.session.controller
        var box = try XCTUnwrap(TextBoxInsert.make(text: "one"))
        box.width = 200; box.height = 120
        c.insertImage(box)
        let i = try XCTUnwrap(c.document.paragraphs.firstIndex { $0.image?.textBox != nil })
        for _ in 0 ..< 3 { ui.pump(); RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        shell._enterBox(i, nil, Rect.fromLTWH(200, 250, 200, 120))
        for _ in 0 ..< 3 { ui.pump(); RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        let editor = shell.session.controller
        XCTAssertFalse(editor === c)
        let green = png(Array(repeating: [0, 200, 0, 255], count: 16).flatMap { $0 }, 4, 4)
        editor.selection = RichSelection(caret: RichPosition(paragraph: 0, offset: editor.document.paragraphs[0].length))
        editor.insertImage(ImageAttachment(data: green, width: 40, height: 40))
        let pi = try XCTUnwrap(editor.document.paragraphs.firstIndex { $0.image != nil } ?? editor.document.paragraphs.firstIndex { !$0.inlineImages.isEmpty })
        editor.selection = RichSelection(caret: RichPosition(paragraph: 0, offset: 0))
        for _ in 0 ..< 4 { ui.pump(); RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        let px = try pixels(ui, w, h)
        var (x0, y0, x1, y1) = (w, h, -1, -1)
        for y in 0 ..< h { for x in 0 ..< w {
            let o = (y * w + x) * 4
            if px[o] < 60, px[o + 1] > 150, px[o + 2] < 60 { x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y) }
        } }
        XCTAssertGreaterThan(x1, x0, "the open box draws the picture")
        ui.click(at: Offset(Double(x0 + x1) / 2, Double(y0 + y1) / 2), kind: .mouse)
        for _ in 0 ..< 3 { ui.pump(); RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        XCTAssertNotNil(shell._boxEdit, "the click stays in the box")
        XCTAssertTrue(shell.session.controller === editor)
        XCTAssertTrue(editor.selectedImageIndex == pi || editor.selectedInlineImage != nil, "the click picks the picture")
    }
}
