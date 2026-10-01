// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Shapes and text boxes on a sheet (`xdr:sp`): the common preset shapes
// (rectangles, rounded ones, ellipses, triangles, arrows, lines and
// connectors), their fill and outline — set on the shape or taken from its
// style's theme references — and their text, paragraph by paragraph. The
// shape's XML is kept, so it is written back as it was; these are drawn
// from it, and can be selected, moved, resized and deleted.

import Flutter
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

    static func == (a: SheetShape, b: SheetShape) -> Bool {
        a.geometry == b.geometry && a.fill == b.fill && a.line == b.line && a.lineWidth == b.lineWidth
            && a.paragraphs == b.paragraphs && a.anchor == b.anchor && a.textColor == b.textColor
    }

    /// The shape in `sp` (or a connector, `cxnSp`).
    static func read(_ sp: XNode, colors: ColorContext) -> SheetShape {
        let pr = sp.child("spPr")
        let style = sp.child("style")
        func color(_ n: XNode?) -> Color? { n.flatMap { colors.color(in: $0) } }
        var s = SheetShape(geometry: pr?.child("prstGeom")?["prst"] ?? (sp.name.hasSuffix("cxnSp") ? "line" : "rect"),
                           fill: nil, line: nil, lineWidth: 0.75)
        // Fill: the shape's own, else its style's.
        if pr?.child("noFill") != nil { s.fill = nil }
        else if let f = pr?.child("solidFill") { s.fill = color(f) }
        else if pr?.child("gradFill") != nil { s.fill = pr?.child("gradFill")?.child("gsLst")?.kids("gs").first.flatMap(color) }
        else { s.fill = color(style?.child("fillRef")) }
        // Line: likewise.
        let ln = pr?.child("ln")
        if let w = ln?["w"].flatMap(Double.init) { s.lineWidth = w / 12700 }
        if ln?.child("noFill") != nil { s.line = nil }
        else if let f = ln?.child("solidFill") { s.line = color(f) }
        else { s.line = color(style?.child("lnRef")) }
        s.textColor = color(style?.child("fontRef"))
        if let x = pr?.child("xfrm") { s.flipH = x["flipH"] == "1"; s.flipV = x["flipV"] == "1" }
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

    /// Draw it into `r` at `k` pixels per point.
    func paint(_ canvas: any Canvas, in r: Rect, pxPerPt k: Double, font: String) {
        let path = _path(r)
        let p = Paint()
        p.isAntiAlias = true
        if let fill, !["line", "straightConnector1", "bentConnector3", "curvedConnector3"].contains(geometry) {
            p.style = .fill
            p.color = fill
            canvas.drawPath(path, p)
        }
        if let line {
            p.style = .stroke
            p.strokeWidth = max(1, lineWidth * k)
            p.color = line
            canvas.drawPath(path, p)
        }
        guard paragraphs.contains(where: { !$0.runs.isEmpty }) else { return }
        let box = Rect.fromLTRB(r.left + insets.left * k, r.top + insets.top * k, r.right - insets.right * k, r.bottom - insets.bottom * k)
        guard box.width > 2 else { return }
        var painters: [TextPainter] = []
        for para in paragraphs {
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
        let height = painters.reduce(0) { $0 + $1.height }
        var y = anchor == "ctr" ? box.center.dy - height / 2 : anchor == "b" ? box.bottom - height : box.top
        canvas.save()
        canvas.clipRect(r)
        for tp in painters {
            tp.paint(canvas, Offset(box.left, y))
            y += tp.height
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
            path.addRect(r)
        }
        return path
    }
}
