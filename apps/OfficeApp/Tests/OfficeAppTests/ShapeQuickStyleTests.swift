import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// S-SH-4: Shape Format > Shape Styles, the theme style gallery (7 colours by 6 rows).
final class ShapeQuickStyleTests: XCTestCase {
    private func deckWithShape() -> (DeckController, SlideShape) {
        let deck = DeckController()
        let s = deck.addShape(.rect)
        deck.selectShapes([s])
        return (deck, s)
    }

    private func rgb(_ c: Color?) -> UInt32? { c.map { UInt32(truncatingIfNeeded: $0.value) & 0xFFFFFF } }

    func testTheGalleryHasSevenColoursBySixRows() {
        XCTAssertEqual(ShapeQuickStyle.all.count, 42)
        XCTAssertEqual(ShapeQuickStyle(row: 1, column: 2).name, "Colored Fill - Accent 2")
        XCTAssertEqual(ShapeQuickStyle(row: 0, column: 0).name, "Colored Outline - Black, Dark 1")
    }

    func testEachRowResolvesItsFillLineAndText() {
        let deck = DeckController()
        let colors = deck.tableStyleColors()
        let accent1 = rgb(colors.scheme("accent1"))
        // Colored Outline: a white fill, an accent line 1 pt, dark text.
        let outline = ShapeQuickStyle(row: 0, column: 1).look(colors)
        XCTAssertEqual(rgb(outline.fill), 0xFFFFFF)
        XCTAssertEqual(rgb(outline.outline), accent1)
        XCTAssertEqual(outline.outlineWidth, 1)
        XCTAssertEqual(rgb(outline.text), rgb(colors.scheme("dk1")))
        // Colored Fill: an accent fill, its 50% shade as the line, light text.
        let filled = ShapeQuickStyle(row: 1, column: 1).look(colors)
        XCTAssertEqual(rgb(filled.fill), accent1)
        XCTAssertEqual(rgb(filled.outline), rgb(DeckController.shadeLinear(colors.scheme("accent1")!, 0.5)))
        XCTAssertEqual(rgb(filled.text), rgb(colors.scheme("lt1")))
        // Light 1 Outline: a white line 1½ pt over the accent fill.
        let light = ShapeQuickStyle(row: 2, column: 1).look(colors)
        XCTAssertEqual(rgb(light.outline), 0xFFFFFF)
        XCTAssertEqual(light.outlineWidth, 1.5)
        // Subtle and Moderate: gradients in the accent, no line for Moderate; Intense adds a shadow.
        XCTAssertNotNil(ShapeQuickStyle(row: 3, column: 1).look(colors).gradient)
        let moderate = ShapeQuickStyle(row: 4, column: 1).look(colors)
        XCTAssertNotNil(moderate.gradient)
        XCTAssertNil(moderate.outline)
        XCTAssertNil(moderate.shadow)
        XCTAssertNotNil(ShapeQuickStyle(row: 5, column: 1).look(colors).shadow)
    }

    func testApplyingIsOneUndoStep() {
        let (deck, s) = deckWithShape()
        let fill = rgb(s.fill), line = rgb(s.outline)
        deck.applyQuickStyle(ShapeQuickStyle(row: 0, column: 3))
        XCTAssertEqual(s.quickStyle, ShapeQuickStyle(row: 0, column: 3))
        XCTAssertEqual(deck.currentQuickStyle, ShapeQuickStyle(row: 0, column: 3))
        XCTAssertEqual(rgb(s.fill), 0xFFFFFF)
        XCTAssertEqual(rgb(s.outline), rgb(deck.tableStyleColors().scheme("accent3")))
        deck.undo()
        XCTAssertNil(s.quickStyle)
        XCTAssertEqual(rgb(s.fill), fill)
        XCTAssertEqual(rgb(s.outline), line)
    }

    func testHoverPreviewsAndLeavingRestores() {
        let (deck, s) = deckWithShape()
        let fill = rgb(s.fill), line = rgb(s.outline), width = s.outlineWidth
        deck.previewQuickStyle(ShapeQuickStyle(row: 5, column: 2))
        XCTAssertNotNil(s.fillStyle, "the preview shows the gradient")
        XCTAssertNotNil(s.shadow)
        deck.endQuickStylePreview()
        XCTAssertNil(s.fillStyle)
        XCTAssertNil(s.shadow)
        XCTAssertNil(s.quickStyle)
        XCTAssertEqual(rgb(s.fill), fill)
        XCTAssertEqual(rgb(s.outline), line)
        XCTAssertEqual(s.outlineWidth, width)
        deck.undo()
        XCTAssertFalse(deck.currentSlide.shapes.contains { $0 === s }, "a preview is not an edit: undo takes back the insert")
    }

    func testSavingWritesTheStyleRefs() throws {
        let (deck, _) = deckWithShape()
        deck.applyQuickStyle(ShapeQuickStyle(row: 1, column: 2))
        let data = try Pptx.write(deck)
        let entries = try Zip.read(data)
        let slide = try XCTUnwrap(entries.first { $0.name == "ppt/slides/slide1.xml" })
        let xml = String(decoding: slide.data, as: UTF8.self)
        XCTAssertTrue(xml.contains("<a:lnRef idx=\"2\"><a:schemeClr val=\"accent2\"><a:shade val=\"50000\"/></a:schemeClr></a:lnRef>"), xml)
        XCTAssertTrue(xml.contains("<a:fillRef idx=\"1\"><a:schemeClr val=\"accent2\"/></a:fillRef>"))
        XCTAssertTrue(xml.contains("<a:fontRef idx=\"minor\"><a:schemeClr val=\"lt1\"/></a:fontRef>"))
        let (state, _, _) = try Pptx.read(data)
        let shape = try XCTUnwrap(state.slides[0].shapes.first { $0.fill != nil })
        XCTAssertEqual(rgb(shape.fill), rgb(deck.tableStyleColors().scheme("accent2")), "the explicit fill reads back")
    }

    func testAThemeChangeRedrawsAStyledShapeUnlessItWasChanged() {
        let (deck, s) = deckWithShape()
        let t = deck.addShape(.ellipse)
        deck.selectShapes([s, t])
        deck.applyQuickStyle(ShapeQuickStyle(row: 1, column: 1))
        deck.selectShapes([t])
        deck.applyShapeColor(.rgb(0x00B050), outline: false)
        var other = deck.theme
        other.accents[0] = Color(0xFF00AA00)
        deck.applyTheme(other)
        XCTAssertEqual(rgb(s.fill), 0x00AA00, "the styled shape takes the new accent")
        XCTAssertEqual(rgb(t.fill), 0x00B050, "a fill changed since keeps its colour")
    }
}
