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
}
