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
import FlutterSwiftBridge
import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

// MARK: - A small DOM

final class XNode {
    let name: String
    let attrs: [String: String]
    var children: [XNode] = []
    var text = ""

    init(name: String, attrs: [String: String]) {
        self.name = name
        self.attrs = attrs
    }

    subscript(_ attr: String) -> String? { attrs[attr] }

    func first(_ name: String) -> XNode? { children.first { $0.name == name } }

    /// Depth-first search by name.
    func descendant(_ name: String) -> XNode? {
        for child in children {
            if child.name == name { return child }
            if let found = child.descendant(name) { return found }
        }
        return nil
    }
    func all(_ name: String) -> [XNode] { children.filter { $0.name == name } }
    var has: (String) -> Bool { { self.first($0) != nil } }

    /// Parse with prefixes kept ("w:p"), which is what the OOXML parts use
    /// consistently and saves resolving namespaces.
    static func parse(_ data: Data) -> XNode? {
        let builder = _Builder()
        let parser = XMLParser(data: data)
        parser.delegate = builder
        parser.shouldProcessNamespaces = false
        guard parser.parse() else { return nil }
        return builder.root
    }

    private final class _Builder: NSObject, XMLParserDelegate {
        var root: XNode?
        private var stack: [XNode] = []

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes: [String: String]) {
            let node = XNode(name: elementName, attrs: attributes)
            if let parent = stack.last { parent.children.append(node) } else { root = node }
            stack.append(node)
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?) {
            _ = stack.popLast()
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            stack.last?.text += string
        }
    }
}

// MARK: - Docx

struct DocxDocument {
    var document: RichDocument
    var pageSetup: PageSetup?
}

enum DocxFormat {
    enum DocxError: Error { case noDocumentPart, badXML(String) }

    // MARK: Reading

    static func read(_ archive: Data) throws -> DocxDocument {
        let entries = try Zip.read(archive)
        func part(_ name: String) -> Data? { entries.first { $0.name == name }?.data }
        guard let docData = part("word/document.xml") else { throw DocxError.noDocumentPart }
        guard let root = XNode.parse(docData) else { throw DocxError.badXML("word/document.xml") }

        // Styles: which paragraph styles are ours (headings, Title, Quote…),
        // and what they look like in this package — Word's Heading 1 is
        // not our Heading 1, so the sheet takes the file's word for it.
        var styleByDocx: [String: String] = [:]
        var sheet = RichStyleSheet.word
        if let stylesData = part("word/styles.xml"), let styles = XNode.parse(stylesData) {
            for style in styles.all("w:style") where style["w:type"] == "paragraph" {
                guard let id = style["w:styleId"] else { continue }
                let name = (style.first("w:name")?["w:val"] ?? id).lowercased()
                guard let ours = _styleId(name) ?? _styleId(id.lowercased()) else { continue }
                // Two of the file's styles can map to one of ours (Quote and
                // Intense Quote): the first defines the look, both use it.
                let first = !styleByDocx.values.contains(ours)
                styleByDocx[id] = ours
                guard first, var entry = sheet[ours], ours != RichNamedStyle.normalId else { continue }
                // The file's definition replaces ours: what its rPr leaves
                // out is off (the style is based on Normal), and a missing
                // pPr means Normal's paragraph props.
                var cs = style.first("w:rPr").map { _charStyle($0, base: CharStyle()) } ?? CharStyle()
                if cs.fontFamily == nil { cs.fontFamily = entry.char.fontFamily }
                entry.char = cs
                var ps = RichParagraphStyle.body
                ps.heading = entry.paragraph.heading
                if let pPr = style.first("w:pPr") { _paragraphProps(pPr, into: &ps) }
                entry.paragraph = ps
                if let next = style.first("w:next")?["w:val"] { entry.next = styleByDocx[next] ?? _styleId(next.lowercased()) }
                sheet[ours] = entry
            }
        }

        // Numbering: numId → level → bullet/decimal, and each numbered
        // level's label format, which the document keeps per list id.
        var kindByNum: [String: [Int: ListKind]] = [:]
        var listFormats: [String: [Int: ListLevelFormat]] = [:]
        if let numData = part("word/numbering.xml"), let numbering = XNode.parse(numData) {
            var abstract: [String: [Int: ListKind]] = [:]
            var abstractFormats: [String: [Int: ListLevelFormat]] = [:]
            for a in numbering.all("w:abstractNum") {
                guard let id = a["w:abstractNumId"] else { continue }
                var levels: [Int: ListKind] = [:]
                var formats: [Int: ListLevelFormat] = [:]
                for lvl in a.all("w:lvl") {
                    let ilvl = Int(lvl["w:ilvl"] ?? "0") ?? 0
                    let fmt = lvl.first("w:numFmt")?["w:val"] ?? "decimal"
                    levels[ilvl] = fmt == "bullet" ? .bullet : .numbered
                    if fmt == "bullet" {
                        // Word's stock bullets are Symbol/Wingdings private-use
                        // glyphs; map the common ones, else a plain bullet.
                        if let raw = lvl.first("w:lvlText")?["w:val"], let ch = raw.unicodeScalars.first {
                            let glyph: String
                            switch ch.value {
                            case 0xF0B7, 0x2022: glyph = "\u{2022}"
                            case 0xF06F, 0x006F: glyph = "\u{25E6}"
                            case 0xF0A7, 0x25AA: glyph = "\u{25AA}"
                            case 0xF0D8, 0x27A2: glyph = "\u{27A2}"
                            case 0xF0FC, 0x2713: glyph = "\u{2713}"
                            case 0xF076, 0x2756: glyph = "\u{2756}"
                            case 0xE000 ... 0xF8FF: glyph = ListLevelFormat.defaultBullet(ilvl)
                            default: glyph = raw
                            }
                            formats[ilvl] = ListLevelFormat(text: glyph, format: .bullet)
                        }
                    } else {
                        let number: ListNumberFormat
                        switch fmt {
                        case "lowerLetter": number = .lowerLetter
                        case "upperLetter": number = .upperLetter
                        case "lowerRoman": number = .lowerRoman
                        case "upperRoman": number = .upperRoman
                        default: number = .decimal
                        }
                        formats[ilvl] = ListLevelFormat(text: lvl.first("w:lvlText")?["w:val"] ?? "%\(ilvl + 1).",
                                                        format: number)
                    }
                }
                abstract[id] = levels
                abstractFormats[id] = formats
            }
            for n in numbering.all("w:num") {
                guard let id = n["w:numId"], let aid = n.first("w:abstractNumId")?["w:val"] else { continue }
                kindByNum[id] = abstract[aid] ?? [:]
                listFormats[id] = abstractFormats[aid] ?? [:]
            }
        }

        // Relationships: hyperlink targets and media parts.
        var rels: [String: String] = [:]
        if let relData = part("word/_rels/document.xml.rels"), let relRoot = XNode.parse(relData) {
            for r in relRoot.all("Relationship") {
                if let id = r["Id"], let target = r["Target"] { rels[id] = target }
            }
        }

        let media: (String) -> Data? = { target in
            let name = target.hasPrefix("/") ? String(target.dropFirst()) : "word/" + target
            return part(name)
        }
        guard let body = root.first("w:body") else { throw DocxError.badXML("no w:body") }
        var paragraphs: [RichParagraph] = []
        var pageSetup: PageSetup? = nil
        var pendingPageBreak = false
        var tableColumns: [String: [Double]] = [:]
        var tableCount = 0
        var currentCell: CellRef? = nil

        func emit(_ p: RichParagraph) {
            var p = p
            if pendingPageBreak { p.style.pageBreakBefore = true; pendingPageBreak = false }
            if p.cell == nil { p.cell = currentCell }
            paragraphs.append(p)
        }

        func walkBlock(_ node: XNode, indent: Double) {
            switch node.name {
            case "w:p":
                for p in _paragraphs(node, styleByDocx, sheet, kindByNum, rels, media, indent) {
                    if p.pageBreakAfter { emit(p.paragraph); pendingPageBreak = true } else { emit(p.paragraph) }
                }
            case "w:tbl" where currentCell != nil:
                // A nested table flattens into its cell, indented.
                for tr in node.all("w:tr") {
                    for tc in tr.all("w:tc") {
                        for child in tc.children { walkBlock(child, indent: indent + 18) }
                    }
                }
            case "w:tbl":
                tableCount += 1
                let id = "t\(tableCount)"
                if let grid = node.first("w:tblGrid") {
                    let widths = grid.all("w:gridCol").compactMap { Double($0["w:w"] ?? "") }.map { $0 / 20 }
                    if !widths.isEmpty { tableColumns[id] = widths }
                }
                // vMerge: "restart" opens a span in a column; a bare vMerge
                // continues it, and that cell's (empty) content is dropped.
                var openSpan: [Int: Range<Int>] = [:]   // column → the spanning cell's paragraphs
                for (r, tr) in node.all("w:tr").enumerated() {
                    var column = 0
                    for tc in tr.all("w:tc") {
                        let tcPr = tc.first("w:tcPr")
                        let span = max(1, Int(tcPr?.first("w:gridSpan")?["w:val"] ?? "1") ?? 1)
                        var restart = false
                        if let v = tcPr?.first("w:vMerge") {
                            if v["w:val"] == "restart" {
                                restart = true
                            } else if let range = openSpan[column], range.upperBound <= paragraphs.count {
                                // Every paragraph of the cell carries the span.
                                for k in range { paragraphs[k].cell?.rowSpan += 1 }
                                column += span
                                continue
                            }
                        } else {
                            openSpan[column] = nil
                        }
                        currentCell = CellRef(table: id, row: r, column: column, span: span)
                        let before = paragraphs.count
                        for child in tc.children { walkBlock(child, indent: indent) }
                        if paragraphs.count == before { emit(RichParagraph()) }
                        if restart { openSpan[column] = before ..< paragraphs.count }
                        column += span
                    }
                }
                currentCell = nil
            case "w:sdt":
                if let content = node.first("w:sdtContent") {
                    for child in content.children { walkBlock(child, indent: indent) }
                }
            case "w:sectPr":
                pageSetup = _pageSetup(node)
            default:
                break
            }
        }
        for child in body.children { walkBlock(child, indent: 0) }
        // The caret must be able to leave a table that ends the document.
        if paragraphs.isEmpty || paragraphs.last?.cell != nil { paragraphs.append(RichParagraph()) }
        var document = RichDocument(paragraphs: paragraphs)
        document.tableColumns = tableColumns
        document.styles = sheet
        document.listFormats = listFormats
        // Header/footer: the section's default references, text with the
        // PAGE/NUMPAGES fields kept as placeholders.
        if let sect = body.first("w:sectPr") {
            for ref in sect.all("w:headerReference") where ref["w:type"] == "default" || ref["w:type"] == nil {
                if let rid = ref["r:id"], let target = rels[rid], let data = media(target),
                   let node = XNode.parse(data) {
                    document.header = _fieldText(node)
                }
            }
            for ref in sect.all("w:footerReference") where ref["w:type"] == "default" || ref["w:type"] == nil {
                if let rid = ref["r:id"], let target = rels[rid], let data = media(target),
                   let node = XNode.parse(data) {
                    document.footer = _fieldText(node)
                }
            }
        }
        return DocxDocument(document: document, pageSetup: pageSetup)
    }

    /// A header/footer part's text with PAGE and NUMPAGES fields (simple or
    /// complex) turned into placeholders; paragraphs joined with spaces.
    private static func _fieldText(_ root: XNode) -> String {
        var out: [String] = []
        var skipping = false   // between a field's separate and end
        func walk(_ node: XNode, into line: inout String) {
            for child in node.children {
                switch child.name {
                case "w:t": if !skipping { line += child.text }
                case "w:tab": if !skipping { line += "\t" }
                case "w:fldSimple":
                    let instr = (child["w:instr"] ?? "").uppercased()
                    if instr.contains("NUMPAGES") { line += RichDocument.pageCountField }
                    else if instr.contains("PAGE") { line += RichDocument.pageField }
                    else { walk(child, into: &line) }
                case "w:instrText":
                    let instr = child.text.uppercased()
                    if instr.contains("NUMPAGES") { line += RichDocument.pageCountField }
                    else if instr.contains("PAGE") { line += RichDocument.pageField }
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
        for p in root.all("w:p") {
            var line = ""
            walk(p, into: &line)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { out.append(trimmed) }
        }
        return out.joined(separator: " ")
    }

    /// Our sheet id for a Word style name (lowercased), or nil.
    private static func _styleId(_ name: String) -> String? {
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

    /// Alignment, indents and spacing from a w:pPr, onto `style`.
    private static func _paragraphProps(_ pPr: XNode, into style: inout RichParagraphStyle) {
        switch pPr.first("w:jc")?["w:val"] {
        case "center": style.alignment = .center
        case "right", "end": style.alignment = .right
        case "both", "distribute": style.alignment = .justify
        case "left", "start": style.alignment = .left
        default: break
        }
        if let ind = pPr.first("w:ind") {
            if let v = Double(ind["w:left"] ?? ind["w:start"] ?? "") { style.indentLeft = v / 20 }
            if let v = Double(ind["w:right"] ?? ind["w:end"] ?? "") { style.indentRight = v / 20 }
            if let v = Double(ind["w:firstLine"] ?? "") { style.firstLineIndent = v / 20 }
            if let v = Double(ind["w:hanging"] ?? "") { style.firstLineIndent = -v / 20 }
        }
        if let sp = pPr.first("w:spacing") {
            if let v = Double(sp["w:before"] ?? "") { style.spaceBefore = v / 20 }
            if let v = Double(sp["w:after"] ?? "") { style.spaceAfter = v / 20 }
            if let v = Double(sp["w:line"] ?? ""), (sp["w:lineRule"] ?? "auto") == "auto", v > 0 {
                style.lineSpacing = v / 240
            }
        }
    }

    private static func _pageSetup(_ sect: XNode) -> PageSetup? {
        guard let sz = sect.first("w:pgSz"), let w = Double(sz["w:w"] ?? ""), let h = Double(sz["w:h"] ?? "") else {
            return nil
        }
        var setup = PageSetup(width: w / 20, height: h / 20)
        if let mar = sect.first("w:pgMar") {
            setup.marginTop = Double(mar["w:top"] ?? "1440").map { abs($0) / 20 } ?? 72
            setup.marginBottom = Double(mar["w:bottom"] ?? "1440").map { abs($0) / 20 } ?? 72
            setup.marginLeft = Double(mar["w:left"] ?? mar["w:start"] ?? "1440").map { $0 / 20 } ?? 72
            setup.marginRight = Double(mar["w:right"] ?? mar["w:end"] ?? "1440").map { $0 / 20 } ?? 72
        }
        if let cols = sect.first("w:cols") {
            if let n = Int(cols["w:num"] ?? ""), n > 1 { setup.columns = n }
            if let space = Double(cols["w:space"] ?? "") { setup.columnGap = space / 20 }
        }
        return setup
    }

    private struct _Built {
        var paragraph: RichParagraph
        var pageBreakAfter: Bool
    }

    /// One w:p can become several paragraphs (a page break inside it).
    private static func _paragraphs(_ p: XNode, _ styleIds: [String: String], _ sheet: RichStyleSheet,
                                    _ nums: [String: [Int: ListKind]],
                                    _ rels: [String: String], _ media: (String) -> Data?,
                                    _ indent: Double) -> [_Built] {
        var style = RichParagraphStyle.body
        if let pPr = p.first("w:pPr") {
            // The named style's props first, then the paragraph's own.
            if let id = pPr.first("w:pStyle")?["w:val"], let ours = styleIds[id] { sheet.apply(ours, to: &style) }
            _paragraphProps(pPr, into: &style)
            style.indentLeft += indent
            if let numPr = pPr.first("w:numPr") {
                let ilvl = Int(numPr.first("w:ilvl")?["w:val"] ?? "0") ?? 0
                let numId = numPr.first("w:numId")?["w:val"] ?? ""
                if numId != "0" {
                    style.list = nums[numId]?[ilvl] ?? nums[numId]?[0] ?? .bullet
                    style.listLevel = min(8, ilvl)
                    style.listId = numId
                    // The list's own indent replaces the style's.
                    style.indentLeft = indent
                }
            }
            if pPr.first("w:pageBreakBefore") != nil, !_isOff(pPr.first("w:pageBreakBefore")!) {
                style.pageBreakBefore = true
            }
        }

        var built: [_Built] = []
        var text = ""
        var runs: [Run] = []
        func flush(pageBreakAfter: Bool) {
            var para = RichParagraph(text: text, runs: runs.isEmpty ? nil : runs, style: style)
            para.normalize()
            built.append(_Built(paragraph: para, pageBreakAfter: pageBreakAfter))
            text = ""
            runs = []
            style.pageBreakBefore = false
        }
        func addImage(_ drawing: XNode) {
            guard let blip = drawing.descendant("a:blip"), let rid = blip["r:embed"],
                  let target = rels[rid], let data = media(target) else { return }
            var w = 300.0, h = 200.0
            if let extent = drawing.descendant("wp:extent"),
               let cx = Double(extent["cx"] ?? ""), let cy = Double(extent["cy"] ?? ""), cx > 0, cy > 0 {
                w = cx / 12700
                h = cy / 12700
            }
            // The text before the picture stands on its own; the picture is a
            // paragraph of its own; what follows starts another.
            if !text.isEmpty { flush(pageBreakAfter: false) } else if !built.isEmpty || true { text = ""; runs = [] }
            var pic = RichParagraph(image: ImageAttachment(data: data, width: w, height: h,
                                                           name: (target as NSString).lastPathComponent))
            pic.style.alignment = style.alignment
            built.append(_Built(paragraph: pic, pageBreakAfter: false))
        }
        func addText(_ s: String, _ cs: CharStyle) {
            guard !s.isEmpty else { return }
            text += s
            runs.append(Run(length: s.utf16.count, style: cs))
        }
        func walkRun(_ r: XNode, link: String?) {
            var cs = CharStyle()
            cs.link = link
            if let rPr = r.first("w:rPr") { cs = _charStyle(rPr, base: cs) }
            for child in r.children {
                switch child.name {
                case "w:t": addText(child.text, cs)
                case "w:tab": addText("\t", cs)
                case "w:br":
                    if child["w:type"] == "page" { flush(pageBreakAfter: true) } else { flush(pageBreakAfter: false) }
                case "w:noBreakHyphen": addText("\u{2011}", cs)
                case "w:softHyphen": addText("\u{00AD}", cs)
                case "w:sym":
                    if let code = child["w:char"], let v = UInt32(code, radix: 16), let sc = UnicodeScalar(v) {
                        addText(String(Character(sc)), cs)
                    }
                case "w:drawing", "w:pict":
                    addImage(child)
                default: break
                }
            }
        }
        func walkInline(_ node: XNode, link: String?) {
            for child in node.children {
                switch child.name {
                case "w:r": walkRun(child, link: link)
                case "w:hyperlink":
                    let target = child["r:id"].flatMap { rels[$0] } ?? child["w:anchor"].map { "#\($0)" }
                    walkInline(child, link: target)
                case "w:ins", "w:smartTag", "w:sdtContent", "w:sdt", "w:fldSimple", "w:customXml":
                    walkInline(child, link: link)
                case "w:del", "w:pPr", "w:proofErr", "w:bookmarkStart", "w:bookmarkEnd":
                    break
                default: break
                }
            }
        }
        walkInline(p, link: nil)
        if !(text.isEmpty && built.last?.paragraph.isImage == true) {
            flush(pageBreakAfter: false)
        }
        return built
    }

    private static func _isOff(_ node: XNode) -> Bool {
        switch node["w:val"] {
        case "0", "false", "off": return true
        default: return false
        }
    }

    private static func _charStyle(_ rPr: XNode, base: CharStyle) -> CharStyle {
        var cs = base
        for child in rPr.children {
            switch child.name {
            case "w:b": cs.bold = !_isOff(child)
            case "w:i": cs.italic = !_isOff(child)
            case "w:u": cs.underline = child["w:val"] != "none"
            case "w:strike", "w:dstrike": cs.strikethrough = !_isOff(child)
            case "w:sz": if let v = Double(child["w:val"] ?? "") { cs.fontSize = v / 2 }
            case "w:color":
                if let hex = child["w:val"], hex.lowercased() != "auto", let v = Int(hex, radix: 16) {
                    cs.color = Color(0xFF000000 | v)
                }
            case "w:highlight":
                cs.highlight = _highlight(child["w:val"] ?? "none")
            case "w:shd":
                if let hex = child["w:fill"], hex.lowercased() != "auto", let v = Int(hex, radix: 16), cs.highlight == nil {
                    cs.highlight = Color(0xFF000000 | v)
                }
            case "w:rFonts":
                cs.fontFamily = _family(child["w:ascii"] ?? child["w:hAnsi"] ?? "")
            case "w:vertAlign":
                switch child["w:val"] {
                case "superscript": cs.script = .superscript
                case "subscript": cs.script = .subscript
                default: cs.script = .normal
                }
            default: break
            }
        }
        return cs
    }

    static let highlightNames: [(String, Color)] = [
        ("yellow", Color(0xFFFFFF00)), ("green", Color(0xFF00FF00)), ("cyan", Color(0xFF00FFFF)),
        ("magenta", Color(0xFFFF00FF)), ("blue", Color(0xFF0000FF)), ("red", Color(0xFFFF0000)),
        ("darkBlue", Color(0xFF000080)), ("darkCyan", Color(0xFF008080)), ("darkGreen", Color(0xFF008000)),
        ("darkMagenta", Color(0xFF800080)), ("darkRed", Color(0xFF800000)), ("darkYellow", Color(0xFF808000)),
        ("darkGray", Color(0xFF808080)), ("lightGray", Color(0xFFC0C0C0)), ("black", Color(0xFF000000)),
        ("white", Color(0xFFFFFFFF)),
    ]

    private static func _highlight(_ name: String) -> Color? {
        highlightNames.first { $0.0 == name }?.1
    }

    private static func _family(_ name: String) -> String? {
        let n = name.lowercased()
        if n.isEmpty { return nil }
        if n.contains("times") || n.contains("serif") || n.contains("georgia") || n.contains("cambria") || n.contains("garamond") { return OfficeFonts.serif }
        if n.contains("courier") || n.contains("mono") || n.contains("consolas") || n.contains("menlo") { return OfficeFonts.mono }
        return nil
    }

    // MARK: Writing

    static func write(_ doc: RichDocument, pageSetup: PageSetup) throws -> Data {
        var rels: [(id: String, target: String)] = []
        var media: [ZipEntry] = []
        var mediaRels: [(id: String, target: String)] = []
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
        var numIds: [String: Int] = [:]        // list id or "run<n>" → numId
        var numFormats: [Int: [Int: ListLevelFormat]] = [:]
        var numKinds: [Int: ListKind] = [:]
        var numIdOf: [Int] = Array(repeating: 0, count: doc.paragraphs.count)
        var runId = 0
        var runOpen = false
        for (i, p) in doc.paragraphs.enumerated() {
            guard let kind = p.style.list else { runOpen = false; continue }
            if let id = p.style.listId {
                if numIds[id] == nil {
                    numIds[id] = numIds.count + 3
                    numFormats[numIds[id]!] = doc.listFormats[id] ?? [:]
                    numKinds[numIds[id]!] = kind
                }
                numIdOf[i] = numIds[id]!
                runOpen = false
            } else if kind == .bullet {
                numIdOf[i] = 1
                runOpen = false
            } else {
                if !runOpen { runId += 1; numIds["run\(runId)"] = numIds.count + 3; runOpen = true }
                let n = numIds["run\(runId)"]!
                numKinds[n] = .numbered
                numIdOf[i] = n
            }
        }

        var body = ""
        func paragraphXML(_ index: Int) -> String {
            let p = doc.paragraphs[index]
            var body = ""
            var pPr = ""
            if let h = p.style.heading { pPr += "<w:pStyle w:val=\"Heading\(min(h, 6))\"/>" }
            else if let n = p.style.named, doc.styles[n] != nil { pPr += "<w:pStyle w:val=\"\(_esc(n))\"/>" }
            else if p.style.list != nil { pPr += "<w:pStyle w:val=\"ListParagraph\"/>" }
            if p.style.pageBreakBefore { pPr += "<w:pageBreakBefore/>" }
            if p.style.list != nil {
                pPr += "<w:numPr><w:ilvl w:val=\"\(p.style.listLevel)\"/><w:numId w:val=\"\(numIdOf[index])\"/></w:numPr>"
            }
            var spacing = ""
            if p.style.spaceBefore > 0 { spacing += " w:before=\"\(Int(p.style.spaceBefore * 20))\"" }
            spacing += " w:after=\"\(Int((p.style.spaceAfter > 0 ? p.style.spaceAfter : 8) * 20))\""
            if p.style.lineSpacing != 1.0 { spacing += " w:line=\"\(Int(p.style.lineSpacing * 240))\" w:lineRule=\"auto\"" }
            pPr += "<w:spacing\(spacing)/>"
            var ind = ""
            if p.style.indentLeft > 0 && p.style.list == nil { ind += " w:left=\"\(Int(p.style.indentLeft * 20))\"" }
            if p.style.indentRight > 0 { ind += " w:right=\"\(Int(p.style.indentRight * 20))\"" }
            if p.style.firstLineIndent > 0 { ind += " w:firstLine=\"\(Int(p.style.firstLineIndent * 20))\"" }
            if p.style.firstLineIndent < 0 { ind += " w:hanging=\"\(Int(-p.style.firstLineIndent * 20))\"" }
            if !ind.isEmpty { pPr += "<w:ind\(ind)/>" }
            switch p.style.alignment {
            case .left: break
            case .center: pPr += "<w:jc w:val=\"center\"/>"
            case .right: pPr += "<w:jc w:val=\"right\"/>"
            case .justify: pPr += "<w:jc w:val=\"both\"/>"
            }
            body += "<w:p><w:pPr>\(pPr)</w:pPr>"
            if let image = p.image {
                let n = media.count + 1
                let ext = image.fileExtension
                usedExtensions.insert(ext)
                let name = "image\(n).\(ext)"
                media.append(ZipEntry(name: "word/media/\(name)", data: image.data))
                let rid = "rIdImage\(n)"
                mediaRels.append((rid, "media/\(name)"))
                let cx = Int(image.width * 12700), cy = Int(image.height * 12700)
                body += "<w:r><w:drawing><wp:inline distT=\"0\" distB=\"0\" distL=\"0\" distR=\"0\"><wp:extent cx=\"\(cx)\" cy=\"\(cy)\"/><wp:docPr id=\"\(n)\" name=\"Picture \(n)\"/><a:graphic xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\"><a:graphicData uri=\"http://schemas.openxmlformats.org/drawingml/2006/picture\"><pic:pic xmlns:pic=\"http://schemas.openxmlformats.org/drawingml/2006/picture\"><pic:nvPicPr><pic:cNvPr id=\"0\" name=\"\(name)\"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed=\"\(rid)\"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"\(cx)\" cy=\"\(cy)\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>"
                return body
            }
            var pos = 0
            let utf16 = p.text.utf16
            for run in p.runs where run.length > 0 {
                let a = utf16.index(utf16.startIndex, offsetBy: pos)
                let b = utf16.index(a, offsetBy: run.length)
                let piece = String(utf16[a ..< b]) ?? ""
                pos += run.length
                let s = run.style
                var rPr = ""
                if let family = s.fontFamily {
                    let name = family == OfficeFonts.serif ? "Times New Roman"
                        : family == OfficeFonts.mono ? "Courier New"
                        : family == OfficeFonts.sans ? "Arial" : family
                    rPr += "<w:rFonts w:ascii=\"\(_esc(name))\" w:hAnsi=\"\(_esc(name))\" w:cs=\"\(_esc(name))\"/>"
                }
                if s.bold { rPr += "<w:b/><w:bCs/>" }
                if s.italic { rPr += "<w:i/><w:iCs/>" }
                if s.underline { rPr += "<w:u w:val=\"single\"/>" }
                if s.strikethrough { rPr += "<w:strike/>" }
                if let color = s.color { rPr += "<w:color w:val=\"\(_hex(color))\"/>" }
                if let size = s.fontSize { rPr += "<w:sz w:val=\"\(Int(size * 2))\"/><w:szCs w:val=\"\(Int(size * 2))\"/>" }
                if let hl = s.highlight {
                    if let name = highlightNames.first(where: { $0.1 == hl })?.0 {
                        rPr += "<w:highlight w:val=\"\(name)\"/>"
                    } else {
                        rPr += "<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"\(_hex(hl))\"/>"
                    }
                }
                if s.script == .superscript { rPr += "<w:vertAlign w:val=\"superscript\"/>" }
                if s.script == .subscript { rPr += "<w:vertAlign w:val=\"subscript\"/>" }
                var runXML = "<w:r>"
                if s.link != nil { rPr = "<w:rStyle w:val=\"Hyperlink\"/>" + rPr }
                if !rPr.isEmpty { runXML += "<w:rPr>\(rPr)</w:rPr>" }
                runXML += _text(piece)
                runXML += "</w:r>"
                if let link = s.link {
                    if link.hasPrefix("#") {
                        body += "<w:hyperlink w:anchor=\"\(_esc(String(link.dropFirst())))\">\(runXML)</w:hyperlink>"
                    } else {
                        body += "<w:hyperlink r:id=\"\(relId(for: link))\">\(runXML)</w:hyperlink>"
                    }
                } else {
                    body += runXML
                }
            }
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
            let cols = (members.compactMap { $0.cell?.column }.max() ?? 0) + 1
            var widths = doc.tableColumns[id] ?? []
            if widths.count != cols {
                let content = pageSetup.width - pageSetup.marginLeft - pageSetup.marginRight
                widths = Array(repeating: content / Double(cols), count: cols)
            }
            let twips = widths.map { Int(($0 * 20).rounded()) }
            var xml = "<w:tbl><w:tblPr><w:tblW w:w=\"0\" w:type=\"auto\"/><w:tblBorders>"
            for side in ["top", "left", "bottom", "right", "insideH", "insideV"] {
                xml += "<w:\(side) w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"auto\"/>"
            }
            xml += "</w:tblBorders><w:tblLook w:val=\"04A0\"/></w:tblPr><w:tblGrid>"
            for w in twips { xml += "<w:gridCol w:w=\"\(w)\"/>" }
            xml += "</w:tblGrid>"
            let refs = members.compactMap(\.cell)
            for r in 0 ..< rows {
                xml += "<w:tr>"
                var c = 0
                while c < cols {
                    // A cell from a row above spanning into this row: a
                    // continuation cell, empty, marked vMerge.
                    if let above = refs.first(where: { $0.row < r && $0.rowSpan > 1 && $0.covers(row: r, column: c) }) {
                        let span = min(cols - c, above.span)
                        let w = twips[c ..< c + span].reduce(0, +)
                        xml += "<w:tc><w:tcPr><w:tcW w:w=\"\(w)\" w:type=\"dxa\"/>"
                        if span > 1 { xml += "<w:gridSpan w:val=\"\(span)\"/>" }
                        xml += "<w:vMerge/></w:tcPr><w:p/></w:tc>"
                        c += span
                        continue
                    }
                    let cell = (start ..< end).filter { doc.paragraphs[$0].cell?.row == r && doc.paragraphs[$0].cell?.column == c }
                    let ref = cell.first.flatMap { doc.paragraphs[$0].cell }
                    let span = min(cols - c, max(1, ref?.span ?? 1))
                    let w = twips[c ..< c + span].reduce(0, +)
                    xml += "<w:tc><w:tcPr><w:tcW w:w=\"\(w)\" w:type=\"dxa\"/>"
                    if span > 1 { xml += "<w:gridSpan w:val=\"\(span)\"/>" }
                    if (ref?.rowSpan ?? 1) > 1 { xml += "<w:vMerge w:val=\"restart\"/>" }
                    xml += "</w:tcPr>"
                    if cell.isEmpty { xml += "<w:p/>" }
                    for k in cell { xml += paragraphXML(k) }
                    xml += "</w:tc>"
                    c += span
                }
                xml += "</w:tr>"
            }
            xml += "</w:tbl>"
            return (xml, end)
        }

        var i = 0
        while i < doc.paragraphs.count {
            if doc.paragraphs[i].cell != nil {
                let t = tableXML(from: i)
                body += t.xml
                i = t.end
            } else {
                body += paragraphXML(i)
                i += 1
            }
        }
        // WordprocessingML wants a paragraph between a table and the section end.
        if doc.paragraphs.last?.cell != nil { body += "<w:p/>" }
        let pw = Int(pageSetup.width * 20), ph = Int(pageSetup.height * 20)
        body += "<w:sectPr>"
        if !doc.header.isEmpty { body += "<w:headerReference w:type=\"default\" r:id=\"rIdHeader\"/>" }
        if !doc.footer.isEmpty { body += "<w:footerReference w:type=\"default\" r:id=\"rIdFooter\"/>" }
        body += "<w:pgSz w:w=\"\(pw)\" w:h=\"\(ph)\"\(pageSetup.isLandscape ? " w:orient=\"landscape\"" : "")/>"
        body += "<w:pgMar w:top=\"\(Int(pageSetup.marginTop * 20))\" w:right=\"\(Int(pageSetup.marginRight * 20))\" w:bottom=\"\(Int(pageSetup.marginBottom * 20))\" w:left=\"\(Int(pageSetup.marginLeft * 20))\" w:header=\"708\" w:footer=\"708\" w:gutter=\"0\"/>"
        if pageSetup.columns > 1 { body += "<w:cols w:num=\"\(pageSetup.columns)\" w:space=\"\(Int(pageSetup.columnGap * 20))\"/>" }
        body += "</w:sectPr>"

        let ns = "xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" xmlns:wp=\"http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing\""
        let document = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<w:document \(ns)><w:body>\(body)</w:body></w:document>"

        var relsXML = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
        relsXML += "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>"
        relsXML += "<Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering\" Target=\"numbering.xml\"/>"
        for r in rels {
            relsXML += "<Relationship Id=\"\(r.id)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink\" Target=\"\(_esc(r.target))\" TargetMode=\"External\"/>"
        }
        for r in mediaRels {
            relsXML += "<Relationship Id=\"\(r.id)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"\(r.target)\"/>"
        }
        var extraParts: [ZipEntry] = []
        var extraOverrides = ""
        if !doc.header.isEmpty {
            relsXML += "<Relationship Id=\"rIdHeader\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/header\" Target=\"header1.xml\"/>"
            extraParts.append(ZipEntry(name: "word/header1.xml", data: Data(_headerFooterPart("w:hdr", doc.header, center: false).utf8)))
            extraOverrides += "<Override PartName=\"/word/header1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml\"/>"
        }
        if !doc.footer.isEmpty {
            relsXML += "<Relationship Id=\"rIdFooter\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer\" Target=\"footer1.xml\"/>"
            extraParts.append(ZipEntry(name: "word/footer1.xml", data: Data(_headerFooterPart("w:ftr", doc.footer, center: true).utf8)))
            extraOverrides += "<Override PartName=\"/word/footer1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml\"/>"
        }
        relsXML += "</Relationships>"
        var contentTypes = _contentTypes.replacingOccurrences(of: "</Types>", with: extraOverrides + "</Types>")
        for ext in usedExtensions.sorted() {
            let mime = ext == "jpeg" ? "image/jpeg" : ext == "gif" ? "image/gif" : "image/png"
            contentTypes = contentTypes.replacingOccurrences(of: "<Override PartName=\"/word/document.xml\"",
                                                             with: "<Default Extension=\"\(ext)\" ContentType=\"\(mime)\"/><Override PartName=\"/word/document.xml\"")
        }

        let entries: [ZipEntry] = [
            ZipEntry(name: "[Content_Types].xml", data: Data(contentTypes.utf8)),
            ZipEntry(name: "_rels/.rels", data: Data(_rootRels.utf8)),
            ZipEntry(name: "word/document.xml", data: Data(document.utf8)),
            ZipEntry(name: "word/styles.xml", data: Data(_stylesPart(doc.styles).utf8)),
            ZipEntry(name: "word/numbering.xml", data: Data(_numberingPart(numKinds, numFormats).utf8)),
            ZipEntry(name: "word/_rels/document.xml.rels", data: Data(relsXML.utf8)),
        ] + media + extraParts
        return try Zip.write(entries)
    }

    /// A header or footer part: one paragraph, fields as fldSimple.
    private static func _headerFooterPart(_ tag: String, _ template: String, center: Bool) -> String {
        var runs = ""
        var literal = ""
        func flush() {
            if !literal.isEmpty { runs += "<w:r>\(_text(literal))</w:r>"; literal = "" }
        }
        var rest = Substring(template)
        while !rest.isEmpty {
            if rest.hasPrefix(RichDocument.pageField) {
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
        let jc = center ? "<w:pPr><w:jc w:val=\"center\"/></w:pPr>" : ""
        return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<\(tag) xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><w:p>\(jc)\(runs)</w:p></\(tag)>"
    }

    private static func _text(_ s: String) -> String {
        // Tabs and line breaks are elements, not characters.
        var out = ""
        var buf = ""
        func flush() {
            if !buf.isEmpty { out += "<w:t xml:space=\"preserve\">\(_esc(buf))</w:t>"; buf = "" }
        }
        for ch in s {
            switch ch {
            case "\t": flush(); out += "<w:tab/>"
            case "\n": flush(); out += "<w:br/>"
            default: buf.append(ch)
            }
        }
        flush()
        return out
    }

    private static func _esc(_ s: String) -> String {
        var out = ""
        for ch in s {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            default: out.append(ch)
            }
        }
        return out
    }

    private static func _hex(_ c: Color) -> String {
        String(format: "%06X", c.value & 0xFFFFFF)
    }

    private static let _contentTypes = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/><Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/></Types>
    """

    private static let _rootRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>
    """

    /// styles.xml from the document's sheet: Normal as the default, every
    /// other entry with its look, plus List Paragraph and Hyperlink.
    private static func _stylesPart(_ sheet: RichStyleSheet) -> String {
        var out = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
        out += "<w:styles xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii=\"Arial\" w:hAnsi=\"Arial\" w:cs=\"Arial\" w:eastAsia=\"Arial\"/><w:sz w:val=\"22\"/><w:szCs w:val=\"22\"/><w:lang w:val=\"en-US\"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after=\"160\" w:line=\"259\" w:lineRule=\"auto\"/></w:pPr></w:pPrDefault></w:docDefaults>"
        out += "<w:style w:type=\"paragraph\" w:default=\"1\" w:styleId=\"Normal\"><w:name w:val=\"Normal\"/><w:qFormat/></w:style>"
        for entry in sheet.styles where entry.id != RichNamedStyle.normalId {
            let name = entry.paragraph.heading.map { "heading \($0)" } ?? entry.name
            out += "<w:style w:type=\"paragraph\" w:styleId=\"\(_esc(entry.id))\"><w:name w:val=\"\(_esc(name))\"/><w:basedOn w:val=\"Normal\"/>"
            if let next = entry.next { out += "<w:next w:val=\"\(_esc(next))\"/>" }
            out += "<w:qFormat/><w:pPr>"
            if entry.paragraph.heading != nil { out += "<w:keepNext/>" }
            var spacing = ""
            if entry.paragraph.spaceBefore > 0 { spacing += " w:before=\"\(Int(entry.paragraph.spaceBefore * 20))\"" }
            spacing += " w:after=\"\(Int(entry.paragraph.spaceAfter * 20))\""
            if entry.paragraph.lineSpacing != 1.0 { spacing += " w:line=\"\(Int(entry.paragraph.lineSpacing * 240))\" w:lineRule=\"auto\"" }
            out += "<w:spacing\(spacing)/>"
            var ind = ""
            if entry.paragraph.indentLeft > 0 { ind += " w:left=\"\(Int(entry.paragraph.indentLeft * 20))\"" }
            if entry.paragraph.indentRight > 0 { ind += " w:right=\"\(Int(entry.paragraph.indentRight * 20))\"" }
            if !ind.isEmpty { out += "<w:ind\(ind)/>" }
            switch entry.paragraph.alignment {
            case .left: break
            case .center: out += "<w:jc w:val=\"center\"/>"
            case .right: out += "<w:jc w:val=\"right\"/>"
            case .justify: out += "<w:jc w:val=\"both\"/>"
            }
            if let h = entry.paragraph.heading { out += "<w:outlineLvl w:val=\"\(h - 1)\"/>" }
            out += "</w:pPr><w:rPr>"
            if let family = entry.char.fontFamily {
                let f = family == OfficeFonts.serif ? "Times New Roman" : family == OfficeFonts.mono ? "Courier New" : family == OfficeFonts.sans ? "Arial" : family
                out += "<w:rFonts w:ascii=\"\(_esc(f))\" w:hAnsi=\"\(_esc(f))\" w:cs=\"\(_esc(f))\"/>"
            }
            if entry.char.bold { out += "<w:b/><w:bCs/>" }
            if entry.char.italic { out += "<w:i/><w:iCs/>" }
            if let c = entry.char.color { out += "<w:color w:val=\"\(_hex(c))\"/>" }
            if let size = entry.char.fontSize { out += "<w:sz w:val=\"\(Int(size * 2))\"/><w:szCs w:val=\"\(Int(size * 2))\"/>" }
            out += "</w:rPr></w:style>"
        }
        out += "<w:style w:type=\"paragraph\" w:styleId=\"ListParagraph\"><w:name w:val=\"List Paragraph\"/><w:basedOn w:val=\"Normal\"/><w:qFormat/><w:pPr><w:ind w:left=\"720\"/><w:contextualSpacing/></w:pPr></w:style>"
        out += "<w:style w:type=\"character\" w:styleId=\"Hyperlink\"><w:name w:val=\"Hyperlink\"/><w:rPr><w:color w:val=\"0563C1\"/><w:u w:val=\"single\"/></w:rPr></w:style></w:styles>"
        return out
    }
    /// numbering.xml: abstract 0 is bullets (numId 1), abstract 1 plain
    /// decimal (numId 2), then one abstract per list the document has,
    /// carrying its level formats.
    private static func _numberingPart(_ kinds: [Int: ListKind], _ formats: [Int: [Int: ListLevelFormat]]) -> String {
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
        for numId in kinds.keys.sorted() where numId >= 3 {
            let abstractId = numId - 1
            var levels = ""
            for i in 0 ..< 9 {
                let left = 720 * (i + 1)
                if kinds[numId] == .bullet {
                    let glyph = formats[numId]?[i].flatMap { $0.format == .bullet ? $0.text : nil } ?? bullets[i % 3]
                    levels += "<w:lvl w:ilvl=\"\(i)\"><w:start w:val=\"1\"/><w:numFmt w:val=\"bullet\"/><w:lvlText w:val=\"\(_esc(glyph))\"/><w:lvlJc w:val=\"left\"/><w:pPr><w:ind w:left=\"\(left)\" w:hanging=\"360\"/></w:pPr></w:lvl>"
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
                    levels += "<w:lvl w:ilvl=\"\(i)\"><w:start w:val=\"1\"/><w:numFmt w:val=\"\(fmt)\"/><w:lvlText w:val=\"\(_esc(f.text))\"/><w:lvlJc w:val=\"left\"/><w:pPr><w:ind w:left=\"\(left)\" w:hanging=\"360\"/></w:pPr></w:lvl>"
                }
            }
            extraAbstract += "<w:abstractNum w:abstractNumId=\"\(abstractId)\"><w:multiLevelType w:val=\"hybridMultilevel\"/>\(levels)</w:abstractNum>"
            extraNums += "<w:num w:numId=\"\(numId)\"><w:abstractNumId w:val=\"\(abstractId)\"/></w:num>"
        }
        return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<w:numbering xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:abstractNum w:abstractNumId=\"0\"><w:multiLevelType w:val=\"hybridMultilevel\"/>\(bulletLevels)</w:abstractNum><w:abstractNum w:abstractNumId=\"1\"><w:multiLevelType w:val=\"hybridMultilevel\"/>\(decimalLevels)</w:abstractNum>\(extraAbstract)<w:num w:numId=\"1\"><w:abstractNumId w:val=\"0\"/></w:num><w:num w:numId=\"2\"><w:abstractNumId w:val=\"1\"/></w:num>\(extraNums)</w:numbering>"
    }
}
