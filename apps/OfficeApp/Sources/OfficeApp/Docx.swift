// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// .docx — WordprocessingML in a zip. The reader covers what the document
// model can hold: paragraphs with runs (bold, italic, underline, strike,
// size, colour, highlight, font, sub/superscript, hyperlinks), paragraph
// alignment, indents, spacing, headings via the style table, lists via the
// numbering table, page breaks, and the section's paper size and margins.
// Tables are flattened to their cells' paragraphs and images are skipped
// until the model has them. The writer emits a minimal package (document,
// styles, numbering, relationships) that Word, LibreOffice and macOS all
// open.

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

        // Styles: which paragraph styles are headings.
        var headingByStyle: [String: Int] = [:]
        if let stylesData = part("word/styles.xml"), let styles = XNode.parse(stylesData) {
            for style in styles.all("w:style") where style["w:type"] == "paragraph" {
                guard let id = style["w:styleId"] else { continue }
                let name = (style.first("w:name")?["w:val"] ?? id).lowercased()
                if let level = _headingLevel(name) ?? _headingLevel(id.lowercased()) {
                    headingByStyle[id] = level
                }
            }
        }

        // Numbering: numId → level → bullet/decimal.
        var kindByNum: [String: [Int: ListKind]] = [:]
        if let numData = part("word/numbering.xml"), let numbering = XNode.parse(numData) {
            var abstract: [String: [Int: ListKind]] = [:]
            for a in numbering.all("w:abstractNum") {
                guard let id = a["w:abstractNumId"] else { continue }
                var levels: [Int: ListKind] = [:]
                for lvl in a.all("w:lvl") {
                    let ilvl = Int(lvl["w:ilvl"] ?? "0") ?? 0
                    let fmt = lvl.first("w:numFmt")?["w:val"] ?? "decimal"
                    levels[ilvl] = fmt == "bullet" ? .bullet : .numbered
                }
                abstract[id] = levels
            }
            for n in numbering.all("w:num") {
                guard let id = n["w:numId"], let aid = n.first("w:abstractNumId")?["w:val"] else { continue }
                kindByNum[id] = abstract[aid] ?? [:]
            }
        }

        // Relationships: hyperlink targets.
        var rels: [String: String] = [:]
        if let relData = part("word/_rels/document.xml.rels"), let relRoot = XNode.parse(relData) {
            for r in relRoot.all("Relationship") {
                if let id = r["Id"], let target = r["Target"] { rels[id] = target }
            }
        }

        guard let body = root.first("w:body") else { throw DocxError.badXML("no w:body") }
        var paragraphs: [RichParagraph] = []
        var pageSetup: PageSetup? = nil
        var pendingPageBreak = false

        func emit(_ p: RichParagraph) {
            var p = p
            if pendingPageBreak { p.style.pageBreakBefore = true; pendingPageBreak = false }
            paragraphs.append(p)
        }

        func walkBlock(_ node: XNode, indent: Double) {
            switch node.name {
            case "w:p":
                for p in _paragraphs(node, headingByStyle, kindByNum, rels, indent) {
                    if p.pageBreakAfter { emit(p.paragraph); pendingPageBreak = true } else { emit(p.paragraph) }
                }
            case "w:tbl":
                // Flatten: each cell's paragraphs, indented, until tables exist.
                for tr in node.all("w:tr") {
                    for tc in tr.all("w:tc") {
                        for child in tc.children { walkBlock(child, indent: indent + 18) }
                    }
                }
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
        if paragraphs.isEmpty { paragraphs = [RichParagraph()] }
        return DocxDocument(document: RichDocument(paragraphs: paragraphs), pageSetup: pageSetup)
    }

    private static func _headingLevel(_ name: String) -> Int? {
        if name == "title" { return 1 }
        for level in 1 ... 6 where name == "heading \(level)" || name == "heading\(level)" { return level }
        return nil
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
        return setup
    }

    private struct _Built {
        var paragraph: RichParagraph
        var pageBreakAfter: Bool
    }

    /// One w:p can become several paragraphs (a page break inside it).
    private static func _paragraphs(_ p: XNode, _ headings: [String: Int], _ nums: [String: [Int: ListKind]],
                                    _ rels: [String: String], _ indent: Double) -> [_Built] {
        var style = RichParagraphStyle.body
        style.indentLeft = indent
        if let pPr = p.first("w:pPr") {
            if let id = pPr.first("w:pStyle")?["w:val"], let level = headings[id] { style.heading = level }
            switch pPr.first("w:jc")?["w:val"] {
            case "center": style.alignment = .center
            case "right", "end": style.alignment = .right
            case "both", "distribute": style.alignment = .justify
            default: break
            }
            if let ind = pPr.first("w:ind") {
                if let v = Double(ind["w:left"] ?? ind["w:start"] ?? "") { style.indentLeft += v / 20 }
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
            if let numPr = pPr.first("w:numPr") {
                let ilvl = Int(numPr.first("w:ilvl")?["w:val"] ?? "0") ?? 0
                let numId = numPr.first("w:numId")?["w:val"] ?? ""
                if numId != "0" {
                    style.list = nums[numId]?[ilvl] ?? nums[numId]?[0] ?? .bullet
                    style.listLevel = min(8, ilvl)
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
        flush(pageBreakAfter: false)
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
        func relId(for link: String) -> String {
            if let r = rels.first(where: { $0.target == link }) { return r.id }
            let id = "rIdLink\(rels.count + 1)"
            rels.append((id, link))
            return id
        }

        var body = ""
        for p in doc.paragraphs {
            var pPr = ""
            if let h = p.style.heading { pPr += "<w:pStyle w:val=\"Heading\(min(h, 6))\"/>" }
            if p.style.list != nil { pPr += "<w:pStyle w:val=\"ListParagraph\"/>" }
            if p.style.pageBreakBefore { pPr += "<w:pageBreakBefore/>" }
            if let list = p.style.list {
                pPr += "<w:numPr><w:ilvl w:val=\"\(p.style.listLevel)\"/><w:numId w:val=\"\(list == .bullet ? 1 : 2)\"/></w:numPr>"
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
        }
        let pw = Int(pageSetup.width * 20), ph = Int(pageSetup.height * 20)
        body += "<w:sectPr><w:pgSz w:w=\"\(pw)\" w:h=\"\(ph)\"\(pageSetup.isLandscape ? " w:orient=\"landscape\"" : "")/>"
        body += "<w:pgMar w:top=\"\(Int(pageSetup.marginTop * 20))\" w:right=\"\(Int(pageSetup.marginRight * 20))\" w:bottom=\"\(Int(pageSetup.marginBottom * 20))\" w:left=\"\(Int(pageSetup.marginLeft * 20))\" w:header=\"708\" w:footer=\"708\" w:gutter=\"0\"/></w:sectPr>"

        let ns = "xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\""
        let document = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<w:document \(ns)><w:body>\(body)</w:body></w:document>"

        var relsXML = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
        relsXML += "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>"
        relsXML += "<Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering\" Target=\"numbering.xml\"/>"
        for r in rels {
            relsXML += "<Relationship Id=\"\(r.id)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink\" Target=\"\(_esc(r.target))\" TargetMode=\"External\"/>"
        }
        relsXML += "</Relationships>"

        let entries: [ZipEntry] = [
            ZipEntry(name: "[Content_Types].xml", data: Data(_contentTypes.utf8)),
            ZipEntry(name: "_rels/.rels", data: Data(_rootRels.utf8)),
            ZipEntry(name: "word/document.xml", data: Data(document.utf8)),
            ZipEntry(name: "word/styles.xml", data: Data(_styles.utf8)),
            ZipEntry(name: "word/numbering.xml", data: Data(_numbering.utf8)),
            ZipEntry(name: "word/_rels/document.xml.rels", data: Data(relsXML.utf8)),
        ]
        return try Zip.write(entries)
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

    private static let _styles = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:cs="Arial" w:eastAsia="Arial"/><w:sz w:val="22"/><w:szCs w:val="22"/><w:lang w:val="en-US"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="160" w:line="259" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style><w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:keepNext/><w:spacing w:before="240" w:after="80"/><w:outlineLvl w:val="0"/></w:pPr><w:rPr><w:b/><w:color w:val="2F5496"/><w:sz w:val="40"/><w:szCs w:val="40"/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:keepNext/><w:spacing w:before="160" w:after="80"/><w:outlineLvl w:val="1"/></w:pPr><w:rPr><w:b/><w:color w:val="2F5496"/><w:sz w:val="32"/><w:szCs w:val="32"/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="Heading3"><w:name w:val="heading 3"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:keepNext/><w:spacing w:before="160" w:after="80"/><w:outlineLvl w:val="2"/></w:pPr><w:rPr><w:b/><w:color w:val="2F5496"/><w:sz w:val="28"/><w:szCs w:val="28"/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="Heading4"><w:name w:val="heading 4"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:pPr><w:keepNext/><w:outlineLvl w:val="3"/></w:pPr><w:rPr><w:b/><w:i/><w:color w:val="2F5496"/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="Heading5"><w:name w:val="heading 5"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:pPr><w:keepNext/><w:outlineLvl w:val="4"/></w:pPr><w:rPr><w:color w:val="2F5496"/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="Heading6"><w:name w:val="heading 6"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:pPr><w:keepNext/><w:outlineLvl w:val="5"/></w:pPr><w:rPr><w:i/><w:color w:val="2F5496"/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="ListParagraph"><w:name w:val="List Paragraph"/><w:basedOn w:val="Normal"/><w:qFormat/><w:pPr><w:ind w:left="720"/><w:contextualSpacing/></w:pPr></w:style><w:style w:type="character" w:styleId="Hyperlink"><w:name w:val="Hyperlink"/><w:rPr><w:color w:val="0563C1"/><w:u w:val="single"/></w:rPr></w:style></w:styles>
    """

    private static let _numbering: String = {
        var bulletLevels = ""
        var decimalLevels = ""
        let bullets = ["\u{2022}", "o", "\u{25AA}"]
        for i in 0 ..< 9 {
            let left = 720 * (i + 1)
            bulletLevels += "<w:lvl w:ilvl=\"\(i)\"><w:start w:val=\"1\"/><w:numFmt w:val=\"bullet\"/><w:lvlText w:val=\"\(bullets[i % 3])\"/><w:lvlJc w:val=\"left\"/><w:pPr><w:ind w:left=\"\(left)\" w:hanging=\"360\"/></w:pPr>\(i % 3 == 1 ? "<w:rPr><w:rFonts w:ascii=\"Courier New\" w:hAnsi=\"Courier New\"/></w:rPr>" : "")</w:lvl>"
            let fmt = ["decimal", "lowerLetter", "lowerRoman"][i % 3]
            decimalLevels += "<w:lvl w:ilvl=\"\(i)\"><w:start w:val=\"1\"/><w:numFmt w:val=\"\(fmt)\"/><w:lvlText w:val=\"%\(i + 1).\"/><w:lvlJc w:val=\"left\"/><w:pPr><w:ind w:left=\"\(left)\" w:hanging=\"360\"/></w:pPr></w:lvl>"
        }
        return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<w:numbering xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:abstractNum w:abstractNumId=\"0\"><w:multiLevelType w:val=\"hybridMultilevel\"/>\(bulletLevels)</w:abstractNum><w:abstractNum w:abstractNumId=\"1\"><w:multiLevelType w:val=\"hybridMultilevel\"/>\(decimalLevels)</w:abstractNum><w:num w:numId=\"1\"><w:abstractNumId w:val=\"0\"/></w:num><w:num w:numId=\"2\"><w:abstractNumId w:val=\"1\"/></w:num></w:numbering>"
    }()
}
