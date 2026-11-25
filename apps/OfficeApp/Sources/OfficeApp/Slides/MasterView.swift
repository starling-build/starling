import Foundation
import Flutter
import OfficeText
import FlutterSwiftBridge

// Slide Master view. The deck's own pages are swapped for one page per master and per layout, built by
// writing the deck, reading the file back, and standing each master or layout part in as a slide part. They
// edit like slides. Closing writes every page back into its master or layout part (the markup outside the
// page is kept as it was), adds, renames and removes layout parts, and reads the result as the deck.

/// Which master or layout a Slide Master view page stands for.
struct MasterRole: Equatable {
    enum Kind { case master, layout }
    var kind: Kind
    /// The master part this page belongs to.
    var master: String
    /// The part the page was read from (a new layout takes its markup from a sibling).
    var part: String
    var name: String
    /// A layout made in this view: it has no part of its own yet.
    var fresh = false
}

struct MasterViewState {
    /// The deck as a file, before the view opened: closing writes into a copy of it.
    var base: PptxPackage
    var theme: DeckTheme
    var returnTo: Int
    /// Each master's title and body paragraphs' first-run look as the view opened, by master part and "title:i" / "body:i".
    var textBaseline: [String: MasterTextLook] = [:]
}

/// What the font controls set on a master's title or body paragraph: compared at close, so a changed look
/// reaches the master's `p:txStyles` (the style every slide and layout inherits).
struct MasterTextLook: Equatable {
    var bold: Bool
    var italic: Bool
    var family: String?
    var size: Double?
    var color: String?

    init(_ c: CharStyle) {
        bold = c.bold
        italic = c.italic
        family = c.fontFamily
        size = c.fontSize
        color = c.color.map { PptxText.hex($0) }
    }

    /// Title and body paragraphs of a master page, keyed like `MasterViewState.textBaseline`.
    static func looks(of page: SlideState, master: String) -> [String: MasterTextLook] {
        looks(page.shapes.map { ($0.phType, $0.text, nil) }, master: master)
    }

    /// The same for the live page: an empty paragraph (a master's prompt text) takes the editor's typing style,
    /// which is where a font control lands when nothing is selected.
    static func looks(of slide: Slide, master: String) -> [String: MasterTextLook] {
        looks(slide.shapes.map { ($0.phType, $0.text?.document, $0.text?.typingStyle) }, master: master)
    }

    private static func looks(_ shapes: [(String?, RichDocument?, CharStyle?)], master: String) -> [String: MasterTextLook] {
        var out: [String: MasterTextLook] = [:]
        for (phType, doc, typing) in shapes {
            guard let t = phType, t == "title" || t == "ctrTitle" || t == "body", let doc else { continue }
            let kind = t == "body" ? "body" : "title"
            for (i, para) in doc.paragraphs.enumerated() {
                let style = (para.text.isEmpty && i == 0 ? typing : nil) ?? para.runs.first?.style
                guard let style else { continue }
                out["\(master)|\(kind):\(i)"] = MasterTextLook(style)
            }
        }
        return out
    }
}

extension DeckController {
    var inMasterView: Bool { masterView != nil }

    // MARK: Open

    func enterMasterView() throws {
        guard masterView == nil else { return }
        let data = try PptxWriter.write(snapshot(), theme: theme, package: package, ownTemplates: ownTemplates, recolourTheme: recolourTheme)
        let (_, theme, base) = try Pptx.read(data)
        var p = base
        guard let presPart = Self._presentationPart(base), var pres = base.xml(presPart) else { throw Pptx.ReadError.noPresentation }
        var presRels = base.rels(presPart).map { Rel(id: $0.id, type: $0.type, target: Pptx.relative($0.target, from: presPart), external: $0.external) }
        var roles: [MasterRole] = []
        var ids = ""
        func relsText(_ rels: [Rel], _ part: String) {
            var b = PackageBuilder()
            b.rels(part, rels)
            p.parts[Pptx.relsPath(part)] = b.parts[Pptx.relsPath(part)]
        }
        func addPage(_ node: XNode, from part: String, role: MasterRole, layoutTarget: String) {
            let page = "ppt/slides/mv\(roles.count + 1).xml"
            node.name = "p:sld"
            node.children = node.children.filter { $0.name == "p:cSld" }
            p.parts[page] = Data(PptxXML.serialize(node).utf8)
            var rels = base.rels(part).filter { $0.kind != "slideMaster" && $0.kind != "slideLayout" && $0.kind != "theme" }
                .map { Rel(id: $0.id, type: $0.type, target: $0.external ? $0.target : Pptx.relative($0.target, from: page), external: $0.external) }
            rels.append(Rel(id: "rIdMvLayout", type: RT.layout, target: Pptx.relative(layoutTarget, from: page)))
            relsText(rels, page)
            p.overrides[page] = CT.slide
            let rid = "rIdMvPage\(roles.count + 1)"
            presRels.append(Rel(id: rid, type: RT.slide, target: Pptx.relative(page, from: presPart)))
            ids += "<p:sldId id=\"\(256 + roles.count)\" r:id=\"\(rid)\"/>"
            roles.append(role)
        }
        for m in base.rels(presPart) where m.kind == "slideMaster" && !m.external {
            guard let mxml = base.xml(m.target) else { continue }
            let layouts = Self._layoutParts(of: m.target, in: base)
            guard let first = layouts.first else { continue }
            addPage(mxml, from: m.target, role: MasterRole(kind: .master, master: m.target, part: m.target,
                                                           name: mxml.first("p:cSld")?["name"] ?? "Slide Master"), layoutTarget: first)
            for l in layouts {
                guard let lxml = base.xml(l) else { continue }
                addPage(lxml, from: l, role: MasterRole(kind: .layout, master: m.target, part: l,
                                                        name: lxml.first("p:cSld")?["name"] ?? Self._layoutTitle(lxml)), layoutTarget: l)
            }
        }
        guard !roles.isEmpty else { throw Pptx.ReadError.notAPresentation }
        pres.children.removeAll { $0.name == "p:sldIdLst" }
        let list = XNode.parse(Data("<p:sldIdLst xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\">\(ids)</p:sldIdLst>".utf8))!
        let at = (pres.children.lastIndex { ["p:sldMasterIdLst", "p:notesMasterIdLst", "p:handoutMasterIdLst"].contains($0.name) } ?? -1) + 1
        pres.children.insert(list, at: at)
        p.parts[presPart] = Data(PptxXML.serialize(pres).utf8)
        relsText(presRels, presPart)
        let entries = p.parts.map { ZipEntry(name: $0.key, data: $0.value) }
        var (state, _, package) = try Pptx.read(try Zip.write(entries))
        guard state.slides.count == roles.count else { throw Pptx.ReadError.notAPresentation }
        let back = current
        for i in state.slides.indices {
            state.slides[i].masterRole = roles[i]
            state.slides[i].section = nil
            state.slides[i].transition = SlideTransition()
            state.slides[i].timingXML = nil
            state.slides[i].animations = []
            // What the master draws shows behind a layout; a master or a layout's own shapes are the page.
            state.slides[i].decorations = roles[i].kind == .layout
                ? state.slides[i].decorations.filter { $0.sourcePart == roles[i].master } : []
        }
        state.sections = []
        state.show = ShowSettings()
        state.customShows = []
        state.current = 0
        let keep = masterView
        load(state, theme: theme, package: package)
        var view = keep ?? MasterViewState(base: base, theme: theme, returnTo: back)
        if keep == nil {
            for page in state.slides {
                guard let r = page.masterRole, r.kind == .master else { continue }
                view.textBaseline.merge(MasterTextLook.looks(of: page, master: r.master)) { a, _ in a }
            }
        }
        masterView = view
    }

    private static func _presentationPart(_ p: PptxPackage) -> String? {
        p.xml("_rels/.rels")?.all("Relationship").first { ($0["Type"] ?? "").hasSuffix("/officeDocument") }
            .flatMap { $0["Target"] }.map { $0.hasPrefix("/") ? String($0.dropFirst()) : $0 }
    }

    /// A master's layout parts in the order its `sldLayoutIdLst` gives.
    static func _layoutParts(of master: String, in p: PptxPackage) -> [String] {
        let rels = p.rels(master)
        let listed = p.xml(master)?.first("p:sldLayoutIdLst")?.all("p:sldLayoutId").compactMap { id in
            rels.first { $0.id == id["r:id"] }?.target } ?? []
        return listed.filter { p.parts[$0] != nil }
    }

    /// The master's `p:txStyles` with each title or body level whose first-run look changed in the view updated
    /// (size, bold, italic, typeface, colour on its `a:defRPr`); the other levels are left as they were.
    static func _patchTextStyles(_ text: String, now: [String: MasterTextLook], was: [String: MasterTextLook], master: String) -> String {
        var changed: [(style: String, level: Int, look: MasterTextLook, old: MasterTextLook)] = []
        for (k, look) in now.sorted(by: { $0.key < $1.key }) {
            guard let old = was[k], old != look, let colon = k.lastIndex(of: ":"), let i = Int(k[k.index(after: colon)...]) else { continue }
            changed.append((k.rangeOfSubstring("|title:") != nil ? "p:titleStyle" : "p:bodyStyle", i + 1, look, old))
        }
        guard !changed.isEmpty, let a = text.rangeOfSubstring("<p:txStyles>"),
              let e = text.rangeOfSubstring("</p:txStyles>", in: a.lowerBound ..< text.endIndex) else { return text }
        let inner = String(text[a.lowerBound ..< e.upperBound])
        let ns = "xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\""
        guard let root = XNode.parse(Data("<w \(ns)>\(inner)</w>".utf8)), let tx = root.first("p:txStyles") else { return text }
        for c in changed {
            guard let style = tx.first(c.style), let lvl = style.first("a:lvl\(c.level)pPr") else { continue }
            let def: XNode
            if let d = lvl.first("a:defRPr") { def = d } else {
                def = XNode(name: "a:defRPr", attrs: [:])
                lvl.children.append(def)
            }
            if c.look.size != c.old.size, let sz = c.look.size { def.attrs["sz"] = String(Int((sz * 100).rounded())) }
            if c.look.bold != c.old.bold { def.attrs["b"] = c.look.bold ? "1" : "0" }
            if c.look.italic != c.old.italic { def.attrs["i"] = c.look.italic ? "1" : "0" }
            if c.look.color != c.old.color, let hex = c.look.color {
                let fills = ["a:noFill", "a:solidFill", "a:gradFill", "a:blipFill", "a:pattFill", "a:grpFill"]
                def.children.removeAll { fills.contains($0.name) }
                let fill = XNode(name: "a:solidFill", attrs: [:])
                fill.children = [XNode(name: "a:srgbClr", attrs: ["val": hex])]
                def.children.insert(fill, at: def.children.firstIndex { $0.name != "a:ln" } ?? def.children.count)
            }
            if c.look.family != c.old.family, let f = c.look.family {
                if let l = def.first("a:latin") { l.attrs = ["typeface": f] } else {
                    let after = ["a:ea", "a:cs", "a:sym", "a:hlinkClick", "a:hlinkMouseOver", "a:rtl", "a:extLst"]
                    def.children.insert(XNode(name: "a:latin", attrs: ["typeface": f]), at: def.children.firstIndex { after.contains($0.name) } ?? def.children.count)
                }
            }
        }
        return text.replacingSubrange(a.lowerBound ..< e.upperBound, with: PptxXML.serialize(tx))
    }

    private static func _layoutTitle(_ x: XNode) -> String { x["type"] ?? "Layout" }

    // MARK: Close

    func closeMasterView() throws {
        guard let view = masterView else { return }
        let data = try masterViewBytes()
        let (state, theme, package) = try Pptx.read(data)
        masterView = nil
        load(state, theme: theme, package: package)
        select(min(view.returnTo, slides.count - 1))
        edits += 1
    }

    /// The deck as a file with the view's pages written into their masters and layouts.
    func masterViewBytes() throws -> Data {
        guard let view = masterView, let source = package else { throw Pptx.ReadError.notAPresentation }
        var q = view.base
        let state = snapshot()
        var ctParts: [String: String] = [:]
        var dropParts: Set<String> = []
        var nextLayout = 1
        for n in q.parts.keys where n.hasPrefix("ppt/slideLayouts/slideLayout") && n.hasSuffix(".xml") {
            let digits = n.dropFirst("ppt/slideLayouts/slideLayout".count).dropLast(4)
            if let k = Int(digits) { nextLayout = max(nextLayout, k + 1) }
        }
        var usedIds = Set<Int>()
        for n in q.parts.keys where n.hasPrefix("ppt/slideMasters/") && n.hasSuffix(".xml") {
            let x = q.xml(n)
            for id in x?.first("p:sldLayoutIdLst")?.all("p:sldLayoutId") ?? [] { if let v = id["id"].flatMap(Int.init) { usedIds.insert(v) } }
        }
        if let pres = Self._presentationPart(q) {
            for id in q.xml(pres)?.first("p:sldMasterIdLst")?.all("p:sldMasterId") ?? [] { if let v = id["id"].flatMap(Int.init) { usedIds.insert(v) } }
        }
        var nextId = max(usedIds.max() ?? 2147483648, 2147483648) + 1
        var kept: [String: [String]] = [:]       // master -> layout parts, in order
        var keptNames: Set<String> = []
        var mediaCount = 0

        // Writes one page into `text` (a layout or master part), returning the new markup and rels.
        func spliced(_ text: String, page pg: PptxWriter.MasterPage, ownRels: [PptxRel], part: String) -> (String, [Rel]) {
            var used = Set(ownRels.map(\.id))
            var map: [String: String] = [:]
            var rels: [Rel] = ownRels.map { Rel(id: $0.id, type: $0.type, target: $0.external ? $0.target : Pptx.relative($0.target, from: part), external: $0.external) }
            var c = pg.cSld
            for r in pg.rels {
                var k = 1
                while used.contains("rIdMv\(k)") { k += 1 }
                let nid = "rIdMv\(k)"
                used.insert(nid)
                map[r.id] = nid
                var target = r.target
                if !r.external {
                    var dest = r.target
                    if let have = q.parts[dest], have != pg.files[dest] {
                        mediaCount += 1
                        let ext = dest.split(separator: ".").last.map(String.init) ?? "bin"
                        dest = "ppt/media/mv\(mediaCount).\(ext)"
                    }
                    if dest != r.target || q.parts[dest] == nil, let d = pg.files[r.target] { q.parts[dest] = d }
                    if let rd = pg.files[Pptx.relsPath(r.target)], q.parts[Pptx.relsPath(dest)] == nil { q.parts[Pptx.relsPath(dest)] = rd }
                    let ext = (dest.split(separator: ".").last.map(String.init) ?? "").lowercased()
                    if q.defaults[ext] == nil, q.overrides[dest] == nil, let t = PackageBuilder().defaults[ext] {
                        q.defaults[ext] = t
                        ctParts["Default:" + ext] = t
                    }
                    target = Pptx.relative(dest, from: part)
                }
                rels.append(Rel(id: nid, type: r.type, target: target, external: r.external))
            }
            for (old, new) in map { c = c.replacingAll("\"\(old)\"", with: "\"\(new)\"") }
            var out = text
            if let a = out.rangeOfSubstring("<p:cSld"), let e = out.rangeOfSubstring("</p:cSld>", in: a.lowerBound ..< out.endIndex) {
                out = out.replacingSubrange(a.lowerBound ..< e.upperBound, with: c)
            }
            for (k, v) in pg.namespaces.sorted(by: { $0.key < $1.key }) where !out.containsSubstring(k + "=") {
                if let r = out.rangeOfSubstring("<p:sldLayout ") ?? out.rangeOfSubstring("<p:sldMaster ") {
                    let at = out.index(r.upperBound, offsetBy: -1)
                    out = out.replacingSubrange(at ..< at, with: " \(k)=\"\(v)\" ")
                }
            }
            return (out, rels)
        }
        func relsData(_ rels: [Rel], _ part: String) -> Data {
            var b = PackageBuilder()
            b.rels(part, rels)
            return b.parts[Pptx.relsPath(part)] ?? Data()
        }

        // Layouts first, in page order, so a master knows its final list.
        for page in state.slides {
            guard let role = page.masterRole, role.kind == .layout else { continue }
            let own: String
            if role.fresh || keptNames.contains(role.part) {
                own = "ppt/slideLayouts/slideLayout\(nextLayout).xml"
                nextLayout += 1
                ctParts["Override:" + own] = CT.layout
                q.overrides[own] = CT.layout
            } else {
                own = role.part
                keptNames.insert(own)
            }
            guard let text = view.base.parts[role.part].map({ String(decoding: $0, as: UTF8.self) }),
                  let pg = PptxWriter.masterPage(page, name: role.name, source: source) else { continue }
            let baseRels = view.base.rels(role.part).filter { $0.kind != "slideMaster" || true }
            let (out, rels) = spliced(text, page: pg, ownRels: baseRels, part: own)
            q.parts[own] = Data(out.utf8)
            q.parts[Pptx.relsPath(own)] = relsData(rels, own)
            kept[role.master, default: []].append(own)
        }
        // The master pages, then each master's layout list and relationships.
        for (pi, page) in state.slides.enumerated() {
            guard let role = page.masterRole, role.kind == .master else { continue }
            let live = slides[pi]
            let m = role.master
            guard let text = view.base.parts[m].map({ String(decoding: $0, as: UTF8.self) }),
                  let pg = PptxWriter.masterPage(page, name: role.name, source: source) else { continue }
            var (out, rels) = spliced(text, page: pg, ownRels: view.base.rels(m), part: m)
            out = Self._patchTextStyles(out, now: MasterTextLook.looks(of: live, master: m), was: view.textBaseline, master: m)
            let oldList = view.base.xml(m)?.first("p:sldLayoutIdLst")?.all("p:sldLayoutId") ?? []
            let oldRels = view.base.rels(m)
            var entries = ""
            let finals = kept[m] ?? []
            for l in finals {
                var rid = rels.first { Pptx.resolve($0.target, from: m) == l && $0.type == RT.layout }?.id
                var idv: Int? = rid.flatMap { r in oldList.first { $0["r:id"] == r }?["id"].flatMap(Int.init) }
                if rid == nil {
                    var k = 1
                    while rels.contains(where: { $0.id == "rIdMvL\(k)" }) { k += 1 }
                    rid = "rIdMvL\(k)"
                    rels.append(Rel(id: rid!, type: RT.layout, target: Pptx.relative(l, from: m)))
                }
                if idv == nil { idv = nextId; nextId += 1 }
                entries += "<p:sldLayoutId id=\"\(idv!)\" r:id=\"\(rid!)\"/>"
            }
            // Layouts the view dropped: their relationships go, and so do their parts.
            let gone = oldRels.filter { $0.kind == "slideLayout" && !finals.contains($0.target) }.map(\.target)
            for g in gone { dropParts.insert(g); dropParts.insert(Pptx.relsPath(g)) }
            rels.removeAll { r in gone.contains { Pptx.resolve(r.target, from: m) == $0 } }
            if let a = out.rangeOfSubstring("<p:sldLayoutIdLst>"), let e = out.rangeOfSubstring("</p:sldLayoutIdLst>", in: a.lowerBound ..< out.endIndex) {
                out = out.replacingSubrange(a.lowerBound ..< e.upperBound, with: "<p:sldLayoutIdLst>\(entries)</p:sldLayoutIdLst>")
            }
            q.parts[m] = Data(out.utf8)
            q.parts[Pptx.relsPath(m)] = relsData(rels, m)
            // A new layout's own relationships name its master.
            for l in finals {
                var lr = q.rels(l).map { Rel(id: $0.id, type: $0.type, target: $0.external ? $0.target : Pptx.relative($0.target, from: l), external: $0.external) }
                if let i = lr.firstIndex(where: { $0.type == RT.master }) { lr[i].target = Pptx.relative(m, from: l) }
                else { lr.append(Rel(id: "rIdMvMaster", type: RT.master, target: Pptx.relative(m, from: l))) }
                q.parts[Pptx.relsPath(l)] = relsData(lr, l)
            }
        }
        // Slides whose layout went take the first layout of their master.
        for n in q.parts.keys where n.hasPrefix("ppt/slides/slide") && n.hasSuffix(".xml") {
            let rp = Pptx.relsPath(n)
            guard var text = q.parts[rp].map({ String(decoding: $0, as: UTF8.self) }) else { continue }
            var changed = false
            for g in dropParts where !g.hasSuffix(".rels") {
                let rel = Pptx.relative(g, from: n)
                guard text.containsSubstring("Target=\"\(rel)\"") else { continue }
                let fallback = kept.values.first?.first ?? ""
                text = text.replacingAll("Target=\"\(rel)\"", with: "Target=\"\(Pptx.relative(fallback, from: n))\"")
                changed = true
            }
            if changed { q.parts[rp] = Data(text.utf8) }
        }
        for g in dropParts { q.parts[g] = nil; q.overrides[g] = nil }
        // Content types.
        if var ct = q.parts["[Content_Types].xml"].map({ String(decoding: $0, as: UTF8.self) }) {
            for g in dropParts where !g.hasSuffix(".rels") {
                if let a = ct.rangeOfSubstring("<Override PartName=\"/\(g)\""), let e = ct.rangeOfSubstring("/>", in: a.lowerBound ..< ct.endIndex) {
                    ct = ct.replacingSubrange(a.lowerBound ..< e.upperBound, with: "")
                }
            }
            var add = ""
            for (k, v) in ctParts.sorted(by: { $0.key < $1.key }) {
                if k.hasPrefix("Override:") { add += "<Override PartName=\"/\(k.dropFirst(9))\" ContentType=\"\(v)\"/>" }
                else { add += "<Default Extension=\"\(k.dropFirst(8))\" ContentType=\"\(v)\"/>" }
            }
            if let r = ct.rangeOfSubstring("</Types>") { ct = ct.replacingSubrange(r.lowerBound ..< r.lowerBound, with: add) }
            q.parts["[Content_Types].xml"] = Data(ct.utf8)
        }
        return try Zip.write(q.parts.sorted { $0.key < $1.key }.map { ZipEntry(name: $0.key, data: $0.value) })
    }

    // MARK: Layouts

    var masterPage: MasterRole? { slides.indices.contains(current) ? slides[current].masterRole : nil }

    func renameMasterPage(_ name: String) {
        guard inMasterView, var role = masterPage, !name.isEmpty else { return }
        _checkpoint()
        role.name = name
        slides[current].masterRole = role
        _changed()
    }

    /// A new layout after the current page's: a title and the three footer placeholders, as PowerPoint's Insert Layout.
    func insertLayout() {
        guard inMasterView, let role = masterPage else { return }
        _checkpoint()
        let slide = Slide(id: _id(), layout: .blank, shapes: [], notes: _textController(RichDocument(paragraphs: [RichParagraph(text: "")])))
        var r = role
        r.kind = .layout; r.fresh = true; r.name = "Custom Layout"
        if role.kind == .master, let first = slides.first(where: { $0.masterRole?.master == role.master && $0.masterRole?.kind == .layout }) { r.part = first.masterRole!.part }
        slide.masterRole = r
        let w = slideSize.width, h = slideSize.height
        slide.shapes = [
            _masterPlaceholder("title", "Title", Rect.fromLTWH(w * 0.07, h * 0.05, w * 0.86, h * 0.17), size: 40, prompt: "Click to edit Master title style", heading: true),
            _masterPlaceholder("dt", "Date Placeholder", Rect.fromLTWH(w * 0.07, h * 0.9, w * 0.22, h * 0.06), size: 12, prompt: "Date"),
            _masterPlaceholder("ftr", "Footer Placeholder", Rect.fromLTWH(w * 0.3, h * 0.9, w * 0.4, h * 0.06), size: 12, prompt: "Footer"),
            _masterPlaceholder("sldNum", "Slide Number Placeholder", Rect.fromLTWH(w * 0.71, h * 0.9, w * 0.22, h * 0.06), size: 12, prompt: "‹#›"),
        ]
        var at = current + 1
        while slides.indices.contains(at), slides[at].masterRole?.kind == .layout, slides[at].masterRole?.master == role.master, role.kind == .master { at += 1 }
        _watch(slide)
        slide.decorations = role.kind == .layout ? currentSlide.decorations : []
        slides.insert(slide, at: min(at, slides.count))
        current = slides.firstIndex { $0 === slide } ?? current
        selection = []
        slideSelectionIds = []
        _changed()
    }

    func duplicateLayout() {
        guard inMasterView, let role = masterPage, role.kind == .layout else { return }
        duplicateSlide(current)
        var r = role
        r.name = "1_" + role.name
        slides[current].masterRole = r
        _changed()
    }

    /// Whether the current page can be deleted: a layout, and not its master's last.
    var canDeleteLayout: Bool {
        guard inMasterView, let role = masterPage, role.kind == .layout else { return false }
        return slides.filter { $0.masterRole?.master == role.master && $0.masterRole?.kind == .layout }.count > 1
    }

    func deleteLayout() {
        guard canDeleteLayout else { return }
        deleteSlide(current)
    }

    /// A placeholder on the current page: "title", "body", "dt", "ftr", "sldNum", "pic" or "obj".
    func insertMasterPlaceholder(_ type: String) {
        guard inMasterView else { return }
        _checkpoint()
        let w = slideSize.width, h = slideSize.height
        let (name, prompt, frame): (String, String, Rect) = {
            switch type {
            case "title": return ("Title", "Click to edit Master title style", Rect.fromLTWH(w * 0.07, h * 0.05, w * 0.86, h * 0.17))
            case "body": return ("Text Placeholder", "Click to edit Master text styles", Rect.fromLTWH(w * 0.07, h * 0.25, w * 0.86, h * 0.6))
            case "dt": return ("Date Placeholder", "Date", Rect.fromLTWH(w * 0.07, h * 0.9, w * 0.22, h * 0.06))
            case "ftr": return ("Footer Placeholder", "Footer", Rect.fromLTWH(w * 0.3, h * 0.9, w * 0.4, h * 0.06))
            case "sldNum": return ("Slide Number Placeholder", "‹#›", Rect.fromLTWH(w * 0.71, h * 0.9, w * 0.22, h * 0.06))
            case "pic": return ("Picture Placeholder", "Click icon to add picture", Rect.fromLTWH(w * 0.15, h * 0.25, w * 0.4, h * 0.5))
            default: return ("Content Placeholder", "Click to edit Master text styles", Rect.fromLTWH(w * 0.07, h * 0.25, w * 0.86, h * 0.6))
            }
        }()
        let taken = Set(currentSlide.shapes.compactMap { $0.phIdx.flatMap(Int.init) })
        let shape = _masterPlaceholder(type == "obj" ? nil : type, name, frame, size: type == "title" ? 40 : (type == "body" || type == "obj" || type == "pic" ? 24 : 12),
                                       prompt: prompt, heading: type == "title", idx: ["title", "dt", "ftr", "sldNum"].contains(type) ? nil : "\((1 ... 99).first { !taken.contains($0) }!)")
        currentSlide.shapes.append(shape)
        _watch(shape)
        selection = [shape]
        _changed()
    }

    private func _masterPlaceholder(_ type: String?, _ name: String, _ frame: Rect, size: Double, prompt: String,
                                    heading: Bool = false, idx: String? = nil) -> SlideShape {
        let theme = _textTheme(font: heading ? self.theme.headingFont : self.theme.bodyFont, size: size, color: self.theme.text)
        let doc = RichDocument(paragraphs: [RichParagraph(text: prompt, style: RichParagraphStyle(spaceAfter: 0, lineSpacing: 0.9))])
        let shape = SlideShape(id: _id(), name: name, kind: .placeholder(type == "title" ? .title : .body), frame: frame,
                               text: _textController(doc), textTheme: theme, anchor: .top, prompt: prompt)
        shape.phType = type
        shape.phIdx = idx
        return shape
    }
}
