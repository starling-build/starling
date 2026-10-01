import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

final class PptxTests: XCTestCase {
    private func roundTrip(_ deck: DeckController) throws -> (DeckState, DeckTheme, PptxPackage) {
        try Pptx.read(Pptx.write(deck))
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
        XCTAssertEqual(layoutIdx, ["1", "2"])
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
