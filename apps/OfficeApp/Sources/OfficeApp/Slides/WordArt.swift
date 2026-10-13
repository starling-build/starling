// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
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
        case "textSlantDown": let a = adj(44444); return { (a * $0, 1 - a * (1 - $0)) }
        default: return nil
        }
    }

    /// The presets whose text follows the area's ellipse.
    static let followsPath: Set<String> = ["textArchUp", "textArchDown", "textCircle", "textButton"]

    static func draws(_ warp: TextWarp) -> Bool { followsPath.contains(warp.preset) || envelope(warp) != nil || warp.preset == "textDeflateInflate" }

    private struct Glyph {
        /// The glyph in its plain colour: what is measured, and what is
        /// drawn when the run has no fill of its own.
        let painter: TextPainter
        let text: String
        let style: (Paint) -> Flutter.TextStyle
        let look: RunLook?
        var width: Double { painter.width }
    }

    private struct Line {
        var glyphs: [Glyph] = []
        var alignment: ParagraphAlignment = .left
        var width: Double { glyphs.reduce(0) { $0 + $1.width } }
        var height: Double { glyphs.map { $0.painter.height }.max() ?? 0 }
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
            let looks = keepLooks && shape.runLooks[pi].count == p.runs.count ? shape.runLooks[pi] : []
            let units = Array(p.text.utf16)
            var at = 0
            for (ri, run) in p.runs.enumerated() {
                let text = String(decoding: units[at ..< min(units.count, at + run.length)], as: UTF16.self)
                at += run.length
                let base = theme.textStyle(for: run.style, in: p.style, scale: scale)
                let look = ri < looks.count ? looks[ri] : nil
                let color = base.color ?? Color(0xFF000000)
                func style(_ paint: Paint) -> Flutter.TextStyle {
                    Flutter.TextStyle(fontSize: base.fontSize, fontWeight: base.fontWeight, fontStyle: base.fontStyle, height: 1.0,
                              foreground: paint, fontFamily: base.fontFamily, fontFamilyFallback: base.fontFamilyFallback)
                }
                let fill = Paint()
                fill.style = .fill
                fill.color = color
                for ch in text where ch != "\n" {
                    let tp = TextPainter(text: TextSpan(text: String(ch), style: style(fill)), textDirection: .ltr)
                    tp.layout(minWidth: 0, maxWidth: Double.infinity)
                    line.glyphs.append(Glyph(painter: tp, text: String(ch), style: style, look: look))
                }
            }
            if !line.glyphs.isEmpty { lines.append(line) }
        }
        defer { for l in lines { for g in l.glyphs { g.painter.dispose() } } }
        guard !lines.isEmpty else { return true }

        /// One glyph through the map of its cell: `origin` its top left,
        /// `x` and `y` where a unit step along and down it lands.
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
            if let fill = g.look?.fill {
                // The fill is the whole area's — one gradient across the
                // word, not one a letter — so its shader is set in the
                // area's space: under the inverse of the glyph's map.
                let inv = [y.dy / det, -x.dy / det, 0, 0, -y.dx / det, x.dx / det, 0, 0, 0, 0, 1, 0,
                           (y.dx * origin.dy - y.dy * origin.dx) / det, (x.dy * origin.dx - x.dx * origin.dy) / det, 0, 1]
                let paint = Paint()
                paint.style = .fill
                paint.color = Color(0xFFFFFFFF)
                if let shader = SlidePainter.gradientShader(fill, area, pre: inv) {
                    paint.shader = shader
                    drawn(paint)
                } else if let image = fill.image, let decoded = cache.image(image) {
                    // A picture: tiled at its own size, or stretched over the area.
                    let w = Double(decoded.width), h = Double(decoded.height)
                    let sx = fill.tiled ? 0.75 * fill.tileScale * px : area.width / max(1, w)
                    let sy = fill.tiled ? 0.75 * fill.tileScale * px : area.height / max(1, h)
                    let own = [sx, 0, 0, 0, 0, sy, 0, 0, 0, 0, 1, 0, area.left, area.top, 0, 1]
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

        if followsPath.contains(warp.preset) {
            _paintAlongEllipse(lines, warp, area, draw)
            return true
        }
        // The bands: one for the whole text, or — deflate-inflate — the
        // first line squeezed above a curve and the rest swelling below it.
        var bands: [(lines: [Line], env: (Double) -> (top: Double, bottom: Double))] = []
        if warp.preset == "textDeflateInflate" {
            let a = (warp.adjust.first ?? 35000) / 100_000
            func mid(_ u: Double) -> Double { 0.5 - (0.5 - a) * (1 - (2 * u - 1) * (2 * u - 1)) }
            if lines.count == 1 {
                bands = [(lines, { u in (0.5 - mid(u) + 0, 1) })]
            } else {
                bands = [([lines[0]], { u in (0, mid(u) - 0.03) }), (Array(lines[1...]), { u in (mid(u) + 0.03, 1) })]
            }
        } else if let env = envelope(warp) {
            bands = [(lines, env)]
        }
        // textPlain's adjust slants the block: its top and bottom edges slide
        // apart by twice the adjust's distance from the middle, and the
        // text is that much narrower.
        let slant = warp.preset == "textPlain" ? 2 * ((warp.adjust.first ?? 50000) / 100_000 - 0.5) : 0
        // Every line at the widest one's scale: a shorter line is shorter,
        // and sits where its paragraph is aligned.
        let widest = max(1e-6, lines.map(\.width).max() ?? 1)
        for band in bands {
            let n = Double(band.lines.count)
            func point(_ u: Double, _ v: Double) -> Offset {
                let e = band.env(u)
                let shift = slant >= 0 ? slant * v : -slant * (1 - v)
                return Offset(area.left + (u * (1 - abs(slant)) + shift) * area.width,
                              area.top + (e.top + (e.bottom - e.top) * v) * area.height)
            }
            for (li, line) in band.lines.enumerated() {
                let total = widest
                let spare = widest - line.width
                var x = line.alignment == .center ? spare / 2 : line.alignment == .right ? spare : 0
                // A line's share of the band is its letters', capital top
                // to descender, not its whole box: the box has an eighth
                // of nothing above the capitals, which goes outside.
                let above = 0.13, below = 0.03
                let share = 1 / n / (1 - above - below)
                let v0 = Double(li) / n - above * share, v1 = Double(li + 1) / n + below * share
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
        return true
    }

    /// Arch, circle and button: each line at its own size along the
    /// area's ellipse, its baseline on the curve — shrunk only when it is
    /// longer than its stretch of it.
    private static func _paintAlongEllipse(_ lines: [Line], _ warp: TextWarp, _ area: Rect,
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
            let k = min(1, arc / line.width)
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
