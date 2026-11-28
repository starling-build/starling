// Copyright the Starling authors
// (gate self-test: comment-only change in a Slides file)
// SPDX-License-Identifier: Apache-2.0

// .pptx out. Two modes, chosen by where the deck came from:
//
//  * A deck read from a file is written through its package: masters,
//    layouts, themes, the notes master and everything else not modelled
//    are copied byte for byte; presentation.xml keeps all it had except the
//    slide list and the slide size; each slide is written fresh from the
//    model, and kept objects (charts, SmartArt, freeforms…) are written
//    back verbatim with the parts their relationships point at.
//  * A new deck gets our own theme, master, seven layouts and notes master
//    (PptxTemplates.swift), bound by the placeholder type/idx pairs that
//    PowerPoint's own default layouts use.
//
// Every slide carries explicit geometry and explicit run properties, so
// what PowerPoint shows is what this app showed.

import Flutter
import OfficeText
import FlutterSwiftBridge
#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif

enum PptxWriter {
    static func write(_ state: DeckState, theme: DeckTheme, package: PptxPackage?,
                      ownTemplates: Bool = false, recolourTheme: Bool = false) throws -> Data {
        var b = PackageBuilder()
        if let package, !ownTemplates, _usable(package) {
            try _writeThrough(package, state: state, theme: theme, recolour: recolourTheme, into: &b)
        } else {
            _writeNew(state, theme: theme, source: package, into: &b)
        }
        return try b.zip()
    }

    /// Whether `p` has what writing through it needs: a presentation, and a
    /// master with at least one layout, present. A damaged file (one
    /// salvaged from a cut-short zip) is written on our own templates
    /// instead, its kept objects still copied from it.
    private static func _usable(_ p: PptxPackage) -> Bool {
        guard let pres = _presentationPart(p), p.parts[pres] != nil else { return false }
        let masters = p.rels(pres).filter { $0.kind == "slideMaster" && !$0.external }
        // One master with a layout will do: a deck may carry masters with
        // none of their own (bug64693's has four).
        return masters.contains { m in
            p.parts[m.target] != nil
                && p.rels(m.target).contains { $0.kind == "slideLayout" && p.parts[$0.target] != nil }
                && p.rels(m.target).contains { $0.kind == "theme" && p.parts[$0.target] != nil }
        }
    }

    private static func _presentationPart(_ p: PptxPackage) -> String? {
        p.xml("_rels/.rels")?.all("Relationship").first { ($0["Type"] ?? "").hasSuffix("/officeDocument") }
            .flatMap { $0["Target"] }.map { $0.hasPrefix("/") ? String($0.dropFirst()) : $0 }
    }

    // MARK: A new deck

    /// Our own templates. `source` is the file the deck came from, if any:
    /// its kept objects' parts are still copied from it.
    private static func _writeNew(_ state: DeckState, theme: DeckTheme, source: PptxPackage?,
                                  into b: inout PackageBuilder) {
        if let source { b.defaults.merge(source.defaults) { mine, _ in mine } }
        var t = PptxTemplates(theme: theme, slideSize: state.slideSize)
        t.masterBackground = state.masterBackground
        b.add("ppt/theme/theme1.xml", t.themeXML(), type: CT.theme)
        b.add("ppt/theme/theme2.xml", t.themeXML(), type: CT.theme)
        b.add("ppt/slideMasters/slideMaster1.xml", t.master(), type: CT.master)
        var masterRels = [Rel(id: "rIdTheme", type: RT.theme, target: "../theme/theme1.xml")]
        var layoutParts: [SlideLayoutKind: String] = [:]
        for (i, kind) in SlideLayoutKind.allCases.enumerated() {
            let part = "ppt/slideLayouts/slideLayout\(i + 1).xml"
            layoutParts[kind] = part
            b.add(part, t.layout(kind), type: CT.layout)
            b.rels(part, [Rel(id: "rId1", type: RT.master, target: "../slideMasters/slideMaster1.xml")])
            masterRels.append(Rel(id: "rIdL\(i + 1)", type: RT.layout, target: "../slideLayouts/slideLayout\(i + 1).xml"))
        }
        if let pic = state.masterBackground?.image {
            masterRels.append(Rel(id: PptxTemplates.masterPictureRID, type: RT.image, target: "../media/" + _masterPictureName(pic)))
            b.addBinary("ppt/media/" + _masterPictureName(pic), pic.data)
        }
        b.rels("ppt/slideMasters/slideMaster1.xml", masterRels)
        b.add("ppt/notesMasters/notesMaster1.xml", t.notesMaster(), type: CT.notesMaster)
        b.rels("ppt/notesMasters/notesMaster1.xml", [Rel(id: "rId1", type: RT.theme, target: "../theme/theme2.xml")])
        b.add("ppt/presProps.xml", PptxTemplates.presProps, type: CT.presProps)
        b.add("ppt/viewProps.xml", PptxTemplates.viewProps, type: CT.viewProps)
        b.add("ppt/tableStyles.xml", PptxTemplates.tableStyles, type: CT.tableStyles)
        b.add("docProps/core.xml", PptxTemplates.core(), type: CT.core)
        b.add("docProps/app.xml", PptxTemplates.app(slides: state.slides.count), type: CT.app)
        b.rels("", [
            Rel(id: "rId1", type: RT.document, target: "ppt/presentation.xml"),
            Rel(id: "rId2", type: RT.core, target: "docProps/core.xml"),
            Rel(id: "rId3", type: RT.app, target: "docProps/app.xml"),
        ])

        var presRels = [
            Rel(id: "rIdM", type: RT.master, target: "slideMasters/slideMaster1.xml"),
            Rel(id: "rIdNM", type: RT.notesMaster, target: "notesMasters/notesMaster1.xml"),
            Rel(id: "rIdPP", type: RT.presProps, target: "presProps.xml"),
            Rel(id: "rIdVP", type: RT.viewProps, target: "viewProps.xml"),
            Rel(id: "rIdTS", type: RT.tableStyles, target: "tableStyles.xml"),
            Rel(id: "rIdT", type: RT.theme, target: "theme/theme1.xml"),
        ]
        var ids = ""
        var media = MediaParts()
        PptxText.setSlideParts(state.slides)
        defer { PptxText.slideParts = [:] }
        for (i, slide) in state.slides.enumerated() {
            let part = "ppt/slides/slide\(i + 1).xml"
            let layout = slide.layoutPart.flatMap { lp in layoutParts.values.contains(lp) ? lp : nil }
                ?? layoutParts[slide.layout] ?? "ppt/slideLayouts/slideLayout2.xml"
            _slide(slide, number: i + 1, part: part, layoutPart: layout, notesMaster: "ppt/notesMasters/notesMaster1.xml",
                   source: source, media: &media, into: &b)
            presRels.append(Rel(id: "rIdS\(i + 1)", type: RT.slide, target: "slides/slide\(i + 1).xml"))
            ids += "<p:sldId id=\"\(256 + i)\" r:id=\"rIdS\(i + 1)\"/>"
        }
        b.rels("ppt/presentation.xml", presRels)
        b.add("ppt/presentation.xml", _setSections(_setCustomShows(t.presentation(slideIds: ids), state), state, slideIds: state.slides.indices.map { 256 + $0 }), type: CT.presentation)
        b.add("ppt/presProps.xml", _applyShowPr(PptxTemplates.presProps, state.show), type: CT.presProps)
    }

    // MARK: Through a package

    private static func _writeThrough(_ p: PptxPackage, state: DeckState, theme: DeckTheme, recolour: Bool,
                                      into b: inout PackageBuilder) throws {
        guard let pres = _presentationPart(p), let presXML = p.parts[pres].flatMap({ String(data: $0, encoding: .utf8) })
        else { throw Pptx.ReadError.noPresentation }
        b.defaults.merge(p.defaults) { mine, _ in mine }

        // Everything reachable from the package root except slides and notes
        // slides: copied as it was.
        // What a .pptx may not carry, a macro project, is left behind
        // (PowerPoint's own Save As .pptx drops it too).
        // A damaged file may name parts it no longer has: those relationships
        // are left behind rather than written pointing at nothing.
        let presRelsAll = p.rels(pres).filter { $0.kind != "vbaProject" && ($0.external || p.parts[$0.target] != nil) }
        var keep: [String] = []
        for r in p.rels("") where !r.external && r.target != pres { keep.append(r.target) }
        for r in presRelsAll where !r.external && r.kind != "slide" { keep.append(r.target) }
        var copied = [String: String]()
        for part in keep { _copy(part, from: p, into: &b, done: &copied) }
        if let m = state.masterBackground { _setMasterBackground(m, in: &b) }
        if let pp = presRelsAll.first(where: { $0.kind == "presProps" })?.target,
           let d = b.parts[pp], let x = String(data: d, encoding: .utf8) {
            if state.show != state.sourceShow { b.parts[pp] = Data(_applyShowPr(x, state.show).utf8) }
        }
        if let scaling = state.slideScaling, let old = _slideSize(presXML), old != state.slideSize {
            _scaleMasters(from: old, to: state.slideSize, scaling, in: &b)
        }
        if recolour {
            for r in presRelsAll where r.kind == "slideMaster" {
                for tr in p.rels(r.target) where tr.kind == "theme" {
                    if let d = b.parts[tr.target], let x = String(data: d, encoding: .utf8) {
                        b.parts[tr.target] = Data(_recoloured(x, theme).utf8)
                    }
                }
            }
        }
        let rootRels = p.rels("").filter { $0.external || p.parts[$0.target] != nil }
        b.rels("", rootRels.map { Rel(id: $0.id, type: $0.type, target: $0.target, external: $0.external) })

        // Layouts by type, for slides that never had one from this file.
        var layoutsByType: [String: String] = [:]
        var anyLayout: String? = nil
        for r in presRelsAll where r.kind == "slideMaster" {
            for lr in p.rels(r.target) where lr.kind == "slideLayout" {
                anyLayout = anyLayout ?? lr.target
                if let type = p.xml(lr.target)?["type"], layoutsByType[type] == nil { layoutsByType[type] = lr.target }
            }
        }
        func layoutFor(_ kind: SlideLayoutKind) -> String? {
            let type: String
            switch kind {
            case .titleSlide: type = "title"
            case .titleAndContent: type = "obj"
            case .sectionHeader: type = "secHead"
            case .twoContent: type = "twoObj"
            case .comparison: type = "twoTxTwoObj"
            case .titleOnly: type = "titleOnly"
            case .blank: type = "blank"
            }
            return layoutsByType[type] ?? anyLayout
        }

        // A notes master: the file's, or ours when it had none and notes exist.
        var notesMaster = presRelsAll.first { $0.kind == "notesMaster" }?.target
        var extraPresRels: [Rel] = []
        var presOut = presXML
        let anyNotes = state.slides.contains { !$0.notes.paragraphs.allSatisfy { $0.text.isEmpty } }
        if notesMaster == nil && anyNotes {
            let t = PptxTemplates(theme: theme, slideSize: state.slideSize)
            b.add("ppt/notesMasters/notesMasterS1.xml", t.notesMaster(), type: CT.notesMaster)
            b.add("ppt/theme/themeS1.xml", t.themeXML(), type: CT.theme)
            b.rels("ppt/notesMasters/notesMasterS1.xml", [Rel(id: "rId1", type: RT.theme, target: "../theme/themeS1.xml")])
            notesMaster = "ppt/notesMasters/notesMasterS1.xml"
            extraPresRels.append(Rel(id: "rIdSNM", type: RT.notesMaster,
                                     target: Pptx.relative("ppt/notesMasters/notesMasterS1.xml", from: pres)))
            presOut = _insertAfter("</p:sldMasterIdLst>", in: presOut,
                                   "<p:notesMasterIdLst><p:notesMasterId r:id=\"rIdSNM\"/></p:notesMasterIdLst>")
        }

        var presRels: [Rel] = presRelsAll.filter { $0.kind != "slide" }.map {
            Rel(id: $0.id, type: $0.type, target: $0.external ? $0.target : Pptx.relative($0.target, from: pres),
                external: $0.external)
        } + extraPresRels
        // A slide read from the file keeps its slide id (sections and custom shows name slides by id); new ones take ids above every old one.
        var oldIdByPart: [String: Int] = [:]
        var maxId = 255
        for e in p.xml(pres)?.descendant("p:sldIdLst")?.all("p:sldId") ?? [] {
            guard let id = Int(e["id"] ?? "") else { continue }
            maxId = max(maxId, id)
            if let rid = e["r:id"], let r = presRelsAll.first(where: { $0.id == rid && $0.kind == "slide" }) { oldIdByPart[r.target] = id }
        }
        var slideIds: [Int] = []
        var usedIds = Set<Int>()
        for slide in state.slides {
            if let part = slide.sourcePart, let id = oldIdByPart[part], !usedIds.contains(id) {
                slideIds.append(id); usedIds.insert(id)
            } else {
                maxId += 1
                slideIds.append(maxId); usedIds.insert(maxId)
            }
        }
        var ids = ""
        var media = MediaParts()
        PptxText.setSlideParts(state.slides)
        defer { PptxText.slideParts = [:] }
        for (i, slide) in state.slides.enumerated() {
            let part = "ppt/slides/slide\(i + 1).xml"
            let layout = slide.layoutPart.flatMap { p.parts[$0] != nil ? $0 : nil } ?? layoutFor(slide.layout)
            _slide(slide, number: i + 1, part: part, layoutPart: layout, notesMaster: notesMaster,
                   source: p, media: &media, into: &b)
            presRels.append(Rel(id: "rIdS\(i + 1)", type: RT.slide, target: Pptx.relative(part, from: pres)))
            ids += "<p:sldId id=\"\(slideIds[i])\" r:id=\"rIdS\(i + 1)\"/>"
        }
        b.rels(pres, presRels)
        presOut = _replaceElement("p:sldIdLst", in: presOut, with: "<p:sldIdLst>\(ids)</p:sldIdLst>",
                                  after: "</p:notesMasterIdLst>", orAfter: "</p:sldMasterIdLst>")
        // Custom shows (`p:custShowLst`) list slides by the same relationship
        // ids this just numbered, written from the deck's own list.
        presOut = _setSections(presOut, state, slideIds: slideIds)
        presOut = _setCustomShows(presOut, state)
        let cx = Int((state.slideSize.width * Pptx.emu).rounded()), cy = Int((state.slideSize.height * Pptx.emu).rounded())
        // The size as the file wrote it, its kind (`type`, a paper or screen
        // name PowerPoint's size menu shows) included, while it is unchanged.
        var size = "<p:sldSz cx=\"\(cx)\" cy=\"\(cy)\"/>"
        if let r = presOut.rangeOfSubstring("<p:sldSz "), let e = presOut.rangeOfSubstring("/>", in: r.upperBound ..< presOut.endIndex) {
            let old = String(presOut[r.lowerBound ..< e.upperBound])
            if old.containsSubstring(" cx=\"\(cx)\""), old.containsSubstring(" cy=\"\(cy)\""),
               !String(old.dropLast(2)).containsSubstring(">") { size = old }
        }
        presOut = _replaceElement("p:sldSz", in: presOut, with: size,
                                  after: "</p:sldIdLst>", orAfter: nil)
        // Always a presentation: a macro-enabled deck, a template or a show
        // read in becomes a plain .pptx, which is what this writes.
        b.add(pres, presOut, type: CT.presentation)
    }

    /// Copy a part, its relationships, and everything they reach.
    private static func _copy(_ part: String, from p: PptxPackage, into b: inout PackageBuilder, done: inout [String: String]) {
        PptxWriterCopy.copy(part, from: p, into: &b, done: &done)
    }

    // MARK: Slides

    private static func _slide(_ slide: SlideState, number: Int, part: String, layoutPart: String?,
                               notesMaster: String?, source: PptxPackage?, media: inout MediaParts,
                               into b: inout PackageBuilder) {
        var rels: [Rel] = []
        if let layoutPart {
            rels.append(Rel(id: "rIdLayout", type: RT.layout, target: Pptx.relative(layoutPart, from: part)))
        }
        var w = SlideXML(part: part, source: source)
        let links = PptxLinks()
        links.part = part; links.slideParts = PptxText.slideParts
        PptxText.links = links
        defer { PptxText.links = nil }
        // Shape ids: a shape read from a file keeps its own (the slide's
        // animations name shapes by id); new ones start above them all.
        let shapes = SlideXML._mergeUprightSplits(slide.shapes)
        w.nextId = 2 + (shapes.compactMap(\.fileId).max() ?? 0)
        var body = ""
        // Members of a group read from the file, still side by side, are
        // grouped again under the group's own id.
        var i = 0
        var written = Set<Int>()
        while i < shapes.count {
            guard var g = shapes[i].group else {
                body += w.shape(shapes[i], media: &media, builder: &b)
                i += 1
                continue
            }
            var j = i
            while j < shapes.count, shapes[j].group?.key == g.key { j += 1 }
            // A group split by reordering is written as two groups: the second must not repeat the id.
            if !written.insert(g.key).inserted { g.fileId = nil }
            body += w.group(g, members: Array(shapes[i ..< j]), media: &media, builder: &b)
            i = j
        }
        var bg = ""
        if let xml = slide.backgroundXML, let src = slide.carryPart, let p = source {
            bg = w.kept(xml, sourcePart: src, package: p, builder: &b, patch: nil)
        } else if let fill = slide.background {
            bg = "<p:bg><p:bgPr>" + w.fill(fill, media: &media, builder: &b) + "<a:effectLst/></p:bgPr></p:bg>"
        }
        // An OLE object (`p:oleObj spid="_x0000_s…"`) draws through a shape
        // in the slide's VML drawing part, which the slide reaches by a
        // relationship nothing in its XML names — so remapping r:ids keeps
        // the embedding and loses the drawing, and PowerPoint then asks to
        // repair the file. Carry the part while a kept object still has one.
        // ActiveX controls (`p:controls`): kept, their parts and pictures
        // carried; the VML drawing below places them, as it does OLE objects.
        var controls = ""
        if let c = slide.controlsXML, let src = slide.carryPart, let p = source {
            controls = w.kept(c, sourcePart: src, package: p, builder: &b, patch: nil)
        }
        // The slide's tags (`p:custDataLst`): kept with the tag parts they name.
        var custData = ""
        if let c = slide.custDataXML, let src = slide.carryPart, let p = source {
            custData = w.kept(c, sourcePart: src, package: p, builder: &b, patch: nil)
        }
        if body.containsSubstring("<p:oleObj") || !controls.isEmpty, let src = slide.carryPart, let p = source,
           let vml = p.rels(src).first(where: { ["vmlDrawing", "legacyDrawing"].contains($0.kind) && !$0.external && p.parts[$0.target] != nil }) {
            var done = [String: String]()
            let name = PptxWriterCopy.copy(vml.target, from: p, into: &b, done: &done)
            rels.append(Rel(id: "rIdVml", type: vml.type, target: Pptx.relative(name, from: part)))
        }
        // A SmartArt's drawing part is reached the same way: the data part's
        // `dsp:dataModelExt relId` names a slide relationship nothing in the
        // slide XML does. PowerPoint lays the diagram out afresh without it,
        // but everything else (this app included) draws from it — carried
        // under its own id, which the data part still names.
        if body.containsSubstring("dgm:relIds"), let src = slide.carryPart, let p = source {
            for d in p.rels(src) where d.kind == "diagramDrawing" && !d.external && p.parts[d.target] != nil
                && !rels.contains(where: { $0.id == d.id }) {
                var done = [String: String]()
                let name = PptxWriterCopy.copy(d.target, from: p, into: &b, done: &done)
                rels.append(Rel(id: d.id, type: d.type, target: Pptx.relative(name, from: part)))
            }
        }
        // Comments (legacy or modern) hang off the slide by a relationship nothing in its XML names: carry each part, with its own rels, under the same id.
        // A copy of a commented slide (commentsFrom) carries the comments too; a part another slide already took goes out under a fresh name, since each slide owns its own.
        if let src = slide.carryPart, let p = source {
            for (n, c) in p.rels(src).filter({ $0.kind == "comments" && !$0.external && p.parts[$0.target] != nil }).enumerated() {
                var done = [String: String]()
                let target = PptxWriterCopy.copy(c.target, from: p, into: &b, done: &done)
                rels.append(Rel(id: "rIdCmt\(n + 1)", type: c.type, target: Pptx.relative(target, from: part)))
            }
            // So does a theme override (60810's slide 18): carried as the file had it.
            if let o = p.rels(src).first(where: { $0.kind == "themeOverride" && !$0.external && p.parts[$0.target] != nil }) {
                var done = [String: String]()
                let target = PptxWriterCopy.copy(o.target, from: p, into: &b, done: &done)
                rels.append(Rel(id: "rIdThmOvr", type: o.type, target: Pptx.relative(target, from: part)))
            }
        }
        let hidden = (slide.hidden ? " show=\"0\"" : "") + (slide.hideMasterShapes ? " showMasterSp=\"0\"" : "")
        // Kept XML may lean on prefixes the source slide declared at its
        // root (a14, p14, mc…): the same declarations go on ours.
        var ns = PptxTemplates.namespaces
        if let src = slide.carryPart, let root = source?.xml(src) {
            for (k, v) in root.attrs.sorted(by: { $0.key < $1.key })
            where k.hasPrefix("xmlns:") && !["xmlns:a", "xmlns:r", "xmlns:p"].contains(k) {
                ns += " \(k)=\"\(PptxXML.escape(v, attribute: true))\""
            }
        }
        var transition = _transition(slide.transition, namespaces: &ns)
        // Kept as read, a transition's sound (`p:snd r:embed`) still names
        // the source slide's relationship: remap it, carrying the .wav.
        if slide.transition.kept != nil, transition.containsSubstring("r:embed"), let src = slide.carryPart, let p = source {
            transition = w.kept(transition, sourcePart: src, package: p, builder: &b, patch: nil)
        }
        // Animations: as read while unchanged (or, for timing this app does
        // not model, while every shape it names is still here); our own
        // timing tree once they are edited.
        body = w.resolveConnections(body)
        var timing = ""
        let modelled = slide.sourceAnimations != nil
        if modelled && slide.animations != slide.sourceAnimations || !modelled && slide.timingXML == nil {
            if !slide.animations.isEmpty {
                let written = w.written
                let text = Set(slide.shapes.filter { $0.text != nil }.map(\.id))
                timing = AnimationXML.write(slide.animations, spid: { written[$0] }, textShapes: text)
            }
        } else if let t = slide.timingXML {
            let named = t.components(separatedBy: "spid=\"").dropFirst().compactMap { Int($0.prefix { $0.isNumber }) }
            if Set(named).isSubset(of: w.usedIds) {
                // Likewise an animation's sound (`p:sndTgt r:embed`).
                if t.containsSubstring("r:embed"), let src = slide.carryPart, let p = source {
                    timing = w.kept(t, sourcePart: src, package: p, builder: &b, patch: nil)
                } else {
                    timing = t
                }
                for (prefix, uri) in [("p14", "http://schemas.microsoft.com/office/powerpoint/2010/main"),
                                      ("mc", "http://schemas.openxmlformats.org/markup-compatibility/2006")]
                where t.containsSubstring("\(prefix):") && !ns.containsSubstring("xmlns:\(prefix)=") {
                    ns += " xmlns:\(prefix)=\"\(uri)\""
                }
            }
        }
        // A sound or movie put here plays when clicked: PowerPoint's own media
        // timing, added to the slide's own animations when it has any.
        let writtenIds = w.written
        let clips: [(spid: Int, isVideo: Bool)] = slide.shapes.compactMap { sh in
            guard let m = sh.media, !m.existing, let id = writtenIds[sh.id] else { return nil }
            return (id, m.isVideo)
        }
        timing = timing.isEmpty ? MediaTiming.write(clips) : MediaTiming.merge(clips, into: timing)
        rels += w.rels
        rels += links.rels
        // The colour map as read when the slide was; a slide of ours maps
        // through the master.
        let clrMapOvr = slide.clrMapOvrXML.map { $0.containsSubstring("overrideClrMapping") ? $0 : "" }
            .flatMap { $0.isEmpty ? nil : $0 } ?? "<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>"
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <p:sld \(ns)\(hidden)><p:cSld>\(bg)<p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>\(body)</p:spTree>\(custData)\(controls)\(slide.cSldExtLstXML ?? "")</p:cSld>\(clrMapOvr)\(transition)\(timing)\(slide.extLstXML ?? "")</p:sld>
        """

        // Notes, when there are any and a notes master to hang them on.
        let hasText = !slide.notes.paragraphs.allSatisfy({ $0.text.isEmpty })
        // A notes page the file had is kept as read while its text is unchanged (or it holds only placeholders: date, number,
        // slide image), so its own shapes, ids, locks and run properties survive; the rewrite keeps only the note text.
        // Its rels are rewritten (master and slide), so a page that points at anything else by r:id is rebuilt instead.
        var keptNotesXML: Data? = nil
        if let notesMaster, let src = slide.carryPart, let p = source,
           let np = p.rel(src, kind: "notesSlide")?.target, let data = p.parts[np],
           let tree = p.xml(np)?.first("p:cSld")?.first("p:spTree"),
           slide.sourceNotes == slide.notes
               && !["r:id=\"", "r:embed=\"", "r:link=\"", "r:pict=\""].contains(where: { String(decoding: data, as: UTF8.self).containsSubstring($0) })
               || !hasText && !tree.all("p:sp").contains(where: { sp in
               sp.first("p:nvSpPr")?.first("p:nvPr")?.first("p:ph")?["type"] == "body"
                   && sp.all("a:t").contains { !($0.text ?? "").isEmpty } }) { keptNotesXML = data }
        if let notesMaster, hasText || keptNotesXML != nil {
            let notesPart = "ppt/notesSlides/notesSlide\(number).xml"
            if let kept = keptNotesXML { b.add(notesPart, String(decoding: kept, as: UTF8.self), type: CT.notesSlide) }
            else { b.add(notesPart, PptxTemplates.notesSlide(PptxText.notesParagraphs(slide.notes)), type: CT.notesSlide) }
            b.rels(notesPart, [
                Rel(id: "rId1", type: RT.notesMaster, target: Pptx.relative(notesMaster, from: notesPart)),
                Rel(id: "rId2", type: RT.slide, target: Pptx.relative(part, from: notesPart)),
            ])
            rels.append(Rel(id: "rIdNotes", type: RT.notesSlide, target: Pptx.relative(notesPart, from: part)))
        }
        b.add(part, xml, type: CT.slide)
        b.rels(part, rels)
    }

    private static func _transition(_ t: SlideTransition, namespaces ns: inout String) -> String {
        if let raw = t.kept {
            for (prefix, uri) in [("mc", "http://schemas.openxmlformats.org/markup-compatibility/2006"),
                                  ("p14", "http://schemas.microsoft.com/office/powerpoint/2010/main")]
            where raw.containsSubstring("\(prefix):") && !ns.containsSubstring("xmlns:\(prefix)=") {
                ns += " xmlns:\(prefix)=\"\(uri)\""
            }
            // (Its Advance Slide settings are the ones set here: swapped into each transition tag.)
            var out = ""
            var rest = raw
            while let r = rest.rangeOfSubstring("<p:transition ") ?? rest.rangeOfSubstring("<p:transition>")
                    ?? rest.rangeOfSubstring("<p:transition/>") {
                out += rest[..<r.lowerBound] + "<p:transition"
                let tail = String(rest[rest.index(r.lowerBound, offsetBy: "<p:transition".count)...])
                guard let close = tail.firstIndex(of: ">") else { rest = tail; break }
                // Its attributes (each with its leading space), the self-closing slash set aside.
                var attrs = String(tail[..<close])
                let selfClosing = attrs.hasSuffix("/")
                if selfClosing { attrs.removeLast() }
                for name in ["advClick", "advTm"] {
                    if let a = attrs.rangeOfSubstring(" \(name)=\""),
                       let e = attrs.rangeOfSubstring("\"", in: a.upperBound ..< attrs.endIndex) {
                        attrs = attrs.replacingSubrange(a.lowerBound ..< e.upperBound, with: "")
                    }
                }
                if !t.advanceOnClick { attrs += " advClick=\"0\"" }
                if let after = t.advanceAfter { attrs += " advTm=\"\(Int((after * 1000).rounded()))\"" }
                out += attrs + (selfClosing ? "/" : "")
                rest = String(tail[close...])
            }
            return out + rest
        }
        // Advance Slide is attributes of the transition itself; a slide that advances only on a click
        // and has no effect writes no transition at all.
        let plainAdvance = t.advanceOnClick && t.advanceAfter == nil
        guard t.kind != .none || !plainAdvance else { return "" }
        let spd = t.duration <= 0.5 ? "fast" : t.duration >= 1.0 ? "slow" : "med"
        let effect: String
        switch t.kind {
        case .fade: effect = "<p:fade/>"
        case .push: effect = "<p:push dir=\"\(t.direction.rawValue)\"/>"
        case .wipe: effect = "<p:wipe dir=\"\(t.direction.rawValue)\"/>"
        case .cover: effect = "<p:cover dir=\"\(t.direction.rawValue)\"/>"
        case .pull: effect = "<p:pull dir=\"\(t.direction.rawValue)\"/>"
        case .split: effect = "<p:split orient=\"\(t.vertical ? "vert" : "horz")\" dir=\"\(t.inward ? "in" : "out")\"/>"
        case .zoom: effect = "<p:zoom dir=\"\(t.zoomIn ? "in" : "out")\"/>"
        case .none: effect = ""
        }
        var advance = t.advanceOnClick ? "" : " advClick=\"0\""
        if let after = t.advanceAfter { advance += " advTm=\"\(Int((after * 1000).rounded()))\"" }
        let plain = "<p:transition spd=\"\(spd)\"\(advance)>\(effect)</p:transition>"
        guard t.kind != .none else { return plain }
        // PowerPoint 2010+ writes the exact duration in p14:dur inside mc:AlternateContent, the plain
        // transition (speed word only) as the fallback.
        for (prefix, uri) in [("mc", "http://schemas.openxmlformats.org/markup-compatibility/2006"),
                              ("p14", "http://schemas.microsoft.com/office/powerpoint/2010/main")]
        where !ns.containsSubstring("xmlns:\(prefix)=") { ns += " xmlns:\(prefix)=\"\(uri)\"" }
        let ms = Int((t.duration * 1000).rounded())
        return "<mc:AlternateContent><mc:Choice Requires=\"p14\"><p:transition spd=\"\(spd)\"\(advance) p14:dur=\"\(ms)\">\(effect)</p:transition></mc:Choice><mc:Fallback>\(plain)</mc:Fallback></mc:AlternateContent>"
    }

    /// `p:custShowLst` written from the deck's custom shows (slides by their
    /// `rIdS<n>` ids), replacing the file's own; none left, none written.
    static func _setCustomShows(_ pres: String, _ state: DeckState) -> String {
        var out = pres
        if let r = _elementRange("p:custShowLst", in: out) { out = out.replacingSubrange(r, with: "") }
        var shows = ""
        for cs in state.customShows {
            let slides = cs.slides.compactMap { sid in state.slides.firstIndex { $0.id == sid } }
            guard !slides.isEmpty else { continue }
            shows += "<p:custShow name=\"\(PptxXML.escape(cs.name, attribute: true))\" id=\"\(cs.id)\"><p:sldLst>"
                + slides.map { "<p:sld r:id=\"rIdS\($0 + 1)\"/>" }.joined() + "</p:sldLst></p:custShow>"
        }
        guard !shows.isEmpty else { return out }
        let list = "<p:custShowLst>" + shows + "</p:custShowLst>"
        for marker in ["<p:photoAlbum", "<p:custDataLst", "<p:kinsoku", "<p:defaultTextStyle", "<p:modifyVerifier", "<p:extLst", "</p:presentation>"] {
            if let r = out.findRange(of: marker) { return out.replacingSubrange(r.lowerBound ..< r.lowerBound, with: list) }
        }
        return out
    }

    /// The span of `<name …>…</name>` or `<name …/>` in `s`.
    static func _elementRange(_ name: String, in s: String) -> Range<String.Index>? {
        guard let start = s.findRange(of: "<\(name)"),
              let close = s.findRange(of: ">", in: start.upperBound ..< s.endIndex) else { return nil }
        if s[s.index(before: close.lowerBound)] == "/" { return start.lowerBound ..< close.upperBound }
        guard let end = s.findRange(of: "</\(name)>", in: close.upperBound ..< s.endIndex) else { return nil }
        return start.lowerBound ..< end.upperBound
    }

    /// `p:showPr` in a `presProps` part, from the deck's show settings. A file
    /// without one, and a deck with the defaults, is left as it was; the
    /// pen colour and extensions the file had are kept.
    static func _applyShowPr(_ xml: String, _ show: ShowSettings) -> String {
        var out = xml, kept = ""
        let had = _elementRange("p:showPr", in: out)
        if let had {
            let old = String(out[had])
            for name in ["p:penClr", "p:extLst"] {
                if let r = _elementRange(name, in: old) { kept += old[r] }
            }
            out = out.replacingSubrange(had, with: "")
        } else if show == ShowSettings() { return xml }
        var attrs = ""
        if show.loop || show.kind == .kiosk { attrs += " loop=\"1\"" }
        if !show.narration { attrs += " showNarration=\"0\"" }
        if !show.useTimings { attrs += " useTimings=\"0\"" }
        let type = show.kind == .window ? "<p:browse/>" : show.kind == .kiosk ? "<p:kiosk/>" : "<p:present/>"
        let range: String
        switch show.range {
        case .all: range = "<p:sldAll/>"
        case .slides(let a, let b): range = "<p:sldRg st=\"\(min(a, b))\" end=\"\(max(a, b))\"/>"
        case .custom(let id): range = "<p:custShow id=\"\(id)\"/>"
        }
        let el = "<p:showPr\(attrs)>" + type + range + kept + "</p:showPr>"
        if let r = _elementRange("p:presentationPr", in: out) {
            let whole = String(out[r])
            if whole.hasSuffix("/>") {
                let open = String(whole.dropLast(2))
                return out.replacingSubrange(r, with: open + ">" + el + "</p:presentationPr>")
            }
            for marker in ["<p:clrMru", "<p:extLst", "</p:presentationPr>"] {
                if let m = out.findRange(of: marker) { return out.replacingSubrange(m.lowerBound ..< m.lowerBound, with: el) }
            }
        }
        return out
    }

    /// Apply to All: the masters' background becomes `fill`, and no layout keeps one of its own over it.
    static func _masterPictureName(_ image: ImageAttachment) -> String { "master_background.\(PptxText.imageExtension(image))" }

    /// `p:sldSz` of a presentation part, in points.
    static func _slideSize(_ presXML: String) -> Size? {
        guard let r = presXML.findRange(of: "<p:sldSz"), let e = presXML.findRange(of: ">", in: r.upperBound ..< presXML.endIndex) else { return nil }
        let tag = String(presXML[r.upperBound ..< e.lowerBound])
        func attr(_ n: String) -> Double? {
            guard let a = tag.findRange(of: " \(n)=\""), let q = tag.findRange(of: "\"", in: a.upperBound ..< tag.endIndex) else { return nil }
            return Double(String(tag[a.upperBound ..< q.lowerBound]))
        }
        guard let cx = attr("cx"), let cy = attr("cy"), cx > 0, cy > 0 else { return nil }
        return Size(cx / Pptx.emu, cy / Pptx.emu)
    }

    /// The file's own master and layouts after a Slide Size change: each shape keeps its proportions and its centre's
    /// place, and the sizes, spacing and indents of its text scale by the same factor as the slides' own.
    private static func _scaleMasters(from old: Size, to new: Size, _ scaling: DeckController.SlideScaling, in b: inout PackageBuilder) {
        let sx = new.width / old.width, sy = new.height / old.height
        let k = DeckController.slideScale(from: old, to: new, scaling)
        for part in Array(b.parts.keys) where (part.hasPrefix("ppt/slideMasters/slideMaster") || part.hasPrefix("ppt/slideLayouts/slideLayout")) && part.hasSuffix(".xml") {
            guard let d = b.parts[part], let x = String(data: d, encoding: .utf8) else { continue }
            b.parts[part] = Data(_scaledShapes(x, sx: sx, sy: sy, k: k).utf8)
        }
    }

    static func _scaledShapes(_ x: String, sx: Double, sy: Double, k: Double) -> String {
        let src = Array(x.utf8)
        func find(_ pat: String, from: Int) -> Int? {
            let p = Array(pat.utf8)
            guard src.count >= p.count, from <= src.count - p.count else { return nil }
            var i = from
            while i <= src.count - p.count {
                if src[i] == p[0], Array(src[i ..< i + p.count]) == p { return i }
                i += 1
            }
            return nil
        }
        /// The integer in ` name="…"` inside src[from ..< to], with the range of its digits.
        func attr(_ name: String, _ from: Int, _ to: Int) -> (Double, Range<Int>)? {
            let key = Array((" " + name + "=\"").utf8)
            var i = from
            while i + key.count < to {
                if src[i] == key[0], Array(src[i ..< i + key.count]) == key {
                    let s0 = i + key.count
                    var e = s0
                    while e < to, src[e] != UInt8(ascii: "\"") { e += 1 }
                    guard let v = Double(String(decoding: src[s0 ..< e], as: UTF8.self)) else { return nil }
                    return (v, s0 ..< e)
                }
                i += 1
            }
            return nil
        }
        // Edits: byte range → replacement.
        var edits: [(Range<Int>, String)] = []
        // A shape's place: `<a:off x y/>` then `<a:ext cx cy/>`, together, so the centre is kept.
        var at = 0
        while let o = find("<a:off ", from: at) {
            at = o + 7
            guard let oe = find("/>", from: o), let e0 = find("<a:ext ", from: oe + 2), e0 - (oe + 2) <= 8,
                  let ee = find("/>", from: e0),
                  let (ox, rx) = attr("x", o, oe), let (oy, ry) = attr("y", o, oe),
                  let (cx, rcx) = attr("cx", e0, ee), let (cy, rcy) = attr("cy", e0, ee) else { continue }
            let w = cx * k, h = cy * k
            edits.append((rx, String(Int(((ox + cx / 2) * sx - w / 2).rounded()))))
            edits.append((ry, String(Int(((oy + cy / 2) * sy - h / 2).rounded()))))
            edits.append((rcx, String(Int(w.rounded()))))
            edits.append((rcy, String(Int(h.rounded()))))
            at = ee
        }
        // Text: sizes (hundredths of a point), indents and margins (EMU) and `a:spcPts val` (hundredths of a point).
        for name in ["sz", "marL", "marR", "indent", "lIns", "rIns", "tIns", "bIns"] {
            var i = 0
            while let p = find(" \(name)=\"", from: i) {
                i = p + 1
                if let (v, r) = attr(name, p, min(src.count, p + name.utf8.count + 16)) { edits.append((r, String(Int((v * k).rounded())))) }
            }
        }
        var i = 0
        while let p = find("<a:spcPts val=\"", from: i) {
            i = p + 1
            if let (v, r) = attr("val", p, min(src.count, p + 30)) { edits.append((r, String(Int((v * k).rounded())))) }
        }
        var out: [UInt8] = []
        var pos = 0
        for (r, text) in edits.sorted(by: { $0.0.lowerBound < $1.0.lowerBound }) where r.lowerBound >= pos {
            out += src[pos ..< r.lowerBound]
            out += Array(text.utf8)
            pos = r.upperBound
        }
        out += src[pos...]
        return String(decoding: out, as: UTF8.self)
    }

    private static func _setMasterBackground(_ fill: SlideFill, in b: inout PackageBuilder) {
        let bg = PptxTemplates.backgroundXML(fill)
        if let pic = fill.image {
            // The picture is a part of its own, reached from the masters only.
            let name = _masterPictureName(pic)
            b.addBinary("ppt/media/" + name, pic.data)
            for part in Array(b.parts.keys) where part.hasPrefix("ppt/slideMasters/slideMaster") && part.hasSuffix(".xml") {
                let rp = Pptx.relsPath(part)
                guard let d = b.parts[rp], var x = String(data: d, encoding: .utf8), let end = x.findRange(of: "</Relationships>") else { continue }
                x.replaceSubrange(end.lowerBound ..< end.lowerBound, with: "<Relationship Id=\"\(PptxTemplates.masterPictureRID)\" Type=\"\(RT.image)\" Target=\"../media/\(name)\"/>")
                b.parts[rp] = Data(x.utf8)
            }
        }
        func edit(_ part: String, _ f: (String) -> String) {
            if let d = b.parts[part], let x = String(data: d, encoding: .utf8) { b.parts[part] = Data(f(x).utf8) }
        }
        func dropBackground(_ x: String) -> String {
            guard let c = x.findRange(of: "<p:cSld"), let open = x.findRange(of: "<p:bg>", in: c.upperBound ..< x.endIndex),
                  let close = x.findRange(of: "</p:bg>", in: open.upperBound ..< x.endIndex) else { return x }
            // Only a background that opens the shape tree's parent: the first child of cSld.
            guard let gt = x.findRange(of: ">", in: c.upperBound ..< x.endIndex), x[gt.upperBound ..< open.lowerBound].allSatisfy({ $0 == " " || $0 == "\n" }) else { return x }
            return x.replacingSubrange(open.lowerBound ..< close.upperBound, with: "")
        }
        for part in Array(b.parts.keys) {
            if part.hasPrefix("ppt/slideMasters/slideMaster"), part.hasSuffix(".xml") {
                edit(part) { x in
                    let y = dropBackground(x)
                    guard let c = y.findRange(of: "<p:cSld"), let gt = y.findRange(of: ">", in: c.upperBound ..< y.endIndex) else { return y }
                    return y.replacingSubrange(gt.upperBound ..< gt.upperBound, with: bg)
                }
            } else if part.hasPrefix("ppt/slideLayouts/slideLayout"), part.hasSuffix(".xml") {
                edit(part, dropBackground)
            }
        }
    }

    /// The file's own theme part with `theme`'s colours (dark and light 1, the six accents) and Latin fonts; everything else in it is left alone.
    static func _recoloured(_ xml: String, _ theme: DeckTheme) -> String {
        var out = xml
        let accents = theme.accents + Array(repeating: Color(0xFF808080), count: max(0, 6 - theme.accents.count))
        func swap(_ name: String, _ c: Color) {
            guard let open = out.findRange(of: "<a:\(name)>"), let close = out.findRange(of: "</a:\(name)>", in: open.upperBound ..< out.endIndex) else { return }
            out = out.replacingSubrange(open.lowerBound ..< close.upperBound,
                                        with: "<a:\(name)><a:srgbClr val=\"\(PptxText.hex(c))\"/></a:\(name)>")
        }
        swap("dk1", theme.text)
        swap("lt1", theme.background)
        for i in 0 ..< 6 { swap("accent\(i + 1)", accents[i]) }
        func font(_ group: String, _ face: String) {
            guard let g = out.findRange(of: "<a:\(group)>"), let l = out.findRange(of: "<a:latin ", in: g.upperBound ..< out.endIndex),
                  let e = out.findRange(of: "/>", in: l.upperBound ..< out.endIndex) else { return }
            out = out.replacingSubrange(l.lowerBound ..< e.upperBound, with: "<a:latin typeface=\"\(PptxXML.escape(face, attribute: true))\"/>")
        }
        font("majorFont", theme.headingFont)
        font("minorFont", theme.bodyFont)
        return out
    }

    static let sectionExtUri = "{521415D9-36F7-43E2-AB2F-B90AF26B5E84}"

    /// The deck's sections as `p14:sectionLst` in the presentation's extension list, written from the deck's own sections and each slide's tag (the file's old list is replaced; other extensions stay).
    static func _setSections(_ pres: String, _ state: DeckState, slideIds: [Int]) -> String {
        var out = pres
        // Drop the old one: its ext element, or the whole list when it was the only extension.
        if let u = out.findRange(of: "uri=\"\(sectionExtUri)\""),
           let s = out.findRange(of: "<p:ext ", backwards: true, in: out.startIndex ..< u.lowerBound),
           let e = out.findRange(of: "</p:ext>", in: u.upperBound ..< out.endIndex) {
            out = out.replacingSubrange(s.lowerBound ..< e.upperBound, with: "")
            if let l = out.findRange(of: "<p:extLst></p:extLst>") { out = out.replacingSubrange(l, with: "") }
        }
        guard !state.sections.isEmpty else { return out }
        var xml = "<p14:sectionLst xmlns:p14=\"http://schemas.microsoft.com/office/powerpoint/2010/main\">"
        for sec in state.sections {
            let ids = state.slides.indices.filter { state.slides[$0].section == sec.guid }.map { "<p14:sldId id=\"\(slideIds[$0])\"/>" }
            xml += "<p14:section name=\"\(PptxXML.escape(sec.name, attribute: true))\" id=\"\(PptxXML.escape(sec.guid, attribute: true))\"><p14:sldIdLst>\(ids.joined())</p14:sldIdLst></p14:section>"
        }
        xml += "</p14:sectionLst>"
        let ext = "<p:ext uri=\"\(sectionExtUri)\">\(xml)</p:ext>"
        // PowerPoint puts it first in the list.
        if let open = out.findRange(of: "<p:extLst>") { return out.replacingSubrange(open, with: "<p:extLst>" + ext) }
        if out.findRange(of: "<p:extLst/>") != nil { return out.replacingAll("<p:extLst/>", with: "<p:extLst>\(ext)</p:extLst>") }
        return out.replacingAll("</p:presentation>", with: "<p:extLst>\(ext)</p:extLst></p:presentation>")
    }

    private static func _insertAfter(_ marker: String, in s: String, _ insert: String) -> String {
        guard let r = s.findRange(of: marker) else { return s }
        return s.replacingSubrange(r, with: marker + insert)
    }

    /// Replace `<name …>…</name>` (or `<name …/>`) in `s`; when absent,
    /// insert the replacement after `after` (or `orAfter`).
    private static func _replaceElement(_ name: String, in s: String, with replacement: String,
                                        after: String, orAfter: String?) -> String {
        if let start = s.findRange(of: "<\(name)") {
            if let selfClose = s.findRange(of: "/>", in: start.upperBound ..< s.endIndex),
               s.findRange(of: ">", in: start.upperBound ..< s.endIndex)?.lowerBound == s.index(before: selfClose.upperBound) {
                return s.replacingSubrange(start.lowerBound ..< selfClose.upperBound, with: replacement)
            }
            if let end = s.findRange(of: "</\(name)>", in: start.upperBound ..< s.endIndex) {
                return s.replacingSubrange(start.lowerBound ..< end.upperBound, with: replacement)
            }
        }
        if s.findRange(of: after) != nil { return _insertAfter(after, in: s, replacement) }
        if let orAfter, s.findRange(of: orAfter) != nil { return _insertAfter(orAfter, in: s, replacement) }
        return s
    }
}

extension Pptx {
    /// `target` as a path relative to the directory of `part`.
    static func relative(_ target: String, from part: String) -> String {
        let from = part.split(separator: "/").dropLast().map(String.init)
        let to = target.split(separator: "/").map(String.init)
        var common = 0
        while common < from.count, common < to.count - 1, from[common] == to[common] { common += 1 }
        let ups = Array(repeating: "..", count: from.count - common)
        return (ups + to[common...]).joined(separator: "/")
    }

    /// The deck as a .pptx file.
    static func write(_ deck: DeckController) throws -> Data {
        if deck.inMasterView { return try deck.masterViewBytes() }
        return try PptxWriter.write(deck.snapshot(), theme: deck.theme, package: deck.package, ownTemplates: deck.ownTemplates, recolourTheme: deck.recolourTheme)
    }
}

// MARK: - Content and relationship types

enum CT {
    private static let pml = "application/vnd.openxmlformats-officedocument.presentationml."
    static let presentation = pml + "presentation.main+xml"
    static let slide = pml + "slide+xml"
    static let layout = pml + "slideLayout+xml"
    static let master = pml + "slideMaster+xml"
    static let notesSlide = pml + "notesSlide+xml"
    static let notesMaster = pml + "notesMaster+xml"
    static let presProps = pml + "presProps+xml"
    static let viewProps = pml + "viewProps+xml"
    static let tableStyles = pml + "tableStyles+xml"
    static let theme = "application/vnd.openxmlformats-officedocument.theme+xml"
    static let core = "application/vnd.openxmlformats-package.core-properties+xml"
    static let app = "application/vnd.openxmlformats-officedocument.extended-properties+xml"
}

enum RT {
    private static let base = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/"
    static let document = base + "officeDocument"
    static let slide = base + "slide"
    static let video = base + "video"
    static let audio = base + "audio"
    static let media2007 = "http://schemas.microsoft.com/office/2007/relationships/media"
    static let layout = base + "slideLayout"
    static let master = base + "slideMaster"
    static let notesSlide = base + "notesSlide"
    static let notesMaster = base + "notesMaster"
    static let theme = base + "theme"
    static let image = base + "image"
    static let hyperlink = base + "hyperlink"
    static let presProps = base + "presProps"
    static let viewProps = base + "viewProps"
    static let tableStyles = base + "tableStyles"
    static let app = base + "extended-properties"
    static let core = "http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties"
}

struct Rel {
    var id: String
    var type: String
    var target: String
    var external = false
}

// MARK: - Package builder

struct PackageBuilder {
    var parts: [String: Data] = [:]
    var overrides: [String: String] = [:]
    var defaults: [String: String] = [
        "rels": "application/vnd.openxmlformats-package.relationships+xml",
        "xml": "application/xml",
        "png": "image/png", "jpeg": "image/jpeg", "jpg": "image/jpeg", "gif": "image/gif",
        "bmp": "image/bmp", "tif": "image/tiff", "tiff": "image/tiff", "svg": "image/svg+xml",
        "emf": "image/x-emf", "wmf": "image/x-wmf",
        // Media a kept sound or movie may carry; a file that declared no
        // type for its own .avi (bnc591147) gets a sound copy regardless.
        "wav": "audio/x-wav", "mp3": "audio/mpeg", "m4a": "audio/mp4", "wma": "audio/x-ms-wma",
        "mp4": "video/mp4", "m4v": "video/mp4", "mov": "video/quicktime", "avi": "video/avi",
        "wmv": "video/x-ms-wmv", "mpg": "video/mpeg", "mpeg": "video/mpeg",
    ]

    mutating func add(_ part: String, _ xml: String, type: String) {
        parts[part] = Data(xml.utf8)
        overrides[part] = type
    }

    mutating func addBinary(_ part: String, _ data: Data) {
        parts[part] = data
    }

    /// The relationships of `part` ("" for the package root).
    mutating func rels(_ part: String, _ rels: [Rel]) {
        let path = part.isEmpty ? "_rels/.rels" : Pptx.relsPath(part)
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
            + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
        for r in rels {
            xml += "<Relationship Id=\"\(PptxXML.escape(r.id, attribute: true))\" Type=\"\(r.type)\" "
                + "Target=\"\(PptxXML.escape(r.target, attribute: true))\"\(r.external ? " TargetMode=\"External\"" : "")/>"
        }
        parts[path] = Data((xml + "</Relationships>").utf8)
    }

    func zip() throws -> Data {
        var ct = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
            + "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">"
        let used = Set(parts.keys.compactMap { $0.split(separator: ".").last.map { String($0).lowercased() } })
        for (ext, type) in defaults.sorted(by: { $0.key < $1.key }) where used.contains(ext) {
            ct += "<Default Extension=\"\(ext)\" ContentType=\"\(type)\"/>"
        }
        for (part, type) in overrides.sorted(by: { $0.key < $1.key }) where parts[part] != nil {
            ct += "<Override PartName=\"/\(part)\" ContentType=\"\(type)\"/>"
        }
        ct += "</Types>"
        // [Content_Types].xml first, as Office writes it; then the rest in a
        // stable order so two saves of one deck are byte-identical.
        var entries = [ZipEntry(name: "[Content_Types].xml", data: Data(ct.utf8))]
        for (name, data) in parts.sorted(by: { $0.key < $1.key }) where name != "[Content_Types].xml" {
            entries.append(ZipEntry(name: name, data: data))
        }
        return try Zip.write(entries)
    }
}

/// Pictures written so far, so one image used on several slides is one part.
struct MediaParts {
    var byId: [String: String] = [:]
    var count = 0
    /// Charts written fresh so far (each with its part and workbook).
    var charts = 0
}

// MARK: - Slide XML

private struct SlideXML {
    let part: String
    let source: PptxPackage?
    var nextId = 2
    var rels: [Rel] = []
    private var _relIds: [String: String] = [:]   // target → id, for this slide

    init(part: String, source: PptxPackage?) {
        self.part = part
        self.source = source
    }

    private var _used = Set<Int>()
    /// The id each shape was written under (deck id → `cNvPr id`), which
    /// the slide's animations name it by.
    private(set) var written: [Int: Int] = [:]
    private var _current: Int? = nil

    /// A connector's glued ends. The target may be written after the connector, so the id is a token
    /// (`@@CXN<deck id>@@`) that `resolveConnections` swaps for the id the target was written under.
    static func _connXML(_ s: ShapeState) -> String {
        var x = ""
        if let c = s.connStart { x += "<a:stCxn id=\"@@CXN\(c.shape)@@\" idx=\"\(c.site)\"/>" }
        if let c = s.connEnd { x += "<a:endCxn id=\"@@CXN\(c.shape)@@\" idx=\"\(c.site)\"/>" }
        return x
    }

    /// Swaps each connection token for its shape's written id; an end whose shape was not written is left out.
    func resolveConnections(_ body: String) -> String {
        guard body.containsSubstring("@@CXN") else { return body }
        var out = ""
        let parts = body.components(separatedBy: "<a:")
        for (i, part) in parts.enumerated() {
            var piece = part
            if i > 0 {
                if (piece.hasPrefix("stCxn ") || piece.hasPrefix("endCxn ")), let a = piece.rangeOfSubstring("@@CXN"),
                   let b = piece.rangeOfSubstring("@@\"", in: a.upperBound..<piece.endIndex) {
                    let n = Int(piece[a.upperBound..<b.lowerBound])
                    if let n, let id = written[n] {
                        piece.replaceSubrange(a.lowerBound..<b.upperBound, with: "\(id)\"")
                    } else if let close = piece.rangeOfSubstring("/>") {
                        piece.removeSubrange(piece.startIndex..<close.upperBound)
                        out += piece
                        continue
                    }
                }
                out += "<a:"
            }
            out += piece
        }
        return out
    }

    /// The alt text to set on a kept element's `cNvPr`: nil while it is as it was read.
    /// A kept picture has no read shape: `pictureAlt` is the descr its kept record holds.
    private func _altChange(_ s: ShapeState, pictureAlt: String?? = nil) -> (descr: String?, title: String?)? {
        if let r = s.readShape {
            return r.altText != s.altText || r.altTitle != s.altTitle ? (s.altText, s.altTitle) : nil
        }
        if let was = pictureAlt, was != s.altText { return (s.altText, s.altTitle) }
        return nil
    }

    private mutating func _id(_ preferred: Int? = nil) -> Int {
        let id: Int
        if let p = preferred, p > 1, !_used.contains(p) {
            _used.insert(p)
            id = p
        } else {
            while _used.contains(nextId) { nextId += 1 }
            _used.insert(nextId)
            id = nextId
            nextId += 1
        }
        if let c = _current, written[c] == nil { written[c] = id }
        return id
    }

    /// The ids written so far, for checking the slide's kept animations.
    var usedIds: Set<Int> { _used }

    private mutating func _rel(_ type: String, _ target: String, external: Bool = false, preferred: String) -> String {
        let key = type + "|" + target
        if let id = _relIds[key] { return id }
        var id = preferred
        var n = 1
        while rels.contains(where: { $0.id == id }) { n += 1; id = preferred + "_\(n)" }
        rels.append(Rel(id: id, type: type, target: target, external: external))
        _relIds[key] = id
        return id
    }

    private static func _emu(_ v: Double) -> Int { Int((v * Pptx.emu).rounded()) }

    /// Sets or clears `noChangeAspect` on a kept shape's own lock element (`spLocks`, `picLocks`).
    static func _lockEdit(_ on: Bool) -> (XNode) -> Void {
        return { node in
            guard let c = node.first("p:nvSpPr")?.first("p:cNvSpPr") ?? node.first("p:nvPicPr")?.first("p:cNvPicPr")
                    ?? node.first("p:nvGraphicFramePr")?.first("p:cNvGraphicFramePr") else { return }
            let name = node.name == "p:pic" ? "a:picLocks" : node.name == "p:graphicFrame" ? "a:graphicFrameLocks" : "a:spLocks"
            let l = c.first(name) ?? { let n = XNode(name: name, attrs: [:]); c.children.insert(n, at: 0); return n }()
            l.attrs["noChangeAspect"] = on ? "1" : nil
        }
    }

    /// An elbow's adjust values: `adj1`... in order, as `a:gd` guides.
    private static func _avLst(_ adjusts: [String: Double]) -> String {
        guard !adjusts.isEmpty else { return "<a:avLst/>" }
        return "<a:avLst>" + adjusts.keys.sorted().map { "<a:gd name=\"\($0)\" fmla=\"val \(Int((adjusts[$0] ?? 0).rounded()))\"/>" }.joined() + "</a:avLst>"
    }

    private static func _xfrm(_ f: Rect, rotation: Double, tag: String = "a:xfrm", flipH: Bool = false, flipV: Bool = false) -> String {
        var attrs = ""
        if rotation != 0 { attrs += " rot=\"\(Int((rotation * 60000).rounded()))\"" }
        if flipH { attrs += " flipH=\"1\"" }
        if flipV { attrs += " flipV=\"1\"" }
        return "<\(tag)\(attrs)><a:off x=\"\(_emu(f.left))\" y=\"\(_emu(f.top))\"/>"
            + "<a:ext cx=\"\(_emu(max(0, f.width)))\" cy=\"\(_emu(max(0, f.height)))\"/></\(tag)>"
    }

    /// A picture's part (one per image however many slides use it) and this
    /// slide's relationship to it.
    private mutating func _media(_ image: ImageAttachment, media: inout MediaParts, builder: inout PackageBuilder) -> String {
        let mediaPart: String
        if let existing = media.byId[image.id] {
            mediaPart = existing
        } else {
            media.count += 1
            mediaPart = "ppt/media/slides_image\(media.count).\(PptxText.imageExtension(image))"
            media.byId[image.id] = mediaPart
            builder.addBinary(mediaPart, image.data)
        }
        return _rel(RT.image, Pptx.relative(mediaPart, from: part), preferred: "rIdImg\(media.count)")
    }

    /// An `a:ln` with its width and/or its fill element swapped, everything else kept.
    /// `a:outerShdw` for a shape shadow (offset as dx, dy in points).
    static func _outerShadowXML(_ sh: CharShadow) -> String {
        let dist = Int((hypot(sh.dx, sh.dy) * Pptx.emu).rounded())
        var deg = atan2(sh.dy, sh.dx) * 180 / .pi
        if deg < 0 { deg += 360 }
        let alpha = sh.color.alpha < 255 ? "<a:alpha val=\"\(Int((Double(sh.color.alpha) / 255 * 100000).rounded()))\"/>" : ""
        let rgb = String(sh.color.value & 0xFFFFFF, radix: 16, uppercase: true)
        let hex = String(repeating: "0", count: max(0, 6 - rgb.count)) + rgb
        return "<a:outerShdw blurRad=\"\(Int((sh.blur * Pptx.emu).rounded()))\" dist=\"\(dist)\" dir=\"\(Int((deg * 60000).rounded()))\" algn=\"ctr\" rotWithShape=\"0\">"
            + "<a:srgbClr val=\"\(hex)\">\(alpha)</a:srgbClr></a:outerShdw>"
    }

    /// The shape's effects with the camera of its `a:scene3d` set to `name` (the light rig and `a:sp3d` stay). With
    /// no scene, one is added unless the camera is square on.
    static func _effectsWithCamera(_ effects: String, _ name: String) -> String {
        let camera = "<a:camera prst=\"\(PptxXML.escape(name, attribute: true))\"/>"
        if let a = effects.rangeOfSubstring("<a:scene3d"), let e = effects.rangeOfSubstring("</a:scene3d>", in: a.lowerBound..<effects.endIndex),
           let c0 = effects.rangeOfSubstring("<a:camera", in: a.lowerBound..<e.lowerBound) {
            var out = effects
            let c1: Range<String.Index>
            if let end = out.rangeOfSubstring("</a:camera>", in: c0.lowerBound..<e.lowerBound) { c1 = c0.lowerBound..<end.upperBound }
            else if let end = out.rangeOfSubstring("/>", in: c0.lowerBound..<e.lowerBound) { c1 = c0.lowerBound..<end.upperBound }
            else { return effects }
            out.replaceSubrange(c1, with: camera)
            return out
        }
        if name == "orthographicFront" { return effects }
        let scene = "<a:scene3d>\(camera)<a:lightRig rig=\"threePt\" dir=\"t\"/></a:scene3d>"
        if let sp = effects.rangeOfSubstring("<a:sp3d") { var out = effects; out.insert(contentsOf: scene, at: sp.lowerBound); return out }
        return effects + scene
    }

    /// An arrowhead as `a:headEnd` / `a:tailEnd`; sizes are the multiples of the line width the reader gives (2, 3, 5).
    static func _endXML(_ tag: String, _ e: LineEnd?) -> String {
        guard let e else { return "" }
        func size(_ v: Double) -> String { v <= 2 ? "sm" : v >= 5 ? "lg" : "med" }
        return "<a:\(tag) type=\"\(PptxXML.escape(e.kind, attribute: true))\" w=\"\(size(e.width))\" len=\"\(size(e.length))\"/>"
    }

    static func _endsXML(_ s: ShapeState) -> String { _endXML("headEnd", s.headEnd) + _endXML("tailEnd", s.tailEnd) }

    static func _dashXML(_ dash: String?) -> String {
        guard let dash, !dash.isEmpty, dash != "solid" else { return "" }
        return "<a:prstDash val=\"\(PptxXML.escape(dash, attribute: true))\"/>"
    }

    static func _patchedLine(_ ln: String, widthEMU: Int?, fill: String?, dash: String?? = nil, ends: String? = nil) -> String {
        guard let open = ln.firstIndex(of: ">") else { return ln }
        var head = String(ln[...open])
        var rest = String(ln[ln.index(after: open)...])
        let selfClosing = head.hasSuffix("/>")
        if selfClosing { head = String(head.dropLast(2)) + ">"; rest = "</a:ln>" }
        if let w = widthEMU {
            if let r = head.rangeOfSubstring(" w=\"") , let e = head[r.upperBound...].firstIndex(of: "\"") {
                head.replaceSubrange(r.upperBound ..< e, with: String(w))
            } else {
                head = String(head.dropLast()) + " w=\"\(w)\">"
            }
        }
        var start = rest.startIndex
        for tag in ["<a:noFill/>", "<a:solidFill>", "<a:gradFill", "<a:pattFill"] where rest.hasPrefix(tag) {
            if tag == "<a:noFill/>" { start = rest.index(rest.startIndex, offsetBy: tag.count); break }
            let close = tag == "<a:solidFill>" ? "</a:solidFill>" : (tag == "<a:gradFill" ? "</a:gradFill>" : "</a:pattFill>")
            if let r = rest.rangeOfSubstring(close) { start = r.upperBound }
            break
        }
        var tail = String(rest[start...])
        var fillPart = String(rest[..<start])
        if let fill { fillPart = fill }
        if let dash {
            if tail.hasPrefix("<a:prstDash"), let e = tail.rangeOfSubstring("/>") { tail = String(tail[e.upperBound...]) }
            else if tail.hasPrefix("<a:custDash>"), let e = tail.rangeOfSubstring("</a:custDash>") { tail = String(tail[e.upperBound...]) }
            tail = _dashXML(dash) + tail
        }
        if let ends {
            // The file's own arrowheads give way to the chosen ones; they sit last, before any extension list.
            for tag in ["<a:headEnd", "<a:tailEnd"] {
                if let r = tail.rangeOfSubstring(tag), let e = tail[r.lowerBound...].rangeOfSubstring("/>") { tail.removeSubrange(r.lowerBound ..< e.upperBound) }
            }
            if let x = tail.rangeOfSubstring("<a:extLst") { tail.insert(contentsOf: ends, at: x.lowerBound) }
            else if let c = tail.rangeOfSubstring("</a:ln>") { tail.insert(contentsOf: ends, at: c.lowerBound) }
            else { tail += ends }
        }
        rest = fillPart + tail
        return head + rest
    }

    /// A fill element: solid, linear gradient or stretched picture.
    mutating func fill(_ f: SlideFill, media: inout MediaParts, builder: inout PackageBuilder) -> String {
        if f.isPattern, let preset = f.patternPreset, let fg = f.patternFg, let bg = f.patternBg {
            return "<a:pattFill prst=\"\(preset)\"><a:fgClr><a:srgbClr val=\"\(PptxText.hex(fg))\"/></a:fgClr><a:bgClr><a:srgbClr val=\"\(PptxText.hex(bg))\"/></a:bgClr></a:pattFill>"
        }
        if let image = f.image {
            let rid = _media(image, media: &media, builder: &builder)
            return PptxTemplates.blipFillXML(f, rid: rid)
        }
        if f.stops.count >= 2 {
            let stops = f.stops.map { "<a:gs pos=\"\(Int(($0.position * 100000).rounded()))\"><a:srgbClr val=\"\(PptxText.hex($0.color))\">\($0.color.alpha < 255 ? "<a:alpha val=\"\($0.color.alpha * 100000 / 255)\"/>" : "")</a:srgbClr></a:gs>" }.joined()
            if let path = f.path {
                // A radial (or rectangular) blend out from the fill-to point: `a:path`, as Format Background makes it.
                func v(_ x: Double) -> Int { Int((x * 100000).rounded()) }
                let to = f.fillTo
                return "<a:gradFill rotWithShape=\"1\"><a:gsLst>\(stops)</a:gsLst><a:path path=\"\(path.rawValue)\"><a:fillToRect l=\"\(v(to.left))\" t=\"\(v(to.top))\" r=\"\(v(1 - to.right))\" b=\"\(v(1 - to.bottom))\"/></a:path></a:gradFill>"
            }
            return "<a:gradFill rotWithShape=\"1\"><a:gsLst>\(stops)</a:gsLst><a:lin ang=\"\(Int((f.angle * 60000).rounded()))\" scaled=\"0\"/></a:gradFill>"
        }
        return Self._fill(f.color ?? Color(0xFFFFFFFF))
    }

    private static func _crop(_ c: EdgeInsets?) -> String {
        guard let c, c != .zero else { return "" }
        func v(_ x: Double) -> Int { Int((x * 100000).rounded()) }
        return "<a:srcRect l=\"\(v(c.left))\" t=\"\(v(c.top))\" r=\"\(v(c.right))\" b=\"\(v(c.bottom))\"/>"
    }

    /// PowerPoint's default style refs for a shape it draws (a line's: lnRef 1, no fill).
    static func _themeStyle(line: Bool) -> String {
        line
            ? "<p:style><a:lnRef idx=\"1\"><a:schemeClr val=\"accent1\"/></a:lnRef><a:fillRef idx=\"0\"><a:schemeClr val=\"accent1\"/></a:fillRef>"
                + "<a:effectRef idx=\"0\"><a:schemeClr val=\"accent1\"/></a:effectRef><a:fontRef idx=\"minor\"><a:schemeClr val=\"tx1\"/></a:fontRef></p:style>"
            : "<p:style><a:lnRef idx=\"2\"><a:schemeClr val=\"accent1\"><a:shade val=\"50000\"/></a:schemeClr></a:lnRef>"
                + "<a:fillRef idx=\"1\"><a:schemeClr val=\"accent1\"/></a:fillRef><a:effectRef idx=\"0\"><a:schemeClr val=\"accent1\"/></a:effectRef>"
                + "<a:fontRef idx=\"minor\"><a:schemeClr val=\"lt1\"/></a:fontRef></p:style>"
    }

    private static func _fill(_ c: Color?, scheme: String? = nil) -> String {
        guard let c else { return "<a:noFill/>" }
        let alpha = (c.value >> 24) & 0xFF
        if let scheme, let x = SchemeColor.xml(scheme, alpha: Int(alpha)) { return x }
        let a = alpha < 255 ? "<a:alpha val=\"\(alpha * 100000 / 255)\"/>" : ""
        return "<a:solidFill><a:srgbClr val=\"\(PptxText.hex(c))\">\(a)</a:srgbClr></a:solidFill>"
    }

    /// A group around `members`, its child space the same as the slide's
    /// (the members carry their slide positions).
    mutating func group(_ g: ShapeGroup, members: [ShapeState], media: inout MediaParts,
                        builder: inout PackageBuilder) -> String {
        let id = _id(g.fileId)
        var inner = ""
        for m in members { inner += shape(m, media: &media, builder: &builder) }
        let fs = members.map(\.frame)
        let l = fs.map { min($0.left, $0.right) }.min() ?? 0, t = fs.map { min($0.top, $0.bottom) }.min() ?? 0
        let r = fs.map { max($0.left, $0.right) }.max() ?? 0, b = fs.map { max($0.top, $0.bottom) }.max() ?? 0
        let off = "x=\"\(Self._emu(l))\" y=\"\(Self._emu(t))\"", ext = "cx=\"\(Self._emu(r - l))\" cy=\"\(Self._emu(b - t))\""
        // The group's own fill, which members saying `a:grpFill` take.
        var fill = g.fillXML ?? ""
        if fill.containsSubstring("r:embed"), let p = source, let part = members.first?.sourcePart {
            fill = kept(fill, sourcePart: part, package: p, builder: &builder, patch: nil)
        }
        let hidden = g.hidden ? " hidden=\"1\"" : ""
        return "<p:grpSp><p:nvGrpSpPr><p:cNvPr id=\"\(id)\" name=\"\(PptxXML.escape(g.name, attribute: true))\"\(hidden)/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>"
            + "<p:grpSpPr><a:xfrm><a:off \(off)/><a:ext \(ext)/><a:chOff \(off)/><a:chExt \(ext)/></a:xfrm>\(fill)</p:grpSpPr>\(inner)</p:grpSp>"
    }

    mutating func shape(_ s: ShapeState, media: inout MediaParts, builder: inout PackageBuilder) -> String {
        _current = s.id
        defer { _current = nil }
        let name = PptxXML.escape(s.name, attribute: true)
        // Hidden by the user or the file; a shape a hidden group drew is hidden by the group's own attribute.
        let hid = s.invisible && s.group?.hidden != true ? " hidden=\"1\"" : ""
        switch s.kind {
        case .opaque(let o):
            guard let p = source else { return "" }
            return kept(o.xml, sourcePart: o.sourcePart, package: p, builder: &builder, patch: s.frame, fileId: s.fileId, alt: _altChange(s))
        case .picture(let image) where s.media != nil:
            // A sound or movie put here: the poster frame as the picture, the
            // file as a media part named twice, as PowerPoint writes it
            // (`a:videoFile`/`a:audioFile` link, `p14:media` embed).
            let clip = s.media!
            let id = _id(s.fileId)
            let poster = _media(image, media: &media, builder: &builder)
            media.count += 1
            let part = "ppt/media/media\(media.count).\(clip.fileExtension)"
            builder.addBinary(part, clip.data)
            let target = Pptx.relative(part, from: self.part)
            let link = _rel(clip.isVideo ? RT.video : RT.audio, target, preferred: "rIdMedia\(media.count)")
            let embed = _rel(RT.media2007, target, preferred: "rIdMediaX\(media.count)")
            let tag = clip.isVideo ? "a:videoFile" : "a:audioFile"
            return "<p:pic><p:nvPicPr><p:cNvPr id=\"\(id)\" name=\"\(name)\"\(PptxText.altAttrs(s))\(hid)/>"
                + "<p:cNvPicPr><a:picLocks noChangeAspect=\"1\"/></p:cNvPicPr><p:nvPr><\(tag) r:link=\"\(link)\"/>"
                + "<p:extLst><p:ext uri=\"{DAA4B4D4-6D71-4841-9C94-3DE7FCFB9230}\"><p14:media xmlns:p14=\"http://schemas.microsoft.com/office/powerpoint/2010/main\" r:embed=\"\(embed)\"/></p:ext></p:extLst></p:nvPr></p:nvPicPr>"
                + "<p:blipFill><a:blip r:embed=\"\(poster)\"/><a:stretch><a:fillRect/></a:stretch></p:blipFill>"
                + "<p:spPr>\(Self._xfrm(s.frame, rotation: s.rotation, flipH: s.flipH, flipV: s.flipV))"
                + "<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></p:spPr></p:pic>"
        case .picture(let image):
            // Unchanged since it was read (same image, crop and turn): the
            // picture as it was, at its frame — its recolouring, transparency,
            // shape crop, flip, fill and outline are not modelled here.
            if let xml = s.sourceXML, let k = s.keptPicture, k.imageId == image.id, k.crop == s.crop,
               k.rotation == s.rotation, k.alpha == s.pictureAlpha, k.geometry == s.pictureGeometry, k.freeform == (s.customPath != nil), let p = source, let part = s.sourcePart {
                return kept(xml, sourcePart: part, package: p, builder: &builder, patch: s.frame, fileId: s.fileId, alt: _altChange(s, pictureAlt: .some(k.alt)))
            }
            // The same image, turned or cropped since it was read: the picture as it was with only the turn and the crop changed, so its
            // recolouring, transparency, flip, shape and outline stay.
            if let xml = s.sourceXML, let k = s.keptPicture, k.imageId == image.id, let p = source, let part = s.sourcePart {
                let crop = s.crop, rotation = s.rotation, flipH = s.flipH, flipV = s.flipV
                let lock = s.aspectLock, alpha = s.pictureAlpha, alphaChanged = k.alpha != s.pictureAlpha
                let geometry = s.pictureGeometry, geometryChanged = k.geometry != s.pictureGeometry || (k.freeform && s.customPath == nil)
                return kept(xml, sourcePart: part, package: p, builder: &builder, patch: s.frame, fileId: s.fileId, alt: _altChange(s, pictureAlt: .some(k.alt)), edit: { node in
                    if let lock { Self._lockEdit(lock)(node) }
                    if let x = node.first("p:spPr")?.first("a:xfrm") {
                        if rotation != 0 { x.attrs["rot"] = "\(Int((rotation * 60000).rounded()))" } else { x.attrs["rot"] = nil }
                        x.attrs["flipH"] = flipH ? "1" : nil
                        x.attrs["flipV"] = flipV ? "1" : nil
                    }
                    // Cut to another shape: the new preset in place of the old outline (preset or freeform).
                    if geometryChanged, let spPr = node.first("p:spPr") {
                        let at = spPr.children.firstIndex { $0.name == "a:prstGeom" || $0.name == "a:custGeom" }
                            ?? ((spPr.children.firstIndex { $0.name == "a:xfrm" } ?? -1) + 1)
                        spPr.children.removeAll { $0.name == "a:prstGeom" || $0.name == "a:custGeom" }
                        let g = XNode(name: "a:prstGeom", attrs: ["prst": geometry?.rawValue ?? "rect"])
                        g.children = [XNode(name: "a:avLst", attrs: [:])]
                        spPr.children.insert(g, at: min(at, spPr.children.count))
                    }
                    guard let fill = node.first("p:blipFill") else { return }
                    if alphaChanged, let blip = fill.first("a:blip") {
                        blip.children.removeAll { $0.name == "a:alphaModFix" }
                        if alpha < 1 { blip.children.insert(XNode(name: "a:alphaModFix", attrs: ["amt": "\(Int((alpha * 100000).rounded()))"]), at: 0) }
                    }
                    fill.children.removeAll { $0.name == "a:srcRect" }
                    if let crop, crop != .zero {
                        func v(_ x: Double) -> String { "\(Int((x * 100000).rounded()))" }
                        let r = XNode(name: "a:srcRect", attrs: ["l": v(crop.left), "t": v(crop.top), "r": v(crop.right), "b": v(crop.bottom)])
                        let at = (fill.children.firstIndex { $0.name == "a:blip" } ?? -1) + 1
                        fill.children.insert(r, at: at)
                    }
                })
            }
            let id = _id(s.fileId)
            let rid = _media(image, media: &media, builder: &builder)
            return "<p:pic><p:nvPicPr><p:cNvPr id=\"\(id)\" name=\"\(name)\"\(PptxText.altAttrs(s))\(hid)\(PptxText.cNvPrEnd(s))<p:cNvPicPr>\(s.aspectLocked ? "<a:picLocks noChangeAspect=\"1\"/>" : "<a:picLocks/>")</p:cNvPicPr><p:nvPr/></p:nvPicPr>"
                + "<p:blipFill><a:blip r:embed=\"\(rid)\"\(s.pictureAlpha < 1 ? "><a:alphaModFix amt=\"\(Int((s.pictureAlpha * 100000).rounded()))\"/></a:blip>" : "/>")\(Self._crop(s.crop))<a:stretch><a:fillRect/></a:stretch></p:blipFill>"
                + "<p:spPr>\(Self._xfrm(s.frame, rotation: s.rotation, flipH: s.flipH, flipV: s.flipV))"
                + "<a:prstGeom prst=\"\(s.pictureGeometry?.rawValue ?? "rect")\"><a:avLst/></a:prstGeom></p:spPr></p:pic>"
        case .table:
            // Unedited since it was read: the table as it was, in place.
            if let xml = s.sourceXML, let doc = s.text, doc == s.sourceText, let p = source, let part = s.sourcePart {
                let lock = s.readShape.flatMap { $0.aspectLock != s.aspectLock ? Self._lockEdit(s.aspectLocked) : nil }
                return kept(xml, sourcePart: part, package: p, builder: &builder, patch: s.frame, fileId: s.fileId, alt: _altChange(s), edit: lock)
            }
            // Only text typed or restyled inside cells: the table as it was, those cells' own runs patched.
            if let xml = s.sourceXML, let read = s.readShape, read.patchable(s), let old = s.sourceText, let new = s.text,
               let p = source, let part = s.sourcePart, let patched = Self._tableCellsPatched(xml, old: old, new: new) {
                let flipped = read.flipH != s.flipH || read.flipV != s.flipV
                let moved = read.frame != s.frame || read.rotation != s.rotation || flipped
                let shapeEdit = Self._shapeEdit(s, read)
                let lock = read.aspectLock != s.aspectLock ? Self._lockEdit(s.aspectLocked) : nil
                let edit: (XNode) -> Void = { shapeEdit($0); lock?($0) }
                return kept(patched, sourcePart: part, package: p, builder: &builder, patch: s.frame, fileId: s.fileId, alt: _altChange(s),
                            rotation: nil, placeIfMissing: moved, flips: nil, hidden: nil, edit: edit)
            }
            return _table(s, name: name)
        case .chart(let chart):
            // Unchanged since it was read: through its own part, which keeps
            // whatever of the file's styling this app does not model.
            if let xml = s.sourceXML, chart == s.sourceChart, let p = source, let part = s.sourcePart {
                return kept(xml, sourcePart: part, package: p, builder: &builder, patch: s.frame, fileId: s.fileId, alt: _altChange(s))
            }
            // Edited since: the file's own part, patched where the user changed it.
            if let xml = s.sourceXML, let old = s.sourceChart, let p = source, let part = s.sourcePart,
               let rel = p.rels(part).first(where: { $0.type.hasSuffix("/chart") && !$0.external }),
               let data = p.parts[rel.target], let text = String(data: data, encoding: .utf8),
               ChartPartPatcher.patch(text, old: old, new: chart) != nil {
                return kept(xml, sourcePart: part, package: p, builder: &builder, patch: s.frame, fileId: s.fileId,
                            chartEdit: { ChartPartPatcher.patch($0, old: old, new: chart) },
                            chartBook: { ChartPartPatcher.apply($0, to: $1) })
            }
            return _chart(chart, s, name: name, media: &media, builder: &builder)
        case .geometry(let preset) where (preset.isLine || preset.rawValue.hasPrefix("bentConnector")
                                          || preset.rawValue.hasPrefix("curvedConnector")) && s.text == nil:
            // A connector as read, while its line and outline are: the
            // original, at its frame on the slide. One only slid (the same
            // length and direction) is the original too, its box slid as far,
            // so it keeps its p:style and ids.
            let slid = s.keptLine.flatMap { k -> Rect? in
                guard abs(k.line.width - s.frame.width) < 1e-6, abs(k.line.height - s.frame.height) < 1e-6 else { return nil }
                let dx = s.frame.left - k.line.left, dy = s.frame.top - k.line.top
                return Rect.fromLTWH(k.box.left + dx, k.box.top + dy, k.box.width, k.box.height)
            }
            if let xml = s.sourceXML, let k = s.keptLine, let box = k.line == s.frame ? k.box : slid, k.outline == s.outline,
               k.width == s.outlineWidth, k.dash == s.outlineDash, k.head == s.headEnd, k.tail == s.tailEnd, k.connStart == s.connStart, k.connEnd == s.connEnd,
               !preset.isElbow || (k.rotation == s.rotation && k.flipH == s.flipH && k.flipV == s.flipV && k.adjusts == s.adjusts),
               let p = source, let part = s.sourcePart {
                return kept(xml, sourcePart: part, package: p, builder: &builder, patch: box, fileId: s.fileId, alt: _altChange(s))
            }
            let id = _id(s.fileId)
            let f = s.frame
            let box = Rect.fromLTRB(min(f.left, f.right), min(f.top, f.bottom), max(f.left, f.right), max(f.top, f.bottom))
            let line = s.outline.map { "<a:ln w=\"\(Self._emu(s.outlineWidth))\">\(Self._fill($0, scheme: s.outlineScheme))\(Self._dashXML(s.outlineDash))\(Self._endsXML(s))</a:ln>" } ?? "<a:ln><a:noFill/></a:ln>"
            return "<p:cxnSp><p:nvCxnSpPr><p:cNvPr id=\"\(id)\" name=\"\(name)\"\(PptxText.altAttrs(s))\(hid)/><p:cNvCxnSpPr>\(Self._connXML(s))</p:cNvCxnSpPr><p:nvPr/></p:nvCxnSpPr>"
                + "<p:spPr>\(Self._xfrm(box, rotation: s.rotation, flipH: s.flipH != (f.right < f.left), flipV: s.flipV != (f.bottom < f.top)))"
                + "<a:prstGeom prst=\"\(preset.rawValue)\">\(Self._avLst(s.adjusts))</a:prstGeom>\(line)</p:spPr>\(s.themeStyle ? Self._themeStyle(line: true) : "")</p:cxnSp>"
        default:
            // Unchanged since it was read, text and all: the shape as it
            // was, so what this app models loosely (the master's bullets,
            // run effects, tab stops) comes back untouched.
            if let xml = s.sourceXML, let read = s.readShape, read.unchangedExceptPlacement(s),
               let p = source, let part = s.sourcePart {
                let flipped = read.flipH != s.flipH || read.flipV != s.flipV
                let moved = read.frame != s.frame || read.rotation != s.rotation || flipped
                return kept(xml, sourcePart: part, package: p, builder: &builder, patch: s.frame, fileId: s.fileId, alt: _altChange(s),
                            rotation: moved ? s.rotation : nil, placeIfMissing: moved,
                            flips: flipped ? (s.flipH, s.flipV) : nil,
                            hidden: read.invisible != s.invisible ? s.invisible : nil,
                            edit: read.aspectLock != s.aspectLock ? Self._lockEdit(s.aspectLocked) : nil)
            }
            // Edited since it was read (typed in, filled, outlined, renamed, its text box changed...): the
            // shape as it was, with only what the edit touched patched into its own XML, so the theme
            // colours, East Asian faces, adjust handles, effects and paragraph settings the model does not
            // hold stay (S-P0-1b, and the sweep that found a fill change stripped them).
            // A field (date, slide number) is patched only while it shows the characters it was read with: a field that
            // now shows other text is written anew; one only restyled (a bold date) keeps its own a:fld and runs.
            if let xml = s.sourceXML, let read = s.readShape, read.patchable(s),
               s.field == nil || s.text?.paragraphs.map(\.text) == s.sourceText?.paragraphs.map(\.text),
               let p = source, let part = s.sourcePart {
                var base: String? = xml
                if s.text != s.sourceText {
                    base = nil
                    if let old = s.sourceText, let new = s.text { base = PptxTextPatch.apply(xml, old: old, new: new) }
                }
                if let base {
                    let flipped = read.flipH != s.flipH || read.flipV != s.flipV
                    let moved = read.frame != s.frame || read.rotation != s.rotation || flipped
                    let shapeEdit = Self._shapeEdit(s, read)
                    let lockEdit = read.aspectLock != s.aspectLock ? Self._lockEdit(s.aspectLocked) : nil
                    let edit: (XNode) -> Void = { n in shapeEdit(n); lockEdit?(n) }
                    return kept(base, sourcePart: part, package: p, builder: &builder, patch: s.frame, fileId: s.fileId, alt: _altChange(s),
                                rotation: moved ? s.rotation : nil, placeIfMissing: moved,
                                flips: flipped ? (s.flipH, s.flipV) : nil,
                                hidden: read.invisible != s.invisible ? s.invisible : nil, edit: edit)
                }
            }
            let id = _id(s.fileId)
            var nv = "<p:cNvPr id=\"\(id)\" name=\"\(name)\"\(PptxText.altAttrs(s))\(hid)\(PptxText.cNvPrEnd(s))"
            var ph = ""
            switch s.kind {
            case .placeholder(let role):
                nv += "<p:cNvSpPr><a:spLocks noGrp=\"1\"/></p:cNvSpPr>"
                let type = s.phType ?? (role == .body ? nil : role.rawValue)
                var attrs = ""
                if let type, type != "obj" { attrs += " type=\"\(type)\"" }
                if let idx = s.phIdx { attrs += " idx=\"\(idx)\"" }
                ph = "<p:ph\(attrs)/>"
            case .textBox:
                nv += s.aspectLock == true ? "<p:cNvSpPr txBox=\"1\"><a:spLocks noChangeAspect=\"1\"/></p:cNvSpPr>" : "<p:cNvSpPr txBox=\"1\"/>"
            default:
                nv += s.aspectLock == true ? "<p:cNvSpPr><a:spLocks noChangeAspect=\"1\"/></p:cNvSpPr>" : "<p:cNvSpPr/>"
            }
            var spPr = Self._xfrm(s.frame, rotation: s.rotation, flipH: s.flipH, flipV: s.flipV)
            let prst: String = {
                switch s.kind {
                case .geometry(let p): return p.rawValue
                default: return "rect"
                }
            }()
            spPr += "<a:prstGeom prst=\"\(prst)\">\(Self._avLst(s.adjusts))</a:prstGeom>"
            var fillXML: String, lineXML: String
            switch s.kind {
            case .placeholder:
                fillXML = s.fill.map { Self._fill($0) } ?? ""
                lineXML = s.outline.map { "<a:ln w=\"\(Self._emu(s.outlineWidth))\">\(Self._fill($0, scheme: s.outlineScheme))\(Self._dashXML(s.outlineDash))\(Self._endsXML(s))</a:ln>" } ?? ""
            default:
                fillXML = Self._fill(s.fill, scheme: s.fillScheme)
                lineXML = s.outline.map { "<a:ln w=\"\(Self._emu(s.outlineWidth))\">\(Self._fill($0, scheme: s.outlineScheme))\(Self._dashXML(s.outlineDash))\(Self._endsXML(s))</a:ln>" } ?? "<a:ln><a:noFill/></a:ln>"
            }
            // A gradient, picture or pattern the user gave the shape (or a new shape's): written as such.
            if case .placeholder = s.kind {} else if let st = s.fillStyle, st.image != nil || st.stops.count >= 2,
               s.keptLook == nil || s.keptLook?.fillReplaced == true {
                fillXML = fill(st, media: &media, builder: &builder)
            }
            // The file's own fill and line while the shape's are unchanged
            // (gradients, patterns, a style's fill stay as they were); its
            // effects and style always.
            let look = s.keptLook
            if let k = look {
                // A picture fill names its image by the source slide's
                // relationship: re-pointed, the image copied over.
                func own(_ xml: String) -> String {
                    guard xml.containsSubstring("r:"), let p = source, let part = s.sourcePart else { return xml }
                    return kept(xml, sourcePart: part, package: p, builder: &builder, patch: nil)
                }
                if k.fillKept(s) { fillXML = k.fill.map(own) ?? "" }
                if k.lineKept(s) { lineXML = k.line.map(own) ?? "" }
                else if let ln = k.line {
                    // A changed colour or width: only the line's fill (and width) change; its dash, caps, joins and arrowheads stay.
                    let replaceFill = k.lineReplaced || s.outline != k.readOutline
                    lineXML = Self._patchedLine(ln, widthEMU: s.outlineWidth == k.readWidth ? nil : Self._emu(s.outlineWidth),
                                                fill: replaceFill ? (s.outline.map { Self._fill($0, scheme: s.outlineScheme) } ?? "<a:noFill/>") : nil,
                                                dash: k.dashEdited ? .some(s.outlineDash) : nil,
                                                ends: k.endsEdited ? Self._endsXML(s) : nil)
                }
            }
            var effectsXML: String
            if let k = look, !k.effectsEdited, !k.bevelEdited { effectsXML = k.effects }
            else {
                effectsXML = Self._effectsEdited(look?.effects ?? "", shadow: s.shadow,
                                                 glow: s.glowRadius.flatMap { r in r > 0 ? (r, s.glowColor ?? Color(0x66000000)) : nil },
                                                 reflection: s.reflection, softEdge: s.softEdge, bevel: s.bevel,
                                                 lists: look?.effectsEdited ?? true, bevelEdit: look?.bevelEdited ?? true,
                                                 emptyList: look?.effectsEdited == true)
            }
            // A Shape Styles entry: what still shows it is left to the refs, as PowerPoint saves it (so the entry
            // is known as its own and follows the theme); only what was changed since is the shape's own.
            if s.quickStyle != nil, let given = s.quickStyleLook {
                if given.fillShown(by: s) { fillXML = "" }
                if given.lineShown(by: s) { lineXML = "" }
                if given.effectsShown(by: s) { effectsXML = "" }
            }
            if let cam = s.camera { effectsXML = Self._effectsWithCamera(effectsXML, cam) }
            spPr += fillXML + lineXML + effectsXML
            var openPath = false
            if case .geometry(let p) = s.kind { openPath = p.isOpenPath }
            let style: String = s.quickStyle?.xml ?? look?.style ?? (s.themeStyle ? Self._themeStyle(line: openPath) : "")
            var xml = "<p:sp><p:nvSpPr>\(nv)<p:nvPr>\(ph)</p:nvPr></p:nvSpPr><p:spPr>\(spPr)</p:spPr>\(style)"
            if let doc = s.text {
                let anchor = s.anchor.rawValue
                let ins = s.insets.minusShare(s.shapeInsets)   // the frame's own margins, not the preset's text rectangle
                let fit: String
                if s.autofit {
                    // Shrink to fit — a text box can say so too.
                    let scale = Int((s.fontScale * 100000).rounded())
                    let reduction = Int((s.lineReduction * 100000).rounded())
                    var attrs = scale < 100000 ? " fontScale=\"\(scale)\"" : ""
                    if reduction > 0 { attrs += " lnSpcReduction=\"\(reduction)\"" }
                    fit = "<a:normAutofit\(attrs)/>"
                } else if s.fitRule == "a:spAutoFit" || (s.fitRule == nil && s.kind == .textBox) {
                    fit = "<a:spAutoFit/>"
                } else {
                    fit = "<a:noAutofit/>"
                }
                let vert = s.bodyVert.map { " vert=\"\(PptxXML.escape($0, attribute: true))\"" } ?? ""
                let wrap = s.noWrap && s.bodyWrap == "none" ? "none" : "square"
                let cols = s.columns > 1 ? " numCol=\"\(s.columns)\" spcCol=\"\(Self._emu(s.columnGap))\"" : ""
                xml += "<p:txBody><a:bodyPr\(vert) wrap=\"\(wrap)\"\(cols) lIns=\"\(Self._emu(ins.left))\" tIns=\"\(Self._emu(ins.top))\" "
                    + "rIns=\"\(Self._emu(ins.right))\" bIns=\"\(Self._emu(ins.bottom))\" anchor=\"\(anchor)\"\(s.anchorCentred ? " anchorCtr=\"1\"" : "") rtlCol=\"0\">\(s.warp?.xml ?? "")\(fit)</a:bodyPr>"
                    + "<a:lstStyle/>" + PptxText.paragraphs(doc, defaults: s, field: s.field) + "</p:txBody>"
            }
            return xml + "</p:sp>"
        }
    }

    /// The fill and line a shape of ours writes, as XML (the same the regenerated shape gets).
    /// A shape whose text is held level while it turns is read as two shapes (the shape, and its text as a box of its own),
    /// both from the one element. Written back from the model they both rebuild; put together again they are the element as it
    /// was, with the text box's edits patched in.
    static func _mergeUprightSplits(_ shapes: [ShapeState]) -> [ShapeState] {
        var out: [ShapeState] = []
        var i = 0
        while i < shapes.count {
            let a = shapes[i]
            if i + 1 < shapes.count, a.text == nil, let xml = a.sourceXML, a.sourceText != nil {
                let b = shapes[i + 1]
                if b.sourceXML == xml, b.sourcePart == a.sourcePart, b.kind == .textBox, b.group?.key == a.group?.key, b.text != nil {
                    var m = a
                    m.text = b.text
                    out.append(m)
                    i += 2
                    continue
                }
            }
            out.append(a)
            i += 1
        }
        return out
    }

    /// A table read from a file with only the text of some cells changed (same grid, same cell settings, same table style):
    /// the table's own XML with those cells' paragraphs patched. Nil when the edit is more than that.
    static func _tableCellsPatched(_ xml: String, old: RichDocument, new: RichDocument) -> String? {
        guard old.tableStyles == new.tableStyles, old.tableColumns == new.tableColumns,
              old.paragraphs.count > 0, new.paragraphs.count > 0,
              let root = XNode.parse(Data(xml.utf8)), let tbl = root.descendant("a:tbl") else { return nil }
        func groups(_ d: RichDocument) -> [[Int]: [RichParagraph]]? {
            var g: [[Int]: [RichParagraph]] = [:]
            for p in d.paragraphs {
                guard let c = p.cell else { return nil }
                var q = p; q.cell = nil
                g[[c.row, c.column], default: []].append(q)
            }
            return g
        }
        func cellRefs(_ d: RichDocument) -> [[Int]: CellRef] {
            var g: [[Int]: CellRef] = [:]
            for p in d.paragraphs { if let c = p.cell, g[[c.row, c.column]] == nil { g[[c.row, c.column]] = c } }
            return g
        }
        guard let og = groups(old), let ng = groups(new), Set(og.keys) == Set(ng.keys), cellRefs(old) == cellRefs(new) else { return nil }
        let rows = tbl.all("a:tr")
        for (key, oldParas) in og where ng[key]! != oldParas {
            guard key[0] < rows.count else { return nil }
            let tcs = rows[key[0]].all("a:tc")
            guard key[1] < tcs.count, let body = tcs[key[1]].first("a:txBody") else { return nil }
            guard PptxTextPatch.patchBody(body, old: RichDocument(paragraphs: oldParas), new: RichDocument(paragraphs: ng[key]!)) else { return nil }
        }
        return PptxXML.serialize(root)
    }

    private static func _shapeFillLine(_ s: ShapeState) -> (fill: String, line: String) {
        if case .placeholder = s.kind {
            return (s.fill.map { Self._fill($0) } ?? "", s.outline.map { "<a:ln w=\"\(Self._emu(s.outlineWidth))\">\(Self._fill($0, scheme: s.outlineScheme))</a:ln>" } ?? "")
        }
        let fill = Self._fill(s.fill, scheme: s.fillScheme)
        return (fill, s.outline.map { "<a:ln w=\"\(Self._emu(s.outlineWidth))\">\(Self._fill($0, scheme: s.outlineScheme))\(Self._dashXML(s.outlineDash))\(Self._endsXML(s))</a:ln>" } ?? "<a:ln><a:noFill/></a:ln>")
    }

    private static func _fragment(_ xml: String) -> [XNode] {
        guard !xml.isEmpty, let root = XNode.parse(Data("<r>\(xml)</r>".utf8)) else { return [] }
        return root.children
    }

    /// What a save patches into a shape's own XML for the properties the edit touched (and nothing else).
    private static func _shapeEdit(_ s: ShapeState, _ read: ReadShape) -> (XNode) -> Void {
        let (fillXML, lineXML) = _shapeFillLine(s)
        let fillChanged = read.fill != s.fill || read.fillScheme != s.fillScheme
        let lineChanged = read.outline != s.outline || read.outlineScheme != s.outlineScheme || read.outlineWidth != s.outlineWidth
        let clickChanged = read.link != s.link || read.linkTip != s.linkTip
        let click = clickChanged ? (PptxText.links?.xml(s.link, s.linkTip) ?? "") : ""
        let fit: String? = {
            guard read.autofit != s.autofit || read.fontScale != s.fontScale else { return nil }
            if s.autofit {
                let scale = Int((s.fontScale * 100000).rounded())
                let reduction = Int((s.lineReduction * 100000).rounded())
                var attrs = scale < 100000 ? " fontScale=\"\(scale)\"" : ""
                if reduction > 0 { attrs += " lnSpcReduction=\"\(reduction)\"" }
                return "<a:normAutofit\(attrs)/>"
            }
            return s.fitRule == "a:spAutoFit" || (s.fitRule == nil && s.kind == .textBox) ? "<a:spAutoFit/>" : "<a:noAutofit/>"
        }()
        let fills: Set<String> = ["a:noFill", "a:solidFill", "a:gradFill", "a:blipFill", "a:pattFill", "a:grpFill"]
        return { node in
            if let c = node.descendant("p:cNvPr") {
                if read.name != s.name { c.attrs["name"] = s.name }
                if clickChanged {
                    c.children.removeAll { $0.name == "a:hlinkClick" }
                    c.children.insert(contentsOf: _fragment(click), at: 0)
                }
            }
            if let spPr = node.first("p:spPr") {
                func after(_ names: Set<String>) -> Int { (spPr.children.lastIndex { names.contains($0.name) } ?? -1) + 1 }
                if read.adjusts != s.adjusts, let geom = spPr.first("a:prstGeom") {
                    geom.children.removeAll { $0.name == "a:avLst" }
                    geom.children.insert(contentsOf: _fragment(_avLst(s.adjusts)), at: 0)
                }
                if fillChanged {
                    spPr.children.removeAll { fills.contains($0.name) }
                    spPr.children.insert(contentsOf: _fragment(fillXML), at: after(["a:xfrm", "a:custGeom", "a:prstGeom"]))
                }
                if lineChanged {
                    spPr.children.removeAll { $0.name == "a:ln" }
                    spPr.children.insert(contentsOf: _fragment(lineXML), at: after(fills.union(["a:xfrm", "a:custGeom", "a:prstGeom"])))
                }
            }
            if let body = node.first("p:txBody")?.first("a:bodyPr") {
                if read.anchor != s.anchor { body.attrs["anchor"] = s.anchor.rawValue }
                // The text frame's own margins: the geometry's share (an oval's inscribed box) is the preset's, not the file's.
                let own = s.insets.minusShare(s.shapeInsets)
                if read.insets != own {
                    body.attrs["lIns"] = "\(_emu(own.left))"; body.attrs["tIns"] = "\(_emu(own.top))"
                    body.attrs["rIns"] = "\(_emu(own.right))"; body.attrs["bIns"] = "\(_emu(own.bottom))"
                }
                if let fit {
                    body.children.removeAll { ["a:normAutofit", "a:noAutofit", "a:spAutoFit"].contains($0.name) }
                    body.children.append(contentsOf: _fragment(fit))
                }
            }
        }
    }

    /// A chart of our own: its part (values cached), the workbook it was
    /// drawn from, and the frame that places it.
    private mutating func _chart(_ chart: Chart, _ s: ShapeState, name: String, media: inout MediaParts,
                                 builder: inout PackageBuilder) -> String {
        let hid = s.invisible && s.group?.hidden != true ? " hidden=\"1\"" : ""
        media.charts += 1
        let n = media.charts
        let chartPart = "ppt/charts/slides_chart\(n).xml"
        let book = "ppt/embeddings/Microsoft_Excel_Worksheet_slides\(n).xlsx"
        builder.add(chartPart, ChartXML.chartSpace(chart), type: ChartXML.contentType)
        builder.addBinary(book, (try? ChartXML.workbook(chart)) ?? Data())
        builder.defaults["xlsx"] = ChartXML.xlsxType
        builder.rels(chartPart, [Rel(id: "rId1", type: ChartXML.packageRelType, target: Pptx.relative(book, from: chartPart))])
        let rid = _rel(ChartXML.relType, Pptx.relative(chartPart, from: part), preferred: "rIdChart\(n)")
        let id = _id(s.fileId)
        return "<p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id=\"\(id)\" name=\"\(name)\"\(PptxText.altAttrs(s))\(hid)/><p:cNvGraphicFramePr><a:graphicFrameLocks noGrp=\"1\"/></p:cNvGraphicFramePr><p:nvPr/></p:nvGraphicFramePr>"
            + Self._xfrm(s.frame, rotation: 0, tag: "p:xfrm")
            + "<a:graphic><a:graphicData uri=\"http://schemas.openxmlformats.org/drawingml/2006/chart\">"
            + "<c:chart xmlns:c=\"http://schemas.openxmlformats.org/drawingml/2006/chart\" r:id=\"\(rid)\"/></a:graphicData></a:graphic></p:graphicFrame>"
    }

    /// A table as `a:tbl`: the grid, rows as tall as the shape shares out,
    /// merges as gridSpan/rowSpan with their hMerge/vMerge stand-ins, and
    /// every cell's fill spelled out so the look does not depend on a table
    /// style the file may not define.
    private mutating func _table(_ s: ShapeState, name: String) -> String {
        guard let doc = s.text, let tableId = doc.paragraphs.first?.cell?.table else { return "" }
        let cells = doc.paragraphs.compactMap(\.cell)
        let rows = (cells.map { $0.row + $0.rowSpan }.max() ?? 1)
        let cols = (cells.map { $0.column + $0.span }.max() ?? 1)
        let widths = doc.tableColumns[tableId].flatMap { $0.count == cols ? $0 : nil }
            ?? Array(repeating: s.frame.width / Double(cols), count: cols)
        let style = doc.tableStyles[tableId] ?? TableStyle()
        // Rows keep the heights they were given (Row Height, a file's own); the rest share what is left.
        let stated = style.rowHeights.filter { $0.key < rows && $0.value > 0 }
        let shared = rows > stated.count ? max(0, s.frame.height - stated.values.reduce(0, +)) / Double(rows - stated.count) : 0
        func rowH(_ r: Int) -> Int { Self._emu(stated[r] ?? shared) }
        // Which grid slots a merge covers, for the stand-ins.
        var covered: [Int: [Int: String]] = [:]   // row → column → "hMerge"/"vMerge"
        for c in cells {
            for r in c.row ..< c.row + c.rowSpan {
                for k in c.column ..< c.column + c.span where !(r == c.row && k == c.column) {
                    covered[r, default: [:]][k] = r == c.row ? "hMerge" : "vMerge"
                }
            }
        }
        func fill(_ row: Int) -> String {
            let header = row == 0 && style.headerRow
            let body = row - (style.headerRow ? 1 : 0)
            let c: Color? = header ? style.headerFill : (body % 2 == 0 ? style.bandFill : style.bandAltFill)
            return c.map { "<a:solidFill><a:srgbClr val=\"\(PptxText.hex($0))\"/></a:solidFill>" } ?? "<a:noFill/>"
        }
        /// A cell the user shaded keeps its own colour (alpha 0 means "no fill"); else the style's.
        func ownFill(_ cell: CellRef, _ row: Int) -> String {
            // A table that names a style leaves its fills to the style: only a colour the user set stays in the cell.
            if style.styleId != nil, cell.fill == nil || cell.styleFilled == true { return "" }
            guard let c = cell.fill else { return fill(row) }
            if c.alpha == 0 { return "<a:noFill/>" }
            return "<a:solidFill><a:srgbClr val=\"\(PptxText.hex(c))\"/></a:solidFill>"
        }
        func border(_ tag: String) -> String {
            guard style.borders else { return "<\(tag) w=\"12700\"><a:noFill/></\(tag)>" }
            let c = style.borderColor ?? Color(0xFF000000)
            return "<\(tag) w=\"12700\"><a:solidFill><a:srgbClr val=\"\(PptxText.hex(c))\"/></a:solidFill></\(tag)>"
        }
        let borders = style.styleId != nil ? "" : border("a:lnL") + border("a:lnR") + border("a:lnT") + border("a:lnB")
        var xml = "<p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id=\"\(_id(s.fileId))\" name=\"\(name)\"" + PptxText.altAttrs(s) + PptxText.cNvPrEnd(s)
            + "<p:cNvGraphicFramePr><a:graphicFrameLocks noGrp=\"1\"\(s.aspectLock == true ? " noChangeAspect=\"1\"" : "")/></p:cNvGraphicFramePr><p:nvPr/></p:nvGraphicFramePr>"
            + Self._xfrm(s.frame, rotation: 0, tag: "p:xfrm")
            + "<a:graphic><a:graphicData uri=\"http://schemas.openxmlformats.org/drawingml/2006/table\"><a:tbl>"
            + "<a:tblPr firstRow=\"\(style.headerRow ? 1 : 0)\" bandRow=\"\((style.bandRows ?? (style.bandFill != nil)) ? 1 : 0)\"\(style.totalRow ? " lastRow=\"1\"" : "")\(style.firstColumn ? " firstCol=\"1\"" : "")\(style.lastColumn ? " lastCol=\"1\"" : "")\(style.bandedColumns ? " bandCol=\"1\"" : "")>"
            + "<a:tableStyleId>\(style.styleId ?? "{5C22544A-7EE6-4342-B048-85BDC9FD1C3A}")</a:tableStyleId></a:tblPr><a:tblGrid>"
            + widths.map { "<a:gridCol w=\"\(Self._emu($0))\"/>" }.joined() + "</a:tblGrid>"
        for r in 0 ..< rows {
            xml += "<a:tr h=\"\(rowH(r))\">"
            for k in 0 ..< cols {
                if let stand = covered[r]?[k] {
                    xml += "<a:tc \(stand)=\"1\"><a:txBody><a:bodyPr/><a:lstStyle/><a:p/></a:txBody><a:tcPr/></a:tc>"
                    continue
                }
                let paras = doc.paragraphs.filter { $0.cell?.row == r && $0.cell?.column == k }
                guard let cell = paras.first?.cell else {
                    xml += "<a:tc><a:txBody><a:bodyPr/><a:lstStyle/><a:p/></a:txBody><a:tcPr>\(borders)\(style.styleId != nil ? "" : fill(r))</a:tcPr></a:tc>"
                    continue
                }
                var attrs = ""
                if cell.span > 1 { attrs += " gridSpan=\"\(cell.span)\"" }
                if cell.rowSpan > 1 { attrs += " rowSpan=\"\(cell.rowSpan)\"" }
                let body = PptxText.paragraphs(RichDocument(paragraphs: paras.map { var p = $0; p.cell = nil; return p }), defaults: s)
                var tcPr = cell.textDirection == .down ? " vert=\"vert\"" : cell.textDirection == .up ? " vert=\"vert270\"" : ""
                // Where the text stands down the cell: PowerPoint's default is the top.
                if cell.verticalAlign == "center" { tcPr += " anchor=\"ctr\"" } else if cell.verticalAlign == "bottom" { tcPr += " anchor=\"b\"" }
                if let m = cell.padding {
                    for (name, v, dflt) in [("marL", m.left, 7.2), ("marR", m.right, 7.2), ("marT", m.top, 3.6), ("marB", m.bottom, 3.6)]
                    where abs(v - dflt) > 0.01 {
                        tcPr += " \(name)=\"\(Self._emu(v))\""
                    }
                }
                // The cell's own edge lines where it has them, the style's
                // elsewhere.
                func own(_ tag: String, _ l: CellRef.CellLine?) -> String {
                    guard let l else { return style.styleId != nil ? "" : border(tag) }
                    guard let c = l.color, l.width > 0 else { return "<\(tag) w=\"12700\"><a:noFill/></\(tag)>" }
                    return "<\(tag) w=\"\(Self._emu(l.width))\"><a:solidFill><a:srgbClr val=\"\(PptxText.hex(c))\"/></a:solidFill>\(DeckController.penDashName(l.dash).map { "<a:prstDash val=\"\($0)\"/>" } ?? "")</\(tag)>"
                }
                let lines = cell.borders.isEmpty ? borders
                    : own("a:lnL", cell.borders.left) + own("a:lnR", cell.borders.right) + own("a:lnT", cell.borders.top) + own("a:lnB", cell.borders.bottom)
                xml += "<a:tc\(attrs)><a:txBody><a:bodyPr/><a:lstStyle/>\(body)</a:txBody><a:tcPr\(tcPr)>\(lines)\(ownFill(cell, r))</a:tcPr></a:tc>"
            }
            xml += "</a:tr>"
        }
        return xml + "</a:tbl></a:graphicData></a:graphic></p:graphicFrame>"
    }

    /// A kept element (an object or a background) written back: its frame
    /// set to where the deck has it now, its shape id made unique, and its
    /// relationships re-pointed — the parts they name copied over with
    /// everything those parts reach.
    mutating func kept(_ xml: String, sourcePart: String, package p: PptxPackage,
                       builder b: inout PackageBuilder, patch frame: Rect?, fileId: Int? = nil, alt: (descr: String?, title: String?)? = nil,
                       rotation: Double? = nil, placeIfMissing: Bool = false, flips: (h: Bool, v: Bool)? = nil,
                       hidden: Bool? = nil, edit: ((XNode) -> Void)? = nil, descr: String?? = nil,
                       chartEdit: ((String) -> ChartPartPatcher.Result?)? = nil, chartBook: (([ChartPartPatcher.CellWrite], Data) -> Data?)? = nil) -> String {
        guard let node = XNode.parse(Data(xml.utf8)) else { return "" }
        edit?(node)
        // A changed alt text: set (or remove) `descr` on the element's own `cNvPr`.
        if let descr, let c = node.descendant("p:cNvPr") { c.attrs["descr"] = descr }
        if let alt, let c = node.descendant("p:cNvPr") { c.attrs["descr"] = alt.descr; c.attrs["title"] = alt.title }
        if let hidden, let c = node.descendant("p:cNvPr") { c.attrs["hidden"] = hidden ? "1" : nil }
        if let frame {
            let x = node.first("p:xfrm") ?? node.first("p:spPr")?.first("a:xfrm") ?? node.first("p:grpSpPr")?.first("a:xfrm")
            if let x {
                if let off = x.first("a:off") { off.attrs["x"] = "\(Self._emu(frame.left))"; off.attrs["y"] = "\(Self._emu(frame.top))" }
                if let ext = x.first("a:ext") { ext.attrs["cx"] = "\(Self._emu(frame.width))"; ext.attrs["cy"] = "\(Self._emu(frame.height))" }
                if let rotation { if rotation == 0 { x.attrs["rot"] = nil } else { x.attrs["rot"] = "\(Int((rotation * 60000).rounded()))" } }
                if let flips { x.attrs["flipH"] = flips.h ? "1" : nil; x.attrs["flipV"] = flips.v ? "1" : nil }
            } else if placeIfMissing, let spPr = node.first("p:spPr") {
                // A placeholder that took its place from the layout, now
                // moved: it gets a frame of its own.
                let x = XNode(name: "a:xfrm", attrs: [:])
                if let rotation, rotation != 0 { x.attrs["rot"] = "\(Int((rotation * 60000).rounded()))" }
                if let flips { if flips.h { x.attrs["flipH"] = "1" }; if flips.v { x.attrs["flipV"] = "1" } }
                x.children = [XNode(name: "a:off", attrs: ["x": "\(Self._emu(frame.left))", "y": "\(Self._emu(frame.top))"]),
                              XNode(name: "a:ext", attrs: ["cx": "\(Self._emu(max(0, frame.width)))", "cy": "\(Self._emu(max(0, frame.height)))"])]
                spPr.children.insert(x, at: 0)
            }
            if let c = node.descendant("p:cNvPr") { c.attrs["id"] = "\(_id(fileId ?? c["id"].flatMap(Int.init)))" }
        }
        let sourceRels = p.rels(sourcePart)
        var done = [String: String]()
        // Elements that are nothing but their reference: without the part
        // they point at, the element goes too — `<a:snd name="hammer.wav"/>`
        // with no r:embed is a schema error PowerPoint repairs
        // (Divino_Revelado, a truncated file whose click sounds were cut off).
        let referenceOnly: Set<String> = ["a:snd", "a:wavAudioFile", "a:audioFile", "a:videoFile", "a:quickTimeFile",
                                          "p:snd", "p:sndTgt"]
        // Wrappers that are nothing without their reference child.
        let needsChild: Set<String> = ["p:stSnd", "p:endSnd", "p:sndAc"]
        /// Remaps `n`'s references; true when `n` should be dropped.
        func remap(_ n: XNode) -> Bool {
            var dead = false
            for (k, v) in n.attrs where k.hasPrefix("r:") {
                guard let r = sourceRels.first(where: { $0.id == v }) else { continue }
                if r.external {
                    n.attrs[k] = _rel(r.type, r.target, external: true, preferred: v)
                } else if r.type.hasSuffix("/hyperlink"), p.parts[r.target] == nil, r.target.contains("#" as Character) {
                    // A jump to a bookmark in the same file (Word's footnote links, `#_ftn1`): no part, and the link stays.
                    n.attrs[k] = _rel(r.type, Pptx.relative(r.target, from: part), external: false, preferred: v)
                } else if p.parts[r.target] == nil {
                    // A part the file names but does not have (a damaged
                    // file): no relationship to nowhere.
                    n.attrs[k] = nil
                    if referenceOnly.contains(n.name) { dead = true }
                } else {
                    let child = PptxWriterCopy.copy(r.target, from: p, into: &b, done: &done)
                    // A chart the user edited: its own part with the edit made in it, the rest as the file wrote it.
                    if r.type.hasSuffix("/chart"), let chartEdit, let data = p.parts[r.target], let xml = String(data: data, encoding: .utf8),
                       let result = chartEdit(xml) {
                        b.parts[child] = Data(result.xml.utf8)
                        if !result.writes.isEmpty, let chartBook,
                           let book = p.rels(r.target).first(where: { $0.type.hasSuffix("/package") && !$0.external }), let name = done[book.target],
                           let old = b.parts[name], let patched = chartBook(result.writes, old) {
                            b.parts[name] = patched
                        }
                    }
                    n.attrs[k] = _rel(r.type, Pptx.relative(child, from: part), preferred: v)
                }
            }
            n.children.removeAll { remap($0) }
            if needsChild.contains(n.name) && n.children.isEmpty { dead = true }
            return dead
        }
        _ = remap(node)
        return PptxXML.serialize(node)
    }
}

enum PptxWriterCopy {
    /// Parts one slide (or one object) owns: a second reference from another
    /// slide must get a part of its own, as PowerPoint writes them. Pictures,
    /// media, layouts, masters and themes are shared by design.
    static func isOwned(_ part: String) -> Bool {
        ["ppt/embeddings/", "ppt/charts/", "ppt/drawings/", "ppt/diagrams/", "ppt/comments/", "ppt/ink/",
         "ppt/activeX/", "ppt/tags/", "ppt/slideUpdateInfos/"].contains { part.hasPrefix($0) }
    }

    /// Copies `part`, its relationships and everything they reach; returns the
    /// name it was written under (a fresh one when another slide already
    /// owns a part of that name). `done` maps each source part to its name.
    @discardableResult
    static func copy(_ part: String, from p: PptxPackage, into b: inout PackageBuilder, done: inout [String: String]) -> String {
        if let name = done[part] { return name }
        guard let data = p.parts[part] else { return part }
        var name = part
        if isOwned(part), b.parts[part] != nil {
            let dot = part.lastIndex(of: ".") ?? part.endIndex
            var k = 2
            while b.parts["\(part[..<dot])-c\(k)\(part[dot...])"] != nil { k += 1 }
            name = "\(part[..<dot])-c\(k)\(part[dot...])"
        }
        done[part] = name
        b.parts[name] = data
        if let type = p.overrides[part] {
            b.overrides[name] = type
        } else if let ext = part.split(separator: ".").last.map({ String($0).lowercased() }),
                  b.defaults[ext] == nil, let type = p.defaults[ext] {
            // A part typed by extension (a video.avi, a .wav): the file's own
            // Default carries over, or the package has a part with no type.
            b.defaults[ext] = type
        }
        if p.parts[Pptx.relsPath(part)] != nil {
            var out: [Rel] = []
            var renamed = name != part
            for r in p.rels(part) {
                if r.external { out.append(Rel(id: r.id, type: r.type, target: r.target, external: true)); continue }
                let child = copy(r.target, from: p, into: &b, done: &done)
                if child != r.target { renamed = true }
                out.append(Rel(id: r.id, type: r.type, target: Pptx.relative(child, from: name)))
            }
            // Where nothing it names was renamed the file's own relationships part is kept as it was, byte for byte.
            if renamed { b.rels(name, out) } else { b.parts[Pptx.relsPath(name)] = p.parts[Pptx.relsPath(part)] }
        }
        return name
    }
}

// MARK: - Text

/// The hyperlinks one slide writes: each distinct target becomes a relationship of the slide.
final class PptxLinks {
    var rels: [Rel] = []
    var part = ""
    /// Source slide part → the part it is written as, for jumps to a slide.
    var slideParts: [String: String] = [:]
    private var ids: [String: String] = [:]

    func xml(_ link: String?, _ tip: String?) -> String {
        guard let link, !link.isEmpty else { return "" }
        let tipAttr = tip.map { " tooltip=\"\(PptxXML.escape($0, attribute: true))\"" } ?? ""
        if link.hasPrefix("action:") {
            return "<a:hlinkClick r:id=\"\" action=\"\(PptxXML.escape(String(link.dropFirst(7)), attribute: true))\"\(tipAttr)/>"
        }
        var type = RT.hyperlink, target = link, external = true, action = ""
        if link.hasPrefix("slide:") {
            guard let new = slideParts[String(link.dropFirst(6))] else { return "" }
            type = RT.slide; target = Pptx.relative(new, from: part); external = false
            action = " action=\"ppaction://hlinksldjump\""
        }
        let key = type + "|" + target
        let id: String
        if let known = ids[key] { id = known } else {
            id = "rIdL\(rels.count + 1)"
            rels.append(Rel(id: id, type: type, target: target, external: external))
            ids[key] = id
        }
        return "<a:hlinkClick r:id=\"\(id)\"\(action)\(tipAttr)/>"
    }
}

enum PptxText {
    nonisolated(unsafe) static var links: PptxLinks? = nil
    nonisolated(unsafe) static var slideParts: [String: String] = [:]
    static func setSlideParts(_ slides: [SlideState]) {
        slideParts = [:]
        for (i, s) in slides.enumerated() { slideParts[s.sourcePart ?? "new:\(s.id)"] = "ppt/slides/slide\(i + 1).xml" }
    }    /// ` descr="..." title="..."` for a shape's alt text (nothing when it has none).
    static func altAttrs(_ s: ShapeState) -> String {
        var r = ""
        if let d = s.altText, !d.isEmpty { r += " descr=\"\(PptxXML.escape(d, attribute: true))\"" }
        if let t = s.altTitle, !t.isEmpty { r += " title=\"\(PptxXML.escape(t, attribute: true))\"" }
        return r
    }
    /// The end of a `p:cNvPr`: a click action on the shape is its child.
    static func cNvPrEnd(_ s: ShapeState) -> String {
        let l = links?.xml(s.link, s.linkTip) ?? ""
        return l.isEmpty ? "/>" : ">" + l + "</p:cNvPr>"
    }
    static func hex(_ c: Color) -> String { String(printf: "%06X", UInt32(truncatingIfNeeded: c.value & 0xFFFFFF)) }

    static func imageExtension(_ image: ImageAttachment) -> String {
        let d = [UInt8](image.data.prefix(8))
        if d.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if d.starts(with: [0xFF, 0xD8]) { return "jpeg" }
        if d.starts(with: [0x47, 0x49, 0x46]) { return "gif" }
        let ext = image.name.pathExtension.lowercased()
        return ext.isEmpty ? "png" : ext
    }

    /// A text body's paragraphs, every run with its look spelled out. With
    /// `field`, the first run is written as that field (`a:fld`) — the
    /// shape is a slide number or a date, not the text it shows now.
    static func paragraphs(_ doc: RichDocument, defaults s: ShapeState, field: SlideField? = nil) -> String {
        var out = ""
        var pendingField = field
        for p in doc.paragraphs {
            let st = p.style
            var pPr = ""
            switch st.alignment {
            case .center: pPr += " algn=\"ctr\""
            case .right: pPr += " algn=\"r\""
            case .justify: pPr += " algn=\"just\""
            case .left: pPr += " algn=\"l\""
            }
            if st.list != nil {
                // Inverse of the reader: a file's own marL and indent come
                // back as they were; a new list hangs by the list indent.
                let marL = st.indentLeft + s.listIndent * Double(st.listLevel + 1)
                let hang = st.firstLineIndent - s.listIndent
                pPr += " marL=\"\(Int((marL * Pptx.emu).rounded()))\" indent=\"\(Int((hang * Pptx.emu).rounded()))\""
                if st.listLevel > 0 { pPr += " lvl=\"\(st.listLevel)\"" }
            } else {
                pPr += " marL=\"\(Int(st.indentLeft * Pptx.emu))\" indent=\"\(Int(st.firstLineIndent * Pptx.emu))\""
            }
            var inner = st.lineHeightPoints.map { "<a:lnSpc><a:spcPts val=\"\(Int(($0 * 100).rounded()))\"/></a:lnSpc>" }
                ?? "<a:lnSpc><a:spcPct val=\"\(Int((st.lineSpacing * 100000).rounded()))\"/></a:lnSpc>"
            inner += "<a:spcBef><a:spcPts val=\"\(Int((st.spaceBefore * 100).rounded()))\"/></a:spcBef>"
            inner += "<a:spcAft><a:spcPts val=\"\(Int((st.spaceAfter * 100).rounded()))\"/></a:spcAft>"
            switch st.list {
            case .bullet?, .numbered?:
                if let c = st.bulletColor { inner += "<a:buClr><a:srgbClr val=\"\(PptxText.hex(c))\"/></a:buClr>" }
                if let k = st.bulletScale { inner += "<a:buSzPct val=\"\(Int((k * 100000).rounded()))\"/>" }
                inner += st.list == .bullet
                    ? "<a:buFont typeface=\"\(PptxXML.escape(st.bulletFontFamily ?? "Arial", attribute: true))\"/><a:buChar char=\"\(PptxXML.escape(st.bulletText ?? "•", attribute: true))\"/>"
                    : "<a:buFont typeface=\"+mj-lt\"/>" + Self._autoNum(doc, st)
            case nil: inner += "<a:buNone/>"
            }
            out += "<a:p><a:pPr\(pPr)>\(inner)</a:pPr>"
            var offset = 0
            let utf16 = Array(p.text.utf16)
            for run in p.runs {
                let end = min(utf16.count, offset + run.length)
                guard end > offset else { offset = end; continue }
                let text = String(decoding: utf16[offset ..< end], as: UTF16.self)
                offset = end
                let rPr = _rPr(run.style, s, tag: "a:rPr")
                let pieces = text.components(separatedBy: "\n")
                for (i, piece) in pieces.enumerated() {
                    if i > 0 { out += "<a:br>\(rPr)</a:br>" }
                    guard !piece.isEmpty else { continue }
                    if let f = pendingField {
                        pendingField = nil
                        out += "<a:fld id=\"\(PptxXML.escape(f.id, attribute: true))\" type=\"\(PptxXML.escape(f.type, attribute: true))\">"
                            + "\(rPr)<a:t>\(PptxXML.escape(piece, attribute: false))</a:t></a:fld>"
                    } else {
                        out += "<a:r>\(rPr)<a:t>\(PptxXML.escape(piece, attribute: false))</a:t></a:r>"
                    }
                }
            }
            out += _rPr(p.runs.last?.style ?? CharStyle(), s, tag: "a:endParaRPr") + "</a:p>"
        }
        return out
    }

    private static func _rPr(_ c: CharStyle, _ s: ShapeState, tag: String) -> String {
        let size = c.fontSize ?? s.size
        var a = " lang=\"en-US\" sz=\"\(Int((size * 100).rounded()))\""
        // Spelled out either way: a run that says nothing about bold inherits
        // the layout's bold (comparison headings), and this app's text is
        // what the deck showed.
        a += c.bold ? " b=\"1\"" : " b=\"0\""
        a += c.italic ? " i=\"1\"" : " i=\"0\""
        a += c.underline ? " u=\"sng\"" : " u=\"none\""
        a += c.strikethrough ? " strike=\"sngStrike\"" : " strike=\"noStrike\""
        if c.caps { a += " cap=\"all\"" } else if c.smallCaps { a += " cap=\"small\"" }
        switch c.script {
        case .superscript: a += " baseline=\"30000\""
        case .subscript: a += " baseline=\"-25000\""
        case .normal: break
        }
        a += " dirty=\"0\""
        let color = c.color ?? s.color
        let font = PptxXML.escape(c.fontFamily ?? s.font ?? "Calibri", attribute: true)
        var shadow = ""
        if let sh = c.shadow {
            let dist = Int((hypot(sh.dx, sh.dy) * Pptx.emu).rounded())
            var deg = atan2(sh.dy, sh.dx) * 180 / .pi
            if deg < 0 { deg += 360 }
            let alpha = sh.color.alpha < 255 ? "<a:alpha val=\"\(Int((Double(sh.color.alpha) / 255 * 100000).rounded()))\"/>" : ""
            shadow = "<a:effectLst><a:outerShdw blurRad=\"\(Int((sh.blur * Pptx.emu).rounded()))\" dist=\"\(dist)\" dir=\"\(Int((deg * 60000).rounded()))\" algn=\"tl\">"
                + "<a:srgbClr val=\"\(hex(sh.color))\">\(alpha)</a:srgbClr></a:outerShdw></a:effectLst>"
        }
        let highlight = c.highlight.map { "<a:highlight><a:srgbClr val=\"\(hex($0))\"/></a:highlight>" } ?? ""
        let click = tag == "a:endParaRPr" ? "" : (links?.xml(c.link, c.linkTip) ?? "")
        return "<\(tag)\(a)><a:solidFill><a:srgbClr val=\"\(hex(color))\"/></a:solidFill>\(shadow)\(highlight)"
            + "<a:latin typeface=\"\(font)\"/><a:cs typeface=\"\(font)\"/>\(click)</\(tag)>"
    }

    /// Notes: plain paragraphs, no looks.
    /// A numbered paragraph's `a:buAutoNum`: the scheme and start its
    /// list was read with (a, b / i, ii / 1)…), "1." for a list made here.
    private static func _autoNum(_ doc: RichDocument, _ st: RichParagraphStyle) -> String {
        let lvl = min(8, max(0, st.listLevel))
        guard let id = st.listId, let f = doc.listFormats[id]?[lvl] else { return "<a:buAutoNum type=\"arabicPeriod\"/>" }
        let scheme: String
        switch f.format {
        case .lowerLetter: scheme = "alphaLc"
        case .upperLetter: scheme = "alphaUc"
        case .lowerRoman: scheme = "romanLc"
        case .upperRoman: scheme = "romanUc"
        default: scheme = "arabic"
        }
        let t = f.text
        let suffix = t.hasPrefix("(") ? "ParenBoth" : t.hasSuffix(")") ? "ParenR" : t.hasSuffix(".") ? "Period" : "Plain"
        let start = doc.listRestarts[id]?[lvl].map { " startAt=\"\($0)\"" } ?? ""
        return "<a:buAutoNum type=\"\(scheme)\(suffix)\"\(start)/>"
    }

    /// Notes text: runs with a look of their own (bold, a colour, a size, a font...) are written with it; notes that are all plain text stay plain, so they take the notes master's look.
    static func notesParagraphs(_ doc: RichDocument) -> String {
        let styled = doc.paragraphs.contains { p in p.runs.contains { $0.style != .plain } || p.style.list != nil }
        guard styled else { return paragraphsPlain(doc) }
        let s = ShapeState(id: 3, name: "Notes", kind: .geometry(.rect), frame: Rect.fromLTWH(0, 0, 1, 1), rotation: 0,
                           fill: nil, outline: nil, outlineWidth: 0, anchor: .top,
                           insets: EdgeInsets(left: 0, top: 0, right: 0, bottom: 0), prompt: nil, text: nil,
                           font: nil, size: 12, color: Color(0xFF000000), listIndent: 18)
        return paragraphs(doc, defaults: s)
    }

    static func paragraphsPlain(_ doc: RichDocument) -> String {
        doc.paragraphs.map { p in
            let parts = p.text.components(separatedBy: "\n").map {
                $0.isEmpty ? "" : "<a:r><a:rPr lang=\"en-US\" dirty=\"0\"/><a:t>\(PptxXML.escape($0, attribute: false))</a:t></a:r>"
            }
            return "<a:p>" + parts.joined(separator: "<a:br><a:rPr lang=\"en-US\"/></a:br>") + "</a:p>"
        }.joined()
    }
}

// S-SH-5: a shape's effects as the file holds them.
extension SlideXML {
    /// The end of the element that starts at `start` (an opening `<tag`), self-closing or not.
    private static func _elementEnd(_ s: String, _ start: String.Index, _ tag: String) -> String.Index? {
        guard let gt = s[start...].firstIndex(of: ">") else { return nil }
        if s[s.index(before: gt)] == "/" { return s.index(after: gt) }
        guard let close = s.rangeOfSubstring("</\(tag)>", in: gt..<s.endIndex) else { return nil }
        return close.upperBound
    }

    /// The first element `<tag ...>` in `s` (not a longer name sharing the prefix).
    private static func _element(_ s: String, _ tag: String) -> Range<String.Index>? {
        var from = s.startIndex
        while let r = s.rangeOfSubstring("<\(tag)", in: from..<s.endIndex) {
            let after = r.upperBound
            if after < s.endIndex, " />".contains(s[after]), let end = _elementEnd(s, r.lowerBound, tag) {
                return r.lowerBound..<end
            }
            from = r.upperBound
        }
        return nil
    }

    /// The top-level children of an element body, in order.
    private static func _children(_ body: String) -> [(tag: String, xml: String)] {
        var out: [(String, String)] = []
        var i = body.startIndex
        while let lt = body[i...].firstIndex(of: "<") {
            var j = body.index(after: lt)
            while j < body.endIndex, !" />".contains(body[j]) { j = body.index(after: j) }
            let tag = String(body[body.index(after: lt)..<j])
            guard let end = _elementEnd(body, lt, tag) else { break }
            out.append((tag, String(body[lt..<end]))); i = end
        }
        return out
    }

    private static func _hex(_ c: Color) -> String {
        let rgb = String(c.value & 0xFFFFFF, radix: 16, uppercase: true)
        return String(repeating: "0", count: max(0, 6 - rgb.count)) + rgb
    }

    private static func _glowXML(_ r: Double, _ c: Color) -> String {
        let alpha = c.alpha < 255 ? "<a:alpha val=\"\(Int((Double(c.alpha) / 255 * 100000).rounded()))\"/>" : ""
        return "<a:glow rad=\"\(Int((r * Pptx.emu).rounded()))\"><a:srgbClr val=\"\(_hex(c))\">\(alpha)</a:srgbClr></a:glow>"
    }

    private static func _reflectionXML(_ r: Reflection) -> String {
        func pct(_ v: Double) -> Int { Int((v * 100000).rounded()) }
        return "<a:reflection blurRad=\"\(Int((r.blur * Pptx.emu).rounded()))\" stA=\"\(pct(r.startAlpha))\" "
            + "endA=\"\(pct(r.endAlpha))\" endPos=\"\(pct(r.endPos))\" dist=\"\(Int((r.dist * Pptx.emu).rounded()))\" "
            + "dir=\"5400000\" sy=\"\(pct(r.scaleY))\" algn=\"bl\" rotWithShape=\"0\"/>"
    }

    private static func _bevelXML(_ b: ShapeBevel) -> String {
        "<a:bevelT w=\"\(Int((b.width * Pptx.emu).rounded()))\" h=\"\(Int((b.height * Pptx.emu).rounded()))\" prst=\"\(b.preset)\"/>"
    }

    /// A shape's effects as the file holds them: `effects` is what the file had (its `a:effectLst`, `a:effectDag`,
    /// `a:scene3d` and `a:sp3d`, in that order; empty for a new shape). With `lists`, the shadow, glow, reflection
    /// and soft edge are rebuilt from the model and the list's other effects kept; with `bevel`, the `a:bevelT` is
    /// swapped and the rest of the 3-D settings kept.
    static func _effectsEdited(_ effects: String, shadow: CharShadow?, glow: (Double, Color)?, reflection: Reflection?,
                               softEdge: Double?, bevel: ShapeBevel?, lists: Bool, bevelEdit: Bool, emptyList: Bool = false) -> String {
        var list = _element(effects, "a:effectLst").map { String(effects[$0]) }
        let dag = _element(effects, "a:effectDag").map { String(effects[$0]) } ?? ""
        var scene = _element(effects, "a:scene3d").map { String(effects[$0]) } ?? ""
        var sp3d = _element(effects, "a:sp3d").map { String(effects[$0]) } ?? ""
        if lists {
            var attrs = ""
            var kids: [(Int, String)] = []
            if let l = list, let gt = l.firstIndex(of: ">") {
                attrs = String(l[l.index(l.startIndex, offsetBy: "<a:effectLst".count)..<gt])
                if attrs.hasSuffix("/") { attrs.removeLast() }
                if !l[..<gt].hasSuffix("/") {
                    let body = String(l[l.index(after: gt)..<(l.rangeOfSubstring("</a:effectLst>")?.lowerBound ?? l.endIndex)])
                    let rank = ["a:blur": 0, "a:fillOverlay": 1, "a:glow": 2, "a:innerShdw": 3, "a:outerShdw": 4,
                                "a:prstShdw": 5, "a:reflection": 6, "a:softEdge": 7]
                    for c in _children(body) {
                        if ["a:glow", "a:outerShdw", "a:softEdge"].contains(c.tag) { continue }
                        if c.tag == "a:reflection" { continue }
                        kids.append((rank[c.tag] ?? 8, c.xml))
                    }
                }
            }
            if let g = glow { kids.append((2, _glowXML(g.0, g.1))) }
            if let s = shadow { kids.append((4, _outerShadowXML(s))) }
            if let r = reflection, !r.onText { kids.append((6, _reflectionXML(r))) }
            if let e = softEdge, e > 0 { kids.append((7, "<a:softEdge rad=\"\(Int((e * Pptx.emu).rounded()))\"/>")) }
            // (A reflection of the text lives on its runs: the file's list keeps none of its own.)
            if list != nil || !kids.isEmpty || emptyList {
                let sorted = kids.enumerated().sorted { ($0.element.0, $0.offset) < ($1.element.0, $1.offset) }
                list = "<a:effectLst\(attrs)>" + sorted.map { $0.element.1 }.joined() + "</a:effectLst>"
            } else { list = nil }
        }
        if bevelEdit {
            var attrs = "", rest = ""
            if let gt = sp3d.firstIndex(of: ">"), !sp3d.isEmpty {
                attrs = String(sp3d[sp3d.index(sp3d.startIndex, offsetBy: "<a:sp3d".count)..<gt])
                if attrs.hasSuffix("/") { attrs.removeLast() }
                if !sp3d[..<gt].hasSuffix("/") {
                    let body = String(sp3d[sp3d.index(after: gt)..<(sp3d.rangeOfSubstring("</a:sp3d>")?.lowerBound ?? sp3d.endIndex)])
                    rest = _children(body).filter { $0.tag != "a:bevelT" }.map(\.xml).joined()
                }
            }
            if let b = bevel {
                if let m = attrs.rangeOfSubstring(" prstMaterial=\""), let q = attrs[m.upperBound...].firstIndex(of: "\"") { attrs.removeSubrange(m.lowerBound...q) }
                if b.material != "warmMatte" { attrs += " prstMaterial=\"\(b.material)\"" }
                sp3d = "<a:sp3d\(attrs)>\(_bevelXML(b))\(rest)</a:sp3d>"
                if scene.isEmpty {
                    scene = "<a:scene3d><a:camera prst=\"orthographicFront\"/><a:lightRig rig=\"\(b.rig)\" dir=\"t\"/></a:scene3d>"
                }
            } else {
                sp3d = (attrs.isEmpty && rest.isEmpty) ? "" : "<a:sp3d\(attrs)>\(rest)</a:sp3d>"
            }
        }
        return (list ?? "") + dag + scene + sp3d
    }
}

// MARK: - Slide Master view: one page written for a layout or master part

extension PptxWriter {
    /// A master or layout page written through the slide writer: its `p:cSld`, the relationships that
    /// markup names, and the parts those reach (pictures, charts), by absolute part name.
    struct MasterPage {
        var cSld: String
        var namespaces: [String: String]
        var rels: [Rel]
        var files: [String: Data]
    }

    static func masterPage(_ slide: SlideState, name: String, source: PptxPackage) -> MasterPage? {
        var b = PackageBuilder()
        var media = MediaParts()
        let part = "ppt/slides/slide1.xml"
        _slide(slide, number: 1, part: part, layoutPart: nil, notesMaster: nil, source: source, media: &media, into: &b)
        guard let root = b.parts[part].flatMap(XNode.parse), let c = root.first("p:cSld") else { return nil }
        c.attrs["name"] = name
        var ns: [String: String] = [:]
        for (k, v) in root.attrs where k.hasPrefix("xmlns:") { ns[k] = v }
        var rels: [Rel] = []
        var files: [String: Data] = [:]
        for r in b.parts[Pptx.relsPath(part)].flatMap(XNode.parse)?.all("Relationship") ?? [] {
            guard let id = r["Id"], let type = r["Type"], let target = r["Target"] else { continue }
            let external = r["TargetMode"] == "External"
            if external { rels.append(Rel(id: id, type: type, target: target, external: true)); continue }
            let abs = Pptx.resolve(target, from: part)
            if type.hasSuffix("/slideLayout") || type.hasSuffix("/notesSlide") { continue }
            rels.append(Rel(id: id, type: type, target: abs))
            if let d = b.parts[abs] { files[abs] = d }
            if let d = b.parts[Pptx.relsPath(abs)] { files[Pptx.relsPath(abs)] = d }
        }
        return MasterPage(cSld: PptxXML.serialize(c), namespaces: ns, rels: rels, files: files)
    }
}
