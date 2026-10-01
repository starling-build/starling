// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// .pptx — PresentationML in a zip (docs/plans/slides.md, S4). The reader
// resolves what PowerPoint resolves: a placeholder's position, text look
// and body settings come from the slide, then its layout, then the master,
// then the master's text styles and the presentation's defaults; colours
// go through the master's colour map into the theme. What the deck does
// not model (charts, SmartArt, tables, video, freeforms) is kept as XML
// and drawn as a labelled box, and the package itself is kept so a save
// can write masters, layouts and themes back byte for byte.

import Flutter
import FlutterSwiftBridge
import Foundation

// MARK: - Package

struct PptxRel: Equatable {
    let id: String
    let type: String
    /// Absolute part name ("ppt/slideLayouts/slideLayout2.xml"), or the URL
    /// for an external target.
    let target: String
    let external: Bool

    /// The last path component of the relationship type ("slideLayout").
    var kind: String { type.split(separator: "/").last.map(String.init) ?? type }
}

/// The file as read: every part, plus the parsed content types.
struct PptxPackage: Equatable {
    var parts: [String: Data]
    var overrides: [String: String] = [:]
    var defaults: [String: String] = [:]

    static func == (a: PptxPackage, b: PptxPackage) -> Bool { a.parts == b.parts }

    init(_ entries: [ZipEntry]) {
        var parts: [String: Data] = [:]
        for e in entries { parts[e.name] = e.data }
        self.parts = parts
        if let ct = parts["[Content_Types].xml"].flatMap(XNode.parse) {
            for o in ct.all("Override") {
                if let name = o["PartName"], let type = o["ContentType"] {
                    overrides[String(name.drop { $0 == "/" })] = type
                }
            }
            for d in ct.all("Default") {
                if let ext = d["Extension"], let type = d["ContentType"] { defaults[ext.lowercased()] = type }
            }
        }
    }

    func xml(_ part: String) -> XNode? { parts[part].flatMap(XNode.parse) }

    func contentType(_ part: String) -> String? {
        overrides[part] ?? defaults[(part.split(separator: ".").last.map(String.init) ?? "").lowercased()]
    }

    func rels(_ part: String) -> [PptxRel] {
        guard let root = xml(Pptx.relsPath(part)) else { return [] }
        return root.all("Relationship").compactMap { r in
            guard let id = r["Id"], let type = r["Type"], let target = r["Target"] else { return nil }
            let external = r["TargetMode"] == "External"
            return PptxRel(id: id, type: type, target: external ? target : Pptx.resolve(target, from: part),
                           external: external)
        }
    }

    func rel(_ part: String, kind: String) -> PptxRel? { rels(part).first { $0.kind == kind } }
}

enum Pptx {
    static let emu = 12700.0

    static func relsPath(_ part: String) -> String {
        if part.isEmpty { return "_rels/.rels" }
        let dir = part.deletingLastPathComponent
        let name = part.lastPathComponent
        return (dir.isEmpty ? "" : dir + "/") + "_rels/" + name + ".rels"
    }

    /// A relationship target, relative to the part that names it, as an
    /// absolute part name.
    static func resolve(_ target: String, from part: String) -> String {
        if target.hasPrefix("/") { return String(target.dropFirst()) }
        var stack = part.split(separator: "/").map(String.init)
        if !stack.isEmpty { stack.removeLast() }   // "" is the package root
        for piece in target.split(separator: "/") {
            if piece == ".." { if !stack.isEmpty { stack.removeLast() } } else if piece != "." { stack.append(String(piece)) }
        }
        return stack.joined(separator: "/")
    }

    enum ReadError: Error { case noPresentation, notAPresentation }

    static func read(_ data: Data) throws -> (DeckState, DeckTheme, PptxPackage) {
        let package = PptxPackage(try Zip.read(data))
        return try PptxReader(package).read()
    }
}

// MARK: - Theme and colours

struct PptxTheme {
    var colors: [String: Color] = [:]
    var major = "Calibri Light"
    var minor = "Calibri"

    init(_ root: XNode?) {
        guard let root, let elements = root.descendant("a:themeElements") else { return }
        if let scheme = elements.first("a:clrScheme") {
            for child in scheme.children {
                let name = String(child.name.drop { $0 != ":" }.dropFirst())
                if let c = child.first("a:srgbClr")?["val"].flatMap(Self.hex) {
                    colors[name] = c
                } else if let c = child.first("a:sysClr")?["lastClr"].flatMap(Self.hex) {
                    colors[name] = c
                }
            }
        }
        if let fonts = elements.first("a:fontScheme") {
            if let f = fonts.first("a:majorFont")?.first("a:latin")?["typeface"], !f.isEmpty { major = f }
            if let f = fonts.first("a:minorFont")?.first("a:latin")?["typeface"], !f.isEmpty { minor = f }
        }
    }

    static func hex(_ s: String) -> Color? {
        guard s.count == 6, let v = Int(s, radix: 16) else { return nil }
        return Color(0xFF00_0000 | Int64(v))
    }
}

/// Colours as one slide sees them: the theme through the master's map.
struct ColorContext {
    var theme: PptxTheme
    var map: [String: String] = ["bg1": "lt1", "tx1": "dk1", "bg2": "lt2", "tx2": "dk2"]
    /// What `phClr` stands for inside a theme style (the referring colour).
    var placeholder: Color? = nil

    func scheme(_ name: String) -> Color? {
        if name == "phClr" { return placeholder }
        let key = map[name] ?? name
        return theme.colors[key]
    }

    /// The colour an element like `a:solidFill` holds, with its modifiers.
    func color(in fill: XNode) -> Color? {
        for child in fill.children {
            var base: Color?
            switch child.name {
            case "a:srgbClr": base = child["val"].flatMap(PptxTheme.hex)
            case "a:schemeClr": base = child["val"].flatMap(scheme)
            case "a:sysClr": base = (child["lastClr"] ?? child["val"]).flatMap(PptxTheme.hex)
            case "a:prstClr": base = Self.preset[child["val"] ?? ""]
            default: continue
            }
            guard let b = base else { continue }
            return Self.modify(b, child)
        }
        return nil
    }

    static let preset: [String: Color] = [
        "black": Color(0xFF000000), "white": Color(0xFFFFFFFF), "red": Color(0xFFFF0000),
        "green": Color(0xFF008000), "blue": Color(0xFF0000FF), "yellow": Color(0xFFFFFF00),
        "gray": Color(0xFF808080), "grey": Color(0xFF808080), "orange": Color(0xFFFFA500),
    ]

    /// lumMod/lumOff (in HSL), tint, shade and alpha, as DrawingML applies them.
    static func modify(_ c: Color, _ node: XNode) -> Color {
        var r = Double((c.value >> 16) & 0xFF) / 255, g = Double((c.value >> 8) & 0xFF) / 255, b = Double(c.value & 0xFF) / 255
        var alpha = 1.0
        for m in node.children {
            let v = (m["val"].flatMap(Double.init) ?? 100000) / 100000
            switch m.name {
            case "a:lumMod", "a:lumOff":
                var (h, s, l) = _hsl(r, g, b)
                l = m.name == "a:lumMod" ? l * v : l + v
                (r, g, b) = _rgb(h, s, min(1, max(0, l)))
                h = 0; s = 0
            case "a:tint": r = 1 - (1 - r) * v; g = 1 - (1 - g) * v; b = 1 - (1 - b) * v
            case "a:shade": r *= v; g *= v; b *= v
            case "a:alpha": alpha = v
            default: break
            }
        }
        let ri = Int((r * 255).rounded()), gi = Int((g * 255).rounded()), bi = Int((b * 255).rounded())
        let ai = Int((alpha * 255).rounded())
        return Color((ai << 24) | (ri << 16) | (gi << 8) | bi)
    }

    private static func _hsl(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        let mx = max(r, g, b), mn = min(r, g, b)
        let l = (mx + mn) / 2
        guard mx != mn else { return (0, 0, l) }
        let d = mx - mn
        let s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
        var h: Double
        if mx == r { h = (g - b) / d + (g < b ? 6 : 0) } else if mx == g { h = (b - r) / d + 2 } else { h = (r - g) / d + 4 }
        h /= 6
        return (h, s, l)
    }

    private static func _rgb(_ h: Double, _ s: Double, _ l: Double) -> (Double, Double, Double) {
        guard s != 0 else { return (l, l, l) }
        func hue(_ p: Double, _ q: Double, _ t0: Double) -> Double {
            var t = t0
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1.0 / 6 { return p + (q - p) * 6 * t }
            if t < 0.5 { return q }
            if t < 2.0 / 3 { return p + (q - p) * (2.0 / 3 - t) * 6 }
            return p
        }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        return (hue(p, q, h + 1.0 / 3), hue(p, q, h), hue(p, q, h - 1.0 / 3))
    }
}

// MARK: - Text styles

private enum Bullet: Equatable { case none, char, number }

/// One level's paragraph and run look, as far as some layer of the
/// inheritance chain says; `filled(from:)` completes it from a lower layer.
private struct LevelStyle {
    var algn: String?
    var marL: Double?
    var indent: Double?
    var lineMultiple: Double?
    var linePoints: Double?
    var beforePoints: Double?
    var beforePercent: Double?
    var afterPoints: Double?
    var bullet: Bullet?
    var size: Double?
    var bold: Bool?
    var italic: Bool?
    var underline: Bool?
    var strike: Bool?
    var font: String?
    var color: Color?
    var baseline: Double?

    func filled(from lower: LevelStyle) -> LevelStyle {
        var s = self
        s.algn = s.algn ?? lower.algn
        s.marL = s.marL ?? lower.marL
        s.indent = s.indent ?? lower.indent
        if s.lineMultiple == nil && s.linePoints == nil { s.lineMultiple = lower.lineMultiple; s.linePoints = lower.linePoints }
        if s.beforePoints == nil && s.beforePercent == nil { s.beforePoints = lower.beforePoints; s.beforePercent = lower.beforePercent }
        s.afterPoints = s.afterPoints ?? lower.afterPoints
        s.bullet = s.bullet ?? lower.bullet
        s.size = s.size ?? lower.size
        s.bold = s.bold ?? lower.bold
        s.italic = s.italic ?? lower.italic
        s.underline = s.underline ?? lower.underline
        s.strike = s.strike ?? lower.strike
        s.font = s.font ?? lower.font
        s.color = s.color ?? lower.color
        s.baseline = s.baseline ?? lower.baseline
        return s
    }

    /// A `a:lvlNpPr` / `a:pPr` element, with its `a:defRPr`.
    static func paragraph(_ p: XNode?, _ colors: ColorContext) -> LevelStyle {
        var s = LevelStyle()
        guard let p else { return s }
        s.algn = p["algn"]
        s.marL = p["marL"].flatMap(Double.init).map { $0 / Pptx.emu }
        s.indent = p["indent"].flatMap(Double.init).map { $0 / Pptx.emu }
        if let ln = p.first("a:lnSpc") {
            if let v = ln.first("a:spcPct")?["val"].flatMap(Double.init) { s.lineMultiple = v / 100000 }
            if let v = ln.first("a:spcPts")?["val"].flatMap(Double.init) { s.linePoints = v / 100 }
        }
        if let b = p.first("a:spcBef") {
            if let v = b.first("a:spcPts")?["val"].flatMap(Double.init) { s.beforePoints = v / 100 }
            if let v = b.first("a:spcPct")?["val"].flatMap(Double.init) { s.beforePercent = v / 100000 }
        }
        if let v = p.first("a:spcAft")?.first("a:spcPts")?["val"].flatMap(Double.init) { s.afterPoints = v / 100 }
        if p.has("a:buNone") { s.bullet = Bullet.none }
        if p.has("a:buChar") { s.bullet = .char }
        if p.has("a:buAutoNum") { s.bullet = .number }
        if let r = p.first("a:defRPr") { s = run(r, colors).filled(from: s) }
        return s
    }

    /// A `a:rPr` / `a:defRPr` / `a:endParaRPr` element.
    static func run(_ r: XNode, _ colors: ColorContext) -> LevelStyle {
        var s = LevelStyle()
        s.size = r["sz"].flatMap(Double.init).map { $0 / 100 }
        s.bold = r["b"].map { $0 == "1" || $0 == "true" }
        s.italic = r["i"].map { $0 == "1" || $0 == "true" }
        s.underline = r["u"].map { $0 != "none" }
        s.strike = r["strike"].map { $0 != "noStrike" }
        s.baseline = r["baseline"].flatMap(Double.init)
        s.font = r.first("a:latin")?["typeface"]
        if let fill = r.first("a:solidFill") { s.color = colors.color(in: fill) }
        return s
    }
}

// MARK: - Reader

private struct PptxReader {
    let package: PptxPackage
    let images = PptxImages()

    init(_ package: PptxPackage) { self.package = package }

    func read() throws -> (DeckState, DeckTheme, PptxPackage) {
        guard let root = package.xml("_rels/.rels"),
              let presPart = root.all("Relationship").first(where: { ($0["Type"] ?? "").hasSuffix("/officeDocument") })?["Target"]
        else { throw Pptx.ReadError.noPresentation }
        let pres = presPart.hasPrefix("/") ? String(presPart.dropFirst()) : presPart
        guard let presentation = package.xml(pres), presentation.name == "p:presentation" else {
            throw Pptx.ReadError.notAPresentation
        }
        var size = Size(960, 540)
        if let sz = presentation.first("p:sldSz"), let cx = sz["cx"].flatMap(Double.init), let cy = sz["cy"].flatMap(Double.init) {
            size = Size(cx / Pptx.emu, cy / Pptx.emu)
        }
        let rels = package.rels(pres)
        var slideParts: [String] = []
        for id in presentation.first("p:sldIdLst")?.all("p:sldId") ?? [] {
            if let rid = id["r:id"], let r = rels.first(where: { $0.id == rid }) { slideParts.append(r.target) }
        }
        let defaults = presentation.first("p:defaultTextStyle")

        var deckTheme = DeckTheme()
        var slides: [SlideState] = []
        var nextId = 1
        func id() -> Int { defer { nextId += 1 }; return nextId }
        for (n, part) in slideParts.enumerated() {
            guard let slide = package.xml(part) else { continue }
            let layoutPart = package.rel(part, kind: "slideLayout")?.target
            let layout = layoutPart.flatMap(package.xml)
            let masterPart = layoutPart.flatMap { package.rel($0, kind: "slideMaster")?.target }
            let master = masterPart.flatMap(package.xml)
            let themePart = masterPart.flatMap { package.rel($0, kind: "theme")?.target }
            let theme = PptxTheme(themePart.flatMap(package.xml))
            var colors = ColorContext(theme: theme)
            if let map = master?.first("p:clrMap") { for (k, v) in map.attrs { colors.map[k] = v } }
            if n == 0 { deckTheme = Self._deckTheme(theme, colors) }
            let ctx = SlideContext(package: package, part: part, slide: slide, layout: layout, master: master,
                                   colors: colors, theme: theme, defaults: defaults, slideSize: size, images: images)
            var shapes: [ShapeState] = []
            if let tree = slide.first("p:cSld")?.first("p:spTree") {
                ctx.shapes(in: tree, transform: nil, into: &shapes, id: id)
            }
            let bg = slide.first("p:cSld")?.first("p:bg")
            let themeRoot = themePart.flatMap(package.xml)
            // The slide's own background is its; one from its layout or
            // master is only drawn (writing it per slide would copy the
            // master's picture into every slide).
            var bgFill: SlideFill? = nil
            var inherited: SlideFill? = nil
            if let b = slide.first("p:cSld")?.first("p:bg") {
                bgFill = _background(b, owner: part, colors: colors, theme: themeRoot)
            } else {
                for (owner, xml) in [(layoutPart, layout), (masterPart, master)] {
                    guard let owner, let b = xml?.first("p:cSld")?.first("p:bg") else { continue }
                    inherited = _background(b, owner: owner, colors: colors, theme: themeRoot)
                    break
                }
            }
            let layoutType = layout?["type"]
            // Where the layout (or master) keeps its date, footer and number.
            var footerFrames: [String: Rect] = [:]
            for type in ["dt", "ftr", "sldNum"] {
                for tree in [layout, master] {
                    let sps = tree?.first("p:cSld")?.first("p:spTree")?.all("p:sp") ?? []
                    if let sp = sps.first(where: { (($0.first("p:nvSpPr")?.first("p:nvPr")?.first("p:ph"))?["type"]) == type }),
                       let x = sp.first("p:spPr")?.first("a:xfrm"),
                       let off = x.first("a:off"), let ext = x.first("a:ext"),
                       let ox = off["x"].flatMap(Double.init), let oy = off["y"].flatMap(Double.init),
                       let cx = ext["cx"].flatMap(Double.init), let cy = ext["cy"].flatMap(Double.init) {
                        footerFrames[type] = Rect.fromLTWH(ox / Pptx.emu, oy / Pptx.emu, cx / Pptx.emu, cy / Pptx.emu)
                        break
                    }
                }
            }
            // Entrance animations this app models, aimed at shapes by the
            // file ids they kept.
            var animations: [ShapeAnimation] = []
            var sourceAnimations: [ShapeAnimation]? = nil
            if let timing = slide.first("p:timing"), let read = AnimationXML.read(timing) {
                let byFileId = Dictionary(shapes.compactMap { s in s.fileId.map { ($0, s.id) } }, uniquingKeysWith: { a, _ in a })
                let mapped = read.compactMap { r -> ShapeAnimation? in
                    byFileId[r.spid].map { var a = r.animation; a.shapeId = $0; return a }
                }
                if mapped.count == read.count {
                    animations = mapped
                    sourceAnimations = mapped
                }
            }
            slides.append(SlideState(
                id: id(), layout: Self._layoutKind(layoutType), hidden: slide["show"] == "0",
                notes: ctx.notes(), shapes: shapes, layoutPart: layoutPart,
                backgroundXML: bg.map(PptxXML.serialize), background: bgFill, inheritedBackground: inherited,
                sourcePart: part,
                transition: Self._transition(slide),
                timingXML: slide.first("p:timing").map(PptxXML.serialize),
                footerFrames: footerFrames, animations: animations, sourceAnimations: sourceAnimations))
        }
        if slides.isEmpty {
            // An empty deck is still a deck: one blank slide to type on.
            slides.append(SlideState(id: id(), layout: .blank, hidden: false,
                                     notes: RichDocument(), shapes: []))
        }
        return (DeckState(slides: slides, current: 0, slideSize: size), deckTheme, package)
    }

    /// A `p:bg`: its own properties, or a reference into the theme's
    /// background fill styles with the referring colour as `phClr`.
    private func _background(_ bg: XNode, owner: String, colors: ColorContext, theme: XNode?) -> SlideFill? {
        if let pr = bg.first("p:bgPr") { return fill(pr, owner: owner, colors: colors) }
        guard let ref = bg.first("p:bgRef"), let idx = ref["idx"].flatMap(Int.init) else { return nil }
        var c = colors
        c.placeholder = colors.color(in: ref)
        let styles = theme?.descendant("a:fmtScheme")
        let list = idx >= 1001 ? styles?.first("a:bgFillStyleLst") : styles?.first("a:fillStyleLst")
        let n = idx >= 1001 ? idx - 1001 : idx - 1
        guard let entries = list?.children, entries.indices.contains(n) else {
            return c.placeholder.map { SlideFill(color: $0) }
        }
        // The style is one fill element; wrap it so `fill` can read it.
        let holder = XNode(name: "holder", attrs: [:])
        holder.children = [entries[n]]
        return fill(holder, owner: owner, colors: c)
    }

    /// The fill inside a properties element (`p:bgPr`, `p:spPr`).
    func fill(_ pr: XNode, owner: String, colors: ColorContext) -> SlideFill? {
        if let f = pr.first("a:solidFill") { return colors.color(in: f).map { SlideFill(color: $0) } }
        if let g = pr.first("a:gradFill") {
            let stops: [SlideFill.GradientStop] = (g.first("a:gsLst")?.all("a:gs") ?? []).compactMap { gs in
                guard let c = colors.color(in: gs) else { return nil }
                return SlideFill.GradientStop(position: (gs["pos"].flatMap(Double.init) ?? 0) / 100000, color: c)
            }.sorted { $0.position < $1.position }
            let angle = (g.first("a:lin")?["ang"].flatMap(Double.init) ?? 5_400_000) / 60000
            if stops.count == 1 { return SlideFill(color: stops[0].color) }
            return stops.isEmpty ? nil : SlideFill(color: stops[0].color, stops: stops, angle: angle)
        }
        if let b = pr.first("a:blipFill"), let rid = b.first("a:blip")?["r:embed"],
           let rel = package.rels(owner).first(where: { $0.id == rid }), !rel.external,
           package.parts[rel.target] != nil {
            return SlideFill(image: images.attachment(rel.target, package))
        }
        return nil
    }

    /// `p:transition`, plain or inside `mc:AlternateContent` (PowerPoint
    /// 2010+ writes the timing in p14 there, with a plain fallback).
    private static func _transition(_ slide: XNode) -> SlideTransition {
        var t = SlideTransition()
        let ac = slide.first("mc:AlternateContent")
        guard let node = slide.first("p:transition") ?? ac?.first("mc:Choice")?.first("p:transition")
            ?? ac?.first("mc:Fallback")?.first("p:transition") else { return t }
        switch node["spd"] { case "fast": t.duration = 0.5; case "slow": t.duration = 1.0; default: t.duration = 0.75 }
        if let ms = node["p14:dur"].flatMap(Double.init) { t.duration = ms / 1000 }
        let effect = node.children.first { !$0.name.hasPrefix("p:snd") && $0.name != "p:sndAc" && $0.name != "p:extLst" }
        switch effect?.name {
        case nil: t.kind = .none
        case "p:fade": t.kind = .fade
        case "p:push": t.kind = .push
        case "p:wipe": t.kind = .wipe
        case "p:cover": t.kind = .cover
        default:
            t.kind = .fade
            t.raw = PptxXML.serialize(ac ?? node)
        }
        if let d = effect?["dir"].flatMap(SlideTransition.Direction.init(rawValue:)) { t.direction = d }
        return t
    }

    private static func _layoutKind(_ type: String?) -> SlideLayoutKind {
        switch type {
        case "title": return .titleSlide
        case "secHead": return .sectionHeader
        case "twoObj": return .twoContent
        case "twoTxTwoObj": return .comparison
        case "titleOnly": return .titleOnly
        case "blank": return .blank
        default: return .titleAndContent
        }
    }

    private static func _deckTheme(_ t: PptxTheme, _ c: ColorContext) -> DeckTheme {
        var d = DeckTheme()
        d.name = "From file"
        d.headingFont = t.major
        d.bodyFont = t.minor
        d.background = c.scheme("bg1") ?? d.background
        d.text = c.scheme("tx1") ?? d.text
        let accents = (1 ... 6).compactMap { t.colors["accent\($0)"] }
        if accents.count == 6 { d.accents = accents }
        return d
    }
}

/// Everything one slide's shapes resolve against.
private struct SlideContext {
    let package: PptxPackage
    let part: String
    let slide: XNode
    let layout: XNode?
    let master: XNode?
    let colors: ColorContext
    let theme: PptxTheme
    let defaults: XNode?
    let slideSize: Size
    let images: PptxImages

    // MARK: Placeholders

    private func _ph(_ sp: XNode) -> XNode? {
        (sp.first("p:nvSpPr") ?? sp.first("p:nvPicPr") ?? sp.first("p:nvGraphicFramePr"))?.first("p:nvPr")?.first("p:ph")
    }

    /// The layout's and then the master's placeholder this one inherits from.
    private func _inherited(_ ph: XNode) -> (layout: XNode?, master: XNode?) {
        let type = ph["type"] ?? "obj"
        let idx = ph["idx"]
        func find(_ tree: XNode?, masterRules: Bool) -> XNode? {
            guard let shapes = tree?.first("p:cSld")?.first("p:spTree")?.children else { return nil }
            let sps = shapes.filter { $0.name == "p:sp" }
            if !masterRules, let idx {
                if let hit = sps.first(where: { _ph($0)?["idx"] == idx }) { return hit }
            }
            let want: String = {
                guard masterRules else { return type }
                switch type {
                case "ctrTitle", "title": return "title"
                case "subTitle", "obj", "body": return "body"
                default: return type
                }
            }()
            return sps.first { sp in
                guard let p = _ph(sp) else { return false }
                let t = p["type"] ?? "obj"
                if want == "body" && masterRules { return t == "body" }
                return t == want || (want == "obj" && t == "body")
            }
        }
        return (find(layout, masterRules: false), find(master, masterRules: true))
    }

    // MARK: Shapes

    func shapes(in tree: XNode, transform: ((Rect) -> Rect)?, into out: inout [ShapeState], id: () -> Int,
                group: ShapeGroup? = nil) {
        // Each shape keeps its file id (animations name shapes by it). A
        // group is flattened for editing, its members remembering it (the
        // outermost one) so a save groups them again under its id.
        func add(_ s: ShapeState?, _ el: XNode) {
            guard var s else { return }
            s.fileId = el.descendant("p:cNvPr")?["id"].flatMap(Int.init)
            s.group = group
            out.append(s)
        }
        func groupOf(_ el: XNode) -> ShapeGroup? {
            if let group { return group }
            let nv = el.first("p:nvGrpSpPr")?.first("p:cNvPr")
            return ShapeGroup(fileId: nv?["id"].flatMap(Int.init), name: nv?["name"] ?? "Group", key: id())
        }
        for el in tree.children {
            switch el.name {
            case "p:sp": add(_shape(el, transform, id: id), el)
            case "p:cxnSp": add(_connector(el, transform, id: id), el)
            case "p:pic": add(_picture(el, transform, id: id), el)
            case "p:graphicFrame":
                if _frameLabel(el) == "Table", let t = _table(el, transform, id: id) { add(t, el) }
                else if _frameLabel(el) == "Chart", let c = _chart(el, transform, id: id) { add(c, el) } else {
                    add(_opaque(el, label: _frameLabel(el), transform, id: id), el)
                }
            case "p:grpSp":
                // A turned or mirrored group is kept whole: flattening places
                // its members but cannot turn them with it.
                if let gx = el.first("p:grpSpPr")?.first("a:xfrm"),
                   (gx["rot"].flatMap(Double.init) ?? 0) != 0 || gx["flipH"] == "1" || gx["flipV"] == "1" {
                    add(_opaque(el, label: "Group", transform, id: id), el)
                    continue
                }
                // Groups are flattened: each member drawn where the group's
                // child space maps it on the slide.
                guard let x = el.first("p:grpSpPr")?.first("a:xfrm"), let frame = _xfrmRect(x),
                      let chOff = x.first("a:chOff"), let chExt = x.first("a:chExt"),
                      let cox = chOff["x"].flatMap(Double.init), let coy = chOff["y"].flatMap(Double.init),
                      let ccx = chExt["cx"].flatMap(Double.init), let ccy = chExt["cy"].flatMap(Double.init),
                      ccx > 0, ccy > 0 else {
                    shapes(in: el, transform: transform, into: &out, id: id, group: groupOf(el))
                    continue
                }
                let sx = frame.width / (ccx / Pptx.emu), sy = frame.height / (ccy / Pptx.emu)
                let map: (Rect) -> Rect = { r in
                    let mapped = Rect.fromLTWH(frame.left + (r.left - cox / Pptx.emu) * sx,
                                               frame.top + (r.top - coy / Pptx.emu) * sy,
                                               r.width * sx, r.height * sy)
                    return transform?(mapped) ?? mapped
                }
                shapes(in: el, transform: map, into: &out, id: id, group: groupOf(el))
            case "mc:AlternateContent":
                // The fallback is what an older reader would draw: keep the
                // whole thing, show it as an object.
                add(_opaque(el, label: "Object", transform, id: id), el)
            default: continue
            }
        }
    }

    private func _xfrmRect(_ x: XNode) -> Rect? {
        guard let off = x.first("a:off"), let ext = x.first("a:ext"),
              let ox = off["x"].flatMap(Double.init), let oy = off["y"].flatMap(Double.init),
              let cx = ext["cx"].flatMap(Double.init), let cy = ext["cy"].flatMap(Double.init) else { return nil }
        return Rect.fromLTWH(ox / Pptx.emu, oy / Pptx.emu, cx / Pptx.emu, cy / Pptx.emu)
    }

    private func _shape(_ sp: XNode, _ transform: ((Rect) -> Rect)?, id: () -> Int) -> ShapeState? {
        let ph = _ph(sp)
        let inherited: (layout: XNode?, master: XNode?) = ph.map { _inherited($0) } ?? (nil, nil)
        let spPr = sp.first("p:spPr")
        let xfrm = spPr?.first("a:xfrm")
        let own: Rect? = xfrm.flatMap { _xfrmRect($0) }
        let fromLayout: Rect? = inherited.layout?.first("p:spPr")?.first("a:xfrm").flatMap { _xfrmRect($0) }
        let fromMaster: Rect? = inherited.master?.first("p:spPr")?.first("a:xfrm").flatMap { _xfrmRect($0) }
        guard var frame = own ?? fromLayout ?? fromMaster else { return nil }
        if let t = transform { frame = t(frame) }
        let name = sp.first("p:nvSpPr")?.first("p:cNvPr")?["name"] ?? "Shape"
        let isTextBox = sp.first("p:nvSpPr")?.first("p:cNvSpPr")?["txBox"] == "1"
        let prst = spPr?.first("a:prstGeom")?["prst"]
        let kind: ShapeKind
        if let ph {
            let role: PlaceholderRole
            switch ph["type"] {
            case "title": role = .title
            case "ctrTitle": role = .ctrTitle
            case "subTitle": role = .subTitle
            default: role = .body
            }
            kind = .placeholder(role)
        } else if isTextBox {
            kind = .textBox
        } else if let prst {
            kind = .geometry(ShapePreset(rawValue: prst))
        } else {
            // A freeform (custGeom): kept whole.
            return _opaque(sp, label: "Freeform", transform, id: id)
        }

        // Fill and line: the shape's own, else its style's references.
        var fill: Color? = nil
        var fillScheme: String? = nil
        var outline: Color? = nil
        var outlineWidth = 0.75
        let style = sp.first("p:style")
        if spPr?.has("a:noFill") == true {
            fill = nil
        } else if let f = spPr?.first("a:solidFill") {
            fill = colors.color(in: f)
            fillScheme = Self._accentSlot(f)
        } else if let g = spPr?.first("a:gradFill") {
            // A gradient shape is drawn in its middle colour for now.
            let stops = g.first("a:gsLst")?.all("a:gs").compactMap { colors.color(in: $0) } ?? []
            fill = stops.isEmpty ? nil : stops[stops.count / 2]
        } else if let ref = style?.first("a:fillRef"), ref["idx"] != "0" {
            // The shape style's fill (idx 0 is none), for any kind of shape.
            fill = colors.color(in: ref)
            fillScheme = Self._accentSlot(ref)
        }
        if let ln = spPr?.first("a:ln") {
            outlineWidth = ln["w"].flatMap(Double.init).map { $0 / Pptx.emu } ?? outlineWidth
            if ln.has("a:noFill") { outline = nil } else if let f = ln.first("a:solidFill") { outline = colors.color(in: f) }
            else if let ref = style?.first("a:lnRef"), ref["idx"] != "0" { outline = colors.color(in: ref) }
        } else if let ref = style?.first("a:lnRef"), ref["idx"] != "0" {
            outline = colors.color(in: ref)
        }

        let text = _text(sp, ph: ph, inherited: inherited, kind: kind)
        let rotation = (xfrm?["rot"].flatMap(Double.init) ?? 0) / 60000
        var st = ShapeState(id: id(), name: name, kind: kind, frame: frame, rotation: rotation,
                            fill: fill, outline: outline, outlineWidth: outlineWidth,
                            anchor: text.anchor, insets: text.insets, prompt: nil,
                            text: text.document, font: text.font, size: text.size, color: text.color,
                            listIndent: text.listIndent, phType: ph?["type"], phIdx: ph?["idx"],
                            fillScheme: fillScheme)
        st.autofit = text.autofit
        st.fontScale = text.fontScale
        // The look as the file spells it — fills this app flattens (gradients,
        // patterns, pictures), effects it does not draw, the style it refers
        // to — written back while the fill and outline are unchanged.
        let fillNames: Set<String> = ["a:noFill", "a:solidFill", "a:gradFill", "a:blipFill", "a:pattFill", "a:grpFill"]
        let effectNames: Set<String> = ["a:effectLst", "a:effectDag", "a:scene3d", "a:sp3d"]
        let kids = spPr?.children ?? []
        if style != nil || kids.contains(where: { fillNames.contains($0.name) || effectNames.contains($0.name) || $0.name == "a:ln" }) {
            st.keptLook = KeptLook(
                fill: kids.first { fillNames.contains($0.name) }.map(PptxXML.serialize),
                line: kids.first { $0.name == "a:ln" }.map(PptxXML.serialize),
                effects: kids.filter { effectNames.contains($0.name) }.map(PptxXML.serialize).joined(),
                style: style.map(PptxXML.serialize),
                readFill: fill, readFillScheme: fillScheme, readOutline: outline, readWidth: outlineWidth)
            st.sourcePart = part
        }
        // A body that is one field and nothing else (a slide number, a
        // date) stays that field.
        let paras = sp.first("p:txBody")?.all("a:p").filter { !$0.all("a:r").isEmpty || !$0.all("a:fld").isEmpty } ?? []
        if paras.count == 1, paras[0].all("a:r").isEmpty, paras[0].all("a:fld").count == 1,
           let fld = paras[0].first("a:fld"), let type = fld["type"], let fid = fld["id"] {
            st.field = SlideField(type: type, id: fid)
        }
        if ph != nil, text.document.paragraphs.allSatisfy({ $0.text.isEmpty }) {
            switch kind {
            case .placeholder(.title), .placeholder(.ctrTitle): st.prompt = "Click to add title"
            case .placeholder(.subTitle): st.prompt = "Click to add subtitle"
            default: st.prompt = "Click to add text"
            }
        }
        // The shape as read: written back verbatim while nothing about it
        // has changed (see ReadShape).
        st.sourceXML = PptxXML.serialize(sp)
        st.sourceText = st.text
        st.sourcePart = part
        st.readShape = ReadShape(st)
        return st
    }

    /// "accent3" when a fill is a plain theme accent (no modifiers), so a
    /// new theme can recolour it.
    private static func _accentSlot(_ fill: XNode) -> String? {
        guard let c = fill.first("a:schemeClr"), c.children.isEmpty, let v = c["val"], v.hasPrefix("accent") else { return nil }
        return v
    }

    private func _connector(_ el: XNode, _ transform: ((Rect) -> Rect)?, id: () -> Int) -> ShapeState? {
        guard let x = el.first("p:spPr")?.first("a:xfrm"), var box = _xfrmRect(x) else { return nil }
        if let t = transform { box = t(box) }
        // Flips turn the box's diagonal into the line's direction, and the
        // rotation turns both ends about the box's centre.
        var x1 = box.left, x2 = box.right, y1 = box.top, y2 = box.bottom
        if x["flipH"] == "1" { swap(&x1, &x2) }
        if x["flipV"] == "1" { swap(&y1, &y2) }
        var a = Offset(x1, y1), b = Offset(x2, y2)
        if let rot = x["rot"].flatMap(Double.init), rot != 0 {
            let r = rot / 60000 * .pi / 180, c = box.center
            func turn(_ p: Offset) -> Offset {
                let dx = p.dx - c.dx, dy = p.dy - c.dy
                return Offset(c.dx + dx * cos(r) - dy * sin(r), c.dy + dx * sin(r) + dy * cos(r))
            }
            a = turn(a); b = turn(b)
        }
        let frame = Rect.fromLTRB(a.dx, a.dy, b.dx, b.dy)
        let ln = el.first("p:spPr")?.first("a:ln")
        let color = ln?.first("a:solidFill").flatMap(colors.color(in:))
            ?? el.first("p:style")?.first("a:lnRef").flatMap(colors.color(in:)) ?? colors.scheme("tx1")
        let width = ln?["w"].flatMap(Double.init).map { $0 / Pptx.emu } ?? 0.75
        var st = ShapeState(id: id(), name: el.first("p:nvCxnSpPr")?.first("p:cNvPr")?["name"] ?? "Line",
                            kind: .geometry(.line), frame: frame, rotation: 0, fill: nil, outline: color,
                            outlineWidth: width,
                            anchor: .middle, insets: EdgeInsets(left: 0, top: 0, right: 0, bottom: 0), prompt: nil,
                            text: nil, font: nil, size: 18, color: Color(0xFF000000), listIndent: 18)
        st.sourceXML = PptxXML.serialize(el)
        st.sourcePart = part
        st.keptLine = KeptLine(line: frame, box: box, outline: color, width: width)
        return st
    }

    private func _picture(_ el: XNode, _ transform: ((Rect) -> Rect)?, id: () -> Int) -> ShapeState? {
        // Audio and video are a `p:pic` too — the poster frame, with the
        // media hung on `p:nvPr` (`a:audioFile`/`a:videoFile`, `p14:media`)
        // and a `p:timing` tree that plays it. Modelled as a picture, the
        // media relationships would be dropped under a timing tree that
        // still calls them, and PowerPoint repairs the slide. Kept whole.
        if let nv = el.first("p:nvPicPr")?.first("p:nvPr"),
           nv.children.contains(where: { ["a:audioFile", "a:videoFile", "a:quickTimeFile", "a:wavAudioFile"].contains($0.name) }) {
            return _opaque(el, label: "Media", transform, id: id)
        }
        guard let rid = el.first("p:blipFill")?.first("a:blip")?["r:embed"],
              let target = package.rels(part).first(where: { $0.id == rid }), !target.external,
              package.parts[target.target] != nil,
              var frame = el.first("p:spPr")?.first("a:xfrm").flatMap(_xfrmRect) else {
            return _opaque(el, label: "Picture", transform, id: id)
        }
        if let t = transform { frame = t(frame) }
        let image = images.attachment(target.target, package)
        let rotation = (el.first("p:spPr")?.first("a:xfrm")?["rot"].flatMap(Double.init) ?? 0) / 60000
        // The crop: fractions of the picture cut from each edge.
        var crop: EdgeInsets? = nil
        if let src = el.first("p:blipFill")?.first("a:srcRect") {
            func f(_ k: String) -> Double { (src[k].flatMap(Double.init) ?? 0) / 100000 }
            let c = EdgeInsets(left: f("l"), top: f("t"), right: f("r"), bottom: f("b"))
            if c != .zero { crop = c }
        }
        return ShapeState(id: id(), name: el.first("p:nvPicPr")?.first("p:cNvPr")?["name"] ?? "Picture",
                          kind: .picture(image), frame: frame, rotation: rotation, fill: nil, outline: nil,
                          outlineWidth: 0, anchor: .top, insets: EdgeInsets(left: 0, top: 0, right: 0, bottom: 0),
                          prompt: nil, text: nil, font: nil, size: 18, color: Color(0xFF000000), listIndent: 18,
                          crop: crop)
    }

    /// `a:tbl` as an editable table: grid widths, merged cells (gridSpan,
    /// rowSpan; the hMerge/vMerge stand-ins dropped), cell text, and the
    /// look approximated from the table's flags in this deck's first accent.
    /// The element is kept too, written back while the text is unchanged.
    private func _table(_ el: XNode, _ transform: ((Rect) -> Rect)?, id: () -> Int) -> ShapeState? {
        guard let tbl = el.descendant("a:tbl"), var frame = el.first("p:xfrm").flatMap(_xfrmRect) else { return nil }
        if let t = transform { frame = t(frame) }
        let tableId = UUID().uuidString
        let widths = (tbl.first("a:tblGrid")?.all("a:gridCol") ?? []).compactMap { $0["w"].flatMap(Double.init).map { $0 / Pptx.emu } }
        let pr = tbl.first("a:tblPr")
        let firstRow = pr?["firstRow"] == "1"
        let banded = pr?["bandRow"] == "1"
        let styleId = pr?.first("a:tableStyleId")?.text.trimmingWhitespace() ?? ""
        let plain = ["{2D5ABB26-0587-4C30-8999-92F81FD0307C}", "{5940675A-B579-460E-94D1-54222C63F5DA}"].contains(styleId)
        let base = LevelStyle.paragraph(defaults?.first("a:lvl1pPr"), colors)
        var paragraphs: [RichParagraph] = []
        for (r, tr) in tbl.all("a:tr").enumerated() {
            var column = 0
            for tc in tr.all("a:tc") {
                defer { column += 1 }
                if tc["hMerge"] == "1" || tc["vMerge"] == "1" { continue }
                let cell = CellRef(table: tableId, row: r, column: column,
                                   span: tc["gridSpan"].flatMap(Int.init) ?? 1, rowSpan: tc["rowSpan"].flatMap(Int.init) ?? 1)
                // The header row's text is light and bold in every styled
                // table PowerPoint offers.
                var look = base
                if r == 0 && firstRow && !plain {
                    look.bold = look.bold ?? true
                    look.color = colors.scheme("lt1") ?? Color(0xFFFFFFFF)
                }
                var cellParas: [RichParagraph] = []
                for p in tc.first("a:txBody")?.all("a:p") ?? [] {
                    let level = LevelStyle.paragraph(p.first("a:pPr"), colors).filled(from: look)
                    var text = "", runs: [Run] = []
                    for child in p.children where child.name == "a:r" || child.name == "a:br" || child.name == "a:fld" {
                        let t = child.name == "a:br" ? "\n" : (child.first("a:t")?.text ?? "")
                        guard !t.isEmpty else { continue }
                        let s = (child.first("a:rPr").map { LevelStyle.run($0, colors) } ?? LevelStyle()).filled(from: level)
                        text += t
                        runs.append(Run(length: t.utf16.count, style: CharStyle(
                            bold: s.bold ?? false, italic: s.italic ?? false, underline: s.underline ?? false,
                            fontFamily: _font(s.font), fontSize: s.size ?? 18,
                            color: s.color ?? colors.scheme("tx1"))))
                    }
                    var style = RichParagraphStyle(spaceAfter: 0, lineSpacing: 1.0)
                    switch level.algn { case "ctr": style.alignment = .center; case "r": style.alignment = .right; default: break }
                    var para = text.isEmpty
                        ? RichParagraph(text: "", runs: [Run(length: 0, style: CharStyle(bold: look.bold ?? false, fontFamily: _font(look.font),
                                                                                          fontSize: look.size ?? 18, color: look.color))], style: style)
                        : RichParagraph(text: text, runs: runs, style: style)
                    para.cell = cell
                    cellParas.append(para)
                }
                if cellParas.isEmpty {
                    var para = RichParagraph(text: "", style: RichParagraphStyle(spaceAfter: 0, lineSpacing: 1.0))
                    para.cell = cell
                    cellParas = [para]
                }
                paragraphs += cellParas
            }
        }
        guard !paragraphs.isEmpty else { return nil }
        var doc = RichDocument(paragraphs: paragraphs)
        if !widths.isEmpty { doc.tableColumns[tableId] = widths }
        let accent = theme.colors["accent1"] ?? Color(0xFF4472C4)
        doc.tableStyles[tableId] = plain
            ? TableStyle(borders: styleId.hasPrefix("{5940675A"), headerRow: false, borderColor: colors.scheme("tx1"))
            : TableStyle(borders: true, headerRow: firstRow, headerFill: accent,
                         bandFill: banded ? DeckController.tint(accent, 0.40) : nil,
                         bandAltFill: banded ? DeckController.tint(accent, 0.20) : nil,
                         borderColor: Color(0xFFFFFFFF))
        var st = ShapeState(id: id(), name: el.descendant("p:cNvPr")?["name"] ?? "Table", kind: .table, frame: frame,
                            rotation: 0, fill: nil, outline: nil, outlineWidth: 0, anchor: .top,
                            insets: EdgeInsets(left: 0, top: 0, right: 0, bottom: 0), prompt: nil, text: doc,
                            font: _font(base.font), size: base.size ?? 18, color: base.color ?? colors.scheme("tx1") ?? Color(0xFF000000),
                            listIndent: 18)
        st.sourceXML = PptxXML.serialize(el)
        st.sourceText = doc
        st.sourcePart = part
        return st
    }

    /// A chart this app draws, from its part's cached values; kept as read
    /// too, and written back through that part while it is unchanged.
    private func _chart(_ el: XNode, _ transform: ((Rect) -> Rect)?, id: () -> Int) -> ShapeState? {
        guard let ref = el.descendant("c:chart")?["r:id"],
              let rel = package.rels(part).first(where: { $0.id == ref && !$0.external }),
              let space = package.xml(rel.target),
              let chart = ChartXML.read(space, color: { colors.color(in: $0) }),
              var frame = el.first("p:xfrm").flatMap(_xfrmRect) else { return nil }
        if let t = transform { frame = t(frame) }
        var st = ShapeState(id: id(), name: el.descendant("p:cNvPr")?["name"] ?? "Chart", kind: .chart(chart), frame: frame,
                            rotation: 0, fill: nil, outline: nil, outlineWidth: 0, anchor: .top,
                            insets: EdgeInsets(left: 0, top: 0, right: 0, bottom: 0), prompt: nil, text: nil,
                            font: nil, size: 18, color: Color(0xFF000000), listIndent: 18)
        st.sourceXML = PptxXML.serialize(el)
        st.sourcePart = part
        st.sourceChart = chart
        return st
    }

    private func _frameLabel(_ el: XNode) -> String {
        let uri = el.descendant("a:graphicData")?["uri"] ?? ""
        if uri.hasSuffix("/chart") || uri.containsSubstring("chartex") { return "Chart" }
        if uri.hasSuffix("/diagram") { return "SmartArt" }
        if uri.hasSuffix("/table") { return "Table" }
        if uri.containsSubstring("ole") { return "Embedded object" }
        return "Object"
    }

    private func _opaque(_ el: XNode, label: String, _ transform: ((Rect) -> Rect)?, id: () -> Int) -> ShapeState? {
        let x = el.first("p:xfrm") ?? el.first("p:spPr")?.first("a:xfrm") ?? el.first("p:grpSpPr")?.first("a:xfrm")
            ?? el.descendant("a:xfrm") ?? el.descendant("p:xfrm")
        guard var frame = x.flatMap(_xfrmRect) else { return nil }
        if let t = transform { frame = t(frame) }
        let name = el.descendant("p:cNvPr")?["name"] ?? label
        return ShapeState(id: id(), name: name,
                          kind: .opaque(OpaqueObject(xml: PptxXML.serialize(el), label: label, sourcePart: part)),
                          frame: frame, rotation: 0, fill: nil, outline: nil, outlineWidth: 0, anchor: .top,
                          insets: EdgeInsets(left: 0, top: 0, right: 0, bottom: 0), prompt: nil, text: nil,
                          font: nil, size: 18, color: Color(0xFF000000), listIndent: 18)
    }

    // MARK: Text

    private struct TextBody {
        var document: RichDocument
        var anchor: TextAnchor
        var insets: EdgeInsets
        var font: String
        var size: Double
        var color: Color
        var listIndent: Double
        /// `normAutofit`: shrink the text to fit, by `fontScale` now.
        var autofit = false
        var fontScale = 1.0
    }

    /// The master text style a placeholder (or plain shape) draws from.
    private func _masterStyle(_ ph: XNode?) -> XNode? {
        let styles = master?.first("p:txStyles")
        guard let ph else { return nil }
        switch ph["type"] ?? "obj" {
        case "title", "ctrTitle": return styles?.first("p:titleStyle")
        case "body", "subTitle", "obj": return styles?.first("p:bodyStyle")
        default: return styles?.first("p:otherStyle")
        }
    }

    /// Level `n` (0-based) as the whole chain resolves it, lowest layer first.
    private func _level(_ n: Int, shapeList: XNode?, ph: XNode?, inherited: (layout: XNode?, master: XNode?)) -> LevelStyle {
        let tag = "a:lvl\(n + 1)pPr"
        var layers: [XNode?] = [
            shapeList?.first(tag),
            inherited.layout?.first("p:txBody")?.first("a:lstStyle")?.first(tag),
            inherited.master?.first("p:txBody")?.first("a:lstStyle")?.first(tag),
            _masterStyle(ph)?.first(tag),
            defaults?.first(tag),
        ]
        // A text box or drawn shape on a slide takes the presentation's
        // default text style, not the master's `otherStyle` — PowerPoint
        // centres a box whose deck says algn="ctr" there while the master
        // says "l" (45541_Header's title slide). otherStyle only fills in
        // what the default leaves unsaid.
        if ph == nil {
            layers = [shapeList?.first(tag), defaults?.first(tag),
                      master?.first("p:txStyles")?.first("p:otherStyle")?.first(tag)]
        }
        var s = LevelStyle()
        for layer in layers { s = s.filled(from: LevelStyle.paragraph(layer, colors)) }
        return s
    }

    private func _font(_ f: String?) -> String {
        switch f {
        case nil, "+mn-lt", "+mn-ea", "+mn-cs": return theme.minor
        case "+mj-lt", "+mj-ea", "+mj-cs": return theme.major
        default: return f!
        }
    }

    private func _text(_ sp: XNode, ph: XNode?, inherited: (layout: XNode?, master: XNode?),
                       kind: ShapeKind) -> TextBody {
        // The shape style's text colour (fontRef), under any the text says.
        let styleColor = sp.first("p:style")?.first("a:fontRef").flatMap(colors.color(in:))
        let tx1 = styleColor ?? colors.scheme("tx1")
        let body = sp.first("p:txBody")
        // Body properties: the shape's, else its layout's, else the master's.
        let bodies = [body?.first("a:bodyPr"),
                      inherited.layout?.first("p:txBody")?.first("a:bodyPr"),
                      inherited.master?.first("p:txBody")?.first("a:bodyPr")]
        func attr(_ name: String) -> String? { bodies.lazy.compactMap { $0?[name] }.first }
        let anchor: TextAnchor = {
            switch attr("anchor") {
            case "ctr": return .middle
            case "b": return .bottom
            // Absent everywhere means top, for every kind of shape: PowerPoint
            // writes anchor="ctr" when it wants a drawn shape centred.
            default: return .top
            }
        }()
        func inset(_ n: String, _ d: Double) -> Double { attr(n).flatMap(Double.init).map { $0 / Pptx.emu } ?? d }
        let insets = EdgeInsets(left: inset("lIns", 7.2), top: inset("tIns", 3.6),
                                right: inset("rIns", 7.2), bottom: inset("bIns", 3.6))
        // normAutofit's fontScale: PowerPoint shrank the text to fit. The
        // sizes stay the file's; the shape draws them at the scale.
        let scale = (body?.first("a:bodyPr")?.first("a:normAutofit")?["fontScale"].flatMap(Double.init)).map { $0 / 100000 } ?? 1
        let fitRule = bodies.lazy.compactMap { b in
            b?.children.first { ["a:normAutofit", "a:spAutoFit", "a:noAutofit"].contains($0.name) }?.name
        }.first
        let list = body?.first("a:lstStyle")

        // The style's text colour (fontRef) beats what the layout and master
        // say, not what the shape's own list style or paragraph says.
        func styled(_ l: LevelStyle, _ n: Int, _ pPr: XNode?) -> LevelStyle {
            guard let sc = styleColor, LevelStyle.paragraph(pPr, colors).color == nil,
                  LevelStyle.paragraph(list?.first("a:lvl\(n + 1)pPr"), colors).color == nil else { return l }
            var l = l
            l.color = sc
            return l
        }
        let level0 = styled(_level(0, shapeList: list, ph: ph, inherited: inherited), 0, nil)
        var paragraphs: [RichParagraph] = []
        for p in body?.all("a:p") ?? [] {
            let pPr = p.first("a:pPr")
            let lvl = pPr?["lvl"].flatMap(Int.init) ?? 0
            let level = styled(LevelStyle.paragraph(pPr, colors).filled(from: _level(lvl, shapeList: list, ph: ph, inherited: inherited)), lvl, pPr)
            let size = level.size ?? 18
            var style = RichParagraphStyle(spaceAfter: level.afterPoints ?? 0, lineSpacing: 1.0)
            switch level.algn {
            case "ctr": style.alignment = .center
            case "r": style.alignment = .right
            case "just", "dist": style.alignment = .justify
            default: style.alignment = .left
            }
            if let m = level.lineMultiple { style.lineSpacing = m } else if let pts = level.linePoints {
                // Exactly that many points, whatever the runs' sizes.
                style.lineHeightPoints = pts
            }
            style.spaceBefore = level.beforePoints ?? (level.beforePercent.map { $0 * size * 1.2 } ?? 0)
            switch level.bullet {
            case .char?, .number?:
                style.list = level.bullet == .char ? .bullet : .numbered
                style.listLevel = lvl
                // The file's own text edge (marL) and bullet offset (indent):
                // the text placed where the file puts it, both written back
                // as read. The layout indents a list by the shape's list
                // indent per level; indentLeft carries the difference.
                let shapeIndent = level0.marL ?? 18
                if let marL = level.marL { style.indentLeft = marL - shapeIndent * Double(lvl + 1) }
                // As an offset from the usual hang (-shapeIndent), so 0 is
                // "the usual" and a file's indent="0" survives as itself.
                if let indent = level.indent { style.firstLineIndent = indent + shapeIndent }
            default:
                style.indentLeft = level.marL ?? 0
                style.firstLineIndent = level.indent ?? 0
            }

            var text = ""
            var runs: [Run] = []
            func add(_ t: String, _ r: LevelStyle) {
                guard !t.isEmpty else { return }
                let s = r.filled(from: level)
                var cs = CharStyle(bold: s.bold ?? false, italic: s.italic ?? false,
                                   underline: s.underline ?? false, strikethrough: s.strike ?? false,
                                   fontFamily: _font(s.font), fontSize: ((s.size ?? 18) * 10).rounded() / 10,
                                   color: s.color ?? tx1)
                if let b = s.baseline { cs.script = b > 0 ? .superscript : b < 0 ? .subscript : .normal }
                text += t
                runs.append(Run(length: t.utf16.count, style: cs))
            }
            for child in p.children {
                switch child.name {
                case "a:r": add(child.first("a:t")?.text ?? "", child.first("a:rPr").map { LevelStyle.run($0, colors) } ?? LevelStyle())
                case "a:br": add("\n", child.first("a:rPr").map { LevelStyle.run($0, colors) } ?? LevelStyle())
                case "a:fld": add(child.first("a:t")?.text ?? "", child.first("a:rPr").map { LevelStyle.run($0, colors) } ?? LevelStyle())
                default: continue
                }
            }
            if text.isEmpty {
                let end = p.first("a:endParaRPr").map { LevelStyle.run($0, colors) } ?? LevelStyle()
                let s = end.filled(from: level)
                paragraphs.append(RichParagraph(text: "", runs: [Run(length: 0, style: CharStyle(
                    bold: s.bold ?? false, italic: s.italic ?? false, fontFamily: _font(s.font),
                    fontSize: ((s.size ?? 18) * 10).rounded() / 10, color: s.color ?? tx1))],
                    style: style))
            } else {
                paragraphs.append(RichParagraph(text: text, runs: runs, style: style))
            }
        }
        if paragraphs.isEmpty {
            var style = RichParagraphStyle(spaceAfter: 0, lineSpacing: level0.lineMultiple ?? 1.0)
            style.alignment = level0.algn == "ctr" ? .center : level0.algn == "r" ? .right : .left
            if level0.bullet == .char { style.list = .bullet }
            paragraphs = [RichParagraph(text: "", style: style)]
        }
        return TextBody(document: RichDocument(paragraphs: paragraphs), anchor: anchor, insets: insets,
                        font: _font(level0.font), size: level0.size ?? 18,
                        color: level0.color ?? tx1 ?? Color(0xFF000000),
                        listIndent: level0.marL ?? 18,
                        autofit: fitRule == "a:normAutofit", fontScale: fitRule == "a:normAutofit" ? scale : 1)
    }

    // MARK: Notes

    func notes() -> RichDocument {
        guard let notesPart = package.rel(part, kind: "notesSlide")?.target, let notes = package.xml(notesPart),
              let tree = notes.first("p:cSld")?.first("p:spTree") else { return RichDocument() }
        for sp in tree.all("p:sp") where _ph(sp)?["type"] == "body" {
            let paras: [RichParagraph] = (sp.first("p:txBody")?.all("a:p") ?? []).map { p in
                let text = p.children.compactMap { c -> String? in
                    switch c.name {
                    case "a:r", "a:fld": return c.first("a:t")?.text
                    case "a:br": return "\n"
                    default: return nil
                    }
                }.joined()
                return RichParagraph(text: text, style: RichParagraphStyle(spaceAfter: 0, lineSpacing: 1.0))
            }
            return RichDocument(paragraphs: paras.isEmpty ? [RichParagraph()] : paras)
        }
        return RichDocument()
    }
}

/// One attachment per media part, so a picture used on many slides (or a
/// master's background) is one image to decode and one part to write.
final class PptxImages {
    private var _byPart: [String: ImageAttachment] = [:]

    func attachment(_ part: String, _ package: PptxPackage) -> ImageAttachment {
        if let a = _byPart[part] { return a }
        let a = ImageAttachment(data: package.parts[part] ?? Data(), width: 0, height: 0, name: part.lastPathComponent)
        _byPart[part] = a
        return a
    }
}

// MARK: - Serializing kept XML

enum PptxXML {
    /// An element back to text, prefixes and all. Attribute order is not
    /// kept (the parser does not keep it), which XML does not care about.
    static func serialize(_ node: XNode) -> String {
        var out = "<" + node.name
        for (k, v) in node.attrs.sorted(by: { $0.key < $1.key }) {
            out += " \(k)=\"\(escape(v, attribute: true))\""
        }
        let text = node.text.trimmingWhitespace().isEmpty && !node.children.isEmpty ? "" : node.text
        if node.children.isEmpty && text.isEmpty { return out + "/>" }
        out += ">" + escape(text, attribute: false)
        for c in node.children { out += serialize(c) }
        return out + "</" + node.name + ">"
    }

    static func escape(_ s: String, attribute: Bool) -> String {
        var out = ""
        out.reserveCapacity(s.utf8.count)
        for ch in s {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"" where attribute: out += "&quot;"
            default: out.append(ch)
            }
        }
        return out
    }
}
