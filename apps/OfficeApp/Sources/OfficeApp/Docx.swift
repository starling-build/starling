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
#if canImport(FoundationXML) && !os(WASI)
import FoundationXML
#endif

// MARK: - A small DOM

final class XNode {
    let name: String
    var attrs: [String: String]
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
        #if os(WASI)
        // FoundationXML's parser is libxml2 and an NSObject delegate, neither
        // of which the web build has; WordprocessingML is plain, well-formed
        // XML, which the parser below reads.
        return MiniXML.parse([UInt8](data))
        #else
        let builder = _Builder()
        let parser = XMLParser(data: data)
        parser.delegate = builder
        parser.shouldProcessNamespaces = false
        guard parser.parse() else { return nil }
        return builder.root
        #endif
    }

    #if !os(WASI)
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
    #endif
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
        let kept = _keptParts(entries, part)
        // Theme fonts: "minorHAnsi" in a run or style means the theme's
        // minor Latin face — Calibri only in Word's default theme. Resolved
        // in the trees before anything reads a font, so a Cambria or Aptos
        // document lays out (and saves) in Cambria or Aptos; the theme part
        // itself rides along in keptParts.
        let theme = _themeFonts(entries)
        _resolveThemeFonts(root, theme)

        // Styles: which paragraph styles are ours (headings, Title, Quote…),
        // and what they look like in this package — Word's Heading 1 is
        // not our Heading 1, so the sheet takes the file's word for it.
        // Spacing is Word's hierarchy: the document defaults (0 after and
        // single lines when the file states none), Normal on top, a
        // table's style on top of that inside its cells, then the named
        // style, then the paragraph's own — every paragraph comes out
        // with the absolute values the layout draws.
        var styleByDocx: [String: String] = [:]
        var sheet = RichStyleSheet.word
        var base = RichParagraphStyle(spaceAfter: 0, lineSpacing: 1.0)
        var tableBases: [String: RichParagraphStyle] = [:]
        // Cell margins by table style, each side from the style's chain
        // down to the default table style, then Word's own (0, 5.4pt).
        var tableMargins: [String: _Margins] = [:]
        var defaultMargins = _Margins()
        // Whether a table style draws borders (Table Grid does, Normal Table
        // does not): a table that says nothing itself takes its style's word.
        var tableBorders: [String: _Borders] = [:]
        var defaultBorders: _Borders? = nil
        // A table style's conditional parts: the first row's fill and run
        // look, the body rows' bands.
        var tableConds: [String: _Cond] = [:]
        // Numbering a paragraph style carries itself (a numbered heading
        // style): the paragraphs of that style number without a numPr.
        var styleNums: [String: (numId: String, ilvl: Int)] = [:]
        if let stylesData = part("word/styles.xml"), let styles = XNode.parse(stylesData) {
            _resolveThemeFonts(styles, theme)
            if let defaults = styles.first("w:docDefaults")?.first("w:pPrDefault")?.first("w:pPr") {
                _paragraphProps(defaults, into: &base)
            }
            for style in styles.all("w:style") where style["w:type"] == "paragraph"
                && (style["w:default"] == "1" || style["w:styleId"] == "Normal") {
                if let pPr = style.first("w:pPr") { _paragraphProps(pPr, into: &base) }
            }
            var tableNodes: [String: XNode] = [:]
            for style in styles.all("w:style") where style["w:type"] == "table" {
                guard let id = style["w:styleId"] else { continue }
                var ps = base
                if let pPr = style.first("w:pPr") { _paragraphProps(pPr, into: &ps) }
                tableBases[id] = ps
                tableNodes[id] = style
                if style["w:default"] == "1" {
                    defaultMargins = _cellMargins(style.first("w:tblPr"))
                    defaultBorders = _borders(style.first("w:tblPr"), "w:tblBorders")
                }
            }
            for id in tableNodes.keys {
                var seen = Set<String>(), cur: String? = id
                while let c = cur, !seen.contains(c), let node = tableNodes[c] {
                    seen.insert(c)
                    if let b = _borders(node.first("w:tblPr"), "w:tblBorders") { tableBorders[id] = b; break }
                    cur = node.first("w:basedOn")?["w:val"]
                }
            }
            for id in tableNodes.keys {
                var cond = _Cond(), seen = Set<String>(), cur: String? = id
                while let c = cur, !seen.contains(c), let node = tableNodes[c] {
                    seen.insert(c)
                    for part in node.all("w:tblStylePr") {
                        let fill = part.first("w:tcPr")?.first("w:shd")?["w:fill"].flatMap { hex -> Color? in
                            guard hex.count == 6, let v = UInt32(hex, radix: 16) else { return nil }
                            return Color(0xFF00_0000 | Int64(v))
                        }
                        switch part["w:type"] {
                        case "firstRow":
                            if cond.headerFill == nil { cond.headerFill = fill }
                            if cond.headerChar == nil, let rPr = part.first("w:rPr") { cond.headerChar = _charStyle(rPr, base: CharStyle()) }
                        case "band1Horz": if cond.band1 == nil { cond.band1 = fill }
                        case "band2Horz": if cond.band2 == nil { cond.band2 = fill }
                        default: break
                        }
                    }
                    cur = node.first("w:basedOn")?["w:val"]
                }
                tableConds[id] = cond
            }
            for id in tableNodes.keys {
                var m = _Margins(), seen = Set<String>(), cur: String? = id
                while let c = cur, !seen.contains(c), let node = tableNodes[c] {
                    seen.insert(c)
                    m = m.under(_cellMargins(node.first("w:tblPr")))
                    cur = node.first("w:basedOn")?["w:val"]
                }
                tableMargins[id] = m
            }
            // A style's look is its chain's: its own props over its
            // `basedOn` parent's, over that one's, down to the defaults.
            // Reading each style alone lost everything a parent gave it
            // (52288's "Chapter Number", based on a "Chapter Name" that holds
            // the bold and the size, came back as plain Normal text).
            var paragraphStyles: [String: XNode] = [:]
            for style in styles.all("w:style") where style["w:type"] == "paragraph" {
                if let id = style["w:styleId"] { paragraphStyles[id] = style }
            }
            for id in paragraphStyles.keys {
                var seen = Set<String>(), cur: String? = id
                while let c = cur, !seen.contains(c), let node = paragraphStyles[c] {
                    seen.insert(c)
                    if let numPr = node.first("w:pPr")?.first("w:numPr") {
                        if let numId = numPr.first("w:numId")?["w:val"], numId != "0" {
                            styleNums[id] = (numId, Int(numPr.first("w:ilvl")?["w:val"] ?? "0") ?? 0)
                        }
                        break
                    }
                    cur = node.first("w:basedOn")?["w:val"]
                }
            }
            var resolved: [String: (paragraph: RichParagraphStyle, char: CharStyle)] = [:]
            func resolve(_ id: String, _ seen: Set<String> = []) -> (paragraph: RichParagraphStyle, char: CharStyle) {
                if let r = resolved[id] { return r }
                guard let style = paragraphStyles[id], !seen.contains(id) else { return (paragraph: base, char: CharStyle()) }
                var r = style.first("w:basedOn")?["w:val"].map { resolve($0, seen.union([id])) } ?? (paragraph: base, char: CharStyle())
                if let pPr = style.first("w:pPr") { _paragraphProps(pPr, into: &r.paragraph) }
                if let rPr = style.first("w:rPr") { r.char = _charStyle(rPr, base: r.char) }
                resolved[id] = r
                return r
            }
            // The styles the document's paragraphs name: those of ours they
            // map to take the file's look; the rest (custom styles) join
            // the sheet under their own ids, so they lay out and save as
            // they were.
            var used = Set<String>()
            func collect(_ n: XNode) {
                if n.name == "w:pStyle", let v = n["w:val"] { used.insert(v) }
                for c in n.children { collect(c) }
            }
            collect(root)
            for (name, data) in kept where name.hasSuffix(".xml") {
                if let n = XNode.parse(data) { collect(n) }
            }
            for style in styles.all("w:style") where style["w:type"] == "paragraph" {
                guard let id = style["w:styleId"] else { continue }
                let rawName = style.first("w:name")?["w:val"] ?? id
                let name = rawName.lowercased()
                let chain = resolve(id)
                if let ours = _styleId(name) ?? _styleId(id.lowercased()) {
                    // Two of the file's styles can map to one of ours (Quote
                    // and Intense Quote): the first defines the look, both use it.
                    let first = !styleByDocx.values.contains(ours)
                    styleByDocx[id] = ours
                    guard first, var entry = sheet[ours], ours != RichNamedStyle.normalId else { continue }
                    var cs = chain.char
                    if cs.fontFamily == nil { cs.fontFamily = entry.char.fontFamily }
                    entry.char = cs
                    var ps = chain.paragraph
                    ps.heading = entry.paragraph.heading
                    entry.paragraph = ps
                    if let next = style.first("w:next")?["w:val"] { entry.next = styleByDocx[next] ?? _styleId(next.lowercased()) }
                    sheet[ours] = entry
                } else if used.contains(id), sheet[id] == nil {
                    styleByDocx[id] = id
                    sheet[id] = RichNamedStyle(id: id, name: rawName, paragraph: chain.paragraph, char: chain.char)
                }
            }
        }
        if var normal = sheet[RichNamedStyle.normalId] {
            normal.paragraph = base
            // Normal's look — the document defaults' run properties under
            // Normal's own: the font and size every plain paragraph is set
            // in. Without it a 12-point document came back at Calibri 11
            // (the writer's defaults), and every line wrapped elsewhere.
            if let styles = part("word/styles.xml").flatMap(XNode.parse) {
                _resolveThemeFonts(styles, theme)
                var cs = CharStyle()
                if let rPr = styles.first("w:docDefaults")?.first("w:rPrDefault")?.first("w:rPr") { cs = _charStyle(rPr, base: cs) }
                for style in styles.all("w:style") where style["w:type"] == "paragraph"
                    && (style["w:default"] == "1" || style["w:styleId"] == "Normal") {
                    if let rPr = style.first("w:rPr") { cs = _charStyle(rPr, base: cs) }
                }
                // A file that states no size anywhere is 10pt in Word (the
                // 2003-era default), not the 11pt of a fresh document.
                if cs.fontSize == nil { cs.fontSize = 10 }
                normal.char = cs
            }
            sheet[RichNamedStyle.normalId] = normal
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
        var relInfo: [String: KeptRel] = [:]
        if let relData = part("word/_rels/document.xml.rels"), let relRoot = XNode.parse(relData) {
            for r in relRoot.all("Relationship") {
                if let id = r["Id"], let target = r["Target"] {
                    rels[id] = target
                    relInfo[id] = KeptRel(id: id, type: r["Type"] ?? "", target: target, external: r["TargetMode"] == "External")
                }
            }
        }
        // Content types, for the parts kept verbatim.
        var typeByExt: [String: String] = [:], typeByPart: [String: String] = [:]
        if let ct = part("[Content_Types].xml").flatMap(XNode.parse) {
            for d in ct.all("Default") { if let e = d["Extension"], let t = d["ContentType"] { typeByExt[e.lowercased()] = t } }
            for o in ct.all("Override") { if let n = o["PartName"], let t = o["ContentType"] { typeByPart[n.hasPrefix("/") ? String(n.dropFirst()) : n] = t } }
        }
        let contentType: (String) -> String? = { path in
            typeByPart[path] ?? typeByExt[(path.split(separator: ".").last.map(String.init) ?? "").lowercased()]
        }
        let rootNS = root.attrs.filter { $0.key.hasPrefix("xmlns:") }

        let media: (String) -> Data? = { target in
            let name = target.hasPrefix("/") ? String(target.dropFirst()) : "word/" + target
            return part(name)
        }
        guard let body = root.first("w:body") else { throw DocxError.badXML("no w:body") }
        let notes = _Shared(kept: kept, rels: relInfo, rootNS: rootNS, part: part, contentType: contentType)
        var paragraphs: [RichParagraph] = []
        var pageSetup: PageSetup? = nil
        var pendingPageBreak = false
        var tableColumns: [String: [Double]] = [:]
        var tableStyles: [String: TableStyle] = [:]
        var tableCount = 0
        var currentCell: CellRef? = nil
        var cellChar = CharStyle()   // the table style's look for the first row's runs
        var cellBase = base   // the table style's spacing while inside one

        func emit(_ p: RichParagraph) {
            var p = p
            if pendingPageBreak { p.style.pageBreakBefore = true; pendingPageBreak = false }
            if p.cell == nil { p.cell = currentCell }
            paragraphs.append(p)
        }

        // A row or cell may sit inside a content control (`w:sdt` >
        // `w:sdtContent` > `w:tr`/`w:tc`, as Word writes repeating-section
        // and cell controls): the wrapper is transparent here.
        func unwrapped(_ parent: XNode, _ name: String) -> [XNode] {
            var out: [XNode] = []
            for c in parent.children {
                if c.name == name { out.append(c) }
                else if c.name == "w:sdt", let inner = c.first("w:sdtContent") { out += unwrapped(inner, name) }
            }
            return out
        }
        // Tables nest through cells; a fuzzer's 5000-deep nest overflowed the
        // stack, so past this depth a cell's paragraphs are gathered without
        // recursing further.
        let maxNesting = 32
        func deepParagraphs(_ node: XNode) -> [XNode] {
            var out: [XNode] = []
            var stack = [node]
            while let n = stack.popLast() {
                if n.name == "w:p" { out.append(n); continue }
                stack.append(contentsOf: n.children.reversed())
            }
            return out
        }
        func walkBlock(_ node: XNode, indent: Double, depth: Int = 0) {
            switch node.name {
            case "w:p":
                for p in _paragraphs(node, currentCell != nil ? cellBase : base, styleByDocx, styleNums, sheet, kindByNum, rels, media, indent, notes, cellChar) {
                    if p.pageBreakAfter { emit(p.paragraph); pendingPageBreak = true } else { emit(p.paragraph) }
                }
            case "w:tbl" where currentCell != nil:
                // A nested table flattens into its cell, indented.
                if depth >= maxNesting {
                    for p in deepParagraphs(node) { walkBlock(p, indent: indent + 18, depth: depth + 1) }
                    break
                }
                for tr in unwrapped(node, "w:tr") {
                    for tc in unwrapped(tr, "w:tc") {
                        for child in tc.children { walkBlock(child, indent: indent + 18, depth: depth + 1) }
                    }
                }
            case "w:tbl":
                tableCount += 1
                let id = "t\(tableCount)"
                // Word's Table Grid says no space after and single lines;
                // a table with no style leaves the document defaults.
                cellBase = node.first("w:tblPr")?.first("w:tblStyle")?["w:val"].flatMap { tableBases[$0] } ?? base
                if let grid = node.first("w:tblGrid") {
                    let widths = grid.all("w:gridCol").compactMap { Double($0["w:w"] ?? "") }.map { $0 / 20 }
                    if !widths.isEmpty { tableColumns[id] = widths }
                }
                var style = TableStyle()
                // The table's own borders, else its style's, else none —
                // 64 of the corpus's 109 tables say nothing and have none.
                // Tables converted from HTML say it per cell instead
                // (bug65649's 5,734-cell table, bug59058, table-indent):
                // what most cells say wins, with their colour.
                let styledBorders = node.first("w:tblPr")?.first("w:tblStyle")?["w:val"].flatMap { tableBorders[$0] }
                let cells = unwrapped(node, "w:tr").flatMap { unwrapped($0, "w:tc") }
                let cellSaid = cells.compactMap { _borders($0.first("w:tcPr"), "w:tcBorders") }
                var cellBorders: _Borders? = nil
                if cellSaid.count * 2 >= cells.count, !cells.isEmpty {
                    let on = cellSaid.filter(\.on)
                    if on.count * 2 > cells.count { cellBorders = on.first { $0.color != nil } ?? on[0] }
                    else if (cellSaid.count - on.count) * 2 > cells.count { cellBorders = _Borders(on: false, color: nil) }
                }
                let borders = cellBorders ?? _borders(node.first("w:tblPr"), "w:tblBorders") ?? styledBorders ?? defaultBorders
                style.borders = borders?.on ?? false
                style.borderColor = borders?.color
                if unwrapped(node, "w:tr").first?.first("w:trPr")?.first("w:tblHeader") != nil { style.headerRow = true }
                // The style's conditional parts, as w:tblLook switches them
                // on (attributes in 2010 files, bits of w:val in 2007's).
                let cond = node.first("w:tblPr")?.first("w:tblStyle")?["w:val"].flatMap { tableConds[$0] } ?? _Cond()
                let look = node.first("w:tblPr")?.first("w:tblLook")
                let lookVal = look.flatMap { Int($0["w:val"] ?? "", radix: 16) } ?? 0x04A0
                let firstRowOn = look?["w:firstRow"].map { $0 != "0" } ?? (lookVal & 0x0020 != 0)
                let bandsOn = !(look?["w:noHBand"].map { $0 != "0" } ?? (lookVal & 0x0200 != 0))
                // Where the table sits in the column (w:jc on the table).
                switch node.first("w:tblPr")?.first("w:jc")?["w:val"] {
                case "center": style.alignment = .center
                case "right", "end": style.alignment = .right
                default: break
                }
                let styled = node.first("w:tblPr")?.first("w:tblStyle")?["w:val"].flatMap { tableMargins[$0] } ?? _Margins()
                // Margins the cells carry themselves (w:tcMar, again the
                // HTML converters' habit) when most of them do.
                let cellMars = cells.filter { $0.first("w:tcPr")?.first("w:tcMar") != nil }
                let cellMar = cellMars.count * 2 >= cells.count && !cellMars.isEmpty
                    ? _cellMargins(cellMars[0].first("w:tcPr"), "w:tcMar") : _Margins()
                let margins = cellMar.under(_cellMargins(node.first("w:tblPr"))).under(styled).under(defaultMargins).under(_Margins.word)
                style.cellMarginTop = margins.top
                style.cellMarginLeft = margins.left
                style.cellMarginBottom = margins.bottom
                style.cellMarginRight = margins.right
                if let ind = node.first("w:tblPr")?.first("w:tblInd"), (ind["w:type"] ?? "dxa") == "dxa",
                   let w = Double(ind["w:w"] ?? "") {
                    style.indent = w / 20
                }
                for (r, tr) in unwrapped(node, "w:tr").enumerated() {
                    if let h = tr.first("w:trPr")?.first("w:trHeight"), let v = Double(h["w:val"] ?? ""), v > 0 {
                        style.rowHeights[r] = v / 20
                    }
                }
                if style != TableStyle() { tableStyles[id] = style }
                // vMerge: "restart" opens a span in a column; a bare vMerge
                // continues it, and that cell's (empty) content is dropped.
                var openSpan: [Int: Range<Int>] = [:]   // column → the spanning cell's paragraphs
                for (r, tr) in unwrapped(node, "w:tr").enumerated() {
                    var column = 0
                    for tc in unwrapped(tr, "w:tc") {
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
                        // The cell's own shading: a fill colour, not "auto".
                        var fill: Color? = nil
                        if let shd = tcPr?.first("w:shd"), let hex = shd["w:fill"], hex.count == 6,
                           let v = UInt32(hex, radix: 16) {
                            fill = Color(0xFF00_0000 | Int64(v))
                        }
                        if fill == nil {
                            if r == 0 && firstRowOn { fill = cond.headerFill }
                            else if bandsOn { fill = (r - (firstRowOn ? 1 : 0)) % 2 == 0 ? cond.band1 : cond.band2 }
                        }
                        currentCell = CellRef(table: id, row: r, column: column, span: span, fill: fill)
                        cellChar = r == 0 && firstRowOn ? (cond.headerChar ?? CharStyle()) : CharStyle()
                        let before = paragraphs.count
                        for child in tc.children { walkBlock(child, indent: indent, depth: depth + 1) }
                        if paragraphs.count == before { emit(RichParagraph(style: cellBase)) }
                        if restart { openSpan[column] = before ..< paragraphs.count }
                        column += span
                    }
                }
                currentCell = nil
                cellChar = CharStyle()
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
        document.tableStyles = tableStyles
        document.styles = sheet
        document.listFormats = listFormats
        document.keptParts = notes.kept
        document.keptPartTypes = notes.keptTypes
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
            // A header or footer with a picture, a table or a text box
            // (a logo, 60329's banner) is more than its text: the part is
            // kept whole and written back unless the text was edited; the
            // first-page and even-page ones, which the editor has no
            // field for, are kept always.
            document.titlePage = sect.first("w:titlePg") != nil
            if let settings = part("word/settings.xml").flatMap(XNode.parse), let compat = settings.first("w:compat"),
               compat.children.allSatisfy({ $0.name.hasPrefix("w:") }) {
                document.keptCompat = PptxXML.serialize(compat)
            }
            document.evenAndOddHeaders = part("word/settings.xml").map { String(decoding: $0, as: UTF8.self).containsSubstring("<w:evenAndOddHeaders") } ?? false
            for ref in sect.children where ref.name == "w:headerReference" || ref.name == "w:footerReference" {
                let type = ref["w:type"] ?? "default"
                guard ["default", "first", "even"].contains(type), let rid = ref["r:id"], let target = relInfo[rid]?.target,
                      let data = media(target), _wellFormed(data), let node = XNode.parse(data) else { continue }
                let xml = String(decoding: data, as: UTF8.self)
                let rich = ["<w:drawing", "<w:pict", "<w:tbl>", "<w:tbl ", "<mc:AlternateContent", "<w:object"].contains { xml.containsSubstring($0) }
                guard rich || type != "default" else { continue }
                let path = _resolvePath("word", target)
                notes.keep(path)
                guard notes.kept[path] != nil else { continue }
                document.keptHeaderFooters.append(KeptHeaderFooter(kind: ref.name == "w:headerReference" ? .header : .footer,
                                                                   type: type, part: path, text: _fieldText(node)))
            }
            document.keptParts = notes.kept
            document.keptPartTypes = notes.keptTypes
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
                case "w:pPr", "w:rPr": break   // tab STOPS live in w:pPr/w:tabs as w:tab too
                case "mc:AlternateContent":
                    // One rendering of the two (a text box's Choice and its
                    // VML Fallback hold the same text), not both.
                    if let pick = child.first("mc:Choice") ?? child.first("mc:Fallback") { walk(pick, into: &line) }
                case "w:t": if !skipping { line += child.text }
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
        if let bidi = pPr.first("w:bidi") { style.rightToLeft = !_isOff(bidi) }
        if let tabs = pPr.first("w:tabs") {
            var stops: [TabStop] = []
            for t in tabs.all("w:tab") {
                guard let pos = Double(t["w:pos"] ?? ""), pos >= 0 else { continue }
                let a: TabStop.Alignment
                switch t["w:val"] ?? "left" {
                case "center": a = .center
                case "right": a = .right
                case "decimal": a = .decimal
                case "left", "start", "num": a = .left
                default: continue   // clear, bar
                }
                stops.append(TabStop(position: pos / 20, alignment: a))
            }
            if !stops.isEmpty { style.tabStops = stops }
        }
        if let bdr = pPr.first("w:pBdr") {
            // Each edge: sz in eighths of a point, space in points, colour
            // hex or auto. "nil"/"none" is an edge without a line.
            func line(_ name: String) -> BorderLine? {
                guard let e = bdr.first(name) else { return nil }
                switch e["w:val"] ?? "nil" {
                case "nil", "none": return nil
                default: break
                }
                let sz = Double(e["w:sz"] ?? "4") ?? 4
                var color: Color? = nil
                if let hex = e["w:color"], hex.lowercased() != "auto", hex.count == 6, let v = Int(hex, radix: 16) {
                    color = Color(argb: 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF)
                }
                return BorderLine(width: max(0.25, sz / 8), color: color, space: Double(e["w:space"] ?? "0") ?? 0)
            }
            let b = ParagraphBorders(top: line("w:top"), bottom: line("w:bottom"), left: line("w:left"), right: line("w:right"))
            style.borders = b.isEmpty ? nil : b
        }
        if let sp = pPr.first("w:spacing") {
            if let v = Double(sp["w:before"] ?? "") { style.spaceBefore = v / 20 }
            if let v = Double(sp["w:after"] ?? "") { style.spaceAfter = v / 20 }
            if let v = Double(sp["w:line"] ?? ""), v > 0 {
                switch sp["w:lineRule"] ?? "auto" {
                case "exact":
                    style.lineHeightPoints = v / 20
                    style.lineHeightIsMinimum = false
                case "atLeast":
                    // "At least 1pt" (Bug51170's atLeast 23 twips) is single
                    // spacing in effect; a real minimum is kept as one.
                    if v / 20 >= 12 {
                        style.lineHeightPoints = v / 20
                        style.lineHeightIsMinimum = true
                    } else {
                        style.lineHeightPoints = nil
                        style.lineSpacing = 1.0
                    }
                default:
                    style.lineSpacing = v / 240
                    style.lineHeightPoints = nil
                }
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
            // The header/footer distances: writing 0.49in into a file whose
            // top margin is 0.1in made Word warn that the margins were small.
            if let v = Double(mar["w:header"] ?? "") { setup.headerDistance = max(0, v) / 20 }
            if let v = Double(mar["w:footer"] ?? "") { setup.footerDistance = max(0, v) / 20 }
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
    /// What one read shares across its paragraphs: which note parts the
    /// file has and the running numbers Word would show for their marks,
    /// the document's relationships, the namespaces its root declares, and
    /// the parts kept verbatim for objects the editor cannot show.
    final class _Shared {
        let footnotes: Bool, endnotes: Bool
        private var seenFootnotes = 0, seenEndnotes = 0
        let rels: [String: KeptRel]
        let rootNS: [String: String]
        let part: (String) -> Data?
        let contentType: (String) -> String?
        var kept: [String: Data]
        var keptTypes: [String: String] = [:]
        init(kept: [String: Data], rels: [String: KeptRel], rootNS: [String: String],
             part: @escaping (String) -> Data?, contentType: @escaping (String) -> String?) {
            self.kept = kept
            self.footnotes = kept["word/footnotes.xml"] != nil
            self.endnotes = kept["word/endnotes.xml"] != nil
            self.rels = rels; self.rootNS = rootNS; self.part = part; self.contentType = contentType
            for name in kept.keys { if let t = contentType(name) { keptTypes[name] = t } }
        }
        func next(footnote: Bool) -> Int {
            if footnote { seenFootnotes += 1; return seenFootnotes }
            seenEndnotes += 1; return seenEndnotes
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
            for r in node.all("Relationship") where r["TargetMode"] != "External" {
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
    }

    /// A table style's conditional formatting, the parts the editor shows.
    struct _Cond {
        var headerFill: Color? = nil
        var headerChar: CharStyle? = nil
        var band1: Color? = nil
        var band2: Color? = nil
    }

    /// `w:tblBorders` of a table or table style (or `w:tcBorders` of a
    /// cell): nil when it says nothing, off when every edge it lists is
    /// nil/none, else on, with the first drawn edge's colour (nil for
    /// auto).
    private static func _borders(_ pr: XNode?, _ tag: String) -> _Borders? {
        guard let b = pr?.first(tag), !b.children.isEmpty else { return nil }
        let drawn = b.children.filter { !["nil", "none"].contains($0["w:val"] ?? "nil") }
        guard let first = drawn.first else { return _Borders(on: false, color: nil) }
        var color: Color? = nil
        if let hex = drawn.first(where: { ($0["w:color"] ?? "auto").lowercased() != "auto" })?["w:color"] ?? first["w:color"],
           hex.lowercased() != "auto", hex.count == 6, let v = Int(hex, radix: 16) {
            color = Color(argb: 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF)
        }
        return _Borders(on: true, color: color)
    }

    /// `w:tblCellMar` of a table or table style (or a cell's `w:tcMar`),
    /// in points, dxa sides only.
    private static func _cellMargins(_ pr: XNode?, _ tag: String = "w:tblCellMar") -> _Margins {
        guard let m = pr?.first(tag) else { return _Margins() }
        func side(_ names: [String]) -> Double? {
            for n in names {
                if let e = m.first(n), (e["w:type"] ?? "dxa") == "dxa", let w = Double(e["w:w"] ?? "") { return w / 20 }
            }
            return nil
        }
        return _Margins(top: side(["w:top"]), left: side(["w:left", "w:start"]), bottom: side(["w:bottom"]), right: side(["w:right", "w:end"]))
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
    private static func _length(_ raw: String) -> Double? {
        let s = raw.trimmingWhitespace()
        let units: [(String, Double)] = [("pt", 1), ("in", 72), ("cm", 72 / 2.54), ("mm", 72 / 25.4), ("px", 0.75)]
        for (u, k) in units where s.hasSuffix(u) { return Double(s.dropLast(u.count)).map { $0 * k } }
        return Double(s)
    }

    /// Parts the editor does not model but the file had — Word's footnotes
    /// and endnotes, each with its rels and whatever those reach (a
    /// picture in a note) — kept verbatim so a save keeps the notes the
    /// body still references.
    private static func _keptParts(_ entries: [ZipEntry], _ part: (String) -> Data?) -> [String: Data] {
        var kept: [String: Data] = [:]
        // Only a part that parses is kept: a damaged one would make the
        // saved file as unopenable as the original.
        for e in entries where e.name.hasPrefix("word/theme/") && e.name.hasSuffix(".xml") && _wellFormed(e.data) {
            kept[e.name] = e.data
        }
        for name in ["footnotes", "endnotes"] {
            guard let data = part("word/\(name).xml"), _wellFormed(data) else { continue }
            kept["word/\(name).xml"] = data
            guard let rels = part("word/_rels/\(name).xml.rels") else { continue }
            kept["word/_rels/\(name).xml.rels"] = rels
            guard let node = XNode.parse(rels) else { continue }
            for r in node.all("Relationship") where r["TargetMode"] != "External" {
                guard let target = r["Target"] else { continue }
                let path = target.hasPrefix("/") ? String(target.dropFirst()) : "word/" + target
                if let d = part(path), !_ownParts.contains(path) { kept[path] = d }
            }
        }
        return kept
    }

    /// The theme's major and minor Latin faces, for the theme font
    /// references runs and styles make.
    private static func _themeFonts(_ entries: [ZipEntry]) -> (major: String?, minor: String?) {
        guard let e = entries.first(where: { $0.name.hasPrefix("word/theme/") && $0.name.hasSuffix(".xml") }),
              let root = XNode.parse(e.data), let scheme = root.descendant("a:fontScheme") else { return (nil, nil) }
        func face(_ name: String) -> String? {
            let f = scheme.first(name)?.first("a:latin")?["typeface"] ?? ""
            return f.isEmpty ? nil : f
        }
        return (face("a:majorFont"), face("a:minorFont"))
    }

    /// Rewrites every `w:rFonts` under `node` whose ascii/hAnsi face is a
    /// theme reference into the face itself.
    private static func _resolveThemeFonts(_ root: XNode, _ theme: (major: String?, minor: String?)) {
        guard theme.major != nil || theme.minor != nil else { return }
        var stack = [root]   // iterative: a fuzzer's tree is deeper than the call stack
        while let node = stack.popLast() {
            if node.name == "w:rFonts" {
                for (ref, attr) in [("w:asciiTheme", "w:ascii"), ("w:hAnsiTheme", "w:hAnsi")] {
                    guard let t = node.attrs[ref] else { continue }
                    if let face = t.hasPrefix("major") ? theme.major : theme.minor { node.attrs[attr] = face }
                }
            }
            stack.append(contentsOf: node.children)
        }
    }

    /// Parses, and holds no character XML 1.0 forbids (Foundation's parser
    /// lets a stray control byte through; Word and expat do not).
    private static func _wellFormed(_ data: Data) -> Bool {
        if data.contains(where: { $0 < 0x20 && $0 != 0x09 && $0 != 0x0A && $0 != 0x0D }) { return false }
        guard let root = XNode.parse(data) else { return false }
        // Names with an empty prefix or local part (`<a: val=…>`) get past
        // the small parser; a namespace-aware one rejects them.
        func bad(_ n: String) -> Bool { n.isEmpty || n.hasPrefix(":") || n.hasSuffix(":") }
        var stack = [root]
        while let node = stack.popLast() {
            if bad(node.name) || node.attrs.keys.contains(where: bad) { return false }
            stack.append(contentsOf: node.children)
        }
        return true
    }

    /// The parts the writer makes itself; a kept part never overrides one.
    static let _ownParts: Set<String> = [
        "word/document.xml", "word/styles.xml", "word/numbering.xml", "word/settings.xml",
        "word/_rels/document.xml.rels",
    ]

    private static func _paragraphs(_ p: XNode, _ base: RichParagraphStyle,
                                    _ styleIds: [String: String], _ styleNums: [String: (numId: String, ilvl: Int)],
                                    _ sheet: RichStyleSheet,
                                    _ nums: [String: [Int: ListKind]],
                                    _ rels: [String: String], _ media: (String) -> Data?,
                                    _ indent: Double, _ notes: _Shared, _ cellChar: CharStyle = CharStyle()) -> [_Built] {
        var style = base
        var sectionBreakAfter = false
        var markStyle: CharStyle? = nil   // the paragraph mark's look: an empty paragraph's height
        if let pPr = p.first("w:pPr") {
            // The named style's props first, then the paragraph's own.
            if let id = pPr.first("w:pStyle")?["w:val"], let ours = styleIds[id] { sheet.apply(ours, to: &style) }
            _paragraphProps(pPr, into: &style)
            style.indentLeft += indent
            if let rPr = pPr.first("w:rPr"), let rev = rPr.first("w:del") ?? rPr.first("w:ins") {
                style.markRevision = RevisionMark(kind: rev.name == "w:ins" ? .inserted : .deleted,
                                                  author: rev["w:author"] ?? "", date: rev["w:date"] ?? "")
            }
            if let rPr = pPr.first("w:rPr") { markStyle = _charStyle(rPr, base: cellChar) }
            // The paragraph's own numbering, else its style's (a numbered
            // heading style: 65099's "1.1.1 Acronyms").
            var num: (numId: String, ilvl: Int)? = nil
            if let numPr = pPr.first("w:numPr") {
                num = (numPr.first("w:numId")?["w:val"] ?? "", Int(numPr.first("w:ilvl")?["w:val"] ?? "0") ?? 0)
            } else if let id = pPr.first("w:pStyle")?["w:val"], let n = styleNums[id] {
                num = n
            }
            if let (numId, ilvl) = num {
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
            // A section ending here (its sectPr sits in this paragraph's
            // properties) starts the next on a new page unless continuous;
            // the section's own headers and page size are not kept, the
            // break is — Headers.docx had come back as one page of three.
            if let sect = pPr.first("w:sectPr") {
                if (sect.first("w:type")?["w:val"] ?? "nextPage") != "continuous" { sectionBreakAfter = true }
                // The section's own page size, margins and columns, kept
                // for the file (bug65649: 15 sections, some landscape);
                // its header/footer references name parts not kept.
                sect.children.removeAll { $0.name == "w:headerReference" || $0.name == "w:footerReference" }
                style.sectionXML = PptxXML.serialize(sect)
            }
        }

        var built: [_Built] = []
        var text = ""
        var runs: [Run] = []
        var inlineImages: [String: ImageAttachment] = [:]
        func flush(pageBreakAfter: Bool) {
            var para: RichParagraph
            if inlineImages.count == 1, text == RichParagraph.inlineImageCharacter, let only = inlineImages.values.first {
                // A paragraph that is one picture and nothing else: the
                // editor's picture paragraph, with its handles.
                para = RichParagraph(image: only, style: style)
            } else {
                if text.isEmpty, inlineImages.isEmpty, let mark = markStyle {
                    para = RichParagraph(text: "", charStyle: mark, style: style)
                } else {
                    para = RichParagraph(text: text, runs: runs.isEmpty ? nil : runs, style: style)
                }
                para.inlineImages = inlineImages
            }
            para.normalize()
            built.append(_Built(paragraph: para, pageBreakAfter: pageBreakAfter))
            text = ""
            runs = []
            inlineImages = [:]
            style.pageBreakBefore = false
        }
        /// A picture or object in the line, where the text has it.
        func addInline(_ att: ImageAttachment) {
            inlineImages[att.id] = att
            var cs = CharStyle()
            cs.inlineImage = att.id
            addText(RichParagraph.inlineImageCharacter, cs)
        }
        /// A drawing that is not a picture (a chart, a shape, a diagram), an
        /// embedded object, a VML picture: kept as the file wrote it, with
        /// the parts it names, and shown as an empty box of its size.
        func addObject(_ node: XNode) {
            if let att = objectAttachment(node) { addInline(att) }
        }
        /// The kept-verbatim attachment for `node`, or nil when a part it
        /// names is missing.
        func objectAttachment(_ node: XNode) -> ImageAttachment? {
            var w = 300.0, h = 200.0
            if let extent = node.descendant("wp:extent"),
               let cx = Double(extent["cx"] ?? ""), let cy = Double(extent["cy"] ?? ""), cx > 0, cy > 0 {
                w = cx / 12700
                h = cy / 12700
            } else if let shape = node.name == "v:shape" ? node : node.descendant("v:shape"), let st = shape["style"] {
                for pair in st.split(separator: ";") {
                    let kv = pair.split(separator: ":", maxSplits: 1)
                    guard kv.count == 2, let v = _length(String(kv[1])), v > 0 else { continue }
                    if kv[0].trimmingWhitespace() == "width" { w = v } else if kv[0].trimmingWhitespace() == "height" { h = v }
                }
            }
            var found: [KeptRel] = []
            var prefixes = Set<String>()
            var stack = [node]
            while let n = stack.popLast() {
                if let i = n.name.firstIndex(of: ":") { prefixes.insert(String(n.name[..<i])) }
                for (k, v) in n.attrs {
                    if let i = k.firstIndex(of: ":"), !k.hasPrefix("xmlns:") { prefixes.insert(String(k[..<i])) }
                    // mc:Choice Requires="cx" needs cx in scope right there,
                    // not on the element that uses it further down.
                    if k == "Requires" || k == "mc:Ignorable" { for t in v.split(separator: " ") { prefixes.insert(String(t)) } }
                    guard ["r:embed", "r:id", "r:link", "r:pict", "r:href"].contains(k), let rel = notes.rels[v],
                          !found.contains(where: { $0.id == v }) else { continue }
                    found.append(rel)
                    if !rel.external { notes.keep(_resolvePath("word", rel.target)) }
                }
                stack.append(contentsOf: n.children)
            }
            // A part the file names but does not hold (a fuzzer's doing):
            // the object is dropped, as it was before it was kept at all.
            if found.contains(where: { !$0.external && notes.part(_resolvePath("word", $0.target)) == nil }) { return nil }
            // Self-contained markup: every prefix it uses that the document's
            // root declared is declared on it.
            for prefix in prefixes where prefix != "xml" && node.attrs["xmlns:" + prefix] == nil {
                if let uri = notes.rootNS["xmlns:" + prefix] { node.attrs["xmlns:" + prefix] = uri }
            }
            var att = ImageAttachment(data: Data(), width: w, height: h, name: node.name)
            att.sourceXML = PptxXML.serialize(node)
            att.sourceRels = found
            return att
        }
        func addImage(_ drawing: XNode) {
            guard let blip = drawing.descendant("a:blip"), let rid = blip["r:embed"],
                  let target = rels[rid], let data = media(target) else { addObject(drawing); return }
            var w = 300.0, h = 200.0
            if let extent = drawing.descendant("wp:extent"),
               let cx = Double(extent["cx"] ?? ""), let cy = Double(extent["cy"] ?? ""), cx > 0, cy > 0 {
                w = cx / 12700
                h = cy / 12700
            }
            // In the line where the text has it (several to a line, text
            // around them); a paragraph of nothing else becomes the
            // editor's picture paragraph at flush.
            if drawing.first("wp:anchor") != nil, var att = objectAttachment(drawing) {
                // A floating picture: its anchor (position, wrapping,
                // behind the text) is kept as written and saved verbatim —
                // Word then lays it out as the file did (WithGIF's text
                // flowed over its picture; VariousPictures) — while the
                // editor shows the picture in the line.
                att.data = data
                att.name = target.lastPathComponent
                addInline(att)
                return
            }
            addInline(ImageAttachment(data: data, width: w, height: h, name: target.lastPathComponent))
        }
        func addText(_ s: String, _ cs: CharStyle) {
            guard !s.isEmpty else { return }
            text += s
            runs.append(Run(length: s.utf16.count, style: cs))
        }
        var pendingCheckbox: Bool? = nil   // a FORMCHECKBOX field's state, from its begin
        func walkRun(_ r: XNode, link: String?, revision: RevisionMark? = nil) {
            var cs = cellChar
            cs.link = link
            cs.revision = revision
            if let rPr = r.first("w:rPr") { cs = _charStyle(rPr, base: cs) }
            for child in r.children {
                switch child.name {
                case "w:t": addText(child.text, cs)
                case "w:fldChar":
                    // A form checkbox has no result text: it is the box
                    // itself, shown as a glyph (form_footnotes' 29 boxes).
                    if child["w:fldCharType"] == "begin", let box = child.first("w:ffData")?.first("w:checkBox") {
                        let on = box.first("w:checked").map { !_isOff($0) } ?? (box.first("w:default")?["w:val"] == "1")
                        pendingCheckbox = on
                    }
                case "w:instrText":
                    if let on = pendingCheckbox, child.text.uppercased().containsSubstring("FORMCHECKBOX") {
                        addText(on ? "\u{2612}" : "\u{2610}", cs)
                        pendingCheckbox = nil
                    }
                case "w:delText": addText(child.text, cs)
                case "w:tab": addText("\t", cs)
                case "w:br":
                    // A page break ends the paragraph; a line break stays
                    // inside it, as Shift+Return's does — splitting it added a
                    // paragraph (and its spacing) on every soft break.
                    if child["w:type"] == "page" { flush(pageBreakAfter: true) } else { addText("\n", cs) }
                case "w:noBreakHyphen": addText("\u{2011}", cs)
                case "w:softHyphen": addText("\u{00AD}", cs)
                case "w:sym":
                    if let code = child["w:char"], let v = UInt32(code, radix: 16), let sc = UnicodeScalar(v) {
                        addText(String(Character(sc)), cs)
                    }
                case "w:drawing", "w:pict":
                    addImage(child)
                case "w:object", "mc:AlternateContent":
                    addObject(child)
                case "w:footnoteReference", "w:endnoteReference":
                    // The mark: its number as superscript text, tagged with
                    // the note it stands for so the writer puts the
                    // reference back. Word numbers marks in order of
                    // appearance; a custom mark (customMarkFollows) is the
                    // run's own text and needs no number.
                    let footnote = child.name == "w:footnoteReference"
                    guard footnote ? notes.footnotes : notes.endnotes, let id = Int(child["w:id"] ?? "") else { break }
                    var mark = cs
                    mark.script = .superscript
                    mark.note = NoteReference(kind: footnote ? .footnote : .endnote, id: id)
                    if child["w:customMarkFollows"] == "1" || child["w:customMarkFollows"] == "true" {
                        addText("\u{200B}", mark)
                    } else {
                        addText(String(notes.next(footnote: footnote)), mark)
                    }
                default: break
                }
            }
        }
        func walkInline(_ node: XNode, link: String?, revision: RevisionMark? = nil) {
            for child in node.children {
                switch child.name {
                case "w:r": walkRun(child, link: link, revision: revision)
                case "w:hyperlink":
                    let target = child["r:id"].flatMap { rels[$0] } ?? child["w:anchor"].map { "#\($0)" }
                    walkInline(child, link: target, revision: revision)
                case "w:ins", "w:del":
                    // Tracked changes stay tracked: the text with its mark,
                    // written back as the insertion or deletion it was.
                    let mark = RevisionMark(kind: child.name == "w:ins" ? .inserted : .deleted,
                                            author: child["w:author"] ?? "", date: child["w:date"] ?? "")
                    walkInline(child, link: link, revision: mark)
                case "w:smartTag", "w:sdtContent", "w:sdt", "w:fldSimple", "w:customXml":
                    walkInline(child, link: link, revision: revision)
                case "w:pPr", "w:proofErr", "w:bookmarkStart", "w:bookmarkEnd":
                    break
                default: break
                }
            }
        }
        walkInline(p, link: nil)
        if text.isEmpty, inlineImages.isEmpty, let last = built.last, last.pageBreakAfter {
            // The paragraph ended with its page break: Word shows nothing
            // for its mark on the new page (SampleDoc's page two began
            // a line down), so no empty paragraph for it — the break
            // still lands on the next paragraph.
            if sectionBreakAfter { built[built.count - 1].pageBreakAfter = true }
        } else {
            flush(pageBreakAfter: sectionBreakAfter)
        }
        return built
    }

    /// A run's properties (CT_RPr children, in schema order). `under` is
    /// the paragraph style's look: a switch the style turns on and the
    /// run turns off is written as off (drawing.docx's "b w:val=0" runs
    /// under a bold heading 3 came back bold).
    private static func _rPrXML(_ s: CharStyle, under: CharStyle? = nil) -> String {
        var rPr = ""
        func off(_ tag: String, _ styleHas: Bool) -> String { styleHas ? "<w:\(tag) w:val=\"0\"/>" : "" }
    if let family = s.fontFamily {
        let name = OfficeFonts.exportName(family)
        rPr += "<w:rFonts w:ascii=\"\(_esc(name))\" w:hAnsi=\"\(_esc(name))\" w:cs=\"\(_esc(name))\"/>"
    }
    if s.bold { rPr += "<w:b/><w:bCs/>" } else { rPr += off("b", under?.bold ?? false) }
    if s.italic { rPr += "<w:i/><w:iCs/>" } else { rPr += off("i", under?.italic ?? false) }
    if s.caps { rPr += "<w:caps/>" } else { rPr += off("caps", under?.caps ?? false) }
    if s.smallCaps { rPr += "<w:smallCaps/>" } else { rPr += off("smallCaps", under?.smallCaps ?? false) }
    if s.underline { rPr += "<w:u w:val=\"single\"/>" } else if under?.underline ?? false { rPr += "<w:u w:val=\"none\"/>" }
    if s.strikethrough { rPr += "<w:strike/>" } else { rPr += off("strike", under?.strikethrough ?? false) }
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
        return rPr
    }

    /// `<w:pBdr>` for a paragraph's borders: sz in eighths of a point.
    private static func _bordersXML(_ b: ParagraphBorders) -> String {
        func edge(_ name: String, _ l: BorderLine?) -> String {
            guard let l else { return "" }
            let color = l.color.map { _hex($0) } ?? "auto"
            return "<w:\(name) w:val=\"single\" w:sz=\"\(Int((l.width * 8).rounded()))\" w:space=\"\(Int(l.space.rounded()))\" w:color=\"\(color)\"/>"
        }
        return "<w:pBdr>" + edge("top", b.top) + edge("left", b.left) + edge("bottom", b.bottom) + edge("right", b.right) + "</w:pBdr>"
    }

    /// `<w:spacing>` with the style's before, after and line, all of them
    /// (a paragraph that says nothing takes the file's defaults, which
    /// need not be ours). Twips and 240ths, rounded — truncation drifted
    /// 1.08 lines to 258/240 and on down with every save.
    static func _spacingXML(_ s: RichParagraphStyle) -> String {
        var spacing = ""
        if s.spaceBefore > 0 { spacing += " w:before=\"\(Int((s.spaceBefore * 20).rounded()))\"" }
        spacing += " w:after=\"\(Int((s.spaceAfter * 20).rounded()))\""
        if let pts = s.lineHeightPoints {
            spacing += " w:line=\"\(Int((pts * 20).rounded()))\" w:lineRule=\"\(s.lineHeightIsMinimum ? "atLeast" : "exact")\""
        } else {
            spacing += " w:line=\"\(Int((s.lineSpacing * 240).rounded()))\" w:lineRule=\"auto\""
        }
        return "<w:spacing\(spacing)/>"
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
            case "w:caps": cs.caps = !_isOff(child)
            case "w:smallCaps": cs.smallCaps = !_isOff(child)
            case "w:sz": if let v = Double(child["w:val"] ?? "") { cs.fontSize = v / 2 }
            case "w:color":
                if let hex = child["w:val"], hex.lowercased() != "auto", let v = Int(hex, radix: 16) {
                    cs.color = Color(argb: 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF)
                } else if child["w:val"]?.lowercased() == "auto" {
                    // "auto" is the text colour: a style based on a blue
                    // heading that says auto is black (65099's Edf Titre 3).
                    cs.color = nil
                }
            case "w:highlight":
                cs.highlight = _highlight(child["w:val"] ?? "none")
            case "w:shd":
                if let hex = child["w:fill"], hex.lowercased() != "auto", let v = Int(hex, radix: 16), cs.highlight == nil {
                    cs.highlight = Color(argb: 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF)
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

    /// The font name as the file has it. Kept, not mapped: the face it
    /// draws with is `OfficeFonts.substitute`'s choice at render time, and
    /// the name goes back out unchanged on save.
    private static func _family(_ name: String) -> String? {
        let n = name.trimmingWhitespace()
        return n.isEmpty ? nil : n
    }

    // MARK: Writing

    static func write(_ doc: RichDocument, pageSetup: PageSetup) throws -> Data {
        var rels: [(id: String, target: String)] = []
        var media: [ZipEntry] = []
        var mediaRels: [(id: String, target: String)] = []
        var keptRels = "", keptRelCount = 0
        var revisionCount = 0
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
            if let b = p.style.borders { pPr += _bordersXML(b) }
            if p.style.rightToLeft { pPr += "<w:bidi/>" }
            else if p.style.named.flatMap({ doc.styles[$0] })?.paragraph.rightToLeft ?? false { pPr += "<w:bidi w:val=\"0\"/>" }
            if !p.style.tabStops.isEmpty {
                pPr += "<w:tabs>"
                for t in p.style.tabStops {
                    let val = ["left", "center", "right", "decimal"][t.alignment.rawValue]
                    pPr += "<w:tab w:val=\"\(val)\" w:pos=\"\(Int((t.position * 20).rounded()))\"/>"
                }
                pPr += "</w:tabs>"
            }
            // Spacing spelled out on every paragraph, so that Word and we
            // lay the file out alike whatever its defaults say.
            pPr += _spacingXML(p.style)
            // Indents the style sets and the paragraph unsets are written
            // as zero: IllustrativeCases' Body Text Indent hangs 0.75in
            // into the margin and every paragraph of it says left 0.
            let sheetEntry = p.style.heading.flatMap { doc.styles["Heading\(min($0, 6))"] } ?? p.style.named.flatMap { doc.styles[$0] }
            let sp = sheetEntry?.paragraph
            var ind = ""
            if (p.style.indentLeft != 0 || (sp?.indentLeft ?? 0) != 0) && p.style.list == nil { ind += " w:left=\"\(Int(p.style.indentLeft * 20))\"" }
            if p.style.indentRight != 0 || (sp?.indentRight ?? 0) != 0 { ind += " w:right=\"\(Int(p.style.indentRight * 20))\"" }
            if p.style.firstLineIndent > 0 { ind += " w:firstLine=\"\(Int(p.style.firstLineIndent * 20))\"" }
            else if p.style.firstLineIndent < 0 { ind += " w:hanging=\"\(Int(-p.style.firstLineIndent * 20))\"" }
            else if (sp?.firstLineIndent ?? 0) != 0 { ind += " w:firstLine=\"0\" w:hanging=\"0\"" }
            if !ind.isEmpty { pPr += "<w:ind\(ind)/>" }
            switch p.style.alignment {
            case .left:
                // Left under a style that centres has to say so.
                if let a = sheetEntry?.paragraph.alignment, a != .left { pPr += "<w:jc w:val=\"left\"/>" }
            case .center: pPr += "<w:jc w:val=\"center\"/>"
            case .right: pPr += "<w:jc w:val=\"right\"/>"
            case .justify: pPr += "<w:jc w:val=\"both\"/>"
            }
            // The paragraph mark's own run properties: a tracked change to
            // the mark, and — for an empty paragraph — its look, which is
            // what gives the empty line its height (bib-chernigovka's
            // cover: 3,350 such spacers in 11 corpus files).
            var markRPr = ""
            if let rev = p.style.markRevision {
                revisionCount += 1
                let tag = rev.kind == .inserted ? "w:ins" : "w:del"
                markRPr += "<\(tag) w:id=\"\(revisionCount)\" w:author=\"\(_esc(rev.author.isEmpty ? "Author" : rev.author))\"\(rev.date.isEmpty ? "" : " w:date=\"\(_esc(rev.date))\"")/>"
            }
            if p.text.isEmpty, p.image == nil, let first = p.runs.first { markRPr += _rPrXML(first.style) }
            if !markRPr.isEmpty { pPr += "<w:rPr>\(markRPr)</w:rPr>" }
            if let sect = p.style.sectionXML, p.cell == nil, index < doc.paragraphs.count - 1 { pPr += sect }
            body += "<w:p><w:pPr>\(pPr)</w:pPr>"
            /// A picture or kept object as a run's content.
            func drawingXML(_ image: ImageAttachment) -> String {
                if let xml = image.sourceXML {
                    // An object the editor cannot show: the file's own
                    // markup, its relationships under fresh ids.
                    var frag = xml
                    for rel in image.sourceRels {
                        keptRelCount += 1
                        let nid = "rIdKept\(keptRelCount)"
                        for attr in ["r:embed", "r:id", "r:link", "r:pict", "r:href"] {
                            frag = frag.replacingAll("\(attr)=\"\(rel.id)\"", with: "\(attr)=\"\(nid)\"")
                        }
                        keptRels += "<Relationship Id=\"\(nid)\" Type=\"\(_esc(rel.type))\" Target=\"\(_esc(rel.target))\"\(rel.external ? " TargetMode=\"External\"" : "")/>"
                    }
                    return "<w:r>\(frag)</w:r>"
                }
                let n = media.count + 1
                let ext = image.fileExtension
                usedExtensions.insert(ext)
                let name = "image\(n).\(ext)"
                media.append(ZipEntry(name: "word/media/\(name)", data: image.data))
                let rid = "rIdImage\(n)"
                mediaRels.append((rid, "media/\(name)"))
                let cx = Int(image.width * 12700), cy = Int(image.height * 12700)
                return "<w:r><w:drawing><wp:inline distT=\"0\" distB=\"0\" distL=\"0\" distR=\"0\"><wp:extent cx=\"\(cx)\" cy=\"\(cy)\"/><wp:docPr id=\"\(n)\" name=\"Picture \(n)\"/><a:graphic xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\"><a:graphicData uri=\"http://schemas.openxmlformats.org/drawingml/2006/picture\"><pic:pic xmlns:pic=\"http://schemas.openxmlformats.org/drawingml/2006/picture\"><pic:nvPicPr><pic:cNvPr id=\"0\" name=\"\(name)\"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed=\"\(rid)\"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"\(cx)\" cy=\"\(cy)\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r>"
            }
            if let image = p.image {
                body += drawingXML(image) + "</w:p>"
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
                if let id = s.inlineImage, let image = p.inlineImages[id] {
                    body += drawingXML(image)
                    continue
                }
                var rPr = _rPrXML(s, under: sheetEntry?.char)
                if let note = s.note, doc.keptParts[note.kind == .footnote ? "word/footnotes.xml" : "word/endnotes.xml"] != nil {
                    // The mark's number is Word's to show; the run carries
                    // only the reference (and its custom mark text, if any),
                    // with its own look — size and font decide where the
                    // line wraps.
                    let tag = note.kind == .footnote ? "w:footnoteReference" : "w:endnoteReference"
                    let st = note.kind == .footnote ? "FootnoteReference" : "EndnoteReference"
                    let custom = piece.filter { $0 != "\u{200B}" && !$0.isNumber }
                    body += "<w:r><w:rPr><w:rStyle w:val=\"\(st)\"/>\(rPr)</w:rPr>"
                    body += custom.isEmpty ? "<\(tag) w:id=\"\(note.id)\"/>" : "<\(tag) w:customMarkFollows=\"1\" w:id=\"\(note.id)\"/>\(_text(custom))"
                    body += "</w:r>"
                    continue
                }
                var runXML = "<w:r>"
                if s.link != nil { rPr = "<w:rStyle w:val=\"Hyperlink\"/>" + rPr }
                if !rPr.isEmpty { runXML += "<w:rPr>\(rPr)</w:rPr>" }
                if s.revision?.kind == .deleted {
                    runXML += _text(piece).replacingAll("<w:t ", with: "<w:delText ").replacingAll("<w:t>", with: "<w:delText>").replacingAll("</w:t>", with: "</w:delText>")
                } else {
                    runXML += _text(piece)
                }
                runXML += "</w:r>"
                if let rev = s.revision {
                    revisionCount += 1
                    let tag = rev.kind == .inserted ? "w:ins" : "w:del"
                    runXML = "<\(tag) w:id=\"\(revisionCount)\" w:author=\"\(_esc(rev.author.isEmpty ? "Author" : rev.author))\"\(rev.date.isEmpty ? "" : " w:date=\"\(_esc(rev.date))\"")>\(runXML)</\(tag)>"
                }
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
            let style = doc.tableStyles[id] ?? TableStyle()
            var xml = "<w:tbl><w:tblPr><w:tblW w:w=\"0\" w:type=\"auto\"/>"
            switch style.alignment {
            case .center: xml += "<w:jc w:val=\"center\"/>"
            case .right: xml += "<w:jc w:val=\"right\"/>"
            default: break
            }
            if style.indent != 0 { xml += "<w:tblInd w:w=\"\(Int((style.indent * 20).rounded()))\" w:type=\"dxa\"/>" }
            xml += "<w:tblBorders>"
            let borderColor = style.borderColor.map { _hex($0) } ?? "auto"
            for side in ["top", "left", "bottom", "right", "insideH", "insideV"] {
                xml += style.borders ? "<w:\(side) w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"\(borderColor)\"/>"
                                     : "<w:\(side) w:val=\"none\" w:sz=\"0\" w:space=\"0\" w:color=\"auto\"/>"
            }
            xml += "</w:tblBorders>"
            let margins: [(String, Double?)] = [("top", style.cellMarginTop), ("left", style.cellMarginLeft),
                                                ("bottom", style.cellMarginBottom), ("right", style.cellMarginRight)]
            if margins.contains(where: { $0.1 != nil }) {
                xml += "<w:tblCellMar>"
                for (side, v) in margins { if let v { xml += "<w:\(side) w:w=\"\(Int((v * 20).rounded()))\" w:type=\"dxa\"/>" } }
                xml += "</w:tblCellMar>"
            }
            xml += "<w:tblLook w:val=\"04A0\"/></w:tblPr><w:tblGrid>"
            for w in twips { xml += "<w:gridCol w:w=\"\(w)\"/>" }
            xml += "</w:tblGrid>"
            let refs = members.compactMap(\.cell)
            for r in 0 ..< rows {
                var trPr = ""
                if let h = style.rowHeights[r] { trPr += "<w:trHeight w:val=\"\(Int((h * 20).rounded()))\"/>" }
                if r == 0 && style.headerRow { trPr += "<w:tblHeader/>" }
                xml += trPr.isEmpty ? "<w:tr>" : "<w:tr><w:trPr>\(trPr)</w:trPr>"
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
                    if let fill = ref?.fill { xml += "<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"\(_hex(fill))\"/>" }
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
        // Kept header/footer parts: the default ones only while their text
        // is what the editor still shows; the generated ones take a name
        // no kept part uses.
        let keptHF = doc.keptHeaderFooters.enumerated().filter { doc.keptParts[$0.element.part] != nil }.filter { (_, k) in
            k.type != "default" || (k.kind == .header ? doc.header : doc.footer) == k.text
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
        body += "<w:pgSz w:w=\"\(pw)\" w:h=\"\(ph)\"\(pageSetup.isLandscape ? " w:orient=\"landscape\"" : "")/>"
        body += "<w:pgMar w:top=\"\(Int(pageSetup.marginTop * 20))\" w:right=\"\(Int(pageSetup.marginRight * 20))\" w:bottom=\"\(Int(pageSetup.marginBottom * 20))\" w:left=\"\(Int(pageSetup.marginLeft * 20))\" w:header=\"\(Int((pageSetup.headerDistance * 20).rounded()))\" w:footer=\"\(Int((pageSetup.footerDistance * 20).rounded()))\" w:gutter=\"0\"/>"
        if pageSetup.columns > 1 { body += "<w:cols w:num=\"\(pageSetup.columns)\" w:space=\"\(Int(pageSetup.columnGap * 20))\"/>" }
        if doc.titlePage && keptHF.contains(where: { $0.element.type == "first" }) { body += "<w:titlePg/>" }
        body += "</w:sectPr>"

        let ns = "xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" xmlns:wp=\"http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing\" xmlns:mc=\"http://schemas.openxmlformats.org/markup-compatibility/2006\" xmlns:wp14=\"http://schemas.microsoft.com/office/word/2010/wordprocessingDrawing\" xmlns:w14=\"http://schemas.microsoft.com/office/word/2010/wordml\" xmlns:w15=\"http://schemas.microsoft.com/office/word/2012/wordml\" mc:Ignorable=\"w14 w15 wp14\""
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
        relsXML += keptRels
        var extraParts: [ZipEntry] = []
        var extraOverrides = ""
        if writeHeader {
            relsXML += "<Relationship Id=\"rIdHeader\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/header\" Target=\"\(headerName)\"/>"
            extraParts.append(ZipEntry(name: "word/\(headerName)", data: Data(_headerFooterPart("w:hdr", doc.header, center: false, width: pageSetup.contentWidth).utf8)))
            extraOverrides += "<Override PartName=\"/word/\(headerName)\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml\"/>"
        }
        if writeFooter {
            relsXML += "<Relationship Id=\"rIdFooter\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer\" Target=\"\(footerName)\"/>"
            extraParts.append(ZipEntry(name: "word/\(footerName)", data: Data(_headerFooterPart("w:ftr", doc.footer, center: true, width: pageSetup.contentWidth).utf8)))
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
        for (name, data) in doc.keptParts.sorted(by: { $0.key < $1.key }) where !written.contains(name) {
            extraParts.append(ZipEntry(name: name, data: data))
            switch name {
            case "word/footnotes.xml":
                relsXML += "<Relationship Id=\"rIdFootnotes\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/footnotes\" Target=\"footnotes.xml\"/>"
                extraOverrides += "<Override PartName=\"/word/footnotes.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.footnotes+xml\"/>"
            case "word/endnotes.xml":
                relsXML += "<Relationship Id=\"rIdEndnotes\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/endnotes\" Target=\"endnotes.xml\"/>"
                extraOverrides += "<Override PartName=\"/word/endnotes.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.endnotes+xml\"/>"
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
        var settings = doc.evenAndOddHeaders && keptHF.contains(where: { $0.element.type == "even" })
            ? _settingsPart.replacingAll("<w:defaultTabStop", with: "<w:evenAndOddHeaders/><w:defaultTabStop") : _settingsPart
        if let compat = doc.keptCompat, let start = settings.range(of: "<w:compat>"), let end = settings.range(of: "</w:compat>") {
            // The file's own compatibility mode and switches: Word 2007 and
            // 2010 files (a third of the corpus) break lines and space
            // tables by their mode's rules, and a copy that said 15 did not.
            settings.replaceSubrange(start.lowerBound ..< end.upperBound, with: compat)
        }
        extraParts.append(ZipEntry(name: "word/settings.xml", data: Data(settings.utf8)))
        extraOverrides += "<Override PartName=\"/word/settings.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml\"/>"
        relsXML += "</Relationships>"
        var contentTypes = _contentTypes.replacingAll("</Types>", with: extraOverrides + "</Types>")
        for ext in usedExtensions.sorted() {
            let mime = _imageMime(ext)
            contentTypes = contentTypes.replacingAll("<Override PartName=\"/word/document.xml\"",
                                                             with: "<Default Extension=\"\(ext)\" ContentType=\"\(mime)\"/><Override PartName=\"/word/document.xml\"")
        }

        let entries: [ZipEntry] = [
            ZipEntry(name: "[Content_Types].xml", data: Data(contentTypes.utf8)),
            ZipEntry(name: "_rels/.rels", data: Data(_rootRels.utf8)),
            ZipEntry(name: "word/document.xml", data: Data(document.utf8)),
            ZipEntry(name: "word/styles.xml", data: Data(_stylesPart(doc.styles, notes: !doc.keptParts.isEmpty).utf8)),
            ZipEntry(name: "word/numbering.xml", data: Data(_numberingPart(numKinds, numFormats, bulletId: bulletId, decimalId: decimalId).utf8)),
            ZipEntry(name: "word/_rels/document.xml.rels", data: Data(relsXML.utf8)),
        ] + media + extraParts
        return try Zip.write(entries)
    }

    private static func _imageMime(_ ext: String) -> String {
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
    private static func _headerFooterPart(_ tag: String, _ template: String, center: Bool, width: Double) -> String {
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
        let tabbed = template.contains("\t")
        let jc = tabbed
            ? "<w:pPr><w:tabs><w:tab w:val=\"center\" w:pos=\"\(Int((width * 10).rounded()))\"/><w:tab w:val=\"right\" w:pos=\"\(Int((width * 20).rounded()))\"/></w:tabs></w:pPr>"
            : (center ? "<w:pPr><w:jc w:val=\"center\"/></w:pPr>" : "")
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
        String(printf: "%06X", c.value & 0xFFFFFF)
    }

    private static let _settingsPart = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:defaultTabStop w:val="720"/><w:characterSpacingControl w:val="doNotCompress"/><w:compat><w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="15"/></w:compat></w:settings>
    """

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
    private static func _stylesPart(_ sheet: RichStyleSheet, notes: Bool = false) -> String {
        var out = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
        // The document defaults are Normal's look (the file's, when it was
        // read from one): Calibri 11 only for a document that never said.
        let normal = sheet[RichNamedStyle.normalId]?.char ?? CharStyle()
        let defaultFont = _esc(OfficeFonts.exportName(normal.fontFamily ?? "Calibri"))
        let defaultSize = Int(((normal.fontSize ?? 11) * 2).rounded())
        out += "<w:styles xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii=\"\(defaultFont)\" w:hAnsi=\"\(defaultFont)\" w:cs=\"\(defaultFont)\" w:eastAsia=\"\(defaultFont)\"/><w:sz w:val=\"\(defaultSize)\"/><w:szCs w:val=\"\(defaultSize)\"/><w:lang w:val=\"en-US\"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after=\"160\" w:line=\"259\" w:lineRule=\"auto\"/></w:pPr></w:pPrDefault></w:docDefaults>"
        out += "<w:style w:type=\"paragraph\" w:default=\"1\" w:styleId=\"Normal\"><w:name w:val=\"Normal\"/><w:qFormat/></w:style>"
        for entry in sheet.styles where entry.id != RichNamedStyle.normalId {
            let name = entry.paragraph.heading.map { "heading \($0)" } ?? entry.name
            out += "<w:style w:type=\"paragraph\" w:styleId=\"\(_esc(entry.id))\"><w:name w:val=\"\(_esc(name))\"/><w:basedOn w:val=\"Normal\"/>"
            if let next = entry.next { out += "<w:next w:val=\"\(_esc(next))\"/>" }
            out += "<w:qFormat/><w:pPr>"
            if entry.paragraph.heading != nil { out += "<w:keepNext/>" }
            if entry.paragraph.rightToLeft { out += "<w:bidi/>" }
            out += _spacingXML(entry.paragraph)
            var ind = ""
            if entry.paragraph.indentLeft != 0 { ind += " w:left=\"\(Int(entry.paragraph.indentLeft * 20))\"" }
            if entry.paragraph.indentRight != 0 { ind += " w:right=\"\(Int(entry.paragraph.indentRight * 20))\"" }
            if entry.paragraph.firstLineIndent > 0 { ind += " w:firstLine=\"\(Int(entry.paragraph.firstLineIndent * 20))\"" }
            if entry.paragraph.firstLineIndent < 0 { ind += " w:hanging=\"\(Int(-entry.paragraph.firstLineIndent * 20))\"" }
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
                let f = OfficeFonts.exportName(family)
                out += "<w:rFonts w:ascii=\"\(_esc(f))\" w:hAnsi=\"\(_esc(f))\" w:cs=\"\(_esc(f))\"/>"
            }
            if entry.char.bold { out += "<w:b/><w:bCs/>" }
            if entry.char.italic { out += "<w:i/><w:iCs/>" }
            if entry.char.caps { out += "<w:caps/>" }
            if entry.char.smallCaps { out += "<w:smallCaps/>" }
            if let c = entry.char.color { out += "<w:color w:val=\"\(_hex(c))\"/>" }
            if let size = entry.char.fontSize { out += "<w:sz w:val=\"\(Int(size * 2))\"/><w:szCs w:val=\"\(Int(size * 2))\"/>" }
            out += "</w:rPr></w:style>"
        }
        out += "<w:style w:type=\"paragraph\" w:styleId=\"ListParagraph\"><w:name w:val=\"List Paragraph\"/><w:basedOn w:val=\"Normal\"/><w:qFormat/><w:pPr><w:ind w:left=\"720\"/><w:contextualSpacing/></w:pPr></w:style>"
        out += "<w:style w:type=\"character\" w:styleId=\"Hyperlink\"><w:name w:val=\"Hyperlink\"/><w:rPr><w:color w:val=\"0563C1\"/><w:u w:val=\"single\"/></w:rPr></w:style>"
        if notes {
            // The marks and the notes' own paragraphs, Word's defaults;
            // a file that defined its own note text style keeps it above.
            for kind in ["Footnote", "Endnote"] {
                out += "<w:style w:type=\"character\" w:styleId=\"\(kind)Reference\"><w:name w:val=\"\(kind.lowercased()) reference\"/><w:rPr><w:vertAlign w:val=\"superscript\"/></w:rPr></w:style>"
                if sheet["\(kind)Text"] == nil {
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
    private static func _numberingPart(_ kinds: [Int: ListKind], _ formats: [Int: [Int: ListLevelFormat]],
                                       bulletId: Int, decimalId: Int) -> String {
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
        for numId in kinds.keys.sorted() where numId != bulletId && numId != decimalId {
            let abstractId = numId + 1
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
        return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<w:numbering xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:abstractNum w:abstractNumId=\"0\"><w:multiLevelType w:val=\"hybridMultilevel\"/>\(bulletLevels)</w:abstractNum><w:abstractNum w:abstractNumId=\"1\"><w:multiLevelType w:val=\"hybridMultilevel\"/>\(decimalLevels)</w:abstractNum>\(extraAbstract)<w:num w:numId=\"\(bulletId)\"><w:abstractNumId w:val=\"0\"/></w:num><w:num w:numId=\"\(decimalId)\"><w:abstractNumId w:val=\"1\"/></w:num>\(extraNums)</w:numbering>"
    }
}
