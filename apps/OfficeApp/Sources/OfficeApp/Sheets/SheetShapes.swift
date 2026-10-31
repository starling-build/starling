// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Shapes and text boxes on a sheet (`xdr:sp`): the preset shapes
// (rectangles, rounded ones, ellipses, triangles, arrows, lines and
// connectors here; the rest through Slides' `geometryPath`), their fill —
// solid or a linear gradient — and outline, set on the shape or taken from
// its style's theme references, arrowheads, rotation, groups (`xdr:grpSp`,
// nested, each child placed by the group's child coordinate space) and
// their text, paragraph by paragraph. The shape's XML is kept, so it is
// written back as it was; these are drawn from it, and can be selected,
// moved, resized and deleted.

import Flutter
import OfficeText
import FlutterSwiftBridge
import Foundation

struct ShapeRun: Equatable {
    var text: String
    var size: Double          // points
    var bold = false, italic = false, underline = false
    var color: Color? = nil
}

struct ShapeParagraph: Equatable {
    var align = "l"           // l, ctr, r, just
    var runs: [ShapeRun] = []
    /// An equation the paragraph holds (`a14:m`'s `m:oMathPara` or
    /// `m:oMath`, in mc:Choice), drawn through WriterMath, and its size.
    var math: ShapeMath? = nil
}

/// An equation in a shape's paragraph: the same node is the same one.
struct ShapeMath: Equatable {
    let node: XNode
    var size = 11.0
    static func == (a: ShapeMath, b: ShapeMath) -> Bool { a.node === b.node && a.size == b.size }
}

struct SheetShape: Equatable {
    var geometry: String      // prstGeom@prst
    var fill: Color?
    var line: Color?
    var lineWidth: Double     // points
    var paragraphs: [ShapeParagraph] = []
    var anchor = "t"          // bodyPr@anchor: t, ctr, b
    var insets = (left: 7.2, top: 3.6, right: 7.2, bottom: 3.6)
    var textColor: Color? = nil
    var flipH = false, flipV = false
    /// `xfrm@rot`, in degrees clockwise.
    var rotation = 0.0
    /// A linear gradient fill: its stops (position 0…1) and angle in
    /// degrees, `fill` being the first stop.
    var gradient: (stops: [(position: Double, color: Color)], angle: Double)? = nil
    /// Arrowheads: `ln/headEnd` sits at the line's start, `tailEnd` at its end.
    var headArrow = false, tailArrow = false
    /// A group's members, each in its frame as a fraction of the group's.
    var children: [GroupChild] = []

    struct GroupChild: Equatable {
        var frame: Rect
        var shape: SheetShape
    }

    var isGroup: Bool { geometry == "group" }

    static func == (a: SheetShape, b: SheetShape) -> Bool {
        a.geometry == b.geometry && a.fill == b.fill && a.line == b.line && a.lineWidth == b.lineWidth
            && a.paragraphs == b.paragraphs && a.anchor == b.anchor && a.textColor == b.textColor
            && a.rotation == b.rotation && a.children == b.children && a.headArrow == b.headArrow && a.tailArrow == b.tailArrow
    }

    /// A group (`grpSp`): its members placed by its child coordinate space
    /// (`grpSpPr/xfrm`'s chOff/chExt), the group itself drawn as nothing.
    static func readGroup(_ grp: XNode, colors: ColorContext) -> SheetShape {
        var g = SheetShape(geometry: "group", fill: nil, line: nil, lineWidth: 0)
        let xfrm = grp.child("grpSpPr")?.child("xfrm")
        g.rotation = (xfrm?["rot"].flatMap(Double.init) ?? 0) / 60000
        g.flipH = xfrm?["flipH"] == "1"; g.flipV = xfrm?["flipV"] == "1"
        func emu(_ n: XNode?, _ k: String) -> Double { n?[k].flatMap(Double.init) ?? 0 }
        let chOff = xfrm?.child("chOff"), chExt = xfrm?.child("chExt")
        let ox = emu(chOff, "x"), oy = emu(chOff, "y")
        let cw = max(1, emu(chExt, "cx")), ch = max(1, emu(chExt, "cy"))
        for el in grp.children {
            let local = el.name.split(separator: ":").last.map(String.init) ?? ""
            let child: SheetShape
            let childXfrm: XNode?
            switch local {
            case "sp", "cxnSp":
                child = read(el, colors: colors)
                childXfrm = el.child("spPr")?.child("xfrm")
            case "grpSp":
                child = readGroup(el, colors: colors)
                childXfrm = el.child("grpSpPr")?.child("xfrm")
            default:
                continue   // pictures and graphic frames inside groups: not drawn yet
            }
            guard let x = childXfrm, let off = x.child("off"), let ext = x.child("ext") else { continue }
            let frame = Rect.fromLTWH((emu(off, "x") - ox) / cw, (emu(off, "y") - oy) / ch, emu(ext, "cx") / cw, emu(ext, "cy") / ch)
            g.children.append(GroupChild(frame: frame, shape: child))
        }
        return g
    }

    /// The shape in `sp` (or a connector, `cxnSp`).
    static func read(_ sp: XNode, colors: ColorContext) -> SheetShape {
        let pr = sp.child("spPr")
        let style = sp.child("style")
        func color(_ n: XNode?) -> Color? { n.flatMap { colors.color(in: $0) } }
        var s = SheetShape(geometry: pr?.child("prstGeom")?["prst"] ?? (sp.name.hasSuffix("cxnSp") ? "line" : "rect"),
                           fill: nil, line: nil, lineWidth: 0.75)
        func gradient(_ g: XNode, _ colors: ColorContext) {
            let stops = (g.child("gsLst")?.kids("gs") ?? []).compactMap { gs -> (position: Double, color: Color)? in
                guard let c = colors.color(in: gs) else { return nil }
                return ((gs["pos"].flatMap(Double.init) ?? 0) / 100_000, c)
            }.sorted { $0.position < $1.position }
            s.fill = stops.first?.color
            if stops.count > 1 { s.gradient = (stops, (g.child("lin")?["ang"].flatMap(Double.init) ?? 5_400_000) / 60000) }
        }
        // Fill: the shape's own, else its style's.
        if pr?.child("noFill") != nil { s.fill = nil }
        else if let f = pr?.child("solidFill") { s.fill = color(f) }
        else if let g = pr?.child("gradFill") { gradient(g, colors) }
        else if let ref = style?.child("fillRef") {
            s.fill = color(ref)
            // Through the theme's fill style it names, when that is a
            // gradient of the referred colour (LIBRE_OFFICE-128382-0's
            // pale green note, drawn in full accent6).
            if let idx = ref["idx"].flatMap(Int.init), colors.theme.fillStyles.indices.contains(idx - 1),
               colors.theme.fillStyles[idx - 1].name.hasSuffix("gradFill") {
                var c = colors
                c.placeholder = s.fill
                gradient(colors.theme.fillStyles[idx - 1], c)
            }
        }
        // Line: likewise.
        let ln = pr?.child("ln")
        if let w = ln?["w"].flatMap(Double.init) { s.lineWidth = w / 12700 }
        if ln?.child("noFill") != nil { s.line = nil }
        else if let f = ln?.child("solidFill") { s.line = color(f) }
        else { s.line = color(style?.child("lnRef")) }
        let arrow: (XNode?) -> Bool = { ($0?["type"] ?? "none") != "none" }
        s.headArrow = arrow(ln?.child("headEnd")); s.tailArrow = arrow(ln?.child("tailEnd"))
        s.textColor = color(style?.child("fontRef"))
        if let x = pr?.child("xfrm") {
            s.flipH = x["flipH"] == "1"; s.flipV = x["flipV"] == "1"
            s.rotation = (x["rot"].flatMap(Double.init) ?? 0) / 60000
        }
        // Text.
        if let body = sp.child("txBody") {
            if let b = body.child("bodyPr") {
                s.anchor = b["anchor"] ?? "t"
                func emu(_ k: String, _ d: Double) -> Double { b[k].flatMap(Double.init).map { $0 / 12700 } ?? d }
                s.insets = (emu("lIns", 7.2), emu("tIns", 3.6), emu("rIns", 7.2), emu("bIns", 3.6))
            }
            for p in body.kids("p") {
                var para = ShapeParagraph(align: p.child("pPr")?["algn"] ?? "l")
                let defaults = p.child("pPr")?.child("defRPr")
                for r in p.children {
                    let local = r.name.split(separator: ":").last ?? ""
                    if local == "br" { para.runs.append(ShapeRun(text: "\n", size: 11)); continue }
                    // (An equation, in mc:Choice: LIBRE_OFFICE-128382-0's
                    // e^x = 1 + x/1! + …, which printed as nothing.)
                    if local == "AlternateContent", let m = r.child("Choice")?.child("m"),
                       let eq = m.child("oMathPara") ?? m.child("oMath") {
                        let sz = eq.descendant("a:rPr")?["sz"].flatMap(Double.init).map { $0 / 100 } ?? 11
                        para.math = ShapeMath(node: eq, size: sz)
                        if eq.name.hasSuffix("oMathPara"), eq.child("oMathParaPr")?.child("jc")?["m:val"]?.hasPrefix("center") == true {
                            para.align = "ctr"
                        }
                        continue
                    }
                    guard local == "r" || local == "fld", let t = r.child("t") else { continue }
                    let rp = r.child("rPr")
                    func attr(_ k: String) -> String? { rp?[k] ?? defaults?[k] }
                    var run = ShapeRun(text: t.text, size: attr("sz").flatMap(Double.init).map { $0 / 100 } ?? 11)
                    run.bold = attr("b") == "1"; run.italic = attr("i") == "1"
                    run.underline = (attr("u") ?? "none") != "none"
                    run.color = color(rp?.child("solidFill") ?? defaults?.child("solidFill"))
                    para.runs.append(run)
                }
                s.paragraphs.append(para)
            }
        }
        return s
    }

    static let lineGeometries: Set<String> = ["line", "straightConnector1", "bentConnector3", "curvedConnector3"]

    /// Where the shape lies before it is turned, given the rectangle its
    /// cell anchor spans. Turned nearer the vertical than the horizontal
    /// (45° to 135°, 225° to 315°), Excel anchors the cells its turned
    /// outline covers — the same centre, width and height changed over.
    func unturned(_ r: Rect) -> Rect {
        let turn = (rotation.truncatingRemainder(dividingBy: 180) + 180).truncatingRemainder(dividingBy: 180)
        guard turn >= 45, turn < 135 else { return r }
        return Rect.fromCenter(center: r.center, width: r.height, height: r.width)
    }

    /// Draw it into `r` at `k` pixels per point.
    func paint(_ canvas: any Canvas, in r: Rect, pxPerPt k: Double, font: String) {
        canvas.save()
        defer { canvas.restore() }
        if rotation != 0 {
            let c = r.center
            canvas.translate(c.dx, c.dy)
            canvas.rotate(rotation * .pi / 180)
            canvas.translate(-c.dx, -c.dy)
        }
        if isGroup {
            for child in children {
                let f = child.frame
                let cr = Rect.fromLTWH(r.left + f.left * r.width, r.top + f.top * r.height, f.width * r.width, f.height * r.height)
                guard cr.width > 0.5 || cr.height > 0.5 else { continue }
                child.shape.paint(canvas, in: cr, pxPerPt: k, font: font)
            }
            return
        }
        let path = _path(r)
        let p = Paint()
        p.isAntiAlias = true
        let isLine = Self.lineGeometries.contains(geometry)
        if let fill, !isLine {
            p.style = .fill
            p.color = fill
            if let gradient {
                // The angle runs clockwise from "left to right", across the
                // frame's whole extent as DrawingML's `lin` does.
                let a = gradient.angle * .pi / 180
                let c = r.center
                let half = (abs(cos(a)) * r.width + abs(sin(a)) * r.height) / 2
                let d = Offset(cos(a) * half, sin(a) * half)
                p.shader = Gradient(linear: Offset(c.dx - d.dx, c.dy - d.dy), to: Offset(c.dx + d.dx, c.dy + d.dy),
                                    colors: gradient.stops.map(\.color), colorStops: gradient.stops.map(\.position))
            }
            canvas.drawPath(path, p)
            p.shader = nil
        }
        if let line {
            p.style = .stroke
            p.strokeWidth = max(1, lineWidth * k)
            p.color = line
            canvas.drawPath(path, p)
            if isLine && (headArrow || tailArrow) {
                let (x0, x1) = flipH ? (r.right, r.left) : (r.left, r.right)
                let (y0, y1) = flipV ? (r.bottom, r.top) : (r.top, r.bottom)
                p.style = .fill
                if headArrow { _arrowhead(canvas, at: Offset(x0, y0), from: Offset(x1, y1), width: p.strokeWidth, paint: p) }
                if tailArrow { _arrowhead(canvas, at: Offset(x1, y1), from: Offset(x0, y0), width: p.strokeWidth, paint: p) }
            }
        }
        guard paragraphs.contains(where: { !$0.runs.isEmpty || $0.math != nil }) else { return }
        let box = Rect.fromLTRB(r.left + insets.left * k, r.top + insets.top * k, r.right - insets.right * k, r.bottom - insets.bottom * k)
        guard box.width > 2 else { return }
        var painters: [TextPainter] = []
        // An equation's box in place of its paragraph's text, by index.
        var equations: [Int: WriterMath.Box] = [:]
        for (i, para) in paragraphs.enumerated() {
            if para.runs.isEmpty, let m = para.math, let eq = WriterMath.box(m.node, size: m.size) { equations[i] = eq }
            let spans = (para.runs.isEmpty ? [ShapeRun(text: " ", size: 11)] : para.runs).map { run -> InlineSpan in
                TextSpan(text: run.text, style: Flutter.TextStyle(
                    color: run.color ?? textColor ?? Color(0xFF000000), fontSize: max(3, run.size * k),
                    fontWeight: run.bold ? .bold : .normal, fontStyle: run.italic ? .italic : .normal,
                    decoration: run.underline ? .underline : nil, fontFamily: font))
            }
            let align: TextAlign = para.align == "ctr" ? .center : para.align == "r" ? .right : para.align == "just" ? .justify : .left
            let tp = TextPainter(text: TextSpan(children: spans), textAlign: align, textDirection: .ltr)
            tp.layout(minWidth: box.width, maxWidth: box.width)
            painters.append(tp)
        }
        func tall(_ i: Int) -> Double { equations[i].map { ($0.ascent + $0.descent) * k } ?? painters[i].height }
        let height = painters.indices.reduce(0) { $0 + tall($1) }
        var y = anchor == "ctr" ? box.center.dy - height / 2 : anchor == "b" ? box.bottom - height : box.top
        canvas.save()
        canvas.clipRect(r)
        for (i, tp) in painters.enumerated() {
            if let eq = equations[i] {
                let w = eq.width * k
                let x = paragraphs[i].align == "ctr" ? box.center.dx - w / 2 : paragraphs[i].align == "r" ? box.right - w : box.left
                canvas.save()
                canvas.translate(x, y)
                canvas.scale(k, k)
                eq.draw(canvas, Offset(0, eq.ascent))
                canvas.restore()
            } else {
                tp.paint(canvas, Offset(box.left, y))
            }
            y += tall(i)
            tp.dispose()
        }
        canvas.restore()
    }

    private func _path(_ r: Rect) -> Path {
        let path = Path()
        let l = r.left, t = r.top, rr = r.right, b = r.bottom, w = r.width, h = r.height, cx = r.center.dx, cy = r.center.dy
        switch geometry {
        case "ellipse", "flowChartConnector":
            path.addOval(r)
        case "roundRect", "flowChartAlternateProcess":
            let rad = min(w, h) * 0.1667
            path.addRRect(RRect(fromRectAndRadius: r, Radius(circular: rad)))
        case "triangle":
            path.moveTo(cx, t); path.lineTo(rr, b); path.lineTo(l, b); path.close()
        case "rtTriangle":
            path.moveTo(l, t); path.lineTo(rr, b); path.lineTo(l, b); path.close()
        case "diamond", "flowChartDecision":
            path.moveTo(cx, t); path.lineTo(rr, cy); path.lineTo(cx, b); path.lineTo(l, cy); path.close()
        case "rightArrow", "leftArrow", "upArrow", "downArrow":
            // A block arrow, drawn pointing right in its own frame and turned.
            let horizontal = geometry == "rightArrow" || geometry == "leftArrow"
            let len = horizontal ? w : h, thick = horizontal ? h : w
            let head = min(len * 0.5, thick * 0.5)
            var pts: [(Double, Double)] = [(0, thick * 0.25), (len - head, thick * 0.25), (len - head, 0), (len, thick / 2),
                                           (len - head, thick), (len - head, thick * 0.75), (0, thick * 0.75)]
            pts = pts.map { (x, y) in
                switch geometry {
                case "leftArrow": return (l + (len - x), t + y)
                case "upArrow": return (l + y, t + (len - x))
                case "downArrow": return (l + y, t + x)
                default: return (l + x, t + y)
                }
            }
            for (i, (x, y)) in pts.enumerated() { if i == 0 { path.moveTo(x, y) } else { path.lineTo(x, y) } }
            path.close()
        case "line", "straightConnector1", "bentConnector3", "curvedConnector3":
            let (x0, x1) = flipH ? (rr, l) : (l, rr)
            let (y0, y1) = flipV ? (b, t) : (t, b)
            path.moveTo(x0, y0); path.lineTo(x1, y1)
        default:
            // The presets Slides draws (hexagon, chevron, braces, stars, callouts…),
            // a rectangle for the rest.
            return SlidePainter.geometryPath(ShapePreset(rawValue: geometry), r)
        }
        return path
    }

    /// A filled triangle at `tip`, pointing away from `from`, sized by the line.
    private func _arrowhead(_ canvas: any Canvas, at tip: Offset, from: Offset, width: Double, paint: Paint) {
        let dx = tip.dx - from.dx, dy = tip.dy - from.dy
        let len = (dx * dx + dy * dy).squareRoot()
        guard len > 0.01 else { return }
        let ux = dx / len, uy = dy / len
        let size = max(6, width * 3)
        let bx = tip.dx - ux * size, by = tip.dy - uy * size
        let hw = size * 0.4
        let path = Path()
        path.moveTo(tip.dx, tip.dy)
        path.lineTo(bx - uy * hw, by + ux * hw)
        path.lineTo(bx + uy * hw, by - ux * hw)
        path.close()
        canvas.drawPath(path, paint)
    }
}
