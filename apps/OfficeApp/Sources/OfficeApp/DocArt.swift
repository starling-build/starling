// Word binary (.doc) drawings: the shapes the text anchors (PlcSpaMom + the drawing records in the
// table stream), their pictures (stored in the WordDocument stream or inline in the Data stream), and
// the DrawingML the .docx reader reads for them. Shared code (also built for the web).

import Foundation

enum DocArt {
    /// One anchor of the PlcSpaMom: the character it sits at, the shape it names and where the shape goes (twips).
    struct Spa {
        var cp = 0, spid = 0, left = 0, top = 0, right = 0, bottom = 0, flags = 0
        var xFrom: String { ["margin", "page", "column", "margin"][flags >> 1 & 3] }
        var yFrom: String { ["margin", "page", "paragraph", "margin"][flags >> 3 & 3] }
        var wrap: Int { flags >> 5 & 15 }
        var behind: Bool { flags & 0x4000 != 0 }
    }

    struct Art {
        var shapes: [Int: ArtShape] = [:]
        var blips: [ArtBlip?] = []
    }

    static func i32(_ b: [UInt8], _ k: Int) -> Int { let v = OfficeArt.u32(b, k); return v >= 0x8000_0000 ? v - 0x1_0000_0000 : v }

    static func spas(_ t: [UInt8], at fc: Int, count lcb: Int) -> [Spa] {
        guard let p = DocProps.plex(t, at: fc, count: lcb, size: 26) else { return [] }
        var out: [Spa] = []
        for k in 0 ..< p.cps.count - 1 {
            let a = p.at + 26 * k
            out.append(Spa(cp: p.cps[k], spid: OfficeArt.u32(t, a), left: i32(t, a + 4), top: i32(t, a + 8), right: i32(t, a + 12), bottom: i32(t, a + 16), flags: OfficeArt.u16(t, a + 20)))
        }
        return out
    }

    /// The drawing group (with its picture store; a picture may sit in the WordDocument stream) and the shapes of the drawings.
    static func art(t: [UInt8], w: [UInt8], at fc: Int, count lcb: Int) -> Art {
        var a = Art()
        guard fc >= 0, lcb >= 8, fc + lcb <= t.count else { return a }
        let end = fc + lcb
        var p = fc
        // The drawing group container, then (one byte, a drawing container) for each drawing.
        let dgg = OfficeArt.records(t, in: p ..< min(end, p + 8 + OfficeArt.u32(t, p + 4)))
        if let g = dgg.first {
            p = g.body.upperBound
            for r in OfficeArt.records(t, in: g.body) where r.type == 0xF001 {
                for e in OfficeArt.records(t, in: r.body) {
                    if e.type != 0xF007 { a.blips.append(OfficeArt.blipRecord(t, e)); continue }
                    let s = e.body.lowerBound
                    let cbName = Int(t.indices.contains(s + 33) ? t[s + 33] : 0)
                    if e.body.count > 36 + cbName + 8 { a.blips.append(OfficeArt.fbse(t, e)); continue }
                    let fo = OfficeArt.u32(t, s + 28)
                    if fo != 0xFFFF_FFFF, fo + 8 <= w.count {
                        let h = OfficeArt.u16(w, fo + 2)
                        a.blips.append(OfficeArt.blipRecord(w, ArtRecord(ver: OfficeArt.u16(w, fo) & 0xF, inst: OfficeArt.u16(w, fo) >> 4, type: h, body: fo + 8 ..< min(w.count, fo + 8 + OfficeArt.u32(w, fo + 4)))))
                    } else { a.blips.append(nil) }
                }
            }
        }
        while p + 9 <= end {
            p += 1
            let len = OfficeArt.u32(t, p + 4)
            let stop = min(end, p + 8 + len)
            for s in OfficeArt.shapes(drawing: t, in: p ..< stop) { a.shapes[s.id] = s }
            p = stop
        }
        return a
    }

    // MARK: DrawingML

    static func emu(_ twips: Int) -> Int { twips * 635 }

    static func rgb(_ v: Int) -> String? {
        guard v >> 24 & 0xFF == 0 else { return nil }
        let h = "0123456789ABCDEF".map { String($0) }
        func b(_ x: Int) -> String { h[x >> 4 & 15] + h[x & 15] }
        return b(v & 255) + b(v >> 8 & 255) + b(v >> 16 & 255)
    }

    /// A boolean of a style-booleans property: a bit counts only when its use-mask bit (16 higher) is set.
    static func flag(_ s: ArtShape, _ pid: Int, bit: Int, default d: Bool) -> Bool {
        guard let v = s.props[pid], v >> (16 + bit) & 1 != 0 else { return d }
        return v >> bit & 1 != 0
    }

    static func fillLine(_ s: ArtShape, isBox: Bool) -> String {
        var x = ""
        let filled = flag(s, 0x1BF, bit: 4, default: isBox)
        if filled { x += "<a:solidFill><a:srgbClr val=\"\(rgb(s.props[0x181] ?? 0xFFFFFF) ?? "FFFFFF")\"/></a:solidFill>" } else { x += "<a:noFill/>" }
        if flag(s, 0x1FF, bit: 3, default: isBox) {
            x += "<a:ln w=\"\(s.props[0x1CB] ?? 9525)\"><a:solidFill><a:srgbClr val=\"\(rgb(s.props[0x1C0] ?? 0) ?? "000000")\"/></a:solidFill></a:ln>"
        } else { x += "<a:ln><a:noFill/></a:ln>" }
        return x
    }

    static func geometry(_ type: Int) -> String {
        switch type {
        case 2: return "roundRect"
        case 3: return "ellipse"
        case 20: return "line"
        default: return "rect"
        }
    }

    /// A drawing run: `cx` by `cy` EMU, holding either the picture `rid` or the text box content.
    /// `place` is the `wp:anchor` or `wp:inline` wrapper's inside after the size, built by the caller.
    static func graphic(shape s: ArtShape?, rid: String?, content: String?, cx: Int, cy: Int, id: Int) -> String {
        let rot = (s?.props[4] ?? 0) >> 16
        let xfrm = "<a:xfrm\(rot != 0 ? " rot=\"\(rot * 60000)\"" : "")><a:off x=\"0\" y=\"0\"/><a:ext cx=\"\(cx)\" cy=\"\(cy)\"/></a:xfrm>"
        if let rid {
            return "<a:graphic><a:graphicData uri=\"http://schemas.openxmlformats.org/drawingml/2006/picture\"><pic:pic><pic:nvPicPr><pic:cNvPr id=\"\(id)\" name=\"Picture \(id)\"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed=\"\(rid)\"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr>\(xfrm)<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic>"
        }
        let isBox = content != nil
        let ins = [(0x81, 91440), (0x82, 45720), (0x83, 91440), (0x84, 45720)].map { s?.props[$0.0] ?? $0.1 }
        let body = isBox ? "<wps:txbx><w:txbxContent>\(content!.isEmpty ? "<w:p/>" : content!)</w:txbxContent></wps:txbx>" : ""
        let sp = s ?? ArtShape()
        return "<a:graphic><a:graphicData uri=\"http://schemas.microsoft.com/office/word/2010/wordprocessingShape\"><wps:wsp><wps:cNvSpPr\(isBox ? " txBox=\"1\"" : "")/><wps:spPr>\(xfrm)<a:prstGeom prst=\"\(geometry(sp.type))\"><a:avLst/></a:prstGeom>\(fillLine(sp, isBox: isBox))</wps:spPr>\(body)<wps:bodyPr wrap=\"square\" lIns=\"\(ins[0])\" tIns=\"\(ins[1])\" rIns=\"\(ins[2])\" bIns=\"\(ins[3])\" anchor=\"t\"><a:noAutofit/></wps:bodyPr></wps:wsp></a:graphicData></a:graphic>"
    }

    /// The run that holds a shape anchored in the text.
    static func floating(_ sp: Spa, shape s: ArtShape?, rid: String?, content: String?, order: Int) -> String {
        let cx = emu(max(0, sp.right - sp.left)), cy = emu(max(0, sp.bottom - sp.top))
        let wrap: String
        switch sp.wrap {
        case 0, 1: wrap = "<wp:wrapTopAndBottom/>"
        case 3: wrap = "<wp:wrapNone/>"
        default: wrap = "<wp:wrapSquare wrapText=\"bothSides\"/>"
        }
        let gr = graphic(shape: s, rid: rid, content: content, cx: cx, cy: cy, id: order + 1)
        return "<w:r><w:drawing><wp:anchor distT=\"0\" distB=\"0\" distL=\"114300\" distR=\"114300\" simplePos=\"0\" relativeHeight=\"\(251_658_240 + order)\" behindDoc=\"\(sp.behind ? 1 : 0)\" locked=\"0\" layoutInCell=\"1\" allowOverlap=\"1\"><wp:simplePos x=\"0\" y=\"0\"/><wp:positionH relativeFrom=\"\(sp.xFrom)\"><wp:posOffset>\(emu(sp.left))</wp:posOffset></wp:positionH><wp:positionV relativeFrom=\"\(sp.yFrom)\"><wp:posOffset>\(emu(sp.top))</wp:posOffset></wp:positionV><wp:extent cx=\"\(cx)\" cy=\"\(cy)\"/><wp:effectExtent l=\"0\" t=\"0\" r=\"0\" b=\"0\"/>\(wrap)<wp:docPr id=\"\(order + 1)\" name=\"Shape \(order + 1)\"/><wp:cNvGraphicFramePr/>\(gr)</wp:anchor></w:drawing></w:r>"
    }

    /// The run of a picture that sits in the line (the Data stream's PICF at `offset`), and its picture.
    static func inline(data d: [UInt8], at offset: Int, rid: (ArtBlip) -> String?) -> String? {
        guard offset >= 0, offset + 68 <= d.count else { return nil }
        let lcb = OfficeArt.u32(d, offset), cbHeader = OfficeArt.u16(d, offset + 4), mm = OfficeArt.u16(d, offset + 6)
        var p = offset + cbHeader
        guard cbHeader >= 68, lcb > cbHeader, offset + lcb <= d.count else { return nil }
        if mm == 0x66, p < d.count { p += 1 + Int(d[p]) }
        let goalW = OfficeArt.u16(d, offset + 28), goalH = OfficeArt.u16(d, offset + 30)
        let mx = OfficeArt.u16(d, offset + 32), my = OfficeArt.u16(d, offset + 34)
        var blip: ArtBlip?
        for r in OfficeArt.records(d, in: p ..< offset + lcb) {
            if r.type == 0xF007, blip == nil { blip = OfficeArt.fbse(d, r) }
        }
        guard let blip, let id = rid(blip) else { return nil }
        let cx = emu(goalW * mx / 1000), cy = emu(goalH * my / 1000)
        guard cx > 0, cy > 0 else { return nil }
        return "<w:r><w:drawing><wp:inline distT=\"0\" distB=\"0\" distL=\"0\" distR=\"0\"><wp:extent cx=\"\(cx)\" cy=\"\(cy)\"/><wp:effectExtent l=\"0\" t=\"0\" r=\"0\" b=\"0\"/><wp:docPr id=\"\(offset + 1)\" name=\"Picture\"/><wp:cNvGraphicFramePr/>\(graphic(shape: nil, rid: id, content: nil, cx: cx, cy: cy, id: offset + 1))</wp:inline></w:drawing></w:r>"
    }
}
