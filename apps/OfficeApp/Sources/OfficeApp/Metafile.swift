// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import OfficeText
import FlutterSwiftBridge
import Foundation

/// A Windows metafile — WMF or EMF — played once into a list of drawing
/// steps and painted from it as vectors. Office files carry these as
/// pictures (clip art, equations, the preview of an embedded object or an
/// ActiveX control), and no image codec reads them: they are GDI calls, not
/// pixels. This is the subset of GDI those files use — pens, brushes, fonts,
/// polygons and paths, text, bitmap blits, rectangular clips and the
/// window/viewport/world mapping — and nothing beyond it: raster operations
/// other than the copy and mask ones, hatches and EMF+ are approximated or
/// skipped.
final class Metafile {
    enum Step {
        case fill(Path, Color)
        /// A stroke `width` metafile units wide; 0 is GDI's one-pixel pen.
        case stroke(Path, Color, Double)
        case text(TextRun)
        case image(Int, source: Rect?, at: Rect, blend: BlendMode?)
        case clip(Path?)
    }

    struct TextRun {
        var text: String
        var at: Offset
        var size: Double
        var face: String
        var bold: Bool
        var italic: Bool
        var underline: Bool
        var color: Color
        /// GDI's text alignment flags (TA_RIGHT 2, TA_CENTER 6, TA_BOTTOM 8,
        /// TA_BASELINE 24).
        var align: Int
        /// Clockwise, radians.
        var angle: Double

        /// Its style in `color`, set in `family` — with the documents'
        /// fallback faces: tika-3388's icon caption, "約翰的測試文件" in
        /// MS Gothic, was a row of empty boxes in the Latin face that
        /// stands in for it.
        func style(_ color: Color, family: String) -> Flutter.TextStyle {
            let fallback = RichTextTheme.glyphFallback
            return Flutter.TextStyle(
                color: color, fontSize: max(1, size), fontWeight: bold ? .bold : .normal,
                fontStyle: italic ? .italic : .normal, decoration: underline ? .underline : nil, fontFamily: family,
                fontFamilyFallback: fallback.isEmpty ? nil : fallback)
        }
    }

    /// The picture's extent in the units the steps are in.
    private(set) var bounds = Rect.zero
    private(set) var steps: [Step] = []
    /// The bitmaps the metafile draws, as BMP files for the image codec.
    private(set) var bitmaps: [ImageAttachment] = []
    private let id: String

    static func isMetafile(_ data: Data) -> Bool { kind(data) != nil }

    /// Text in a symbol face (Wingdings, Webdings, Symbol) as the Unicode
    /// glyphs it shows.
    static func symbols(_ text: String, face: String) -> String { Player.symbols(text, face: face) }
    static func symbolAdvance(_ face: String?, _ glyph: Character) -> Double? { Player.symbolAdvance(face, glyph) }

    private enum Kind { case wmf, emf }

    private static func kind(_ data: Data) -> Kind? {
        guard data.count >= 44 else { return nil }
        let b = [UInt8](data.prefix(44))
        if b[0] == 0xD7, b[1] == 0xCD, b[2] == 0xC6, b[3] == 0x9A { return .wmf }
        if b[0] == 1, b[1] == 0, b[2] == 0, b[3] == 0, b[40] == 0x20, b[41] == 0x45, b[42] == 0x4D, b[43] == 0x46 { return .emf }
        // A WMF without the placeable header: type 1 or 2, a 9-word header,
        // version 1.0 or 3.0.
        if (b[0] == 1 || b[0] == 2), b[1] == 0, b[2] == 9, b[3] == 0, b[4] == 0, (b[5] == 3 || b[5] == 1) { return .wmf }
        return nil
    }

    init?(_ data: Data, id: String) {
        guard let kind = Self.kind(data) else { return nil }
        self.id = id
        var player = Player(bytes: [UInt8](data), id: id)
        switch kind {
        case .wmf: player.playWMF()
        case .emf: player.playEMF()
        }
        guard let b = player.bounds, b.width > 0, b.height > 0, !player.steps.isEmpty else { return nil }
        bounds = b
        steps = player.steps
        bitmaps = player.bitmaps
    }

    /// Draws the picture stretched into `dest`. `image` decodes one of
    /// `bitmaps` (nil while it is not ready), `font` names the face to draw
    /// a metafile's face with. `change` is a colour drawn as another
    /// ([from, to], PowerPoint's Set Transparent Color): what is filled,
    /// ruled or written in the first is in the second, or left out where
    /// that is clear — tdf113163's page is a drawing on a white sheet,
    /// the white taken out over a black slide.
    func paint(_ canvas: any Canvas, in dest: Rect, image: (ImageAttachment) -> Image?, font: (String) -> String,
               change: [Color]? = nil) {
        guard dest.width > 0, dest.height > 0 else { return }
        func drawn(_ c: Color) -> Color? {
            guard let change, change.count == 2, abs(c.r - change[0].r) < 0.002, abs(c.g - change[0].g) < 0.002,
                  abs(c.b - change[0].b) < 0.002 else { return c }
            return change[1].a < 0.002 ? nil : change[1]
        }
        let sx = dest.width / bounds.width, sy = dest.height / bounds.height
        // GDI's one-pixel pen, and any thinner one, as most of a pixel here.
        let hairline = 0.75 / max(0.0001, (sx + sy) / 2)
        canvas.save()
        canvas.clipRect(dest)
        canvas.translate(dest.left, dest.top)
        canvas.scale(sx, sy)
        canvas.translate(-bounds.left, -bounds.top)
        canvas.save()   // the metafile's own clip, replaced as it changes
        for step in steps {
            switch step {
            case .fill(let path, let color):
                guard let color = drawn(color) else { continue }
                let p = Paint()
                p.style = .fill
                p.isAntiAlias = true
                p.color = color
                canvas.drawPath(path, p)
            case .stroke(let path, let color, let width):
                guard let color = drawn(color) else { continue }
                let p = Paint()
                p.style = .stroke
                p.isAntiAlias = true
                p.strokeWidth = max(width, hairline)
                p.strokeJoin = .round
                p.color = color
                canvas.drawPath(path, p)
            case .clip(let path):
                canvas.restore()
                canvas.save()
                if let path { canvas.clipPath(path) }
            case .image(let index, let source, let at, let blend):
                guard bitmaps.indices.contains(index), let decoded = image(bitmaps[index]) else { continue }
                let whole = Rect.fromLTWH(0, 0, Double(decoded.width), Double(decoded.height))
                let p = Paint()
                p.filterQuality = .medium
                if let blend { p.blendMode = blend }
                canvas.drawImageRect(decoded, source.map { $0.intersect(whole) } ?? whole, at, p)
            case .text(let run):
                guard let ink = drawn(run.color) else { continue }
                let tp = TextPainter(text: TextSpan(text: run.text, style: run.style(ink, family: font(run.face))),
                                     textDirection: .ltr)
                tp.layout(minWidth: 0, maxWidth: .infinity)
                let dx = run.align & 6 == 6 ? -tp.width / 2 : run.align & 6 == 2 ? -tp.width : 0
                let dy = run.align & 24 == 24 ? -tp.computeDistanceToActualBaseline(.alphabetic)
                    : run.align & 24 == 8 ? -tp.height : 0
                canvas.save()
                canvas.translate(run.at.dx, run.at.dy)
                if run.angle != 0 { canvas.rotate(run.angle) }
                tp.paint(canvas, Offset(dx, dy))
                canvas.restore()
                tp.dispose()
            }
        }
        canvas.restore()
        canvas.restore()
    }
}

// MARK: - Playing the records

/// The GDI device context a metafile's records act on, and the steps they
/// leave. Coordinates are mapped as each record is played, so a step is in
/// the picture's own space whatever window or transform was in force.
private struct Player {
    struct Pen { var color = Color(0xFF000000); var width = 0.0; var null = false }
    struct Brush { var color = Color(0xFFFFFFFF); var null = false }
    struct Font {
        var height = 12.0
        var face = "Arial"
        var bold = false
        var italic = false
        var underline = false
        /// Tenths of a degree, anticlockwise.
        var escapement = 0.0
    }
    enum Object { case pen(Pen), brush(Brush), font(Font), other }

    struct DC {
        var winOrg = Offset.zero
        var winExt = Size(1, 1)
        var vpOrg = Offset.zero
        var vpExt = Size(1, 1)
        /// Whether the extents scale (MM_ISOTROPIC, MM_ANISOTROPIC).
        var scales = false
        /// The world transform: x' = a·x + c·y + e, y' = b·x + d·y + f.
        var a = 1.0, b = 0.0, c = 0.0, d = 1.0, e = 0.0, f = 0.0
        var pen = Pen()
        var brush = Brush()
        var font = Font()
        var textColor = Color(0xFF000000)
        var bkColor = Color(0xFFFFFFFF)
        var bkOpaque = true
        var textAlign = 0
        var winding = false
        var pos = Offset.zero
        var clip: Path? = nil
    }

    let bytes: [UInt8]
    let id: String
    var dc = DC()
    var stack: [DC] = []
    var objects: [Int: Object] = [:]
    var steps: [Metafile.Step] = []
    var bitmaps: [ImageAttachment] = []
    var bounds: Rect? = nil
    /// WMF: the first window, which later ones are mapped into.
    var frame: Rect? = nil
    var isWMF = false
    /// EMF: the path a BEGINPATH…ENDPATH bracket is building.
    var path: Path? = nil
    var building = false
    var figureOpen = false

    init(bytes: [UInt8], id: String) {
        self.bytes = bytes
        self.id = id
    }

    // MARK: Reading

    func u16(_ at: Int) -> Int { at + 2 <= bytes.count ? Int(bytes[at]) | Int(bytes[at + 1]) << 8 : 0 }
    func i16(_ at: Int) -> Int { Int(Int16(truncatingIfNeeded: u16(at))) }
    func u32(_ at: Int) -> Int {
        at + 4 <= bytes.count ? Int(bytes[at]) | Int(bytes[at + 1]) << 8 | Int(bytes[at + 2]) << 16 | Int(bytes[at + 3]) << 24 : 0
    }
    func i32(_ at: Int) -> Int { Int(Int32(truncatingIfNeeded: u32(at))) }
    func f32(_ at: Int) -> Double { Double(Float(bitPattern: UInt32(truncatingIfNeeded: u32(at)))) }
    func color(_ at: Int) -> Color {
        guard at + 3 <= bytes.count else { return Color(0xFF000000) }
        return Color(0xFF00_0000 | Int64(bytes[at]) << 16 | Int64(bytes[at + 1]) << 8 | Int64(bytes[at + 2]))
    }

    // MARK: Mapping

    func map(_ x: Double, _ y: Double) -> Offset {
        let wx = dc.a * x + dc.c * y + dc.e, wy = dc.b * x + dc.d * y + dc.f
        if isWMF {
            // Into the first window, which is the picture.
            guard let frame, dc.winExt.width != 0, dc.winExt.height != 0 else { return Offset(wx, wy) }
            return Offset(frame.left + (wx - dc.winOrg.dx) / dc.winExt.width * frame.width,
                          frame.top + (wy - dc.winOrg.dy) / dc.winExt.height * frame.height)
        }
        let kx = dc.scales && dc.winExt.width != 0 ? dc.vpExt.width / dc.winExt.width : 1
        let ky = dc.scales && dc.winExt.height != 0 ? dc.vpExt.height / dc.winExt.height : 1
        return Offset((wx - dc.winOrg.dx) * kx + dc.vpOrg.dx, (wy - dc.winOrg.dy) * ky + dc.vpOrg.dy)
    }
    func map(_ p: Offset) -> Offset { map(p.dx, p.dy) }

    /// How long one logical unit is, across and down, once mapped.
    var scaleX: Double { let o = map(0, 0), p = map(1, 0); return hypot(p.dx - o.dx, p.dy - o.dy) }
    var scaleY: Double { let o = map(0, 0), p = map(0, 1); return hypot(p.dx - o.dx, p.dy - o.dy) }
    /// The mapping's rotation, clockwise.
    var turn: Double { let o = map(0, 0), p = map(1, 0); return atan2(p.dy - o.dy, p.dx - o.dx) }

    // MARK: Drawing

    func polygon(_ points: [Offset], close: Bool) -> Path {
        let p = Path()
        p.fillType = dc.winding ? .nonZero : .evenOdd
        for (i, pt) in points.enumerated() {
            let m = map(pt)
            if i == 0 { p.moveTo(m.dx, m.dy) } else { p.lineTo(m.dx, m.dy) }
        }
        if close { p.close() }
        return p
    }

    func rect(_ l: Double, _ t: Double, _ r: Double, _ b: Double) -> Path {
        polygon([Offset(l, t), Offset(r, t), Offset(r, b), Offset(l, b)], close: true)
    }

    /// An ellipse as four cubics through mapped points, so that it turns
    /// and skews with the mapping.
    func ellipse(_ l: Double, _ t: Double, _ r: Double, _ b: Double) -> Path {
        let cx = (l + r) / 2, cy = (t + b) / 2, rx = (r - l) / 2, ry = (b - t) / 2, k = 0.5522847498
        let p = Path()
        func m(_ x: Double, _ y: Double) -> Offset { map(x, y) }
        let start = m(cx + rx, cy)
        p.moveTo(start.dx, start.dy)
        for (c1, c2, end) in [
            (m(cx + rx, cy + k * ry), m(cx + k * rx, cy + ry), m(cx, cy + ry)),
            (m(cx - k * rx, cy + ry), m(cx - rx, cy + k * ry), m(cx - rx, cy)),
            (m(cx - rx, cy - k * ry), m(cx - k * rx, cy - ry), m(cx, cy - ry)),
            (m(cx + k * rx, cy - ry), m(cx + rx, cy - k * ry), m(cx + rx, cy)),
        ] {
            p.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, end.dx, end.dy)
        }
        p.close()
        return p
    }

    mutating func fill(_ p: Path) {
        if !dc.brush.null { steps.append(.fill(p, dc.brush.color)) }
    }
    mutating func stroke(_ p: Path) {
        if !dc.pen.null { steps.append(.stroke(p, dc.pen.color, dc.pen.width * (scaleX + scaleY) / 2)) }
    }
    mutating func shape(_ p: Path) {
        if building { path?.addPath(p, Offset.zero); return }
        fill(p)
        stroke(p)
    }

    mutating func moveTo(_ x: Double, _ y: Double) {
        dc.pos = Offset(x, y)
        if building {
            let m = map(x, y)
            path?.moveTo(m.dx, m.dy)
            figureOpen = true
        }
    }

    mutating func lineTo(_ x: Double, _ y: Double) {
        if building {
            let m = map(x, y)
            if !figureOpen { let s = map(dc.pos); path?.moveTo(s.dx, s.dy); figureOpen = true }
            path?.lineTo(m.dx, m.dy)
        } else {
            stroke(polygon([dc.pos, Offset(x, y)], close: false))
        }
        dc.pos = Offset(x, y)
    }

    /// A run of line or curve points continuing from the current position.
    mutating func continueTo(_ points: [Offset], curves: Bool) {
        guard !points.isEmpty else { return }
        let target: Path
        if building, let path {
            target = path
            if !figureOpen { let s = map(dc.pos); target.moveTo(s.dx, s.dy); figureOpen = true }
        } else {
            target = Path()
            let s = map(dc.pos)
            target.moveTo(s.dx, s.dy)
        }
        if curves {
            var i = 0
            while i + 2 < points.count {
                let c1 = map(points[i]), c2 = map(points[i + 1]), e = map(points[i + 2])
                target.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, e.dx, e.dy)
                i += 3
            }
        } else {
            for pt in points { let m = map(pt); target.lineTo(m.dx, m.dy) }
        }
        dc.pos = points[points.count - 1]
        if !building { stroke(target) }
    }

    mutating func setClip(_ p: Path?) {
        dc.clip = p
        steps.append(.clip(p))
    }

    mutating func intersectClip(_ p: Path) {
        if let old = dc.clip {
            setClip(Path.combine(.intersect, old, p))
        } else {
            setClip(p)
        }
    }

    mutating func save() { stack.append(dc) }
    mutating func restore(_ n: Int) {
        // Relative (negative) or absolute (positive) level.
        let keep = n < 0 ? stack.count + n : n - 1
        guard keep >= 0, keep < stack.count else { return }
        let had = dc.clip
        dc = stack[keep]
        stack.removeSubrange(keep...)
        if had != nil || dc.clip != nil { steps.append(.clip(dc.clip)) }
    }

    mutating func select(_ object: Object?) {
        switch object {
        case .pen(let p)?: dc.pen = p
        case .brush(let b)?: dc.brush = b
        case .font(let f)?: dc.font = f
        default: break
        }
    }

    mutating func text(_ string: String, at: Offset, opaque: Rect?) {
        if let r = opaque {
            steps.append(.fill(rect(r.left, r.top, r.right, r.bottom), dc.bkColor))
        }
        // (Half of a surrogate pair, split over two records, decodes as a
        // replacement mark: tika-3388's attachment caption carries one at
        // the end of one line and the start of the next, and Word draws
        // neither.)
        let shown = Self.symbols(string.filter { $0 != "\0" && $0 != "\u{FFFD}" }, face: dc.font.face)
        guard !shown.isEmpty, !shown.allSatisfy({ $0 == " " }) else { return }
        // lfHeight below zero is the character height; above, the cell's
        // (ascent and descent, a sixth or so more than the size).
        let h = dc.font.height
        let size = (h < 0 ? -h : h * 0.86) * scaleY
        let ref = dc.textAlign & 1 == 1 ? dc.pos : at
        // Webdings' "n" and "g" are a disc and a square a whole em across
        // that no stand-in face has (theirs "●" is under half that): drawn
        // as such, where the run is set on its baseline from the left.
        // PowerPoint's print of 45545's feasibility grid and its legend:
        // 1.0 em wide, 1.06 em apart, centred 0.29 em above the baseline.
        if dc.font.face.lowercased().hasPrefix("webdings"), dc.textAlign & 31 == 24, dc.font.escapement == 0, abs(turn) < 1e-9,
           shown.allSatisfy({ $0 == "●" || $0 == "■" }) {
            let o = map(ref), wide = size / scaleY * scaleX
            let disc = Path()
            for (i, ch) in shown.enumerated() {
                let cx = o.dx + (Double(i) * 1.06 + 0.53) * wide, cy = o.dy - 0.29 * size
                let box = Rect.fromLTRB(cx - wide / 2, cy - size / 2, cx + wide / 2, cy + size / 2)
                if ch == "●" { disc.addOval(box) } else { disc.addRect(box) }
            }
            steps.append(.fill(disc, dc.textColor))
            return
        }
        steps.append(.text(Metafile.TextRun(
            text: shown, at: map(ref), size: size, face: dc.font.face, bold: dc.font.bold, italic: dc.font.italic,
            underline: dc.font.underline, color: dc.textColor, align: dc.textAlign,
            angle: turn - dc.font.escapement / 10 * .pi / 180)))
    }

    /// Text in a symbol face as the Unicode glyphs it shows: the bullets,
    /// boxes, ticks and arrows that metafiles draw with Wingdings and
    /// Webdings. A code this does not know stays as it is.
    /// The advance, in ems, a symbol face gives the glyph `symbols` drew,
    /// where the stand-in's is otherwise: Wingdings 2's boxes and ticks.
    static func symbolAdvance(_ face: String?, _ glyph: Character) -> Double? {
        guard face?.lowercased() == "wingdings 2" else { return nil }
        // (Its box: 10.68pt at 12pt in Word for Windows' print of zh-d0a207ac.)
        return ["☐": 0.89, "☑": 0.89, "☒": 0.89][glyph]
    }

    static func symbols(_ text: String, face: String) -> String {
        let name = face.lowercased()
        let map: [Character: Character]
        if name == "wingdings 2" {
            // (Wingdings 2's boxes, ticks and crosses: forms tick "£" and "R"
            // — zh-d0a207ac's 双龙杯 / 钱江杯 / 鲁班杯 boxes.)
            map = ["£": "☐", "R": "☑", "S": "☒", "T": "☒", "P": "✓", "O": "✗", "Q": "☒"]
        } else if name == "wingdings 3" {
            return text
        } else if name.hasPrefix("wingdings") {
            map = ["l": "●", "m": "❍", "n": "■", "o": "□", "q": "❑", "r": "❒", "s": "⬧", "t": "⧫", "u": "◆", "v": "❖",
                   "w": "⬥", "§": "▪", "¨": "◻", "ü": "✓", "û": "✗", "þ": "☑", "ý": "☒", "Ø": "➢", "à": "→", "ß": "←",
                   "á": "↑", "â": "↓", "è": "➔", "ð": "⇨", "J": "☺", "L": "☹", "(": "☎", "*": "✉", "F": "☞", "E": "☜"]
        } else if name.hasPrefix("webdings") {
            map = ["n": "●", "g": "■", "c": "▪", "a": "✔", "r": "✖", "3": "◀", "4": "▶", "5": "▲", "6": "▼", "=": "●",
                   "<": "■", "i": "ℹ", "s": "?", "x": "⊘", "y": "❤"]
        } else if name == "symbol" {
            map = ["·": "•", "®": "→", "¬": "←", "­": "↑", "¯": "↓", "´": "×", "¸": "÷", "£": "≤", "³": "≥", "¹": "≠",
                   "±": "±", "°": "°", "a": "α", "b": "β", "g": "γ", "d": "δ", "p": "π", "m": "μ", "s": "σ", "q": "θ",
                   "l": "λ", "w": "ω", "D": "Δ", "S": "Σ", "W": "Ω", "¥": "∞", "Ö": "√", "»": "≈", "å": "∑",
                   "Þ": "⇒", "Û": "⇔", "Ü": "⇐", "Ý": "⇑", "ß": "⇓", "«": "↔", "Î": "∈", "Ï": "∉", "Ç": "∩", "È": "∪",
                   "Ì": "⊂", "Í": "⊆", "É": "⊃", "Ê": "⊇", "\"": "∀", "$": "∃", "Ñ": "∇", "¶": "∂", "Ø": "¬", "Ù": "∧",
                   "Ú": "∨", "º": "≡", "µ": "∝", "^": "⊥", "Ð": "∠", "f": "φ", "e": "ε", "r": "ρ", "t": "τ", "c": "χ",
                   "y": "ψ", "h": "η", "z": "ζ", "x": "ξ", "n": "ν", "k": "κ", "i": "ι", "u": "υ", "o": "ο", "j": "ϕ",
                   "F": "Φ", "G": "Γ", "L": "Λ", "P": "Π", "Q": "Θ", "Y": "Ψ", "X": "Ξ", "ò": "∫"]
        } else {
            return text
        }
        // Symbol faces are often spelled in the private range (U+F0xx).
        return String(text.map { ch -> Character in
            var key = ch
            if let v = ch.unicodeScalars.first?.value, (0xF020 ... 0xF0FF).contains(v), let u = Unicode.Scalar(v - 0xF000) {
                key = Character(u)
            }
            return map[key] ?? key
        })
    }

    /// A device-independent bitmap (header, palette, bits) as a BMP file,
    /// which the image codec reads; its index among `bitmaps`.
    mutating func bitmap(header: Int, headerLength: Int, bits: Int? = nil, bitsLength: Int = 0, alpha: Bool = false) -> (index: Int, width: Double, height: Double)? {
        guard header >= 0, header + 16 <= bytes.count else { return nil }
        let size = u32(header)
        var width = 0, height = 0, palette = 0
        if size == 12 {
            width = u16(header + 4); height = u16(header + 6)
            let depth = u16(header + 10)
            if depth > 0, depth <= 8 { palette = (1 << depth) * 3 }
        } else if size >= 40, size <= 124 {
            width = i32(header + 4); height = i32(header + 8)
            guard height > -20_000 else { return nil }
            height = abs(height)
            let depth = u16(header + 14), compression = u32(header + 16), used = u32(header + 32)
            guard used >= 0, used <= 65_536, depth > 0, depth <= 32 else { return nil }
            if depth <= 8 { palette = (used > 0 ? used : 1 << depth) * 4 } else { palette = used * 4 }
            if compression == 3, size == 40 { palette += 12 }
        } else {
            return nil
        }
        guard width > 0, height > 0, width < 20_000, height < 20_000 else { return nil }
        var dib: [UInt8]
        guard headerLength > 0, headerLength <= bytes.count, bitsLength >= 0, bitsLength <= bytes.count else { return nil }
        if let bits {
            // Header and bits apart (EMF): the header with its palette, then
            // the bits.
            guard bits >= 0, bits <= bytes.count else { return nil }
            let headEnd = min(bytes.count, header + min(headerLength, size + palette))
            let bitsEnd = min(bytes.count, bits + bitsLength)
            guard bits <= bitsEnd, header <= headEnd else { return nil }
            dib = Array(bytes[header ..< headEnd])
            // A header shorter than its palette says: pad, so the offset holds.
            if dib.count < size + palette { dib += [UInt8](repeating: 0, count: size + palette - dib.count) }
            dib += bytes[bits ..< bitsEnd]
        } else {
            let end = min(bytes.count, header + headerLength)
            guard header < end else { return nil }
            dib = Array(bytes[header ..< end])
        }
        var offset = 14 + size + palette
        guard dib.count + 14 > offset else { return nil }
        // An alpha blend's 32-bit bitmap carries its alpha in the fourth byte,
        // which a plain header tells a reader to ignore (and the transparent
        // surround comes out black). Said outright: a V4 header with masks.
        let masked = u32(header + 16) == 3 && palette == 12
        if alpha, size == 40, u16(header + 14) == 32, (u32(header + 16) == 0 && palette == 0) || masked, dib.count >= 40 + palette {
            var v4 = Array(dib[0 ..< 40]) + [UInt8](repeating: 0, count: 68)
            v4[0] = 108; v4[16] = 3
            if masked {
                // The file's own colour masks, and alpha in the bits they leave.
                for k in 0 ..< 12 { v4[40 + k] = dib[40 + k] }
                for k in 0 ..< 4 { v4[52 + k] = ~(dib[40 + k] | dib[44 + k] | dib[48 + k]) }
            } else {
                v4[42] = 0xFF; v4[45] = 0xFF; v4[48] = 0xFF; v4[55] = 0xFF   // red, green, blue, alpha masks
            }
            dib = v4 + dib[(40 + palette)...]
            offset = 14 + 108
        }
        var file: [UInt8] = [0x42, 0x4D]
        func le(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)] }
        file += le(14 + dib.count) + [0, 0, 0, 0] + le(offset) + dib
        bitmaps.append(ImageAttachment(data: Data(file), width: Double(width), height: Double(height),
                                       name: "metafile-\(bitmaps.count).bmp"))
        return (bitmaps.count - 1, Double(width), Double(height))
    }

    /// A blit: the bitmap drawn into a rectangle, or — with no bitmap, or a
    /// pattern operation — the rectangle filled.
    mutating func blit(rop: Int, dest: Rect, source: Rect?, image: (index: Int, width: Double, height: Double)?) {
        let a = map(dest.left, dest.top), b = map(dest.right, dest.bottom)
        let at = Rect.fromLTRB(min(a.dx, b.dx), min(a.dy, b.dy), max(a.dx, b.dx), max(a.dy, b.dy))
        let box = rect(dest.left, dest.top, dest.right, dest.bottom)
        switch rop & 0xFFFFFF {
        case 0x000042: steps.append(.fill(box, Color(0xFF000000)))   // BLACKNESS
        case 0xFF0062: steps.append(.fill(box, Color(0xFFFFFFFF)))   // WHITENESS
        case 0xF00021, 0x5A0049: fill(box)                           // PATCOPY, PATINVERT
        case 0xAA0029, 0x550009: break                               // no-op, DSTINVERT
        default:
            guard let image else { return }
            // The mask idioms: AND darkens through a mask, OR and XOR put
            // the picture back over what the mask left black.
            let blend: BlendMode?
            switch rop & 0xFFFFFF {
            case 0x8800C6: blend = .multiply       // SRCAND
            case 0xEE0086: blend = .screen         // SRCPAINT
            case 0x660046: blend = .difference     // SRCINVERT
            default: blend = nil
            }
            steps.append(.image(image.index, source: source, at: at, blend: blend))
        }
    }

    // MARK: WMF

    mutating func addObject(_ o: Object) {
        var slot = 0
        while objects[slot] != nil { slot += 1 }
        objects[slot] = o
    }

    func ansi(_ at: Int, _ count: Int) -> String {
        guard at >= 0, count > 0, at + count <= bytes.count else { return "" }
        // Windows-1252, whose 0x80…0x9F differ from Latin-1.
        let high: [UInt32] = [0x20AC, 0x81, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, 0x02C6, 0x2030, 0x0160, 0x2039, 0x0152,
                              0x8D, 0x017D, 0x8F, 0x90, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, 0x02DC, 0x2122,
                              0x0161, 0x203A, 0x0153, 0x9D, 0x017E, 0x0178]
        var s = String.UnicodeScalarView()
        for b in bytes[at ..< at + count] {
            let v: UInt32 = (0x80 ... 0x9F).contains(b) ? high[Int(b) - 0x80] : UInt32(b)
            if let u = Unicode.Scalar(v) { s.append(u) }
        }
        return String(s)
    }

    mutating func playWMF() {
        isWMF = true
        var p = 0
        var placeable: Rect? = nil
        if bytes.count > 22, bytes[0] == 0xD7, bytes[1] == 0xCD {
            placeable = Rect.fromLTRB(Double(i16(6)), Double(i16(8)), Double(i16(10)), Double(i16(12)))
            p = 22
        }
        p += u16(p + 2) * 2
        var org: Offset? = nil
        while p + 6 <= bytes.count {
            let words = u32(p), fn = u16(p + 4)
            guard words >= 3, words <= bytes.count else { break }
            let size = words * 2
            guard p + size <= bytes.count else { break }
            if fn == 0 { break }
            let a = p + 6   // the parameters, last argument first
            switch fn {
            case 0x020B:   // SetWindowOrg
                dc.winOrg = Offset(Double(i16(a + 2)), Double(i16(a)))
                org = org ?? dc.winOrg
            case 0x020C:   // SetWindowExt
                dc.winExt = Size(Double(i16(a + 2)), Double(i16(a)))
                if frame == nil, dc.winExt.width != 0, dc.winExt.height != 0 {
                    let o = org ?? dc.winOrg
                    // (Its size, not its sign: a window of negative height
                    // — y up, cooper's cartoon at origin 1215, extent
                    // −1824 — maps into it upside down, and a frame of
                    // negative height drew nothing.)
                    frame = Rect.fromLTWH(o.dx, o.dy, abs(dc.winExt.width), abs(dc.winExt.height))
                }
            case 0x001E: save()
            case 0x0127: restore(i16(a))
            case 0x0102: dc.bkOpaque = u16(a) == 2
            case 0x0201: dc.bkColor = color(a)
            case 0x0209: dc.textColor = color(a)
            case 0x012E: dc.textAlign = u16(a)
            case 0x0106: dc.winding = u16(a) == 2
            case 0x02FA:   // CreatePenIndirect
                let style = u16(a) & 0xF
                addObject(.pen(Player.Pen(color: color(a + 6), width: Double(i16(a + 2)), null: style == 5)))
            case 0x02FC:   // CreateBrushIndirect
                addObject(.brush(Player.Brush(color: color(a + 2), null: u16(a) == 1)))
            case 0x02FB:   // CreateFontIndirect
                var f = Player.Font()
                f.height = Double(i16(a))
                if f.height == 0 { f.height = 12 }
                f.escapement = Double(i16(a + 4))
                f.bold = u16(a + 8) >= 600
                f.italic = a + 10 < bytes.count && bytes[a + 10] != 0
                f.underline = a + 11 < bytes.count && bytes[a + 11] != 0
                let nameAt = a + 18
                var n = 0
                while nameAt + n < p + size, n < 32, bytes[nameAt + n] != 0 { n += 1 }
                let face = ansi(nameAt, n)
                if !face.isEmpty { f.face = face }
                addObject(.font(f))
            case 0x0142:   // DibCreatePatternBrush: style, usage, bitmap
                // A one-bit pattern (style BS_PATTERN) paints its clear bits
                // in the text colour and its set ones in the background's:
                // drawn as the two mixed by their share of the pattern
                // (lo-activex_scrollbar's troughs, a checker of their
                // colour and white, light grey and pale cyan in
                // PowerPoint's print). Others, a middle grey.
                let header = a + 4
                let width = u32(header + 4), height = abs(Int(Int32(truncatingIfNeeded: u32(header + 8))))
                let bits = u16(header + 14), headerSize = u32(header)
                if bits == 1, width > 0, height > 0, width <= 64, height <= 64, headerSize >= 40 {
                    let stride = (width + 31) / 32 * 4
                    let data = header + headerSize + 8   // past the two-colour table
                    var set = 0
                    if data + stride * height <= p + size {
                        for row in 0 ..< height {
                            for x in 0 ..< width where bytes[data + row * stride + x / 8] & (0x80 >> (x % 8)) != 0 { set += 1 }
                        }
                        let t = Double(set) / Double(width * height)
                        func mix(_ fg: Int, _ bg: Int) -> Int { Int((Double(fg) * (1 - t) + Double(bg) * t).rounded()) }
                        let f = dc.textColor, b = dc.bkColor
                        addObject(.brush(Player.Brush(color: Color(rgbo: mix(f.red, b.red), mix(f.green, b.green), mix(f.blue, b.blue), 1), null: false)))
                        break
                    }
                }
                addObject(.brush(Player.Brush(color: Color(0xFFC0C0C0), null: false)))
            case 0x01F9:   // CreatePatternBrush: the pattern's middle grey
                addObject(.brush(Player.Brush(color: Color(0xFFC0C0C0), null: false)))
            case 0x00F7, 0x06FF, 0x02FD, 0x06FE: addObject(.other)   // palette, region, bitmap
            case 0x012D: select(objects[u16(a)])
            case 0x01F0: objects[u16(a)] = nil
            case 0x0214: moveTo(Double(i16(a + 2)), Double(i16(a)))
            case 0x0213: lineTo(Double(i16(a + 2)), Double(i16(a)))
            case 0x0324, 0x0325:   // Polygon, Polyline
                let n = u16(a)
                guard n > 0, a + 2 + n * 4 <= p + size else { break }
                let pts = (0 ..< n).map { Offset(Double(i16(a + 2 + $0 * 4)), Double(i16(a + 4 + $0 * 4))) }
                if fn == 0x0324 { shape(polygon(pts, close: true)) } else { stroke(polygon(pts, close: false)) }
            case 0x0538:   // PolyPolygon
                let polys = u16(a)
                guard polys > 0, a + 2 + polys * 2 <= p + size else { break }
                let counts = (0 ..< polys).map { u16(a + 2 + $0 * 2) }
                var at = a + 2 + polys * 2
                guard at + counts.reduce(0, +) * 4 <= p + size else { break }
                let whole = Path()
                whole.fillType = dc.winding ? .nonZero : .evenOdd
                for n in counts {
                    let pts = (0 ..< n).map { Offset(Double(i16(at + $0 * 4)), Double(i16(at + 2 + $0 * 4))) }
                    whole.addPath(polygon(pts, close: true), Offset.zero)
                    at += n * 4
                }
                shape(whole)
            case 0x041B:   // Rectangle: bottom, right, top, left
                shape(rect(Double(i16(a + 6)), Double(i16(a + 4)), Double(i16(a + 2)), Double(i16(a))))
            case 0x061C:   // RoundRect, as its rectangle
                shape(rect(Double(i16(a + 10)), Double(i16(a + 8)), Double(i16(a + 6)), Double(i16(a + 4))))
            case 0x0418:   // Ellipse
                shape(ellipse(Double(i16(a + 6)), Double(i16(a + 4)), Double(i16(a + 2)), Double(i16(a))))
            case 0x0416:   // IntersectClipRect
                intersectClip(rect(Double(i16(a + 6)), Double(i16(a + 4)), Double(i16(a + 2)), Double(i16(a))))
            case 0x061D:   // PatBlt: rop, height, width, y, x
                let h = Double(i16(a + 4)), w = Double(i16(a + 6)), y = Double(i16(a + 8)), x = Double(i16(a + 10))
                blit(rop: u32(a), dest: Rect.fromLTWH(x, y, w, h), source: nil, image: nil)
            case 0x0521:   // TextOut: length, string, y, x
                let n = u16(a), after = a + 2 + (n + 1) / 2 * 2
                text(ansi(a + 2, n), at: Offset(Double(i16(after + 2)), Double(i16(after))), opaque: nil)
            case 0x0A32:   // ExtTextOut: y, x, length, options, [rectangle], string
                let y = Double(i16(a)), x = Double(i16(a + 2)), n = u16(a + 4), options = u16(a + 6)
                var at = a + 8
                var box: Rect? = nil
                if options & 6 != 0 {
                    box = Rect.fromLTRB(Double(i16(at)), Double(i16(at + 2)), Double(i16(at + 4)), Double(i16(at + 6)))
                    at += 8
                }
                guard at + n <= p + size else { break }
                // (An empty one that only fills its box, in the transparent
                // background mode, fills nothing in PowerPoint's print:
                // lo-activex_textbox's control pictures draw no green.)
                let fills = options & 2 != 0 && (n > 0 || dc.bkOpaque)
                text(ansi(at, n), at: Offset(x, y), opaque: fills ? box : nil)
            case 0x0940:   // DibBitBlt: rop, ySrc, xSrc, height, width, yDest, xDest, bitmap
                if size == 6 + 18 {   // no bitmap: rop, ySrc, xSrc, (unused), height, width, yDest, xDest
                    let h = Double(i16(a + 10)), w = Double(i16(a + 12)), y = Double(i16(a + 14)), x = Double(i16(a + 16))
                    blit(rop: u32(a), dest: Rect.fromLTWH(x, y, w, h), source: nil, image: nil)
                } else {
                    let sy = Double(i16(a + 4)), sx = Double(i16(a + 6))
                    let h = Double(i16(a + 8)), w = Double(i16(a + 10)), y = Double(i16(a + 12)), x = Double(i16(a + 14))
                    let image = bitmap(header: a + 16, headerLength: p + size - (a + 16))
                    // Blitted one to one: as much of the source as the target is, in device units.
                    let k = scaleX
                    blit(rop: u32(a), dest: Rect.fromLTWH(x, y, w, h),
                         source: image.map { _ in Rect.fromLTWH(sx, sy, abs(w) * k, abs(h) * k) }, image: image)
                }
            case 0x0B41:   // DibStretchBlt: rop, srcH, srcW, ySrc, xSrc, destH, destW, yDest, xDest, bitmap
                let sh = Double(i16(a + 4)), sw = Double(i16(a + 6)), sy = Double(i16(a + 8)), sx = Double(i16(a + 10))
                let h = Double(i16(a + 12)), w = Double(i16(a + 14)), y = Double(i16(a + 16)), x = Double(i16(a + 18))
                let image = size > 6 + 22 ? bitmap(header: a + 20, headerLength: p + size - (a + 20)) : nil
                blit(rop: u32(a), dest: Rect.fromLTWH(x, y, w, h), source: Rect.fromLTWH(sx, sy, sw, sh), image: image)
            case 0x0F43:   // StretchDIB: rop, usage, srcH, srcW, ySrc, xSrc, destH, destW, yDest, xDest, bitmap
                let sh = Double(i16(a + 6)), sw = Double(i16(a + 8)), sy = Double(i16(a + 10)), sx = Double(i16(a + 12))
                let h = Double(i16(a + 14)), w = Double(i16(a + 16)), y = Double(i16(a + 18)), x = Double(i16(a + 20))
                let image = bitmap(header: a + 22, headerLength: p + size - (a + 22))
                // The source rectangle counts from the bitmap's bottom row.
                let source = image.map { Rect.fromLTWH(sx, $0.height - sy - sh, sw, sh) }
                blit(rop: u32(a), dest: Rect.fromLTWH(x, y, w, h), source: source, image: image)
            default:
                break
            }
            p += size
        }
        // The window is the picture; a file that sets none is its placeable
        // header's box.
        bounds = frame ?? placeable
        // A window's last unit lands on the frame's edge, and what is drawn
        // in it falls outside: a control's picture of 175 by 114 is drawn
        // 174 by 113 across its frame, its right and bottom rules left out.
        if let f = frame, f.width > 1, f.height > 1 {
            bounds = Rect.fromLTWH(f.left, f.top, f.width - 1, f.height - 1)
        }
    }

    // MARK: EMF

    func points16(_ at: Int, _ n: Int) -> [Offset] {
        guard n > 0, n < 1_000_000, at >= 0, at + n * 4 <= bytes.count else { return [] }
        return (0 ..< n).map { Offset(Double(i16(at + $0 * 4)), Double(i16(at + 2 + $0 * 4))) }
    }
    func points32(_ at: Int, _ n: Int) -> [Offset] {
        guard n > 0, n < 1_000_000, at >= 0, at + n * 8 <= bytes.count else { return [] }
        return (0 ..< n).map { Offset(Double(i32(at + $0 * 8)), Double(i32(at + 4 + $0 * 8))) }
    }

    func utf16(_ at: Int, _ count: Int) -> String {
        guard at >= 0, count > 0, at + count * 2 <= bytes.count else { return "" }
        return String(decoding: (0 ..< count).map { UInt16(u16(at + $0 * 2)) }, as: UTF16.self)
    }

    mutating func selectStock(_ n: Int) {
        switch n {
        case 0: dc.brush = Brush(color: Color(0xFFFFFFFF), null: false)
        case 1: dc.brush = Brush(color: Color(0xFFC0C0C0), null: false)
        case 2: dc.brush = Brush(color: Color(0xFF808080), null: false)
        case 3: dc.brush = Brush(color: Color(0xFF404040), null: false)
        case 4: dc.brush = Brush(color: Color(0xFF000000), null: false)
        case 5: dc.brush = Brush(color: Color(0xFFFFFFFF), null: true)
        case 6: dc.pen = Pen(color: Color(0xFFFFFFFF), width: 0, null: false)
        case 7: dc.pen = Pen(color: Color(0xFF000000), width: 0, null: false)
        case 8: dc.pen = Pen(color: Color(0xFF000000), width: 0, null: true)
        case 10 ... 17: dc.font = Font()
        default: break
        }
    }

    mutating func playEMF() {
        guard bytes.count >= 88 else { return }
        // The frame (hundredths of a millimetre) in device units; the bounds
        // when the header's device size says nothing.
        let devW = Double(i32(72)), devH = Double(i32(76)), mmW = Double(i32(80)), mmH = Double(i32(84))
        let box = Rect.fromLTRB(Double(i32(8)), Double(i32(12)), Double(i32(16)) + 1, Double(i32(20)) + 1)
        if devW > 0, devH > 0, mmW > 0, mmH > 0 {
            let kx = devW / (mmW * 100), ky = devH / (mmH * 100)
            let f = Rect.fromLTRB(Double(i32(24)) * kx, Double(i32(28)) * ky, Double(i32(32)) * kx, Double(i32(36)) * ky)
            // A unit wider and taller, the frame counted to and including
            // its last unit: lo-tdf143222's sheet, 1569 units across its
            // frame, prints 1570 across, ecodesign's table 496 for 495.
            bounds = f.width > 0 && f.height > 0 ? Rect.fromLTWH(f.left, f.top, f.width + 1, f.height + 1) : box
        } else {
            bounds = box
        }
        var p = 0
        while p + 8 <= bytes.count {
            let type = u32(p), size = u32(p + 4)
            guard size >= 8, size <= bytes.count, p + size <= bytes.count else { break }
            if type == 14 { break }
            let a = p + 8
            switch type {
            case 9: dc.winExt = Size(Double(i32(a)), Double(i32(a + 4)))
            case 10: dc.winOrg = Offset(Double(i32(a)), Double(i32(a + 4)))
            case 11: dc.vpExt = Size(Double(i32(a)), Double(i32(a + 4)))
            case 12: dc.vpOrg = Offset(Double(i32(a)), Double(i32(a + 4)))
            case 17: dc.scales = u32(a) == 7 || u32(a) == 8
            case 18: dc.bkOpaque = u32(a) == 2
            case 19: dc.winding = u32(a) == 2
            case 22: dc.textAlign = u32(a)
            case 24: dc.textColor = color(a)
            case 25: dc.bkColor = color(a)
            case 27: moveTo(Double(i32(a)), Double(i32(a + 4)))
            case 54: lineTo(Double(i32(a)), Double(i32(a + 4)))
            case 33: save()
            case 34: restore(i32(a))
            case 35:   // SetWorldTransform
                dc.a = f32(a); dc.b = f32(a + 4); dc.c = f32(a + 8); dc.d = f32(a + 12); dc.e = f32(a + 16); dc.f = f32(a + 20)
            case 36:   // ModifyWorldTransform
                let m = (a: f32(a), b: f32(a + 4), c: f32(a + 8), d: f32(a + 12), e: f32(a + 16), f: f32(a + 20))
                let w = (a: dc.a, b: dc.b, c: dc.c, d: dc.d, e: dc.e, f: dc.f)
                switch u32(a + 24) {
                case 1: dc.a = 1; dc.b = 0; dc.c = 0; dc.d = 1; dc.e = 0; dc.f = 0
                case 2:   // the new one applied first
                    dc.a = m.a * w.a + m.b * w.c; dc.b = m.a * w.b + m.b * w.d
                    dc.c = m.c * w.a + m.d * w.c; dc.d = m.c * w.b + m.d * w.d
                    dc.e = m.e * w.a + m.f * w.c + w.e; dc.f = m.e * w.b + m.f * w.d + w.f
                case 3:   // the new one applied last
                    dc.a = w.a * m.a + w.b * m.c; dc.b = w.a * m.b + w.b * m.d
                    dc.c = w.c * m.a + w.d * m.c; dc.d = w.c * m.b + w.d * m.d
                    dc.e = w.e * m.a + w.f * m.c + m.e; dc.f = w.e * m.b + w.f * m.d + m.f
                default:
                    dc.a = m.a; dc.b = m.b; dc.c = m.c; dc.d = m.d; dc.e = m.e; dc.f = m.f
                }
            case 37:   // SelectObject
                let ih = u32(a)
                // (The high bit, tested as 32 bits: `Int` is that wide in the browser.)
                if UInt32(truncatingIfNeeded: ih) & 0x8000_0000 != 0 { selectStock(ih & 0xFF) } else { select(objects[ih]) }
            case 38:   // CreatePen: index, style, width, (y), colour
                objects[u32(a)] = .pen(Pen(color: color(a + 16), width: Double(i32(a + 8)), null: u32(a + 4) & 0xF == 5))
            case 95:   // ExtCreatePen: index, four offsets, style, width, brush style, colour
                objects[u32(a)] = .pen(Pen(color: color(a + 32), width: Double(i32(a + 24)), null: u32(a + 20) & 0xF == 5))
            case 39:   // CreateBrushIndirect: index, style, colour
                objects[u32(a)] = .brush(Brush(color: color(a + 8), null: u32(a + 4) == 1))
            case 93, 94:   // a pattern brush, as its middle grey
                objects[u32(a)] = .brush(Brush(color: Color(0xFFC0C0C0), null: false))
            case 82:   // ExtCreateFontIndirectW
                var f = Font()
                f.height = Double(i32(a + 4))
                if f.height == 0 { f.height = 12 }
                f.escapement = Double(i32(a + 12))
                f.bold = i32(a + 20) >= 600
                f.italic = a + 24 < bytes.count && bytes[a + 24] != 0
                f.underline = a + 25 < bytes.count && bytes[a + 25] != 0
                var n = 0
                while n < 32, a + 32 + n * 2 + 2 <= p + size, u16(a + 32 + n * 2) != 0 { n += 1 }
                let face = utf16(a + 32, n)
                if !face.isEmpty { f.face = face }
                objects[u32(a)] = .font(f)
            case 40: objects[u32(a)] = nil
            case 42: shape(ellipse(Double(i32(a)), Double(i32(a + 4)), Double(i32(a + 8)), Double(i32(a + 12))))
            case 43, 44: shape(rect(Double(i32(a)), Double(i32(a + 4)), Double(i32(a + 8)), Double(i32(a + 12))))
            case 30: intersectClip(rect(Double(i32(a)), Double(i32(a + 4)), Double(i32(a + 8)), Double(i32(a + 12))))
            case 75:   // ExtSelectClipRgn: byte count, mode, region (device units)
                let count = u32(a), mode = u32(a + 4)
                if count < 32 { setClip(nil); break }
                let n = u32(a + 8 + 8)
                guard n >= 0, n < 100_000, a + 8 + 32 + n * 16 <= p + size else { break }
                let region = Path()
                for k in 0 ..< n {
                    let r = a + 8 + 32 + k * 16
                    region.addRect(Rect.fromLTRB(Double(i32(r)), Double(i32(r + 4)), Double(i32(r + 8)), Double(i32(r + 12))))
                }
                if mode == 1, let old = dc.clip { setClip(Path.combine(.intersect, old, region)) } else { setClip(region) }
            case 59: path = Path(); building = true; figureOpen = false
            case 60: building = false
            case 61: path?.close(); figureOpen = false
            case 68: path = nil; building = false
            case 62, 63, 64:   // FillPath, StrokeAndFillPath, StrokePath
                guard let done = path else { break }
                done.fillType = dc.winding ? .nonZero : .evenOdd
                if type != 64 { fill(done) }
                if type != 62 { stroke(done) }
                path = nil
            case 67:   // SelectClipPath
                guard let done = path else { break }
                if u32(a) == 1, let old = dc.clip { setClip(Path.combine(.intersect, old, done)) } else { setClip(done) }
                path = nil
            case 86, 87, 3, 4:   // Polygon16, Polyline16, Polygon, Polyline
                let n = u32(a + 16)
                let pts = type > 4 ? points16(a + 20, n) : points32(a + 20, n)
                guard !pts.isEmpty else { break }
                let closed = type == 86 || type == 3
                let poly = polygon(pts, close: closed)
                if building { path?.addPath(poly, Offset.zero) } else if closed { shape(poly) } else { stroke(poly) }
            case 89, 6: continueTo(type == 89 ? points16(a + 20, u32(a + 16)) : points32(a + 20, u32(a + 16)), curves: false)
            case 88, 5: continueTo(type == 88 ? points16(a + 20, u32(a + 16)) : points32(a + 20, u32(a + 16)), curves: true)
            case 85, 2:   // PolyBezier: a start point, then curves
                let pts = type == 85 ? points16(a + 20, u32(a + 16)) : points32(a + 20, u32(a + 16))
                guard pts.count >= 4 else { break }
                moveTo(pts[0].dx, pts[0].dy)
                continueTo(Array(pts.dropFirst()), curves: true)
            case 90, 91, 7, 8:   // PolyPolyline16, PolyPolygon16, and the 32-bit ones
                let polys = u32(a + 16), wide = type < 90
                guard polys > 0, polys < 100_000, a + 24 + polys * 4 <= p + size else { break }
                var at = a + 24 + polys * 4
                let closed = type == 91 || type == 8
                let whole = Path()
                whole.fillType = dc.winding ? .nonZero : .evenOdd
                for k in 0 ..< polys {
                    let n = u32(a + 24 + k * 4)
                    let pts = wide ? points32(at, n) : points16(at, n)
                    guard !pts.isEmpty else { break }
                    whole.addPath(polygon(pts, close: closed), Offset.zero)
                    at += n * (wide ? 8 : 4)
                }
                if building { path?.addPath(whole, Offset.zero) } else if closed { shape(whole) } else { stroke(whole) }
            case 84:   // ExtTextOutW: bounds, mode, scales, reference, count, string offset, options, rectangle
                let x = Double(i32(a + 28)), y = Double(i32(a + 32)), n = u32(a + 36), at = p + u32(a + 40), options = u32(a + 44)
                let box = Rect.fromLTRB(Double(i32(a + 48)), Double(i32(a + 52)), Double(i32(a + 56)), Double(i32(a + 60)))
                guard n < 100_000, at + n * 2 <= p + size else { break }
                // (ETO_GLYPH_INDEX: the string is the selected face's glyph
                // numbers, not text — what GDI records for shaped script.
                // zh-8d72961c's Arabic is Arial's glyphs so, and read as
                // UTF-16 it drew a row of Greek and Cyrillic; without that
                // face's own table it is left out.)
                guard options & 0x10 == 0 else { break }
                text(utf16(at, n), at: Offset(x, y), opaque: options & 2 != 0 ? box : nil)
            case 76, 77, 114:   // BitBlt, StretchBlt, AlphaBlend (StretchBlt's record, a blend where its raster op is)
                let x = Double(i32(a + 16)), y = Double(i32(a + 20)), w = Double(i32(a + 24)), h = Double(i32(a + 28))
                let sx = Double(i32(a + 36)), sy = Double(i32(a + 40))
                let head = u32(a + 76), headLength = u32(a + 80), bits = u32(a + 84), bitsLength = u32(a + 88)
                // (Per-pixel alpha when the blend's format says so: AC_SRC_ALPHA.)
                let perPixel = type == 114 && (u32(a + 32) >> 24) & 1 == 1
                let image = headLength > 0 ? bitmap(header: p + head, headerLength: headLength, bits: p + bits, bitsLength: bitsLength, alpha: perPixel) : nil
                var source: Rect? = nil
                if let image {
                    let sw = type != 76 ? Double(i32(a + 92)) : min(abs(w) * scaleX, image.width)
                    let sh = type != 76 ? Double(i32(a + 96)) : min(abs(h) * scaleY, image.height)
                    source = Rect.fromLTWH(sx, sy, sw, sh)
                }
                blit(rop: type == 114 ? 0xCC0020 : u32(a + 32), dest: Rect.fromLTWH(x, y, w, h), source: source, image: image)
            case 81:   // StretchDIBits
                let x = Double(i32(a + 16)), y = Double(i32(a + 20)), sx = Double(i32(a + 24)), sy = Double(i32(a + 28))
                let sw = Double(i32(a + 32)), sh = Double(i32(a + 36))
                let head = u32(a + 40), headLength = u32(a + 44), bits = u32(a + 48), bitsLength = u32(a + 52)
                let rop = u32(a + 60), w = Double(i32(a + 64)), h = Double(i32(a + 68))
                let image = headLength > 0 ? bitmap(header: p + head, headerLength: headLength, bits: p + bits, bitsLength: bitsLength) : nil
                let source = image.map { Rect.fromLTWH(sx, $0.height - sy - sh, sw, sh) }
                blit(rop: rop, dest: Rect.fromLTWH(x, y, w, h), source: source, image: image)
            default:
                break
            }
            p += size
        }
    }
}
