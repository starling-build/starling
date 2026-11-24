// The shapes of a legacy .ppt slide as PresentationML: the OfficeArt drawing with PowerPoint's
// own children (ClientAnchor, ClientData, ClientTextbox). Step 4a covers the shapes that hold text.
//
// Shared code (also built for the web): bounds-checked, never traps.

import Foundation

extension PptFile {
    private static let maxDepth = 16

    /// `p:sp` elements for the text-bearing shapes of a slide, in drawing order.
    func shapeXML(of slide: Page) -> String {
        guard let c = record(persistId: slide.persistId), c.isContainer else { return "" }
        var out = ""
        var n = 1
        func escape(_ t: String) -> String {
            var o = ""
            for ch in t { switch ch { case "&": o += "&amp;"; case "<": o += "&lt;"; case ">": o += "&gt;"; case "\"": o += "&quot;"; default: o.append(ch) } }
            return o
        }
        func shape(_ sp: ArtRecord) {
            var anchor: [Int]? = nil
            var placeholder: Int? = nil
            var block: PptTextBlock? = nil
            for ch in OfficeArt.records(data, in: sp.body) {
                let b = ch.body.lowerBound
                switch ch.type {
                case 0xF010:
                    func s16(_ k: Int) -> Int { let v = OfficeArt.u16(data, k); return v >= 0x8000 ? v - 0x10000 : v }
                    func s32(_ k: Int) -> Int { let v = OfficeArt.u32(data, k); return v >= 0x8000_0000 ? v - 0x1_0000_0000 : v }
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
            guard block != nil || placeholder != nil else { return }
            n += 1
            let phType: String? = placeholder.flatMap { Self.placeholderType($0) }
            var xml = "<p:sp><p:nvSpPr><p:cNvPr id=\"\(n)\" name=\"Shape \(n)\"/><p:cNvSpPr/><p:nvPr>"
            if let p = placeholder { xml += phType.map { "<p:ph type=\"\($0)\"/>" } ?? (p == 0 ? "" : "<p:ph/>") }
            xml += "</p:nvPr></p:nvSpPr><p:spPr>"
            if let a = anchor, a[2] >= a[1], a[3] >= a[0] {
                xml += "<a:xfrm><a:off x=\"\(PptBuild.emu(a[1]))\" y=\"\(PptBuild.emu(a[0]))\"/><a:ext cx=\"\(PptBuild.emu(a[2] - a[1]))\" cy=\"\(PptBuild.emu(a[3] - a[0]))\"/></a:xfrm>"
            }
            xml += "<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></p:spPr>"
            xml += "<p:txBody><a:bodyPr/><a:lstStyle/>"
            let paras = block.map { PptText.paragraphs($0.text) } ?? [[""]]
            for lines in paras {
                xml += "<a:p>"
                for (i, line) in lines.enumerated() {
                    if i > 0 { xml += "<a:br/>" }
                    if !line.isEmpty { xml += "<a:r><a:t>\(escape(line))</a:t></a:r>" }
                }
                xml += "</a:p>"
            }
            out += xml + "</p:txBody></p:sp>"
        }
        func walk(_ r: Range<Int>, depth: Int, skipFirst: Bool) {
            guard depth < Self.maxDepth else { return }
            var first = skipFirst
            for rec in OfficeArt.records(data, in: r) where rec.isContainer {
                if rec.type == 0xF004 {
                    if first { first = false } else { shape(rec) }
                } else if rec.type == 0xF003 {
                    walk(rec.body, depth: depth + 1, skipFirst: true)
                }
            }
        }
        for drawing in OfficeArt.records(data, in: c.body) where drawing.type == 0x040C {
            for dg in OfficeArt.records(data, in: drawing.body) where dg.type == 0xF002 {
                // The background shape is a direct child of the drawing; the shapes are inside the top group.
                walk(dg.body, depth: 0, skipFirst: false)
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
