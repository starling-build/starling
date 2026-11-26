// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

final class SlideMasterViewTests: XCTestCase {
    private func _deck() throws -> DeckController {
        let d = SlidesSample.make()
        // Through a file, so the deck has a real package with masters and layouts.
        let data = try Pptx.write(d)
        let (state, theme, pkg) = try Pptx.read(data)
        let deck = DeckController()
        deck.load(state, theme: theme, package: pkg)
        return deck
    }

    private func _layoutNames(_ d: DeckController) -> [String] {
        d.slides.compactMap { $0.masterRole }.filter { $0.kind == .layout }.map(\.name)
    }

    private func _reopen(_ d: DeckController) throws -> (DeckState, PptxPackage) {
        let (s, _, p) = try Pptx.read(try Pptx.write(d))
        return (s, p)
    }

    private func _checkXML(_ p: PptxPackage) {
        for (name, data) in p.parts where name.hasSuffix(".xml") || name.hasSuffix(".rels") {
            XCTAssertNotNil(XNode.parse(data), "\(name) does not parse")
        }
    }

    func testEnterListsMasterAndLayouts() throws {
        let d = try _deck()
        let before = d.slides.count
        try d.enterMasterView()
        XCTAssertTrue(d.inMasterView)
        XCTAssertEqual(d.slides.first?.masterRole?.kind, .master)
        XCTAssertGreaterThan(_layoutNames(d).count, 0)
        try d.closeMasterView()
        XCTAssertFalse(d.inMasterView)
        XCTAssertEqual(d.slides.count, before)
    }

    func testNoEditKeepsLayouts() throws {
        let d = try _deck()
        let (_, p0) = try _reopen(d)
        try d.enterMasterView()
        try d.closeMasterView()
        let (_, p1) = try _reopen(d)
        func layouts(_ p: PptxPackage) -> [String] { p.parts.keys.filter { $0.hasPrefix("ppt/slideLayouts/slideLayout") && $0.hasSuffix(".xml") }.sorted() }
        XCTAssertEqual(layouts(p0), layouts(p1))
        _checkXML(p1)
    }

    func testRenameDuplicateInsertDelete() throws {
        let d = try _deck()
        try d.enterMasterView()
        let n0 = _layoutNames(d).count
        d.select(d.slides.firstIndex { $0.masterRole?.kind == .layout }!)
        d.renameMasterPage("My Layout")
        d.duplicateLayout()
        d.insertLayout()
        XCTAssertEqual(_layoutNames(d).count, n0 + 2)
        d.insertMasterPlaceholder("body")
        d.select(d.slides.firstIndex { $0.masterRole?.kind == .master }!)
        if let t = d.currentSlide.shapes.first(where: { $0.phType == "title" }) { t.text?.setFontSize(40); t.text?.toggleItalic() }
        try d.closeMasterView()
        let (_, p) = try _reopen(d)
        _checkXML(p)
        let parts = p.parts.keys.filter { $0.hasPrefix("ppt/slideLayouts/slideLayout") && $0.hasSuffix(".xml") }
        XCTAssertEqual(parts.count, n0 + 2)
        let names = parts.compactMap { p.xml($0)?.descendant("p:cSld")?["name"] }
        XCTAssertTrue(names.contains("My Layout"))
        XCTAssertTrue(names.contains("1_My Layout"))
        XCTAssertTrue(names.contains("Custom Layout"))
        let master = p.xml("ppt/slideMasters/slideMaster1.xml")
        XCTAssertEqual(master?.descendant("p:sldLayoutIdLst")?.all("p:sldLayoutId").count, n0 + 2)
        // Every layout is in the master's rels and the content types.
        for part in parts { XCTAssertNotNil(p.overrides[part], part) }
    }

    func testDeleteLayoutRepointsSlides() throws {
        let d = try _deck()
        try d.enterMasterView()
        let n0 = _layoutNames(d).count
        d.select(d.slides.firstIndex { $0.masterRole?.kind == .layout }!)
        XCTAssertTrue(d.canDeleteLayout)
        d.deleteLayout()
        XCTAssertEqual(_layoutNames(d).count, n0 - 1)
        try d.closeMasterView()
        let (s, p) = try _reopen(d)
        _checkXML(p)
        XCTAssertEqual(s.slides.count, d.slides.count)
        let parts = p.parts.keys.filter { $0.hasPrefix("ppt/slideLayouts/slideLayout") && $0.hasSuffix(".xml") }
        XCTAssertEqual(parts.count, n0 - 1)
        for k in p.parts.keys where k.hasPrefix("ppt/slides/slide") && k.hasSuffix(".xml") {
            let rels = p.rels(k)
            let target = rels.first { $0.type.hasSuffix("/slideLayout") }?.target
            XCTAssertNotNil(target, k)
        }
    }

    func testSaveWhileOpen() throws {
        let d = try _deck()
        try d.enterMasterView()
        d.select(1)
        d.renameMasterPage("Saved Open")
        let data = try Pptx.write(d)
        let (_, _, p) = try Pptx.read(data)
        let names = p.parts.keys.filter { $0.hasPrefix("ppt/slideLayouts/slideLayout") && $0.hasSuffix(".xml") }.compactMap { p.xml($0)?.descendant("p:cSld")?["name"] }
        XCTAssertTrue(names.contains("Saved Open"))
    }


    private func _deckWithListStyle() throws -> DeckController { try _deck() }

    private func _layout1(_ d: DeckController) throws -> String {
        let (_, p) = try _reopen(d)
        return String(decoding: p.parts["ppt/slideLayouts/slideLayout1.xml"] ?? Data(), as: UTF8.self)
    }

    func testEditedPlaceholderKeepsListStyle() throws {
        for edit in 0 ..< 5 {
            let d = try _deckWithListStyle()
            try d.enterMasterView()
            let page = d.slides.firstIndex { $0.masterRole?.part == "ppt/slideLayouts/slideLayout1.xml" }!
            d.select(page)
            let title = d.currentSlide.shapes.first { $0.phType == "ctrTitle" || $0.phType == "title" }!
            d.selectShapes([title])
            switch edit {
            case 0: d.setFill(Color(0xFF3366CC))
            case 1: d.setSize(width: title.frame.width - 10)
            case 2: title.text?.replaceText(in: 0, 0 ..< (title.text?.document.paragraphs[0].text.count ?? 0), with: "A new title")
            case 3: d.renameMasterPage("Named")
            default: break
            }
            try d.closeMasterView()
            let x = try _layout1(d)
            XCTAssertTrue(x.containsSubstring("<a:lstStyle><a:lvl1pPr algn=\"ctr\" indent=\"0\" marL=\"0\"><a:buNone/><a:defRPr sz=\"6000\"/>"), "edit \(edit): \(x.rangeOfSubstring("<a:lstStyle").map { String(x[$0.lowerBound...].prefix(260)) } ?? "none")")
        }
    }

    private func _selectFirstParagraph(_ s: SlideShape) {
        guard let c = s.text else { return }
        let n = c.document.paragraphs[0].text.count
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        c.moveTo(RichPosition(paragraph: 0, offset: n), extend: true)
    }

    func testMasterFontControlsChangeTextStyles() throws {
        let d = try _deck()
        let (_, before) = try _reopen(d)
        let old = String(decoding: before.parts["ppt/slideMasters/slideMaster1.xml"] ?? Data(), as: UTF8.self)
        try d.enterMasterView()
        let page = d.slides.firstIndex { $0.masterRole?.kind == .master }!
        d.select(page)
        let title = d.currentSlide.shapes.first { $0.phType == "title" }!
        _selectFirstParagraph(title)
        title.text?.setFontSize(33)
        title.text?.toggleItalic()
        title.text?.setFontFamily("Georgia")
        let body = d.currentSlide.shapes.first { $0.phType == "body" }!
        _selectFirstParagraph(body)
        body.text?.setFontSize(21)
        try d.closeMasterView()
        let (_, p) = try _reopen(d)
        _checkXML(p)
        let x = String(decoding: p.parts["ppt/slideMasters/slideMaster1.xml"] ?? Data(), as: UTF8.self)
        let root = XNode.parse(Data(x.utf8))!
        let tx = root.first("p:txStyles")!
        let tl = tx.first("p:titleStyle")!.first("a:lvl1pPr")!.first("a:defRPr")!
        XCTAssertEqual(tl["sz"], "3300")
        XCTAssertEqual(tl["i"], "1")
        XCTAssertEqual(tl.first("a:latin")?["typeface"], "Georgia")
        let bl = tx.first("p:bodyStyle")!.first("a:lvl1pPr")!.first("a:defRPr")!
        XCTAssertEqual(bl["sz"], "2100")
        // A level the view did not touch keeps its text style, and a title edit leaves the body style alone.
        let oldRoot = XNode.parse(Data(old.utf8))!
        let b3 = { (r: XNode) in r.first("p:txStyles")!.first("p:bodyStyle")!.first("a:lvl9pPr").map { PptxXML.serialize($0) } }
        XCTAssertEqual(b3(root), b3(oldRoot))
        XCTAssertNil(bl["i"])
    }

    func testWriteCheckDeck() throws {
        guard let out = ProcessInfo.processInfo.environment["STARLING_MASTER_OUT"] else { return }
        let d = try _deck()
        try d.enterMasterView()
        d.select(d.slides.firstIndex { $0.masterRole?.kind == .layout }!)
        d.renameMasterPage("Renamed Layout")
        d.duplicateLayout()
        d.insertLayout()
        d.insertMasterPlaceholder("body")
        d.select(d.slides.firstIndex { $0.masterRole?.kind == .master }!)
        if let t = d.currentSlide.shapes.first(where: { $0.phType == "title" }) { t.text?.setFontSize(40); t.text?.toggleItalic() }
        try d.closeMasterView()
        try Pptx.write(d).write(to: URL(fileURLWithPath: out))
    }

    // A deck whose slide titles and layouts 2-7 say nothing about the title's size or italic
    // (layout 1, Title Slide, keeps its 60 pt, as PowerPoint's own default template does).
    private func _cleanTitleDeck() throws -> Data {
        var pkg = PptxPackage(try Zip.read(try Pptx.write(SlidesSample.make())))
        func titles(_ x: String, _ f: (String) -> String) -> String {
            let re = try! NSRegularExpression(pattern: "<p:sp>.*?</p:sp>", options: [.dotMatchesLineSeparators])
            var out = x
            for m in re.matches(in: x, range: NSRange(x.startIndex..., in: x)).reversed() {
                let r = Range(m.range, in: x)!
                let sp = String(x[r])
                guard sp.range(of: "type=\"title\"") != nil || sp.range(of: "type=\"ctrTitle\"") != nil else { continue }
                out.replaceSubrange(Range(m.range, in: out)!, with: f(sp))
            }
            return out
        }
        func strip(_ sp: String, tags: String, attrs: String) -> String {
            let tag = try! NSRegularExpression(pattern: "<a:(\(tags))\\b[^>]*>")
            let attr = try! NSRegularExpression(pattern: " (\(attrs))=\"[^\"]*\"")
            var out = sp
            for m in tag.matches(in: sp, range: NSRange(sp.startIndex..., in: sp)).reversed() {
                let t = String(sp[Range(m.range, in: sp)!])
                let c = attr.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: "")
                out.replaceSubrange(Range(m.range, in: out)!, with: c)
            }
            return out
        }
        for name in pkg.parts.keys.sorted() {
            let x = String(decoding: pkg.parts[name]!, as: UTF8.self)
            if name.hasPrefix("ppt/slides/slide"), name.hasSuffix(".xml") {
                pkg.parts[name] = Data(titles(x) { strip($0, tags: "rPr|endParaRPr", attrs: "sz|b|i|u|strike") }.utf8)
            } else if name.hasPrefix("ppt/slideLayouts/slideLayout"), name.hasSuffix(".xml"), name != "ppt/slideLayouts/slideLayout1.xml" {
                pkg.parts[name] = Data(titles(x) { strip($0, tags: "defRPr", attrs: "sz|b|i") }.utf8)
            }
        }
        return try Zip.write(pkg.parts.sorted { $0.key < $1.key }.map { ZipEntry(name: $0.key, data: $0.value) })
    }

    private func _open(_ data: Data) throws -> DeckController {
        let (state, theme, pkg) = try Pptx.read(data)
        let d = DeckController()
        d.load(state, theme: theme, package: pkg)
        return d
    }

    /// The run properties written on each slide's title (rPr and endParaRPr tags).
    private func _slideTitleRuns(_ data: Data) throws -> [String: [String]] {
        let p = PptxPackage(try Zip.read(data))
        var out: [String: [String]] = [:]
        let re = try NSRegularExpression(pattern: "<a:(rPr|endParaRPr)\\b[^>]*>")
        let sps = try NSRegularExpression(pattern: "<p:sp>.*?</p:sp>", options: [.dotMatchesLineSeparators])
        for (name, bytes) in p.parts where name.hasPrefix("ppt/slides/slide") && name.hasSuffix(".xml") {
            let x = String(decoding: bytes, as: UTF8.self)
            for m in sps.matches(in: x, range: NSRange(x.startIndex..., in: x)) {
                let t = String(x[Range(m.range, in: x)!])
                guard t.range(of: "type=\"title\"") != nil || t.range(of: "type=\"ctrTitle\"") != nil else { continue }
                out[name, default: []] += re.matches(in: t, range: NSRange(t.startIndex..., in: t)).map { String(t[Range($0.range, in: t)!]) }
            }
        }
        return out
    }

    private func _assertUnpinned(_ data: Data, _ what: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let runs = try _slideTitleRuns(data)
        XCTAssertFalse(runs.isEmpty, what, file: file, line: line)
        for (name, tags) in runs {
            for t in tags {
                XCTAssertNil(t.range(of: " sz=\""), "\(what): \(name) \(t)", file: file, line: line)
                XCTAssertNil(t.range(of: " i=\""), "\(what): \(name) \(t)", file: file, line: line)
            }
        }
    }

    /// Opening and saving a deck does not write the title's size or italic onto slides that never had them:
    /// a run that pins them stops following the master and layout in PowerPoint.
    func testPlainSaveKeepsSlideTitlesInheriting() throws {
        let clean = try _cleanTitleDeck()
        try _assertUnpinned(clean, "input")
        try _assertUnpinned(try Pptx.write(try _open(clean)), "plain save")
    }

    /// A master title change through the view's font controls reaches the master's title style, and the
    /// slides and unpinned layouts keep inheriting it.
    func testMasterTitleChangeReachesSlides() throws {
        let d = try _open(try _cleanTitleDeck())
        try d.enterMasterView()
        d.select(d.slides.firstIndex { $0.masterRole?.kind == .master }!)
        let t = d.currentSlide.shapes.first { $0.phType == "title" }!
        _selectFirstParagraph(t)
        t.text?.setFontSize(40)
        t.text?.toggleItalic()
        try d.closeMasterView()
        let out = try Pptx.write(d)
        try _assertUnpinned(out, "after the master edit")
        let p = PptxPackage(try Zip.read(out))
        let m = XNode.parse(p.parts["ppt/slideMasters/slideMaster1.xml"]!)!
        let tl = m.first("p:txStyles")!.first("p:titleStyle")!.first("a:lvl1pPr")!.first("a:defRPr")!
        XCTAssertEqual(tl["sz"], "4000")
        XCTAssertEqual(tl["i"], "1")
        let l2 = String(decoding: p.parts["ppt/slideLayouts/slideLayout2.xml"]!, as: UTF8.self)
        XCTAssertNil(l2.range(of: "sz=\"4400\""))
    }

    /// Typing in a slide title writes the new text with the run's own properties, not the resolved ones.
    func testTypingInTitleKeepsItInheriting() throws {
        let d = try _open(try _cleanTitleDeck())
        let i = d.slides.firstIndex { $0.shapes.contains { $0.phType == "title" } }!
        d.select(i)
        let t = d.currentSlide.shapes.first { $0.phType == "title" }!
        t.text?.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        t.text?.insertText("New ")
        try _assertUnpinned(try Pptx.write(d), "after typing")
    }

    // PowerPoint check: STARLING_MASTER_IN_OUT writes the clean deck (and STARLING_MASTER_CLEAN the deck
    // before the edit) after the master title is set to 40 pt italic through the view's controls.
    func testWriteMasterTitleCheckDeck() throws {
        let env = ProcessInfo.processInfo.environment
        guard let out = env["STARLING_MASTER_IN_OUT"] else { return }
        let clean = try _cleanTitleDeck()
        if let c = env["STARLING_MASTER_CLEAN"] { try clean.write(to: URL(fileURLWithPath: c)) }
        let d = try _open(clean)
        try d.enterMasterView()
        d.select(d.slides.firstIndex { $0.masterRole?.kind == .master }!)
        let t = d.currentSlide.shapes.first { $0.phType == "title" }!
        _selectFirstParagraph(t)
        t.text?.setFontSize(40)
        t.text?.toggleItalic()
        try d.closeMasterView()
        try Pptx.write(d).write(to: URL(fileURLWithPath: out))
    }

    // Corpus count: STARLING_PIN_DIR (decks) to STARLING_PIN_OUT, one row per deck: the run tags on its slides
    // that state sz, b or i, in the file and after a plain open and save.
    func testCountPinnedRunsAfterPlainSave() throws {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["STARLING_PIN_DIR"], let outPath = env["STARLING_PIN_OUT"] else { return }
        let re = try NSRegularExpression(pattern: "<a:(rPr|endParaRPr)\\b[^>]*>")
        func count(_ data: Data) throws -> (Int, Int) {
            let p = PptxPackage(try Zip.read(data))
            var tags = 0, pinned = 0
            for name in p.parts.keys.sorted() where name.hasPrefix("ppt/slides/slide") && name.hasSuffix(".xml") {
                let x = String(decoding: p.parts[name]!, as: UTF8.self)
                for m in re.matches(in: x, range: NSRange(x.startIndex..., in: x)) {
                    let t = String(x[Range(m.range, in: x)!])
                    tags += 1
                    if t.range(of: " sz=\"") != nil || t.range(of: " b=\"") != nil || t.range(of: " i=\"") != nil { pinned += 1 }
                }
            }
            return (tags, pinned)
        }
        var rows = ["deck\ttags_in\tpinned_in\ttags_out\tpinned_out"]
        for f in try FileManager.default.contentsOfDirectory(atPath: dir).sorted() where f.hasSuffix(".pptx") {
            let data = try Data(contentsOf: URL(fileURLWithPath: dir + "/" + f))
            guard let a = try? count(data), let (state, theme, pkg) = try? Pptx.read(data) else { continue }
            let d = DeckController()
            d.load(state, theme: theme, package: pkg)
            guard let out = try? Pptx.write(d), let b = try? count(out) else { rows.append("\(f)\t\(a.0)\t\(a.1)\tERR\tERR"); continue }
            rows.append("\(f)\t\(a.0)\t\(a.1)\t\(b.0)\t\(b.1)")
        }
        try (rows.joined(separator: "\n") + "\n").write(toFile: outPath, atomically: true, encoding: .utf8)
    }
}
