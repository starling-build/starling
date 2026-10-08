// Copyright the Starling authors
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
import FlutterSwiftBridge
#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif

enum PptxWriter {
    static func write(_ state: DeckState, theme: DeckTheme, package: PptxPackage?,
                      ownTemplates: Bool = false) throws -> Data {
        var b = PackageBuilder()
        if let package, !ownTemplates, _usable(package) {
            try _writeThrough(package, state: state, theme: theme, into: &b)
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
        let t = PptxTemplates(theme: theme, slideSize: state.slideSize)
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
        b.add("ppt/presentation.xml", t.presentation(slideIds: ids), type: CT.presentation)
    }

    // MARK: Through a package

    private static func _writeThrough(_ p: PptxPackage, state: DeckState, theme: DeckTheme,
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
        var copied = Set<String>()
        for part in keep { _copy(part, from: p, into: &b, done: &copied) }
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
        var ids = ""
        var media = MediaParts()
        for (i, slide) in state.slides.enumerated() {
            let part = "ppt/slides/slide\(i + 1).xml"
            let layout = slide.layoutPart.flatMap { p.parts[$0] != nil ? $0 : nil } ?? layoutFor(slide.layout)
            _slide(slide, number: i + 1, part: part, layoutPart: layout, notesMaster: notesMaster,
                   source: p, media: &media, into: &b)
            presRels.append(Rel(id: "rIdS\(i + 1)", type: RT.slide, target: Pptx.relative(part, from: pres)))
            ids += "<p:sldId id=\"\(256 + i)\" r:id=\"rIdS\(i + 1)\"/>"
        }
        b.rels(pres, presRels)
        presOut = _replaceElement("p:sldIdLst", in: presOut, with: "<p:sldIdLst>\(ids)</p:sldIdLst>",
                                  after: "</p:notesMasterIdLst>", orAfter: "</p:sldMasterIdLst>")
        // Custom shows (`p:custShowLst`) list slides by the same relationship
        // ids this just renumbered: each `<p:sld r:id>` follows its slide,
        // or goes when the slide did; an emptied show goes with it.
        if presOut.containsSubstring("<p:custShowLst") {
            var newId: [String: String] = [:]
            for r in presRelsAll where r.kind == "slide" {
                if let i = state.slides.firstIndex(where: { $0.sourcePart == r.target }) { newId[r.id] = "rIdS\(i + 1)" }
            }
            presOut = _remapCustomShows(presOut, newId)
        }
        let cx = Int((state.slideSize.width * Pptx.emu).rounded()), cy = Int((state.slideSize.height * Pptx.emu).rounded())
        presOut = _replaceElement("p:sldSz", in: presOut, with: "<p:sldSz cx=\"\(cx)\" cy=\"\(cy)\"/>",
                                  after: "</p:sldIdLst>", orAfter: nil)
        // Always a presentation: a macro-enabled deck, a template or a show
        // read in becomes a plain .pptx, which is what this writes.
        b.add(pres, presOut, type: CT.presentation)
    }

    /// Copy a part, its relationships, and everything they reach.
    private static func _copy(_ part: String, from p: PptxPackage, into b: inout PackageBuilder, done: inout Set<String>) {
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
        // Shape ids: a shape read from a file keeps its own (the slide's
        // animations name shapes by id); new ones start above them all.
        w.nextId = 2 + (slide.shapes.compactMap(\.fileId).max() ?? 0)
        var body = ""
        // Members of a group read from the file, still side by side, are
        // grouped again under the group's own id.
        var i = 0
        while i < slide.shapes.count {
            guard let g = slide.shapes[i].group else {
                body += w.shape(slide.shapes[i], media: &media, builder: &b)
                i += 1
                continue
            }
            var j = i
            while j < slide.shapes.count, slide.shapes[j].group?.key == g.key { j += 1 }
            body += w.group(g, members: Array(slide.shapes[i ..< j]), media: &media, builder: &b)
            i = j
        }
        var bg = ""
        if let xml = slide.backgroundXML, let src = slide.sourcePart, let p = source {
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
        if let c = slide.controlsXML, let src = slide.sourcePart, let p = source {
            controls = w.kept(c, sourcePart: src, package: p, builder: &b, patch: nil)
        }
        if body.containsSubstring("<p:oleObj") || !controls.isEmpty, let src = slide.sourcePart, let p = source,
           let vml = p.rels(src).first(where: { $0.kind == "vmlDrawing" && !$0.external && p.parts[$0.target] != nil }) {
            var done = Set<String>()
            PptxWriterCopy.copy(vml.target, from: p, into: &b, done: &done)
            rels.append(Rel(id: "rIdVml", type: vml.type, target: Pptx.relative(vml.target, from: part)))
        }
        let hidden = (slide.hidden ? " show=\"0\"" : "") + (slide.hideMasterShapes ? " showMasterSp=\"0\"" : "")
        // Kept XML may lean on prefixes the source slide declared at its
        // root (a14, p14, mc…): the same declarations go on ours.
        var ns = PptxTemplates.namespaces
        if let src = slide.sourcePart, let root = source?.xml(src) {
            for (k, v) in root.attrs.sorted(by: { $0.key < $1.key })
            where k.hasPrefix("xmlns:") && !["xmlns:a", "xmlns:r", "xmlns:p"].contains(k) {
                ns += " \(k)=\"\(PptxXML.escape(v, attribute: true))\""
            }
        }
        var transition = _transition(slide.transition, namespaces: &ns)
        // Kept as read, a transition's sound (`p:snd r:embed`) still names
        // the source slide's relationship: remap it, carrying the .wav.
        if slide.transition.raw != nil, transition.containsSubstring("r:embed"), let src = slide.sourcePart, let p = source {
            transition = w.kept(transition, sourcePart: src, package: p, builder: &b, patch: nil)
        }
        // Animations: as read while unchanged (or, for timing this app does
        // not model, while every shape it names is still here); our own
        // timing tree once they are edited.
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
                if t.containsSubstring("r:embed"), let src = slide.sourcePart, let p = source {
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
        rels += w.rels
        // The colour map as read when the slide was; a slide of ours maps
        // through the master.
        let clrMapOvr = slide.clrMapOvrXML.map { $0.containsSubstring("overrideClrMapping") ? $0 : "" }
            .flatMap { $0.isEmpty ? nil : $0 } ?? "<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>"
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <p:sld \(ns)\(hidden)><p:cSld>\(bg)<p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>\(body)</p:spTree>\(controls)</p:cSld>\(clrMapOvr)\(transition)\(timing)</p:sld>
        """

        // Notes, when there are any and a notes master to hang them on.
        if let notesMaster, !slide.notes.paragraphs.allSatisfy({ $0.text.isEmpty }) {
            let notesPart = "ppt/notesSlides/notesSlide\(number).xml"
            b.add(notesPart, PptxTemplates.notesSlide(PptxText.paragraphsPlain(slide.notes)), type: CT.notesSlide)
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
        if let raw = t.raw {
            for (prefix, uri) in [("mc", "http://schemas.openxmlformats.org/markup-compatibility/2006"),
                                  ("p14", "http://schemas.microsoft.com/office/powerpoint/2010/main")]
            where raw.containsSubstring("\(prefix):") && !ns.containsSubstring("xmlns:\(prefix)=") {
                ns += " xmlns:\(prefix)=\"\(uri)\""
            }
            return raw
        }
        guard t.kind != .none else { return "" }
        let spd = t.duration <= 0.5 ? "fast" : t.duration >= 1.0 ? "slow" : "med"
        let effect: String
        switch t.kind {
        case .fade: effect = "<p:fade/>"
        case .push: effect = "<p:push dir=\"\(t.direction.rawValue)\"/>"
        case .wipe: effect = "<p:wipe dir=\"\(t.direction.rawValue)\"/>"
        case .cover: effect = "<p:cover dir=\"\(t.direction.rawValue)\"/>"
        case .none: effect = ""
        }
        return "<p:transition spd=\"\(spd)\">\(effect)</p:transition>"
    }

    /// `p:custShowLst` with every `<p:sld r:id="…"/>` renamed through
    /// `newId`, listed slides without a new id dropped, shows left with no
    /// slides dropped, and the list itself dropped once it is empty.
    static func _remapCustomShows(_ s: String, _ newId: [String: String]) -> String {
        guard let start = s.findRange(of: "<p:custShowLst"),
              let end = s.findRange(of: "</p:custShowLst>", in: start.upperBound ..< s.endIndex) else { return s }
        let list = String(s[start.lowerBound ..< end.upperBound])
        /// Every `<open …>…<close>` span of `list`, rewritten by `f` (nil drops it).
        func rewrite(_ list: String, open: String, close: String, _ f: (String) -> String?) -> String {
            var out = "", cursor = list.startIndex
            while let r = list.findRange(of: open, in: cursor ..< list.endIndex) {
                out += list[cursor ..< r.lowerBound]
                guard let c = list.findRange(of: close, in: r.upperBound ..< list.endIndex) else { cursor = r.lowerBound; break }
                if let kept = f(String(list[r.lowerBound ..< c.upperBound])) { out += kept }
                cursor = c.upperBound
            }
            return out + list[cursor...]
        }
        var pruned = rewrite(list, open: "<p:sld ", close: "/>") { tag in
            guard let q = tag.findRange(of: "r:id=\""),
                  let qe = tag.findRange(of: "\"", in: q.upperBound ..< tag.endIndex),
                  let new = newId[String(tag[q.upperBound ..< qe.lowerBound])] else { return nil }
            return "<p:sld r:id=\"\(new)\"/>"
        }
        pruned = rewrite(pruned, open: "<p:custShow ", close: "</p:custShow>") { $0.containsSubstring("<p:sld ") ? $0 : nil }
        if !pruned.containsSubstring("<p:custShow ") { pruned = "" }
        return s.replacingSubrange(start.lowerBound ..< end.upperBound, with: pruned)
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
        try PptxWriter.write(deck.snapshot(), theme: deck.theme, package: deck.package, ownTemplates: deck.ownTemplates)
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
    static let layout = base + "slideLayout"
    static let master = base + "slideMaster"
    static let notesSlide = base + "notesSlide"
    static let notesMaster = base + "notesMaster"
    static let theme = base + "theme"
    static let image = base + "image"
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

    /// A fill element: solid, linear gradient or stretched picture.
    mutating func fill(_ f: SlideFill, media: inout MediaParts, builder: inout PackageBuilder) -> String {
        if let image = f.image {
            let rid = _media(image, media: &media, builder: &builder)
            return "<a:blipFill dpi=\"0\" rotWithShape=\"1\"><a:blip r:embed=\"\(rid)\"/><a:srcRect/><a:stretch><a:fillRect/></a:stretch></a:blipFill>"
        }
        if f.stops.count >= 2 {
            let stops = f.stops.map { "<a:gs pos=\"\(Int(($0.position * 100000).rounded()))\"><a:srgbClr val=\"\(PptxText.hex($0.color))\"/></a:gs>" }.joined()
            return "<a:gradFill rotWithShape=\"1\"><a:gsLst>\(stops)</a:gsLst><a:lin ang=\"\(Int((f.angle * 60000).rounded()))\" scaled=\"0\"/></a:gradFill>"
        }
        return Self._fill(f.color ?? Color(0xFFFFFFFF))
    }

    private static func _crop(_ c: EdgeInsets?) -> String {
        guard let c, c != .zero else { return "" }
        func v(_ x: Double) -> Int { Int((x * 100000).rounded()) }
        return "<a:srcRect l=\"\(v(c.left))\" t=\"\(v(c.top))\" r=\"\(v(c.right))\" b=\"\(v(c.bottom))\"/>"
    }

    private static func _fill(_ c: Color?) -> String {
        guard let c else { return "<a:noFill/>" }
        let alpha = (c.value >> 24) & 0xFF
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
        switch s.kind {
        case .opaque(let o):
            guard let p = source else { return "" }
            return kept(o.xml, sourcePart: o.sourcePart, package: p, builder: &builder, patch: s.frame, fileId: s.fileId)
        case .picture(let image):
            // Unchanged since it was read (same image, crop and turn): the
            // picture as it was, at its frame — its recolouring, transparency,
            // shape crop, flip, fill and outline are not modelled here.
            if let xml = s.sourceXML, let k = s.keptPicture, k.imageId == image.id, k.crop == s.crop,
               k.rotation == s.rotation, let p = source, let part = s.sourcePart {
                return kept(xml, sourcePart: part, package: p, builder: &builder, patch: s.frame, fileId: s.fileId)
            }
            let id = _id(s.fileId)
            let rid = _media(image, media: &media, builder: &builder)
            return "<p:pic><p:nvPicPr><p:cNvPr id=\"\(id)\" name=\"\(name)\"/><p:cNvPicPr><a:picLocks noChangeAspect=\"1\"/></p:cNvPicPr><p:nvPr/></p:nvPicPr>"
                + "<p:blipFill><a:blip r:embed=\"\(rid)\"/>\(Self._crop(s.crop))<a:stretch><a:fillRect/></a:stretch></p:blipFill>"
                + "<p:spPr>\(Self._xfrm(s.frame, rotation: s.rotation))<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></p:spPr></p:pic>"
        case .table:
            // Unedited since it was read: the table as it was, in place.
            if let xml = s.sourceXML, let doc = s.text, doc == s.sourceText, let p = source, let part = s.sourcePart {
                return kept(xml, sourcePart: part, package: p, builder: &builder, patch: s.frame, fileId: s.fileId)
            }
            return _table(s, name: name)
        case .chart(let chart):
            // Unchanged since it was read: through its own part, which keeps
            // whatever of the file's styling this app does not model.
            if let xml = s.sourceXML, chart == s.sourceChart, let p = source, let part = s.sourcePart {
                return kept(xml, sourcePart: part, package: p, builder: &builder, patch: s.frame, fileId: s.fileId)
            }
            return _chart(chart, s, name: name, media: &media, builder: &builder)
        case .geometry(let preset) where preset.isLine && s.text == nil:
            // A connector as read, while its line and outline are: the
            // original, at its frame on the slide.
            if let xml = s.sourceXML, let k = s.keptLine, k.line == s.frame, k.outline == s.outline,
               k.width == s.outlineWidth, let p = source, let part = s.sourcePart {
                return kept(xml, sourcePart: part, package: p, builder: &builder, patch: k.box, fileId: s.fileId)
            }
            let id = _id(s.fileId)
            let f = s.frame
            let box = Rect.fromLTRB(min(f.left, f.right), min(f.top, f.bottom), max(f.left, f.right), max(f.top, f.bottom))
            let line = s.outline.map { "<a:ln w=\"\(Self._emu(s.outlineWidth))\">\(Self._fill($0))</a:ln>" } ?? "<a:ln><a:noFill/></a:ln>"
            return "<p:cxnSp><p:nvCxnSpPr><p:cNvPr id=\"\(id)\" name=\"\(name)\"/><p:cNvCxnSpPr/><p:nvPr/></p:nvCxnSpPr>"
                + "<p:spPr>\(Self._xfrm(box, rotation: s.rotation, flipH: f.right < f.left, flipV: f.bottom < f.top))"
                + "<a:prstGeom prst=\"\(preset.rawValue)\"><a:avLst/></a:prstGeom>\(line)</p:spPr></p:cxnSp>"
        default:
            // Unchanged since it was read, text and all: the shape as it
            // was, so what this app models loosely (the master's bullets,
            // run effects, tab stops) comes back untouched.
            if let xml = s.sourceXML, let read = s.readShape, read.unchanged(s),
               let p = source, let part = s.sourcePart {
                return kept(xml, sourcePart: part, package: p, builder: &builder, patch: s.frame, fileId: s.fileId)
            }
            let id = _id(s.fileId)
            var nv = "<p:cNvPr id=\"\(id)\" name=\"\(name)\"/>"
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
                nv += "<p:cNvSpPr txBox=\"1\"/>"
            default:
                nv += "<p:cNvSpPr/>"
            }
            var spPr = Self._xfrm(s.frame, rotation: s.rotation)
            let prst: String = {
                switch s.kind {
                case .geometry(let p): return p.rawValue
                default: return "rect"
                }
            }()
            spPr += "<a:prstGeom prst=\"\(prst)\"><a:avLst/></a:prstGeom>"
            var fillXML: String, lineXML: String
            switch s.kind {
            case .placeholder:
                fillXML = s.fill.map { Self._fill($0) } ?? ""
                lineXML = s.outline.map { "<a:ln w=\"\(Self._emu(s.outlineWidth))\">\(Self._fill($0))</a:ln>" } ?? ""
            default:
                if let scheme = s.fillScheme, s.fill != nil {
                    fillXML = "<a:solidFill><a:schemeClr val=\"\(scheme)\"/></a:solidFill>"
                } else {
                    fillXML = Self._fill(s.fill)
                }
                lineXML = s.outline.map { "<a:ln w=\"\(Self._emu(s.outlineWidth))\">\(Self._fill($0))</a:ln>" } ?? "<a:ln><a:noFill/></a:ln>"
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
            }
            spPr += fillXML + lineXML + (look?.effects ?? "")
            var xml = "<p:sp><p:nvSpPr>\(nv)<p:nvPr>\(ph)</p:nvPr></p:nvSpPr><p:spPr>\(spPr)</p:spPr>\(look?.style ?? "")"
            if let doc = s.text {
                let anchor = s.anchor.rawValue
                let ins = s.insets
                let fit: String
                if s.autofit {
                    // Shrink to fit — a text box can say so too.
                    let scale = Int((s.fontScale * 100000).rounded())
                    fit = scale < 100000 ? "<a:normAutofit fontScale=\"\(scale)\"/>" : "<a:normAutofit/>"
                } else if s.kind == .textBox {
                    fit = "<a:spAutoFit/>"
                } else {
                    fit = "<a:noAutofit/>"
                }
                xml += "<p:txBody><a:bodyPr wrap=\"square\" lIns=\"\(Self._emu(ins.left))\" tIns=\"\(Self._emu(ins.top))\" "
                    + "rIns=\"\(Self._emu(ins.right))\" bIns=\"\(Self._emu(ins.bottom))\" anchor=\"\(anchor)\" rtlCol=\"0\">\(fit)</a:bodyPr>"
                    + "<a:lstStyle/>" + PptxText.paragraphs(doc, defaults: s, field: s.field) + "</p:txBody>"
            }
            return xml + "</p:sp>"
        }
    }

    /// A chart of our own: its part (values cached), the workbook it was
    /// drawn from, and the frame that places it.
    private mutating func _chart(_ chart: Chart, _ s: ShapeState, name: String, media: inout MediaParts,
                                 builder: inout PackageBuilder) -> String {
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
        return "<p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id=\"\(id)\" name=\"\(name)\"/><p:cNvGraphicFramePr><a:graphicFrameLocks noGrp=\"1\"/></p:cNvGraphicFramePr><p:nvPr/></p:nvGraphicFramePr>"
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
        let rowH = Self._emu(s.frame.height / Double(rows))
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
        func border(_ tag: String) -> String {
            guard style.borders else { return "<\(tag) w=\"12700\"><a:noFill/></\(tag)>" }
            let c = style.borderColor ?? Color(0xFF000000)
            return "<\(tag) w=\"12700\"><a:solidFill><a:srgbClr val=\"\(PptxText.hex(c))\"/></a:solidFill></\(tag)>"
        }
        let borders = border("a:lnL") + border("a:lnR") + border("a:lnT") + border("a:lnB")
        var xml = "<p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id=\"\(_id(s.fileId))\" name=\"\(name)\"/>"
            + "<p:cNvGraphicFramePr><a:graphicFrameLocks noGrp=\"1\"/></p:cNvGraphicFramePr><p:nvPr/></p:nvGraphicFramePr>"
            + Self._xfrm(s.frame, rotation: 0, tag: "p:xfrm")
            + "<a:graphic><a:graphicData uri=\"http://schemas.openxmlformats.org/drawingml/2006/table\"><a:tbl>"
            + "<a:tblPr firstRow=\"\(style.headerRow ? 1 : 0)\" bandRow=\"\(style.bandFill != nil ? 1 : 0)\">"
            + "<a:tableStyleId>{5C22544A-7EE6-4342-B048-85BDC9FD1C3A}</a:tableStyleId></a:tblPr><a:tblGrid>"
            + widths.map { "<a:gridCol w=\"\(Self._emu($0))\"/>" }.joined() + "</a:tblGrid>"
        for r in 0 ..< rows {
            xml += "<a:tr h=\"\(rowH)\">"
            for k in 0 ..< cols {
                if let stand = covered[r]?[k] {
                    xml += "<a:tc \(stand)=\"1\"><a:txBody><a:bodyPr/><a:lstStyle/><a:p/></a:txBody><a:tcPr/></a:tc>"
                    continue
                }
                let paras = doc.paragraphs.filter { $0.cell?.row == r && $0.cell?.column == k }
                guard let cell = paras.first?.cell else {
                    xml += "<a:tc><a:txBody><a:bodyPr/><a:lstStyle/><a:p/></a:txBody><a:tcPr>\(borders)\(fill(r))</a:tcPr></a:tc>"
                    continue
                }
                var attrs = ""
                if cell.span > 1 { attrs += " gridSpan=\"\(cell.span)\"" }
                if cell.rowSpan > 1 { attrs += " rowSpan=\"\(cell.rowSpan)\"" }
                let body = PptxText.paragraphs(RichDocument(paragraphs: paras.map { var p = $0; p.cell = nil; return p }), defaults: s)
                xml += "<a:tc\(attrs)><a:txBody><a:bodyPr/><a:lstStyle/>\(body)</a:txBody><a:tcPr anchor=\"ctr\">\(borders)\(fill(r))</a:tcPr></a:tc>"
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
                       builder b: inout PackageBuilder, patch frame: Rect?, fileId: Int? = nil) -> String {
        guard let node = XNode.parse(Data(xml.utf8)) else { return "" }
        if let frame {
            let x = node.first("p:xfrm") ?? node.first("p:spPr")?.first("a:xfrm") ?? node.first("p:grpSpPr")?.first("a:xfrm")
            if let x {
                if let off = x.first("a:off") { off.attrs["x"] = "\(Self._emu(frame.left))"; off.attrs["y"] = "\(Self._emu(frame.top))" }
                if let ext = x.first("a:ext") { ext.attrs["cx"] = "\(Self._emu(frame.width))"; ext.attrs["cy"] = "\(Self._emu(frame.height))" }
            }
            if let c = node.descendant("p:cNvPr") { c.attrs["id"] = "\(_id(fileId ?? c["id"].flatMap(Int.init)))" }
        }
        let sourceRels = p.rels(sourcePart)
        var done = Set<String>()
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
                } else if p.parts[r.target] == nil {
                    // A part the file names but does not have (a damaged
                    // file): no relationship to nowhere.
                    n.attrs[k] = nil
                    if referenceOnly.contains(n.name) { dead = true }
                } else {
                    var copied = done
                    PptxWriterCopy.copy(r.target, from: p, into: &b, done: &copied)
                    done = copied
                    n.attrs[k] = _rel(r.type, Pptx.relative(r.target, from: part), preferred: v)
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
    static func copy(_ part: String, from p: PptxPackage, into b: inout PackageBuilder, done: inout Set<String>) {
        guard !done.contains(part), let data = p.parts[part] else { return }
        done.insert(part)
        b.parts[part] = data
        if let type = p.overrides[part] {
            b.overrides[part] = type
        } else if let ext = part.split(separator: ".").last.map({ String($0).lowercased() }),
                  b.defaults[ext] == nil, let type = p.defaults[ext] {
            // A part typed by extension (a video.avi, a .wav): the file's own
            // Default carries over, or the package has a part with no type.
            b.defaults[ext] = type
        }
        let relsPart = Pptx.relsPath(part)
        if let rels = p.parts[relsPart] {
            b.parts[relsPart] = rels
            for r in p.rels(part) where !r.external { copy(r.target, from: p, into: &b, done: &done) }
        }
    }
}

// MARK: - Text

enum PptxText {
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
            case .bullet?: inner += "<a:buFont typeface=\"Arial\"/><a:buChar char=\"•\"/>"
            case .numbered?: inner += "<a:buFont typeface=\"+mj-lt\"/><a:buAutoNum type=\"arabicPeriod\"/>"
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
        switch c.script {
        case .superscript: a += " baseline=\"30000\""
        case .subscript: a += " baseline=\"-25000\""
        case .normal: break
        }
        a += " dirty=\"0\""
        let color = c.color ?? s.color
        let font = PptxXML.escape(c.fontFamily ?? s.font ?? "Calibri", attribute: true)
        return "<\(tag)\(a)><a:solidFill><a:srgbClr val=\"\(hex(color))\"/></a:solidFill>"
            + "<a:latin typeface=\"\(font)\"/><a:cs typeface=\"\(font)\"/></\(tag)>"
    }

    /// Notes: plain paragraphs, no looks.
    static func paragraphsPlain(_ doc: RichDocument) -> String {
        doc.paragraphs.map { p in
            let parts = p.text.components(separatedBy: "\n").map {
                $0.isEmpty ? "" : "<a:r><a:rPr lang=\"en-US\" dirty=\"0\"/><a:t>\(PptxXML.escape($0, attribute: false))</a:t></a:r>"
            }
            return "<a:p>" + parts.joined(separator: "<a:br><a:rPr lang=\"en-US\"/></a:br>") + "</a:p>"
        }.joined()
    }
}
