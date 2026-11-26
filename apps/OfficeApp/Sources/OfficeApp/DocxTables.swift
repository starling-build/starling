// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// .docx — WordprocessingML in a zip. The reader covers what the document
// model can hold: paragraphs with runs (bold, italic, underline, strike,
// size, colour, highlight, font, sub/superscript, hyperlinks), paragraph
// alignment, indents, spacing, headings via the style table, lists via the
// numbering table, page breaks, tables (cells as cell-tagged paragraphs,
// column widths from the grid), inline pictures, headers and footers, and
// the section's paper size and margins. The writer emits a minimal package
// (document, styles, numbering, relationships, media) that Word,
// LibreOffice and macOS all open.

import Flutter
import OfficeText
import FlutterSwiftBridge
import Foundation
#if canImport(FoundationXML) && !os(WASI)
import FoundationXML
#endif

// Part of the .docx reader/writer (split from Docx.swift, members unchanged).

extension DocxFormat {
    /// The paragraphs of an HTML chunk: its text, split where a block
    /// element (p, div, h1-h6, li, tr, br) starts, tags and head dropped,
    /// the common entities read, runs of white space one space.
    /// The body of a Word document that stands as an alt-chunk.
    static func _innerBody(_ archive: Data) -> XNode? {
        guard let entries = try? Zip.read(archive),
              let doc = entries.first(where: { $0.name == "word/document.xml" }),
              let root = XNode.parse(doc.data) else { return nil }
        return root.first("w:body")
    }

    static func _htmlParagraphs(_ html: String) -> [String] {
        var out: [String] = []
        var cur = ""
        var skip = false
        func end() {
            let t = cur.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\r" || $0 == "\t" }).joined(separator: " ")
            if !t.isEmpty { out.append(t) }
            cur = ""
        }
        var i = html.startIndex
        while i < html.endIndex {
            if html[i] == "<", let close = html[i...].firstIndex(of: ">") {
                let tag = html[html.index(after: i) ..< close].lowercased()
                let name = tag.drop(while: { $0 == "/" || $0 == " " }).prefix(while: { $0 != " " && $0 != "/" }).description
                if ["head", "style", "script", "title"].contains(name) { skip = !tag.hasPrefix("/") }
                else if ["p", "div", "br", "li", "tr", "h1", "h2", "h3", "h4", "h5", "h6", "table", "ul", "ol", "pre"].contains(name) { end() }
                i = html.index(after: close)
                continue
            }
            if !skip {
                if html[i] == "&", let semi = html[i...].prefix(10).firstIndex(of: ";") {
                    let ent = String(html[html.index(after: i) ..< semi])
                    let known = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}"]
                    if let v = known[ent] { cur += v; i = html.index(after: semi); continue }
                    if ent.hasPrefix("#"), let code = ent.dropFirst().first == "x" || ent.dropFirst().first == "X" ? UInt32(ent.dropFirst(2), radix: 16) : UInt32(ent.dropFirst()),
                       let u = Unicode.Scalar(code) { cur.unicodeScalars.append(u); i = html.index(after: semi); continue }
                }
                cur.append(html[i])
            }
            i = html.index(after: i)
        }
        end()
        return out
    }

    /// A paragraph cut at a page or column break is several paragraphs here,
    /// and the section's mark (its `w:sectPr`) is the LAST one's: the pieces
    /// before it are inside the section. Left on all of them the section
    /// ended at the first piece, and an odd-page section began the rest on
    /// the next odd page: lo bnc519228's "page 2", after a page break in the
    /// paragraph that ends the first section, stood on page 3 with a blank
    /// page 2, where Word has it on page 2.
    static func _sectionMarkStaysOnTheLastPiece(_ p: inout RichParagraph) {
        guard p.style.sectionXML != nil else { return }
        RuleTrace.hit("section-mark-on-the-last-piece-of-a-split-paragraph")
        p.style.sectionXML = nil; p.style.sectionRels = []; p.style.sectionPage = nil; p.style.sectionBreaksPage = nil
    }

    /// `w:rFonts` for a look: the Latin face in ascii and hAnsi, and in
    /// the complex-script slot too unless the file named another face
    /// there — rtl.docx's Arabic is set in its w:cs face, and with the
    /// Latin one written over it Word substituted a wider font and
    /// wrapped every paragraph elsewhere.
    static func _rFontsXML(_ s: CharStyle, fileFonts: Set<String>, eastAsiaDefault: Bool = false) -> String {
        let latin = s.fontFamily.map { fileFonts.contains($0) ? $0 : OfficeFonts.exportName($0) }
        var attrs = ""
        if let latin { attrs += " w:ascii=\"\(_esc(latin))\" w:hAnsi=\"\(_esc(s.hAnsiFontFamily ?? latin))\"" }
        else if let h = s.hAnsiFontFamily { attrs += " w:hAnsi=\"\(_esc(h))\"" }
        if let hint = s.fontHint { attrs += " w:hint=\"\(_esc(hint))\"" }
        if let cs = s.complexFontFamily ?? latin { attrs += " w:cs=\"\(_esc(cs))\"" }
        if let ea = s.eastAsiaFontFamily ?? (eastAsiaDefault ? latin : nil) { attrs += " w:eastAsia=\"\(_esc(ea))\"" }
        if let t = s.fontTheme, let hash = t.firstIndex(of: "#"), t[t.startIndex ..< hash] == Substring(_fontKey(s)) { attrs += t[t.index(after: hash)...] }
        return attrs.isEmpty ? "" : "<w:rFonts\(attrs)/>"
    }

    /// The four faces of a look, for telling whether its theme-font attributes still apply.
    static func _fontKey(_ s: CharStyle) -> String {
        [s.fontFamily, s.hAnsiFontFamily, s.complexFontFamily, s.eastAsiaFontFamily].map { $0 ?? "" }.joined(separator: "|")
    }

    /// A run's properties (CT_RPr children, in schema order). A switch
    /// the run turns off explicitly (`off`) is written as off: a false
    /// alone means "inherit" (drawing.docx's "b w:val=0" runs under a
    /// bold heading 3 came back bold; 52288's plain runs under a bold
    /// style must not come back un-bold).
    /// CT_RPr's element order (w14 and other extensions after it).
    static let _rPrOrder: [String: Int] = Dictionary(uniqueKeysWithValues: ["w:rStyle", "w:rFonts", "w:b", "w:bCs", "w:i", "w:iCs", "w:caps", "w:smallCaps",
        "w:strike", "w:dstrike", "w:outline", "w:shadow", "w:emboss", "w:imprint", "w:noProof", "w:snapToGrid", "w:vanish", "w:webHidden",
        "w:color", "w:spacing", "w:w", "w:kern", "w:position", "w:sz", "w:szCs", "w:highlight", "w:u", "w:effect", "w:bdr", "w:shd",
        "w:fitText", "w:vertAlign", "w:rtl", "w:cs", "w:em", "w:lang", "w:eastAsianLayout", "w:specVanish", "w:oMath"].enumerated().map { ($1, $0) })
    /// The top-level elements of a run of sibling XML elements: (name, start, end) as UTF-8 offsets.
    static func _rPrElements(_ xml: String) -> [(name: String, range: Range<Int>)] {
        let b = Array(xml.utf8); var out: [(String, Range<Int>)] = []
        var i = 0, depth = 0, start = 0, name = ""
        while i < b.count {
            guard b[i] == UInt8(ascii: "<") else { i += 1; continue }
            var j = i + 1; while j < b.count, b[j] != UInt8(ascii: ">") { j += 1 }
            let closing = i + 1 < b.count && b[i + 1] == UInt8(ascii: "/"), selfClosing = j > 0 && b[j - 1] == UInt8(ascii: "/")
            if closing { depth -= 1; if depth == 0 { out.append((name, start ..< j + 1)) } }
            else {
                if depth == 0 {
                    start = i; var k = i + 1
                    while k < j, b[k] != UInt8(ascii: " "), b[k] != UInt8(ascii: "/"), b[k] != UInt8(ascii: "\t"), b[k] != UInt8(ascii: "\n") { k += 1 }
                    name = String(decoding: b[(i + 1) ..< k], as: UTF8.self)
                }
                if selfClosing { if depth == 0 { out.append((name, start ..< j + 1)) } } else { depth += 1 }
            }
            i = j + 1
        }
        return out
    }
    static func _rPrElementNames(_ xml: String) -> [String] { _rPrElements(xml).map(\.name) }
    /// The fields' run properties with the file's extra elements put back in schema order (a name the fields now write wins).
    static func _mergeRPr(_ fresh: String, _ extras: String) -> String {
        let fb = Array(fresh.utf8), eb = Array(extras.utf8)
        let have = Set(_rPrElementNames(fresh))
        var parts: [(rank: Int, seq: Int, xml: String)] = []
        var seq = 0
        func rank(_ n: String) -> Int { n == "w:rPrChange" ? 10_000 : (_rPrOrder[n] ?? 1_000) }
        for e in _rPrElements(fresh) { parts.append((rank(e.name), seq, String(decoding: fb[e.range], as: UTF8.self))); seq += 1 }
        for e in _rPrElements(extras) where !have.contains(e.name) { parts.append((rank(e.name), seq, String(decoding: eb[e.range], as: UTF8.self))); seq += 1 }
        return parts.sorted { ($0.rank, $0.seq) < ($1.rank, $1.seq) }.map(\.xml).joined()
    }
    static func _rPrXML(_ s: CharStyle, fileFonts: Set<String> = [], changeId: Int? = nil) -> String {
        if changeId == nil, let original = s.originalRPr { return original }
        if let extras = s.origExtras {
            var plain = s; plain.origExtras = nil
            return _mergeRPr(_rPrXML(plain, fileFonts: fileFonts, changeId: changeId), extras)
        }
        var rPr = s.styleId.map { "<w:rStyle w:val=\"\(_esc($0))\"/>" } ?? ""
        func off(_ tag: String, _ sw: CharSwitches) -> String { s.off.contains(sw) ? "<w:\(tag) w:val=\"0\"/>" : "" }
    rPr += _rFontsXML(s, fileFonts: fileFonts)
    if s.bold { rPr += "<w:b/><w:bCs/>" } else { rPr += off("b", .bold) }
    if s.italic { rPr += "<w:i/><w:iCs/>" } else { rPr += off("i", .italic) }
    if s.caps { rPr += "<w:caps/>" } else { rPr += off("caps", .caps) }
    if s.hidden { rPr += "<w:vanish/>" } else { rPr += off("vanish", .hidden) }
    if s.smallCaps { rPr += "<w:smallCaps/>" } else { rPr += off("smallCaps", .smallCaps) }
    if s.underline {
        rPr += "<w:u w:val=\"\(_esc(s.underlineKind ?? "single"))\""
        if let c = s.underlineColor { rPr += " w:color=\"\(_esc(c))\"" }
        if let t = s.underlineThemeAttrs { rPr += t }
        rPr += "/>"
    } else if s.off.contains(.underline) { rPr += "<w:u w:val=\"none\"/>" }
    if s.strikethrough { rPr += s.doubleStrike ? "<w:dstrike/>" : "<w:strike/>" } else { rPr += off("strike", .strikethrough) }
    if let em = s.emphasis { rPr += "<w:em w:val=\"\(em)\"/>" }
    if let color = s.color {
        let hex = _hex(color)
        let theme = s.colorTheme.flatMap { $0.hasPrefix(hex) ? String($0.dropFirst(hex.count)) : nil } ?? ""
        rPr += "<w:color w:val=\"\(hex)\"\(theme)/>"
    }
    if let ls = s.letterSpacing, ls != 0 { rPr += "<w:spacing w:val=\"\(Int((ls * 20).rounded()))\"/>" }
    if let w = s.horizontalScale, w != 1 { rPr += "<w:w w:val=\"\(Int((w * 100).rounded()))\"/>" }
    if let k = s.kerningFrom { rPr += "<w:kern w:val=\"\(Int((k * 2).rounded()))\"/>" }
    if let r = s.raised, r != 0 { rPr += "<w:position w:val=\"\(Int((r * 2).rounded()))\"/>" }
    if let size = s.fontSize { rPr += "<w:sz w:val=\"\(Int(size * 2))\"/><w:szCs w:val=\"\(Int(size * 2))\"/>" }
    if s.highlight == nil, let t = s.shdSource, t.hasPrefix("auto#") { rPr += "<w:shd\(t.dropFirst(5)) w:fill=\"auto\"/>" }
    if let hl = s.highlight {
        if let t = s.shdSource, let h = t.firstIndex(of: "#"), t[t.startIndex ..< h].lowercased() == _hex(hl).lowercased() {
            rPr += "<w:shd\(t[t.index(after: h)...]) w:fill=\"\(_hex(hl))\"/>"
        } else if let name = highlightNames.first(where: { $0.1 == hl })?.0 {
            rPr += "<w:highlight w:val=\"\(name)\"/>"
        } else {
            rPr += "<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"\(_hex(hl))\"/>"
        }
    }
    if s.script == .superscript { rPr += "<w:vertAlign w:val=\"superscript\"/>" }
    if s.script == .subscript { rPr += "<w:vertAlign w:val=\"subscript\"/>" }
    if let fc = s.formatChange, let id = changeId {
        rPr += "<w:rPrChange w:id=\"\(id)\" w:author=\"\(_esc(fc.author.isEmpty ? "Author" : fc.author))\"\(fc.date.isEmpty ? "" : " w:date=\"\(_esc(fc.date))\"")>\(fc.oldRPrXML)</w:rPrChange>"
    }
    if s.rightToLeft { rPr += "<w:rtl/>" }
    if var kept = s.keptXML {
        // The scale and raise are fields now (the Font dialog sets them), so the
        // copy kept from the file must not say them a second time or out of date.
        if kept.containsSubstring("<w:w ") || kept.containsSubstring("<w:position ") {
            let parts = _keptRunProperties(kept).filter { $0.key != "w:w" && $0.key != "w:position" }
            kept = parts.keys.sorted().map { parts[$0]! }.joined()
        }
        rPr += kept
    }
        return rPr
    }

    /// How deep `w:tbl` elements nest under `node` (iterative; a fuzzer's
    /// 5,000-level table must not recurse).
    /// A section's columns from its `w:cols` (`sectionXML`), each one's
    /// width and the gap after it in points — the file's own where its
    /// columns are unequal, else equal shares of the text width. Nil for
    /// one column.
    /// A kept section mark with the page the user set: only the size,
    /// margins and column count that differ from the XML are rewritten, so a
    /// section nobody touched is written back byte for byte.
    static func _sectionXML(_ xml: String, patchedTo page: PageSetup?) -> String {
        guard let page, !page.vertical, let sect = XNode.parse(Data(xml.utf8)) else { return xml }
        var changed = false
        func twips(_ v: Double) -> String { String(Int((v * 20).rounded())) }
        func put(_ node: XNode, _ key: String, _ v: Double) {
            if let have = Double(node.attrs[key] ?? ""), abs(have - (v * 20).rounded()) < 1 { return }
            node.attrs[key] = twips(v); changed = true
        }
        let size = sect.first("w:pgSz") ?? { let n = XNode(name: "w:pgSz", attrs: [:]); sect.children.insert(n, at: 0); return n }()
        put(size, "w:w", page.width); put(size, "w:h", page.height)
        if page.isLandscape != (size.attrs["w:orient"] == "landscape"), page.orientStated || size.attrs["w:orient"] != nil {
            size.attrs["w:orient"] = page.isLandscape ? "landscape" : "portrait"; changed = true
        }
        if let mar = sect.first("w:pgMar") {
            put(mar, "w:top", page.marginTop); put(mar, "w:bottom", page.marginBottom)
            put(mar, "w:left", page.marginLeft); put(mar, "w:right", page.marginRight)
        }
        let cols = sect.first("w:cols")
        let have = Int(cols?.attrs["w:num"] ?? "") ?? 1
        if have != max(1, page.columns) {
            let n = cols ?? { let n = XNode(name: "w:cols", attrs: [:]); sect.children.append(n); return n }()
            n.children = []
            n.attrs = ["w:num": String(max(1, page.columns)), "w:space": twips(page.columnGap)]
            changed = true
        }
        return changed ? PptxXML.serialize(sect) : xml
    }

    static func _sectionColumns(_ sectionXML: String, _ page: PageSetup?) -> [(width: Double, space: Double)]? {
        guard let sect = XNode.parse(Data(sectionXML.utf8)), let cols = sect.name == "w:cols" ? sect : sect.descendant("w:cols") else { return nil }
        let num = Int(cols["w:num"] ?? "1") ?? 1
        guard num > 1 else { return nil }
        let space = (Double(cols["w:space"] ?? "") ?? 720) / 20
        let own = cols.children.filter { $0.name == "w:col" }
        if cols["w:equalWidth"].map({ $0 == "0" || $0 == "false" || $0 == "off" }) ?? false, own.count == num {
            return own.map { ((Double($0["w:w"] ?? "") ?? 0) / 20, (Double($0["w:space"] ?? "") ?? 0) / 20) }
        }
        guard let page else { return nil }
        let text = page.width - page.marginLeft - page.marginRight
        let width = (text - space * Double(num - 1)) / Double(num)
        guard width > 0 else { return nil }
        return (0 ..< num).map { k in (width, k < num - 1 ? space : 0) }
    }

    /// A table floating in a cell (`w:tblpPr`), one column wide and tall by
    /// the least heights it gives its rows: Word parts it between its rows
    /// across pages, as it does a table of the body — LibreOffice's
    /// floattable-anchor-height, whose three rows of 98, 363 and 170pt each
    /// stand on a page of their own. A box (`RichTextBox`) does not part,
    /// so such a table is read as paragraphs, one row each: see the reader.
    static func _isTallNarrowFloat(_ node: XNode) -> Bool {
        guard let pr = node.first("w:tblPr"), let pos = pr.first("w:tblpPr"),
              node.first("w:tblGrid")?.all("w:gridCol").count == 1,
              !node.all("w:tr").isEmpty else { return false }
        // (Not one that floats only in name, which the box reads as an
        // inline table and parts between its rows already: LibreOffice's
        // tdf170620, 56 rows, against the text, from the column's edge, a
        // twip under its paragraph.)
        if pos["w:vertAnchor"] == "text", (pos["w:horzAnchor"] ?? "text") == "text", pos["w:tblpXSpec"] == nil, pos["w:tblpYSpec"] == nil,
           (Double(pos["w:tblpY"] ?? "") ?? 0) / 20 <= 1, (Double(pos["w:tblpX"] ?? "") ?? 0) >= 0 { return false }
        // (A row is as tall as its least height or as its text, set at about 5pt a character in the column,
        // whichever is more: lab nf1, Word for Windows, prints the float of lo-c7082c66 whose rows state 10pt
        // as it prints the one whose last row states 170pt — four pages, the same lines on the first three —
        // where ours, reading only the stated heights, set the 86pt column as a wide block.)
        let colWide = (Double(node.first("w:tblGrid")?.all("w:gridCol").first?["w:w"] ?? "") ?? 0) / 20
        var total = 0.0
        for tr in node.all("w:tr") {
            if tr.all("w:tc").count != 1 { return false }
            var stated = 0.0
            if let h = tr.first("w:trPr")?.first("w:trHeight"), h["w:hRule"] != "exact", let v = Double(h["w:val"] ?? "") { stated = v / 20 }
            let chars = Double(tr.descendants("w:t").reduce(0) { $0 + $1.text.count })
            let lines = colWide > 12 ? (chars * 5 / (colWide - 11)).rounded(.up) : 0
            total += max(stated, lines * 13.4)
        }
        return total >= 200
    }

    /// A table in a cell that holds exactly one level of tables of its own,
    /// of three rows or more and none floating: a form whose check-box rows nest
    /// the "Plan number / Number of lots" strip (LibreOffice's tdf158349).
    /// Word sets it as a block in its cell like any other; flattened, the
    /// check box and its text stacked as two lines. A one- or two-row wrapper (the
    /// single cell around a form, zh-cb57eaad's three deep; floattable-nested-rowspan's
    /// spacer row and form) and anything
    /// with a floating table in it stay flattened.
    static func _formHoldingATable(_ node: XNode) -> Bool {
        _nestingDepth(node) == 2
            && node.children.filter { $0.name == "w:tr" }.count >= 2
            && (node.children.filter { $0.name == "w:tr" }.count >= 3 || node.first("w:tblPr")?.first("w:tblpPr") == nil)
    }

    static func _nestingDepth(_ node: XNode) -> Int {
        var deepest = 0
        var stack: [(XNode, Int)] = [(node, 0)]
        while let (n, d) = stack.popLast() {
            let nd = n.name == "w:tbl" ? d + 1 : d
            deepest = max(deepest, nd)
            if nd > 8 { return nd }
            for c in n.children { stack.append((c, nd)) }
        }
        return deepest
    }

    /// `node` serialized as a self-contained fragment: its relationships
    /// collected (and their parts kept), every prefix it uses declared on
    /// it. Nil when a part it names is missing from the package.
    /// The attributes that name a relationship of the part they stand in.
    /// The last four are a SmartArt diagram's (`dgm:relIds`: data, layout,
    /// quick style, colours) — left out, a kept diagram named ids the save
    /// never wrote and its parts stayed behind.
    static let _relationshipAttributes = ["r:embed", "r:id", "r:link", "r:pict", "r:href", "r:dm", "r:lo", "r:qs", "r:cs"]

    /// Whether a table is a one-column frame that draws nothing round
    /// tables of its own: no style, no float, one grid column and one cell
    /// a row, no shading, and no line one column can draw — its own lines
    /// none, or inside-vertical ones only.
    static func _isInvisibleWrapper(_ node: XNode) -> Bool {
        guard let pr = node.first("w:tblPr"), pr.first("w:tblStyle") == nil, pr.first("w:tblpPr") == nil,
              pr.first("w:shd") == nil,
              let columns = node.first("w:tblGrid")?.all("w:gridCol").count, columns >= 1 else { return false }
        func drawn(_ b: XNode?, except: Set<String>) -> Bool {
            guard let b else { return false }
            return b.children.contains { side in
                !except.contains(side.name) && !["none", "nil"].contains(side["w:val"] ?? "none")
            }
        }
        // (One column never draws its insideV; more would.)
        if drawn(pr.first("w:tblBorders"), except: columns == 1 ? ["w:insideV"] : []) { return false }
        // (Nor is a column beside it anything but room: 60329's body is a
        // 678.75pt column of tables in cells and an 82.35pt one empty in
        // every row, and Word sets each table at the margin, its own grid
        // wide, parting over pages; flattened as tables in a cell are,
        // their columns stood one under another.)
        func empty(_ tc: XNode) -> Bool {
            var stack = tc.children
            while let n = stack.popLast() {
                if ["w:t", "w:tbl", "w:drawing", "w:pict", "w:object", "w:sym", "w:tab", "w:br"].contains(n.name) { return false }
                stack.append(contentsOf: n.children)
            }
            return true
        }
        var nests = false
        for tr in node.all("w:tr") {
            let cells = tr.all("w:tc")
            guard let tc = cells.first, cells.count == 1 || cells.dropFirst().allSatisfy(empty) else { return false }
            // (… and no row of more than a line's height: a frame whose rows
            // are set to a height is laid out by them.)
            if columns > 1, let h = tr.first("w:trPr")?.first("w:trHeight"),
               h["w:hRule"] == "exact" || (Double(h["w:val"] ?? "") ?? 0) > 400 { return false }
            for c in cells {
                let tcPr = c.first("w:tcPr")
                if drawn(tcPr?.first("w:tcBorders"), except: []) { return false }
                if let fill = tcPr?.first("w:shd")?["w:fill"], !["auto", "FFFFFF", "ffffff"].contains(fill) { return false }
                if tcPr?.first("w:gridSpan") != nil || tcPr?.first("w:vMerge") != nil { return false }
            }
            if tc.all("w:tbl").isEmpty == false { nests = true }
        }
        return nests
    }

    /// `node` with its columns in reverse order when it is a `w:bidiVisual` table; else `node`.
    static func _mirroredTable(_ node: XNode) -> XNode {
        guard node.name == "w:tbl", node.mirroredFrom == nil, let v = node.first("w:tblPr")?.first("w:bidiVisual"),
              !["0", "false", "off"].contains((v["w:val"] ?? "1").lowercased()) else { return node }
        let copy = XNode(name: node.name, attrs: node.attrs)
        copy.mirroredFrom = node
        for child in node.children {
            if child.name == "w:tblGrid" {
                let g = XNode(name: child.name, attrs: child.attrs)
                g.children = child.children.filter { $0.name != "w:gridCol" } + child.children.filter { $0.name == "w:gridCol" }.reversed()
                copy.children.append(g)
            } else if child.name == "w:tr", child.children.allSatisfy({ ["w:tc", "w:trPr", "w:tblPrEx"].contains($0.name) }) {
                let r = XNode(name: child.name, attrs: child.attrs)
                r.children = child.children.filter { $0.name != "w:tc" && $0.name != "w:trPr" } + child.children.filter { $0.name == "w:tc" }.reversed()
                // The cells run the other way, so the unused grid columns before and after them trade places.
                if let pr = child.first("w:trPr") {
                    let swapped = XNode(name: pr.name, attrs: pr.attrs)
                    let rename = ["w:gridBefore": "w:gridAfter", "w:gridAfter": "w:gridBefore", "w:wBefore": "w:wAfter", "w:wAfter": "w:wBefore"]
                    swapped.children = pr.children.map { k in
                        guard let to = rename[k.name] else { return k }
                        let n = XNode(name: to, attrs: k.attrs); n.children = k.children; return n
                    }
                    r.children.insert(swapped, at: 0)
                }
                copy.children.append(r)
            } else { copy.children.append(child) }
        }
        return copy
    }

    static func _keptFragment(_ given: XNode, _ notes: _Shared) -> (xml: String, rels: [KeptRel])? {
        let node = given.mirroredFrom ?? given
        var found: [KeptRel] = []
        var prefixes = Set<String>()
        var stack = [node]
        while let n = stack.popLast() {
            if let i = n.name.firstIndex(of: ":") { prefixes.insert(String(n.name[..<i])) }
            for (k, v) in n.attrs {
                if let i = k.firstIndex(of: ":"), !k.hasPrefix("xmlns:") { prefixes.insert(String(k[..<i])) }
                if k == "Requires" || k == "mc:Ignorable" { for t in v.split(separator: " ") { prefixes.insert(String(t)) } }
                guard _relationshipAttributes.contains(k), let rel = notes.rels[v],
                      !found.contains(where: { $0.id == v }) else { continue }
                found.append(rel)
                if !rel.external { notes.keep(_resolvePath("word", rel.target)) }
            }
            stack.append(contentsOf: n.children)
        }
        if found.contains(where: { !$0.external && notes.part(_resolvePath("word", $0.target)) == nil }) { return nil }
        for prefix in prefixes where prefix != "xml" && node.attrs["xmlns:" + prefix] == nil {
            if let uri = notes.rootNS["xmlns:" + prefix] { node.attrs["xmlns:" + prefix] = uri }
        }
        return (PptxXML.serialize(node), found)
    }

    /// `xml` with its picture's `a:xfrm` turned `degrees` (clockwise; `rot` is removed for none), the rest as it was.
    static func _drawingWithRotation(_ xml: String, _ degrees: Double) -> String {
        guard let spPr = xml.rangeOfSubstring("<pic:spPr", in: xml.startIndex ..< xml.endIndex),
              let open = xml.rangeOfSubstring("<a:xfrm", in: spPr.upperBound ..< xml.endIndex),
              let close = xml.rangeOfSubstring(">", in: open.upperBound ..< xml.endIndex) else { return xml }
        var tag = String(xml[open.lowerBound ..< close.lowerBound])
        let selfClosing = tag.hasSuffix("/")
        if selfClosing { tag.removeLast() }
        if let r = tag.rangeOfSubstring(" rot=\"", in: tag.startIndex ..< tag.endIndex),
           let e = tag.rangeOfSubstring("\"", in: r.upperBound ..< tag.endIndex) {
            tag.removeSubrange(r.lowerBound ..< e.upperBound)
        }
        let turned = Int(((degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) * 60000).rounded())
        if turned != 0 { tag += " rot=\"\(turned)\"" }
        if selfClosing { tag += "/" }
        return String(xml[xml.startIndex ..< open.lowerBound]) + tag + String(xml[close.lowerBound...])
    }

    /// The `a:srcRect` element for `crop` (shares of the picture cut off each side, in 1/100000), or "" for none.
    static func _srcRectXML(_ crop: PictureCrop?) -> String {
        guard let c = crop, c.left > 0 || c.top > 0 || c.right > 0 || c.bottom > 0 else { return "" }
        func part(_ name: String, _ v: Double) -> String { v > 0 ? " \(name)=\"\(Int((v * 100000).rounded()))\"" : "" }
        return "<a:srcRect" + part("l", c.left) + part("t", c.top) + part("r", c.right) + part("b", c.bottom) + "/>"
    }

    /// `xml` with its picture's `a:srcRect` set to `crop` (removed for none), the rest as it was; unchanged when it holds no `pic:blipFill`.
    static func _drawingWithCrop(_ xml: String, _ crop: PictureCrop?) -> String {
        guard let fill = xml.rangeOfSubstring("</pic:blipFill>", in: xml.startIndex ..< xml.endIndex),
              let fillOpen = xml.rangeOfSubstring("<pic:blipFill", in: xml.startIndex ..< fill.lowerBound) else { return xml }
        var inner = String(xml[fillOpen.lowerBound ..< fill.lowerBound])
        if let r = inner.rangeOfSubstring("<a:srcRect", in: inner.startIndex ..< inner.endIndex),
           let e = inner.rangeOfSubstring(">", in: r.upperBound ..< inner.endIndex) {
            inner.removeSubrange(r.lowerBound ..< e.upperBound)
        }
        let rect = _srcRectXML(crop)
        if !rect.isEmpty {
            if let st = inner.rangeOfSubstring("<a:stretch", in: inner.startIndex ..< inner.endIndex) ?? inner.rangeOfSubstring("<a:tile", in: inner.startIndex ..< inner.endIndex) {
                inner.insert(contentsOf: rect, at: st.lowerBound)
            } else {
                inner += rect
            }
        }
        return String(xml[xml.startIndex ..< fillOpen.lowerBound]) + inner + String(xml[fill.lowerBound...])
    }

    /// `xml` with the `descr` (alternative text) of its first `wp:docPr` set to `text`, the rest as it was.
    static func _drawingWithAltText(_ xml: String, _ text: String) -> String {
        guard let open = xml.rangeOfSubstring("<wp:docPr", in: xml.startIndex ..< xml.endIndex),
              let close = xml.rangeOfSubstring(">", in: open.upperBound ..< xml.endIndex) else { return xml }
        var tag = String(xml[open.lowerBound ..< close.lowerBound])
        let selfClosing = tag.hasSuffix("/")
        if selfClosing { tag.removeLast() }
        // Drop an existing descr="…" attribute.
        if let d = tag.rangeOfSubstring(" descr=\"", in: tag.startIndex ..< tag.endIndex),
           let e = tag.rangeOfSubstring("\"", in: d.upperBound ..< tag.endIndex) {
            tag.removeSubrange(d.lowerBound ..< e.upperBound)
        }
        if !text.isEmpty { tag += " descr=\"\(_esc(text))\"" }
        if selfClosing { tag += "/" }
        return String(xml[xml.startIndex ..< open.lowerBound]) + tag + String(xml[close.lowerBound...])
    }

    /// A kept drawing's markup with its size changed in place: the first `wp:extent` and the first `a:ext`
    /// after it (the drawing's own frame, not a group child's) take the new size, so a resize keeps the
    /// float's position, wrap, crop, turn, alt text and effects. Returns nil where the markup names no
    /// size to patch; `unchanged` is true when the markup already has this size (then it is written as read).
    static func _resizedDrawingXML(_ xml: String, width: Double, height: Double, sourceWidth: Double?, sourceHeight: Double?, turned: Bool? = nil) -> (xml: String, unchanged: Bool)? {
        func pair(_ tag: String, from start: String.Index) -> (range: Range<String.Index>, cx: Double, cy: Double)? {
            guard let open = xml.rangeOfSubstring(tag, in: start ..< xml.endIndex),
                  let close = xml.rangeOfSubstring("/>", in: open.upperBound ..< xml.endIndex) else { return nil }
            let attrs = " " + String(String(xml[open.lowerBound ..< close.lowerBound]).drop(while: { $0 != " " }))
            func value(_ name: String) -> Double? {
                guard let a = attrs.rangeOfSubstring(" \(name)=\"") else { return nil }
                let rest = attrs[a.upperBound...]
                guard let q = rest.firstIndex(of: "\"") else { return nil }
                return Double(String(rest[rest.startIndex ..< q]))
            }
            guard let cx = value("cx"), let cy = value("cy") else { return nil }
            return (open.lowerBound ..< close.upperBound, cx, cy)
        }
        guard let ext = pair("<wp:extent", from: xml.startIndex) else { return nil }
        let oldW = ext.cx / 12700, oldH = ext.cy / 12700
        // (A picture turned a quarter was read with its width and height swapped.)
        // (`turned`, when the editor turned it, says it outright.)
        let swapped = turned ?? sourceWidth.map { abs($0 - oldH) < 0.1 && abs($0 - oldW) >= 0.1 } ?? false
        let newW = swapped ? height : width, newH = swapped ? width : height
        if abs(newW - oldW) < 0.1, abs(newH - oldH) < 0.1 { return (xml, true) }
        let cx = Int((newW * 12700).rounded()), cy = Int((newH * 12700).rounded())
        var out = xml
        let inner = pair("<a:ext cx", from: ext.range.upperBound)
        // Later range first, so the earlier one's index stays valid.
        if let inner, let tail = out.rangeOfSubstring(String(xml[inner.range])) {
            out.replaceSubrange(tail, with: "<a:ext cx=\"\(cx)\" cy=\"\(cy)\"/>")
        }
        if let head = out.rangeOfSubstring(String(xml[ext.range])) {
            out.replaceSubrange(head, with: "<wp:extent cx=\"\(cx)\" cy=\"\(cy)\"/>")
        }
        return (out, false)
    }

    /// `fragment` with each `wp:docPr id="…"` given the next id from
    /// `next` (a kept nested table holds several drawings; one id for all
    /// of them was "unreadable content" to Word).
    static func _renumberDocPr(_ fragment: String, next: inout Int) -> String {
        var out = fragment
        var search = out.startIndex
        // The serializer sorts attributes, so `id` may follow `descr`:
        // find the tag, then its id attribute.
        while let tag = out.rangeOfSubstring("<wp:docPr", in: search ..< out.endIndex) {
            guard let close = out[tag.upperBound...].firstIndex(of: ">"),
                  let r = out.rangeOfSubstring(" id=\"", in: tag.upperBound ..< close) else { search = tag.upperBound; continue }
            next += 1
            let id = String(next)
            let digitsStart = r.upperBound
            var digitsEnd = digitsStart
            while digitsEnd < out.endIndex, out[digitsEnd].isNumber { digitsEnd = out.index(after: digitsEnd) }
            out.replaceSubrange(digitsStart ..< digitsEnd, with: id)
            search = out.index(digitsStart, offsetBy: id.count)
        }
        return out
    }

    /// `<w:pBdr>` for a paragraph's borders: sz in eighths of a point.
    static func _bordersXML(_ b: ParagraphBorders) -> String {
        func edge(_ name: String, _ l: BorderLine?) -> String {
            guard let l else { return "" }
            let color = l.color.map { _hex($0) } ?? "auto"
            return "<w:\(name) w:val=\"\(_esc(l.style ?? "single"))\" w:sz=\"\(Int((l.width * 8).rounded()))\" w:space=\"\(Int(l.space.rounded()))\" w:color=\"\(color)\"/>"
        }
        return "<w:pBdr>" + edge("top", b.top) + edge("left", b.left) + edge("bottom", b.bottom) + edge("right", b.right) + edge("between", b.between) + "</w:pBdr>"
    }

    /// `<w:spacing>` with the style's before, after and line, all of them
    /// (a paragraph that says nothing takes the file's defaults, which
    /// need not be ours). Twips and 240ths, rounded — truncation drifted
    /// 1.08 lines to 258/240 and on down with every save.
    /// `under` is the paragraph style's spacing: auto spacing the style
    /// turns on and the paragraph turns off is written as off (drawing's
    /// "after 240, afterAutospacing 0" under an auto-spaced style).
    static func _spacingXML(_ s: RichParagraphStyle, under: RichParagraphStyle? = nil, omittingWhatItsStyleSays sheet: RichParagraphStyle? = nil) -> String {
        func same(_ f: (RichParagraphStyle) -> AnyHashable) -> Bool { sheet.map { f($0) == f(s) } ?? false }
        var spacing = ""
        // Zero included, when the paragraph's style has space before: a
        // Heading 6 spacer that says before 0 came back with the style's
        // 2pt, which moved the rest of form_footnotes' first page.
        let beforeSaid = same { [$0.spaceBefore, $0.spaceBeforeAuto] as [AnyHashable] }
        let afterSaid = same { [$0.spaceAfter, $0.spaceAfterAuto] as [AnyHashable] }
        let lineSaid = same { [$0.lineSpacing, $0.lineHeightPoints as Double?, $0.lineHeightIsMinimum, $0.lineCollapsed] as [AnyHashable] }
        if !beforeSaid, s.spaceBefore > 0 || (under?.spaceBefore ?? 0) > 0 { spacing += " w:before=\"\(Int((s.spaceBefore * 20).rounded()))\"" }
        if beforeSaid {} else if s.spaceBeforeAuto { spacing += " w:beforeAutospacing=\"1\"" } else if under?.spaceBeforeAuto ?? false { spacing += " w:beforeAutospacing=\"0\"" }
        if !afterSaid { spacing += " w:after=\"\(Int((s.spaceAfter * 20).rounded()))\"" }
        if afterSaid {} else if s.spaceAfterAuto { spacing += " w:afterAutospacing=\"1\"" } else if under?.spaceAfterAuto ?? false { spacing += " w:afterAutospacing=\"0\"" }
        if lineSaid {
        } else if s.lineCollapsed, s.lineHeightPoints == nil {
            spacing += " w:line=\"0\" w:lineRule=\"auto\""
        } else if let pts = s.lineHeightPoints {
            spacing += " w:line=\"\(Int((pts * 20).rounded()))\" w:lineRule=\"\(s.lineHeightIsMinimum ? "atLeast" : "exact")\""
        } else {
            spacing += " w:line=\"\(Int((s.lineSpacing * 240).rounded()))\" w:lineRule=\"auto\""
        }
        if spacing.isEmpty, sheet != nil { return "" }
        return "<w:spacing\(spacing)/>"
    }

    /// A `w:t`'s text as Word reads it: without xml:space="preserve" the
    /// XML whitespace at either end is not text. A hand-written file's
    /// "<w:t>Before </w:t>" joins the run after it (Bug66263-paragraph);
    /// no-break and typographic spaces are characters and stay.
    /// `xml:space` is inherited: a part whose root says "preserve" — Word
    /// 2007's zh-7773163d does, on `w:document` — keeps every `w:t`'s
    /// spaces that does not say otherwise. Ours read its 316 runs such as
    /// "<w:t>案例 </w:t>" without their spaces: "⚫案例2：…" where Word's
    /// print has "⚫ 案例 2：…" and breaks after the space.
    static func _inheritSpace(_ node: XNode, _ preserve: Bool = false) {
        let here = node["xml:space"].map { $0 == "preserve" } ?? preserve
        if node.name == "w:t" || node.name == "w:instrText" || node.name == "w:delText" {
            if here, node["xml:space"] == nil { node.attrs["xml:space"] = "preserve" }
            return
        }
        for child in node.children { _inheritSpace(child, here) }
    }

    static func _runText(_ t: XNode) -> String {
        // (A line separator typed into the text is no break to Word: it
        // prints a blank half an em wide and the line runs on —
        // LibreOffice's tdf152983-1-min, two of them in a 12pt paragraph,
        // 6pt each in Word's print. The layout's own breaks are U+2028, so
        // it is set as the en space, which is that wide.)
        let raw = t.text.containsSubstring("\u{2028}") ? t.text.replacingAll("\u{2028}", with: "\u{2002}") : t.text
        // (A raw line feed or carriage return typed inside w:t is no break to Word
        // either: it prints as a blank and the line runs on, as in xb jpn 5ff3d0's
        // cells "...の定義(LF)→ 1072nm", kept on one line in the print.)
        if t["xml:space"] == "preserve" {
            return raw.contains(where: { $0 == "\n" || $0 == "\r" || $0 == "\r\n" }) ? String(raw.map { $0 == "\n" || $0 == "\r" || $0 == "\r\n" ? " " : $0 }) : raw
        }
        let ws: Set<Character> = [" ", "\t", "\n", "\r", "\r\n"]
        var text = Substring(raw)
        while let f = text.first, ws.contains(f) { text.removeFirst() }
        while let l = text.last, ws.contains(l) { text.removeLast() }
        // (The same inside a text without xml:space=preserve: the line feed between "wie" and "Ursula" of
        // dx2 73357ebf prints as a blank and the line runs on; it was set as a break.)
        return text.contains(where: { $0 == "\n" || $0 == "\r" || $0 == "\r\n" }) ? String(text.map { $0 == "\n" || $0 == "\r" || $0 == "\r\n" ? " " : $0 }) : String(text)
    }

    /// An on/off element: present counts as on unless w:val is false, 0 or off.
    static func _on(_ node: XNode?) -> Bool {
        guard let node = node else { return false }
        return !_isOff(node)
    }

    /// Word's built-in definitions, which a styles part takes when its template is gone.
    /// Normal.dotm's Normal resolved through its defaults: +Body 12 pt, 0 before, 8 after, 1.16 lines (lab linkstyles NOTES). Only Normal is replaced; the file's Heading styles and defaults stay.
    static let _builtinNormal = "<w:style xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" w:type=\"paragraph\" w:default=\"1\" w:styleId=\"Normal\"><w:name w:val=\"Normal\"/><w:qFormat/><w:pPr><w:spacing w:after=\"160\" w:line=\"278\" w:lineRule=\"auto\"/></w:pPr><w:rPr><w:rFonts w:asciiTheme=\"minorHAnsi\" w:hAnsiTheme=\"minorHAnsi\" w:eastAsiaTheme=\"minorEastAsia\" w:cstheme=\"minorBidi\"/><w:sz w:val=\"24\"/><w:szCs w:val=\"24\"/></w:rPr></w:style>"

    static func _applyBuiltinStyles(_ styles: XNode) {
        guard let builtin = XNode.parse(Data(_builtinNormal.utf8)),
              let i = styles.children.firstIndex(where: { $0.name == "w:style" && $0["w:styleId"] == "Normal" }) else { return }
        styles.children[i] = builtin
    }

    static func _isOff(_ node: XNode) -> Bool {
        switch node["w:val"] {
        case "0", "false", "off": return true
        default: return false
        }
    }

    /// The theme's colours by scheme name ("accent2", "dk1", ...), set when a document is read.
    // (The settings' `m:defJc`: how a display equation without its own
    // `m:jc` stands; Word's default is centred.)
    nonisolated(unsafe) static var _mathDefaultJc: String? = nil
    /// `w:noExtraLineSpacing` of the document being read.
    nonisolated(unsafe) static var _exactAtAscent = false
    /// Set while a package is read whose styles' default Latin language is Korean (`w:lang w:val="ko…"`): Word for Windows then draws every
    /// Latin letter, digit and space in the run's East Asian face (Malgun Gothic where it names none, MS Mincho where it names a Latin-only one).
    /// Lab langko (2026-11-13, Word for Windows, xd f1b5cc8b): a run's own w:lang and w:noProof change nothing; only the style default does.
    nonisolated(unsafe) static var _latinLangKorean = false
    nonisolated(unsafe) static var _bidiLangHebrew = false
    nonisolated(unsafe) static var _themeColors: [String: (Int, Int, Int)] = [:]

    static func _themePalette(_ entries: [ZipEntry]) -> [String: (Int, Int, Int)] {
        guard let e = entries.first(where: { $0.name.hasPrefix("word/theme/") && $0.name.hasSuffix(".xml") }),
              let root = XNode.parse(e.data), let scheme = root.descendant("a:clrScheme") else { return [:] }
        var out: [String: (Int, Int, Int)] = [:]
        for c in scheme.children {
            guard c.name.hasPrefix("a:") else { continue }
            let name = String(c.name.dropFirst(2))
            var hex: String? = c.first("a:srgbClr")?["val"]
            if hex == nil { hex = c.first("a:sysClr")?["lastClr"] }
            if let h = hex, let v = Int(h, radix: 16) { out[name] = ((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF) }
        }
        out["tx1"] = out["dk1"]; out["bg1"] = out["lt1"]; out["tx2"] = out["dk2"]; out["bg2"] = out["lt2"]
        return out
    }

    /// A theme slot's colour for a page background, with `w:themeTint` / `w:themeShade` (hex bytes) applied to its HSL lightness.
    static func _themeBackground(_ slot: String, tint: String?, shade: String?) -> UInt32? {
        let name = ["text1": "tx1", "background1": "bg1", "text2": "tx2", "background2": "bg2"][slot] ?? slot
        guard let c = _themeColors[name] else { return nil }
        let r = Double(c.0) / 255, g = Double(c.1) / 255, b = Double(c.2) / 255
        let mx = max(r, g, b), mn = min(r, g, b)
        var l = (mx + mn) / 2, h = 0.0, sat = 0.0
        if mx != mn {
            let d = mx - mn
            sat = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
            h = mx == r ? (g - b) / d + (g < b ? 6 : 0) : mx == g ? (b - r) / d + 2 : (r - g) / d + 4
            h /= 6
        }
        if let t = tint, let v = Int(t, radix: 16) { l = l * Double(v) / 255 + (1 - Double(v) / 255) }
        else if let t = shade, let v = Int(t, radix: 16) { l *= Double(v) / 255 }
        func ch(_ p: Double, _ q: Double, _ t0: Double) -> Double {
            var t = t0; if t < 0 { t += 1 }; if t > 1 { t -= 1 }
            if t < 1.0 / 6 { return p + (q - p) * 6 * t }
            if t < 0.5 { return q }
            if t < 2.0 / 3 { return p + (q - p) * (2.0 / 3 - t) * 6 }
            return p
        }
        var out: (Double, Double, Double) = (l, l, l)
        if sat != 0 {
            let q = l < 0.5 ? l * (1 + sat) : l + sat - l * sat, p = 2 * l - q
            out = (ch(p, q, h + 1.0 / 3), ch(p, q, h), ch(p, q, h - 1.0 / 3))
        }
        func by(_ x: Double) -> UInt32 { UInt32(max(0, min(255, (x * 255).rounded()))) }
        return by(out.0) << 16 | by(out.1) << 8 | by(out.2)
    }

    /// A `w14:srgbClr` / `w14:schemeClr`'s colour with its tint, shade and saturation / luminance modifiers applied
    /// (tint toward white, shade toward black, the rest in HSL).
    static func _w14Color(_ node: XNode) -> (Int, Int, Int)? {
        var rgb: (Int, Int, Int)
        if node.name == "w14:srgbClr", let v = Int(node["w14:val"] ?? "", radix: 16) { rgb = ((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF) }
        else if node.name == "w14:schemeClr", let c = _themeColors[node["w14:val"] ?? ""] { rgb = c }
        else { return nil }
        var r = Double(rgb.0) / 255, g = Double(rgb.1) / 255, b = Double(rgb.2) / 255
        func hsl() -> (Double, Double, Double) {
            let mx = max(r, g, b), mn = min(r, g, b), l = (mx + mn) / 2
            guard mx != mn else { return (0, 0, l) }
            let d = mx - mn, s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
            let h = mx == r ? (g - b) / d + (g < b ? 6 : 0) : mx == g ? (b - r) / d + 2 : (r - g) / d + 4
            return (h / 6, s, l)
        }
        func setHSL(_ h: Double, _ s: Double, _ l: Double) {
            func f(_ p: Double, _ q: Double, _ t0: Double) -> Double {
                var t = t0; if t < 0 { t += 1 }; if t > 1 { t -= 1 }
                return t < 1 / 6 ? p + (q - p) * 6 * t : t < 1 / 2 ? q : t < 2 / 3 ? p + (q - p) * (2 / 3 - t) * 6 : p
            }
            if s == 0 { r = l; g = l; b = l; return }
            let q = l < 0.5 ? l * (1 + s) : l + s - l * s, p = 2 * l - q
            r = f(p, q, h + 1 / 3); g = f(p, q, h); b = f(p, q, h - 1 / 3)
        }
        for m in node.children {
            let v = (Double(m["w14:val"] ?? "") ?? 100000) / 100000
            switch m.name {
            case "w14:tint": r = r * v + (1 - v); g = g * v + (1 - v); b = b * v + (1 - v)
            case "w14:shade": r *= v; g *= v; b *= v
            case "w14:satMod": let (h, s, l) = hsl(); setHSL(h, min(1, s * v), l)
            case "w14:lumMod": let (h, s, l) = hsl(); setHSL(h, s, min(1, l * v))
            case "w14:lumOff": let (h, s, l) = hsl(); setHSL(h, s, min(1, max(0, l + v)))
            default: break
            }
        }
        func byte(_ x: Double) -> Int { Int((min(1, max(0, x)) * 255).rounded()) }
        return (byte(r), byte(g), byte(b))
    }

    /// `complexText` says whether the run's characters are complex-script
    /// ones (Arabic, Hebrew, ...): Word applies w:bCs/w:iCs/w:szCs to those
    /// characters only, so a Latin "Reino de España" inside an Arabic
    /// paragraph stays plain. nil falls back to the run's w:rtl.
    // A table style's run properties stand under the paragraph's style and
    // over the document's defaults: the cell's runs take each one the
    // Normal style leaves unsaid (its size apart: `tableSizes`). Read and
    // then dropped, a table style's w:kern left its cells' Latin pairs
    // unkerned where Word kerns them (lab asp's Times "11", 5.52pt in
    // Word's print, 5.56 ours), and its fonts and colour went the same way.
    static let _tableCharKeys: [(String, WritableKeyPath<CharStyle, String?>)] = [
        ("ascii", \.fontFamily), ("hAnsi", \.hAnsiFontFamily), ("eastAsia", \.eastAsiaFontFamily),
        ("cs", \.complexFontFamily), ("hint", \.fontHint),
    ]
    static let _tableCharNumbers: [(String, WritableKeyPath<CharStyle, Double?>)] = [
        ("kern", \.kerningFrom), ("spacing", \.letterSpacing), ("w", \.horizontalScale), ("position", \.raised),
    ]
    static func _takeTableChar(_ cell: inout CharStyle, _ table: CharStyle, normal: CharStyle) -> Set<String> {
        var took = Set<String>()
        for (name, k) in _tableCharKeys where cell[keyPath: k] == nil && normal[keyPath: k] == nil {
            // Normal naming one face for ascii and hAnsi stores hAnsi as nil: that is
            // a statement, not a gap, so the table style's hAnsi must not stand in
            // (dx2 d611e23b: Normal Arial, TableGrid Calibri; Word prints Arial).
            if name == "hAnsi", normal.fontFamily != nil { continue }
            if let v = table[keyPath: k] { cell[keyPath: k] = v; took.insert(name) }
        }
        for (name, k) in _tableCharNumbers where cell[keyPath: k] == nil && normal[keyPath: k] == nil {
            if let v = table[keyPath: k] { cell[keyPath: k] = v; took.insert(name) }
        }
        if took.contains("hAnsi") || took.contains("ascii") { cell.hAnsiNamedAsAscii = table.hAnsiNamedAsAscii }
        if cell.color == nil, normal.color == nil, !normal.off.contains(.autoColor), let c = table.color { cell.color = c; took.insert("color") }
        if !cell.bold, !normal.bold, table.bold { cell.bold = true; took.insert("bold") }
        if !cell.italic, !normal.italic, table.italic { cell.italic = true; took.insert("italic") }
        if !cell.smallCaps, !normal.smallCaps, table.smallCaps { cell.smallCaps = true; took.insert("smallCaps") }
        return took
    }
    /// A paragraph style that states a property takes it back from the
    /// table's.
    static func _dropTableChar(_ cell: inout CharStyle, stated named: CharStyle, took: Set<String>) {
        for (name, k) in _tableCharKeys where took.contains(name) && named[keyPath: k] != nil { cell[keyPath: k] = nil }
        for (name, k) in _tableCharNumbers where took.contains(name) && named[keyPath: k] != nil { cell[keyPath: k] = nil }
        if took.contains("color"), named.color != nil || named.off.contains(.autoColor) { cell.color = nil }
    }

    static func _charStyle(_ rPr: XNode, base: CharStyle, complexText: Bool? = nil, complexSize: Bool? = nil, thaiStyleSize: Bool = false, indicOnly: Bool = false, rtlLettersOnly: Bool = false) -> CharStyle {
        var cs = base
        // Complex-script bold, italic and size (w:bCs, w:iCs, w:szCs) are
        // what a right-to-left run is set in; rtl.docx's Arabic headings
        // say bCs alone and came back plain.
        var sawB = false, sawI = false, sawSz = false
        // Kept properties by name, so a run's own replaces its style's.
        var keptRun: [String: String] = [:]
        var bCs: Bool? = nil, iCs: Bool? = nil, szCs: Double? = nil
        for child in rPr.children {
            // (Effects the layout draws or ignores are kept as the file wrote them too, so a save does not drop them.)
            if Self._keptEffectNames.contains(child.name) { keptRun[child.name] = PptxXML.serialize(child) }
            switch child.name {
            case "w:bCs": bCs = !_isOff(child)
            case "w:iCs": iCs = !_isOff(child)
            case "w:szCs": szCs = Double(child["w:val"] ?? "").map { $0 / 2 }
            case "w:rPrChange":
                cs.formatChange = FormatChange(author: child["w:author"] ?? "", date: child["w:date"] ?? "",
                                               oldRPrXML: child.first("w:rPr").map { PptxXML.serialize($0) } ?? "<w:rPr/>")
            case "w:b": sawB = true; cs.bold = !_isOff(child); if cs.bold { cs.off.remove(.bold) } else { cs.off.insert(.bold) }
            case "w:i": sawI = true; cs.italic = !_isOff(child); if cs.italic { cs.off.remove(.italic) } else { cs.off.insert(.italic) }
            case "w:u":
                cs.underlineKind = nil; cs.underlineColor = nil; cs.underlineThemeAttrs = nil
                if let v = child["w:val"], v != "single", v != "none" { cs.underlineKind = v }
                if child["w:val"] != "none" {
                    cs.underlineColor = child["w:color"]
                    let theme = ["w:themeColor", "w:themeTint", "w:themeShade"].compactMap { k in child[k].map { " \(k)=\"\(_esc($0))\"" } }.joined()
                    cs.underlineThemeAttrs = theme.isEmpty ? nil : theme
                }
                cs.underline = child["w:val"] != "none"; if cs.underline { cs.off.remove(.underline) } else { cs.off.insert(.underline) }
            case "w:em": cs.emphasis = ["dot", "comma", "circle", "underDot"].contains(child["w:val"] ?? "") ? child["w:val"] : nil
            case "w:strike", "w:dstrike": cs.doubleStrike = child.name == "w:dstrike" && !_isOff(child); cs.strikethrough = !_isOff(child); if cs.strikethrough { cs.off.remove(.strikethrough) } else { cs.off.insert(.strikethrough) }
            case "w:caps": cs.caps = !_isOff(child); if cs.caps { cs.off.remove(.caps) } else { cs.off.insert(.caps) }
            case "w:vanish": cs.hidden = !_isOff(child); if cs.hidden { cs.off.remove(.hidden) } else { cs.off.insert(.hidden) }
            case "w:spacing": if let v = Double(child["w:val"] ?? "") { cs.letterSpacing = v / 20 }
            case "w14:glow":
                // (Word's glow: `w14:rad` in EMU, the colour a child with
                // an optional alpha in thousandths of a percent. Drawn as
                // the slide runs' glow is.)
                if let c = child.children.first(where: { $0.name == "w14:srgbClr" || $0.name == "w14:schemeClr" }), let rgb = _w14Color(c) {
                    let alpha = c.first("w14:alpha").flatMap { Double($0["w14:val"] ?? "") }.map { $0 / 100000 } ?? 1
                    // (w14:alpha is TRANSPARENCY, unlike a:alpha: Word reports Glow.Transparency 0.4 for 40000, 2026-11-24. Word draws none at all for a glow of alpha 100%: its lab print of wordglow.docx.)
                    if alpha >= 1 { break }
                    var glow = CharShadow(color: Color(argb: Int(((1 - alpha) * 255).rounded()), rgb.0, rgb.1, rgb.2),
                                          dx: 0, dy: 0, blur: (Double(child["w14:rad"] ?? "") ?? 0) / 12700)
                    glow.glow = true
                    cs.shadow = glow
                }
            case "w14:shadow":
                // (A run's shadow, `w14:dist` EMU out along `w14:dir` (sixty-thousandths of a degree), blurred by `w14:blurRad`:
                // bib-chernigovka's title, a 39001 EMU shadow at 91 degrees, 62% black.)
                if let c = child.children.first(where: { $0.name == "w14:srgbClr" || $0.name == "w14:schemeClr" }), let rgb = _w14Color(c) {
                    let alpha = c.first("w14:alpha").flatMap { Double($0["w14:val"] ?? "") }.map { $0 / 100000 } ?? 1
                    let dist = (Double(child["w14:dist"] ?? "") ?? 0) / 12700, dir = (Double(child["w14:dir"] ?? "") ?? 0) / 60000 * Double.pi / 180
                    cs.shadow = CharShadow(color: Color(argb: Int((alpha * 255).rounded()), rgb.0, rgb.1, rgb.2),
                                           dx: dist * cos(dir), dy: dist * sin(dir), blur: (Double(child["w14:blurRad"] ?? "") ?? 0) / 12700)
                    // (A shadow scaled to nothing both ways, `sx` and `sy` 0, is no shadow: dx2 fa1598ff's headings carry one and Word's
                    // print keeps their lines at the face's own height.)
                    if child["w14:sx"] == "0", child["w14:sy"] == "0" { cs.shadow?.scale = 0 }
                }
            case "w14:textOutline":
                if let w = Double(child["w14:w"] ?? ""), w > 0,
                   let c = child.first("w14:solidFill")?.children.first(where: { $0.name == "w14:srgbClr" || $0.name == "w14:schemeClr" }), let rgb = _w14Color(c) {
                    cs.textLine = CharOutline(color: Color(argb: 0xFF, rgb.0, rgb.1, rgb.2), width: w / 12700)
                }
            case "w14:textFill":
                if child.first("w14:noFill") != nil { cs.noFill = true }
                // (A solid fill with an alpha: Word draws the text at the OPPOSITE opacity, `w14:alpha` being a transparency there.
                // dx2 f22ada3a's NOTAT, 383838 at 87000, prints as pixel 230 grey, 13% ink, not 87%.)
                if let c = child.first("w14:solidFill")?.children.first(where: { $0.name == "w14:srgbClr" || $0.name == "w14:schemeClr" }),
                   let a = c.first("w14:alpha").flatMap({ Double($0["w14:val"] ?? "") }), let rgb = _w14Color(c) {
                    cs.color = Color(argb: Int(((1 - a / 100000) * 255).rounded()), rgb.0, rgb.1, rgb.2)
                    cs.off.remove(.autoColor)
                }
                // (A gradient fill drawn as the solid colour a quarter of the way along it: the text takes no shader yet. Word's print
                // of bib-chernigovka's title, accent2 tinted and shaded, is a bright orange; a solid fill keeps the run's own colour.)
                if let g = child.first("w14:gradFill"), let list = g.first("w14:gsLst") {
                    let stops: [(Double, (Int, Int, Int))] = list.children.compactMap { st in
                        guard st.name == "w14:gs", let pos = Double(st["w14:pos"] ?? ""), let c = st.children.first(where: { $0.name == "w14:srgbClr" || $0.name == "w14:schemeClr" }),
                              let rgb = _w14Color(c) else { return nil }
                        return (pos / 100000, rgb)
                    }.sorted { $0.0 < $1.0 }
                    let at = 0.25
                    if let a = stops.last(where: { $0.0 <= at }), let b = stops.first(where: { $0.0 >= at }) {
                        let t = b.0 > a.0 ? (at - a.0) / (b.0 - a.0) : 0
                        func mix(_ x: Int, _ y: Int) -> Int { Int((Double(x) + (Double(y) - Double(x)) * t).rounded()) }
                        cs.color = Color(argb: 0xFF, mix(a.1.0, b.1.0), mix(a.1.1, b.1.1), mix(a.1.2, b.1.2))
                        cs.off.remove(.autoColor)
                    }
                }
            case "w:rtl": cs.rightToLeft = !_isOff(child)
            case "w:kern": if let v = Double(child["w:val"] ?? "") { cs.kerningFrom = v / 2 }
            // (`w:cs`, the run's text taken as complex script, kept for
            // the layout too: see `RichLayout`'s wide spaces.)
            case "w:w", "w:position", "w:bdr", "w:lang", "w:em", "w:fitText", "w:snapToGrid", "w:eastAsianLayout", "w:cs":
                if child.name == "w:position", let v = Self.halfPointsOrMeasure(child["w:val"] ?? "") { cs.raised = v }
                // (The character scale, for the layout too.)
                if child.name == "w:w", let v = Double((child["w:val"] ?? "").replacingAll("%", with: "")), v > 0 {
                    // (100 is a scale too: it undoes the style's. zh-90e0cea8's
                    // "山东省市场监督管理局 发布" says 100 over its style's 135,
                    // and Word prints it at 14pt; read as none, it took the
                    // style's 135 and its line ran 35% wide.)
                    cs.horizontalScale = v / 100
                }
                keptRun[child.name] = PptxXML.serialize(child)
            case "w:smallCaps": cs.smallCaps = !_isOff(child); if cs.smallCaps { cs.off.remove(.smallCaps) } else { cs.off.insert(.smallCaps) }
            case "w:sz": sawSz = true; if let v = Double(child["w:val"] ?? "") { cs.fontSize = v / 2 }
            case "w:color":
                cs.colorTheme = nil
                if let hex = child["w:val"], hex.lowercased() != "auto", let v = Int(hex, radix: 16) {
                    cs.color = Color(argb: 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF)
                    let theme = ["w:themeColor", "w:themeTint", "w:themeShade"].compactMap { k in child[k].map { " \(k)=\"\(_esc($0))\"" } }.joined()
                    if !theme.isEmpty { cs.colorTheme = _hex(cs.color!) + theme }
                } else if child["w:val"]?.lowercased() == "auto" {
                    // "auto" is the text colour: a style based on a blue
                    // heading that says auto is black (65099's Edf Titre 3).
                    cs.color = nil
                    cs.off.insert(.autoColor)
                }
                if cs.color != nil { cs.off.remove(.autoColor) }
            case "w:highlight":
                cs.highlight = _highlight(child["w:val"] ?? "none")
                cs.shdSource = nil
            case "w:shd":
                if cs.highlight == nil, child["w:fill"] == nil || child["w:fill"]?.lowercased() == "auto", child["w:val"] != "nil" {
                    // An explicit no fill (or a pattern over none): kept for the save, drawn as nothing.
                    cs.shdSource = "auto#" + ["w:val", "w:color", "w:themeFill", "w:themeFillTint", "w:themeFillShade", "w:themeColor", "w:themeTint", "w:themeShade"]
                        .compactMap { k in child[k].map { " \(k)=\"\(_esc($0))\"" } }.joined()
                }
                if let hex = child["w:fill"], hex.lowercased() != "auto", let v = Int(hex, radix: 16), cs.highlight == nil {
                    cs.highlight = Color(argb: 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF)
                    cs.shdSource = hex.uppercased() + "#" + ["w:val", "w:color", "w:themeFill", "w:themeFillTint", "w:themeFillShade", "w:themeColor", "w:themeTint", "w:themeShade"]
                        .compactMap { k in child[k].map { " \(k)=\"\(_esc($0))\"" } }.joined()
                }
            case "w:rFonts":
                // A slot the element leaves out is inherited, not cleared
                // (a style's lone w:cs must not drop its Latin face).
                // The Latin face is w:ascii's. A run that names only w:hAnsi
                // (Chinese text usually does, beside w:eastAsia) keeps its
                // inherited ascii face: its digits and letters stay in
                // Times, and came back in the East Asian face otherwise.
                if let f = _family(child["w:ascii"] ?? "") { cs.fontFamily = f }
                if let f = _family(child["w:cs"] ?? "") { cs.complexFontFamily = f }
                if _family(child["w:ascii"] ?? "") != nil, child["w:hAnsi"] == nil { cs.hAnsiNamedAsAscii = false }
                if let h = _family(child["w:hAnsi"] ?? "") { cs.hAnsiFontFamily = (h == cs.fontFamily && child["w:ascii"] != nil) ? nil : h; cs.hAnsiNamedAsAscii = h == cs.fontFamily }
                else if child["w:ascii"] != nil, child["w:hAnsi"] == nil, base.hAnsiFontFamily == nil, base.fontFamily != nil, base.fontFamily != cs.fontFamily {
                    cs.hAnsiFontFamily = base.fontFamily   // ascii alone: hAnsi stays the inherited face
                }
                if let h = child["w:hint"] { cs.fontHint = h }
                if let f = _family(child["w:eastAsia"] ?? "") { cs.eastAsiaFontFamily = f }
                var themeAttrs = ""
                for k in ["asciiTheme", "hAnsiTheme", "eastAsiaTheme", "cstheme"] { if let v = child["w:" + k] { themeAttrs += " w:\(k)=\"\(_esc(v))\"" } }
                if _latinLangKorean, child["w:ascii"] != nil || child["w:hAnsi"] != nil || child["w:eastAsia"] != nil || child["w:eastAsiaTheme"] != nil {
                    let ea = cs.eastAsiaFontFamily
                    cs.fontFamily = ea.map { OfficeFonts.isEastAsianFace($0) ? $0 : "MS Mincho" } ?? "Malgun Gothic"
                    cs.hAnsiFontFamily = nil
                }
                if !themeAttrs.isEmpty { cs.fontTheme = _fontKey(cs) + "#" + themeAttrs }
                else if ["w:ascii", "w:hAnsi", "w:cs", "w:eastAsia"].contains(where: { child[$0] != nil }) { cs.fontTheme = nil }
            case "w:vertAlign":
                switch child["w:val"] {
                case "superscript": cs.script = .superscript
                case "subscript": cs.script = .subscript
                default: cs.script = .normal
                }
            default: break
            }
        }
        if !keptRun.isEmpty {
            var all = _keptRunProperties(base.keptXML)
            for (k, v) in keptRun { all[k] = v }
            cs.keptXML = (["w:shadow", "w:outline", "w:emboss", "w:imprint"] + ["w:bdr", "w:w", "w:position", "w:fitText", "w:cs", "w:em", "w:lang", "w:eastAsianLayout", "w:snapToGrid", "w:effect"] + Self._keptEffectList.filter { $0.hasPrefix("w14:") }).compactMap { all[$0] }.joined()
        }
        if let z = szCs { cs.complexFontSize = z }
        if bCs != nil { cs.boldWithoutBCs = false; cs.bCsFromStyle = bCs } else if sawB { cs.boldWithoutBCs = cs.bold }
        if complexText ?? cs.rightToLeft {
            // (A complex run's weight is its bCs even when the run also states b: af19d946's Heading3 run, b 0 / bCs, prints Devanagari in Nirmala UI Bold.)
            if let b = bCs { cs.bold = b; if b { cs.off.remove(.bold) } else { cs.off.insert(.bold) } }
            // (A run of Devanagari, Bengali, Gurmukhi or Gujarati letters only that carries the w:cs flag and states b with no bCs keeps the weight it inherited (a run without the flag, as in xd 77d6ca49's Nirmala UI, is bold): Word
            // prints dx2-class xd 745490897f9f's bold-marked Kokila words in regular Kokila.)
            // (A Hebrew or Arabic run of letters only, w:rtl with w:b and no bCs, is regular as well: xd 7d58f74e's Arial Hebrew paragraph, b without bCs, prints in ArialMT
            // at 11 pt, the words 2 pt narrower than our bold and a line one word shorter.)
            else if (indicOnly && _on(rPr.first("w:cs"))) || (rtlLettersOnly && _on(rPr.first("w:rtl"))), cs.bold, sawB ? !base.bold : cs.boldWithoutBCs { cs.bold = false; if base.off.contains(.bold) { cs.off.insert(.bold) } else { cs.off.remove(.bold) } }
            if !sawI, let i = iCs { cs.italic = i; if i { cs.off.remove(.italic) } else { cs.off.insert(.italic) } }
            // (The same for the slant: dx2 f0001d05's w:i + w:cs Kokila words (no iCs) print in upright Kokila, the face's regular widths.)
            else if indicOnly, sawI, iCs == nil, cs.italic, !base.italic, _on(rPr.first("w:cs")) { cs.italic = false; if base.off.contains(.italic) { cs.off.insert(.italic) } else { cs.off.remove(.italic) } }
            if !(complexSize ?? true) {}
            else if !sawSz, let z = szCs ?? cs.complexFontSize { cs.fontSize = z }
            // (A complex run that gives both sizes is set at szCs: the Arabic of ara-z4399437's even-page header, sz 9 / szCs 11, prints at 11.)
            else if sawSz, let z = szCs { cs.fontSize = z }
            else if sawSz, complexSize == true, cs.rightToLeft { cs.sizeFromStyleSzCs = true }
            // (A complex run with the w:cs flag and no size of its own is set at the szCs of its style or the defaults: dx2 27dc0c47's TH SarabunPSK title, docDefaults sz 22 / szCs 28, prints at 14.)
            else if !sawSz, thaiStyleSize, !cs.rightToLeft, cs.fontSize == nil { cs.sizeFromStyleSzCs = true }
        }
        return cs
    }

    static let _keptEffectList: [String] = ["w:shadow", "w:outline", "w:emboss", "w:imprint", "w:effect", "w14:glow", "w14:shadow", "w14:reflection", "w14:textOutline", "w14:textFill", "w14:scene3d", "w14:props3d", "w14:ligatures", "w14:numForm", "w14:numSpacing", "w14:stylisticSets", "w14:cntxtAlts"]
    static let _keptEffectNames = Set(_keptEffectList)
    /// A `CharStyle.keptXML` taken apart again, by element name.
    static func _keptRunProperties(_ xml: String?) -> [String: String] {
        guard let xml, let node = XNode.parse(Data(("<x xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" xmlns:w14=\"http://schemas.microsoft.com/office/word/2010/wordml\">" + xml + "</x>").utf8)) else { return [:] }
        var out: [String: String] = [:]
        for c in node.children { out[c.name] = PptxXML.serialize(c) }
        return out
    }

    static let highlightNames: [(String, Color)] = [
        ("yellow", Color(0xFFFFFF00)), ("green", Color(0xFF00FF00)), ("cyan", Color(0xFF00FFFF)),
        ("magenta", Color(0xFFFF00FF)), ("blue", Color(0xFF0000FF)), ("red", Color(0xFFFF0000)),
        ("darkBlue", Color(0xFF000080)), ("darkCyan", Color(0xFF008080)), ("darkGreen", Color(0xFF008000)),
        ("darkMagenta", Color(0xFF800080)), ("darkRed", Color(0xFF800000)), ("darkYellow", Color(0xFF808000)),
        ("darkGray", Color(0xFF808080)), ("lightGray", Color(0xFFC0C0C0)), ("black", Color(0xFF000000)),
        ("white", Color(0xFFFFFFFF)),
    ]

    static func _highlight(_ name: String) -> Color? {
        highlightNames.first { $0.0 == name }?.1
    }

    /// The font name as the file has it. Kept, not mapped: the face it
    /// draws with is `OfficeFonts.substitute`'s choice at render time, and
    /// the name goes back out unchanged on save.
    /// Every family a part names in a `w:rFonts` (ascii and hAnsi).
    /// Whether the document part holds Devanagari to Malayalam text (UTF-8 lead bytes E0 A4 to E0 B5).
    /// Whether the first run holding Devanagari names Mangal itself (ascii, hAnsi or cs): Word then draws every Devanagari run of the document in Mangal,
    /// even runs whose complex face is one Windows lacks (Arial), which would otherwise fall to Nirmala UI (dx2 88e26672; labs dpitch5-9).
    static func _firstDevanagariRunNamesMangal(_ data: Data) -> Bool { _firstRunNames(data, leads: [0xA4, 0xA5], face: "\"mangal\"") }
    static func _firstRunNames(_ data: Data, leads: [UInt8], face: String) -> Bool {
        let bytes = [UInt8](data)
        var i = 0
        while i + 1 < bytes.count { if bytes[i] == 0xE0, leads.contains(bytes[i + 1]) { break }; i += 1 }
        guard i + 1 < bytes.count else { return false }
        // The run's opening tag: the last "<w:r>" or "<w:r " before the first Devanagari byte; its properties run to the first "<w:t".
        var start = i
        while start > 0 {
            start -= 1
            if bytes[start] == 0x3C, start + 4 < bytes.count, bytes[start + 1] == 0x77, bytes[start + 2] == 0x3A, bytes[start + 3] == 0x72,
               bytes[start + 4] == 0x3E || bytes[start + 4] == 0x20 { break }
        }
        var stop = start
        while stop + 4 < i, !(bytes[stop] == 0x3C && bytes[stop + 1] == 0x77 && bytes[stop + 2] == 0x3A && bytes[stop + 3] == 0x74) { stop += 1 }
        let props = String(decoding: bytes[start ..< stop], as: UTF8.self).lowercased()
        return props.containsSubstring(face)
    }
    static func _hasIndicBytes(_ data: Data) -> Bool {
        let bytes = [UInt8](data)
        var i = 0
        while i + 1 < bytes.count { if bytes[i] == 0xE0, bytes[i + 1] >= 0xA4, bytes[i + 1] <= 0xB5 { return true }; i += 1 }
        return false
    }
    static func _declaredFonts(_ data: Data?) -> Set<String> {
        guard let data, let text = String(data: data, encoding: .utf8) else { return [] }
        var out = Set<String>()
        for attr in ["w:ascii=\"", "w:hAnsi=\""] {
            var search = text.startIndex
            while let r = text.rangeOfSubstring(attr, in: search ..< text.endIndex) {
                if let end = text[r.upperBound...].firstIndex(of: "\"") {
                    let name = String(text[r.upperBound ..< end])
                    if !name.isEmpty { out.insert(name) }
                    search = end
                } else { break }
            }
        }
        return out
    }

    static func _family(_ name: String) -> String? {
        let n = name.trimmingWhitespace()
        return n.isEmpty ? nil : n
    }

    // MARK: Writing

    /// A paragraph id as Word prints it: eight upper-case hex digits.
    static func _paraIdHex(_ id: UInt32) -> String {
        let hex = String(id, radix: 16, uppercase: true)
        return String(repeating: "0", count: max(0, 8 - hex.count)) + hex
    }

    static func write(_ source: RichDocument, pageSetup: PageSetup) throws -> Data {
        var doc = source
        doc.paragraphs.removeAll { $0.flowedEndnote != nil }
        _writeBackBoundValues(&doc)
        var rels: [(id: String, target: String)] = []
        var media: [ZipEntry] = []
        var mediaRels: [(id: String, target: String)] = []
        var keptRels = "", keptRelCount = 0
        var checkboxCount = 0   // FORMCHECKBOX fields written, for their names
        var keptDocPrCount = 100_000   // kept drawings' docPr ids start here, above the generated pictures'
        let commentsKept = doc.keptParts["word/comments.xml"] != nil
        var openComments: [String] = []
        var closedComments = Set<String>()   // a range id is started once; Word rejects a second start
        /// The end markers (and reference runs) of every open range not in
        /// `keep`, which are then closed for good.
        func closeComments(except keep: [String]) -> String {
            var out = ""
            for id in openComments where !keep.contains(id) {
                out += "<w:commentRangeEnd w:id=\"\(_esc(id))\"/><w:r><w:rPr><w:rStyle w:val=\"CommentReference\"/></w:rPr><w:commentReference w:id=\"\(_esc(id))\"/></w:r>"
                closedComments.insert(id)
            }
            openComments.removeAll { !keep.contains($0) }
            return out
        }
        /// The comment ids on the run after (`index`, `runIndex`): the next
        /// run of the paragraph, else the next paragraph's first.
        func commentsAfter(_ index: Int, _ runIndex: Int, in p: RichParagraph) -> [String] {
            if let next = p.runs[(runIndex + 1)...].first(where: { $0.length > 0 }) { return next.style.comments }
            guard index + 1 < doc.paragraphs.count else { return [] }
            let np = doc.paragraphs[index + 1]
            return (np.runs.first(where: { $0.length > 0 }) ?? np.runs.first)?.style.comments ?? []
        }
        var revisionCount = 0
        // Ids the file already uses and we keep as they are (kept header, footer and note parts, boxes and
        // pictures written from their own XML, bookmark markers): new revision and point-bookmark ids skip them,
        // so one id never names two annotations anywhere in the package.
        var takenAnnotationIDs = Set<Int>()
        for (name, data) in doc.keptParts where name.hasPrefix("word/") && name.hasSuffix(".xml") && name != "word/document.xml" && name != "word/comments.xml" {
            takenAnnotationIDs.formUnion(RichDocumentController._annotationIds(in: String(decoding: data, as: UTF8.self)))
        }
        for p in doc.paragraphs {
            for img in [p.image].compactMap({ $0 }) + Array(p.inlineImages.values) {
                if let x = img.sourceXML { takenAnnotationIDs.formUnion(RichDocumentController._annotationIds(in: x)) }
            }
            for m in p.bookmarkMarkers { if let n = Int(m.id) { takenAnnotationIDs.insert(n) } }
        }
        func nextRevisionID() -> Int {
            repeat { revisionCount += 1 } while takenAnnotationIDs.contains(revisionCount)
            return revisionCount
        }
        var usedExtensions: Set<String> = []
        func relId(for link: String) -> String {
            if let r = rels.first(where: { $0.target == link }) { return r.id }
            let id = "rIdLink\(rels.count + 1)"
            rels.append((id, link))
            return id
        }

        // Word numbers per numId across the document, so every list id
        // and every anonymous run of numbered items gets a numId of its
        // own; bullets without an id share one.
        // A list read from a file keeps its numId: text boxes and notes
        // kept verbatim still name it (60316's ">" bullets came back as
        // "1." under a renumbered id). Our own bullet and decimal lists
        // and anonymous runs take ids above the file's.
        var numIds: [String: Int] = [:]        // list id or "run<n>" → numId
        var numFormats: [Int: [Int: ListLevelFormat]] = [:]
        var numKinds: [Int: ListKind] = [:]
        var numIdOf: [Int] = Array(repeating: 0, count: doc.paragraphs.count)
        let fileIds = doc.listFormats.keys.compactMap { Int($0) }
        let bulletId = (fileIds.max() ?? 0) + 1
        let decimalId = bulletId + 1
        var nextId = decimalId + 1
        for (id, formats) in doc.listFormats {
            guard let n = Int(id) else { continue }
            numIds[id] = n
            numFormats[n] = formats
            numKinds[n] = formats[0]?.format == .bullet ? .bullet : .numbered
        }
        var runId = 0
        var runOpen = false
        for (i, p) in doc.paragraphs.enumerated() {
            guard let kind = p.style.list else { runOpen = false; continue }
            if let id = p.style.listId {
                if numIds[id] == nil {
                    numIds[id] = nextId
                    nextId += 1
                    numFormats[numIds[id]!] = doc.listFormats[id] ?? [:]
                    numKinds[numIds[id]!] = kind
                }
                if doc.listFormats[id] == nil { numKinds[numIds[id]!] = kind }
                numIdOf[i] = numIds[id]!
                runOpen = false
            } else if kind == .bullet {
                numIdOf[i] = bulletId
                runOpen = false
            } else {
                if !runOpen { runId += 1; numIds["run\(runId)"] = nextId; nextId += 1; runOpen = true }
                let n = numIds["run\(runId)"]!
                numKinds[n] = .numbered
                numIdOf[i] = n
            }
        }

        var body = ""
        /// A kept fragment with its relationships under fresh ids and its
        /// drawings' docPr ids made unique.
        func keptFragmentXML(_ xml: String, _ rels: [KeptRel]) -> String {
            var frag = _renumberDocPr(xml, next: &keptDocPrCount)
            for rel in rels {
                // A relationship the fragment never names (its old id appears nowhere in the markup, in any
                // attribute) is a leftover of an edit: not written. One the file gave and the markup names
                // by any attribute stays, even where we do not read that attribute.
                // Only kinds this writer re-creates (picture, link, embedded object, chart, diagram) are ever dropped:
                // other kinds are found by type or from other parts (template, glossary, settings...) and stay.
                let kind = String(rel.type.split(separator: "/").last ?? "")
                let droppable = ["image", "hyperlink", "oleObject", "chart", "diagramData", "diagramLayout", "diagramQuickStyle", "diagramColors", "diagramDrawing"].contains(kind)
                if droppable, !xml.containsSubstring("\"\(rel.id)\"") { continue }
                keptRelCount += 1
                let nid = "rIdKept\(keptRelCount)"
                for attr in _relationshipAttributes {
                    frag = frag.replacingAll("\(attr)=\"\(rel.id)\"", with: "\(attr)=\"\(nid)\"")
                }
                keptRels += "<Relationship Id=\"\(nid)\" Type=\"\(_esc(rel.type))\" Target=\"\(_esc(rel.target))\"\(rel.external ? " TargetMode=\"External\"" : "")/>"
            }
            return frag
        }
        var writtenBookmarks = Set<String>()   // a name is written once (a split paragraph carries its twice)
        var nextPointBookmarkID = 100_000
        var rangedBookmarkNames = Set<String>(), rangedBookmarkIDs = Set<String>(), seenBookmarkNames = Set<String>()
        var openBookmarks: [String: (paragraph: Int, marker: Int, name: String)] = [:]
        var bookmarkMarkersToWrite: [Int: Set<Int>] = [:]
        for (i, paragraph) in doc.paragraphs.enumerated() {
            for (j, marker) in paragraph.bookmarkMarkers.enumerated() {
                if let name = marker.name {
                    // Pasting a paragraph can copy its markers too. A
                    // bookmark name/id still defines only one range.
                    guard !seenBookmarkNames.contains(name), !rangedBookmarkIDs.contains(marker.id) else { continue }
                    seenBookmarkNames.insert(name); rangedBookmarkIDs.insert(marker.id)
                    openBookmarks[marker.id] = (i, j, name)
                } else if let start = openBookmarks.removeValue(forKey: marker.id) {
                    rangedBookmarkNames.insert(start.name)
                    bookmarkMarkersToWrite[start.paragraph, default: []].insert(start.marker)
                    bookmarkMarkersToWrite[i, default: []].insert(j)
                }
            }
        }
        /// Whether paragraph `i`'s page break goes back as the break
        /// character that ended the paragraph before it, as the file had
        /// it: Word drops the space before a paragraph that follows one
        /// (a training handbook's chapter titles, 6pt before, sat 6pt low
        /// on each of their pages under "page break before"). Also where
        /// the paragraph before ends a section: a break character there
        /// is a page of its own (a chemicals list's blank page 12).
        func breakRidesOnPrevious(_ i: Int) -> Bool {
            guard i > 0, i < doc.paragraphs.count else { return false }
            let p = doc.paragraphs[i], prev = doc.paragraphs[i - 1]
            let sameCell = p.cell?.table == prev.cell?.table && p.cell?.row == prev.cell?.row && p.cell?.column == prev.cell?.column
            return p.style.pageBreakBefore && p.style.breakEndsPrevious && !p.style.pageBreakInline && sameCell
                && prev.image == nil && prev.keptTable == nil && p.keptTable == nil
        }
        // Block-level content controls (W-RV-3): written only when the start and the end are both still there, start first.
        var pairedBlockControls = Set<Int>()
        do {
            var open = Set<Int>()
            for q in doc.paragraphs {
                for c in q.blockControlsBefore where c.isStart { open.insert(c.id) }
                for c in q.blockControlsAfter where open.contains(c.id) { pairedBlockControls.insert(c.id) }
            }
        }
        /// The control starts / ends that go around paragraph `index`; `table`: those that wrap a whole table (written
        /// outside its cells) rather than the paragraphs inside one.
        func blockOpen(_ index: Int, table: Bool) -> String {
            doc.paragraphs[index].blockControlsBefore.filter {
                pairedBlockControls.contains($0.id) && $0.aroundTable == table
            }.compactMap { $0.properties.map { "<w:sdt>\($0)<w:sdtContent>" } }.joined()
        }
        func blockClose(_ index: Int, table: Bool) -> String {
            doc.paragraphs[index].blockControlsAfter.filter {
                pairedBlockControls.contains($0.id) && $0.aroundTable == table
            }.map { _ in "</w:sdtContent></w:sdt>" }.joined()
        }
        func paragraphXML(_ index: Int) -> String {
            var p = doc.paragraphs[index]
            // Boundaries can fall inside a normalized run. Split only the
            // serialization view, keeping the document's run invariants.
            // (A content control is written only when both its ends are in this paragraph, start first.)
            var controlStarts = Set<Int>()
            var pairedControls = Set<Int>()
            for m in p.controlMarkers { if m.isStart { controlStarts.insert(m.id) } else if controlStarts.contains(m.id) { pairedControls.insert(m.id) } }
            let controlsHere = p.controlMarkers.filter { pairedControls.contains($0.id) }
            let cuts = Set(p.bookmarkMarkers.map { max(0, min($0.offset, p.length)) } + controlsHere.map { max(0, min($0.offset, p.length)) })
            if !cuts.isEmpty {
                var split: [Run] = [], offset = 0
                for run in p.runs {
                    let end = offset + run.length
                    for cut in cuts.filter({ $0 > offset && $0 < end }).sorted() {
                        split.append(Run(length: cut - offset, style: run.style)); offset = cut
                    }
                    split.append(Run(length: end - offset, style: run.style)); offset = end
                }
                p.runs = split
            }
            func bookmarkXML(at offset: Int) -> String {
                p.bookmarkMarkers.enumerated().filter {
                    bookmarkMarkersToWrite[index]?.contains($0.offset) == true && max(0, min($0.element.offset, p.length)) == offset
                }.map { _, marker in
                    if let name = marker.name {
                        return "<w:bookmarkStart w:id=\"\(_esc(marker.id))\" w:name=\"\(_esc(name))\"/>"
                    }
                    return "<w:bookmarkEnd w:id=\"\(_esc(marker.id))\"/>"
                }.joined()
            }
            func controlXML(at offset: Int) -> String {
                controlsHere.filter { max(0, min($0.offset, p.length)) == offset }.map { marker in
                    marker.properties.map { "<w:sdt>\($0)<w:sdtContent>" } ?? "</w:sdtContent></w:sdt>"
                }.joined()
            }
            var body = ""
            var pPr = ""
            // A paragraph of a file keeps the id its style has in that file (Heading 1 is "2" there, "HTML Preformatted"
            // is "HTML"): the file defines it, and the save must not add a second definition under our id.
            func fileId(_ ours: String) -> String { doc.readFromFile ? (doc.styleSource[ours] ?? ours) : ours }
            if let h = p.style.heading { pPr += "<w:pStyle w:val=\"\(_esc(fileId("Heading\(min(h, 6))")))\"/>" }
            else if let n = p.style.named, doc.styles[n] != nil { pPr += "<w:pStyle w:val=\"\(_esc(fileId(n)))\"/>" }
            else if p.style.list != nil, !doc.readFromFile { pPr += "<w:pStyle w:val=\"ListParagraph\"/>" }
            // (Said as off where the file's style keeps and this one does not.)
            let styled = doc.readFromFile ? (p.style.heading.map { "Heading\(min($0, 6))" } ?? p.style.named).flatMap { doc.styles[$0]?.paragraph } : nil
            if p.style.keepNext { pPr += "<w:keepNext/>" } else if styled?.keepNext == true { pPr += "<w:keepNext w:val=\"0\"/>" }
            if p.style.keepLines { pPr += "<w:keepLines/>" } else if styled?.keepLines == true { pPr += "<w:keepLines w:val=\"0\"/>" }
            // A section break written on the paragraph before already
            // starts this one on a new page; saying it again here, with the
            // paragraph first in a table, gave Word an empty page per
            // section (bug65649: 15 sections, five pages of nothing).
            let afterSectionBreak: Bool = {
                guard index > 0, let prev = Optional(doc.paragraphs[index - 1]), prev.cell == nil,
                      let sect = prev.style.sectionXML else { return false }
                return prev.style.sectionBreaksPage ?? !sect.containsSubstring("w:val=\"continuous\"")
            }()
            let columnBreak = p.style.pageBreakBefore && p.style.pageBreakInline && p.style.columnBreak
            // (In a table cell too: Word ignores a break character there,
            // and honours "page break before" by moving the row — a
            // handbook's last table row went to the next page.)
            let inlineBreak = p.style.pageBreakBefore && p.style.pageBreakInline && (!afterSectionBreak || columnBreak)
            if p.style.pageBreakBefore && !afterSectionBreak && !inlineBreak && !breakRidesOnPrevious(index) { pPr += "<w:pageBreakBefore/>" }
            if let frame = p.style.frameXML { pPr += frame }
            if !p.style.widowControl { pPr += "<w:widowControl w:val=\"0\"/>" }
            if p.style.list != nil {
                pPr += "<w:numPr><w:ilvl w:val=\"\(p.style.listLevel)\"/><w:numId w:val=\"\(numIdOf[index])\"/></w:numPr>"
            }
            // (A paragraph that has neither under a style that has one says
            // so: its style writes its own now.)
            let ownStyle = (p.style.heading.flatMap { doc.styles["Heading\(min($0, 6))"] } ?? p.style.named.flatMap { doc.styles[$0] })?.paragraph
            if let b = p.style.borders { pPr += _bordersXML(b) }
            else if ownStyle?.borders != nil { pPr += "<w:pBdr><w:top w:val=\"nil\"/><w:left w:val=\"nil\"/><w:bottom w:val=\"nil\"/><w:right w:val=\"nil\"/></w:pBdr>" }
            if p.style.fill == nil, let t = p.style.fillAttrs, t.hasPrefix("auto#") { pPr += "<w:shd\(t.dropFirst(5)) w:fill=\"auto\"/>" }
            else if p.style.fill == nil, ownStyle?.fill != nil { pPr += "<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"auto\"/>" }
            if let fill = p.style.fill { pPr += _paraShdXML(fill, p.style.fillAttrs) }
            if p.style.rightToLeft { pPr += "<w:bidi/>" }
            else if p.style.named.flatMap({ doc.styles[$0] })?.paragraph.rightToLeft ?? false { pPr += "<w:bidi w:val=\"0\"/>" }
            pPr += _tabsXML(p.style.tabStops, under: ownStyle?.tabStops ?? [])
            // Spacing spelled out on every paragraph, so that Word and we
            // lay the file out alike whatever its defaults say.
            pPr += _eastAsianSwitchesXML(p.style)
            // A paragraph of a style made in the app that still holds the style's
            // own spacing, indents and alignment says none of it: the style
            // does, so a later Modify Style in Word reaches it.
            let ownSheet = !doc.readFromFile && p.style.heading == nil && p.style.list == nil
                ? p.style.named.flatMap { doc.styles[$0] }?.paragraph : nil
            // A paragraph of a file whose spacing is just what its style (or
            // Normal) gives it says none: the file never wrote it, and writing
            // it bakes the style's numbers into the body, where a later style
            // change in Word no longer reaches it.
            let fileSheet: RichParagraphStyle? = doc.readFromFile
                ? (p.style.heading.flatMap { doc.styles["Heading\(min($0, 6))"] } ?? p.style.named.flatMap { doc.styles[$0] } ?? doc.styles["Normal"])?.paragraph : nil
            func holds(_ k: KeyPath<RichParagraphStyle, Double>) -> Bool { ownSheet.map { $0[keyPath: k] == p.style[keyPath: k] } ?? false }
            let inheritsSpacing = ownSheet != nil && holds(\.spaceBefore) && holds(\.spaceAfter) && holds(\.lineSpacing)
                && ownSheet!.lineHeightPoints == p.style.lineHeightPoints && !p.style.spaceBeforeAuto && !p.style.spaceAfterAuto
                && !ownSheet!.spaceBeforeAuto && !ownSheet!.spaceAfterAuto
            let inheritsInd = ownSheet != nil && holds(\.indentLeft) && holds(\.indentRight) && holds(\.firstLineIndent)
            if !inheritsSpacing {
                let under = (p.style.heading.flatMap { doc.styles["Heading\(min($0, 6))"] } ?? p.style.named.flatMap { doc.styles[$0] })?.paragraph
                let plain = _spacingXML(p.style, under: under)
                let withEA = _withEastAsian(plain, "w:spacing", _eastAsianSpacing, p.style)
                pPr += withEA == plain ? _spacingXML(p.style, under: under, omittingWhatItsStyleSays: fileSheet) : withEA
            }
            // Indents the style sets and the paragraph unsets are written
            // as zero: IllustrativeCases' Body Text Indent hangs 0.75in
            // into the margin and every paragraph of it says left 0.
            let sheetEntry = p.style.heading.flatMap { doc.styles["Heading\(min($0, 6))"] } ?? p.style.named.flatMap { doc.styles[$0] }
            let sp = sheetEntry?.paragraph
            var ind = ""
            if p.style.list != nil {
                if let own = p.style.listIndentLeft { ind += " w:left=\"\(Int((own * 20).rounded()))\"" }
            } else if p.style.indentLeft != 0 || (sp?.indentLeft ?? 0) != 0 {
                ind += " w:left=\"\(Int(p.style.indentLeft * 20))\""
            }
            if p.style.indentRight != 0 || (sp?.indentRight ?? 0) != 0 { ind += " w:right=\"\(Int(p.style.indentRight * 20))\"" }
            if p.style.list != nil, let own = p.style.listFirstLine {
                // A list paragraph's own first line, zero included, over
                // its level's hanging (bug65649's centred numbered headings
                // say left 0, firstLine 0 under a level hanging 375).
                ind += own < 0 ? " w:hanging=\"\(Int((-own * 20).rounded()))\"" : " w:firstLine=\"\(Int((own * 20).rounded()))\""
            } else if p.style.firstLineIndent > 0 { ind += " w:firstLine=\"\(Int(p.style.firstLineIndent * 20))\"" }
            else if p.style.firstLineIndent < 0 { ind += " w:hanging=\"\(Int(-p.style.firstLineIndent * 20))\"" }
            else if (sp?.firstLineIndent ?? 0) != 0 { ind += " w:firstLine=\"0\" w:hanging=\"0\"" }
            if !inheritsInd { pPr += _withEastAsian(ind.isEmpty ? "" : "<w:ind\(ind)/>", "w:ind", _eastAsianIndents, p.style) }
            if p.style.contextualSpacing { pPr += "<w:contextualSpacing/>" }
            switch p.style.alignment {
            case .left:
                // Left under a style that centres has to say so.
                if let a = sheetEntry?.paragraph.alignment, a != .left { pPr += "<w:jc w:val=\"left\"/>" }
            case .center: if ownSheet?.alignment != .center { pPr += "<w:jc w:val=\"center\"/>" }
            case .right: if ownSheet?.alignment != .right { pPr += "<w:jc w:val=\"right\"/>" }
            case .justify: pPr += "<w:jc w:val=\"\(_esc(p.style.eastAsian["w:jc"] ?? "both"))\"/>"
            }
            if let v = p.style.eastAsian["w:textAlignment"] { pPr += "<w:textAlignment w:val=\"\(_esc(v))\"/>" }
            if let div = p.style.divId, doc.keptParts["word/webSettings.xml"] != nil { pPr += "<w:divId w:val=\"\(_esc(div))\"/>" }
            // The paragraph mark's own run properties: a tracked change to
            // the mark, and — for an empty paragraph — its look, which is
            // what gives the empty line its height (Word honours it in
            // every spelling, probed 2026-10-09; bib-chernigovka's cover).
            var markRPr = ""
            if let rev = p.style.markRevision {
                _ = nextRevisionID()
                let tag = rev.kind == .inserted ? "w:ins" : "w:del"
                markRPr += "<\(tag) w:id=\"\(revisionCount)\" w:author=\"\(_esc(rev.author.isEmpty ? "Author" : rev.author))\"\(rev.date.isEmpty ? "" : " w:date=\"\(_esc(rev.date))\"")/>"
            }
            let anchorOnly = p.image?.sourceXML?.containsSubstring("<wp:anchor") ?? false
            if p.text.isEmpty, p.image == nil || anchorOnly, let first = p.runs.first {
                markRPr += _rPrXML({ var m = first.style; m.origRPr = nil; m.origExtras = nil; return m }(), fileFonts: doc.fileFonts)
            } else if let mark = p.style.mark {
                // The mark's own look on a paragraph with text: a list
                // number is formatted with it, and a hidden mark over
                // hidden text makes Word show no line and no border.
                markRPr += _rPrXML({ var m = mark; m.origRPr = nil; m.origExtras = nil; return m }(), fileFonts: doc.fileFonts)
            } else if p.style.markHidden {
                markRPr += "<w:vanish/>"
            }
            if !markRPr.isEmpty { pPr += "<w:rPr>\(markRPr)</w:rPr>" }
            if let sect = p.style.sectionXML, p.cell == nil, index < doc.paragraphs.count - 1 { pPr += keptFragmentXML(Self._sectionXML(sect, patchedTo: p.style.sectionPage), p.style.sectionRels) }
            body += "<w:p\(p.id != 0 ? " w14:paraId=\"\(_paraIdHex(p.id))\"" : "")><w:pPr>\(pPr)</w:pPr>"
            // W-FD-2: the table of contents field opens in this paragraph; its entries are the paragraphs that follow.
            if let toc = p.style.contentsStart {
                body += "<w:r><w:fldChar w:fldCharType=\"begin\"/></w:r><w:r><w:instrText xml:space=\"preserve\"> \(_esc(toc)) </w:instrText></w:r><w:r><w:fldChar w:fldCharType=\"separate\"/></w:r>"
            }
            for name in p.bookmarks where !rangedBookmarkNames.contains(name) && writtenBookmarks.insert(name).inserted {
                // (Numbered clear of any a kept table's own XML carries.)
                repeat { nextPointBookmarkID += 1 } while rangedBookmarkIDs.contains(String(nextPointBookmarkID)) || takenAnnotationIDs.contains(nextPointBookmarkID)
                let id = nextPointBookmarkID
                body += "<w:bookmarkStart w:id=\"\(id)\" w:name=\"\(_esc(name))\"/><w:bookmarkEnd w:id=\"\(id)\"/>"
            }
            if inlineBreak {
                // In its own run's look: an indent counted in characters
                // is measured by the paragraph's first run, which the
                // break is (a 1.5-character indent under a 16pt title came
                // back 6pt short behind a bare break).
                body += "<w:r>\(p.style.breakRunPropertiesXML ?? "")<w:br w:type=\"\(columnBreak ? "column" : "page")\"/></w:r>"
            }
            /// A picture or kept object as a run's content.
            func drawingXML(_ image: ImageAttachment) -> String {
                var image = image
                if image.altText != image.sourceAltText, let xml = image.sourceXML, image.name != "m:oMath", image.name != "m:oMathPara" {
                    image.sourceXML = Self._drawingWithAltText(xml, image.altText)
                    image.sourceAltText = image.altText
                }
                var turnedNow: Bool? = nil
                if image.rotation != image.sourceRotation, let xml = image.sourceXML, image.name != "m:oMath", image.name != "m:oMathPara" {
                    image.sourceXML = Self._drawingWithRotation(xml, image.rotation)
                    image.sourceRotation = image.rotation
                    turnedNow = RichLayout._quarterTurned(image)
                }
                if image.crop != image.sourceCrop, let xml = image.sourceXML, image.name != "m:oMath", image.name != "m:oMathPara" {
                    image.sourceXML = Self._drawingWithCrop(xml, image.crop)
                    image.sourceCrop = image.crop
                }
                let unresized = image.sourceWidth == nil || (image.sourceWidth == image.width && image.sourceHeight == image.height)
                // (An equation stands in the paragraph itself, not in a run.)
                if let xml = image.sourceXML, image.name == "m:oMath" || image.name == "m:oMathPara" {
                    return keptFragmentXML(xml, image.sourceRels)
                }
                if let xml = image.sourceXML, !unresized || image.sourceWidth == nil,
                   let patched = Self._resizedDrawingXML(xml, width: image.width, height: image.height, sourceWidth: image.sourceWidth, sourceHeight: image.sourceHeight, turned: turnedNow) {
                    // (Resized: the size is patched in the kept markup, which keeps everything else the file said.)
                    return "<w:r>\(image.sourceRunPropertiesXML ?? "")\(keptFragmentXML(patched.xml, image.sourceRels))</w:r>"
                }
                if let xml = image.sourceXML, unresized {
                    // With the run's own properties: bug59058's thumbnails
                    // stand in a bordered 13pt run, a point taller each.
                    return "<w:r>\(image.sourceRunPropertiesXML ?? "")\(keptFragmentXML(xml, image.sourceRels))</w:r>"
                }
                // A name no kept part and no earlier picture uses: a kept
                // header's media/image1.png was being dropped for the body's
                // own image1.png (issue_51265_3's header showed the wrong
                // picture), and counting from the media count after skipping
                // a name wrote the same name twice (drawing.docx: two
                // image2.png entries, which Word calls unreadable).
                var n = media.count + 1
                while doc.keptParts.keys.contains(where: { $0.hasPrefix("word/media/image\(n).") })
                    || media.contains(where: { $0.name.hasPrefix("word/media/image\(n).") }) { n += 1 }
                let ext = image.fileExtension
                usedExtensions.insert(ext)
                let name = "image\(n).\(ext)"
                media.append(ZipEntry(name: "word/media/\(name)", data: image.data))
                let rid = "rIdImage\(n)"
                mediaRels.append((rid, "media/\(name)"))
                // (A picture turned a quarter stands in its turned box; the file holds the unturned frame.)
                let quarter = RichLayout._quarterTurned(image)
                let cx = Int((quarter ? image.height : image.width) * 12700), cy = Int((quarter ? image.width : image.height) * 12700)
                let turn: String = {
                    let d = (image.rotation.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
                    return d == 0 ? "" : " rot=\"\(Int((d * 60000).rounded()))\""
                }()
                return "<w:r><w:drawing><wp:inline distT=\"0\" distB=\"0\" distL=\"0\" distR=\"0\"><wp:extent cx=\"\(cx)\" cy=\"\(cy)\"/><wp:docPr id=\"\(n)\" name=\"Picture \(n)\"\(image.altText.isEmpty ? "" : " descr=\"\(Self._esc(image.altText))\"")/><a:graphic xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\"><a:graphicData uri=\"http://schemas.openxmlformats.org/drawingml/2006/picture\"><pic:pic xmlns:pic=\"http://schemas.openxmlformats.org/drawingml/2006/picture\"><pic:nvPicPr><pic:cNvPr id=\"0\" name=\"\(name)\"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed=\"\(rid)\"/>\(Self._srcRectXML(image.crop))<a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm\(turn)><a:off x=\"0\" y=\"0\"/><a:ext cx=\"\(cx)\" cy=\"\(cy)\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r>"
            }
            if let image = p.image {
                body += drawingXML(image) + "</w:p>"
                return body
            }
            var pos = 0
            let utf16 = p.text.utf16
            let boxRanges = p.checkBoxes.map(\.range)   // a content-control check box shows its glyph as text, not as a legacy form field
            // (Runs of the same target that follow each other share one w:hyperlink, as Word writes an entry.)
            var linkOpen = "", linkClosedAt = -1
            for (runIndex, run) in p.runs.enumerated() where run.length > 0 {
                body += bookmarkXML(at: pos) + controlXML(at: pos)
                let a = utf16.index(utf16.startIndex, offsetBy: pos)
                let b = utf16.index(a, offsetBy: run.length)
                let piece = String(utf16[a ..< b]) ?? ""
                pos += run.length
                let s = run.style
                if let id = s.inlineImage, let image = p.inlineImages[id] {
                    body += drawingXML(image)
                    continue
                }
                var changeId: Int? = nil
                if s.formatChange != nil { changeId = nextRevisionID() }
                var rPr = _rPrXML(s, fileFonts: doc.fileFonts, changeId: changeId)
                if let note = s.note, doc.keptParts[note.kind == .footnote ? "word/footnotes.xml" : "word/endnotes.xml"] != nil {
                    // The mark's number is Word's to show; the run carries
                    // only the reference (and its custom mark text, if any),
                    // with its own look — size and font decide where the
                    // line wraps.
                    let tag = note.kind == .footnote ? "w:footnoteReference" : "w:endnoteReference"
                    let st = doc.keptCharacterStyleIds[note.kind == .footnote ? "footnote reference" : "endnote reference"]
                        ?? (note.kind == .footnote ? "FootnoteReference" : "EndnoteReference")
                    // (A custom mark is the one the reader tagged with U+200B; a roman or letter label is Word's own numbering.)
                    let custom = piece.contains("\u{200B}" as Character) ? piece.filter { $0 != "\u{200B}" } : ""
                    // (A mark the file set on the baseline keeps it, under
                    // the reference style's superscript.)
                    if s.script != .superscript { rPr += "<w:vertAlign w:val=\"baseline\"/>" }
                    else { rPr = rPr.replacingAll("<w:vertAlign w:val=\"superscript\"/>", with: "") }   // (the reference style raises it)
                    body += "<w:r><w:rPr>\(rPr.hasPrefix("<w:rStyle ") ? "" : "<w:rStyle w:val=\"\(st)\"/>")\(rPr)</w:rPr>"
                    body += custom.isEmpty ? "<\(tag) w:id=\"\(note.id)\"/>" : "<\(tag) w:customMarkFollows=\"1\" w:id=\"\(note.id)\"/>\(_text(custom))"
                    body += "</w:r>"
                    continue
                }
                if s.link != nil, s.linkField == nil, !s.linkKeepsLook, !rPr.hasPrefix("<w:rStyle ") { rPr = "<w:rStyle w:val=\"\(_esc(doc.keptCharacterStyleIds["hyperlink"] ?? "Hyperlink"))\"/>" + rPr }
                let rPrXML = rPr.isEmpty ? "" : "<w:rPr>\(rPr)</w:rPr>"
                var runXML = ""
                let isBox: (Character) -> Bool = { $0 == "\u{2610}" || $0 == "\u{2612}" }
                if s.revision?.kind != .deleted, piece.contains(where: isBox),
                   !boxRanges.contains(where: { $0.lowerBound <= pos - run.length && pos - run.length < $0.upperBound }) {
                    // A checkbox glyph goes back as the form field it came
                    // from (form_footnotes' 29): the glyph's fallback font
                    // made every line it sat on taller than Word's.
                    var text = ""
                    func flush() { if !text.isEmpty { runXML += "<w:r>\(rPrXML)\(_text(text))</w:r>"; text = "" } }
                    for ch in piece {
                        if isBox(ch) {
                            flush()
                            checkboxCount += 1
                            runXML += "<w:r>\(rPrXML)<w:fldChar w:fldCharType=\"begin\"><w:ffData><w:name w:val=\"Check\(checkboxCount)\"/><w:enabled/><w:calcOnExit w:val=\"0\"/><w:checkBox><w:sizeAuto/><w:default w:val=\"\(ch == "\u{2612}" ? 1 : 0)\"/></w:checkBox></w:ffData></w:fldChar></w:r>"
                            runXML += "<w:r>\(rPrXML)<w:instrText xml:space=\"preserve\"> FORMCHECKBOX </w:instrText></w:r><w:r>\(rPrXML)<w:fldChar w:fldCharType=\"end\"/></w:r>"
                        } else {
                            text.append(ch)
                        }
                    }
                    flush()
                } else if s.revision?.kind != .deleted, let font = s.fontFamily,
                          piece.unicodeScalars.contains(where: { (0xF000...0xF0FF).contains($0.value) }) {
                    // Private-use characters in a named font go back as
                    // w:sym, the font with them.
                    var text = ""
                    func flush() { if !text.isEmpty { runXML += "<w:r>\(rPrXML)\(_text(text))</w:r>"; text = "" } }
                    for sc in piece.unicodeScalars {
                        if (0xF000...0xF0FF).contains(sc.value) {
                            flush()
                            runXML += "<w:r>\(rPrXML)<w:sym w:font=\"\(_esc(font))\" w:char=\"\(String(sc.value, radix: 16, uppercase: true))\"/></w:r>"
                        } else { text.unicodeScalars.append(sc) }
                    }
                    flush()
                } else if s.revision?.kind == .deleted {
                    runXML = "<w:r>\(rPrXML)" + _text(piece).replacingAll("<w:t ", with: "<w:delText ").replacingAll("<w:t>", with: "<w:delText>").replacingAll("</w:t>", with: "</w:delText>") + "</w:r>"
                } else if let ruby = s.ruby {
                    // Ruby goes back round its base as it came (its
                    // w:rubyPr and w:rt kept whole); a base in several
                    // looks is one w:ruby.
                    let lengths = p.runs.map(\.length)
                    let prior = p.runs.indices.prefix(runIndex).last { lengths[$0] > 0 }.map { p.runs[$0].style.ruby }
                    let later = p.runs.indices.dropFirst(runIndex + 1).first { lengths[$0] > 0 }.map { p.runs[$0].style.ruby }
                    if prior != ruby { runXML += "<w:r>\(rPrXML)<w:ruby>\(ruby.xml)<w:rubyBase>" }
                    runXML += "<w:r>\(rPrXML)\(_text(piece))</w:r>"
                    if later != ruby { runXML += "</w:rubyBase></w:ruby></w:r>" }
                } else {
                    runXML = "<w:r>\(rPrXML)\(_text(piece))</w:r>"
                }
                if let instr = s.field ?? s.preservedField {
                    // One field may have several result runs (a contents
                    // number with only some digits bold, for example).
                    // Keep every run inside the field rather than skipping
                    // later runs. Distinct imported fields can have the
                    // same instruction, so compare their result ids too.
                    func sameField(_ other: Run?) -> Bool {
                        guard let other, (other.style.field ?? other.style.preservedField) == instr,
                              other.style.fieldResult == s.fieldResult else { return false }
                        if let id = other.style.inlineImage, p.inlineImages[id] != nil { return false }
                        if let note = other.style.note,
                           doc.keptParts[note.kind == .footnote ? "word/footnotes.xml" : "word/endnotes.xml"] != nil { return false }
                        return true
                    }
                    let prior = p.runs.prefix(runIndex).last { $0.length > 0 }
                    let next = p.runs.dropFirst(runIndex + 1).first { $0.length > 0 }
                    if !sameField(prior) {
                        let properties = s.preservedFieldProperties.keys.sorted().map {
                            " \($0)=\"\(_esc(s.preservedFieldProperties[$0]!))\""
                        }.joined()
                        runXML = "<w:r>\(rPrXML)<w:fldChar w:fldCharType=\"begin\"\(properties)/></w:r><w:r>\(rPrXML)<w:instrText xml:space=\"preserve\"> \(_esc(instr)) </w:instrText></w:r><w:r>\(rPrXML)<w:fldChar w:fldCharType=\"separate\"/></w:r>\(runXML)"
                    }
                    if !sameField(next) {
                        runXML += "<w:r>\(rPrXML)<w:fldChar w:fldCharType=\"end\"/></w:r>"
                    }
                }
                if let rev = s.revision {
                    _ = nextRevisionID()
                    let tag = rev.kind == .inserted ? "w:ins" : "w:del"
                    runXML = "<\(tag) w:id=\"\(revisionCount)\" w:author=\"\(_esc(rev.author.isEmpty ? "Author" : rev.author))\"\(rev.date.isEmpty ? "" : " w:date=\"\(_esc(rev.date))\"")>\(runXML)</\(tag)>"
                }
                if commentsKept {
                    // A range still open that this run is not in (its last
                    // run sat in a paragraph written another way — a kept
                    // nested table, a picture): closed here.
                    body += closeComments(except: s.comments)
                    for id in s.comments where !openComments.contains(id) && !closedComments.contains(id) {
                        body += "<w:commentRangeStart w:id=\"\(_esc(id))\"/>"
                        openComments.append(id)
                    }
                }
                if let lf = s.linkField, s.link != nil {
                    // A HYPERLINK field kept as written: it opens before its first run and ends after its last, which may
                    // sit in another paragraph.
                    func same(_ o: Run?) -> Bool { o.map { $0.style.linkField == lf && $0.style.linkFieldID == s.linkFieldID } ?? false }
                    let before = p.runs.prefix(runIndex).last { $0.length > 0 }
                        ?? (index > 0 ? doc.paragraphs[index - 1].runs.last { $0.length > 0 } : nil)
                    let after = p.runs.dropFirst(runIndex + 1).first { $0.length > 0 }
                        ?? (index + 1 < doc.paragraphs.count ? doc.paragraphs[index + 1].runs.first { $0.length > 0 } : nil)
                    if !same(before) {
                        body += "<w:r><w:fldChar w:fldCharType=\"begin\"/></w:r><w:r><w:instrText xml:space=\"preserve\"> \(_esc(lf)) </w:instrText></w:r><w:r><w:fldChar w:fldCharType=\"separate\"/></w:r>"
                    }
                    body += runXML
                    if !same(after) { body += "<w:r><w:fldChar w:fldCharType=\"end\"/></w:r>" }
                } else if let link = s.link {
                    let tip = s.linkTip.map { " w:tooltip=\"\(_esc($0))\"" } ?? ""
                    // (A link the file wrote keeps what it had; one made in the app gets Word's w:history.)
                    let history = !s.linkKeepsLook || s.linkHistory ? " w:history=\"1\"" : ""
                    let open = link.hasPrefix("#") ? "<w:hyperlink w:anchor=\"\(_esc(String(link.dropFirst())))\"\(tip)\(history)>"
                        : "<w:hyperlink r:id=\"\(relId(for: link))\"\(tip)\(history)>"
                    if open == linkOpen, body.utf8.count == linkClosedAt {
                        body.removeLast("</w:hyperlink>".count)
                        body += runXML + "</w:hyperlink>"
                    } else {
                        body += open + runXML + "</w:hyperlink>"
                    }
                    linkOpen = open; linkClosedAt = body.utf8.count
                } else {
                    body += runXML
                }
                if commentsKept { body += closeComments(except: commentsAfter(index, runIndex, in: p)) }
            }
            body += bookmarkXML(at: p.length) + controlXML(at: p.length)
            if breakRidesOnPrevious(index + 1) {
                let next = doc.paragraphs[index + 1].style
                body += "<w:r>\(next.breakRunPropertiesXML ?? "")<w:br w:type=\"\(next.columnBreak ? "column" : "page")\"/></w:r>"
            }
            if commentsKept, index == doc.paragraphs.count - 1 { body += closeComments(except: []) }
            if p.style.contentsEnd { body += "<w:r><w:fldChar w:fldCharType=\"end\"/></w:r>" }
            body += "</w:p>"
            return body
        }

        /// One table: the run of cell paragraphs starting at `start`, as
        /// rows of cells with the grid's widths. Returns the index after it.
        func tableXML(from start: Int) -> (xml: String, end: Int) {
            let id = doc.paragraphs[start].cell!.table
            var end = start
            while end < doc.paragraphs.count, doc.paragraphs[end].cell?.table == id { end += 1 }
            let members = doc.paragraphs[start ..< end]
            let rows = (members.compactMap { $0.cell?.row }.max() ?? 0) + 1
            // The grid is as wide as the furthest cell REACHES, span
            // included: counting start columns alone lost the last
            // column of any row whose final cell spans several, and the
            // file's widths then failed to match and fell back to a
            // uniform grid (bug65649's 63-column estimate table came
            // back as 62 equal columns, every description one word wide,
            // and 34 pages longer).
            let cols = members.compactMap { $0.cell.map { $0.column + $0.span } }.max() ?? 1
            var widths = doc.tableColumns[id] ?? []
            if widths.count != cols {
                let content = pageSetup.contentWidth
                widths = Array(repeating: content / Double(cols), count: cols)
            }
            let twips = widths.map { Int(($0 * 20).rounded()) }
            let style = doc.tableStyles[id] ?? TableStyle()
            var xml = "<w:tbl><w:tblPr>"
            let namedStyle = doc.tableStyleIds[id].flatMap { doc.keptTableStyles[$0] != nil ? $0 : nil }
            if let namedStyle { xml += "<w:tblStyle w:val=\"\(_esc(namedStyle))\"/>" }
            if let pos = style.keptPosition { xml += pos }
            if let pct = style.widthPercent { xml += "<w:tblW w:w=\"\(Int((pct * 50).rounded()))\" w:type=\"pct\"/>" }
            else if let w = style.width { xml += "<w:tblW w:w=\"\(Int((w * 20).rounded()))\" w:type=\"dxa\"/>" }
            else { xml += "<w:tblW w:w=\"0\" w:type=\"auto\"/>" }
            switch style.alignment {
            case .center: xml += "<w:jc w:val=\"center\"/>"
            case .right: xml += "<w:jc w:val=\"right\"/>"
            default: break
            }
            if let sp = style.cellSpacing { xml += "<w:tblCellSpacing w:w=\"\(Int((sp * 20).rounded()))\" w:type=\"dxa\"/>" }
            if style.indent != 0 { xml += "<w:tblInd w:w=\"\(Int((style.indent * 20).rounded()))\" w:type=\"dxa\"/>" }
            let borderColor = style.borderColor.map { _hex($0) } ?? "auto"
            let borderSz = Int(((style.borderWidth ?? 0.5) * 8).rounded())
            let borderVal = _esc(style.borderStyle ?? "single")
            let e = style.edges ?? BorderEdges()
            let borderless = style.bordersFromCells || (doc.tableStyleIds[id] != nil && style.inheritedBordersKey == style.bordersKey)
            if !borderless { xml += "<w:tblBorders>" }
            for (side, own) in [("top", e.top), ("left", e.left), ("bottom", e.bottom), ("right", e.right), ("insideH", e.insideH), ("insideV", e.insideV)] where !borderless {
                let val = style.edgeStyles[side].map { _esc($0) } ?? borderVal
                let sz = style.edgeWidths[side].map { Int(($0 * 8).rounded()) } ?? borderSz
                xml += (own ?? style.borders) ? "<w:\(side) w:val=\"\(val)\" w:sz=\"\(sz)\" w:space=\"0\" w:color=\"\(borderColor)\"/>"
                                              : "<w:\(side) w:val=\"none\" w:sz=\"0\" w:space=\"0\" w:color=\"auto\"/>"
            }
            if !borderless { xml += "</w:tblBorders>" }
            if let shd = style.keptShdXML { xml += shd }
            if style.fixedLayout { xml += "<w:tblLayout w:type=\"fixed\"/>" }
            let margins: [(String, Double?)] = [("top", style.cellMarginTop), ("left", style.cellMarginLeft),
                                                ("bottom", style.cellMarginBottom), ("right", style.cellMarginRight)]
            if doc.tableStyleIds[id] != nil, style.inheritedMarginsKey == style.marginsKey {
                // (the style's own margins stand)
            } else if let kept = style.keptCellMarginsXML, style.keptCellMarginsUnder == margins.map(\.1) {
                xml += kept
            } else if margins.contains(where: { $0.1 != nil }) {
                xml += "<w:tblCellMar>"
                for (side, v) in margins { if let v { xml += "<w:\(side) w:w=\"\(Int((v * 20).rounded()))\" w:type=\"dxa\"/>" } }
                xml += "</w:tblCellMar>"
            }
            if let look = style.look {
                func bit(_ b: Int) -> String { look & b != 0 ? "1" : "0" }
                xml += "<w:tblLook w:val=\"" + TableLook.hex(look) + "\" w:firstRow=\"\(bit(0x20))\" w:lastRow=\"\(bit(0x40))\" w:firstColumn=\"\(bit(0x80))\" w:lastColumn=\"\(bit(0x100))\" w:noHBand=\"\(bit(0x200))\" w:noVBand=\"\(bit(0x400))\"/>"
            } else {
                xml += (namedStyle != nil ? doc.tableLooks[id] : nil) ?? "<w:tblLook w:val=\"04A0\"/>"
            }
            xml += "</w:tblPr><w:tblGrid>"
            // A cell's preferred width: the grid's, or none at all when the
            // file's cells stated none and Word autofits them.
            // The file's own word for a cell, while the columns are the
            // ones it was read with: a table whose cells mix percentages
            // with "auto" is neither all-auto nor the grid (a Taiwanese
            // performance-indicator table came back with every column at
            // another width, 27% over 17 pages).
            func tcW(_ w: Int, kept: String? = nil, under: Int? = nil) -> String {
                if let kept, under == w { return kept }
                return style.autoCellWidths ? "<w:tcW w:w=\"0\" w:type=\"auto\"/>" : "<w:tcW w:w=\"\(w)\" w:type=\"dxa\"/>"
            }
            // A cell's own sides, over the table's, at its own width.
            func cellBordersXML(_ own: BorderEdges?, width: Double? = nil, kept: String? = nil, under: Bool? = nil) -> String {
                if let kept, under == style.borders { return kept }
                guard let own else { return "" }
                let sz = width.map { Int(($0 * 8).rounded()) } ?? borderSz
                var out = "<w:tcBorders>"
                for (side, v) in [("top", own.top), ("left", own.left), ("bottom", own.bottom), ("right", own.right)] {
                    guard let v else { continue }
                    out += v ? "<w:\(side) w:val=\"\(borderVal)\" w:sz=\"\(sz)\" w:space=\"0\" w:color=\"\(borderColor)\"/>"
                             : "<w:\(side) w:val=\"nil\"/>"
                }
                return out + "</w:tcBorders>"
            }
            for w in twips { xml += "<w:gridCol w:w=\"\(w)\"/>" }
            xml += "</w:tblGrid>"
            let refs = members.compactMap(\.cell)
            for r in 0 ..< rows {
                var trPr = ""
                // (Schema order: the columns left empty before the rest.)
                let skipped = min(style.rowsGridBefore[r] ?? 0, cols)
                if skipped > 0 { trPr += "<w:gridBefore w:val=\"\(skipped)\"/><w:wBefore w:w=\"\(twips[0 ..< skipped].reduce(0, +))\" w:type=\"dxa\"/>" }
                if style.rowsCantSplit.contains(r) { trPr += "<w:cantSplit/>" }
                if let h = style.rowHeights[r] { trPr += "<w:trHeight w:val=\"\(Int((h * 20).rounded()))\"\(style.rowsExactHeight.contains(r) ? " w:hRule=\"exact\"" : "")/>" }
                if style.headerRow && r < style.headerRowCount { trPr += "<w:tblHeader/>" }
                xml += "<w:tr>" + (style.rowExceptions[r] ?? "") + (trPr.isEmpty ? "" : "<w:trPr>\(trPr)</w:trPr>")
                // A row ends where its last cell does: Word allows a row
                // shorter than the grid (145 of bug65649's 480 rows are,
                // and drawing's), and padding one with an empty cell adds a
                // paragraph the file never had.
                let rowEnd = refs.filter { $0.covers(row: r, column: $0.column) }.map { $0.column + $0.span }.max() ?? cols
                var c = skipped
                while c < rowEnd {
                    // A cell from a row above spanning into this row: a
                    // continuation cell, empty, marked vMerge.
                    if let above = refs.first(where: { $0.row < r && $0.rowSpan > 1 && $0.covers(row: r, column: c) }) {
                        let span = min(cols - c, above.span)
                        let w = twips[c ..< c + span].reduce(0, +)
                        xml += "<w:tc><w:tcPr>" + tcW(w)
                        if span > 1 { xml += "<w:gridSpan w:val=\"\(span)\"/>" }
                        let offset = r - above.row - 1
                        let contEdges = offset < above.continuationEdges.count ? above.continuationEdges[offset] : above.edges
                        let contKept = offset < above.continuationBordersXML.count ? above.continuationBordersXML[offset] : nil
                        xml += "<w:vMerge/>" + cellBordersXML(contEdges, width: above.borderWidth, kept: contKept, under: above.bordersKeptUnder)
                        if offset < above.continuationShdXML.count, let shd = above.continuationShdXML[offset] { xml += shd }
                        if let v = above.verticalAlign { xml += "<w:vAlign w:val=\"\(v)\"/>" }
                        let contContent = offset < above.continuationContentXML.count ? above.continuationContentXML[offset] : nil
                        xml += "</w:tcPr>" + (contContent ?? "<w:p/>") + "</w:tc>"
                        c += span
                        continue
                    }
                    let cell = (start ..< end).filter { doc.paragraphs[$0].cell?.row == r && doc.paragraphs[$0].cell?.column == c }
                    let ref = cell.first.flatMap { doc.paragraphs[$0].cell }
                    let span = min(cols - c, max(1, ref?.span ?? 1))
                    let w = twips[c ..< c + span].reduce(0, +)
                    xml += "<w:tc><w:tcPr>" + tcW(w, kept: ref?.widthXML, under: ref?.widthKeptUnder)
                    if span > 1 { xml += "<w:gridSpan w:val=\"\(span)\"/>" }
                    if (ref?.rowSpan ?? 1) > 1 { xml += "<w:vMerge w:val=\"restart\"/>" }
                    xml += cellBordersXML(ref?.edges, width: ref?.borderWidth, kept: ref?.bordersXML ?? (ref?.rowBordersXML != nil ? "" : nil), under: ref?.bordersKeptUnder)   // schema order: borders, then shading
                    if ref?.fill == nil, ref?.fillAuto == true { xml += "<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"auto\"/>" }
                    else if let fill = ref?.fill, !(ref?.styleFilled == true && doc.tableStyleIds[ref?.table ?? ""] != nil) { xml += "<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"\(_hex(fill))\"\(ref?.fillThemeAttrs ?? "")/>" }
                    if let mar = ref?.marginsXML { xml += mar }
                    // Schema order: the text direction before the alignment.
                    // (As the file wrote it while it still reads that way.)
                    let direction = ref?.textDirectionValue
                    switch ref?.textDirection {
                    case .down?: xml += "<w:textDirection w:val=\"\(direction.flatMap { ["tbRl", "tbRlV", "tbLrV"].contains($0) ? $0 : nil } ?? "tbRl")\"/>"
                    case .up?: xml += "<w:textDirection w:val=\"\(direction.flatMap { ["btLr", "lrTbV"].contains($0) ? $0 : nil } ?? "btLr")\"/>"
                    default: if direction == "lrTbV" { xml += "<w:textDirection w:val=\"lrTbV\"/>" }
                    }
                    if let v = ref?.verticalAlign { xml += "<w:vAlign w:val=\"\(v)\"/>" }
                    if let kept = ref?.keptPropertiesXML { xml += kept }
                    xml += "</w:tcPr>"
                    if cell.isEmpty { xml += "<w:p/>" }
                    // A nested table kept verbatim stands in for its
                    // flattened paragraphs while their text is unchanged.
                    var j = 0
                    var endedWithTable = false
                    while j < cell.count {
                        let k = cell[j]
                        if let kid = doc.paragraphs[k].keptTable, let kept = doc.keptTables[kid] {
                            var group: [Int] = []
                            while j < cell.count, doc.paragraphs[cell[j]].keptTable == kid { group.append(cell[j]); j += 1 }
                            if group.map({ doc.paragraphs[$0].text }) == kept.texts {
                                xml += keptFragmentXML(kept.xml, kept.rels)
                                endedWithTable = true
                                continue
                            }
                            for g in group { xml += blockOpen(g, table: false) + paragraphXML(g) + blockClose(g, table: false) }
                            endedWithTable = false
                            continue
                        }
                        xml += blockOpen(k, table: false) + paragraphXML(k) + blockClose(k, table: false)
                        endedWithTable = false
                        j += 1
                    }
                    if endedWithTable { xml += "<w:p/>" }   // a cell ends in a paragraph
                    xml += "</w:tc>"
                    c += span
                }
                xml += "</w:tr>"
            }
            xml += "</w:tbl>"
            // (A table the reader would take for an invisible wrapper — one
            // with no style, no borders, a column of room — is dissolved on
            // reading, and what it held stands in the body: LibreOffice's
            // NumberedList, a table with a table in its cell, came back
            // with the nested one as the outer. This one was a table when
            // it was read, and says so: the file's default table style,
            // which Word takes as no change.)
            if xml.hasPrefix("<w:tbl><w:tblPr>"), !xml.hasPrefix("<w:tbl><w:tblPr><w:tblStyle"), xml.utf8.count < 2_000_000 {
                let spaces = ["w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main", "r": "http://schemas.openxmlformats.org/officeDocument/2006/relationships",
                              "wp": "http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing", "a": "http://schemas.openxmlformats.org/drawingml/2006/main",
                              "mc": "http://schemas.openxmlformats.org/markup-compatibility/2006", "w14": "http://schemas.microsoft.com/office/word/2010/wordml",
                              "w15": "http://schemas.microsoft.com/office/word/2012/wordml", "wp14": "http://schemas.microsoft.com/office/word/2010/wordprocessingDrawing",
                              "v": "urn:schemas-microsoft-com:vml", "o": "urn:schemas-microsoft-com:office:office"]
                    .sorted { $0.key < $1.key }.map { "xmlns:\($0.key)=\"\($0.value)\"" }.joined(separator: " ")
                if let node = XNode.parse(Data("<w:wrap \(spaces)>\(xml)</w:wrap>".utf8))?.first("w:tbl"), _isInvisibleWrapper(node) {
                    xml = "<w:tbl><w:tblPr><w:tblStyle w:val=\"TableNormal\"/>" + xml.dropFirst("<w:tbl><w:tblPr>".count)
                }
            }
            return (xml, end)
        }

        var i = 0
        while i < doc.paragraphs.count {
            // A section of columns read as a table row (the reader does
            // that after the body walk) goes back as it was while its
            // text is.
            if let kid = doc.paragraphs[i].keptTable, kid.hasPrefix("kc"), let kept = doc.keptTables[kid] {
                var end = i
                while end < doc.paragraphs.count, doc.paragraphs[end].keptTable == kid { end += 1 }
                if doc.paragraphs[i ..< end].map(\.text) == kept.texts {
                    body += keptFragmentXML(kept.xml, kept.rels)
                    i = end
                    continue
                }
            }
            if doc.paragraphs[i].cell != nil {
                let t = tableXML(from: i)
                // Two tables with nothing between them are one table to Word.
                if body.hasSuffix("</w:tbl>") { body += "<w:p/>" }
                body += blockOpen(i, table: true) + t.xml + blockClose(t.end - 1, table: true)
                i = t.end
            } else {
                body += blockOpen(i, table: false)
                defer { body += blockClose(i - 1, table: false) }
                let xml = paragraphXML(i)
                // (The rest of a paragraph a page break split goes back into
                // it: the break ended the one before as its last run, and the
                // text after it is the same w:p. Written as two, the first's
                // mark read back as a paragraph of its own and every save
                // added one — LibreOffice's tdf123636_newlinePageBreak,
                // two paragraphs, then three.)
                if doc.paragraphs[i].style.continuesParagraph, breakRidesOnPrevious(i), body.hasSuffix("</w:p>"),
                   xml.hasPrefix("<w:p><w:pPr>"), let end = xml.firstRange(of: "</w:pPr>") {
                    body.removeLast(6)
                    body += xml[end.upperBound...]
                } else {
                    body += xml
                }
                i += 1
            }
        }
        // WordprocessingML wants a paragraph between a table and the section end.
        if doc.paragraphs.last?.cell != nil { body += "<w:p/>" }
        let pageSetup = pageSetup.vertical ? pageSetup.transposed() : pageSetup
        let pw = Int(pageSetup.width * 20), ph = Int(pageSetup.height * 20)
        body += "<w:sectPr>"
        // Kept header/footer parts: the default ones only while their text
        // is what the editor still shows; the generated ones take a name
        // no kept part uses.
        func editedHF(_ kind: KeptHeaderFooter.Kind) -> RichHeaderFooter? {
            doc.headerFooters.first { $0.kind == kind && $0.type == "default" && $0.section == nil && $0.edited == true }
        }
        let keptHF = doc.keptHeaderFooters.enumerated().filter { doc.keptParts[$0.element.part] != nil }.filter { (_, k) in
            k.type != "default" || (editedHF(k.kind) == nil && (k.kind == .header ? doc.header : doc.footer) == k.text)
        }
        let keptDefaultHeader = keptHF.contains { $0.element.kind == .header && $0.element.type == "default" }
        let keptDefaultFooter = keptHF.contains { $0.element.kind == .footer && $0.element.type == "default" }
        func freeName(_ stem: String) -> String {
            var n = 1
            while doc.keptParts["word/\(stem)\(n).xml"] != nil { n += 1 }
            return "\(stem)\(n).xml"
        }
        let headerName = freeName("header"), footerName = freeName("footer")
        let writeHeader = !doc.header.isEmpty && !keptDefaultHeader
        let writeFooter = !doc.footer.isEmpty && !keptDefaultFooter
        if writeHeader { body += "<w:headerReference w:type=\"default\" r:id=\"rIdHeader\"/>" }
        if writeFooter { body += "<w:footerReference w:type=\"default\" r:id=\"rIdFooter\"/>" }
        for (i, k) in keptHF {
            body += "<w:\(k.kind == .header ? "headerReference" : "footerReference") w:type=\"\(k.type)\" r:id=\"rIdKeptHF\(i)\"/>"
        }
        if let type = doc.sectionTypeXML { body += type }
        body += "<w:pgSz w:w=\"\(pw)\" w:h=\"\(ph)\"\(pageSetup.isLandscape && pageSetup.orientStated ? " w:orient=\"landscape\"" : "")/>"
        body += "<w:pgMar w:top=\"\(Int(pageSetup.marginTop * 20))\" w:right=\"\(Int(pageSetup.marginRight * 20))\" w:bottom=\"\(Int(pageSetup.marginBottom * 20))\" w:left=\"\(Int(pageSetup.marginLeft * 20))\" w:header=\"\(Int((pageSetup.headerDistance * 20).rounded()))\" w:footer=\"\(Int((pageSetup.footerDistance * 20).rounded()))\" w:gutter=\"\(doc.gutterTwips ?? 0)\"/>"
        if let pb = doc.pageBordersXML { body += pb }
        if let lead = doc.sectionLeadXML { body += lead }
        if let cols = doc.columnsXML, doc.columnsKeptUnder == max(1, pageSetup.columns) {
            // The file's own columns (an exam paper's two unequal ones, 0.3in
            // apart: at our half inch every line of it broke 7pt early).
            body += cols
        } else
        if pageSetup.columns > 1 { body += "<w:cols w:num=\"\(pageSetup.columns)\" w:space=\"\(Int(pageSetup.columnGap * 20))\"/>" }
        // A title page with no first-page part referenced is a page with
        // an EMPTY header and footer (Bug51170's cover shows no logo).
        if let tail = doc.sectionTailXML, tail.containsSubstring("<w:vAlign") { body += tail } // (vAlign precedes titlePg… and the rest follow it)
        if doc.titlePage { body += "<w:titlePg/>" }
        if let tail = doc.sectionTailXML, !tail.containsSubstring("<w:vAlign") { body += tail }
        if let grid = doc.docGridXML { body += grid }
        body += "</w:sectPr>"

        let ns = "xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" xmlns:wp=\"http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing\" xmlns:mc=\"http://schemas.openxmlformats.org/markup-compatibility/2006\" xmlns:wp14=\"http://schemas.microsoft.com/office/word/2010/wordprocessingDrawing\" xmlns:w14=\"http://schemas.microsoft.com/office/word/2010/wordml\" xmlns:w15=\"http://schemas.microsoft.com/office/word/2012/wordml\" mc:Ignorable=\"w14 w15 wp14\""
        let background = doc.backgroundXML.map { keptFragmentXML($0, doc.backgroundRels) } ?? ""
        let document = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<w:document \(ns)>\(background)<w:body>\(body)</w:body></w:document>"

        var relsXML = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
        relsXML += "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>"
        // A file with no numbering part and no list keeps none (the save used to add one to every such file).
        let dropNumbering = doc.readFromFile && doc.keptNumberingXML == nil && !numIdOf.contains { $0 != 0 }
        if !dropNumbering { relsXML += "<Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering\" Target=\"numbering.xml\"/>" }
        for r in rels {
            relsXML += "<Relationship Id=\"\(r.id)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink\" Target=\"\(_esc(r.target))\" TargetMode=\"External\"/>"
        }
        for r in mediaRels {
            relsXML += "<Relationship Id=\"\(r.id)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"\(r.target)\"/>"
        }
        relsXML += keptRels
        for (i, r) in doc.keptCustomXmlRels.enumerated() {
            relsXML += "<Relationship Id=\"rIdCustomXml\(i + 1)\" Type=\"\(_esc(r.type))\" Target=\"\(_esc(r.target))\"/>"
        }
        var extraParts: [ZipEntry] = []
        var extraOverrides = ""
        if writeHeader {
            relsXML += "<Relationship Id=\"rIdHeader\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/header\" Target=\"\(headerName)\"/>"
            extraParts.append(ZipEntry(name: "word/\(headerName)", data: Data((editedHF(.header).map { _richHeaderFooterPart("w:hdr", $0.paragraphs, width: pageSetup.contentWidth) } ?? _headerFooterPart("w:hdr", doc.header, center: false, width: pageSetup.contentWidth)).utf8)))
            extraOverrides += "<Override PartName=\"/word/\(headerName)\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml\"/>"
        }
        if writeFooter {
            relsXML += "<Relationship Id=\"rIdFooter\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer\" Target=\"\(footerName)\"/>"
            extraParts.append(ZipEntry(name: "word/\(footerName)", data: Data((editedHF(.footer).map { _richHeaderFooterPart("w:ftr", $0.paragraphs, width: pageSetup.contentWidth) } ?? _headerFooterPart("w:ftr", doc.footer, center: true, width: pageSetup.contentWidth)).utf8)))
            extraOverrides += "<Override PartName=\"/word/\(footerName)\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml\"/>"
        }
        for (i, k) in keptHF {
            let rel = k.kind == .header ? "header" : "footer"
            relsXML += "<Relationship Id=\"rIdKeptHF\(i)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/\(rel)\" Target=\"\(_esc(String(k.part.dropFirst(5))))\"/>"
        }
        // Settings: the compatibility mode is Word's own (15 = Word 2013 and
        // later). Without a settings part Word opens the file in
        // "Compatibility Mode" and lays it out by the 2007 rules — wider
        // default spacing, older line breaking — which the corpus showed
        // on every saved copy (2026-10-07).
        let written = Set(media.map(\.name))
        // A kept picture part nothing points at any more (its picture was replaced or deleted) is not written back.
        let relTexts = [relsXML, keptRels] + doc.keptParts.filter { $0.key.hasSuffix(".rels") }.map { String(decoding: $0.value, as: UTF8.self) }
        func orphanMedia(_ name: String) -> Bool {
            guard name.hasPrefix("word/media/") else { return false }
            let target = "media/" + name.dropFirst("word/media/".count)
            return !relTexts.contains { $0.containsSubstring("\"\(target)\"") || $0.containsSubstring("\"/\(name)\"") || $0.containsSubstring("\"../\(target)\"") }
        }
        // A theme-linked table colour in a document with no theme part: Word would fall back on ITS default
        // palette and draw other colours than the app did. Write the palette the app drew with.
        var keptAll = doc.keptParts
        if !keptAll.keys.contains(where: { $0.hasPrefix("word/theme/") }),
           doc.paragraphs.contains(where: { $0.cell?.fillThemeAttrs != nil || $0.cell?.bordersXML?.containsSubstring("w:themeColor=") == true }) {
            keptAll["word/theme/theme1.xml"] = Data(_defaultThemePart().utf8)
        }
        // A document made here has no properties part: write the core and extended properties Word expects, so the
        // author, title and subject fields have somewhere to read from and the file says when it was saved.
        var rootRelsExtra = doc.keptRootRels
        if !keptAll.keys.contains(where: { $0.hasPrefix("docProps/") }), !doc.keptRootRels.contains(where: { $0.type.hasSuffix("core-properties") || $0.type.hasSuffix("extended-properties") }) {
            let c = FieldClock.current()
            func two(_ n: Int) -> String { n < 10 ? "0\(n)" : String(n) }
            let stamp = c.map { "\($0.year)-\(two($0.month))-\(two($0.day))T\(two($0.hour)):\(two($0.minute)):\(two($0.second))Z" } ?? "2000-01-01T00:00:00Z"
            keptAll["docProps/core.xml"] = Data(("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<cp:coreProperties xmlns:cp=\"http://schemas.openxmlformats.org/package/2006/metadata/core-properties\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:dcterms=\"http://purl.org/dc/terms/\" xmlns:dcmitype=\"http://purl.org/dc/dcmitype/\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"><dc:creator></dc:creator><cp:lastModifiedBy></cp:lastModifiedBy>"
                + "<dcterms:created xsi:type=\"dcterms:W3CDTF\">\(stamp)</dcterms:created><dcterms:modified xsi:type=\"dcterms:W3CDTF\">\(stamp)</dcterms:modified></cp:coreProperties>").utf8)
            keptAll["docProps/app.xml"] = Data("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<Properties xmlns=\"http://schemas.openxmlformats.org/officeDocument/2006/extended-properties\"><Application>Starling Office</Application></Properties>".utf8)
            extraOverrides += "<Override PartName=\"/docProps/core.xml\" ContentType=\"application/vnd.openxmlformats-package.core-properties+xml\"/><Override PartName=\"/docProps/app.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.extended-properties+xml\"/>"
            rootRelsExtra.append(KeptRel(id: "", type: "http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties", target: "docProps/core.xml", external: false))
            rootRelsExtra.append(KeptRel(id: "", type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties", target: "docProps/app.xml", external: false))
        }
        // A file with core properties but no extended ones (a Properties edit made them first) gets app.xml too.
        if keptAll["docProps/app.xml"] == nil, !rootRelsExtra.contains(where: { $0.type.hasSuffix("extended-properties") }) {
            keptAll["docProps/app.xml"] = Data("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<Properties xmlns=\"http://schemas.openxmlformats.org/officeDocument/2006/extended-properties\"><Application>Starling Office</Application></Properties>".utf8)
            extraOverrides += "<Override PartName=\"/docProps/app.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.extended-properties+xml\"/>"
            rootRelsExtra.append(KeptRel(id: "", type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties", target: "docProps/app.xml", external: false))
        }
        for (name, data) in keptAll.sorted(by: { $0.key < $1.key }) where !written.contains(name) && !orphanMedia(name) && name != "word/settings.xml" {
            extraParts.append(ZipEntry(name: name, data: data))
            switch name {
            case "word/footnotes.xml":
                relsXML += "<Relationship Id=\"rIdFootnotes\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/footnotes\" Target=\"footnotes.xml\"/>"
                extraOverrides += "<Override PartName=\"/word/footnotes.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.footnotes+xml\"/>"
            case "word/endnotes.xml":
                relsXML += "<Relationship Id=\"rIdEndnotes\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/endnotes\" Target=\"endnotes.xml\"/>"
                extraOverrides += "<Override PartName=\"/word/endnotes.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.endnotes+xml\"/>"
            case "word/comments.xml":
                relsXML += "<Relationship Id=\"rIdComments\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/comments\" Target=\"comments.xml\"/>"
                extraOverrides += "<Override PartName=\"/word/comments.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.comments+xml\"/>"
            case "word/commentsExtended.xml":
                relsXML += "<Relationship Id=\"rIdCommentsExt\" Type=\"http://schemas.microsoft.com/office/2011/relationships/commentsExtended\" Target=\"commentsExtended.xml\"/>"
                extraOverrides += "<Override PartName=\"/word/commentsExtended.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.commentsExtended+xml\"/>"
            case "word/commentsIds.xml":
                relsXML += "<Relationship Id=\"rIdCommentsIds\" Type=\"http://schemas.microsoft.com/office/2016/09/relationships/commentsIds\" Target=\"commentsIds.xml\"/>"
                extraOverrides += "<Override PartName=\"/word/commentsIds.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.commentsIds+xml\"/>"
            case "word/commentsExtensible.xml":
                relsXML += "<Relationship Id=\"rIdCommentsExtensible\" Type=\"http://schemas.microsoft.com/office/2018/08/relationships/commentsExtensible\" Target=\"commentsExtensible.xml\"/>"
                extraOverrides += "<Override PartName=\"/word/commentsExtensible.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.commentsExtensible+xml\"/>"
            case "word/fontTable.xml":
                relsXML += "<Relationship Id=\"rIdFontTable\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/fontTable\" Target=\"fontTable.xml\"/>"
                extraOverrides += "<Override PartName=\"/word/fontTable.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.fontTable+xml\"/>"
            case "word/stylesWithEffects.xml":
                relsXML += "<Relationship Id=\"rIdStylesFx\" Type=\"http://schemas.microsoft.com/office/2007/relationships/stylesWithEffects\" Target=\"stylesWithEffects.xml\"/>"
                extraOverrides += "<Override PartName=\"/word/stylesWithEffects.xml\" ContentType=\"\(_esc(doc.keptPartTypes[name] ?? "application/vnd.ms-word.stylesWithEffects+xml"))\"/>"
            case "word/glossary/document.xml":
                relsXML += "<Relationship Id=\"rIdGlossary\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/glossaryDocument\" Target=\"glossary/document.xml\"/>"
                extraOverrides += "<Override PartName=\"/word/glossary/document.xml\" ContentType=\"\(_esc(doc.keptPartTypes[name] ?? "application/vnd.openxmlformats-officedocument.wordprocessingml.document.glossary+xml"))\"/>"
            case "word/webSettings.xml":
                relsXML += "<Relationship Id=\"rIdWebSettings\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/webSettings\" Target=\"webSettings.xml\"/>"
                extraOverrides += "<Override PartName=\"/word/webSettings.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.webSettings+xml\"/>"
            case _ where name.hasPrefix("word/theme/"):
                relsXML += "<Relationship Id=\"rIdTheme\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme\" Target=\"\(_esc(String(name.dropFirst(5))))\"/>"
                extraOverrides += "<Override PartName=\"/\(_esc(name))\" ContentType=\"application/vnd.openxmlformats-officedocument.theme+xml\"/>"
            default:
                let ext = (name.split(separator: "/").last ?? "").split(separator: ".").dropFirst().last.map { String($0).lowercased() } ?? ""
                if ext == "rels" { break }
                if let t = doc.keptPartTypes[name] {
                    extraOverrides += "<Override PartName=\"/\(_esc(name))\" ContentType=\"\(_esc(t))\"/>"
                } else if ext != "xml", !ext.isEmpty {
                    usedExtensions.insert(ext)
                }
            }
        }
        relsXML += "<Relationship Id=\"rIdSettings\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings\" Target=\"settings.xml\"/>"
        // (An even-page part may belong to an earlier section only, kept
        // with that section's own XML: a chemicals list of three sections
        // lost the setting and showed its odd footer on every page.)
        let evenReferenced = keptHF.contains(where: { $0.element.type == "even" })
            || document.containsSubstring("Reference r:id=") && {
                // A header or footer reference of type "even", found by hand:
                // a regular expression is the legacy Foundation layer, which
                // the web build does not link.
                for tag in ["<w:headerReference ", "<w:footerReference "] {
                    var rest = Substring(document)
                    while let at = rest.firstRange(of: tag) {
                        rest = rest[at.upperBound...]
                        let end = rest.firstIndex(of: ">") ?? rest.endIndex
                        if String(rest[..<end]).containsSubstring("w:type=\"even\"") { return true }
                    }
                }
                return false
            }()
        var settings = doc.evenAndOddHeaders && evenReferenced
            ? _settingsPart.replacingAll("<w:defaultTabStop", with: "<w:evenAndOddHeaders/><w:defaultTabStop") : _settingsPart
        // The rest of what Word lays out by, each group at its place in the
        // schema: before the tab stop, after it, and round the character
        // spacing control. (A county notice printed 18 pages to the
        // original's 14 without its w:noPunctuationKerning.)
        func keptSettings(_ group: Int) -> String { _keptSettingNames[group].compactMap { doc.keptSettings[$0] }.joined() }
        settings = settings.replacingAll("<w:defaultTabStop w:val=\"720\"/>", with: keptSettings(0) + "<w:defaultTabStop w:val=\"720\"/>" + keptSettings(1))
        settings = settings.replacingAll("<w:characterSpacingControl w:val=\"doNotCompress\"/>",
                                         with: keptSettings(2) + "<w:characterSpacingControl w:val=\"doNotCompress\"/>" + keptSettings(3))
        if let csc = doc.characterSpacingControl {
            settings = settings.replacingAll("<w:characterSpacingControl w:val=\"doNotCompress\"/>", with: "<w:characterSpacingControl w:val=\"\(_esc(csc))\"/>")
        }
        if let lang = doc.themeFontLangXML { settings = settings.replacingAll("</w:settings>", with: lang + "</w:settings>") }
        // (Schema order: both stand before the default tab stop.)
        if let margins = doc.marginSettingsXML { settings = settings.replacingAll("<w:defaultTabStop", with: margins + "<w:defaultTabStop") }
        if let tab = doc.defaultTabStop {
            settings = settings.replacingAll("<w:defaultTabStop w:val=\"720\"/>", with: "<w:defaultTabStop w:val=\"\(Int((tab * 20).rounded()))\"/>")
        }
        if let compat = doc.keptCompat, let start = settings.rangeOfSubstring("<w:compat>"), let end = settings.rangeOfSubstring("</w:compat>") {
            // The file's own compatibility mode and switches: Word 2007 and
            // 2010 files (a third of the corpus) break lines and space
            // tables by their mode's rules, and a copy that said 15 did not.
            settings.replaceSubrange(start.lowerBound ..< end.upperBound, with: compat)
        }
        if let original = doc.keptParts["word/settings.xml"] {
            settings = Self._patchedSettings(String(decoding: original, as: UTF8.self), even: doc.evenAndOddHeaders, evenReferenced: evenReferenced,
                                             tab: doc.defaultTabStop, spacing: doc.characterSpacingControl)
        }
        extraParts.append(ZipEntry(name: "word/settings.xml", data: Data(settings.utf8)))
        extraOverrides += "<Override PartName=\"/word/settings.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml\"/>"
        relsXML += "</Relationships>"
        var contentTypes = _contentTypes.replacingAll("</Types>", with: extraOverrides + "</Types>")
        if dropNumbering { contentTypes = contentTypes.replacingAll("<Override PartName=\"/word/numbering.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml\"/>", with: "") }
        for ext in usedExtensions.sorted() {
            let mime = _imageMime(ext)
            contentTypes = contentTypes.replacingAll("<Override PartName=\"/word/document.xml\"",
                                                             with: "<Default Extension=\"\(ext)\" ContentType=\"\(mime)\"/><Override PartName=\"/word/document.xml\"")
        }

        let generatedStyles = _stylesPart(doc.styles, notes: doc.keptParts.keys.contains { !$0.hasPrefix("docProps/") && !$0.hasPrefix("customXml/") && $0 != "word/webSettings.xml" }, aliases: doc.styleAliases, fileFonts: doc.fileFonts, fromFile: doc.readFromFile,
                                                                         characterStyles: doc.keptCharacterStyles, characterStyleIds: doc.keptCharacterStyleIds, tableStyles: doc.keptTableStyles)
                .replacingAll("<w:lang w:val=\"en-US\"/>", with: doc.defaultLangXML ?? "<w:lang w:val=\"en-US\"/>")
        let stylesXML = doc.readFromFile ? (doc.keptStylesXML.flatMap { _patchedStyles(original: $0, generated: generatedStyles, doc: doc, usedIn: document + extraParts.filter { $0.name.hasSuffix(".xml") && !$0.name.containsSubstring("styles") }.map { String(decoding: $0.data, as: UTF8.self) }.joined()) } ?? generatedStyles) : generatedStyles
        let generatedNumbering = _numberingPart(numKinds, numFormats, bulletId: bulletId, decimalId: decimalId,
                                                counterOf: Dictionary(uniqueKeysWithValues: numIds.compactMap { k, v in doc.listCounterOf[k].map { (v, $0) } }),
                                                restarts: Dictionary(uniqueKeysWithValues: numIds.compactMap { k, v in doc.listRestarts[k].map { (v, $0) } }))
        let numberingXML = doc.readFromFile ? (doc.keptNumberingXML.flatMap { _patchedNumbering(original: $0, generated: generatedNumbering, doc: doc, usedIds: Set(numIdOf)) } ?? generatedNumbering) : generatedNumbering
        let entries: [ZipEntry] = [
            ZipEntry(name: "[Content_Types].xml", data: Data(contentTypes.utf8)),
            ZipEntry(name: "_rels/.rels", data: Data(_rootRels.replacingAll("</Relationships>", with: rootRelsExtra.enumerated().map { i, r in
                "<Relationship Id=\"rIdPkg\(i + 1)\" Type=\"\(_esc(r.type))\" Target=\"\(_esc(r.target))\"\(r.external ? " TargetMode=\"External\"" : "")/>"
            }.joined() + "</Relationships>").utf8)),
            ZipEntry(name: "word/document.xml", data: Data(document.utf8)),
            ZipEntry(name: "word/styles.xml", data: Data(stylesXML.utf8)),
            ZipEntry(name: "word/numbering.xml", data: Data(numberingXML.utf8)),
            ZipEntry(name: "word/_rels/document.xml.rels", data: Data(relsXML.utf8)),
        ] + media + extraParts
        return try Zip.write(dropNumbering ? entries.filter { $0.name != "word/numbering.xml" } : entries)
    }

    /// Office's 2013 default theme (the palette `ColorMath.officeTheme` draws): colours, Calibri fonts, plain format scheme.
    static func _defaultThemePart() -> String {
        let c = ColorMath.officeTheme.map { String($0, radix: 16, uppercase: true) }.map { String(repeating: "0", count: 6 - $0.count) + $0 }
        let names = ["lt1", "dk1", "lt2", "dk2", "accent1", "accent2", "accent3", "accent4", "accent5", "accent6"]
        // Theme order is dk1, lt1, dk2, lt2, accents; the picker's order is Background 1 (lt1), Text 1 (dk1), ...
        var scheme = ""
        for n in ["dk1", "lt1", "dk2", "lt2", "accent1", "accent2", "accent3", "accent4", "accent5", "accent6"] {
            scheme += "<a:\(n)><a:srgbClr val=\"\(c[names.firstIndex(of: n)!])\"/></a:\(n)>"
        }
        scheme += "<a:hlink><a:srgbClr val=\"0563C1\"/></a:hlink><a:folHlink><a:srgbClr val=\"954F72\"/></a:folHlink>"
        let fill = "<a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill>"
        let ln = "<a:ln w=\"6350\"><a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill></a:ln>"
        return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<a:theme xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" name=\"Office Theme\"><a:themeElements>"
            + "<a:clrScheme name=\"Office\">\(scheme)</a:clrScheme>"
            + "<a:fontScheme name=\"Office\"><a:majorFont><a:latin typeface=\"Calibri Light\"/><a:ea typeface=\"\"/><a:cs typeface=\"\"/></a:majorFont><a:minorFont><a:latin typeface=\"Calibri\"/><a:ea typeface=\"\"/><a:cs typeface=\"\"/></a:minorFont></a:fontScheme>"
            + "<a:fmtScheme name=\"Office\"><a:fillStyleLst>\(fill)\(fill)\(fill)</a:fillStyleLst><a:lnStyleLst>\(ln)\(ln)\(ln)</a:lnStyleLst>"
            + "<a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst>"
            + "<a:bgFillStyleLst>\(fill)\(fill)\(fill)</a:bgFillStyleLst></a:fmtScheme></a:themeElements></a:theme>"
    }

    static func _imageMime(_ ext: String) -> String {
        switch ext {
        case "jpeg", "jpg": return "image/jpeg"
        case "gif": return "image/gif"
        case "bmp": return "image/bmp"
        case "tiff", "tif": return "image/tiff"
        case "emf": return "image/x-emf"
        case "wmf": return "image/x-wmf"
        case "svg": return "image/svg+xml"
        default: return "image/png"
        }
    }

    /// A header or footer part: one paragraph, fields as fldSimple.
    /// A header or footer part written from the editor's formatted paragraphs (W-HF-1): direct formatting only,
    /// tabs as the Header/Footer centre and right stops, page fields as simple fields.
    static func _richHeaderFooterPart(_ tag: String, _ paragraphs: [RichParagraph], width: Double) -> String {
        var body = ""
        for p in paragraphs {
            var pPr = ""
            if p.text.contains("\t" as Character) {
                pPr += "<w:tabs><w:tab w:val=\"center\" w:pos=\"\(Int((width * 10).rounded()))\"/><w:tab w:val=\"right\" w:pos=\"\(Int((width * 20).rounded()))\"/></w:tabs>"
            }
            switch p.style.alignment {
            case .center: pPr += "<w:jc w:val=\"center\"/>"
            case .right: pPr += "<w:jc w:val=\"right\"/>"
            case .justify: pPr += "<w:jc w:val=\"both\"/>"
            default: break
            }
            var runs = ""
            var offset = 0
            let units = Array(p.text.utf16)
            for r in p.runs where r.length > 0 {
                let piece = String(decoding: units[offset..<min(offset + r.length, units.count)], as: UTF16.self)
                offset += r.length
                let rPr = _rPrXML(r.style)
                let props = rPr.isEmpty ? "" : "<w:rPr>\(rPr)</w:rPr>"
                var inner = ""
                var literal = ""
                func flush() { if !literal.isEmpty { inner += "<w:r>\(props)\(_text(literal))</w:r>"; literal = "" } }
                for ch in piece {
                    if ch == "\t" { flush(); inner += "<w:r>\(props)<w:tab/></w:r>" } else { literal.append(ch) }
                }
                flush()
                if let f = r.style.field { runs += "<w:fldSimple w:instr=\" \(_esc(f)) \">\(inner)</w:fldSimple>" } else { runs += inner }
            }
            body += "<w:p>\(pPr.isEmpty ? "" : "<w:pPr>\(pPr)</w:pPr>")\(runs)</w:p>"
        }
        return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<\(tag) xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\">\(body)</\(tag)>"
    }

    static func _headerFooterPart(_ tag: String, _ template: String, center: Bool, width: Double) -> String {
        var runs = ""
        var literal = ""
        func flush() {
            if !literal.isEmpty { runs += "<w:r>\(_text(literal))</w:r>"; literal = "" }
        }
        var rest = Substring(template)
        while !rest.isEmpty {
            if rest.hasPrefix("\t") {
                flush(); runs += "<w:r><w:tab/></w:r>"
                rest = rest.dropFirst()
            } else if rest.hasPrefix(RichDocument.pageField) {
                flush(); runs += "<w:fldSimple w:instr=\" PAGE \"><w:r><w:t>1</w:t></w:r></w:fldSimple>"
                rest = rest.dropFirst(RichDocument.pageField.count)
            } else if rest.hasPrefix(RichDocument.pageCountField) {
                flush(); runs += "<w:fldSimple w:instr=\" NUMPAGES \"><w:r><w:t>1</w:t></w:r></w:fldSimple>"
                rest = rest.dropFirst(RichDocument.pageCountField.count)
            } else {
                literal.append(rest.removeFirst())
            }
        }
        flush()
        // Tabs: Word's Header/Footer stops, a centre one halfway across
        // the text and a right one at its end; the line is then left,
        // centre and right thirds rather than centred as a whole.
        let tabbed = template.contains("\t" as Character)
        let jc = tabbed
            ? "<w:pPr><w:tabs><w:tab w:val=\"center\" w:pos=\"\(Int((width * 10).rounded()))\"/><w:tab w:val=\"right\" w:pos=\"\(Int((width * 20).rounded()))\"/></w:tabs></w:pPr>"
            : (center ? "<w:pPr><w:jc w:val=\"center\"/></w:pPr>" : "")
        return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<\(tag) xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><w:p>\(jc)\(runs)</w:p></\(tag)>"
    }

    static func _text(_ s: String) -> String {
        // Tabs and line breaks are elements, not characters — and so are
        // the optional and the non-breaking hyphen: the character U+00AD
        // in a w:t is not a break opportunity to Word, so bug65649's
        // "Техни-ческому" stayed whole and its autofit column grew by
        // the half word (three pages over 180).
        var out = ""
        var buf = ""
        func flush() {
            // xml:space only where whitespace could be lost: an edge, a run of
            // blanks, or a control whitespace character.
            if !buf.isEmpty {
                let needs = buf.first!.isWhitespace || buf.last!.isWhitespace || buf.containsSubstring("  ")
                    || buf.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0xA0 || $0.value == 0x3000 }
                out += needs ? "<w:t xml:space=\"preserve\">\(_esc(buf))</w:t>" : "<w:t>\(_esc(buf))</w:t>"; buf = ""
            }
        }
        for ch in s {
            switch ch {
            case "\t": flush(); out += "<w:tab/>"
            case "\n": flush(); out += "<w:br/>"
            case "\u{00AD}": flush(); out += "<w:softHyphen/>"
            case "\u{2011}": flush(); out += "<w:noBreakHyphen/>"
            default: buf.append(ch)
            }
        }
        flush()
        return out
    }

    static func _esc(_ s: String) -> String {
        var out = ""
        for u in s.unicodeScalars {
            // (Not a character XML 1.0 can hold: the C0 controls but tab,
            // line feed and carriage return, U+FFFE and U+FFFF. A file read
            // as text from bytes that were never a document — LibreOffice's
            // EDB-36788-1 — saved a document.xml no parser opens.)
            let v = u.value
            guard v == 0x9 || v == 0xA || v == 0xD || (v >= 0x20 && v <= 0xD7FF) || (v >= 0xE000 && v <= 0xFFFD) || v >= 0x10000 else { continue }
            switch u {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            default: out.unicodeScalars.append(u)
            }
        }
        return out
    }

    /// A paragraph's shading: as the file wrote it (pattern, theme link) while the fill is still that colour.
    static func _paraShdXML(_ fill: Color, _ attrs: String?) -> String {
        if let t = attrs, let h = t.firstIndex(of: "#"), t[t.startIndex ..< h].lowercased() == _hex(fill).lowercased() {
            return "<w:shd\(t[t.index(after: h)...]) w:fill=\"\(_hex(fill))\"/>"
        }
        return "<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"\(_hex(fill))\"/>"
    }
    static func _hex(_ c: Color) -> String {
        String(printf: "%06X", c.value & 0xFFFFFF)
    }

    /// The file's own settings with only what the app sets changed: the even/odd headers switch, the default tab stop and the
    /// character spacing control. Everything else (zoom, colour map, revision ids, math and shape defaults, note settings...)
    /// stays as the file had it.
    static func _patchedSettings(_ original: String, even: Bool, evenReferenced: Bool, tab: Double?, spacing: String?) -> String {
        var xml = original
        /// The range of the first `<w:name .../>` (or `<w:name ...>...</w:name>`) element.
        func element(_ name: String) -> Range<String.Index>? {
            guard let start = xml.rangeOfSubstring("<w:\(name)") else { return nil }
            let after = xml[start.upperBound...]
            guard let c = after.first, c == " " || c == "/" || c == ">" else { return nil }
            guard let close = after.firstIndex(of: ">") else { return nil }
            if xml[xml.index(before: close)] == "/" { return start.lowerBound ..< xml.index(after: close) }
            if let end = xml.rangeOfSubstring("</w:\(name)>") { return start.lowerBound ..< end.upperBound }
            return nil
        }
        func setValue(_ name: String, _ value: String) {
            guard let r = element(name) else { return }
            var tag = String(xml[r])
            guard let at = tag.rangeOfSubstring("w:val=\""), let end = tag[at.upperBound...].firstIndex(of: "\"") else { return }
            if tag[at.upperBound ..< end] == value { return }
            tag.replaceSubrange(at.upperBound ..< end, with: value)
            xml.replaceSubrange(r, with: tag)
        }
        if let r = element("evenAndOddHeaders") {
            let off = ["0", "false", "off"].contains { String(xml[r]).containsSubstring("w:val=\"\($0)\"") }
            if !even { xml.removeSubrange(r) }
            else if off { xml.replaceSubrange(r, with: "<w:evenAndOddHeaders/>") }
        } else if even, evenReferenced {
            let marker = ["<w:defaultTabStop", "<w:characterSpacingControl", "<w:compat", "</w:settings>"].first { xml.containsSubstring($0) }
            if let marker, let at = xml.rangeOfSubstring(marker) { xml.insert(contentsOf: "<w:evenAndOddHeaders/>", at: at.lowerBound) }
        }
        if let tab { setValue("defaultTabStop", String(Int((tab * 20).rounded()))) }
        if let spacing { setValue("characterSpacingControl", _esc(spacing)) }
        return xml
    }

    static let _settingsPart = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:defaultTabStop w:val="720"/><w:characterSpacingControl w:val="doNotCompress"/><w:compat><w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="15"/></w:compat></w:settings>
    """

    static let _contentTypes = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/><Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/></Types>
    """

    static let _rootRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>
    """

    /// styles.xml from the document's sheet: Normal as the default, every
    /// other entry with its look, plus List Paragraph and Hyperlink.
    static func _stylesPart(_ sheet: RichStyleSheet, notes: Bool = false, aliases: [String: String] = [:], fileFonts: Set<String> = [], fromFile: Bool = false,
                                    characterStyles: [String: String] = [:], characterStyleIds: [String: String] = [:], tableStyles: [String: String] = [:]) -> String {
        func exportName(_ family: String) -> String { fileFonts.contains(family) ? family : OfficeFonts.exportName(family) }
        var out = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
        // The document defaults are Normal's look (the file's, when it was
        // read from one): Calibri 11 only for a document that never said.
        let normal = sheet[RichNamedStyle.normalId]?.char ?? CharStyle()
        var defaultLook = normal
        defaultLook.fontFamily = normal.fontFamily ?? "Calibri"
        let defaultFonts = _rFontsXML(defaultLook, fileFonts: fileFonts, eastAsiaDefault: true)
        // Kerning on by default (every LibreOffice file says so) moves
        // each Latin pair, so the default goes back with the fonts.
        let defaultKern = normal.kerningFrom.map { "<w:kern w:val=\"\(Int(($0 * 2).rounded()))\"/>" } ?? ""
        let defaultSize = Int(((normal.fontSize ?? 11) * 2).rounded())
        // And Normal's spacing: the body's paragraphs spell theirs out, but
        // a kept part's (a header's, a footnote's, a text box's) fall back
        // to these — issue_51265_3's header grew by Word's 8pt after.
        let normalParagraph = sheet[RichNamedStyle.normalId]?.paragraph ?? .body
        let defaultSpacing = _spacingXML(normalParagraph)
        out += "<w:styles xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:docDefaults><w:rPrDefault><w:rPr>\(defaultFonts)\(defaultKern)<w:sz w:val=\"\(defaultSize)\"/><w:szCs w:val=\"\(defaultSize)\"/><w:lang w:val=\"en-US\"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr>\(defaultSpacing)</w:pPr></w:pPrDefault></w:docDefaults>"
        out += "<w:style w:type=\"paragraph\" w:default=\"1\" w:styleId=\"Normal\"><w:name w:val=\"Normal\"/><w:qFormat/></w:style>"
        for entry in sheet.styles where entry.id != RichNamedStyle.normalId {
            let name = entry.paragraph.heading.map { "heading \($0)" } ?? entry.name
            out += "<w:style w:type=\"paragraph\" w:styleId=\"\(_esc(entry.id))\"><w:name w:val=\"\(_esc(name))\"/><w:basedOn w:val=\"Normal\"/>"
            if let next = entry.next { out += "<w:next w:val=\"\(_esc(next))\"/>" }
            out += "<w:qFormat/><w:pPr>"
            // Our own headings keep with the next paragraph; a file's say
            // for themselves. (A Taiwanese impeachment text numbers every
            // paragraph as a "heading": kept with the next, Word carried
            // each one's last line over the page, 53 pages for 54.)
            if fromFile ? entry.paragraph.keepNext : entry.paragraph.heading != nil { out += "<w:keepNext/>" }
            if fromFile, entry.paragraph.keepLines { out += "<w:keepLines/>" }
            // A style's own rule (the line under a "header" style: the
            // kept header part's paragraphs draw it by their style).
            if let b = entry.paragraph.borders { out += _bordersXML(b) }
            if entry.paragraph.fill == nil, let t = entry.paragraph.fillAttrs, t.hasPrefix("auto#") { out += "<w:shd\(t.dropFirst(5)) w:fill=\"auto\"/>" }
            if let fill = entry.paragraph.fill { out += _paraShdXML(fill, entry.paragraph.fillAttrs) }
            if entry.paragraph.rightToLeft { out += "<w:bidi/>" }
            // The style's tab stops: a header style's centre and right
            // tabs place what the kept header part lays out with them
            // (issue_51265_3's header pictures, 4.2% -> 0.00).
            out += _tabsXML(entry.paragraph.tabStops, under: normalParagraph.tabStops)
            out += _eastAsianSwitchesXML(entry.paragraph)
            out += _withEastAsian(_spacingXML(entry.paragraph), "w:spacing", _eastAsianSpacing, entry.paragraph)
            var ind = ""
            if entry.paragraph.indentLeft != 0 { ind += " w:left=\"\(Int(entry.paragraph.indentLeft * 20))\"" }
            if entry.paragraph.indentRight != 0 { ind += " w:right=\"\(Int(entry.paragraph.indentRight * 20))\"" }
            if entry.paragraph.firstLineIndent > 0 { ind += " w:firstLine=\"\(Int(entry.paragraph.firstLineIndent * 20))\"" }
            if entry.paragraph.firstLineIndent < 0 { ind += " w:hanging=\"\(Int(-entry.paragraph.firstLineIndent * 20))\"" }
            out += _withEastAsian(ind.isEmpty ? "" : "<w:ind\(ind)/>", "w:ind", _eastAsianIndents, entry.paragraph)
            switch entry.paragraph.alignment {
            // (Said, where Normal is not left: a kept footer's paragraphs
            // have only their style to tell them.)
            case .left: if normalParagraph.alignment != .left { out += "<w:jc w:val=\"left\"/>" }
            case .center: out += "<w:jc w:val=\"center\"/>"
            case .right: out += "<w:jc w:val=\"right\"/>"
            case .justify: out += "<w:jc w:val=\"\(_esc(entry.paragraph.eastAsian["w:jc"] ?? "both"))\"/>"
            }
            if let v = entry.paragraph.eastAsian["w:textAlignment"] { out += "<w:textAlignment w:val=\"\(_esc(v))\"/>" }
            if let h = entry.paragraph.heading { out += "<w:outlineLvl w:val=\"\(h - 1)\"/>" }
            out += "</w:pPr><w:rPr>"
            out += _rFontsXML(entry.char, fileFonts: fileFonts)
            if entry.char.bold { out += "<w:b/><w:bCs/>" }
            if entry.char.italic { out += "<w:i/><w:iCs/>" }
            if entry.char.caps { out += "<w:caps/>" }
            if entry.char.smallCaps { out += "<w:smallCaps/>" }
            // A style that hides its text (the HTML form markers Word's
            // importer leaves: bug59058 printed "Top of Form" over a rule
            // above each of its tables).
            if entry.char.hidden { out += "<w:vanish/>" }
            if entry.char.underline {
                out += "<w:u w:val=\"\(_esc(entry.char.underlineKind ?? "single"))\""
                if let c = entry.char.underlineColor { out += " w:color=\"\(_esc(c))\"" }
                out += (entry.char.underlineThemeAttrs ?? "") + "/>"
            }
            if entry.char.strikethrough { out += entry.char.doubleStrike ? "<w:dstrike/>" : "<w:strike/>" }
            if let em = entry.char.emphasis { out += "<w:em w:val=\"\(em)\"/>" }
            if let c = entry.char.color { out += "<w:color w:val=\"\(_hex(c))\"/>" }
            // The rest of a style's look that its runs lean on: a title
            // style's letter spacing (a Taiwanese impeachment text's
            // heading came back 60pt narrower), kerning, and the kept
            // properties.
            if let ls = entry.char.letterSpacing, ls != 0 { out += "<w:spacing w:val=\"\(Int((ls * 20).rounded()))\"/>" }
            if let k = entry.char.kerningFrom { out += "<w:kern w:val=\"\(Int((k * 2).rounded()))\"/>" }
            if let size = entry.char.fontSize { out += "<w:sz w:val=\"\(Int(size * 2))\"/><w:szCs w:val=\"\(Int(size * 2))\"/>" }
            if let kept = entry.char.keptXML { out += kept }
            out += "</w:rPr></w:style>"
        }
        // Unless the file brought a "List Paragraph" of its own under
        // another id: two styles of one name, and Word took ours — half an
        // inch of left indent on every paragraph of a Ningbo regulation.
        if !sheet.styles.contains(where: { $0.id != "ListParagraph" && $0.name.lowercased() == "list paragraph" }) {
        out += "<w:style w:type=\"paragraph\" w:styleId=\"ListParagraph\"><w:name w:val=\"List Paragraph\"/><w:basedOn w:val=\"Normal\"/><w:qFormat/><w:pPr><w:ind w:left=\"720\"/><w:contextualSpacing/></w:pPr></w:style>"
        }
        // The file's character styles, for the kept markup that names
        // them: a footnote's own mark was full size without its "footnote
        // reference" (a training handbook's notes each broke a character
        // early), and ours of a name the file has is not added beside it.
        for id in characterStyles.keys.sorted() { out += characterStyles[id]! }
        for id in tableStyles.keys.sorted() { out += tableStyles[id]! }
        // Word's own note styles, for the notes Starling writes (10 pt single-spaced text, raised reference marks).
        for (kind, name) in [("Footnote", "footnote"), ("Endnote", "endnote")] where notes {
            if !sheet.styles.contains(where: { $0.name.lowercased() == "\(name) text" }) {
                out += "<w:style w:type=\"paragraph\" w:styleId=\"\(kind)Text\"><w:name w:val=\"\(name) text\"/><w:basedOn w:val=\"Normal\"/><w:pPr><w:spacing w:after=\"0\" w:line=\"240\" w:lineRule=\"auto\"/></w:pPr><w:rPr><w:sz w:val=\"20\"/><w:szCs w:val=\"20\"/></w:rPr></w:style>"
            }
            if characterStyleIds["\(name) reference"] == nil, characterStyles["\(kind)Reference"] == nil {
                out += "<w:style w:type=\"character\" w:styleId=\"\(kind)Reference\"><w:name w:val=\"\(name) reference\"/><w:rPr><w:vertAlign w:val=\"superscript\"/></w:rPr></w:style>"
            }
        }
        if characterStyleIds["hyperlink"] == nil, characterStyles["Hyperlink"] == nil {
        out += "<w:style w:type=\"character\" w:styleId=\"Hyperlink\"><w:name w:val=\"Hyperlink\"/><w:rPr><w:color w:val=\"0563C1\"/><w:u w:val=\"single\"/></w:rPr></w:style>"
        }
        // Word's default table style, as Word writes it. Without it Word
        // (in its legacy layout mode) set form_footnotes' tables 5pt to
        // the right of the original's: 12.3% -> 9.9% with it.
        // (A file that already had one keeps its own: two styles with one id is a file Word may refuse.)
        if !tableStyles.values.contains(where: { $0.containsSubstring("w:styleId=\"TableNormal\"") }) {
        out += "<w:style w:type=\"table\" w:default=\"1\" w:styleId=\"TableNormal\"><w:name w:val=\"Normal Table\"/><w:uiPriority w:val=\"99\"/><w:semiHidden/><w:unhideWhenUsed/><w:tblPr><w:tblInd w:w=\"0\" w:type=\"dxa\"/><w:tblCellMar><w:top w:w=\"0\" w:type=\"dxa\"/><w:left w:w=\"108\" w:type=\"dxa\"/><w:bottom w:w=\"0\" w:type=\"dxa\"/><w:right w:w=\"108\" w:type=\"dxa\"/></w:tblCellMar></w:tblPr></w:style>"
        }
        // The file's ids for our styles, for kept markup that names them.
        for (fileId, ours) in aliases.sorted(by: { $0.key < $1.key }) where sheet[ours] != nil || ours == RichNamedStyle.normalId {
            out += "<w:style w:type=\"paragraph\" w:styleId=\"\(_esc(fileId))\"><w:name w:val=\"\(_esc(ours)) \(_esc(fileId))\"/><w:basedOn w:val=\"\(_esc(ours))\"/></w:style>"
        }
        if notes {
            // The marks and the notes' own paragraphs, Word's defaults;
            // a file that defined its own note text style keeps it above.
            for kind in ["Footnote", "Endnote"] {
                if characterStyleIds["\(kind.lowercased()) reference"] == nil, characterStyles["\(kind)Reference"] == nil {
                out += "<w:style w:type=\"character\" w:styleId=\"\(kind)Reference\"><w:name w:val=\"\(kind.lowercased()) reference\"/><w:rPr><w:vertAlign w:val=\"superscript\"/></w:rPr></w:style>"
                }
                if sheet["\(kind)Text"] == nil, !sheet.styles.contains(where: { $0.name.lowercased() == "\(kind.lowercased()) text" }) {
                    out += "<w:style w:type=\"paragraph\" w:styleId=\"\(kind)Text\"><w:name w:val=\"\(kind.lowercased()) text\"/><w:basedOn w:val=\"Normal\"/><w:pPr><w:spacing w:after=\"0\" w:line=\"240\" w:lineRule=\"auto\"/></w:pPr><w:rPr><w:sz w:val=\"20\"/><w:szCs w:val=\"20\"/></w:rPr></w:style>"
                }
            }
        }
        out += "</w:styles>"
        return out
    }
    /// numbering.xml: abstract 0 is bullets (numId 1), abstract 1 plain
    /// decimal (numId 2), then one abstract per list the document has,
    /// carrying its level formats.
    static func _numberingPart(_ kinds: [Int: ListKind], _ formats: [Int: [Int: ListLevelFormat]],
                                       bulletId: Int, decimalId: Int,
                                       counterOf: [Int: String] = [:], restarts: [Int: [Int: Int]] = [:]) -> String {
        var bulletLevels = ""
        var decimalLevels = ""
        let bullets = ["\u{2022}", "o", "\u{25AA}"]
        for i in 0 ..< 9 {
            let left = 720 * (i + 1)
            bulletLevels += "<w:lvl w:ilvl=\"\(i)\"><w:start w:val=\"1\"/><w:numFmt w:val=\"bullet\"/><w:lvlText w:val=\"\(bullets[i % 3])\"/><w:lvlJc w:val=\"left\"/><w:pPr><w:ind w:left=\"\(left)\" w:hanging=\"360\"/></w:pPr>\(i % 3 == 1 ? "<w:rPr><w:rFonts w:ascii=\"Courier New\" w:hAnsi=\"Courier New\"/></w:rPr>" : "")</w:lvl>"
            let fmt = ["decimal", "lowerLetter", "lowerRoman"][i % 3]
            decimalLevels += "<w:lvl w:ilvl=\"\(i)\"><w:start w:val=\"1\"/><w:numFmt w:val=\"\(fmt)\"/><w:lvlText w:val=\"%\(i + 1).\"/><w:lvlJc w:val=\"left\"/><w:pPr><w:ind w:left=\"\(left)\" w:hanging=\"360\"/></w:pPr></w:lvl>"
        }
        var extraAbstract = ""
        var extraNums = ""
        // Lists the file had share one definition when they shared one
        // there, so they still count as one list in Word; the first such
        // list's levels are the definition, and another's differing level
        // is an override of its own.
        var leaderOf: [String: Int] = [:]
        var leaderLevels: [Int: [String]] = [:]
        for numId in kinds.keys.sorted() where numId != bulletId && numId != decimalId {
            var lvls: [String] = []
            for i in 0 ..< 9 {
                var levels = ""
                let own = formats[numId]?[i]
                let left = own?.indentLeft.map { Int(($0 * 20).rounded()) } ?? 720 * (i + 1)
                let hang = own?.hanging.map { Int(($0 * 20).rounded()) } ?? 360
                let ind = hang >= 0 ? "<w:ind w:left=\"\(left)\" w:hanging=\"\(hang)\"/>" : "<w:ind w:left=\"\(left)\" w:firstLine=\"\(-hang)\"/>"
                let suff = own?.suffix.map { "<w:suff w:val=\"\(_esc($0))\"/>" } ?? ""
                let numRPr = own?.numberRPrXML ?? ""
                if kinds[numId] == .bullet {
                    var glyph = formats[numId]?[i].flatMap { $0.format == .bullet ? $0.text : nil } ?? bullets[i % 3]
                    if let own, let raw = own.rawText, own.rawTextGlyph == own.text, own.numberRPrXML != nil { glyph = raw }
                    levels += "<w:lvl w:ilvl=\"\(i)\"><w:start w:val=\"1\"/><w:numFmt w:val=\"bullet\"/>\(suff)<w:lvlText w:val=\"\(_esc(glyph))\"/><w:lvlJc w:val=\"left\"/><w:pPr>\(ind)</w:pPr>\(numRPr)</w:lvl>"
                } else {
                    let f = formats[numId]?[i] ?? .plain(i)
                    let fmt: String
                    switch f.format {
                    case .decimal: fmt = "decimal"
                    case .lowerLetter: fmt = "lowerLetter"
                    case .upperLetter: fmt = "upperLetter"
                    case .lowerRoman: fmt = "lowerRoman"
                    case .upperRoman: fmt = "upperRoman"
                    case .bullet: fmt = "bullet"
                    }
                    let numFmt = f.rawFormat.map { $0.hasPrefix("custom:") }  == true
                        ? "<mc:AlternateContent><mc:Choice Requires=\"w14\"><w:numFmt w:val=\"custom\" w:format=\"\(_esc(String(f.rawFormat!.dropFirst(7))))\"/></mc:Choice><mc:Fallback><w:numFmt w:val=\"decimal\"/></mc:Fallback></mc:AlternateContent>"
                        : "<w:numFmt w:val=\"\(_esc(f.rawFormat ?? fmt))\"/>"
                    levels += "<w:lvl w:ilvl=\"\(i)\"><w:start w:val=\"\(f.start ?? 1)\"/>\(numFmt)\(suff)<w:lvlText w:val=\"\(_esc(f.text))\"/><w:lvlJc w:val=\"\(_esc(f.justification ?? "left"))\"/><w:pPr>\(ind)</w:pPr>\(numRPr)</w:lvl>"
                }
                lvls.append(levels)
            }
            var leader = numId
            if let key = counterOf[numId] {
                if let l = leaderOf[key] { leader = l } else { leaderOf[key] = numId }
            }
            var overrides = ""
            if leader == numId {
                leaderLevels[numId] = lvls
                extraAbstract += "<w:abstractNum w:abstractNumId=\"\(numId + 1)\"><w:multiLevelType w:val=\"hybridMultilevel\"/>\(lvls.joined())</w:abstractNum>"
            }
            for i in 0 ..< 9 {
                let restart = restarts[numId]?[i].map { "<w:startOverride w:val=\"\($0)\"/>" } ?? ""
                let own = leader != numId && leaderLevels[leader]?[i] != lvls[i] ? lvls[i] : ""
                if !restart.isEmpty || !own.isEmpty { overrides += "<w:lvlOverride w:ilvl=\"\(i)\">\(restart)\(own)</w:lvlOverride>" }
            }
            extraNums += "<w:num w:numId=\"\(numId)\"><w:abstractNumId w:val=\"\(leader + 1)\"/>\(overrides)</w:num>"
        }
        return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<w:numbering xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" xmlns:mc=\"http://schemas.openxmlformats.org/markup-compatibility/2006\" xmlns:w14=\"http://schemas.microsoft.com/office/word/2010/wordml\" xmlns:w15=\"http://schemas.microsoft.com/office/word/2012/wordml\" mc:Ignorable=\"w14 w15\"><w:abstractNum w:abstractNumId=\"0\"><w:multiLevelType w:val=\"hybridMultilevel\"/>\(bulletLevels)</w:abstractNum><w:abstractNum w:abstractNumId=\"1\"><w:multiLevelType w:val=\"hybridMultilevel\"/>\(decimalLevels)</w:abstractNum>\(extraAbstract)<w:num w:numId=\"\(bulletId)\"><w:abstractNumId w:val=\"0\"/></w:num><w:num w:numId=\"\(decimalId)\"><w:abstractNumId w:val=\"1\"/></w:num>\(extraNums)</w:numbering>"
    }
}
