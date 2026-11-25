import XCTest
import Flutter
import FlutterSwiftBridge
import OfficeText
@testable import OfficeApp

/// S-SH-4: Shape Fill and Shape Outline through the shared colour picker.
final class SlideShapeColorTests: XCTestCase {
    private func deckWithShape() -> (DeckController, SlideShape) {
        let deck = DeckController()
        let s = deck.addShape(.rect)
        deck.selectShapes([s])
        return (deck, s)
    }

    func testAnAccentAndATintKeepTheirThemeLink() throws {
        let (deck, s) = deckWithShape()
        deck.applyShapeColor(.theme(slot: 5, lumMod: 100, lumOff: 0), outline: false)
        XCTAssertEqual(s.fillScheme, "accent2")
        XCTAssertEqual(UInt32(truncatingIfNeeded: s.fill!.value) & 0xFFFFFF, deck.theme.slots[5])
        deck.applyShapeColor(.theme(slot: 5, lumMod: 60, lumOff: 40), outline: false)
        XCTAssertEqual(s.fillScheme, "accent2|60000|40000", "a tint keeps its theme link")
        XCTAssertEqual(UInt32(truncatingIfNeeded: s.fill!.value) & 0xFFFFFF, ColorMath.adjusted(deck.theme.slots[5], lumMod: 60, lumOff: 40))
        deck.applyShapeColor(.theme(slot: 4, lumMod: 40, lumOff: 60), outline: true)
        XCTAssertEqual(s.outlineScheme, "accent1|40000|60000")
        deck.applyShapeColor(.rgb(0x00B050), outline: true)
        XCTAssertNil(s.outlineScheme, "a plain colour has no link")
        XCTAssertEqual(UInt32(truncatingIfNeeded: s.outline!.value) & 0xFFFFFF, 0x00B050)
        deck.applyShapeColor(.none, outline: false); deck.applyShapeColor(.none, outline: true)
        XCTAssertNil(s.fill); XCTAssertNil(s.outline)
        deck.undo()
        XCTAssertNotNil(s.outline, "undo brings the outline back")
        XCTAssertEqual(deck.recentShapeColors.list.first, 0x00B050)
    }

    func testATintFollowsTheThemeAndSurvivesSaving() throws {
        let (deck, s) = deckWithShape()
        deck.applyShapeColor(.theme(slot: 5, lumMod: 60, lumOff: 40), outline: false)
        deck.applyShapeColor(.theme(slot: 6, lumMod: 75, lumOff: 0), outline: true)
        let (state, _, _) = try Pptx.read(Pptx.write(deck))
        let r = try XCTUnwrap(state.slides[0].shapes.first { $0.fillScheme == "accent2|60000|40000" })
        XCTAssertEqual(r.outlineScheme, "accent3|75000|0")
        let xml = String(decoding: try Pptx.write(deck), as: UTF8.self)
        _ = xml
        var other = deck.theme
        other.accents[1] = Color(0xFF00AA00)
        deck.applyTheme(other)
        XCTAssertEqual(UInt32(truncatingIfNeeded: s.fill!.value) & 0xFFFFFF, ColorMath.adjusted(0x00AA00, lumMod: 60, lumOff: 40))
    }

    func testThePickerGridAppliesAFillAndAnOutline() throws {
        let (deck, s) = deckWithShape()
        var more = 0
        let item = ColorGridMenuItem(theme: deck.theme.slots, recent: [0x123456], noneLabel: "No Fill",
                                     onChoose: { deck.applyShapeColor($0, outline: false) }, onMore: { more += 1 })
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: Builder(builder: { ctx in item.buildItem(ctx) }), title: "T"))
        XCTAssertTrue(ui.has(text: "Theme Colors")); XCTAssertTrue(ui.has(text: "Standard Colors")); XCTAssertTrue(ui.has(text: "Recent Colors"))
        XCTAssertTrue(ui.tap(tip: "Accent 3"))
        XCTAssertEqual(s.fillScheme, "accent3")
        XCTAssertTrue(ui.tap(tip: "Purple"))
        XCTAssertEqual(UInt32(truncatingIfNeeded: s.fill!.value) & 0xFFFFFF, 0x7030A0)
        XCTAssertTrue(ui.tap(text: "No Fill"))
        XCTAssertNil(s.fill)
        XCTAssertTrue(ui.tap(text: "More Colors…"))
        XCTAssertEqual(more, 1)
    }

    func testWritesThePowerPointCheckFile() throws {
        let (deck, s) = deckWithShape()
        s.frame = Rect.fromLTWH(60, 60, 220, 110)
        deck.applyShapeColor(.theme(slot: 6, lumMod: 100, lumOff: 0), outline: false)
        deck.applyShapeColor(.theme(slot: 4, lumMod: 40, lumOff: 60), outline: true)
        let t = deck.addShape(.ellipse); t.frame = Rect.fromLTWH(60, 220, 220, 110); deck.selectShapes([t])
        deck.applyShapeColor(.theme(slot: 7, lumMod: 75, lumOff: 0), outline: false)
        deck.applyShapeColor(.rgb(0x7030A0), outline: true)
        let u = deck.addShape(.rect); u.frame = Rect.fromLTWH(340, 60, 220, 110); deck.selectShapes([u])
        deck.applyShapeColor(.none, outline: false)
        deck.applyShapeColor(.rgb(0xC00000), outline: true)
        let dir = "/data/s/amd-6/ui-check"
        guard FileManager.default.fileExists(atPath: dir) else { return }
        try Pptx.write(deck).write(to: URL(fileURLWithPath: dir + "/shapecolor.pptx"))
        let (state, _, _) = try Pptx.read(Pptx.write(deck))
        XCTAssertEqual(state.slides[0].shapes.filter { $0.fillScheme == "accent3" }.count, 1)
        XCTAssertEqual(state.slides[0].shapes.filter { $0.fillScheme == "accent4|75000|0" }.count, 1)
        XCTAssertEqual(state.slides[0].shapes.filter { $0.outlineScheme == "accent1|40000|60000" }.count, 1)
    }
}
