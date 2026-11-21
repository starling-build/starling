// InkML strokes (a slide's `p:contentPart` pointing at ppt/ink/inkN.xml): the pen and highlighter
// traces PowerPoint draws, built as freeform shapes so the ordinary painter draws them.
import Foundation

enum InkStrokes {
    struct Trace {
        var points: [(x: Double, y: Double)]
        var color: String
        var widthCm: Double
        var heightCm: Double
        var highlighter: Bool
    }

    /// The traces of an InkML document, coordinates in cm.
    static func traces(_ root: XNode) -> [Trace] {
        var brushes: [String: XNode] = [:]
        func walk(_ n: XNode, _ f: (XNode) -> Void) { f(n); for c in n.children { walk(c, f) } }
        walk(root) { n in
            if n.name.hasSuffix("brush"), let id = n["xml:id"] { brushes[id] = n }
        }
        var out: [Trace] = []
        walk(root) { n in
            guard n.name.hasSuffix(":trace") || n.name == "trace" else { return }
            let pts = decode(n.text)
            guard pts.count > 0 else { return }
            var color = "000000", w = 0.1, h = 0.1, hi = false
            if let ref = n["brushRef"], let b = brushes[String(ref.dropFirst())] {
                for p in b.children {
                    let v = p["value"] ?? ""
                    switch p["name"] ?? "" {
                    case "color": color = String(v.drop { $0 == "#" })
                    case "width": w = Double(v) ?? w
                    case "height": h = Double(v) ?? h
                    case "rasterOp": hi = v == "maskPen"
                    default: break
                    }
                }
            }
            out.append(Trace(points: pts.map { (x: $0[0] / 1000, y: $0[1] / 1000) }, color: color, widthCm: w, heightCm: h, highlighter: hi))
        }
        return out
    }

    /// InkML's compressed trace text: a point per comma, a number per channel, `!` explicit, `'` first
    /// difference, `"` second difference (the mode stays for that channel until another prefix).
    static func decode(_ text: String) -> [[Double]] {
        var rows: [[Double]] = []
        var mode = [Character](repeating: "!", count: 8)
        var value = [Double](repeating: 0, count: 8)
        var delta = [Double](repeating: 0, count: 8)
        for pt in text.split(separator: ",", omittingEmptySubsequences: true) {
            var nums: [(Character?, String)] = []
            var pre: Character? = nil
            var cur = ""
            func flush() { if !cur.isEmpty { nums.append((pre, cur)); cur = ""; pre = nil } }
            for ch in pt {
                if ch == "!" || ch == "'" || ch == "\"" { flush(); pre = ch }
                else if ch == "-" || ch == "+" { flush(); cur.append(ch) }
                else if ch.isWholeNumber || ch == "." { cur.append(ch) }
                else { flush() }
            }
            flush()
            var row: [Double] = []
            for (i, n) in nums.enumerated() where i < 8 {
                if let p = n.0 { mode[i] = p }
                let v = Double(n.1) ?? 0
                switch mode[i] {
                case "'": delta[i] = v; value[i] += v
                case "\"": delta[i] += v; value[i] += delta[i]
                default: value[i] = v; delta[i] = 0
                }
                row.append(value[i])
            }
            if row.count >= 2 { rows.append(row) }
        }
        return rows
    }

    /// One freeform `p:sp` per trace, placed by the content part's frame (`off`/`ext` in EMU): the ink's
    /// own bounding box lies on that frame.
    static func shapes(_ root: XNode, offX: Double, offY: Double) -> [(XNode, Bool)] {
        let ts = traces(root)
        guard let minX = ts.flatMap({ $0.points.map(\.x) }).min(), let minY = ts.flatMap({ $0.points.map(\.y) }).min() else { return [] }
        let emu = 360000.0
        var out: [(XNode, Bool)] = []
        for t in ts {
            let xs = t.points.map(\.x), ys = t.points.map(\.y)
            let tx = xs.min() ?? 0, ty = ys.min() ?? 0
            let w = max(1, Int(((xs.max() ?? 0) - tx) * emu)), h = max(1, Int(((ys.max() ?? 0) - ty) * emu))
            func n(_ name: String, _ a: [String: String] = [:], _ k: [XNode] = []) -> XNode {
                let x = XNode(name: name, attrs: a); x.children = k; return x
            }
            let path = n("a:path", ["w": String(w), "h": String(h), "fill": "none"],
                         t.points.enumerated().map { (i, p) in
                             n(i == 0 ? "a:moveTo" : "a:lnTo", [:], [n("a:pt", ["x": String(Int((p.x - tx) * emu)), "y": String(Int((p.y - ty) * emu))])])
                         })
            let geom = n("a:custGeom", [:], [n("a:avLst"), n("a:gdLst"), n("a:ahLst"), n("a:cxnLst"),
                                              n("a:rect", ["l": "0", "t": "0", "r": "r", "b": "b"]), n("a:pathLst", [:], [path])])
            let lw = Int((t.highlighter ? t.heightCm : t.widthCm) * emu)
            let ln = n("a:ln", ["w": String(lw), "cap": t.highlighter ? "flat" : "rnd"],
                       [n("a:solidFill", [:], [n("a:srgbClr", ["val": t.color], t.highlighter ? [n("a:alpha", ["val": "50000"])] : [])]),
                        t.highlighter ? n("a:miter", ["lim": "800000"]) : n("a:round")])
            let xfrm = n("a:xfrm", [:], [n("a:off", ["x": String(Int(offX + (tx - minX) * emu)), "y": String(Int(offY + (ty - minY) * emu))]),
                                          n("a:ext", ["cx": String(w), "cy": String(h)])])
            let spPr = n("p:spPr", [:], [xfrm, geom, n("a:noFill"), ln])
            let sp = n("p:sp", [:], [n("p:nvSpPr", [:], [n("p:cNvPr", ["id": "0", "name": "Ink"]), n("p:cNvSpPr"), n("p:nvPr")]), spPr])
            out.append((sp, t.highlighter))
        }
        return out
    }
}
