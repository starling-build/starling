import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

/// Not a pass/fail test: with STARLING_SWEEP_DIR set, changes one shape's fill per slide in every deck of that folder, saves, and
/// counts (by name) the elements and attributes the shape's original XML had that the saved one lacks.
final class PptxSweepTests: XCTestCase {
    private func names(_ n: XNode, _ out: inout Set<String>) {
        out.insert(n.name)
        for (k, _) in n.attrs { out.insert(n.name + "@" + k) }
        for c in n.children { names(c, &out) }
    }
    /// The saved element to compare with a shape's source: when the source is an mc:AlternateContent
    /// (a chartex frame with its picture fallback), the whole wrapper, not just the frame inside it.
    private func shapeEl(_ n: XNode, id: String, wrapped: Bool = false) -> XNode? {
        if wrapped, n.name == "mc:AlternateContent", shapeEl(n, id: id) != nil { return n }
        if ["p:sp", "p:pic", "p:cxnSp", "p:graphicFrame"].contains(n.name), n.descendant("p:cNvPr")?["id"] == id { return n }
        for c in n.children { if let f = shapeEl(c, id: id, wrapped: wrapped) { return f } }
        return nil
    }

    func testSweep() throws {
        guard let dir = ProcessInfo.processInfo.environment["STARLING_SWEEP_DIR"] else { throw XCTSkip("no STARLING_SWEEP_DIR") }
        let plain = ProcessInfo.processInfo.environment["STARLING_SWEEP_PLAIN"] != nil
        let files = try FileManager.default.contentsOfDirectory(atPath: dir).filter { $0.hasSuffix(".pptx") }.sorted()
        var missing: [String: Int] = [:], decks: [String: Set<String>] = [:]
        var why: [String: Int] = [:]
        var shapes = 0, failed = 0, noRead = 0, field = 0, notPatchable = 0
        for f in files {
            guard let data = FileManager.default.contents(atPath: dir + "/" + f),
                  let (state0, theme, pkg) = try? Pptx.read(data) else { failed += 1; why["FAILREAD " + f, default: 0] += 1; continue }
            var state = state0
            var changed: [(Int, ShapeState)] = []
            for si in state.slides.indices {
                let pick: (ShapeState) -> Bool = { sh in
                    if sh.sourceXML == nil || sh.fileId == nil || sh.sourcePart == nil { return false }
                    if sh.keptPicture != nil || sh.text == nil { return false }
                    let k = String(describing: sh.kind).lowercased()
                    return !k.contains("line") && !k.contains("table")
                }
                if plain {
                    for sh in state.slides[si].shapes where sh.sourceXML != nil && sh.fileId != nil && sh.sourcePart != nil { changed.append((si, sh)) }
                    continue
                }
                guard let i = state.slides[si].shapes.firstIndex(where: pick) else { continue }
                state.slides[si].shapes[i].fill = Color(0xFFAA0000)
                changed.append((si, state.slides[si].shapes[i]))
            }
            guard let out = try? PptxWriter.write(state, theme: theme, package: pkg),
                  let saved = try? PptxPackage(Zip.read(out)) else { failed += 1; why["FAILWRITE " + f, default: 0] += 1; continue }
            for (si, s) in changed {
                guard let orig = XNode.parse(Data(s.sourceXML!.utf8)),
                      let sx = saved.parts["ppt/slides/slide\(si + 1).xml"].flatMap({ XNode.parse($0) }),
                      let now = shapeEl(sx, id: "\(s.fileId!)", wrapped: orig.name == "mc:AlternateContent") else { continue }
                shapes += 1
                if s.readShape == nil { noRead += 1; why[String(String(describing: s.kind).prefix(24)) + (s.customPath != nil ? " custom" : "") + (s.sourceXML!.contains("<p:sp>") ? " sp" : " other"), default: 0] += 1 } else if s.field != nil { field += 1 } else if !s.readShape!.patchable(s) { notPatchable += 1 }
                var a = Set<String>(), b = Set<String>()
                // (The fill the sweep itself replaced is not a loss.)
                if !plain { orig.first("p:spPr")?.children.removeAll { ["a:noFill", "a:solidFill", "a:gradFill", "a:blipFill", "a:pattFill", "a:grpFill"].contains($0.name) } }
                names(orig, &a); names(now, &b)
                for n in a.subtracting(b) { missing[n, default: 0] += 1; decks[n, default: []].insert(f) }
                if !a.subtracting(b).isEmpty, let dump = ProcessInfo.processInfo.environment["STARLING_SWEEP_DUMP"] {
                    try? (s.sourceXML! + "\n=====\n" + String(decoding: saved.parts["ppt/slides/slide\(si + 1).xml"]!, as: UTF8.self)).write(toFile: "\(dump)/\(f)-s\(si + 1)-\(s.fileId!).txt", atomically: true, encoding: .utf8)
                }
            }
        }
        var lines = ["decks \(files.count) unreadable-or-failed \(failed) shapes changed \(shapes) (no readShape \(noRead), field \(field), not patchable \(notPatchable))"]
        for (k, v) in why { lines.append("NOREAD \(v) \(k)") }
        for (n, c) in missing.sorted(by: { $0.value > $1.value }) { lines.append("\(c)\t\(decks[n]!.count) decks\t\(n)\t\(decks[n]!.sorted().prefix(3).joined(separator: " "))") }
        try lines.joined(separator: "\n").write(toFile: ProcessInfo.processInfo.environment["STARLING_SWEEP_OUT"] ?? "/data/s/amd-9/sweep/result.txt", atomically: true, encoding: .utf8)
    }

    /// Changing a shape's fill, line or text box keeps what the model does not hold: theme colours, East Asian faces, adjust handles, effects, paragraph settings.
    func testEditingOneThingKeepsTheRest() throws {
        let deck = SlidesSample.make()
        var package = PptxPackage(try Zip.read(try Pptx.write(deck)))
        let sp = "<p:sp><p:nvSpPr><p:cNvPr id=\"91\" name=\"Rich\"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>"
            + "<p:spPr><a:xfrm><a:off x=\"1270000\" y=\"1270000\"/><a:ext cx=\"5080000\" cy=\"1270000\"/></a:xfrm>"
            + "<a:prstGeom prst=\"roundRect\"><a:avLst><a:gd name=\"adj\" fmla=\"val 33333\"/></a:avLst></a:prstGeom>"
            + "<a:solidFill><a:srgbClr val=\"336699\"/></a:solidFill><a:effectLst><a:outerShdw blurRad=\"50800\"/></a:effectLst></p:spPr>"
            + "<p:txBody><a:bodyPr/><a:lstStyle><a:lvl1pPr marL=\"0\" defTabSz=\"914400\"><a:defRPr sz=\"2000\"/></a:lvl1pPr></a:lstStyle>"
            + "<a:p><a:pPr eaLnBrk=\"0\" hangingPunct=\"0\"><a:tabLst><a:tab pos=\"100\" algn=\"l\"/></a:tabLst></a:pPr>"
            + "<a:r><a:rPr lang=\"ja-JP\"><a:solidFill><a:schemeClr val=\"accent2\"><a:lumMod val=\"75000\"/></a:schemeClr></a:solidFill>"
            + "<a:latin typeface=\"Arial\" charset=\"0\"/><a:ea typeface=\"MS Gothic\"/></a:rPr><a:t>hello</a:t></a:r></a:p></p:txBody></p:sp>"
        let part = "ppt/slides/slide2.xml"
        var slide = String(data: package.parts[part]!, encoding: .utf8)!
        slide = slide.replacingOccurrences(of: "</p:spTree>", with: sp + "</p:spTree>")
        package.parts[part] = Data(slide.utf8)
        var entries: [ZipEntry] = []
        for (k, v) in package.parts { entries.append(ZipEntry(name: k, data: v)) }
        var (state, theme, pkg) = try Pptx.read(try Zip.write(entries))
        let si = try XCTUnwrap(state.slides.firstIndex { $0.shapes.contains { $0.name == "Rich" } })
        let i = try XCTUnwrap(state.slides[si].shapes.firstIndex { $0.name == "Rich" })
        state.slides[si].shapes[i].fill = Color(0xFFAA0000)
        state.slides[si].shapes[i].outline = Color(0xFF00AA00)
        state.slides[si].shapes[i].outlineWidth = 3
        state.slides[si].shapes[i].anchor = .bottom
        let out = PptxPackage(try Zip.read(try PptxWriter.write(state, theme: theme, package: pkg)))
        let xml = try XCTUnwrap(out.parts.keys.filter { $0.hasPrefix("ppt/slides/slide") && !$0.contains("_rels") }
            .compactMap { String(data: out.parts[$0]!, encoding: .utf8) }.first { $0.contains("name=\"Rich\"") })
        for kept in ["val 33333", "outerShdw", "accent2", "lumMod", "MS Gothic", "eaLnBrk", "hangingPunct", "a:tabLst", "defTabSz", "charset", "ja-JP"] {
            XCTAssertTrue(xml.contains(kept), "\(kept) survives")
        }
        XCTAssertTrue(xml.contains("AA0000") && xml.contains("00AA00") && xml.contains("anchor=\"b\""), "the edit itself is written")
        XCTAssertFalse(xml.contains("336699"), "the old fill is replaced")
    }

    /// A link to a bookmark in the same file (`#_ftn1`) keeps its target when the shape is edited.
    func testBookmarkLinksKeepTheirTarget() throws {
        let path = "/data/corpus-cache/test/corpus/pptx/decks/with_japanese.pptx"
        guard let data = FileManager.default.contents(atPath: path) else { throw XCTSkip("corpus deck not restored") }
        var (state, theme, pkg) = try Pptx.read(data)
        for si in state.slides.indices { for hi in state.slides[si].shapes.indices where state.slides[si].shapes[hi].sourceXML != nil {
            state.slides[si].shapes[hi].fill = Color(0xFFAA0000)
        } }
        let after = PptxPackage(try Zip.read(try PptxWriter.write(state, theme: theme, package: pkg)))
        let slide = String(data: after.parts["ppt/slides/slide1.xml"]!, encoding: .utf8)!
        XCTAssertFalse(slide.contains("<a:hlinkClick/>"), "a link lost its target")
        let rels = String(data: after.parts["ppt/slides/_rels/slide1.xml.rels"]!, encoding: .utf8)!
        XCTAssertTrue(rels.contains("#_ftn1") && rels.contains("#_ftnref1"), rels)
    }

    /// Making part of a run bold and red changes only that part's own properties: the run splits, the East Asian face, theme colour of the rest and paragraph settings stay.
    func testBoldAndColourEditKeepFacesAndSplitTheRun() throws {
        let deck = SlidesSample.make()
        var package = PptxPackage(try Zip.read(try Pptx.write(deck)))
        let sp = "<p:sp><p:nvSpPr><p:cNvPr id=\"91\" name=\"Rich\"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>"
            + "<p:spPr><a:xfrm><a:off x=\"1270000\" y=\"1270000\"/><a:ext cx=\"5080000\" cy=\"1270000\"/></a:xfrm>"
            + "<a:prstGeom prst=\"roundRect\"><a:avLst><a:gd name=\"adj\" fmla=\"val 33333\"/></a:avLst></a:prstGeom>"
            + "<a:solidFill><a:srgbClr val=\"336699\"/></a:solidFill><a:effectLst><a:outerShdw blurRad=\"50800\"/></a:effectLst></p:spPr>"
            + "<p:txBody><a:bodyPr/><a:lstStyle><a:lvl1pPr marL=\"0\" defTabSz=\"914400\"><a:defRPr sz=\"2000\"/></a:lvl1pPr></a:lstStyle>"
            + "<a:p><a:pPr eaLnBrk=\"0\" hangingPunct=\"0\"><a:tabLst><a:tab pos=\"100\" algn=\"l\"/></a:tabLst></a:pPr>"
            + "<a:r><a:rPr lang=\"ja-JP\"><a:solidFill><a:schemeClr val=\"accent2\"><a:lumMod val=\"75000\"/></a:schemeClr></a:solidFill>"
            + "<a:latin typeface=\"Arial\" charset=\"0\"/><a:ea typeface=\"MS Gothic\"/></a:rPr><a:t>hello</a:t></a:r></a:p></p:txBody></p:sp>"
        let part = "ppt/slides/slide2.xml"
        var slide = String(data: package.parts[part]!, encoding: .utf8)!
        slide = slide.replacingOccurrences(of: "</p:spTree>", with: sp + "</p:spTree>")
        package.parts[part] = Data(slide.utf8)
        var entries: [ZipEntry] = []
        for (k, v) in package.parts { entries.append(ZipEntry(name: k, data: v)) }
        var (state, theme, pkg) = try Pptx.read(try Zip.write(entries))
        let si = try XCTUnwrap(state.slides.firstIndex { $0.shapes.contains { $0.name == "Rich" } })
        let i = try XCTUnwrap(state.slides[si].shapes.firstIndex { $0.name == "Rich" })
        var doc = try XCTUnwrap(state.slides[si].shapes[i].text)
        doc.paragraphs[0].applyStyle(1 ..< 3) { $0.bold = true; $0.color = Color(0xFFFF0000); $0.fontSize = 30 }
        state.slides[si].shapes[i].text = doc
        let out = PptxPackage(try Zip.read(try PptxWriter.write(state, theme: theme, package: pkg)))
        let xml = try XCTUnwrap(out.parts.keys.filter { $0.hasPrefix("ppt/slides/slide") && !$0.contains("_rels") }
            .compactMap { String(data: out.parts[$0]!, encoding: .utf8) }.first { $0.contains("name=\"Rich\"") })
        for kept in ["val 33333", "outerShdw", "accent2", "MS Gothic", "eaLnBrk", "a:tabLst", "defTabSz", "ja-JP"] {
            XCTAssertTrue(xml.contains(kept), "\(kept) survives")
        }
        XCTAssertTrue(xml.contains("b=\"1\"") && xml.contains("FF0000") && xml.contains("sz=\"3000\""), "the edit itself is written")
        XCTAssertTrue(xml.contains(">h<") && xml.contains(">el<") && xml.contains(">lo<"), "the run is split around the edit")
    }

    /// Text held level inside a rotated shape is read as two shapes; an edit to it still writes the one original element.
    func testUprightTextShapeKeepsItsElementWhenEdited() throws {
        let path = "/data/corpus-cache/test/corpus/pptx/decks/oox-tdf149538_upright.pptx"
        guard FileManager.default.fileExists(atPath: path) else { throw XCTSkip("corpus deck not restored") }
        var (state, theme, pkg) = try Pptx.read(try Data(contentsOf: URL(fileURLWithPath: path)))
        let i = try XCTUnwrap(state.slides[0].shapes.firstIndex { $0.fill != nil && $0.sourceXML != nil })
        state.slides[0].shapes[i].fill = Color(0xFFFFC000); state.slides[0].shapes[i].fillScheme = nil
        let out = PptxPackage(try Zip.read(try PptxWriter.write(state, theme: theme, package: pkg)))
        let xml = String(data: try XCTUnwrap(out.parts["ppt/slides/slide1.xml"]), encoding: .utf8)!
        for kept in ["MS Mincho", "prstTxWarp", "adj4", "FFC000"] { XCTAssertTrue(xml.contains(kept), kept) }
        XCTAssertEqual(xml.components(separatedBy: "<p:sp>").count, 2, "one shape element")
    }

    /// Typing in one table cell writes the table's own XML with that cell patched: styles, borders, East Asian faces stay.
    func testTableCellTypingKeepsTheTableElement() throws {
        let path = "/data/corpus-cache/test/corpus/pptx/decks/lo-tablescale.pptx"
        guard FileManager.default.fileExists(atPath: path) else { throw XCTSkip("corpus deck not restored") }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        var (state, theme, pkg) = try Pptx.read(data)
        var done = false
        outer: for si in state.slides.indices { for hi in state.slides[si].shapes.indices {
            let sh = state.slides[si].shapes[hi]
            if case .table = sh.kind, var doc = sh.text, sh.sourceXML != nil {
                doc.paragraphs[0].insert("Z", at: 0)
                state.slides[si].shapes[hi].text = doc
                done = true; break outer
            }
        } }
        try XCTSkipUnless(done, "no table")
        let before = PptxPackage(try Zip.read(data)), after = PptxPackage(try Zip.read(try PptxWriter.write(state, theme: theme, package: pkg)))
        func tables(_ p: PptxPackage) -> String {
            p.parts.keys.filter { $0.hasPrefix("ppt/slides/slide") && !$0.contains("_rels") }.sorted()
                .compactMap { String(data: p.parts[$0]!, encoding: .utf8) }.joined()
        }
        let a = tables(before), b = tables(after)
        for k in ["schemeClr", "<a:ea ", "<a:tableStyleId>", "<a:lnL", "a:tcPr"] { XCTAssertEqual(a.components(separatedBy: k).count, b.components(separatedBy: k).count, k) }
        XCTAssertTrue(b.contains("Z"))
    }

    func testShapeLinkToASlideWritesAnInternalJump() throws {
        let deck = DeckController()
        _ = deck.addSlide()
        deck.select(0)
        deck.selectShapes([deck.currentSlide.shapes[0]])
        let target = try XCTUnwrap(deck.slideLinkTargets().last)
        XCTAssertTrue(deck.setShapeLink("slide:" + target.key, tip: "Go"))
        XCTAssertEqual(deck.selectedShapeLink.link, "slide:" + target.key)
        let (state, theme, pkg) = (deck.snapshot(), deck.theme, deck.package)
        let out = PptxPackage(try Zip.read(try PptxWriter.write(state, theme: theme, package: pkg)))
        let slide = String(data: out.parts["ppt/slides/slide1.xml"]!, encoding: .utf8)!
        XCTAssertTrue(slide.contains("ppaction://hlinksldjump"), slide)
        let rels = String(data: out.parts["ppt/slides/_rels/slide1.xml.rels"]!, encoding: .utf8)!
        XCTAssertTrue(rels.contains("slide2.xml"), rels)
        XCTAssertTrue(deck.setShapeLink(nil, tip: nil))
        XCTAssertNil(deck.selectedShapeLink.link)
    }
}
