// Word 97-2003 .doc: character and paragraph properties (M1). The CHPX and PAPX
// FKPs hold property lists ("grpprl": a run of sprms) for stretches of the
// WordDocument stream; they are mapped to character positions through the
// piece table and written out as w:rPr / w:pPr.
//
// Shared code (also built for the web): no legacy Foundation calls.

import Foundation

/// A property list applying to the characters [cp, cpEnd).
struct DocPropRun {
    var cp: Int
    var cpEnd: Int
    var grpprl: [UInt8]
    var istd = 0
}

struct DocSprm {
    var op: Int
    var operand: [UInt8]
    var sgc: Int { op >> 10 & 7 }          // 1 paragraph, 2 character, 3 picture, 4 section, 5 table
    var u8: Int { operand.first.map { Int($0) } ?? 0 }
    var u16: Int { OfficeArt.u16(operand, 0) }
    var i16: Int { let v = u16; return v >= 0x8000 ? v - 0x10000 : v }
}

enum DocProps {
    /// The sprms of a property list.
    static func sprms(_ g: [UInt8]) -> [DocSprm] {
        var out: [DocSprm] = []
        var p = 0
        while p + 2 <= g.count {
            let op = OfficeArt.u16(g, p)
            p += 2
            var n: Int
            switch op >> 13 {
            case 0, 1: n = 1
            case 2, 4, 5: n = 2
            case 3: n = 4
            case 7: n = 3
            default:
                if op == 0xD608 { n = OfficeArt.u16(g, p) - 1; p += 2 } else { n = p < g.count ? Int(g[p]) : 0; p += 1 }
            }
            n = max(0, n)
            guard p + n <= g.count else { break }
            out.append(DocSprm(op: op, operand: Array(g[p ..< p + n])))
            p += n
        }
        return out
    }

    /// The font names of the SttbfFfn (index = the font numbers the sprms use).
    static func fonts(_ t: [UInt8], at fc: Int, count lcb: Int) -> [String] {
        guard fc >= 0, fc + lcb <= t.count, lcb >= 2 else { return [] }
        var out: [String] = []
        var p = fc + 4              // cData and cbExtra (2 bytes each) come first
        let end = fc + lcb
        while p < end {
            let cb = Int(t[p])
            guard cb >= 40, p + 1 + cb <= end else { out.append(""); p += 1 + cb; continue }
            var u: [UInt16] = []
            var k = p + 40
            while k + 2 <= p + 1 + cb {
                let c = UInt16(t[k]) | UInt16(t[k + 1]) << 8
                if c == 0 { break }
                u.append(c)
                k += 2
            }
            out.append(String(decoding: u, as: UTF16.self))
            p += 1 + cb
        }
        return out
    }

    /// The property runs of a PlcfBte (CHPX when `paragraph` is false, PAPX when true), as character positions.
    static func runs(w: [UInt8], t: [UInt8], at fc: Int, count lcb: Int, pieces: [DocPiece], paragraph: Bool) -> [DocPropRun] {
        guard fc >= 0, fc + lcb <= t.count, lcb >= 12 else { return [] }
        let n = (lcb - 4) / 8
        var out: [DocPropRun] = []
        for k in 0 ..< n {
            let page = (OfficeArt.u32(t, fc + 4 * (n + 1) + 4 * k) & 0x3F_FFFF) * 512
            guard page + 512 <= w.count else { continue }
            let count = Int(w[page + 511])
            guard count > 0, page + 4 * (count + 1) <= 511 else { continue }
            for i in 0 ..< count {
                let f0 = OfficeArt.u32(w, page + 4 * i), f1 = OfficeArt.u32(w, page + 4 * (i + 1))
                var g: [UInt8] = []
                var istd = 0
                if paragraph {
                    let off = Int(w[page + 4 * (count + 1) + 13 * i]) * 2
                    guard off > 0, off < 511 else { continue }
                    var len = Int(w[page + off])
                    var s = page + off + 1
                    if len == 0 { len = 2 * Int(w[s]); s += 1 } else { len = 2 * len - 1 }
                    guard len >= 2, s + len <= page + 512 else { continue }
                    // the style index (2 bytes) first, then the sprms.
                    g = Array(w[s + 2 ..< s + len]); istd = OfficeArt.u16(w, s)
                } else {
                    let off = Int(w[page + 4 * (count + 1) + i]) * 2
                    guard off > 0, off < 511 else { continue }
                    let len = Int(w[page + off])
                    guard len > 0, page + off + 1 + len <= page + 512 else { continue }
                    g = Array(w[page + off + 1 ..< page + off + 1 + len])
                }
                for pc in pieces {
                    let width = pc.compressed ? 1 : 2
                    let a = max(f0, pc.fc), b = min(f1, pc.fc + (pc.cpEnd - pc.cp) * width)
                    guard b > a else { continue }
                    out.append(DocPropRun(cp: pc.cp + (a - pc.fc) / width, cpEnd: pc.cp + (b - pc.fc + width - 1) / width, grpprl: g, istd: istd))
                }
            }
        }
        return out.sorted { $0.cp < $1.cp }
    }

    private static let ico = ["", "000000", "0000FF", "00FFFF", "00FF00", "FF00FF", "FF0000", "FFFF00", "FFFFFF",
                              "000080", "008080", "008000", "800080", "800000", "808000", "808080", "C0C0C0"]
    private static let highlight = ["", "black", "blue", "cyan", "green", "magenta", "red", "yellow", "white",
                                    "darkBlue", "darkCyan", "darkGreen", "darkMagenta", "darkRed", "darkYellow", "darkGray", "lightGray"]
    private static let underline: [Int: String] = [1: "single", 2: "words", 3: "double", 4: "dotted", 6: "thick", 7: "dash", 8: "dotDash",
                                                   9: "dotDotDash", 10: "wave", 11: "dottedHeavy", 12: "dashedHeavy", 13: "dashDotHeavy",
                                                   14: "dashDotDotHeavy", 15: "wavyHeavy", 16: "dashLong", 17: "wavyDouble", 18: "dashLongHeavy"]

    private static func attr(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "<", with: "&lt;")
    }

    /// `<w:rPr>` for a character property list ("" when it sets nothing).
    static func rPr(_ g: [UInt8], fonts: [String]) -> String {
        var ascii: Int?, fe: Int?, other: Int?
        var flags: [Int: Bool] = [:]
        var size: Int?, color: String?, hl = "", ul = "", va = "", rstyle = -1
        for s in sprms(g) where s.sgc == 2 {
            switch s.op {
            case 0x0835, 0x0836, 0x0837, 0x0838, 0x0839, 0x083A, 0x083B, 0x083C:
                if s.u8 == 0 { flags[s.op] = false } else if s.u8 == 1 || s.u8 == 0x81 { flags[s.op] = true }
            case 0x2A3E: ul = underline[s.u8] ?? (s.u8 == 0 ? "none" : "single")
            case 0x2A42: if s.u8 > 0, s.u8 < ico.count { color = ico[s.u8] }
            case 0x6870: if s.operand.count >= 3 { color = hex(s.operand[0]) + hex(s.operand[1]) + hex(s.operand[2]) }
            case 0x4A43: size = s.u16
            case 0x2A0C: if s.u8 > 0, s.u8 < highlight.count { hl = highlight[s.u8] }
            case 0x2A48: va = s.u8 == 1 ? "superscript" : s.u8 == 2 ? "subscript" : "baseline"
            case 0x4A30: rstyle = s.u16
            case 0x4A4F: ascii = s.u16
            case 0x4A50: fe = s.u16
            case 0x4A51: other = s.u16
            default: break
            }
        }
        func name(_ i: Int?) -> String? { i.flatMap { $0 < fonts.count && !fonts[$0].isEmpty ? attr(fonts[$0]) : nil } }
        var x = rstyle > 0 ? "<w:rStyle w:val=\"S\(rstyle)\"/>" : ""
        let a = name(ascii), f = name(fe), o = name(other)
        if a != nil || f != nil || o != nil {
            x += "<w:rFonts"
            if let a { x += " w:ascii=\"\(a)\"" }
            if let h = o ?? a { x += " w:hAnsi=\"\(h)\"" }
            if let f { x += " w:eastAsia=\"\(f)\"" }
            if let c = o ?? a { x += " w:cs=\"\(c)\"" }
            x += "/>"
        }
        func on(_ op: Int, _ tag: String) {
            if let v = flags[op] { x += v ? "<w:\(tag)/>" : "<w:\(tag) w:val=\"0\"/>" }
        }
        on(0x0835, "b"); if let v = flags[0x0835] { x += v ? "<w:bCs/>" : "" }
        on(0x0836, "i"); if flags[0x0836] == true { x += "<w:iCs/>" }
        on(0x083B, "caps"); on(0x083A, "smallCaps"); on(0x0837, "strike"); on(0x0838, "outline"); on(0x0839, "shadow"); on(0x083C, "vanish")
        if let color { x += "<w:color w:val=\"\(color)\"/>" }
        if let size, size > 0 { x += "<w:sz w:val=\"\(size)\"/><w:szCs w:val=\"\(size)\"/>" }
        if !hl.isEmpty { x += "<w:highlight w:val=\"\(hl)\"/>" }
        if !ul.isEmpty { x += "<w:u w:val=\"\(ul)\"/>" }
        if !va.isEmpty { x += "<w:vertAlign w:val=\"\(va)\"/>" }
        return x.isEmpty ? "" : "<w:rPr>" + x + "</w:rPr>"
    }

    private static func hex(_ b: UInt8) -> String {
        let d = Array("0123456789ABCDEF")
        return String([d[Int(b >> 4)], d[Int(b & 15)]])
    }

    /// `<w:pPr>` for a paragraph property list ("" when it sets nothing).
    static func pPr(_ g: [UInt8], istd: Int = 0) -> String {
        var x = istd > 0 ? "<w:pStyle w:val=\"S\(istd)\"/>" : ""
        var keepNext = false, keepLines = false, pageBreak = false, widow: Bool?
        var before: Int?, after: Int?, line: (Int, Int)?
        var left: Int?, right: Int?, first: Int?, jc: String?
        for s in sprms(g) where s.sgc == 1 {
            switch s.op {
            case 0x2406: keepNext = s.u8 == 1
            case 0x2405: keepLines = s.u8 == 1
            case 0x2407: pageBreak = s.u8 == 1
            case 0x2431: widow = s.u8 == 1
            case 0xA413: before = s.u16
            case 0xA414: after = s.u16
            case 0x6412: if s.operand.count >= 4 { line = (OfficeArt.u16(s.operand, 0), OfficeArt.u16(s.operand, 2)) }
            case 0x840F, 0x845E: left = s.i16
            case 0x840E, 0x845D: right = s.i16
            case 0x8411, 0x8460: first = s.i16
            case 0x2461, 0x2403: jc = ["left", "center", "right", "both", "distribute"][min(s.u8, 4)]
            default: break
            }
        }
        if keepNext { x += "<w:keepNext/>" }
        if keepLines { x += "<w:keepLines/>" }
        if pageBreak { x += "<w:pageBreakBefore/>" }
        if let widow { x += widow ? "<w:widowControl/>" : "<w:widowControl w:val=\"0\"/>" }
        if before != nil || after != nil || line != nil {
            x += "<w:spacing"
            if let before { x += " w:before=\"\(before)\"" }
            if let after { x += " w:after=\"\(after)\"" }
            if let (l, m) = line {
                let v = l >= 0x8000 ? l - 0x10000 : l
                x += m == 1 ? " w:line=\"\(v)\" w:lineRule=\"auto\"" : v < 0 ? " w:line=\"\(-v)\" w:lineRule=\"exact\"" : " w:line=\"\(v)\" w:lineRule=\"atLeast\""
            }
            x += "/>"
        }
        if left != nil || right != nil || first != nil {
            x += "<w:ind"
            if let left { x += " w:left=\"\(left)\"" }
            if let right { x += " w:right=\"\(right)\"" }
            if let first { x += first < 0 ? " w:hanging=\"\(-first)\"" : " w:firstLine=\"\(first)\"" }
            x += "/>"
        }
        if let jc { x += "<w:jc w:val=\"\(jc)\"/>" }
        return x.isEmpty ? "" : "<w:pPr>" + x + "</w:pPr>"
    }

    /// The styles of the STSH as `w:style` elements, and the document's default font number.
    static func styles(_ t: [UInt8], at fc: Int, count lcb: Int, fonts: [String]) -> (xml: String, font: Int) {
        guard fc >= 0, fc + lcb <= t.count, lcb >= 4 else { return ("", 0) }
        let end = fc + lcb
        let cbStshi = OfficeArt.u16(t, fc)
        let h = fc + 2
        let cstd = OfficeArt.u16(t, h), cbBase = OfficeArt.u16(t, h + 2)
        let font = cbStshi >= 14 ? OfficeArt.u16(t, h + 12) : 0
        var p = h + cbStshi
        var xml = ""
        for istd in 0 ..< cstd {
            guard p + 2 <= end else { break }
            let cb = OfficeArt.u16(t, p)
            let at = p + 2
            p = at + cb + (cb & 1)
            guard cb >= cbBase, cbBase >= 10, at + cb <= end else { continue }
            let w1 = OfficeArt.u16(t, at + 2), w2 = OfficeArt.u16(t, at + 4)
            let stk = w1 & 15, base = w1 >> 4, cupx = w2 & 15, next = w2 >> 4
            guard stk == 1 || stk == 2 else { continue }
            var k = at + cbBase
            let cch = OfficeArt.u16(t, k)
            var u: [UInt16] = []
            for i in 0 ..< cch where k + 2 + 2 * i + 2 <= at + cb { u.append(UInt16(t[k + 2 + 2 * i]) | UInt16(t[k + 3 + 2 * i]) << 8) }
            k += 2 + 2 * cch + 2
            k += k & 1 == (at & 1) ? 0 : 1
            var upx: [[UInt8]] = []
            for _ in 0 ..< cupx {
                guard k + 2 <= at + cb else { break }
                let n = OfficeArt.u16(t, k)
                guard k + 2 + n <= at + cb else { break }
                upx.append(Array(t[k + 2 ..< k + 2 + n]))
                k += 2 + n + (n & 1)
            }
            var pp = "", rp = ""
            if stk == 1 {
                if upx.count > 0, upx[0].count > 2 { pp = pPr(Array(upx[0][2...])) }
                if upx.count > 1 { rp = rPr(upx[1], fonts: fonts) }
            } else if let c = upx.first { rp = rPr(c, fonts: fonts) }
            let name = attr(String(decoding: u, as: UTF16.self))
            xml += "<w:style w:type=\"\(stk == 1 ? "paragraph" : "character")\" w:styleId=\"S\(istd)\"\(istd == 0 ? " w:default=\"1\"" : "")><w:name w:val=\"\(name)\"/>"
            if base != 0xFFF, base != istd, base < cstd { xml += "<w:basedOn w:val=\"S\(base)\"/>" }
            if stk == 1, next != istd, next < cstd { xml += "<w:next w:val=\"S\(next)\"/>" }
            xml += pp + rp + "</w:style>"
        }
        return (xml, font)
    }

    /// The character positions and the n entries of a plex (n + 1 positions, then n entries of `size` bytes).
    static func plex(_ t: [UInt8], at fc: Int, count lcb: Int, size: Int) -> (cps: [Int], at: Int)? {
        guard fc >= 0, fc + lcb <= t.count, lcb >= 4 else { return nil }
        let n = (lcb - 4) / (4 + size)
        return ((0 ... n).map { OfficeArt.u32(t, fc + 4 * $0) }, fc + 4 * (n + 1))
    }

    /// `w:sectPr` for a section's property list (`refs` = its header and footer references).
    static func sectPr(_ g: [UInt8], refs: String) -> String {
        var w = 12240, h = 15840, l = 1800, r = 1800, tp = 1440, bt = 1440, hd = 720, ft = 720, gut = 0
        var landscape = false, title = false, cols = 1, space = 720, bkc = 2
        for s in sprms(g) where s.sgc == 4 {
            switch s.op {
            case 0xB01F: w = s.u16
            case 0xB020: h = s.u16
            case 0xB021: l = s.u16
            case 0xB022: r = s.u16
            case 0x9023: tp = s.i16
            case 0x9024: bt = s.i16
            case 0xB025: gut = s.u16
            case 0xB017: hd = s.u16
            case 0xB018: ft = s.u16
            case 0x301D: landscape = s.u8 == 2
            case 0x300A: title = s.u8 == 1
            case 0x500B: cols = s.u16 + 1
            case 0x900C: space = s.u16
            case 0x3009: bkc = s.u8
            default: break
            }
        }
        var x = refs
        x += "<w:type w:val=\"" + ["continuous", "nextColumn", "nextPage", "evenPage", "oddPage"][min(bkc, 4)] + "\"/>"
        x += "<w:pgSz w:w=\"\(w)\" w:h=\"\(h)\"" + (landscape ? " w:orient=\"landscape\"" : "") + "/>"
        x += "<w:pgMar w:top=\"\(tp)\" w:right=\"\(r)\" w:bottom=\"\(bt)\" w:left=\"\(l)\" w:header=\"\(hd)\" w:footer=\"\(ft)\" w:gutter=\"\(gut)\"/>"
        if cols > 1 { x += "<w:cols w:num=\"\(cols)\" w:space=\"\(space)\"/>" }
        if title { x += "<w:titlePg/>" }
        return "<w:sectPr>" + x + "</w:sectPr>"
    }
}
