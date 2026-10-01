import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

final class DeckControllerTests: XCTestCase {
    private func type(_ text: String, into shape: SlideShape?) {
        shape?.text?.insertText(text)
    }

    func testNewDeckIsOneTitleSlideAtWidescreen() {
        let deck = DeckController()
        XCTAssertEqual(deck.slides.count, 1)
        XCTAssertEqual(deck.currentSlide.layout, .titleSlide)
        XCTAssertEqual(deck.slideSize, Size(960, 540))
        XCTAssertEqual(deck.currentSlide.shapes.map(\.role), [.ctrTitle, .subTitle])
    }

    func testNewSlideFollowsPowerPointsChoiceOfLayout() {
        let deck = DeckController()
        deck.addSlide()
        XCTAssertEqual(deck.currentSlide.layout, .titleAndContent, "after a title slide")
        deck.applyLayout(.twoContent, to: deck.current)
        deck.addSlide()
        XCTAssertEqual(deck.currentSlide.layout, .twoContent, "otherwise the current layout repeats")
        XCTAssertEqual(deck.current, 2)
    }

    func testApplyLayoutCarriesTextByRole() {
        let deck = DeckController()
        deck.addSlide(.titleAndContent)
        let slide = deck.currentSlide
        type("Agenda", into: slide.shapes.first { $0.role == .title })
        type("First point", into: slide.shapes.first { $0.role == .body })
        deck.applyLayout(.twoContent, to: deck.current)
        XCTAssertEqual(slide.titleText, "Agenda")
        let bodies = slide.shapes.filter { $0.role == .body }
        XCTAssertEqual(bodies.count, 2)
        XCTAssertEqual(bodies[0].text?.document.plainText(), "First point")
        XCTAssertTrue(bodies[1].isEmptyText)
        // To Title Only: the body has no slot, so it stays as it was.
        deck.applyLayout(.titleOnly, to: deck.current)
        XCTAssertEqual(slide.titleText, "Agenda")
        XCTAssertTrue(slide.shapes.contains { $0.text?.document.plainText() == "First point" })
        XCTAssertEqual(slide.shapes.filter { $0.isEmptyText }.count, 0, "empty leftovers are dropped")
    }

    func testDuplicateIsDeepAndDeleteKeepsOneSlide() {
        let deck = DeckController()
        type("Original", into: deck.currentSlide.shapes.first)
        deck.duplicateSlide(0)
        XCTAssertEqual(deck.slides.count, 2)
        XCTAssertEqual(deck.current, 1)
        type(" changed", into: deck.currentSlide.shapes.first)
        XCTAssertEqual(deck.slides[0].titleText, "Original", "the copy has its own text")
        deck.deleteSlide(1)
        deck.deleteSlide(0)
        XCTAssertEqual(deck.slides.count, 1, "the last slide cannot be deleted")
    }

    func testMoveAndHide() {
        let deck = DeckController()
        let first = deck.currentSlide
        deck.addSlide()
        deck.addSlide()
        deck.moveSlide(0, to: 2)
        XCTAssertTrue(deck.slides[2] === first)
        XCTAssertEqual(deck.current, 2)
        deck.toggleHidden(2)
        XCTAssertTrue(first.hidden)
    }

    func testSlideSizeScalesShapes() {
        let deck = DeckController()
        let title = deck.currentSlide.shapes[0]
        let before = title.frame
        deck.setSlideSize(Size(720, 540))
        XCTAssertEqual(title.frame.left, before.left * 0.75, accuracy: 0.001)
        XCTAssertEqual(title.frame.width, before.width * 0.75, accuracy: 0.001)
        XCTAssertEqual(title.frame.top, before.top, accuracy: 0.001)
        deck.addSlide()
        let body = deck.currentSlide.shapes.first { $0.role == .body }!
        XCTAssertLessThanOrEqual(body.frame.right, 720, "new slides are laid out for the new size")
    }

    func testTypingMovesTheRevisionAndCaretMovesDoNot() {
        let deck = DeckController()
        let title = deck.currentSlide.shapes[0].text!
        title.insertText("Hello")
        let r = deck.revision
        title.moveTo(.start, extend: false)
        XCTAssertEqual(deck.revision, r, "a caret move is not an edit")
        title.insertText("x")
        XCTAssertGreaterThan(deck.revision, r)
    }

    func testAnchoredTextSitsAtTheBottomOfTheTitle() {
        _ = OfficeFonts.register()
        let deck = DeckController()
        let title = deck.currentSlide.shapes[0]
        title.text?.insertText("Quarterly review")
        let cache = SlideTextCache()
        let px = 1.0
        let top = cache.textTop(title, pxPerPt: px)
        let h = cache.layout(title, pxPerPt: px)!.totalHeight
        XCTAssertEqual(top + h, (title.frame.height - title.insets.bottom) * px, accuracy: 0.5)
    }
}

final class DeckUndoTests: XCTestCase {
    func testEveryEditUndoesAndRedoes() {
        let deck = DeckController()
        let start = deck.snapshot()
        deck.addSlide()
        let shape = deck.addShape(.ellipse)
        deck.setFill(Color(0xFFFF0000))
        XCTAssertEqual(shape.fill, Color(0xFFFF0000))
        deck.undo()
        XCTAssertEqual(deck.currentSlide.shapes.first { $0.id == shape.id }?.fill, deck.theme.accents[0])
        deck.undo()
        XCTAssertFalse(deck.currentSlide.shapes.contains { $0.preset == .ellipse })
        deck.undo()
        XCTAssertEqual(deck.snapshot(), start)
        XCTAssertFalse(deck.canUndo)
        deck.redo(); deck.redo(); deck.redo()
        XCTAssertEqual(deck.slides.count, 2)
        XCTAssertEqual(deck.currentSlide.shapes.last?.fill, Color(0xFFFF0000))
    }

    func testATextSessionIsOneStepAndKeepsItsEditor() {
        let deck = DeckController()
        let title = deck.currentSlide.shapes[0]
        let controller = title.text!
        deck.beginTextSession()
        controller.insertText("Hello")
        controller.insertText(" world")
        deck.endTextSession()
        XCTAssertTrue(deck.canUndo)
        deck.undo()
        XCTAssertEqual(deck.currentSlide.titleText, "")
        XCTAssertTrue(deck.currentSlide.shapes[0] === title, "restore keeps the shape object")
        XCTAssertTrue(title.text === controller, "and the controller its editor is bound to")
        deck.redo()
        XCTAssertEqual(deck.currentSlide.titleText, "Hello world")
    }

    func testAnEditDuringTypingSplitsTheSession() {
        let deck = DeckController()
        let title = deck.currentSlide.shapes[0].text!
        deck.beginTextSession()
        title.insertText("A")
        deck.nudgeSelection(dx: 1, dy: 0)       // no selection: nothing, no step
        deck.selectShapes([deck.currentSlide.shapes[1]])
        deck.nudgeSelection(dx: 5, dy: 0)       // a deck edit mid-session
        title.insertText("B")
        deck.endTextSession()
        deck.undo()
        XCTAssertEqual(deck.currentSlide.titleText, "A", "the typing after the nudge is its own step")
        deck.undo()
        XCTAssertEqual(deck.currentSlide.titleText, "A", "the nudge")
        deck.undo()
        XCTAssertEqual(deck.currentSlide.titleText, "", "the typing before it")
    }

    func testLiveFramesAreOneStep() {
        let deck = DeckController()
        let shape = deck.addShape(.rect)
        let before = shape.frame
        deck.beginFrameEdit()
        for i in 1 ... 10 { deck.setFramesLive([(shape, before.shift(Offset(Double(i), 0)))]) }
        deck.endFrameEdit()
        XCTAssertEqual(shape.frame.left, before.left + 10)
        deck.undo()
        XCTAssertEqual(deck.currentSlide.shapes.last?.frame, before)
    }

    func testArrangeAlignDuplicatePaste() {
        let deck = DeckController()
        let a = deck.addShape(.rect)
        let b = deck.addShape(.ellipse)
        deck.selectShapes([b])
        deck.arrange(.back)
        XCTAssertTrue(deck.currentSlide.shapes.first === b)
        deck.arrange(.forward)
        XCTAssertTrue(deck.currentSlide.shapes[1] === b)
        deck.selectShapes([a])
        deck.align(.left)
        XCTAssertEqual(a.frame.left, 0)
        deck.align(.bottom)
        XCTAssertEqual(a.frame.bottom, deck.slideSize.height)
        deck.duplicateSelection()
        XCTAssertEqual(deck.selection.count, 1)
        XCTAssertFalse(deck.selection[0] === a)
        XCTAssertEqual(deck.selection[0].frame.left, 18)
        let copied = deck.copySelection()
        deck.paste(copied)
        XCTAssertEqual(deck.selection[0].frame.left, 36)
        XCTAssertNotEqual(deck.selection[0].id, copied[0].id)
    }

    func testResizeKeepsTheOppositeCornerOfARotatedShape() {
        let frame = Rect.fromLTWH(100, 100, 200, 100)
        for rotation in [0.0, 30, 90, 200] {
            // Drag the bottom-right handle (4); top-left (0) must not move.
            let anchor = { (f: Rect) -> Offset in
                let v = SlideCanvasState.rotate(Offset(-f.width / 2, -f.height / 2), rotation)
                return Offset(f.center.dx + v.dx, f.center.dy + v.dy)
            }
            let r = SlideCanvasState.resizedFrame(frame, rotation: rotation, handle: 4,
                                                  delta: SlideCanvasState.rotate(Offset(40, 20), rotation))
            XCTAssertEqual(r.width, 240, accuracy: 1e-6)
            XCTAssertEqual(r.height, 120, accuracy: 1e-6)
            XCTAssertEqual(anchor(r).dx, anchor(frame).dx, accuracy: 1e-6)
            XCTAssertEqual(anchor(r).dy, anchor(frame).dy, accuracy: 1e-6)
        }
    }
}

final class ThemeTests: XCTestCase {
    func testApplyThemeRestylesAndUndoes() {
        let deck = SlidesSample.make()
        let slate = DeckTheme.presets.first { $0.name == "Slate" }!
        let title = deck.slides[0].shapes[0]
        let shape = deck.slides.flatMap(\.shapes).first { $0.preset == .roundRect }!
        let before = (title.textTheme!.textColor, shape.fill)
        deck.applyTheme(slate)
        XCTAssertEqual(title.textTheme?.textColor, slate.text)
        XCTAssertEqual(title.textTheme?.fontFamily, slate.headingFont)
        XCTAssertEqual(shape.fill, slate.accents[0], "theme-coloured shapes recolour")
        XCTAssertTrue(deck.ownTemplates)
        deck.undo()
        XCTAssertEqual(deck.theme.name, "Starling")
        XCTAssertEqual(title.textTheme?.textColor, before.0)
        XCTAssertEqual(shape.fill, before.1)
    }

    func testThemedDeckWritesOurMasterWithItsColours() throws {
        let deck = SlidesSample.make()
        deck.applyTheme(DeckTheme.presets.first { $0.name == "Ocean" }!)
        let package = PptxPackage(try Zip.read(try Pptx.write(deck)))
        let theme = String(data: package.parts["ppt/theme/theme1.xml"]!, encoding: .utf8)!
        XCTAssertTrue(theme.contains("name=\"Ocean\""))
        let master = String(data: package.parts["ppt/slideMasters/slideMaster1.xml"]!, encoding: .utf8)!
        XCTAssertTrue(master.contains("<a:gradFill"), "Ocean's gradient is the master background")
        let (state, _, _) = try Pptx.read(Pptx.write(deck))
        let shape = state.slides.flatMap(\.shapes).first { $0.kind == .geometry(.roundRect) }!
        XCTAssertEqual(shape.fillScheme, "accent1", "theme fills travel as theme references")
    }
}

final class PictureTests: XCTestCase {
    func testCropFitsInsideTheOldBoxAndResets() throws {
        let deck = SlidesSample.make()
        deck.select(deck.slides.firstIndex { $0.titleText == "A picture" }!)
        let pic = deck.currentSlide.shapes.first { $0.picture != nil }!
        let before = pic.frame
        deck.selectShapes([pic])
        deck.cropPictures(aspect: 1)
        XCTAssertEqual(pic.frame.width, pic.frame.height, accuracy: 0.001)
        XCTAssertLessThanOrEqual(pic.frame.width, before.width + 0.001)
        XCTAssertEqual(pic.frame.center.dx, before.center.dx, accuracy: 0.001)
        XCTAssertEqual(pic.crop!.left, 0.125, accuracy: 0.001, "a 4:3 picture loses an eighth each side")
        let (state, _, _) = try Pptx.read(Pptx.write(deck))
        let read = state.slides[deck.current].shapes.first { if case .picture = $0.kind { return true }; return false }!
        XCTAssertEqual(read.crop!.left, 0.125, accuracy: 0.001, "the crop travels as a:srcRect")
        deck.resetPictures()
        XCTAssertNil(pic.crop)
    }
}
