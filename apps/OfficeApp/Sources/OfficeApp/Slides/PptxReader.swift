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
    /// The part names by lower case: PowerPoint finds a part whatever the case of the name a relationship gives.
    var lowerNames: [String: String] = [:]

    static func == (a: PptxPackage, b: PptxPackage) -> Bool { a.parts == b.parts }

    init(_ entries: [ZipEntry]) {
        var parts: [String: Data] = [:]
        for e in entries { parts[e.name] = e.data }
        self.parts = parts
        for name in parts.keys { lowerNames[name.lowercased()] = lowerNames[name.lowercased()] ?? name }
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
            var resolved = external ? target : Pptx.resolve(target, from: part)
            // (ppt/Media/image1.png named as ../media/image1.png: ko-68695d7a's slides, all pictures, print blank without it.)
            if !external, parts[resolved] == nil, let actual = lowerNames[resolved.lowercased()] { resolved = actual }
            return PptxRel(id: id, type: type, target: resolved, external: external)
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
        try BigStack.run { try _read(data) }
    }

    private static func _read(_ data: Data) throws -> (DeckState, DeckTheme, PptxPackage) {
        // A legacy .ppt (PowerPoint 97-2003, a compound file holding a "PowerPoint Document" stream) is
        // read as the package it translates to; an encrypted .pptx is a compound file too and stays on its path.
        if data.count > 8, data.starts(with: [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]),
           let cf = try? CompoundFile([UInt8](data)), cf.stream("PowerPoint Document") != nil {
            return try PptxReader(try PptBuild.package([UInt8](data))).read()
        }
        let package = PptxPackage(try Zip.read(data))
        // The reader recurses through nested groups: keep ShapeState small (Boxed), or a deep deck overflows the
        // stack (ja-85c85cb794, 8 levels at 375 KB each).
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
    /// The theme's part, whose relationships its picture fill styles use.
    var part: String?
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
                if let t = font.first("a:ea")?["typeface"], !t.isEmpty { table["ea"] = t }
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
    /// Colours of a page background fill: PowerPoint mixes their tints in
    /// linear light even before a strong saturation boost (5ea13b90's
    /// tint 80% satMod 300% centre prints (91,124,198), as linear light
    /// gives and sRGB's (1,101,226) does not; the shapes' of the same
    /// theme styles print as sRGB's).
    var pageBackground = false
    /// A table's themed gradient (tint then satMod 300%) keeps the saturation boost unclamped, as Word's print
    /// of Themed Style 1 on an Office 2007 theme does (ca992b5bf p16: bottom stop prints 255,190,134, a clamped boost gives 255,210,189).
    var tableGradient = false

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
            return Self.modify(b, child, duotone: duotone || pageBackground, unclampedSat: tableGradient)
        }
        return nil
    }

    static let preset: [String: Color] = [
        "black": Color(0xFF000000), "white": Color(0xFFFFFFFF), "red": Color(0xFFFF0000),
        "green": Color(0xFF008000), "blue": Color(0xFF0000FF), "yellow": Color(0xFFFFFF00),
        "gray": Color(0xFF808080), "grey": Color(0xFF808080), "orange": Color(0xFFFFA500),
    ]

    /// The chart colour style's (`cs:colorStyle meth="cycle"`, the colourful one) nth cycle of the six accents: the plain accent,
    /// then lumMod 60%, 80% + 20%, 80%, 60% + 40%, 50%, 70% + 30%, 70%, 50% + 50% (chartex-lab2 treemap: item 7 is accent1 at 60%,
    /// item 13 at 80% + 20%, item 19 at 80%). The ninth variation is followed by the first again.
    static func chartexVariation(_ c: Color, cycle: Int) -> Color {
        let steps: [(Double, Double)] = [(1, 0), (0.6, 0), (0.8, 0.2), (0.8, 0), (0.6, 0.4), (0.5, 0), (0.7, 0.3), (0.7, 0), (0.5, 0.5)]
        let (mod, off) = steps[cycle % steps.count]
        if mod == 1 { return c }
        let (h, s, l) = _hsl(Double((c.value >> 16) & 0xFF) / 255, Double((c.value >> 8) & 0xFF) / 255, Double(c.value & 0xFF) / 255)
        let (r, g, b) = _rgb(h, s, min(1, max(0, l * mod + off)))
        func ch(_ v: Double) -> Int64 { Int64(min(255, max(0, (v * 255).rounded()))) }
        return Color(Int64(0xFF00_0000) | ch(r) << 16 | ch(g) << 8 | ch(b))
    }

    /// lumMod/lumOff, satMod/satOff and hueMod/hueOff (in HSL), tint,
    /// shade and alpha, as DrawingML applies them. (satMod is what makes a
    /// theme's near-grey `lt2` the warm cream of its radial backgrounds.)
    static func modify(_ c: Color, _ node: XNode, duotone: Bool = false, unclampedSat: Bool = false) -> Color {
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
                // PowerPoint leaves saturation above 100% unclamped and clamps the
                // channels instead (hueoff lab: accent3 + satOff 100% is FFEB00).
                let achromatic = _hsl(r, g, b).1 == 0
                (r, g, b) = _rgb(h, m.name == "a:satMod" ? (unclampedSat ? max(0, s) : min(1, max(0, s))) : max(0, s), l)   // (only satOff was measured unclamped; satMod keeps its clamp: table styles' satMod 300% decks matched with it)
                // A grey given saturation takes hue 0, and its blue comes out of
                // the hue ramp unwrapped (3p - 2q, so 0 once saturated): the
                // grey lab's A5A5A5 + satOff 100% prints FF4B00, +50% D27800.
                if achromatic && s > 0 {
                    let q = l < 0.5 ? l * (1 + s) : l + s - l * s
                    b = min(1, max(0, 3 * (2 * l - q) - 2 * q))
                }
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
                // picture's duotone (Treck's background). A pale colour's (SmartArt
                // boxes of a purple theme, HSL saturation 0.25) is linear too: it prints
                // (201,181,232) at tint 50%, satMod 300%, where sRGB gives (189,146,240).
                let sRGBTint = tint && !duotone && _hsl(r, g, b).1 > 0.5
                    && kids.indices.contains(k + 1) && kids[k + 1].name == "a:satMod"
                    && (kids[k + 1]["val"].flatMap(Double.init) ?? 0) >= 250000 && v <= 0.6
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

    static func _hsl(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
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

    static func _rgb(_ h: Double, _ s: Double, _ l: Double) -> (Double, Double, Double) {
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
        func c(_ x: Double) -> Double { min(1, max(0, x)) }
        return (c(hue(p, q, h + 1.0 / 3)), c(hue(p, q, h)), c(hue(p, q, h - 1.0 / 3)))
    }
}

// MARK: - Text styles

enum Bullet: Equatable { case none, char, number }

/// One level's paragraph and run look, as far as some layer of the
/// inheritance chain says; `filled(from:)` completes it from a lower layer.
struct LevelStyle {
    var algn: String?
    var latinLnBrk: String?
    var eaLnBrk: String?
    /// `hangingPunct` as some layer of the chain states it (a master's title style says "0"; a slide's paragraph then inherits it).
    var hangingPunct: String?
    var rtl: String?
    var marL: Double?
    var marR: Double?
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
    /// `buSzPts`: a bullet at a fixed size, in points.
    var bulletPoints: Double?
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
    var csArabicCharset = false   // the cs face is declared with charset -78 (Arabic)
    /// `a:ea`: the face for East Asian text; `lang` picks the theme's script face when it is empty.
    var eaFont: String?
    var lang: String?
    var altLang: String?
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
    /// `a:ln` on the run: its outline (nil under `a:noFill`), and whether it was said.
    var outline: CharOutline?
    var outlineSet = false
    /// `a:noFill` on the run: with an outline, the letters print hollow.
    var noFill = false
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
        s.latinLnBrk = s.latinLnBrk ?? lower.latinLnBrk
        s.eaLnBrk = s.eaLnBrk ?? lower.eaLnBrk
        s.hangingPunct = s.hangingPunct ?? lower.hangingPunct
        s.rtl = s.rtl ?? lower.rtl
        s.marL = s.marL ?? lower.marL
        s.marR = s.marR ?? lower.marR
        s.indent = s.indent ?? lower.indent
        if s.lineMultiple == nil && s.linePoints == nil { s.lineMultiple = lower.lineMultiple; s.linePoints = lower.linePoints }
        if s.beforePoints == nil && s.beforePercent == nil { s.beforePoints = lower.beforePoints; s.beforePercent = lower.beforePercent }
        if s.afterPoints == nil && s.afterPercent == nil { s.afterPoints = lower.afterPoints; s.afterPercent = lower.afterPercent }
        s.bullet = s.bullet ?? lower.bullet
        if s.autoNumType == nil { s.autoNumType = lower.autoNumType; s.autoNumStart = s.autoNumStart ?? lower.autoNumStart }
        if s.bulletChar == nil { s.bulletChar = lower.bulletChar; s.bulletFont = s.bulletFont ?? lower.bulletFont; s.bulletPicture = lower.bulletPicture }
        if s.bulletColor == nil, !s.bulletColorFollows { s.bulletColor = lower.bulletColor; s.bulletColorFollows = lower.bulletColorFollows }
        if s.bulletScale == nil, s.bulletPoints == nil, !s.bulletSizeFollows { s.bulletScale = lower.bulletScale; s.bulletSizeFollows = lower.bulletSizeFollows; if s.bulletPoints == nil { s.bulletPoints = lower.bulletPoints } }
        s.caps = s.caps ?? lower.caps
        s.size = s.size ?? lower.size
        s.bold = s.bold ?? lower.bold
        s.italic = s.italic ?? lower.italic
        s.underline = s.underline ?? lower.underline
        s.strike = s.strike ?? lower.strike
        s.font = s.font ?? lower.font
        if s.csFont == nil { s.csArabicCharset = lower.csArabicCharset }
        s.csFont = s.csFont ?? lower.csFont
        s.eaFont = s.eaFont ?? lower.eaFont
        s.lang = s.lang ?? lower.lang
        s.altLang = s.altLang ?? lower.altLang
        s.color = s.color ?? lower.color
        s.baseline = s.baseline ?? lower.baseline
        s.spc = s.spc ?? lower.spc
        s.kern = s.kern ?? lower.kern
        if !s.shadowSet { s.shadow = lower.shadow; s.shadowSet = lower.shadowSet }
        if !s.outlineSet { s.outline = lower.outline; s.outlineSet = lower.outlineSet }
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
        s.latinLnBrk = p["latinLnBrk"]
        s.eaLnBrk = p["eaLnBrk"]
        s.hangingPunct = p["hangingPunct"]
        s.rtl = p["rtl"]
        s.marL = p["marL"].flatMap(Double.init).map { $0 / Pptx.emu }
        s.marR = p["marR"].flatMap(Double.init).map { $0 / Pptx.emu }
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
        if let v = p.first("a:buSzPct")?["val"].flatMap(Double.init) { s.bulletScale = v / 100000; s.bulletPoints = nil }
        if let v = p.first("a:buSzPts")?["val"].flatMap(Double.init) { s.bulletPoints = v / 100; s.bulletScale = nil }
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
    /// Wingdings' common bullets as our own shapes, from the face's measured
    /// ink box (metrics only): kind (0 round, 1 square, 2 diamond), x0, y0, x1, y1 in ems, then (optional) the character PowerPoint writes for the bullet in its text layer (its print: Wingdings 6C is U+26AB, A7 U+25AA; Wingdings 2/3 keep their private-use code).
    var bulletInk: [Double]? {
        guard let ch = bulletChar, let scalar = ch.unicodeScalars.first else { return nil }
        let face = (bulletFont ?? "").lowercased()
        let code = (0xF000 ... 0xF0FF).contains(scalar.value) ? scalar.value - 0xF000 : scalar.value
        // Wingdings 2 and 3 (lab wing2, measured on PowerPoint's print at 18/28/40 pt): a small dot, a small
        // square, a diamond; two right triangles (kind 6).
        if face == "wingdings 2" {
            switch code {
            case 0x96: return [0, 0.0870, 0.2660, 0.2800, 0.4580, 0xF096]
            case 0xA0: return [1, 0.0870, 0.2650, 0.2800, 0.4575, 0xF0A0]
            case 0xAE: return [2, 0.0870, 0.0880, 0.6310, 0.6315, 0xF0AE]
            default: return nil
            }
        }
        if face == "wingdings 3" {
            switch code {
            case 0x75: return [6, 0.0870, -0.0555, 0.8085, 0.7780, 0xF075]
            case 0x84: return [6, 0.2188, 0.0495, 0.7595, 0.6730, 0xF084]
            case 0x7D: return [6, 0.0852, 0.0, 0.4455, 0.7200, 0xF07D]
            default: return nil
            }
        }
        guard face == "wingdings" else { return nil }
        switch code {
        case 0x6C: return [0, 0.0845, 0.0723, 0.6631, 0.6504, 0x26AB]
        case 0x6E: return [1, 0.0845, 0.0723, 0.6626, 0.6504, 0x25FC]
        case 0xA7: return [1, 0.0845, 0.2168, 0.3735, 0.5059, 0x25AA]
        case 0x75: return [2, 0.0845, -0.0474, 0.9023, 0.7705]
        case 0x71: return [5, 0.0845, 0.0, 0.8071, 0.7227]
        case 0x76: return [6, 0.0845, 0.0, 0.8071, 0.7227]
        case 0xD8: return [3, 0.0845, 0.0, 0.7104, 0.7227]
        case 0xA2: return [5, 0.0845, 0.0, 0.8071, 0.7227]
        case 0xFC: return [4, 0.0723, 0.1226, 0.7495, 0.7656]
        default: return nil
        }
    }

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
            return [0x7D: "▸", 0x75: "▸", 0x84: "▸"][code]
        }
        if face == "wingdings 2" {
            return [0x96: "•", 0xA0: "▪", 0xAE: "◆"][code]
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
            let map: [UInt32: String] = [0xB7: "•", 0x2A: "∗", 0x2D: "–", 0x3E: ">", 0xB2: "″", 0xA8: "♦", 0xA7: "♣", 0xAE: "→", 0xDE: "⇒"]
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
        s.csArabicCharset = r.first("a:cs")?["charset"] == "-78"
        s.eaFont = r.first("a:ea")?["typeface"].flatMap { $0.isEmpty ? nil : $0 }
        s.lang = r["lang"].flatMap { $0.isEmpty ? nil : $0 }
        s.altLang = r["altLang"].flatMap { $0.isEmpty ? nil : $0 }
        // (An East Asian face PowerPoint does not have, named in a Traditional Chinese run and declared with the Big5 charset (-120), is
        // drawn in Microsoft JhengHei, Latin letters and ideographs alike, at JhengHei's advances: lab tcfall2, 5 faces x 4 attribute
        // variants, lines within 0.5 pt. With no charset the Latin letters are narrower (JhengHei UI's, not yet measured), and the GB2312,
        // Shift-JIS and Hangul charsets draw yet other Latin: those are left as they were. A face the print box has under ANY of its names, local ones included
        // (標楷體 = DFKai-SB, as pptx-zh 76f3dc44cb00 names: PowerPoint drew DFKaiShu there), stays: SlideFonts.printBoxHasIdeographName reads the
        // measured table of installed names, kana names included.)
        if let lang = (s.lang ?? s.altLang)?.lowercased(), ["zh-tw", "zh-hk", "zh-mo", "zh-hant"].contains(lang),
           r.first("a:ea")?["charset"] == "-120", let ea = s.eaFont,
           ea.unicodeScalars.contains(where: { $0.value >= 0x4E00 && $0.value <= 0x9FFF }),
           !WordWindowsFaces.names.contains(ea.trimmingWhitespace().lowercased()),
           !SlideFonts.printBoxHasIdeographName(ea.trimmingWhitespace().lowercased()), !SlideFonts.isEmbedded(ea) {
            if s.font == ea { s.font = "Microsoft JhengHei" }
            s.eaFont = "Microsoft JhengHei"
        }
        if let fill = r.first("a:solidFill") { s.color = colors.color(in: fill) }
        // Text filled with a gradient is drawn as such in WordArt (its run
        // looks); elsewhere in the gradient's middle colour, not the black
        // of no colour at all — tdf114848's red "Word Art Perspective".
        else if let g = r.first("a:gradFill"), let f = PptxReader.gradient(g, colors: colors), f.stops.count >= 2 {
            s.color = SlideFill.colorAt(f.stops, 0.5)
        }
        if r.has("a:noFill") { s.noFill = true }
        if let ln = r.first("a:ln") {
            s.outlineSet = true
            if !ln.has("a:noFill"), let c = ln.first("a:solidFill").flatMap(colors.color(in:)), c.alpha > 0 {
                s.outline = CharOutline(color: c, width: ln["w"].flatMap(Double.init).map { $0 / Pptx.emu } ?? 0.75)
            }
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
            s.shadow = outerShadow(effects, colors, text: true)
            // (A glow on the run, with no shadow of its own: the letters haloed.)
            // (With both, the halo is what shows: a91e3e82 p20's orange title glows in PowerPoint where ours kept only the shadow, red.)
            if let g = effects.first("a:glow"), let c = colors.color(in: g) {
                var glow = CharShadow(color: c, dx: 0, dy: 0, blur: (g["rad"].flatMap(Double.init) ?? 0) / Pptx.emu)
                glow.glow = true
                s.shadow = glow
            }
        }
        return s
    }

    /// An effect list's `a:reflection`.
    static func reflection(_ effects: XNode?) -> Reflection? {
        guard let r = effects?.first("a:reflection") else { return nil }
        func v(_ k: String, _ d: Double) -> Double { r[k].flatMap(Double.init) ?? d }
        var out = Reflection()
        out.blur = v("blurRad", 0) / Pptx.emu
        out.dist = v("dist", 0) / Pptx.emu
        out.startAlpha = v("stA", 100000) / 100000
        out.endAlpha = v("endA", 0) / 100000
        out.startPos = v("stPos", 0) / 100000
        out.endPos = v("endPos", 100000) / 100000
        out.scaleY = v("sy", 100000) / 100000
        // Only the flip straight down (dir 90°, sy negative) is drawn.
        guard v("dir", 5400000) == 5400000, out.scaleY < 0 else { return nil }
        return out
    }

    /// An effect list's outer shadow: `dist` along `dir` (60000ths of a
    /// degree, clockwise from the right), blurred by `blurRad`. One cast
    /// on the ground — scaled or skewed — is nil: drawn as a copy of the
    /// outline it would stand up.
    static func outerShadow(_ effects: XNode?, _ colors: ColorContext, text: Bool = false) -> CharShadow? {
        // (Scaled alike both ways it is the outline larger or smaller —
        // tdf104015's title's 101%, tdf130058's 1% — and drawn so.)
        guard let sh = effects?.first("a:outerShdw"), let c = colors.color(in: sh) else { return nil }
        let flat = ["kx", "ky"].allSatisfy({ k in sh[k].flatMap(Double.init).map { $0 == 0 } ?? true })
            && (sh["sx"].flatMap(Double.init) ?? 100000) == (sh["sy"].flatMap(Double.init) ?? 100000)
        let dist = (sh["dist"].flatMap(Double.init) ?? 0) / Pptx.emu
        let dir = (sh["dir"].flatMap(Double.init) ?? 0) / 60000 * .pi / 180
        var shadow = CharShadow(color: c, dx: dist * cos(dir), dy: dist * sin(dir),
                                blur: (sh["blurRad"].flatMap(Double.init) ?? 0) / Pptx.emu)
        shadow.scale = flat ? (sh["sx"].flatMap(Double.init) ?? 100000) / 100000 : 1
        let algn = sh["algn"] ?? "b"
        shadow.anchor = Offset(algn.hasSuffix("l") ? 0 : algn.hasSuffix("r") ? 1 : 0.5,
                               algn.hasPrefix("t") ? 0 : algn.hasPrefix("b") ? 1 : 0.5)
        if !flat {
            func angle(_ k: String) -> Double { tan((sh[k].flatMap(Double.init) ?? 0) / 60000 * .pi / 180) }
            shadow.ground = [(sh["sx"].flatMap(Double.init) ?? 100000) / 100000, (sh["sy"].flatMap(Double.init) ?? 100000) / 100000,
                             angle("kx"), angle("ky")]
        }
        return shadow
    }
}

// MARK: - Reader

extension PptxPackage {
    /// A click action (`a:hlinkClick`) as the model keeps it: the URL (web,
    /// mailto), "slide:<part>" for a jump to a slide, "action:<ppaction>" for
    /// one with no target (next slide, end show…). The tip is its tooltip.
    func clickAction(_ n: XNode?, part: String) -> (link: String?, tip: String?) {
        guard let n else { return (nil, nil) }
        let tip = (n["tooltip"]).flatMap { $0.isEmpty ? nil : $0 }
        if let rid = n["r:id"], !rid.isEmpty, let rel = rels(part).first(where: { $0.id == rid }) {
            if rel.external { return (rel.target, tip) }
            if rel.kind == "slide" { return ("slide:" + rel.target, tip) }
            return (nil, nil)
        }
        if let a = n["action"], !a.isEmpty { return ("action:" + a, tip) }
        return (nil, nil)
    }
}

struct PptxReader {
    let package: PptxPackage
    let images = PptxImages()

    init(_ package: PptxPackage) { self.package = package }


    /// A line feed inside a run's text (`<a:t>` holding "\n") ends the paragraph in PowerPoint's print, with the paragraph's space after and
    /// its own line spacing (0be73c557ee1 p3: three LF-joined lines stand 34 pt apart, the 26 pt line plus the 8 pt after; an `a:br` is the
    /// soft break that stays in the paragraph). The paragraph is split here, each piece keeping the paragraph's properties.
    static func splitParagraphsAtLineFeeds(_ node: XNode) {
        var out: [XNode] = []
        var changed = false
        for child in node.children {
            if child.name == "a:p", child.children.contains(where: { $0.name == "a:r" && ($0.first("a:t")?.text ?? "").firstIndex(of: "\n") != nil }) {
                changed = true
                let pPr = child.first("a:pPr"), end = child.first("a:endParaRPr")
                var cur = XNode(name: "a:p", attrs: child.attrs)
                if let pPr { cur.children.append(pPr) }
                for piece in child.children where piece.name != "a:pPr" && piece.name != "a:endParaRPr" {
                    guard piece.name == "a:r", let t = piece.first("a:t"), t.text.firstIndex(of: "\n") != nil else { cur.children.append(piece); continue }
                    let parts = t.text.split(separator: "\n", omittingEmptySubsequences: false)
                    for (i, part) in parts.enumerated() {
                        if i > 0 {
                            if let end { cur.children.append(end) }
                            out.append(cur)
                            cur = XNode(name: "a:p", attrs: child.attrs)
                            if let pPr { cur.children.append(pPr) }
                        }
                        if part.isEmpty { continue }
                        let r = XNode(name: "a:r", attrs: piece.attrs)
                        r.children = piece.children.map { c in
                            guard c === t else { return c }
                            let nt = XNode(name: "a:t", attrs: t.attrs); nt.text = String(part); return nt
                        }
                        cur.children.append(r)
                    }
                }
                if let end { cur.children.append(end) }
                out.append(cur)
            } else {
                splitParagraphsAtLineFeeds(child)
                out.append(child)
            }
        }
        if changed { node.children = out }
    }

    /// Set Up Slide Show (`ppt/presProps.xml` `p:showPr`) and the custom shows (`p:custShowLst`).
    static func _showSettings(_ presentation: XNode, rels: [PptxRel], slides: [SlideState], package: PptxPackage)
        -> (ShowSettings, [CustomShow]) {
        var shows: [CustomShow] = []
        for cs in presentation.first("p:custShowLst")?.all("p:custShow") ?? [] {
            var ids: [Int] = []
            for sld in cs.first("p:sldLst")?.all("p:sld") ?? [] {
                guard let rid = sld["r:id"], let part = rels.first(where: { $0.id == rid })?.target,
                      let slide = slides.first(where: { $0.sourcePart == part }) else { continue }
                ids.append(slide.id)
            }
            shows.append(CustomShow(id: cs["id"].flatMap(Int.init) ?? shows.count, name: cs["name"] ?? "Custom Show", slides: ids))
        }
        var show = ShowSettings()
        if let rel = rels.first(where: { $0.kind == "presProps" }), let pr = package.xml(rel.target)?.first("p:showPr") {
            if pr.first("p:browse") != nil { show.kind = .window }
            if pr.first("p:kiosk") != nil { show.kind = .kiosk }
            show.loop = pr["loop"] == "1" || pr["loop"] == "true"
            show.useTimings = !(pr["useTimings"] == "0" || pr["useTimings"] == "false")
            show.narration = !(pr["showNarration"] == "0" || pr["showNarration"] == "false")
            if let rg = pr.first("p:sldRg"), let a = rg["st"].flatMap(Int.init), let b = rg["end"].flatMap(Int.init) {
                show.range = .slides(from: a, to: b)
            } else if let cs = pr.first("p:custShow"), let id = cs["id"].flatMap(Int.init), shows.contains(where: { $0.id == id }) {
                show.range = .custom(id)
            }
            if pr["loop"] == nil, pr.first("p:kiosk") != nil { show.loop = true }
        }
        return (show, shows)
    }

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
        // The fonts the deck carries (EOT, usually MicroType Express packed).
        var embeddedFaces: [String: String] = [:]
        var embeddedWinShares: [String: Double] = [:]
        for font in presentation.first("p:embeddedFontLst")?.all("p:embeddedFont") ?? [] {
            guard let name = font.first("p:font")?["typeface"] else { continue }
            for style in ["p:regular", "p:bold", "p:italic", "p:boldItalic"] {
                guard let rid = font.first(style)?["r:id"], let r = rels.first(where: { $0.id == rid }),
                      let raw = package.parts[r.target], let sfnt = EmbeddedEot.sfnt(raw),
                      !OfficeFonts.embeddedFileIsIgnored(sfnt, named: name),
                      let family = OfficeFonts.loadEmbedded(sfnt, sharedFamily: "Starling Embedded " + name) else { continue }
                if let w = OfficeFonts.variableWeight(sfnt, named: name) { RichTextTheme.variableWeights["Starling Embedded " + name] = w }
                embeddedFaces[name] = family
                if style == "p:regular" || embeddedWinShares[name] == nil, let share = OfficeFonts.sfntWindowsDescentShare(sfnt) { embeddedWinShares[name] = share }
            }
        }
        SlideFonts.noteEmbedded(embeddedFaces)
        SlideFonts.noteEmbeddedWindowsShares(embeddedWinShares)
        var missingRoman: Set<String> = []
        for (name, data) in package.parts where name.hasPrefix("ppt/") && name.hasSuffix(".xml") {
            let text = String(decoding: data, as: UTF8.self)
            guard text.containsSubstring("panose=\"0205") else { continue }
            for piece in text.split(separator: "<").map(String.init) where piece.hasPrefix("a:latin ") && piece.containsSubstring("panose=\"0205") {
                guard piece.containsSubstring("pitchFamily=\"18\""), !piece.containsSubstring("charset=\"") || piece.containsSubstring("charset=\"0\"") else { continue }
                if let r = piece.rangeOfSubstring("typeface=\"") { missingRoman.insert(String(piece[r.upperBound...].prefix { $0 != "\"" })) }
            }
        }
        SlideFonts.noteMissingRoman(missingRoman)
        var hans = 0, hant = 0
        for (name, data) in package.parts where name.hasPrefix("ppt/slides/") && name.hasSuffix(".xml") {
            let text = String(decoding: data, as: UTF8.self)
            guard text.containsSubstring("lang=\"zh-") else { continue }
            for piece in text.split(separator: "<") {
                if piece.hasPrefix("a:rPr ") || piece.hasPrefix("a:endParaRPr ") || piece.hasPrefix("a:fld ") {
                    if piece.containsSubstring("lang=\"zh-CN\"") || piece.containsSubstring("lang=\"zh-SG\"") { hans += 1 }
                    else if piece.containsSubstring("lang=\"zh-TW\"") || piece.containsSubstring("lang=\"zh-HK\"") || piece.containsSubstring("lang=\"zh-MO\"") { hant += 1 }
                }
            }
        }
        SlideFonts.noteSimplifiedChinese(hans > hant)
        var slideParts: [String] = []
        for id in presentation.first("p:sldIdLst")?.all("p:sldId") ?? [] {
            if let rid = id["r:id"], let r = rels.first(where: { $0.id == rid }) { slideParts.append(r.target) }
        }
        let defaults = presentation.first("p:defaultTextStyle")
        let unsaidKern: Double = defaults != nil ? 0 : 12
        // (`p:presentation strictFirstAndLastChars` is on unless the file says "0": strict kinsoku keeps small kana and ー from opening a line.)
        let looseKinsoku = presentation["strictFirstAndLastChars"] == "0"
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
            Self.splitParagraphsAtLineFeeds(slide)
            let layoutPart = package.rel(part, kind: "slideLayout")?.target
            let layout = layoutPart.flatMap(package.xml)
            let masterPart = layoutPart.flatMap { package.rel($0, kind: "slideMaster")?.target }
            let master = masterPart.flatMap(package.xml)
            let themePart = masterPart.flatMap { package.rel($0, kind: "theme")?.target }
            var theme = PptxTheme(themePart.flatMap(package.xml))
            theme.part = themePart
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
                                   unsaidKern: unsaidKern, looseKinsoku: looseKinsoku)
            var shapes: [ShapeState] = []
            // A shape whose `p:cNvPr` has no `id` breaks the schema (id is
            // required): PowerPoint prints that slide as a blank page, its
            // backdrop and background gone too (clusterfuzz 4986's p5, whose
            // eighty shapes read `nd=` for `id=`). The page stays, empty.
            let noIds = slide.first("p:cSld")?.first("p:spTree")?.descendants("p:cNvPr").contains { $0["id"] == nil } ?? false
            if !noIds, let tree = slide.first("p:cSld")?.first("p:spTree") {
                ctx.shapes(in: tree, transform: nil, into: &shapes, id: id)
            }
            // What the master and the layout draw behind the slide — their
            // own shapes (logos, bars, pictures), not their placeholders —
            // unless the slide (or, for the master's, the layout) says
            // `showMasterSp="0"`. Drawn, never written.
            var decorations: [ShapeState] = []
            if slide["showMasterSp"] != "0", !noIds {
                var owners: [(String, XNode)] = []
                if let masterPart, let master, layout?["showMasterSp"] != "0" { owners.append((masterPart, master)) }
                if let layoutPart, let layout { owners.append((layoutPart, layout)) }
                for (ownerPart, xml) in owners {
                    guard let tree = xml.first("p:cSld")?.first("p:spTree") else { continue }
                    let octx = SlideContext(package: package, part: ownerPart, slide: xml, layout: layout, master: master,
                                            colors: colors, theme: theme, defaults: defaults, slideSize: size, images: images,
                                            foreignTheme: n > 0 && themePart != deckThemePart,
                                            unsaidKern: unsaidKern, looseKinsoku: looseKinsoku)
                    var found: [ShapeState] = []
                    octx.shapes(in: tree, transform: nil, into: &found, id: id)
                    // (A slide-number field in a shape the layout or master draws (not a placeholder, so the slide holds no copy of it) shows the number of
                    // the slide it is drawn on: PowerPoint prints ko-2fd3de28's layout text box as 136, not the field's stored ‹#›.)
                    // (The same where the field is one run among others, "- page ‹#› -": the stored ‹#› becomes the number, in the run that holds it:
                    // ko-c03ed80e's layout footer, printed "- page 4 -" by PowerPoint.)
                    for k in found.indices where found[k].field == nil && (found[k].sourceXML?.containsSubstring("type=\"slidenum\"") ?? false) {
                        guard var doc = found[k].text else { continue }
                        let want = SlideField(type: "slidenum", id: "").value(slide: n + (presentation["firstSlideNum"].flatMap(Int.init) ?? 1))
                        var changed = false
                        for pi in doc.paragraphs.indices {
                            let units = Array(doc.paragraphs[pi].text.utf16)
                            let mark = Array("‹#›".utf16)
                            guard units.count >= mark.count, let at = (0 ... units.count - mark.count).first(where: { Array(units[$0 ..< $0 + mark.count]) == mark }) else { continue }
                            var start = 0
                            var runs = doc.paragraphs[pi].runs
                            guard let ri = runs.firstIndex(where: { r in defer { start += r.length }; return start <= at && at + mark.count <= start + r.length }) else { continue }
                            runs[ri].length += want.utf16.count - mark.count
                            doc.paragraphs[pi].text = String(decoding: units[..<at], as: UTF16.self) + want + String(decoding: units[(at + mark.count)...], as: UTF16.self)
                            doc.paragraphs[pi].runs = runs
                            changed = true
                        }
                        if changed { found[k].text = doc }
                    }
                    for k in found.indices {
                        // (The same where the field shares its paragraph with other text, "- page ‹#› -" in ko-c03ed80e's layout
                        // footer: the stored mark inside the text becomes the number.)
                        if found[k].field == nil, var doc = found[k].text {
                            let want = "\(n + (presentation["firstSlideNum"].flatMap(Int.init) ?? 1))"
                            var changed = false
                            for at in doc.paragraphs.indices {
                                let mark = "‹#›"
                                guard doc.paragraphs[at].text.containsSubstring(mark) else { continue }
                                var text = Array(doc.paragraphs[at].text.utf16)
                                let m = Array(mark.utf16)
                                var i = 0
                                while i + m.count <= text.count {
                                    if Array(text[i ..< i + m.count]) == m {
                                        var pos = 0
                                        for r in doc.paragraphs[at].runs.indices {
                                            let len = doc.paragraphs[at].runs[r].length
                                            if i >= pos, i + m.count <= pos + len {
                                                doc.paragraphs[at].runs[r].length = len - m.count + want.utf16.count
                                                break
                                            }
                                            pos += len
                                        }
                                        text.replaceSubrange(i ..< i + m.count, with: Array(want.utf16))
                                        i += want.utf16.count
                                        changed = true
                                    } else { i += 1 }
                                }
                                doc.paragraphs[at].text = String(decoding: text, as: UTF16.self)
                            }
                            if changed { found[k].text = doc }
                            continue
                        }
                        guard let field = found[k].field, field.isSlideNumber, var doc = found[k].text else { continue }
                        guard let at = doc.paragraphs.firstIndex(where: { !$0.text.isEmpty }) else { continue }
                        let want = field.value(slide: n + (presentation["firstSlideNum"].flatMap(Int.init) ?? 1))
                        let style = doc.paragraphs[at].runs.first?.style ?? CharStyle()
                        doc.paragraphs[at].text = want
                        doc.paragraphs[at].runs = [Run(length: want.utf16.count, style: style)]
                        found[k].text = doc
                    }
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
            let bg = noIds ? nil : slide.first("p:cSld")?.first("p:bg")
            let themeRoot = themePart.flatMap(package.xml)
            // The slide's own background is its; one from its layout or
            // master is only drawn (writing it per slide would copy the
            // master's picture into every slide).
            var bgFill: SlideFill? = nil
            var inherited: SlideFill? = nil
            if noIds {
                // (blank: no background of its own, none inherited)
            } else if let b = slide.first("p:cSld")?.first("p:bg") {
                bgFill = _background(b, owner: part, colors: colors, theme: themeRoot, themePart: themePart)
                // Shaded to the title (`shadeToTitle`): the path gradient
                // runs out from a point at the title box's top centre, as
                // Windows PowerPoint prints tdf114848's slide 5 (t = the
                // larger of the across distance over half the width and the
                // down distance from the title's top over what is left).
                if b.first("p:bgPr")?["shadeToTitle"] == "1", bgFill?.path != nil, size.width > 0, size.height > 0,
                   let title = shapes.first(where: { $0.phType == "title" || $0.phType == "ctrTitle" })?.frame {
                    let cx = min(1, max(0, (title.left + title.right) / 2 / size.width)), top = min(1, max(0, title.top / size.height))
                    // (A rect or shape path is stepped from the fill-to POINT: its edges in fractions across and
                    // down, as `gradient` writes them; a circle's keeps the insets it was fitted with.)
                    let isCircle = bgFill?.path == .circle
                    bgFill?.fillTo = isCircle ? Rect.fromLTRB(cx, top, 1 - cx, 1 - top) : Rect.fromLTRB(cx, top, cx, top)
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
            let byFileId = Dictionary(shapes.compactMap { s in s.fileId.map { ($0, s.id) } }, uniquingKeysWith: { a, _ in a })
            for i in shapes.indices where shapes[i].pendingConnStart != nil || shapes[i].pendingConnEnd != nil {
                let ps = shapes[i].pendingConnStart, pe = shapes[i].pendingConnEnd
                let cs = ps.flatMap { p in byFileId[p.shape].map { ShapeConn(shape: $0, site: p.site) } }
                let ce = pe.flatMap { p in byFileId[p.shape].map { ShapeConn(shape: $0, site: p.site) } }
                shapes[i].connStart = cs; shapes[i].connEnd = ce
                shapes[i].keptLine?.connStart = cs; shapes[i].keptLine?.connEnd = ce
            }
            var animations: [ShapeAnimation] = []
            var sourceAnimations: [ShapeAnimation]? = nil
            if let timing = slide.first("p:timing"), let read = AnimationXML.read(timing) {
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
        var state = DeckState(slides: slides, current: 0, slideSize: size, firstSlideNum: presentation["firstSlideNum"].flatMap(Int.init) ?? 1)
        (state.show, state.customShows) = Self._showSettings(presentation, rels: rels, slides: slides, package: package)
        (state.sections, state.slides) = Self._sections(presentation, rels: rels, slides: slides)
        return (state, deckTheme, package)
    }

    /// The deck's sections (`p14:sectionLst`): each slide gets the guid of the section that lists its slide id. A slide no section lists joins the one before it; a file whose list names no slide has no sections.
    static func _sections(_ presentation: XNode, rels: [PptxRel], slides: [SlideState]) -> ([SlideSection], [SlideState]) {
        guard let list = presentation.descendant("p14:sectionLst") else { return ([], slides) }
        var byFileId: [Int: Int] = [:]
        for e in presentation.descendant("p:sldIdLst")?.all("p:sldId") ?? [] {
            guard let fid = e["id"].flatMap(Int.init), let rid = e["r:id"],
                  let part = rels.first(where: { $0.id == rid })?.target,
                  let at = slides.firstIndex(where: { $0.sourcePart == part }) else { continue }
            byFileId[fid] = at
        }
        var out = slides
        var sections: [SlideSection] = []
        var tagged = Set<Int>()
        for sec in list.all("p14:section") {
            let guid = sec["id"] ?? DeckController.newSectionGuid()
            sections.append(SlideSection(guid: guid, name: sec["name"] ?? "Section"))
            for s in sec.first("p14:sldIdLst")?.all("p14:sldId") ?? [] {
                if let fid = s["id"].flatMap(Int.init), let at = byFileId[fid] { out[at].section = guid; tagged.insert(at) }
            }
        }
        guard !tagged.isEmpty else { return ([], slides) }
        var last = out[tagged.min()!].section
        for i in out.indices {
            if tagged.contains(i) { last = out[i].section } else { out[i].section = last }
        }
        return (sections, out)
    }

    /// A `p:bg`: its own properties, or a reference into the theme's
    /// background fill styles with the referring colour as `phClr`.
    func _background(_ bg: XNode, owner: String, colors: ColorContext, theme: XNode?,
                             themePart: String?) -> SlideFill? {
        if let pr = bg.first("p:bgPr") { return fill(pr, owner: owner, colors: colors) }
        guard let ref = bg.first("p:bgRef"), let idx = ref["idx"].flatMap(Int.init) else { return nil }
        var c = colors
        c.placeholder = colors.color(in: ref)
        c.pageBackground = true
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
            var f = SlideFill(image: images.attachment(rel.target, package, blip: blip))
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

    /// Stops that share a position, as PowerPoint for Windows draws them
    /// (lab grad, 20 gradients): at 0 the later stop wins, at 100 the first
    /// does; anywhere else the later stop moves on to the next position a
    /// stop holds (100 if none) and gives way to the stop already there.
    /// So red 30 / blue 30 is red to 30 and a blend to blue at 100, and
    /// red 0 / blue 50 / green 50 is red to blue to green.
    static func settled(_ stops: [SlideFill.GradientStop]) -> [SlideFill.GradientStop] {
        var out: [(stop: SlideFill.GradientStop, moved: Bool)] = []
        for (i, stop) in stops.enumerated() {
            var stop = stop
            var moved = false
            if let last = out.last, last.stop.position == stop.position {
                if last.moved { out.removeLast() }
                else if stop.position <= 0 { out.removeLast() }
                else if stop.position >= 1 { continue }
                else {
                    stop.position = stops[(i + 1)...].first { $0.position > stop.position }?.position ?? 1
                    moved = true
                }
            }
            out.append((stop, moved))
        }
        return out.map(\.stop)
    }

    /// The stops seen from the far end: a path gradient (`a:path`) is
    /// settled that way round, as PowerPoint draws it.
    static func mirrored(_ stops: [SlideFill.GradientStop]) -> [SlideFill.GradientStop] {
        stops.reversed().map { SlideFill.GradientStop(position: ((1 - $0.position) * 1e6).rounded() / 1e6, color: $0.color) }
    }

    /// An `a:gradFill` as a fill: its stops in order and its direction, or
    /// its path (`a:path`, radiating from `a:fillToRect`). A single stop is
    /// a colour; none at all is nothing (the shape's style fill then).
    static func gradient(_ g: XNode, colors: ColorContext) -> SlideFill? {
        let read: [SlideFill.GradientStop] = (g.first("a:gsLst")?.all("a:gs") ?? []).compactMap { gs in
            guard let c = colors.color(in: gs) else { return nil }
            return SlideFill.GradientStop(position: (gs["pos"].flatMap(Double.init) ?? 0) / 100000, color: c)
        }
        let ordered = read.enumerated().sorted { ($0.element.position, $0.offset) < ($1.element.position, $1.offset) }.map(\.element)
        let stops = g.first("a:path") != nil ? Self.mirrored(Self.settled(Self.mirrored(ordered))) : Self.settled(ordered)
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
        if let t = g.first("a:tileRect") {
            func v(_ k: String) -> Double { (t[k].flatMap(Double.init) ?? 0) / 100000 }
            if ["l", "t", "r", "b"].contains(where: { v($0) != 0 }) { f.tile = Rect.fromLTRB(v("l"), v("t"), 1 - v("r"), 1 - v("b")) }
        }
        if let path = g.first("a:path") {
            f.path = path["path"].flatMap(SlideFill.GradientPath.init(rawValue:)) ?? .shape
            if let to = path.first("a:fillToRect") {
                func v(_ k: String) -> Double { (to[k].flatMap(Double.init) ?? 0) / 100000 }
                // A focus outside the shape (t 150%, b -50%) is drawn by
                // Windows PowerPoint at the centre, not beyond the edge
                // where the Mac's print has it (tdf94238).
                f.fillToExact = Rect.fromLTRB(v("l"), v("t"), 1 - v("r"), 1 - v("b"))
                if ["l", "t", "r", "b"].contains(where: { v($0) < 0 || v($0) > 1 }) {
                    f.fillTo = Rect.fromLTRB(0.5, 0.5, 0.5, 0.5)
                } else {
                    f.fillTo = Rect.fromLTRB(v("l"), v("t"), 1 - v("r"), 1 - v("b"))
                }
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
        // PowerPoint print fit (lab lum3, 48 bright/contrast pairs, worst
        // error 1 level, same on every channel): the contrast slope pivots
        // at mid grey, and brightness adds 255·b scaled by (1 + slope)/2.
        let scale = cf
        let offset = 127.5 * (1 - cf) + 127.5 * bright * (1 + cf)
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
    static func _transition(_ slide: XNode) -> SlideTransition {
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
        case "p:pull": t.kind = .pull
        case "p:split": t.kind = .split
        case "p:zoom": t.kind = .zoom
        default:
            t.kind = .fade
            t.raw = PptxXML.serialize(ac ?? node)
        }
        if let d = effect?["dir"].flatMap(SlideTransition.Direction.init(rawValue:)) { t.direction = d }
        if t.kind == .split { t.vertical = effect?["orient"] == "vert"; t.inward = effect?["dir"] == "in" }
        if t.kind == .zoom { t.zoomIn = effect?["dir"] != "out" }
        t.advanceOnClick = node["advClick"] != "0"
        t.advanceAfter = node["advTm"].flatMap(Double.init).map { $0 / 1000 }
        return t
    }

    static func _layoutKind(_ type: String?) -> SlideLayoutKind {
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

    static func _deckTheme(_ t: PptxTheme, _ c: ColorContext) -> DeckTheme {
        var d = DeckTheme()
        d.name = "From file"
        d.headingFont = t.major
        d.bodyFont = t.minor
        // (A theme whose East Asian slot is empty names its Japanese face in the Jpan script entry, else in the complex-script slot where
        // that is a Japanese Office face: PowerPoint's print sets a ja chart's kana and kanji in it, ja 7d329933 p23 and 81d28d42 p29.)
        if (t.minorScript["ea"] ?? "").isEmpty {
            if let j = t.minorScript["Jpan"], !j.isEmpty { d.japaneseFace = j }
            else if let cs = t.minorScript["cs"], SlideEastAsianWidths.lookup(SlideFonts.windowsName(cs)) != nil { d.japaneseFace = cs }
        }
        d.background = c.scheme("bg1") ?? d.background
        d.text = c.scheme("tx1") ?? d.text
        let accents = (1 ... 6).compactMap { t.colors["accent\($0)"] }
        if accents.count == 6 { d.accents = accents }
        return d
    }
}

/// Everything one slide's shapes resolve against.
struct SlideContext {
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
    /// The text is a SmartArt drawing's: an East Asian face stands on Word's line there (`SlideFonts.diagramEastAsianLine`).
    var inDiagram = false
    var looseKinsoku = false

    // MARK: Placeholders

    func _ph(_ sp: XNode) -> XNode? {
        (sp.first("p:nvSpPr") ?? sp.first("p:nvPicPr") ?? sp.first("p:nvGraphicFramePr"))?.first("p:nvPr")?.first("p:ph")
    }

    /// The layout's and then the master's placeholder this one inherits from.
    func _inherited(_ ph: XNode) -> (layout: XNode?, master: XNode?) {
        let type = ph["type"] ?? "obj"
        let idx = ph["idx"]
        func find(_ tree: XNode?, masterRules: Bool) -> XNode? {
            guard let shapes = tree?.first("p:cSld")?.first("p:spTree")?.children else { return nil }
            let sps = shapes.filter { $0.name == "p:sp" }
            // An orphan placeholder (`idx` 4294967295, PowerPoint's mark for a shape whose layout
            // placeholder is gone) takes nothing from the layout, only from the master.
            if !masterRules, idx == "4294967295" { return nil }
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
                // (A slide's `ctrTitle` inherits from its layout's `title` and the other way round: lo-tdf128550's
                // second slide, `ctrTitle` over a layout whose title sits at y 129pt, anchored to its foot, took
                // the master's at the top of the page; PowerPoint's print has it by the layout's.)
                let titled = { (v: String) in v == "title" || v == "ctrTitle" }
                return t == want || (want == "obj" && t == "body") || (!masterRules && titled(t) && titled(want))
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
            let click = package.clickAction(el.descendant("p:cNvPr")?.first("a:hlinkClick"), part: part)
            s.link = click.link; s.linkTip = click.tip
            if click.link != nil, s.readShape != nil { s.readShape = ReadShape(s) }
            // Hidden (`cNvPr hidden="1"`), itself or by its group: in the
            // file, and not drawn — lo-hidden_group_shape's red square.
            if group?.hidden == true || el.descendant("p:cNvPr")?["hidden"] == "1" { s.invisible = true }
            // A member filled by its group (`a:grpFill`): drawn in the
            // group's colour; still the shape that was read, so a save
            // keeps its element (and the group's fill with it). Not a picture: PowerPoint
            // draws the image there, not the group colour over it (es ba0a6310 p1).
            if s.fill == nil, el.name != "p:pic", let groupFill, el.first("p:spPr")?.has("a:grpFill") == true {
                s.fill = groupFill
                s.keptLook?.readFill = groupFill
                if s.readShape != nil { s.readShape = ReadShape(s) }
            }
            // Text held level in a shape that turns (`bodyPr upright`): the
            // shape, and its text as a box of its own.
            if let box = s.uprightBox, s.text != nil {
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
                out.append(shape)
                out.append(text)
                return
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
                // Ink (a p:contentPart): PowerPoint draws the strokes, never the fallback picture, which is a
                // stale thumbnail at a different size (3680b255's ink fallback filled a box 8 M EMU tall). Strokes are not drawn yet.
                if let cp = el.first("mc:Choice")?.first("p:contentPart") {
                    // The strokes are the part's InkML, laid on the part's own frame; the element is kept whole for the file.
                    guard let xf = cp.first("p14:xfrm"), var frame = _xfrmRect(xf) else { continue }
                    if let t = transform { frame = t(frame) }
                    let box = ShapeState(id: id(), name: cp.descendant("p14:cNvPr")?["name"] ?? "Ink",
                                         kind: .opaque(OpaqueObject(xml: PptxXML.serialize(el), label: "Ink", sourcePart: part)),
                                         frame: frame, rotation: 0, fill: nil, outline: nil, outlineWidth: 0, anchor: .top,
                                         insets: EdgeInsets(left: 0, top: 0, right: 0, bottom: 0), prompt: nil, text: nil,
                                         font: nil, size: 18, color: Color(0xFF000000), listIndent: 18)
                    var ink = box
                    if case .opaque(var obj) = ink.kind,
                       let rid = cp["r:id"], let rel = package.rels(part).first(where: { $0.id == rid && !$0.external }),
                       let doc = package.xml(rel.target), let off = xf.first("a:off"),
                       let ox = off["x"].flatMap(Double.init), let oy = off["y"].flatMap(Double.init) {
                        for (sp, _) in InkStrokes.shapes(doc, offX: ox, offY: oy) {
                            let holder = XNode(name: "p:spTree", attrs: [:]); holder.children = [sp]
                            var inner: [ShapeState] = []
                            shapes(in: holder, transform: transform, into: &inner, id: id, group: nil, groupFill: groupFill)
                            obj.rendering += inner
                        }
                        ink.kind = .opaque(obj)
                    }
                    out.append(ink)
                    continue
                }
                // A chartex chart in the choice is drawn from its part, never from the fallback picture (which is a bitmap).
                if let gf = el.first("mc:Choice")?.first("p:graphicFrame"),
                   gf.descendant("a:graphicData")?["uri"]?.containsSubstring("chartex") == true,
                   var c = _chart(gf, transform, id: id) {
                    c.sourceXML = PptxXML.serialize(el)
                    add(c, el)
                    continue
                }
                // The fallback is what an older reader would draw: keep the
                // whole thing — and draw it as that fallback's shapes (or the
                // choice's, where the fallback holds nothing this app reads:
                // tdf131553's diagram sits in one of each).
                let x0 = el.first("p:xfrm") ?? el.first("p:spPr")?.first("a:xfrm") ?? el.first("p:grpSpPr")?.first("a:xfrm")
                    ?? el.descendant("a:xfrm") ?? el.descendant("p:xfrm")
                var o = _opaque(el, label: "Object", transform, id: id, framed: false)
                if case .opaque(var obj)? = o?.kind {
                    // An equation the math engine can lay out is drawn as text from the choice; the fallback picture only where it cannot.
                    let mathChoice = el.first("mc:Choice").map { c in
                        let eqs = c.descendants("a14:m").flatMap { $0.children.filter { $0.name == "m:oMath" || $0.name == "m:oMathPara" } }
                        WriterMath.slideScope = true; defer { WriterMath.slideScope = false }
                        return !eqs.isEmpty && eqs.allSatisfy { WriterMath.box($0, size: 18) != nil }
                    } ?? false
                    for branch in (mathChoice ? ["mc:Choice", "mc:Fallback"] : ["mc:Fallback", "mc:Choice"]) where obj.rendering.isEmpty {
                        guard let b = el.first(branch) else { continue }
                        var inner: [ShapeState] = []
                        shapes(in: b, transform: transform, into: &inner, id: id, group: nil, groupFill: groupFill)
                        obj.fromAlternate = true
                        obj.rendering = inner.flatMap { m -> [ShapeState] in
                            if case .opaque(let x) = m.kind { return x.rendering }
                            return [m]
                        }
                    }
                    o?.kind = .opaque(obj)
                    // A placeholder with no xfrm of its own (the layout gives the frame) has no box in the file: the drawn shape's is the object's.
                    if x0 == nil, let f = obj.rendering.first?.frame { o?.frame = f }
                }
                add(o, el)
            default: continue
            }
        }
    }

    func _xfrmRect(_ x: XNode) -> Rect? {
        guard let off = x.first("a:off"), let ext = x.first("a:ext"),
              let ox = off["x"].flatMap(Double.init), let oy = off["y"].flatMap(Double.init),
              let cx = ext["cx"].flatMap(Double.init), let cy = ext["cy"].flatMap(Double.init) else { return nil }
        return Rect.fromLTWH(ox / Pptx.emu, oy / Pptx.emu, cx / Pptx.emu, cy / Pptx.emu)
    }

    func _shape(_ sp: XNode, _ transform: ((Rect) -> Rect)?, id: () -> Int) -> ShapeState? {
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
        // A date, footer or slide-number placeholder the layout has but no frame stands anywhere (layout, master, slide): PowerPoint sets its text
        // at the page's corner, on one line and without insets (c991b42e p25's "Página 25" starts at x 0, 64547fb24d29's "10" the same).
        let frameless = own == nil && fromLayout == nil && fromMaster == nil && inherited.layout != nil
            && ["dt", "ftr", "sldNum"].contains(ph?["type"] ?? "")
        guard var frame = own ?? fromLayout ?? fromMaster ?? (frameless ? Rect.fromLTWH(0, 0, 0, 0) : nil) else { return nil }
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
        var outlineScheme: String? = nil
        var outline: Color? = nil
        var outlineWidth = 0.75
        let style = sp.first("p:style")
        if spPr?.has("a:noFill") == true || sp["useBgFill"] == "1" {
            // (`useBgFill`: the shape is painted with the slide's background.)
            fill = nil
        } else if let f = spPr?.first("a:solidFill") {
            fill = colors.color(in: f)
            fillScheme = SchemeColor.read(f)
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
            var f = SlideFill(image: images.attachment(rel.target, package, blip: blip))
            (f.imageAlpha, f.duotone) = PptxReader.blipEffects(blip, colors: colors)
            f.imageLevels = PptxReader.blipLevels(blip)
            f.imageInset = PptxReader.stretchInset(b)
            // (A picture that stays upright in a shape turned: 8bef769d p69's clouds, PowerPoint's print keeps the illustrations square to the page.)
            f.imageStays = (spPr?.first("a:xfrm")?["rot"].flatMap(Double.init) ?? 0) != 0 && ["0", "false"].contains(b["rotWithShape"] ?? "")
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
            fillScheme = SchemeColor.read(ref)
            // A solid fill style's own modifiers on the referring colour
            // (a theme whose second fill is phClr tint 69%, satMod 105%,
            // lumMod 110%: a91e3e82 p13's callouts print light lavender).
            if let idx = ref["idx"].flatMap(Int.init), theme.fillStyles.indices.contains(idx - 1),
               theme.fillStyles[idx - 1].name == "a:solidFill",
               let mods = theme.fillStyles[idx - 1].first("a:schemeClr"), mods["val"] == "phClr",
               !mods.children.isEmpty, let f = fill {
                fill = ColorContext.modify(f, mods)
            }
            if let idx = ref["idx"].flatMap(Int.init), theme.fillStyles.indices.contains(idx - 1),
               theme.fillStyles[idx - 1].name == "a:gradFill" {
                var c = colors
                c.placeholder = fill
                if let gradient = PptxReader.gradient(theme.fillStyles[idx - 1], colors: c), gradient.stops.count >= 2 {
                    fillStyle = gradient
                }
            }
            // A picture in the theme's fill style (a tiled, duotoned texture:
            // es/6422a4c7's hatched teal title band), whose r:embed is the
            // theme's.
            if let idx = ref["idx"].flatMap(Int.init), theme.fillStyles.indices.contains(idx - 1),
               theme.fillStyles[idx - 1].name == "a:blipFill", let tp = theme.part {
                var c = colors
                c.placeholder = fill
                let b = theme.fillStyles[idx - 1]
                if let blip = b.first("a:blip"), let rid = blip["r:embed"],
                   let rel = package.rels(tp).first(where: { $0.id == rid }), !rel.external,
                   package.parts[rel.target] != nil {
                    var f = SlideFill(image: images.attachment(rel.target, package, blip: blip))
                    (f.imageAlpha, f.duotone) = PptxReader.blipEffects(blip, colors: c)
                    f.imageLevels = PptxReader.blipLevels(blip)
                    f.imageInset = PptxReader.stretchInset(b)
                    if b.first("a:tile") != nil || b.first("a:stretch") == nil {
                        PptxReader.tile(b.first("a:tile"), image: package.parts[rel.target], into: &f)
                    }
                    fillStyle = f
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
            if ln.has("a:noFill") { outline = nil } else if let f = ln.first("a:solidFill") { outline = colors.color(in: f); outlineScheme = SchemeColor.read(f) }
            else if let gs = ln.first("a:gradFill")?.first("a:gsLst")?.all("a:gs"), !gs.isEmpty {
                // A gradient line by its first stop that shows — or no line,
                // when every stop is fully transparent (tdf149588's curve).
                let stops = gs.compactMap { colors.color(in: $0) }
                outline = stops.first { $0.alpha > 0 }
            }
            else if let ref = style?.first("a:lnRef"), ref["idx"] != "0" { outline = colors.lineColor(in: ref) }
            // A line at alpha 0 is no line. One of no width (`w="0"`, as
            // LibreOffice writes a hairline) is drawn as one in PowerPoint
            // for Windows, 0.14 pt in its PDF (ThemeColorTransparency's red
            // box, vert_and_padding's blue arrows); Mac's showed none.
            if let o = outline, o.alpha == 0 { outline = nil }
            if ln["w"] == "0" { outlineWidth = 0.14 }
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
                if let f = pr.first("a:solidFill") { fill = colors.color(in: f); fillScheme = SchemeColor.read(f); break }
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
        var textInsets = text.insets
        if frameless { textInsets = EdgeInsets(left: 0, top: 0, right: 0, bottom: 0) }
        let rotation = (xfrm?["rot"].flatMap(Double.init) ?? 0) / 60000
        var st = ShapeState(id: id(), name: name, kind: kind, frame: frame, rotation: rotation,
                            fill: fill, outline: outline, outlineWidth: outlineWidth,
                            anchor: text.anchor, insets: textInsets, prompt: nil,
                            text: text.document, font: text.font, size: text.size, color: text.color,
                            listIndent: text.listIndent, phType: phRead?["type"], phIdx: phRead?["idx"],
                            fillScheme: fillScheme)
        st.outlineScheme = outlineScheme
        if let prst, ph == nil, !isTextBox, !PresetGeometry.has(prst) { st.text = nil; st.fill = nil }
        st.autofit = text.autofit
        st.fontScale = text.fontScale
        st.lineReduction = text.lineReduction
        st.insetsFollowFont = text.insetsFollowFont
        st.sizeGroup = text.sizeGroup
        st.keepsSize = text.keepsSize
        if text.wordLines { st.naturalLines = true }
        st.generatedHang = text.generatedHang
        st.noWrap = text.noWrap || frameless
        st.anchorCentred = text.anchorCentred
        st.bodyVert = text.bodyVert
        st.bodyWrap = text.bodyWrap
        st.fitRule = text.fitRule
        st.keepsFirstSpace = text.keepsFirstSpace
        st.textTurn = text.textTurn
        st.textStacked = text.textStacked
        st.uprightIdeographs = text.uprightIdeographs
        st.sidewaysDigits = text.sidewaysDigits
        // An eaVert column in a frame turned to 270 degrees reads as one upright horizontal line in
        // PowerPoint's print (the frame's turn cancels the column's quarter turn; ideographs are not
        // kept upright against it): b3af6b818144 layout bar, b7cbab02dccf p9, d8cbc61e1a24.
        if text.textTurn > 0, text.uprightIdeographs, abs(((st.rotation.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360) - 270) < 0.01 { st.uprightIdeographs = false }
        if text.textTurn > 0, text.sidewaysDigits, abs(((st.rotation.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360) - 270) < 0.01 { st.sidewaysDigits = false }
        st.textSpin = text.textSpin
        st.textRev = text.textRev
        st.textScene = text.textScene
        st.columns = text.columns
        st.columnGap = text.columnGap
        st.warp = text.warp
        st.runLooks = text.runLooks
        st.scene3d = Extrusion.read(spPr, colors: colors)
        st.flipH = xfrm?["flipH"] == "1"
        st.flipV = xfrm?["flipV"] == "1"
        // A shape mirrored top to bottom turns its text half round (flipH
        // leaves it), horizontal or vertical, and the file's `bodyPr rot`
        // comes on top: tdf165261's pyramid steps are flipV with rot 180,
        // which together read upright (lab flip, all 36 boxes).
        if st.flipV { st.textSpin += 180 }
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
        st.reflection = LevelStyle.reflection(spPr?.first("a:effectLst"))
        if st.reflection == nil, var r = sp.first("p:txBody")?.descendants("a:rPr").lazy.compactMap({ LevelStyle.reflection($0.first("a:effectLst")) }).first {
            r.onText = true
            st.reflection = r
        }
        st.fillStyle = fillStyle
        if var fs = st.fillStyle, fs.path == .circle, let ex = fs.fillToExact, spPr?.first("a:sp3d")?.first("a:bevelT") != nil {
            fs.fillTo = ex; fs.exactFocus = true; st.fillStyle = fs
        }
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
        // (A text box that names a preset keeps it as any shape does: its text in the preset's text rectangle, the 4.7 pt
        // a rounded rectangle at 4% leaves PowerPoint's 87a69a7b bullets short of ours.)
        var presetOfShape: ShapePreset? = nil
        if case .geometry(let preset) = kind { presetOfShape = preset }
        else if case .textBox = kind, let prst, prst != "rect", PresetGeometry.has(prst) { presetOfShape = ShapePreset(rawValue: prst) }
        if let preset = presetOfShape, preset.rawValue != "rect", !preset.isLine {
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
        if st.shapeInsets != .zero, st.flipH || st.flipV {
            st.insets = st.insets.mirroringShare(st.shapeInsets, horizontal: st.flipH, vertical: st.flipV)
            st.shapeInsets = st.shapeInsets.mirroringShare(st.shapeInsets, horizontal: st.flipH, vertical: st.flipV)
        }
        // `bodyPr upright="1"`: the text stays level whatever the shape's
        // turn. Its frame is the text rectangle's own, set level about the
        // rectangle's turned middle — its width and height swapped when the
        // shape lies on its side (45° to 135° either way); PowerPoint wraps
        // oox-tdf149538_upright's 8 pt Courier in 168 pt, not the arrow
        // callout's 80 pt turned with it.
        let uprightTurn = rotation.truncatingRemainder(dividingBy: 360)
        if st.uprightBox == nil, st.text != nil, abs(uprightTurn) > 0.01, abs(abs(uprightTurn) - 360) > 0.01,
           ["1", "true"].contains(sp.first("p:txBody")?.first("a:bodyPr")?["upright"] ?? "") {
            let t = st.shapeInsets
            let w = frame.width - t.left - t.right, h = frame.height - t.top - t.bottom
            let mid = Offset(frame.left + t.left + w / 2, frame.top + t.top + h / 2)
            let c = frame.center, th = uprightTurn * .pi / 180
            let at = Offset(c.dx + cos(th) * (mid.dx - c.dx) - sin(th) * (mid.dy - c.dy),
                            c.dy + sin(th) * (mid.dx - c.dx) + cos(th) * (mid.dy - c.dy))
            let side = (abs(uprightTurn).truncatingRemainder(dividingBy: 180)) >= 45
                && (abs(uprightTurn).truncatingRemainder(dividingBy: 180)) < 135
            st.uprightBox = Rect.fromCenter(center: at, width: side ? h : w, height: side ? w : h)
            st.uprightInsets = EdgeInsets(left: st.insets.left - t.left, top: st.insets.top - t.top,
                                          right: st.insets.right - t.right, bottom: st.insets.bottom - t.bottom)
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
        let paras = sp.first("p:txBody")?.all("a:p").filter { !$0.all("a:r").isEmpty || !$0.all("a:fld").isEmpty || !$0.all("a14:m").isEmpty } ?? []
        if paras.count == 1, paras[0].all("a:r").isEmpty, paras[0].all("a:fld").count == 1,
           let fld = paras[0].first("a:fld"), let type = fld["type"], let fid = fld["id"], SlideField.isKnownType(type) {
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
        st.aspectLock = sp.first("p:nvSpPr")?.first("p:cNvSpPr")?.first("a:spLocks")?["noChangeAspect"] == "1"
        st.readShape = ReadShape(st)
        return st
    }

    /// "accent3" when a fill is a plain theme accent (no modifiers), so a
    /// new theme can recolour it.
    static func _accentSlot(_ fill: XNode) -> String? {
        guard let c = fill.first("a:schemeClr"), c.children.isEmpty, let v = c["val"], v.hasPrefix("accent") else { return nil }
        return v
    }

}

/// One attachment per media part, so a picture used on many slides (or a
/// master's background) is one image to decode and one part to write.
final class PptxImages {
    var _byPart: [String: ImageAttachment] = [:]

    func attachment(_ part: String, _ package: PptxPackage, blip: XNode? = nil) -> ImageAttachment {
        // A blip with `a:alphaModFix` takes PowerPoint's transparency path, which converts the pixels from the
        // file's colour profile to sRGB (lab icc-lab2: PNG and JPEG, Generic RGB and Display; a plain blip, or a
        // file with no profile, prints raw). That use is its own attachment: the same media part is decoded twice.
        let managed = blip?.has("a:alphaModFix") ?? false
        let key = managed ? part + "\u{0}managed" : part
        if let a = _byPart[key] { return a }
        var a = ImageAttachment(data: package.parts[part] ?? Data(), width: 0, height: 0, name: part.lastPathComponent)
        if managed { a.colourManaged = true }
        _byPart[key] = a
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
    static func _write(_ node: XNode, into out: inout [UInt8]) {
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

    static func _attribute(_ k: String, _ v: String, into out: inout [UInt8]) {
        out.append(UInt8(ascii: " "))
        out.append(contentsOf: k.utf8)
        out.append(UInt8(ascii: "=")); out.append(UInt8(ascii: "\""))
        _escape(v, attribute: true, into: &out)
        out.append(UInt8(ascii: "\""))
    }

    /// The markup characters are single bytes in UTF-8 and occur in no
    /// other character's encoding, so the bytes are walked, not the
    /// characters.
    static func _escape(_ s: String, attribute: Bool, into out: inout [UInt8]) {
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

