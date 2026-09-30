// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// File formats Office reads and writes today: RTF (character runs,
// paragraph formatting, headings, lists — the bridge to Word until .docx
// lands in Phase 2), Markdown, and plain text. Everything here is pure
// Swift over the document model; nothing touches the engine.

import Flutter
import FlutterSwiftBridge
import Foundation

/// What opening a file yields: the document, and the paper it was set for
/// when the format carries that (.docx does).
struct OpenedDocument {
    var document: RichDocument
    var pageSetup: PageSetup?
}

enum OfficeFormats {
    static let readable = ["docx", "rtf", "md", "markdown", "txt", "text"]
    static let writable = ["docx", "rtf", "md", "txt"]

    enum FormatError: Error { case unreadable, unsupported(String) }

    static func read(_ path: String) throws -> OpenedDocument {
        guard let data = FileManager.default.contents(atPath: path) else { throw FormatError.unreadable }
        // A zip starts with "PK": a .docx whatever it is called.
        if data.count > 4, data[0] == 0x50, data[1] == 0x4B {
            let d = try DocxFormat.read(data)
            return OpenedDocument(document: d.document, pageSetup: d.pageSetup)
        }
        let text = String(decoding: data, as: UTF8.self)
        if text.hasPrefix("{\\rtf"), let doc = RtfFormat.parse(text) { return OpenedDocument(document: doc, pageSetup: nil) }
        switch (path as NSString).pathExtension.lowercased() {
        case "md", "markdown": return OpenedDocument(document: MarkdownFormat.parse(text), pageSetup: nil)
        case "rtf": return OpenedDocument(document: RtfFormat.parse(text) ?? RichDocument(plainText: text), pageSetup: nil)
        default:
            var doc = RichDocument(plainText: text.replacingOccurrences(of: "\r\n", with: "\n"))
            doc.styles = OfficeStyles.sheet
            return OpenedDocument(document: doc, pageSetup: nil)
        }
    }

    static func write(_ doc: RichDocument, to path: String, pageSetup: PageSetup = .letter) throws {
        let ext = (path as NSString).pathExtension.lowercased()
        let text: String
        switch ext {
        case "docx":
            let data = try DocxFormat.write(doc, pageSetup: pageSetup)
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            return
        case "rtf": text = RtfFormat.render(doc)
        case "md", "markdown": text = MarkdownFormat.render(doc)
        case "txt", "text", "": text = doc.plainText()
        default: throw FormatError.unsupported(ext)
        }
        try text.write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// True when saving to `path` would drop formatting.
    static func losesFormatting(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return ext == "txt" || ext == "text" || ext == ""
    }
}

// MARK: - Markdown

enum MarkdownFormat {
    static func parse(_ text: String) -> RichDocument {
        var paragraphs: [RichParagraph] = []
        var pending: [String] = []       // lines of the paragraph being gathered
        var pendingStyle = RichParagraphStyle.body
        func flush() {
            guard !pending.isEmpty else { return }
            let joined = pending.joined(separator: " ")
            paragraphs.append(_inline(joined, pendingStyle))
            pending.removeAll()
            pendingStyle = .body
        }
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let sheet = OfficeStyles.sheet
        var tableCount = 0
        var li = 0
        while li < lines.count {
            let line = lines[li]
            li += 1
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { flush(); continue }
            // A pipe table: a header row, a delimiter row, then body rows
            // until a line that is not one.
            if trimmed.hasPrefix("|"), li < lines.count,
               let alignments = _tableDelimiter(lines[li].trimmingCharacters(in: .whitespaces)) {
                flush()
                tableCount += 1
                let id = "t\(tableCount)"
                let columns = alignments.count
                var rows: [[String]] = [_tableCells(trimmed)]
                li += 1
                while li < lines.count {
                    let next = lines[li].trimmingCharacters(in: .whitespaces)
                    guard next.hasPrefix("|") else { break }
                    rows.append(_tableCells(next))
                    li += 1
                }
                for (r, cells) in rows.enumerated() {
                    for c in 0 ..< columns {
                        var style = RichParagraphStyle.body
                        style.alignment = alignments[c]
                        var p = _inline(c < cells.count ? cells[c] : "", style)
                        if r == 0 { p.applyStyle(0 ..< p.length) { $0.bold = true } }
                        p.cell = CellRef(table: id, row: r, column: c)
                        paragraphs.append(p)
                    }
                }
                continue
            }
            if trimmed.hasPrefix("#") {
                flush()
                let level = trimmed.prefix(while: { $0 == "#" }).count
                let rest = trimmed.dropFirst(level).trimmingCharacters(in: .whitespaces)
                if level <= 6 && !rest.isEmpty {
                    paragraphs.append(_inline(String(rest), RichParagraphStyle(heading: level)))
                    continue
                }
            }
            if trimmed == "---" || trimmed == "***" {
                flush()
                var style = RichParagraphStyle.body
                style.pageBreakBefore = true
                pendingStyle = style
                continue
            }
            let indent = line.prefix(while: { $0 == " " || $0 == "\t" }).reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
            if let bullet = _listPrefix(trimmed) {
                flush()
                var style = RichParagraphStyle(list: bullet.kind, listLevel: min(8, indent / 2))
                style.pageBreakBefore = false
                paragraphs.append(_inline(bullet.rest, style))
                continue
            }
            if trimmed.hasPrefix("> ") || trimmed == ">" {
                flush()
                var style = RichParagraphStyle.body
                sheet.apply("Quote", to: &style)
                paragraphs.append(_inline(String(trimmed.dropFirst(min(2, trimmed.count))), style))
                continue
            }
            if trimmed.hasPrefix("```") {
                // A fenced block: one Code paragraph per line, verbatim.
                flush()
                var style = RichParagraphStyle.body
                sheet.apply("Code", to: &style)
                while li < lines.count, !lines[li].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    paragraphs.append(RichParagraph(text: lines[li], style: style))
                    li += 1
                }
                li += 1
                continue
            }
            pending.append(trimmed)
        }
        flush()
        if paragraphs.last?.cell != nil { paragraphs.append(RichParagraph()) }
        var doc = RichDocument(paragraphs: paragraphs)
        doc.styles = sheet
        doc.styles = sheet
        return doc
    }

    /// `| --- | :-: | --: |` → one alignment per column, or nil if the line
    /// is not a delimiter row.
    private static func _tableDelimiter(_ line: String) -> [ParagraphAlignment]? {
        guard line.hasPrefix("|") else { return nil }
        let cells = _tableCells(line)
        guard !cells.isEmpty else { return nil }
        var out: [ParagraphAlignment] = []
        for cell in cells {
            let c = cell.trimmingCharacters(in: .whitespaces)
            guard c.count >= 3 || (c.count >= 1 && c.allSatisfy { $0 == "-" }) else { return nil }
            let left = c.hasPrefix(":"), right = c.hasSuffix(":")
            let dashes = c.dropFirst(left ? 1 : 0).dropLast(right ? 1 : 0)
            guard !dashes.isEmpty, dashes.allSatisfy({ $0 == "-" }) else { return nil }
            out.append(left && right ? .center : right ? .right : .left)
        }
        return out
    }

    /// The cells of `| a | b |`, trimmed; `\|` does not split (and stays
    /// escaped for `_inline`).
    private static func _tableCells(_ line: String) -> [String] {
        var body = Substring(line)
        if body.hasPrefix("|") { body = body.dropFirst() }
        if body.hasSuffix("|") && !body.hasSuffix("\\|") { body = body.dropLast() }
        var cells: [String] = []
        var current = ""
        var chars = body.makeIterator()
        while let ch = chars.next() {
            if ch == "\\", let next = chars.next() {
                current.append(ch); current.append(next); continue
            }
            if ch == "|" { cells.append(current.trimmingCharacters(in: .whitespaces)); current = ""; continue }
            current.append(ch)
        }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    private static func _listPrefix(_ s: String) -> (kind: ListKind, rest: String)? {
        if s.hasPrefix("- ") || s.hasPrefix("* ") || s.hasPrefix("+ ") {
            return (.bullet, String(s.dropFirst(2)))
        }
        var i = s.startIndex
        while i < s.endIndex, s[i].isNumber { i = s.index(after: i) }
        if i > s.startIndex, i < s.endIndex, s[i] == ".", s.index(after: i) < s.endIndex, s[s.index(after: i)] == " " {
            return (.numbered, String(s[s.index(i, offsetBy: 2)...]))
        }
        return nil
    }

    /// Inline markers: **bold**, *italic*, _italic_, ~~strike~~, `code`,
    /// [text](url). Unclosed markers are literal.
    private static func _inline(_ s: String, _ style: RichParagraphStyle) -> RichParagraph {
        var text = ""
        var runs: [Run] = []
        var current = CharStyle()
        func emit(_ piece: String) {
            guard !piece.isEmpty else { return }
            text += piece
            runs.append(Run(length: piece.utf16.count, style: current))
        }
        let chars = Array(s)
        var i = 0
        var literal = ""
        func has(_ marker: String, at k: Int) -> Bool {
            let m = Array(marker)
            guard k + m.count <= chars.count else { return false }
            return Array(chars[k ..< k + m.count]) == m
        }
        func closes(_ marker: String, from k: Int) -> Bool {
            var j = k
            while j < chars.count {
                if has(marker, at: j) { return j > k }
                j += 1
            }
            return false
        }
        while i < chars.count {
            let c = chars[i]
            if c == "\\" && i + 1 < chars.count {
                literal.append(chars[i + 1]); i += 2; continue
            }
            if has("**", at: i) && (current.bold || closes("**", from: i + 2)) {
                emit(literal); literal = ""
                current.bold.toggle(); i += 2; continue
            }
            if has("~~", at: i) && (current.strikethrough || closes("~~", from: i + 2)) {
                emit(literal); literal = ""
                current.strikethrough.toggle(); i += 2; continue
            }
            if (c == "*" || c == "_") && (current.italic || closes(String(c), from: i + 1)) {
                emit(literal); literal = ""
                current.italic.toggle(); i += 1; continue
            }
            if c == "`" && (current.fontFamily == OfficeFonts.mono || closes("`", from: i + 1)) {
                emit(literal); literal = ""
                current.fontFamily = current.fontFamily == OfficeFonts.mono ? nil : OfficeFonts.mono
                i += 1; continue
            }
            if c == "[", let close = _find("]", chars, from: i + 1), close + 1 < chars.count, chars[close + 1] == "(",
               let end = _find(")", chars, from: close + 2) {
                emit(literal); literal = ""
                let label = String(chars[(i + 1) ..< close])
                let url = String(chars[(close + 2) ..< end])
                let saved = current
                current.link = url
                emit(label)
                current = saved
                i = end + 1
                continue
            }
            literal.append(c)
            i += 1
        }
        emit(literal)
        return RichParagraph(text: text, runs: runs.isEmpty ? nil : runs, style: style)
    }

    private static func _find(_ ch: Character, _ chars: [Character], from: Int) -> Int? {
        var j = from
        while j < chars.count {
            if chars[j] == ch { return j }
            j += 1
        }
        return nil
    }

    static func render(_ doc: RichDocument) -> String {
        var out: [String] = []
        var i = 0
        while i < doc.paragraphs.count {
            let p = doc.paragraphs[i]
            if let cell = p.cell {
                // The whole table as one pipe table; a cell's paragraphs
                // join with a space, and the first row is the header.
                var end = i
                while end < doc.paragraphs.count, doc.paragraphs[end].cell?.table == cell.table { end += 1 }
                let members = doc.paragraphs[i ..< end]
                let rows = (members.compactMap { $0.cell?.row }.max() ?? 0) + 1
                let cols = (members.compactMap { $0.cell?.column }.max() ?? 0) + 1
                var grid = Array(repeating: Array(repeating: "", count: cols), count: rows)
                var alignment = Array(repeating: ParagraphAlignment.left, count: cols)
                for q in members {
                    guard let c = q.cell else { continue }
                    let text = _inlineMarkdown(q, plainBold: c.row == 0).replacingOccurrences(of: "|", with: "\\|")
                    grid[c.row][c.column] += (grid[c.row][c.column].isEmpty || text.isEmpty ? "" : " ") + text
                    if c.row == 0 { alignment[c.column] = q.style.alignment }
                }
                if p.style.pageBreakBefore { out.append("---"); out.append("") }
                out.append("| " + grid[0].joined(separator: " | ") + " |")
                out.append("| " + alignment.map { a -> String in
                    switch a {
                    case .center: return ":-:"
                    case .right: return "--:"
                    case .left, .justify: return "---"
                    }
                }.joined(separator: " | ") + " |")
                for row in grid.dropFirst() { out.append("| " + row.joined(separator: " | ") + " |") }
                out.append("")
                i = end
                continue
            }
            if p.style.named == "Code" {
                // Consecutive Code paragraphs share one fence.
                var end = i
                while end < doc.paragraphs.count, doc.paragraphs[end].style.named == "Code",
                      doc.paragraphs[end].cell == nil { end += 1 }
                if p.style.pageBreakBefore { out.append("---"); out.append("") }
                out.append("```")
                for q in doc.paragraphs[i ..< end] { out.append(q.text) }
                out.append("```")
                out.append("")
                i = end
                continue
            }
            var line = ""
            if p.style.pageBreakBefore { out.append("---"); out.append("") }
            if p.style.named == "Quote" { line += "> " }
            if let h = p.style.heading { line += String(repeating: "#", count: max(1, min(6, h))) + " " }
            if let list = p.style.list {
                line += String(repeating: "  ", count: p.style.listLevel) + (list == .bullet ? "- " : "1. ")
            }
            line += _inlineMarkdown(p, plainBold: p.style.heading != nil)
            out.append(line)
            out.append("")
            i += 1
        }
        while out.last == "" { out.removeLast() }
        return out.joined(separator: "\n") + "\n"
    }

    /// A paragraph's runs with inline markers. `plainBold` leaves bold
    /// unmarked where the context already is (headings, table headers).
    private static func _inlineMarkdown(_ p: RichParagraph, plainBold: Bool) -> String {
        var line = ""
        var pos = 0
        let utf16 = p.text.utf16
        for run in p.runs where run.length > 0 {
            let a = utf16.index(utf16.startIndex, offsetBy: pos)
            let b = utf16.index(a, offsetBy: run.length)
            var piece = String(utf16[a ..< b]) ?? ""
            pos += run.length
            let s = run.style
            // Markers around whitespace render as literal stars.
            let inert = piece.trimmingCharacters(in: .whitespaces).isEmpty
            if !inert {
                if s.fontFamily == OfficeFonts.mono { piece = "`\(piece)`" }
                if s.bold && !plainBold { piece = "**\(piece)**" }
                if s.italic { piece = "*\(piece)*" }
                if s.strikethrough { piece = "~~\(piece)~~" }
                if let link = s.link { piece = "[\(piece)](\(link))" }
            }
            line += piece
        }
        return line
    }
}

// MARK: - RTF

enum RtfFormat {
    // MARK: Reading

    private struct State {
        var char = CharStyle()
        var para = RichParagraphStyle.body
        var skip = 0          // \ucN: UTF-16 units to skip after \uN
        var inList = false
    }

    static func parse(_ text: String) -> RichDocument? {
        guard text.hasPrefix("{\\rtf") else { return nil }
        let chars = Array(text.utf8)
        var i = 0
        var stack: [State] = []
        var state = State()
        var colors: [Color] = []
        var fonts: [Int: String] = [:]
        var paragraphs: [RichParagraph] = []
        var runs: [Run] = []
        var buf = ""            // pending text in the current style
        var paraText = ""
        var groupDepth = 0
        var skipGroupUntil: Int? = nil   // depth at which an ignored destination ends
        var destination: String? = nil
        var destDepth = 0
        var colorEntry = (r: 0, g: 0, b: 0, any: false)
        var fontEntry = (index: -1, name: "")
        var styleEntry = (index: -1, name: "")
        var styleNames: [Int: String] = [:]   // \sN → its name, from the stylesheet
        let sheet = OfficeStyles.sheet
        var pendingUnicodeSkip = 0
        // List membership lives outside the group stack: Word writes it in a
        // {\*\pn …} group that closes before the paragraph's text, and
        // \pard resets it.
        var currentList: ListKind? = nil
        var currentLevel = 0
        var highSurrogate: Int? = nil
        var header = ""
        var footer = ""

        func flushRun() {
            guard !buf.isEmpty else { return }
            paraText += buf
            runs.append(Run(length: buf.utf16.count, style: state.char))
            buf = ""
        }
        func endParagraph() {
            flushRun()
            var style = state.para
            if let list = currentList {
                style.list = list
                style.listLevel = currentLevel
            }
            var p = RichParagraph(text: paraText, runs: runs.isEmpty ? nil : runs, style: style)
            p.normalize()
            paragraphs.append(p)
            paraText = ""
            runs = []
            // Word keeps paragraph props until \pard; the page-break flag is
            // one-shot.
            state.para.pageBreakBefore = false
        }
        func append(_ s: String) {
            if pendingUnicodeSkip > 0 { pendingUnicodeSkip -= 1; return }
            if destination != nil {
                if destination == "header" { header += s }
                if destination == "footer" { footer += s }
                if destination == "fonttbl" { fontEntry.name += s }
                if destination == "stylesheet" { styleEntry.name += s }
                if destination == "colortbl" {
                    // Each ';' closes one entry; a bare ';' is "auto".
                    for ch in s where ch == ";" {
                        colors.append(colorEntry.any
                            ? Color(0xFF000000 | (colorEntry.r << 16) | (colorEntry.g << 8) | colorEntry.b)
                            : Color(0xFF000000))
                        colorEntry = (0, 0, 0, false)
                    }
                }
                return   // pn, colortbl, and the skipped ones carry no body text
            }
            buf += s
        }

        while i < chars.count {
            let c = chars[i]
            if c == UInt8(ascii: "{") {
                stack.append(state)
                groupDepth += 1
                i += 1
                // \* destinations we do not understand are skipped whole.
                if i + 1 < chars.count && chars[i] == UInt8(ascii: "\\") && chars[i + 1] == UInt8(ascii: "*") {
                    // Peek the destination name after "\*\".
                    var j = i + 2
                    if j < chars.count && chars[j] == UInt8(ascii: "\\") { j += 1 }
                    var name = ""
                    while j < chars.count, (chars[j] >= 97 && chars[j] <= 122) { name.append(Character(UnicodeScalar(chars[j]))); j += 1 }
                    if name == "pn" {
                        // Word's list definition: read it, its keywords set the
                        // paragraph's list kind (handled below).
                        currentList = currentList ?? .bullet
                        destination = "pn"
                        destDepth = groupDepth
                    } else if skipGroupUntil == nil {
                        skipGroupUntil = groupDepth
                    }
                    i = j
                }
                continue
            }
            if c == UInt8(ascii: "}") {
                if destination == "stylesheet", styleEntry.index >= 0 {
                    styleNames[styleEntry.index] = styleEntry.name.trimmingCharacters(in: CharacterSet(charactersIn: "; ")).lowercased()
                    styleEntry = (-1, "")
                }
                if destination == "fonttbl", fontEntry.index >= 0 {
                    fonts[fontEntry.index] = fontEntry.name.trimmingCharacters(in: CharacterSet(charactersIn: "; "))
                    fontEntry = (-1, "")
                }
                if let d = skipGroupUntil, d == groupDepth { skipGroupUntil = nil }
                if destination != nil && destDepth == groupDepth { destination = nil }
                flushRun()
                groupDepth -= 1
                if let saved = stack.popLast() { state = saved }
                i += 1
                continue
            }
            if c == UInt8(ascii: "\\") {
                i += 1
                guard i < chars.count else { break }
                let n = chars[i]
                if n == UInt8(ascii: "'") {
                    // \'hh — a code-page byte; treat as Latin-1.
                    guard i + 2 < chars.count, let v = UInt8(String(decoding: chars[(i + 1) ... (i + 2)], as: UTF8.self), radix: 16) else { i += 1; continue }
                    i += 3
                    if skipGroupUntil == nil { append(String(UnicodeScalar(v))) }
                    continue
                }
                if !(n >= 97 && n <= 122) && !(n >= 65 && n <= 90) {
                    // Control symbol: \\ \{ \} \~ \- \_ \* etc.
                    i += 1
                    if skipGroupUntil != nil { continue }
                    switch n {
                    case UInt8(ascii: "\\"), UInt8(ascii: "{"), UInt8(ascii: "}"): append(String(UnicodeScalar(n)))
                    case UInt8(ascii: "~"): append("\u{00A0}")
                    case UInt8(ascii: "-"): append("\u{00AD}")
                    case UInt8(ascii: "_"): append("\u{2011}")
                    case UInt8(ascii: "\n"), UInt8(ascii: "\r"): endParagraph()
                    default: break
                    }
                    continue
                }
                var word = ""
                while i < chars.count, (chars[i] >= 97 && chars[i] <= 122) || (chars[i] >= 65 && chars[i] <= 90) {
                    word.append(Character(UnicodeScalar(chars[i]))); i += 1
                }
                var param: Int? = nil
                var negative = false
                if i < chars.count && chars[i] == UInt8(ascii: "-") { negative = true; i += 1 }
                var digits = ""
                while i < chars.count, chars[i] >= 48 && chars[i] <= 57 { digits.append(Character(UnicodeScalar(chars[i]))); i += 1 }
                if !digits.isEmpty { param = (Int(digits) ?? 0) * (negative ? -1 : 1) }
                if i < chars.count && chars[i] == UInt8(ascii: " ") { i += 1 }  // the delimiting space

                if skipGroupUntil != nil { continue }
                // A keyword may change the character style: close the run
                // typed so far under the style it was typed with.
                flushRun()
                switch word {
                case "fonttbl", "colortbl", "stylesheet", "info", "pict", "header", "footer", "listtable",
                     "listoverridetable", "themedata", "colorschememapping", "latentstyles", "datastore",
                     "xmlnstbl", "rsidtbl", "generator", "mmathPr", "field", "fldinst", "object", "shp",
                     "listtext", "pntext", "footnote", "annotation", "bkmkstart", "bkmkend":
                    if word == "listtext" || word == "pntext" {
                        // Word's literal bullet text: skip it, the list flag draws ours.
                        if skipGroupUntil == nil { skipGroupUntil = groupDepth }
                    } else {
                        destination = word
                        destDepth = groupDepth
                        if word != "fonttbl" && word != "colortbl" && word != "header" && word != "footer"
                            && word != "stylesheet", skipGroupUntil == nil { skipGroupUntil = groupDepth }
                    }
                case "red": colorEntry.r = param ?? 0; colorEntry.any = true
                case "green": colorEntry.g = param ?? 0; colorEntry.any = true
                case "blue": colorEntry.b = param ?? 0; colorEntry.any = true
                case "f":
                    if destination == "fonttbl" { fontEntry.index = param ?? 0; fontEntry.name = "" }
                    else if let idx = param, let name = fonts[idx] { state.char.fontFamily = _family(name) }
                case "chpgn": append(RichDocument.pageField)
                case "par": if destination == nil { endParagraph() } else { append(" ") }
                case "line": append("\n")
                case "tab": append("\t")
                case "pard": state.para = .body; state.inList = false; currentList = nil; currentLevel = 0
                case "plain": state.char = CharStyle()
                case "b": state.char.bold = param != 0
                case "i": state.char.italic = param != 0
                case "ul", "uldb", "ulw": state.char.underline = param != 0
                case "ulnone": state.char.underline = false
                case "strike": state.char.strikethrough = param != 0
                case "super": state.char.script = param == 0 ? .normal : .superscript
                case "sub": state.char.script = param == 0 ? .normal : .subscript
                case "nosupersub": state.char.script = .normal
                case "fs": if let p = param { state.char.fontSize = Double(p) / 2 }
                case "cf":
                    if let p = param, p > 0, p < colors.count { state.char.color = colors[p] } else { state.char.color = nil }
                case "highlight", "cb", "chcbpat":
                    if let p = param, p > 0, p < colors.count { state.char.highlight = colors[p] } else { state.char.highlight = nil }
                case "ql": state.para.alignment = .left
                case "qc": state.para.alignment = .center
                case "qr": state.para.alignment = .right
                case "qj": state.para.alignment = .justify
                case "li": state.para.indentLeft = Double(param ?? 0) / 20
                case "ri": state.para.indentRight = Double(param ?? 0) / 20
                case "fi": state.para.firstLineIndent = Double(param ?? 0) / 20
                case "sb": state.para.spaceBefore = Double(param ?? 0) / 20
                case "sa": state.para.spaceAfter = Double(param ?? 0) / 20
                case "sl":
                    if let p = param, p > 0 { state.para.lineSpacing = max(0.5, Double(p) / 240) }
                case "ls", "pn", "pnlvl":
                    if currentList == nil { currentList = .bullet }
                case "pnlvlblt": currentList = .bullet
                case "pnlvlbody", "pndec": currentList = .numbered
                case "ilvl": currentLevel = max(0, min(8, param ?? 0))
                case "pnlvlcont": break
                case "page", "pagebb": state.para.pageBreakBefore = true
                case "s":
                    if destination == "stylesheet" {
                        styleEntry.index = param ?? 0; styleEntry.name = ""
                    } else if let p = param, let id = _rtfStyleId(styleNames[p], number: p) {
                        // The stylesheet's name for it; without one, Word's
                        // default numbering has headings at \s1..\s6.
                        sheet.apply(id, to: &state.para)
                    } else {
                        state.para.heading = nil; state.para.named = nil
                    }
                case "uc": state.skip = param ?? 1
                case "u":
                    if let p = param {
                        let v = p < 0 ? p + 65536 : p
                        if v >= 0xD800 && v <= 0xDBFF {
                            highSurrogate = v
                        } else if v >= 0xDC00 && v <= 0xDFFF, let hi = highSurrogate {
                            let code = 0x10000 + ((hi - 0xD800) << 10) + (v - 0xDC00)
                            highSurrogate = nil
                            if let scalar = UnicodeScalar(UInt32(code)) { append(String(Character(scalar))) }
                        } else if let scalar = UnicodeScalar(UInt32(v)) {
                            append(String(Character(scalar)))
                        }
                        pendingUnicodeSkip = state.skip
                    }
                default: break
                }
                continue
            }
            if c == UInt8(ascii: "\n") || c == UInt8(ascii: "\r") { i += 1; continue }
            // Plain text run: gather bytes to the next control/brace.
            var j = i
            while j < chars.count, chars[j] != UInt8(ascii: "\\"), chars[j] != UInt8(ascii: "{"),
                  chars[j] != UInt8(ascii: "}"), chars[j] != UInt8(ascii: "\n"), chars[j] != UInt8(ascii: "\r") { j += 1 }
            let piece = String(decoding: chars[i ..< j], as: UTF8.self)
            i = j
            if skipGroupUntil != nil { continue }
            if pendingUnicodeSkip > 0 {
                let drop = min(pendingUnicodeSkip, piece.count)
                pendingUnicodeSkip -= drop
                append(String(piece.dropFirst(drop)))
            } else {
                append(piece)
            }
        }
        if !paraText.isEmpty || !buf.isEmpty { endParagraph() }
        if paragraphs.isEmpty { return RichDocument() }
        var doc = RichDocument(paragraphs: paragraphs)
        doc.header = header.trimmingCharacters(in: .whitespaces)
        doc.footer = footer.trimmingCharacters(in: .whitespaces)
        return doc
    }

    /// Map Word's font names onto the faces we ship.
    private static func _family(_ name: String) -> String? {
        let n = name.lowercased()
        if n.contains("times") || n.contains("serif") || n.contains("georgia") || n.contains("cambria") || n.contains("liberation serif") { return OfficeFonts.serif }
        if n.contains("courier") || n.contains("mono") || n.contains("consolas") || n.contains("menlo") { return OfficeFonts.mono }
        return nil   // the document default: Liberation Sans
    }

    // MARK: Writing

    static func render(_ doc: RichDocument) -> String {
        // Colour table: index 0 is auto; gather every colour used.
        var palette: [Color] = []
        func colorIndex(_ c: Color?) -> Int {
            guard let c else { return 0 }
            if let i = palette.firstIndex(of: c) { return i + 1 }
            palette.append(c)
            return palette.count
        }
        var body = ""
        for (n, p) in doc.paragraphs.enumerated() {
            var head = "\\pard\\plain"
            switch p.style.alignment {
            case .left: head += "\\ql"
            case .center: head += "\\qc"
            case .right: head += "\\qr"
            case .justify: head += "\\qj"
            }
            if p.style.pageBreakBefore && n > 0 { head += "\\pagebb" }
            if let h = p.style.heading { head += "\\s\(h)\\keepn" }
            else if let n = p.style.named, let num = _rtfStyleNumber(n) { head += "\\s\(num)" }
            var li = Int(p.style.indentLeft * 20)
            var fi = Int(p.style.firstLineIndent * 20)
            var listPrefix = ""
            if let list = p.style.list {
                li += 720 * (p.style.listLevel + 1)
                fi = -360
                head += "\\ilvl\(p.style.listLevel)"
                listPrefix = list == .bullet ? "{\\pntext\\'b7\\tab}" : "{\\pntext 1.\\tab}"
                head += list == .bullet
                    ? "{\\*\\pn\\pnlvlblt\\pnf1\\pnindent360{\\pntxtb\\'b7}}"
                    : "{\\*\\pn\\pnlvlbody\\pnf0\\pnindent360\\pnstart1\\pndec{\\pntxta.}}"
            }
            if li != 0 { head += "\\li\(li)" }
            if fi != 0 { head += "\\fi\(fi)" }
            if p.style.indentRight != 0 { head += "\\ri\(Int(p.style.indentRight * 20))" }
            if p.style.spaceBefore != 0 { head += "\\sb\(Int(p.style.spaceBefore * 20))" }
            head += "\\sa\(Int((p.style.spaceAfter > 0 ? p.style.spaceAfter : 8) * 20))"
            if p.style.lineSpacing != 1.0 { head += "\\sl\(Int(p.style.lineSpacing * 240))\\slmult1" }
            head += " "
            body += head + listPrefix
            var pos = 0
            let utf16 = p.text.utf16
            let named = doc.styles.resolve(p.style)
            let headingSize: Double? = named?.char.fontSize
                ?? p.style.heading.map { [20, 16, 14, 12, 11, 11][min($0, 6) - 1] }
            for run in p.runs where run.length > 0 {
                let a = utf16.index(utf16.startIndex, offsetBy: pos)
                let b = utf16.index(a, offsetBy: run.length)
                let piece = String(utf16[a ..< b]) ?? ""
                pos += run.length
                let s = run.style
                var ctrl = "{"
                switch s.fontFamily ?? named?.char.fontFamily {
                case OfficeFonts.serif?: ctrl += "\\f1"
                case OfficeFonts.mono?: ctrl += "\\f2"
                default: ctrl += "\\f0"
                }
                let size = s.fontSize ?? headingSize ?? 11
                ctrl += "\\fs\(Int(size * 2))"
                if s.bold || (named?.char.bold ?? (p.style.heading.map { $0 <= 3 } ?? false)) { ctrl += "\\b" }
                if s.italic || (named?.char.italic ?? false) { ctrl += "\\i" }
                if s.underline { ctrl += "\\ul" }
                if s.strikethrough { ctrl += "\\strike" }
                if s.script == .superscript { ctrl += "\\super" }
                if s.script == .subscript { ctrl += "\\sub" }
                let color = s.color ?? named?.char.color ?? (p.style.heading != nil ? Color(0xFF2F5496) : nil)
                if let color { ctrl += "\\cf\(colorIndex(color))" }
                if let hl = s.highlight { ctrl += "\\highlight\(colorIndex(hl))" }
                ctrl += " "
                body += ctrl + _escape(piece) + "}"
            }
            body += "\\par\n"
        }
        var colortbl = "{\\colortbl;"
        for c in palette {
            colortbl += "\\red\((c.value >> 16) & 0xFF)\\green\((c.value >> 8) & 0xFF)\\blue\(c.value & 0xFF);"
        }
        colortbl += "}"
        var hf = ""
        if !doc.header.isEmpty {
            hf += "{\\header\\pard\\ql " + _escape(doc.header).replacingOccurrences(of: RichDocument.pageField, with: "\\chpgn ") + "\\par}\n"
        }
        if !doc.footer.isEmpty {
            hf += "{\\footer\\pard\\qc " + _escape(doc.footer).replacingOccurrences(of: RichDocument.pageField, with: "\\chpgn ") + "\\par}\n"
        }
        let fonttbl = "{\\fonttbl{\\f0\\fswiss\\fcharset0 Arial;}{\\f1\\froman\\fcharset0 Times New Roman;}{\\f2\\fmodern\\fcharset0 Courier New;}}"
        var stylesheet = "{\\stylesheet{\\s0 Normal;}"
        for entry in doc.styles.styles where entry.id != RichNamedStyle.normalId {
            let num = entry.paragraph.heading ?? _rtfStyleNumber(entry.id) ?? 0
            if num == 0 { continue }
            var look = ""
            if entry.char.bold { look += "\\b" }
            if entry.char.italic { look += "\\i" }
            if let size = entry.char.fontSize { look += "\\fs\(Int(size * 2))" }
            let name = entry.paragraph.heading.map { "heading \($0)" } ?? entry.name
            stylesheet += "{\\s\(num)\(look) \(_escape(name));}"
        }
        stylesheet += "}"
        return "{\\rtf1\\ansi\\ansicpg1252\\deff0\\deflang1033\\uc1\n\(fonttbl)\n\(colortbl)\n\(stylesheet)\n\\paperw12240\\paperh15840\\margl1440\\margr1440\\margt1440\\margb1440\n\(hf)\(body)}\n"
    }

    /// Word's own numbering for the styles we write, so a stylesheet-less
    /// reader still sees headings at \s1..\s6.
    private static func _rtfStyleNumber(_ id: String) -> Int? {
        switch id {
        case "Title": return 15
        case "Subtitle": return 16
        case "Quote": return 17
        case "Caption": return 18
        case "Code": return 19
        default: return nil
        }
    }

    private static func _rtfStyleId(_ name: String?, number: Int) -> String? {
        if let name {
            for level in 1 ... 6 where name == "heading \(level)" || name == "heading\(level)" {
                return RichNamedStyle.headingId(level)
            }
            switch name {
            case "normal": return RichNamedStyle.normalId
            case "title": return "Title"
            case "subtitle": return "Subtitle"
            case "quote", "intense quote", "block text": return "Quote"
            case "caption": return "Caption"
            case "code", "html preformatted", "plain text": return "Code"
            default: return nil
            }
        }
        return number >= 1 && number <= 6 ? RichNamedStyle.headingId(number) : nil
    }

    private static func _escape(_ s: String) -> String {
        var out = ""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\\": out += "\\\\"
            case "{": out += "\\{"
            case "}": out += "\\}"
            case "\n": out += "\\line "
            case "\t": out += "\\tab "
            default:
                if scalar.value < 0x80 {
                    out.unicodeScalars.append(scalar)
                } else if scalar.value < 0x10000 {
                    let v = Int(scalar.value)
                    out += "\\u\(v > 32767 ? v - 65536 : v)?"
                } else {
                    // Surrogate pair.
                    let v = scalar.value - 0x10000
                    let hi = Int(0xD800 + (v >> 10)), lo = Int(0xDC00 + (v & 0x3FF))
                    out += "\\u\(hi - 65536)?\\u\(lo - 65536)?"
                }
            }
        }
        return out
    }
}
