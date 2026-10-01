import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

final class AnimationTests: XCTestCase {
    func testPlanGroupsAndProgress() {
        let a = [
            ShapeAnimation(shapeId: 1, effect: .fade),
            ShapeAnimation(shapeId: 2, effect: .zoom, start: .withPrevious),
            ShapeAnimation(shapeId: 3, effect: .flyIn, start: .afterPrevious, duration: 1),
            ShapeAnimation(shapeId: 4, effect: .appear),
        ]
        let plan = AnimationPlan(a)
        XCTAssertFalse(plan.autoStart)
        XCTAssertEqual(plan.groups.count, 2)
        XCTAssertEqual(plan.groups[0].map(\.begin), [0, 0, 0.5], "after previous waits for the fade")
        XCTAssertEqual(plan.length(0), 1.5)
        XCTAssertEqual(AnimationPlan.clickNumbers(a), [1, 1, 1, 2])
        // Before the first click every animated shape is hidden.
        let before = plan.reveals(played: 0, elapsed: nil)
        XCTAssertEqual(Set(before.whole.keys), [1, 2, 3, 4])
        XCTAssertTrue(before.whole.values.allSatisfy { $0.progress == 0 })
        // A second into group 0: the fade done, the fly half way.
        let mid = plan.reveals(played: 0, elapsed: 1.0)
        XCTAssertEqual(mid.whole[1]?.progress, 1)
        XCTAssertEqual(mid.whole[3]?.progress ?? -1, 0.5, accuracy: 1e-9)
        XCTAssertEqual(mid.whole[4]?.progress, 0, "the next click's shape still waits")
        XCTAssertEqual(Set(plan.reveals(played: 1, elapsed: nil).whole.keys), [4])

        let auto = AnimationPlan([ShapeAnimation(shapeId: 1, effect: .fade, start: .afterPrevious)])
        XCTAssertTrue(auto.autoStart)
    }

    func testOurTimingReadsBack() throws {
        let animations = [
            ShapeAnimation(shapeId: 10, paragraph: 0, effect: .flyIn, direction: .left),
            ShapeAnimation(shapeId: 10, paragraph: 1, effect: .flyIn, direction: .left),
            ShapeAnimation(shapeId: 11, effect: .wipe, start: .withPrevious, direction: .top, duration: 1, delay: 0.25),
            ShapeAnimation(shapeId: 12, effect: .zoom, start: .afterPrevious),
            ShapeAnimation(shapeId: 13, effect: .appear),
            ShapeAnimation(shapeId: 14, effect: .fade, duration: 2),
        ]
        let xml = AnimationXML.write(animations, spid: { $0 + 100 }, textShapes: [10, 11])
        XCTAssertTrue(xml.contains("<p:bldP spid=\"110\" grpId=\"0\" build=\"p\"/>"))
        XCTAssertTrue(xml.contains("<p:bldP spid=\"111\" grpId=\"0\" animBg=\"1\"/>"))
        let read = try XCTUnwrap(AnimationXML.read(try XCTUnwrap(XNode.parse(Data(xml.utf8)))))
        XCTAssertEqual(read.map(\.spid), [110, 110, 111, 112, 113, 114])
        XCTAssertEqual(read.map { var a = $0.animation; a.shapeId = $0.spid - 100; return a }, animations)
    }

    func testDeckKeepsTheFilesTimingUntilEdited() throws {
        let deck = SlidesSample.make()
        var package = PptxPackage(try Zip.read(try Pptx.write(deck)))
        // Mark slide 6's timing: kept, the mark survives a save.
        var slide6 = String(data: package.parts["ppt/slides/slide6.xml"]!, encoding: .utf8)!
        slide6 = slide6.replacingOccurrences(of: "nodeType=\"tmRoot\"", with: "nodeType=\"tmRoot\" accel=\"0\"")
        package.parts["ppt/slides/slide6.xml"] = Data(slide6.utf8)
        var entries: [ZipEntry] = []
        for (k, v) in package.parts { entries.append(ZipEntry(name: k, data: v)) }
        var (state, theme, pkg) = try Pptx.read(try Zip.write(entries))
        XCTAssertEqual(state.slides[5].animations.map(\.effect), [.fade, .zoom])
        XCTAssertEqual(state.slides[1].animations.compactMap(\.paragraph), [0, 1, 2])

        func written(_ s: DeckState) throws -> String {
            let out = PptxPackage(try Zip.read(try PptxWriter.write(s, theme: theme, package: pkg)))
            return String(data: out.parts["ppt/slides/slide6.xml"]!, encoding: .utf8)!
        }
        XCTAssertTrue(try written(state).contains("accel=\"0\""), "unchanged: as read")
        state.slides[5].animations[0].duration = 1
        let edited = try written(state)
        XCTAssertFalse(edited.contains("accel=\"0\""), "edited: our own tree")
        XCTAssertTrue(edited.contains("dur=\"1000\""))
    }

    func testTimingThisAppDoesNotModelIsKeptAndLocked() throws {
        let deck = SlidesSample.make()
        var package = PptxPackage(try Zip.read(try Pptx.write(deck)))
        var slide6 = String(data: package.parts["ppt/slides/slide6.xml"]!, encoding: .utf8)!
        slide6 = slide6.replacingOccurrences(of: "presetClass=\"entr\"", with: "presetClass=\"exit\"")
        package.parts["ppt/slides/slide6.xml"] = Data(slide6.utf8)
        var entries: [ZipEntry] = []
        for (k, v) in package.parts { entries.append(ZipEntry(name: k, data: v)) }
        let (state, theme, pkg) = try Pptx.read(try Zip.write(entries))
        let opened = DeckController()
        opened.load(state, theme: theme, package: pkg)
        opened.select(5)
        XCTAssertTrue(opened.currentSlide.animationsKept)
        XCTAssertFalse(opened.canAnimate)
        opened.selectShapes([opened.currentSlide.shapes[1]])
        opened.setEntrance(.fade)
        XCTAssertTrue(opened.currentSlide.animations.isEmpty, "not editable here")
        let out = String(data: PptxPackage(try Zip.read(try Pptx.write(opened))).parts["ppt/slides/slide6.xml"]!, encoding: .utf8)!
        XCTAssertTrue(out.contains("presetClass=\"exit\""), "written back as read")
    }

    func testDeletingAndDuplicating() {
        let deck = SlidesSample.make()
        deck.select(5)
        let box = deck.currentSlide.shapes.first { $0.preset == .roundRect }!
        deck.duplicateSlide(5)
        let copy = deck.currentSlide
        XCTAssertEqual(copy.animations.count, 2)
        XCTAssertTrue(copy.animations.allSatisfy { a in copy.shapes.contains { $0.id == a.shapeId } }, "aimed at the copies")
        deck.select(5)
        deck.selectShapes([box])
        deck.deleteSelection()
        XCTAssertEqual(deck.currentSlide.animations.map(\.effect), [.zoom], "the box's fade went with it")
        deck.undo()
        XCTAssertEqual(deck.currentSlide.animations.map(\.effect), [.fade, .zoom])
    }

    func testByParagraphAndBack() {
        let deck = SlidesSample.make()
        deck.select(1)
        let body = deck.currentSlide.shapes.first { $0.role == .body }!
        deck.selectShapes([body])
        XCTAssertTrue(deck.selectionByParagraph)
        deck.setByParagraph(false)
        XCTAssertEqual(deck.currentSlide.animations.map(\.paragraph), [nil])
        deck.setEntrance(.wipe)
        deck.setByParagraph(true)
        XCTAssertEqual(deck.currentSlide.animations.map(\.paragraph), [0, 1, 2])
        XCTAssertEqual(Set(deck.currentSlide.animations.map(\.effect)), [.wipe])
    }
}
