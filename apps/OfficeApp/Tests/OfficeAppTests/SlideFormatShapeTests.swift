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

    func testRotationPresetIsWrittenReplacedAndUndone() throws {
        let deck = DeckController()
        let a = deck.addShape(.rect); deck.selectShapes([a])
        deck.setCamera("isometricOffAxis1Right")
        XCTAssertEqual(a.scene3d?.cameraName, "isometricOffAxis1Right")
        var xml = try slideXML(deck)
        XCTAssertTrue(xml.contains("<a:scene3d><a:camera prst=\"isometricOffAxis1Right\"/><a:lightRig rig=\"threePt\" dir=\"t\"/></a:scene3d>"))
        let (back, _, _) = try Pptx.read(Pptx.write(deck))
        XCTAssertEqual(back.slides[0].shapes.first { $0.name == a.name }?.scene3d?.cameraName, "isometricOffAxis1Right")
        // Another preset replaces the camera, never adds a second scene.
        deck.setCamera("perspectiveLeft")
        xml = try slideXML(deck)
        XCTAssertEqual(xml.components(separatedBy: "<a:scene3d>").count, 2)
        XCTAssertTrue(xml.contains("prst=\"perspectiveLeft\""))
        if let dir = ProcessInfo.processInfo.environment["AMD6_UI_CHECK_DIR"], ProcessInfo.processInfo.environment["AMD6_CHECK_DECK"] != nil {
            // A PowerPoint check deck: one shape per preset, patched afterwards (depth, bevel, labels) by a script.
            let d = DeckController()
            let presets = ["isometricLeftDown", "isometricRightUp", "isometricTopUp", "isometricOffAxis1Right", "isometricOffAxis2Top",
                           "obliqueTopLeft", "obliqueBottomRight", "perspectiveLeft", "perspectiveAbove", "perspectiveRelaxed",
                           "perspectiveHeroicExtremeLeftFacing", "isometricOffAxis1Right", "obliqueTopRight", "isometricLeftDown"]
            for (i, p) in presets.enumerated() {
                let s = d.addShape(.rect); d.selectShapes([s])
                d.setFramesLive([(s, Rect.fromLTWH(30 + Double(i % 4) * 230, 40 + Double(i / 4) * 125, 130, 70))])
                d.setCamera(p)
                s.name = "chk\(i)_\(p)"
            }
            try Pptx.write(d).write(to: URL(fileURLWithPath: dir + "/rotation-base.pptx"))
        }
        if let dir = ProcessInfo.processInfo.environment["AMD6_UI_CHECK_DIR"] {
            let d = DeckController()
            for (i, p) in ["isometricOffAxis1Right", "perspectiveLeft", "obliqueTopRight", "perspectiveAbove"].enumerated() {
                let s = d.addShape(.rect); d.selectShapes([s])
                d.setFramesLive([(s, Rect.fromLTWH(40 + Double(i % 2) * 300, 40 + Double(i / 2) * 200, 200, 120))])
                d.setCamera(p)
            }
            try Pptx.write(d).write(to: URL(fileURLWithPath: dir + "/rotation.pptx"))
        }
        deck.setCamera("orthographicFront")
        XCTAssertNil(a.scene3d)
        deck.undo(); deck.undo(); deck.undo()
        XCTAssertNil(try XCTUnwrap(deck.slides[0].shapes.first { $0.name == a.name }).camera)
        XCTAssertFalse(try slideXML(deck).contains("<a:scene3d>"))
    }

    func testShadowFromThePaneAndOnAFileShape() throws {
        // A new shape: the check box turns a default shadow on, the rows edit it, the file holds it, undo takes it back.
        let deck = DeckController()
        let a = deck.addShape(.rect); deck.selectShapes([a])
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SizedBox(width: 400, height: 780, child: FormatShapePane(deck: deck, onClose: {})), title: "Test"), size: Size(1280, 800))
        settle(ui)
        // The pane's lower rows lie below the test window's bottom edge: reach them through their own callbacks.
        func control<W>(_ id: String, _ type: W.Type) -> W? {
            var found: W?
            for e in ui.elements() where (e.widget.key as? ValueKey<String>)?.value == id {
                if let w = e.widget as? W { return w }
                e.visitChildElements { c in
                    func walk(_ x: Element) { if found == nil, let w = x.widget as? W { found = w }; x.visitChildElements(walk) }
                    walk(c)
                }
            }
            return found
        }
        func enter(_ id: String, _ text: String) { control(id, FluentTextBox.self)?.onSubmitted?(text); settle(ui) }
        XCTAssertNil(a.shadow)
        control("fmt.shadow.on", Checkbox.self)?.onChanged?(true); settle(ui)
        XCTAssertNotNil(a.shadow)
        enter("fmt.shadow.blur", "10"); enter("fmt.shadow.distance", "6"); enter("fmt.shadow.angle", "90"); enter("fmt.shadow.transparency", "0")
        let sh = try XCTUnwrap(a.shadow)
        XCTAssertEqual(sh.blur, 10, accuracy: 0.01); XCTAssertEqual(sh.dy, 6, accuracy: 0.01); XCTAssertEqual(sh.dx, 0, accuracy: 0.01)
        XCTAssertEqual(sh.color.value >> 24, 255)
        let xml = try slideXML(deck)
        XCTAssertTrue(xml.contains("<a:outerShdw blurRad=\"127000\" dist=\"76200\" dir=\"5400000\""))
        let (back, _, _) = try Pptx.read(Pptx.write(deck))
        XCTAssertEqual(try XCTUnwrap(back.slides[0].shapes.first { $0.name == a.name }?.shadow).blur, 10, accuracy: 0.01)
        deck.undo()
        XCTAssertEqual(try XCTUnwrap(a.shadow).color.value >> 24, 0x66)

        // A file shape with a glow, a shadow and a soft edge: the shadow changes, the others stay.
        let fx = "<a:effectLst><a:glow rad=\"63500\"><a:srgbClr val=\"FFFF00\"/></a:glow>"
            + "<a:outerShdw blurRad=\"50800\" dist=\"38100\" dir=\"2700000\"><a:srgbClr val=\"000000\"/></a:outerShdw><a:softEdge rad=\"12700\"/></a:effectLst>"
        let d2 = try deckWithGradientShape(effects: fx)
        let g = try XCTUnwrap(d2.currentSlide.shapes.first { $0.name == "Grad" })
        d2.selectShapes([g])
        var moved = try XCTUnwrap(g.shadow); moved.blur = 20
        d2.setShadow(moved)
        let x2 = shapeXML(try slideXML(d2), "Grad")
        XCTAssertTrue(x2.contains("blurRad=\"254000\""), "the new blur")
        XCTAssertFalse(x2.contains("blurRad=\"50800\""), "the old shadow is gone, not doubled")
        XCTAssertEqual(x2.components(separatedBy: "<a:outerShdw").count, 2)
        XCTAssertTrue(x2.contains("<a:glow rad=\"63500\">")); XCTAssertTrue(x2.contains("<a:softEdge rad=\"12700\"/>"))
        XCTAssertTrue(x2.range(of: "<a:glow")!.lowerBound < x2.range(of: "<a:outerShdw")!.lowerBound, "schema order: glow, then shadow")
        XCTAssertTrue(x2.range(of: "<a:outerShdw")!.lowerBound < x2.range(of: "<a:softEdge")!.lowerBound)
        d2.setShadow(nil)
        let x3 = shapeXML(try slideXML(d2), "Grad")
        XCTAssertFalse(x3.contains("outerShdw")); XCTAssertTrue(x3.contains("<a:glow"))
    }

    func testScalePercentFromThePane() throws {
        let deck = DeckController()
        let a = deck.addShape(.rect)
        a.frame = Rect.fromLTWH(50, 50, 200, 100)
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
        enter("fmt.scale.width", "50")
        XCTAssertEqual(a.frame.width, 100, accuracy: 0.01); XCTAssertEqual(a.frame.height, 100, accuracy: 0.01, "unlocked: height alone stays")
        enter("fmt.scale.height", "200")
        XCTAssertEqual(a.frame.height, 200, accuracy: 0.01)
        enter("fmt.scale.width", "100")
        XCTAssertEqual(a.frame.width, 200, accuracy: 0.01, "100% is the size it had when first scaled")
        deck.setAspectLock(true)
        enter("fmt.scale.width", "50")
        XCTAssertEqual(a.frame.width, 100, accuracy: 0.01); XCTAssertEqual(a.frame.height, 50, accuracy: 0.01, "locked: both sides scale together")
        XCTAssertEqual(a.frame.left, 50); XCTAssertEqual(a.frame.top, 50)
        deck.undo()
        XCTAssertEqual(a.frame.width, 200, accuracy: 0.01)
    }

    func testDashTypeFromThePaneSurvivesSaving() throws {
        let deck = DeckController()
        let a = deck.addShape(.rect)
        deck.selectShapes([a])
        deck.setOutline(Color(0xFF123456))
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: FormatShapePane(deck: deck, onClose: {}), title: "Test"),
                              size: Size(1280, 800))
        settle(ui)
        XCTAssertTrue(ui.has(text: "Solid"))
        ui.tap(id: "fmt.line.dash"); settle(ui)
        XCTAssertEqual(a.outlineDash, "sysDot")
        ui.tap(id: "fmt.line.dash"); ui.tap(id: "fmt.line.dash"); settle(ui)
        XCTAssertEqual(a.outlineDash, "dash")
        XCTAssertTrue(ui.has(text: "Dash"))
        let (state, _, _) = try Pptx.read(Pptx.write(deck))
        XCTAssertEqual(try XCTUnwrap(state.slides[0].shapes.first { $0.name == a.name }).outlineDash, "dash")
        deck.undo()
        XCTAssertEqual(a.outlineDash, "sysDash")
    }

    func testDashOnAFileLineReplacesOnlyTheDash() throws {
        let deck = try deckWithGradientShape()
        let g = try XCTUnwrap(deck.currentSlide.shapes.first { $0.name == "Grad" })
        deck.selectShapes([g])
        deck.setOutlineDash("sysDot")
        let x = shapeXML(try slideXML(deck), "Grad")
        XCTAssertTrue(x.contains("prstDash val=\"sysDot\"") && !x.contains("val=\"dash\""))
        XCTAssertTrue(x.contains("00AA00") && x.contains("<a:round/>") && x.contains("tailEnd"), "colour, join, arrowhead kept")
        XCTAssertTrue(x.contains("<a:gradFill"), "the shape's fill is not touched")
        deck.setOutlineDash(nil)
        XCTAssertFalse(shapeXML(try slideXML(deck), "Grad").contains("prstDash"), "solid again")
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
    private func deckWithGradientShape(effects: String = "", style: String = "") throws -> DeckController {
        let (_, _, _) = try Pptx.read(Pptx.write(SlidesSample.make()))
        var package = PptxPackage(try Zip.read(try Pptx.write(SlidesSample.make())))
        let sp = "<p:sp><p:nvSpPr><p:cNvPr id=\"91\" name=\"Grad\"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>"
            + "<p:spPr><a:xfrm><a:off x=\"1270000\" y=\"3810000\"/><a:ext cx=\"2540000\" cy=\"1270000\"/></a:xfrm>"
            + "<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom>"
            + "<a:gradFill><a:gsLst><a:gs pos=\"0\"><a:srgbClr val=\"FF0000\"/></a:gs><a:gs pos=\"100000\"><a:srgbClr val=\"0000FF\"/></a:gs></a:gsLst><a:lin ang=\"0\"/></a:gradFill>"
            + "<a:ln w=\"25400\"><a:solidFill><a:srgbClr val=\"00AA00\"/></a:solidFill><a:prstDash val=\"dash\"/><a:round/><a:tailEnd type=\"triangle\"/></a:ln>" + effects + "</p:spPr>" + style + "</p:sp>"
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

    func testEditingAShadowKeepsItsTransparencyAndRemovingAThemeShadowKeepsTheStyle() throws {
        // (1) A file shadow with 40% opacity keeps its alpha when only the blur changes.
        let fx = "<a:effectLst><a:outerShdw blurRad=\"50800\" dist=\"38100\" dir=\"2700000\"><a:srgbClr val=\"112233\"><a:alpha val=\"40000\"/></a:srgbClr></a:outerShdw></a:effectLst>"
        let deck = try deckWithGradientShape(effects: fx)
        let g = try XCTUnwrap(deck.currentSlide.shapes.first { $0.name == "Grad" })
        deck.selectShapes([g])
        var sh = try XCTUnwrap(g.shadow); sh.blur = 9
        deck.setShadow(sh)
        let xml = shapeXML(try slideXML(deck), "Grad")
        XCTAssertTrue(xml.contains("<a:alpha val=\"40000\"/>"), xml)
        XCTAssertTrue(xml.contains("112233"))
        XCTAssertTrue(xml.contains("blurRad=\"114300\""))
        // (2) A shape whose shadow comes from the theme (style effectRef): removing it writes an empty list, the style stays.
        let style = "<p:style><a:lnRef idx=\"1\"><a:schemeClr val=\"accent1\"/></a:lnRef><a:fillRef idx=\"1\"><a:schemeClr val=\"accent1\"/></a:fillRef><a:effectRef idx=\"2\"><a:schemeClr val=\"accent1\"/></a:effectRef><a:fontRef idx=\"minor\"><a:schemeClr val=\"lt1\"/></a:fontRef></p:style>"
        let d2 = try deckWithGradientShape(style: style)
        let g2 = try XCTUnwrap(d2.currentSlide.shapes.first { $0.name == "Grad" })
        d2.selectShapes([g2])
        d2.setShadow(FormatShapePaneState.defaultShadow); d2.setShadow(nil)
        let x2 = shapeXML(try slideXML(d2), "Grad")
        XCTAssertTrue(x2.contains("<a:effectLst></a:effectLst>") || x2.contains("<a:effectLst/>"), x2)
        XCTAssertTrue(x2.contains("<a:effectRef idx=\"2\">"), "the style stays")
        XCTAssertFalse(x2.contains("outerShdw"))
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

    func testAColourChangeKeepsTheDashJoinAndArrowhead() throws {
        let deck = try deckWithGradientShape()
        let g = try XCTUnwrap(deck.currentSlide.shapes.first { $0.name == "Grad" })
        deck.selectShapes([g])
        deck.setOutline(Color(0xFF123456))
        var x = shapeXML(try slideXML(deck), "Grad")
        XCTAssertTrue(x.contains("prstDash val=\"dash\""), "still dashed")
        XCTAssertTrue(x.contains("<a:round/>") && x.contains("tailEnd"), "join and arrowhead kept")
        XCTAssertTrue(x.contains("123456") && !x.contains("00AA00"), "new colour only")
        deck.setOutlineWidth(4)
        x = shapeXML(try slideXML(deck), "Grad")
        XCTAssertTrue(x.contains("w=\"50800\"") && x.contains("prstDash"), "width changes, dash stays")
        deck.setOutline(nil)
        x = shapeXML(try slideXML(deck), "Grad")
        XCTAssertTrue(x.contains("prstDash"), "no line keeps the rest too")
        XCTAssertFalse(x.contains("123456"))
    }

    /// Writes the dash check file: one line shape per dash style, plus a file line whose dash was swapped.
    func testWritesTheDashCheckFile() throws {
        let dir = "/data/s/amd-6/ui-check"
        guard FileManager.default.fileExists(atPath: dir) else { return }
        let deck = try deckWithGradientShape()
        var y = 30.0
        for (dash, _) in FormatShapePaneState.dashStyles {
            let s = deck.addShape(.rect); s.frame = Rect.fromLTWH(40, y, 300, 24); y += 40
            deck.selectShapes([s]); deck.setFill(nil); deck.setOutline(Color(0xFF1F4E79)); deck.setOutlineWidth(3); deck.setOutlineDash(dash)
        }
        let g = try XCTUnwrap(deck.currentSlide.shapes.first { $0.name == "Grad" })
        g.frame = Rect.fromLTWH(400, 200, 160, 90)
        deck.selectShapes([g]); deck.setOutlineDash("sysDot")
        // A shape scaled to 150% by 50%, and a locked shape resized in proportion (200x100 to 300x150).
        let sc = deck.addShape(.rect); sc.frame = Rect.fromLTWH(400, 40, 100, 100)
        deck.selectShapes([sc]); deck.setScale(width: 150, height: 50)
        let lk = deck.addShape(.ellipse); lk.frame = Rect.fromLTWH(400, 320, 200, 100); lk.aspectLock = true
        lk.frame = SlideCanvasState.resizedFrame(lk.frame, rotation: 0, handle: 4, delta: Offset(100, 5), keepAspect: true)
        try Pptx.write(deck).write(to: URL(fileURLWithPath: dir + "/dash.pptx"))
    }

    /// Writes the effects check file: a new shape with a shadow, one with a long soft shadow, and a file shape whose shadow is edited next to its glow.
    func testWritesTheEffectsCheckFile() throws {
        let dir = "/data/s/amd-6/ui-check"
        guard FileManager.default.fileExists(atPath: dir) else { return }
        let fx = "<a:effectLst><a:glow rad=\"101600\"><a:srgbClr val=\"FFC000\"><a:alpha val=\"40000\"/></a:srgbClr></a:glow>"
            + "<a:outerShdw blurRad=\"50800\" dist=\"38100\" dir=\"2700000\"><a:srgbClr val=\"000000\"/></a:outerShdw></a:effectLst>"
        let deck = try deckWithGradientShape(effects: fx)
        let g = try XCTUnwrap(deck.currentSlide.shapes.first { $0.name == "Grad" })
        g.frame = Rect.fromLTWH(400, 200, 160, 90)
        deck.selectShapes([g])
        var sh = try XCTUnwrap(g.shadow); sh.blur = 12; sh.dx = 0; sh.dy = 10
        deck.setShadow(sh)
        let a = deck.addShape(.rect); a.frame = Rect.fromLTWH(40, 40, 200, 100)
        deck.selectShapes([a]); deck.setFill(Color(0xFF4472C4)); deck.setShadow(FormatShapePaneState.defaultShadow)
        let b = deck.addShape(.ellipse); b.frame = Rect.fromLTWH(40, 220, 200, 100)
        deck.selectShapes([b]); deck.setFill(Color(0xFFED7D31))
        deck.setShadow(CharShadow(color: Color(0x80000000), dx: 14, dy: 14, blur: 16))
        let c = deck.addShape(.rect); c.frame = Rect.fromLTWH(40, 400, 200, 80)
        deck.selectShapes([c]); deck.setFill(Color(0xFF70AD47)); deck.setShadow(FormatShapePaneState.defaultShadow); deck.setShadow(nil)
        try Pptx.write(deck).write(to: URL(fileURLWithPath: dir + "/effects.pptx"))
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
