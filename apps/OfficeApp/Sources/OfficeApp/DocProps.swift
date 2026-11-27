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
            guard count > 0, 4 * (count + 1) <= 511 else { continue }
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
                    // A piece's own modifier comes after the paragraph's or character's sprms (sgc 1 paragraph, 2 character).
                    var gp = g
                    if !pc.grpprl.isEmpty {
                        for s in sprms(pc.grpprl) where (s.op >> 10 & 7) == (paragraph ? 1 : 2) {
                            let len: [UInt8] = s.op >> 13 != 6 ? [] : s.op == 0xD608 ? [UInt8((s.operand.count + 1) & 255), UInt8((s.operand.count + 1) >> 8)] : [UInt8(s.operand.count)]
                            gp += [UInt8(s.op & 255), UInt8(s.op >> 8)] + len + s.operand
                        }
                    }
                    out.append(DocPropRun(cp: pc.cp + (a - pc.fc) / width, cpEnd: pc.cp + (b - pc.fc + width - 1) / width, grpprl: gp, istd: istd))
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
    static func rPr(_ g: [UInt8], fonts: [String], toggles: Bool = false) -> String {
        var toggled = Set<Int>()   // 0x81: the opposite of what the style gives (settled per paragraph, see `settleToggles`)
        var ascii: Int?, fe: Int?, other: Int?
        var flags: [Int: Bool] = [:]
        var size: Int?, color: String?, hl = "", ul = "", va = "", rstyle = -1
        for s in sprms(g) where s.sgc == 2 {
            switch s.op {
            case 0x0835, 0x0836, 0x0837, 0x0838, 0x0839, 0x083A, 0x083B, 0x083C:
                if s.u8 == 0 { flags[s.op] = false } else if s.u8 == 1 { flags[s.op] = true }
                else if s.u8 == 0x81 { if toggles { toggled.insert(s.op) } else { flags[s.op] = true } }
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
            if toggled.contains(op) { x += "<w:\(tag) w:val=\"toggle\"/>"; return }
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

    /// Settles the toggled flags (`w:val="toggle"`) of a paragraph against the paragraph style: a toggle
    /// sprm (0x81) gives the opposite of what the style's chain gives, written out as an explicit on or off.
    static func settleToggles(_ xml: String, styles: String, istd: Int) -> String {
        guard xml.containsSubstring("w:val=\"toggle\"") else { return xml }
        var out = xml
        for tag in ["b", "i", "caps", "smallCaps", "strike", "outline", "shadow", "vanish"] {
            let marker = "<w:\(tag) w:val=\"toggle\"/>"
            guard out.containsSubstring(marker) else { continue }
            out = out.replacingAll(marker, with: styleHas(styles, istd: istd, tag: tag) ? "<w:\(tag) w:val=\"0\"/>" : "<w:\(tag)/>")
        }
        return out
    }

    private static func styleHas(_ styles: String, istd: Int, tag: String) -> Bool {
        var id = istd, hops = 0
        while hops < 20 {
            hops += 1
            guard let a = styles.rangeOfSubstring("w:styleId=\"S\(id)\"") else { return false }
            let rest = styles[a.upperBound...]
            let rs = String(rest)
            let body = rs.rangeOfSubstring("</w:style>").map { String(rs[..<$0.lowerBound]) } ?? rs
            if let r = body.rangeOfSubstring("<w:\(tag)") {
                let after = body[r.upperBound...]
                if after.hasPrefix("/>") || after.hasPrefix(" />") { return true }
                if after.hasPrefix(" w:val=\"0\"") { return false }
                if after.hasPrefix(">") || after.hasPrefix(" ") { return true }
            }
            guard let b = body.rangeOfSubstring("<w:basedOn w:val=\"S") else { return false }
            let digits = body[b.upperBound...].prefix(while: { $0 >= "0" && $0 <= "9" })
            guard let n = Int(digits), n != id else { return false }
            id = n
        }
        return false
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
        var beforeAuto: Bool?, afterAuto: Bool?
        var left: Int?, right: Int?, first: Int?, jc: String?
        var ilfo = 0, ilvl = 0
        var snapToGrid: Bool?
        for s in sprms(g) where s.sgc == 1 {
            switch s.op {
            case 0x2447: snapToGrid = s.u8 == 1   // sprmPFUsePgsuSettings: the paragraph follows the page's document grid (w:snapToGrid)
            case 0x2406: keepNext = s.u8 == 1
            case 0x2405: keepLines = s.u8 == 1
            case 0x2407: pageBreak = s.u8 == 1
            case 0x2431: widow = s.u8 == 1
            case 0x460B: ilfo = s.i16
            case 0x260A: ilvl = s.u8
            case 0x245B: beforeAuto = s.u8 == 1   // sprmPFDyaBeforeAuto: Word's 14 pt "auto" spacing
            case 0x245C: afterAuto = s.u8 == 1
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
        if ilfo > 0 { x += "<w:numPr><w:ilvl w:val=\"\(min(ilvl, 8))\"/><w:numId w:val=\"\(ilfo)\"/></w:numPr>" }
        if let snapToGrid { x += snapToGrid ? "<w:snapToGrid/>" : "<w:snapToGrid w:val=\"0\"/>" }
        if before != nil || after != nil || line != nil || beforeAuto != nil || afterAuto != nil {
            x += "<w:spacing"
            if let before { x += " w:before=\"\(before)\"" }
            if let after { x += " w:after=\"\(after)\"" }
            if let beforeAuto { x += " w:beforeAutospacing=\"\(beforeAuto ? 1 : 0)\"" }
            if let afterAuto { x += " w:afterAutospacing=\"\(afterAuto ? 1 : 0)\"" }
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

    /// A symbol character (font name, code as hex) set by the symbol sprm, or nil.
    static func symbol(_ g: [UInt8], fonts: [String]) -> (String, String)? {
        for s in sprms(g) where s.op == 0x6A09 && s.operand.count >= 4 {
            let f = s.u16, ch = OfficeArt.u16(s.operand, 2)
            guard f < fonts.count, !fonts[f].isEmpty else { return nil }
            return (attr(fonts[f]), hex(UInt8(ch >> 8)) + hex(UInt8(ch & 255)))
        }
        return nil
    }

    // MARK: tables

    /// Whether a paragraph's properties put it in a table, and whether its mark ends a row.
    static func tableFlags(_ g: [UInt8]) -> (inTable: Bool, rowEnd: Bool) {
        var a = false, r = false
        for s in sprms(g) where s.sgc == 1 {
            if s.op == 0x2416 { a = s.u8 == 1 }
            if s.op == 0x2417 { r = s.u8 == 1 }
        }
        return (a, r)
    }

    private static func brc(_ tag: String, width: Int, type: Int, ico c: Int, rgb: String? = nil) -> String {
        if type == 0 || type == 0xFF || width == 0 { return "<w:\(tag) w:val=\"nil\"/>" }
        let v = [1: "single", 2: "single", 3: "double", 5: "single", 6: "dotted", 7: "dashed", 8: "dotDash", 9: "dotDotDash",
                 10: "triple", 20: "wave", 22: "outset", 21: "inset"][type] ?? "single"
        let col = rgb ?? (c > 0 && c < ico.count ? ico[c] : "auto")
        return "<w:\(tag) w:val=\"\(v)\" w:sz=\"\(max(2, min(96, width)))\" w:space=\"0\" w:color=\"\(col)\"/>"
    }

    private static func shade(_ v: Int) -> String {
        let fore = v & 31, back = v >> 5 & 31, pat = v >> 10 & 63
        let c = pat == 1 ? fore : back
        return c > 0 && c < ico.count ? ico[c] : ""
    }

    /// The table properties, column widths, row properties and per-cell properties of the row a TAP sprm list describes.
    /// `union`: the table's column edges when its rows do not share them (every row's edges, snapped); the row then
    /// states its cells against that one grid, as Word's own table grid does, so a row of two cells under a four-column
    /// table spans columns instead of taking the first two.
    static func row(_ g: [UInt8], union: [Int]? = nil) -> (tblPr: String, grid: [Int], trPr: String, cells: [(span: Int, merged: Bool, pr: String)], edges: [Int])? {
        var edges: [Int] = [], tcs: [[UInt8]] = []
        var jc = "", gap = 108, shd: [Int] = [], height = 0
        var tb: [String] = [], header = false, cant = false
        let names = ["top", "left", "bottom", "right", "insideH", "insideV"]
        for s in sprms(g) where s.sgc == 5 {
            switch s.op {
            case 0xD608:
                let o = s.operand
                guard o.count >= 3 else { break }
                let n = Int(o[0])
                guard o.count >= 1 + 2 * (n + 1) else { break }
                edges = (0 ... n).map { let v = OfficeArt.u16(o, 1 + 2 * $0); return v >= 0x8000 ? v - 0x10000 : v }
                tcs = (0 ..< n).map { k in
                    let a = 1 + 2 * (n + 1) + 20 * k
                    return a + 20 <= o.count ? Array(o[a ..< a + 20]) : []
                }
            case 0x5400: jc = ["left", "center", "right"][min(s.u16 & 0xFF, 2)]
            case 0x9602: gap = s.i16
            case 0x9407: height = s.i16
            case 0x3404: header = s.u8 != 0
            case 0x3403: cant = s.u8 != 0
            case 0xD609: shd = stride(from: 0, to: s.operand.count - 1, by: 2).map { OfficeArt.u16(s.operand, $0) }
            case 0xD613:
                let o = s.operand
                tb = (0 ..< 6).map { k in
                    let a = 8 * k
                    guard a + 8 <= o.count else { return "" }
                    let rgb = o[a + 3] == 0xFF ? nil : hex(o[a]) + hex(o[a + 1]) + hex(o[a + 2])
                    return brc(names[k], width: Int(o[a + 4]), type: Int(o[a + 5]), ico: 0, rgb: rgb)
                }
            case 0xD605 where tb.isEmpty:
                let o = s.operand
                tb = (0 ..< 6).map { k in
                    let a = 4 * k
                    guard a + 4 <= o.count else { return "" }
                    return brc(names[k], width: Int(o[a]), type: Int(o[a + 1]), ico: Int(o[a + 2]) & 31)
                }
            default: break
            }
        }
        guard edges.count >= 2 else { return nil }
        let n = edges.count - 1
        let ownGrid = (0 ..< n).map { max(0, edges[$0 + 1] - edges[$0]) }
        let grid = union.map { u in (0 ..< u.count - 1).map { max(0, u[$0 + 1] - u[$0]) } } ?? ownGrid
        func ui(_ e: Int) -> Int { union.map { u in u.indices.min(by: { abs(u[$0] - e) < abs(u[$1] - e) }) ?? 0 } ?? 0 }
        var tblPr = "<w:tblPr><w:tblW w:w=\"\((union?.last ?? edges[n]) - edges[0])\" w:type=\"dxa\"/>"
        if !jc.isEmpty { tblPr += "<w:jc w:val=\"\(jc)\"/>" }
        tblPr += "<w:tblInd w:w=\"\(edges[0] + gap)\" w:type=\"dxa\"/>"
        let real = tb.filter { !$0.isEmpty }
        if !real.isEmpty { tblPr += "<w:tblBorders>" + real.joined() + "</w:tblBorders>" }
        tblPr += "<w:tblLayout w:type=\"fixed\"/><w:tblCellMar><w:left w:w=\"\(gap)\" w:type=\"dxa\"/><w:right w:w=\"\(gap)\" w:type=\"dxa\"/></w:tblCellMar></w:tblPr>"
        var trPr = ""
        if cant { trPr += "<w:cantSplit/>" }
        if height != 0 { trPr += height < 0 ? "<w:trHeight w:val=\"\(-height)\" w:hRule=\"exact\"/>" : "<w:trHeight w:val=\"\(height)\" w:hRule=\"atLeast\"/>" }
        if header { trPr += "<w:tblHeader/>" }
        var cells: [(span: Int, merged: Bool, pr: String)] = []
        var k = 0
        while k < n {
            let tc = k < tcs.count ? tcs[k] : []
            let flags = tc.count >= 2 ? OfficeArt.u16(tc, 0) : 0
            let hm = flags & 3, vm = flags >> 5 & 3, va = flags >> 7 & 3
            if hm == 2 { cells.append((0, true, "")); k += 1; continue }
            var span = 1, w = ownGrid[k]
            if hm == 1 { while k + span < n, k + span < tcs.count, tcs[k + span].count >= 2, OfficeArt.u16(tcs[k + span], 0) & 3 == 2 { w += ownGrid[k + span]; span += 1 } }
            var uspan = span
            if let u = union { let lo = ui(edges[k]), hi = ui(edges[k + span]); uspan = max(1, hi - lo); w = max(0, u[hi] - u[lo]) }
            var pr = "<w:tcPr><w:tcW w:w=\"\(w)\" w:type=\"dxa\"/>"
            if uspan > 1 { pr += "<w:gridSpan w:val=\"\(uspan)\"/>" }
            if vm == 1 { pr += "<w:vMerge/>" } else if vm == 2 { pr += "<w:vMerge w:val=\"restart\"/>" }
            if tc.count >= 20 {
                let b = [("top", 4), ("left", 8), ("bottom", 12), ("right", 16)].map { brc($0.0, width: Int(tc[$0.1]), type: Int(tc[$0.1 + 1]), ico: Int(tc[$0.1 + 2]) & 31) }
                let some = b.filter { !$0.contains("w:val=\"nil\"") }
                if !some.isEmpty { pr += "<w:tcBorders>" + some.joined() + "</w:tcBorders>" }
            }
            if k < shd.count { let f = shade(shd[k]); if !f.isEmpty { pr += "<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"\(f)\"/>" } }
            if va > 0 { pr += "<w:vAlign w:val=\"\(va == 1 ? "center" : "bottom")\"/>" }
            pr += "</w:tcPr>"
            cells.append((uspan, false, pr))
            k += span
        }
        return (tblPr, grid, trPr.isEmpty ? "" : "<w:trPr>" + trPr + "</w:trPr>", cells, edges)
    }

    // MARK: lists

    /// numbering.xml from the list tables (PlfLst: the list definitions; PlfLfo: the numbers paragraphs refer to).
    static func numbering(_ t: [UInt8], lst: (fc: Int, lcb: Int), lfo: (fc: Int, lcb: Int)?, fonts: [String]) -> String? {
        let end = lst.fc + lst.lcb
        guard lst.fc >= 0, end <= t.count, lst.lcb >= 2 else { return nil }
        let cLst = OfficeArt.u16(t, lst.fc)
        var p = lst.fc + 2
        var lsids: [Int] = [], simple: [Bool] = []
        for _ in 0 ..< cLst {
            guard p + 28 <= end else { return nil }
            lsids.append(OfficeArt.u32(t, p)); simple.append(t[p + 26] & 1 != 0)
            p += 28
        }
        let fmts: [Int: String] = [0: "decimal", 1: "upperRoman", 2: "lowerRoman", 3: "upperLetter", 4: "lowerLetter", 5: "ordinal",
                                   22: "decimalZero", 23: "bullet", 255: "none"]
        var abs = ""
        for li in 0 ..< cLst {
            abs += "<w:abstractNum w:abstractNumId=\"\(li)\"><w:multiLevelType w:val=\"\(simple[li] ? "singleLevel" : "multilevel")\"/>"
            for lv in 0 ..< (simple[li] ? 1 : 9) {
                guard p + 28 <= end else { break }
                let start = OfficeArt.u32(t, p), nfc = Int(t[p + 4]), fl = Int(t[p + 5])
                let nums = Array(t[p + 6 ..< p + 15]), follow = Int(t[p + 15])
                let cbC = Int(t[p + 24]), cbP = Int(t[p + 25])
                p += 28
                guard p + cbP + cbC + 2 <= end else { break }
                let pap = Array(t[p ..< p + cbP]), chp = Array(t[p + cbP ..< p + cbP + cbC])
                p += cbP + cbC
                let cch = OfficeArt.u16(t, p); p += 2
                guard p + 2 * cch <= end else { break }
                var text = ""
                for k in 0 ..< cch {
                    let c = OfficeArt.u16(t, p + 2 * k)
                    if c < 9 { text += "%\(c + 1)" } else if let u = Unicode.Scalar(c) { text += attr(String(Character(u))) }
                }
                p += 2 * cch
                var rp = rPr(chp, fonts: fonts)
                if nfc == 23, rp.isEmpty { rp = "" }
                let ppr = pPr(pap)
                abs += "<w:lvl w:ilvl=\"\(lv)\"><w:start w:val=\"\(start)\"/><w:numFmt w:val=\"\(fmts[nfc] ?? "decimal")\"/>"
                if fl & 4 != 0 { abs += "<w:isLgl/>" }
                abs += "<w:suff w:val=\"\(follow == 1 ? "space" : follow == 2 ? "nothing" : "tab")\"/>"
                abs += "<w:lvlText w:val=\"\(text)\"/><w:lvlJc w:val=\"\(["left", "center", "right"][min(fl & 3, 2)])\"/>"
                abs += ppr + rp + "</w:lvl>"
                _ = nums
            }
            abs += "</w:abstractNum>"
        }
        var nums = ""
        if let lfo, lfo.fc + 4 <= t.count {
            let n = OfficeArt.u32(t, lfo.fc)
            for k in 0 ..< n {
                let a = lfo.fc + 4 + 16 * k
                guard a + 16 <= t.count else { break }
                let id = OfficeArt.u32(t, a)
                let idx = lsids.firstIndex(of: id) ?? 0
                nums += "<w:num w:numId=\"\(k + 1)\"><w:abstractNumId w:val=\"\(idx)\"/></w:num>"
            }
        }
        return abs.isEmpty || nums.isEmpty ? nil : abs + nums
    }

    /// The styles of the STSH as `w:style` elements, and the document's default font number.
    static func styles(_ t: [UInt8], at fc: Int, count lcb: Int, fonts: [String]) -> (xml: String, font: Int, fontFE: Int) {
        guard fc >= 0, fc + lcb <= t.count, lcb >= 4 else { return ("", 0, 0) }
        let end = fc + lcb
        let cbStshi = OfficeArt.u16(t, fc)
        let h = fc + 2
        let cstd = OfficeArt.u16(t, h), cbBase = OfficeArt.u16(t, h + 2)
        let font = cbStshi >= 14 ? OfficeArt.u16(t, h + 12) : 0
        // (The East Asian default is the next of the three standard fonts, ftcFE: the face a run that names none gives its Hangul, kana and ideographs.)
        let fontFE = cbStshi >= 16 ? OfficeArt.u16(t, h + 14) : font
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
        return (xml, font, fontFE)
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
        var gridType = 0, gridPitch = 0, gridChar = 0
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
            case 0x5032: gridType = s.u16
            case 0x9031: gridPitch = s.u16
            case 0x7030: gridChar = Int(Int32(truncatingIfNeeded: OfficeArt.u32(s.operand, 0)))  // signed: a negative pitch is stored as 32-bit two's complement
            default: break
            }
        }
        var x = refs
        x += "<w:type w:val=\"" + ["continuous", "nextColumn", "nextPage", "evenPage", "oddPage"][min(bkc, 4)] + "\"/>"
        x += "<w:pgSz w:w=\"\(w)\" w:h=\"\(h)\"" + (landscape ? " w:orient=\"landscape\"" : "") + "/>"
        x += "<w:pgMar w:top=\"\(tp)\" w:right=\"\(r)\" w:bottom=\"\(bt)\" w:left=\"\(l)\" w:header=\"\(hd)\" w:footer=\"\(ft)\" w:gutter=\"\(gut)\"/>"
        if cols > 1 { x += "<w:cols w:num=\"\(cols)\" w:space=\"\(space)\"/>" }
        if title { x += "<w:titlePg/>" }
        if gridType > 0, gridPitch > 0 {
            let ty = gridType == 1 ? "linesAndChars" : gridType == 3 ? "snapToChars" : "lines"   // sprmSClm: 1 chars and lines, 2 lines, 3 snap to chars
            x += "<w:docGrid w:type=\"\(ty)\" w:linePitch=\"\(gridPitch)\"" + (gridChar != 0 ? " w:charSpace=\"\(gridChar)\"" : "") + "/>"
        }
        return "<w:sectPr>" + x + "</w:sectPr>"
    }
}
