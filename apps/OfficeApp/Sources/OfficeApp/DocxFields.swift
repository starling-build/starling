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
    /// Note number `n` in the notes' `w:numFmt` (`format`).
    static func noteLabel(_ n: Int, format: String) -> String {
        switch format {
        case "lowerRoman": return ListNumberFormat.lowerRoman.string(n)
        case "upperRoman": return ListNumberFormat.upperRoman.string(n)
        case "lowerLetter": return ListNumberFormat.lowerLetter.string(n)
        case "upperLetter": return ListNumberFormat.upperLetter.string(n)
        // (The East Asian forms as a list writes them: zh-424775e4's footnotePr says
        // decimalEnclosedCircleChinese, and Word's print marks its notes "①".)
        case let raw:
            var f = ListLevelFormat(text: "")
            f.rawFormat = raw
            return f.number(n)
        }
    }

    static func _bindCoreProperties(_ root: XNode, part: (String) -> Data?) {
        func texts(_ n: XNode, _ out: inout [XNode]) {
            if n.name == "w:t" { out.append(n) }
            for c in n.children { texts(c, &out) }
        }
        var core: XNode??
        var glossary: XNode??
        // A TITLE field shows the document's title property, empty where the file has none, whatever it cached: Word
        // updates the fields of a header and footer as it prints. lo-06933f8e's footer cached "Getting Started with
        // LibreOffice 5.0" over a core.xml with no title, and Word's print has "2 | " alone.
        func titleFields(_ p: XNode) {
            var state = 0   // 0 outside, 1 in the instruction, 2 in the result
            var instr = ""
            var results: [XNode] = []
            for r in p.children where r.name == "w:r" {
                for c in r.children {
                    if c.name == "w:fldChar" {
                        switch c["w:fldCharType"] {
                        case "begin": state = 1; instr = ""; results = []
                        case "separate": state = 2
                        case "end":
                            // (A SET field shows nothing: it stores its text in a bookmark. lo-d0fc1bd5c5's
                            // "2001. " + SET praun01 "Praun et al. 2001" + SET praun01yr 2001 is "2001. Consistent …" in
                            // Word's print; ours showed both cached results.)
                            if state == 2, instr.trimmingWhitespace(newlines: true).uppercased().hasPrefix("SET "), !results.isEmpty {
                                RuleTrace.hit("set-field-shows-nothing")
                                for t in results { t.text = "" }
                            }
                            if state == 2, instr.trimmingWhitespace(newlines: true).uppercased() == "TITLE" {
                                if core == nil { core = .some(part("docProps/core.xml").flatMap(XNode.parse)) }
                                if let props = core ?? nil {
                                    let title = (props.children.first { $0.name.hasSuffix(":title") }?.text ?? "").trimmingWhitespace(newlines: true)
                                    if let first = results.first, first.text != title {
                                        RuleTrace.hit("title-field-shows-the-title-property")
                                        first.text = title
                                        for t in results.dropFirst() { t.text = "" }
                                    }
                                }
                            }
                            if state == 2, let clock = FieldClock.current(), let first = results.first,
                               let shown = clock.text(instr: instr.trimmingWhitespace(newlines: true), cached: results.map { $0.text }.joined()),
                               shown != first.text {
                                RuleTrace.hit("date-time-field-shows-the-print-moment")
                                first.text = shown
                                for t in results.dropFirst() { t.text = "" }
                            }
                            state = 0
                        default: break
                        }
                    } else if c.name == "w:instrText", state == 1 { instr += c.text }
                    else if c.name == "w:t", state == 2 { results.append(c) }
                }
            }
        }
        // (Iterative: a table nested 5000 deep (deep-table-cell) overflowed the stack here.)
        var pending: [XNode] = [root]
        while let node = pending.popLast() {
            if node.name == "w:p" { titleFields(node) }
            if node.name == "w:sdt", let pr = node.first("w:sdtPr"), let bind = pr.first("w:dataBinding"),
               let store = bind["w:storeItemID"]?.uppercased(),
               let xpath = bind["w:xpath"], let last = xpath.split(separator: "/").last,
               let content = node.first("w:sdtContent") {
                let local = String(last.split(separator: "[").first ?? "").split(separator: ":").last.map(String.init) ?? ""
                var value: String
                var custom = false
                if store == "{6C3C8BC8-F283-45AE-878A-BAB7291924A1}" {
                    if core == nil { core = .some(part("docProps/core.xml").flatMap(XNode.parse)) }
                    guard let props = core ?? nil else { continue }
                    value = props.children.first { $0.name.hasSuffix(":" + local) }?.text ?? ""
                    value = value.trimmingWhitespace(newlines: true)
                } else {
                    // A control mapped to a custom XML part shows that element's text and drops what it cached, formatting
                    // included (Word lab word-uicheck24: bold cached text came out plain). An element the part lacks leaves the
                    // control unmapped, with its cached text.
                    guard let found = Self._customXmlValue(store: store, xpath: xpath, part: part) else { continue }
                    value = found
                    custom = true
                }
                // A date picker shows its bound value in its own w:dateFormat, not as stored: 52449's PublishDate
                // "2012-01-11T00:00:00" is "11-01-2012" (dd-MM-yyyy) in Word's print, f7888b70's "February 1, 2025"
                // (MMMM d, yyyy, en-US). A month or day name outside English keeps the cached text.
                if let date = pr.first("w:date"), let picture = date.first("w:dateFormat")?["w:val"], !picture.isEmpty,
                   let clock = FieldClock.parse(value) {
                    let english = (date.first("w:lid")?["w:val"] ?? "en-US").lowercased().hasPrefix("en")
                    guard let shown = clock.format(picture: picture, english: english) else { continue }
                    RuleTrace.hit("bound-date-control-shows-its-date-format")
                    value = shown
                }
                var placeholderRun: XNode?
                if value.isEmpty {
                    guard let name = pr.first("w:placeholder")?.first("w:docPart")?["w:val"], !name.isEmpty else { continue }
                    if glossary == nil { glossary = .some(part("word/glossary/document.xml").flatMap(XNode.parse)) }
                    guard let g = glossary ?? nil,
                          let docPart = (g.first("w:docParts")?.all("w:docPart") ?? []).first(where: { $0.first("w:docPartPr")?.first("w:name")?["w:val"] == name }),
                          let body = docPart.first("w:docPartBody") else { continue }
                    var shown: [XNode] = []
                    texts(body, &shown)
                    value = shown.map { $0.text }.joined()
                    if value.isEmpty { continue }
                    placeholderRun = body.descendants("w:r").first
                }
                var runs: [XNode] = []
                texts(content, &runs)
                guard let first = runs.first else { continue }
                RuleTrace.hit(custom ? "custom-xml-bound-control-shows-the-element" : "core-bound-control-shows-the-property")
                first.text = value
                if custom, placeholderRun == nil, let run = content.descendants("w:r").first(where: { $0.children.contains { $0 === first } }) {
                    run.children.removeAll { $0.name == "w:rPr" }
                }
                // (The placeholder shows in its own formatting, not that of the text the control held:
                // lo-c657ba7d's title, bold orange "Communication digitale" in the file, is "[Titre du
                // document]" in the glossary's plain 16pt black in Word's print.)
                if let ph = placeholderRun, let run = content.descendants("w:r").first(where: { $0.children.contains { $0 === first } }) {
                    run.children.removeAll { $0.name == "w:rPr" }
                    if let rpr = ph.first("w:rPr") { run.children.insert(rpr, at: 0) }
                }
                for r in runs.dropFirst() { r.text = "" }
                continue
            }
            pending.append(contentsOf: node.children.reversed())
        }
    }

    /// The text of the element a content control's binding names inside the custom XML part whose data store id is
    /// `store`, or nil when there is no such part or element. The path is `/ns0:root[1]/ns0:a[1]`: each step is a name
    /// (prefix ignored) and an optional 1-based position among the same-named children.
    static func _customXmlValue(store: String, xpath: String, part: (String) -> Data?) -> String? {
        var item: XNode?
        for n in 1...64 {
            guard let props = part("customXml/itemProps\(n).xml").flatMap(XNode.parse) else { continue }
            if props["ds:itemID"]?.uppercased() == store { item = part("customXml/item\(n).xml").flatMap(XNode.parse); break }
        }
        guard var node = item else { return nil }
        let steps = xpath.split(separator: "/").map(String.init)
        guard !steps.isEmpty else { return nil }
        for (i, step) in steps.enumerated() {
            let name = String(step.split(separator: "[").first ?? "")
            let local = String(name.split(separator: ":").last ?? "")
            var position = 1
            if let open = step.firstIndex(of: "["), let close = step.firstIndex(of: "]"), open < close,
               let n = Int(step[step.index(after: open)..<close]) { position = n }
            func matches(_ x: XNode) -> Bool { local == "*" || String(x.name.split(separator: ":").last ?? "") == local }
            if i == 0 { guard matches(node), position == 1 else { return nil }; continue }
            let same = node.children.filter(matches)
            guard position >= 1, position <= same.count else { return nil }
            node = same[position - 1]
        }
        var out = ""
        func collect(_ n: XNode) { out += n.text; for c in n.children { collect(c) } }
        collect(node)
        return out
    }

    /// Plain-text inline controls showing one named placeholder share its
    /// first cached value. Word does this even across paragraphs (55966
    /// and the placeholder labs); a filled control does not participate.
    /// Block controls have a separate refresh behavior, so keep their
    /// cached paragraphs. The glossary's default text is not what Word
    /// displays when the inline controls already carry a cached value.
    static func _reuseInlinePlaceholders(_ body: XNode) {
        var first: [String: XNode] = [:]
        func copy(_ node: XNode) -> XNode {
            let result = XNode(name: node.name, attrs: node.attrs)
            result.text = node.text
            result.children = node.children.map(copy)
            return result
        }
        func walk(_ node: XNode) {
            if node.name == "w:sdt", let pr = node.first("w:sdtPr"), pr.first("w:text") != nil,
               let flag = pr.first("w:showingPlcHdr"), !_isOff(flag),
               let name = pr.first("w:placeholder")?.first("w:docPart")?["w:val"], !name.isEmpty,
               let content = node.first("w:sdtContent"), !content.children.isEmpty,
               content.children.allSatisfy({ $0.name == "w:r" || $0.name == "w:proofErr" }) {
                if let cached = first[name] { content.children = cached.children.map(copy) }
                else { first[name] = copy(content) }
                return
            }
            for child in node.children { walk(child) }
        }
        walk(body)
    }

    /// A header/footer part's text with PAGE and NUMPAGES fields (simple or
    /// complex) turned into placeholders; paragraphs joined with spaces.
    /// Whether a field instruction is a page number or a page count.
    /// The text an `IF left op right "then" "else"` field shows where the file wrote no result: the comparison
    /// made on what the field itself holds — quoted strings and numbers, `=`, `<>`, `<`, `>`, `<=`, `>=`, two
    /// numbers as numbers, anything else as text without regard to case — and the true or the false text (empty
    /// when there is none). Nil for an instruction that is not that whole shape (a nested field's operand is
    /// not in it; a wildcard is not understood).
    static func _ifFieldResult(_ instr: String) -> String? {
        var tokens: [(text: String, quoted: Bool)] = []
        var chars = Array(instr.trimmingWhitespace(newlines: true))
        var i = 0
        let open: Set<Character> = ["\"", "\u{201C}"], close: Set<Character> = ["\"", "\u{201D}"]
        while i < chars.count {
            if chars[i].isWhitespace { i += 1; continue }
            if open.contains(chars[i]) {
                var j = i + 1, text = ""
                while j < chars.count, !close.contains(chars[j]) { text.append(chars[j]); j += 1 }
                guard j < chars.count else { return nil }
                tokens.append((text, true)); i = j + 1
            } else {
                var j = i, text = ""
                while j < chars.count, !chars[j].isWhitespace, !open.contains(chars[j]) { text.append(chars[j]); j += 1 }
                tokens.append((text, false)); i = j
            }
        }
        chars = []
        guard tokens.count >= 1, !tokens[0].quoted, tokens[0].text.uppercased() == "IF" else { return nil }
        var rest = Array(tokens.dropFirst())
        // `1=2` written close: split it where the operator is.
        if rest.count >= 1, !rest[0].quoted, !["=", "<>", "<", ">", "<=", ">="].contains(rest[0].text) {
            let t = Array(rest[0].text)
            if let at = t.firstIndex(where: { "=<>".contains($0) }) {
                var end = at + 1
                if end < t.count, "=<>".contains(t[end]), t[at] != t[end] || t[at] == "<" && t[end] == ">" { end += 1 }
                var split: [(text: String, quoted: Bool)] = []
                if at > 0 { split.append((String(t[..<at]), false)) }
                split.append((String(t[at ..< end]), false))
                if end < t.count { split.append((String(t[end...]), false)) }
                rest.replaceSubrange(0 ... 0, with: split)
            }
        }
        // left op right then [else]
        guard rest.count >= 4, !rest[1].quoted, ["=", "<>", "<", ">", "<=", ">="].contains(rest[1].text), rest.count <= 5 else { return nil }
        let (left, op, right) = (rest[0].text, rest[1].text, rest[2].text)
        let order: Int
        if let a = Double(left), let b = Double(right) {
            order = a < b ? -1 : a > b ? 1 : 0
        } else {
            let a = left.lowercased(), b = right.lowercased()
            order = a < b ? -1 : a > b ? 1 : 0
        }
        let holds: Bool
        switch op {
        case "=": holds = order == 0
        case "<>": holds = order != 0
        case "<": holds = order < 0
        case ">": holds = order > 0
        case "<=": holds = order <= 0
        default: holds = order >= 0
        }
        return holds ? rest[3].text : (rest.count == 5 ? rest[4].text : "")
    }

    /// The ruby an `EQ \o(\s\up N(ruby),base)` field sets (Word's Phonetic Guide before w:ruby): its
    /// ruby text, base, size (`\* hpsN`, half points) and raise (points), or nil for any other field.
    static func _eqRuby(_ instr: String) -> (ruby: String, base: String, size: Double, raise: Double, align: String?)? {
        let t = instr.trimmingWhitespace(newlines: true)
        guard t.uppercased().hasPrefix("EQ"), let o = t.rangeOfSubstring("\\o"), let up = t.rangeOfSubstring("\\s\\up") else { return nil }
        let head = String(t[t.startIndex ..< o.lowerBound])
        let tail = t[up.upperBound...]
        guard let open = tail.firstIndex(of: "(") else { return nil }
        let raise = Double(String(tail[tail.startIndex ..< open]).trimmingWhitespace(newlines: true)) ?? 0
        let afterOpen = tail.index(after: open)
        guard let close = tail[afterOpen...].firstIndex(of: ")") else { return nil }
        let ruby = String(tail[afterOpen ..< close])
        var rest = tail[tail.index(after: close)...]
        guard rest.hasPrefix(",") else { return nil }
        rest = rest.dropFirst()
        guard rest.hasSuffix(")") else { return nil }
        let base = String(rest.dropLast())
        guard !ruby.isEmpty, !base.isEmpty, !base.containsSubstring("(") else { return nil }
        var size = 0.0, align: String? = nil
        for tok in head.split(whereSeparator: { $0.isWhitespace }) {
            let lower = tok.lowercased()
            if lower.hasPrefix("hps"), let v = Double(lower.dropFirst(3)) { size = v / 2 }
            if lower == "jc0" { align = "center" } else if lower == "jc1" { align = "left" } else if lower == "jc2" { align = "right" }
        }
        return (ruby, base, size, raise, align)
    }

    /// An `EQ \o(base,\s\up N(over),\s\do M(under))` field: the base, the item set above it (with its raise in
    /// points) and the item set below, or nil for any other field.
    static func _eqStack(_ instr: String) -> (base: String, over: String, raise: Double, under: String)? {
        let t = instr.trimmingWhitespace(newlines: true)
        guard t.uppercased().hasPrefix("EQ"), let o = t.rangeOfSubstring("\\o("), t.hasSuffix("))"),
              let up = t.rangeOfSubstring(",\\s\\up"), let down = t.rangeOfSubstring("),\\s\\do") else { return nil }
        let base = String(t[o.upperBound ..< up.lowerBound])
        let upPart = t[up.upperBound ..< down.lowerBound]
        guard let open = upPart.firstIndex(of: "("), !base.isEmpty else { return nil }
        let raise = Double(String(upPart[upPart.startIndex ..< open]).trimmingWhitespace(newlines: true)) ?? 0
        let over = String(upPart[upPart.index(after: open)...])
        let downPart = t[down.upperBound ..< t.index(t.endIndex, offsetBy: -2)]
        guard let open2 = downPart.firstIndex(of: "(") else { return nil }
        let under = String(downPart[downPart.index(after: open2)...])
        guard !over.isEmpty, !over.containsSubstring("("), !under.containsSubstring("(") else { return nil }
        return (base, over, raise, under)
    }

    /// The circled number an `eq \o\ac(○,N)` field draws (N from 1 to
    /// 20), or nil for any other field.
    static func _ringedNumber(_ instr: String) -> String? {
        let compact = instr.filter { !$0.isWhitespace }
        guard compact.lowercased().hasPrefix("eq\\o\\ac("), compact.hasSuffix(")") else { return nil }
        let inner = compact.dropFirst("eq\\o\\ac(".count).dropLast()
        let parts = inner.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 2, ["○", "◯"].contains(String(parts[0])) else { return nil }
        // (Not a number to ring, `eq \o\ac(○,예)`: Word still sets the ring an em wide and
        // overlays the other character at 8 pt on it. We keep the ring, so the line takes its
        // width; 6a68f6ca's four fields had been dropped and its pages ran 9.5 against 86.9.)
        guard let n = Int(parts[1]), (1 ... 20).contains(n), let u = Unicode.Scalar(0x2460 + n - 1) else {
            RuleTrace.hit("eq-overstrike-keeps-its-ring")
            return String(parts[0])
        }
        return String(Character(u))
    }

    /// The non-number character an `eq \o\ac(○,예)` field draws over its ring, or nil.
    static func _ringOverlay(_ instr: String) -> String? {
        let compact = instr.filter { !$0.isWhitespace }
        guard compact.lowercased().hasPrefix("eq\\o\\ac("), compact.hasSuffix(")") else { return nil }
        let parts = compact.dropFirst("eq\\o\\ac(".count).dropLast().split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 2, ["○", "◯"].contains(String(parts[0])), Int(parts[1]) == nil, !parts[1].isEmpty else { return nil }
        return String(parts[1])
    }

    /// The style a STYLEREF instruction names, quoted or not.
    static func _styleRefName(_ instr: String) -> String? {
        let text = instr.trimmingWhitespace(newlines: true)
        guard text.uppercased().hasPrefix("STYLEREF") else { return nil }
        let rest = String(text.dropFirst("STYLEREF".count)).trimmingWhitespace(newlines: true)
        if rest.hasPrefix("\""), let end = rest.dropFirst().firstIndex(of: "\"") {
            let name = String(rest[rest.index(after: rest.startIndex) ..< end]).trimmingWhitespace(newlines: true)
            return name.isEmpty ? nil : name
        }
        let word = rest.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
        // (A bare 1 to 9 is a heading level, not a name: LibreOffice's
        // 06933f8e footer "STYLEREF 1" keeps its text.)
        return word.isEmpty || word.hasPrefix("\\") || (word.count == 1 && "123456789".containsSubstring(word)) ? nil : word
    }

    /// The name a `REF` field points at when the document defines no such
    /// bookmark, else nil.
    static func _missingReference(_ instr: String, _ names: Set<String>, _ otherText: String) -> String? {
        let words = instr.trimmingWhitespace(newlines: true).split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard words.count >= 2, words[0].uppercased() == "REF" else { return nil }
        // (Quotes off both ends by hand: `trimmingCharacters(in:)` is legacy Foundation, which the web build leaves out.)
        var quoted = Substring(words[1])
        while quoted.first == "\"" { quoted = quoted.dropFirst() }
        while quoted.last == "\"" { quoted = quoted.dropLast() }
        let name = String(quoted)
        guard !name.isEmpty, !name.hasPrefix("\\"), !names.contains(name.lowercased()),
              !otherText.lowercased().containsSubstring("w:name=\"\(name.lowercased())\"") else { return nil }
        return name
    }
    static func _isPageField(_ instr: String) -> Bool {
        let word = instr.trimmingWhitespace(newlines: true).uppercased().split(separator: " ").first.map(String.init) ?? ""
        return word == "PAGE" || word == "NUMPAGES" || word == "SECTIONPAGES"
    }

    /// Metadata fields keep their cached result and instruction; layout
    /// does not update them or confuse them with page-number fields.
    static func _isHyperlinkField(_ instr: String) -> Bool {
        instr.split(whereSeparator: { $0.isWhitespace }).first?.uppercased() == "HYPERLINK"
    }

    /// Where a HYPERLINK field points: its address and/or `\l` place ("#place" for the document's own), and the `\o` tip.
    static func _hyperlinkFieldTarget(_ instr: String) -> (target: String, tip: String?)? {
        var tokens: [(text: String, quoted: Bool)] = []
        var cur = "", quoted = false, inQuote = false, any = false
        for ch in instr {
            if ch == "\"" { if inQuote { tokens.append((cur, true)); cur = ""; any = false } ; inQuote.toggle(); quoted = inQuote; continue }
            if ch.isWhitespace && !inQuote { if any { tokens.append((cur, false)); cur = ""; any = false }; continue }
            cur.append(ch); any = true
        }
        if any { tokens.append((cur, quoted)) }
        guard tokens.count > 1 else { return nil }
        var url = "", place = "", tip: String? = nil
        var i = 1
        while i < tokens.count {
            let t = tokens[i]
            if !t.quoted, t.text.hasPrefix("\\") {
                let sw = t.text.lowercased()
                if (sw == "\\l" || sw == "\\o" || sw == "\\t"), i + 1 < tokens.count {
                    if sw == "\\l" { place = tokens[i + 1].text } else if sw == "\\o" { tip = tokens[i + 1].text }
                    i += 2; continue
                }
            } else if url.isEmpty { url = t.text }
            i += 1
        }
        if url.isEmpty && place.isEmpty { return nil }
        return (place.isEmpty ? url : url + "#" + place, tip)
    }

    static func _preservesField(_ instr: String) -> Bool {
        let word = instr.split(whereSeparator: { $0.isWhitespace }).first?.uppercased() ?? ""
        return Self._keptFieldWords.contains(word)
    }

    /// Fields whose result is one inline run of text, shown as the file cached it
    /// and written back as the field so Word can bring it up to date. (TOC, which
    /// spans paragraphs, the page-number fields of headers and footers, IF, EQ,
    /// HYPERLINK and the form fields have their own paths.)
    static let _keptFieldWords: Set<String> = [
        "AUTHOR", "DATE", "DOCPROPERTY", "REF", "SEQ", "MERGEFIELD", "STYLEREF", "TITLE", "SUBJECT", "KEYWORDS", "COMMENTS",
        "FILENAME", "FILESIZE", "NUMWORDS", "NUMCHARS", "NUMPAGES", "PAGE", "SECTION", "SECTIONPAGES", "CREATEDATE", "SAVEDATE",
        "PRINTDATE", "TIME", "EDITTIME", "REVNUM", "LASTSAVEDBY", "USERNAME", "USERINITIALS", "USERADDRESS", "TEMPLATE",
        "DOCVARIABLE", "INFO", "QUOTE", "AUTONUM", "AUTONUMLGL", "AUTONUMOUT", "LISTNUM", "NOTEREF", "CITATION",
    ]

    static func _fieldText(_ root: XNode) -> String {
        var out: [String] = []
        var skipping = false   // between a field's separate and end
        func walk(_ node: XNode, into line: inout String) {
            for child in node.children {
                switch child.name {
                case "w:pPr", "w:rPr": break   // tab STOPS live in w:pPr/w:tabs as w:tab too
                case "mc:AlternateContent":
                    // One rendering of the two (a text box's Choice and its
                    // VML Fallback hold the same text), not both.
                    if let pick = child.first("mc:Choice") ?? child.first("mc:Fallback") { walk(pick, into: &line) }
                case "w:t": if !skipping { line += _runText(child) }
                case "w:tab": if !skipping { line += "\t" }
                case "w:ptab":
                    // A positional tab: Word's header/footer convention
                    // is left, centre and right thirds, so a centre tab
                    // is the first stop and a right tab the second.
                    if !skipping {
                        let want = child["w:alignment"] == "right" ? 2 : 1
                        let have = line.filter { $0 == "\t" }.count
                        line += String(repeating: "\t", count: max(1, want - have))
                    }
                case "w:fldSimple":
                    let instr = (child["w:instr"] ?? "").uppercased()
                    if instr.containsSubstring("NUMPAGES") { line += RichDocument.pageCountField }
                    else if instr.containsSubstring("PAGE") { line += RichDocument.pageField }
                    else { walk(child, into: &line) }
                case "w:instrText":
                    let instr = child.text.uppercased()
                    if instr.containsSubstring("NUMPAGES") { line += RichDocument.pageCountField }
                    else if instr.containsSubstring("PAGE") { line += RichDocument.pageField }
                case "w:fldChar":
                    switch child["w:fldCharType"] {
                    case "separate": skipping = true
                    case "end": skipping = false
                    default: break
                    }
                default: walk(child, into: &line)
                }
            }
        }
        // Every paragraph, including those inside a table or a text box
        // (60329's banner is a one-cell table).
        func paragraphs(_ node: XNode) {
            for child in node.children {
                if child.name == "w:p" {
                    var line = ""
                    walk(child, into: &line)
                    let trimmed = line.trimmingWhitespace(newlines: false)
                    if !trimmed.isEmpty { out.append(trimmed) }
                } else if child.name == "mc:AlternateContent" {
                    if let pick = child.first("mc:Choice") ?? child.first("mc:Fallback") { paragraphs(pick) }
                } else {
                    paragraphs(child)
                }
            }
        }
        paragraphs(root)
        return out.joined(separator: " ")
    }

    /// Our sheet id for a Word style name (lowercased), or nil.
    static func _styleId(_ name: String) -> String? {
        for level in 1 ... 6 where name == "heading \(level)" || name == "heading\(level)" {
            return RichNamedStyle.headingId(level)
        }
        switch name {
        case "normal": return RichNamedStyle.normalId
        case "title": return "Title"
        case "subtitle": return "Subtitle"
        case "quote", "intense quote", "intensequote", "block text", "blocktext": return "Quote"
        case "caption": return "Caption"
        case "code", "html preformatted", "htmlpreformatted", "source code", "sourcecode", "plain text", "plaintext": return "Code"
        default: return nil
        }
    }

    /// A separator note's line is sized by the separator character it holds, in that run's own face and size: Word sets the line
    /// 13.47 pt for a bare `w:separator` run (Normal 11 pt) under a 6 pt paragraph mark, not by the mark's 7.44 (sa1 3a00de51).
    /// The importer keeps no character for the run, so the mark's size is dropped where the run sets none of its own.
    static func sizeSeparatorByItsRun(_ note: XNode, _ paragraphs: inout [RichParagraph]) {
        let sources = note.all("w:p")
        guard sources.count == paragraphs.count else { return }
        for (k, src) in sources.enumerated() {
            let runs = src.all("w:r")
            guard let run = runs.first(where: { $0.first("w:separator") != nil || $0.first("w:continuationSeparator") != nil }),
                  run.first("w:rPr")?.first("w:sz") == nil, paragraphs[k].text.isEmpty else { continue }
            var st = paragraphs[k].style; st.mark = nil
            paragraphs[k] = RichParagraph(text: "", style: st)
        }
    }

    /// Alignment, indents and spacing from a w:pPr, onto `style`.
    /// East Asian paragraph markup carried in `RichParagraphStyle.eastAsian`
    /// (schema order): the switches, and the character- and line-unit
    /// measures of `w:ind` and `w:spacing`.
    /// Settings kept as written (`RichDocument.keptSettings`), in four
    /// groups by where the schema puts them.
    /// `OFFICE_WORD_FONTS=windows`: laid out as Word for Windows does where
    /// it differs from Word for Mac (the background's header marks).
    static var wordOnWindows = ProcessInfo.processInfo.environment["OFFICE_WORD_FONTS"] == "windows"
    static let wordOnMac = ProcessInfo.processInfo.environment["OFFICE_WORD_FONTS"] == "mac"

    /// What a VML WordArt shape adds to its line's height in Word for
    /// Windows' print, over its box (see `objectAttachment`'s note); nil
    /// for a shape that is not WordArt. The outline's term between the
    /// weights the lab measured is in proportion, and past 4pt goes on
    /// as from 3 to 4.
    static func _wordArtExtra(_ shape: XNode, types: [XNode]) -> Double? {
        let ref = shape["type"] ?? ""
        let id = ref.hasPrefix("#") ? String(ref.dropFirst()) : ref
        let type = types.first { $0["id"] == id }
        let spt = Int(shape["o:spt"] ?? type?["o:spt"] ?? "") ?? 0
        guard (136 ... 175).contains(spt), let path = shape.first("v:textpath") ?? type?.first("v:textpath"),
              !["f", "false", "0"].contains(path["on"] ?? type?.first("v:textpath")?["on"] ?? "f") else { return nil }
        let stroke = shape.first("v:stroke")
        let off = ["f", "false", "0"]
        var weight = 0.0
        if !off.contains(shape["stroked"] ?? "t"), !off.contains(stroke?["on"] ?? "t") {
            weight = _length(shape["strokeweight"] ?? stroke?["weight"] ?? "") ?? 0.75
        }
        // (Lab wae, Word for Windows, WordWithAttachments' package: a
        // 150 by 28.5pt Arial Black textpath between two Times 10pt lines
        // adds 0.84 over its box unstroked and unshadowed, its text with
        // descenders or without; a 0.5, 1, 2, 3 and 4pt outline 0.6, 0.75,
        // 8.16, 15.0 and 24.6 more; a shadow its offset's y — 3pt down
        // 3.03, 3pt across nothing, unstated (2pt) or perspective 2.28 —
        // and a shadow and an outline together the larger. The table
        // before it, an earlier lab's, set a 1pt outline 2.28 and any
        // shadow 2.28: ours stood WordWithAttachments' p1 2.5pt high
        // after its three titles, and its p2 icon on p1.)
        let table: [(Double, Double)] = [(0, 0), (0.5, 0.6), (1, 0.75), (2, 8.16), (3, 15.0), (4, 24.62)]
        var outline = 0.0
        if weight >= 4 {
            outline = 24.62 + (weight - 4) * (24.62 - 15.0)
        } else if let i = table.indices.dropFirst().first(where: { table[$0].0 >= weight }) {
            let (w0, e0) = table[i - 1], (w1, e1) = table[i]
            outline = e0 + (e1 - e0) * (weight - w0) / (w1 - w0)
        }
        var shadowDrop = 0.0
        if let shadow = shape.first("v:shadow"), !off.contains(shadow["on"] ?? "f") {
            let parts = (shadow["offset"] ?? "").split(separator: ",", omittingEmptySubsequences: false)
            if parts.count >= 2, let y = _length(String(parts[1].filter { $0 != " " })) {
                // (A shadow thrown up grows the line by its offset the same
                // way: dx2 e9eab5f8's -36pt shadow put Word's body 35.3pt
                // below ours.)
                shadowDrop = abs(y)
            } else {
                shadowDrop = 2.28
            }
        }
        return 0.84 + max(outline, shadowDrop)
    }
    static let _keptSettingNames: [[String]] = [
        ["w:embedTrueTypeFonts", "w:embedSystemFonts", "w:saveSubsetFonts",
         "w:alignBordersAndEdges", "w:bordersDoNotSurroundHeader", "w:bordersDoNotSurroundFooter"],
        ["w:autoHyphenation", "w:consecutiveHyphenLimit", "w:hyphenationZone", "w:doNotHyphenateCaps"],
        ["w:noPunctuationKerning"],
        ["w:strictFirstAndLastChars", "w:noLineBreaksAfter", "w:noLineBreaksBefore"],
    ]

    static let _vmlShapes: Set<String> = ["v:shape", "v:rect", "v:group", "v:line", "v:oval", "v:roundrect"]

    /// The outermost VML shape of a drawing — a group before the shapes
    /// in it, which stand in the group's own coordinates (`style`'s
    /// unitless left, top, width and height).
    static func _vmlTop(_ node: XNode) -> XNode? {
        var level = [node]
        while !level.isEmpty {
            if let hit = level.first(where: { _vmlShapes.contains($0.name) }) { return hit }
            level = level.flatMap(\.children)
        }
        return nil
    }

    /// Where the text of a VML group's text box stands in the group, in
    /// points from its top left: the box's place in the group's
    /// coordinates (`coordorigin`, `coordsize`) inside the textbox's
    /// insets (VML's 7.2pt and 3.6pt where it states none).
    static func _vmlTextPlace(_ group: XNode) -> Rect? {
        func boxed(_ n: XNode) -> Bool { n.first("v:textbox") != nil }
        guard let shape = group.all("v:shape").first(where: boxed) ?? group.all("v:rect").first(where: boxed)
                ?? group.descendants("v:shape").first(where: boxed) ?? group.descendants("v:rect").first(where: boxed),
              let textbox = shape.first("v:textbox") else { return nil }
        // (Through nested groups, each with its own coordinates, and with a
        // missing `left` or `top` at 0: lo-83c47ec6's sidebar rectangle stands
        // in a group in a group and gives no `top`.)
        if let content = textbox.descendant("w:txbxContent"),
           !group.children.contains(where: { $0 === shape }) || !(shape["style"] ?? "").containsSubstring("top:") || !(shape["style"] ?? "").containsSubstring("left:"),
           let hit = _vmlTextPlaces(group).first(where: { $0.content === content }) { return hit.place }
        func style(_ n: XNode) -> [String: String] {
            var out: [String: String] = [:]
            for pair in (n["style"] ?? "").split(separator: ";") {
                let kv = pair.split(separator: ":", maxSplits: 1)
                if kv.count == 2 { out[kv[0].trimmingWhitespace()] = String(kv[1]).trimmingWhitespace() }
            }
            return out
        }
        func pair(_ raw: String?, _ fallback: (Double, Double)) -> (Double, Double) {
            let v = (raw ?? "").split(separator: ",", omittingEmptySubsequences: false).map { Double($0.trimmingWhitespace()) }
            return (v.count > 0 ? v[0] ?? fallback.0 : fallback.0, v.count > 1 ? v[1] ?? fallback.1 : fallback.1)
        }
        let g = style(group), sh = style(shape)
        guard let gw = g["width"].flatMap(_length), let gh = g["height"].flatMap(_length), gw > 0, gh > 0,
              let x = sh["left"].flatMap({ Double($0) }), let y = sh["top"].flatMap({ Double($0) }),
              let w = sh["width"].flatMap({ Double($0) }), let h = sh["height"].flatMap({ Double($0) }) else { return nil }
        let origin = pair(group["coordorigin"], (0, 0)), size = pair(group["coordsize"], (1000, 1000))
        guard size.0 > 0, size.1 > 0 else { return nil }
        let kx = gw / size.0, ky = gh / size.1
        let inset = (textbox["inset"] ?? "").split(separator: ",", omittingEmptySubsequences: false).map { _length(String($0)) }
        func at(_ k: Int, _ d: Double) -> Double { k < inset.count ? inset[k] ?? d : d }
        return Rect.fromLTRB((x - origin.0) * kx + at(0, 7.2), (y - origin.1) * ky + at(1, 3.6),
                             (x - origin.0 + w) * kx - at(2, 7.2), (y - origin.1 + h) * ky - at(3, 3.6))
    }

    /// A lone VML shape's text rectangle, as fractions of its box: its
    /// The four numbers of a `textboxrect` that names `v:formulas` entries (`@n`) or handles (`#n`), read
    /// through the type's formulas (`val sum prod mid abs min max sqrt if`) with the shape's `adj` over the type's.
    static func _vmlFormulaRect(_ raw: String, type: XNode, shape: XNode, coord: (Double, Double)) -> [Double]? {
        let adjRaw = (shape["adj"] ?? "").split(separator: ",", omittingEmptySubsequences: false)
        let typeAdj = (type["adj"] ?? "").split(separator: ",", omittingEmptySubsequences: false)
        var adjs: [Double] = []
        for i in 0..<max(adjRaw.count, typeAdj.count) {
            let a = i < adjRaw.count ? Double(adjRaw[i].trimmingWhitespace()) : nil
            let t = i < typeAdj.count ? Double(typeAdj[i].trimmingWhitespace()) : nil
            adjs.append(a ?? t ?? 0)
        }
        let eqns = (type.first("v:formulas")?.all("v:f") ?? []).compactMap { $0["eqn"] }
        var memo: [Int: Double] = [:]
        func arg(_ t: String, _ depth: Int) -> Double? {
            let t = t.trimmingWhitespace()
            if let d = Double(t) { return d }
            if t == "width" { return coord.0 }
            if t == "height" { return coord.1 }
            if t == "xcenter" { return coord.0 / 2 }
            if t == "ycenter" { return coord.1 / 2 }
            if t.hasPrefix("#"), let i = Int(t.dropFirst()), i < adjs.count { return adjs[i] }
            if t.hasPrefix("@"), let i = Int(t.dropFirst()), i < eqns.count, depth < 12 { return eval(i, depth + 1) }
            return nil
        }
        func eval(_ i: Int, _ depth: Int) -> Double? {
            if let m = memo[i] { return m }
            let parts = eqns[i].split(separator: " ").map(String.init)
            guard let op = parts.first else { return nil }
            let a = parts.dropFirst().map { arg($0, depth) }
            if a.contains(where: { $0 == nil }) { return nil }
            let x = a.map { $0! }
            var r: Double?
            switch op {
            case "val" where x.count == 1: r = x[0]
            case "sum" where x.count == 3: r = x[0] + x[1] - x[2]
            case "prod" where x.count == 3: r = x[2] == 0 ? nil : x[0] * x[1] / x[2]
            case "mid" where x.count == 2: r = (x[0] + x[1]) / 2
            case "abs" where x.count == 1: r = Swift.abs(x[0])
            case "min" where x.count == 2: r = Swift.min(x[0], x[1])
            case "max" where x.count == 2: r = Swift.max(x[0], x[1])
            case "sqrt" where x.count == 1: r = x[0] >= 0 ? x[0].squareRoot() : nil
            case "if" where x.count == 3: r = x[0] > 0 ? x[1] : x[2]
            default: r = nil
            }
            if let r { memo[i] = r }
            return r
        }
        let vals = raw.split(separator: ",").map { arg(String($0), 0) }
        guard vals.count == 4, !vals.contains(where: { $0 == nil }) else { return nil }
        return vals.map { $0! }
    }

    /// `v:shapetype`'s `textboxrect` (among `types`, by id) where that
    /// is plain numbers, else VML's own for the type (`o:spt`) — nil for
    /// a rectangle or a type not known here. The rounded ones inset by
    /// 0.2929 of their corner (`adj`, 2700 of 21600 for the alternate
    /// process, 5400 for the round rectangle).
    static func _vmlTextRect(_ node: XNode, types: [XNode]) -> Rect? {
        // (A VML ellipse sets its text in the inscribed rectangle, as the
        // type 3 shape does: lo-ff3b52d1's oval, Word's text 15.4pt in.)
        if node.name == "v:oval" || (node.descendant("v:shape") == nil && node.descendant("v:oval") != nil) {
            return Rect.fromLTRB(3163 / 21600, 3163 / 21600, 18437 / 21600, 18437 / 21600)
        }
        guard let shape = node.name == "v:shape" ? node : node.descendant("v:shape") else { return nil }
        let typeId = shape["type"].map { $0.hasPrefix("#") ? String($0.dropFirst()) : $0 }
        if let id = typeId, let type = types.first(where: { $0["id"] == id }),
           let raw = type.first("v:path")?["textboxrect"]?.split(separator: ";").first {
            let cs = (type["coordsize"] ?? "21600,21600").split(separator: ",").compactMap { Double($0.trimmingWhitespace()) }
            var v = raw.split(separator: ",").compactMap { Double($0.trimmingWhitespace()) }
            if v.count != 4, cs.count == 2 {
                // (A textboxrect named by the type's formulas, as the right arrow's `0,@1,@6,@2`.)
                v = Self._vmlFormulaRect(String(raw), type: type, shape: shape, coord: (cs[0], cs[1])) ?? v
            }
            guard v.count == 4, cs.count == 2, cs[0] > 0, cs[1] > 0, v[2] > v[0], v[3] > v[1] else { return nil }
            return Rect.fromLTRB(v[0] / cs[0], v[1] / cs[1], v[2] / cs[0], v[3] / cs[1])
        }
        let spt = shape["o:spt"].flatMap { Int(Double($0) ?? -1) }
            ?? typeId.flatMap { $0.hasPrefix("_x0000_t") ? Int($0.dropFirst(8)) : nil }
        guard let spt else { return nil }
        let adj = (shape["adj"] ?? "").split(separator: ",", omittingEmptySubsequences: false).first.flatMap { Double($0.trimmingWhitespace()) }
        let box: (Double, Double, Double, Double)
        switch spt {
        case 2, 176:
            let k = (adj ?? (spt == 2 ? 5400 : 2700)) * 0.2929
            box = (k, k, 21600 - k, 21600 - k)
        case 3, 120: box = (3163, 3163, 18437, 18437)
        case 110: box = (5400, 5400, 16200, 16200)
        case 116: box = (1018, 3163, 20582, 18437)
        // (The explosions: DrawingML's `irregularSeal1` and `2` text rectangles. zh-60c80728's "突发事件" in its
        // `o:spt` 71 burst stands 15pt lower in Word's print than in the whole box.)
        case 71: box = (4627, 6320, 16702, 13937)
        case 72: box = (5372, 6382, 14640, 15935)
        default: return nil
        }
        return Rect.fromLTRB(box.0 / 21600, box.1 / 21600, box.2 / 21600, box.3 / 21600)
    }

    /// Every text box in a VML group, nested groups' too, in document
    /// order: its content, where its text stands in the outermost group
    /// in points from its top left (`_vmlTextPlace`'s reckoning, through
    /// each group's `coordorigin` and `coordsize`), and whether it stands
    /// at the box's foot (`v-text-anchor:bottom`). A shape whose
    /// `v:shapetype` (among `types`, by id) gives a `textboxrect` sets
    /// its text in that: zh-6e6b9821's flowchart "preparation" hexagon
    /// (`_x0000_t117`, 4353 to 17214 of 21600 across) has its text at
    /// 217pt in Word's print, 50pt in from the box's edge.
    static func _vmlTextPlaces(_ group: XNode, types: [XNode] = []) -> [(content: XNode, place: Rect, atFoot: Bool, inMiddle: Bool)] {
        func style(_ n: XNode) -> [String: String] {
            var out: [String: String] = [:]
            for pair in (n["style"] ?? "").split(separator: ";") {
                let kv = pair.split(separator: ":", maxSplits: 1)
                if kv.count == 2 { out[kv[0].trimmingWhitespace()] = String(kv[1]).trimmingWhitespace() }
            }
            return out
        }
        func pair(_ raw: String?, _ fallback: (Double, Double)) -> (Double, Double) {
            let v = (raw ?? "").split(separator: ",", omittingEmptySubsequences: false).map { Double($0.trimmingWhitespace()) }
            return (v.count > 0 ? v[0] ?? fallback.0 : fallback.0, v.count > 1 ? v[1] ?? fallback.1 : fallback.1)
        }
        let g = style(group)
        guard let gw = g["width"].flatMap(_length), let gh = g["height"].flatMap(_length), gw > 0, gh > 0 else { return [] }
        var out: [(content: XNode, place: Rect, atFoot: Bool, inMiddle: Bool)] = []
        // A group's children in its own coordinates → points in the outermost.
        let topGroup = group
        func walk(_ group: XNode, _ map: @escaping (Rect) -> Rect) {
            let origin = pair(group["coordorigin"], (0, 0)), size = pair(group["coordsize"], (1000, 1000))
            guard size.0 > 0, size.1 > 0 else { return }
            for child in group.children {
                let sh = style(child)
                // (A missing `left` or `top` is 0, CSS's default: lo-83c47ec6's
                // sidebar rectangle gives only `left`, and Word sets its text
                // in it, not across the whole group.)
                guard let w = sh["width"].flatMap({ Double($0) }), let h = sh["height"].flatMap({ Double($0) }) else { continue }
                let x = sh["left"].flatMap { Double($0) } ?? 0, y = sh["top"].flatMap { Double($0) } ?? 0
                var r = map(Rect.fromLTWH(x - origin.0, y - origin.1, w, h))
                // (A child with `mso-width-percent` is that share of its
                // group's width, in the group's middle where it centres:
                // Word's lab 8 (lo-0622682c) sets a 1000 child across the
                // whole of a group as wide as the page.)
                if group === topGroup, let pct = sh["mso-width-percent"].flatMap({ Double($0) }), pct > 0, child.name != "v:group" {
                    let pw = gw * pct / 1000
                    r = Rect.fromLTWH(sh["mso-position-horizontal"] == "center" ? (gw - pw) / 2 : r.left, r.top, pw, r.height)
                }
                if child.name == "v:group" {
                    let inner = pair(child["coordsize"], (1000, 1000))
                    guard inner.0 > 0, inner.1 > 0 else { continue }
                    walk(child) { q in Rect.fromLTWH(r.left + q.left * r.width / inner.0, r.top + q.top * r.height / inner.1,
                                                     q.width * r.width / inner.0, q.height * r.height / inner.1) }
                } else if _vmlShapes.contains(child.name), let textbox = child.first("v:textbox"),
                          let content = textbox.descendant("w:txbxContent") {
                    let inset = (textbox["inset"] ?? "").split(separator: ",", omittingEmptySubsequences: false).map { _length(String($0)) }
                    func at(_ k: Int, _ d: Double) -> Double { k < inset.count ? inset[k] ?? d : d }
                    if let id = child["type"].map({ $0.hasPrefix("#") ? String($0.dropFirst()) : $0 }),
                       let type = types.first(where: { $0["id"] == id }),
                       let raw = type.first("v:path")?["textboxrect"]?.split(separator: ";").first,
                       case let v = raw.split(separator: ",").compactMap({ Double($0.trimmingWhitespace()) }), v.count == 4 {
                        let cs = pair(type["coordsize"], (21600, 21600))
                        if cs.0 > 0, cs.1 > 0, v[2] > v[0], v[3] > v[1] {
                            r = Rect.fromLTRB(r.left + v[0] / cs.0 * r.width, r.top + v[1] / cs.1 * r.height,
                                              r.left + v[2] / cs.0 * r.width, r.top + v[3] / cs.1 * r.height)
                        }
                    }
                    out.append((content, Rect.fromLTRB(r.left + at(0, 7.2), r.top + at(1, 3.6), r.right - at(2, 7.2), r.bottom - at(3, 3.6)),
                                sh["v-text-anchor"]?.hasPrefix("bottom") == true, sh["v-text-anchor"]?.hasPrefix("middle") == true))
                }
            }
        }
        let size = pair(group["coordsize"], (1000, 1000))
        guard size.0 > 0, size.1 > 0 else { return [] }
        // (A group sized as a share of the margins has its children's
        // spread for its height: lab grp2 (Word for Windows, lo-0622682c),
        // the first box's top to the last's foot fill the group — 11018
        // units of a 12960 coordinate box, 0.0564pt each over 621.95pt,
        // not 0.048.)
        var yScale = gh / size.1
        if g["mso-height-percent"] != nil {
            let origin = pair(group["coordorigin"], (0, 0))
            let tops = group.children.compactMap { c -> (Double, Double)? in
                let sh = style(c)
                guard let y = sh["top"].flatMap({ Double($0) }), let h = sh["height"].flatMap({ Double($0) }) else { return nil }
                return (y, y + h)
            }
            // (The last box is fitted to its text — its line, 1.15 of the
            // largest size in it, and its insets — so it ends where the text
            // does, not at its stated foot: 48pt "TEXT2" is 62.4pt tall in
            // Word's print, which makes the scale 0.0576 per unit.)
            if let low = tops.map({ $0.0 }).min(), abs(low - origin.1) < 1,
               let last = group.children.filter({ style($0)["top"] != nil }).max(by: { (Double(style($0)["top"] ?? "") ?? 0) < (Double(style($1)["top"] ?? "") ?? 0) }),
               let lastTop = Double(style(last)["top"] ?? ""), lastTop > low,
               (last.first("v:textbox")?["style"] ?? "").containsSubstring("mso-fit-shape-to-text:t"),
               let content = last.first("v:textbox")?.descendant("w:txbxContent") {
                let sizes = content.descendants("w:sz").compactMap { Double($0["w:val"] ?? "") }
                if let big = sizes.max(), big > 0 {
                    let fitted = big / 2 * 1.15 + 7.2
                    yScale = (gh - fitted) / (lastTop - low)
                }
            } else if let low = tops.map({ $0.0 }).min(), let high = tops.map({ $0.1 }).max(), high > low, abs(low - origin.1) < 1 { yScale = gh / (high - low) }
        }
        walk(group) { r in Rect.fromLTWH(r.left * gw / size.0, r.top * yScale, r.width * gw / size.0, r.height * yScale) }
        return out
    }

    /// Where an anchored drawing floats (`wp:anchor`: its two positions
    /// and its wrapping), or nil for one in the line. A VML shape floats
    /// when its style positions it absolutely — the outermost one: a
    /// drawing canvas in the line (`v:group`, WordWithAttachments'
    /// "Словарь" box) holds shapes placed absolutely in it, and floated
    /// by its text box it took no room.
    /// The part of a picture that shows: a DrawingML `a:srcRect` (hundred-thousandths) or a VML
    /// `v:imagedata`'s `croptop`… (sixty-five-thousandths with an "f", or percent). Cut-ins only
    /// (a negative share would pad the picture, which is not drawn).
    static func _pictureCrop(_ node: XNode) -> PictureCrop? {
        func share(_ text: String?, per: Double) -> Double {
            guard var t = text, !t.isEmpty else { return 0 }
            var scale = per
            if t.hasSuffix("f") { t.removeLast(); scale = 65536 } else if t.hasSuffix("%") { t.removeLast(); scale = 100 }
            return max(0, (Double(t) ?? 0) / scale)
        }
        var crop = PictureCrop(left: 0, top: 0, right: 0, bottom: 0)
        if let r = node.descendant("a:srcRect") {
            crop = PictureCrop(left: share(r["l"], per: 100000), top: share(r["t"], per: 100000), right: share(r["r"], per: 100000), bottom: share(r["b"], per: 100000))
        } else if let d = node.descendant("v:imagedata") {
            crop = PictureCrop(left: share(d["cropleft"], per: 65536), top: share(d["croptop"], per: 65536), right: share(d["cropright"], per: 65536), bottom: share(d["cropbottom"], per: 65536))
        }
        guard crop.left + crop.right < 0.99, crop.top + crop.bottom < 0.99,
              crop.left > 0 || crop.top > 0 || crop.right > 0 || crop.bottom > 0 else { return nil }
        return crop
    }

    /// Where the picture stands in the drawing canvas it is the only thing in, from `a:xfrm`, or nil.
    static func _canvasInset(_ drawing: XNode) -> PictureCrop? {
        guard drawing.descendant("wpc:wpc") != nil,
              let extent = drawing.descendant("wp:extent"), let cx = Double(extent["cx"] ?? ""), let cy = Double(extent["cy"] ?? ""), cx > 0, cy > 0,
              let pic = drawing.descendant("pic:pic"), let xfrm = pic.descendant("a:xfrm"),
              let off = xfrm.first("a:off"), let ext = xfrm.first("a:ext"),
              let x = Double(off["x"] ?? ""), let y = Double(off["y"] ?? ""), let w = Double(ext["cx"] ?? ""), let h = Double(ext["cy"] ?? ""),
              w > 0, h > 0, x >= 0, y >= 0, x + w <= cx + 1, y + h <= cy + 1,
              w < cx * 0.98 || h < cy * 0.98 else { return nil }
        return PictureCrop(left: x / cx, top: y / cy, right: max(0, 1 - (x + w) / cx), bottom: max(0, 1 - (y + h) / cy))
    }

    static func _float(_ node: XNode) -> ImageFloat? {
        if let anchor = node.name == "wp:anchor" ? node : node.descendant("wp:anchor") {
            var f = ImageFloat()
            f.leavesCell = anchor["layoutInCell"] == "0"
            // Word can wrap either position in AlternateContent, with a
            // wp14 percentage in Choice and a point offset in Fallback.
            // We do not interpret percentage positions yet. Read their
            // fallback instead of dropping the position altogether:
            // 60316's page-anchored sidebar landed in the body column.
            func position(_ name: String) -> XNode? {
                anchor.first(name) ?? anchor.all("mc:AlternateContent")
                    .compactMap { $0.first("mc:Fallback")?.first(name) }.first
            }
            if let h = position("wp:positionH") {
                f.horizontalFrom = h["relativeFrom"] ?? "column"
                // (The left margin is the strip from the page's edge to the text, and the
                // offset runs from its start: lo-08b61fb0's box at -144.35pt "from the
                // left margin" stands 144.4pt left of the page's edge in Word's print,
                // not 73.5 as measured from the text.)
                if let v = Double(h.first("wp:posOffset")?.text ?? "") { f.x = v / 12700 }
                f.horizontalAlign = h.first("wp:align")?.text
                if f.horizontalFrom == "leftMargin", f.horizontalAlign == nil { f.horizontalFrom = "page" }
            }
            if let v = position("wp:positionV") {
                f.verticalFrom = v["relativeFrom"] ?? "paragraph"
                if let o = Double(v.first("wp:posOffset")?.text ?? "") { f.y = o / 12700 }
                f.verticalAlign = v.first("wp:align")?.text
            }
            f.takesRoom = anchor.first("wp:wrapTopAndBottom") != nil
            // (A top-and-bottom band set from the anchor's line is kept from the paragraph, as the line an object is anchored in is
            // the paragraph's first for the usual one-line title: dx2 7d7592a1's squiggle, 46.4pt under "AuerbachsKellertheaterStaufen",
            // bands the page there in Word's print and sends the line under it.)
            if f.takesRoom, f.verticalFrom == "line", f.verticalAlign == nil { f.verticalFrom = "paragraph" }
            f.wraps = ["wp:wrapSquare", "wp:wrapTight", "wp:wrapThrough"].contains { anchor.first($0) != nil }
            f.wrapsTight = anchor.first("wp:wrapTight") != nil || anchor.first("wp:wrapThrough") != nil
            if let w = ["wp:wrapSquare", "wp:wrapTight", "wp:wrapThrough"].lazy.compactMap({ anchor.first($0) }).first,
               let side = w["wrapText"], side == "left" || side == "right" || side == "largest" { f.wrapSide = side }
            // (A tight wrap's polygon with a cut corner at the top: the right edge reaches its full
            // reach a few points down, and a line over that stretch is held in by less than the
            // box. lo tdf163575: 1072 of 21600 down on a 181pt picture, Word's first line at 190.4
            // over a picture ending at 199.9.)
            if let tight = anchor.first("wp:wrapTight") ?? anchor.first("wp:wrapThrough"), let polygon = tight.first("wp:wrapPolygon"), let ext = anchor.first("wp:extent"),
               let cy = Double(ext["cy"] ?? "") {
                let pts = ([polygon.first("wp:start")] + polygon.all("wp:lineTo").map { Optional($0) }).compactMap { $0 }
                    .compactMap { n -> (Double, Double)? in
                        guard let x = Double(n["x"] ?? ""), let y = Double(n["y"] ?? "") else { return nil }
                        return (x, y)
                    }
                if let maxX = pts.map(\.0).max(), let minY = pts.map(\.1).min(), let first = pts.filter({ $0.0 >= maxX - 1 }).min(by: { $0.1 < $1.1 }), first.1 > minY {
                    let skip = (first.1 - minY) / 21600 * cy / 12700
                    if skip > 0, skip <= 12, skip <= cy / 12700 * 0.12 { f.wrapTopSkip = skip }
                }
                if pts.count >= 3 { f.wrapPolygon = pts.map { WrapPoint(x: $0.0 / 21600, y: $0.1 / 21600) } }
                // (The polygon's right reach: Word's wrap edge is the polygon's, not the picture box's: kla.tv's logo, 21185 of 21600.)
                if let maxX = pts.map(\.0).max(), maxX >= 10800, maxX < 21600 { f.wrapReach = maxX / 21600 }
                if let maxY = pts.map(\.1).max(), maxY >= 10800, maxY < 21600 { f.wrapBottomShare = maxY / 21600 }
            }
            Self._bandPage(&f)
            if let b = Double(anchor.first("wp:effectExtent")?["b"] ?? "") { f.effectBottom = b / 12700 }
            if let t = Double(anchor.first("wp:effectExtent")?["t"] ?? "") { f.effectTop = t / 12700 }
            if let l = Double(anchor.first("wp:effectExtent")?["l"] ?? "") { f.effectLeft = l / 12700 }
            if let r = Double(anchor.first("wp:effectExtent")?["r"] ?? "") { f.effectRight = r / 12700 }
            // (A height that is a share of the page's or margins': 60316's
            // header divider, 105% of the margins, 718.2pt where its
            // extent says 99. Not a box that fits its text, which keeps
            // its text's height: zh-3ecd3152's and zh-e0ca7252's say 20%
            // and are 28.5 and 48pt in Word's print.)
            if anchor.descendant("a:spAutoFit") == nil,
               let rel = anchor.first("wp14:sizeRelV"), let pct = Double(rel.first("wp14:pctHeight")?.text ?? ""), pct > 0,
               ["page", "margin"].contains(rel["relativeFrom"] ?? "") {
                f.heightShare = pct / 100_000
                f.heightFrom = rel["relativeFrom"] ?? "margin"
            }
            if let t = Double(anchor["distT"] ?? "") { f.distanceTop = t / 12700 }
            if let b = Double(anchor["distB"] ?? "") { f.distanceBottom = b / 12700 }
            if let l = Double(anchor["distL"] ?? "") { f.distanceLeft = l / 12700 }
            if let r = Double(anchor["distR"] ?? "") { f.distanceRight = r / 12700 }
            return f
        }
        // (Not for a drawing the file puts in the line, `wp:inline`, whose
        // VML fallback says "position:absolute" all the same: lo
        // tdf147485's logo, drawn one height above its line.)
        // (Not one inside the shape's own text box: lo-373ee508's header table holds a picture,
        // and the VML box round it was left in the line, at the paragraph's indent.)
        func holdsInline(_ n: XNode) -> Bool {
            n.children.contains { $0.name == "wp:inline" || ($0.name != "w:txbxContent" && holdsInline($0)) }
        }
        if holdsInline(node) { return nil }
        if let shape = _vmlTop(node), let st = shape["style"], st.containsSubstring("position:absolute") {
            var f = ImageFloat()
            var vmlHeightShare: Double? = nil, vmlHeightFrom = ""
            for pair in st.split(separator: ";") {
                let kv = pair.split(separator: ":", maxSplits: 1)
                guard kv.count == 2 else { continue }
                let key = kv[0].trimmingWhitespace(), value = String(kv[1]).trimmingWhitespace()
                switch key {
                case "margin-left": if let v = _length(value) { f.x = v }
                case "margin-top": if let v = _length(value) { f.y = v }
                // (VML names the side strips "right-margin-area" and "left-margin-area", DrawingML "rightMargin" and "leftMargin":
                // a header's page-number box set right in the right strip stands at the page's edge in Word's print.)
                case "mso-position-horizontal-relative": f.horizontalFrom = value == "text" ? "column" : value == "right-margin-area" ? "rightMargin" : value == "left-margin-area" ? "leftMargin" : value
                // (VML names the bottom margin's strip "bottom-margin-area", DrawingML "bottomMargin": a footer's
                // page-number oval centred in it stands mid-strip in Word's print, poi-51272c8358's 19pt lower than ours.)
                case "mso-position-vertical-relative": f.verticalFrom = value == "text" ? "paragraph" : value == "bottom-margin-area" ? "bottomMargin" : value
                case "mso-position-horizontal": if value != "absolute" { f.horizontalAlign = value }
                case "mso-position-vertical": if value != "absolute" { f.verticalAlign = value }
                case "mso-wrap-distance-top": if let v = _length(value) { f.distanceTop = v }
                case "mso-wrap-distance-bottom": if let v = _length(value) { f.distanceBottom = v }
                case "mso-height-percent": if let v = Double(value), v > 0 { vmlHeightShare = v / 1000 }
                case "mso-height-relative": vmlHeightFrom = value
                default: break
                }
            }
            // (A group as tall as a share of the margins' room: Word's lab
            // grp2 (lo-0622682c's group, 100% of the margins, 9in stated):
            // the margins' height whatever the style height says.)
            if shape.name == "v:group", let share = vmlHeightShare, vmlHeightFrom == "margin" || vmlHeightFrom == "page" {
                f.heightShare = share
                f.heightFrom = vmlHeightFrom
            }
            f.takesRoom = shape.first("w10:wrap")?["type"] == "topAndBottom"
            // (A VML line with no margin offsets stands at its `from` and `to` points; a top-and-bottom one
            // 13.6pt down its paragraph is set under by the next text, as a picture is: sa2 3c4382f0's
            // signature rule, Word's next line 14.28pt lower than ours.)
            if shape.name == "v:line", Self.wordOnWindows, f.takesRoom, !st.containsSubstring("margin-top"),
               let from = shape["from"], let to = shape["to"] {
                func point(_ s: String) -> Double? {
                    let c = s.split(separator: ",")
                    return c.count == 2 ? _length(String(c[1]).trimmingWhitespace()) : nil
                }
                if let a = point(from), let b = point(to) { f.y = min(a, b); f.fromVMLLine = true; f.effectBottom = _length(shape["strokeweight"] ?? "") ?? 0.75 }
            }
            f.wraps = ["square", "tight", "through"].contains(shape.first("w10:wrap")?["type"] ?? "")
            if let side = shape.first("w10:wrap")?["side"], side == "left" || side == "right" { f.wrapSide = side }
            // (Behind the text — a z-index under 0 — no text wraps beside it,
            // whatever its wrap says: zh-6d402586's annex is one empty
            // paragraph anchoring a 786pt flowchart picture, wrap "tight"
            // and z-index -251652097, on a page of 770; Word prints it on
            // that page alone, ours wrapped the paragraph's line under the
            // picture, past the foot, and left the page blank.)
            if let z = st.split(separator: ";").compactMap({ pair -> Double? in
                let kv = pair.split(separator: ":", maxSplits: 1)
                return kv.count == 2 && kv[0].trimmingWhitespace() == "z-index" ? Double(String(kv[1]).trimmingWhitespace()) : nil
            }).first, z < 0 {
                // (A top-and-bottom one still takes its band: zh-7773163d's
                // 153pt boxes at z under 0 push the text below them in
                // Word's print as they did in ours.)
                f.wraps = false
            }
            Self._bandPage(&f)
            return f
        }
        return nil
    }

    /// A top-and-bottom float placed against the page or its margin
    /// bands its page (`ImageFloat.bandsPage`): zh-a78d52e7's red
    /// masthead, a text box 94pt down the page anchored in the second
    /// paragraph, has the first ("嘉政发〔2019〕2号") under it in Word's
    /// print; taken as a block in its anchor's line, ours stood the box
    /// in the flow and the page ran 50pt long.
    static func _bandPage(_ f: inout ImageFloat) {
        // (So does one placed down from its paragraph: zh-6d402586's box of
        // revision dates, 38pt under the second title line it is anchored
        // in, stands at the right margin in Word's print, the title in its
        // place and "一、前言" under the box; set in the line, ours stood
        // the box at the paragraph's start and the title after it.)
        guard f.takesRoom, f.verticalAlign == nil, ["page", "margin", "paragraph"].contains(f.verticalFrom) else { return }
        f.takesRoom = false
        f.bandsPage = true
    }

    static let _eastAsianSwitches = ["w:suppressLineNumbers", "w:suppressAutoHyphens", "w:kinsoku", "w:wordWrap", "w:overflowPunct", "w:topLinePunct", "w:autoSpaceDE", "w:autoSpaceDN", "w:adjustRightInd", "w:snapToGrid", "w:mirrorIndents"]
    static let _eastAsianIndents = ["w:leftChars", "w:startChars", "w:rightChars", "w:endChars", "w:hangingChars", "w:firstLineChars"]
    static let _eastAsianSpacing = ["w:beforeLines", "w:afterLines"]

    /// A SmartArt diagram as the group of shapes Word drew it as: the
    /// `dsp:drawing` part its data names (`dsp:dataModelExt`), each
    /// `dsp:sp` a `wps:wsp` — its outline and fill as they are, and its
    /// text, when it has any, a text box of its own at `dsp:txXfrm` whose
    /// DrawingML paragraphs are read as Word ones. `cx` by `cy` (EMU) is
    /// the frame's extent, the drawing's own space.
    static func _diagramGroup(_ drawing: XNode, cx: Double, cy: Double) -> XNode? {
        guard let tree = drawing.descendant("dsp:spTree") else { return nil }
        func el(_ name: String, _ attrs: [String: String] = [:], _ children: [XNode] = []) -> XNode {
            let n = XNode(name: name, attrs: attrs)
            n.children = children
            return n
        }
        func renamed(_ n: XNode, _ name: String) -> XNode { el(name, n.attrs, n.children) }
        func xfrm(_ x: XNode?) -> XNode? {
            guard let off = x?.first("a:off"), let ext = x?.first("a:ext") else { return nil }
            return el("a:xfrm", x?.attrs ?? [:], [off, ext])
        }
        // A DrawingML paragraph as a Word one: its alignment, line and
        // after spacing, and each run's face, size, weight and colour.
        func paragraph(_ ap: XNode, last: Bool = false) -> XNode {
            var pPr: [XNode] = []
            let props = ap.first("a:pPr")
            let sz: String? = ap.all("a:r").first?.first("a:rPr")?["sz"] ?? ap.first("a:endParaRPr")?["sz"]
            let size: Double = (sz.flatMap { Double($0) } ?? 1800) / 100
            var spacing: [String: String] = [:]
            if let pct = props?.first("a:lnSpc")?.first("a:spcPct")?["val"].flatMap({ Double($0) }) {
                spacing["w:line"] = String(Int((pct / 100000 * 240).rounded())); spacing["w:lineRule"] = "auto"
            }
            for (tag, key) in [("a:spcBef", "w:before"), ("a:spcAft", "w:after")] {
                if let pct = props?.first(tag)?.first("a:spcPct")?["val"].flatMap({ Double($0) }) {
                    spacing[key] = String(Int((pct / 100000 * size * 20).rounded()))
                } else if let pts = props?.first(tag)?.first("a:spcPts")?["val"].flatMap({ Double($0) }) {
                    spacing[key] = String(Int((pts / 100 * 20).rounded()))
                }
            }
            // (The last paragraph's space after does not count in a drawing's text block, so the block centres without it:
            // xd bf53d2b7's footer text stood 1.87 pt high with it, 1.92 pt less without.)
            if last, Self.wordOnWindows { spacing["w:after"] = "0" }
            if !spacing.isEmpty { pPr.append(el("w:spacing", spacing)) }
            let jc = ["ctr": "center", "r": "right", "l": "left", "just": "both", "dist": "distribute"][props?["algn"] ?? "l"] ?? "left"
            pPr.append(el("w:jc", ["w:val": jc]))
            func runProps(_ rPr: XNode?) -> XNode {
                var out: [XNode] = []
                var fonts: [String: String] = [:]
                if let f = rPr?.first("a:latin")?["typeface"], !f.hasPrefix("+") { fonts["w:ascii"] = f; fonts["w:hAnsi"] = f }
                if let f = rPr?.first("a:ea")?["typeface"], !f.hasPrefix("+") { fonts["w:eastAsia"] = f }
                if let f = rPr?.first("a:cs")?["typeface"], !f.hasPrefix("+") { fonts["w:cs"] = f }
                // (A SmartArt run that names no face is set in the theme's body faces, as the diagram's own text is in Word:
                // xd bf53d2b7's footer diagram prints its Hebrew in Arial, the theme's complex-script face, not the document default.)
                if fonts.isEmpty, Self.wordOnWindows {
                    fonts = ["w:asciiTheme": "minorHAnsi", "w:hAnsiTheme": "minorHAnsi", "w:eastAsiaTheme": "minorEastAsia", "w:cstheme": "minorBidi"]
                }
                if !fonts.isEmpty { out.append(el("w:rFonts", fonts)) }
                if rPr?["b"] == "1" { out.append(el("w:b")) }
                if rPr?["i"] == "1" { out.append(el("w:i")) }
                if let hex = rPr?.first("a:solidFill")?.first("a:srgbClr")?["val"] { out.append(el("w:color", ["w:val": hex])) }
                let points: Double = rPr?["sz"].flatMap { Double($0) }.map { $0 / 100 } ?? size
                let half = String(Int((points * 2).rounded()))
                out.append(el("w:sz", ["w:val": half]))
                out.append(el("w:szCs", ["w:val": half]))
                return el("w:rPr", [:], out)
            }
            pPr.append(runProps(ap.first("a:endParaRPr")))
            var children = [el("w:pPr", [:], pPr)]
            for r in ap.children {
                if r.name == "a:r" || r.name == "a:fld" {
                    let t = el("w:t", ["xml:space": "preserve"])
                    t.text = r.first("a:t")?.text ?? ""
                    children.append(el("w:r", [:], [runProps(r.first("a:rPr")), t]))
                } else if r.name == "a:br" {
                    children.append(el("w:r", [:], [runProps(r.first("a:rPr")), el("w:br")]))
                }
            }
            return el("w:p", [:], children)
        }
        var shapes: [XNode] = []
        for sp in tree.all("dsp:sp") {
            guard let spPr = sp.first("dsp:spPr") else { continue }
            var parts = [el("wps:cNvSpPr"), renamed(spPr, "wps:spPr")]
            if let style = sp.first("dsp:style") { parts.append(renamed(style, "wps:style")) }
            parts.append(el("wps:bodyPr"))
            shapes.append(el("wps:wsp", [:], parts))
            guard let body = sp.first("dsp:txBody"), body.all("a:p").contains(where: { !$0.descendants("a:t").isEmpty }),
                  let place = xfrm(sp.first("dsp:txXfrm")) ?? xfrm(spPr.first("a:xfrm")) else { continue }
            let bodyPr = body.first("a:bodyPr").map { renamed($0, "wps:bodyPr") } ?? el("wps:bodyPr")
            let box = el("wps:spPr", [:], [place, el("a:prstGeom", ["prst": "rect"], [el("a:avLst")]), el("a:noFill"),
                                           el("a:ln", [:], [el("a:noFill")])])
            shapes.append(el("wps:wsp", [:], [el("wps:cNvSpPr", ["txBox": "1"]), box,
                                              el("wps:txbx", [:], [el("w:txbxContent", [:], { let ps = body.all("a:p"); return ps.enumerated().map { paragraph($1, last: $0 == ps.count - 1) } }())]), bodyPr]))
        }
        guard !shapes.isEmpty else { return nil }
        let e = String(Int(cx)), f = String(Int(cy))
        let frame = el("a:xfrm", [:], [el("a:off", ["x": "0", "y": "0"]), el("a:ext", ["cx": e, "cy": f]),
                                       el("a:chOff", ["x": "0", "y": "0"]), el("a:chExt", ["cx": e, "cy": f])])
        return el("wpg:wgp", [:], [el("wpg:cNvGrpSpPr"), el("wpg:grpSpPr", [:], [frame])] + shapes)
    }

    /// A group's text boxes (`wps:wsp` holding `w:txbxContent`), those of
    /// the groups nested in it too, in document order, each at its place
    /// in the group's own child space (EMU).
    static func _groupTextBoxes(_ group: XNode) -> [(box: XNode, place: Rect)] {
        func number(_ n: XNode?, _ key: String) -> Double { Double(n?[key] ?? "") ?? 0 }
        var out: [(box: XNode, place: Rect)] = []
        func walk(_ children: [XNode], _ place: @escaping (Rect) -> Rect) {
            for child in children {
                let xfrm = (child.first("wps:spPr") ?? child.first("wpg:grpSpPr"))?.first("a:xfrm")
                let r = Rect.fromLTWH(number(xfrm?.first("a:off"), "x"), number(xfrm?.first("a:off"), "y"),
                                      number(xfrm?.first("a:ext"), "cx"), number(xfrm?.first("a:ext"), "cy"))
                if child.name == "wps:wsp", child.descendant("w:txbxContent") != nil {
                    out.append((child, place(r)))
                } else if child.name == "wpg:grpSp", let xfrm {
                    let chOff = xfrm.first("a:chOff"), chExt = xfrm.first("a:chExt")
                    let kx = number(chExt, "cx") > 0 ? r.width / number(chExt, "cx") : 1
                    let ky = number(chExt, "cy") > 0 ? r.height / number(chExt, "cy") : 1
                    let cx = number(chOff, "x"), cy = number(chOff, "y")
                    walk(child.children) { inner in
                        place(Rect.fromLTWH(r.left + (inner.left - cx) * kx, r.top + (inner.top - cy) * ky, inner.width * kx, inner.height * ky))
                    }
                }
            }
        }
        walk(group.children) { $0 }
        return out
    }

    /// The left indent the list level a paragraph is in states, where the
    /// paragraph carries none of its own (a text box moves it with the box's).
    static func _levelLeft(_ style: RichParagraphStyle, _ notes: _Shared) -> Double? {
        guard style.list != nil, let id = style.listId else { return nil }
        return notes.listFormats[id]?[style.listLevel]?.indentLeft
    }

    /// Half a shape's outline width (points), which Word adds to its
    /// text's insets whether or not the outline is drawn (see the text
    /// box reader); none where the outline states no width.
    static func _halfOutline(_ spPr: XNode?) -> Double {
        Double(spPr?.first("a:ln")?["w"] ?? "").map { $0 / 12700 / 2 } ?? 0
    }

    /// `w:spacing`/`w:ind` markup with the kept line- and character-unit
    /// attributes added (an element is made for them when there is none).
    static func _withEastAsian(_ xml: String, _ element: String, _ attrs: [String], _ style: RichParagraphStyle) -> String {
        let extra = attrs.compactMap { a in style.eastAsian[a].map { " \(a)=\"\(_esc($0))\"" } }.joined()
        if extra.isEmpty { return xml }
        if xml.isEmpty { return "<\(element)\(extra)/>" }
        return xml.replacingAll("<\(element)", with: "<\(element)\(extra)")
    }

    /// `w:tabs` for a paragraph (or a style) whose stops are `stops`, over
    /// the style under it: its own stops, and a "clear" for each of the
    /// style's it does not have.
    static func _tabsXML(_ stops: [TabStop], under: [TabStop]) -> String {
        var out = ""
        for u in under where !stops.contains(where: { abs($0.position - u.position) < 0.026 }) {
            out += "<w:tab w:val=\"clear\" w:pos=\"\(Int((u.position * 20).rounded()))\"/>"
        }
        for t in stops {
            let val = t.rawKind ?? ["left", "center", "right", "decimal"][t.alignment.rawValue]
            out += "<w:tab w:val=\"\(_esc(val))\"\(t.leader.map { " w:leader=\"\(_esc($0))\"" } ?? "") w:pos=\"\(Int((t.position * 20).rounded()))\"/>"
        }
        return out.isEmpty ? "" : "<w:tabs>\(out)</w:tabs>"
    }

    static func _eastAsianSwitchesXML(_ style: RichParagraphStyle) -> String {
        _eastAsianSwitches.compactMap { tag in style.eastAsian[tag].map { "<\(tag) w:val=\"\($0)\"/>" } }.joined()
    }

    /// One edge of a border — a paragraph's (`w:pBdr`) or a run's
    /// (`w:bdr`): sz in eighths of a point, space in points, colour hex
    /// or auto. "nil"/"none" is an edge without a line.
    static func _borderLine(_ e: XNode) -> BorderLine? {
        switch e["w:val"] ?? "nil" {
        case "none":
            // No line, but Word still stands the text its `space`
            // off: a header style with four "none" edges a point
            // away put its text a point lower, and a footer of two
            // such paragraphs four points higher.
            guard let space = Double(e["w:space"] ?? ""), space > 0 else { return nil }
            var gap = BorderLine(width: 0, color: nil, space: space)
            gap.style = "none"
            return gap
        case "nil": return nil
        default: break
        }
        let sz = Double(e["w:sz"] ?? "4") ?? 4
        let color = _borderColor(e["w:color"])
        var l = BorderLine(width: max(0.25, sz / 8), color: color, space: Double(e["w:space"] ?? "0") ?? 0)
        if let v = e["w:val"], v != "single" { l.style = v }
        return l
    }

    static func _paragraphProps(_ pPr: XNode, into style: inout RichParagraphStyle, direct: Bool = false) {
        // (A kind of justified the editor has one of — "distribute" spreads
        // the last line too, the Thai and kashida ones stretch otherwise —
        // is kept by name beside it.)
        if let jc = pPr.first("w:jc")?["w:val"] {
            style.eastAsian["w:jc"] = nil
            switch jc {
            case "center": style.alignment = .center
            case "right", "end": style.alignment = .right
            case "both": style.alignment = .justify
            case "left", "start": style.alignment = .left
            case "distribute", "thaiDistribute", "lowKashida", "mediumKashida", "highKashida":
                style.alignment = .justify
                style.eastAsian["w:jc"] = jc
            default: break
            }
        }
        if let ind = pPr.first("w:ind") {
            if let v = Double(ind["w:left"] ?? ind["w:start"] ?? "") { style.indentLeft = v / 20 }
            if let v = Double(ind["w:right"] ?? ind["w:end"] ?? "") { style.indentRight = v / 20 }
            if let v = Double(ind["w:firstLine"] ?? "") { style.firstLineIndent = v / 20 }
            if let v = Double(ind["w:hanging"] ?? "") { style.firstLineIndent = -v / 20 }
        }
        if let bidi = pPr.first("w:bidi") { style.rightToLeft = !_isOff(bidi) }
        // (A fill written with a leading "#" — `#ff00ff`, as lo-f17a56168c9e's Title
        // style has it — prints as that colour in Word.)
        if let shd = pPr.first("w:shd"), let raw = shd["w:fill"], case let hex = raw.hasPrefix("#") ? String(raw.dropFirst()) : raw,
           hex.lowercased() != "auto", hex.count == 6, let v = Int(hex, radix: 16) {
            style.fill = Color(argb: 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF)
            let extra = ["w:val", "w:color", "w:themeFill", "w:themeFillTint", "w:themeFillShade", "w:themeColor", "w:themeTint", "w:themeShade"]
                .compactMap { k in shd[k].map { " \(k)=\"\(_esc($0))\"" } }.joined()
            style.fillAttrs = hex.uppercased() + "#" + extra
        }
        else if let shd = pPr.first("w:shd"), let v = shd["w:val"], v != "nil" {
            // A pattern over no fill colour: kept for the save (drawn as no fill).
            style.fillAttrs = "auto#" + ["w:val", "w:color", "w:themeFill", "w:themeFillTint", "w:themeFillShade", "w:themeColor", "w:themeTint", "w:themeShade"]
                .compactMap { k in shd[k].map { " \(k)=\"\(_esc($0))\"" } }.joined()
        }
        if let c = pPr.first("w:contextualSpacing") { style.contextualSpacing = !_isOff(c) }
        if let frame = pPr.first("w:framePr") {
            // Over the style's frame, attribute by attribute: a standard's
            // cover title says only its height and x, and its style says
            // the page anchor, the width and the y — without those the
            // title sat at the top of the page, not in its box.
            if let under = style.frameXML, let inherited = XNode.parse(Data(under.replacingAll("<w:framePr ", with: "<w:framePr xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" ").utf8)) {
                let merged = XNode(name: "w:framePr", attrs: inherited.attrs.filter { !$0.key.hasPrefix("xmlns") }.merging(frame.attrs) { _, own in own })
                style.frameXML = PptxXML.serialize(merged)
            } else { style.frameXML = PptxXML.serialize(frame) }
            // Its place, for the layout (a drop cap's frame is not placed).
            if let xml = style.frameXML, frame["w:dropCap"] == nil,
               let node = XNode.parse(Data(xml.replacingAll("<w:framePr ", with: "<w:framePr xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" ").utf8)) {
                var f = ParagraphFrame()
                if let v = Double(node["w:x"] ?? "") { f.x = v / 20 }
                if let v = Double(node["w:y"] ?? "") { f.y = v / 20 }
                if let v = Double(node["w:w"] ?? ""), v > 0 { f.width = v / 20 }
                f.horizontalAnchor = node["w:hAnchor"] ?? "text"
                // (A frame that gives its height on the page and no
                // anchor is set from the margin — the schema's default:
                // zh-90e0cea8's cover's "山东省市场监督管理局 发布", y 15027
                // twips, stands at the page's foot in Word's print and
                // was in the flow under the title here.)
                f.verticalAnchor = node["w:vAnchor"] ?? (node["w:y"] != nil || node["w:yAlign"] != nil ? "margin" : "text")
                f.horizontalAlign = node["w:xAlign"]
                // (An y beside the alignment is the place: LibreOffice's
                // tdf157572_defaultVAnchor says "center" and y 10, and Word
                // sets its frame at the margin's top, 0.5pt down.)
                // (Zero is no place: tdf112287B's "bottom" with y 0 stays where
                // its text is, 97pt, and an alignment is set by the height
                // only where no y is given and the text goes round the frame —
                // the one shape seen; a style's wrap-auto frame, special_styles',
                // kept its old place.)
                let placed = (Double(node["w:y"] ?? "") ?? 0) != 0
                f.verticalAlign = placed ? nil : node["w:yAlign"]
                // (A style's frame of an exact height with no anchor of its own, aligned
                // on the margins and left to the default wrap: lo special_styles' "envelope
                // address", 396 by 99pt, hAnchor page, centred, "bottom" — the foot of the
                // text area in Word's print, the lines level with it set beside it.)
                let styled = node["w:vAnchor"] == nil && node["w:hRule"] == "exact" && (node["w:wrap"] ?? "auto") == "auto"
                    && ["top", "center", "bottom"].contains(node["w:yAlign"] ?? "")
                if node["w:y"] == nil, node["w:wrap"] == "around" || styled, let h = Double(node["w:h"] ?? ""), h > 0 { f.height = h / 20 }
                // (A frame set "inline" vertically, of no width or height of
                // its own, stays in the flow as a paragraph: zh-fe536967's
                // footer, over a style's framed 29pt box, is one, and Word
                // sets its page-number box from the footer's line, 21pt
                // above where ours took it out of the flow.)
                let inline = node["w:yAlign"] == "inline" && (Double(node["w:w"] ?? "") ?? 0) == 0 && node["w:hRule"] != "exact"
                style.frame = inline ? nil : f
            }
        }
        if let k = pPr.first("w:keepNext") { style.keepNext = !_isOff(k) }
        // (A style's own break before, too — and a paragraph's "off" over
        // it: zh-499adba6's Heading 2 says pageBreakBefore, and Word's print
        // opens page 23 with its "（一）權力、決策與影響力", where ours, which
        // read the break only from the paragraph's own properties, set it
        // at page 22's foot, and the book ran three pages short from there.)
        if let b = pPr.first("w:pageBreakBefore") { style.pageBreakBefore = !_isOff(b) }
        if let d = pPr.first("w:divId")?["w:val"] { style.divId = d }
        for tag in _eastAsianSwitches { if let n = pPr.first(tag) { style.eastAsian[tag] = _isOff(n) ? "0" : "1" } }
        if let v = pPr.first("w:textAlignment")?["w:val"] { style.eastAsian["w:textAlignment"] = v }
        for (element, attrs) in [("w:ind", _eastAsianIndents), ("w:spacing", _eastAsianSpacing)] {
            guard let n = pPr.first(element) else { continue }
            // (The first line's count, in or out, is one setting: a
            // paragraph's firstLineChars 0 under a style's hangingChars
            // 200 hangs nothing — zh-06c46ba9's division-of-work table,
            // whose rows stood two characters out of Word's.)
            if element == "w:ind", n["w:firstLineChars"] != nil || n["w:hangingChars"] != nil {
                style.eastAsian["w:firstLineChars"] = nil
                style.eastAsian["w:hangingChars"] = nil
            }
            // (Whether the paragraph's OWN indent writes the first line's twips and
            // its count together: Word for Windows takes the twips then — all 145
            // measured paragraphs — and takes the count where the twips stand alone
            // over a style's count (zh-76700e5f's firstLine 31680 over its style's
            // 200 characters starts the line 21pt in) or come from a style, which can
            // be stale (zh-efd9229a's style says 836 for 200 characters, 14pt runs
            // start 28pt in).)
            if element == "w:ind", n["w:firstLine"] != nil || n["w:hanging"] != nil || n["w:firstLineChars"] != nil || n["w:hangingChars"] != nil {
                let together = (n["w:firstLine"] != nil && n["w:firstLineChars"] != nil) || (n["w:hanging"] != nil && n["w:hangingChars"] != nil)
                // (Twips alone over a style's count stand too where they are within 1.5pt of
                // the count — layout checks that: zh-bfe04e2f's firstLine 482 under a style's
                // 200 characters of 12pt starts 24.12pt in Word's print, not the 24.00 counted.)
                style.eastAsian["w:indentStored"] = (together || n["w:firstLine"] != nil || n["w:hanging"] != nil) && direct ? "1" : nil
            }
            for a in attrs {
                guard let v = n[a], Int(v) != nil else { continue }
                // (A count of none, alone, over a first-line indent in twips that a style
                // states without a count, takes nothing off it in Word for Windows:
                // zh-60173bb6's numbered items, "w:firstLineChars=0" under Normal Indent's
                // 556, start 27.8pt in.)
                if DocxFormat.wordOnWindows, element == "w:ind", a == "w:firstLineChars", v == "0", n["w:firstLine"] == nil, n["w:hanging"] == nil,
                   n["w:hangingChars"] == nil, style.eastAsian["w:firstLineChars"] == nil, style.eastAsian["w:hangingChars"] == nil,
                   style.firstLineIndent > 0 {
                    RuleTrace.hit("word-first-line-count-of-none-keeps-the-styles-twips")
                    continue
                }
                style.eastAsian[a] = v
            }
        }
        if let k = pPr.first("w:keepLines") { style.keepLines = !_isOff(k) }
        if let w = pPr.first("w:widowControl") { style.widowControl = !_isOff(w) }
        if let tabs = pPr.first("w:tabs") {
            // Tab stops ADD to the ones inherited (a style's, under a
            // paragraph's): a stop at a position replaces the one there,
            // and "clear" takes one away.
            var stops = style.tabStops
            for t in tabs.all("w:tab") {
                guard let pos = Double(t["w:pos"] ?? ""), pos >= 0 else { continue }
                stops.removeAll { abs($0.position - pos / 20) < 0.026 }
                let a: TabStop.Alignment
                var raw: String? = nil
                switch t["w:val"] ?? "left" {
                case "center": a = .center
                case "right", "end": a = .right
                case "decimal": a = .decimal
                case "left", "start": a = .left
                case "num", "bar": a = .left; raw = t["w:val"]
                default: continue   // clear
                }
                var stop = TabStop(position: pos / 20, alignment: a)
                stop.rawKind = raw
                if let l = t["w:leader"], l != "none" { stop.leader = l }
                stops.append(stop)
            }
            style.tabStops = stops.sorted { $0.position < $1.position }
        }
        if let bdr = pPr.first("w:pBdr") {
            func line(_ name: String) -> BorderLine? { bdr.first(name).flatMap(_borderLine) }
            // (Per side: a pBdr naming only the top keeps the style's bottom;
            // 3ebc3ec5's "Intense Quote" lost its group's bottom rule.)
            let old = style.borders
            func side(_ name: String, _ prev: BorderLine?) -> BorderLine? { bdr.first(name) == nil ? prev : line(name) }
            let b = ParagraphBorders(top: side("w:top", old?.top), bottom: side("w:bottom", old?.bottom), left: side("w:left", old?.left), right: side("w:right", old?.right), between: side("w:between", old?.between))
            style.borders = b.isEmpty ? nil : b
            style.pBdrElement = true
        }
        if let sp = pPr.first("w:spacing") {
            if let v = Double(sp["w:before"] ?? "") { style.spaceBefore = v / 20 }
            if let v = Double(sp["w:after"] ?? "") { style.spaceAfter = v / 20 }
            func on(_ v: String?) -> Bool? { v.map { ["1", "true", "on"].contains($0) } }
            if let a = on(sp["w:beforeAutospacing"]) { style.spaceBeforeAuto = a }
            if let a = on(sp["w:afterAutospacing"]) { style.spaceAfterAuto = a }
            // ("At least 0" is a statement too — the line's natural height,
            // which a document on a line grid then does not snap; as single
            // spacing every paragraph of one sat 2.4pt lower.)
            if let v = Double(sp["w:line"] ?? "") { style.lineCollapsed = v == 0 && (sp["w:lineRule"] ?? "auto") == "auto" }
            if let v = Double(sp["w:line"] ?? ""), v > 0 || (v == 0 && sp["w:lineRule"] == "atLeast") {
                switch sp["w:lineRule"] ?? "auto" {
                case "exact":
                    style.lineHeightPoints = v / 20
                    style.lineHeightIsMinimum = false
                    style.exactBaselineAtAscent = Self._exactAtAscent
                case "atLeast":
                    // A minimum, however small: Word lays "at least 1pt"
                    // (Bug51170's atLeast 23 twips) out tighter than
                    // single-auto — the font's own height without the
                    // multiple — so it is kept as the minimum it is, over
                    // single lines, and written back as such.
                    style.lineHeightPoints = v / 20
                    style.lineHeightIsMinimum = true
                    style.lineSpacing = 1.0
                default:
                    // (A fractional w:line, Google Docs' 335.99999999999994, is read as the whole twips below it: 335 is 1.3958 lines, not 1.4;
                    // lab coverpitch, Arial 33 / 22 and Roboto 11 pitches 0.4% under 1.4 times single, all three.)
                    style.lineSpacing = (RichTextTheme.wordWindowsPages ? v.rounded(.towardZero) : v) / 240
                    style.lineHeightPoints = nil
                }
            }
        }
    }

    /// A horizontal `snapToChars` grid sets whole cells to a line: as many as the Normal size plus the
    /// grid's addition (`charSpace`) goes into the text width, spread evenly over it, so the cell is the
    /// width over that count. Word's print of f3550c7b/837e72c4 (451.3pt wide, Normal 11pt, charSpace 210)
    /// sets 40 cells of 11.28 for 10.5pt text; the addition that gives that cell is returned.
    static func _snapCellSpace(_ sect: XNode, normalSize: Double?) -> Double? {
        guard let grid = sect.first("w:docGrid"), grid["w:type"] == "snapToChars",
              !["tbRl", "tbRlV"].contains(sect.first("w:textDirection")?["w:val"] ?? ""),
              (Int(sect.first("w:cols")?["w:num"] ?? "") ?? 1) <= 1,
              let size = normalSize, size > 0, let sz = sect.first("w:pgSz"), let w = Double(sz["w:w"] ?? "") else { return nil }
        let mar = sect.first("w:pgMar")
        let left = Double(mar?["w:left"] ?? "1440") ?? 1440, right = Double(mar?["w:right"] ?? "1440") ?? 1440
        let gutter = max(0, Double(mar?["w:gutter"] ?? "0") ?? 0)
        let width = (w - left - right - gutter) / 20
        let n = ((width / (size + (Double(grid["w:charSpace"] ?? "") ?? 0) / 4096)).rounded(.down))
        guard n >= 1, width > 0 else { return nil }
        return width / n - size
    }

    /// What Word's "Formatted:" balloon says of a section's changed page margins (w:sectPrChange): only
    /// the margins and distances that differ, in inches to two places, e.g. `Left:  0.75", Bottom:  0.79"`.
    static func _sectionChangeSaid(_ sect: XNode, was old: XNode?) -> String {
        guard let now = sect.first("w:pgMar"), let was = old?.first("w:pgMar") else { return "" }
        var parts: [String] = []
        for (attr, label) in [("w:top", "Top"), ("w:left", "Left"), ("w:right", "Right"), ("w:bottom", "Bottom"),
                              ("w:header", "Header distance from edge"), ("w:footer", "Footer distance from edge")] {
            guard let a = Double(now[attr] ?? ""), a != Double(was[attr] ?? "") else { continue }
            let v = (a / 1440 * 100).rounded() / 100
            parts.append("\(label):  \(v == v.rounded() ? String(Int(v)) : (v * 10).rounded() == v * 10 ? String(v) + "0" : String(v))\"")
        }
        return parts.joined(separator: ", ")
    }

    /// A section's `w:cols`: the count, the gap, each unequal column's own width and gap, and the line between.
    static func _readColumns(_ cols: XNode, into setup: inout PageSetup) {
        if let n = Int(cols["w:num"] ?? ""), n > 1 { setup.columns = n }
        // (Unequal columns state their gaps on each w:col: zh-25c4de17's
        // two say 425 there and nothing on w:cols, and Word sets them
        // 21.25pt apart — Word's 36pt default made each 7.4pt narrower
        // and its questions wrap a line early.)
        if let space = Double(cols["w:space"] ?? cols.first("w:col")?["w:space"] ?? "") { setup.columnGap = space / 20 }
        // (Unequal columns keep each one's own width and gap: Word sets
        // 28abf02c's two at 288 and 225pt, from the section's own margin.)
        if setup.columns > 1, ["0", "false", "off"].contains(cols["w:equalWidth"] ?? "") {
            let own = cols.all("w:col")
            if own.count == setup.columns {
                setup.columnSpec = own.map { ColumnSpan(width: (Double($0["w:w"] ?? "") ?? 0) / 20, gap: (Double($0["w:space"] ?? "") ?? 0) / 20) }
            }
        }
        if let sep = cols["w:sep"] { setup.columnLine = !["0", "false", "off"].contains(sep) }
    }

    static func _pageSetup(_ sect: XNode, _ notes: _Shared? = nil, normalSize: Double? = nil) -> PageSetup? {
        guard let sz = sect.first("w:pgSz"), let w = Double(sz["w:w"] ?? ""), let h = Double(sz["w:h"] ?? "") else {
            return nil
        }
        var setup = PageSetup(width: w / 20, height: h / 20)
        switch sect.first("w:type")?["w:val"] {
        case "oddPage": setup.sectionStartParity = .odd
        case "evenPage": setup.sectionStartParity = .even
        default: break
        }
        setup.orientStated = sz["w:orient"] != nil
        if let t = sect.first("w:titlePg"), !_isOff(t) { setup.titlePage = true }
        if let v = sect.first("w:vAlign")?["w:val"], v == "center" || v == "bottom" || v == "both" { setup.verticalAlign = v }
        if let ln = sect.first("w:lnNumType") {
            var numbering = LineNumbering()
            numbering.countBy = max(1, Int(ln["w:countBy"] ?? "") ?? 1)
            numbering.start = (Int(ln["w:start"] ?? "") ?? 0) + 1   // zero-based in the file (lab/pg3)
            numbering.distance = Double(ln["w:distance"] ?? "").map { $0 / 20 }
            switch ln["w:restart"] {
            case "continuous": numbering.restart = .continuous
            case "newSection": numbering.restart = .newSection
            default: numbering.restart = .newPage
            }
            setup.lineNumbers = numbering
        }
        if let num = sect.first("w:pgNumType") {
            setup.pageNumberStart = Int(num["w:start"] ?? "")
            setup.pageNumberFormat = num["w:fmt"]
            setup.chapterStyle = Int(num["w:chapStyle"] ?? "")
            setup.chapterSeparator = num["w:chapSep"]
        }
        if let mar = sect.first("w:pgMar") {
            setup.marginTop = Double(mar["w:top"] ?? "1440").map { abs($0) / 20 } ?? 72
            setup.marginBottom = Double(mar["w:bottom"] ?? "1440").map { abs($0) / 20 } ?? 72
            setup.marginTopExact = (Double(mar["w:top"] ?? "") ?? 0) < 0
            setup.marginBottomExact = (Double(mar["w:bottom"] ?? "") ?? 0) < 0
            setup.marginLeft = Double(mar["w:left"] ?? mar["w:start"] ?? "1440").map { $0 / 20 } ?? 72
            // (The gutter, kept clear beside the left margin unless the
            // settings put it at the top.)
            if let g = Double(mar["w:gutter"] ?? ""), g > 0 { setup.gutter = g / 20 }
            setup.marginRight = Double(mar["w:right"] ?? mar["w:end"] ?? "1440").map { $0 / 20 } ?? 72
            // The header/footer distances: writing 0.49in into a file whose
            // top margin is 0.1in made Word warn that the margins were small.
            if let v = Double(mar["w:header"] ?? "") { setup.headerDistance = max(0, v) / 20 }
            if let v = Double(mar["w:footer"] ?? "") { setup.footerDistance = max(0, v) / 20 }
        }
        if let cols = sect.first("w:cols") { _readColumns(cols, into: &setup) }
        // (A right-to-left section sets its columns from the right: its first
        // column is the rightmost, lo-998868b6's "RTL 1".)
        if let bidi = sect.first("w:bidi"), bidi["w:val"] != "0", bidi["w:val"] != "false" {
            setup.bidiSection = true
            if setup.columns > 1 { setup.rtlColumns = true }
            // (A right-to-left section of one narrowed column, `w:equalWidth` 0 and a single `w:col`, sets that column
            // at the right margin: the text's left edge is the narrowing in from the left. xd bf53d2b7: the table
            // spans 73.3 to 530.7 in Word's print, with margins 31.5 and 90.)
            if RichTextTheme.wordWindowsPages, setup.columns == 1, let cols = sect.first("w:cols"),
               ["0", "false", "off"].contains(cols["w:equalWidth"] ?? ""), cols.all("w:col").count == 1,
               let tw = Double(cols.first("w:col")?["w:w"] ?? ""), tw / 20 > 20, tw / 20 < setup.contentWidth - 1 {
                setup.marginLeft += setup.contentWidth - tw / 20
            }
        }
        if let grid = sect.first("w:docGrid") {
            // (A top-to-bottom section's snapToChars grid also holds its columns to linePitch: dx2 4427518d's print steps 33.7 pt, 671 twips.)
            let verticalSection = ["tbRl", "tbRlV"].contains(sect.first("w:textDirection")?["w:val"] ?? "")
            if let type = grid["w:type"], type == "lines" || type == "linesAndChars" || type == "snapToChars", let pitch = Double(grid["w:linePitch"] ?? ""), pitch > 0 {
                setup.lineGridPitch = pitch / 20
            }
            if grid["w:type"] == "linesAndChars" || (grid["w:type"] == "snapToChars" && ["tbRl", "tbRlV"].contains(sect.first("w:textDirection")?["w:val"] ?? "")) {
                let space = Double(grid["w:charSpace"] ?? "") ?? 0
                setup.characterGridSpace = space != 0 ? space / 4096 : 1e-6
            }
            if let cell = _snapCellSpace(sect, normalSize: normalSize ?? 11) { setup.characterGridSpace = cell; setup.characterGridCellBase = normalSize ?? 11 }
        }
        if let notes { setup.headerWrapLeft = _headerWrapLeft(sect, setup, notes) }
        // (Text top to bottom: laid out in the turned page; see `PageSetup.vertical`.)
        if let d = sect.first("w:textDirection")?["w:val"], d == "tbRl" || d == "tbRlV" {
            setup = setup.transposed()
            setup.vertical = true
        }
        return setup
    }

    /// How far a header's picture that wraps the text and stands the page's height
    /// pushes the body in from the left margin, in points; 0 for none. Word sets the
    /// body's lines beside such a picture on every page (LibreOffice's tdf38575: a
    /// 83pt-wide, 848pt-tall wrapThrough picture at -75pt from the column, whose
    /// polygon ends at 21255 of 21600, has the body at 101.8, the margin at 85.1 and
    /// the picture's edge plus distR 16.7pt in).
    static func _headerWrapLeft(_ sect: XNode, _ setup: PageSetup, _ notes: _Shared) -> Double {
        guard let ref = sect.children.first(where: { $0.name == "w:headerReference" && ($0["w:type"] ?? "default") == "default" }),
              let rel = ref["r:id"].flatMap({ notes.rels[$0] }), !rel.external,
              let header = notes.part(_resolvePath("word", rel.target)).flatMap(XNode.parse) else { return 0 }
        let left = setup.marginLeft + setup.gutter
        for anchor in header.descendants("wp:anchor") {
            guard let wrap = anchor.children.first(where: { ["wp:wrapSquare", "wp:wrapTight", "wp:wrapThrough"].contains($0.name) }),
                  let ext = anchor.first("wp:extent"), let cx = Double(ext["cx"] ?? ""), let cy = Double(ext["cy"] ?? ""),
                  let ph = anchor.first("wp:positionH"), let pv = anchor.first("wp:positionV"),
                  let ox = Double(ph.first("wp:posOffset")?.text ?? ""), let oy = Double(pv.first("wp:posOffset")?.text ?? "")
            else { continue }
            let emu = 12700.0
            let baseX: Double
            switch ph["relativeFrom"] ?? "" {
            case "page", "leftMargin": baseX = 0
            case "column", "margin": baseX = left
            default: continue
            }
            let baseY: Double
            switch pv["relativeFrom"] ?? "" {
            case "page": baseY = 0
            case "paragraph": baseY = setup.headerDistance
            case "margin": baseY = setup.marginTop
            default: continue
            }
            let x0 = baseX + ox / emu, y0 = baseY + oy / emu, w = cx / emu, h = cy / emu
            // (It has to stand the whole text area's height, and start at or before the margin.)
            guard y0 <= setup.marginTop + 1, y0 + h >= setup.height - setup.marginBottom - 1, x0 <= left + 1 else { continue }
            var reach = w
            if let polygon = wrap.first("wp:wrapPolygon") {
                let xs = ([polygon.first("wp:start")] + polygon.all("wp:lineTo").map { Optional($0) }).compactMap { $0 }.compactMap { Double($0["x"] ?? "") }
                if let maxX = xs.max() { reach = w * min(max(maxX, 0), 21600) / 21600 }
            }
            let inset = x0 + reach + (Double(anchor["distR"] ?? "") ?? 0) / emu - left
            if inset > 0, inset < setup.contentWidth / 2 { return inset }
        }
        return 0
    }

    struct _Built {
        var paragraph: RichParagraph
        var pageBreakAfter: Bool
        /// That break is a `w:br` character (not a section's), in a run
        /// with these properties.
        var breakCharacter = false
        var breakRPr: String? = nil
        var breakColumn = false   // ... and a column break
        /// The section this paragraph ends is followed by a continuous one with other top or
        /// bottom margins: a page break ending the paragraph stays (see `sectionsOwn`).
        var sectionMarginsChange = false
    }

    /// One w:p can become several paragraphs (a page break inside it).
    /// What one read shares across its paragraphs: which note parts the
    /// file has and the running numbers Word would show for their marks,
    /// the document's relationships, the namespaces its root declares, and
    /// the parts kept verbatim for objects the editor cannot show.
    final class _Shared {
        let footnotes: Bool, endnotes: Bool
        /// The lists' levels as the file defines them, by `w:numId`.
        var listFormats: [String: [Int: ListLevelFormat]] = [:]
        /// The document's theme faces, for text the reader builds after the parts were read (a SmartArt's).
        var themeFonts: ThemeFonts? = nil
        var seenFootnotes = 0, seenEndnotes = 0
        /// The number the first note takes (`w:numStart`), and the first after each restart.
        var footnoteStart = 1, endnoteStart = 1
        /// Footnote ids that open a section whose footnotePr restarts the numbering (numRestart eachSect).
        var footnoteRestarts: Set<Int> = []
        /// The number each footnote's mark was given in the body, by id;
        /// and, while a note's own text is read, its number for its
        /// `w:footnoteRef`.
        var footnoteNumbers: [Int: Int] = [:], endnoteNumbers: [Int: Int] = [:]
        // (Notes whose mark is the author's own text, customMarkFollows: they take no number but are set all the same.)
        var customFootnotes: Set<Int> = [], customEndnotes: Set<Int> = []
        var currentNote: Int? = nil
        /// An endnote's own mark, in its numbering's form ("i").
        var currentNoteLabel: String? = nil
        var endnoteFormat = "lowerRoman", footnoteFormat = "decimal"
        func label(_ n: Int, footnote: Bool) -> String { DocxFormat.noteLabel(n, format: footnote ? footnoteFormat : endnoteFormat) }
        var rels: [String: KeptRel]
        /// Reading a header or footer part: its page fields stay fields
        /// (the layout fills them for each page).
        var inHeaderFooter = false
        /// Normal's ascii face is its complex face (a Simplified Arabic document): an rtl flag on digits then changes no face.
        var normalAsciiIsCs = false
        /// Reading a text box's paragraphs (a box inside a box is not read).
        var inTextBox = false
        /// The document's own paragraph base while a paragraph inside a table
        /// cell is read: a text box anchored there takes the document's
        /// defaults, not the cell's.
        var cellBoxBase: RichParagraphStyle? = nil
        /// The cell's run base takes its size from the table's style
        /// (`tableSizes`): a paragraph whose own style states one keeps that.
        var cellSizeFromTable = false
        /// The cell's run base's other properties taken from the table's
        /// style (`_takeTableChar`), which a paragraph style stating its own
        /// takes back.
        var cellCharFromTable = Set<String>()
        /// A text box whose text holds a table, by its attachment's id:
        /// its `w:txbxContent`, for the body's reader to read again with
        /// its tables (this reader sets paragraphs only).
        var boxTables: [String: XNode] = [:]
        /// A group's text boxes that hold a table, by its attachment's id, then
        /// by the box's part number: its `w:txbxContent` and the shifts that
        /// place its paragraphs in the group (left, right, inset right).
        var boxPartTables: [String: [Int: (content: XNode, left: Double, right: Double, inset: Double)]] = [:]
        /// The VML shape types read so far (`v:shapetype`): Word writes
        /// each once, where it is first used.
        var shapeTypes: [XNode] = []
        var fieldShown = false   // the innermost field's result has text
        let rootNS: [String: String]
        let part: (String) -> Data?
        let contentType: (String) -> String?
        var kept: [String: Data]
        var keptTypes: [String: String] = [:]
        /// Comment ranges open at this point of the walk (they cross
        /// paragraphs).
        var openComments: [String] = []
        /// Bookmarks started since the last paragraph was built: they go
        /// to the next one.
        var pendingBookmarks: [String] = []
        var pendingBookmarkMarkers: [RichBookmarkMarker] = []
        var controlCount = 0
        /// The names (lower-cased) of the bookmarks the body defines, and the
        /// page references already answered "Error! Bookmark not defined."
        /// (one answer per field, however many runs its old result was in).
        var bookmarkNames: Set<String> = []
        var missingReferenceShown: Set<Int> = []
        /// The fields open at this point of the walk, innermost last (a
        /// contents field spans paragraphs and holds a page reference per
        /// line): each one's instruction, whether its result has begun,
        /// and its number in the document (`CharStyle.fieldResult`).
        var fields: [(instr: String, result: Bool, id: Int, properties: [String: String])] = []
        /// The look of each field's code (its first instruction run), by id.
        var fieldCodeStyle: [Int: CharStyle] = [:]
        var fieldLastCodeStyle: [Int: CharStyle] = [:]
        /// The page fields (PAGE, NUMPAGES) that closed inside the outermost field still open.
        var nestedPageFields: Set<String> = []
        var lastTextFamily: String? = nil   // the face of the last plain (non-field) text run, for an eq ring that names none
        var fieldCount = 0
        var contentsStart: String? = nil   // W-FD-2: the TOC instruction opened in the paragraph being read
        var contentsEnd = false
        /// Every style's name, lowercased, and the fields whose STYLEREF
        /// error has been written: a STYLEREF naming no style prints Word's
        /// error, not the result it was saved with.
        var styleNames = Set<String>()
        var styleDisplayNames: [String: String] = [:]
        var styleRefShown = Set<Int>()
        /// The reference fields whose result is already Word's error text (`REF` to a name not in the file).
        var referenceErrors = Set<Int>()
        var keptBookmarkText = ""
        /// Whether the code of the field being read was reformatted under
        /// change tracking: its result's first run says so
        /// (`CharStyle.fieldCodeChanged`).
        var fieldCodeChanged = false
        /// Every comment id whose range has been opened (a reference run
        /// for one of these ends a range; any other is a point comment).
        var seenComments = Set<String>()
        /// Counts the comment references met: two deletions with one between them are two balloons in Word's print.
        var commentReferences = 0
        /// Comments some text of the body carries: a range that covers an
        /// anchored picture alone carries none, and is anchored at its end.
        var carriedComments = Set<String>()
        /// The comment ids some run carries (a range with text in it).
        var anchoredComments = Set<String>()
        /// Character styles (w:rStyle on a run), each as its chain of run
        /// properties from the root style down, applied under the run's
        /// own. drawing.docx's dates wear a Tahoma 7.5pt shaded style and
        /// its headings a bold 14pt one; both came back as plain text.
        var charStyleChains: [String: [XNode]] = [:]
        /// `w:splitPgBreakAndParaMark` before 2013's layout: the mark of a
        /// paragraph that ends in a page break goes to the next page.
        var marksFollowBreaks = false
        var compatMode = 12
        /// The mark of a paragraph that ends in a COLUMN break stands at the
        /// top of the next column, in 2010's layout and 2013's alike (lab
        /// cb1 and cb2 in Word for Windows; LibreOffice's tdf165492: Word's
        /// second column opens with that empty line, ours with the table).
        var columnMarksFollow = true
        /// Some section of the body sets its text in two columns or more:
        /// there a column break in the middle of a paragraph is a break.
        var hasColumns = false
        init(kept: [String: Data], rels: [String: KeptRel], rootNS: [String: String],
             part: @escaping (String) -> Data?, contentType: @escaping (String) -> String?) {
            self.kept = kept
            self.footnotes = kept["word/footnotes.xml"] != nil
            self.endnotes = kept["word/endnotes.xml"] != nil
            self.rels = rels; self.rootNS = rootNS; self.part = part; self.contentType = contentType
            for name in kept.keys { if let t = contentType(name) { keptTypes[name] = t } }
        }
        func next(footnote: Bool, id: Int = -1) -> Int {
            if footnote { if footnoteRestarts.contains(id) { seenFootnotes = 0 }; seenFootnotes += 1; return seenFootnotes + footnoteStart - 1 }
            seenEndnotes += 1; return seenEndnotes + endnoteStart - 1
        }
        /// Keeps the part at `path` and, through its rels, every part it reaches.
        func keep(_ path: String) {
            guard kept[path] == nil, !DocxFormat._ownParts.contains(path), let data = part(path) else { return }
            kept[path] = data
            if let t = contentType(path) { keptTypes[path] = t }
            var comps = path.split(separator: "/").map(String.init)
            guard let file = comps.popLast() else { return }
            let dir = comps.joined(separator: "/")
            let relsPath = (dir.isEmpty ? "" : dir + "/") + "_rels/" + file + ".rels"
            guard let relsData = part(relsPath), let node = XNode.parse(relsData) else { return }
            kept[relsPath] = relsData
            for r in node.relationships() where r["TargetMode"] != "External" {
                if let target = r["Target"] { keep(DocxFormat._resolvePath(dir, target)) }
            }
        }
    }

    struct _Margins {
        var top: Double? = nil, left: Double? = nil, bottom: Double? = nil, right: Double? = nil
        static let word = _Margins(top: 0, left: 5.4, bottom: 0, right: 5.4)
        /// Self where set, `other` where not.
        func under(_ other: _Margins) -> _Margins {
            _Margins(top: top ?? other.top, left: left ?? other.left, bottom: bottom ?? other.bottom, right: right ?? other.right)
        }
    }

    struct _Borders {
        var on: Bool
        var color: Color?
        var width: Double? = nil
        var style: String? = nil   // w:val when drawn and not "single"
    }

    /// A table style's conditional formatting, the parts the editor shows.
    struct _Cond {
        /// The style's own cell vertical alignment (`w:tcPr/w:vAlign`, centre or bottom).
        var cellVAlign: String? = nil
        /// The firstRow part's own cell vertical alignment (acd729's pandoc "Table").
        var headerVAlign: String? = nil
        var headerChar: CharStyle? = nil
        var firstColChar: CharStyle? = nil
        /// Every conditional part's fill, by `w:tblStylePr` type (first one in the style chain wins).
        var fills: [String: Color] = [:]
        var rowBandSize: Int? = nil
        var colBandSize: Int? = nil
        var lastRowChar: CharStyle? = nil
        var lastColChar: CharStyle? = nil
        /// The header row's cell borders (`firstRow`'s `w:tcBorders`).
        var headerBorders: XNode? = nil
        /// Whether the style's first row repeats on every page
        /// (`firstRow`'s `w:trPr` `w:tblHeader`).
        var headerRepeats = false
    }

    /// Whether `data` is a picture the image codec reads: PNG, JPEG,
    /// GIF or BMP by its signature.
    static func _isRasterImage(_ data: Data) -> Bool {
        let b = [UInt8](data.prefix(4))
        guard b.count == 4 else { return false }
        return b == [0x89, 0x50, 0x4E, 0x47] || (b[0] == 0xFF && b[1] == 0xD8) || b[0 ..< 3] == [0x47, 0x49, 0x46] || b[0 ..< 2] == [0x42, 0x4D]
    }

    /// `w:tblBorders` of a table or table style (or `w:tcBorders` of a
    /// cell): nil when it says nothing, off when every edge it lists is
    /// nil/none, else on, with the first drawn edge's colour (nil for
    /// auto).
    static func _borders(_ pr: XNode?, _ tag: String, lost: Set<String> = []) -> _Borders? {
        guard let b = pr?.first(tag), !b.children.isEmpty else { return nil }
        let drawn = b.children.filter { !["nil", "none"].contains($0["w:val"] ?? "nil") }
        guard let first = drawn.first else { return _Borders(on: false, color: nil) }
        // An edge the neighbour's edge beats names no colour for the cell.
        let kept = drawn.filter { !lost.contains($0.name) }
        let color = _borderColor(kept.first(where: { ($0["w:color"] ?? "auto").lowercased() != "auto" })?["w:color"] ?? kept.first?["w:color"])
        let width = Double(first["w:sz"] ?? "").map { max(0.25, $0 / 8) }
        let style = first["w:val"].flatMap { $0 == "single" ? nil : $0 }
        return _Borders(on: true, color: color, width: width, style: style)
    }

    /// Edges of a table's cells that lose to the neighbour across the shared
    /// line. Word draws one line there: the heavier one, and at equal weight
    /// the darker colour (auto counts as black). zh-604e21e5's cells name a
    /// white bottom edge over a row whose top is auto, and Word's print
    /// rules them black. Keyed by cell identity; the value holds the
    /// element names that lose. Neighbours are matched by position in the
    /// row, so spanned/merged cells are left alone.
    static func _lostCellEdges(rows: [[XNode]]) -> [ObjectIdentifier: Set<String>] {
        func rank(_ e: XNode) -> (Double, Double)? {
            guard !["nil", "none"].contains(e["w:val"] ?? "nil") else { return nil }
            let w = Double(e["w:sz"] ?? "") ?? 0
            var lum = 0.0
            if let k = _borderColor(e["w:color"]) {
                let v = Int(k.value)
                lum = 0.299 * Double((v >> 16) & 255) + 0.587 * Double((v >> 8) & 255) + 0.114 * Double(v & 255)
            }
            return (w, -lum)   // larger wins: heavier, then darker
        }
        func edge(_ cell: XNode, _ names: [String]) -> XNode? {
            guard let b = cell.first("w:tcPr")?.first("w:tcBorders") else { return nil }
            for n in names { if let e = b.first(n) { return e } }
            return nil
        }
        func span(_ cell: XNode) -> Int { max(1, Int(cell.first("w:tcPr")?.first("w:gridSpan")?["w:val"] ?? "") ?? 1) }
        func continues(_ cell: XNode) -> Bool {
            guard let m = cell.first("w:tcPr")?.first("w:vMerge") else { return false }
            return (m["w:val"] ?? "continue") != "restart"
        }
        var lost: [ObjectIdentifier: Set<String>] = [:]
        func duel(_ a: XNode, _ ea: XNode?, _ b: XNode, _ eb: XNode?) {
            guard let ea, let eb, let ra = rank(ea), let rb = rank(eb), ra != rb else { return }
            if ra < rb { lost[ObjectIdentifier(a), default: []].insert(ea.name) }
            else { lost[ObjectIdentifier(b), default: []].insert(eb.name) }
        }
        // Each cell by the grid column it starts at, with its span.
        let grid: [[(cell: XNode, col: Int, span: Int)]] = rows.map { row in
            var c = 0
            return row.map { cell in let sp = span(cell); defer { c += sp }; return (cell, c, sp) }
        }
        for (ri, row) in grid.enumerated() {
            for (ci, g) in row.enumerated() {
                if ci + 1 < row.count {
                    duel(g.cell, edge(g.cell, ["w:right", "w:end"]), row[ci + 1].cell, edge(row[ci + 1].cell, ["w:left", "w:start"]))
                }
                if ri + 1 < grid.count {
                  // (Every cell under any part of this one's width shares the line.)
                  for below in grid[ri + 1] where below.col < g.col + g.span && g.col < below.col + below.span {
                    if continues(below.cell) {
                        // Inside a merged block the line is not drawn: neither
                        // side names a colour for it (zh-604e21e5's merged
                        // column carries a white bottom on every row).
                        if let e = edge(g.cell, ["w:bottom"]) { lost[ObjectIdentifier(g.cell), default: []].insert(e.name) }
                        if let e = edge(below.cell, ["w:top"]) { lost[ObjectIdentifier(below.cell), default: []].insert(e.name) }
                    } else {
                        duel(g.cell, edge(g.cell, ["w:bottom"]), below.cell, edge(below.cell, ["w:top"]))
                    }
                  }
                }
            }
        }
        return lost
    }

    /// The sides a `w:tblBorders`/`w:tcBorders` names: false for nil or
    /// none, true for a drawn line, nil for a side it does not mention.
    static func _edges(_ pr: XNode?, _ tag: String) -> BorderEdges? {
        guard let b = pr?.first(tag) else { return nil }
        func side(_ name: String) -> Bool? {
            guard let e = b.first(name) else { return nil }
            return !["nil", "none"].contains(e["w:val"] ?? "nil")
        }
        // LibreOffice spells the sides w:start/w:end.
        let e = BorderEdges(top: side("w:top"), left: side("w:left") ?? side("w:start"), bottom: side("w:bottom"),
                            right: side("w:right") ?? side("w:end"), insideH: side("w:insideH"), insideV: side("w:insideV"))
        return e.isEmpty ? nil : e
    }

    /// True when the table's own `w:tblCellMar` states both left (or start) and right (or end) as 0.
    static func _tableZeroesSideMargins(_ node: XNode) -> Bool {
        guard let m = node.first("w:tblPr")?.first("w:tblCellMar") else { return false }
        func z(_ a: String, _ b: String) -> Bool {
            guard let e = m.first(a) ?? m.first(b) else { return false }
            return (Double(e["w:w"] ?? "") ?? 1) == 0
        }
        return z("w:left", "w:start") && z("w:right", "w:end")
    }

    /// `w:tblCellMar` of a table or table style (or a cell's `w:tcMar`),
    /// in points, dxa sides only.
    static func _cellMargins(_ pr: XNode?, _ tag: String = "w:tblCellMar") -> _Margins {
        guard let m = pr?.first(tag) else { return _Margins() }
        func side(_ names: [String]) -> Double? {
            for n in names {
                if let e = m.first(n), (e["w:type"] ?? "dxa") == "dxa", let w = Double(e["w:w"] ?? "") { return w / 20 }
            }
            return nil
        }
        return _Margins(top: side(["w:top"]), left: side(["w:left", "w:start"]), bottom: side(["w:bottom"]), right: side(["w:right", "w:end"]))
    }

    /// The cell margins of the DEFAULT table style. Word ignores a default style's
    /// zero left and right (lab fitedge c00-c05, Windows prints: a table whose
    /// style is the default one with margins 0 is set out by 5.4 pt all the
    /// same, in compat 14 and 15, schema order or not); a non-default style's
    /// zero is honoured (zh-dc9cfa34, zh-147bdae0).
    /// A table style is the default one when `w:default` is on: "1" or "true" (an exporter's spelling; 8f1703b9
    /// stated "true", lost Normal Table's 5.4pt margins, and its tables overflowed the page).
    static func _isDefaultTableStyle(_ style: XNode) -> Bool {
        let v = style["w:default"]
        return v == "1" || v == "true" || v == "on"
    }

    static func _defaultStyleMargins(_ style: XNode) -> _Margins {
        let m = _cellMargins(style.first("w:tblPr"))
        if m.left == 0 && m.right == 0 {
            RuleTrace.hit("default-table-style-zero-margin-ignored")
            return _Margins()
        }
        return m
    }

    /// `target` relative to the directory `base` ("word/charts" + "../media/x.png").
    static func _resolvePath(_ base: String, _ target: String) -> String {
        if target.hasPrefix("/") { return String(target.dropFirst()) }
        var comps = base.split(separator: "/").map(String.init)
        for c in target.split(separator: "/") {
            if c == ".." { _ = comps.popLast() } else if c != "." { comps.append(String(c)) }
        }
        return comps.joined(separator: "/")
    }

    /// "123.4pt" / "2in" / "5cm" as points.
    static func _length(_ raw: String) -> Double? {
        let s = raw.trimmingWhitespace()
        let units: [(String, Double)] = [("pt", 1), ("in", 72), ("cm", 72 / 2.54), ("mm", 72 / 25.4), ("px", 0.75)]
        for (u, k) in units where s.hasSuffix(u) { return Double(s.dropLast(u.count)).map { $0 * k } }
        return Double(s)
    }

    /// Parts the editor does not model but the file had — Word's footnotes
    /// and endnotes, each with its rels and whatever those reach (metric
    /// picture in a note) — kept verbatim so a save keeps the notes the
    /// body still references.
    static func _keptParts(_ entries: [ZipEntry], _ part: (String) -> Data?) -> [String: Data] {
        var kept: [String: Data] = [:]
        // Only a part that parses is kept: a damaged one would make the
        // saved file as unopenable as the original.
        for e in entries where e.name.hasPrefix("word/theme/") && e.name.hasSuffix(".xml") && _wellFormed(e.data) {
            kept[e.name] = e.data
            // (With its rels and the pictures they name: a theme's picture fill names one by r:embed, and saved
            // without them the theme named an id with no relationship.)
            let file = String(e.name.dropFirst("word/theme/".count))
            guard let rels = part("word/theme/_rels/\(file).rels"), let node = XNode.parse(rels) else { continue }
            kept["word/theme/_rels/\(file).rels"] = rels
            for r in node.relationships() where r["TargetMode"] != "External" {
                guard let target = r["Target"] else { continue }
                let path = _resolvePath("word/theme", target)
                if let d = part(path), !_ownParts.contains(path) { kept[path] = d }
            }
        }
        // The legacy copy of the styles (Word 2010's stylesWithEffects) and the glossary document
        // (the user's Quick Parts and building blocks, with its own styles, settings, fonts and rels):
        // parts we do not model must never vanish on a save.
        for e in entries where e.name == "word/stylesWithEffects.xml" || e.name.hasPrefix("word/glossary/") {
            if e.name.hasSuffix("/") { continue }
            let text = e.name.hasSuffix(".xml") || e.name.hasSuffix(".rels")
            if !text || _wellFormed(e.data) { kept[e.name] = e.data }
        }
        // The web settings: the margins of the HTML blocks paragraphs name
        // by w:divId (drawing.docx's last banner sits 4.5pt lower for one).
        // Kept only for a document that names one: the part says nothing
        // else a page shows.
        if let web = part("word/webSettings.xml"), _wellFormed(web) {
            kept["word/webSettings.xml"] = web
        }
        // The package's own properties and the custom XML items (data bound
        // to content controls, bibliography sources), with their rels and
        // item properties: nothing here is shown, and a save must not drop it.
        for e in entries where (e.name.hasPrefix("docProps/") || e.name.hasPrefix("customXml/")) && !e.name.hasSuffix("/") {
            let text = e.name.hasSuffix(".xml") || e.name.hasSuffix(".rels")
            if !text || _wellFormed(e.data) { kept[e.name] = e.data }
        }
        // (And the font table: what Word substitutes for a face the machine
        // lacks is chosen by the family, pitch and alternate name stated
        // there, and a Chinese document names faces few machines have.)
        // (And the settings: the zoom, the colour map, the revision ids, the math and shape defaults, the notes' settings;
        // a save changes only what the app itself sets in it.)
        for name in ["footnotes", "endnotes", "fontTable", "settings"] {
            guard let data = part("word/\(name).xml"), _wellFormed(data) else { continue }
            kept["word/\(name).xml"] = data
            guard let rels = part("word/_rels/\(name).xml.rels") else { continue }
            kept["word/_rels/\(name).xml.rels"] = rels
            guard let node = XNode.parse(rels) else { continue }
            for r in node.relationships() where r["TargetMode"] != "External" {
                guard let target = r["Target"] else { continue }
                let path = target.hasPrefix("/") ? String(target.dropFirst()) : "word/" + target
                if let d = part(path), !_ownParts.contains(path) { kept[path] = d }
            }
        }
        // The numbering's own rels and what they name (a picture bullet's image): the numbering part is written back
        // as read, with its r:id, and an r:id with no rel behind it makes Word refuse the whole file.
        if let rels = part("word/_rels/numbering.xml.rels"), let node = XNode.parse(rels) {
            kept["word/_rels/numbering.xml.rels"] = rels
            for r in node.relationships() where r["TargetMode"] != "External" {
                guard let target = r["Target"] else { continue }
                let path = target.hasPrefix("/") ? String(target.dropFirst()) : "word/" + target
                if let d = part(path), !_ownParts.contains(path) { kept[path] = d }
            }
        }
        return kept
    }

    /// The theme's faces, for the theme font references runs and styles
    /// make: each of major and minor, its Latin face and its East Asian
    /// one. A theme's `a:ea` is usually empty, and Word then takes the
    /// face the theme lists for the document's East Asian script
    /// (`w:themeFontLang w:eastAsia`, zh-CN → `Hans`): zh-a4b0f6ea's page
    /// numbers say `asciiTheme="majorEastAsia"`, which is 宋体 there —
    /// Word's print sets their digits in SimSun — where ours took the
    /// major Latin face.
    struct ThemeFonts {
        var major: String?
        var minor: String?
        var majorEastAsia: String?
        var minorEastAsia: String?
        /// The complex-script face: the theme's `a:cs`, else its Arabic one
        /// (merge_hidden_redline's `asciiTheme="minorBidi"` is Arial in
        /// Word's print, where ours took Normal's Calibri).
        var majorBidi: String?
        var minorBidi: String?
        var isEmpty: Bool { major == nil && minor == nil && majorEastAsia == nil && minorEastAsia == nil }
        /// The face a reference (`minorHAnsi`, `majorEastAsia`, …) names.
        func face(_ ref: String) -> String? {
            let major = ref.hasPrefix("major")
            if ref.hasSuffix("EastAsia") { return major ? majorEastAsia : minorEastAsia }
            if ref.hasSuffix("Bidi") { return major ? majorBidi : minorBidi }
            return major ? self.major : minor
        }
    }

    static func _themeFonts(_ entries: [ZipEntry]) -> ThemeFonts {
        // (A package with no theme part at all: Word takes its current default theme, whose minor Latin face is Aptos
        // (sa2 be63fe36: docDefaults say minorHAnsi, no theme part; Word prints Aptos, we set it in Calibri, 9.5% narrow).)
        if !entries.contains(where: { $0.name.hasPrefix("word/theme/") }) { return ThemeFonts(minor: "Aptos") }
        guard let e = entries.first(where: { $0.name.hasPrefix("word/theme/") && $0.name.hasSuffix(".xml") }),
              let root = XNode.parse(e.data), let scheme = root.descendant("a:fontScheme") else { return ThemeFonts() }
        let lang = entries.first(where: { $0.name == "word/settings.xml" }).flatMap { XNode.parse($0.data) }?
            .first("w:themeFontLang")?["w:eastAsia"]?.lowercased()
        var script: String? = switch lang {
        case "zh-cn", "zh-sg": "Hans"
        case "zh-tw", "zh-hk", "zh-mo": "Hant"
        case "ja-jp": "Jpan"
        case "ko-kr": "Hang"
        default: nil
        }
        // (A theme face for "ja-JP" is taken for the text's own script where the text is Korean: dx2's
        // ed5bf93a (themeFontLang ja-JP, Hangul only, 585 East Asian theme references) prints its Hangul
        // in 맑은 고딕, the theme's Hang face, where we set it in the Jpan one's name's stand-in.)
        if script == "Jpan", let body = entries.first(where: { $0.name == "word/document.xml" }) {
            var hangul = 0, kana = 0
            for u in String(decoding: body.data, as: UTF8.self).unicodeScalars {
                if u.value >= 0xAC00 && u.value <= 0xD7A3 { hangul += 1 } else if u.value >= 0x3040 && u.value <= 0x30FF { kana += 1 }
            }
            if hangul > 0, kana == 0 { script = "Hang" }
        }
        // (A document whose theme language (`w:themeFontLang w:val`) is Vietnamese takes the theme's face for the Viet script as its
        // Latin theme face: xs 2dd064d7 and d631aa7d (vi-VN, theme Cambria/Calibri, Viet faces Times New Roman/Arial) print their
        // majorHAnsi runs in Times New Roman and their minorHAnsi ones in Arial.)
        let latinViet = (entries.first(where: { $0.name == "word/settings.xml" }).flatMap { XNode.parse($0.data) }?
            .first("w:themeFontLang")?["w:val"]?.lowercased() ?? "").hasPrefix("vi")
        func latin(_ name: String) -> String? {
            if latinViet, let f = scheme.first(name)?.all("a:font").first(where: { $0["script"] == "Viet" })?["typeface"], !f.isEmpty { return f }
            let f = scheme.first(name)?.first("a:latin")?["typeface"] ?? ""
            return f.isEmpty ? nil : f
        }
        func eastAsian(_ name: String) -> String? {
            guard let font = scheme.first(name) else { return nil }
            if let f = font.first("a:ea")?["typeface"], !f.isEmpty { return f }
            guard let script else { return nil }
            let f = font.all("a:font").first { $0["script"] == script }?["typeface"] ?? ""
            return f.isEmpty ? nil : f
        }
        // (A document whose complex-script language (`w:themeFontLang w:bidi`) is an Indic one takes the theme's face for that
        // script — Shruti for gu-IN, Mangal for hi-IN, Raavi, Gautami, Vrinda — where ar-SA and the rest take the Arabic one:
        // dx2's gu-IN table cells print in Shruti, where the same markup with bidi ar-SA prints in Nirmala UI.)
        let bidiScript: String? = switch entries.first(where: { $0.name == "word/settings.xml" }).flatMap({ XNode.parse($0.data) })?
            .first("w:themeFontLang")?["w:bidi"]?.lowercased().split(separator: "-").first.map(String.init) {
        case "hi", "mr", "sa", "ne", "kok": "Deva"
        case "gu": "Gujr"
        case "pa": "Guru"
        case "te": "Telu"
        case "bn": "Beng"
        case "th": "Thai"   // (xd 4d02d27f: bidi th-TH, majorBidi runs print in the theme's Thai face, Angsana New)
        default: nil
        }
        var hebrewOnly = false   // Hebrew letters in the body and no Arabic ones (the Hebrew-glyph coverage below only helps Hebrew)
        if let body = entries.first(where: { $0.name == "word/document.xml" }) {
            var heb = 0, arab = 0
            for u in String(decoding: body.data, as: UTF8.self).unicodeScalars {
                if u.value >= 0x5D0 && u.value <= 0x5EA { heb += 1 } else if u.value >= 0x600 && u.value <= 0x6FF { arab += 1 }
            }
            hebrewOnly = heb > 0 && arab == 0
        }
        let themeLang = entries.first(where: { $0.name == "word/settings.xml" }).flatMap { XNode.parse($0.data) }?.first("w:themeFontLang")
        let themeLangPresent = themeLang != nil
        let themeLangHasBidi = !(themeLang?["w:bidi"] ?? "").isEmpty
        func complex(_ name: String) -> String? {
            guard let font = scheme.first(name) else { return nil }
            if let f = font.first("a:cs")?["typeface"], !f.isEmpty { return f }
            if let bidiScript, let f = font.all("a:font").first(where: { $0["script"] == bidiScript })?["typeface"], !f.isEmpty { return f }
            // (A theme whose complex-script face is empty, in a file whose w:themeFontLang names no w:bidi language,
            // prints Hebrew and Arabic in Times New Roman, not the theme's Arabic Arial: xb heb-944544, heb-bae91d and
            // ara-a6e54c, all with themeFontLang val/eastAsia only; the same theme with bidi ar-SA or he-IL prints Arial.)
            // (Narrowed by the theme's minor Latin face, not the language: a face with Hebrew glyphs (Calibri) is drawn for
            // Hebrew itself, one without (Cambria) falls to Times New Roman. Lab e040af-face: en-US with minor Calibri
            // draws Calibri, de-DE with the minor changed to Cambria draws Times New Roman.)
            let hebrewFaces: Set<String> = ["calibri", "arial", "times new roman", "tahoma", "segoe ui", "verdana", "consolas", "courier new", "trebuchet ms", "cambria math", "calibri light"]
            let minorHasHebrew = hebrewOnly && hebrewFaces.contains((latin("a:minorFont") ?? "").lowercased())
            if themeLangPresent && !themeLangHasBidi && !minorHasHebrew { return "Times New Roman" }
            let f = font.all("a:font").first { $0["script"] == "Arab" }?["typeface"] ?? ""
            return f.isEmpty ? nil : f
        }
        return ThemeFonts(major: latin("a:majorFont"), minor: latin("a:minorFont"),
                          majorEastAsia: eastAsian("a:majorFont"), minorEastAsia: eastAsian("a:minorFont"),
                          majorBidi: complex("a:majorFont"), minorBidi: complex("a:minorFont"))
    }

    /// Rewrites every `w:rFonts` under `node` whose ascii/hAnsi face is a
    /// theme reference into the face itself.
    /// A style's `w:styleId` and `w:type` are both optional, and Word fills
    /// them in: no type is a paragraph style, and a style with no id is
    /// looked up by its name. 60329's `EmptyCellLayoutStyle` (1pt, no id, no
    /// type) is what every empty cell's paragraph wears; skipping it set
    /// those cells in Normal's 10pt + 10pt after, grew every table, and
    /// cost the copy a fourth page.
    /// Word counts its `SEQ` fields again when it prints, whatever number the
    /// file cached: lo-c4c60fcb's only "Figure" caption holds 2 and prints 1, and
    /// lo-dcf44597's holds 72 and prints 1. Each identifier counts in document order
    /// (`\r n` starts again at n, `\c` repeats the last, `\h` and a `\*` format
    /// other than Arabic are counted but left as the file wrote them); a text
    /// box's fallback copy takes the number its first copy has.
    static func _renumberSequences(_ root: XNode) {
        var counts: [String: Int] = [:]
        // Each open complex field: its text, whether its result has begun,
        // and the number it shows (nil to leave the cached one).
        var open: [(instr: String, result: Bool, shown: String?, placed: Bool)] = []
        func number(_ instr: String, fallback: Bool) -> String? {
            let tokens = instr.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).map(String.init)
            guard tokens.count >= 2, tokens[0].uppercased() == "SEQ", !tokens[1].hasPrefix("\\") else { return nil }
            let id = tokens[1]
            var hidden = false, arabic = true, repeating = false, reset: Int? = nil
            var i = 2
            while i < tokens.count {
                let t = tokens[i].lowercased()
                if t == "\\s" { return nil }
                if t == "\\h" { hidden = true }
                if t == "\\c" { repeating = true }
                if t == "\\r", i + 1 < tokens.count { reset = Int(tokens[i + 1]); i += 1 }
                if t == "\\*", i + 1 < tokens.count { arabic = arabic && tokens[i + 1].uppercased() == "ARABIC"; i += 1 }
                i += 1
            }
            if !fallback {
                if let reset { counts[id] = reset } else if !repeating { counts[id, default: 0] += 1 }
            }
            guard let n = counts[id] ?? (fallback ? nil : 0), arabic, !hidden else { return nil }
            return String(n)
        }
        func walk(_ node: XNode, fallback: Bool) {
            for child in node.children {
                switch child.name {
                case "w:fldChar":
                    switch child["w:fldCharType"] {
                    case "begin": open.append((instr: "", result: false, shown: nil, placed: false))
                    case "separate":
                        if !open.isEmpty {
                            open[open.count - 1].result = true
                            open[open.count - 1].shown = number(open[open.count - 1].instr, fallback: fallback)
                        }
                    case "end": if !open.isEmpty { open.removeLast() }
                    default: break
                    }
                case "w:instrText":
                    if !open.isEmpty, !open[open.count - 1].result { open[open.count - 1].instr += child.text }
                case "w:t":
                    if let f = open.last, f.result, let shown = f.shown {
                        child.text = f.placed ? "" : shown
                        open[open.count - 1].placed = true
                    }
                case "w:fldSimple":
                    if let shown = number(child["w:instr"] ?? "", fallback: fallback), let t = child.descendant("w:t") { t.text = shown }
                    walk(child, fallback: fallback)
                default:
                    walk(child, fallback: fallback || child.name == "mc:Fallback")
                }
            }
        }
        walk(root, fallback: false)
    }

    /// Word refreshes a plain `REF bookmark` field with the bookmark's text when it
    /// prints, so a reference to a caption whose SEQ number was counted again shows
    /// the new number (2179cebe: the caption prints "Table 1", the cached REF says
    /// "Table 2" and Word prints "Table 1" there too). Only a bookmark that opens
    /// and closes in one paragraph, and a REF with no switch but \h and \*, count.
    static func _refreshReferences(_ root: XNode) {
        var texts: [String: String] = [:]
        func bookmarks(_ p: XNode) {
            var active: [String: (name: String, text: String)] = [:]
            func walk(_ node: XNode) {
                for c in node.children {
                    switch c.name {
                    case "w:bookmarkStart": if let id = c["w:id"], let n = c["w:name"] { active[id] = (n, "") }
                    case "w:bookmarkEnd":
                        if let id = c["w:id"], let a = active.removeValue(forKey: id), !a.text.isEmpty { texts[a.name] = a.text }
                    case "w:t": for k in Array(active.keys) { active[k]?.text += c.text }
                    case "mc:Fallback": break
                    default: walk(c)
                    }
                }
            }
            walk(p)
        }
        var stack = [root]
        while let node = stack.popLast() {
            if node.name == "w:p" { bookmarks(node) }
            stack.append(contentsOf: node.children)
        }
        if texts.isEmpty { return }
        var open: [(instr: String, result: Bool, shown: String?, placed: Bool)] = []
        func target(_ instr: String) -> String? {
            let t = instr.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).map(String.init)
            guard t.count >= 2, t[0].uppercased() == "REF", !t[1].hasPrefix("\\") else { return nil }
            var i = 2
            while i < t.count {
                let k = t[i].lowercased()
                if k == "\\*" { i += 1 } else if k != "\\h" { return nil }
                i += 1
            }
            return texts[t[1]]
        }
        func walk(_ node: XNode, fallback: Bool) {
            for child in node.children {
                switch child.name {
                case "w:fldChar":
                    switch child["w:fldCharType"] {
                    case "begin": open.append((instr: "", result: false, shown: nil, placed: false))
                    case "separate":
                        if !open.isEmpty {
                            open[open.count - 1].result = true
                            open[open.count - 1].shown = fallback ? nil : target(open[open.count - 1].instr)
                        }
                    case "end": if !open.isEmpty { open.removeLast() }
                    default: break
                    }
                case "w:instrText":
                    if !open.isEmpty, !open[open.count - 1].result { open[open.count - 1].instr += child.text }
                case "w:t":
                    if let f = open.last, f.result, let shown = f.shown {
                        child.text = f.placed ? "" : shown
                        open[open.count - 1].placed = true
                    }
                default:
                    walk(child, fallback: fallback || child.name == "mc:Fallback")
                }
            }
        }
        walk(root, fallback: false)
    }

    /// A table written inside a paragraph (LibreOffice's tdf111550 has one in a cell's
    /// paragraph, after a line break) is read by Word as standing after it.
    static func _hoistTablesOutOfParagraphs(_ root: XNode) {
        var stack = [root]
        while let node = ref(&stack) {
            var i = 0
            while i < node.children.count {
                let child = node.children[i]
                if child.name == "w:p", child.children.contains(where: { $0.name == "w:tbl" }) {
                    let tables = child.children.filter { $0.name == "w:tbl" }
                    // (A line break just before it ends the line the table follows: no
                    // empty line is left between, as Word's print has it.)
                    if let at = child.children.firstIndex(where: { $0.name == "w:tbl" }), at > 0,
                       case let run = child.children[at - 1], run.name == "w:r",
                       let last = run.children.last, last.name == "w:br", (last["w:type"] ?? "textWrapping") == "textWrapping" {
                        run.children.removeLast()
                    }
                    child.children.removeAll { $0.name == "w:tbl" }
                    // (And the paragraph's own space after goes: the table was inside it.)
                    let pPr: XNode
                    if let have = child.first("w:pPr") { pPr = have } else {
                        pPr = XNode(name: "w:pPr", attrs: [:])
                        child.children.insert(pPr, at: 0)
                    }
                    if let spacing = pPr.first("w:spacing") { spacing.attrs["w:after"] = "0" }
                    else { pPr.children.append(XNode(name: "w:spacing", attrs: ["w:after": "0"])) }
                    node.children.insert(contentsOf: tables, at: i + 1)
                }
                i += 1
            }
            stack.append(contentsOf: node.children)
        }
        func ref(_ s: inout [XNode]) -> XNode? { s.popLast() }
    }

    static func _normaliseStyleIds(_ styles: XNode) {
        for style in styles.all("w:style") {
            if style.attrs["w:type"] == nil { style.attrs["w:type"] = "paragraph" }
            if style.attrs["w:styleId"] == nil, let name = style.first("w:name")?["w:val"] { style.attrs["w:styleId"] = name }
        }
        // A file whose styles flag no paragraph style as the default (LibreOffice's
        // "style0", named Normal) has the one named "Normal" as it: tdf103931's
        // Liberation Serif paragraphs, which Word's print sets at 24.0pt a line
        // (Times) where ours, outside the style, took 25 (Calibri).
        let paragraphStyles = styles.all("w:style").filter { $0.attrs["w:type"] == "paragraph" }
        if !paragraphStyles.contains(where: { $0.attrs["w:default"] == "1" }),
           let normal = paragraphStyles.first(where: { $0.first("w:name")?["w:val"] == "Normal" }), normal.attrs["w:styleId"] != "Normal" {
            normal.attrs["w:default"] = "1"
        }
    }

    /// The Thai faces Word for Windows lacks (TH SarabunIT๙, TH Sarabun New) whose font-table entry names TH SarabunPSK as the alternate:
    /// Word prints them in that face (xd a0570757: "TH SarabunIT๙", altName "TH SarabunPSK", the print's fonts are TH SarabunPSK, a 16 pt Thai
    /// line 21.0 pt where Browallia's is 20.0). An entry with no alternate, or Browallia New as it, stays Browallia (21 docs, 3a493613).
    static func _thaiAlternates(_ entries: [ZipEntry]) -> Set<String> {
        guard wordOnWindows, let table = entries.first(where: { $0.name == "word/fontTable.xml" }).flatMap({ XNode.parse($0.data) }) else { return [] }
        var out = Set<String>()
        for font in table.all("w:font") {
            guard let name = font["w:name"], ["th sarabunit๙", "th sarabun new"].contains(name.trimmingWhitespace().lowercased()),
                  let alt = font.first("w:altName")?["w:val"], alt.trimmingWhitespace().lowercased() == "th sarabunpsk" else { continue }
            out.insert(name.trimmingWhitespace().lowercased())
        }
        return out
    }
}
