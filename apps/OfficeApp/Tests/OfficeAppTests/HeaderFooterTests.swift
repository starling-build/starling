import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

final class HeaderFooterTests: XCTestCase {
    private func footer(_ slide: Slide, _ type: String) -> SlideShape? {
        slide.shapes.first { $0.phType == type }
    }

    func testApplyToAllSkipsTitleSlidesAndNumbersFollowOrder() {
        let deck = SlidesSample.make()
        var hf = DeckController.HeaderFooter()
        hf.slideNumber = true
        hf.date = true
        hf.footer = "Q4"
        hf.skipTitleSlides = true
        deck.applyHeaderFooter(hf, toAll: true)
        XCTAssertNil(footer(deck.slides[0], "sldNum"), "the title slide is skipped")
        XCTAssertEqual(footer(deck.slides[1], "sldNum")?.text?.document.plainText(), "2")
        XCTAssertEqual(footer(deck.slides[1], "ftr")?.text?.document.plainText(), "Q4")
        XCTAssertEqual(footer(deck.slides[1], "dt")?.field?.type, "datetime1")
        // Moving the slide renumbers it.
        let moved = deck.slides[1]
        deck.moveSlide(1, to: 3)
        XCTAssertEqual(footer(moved, "sldNum")?.text?.document.plainText(), "4")
        XCTAssertEqual(deck.headerFooter(of: moved).footer, "Q4")
        XCTAssertTrue(deck.headerFooter(of: moved).skipTitleSlides)
        deck.undo()
        deck.undo()
        XCTAssertTrue(deck.slides.allSatisfy { footer($0, "sldNum") == nil }, "one undo step each")
    }

    func testFieldsSurviveASaveAndAreNotEdits() throws {
        let deck = SlidesSample.make()
        var hf = DeckController.HeaderFooter()
        hf.slideNumber = true
        deck.applyHeaderFooter(hf, toAll: true)
        let data = try Pptx.write(deck)
        let package = PptxPackage(try Zip.read(data))
        let slide3 = String(data: package.parts["ppt/slides/slide3.xml"]!, encoding: .utf8)!
        XCTAssertTrue(slide3.contains("type=\"slidenum\"><a:rPr"), "a field, not frozen text")
        XCTAssertTrue(slide3.contains("<a:t>3</a:t></a:fld>"))
        // Our layouts carry the footer placeholders PowerPoint binds to.
        let layout = String(data: package.parts["ppt/slideLayouts/slideLayout2.xml"]!, encoding: .utf8)!
        XCTAssertTrue(layout.contains("<p:ph type=\"sldNum\" sz=\"quarter\" idx=\"12\"/>"))

        // A file whose cached numbers are stale opens showing the right ones,
        // and opening it is not an edit.
        let stale = Data(slide3.replacingOccurrences(of: "<a:t>3</a:t></a:fld>", with: "<a:t>9</a:t></a:fld>").utf8)
        var entries: [ZipEntry] = []
        for (k, v) in package.parts { entries.append(ZipEntry(name: k, data: k == "ppt/slides/slide3.xml" ? stale : v)) }
        let (state, theme, pkg) = try Pptx.read(try Zip.write(entries))
        let opened = DeckController()
        opened.load(state, theme: theme, package: pkg)
        XCTAssertEqual(footer(opened.slides[2], "sldNum")?.text?.document.plainText(), "3")
        XCTAssertEqual(opened.edits, 0)
        XCTAssertEqual(footer(opened.slides[2], "sldNum")?.footerFrameMatchesLayout(state.slides[2]), true)
    }

    func testTypingOverAFieldMakesItText() {
        let deck = SlidesSample.make()
        var hf = DeckController.HeaderFooter()
        hf.slideNumber = true
        deck.applyHeaderFooter(hf, toAll: false)
        let number = footer(deck.currentSlide, "sldNum")!
        number.text!.selectAll()
        number.text!.insertText("Page one")
        deck.addSlide()
        XCTAssertNil(number.field)
        XCTAssertEqual(number.text?.document.plainText(), "Page one")
    }
}

private extension SlideShape {
    /// The shape sits where its slide's layout keeps that placeholder.
    func footerFrameMatchesLayout(_ slide: SlideState) -> Bool {
        guard let type = phType, let f = slide.footerFrames[type] else { return false }
        return abs(f.left - frame.left) < 0.5 && abs(f.top - frame.top) < 0.5
    }
}
