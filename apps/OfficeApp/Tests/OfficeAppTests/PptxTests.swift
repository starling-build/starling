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
        let deck = SlidesSample.make()
        var package = PptxPackage(try Zip.read(try Pptx.write(deck)))
        var slide = String(data: package.parts["ppt/slides/slide2.xml"]!, encoding: .utf8)!
        let firstId = slide.components(separatedBy: "<p:cNvPr id=\"")[2].prefix { $0.isNumber }
        let timing = "<p:timing><p:tnLst><p:par><p:cTn id=\"1\" dur=\"indefinite\" nodeType=\"tmRoot\"><p:childTnLst><p:par><p:cTn id=\"2\"><p:stCondLst><p:cond delay=\"0\"/></p:stCondLst><p:childTnLst><p:set><p:cBhvr><p:cTn id=\"3\" dur=\"1\"/><p:tgtEl><p:spTgt spid=\"\(firstId)\"/></p:tgtEl></p:cBhvr><p:to><p:strVal val=\"visible\"/></p:to></p:set></p:childTnLst></p:cTn></p:par></p:childTnLst></p:cTn></p:par></p:tnLst></p:timing>"
        slide = slide.replacingOccurrences(of: "</p:sld>", with: timing + "</p:sld>")
        package.parts["ppt/slides/slide2.xml"] = Data(slide.utf8)
        let zipped = try Zip.write(package.parts.map { ZipEntry(name: $0.key, data: $0.value) })
        let (state, theme, pkg) = try Pptx.read(zipped)
        XCTAssertNotNil(state.slides[1].timingXML)

        let kept = String(data: PptxPackage(try Zip.read(try PptxWriter.write(state, theme: theme, package: pkg)))
            .parts["ppt/slides/slide2.xml"]!, encoding: .utf8)!
        XCTAssertTrue(kept.contains("spid=\"\(firstId)\""), "animations kept while their shape is")

        var gone = state
        gone.slides[1].shapes.removeAll { $0.fileId == Int(firstId) }
        let dropped = String(data: PptxPackage(try Zip.read(try PptxWriter.write(gone, theme: theme, package: pkg)))
            .parts["ppt/slides/slide2.xml"]!, encoding: .utf8)!
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
        XCTAssertTrue(edited.contains(ours) && !edited.contains(theirs), "edited: our table")
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
