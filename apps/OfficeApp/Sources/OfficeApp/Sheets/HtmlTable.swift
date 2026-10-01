// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Cells to and from other apps as an HTML table, beside the TSV text.
// Copying writes both, so a paste into Writer, Mail or Word keeps the
// table and its formatting; pasting reads a table from Excel, Numbers,
// Google Sheets or a web page and keeps bold, italic, colours, fills and
// alignment. Excel styles its cells by class (`.xl65`) from a <style>
// block, the others inline — both are read.

import Foundation

/// One cell of a pasted table: its shown text and what styling it carried.
struct PastedCell: Equatable {
    var text: String
    var style: CellStyle? = nil
}

enum HtmlTable {
    // MARK: Writing

    static func render(_ c: WorkbookController, _ r: CellRange, rows: ClosedRange<Int>, cols: ClosedRange<Int>) -> String {
        let ws = c.sheet
        // A merge's top-left spans; the cells under it are not written.
        let merges = ws.merges.filter { r.contains($0.topLeft) }
        var covered = Set<CellAddress>()
        for m in merges {
            for row in m.top ... m.bottom { for col in m.left ... m.right where !(row == m.top && col == m.left) {
                covered.insert(CellAddress(row: row, col: col))
            } }
        }
        var out = "<meta charset=\"utf-8\"><table style=\"border-collapse:collapse\">"
        for row in rows {
            out += "<tr>"
            for col in cols {
                let a = CellAddress(row: row, col: col)
                if covered.contains(a) { continue }
                let st = c.style(at: a)
                let v = ws.value(a)
                let shown = NumberFormat.display(v, st.numberFormat, width: 255)
                // Character styling on an inner span (Writer and most editors
                // read text styles from runs, not cells); the cell's own
                // fill and alignment on the td.
                var css: [String] = [], run: [String] = []
                if let f = st.fontName { run.append("font-family:'\(f)'") }
                if let s = st.fontSize { run.append("font-size:\(NumberFormat.general(s))pt") }
                if st.bold { run.append("font-weight:bold") }
                if st.italic { run.append("font-style:italic") }
                if st.underline || st.strike {
                    run.append("text-decoration:" + [st.underline ? "underline" : nil, st.strike ? "line-through" : nil]
                        .compactMap { $0 }.joined(separator: " "))
                }
                if let ink = shown.color ?? st.color { run.append("color:\(_hex(ink))") }
                if let fill = st.fill { css.append("background:\(_hex(fill))") }
                var align = st.hAlign
                if align == .general, case .number = v { align = .right }
                if align != .general { css.append("text-align:\(align.rawValue)") }
                if st.wrap { css.append("white-space:normal") }
                var attrs = css.isEmpty ? "" : " style=\"\(css.joined(separator: ";"))\""
                if let m = merges.first(where: { $0.topLeft == a }) {
                    if m.cols > 1 { attrs += " colspan=\"\(m.cols)\"" }
                    if m.rows > 1 { attrs += " rowspan=\"\(m.rows)\"" }
                }
                let text = _escape(shown.text)
                out += "<td\(attrs)>" + (run.isEmpty ? text : "<span style=\"\(run.joined(separator: ";"))\">\(text)</span>") + "</td>"
            }
            out += "</tr>"
        }
        return out + "</table>"
    }

    private static func _hex(_ rgb: UInt32) -> String {
        let digits = Array("0123456789ABCDEF")
        var s = "#"
        for shift in stride(from: 20, through: 0, by: -4) { s.append(digits[Int((rgb >> UInt32(shift)) & 0xF)]) }
        return s
    }

    private static func _escape(_ s: String) -> String {
        var out = ""
        for ch in s {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\n": out += "<br>"
            default: out.append(ch)
            }
        }
        return out
    }

    // MARK: Reading

    /// The first table in `html`, row by row; nil when there is none. A
    /// colspan is padded with empty cells so columns line up; a rowspan
    /// leaves its rows' cells to the right of it, as Excel pastes them.
    static func parse(_ html: String) -> [[PastedCell]]? {
        let chars = Array(html)
        var classes: [String: [String: String]] = [:]
        var rows: [[PastedCell]] = []
        var row: [PastedCell]? = nil
        var cell: (text: String, style: CellStyle, span: Int)? = nil
        var inTable = 0, sawTable = false
        var pendingSpaces = false
        // Rowspans still open: column → rows left.
        var spans: [Int: Int] = [:]
        var styleStack: [CellStyle] = []
        var i = 0
        func padRowspans() {
            guard row != nil else { return }
            while let left = spans[row!.count], left > 0 {
                spans[row!.count] = left - 1
                row!.append(PastedCell(text: ""))
            }
        }
        while i < chars.count {
            if chars[i] == "<" {
                guard let close = _index(of: ">", in: chars, from: i) else { break }
                let tag = String(chars[(i + 1) ..< close])
                i = close + 1
                if tag.hasPrefix("!--") {
                    // A comment: skip to its end (Excel wraps conditional bits in them).
                    if let end = _find("-->", in: chars, from: close - 2) { i = end + 3 }
                    continue
                }
                let (name, attrs, closing) = _tag(tag)
                switch name {
                case "style" where !closing:
                    if let end = _find("</style", in: chars, from: i, caseInsensitive: true) {
                        classes.merge(_classes(String(chars[i ..< end])), uniquingKeysWith: { $1 })
                        i = end
                    }
                case "script" where !closing:
                    if let end = _find("</script", in: chars, from: i, caseInsensitive: true) { i = end }
                case "table":
                    if closing { inTable -= 1; if inTable == 0 && sawTable { return rows } } else { inTable += 1; sawTable = true }
                case "tr" where inTable > 0:
                    if let r = row { rows.append(r) }
                    row = closing ? nil : []
                    if !closing { padRowspans() }
                    if closing {
                        for (k, v) in spans { spans[k] = v > 0 ? v : nil }
                    }
                case "td", "th":
                    guard inTable > 0 else { break }
                    if closing {
                        if let c = cell {
                            if row == nil { row = [] }
                            row!.append(PastedCell(text: c.text.trimmingWhitespace(), style: c.style == .plain ? nil : c.style))
                            for _ in 1 ..< max(1, c.span) { row!.append(PastedCell(text: "")) }
                            cell = nil
                            padRowspans()
                        }
                    } else {
                        if row == nil { row = [] }
                        var st = CellStyle()
                        if name == "th" { st.bold = true }
                        for cls in (attrs["class"] ?? "").split(separator: " ") {
                            if let decl = classes[String(cls).lowercased()] { _apply(decl, to: &st) }
                        }
                        if let inline = attrs["style"] { _apply(_declarations(inline), to: &st) }
                        if let a = attrs["align"] { st.hAlign = CellStyle.HAlign(rawValue: a.lowercased()) ?? st.hAlign }
                        if let bg = attrs["bgcolor"], let rgb = _color(bg) { st.fill = rgb }
                        let span = Int(attrs["colspan"] ?? "") ?? 1
                        if let rs = Int(attrs["rowspan"] ?? ""), rs > 1, let r = row {
                            for k in 0 ..< max(1, span) { spans[r.count + k] = rs - 1 }
                        }
                        cell = ("", st, span)
                        styleStack = [st]
                        pendingSpaces = false
                    }
                case "br":
                    if cell != nil { cell!.text += "\n" }
                case "p", "div":
                    if cell != nil && closing { cell!.text += "\n" }
                case "b", "strong", "i", "em", "u", "font", "span":
                    guard cell != nil else { break }
                    if closing {
                        if styleStack.count > 1 { styleStack.removeLast() }
                    } else {
                        var st = styleStack.last ?? CellStyle()
                        if name == "b" || name == "strong" { st.bold = true }
                        if name == "i" || name == "em" { st.italic = true }
                        if name == "u" { st.underline = true }
                        if let c = attrs["color"], let rgb = _color(c) { st.color = rgb }
                        if let inline = attrs["style"] { _apply(_declarations(inline), to: &st) }
                        styleStack.append(st)
                        // A cell's text is styled whole: what the first run
                        // inside it says is what the cell takes.
                        if cell!.text.isEmpty { cell!.style = st }
                    }
                default: break
                }
                continue
            }
            // Text.
            if cell != nil {
                var ch = chars[i]
                if ch == "&", let semi = _index(of: ";", in: chars, from: i), semi - i <= 10 {
                    if let decoded = _entity(String(chars[(i + 1) ..< semi])) {
                        ch = decoded
                        i = semi
                    }
                    if ch == "\u{A0}" { cell!.text.append(" "); i += 1; continue }
                }
                if ch == " " || ch == "\n" || ch == "\r" || ch == "\t" {
                    pendingSpaces = true
                } else {
                    if pendingSpaces && !cell!.text.isEmpty && !cell!.text.hasSuffix("\n") { cell!.text.append(" ") }
                    pendingSpaces = false
                    cell!.text.append(ch)
                }
            }
            i += 1
        }
        if let r = row, !r.isEmpty { rows.append(r) }
        return sawTable && !rows.isEmpty ? rows : nil
    }

    // MARK: Pieces

    private static func _index(of c: Character, in chars: [Character], from: Int) -> Int? {
        var j = from
        while j < chars.count { if chars[j] == c { return j }; j += 1 }
        return nil
    }

    private static func _find(_ s: String, in chars: [Character], from: Int, caseInsensitive: Bool = false) -> Int? {
        let needle = Array(caseInsensitive ? s.lowercased() : s)
        guard !needle.isEmpty, chars.count >= needle.count else { return nil }
        var j = max(0, from)
        while j + needle.count <= chars.count {
            var k = 0
            while k < needle.count {
                let c = caseInsensitive ? Character(chars[j + k].lowercased()) : chars[j + k]
                if c != needle[k] { break }
                k += 1
            }
            if k == needle.count { return j }
            j += 1
        }
        return nil
    }

    /// `td class=xl65 style="..."` → ("td", attributes, closing?).
    static func _tag(_ raw: String) -> (String, [String: String], Bool) {
        var s = Substring(raw)
        let closing = s.hasPrefix("/")
        if closing { s = s.dropFirst() }
        if s.hasSuffix("/") { s = s.dropLast() }
        let chars = Array(s)
        var j = 0
        var name = ""
        while j < chars.count, !chars[j].isWhitespace { name.append(chars[j]); j += 1 }
        var attrs: [String: String] = [:]
        while j < chars.count {
            while j < chars.count, chars[j].isWhitespace { j += 1 }
            var key = ""
            while j < chars.count, chars[j] != "=", !chars[j].isWhitespace { key.append(chars[j]); j += 1 }
            while j < chars.count, chars[j].isWhitespace { j += 1 }
            var value = ""
            if j < chars.count, chars[j] == "=" {
                j += 1
                while j < chars.count, chars[j].isWhitespace { j += 1 }
                if j < chars.count, chars[j] == "\"" || chars[j] == "'" {
                    let q = chars[j]; j += 1
                    while j < chars.count, chars[j] != q { value.append(chars[j]); j += 1 }
                    j += 1
                } else {
                    while j < chars.count, !chars[j].isWhitespace { value.append(chars[j]); j += 1 }
                }
            }
            if !key.isEmpty { attrs[key.lowercased()] = value }
        }
        return (name.lowercased(), attrs, closing)
    }

    /// `.xl65 { font-weight:700; color:red }` → ["xl65": [...]]. Only
    /// plain class selectors; Excel writes `td.xl65` too.
    static func _classes(_ css: String) -> [String: [String: String]] {
        var out: [String: [String: String]] = [:]
        var rest = Substring(css)
        while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
            let selectors = rest[rest.startIndex ..< open]
            let decl = _declarations(String(rest[rest.index(after: open) ..< close]))
            for sel in selectors.split(separator: ",") {
                let t = sel.trimmingWhitespace()
                guard let dot = t.lastIndex(of: ".") else { continue }
                let name = String(t[t.index(after: dot)...]).lowercased()
                if !name.isEmpty { out[name, default: [:]].merge(decl, uniquingKeysWith: { $1 }) }
            }
            rest = rest[rest.index(after: close)...]
        }
        return out
    }

    static func _declarations(_ s: String) -> [String: String] {
        var out: [String: String] = [:]
        for part in s.split(separator: ";") {
            guard let colon = part.firstIndex(of: ":") else { continue }
            let k = part[part.startIndex ..< colon].trimmingWhitespace().lowercased()
            let v = part[part.index(after: colon)...].trimmingWhitespace()
            out[k] = v.replacingAll("!important", with: "").trimmingWhitespace()
        }
        return out
    }

    private static func _apply(_ d: [String: String], to st: inout CellStyle) {
        if let w = d["font-weight"]?.lowercased() {
            st.bold = w == "bold" || w == "bolder" || (Int(w) ?? 400) >= 600
        }
        if let f = d["font-style"]?.lowercased() { st.italic = f == "italic" || f == "oblique" }
        if let t = d["text-decoration"]?.lowercased() ?? d["text-decoration-line"]?.lowercased() {
            st.underline = t.containsSubstring("underline")
            st.strike = t.containsSubstring("line-through")
        }
        if let c = d["color"], let rgb = _color(c) { st.color = rgb == 0 ? nil : rgb }
        if let b = d["background-color"] ?? d["background"], let rgb = _color(b) { st.fill = rgb == 0xFFFFFF ? nil : rgb }
        if let a = d["text-align"]?.lowercased() { st.hAlign = CellStyle.HAlign(rawValue: a) ?? st.hAlign }
        if let size = d["font-size"]?.lowercased() {
            if size.hasSuffix("pt"), let v = Double(size.dropLast(2)) { st.fontSize = v == 11 ? nil : v }
            else if size.hasSuffix("px"), let v = Double(size.dropLast(2)) { st.fontSize = (v * 0.75 * 2).rounded() / 2 }
        }
        if let fam = d["font-family"] {
            let first = fam.split(separator: ",").first.map { $0.trimmingWhitespace() } ?? ""
            let name = first.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            let generic: Set<String> = ["serif", "sans-serif", "monospace", "system-ui", "-apple-system", "arial"]
            if !name.isEmpty && !generic.contains(name.lowercased()) && name != OfficeFonts.defaultFamily { st.fontName = name }
        }
        if let ws = d["white-space"]?.lowercased() { st.wrap = ws == "normal" || ws == "pre-wrap" }
    }

    static func _color(_ s: String) -> UInt32? {
        let v = s.trimmingWhitespace().lowercased()
        if v.hasPrefix("#") {
            let hex = Array(v.dropFirst())
            if hex.count == 3 {
                guard let n = UInt32(String(hex), radix: 16) else { return nil }
                let r = (n >> 8) & 0xF, g = (n >> 4) & 0xF, b = n & 0xF
                return (r * 17) << 16 | (g * 17) << 8 | b * 17
            }
            guard hex.count >= 6 else { return nil }
            return UInt32(String(hex.prefix(6)), radix: 16)
        }
        if v.hasPrefix("rgb") {
            guard let open = v.firstIndex(of: "("), let close = v.firstIndex(of: ")") else { return nil }
            let parts = v[v.index(after: open) ..< close].split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" })
                .compactMap { Double($0) }
            guard parts.count >= 3 else { return nil }
            if parts.count >= 4 && parts[3] == 0 { return nil }   // transparent
            return UInt32(parts[0]) << 16 | UInt32(parts[1]) << 8 | UInt32(parts[2])
        }
        let named: [String: UInt32] = [
            "black": 0x000000, "white": 0xFFFFFF, "red": 0xFF0000, "green": 0x008000, "blue": 0x0000FF,
            "yellow": 0xFFFF00, "gray": 0x808080, "grey": 0x808080, "silver": 0xC0C0C0, "maroon": 0x800000,
            "navy": 0x000080, "purple": 0x800080, "teal": 0x008080, "olive": 0x808000, "orange": 0xFFA500,
        ]
        return named[v]
    }

    private static func _entity(_ name: String) -> Character? {
        switch name {
        case "amp": return "&"
        case "lt": return "<"
        case "gt": return ">"
        case "quot": return "\""
        case "apos", "#39": return "'"
        case "nbsp", "#160": return "\u{A0}"
        default:
            if name.hasPrefix("#x"), let n = UInt32(name.dropFirst(2), radix: 16), let u = Unicode.Scalar(n) { return Character(u) }
            if name.hasPrefix("#"), let n = UInt32(name.dropFirst()), let u = Unicode.Scalar(n) { return Character(u) }
            return nil
        }
    }
}

extension WorkbookController {
    /// Paste rows of cells from another app at the selection's top-left, as
    /// one undo step: each text goes in as if typed, and a carried style
    /// replaces the cell's.
    func pasteTable(_ rows: [[PastedCell]]) {
        let origin = selection.topLeft
        let ws = sheet
        var before: [CellAddress: Cell?] = [:]
        var items: [(CellAddress, String)] = []
        for (i, row) in rows.enumerated() {
            for (j, p) in row.enumerated() {
                let a = CellAddress(row: origin.row + i, col: origin.col + j)
                guard a.row < CellAddress.maxRows, a.col < CellAddress.maxCols else { continue }
                before[a] = .some(ws.cells[a])
                if let st = p.style {
                    var cell = ws.cells[a] ?? Cell(input: "")
                    cell.style = book.styleIndex(st)
                    ws.cells[a] = cell
                }
                items.append((a, p.text))
            }
        }
        guard !items.isEmpty else { return }
        // setInputs records its own step; fold the style change into it by
        // restoring `before` as that step's starting point.
        setInputs(items)
        _foldLastStep(before: before)
        let h = rows.count, w = rows.map(\.count).max() ?? 1
        select(range: CellRange(top: origin.row, left: origin.col, bottom: origin.row + h - 1, right: origin.col + w - 1),
               active: origin)
    }
}
