import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// Elbow and curved connectors: routed between glued shapes, saved with their adjust values.
final class SlideElbowTests: XCTestCase {
    private func near(_ a: Offset, _ b: Offset, _ msg: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.dx, b.dx, accuracy: 1.01, msg, file: file, line: line)
        XCTAssertEqual(a.dy, b.dy, accuracy: 1.01, msg, file: file, line: line)
    }

    private func elbow(_ deck: DeckController, _ name: String = "bentConnector3") -> SlideShape {
        deck.addShape(ShapePreset(rawValue: name))
    }

    private func boxes(_ deck: DeckController, _ bx: Rect, _ ax: Rect = Rect.fromLTWH(60, 100, 100, 60)) -> (SlideShape, SlideShape) {
        let a = deck.addShape(.rect); a.frame = ax
        let b = deck.addShape(.rect); b.frame = bx
        return (a, b)
    }

    func testRightSideToLeftSideIsAnSShape() {
        let r = ElbowRoute.make(from: Offset(160, 130), to: Offset(400, 330), leaving: (1, 0), arriving: (1, 0), curved: false)
        XCTAssertEqual(r.preset, "bentConnector3"); XCTAssertEqual(r.rotation, 0); XCTAssertFalse(r.flipV)
        XCTAssertEqual(r.adjusts["adj1"], 50000)
    }

    func testEveryRouteEndsExactlyOnItsTwoPoints() {
        let dirs: [(Double, Double)] = [(1, 0), (-1, 0), (0, 1), (0, -1)]
        let targets = [Offset(400, 330), Offset(40, 330), Offset(400, -80), Offset(60, 300), Offset(300, 100)]
        let s = Offset(160, 130)
        var variants = Set<String>()
        for t in targets { for a in dirs { for b in dirs {
            let r = ElbowRoute.make(from: s, to: t, leaving: a, arriving: b, curved: false)
            let sh = SlideShape(id: 1, name: "x", kind: .geometry(ShapePreset(rawValue: r.preset)), frame: r.frame, text: nil, textTheme: nil)
            sh.apply(r)
            near(sh.lineStart, s, "start \(a) \(b) to \(t)"); near(sh.lineEndPoint, t, "end \(a) \(b) to \(t)")
            XCTAssertNotNil(sh.customPath)
            variants.insert(r.preset)
        } } }
        XCTAssertEqual(variants, ["bentConnector2", "bentConnector3", "bentConnector4", "bentConnector5"])
    }

    func testAnEndFacingTheSameSideMakesAUShape() {
        // Right of A to right of B, straight below: the path stands off to the right and comes back.
        let r = ElbowRoute.make(from: Offset(160, 130), to: Offset(160, 330), leaving: (1, 0), arriving: (-1, 0), curved: false)
        XCTAssertEqual(r.preset, "bentConnector3")
        XCTAssertGreaterThan(r.adjusts["adj1"] ?? 0, 100000)
    }

    func testCurvedMakesTheCurvedVariants() {
        let r = ElbowRoute.make(from: Offset(160, 130), to: Offset(400, 330), leaving: (1, 0), arriving: (0, 1), curved: true)
        XCTAssertEqual(r.preset, "curvedConnector2")
    }

    func testGluedElbowFollowsAMovedShapeAndKeepsLeavingTheSide() {
        let deck = DeckController()
        let (a, b) = boxes(deck, Rect.fromLTWH(400, 260, 100, 60))
        let l = elbow(deck)
        deck.connect(l, start: true, to: a, site: 3); deck.connect(l, start: false, to: b, site: 1)
        near(l.lineStart, Offset(160, 130)); near(l.lineEndPoint, Offset(400, 290))
        deck.selectShapes([b]); deck.nudgeSelection(dx: 0, dy: -150)
        near(l.lineEndPoint, Offset(400, 140))
        XCTAssertEqual(l.preset?.rawValue, "bentConnector3")
        // B swung round behind A: the path turns back round it.
        deck.nudgeSelection(dx: -420, dy: 0)
        near(l.lineEndPoint, Offset(-20, 140))
        XCTAssertEqual(l.preset?.rawValue, "bentConnector5")
        // Undo may swap in a new object when the shape type changes: look the line up again.
        func line() -> SlideShape { deck.slides[deck.current].shapes.first { $0.id == l.id }! }
        deck.undo()
        XCTAssertEqual(line().preset?.rawValue, "bentConnector3")
        near(line().lineEndPoint, Offset(400, 140))
        deck.undo()
        near(line().lineEndPoint, Offset(400, 290))
        XCTAssertEqual(line().preset?.rawValue, "bentConnector3")
    }

    /// PowerPoint draws a file's stored route as it is until a glued shape moves: an end 10 pt off its site opens and saves untouched.
    func testAnEndOffItsSiteOpensAndSavesUnchangedUntilAShapeMoves() throws {
        let deck = DeckController()
        let (a, b) = boxes(deck, Rect.fromLTWH(400, 260, 100, 60))
        let l = elbow(deck)
        deck.connect(l, start: true, to: a, site: 3); deck.connect(l, start: false, to: b, site: 1)
        var package = PptxPackage(try Zip.read(try Pptx.write(deck)))
        let part = try XCTUnwrap(package.parts.keys.first { $0.hasPrefix("ppt/slides/slide") && !$0.contains("_rels") })
        var xml = String(data: package.parts[part]!, encoding: .utf8)!
        let cx = try XCTUnwrap(xml.range(of: "<p:cxnSp>.*?</p:cxnSp>", options: .regularExpression))
        let off = try XCTUnwrap(xml.range(of: "<a:off x=\"[0-9]+\"", options: .regularExpression, range: cx))
        let x = Int(xml[off].dropFirst(12).dropLast())!
        xml.replaceSubrange(off, with: "<a:off x=\"\(x + 127000)\"")   // 10 pt to the right
        package.parts[part] = Data(xml.utf8)
        let data = try Zip.write(package.parts.keys.sorted().map { ZipEntry(name: $0, data: package.parts[$0]!) })
        func connector(_ d: Data) throws -> String {
            let p = PptxPackage(try Zip.read(d))
            let part = try XCTUnwrap(p.parts.keys.first { $0.hasPrefix("ppt/slides/slide") && !$0.contains("_rels") })
            let x = String(data: p.parts[part]!, encoding: .utf8)!
            let c = String(x[try XCTUnwrap(x.range(of: "<p:cxnSp>.*?</p:cxnSp>", options: .regularExpression))])
            // The geometry as stored: the frame, turn, flips and adjust values (attribute order and tag style may differ).
            let g = try XCTUnwrap(c.range(of: "<a:xfrm.*?</a:prstGeom>", options: .regularExpression))
            return String(c[g]).replacingOccurrences(of: "name=\"adj1\" fmla=\"val 50000\"", with: "fmla=\"val 50000\" name=\"adj1\"")
        }
        let before = try connector(data)
        let (state, theme, pkg) = try Pptx.read(data)
        let d2 = DeckController(); d2.load(state, theme: theme, package: pkg)
        d2.nudgeSelection(dx: 0, dy: 0)   // any later edit also leaves it be
        XCTAssertEqual(try connector(try Pptx.write(d2)), before)
        // Moving a glued shape does route it.
        let b2 = try XCTUnwrap(d2.slides[0].shapes.first { $0.name == b.name })
        d2.selectShapes([b2]); d2.nudgeSelection(dx: 0, dy: 20)
        XCTAssertNotEqual(try connector(try Pptx.write(d2)), before)
    }

    func testBottomToTopTurnsTheBox() {
        let deck = DeckController()
        let (a, b) = boxes(deck, Rect.fromLTWH(300, 300, 100, 60))
        let l = elbow(deck)
        deck.connect(l, start: true, to: a, site: 2); deck.connect(l, start: false, to: b, site: 0)
        XCTAssertEqual(l.rotation, 90)
        near(l.lineStart, Offset(110, 160)); near(l.lineEndPoint, Offset(350, 300))
    }

    func testDraggingTheEndOntoASiteGluesIt() {
        let deck = DeckController()
        let (a, b) = boxes(deck, Rect.fromLTWH(400, 260, 100, 60))
        let l = elbow(deck)
        deck.selectShapes([l])
        deck.dragElbowEnd(l, handle: 0, to: Offset(161, 131), snap: true)
        XCTAssertEqual(l.connStart, ShapeConn(shape: a.id, site: 3))
        deck.dragElbowEnd(l, handle: 1, to: Offset(399, 291), snap: true)
        XCTAssertEqual(l.connEnd, ShapeConn(shape: b.id, site: 1))
        deck.dragElbowEnd(l, handle: 1, to: Offset(600, 500), snap: true)
        XCTAssertNil(l.connEnd); near(l.lineEndPoint, Offset(600, 500))
    }

    func testRerouteTakesTheNearestSitesForElbows() {
        let deck = DeckController()
        let (a, b) = boxes(deck, Rect.fromLTWH(400, 200, 100, 60))
        let l = elbow(deck)
        deck.connect(l, start: true, to: a, site: 0); deck.connect(l, start: false, to: b, site: 2)
        deck.selectShapes([l]); deck.rerouteConnectors()
        XCTAssertEqual(l.connStart, ShapeConn(shape: a.id, site: 3)); XCTAssertEqual(l.connEnd, ShapeConn(shape: b.id, site: 1))
        near(l.lineStart, Offset(160, 130)); near(l.lineEndPoint, Offset(400, 230))
    }

    func testPlacingByDragMakesAnElbowBetweenThePoints() {
        let deck = DeckController()
        let l = deck.placeInsert(ShapePreset(rawValue: "curvedConnector3"), from: Offset(100, 100), to: Offset(300, 220), keepProportions: false)
        XCTAssertEqual(l.preset?.rawValue, "curvedConnector3"); XCTAssertNil(l.text)
        near(l.lineStart, Offset(100, 100)); near(l.lineEndPoint, Offset(300, 220))
    }

    func testAdjustValuesTurnAndGlueSurviveSaving() throws {
        let deck = DeckController()
        let (a, b) = boxes(deck, Rect.fromLTWH(60, 300, 100, 60))
        let l = elbow(deck)
        deck.connect(l, start: true, to: a, site: 3); deck.connect(l, start: false, to: b, site: 3)   // U shape
        let adj = try XCTUnwrap(l.adjusts["adj1"])
        XCTAssertGreaterThan(adj, 100000)
        let (state, theme, pkg) = try Pptx.read(Pptx.write(deck))
        let again = DeckController(); again.load(state, theme: theme, package: pkg)
        let r = try XCTUnwrap(again.currentSlide.shapes.last(where: { $0.preset?.isElbow == true }))
        XCTAssertEqual(r.preset?.rawValue, "bentConnector3")
        XCTAssertEqual(r.adjusts["adj1"] ?? 0, adj, accuracy: 1)
        XCTAssertNotNil(r.connStart); XCTAssertNotNil(r.connEnd)
        near(r.lineStart, l.lineStart); near(r.lineEndPoint, l.lineEndPoint)
        // A read connector that is not touched is written back as it was; one that is turned keeps its adjusts.
        let (s2, t2, p2) = try Pptx.read(Pptx.write(again))
        let third = DeckController(); third.load(s2, theme: t2, package: p2)
        XCTAssertEqual(third.currentSlide.shapes.last(where: { $0.preset?.isElbow == true })?.adjusts["adj1"] ?? 0, adj, accuracy: 1)
    }

    func testWritesThePowerPointCheckFile() throws {
        let dir = "/data/s/amd-6/ui-check"
        guard FileManager.default.fileExists(atPath: dir) else { return }
        let deck = DeckController()
        // Two slides' worth in one: left column of boxes, right column of targets, one connector per site pairing.
        func pair(_ y: Double, _ ax: Rect, _ bx: Rect, _ sa: Int, _ sb: Int, curved: Bool, arrow: Bool = true) {
            let a = deck.addShape(.roundRect); a.frame = ax.shift(Offset(0, y))
            let b = deck.addShape(.ellipse); b.frame = bx.shift(Offset(0, y))
            let l = elbow(deck, curved ? "curvedConnector3" : "bentConnector3")
            deck.selectShapes([l]); deck.setOutlineWidth(2); if arrow { deck.setLineEnd(start: false, kind: "triangle") }
            deck.connect(l, start: true, to: a, site: sa); deck.connect(l, start: false, to: b, site: sb)
        }
        let a = Rect.fromLTWH(30, 20, 90, 40), b = Rect.fromLTWH(300, 20, 90, 60)
        pair(0, a, b.shift(Offset(0, 40)), 3, 2, curved: false)    // right of A to bottom of B (a corner)
        pair(0, a.shift(Offset(480, 0)), b.shift(Offset(150, 150)), 2, 0, curved: false)   // down then across, turned
        pair(150, a, b, 3, 1, curved: false)                       // S shape
        pair(150, a.shift(Offset(450, 0)), b.shift(Offset(60, 30)), 3, 3, curved: true)    // round the back
        pair(300, a, b, 2, 0, curved: true)
        pair(300, a.shift(Offset(450, 0)), b.shift(Offset(-30, 80)), 1, 2, curved: false)
        // The ellipse in the first pair moves: the elbow follows it.
        deck.selectShapes([deck.currentSlide.shapes[3]]); deck.nudgeSelection(dx: 20, dy: 10)
        try Pptx.write(deck).write(to: URL(fileURLWithPath: dir + "/elbows.pptx"))
    }

    func testMiddleRunHandleSitsOnTheRunAndDragsIt() {
        let deck = DeckController()
        let l = elbow(deck)
        let r = ElbowRoute.make(from: Offset(100, 100), to: Offset(300, 200), leaving: (1, 0), arriving: (1, 0), curved: false)
        l.apply(r)
        let hs = l.elbowAdjustHandles
        XCTAssertEqual(hs.count, 1)
        near(hs[0].at, Offset(200, 150), "the middle of the vertical run")
        deck.beginFrameEdit()
        deck.setElbowRunLive(l, "adj1", alongWidth: true, to: Offset(150, 170))
        XCTAssertEqual(l.adjusts["adj1"] ?? 0, 25000, accuracy: 1)
        near(l.elbowAdjustHandles[0].at, Offset(150, 150))
        deck.endFrameEdit()
        // Turned and mirrored: the same drag still lands on the run.
        let m = elbow(deck)
        m.apply(ElbowRoute.make(from: Offset(300, 400), to: Offset(100, 300), leaving: (-1, 0), arriving: (-1, 0), curved: false))
        near(m.elbowAdjustHandles[0].at, Offset(200, 350))
        deck.setElbowRunLive(m, "adj1", alongWidth: true, to: Offset(250, 330))
        near(m.elbowAdjustHandles[0].at, Offset(250, 350))
    }
}
