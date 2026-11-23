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
        var children: [Int: [Int]] = [:]     // a group's shape ids, in file order
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
            for s in OfficeArt.shapes(drawing: t, in: p ..< stop) { a.shapes[s.id] = s; if s.flags & 2 != 0 { a.children[s.parent, default: []].append(s.id) } }
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

    /// The preset outline of a shape type, nil for the ones with no preset (WordArt, freeforms): drawing those as a box would be wrong.
    static func geometry(_ type: Int) -> String? {
        switch type {
        case 1, 75, 202: return "rect"
        case 2: return "roundRect"
        case 3: return "ellipse"
        case 4: return "diamond"
        case 5: return "triangle"
        case 6: return "rtTriangle"
        case 7: return "parallelogram"
        case 8: return "trapezoid"
        case 9: return "hexagon"
        case 10: return "octagon"
        case 11: return "plus"
        case 13: return "rightArrow"
        case 20, 32: return "line"
        default: return nil
        }
    }

    /// The part of the picture that shows: the crop properties are fractions of the picture (16.16 fixed), top, bottom, left, right.
    static func crop(_ s: ArtShape?) -> String {
        guard let s else { return "" }
        func f(_ pid: Int) -> Int { let v = s.props[pid] ?? 0; return (v >= 0x8000_0000 ? v - 0x1_0000_0000 : v) * 100_000 / 65536 }
        let t = f(0x100), b = f(0x101), l = f(0x102), r = f(0x103)
        return t == 0 && b == 0 && l == 0 && r == 0 ? "" : "<a:srcRect l=\"\(l)\" t=\"\(t)\" r=\"\(r)\" b=\"\(b)\"/>"
    }

    /// A drawing run: `cx` by `cy` EMU, holding either the picture `rid` or the text box content.
    /// `place` is the `wp:anchor` or `wp:inline` wrapper's inside after the size, built by the caller.
    static func element(shape s: ArtShape?, rid: String?, content: String?, cx: Int, cy: Int, id: Int, at: (Int, Int) = (0, 0)) -> (xml: String, picture: Bool) {
        let rot = (s?.props[4] ?? 0) >> 16
        let flips = (s?.flags ?? 0) & 0x40 != 0 ? " flipH=\"1\"" : "", flipsV = (s?.flags ?? 0) & 0x80 != 0 ? " flipV=\"1\"" : ""
        let xfrm = "<a:xfrm\(rot != 0 ? " rot=\"\(rot * 60000)\"" : "")\(flips)\(flipsV)><a:off x=\"\(at.0)\" y=\"\(at.1)\"/><a:ext cx=\"\(cx)\" cy=\"\(cy)\"/></a:xfrm>"
        if let rid {
            return ("<pic:pic><pic:nvPicPr><pic:cNvPr id=\"\(id)\" name=\"Picture \(id)\"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed=\"\(rid)\"/>\(crop(s))<a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr>\(xfrm)<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></pic:spPr></pic:pic>", true)
        }
        let isBox = content != nil
        let ins = [(0x81, 91440), (0x82, 45720), (0x83, 91440), (0x84, 45720)].map { s?.props[$0.0] ?? $0.1 }
        let body = isBox ? "<wps:txbx><w:txbxContent>\(content!.isEmpty ? "<w:p/>" : content!)</w:txbxContent></wps:txbx>" : ""
        let sp = s ?? ArtShape()
        return ("<wps:wsp><wps:cNvSpPr\(isBox ? " txBox=\"1\"" : "")/><wps:spPr>\(xfrm)<a:prstGeom prst=\"\(geometry(sp.type) ?? "rect")\"><a:avLst/></a:prstGeom>\(fillLine(sp, isBox: isBox))</wps:spPr>\(body)<wps:bodyPr wrap=\"square\" lIns=\"\(ins[0])\" tIns=\"\(ins[1])\" rIns=\"\(ins[2])\" bIns=\"\(ins[3])\" anchor=\"t\"><a:noAutofit/></wps:bodyPr></wps:wsp>", false)
    }

    static func graphic(shape s: ArtShape?, rid: String?, content: String?, cx: Int, cy: Int, id: Int) -> String {
        let e = element(shape: s, rid: rid, content: content, cx: cx, cy: cy, id: id)
        let uri = e.picture ? "http://schemas.openxmlformats.org/drawingml/2006/picture" : "http://schemas.microsoft.com/office/word/2010/wordprocessingShape"
        return "<a:graphic><a:graphicData uri=\"\(uri)\">" + e.xml + "</a:graphicData></a:graphic>"
    }

    /// A group of shapes as DrawingML: its members sit in the group's own coordinate space (`chOff`, `chExt`).
    /// `member` gives the picture (relationship id) or text box content of a member shape.
    static func group(_ g: ArtShape, art: Art, cx: Int, cy: Int, member: (ArtShape) -> (rid: String?, content: String?)) -> String? {
        guard let r = g.groupRect, r[2] > r[0], r[3] > r[1], let ids = art.children[g.id] else { return nil }
        var kids = ""
        for id in ids {
            guard let c = art.shapes[id], let a = c.childAnchor, a[2] > a[0], a[3] > a[1] else { continue }
            let m = member(c)
            if m.rid == nil, m.content == nil, geometry(c.type) == nil { continue }
            kids += element(shape: c, rid: m.rid, content: m.content, cx: a[2] - a[0], cy: a[3] - a[1], id: id & 0xFFFF, at: (a[0], a[1])).xml
        }
        guard !kids.isEmpty else { return nil }
        return "<a:graphic><a:graphicData uri=\"http://schemas.microsoft.com/office/word/2010/wordprocessingGroup\"><wpg:wgp><wpg:cNvGrpSpPr/><wpg:grpSpPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"\(cx)\" cy=\"\(cy)\"/><a:chOff x=\"\(r[0])\" y=\"\(r[1])\"/><a:chExt cx=\"\(r[2] - r[0])\" cy=\"\(r[3] - r[1])\"/></a:xfrm></wpg:grpSpPr>\(kids)</wpg:wgp></a:graphicData></a:graphic>"
    }

    /// The run that holds a shape anchored in the text.
    static func floating(_ sp: Spa, shape s: ArtShape?, rid: String?, content: String?, order: Int, group: String? = nil) -> String {
        let cx = emu(max(0, sp.right - sp.left)), cy = emu(max(0, sp.bottom - sp.top))
        let wrap: String
        switch sp.wrap {
        case 0, 1: wrap = "<wp:wrapTopAndBottom/>"
        case 3: wrap = "<wp:wrapNone/>"
        default: wrap = "<wp:wrapSquare wrapText=\"bothSides\"/>"
        }
        let gr = group ?? graphic(shape: s, rid: rid, content: content, cx: cx, cy: cy, id: order + 1)
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
