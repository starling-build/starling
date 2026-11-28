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

    func testPictureTransparencyFromThePane() throws {
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
        let deck = DeckController()
        let shape = deck.addShape(.rect)
        deck.selectShapes([shape])
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: FormatShapePane(deck: deck, onClose: {}), title: "Test"),
                              size: Size(1280, 800))
        settle(ui)
        XCTAssertFalse(ui.has(id: "fmt.pic.alpha.slider"), "a shape has no Picture section")
        let pic = deck.addPicture(ImageAttachment(data: png, width: 1, height: 1), naturalSize: Size(100, 100))
        deck.selectShapes([pic]); settle(ui)
        let c = try XCTUnwrap(ui.centre(id: "fmt.pic.alpha.slider"))
        ui.drag(from: c, to: Offset(c.dx + 60, c.dy)); settle(ui)
        XCTAssertLessThan(pic.pictureAlpha, 0.4, "the slider drags the picture past half see-through")
        XCTAssertGreaterThan(pic.pictureAlpha, 0.05)
        deck.undo(); settle(ui)
        XCTAssertEqual(pic.pictureAlpha, 1, "the whole drag is one undo step")
        deck.undo(); settle(ui)
        XCTAssertFalse(deck.currentSlide.shapes.contains { $0.picture != nil }, "the next undo takes the picture away: no empty step")
        deck.redo(); settle(ui)
        let again = try XCTUnwrap(deck.currentSlide.shapes.first { $0.picture != nil })
        deck.selectShapes([again]); settle(ui)
        ui.tap(id: "fmt.pic.alpha")
        for _ in 0 ..< 6 { ui.press(.backspace) }
        ui.type("30"); ui.press(.enter); settle(ui)
        XCTAssertEqual(again.pictureAlpha, 0.7, accuracy: 1e-9, "a typed percent applies on Enter")
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
        deck.undo(); settle(ui); XCTAssertNotNil(a.fill, "one undo brings the fill back")
        XCTAssertEqual(deck.selection.map(\.id), [a.id], "and keeps the shape selected")
        ui.tap(id: "fmt.fill.none"); settle(ui)
        XCTAssertNil(a.fill)
        ui.tap(id: "fmt.fill.none"); settle(ui)
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
        if let dir = ProcessInfo.processInfo.environment["AMD6_UI_CHECK_DIR"], ProcessInfo.processInfo.environment["AMD6_CHECK_DECK2"] != nil {
            // The presets the first check deck did not print: all other isometric, oblique (with depth) and perspective ones.
            let iso = ["isometricBottomDown", "isometricBottomUp", "isometricLeftUp", "isometricRightDown", "isometricTopDown",
                       "isometricOffAxis1Left", "isometricOffAxis1Top", "isometricOffAxis2Left", "isometricOffAxis2Right",
                       "isometricOffAxis3Left", "isometricOffAxis3Right", "isometricOffAxis3Bottom", "isometricOffAxis4Left",
                       "isometricOffAxis4Right", "isometricOffAxis4Bottom"]
            let obl = ["obliqueBottom", "obliqueBottomLeft", "obliqueBottomRight", "obliqueLeft", "obliqueRight", "obliqueTop",
                       "obliqueTopLeft", "obliqueTopRight"]
            let per = ["perspectiveFront", "perspectiveRight", "perspectiveBelow", "perspectiveAboveLeftFacing", "perspectiveAboveRightFacing",
                       "perspectiveContrastingLeftFacing", "perspectiveContrastingRightFacing", "perspectiveHeroicLeftFacing",
                       "perspectiveHeroicRightFacing", "perspectiveHeroicExtremeRightFacing", "perspectiveRelaxedModerately", "orthographicFront"]
            let d = DeckController()
            _ = d.addSlide(.blank); _ = d.addSlide(.blank); _ = d.addSlide(.blank)
            d.deleteSlide(0)
            var s1: [String] = Array(iso.suffix(3))
            s1.append(contentsOf: obl)
            var s0: [String] = []
            s0.append(contentsOf: iso.prefix(12))
            let sets: [[String]] = [s0, s1, per]
            for (si, names) in sets.enumerated() {
                d.selectSlide(si)
                for (i, p) in names.enumerated() {
                    let s = d.addShape(.rect); d.selectShapes([s])
                    let x: Double = 40 + Double(i % 4) * 225
                    let y: Double = 30 + Double(i / 4) * 165
                    d.setFramesLive([(s, Rect.fromLTWH(x, y, 120, 70))])
                    d.setCamera(p)
                    s.name = "chk\(si)_\(i)_\(p)"
                }
            }
            try Pptx.write(d).write(to: URL(fileURLWithPath: dir + "/rotation2-base.pptx"))
        }
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

    /// PowerPoint's own RotX/RotY/RotZ for presets (rotation2-angles.txt): lat = RotY, lon = -RotX, rev = -RotZ.
    func testCameraTableHoldsPowerPointsAngles() throws {
        let want: [(String, Double, Double, Double)] = [
            ("isometricBottomDown", 35.396, 314.719, 299.838), ("isometricOffAxis3Bottom", 58.738, 306.546, 302.357),
            ("isometricOffAxis4Left", 342, 26, 0), ("perspectiveAboveLeftFacing", 39.306, 14.338, 341.124),
            ("perspectiveHeroicRightFacing", 348.984, 345.707, 357.373)]
        for (n, la, lo, re) in want {
            let s = try XCTUnwrap(Extrusion.scene(camera: n, from: nil), n)
            XCTAssertEqual(s.lat, la, accuracy: 0.01, n); XCTAssertEqual(s.lon, lo, accuracy: 0.01, n)
            XCTAssertEqual(s.rev, re, accuracy: 0.01, n)
        }
        XCTAssertNil(Extrusion.scene(camera: "orthographicFront", from: nil))
    }

    func testTextLiesOnTheTiltedFace() throws {
        XCTAssertNil(Extrusion.frontMap(Scene3D(depth: 0)))
        let s = try XCTUnwrap(Extrusion.scene(camera: "isometricLeftDown", from: nil))
        let m = try XCTUnwrap(Extrusion.frontMap(s))
        // The shape's x step shortens to .707 across and slides down by .408; its y step stays upright and keeps .816 of its length.
        XCTAssertEqual(m.a, 0.707, accuracy: 0.01); XCTAssertEqual(abs(m.b), 0.408, accuracy: 0.01)
        XCTAssertEqual(m.c, 0, accuracy: 0.01); XCTAssertEqual(m.d, 0.816, accuracy: 0.01)
        // A legacy camera's turn leaves the text flat, as PowerPoint prints fr-f0244d46aa slide 26.
        var legacy = try XCTUnwrap(Extrusion.read(XNode.parse(Data("<p:spPr xmlns:p=\"p\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\"><a:scene3d><a:camera prst=\"legacyPerspectiveFront\"><a:rot lat=\"1500000\" lon=\"20099999\" rev=\"0\"/></a:camera></a:scene3d><a:sp3d extrusionH=\"887400\"/></p:spPr>".utf8)), colors: ColorContext(theme: PptxTheme(nil))))
        XCTAssertTrue(legacy.legacy)
        XCTAssertNil(Extrusion.frontMap(legacy))
        legacy.legacy = false
        XCTAssertNotNil(Extrusion.frontMap(legacy))
    }

    func testTextTapersWithAPerspectiveFace() throws {
        func at(_ m: [Double], _ x: Double, _ y: Double) -> Offset {
            let w = m[3] * x + m[7] * y + m[15]
            return Offset((m[0] * x + m[4] * y + m[12]) / w, (m[1] * x + m[5] * y + m[13]) / w)
        }
        let c = Offset(300, 200)
        // An orthographic turn keeps parallel lines parallel: no divide.
        let iso = try XCTUnwrap(Extrusion.frontTransform(XCTUnwrap(Extrusion.scene(camera: "isometricLeftDown", from: nil)), center: c, pxPerPt: 1))
        XCTAssertEqual(iso[3], 0); XCTAssertEqual(iso[7], 0); XCTAssertEqual(iso[15], 1)
        // Under perspectiveHeroicExtremeLeftFacing (80 deg lens) the face's middle stays put and its
        // two upright edges print at different heights, as the face's own corners do:
        // rotation-check's text spans 510.8-604.2 pt on PowerPoint's print (a flat-tilt map gave 508.0-601.8).
        let s = try XCTUnwrap(Extrusion.scene(camera: "perspectiveHeroicExtremeLeftFacing", from: nil))
        let m = try XCTUnwrap(Extrusion.frontTransform(s, center: c, pxPerPt: 1))
        let o = at(m, c.dx, c.dy)
        XCTAssertEqual(o.dx, c.dx, accuracy: 1e-9); XCTAssertEqual(o.dy, c.dy, accuracy: 1e-9)
        let left = at(m, c.dx - 60, c.dy + 35).dy - at(m, c.dx - 60, c.dy - 35).dy
        let right = at(m, c.dx + 60, c.dy + 35).dy - at(m, c.dx + 60, c.dy - 35).dy
        XCTAssertGreaterThan(abs(left - right), 3)
        // The same corner through the solid's own projection: q = R p, drawn at q * eye / (eye - q.z).
        let f = try XCTUnwrap(Extrusion.frontMap(s))
        let eye = Extrusion.eye(s)
        let lat = -s.lat * .pi / 180, lon = -s.lon * .pi / 180
        let qz = { (x: Double, y: Double) in y * sin(lat) + (-x * sin(lon)) * cos(lat) }(60, 35)
        let k = eye / (eye - qz)
        let p = at(m, c.dx + 60, c.dy + 35)
        XCTAssertEqual(p.dx, c.dx + (f.a * 60 + f.c * 35) * k, accuracy: 1e-6)
        XCTAssertEqual(p.dy, c.dy + (f.b * 60 + f.d * 35) * k, accuracy: 1e-6)
        // A legacy camera leaves the text flat.
        var legacy = s; legacy.legacy = true
        XCTAssertNil(Extrusion.frontTransform(legacy, center: c, pxPerPt: 1))
    }

    func testTurnedFaceCatchesThreePtGlintTowardTheEye() throws {
        // PowerPoint's prints of flat 2B6CB0 rects under threePt (rotation-check, rotation2-check):
        // the face is 1.04 x the fill plus this white. It follows where the eye stands, not just
        // how far the face is turned: the four isometric presets turn it equally and print .209,
        // .064, .002 and .009.
        func white(_ camera: String) throws -> Double {
            let s = try XCTUnwrap(Extrusion.scene(camera: camera, from: nil))
            return Extrusion.threePtFaceWhite(toward: Extrusion.towardEye(s))
        }
        for (camera, ppt) in [("isometricLeftUp", 0.209), ("isometricTopDown", 0.209), ("isometricRightUp", 0.064),
                              ("isometricLeftDown", 0.002), ("isometricRightDown", 0.009), ("isometricOffAxis4Left", 0.174),
                              ("perspectiveRelaxedModerately", 0.237), ("perspectiveHeroicLeftFacing", 0.111)] {
            XCTAssertEqual(try white(camera), ppt, accuracy: 0.012, camera)
        }
        // The eye's direction: what the camera turn takes to the line of sight.
        let s = try XCTUnwrap(Extrusion.scene(camera: "perspectiveRelaxed", from: nil))
        let v = Extrusion.towardEye(s)
        let lat = -s.lat * .pi / 180, lon = -s.lon * .pi / 180
        let qz0 = -v.x * sin(lon) + v.z * cos(lon)
        XCTAssertEqual(v.x * cos(lon) + v.z * sin(lon), 0, accuracy: 1e-9)
        XCTAssertEqual(v.y * cos(lat) - qz0 * sin(lat), 0, accuracy: 1e-9)
    }

    func testObliqueAndSquareOnFacesCatchThreePtGlint() throws {
        // A non-legacy oblique preset's eye leans toward its slide, the same amount every way,
        // and PowerPoint's prints (rotation-check) add white to match.
        for (camera, ppt) in [("obliqueRight", 0.037), ("obliqueTop", 0.009), ("obliqueBottomRight", 0.107),
                              ("obliqueBottomLeft", 0.037), ("obliqueBottom", 0.107), ("obliqueLeft", 0.005)] {
            let s = try XCTUnwrap(Extrusion.scene(camera: camera, from: Scene3D(depth: 10)))
            XCTAssertEqual(Extrusion.threePtFaceWhite(toward: Extrusion.towardEye(s)), ppt, accuracy: 0.012, camera)
        }
        // Looking square on, the face still catches .025 (perspectiveFront prints it); an
        // orthographicFront or legacy camera stays plain.
        XCTAssertEqual(Extrusion.threePtFaceWhite(toward: Extrusion.P3(x: 0, y: 0, z: 1)), 0.025, accuracy: 0.005)
        var s = Scene3D(depth: 0)
        for (camera, glints) in [("perspectiveFront", true), ("obliqueTopLeft", true), ("orthographicFront", false),
                                 ("legacyObliqueFront", false)] {
            s.cameraName = camera; s.legacy = camera.hasPrefix("legacy")
            XCTAssertEqual(Extrusion.glintsSquareOn(s), glints, camera)
        }
        s.cameraName = "perspectiveFront"; s.material = "matte"
        XCTAssertFalse(Extrusion.glintsSquareOn(s))
    }

    func testIsometricTopCamerasAreTrueIsometric() throws {
        // PowerPoint's print of a 130x70 rect under isometricTopUp (rotation-check.pdf): corners at (-71.5,11.5), (71.5,-12.5),
        // (21,-41.5), (-22,41.5) from the centre, i.e. rows (.707,.707) and (-.408,.408) of the turn.
        let s = try XCTUnwrap(Extrusion.scene(camera: "isometricTopUp", from: nil))
        func rad(_ d: Double) -> Double { -d * .pi / 180 }
        let (la, lo, re) = (rad(s.lat), rad(s.lon), rad(s.rev))
        // x' and y' of the unit x and y axes through Ry(lon), Rx(lat), Rz(rev), as in Extrusion.solid.
        func project(_ x: Double, _ y: Double) -> (Double, Double) {
            var (px, py, pz) = (x * cos(lo), y, -x * sin(lo))
            (py, pz) = (py * cos(la) - pz * sin(la), py * sin(la) + pz * cos(la))
            return (px * cos(re) - py * sin(re), px * sin(re) + py * cos(re))
        }
        let (ax, ay) = project(1, 0), (bx, by) = project(0, 1)
        XCTAssertEqual(ax, 0.7071, accuracy: 0.01); XCTAssertEqual(bx, 0.7071, accuracy: 0.01)
        XCTAssertEqual(ay, -0.4082, accuracy: 0.01); XCTAssertEqual(by, 0.4082, accuracy: 0.01)
    }

    func testGlowAndSoftEdgeFromThePane() throws {
        // The check box turns a glow on in the first accent, the rows size the glow and the soft edge, the file holds both, undo steps back.
        let deck = DeckController()
        let a = deck.addShape(.rect); deck.selectShapes([a])
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SizedBox(width: 400, height: 780, child: FormatShapePane(deck: deck, onClose: {})), title: "Test"), size: Size(1280, 800))
        settle(ui)
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
        XCTAssertNotNil(control("fmt.glow.on", Checkbox.self))
        control("fmt.glow.on", Checkbox.self)?.onChanged?(true); settle(ui)
        XCTAssertEqual(a.glowRadius, 10)
        XCTAssertEqual(a.glowColor, ShapeEffectPresets.glowColor(deck.theme.accents[0]))
        enter("fmt.glow.size", "8"); enter("fmt.softedge.size", "5")
        XCTAssertEqual(a.glowRadius, 8); XCTAssertEqual(a.softEdge, 5)
        let xml = try slideXML(deck)
        XCTAssertTrue(xml.contains("<a:glow rad=\"101600\">"))
        XCTAssertTrue(xml.contains("<a:softEdge rad=\"63500\"/>"))
        deck.undo()
        XCTAssertNil(a.softEdge); XCTAssertEqual(a.glowRadius, 8)
        deck.selectShapes([a]); settle(ui)  // undo drops the selection
        enter("fmt.softedge.size", "0"); XCTAssertNil(a.softEdge)
        control("fmt.glow.on", Checkbox.self)?.onChanged?(false); settle(ui)
        XCTAssertNil(a.glowRadius)
        XCTAssertFalse(try slideXML(deck).contains("<a:glow"))
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

/// ⌘Z after a change made from the Format Shape pane undoes it, even while a pane box had the keyboard (the
/// boxes keep no undo of their own, and a box passes no undo chord on).
final class SlideFormatShapeUndoTests: XCTestCase {
    private func settle(_ ui: WidgetTester) {
        for _ in 0 ..< 3 { ui.pump(); for cb in FrameCallbackScheduler.shared.takePostFrameCallbacks() { cb(.zero) } }
        ui.pump()
    }

    private func undoChord(_ ui: WidgetTester) {
        let main: Int64 = KeyModifiers.primary == .meta ? 0xFFE7 : 0xFFE3
        func send(_ l: Int64, _ t: KeyEventType) {
            FocusManager.instance.dispatchKeyData(KeyData(timeStamp: 0, type: t, physical: 0, logical: l, character: nil, synthesized: false))
        }
        send(main, .down); send(0x7A, .down); send(0x7A, .up); send(main, .up); settle(ui)
    }

    func testUndoChordAfterAPaneChangeWhileABoxHadTheKeyboard() throws {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SlidesShell(initialPath: nil, startBlank: true, onSwitch: { _, _ in }), title: "Test"),
                              size: Size(1440, 932))
        settle(ui)
        let shell = try XCTUnwrap(ui.state(SlidesShellState.self))
        let deck = try XCTUnwrap(shell.session.deck)
        let a = deck.addShape(.rect)
        deck.selectShapes([a]); settle(ui)
        shell.session.onFormatShape?(); settle(ui)
        // Enter in a box applies the width; ⌘Z straight after takes it back.
        let width = a.frame.width
        ui.tap(id: "fmt.width"); settle(ui)
        let box = try XCTUnwrap(FocusManager.instance.focusedNode, "the box has the keyboard")
        for _ in 0 ..< 10 { ui.press(.backspace) }
        ui.type("200"); ui.press(.enter); settle(ui)
        XCTAssertEqual(a.frame.width, 200, accuracy: 0.01)
        XCTAssertFalse(FocusManager.instance.focusedNode === box, "the edit took the keyboard back from the box")
        undoChord(ui)
        XCTAssertEqual(a.frame.width, width, accuracy: 0.01, "⌘Z undid the width")
        // A box has the keyboard, then a check box (not a box) changes the shape.
        ui.tap(id: "fmt.line.width"); settle(ui)
        let line = try XCTUnwrap(FocusManager.instance.focusedNode, "the box has the keyboard")
        XCTAssertNotNil(a.fill)
        ui.tap(id: "fmt.fill.none"); settle(ui)
        XCTAssertNil(a.fill)
        XCTAssertFalse(FocusManager.instance.focusedNode === line)
        undoChord(ui)
        XCTAssertNotNil(a.fill, "⌘Z brought the fill back")
    }
}
