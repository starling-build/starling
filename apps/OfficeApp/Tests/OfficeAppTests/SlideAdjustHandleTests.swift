import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// S-SH-2: a preset's yellow handles (corner radius, arrow head, pie angles...) are drawn, drag, undo, and their
/// values reach the file.
final class SlideAdjustHandleTests: XCTestCase {
    private func slideXML(_ data: Data) throws -> String {
        let p = PptxPackage(try Zip.read(data))
        let part = try XCTUnwrap(p.parts.keys.first { $0.hasPrefix("ppt/slides/slide") && !$0.contains("_rels") })
        return String(data: p.parts[part]!, encoding: .utf8)!
    }

    private func sp(_ xml: String) throws -> String {
        String(xml[try XCTUnwrap(xml.range(of: "<p:sp>((?!</p:sp>).)*prst=\"roundRect\".*?</p:sp>", options: .regularExpression))])
    }

    /// A deck of one rounded rectangle saved with `avLst` in place of its empty one.
    private func roundRectFile(avLst: String) throws -> Data {
        let deck = DeckController()
        let s = deck.addShape(ShapePreset(rawValue: "roundRect")); s.frame = Rect.fromLTWH(100, 100, 200, 100)
        var package = PptxPackage(try Zip.read(try Pptx.write(deck)))
        let part = try XCTUnwrap(package.parts.keys.first { $0.hasPrefix("ppt/slides/slide") && !$0.contains("_rels") })
        var xml = String(data: package.parts[part]!, encoding: .utf8)!
        let r = try XCTUnwrap(xml.range(of: "<a:prstGeom prst=\"roundRect\"><a:avLst/></a:prstGeom>"))
        xml.replaceSubrange(r, with: "<a:prstGeom prst=\"roundRect\">\(avLst)</a:prstGeom>")
        package.parts[part] = Data(xml.utf8)
        return try Zip.write(package.parts.keys.sorted().map { ZipEntry(name: $0, data: package.parts[$0]!) })
    }

    private func open(_ data: Data) throws -> DeckController {
        let (state, theme, pkg) = try Pptx.read(data)
        let d = DeckController(); d.load(state, theme: theme, package: pkg)
        return d
    }

    func testAFileShapesAdjustValuesAreReadAndAChangeIsSavedIntoItsOwnXML() throws {
        let data = try roundRectFile(avLst: "<a:avLst><a:gd name=\"adj\" fmla=\"val 30000\"/></a:avLst>")
        let d = try open(data)
        let s = try XCTUnwrap(d.slides[0].shapes.first { $0.preset?.rawValue == "roundRect" })
        XCTAssertEqual(s.adjusts, ["adj": 30000])
        // An edit elsewhere keeps the value.
        d.selectShapes([s]); d.nudgeSelection(dx: 5, dy: 0)
        XCTAssertEqual(try open(try Pptx.write(d)).slides[0].shapes.first { $0.preset?.rawValue == "roundRect" }?.adjusts, ["adj": 30000])
        // A new value is written into the shape's own XML, and only there: no text margins appear.
        let before = try sp(try slideXML(data))
        d.setAdjusts(s, ["adj": 45000])
        let saved = try Pptx.write(d)
        let after = try sp(try slideXML(saved))
        XCTAssertTrue(after.contains("val 45000"), after)
        func bodyPr(_ x: String) throws -> [String] {   // its attributes, in any order
            let tag = String(x[try XCTUnwrap(x.range(of: "<a:bodyPr[^>]*>", options: .regularExpression))])
            return tag.dropFirst(9).split(separator: " ").map { String($0).replacingOccurrences(of: ">", with: "") }.sorted()
        }
        XCTAssertEqual(try bodyPr(after), try bodyPr(before))
        let again = try open(saved)
        XCTAssertEqual(again.slides[0].shapes.first { $0.preset?.rawValue == "roundRect" }?.adjusts, ["adj": 45000])
    }

    func testARewrittenShapeKeepsItsTextMarginsAcrossSaves() throws {
        // A fill change writes the shape again from the model: its margins must be the text frame's own, not those
        // plus the rounded rectangle's text rectangle, or the text creeps inward at every save.
        var data = try roundRectFile(avLst: "<a:avLst><a:gd name=\"adj\" fmla=\"val 30000\"/></a:avLst>")
        let first = try XCTUnwrap(try open(data).slides[0].shapes.first { $0.preset?.rawValue == "roundRect" }?.insets)
        for color in [Color(0xFF112233), Color(0xFF445566)] {
            let d = try open(data)
            let s = try XCTUnwrap(d.slides[0].shapes.first { $0.preset?.rawValue == "roundRect" })
            d.selectShapes([s]); d.setFill(color)
            data = try Pptx.write(d)
        }
        let last = try XCTUnwrap(try open(data).slides[0].shapes.first { $0.preset?.rawValue == "roundRect" }?.insets)
        XCTAssertEqual(last.left, first.left, accuracy: 0.01)
        XCTAssertEqual(last.top, first.top, accuracy: 0.01)
    }

    func testANewShapesAdjustValuesAreSaved() throws {
        let deck = DeckController()
        let s = deck.addShape(ShapePreset(rawValue: "rightArrow")); s.frame = Rect.fromLTWH(100, 100, 200, 100)
        deck.setAdjusts(s, ["adj1": 60000, "adj2": 25000])
        let again = try open(try Pptx.write(deck))
        XCTAssertEqual(again.slides[0].shapes.first { $0.preset?.rawValue == "rightArrow" }?.adjusts, ["adj1": 60000, "adj2": 25000])
    }

    func testDraggingTheCornerHandleSetsTheRadiusAndUndoesInOneStep() throws {
        let deck = DeckController()
        let s = deck.addShape(ShapePreset(rawValue: "roundRect")); s.frame = Rect.fromLTWH(100, 100, 200, 100)
        // The default corner is 16667 of the short side (100 pt): the handle sits 16.67 pt in along the top.
        let h = try XCTUnwrap(s.adjustHandles.first)
        XCTAssertEqual(h.at.dx, 116.667, accuracy: 0.01)
        XCTAssertEqual(h.at.dy, 100, accuracy: 0.01)
        deck.beginFrameEdit()
        deck.setAdjustHandleLive(s, 0, to: Offset(125, 140))   // up and down does nothing: it runs along the top
        deck.setAdjustHandleLive(s, 0, to: Offset(130, 140))
        deck.endFrameEdit()
        XCTAssertEqual(s.adjusts["adj"], 30000)
        XCTAssertEqual(try XCTUnwrap(s.adjustHandles.first).at.dx, 130, accuracy: 0.01)
        // Past the middle it stops at its limit (half the short side).
        deck.beginFrameEdit(); deck.setAdjustHandleLive(s, 0, to: Offset(290, 100)); deck.endFrameEdit()
        XCTAssertEqual(s.adjusts["adj"], 50000)
        deck.undo()
        XCTAssertEqual(s.adjusts["adj"], 30000)
        deck.undo()
        XCTAssertEqual(s.adjusts["adj"], nil)
    }

    func testATurnedMirroredShapesHandleFollowsThePointer() throws {
        let deck = DeckController()
        let s = deck.addShape(ShapePreset(rawValue: "rightArrow")); s.frame = Rect.fromLTWH(100, 100, 200, 100)
        s.rotation = 90; s.flipH = true
        // The head handle (adj2) dragged to where the handle at 40000 would sit comes back to 40000.
        let target = s.toSlide(localX: 200 - 100 * 0.4, localY: 0)
        deck.beginFrameEdit(); deck.setAdjustHandleLive(s, 1, to: target); deck.endFrameEdit()
        XCTAssertEqual(try XCTUnwrap(s.adjusts["adj2"]), 40000, accuracy: 1)
    }

    func testAPieHandleGoesToThePointersAngle() throws {
        let deck = DeckController()
        let s = deck.addShape(ShapePreset(rawValue: "pie")); s.frame = Rect.fromLTWH(100, 100, 200, 200)
        // Straight down from the middle is 90°: 5400000 in 60000ths.
        deck.beginFrameEdit(); deck.setAdjustHandleLive(s, 0, to: Offset(200, 290)); deck.endFrameEdit()
        XCTAssertEqual(try XCTUnwrap(s.adjusts["adj1"]), 5_400_000, accuracy: 60_000)
    }

    /// On the canvas: a mouse drag on the selected rounded rectangle's yellow handle changes its corner, in one undo.
    func testDraggingTheYellowHandleOnTheCanvas() throws {
        let deck = DeckController()
        let s = deck.addShape(ShapePreset(rawValue: "roundRect")); s.frame = Rect.fromLTWH(100, 100, 200, 100)
        deck.selectShapes([s])
        let canvas = SlideCanvas(deck: deck, cache: SlideTextCache(), active: nil, onEdit: { _ in },
                                 onShortcut: { _, _ in false }, modifiers: { [] }, spellChecker: nil)
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: canvas, title: "Test"))
        for _ in 0 ..< 3 { ui.pump(); for cb in FrameCallbackScheduler.shared.takePostFrameCallbacks() { cb(.zero) } }
        ui.pump()
        let state = try XCTUnwrap(ui.state(SlideCanvasState.self))
        let h = try XCTUnwrap(s.adjustHandles.first)
        ui.drag(from: state.screenPoint(h.at), to: state.screenPoint(Offset(130, 100)), steps: 6, kind: .mouse)
        XCTAssertEqual(try XCTUnwrap(s.adjusts["adj"]), 30000, accuracy: 200)
        XCTAssertEqual(s.frame, Rect.fromLTWH(100, 100, 200, 100), "the shape itself did not move")
        deck.undo()
        XCTAssertNil(s.adjusts["adj"])
    }

    /// The check deck for PowerPoint: presets with changed handles (written only where /data/s/amd-6/ui-check exists).
    func testWritesThePowerPointCheckFile() throws {
        let deck = DeckController()
        for (i, (name, adj)) in [("roundRect", ["adj": 40000.0]), ("rightArrow", ["adj1": 70000.0, "adj2": 80000.0]),
                                 ("pie", ["adj1": 5_400_000.0, "adj2": 16_200_000.0]), ("star5", ["adj": 10000.0, "hf": 105146.0, "vf": 110557.0]),
                                 ("wedgeRectCallout", ["adj1": -40000.0, "adj2": 90000.0]), ("can", ["adj": 50000.0])].enumerated() {
            let s = deck.addShape(ShapePreset(rawValue: name))
            s.frame = Rect.fromLTWH(60 + Double(i % 3) * 280, 80 + Double(i / 3) * 220, 200, 130)
            deck.setAdjusts(s, adj)
        }
        let dir = "/data/s/amd-6/ui-check"
        guard FileManager.default.fileExists(atPath: dir) else { return }
        try Pptx.write(deck).write(to: URL(fileURLWithPath: dir + "/adjust-handles.pptx"))
    }

    func testEveryPresetsHandlesSitWhereTheyAreAndStayWhenDroppedThere() {
        var checked = 0
        for name in PresetHandleTable.rows.keys.sorted() where PresetGeometry.has(name) {
            let w = 1_270_000.0, h = 762_000.0
            let places = PresetHandles.positions(name, width: w, height: h, adjusts: [:])
            XCTAssertEqual(places.count, PresetHandles.handles(name).count, name)
            for (i, p) in places.enumerated() {
                guard let p else { XCTFail("\(name) handle \(i) has no place"); continue }
                let a = PresetHandles.drag(name, handle: i, to: p, width: w, height: h, adjusts: [:])
                let q = PresetHandles.positions(name, width: w, height: h, adjusts: a)[i]
                XCTAssertEqual(q?.dx ?? .nan, p.dx, accuracy: 2000, "\(name) handle \(i)")
                XCTAssertEqual(q?.dy ?? .nan, p.dy, accuracy: 2000, "\(name) handle \(i)")
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 200)
    }
}
