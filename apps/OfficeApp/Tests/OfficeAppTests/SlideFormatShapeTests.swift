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

    /// A deck read from a file, with a gradient shape (and a green dashed line) added to its first slide.
    private func deckWithGradientShape() throws -> DeckController {
        let (_, _, _) = try Pptx.read(Pptx.write(SlidesSample.make()))
        var package = PptxPackage(try Zip.read(try Pptx.write(SlidesSample.make())))
        let sp = "<p:sp><p:nvSpPr><p:cNvPr id=\"91\" name=\"Grad\"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>"
            + "<p:spPr><a:xfrm><a:off x=\"1270000\" y=\"3810000\"/><a:ext cx=\"2540000\" cy=\"1270000\"/></a:xfrm>"
            + "<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom>"
            + "<a:gradFill><a:gsLst><a:gs pos=\"0\"><a:srgbClr val=\"FF0000\"/></a:gs><a:gs pos=\"100000\"><a:srgbClr val=\"0000FF\"/></a:gs></a:gsLst><a:lin ang=\"0\"/></a:gradFill>"
            + "<a:ln w=\"25400\"><a:solidFill><a:srgbClr val=\"00AA00\"/></a:solidFill><a:prstDash val=\"dash\"/></a:ln></p:spPr></p:sp>"
        var slide = String(data: package.parts["ppt/slides/slide1.xml"]!, encoding: .utf8)!
        slide = slide.replacingOccurrences(of: "</p:spTree>", with: sp + "</p:spTree>")
        package.parts["ppt/slides/slide1.xml"] = Data(slide.utf8)
        var entries: [ZipEntry] = []
        for (k, v) in package.parts { entries.append(ZipEntry(name: k, data: v)) }
        let (state, theme, pkg) = try Pptx.read(try Zip.write(entries))
        let deck = DeckController()
        deck.load(state, theme: theme, package: pkg)
        return deck
    }

    private func slideXML(_ deck: DeckController) throws -> String {
        let out = PptxPackage(try Zip.read(try Pptx.write(deck)))
        return String(data: out.parts["ppt/slides/slide1.xml"]!, encoding: .utf8)!
    }

    private func shapeXML(_ xml: String, _ name: String) -> String {
        guard let r = xml.range(of: "name=\"\(name)\"") else { return "" }
        let rest = String(xml[r.upperBound...])
        return String(rest[..<(rest.range(of: "</p:sp>")?.lowerBound ?? rest.endIndex)])
    }

    func testChoosingASolidFillReplacesAGradientEvenOfTheSameColour() throws {
        let deck = try deckWithGradientShape()
        let g = try XCTUnwrap(deck.currentSlide.shapes.first { $0.name == "Grad" })
        XCTAssertTrue(shapeXML(try slideXML(deck), "Grad").contains("<a:gradFill"), "untouched, the gradient is kept")
        deck.selectShapes([g])
        deck.setFill(g.fill ?? Color(0xFFFF0000)); deck.setOutline(Color(0xFF00AA00))
        let x = shapeXML(try slideXML(deck), "Grad")
        XCTAssertFalse(x.contains("<a:gradFill"), "a gradient and a solid fill must not share one spPr")
        XCTAssertTrue(x.contains("<a:solidFill"))
        XCTAssertNil(g.fillStyle)
        deck.undo(); deck.undo()
        XCTAssertTrue(shapeXML(try slideXML(deck), "Grad").contains("<a:gradFill"), "undo brings the gradient back")
    }

    /// Writes the fuller check file: no fill, no line, a gradient shape made solid, and a clear shape over another.
    func testWritesTheFillAndLineCheckFile() throws {
        let dir = "/data/s/amd-6/ui-check"
        guard FileManager.default.fileExists(atPath: dir) else { return }
        let deck = try deckWithGradientShape()
        func place(_ s: SlideShape, _ x: Double, _ y: Double) { s.frame = Rect.fromLTWH(x, y, 160, 90) }
        let noFill = deck.addShape(.rect); place(noFill, 40, 40)
        deck.selectShapes([noFill]); deck.setFill(nil); deck.setOutline(Color(0xFF000000)); deck.setOutlineWidth(2)
        let noLine = deck.addShape(.rect); place(noLine, 240, 40)
        deck.selectShapes([noLine]); deck.setFill(Color(0xFF4472C4)); deck.setOutline(nil)
        let under = deck.addShape(.rect); place(under, 440, 40)
        deck.selectShapes([under]); deck.setFill(Color(0xFFC00000)); deck.setOutline(nil)
        let over = deck.addShape(.rect); place(over, 480, 70)
        deck.selectShapes([over]); deck.setFill(Color(0xFF0070C0)); deck.setFillTransparency(50); deck.setOutline(nil)
        let g = try XCTUnwrap(deck.currentSlide.shapes.first { $0.name == "Grad" })
        g.frame = Rect.fromLTWH(40, 200, 160, 90)
        deck.selectShapes([g]); deck.setFill(Color(0xFF70AD47)); deck.setOutline(Color(0xFF7030A0))
        try Pptx.write(deck).write(to: URL(fileURLWithPath: dir + "/fill-line2.pptx"))
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
