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
        let part = "ppt/slides/slide2.xml"
        var slide = String(data: package.parts[part]!, encoding: .utf8)!
        slide = slide.replacingOccurrences(of: "</p:spTree>", with: sp + "</p:spTree>")
        package.parts[part] = Data(slide.utf8)
        var rels = String(data: package.parts["ppt/slides/_rels/slide2.xml.rels"]!, encoding: .utf8)!
        rels = rels.replacingOccurrences(of: "</Relationships>",
            with: "<Relationship Id=\"rId10\" Type=\"\(rel)hyperlink\" Target=\"https://example.com/a\" TargetMode=\"External\"/>"
            + "<Relationship Id=\"rId11\" Type=\"\(rel)hyperlink\" Target=\"mailto:a@example.com\" TargetMode=\"External\"/>"
            + "<Relationship Id=\"rId12\" Type=\"\(rel)slide\" Target=\"slide1.xml\"/>"
            + "<Relationship Id=\"rId13\" Type=\"\(rel)hyperlink\" Target=\"https://example.com/click\" TargetMode=\"External\"/></Relationships>")
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
        for target in ["https://example.com/a", "mailto:a@example.com", "https://example.com/click"] {
            XCTAssertTrue(rels.contains(target), "\(target) after \(why)", file: file, line: line)
        }
        XCTAssertTrue(xml.contains("hlinksldjump"), "the slide link keeps its action after \(why)", file: file, line: line)
        XCTAssertTrue(xml.contains("click tip") && xml.contains("web tip"), "tips after \(why)", file: file, line: line)
        // Every r:id the shape uses is a relationship of the part.
        for id in xml.components(separatedBy: "r:id=\"").dropFirst().map({ String($0.prefix { $0 != "\"" }) }) {
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
}
