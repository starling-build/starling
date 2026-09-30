// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// HTML, the clipboard's lingua franca: what a browser, Pages or Mail puts
// on the pasteboard, and what other apps read from ours. The reader takes
// the subset a document model can hold — p, h1–h6, b/strong, i/em, u, s,
// a, ul/ol/li, blockquote, pre/code, table/tr/td/th, br, img (data URLs) —
// and the writer emits the same subset, one element per paragraph.

import Flutter
import FlutterSwiftBridge
import Foundation

enum HtmlFormat {
    // MARK: Reading

    /// Paragraphs from an HTML fragment or document; nil when nothing in it
    /// is text.
    static func parse(_ html: String, sheet: RichStyleSheet = OfficeStyles.sheet) -> [RichParagraph]? {
        let tokens = _tokenize(html)
        var out: [RichParagraph] = []
        var text = ""
        var runs: [Run] = []
        var style = RichParagraphStyle.body
        var char = CharStyle()
        var charStack: [CharStyle] = []
        var listStack: [ListKind] = []
        var pre = 0
        var table: (id: String, row: Int, col: Int)? = nil
        var tableCount = 0
        var open = false          // a block has content pending
        var inHead = 0            // text inside <head> is not content

        func emit(_ piece: String) {
            guard !piece.isEmpty else { return }
            text += piece
            runs.append(Run(length: piece.utf16.count, style: char))
            open = true
        }
        func flush() {
            guard open || !text.isEmpty else { return }
            var p = RichParagraph(text: text, runs: runs.isEmpty ? nil : runs, style: style)
            p.normalize()
            if let t = table { p.cell = CellRef(table: t.id, row: t.row, column: t.col) }
            out.append(p)
            text = ""; runs = []; open = false
        }
        func startBlock(_ s: RichParagraphStyle) {
            flush()
            style = s
            if let kind = listStack.last { style.list = kind; style.listLevel = max(0, listStack.count - 1) }
        }

        for token in tokens {
            switch token {
            case .text(var t):
                if inHead > 0 { continue }
                if pre == 0 {
                    t = t.replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\n", with: " ")
                    t = t.replacingOccurrences(of: "\t", with: " ")
                    while t.contains("  ") { t = t.replacingOccurrences(of: "  ", with: " ") }
                    if text.isEmpty || text.hasSuffix(" ") { t = String(t.drop(while: { $0 == " " })) }
                    if t.isEmpty { continue }
                    emit(t)
                } else {
                    // Preformatted: each line its own Code paragraph.
                    let lines = t.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
                    for (i, line) in lines.enumerated() {
                        if i > 0 { flush(); var s = RichParagraphStyle.body; sheet.apply("Code", to: &s); style = s; open = true }
                        emit(String(line))
                        open = true
                    }
                }
            case .open(let name, let attrs):
                switch name {
                case "p", "div", "section", "article", "header", "footer", "main":
                    startBlock(.body)
                case "h1", "h2", "h3", "h4", "h5", "h6":
                    startBlock(.body)
                    sheet.apply(RichNamedStyle.headingId(Int(String(name.last!))!), to: &style)
                case "blockquote":
                    startBlock(.body)
                    sheet.apply("Quote", to: &style)
                case "pre":
                    startBlock(.body)
                    sheet.apply("Code", to: &style)
                    pre += 1
                case "ul": flush(); listStack.append(.bullet)
                case "ol": flush(); listStack.append(.numbered)
                case "li":
                    startBlock(.body)
                    open = true
                case "br": emit("\n")
                case "b", "strong": charStack.append(char); char.bold = true
                case "i", "em": charStack.append(char); char.italic = true
                case "u": charStack.append(char); char.underline = true
                case "s", "strike", "del": charStack.append(char); char.strikethrough = true
                case "sup": charStack.append(char); char.script = .superscript
                case "sub": charStack.append(char); char.script = .subscript
                case "code", "tt", "kbd":
                    charStack.append(char)
                    if pre == 0 { char.fontFamily = OfficeFonts.mono }
                case "a":
                    charStack.append(char)
                    if let href = attrs["href"], !href.isEmpty { char.link = href }
                case "span", "font":
                    charStack.append(char)
                    if let st = attrs["style"] { _applyInlineStyle(st, to: &char) }
                case "table":
                    flush()
                    tableCount += 1
                    table = ("h\(tableCount)", -1, 0)
                case "tr":
                    flush()
                    if table != nil { table!.row += 1; table!.col = -1 }
                case "td", "th":
                    if table != nil { table!.col += 1 }
                    startBlock(.body)
                    if name == "th" { char.bold = true }
                    open = true
                case "img":
                    if let src = attrs["src"], src.hasPrefix("data:image/"),
                       let comma = src.firstIndex(of: ","),
                       let data = Data(base64Encoded: String(src[src.index(after: comma)...]).trimmingCharacters(in: .whitespacesAndNewlines)),
                       let px = ImageAttachment.pngPixelSize(data) {
                        flush()
                        var w = Double(attrs["width"].flatMap(Double.init) ?? Double(px.width) * 0.75)
                        var h = Double(attrs["height"].flatMap(Double.init) ?? Double(px.height) * 0.75)
                        if w > 468 { h *= 468 / w; w = 468 }
                        out.append(RichParagraph(image: ImageAttachment(data: data, width: w, height: h)))
                    }
                case "head": inHead += 1
                default: break
                }
            case .close(let name):
                switch name {
                case "head": inHead = max(0, inHead - 1)
                case "p", "div", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "li", "section", "article", "td", "th":
                    flush()
                    if name == "th" { char.bold = false }
                    if name == "td" || name == "th" { open = false }
                    style = .body
                case "pre": flush(); pre = max(0, pre - 1); style = .body
                case "ul", "ol": flush(); _ = listStack.popLast()
                case "table": flush(); table = nil
                case "b", "strong", "i", "em", "u", "s", "strike", "del", "sup", "sub", "code", "tt", "kbd", "a", "span", "font":
                    if let prev = charStack.popLast() { char = prev }
                default: break
                }
            }
        }
        flush()
        return out.isEmpty ? nil : out
    }

    private static func _applyInlineStyle(_ css: String, to char: inout CharStyle) {
        for decl in css.split(separator: ";") {
            let parts = decl.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            guard parts.count == 2 else { continue }
            switch parts[0] {
            case "font-weight": if parts[1] == "bold" || (Int(parts[1]) ?? 0) >= 600 { char.bold = true }
            case "font-style": if parts[1] == "italic" { char.italic = true }
            case "text-decoration", "text-decoration-line":
                if parts[1].contains("underline") { char.underline = true }
                if parts[1].contains("line-through") { char.strikethrough = true }
            case "color": if let c = _color(parts[1]) { char.color = c }
            case "background-color", "background": if let c = _color(parts[1]) { char.highlight = c }
            case "font-size":
                if parts[1].hasSuffix("pt"), let v = Double(parts[1].dropLast(2)) { char.fontSize = v }
                else if parts[1].hasSuffix("px"), let v = Double(parts[1].dropLast(2)) { char.fontSize = v * 0.75 }
            default: break
            }
        }
    }

    private static func _color(_ s: String) -> Color? {
        if s.hasPrefix("#") {
            let hex = String(s.dropFirst())
            if hex.count == 6, let v = Int(hex, radix: 16) { return Color(0xFF000000 | v) }
            if hex.count == 3, let v = Int(hex, radix: 16) {
                let r = (v >> 8) & 0xF, g = (v >> 4) & 0xF, b = v & 0xF
                return Color(0xFF000000 | (r * 17) << 16 | (g * 17) << 8 | (b * 17))
            }
        }
        if s.hasPrefix("rgb(") {
            let nums = s.dropFirst(4).dropLast().split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            if nums.count == 3 { return Color(0xFF000000 | nums[0] << 16 | nums[1] << 8 | nums[2]) }
        }
        return nil
    }

    // MARK: Tokenizer

    private enum Token { case text(String), open(String, [String: String]), close(String) }

    private static func _tokenize(_ html: String) -> [Token] {
        var out: [Token] = []
        let chars = Array(html)
        var i = 0
        var text = ""
        func flushText() { if !text.isEmpty { out.append(.text(_unescape(text))); text = "" } }
        while i < chars.count {
            let c = chars[i]
            if c == "<" {
                if i + 3 < chars.count, chars[i + 1] == "!", chars[i + 2] == "-", chars[i + 3] == "-" {
                    // A comment.
                    if let end = _find("-->", chars, from: i + 4) { i = end + 3 } else { i = chars.count }
                    continue
                }
                guard let end = _find(">", chars, from: i + 1) else { break }
                let inner = String(chars[(i + 1) ..< end]).trimmingCharacters(in: .whitespacesAndNewlines)
                i = end + 1
                if inner.hasPrefix("!") || inner.hasPrefix("?") { continue }
                flushText()
                if inner.hasPrefix("/") {
                    out.append(.close(String(inner.dropFirst()).trimmingCharacters(in: .whitespaces).lowercased()))
                    continue
                }
                var body = Substring(inner)
                let selfClosing = body.hasSuffix("/")
                if selfClosing { body = body.dropLast() }
                let nameEnd = body.firstIndex(where: { $0 == " " || $0 == "\n" || $0 == "\t" }) ?? body.endIndex
                let name = String(body[..<nameEnd]).lowercased()
                let attrs = _attributes(String(body[nameEnd...]))
                out.append(.open(name, attrs))
                if selfClosing || name == "br" || name == "img" || name == "hr" { if name != "br" && name != "img" { out.append(.close(name)) } }
                if name == "script" || name == "style" || name == "title" {
                    // Skip to the closing tag.
                    let closeTag = "</" + name
                    if let e = _find(closeTag, chars, from: i), let gt = _find(">", chars, from: e) { i = gt + 1 } else { i = chars.count }
                    out.append(.close(name))
                }
            } else {
                text.append(c)
                i += 1
            }
        }
        flushText()
        return out
    }

    private static func _attributes(_ s: String) -> [String: String] {
        var out: [String: String] = [:]
        let chars = Array(s)
        var i = 0
        while i < chars.count {
            while i < chars.count, chars[i].isWhitespace { i += 1 }
            var name = ""
            while i < chars.count, !chars[i].isWhitespace, chars[i] != "=" { name.append(chars[i]); i += 1 }
            if name.isEmpty { break }
            while i < chars.count, chars[i].isWhitespace { i += 1 }
            var value = ""
            if i < chars.count, chars[i] == "=" {
                i += 1
                while i < chars.count, chars[i].isWhitespace { i += 1 }
                if i < chars.count, chars[i] == "\"" || chars[i] == "'" {
                    let q = chars[i]; i += 1
                    while i < chars.count, chars[i] != q { value.append(chars[i]); i += 1 }
                    i += 1
                } else {
                    while i < chars.count, !chars[i].isWhitespace { value.append(chars[i]); i += 1 }
                }
            }
            out[name.lowercased()] = _unescape(value)
        }
        return out
    }

    private static func _find(_ needle: String, _ chars: [Character], from: Int) -> Int? {
        let n = Array(needle)
        var i = from
        while i + n.count <= chars.count {
            if Array(chars[i ..< i + n.count]) == n { return i }
            i += 1
        }
        return nil
    }

    private static func _unescape(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = s
        for (e, r) in [("&nbsp;", "\u{00A0}"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'")] {
            out = out.replacingOccurrences(of: e, with: r)
        }
        // Numeric entities.
        while let amp = out.range(of: "&#") {
            guard let semi = out[amp.upperBound...].firstIndex(of: ";") else { break }
            let body = out[amp.upperBound ..< semi]
            let value = body.hasPrefix("x") || body.hasPrefix("X") ? Int(body.dropFirst(), radix: 16) : Int(body)
            guard let v = value, let scalar = UnicodeScalar(v) else { out.replaceSubrange(amp, with: "&#;"); continue }
            out.replaceSubrange(amp.lowerBound ... semi, with: String(Character(scalar)))
        }
        return out.replacingOccurrences(of: "&amp;", with: "&")
    }

    // MARK: Writing

    /// A fragment or document as HTML, one element per paragraph, inline
    /// formatting as tags, pictures as data URLs, tables as tables.
    static func render(_ paragraphs: [RichParagraph], styles: RichStyleSheet = OfficeStyles.sheet) -> String {
        var out = "<html><body>"
        var i = 0
        var listOpen: ListKind? = nil
        func closeList() { if let k = listOpen { out += k == .bullet ? "</ul>" : "</ol>"; listOpen = nil } }
        while i < paragraphs.count {
            let p = paragraphs[i]
            if let cell = p.cell {
                closeList()
                var end = i
                while end < paragraphs.count, paragraphs[end].cell?.table == cell.table { end += 1 }
                let members = paragraphs[i ..< end]
                let rows = (members.compactMap { $0.cell?.row }.max() ?? 0) + 1
                let cols = (members.compactMap { $0.cell?.column }.max() ?? 0) + 1
                out += "<table border=\"1\" cellspacing=\"0\" cellpadding=\"4\">"
                for r in 0 ..< rows {
                    out += "<tr>"
                    for c in 0 ..< cols {
                        out += "<td>"
                        out += members.filter { $0.cell?.row == r && $0.cell?.column == c }.map { _inline($0) }.joined(separator: "<br>")
                        out += "</td>"
                    }
                    out += "</tr>"
                }
                out += "</table>"
                i = end
                continue
            }
            if let image = p.image {
                closeList()
                let mime = image.isJPEG ? "image/jpeg" : image.isGIF ? "image/gif" : "image/png"
                out += "<p><img src=\"data:\(mime);base64,\(image.data.base64EncodedString())\" width=\"\(Int(image.width))\" height=\"\(Int(image.height))\"></p>"
                i += 1
                continue
            }
            if let kind = p.style.list {
                if listOpen != kind { closeList(); out += kind == .bullet ? "<ul>" : "<ol>"; listOpen = kind }
                out += "<li>\(_inline(p))</li>"
                i += 1
                continue
            }
            closeList()
            let named = styles.resolve(p.style)
            let tag: String
            if let h = p.style.heading { tag = "h\(min(6, max(1, h)))" }
            else if named?.id == "Quote" { tag = "blockquote" }
            else if named?.id == "Code" { tag = "pre" }
            else { tag = "p" }
            var attrs = ""
            switch p.style.alignment {
            case .left: break
            case .center: attrs = " style=\"text-align:center\""
            case .right: attrs = " style=\"text-align:right\""
            case .justify: attrs = " style=\"text-align:justify\""
            }
            out += "<\(tag)\(attrs)>\(_inline(p))</\(tag)>"
            i += 1
        }
        closeList()
        return out + "</body></html>"
    }

    private static func _inline(_ p: RichParagraph) -> String {
        var out = ""
        var pos = 0
        let utf16 = p.text.utf16
        for run in p.runs where run.length > 0 {
            let a = utf16.index(utf16.startIndex, offsetBy: pos)
            let b = utf16.index(a, offsetBy: run.length)
            var piece = _escape(String(utf16[a ..< b]) ?? "").replacingOccurrences(of: "\n", with: "<br>")
            pos += run.length
            let s = run.style
            var css: [String] = []
            if let c = s.color { css.append("color:#\(_hex(c))") }
            if let c = s.highlight { css.append("background-color:#\(_hex(c))") }
            if let size = s.fontSize { css.append("font-size:\(size)pt") }
            if let family = s.fontFamily, family != OfficeFonts.mono { css.append("font-family:'\(family)'") }
            if !css.isEmpty { piece = "<span style=\"\(css.joined(separator: ";"))\">\(piece)</span>" }
            if s.fontFamily == OfficeFonts.mono { piece = "<code>\(piece)</code>" }
            if s.bold { piece = "<b>\(piece)</b>" }
            if s.italic { piece = "<i>\(piece)</i>" }
            if s.underline { piece = "<u>\(piece)</u>" }
            if s.strikethrough { piece = "<s>\(piece)</s>" }
            if s.script == .superscript { piece = "<sup>\(piece)</sup>" }
            if s.script == .subscript { piece = "<sub>\(piece)</sub>" }
            if let link = s.link { piece = "<a href=\"\(_escape(link))\">\(piece)</a>" }
            out += piece
        }
        return out
    }

    private static func _escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func _hex(_ c: Color) -> String { String(format: "%06X", c.value & 0xFFFFFF) }
}

/// Writer's clipboard: RTF and HTML out, RTF or HTML in, through the
/// formats the app already speaks.
struct OfficeClipboardCodec: RichClipboardCodec {
    func encode(_ fragment: [RichParagraph], styles: RichStyleSheet, text: String) -> ClipboardData {
        var doc = RichDocument(paragraphs: fragment)
        doc.styles = styles
        return ClipboardData(text: text, rtf: RtfFormat.render(doc), html: HtmlFormat.render(fragment, styles: styles))
    }

    func decode(_ data: ClipboardData) -> [RichParagraph]? {
        if let rtf = data.rtf, let doc = RtfFormat.parse(rtf), !doc.paragraphs.isEmpty {
            return doc.paragraphs
        }
        if let html = data.html, let paragraphs = HtmlFormat.parse(html) {
            return paragraphs
        }
        return nil
    }
}
