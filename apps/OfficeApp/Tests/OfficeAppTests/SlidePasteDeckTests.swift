import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

/// S-ED-1: slides on the system clipboard (pasted into another deck through their pptx, in its theme or their
/// own), their Paste Options, and where a picture or the text of copied shapes lands.
final class SlidePasteDeckTests: XCTestCase {
    private func isPicture(_ shape: SlideShape?) -> Bool {
        if case .picture = shape?.kind { return true }
        return false
    }

    /// A dark deck's slide copied, as another process sees it (only the clipboard's bytes cross).
    private func darkSlide() -> (DeckController, ClipboardData) {
        let source = DeckController()
        source.applyTheme(DeckTheme.presets[1])
        source.addTextBox(text: "From the dark deck")
        source.addShape(.rect)
        return (source, source.slidesClipboardData(token: "slides:elsewhere:1"))
    }

    /// Use Destination Theme (the default): the slide takes this deck's background and colours. Keep Source
    /// Formatting, through Paste Options: it keeps the dark background, spelled out on the slide, and its fill.
    /// One Undo takes the paste out however often it was redone.
    func testSlidesCrossToAnotherDeckInEitherTheme() throws {
        let (source, data) = darkSlide()
        let dark = DeckTheme.presets[1]
        let target = DeckController()
        let n = target.slides.count
        XCTAssertTrue(target.canPasteSlides(data))
        XCTAssertTrue(target.pasteSlides(from: data))
        XCTAssertEqual(target.slides.count, n + 1)
        XCTAssertEqual(target.slidesPasteOptions, .destinationTheme)
        let here = target.slides[target.current]
        XCTAssertNil(here.background, "the deck's own background shows")
        let box = try XCTUnwrap(here.shapes.first { $0.text?.document.plainText() == "From the dark deck" })
        XCTAssertEqual(box.textTheme?.textColor, target.theme.text)
        let sourceFill = source.currentSlide.shapes.last?.fill
        let rect = try XCTUnwrap(here.shapes.last)
        XCTAssertEqual(rect.fill, target.theme.accents[0], "the fill follows this theme's accent")
        XCTAssertNotEqual(rect.fill, sourceFill)

        target.repasteSlides(.keepSource)
        XCTAssertEqual(target.slides.count, n + 1, "the slide is replaced, not added to")
        XCTAssertEqual(target.slidesPasteOptions, .keepSource)
        let kept = target.slides[target.current]
        XCTAssertEqual(kept.background?.color, dark.background)
        XCTAssertEqual(kept.shapes.last?.fill, sourceFill)
        XCTAssertNil(kept.shapes.last?.fillScheme, "its colours stop following a theme")
        XCTAssertEqual(kept.shapes.first { $0.text != nil }?.textTheme?.textColor, dark.text)

        target.undo()
        XCTAssertEqual(target.slides.count, n)
        XCTAssertNil(target.slidesPasteOptions)
    }

    /// Slides copied here paste back from the in-memory copy (the token is this deck's), after the pick.
    func testOwnSlidesPasteFromTheToken() throws {
        let deck = DeckController()
        deck.addTextBox(text: "Mine")
        deck.copySlides()
        let token = try XCTUnwrap(deck.slideClipboardToken)
        var got: ClipboardData?
        Clipboard.getData(Clipboard.kAll) { got = $0 }
        let data = try XCTUnwrap(got)
        XCTAssertEqual(data.custom[DeckController.slidesMime].map { String(decoding: $0, as: UTF8.self) }, token)
        XCTAssertNotNil(data.custom[DeckController.slidesPptxMime])
        let n = deck.slides.count
        XCTAssertTrue(deck.pasteSlides(from: data))
        XCTAssertEqual(deck.slides.count, n + 1)
        XCTAssertEqual(deck.current, 1)
        XCTAssertEqual(deck.lastPastedSlide, 1)
        XCTAssertTrue(deck.currentSlide.shapes.contains { $0.text?.document.plainText() == "Mine" })
    }

    /// A picture or the text of copied shapes, through Paste Options or Paste Special, lands where the shapes copy
    /// is (or would be), not in the middle of the slide; the picture is the shapes' size.
    func testConvertedPasteStaysWhereTheShapesWere() throws {
        let deck = DeckController()
        let box = deck.addTextBox(at: Rect.fromLTWH(40, 50, 200, 60))
        box.text?.load(RichDocument(plainText: "Placed"))
        deck.selectShapes([box])
        XCTAssertTrue(deck.copyShapes())
        var got: ClipboardData?
        Clipboard.getData(Clipboard.kAll) { got = $0 }
        let data = try XCTUnwrap(got)
        deck.selectShapes([])
        XCTAssertTrue(deck.pasteOnSlide(data))
        let shapes = try XCTUnwrap(deck.selection.first).frame
        XCTAssertEqual(shapes.left, 58, accuracy: 0.01, "a paste here cascades one step")

        deck.repaste(.picture)
        let picture = try XCTUnwrap(deck.selection.first)
        XCTAssertTrue(isPicture(picture))
        XCTAssertEqual(picture.frame.left, shapes.left, accuracy: 0.01)
        XCTAssertEqual(picture.frame.top, shapes.top, accuracy: 0.01)
        XCTAssertEqual(picture.frame.width, shapes.width, accuracy: 0.01)

        deck.repaste(.textOnly)
        let text = try XCTUnwrap(deck.selection.first)
        XCTAssertEqual(text.frame.left, shapes.left, accuracy: 0.01)
        XCTAssertEqual(text.frame.top, shapes.top, accuracy: 0.01)
        deck.undo()

        // Paste Special straight away goes where the shapes would.
        XCTAssertTrue(deck.paste(data, way: .textOnly))
        XCTAssertEqual(try XCTUnwrap(deck.selection.first).frame.left, 58, accuracy: 0.01)
        deck.undo()
        // Text from elsewhere still goes in the middle.
        XCTAssertTrue(deck.paste(ClipboardData(text: "elsewhere"), way: .textOnly))
        let middle = try XCTUnwrap(deck.selection.first).frame
        XCTAssertEqual(middle.center.dx, deck.slideSize.width / 2, accuracy: 1)
    }

    /// Text pasted alone, or a new text box, takes the deck's text-box defaults (the presentation's default text
    /// style before the master's otherStyle), not a fixed face: here Arial 24 centred in yellow. A deck that
    /// says nothing gets the theme's body font at 18 pt.
    func testTextBoxTakesTheDecksTextBoxDefaults() throws {
        let plain = DeckController()
        let bare = plain.addTextBox(text: "plain")
        XCTAssertEqual(bare.textTheme?.fontFamily, plain.theme.bodyFont)
        XCTAssertEqual(bare.textTheme?.fontSize, 18)

        var package = PptxPackage(try Zip.read(try Pptx.write(DeckController())))
        var xml = String(decoding: try XCTUnwrap(package.parts["ppt/presentation.xml"]), as: UTF8.self)
        if let r = PptxWriter._elementRange("p:defaultTextStyle", in: xml) { xml.removeSubrange(r) }
        let style = "<p:defaultTextStyle><a:lvl1pPr algn=\"ctr\"><a:defRPr sz=\"2400\"><a:solidFill><a:srgbClr val=\"FFFF66\"/></a:solidFill>"
            + "<a:latin typeface=\"Arial\"/></a:defRPr></a:lvl1pPr></p:defaultTextStyle>"
        let end = try XCTUnwrap(xml.findRange(of: "</p:presentation>"))
        xml.replaceSubrange(end.lowerBound ..< end.lowerBound, with: style)
        package.parts["ppt/presentation.xml"] = Data(xml.utf8)
        let (state, theme, pkg) = try Pptx.read(try Zip.write(package.parts.map { ZipEntry(name: $0.key, data: $0.value) }))
        XCTAssertEqual(theme.textBoxFont, "Arial")
        XCTAssertEqual(theme.textBoxSize, 24)
        XCTAssertEqual(theme.textBoxAlign, "ctr")
        let deck = DeckController()
        deck.load(state, theme: theme, package: pkg)
        let pasted = deck.addTextBox(text: "yellow")
        XCTAssertEqual(pasted.textTheme?.fontFamily, "Arial")
        XCTAssertEqual(pasted.textTheme?.fontSize, 24)
        XCTAssertEqual(pasted.textTheme?.textColor, Color(0xFFFFFF66))
        XCTAssertEqual(pasted.text?.document.paragraphs.first?.style.alignment, .center)
        // Saved and read back, it is still what was drawn.
        let (again, _, _) = try Pptx.read(try Pptx.write(deck))
        let back = try XCTUnwrap(again.slides[deck.current].shapes.first { $0.text?.plainText() == "yellow" })
        XCTAssertEqual(back.text?.paragraphs.first?.runs.first?.style.fontFamily ?? back.font, "Arial")
    }
}
