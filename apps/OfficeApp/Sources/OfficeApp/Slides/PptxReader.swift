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
import OfficeText
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
    /// The complex-script faces (`a:cs`), and each script's own
    /// (`a:font script="Hebr"`) for when that is empty: what Hebrew,
    /// Arabic and Thai letters are set in.
    var majorScript: [String: String] = [:]
    var minorScript: [String: String] = [:]
    /// The format scheme's fill styles (`a:fillStyleLst`), which a shape's
    /// style refers to by index with its own colour as `phClr`.
    var fillStyles: [XNode] = []
    /// Its effect styles (`a:effectStyleLst`), referred to the same way.
    var effectStyles: [XNode] = []
    /// Its line styles' widths (`a:lnStyleLst`, points): a shape whose
    /// style refers to one and whose own line names no width is that wide.
    var lineWidths: [Double] = []
    /// And their colours' modifiers on the shape's own (`phClr`): the
    /// Office 2007 theme's first line is its colour shaded to 95% and
    /// saturated 105% — shapes' connector prints 4A7EBB for 4F81BD.
    var lineColorMods: [XNode?] = []
    /// And their joins (`PptxReader.join`).
    var lineJoins: [String?] = []
    /// And their caps (`a:ln cap`).
    var lineCaps: [String?] = []

    init(_ root: XNode?) {
        guard let root, let elements = root.descendant("a:themeElements") else {
            // No theme part (a damaged file: clusterfuzz 4986's master
            // names one that is not there): PowerPoint's own Office theme,
            // whose grey accent 3 and orange accent 2 its boxes show.
            let office: [String: Int64] = ["dk1": 0x000000, "lt1": 0xFFFFFF, "dk2": 0x44546A, "lt2": 0xE7E6E6,
                                           "accent1": 0x4472C4, "accent2": 0xED7D31, "accent3": 0xA5A5A5,
                                           "accent4": 0xFFC000, "accent5": 0x5B9BD5, "accent6": 0x70AD47,
                                           "hlink": 0x0563C1, "folHlink": 0x954F72]
            for (k, v) in office { colors[k] = Color(0xFF00_0000 | v) }
            lineWidths = [0.5, 1, 1.5]
            return
        }
        fillStyles = elements.first("a:fmtScheme")?.first("a:fillStyleLst")?.children ?? []
        effectStyles = elements.first("a:fmtScheme")?.first("a:effectStyleLst")?.children ?? []
        lineWidths = (elements.first("a:fmtScheme")?.first("a:lnStyleLst")?.children ?? []).map {
            ($0["w"].flatMap(Double.init) ?? 9525) / 12700
        }
        lineJoins = (elements.first("a:fmtScheme")?.first("a:lnStyleLst")?.children ?? []).map { PptxReader.join($0) }
        lineCaps = (elements.first("a:fmtScheme")?.first("a:lnStyleLst")?.children ?? []).map { $0["cap"] }
        lineColorMods = (elements.first("a:fmtScheme")?.first("a:lnStyleLst")?.children ?? []).map {
            $0.first("a:solidFill")?.first("a:schemeClr").flatMap { $0["val"] == "phClr" ? $0 : nil }
        }
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
            for (key, var table) in [("a:majorFont", [String: String]()), ("a:minorFont", [:])] {
                guard let font = fonts.first(key) else { continue }
                for f in font.all("a:font") { if let k = f["script"], let t = f["typeface"], !t.isEmpty { table[k] = t } }
                if let t = font.first("a:cs")?["typeface"], !t.isEmpty { table["cs"] = t }
                if key == "a:majorFont" { majorScript = table } else { minorScript = table }
            }
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
    func color(in fill: XNode) -> Color? { color(in: fill, duotone: false) }

    /// A shape style's line colour (`a:lnRef`): its own, through the
    /// modifiers the theme's line style puts on it.
    func lineColor(in ref: XNode) -> Color? {
        guard let base = color(in: ref) else { return nil }
        guard let idx = ref["idx"].flatMap(Int.init), theme.lineColorMods.indices.contains(idx - 1),
              let mods = theme.lineColorMods[idx - 1], !mods.children.isEmpty else { return base }
        return Self.modify(base, mods)
    }

    /// The same, for one of a picture's duotone pair.
    func color(in fill: XNode, duotone: Bool) -> Color? {
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
            return Self.modify(b, child, duotone: duotone)
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
    static func modify(_ c: Color, _ node: XNode, duotone: Bool = false) -> Color {
        var r = Double((c.value >> 16) & 0xFF) / 255, g = Double((c.value >> 8) & 0xFF) / 255, b = Double(c.value & 0xFF) / 255
        var alpha = 1.0
        // Between `a:gamma` and `a:invGamma` (how a converted .ppt spells
        // its shades) a tint or shade works on the sRGB values as they are.
        var gammaShifted = false
        let kids = node.children
        for (k, m) in kids.enumerated() {
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
                // A tint of a colour that a strong saturation boost follows
                // straight after mixes in sRGB: the Office 2007 themes' gradient fills
                // (tint 50%, satMod 300%) are PowerPoint's to a level so,
                // and a third too pale in linear light (customGeo's orange
                // diagram boxes). A milder boost's stays linear (GeomLec1's
                // blue band, tint 86%, satMod 149%), as do a grey's (its
                // dark backgrounds, which the boost leaves grey) and a
                // picture's duotone (Treck's background).
                let sRGBTint = tint && !duotone && _hsl(r, g, b).1 > 0.1
                    && kids.indices.contains(k + 1) && kids[k + 1].name == "a:satMod"
                    && (kids[k + 1]["val"].flatMap(Double.init) ?? 0) >= 155000
                func apply(_ c: Double) -> Double {
                    if gammaShifted || sRGBTint { return tint ? 1 - (1 - c) * v : c * v }
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
    /// `a:cs`: the face for complex-script (Hebrew, Arabic, Thai) text.
    var csFont: String?
    var color: Color?
    var baseline: Double?
    /// Character spacing in points (`spc`, hundredths of a point).
    var spc: Double?
    /// `kern`: kerning from this size up, in points (0 for none).
    var kern: Double?
    /// `a:effectLst` on the run: its outer shadow (nil inside a list
    /// that has none), and whether the list was there at all.
    var shadow: CharShadow?
    var shadowSet = false
    /// `a:highlight`: the run's text highlight colour.
    var highlight: Color?
    /// `a:buBlip`: the picture bullet, resolved from the part it is in.
    var bulletPicture: ImageAttachment?
    /// `a:buAutoNum`'s scheme ("arabicPeriod", "alphaLcParenR"…) and
    /// `startAt`.
    var autoNumType: String?
    var autoNumStart: Int?
    /// `a:tabLst` (points from the text's left edge) and `defTabSz`.
    var tabs: [TabStop]?
    var defTab: Double?

    func filled(from lower: LevelStyle) -> LevelStyle {
        var s = self
        s.algn = s.algn ?? lower.algn
        s.marL = s.marL ?? lower.marL
        s.indent = s.indent ?? lower.indent
        if s.lineMultiple == nil && s.linePoints == nil { s.lineMultiple = lower.lineMultiple; s.linePoints = lower.linePoints }
        if s.beforePoints == nil && s.beforePercent == nil { s.beforePoints = lower.beforePoints; s.beforePercent = lower.beforePercent }
        if s.afterPoints == nil && s.afterPercent == nil { s.afterPoints = lower.afterPoints; s.afterPercent = lower.afterPercent }
        s.bullet = s.bullet ?? lower.bullet
        if s.autoNumType == nil { s.autoNumType = lower.autoNumType; s.autoNumStart = s.autoNumStart ?? lower.autoNumStart }
        if s.bulletChar == nil { s.bulletChar = lower.bulletChar; s.bulletFont = s.bulletFont ?? lower.bulletFont; s.bulletPicture = lower.bulletPicture }
        if s.bulletColor == nil, !s.bulletColorFollows { s.bulletColor = lower.bulletColor; s.bulletColorFollows = lower.bulletColorFollows }
        if s.bulletScale == nil, !s.bulletSizeFollows { s.bulletScale = lower.bulletScale; s.bulletSizeFollows = lower.bulletSizeFollows }
        s.caps = s.caps ?? lower.caps
        s.size = s.size ?? lower.size
        s.bold = s.bold ?? lower.bold
        s.italic = s.italic ?? lower.italic
        s.underline = s.underline ?? lower.underline
        s.strike = s.strike ?? lower.strike
        s.font = s.font ?? lower.font
        s.csFont = s.csFont ?? lower.csFont
        s.color = s.color ?? lower.color
        s.baseline = s.baseline ?? lower.baseline
        s.spc = s.spc ?? lower.spc
        s.kern = s.kern ?? lower.kern
        if !s.shadowSet { s.shadow = lower.shadow; s.shadowSet = lower.shadowSet }
        s.highlight = s.highlight ?? lower.highlight
        s.tabs = s.tabs ?? lower.tabs
        s.defTab = s.defTab ?? lower.defTab

        return s
    }

    /// A `a:lvlNpPr` / `a:pPr` element, with its `a:defRPr`.
    static func paragraph(_ p: XNode?, _ colors: ColorContext, picture: ((String) -> ImageAttachment?)? = nil) -> LevelStyle {
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
        if let n = p.first("a:buAutoNum") {
            s.bullet = .number
            s.autoNumType = n["type"] ?? "arabicPeriod"
            s.autoNumStart = n["startAt"].flatMap(Int.init)
        }
        // A picture bullet (`a:buBlip`): a list paragraph whose marker is
        // not drawn yet — its text where a bullet's is, not hung out to
        // the left as an unbulleted paragraph's first line is.
        if let blip = p.first("a:buBlip") {
            s.bullet = .char
            s.bulletChar = "\u{200B}"
            s.bulletPicture = blip.first("a:blip")?["r:embed"].flatMap { picture?($0) }
        }
        s.defTab = p["defTabSz"].flatMap(Double.init).map { $0 / Pptx.emu }
        if let list = p.first("a:tabLst") {
            s.tabs = list.all("a:tab").compactMap { t in
                guard let pos = t["pos"].flatMap(Double.init) else { return nil }
                let align: TabStop.Alignment
                switch t["algn"] { case "ctr": align = .center; case "r": align = .right; case "dec": align = .decimal; default: align = .left }
                return TabStop(position: pos / Pptx.emu, alignment: align)
            }
        }
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
        // A character that is a symbol in its own right (✭, ➢) is that
        // symbol whatever face is named: a symbol face's codes are Latin-1
        // or the private range, and PowerPoint finds anything else in
        // another font (pptx2svg's stars, "Wingdings" with U+272D).
        if scalar.value > 0xFF, !(0xF000 ... 0xF0FF).contains(scalar.value),
           face.hasPrefix("wingdings") || face.hasPrefix("symbol") || face.hasPrefix("webdings") {
            return String(ch[ch.startIndex])
        }
        // Wingdings 3's right arrowhead, a small triangle in PowerPoint's
        // prints (GeomLec1's and aascu 5864's bullets) — the one code of
        // that face the corpus shows printed.
        if face == "wingdings 3" {
            return [0x7D: "▸"][code]
        }
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
        s.kern = r["kern"].flatMap(Double.init).map { $0 / 100 }
        s.font = r.first("a:latin")?["typeface"]
        s.csFont = r.first("a:cs")?["typeface"].flatMap { $0.isEmpty ? nil : $0 }
        if let fill = r.first("a:solidFill") { s.color = colors.color(in: fill) }
        // Text filled with a gradient is drawn as such in WordArt (its run
        // looks); elsewhere in the gradient's middle colour, not the black
        // of no colour at all — tdf114848's red "Word Art Perspective".
        else if let g = r.first("a:gradFill"), let f = PptxReader.gradient(g, colors: colors), f.stops.count >= 2 {
            s.color = SlideFill.colorAt(f.stops, 0.5)
        }
        if let h = r.first("a:highlight") { s.highlight = colors.color(in: h) }
        if let link = r.first("a:hlinkClick") {
            // Linked text: underlined, in the theme's link colour over its
            // own — unless the link says to keep the text's (`hlinkClr
            // val="tx"`, PowerPoint 2019's). customGeo's resources page.
            s.underline = true
            if link.descendant("ahyp:hlinkClr")?["val"] != "tx", let c = colors.scheme("hlink") { s.color = c }
        }
        if let effects = r.first("a:effectLst") {
            // An outer shadow: `dist` along `dir` (60000ths of a degree,
            // clockwise from the right), blurred by `blurRad` — 45541's
            // titles and bullets, black three points down and right.
            // (One cast on the ground — scaled or skewed, tdf114848's —
            // is not drawn: as a copy of the letters it would stand up.)
            s.shadowSet = true
            s.shadow = outerShadow(effects, colors)
        }
        return s
    }

    /// An effect list's outer shadow: `dist` along `dir` (60000ths of a
    /// degree, clockwise from the right), blurred by `blurRad`. One cast
    /// on the ground — scaled or skewed — is nil: drawn as a copy of the
    /// outline it would stand up.
    static func outerShadow(_ effects: XNode?, _ colors: ColorContext) -> CharShadow? {
        // (Scaled alike both ways it is the outline larger or smaller —
        // tdf104015's title's 101%, tdf130058's 1% — and drawn so.)
        guard let sh = effects?.first("a:outerShdw"), let c = colors.color(in: sh),
              ["kx", "ky"].allSatisfy({ k in sh[k].flatMap(Double.init).map { $0 == 0 } ?? true }),
              (sh["sx"].flatMap(Double.init) ?? 100000) == (sh["sy"].flatMap(Double.init) ?? 100000)
        else { return nil }
        let dist = (sh["dist"].flatMap(Double.init) ?? 0) / Pptx.emu
        let dir = (sh["dir"].flatMap(Double.init) ?? 0) / 60000 * .pi / 180
        var shadow = CharShadow(color: c, dx: dist * cos(dir), dy: dist * sin(dir),
                                blur: (sh["blurRad"].flatMap(Double.init) ?? 0) / Pptx.emu)
        shadow.scale = (sh["sx"].flatMap(Double.init) ?? 100000) / 100000
        let algn = sh["algn"] ?? "b"
        shadow.anchor = Offset(algn.hasSuffix("l") ? 0 : algn.hasSuffix("r") ? 1 : 0.5,
                               algn.hasPrefix("t") ? 0 : algn.hasPrefix("b") ? 1 : 0.5)
        return shadow
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
        let unsaidKern: Double = defaults != nil ? 0 : 12
        // The deck's table styles, by id: what each table's `tableStyleId`
        // names (PowerPoint writes every style a deck uses into the part).
        var tableStyles: [String: XNode] = [:]
        if let lst = package.rel(pres, kind: "tableStyles").flatMap({ package.xml($0.target) }) {
            for st in lst.all("a:tblStyle") { if let id = st["styleId"] { tableStyles[id] = st } }
        }
        for (id, xml) in PptxTemplates.builtinTableStyles where tableStyles[id] == nil {
            if let st = XNode.parse(Data(xml.utf8)) { tableStyles[id] = st }
        }

        var deckTheme = DeckTheme()
        var deckThemePart: String? = nil
        var slides: [SlideState] = []
        var nextId = 1
        func id() -> Int { defer { nextId += 1 }; return nextId }
        for (n, part) in slideParts.enumerated() {
            // A slide whose part is missing or unreadable (a damaged
            // file) is a blank page, as PowerPoint shows it after repair —
            // dropped, every later slide stood a page early against it
            // (clusterfuzz 4986 lost four).
            let slide = package.xml(part)
                ?? XNode.parse(Data("<p:sld><p:cSld><p:spTree></p:spTree></p:cSld></p:sld>".utf8))!
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
            if n == 0 { deckTheme = Self._deckTheme(theme, colors); deckThemePart = themePart }
            let ctx = SlideContext(package: package, part: part, slide: slide, layout: layout, master: master,
                                   colors: colors, theme: theme, defaults: defaults, slideSize: size, images: images,
                                   tableStyles: tableStyles, foreignTheme: n > 0 && themePart != deckThemePart,
                                   unsaidKern: unsaidKern)
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
                                            colors: colors, theme: theme, defaults: defaults, slideSize: size, images: images,
                                            foreignTheme: n > 0 && themePart != deckThemePart,
                                            unsaidKern: unsaidKern)
                    var found: [ShapeState] = []
                    octx.shapes(in: tree, transform: nil, into: &found, id: id)
                    decorations += found.filter { s in
                        if case .placeholder = s.kind { return false }
                        // An object this app cannot draw is a labelled box on
                        // a slide, but nothing in its backdrop.
                        // (One drawn from its members — a turned group, a
                        // diagram — is drawn: tdf149865's layout stripe is a
                        // group turned a quarter.)
                        if case .opaque(let o) = s.kind, o.freeform == nil, o.rendering.isEmpty { return false }
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
                // Shaded to the title (`shadeToTitle`): the path gradient
                // runs out from the title's box.
                if b.first("p:bgPr")?["shadeToTitle"] == "1", bgFill?.path != nil, size.width > 0, size.height > 0,
                   let title = shapes.first(where: { $0.phType == "title" || $0.phType == "ctrTitle" })?.frame {
                    bgFill?.fillTo = Rect.fromLTRB(max(0, title.left / size.width), max(0, title.top / size.height),
                                                   max(0, 1 - title.right / size.width), max(0, 1 - title.bottom / size.height))
                }
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
        if let p = pr.first("a:pattFill") { return Self.pattern(p, colors: colors) }
        if let b = pr.first("a:blipFill"), let blip = b.first("a:blip"), let rid = blip["r:embed"],
           let rel = package.rels(owner).first(where: { $0.id == rid }), !rel.external,
           package.parts[rel.target] != nil {
            var f = SlideFill(image: images.attachment(rel.target, package))
            (f.imageAlpha, f.duotone) = Self.blipEffects(blip, colors: colors)
            f.imageLevels = Self.blipLevels(blip)
            // Tiled when it says so — and when it says neither that nor
            // `a:stretch`: a bare `a:blip` repeats at its own size
            // (tdf128596's sheet of ticks, which was one tick stretched).
            let tileNode = b.first("a:tile") ?? (b.first("a:stretch") == nil ? XNode(name: "a:tile", attrs: [:]) : nil)
            if let tile = tileNode {
                Self.tile(tile, image: package.parts[rel.target], into: &f)
            }
            f.imageInset = Self.stretchInset(b)
            return f
        }
        return nil
    }

    /// A picture fill's `a:tile` (or nil for a bare `a:blip`, which tiles
    /// with the defaults): its scale, alignment and offset, into `f`.
    /// `a:pattFill`: its preset in its two colours (black on white where
    /// it names none, as PowerPoint draws them).
    static func pattern(_ p: XNode, colors: ColorContext) -> SlideFill {
        PatternFill.fill(preset: p["prst"] ?? "pct5",
                         foreground: p.first("a:fgClr").flatMap { colors.color(in: $0) } ?? Color(0xFF000000),
                         background: p.first("a:bgClr").flatMap { colors.color(in: $0) } ?? Color(0xFFFFFFFF))
    }

    static func tile(_ tile: XNode?, image: Data?, into f: inout SlideFill) {
        f.tiled = true
        // At the picture's own resolution (its declared dpi) times `sx` and
        // `sy`. One that declares none comes out at 96 dpi in PowerPoint for
        // Windows — lo-page_transparent_bitmap, a 94 px PNG, tiles at 70.5 pt
        // in its export (PowerPoint for Mac drew it 47 pt wide, as at 144 dpi:
        // its pixels taken as a Retina screen's, it seems).
        let dpi = image.flatMap(imageDPI) ?? 96
        f.tileScale = (tile?["sx"].flatMap(Double.init) ?? 100000) / 100000 * 96 / dpi
        f.tileScaleY = (tile?["sy"].flatMap(Double.init) ?? 100000) / 100000 * 96 / dpi
        // `tx`/`ty` in EMU, after the alignment (tdf152070: the grid starts
        // 35 pt in and 40.5 down, as its 444500 and 514350 say).
        f.tileOffset = Offset((tile?["tx"].flatMap(Double.init) ?? 0) / 12700,
                              (tile?["ty"].flatMap(Double.init) ?? 0) / 12700)
        switch tile?["algn"] ?? "tl" {
        case "t": f.tileAlign = Offset(0.5, 0)
        case "tr": f.tileAlign = Offset(1, 0)
        case "l": f.tileAlign = Offset(0, 0.5)
        case "ctr": f.tileAlign = Offset(0.5, 0.5)
        case "r": f.tileAlign = Offset(1, 0.5)
        case "bl": f.tileAlign = Offset(0, 1)
        case "b": f.tileAlign = Offset(0.5, 1)
        case "br": f.tileAlign = Offset(1, 1)
        default: f.tileAlign = Offset(0, 0)
        }
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
        f.scaled = ["1", "true"].contains(g.first("a:lin")?["scaled"] ?? "")
        // Plain colours: no stop's colour carries a modifier (tint, satMod…).
        f.eased = !(g.first("a:gsLst")?.all("a:gs") ?? []).contains { gs in gs.children.contains { !$0.children.isEmpty } }
        f.even = (g.first("a:gsLst")?.all("a:gs") ?? []).contains { gs in
            gs.children.contains { $0.name == "a:schemeClr" && !$0.children.isEmpty }
        }
        f.undirected = g.first("a:lin") == nil && g.first("a:path") == nil
        f.squared = (g.first("a:gsLst")?.all("a:gs") ?? []).contains { gs in gs.children.contains { $0.first("a:gamma") != nil } }
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

    /// An arrowhead, or nil for none.
    static func lineEnd(_ n: XNode?) -> LineEnd? {
        guard let n, let kind = n["type"], kind != "none" else { return nil }
        func size(_ v: String?) -> Double { v == "sm" ? 2 : v == "lg" ? 5 : 3 }
        return LineEnd(kind: kind, width: size(n["w"]), length: size(n["len"]))
    }

    /// A line's join: "round", "bevel", "miter", or nil where it names none.
    static func join(_ ln: XNode?) -> String? {
        guard let ln else { return nil }
        if ln.first("a:round") != nil { return "round" }
        if ln.first("a:bevel") != nil { return "bevel" }
        if ln.first("a:miter") != nil { return "miter" }
        return nil
    }

    /// A line's preset dash (`a:prstDash`), nil for solid.
    static func dash(_ ln: XNode?) -> String? {
        // A custom dash (`a:custDash`), its stops in thousandths of a
        // percent of the width: "cust:" and the widths, on and off by turns.
        if let cust = ln?.first("a:custDash") {
            let widths = cust.all("a:ds").flatMap { ds in
                [ds["d"], ds["sp"]].map { ($0.flatMap(Double.init) ?? 0) / 100000 }
            }
            guard widths.contains(where: { $0 > 0 }) else { return nil }
            return "cust:" + widths.map { String($0) }.joined(separator: ",")
        }
        guard let v = ln?.first("a:prstDash")?["val"], v != "solid" else { return nil }
        return v
    }

    /// `a:stretch/a:fillRect` in a blip fill: where the picture sits, as
    /// fractions inset from each edge.
    static func stretchInset(_ blipFill: XNode) -> EdgeInsets {
        guard let fr = blipFill.first("a:stretch")?.first("a:fillRect") else { return .zero }
        func v(_ k: String) -> Double { (fr[k].flatMap(Double.init) ?? 0) / 100000 }
        return EdgeInsets(left: v("l"), top: v("t"), right: v("r"), bottom: v("b"))
    }

    /// A blip's brightness and contrast (`a:lum`) or black and white
    /// (`a:biLevel`) as a colour matrix over 0…255 channels, as
    /// PowerPoint's print has them: contrast c scales about the middle by
    /// 1 + c (below nought; 1 / (1 − c) above), then brightness b blends
    /// toward white by b (toward black by −b) — Washout (b 70%, c −70%)
    /// takes black to 205 (tdf79007); black and white turns a pixel whose
    /// luminance is under the threshold black, the rest white (189 under
    /// 75% black, 194 white: tdf89928).
    static func blipLevels(_ blip: XNode) -> [Double]? {
        if let b = blip.first("a:biLevel") {
            let t = (b["thresh"].flatMap(Double.init) ?? 50000) / 100000
            let k = 100.0
            var m: [Double] = []
            for _ in 0 ..< 3 { m += [0.299 * k, 0.587 * k, 0.114 * k, 0, -k * t * 255 + 127.5] }
            return m + [0, 0, 0, 1, 0]
        }
        guard let l = blip.first("a:lum") else { return nil }
        let bright = (l["bright"].flatMap(Double.init) ?? 0) / 100000
        let contrast = (l["contrast"].flatMap(Double.init) ?? 0) / 100000
        guard bright != 0 || contrast != 0 else { return nil }
        let cf = contrast < 0 ? 1 + contrast : 1 / max(0.01, 1 - contrast)
        // c' = cf·x + 127.5·(1 − cf); then toward white: c'·(1 − b) + 255·b.
        var scale = cf, offset = 127.5 * (1 - cf)
        if bright > 0 { scale *= 1 - bright; offset = offset * (1 - bright) + 255 * bright }
        else if bright < 0 { scale *= 1 + bright; offset *= 1 + bright }
        var m: [Double] = []
        for ch in 0 ..< 3 {
            var row = [0.0, 0, 0, 0, offset]
            row[ch] = scale
            m += row
        }
        return m + [0, 0, 0, 1, 0]
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
                if let col = colors.color(in: holder, duotone: true) { pair.append(col) }
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
    /// A group's child turned nearer upright on its side (45° to 135°, or
    /// 225° to 315°) is scaled by the group with its axes swapped, its box
    /// stored so: GroupTransform's 80° shape in a group squeezed to two
    /// thirds of its height keeps its width and loses a third of its
    /// length in PowerPoint's print, where ours squeezed it across.
    static func swapGroupScale(_ m: inout ShapeState, sx: Double, sy: Double) {
        guard sx > 0, sy > 0, abs(sx - sy) > 1e-9 else { return }
        let r = (m.rotation.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        guard (r >= 45 && r < 135) || (r >= 225 && r < 315) else { return }
        m.frame = Rect.fromCenter(center: m.frame.center, width: m.frame.width * sy / sx, height: m.frame.height * sx / sy)
    }

    /// An indent past the margin (a first-line indent, the paragraph's own)
    /// under a bullet, read as a hang of that much: PowerPoint keeps the
    /// bullet at the margin and starts the text at the indent, as with the
    /// margin that far in and the indent hanging back to it — bullet-
    /// indent's 25.5 pt first line, its bullet at the box's edge, where
    /// ours stood both 25.5 further in.
    static func hangPositiveIndent(_ style: inout RichParagraphStyle, own: Double?, indent: Double?, marL: Double?,
                                   shapeIndent: Double, level: Int) {
        guard let own, own > 0, let indent, indent > 0 else { return }
        style.indentLeft = (marL ?? 0) + indent - shapeIndent * Double(level + 1)
        style.firstLineIndent = -indent + shapeIndent
    }

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
    /// The slide's master has a theme of its own, not the deck's (the
    /// first slide's): what follows the theme is drawn against the deck's,
    /// so a chart takes this one's colours as its own.
    var foreignTheme = false
    /// The size a run whose styles say no `kern` is kerned from: none
    /// (0) in a deck with a default text style of its own, as every
    /// PowerPoint file has, and PowerPoint's built-in 12 pt in one with
    /// none (LibreOffice's). Sweep 170-174: alterman's 24 pt body sets
    /// "You" at its plain width, and so do bug68703's and bug65228's,
    /// which say `kern` nowhere but have the style; lo-open-as-read-only's
    /// "read-only," is 2.7 pt short of plain.
    var unsaidKern: Double? = nil

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
            // Hidden (`cNvPr hidden="1"`), itself or by its group: in the
            // file, and not drawn — lo-hidden_group_shape's red square.
            if group?.hidden == true || el.descendant("p:cNvPr")?["hidden"] == "1" { s.invisible = true }
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
                    // Drawn, though, as its members placed and turned the way
                    // the group turns them: each about the group's middle,
                    // mirrored first when the group is (a show and an export
                    // had nothing where a turned group stood — tdf100065).
                    var o = _opaque(el, label: "Group", transform, id: id)
                    if case .opaque(var obj)? = o?.kind, let gf = _xfrmRect(gx),
                       let chOff = gx.first("a:chOff"), let chExt = gx.first("a:chExt"),
                       let cox = chOff["x"].flatMap(Double.init), let coy = chOff["y"].flatMap(Double.init),
                       let ccx = chExt["cx"].flatMap(Double.init), let ccy = chExt["cy"].flatMap(Double.init),
                       ccx >= 0, ccy >= 0 {
                        let sx = ccx > 0 ? gf.width / (ccx / Pptx.emu) : 1, sy = ccy > 0 ? gf.height / (ccy / Pptx.emu) : 1
                        let map: (Rect) -> Rect = { r in
                            let mapped = Rect.fromLTWH(gf.left + (r.left - cox / Pptx.emu) * sx,
                                                       gf.top + (r.top - coy / Pptx.emu) * sy, r.width * sx, r.height * sy)
                            return transform?(mapped) ?? mapped
                        }
                        var members: [ShapeState] = []
                        shapes(in: el, transform: map, into: &members, id: id, group: nil, groupFill: ownFill(el))
                        let frame = transform?(gf) ?? gf
                        let centre = frame.center
                        let degrees = (gx["rot"].flatMap(Double.init) ?? 0) / 60000
                        let rad = degrees * .pi / 180
                        let flipH = gx["flipH"] == "1", flipV = gx["flipV"] == "1"
                        for k in members.indices { SlideContext.swapGroupScale(&members[k], sx: sx, sy: sy) }
                        obj.rendering = members.flatMap { m -> [ShapeState] in
                            // A member that is itself drawn through others
                            // (a nested turned group) hands those on; one
                            // kept whole that draws itself (a freeform) is
                            // a member like any other — HowWeRefactor's
                            // mirrored wrenches were left out.
                            if case .opaque(let inner) = m.kind, !inner.rendering.isEmpty || inner.freeform == nil { return inner.rendering }
                            return [m]
                        }.map { m in
                            var m = m
                            var c = m.frame.center
                            if flipH { c = Offset(2 * centre.dx - c.dx, c.dy); m.flipH.toggle(); m.rotation = -m.rotation }
                            if flipV { c = Offset(c.dx, 2 * centre.dy - c.dy); m.flipV.toggle(); m.rotation = -m.rotation }
                            let dx = c.dx - centre.dx, dy = c.dy - centre.dy
                            c = Offset(centre.dx + dx * cos(rad) - dy * sin(rad), centre.dy + dx * sin(rad) + dy * cos(rad))
                            m.frame = Rect.fromCenter(center: c, width: m.frame.width, height: m.frame.height)
                            m.rotation += degrees
                            return m
                        }
                        o?.kind = .opaque(obj)
                    }
                    add(o, el)
                    continue
                }
                // Groups are flattened: each member drawn where the group's
                // child space maps it on the slide.
                guard let x = el.first("p:grpSpPr")?.first("a:xfrm"), let frame = _xfrmRect(x),
                      let chOff = x.first("a:chOff"), let chExt = x.first("a:chExt"),
                      let cox = chOff["x"].flatMap(Double.init), let coy = chOff["y"].flatMap(Double.init),
                      let ccx = chExt["cx"].flatMap(Double.init), let ccy = chExt["cy"].flatMap(Double.init),
                      ccx >= 0, ccy >= 0 else {
                    add(_opaque(el, label: "Group", transform, id: id), el)
                    continue
                }
                // A child space of no width (or height) maps that way one
                // to one from the group's corner: tdf136830's figure, whose
                // `chExt cx="0"`, keeps its members' own widths in
                // PowerPoint's print and is scaled only up and down. (It
                // was drawn as nothing.)
                let sx = ccx > 0 ? frame.width / (ccx / Pptx.emu) : 1, sy = ccy > 0 ? frame.height / (ccy / Pptx.emu) : 1
                let map: (Rect) -> Rect = { r in
                    let mapped = Rect.fromLTWH(frame.left + (r.left - cox / Pptx.emu) * sx,
                                               frame.top + (r.top - coy / Pptx.emu) * sy,
                                               r.width * sx, r.height * sy)
                    return transform?(mapped) ?? mapped
                }
                var members: [ShapeState] = []
                shapes(in: el, transform: map, into: &members, id: id, group: groupOf(el), groupFill: ownFill(el))
                for k in members.indices { SlideContext.swapGroupScale(&members[k], sx: sx, sy: sy) }
                out += members
            case "mc:AlternateContent":
                // The fallback is what an older reader would draw: keep the
                // whole thing — and draw it as that fallback's shapes (or the
                // choice's, where the fallback holds nothing this app reads:
                // tdf131553's diagram sits in one of each).
                var o = _opaque(el, label: "Object", transform, id: id)
                if case .opaque(var obj)? = o?.kind {
                    for branch in ["mc:Fallback", "mc:Choice"] where obj.rendering.isEmpty {
                        guard let b = el.first(branch) else { continue }
                        var inner: [ShapeState] = []
                        shapes(in: b, transform: transform, into: &inner, id: id, group: nil, groupFill: groupFill)
                        obj.rendering = inner.flatMap { m -> [ShapeState] in
                            if case .opaque(let x) = m.kind { return x.rendering }
                            return [m]
                        }
                    }
                    o?.kind = .opaque(obj)
                }
                add(o, el)
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
        let phRead = _ph(sp)
        // A placeholder with neither type nor index is index 0 — the
        // title's, which PowerPoint matches it to: formatting-bullet-
        // indent's `<p:ph/>` is set as its title is (44 pt, no bullet).
        let ph: XNode? = phRead.map { p in
            guard p["type"] == nil, p["idx"] == nil || p["idx"] == "0" else { return p }
            let t = XNode(name: p.name, attrs: p.attrs)
            t.attrs["type"] = "title"
            return t
        }
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
            // (A preset of no name DrawingML knows is a line across the
            // frame, top left to bottom right, as PowerPoint draws it —
            // a fuzzed deck's "roCndRect", its text and fill not shown.)
            kind = .geometry(PresetGeometry.has(prst) ? ShapePreset(rawValue: prst) : .line)
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
            // A picture fill: drawn within the outline, stretched — or
            // tiled, as a background's is: when it says `a:tile`, and when
            // it says neither that nor `a:stretch` (tdf128596's sheet of
            // ticks, which was one tick stretched).
            var f = SlideFill(image: images.attachment(rel.target, package))
            (f.imageAlpha, f.duotone) = PptxReader.blipEffects(blip, colors: colors)
            f.imageLevels = PptxReader.blipLevels(blip)
            f.imageInset = PptxReader.stretchInset(b)
            if b.first("a:tile") != nil || b.first("a:stretch") == nil {
                PptxReader.tile(b.first("a:tile"), image: package.parts[rel.target], into: &f)
            }
            fillStyle = f
        } else if let pf = spPr?.first("a:pattFill") {
            // A pattern: drawn as itself, the blend of its colours standing
            // for it.
            let f = PptxReader.pattern(pf, colors: colors)
            fill = f.color
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
        // The width of the theme's line style the shape's style refers to,
        // where its own line names none: 2 pt for an Office 2007 theme's
        // second (aascu 5864's ovals), where ours were ¾ pt.
        if let idx = style?.first("a:lnRef")?["idx"].flatMap(Int.init), theme.lineWidths.indices.contains(idx - 1) {
            outlineWidth = theme.lineWidths[idx - 1]
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
            else if let ref = style?.first("a:lnRef"), ref["idx"] != "0" { outline = colors.lineColor(in: ref) }
            // A line at alpha 0 is no line, and so is one of no width
            // (`w="0"`, as LibreOffice writes a hairline: PowerPoint shows
            // ThemeColorTransparency's red box and vert_and_padding's blue
            // arrows with none).
            if let o = outline, o.alpha == 0 { outline = nil }
            if ln["w"] == "0" { outline = nil }
        } else if let ref = style?.first("a:lnRef"), ref["idx"] != "0" {
            outline = colors.lineColor(in: ref)
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
        var inheritedDash: String? = nil
        if ph != nil, spPr?.first("a:ln") == nil, style?.first("a:lnRef") == nil {
            for node in [inherited.layout, inherited.master] {
                guard let ln = node?.first("p:spPr")?.first("a:ln") else { continue }
                if ln.has("a:noFill") { break }
                if let f = ln.first("a:solidFill") {
                    outline = colors.color(in: f)
                    outlineWidth = ln["w"].flatMap(Double.init).map { $0 / Pptx.emu } ?? outlineWidth
                    // And its dash (ShapeLineProperties' title, dotted by
                    // its layout).
                    inheritedDash = PptxReader.dash(ln)
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
                            listIndent: text.listIndent, phType: phRead?["type"], phIdx: phRead?["idx"],
                            fillScheme: fillScheme)
        if let prst, ph == nil, !isTextBox, !PresetGeometry.has(prst) { st.text = nil; st.fill = nil }
        st.autofit = text.autofit
        st.fontScale = text.fontScale
        st.lineReduction = text.lineReduction
        st.insetsFollowFont = text.insetsFollowFont
        st.sizeGroup = text.sizeGroup
        st.noWrap = text.noWrap
        st.anchorCentred = text.anchorCentred
        st.textTurn = text.textTurn
        st.textSpin = text.textSpin
        st.columns = text.columns
        st.columnGap = text.columnGap
        st.warp = text.warp
        st.runLooks = text.runLooks
        st.scene3d = Extrusion.read(spPr, colors: colors)
        st.flipH = xfrm?["flipH"] == "1"
        st.flipV = xfrm?["flipV"] == "1"
        st.fillsWithBackground = sp["useBgFill"] == "1"
        st.outlineDash = PptxReader.dash(spPr?.first("a:ln")) ?? inheritedDash
        // (Its join and ends, else its theme line style's.)
        let lineStyle: Int? = style?.first("a:lnRef")?["idx"].flatMap(Int.init).map { $0 - 1 }
        var styleJoin: String? = nil, styleCap: String? = nil
        if let k = lineStyle, theme.lineJoins.indices.contains(k) { styleJoin = theme.lineJoins[k] }
        if let k = lineStyle, theme.lineCaps.indices.contains(k) { styleCap = theme.lineCaps[k] }
        st.outlineJoin = PptxReader.join(spPr?.first("a:ln")) ?? styleJoin
        st.outlineCap = spPr?.first("a:ln")?["cap"] ?? styleCap
        // (Its colours across the box, where the line is a gradient: the
        // backgrounds deck's orange-to-blue frame, drawn in its first.)
        if let g = spPr?.first("a:ln")?.first("a:gradFill"), let fill = PptxReader.gradient(g, colors: colors),
           fill.stops.count >= 2, outline != nil { st.outlineFill = fill }
        st.headEnd = PptxReader.lineEnd(spPr?.first("a:ln")?.first("a:headEnd"))
        if let c = spPr?.first("a:ln")?["cmpd"], c != "sng" { st.outlineCompound = c }
        st.tailEnd = PptxReader.lineEnd(spPr?.first("a:ln")?.first("a:tailEnd"))
        st.shadow = _shapeShadow(spPr, style)
        if ph != nil, spPr?.first("a:effectLst") == nil, spPr?.first("a:effectDag") == nil, style?.first("a:effectRef") == nil {
            // A placeholder's shadow from its layout's or master's own
            // (tdf104015's title, red and shadowed by its master).
            for node in [inherited.layout, inherited.master] {
                guard let effects = node?.first("p:spPr")?.first("a:effectLst") else { continue }
                st.shadow = LevelStyle.outerShadow(effects, colors)
                break
            }
        }
        st.innerShadow = _shapeInnerShadow(spPr, style)
        if st.scene3d == nil { st.bevel = _shapeBevel(spPr, style) }
        if let effects = spPr?.first("a:effectLst") {
            if let g = effects.first("a:glow"), let c = colors.color(in: g) {
                st.glowRadius = (g["rad"].flatMap(Double.init) ?? 0) / Pptx.emu
                st.glowColor = c
            }
            if let soft = effects.first("a:softEdge")?["rad"].flatMap(Double.init), soft > 0 { st.softEdge = soft / Pptx.emu }
        }
        st.fillStyle = fillStyle
        if let o = spPr?.first("a:effectLst")?.first("a:fillOverlay"),
           var base = fillStyle ?? fill.map({ SlideFill(color: $0) }) {
            var over: SlideFill? = nil
            if let g = o.first("a:gradFill") { over = PptxReader.gradient(g, colors: colors) }
            else if let f = o.first("a:solidFill"), let c = colors.color(in: f) { over = SlideFill(color: c) }
            if let over {
                base.overlay = FillOverlay(fill: over, blend: o["blend"] ?? "over")
                st.fillStyle = base
            }
        }
        // A gradient that stays put when its shape turns (`rotWithShape`
        // off — tdf125551's chevrons, turned a quarter, shade top to
        // bottom still): its angle counted back by the shape's turn.
        if rotation != 0, let g = spPr?.first("a:gradFill"), ["0", "false"].contains(g["rotWithShape"] ?? ""),
           g.first("a:lin") != nil, st.fillStyle?.stops.isEmpty == false {
            st.fillStyle?.angle -= rotation
        }
        // A shape with depth or a camera prints as a picture, in sRGB: its
        // gradient's colours are its own (`SlideFill.unshifted`).
        if st.scene3d != nil { st.fillStyle?.unshifted = true }
        st.invisible = hiddenByLayout
        // A diagram shape's text frame (`txXfrm`, from a SmartArt drawing):
        // the text sits in that box rather than the shape's.
        let txBox = sp.first("p:txXfrm").flatMap(_xfrmRect)
        if let txBox {
            var tr = transform?(txBox) ?? txBox
            // A text frame turned a quarter in a shape that is not
            // (tdf135953's "left shape", read upward up the box's side):
            // the text is laid out along the frame and drawn turned, in
            // the room the turned frame covers.
            let own = (sp.first("p:txXfrm")?["rot"].flatMap(Double.init) ?? 0) / 60000
            let ownQuarter = abs(abs(own.truncatingRemainder(dividingBy: 180)) - 90) < 0.01
            var turnedInsets: EdgeInsets? = nil
            if ownQuarter, abs(st.rotation.truncatingRemainder(dividingBy: 360)) < 0.01, st.textTurn == 0 {
                let unturned = tr
                tr = Rect.fromCenter(center: tr.center, width: tr.height, height: tr.width)
                let turn = ((own.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360)
                st.textTurn = abs(turn - 90) < 0.01 ? 1 : -1
                // Its insets are the text frame's own, along the turned
                // text: the frame placed where the painter's turn about the
                // shape's centre brings it, the file's insets inside it,
                // and given in the order the painter turns them back.
                // (Added to the page's offsets instead, "left shape" stood
                // 10 pt nearer the box's side than PowerPoint's.)
                let c = frame.center, th = -Double(st.textTurn) * .pi / 2
                let q = unturned.center
                let at = Offset(c.dx + cos(th) * (q.dx - c.dx) - sin(th) * (q.dy - c.dy),
                                c.dy + sin(th) * (q.dx - c.dx) + cos(th) * (q.dy - c.dy))
                let t = Rect.fromCenter(center: at, width: unturned.width, height: unturned.height)
                let f = Rect.fromCenter(center: c, width: frame.height, height: frame.width)
                let n = EdgeInsets(left: st.insets.left + t.left - f.left, top: st.insets.top + t.top - f.top,
                                   right: st.insets.right + f.right - t.right, bottom: st.insets.bottom + f.bottom - t.bottom)
                turnedInsets = st.textTurn > 0 ? EdgeInsets(left: n.bottom, top: n.left, right: n.top, bottom: n.right)
                    : EdgeInsets(left: n.top, top: n.right, right: n.bottom, bottom: n.left)
            }
            // A quarter turn the text frame turns back (tdf145528's matrix:
            // "Writer" in a box turned 270° with its text at 90°): the text
            // stands upright in the frame as given, the shape turned.
            let back = (sp.first("p:txXfrm")?["rot"].flatMap(Double.init) ?? 0) / 60000
            let quarter = abs(abs(st.rotation.truncatingRemainder(dividingBy: 180)) - 90) < 0.01
            if quarter, abs((st.rotation + back).truncatingRemainder(dividingBy: 360)) < 0.01, sp["modelId"] != nil {
                st.uprightBox = tr
                st.uprightInsets = st.insets
            }
            st.insets = turnedInsets ?? EdgeInsets(left: st.insets.left + (tr.left - frame.left), top: st.insets.top + (tr.top - frame.top),
                                                   right: st.insets.right + (frame.right - tr.right),
                                                   bottom: st.insets.bottom + (frame.bottom - tr.bottom))
            // A shape turned half round whose text frame is turned back
            // (a callout header pointing down, tdf150789): the text stands
            // upright in its frame as placed. Half a turn is both mirrors,
            // and a mirrored shape keeps its text upright.
            let textTurn = (sp.first("p:txXfrm")?["rot"].flatMap(Double.init) ?? 0) / 60000
            if abs(abs(st.rotation.truncatingRemainder(dividingBy: 360)) - 180) < 0.01,
               abs((st.rotation + textTurn).truncatingRemainder(dividingBy: 360)) < 0.01 {
                st.rotation = 0
                st.flipH.toggle()
                st.flipV.toggle()
            }
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
                    st.shapeInsets = EdgeInsets(left: box.left * frame.width, top: box.top * frame.height,
                                                right: (1 - box.right) * frame.width, bottom: (1 - box.bottom) * frame.height)
                    st.insets = EdgeInsets(left: st.insets.left + box.left * frame.width,
                                           top: st.insets.top + box.top * frame.height,
                                           right: st.insets.right + (1 - box.right) * frame.width,
                                           bottom: st.insets.bottom + (1 - box.bottom) * frame.height)
                }
            }
        }
        // A placeholder drawn as a preset of its own: the shape, and its
        // text in the preset's text rectangle (customGeo's content oval
        // wraps in the inscribed box, as any oval does).
        if ph != nil, let p = prst, p != "rect" {
            st.inheritedPreset = ShapePreset(rawValue: p)
            if let g = PresetGeometry.geometry(p, width: frame.width * Pptx.emu, height: frame.height * Pptx.emu,
                                               adjustments: PresetGeometry.adjustments(spPr?.first("a:prstGeom"))) {
                st.customPath = g
                if txBox == nil, let box = g.textRect {
                    st.shapeInsets = EdgeInsets(left: box.left * frame.width, top: box.top * frame.height,
                                                right: (1 - box.right) * frame.width, bottom: (1 - box.bottom) * frame.height)
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
        // An elbow or a curve: its own path in its box, turned and mirrored
        // as a shape is (tdf141058's tree, whose elbows were diagonals).
        let prst = el.first("p:spPr")?.first("a:prstGeom")?["prst"] ?? "line"
        if prst.hasPrefix("bentConnector") || prst.hasPrefix("curvedConnector"),
           let g = PresetGeometry.geometry(prst, width: box.width * Pptx.emu, height: box.height * Pptx.emu,
                                           adjustments: PresetGeometry.adjustments(el.first("p:spPr")?.first("a:prstGeom"))) {
            let ln = el.first("p:spPr")?.first("a:ln")
            let color = ln?.has("a:noFill") == true ? nil : ln?.first("a:solidFill").flatMap(colors.color(in:))
                ?? el.first("p:style")?.first("a:lnRef").flatMap(colors.lineColor(in:)) ?? colors.scheme("tx1")
            var width = ln?["w"].flatMap(Double.init).map { $0 / Pptx.emu } ?? 0.75
            if ln?["w"] == nil, let idx = el.first("p:style")?.first("a:lnRef")?["idx"].flatMap(Int.init),
               theme.lineWidths.indices.contains(idx - 1) { width = theme.lineWidths[idx - 1] }
            var st = ShapeState(id: id(), name: el.first("p:nvCxnSpPr")?.first("p:cNvPr")?["name"] ?? "Connector",
                                kind: .geometry(ShapePreset(rawValue: prst)), frame: box,
                                rotation: (x["rot"].flatMap(Double.init) ?? 0) / 60000, fill: nil, outline: color,
                                outlineWidth: width, anchor: .middle, insets: EdgeInsets(left: 0, top: 0, right: 0, bottom: 0),
                                prompt: nil, text: nil, font: nil, size: 18, color: Color(0xFF000000), listIndent: 18)
            st.flipH = x["flipH"] == "1"
            st.flipV = x["flipV"] == "1"
            st.customPath = g
            st.sourceXML = PptxXML.serialize(el)
            st.sourcePart = part
            st.keptLine = KeptLine(line: box, box: box, outline: color, width: width)
            st.outlineDash = PptxReader.dash(ln)
            st.outlineJoin = PptxReader.join(ln)
            st.outlineCap = ln?["cap"]
            st.headEnd = PptxReader.lineEnd(ln?.first("a:headEnd"))
            st.tailEnd = PptxReader.lineEnd(ln?.first("a:tailEnd"))
            st.shadow = _shapeShadow(el.first("p:spPr"), el.first("p:style"))
            return st
        }
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
            ?? el.first("p:style")?.first("a:lnRef").flatMap(colors.lineColor(in:)) ?? colors.scheme("tx1")
        // (Its width the theme's line style, where it names one and says
        // none of its own, as an elbow's: lineStyle's `lnRef idx="2"`, 2 pt
        // in PowerPoint's print, drawn at 0.75.)
        var width = ln?["w"].flatMap(Double.init).map { $0 / Pptx.emu } ?? 0.75
        if ln?["w"] == nil, let idx = el.first("p:style")?.first("a:lnRef")?["idx"].flatMap(Int.init),
           theme.lineWidths.indices.contains(idx - 1) { width = theme.lineWidths[idx - 1] }
        var st = ShapeState(id: id(), name: el.first("p:nvCxnSpPr")?.first("p:cNvPr")?["name"] ?? "Line",
                            kind: .geometry(.line), frame: frame, rotation: 0, fill: nil, outline: color,
                            outlineWidth: width,
                            anchor: .middle, insets: EdgeInsets(left: 0, top: 0, right: 0, bottom: 0), prompt: nil,
                            text: nil, font: nil, size: 18, color: Color(0xFF000000), listIndent: 18)
        st.sourceXML = PptxXML.serialize(el)
        st.sourcePart = part
        st.keptLine = KeptLine(line: frame, box: box, outline: color, width: width)
        st.shadow = _shapeShadow(el.first("p:spPr"), el.first("p:style"))
        st.outlineDash = PptxReader.dash(el.first("p:spPr")?.first("a:ln"))
        st.outlineJoin = PptxReader.join(el.first("p:spPr")?.first("a:ln"))
        st.outlineCap = el.first("p:spPr")?.first("a:ln")?["cap"]
        st.headEnd = PptxReader.lineEnd(ln?.first("a:headEnd"))
        st.tailEnd = PptxReader.lineEnd(ln?.first("a:tailEnd"))
        return st
    }

    /// The picture a legacy VML drawing shows for shape `spid`
    /// (`<v:shape id="…"><v:imagedata o:relid="…"/>`): what an embedded
    /// object written before `p:pic` fallbacks displays. The drawing is
    /// read as text — VML is not always well-formed XML.
    private func _vmlImage(_ spid: String) -> ImageAttachment? {
        // (Office 2007 names the relationship `legacyDrawing`, under its
        // own namespace: tdf169781's budget chart.)
        for rel in package.rels(part) where ["vmlDrawing", "legacyDrawing"].contains(rel.kind) && !rel.external {
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

    /// PowerPoint's box for a picture it cannot draw: white, ruled black,
    /// a bevelled icon with a red cross 7 pt in, and "The picture can't be
    /// displayed." in Segoe UI 10.5 pt, 27 pt in — measured on its print.
    static func brokenPicture(in r: Rect, id: () -> Int) -> [ShapeState] {
        func box(_ f: Rect, fill: Color?, outline: Color? = nil, width: Double = 0, preset: String = "rect") -> ShapeState {
            ShapeState(id: id(), name: "Broken picture", kind: .geometry(ShapePreset(rawValue: preset)), frame: f, rotation: 0,
                       fill: fill, outline: outline, outlineWidth: width, anchor: .top,
                       insets: EdgeInsets(left: 0, top: 0, right: 0, bottom: 0), prompt: nil, text: nil,
                       font: nil, size: 18, color: Color(0xFF000000), listIndent: 18)
        }
        var shapes = [box(Rect.fromLTRB(r.left + 0.5, r.top + 0.5, r.right - 0.5, r.bottom - 0.5),
                          fill: Color(0xFFFFFFFF), outline: Color(0xFF000000), width: 1)]
        let x = r.left + 7, y = r.top + 7
        shapes.append(box(Rect.fromLTWH(x, y, 14, 16), fill: Color(0xFF000000)))
        shapes.append(box(Rect.fromLTWH(x, y, 13, 15), fill: Color(0xFF808080)))
        shapes.append(box(Rect.fromLTWH(x + 1, y + 1, 12, 14), fill: Color(0xFFC0C0C0)))
        shapes.append(box(Rect.fromLTWH(x + 1, y + 1, 11, 13), fill: Color(0xFFFFFFFF)))
        var a = box(Rect.fromLTWH(x + 4.5, y + 5.5, 5, 4), fill: nil, outline: Color(0xFFFF0000), width: 1.3, preset: "line")
        shapes.append(a)
        a.id = id()
        a.flipV = true
        shapes.append(a)
        var text = box(Rect.fromLTRB(r.left + 27, r.top + 8.0, max(r.left + 28, r.right - 4), r.bottom), fill: nil)
        text.kind = .textBox
        let message = "The picture can't be displayed."
        let look = CharStyle(fontFamily: "Segoe UI", fontSize: 10.5, color: Color(0xFF000000))
        text.text = RichDocument(paragraphs: [RichParagraph(text: message, runs: [Run(length: message.utf16.count, style: look)],
                                                            style: RichParagraphStyle(spaceAfter: 0, lineSpacing: 1.0))])
        text.font = "Segoe UI"
        text.size = 10.5
        shapes.append(text)
        return shapes
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
            guard var o = _opaque(el, label: "Picture", transform, id: id) else { return nil }
            // A picture that names no picture (no `blipFill`, or a blip with
            // neither `r:embed` nor `r:link`): PowerPoint's box saying so, as
            // its print has it in missing-blip-fill, tdf147586 and a fuzzed
            // deck. (Not one naming a part the package lacks: Divino's,
            // its zip cut short, print as nothing.)
            let blip = el.first("p:blipFill")?.first("a:blip")
            if blip?["r:embed"] == nil, blip?["r:link"] == nil, case .opaque(var obj) = o.kind {
                obj.rendering = Self.brokenPicture(in: o.frame, id: id)
                obj.clipsRendering = true
                o.kind = .opaque(obj)
            }
            return o
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
        } else if let geom = el.first("p:spPr")?.first("a:custGeom") {
            // Or to a freeform outline (tdf153008's circle in four curves).
            s.customPath = FreeformGeometry.parse(geom, width: frame.width * Pptx.emu, height: frame.height * Pptx.emu)
        }
        if let blip = el.first("p:blipFill")?.first("a:blip") {
            (s.pictureAlpha, s.pictureDuotone) = PptxReader.blipEffects(blip, colors: colors)
            s.pictureLevels = PptxReader.blipLevels(blip)
            if let change = blip.first("a:clrChange"), let from = change.first("a:clrFrom").flatMap({ colors.color(in: $0) }),
               let to = change.first("a:clrTo").flatMap({ colors.color(in: $0) }) {
                s.pictureColorChange = [from, to]
            }
        }
        if let b = el.first("p:blipFill") { s.pictureInset = PptxReader.stretchInset(b) }
        // Its outline (graphic-stroke's green frame round an OLE object's
        // picture): the line's own colour, else its style's.
        let ln = el.first("p:spPr")?.first("a:ln"), lnRef = el.first("p:style")?.first("a:lnRef")
        // (Not one turned in 3-D, which is drawn flat here: its frame
        // would stand where the picture does not — Scene3d_pureImage.)
        if ln?.has("a:noFill") != true, el.first("p:spPr")?.first("a:scene3d") == nil {
            if let f = ln?.first("a:solidFill") { s.outline = colors.color(in: f) }
            else if let ref = lnRef, ref["idx"] != "0" { s.outline = colors.lineColor(in: ref) }
            if s.outline != nil {
                var w = 0.75
                if let idx = lnRef?["idx"].flatMap(Int.init), theme.lineWidths.indices.contains(idx - 1) { w = theme.lineWidths[idx - 1] }
                s.outlineWidth = ln?["w"].flatMap(Double.init).map { $0 / Pptx.emu } ?? w
                s.outlineDash = PptxReader.dash(ln)
            }
        }
        s.shadow = _shapeShadow(el.first("p:spPr"), el.first("p:style"))
        // (Its edge faded as a shape's is: croppedTo0's rounded picture,
        // its 10 pt `softEdge` drawn sharp before. Not one in 3-D, a
        // bevel on it: tdf170095's prints whole, unfaded.)
        if el.first("p:spPr")?.first("a:sp3d") == nil,
           let soft = el.first("p:spPr")?.first("a:effectLst")?.first("a:softEdge")?["rad"].flatMap(Double.init), soft > 0 {
            s.softEdge = soft / Pptx.emu
        }
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
        // A table's text takes the master's other-text style over the
        // presentation's default: tdf135843_insideH's empty rows are
        // 10.13 pt lines (the master's), not 13.5 (the default's).
        var base = LevelStyle.paragraph(master?.first("p:txStyles")?.first("p:otherStyle")?.first("a:lvl1pPr"), colors)
            .filled(from: LevelStyle.paragraph(defaults?.first("a:lvl1pPr"), colors))
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
        // The table style's face over the deck's default text: every
        // built-in style names the theme's minor font (`fontRef idx=
        // "minor"`), so a table set in it where the deck's default text
        // says Arial — the AES deck's Verdana tables, which wrapped a
        // word or two later in Arial.
        base.font = whole?.font ?? (style == nil ? "+mn-lt" : base.font)
        let rowCount = tbl.all("a:tr").count
        var paragraphs: [RichParagraph] = []
        var cellListFormats: [String: [Int: ListLevelFormat]] = [:], cellListRestarts: [String: [Int: Int]] = [:]
        for (r, tr) in tbl.all("a:tr").enumerated() {
            var column = 0
            let cells = tr.all("a:tc")
            let columnCount = cells.count
            for (c, tc) in cells.enumerated() {
                defer { column += 1 }
                if tc["hMerge"] == "1" || tc["vMerge"] == "1" { continue }
                // A span reaches over the merged cells that follow it and no
                // further: LIBRE_OFFICE-100610's "Vermelho" says three
                // columns with none after it, and PowerPoint wraps it in one.
                var span = 1
                while span < (tc["gridSpan"].flatMap(Int.init) ?? 1), c + span < cells.count, cells[c + span]["hMerge"] == "1" { span += 1 }
                var cell = CellRef(table: tableId, row: r, column: column,
                                   span: span, rowSpan: tc["rowSpan"].flatMap(Int.init) ?? 1)
                // The style's regional looks, the later ones over the earlier
                // (a corner cell of the header row looks like the header).
                var regional: [TablePartStyle] = []
                // Banded columns (`bandCol`): the style's two column bands
                // by turns, counted from the column after an emphasised
                // first one — table-with-different-font-colors' darker
                // second column and cyan third. Their fill is under the
                // row bands', which PowerPoint draws over them.
                var bandColPart: TablePartStyle? = nil
                if pr?["bandCol"] == "1", let style {
                    let k = c - (pr?["firstCol"] == "1" ? 1 : 0)
                    if k >= 0 { bandColPart = _tablePart(style, k % 2 == 0 ? "a:band1V" : "a:band2V") }
                }
                if let f = bandColPart?.fill, !banded, r > 0 || firstRowPart == nil { cell.fill = f }
                if c == 0, let p = firstColPart { regional.append(p) }
                if c == columnCount - 1, let p = lastColPart { regional.append(p) }
                if r == rowCount - 1, r > 0, let p = lastRowPart { regional.append(p) }
                if r == 0, let p = firstRowPart { regional.append(p) }
                // (A header cell spanning rows down takes the header's fill
                // as its own: left to the row's, the band of the row below
                // showed through it — tdf149785's "Key Functions".)
                let tall = (tc["rowSpan"].flatMap(Int.init) ?? 1) > 1
                if let f = regional.compactMap(\.fill).last, r > 0 || firstRowPart == nil || tall { cell.fill = f }
                // A built-in style the deck does not define (the guess: the
                // first accent, white bold header) dresses its first and
                // last column and its last row like the header when the
                // table's flags ask — Medium Style 2's own way (tdf149785's
                // first column was a plain band).
                let emphasised = style == nil && !plain
                    && ((pr?["firstCol"] == "1" && c == 0) || (pr?["lastCol"] == "1" && c == columnCount - 1)
                        || (pr?["lastRow"] == "1" && r == rowCount - 1 && r > 0))
                if emphasised, !(r == 0 && firstRow) || tall { cell.fill = theme.colors["accent1"] ?? Color(0xFF4472C4) }
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
                            // (Dashed as a shape's line is: tableBorderLineStyle's
                            // dots and dashes.)
                            return CellRef.CellLine(width: width, color: c, dash: SlidePainter.dashPattern(PptxReader.dash(ln)))
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
                if let style {
                    // A row band's text look (`band1H`/`band2H` `tcTxStyle`),
                    // under the regional ones, its bands counted as their
                    // fills are, from the row after a header:
                    // table-with-different-font-colors' third row is band2H's
                    // cyan text. (Only the bands' fills were read.)
                    let k = r - (firstRow ? 1 : 0)
                    let rowBandText: [TablePartStyle] = pr?["bandRow"] == "1" && k >= 0
                        ? [_tablePart(style, k % 2 == 0 ? "a:band1H" : "a:band2H")].compactMap { $0 } : []
                    for p in rowBandText + (bandColPart.map { [$0] } ?? []) + regional {
                        if let f = p.font { look.font = f }
                        if let b = p.bold { look.bold = b }
                        if let c = p.textColor { look.color = c }
                    }
                } else if (r == 0 && firstRow && !plain) || emphasised {
                    look.bold = look.bold ?? true
                    look.color = colors.scheme("lt1") ?? Color(0xFFFFFFFF)
                }
                var cellParas: [RichParagraph] = []
                var cellLevels: [Int] = [], cellNumbering: [(type: String, start: Int)?] = []
                for p in tc.first("a:txBody")?.all("a:p") ?? [] {
                    var level = LevelStyle.paragraph(p.first("a:pPr"), colors).filled(from: look)
                    let cellLevel = p.first("a:pPr")?["lvl"].flatMap(Int.init) ?? 0
                    cellLevels.append(cellLevel)
                    // A deeper level's text edge and hang, where the
                    // paragraph says neither, are its level's in the
                    // master's other-text style or the presentation's
                    // default: the AES tables' `lvl="1"` and `lvl="2"`
                    // bullets, at half an inch and an inch (marL 457200 and
                    // 914400 in `lvl2pPr` and `lvl3pPr`), stood at the edge.
                    if cellLevel > 0, p.first("a:pPr")?["marL"] == nil, p.first("a:pPr")?["indent"] == nil {
                        let tag = "a:lvl\(min(cellLevel, 8) + 1)pPr"
                        let own = LevelStyle.paragraph(master?.first("p:txStyles")?.first("p:otherStyle")?.first(tag), colors)
                            .filled(from: LevelStyle.paragraph(defaults?.first(tag), colors))
                        level.marL = own.marL
                        level.indent = own.indent
                    }
                    cellNumbering.append(level.bullet == .number ? (level.autoNumType ?? "arabicPeriod", level.autoNumStart ?? 1) : nil)
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
                        // (Kerned from the size `kern` says up, as a text box's runs.)
                        if Self._unkerned(_font(s.font), bold: s.bold ?? false) {
                            runs[runs.count - 1].style.kerningFrom = 0
                        } else { runs[runs.count - 1].style.kerningFrom = s.kern ?? unsaidKern }
                        Self.faceSpacing(&runs[runs.count - 1].style)
                        // (And what a text box's run carries besides: highlight-
                        // test-case's green and yellow in its table's first
                        // cell, drawn plain.)
                        runs[runs.count - 1].style.strikethrough = s.strike ?? false
                        if let b = s.baseline { runs[runs.count - 1].style.script = b > 0 ? .superscript : b < 0 ? .subscript : .normal }
                        runs[runs.count - 1].style.highlight = s.highlight
                        runs[runs.count - 1].style.shadow = s.shadow
                        if s.caps == "all" { runs[runs.count - 1].style.caps = true } else if s.caps == "small" { runs[runs.count - 1].style.smallCaps = true }
                    }
                    var style = RichParagraphStyle(spaceAfter: 0, lineSpacing: 1.0)
                    switch level.algn { case "ctr": style.alignment = .center; case "r": style.alignment = .right; default: break }
                    // Its spacing, as a text box's paragraph has it (aptia's
                    // cells, 6 pt before each paragraph, sat that much high).
                    let endMark: Double? = p.first("a:endParaRPr")?["sz"].flatMap(Double.init).map { $0 / 100 }
                    let size: Double = runs.first?.style.fontSize ?? endMark ?? level.size ?? 18
                    if let m = level.lineMultiple { style.lineSpacing = m } else if let pts = level.linePoints { style.lineHeightPoints = pts }
                    // (None before a cell's first paragraph, as none before a
                    // body's: aptia's empty first line and the text under it
                    // both say 6 pt, and the text is 6 lower, not 12.)
                    style.spaceBefore = cellParas.isEmpty ? 0 : level.beforePoints ?? (level.beforePercent.map { $0 * size * 1.2 } ?? 0)
                    style.spaceAfter = level.afterPoints ?? (level.afterPercent.map { $0 * size * 1.2 } ?? 0)
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
                        // The file's own text edge and bullet offset when it
                        // says them (the bullet's offset against the 18 pt
                        // slot, as a shape's): the AES tables' "•" at marL 0,
                        // 36 and 72, indent 0, stand at the cell's edge, half
                        // an inch and an inch in, each with its text right
                        // after it, where all three hung 18 pt before the
                        // text.
                        if level.marL != nil || level.indent != nil {
                            style.indentLeft = level.marL ?? 0
                            style.firstLineIndent = (level.indent ?? 0) + 18
                        }
                        // The cell's own bullet, as a shape's: the AES
                        // tables' "•" at every level, where the layout's
                        // own drew "◦" below the first.
                        if level.bullet == .char { style.bulletText = level.bulletGlyph }
                        style.bulletColor = level.bulletColor
                        style.bulletScale = level.bulletScale
                        // In its own face, as a shape's: AES 2011's Arial
                        // "•" before Verdana text is Arial's 4.9 pt at 14,
                        // where Verdana's 6.9 pushed "that tell" apart.
                        if level.bullet == .char, let f = level.bulletFont,
                           !["wingdings", "symbol", "webdings"].contains(where: { f.lowercased().hasPrefix($0) }) {
                            style.bulletFontFamily = _font(f)
                        }
                        if level.bullet == .char, level.bulletFont?.lowercased() == "wingdings", style.bulletText == "●" {
                            style.bulletStandInFamily = OfficeFonts.calibri
                            style.bulletStandInScale = 0.565 / 0.46
                        }
                    default:
                        break
                    }
                    // An empty paragraph is as tall as its end mark says
                    // (`endParaRPr`): a row grows for 96 pt of nothing
                    // (tdf144092), as it would for a letter that size.
                    let end = p.first("a:endParaRPr").map { LevelStyle.run($0, colors) }
                    var para = text.isEmpty
                        ? RichParagraph(text: "", runs: [Run(length: 0, style: CharStyle(bold: end?.bold ?? look.bold ?? false,
                                                                                          fontFamily: _font(end?.font ?? look.font),
                                                                                          fontSize: end?.size ?? look.size ?? 18, color: look.color))], style: style)
                        : RichParagraph(text: text, runs: runs, style: style)
                    para.cell = cell
                    cellParas.append(para)
                }
                if cellParas.isEmpty {
                    var para = RichParagraph(text: "", style: RichParagraphStyle(spaceAfter: 0, lineSpacing: 1.0))
                    para.cell = cell
                    cellParas = [para]
                } else if cellNumbering.contains(where: { $0 != nil }), cellLevels.count == cellParas.count {
                    // A cell numbers its own paragraphs, from its own
                    // `startAt`: customGeo's crosswalk counts 1 to 6 down
                    // six cells, each starting where the last left off.
                    var own = RichDocument(paragraphs: cellParas)
                    Self._numberRuns(&own, levels: cellLevels, numbering: cellNumbering, prefix: "pptx-\(tableId)-\(r)-\(column)")
                    cellParas = own.paragraphs
                    for (k, v) in own.listFormats { cellListFormats[k] = v }
                    for (k, v) in own.listRestarts { cellListRestarts[k] = v }
                }
                paragraphs += cellParas
            }
            // A row short of the grid's columns (a span with no merged
            // cells after it) is filled out with empty cells, in the
            // table's own lines: LIBRE_OFFICE-100610's survey row ends in
            // two such, ruled black in PowerPoint's print.
            // (Their lines over a neighbour's own: the survey's two are
            // closed at the top, under the title cell's white edge.)
            let gridded = plain && (styleId.isEmpty || styleId.hasPrefix("{5940675A"))
            while !widths.isEmpty, column < widths.count {
                var para = RichParagraph(text: "", style: RichParagraphStyle(spaceAfter: 0, lineSpacing: 1.0))
                var cell = CellRef(table: tableId, row: r, column: column, span: 1, rowSpan: 1)
                if gridded {
                    let edge = CellRef.CellLine(width: 1, color: colors.scheme("tx1") ?? Color(0xFF000000))
                    cell.borders.left = edge; cell.borders.right = edge; cell.borders.top = edge; cell.borders.bottom = edge
                }
                para.cell = cell
                paragraphs.append(para)
                column += 1
            }
        }
        guard !paragraphs.isEmpty else { return nil }
        var doc = RichDocument(paragraphs: paragraphs)
        for (k, v) in cellListFormats { doc.listFormats[k] = v }
        for (k, v) in cellListRestarts { doc.listRestarts[k] = v }
        if !widths.isEmpty { doc.tableColumns[tableId] = widths }
        // The rows' own heights (`a:tr h`), as minimums: PowerPoint keeps a
        // row that tall however little is in it.
        let rowHeights = tbl.all("a:tr").map { ($0["h"].flatMap(Double.init) ?? 0) / Pptx.emu }
        let accent = theme.colors["accent1"] ?? Color(0xFF4472C4)
        var tableGradient: SlideFill? = nil
        var ts = plain
            ? TableStyle(borders: styleId.isEmpty || styleId.hasPrefix("{5940675A"), headerRow: false, borderColor: colors.scheme("tx1"))
            : TableStyle(borders: true, headerRow: firstRow, headerFill: accent,
                         bandFill: banded ? DeckController.tint(accent, 0.40) : nil,
                         bandAltFill: banded ? DeckController.tint(accent, 0.20) : nil,
                         borderColor: Color(0xFFFFFFFF))
        // A table with no style (or "Table Grid") is ruled in 1 pt black,
        // as PowerPoint draws tdf135843_export's grid, not the editor's ½.
        if plain, ts.borders { ts.borderWidth = 1 }
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
                        // The theme's gradient runs over the whole table,
                        // under its cells, and a band's tint lies on it as
                        // it is: bnc480256's "Themed Style" tables shade
                        // from top to bottom across their rows. (Where the
                        // gradient does not read, its middle colour under
                        // every cell, as before.)
                        if let gradient = PptxReader.gradient(theme.fillStyles[idx - 1], colors: c), gradient.stops.count >= 2 {
                            tableGradient = gradient
                            under = nil
                        } else {
                            let stops = theme.fillStyles[idx - 1].first("a:gsLst")?.all("a:gs").compactMap { c.color(in: $0) } ?? []
                            under = stops.isEmpty ? c.placeholder : stops[stops.count / 2]
                        }
                    } else {
                        under = colors.color(in: ref)
                    }
                } else if let f = bg.first("a:fill") {
                    under = f.first("a:solidFill").flatMap(colors.color(in:))
                }
            }
            // (No fill under the cells is nothing to lay a tint over: a
            // style whose cells say `a:noFill` and that has no table
            // background had its 20% band mixed with black.)
            if let u = under, u.a < 0.002 { under = nil }
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
            if let e = whole?.edges { ts.edges = e }
            if let w = whole?.borderWidth { ts.borderWidth = w }
        }
        for (r, h) in rowHeights.enumerated() where h > 0 { ts.rowHeights[r] = h }
        doc.tableStyles[tableId] = ts
        var st = ShapeState(id: id(), name: el.descendant("p:cNvPr")?["name"] ?? "Table", kind: .table, frame: frame,
                            rotation: 0, fill: nil, outline: nil, outlineWidth: 0, anchor: .top,
                            insets: EdgeInsets(left: 0, top: 0, right: 0, bottom: 0), prompt: nil, text: doc,
                            font: _font(base.font), size: base.size ?? 18, color: base.color ?? colors.scheme("tx1") ?? Color(0xFF000000),
                            listIndent: 18)
        st.fillStyle = tableGradient
        // The table's own fill (a fill in `a:tblPr`), behind every cell:
        // tdf127237's cells all say no fill, and stand on the table's blue.
        if let pr = tbl.first("a:tblPr") {
            if let solid = pr.first("a:solidFill"), let c = colors.color(in: solid) {
                st.fill = c
            } else if let g = pr.first("a:gradFill"), let gradient = PptxReader.gradient(g, colors: colors), gradient.stops.count >= 2 {
                st.fillStyle = gradient
            }
        }
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
              let space = package.xml(rel.target).map(ChartXML.canonical) else { return nil }
        // A chart pasted from another file brings that file's colours with
        // it: a theme override part, whose scheme stands in for the deck's
        // wherever the chart says `schemeClr` (tdf149985's greens, where
        // the deck's own accents are Office's blue and orange).
        var colors = colors
        // (So does one on a slide whose master has another theme: aascu
        // 5864's charts under the Office theme, drawn in Concourse's.)
        var overridden = foreignTheme
        // (And its own fonts: aascu 5864's employment chart, under a
        // master in Lucida Sans Unicode, is Calibri by its override.)
        var overrideFont: String?
        if let over = package.rels(rel.target).first(where: { $0.kind == "themeOverride" && !$0.external }),
           let face = package.xml(over.target)?.descendant("a:minorFont")?.first("a:latin")?["typeface"], !face.isEmpty {
            overrideFont = face
        }
        if let over = package.rels(rel.target).first(where: { $0.kind == "themeOverride" && !$0.external }),
           let scheme = package.xml(over.target)?.descendant("a:clrScheme") {
            overridden = true
            for child in scheme.children {
                let name = String(child.name.drop { $0 != ":" }.dropFirst())
                if let c = child.first("a:srgbClr")?["val"].flatMap(PptxTheme.hex)
                    ?? child.first("a:sysClr")?["lastClr"].flatMap(PptxTheme.hex) {
                    colors.theme.colors[name] = c
                }
            }
        }
        // The chart's own colour map, over the slide's: chart_pt_color_bg1's
        // slide swaps bg1 for dark, its chart keeps bg1 light, and its
        // `bg1 lumMod 85%` slice is light grey in PowerPoint's print.
        if let map = space.first("c:clrMapOvr") { for (k, v) in map.attrs { colors.map[k] = v } }
        guard var chart = ChartXML.read(space, color: { colors.color(in: $0) }),
              var frame = el.first("p:xfrm").flatMap(_xfrmRect) else { return nil }
        // A chart that names no face is in its own slide's theme font — a
        // deck of several masters (aascu 5864's census charts, Calibri;
        // cooper's, Verdana) was drawn in the first master's.
        if chart.font == nil, let face = overrideFont ?? (foreignTheme ? theme.minor : nil) {
            chart.font = face
            if chart.titleFont == nil { chart.titleFont = chart.font }
        }
        if overridden {
            // A series that names a theme slot, or leaves its colour to the
            // cycle, is drawn against the deck's theme — which is not this
            // chart's. Each gets the colour it has in the chart's own.
            let accents = (1 ... 6).compactMap { colors.scheme("accent\($0)") }
            if chart.type.isPie, accents.count == 6 {
                for i in chart.categories.indices where chart.pointColors[i] == nil { chart.pointColors[i] = chart.pointColor(i, accents: accents) }
            }
            for i in chart.series.indices where chart.series[i].color == nil {
                if let slot = chart.series[i].scheme { chart.series[i].color = colors.scheme(slot) }
                else if accents.count == 6 { chart.series[i].color = chart.color(series: i, accents: accents) }
                if chart.series[i].color != nil { chart.series[i].scheme = nil }
            }
        }
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
                f.imageLevels = PptxReader.blipLevels(blip)
                f.imageInset = PptxReader.stretchInset(b)
                // Tiled as a shape's picture fill is (chart-texture-bg's
                // paper at its own size, where it was one sheet stretched).
                if b.first("a:tile") != nil {
                    PptxReader.tile(b.first("a:tile"), image: package.parts[img.target], into: &f)
                }
                st.fillStyle = f
            } else if let f = pr.first("a:solidFill"), let c = colors.color(in: f) {
                st.fillStyle = SlideFill(color: c)
            }
            // The chart area's outline.
            if let ln = pr.first("a:ln"), !ln.has("a:noFill"), let f = ln.first("a:solidFill"), let c = colors.color(in: f) {
                st.outline = c
                st.outlineWidth = ln["w"].flatMap(Double.init).map { $0 / Pptx.emu } ?? 0.75
            }
        }
        // The chart's own drawing (`c:userShapes`): shapes placed in the
        // chart's frame by fractions of it, or by an offset and size —
        // tdf149985's grey oval over its last bar. Drawn over the chart,
        // never written (the chart part keeps them).
        if let us = package.rel(rel.target, kind: "chartUserShapes"), let drawing = package.xml(us.target) {
            func renamed(_ n: XNode) -> XNode {
                let name = n.name.hasPrefix("cdr:") ? "p:" + n.name.dropFirst(4) : n.name
                let c = XNode(name: name, attrs: n.attrs)
                c.text = n.text
                c.children = n.children.map(renamed)
                return c
            }
            func at(_ n: XNode?) -> Offset? {
                guard let x = n?.first("cdr:x").flatMap({ Double($0.text) }), let y = n?.first("cdr:y").flatMap({ Double($0.text) }) else { return nil }
                return Offset(x, y)
            }
            for anchor in drawing.children {
                let target: Rect
                if anchor.name == "cdr:relSizeAnchor", let a = at(anchor.first("cdr:from")), let b = at(anchor.first("cdr:to")) {
                    target = Rect.fromLTRB(frame.left + a.dx * frame.width, frame.top + a.dy * frame.height,
                                           frame.left + b.dx * frame.width, frame.top + b.dy * frame.height)
                } else if anchor.name == "cdr:absSizeAnchor", let a = at(anchor.first("cdr:from")),
                          let cx = anchor.first("cdr:ext")?["cx"].flatMap(Double.init), let cy = anchor.first("cdr:ext")?["cy"].flatMap(Double.init) {
                    target = Rect.fromLTWH(frame.left + a.dx * frame.width, frame.top + a.dy * frame.height, cx / Pptx.emu, cy / Pptx.emu)
                } else { continue }
                guard let child = anchor.children.first(where: { ["cdr:sp", "cdr:grpSp", "cdr:cxnSp"].contains($0.name) }) else { continue }
                let shape = renamed(child)
                // Its own box (the group's, or the shape's), laid onto the anchor's.
                let own = (shape.first("p:spPr") ?? shape.first("p:grpSpPr"))?.first("a:xfrm").flatMap(_xfrmRect)
                let map: (Rect) -> Rect = { r in
                    guard let own, own.width > 0, own.height > 0 else { return target }
                    let sx = target.width / own.width, sy = target.height / own.height
                    return Rect.fromLTWH(target.left + (r.left - own.left) * sx, target.top + (r.top - own.top) * sy, r.width * sx, r.height * sy)
                }
                let tree = XNode(name: "p:spTree", attrs: [:])
                tree.children = [shape]
                shapes(in: tree, transform: map, into: &st.chartDrawing, id: id)
            }
        }
        return st
    }

    /// A SmartArt's drawing part (`dsp:drawing`, reached from the data
    /// part's `dsp:dataModelExt relId`) as shapes at `frame`: its elements
    /// are DrawingML shapes under another prefix, so they read as `p:` ones.
    private static let customTextId = -125551
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
            // A point whose text size the author set (`custT`): its shape is
            // marked here (the drawing's ids are all 0) and keeps that size
            // below, overflowing or not.
            var custom: Set<String> = [], owner: [String: String] = [:]
            for pt in data.first("dgm:ptLst")?.all("dgm:pt") ?? [] {
                guard let id = pt["modelId"], let pr = pt.first("dgm:prSet") else { continue }
                if pr["custT"] == "1" { custom.insert(id) }
                if let o = pr["presAssocID"] { owner[id] = o }
            }
            // (And a shape that shows such a point's text by a `presOf`
            // connection, whoever it belongs to: tdf145528's centre tile,
            // the document's, shows the 72 pt "☺" and keeps it.)
            for cxn in data.first("dgm:cxnLst")?.all("dgm:cxn") ?? [] where cxn["type"] == "presOf" {
                if let src = cxn["srcId"], let dst = cxn["destId"], custom.contains(src) { custom.insert(dst) }
            }
            for sp in tree?.all("p:sp") ?? [] {
                guard let id = sp["modelId"], custom.contains(id) || owner[id].map(custom.contains) == true else { continue }
                sp.descendant("p:cNvPr")?.attrs["id"] = String(Self.customTextId)
            }
        } else if let (_, layoutDef) = related("r:lo") {
            // No drawing (a deck LibreOffice saved): laid out here from the
            // data and the layout definition.
            tree = DiagramLayout.render(data: data, layout: layoutDef, colors: related("r:cs")?.1, style: related("r:qs")?.1,
                                        frame: Rect.fromLTWH(0, 0, frame.width, frame.height))
            // Its pictures are the data's (`r:embed` in a point's fill
            // names the data part's relationship): picture-strip's
            // numbered tabs were looked for among the slide's, and drawn
            // as nothing.
            drawingPart = dataPart
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
                               colors: colors, theme: theme, defaults: defaults, slideSize: slideSize, images: images,
                               unsaidKern: unsaidKern)
        var out: [ShapeState] = []
        ctx.shapes(in: tree, transform: { r in r.shift(Offset(frame.left, frame.top)) }, into: &out, id: id)
        out = out.flatMap { s -> [ShapeState] in
            guard let box = s.uprightBox, s.text != nil else { return [s] }
            var shape = s
            shape.text = nil
            shape.uprightBox = nil
            var text = s
            text.id = id()
            text.kind = .textBox
            text.frame = box
            text.rotation = 0
            text.flipH = false
            text.flipV = false
            text.fill = nil
            text.fillStyle = nil
            text.outline = nil
            text.customPath = nil
            text.shadow = nil
            text.glowRadius = nil
            text.softEdge = nil
            text.scene3d = nil
            text.shapeInsets = .zero
            text.insets = s.uprightInsets
            text.uprightBox = nil
            return [shape, text]
        }
        // A preset this app has no outline for is drawn as a box, which
        // serves for the rounded and snipped rectangles diagrams favour but
        // not for a gear (gear6, gear9): those are left out.
        // The drawing part caches one layout of the text; PowerPoint fits it
        // to the shapes afresh, so every text shrinks to fit here too —
        // but for one at a size its author set, which PowerPoint leaves
        // alone (tdf125551's 32 pt labels run out of their bars).
        for i in out.indices where out[i].text != nil && out[i].fileId != Self.customTextId { out[i].autofit = true }
        for i in out.indices where out[i].text != nil { out[i].naturalLines = true }
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
        /// Which of its six rules it draws, and their width (points),
        /// where its `a:tcBdr` names each side.
        var edges: BorderEdges? = nil
        var borderWidth: Double? = nil
        /// `a:tcTxStyle`'s face: a theme slot (`fontRef idx`) or a name.
        var font: String? = nil
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
                var shown: [String: Bool] = [:]
                for side in ["a:insideH", "a:insideV", "a:left", "a:right", "a:top", "a:bottom"] {
                    if let ref = bdr.first(side)?.first("a:lnRef") {
                        // The theme's line style in the referred colour.
                        if ref["idx"] == "0" { shown[side] = false; continue }
                        visible = true
                        shown[side] = true
                        if r.borderColor == nil { r.borderColor = colors.color(in: ref) }
                        continue
                    }
                    guard let ln = bdr.first(side)?.first("a:ln") else { continue }
                    if ln.has("a:noFill") { shown[side] = false; continue }
                    visible = true
                    shown[side] = true
                    if r.borderColor == nil, let f = ln.first("a:solidFill") { r.borderColor = colors.color(in: f) }
                    if r.borderWidth == nil, let w = ln["w"].flatMap(Double.init) { r.borderWidth = w / Pptx.emu }
                }
                r.borders = visible
                // Each side as it says (a side it leaves out has no rule:
                // tdf135843_insideH's rows ruled, its columns not).
                if visible {
                    r.edges = BorderEdges(top: shown["a:top"] ?? false, left: shown["a:left"] ?? false,
                                          bottom: shown["a:bottom"] ?? false, right: shown["a:right"] ?? false,
                                          insideH: shown["a:insideH"] ?? false, insideV: shown["a:insideV"] ?? false)
                }
            }
        }
        if let tx = part.first("a:tcTxStyle") {
            r.textColor = colors.color(in: tx)
            switch tx["b"] { case "on": r.bold = true; case "off": r.bold = false; default: break }
            if let idx = tx.first("a:fontRef")?["idx"] { r.font = idx == "major" ? "+mj-lt" : "+mn-lt" }
            if let name = tx.first("a:font")?.first("a:latin")?["typeface"] { r.font = name }
        }
        return r
    }

    /// A shape's or picture's outer shadow: its own effects', or — saying
    /// none — its style's theme effect (`effectRef`, the referred colour
    /// as `phClr`), as Office 2007's themes give every shape one.
    /// A shape's inner shadow, its own or its style's.
    /// A shape's top bevel: its own `a:sp3d`, else its theme effect
    /// style's (`effectRef`) — the Office 2007 theme's intense effect, a
    /// 5 × 2 pt bevel under a three-point light. Nil for none, or one of
    /// no width.
    private func _shapeBevel(_ spPr: XNode?, _ style: XNode?) -> ShapeBevel? {
        func read(_ sp3d: XNode?, _ scene: XNode?) -> ShapeBevel? {
            guard let bev = sp3d?.first("a:bevelT") else { return nil }
            let w = (bev["w"].flatMap(Double.init) ?? 76200) / Pptx.emu, h = (bev["h"].flatMap(Double.init) ?? 76200) / Pptx.emu
            guard w > 0.1, h > 0 else { return nil }
            var b = ShapeBevel(width: w, height: h)
            if let rig = scene?.first("a:lightRig")?["rig"] { b.rig = rig }
            if let m = sp3d?["prstMaterial"] { b.material = m }
            return b
        }
        if let spPr, spPr.first("a:sp3d") != nil || spPr.first("a:scene3d") != nil {
            return read(spPr.first("a:sp3d"), spPr.first("a:scene3d"))
        }
        guard let ref = style?.first("a:effectRef"), let idx = ref["idx"].flatMap(Int.init), idx > 0,
              theme.effectStyles.indices.contains(idx - 1) else { return nil }
        let effect = theme.effectStyles[idx - 1]
        return read(effect.first("a:sp3d"), effect.first("a:scene3d"))
    }

    private func _shapeInnerShadow(_ spPr: XNode?, _ style: XNode?) -> CharShadow? {
        func read(_ effects: XNode?, _ c: ColorContext) -> CharShadow? {
            guard let sh = effects?.first("a:innerShdw"), let color = c.color(in: sh) else { return nil }
            let dist = (sh["dist"].flatMap(Double.init) ?? 0) / Pptx.emu
            let dir = (sh["dir"].flatMap(Double.init) ?? 0) / 60000 * .pi / 180
            return CharShadow(color: color, dx: dist * cos(dir), dy: dist * sin(dir),
                              blur: (sh["blurRad"].flatMap(Double.init) ?? 0) / Pptx.emu)
        }
        if let own = spPr?.first("a:effectLst") { return read(own, colors) }
        if spPr?.first("a:effectDag") != nil { return nil }
        guard let ref = style?.first("a:effectRef"), let idx = ref["idx"].flatMap(Int.init), idx > 0,
              theme.effectStyles.indices.contains(idx - 1) else { return nil }
        var c = colors
        c.placeholder = colors.color(in: ref)
        return read(theme.effectStyles[idx - 1].first("a:effectLst"), c)
    }

    private func _shapeShadow(_ spPr: XNode?, _ style: XNode?) -> CharShadow? {
        if let own = spPr?.first("a:effectLst") { return LevelStyle.outerShadow(own, colors) }
        if spPr?.first("a:effectDag") != nil { return nil }
        guard let ref = style?.first("a:effectRef"), let idx = ref["idx"].flatMap(Int.init), idx > 0,
              theme.effectStyles.indices.contains(idx - 1) else { return nil }
        var c = colors
        c.placeholder = colors.color(in: ref)
        return LevelStyle.outerShadow(theme.effectStyles[idx - 1].first("a:effectLst"), c)
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
        /// A diagram laid out here: the shapes that end at one size.
        var sizeGroup: String? = nil
        /// `bodyPr wrap="none"`.
        var noWrap = false
        /// `bodyPr anchorCtr="1"`.
        var anchorCentred = false
        /// `bodyPr vert`: 1 a quarter clockwise, -1 anticlockwise.
        var textTurn = 0
        /// The text's camera turned about its axis (`scene3d/camera/rot
        /// rev`), degrees clockwise.
        var textSpin = 0.0
        /// `bodyPr numCol` and `spcCol` (points).
        var columns = 1
        var columnGap = 0.0
        var warp: TextWarp? = nil
        var runLooks: [[RunLook]] = []
    }

    /// The master text style a placeholder (or plain shape) draws from.
    /// A master that has no title or body style (one written by another
    /// program: subtitle-animation-save's has no `p:txStyles` at all)
    /// leaves PowerPoint's own: a title at 44 pt in the heading face, a
    /// body at 28 with a "•", both at 90% line spacing.
    private func _masterStyle(_ ph: XNode?) -> XNode? {
        let styles = master?.first("p:txStyles")
        guard let ph else { return nil }
        switch ph["type"] ?? "obj" {
        case "title", "ctrTitle": return styles?.first("p:titleStyle") ?? Self.builtInTitleStyle
        // (A content placeholder, `p:ph` with no type, does not take the
        // built-in bullet: outliner-list-style's unbulleted first level.)
        case "body", "subTitle": return styles?.first("p:bodyStyle") ?? Self.builtInBodyStyle
        case "obj": return styles?.first("p:bodyStyle") ?? Self.builtInContentStyle
        // (Text typed into a picture placeholder is body text: 28 pt in
        // pic-placeholder-with-text's print, where the other style's 18
        // stood. Its kin — table, chart, clip art, diagram, media — read so
        // too.)
        case "pic", "tbl", "chart", "clipArt", "dgm", "media": return styles?.first("p:bodyStyle") ?? Self.builtInContentStyle
        default: return styles?.first("p:otherStyle")
        }
    }

    private static let builtInTitleStyle = MiniXML.parse(Array("""
        <p:titleStyle><a:lvl1pPr><a:lnSpc><a:spcPct val="90000"/></a:lnSpc><a:spcBef><a:spcPct val="0"/></a:spcBef>\
        <a:buNone/><a:defRPr sz="4400"><a:solidFill><a:schemeClr val="tx1"/></a:solidFill><a:latin typeface="+mj-lt"/>\
        <a:ea typeface="+mj-ea"/><a:cs typeface="+mj-cs"/></a:defRPr></a:lvl1pPr></p:titleStyle>
        """.utf8))
    private static let builtInContentStyle = MiniXML.parse(Array("""
        <p:bodyStyle><a:lvl1pPr><a:lnSpc><a:spcPct val="90000"/></a:lnSpc>\
        <a:defRPr sz="2800"><a:solidFill><a:schemeClr val="tx1"/></a:solidFill>\
        <a:latin typeface="+mn-lt"/><a:ea typeface="+mn-ea"/><a:cs typeface="+mn-cs"/></a:defRPr></a:lvl1pPr></p:bodyStyle>
        """.utf8))
    private static let builtInBodyStyle = MiniXML.parse(Array("""
        <p:bodyStyle><a:lvl1pPr><a:lnSpc><a:spcPct val="90000"/></a:lnSpc><a:spcBef><a:spcPts val="1000"/></a:spcBef>\
        <a:buFont typeface="Arial"/><a:buChar char="&#8226;"/><a:defRPr sz="2800"><a:solidFill><a:schemeClr val="tx1"/></a:solidFill>\
        <a:latin typeface="+mn-lt"/><a:ea typeface="+mn-ea"/><a:cs typeface="+mn-cs"/></a:defRPr></a:lvl1pPr></p:bodyStyle>
        """.utf8))

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
        // (Each layer's picture bullet from its own part.)
        let layoutPart = package.rel(part, kind: "slideLayout")?.target
        let masterPart = layoutPart.flatMap { package.rel($0, kind: "slideMaster")?.target }
        func pictures(_ owner: String?) -> (String) -> ImageAttachment? {
            { rid in
                guard let owner, let rel = self.package.rels(owner).first(where: { $0.id == rid }), !rel.external,
                      self.package.parts[rel.target] != nil else { return nil }
                return self.images.attachment(rel.target, self.package)
            }
        }
        let owners: [String?] = ph == nil ? [part, nil, masterPart] : [part, layoutPart, masterPart, masterPart, nil]
        var s = LevelStyle()
        for (k, layer) in layers.enumerated() {
            s = s.filled(from: LevelStyle.paragraph(layer, colors, picture: pictures(k < owners.count ? owners[k] : nil)))
        }
        return s
    }

    /// The face a complex script's letters are set in: the run's `a:cs`,
    /// a theme reference's complex-script face, else the theme's face for
    /// that script — nil where nothing names one (the Latin face serves).
    private func _csFont(_ f: String?, script: String) -> String? {
        switch f {
        case nil, "+mn-cs", "+mn-lt", "+mn-ea": return theme.minorScript["cs"] ?? theme.minorScript[script]
        case "+mj-cs", "+mj-lt", "+mj-ea": return theme.majorScript["cs"] ?? theme.majorScript[script]
        default: return f
        }
    }

    /// A run's spacing for a face drawn by a stand-in of other widths,
    /// in a text box and in a table cell alike.
    static func faceSpacing(_ cs: inout CharStyle) {
        // Arial Black, which no face shipped here has: drawn in the
        // stand-in's bold, at Arial Black's own widths (`SlideFonts.face`)
        // — the plain face left "TRADE SHOW" on one line where PowerPoint
        // breaks it in two. (Segoe UI, Tahoma, Franklin Gothic and the
        // rest have their own widths there too.)
        if cs.fontFamily?.lowercased() == "arial black" {
            cs.bold = true
        }
        // Aptos, set in Liberation Sans: that much tighter, as
        // Aptos runs narrower — PowerPoint's lines in it are 3.5%
        // shorter than ours across the twelve Aptos decks, 5.5% in
        // bold (28 lines compared).
        if cs.fontFamily?.lowercased() == "aptos" {
            cs.letterSpacing = (cs.letterSpacing ?? 0) - (cs.bold ? 0.031 : 0.0185) * (cs.fontSize ?? 18)
        }
        // Calibri Light, set in Calibri's regular: 0.0054 em a letter
        // tighter — PowerPoint's lines in it are 1.2 to 1.6% shorter than
        // ours, the same in all twenty decks (69 lines compared). (Its own
        // widths, `SlideFontWidths.calibriLight`, came out worse: a face
        // set at its own widths is not kerned here, and its titles are.)
        if cs.fontFamily?.lowercased() == "calibri light" {
            cs.letterSpacing = (cs.letterSpacing ?? 0) - 0.0054 * (cs.fontSize ?? 18)
        }
        // Consolas, set in Liberation Mono: 0.55 em a letter, not
        // 0.6 (lines 8.7% wide).
        if cs.fontFamily?.lowercased() == "consolas" {
            cs.letterSpacing = (cs.letterSpacing ?? 0) - 0.05 * (cs.fontSize ?? 18)
        }
    }

    /// The complex script a character is written in (the theme's key for
    /// it), nil for any other.
    static func complexScript(_ v: UInt32) -> String? {
        switch v {
        case 0x0590 ... 0x05FF, 0xFB1D ... 0xFB4F: return "Hebr"
        case 0x0600 ... 0x06FF, 0x0750 ... 0x077F, 0xFB50 ... 0xFDFF, 0xFE70 ... 0xFEFF: return "Arab"
        case 0x0E00 ... 0x0E7F: return "Thai"
        default: return nil
        }
    }

    /// A face PowerPoint does not kern, whatever `kern` says: it kerns
    /// by a face's `kern` table, and these have none — Work Sans and
    /// Poppins kern only in their OpenType layout (tdf140852's "Training"
    /// and lo-master-slides' "Avoid" at their plain widths in
    /// PowerPoint's print, where ours were 4 and 1.5 pt shorter), Tahoma
    /// Bold too, and Century Gothic not at all (its stand-in does).
    static func _unkerned(_ family: String?, bold: Bool) -> Bool {
        guard let n = family?.trimmingWhitespace().lowercased() else { return false }
        return n.hasPrefix("work sans") || n.hasPrefix("poppins") || n.hasPrefix("century gothic") || (bold && n == "tahoma")
    }

    /// Whether the first strong letter of `text` is Hebrew or Arabic
    /// (a letter, not a digit or a mark, before any Latin one).
    static func _startsRightToLeft(_ text: String) -> Bool {
        for u in text.unicodeScalars {
            switch u.value {
            case 0x0590 ... 0x08FF, 0xFB1D ... 0xFDFF, 0xFE70 ... 0xFEFF:
                if u.properties.isAlphabetic { return true }
            default:
                if u.properties.isAlphabetic { return false }
            }
        }
        return false
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
        let noWrapBody = bodies.compactMap { $0?["wrap"] }.first == "none"
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
        // So does its face (`fontRef idx`): customGeo's boxes say "minor"
        // (Calibri) over a deck default of Arial, and PowerPoint sets them
        // in Calibri.
        let styleFont: String? = sp.first("p:style")?.first("a:fontRef")?["idx"].flatMap {
            $0 == "major" ? "+mj-lt" : $0 == "minor" ? "+mn-lt" : nil
        }
        func styled(_ l: LevelStyle, _ n: Int, _ pPr: XNode?) -> LevelStyle {
            var l = l
            let own = LevelStyle.paragraph(pPr, colors), listed = LevelStyle.paragraph(list?.first("a:lvl\(n + 1)pPr"), colors)
            if let sf = styleFont, own.font == nil, listed.font == nil { l.font = sf }
            guard let sc = styleColor, own.color == nil, listed.color == nil else { return l }
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
        var runLooks: [[RunLook]] = []
        var paragraphs: [RichParagraph] = []
        let allParagraphs = body?.all("a:p") ?? []
        // Each paragraph's level and numbering scheme, for the runs of
        // numbers below.
        var paragraphLevels: [Int] = []
        var numbering: [(type: String, start: Int)?] = []
        for p in allParagraphs {
            let pPr = p.first("a:pPr")
            let lvl = pPr?["lvl"].flatMap(Int.init) ?? 0
            let picture: (String) -> ImageAttachment? = { rid in
                guard let rel = self.package.rels(self.part).first(where: { $0.id == rid }), !rel.external,
                      self.package.parts[rel.target] != nil else { return nil }
                return self.images.attachment(rel.target, self.package)
            }
            let level = styled(LevelStyle.paragraph(pPr, colors, picture: picture).filled(from: _level(lvl, shapeList: list, ph: ph, inherited: inherited)), lvl, pPr)
            // What a percentage of spacing is a percentage of: the size the
            // paragraph's runs are actually set in (a SmartArt label is 31 pt
            // by its runs under a level that says nothing), else the level's.
            let runSizes = p.all("a:r").compactMap { $0.first("a:rPr")?["sz"].flatMap(Double.init).map { $0 / 100 } }
            // (An empty paragraph's by its end mark: alterman's 24 pt blank
            // lines under a 28 pt level, each 1.3 pt further apart.)
            let endSize = p.all("a:r").isEmpty ? p.first("a:endParaRPr")?["sz"].flatMap(Double.init).map { $0 / 100 } : nil
            let size = runSizes.max() ?? endSize ?? level.size ?? 18
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
            } else {
                style.lineSpacingUnstated = true
            }
            // (A percentage is of the text as drawn: under PowerPoint's own
            // shrink to fit, `fontScale` of it — bug62513's 20% before its
            // 77.5% list items is 6 pt in the print, ours was 7.7.)
            style.spaceBefore = level.beforePoints ?? (level.beforePercent.map { $0 * size * scale * 1.2 } ?? 0)
            // A percentage after, as before: of the line, taken as 1.2 of the
            // size — but not under the last paragraph, where PowerPoint adds
            // nothing: counted there, a one-line SmartArt label (35% after,
            // every one) measured taller than its box and was shrunk to fit.
            if level.afterPoints == nil, let pct = level.afterPercent, p !== allParagraphs.last {
                style.spaceAfter = pct * size * scale * 1.2
            }
            // (Nor in points: bnc904423's centred boxes, 11.5 pt after their
            // one paragraph, stood 5.75 high.)
            if p === allParagraphs.last { style.spaceAfter = 0 }
            paragraphLevels.append(lvl)
            numbering.append(level.bullet == .number ? (level.autoNumType ?? "arabicPeriod", level.autoNumStart ?? 1) : nil)
            switch level.bullet {
            case .char?, .number?:
                style.list = level.bullet == .char ? .bullet : .numbered
                style.listLevel = lvl
                if level.bullet == .char { style.bulletText = level.bulletGlyph }
                if level.bullet == .char { style.bulletPicture = level.bulletPicture }
                style.bulletColor = level.bulletColor
                style.bulletScale = level.bulletScale
                // The bullet's own face — but not a symbol face, whose codes
                // were turned into the glyphs they show and are set in the
                // text's.
                if level.bullet == .char, let f = level.bulletFont,
                   !["wingdings", "symbol", "webdings"].contains(where: { f.lowercased().hasPrefix($0) }) {
                    style.bulletFontFamily = _font(f)
                }
                // Wingdings' round bullet, the commonest of them (46 decks),
                // is 0.565 of an em across and stands 0.09 above the
                // baseline: Carlito's "●" at 1.23 times is that, where the
                // text's own was three quarters of its size.
                if level.bullet == .char, level.bulletFont?.lowercased() == "wingdings", style.bulletText == "●" {
                    style.bulletStandInFamily = OfficeFonts.calibri
                    style.bulletStandInScale = 0.565 / 0.46
                }
                // The file's own text edge (marL) and bullet offset (indent):
                // the text placed where the file puts it, both written back
                // as read. The layout indents a list by the shape's list
                // indent per level; indentLeft carries the difference.
                if let marL = level.marL { style.indentLeft = marL - shapeIndent * Double(lvl + 1) }
                // As an offset from the usual hang (-shapeIndent), so 0 is
                // "the usual" and a file's indent="0" survives as itself.
                if let indent = level.indent { style.firstLineIndent = indent + shapeIndent }
                // A text edge with no offset said anywhere is offset 0, as
                // the format's default: aascu 5864's text boxes' "•" at
                // marL 0 stands at the edge with its text after it, where
                // it hung in the margin.
                else if level.marL != nil { style.firstLineIndent = shapeIndent }
                // Neither said anywhere (an export with no default text
                // style, ececapstone's): PowerPoint's own, half an inch a
                // level and no hang — the bullet at the edge, the text
                // after it.
                if level.marL == nil, level.indent == nil {
                    style.indentLeft = 36 * Double(lvl) - shapeIndent * Double(lvl + 1)
                    style.firstLineIndent = shapeIndent
                }
                SlideContext.hangPositiveIndent(&style, own: pPr?["indent"].flatMap(Double.init), indent: level.indent,
                                                marL: level.marL, shapeIndent: shapeIndent, level: lvl)
            default:
                style.indentLeft = level.marL ?? 0
                style.firstLineIndent = level.indent ?? 0
            }
            if let tabs = level.tabs { style.tabStops = tabs }

            var text = ""
            var runs: [Run] = []
            var looks: [RunLook] = []
            func add(_ t0: String, _ r: LevelStyle, _ rPr: XNode? = nil) {
                guard !t0.isEmpty else { return }
                // A symbol face's private-range codes as the glyphs they show
                // (`a:sym` Symbol, or the run's own face): GeomLec1's U+F0DE
                // is Symbol's "⇒", and drew as nothing.
                var t = t0
                if t.unicodeScalars.contains(where: { (0xF020 ... 0xF0FF).contains($0.value) }),
                   let face = rPr?.first("a:sym")?["typeface"] ?? rPr?.first("a:latin")?["typeface"] {
                    t = String(t.map { ch -> Character in
                        guard let v = ch.unicodeScalars.first?.value, (0xF020 ... 0xF0FF).contains(v) else { return ch }
                        let shown = Metafile.symbols(String(ch), face: face)
                        return shown == String(ch) ? ch : (shown.first ?? ch)
                    })
                }
                var look = _runLook(rPr) ?? RunLook()
                look.length = t.utf16.count
                looks.append(look)
                let s = r.filled(from: level)
                var cs = CharStyle(bold: s.bold ?? false, italic: s.italic ?? false,
                                   underline: s.underline ?? false, strikethrough: s.strike ?? false,
                                   fontFamily: _font(s.font), fontSize: ((s.size ?? 18) * 10).rounded() / 10,
                                   color: s.color ?? tx1)
                if let b = s.baseline { cs.script = b > 0 ? .superscript : b < 0 ? .subscript : .normal }
                if let spc = s.spc, spc != 0 { cs.letterSpacing = spc }
                // Kerned from the size `kern` says up (PowerPoint's own
                // masters say 12 pt); none where it says nothing.
                if Self._unkerned(cs.fontFamily, bold: cs.bold) { cs.kerningFrom = 0 } else { cs.kerningFrom = s.kern ?? unsaidKern }
                let plain = cs
                Self.faceSpacing(&cs)
                cs.shadow = s.shadow
                cs.highlight = s.highlight
                if s.caps == "all" { cs.caps = true } else if s.caps == "small" { cs.smallCaps = true }
                text += t
                // Hebrew, Arabic and Thai letters in the complex-script
                // face, as PowerPoint sets them: tdf98603's Hebrew title is
                // in the theme's Times New Roman for Hebrew (one line), not
                // Calibri Light's fallback (two). Spaces, digits and
                // punctuation go with the letters before them.
                let runsBefore = runs.count
                var pieces: [(length: Int, script: String?)] = []
                var sawLetter = false
                for ch in t.unicodeScalars {
                    let n = ch.utf16.count
                    let script = Self.complexScript(ch.value)
                    let letter = script != nil || ch.properties.isAlphabetic
                    if pieces.isEmpty {
                        pieces.append((n, script))
                        sawLetter = letter
                    } else if letter, !sawLetter {
                        // The first letter claims what came before it.
                        pieces[pieces.count - 1].script = script
                        pieces[pieces.count - 1].length += n
                        sawLetter = true
                    } else if letter, script != pieces[pieces.count - 1].script {
                        pieces.append((n, script))
                    } else {
                        pieces[pieces.count - 1].length += n
                    }
                }
                for piece in pieces {
                    var c = cs
                    if let script = piece.script, let face = _csFont(s.csFont, script: script), face != plain.fontFamily {
                        c = plain
                        c.fontFamily = face
                        c.shadow = cs.shadow; c.highlight = cs.highlight; c.caps = cs.caps; c.smallCaps = cs.smallCaps
                    }
                    if let last = runs.last, last.style == c, runs.count > runsBefore {
                        runs[runs.count - 1].length += piece.length
                    } else {
                        runs.append(Run(length: piece.length, style: c))
                    }
                }
            }
            for child in p.children {
                switch child.name {
                case "a:r": add(child.first("a:t")?.text ?? "", child.first("a:rPr").map { LevelStyle.run($0, colors) } ?? LevelStyle(), child.first("a:rPr"))
                case "a:br":
                    // In a box that does not wrap, a space just before the
                    // break is part of its line as PowerPoint centres and
                    // right-aligns it: cooper's "OVERVIEW OF THE ", 32 pt
                    // and centred, stands half a space left of where the
                    // engine, trimming it, put it. Kept as a no-break space,
                    // as wide, which it keeps. A wrapping box hangs it past
                    // the edge as at any wrap (cooper's slide 11 title, the
                    // same XML in a wrapping box, stands where trimmed).
                    if noWrapBody, text.hasSuffix(" ") { text = String(text.dropLast()) + "\u{00A0}" }
                    add("\n", child.first("a:rPr").map { LevelStyle.run($0, colors) } ?? LevelStyle())
                case "a:fld": add(child.first("a:t")?.text ?? "", child.first("a:rPr").map { LevelStyle.run($0, colors) } ?? LevelStyle(), child.first("a:rPr"))
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
                // A bullet before a link is in the text's own colour, not
                // the link's: customGeo's resources list has black bullets
                // before its blue links in PowerPoint's print.
                if style.list != nil, style.bulletColor == nil,
                   let first = p.children.first(where: { $0.name == "a:r" })?.first("a:rPr"),
                   let link = first.first("a:hlinkClick"), link.descendant("ahyp:hlinkClr")?["val"] != "tx" {
                    style.bulletColor = first.first("a:solidFill").flatMap { colors.color(in: $0) } ?? level.color ?? tx1
                }
                // Right to left where the paragraph says so, or where its
                // first strong letter is Hebrew or Arabic and it says
                // nothing itself: tdf98603's quoted Hebrew under a master
                // that says left to right, its opening quote at the right
                // in PowerPoint's print.
                let own = p.first("a:pPr")?["rtl"]
                if own == "1" || (own == nil && Self._startsRightToLeft(text)) { style.rightToLeft = true }
                paragraphs.append(RichParagraph(text: text, runs: runs, style: style))
            }
            runLooks.append(looks)
        }
        // Looks matter only where some run has one.
        if !runLooks.contains(where: { $0.contains { !$0.isPlain } }) { runLooks = [] }
        let warp: TextWarp? = (body?.first("a:bodyPr")?.first("a:prstTxWarp")).flatMap { w in
            guard let preset = w["prst"], preset != "textNoShape" else { return nil }
            let adjust = (w.first("a:avLst")?.all("a:gd") ?? []).compactMap { gd -> Double? in
                guard let f = gd["fmla"], f.hasPrefix("val ") else { return nil }
                return Double(f.dropFirst(4))
            }
            return TextWarp(preset: preset, adjust: adjust, xml: PptxXML.serialize(w))
        }
        if paragraphs.isEmpty {
            var style = RichParagraphStyle(spaceAfter: 0, lineSpacing: level0.lineMultiple ?? 1.0)
            style.alignment = level0.algn == "ctr" ? .center : level0.algn == "r" ? .right : .left
            if level0.bullet == .char { style.list = .bullet }
            paragraphs = [RichParagraph(text: "", style: style)]
        }
        // Tabs go to the next stop a default distance apart (`defTabSz`,
        // an inch unless the level says otherwise) from the text's left.
        var bodyDocument = RichDocument(paragraphs: paragraphs)
        Self._numberRuns(&bodyDocument, levels: paragraphLevels, numbering: numbering)
        bodyDocument.defaultTabStop = level0.defTab ?? 72
        var body0 = TextBody(document: bodyDocument, anchor: anchor, insets: insets,
                        font: _font(level0.font), size: level0.size ?? 18,
                        color: level0.color ?? tx1 ?? Color(0xFF000000),
                        listIndent: shapeIndent,
                        autofit: fitRule == "a:normAutofit", fontScale: fitRule == "a:normAutofit" ? scale : 1,
                        lineReduction: fitRule == "a:normAutofit" ? min(1, max(0, reduction)) : 0,
                        insetsFollowFont: body?.first("a:bodyPr")?["starling:insScale"] == "1",
                        noWrap: bodies.compactMap { $0?["wrap"] }.first == "none",
                        columns: max(1, min(16, attr("numCol").flatMap(Int.init) ?? 1)),
                        columnGap: attr("spcCol").flatMap(Double.init).map { $0 / Pptx.emu } ?? 0,
                        warp: warp, runLooks: runLooks)
        body0.sizeGroup = body?.first("a:bodyPr")?["starling:sizeGroup"]
        body0.anchorCentred = ["1", "true"].contains(attr("anchorCtr") ?? "")
        switch attr("vert") {
        case "vert", "eaVert", "mongolianVert": body0.textTurn = 1
        case "vert270": body0.textTurn = -1
        default: break
        }
        // A flat camera turned about its axis (`rev`, lat and lon nought)
        // turns the text the other way about its own middle: tdf128213's
        // "Vertical it should be!" at rev 90° reads upward from the box,
        // tdf128206's at 270° down its arrow.
        if let rot = body?.first("a:bodyPr")?.first("a:scene3d")?.first("a:camera")?.first("a:rot"),
           (rot["lat"].flatMap(Double.init) ?? 0) == 0, (rot["lon"].flatMap(Double.init) ?? 0) == 0,
           let rev = rot["rev"].flatMap(Double.init), rev != 0 {
            body0.textSpin = -rev / 60000
        }
        return body0
    }

    /// A run's WordArt look: a gradient or picture fill, no fill, an
    /// outline. Nil for a run that is plain coloured text.
    /// PowerPoint's runs of numbers: a level numbers on past deeper
    /// paragraphs, and starts again after a paragraph at its own level or
    /// shallower that is not numbered (or numbered another way) —
    /// NumberedList-12ab-ab-34's outer 3 and 4 after its sub-lists, whose
    /// second "a, b" follows an unnumbered line. Each run is a list of its
    /// own, in its scheme's format (a, b / i, ii / 1)…), from `startAt`.
    /// An empty paragraph shows no number and neither counts nor breaks.
    static func _numberRuns(_ doc: inout RichDocument, levels: [Int], numbering: [(type: String, start: Int)?],
                            prefix: String = "pptx") {
        guard numbering.contains(where: { $0 != nil }), levels.count == doc.paragraphs.count else { return }
        var broken = Array(repeating: true, count: 9), run = Array(repeating: 0, count: 9)
        var scheme = Array(repeating: "", count: 9)
        for i in doc.paragraphs.indices {
            let lvl = min(8, max(0, levels[i]))
            for deeper in (lvl + 1) ..< 9 { broken[deeper] = true }
            guard doc.paragraphs[i].style.list == .numbered, let n = numbering[i] else { broken[lvl] = true; continue }
            if doc.paragraphs[i].text.isEmpty {
                doc.paragraphs[i].style.listId = "\(prefix)-empty-\(i)"
                continue
            }
            let key = "\(n.type)/\(n.start)"
            if broken[lvl] || scheme[lvl] != key { run[lvl] += 1; broken[lvl] = false; scheme[lvl] = key }
            let id = "\(prefix)-\(lvl)-\(run[lvl])"
            doc.paragraphs[i].style.listId = id
            if doc.listFormats[id] == nil {
                let t = n.type.lowercased()
                let format: ListNumberFormat = t.hasPrefix("alphalc") ? .lowerLetter : t.hasPrefix("alphauc") ? .upperLetter
                    : t.hasPrefix("romanlc") ? .lowerRoman : t.hasPrefix("romanuc") ? .upperRoman : .decimal
                let counter = "%\(lvl + 1)"
                let text = t.hasSuffix("parenboth") ? "(\(counter))" : t.hasSuffix("parenr") ? "\(counter))"
                    : t.hasSuffix("plain") ? counter : "\(counter)."
                var levelsOf: [Int: ListLevelFormat] = [:]
                levelsOf[lvl] = ListLevelFormat(text: text, format: format)
                doc.listFormats[id] = levelsOf
                if n.start != 1 { doc.listRestarts[id] = [lvl: n.start] }
            }
        }
    }

    private func _runLook(_ rPr: XNode?) -> RunLook? {
        guard let rPr else { return nil }
        var look = RunLook()
        var any = false
        if rPr.has("a:noFill") { look.noFill = true; any = true }
        if let g = rPr.first("a:gradFill"), let f = PptxReader.gradient(g, colors: colors), f.stops.count >= 2 {
            look.fill = f; any = true
        } else if let b = rPr.first("a:blipFill"), let blip = b.first("a:blip"), let rid = blip["r:embed"],
                  let rel = package.rels(part).first(where: { $0.id == rid }), !rel.external,
                  package.parts[rel.target] != nil {
            var f = SlideFill(image: images.attachment(rel.target, package))
            (f.imageAlpha, f.duotone) = PptxReader.blipEffects(blip, colors: colors)
            f.imageLevels = PptxReader.blipLevels(blip)
            if b.first("a:tile") != nil || b.first("a:stretch") == nil {
                PptxReader.tile(b.first("a:tile"), image: package.parts[rel.target], into: &f)
            }
            look.fill = f; any = true
        }
        if let ln = rPr.first("a:ln"), !ln.has("a:noFill"), let c = ln.first("a:solidFill").flatMap(colors.color(in:)), c.alpha > 0 {
            look.outline = c
            look.outlineWidth = ln["w"].flatMap(Double.init).map { $0 / Pptx.emu } ?? 0.75
            any = true
        }
        return any ? look : nil
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
        var out: [UInt8] = []
        out.reserveCapacity(1024)
        _write(node, into: &out)
        return String(decoding: out, as: UTF8.self)
    }

    /// One buffer for the whole element. A string built per node and
    /// appended to its parent's copies every byte once per level it sits
    /// under, and a reader keeps the text of every shape: a slide of a
    /// megabyte of grouped drawing spent most of its opening here.
    private static func _write(_ node: XNode, into out: inout [UInt8]) {
        out.append(UInt8(ascii: "<"))
        out.append(contentsOf: node.name.utf8)
        if node.attrs.count == 1, let (k, v) = node.attrs.first {
            _attribute(k, v, into: &out)
        } else if !node.attrs.isEmpty {
            for (k, v) in node.attrs.sorted(by: { $0.key < $1.key }) { _attribute(k, v, into: &out) }
        }
        // Whitespace between child elements is indentation, not content.
        let text = !node.children.isEmpty && (node.text.isEmpty || node.text.trimmingWhitespace().isEmpty) ? "" : node.text
        if node.children.isEmpty && text.isEmpty {
            out.append(UInt8(ascii: "/")); out.append(UInt8(ascii: ">"))
            return
        }
        out.append(UInt8(ascii: ">"))
        _escape(text, attribute: false, into: &out)
        for c in node.children { _write(c, into: &out) }
        out.append(UInt8(ascii: "<")); out.append(UInt8(ascii: "/"))
        out.append(contentsOf: node.name.utf8)
        out.append(UInt8(ascii: ">"))
    }

    private static func _attribute(_ k: String, _ v: String, into out: inout [UInt8]) {
        out.append(UInt8(ascii: " "))
        out.append(contentsOf: k.utf8)
        out.append(UInt8(ascii: "=")); out.append(UInt8(ascii: "\""))
        _escape(v, attribute: true, into: &out)
        out.append(UInt8(ascii: "\""))
    }

    /// The markup characters are single bytes in UTF-8 and occur in no
    /// other character's encoding, so the bytes are walked, not the
    /// characters.
    private static func _escape(_ s: String, attribute: Bool, into out: inout [UInt8]) {
        for b in s.utf8 {
            switch b {
            case UInt8(ascii: "&"): out.append(contentsOf: "&amp;".utf8)
            case UInt8(ascii: "<"): out.append(contentsOf: "&lt;".utf8)
            case UInt8(ascii: ">"): out.append(contentsOf: "&gt;".utf8)
            case UInt8(ascii: "\"") where attribute: out.append(contentsOf: "&quot;".utf8)
            default: out.append(b)
            }
        }
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
