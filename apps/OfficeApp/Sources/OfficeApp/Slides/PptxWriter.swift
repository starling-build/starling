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
import Foundation

enum PptxWriter {
    static func write(_ state: DeckState, theme: DeckTheme, package: PptxPackage?) throws -> Data {
        var b = PackageBuilder()
        if let package, package.parts["ppt/presentation.xml"] != nil || _presentationPart(package) != nil {
            try _writeThrough(package, state: state, theme: theme, into: &b)
        } else {
            _writeNew(state, theme: theme, into: &b)
        }
        return try b.zip()
    }

    private static func _presentationPart(_ p: PptxPackage) -> String? {
        p.xml("_rels/.rels")?.all("Relationship").first { ($0["Type"] ?? "").hasSuffix("/officeDocument") }
            .flatMap { $0["Target"] }.map { $0.hasPrefix("/") ? String($0.dropFirst()) : $0 }
    }

    // MARK: A new deck

    private static func _writeNew(_ state: DeckState, theme: DeckTheme, into b: inout PackageBuilder) {
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
                   source: nil, media: &media, into: &b)
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
        let presRelsAll = p.rels(pres)
        var keep: [String] = []
        for r in p.rels("") where !r.external && r.target != pres { keep.append(r.target) }
        for r in presRelsAll where !r.external && r.kind != "slide" { keep.append(r.target) }
        var copied = Set<String>()
        for part in keep { _copy(part, from: p, into: &b, done: &copied) }
        if let rootRels = p.parts["_rels/.rels"] { b.parts["_rels/.rels"] = rootRels }

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
        let cx = Int((state.slideSize.width * Pptx.emu).rounded()), cy = Int((state.slideSize.height * Pptx.emu).rounded())
        presOut = _replaceElement("p:sldSz", in: presOut, with: "<p:sldSz cx=\"\(cx)\" cy=\"\(cy)\"/>",
                                  after: "</p:sldIdLst>", orAfter: nil)
        b.add(pres, presOut, type: p.contentType(pres) ?? CT.presentation)
    }

    /// Copy a part, its relationships, and everything they reach.
    private static func _copy(_ part: String, from p: PptxPackage, into b: inout PackageBuilder, done: inout Set<String>) {
        guard !done.contains(part), let data = p.parts[part] else { return }
        done.insert(part)
        b.parts[part] = data
        if let type = p.overrides[part] { b.overrides[part] = type }
        let relsPart = Pptx.relsPath(part)
        if let rels = p.parts[relsPart] {
            b.parts[relsPart] = rels
            for r in p.rels(part) where !r.external { _copy(r.target, from: p, into: &b, done: &done) }
        }
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
        for shape in slide.shapes { body += w.shape(shape, media: &media, builder: &b) }
        var bg = ""
        if let xml = slide.backgroundXML, let src = slide.sourcePart, let p = source {
            bg = w.kept(xml, sourcePart: src, package: p, builder: &b, patch: nil)
        } else if let fill = slide.background, slide.backgroundXML == nil, let c = fill.color, fill.image == nil, fill.stops.isEmpty {
            bg = "<p:bg><p:bgPr><a:solidFill><a:srgbClr val=\"\(PptxText.hex(c))\"/></a:solidFill><a:effectLst/></p:bgPr></p:bg>"
        }
        rels += w.rels
        let hidden = slide.hidden ? " show=\"0\"" : ""
        // Kept XML may lean on prefixes the source slide declared at its
        // root (a14, p14, mc…): the same declarations go on ours.
        var ns = PptxTemplates.namespaces
        if let src = slide.sourcePart, let root = source?.xml(src) {
            for (k, v) in root.attrs.sorted(by: { $0.key < $1.key })
            where k.hasPrefix("xmlns:") && !["xmlns:a", "xmlns:r", "xmlns:p"].contains(k) {
                ns += " \(k)=\"\(PptxXML.escape(v, attribute: true))\""
            }
        }
        let transition = _transition(slide.transition, namespaces: &ns)
        // Animations as read, while every shape they name is still here.
        var timing = ""
        if let t = slide.timingXML {
            let named = t.components(separatedBy: "spid=\"").dropFirst().compactMap { Int($0.prefix { $0.isNumber }) }
            if Set(named).isSubset(of: w.usedIds) {
                timing = t
                for (prefix, uri) in [("p14", "http://schemas.microsoft.com/office/powerpoint/2010/main"),
                                      ("mc", "http://schemas.openxmlformats.org/markup-compatibility/2006")]
                where t.contains("\(prefix):") && !ns.contains("xmlns:\(prefix)=") {
                    ns += " xmlns:\(prefix)=\"\(uri)\""
                }
            }
        }
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <p:sld \(ns)\(hidden)><p:cSld>\(bg)<p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>\(body)</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>\(transition)\(timing)</p:sld>
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
            where raw.contains("\(prefix):") && !ns.contains("xmlns:\(prefix)=") {
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

    private static func _insertAfter(_ marker: String, in s: String, _ insert: String) -> String {
        guard let r = s.range(of: marker) else { return s }
        return s.replacingCharacters(in: r, with: marker + insert)
    }

    /// Replace `<name …>…</name>` (or `<name …/>`) in `s`; when absent,
    /// insert the replacement after `after` (or `orAfter`).
    private static func _replaceElement(_ name: String, in s: String, with replacement: String,
                                        after: String, orAfter: String?) -> String {
        if let start = s.range(of: "<\(name)") {
            if let selfClose = s.range(of: "/>", range: start.upperBound ..< s.endIndex),
               s.range(of: ">", range: start.upperBound ..< s.endIndex)?.lowerBound == s.index(before: selfClose.upperBound) {
                return s.replacingCharacters(in: start.lowerBound ..< selfClose.upperBound, with: replacement)
            }
            if let end = s.range(of: "</\(name)>", range: start.upperBound ..< s.endIndex) {
                return s.replacingCharacters(in: start.lowerBound ..< end.upperBound, with: replacement)
            }
        }
        if s.range(of: after) != nil { return _insertAfter(after, in: s, replacement) }
        if let orAfter, s.range(of: orAfter) != nil { return _insertAfter(orAfter, in: s, replacement) }
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
        try PptxWriter.write(deck.snapshot(), theme: deck.theme, package: deck.package)
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

    private mutating func _id(_ preferred: Int? = nil) -> Int {
        if let p = preferred, p > 1, !_used.contains(p) {
            _used.insert(p)
            return p
        }
        while _used.contains(nextId) { nextId += 1 }
        _used.insert(nextId)
        defer { nextId += 1 }
        return nextId
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

    mutating func shape(_ s: ShapeState, media: inout MediaParts, builder: inout PackageBuilder) -> String {
        let name = PptxXML.escape(s.name, attribute: true)
        switch s.kind {
        case .opaque(let o):
            guard let p = source else { return "" }
            return kept(o.xml, sourcePart: o.sourcePart, package: p, builder: &builder, patch: s.frame, fileId: s.fileId)
        case .picture(let image):
            let id = _id(s.fileId)
            let mediaPart: String
            if let existing = media.byId[image.id] {
                mediaPart = existing
            } else {
                media.count += 1
                let ext = PptxText.imageExtension(image)
                mediaPart = "ppt/media/slides_image\(media.count).\(ext)"
                media.byId[image.id] = mediaPart
                builder.addBinary(mediaPart, image.data)
            }
            let rid = _rel(RT.image, Pptx.relative(mediaPart, from: part), preferred: "rIdImg\(media.count)")
            return "<p:pic><p:nvPicPr><p:cNvPr id=\"\(id)\" name=\"\(name)\"/><p:cNvPicPr><a:picLocks noChangeAspect=\"1\"/></p:cNvPicPr><p:nvPr/></p:nvPicPr>"
                + "<p:blipFill><a:blip r:embed=\"\(rid)\"/>\(Self._crop(s.crop))<a:stretch><a:fillRect/></a:stretch></p:blipFill>"
                + "<p:spPr>\(Self._xfrm(s.frame, rotation: s.rotation))<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></p:spPr></p:pic>"
        case .geometry(let preset) where preset.isLine && s.text == nil:
            let id = _id(s.fileId)
            let f = s.frame
            let box = Rect.fromLTRB(min(f.left, f.right), min(f.top, f.bottom), max(f.left, f.right), max(f.top, f.bottom))
            let line = s.outline.map { "<a:ln w=\"\(Self._emu(s.outlineWidth))\">\(Self._fill($0))</a:ln>" } ?? "<a:ln><a:noFill/></a:ln>"
            return "<p:cxnSp><p:nvCxnSpPr><p:cNvPr id=\"\(id)\" name=\"\(name)\"/><p:cNvCxnSpPr/><p:nvPr/></p:nvCxnSpPr>"
                + "<p:spPr>\(Self._xfrm(box, rotation: s.rotation, flipH: f.right < f.left, flipV: f.bottom < f.top))"
                + "<a:prstGeom prst=\"\(preset.rawValue)\"><a:avLst/></a:prstGeom>\(line)</p:spPr></p:cxnSp>"
        default:
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
            switch s.kind {
            case .placeholder:
                if let f = s.fill { spPr += Self._fill(f) }
                if let l = s.outline { spPr += "<a:ln w=\"\(Self._emu(s.outlineWidth))\">\(Self._fill(l))</a:ln>" }
            default:
                spPr += Self._fill(s.fill)
                spPr += s.outline.map { "<a:ln w=\"\(Self._emu(s.outlineWidth))\">\(Self._fill($0))</a:ln>" } ?? "<a:ln><a:noFill/></a:ln>"
            }
            var xml = "<p:sp><p:nvSpPr>\(nv)<p:nvPr>\(ph)</p:nvPr></p:nvSpPr><p:spPr>\(spPr)</p:spPr>"
            if let doc = s.text {
                let anchor = s.anchor.rawValue
                let ins = s.insets
                let fit = s.kind == .textBox ? "<a:spAutoFit/>" : "<a:noAutofit/>"
                xml += "<p:txBody><a:bodyPr wrap=\"square\" lIns=\"\(Self._emu(ins.left))\" tIns=\"\(Self._emu(ins.top))\" "
                    + "rIns=\"\(Self._emu(ins.right))\" bIns=\"\(Self._emu(ins.bottom))\" anchor=\"\(anchor)\" rtlCol=\"0\">\(fit)</a:bodyPr>"
                    + "<a:lstStyle/>" + PptxText.paragraphs(doc, defaults: s) + "</p:txBody>"
            }
            return xml + "</p:sp>"
        }
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
        func remap(_ n: XNode) {
            for (k, v) in n.attrs where k.hasPrefix("r:") {
                guard let r = sourceRels.first(where: { $0.id == v }) else { continue }
                if r.external {
                    n.attrs[k] = _rel(r.type, r.target, external: true, preferred: v)
                } else {
                    var copied = done
                    PptxWriterCopy.copy(r.target, from: p, into: &b, done: &copied)
                    done = copied
                    n.attrs[k] = _rel(r.type, Pptx.relative(r.target, from: part), preferred: v)
                }
            }
            for c in n.children { remap(c) }
        }
        remap(node)
        return PptxXML.serialize(node)
    }
}

enum PptxWriterCopy {
    static func copy(_ part: String, from p: PptxPackage, into b: inout PackageBuilder, done: inout Set<String>) {
        guard !done.contains(part), let data = p.parts[part] else { return }
        done.insert(part)
        b.parts[part] = data
        if let type = p.overrides[part] { b.overrides[part] = type }
        let relsPart = Pptx.relsPath(part)
        if let rels = p.parts[relsPart] {
            b.parts[relsPart] = rels
            for r in p.rels(part) where !r.external { copy(r.target, from: p, into: &b, done: &done) }
        }
    }
}

// MARK: - Text

enum PptxText {
    static func hex(_ c: Color) -> String { String(format: "%06X", c.value & 0xFFFFFF) }

    static func imageExtension(_ image: ImageAttachment) -> String {
        let d = [UInt8](image.data.prefix(8))
        if d.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if d.starts(with: [0xFF, 0xD8]) { return "jpeg" }
        if d.starts(with: [0x47, 0x49, 0x46]) { return "gif" }
        let ext = image.name.pathExtension.lowercased()
        return ext.isEmpty ? "png" : ext
    }

    /// A text body's paragraphs, every run with its look spelled out.
    static func paragraphs(_ doc: RichDocument, defaults s: ShapeState) -> String {
        var out = ""
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
                let indent = s.listIndent * Double(st.listLevel + 1)
                pPr += " marL=\"\(Int(indent * Pptx.emu))\" indent=\"\(-Int(s.listIndent * Pptx.emu))\""
                if st.listLevel > 0 { pPr += " lvl=\"\(st.listLevel)\"" }
            } else {
                pPr += " marL=\"\(Int(st.indentLeft * Pptx.emu))\" indent=\"\(Int(st.firstLineIndent * Pptx.emu))\""
            }
            var inner = "<a:lnSpc><a:spcPct val=\"\(Int((st.lineSpacing * 100000).rounded()))\"/></a:lnSpc>"
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
                    if !piece.isEmpty { out += "<a:r>\(rPr)<a:t>\(PptxXML.escape(piece, attribute: false))</a:t></a:r>" }
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
