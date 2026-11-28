import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

/// Hyperlinks must survive a save: text links (web, slide, mail) and a shape's
/// click action, with their relationships, whatever else was edited.
final class PptxLinkTests: XCTestCase {
    private let rel = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/"

    /// A deck whose slide 2 has one shape with three linked runs and a click action.
    private func deckWithLinks() throws -> (DeckState, DeckTheme, PptxPackage) {
        let deck = SlidesSample.make()
        var package = PptxPackage(try Zip.read(try Pptx.write(deck)))
        let run = { (id: String, extra: String, text: String) in
            "<a:r><a:rPr lang=\"en-US\"><a:hlinkClick r:id=\"\(id)\"\(extra)/></a:rPr><a:t>\(text)</a:t></a:r>" }
        let sp = "<p:sp><p:nvSpPr><p:cNvPr id=\"91\" name=\"Linked\"><a:hlinkClick r:id=\"rId13\" tooltip=\"click tip\"/></p:cNvPr><p:cNvSpPr/><p:nvPr/></p:nvSpPr>"
            + "<p:spPr><a:xfrm><a:off x=\"1270000\" y=\"1270000\"/><a:ext cx=\"5080000\" cy=\"1270000\"/></a:xfrm>"
            + "<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom><a:solidFill><a:srgbClr val=\"336699\"/></a:solidFill></p:spPr>"
            + "<p:txBody><a:bodyPr/><a:lstStyle/><a:p>"
            + run("rId10", " tooltip=\"web tip\"", "web") + run("rId11", "", "mail")
            + run("rId12", " action=\"ppaction://hlinksldjump\"", "slide")
            + "</a:p></p:txBody></p:sp>"
            // Mouse-over actions: on the shape (a web page) and on a run (next slide, no relationship).
            + "<p:sp><p:nvSpPr><p:cNvPr id=\"92\" name=\"Hover\"><a:hlinkMouseOver r:id=\"rId14\" tooltip=\"hover tip\"/></p:cNvPr><p:cNvSpPr/><p:nvPr/></p:nvSpPr>"
            + "<p:spPr><a:xfrm><a:off x=\"1270000\" y=\"3270000\"/><a:ext cx=\"5080000\" cy=\"1270000\"/></a:xfrm>"
            + "<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></p:spPr>"
            + "<p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:rPr lang=\"en-US\"><a:hlinkMouseOver r:id=\"\" action=\"ppaction://hlinkshowjump?jump=nextslide\"/></a:rPr>"
            + "<a:t>over</a:t></a:r></a:p></p:txBody></p:sp>"
        let part = "ppt/slides/slide2.xml"
        var slide = String(data: package.parts[part]!, encoding: .utf8)!
        slide = slide.replacingOccurrences(of: "</p:spTree>", with: sp + "</p:spTree>")
        package.parts[part] = Data(slide.utf8)
        var rels = String(data: package.parts["ppt/slides/_rels/slide2.xml.rels"]!, encoding: .utf8)!
        rels = rels.replacingOccurrences(of: "</Relationships>",
            with: "<Relationship Id=\"rId10\" Type=\"\(rel)hyperlink\" Target=\"https://example.com/a\" TargetMode=\"External\"/>"
            + "<Relationship Id=\"rId11\" Type=\"\(rel)hyperlink\" Target=\"mailto:a@example.com\" TargetMode=\"External\"/>"
            + "<Relationship Id=\"rId12\" Type=\"\(rel)slide\" Target=\"slide1.xml\"/>"
            + "<Relationship Id=\"rId13\" Type=\"\(rel)hyperlink\" Target=\"https://example.com/click\" TargetMode=\"External\"/>"
            + "<Relationship Id=\"rId14\" Type=\"\(rel)hyperlink\" Target=\"https://example.com/hover\" TargetMode=\"External\"/></Relationships>")
        package.parts["ppt/slides/_rels/slide2.xml.rels"] = Data(rels.utf8)
        var entries: [ZipEntry] = []
        for (k, v) in package.parts { entries.append(ZipEntry(name: k, data: v)) }
        return try Pptx.read(try Zip.write(entries))
    }

    /// Writes, then checks every link is there and points where it did.
    private func assertLinksSurvive(_ state: DeckState, _ theme: DeckTheme, _ pkg: PptxPackage,
                                    _ why: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let out = PptxPackage(try Zip.read(try PptxWriter.write(state, theme: theme, package: pkg)))
        let part = try XCTUnwrap(out.parts.keys.first { k in
            k.hasPrefix("ppt/slides/slide") && !k.contains("_rels") && String(data: out.parts[k]!, encoding: .utf8)!.contains("name=\"Linked\"")
        }, "the shape is written (\(why))", file: file, line: line)
        let xml = String(data: out.parts[part]!, encoding: .utf8)!
        let rels = String(data: out.parts[part.replacingOccurrences(of: "slides/", with: "slides/_rels/") + ".rels"]!, encoding: .utf8)!
        XCTAssertEqual(xml.components(separatedBy: "<a:hlinkClick").count - 1, 4, "four links after \(why)", file: file, line: line)
        XCTAssertEqual(xml.components(separatedBy: "<a:hlinkMouseOver").count - 1, 2, "two mouse-over actions after \(why)", file: file, line: line)
        XCTAssertTrue(xml.contains("jump=nextslide") && xml.contains("hover tip"), "mouse-over targets after \(why)", file: file, line: line)
        for target in ["https://example.com/a", "mailto:a@example.com", "https://example.com/click", "https://example.com/hover"] {
            XCTAssertTrue(rels.contains(target), "\(target) after \(why)", file: file, line: line)
        }
        XCTAssertTrue(xml.contains("hlinksldjump"), "the slide link keeps its action after \(why)", file: file, line: line)
        XCTAssertTrue(xml.contains("click tip") && xml.contains("web tip"), "tips after \(why)", file: file, line: line)
        // Every r:id the shape uses is a relationship of the part.
        for id in xml.components(separatedBy: "r:id=\"").dropFirst().map({ String($0.prefix { $0 != "\"" }) }) where !id.isEmpty {
            XCTAssertTrue(rels.contains("Id=\"\(id)\""), "\(id) has its relationship after \(why)", file: file, line: line)
        }
    }

    private func linked(_ state: DeckState) throws -> (Int, Int) {
        let si = try XCTUnwrap(state.slides.firstIndex { $0.shapes.contains { $0.name == "Linked" } })
        return (si, try XCTUnwrap(state.slides[si].shapes.firstIndex { $0.name == "Linked" }))
    }

    func testLinksSurviveASaveWithNoEdit() throws {
        let (state, theme, pkg) = try deckWithLinks()
        try assertLinksSurvive(state, theme, pkg, "no edit")
    }

    func testLinksSurviveMovingTheShape() throws {
        var (state, theme, pkg) = try deckWithLinks()
        let (si, i) = try linked(state)
        state.slides[si].shapes[i].frame = Rect.fromLTWH(200, 150, 300, 80)
        try assertLinksSurvive(state, theme, pkg, "a move")
    }

    func testLinksSurviveChangingTheShapesFill() throws {
        var (state, theme, pkg) = try deckWithLinks()
        let (si, i) = try linked(state)
        state.slides[si].shapes[i].fill = Color(0xFFAA0000)
        try assertLinksSurvive(state, theme, pkg, "a fill change")
    }

    func testLinksSurviveEditingAnotherShape() throws {
        var (state, theme, pkg) = try deckWithLinks()
        let (si, i) = try linked(state)
        let other = try XCTUnwrap(state.slides[si].shapes.indices.first { $0 != i })
        state.slides[si].shapes[other].frame = Rect.fromLTWH(20, 20, 100, 50)
        try assertLinksSurvive(state, theme, pkg, "an edit elsewhere")
    }

    private func shape(_ state: DeckState, _ name: String) throws -> (Int, Int) {
        let si = try XCTUnwrap(state.slides.firstIndex { $0.shapes.contains { $0.name == name } })
        return (si, try XCTUnwrap(state.slides[si].shapes.firstIndex { $0.name == name }))
    }

    /// Typing inside a linked run keeps the link on the longer text (PowerPoint: the link grows).
    func testTypingInsideALinkedRunKeepsTheLink() throws {
        var (state, theme, pkg) = try deckWithLinks()
        let (si, i) = try linked(state)
        var doc = try XCTUnwrap(state.slides[si].shapes[i].text)
        doc.paragraphs[0].insert("X", at: 1)
        state.slides[si].shapes[i].text = doc
        try assertLinksSurvive(state, theme, pkg, "typing in a linked run")
    }

    func testBoldOnALinkedRunKeepsTheLink() throws {
        var (state, theme, pkg) = try deckWithLinks()
        let (si, i) = try linked(state)
        var doc = try XCTUnwrap(state.slides[si].shapes[i].text)
        doc.paragraphs[0].applyStyle(0 ..< 3) { $0.bold = true }
        state.slides[si].shapes[i].text = doc
        try assertLinksSurvive(state, theme, pkg, "bold on a linked run")
    }

    func testMouseOverSurvivesEditingThatShape() throws {
        var (state, theme, pkg) = try deckWithLinks()
        let (si, i) = try shape(state, "Hover")
        state.slides[si].shapes[i].fill = Color(0xFF00AA00)
        var doc = try XCTUnwrap(state.slides[si].shapes[i].text)
        doc.paragraphs[0].insert("Y", at: 2)
        state.slides[si].shapes[i].text = doc
        try assertLinksSurvive(state, theme, pkg, "a fill and text edit of the mouse-over shape")
    }

    /// A duplicated slide carries the links too, each copy with its own relationships.
    func testDuplicatedSlideKeepsItsLinks() throws {
        let (state, theme, pkg) = try deckWithLinks()
        let deck = DeckController()
        deck.load(state, theme: theme, package: pkg)
        let (si, _) = try linked(state)
        deck.duplicateSlide(si)
        let out = PptxPackage(try Zip.read(try PptxWriter.write(deck.snapshot(), theme: theme, package: pkg)))
        for n in [si + 1, si + 2] {
            let xml = String(data: try XCTUnwrap(out.parts["ppt/slides/slide\(n).xml"]), encoding: .utf8)!
            let rels = String(data: try XCTUnwrap(out.parts["ppt/slides/_rels/slide\(n).xml.rels"]), encoding: .utf8)!
            XCTAssertEqual(xml.components(separatedBy: "<a:hlinkClick").count - 1, 4, "slide \(n)")
            XCTAssertEqual(xml.components(separatedBy: "<a:hlinkMouseOver").count - 1, 2, "slide \(n)")
            for id in xml.components(separatedBy: "r:id=\"").dropFirst().map({ String($0.prefix { $0 != "\"" }) }) where !id.isEmpty {
                XCTAssertTrue(rels.contains("Id=\"\(id)\""), "\(id) on slide \(n)")
            }
            XCTAssertTrue(rels.contains("https://example.com/hover"), "slide \(n)")
        }
    }

    private func save(_ state: DeckState, _ theme: DeckTheme, _ pkg: PptxPackage, slide n: Int) throws -> (xml: String, rels: String) {
        let out = PptxPackage(try Zip.read(try PptxWriter.write(state, theme: theme, package: pkg)))
        return (String(data: try XCTUnwrap(out.parts["ppt/slides/slide\(n).xml"]), encoding: .utf8)!,
                String(data: try XCTUnwrap(out.parts["ppt/slides/_rels/slide\(n).xml.rels"]), encoding: .utf8)!)
    }

    /// Ctrl+K on a word of a read shape: the link goes into that run's own XML, and the rest of the shape stays as read.
    func testLinkMadeOnReadTextIsPatchedIntoTheRun() throws {
        var (state, theme, pkg) = try deckWithLinks()
        let (si, i) = try shape(state, "Hover")
        var doc = try XCTUnwrap(state.slides[si].shapes[i].text)
        doc.paragraphs[0].applyStyle(0 ..< 4) { $0.link = "https://example.com/new"; $0.linkTip = "new tip" }
        state.slides[si].shapes[i].text = doc
        let (xml, rels) = try save(state, theme, pkg, slide: si + 1)
        XCTAssertTrue(rels.contains("https://example.com/new"), rels)
        let id = try XCTUnwrap(xml.components(separatedBy: "<a:hlinkClick r:id=\"").dropFirst().map { String($0.prefix { $0 != "\"" }) }
            .first { rels.contains("Id=\"\($0)\" Type=\"\(rel)hyperlink\" Target=\"https://example.com/new\"") })
        // The run keeps its mouse-over, after the new click action (the schema's order).
        XCTAssertTrue(xml.contains("<a:hlinkClick r:id=\"\(id)\" tooltip=\"new tip\"/><a:hlinkMouseOver "), xml)
        XCTAssertEqual(xml.components(separatedBy: "<a:hlinkClick").count - 1, 5, xml)
        XCTAssertEqual(xml.components(separatedBy: "jump=nextslide").count - 1, 1, xml)
    }

    func testRemovingALinkFromReadTextLeavesTheOthers() throws {
        var (state, theme, pkg) = try deckWithLinks()
        let (si, i) = try linked(state)
        var doc = try XCTUnwrap(state.slides[si].shapes[i].text)
        doc.paragraphs[0].applyStyle(3 ..< 7) { $0.link = nil; $0.linkTip = nil }   // "mail"
        state.slides[si].shapes[i].text = doc
        let (xml, _) = try save(state, theme, pkg, slide: si + 1)
        XCTAssertEqual(xml.components(separatedBy: "<a:hlinkClick").count - 1, 3, xml)
        XCTAssertTrue(xml.contains("web tip") && xml.contains("hlinksldjump") && xml.contains("click tip"), xml)
    }

    /// A shape made here with both actions writes them in the schema's order, each with its relationship.
    func testNewShapeWritesClickAndMouseOver() throws {
        let (state0, theme, pkg) = try deckWithLinks()
        let deck = DeckController()
        deck.load(state0, theme: theme, package: pkg)
        deck.current = 0
        let made = deck.addTextBox(text: "made")
        made.name = "Made"
        deck.selection = [made]
        deck.setShapeLink("slide:" + (state0.slides[0].sourcePart ?? ""), tip: nil)
        made.hoverLink = "https://example.com/made"; made.hoverLinkTip = "made tip"
        let state = deck.snapshot()
        XCTAssertEqual(state.slides.firstIndex { $0.shapes.contains { $0.name == "Made" } }, 0, "\(state.slides.map { $0.shapes.map(\.name) })")
        let (xml, rels) = try save(state, theme, pkg, slide: 1)
        XCTAssertTrue(rels.contains("https://example.com/made"), rels)
        XCTAssertTrue(xml.range(of: "name=\"Made\"><a:hlinkClick r:id=\"rIdL") != nil, xml)
        XCTAssertTrue(xml.contains("action=\"ppaction://hlinksldjump\"/><a:hlinkMouseOver r:id=\"rIdL"), xml)
        XCTAssertTrue(xml.contains("tooltip=\"made tip\"/></p:cNvPr>"), xml)
    }

    /// Slide 2 keeps (as read) a link to slide 1: saving must not copy slide 1 as read over the slide 1 just written, so a
    /// new box there is kept; the link goes to slide 1 wherever it now is, and goes with it when slide 1 is deleted.
    func testKeptLinkToAnEditedSlideKeepsTheEdit() throws {
        var (state, theme, pkg) = try deckWithLinks()
        var box = state.slides[0].shapes[0]
        box.id = 9_001; box.sourceXML = nil; box.readShape = nil; box.fileId = nil; box.name = "Added"; box.kind = .textBox
        state.slides[0].shapes.append(box)
        let (xml1, _) = try save(state, theme, pkg, slide: 1)
        XCTAssertTrue(xml1.contains("name=\"Added\""), xml1)
        let (_, rels2) = try save(state, theme, pkg, slide: 2)
        XCTAssertTrue(rels2.contains("Target=\"slide1.xml\""), rels2)
        // Slide 1 moved to the end: the link follows it.
        state.slides.append(state.slides.removeFirst())
        let last = state.slides.count
        let (moved, _) = try save(state, theme, pkg, slide: last)
        XCTAssertTrue(moved.contains("name=\"Added\""), moved)
        let (_, rels1) = try save(state, theme, pkg, slide: 1)
        XCTAssertTrue(rels1.contains("Target=\"slide\(last).xml\""), rels1)
        // Slide 1 deleted: no jump to a slide that is gone.
        state.slides.removeLast()
        let (xml, rels) = try save(state, theme, pkg, slide: 1)
        XCTAssertFalse(rels.contains("relationships/slide\""), rels)
        XCTAssertFalse(xml.contains("hlinksldjump"), xml)
        XCTAssertTrue(xml.contains("https://example.com") || rels.contains("https://example.com"), rels)
    }

    /// The model reads a mouse-over action on a shape and on a run.
    func testMouseOverIsRead() throws {
        let (state, _, _) = try deckWithLinks()
        let (si, i) = try shape(state, "Hover")
        let s = state.slides[si].shapes[i]
        XCTAssertEqual(s.hoverLink, "https://example.com/hover")
        XCTAssertEqual(s.hoverLinkTip, "hover tip")
        XCTAssertEqual(s.text?.paragraphs[0].style(at: 0).hoverLink, "action:ppaction://hlinkshowjump?jump=nextslide")
    }
}
