// The shapes of a legacy .ppt slide as PresentationML: the OfficeArt drawing with PowerPoint's
// own children (ClientAnchor, ClientData, ClientTextbox). Step 4a covers the shapes that hold text.
//
// Shared code (also built for the web): bounds-checked, never traps.

import Foundation

extension PptFile {
    private static let maxDepth = 16

    /// The scheme-colour names, in the order of a colour scheme's first eight entries.
    private static let schemeNames = ["bg1", "tx1", "bg2", "tx2", "accent1", "accent2", "hlink", "folHlink"]

    /// An OfficeArt colour property as a DrawingML colour: a scheme index (flag 0x08) or a literal RGB.
    static func artColor(_ v: Int) -> String {
        if v >> 24 & 0x08 != 0, v & 0xFF < schemeNames.count { return "<a:schemeClr val=\"\(schemeNames[v & 0xFF])\"/>" }
        return "<a:srgbClr val=\"\(DocArt.rgb(v & 0xFFFFFF) ?? "000000")\"/>"
    }

    /// Fill and outline of a shape from its properties; a placeholder or a shape that sets nothing inherits.
    static func fillLineXML(_ s: ArtShape, placeholder: Bool, picture: (Int) -> String? = { _ in nil }) -> String {
        var x = ""
        let boxy = !placeholder && s.type != 202
        if DocArt.flag(s, 0x1BF, bit: 4, default: boxy && s.type != 20 && s.type != 32) {
            let fore = artColor(s.props[0x181] ?? 0xFFFFFF)
            switch s.props[0x180] ?? 0 {
            case 4...7:
                // A shaded fill: fore colour to back colour along the fill angle (16.16 degrees).
                let angle = (((s.props[0x18B] ?? 0) >> 16) % 360 + 360) % 360 * 60000
                x += "<a:gradFill rotWithShape=\"1\"><a:gsLst><a:gs pos=\"0\">\(fore)</a:gs><a:gs pos=\"100000\">\(artColor(s.props[0x183] ?? 0xFFFFFF))</a:gs></a:gsLst><a:lin ang=\"\(angle)\" scaled=\"0\"/></a:gradFill>"
            case 2, 3:
                if let pib = s.props[0x186], let rid = picture(pib) {
                    let tile = s.props[0x180] == 2 ? "<a:tile/>" : "<a:stretch><a:fillRect/></a:stretch>"
                    x += "<a:blipFill><a:blip r:embed=\"\(rid)\"/>\(tile)</a:blipFill>"
                } else { x += "<a:solidFill>\(fore)</a:solidFill>" }
            default:
                x += "<a:solidFill>\(fore)</a:solidFill>"
            }
        } else if !placeholder || s.props[0x1BF] != nil { x += "<a:noFill/>" }
        if DocArt.flag(s, 0x1FF, bit: 3, default: boxy) {
            x += "<a:ln w=\"\(s.props[0x1CB] ?? 9525)\"><a:solidFill>\(artColor(s.props[0x1C0] ?? 0))</a:solidFill></a:ln>"
        } else if !placeholder || s.props[0x1FF] != nil { x += "<a:ln><a:noFill/></a:ln>" }
        return x
    }

    /// `p:sp` / `p:grpSp` elements for the shapes of a slide, in drawing order.
    /// `picture` turns a picture-store index into the relationship id a part holds it under (nil: the picture cannot be used).
    /// `master`: a master's own drawing, where placeholders are left out.
    func shapeXML(of slide: Page, master: Bool = false, picture: (Int) -> String? = { _ in nil }) -> String {
        guard let c = record(persistId: slide.persistId), c.isContainer else { return "" }
        var n = 1
        func s16(_ k: Int) -> Int { let v = OfficeArt.u16(data, k); return v >= 0x8000 ? v - 0x10000 : v }
        func s32(_ k: Int) -> Int { let v = OfficeArt.u32(data, k); return v >= 0x8000_0000 ? v - 0x1_0000_0000 : v }
        /// Reads one shape container: its OfficeArt properties plus PowerPoint's own children.
        func read(_ sp: ArtRecord) -> (art: ArtShape, anchor: [Int]?, placeholder: Int?, block: PptTextBlock?) {
            let art = OfficeArt.shapes(drawing: data, in: (sp.body.lowerBound - 8) ..< sp.body.upperBound).first ?? ArtShape()
            var anchor: [Int]? = nil
            var placeholder: Int? = nil
            var block: PptTextBlock? = nil
            for ch in OfficeArt.records(data, in: sp.body) {
                let b = ch.body.lowerBound
                switch ch.type {
                case 0xF010:
                    // top, left, right, bottom
                    if ch.body.count >= 16 { anchor = [s32(b), s32(b + 4), s32(b + 8), s32(b + 12)] }
                    else if ch.body.count >= 8 { anchor = [s16(b), s16(b + 2), s16(b + 4), s16(b + 6)] }
                case 0xF011:
                    for d in OfficeArt.records(data, in: ch.body) where d.type == 0x0BC3 && d.body.count >= 5 {
                        placeholder = Int(data[d.body.lowerBound + 4])
                    }
                case 0xF00D:
                    let inner = OfficeArt.records(data, in: ch.body)
                    if let ref = inner.first(where: { $0.type == PptText.outlineRefType }), ref.body.count >= 4 {
                        let i = OfficeArt.u32(data, ref.body.lowerBound)
                        if i < slide.texts.count { block = slide.texts[i] }
                    } else {
                        block = PptText.blocks(inner, in: data).first
                    }
                default: break
                }
            }
            return (art, anchor, placeholder, block)
        }
        func xfrm(_ tag: String, _ a: [Int]?, rot: Int, flipH: Bool, flipV: Bool, child: [Int]? = nil) -> String {
            guard let a = a, a[2] >= a[1], a[3] >= a[0] else { return "" }
            var x = "<a:xfrm"
            if rot != 0 { x += " rot=\"\(rot)\"" }
            if flipH { x += " flipH=\"1\"" }
            if flipV { x += " flipV=\"1\"" }
            x += "><a:off x=\"\(PptBuild.emu(a[1]))\" y=\"\(PptBuild.emu(a[0]))\"/><a:ext cx=\"\(PptBuild.emu(a[2] - a[1]))\" cy=\"\(PptBuild.emu(a[3] - a[0]))\"/>"
            if let ch = child, ch.count == 4, ch[2] >= ch[0], ch[3] >= ch[1] {
                x += "<a:chOff x=\"\(PptBuild.emu(ch[0]))\" y=\"\(PptBuild.emu(ch[1]))\"/><a:chExt cx=\"\(PptBuild.emu(ch[2] - ch[0]))\" cy=\"\(PptBuild.emu(ch[3] - ch[1]))\"/>"
            }
            return x + "</a:xfrm>"
        }
        func rotation(_ s: ArtShape) -> Int {
            // 16.16 fixed degrees -> 60000ths of a degree
            var v = s.props[0x4] ?? 0
            if v >= 0x8000_0000 { v -= 0x1_0000_0000 }
            let r = Int((Double(v) / 65536.0 * 60000.0).rounded()) % 21_600_000
            return r < 0 ? r + 21_600_000 : r
        }
        func shape(_ sp: ArtRecord) -> String {
            let (art, anchor, placeholder, block) = read(sp)
            if master && placeholder != nil { return "" }
            if art.type == 75, art.pib > 0, let rid = picture(art.pib) {
                n += 1
                var x = "<p:pic><p:nvPicPr><p:cNvPr id=\"\(n)\" name=\"Picture \(n)\"/><p:cNvPicPr/><p:nvPr/></p:nvPicPr>"
                x += "<p:blipFill><a:blip r:embed=\"\(rid)\"/>\(DocArt.crop(art))<a:stretch><a:fillRect/></a:stretch></p:blipFill><p:spPr>"
                x += xfrm("xfrm", anchor, rot: rotation(art), flipH: art.flags & 0x40 != 0, flipV: art.flags & 0x80 != 0)
                return x + "<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></p:spPr></p:pic>"
            }
            var geom: String? = nil
            if let g = DocArt.geometry(art.type) { geom = "<a:prstGeom prst=\"\(g)\"><a:avLst/></a:prstGeom>" }
            else if art.type == 0, let f = DocArt.freeform(art) { geom = f }
            if geom == nil, block != nil || placeholder != nil || art.type == 202 { geom = "<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom>" }
            guard let geometry = geom else { return "" }
            n += 1
            let phType: String? = placeholder.flatMap { Self.placeholderType($0) }
            var xml = "<p:sp><p:nvSpPr><p:cNvPr id=\"\(n)\" name=\"Shape \(n)\"/><p:cNvSpPr/><p:nvPr>"
            if let p = placeholder { xml += phType.map { "<p:ph type=\"\($0)\"/>" } ?? (p == 0 ? "" : "<p:ph/>") }
            xml += "</p:nvPr></p:nvSpPr><p:spPr>"
            xml += xfrm("xfrm", anchor, rot: rotation(art), flipH: art.flags & 0x40 != 0, flipV: art.flags & 0x80 != 0)
            xml += geometry + Self.fillLineXML(art, placeholder: placeholder != nil, picture: picture) + "</p:spPr>"
            if block != nil || placeholder != nil {
                xml += "<p:txBody><a:bodyPr/><a:lstStyle/>" + paragraphsXML(block) + "</p:txBody>"
            }
            return xml + "</p:sp>"
        }
        func walk(_ r: Range<Int>, depth: Int, skipFirst: Bool) -> String {
            guard depth < Self.maxDepth else { return "" }
            var first = skipFirst
            var out = ""
            for rec in OfficeArt.records(data, in: r) where rec.isContainer {
                if rec.type == 0xF004 {
                    if first { first = false } else { out += shape(rec) }
                } else if rec.type == 0xF003 {
                    // The group's own anchor and coordinate space sit in its first shape.
                    guard let head = OfficeArt.records(data, in: rec.body).first(where: { $0.type == 0xF004 }) else { continue }
                    let (art, anchor, _, _) = read(head)
                    let inner = walk(rec.body, depth: depth + 1, skipFirst: true)
                    guard !inner.isEmpty else { continue }
                    n += 1
                    out += "<p:grpSp><p:nvGrpSpPr><p:cNvPr id=\"\(n)\" name=\"Group \(n)\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr>"
                    out += xfrm("xfrm", anchor, rot: rotation(art), flipH: art.flags & 0x40 != 0, flipV: art.flags & 0x80 != 0, child: art.groupRect)
                    out += "</p:grpSpPr>" + inner + "</p:grpSp>"
                }
            }
            return out
        }
        var out = ""
        for drawing in OfficeArt.records(data, in: c.body) where drawing.type == 0x040C {
            for dg in OfficeArt.records(data, in: drawing.body) where dg.type == 0xF002 {
                // The background shape is a direct child of the drawing; the shapes are inside the top group.
                // (The top group itself is flat: its first shape is the group, and slide space is its own.)
                for top in OfficeArt.records(data, in: dg.body) where top.type == 0xF003 && top.isContainer {
                    out += walk(top.body, depth: 1, skipFirst: true)
                }
            }
        }
        return out
    }

    /// PlaceholderAtom type -> `p:ph` type (nil: an object placeholder or none).
    static func placeholderType(_ t: Int) -> String? {
        switch t {
        case 1, 13, 17: return "title"
        case 2, 14, 18: return "body"
        case 3, 15: return "ctrTitle"
        case 4, 16: return "subTitle"
        case 7: return "dt"
        case 8: return "sldNum"
        case 9: return "ftr"
        case 10: return "hdr"
        case 20: return "chart"
        case 21: return "tbl"
        case 22: return "clipArt"
        case 23: return "dgm"
        case 24: return "media"
        case 26: return "pic"
        default: return nil
        }
    }
}
