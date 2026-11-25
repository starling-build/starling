import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

/// The Format Background pane: solid, gradient and picture fills, one slide or all, and the file they save to.
final class SlideFormatBackgroundTests: XCTestCase {
    private func settle(_ ui: WidgetTester) {
        for _ in 0 ..< 3 { ui.pump(); for cb in FrameCallbackScheduler.shared.takePostFrameCallbacks() { cb(.zero) } }
        ui.pump()
    }

    private func pane(_ deck: DeckController, picture: @escaping () -> Void = {}) -> WidgetTester {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: FormatBackgroundPane(deck: deck, onPicture: picture, onClose: {}), title: "Test"),
                              size: Size(1280, 800))
        settle(ui)
        return ui
    }

    private func enter(_ ui: WidgetTester, _ id: String, _ text: String) {
        ui.tap(id: id)
        for _ in 0 ..< 10 { ui.press(.backspace) }
        ui.type(text); ui.press(.enter); settle(ui)
    }

    func testSolidThenGradientFromThePane() throws {
        let deck = DeckController()
        let ui = pane(deck)
        ui.tap(id: "bg.kind.solid"); settle(ui)
        XCTAssertNotNil(deck.currentSlide.background?.color)
        enter(ui, "bg.color", "336699")
        XCTAssertEqual((deck.currentSlide.background?.color?.value ?? 0) & 0xFFFFFF, 0x336699)
        ui.tap(id: "bg.kind.gradient"); settle(ui)
        XCTAssertGreaterThanOrEqual(deck.currentSlide.background?.stops.count ?? 0, 2)
        enter(ui, "bg.stop2", "FF0000")
        XCTAssertEqual((deck.currentSlide.background?.stops.last?.color.value ?? 0) & 0xFFFFFF, 0xFF0000)
        enter(ui, "bg.angle", "45")
        XCTAssertEqual(deck.currentSlide.background?.angle ?? 0, 45, accuracy: 0.01)
        ui.tap(id: "bg.kind.theme"); settle(ui)
        XCTAssertNil(deck.currentSlide.background)
    }

    func testApplyToAllSlidesAndPictureButton() throws {
        let deck = DeckController()
        _ = deck.addSlide()
        deck.select(0)
        var asked = 0
        let ui = pane(deck, picture: { asked += 1 })
        ui.tap(id: "bg.kind.solid"); settle(ui)
        enter(ui, "bg.color", "00AA00")
        ui.tap(id: "bg.all"); settle(ui)
        XCTAssertEqual((deck.masterBackground?.color?.value ?? 0) & 0xFFFFFF, 0x00AA00)
        XCTAssertTrue(deck.slides.allSatisfy { $0.background == nil && ($0.inheritedBackground?.color?.value ?? 0) & 0xFFFFFF == 0x00AA00 })
        ui.tap(id: "bg.kind.picture"); settle(ui)
        XCTAssertEqual(asked, 1)
    }

    func testGradientBackgroundSurvivesASave() throws {
        let deck = DeckController()
        deck.setBackground(FormatBackgroundPaneState.gradient(from: Color(0xFF336699)))
        let (state, _, _) = try Pptx.read(Pptx.write(deck))
        let f = try XCTUnwrap(state.slides[0].background)
        XCTAssertGreaterThanOrEqual(f.stops.count, 2)
        XCTAssertEqual(f.angle, 90, accuracy: 0.5)
    }

    func testApplyToAllWritesTheMasterAndOneUndoStepRestoresIt() throws {
        let deck = DeckController()
        _ = deck.addSlide()
        deck.select(1); deck.setBackground(SlideFill(color: Color(0xFFAA0000)))
        deck.select(0)
        deck.setBackground(SlideFill(color: Color(0xFF00AA00)), all: true)
        XCTAssertTrue(deck.slides.allSatisfy { $0.background == nil })
        // A slide added later picks it up.
        let added = deck.addSlide()
        XCTAssertEqual((added.inheritedBackground?.color?.value ?? 0) & 0xFFFFFF, 0x00AA00)
        let data = try Pptx.write(deck)
        let pkg = PptxPackage(try Zip.read(data))
        let master = String(data: pkg.parts["ppt/slideMasters/slideMaster1.xml"]!, encoding: .utf8)!
        XCTAssertTrue(master.contains("<p:bg><p:bgPr><a:solidFill><a:srgbClr val=\"00AA00\""), String(master.prefix(600)))
        for i in 1 ... deck.slides.count {
            let slide = String(data: pkg.parts["ppt/slides/slide\(i).xml"]!, encoding: .utf8)!
            XCTAssertFalse(slide.contains("<p:bg>"), "slide \(i)")
        }
        // Through a file: the master is changed and a layout's own background is dropped.
        let (state, _, _) = try Pptx.read(data)
        XCTAssertTrue(state.slides.allSatisfy { $0.background == nil })
        deck.undo()   // removes the added slide
        deck.undo()   // the Apply to All
        XCTAssertNil(deck.masterBackground)
        XCTAssertEqual((deck.slides[1].background?.color?.value ?? 0) & 0xFFFFFF, 0xAA0000)
    }

    func testApplyToAllWithAPictureWritesItOnceOnTheMaster() throws {
        let deck = DeckController()
        for _ in 0 ..< 2 { _ = deck.addSlide() }
        deck.select(0)
        var pic = SlideFill(image: ImageAttachment(data: Self.png, width: 64, height: 64))
        pic.imageAlpha = 0.6
        deck.setBackground(pic, all: true)
        XCTAssertNotNil(deck.masterBackground?.image)
        XCTAssertTrue(deck.slides.allSatisfy { $0.background == nil })
        XCTAssertNotNil(deck.addSlide().inheritedBackground?.image)
        if let out = ProcessInfo.processInfo.environment["STARLING_MASTERPIC_OUT"] { try Pptx.write(deck).write(to: URL(fileURLWithPath: out)) }
        func check(_ data: Data) throws {
            let pkg = PptxPackage(try Zip.read(data))
            XCTAssertEqual(pkg.parts.keys.filter { $0.hasPrefix("ppt/media/") }.count, 1, "\(pkg.parts.keys.sorted())")
            let master = String(data: pkg.parts["ppt/slideMasters/slideMaster1.xml"]!, encoding: .utf8)!
            XCTAssertTrue(master.contains("<p:bg><p:bgPr><a:blipFill") && master.contains("r:embed=\"rIdMasterBg\""))
            let rels = String(data: pkg.parts["ppt/slideMasters/_rels/slideMaster1.xml.rels"]!, encoding: .utf8)!
            XCTAssertTrue(rels.contains("Id=\"rIdMasterBg\"") && rels.contains("../media/master_background"), rels)
            for p in pkg.parts.keys where p.hasPrefix("ppt/slides/_rels/") {
                XCTAssertFalse(String(data: pkg.parts[p]!, encoding: .utf8)!.contains("media/"), p)
            }
        }
        let data = try Pptx.write(deck)
        try check(data)
        let (state, _, _) = try Pptx.read(data)
        XCTAssertTrue(state.slides.allSatisfy { $0.background == nil })
        XCTAssertNotNil(state.slides[0].inheritedBackground?.image)
        XCTAssertEqual(state.slides[0].inheritedBackground?.imageAlpha ?? 1, 0.6, accuracy: 0.01)
        deck.undo(); deck.undo()
        XCTAssertNil(deck.masterBackground)
    }

    func testApplyToAllWithAPictureOnAnOpenedFile() throws {
        let path = "/data/corpus-cache/test/corpus/pptx/decks/45545_Comment.pptx"
        guard FileManager.default.fileExists(atPath: path) else { throw XCTSkip("deck not in the corpus cache") }
        let (state, theme, pkg) = try Pptx.read(try Data(contentsOf: URL(fileURLWithPath: path)))
        let deck = DeckController()
        deck.load(state, theme: theme, package: pkg)
        deck.select(0)
        deck.setBackground(SlideFill(image: ImageAttachment(data: Self.png, width: 64, height: 64)), all: true)
        let out = PptxPackage(try Zip.read(try Pptx.write(deck)))
        XCTAssertEqual(out.parts.keys.filter { $0.contains("master_background") }.count, 1)
        let masters = out.parts.keys.filter { $0.hasPrefix("ppt/slideMasters/slideMaster") && $0.hasSuffix(".xml") }
        XCTAssertFalse(masters.isEmpty)
        for m in masters {
            let rels = String(data: out.parts[m.replacingAll("slideMasters/", with: "slideMasters/_rels/") + ".rels"]!, encoding: .utf8)!
            XCTAssertTrue(rels.contains("rIdMasterBg"), rels)
            XCTAssertTrue(String(data: out.parts[m]!, encoding: .utf8)!.contains("r:embed=\"rIdMasterBg\""))
        }
        for p in out.parts.keys where p.hasPrefix("ppt/slides/_rels/") {
            XCTAssertFalse(String(data: out.parts[p]!, encoding: .utf8)!.contains("master_background"), p)
        }
        let (back, _, _) = try Pptx.read(try Pptx.write(deck))
        XCTAssertNotNil(back.slides[0].inheritedBackground?.image)
    }

    /// STARLING_BGPIC_OUT: slides with their own backgrounds, then Apply to All with a picture, then one new slide.
    func testSaveMasterPictureAfterOwnBackgrounds() throws {
        let deck = DeckController()
        for _ in 0 ..< 2 { _ = deck.addSlide() }
        deck.select(0); deck.setBackground(SlideFill(color: Color(0xFF336699)))
        deck.select(1); deck.setBackground(FormatBackgroundPaneState.gradient(from: Color(0xFFCC3333)))
        deck.select(0)
        var pic = SlideFill(image: ImageAttachment(data: Self.png, width: 64, height: 64))
        pic.tiled = true
        pic.imageAlpha = 0.6
        deck.setBackground(pic, all: true)
        deck.select(2)
        _ = deck.addSlide()
        let data = try Pptx.write(deck)
        if let out = ProcessInfo.processInfo.environment["STARLING_BGPIC_OUT"] { try data.write(to: URL(fileURLWithPath: out)) }
        let (state, _, _) = try Pptx.read(data)
        XCTAssertEqual(state.slides.count, 4)
        XCTAssertTrue(state.slides.allSatisfy { $0.background == nil && $0.inheritedBackground?.image != nil })
    }

    private static let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAIAAAAlC+aJAAABTklEQVR4nNXVQQrDMAxE0Rwnp+u6R+xJ5hppIRBCJKt2Ilka8M6D4K3+sm0b3qt86+ujPnWcuF9+f6qBCaAayADSwAe4GCgBZwMr4DAQA3YDDaD1wdKHJgAkfbAAqoEMIA18ANTuQxcAhfvQC0DVPgwAULIPesiMQ9X6MAxAsT7cAagGMoA08AFQow+PACjQh6cAZPfBAYDUPoyFzDiU1Qc3AJL64AlQDWQAaeADYG4fQgCY2IcoAGb1IRCAKX3wCZmxj+5DOADBfZgBUA1kAGngAyCmD1MBCOjDbAC8+5AAgGsfYkNm7L36kAaAUx8yAaqBDCANfAA860MJAB70oQoAd/tQCIBbfcgJmbEf7UM5AAb7UBGgGsgA0sAHQF8fSgPQ0YfqAPzrAwEAZh9qhczYt/pAA0CjD0wA1UAGkAY+wMVACTgbWAGHgRiwG77flX8a/qckzQAAAABJRU5ErkJggg==")!

    /// A deck for PowerPoint to open (STARLING_BACKGROUNDS_OUT): every kind of background, one per slide, after one Apply to All.
    func testSaveEveryKindOfBackground() throws {
        let deck = DeckController()
        for _ in 0 ..< 3 { _ = deck.addSlide() }
        deck.select(0)
        deck.setBackground(SlideFill(color: Color(0xFFF2E6D0)), all: true)
        deck.select(0); deck.setBackground(SlideFill(color: Color(0xFF336699)))
        deck.select(1); deck.setBackground(FormatBackgroundPaneState.gradient(from: Color(0xFFCC3333)))
        deck.select(2)
        var pic = SlideFill(image: ImageAttachment(data: Self.png, width: 64, height: 64))
        pic.imageAlpha = 0.6
        pic.tiled = true
        deck.setBackground(pic)
        deck.select(3); deck.setBackground(nil)
        _ = deck.addSlide()   // slide 5: follows the master
        let data = try Pptx.write(deck)
        if let out = ProcessInfo.processInfo.environment["STARLING_BACKGROUNDS_OUT"] { try data.write(to: URL(fileURLWithPath: out)) }
        let (state, _, _) = try Pptx.read(data)
        XCTAssertEqual((state.slides[0].background?.color?.value ?? 0) & 0xFFFFFF, 0x336699)
        XCTAssertGreaterThanOrEqual(state.slides[1].background?.stops.count ?? 0, 2)
        XCTAssertNotNil(state.slides[2].background?.image)
        XCTAssertEqual(state.slides[2].background?.imageAlpha ?? 1, 0.6, accuracy: 0.01)
        XCTAssertTrue(state.slides[2].background?.tiled ?? false)
        XCTAssertNil(state.slides[3].background)
        XCTAssertNil(state.slides[4].background)
        XCTAssertEqual(state.slides.count, 5)
    }
}
