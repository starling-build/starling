// A .ppt text block as DrawingML paragraphs: the paragraph and character runs of its StyleTextPropAtom
// split where they cross, and only the fields a mask names written out (the rest inherits).
//
// Shared code (also built for the web): bounds-checked, never traps.

import Foundation

extension PptFile {
    private static let schemeNames = ["bg1", "tx1", "bg2", "tx2", "accent1", "accent2", "hlink", "folHlink"]

    private static func escape(_ t: String) -> String {
        var o = ""
        for ch in t { switch ch { case "&": o += "&amp;"; case "<": o += "&lt;"; case ">": o += "&gt;"; case "\"": o += "&quot;"; default: o.append(ch) } }
        return o
    }

    private static func fill(_ c: PptColorRef) -> String {
        if let s = c.scheme { return "<a:solidFill><a:schemeClr val=\"\(schemeNames[s])\"/></a:solidFill>" }
        let d = Array("0123456789ABCDEF")
        return "<a:solidFill><a:srgbClr val=\"\(String((0 ..< 6).map { d[c.rgb >> (20 - 4 * $0) & 15] }))\"/></a:solidFill>"
    }

    private func face(_ i: Int?) -> String? {
        guard let i, i >= 0, i < fonts.count, !fonts[i].isEmpty else { return nil }
        return Self.escape(fonts[i])
    }

    /// `a:pPr` for a paragraph run (empty when it states nothing).
    func paragraphProps(_ p: PptParaRun, tag: String = "a:pPr", defaults: String = "") -> String {
        var attrs = ""
        if p.level > 0 { attrs += " lvl=\"\(min(p.level, 8))\"" }
        if let l = p.leftMargin { attrs += " marL=\"\(PptBuild.emu(l))\"" }
        if let i = p.indent { attrs += " indent=\"\(PptBuild.emu(i - (p.leftMargin ?? 0)))\"" }
        if let a = p.align, a < 7 { attrs += " algn=\"\(["l", "ctr", "r", "just", "dist", "thaiDist", "justLow"][a])\"" }
        if let t = p.defaultTab { attrs += " defTabSz=\"\(PptBuild.emu(t))\"" }
        if let f = p.fontAlign, f < 4 { attrs += " fontAlgn=\"\(["base", "t", "ctr", "b"][f])\"" }
        if p.textDirection == 1 { attrs += " rtl=\"1\"" }
        func spacing(_ v: Int) -> String {
            v >= 0 ? "<a:spcPct val=\"\(v * 1000)\"/>" : "<a:spcPts val=\"\(-v * 25 / 2)\"/>"
        }
        var kids = ""
        if let v = p.lineSpacing { kids += "<a:lnSpc>\(spacing(v))</a:lnSpc>" }
        if let v = p.spaceBefore { kids += "<a:spcBef>\(spacing(v))</a:spcBef>" }
        if let v = p.spaceAfter { kids += "<a:spcAft>\(spacing(v))</a:spcAft>" }
        if let c = p.bulletColor { kids += "<a:buClr>\(Self.fill(c).dropFirst(13).dropLast(14))</a:buClr>" }
        if let s = p.bulletSize { kids += s >= 0 ? "<a:buSzPct val=\"\(s * 1000)\"/>" : "<a:buSzPts val=\"\(-s * 100)\"/>" }
        if let f = face(p.bulletFont) { kids += "<a:buFont typeface=\"\(f)\"/>" }
        if p.hasBullet == false { kids += "<a:buNone/>" }
        else if let ch = p.bulletChar, p.hasBullet == true {
            kids += "<a:buChar char=\"\(Self.escape(String(decoding: [UInt16(ch)], as: UTF16.self)))\"/>"
        }
        if let tabs = p.tabs {
            kids += "<a:tabLst>" + tabs.map { "<a:tab pos=\"\(PptBuild.emu($0.position))\" algn=\"\(["l", "ctr", "r", "dec"][min($0.type, 3)])\"/>" }.joined() + "</a:tabLst>"
        }
        kids += defaults
        return attrs.isEmpty && kids.isEmpty ? "" : (kids.isEmpty ? "<\(tag)\(attrs)/>" : "<\(tag)\(attrs)>\(kids)</\(tag)>")
    }

    /// `a:rPr` for a character run (empty when it states nothing).
    func runProps(_ c: PptCharRun, tag: String = "a:rPr") -> String {
        var attrs = ""
        if let s = c.size { attrs += " sz=\"\(s * 100)\"" }
        if let v = c.bold { attrs += " b=\"\(v ? 1 : 0)\"" }
        if let v = c.italic { attrs += " i=\"\(v ? 1 : 0)\"" }
        if let v = c.underline { attrs += " u=\"\(v ? "sng" : "none")\"" }
        if let v = c.position { attrs += " baseline=\"\(v * 1000)\"" }
        // A .ppt kerns from 12 pt (the old versions' fixed rule; .ppt has no kern setting), and PowerPoint's own
        // conversion says so on every style level: without it a deck's default text style would switch kerning off.
        if tag == "a:defRPr" { attrs += " kern=\"1200\"" }
        var kids = ""
        if let col = c.color { kids += Self.fill(col) }
        if let f = face(c.font) { kids += "<a:latin typeface=\"\(f)\"/>" }
        if let f = face(c.eastAsianFont) { kids += "<a:ea typeface=\"\(f)\"/>" }
        // (A .ppt run has no complex-script face of its own: PowerPoint sets its Thai in the run's font, not the theme's `cs`
        // face (th-e7813af3d5 prints its Thai in Tahoma, where its theme names Angsana New).)
        if let f = face(c.font) { kids += "<a:cs typeface=\"\(f)\"/>" }
        if let f = face(c.symbolFont) { kids += "<a:sym typeface=\"\(f)\"/>" }
        return attrs.isEmpty && kids.isEmpty ? "" : (kids.isEmpty ? "<\(tag)\(attrs)/>" : "<\(tag)\(attrs)>\(kids)</\(tag)>")
    }

    /// The `a:p` elements of a block.
    func paragraphsXML(_ block: PptTextBlock?) -> String {
        guard let block else { return "<a:p/>" }
        let units = Array(block.text.utf16)
        // Run boundaries: the start offset of each run, in text units.
        func starts<T>(_ runs: [T], _ count: (T) -> Int) -> [Int] {
            var out: [Int] = [], at = 0
            for r in runs { out.append(at); at += max(count(r), 0) }
            return out
        }
        let pStart = starts(block.paraRuns) { $0.count }, cStart = starts(block.charRuns) { $0.count }
        func paraRun(at k: Int) -> PptParaRun? {
            var run: PptParaRun? = nil
            if let i = pStart.lastIndex(where: { $0 <= k }), k < pStart[i] + block.paraRuns[i].count { run = block.paraRuns[i] }
            // The shape's ruler sets the margin and indent of a level its own runs leave open.
            if let r = block.ruler[run?.level ?? 0], r.left != nil || r.indent != nil {
                var p = run ?? PptParaRun()
                if p.leftMargin == nil { p.leftMargin = r.left }
                return p
            }
            return run
        }
        func charRun(at k: Int) -> (PptCharRun, Int)? {
            guard let i = cStart.lastIndex(where: { $0 <= k }), k < cStart[i] + block.charRuns[i].count else { return nil }
            return (block.charRuns[i], cStart[i] + block.charRuns[i].count)
        }
        var out = ""
        var ps = 0
        while ps <= units.count {
            var pe = ps
            while pe < units.count, units[pe] != 0x0D { pe += 1 }
            out += "<a:p>" + (paraRun(at: ps).map { paragraphProps($0) } ?? "")
            var k = ps
            while k < pe {
                if units[k] == 0x0B {
                    let props = charRun(at: k).map { runProps($0.0) } ?? ""
                    out += props.isEmpty ? "<a:br/>" : "<a:br>\(props)</a:br>"
                    k += 1; continue
                }
                if let type = block.fields[k] {
                    let shown = type == "slidenum" ? "‹#›" : "1/1/2026"
                    out += "<a:fld id=\"{5C1F2A90-7B3D-4E60-9A41-0D8E6B2F7C13}\" type=\"\(type)\">\(charRun(at: k).map { runProps($0.0) }.flatMap { $0.isEmpty ? nil : $0 } ?? "<a:rPr lang=\"en-US\"/>")<a:t>\(shown)</a:t></a:fld>"
                    k += 1; continue
                }
                let run = charRun(at: k)
                var e = k
                let limit = min(pe, run?.1 ?? pe)
                while e < limit, units[e] != 0x0B, block.fields[e] == nil || e == k { e += 1 }
                if e == k { e = k + 1 }
                let text = units[k ..< e].filter { $0 >= 0x20 || $0 == 0x09 }
                if !text.isEmpty {
                    out += "<a:r>\(run.map { runProps($0.0) } ?? "")<a:t>\(Self.escape(String(decoding: text, as: UTF16.self)))</a:t></a:r>"
                }
                k = e
            }
            // The paragraph mark's own run: the size of an empty paragraph's line.
            if let run = charRun(at: pe) { out += runProps(run.0, tag: "a:endParaRPr") }
            out += "</a:p>"
            ps = pe + 1
        }
        return out
    }

    /// A master's `p:txStyles`: title, body and other text styles from its TextMasterStyleAtoms.
    func textStylesXML(of master: Page) -> String {
        let body = levelsXML("p:titleStyle", master.textStyles[0]) + levelsXML("p:bodyStyle", master.textStyles[1])
            + levelsXML("p:otherStyle", master.textStyles[4])
        return body.isEmpty ? "" : "<p:txStyles>\(body)</p:txStyles>"
    }

    /// The presentation's `p:defaultTextStyle`: the document's own style for other text (its Environment's
    /// TextMasterStyleAtom), which PowerPoint gives a text box on a slide.
    func defaultTextStyleXML() -> String {
        levelsXML("p:defaultTextStyle", defaultStyles[4] ?? defaultStyles.sorted { $0.key < $1.key }.first?.value)
    }

    /// `<p:tag>` with one `a:lvlNpPr` per level; a level that names no font gets the document's default one.
    /// `ruler`: a shape's TextRuler, whose left margins and indents replace the style's at the levels it names.
    func levelsXML(_ tag: String, _ levels: [PptStyle.Level]?, ruler: [Int: (left: Int?, indent: Int?)] = [:]) -> String {
        guard let levels, !levels.isEmpty else { return "" }
        var out = "<\(tag)>"
        var font = defaultChar.font ?? 0
        for (k, l) in levels.enumerated() {
            var para = l.para
            para.level = 0
            if let r = ruler[k] {
                if let v = r.left { para.leftMargin = v }
                if let v = r.indent { para.indent = v }
            }
            var char = l.char
            // A level that names no font keeps the one of the level above it.
            if let f = char.font { font = f } else { char.font = font }
            out += paragraphProps(para, tag: "a:lvl\(k + 1)pPr", defaults: runProps(char, tag: "a:defRPr"))
        }
        return out + "</\(tag)>"
    }
}
