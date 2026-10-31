// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import OfficeText
import FlutterSwiftBridge
import Foundation

/// WordArt: a body whose `bodyPr` has a `prstTxWarp`. PowerPoint does not
/// lay such text out in its box — it fits the text TO the box, each line
/// stretched across it and bent between two curves (inflate, wave, can…),
/// or sets it along the box's ellipse at its own size (arch, circle).
///
/// There are no glyph outlines to bend here, so each character is drawn
/// through the affine map of its own cell: exact for the text that
/// follows a path, and for the bends as close as a character is small
/// against the curve — a wave's letters lean and ride it, they do not
/// themselves curve.
enum WordArt {
    /// The top and bottom of the band the text is stretched into, as
    /// fractions of the area's height at `u` across it — or nil for a
    /// preset this does not draw (the text is then laid out as usual).
    static func envelope(_ warp: TextWarp) -> ((Double) -> (top: Double, bottom: Double))? {
        func adj(_ d: Double) -> Double { (warp.adjust.first ?? d) / 100_000 }
        func bow(_ u: Double) -> Double { (2 * u - 1) * (2 * u - 1) }       // 1 at the ends, 0 in the middle
        func arc(_ u: Double) -> Double { 1 - (max(0, 1 - bow(u))).squareRoot() }   // the same, round
        switch warp.preset {
        case "textPlain": return { _ in (0, 1) }
        case "textInflate": let a = adj(18750); return { (a * bow($0), 1 - a * bow($0)) }
        case "textDeflate": let a = adj(18750); return { (a * (1 - bow($0)), 1 - a * (1 - bow($0))) }
        case "textInflateTop": let a = adj(40000); return { (a * bow($0), 1) }
        case "textInflateBottom": let a = adj(60000); return { (0, 1 - (1 - a) * bow($0)) }
        case "textDeflateTop": let a = adj(50000); return { (a * (1 - bow($0)), 1) }
        case "textDeflateBottom": let a = adj(50000); return { (0, a + (1 - a) * bow($0)) }
        case "textWave1": let a = adj(12500); return { let t = a * (1 - sin(2 * .pi * $0)); return (t, t + 1 - 2 * a) }
        case "textWave2": let a = adj(12500); return { let t = a * (1 + sin(2 * .pi * $0)); return (t, t + 1 - 2 * a) }
        case "textDoubleWave1": let a = adj(6250); return { let t = a * (1 - sin(4 * .pi * $0)); return (t, t + 1 - 2 * a) }
        case "textWave4": let a = adj(6250); return { let t = a * (1 + sin(4 * .pi * $0)); return (t, t + 1 - 2 * a) }
        case "textCanUp": let d = 1 - adj(85714); return { (d * arc($0), 1 - d + d * arc($0)) }
        case "textCanDown": let d = adj(14286); return { (d * (1 - arc($0)), 1 - d * arc($0)) }
        case "textTriangle": let a = adj(50000); return { (a * abs(2 * $0 - 1), 1) }
        case "textTriangleInverted": let a = adj(50000); return { (0, 1 - (1 - a) * abs(2 * $0 - 1)) }
        case "textChevron": let a = adj(25000); return { (a * abs(2 * $0 - 1), 1 - a + a * abs(2 * $0 - 1)) }
        case "textChevronInverted": let a = adj(75000); return { ((1 - a) * (1 - abs(2 * $0 - 1)), 1 - (1 - a) * abs(2 * $0 - 1)) }
        case "textSlantUp": let a = adj(55556); return { (a * (1 - $0), 1 - a * $0) }
        // The adjustment is the band's thickness: at 100000 the text is
        // rectangular, at 28569 it is thin and slopes most. ECMA's two
        // paths join (0,0) to (1,1-a), and (0,a) to (1,1).
        case "textSlantDown": let a = max(0.28569, min(1, adj(44445))); return { ((1 - a) * $0, a + (1 - a) * $0) }
        // Curve: the text shrinks (or grows) along a quarter turn over a
        // level foot.
        case "textCurveDown": let a = adj(45977); return { (a * sin($0 * .pi / 2), 1) }
        case "textCurveUp": let a = adj(45977); return { (a * sin((1 - $0) * .pi / 2), 1) }
        // Stop: the corners cut, as a stop sign's.
        case "textStop":
            let a = adj(25000)
            return { u in let t = a * max(0, max(1 - 3 * u, 3 * u - 2)); return (t, 1 - t) }
        // Fade: the text narrows toward one side.
        case "textFadeRight": let a = adj(33333); return { ($0 * a, 1 - $0 * a) }
        case "textFadeLeft": let a = adj(33333); return { ((1 - $0) * a, 1 - (1 - $0) * a) }
        case "textFadeUp", "textFadeDown": return { _ in (0, 1) }
        // Cascade: the lines climb (or descend) and shrink as they go.
        case "textCascadeUp": let a = adj(44444); return { (0, 1 - (1 - a) * $0) }
        case "textCascadeDown": let a = adj(44444); return { (0, a + (1 - a) * $0) }
        default: return nil
        }
    }

    /// How far apart WordArt's lines stand, in heights of a line's box:
    /// the best fit over the corpus's multi-line WordArt (1.0 to 1.6
    /// tried; 1.3 best in sum, ImportWordArtGradient's own best, the
    /// tdf155327 and tdf125085 ones a little further apart).
    static let linePitch = 1.3

    /// The presets whose text follows the area's ellipse.
    static let followsPath: Set<String> = ["textArchUp", "textArchDown", "textCircle", "textButton"]
    /// The presets drawn in bands of their own making.
    private static let banded: Set<String> = ["textDeflateInflate", "textDeflateInflateDeflate", "textRingInside", "textRingOutside",
                                              "textArchUpPour", "textArchDownPour", "textCirclePour", "textButtonPour"]

    static func draws(_ warp: TextWarp) -> Bool { followsPath.contains(warp.preset) || envelope(warp) != nil || banded.contains(warp.preset) }

    private struct Glyph {
        /// The glyph in its plain colour: what is measured, and what is
        /// drawn when the run has no fill of its own.
        let painter: TextPainter
        let text: String
        let style: (Paint) -> Flutter.TextStyle
        let look: RunLook?
        var ink: Rect? { painter.getGlyphInkBounds() }
        var width: Double { painter.width }
    }

    private struct Line {
        var glyphs: [Glyph] = []
        var alignment: ParagraphAlignment = .left
        var width: Double { glyphs.reduce(0) { $0 + $1.width } }
        var height: Double { glyphs.map { $0.painter.height }.max() ?? 0 }
    }

    /// A line's glyphs in the order they stand, left to right: a line
    /// whose first strong letter is Hebrew or Arabic runs right to left,
    /// each stretch of Latin letters and digits in it reading forwards
    /// (tdf125085_WordArtFontText's מדינת ישראל came out letter-reversed).
    private static func visualOrder(_ glyphs: [Glyph]) -> [Glyph] {
        func strong(_ g: Glyph) -> Bool? {
            guard let u = g.text.unicodeScalars.first else { return nil }
            if (0x0590 ... 0x08FF).contains(u.value) || (0xFB1D ... 0xFDFF).contains(u.value) || (0xFE70 ... 0xFEFF).contains(u.value) { return true }
            if u.properties.isAlphabetic || ("0" ... "9").contains(Character(u)) { return false }
            return nil
        }
        guard let first = glyphs.lazy.compactMap(strong).first, first else { return glyphs }
        var out: [Glyph] = []
        var i = 0
        // Reversed as a whole, the left-to-right stretches put back.
        var pieces: [[Glyph]] = []
        while i < glyphs.count {
            if strong(glyphs[i]) == false {
                var j = i
                while j < glyphs.count, strong(glyphs[j]) != true { j += 1 }
                // (Trailing neutrals belong to the right-to-left text.)
                var end = j
                while end > i, strong(glyphs[end - 1]) == nil { end -= 1 }
                pieces.append(Array(glyphs[i ..< end]))
                i = end
            } else {
                pieces.append([glyphs[i]])
                i += 1
            }
        }
        for piece in pieces.reversed() { out += piece }
        return out
    }

    /// Draws `shape`'s text in its bend, in the shape's own space (`r` is
    /// its frame). False when the preset is not one this draws.
    static func paint(_ shape: SlideShape, _ r: Rect, _ canvas: any Canvas, pxPerPt px: Double, cache: SlideTextCache) -> Bool {
        guard let warp = shape.warp, draws(warp), let doc = shape.text?.document, let theme = shape.textTheme else { return false }
        // Text on a path keeps the body's insets; text fitted to the box
        // is fitted to all of it.
        let area = followsPath.contains(warp.preset)
            ? Rect.fromLTRB(r.left + shape.drawInsets.left * px, r.top + shape.drawInsets.top * px,
                            r.right - shape.drawInsets.right * px, r.bottom - shape.drawInsets.bottom * px)
            : r
        guard area.width > 1, area.height > 1 else { return false }
        let scale = px / theme.pixelsPerPoint
        let keepLooks = shape.runLooks.count == doc.paragraphs.count
        var lines: [Line] = []
        for (pi, p) in doc.paragraphs.enumerated() where !p.text.isEmpty {
            var line = Line()
            line.alignment = p.style.alignment
            // The looks hold while they still cover the paragraph they were read with.
            let units = Array(p.text.utf16)
            var looks = keepLooks ? shape.runLooks[pi] : []
            if looks.reduce(0, { $0 + $1.length }) != units.count { looks = [] }
            func look(at offset: Int) -> RunLook? {
                var end = 0
                for l in looks { end += l.length; if offset < end { return l.isPlain ? nil : l } }
                return nil
            }
            var at = 0
            for run in p.runs {
                let start = at
                let text = String(decoding: units[at ..< min(units.count, at + run.length)], as: UTF16.self)
                at += run.length
                let base = theme.textStyle(for: run.style, in: p.style, scale: scale)
                var offset = start
                for ch in text {
                    defer { offset += String(ch).utf16.count }
                    guard ch != "\n" else { continue }
                    line.glyphs.append(_glyph(String(ch), base, look(at: offset)))
                }
            }
            line.glyphs = visualOrder(line.glyphs)
            if !line.glyphs.isEmpty { lines.append(line) }
        }
        defer { for l in lines { for g in l.glyphs { g.painter.dispose() } } }
        guard !lines.isEmpty else { return true }
        _paint(lines, warp, area, canvas, pxPerPt: px, cache: cache, shadow: nil)
        return true
    }

    /// A shadow cast under WordArt's letters (VML's `v:shadow` on Word's
    /// WordArt): the letters again in `color`, moved `offset` points and
    /// put through `matrix` — VML's perspective, x' = sxx x + sxy y and
    /// y' = syx x + syy y about `origin` (fractions of the area from its
    /// centre, VML's -0.5 to 0.5).
    struct Shadow {
        var color: Color
        var offset = Offset(0, 0)
        var matrix = (sxx: 1.0, sxy: 0.0, syx: 0.0, syy: 1.0)
        var origin = Offset(0, 0)
    }

    /// WordArt from runs read elsewhere than a slide — a Word document's
    /// VML textpath: each line's runs, as text in a style (its colour the
    /// letters' own) and a look, fitted into `area` by `warp`.
    @discardableResult
    static func paint(lines paragraphs: [[(text: String, style: Flutter.TextStyle, look: RunLook?)]], alignment: ParagraphAlignment,
                      warp: TextWarp, area: Rect, canvas: any Canvas, pxPerPt px: Double, shadow: Shadow? = nil,
                      fitsPath: Bool = false, fitsInk: Bool = false) -> Bool {
        guard draws(warp), area.width > 1, area.height > 1 else { return false }
        var lines: [Line] = []
        for runs in paragraphs {
            var line = Line()
            line.alignment = alignment
            for run in runs {
                for ch in run.text where ch != "\n" { line.glyphs.append(_glyph(String(ch), run.style, run.look)) }
            }
            line.glyphs = visualOrder(line.glyphs)
            if !line.glyphs.isEmpty { lines.append(line) }
        }
        defer { for l in lines { for g in l.glyphs { g.painter.dispose() } } }
        guard !lines.isEmpty else { return true }
        _paint(lines, warp, area, canvas, pxPerPt: px, cache: nil, shadow: shadow, fitsPath: fitsPath, fitsInk: fitsInk)
        return true
    }

    /// One character as WordArt measures and draws it: at `base`'s face and
    /// size on a line one em high.
    private static func _glyph(_ ch: String, _ base: Flutter.TextStyle, _ look: RunLook?) -> Glyph {
        func style(_ paint: Paint) -> Flutter.TextStyle {
            Flutter.TextStyle(fontSize: base.fontSize, fontWeight: base.fontWeight, fontStyle: base.fontStyle, height: 1.0,
                              foreground: paint, fontFamily: base.fontFamily, fontFamilyFallback: base.fontFamilyFallback)
        }
        let fill = Paint()
        fill.style = .fill
        fill.color = base.color ?? Color(0xFF000000)
        let tp = TextPainter(text: TextSpan(text: ch, style: style(fill)), textDirection: .ltr)
        tp.layout(minWidth: 0, maxWidth: Double.infinity)
        return Glyph(painter: tp, text: ch, style: style, look: look)
    }

    /// The lines fitted into `area` and drawn: the shadow first, if any,
    /// then the letters.
    private static func _paint(_ lines: [Line], _ warp: TextWarp, _ area: Rect, _ canvas: any Canvas,
                               pxPerPt px: Double, cache: SlideTextCache?, shadow: Shadow?, fitsPath: Bool = false, fitsInk: Bool = false) {
        /// Set while the shadow is drawn: every letter in it, filled.
        var shadowPaint: Paint? = nil
        /// One glyph through the map of its cell: `origin` its top left,
        /// `x` and `y` where a unit step along and down it lands.
        // Text on a path is filled letter by letter, each with the whole
        // gradient; text fitted to the box shares one across it.
        let fillsEachGlyph = followsPath.contains(warp.preset)
        func draw(_ g: Glyph, origin: Offset, x: Offset, y: Offset) {
            let m = [x.dx, x.dy, 0, 0, y.dx, y.dy, 0, 0, 0, 0, 1, 0, origin.dx, origin.dy, 0, 1]
            let det = x.dx * y.dy - x.dy * y.dx
            guard abs(det) > 1e-9 else { return }
            /// The glyph again with another paint, through the same map.
            func drawn(_ paint: Paint) {
                let tp = TextPainter(text: TextSpan(text: g.text, style: g.style(paint)), textDirection: .ltr)
                tp.layout(minWidth: 0, maxWidth: Double.infinity)
                tp.paint(canvas, .zero)
                tp.dispose()
            }
            canvas.save()
            canvas.transform(m)
            if let shadowPaint {
                // The letters' silhouette, outline and all.
                if !(g.look?.noFill ?? false) { drawn(shadowPaint) }
                if g.look?.outline != nil {
                    let stroke = Paint()
                    stroke.style = .stroke
                    stroke.strokeWidth = max(0.25, (g.look?.outlineWidth ?? 0.75) * px) / max(1e-6, abs(det).squareRoot())
                    stroke.strokeJoin = .round
                    stroke.color = shadowPaint.color
                    drawn(stroke)
                }
                canvas.restore()
                return
            }
            if let fill = g.look?.fill {
                // The fill is the whole area's — one gradient across the
                // word, not one a letter — so its shader is set in the
                // area's space: under the inverse of the glyph's map.
                let inv = [y.dy / det, -x.dy / det, 0, 0, -y.dx / det, x.dx / det, 0, 0, 0, 0, 1, 0,
                           (y.dx * origin.dy - y.dy * origin.dx) / det, (x.dy * origin.dx - x.dx * origin.dy) / det, 0, 1]
                let paint = Paint()
                paint.style = .fill
                paint.color = Color(0xFFFFFFFF)
                if fillsEachGlyph, let shader = SlidePainter.gradientShader(fill, Rect.fromLTWH(0, 0, g.width, g.painter.height)) {
                    paint.shader = shader
                    drawn(paint)
                } else if let shader = SlidePainter.gradientShader(fill, area, pre: inv) {
                    paint.shader = shader
                    drawn(paint)
                } else if let image = fill.image, let decoded = cache?.image(image) {
                    // A picture: tiled at its own size, or stretched over the area.
                    let w = Double(decoded.width), h = Double(decoded.height)
                    let sx = fill.tiled ? 0.75 * fill.tileScale * px : area.width / max(1, w)
                    let sy = fill.tiled ? 0.75 * fill.tileScaleY * px : area.height / max(1, h)
                    // A tile's grid starts where its alignment and offset put one tile.
                    let ox = fill.tiled ? (area.width - w * sx) * fill.tileAlign.dx + fill.tileOffset.dx * px : 0
                    let oy = fill.tiled ? (area.height - h * sy) * fill.tileAlign.dy + fill.tileOffset.dy * px : 0
                    let own = [sx, 0, 0, 0, 0, sy, 0, 0, 0, 0, 1, 0, area.left + ox, area.top + oy, 0, 1]
                    var local = [Double](repeating: 0, count: 16)
                    for c in 0 ..< 4 { for r in 0 ..< 4 { for k in 0 ..< 4 { local[c * 4 + r] += inv[k * 4 + r] * own[c * 4 + k] } } }
                    if let shader = try? ImageShader(decoded, .repeated, .repeated, local, filterQuality: .medium) {
                        paint.shader = shader
                        drawn(paint)
                    } else {
                        g.painter.paint(canvas, .zero)
                    }
                } else {
                    g.painter.paint(canvas, .zero)
                }
            } else if !(g.look?.noFill ?? false) {
                g.painter.paint(canvas, .zero)
            }
            if let o = g.look?.outline {
                let stroke = Paint()
                stroke.style = .stroke
                // The line's width is the page's, not the stretched glyph's.
                stroke.strokeWidth = max(0.25, (g.look?.outlineWidth ?? 0.75) * px) / max(1e-6, abs(det).squareRoot())
                stroke.strokeJoin = .round
                stroke.color = o
                drawn(stroke)
            }
            canvas.restore()
        }

        /// One drawing of every letter, through `draw`.
        func pass() {
            // DrawingML WordArt fits the visible letters into the text
            // rectangle. Advance bearings and a font's line leading are
            // not part of that rectangle (especially CJK parentheses).
            if fitsInk, let envelope = envelope(warp) {
                let width = lines.map(\.width).max() ?? 0
                let height = lines.map(\.height).max() ?? 0
                var placed: [(glyph: Glyph, origin: Offset)] = []
                var ink: Rect?
                for (index, line) in lines.enumerated() {
                    let baseline = line.glyphs.map { $0.painter.computeDistanceToActualBaseline(.alphabetic) }.max() ?? 0
                    let spare = width - line.width
                    var x = line.alignment == .center ? spare / 2 : line.alignment == .right ? spare : 0
                    for glyph in line.glyphs {
                        let origin = Offset(x, Double(index) * height * linePitch + baseline - glyph.painter.computeDistanceToActualBaseline(.alphabetic))
                        placed.append((glyph, origin))
                        if let bounds = glyph.ink?.shift(origin), !bounds.isEmpty {
                            ink = ink.map { $0.expandToInclude(bounds) } ?? bounds
                        }
                        x += glyph.width
                    }
                }
                if let ink, ink.width > 0, ink.height > 0 {
                    func point(_ x: Double, _ y: Double) -> Offset {
                        let u = (x - ink.left) / ink.width, v = (y - ink.top) / ink.height
                        let edge = envelope(u)
                        return Offset(area.left + u * area.width, area.top + (edge.top + (edge.bottom - edge.top) * v) * area.height)
                    }
                    for (glyph, origin) in placed where glyph.width > 0 && glyph.painter.height > 0 {
                        let p00 = point(origin.dx, origin.dy)
                        let p10 = point(origin.dx + glyph.width, origin.dy)
                        let p01 = point(origin.dx, origin.dy + glyph.painter.height)
                        let p11 = point(origin.dx + glyph.width, origin.dy + glyph.painter.height)
                        let x = Offset((p10.dx - p00.dx + p11.dx - p01.dx) / (2 * glyph.width),
                                       (p10.dy - p00.dy + p11.dy - p01.dy) / (2 * glyph.width))
                        let y = Offset((p01.dx - p00.dx + p11.dx - p10.dx) / (2 * glyph.painter.height),
                                       (p01.dy - p00.dy + p11.dy - p10.dy) / (2 * glyph.painter.height))
                        let center = Offset((p00.dx + p10.dx + p01.dx + p11.dx) / 4, (p00.dy + p10.dy + p01.dy + p11.dy) / 4)
                        draw(glyph, origin: Offset(center.dx - x.dx * glyph.width / 2 - y.dx * glyph.painter.height / 2,
                                                  center.dy - x.dy * glyph.width / 2 - y.dy * glyph.painter.height / 2), x: x, y: y)
                    }
                    return
                }
                // A host without the optional ink query keeps the existing
                // advance-box fit instead of losing the shape's text.
            }
            if followsPath.contains(warp.preset) {
                _paintAlongEllipse(lines, warp, area, fits: fitsPath, draw)
                return
            }
            // The bands: one for the whole text, or several — deflate-inflate's
            // first line squeezed above a curve and the rest swelling below it,
            // a ring's two halves. A mirrored band runs right to left, its
            // letters seen from behind; `sides` narrows a band toward its top
            // or bottom.
            typealias Envelope = (Double) -> (top: Double, bottom: Double)
            var bands: [(lines: [Line], env: Envelope, mirrored: Bool, sides: ((Double) -> (Double, Double))?)] = []
            // A pour: the text poured between two arcs of the box's ellipse —
            // across the arc from `start` through `sweep` degrees, from the
            // outer curve in to one at `inner` of its radius (or out, when the
            // letters' feet are on the outside).
            var pour: ((Double, Double) -> Offset)? = nil
            func poured(start: Double, sweep: Double, feetOut: Bool) {
                let inner = (warp.adjust.count > 1 ? warp.adjust[1] : 50000) / 100_000
                pour = { u, v in
                    let a = (start + sweep * u) * .pi / 180
                    let rho = feetOut ? inner + (1 - inner) * v : 1 - (1 - inner) * v
                    return Offset(area.center.dx + area.width / 2 * rho * cos(a), area.center.dy + area.height / 2 * rho * sin(a))
                }
            }
            func bow(_ u: Double) -> Double { (2 * u - 1) * (2 * u - 1) }
            switch warp.preset {
            case "textDeflateInflate":
                let a = (warp.adjust.first ?? 35000) / 100_000
                func mid(_ u: Double) -> Double { 0.5 - (0.5 - a) * (1 - bow(u)) }
                if lines.count == 1 {
                    // One line has the upper band alone.
                    bands = [(lines, { u in (0, mid(u)) }, false, nil)]
                } else {
                    bands = [([lines[0]], { u in (0, mid(u) - 0.03) }, false, nil),
                             (Array(lines[1...]), { u in (mid(u) + 0.03, 1) }, false, nil)]
                }
            case "textDeflateInflateDeflate":
                // Three bands: pinched, swollen, pinched.
                let a = (warp.adjust.first ?? 25000) / 100_000
                func upper(_ u: Double) -> Double { 1.0 / 3 - (1.0 / 3 - a) * (1 - bow(u)) }
                func lower(_ u: Double) -> Double { 1 - upper(u) }
                let third = max(1, lines.count / 3)
                if lines.count < 3 {
                    // Fewer lines than bands: the bands from the top down.
                    bands = [([lines[0]], { u in (0, upper(u) - 0.02) }, false, nil)]
                    if lines.count == 2 { bands.append(([lines[1]], { u in (upper(u) + 0.02, lower(u) - 0.02) }, false, nil)) }
                } else {
                    bands = [(Array(lines[..<third]), { u in (0, upper(u) - 0.02) }, false, nil),
                             (Array(lines[third ..< lines.count - third]), { u in (upper(u) + 0.02, lower(u) - 0.02) }, false, nil),
                             (Array(lines[(lines.count - third)...]), { u in (lower(u) + 0.02, 1) }, false, nil)]
                }
            case "textRingInside", "textRingOutside":
                // The text round a ring seen from the front: its first half
                // across the near side, the second coming back across the far
                // side, mirrored. Inside the ring the near side is the upper
                // arc; outside it, the lower.
                var all = Line()
                all.glyphs = lines.flatMap(\.glyphs)
                let half = (all.glyphs.count + 1) / 2
                var near = Line(), far = Line()
                near.glyphs = Array(all.glyphs[..<half])
                far.glyphs = Array(all.glyphs[half...])
                // A shallow arc and a band a third of the box, as PowerPoint's
                // default (adjust 60%) comes out: the ends of the two halves
                // cross where the ring turns away.
                let adjust = (warp.adjust.first ?? 60000) / 100_000
                let depth = 0.5 * (1 - adjust), t = 0.55 * adjust
                // Nearly level across the middle and turning down sharply at
                // the ends, as the edge of a ring does.
                func dip(_ u: Double) -> Double { depth * 1.5 * (1 - (1 - 0.97 * bow(u)).squareRoot()) }
                let top: Envelope = { u in (dip(u), dip(u) + t) }
                let bottom: Envelope = { u in (1 - dip(u) - t, 1 - dip(u)) }
                let inside = warp.preset == "textRingInside"
                bands = [([near], inside ? top : bottom, false, nil)]
                if !far.glyphs.isEmpty { bands.append(([far], inside ? bottom : top, true, nil)) }
            case "textArchUpPour", "textButtonPour":
                poured(start: 180, sweep: 180, feetOut: false)
                bands = [(lines, { _ in (0, 1) }, false, nil)]
            case "textArchDownPour":
                poured(start: 180, sweep: -180, feetOut: true)
                bands = [(lines, { _ in (0, 1) }, false, nil)]
            case "textCirclePour":
                poured(start: 180, sweep: 360, feetOut: false)
                bands = [(lines, { _ in (0, 1) }, false, nil)]
            default:
                if let env = envelope(warp) {
                    var sides: ((Double) -> (Double, Double))? = nil
                    let a = (warp.adjust.first ?? 33333) / 100_000
                    if warp.preset == "textFadeUp" { sides = { v in (a * (1 - v), 1 - a * (1 - v)) } }
                    if warp.preset == "textFadeDown" { sides = { v in (a * v, 1 - a * v) } }
                    bands = [(lines, env, false, sides)]
                }
            }
            // textPlain's adjust slants the block: its top and bottom edges slide
            // apart by twice the adjust's distance from the middle, and the
            // text is that much narrower.
            // A wave's second adjust does the same (its `dx`, ±10%): the top
            // edge slides right of the bottom one by twice it when negative
            // (FontWorkScaleX's −5661, its lines leaning right in PowerPoint's
            // print), left when positive.
            let waves: Set<String> = ["textWave1", "textWave2", "textDoubleWave1", "textWave4"]
            let slant = warp.preset == "textPlain" ? 2 * ((warp.adjust.first ?? 50000) / 100_000 - 0.5)
                : waves.contains(warp.preset) && warp.adjust.count >= 2 ? 2 * max(-0.1, min(0.1, warp.adjust[1] / 100_000)) : 0
            // Fitted to the letters there are: with nothing hanging below the
            // line, the line itself is the foot of the band.
            let descends = lines.contains { $0.glyphs.contains { "gjpqyQ,;".containsSubstring($0.text) } }
            // Every line at the widest one's scale, whichever band it is in —
            // but a ring's two halves each go the whole way across.
            let ring = warp.preset.hasPrefix("textRing")
            let widestOfAll = max(1e-6, bands.flatMap(\.lines).map(\.width).max() ?? 1)
            for band in bands {
                let n = Double(band.lines.count)
                let widest = ring ? max(1e-6, band.lines.map(\.width).max() ?? 1) : widestOfAll
                func point(_ u: Double, _ v: Double) -> Offset {
                    if let pour { return pour(u, v) }
                    let u = band.mirrored ? 1 - u : u
                    let e = band.env(u)
                    let shift = slant >= 0 ? slant * v : -slant * (1 - v)
                    var x = u * (1 - abs(slant)) + shift
                    if let sides = band.sides { let (l, r) = sides(max(0, min(1, v))); x = l + (r - l) * u }
                    return Offset(area.left + x * area.width, area.top + (e.top + (e.bottom - e.top) * v) * area.height)
                }
                for (li, line) in band.lines.enumerated() {
                    let total = widest
                    let spare = widest - line.width
                    var x = line.alignment == .center ? spare / 2 : line.alignment == .right ? spare : 0
                    // A line's share of the band is its letters', capital top
                    // to descender, not its whole box: what is above the
                    // capitals goes outside.
                    // Lines stand a line's pitch apart (`pitch`, in heights of
                    // a line's box), the gaps between them kept: the band is
                    // the first line's capitals to the last one's foot, all of
                    // it scaled to fit (ImportWordArtGradient's two lines,
                    // 27 pt apart in PowerPoint's print, where squeezed
                    // together they ran into each other).
                    // (Fitted over the corpus's WordArt, 2026-10-22: the box is
                    // one em, so the capitals' top sits only a few hundredths
                    // in, and a descender hangs past its foot — Archivo Black's
                    // "y" 0.017 em. At 0.13 and 0.03 the letters stood past
                    // WordArtBitmapFill's frame top and foot; 20 decks 75.6 →
                    // 70.1 in sum, ImportWordArtGradient's two lines 0.9 worse.)
                    let above = 0.04, below = descends ? -0.02 : 0.15
                    let pitch = Self.linePitch
                    let span = (n - 1) * pitch + 1 - above - below
                    let v0 = (Double(li) * pitch - above) / span, v1 = (Double(li) * pitch + 1 - above) / span
                    for g in line.glyphs {
                        let u0 = x / total, u1 = (x + g.width) / total
                        x += g.width
                        guard g.width > 0, g.painter.height > 0 else { continue }
                        let p00 = point(u0, v0), p10 = point(u1, v0), p01 = point(u0, v1), p11 = point(u1, v1)
                        let ax = Offset((p10.dx - p00.dx + p11.dx - p01.dx) / 2 / g.width, (p10.dy - p00.dy + p11.dy - p01.dy) / 2 / g.width)
                        let ay = Offset((p01.dx - p00.dx + p11.dx - p10.dx) / 2 / g.painter.height,
                                        (p01.dy - p00.dy + p11.dy - p10.dy) / 2 / g.painter.height)
                        let c = Offset((p00.dx + p10.dx + p01.dx + p11.dx) / 4, (p00.dy + p10.dy + p01.dy + p11.dy) / 4)
                        let o = Offset(c.dx - ax.dx * g.width / 2 - ay.dx * g.painter.height / 2,
                                       c.dy - ax.dy * g.width / 2 - ay.dy * g.painter.height / 2)
                        draw(g, origin: o, x: ax, y: ay)
                    }
                }
            }
        }

        if let shadow {
            let p = Paint()
            p.style = .fill
            p.color = shadow.color
            shadowPaint = p
            let o = Offset(area.center.dx + shadow.origin.dx * area.width, area.center.dy + shadow.origin.dy * area.height)
            let k = shadow.matrix
            canvas.save()
            canvas.translate(shadow.offset.dx * px, shadow.offset.dy * px)
            canvas.transform([k.sxx, k.syx, 0, 0, k.sxy, k.syy, 0, 0, 0, 0, 1, 0,
                              o.dx - k.sxx * o.dx - k.sxy * o.dy, o.dy - k.syx * o.dx - k.syy * o.dy, 0, 1])
            pass()
            canvas.restore()
            shadowPaint = nil
        }
        pass()
    }

    /// Arch, circle and button: each line at its own size along the
    /// area's ellipse, its baseline on the curve — shrunk only when it is
    /// longer than its stretch of it.
    private static func _paintAlongEllipse(_ lines: [Line], _ warp: TextWarp, _ area: Rect, fits: Bool = false,
                                           _ draw: (Glyph, Offset, Offset, Offset) -> Void) {
        let rx = area.width / 2, ry = area.height / 2, c = area.center
        /// A line along the arc from `start`, sweeping `sweep` degrees
        /// (clockwise positive, as DrawingML measures).
        func along(_ line: Line, start: Double, sweep: Double) {
            let steps = 720
            var pts: [Offset] = [], lens: [Double] = [0]
            for i in 0 ... steps {
                let a = (start + sweep * Double(i) / Double(steps)) * .pi / 180
                pts.append(Offset(c.dx + rx * cos(a), c.dy + ry * sin(a)))
                if i > 0 { lens.append(lens[i - 1] + hypot(pts[i].dx - pts[i - 1].dx, pts[i].dy - pts[i - 1].dy)) }
            }
            let arc = lens[steps]
            guard arc > 0, line.width > 0 else { return }
            // (Fitted to its path — VML's `fitshape`/`fitpath`, Word's
            // WordArt — the line runs the arc's whole length, grown or
            // shrunk: F13's 30pt "Arch Up: Open software" spans its
            // 450 x 88 box's upper half in Word's print, about 52pt.)
            let k = fits ? arc / line.width : min(1, arc / line.width)
            let used = line.width * k
            var s = line.alignment == .center ? (arc - used) / 2 : line.alignment == .right ? arc - used : 0
            func at(_ d: Double) -> (Offset, Offset) {
                let d = max(0, min(arc, d))
                var i = lens.firstIndex { $0 >= d } ?? steps
                i = max(1, i)
                let t = (d - lens[i - 1]) / max(1e-9, lens[i] - lens[i - 1])
                let p = Offset(pts[i - 1].dx + (pts[i].dx - pts[i - 1].dx) * t, pts[i - 1].dy + (pts[i].dy - pts[i - 1].dy) * t)
                let len = max(1e-9, hypot(pts[i].dx - pts[i - 1].dx, pts[i].dy - pts[i - 1].dy))
                return (p, Offset((pts[i].dx - pts[i - 1].dx) / len, (pts[i].dy - pts[i - 1].dy) / len))
            }
            for g in line.glyphs {
                let w = g.width * k
                let (p, t) = at(s + w / 2)
                s += w
                guard g.width > 0 else { continue }
                let base = g.painter.computeDistanceToActualBaseline(.alphabetic) * k
                // Along the tangent, and down its right-hand normal.
                let ax = Offset(t.dx * k, t.dy * k), ay = Offset(-t.dy * k, t.dx * k)
                let o = Offset(p.dx - t.dx * w / 2 + t.dy * base, p.dy - t.dy * w / 2 - t.dx * base)
                draw(g, o, ax, ay)
            }
        }
        func angle(_ d: Double) -> Double { (warp.adjust.first ?? d) / 60000 }
        switch warp.preset {
        case "textArchUp":
            let a = angle(10_800_000)
            var sweep = (540 - a).truncatingRemainder(dividingBy: 360) - a
            while sweep <= 0 { sweep += 360 }
            for l in lines { along(l, start: a, sweep: sweep) }
        case "textArchDown":
            let a = angle(0)
            let start = 180 - a
            var sweep = start - a
            while sweep <= 0 { sweep += 360 }
            for l in lines { along(l, start: start, sweep: -sweep) }
        case "textCircle":
            let a = angle(10_800_000)
            for l in lines { along(l, start: a, sweep: 360) }
        default:   // textButton: over the top, straight across, under the bottom
            let a = angle(10_800_000)
            var sweep = (540 - a).truncatingRemainder(dividingBy: 360) - a
            while sweep <= 0 { sweep += 360 }
            for (i, l) in lines.enumerated() {
                if i == 0 { along(l, start: a, sweep: sweep) }
                else if i == lines.count - 1 { along(l, start: a, sweep: -(360 - sweep)) }
                else {
                    var x = c.dx - l.width / 2
                    for g in l.glyphs {
                        draw(g, Offset(x, c.dy - g.painter.height / 2), Offset(1, 0), Offset(0, 1))
                        x += g.width
                    }
                }
            }
        }
    }
}
