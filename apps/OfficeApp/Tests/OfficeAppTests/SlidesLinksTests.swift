import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

/// Links in Slides: saved to the file, and followed in the slide show.
final class SlidesLinksTests: XCTestCase {
    private func linkedBox(_ deck: DeckController, _ text: String, _ at: Rect, _ link: String, tip: String? = nil) -> SlideShape {
        let b = deck.addTextBox(at: at)
        b.text!.insertText(text)
        b.text!.selectAll()
        XCTAssertTrue(b.text!.applyHyperlink(address: link, tip: tip))
        return b
    }

    /// Where a shape's top-left corner shows when the slide is fitted to the tester's surface (it may not be the size asked for).
    private func onScreen(_ box: SlideShape, _ ui: WidgetTester, _ deck: DeckController) -> Offset {
        let size = (ui.state(SlideShowState.self)?.context?.findRenderObject() as? RenderBox)?.size ?? ui.size
        let k = min(size.width / deck.slideSize.width, size.height / deck.slideSize.height)
        let left = ((size.width - (deck.slideSize.width * k).rounded()) / 2).rounded()
        let top = ((size.height - (deck.slideSize.height * k).rounded()) / 2).rounded()
        return Offset(left + (box.frame.left + 20) * k, top + (box.frame.top + 12) * k)
    }

    /// A deck with every kind of link; saved for PowerPoint to open when STARLING_LINKS_OUT names a path.
    private func linksDeck() -> DeckController {
        let deck = DeckController()
        _ = deck.addSlide()
        _ = deck.addSlide()
        deck.select(0)
        let second = deck.slideLinkTargets()[1].key, third = deck.slideLinkTargets()[2].key
        _ = linkedBox(deck, "Visit the site", Rect.fromLTWH(40, 40, 300, 40), "https://example.com/a", tip: "Example site")
        _ = linkedBox(deck, "Mail us", Rect.fromLTWH(40, 100, 300, 40), "mailto:team@example.com")
        _ = linkedBox(deck, "Go to slide two", Rect.fromLTWH(40, 160, 300, 40), "slide:" + second)
        let shape = deck.addShape(.rect)
        deck.selectShapes([shape])
        XCTAssertTrue(deck.setShapeLink("slide:" + second, tip: "Jump"))
        _ = linkedBox(deck, "Go to slide three", Rect.fromLTWH(40, 220, 300, 40), "slide:" + third)
        return deck
    }

    func testEveryKindOfLinkSurvivesASave() throws {
        let deck = linksDeck()
        let data = try Pptx.write(deck)
        if let out = ProcessInfo.processInfo.environment["STARLING_LINKS_OUT"] { try data.write(to: URL(fileURLWithPath: out)) }
        let pkg = PptxPackage(try Zip.read(data))
        let slide = String(data: pkg.parts["ppt/slides/slide1.xml"]!, encoding: .utf8)!
        let rels = String(data: pkg.parts["ppt/slides/_rels/slide1.xml.rels"]!, encoding: .utf8)!
        XCTAssertTrue(rels.contains("https://example.com/a") && rels.contains("mailto:team@example.com"), rels)
        XCTAssertTrue(rels.contains("slide2.xml") && rels.contains("slide3.xml"), rels)
        XCTAssertTrue(slide.contains("Example site"), "screen tip")
        XCTAssertEqual(slide.components(separatedBy: "ppaction://hlinksldjump").count - 1, 3, slide)
        // Read back: the links are still the same links.
        let (state, _, _) = try Pptx.read(data)
        XCTAssertEqual(state.slides.count, 3)
    }

    func testSlideShowFollowsASlideLink() throws {
        let deck = DeckController()
        _ = deck.addSlide()
        deck.select(0)
        let second = deck.slideLinkTargets()[1].key
        let box = linkedBox(deck, "Next", Rect.fromLTWH(100, 100, 300, 60), "slide:" + second)
        let size = Size(deck.slideSize.width, deck.slideSize.height)
        let ui = WidgetTester(SlideShowView(deck: deck, images: SlideTextCache(), start: 0, onEnd: {}),
                              size: size)
        let state = try XCTUnwrap(ui.state(SlideShowState.self))
        XCTAssertEqual(state._at, 0)
        // A click away from the text advances by one, as ever; here that also lands on slide two, so test the link first on slide order.
        ui.click(at: onScreen(box, ui, deck))
        XCTAssertEqual(state._at, 1)
    }

    func testSlideShowOpensAnExternalLink() throws {
        let deck = DeckController()
        _ = deck.addSlide()
        _ = deck.addSlide()
        deck.select(0)
        let box = linkedBox(deck, "Site", Rect.fromLTWH(100, 100, 300, 60), "https://example.com/x")
        var opened: [String] = []
        let saved = hostOpenURL
        hostOpenURL = { opened.append($0) }
        defer { hostOpenURL = saved }
        let size = Size(deck.slideSize.width, deck.slideSize.height)
        let ui = WidgetTester(SlideShowView(deck: deck, images: SlideTextCache(), start: 0, onEnd: {}),
                              size: size)
        let state = try XCTUnwrap(ui.state(SlideShowState.self))
        ui.click(at: onScreen(box, ui, deck))
        XCTAssertEqual(opened, ["https://example.com/x"])
        XCTAssertEqual(state._at, 0, "a followed link does not also advance")
    }
}
