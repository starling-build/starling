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
    /// The format scheme's fill styles (`a:fillStyleLst`), which a shape's
    /// style refers to by index with its own colour as `phClr`.
    var fillStyles: [XNode] = []

    init(_ root: XNode?) {
        guard let root, let elements = root.descendant("a:themeElements") else { return }
        fillStyles = elements.first("a:fmtScheme")?.first("a:fillStyleLst")?.children ?? []
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

    /// lumMod/lumOff, satMod/satOff and hueMod/hueOff (in HSL), tint,
    /// shade and alpha, as DrawingML applies them. (satMod is what makes a
    /// theme's near-grey `lt2` the warm cream of its radial backgrounds.)
    static func modify(_ c: Color, _ node: XNode) -> Color {
        var r = Double((c.value >> 16) & 0xFF) / 255, g = Double((c.value >> 8) & 0xFF) / 255, b = Double(c.value & 0xFF) / 255
        var alpha = 1.0
        // Between `a:gamma` and `a:invGamma` (how a converted .ppt spells
        // its shades) a tint or shade works on the sRGB values as they are.
        var gammaShifted = false
        for m in node.children {
            let v = (m["val"].flatMap(Double.init) ?? 100000) / 100000
            switch m.name {
            case "a:gamma": gammaShifted = true
            case "a:invGamma": gammaShifted = false
            case "a:lumMod", "a:lumOff":
                var (h, s, l) = _hsl(r, g, b)
                l = m.name == "a:lumMod" ? l * v : l + v
                (r, g, b) = _rgb(h, s, min(1, max(0, l)))
                h = 0; s = 0
            case "a:satMod", "a:satOff":
                var (h, s, l) = _hsl(r, g, b)
                s = m.name == "a:satMod" ? s * v : s + v
                (r, g, b) = _rgb(h, min(1, max(0, s)), l)
                h = 0; l = 0
            case "a:hueMod", "a:hueOff":
                // Hues are in 60000ths of a degree; the HSL here is 0...1.
                var (h, s, l) = _hsl(r, g, b)
                h = m.name == "a:hueMod" ? h * v : h + (m["val"].flatMap(Double.init) ?? 0) / 60000 / 360
                h -= h.rounded(.down)
                (r, g, b) = _rgb(h, s, l)
                s = 0; l = 0
            case "a:tint", "a:shade":
                // Mixed with white (tint) or black (shade) in linear light,
                // as PowerPoint does: a 55% tint of a dark grey is a light
                // grey, not the sRGB midpoint's medium one (GeomLec1's
                // backgrounds, a theme's radial fills).
                func lin(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
                func srgb(_ l: Double) -> Double { l <= 0.0031308 ? l * 12.92 : 1.055 * pow(l, 1 / 2.4) - 0.055 }
                let tint = m.name == "a:tint"
                func apply(_ c: Double) -> Double {
                    if gammaShifted { return tint ? 1 - (1 - c) * v : c * v }
                    return srgb(tint ? 1 - (1 - lin(c)) * v : lin(c) * v)
                }
                r = apply(r); g = apply(g); b = apply(b)
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
    var afterPercent: Double?
    var bullet: Bullet?
    /// `a:buChar`'s glyph and `a:buFont`'s face (a symbol face's code
    /// mapped to the glyph it shows).
    var bulletChar: String?
    var bulletFont: String?
    /// `a:buClr` and `a:buSzPct` (a share of the text size); the `…Tx`
    /// forms (follow the text) read as nil.
    var bulletColor: Color?
    var bulletScale: Double?
    var bulletColorFollows = false
    var bulletSizeFollows = false
    /// `cap`: "all", "small" or "none".
    var caps: String?
    var size: Double?
    var bold: Bool?
    var italic: Bool?
    var underline: Bool?
    var strike: Bool?
    var font: String?
    var color: Color?
    var baseline: Double?
    /// Character spacing in points (`spc`, hundredths of a point).
    var spc: Double?

    func filled(from lower: LevelStyle) -> LevelStyle {
        var s = self
        s.algn = s.algn ?? lower.algn
        s.marL = s.marL ?? lower.marL
        s.indent = s.indent ?? lower.indent
        if s.lineMultiple == nil && s.linePoints == nil { s.lineMultiple = lower.lineMultiple; s.linePoints = lower.linePoints }
        if s.beforePoints == nil && s.beforePercent == nil { s.beforePoints = lower.beforePoints; s.beforePercent = lower.beforePercent }
        if s.afterPoints == nil && s.afterPercent == nil { s.afterPoints = lower.afterPoints; s.afterPercent = lower.afterPercent }
        s.bullet = s.bullet ?? lower.bullet
        if s.bulletChar == nil { s.bulletChar = lower.bulletChar; s.bulletFont = s.bulletFont ?? lower.bulletFont }
        if s.bulletColor == nil, !s.bulletColorFollows { s.bulletColor = lower.bulletColor; s.bulletColorFollows = lower.bulletColorFollows }
        if s.bulletScale == nil, !s.bulletSizeFollows { s.bulletScale = lower.bulletScale; s.bulletSizeFollows = lower.bulletSizeFollows }
        s.caps = s.caps ?? lower.caps
        s.size = s.size ?? lower.size
        s.bold = s.bold ?? lower.bold
        s.italic = s.italic ?? lower.italic
        s.underline = s.underline ?? lower.underline
        s.strike = s.strike ?? lower.strike
        s.font = s.font ?? lower.font
        s.color = s.color ?? lower.color
        s.baseline = s.baseline ?? lower.baseline
        s.spc = s.spc ?? lower.spc
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
        if let a = p.first("a:spcAft") {
            if let v = a.first("a:spcPts")?["val"].flatMap(Double.init) { s.afterPoints = v / 100 }
            if let v = a.first("a:spcPct")?["val"].flatMap(Double.init) { s.afterPercent = v / 100000 }
        }
        if p.has("a:buNone") { s.bullet = Bullet.none }
        if let bu = p.first("a:buChar") { s.bullet = .char; s.bulletChar = bu["char"] }
        if let f = p.first("a:buFont")?["typeface"] { s.bulletFont = f }
        if let c = p.first("a:buClr") { s.bulletColor = colors.color(in: c) }
        if p.has("a:buClrTx") { s.bulletColorFollows = true }
        if let v = p.first("a:buSzPct")?["val"].flatMap(Double.init) { s.bulletScale = v / 100000 }
        if p.has("a:buSzTx") { s.bulletSizeFollows = true }
        if p.has("a:buAutoNum") { s.bullet = .number }
        if let r = p.first("a:defRPr") { s = run(r, colors).filled(from: s) }
        return s
    }

    /// The bullet as a Unicode glyph: the file's character, or what a
    /// symbol face (Wingdings, Symbol) shows for that code; nil for a code
    /// in such a face this app does not know, which draws the level's own.
    var bulletGlyph: String? {
        guard let ch = bulletChar, let scalar = ch.unicodeScalars.first else { return nil }
        // Symbol faces are often spelled in the private range (U+F0xx).
        let code = (0xF000 ... 0xF0FF).contains(scalar.value) ? scalar.value - 0xF000 : scalar.value
        let face = (bulletFont ?? "").lowercased()
        if face.hasPrefix("wingdings") {
            let map: [UInt32: String] = [
                0x6C: "●", 0x6D: "❍", 0x6E: "■", 0x6F: "□", 0x70: "◻", 0x71: "❑", 0x72: "❒", 0x73: "◆",
                0x74: "❖", 0x75: "◆", 0x76: "❖", 0x77: "◆", 0x78: "⌧", 0x7E: "⬥", 0xA7: "▪", 0xA8: "◻",
                0xB7: "●", 0xD8: "➢", 0xDC: "➨", 0xE0: "⇨", 0xE8: "➔", 0xF0: "⇨", 0xF6: "⇦", 0xFC: "✓",
                0xFE: "☑", 0xA1: "○", 0x9F: "•", 0x9E: "·", 0x4A: "☺",
            ]
            return map[code]
        }
        if face.hasPrefix("symbol") {
            let map: [UInt32: String] = [0xB7: "•", 0x2D: "–", 0x3E: ">", 0xB2: "″", 0xA8: "♦", 0xA7: "♣", 0xAE: "→", 0xDE: "⇒"]
            return map[code]
        }
        if face.hasPrefix("webdings") { return nil }
        // A bullet is one character: PowerPoint shows the first of "••"
        // (a SmartArt drawing's spelling, tdf93830) and no more.
        return String(ch[ch.startIndex])
    }

    /// A `a:rPr` / `a:defRPr` / `a:endParaRPr` element.
    static func run(_ r: XNode, _ colors: ColorContext) -> LevelStyle {
        var s = LevelStyle()
        s.size = r["sz"].flatMap(Double.init).map { $0 / 100 }
        s.bold = r["b"].map { $0 == "1" || $0 == "true" }
        s.italic = r["i"].map { $0 == "1" || $0 == "true" }
        s.underline = r["u"].map { $0 != "none" }
        s.strike = r["strike"].map { $0 != "noStrike" }
        s.caps = r["cap"]
        s.baseline = r["baseline"].flatMap(Double.init)
        s.spc = r["spc"].flatMap(Double.init).map { $0 / 100 }
        s.font = r.first("a:latin")?["typeface"]
        if let fill = r.first("a:solidFill") { s.color = colors.color(in: fill) }
        return s
    }
}

// MARK: - Reader

struct PptxReader {
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
        // The deck's table styles, by id: what each table's `tableStyleId`
        // names (PowerPoint writes every style a deck uses into the part).
        var tableStyles: [String: XNode] = [:]
        if let lst = package.rel(pres, kind: "tableStyles").flatMap({ package.xml($0.target) }) {
            for st in lst.all("a:tblStyle") { if let id = st["styleId"] { tableStyles[id] = st } }
        }

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
            // A slide (or its layout) may override the map — swapping bg1
            // for dk1 turns a light theme's slide dark.
            for owner in [layout, slide] {
                if let o = owner?.first("p:clrMapOvr")?.first("a:overrideClrMapping") {
                    for (k, v) in o.attrs { colors.map[k] = v }
                }
            }
            if n == 0 { deckTheme = Self._deckTheme(theme, colors) }
            let ctx = SlideContext(package: package, part: part, slide: slide, layout: layout, master: master,
                                   colors: colors, theme: theme, defaults: defaults, slideSize: size, images: images,
                                   tableStyles: tableStyles)
            var shapes: [ShapeState] = []
            if let tree = slide.first("p:cSld")?.first("p:spTree") {
                ctx.shapes(in: tree, transform: nil, into: &shapes, id: id)
            }
            // What the master and the layout draw behind the slide — their
            // own shapes (logos, bars, pictures), not their placeholders —
            // unless the slide (or, for the master's, the layout) says
            // `showMasterSp="0"`. Drawn, never written.
            var decorations: [ShapeState] = []
            if slide["showMasterSp"] != "0" {
                var owners: [(String, XNode)] = []
                if let masterPart, let master, layout?["showMasterSp"] != "0" { owners.append((masterPart, master)) }
                if let layoutPart, let layout { owners.append((layoutPart, layout)) }
                for (ownerPart, xml) in owners {
                    guard let tree = xml.first("p:cSld")?.first("p:spTree") else { continue }
                    let octx = SlideContext(package: package, part: ownerPart, slide: xml, layout: layout, master: master,
                                            colors: colors, theme: theme, defaults: defaults, slideSize: size, images: images)
                    var found: [ShapeState] = []
                    octx.shapes(in: tree, transform: nil, into: &found, id: id)
                    decorations += found.filter { s in
                        if case .placeholder = s.kind { return false }
                        // An object this app cannot draw is a labelled box on
                        // a slide, but nothing in its backdrop.
                        if case .opaque(let o) = s.kind, o.freeform == nil { return false }
                        return s.phType == nil && s.phIdx == nil
                    }
                }
            }
            // An ActiveX control (`p:controls`) shows as its fallback
            // picture. Drawn with the backdrop, so under the slide's
            // shapes; PowerPoint draws controls over them (rarely overlap).
            if let controls = slide.first("p:cSld")?.first("p:controls") {
                let tree = XNode(name: "p:spTree", attrs: [:])
                func collect(_ n: XNode) {
                    for c in n.children { if c.name == "p:pic" { tree.children.append(c) } else { collect(c) } }
                }
                collect(controls)
                var found: [ShapeState] = []
                ctx.shapes(in: tree, transform: nil, into: &found, id: id)
                decorations += found.filter { if case .picture = $0.kind { return true } else { return false } }
            }
            let bg = slide.first("p:cSld")?.first("p:bg")
            let themeRoot = themePart.flatMap(package.xml)
            // The slide's own background is its; one from its layout or
            // master is only drawn (writing it per slide would copy the
            // master's picture into every slide).
            var bgFill: SlideFill? = nil
            var inherited: SlideFill? = nil
            if let b = slide.first("p:cSld")?.first("p:bg") {
                bgFill = _background(b, owner: part, colors: colors, theme: themeRoot, themePart: themePart)
            } else {
                for (owner, xml) in [(layoutPart, layout), (masterPart, master)] {
                    guard let owner, let b = xml?.first("p:cSld")?.first("p:bg") else { continue }
                    inherited = _background(b, owner: owner, colors: colors, theme: themeRoot, themePart: themePart)
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
                hideMasterShapes: slide["showMasterSp"] == "0",
                clrMapOvrXML: slide.first("p:clrMapOvr").map(PptxXML.serialize),
                controlsXML: slide.first("p:cSld")?.first("p:controls").map(PptxXML.serialize),
                decorations: decorations,
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
    private func _background(_ bg: XNode, owner: String, colors: ColorContext, theme: XNode?,
                             themePart: String?) -> SlideFill? {
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
        // The style is one fill element; wrap it so `fill` can read it. A
        // picture in it is the theme's, so its r:embed resolves there.
        let holder = XNode(name: "holder", attrs: [:])
        holder.children = [entries[n]]
        return fill(holder, owner: themePart ?? owner, colors: c)
    }

    /// The fill inside a properties element (`p:bgPr`, `p:spPr`).
    func fill(_ pr: XNode, owner: String, colors: ColorContext) -> SlideFill? {
        if let f = pr.first("a:solidFill") { return colors.color(in: f).map { SlideFill(color: $0) } }
        if let g = pr.first("a:gradFill") { return Self.gradient(g, colors: colors) }
        if let b = pr.first("a:blipFill"), let blip = b.first("a:blip"), let rid = blip["r:embed"],
           let rel = package.rels(owner).first(where: { $0.id == rid }), !rel.external,
           package.parts[rel.target] != nil {
            var f = SlideFill(image: images.attachment(rel.target, package))
            (f.imageAlpha, f.duotone) = Self.blipEffects(blip, colors: colors)
            if let tile = b.first("a:tile") {
                f.tiled = true
                // At the picture's own resolution (its declared dpi) times
                // `sx`. One that declares none comes out at 144 dpi — as
                // measured against PowerPoint's (for Mac) export of
                // lo-page_transparent_bitmap, a 94 px PNG drawn 47 pt wide;
                // its pixels taken as a Retina screen's, it seems.
                let dpi = package.parts[rel.target].flatMap(Self.imageDPI) ?? 144
                f.tileScale = (tile["sx"].flatMap(Double.init) ?? 100000) / 100000 * 96 / dpi
            }
            f.imageInset = Self.stretchInset(b)
            return f
        }
        return nil
    }

    /// The resolution a picture declares, in dots per inch: a PNG's `pHYs`,
    /// a JPEG's JFIF density. Nil when it declares none.
    static func imageDPI(_ data: Data) -> Double? {
        let b = [UInt8](data.prefix(64 * 1024))
        func be32(_ i: Int) -> Int { (Int(b[i]) << 24) | (Int(b[i + 1]) << 16) | (Int(b[i + 2]) << 8) | Int(b[i + 3]) }
        if b.count > 8, b[0] == 0x89, b[1] == 0x50, b[2] == 0x4E, b[3] == 0x47 {
            var i = 8
            while i + 8 <= b.count {
                let len = be32(i)
                let type = String(decoding: b[i + 4 ..< i + 8], as: UTF8.self)
                if type == "pHYs", i + 17 <= b.count {
                    let x = be32(i + 8), unit = b[i + 16]
                    return unit == 1 && x > 0 ? Double(x) * 0.0254 : nil
                }
                if type == "IDAT" || type == "IEND" { return nil }
                i += 12 + len
            }
            return nil
        }
        if b.count > 18, b[0] == 0xFF, b[1] == 0xD8 {
            var i = 2
            while i + 4 <= b.count, b[i] == 0xFF {
                let marker = b[i + 1], len = (Int(b[i + 2]) << 8) | Int(b[i + 3])
                if marker == 0xE0, i + 18 <= b.count, b[i + 4] == 0x4A, b[i + 5] == 0x46, b[i + 6] == 0x49, b[i + 7] == 0x46 {
                    let unit = b[i + 11], x = (Int(b[i + 12]) << 8) | Int(b[i + 13])
                    if x <= 1 { return nil }
                    return unit == 1 ? Double(x) : unit == 2 ? Double(x) * 2.54 : nil
                }
                if marker == 0xDA { return nil }
                i += 2 + len
            }
        }
        return nil
    }

    /// An `a:gradFill` as a fill: its stops in order and its direction, or
    /// its path (`a:path`, radiating from `a:fillToRect`). A single stop is
    /// a colour; none at all is nothing (the shape's style fill then).
    static func gradient(_ g: XNode, colors: ColorContext) -> SlideFill? {
        let stops: [SlideFill.GradientStop] = (g.first("a:gsLst")?.all("a:gs") ?? []).compactMap { gs in
            guard let c = colors.color(in: gs) else { return nil }
            return SlideFill.GradientStop(position: (gs["pos"].flatMap(Double.init) ?? 0) / 100000, color: c)
        }.sorted { $0.position < $1.position }
        if stops.isEmpty { return nil }
        if stops.count == 1 { return SlideFill(color: stops[0].color) }
        var f = SlideFill(color: stops[0].color, stops: stops,
                          angle: (g.first("a:lin")?["ang"].flatMap(Double.init) ?? 5_400_000) / 60000)
        if let path = g.first("a:path") {
            f.path = path["path"].flatMap(SlideFill.GradientPath.init(rawValue:)) ?? .shape
            if let to = path.first("a:fillToRect") {
                func v(_ k: String) -> Double { (to[k].flatMap(Double.init) ?? 0) / 100000 }
                f.fillTo = Rect.fromLTRB(v("l"), v("t"), 1 - v("r"), 1 - v("b"))
            } else {
                f.fillTo = Rect.fromLTRB(0, 0, 1, 1)
            }
        }
        return f
    }

    /// `a:stretch/a:fillRect` in a blip fill: where the picture sits, as
    /// fractions inset from each edge.
    static func stretchInset(_ blipFill: XNode) -> EdgeInsets {
        guard let fr = blipFill.first("a:stretch")?.first("a:fillRect") else { return .zero }
        func v(_ k: String) -> Double { (fr[k].flatMap(Double.init) ?? 0) / 100000 }
        return EdgeInsets(left: v("l"), top: v("t"), right: v("r"), bottom: v("b"))
    }

    /// A blip's transparency (`a:alphaModFix amt`) and duotone (its two
    /// colours), the effects this app draws.
    static func blipEffects(_ blip: XNode, colors: ColorContext) -> (Double, [Color]?) {
        let alpha = (blip.first("a:alphaModFix")?["amt"].flatMap(Double.init) ?? 100000) / 100000
        var duotone: [Color]? = nil
        // Greyscale (`a:grayscl`) is the duotone from black to white.
        if blip.has("a:grayscl") { duotone = [Color(0xFF000000), Color(0xFFFFFFFF)] }
        if let d = blip.first("a:duotone") {
            let holder = XNode(name: "holder", attrs: [:])
            var pair: [Color] = []
            for c in d.children {
                holder.children = [c]
                if let col = colors.color(in: holder) { pair.append(col) }
            }
            if pair.count == 2 { duotone = pair }
        }
        return (max(0, min(1, alpha)), duotone)
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
    /// The deck's `a:tblStyle` elements by id.
    var tableStyles: [String: XNode] = [:]

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
                group: ShapeGroup? = nil, groupFill: Color? = nil) {
        // Each shape keeps its file id (animations name shapes by it). A
        // group is flattened for editing, its members remembering it (the
        // outermost one) so a save groups them again under its id.
        func add(_ s: ShapeState?, _ el: XNode) {
            guard var s else { return }
            s.fileId = el.descendant("p:cNvPr")?["id"].flatMap(Int.init)
            s.group = group
            // A member filled by its group (`a:grpFill`): drawn in the
            // group's colour; still the shape that was read, so a save
            // keeps its element (and the group's fill with it).
            if s.fill == nil, let groupFill, el.first("p:spPr")?.has("a:grpFill") == true {
                s.fill = groupFill
                s.keptLook?.readFill = groupFill
                if s.readShape != nil { s.readShape = ReadShape(s) }
            }
            out.append(s)
        }
        func groupOf(_ el: XNode) -> ShapeGroup? {
            if let group { return group }
            let nv = el.first("p:nvGrpSpPr")?.first("p:cNvPr")
            let fill = el.first("p:grpSpPr")?.children.first {
                ["a:solidFill", "a:gradFill", "a:blipFill", "a:pattFill", "a:grpFill"].contains($0.name)
            }
            return ShapeGroup(fileId: nv?["id"].flatMap(Int.init), name: nv?["name"] ?? "Group", key: id(),
                              hidden: nv?["hidden"] == "1", fillXML: fill.map(PptxXML.serialize),
                              fillColor: ownFill(el))
        }
        /// The colour a group's members take for `a:grpFill`: the group's
        /// own solid or gradient fill, or (saying `a:grpFill` itself, or
        /// nothing) its enclosing group's.
        func ownFill(_ el: XNode) -> Color? {
            guard let pr = el.first("p:grpSpPr") else { return groupFill }
            if let f = pr.first("a:solidFill") { return colors.color(in: f) }
            if let g = pr.first("a:gradFill") {
                let stops = g.first("a:gsLst")?.all("a:gs").compactMap { colors.color(in: $0) } ?? []
                return stops.isEmpty ? groupFill : stops[stops.count / 2]
            }
            return groupFill
        }
        for el in tree.children {
            switch el.name {
            case "p:sp": add(_shape(el, transform, id: id), el)
            case "p:cxnSp": add(_connector(el, transform, id: id), el)
            case "p:pic": add(_picture(el, transform, id: id), el)
            case "p:graphicFrame":
                if _frameLabel(el) == "Table", let t = _table(el, transform, id: id) { add(t, el) }
                else if _frameLabel(el) == "Chart", let c = _chart(el, transform, id: id) { add(c, el) }
                else if _frameLabel(el) == "SmartArt", var o = _opaque(el, label: "SmartArt", transform, id: id) {
                    // Kept whole for the file; drawn from the diagram's own
                    // drawing part (PowerPoint's rendering of it) when the
                    // file has one.
                    if case .opaque(var obj) = o.kind {
                        obj.rendering = _diagram(el, frame: o.frame, id: id)
                        o.kind = .opaque(obj)
                    }
                    add(o, el)
                } else if _frameLabel(el) == "Embedded object", var o = _opaque(el, label: "Embedded object", transform, id: id) {
                    // Drawn from the object's own fallback picture (what the
                    // file shows where the object is not activated).
                    if case .opaque(var obj) = o.kind, let pic = el.descendant("p:pic"),
                       let r = _picture(pic, transform, id: id), case .picture = r.kind {
                        obj.rendering = [r]
                        o.kind = .opaque(obj)
                    } else if case .opaque(var obj) = o.kind, let spid = el.descendant("p:oleObj")?["spid"],
                              let image = _vmlImage(spid) {
                        // An object from before the fallback picture: its
                        // preview is the VML drawing's shape of that id.
                        obj.rendering = [ShapeState(
                            id: id(), name: "Preview", kind: .picture(image), frame: o.frame, rotation: 0, fill: nil,
                            outline: nil, outlineWidth: 0, anchor: .top,
                            insets: EdgeInsets(left: 0, top: 0, right: 0, bottom: 0), prompt: nil, text: nil,
                            font: nil, size: 18, color: Color(0xFF000000), listIndent: 18)]
                        o.kind = .opaque(obj)
                    }
                    add(o, el)
                } else {
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
                    // No child space to map through (a zero `chExt`, which
                    // PowerPoint still draws somehow — tdf136830): kept
                    // whole, so it gets exactly that back.
                    add(_opaque(el, label: "Group", transform, id: id), el)
                    continue
                }
                let sx = frame.width / (ccx / Pptx.emu), sy = frame.height / (ccy / Pptx.emu)
                let map: (Rect) -> Rect = { r in
                    let mapped = Rect.fromLTWH(frame.left + (r.left - cox / Pptx.emu) * sx,
                                               frame.top + (r.top - coy / Pptx.emu) * sy,
                                               r.width * sx, r.height * sy)
                    return transform?(mapped) ?? mapped
                }
                shapes(in: el, transform: map, into: &out, id: id, group: groupOf(el), groupFill: ownFill(el))
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
        // A date, footer or slide-number placeholder with no frame of its
        // own and none on the layout is not on the slide for PowerPoint,
        // whatever the master has (the file keeps it; a save does too).
        let hiddenByLayout = own == nil && inherited.layout == nil
            && ["dt", "ftr", "sldNum"].contains(ph?["type"] ?? "")
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
        } else if let geom = spPr?.first("a:custGeom"),
                  let ext = xfrm?.first("a:ext"), let cx = ext["cx"].flatMap(Double.init), let cy = ext["cy"].flatMap(Double.init),
                  let freeform = FreeformGeometry.parse(geom, width: cx, height: cy) {
            // A freeform: kept whole for the file, drawn along its path.
            var o = OpaqueObject(xml: PptxXML.serialize(sp), label: "Freeform", sourcePart: part)
            o.freeform = freeform
            kind = .opaque(o)
        } else {
            // A freeform whose guides this app cannot evaluate: kept whole.
            return _opaque(sp, label: "Freeform", transform, id: id)
        }

        // Fill and line: the shape's own, else its style's references.
        var fill: Color? = nil
        var fillStyle: SlideFill? = nil
        var fillScheme: String? = nil
        var outline: Color? = nil
        var outlineWidth = 0.75
        let style = sp.first("p:style")
        if spPr?.has("a:noFill") == true || sp["useBgFill"] == "1" {
            // (`useBgFill`: the shape is painted with the slide's background.)
            fill = nil
        } else if let f = spPr?.first("a:solidFill") {
            fill = colors.color(in: f)
            fillScheme = Self._accentSlot(f)
        } else if let g = spPr?.first("a:gradFill"), let gradient = PptxReader.gradient(g, colors: colors) {
            // A gradient: its middle colour stands for it (the theme gallery,
            // a save that regenerates the shape); drawn as itself. (One with
            // no stops at all — 63200's oval — is the style's fill, below.)
            let stops = gradient.stops.map(\.color)
            fill = stops.isEmpty ? gradient.color : stops[stops.count / 2]
            if gradient.stops.count >= 2 { fillStyle = gradient }
        } else if let b = spPr?.first("a:blipFill"), let blip = b.first("a:blip"), let rid = blip["r:embed"],
                  let rel = package.rels(part).first(where: { $0.id == rid }), !rel.external,
                  package.parts[rel.target] != nil {
            // A picture fill: drawn stretched within the outline.
            var f = SlideFill(image: images.attachment(rel.target, package))
            (f.imageAlpha, f.duotone) = PptxReader.blipEffects(blip, colors: colors)
            f.imageInset = PptxReader.stretchInset(b)
            fillStyle = f
        } else if spPr?.has("a:grpFill") == true {
            // The group's fill, which the group it is read from supplies.
            fill = nil
        } else if let ref = style?.first("a:fillRef"), ref["idx"] != "0" {
            // The shape style's fill (idx 0 is none), for any kind of shape:
            // the referred colour, through the theme's fill style when that
            // is a gradient (oox-gradient-multistep-transparency).
            fill = colors.color(in: ref)
            fillScheme = Self._accentSlot(ref)
            if let idx = ref["idx"].flatMap(Int.init), theme.fillStyles.indices.contains(idx - 1),
               theme.fillStyles[idx - 1].name == "a:gradFill" {
                var c = colors
                c.placeholder = fill
                if let gradient = PptxReader.gradient(theme.fillStyles[idx - 1], colors: c), gradient.stops.count >= 2 {
                    fillStyle = gradient
                }
            }
        }
        if let ln = spPr?.first("a:ln") {
            outlineWidth = ln["w"].flatMap(Double.init).map { $0 / Pptx.emu } ?? outlineWidth
            if ln.has("a:noFill") { outline = nil } else if let f = ln.first("a:solidFill") { outline = colors.color(in: f) }
            else if let gs = ln.first("a:gradFill")?.first("a:gsLst")?.all("a:gs"), !gs.isEmpty {
                // A gradient line by its first stop that shows — or no line,
                // when every stop is fully transparent (tdf149588's curve).
                let stops = gs.compactMap { colors.color(in: $0) }
                outline = stops.first { $0.alpha > 0 }
            }
            else if let ref = style?.first("a:lnRef"), ref["idx"] != "0" { outline = colors.color(in: ref) }
            // A line at alpha 0 is no line.
            if let o = outline, o.alpha == 0 { outline = nil }
        } else if let ref = style?.first("a:lnRef"), ref["idx"] != "0" {
            outline = colors.color(in: ref)
        }

        // A placeholder with no fill or line of its own takes its layout's,
        // then its master's (tdf95932: a green body from the master).
        let ownFillNames: Set<String> = ["a:noFill", "a:solidFill", "a:gradFill", "a:blipFill", "a:pattFill", "a:grpFill"]
        if ph != nil, !(spPr?.children.contains { ownFillNames.contains($0.name) } ?? false), style?.first("a:fillRef") == nil {
            for node in [inherited.layout, inherited.master] {
                guard let pr = node?.first("p:spPr") else { continue }
                if pr.has("a:noFill") { break }
                if let f = pr.first("a:solidFill") { fill = colors.color(in: f); fillScheme = Self._accentSlot(f); break }
                if let g = pr.first("a:gradFill"), let gradient = PptxReader.gradient(g, colors: colors) {
                    // The layout's gradient (tdf114848's title bar).
                    let stops = gradient.stops.map(\.color)
                    fill = stops.isEmpty ? gradient.color : stops[stops.count / 2]
                    if gradient.stops.count >= 2 { fillStyle = gradient }
                    break
                }
            }
        }
        if ph != nil, spPr?.first("a:ln") == nil, style?.first("a:lnRef") == nil {
            for node in [inherited.layout, inherited.master] {
                guard let ln = node?.first("p:spPr")?.first("a:ln") else { continue }
                if ln.has("a:noFill") { break }
                if let f = ln.first("a:solidFill") {
                    outline = colors.color(in: f)
                    outlineWidth = ln["w"].flatMap(Double.init).map { $0 / Pptx.emu } ?? outlineWidth
                }
                break
            }
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
        st.lineReduction = text.lineReduction
        st.insetsFollowFont = text.insetsFollowFont
        st.noWrap = text.noWrap
        st.flipH = xfrm?["flipH"] == "1"
        st.flipV = xfrm?["flipV"] == "1"
        st.fillsWithBackground = sp["useBgFill"] == "1"
        st.fillStyle = fillStyle
        st.invisible = hiddenByLayout
        // A diagram shape's text frame (`txXfrm`, from a SmartArt drawing):
        // the text sits in that box rather than the shape's.
        let txBox = sp.first("p:txXfrm").flatMap(_xfrmRect)
        if let txBox {
            let tr = transform?(txBox) ?? txBox
            st.insets = EdgeInsets(left: st.insets.left + (tr.left - frame.left), top: st.insets.top + (tr.top - frame.top),
                                   right: st.insets.right + (frame.right - tr.right),
                                   bottom: st.insets.bottom + (frame.bottom - tr.bottom))
        }
        if case .geometry(let preset) = kind, preset.rawValue != "rect", !preset.isLine {
            // A preset from its definition, at the shape's adjust values;
            // its text within the definition's text rectangle (an oval's
            // inscribed box, a pie's quarter) unless the shape has its own
            // text frame above. For the frame as placed — a group's child
            // is scaled by the group, and PowerPoint sizes the arrow's head
            // by the frame it ends up with (63200), not by the child's own
            // extent. (A diagram's callout header used to skip this for its
            // text frame, and the arrow filter then dropped it — tdf150789.)
            if let g = PresetGeometry.geometry(preset.rawValue, width: frame.width * Pptx.emu, height: frame.height * Pptx.emu,
                                               adjustments: PresetGeometry.adjustments(spPr?.first("a:prstGeom"))) {
                st.customPath = g
                if txBox == nil, let box = g.textRect {
                    st.insets = EdgeInsets(left: st.insets.left + box.left * frame.width,
                                           top: st.insets.top + box.top * frame.height,
                                           right: st.insets.right + (1 - box.right) * frame.width,
                                           bottom: st.insets.bottom + (1 - box.bottom) * frame.height)
                }
            }
        }
        // A placeholder with no geometry of its own takes its layout's or
        // master's (custgeom-placeholder: a notched ellipse from the layout).
        if ph != nil, spPr?.first("a:prstGeom") == nil, spPr?.first("a:custGeom") == nil {
            for node in [inherited.layout, inherited.master] {
                guard let pr = node?.first("p:spPr") else { continue }
                if let p = pr.first("a:prstGeom")?["prst"] {
                    if p != "rect" {
                        st.inheritedPreset = ShapePreset(rawValue: p)
                        st.customPath = PresetGeometry.geometry(p, width: frame.width * Pptx.emu, height: frame.height * Pptx.emu,
                                                                adjustments: PresetGeometry.adjustments(pr.first("a:prstGeom")))
                    }
                    break
                }
                if let geom = pr.first("a:custGeom") {
                    st.customPath = FreeformGeometry.parse(geom, width: frame.width * Pptx.emu, height: frame.height * Pptx.emu)
                    break
                }
            }
        }
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

    /// The picture a legacy VML drawing shows for shape `spid`
    /// (`<v:shape id="…"><v:imagedata o:relid="…"/>`): what an embedded
    /// object written before `p:pic` fallbacks displays. The drawing is
    /// read as text — VML is not always well-formed XML.
    private func _vmlImage(_ spid: String) -> ImageAttachment? {
        for rel in package.rels(part) where rel.kind == "vmlDrawing" && !rel.external {
            guard let data = package.parts[rel.target], let vml = String(data: data, encoding: .utf8),
                  let shape = vml.rangeOfSubstring("id=\"\(spid)\""),
                  let end = vml.rangeOfSubstring("</v:shape>", in: shape.upperBound ..< vml.endIndex) else { continue }
            let body = vml[shape.upperBound ..< end.lowerBound]
            for key in ["o:relid=\"", "r:id=\"", "r:pict=\""] {
                guard let at = String(body).rangeOfSubstring(key) else { continue }
                let rest = String(body)[at.upperBound...]
                guard let close = rest.firstIndex(of: "\"") else { continue }
                let rid = String(rest[..<close])
                if let target = package.rels(rel.target).first(where: { $0.id == rid }), !target.external,
                   package.parts[target.target] != nil {
                    return images.attachment(target.target, package)
                }
            }
        }
        return nil
    }

    private func _picture(_ el: XNode, _ transform: ((Rect) -> Rect)?, id: () -> Int) -> ShapeState? {
        // Audio and video are a `p:pic` too — the poster frame, with the
        // media hung on `p:nvPr` (`a:audioFile`/`a:videoFile`, `p14:media`)
        // and a `p:timing` tree that plays it. Modelled as a picture, the
        // media relationships would be dropped under a timing tree that
        // still calls them, and PowerPoint repairs the slide. Kept whole.
        if let nv = el.first("p:nvPicPr")?.first("p:nvPr"),
           nv.children.contains(where: { ["a:audioFile", "a:videoFile", "a:quickTimeFile", "a:wavAudioFile"].contains($0.name) }) {
            // Drawn as its poster frame (the pic's own picture), or black
            // where it has none, as PowerPoint shows a video at rest.
            guard var o = _opaque(el, label: "Media", transform, id: id) else { return nil }
            if case .opaque(var obj) = o.kind {
                var poster = ShapeState(id: id(), name: "Poster", kind: .geometry(.rect), frame: o.frame, rotation: 0,
                                        fill: Color(0xFF000000), outline: nil, outlineWidth: 0, anchor: .top,
                                        insets: EdgeInsets(left: 0, top: 0, right: 0, bottom: 0), prompt: nil, text: nil,
                                        font: nil, size: 18, color: Color(0xFF000000), listIndent: 18)
                if let rid = el.first("p:blipFill")?.first("a:blip")?["r:embed"],
                   let target = package.rels(part).first(where: { $0.id == rid }), !target.external,
                   package.parts[target.target] != nil {
                    poster.kind = .picture(images.attachment(target.target, package))
                    poster.fill = nil
                }
                obj.rendering = [poster]
                o.kind = .opaque(obj)
            }
            return o
        }
        // A picture in a placeholder (`p:ph`) may leave its frame to the
        // layout's (`<p:spPr/>`): the inherited placeholder says where.
        var own = el.first("p:spPr")?.first("a:xfrm").flatMap(_xfrmRect)
        if own == nil, let ph = _ph(el) {
            let inherited = _inherited(ph)
            for node in [inherited.layout, inherited.master] {
                if let x = node?.first("p:spPr")?.first("a:xfrm"), let r = _xfrmRect(x) { own = r; break }
            }
        }
        guard let rid = el.first("p:blipFill")?.first("a:blip")?["r:embed"],
              let target = package.rels(part).first(where: { $0.id == rid }), !target.external,
              package.parts[target.target] != nil,
              var frame = own else {
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
        var s = ShapeState(id: id(), name: el.first("p:nvPicPr")?.first("p:cNvPr")?["name"] ?? "Picture",
                           kind: .picture(image), frame: frame, rotation: rotation, fill: nil, outline: nil,
                           outlineWidth: 0, anchor: .top, insets: EdgeInsets(left: 0, top: 0, right: 0, bottom: 0),
                           prompt: nil, text: nil, font: nil, size: 18, color: Color(0xFF000000), listIndent: 18,
                           crop: crop)
        // Mirrored, and cropped to a shape (an ellipse, rounded corners).
        let xfrm = el.first("p:spPr")?.first("a:xfrm")
        s.flipH = xfrm?["flipH"] == "1"
        s.flipV = xfrm?["flipV"] == "1"
        if let prst = el.first("p:spPr")?.first("a:prstGeom")?["prst"], prst != "rect" {
            s.pictureGeometry = ShapePreset(rawValue: prst)
        }
        if let blip = el.first("p:blipFill")?.first("a:blip") {
            (s.pictureAlpha, s.pictureDuotone) = PptxReader.blipEffects(blip, colors: colors)
        }
        if let b = el.first("p:blipFill") { s.pictureInset = PptxReader.stretchInset(b) }
        // A fill of its own, behind the picture (showing through its
        // transparent parts and around one padded by a negative crop).
        if let pr = el.first("p:spPr") {
            if let f = pr.first("a:solidFill"), let c = colors.color(in: f) {
                s.fillStyle = SlideFill(color: c)
            } else if let g = pr.first("a:gradFill"), let gradient = PptxReader.gradient(g, colors: colors), gradient.stops.count >= 2 {
                s.fillStyle = gradient
            }
        }
        // The element too: written back while the picture is unchanged.
        s.sourceXML = PptxXML.serialize(el)
        s.sourcePart = part
        s.keptPicture = KeptPicture(imageId: image.id, crop: crop, rotation: rotation)
        return s
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
        // No style id at all draws as "No Style, Table Grid" does.
        let plain = styleId.isEmpty || ["{2D5ABB26-0587-4C30-8999-92F81FD0307C}", "{5940675A-B579-460E-94D1-54222C63F5DA}"].contains(styleId)
        var base = LevelStyle.paragraph(defaults?.first("a:lvl1pPr"), colors)
        // The style the id names, when the deck defines it: the look of the
        // whole table, its header row, bands, and (when the table's flags
        // ask) its first and last columns and last row.
        let style = plain ? nil : tableStyles[styleId]
        let whole = style.flatMap { _tablePart($0, "a:wholeTbl") }
        let firstRowPart = firstRow ? style.flatMap { _tablePart($0, "a:firstRow") } : nil
        let lastRowPart = pr?["lastRow"] == "1" ? style.flatMap { _tablePart($0, "a:lastRow") } : nil
        let firstColPart = pr?["firstCol"] == "1" ? style.flatMap { _tablePart($0, "a:firstCol") } : nil
        let lastColPart = pr?["lastCol"] == "1" ? style.flatMap { _tablePart($0, "a:lastCol") } : nil
        if let c = whole?.textColor { base.color = c }
        let rowCount = tbl.all("a:tr").count
        var paragraphs: [RichParagraph] = []
        for (r, tr) in tbl.all("a:tr").enumerated() {
            var column = 0
            let columnCount = tr.all("a:tc").count
            for (c, tc) in tr.all("a:tc").enumerated() {
                defer { column += 1 }
                if tc["hMerge"] == "1" || tc["vMerge"] == "1" { continue }
                var cell = CellRef(table: tableId, row: r, column: column,
                                   span: tc["gridSpan"].flatMap(Int.init) ?? 1, rowSpan: tc["rowSpan"].flatMap(Int.init) ?? 1)
                // The style's regional looks, the later ones over the earlier
                // (a corner cell of the header row looks like the header).
                var regional: [TablePartStyle] = []
                if c == 0, let p = firstColPart { regional.append(p) }
                if c == columnCount - 1, let p = lastColPart { regional.append(p) }
                if r == rowCount - 1, r > 0, let p = lastRowPart { regional.append(p) }
                if r == 0, let p = firstRowPart { regional.append(p) }
                if let f = regional.compactMap(\.fill).last, r > 0 || firstRowPart == nil { cell.fill = f }
                // The cell's margins: PowerPoint's 0.1" sides and 0.05" top
                // and bottom unless the cell says otherwise. Its own fill
                // and edge lines (`a:tcPr`) go over the style's.
                let tcPr = tc.first("a:tcPr")
                func margin(_ name: String, _ fallback: Double) -> Double {
                    tcPr?[name].flatMap(Double.init).map { $0 / Pptx.emu } ?? fallback
                }
                cell.padding = EdgeInsets(left: margin("marL", 7.2), top: margin("marT", 3.6),
                                          right: margin("marR", 7.2), bottom: margin("marB", 3.6))
                if let tcPr {
                    switch tcPr["anchor"] { case "ctr": cell.verticalAlign = "center"; case "b": cell.verticalAlign = "bottom"; default: break }
                    switch tcPr["vert"] { case "vert", "eaVert": cell.textDirection = .down; case "vert270": cell.textDirection = .up; default: break }
                    if let f = tcPr.first("a:solidFill") {
                        cell.fill = colors.color(in: f)
                    } else if let g = tcPr.first("a:gradFill") {
                        let stops = g.first("a:gsLst")?.all("a:gs").compactMap { colors.color(in: $0) } ?? []
                        if !stops.isEmpty { cell.fill = stops[stops.count / 2] }
                    } else if tcPr.has("a:noFill") {
                        // The cell says "no fill" over the style's band or
                        // header (tdf164936's empty box).
                        cell.fill = Color(0x00000000)
                    }
                    func line(_ tag: String) -> CellRef.CellLine? {
                        guard let ln = tcPr.first(tag) else { return nil }
                        if ln.has("a:noFill") { return CellRef.CellLine.hidden }
                        let width = ln["w"].flatMap(Double.init).map { $0 / Pptx.emu } ?? 1
                        if let f = ln.first("a:solidFill") {
                            // Fully transparent is hidden, not the style's rule.
                            let c = colors.color(in: f)
                            if let c, c.alpha == 0 { return CellRef.CellLine.hidden }
                            return CellRef.CellLine(width: width, color: c)
                        }
                        if let g = ln.first("a:gradFill"), let gs = g.first("a:gsLst")?.all("a:gs").first {
                            return CellRef.CellLine(width: width, color: colors.color(in: gs))
                        }
                        return nil   // a width alone: the style's line, as it is
                    }
                    cell.borders.left = line("a:lnL")
                    cell.borders.right = line("a:lnR")
                    cell.borders.top = line("a:lnT")
                    cell.borders.bottom = line("a:lnB")
                }
                // The header row's text is light and bold in every styled
                // table PowerPoint offers; a style the deck defines says
                // exactly what (Light Style 2's header is dark text, no fill).
                var look = base
                if style != nil {
                    for p in regional {
                        if let b = p.bold { look.bold = b }
                        if let c = p.textColor { look.color = c }
                    }
                } else if r == 0 && firstRow && !plain {
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
                            color: s.color ?? colors.scheme("tx1"), letterSpacing: s.spc.flatMap { $0 != 0 ? $0 : nil })))
                    }
                    var style = RichParagraphStyle(spaceAfter: 0, lineSpacing: 1.0)
                    switch level.algn { case "ctr": style.alignment = .center; case "r": style.alignment = .right; default: break }
                    // A bulleted cell paragraph. In a cell the layout puts
                    // the text at `indentLeft` and the bullet in the 18 pt
                    // slot before it (no per-level indent), so the text edge
                    // is the file's, and at least that slot: PowerPoint's
                    // unsaid default is the bullet at 0 with the text right
                    // after it, which this approximates.
                    switch level.bullet {
                    case .char?, .number?:
                        style.list = level.bullet == .char ? .bullet : .numbered
                        style.listLevel = p.first("a:pPr")?["lvl"].flatMap(Int.init) ?? 0
                        style.indentLeft = max(18, level.marL ?? 0)
                    default:
                        break
                    }
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
        // The rows' own heights (`a:tr h`), as minimums: PowerPoint keeps a
        // row that tall however little is in it.
        let rowHeights = tbl.all("a:tr").map { ($0["h"].flatMap(Double.init) ?? 0) / Pptx.emu }
        let accent = theme.colors["accent1"] ?? Color(0xFF4472C4)
        var ts = plain
            ? TableStyle(borders: styleId.isEmpty || styleId.hasPrefix("{5940675A"), headerRow: false, borderColor: colors.scheme("tx1"))
            : TableStyle(borders: true, headerRow: firstRow, headerFill: accent,
                         bandFill: banded ? DeckController.tint(accent, 0.40) : nil,
                         bandAltFill: banded ? DeckController.tint(accent, 0.20) : nil,
                         borderColor: Color(0xFFFFFFFF))
        if let style {
            // As the deck's style has it: the header's own fill (none is
            // none, not a tint), band 1 and band 2 over the whole table's
            // fill — which is the table background (`a:tblBg`, a themed
            // style's gradient, by its middle colour) when the cells say
            // none — and the whole table's rules.
            let b1 = _tablePart(style, "a:band1H"), b2 = _tablePart(style, "a:band2H")
            var under = whole?.fill
            if under == nil || under == Color(0x00000000), let bg = style.first("a:tblBg") {
                if let ref = bg.first("a:fillRef"), ref["idx"] != "0" {
                    if let idx = ref["idx"].flatMap(Int.init), theme.fillStyles.indices.contains(idx - 1),
                       theme.fillStyles[idx - 1].name == "a:gradFill" {
                        var c = colors
                        c.placeholder = colors.color(in: ref)
                        let stops = theme.fillStyles[idx - 1].first("a:gsLst")?.all("a:gs").compactMap { c.color(in: $0) } ?? []
                        under = stops.isEmpty ? c.placeholder : stops[stops.count / 2]
                    } else {
                        under = colors.color(in: ref)
                    }
                } else if let f = bg.first("a:fill") {
                    under = f.first("a:solidFill").flatMap(colors.color(in:))
                }
            }
            func over(_ fill: Color?) -> Color? {
                // A translucent band over the table's own fill.
                guard let fill, let under, (fill.value >> 24) & 0xFF < 0xFF else { return fill ?? under }
                return DeckController.blend(fill, over: under)
            }
            ts.headerFill = firstRow ? (over(firstRowPart?.fill) ?? Color(0x00000000)) : nil
            ts.bandFill = banded ? over(b1?.fill) : under
            ts.bandAltFill = banded ? over(b2?.fill) : under
            if let b = whole?.borders { ts.borders = b }
            if let c = whole?.borderColor { ts.borderColor = c }
        }
        for (r, h) in rowHeights.enumerated() where h > 0 { ts.rowHeights[r] = h }
        doc.tableStyles[tableId] = ts
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
        // The chart area's own picture or gradient fill (chart-picture-bg),
        // drawn under the plot.
        if let pr = space.first("c:spPr") {
            if let b = pr.first("a:blipFill"), let blip = b.first("a:blip"), let rid = blip["r:embed"],
               let img = package.rels(rel.target).first(where: { $0.id == rid }), !img.external,
               package.parts[img.target] != nil {
                var f = SlideFill(image: images.attachment(img.target, package))
                (f.imageAlpha, f.duotone) = PptxReader.blipEffects(blip, colors: colors)
                st.fillStyle = f
            } else if let f = pr.first("a:solidFill"), let c = colors.color(in: f) {
                st.fillStyle = SlideFill(color: c)
            }
        }
        return st
    }

    /// A SmartArt's drawing part (`dsp:drawing`, reached from the data
    /// part's `dsp:dataModelExt relId`) as shapes at `frame`: its elements
    /// are DrawingML shapes under another prefix, so they read as `p:` ones.
    private func _diagram(_ el: XNode, frame: Rect, id: () -> Int) -> [ShapeState] {
        guard let relIds = el.descendant("dgm:relIds"), let dm = relIds["r:dm"],
              let dataPart = package.rels(part).first(where: { $0.id == dm })?.target,
              let data = package.xml(dataPart) else { return [] }
        func renamed(_ n: XNode) -> XNode {
            let name = n.name.hasPrefix("dsp:") ? "p:" + n.name.dropFirst(4) : n.name
            let c = XNode(name: name, attrs: n.attrs)
            c.text = n.text
            c.children = n.children.map(renamed)
            return c
        }
        func related(_ key: String) -> (String, XNode)? {
            guard let rid = relIds[key], let p = package.rels(part).first(where: { $0.id == rid })?.target,
                  let x = package.xml(p) else { return nil }
            return (p, x)
        }
        var tree: XNode? = nil
        var drawingPart = part
        if let relId = data.descendant("dsp:dataModelExt")?["relId"],
           let dp = package.rels(part).first(where: { $0.id == relId })?.target,
           let drawing = package.xml(dp), let t = drawing.first("dsp:spTree"),
           t.children.contains(where: { $0.name == "dsp:sp" || $0.name == "dsp:grpSp" }) {
            // PowerPoint's own drawing of the diagram. (LibreOffice writes
            // the part with nothing in it; that counts as none.)
            tree = renamed(t)
            drawingPart = dp
            // The drawing's `fontRef` is the quick style's, whatever the
            // colour scheme says: a white node of an outlined scheme
            // (accent3_1) still carries `lt1` there, and PowerPoint, which
            // lays the diagram out afresh, shows its text in the scheme's
            // own text colour (`txFillClrLst` of the node's style label) —
            // dark. Across the corpus the two disagree only where that list
            // names a colour, and an empty list leaves the fontRef to rule;
            // so a named one replaces it (tdf93830's text was white on white).
            if let scheme = related("r:cs")?.1 {
                var labels: [String: String] = [:]
                for pt in data.first("dgm:ptLst")?.all("dgm:pt") ?? [] {
                    if let id = pt["modelId"], let l = pt.first("dgm:prSet")?["presStyleLbl"] { labels[id] = l }
                }
                var textColors: [String: XNode] = [:]
                for l in scheme.all("dgm:styleLbl") {
                    if let name = l["name"], let c = l.first("dgm:txFillClrLst")?.children.first { textColors[name] = c }
                }
                for sp in tree?.all("p:sp") ?? [] {
                    guard let id = sp["modelId"], let label = labels[id], let color = textColors[label],
                          let font = sp.first("p:style")?.first("a:fontRef") else { continue }
                    font.children = [color]
                }
            }
        } else if let (_, layoutDef) = related("r:lo") {
            // No drawing (a deck LibreOffice saved): laid out here from the
            // data and the layout definition.
            tree = DiagramLayout.render(data: data, layout: layoutDef, colors: related("r:cs")?.1, style: related("r:qs")?.1,
                                        frame: Rect.fromLTWH(0, 0, frame.width, frame.height))
        }
        guard let tree else { return [] }
        // The diagram's own background and outline (`dgm:bg`, `dgm:whole`
        // in the data): a rectangle the size of the frame, behind everything
        // — smartart-background's green between its boxes.
        let fillNames: Set<String> = ["a:solidFill", "a:gradFill", "a:blipFill", "a:pattFill"]
        let bgFill = data.first("dgm:bg")?.children.first { fillNames.contains($0.name) }
        let wholeLine = data.first("dgm:whole")?.first("a:ln")
        if bgFill != nil || wholeLine != nil {
            let sp = XNode(name: "p:sp", attrs: [:])
            let nv = XNode(name: "p:nvSpPr", attrs: [:])
            nv.children = [XNode(name: "p:cNvPr", attrs: ["id": "0", "name": "diagram background"]),
                           XNode(name: "p:cNvSpPr", attrs: [:]), XNode(name: "p:nvPr", attrs: [:])]
            let spPr = XNode(name: "p:spPr", attrs: [:])
            let xfrm = XNode(name: "a:xfrm", attrs: [:])
            xfrm.children = [XNode(name: "a:off", attrs: ["x": "0", "y": "0"]),
                             XNode(name: "a:ext", attrs: ["cx": String(Int(frame.width * Pptx.emu)),
                                                          "cy": String(Int(frame.height * Pptx.emu))])]
            let geom = XNode(name: "a:prstGeom", attrs: ["prst": "rect"])
            geom.children = [XNode(name: "a:avLst", attrs: [:])]
            let line = wholeLine ?? XNode(name: "a:ln", attrs: [:])
            if wholeLine == nil { line.children = [XNode(name: "a:noFill", attrs: [:])] }
            spPr.children = [xfrm, geom, bgFill ?? XNode(name: "a:noFill", attrs: [:]), line]
            sp.children = [nv, spPr]
            tree.children.insert(sp, at: 0)
        }
        let ctx = SlideContext(package: package, part: drawingPart, slide: slide, layout: layout, master: master,
                               colors: colors, theme: theme, defaults: defaults, slideSize: slideSize, images: images)
        var out: [ShapeState] = []
        ctx.shapes(in: tree, transform: { r in r.shift(Offset(frame.left, frame.top)) }, into: &out, id: id)
        // A preset this app has no outline for is drawn as a box, which
        // serves for the rounded and snipped rectangles diagrams favour but
        // not for a gear (gear6, gear9): those are left out.
        // The drawing part caches one layout of the text; PowerPoint fits it
        // to the shapes afresh, so every text shrinks to fit here too.
        for i in out.indices where out[i].text != nil { out[i].autofit = true }
        return out.filter { s in
            if case .geometry(let p) = s.kind {
                // Round things and curved arrows look nothing like their box.
                let name = p.rawValue
                if SlidePainter.drawablePresets.contains(name) || s.customPath != nil { return true }
                for part in ["gear", "Arrow", "arc", "Arc", "pie", "chord", "donut", "moon", "sun", "cloud", "heart",
                             "lightning", "Circle", "ellipse"] where name.containsSubstring(part) { return false }
                return true
            }
            // A freeform whose guides this app cannot evaluate would be a
            // labelled box here: nothing is better.
            if case .opaque(let o) = s.kind, o.freeform == nil { return false }
            return true
        }
    }

    /// One region of a table style (`a:wholeTbl`, `a:firstRow`, `a:band1H`…):
    /// its cells' fill and rules, and its text's colour and weight.
    private struct TablePartStyle {
        var fill: Color? = nil
        var textColor: Color? = nil
        var bold: Bool? = nil
        var borders: Bool? = nil
        var borderColor: Color? = nil
    }

    private func _tablePart(_ style: XNode, _ name: String) -> TablePartStyle? {
        guard let part = style.first(name) else { return nil }
        var r = TablePartStyle()
        if let tc = part.first("a:tcStyle") {
            if let f = tc.first("a:fill") {
                if let s = f.first("a:solidFill") {
                    r.fill = colors.color(in: s)
                } else if let g = f.first("a:gradFill") {
                    // Its middle colour stands for the gradient.
                    let stops = g.first("a:gsLst")?.all("a:gs").compactMap { colors.color(in: $0) } ?? []
                    if !stops.isEmpty { r.fill = stops[stops.count / 2] }
                } else if f.has("a:noFill") {
                    r.fill = Color(0x00000000)
                }
            } else if let ref = tc.first("a:fillRef"), ref["idx"] != "0" {
                r.fill = colors.color(in: ref)
            }
            if let bdr = tc.first("a:tcBdr"), !bdr.children.isEmpty {
                var visible = false
                for side in ["a:insideH", "a:insideV", "a:left", "a:right", "a:top", "a:bottom"] {
                    if let ref = bdr.first(side)?.first("a:lnRef") {
                        // The theme's line style in the referred colour.
                        if ref["idx"] == "0" { continue }
                        visible = true
                        if r.borderColor == nil { r.borderColor = colors.color(in: ref) }
                        continue
                    }
                    guard let ln = bdr.first(side)?.first("a:ln") else { continue }
                    if ln.has("a:noFill") { continue }
                    visible = true
                    if r.borderColor == nil, let f = ln.first("a:solidFill") { r.borderColor = colors.color(in: f) }
                }
                r.borders = visible
            }
        }
        if let tx = part.first("a:tcTxStyle") {
            r.textColor = colors.color(in: tx)
            switch tx["b"] { case "on": r.bold = true; case "off": r.bold = false; default: break }
        }
        return r
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
        var lineReduction = 0.0
        /// The insets are fractions of the font size (a diagram's margins)
        /// and shrink with it.
        var insetsFollowFont = false
        /// `bodyPr wrap="none"`.
        var noWrap = false
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
        } else if ["title", "ctrTitle", "body", "subTitle", "obj"].contains(ph?["type"] ?? "obj") {
            // And the reverse: a title or body draws from the master's title
            // and body styles alone. The presentation's default is for the
            // other objects — alterman_security's says i="1" at every level,
            // and PowerPoint shows its bodies upright.
            layers.removeLast()
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
        let reduction = (body?.first("a:bodyPr")?.first("a:normAutofit")?["lnSpcReduction"].flatMap(Double.init)).map { $0 / 100000 } ?? 0
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
        // The list slot the layout indents by, per level: the text edge
        // level 0 declares (marL), or — for a shape whose level 0 has none, a
        // SmartArt's text — the hang of its first bulleted paragraph, so the
        // bullet has a slot to be drawn in rather than none.
        var listIndent = level0.marL.flatMap { $0 > 0 ? $0 : nil }
        if listIndent == nil {
            for p in body?.all("a:p") ?? [] {
                guard let pPr = p.first("a:pPr"), pPr.has("a:buChar") || pPr.has("a:buAutoNum") else { continue }
                if let ind = pPr["indent"].flatMap(Double.init), ind < 0 { listIndent = -ind / Pptx.emu; break }
                if let m = pPr["marL"].flatMap(Double.init), m > 0 {
                    listIndent = m / Pptx.emu / Double((pPr["lvl"].flatMap(Int.init) ?? 0) + 1)
                    break
                }
            }
        }
        let shapeIndent = listIndent ?? 18
        var paragraphs: [RichParagraph] = []
        let allParagraphs = body?.all("a:p") ?? []
        for p in allParagraphs {
            let pPr = p.first("a:pPr")
            let lvl = pPr?["lvl"].flatMap(Int.init) ?? 0
            let level = styled(LevelStyle.paragraph(pPr, colors).filled(from: _level(lvl, shapeList: list, ph: ph, inherited: inherited)), lvl, pPr)
            // What a percentage of spacing is a percentage of: the size the
            // paragraph's runs are actually set in (a SmartArt label is 31 pt
            // by its runs under a level that says nothing), else the level's.
            let runSizes = p.all("a:r").compactMap { $0.first("a:rPr")?["sz"].flatMap(Double.init).map { $0 / 100 } }
            let size = runSizes.max() ?? level.size ?? 18
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
            // A percentage after, as before: of the line, taken as 1.2 of the
            // size — but not under the last paragraph, where PowerPoint adds
            // nothing: counted there, a one-line SmartArt label (35% after,
            // every one) measured taller than its box and was shrunk to fit.
            if level.afterPoints == nil, let pct = level.afterPercent, p !== allParagraphs.last {
                style.spaceAfter = pct * size * 1.2
            }
            switch level.bullet {
            case .char?, .number?:
                style.list = level.bullet == .char ? .bullet : .numbered
                style.listLevel = lvl
                if level.bullet == .char { style.bulletText = level.bulletGlyph }
                style.bulletColor = level.bulletColor
                style.bulletScale = level.bulletScale
                // The file's own text edge (marL) and bullet offset (indent):
                // the text placed where the file puts it, both written back
                // as read. The layout indents a list by the shape's list
                // indent per level; indentLeft carries the difference.
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
                if let spc = s.spc, spc != 0 { cs.letterSpacing = spc }
                if s.caps == "all" { cs.caps = true } else if s.caps == "small" { cs.smallCaps = true }
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
                        listIndent: shapeIndent,
                        autofit: fitRule == "a:normAutofit", fontScale: fitRule == "a:normAutofit" ? scale : 1,
                        lineReduction: fitRule == "a:normAutofit" ? min(1, max(0, reduction)) : 0,
                        insetsFollowFont: body?.first("a:bodyPr")?["starling:insScale"] == "1",
                        noWrap: bodies.compactMap { $0?["wrap"] }.first == "none")
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
