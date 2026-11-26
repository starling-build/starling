import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

final class PptxTests: XCTestCase {
    private func roundTrip(_ deck: DeckController) throws -> (DeckState, DeckTheme, PptxPackage) {
        try Pptx.read(Pptx.write(deck))
    }

    /// S-P0-2: a theme applied to a deck read from a file recolours the file's theme part and keeps its masters and layouts.
    func testApplyingAThemeToAnOpenedDeckKeepsItsMastersAndLayouts() throws {
        _ = OfficeFonts.register()
        let (state, theme, package) = try roundTrip(SlidesSample.make())
        let opened = DeckController()
        opened.load(state, theme: theme, package: package)
        let ocean = DeckTheme.presets.first { $0.name == "Ocean" }!
        opened.applyTheme(ocean)
        XCTAssertFalse(opened.ownTemplates)
        let saved = PptxPackage(try Zip.read(try Pptx.write(opened)))
        func names(_ p: PptxPackage) -> [String] { p.parts.keys.filter { $0.hasPrefix("ppt/slideMasters/") || $0.hasPrefix("ppt/slideLayouts/") }.sorted() }
        XCTAssertEqual(names(saved), names(package), "the file's masters and layouts are all still there")
        XCTAssertEqual(saved.parts["ppt/slideLayouts/slideLayout1.xml"], package.parts["ppt/slideLayouts/slideLayout1.xml"], "a layout is written as it was")
        let themeXML = String(data: saved.parts["ppt/theme/theme1.xml"]!, encoding: .utf8)!
        XCTAssertTrue(themeXML.containsSubstring("<a:accent1><a:srgbClr val=\"\(PptxText.hex(ocean.accents[0]))\"/></a:accent1>"))
        XCTAssertTrue(themeXML.containsSubstring("<a:latin typeface=\"\(ocean.headingFont)\"/>"))
        // Undo goes back to the file's own colours.
        opened.undo()
        XCTAssertFalse(opened.recolourTheme)
        let (_, reopened, _) = try Pptx.read(Pptx.write(opened))
        XCTAssertEqual(reopened.accents[0], theme.accents[0])
    }

    func testANewDeckSurvivesItsOwnWriter() throws {
        _ = OfficeFonts.register()
        let deck = SlidesSample.make()
        // The model leaves looks to the theme; the file spells them out. So:
        // the words survive the first trip, and a second trip is a fixed point.
        let (once, theme1, package1) = try roundTrip(deck)
        for (a, b) in zip(deck.snapshot().slides, once.slides) {
            XCTAssertEqual(a.shapes.map { $0.text?.plainText() }, b.shapes.map { $0.text?.plainText() })
            XCTAssertEqual(a.shapes.map(\.frame), b.shapes.map(\.frame))
        }
        let (twice, theme2, _) = try Pptx.read(PptxWriter.write(once, theme: theme1, package: package1))
        XCTAssertEqual(SlidesDump.text(twice, theme: theme2), SlidesDump.text(once, theme: theme1))
    }

    func testPlaceholdersBindToTheirLayouts() throws {
        let deck = SlidesSample.make()
        let data = try Pptx.write(deck)
        let package = PptxPackage(try Zip.read(data))
        // Slide 4 is Two Content: two body placeholders, idx 1 and 2, on a
        // layout of type twoObj that has both.
        let slide = package.xml("ppt/slides/slide4.xml")!
        let phs = slide.descendant("p:spTree")!.all("p:sp").compactMap { $0.descendant("p:ph") }
        XCTAssertEqual(phs.map { $0["idx"] }, [nil, "1", "2"])
        let layout = package.rel("ppt/slides/slide4.xml", kind: "slideLayout")!.target
        XCTAssertEqual(package.xml(layout)?["type"], "twoObj")
        let layoutIdx = package.xml(layout)!.descendant("p:spTree")!.all("p:sp").compactMap { $0.descendant("p:ph")?["idx"] }
        XCTAssertEqual(layoutIdx, ["1", "2", "10", "11", "12"], "the two bodies, then date, footer and number")
    }

    func testHiddenSlidesAndNotes() throws {
        let deck = SlidesSample.make()
        let (state, _, _) = try roundTrip(deck)
        XCTAssertTrue(state.slides.last!.hidden)
        XCTAssertEqual(state.slides[0].notes.plainText(), "Open with the numbers.")
    }

    func testRunLooksAreExplicit() throws {
        // A heading placeholder whose layout says bold, typed into without
        // bold, stays not bold after a round trip.
        let deck = SlidesSample.make()
        let (state, _, _) = try roundTrip(deck)
        let comparison = state.slides.first { $0.layout == .comparison }!
        let heading = comparison.shapes.first { $0.phIdx == "1" }!
        XCTAssertEqual(heading.text?.plainText(), "Before")
        XCTAssertEqual(heading.text?.paragraphs.first?.runs.first?.style.bold, false)
    }

    func testKeptObjectsAndTheirPartsGoThroughUntouched() throws {
        // A package with a chart on a slide: the graphicFrame is kept, its
        // r:id re-pointed, and the chart part (with its own rels) copied.
        let deck = SlidesSample.make()
        var package = PptxPackage(try Zip.read(try Pptx.write(deck)))
        let chart = "<c:chartSpace xmlns:c=\"http://schemas.openxmlformats.org/drawingml/2006/chart\"/>"
        package.parts["ppt/charts/chart9.xml"] = Data(chart.utf8)
        package.parts["ppt/charts/_rels/chart9.xml.rels"] = Data("<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/package\" Target=\"../embeddings/Book9.xlsx\"/></Relationships>".utf8)
        package.parts["ppt/embeddings/Book9.xlsx"] = Data([0x50, 0x4B, 0x03, 0x04])
        package.overrides["ppt/charts/chart9.xml"] = "application/vnd.openxmlformats-officedocument.drawingml.chart+xml"
        package.defaults["xlsx"] = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        let frame = "<p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id=\"40\" name=\"Chart 1\"/><p:cNvGraphicFramePr/><p:nvPr/></p:nvGraphicFramePr><p:xfrm><a:off x=\"1270000\" y=\"1270000\"/><a:ext cx=\"2540000\" cy=\"1270000\"/></p:xfrm><a:graphic><a:graphicData uri=\"http://schemas.openxmlformats.org/drawingml/2006/chart\"><c:chart xmlns:c=\"http://schemas.openxmlformats.org/drawingml/2006/chart\" r:id=\"rId7\"/></a:graphicData></a:graphic></p:graphicFrame>"
        var slide = String(data: package.parts["ppt/slides/slide2.xml"]!, encoding: .utf8)!
        slide = slide.replacingOccurrences(of: "</p:spTree>", with: frame + "</p:spTree>")
        package.parts["ppt/slides/slide2.xml"] = Data(slide.utf8)
        var rels = String(data: package.parts["ppt/slides/_rels/slide2.xml.rels"]!, encoding: .utf8)!
        rels = rels.replacingOccurrences(of: "</Relationships>", with: "<Relationship Id=\"rId7\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart\" Target=\"../charts/chart9.xml\"/></Relationships>")
        package.parts["ppt/slides/_rels/slide2.xml.rels"] = Data(rels.utf8)

        var entries: [ZipEntry] = []
        for (k, v) in package.parts { entries.append(ZipEntry(name: k, data: v)) }
        let (state, theme, pkg) = try Pptx.read(try Zip.write(entries))
        let kept = state.slides[1].shapes.first { if case .opaque = $0.kind { return true }; return false }
        XCTAssertNotNil(kept, "the chart frame is kept")
        XCTAssertEqual(kept?.frame, Rect.fromLTWH(100, 100, 200, 100))

        let out = PptxPackage(try Zip.read(try PptxWriter.write(state, theme: theme, package: pkg)))
        XCTAssertNotNil(out.parts["ppt/charts/chart9.xml"], "the chart part is copied")
        XCTAssertNotNil(out.parts["ppt/embeddings/Book9.xlsx"], "and what the chart reaches")
        let rel = out.rels("ppt/slides/slide2.xml").first { $0.kind == "chart" }
        XCTAssertEqual(rel?.target, "ppt/charts/chart9.xml")
        let written = String(data: out.parts["ppt/slides/slide2.xml"]!, encoding: .utf8)!
        XCTAssertTrue(written.contains("r:id=\"\(rel!.id)\""), "the frame points at the copied chart")
    }

    func testRelativePaths() {
        XCTAssertEqual(Pptx.relative("ppt/charts/chart1.xml", from: "ppt/slides/slide3.xml"), "../charts/chart1.xml")
        XCTAssertEqual(Pptx.relative("ppt/slides/slide3.xml", from: "ppt/presentation.xml"), "slides/slide3.xml")
        XCTAssertEqual(Pptx.resolve("../media/a.png", from: "ppt/slides/slide3.xml"), "ppt/media/a.png")
        XCTAssertEqual(Pptx.resolve("ppt/presentation.xml", from: ""), "ppt/presentation.xml")
    }
}

final class TransitionTests: XCTestCase {
    func testTransitionsRoundTrip() throws {
        let deck = SlidesSample.make()
        deck.select(1)
        deck.setTransition(.push, direction: .up, duration: 1.0)
        deck.select(2)
        deck.setTransition(.fade, duration: 0.5)
        let (state, _, _) = try Pptx.read(Pptx.write(deck))
        XCTAssertEqual(state.slides[1].transition.kind, .push)
        XCTAssertEqual(state.slides[1].transition.direction, .up)
        XCTAssertEqual(state.slides[1].transition.duration, 1.0)
        XCTAssertEqual(state.slides[2].transition.kind, .fade)
        XCTAssertEqual(state.slides[0].transition.kind, .none)
    }

    func testMoreEffectsAndAdvanceRoundTrip() throws {
        let deck = SlidesSample.make()
        deck.select(0)
        deck.setTransition(.split, vertical: true, inward: true)
        deck.select(1)
        deck.setTransition(.zoom, duration: 0.7, zoomIn: false)
        deck.setTransition(advanceOnClick: false, advanceAfter: .some(3.5))
        deck.select(2)
        deck.setTransition(.pull, direction: .right)
        deck.select(3)
        deck.setTransition(advanceOnClick: false, advanceAfter: .some(2))   // no effect, advance only, not on a click
        let bytes = try Pptx.write(deck)
        let (state, _, package) = try Pptx.read(bytes)
        let t = state.slides.map(\.transition)
        XCTAssertEqual(t[0].kind, .split); XCTAssertTrue(t[0].vertical); XCTAssertTrue(t[0].inward)
        XCTAssertEqual(t[1].kind, .zoom); XCTAssertFalse(t[1].zoomIn)
        XCTAssertEqual(t[1].duration, 0.7, accuracy: 0.001)
        XCTAssertFalse(t[1].advanceOnClick); XCTAssertEqual(t[1].advanceAfter, 3.5)
        XCTAssertEqual(t[2].kind, .pull); XCTAssertEqual(t[2].direction, .right)
        XCTAssertTrue(t[2].advanceOnClick); XCTAssertNil(t[2].advanceAfter)
        XCTAssertEqual(t[3].kind, .none); XCTAssertEqual(t[3].advanceAfter, 2)
        XCTAssertFalse(t[3].advanceOnClick)
        XCTAssertTrue(String(decoding: package.parts["ppt/slides/slide4.xml"]!, as: UTF8.self).contains("advClick=\"0\" advTm=\"2000\""))
        let xml = String(decoding: package.parts["ppt/slides/slide2.xml"]!, as: UTF8.self)
        XCTAssertTrue(xml.contains("p14:dur=\"700\""))
        XCTAssertTrue(xml.contains("advClick=\"0\" advTm=\"3500\""))
        XCTAssertTrue(xml.contains("<mc:Fallback>"))
    }

    /// A plain save keeps every slide's transition as the file wrote it: an auto-advance with no effect
    /// inside mc:AlternateContent (lo-narration), and a bare transition naming only a speed (bug60715).
    func testPlainSaveKeepsEffectlessTransitions() throws {
        let deck = SlidesSample.make()
        var package = PptxPackage(try Zip.read(try Pptx.write(deck)))
        let timed = "<mc:AlternateContent xmlns:mc=\"http://schemas.openxmlformats.org/markup-compatibility/2006\"><mc:Choice "
            + "xmlns:p14=\"http://schemas.microsoft.com/office/powerpoint/2010/main\" Requires=\"p14\"><p:transition spd=\"slow\" "
            + "p14:dur=\"2000\" advTm=\"2453\"/></mc:Choice><mc:Fallback><p:transition spd=\"slow\" advTm=\"2453\"/></mc:Fallback></mc:AlternateContent>"
        for (n, t) in [(1, timed), (2, "<p:transition spd=\"slow\"/>")] {
            var slide = String(decoding: package.parts["ppt/slides/slide\(n).xml"]!, as: UTF8.self)
            if let r = slide.range(of: "<p:transition") ?? slide.range(of: "<mc:AlternateContent><mc:Choice Requires=\"p14\"><p:transition") {
                XCTFail("sample slide \(n) already has a transition at \(r)")
            }
            slide = slide.replacingOccurrences(of: "</p:sld>", with: t + "</p:sld>")
            package.parts["ppt/slides/slide\(n).xml"] = Data(slide.utf8)
        }
        let (state, theme, pkg) = try Pptx.read(try Zip.write(package.parts.map { ZipEntry(name: $0.key, data: $0.value) }))
        XCTAssertEqual(state.slides[0].transition.advanceAfter ?? 0, 2.453, accuracy: 1e-9)
        let out = PptxPackage(try Zip.read(try PptxWriter.write(state, theme: theme, package: pkg)))
        let one = String(decoding: out.parts["ppt/slides/slide1.xml"]!, as: UTF8.self)
        let two = String(decoding: out.parts["ppt/slides/slide2.xml"]!, as: UTF8.self)
        XCTAssertTrue(one.contains("<mc:Choice") && one.contains("p14:dur=\"2000\" spd=\"slow\" advTm=\"2453\"/>"), "the timed advance survives with its duration: " + String(one.suffix(700)))
        XCTAssertTrue(one.contains("<mc:Fallback><p:transition spd=\"slow\" advTm=\"2453\"/>"), "and its fallback")
        XCTAssertTrue(two.contains("<p:transition spd=\"slow\"/>"), "the bare transition survives")
        // Changed here, the transition is written fresh.
        var edited = state
        edited.slides[0].transition.kind = .fade
        let again = PptxPackage(try Zip.read(try PptxWriter.write(edited, theme: theme, package: pkg)))
        let fresh = String(decoding: again.parts["ppt/slides/slide1.xml"]!, as: UTF8.self)
        XCTAssertTrue(fresh.contains("<p:fade/>") && fresh.contains("advTm=\"2453\""))
    }

    func testAdvanceOnlyKeepsAnUnknownTransition() throws {
        let deck = SlidesSample.make()
        let bytes = try Pptx.write(deck)
        var package = PptxPackage(try Zip.read(bytes))
        var slide = String(decoding: package.parts["ppt/slides/slide1.xml"]!, as: UTF8.self)
        slide = slide.replacingOccurrences(of: "</p:cSld>", with: "</p:cSld><p:transition spd=\"slow\"><p:vortex dir=\"r\"/></p:transition>")
        package.parts["ppt/slides/slide1.xml"] = Data(slide.utf8)
        let zipped = try Zip.write(package.parts.map { ZipEntry(name: $0.key, data: $0.value) })
        let (state, theme, pkg) = try Pptx.read(zipped)
        var slide0 = state.slides[0]
        XCTAssertNotNil(slide0.transition.raw)
        slide0.transition.advanceAfter = 4
        var edited = state
        edited.slides[0] = slide0
        let out = PptxPackage(try Zip.read(try PptxWriter.write(edited, theme: theme, package: pkg)))
        let xml = String(decoding: out.parts["ppt/slides/slide1.xml"]!, as: UTF8.self)
        XCTAssertTrue(xml.contains("<p:vortex"))
        XCTAssertTrue(xml.contains("advTm=\"4000\""))
    }

    /// For the PowerPoint check: a corpus deck with one transition of each kind, saved to STARLING_TRANSITION_OUT.
    func testSaveTransitionDeck() throws {
        guard let out = ProcessInfo.processInfo.environment["STARLING_TRANSITION_OUT"] else { throw XCTSkip("no output path") }
        let path = "/data/corpus-cache/test/corpus/pptx/decks/layouts.pptx"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { throw XCTSkip("no corpus cache") }
        let (state, theme, pkg) = try Pptx.read(data)
        let deck = DeckController()
        deck.load(state, theme: theme, package: pkg)
        var notes: [String] = []
        func set(_ i: Int, _ label: String, _ body: () -> Void) {
            deck.select(i); body(); notes.append("slide \(i + 1): \(label)")
        }
        set(0, "Fade, 0.5 s") { deck.setTransition(.fade, duration: 0.5) }
        set(1, "Push from left, 1.5 s") { deck.setTransition(.push, direction: .right, duration: 1.5) }
        set(2, "Wipe from bottom, 0.75 s, advance after 3 s as well as on click") {
            deck.setTransition(.wipe, direction: .up, duration: 0.75); deck.setTransition(advanceAfter: .some(3)) }
        set(3, "Cover from top, click does not advance, after 2 s") {
            deck.setTransition(.cover, direction: .down); deck.setTransition(advanceOnClick: false, advanceAfter: .some(2)) }
        set(4, "Uncover to the left") { deck.setTransition(.pull, direction: .left) }
        set(5, "Split vertical in, 2 s") { deck.setTransition(.split, duration: 2, vertical: true, inward: true) }
        set(6, "Zoom out") { deck.setTransition(.zoom, zoomIn: false) }
        set(7, "No effect, advance after 1 s only (click does not advance)") {
            deck.setTransition(.none); deck.setTransition(advanceOnClick: false, advanceAfter: .some(1)) }
        try Pptx.write(deck).write(to: URL(fileURLWithPath: out))
        try notes.joined(separator: "\n").write(toFile: out + ".txt", atomically: true, encoding: .utf8)
    }

    func testApplyToAllAndUndo() {
        let deck = SlidesSample.make()
        deck.setTransition(.wipe, all: true)
        XCTAssertTrue(deck.slides.allSatisfy { $0.transition.kind == .wipe })
        deck.undo()
        XCTAssertTrue(deck.slides.allSatisfy { $0.transition.kind == .none })
    }
}

final class AnimationKeepTests: XCTestCase {
    /// A slide's p:timing names shapes by file id: it survives a save while
    /// those shapes do, and goes when one of them is deleted.
    func testTimingKeptWhileItsShapesExist() throws {
        // Slide 3: the sample's slide 2 carries animations of its own.
        let deck = SlidesSample.make()
        var package = PptxPackage(try Zip.read(try Pptx.write(deck)))
        var slide = String(data: package.parts["ppt/slides/slide3.xml"]!, encoding: .utf8)!
        let firstId = slide.components(separatedBy: "<p:cNvPr id=\"")[2].prefix { $0.isNumber }
        let timing = "<p:timing><p:tnLst><p:par><p:cTn id=\"1\" dur=\"indefinite\" nodeType=\"tmRoot\"><p:childTnLst><p:par><p:cTn id=\"2\"><p:stCondLst><p:cond delay=\"0\"/></p:stCondLst><p:childTnLst><p:set><p:cBhvr><p:cTn id=\"3\" dur=\"1\"/><p:tgtEl><p:spTgt spid=\"\(firstId)\"/></p:tgtEl></p:cBhvr><p:to><p:strVal val=\"visible\"/></p:to></p:set></p:childTnLst></p:cTn></p:par></p:childTnLst></p:cTn></p:par></p:tnLst></p:timing>"
        slide = slide.replacingOccurrences(of: "</p:sld>", with: timing + "</p:sld>")
        package.parts["ppt/slides/slide3.xml"] = Data(slide.utf8)
        let zipped = try Zip.write(package.parts.map { ZipEntry(name: $0.key, data: $0.value) })
        let (state, theme, pkg) = try Pptx.read(zipped)
        XCTAssertNotNil(state.slides[2].timingXML)

        let kept = String(data: PptxPackage(try Zip.read(try PptxWriter.write(state, theme: theme, package: pkg)))
            .parts["ppt/slides/slide3.xml"]!, encoding: .utf8)!
        XCTAssertTrue(kept.contains("spid=\"\(firstId)\""), "animations kept while their shape is")

        var gone = state
        gone.slides[2].shapes.removeAll { $0.fileId == Int(firstId) }
        let dropped = String(data: PptxPackage(try Zip.read(try PptxWriter.write(gone, theme: theme, package: pkg)))
            .parts["ppt/slides/slide3.xml"]!, encoding: .utf8)!
        XCTAssertFalse(dropped.contains("<p:timing"), "and dropped once it is gone")
    }
}

final class TableTests: XCTestCase {
    private func tableShape(_ state: DeckState) -> ShapeState? {
        state.slides.flatMap(\.shapes).first { $0.kind == .table }
    }

    private func cells(_ doc: RichDocument?) -> [String] {
        doc?.paragraphs.map(\.text) ?? []
    }

    func testTablesRoundTrip() throws {
        let deck = SlidesSample.make()
        let (state, _, _) = try Pptx.read(Pptx.write(deck))
        let table = try XCTUnwrap(tableShape(state))
        XCTAssertEqual(cells(table.text), ["Feature", "Writer", "Slides", "Open", "docx", "pptx", "Save", "yes", "yes"])
        let id = try XCTUnwrap(table.text?.paragraphs.first?.cell?.table)
        XCTAssertEqual(table.text?.tableColumns[id]?.count, 3)
        let style = table.text?.tableStyles[id]
        XCTAssertEqual(style?.headerFill, deck.theme.accents[0], "the header row keeps the accent fill")
        XCTAssertEqual(table.text?.paragraphs.first?.runs.first?.style.bold, true)
    }

    /// A deck with one rounded shape carrying what the model does not hold:
    /// link, alt text, adjust value, vertical text, wrap off, right-to-left,
    /// tab stop, character spacing, East Asian font, text outline, gradient text.
    private func deckWithAnnotatedShape() throws -> (DeckState, DeckTheme, PptxPackage) {
        let deck = SlidesSample.make()
        var package = PptxPackage(try Zip.read(try Pptx.write(deck)))
        let sp = "<p:sp><p:nvSpPr><p:cNvPr id=\"90\" name=\"Rounded\" descr=\"alt words\"><a:hlinkClick r:id=\"rId9\"/></p:cNvPr><p:cNvSpPr/><p:nvPr/></p:nvSpPr>"
            + "<p:spPr><a:xfrm><a:off x=\"1270000\" y=\"1270000\"/><a:ext cx=\"2540000\" cy=\"1270000\"/></a:xfrm>"
            + "<a:prstGeom prst=\"roundRect\"><a:avLst><a:gd name=\"adj\" fmla=\"val 31234\"/></a:avLst></a:prstGeom>"
            + "<a:solidFill><a:srgbClr val=\"336699\"/></a:solidFill></p:spPr>"
            + "<p:txBody><a:bodyPr vert=\"vert\" wrap=\"none\" rtlCol=\"1\"/><a:lstStyle/><a:p><a:pPr rtl=\"1\"><a:tabLst><a:tab pos=\"914400\" algn=\"l\"/></a:tabLst></a:pPr>"
            + "<a:r><a:rPr lang=\"en-US\" spc=\"300\"><a:ln w=\"12700\"><a:solidFill><a:srgbClr val=\"AA0000\"/></a:solidFill></a:ln><a:ea typeface=\"MS Mincho\"/></a:rPr><a:t>kept words</a:t></a:r><a:r><a:rPr lang=\"en-US\"><a:gradFill><a:gsLst><a:gs pos=\"0\"><a:srgbClr val=\"112233\"/></a:gs><a:gs pos=\"100000\"><a:srgbClr val=\"445566\"/></a:gs></a:gsLst></a:gradFill></a:rPr><a:t> gradient words</a:t></a:r></a:p></p:txBody></p:sp>"
        var slide = String(data: package.parts["ppt/slides/slide2.xml"]!, encoding: .utf8)!
        slide = slide.replacingOccurrences(of: "</p:spTree>", with: sp + "</p:spTree>")
        package.parts["ppt/slides/slide2.xml"] = Data(slide.utf8)
        var rels = String(data: package.parts["ppt/slides/_rels/slide2.xml.rels"]!, encoding: .utf8)!
        rels = rels.replacingOccurrences(of: "</Relationships>", with: "<Relationship Id=\"rId9\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink\" Target=\"https://example.org/\" TargetMode=\"External\"/></Relationships>")
        package.parts["ppt/slides/_rels/slide2.xml.rels"] = Data(rels.utf8)
        var entries: [ZipEntry] = []
        for (k, v) in package.parts { entries.append(ZipEntry(name: k, data: v)) }
        return try Pptx.read(try Zip.write(entries))

    }

    private let annotatedKept = ["descr=\"alt words\"", "hlinkClick", "val 31234", "vert=\"vert\"", "wrap=\"none\"", "rtl=\"1\"",
                                 "pos=\"914400\"", "spc=\"300\"", "MS Mincho", "kept words", "AA0000", "gradFill", "445566"]

    private func writtenAnnotatedShape(_ state: DeckState, _ theme: DeckTheme, _ pkg: PptxPackage) throws -> String {
        let out = PptxPackage(try Zip.read(try PptxWriter.write(state, theme: theme, package: pkg)))
        let part = try XCTUnwrap(out.parts.keys.first { k in
            k.hasPrefix("ppt/slides/slide") && String(data: out.parts[k]!, encoding: .utf8)!.contains("name=\"Rounded\"")
        })
        return String(data: out.parts[part]!, encoding: .utf8)!
    }

    /// S-P0-1: a drag, a resize or a turn patches the frame in the shape's own
    /// XML and everything the model does not hold stays.
    func testMovingAShapePatchesItsFrameAndKeepsWhatTheModelDoesNotHold() throws {
        var (state, theme, pkg) = try deckWithAnnotatedShape()
        let si = try XCTUnwrap(state.slides.firstIndex { $0.shapes.contains { $0.name == "Rounded" } })
        let i = try XCTUnwrap(state.slides[si].shapes.firstIndex { $0.name == "Rounded" })
        state.slides[si].shapes[i].frame = Rect.fromLTWH(200, 150, 300, 80)
        state.slides[si].shapes[i].rotation = 30
        let written = try writtenAnnotatedShape(state, theme, pkg)
        for kept in annotatedKept { XCTAssertTrue(written.contains(kept), "kept after a move: \(kept)") }
        XCTAssertTrue(written.contains("<a:off x=\"2540000\" y=\"1905000\"/>"), "moved")
        XCTAssertTrue(written.contains("<a:ext cx=\"3810000\" cy=\"1016000\"/>"), "resized")
        XCTAssertTrue(written.contains("rot=\"1800000\""), "turned")
        let (again, _, _) = try Pptx.read(try PptxWriter.write(state, theme: theme, package: pkg))
        let back = try XCTUnwrap(again.slides.flatMap { $0.shapes }.first { $0.name == "Rounded" })
        XCTAssertEqual(back.frame, Rect.fromLTWH(200, 150, 300, 80))
        XCTAssertEqual(back.rotation, 30)
        XCTAssertEqual(again.slides[si].shapes.count, state.slides[si].shapes.count)
    }

    /// Flipping a kept shape is saved, and nothing else about it changes.
    func testFlippingAShapePatchesItsFlipAndKeepsWhatTheModelDoesNotHold() throws {
        var (state, theme, pkg) = try deckWithAnnotatedShape()
        let si = try XCTUnwrap(state.slides.firstIndex { $0.shapes.contains { $0.name == "Rounded" } })
        let i = try XCTUnwrap(state.slides[si].shapes.firstIndex { $0.name == "Rounded" })
        state.slides[si].shapes[i].flipH = true
        state.slides[si].shapes[i].flipV = true
        let written = try writtenAnnotatedShape(state, theme, pkg)
        for kept in annotatedKept { XCTAssertTrue(written.contains(kept), "kept after a flip: \(kept)") }
        let (again, _, _) = try Pptx.read(try PptxWriter.write(state, theme: theme, package: pkg))
        var back = try XCTUnwrap(again.slides.flatMap { $0.shapes }.first { $0.name == "Rounded" })
        XCTAssertTrue(back.flipH && back.flipV)
        back.flipH = false
        state.slides[si].shapes[i].flipH = false; state.slides[si].shapes[i].flipV = false
        let (clear, _, _) = try Pptx.read(try PptxWriter.write(state, theme: theme, package: pkg))
        let c = try XCTUnwrap(clear.slides.flatMap { $0.shapes }.first { $0.name == "Rounded" })
        XCTAssertFalse(c.flipH || c.flipV, "an unflipped shape has no flip left")
    }

    /// S-AR-1b: hiding a shape writes `hidden` into its own XML and keeps the rest; showing it again takes it out.
    func testHidingAShapePatchesItsHiddenFlagAndKeepsWhatTheModelDoesNotHold() throws {
        var (state, theme, pkg) = try deckWithAnnotatedShape()
        let si = try XCTUnwrap(state.slides.firstIndex { $0.shapes.contains { $0.name == "Rounded" } })
        let i = try XCTUnwrap(state.slides[si].shapes.firstIndex { $0.name == "Rounded" })
        state.slides[si].shapes[i].invisible = true
        let written = try writtenAnnotatedShape(state, theme, pkg)
        for kept in annotatedKept { XCTAssertTrue(written.contains(kept), "kept after hiding: \(kept)") }
        let (again, _, _) = try Pptx.read(try PptxWriter.write(state, theme: theme, package: pkg))
        XCTAssertTrue(try XCTUnwrap(again.slides.flatMap { $0.shapes }.first { $0.name == "Rounded" }).invisible)
        state.slides[si].shapes[i].invisible = false
        let (clear, _, _) = try Pptx.read(try PptxWriter.write(state, theme: theme, package: pkg))
        XCTAssertFalse(try XCTUnwrap(clear.slides.flatMap { $0.shapes }.first { $0.name == "Rounded" }).invisible)
    }

    /// S-AR-1b: writes the file for the PowerPoint check (SELPANE_CHECK_OUT=path): one shape hidden, two reordered, as the pane does.
    func testWriteSelectionPaneCheckFile() throws {
        guard let out = ProcessInfo.processInfo.environment["SELPANE_CHECK_OUT"] else { throw XCTSkip("no output path") }
        var (state, theme, pkg) = try deckWithAnnotatedShape()
        let si = try XCTUnwrap(state.slides.firstIndex { $0.shapes.contains { $0.name == "Rounded" } })
        let i = try XCTUnwrap(state.slides[si].shapes.firstIndex { $0.name == "Rounded" })
        state.slides[si].shapes[i].invisible = true
        let others = state.slides[si].shapes.indices.filter { $0 != i }
        XCTAssertGreaterThanOrEqual(others.count, 2)
        state.slides[si].shapes.swapAt(others[0], others[1])
        try PptxWriter.write(state, theme: theme, package: pkg).write(to: URL(fileURLWithPath: out))
    }

    /// S-P0-1b: typing in the shape changes its text and nothing else.
    func testTypingInAShapeKeepsWhatTheModelDoesNotHold() throws {
        var (state, theme, pkg) = try deckWithAnnotatedShape()
        let si = try XCTUnwrap(state.slides.firstIndex { $0.shapes.contains { $0.name == "Rounded" } })
        let i = try XCTUnwrap(state.slides[si].shapes.firstIndex { $0.name == "Rounded" })
        var doc = try XCTUnwrap(state.slides[si].shapes[i].text)
        doc.paragraphs[0].insert("TYPED ", at: 0)
        state.slides[si].shapes[i].text = doc
        let written = try writtenAnnotatedShape(state, theme, pkg)
        XCTAssertTrue(written.contains("TYPED"), "the typed text is written")
        for kept in annotatedKept where kept != "kept words" { XCTAssertTrue(written.contains(kept), "kept after typing: \(kept)") }
        let (again, _, _) = try Pptx.read(try PptxWriter.write(state, theme: theme, package: pkg))
        let back = try XCTUnwrap(again.slides.flatMap { $0.shapes }.first { $0.name == "Rounded" })
        XCTAssertTrue(back.text?.paragraphs.first.map { String(describing: $0).contains("TYPED") } ?? false)
    }

    func testAnUneditedTableIsKeptAndAnEditedOneRewritten() throws {
        // Swap the written style GUID for another of PowerPoint's: kept, it
        // survives; once a cell is edited, our own table replaces it.
        let deck = SlidesSample.make()
        var package = PptxPackage(try Zip.read(try Pptx.write(deck)))
        let ours = "{5C22544A-7EE6-4342-B048-85BDC9FD1C3A}", theirs = "{073A0DAA-6AF3-43AB-8588-CEC1D06C72B9}"
        let part = try XCTUnwrap(package.parts.keys.first { k in
            k.hasPrefix("ppt/slides/slide") && String(data: package.parts[k]!, encoding: .utf8)!.contains("<a:tbl>")
        })
        let slide = String(data: package.parts[part]!, encoding: .utf8)!
        package.parts[part] = Data(slide.replacingOccurrences(of: ours, with: theirs).utf8)
        var entries: [ZipEntry] = []
        for (k, v) in package.parts { entries.append(ZipEntry(name: k, data: v)) }
        var (state, theme, pkg) = try Pptx.read(try Zip.write(entries))

        func written(_ state: DeckState) throws -> String {
            let out = PptxPackage(try Zip.read(try PptxWriter.write(state, theme: theme, package: pkg)))
            let k = try XCTUnwrap(out.parts.keys.first { k in
                k.hasPrefix("ppt/slides/slide") && String(data: out.parts[k]!, encoding: .utf8)!.contains("<a:tbl>")
            })
            return String(data: out.parts[k]!, encoding: .utf8)!
        }
        XCTAssertTrue(try written(state).contains(theirs), "unedited: kept as read")

        let s = try XCTUnwrap(state.slides.firstIndex { $0.shapes.contains { $0.kind == .table } })
        let i = state.slides[s].shapes.firstIndex { $0.kind == .table }!
        var doc = state.slides[s].shapes[i].text!
        doc.paragraphs[4].insert(" (both)", at: 4)
        state.slides[s].shapes[i].text = doc
        let edited = try written(state)
        XCTAssertTrue(edited.contains(theirs) && !edited.contains(ours), "edited: typing in a cell keeps the file's own table element")
        XCTAssertTrue(edited.contains("docx (both)"))
    }

    func testThemeRecoloursOurTables() {
        let deck = SlidesSample.make()
        let table = deck.slides.flatMap(\.shapes).first { $0.kind == .table }!
        let ocean = DeckTheme.presets.first { $0.name == "Ocean" }!
        deck.applyTheme(ocean)
        XCTAssertEqual(table.text?.document.tableStyles[table.tableId!]?.headerFill, ocean.accents[0])
        deck.undo()
        XCTAssertEqual(deck.slides.flatMap(\.shapes).first { $0.kind == .table }?
            .text?.document.tableStyles[table.tableId!]?.headerFill, deck.theme.accents[0])
    }
}

final class GroupAndConnectorTests: XCTestCase {
    /// The sample with slide 6's box and star wrapped in a group whose own
    /// id an animation names, and a curved, rotated, flipped connector with
    /// an arrowhead.
    private func package() throws -> PptxPackage {
        let deck = SlidesSample.make()
        var package = PptxPackage(try Zip.read(try Pptx.write(deck)))
        var slide = String(data: package.parts["ppt/slides/slide6.xml"]!, encoding: .utf8)!
        // Drop our own timing; group the first two drawn shapes under id 77.
        if let t = slide.range(of: "<p:timing>"), let e = slide.range(of: "</p:timing>") {
            slide.removeSubrange(t.lowerBound ..< e.upperBound)
        }
        let open = "<p:grpSp><p:nvGrpSpPr><p:cNvPr id=\"77\" name=\"Pair\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"12192000\" cy=\"6858000\"/><a:chOff x=\"0\" y=\"0\"/><a:chExt cx=\"12192000\" cy=\"6858000\"/></a:xfrm></p:grpSpPr>"
        let firstSp = slide.range(of: "<p:sp>", range: slide.range(of: "</p:sp>")!.upperBound ..< slide.endIndex)!
        let afterSecond = slide.range(of: "</p:sp>", range: slide.range(of: "</p:sp>", range: firstSp.upperBound ..< slide.endIndex)!.upperBound ..< slide.endIndex)!
        slide.insert(contentsOf: "</p:grpSp>", at: afterSecond.upperBound)
        slide.insert(contentsOf: open, at: firstSp.lowerBound)
        let connector = "<p:cxnSp><p:nvCxnSpPr><p:cNvPr id=\"88\" name=\"Arrow\"/><p:cNvCxnSpPr/><p:nvPr/></p:nvCxnSpPr><p:spPr><a:xfrm rot=\"5400000\" flipH=\"1\" flipV=\"1\"><a:off x=\"1270000\" y=\"1270000\"/><a:ext cx=\"1270000\" cy=\"635000\"/></a:xfrm><a:prstGeom prst=\"curvedConnector3\"><a:avLst/></a:prstGeom><a:ln w=\"25400\"><a:solidFill><a:srgbClr val=\"1F497D\"/></a:solidFill><a:tailEnd type=\"triangle\"/></a:ln></p:spPr></p:cxnSp>"
        let timing = "<p:timing><p:tnLst><p:par><p:cTn id=\"1\" dur=\"indefinite\" restart=\"never\" nodeType=\"tmRoot\"><p:childTnLst><p:seq concurrent=\"1\" nextAc=\"seek\"><p:cTn id=\"2\" dur=\"indefinite\" nodeType=\"mainSeq\"><p:childTnLst><p:par><p:cTn id=\"3\" fill=\"hold\"><p:stCondLst><p:cond delay=\"indefinite\"/></p:stCondLst><p:childTnLst><p:par><p:cTn id=\"4\" fill=\"hold\"><p:stCondLst><p:cond delay=\"0\"/></p:stCondLst><p:childTnLst><p:par><p:cTn id=\"5\" presetID=\"1\" presetClass=\"entr\" presetSubtype=\"0\" fill=\"hold\" nodeType=\"clickEffect\"><p:stCondLst><p:cond delay=\"0\"/></p:stCondLst><p:childTnLst><p:set><p:cBhvr><p:cTn id=\"6\" dur=\"1\" fill=\"hold\"><p:stCondLst><p:cond delay=\"0\"/></p:stCondLst></p:cTn><p:tgtEl><p:spTgt spid=\"77\"/></p:tgtEl><p:attrNameLst><p:attrName>style.visibility</p:attrName></p:attrNameLst></p:cBhvr><p:to><p:strVal val=\"visible\"/></p:to></p:set></p:childTnLst></p:cTn></p:par></p:childTnLst></p:cTn></p:par></p:childTnLst></p:cTn></p:par></p:childTnLst></p:cTn><p:prevCondLst><p:cond evt=\"onPrev\" delay=\"0\"><p:tgtEl><p:sldTgt/></p:tgtEl></p:cond></p:prevCondLst><p:nextCondLst><p:cond evt=\"onNext\" delay=\"0\"><p:tgtEl><p:sldTgt/></p:tgtEl></p:cond></p:nextCondLst></p:seq></p:childTnLst></p:cTn></p:par></p:tnLst></p:timing>"
        slide = slide.replacingOccurrences(of: "</p:spTree>", with: connector + "</p:spTree>")
        slide = slide.replacingOccurrences(of: "</p:sld>", with: timing + "</p:sld>")
        package.parts["ppt/slides/slide6.xml"] = Data(slide.utf8)
        return package
    }

    private func reread(_ p: PptxPackage) throws -> (DeckState, DeckTheme, PptxPackage) {
        try Pptx.read(try Zip.write(p.parts.map { ZipEntry(name: $0.key, data: $0.value) }))
    }

    func testGroupsComeBackWithTheirIdAndAnimations() throws {
        let (state, theme, pkg) = try reread(try package())
        let members = state.slides[5].shapes.filter { $0.group != nil }
        XCTAssertEqual(members.count, 2)
        XCTAssertTrue(state.slides[5].sourceAnimations == nil && state.slides[5].timingXML != nil, "aimed at the group itself: kept as read")
        let out = String(data: PptxPackage(try Zip.read(try PptxWriter.write(state, theme: theme, package: pkg)))
            .parts["ppt/slides/slide6.xml"]!, encoding: .utf8)!
        XCTAssertTrue(out.contains("<p:grpSp><p:nvGrpSpPr><p:cNvPr id=\"77\" name=\"Pair\"/>"))
        XCTAssertTrue(out.contains("spid=\"77\""), "its animation survives")
        let (again, _, _) = try Pptx.read(try PptxWriter.write(state, theme: theme, package: pkg))
        XCTAssertEqual(again.slides[5].shapes.filter { $0.group != nil }.map(\.frame), members.map(\.frame))
    }

    func testConnectorsDrawTheirRealDirectionAndKeepTheirShape() throws {
        var (state, theme, pkg) = try reread(try package())
        let i = try XCTUnwrap(state.slides[5].shapes.firstIndex { $0.name == "Arrow" })
        let shape = state.slides[5].shapes[i]
        let f = shape.frame
        // A curve is drawn as its own path: its box (100,100 100x50) turned
        // a quarter and flipped both ways, as the file places it.
        XCTAssertEqual(f.left, 100, accuracy: 0.01)
        XCTAssertEqual(f.top, 100, accuracy: 0.01)
        XCTAssertEqual(f.right, 200, accuracy: 0.01)
        XCTAssertEqual(f.bottom, 150, accuracy: 0.01)
        XCTAssertEqual(shape.rotation, 90, accuracy: 0.01)
        XCTAssertTrue(shape.flipH && shape.flipV)
        XCTAssertNotNil(shape.customPath)
        XCTAssertEqual(shape.tailEnd?.kind, "triangle")
        func slide6(_ s: DeckState) throws -> String {
            String(data: PptxPackage(try Zip.read(try PptxWriter.write(s, theme: theme, package: pkg)))
                .parts["ppt/slides/slide6.xml"]!, encoding: .utf8)!
        }
        let kept = try slide6(state)
        XCTAssertTrue(kept.contains("prst=\"curvedConnector3\"") && kept.contains("<a:tailEnd type=\"triangle\"/>"))
        XCTAssertTrue(kept.contains("<a:off x=\"1270000\" y=\"1270000\"/><a:ext cx=\"1270000\" cy=\"635000\"/>"))
        state.slides[5].shapes[i].outline = Color(0xFFFF0000)
        let edited = try slide6(state)
        XCTAssertTrue(edited.contains("prst=\"curvedConnector3\""), "recoloured: still the curve")
        XCTAssertTrue(edited.contains("FF0000"))
    }

    /// PowerPoint's runs of numbers: a level numbers on past deeper items
    /// and starts again after an unnumbered line at its own level, each
    /// in its scheme; a save keeps the scheme.
    func testNumberedListRunsAndSchemes() throws {
        let deck = SlidesSample.make()
        var package = PptxPackage(try Zip.read(try Pptx.write(deck)))
        var slide = String(data: package.parts["ppt/slides/slide2.xml"]!, encoding: .utf8)!
        func p(_ lvl: Int, _ bu: String, _ t: String) -> String {
            "<a:p><a:pPr lvl=\"\(lvl)\">\(bu)</a:pPr><a:r><a:rPr lang=\"en-US\"/><a:t>\(t)</a:t></a:r></a:p>"
        }
        let num = "<a:buAutoNum type=\"arabicPeriod\"/>", alpha = "<a:buAutoNum type=\"alphaLcParenR\" startAt=\"3\"/>"
        let list = [p(0, num, "one"), p(0, num, "two"), p(1, alpha, "c"), p(1, alpha, "d"), p(1, "<a:buNone/>", "plain"),
                    p(1, alpha, "c again"), p(0, num, "three")].joined()
        // The body: the slide's second text body.
        let bodies = slide.components(separatedBy: "<p:txBody>")
        XCTAssertGreaterThanOrEqual(bodies.count, 3)
        let body = bodies[2]
        let lst = try XCTUnwrap(body.range(of: "</a:lstStyle>") ?? body.range(of: "<a:lstStyle/>"))
        let end = try XCTUnwrap(body.range(of: "</p:txBody>"))
        let rebuilt = String(body[..<lst.upperBound]) + list + String(body[end.lowerBound...])
        slide = bodies[0] + "<p:txBody>" + bodies[1] + "<p:txBody>" + rebuilt + bodies.dropFirst(3).map { "<p:txBody>" + $0 }.joined()
        package.parts["ppt/slides/slide2.xml"] = Data(slide.utf8)
        let (state, theme, pkg) = try Pptx.read(try Zip.write(package.parts.map { ZipEntry(name: $0.key, data: $0.value) }))
        let doc = try XCTUnwrap(state.slides[1].shapes.first { $0.phIdx == "1" }?.text)
        XCTAssertEqual(RichListNumbering.labels(doc), ["1.", "2.", "c)", "d)", nil, "c)", "3."])
        // Edited, so the body is written afresh rather than kept as read.
        var edited = state
        let i = try XCTUnwrap(edited.slides[1].shapes.firstIndex { $0.phIdx == "1" })
        edited.slides[1].shapes[i].text?.paragraphs[0].text = "uno"
        let out = String(data: PptxPackage(try Zip.read(try PptxWriter.write(edited, theme: theme, package: pkg)))
            .parts["ppt/slides/slide2.xml"]!, encoding: .utf8)!
        XCTAssertTrue(out.contains("type=\"alphaLcParenR\"") && out.contains("startAt=\"3\""),
                      out.components(separatedBy: "buAutoNum").dropFirst().map { String($0.prefix(40)) }.joined(separator: " | "))
    }

    func testFontAlgnMixedFacesGetPerRunBaselines() throws {
        let deck = SlidesSample.make()
        var package = PptxPackage(try Zip.read(try Pptx.write(deck)))
        var slide = String(data: package.parts["ppt/slides/slide2.xml"]!, encoding: .utf8)!
        func r(_ face: String, _ t: String) -> String {
            "<a:r><a:rPr lang=\"en-US\" sz=\"3500\"><a:latin typeface=\"\(face)\"/><a:ea typeface=\"\(face)\"/></a:rPr><a:t>\(t)</a:t></a:r>"
        }
        let para = "<a:p><a:pPr fontAlgn=\"t\"/>" + r("Arial", "Latin ") + r("PMingLiU", "\u{4E2D}\u{6587}") + "</a:p>"
        let bodies = slide.components(separatedBy: "<p:txBody>")
        let body = bodies[2]
        let lst = try XCTUnwrap(body.range(of: "</a:lstStyle>") ?? body.range(of: "<a:lstStyle/>"))
        let end = try XCTUnwrap(body.range(of: "</p:txBody>"))
        let rebuilt = String(body[..<lst.upperBound]) + para + String(body[end.lowerBound...])
        slide = bodies[0] + "<p:txBody>" + bodies[1] + "<p:txBody>" + rebuilt + bodies.dropFirst(3).map { "<p:txBody>" + $0 }.joined()
        package.parts["ppt/slides/slide2.xml"] = Data(slide.utf8)
        let (state, _, _) = try Pptx.read(try Zip.write(package.parts.map { ZipEntry(name: $0.key, data: $0.value) }))
        let doc = try XCTUnwrap(state.slides[1].shapes.first { $0.phIdx == "1" }?.text)
        XCTAssertTrue(doc.paragraphs[0].style.alignPerRun)
        let runs = doc.paragraphs[0].runs.filter { $0.length > 0 }
        XCTAssertEqual(runs.count, 2)
        // fontAlgn t: the glyph box's top sits at the line top, so the baseline is the face's ascent.
        XCTAssertEqual(try XCTUnwrap(runs[0].style.alignTop), 0.905, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(runs[1].style.alignTop), 0.803, accuracy: 0.001)
        XCTAssertNotEqual(runs[0].style.alignNatural, runs[1].style.alignNatural)
    }
    /// A paragraph that ends in East Asian text and has no endParaRPr: PowerPoint's end mark takes the run's own Latin face (lab num2),
    /// so that face (Palatino here) is read as the paragraph's end-mark face when it differs from the face of the last run's text.
    func testEastAsianTailWithoutEndParaRPrKeepsTheLatinFaceAsEndMark() throws {
        var package = PptxPackage(try Zip.read(try Pptx.write(SlidesSample.make())))
        var slide = String(data: package.parts["ppt/slides/slide2.xml"]!, encoding: .utf8)!
        let run = "<a:r><a:rPr lang=\"ja-JP\" sz=\"2000\"><a:latin typeface=\"Palatino Linotype\"/><a:ea typeface=\"MS PGothic\"/></a:rPr><a:t>\u{65E5}\u{672C}\u{8A9E}</a:t></a:r>"
        let bodies = slide.components(separatedBy: "<p:txBody>")
        let body = bodies[2]
        let lst = try XCTUnwrap(body.range(of: "</a:lstStyle>") ?? body.range(of: "<a:lstStyle/>"))
        let end = try XCTUnwrap(body.range(of: "</p:txBody>"))
        let rebuilt = String(body[..<lst.upperBound]) + "<a:p>" + run + "</a:p>" + String(body[end.lowerBound...])
        slide = bodies[0] + "<p:txBody>" + bodies[1] + "<p:txBody>" + rebuilt + bodies.dropFirst(3).map { "<p:txBody>" + $0 }.joined()
        package.parts["ppt/slides/slide2.xml"] = Data(slide.utf8)
        let (state, _, _) = try Pptx.read(try Zip.write(package.parts.map { ZipEntry(name: $0.key, data: $0.value) }))
        let doc = try XCTUnwrap(state.slides[1].shapes.first { $0.phIdx == "1" }?.text)
        XCTAssertNotNil(doc.paragraphs[0].style.endMarkFace)
    }
}

final class DeepGroupTests: XCTestCase {
    /// The shape reader recurses through groups with several ShapeStates in a frame: at 27 KB each a
    /// group level cost 375 KB of stack (ja-85c85cb794 overflowed 8 MB at 8 levels). Keep the value small.
    func testShapeStateStaysSmall() {
        XCTAssertLessThan(MemoryLayout<ShapeState>.size, 4096)
    }

    /// Groups nested deeper than the main thread's stack allows (the shape reader's frame is
    /// hundreds of KB a level): reading must finish, with the innermost shape kept.
    /// ja-85c85cb794 (8 deep) was Signal 11.
    func testDeeplyNestedGroupsRead() throws {
        var package = PptxPackage(try Zip.read(try Pptx.write(SlidesSample.make())))
        var slide = String(data: package.parts["ppt/slides/slide1.xml"]!, encoding: .utf8)!
        let depth = 40
        let xfrm = "<p:grpSpPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"914400\" cy=\"914400\"/><a:chOff x=\"0\" y=\"0\"/><a:chExt cx=\"914400\" cy=\"914400\"/></a:xfrm></p:grpSpPr>"
        var open = "", close = ""
        for i in 0..<depth {
            open += "<p:grpSp><p:nvGrpSpPr><p:cNvPr id=\"\(900 + i)\" name=\"G\(i)\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>\(xfrm)"
            close += "</p:grpSp>"
        }
        let leaf = "<p:sp><p:nvSpPr><p:cNvPr id=\"999\" name=\"Leaf\"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"914400\" cy=\"914400\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></p:spPr></p:sp>"
        slide = slide.replacingOccurrences(of: "</p:spTree>", with: open + leaf + close + "</p:spTree>")
        package.parts["ppt/slides/slide1.xml"] = Data(slide.utf8)
        let zipped = try Zip.write(package.parts.map { ZipEntry(name: $0.key, data: $0.value) })
        let (state, _, _) = try Pptx.read(zipped)
        XCTAssertTrue(state.slides[0].shapes.contains { $0.fileId == 999 })
    }

    func testMissingChineseFaceIsYaHeiInSimplifiedDecks() {
        XCTAssertTrue(SlideFonts.isMissingChineseName("隶书"))
        XCTAssertTrue(SlideFonts.isMissingChineseName("方正兰亭黑简体"))
        XCTAssertFalse(SlideFonts.isMissingChineseName("宋体"))
        XCTAssertFalse(SlideFonts.isMissingChineseName("微軟正黑體"))
        XCTAssertFalse(SlideFonts.isMissingChineseName("ｍｓ ｐ明朝"))
        XCTAssertFalse(SlideFonts.isMissingChineseName("Arial"))
    }

    func testLineFeedInRunTextSplitsTheParagraph() {
        let root = XNode(name: "a:txBody", attrs: [:])
        let p = XNode(name: "a:p", attrs: [:])
        let pPr = XNode(name: "a:pPr", attrs: [:])
        let r = XNode(name: "a:r", attrs: [:])
        let t = XNode(name: "a:t", attrs: [:]); t.text = "one\ntwo"
        r.children = [t]; p.children = [pPr, r]; root.children = [p]
        PptxReader.splitParagraphsAtLineFeeds(root)
        XCTAssertEqual(root.children.count, 2)
        XCTAssertEqual(root.children[1].first("a:r")?.first("a:t")?.text, "two")
        XCTAssertNotNil(root.children[1].first("a:pPr"))
    }

    /// HGS明朝E is installed on the print machine (lab num2 prints HGSMinchoE), so it is not mapped to Yu Gothic and its
    /// line stands at the 288/2048 descent share of the HG Mincho cut.
    func testHgsMinchoEIsAPrintMachineFaceNotYuGothic() {
        XCTAssertFalse(SlideFonts.isMissingJapaneseName("hgs明朝e"))
        XCTAssertEqual(SlideFonts.ownDescentShare("HGS明朝E"), 288.0 / 2048)
    }

    func testAnEquationInATableCellIsLaidOutAsAnEquation() throws {
        // A cell holding an a14:m equation used to read as flat letters ("e1");
        // it is now one inline equation image, so its subscript is set down.
        let deck = SlidesSample.make()
        var package = PptxPackage(try Zip.read(try Pptx.write(deck)))
        let part = try XCTUnwrap(package.parts.keys.first { k in
            k.hasPrefix("ppt/slides/slide") && String(data: package.parts[k]!, encoding: .utf8)!.contains("<a:tbl>")
        })
        var slide = String(data: package.parts[part]!, encoding: .utf8)!
        let math = "<a14:m xmlns:a14=\"http://schemas.microsoft.com/office/drawing/2010/main\" xmlns:m=\"http://schemas.openxmlformats.org/officeDocument/2006/math\"><m:oMath><m:sSub><m:e><m:r><m:t>e</m:t></m:r></m:e><m:sub><m:r><m:t>1</m:t></m:r></m:sub></m:sSub></m:oMath></a14:m>"
        let range = try XCTUnwrap(slide.range(of: "<a:r>", options: [], range: slide.range(of: "<a:tbl>")!.upperBound..<slide.endIndex))
        slide.insert(contentsOf: math, at: range.lowerBound)
        package.parts[part] = Data(slide.utf8)
        var entries: [ZipEntry] = []
        for (k, v) in package.parts { entries.append(ZipEntry(name: k, data: v)) }
        let (state, _, _) = try Pptx.read(try Zip.write(entries))
        let table = try XCTUnwrap(state.slides.flatMap { $0.shapes }.first { $0.kind == .table })
        let withMath = table.text?.paragraphs.filter { !$0.inlineImages.isEmpty } ?? []
        XCTAssertEqual(withMath.count, 1, "the cell's equation is an inline equation image")
    }

    /// TH SarabunPSK is not installed here: Slides gives it its own Thai advance table and draws Thai at 0.82 size (th-cb034815ae),
    /// instead of the much wider stand-in face's own widths.
    func testThSarabunPskUsesItsOwnThaiAdvances() throws {
        let f = try XCTUnwrap(SlideFonts.face("TH SarabunPSK", false))
        XCTAssertEqual(f.classScales, [1, 1, 1, 1, 0.82])
        XCTAssertFalse(try XCTUnwrap(f.otherAdvances).isEmpty)
        XCTAssertFalse(try XCTUnwrap(f.boldOtherAdvances).isEmpty)
    }

    /// S-PI-1a: a picture's alt text is set in one undoable step, saved, and the picture's recolour (kept XML) and neighbours survive.
    func testPictureAltTextRoundTripsAndKeepsTheKeptElement() throws {
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
        let deck = SlidesSample.make()
        let pic = deck.addPicture(ImageAttachment(data: png, width: 1, height: 1), naturalSize: Size(100, 100))
        deck.selectShapes([pic])
        deck.setAltText("A red square")
        XCTAssertEqual(pic.altText, "A red square")
        deck.undo()
        XCTAssertNil(deck.slides[deck.current].shapes.first { $0.picture != nil }?.altText)
        deck.selectShapes(deck.slides[deck.current].shapes.filter { $0.picture != nil })
        deck.setAltText("A \"red\" <square>")
        let (state, theme, package) = try Pptx.read(Pptx.write(deck))
        let read = try XCTUnwrap(state.slides[deck.current].shapes.first { if case .picture = $0.kind { return true }; return false })
        XCTAssertEqual(read.altText, "A \"red\" <square>")
        // Reopen with a recolour in the picture's blip (kept XML), change the alt text, save: the recolour stays and the new text is in.
        var pkg = package
        let part = try XCTUnwrap(read.sourcePart)
        var xml = String(data: try XCTUnwrap(pkg.parts[part]), encoding: .utf8)!
        let blip = try XCTUnwrap(xml.range(of: "<a:blip [^>]*?/>", options: .regularExpression))
        xml.replaceSubrange(blip, with: String(xml[blip].dropLast(2)) + "><a:lum bright=\"20000\"/></a:blip>")
        pkg.parts[part] = Data(xml.utf8)
        let (s2r, t2, p2) = try Pptx.read(try Zip.write(pkg.parts.map { ZipEntry(name: $0.key, data: $0.value) }))
        var s2 = s2r
        let ki = try XCTUnwrap(s2.slides[deck.current].shapes.firstIndex { if case .picture = $0.kind { return true }; return false })
        s2.slides[deck.current].shapes[ki].altText = "New text"
        let out = PptxPackage(try Zip.read(try PptxWriter.write(s2, theme: t2, package: p2)))
        let written = String(data: try XCTUnwrap(out.parts[part]), encoding: .utf8)!
        XCTAssertTrue(written.contains("<a:lum bright=\"20000\"/>"))
        XCTAssertTrue(written.contains("descr=\"New text\""))
        let again = try Pptx.read(PptxWriter.write(state, theme: theme, package: package))
        XCTAssertEqual(again.0.slides[deck.current].shapes.first { if case .picture = $0.kind { return true }; return false }?.altText, "A \"red\" <square>")
        XCTAssertEqual(again.0.slides[deck.current].shapes.count, state.slides[deck.current].shapes.count)
    }

    /// S-TX-2: a text box's anchor, direction, wrap, fit, margins and columns are set in one undo step and survive a save and reopen
    /// (vert and wrap were dropped on every rewrite).
    func testTextOptionsRoundTripAndUndo() throws {
        let deck = SlidesSample.make()
        let box = deck.slides[deck.current].shapes.first { $0.text != nil && $0.picture == nil }!
        let other = deck.slides[deck.current].shapes.filter { $0 !== box }.count
        deck.selectShapes([box])
        var o = try XCTUnwrap(deck.selectedTextOptions)
        let before = o
        o.anchor = .bottom
        o.direction = .rotate270
        o.wrap = false
        o.fit = .resize
        o.insets = EdgeInsets(left: 10, top: 2, right: 11, bottom: 3)
        o.columns = 2
        o.columnGap = 12
        deck.setTextOptions(o)
        XCTAssertEqual(deck.selectedTextOptions, o)
        deck.undo()
        deck.selectShapes(deck.slides[deck.current].shapes.filter { $0.id == box.id })
        XCTAssertEqual(deck.selectedTextOptions, before)
        deck.setTextOptions(o)
        let (state, _, _) = try Pptx.read(Pptx.write(deck))
        let again = DeckController(); again.restore(state)
        again.selectShapes(again.slides[again.current].shapes.filter { $0.id == box.id })
        XCTAssertEqual(again.selectedTextOptions, o)
        XCTAssertEqual(again.slides[again.current].shapes.count, other + 1)
        XCTAssertEqual(again.slides[again.current].shapes.first { $0.id == box.id }?.text?.document.paragraphs.count,
                       box.text?.document.paragraphs.count)
    }

    /// S-TB-1c: First/Last Column, Total Row and Banded Columns colour their cells, undo, keep the user's shading, and survive a save.
    func testTableStyleSwitchesColourCellsAndRoundTrip() throws {
        let deck = DeckController()
        deck.slides[0].shapes.removeAll()
        let t = deck.addTable(rows: 4, columns: 4)
        deck.selectShapes([t])
        func cell(_ r: Int, _ c: Int) -> CellRef? { t.text!.document.paragraphs.first { $0.cell?.row == r && $0.cell?.column == c }?.cell }
        func bold(_ r: Int, _ c: Int) -> Bool? { t.text!.document.paragraphs.first { $0.cell?.row == r && $0.cell?.column == c }?.runs.first?.style.bold }
        let yellow = Color(0xFFFFFF00)
        deck.setTableShading(yellow, block: CellBlock(table: t.tableId!, rows: 3...3, columns: 0...0))
        var o = deck.selectedTableOptions!
        o.firstColumn = true; o.totalRow = true; o.bandedColumns = true
        deck.setTableOptions(o)
        XCTAssertNotNil(cell(1, 0)?.fill)             // first column
        XCTAssertEqual(bold(1, 0), true)
        XCTAssertNotNil(cell(3, 2)?.fill)             // total row
        XCTAssertEqual(cell(3, 0)?.fill, yellow)      // the user's shading stays
        XCTAssertNotNil(cell(1, 1)?.fill)             // banded columns: 1 and 3 (counted after the first column)
        XCTAssertNotNil(cell(1, 3)?.fill)
        XCTAssertNil(cell(1, 2)?.fill)
        let (state, _, _) = try Pptx.read(Pptx.write(deck))
        let again = DeckController(); again.restore(state)
        again.selectShapes(again.slides[0].shapes.filter { $0.kind == .table })
        XCTAssertEqual(again.selectedTableOptions?.firstColumn, true)
        XCTAssertEqual(again.selectedTableOptions?.totalRow, true)
        XCTAssertEqual(again.selectedTableOptions?.bandedColumns, true)
        XCTAssertEqual(again.selectedTableOptions?.lastColumn, false)
        o.firstColumn = false; o.totalRow = false; o.bandedColumns = false
        deck.setTableOptions(o)
        XCTAssertNil(cell(1, 0)?.fill)
        XCTAssertNil(cell(3, 2)?.fill)
        XCTAssertEqual(cell(3, 0)?.fill, yellow)
        XCTAssertEqual(bold(1, 0), false)
        deck.undo()
        XCTAssertNotNil(cell(1, 0)?.fill)
    }

    /// S-TB-1d: a gallery style recolours the table, keeps shading and switches, undoes, and survives a save.
    func testTableGalleryStyleRecoloursAndRoundTrips() throws {
        let deck = DeckController()
        deck.slides[0].shapes.removeAll()
        let t = deck.addTable(rows: 3, columns: 2)
        deck.selectShapes([t])
        func para(_ r: Int, _ c: Int) -> RichParagraph? { t.text!.document.paragraphs.first { $0.cell?.row == r && $0.cell?.column == c } }
        let yellow = Color(0xFFFFFF00)
        deck.setTableShading(yellow, block: CellBlock(table: t.tableId!, rows: 2...2, columns: 0...0))
        let green = deck.tableLookColor(.accent(4))!
        deck.applyTableLook(.accent(4))
        XCTAssertEqual(t.text!.document.tableStyles[t.tableId!]?.headerFill, green)
        XCTAssertEqual(para(2, 0)?.cell?.fill, yellow)
        XCTAssertEqual(deck.selectedTableOptions?.headerRow, true)
        // The file names the real style (Medium Style 2 - Accent 5) and holds no fill but the user's yellow.
        func saved(_ d: DeckController) throws -> String {
            let package = PptxPackage(try Zip.read(try Pptx.write(d)))
            return String(data: package.parts["ppt/slides/slide1.xml"]!, encoding: .utf8)!
        }
        let xml = try saved(deck)
        XCTAssertTrue(xml.contains("<a:tableStyleId>{7DF18680-E054-41AD-8BC1-D1AEF772440D}</a:tableStyleId>"))
        let cellFills = xml.components(separatedBy: "<a:tcPr").dropFirst().map { String($0.components(separatedBy: "</a:tcPr>")[0]) }
            .filter { $0.contains("solidFill") }
        XCTAssertEqual(cellFills.count, 1)
        XCTAssertTrue(cellFills[0].contains(PptxText.hex(yellow)))
        let (state, _, _) = try Pptx.read(Pptx.write(deck))
        let again = DeckController(); again.restore(state)
        let t2 = again.slides[0].shapes.first { $0.kind == .table }!
        XCTAssertEqual(t2.text!.document.tableStyles[t2.tableId!]?.styleId, "{7DF18680-E054-41AD-8BC1-D1AEF772440D}")
        // Read back, the style still draws from the fifth accent, and saving again adds no fills.
        XCTAssertEqual(t2.text!.document.tableStyles[t2.tableId!]?.headerFill, green)
        let again2 = try saved(again)
        // (Edge lines the reader copies from the style are borders, not fills: cut them out first.)
        let noLines = again2.replacingOccurrences(of: "<a:ln[LRTB][^>]*>.*?</a:ln[LRTB]>", with: "", options: .regularExpression)
        XCTAssertEqual(noLines.components(separatedBy: "<a:tcPr").dropFirst().map { String($0.components(separatedBy: "</a:tcPr>")[0]) }
            .filter { $0.contains("solidFill") }.count, 1)
        deck.applyTableLook(.plain)
        let st = t.text!.document.tableStyles[t.tableId!]
        XCTAssertNil(st?.headerFill); XCTAssertNil(st?.bandFill)
        XCTAssertEqual(st?.styleId, "{5940675A-B579-460E-94D1-54222C63F5DA}")
        XCTAssertNil(para(0, 0)?.runs.first?.style.color)
        XCTAssertEqual(para(0, 0)?.runs.first?.style.bold, true)
        deck.undo()
        XCTAssertEqual(t.text!.document.tableStyles[t.tableId!]?.headerFill, green)
    }

    /// S-TB-1d: a table in a family beyond Medium Style 2 (Dark Style 1, Accent 2) is drawn from the style's definition,
    /// the file names the style and holds no fill of the style's, the user's own shading stays, undo restores.
    func testTableFamilyStyleDrawsFromTheDefinition() throws {
        let deck = DeckController()
        deck.slides[0].shapes.removeAll()
        let t = deck.addTable(rows: 3, columns: 2)
        deck.selectShapes([t])
        let yellow = Color(0xFFFFFF00)
        deck.setTableShading(yellow, block: CellBlock(table: t.tableId!, rows: 2...2, columns: 0...0))
        let dark = PptxTemplates.builtinTableStyleFamilyList.first { $0.0 == "Dark Style 1" }!.2[1]
        let before = t.text!.document.tableStyles[t.tableId!]
        deck.applyTableLook(.builtin(dark))
        let st = t.text!.document.tableStyles[t.tableId!]
        XCTAssertEqual(st?.styleId, dark)
        XCTAssertNotNil(st?.bandFill)
        XCTAssertNotEqual(st?.bandFill, before?.bandFill)
        func cell(_ r: Int, _ c: Int) -> CellRef? { t.text!.document.paragraphs.first { $0.cell?.row == r && $0.cell?.column == c }?.cell }
        XCTAssertEqual(cell(2, 0)?.fill, yellow)
        XCTAssertNotEqual(cell(2, 0)?.styleFilled, true)
        let head = t.text!.document.paragraphs.first { $0.cell?.row == 0 && $0.cell?.column == 0 }
        XCTAssertEqual(head?.runs.first?.style.bold, true)
        let package = PptxPackage(try Zip.read(try Pptx.write(deck)))
        let xml = String(data: package.parts["ppt/slides/slide1.xml"]!, encoding: .utf8)!
        XCTAssertTrue(xml.contains("<a:tableStyleId>\(dark)</a:tableStyleId>"))
        let fills = xml.components(separatedBy: "<a:tcPr").dropFirst().map { String($0.components(separatedBy: "</a:tcPr>")[0]) }
            .filter { $0.contains("solidFill") }
        XCTAssertEqual(fills.count, 1)
        deck.undo()
        XCTAssertEqual(t.text!.document.tableStyles[t.tableId!]?.styleId, before?.styleId)
    }

    /// S-TB-1d: Table Grid has no header fill, so its header text must not stay white from the old style; and Dark Style 2's
    /// first id is the Accent 1/Accent 2 pair (header in accent 2).
    func testTableGridHeaderTextAndDarkStyle2Pair() throws {
        let deck = DeckController()
        deck.slides[0].shapes.removeAll()
        let t = deck.addTable(rows: 3, columns: 2)
        deck.selectShapes([t])
        deck.applyTableLook(.builtin(DeckController.TableLook.plain.styleId))
        let head = t.text!.document.paragraphs.first { $0.cell?.row == 0 && $0.cell?.column == 0 }
        XCTAssertNotEqual(head?.runs.first?.style.color, Color(0xFFFFFFFF))
        let pair = PptxTemplates.builtinTableStyleFamilyList.first { $0.0 == "Dark Style 2" }!.2
        XCTAssertEqual(pair.count, 3)
        deck.applyTableLook(.builtin(pair[0]))
        XCTAssertEqual(t.text!.document.tableStyles[t.tableId!]?.headerFill, deck.theme.accents[1])
        let back = t.text!.document.paragraphs.first { $0.cell?.row == 0 && $0.cell?.column == 0 }
        XCTAssertEqual(back?.runs.first?.style.color, Color(0xFFFFFFFF))
    }

    /// Picking a style never moves the user's switches (header row, banded rows, first column...), through Table Grid, a family and back, and a save.
    func testStylePickKeepsTableSwitches() throws {
        let deck = DeckController()
        deck.slides[0].shapes.removeAll()
        let t = deck.addTable(rows: 3, columns: 2)
        deck.selectShapes([t])
        var o = try XCTUnwrap(deck.selectedTableOptions)
        o.bandedRows = true; o.firstColumn = true
        deck.setTableOptions(o)
        let want = deck.selectedTableOptions
        XCTAssertTrue(want?.bandedRows ?? false)
        let pair = PptxTemplates.builtinTableStyleFamilyList.first { $0.0 == "Dark Style 2" }!.2
        for look in [DeckController.TableLook.builtin(DeckController.TableLook.plain.styleId), .builtin(pair[0]), .plain, .accent(2)] {
            deck.applyTableLook(look)
            XCTAssertEqual(deck.selectedTableOptions, want)
        }
        deck.applyTableLook(.builtin(DeckController.TableLook.plain.styleId))
        let (state, _, _) = try Pptx.read(Pptx.write(deck))
        let again = DeckController(); again.restore(state)
        again.selectShapes([again.slides[0].shapes.first { $0.kind == .table }!])
        XCTAssertEqual(again.selectedTableOptions, want)
    }

    /// S-TB-1e: borders and the pen: a line on a block's outside also lands on the neighbours' matching edge, erase
    /// hides it, undo puts it back, and a save keeps colour, weight and dash.
    func testTableBordersPenRoundTripAndUndo() throws {
        let deck = DeckController()
        deck.slides[0].shapes.removeAll()
        let t = deck.addTable(rows: 3, columns: 3)
        deck.selectShapes([t])
        func cell(_ d: DeckController, _ sh: SlideShape, _ r: Int, _ c: Int) -> CellRef? { sh.text!.document.paragraphs.compactMap { $0.cell }.first { $0.row == r && $0.column == c } }
        deck.tablePen = DeckController.TablePen(width: 3, color: Color(0xFFFF0000), dash: "dash")
        let block = CellBlock(table: t.tableId!, rows: 1...1, columns: 1...1)
        deck.setTableBorders([.top, .bottom, .left, .right], line: deck.tablePen.line, block: block)
        XCTAssertEqual(cell(deck, t, 1, 1)?.borders.top?.width, 3)
        XCTAssertEqual(cell(deck, t, 0, 1)?.borders.bottom?.color, Color(0xFFFF0000))
        XCTAssertEqual(cell(deck, t, 2, 1)?.borders.top?.width, 3)
        XCTAssertEqual(cell(deck, t, 1, 0)?.borders.right?.width, 3)
        XCTAssertEqual(cell(deck, t, 1, 2)?.borders.left?.width, 3)
        XCTAssertNil(cell(deck, t, 0, 0)?.borders.right)
        let (state, _, _) = try Pptx.read(Pptx.write(deck))
        let again = DeckController(); again.restore(state)
        let t2 = again.slides[0].shapes.first { $0.kind == .table }!
        let line = cell(again, t2, 1, 1)?.borders.left
        XCTAssertEqual(line?.width, 3)
        XCTAssertEqual(line?.color, Color(0xFFFF0000))
        XCTAssertEqual(line?.dash, SlidePainter.dashPattern("dash"))
        deck.setTableBorders([.insideH], line: nil, block: CellBlock(table: t.tableId!, rows: 0...2, columns: 0...2))
        XCTAssertEqual(cell(deck, t, 1, 1)?.borders.top, CellRef.CellLine.hidden)
        XCTAssertEqual(cell(deck, t, 0, 1)?.borders.bottom, CellRef.CellLine.hidden)
        deck.undo()
        XCTAssertEqual(cell(deck, t, 1, 1)?.borders.top?.width, 3)
    }

    /// S-TB-1e: the pen and eraser find the edge under a point and lay or hide that edge on both cells.
    func testTablePenAndEraserTouchAnEdge() throws {
        let deck = DeckController()
        deck.slides[0].shapes.removeAll()
        let t = deck.addTable(rows: 3, columns: 3)
        deck.selectShapes([t])
        let doc = t.text!.document
        let layout = RichLayout(theme: RichTextTheme(fontFamily: OfficeFonts.sans), paragraphCount: doc.paragraphs.count)
        layout.width = 600
        layout.ensureLaidOut(doc)
        var found: Set<String> = []
        var y = 0.0
        while y < 400 {
            var x = 0.0
            while x < 640 {
                if let e = layout.cellEdge(at: Offset(x, y), tolerance: 2, doc) { found.insert("\(e.side)") }
                x += 1
            }
            y += 1
        }
        XCTAssertEqual(found, ["left", "right", "top", "bottom"])
        XCTAssertNil(layout.cellEdge(at: Offset(-50, -50), tolerance: 2, doc))
        func cell(_ r: Int, _ c: Int) -> CellRef? { t.text!.document.paragraphs.compactMap { $0.cell }.first { $0.row == r && $0.column == c } }
        deck.tablePen = DeckController.TablePen(width: 2.25, color: Color(0xFF0000FF), dash: "lgDash")
        deck.tableTool = .draw
        deck.penTouch(t, row: 1, column: 1, side: .right)
        XCTAssertEqual(cell(1, 1)?.borders.right?.width, 2.25)
        XCTAssertEqual(cell(1, 2)?.borders.left?.color, Color(0xFF0000FF))
        XCTAssertNil(cell(1, 1)?.borders.left)
        deck.tableTool = .erase
        deck.penTouch(t, row: 1, column: 2, side: .left)
        XCTAssertEqual(cell(1, 1)?.borders.right, CellRef.CellLine.hidden)
        deck.tableTool = .none
        deck.penTouch(t, row: 0, column: 0, side: .top)
        XCTAssertNil(cell(0, 0)?.borders.top)
    }

    /// S-TB-1f: "Reset to Table Style" drops the user's shading and border lines, so the style's look returns; one undo step.
    func testResetToTableStyleDropsOwnShadingAndBorders() throws {
        let deck = DeckController()
        deck.slides[0].shapes.removeAll()
        let t = deck.addTable(rows: 3, columns: 2)
        deck.selectShapes([t])
        deck.applyTableLook(.accent(0))
        func cell(_ r: Int, _ c: Int) -> CellRef? { t.text!.document.paragraphs.compactMap { $0.cell }.first { $0.row == r && $0.column == c } }
        let all = CellBlock(table: t.tableId!, rows: 0...2, columns: 0...1)
        deck.setTableShading(Color(0xFFFFFF00), block: all)
        deck.setTableBorders([.top, .bottom, .left, .right, .insideH, .insideV], line: CellRef.CellLine(width: 3, color: Color(0xFFFF0000), dash: nil))
        XCTAssertNotNil(cell(1, 1)?.fill)
        XCTAssertFalse(cell(1, 1)?.borders.isEmpty ?? true)
        XCTAssertNotNil(t.text!.document.tableStyles[t.tableId!]?.styleId, "styled")
        deck.resetTableToStyle(block: CellBlock(table: t.tableId!, rows: 1...1, columns: 0...1))
        XCTAssertNotEqual(cell(1, 1)?.fill, Color(0xFFFFFF00), "own yellow gone")
        XCTAssertTrue(cell(1, 1)?.borders.isEmpty ?? false)
        XCTAssertEqual(cell(0, 0)?.fill, Color(0xFFFFFF00), "cells outside the block keep their own look")
        deck.undo()
        XCTAssertNotNil(cell(1, 1)?.fill, "one undo brings it back")
        deck.selectShapes([deck.currentSlide.shapes.first { $0.kind == .table }!])
        deck.resetTableToStyle()
        XCTAssertNotEqual(cell(0, 0)?.fill, Color(0xFFFFFF00))
        XCTAssertTrue(cell(2, 1)?.borders.isEmpty ?? false)
        let (state, _, _) = try Pptx.read(Pptx.write(deck))
        let again = DeckController(); again.restore(state)
        let rt = again.slides[0].shapes.first { $0.kind == .table }
        XCTAssertNotEqual(rt?.text?.document.paragraphs.compactMap { $0.cell }.first { $0.row == 1 }?.fill, Color(0xFFFFFF00))
        // A style that came from a file: shade a cell, reset, the file's fill returns.
        let file = DeckController(); file.restore(state)
        file.selectShapes([file.currentSlide.shapes.first { $0.kind == .table }!])
        let ft = file.currentSlide.shapes.first { $0.kind == .table }!
        let before = ft.text!.document.paragraphs.compactMap { $0.cell }.first { $0.row == 0 }?.fill
        file.setTableShading(Color(0xFF00FF00), block: CellBlock(table: ft.tableId!, rows: 0...0, columns: 0...1))
        file.resetTableToStyle()
        XCTAssertEqual(ft.text!.document.paragraphs.compactMap { $0.cell }.first { $0.row == 0 }?.fill, before)
    }

    /// S-TB-1b: shading some cells of a table undoes and survives a save, other cells keep the style's.
    func testTableCellShadingRoundTripAndUndo() throws {
        let deck = DeckController()
        deck.slides[0].shapes.removeAll()
        let t = deck.addTable(rows: 3, columns: 2)
        deck.selectShapes([t])
        let yellow = Color(0xFFFFFF00)
        deck.setTableShading(yellow, block: CellBlock(table: t.tableId!, rows: 1...1, columns: 0...1))
        func fill(_ r: Int, _ c: Int) -> Color? { t.text!.document.paragraphs.first { $0.cell?.row == r && $0.cell?.column == c }?.cell?.fill }
        XCTAssertEqual(fill(1, 0), yellow)
        XCTAssertNil(fill(0, 0))
        XCTAssertNil(fill(2, 1))
        let (state, _, _) = try Pptx.read(Pptx.write(deck))
        let again = DeckController(); again.restore(state)
        let t2 = again.slides[0].shapes.first { $0.kind == .table }!
        let f2 = t2.text!.document.paragraphs.compactMap { $0.cell }.filter { $0.fill == yellow }
        XCTAssertEqual(Set(f2.map { $0.row }), [1])
        deck.undo()
        XCTAssertNil(fill(1, 0))
    }

    /// S-TB-1a: a table's header row and banded rows switch off and on, undo, and survive a save.
    func testTableOptionsRoundTripAndUndo() throws {
        let deck = DeckController()
        deck.slides[0].shapes.removeAll()
        let t = deck.addTable(rows: 3, columns: 2)
        deck.selectShapes([t])
        XCTAssertEqual(deck.selectedTableOptions, DeckController.TableOptions(headerRow: true, bandedRows: true))
        deck.setTableOptions(DeckController.TableOptions(headerRow: false, bandedRows: false))
        XCTAssertEqual(deck.selectedTableOptions, DeckController.TableOptions(headerRow: false, bandedRows: false))
        // The first row's text look follows the header: plain with it off, white bold with it on.
        func firstRunStyle() -> CharStyle? { t.text?.document.paragraphs.first?.runs.first?.style }
        XCTAssertEqual(firstRunStyle()?.bold, false)
        XCTAssertNil(firstRunStyle()?.color)
        deck.setTableOptions(DeckController.TableOptions(headerRow: true, bandedRows: false))
        XCTAssertEqual(firstRunStyle()?.bold, true)
        XCTAssertEqual(firstRunStyle()?.color, Color(0xFFFFFFFF))
        deck.setTableOptions(DeckController.TableOptions(headerRow: false, bandedRows: false))
        let (state, _, _) = try Pptx.read(Pptx.write(deck))
        let again = DeckController(); again.restore(state)
        again.selectShapes(again.slides[0].shapes.filter { $0.kind == .table })
        XCTAssertEqual(again.selectedTableOptions, DeckController.TableOptions(headerRow: false, bandedRows: false))
        deck.undo(); deck.undo(); deck.undo()
        deck.selectShapes(deck.slides[0].shapes.filter { $0.kind == .table })
        XCTAssertEqual(deck.selectedTableOptions, DeckController.TableOptions(headerRow: true, bandedRows: true))
        XCTAssertEqual(firstRunStyle()?.color, Color(0xFFFFFFFF))
    }
}
