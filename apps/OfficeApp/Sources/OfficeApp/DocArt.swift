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

    static func i32(_ b: [UInt8], _ k: Int) -> Int { let v = OfficeArt.u32(b, k); return Int(Int32(truncatingIfNeeded: v)) }

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
                    if UInt32(truncatingIfNeeded: fo) != UInt32.max, fo >= 0, fo + 8 <= w.count {
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

    static func fillLine(_ s: ArtShape, isBox: Bool, freeform: Bool = false) -> String {
        var x = ""
        let filled = flag(s, 0x1BF, bit: 4, default: isBox)
        if filled { x += "<a:solidFill><a:srgbClr val=\"\(rgb(s.props[0x181] ?? 0xFFFFFF) ?? "FFFFFF")\"/></a:solidFill>" } else { x += "<a:noFill/>" }
        if flag(s, 0x1FF, bit: 3, default: isBox || freeform) {
            x += "<a:ln w=\"\(s.props[0x1CB] ?? 9525)\"><a:solidFill><a:srgbClr val=\"\(rgb(s.props[0x1C0] ?? 0) ?? "000000")\"/></a:solidFill></a:ln>"
        } else { x += "<a:ln><a:noFill/></a:ln>" }
        return x
    }

    /// The preset outline of a shape type, nil for the ones with no preset (WordArt, freeforms): drawing those as a box would be wrong.
    /// (The OfficeArt shape types by number; a type was dropped unless it was one of the first dozen, so a .ppt's chevrons, braces,
    /// callouts and flowchart boxes went missing. Types whose old outline has no preset of the same shape stay nil: the thick
    /// arrow, balloon and seal, the arc, the leader callouts and the 90-degree callouts, and 100, which newer writers give their
    /// own outlines too.)
    static func geometry(_ type: Int) -> String? {
        switch type {
        case 1, 75, 202: return "rect"
        case 20, 32: return "line"
        case 109 ... 135:
            return "flowChart" + ["Process", "Decision", "InputOutput", "PredefinedProcess", "InternalStorage", "Document",
                                  "MultiDocument", "Terminator", "Preparation", "ManualInput", "ManualOperation", "Connector",
                                  "PunchedCard", "PunchedTape", "SummingJunction", "Or", "Collate", "Sort", "Extract", "Merge",
                                  "OfflineStorage", "OnlineStorage", "MagneticTape", "MagneticDisk", "MagneticDrum", "Display",
                                  "Delay"][type - 109]
        case 189 ... 200:
            return "actionButton" + ["Blank", "Home", "Help", "Information", "ForwardNext", "BackPrevious", "End", "Beginning",
                                     "Return", "Document", "Sound", "Movie"][type - 189]
        default: return presets[type]
        }
    }

    private static let presets: [Int: String] = [
        2: "roundRect", 3: "ellipse", 4: "diamond", 5: "triangle", 6: "rtTriangle", 7: "parallelogram", 8: "trapezoid",
        9: "hexagon", 10: "octagon", 11: "plus", 12: "star5", 13: "rightArrow", 15: "homePlate", 16: "cube", 21: "plaque",
        22: "can", 23: "donut", 33: "bentConnector2", 34: "bentConnector3", 35: "bentConnector4", 36: "bentConnector5",
        37: "curvedConnector2", 38: "curvedConnector3", 39: "curvedConnector4", 40: "curvedConnector5", 53: "ribbon",
        54: "ribbon2", 55: "chevron", 56: "pentagon", 57: "noSmoking", 58: "star8", 59: "star16", 60: "star32",
        61: "wedgeRectCallout", 62: "wedgeRoundRectCallout", 63: "wedgeEllipseCallout", 64: "wave", 65: "foldedCorner",
        66: "leftArrow", 67: "downArrow", 68: "upArrow", 69: "leftRightArrow", 70: "upDownArrow", 71: "irregularSeal1",
        72: "irregularSeal2", 73: "lightningBolt", 74: "heart", 76: "quadArrow", 77: "leftArrowCallout",
        78: "rightArrowCallout", 79: "upArrowCallout", 80: "downArrowCallout", 81: "leftRightArrowCallout",
        82: "upDownArrowCallout", 83: "quadArrowCallout", 84: "bevel", 85: "leftBracket", 86: "rightBracket",
        87: "leftBrace", 88: "rightBrace", 89: "leftUpArrow", 90: "bentUpArrow", 91: "bentArrow", 92: "star24",
        93: "stripedRightArrow", 94: "notchedRightArrow", 95: "blockArc", 96: "smileyFace", 97: "verticalScroll",
        98: "horizontalScroll", 99: "circularArrow", 101: "uturnArrow", 102: "curvedRightArrow", 103: "curvedLeftArrow",
        104: "curvedUpArrow", 105: "curvedDownArrow", 106: "cloudCallout", 107: "ellipseRibbon", 108: "ellipseRibbon2",
        176: "flowChartAlternateProcess", 177: "flowChartOffpageConnector", 182: "leftRightUpArrow", 183: "sun",
        184: "moon", 185: "bracketPair", 186: "bracePair", 187: "star4", 188: "doubleWave",
    ]

    /// Whether a shape has something to draw: a preset outline, a freeform's own path, or WordArt text.
    static func drawable(_ s: ArtShape) -> Bool {
        geometry(s.type) != nil || (wordArtPreset(s.type) != nil && wordArtText(s) != nil) || (s.type == 0 && freeform(s) != nil)
    }

    /// The text warp of a WordArt shape type (136 to 175, in the order of the OfficeArt shape list).
    static func wordArtPreset(_ type: Int) -> String? {
        let names = ["textPlain", "textStop", "textTriangle", "textTriangleInverted", "textChevron", "textChevronInverted",
                     "textRingInside", "textRingOutside", "textArchUp", "textArchDown", "textCircle", "textButton",
                     "textArchUpPour", "textArchDownPour", "textCirclePour", "textButtonPour", "textCurveUp", "textCurveDown",
                     "textCascadeUp", "textCascadeDown", "textWave1", "textWave2", "textDoubleWave1", "textWave4",
                     "textInflate", "textDeflate", "textInflateBottom", "textDeflateBottom", "textInflateTop", "textDeflateTop",
                     "textDeflateInflate", "textDeflateInflateDeflate", "textFadeRight", "textFadeLeft", "textFadeUp", "textFadeDown",
                     "textSlantUp", "textSlantDown", "textCanUp", "textCanDown"]
        return type >= 136 && type - 136 < names.count ? names[type - 136] : nil
    }

    /// The text of a WordArt shape.
    static func wordArtText(_ s: ArtShape) -> String? {
        guard let d = s.complex[0xC0], d.count >= 2 else { return nil }
        var u: [UInt16] = []
        var k = 0
        while k + 1 < d.count { let c = UInt16(d[k]) | UInt16(d[k + 1]) << 8; if c == 0 { break }; u.append(c); k += 2 }
        let t = String(decoding: u, as: UTF16.self)
        return t.isEmpty ? nil : t
    }

    static func xmlEscape(_ t: String) -> String {
        var o = ""
        for c in t { switch c { case "&": o += "&amp;"; case "<": o += "&lt;"; case ">": o += "&gt;"; case "\"": o += "&quot;"; default: o.append(c) } }
        return o
    }

    /// WordArt as a text box whose text the drawing code fits to the warp: the paragraph, in the shape's font, size and fill.
    static func wordArtContent(_ s: ArtShape) -> String? {
        guard let t = wordArtText(s) else { return nil }
        var face = "Arial"
        if let d = s.complex[0xC5], d.count >= 2 {
            var u: [UInt16] = []
            var k = 0
            while k + 1 < d.count { let c = UInt16(d[k]) | UInt16(d[k + 1]) << 8; if c == 0 { break }; u.append(c); k += 2 }
            let f = String(decoding: u, as: UTF16.self)
            if !f.isEmpty { face = f }
        }
        let pt = max(1, (s.props[0xC3] ?? 0x360000) >> 16)
        let bools = s.props[0xBF] ?? 0
        func on(_ bit: Int) -> Bool { bools >> (16 + bit) & 1 != 0 && bools >> bit & 1 != 0 }
        let color = rgb(s.props[0x181] ?? 0xFFFFFF) ?? "FFFFFF"
        let rpr = "<w:rPr><w:rFonts w:ascii=\"\(xmlEscape(face))\" w:hAnsi=\"\(xmlEscape(face))\" w:eastAsia=\"\(xmlEscape(face))\"/>\(on(1) ? "<w:b/>" : "")\(on(0) ? "<w:i/>" : "")<w:color w:val=\"\(color)\"/><w:sz w:val=\"\(pt * 2)\"/></w:rPr>"
        return "<w:p><w:pPr><w:jc w:val=\"center\"/></w:pPr><w:r>\(rpr)<w:t xml:space=\"preserve\">\(xmlEscape(t))</w:t></w:r></w:p>"
    }

    /// A freeform's path as `a:custGeom`, from the vertex and segment arrays (types of segments: line, curve, move, close, end).
    static func freeform(_ s: ArtShape) -> String? {
        guard let vd = s.complex[0x145], vd.count >= 6 else { return nil }
        let n = OfficeArt.u16(vd, 0), cb = OfficeArt.u16(vd, 4)
        let size = cb == 0xFFF0 ? 4 : cb
        guard size == 4 || size == 8, n > 1, vd.count >= 6 + n * size else { return nil }
        func i32(_ k: Int) -> Int { let v = OfficeArt.u32(vd, k); return Int(Int32(truncatingIfNeeded: v)) }
        func i16(_ k: Int) -> Int { let v = OfficeArt.u16(vd, k); return v >= 0x8000 ? v - 0x10000 : v }
        var pts: [(Int, Int)] = []
        for k in 0 ..< n {
            let o = 6 + k * size
            pts.append(size == 8 ? (i32(o), i32(o + 4)) : (i16(o), i16(o + 2)))
        }
        let gl = s.props[0x140] ?? 0, gt = s.props[0x141] ?? 0
        let gr = s.props[0x142] ?? 21600, gb = s.props[0x143] ?? 21600
        func sg(_ v: Int) -> Int { Int(Int32(truncatingIfNeeded: v)) }
        var l = sg(gl), t = sg(gt), r = sg(gr), b = sg(gb)
        if r <= l || b <= t {
            l = pts.map { $0.0 }.min() ?? 0; r = pts.map { $0.0 }.max() ?? 0
            t = pts.map { $0.1 }.min() ?? 0; b = pts.map { $0.1 }.max() ?? 0
        }
        guard r > l || b > t else { return nil }
        func pt(_ i: Int) -> String { "<a:pt x=\"\(pts[i].0 - l)\" y=\"\(pts[i].1 - t)\"/>" }
        var segs: [Int] = []
        if let sd = s.complex[0x146], sd.count >= 6 {
            let m = OfficeArt.u16(sd, 0), sz = OfficeArt.u16(sd, 4) == 0xFFF0 ? 2 : OfficeArt.u16(sd, 4)
            if sz == 2 { for k in 0 ..< min(m, (sd.count - 6) / 2) { segs.append(OfficeArt.u16(sd, 6 + 2 * k)) } }
        }
        var path = "", i = 0, open = false
        if segs.isEmpty {
            path += "<a:moveTo>\(pt(0))</a:moveTo>"
            for k in 1 ..< n { path += "<a:lnTo>\(pt(k))</a:lnTo>" }
        } else {
            loop: for v in segs {
                let kind = v >> 13 & 7, count = v & 0x1FFF
                switch kind {
                case 0: for _ in 0 ..< max(count, 1) where i < n { path += "<a:lnTo>\(pt(i))</a:lnTo>"; i += 1 }
                case 1: for _ in 0 ..< count where i + 2 < n { path += "<a:cubicBezTo>\(pt(i))\(pt(i + 1))\(pt(i + 2))</a:cubicBezTo>"; i += 3 }
                case 2: if i < n { path += "<a:moveTo>\(pt(i))</a:moveTo>"; i += 1; open = true }
                case 3: path += "<a:close/>"
                case 4: break loop
                default: break      // escapes (auto-line and the like) draw nothing
                }
            }
            _ = open
        }
        guard !path.isEmpty else { return nil }
        return "<a:custGeom><a:avLst/><a:gdLst/><a:ahLst/><a:cxnLst/><a:rect l=\"0\" t=\"0\" r=\"r\" b=\"b\"/><a:pathLst><a:path w=\"\(max(1, r - l))\" h=\"\(max(1, b - t))\">\(path)</a:path></a:pathLst></a:custGeom>"
    }

    /// The part of the picture that shows: the crop properties are fractions of the picture (16.16 fixed), top, bottom, left, right.
    static func crop(_ s: ArtShape?) -> String {
        guard let s else { return "" }
        func f(_ pid: Int) -> Int { let v = s.props[pid] ?? 0; return Int(Int32(truncatingIfNeeded: v)) * 100_000 / 65536 }
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
        let wa = wordArtPreset(s?.type ?? 0) != nil ? s.flatMap { wordArtContent($0) } : nil
        let content = content ?? wa
        let isBox = content != nil
        let ins = [(0x81, 91440), (0x82, 45720), (0x83, 91440), (0x84, 45720)].map { s?.props[$0.0] ?? $0.1 }
        let body = isBox ? "<wps:txbx><w:txbxContent>\(content!.isEmpty ? "<w:p/>" : content!)</w:txbxContent></wps:txbx>" : ""
        let sp = s ?? ArtShape()
        return ("<wps:wsp><wps:cNvSpPr\(isBox ? " txBox=\"1\"" : "")/><wps:spPr>\(xfrm)\(sp.type == 0 ? (freeform(sp) ?? "<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom>") : "<a:prstGeom prst=\"\(geometry(sp.type) ?? "rect")\"><a:avLst/></a:prstGeom>")\(wa != nil ? "<a:noFill/><a:ln><a:noFill/></a:ln>" : fillLine(sp, isBox: isBox, freeform: sp.type == 0))</wps:spPr>\(body)<wps:bodyPr \(wa != nil ? "fromWordArt=\"1\" " : "")wrap=\"square\" lIns=\"\(ins[0])\" tIns=\"\(ins[1])\" rIns=\"\(ins[2])\" bIns=\"\(ins[3])\" anchor=\"t\">\(wa != nil ? "<a:prstTxWarp prst=\"\(wordArtPreset(sp.type) ?? "textPlain")\"><a:avLst/></a:prstTxWarp>" : "")<a:noAutofit/></wps:bodyPr></wps:wsp>", false)
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
            if m.rid == nil, m.content == nil, !drawable(c) { continue }
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
