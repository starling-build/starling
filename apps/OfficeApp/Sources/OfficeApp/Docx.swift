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
    /// Every descendant by name, depth first.
    func descendants(_ name: String) -> [XNode] { children.flatMap { ($0.name == name ? [$0] : []) + $0.descendants(name) } }

    /// The tree with each name in a namespace of `prefixes` (by URI) under
    /// that prefix, whatever the file called it; the rest as they were.
    func withPrefixes(_ prefixes: [String: String], scope: [String: String] = [:]) -> XNode {
        var scope = scope
        for (k, v) in attrs {
            if k == "xmlns" { scope[""] = v } else if k.hasPrefix("xmlns:") { scope[String(k.dropFirst(6))] = v }
        }
        func renamed(_ n: String, element: Bool) -> String {
            let colon = n.firstIndex(of: ":")
            let prefix = colon.map { String(n[..<$0]) } ?? ""
            // (An attribute without a prefix is in no namespace.)
            guard element || colon != nil, prefix != "xmlns", let uri = scope[prefix], let p = prefixes[uri] else { return n }
            return p + ":" + (colon.map { String(n[n.index(after: $0)...]) } ?? n)
        }
        var renamedAttrs: [String: String] = [:]
        for (k, v) in attrs { renamedAttrs[k.hasPrefix("xmlns") ? k : renamed(k, element: false)] = v }
        let node = XNode(name: renamed(name, element: true), attrs: renamedAttrs)
        node.text = text
        node.children = children.map { $0.withPrefixes(prefixes, scope: scope) }
        return node
    }
    var has: (String) -> Bool { { self.first($0) != nil } }

    /// The system's parser, with prefixes kept ("w:p") — which is what the
    /// OOXML parts use consistently and saves resolving namespaces. What
    /// `parse` falls back on.
    static func parseSystem(_ data: Data) -> XNode? {
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
        if parser.parse() { return builder.root }
        #if canImport(FoundationXML)
        // libxml2 off a Mac gives up on a part past 10 MB (a 12 MB
        // document.xml: bug65649), where the Mac's reads it.
        if data.count > 10_000_000 { return MiniXML.parse([UInt8](data)) }
        #endif
        return nil
        #endif
    }

    /// A part as a tree: by this app's own reader where it can read the
    /// part, and by the system's where it cannot — a part that is not
    /// UTF-8 (a byte order mark of UTF-16, or a declaration naming another
    /// encoding), or one it makes nothing of. About twice as fast as the
    /// system's parser on a Mac, where every element's attributes cross
    /// into Swift as a bridged dictionary — half of what opening a deck
    /// cost, and most of opening a large workbook.
    static func parse(_ data: Data) -> XNode? {
        #if os(WASI)
        return parseSystem(data)
        #else
        if _systemOnly { return parseSystem(data) }
        let bytes = [UInt8](data)
        if _plainUTF8(bytes), let root = MiniXML.parse(bytes) { return root }
        return parseSystem(data)
        #endif
    }

    /// A part whose bulk is one long list under its root — a sheet's rows:
    /// the tree with that list's parent left empty, and the items one at a
    /// time, each built, handed over and let go. A million cells as a tree
    /// are several million objects held at once; this way there is a row
    /// of them. (Where the system's parser has to read the part, it is
    /// the whole tree after all, taken apart afterwards.)
    struct ListPart {
        let root: XNode
        let forEach: ((XNode) -> Void) -> Void
    }

    static func parse(_ data: Data, listUnder parent: String, of item: String) -> ListPart? {
        let bytes = [UInt8](data)
        var own = true
        #if !os(WASI)
        own = !_systemOnly && _plainUTF8(bytes)
        #endif
        if own, let root = MiniXML.parse(bytes, emptying: parent) {
            return ListPart(root: root) { each in MiniXML.children(named: item, ofRootChild: parent, in: bytes, each) }
        }
        guard let root = parseSystem(data) else { return nil }
        let isNamed: (XNode, String) -> Bool = { $0.name == $1 || $0.name.hasSuffix(":" + $1) }
        var items: [XNode] = []
        if let list = root.children.first(where: { isNamed($0, parent) }) {
            items = list.children.filter { isNamed($0, item) }
            list.children = []
        }
        return ListPart(root: root) { each in items.forEach(each) }
    }

    /// `OFFICE_XML=system` reads everything with the system's parser: the
    /// other side of a comparison when the two are suspected to differ.
    private static let _systemOnly = ProcessInfo.processInfo.environment["OFFICE_XML"] == "system"

    /// Whether this app's own reader can take the part.
    private static func _plainUTF8(_ b: [UInt8]) -> Bool {
        if b.count >= 2, (b[0] == 0xFE && b[1] == 0xFF) || (b[0] == 0xFF && b[1] == 0xFE) || b[0] == 0 || b[1] == 0 { return false }
        // <?xml version="1.0" encoding="…"?> is all there is to look at.
        let head = b.prefix(512).map { $0 >= 0x41 && $0 <= 0x5A ? $0 + 0x20 : $0 }
        func find(_ word: String, from: Int = 0) -> Int? {
            let w = Array(word.utf8)
            guard head.count >= w.count else { return nil }
            for k in from ... head.count - w.count where head[k ..< k + w.count].elementsEqual(w) { return k + w.count }
            return nil
        }
        // A document type declaration can define entities, and this app's
        // reader knows the five predefined ones: the system's parser reads
        // those parts (and refuses the ones that are a bomb).
        if find("<!doctype") != nil { return false }
        guard let xml = find("<?xml"), xml <= 8, let e = find("encoding", from: xml) else { return true }
        return find("utf-8", from: e) != nil || find("utf8", from: e) != nil || find("us-ascii", from: e) != nil
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

        // A CDATA section is text. The Mac's parser hands it to
        // `foundCharacters` when this is not implemented; FoundationXML
        // off a Mac drops it.
        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            stack.last?.text += String(decoding: CDATABlock, as: UTF8.self)
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

    /// Word's drop caps. A paragraph holding only `w:framePr w:dropCap="drop"`
    /// (`w:lines` of them) and the letters it drops, on an exact line of
    /// the lines' height, goes before the paragraph it is the first of; the
    /// drop is a box at that paragraph's left, the letters in it at the size
    /// Word sets them in (the lines' height over the text's, by the face's
    /// cap height) and on the last of those lines' baseline, the text round
    /// it as round a square-wrapped box. Here the box is written into
    /// the paragraph after it — the reader reads it as any anchored text
    /// box — and the paragraph itself is dropped from the body. (lo
    /// tdf150438: Word's print sets 53pt "“" in 11pt text three lines
    /// deep, its baseline the third line's, the lines beside it 23.5pt in;
    /// ours set it on a line of its own.)
    static func _foldDropCaps(_ root: XNode) {
        // (The text's room: the section's page less its margins, in points.)
        var column = 451.0
        if let sect = root.first("w:body")?.descendants("w:sectPr").last, let sz = sect.first("w:pgSz"), let mar = sect.first("w:pgMar"),
           let w = Double(sz["w:w"] ?? ""), let l = Double(mar["w:left"] ?? ""), let r = Double(mar["w:right"] ?? "") {
            column = (w - l - r - (Double(mar["w:gutter"] ?? "") ?? 0)) / 20
        }
        /// The em-widths of a text in Times-like faces, roughly (the
        /// drop's own width and whether its paragraph is all beside it).
        func em(_ text: String) -> Double {
            text.unicodeScalars.reduce(0) { total, c in
                switch c.value {
                case 0x20: return total + 0.25
                case 0x201C, 0x201D: return total + 0.444
                case 0x2018, 0x2019: return total + 0.333
                case 0x2D, 0x2013: return total + (c.value == 0x2D ? 0.333 : 0.5)
                case 0x2E80...: return total + 1
                case 0x41...0x5A: return total + 0.7
                default: return total + 0.46
                }
            }
        }
        func fold(_ parent: XNode, top: Bool) {
            var out: [XNode] = []
            var i = 0
            let kids = parent.children
            while i < kids.count {
                let p = kids[i]
                if p.name == "w:p", i + 1 < kids.count, kids[i + 1].name == "w:p",
                   let pPr = p.first("w:pPr"), let frame = pPr.first("w:framePr"), frame["w:dropCap"] == "drop",
                   let lines = Double(frame["w:lines"] ?? ""), lines >= 2,
                   let spacing = pPr.first("w:spacing"), spacing["w:lineRule"] == "exact", let line = Double(spacing["w:line"] ?? ""), line > 0,
                   p.children.filter({ $0.name == "w:r" }).count == 1, p.children.filter({ $0.name != "w:pPr" && $0.name != "w:r" }).isEmpty,
                   let run = p.first("w:r"), let t = run.first("w:t"), !t.text.isEmpty,
                   case let host = kids[i + 1], host.first("w:pPr")?.first("w:framePr") == nil {
                    let height = line / 20                      // points: the lines' height
                    let pitch = height / lines
                    // (Word's size: the lines above the last, over the face's
                    // cap height, and the text's own cap height on top.)
                    let capHeight = 0.655
                    var hostSize = 11.0
                    if let r = host.children.first(where: { $0.name == "w:r" }),
                       let sz = r.first("w:rPr")?.first("w:sz")?["w:val"].flatMap(Double.init) { hostSize = sz / 2 }
                    let size = hostSize + (lines - 1) * pitch / capHeight
                    let capWidth = em(t.text) * size
                    // (Word sets only the drop's lines narrower; this takes a
                    // paragraph that is all of them, and leaves the rest as
                    // they were: the engine does not set lines beside a box.)
                    let hostText = host.descendants("w:t").map(\.text).joined()
                    guard em(hostText) * hostSize <= (column - capWidth) * (lines - 0.35) else {
                        out.append(p); i += 1; continue
                    }
                    let halfPoints = Int((size * 2).rounded())
                    let baseline = height - 0.25 * pitch        // the last line's baseline, from the box's top
                    let exact = Int((baseline / 0.905 * 20).rounded())
                    let rPrInner = (run.first("w:rPr")?.children ?? []).filter { $0.name != "w:sz" && $0.name != "w:szCs" }
                        .map { PptxXML.serialize($0) }.joined()
                    let esc = t.text.replacingAll("&", with: "&amp;").replacingAll("<", with: "&lt;")
                    let emu = Int(height * 12700)
                    let ns = "xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" xmlns:wp=\"http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:wps=\"http://schemas.microsoft.com/office/word/2010/wordprocessingShape\""
                    let xml = "<w:r \(ns)><w:drawing><wp:anchor distT=\"0\" distB=\"0\" distL=\"0\" distR=\"\(Int((Double(frame["w:hSpace"] ?? "") ?? 0) / 20 * 12700))\" simplePos=\"0\" relativeHeight=\"0\" behindDoc=\"0\" locked=\"0\" layoutInCell=\"1\" allowOverlap=\"1\"><wp:simplePos x=\"0\" y=\"0\"/><wp:positionH relativeFrom=\"column\"><wp:posOffset>0</wp:posOffset></wp:positionH><wp:positionV relativeFrom=\"paragraph\"><wp:posOffset>0</wp:posOffset></wp:positionV><wp:extent cx=\"\(emu)\" cy=\"\(emu)\"/><wp:effectExtent l=\"0\" t=\"0\" r=\"0\" b=\"0\"/><wp:wrapSquare wrapText=\"bothSides\"/><wp:docPr id=\"1\" name=\"Drop cap\"/><wp:cNvGraphicFramePr/><a:graphic><a:graphicData uri=\"http://schemas.microsoft.com/office/word/2010/wordprocessingShape\"><wps:wsp><wps:cNvSpPr txBox=\"1\"/><wps:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"\(emu)\" cy=\"\(emu)\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom><a:noFill/><a:ln><a:noFill/></a:ln></wps:spPr><wps:txbx><w:txbxContent><w:p><w:pPr><w:spacing w:before=\"0\" w:after=\"0\" w:line=\"\(exact)\" w:lineRule=\"exact\"/></w:pPr><w:r><w:rPr>\(rPrInner)<w:sz w:val=\"\(halfPoints)\"/><w:szCs w:val=\"\(halfPoints)\"/></w:rPr><w:t xml:space=\"preserve\">\(esc)</w:t></w:r></w:p></w:txbxContent></wps:txbx><wps:bodyPr wrap=\"none\" lIns=\"0\" tIns=\"0\" rIns=\"0\" bIns=\"0\" anchor=\"t\"><a:spAutoFit/></wps:bodyPr></wps:wsp></a:graphicData></a:graphic></wp:anchor></w:drawing></w:r>"
                    if let drawing = XNode.parse(Data(xml.utf8)) {
                        let at = host.children.firstIndex(where: { $0.name != "w:pPr" }) ?? host.children.count
                        host.children.insert(drawing, at: at)
                        let left = Int((capWidth + (Double(frame["w:hSpace"] ?? "") ?? 0) / 20) * 20)
                        let hostPr = host.first("w:pPr") ?? { let n = XNode(name: "w:pPr", attrs: [:]); host.children.insert(n, at: 0); return n }()
                        if let ind = hostPr.first("w:ind") { ind.attrs["w:left"] = String((Int(ind["w:left"] ?? "") ?? 0) + left); ind.attrs["w:start"] = nil }
                        else { hostPr.children.append(XNode(name: "w:ind", attrs: ["w:left": String(left)])) }
                        out.append(host)
                        i += 2
                        continue
                    }
                }
                out.append(p)
                i += 1
            }
            parent.children = out
        }
        if let body = root.first("w:body") { fold(body, top: true) }
    }

    /// A package whose main part is not named `word/document.xml`: the root
    /// relationships say which it is (LibreOffice's tdf104713_undefinedStyles
    /// names `word/trial.xml`), and it and its relationships file are read
    /// under the usual names. Only a main part in `word/`, whose relative
    /// targets are then the same; any other package is left as it is.
    static func _withStandardMainPart(_ entries: [ZipEntry]) -> [ZipEntry] {
        guard !entries.contains(where: { $0.name == "word/document.xml" }),
              let root = entries.first(where: { $0.name == "_rels/.rels" }).flatMap({ XNode.parse($0.data) }),
              let rel = root.all("Relationship").first(where: { ($0["Type"] ?? "").hasSuffix("/officeDocument") && $0["TargetMode"] != "External" }),
              var main = rel["Target"] else { return entries }
        if main.hasPrefix("/") { main.removeFirst() }
        let parts = main.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0] == "word", entries.contains(where: { $0.name == main }) else { return entries }
        return entries.map { e in
            if e.name == main { return ZipEntry(name: "word/document.xml", data: e.data) }
            if e.name == "word/_rels/\(parts[1]).rels" { return ZipEntry(name: "word/_rels/document.xml.rels", data: e.data) }
            return e
        }
    }

    static func read(_ archive: Data) throws -> DocxDocument {
        let entries = _withStandardMainPart(try Zip.read(archive))
        func part(_ name: String) -> Data? { entries.first { $0.name == name }?.data }
        guard let docData = part("word/document.xml") else { throw DocxError.noDocumentPart }
        guard let root = XNode.parse(docData) else { throw DocxError.badXML("word/document.xml") }
        let kept = _keptParts(entries, part)
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
        _inheritSpace(root)
        Self._foldDropCaps(root)
        // A document with several bodies: Word shows them all, one after
        // the other (MultipleBodyBug came back with the first alone).
        // Each section break in the text, told how the section after it
        // starts (see `_paragraphs`).
        do {
            var sects: [XNode] = []
            var stack = Array(body.children.reversed())
            while let n = stack.popLast() {
                if n.name == "w:sectPr" { sects.append(n) } else if n.name != "w:tbl" { stack.append(contentsOf: n.children.reversed()) }
            }
            // (A continuous section on paper of another size or the other
            // way round starts a page all the same: zh-3ab8a2fb's landscape
            // "附件2" table, continuous after a portrait section, opens page
            // 22 in Word's print; ours set its label at page 21's foot, and
            // the document ran a page long.)
            func paper(_ s: XNode) -> String {
                let size = s.first("w:pgSz")
                return "\(size?["w:w"] ?? "")x\(size?["w:h"] ?? "")"
            }
            for (i, sect) in sects.enumerated().dropLast() {
                let next = sects[i + 1]
                let breaks = (next.first("w:type")?["w:val"] ?? "nextPage") != "continuous" || paper(next) != paper(sect)
                sect.attrs["x-next-breaks"] = breaks ? "1" : "0"
            }
        }
        for extra in root.all("w:body").dropFirst() {
            let at = body.children.lastIndex { $0.name == "w:sectPr" } ?? body.children.count
            body.children.insert(contentsOf: extra.children.filter { $0.name != "w:sectPr" }, at: at)
        }
        _reuseInlinePlaceholders(body)
        let notes = _Shared(kept: kept, rels: relInfo, rootNS: rootNS, part: part, contentType: contentType)
        // How note marks are numbered: Word's endnotes count "i, ii, iii"
        // unless the settings say otherwise, its footnotes "1, 2, 3"
        // (endnotes.docx and Bug54849 show "i" in Word's print).
        if let settings = part("word/settings.xml").flatMap(XNode.parse) {
            if let f = settings.first("w:endnotePr")?.first("w:numFmt")?["w:val"] { notes.endnoteFormat = f }
            if let f = settings.first("w:footnotePr")?.first("w:numFmt")?["w:val"] { notes.footnoteFormat = f }
        }
        if let compat = part("word/settings.xml").flatMap(XNode.parse)?.first("w:compat") {
            let mode = compat.all("w:compatSetting").first { $0["w:name"] == "compatibilityMode" }.flatMap { Int($0["w:val"] ?? "") } ?? 12
            notes.marksFollowBreaks = mode < 15 && (compat.first("w:splitPgBreakAndParaMark").map { !_isOff($0) } ?? false)
        }

        // Kept header and footer parts, before the styles are read: the
        // styles they name must be written too (issue_51265_3's header
        // paragraphs are "Kopfzeile", which fell back to Normal).
        var keptHeaderFooters: [KeptHeaderFooter] = []
        var titlePage = false
        var evenAndOddHeaders = false
        var footerFramed = false
        var keptCompat: String? = nil
        // The default tab distance: 35.4pt in a third of the corpus (metric
        // Word's 1.25cm), and every typed "4.2.8.<tab>text" lands
        // elsewhere under our 36 — bug65649's first lines.
        let defaultTabStop = part("word/settings.xml").flatMap(XNode.parse)?.first("w:defaultTabStop")
            .flatMap { Double($0["w:val"] ?? "") }.flatMap { $0 >= 0 ? $0 / 20 : nil }
        if let sect = body.first("w:sectPr") {
            // A header or footer with a picture, a table or a text box
            // (a logo, 60329's banner) is more than its text: the part is
            // kept whole and written back unless the text was edited; the
            // first-page and even-page ones, which the editor has no
            // field for, are kept always.
            titlePage = sect.first("w:titlePg") != nil
            // The file's compatibility block, as it stands — including an
            // EMPTY one, which is Word's legacy (2003) layout mode and lays
            // text out measurably differently: drawing.docx wrapped tighter
            // under mode 15 and ran two lines ahead by page 7 (13% -> 1.4%
            // with its empty block put back). An earlier reading dropped
            // the empty block over a form_footnotes page that has since
            // turned out to be a one-point knife edge.
            if let settings = part("word/settings.xml").flatMap(XNode.parse), let compat = settings.first("w:compat") {
                if compat.children.isEmpty {
                    keptCompat = "<w:compat/>"
                } else if compat.children.allSatisfy({ $0.name.hasPrefix("w:") }) {
                    keptCompat = PptxXML.serialize(compat)
                }
            }
            evenAndOddHeaders = part("word/settings.xml").map { String(decoding: $0, as: UTF8.self).containsSubstring("<w:evenAndOddHeaders") } ?? false
            for ref in sect.children where ref.name == "w:headerReference" || ref.name == "w:footerReference" {
                // ("odd", which the format does not have, is the default
                // to Word: 60293's "ODD_PAGE_HEADER" on its page 3.)
                let type = ref["w:type"].map { $0 == "odd" ? "default" : $0 } ?? "default"
                guard ["default", "first", "even"].contains(type), let rid = ref["r:id"], let target = relInfo[rid]?.target,
                      let data = media(target), _wellFormed(data), let node = XNode.parse(data) else { continue }
                // Every part is kept, the plainest included, and written back
                // while the editor's text for it is still the file's: the
                // generated form is one line, centred or tabbed into thirds,
                // and says none of a part's border, font, alignment tab,
                // second paragraph or left-set footer (WordWithAttachments'
                // three-line header, form_footnotes' blank footer that still
                // reserves its height, FancyFoot's ruled Cambria line,
                // headerFooter's footer at the left margin).
                // (A framed paragraph in a footer raised over the footer's
                // top — `w:framePr` with a negative `w:y`, so it stands up
                // into the body's room — and Word for Mac lets the body's
                // lines part with no widow control: lab wc2 (Word 16, mode
                // 14); its w:y set to 0 or 1 (lab wc3), the lines stay
                // together again. Not a frame at or under the footer's top:
                // the 36 references whose page numbers stand 1 to 8 twips
                // down keep widow control in Word's prints.)
                func raisedFrame(_ n: XNode) -> Bool {
                    if n.name == "w:framePr", let y = n["w:y"].flatMap(Double.init), y < 0 { return true }
                    return n.children.contains(where: raisedFrame)
                }
                if ref.name == "w:footerReference", raisedFrame(node) { footerFramed = true }
                let path = _resolvePath("word", target)
                notes.keep(path)
                guard notes.kept[path] != nil else { continue }
                keptHeaderFooters.append(KeptHeaderFooter(kind: ref.name == "w:headerReference" ? .header : .footer,
                                                                   type: type, part: path, text: _fieldText(node)))
            }
        }
        // Comments: the part (and Word's extended parts) kept whole; the
        // ranges ride on the runs. Word prints them as balloons, which
        // scale the page (WordWithAttachments, delins, testComment).
        for p in ["word/comments.xml", "word/commentsExtended.xml", "word/commentsIds.xml", "word/commentsExtensible.xml"] {
            if let data = part(p), _wellFormed(data) { notes.keep(p) }
        }
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
        // A package with no styles part at all is laid out by Word's own
        // Normal of the day — 12pt, 8pt after, lines of 1.16 (measured off
        // Word 16's print of Bug66263-paragraph) — not by the bare
        // defaults a styles part that says nothing leaves.
        let noStyles = part("word/styles.xml") == nil
        if noStyles { base = RichParagraphStyle(spaceAfter: 8, lineSpacing: 278.0 / 240) }
        var tableBases: [String: RichParagraphStyle] = [:]
        // The same over the document defaults alone, for a cell paragraph
        // whose style chain does not reach Normal.
        var tableRootBases: [String: RichParagraphStyle] = [:]
        var docBase = base
        // Cell margins by table style, each side from the style's chain
        // down to the default table style, then Word's own (0, 5.4pt).
        var tableMargins: [String: _Margins] = [:]
        var defaultMargins = _Margins()
        // Whether a table style draws borders (Table Grid does, Normal Table
        // does not): a table that says nothing itself takes its style's word.
        var tableBorders: [String: _Borders] = [:]
        var tableEdges: [String: BorderEdges?] = [:]
        var tableSides: [String: XNode] = [:]
        var defaultBorders: _Borders? = nil
        // A table style's conditional parts: the first row's fill and run
        // look, the body rows' bands.
        var tableConds: [String: _Cond] = [:]
        // A table style's own text size, by its chain, where the Normal style
        // says none of its own (`tableSizes`).
        var tableSizes: [String: Double] = [:]
        var normalStatesSize = false
        // Table styles (and the default one) that fix the layout: a table
        // that says nothing itself is then not autofitted.
        var fixedTableStyles = Set<String>()
        var defaultTableFixed = false
        // Numbering a paragraph style carries itself (a numbered heading
        // style): the paragraphs of that style number without a numPr.
        var styleNums: [String: (numId: String, ilvl: Int, left: Double?, first: Double?)] = [:]
        var paragraphStyles: [String: XNode] = [:]
        var styleAliases: [String: String] = [:]
        var keptCharacterStyles: [String: String] = [:]
        var keptCharacterStyleIds: [String: String] = [:]
        if let stylesData = part("word/styles.xml"), let styles = XNode.parse(stylesData) {
            _resolveThemeFonts(styles, theme)
            _normaliseStyleIds(styles)
            // A styles part with NO w:pPrDefault at all (WPS writes them
            // so: six of a sample of 68 Chinese government documents, every
            // one 6-37% off) is spaced by Word's own Normal — 8pt after,
            // lines of 278/240, the same as a package with no styles part.
            // An EMPTY w:pPrDefault is a statement, and means none.
            if styles.first("w:docDefaults")?.first("w:pPrDefault") == nil {
                base = RichParagraphStyle(spaceAfter: 8, lineSpacing: 278.0 / 240)
            }
            if let defaults = styles.first("w:docDefaults")?.first("w:pPrDefault")?.first("w:pPr") {
                _paragraphProps(defaults, into: &base)
            }
            // What a style with no w:basedOn starts from: the document
            // defaults alone. Only a style based on Normal takes Normal's
            // look (Bug54771b's No Spacing names no parent, and came back
            // with Normal's 10pt after and 1.15 lines in every cell).
            docBase = base
            var docChar = CharStyle()
            if let rPr = styles.first("w:docDefaults")?.first("w:rPrDefault")?.first("w:rPr") { docChar = _charStyle(rPr, base: docChar) }
            var normalChar = docChar
            for style in styles.all("w:style") where style["w:type"] == "paragraph"
                && (style["w:default"] == "1" || style["w:styleId"] == "Normal") {
                if let rPr = style.first("w:rPr") { normalChar = _charStyle(rPr, base: normalChar) }
            }
            // (A style's look is kept as what it says over Normal's, so
            // only where the defaults differ from Normal are they stated.)
            var rootChar = CharStyle()
            if docChar.fontSize != normalChar.fontSize { rootChar.fontSize = docChar.fontSize }
            if docChar.fontFamily != normalChar.fontFamily { rootChar.fontFamily = docChar.fontFamily }
            // Kerning too, said as none where only Normal kerns: Word
            // closes up 》《 only where it kerns, and a Zhejiang plan's
            // body, in a style that is not Normal's child, took a
            // character more a line under Normal's.
            if docChar.kerningFrom != normalChar.kerningFrom { rootChar.kerningFrom = docChar.kerningFrom ?? 0 }
            // And the language: zh-fec5fa30's Normal says East Asian
            // en-US, its defaults zh-TW, and its body style "內文2" is
            // no child of Normal — Word keeps "，" off a line's start
            // there, carrying "目" down with it; ours read Normal's
            // en-US, which has no such rules.
            let docLang = _keptRunProperties(docChar.keptXML)["w:lang"]
            if let docLang, docLang != _keptRunProperties(normalChar.keptXML)["w:lang"] { rootChar.keptXML = docLang }
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
                var rootPs = docBase
                if let pPr = style.first("w:pPr") { _paragraphProps(pPr, into: &rootPs) }
                tableRootBases[id] = rootPs
                tableNodes[id] = style
                tableEdges[id] = _edges(style.first("w:tblPr"), "w:tblBorders")
                tableSides[id] = style.first("w:tblPr")?.first("w:tblBorders")
                if style.first("w:tblPr")?.first("w:tblLayout")?["w:type"] == "fixed" {
                    fixedTableStyles.insert(id)
                    if style["w:default"] == "1" { defaultTableFixed = true }
                }
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
                            guard hex.count == 6, let v = Int64(hex, radix: 16) else { return nil }
                            return Color(0xFF00_0000 | Int64(v))
                        }
                        switch part["w:type"] {
                        case "firstRow":
                            if cond.headerFill == nil { cond.headerFill = fill }
                            if cond.headerChar == nil, let rPr = part.first("w:rPr") { cond.headerChar = _charStyle(rPr, base: CharStyle()) }
                            if cond.headerBorders == nil { cond.headerBorders = part.first("w:tcPr")?.first("w:tcBorders") }
                        case "firstCol":
                            if cond.firstColChar == nil, let rPr = part.first("w:rPr") { cond.firstColChar = _charStyle(rPr, base: CharStyle()) }
                        case "band1Horz": if cond.band1 == nil { cond.band1 = fill }
                        case "band2Horz": if cond.band2 == nil { cond.band2 = fill }
                        default: break
                        }
                    }
                    cur = node.first("w:basedOn")?["w:val"]
                }
                tableConds[id] = cond
            }
            // (A table style's text size stands under the paragraph's own
            // style, over the document's defaults: zh-e2dc9dce's form, style
            // "表格格線1" at 10pt under a Normal that says no size over 12pt
            // defaults, sets its cells' unsized text at 10pt in Word's print;
            // ours at 12, its rows grew and its lines wrapped elsewhere.)
            normalStatesSize = styles.all("w:style").contains { style in
                style["w:type"] == "paragraph" && (style["w:default"] == "1" || style["w:styleId"] == "Normal")
                    && style.first("w:rPr")?.first("w:sz") != nil
            }
            for id in tableNodes.keys {
                var seen = Set<String>(), cur: String? = id
                while let c = cur, !seen.contains(c), let node = tableNodes[c] {
                    seen.insert(c)
                    if let v = node.first("w:rPr")?.first("w:sz")?["w:val"].flatMap(Double.init) { tableSizes[id] = v / 2; break }
                    cur = node.first("w:basedOn")?["w:val"]
                }
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
            for style in styles.all("w:style") where style["w:type"] == "paragraph" {
                if let id = style["w:styleId"] { paragraphStyles[id] = style }
            }
            var charNodes: [String: XNode] = [:]
            for style in styles.all("w:style") where style["w:type"] == "character" {
                if let id = style["w:styleId"] { charNodes[id] = style }
            }
            // Kept as written, less what would not stand alone in the
            // saved styles part: other namespaces, theme references (the
            // faces were resolved above) and the link to a paragraph style.
            func standalone(_ node: XNode) -> XNode {
                let copy = XNode(name: node.name, attrs: node.attrs.filter { $0.key.hasPrefix("w:") && !$0.key.lowercased().containsSubstring("theme") })
                copy.text = node.text
                copy.children = node.children.filter { $0.name.hasPrefix("w:") && $0.name != "w:link" && $0.name != "w:rsid" }.map(standalone)
                return copy
            }
            for (id, node) in charNodes {
                keptCharacterStyles[id] = PptxXML.serialize(standalone(node))
                if let name = node.first("w:name")?["w:val"] { keptCharacterStyleIds[name.lowercased()] = id }
            }
            for id in charNodes.keys {
                var chain: [XNode] = [], seen = Set<String>(), cur: String? = id
                while let c = cur, !seen.contains(c), let node = charNodes[c] {
                    seen.insert(c)
                    if let rPr = node.first("w:rPr") { chain.insert(rPr, at: 0) }
                    cur = node.first("w:basedOn")?["w:val"]
                }
                notes.charStyleChains[id] = chain
            }
            // The level a numbering definition ties a style to (w:lvl's
            // w:pStyle): a style that names a list and no level is that one.
            var linkedLevel: [String: Int] = [:]
            if let numbering = part("word/numbering.xml").flatMap(XNode.parse) {
                for a in numbering.all("w:abstractNum") {
                    for lvl in a.all("w:lvl") {
                        if let sid = lvl.first("w:pStyle")?["w:val"], let n = Int(lvl["w:ilvl"] ?? "") { linkedLevel[sid] = n }
                    }
                }
            }
            for id in paragraphStyles.keys {
                var seen = Set<String>(), cur: String? = id
                // The list and the level are inherited apart: "heading 3"
                // says level 2 and takes the list from "heading 1" under it
                // (a Taiwanese handbook's 一、 and (一) were gone from every
                // heading). And the indent the chain states from this style
                // down to the one that names the list: a numbered style's
                // own w:ind stands over its level's (another's "heading 5"
                // items sat 61pt right of where their style puts them).
                var left: Double? = nil, first: Double? = nil
                var numId: String? = nil, ilvl: Int? = nil
                while let c = cur, !seen.contains(c), let node = paragraphStyles[c] {
                    seen.insert(c)
                    if let ind = node.first("w:pPr")?.first("w:ind") {
                        if left == nil, let v = Double(ind["w:left"] ?? ind["w:start"] ?? "") { left = v / 20 }
                        if first == nil {
                            if let v = Double(ind["w:hanging"] ?? "") { first = -v / 20 }
                            else if let v = Double(ind["w:firstLine"] ?? "") { first = v / 20 }
                        }
                    }
                    if let numPr = node.first("w:pPr")?.first("w:numPr") {
                        if ilvl == nil, let v = Int(numPr.first("w:ilvl")?["w:val"] ?? "") { ilvl = v }
                        if let v = numPr.first("w:numId")?["w:val"] { numId = v; break }
                    }
                    cur = node.first("w:basedOn")?["w:val"]
                }
                if let numId, numId != "0" { styleNums[id] = (numId, ilvl ?? linkedLevel[id] ?? 0, left, first) }
            }
            var resolved: [String: (paragraph: RichParagraphStyle, char: CharStyle)] = [:]
            func resolve(_ id: String, _ seen: Set<String> = []) -> (paragraph: RichParagraphStyle, char: CharStyle) {
                if let r = resolved[id] { return r }
                guard let style = paragraphStyles[id], !seen.contains(id) else { return (paragraph: base, char: CharStyle()) }
                let isDefault = style["w:default"] == "1" || id == "Normal"
                var r = style.first("w:basedOn")?["w:val"].map { resolve($0, seen.union([id])) }
                    ?? (isDefault ? (paragraph: base, char: CharStyle()) : (paragraph: docBase, char: rootChar))
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
            for (name, data) in notes.kept where name.hasSuffix(".xml") {
                if let n = XNode.parse(data) { collect(n) }
            }
            // And by every header and footer part the document relates to:
            // a section break in the text keeps the ones it names only
            // later, when its paragraph is read, and their styles were
            // not written (footers of a "footer" style at 9pt came back
            // at the body's size, a line lower).
            for rel in relInfo.values where !rel.external && (rel.type.hasSuffix("/header") || rel.type.hasSuffix("/footer")) {
                let path = _resolvePath("word", rel.target)
                if notes.kept[path] == nil, let data = part(path), let n = XNode.parse(data) { collect(n) }
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
                } else if used.contains(id) || name == "balloon text", sheet[id] == nil {
                    // (Balloon Text too, which no paragraph names: Word
                    // prints a document's markup balloons in it — delins's
                    // Tahoma 8pt, which went to the 9pt serif without it.)
                    styleByDocx[id] = id
                    sheet[id] = RichNamedStyle(id: id, name: rawName, paragraph: chain.paragraph, char: chain.char)
                }
            }
            // Kept markup (a nested table, a header part) still names the
            // file's ids: drawing.docx's heading 1 is "1", and inside its
            // kept table it fell back to plain text.
            styleAliases = styleByDocx.filter { used.contains($0.key) && $0.key != $0.value }
        }
        if var normal = sheet[RichNamedStyle.normalId] {
            normal.paragraph = base
            // Normal's look — the document defaults' run properties under
            // Normal's own: the font and size every plain paragraph is set
            // in. Without it a 12-point document came back at Calibri 11
            // (the writer's defaults), and every line wrapped elsewhere.
            if let styles = part("word/styles.xml").flatMap(XNode.parse) {
                _resolveThemeFonts(styles, theme)
                _normaliseStyleIds(styles)
                var cs = CharStyle()
                if let rPr = styles.first("w:docDefaults")?.first("w:rPrDefault")?.first("w:rPr") { cs = _charStyle(rPr, base: cs) }
                for style in styles.all("w:style") where style["w:type"] == "paragraph"
                    && (style["w:default"] == "1" || style["w:styleId"] == "Normal") {
                    if let rPr = style.first("w:rPr") { cs = _charStyle(rPr, base: cs) }
                }
                // A file that states no size anywhere is 10pt in Word (the
                // 2003-era default), not the 11pt of a fresh document.
                if cs.fontSize == nil { cs.fontSize = 10 }
                // A file whose styles carry no document defaults at all
                // (LibreOffice's older export) kerns every pair, as one
                // without styles does: fdo63164-1's "Wasserschöpfe" is
                // 0.4pt shorter in Word's print by "Wa", and fits a line
                // that ours, unkerned, spilled by a tenth of a point.
                if styles.first("w:docDefaults") == nil, cs.kerningFrom == nil {
                    cs.kerningFrom = 1
                    RuleTrace.hit("no-docdefaults-kerns")
                }
                normal.char = cs
            } else if noStyles {
                normal.char.fontSize = 12
                normal.char.kerningFrom = 1   // that Normal kerns, and the lines are half a percent shorter for it
            }
            sheet[RichNamedStyle.normalId] = normal
        }

        // Numbering: numId → level → bullet/decimal, and each numbered
        // level's label format, which the document keeps per list id.
        var kindByNum: [String: [Int: ListKind]] = [:]
        var listFormats: [String: [Int: ListLevelFormat]] = [:]
        var listCounterOf: [String: String] = [:]
        var listRestarts: [String: [Int: Int]] = [:]
        if let numData = part("word/numbering.xml"), let numbering = XNode.parse(numData) {
            var abstract: [String: [Int: ListKind]] = [:]
            var abstractFormats: [String: [Int: ListLevelFormat]] = [:]
            func readLevel(_ lvl: XNode, _ levels: inout [Int: ListKind], _ formats: inout [Int: ListLevelFormat]) {
                let ilvl = Int(lvl["w:ilvl"] ?? "0") ?? 0
                // (Word 2010's custom formats — "α, β, γ, ..." — stand in
                // an mc:Choice over a decimal fallback.)
                let chosen = lvl.first("mc:AlternateContent")?.first("mc:Choice")?.first("w:numFmt")
                let fmtNode = chosen ?? lvl.first("w:numFmt") ?? lvl.first("mc:AlternateContent")?.first("mc:Fallback")?.first("w:numFmt")
                let customSpec = fmtNode?["w:val"] == "custom" ? fmtNode?["w:format"] : nil
                let fmt = customSpec == nil ? (fmtNode?["w:val"] == "custom" ? "decimal" : fmtNode?["w:val"] ?? "decimal") : "custom"
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
                        if glyph != raw { formats[ilvl]!.rawText = raw; formats[ilvl]!.rawTextGlyph = glyph }
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
                    // "一、二、三": a format the editor counts in digits.
                    if !["decimal", "lowerLetter", "upperLetter", "lowerRoman", "upperRoman"].contains(fmt) { formats[ilvl]!.rawFormat = fmt }
                    if let spec = customSpec { formats[ilvl]!.rawFormat = "custom:" + spec }
                }
                // The level's indents (65099's "1.1.1" hangs 0.5in at the
                // margin; the editor's default put it 1.5in in).
                if formats[ilvl] != nil {
                    // Kept as written, in the namespaces the numbering part
                    // declares (a number's w14 text effects — ten Chinese
                    // government files in a first sample of 179 — made the
                    // saved part ill-formed while it declared w alone).
                    if let v = Int(lvl.first("w:start")?["w:val"] ?? ""), v != 1 { formats[ilvl]!.start = v }
                    if let v = lvl.first("w:lvlJc")?["w:val"], v != "left", v != "start" { formats[ilvl]!.justification = v }
                    if let rPr = lvl.first("w:rPr"), !rPr.children.isEmpty {
                        let kept = XNode(name: rPr.name, attrs: rPr.attrs)
                        kept.children = rPr.children.filter { c in ["w:", "w14:", "w15:"].contains { c.name.hasPrefix($0) } }
                        if !kept.children.isEmpty { formats[ilvl]!.numberRPrXML = PptxXML.serialize(kept) }
                    }
                    if let suff = lvl.first("w:suff")?["w:val"] { formats[ilvl]!.suffix = suff }
                }
                if let ind = lvl.first("w:pPr")?.first("w:ind"), formats[ilvl] != nil {
                    if let v = Double(ind["w:left"] ?? ind["w:start"] ?? "") { formats[ilvl]!.indentLeft = v / 20 }
                    if let v = Double(ind["w:hanging"] ?? "") { formats[ilvl]!.hanging = v / 20 }
                    else if let v = Double(ind["w:firstLine"] ?? "") { formats[ilvl]!.hanging = -v / 20 }
                }
            }
            for a in numbering.all("w:abstractNum") {
                guard let id = a["w:abstractNumId"] else { continue }
                var levels: [Int: ListKind] = [:]
                var formats: [Int: ListLevelFormat] = [:]
                for lvl in a.all("w:lvl") { readLevel(lvl, &levels, &formats) }
                abstract[id] = levels
                abstractFormats[id] = formats
            }
            // (A definition that only names a numbering style —
            // w:numStyleLink — has its levels in the definition that
            // style is (w:styleLink): zh-12c4f07a's "3.1.1" items are a
            // list over such a one, which ours, finding no levels, drew
            // as bullets.)
            var styleLinked: [String: String] = [:]
            var numStyleLinks: [String: String] = [:]
            for a in numbering.all("w:abstractNum") {
                guard let id = a["w:abstractNumId"] else { continue }
                if let s = a.first("w:styleLink")?["w:val"] { styleLinked[s] = id }
                if let s = a.first("w:numStyleLink")?["w:val"] { numStyleLinks[id] = s }
            }
            for n in numbering.all("w:num") {
                guard let id = n["w:numId"], var aid = n.first("w:abstractNumId")?["w:val"] else { continue }
                if (abstract[aid] ?? [:]).isEmpty, let style = numStyleLinks[aid], let linked = styleLinked[style] { aid = linked }
                var levels = abstract[aid] ?? [:]
                var formats = abstractFormats[aid] ?? [:]
                // A level the list itself redefines (w:lvlOverride with a
                // whole w:lvl) replaces the definition's: form_footnotes'
                // instructions are bullets at 0.25in over a definition
                // that says "*" and nothing else.
                for ov in n.all("w:lvlOverride") {
                    guard let lvl = ov.first("w:lvl") else { continue }
                    let ilvl = Int(lvl["w:ilvl"] ?? ov["w:ilvl"] ?? "0") ?? 0
                    formats[ilvl] = nil
                    readLevel(lvl, &levels, &formats)
                }
                kindByNum[id] = levels
                listFormats[id] = formats
                notes.listFormats[id] = formats
                // Lists over one definition share its numbers; a list's
                // startOverride restarts a level the first time it is used.
                listCounterOf[id] = "abstract:" + aid
                for ov in n.all("w:lvlOverride") {
                    guard let v = Int(ov.first("w:startOverride")?["w:val"] ?? "") else { continue }
                    listRestarts[id, default: [:]][Int(ov["w:ilvl"] ?? "0") ?? 0] = v
                }
            }
        }

        var paragraphs: [RichParagraph] = []
        var pageSetup: PageSetup? = nil
        var pendingPageBreak = false
        var pendingBreakCharacter = false   // ... made by a break character, in a run with these properties
        var pendingBreakRPr: String? = nil
        var pendingBreakColumn = false
        var tableColumns: [String: [Double]] = [:]
        var tableStyles: [String: TableStyle] = [:]
        var tableCount = 0
        var currentCell: CellRef? = nil
        var cellChar = CharStyle()   // the table style's look for the first row's runs
        var keptTables: [String: KeptTable] = [:]
        var keptTableCount = 0
        /// Each top-level body paragraph's own `w:p`, while the body is read
        /// (the column sections read as table rows keep their markup).
        var bodyNodes: [Int: XNode] = [:]
        var recordingBody = true
        /// A paragraph style's chain laid over `base` — the table style's
        /// paragraph props inside a cell: Word puts the table style under
        /// the paragraph style, so a style that sets only "after" keeps the
        /// table style's line rule (65099's cells were a line of 1.15, not 1.0).
        func chainOver(_ id: String, _ base: RichParagraphStyle, _ rootBase: RichParagraphStyle) -> RichParagraphStyle? {
            guard paragraphStyles[id] != nil else { return nil }
            var ids: [String] = [], seen = Set<String>(), cur: String? = id
            while let c = cur, !seen.contains(c), let node = paragraphStyles[c] {
                ids.append(c); seen.insert(c); cur = node.first("w:basedOn")?["w:val"]
            }
            // A chain that ends in a style other than Normal never takes
            // Normal's look (see `docBase`).
            let root = ids.last.flatMap { paragraphStyles[$0] }
            let reachesNormal = root.map { $0["w:default"] == "1" || $0["w:styleId"] == "Normal" } ?? true
            var ps = reachesNormal ? base : rootBase
            for c in ids.reversed() { if let pPr = paragraphStyles[c]?.first("w:pPr") { _paragraphProps(pPr, into: &ps) } }
            return ps
        }
        var cellBase = base   // the table style's spacing while inside one
        var cellRootBase = docBase
        // (A cell's paragraph of no style of its own is Normal's, and
        // Normal's own settings stand over the table style's, as a named
        // style's chain does — Word applies the table style under the
        // paragraph's style, not over it. zh-0b48a0db's Normal says 1.08
        // lines (w:line 259) and its "TableGrid" single, no space after;
        // Word's print sets the table's 14pt lines 25.9pt apart, 1.08 of
        // YaHei's 24, with nothing after; ours took the table style's
        // single line, 24.4, and the table ran a line short a page.)
        let normalStyleId = paragraphStyles.first(where: { $0.value["w:default"] == "1" })?.key
        func cellNormal() -> RichParagraphStyle {
            normalStyleId.flatMap { chainOver($0, cellBase, cellRootBase) } ?? cellBase
        }

        var joinInto: Int? = nil
        func emit(_ p: RichParagraph) {
            var p = p
            if pendingPageBreak {
                p.style.pageBreakBefore = true; pendingPageBreak = false
                if pendingBreakCharacter, !p.style.pageBreakInline {
                    p.style.breakEndsPrevious = true; p.style.breakRunPropertiesXML = pendingBreakRPr; p.style.columnBreak = pendingBreakColumn
                }
                // (A paragraph of a page break alone, then one opening with
                // its own: Word's page between is blank but for the second
                // paragraph's start — zh-e74dd0a1's page 63, its folio
                // alone, before "衢州市政府信息公开工作社会评议办法" on 64;
                // ours merged the two breaks, and ran two pages short.)
                else if pendingBreakCharacter, p.style.pageBreakInline, !pendingBreakColumn, !p.style.columnBreak {
                    p.style.pageBreakTwice = true
                }
                pendingBreakCharacter = false; pendingBreakRPr = nil; pendingBreakColumn = false
            }
            if p.cell == nil { p.cell = currentCell }
            // (A paragraph whose mark is hidden runs on into the next, as
            // Word shows it — a style separator (`w:vanish` and
            // `w:specVanish` on the mark): zh-9f24d3eb's "(二)附件2" and
            // "：切結書暨領據…" are one line in Word's print, the first's
            // numbering and indents for both; ours set two, and page 2 ran
            // a line long.)
            if let i = joinInto, i == paragraphs.count - 1, paragraphs[i].cell == p.cell, p.image == nil, paragraphs[i].image == nil {
                paragraphs[i].text += p.text
                paragraphs[i].runs += p.runs
                paragraphs[i].bookmarks += p.bookmarks
                for (k, v) in p.inlineImages { paragraphs[i].inlineImages[k] = v }
                if !p.style.markHidden { paragraphs[i].style.markHidden = false; paragraphs[i].style.mark = p.style.mark; joinInto = nil }
                return
            }
            joinInto = nil
            paragraphs.append(p)
            if p.style.markHidden, p.image == nil, p.runs.contains(where: { !$0.style.hidden && $0.length > 0 }) { joinInto = paragraphs.count - 1 }
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
        /// The characters of text under `node`.
        func textLength(_ node: XNode) -> Int {
            var n = 0
            var stack = [node]
            while let x = stack.popLast() {
                if x.name == "w:t" { n += x.text.count; continue }
                stack.append(contentsOf: x.children)
            }
            return n
        }
        func deepParagraphs(_ node: XNode) -> [XNode] {
            var out: [XNode] = []
            var stack = [node]
            while let n = stack.popLast() {
                if n.name == "w:p" { out.append(n); continue }
                stack.append(contentsOf: n.children.reversed())
            }
            return out
        }
        /// Flags the paragraph just read, when it is the empty one that
        /// ends cell `tc` right under a table nested in it
        /// (`RichParagraphStyle.markUnderNestedTable`).
        func flagMarkUnderNestedTable(_ tc: XNode, since first: Int) {
            let blocks = tc.children.filter { ["w:p", "w:tbl", "w:sdt"].contains($0.name) }
            guard blocks.count >= 2, blocks[blocks.count - 1].name == "w:p", blocks[blocks.count - 2].name == "w:tbl",
                  paragraphs.count > first, let last = paragraphs.indices.last,
                  paragraphs[last].text.isEmpty, paragraphs[last].image == nil else { return }
            paragraphs[last].style.markUnderNestedTable = true
        }
        func walkBlock(_ node: XNode, indent: Double, depth: Int = 0) {
            switch node.name {
            case "w:p":
                let first = paragraphs.count
                for p in _paragraphs(node, currentCell != nil ? cellNormal() : base, styleByDocx, styleNums, sheet, kindByNum, rels, media, indent, notes, cellChar,
                                     currentCell != nil ? { id in chainOver(id, cellBase, cellRootBase) } : nil) {
                    // (A page break that ends the paragraph holding a
                    // section's mark is that section's break, as Word lays
                    // it — and where the next section is continuous there
                    // is none: zh-e2dc9dce's contents end in a page break
                    // and a continuous section, and Word for Windows sets
                    // chapter 1's title picture, the paragraph after, on
                    // the contents page, the body from page 3; ours gave
                    // the picture a page and ran a page long to the end.
                    // Only there: Mac Word keeps the break, and its print of
                    // the same document has a page 3 of the picture alone.)
                    let sectionsOwn = Self.wordOnWindows && currentCell == nil && !p.breakColumn && p.paragraph.style.sectionXML != nil
                        && p.paragraph.style.sectionBreaksPage == false
                    if p.pageBreakAfter, !sectionsOwn { emit(p.paragraph); pendingPageBreak = true; pendingBreakCharacter = p.breakCharacter; pendingBreakRPr = p.breakRPr; pendingBreakColumn = p.breakColumn } else { emit(p.paragraph) }
                }
                if recordingBody, currentCell == nil { for k in first ..< paragraphs.count { bodyNodes[k] = node } }
                // A text box whose text holds a table (`_Shared.boxTables`):
                // its text read again here, tables and all, as a small table
                // in a cell is (below). zh-64044a1d's 災民收容登記表 is a form
                // in a VML box behind the text; read for its paragraphs alone,
                // the box held one empty line and printed as nothing.
                if !notes.boxTables.isEmpty {
                    func boxed(_ image: ImageAttachment) -> ImageAttachment {
                        guard let content = notes.boxTables.removeValue(forKey: image.id), var box = image.textBox else { return image }
                        let saved = (paragraphs, currentCell, cellChar, cellBase, cellRootBase, recordingBody,
                                     pendingPageBreak, pendingBreakCharacter, pendingBreakRPr, pendingBreakColumn)
                        let counts = (notes.seenFootnotes, notes.seenEndnotes, notes.openComments, notes.pendingBookmarks, notes.fields,
                                      notes.seenComments, notes.fieldShown)
                        paragraphs = []; currentCell = nil; recordingBody = false; pendingPageBreak = false
                        cellChar = CharStyle()
                        notes.inTextBox = true
                        for child in content.children { walkBlock(child, indent: 0, depth: 1) }
                        notes.inTextBox = false
                        let inner = paragraphs
                        (paragraphs, currentCell, cellChar, cellBase, cellRootBase, recordingBody,
                         pendingPageBreak, pendingBreakCharacter, pendingBreakRPr, pendingBreakColumn) = saved
                        (notes.seenFootnotes, notes.seenEndnotes, notes.openComments, notes.pendingBookmarks, notes.fields,
                         notes.seenComments, notes.fieldShown) = counts
                        guard !inner.isEmpty else { return image }
                        let ids = Set(inner.compactMap { $0.cell?.table })
                        box.paragraphs = inner
                        box.tableStyles = tableStyles.filter { ids.contains($0.key) }
                        box.tableColumns = tableColumns.filter { ids.contains($0.key) }
                        var out = image
                        out.textBox = box
                        return out
                    }
                    for k in first ..< paragraphs.count {
                        if let image = paragraphs[k].image { paragraphs[k].image = boxed(image) }
                        for (key, image) in paragraphs[k].inlineImages { paragraphs[k].inlineImages[key] = boxed(image) }
                    }
                }
            case "w:tbl" where currentCell != nil && depth < maxNesting && _nestingDepth(node) == 1
                                && ((unwrapped(node, "w:tr").count <= 15 && textLength(node) <= 600)
                                    || (unwrapped(node, "w:tr").count > 15 && (node.first("w:tblGrid")?.all("w:gridCol").count ?? 1) >= 2)):
                // A small table in a cell, with none in it, is a table of
                // its own: read as a document is, and set in its cell as a
                // block as tall as it lays out (`RichTextBox.growsToFit`).
                // Flattened, zh-454e2e29's form of five columns — "姓名",
                // "職稱", "職務編號"… — stood as a column of lines 36pt
                // apart. (A long one is still flattened below: a block
                // does not part across pages, and 60329's protocol text,
                // 2,235 characters in a three-row table in a cell, ran to
                // six pages for it.) Its markup is kept for the save.
                let saved = (paragraphs, currentCell, cellChar, cellBase, cellRootBase)
                paragraphs = []
                currentCell = nil
                walkBlock(node, indent: 0, depth: depth + 1)
                let inner = paragraphs
                (paragraphs, currentCell, cellChar, cellBase, cellRootBase) = saved
                let ids = Set(inner.compactMap { $0.cell?.table })
                var box = RichTextBox(paragraphs: inner)
                box.insetLeft = 0; box.insetTop = 0; box.insetRight = 0; box.insetBottom = 0
                box.tableStyles = tableStyles.filter { ids.contains($0.key) }
                box.tableColumns = tableColumns.filter { ids.contains($0.key) }
                box.growsToFit = true
                let gridWidth = (node.first("w:tblGrid")?.all("w:gridCol").compactMap { Double($0["w:w"] ?? "") }.reduce(0, +) ?? 0) / 20
                var image = ImageAttachment(data: Data(), width: max(1, gridWidth), height: 1, name: "table")
                image.textBox = box
                // (One placed as it floats, `w:tblpPr`, stands where it says,
                // from the cell, and the text goes round it — lab `tf` on
                // Word for Windows: zh-291fcea7 p5's flowchart boxes, placed
                // against the "page" at 29.25 and 320.85pt and centred on the
                // "margin", stand 29.5 and 321.2pt from the cell's left edge
                // and centred on the cell, side by side; ours stacked them
                // down the cell.)
                var nominalLeft = 0.0
                if let pos = node.first("w:tblPr")?.first("w:tblpPr") {
                    var f = ImageFloat()
                    f.horizontalFrom = "cell"
                    f.verticalFrom = "paragraph"
                    if let spec = pos["w:tblpXSpec"] { f.horizontalAlign = spec } else { f.x = (Double(pos["w:tblpX"] ?? "") ?? 0) / 20 }
                    f.y = (Double(pos["w:tblpY"] ?? "") ?? 0) / 20
                    f.wraps = true
                    // (One that floats only in name — against the text, from the
                    // column's edge, a twip or so under its paragraph's top —
                    // stands where it is set, an inline block shifted by its x:
                    // LibreOffice's tdf170381, a 75pt table in a 383pt cell,
                    // which Word parts over two pages between its rows, as an
                    // inline one does; a floating box ran off the page's foot
                    // and its rows were never cut.)
                    if pos["w:vertAnchor"] == "text", (pos["w:horzAnchor"] ?? "text") == "text", pos["w:tblpXSpec"] == nil, pos["w:tblpYSpec"] == nil,
                       f.y <= 1, f.x >= 0 {
                        nominalLeft = f.x
                    } else {
                        image.float = f
                    }
                    // (Placed so, it stands at its box's corner inside it: the
                    // box's copy of its style floats it no further.)
                    for (key, var st) in box.tableStyles {
                        st.floatOffsetY = nil; st.floatRaiseY = nil; st.floatX = nil; st.floatXAnchor = nil
                        st.pageAnchored = false; st.pageOffsetY = nil; st.floatsOverText = false; st.alignment = .left
                        box.tableStyles[key] = st
                    }
                    image.textBox = box
                }
                var para = RichParagraph(image: image, style: cellBase)
                para.style.indentLeft += nominalLeft
                if let frag = _keptFragment(node, notes) {
                    keptTableCount += 1
                    let kid = "kt\(keptTableCount)"
                    keptTables[kid] = KeptTable(xml: frag.xml, rels: frag.rels, texts: [para.text])
                    para.keptTable = kid
                }
                emit(para)
            case "w:tbl" where currentCell != nil:
                // A nested table flattens into its cell, indented — and,
                // unless it nests absurdly (a fuzzer's 5,000 levels), is
                // kept as written: 60329's body is a table in a cell, and
                // flattened it lost its boxes and widths. The save writes
                // the kept markup back while the flattened text stands.
                let before = paragraphs.count
                var keptId: String? = nil
                if depth < maxNesting, _nestingDepth(node) <= 6, let frag = _keptFragment(node, notes) {
                    keptTableCount += 1
                    keptId = "kt\(keptTableCount)"
                    keptTables[keptId!] = KeptTable(xml: frag.xml, rels: frag.rels, texts: [])
                }
                if depth >= maxNesting {
                    for p in deepParagraphs(node) { walkBlock(p, indent: indent + 18, depth: depth + 1) }
                } else {
                    // (Each cell keeps the room its table gave it above and
                    // below — its top and bottom margins and the table's
                    // cell spacing — as its first and last paragraphs'
                    // spacing: drawing.docx's article heads stand in HTML
                    // tables three deep, and flattened they lost 10.5pt of
                    // it, the "12.04.2006 - Cbonds" line 11pt high of Word's
                    // print and three pages after it a line early.)
                    let rows = unwrapped(node, "w:tr")
                    let tableMargins = _cellMargins(node.first("w:tblPr"))
                    let spacing = node.first("w:tblPr")?.first("w:tblCellSpacing").flatMap { sp -> Double? in
                        (sp["w:type"] ?? "dxa") == "dxa" ? Double(sp["w:w"] ?? "").map { $0 / 20 } : nil
                    } ?? 0
                    for (r, tr) in rows.enumerated() {
                        for tc in unwrapped(tr, "w:tc") {
                            let first = paragraphs.count
                            for child in tc.children { walkBlock(child, indent: indent + 18, depth: depth + 1) }
                            guard paragraphs.count > first else { continue }
                            flagMarkUnderNestedTable(tc, since: first)
                            let m = _cellMargins(tc.first("w:tcPr"), "w:tcMar").under(tableMargins)
                            paragraphs[first].style.spaceBefore += (m.top ?? 0) + spacing * (r == 0 ? 2 : 1)
                            paragraphs[paragraphs.count - 1].style.spaceAfter += (m.bottom ?? 0) + spacing * (r == rows.count - 1 ? 2 : 1)
                        }
                    }
                }
                if let kid = keptId {
                    if paragraphs.count == before { emit(RichParagraph(style: cellBase)) }
                    for k in before ..< paragraphs.count { paragraphs[k].keptTable = kid }
                    keptTables[kid]!.texts = paragraphs[before...].map(\.text)
                }
            case "w:tbl" where currentCell == nil && depth == 0 && Self._isInvisibleWrapper(node):
                // A one-column table that draws nothing round tables of its
                // own is a page's frame, and its tables are the body's:
                // zh-e9616b2b is all one such cell (its only line an
                // insideV, which one column never draws), and its 35-row
                // checklist, flattened as a table in a cell is, ran four
                // pages where Word's print parts it over two. Read as the
                // body; the wrapper goes back as written while the text is.
                // (Each cell keeps the room the wrapper gave it above and
                // below, as a nested table's do — see there: zh-045c5a75's
                // law text stands in a wrapper of 0.75pt margins and
                // spacing, and Word sets its first line 2.35pt lower than
                // ours, the row that parts at page 9's foot a line shorter.)
                let before = paragraphs.count
                let rows = unwrapped(node, "w:tr")
                let tableMargins = _cellMargins(node.first("w:tblPr"))
                let spacing = node.first("w:tblPr")?.first("w:tblCellSpacing").flatMap { sp -> Double? in
                    (sp["w:type"] ?? "dxa") == "dxa" ? Double(sp["w:w"] ?? "").map { $0 / 20 } : nil
                } ?? 0
                for (r, tr) in rows.enumerated() {
                    for tc in unwrapped(tr, "w:tc").prefix(1) {
                        let first = paragraphs.count
                        // (The cell's mark under a table it ends with takes
                        // no room in Word, as under a nested one: 60329's
                        // rows, each a table and that mark, stood a line
                        // apart read as the body's.)
                        var children = tc.children
                        if let last = children.last, last.name == "w:p", children.dropLast().last?.name == "w:tbl",
                           !last.children.contains(where: { $0.name != "w:pPr" }) { children.removeLast() }
                        for child in children { walkBlock(child, indent: indent, depth: depth) }
                        guard paragraphs.count > first else { continue }
                        // (A row of one paragraph keeps the height the row
                        // was given as that line's least: 60329's 9pt
                        // spacer row holds a 1pt empty mark, and Word's
                        // print has the 9pt between its tables.)
                        if paragraphs.count == first + 1, !children.contains(where: { $0.name == "w:tbl" }),
                           let h = tr.first("w:trPr")?.first("w:trHeight"), h["w:hRule"] != "exact",
                           let v = Double(h["w:val"] ?? ""), v > 0,
                           paragraphs[first].style.lineHeightPoints == nil || paragraphs[first].style.lineHeightIsMinimum {
                            paragraphs[first].style.lineHeightPoints = max(paragraphs[first].style.lineHeightPoints ?? 0, v / 20)
                            paragraphs[first].style.lineHeightIsMinimum = true
                        }
                        let m = _cellMargins(tc.first("w:tcPr"), "w:tcMar").under(tableMargins)
                        paragraphs[first].style.spaceBefore += (m.top ?? 0) + spacing * (r == 0 ? 2 : 1)
                        paragraphs[paragraphs.count - 1].style.spaceAfter += (m.bottom ?? 0) + spacing * (r == rows.count - 1 ? 2 : 1)
                        // (And on each page the row goes on to — see
                        // `RichParagraphStyle.frameInsetTop`.)
                        if rows.count == 1 {
                            for k in first ..< paragraphs.count {
                                paragraphs[k].style.frameInsetTop = (m.top ?? 0) + spacing * 2
                                paragraphs[k].style.frameInsetBottom = (m.bottom ?? 0) + spacing * 2
                            }
                        }
                    }
                }
                if paragraphs.count > before, let frag = _keptFragment(node, notes) {
                    keptTableCount += 1
                    let kid = "kc\(keptTableCount)"
                    for k in before ..< paragraphs.count { paragraphs[k].keptTable = kid }
                    keptTables[kid] = KeptTable(xml: frag.xml, rels: frag.rels, texts: paragraphs[before...].map(\.text))
                }
            case "w:tbl":
                tableCount += 1
                let id = "t\(tableCount)"
                // Word's Table Grid says no space after and single lines;
                // a table with no style leaves the document defaults.
                cellBase = node.first("w:tblPr")?.first("w:tblStyle")?["w:val"].flatMap { tableBases[$0] } ?? base
                cellRootBase = node.first("w:tblPr")?.first("w:tblStyle")?["w:val"].flatMap { tableRootBases[$0] } ?? docBase
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
                    if on.count * 2 > cells.count {
                        // The width most cells draw, not the first cell's:
                        // bug65649's estimate rows rule their cells at sz 6
                        // and a few headings at sz 12, and the first cell
                        // was a heading — every row came out a point taller.
                        var pick = on.first { $0.color != nil } ?? on[0]
                        var counts: [Double: Int] = [:]
                        for b in on { if let w = b.width { counts[w, default: 0] += 1 } }
                        if let best = counts.max(by: { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }) { pick.width = best.key }
                        cellBorders = pick
                    }
                    else if (cellSaid.count - on.count) * 2 > cells.count { cellBorders = _Borders(on: false, color: nil) }
                }
                let borders = cellBorders ?? _borders(node.first("w:tblPr"), "w:tblBorders") ?? styledBorders ?? defaultBorders
                style.borders = borders?.on ?? false
                if cellBorders != nil, node.first("w:tblPr")?.first("w:tblBorders") == nil, styledBorders == nil {
                    style.bordersFromCells = true
                }
                // (The table's own colour when its cells decided the switch
                // and named none: bug57031's grey frames came back black.)
                style.borderColor = borders?.color ?? _borders(node.first("w:tblPr"), "w:tblBorders")?.color
                // (The width a side no cell states takes is the table's own,
                // else its style's, where either says one — the cells decide
                // only whether it is ruled: zh-bbbb2e6a's review form rules
                // its cells' outer sides 1.5pt and leaves the rows to Table
                // Grid's 0.5pt, its 96.6pt rows 97.1 apart in Word's print;
                // ours took 1.5 between them, 98.1, and the form's closing
                // lines went to a page of their own.)
                let tableSaid = _borders(node.first("w:tblPr"), "w:tblBorders") ?? styledBorders
                let widthFrom = cellBorders != nil && tableSaid?.on == true ? tableSaid : borders
                style.borderWidth = widthFrom?.width.flatMap { $0 == 0.5 ? nil : $0 }   // nil is Word's 0.5pt
                // The line style: the cells' when they decided, else the
                // table's own (a table ruled by its cells' nil sides still
                // names outset on its tblBorders).
                style.borderStyle = borders?.style ?? _borders(node.first("w:tblPr"), "w:tblBorders")?.style
                // Sides whose line style or width differ from the table's.
                // (A side the table's own borders leave out is its style's,
                // width and all: zh-5251dd23's tables name a 2.25pt frame
                // and leave the rows to Table Grid's 0.5pt insideH; ours
                // drew them 2.25 and every row 1.8pt taller.)
                let styledSides = node.first("w:tblPr")?.first("w:tblStyle")?["w:val"].flatMap { tableSides[$0] }
                if let tb = node.first("w:tblPr")?.first("w:tblBorders") {
                    for side in ["top", "left", "bottom", "right", "insideH", "insideV"] {
                        guard let e = tb.first("w:" + side) ?? styledSides?.first("w:" + side),
                              !["nil", "none"].contains(e["w:val"] ?? "nil") else { continue }
                        if let v = e["w:val"], v != (style.borderStyle ?? "single") { style.edgeStyles[side] = v }
                        if let sz = Double(e["w:sz"] ?? ""), max(0.25, sz / 8) != (style.borderWidth ?? 0.5) { style.edgeWidths[side] = max(0.25, sz / 8) }
                    }
                }
                // The table's sides, where they differ from that verdict:
                // its own w:tblBorders over its style's, and a side neither
                // names is none (form_footnotes' tables are ruled outside,
                // not between their cells; the verdict alone ruled every
                // row and grew the form by a line of borders).
                let styledEdges = node.first("w:tblPr")?.first("w:tblStyle")?["w:val"].flatMap { tableEdges[$0] ?? nil }
                if let own = _edges(node.first("w:tblPr"), "w:tblBorders") ?? styledEdges {
                    var e = BorderEdges()
                    e.top = own.top ?? styledEdges?.top ?? false
                    e.left = own.left ?? styledEdges?.left ?? false
                    e.bottom = own.bottom ?? styledEdges?.bottom ?? false
                    e.right = own.right ?? styledEdges?.right ?? false
                    e.insideH = own.insideH ?? styledEdges?.insideH ?? false
                    e.insideV = own.insideV ?? styledEdges?.insideV ?? false
                    if e.top == style.borders { e.top = nil }
                    if e.left == style.borders { e.left = nil }
                    if e.bottom == style.borders { e.bottom = nil }
                    if e.right == style.borders { e.right = nil }
                    if e.insideH == style.borders { e.insideH = nil }
                    if e.insideV == style.borders { e.insideV = nil }
                    if !e.isEmpty { style.edges = e }
                }
                // Leading rows that repeat on every page: all of them.
                let repeating = unwrapped(node, "w:tr").prefix { $0.first("w:trPr")?.first("w:tblHeader") != nil }.count
                if repeating > 0 { style.headerRow = true; style.headerRowCount = repeating }
                // The style's conditional parts, as w:tblLook switches them
                // on (attributes in 2010 files, bits of w:val in 2007's).
                let cond = node.first("w:tblPr")?.first("w:tblStyle")?["w:val"].flatMap { tableConds[$0] } ?? _Cond()
                let tableStyleSize = node.first("w:tblPr")?.first("w:tblStyle")?["w:val"].flatMap { tableSizes[$0] }
                let look = node.first("w:tblPr")?.first("w:tblLook")
                let lookVal = look.flatMap { Int($0["w:val"] ?? "", radix: 16) } ?? 0x04A0
                let firstRowOn = look?["w:firstRow"].map { $0 != "0" } ?? (lookVal & 0x0020 != 0)
                let bandsOn = !(look?["w:noHBand"].map { $0 != "0" } ?? (lookVal & 0x0200 != 0))
                let firstColOn = look?["w:firstColumn"].map { $0 != "0" } ?? (lookVal & 0x0080 != 0)
                // Where the table sits in the column (w:jc on the table).
                // (Or on its rows, every one of them, when the table says
                // nothing: a centred form came back at the left margin.)
                let rowJc = Set(unwrapped(node, "w:tr").map { $0.first("w:trPr")?.first("w:jc")?["w:val"] ?? "" })
                switch node.first("w:tblPr")?.first("w:jc")?["w:val"] ?? (rowJc.count == 1 ? rowJc.first! : "") {
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
                // (The table's own margins, else its style's, else Word's:
                // what the layout sets a table out by before Word 2013's
                // layout — a stated margin too, lab `tc` 2026-10-14.)
                let own = _cellMargins(node.first("w:tblPr"))
                let base = styled.under(defaultMargins).under(_Margins.word)
                style.textOutdent = own.left ?? base.left ?? 5.4
                style.textOutdentRight = own.right ?? base.right ?? 5.4
                // (… unless its first cell states its own: the table is set
                // out by the margin of the cell whose text it lines up.
                // zh-6143e5f0's plans, cells of zero margin in a table of
                // Word's 5.4pt, have their left rule on the page's margin
                // in Word's print, where ours stood 5.4pt left of it.)
                if let first = node.first("w:tr")?.first("w:tc"),
                   let l = _cellMargins(first.first("w:tcPr"), "w:tcMar").left {
                    style.textOutdent = l
                }
                // The table's own margins, for the save: the cells keep
                // their w:tcMar, and the cells that state none take these
                // (drawing.docx zeroes its banner row's and leaves 5.25pt
                // on the rest; flattened to zero, every article under a
                // banner sat that much high — 6.1% over twenty pages).
                if !cellMars.isEmpty {
                    let own = _cellMargins(node.first("w:tblPr")).under(styled).under(defaultMargins).under(_Margins.word)
                    var xml = "<w:tblCellMar>"
                    for (side, v) in [("top", own.top), ("left", own.left), ("bottom", own.bottom), ("right", own.right)] {
                        if let v { xml += "<w:\(side) w:w=\"\(Int((v * 20).rounded()))\" w:type=\"dxa\"/>" }
                    }
                    style.keptCellMarginsXML = xml + "</w:tblCellMar>"
                    style.keptCellMarginsUnder = [margins.top, margins.left, margins.bottom, margins.right]
                }
                if let ind = node.first("w:tblPr")?.first("w:tblInd"), (ind["w:type"] ?? "dxa") == "dxa",
                   let w = Double(ind["w:w"] ?? "") {
                    style.indent = w / 20
                }
                if let own = node.first("w:tblPr")?.first("w:tblLayout")?["w:type"] {
                    if own == "fixed" { style.fixedLayout = true }
                } else if node.first("w:tblPr")?.first("w:tblStyle")?["w:val"].map({ fixedTableStyles.contains($0) }) ?? defaultTableFixed {
                    style.fixedLayout = true
                }
                // A floating table's anchor (Bug54771b's title block sits at
                // the right margin, a set distance down the page).
                if let pos = node.first("w:tblPr")?.first("w:tblpPr") {
                    if pos["w:vertAnchor"] == "page" { style.pageAnchored = true }
                    if pos["w:vertAnchor"] == "page", pos["w:tblpYSpec"] == nil, let v = Double(pos["w:tblpY"] ?? "") { style.pageOffsetY = v / 20 }
                    style.keptPosition = PptxXML.serialize(pos)
                        + (node.first("w:tblPr")?.first("w:tblOverlap").map { PptxXML.serialize($0) } ?? "")
                    if pos["w:vertAnchor"] == "text", pos["w:tblpYSpec"] == nil, let v = Double(pos["w:tblpY"] ?? ""), v > 0 {
                        style.floatOffsetY = v / 20
                    }
                    if pos["w:vertAnchor"] == "text", pos["w:tblpYSpec"] == nil { style.floatsOverText = true }
                    if pos["w:vertAnchor"] == "text", pos["w:tblpYSpec"] == nil, let v = Double(pos["w:tblpY"] ?? ""), v < 0 {
                        style.floatRaiseY = -v / 20
                    }
                    if pos["w:tblpXSpec"] == nil, let v = Double(pos["w:tblpX"] ?? "") {
                        style.floatX = v / 20
                        style.floatXAnchor = pos["w:horzAnchor"] ?? "text"
                    } else if let spec = pos["w:tblpXSpec"], (pos["w:horzAnchor"] ?? "text") != "page" {
                        // Or aligned in its margin or column, a table wider
                        // than it standing out on both sides: zh-0243e7fc
                        // p11's 539pt form, centred on its 415pt margin, has
                        // its first column's text at 54pt in Word's print,
                        // where ours, at the margin, stood at 115.
                        if spec == "center" { style.alignment = .center }
                        if spec == "right" { style.alignment = .right }
                    }
                } else if case let frames = unwrapped(node, "w:tr").flatMap({ unwrapped($0, "w:tc") }).flatMap({ unwrapped($0, "w:p") })
                            .map({ $0.first("w:pPr")?.first("w:framePr") }),
                          !frames.isEmpty, let frame = frames[0], frame["w:vAnchor"] == "text", frame["w:wrap"] == "notBeside",
                          Set(frames.map { $0.map { PptxXML.serialize($0) } ?? "" }).count == 1 {
                    // A table set in a frame — Word writes one by giving
                    // every paragraph of every cell the same w:framePr —
                    // stands where the frame says, as a floating table
                    // does: its y below the text's place, the text under
                    // it, and centred on the margin where it says so.
                    // zh-621d8756 p15's form (y 342) starts 17.1pt under
                    // "需要补正内容如下：" in Word's print; ours sat on it.
                    if frame["w:yAlign"] == nil, let v = Double(frame["w:y"] ?? ""), v > 0 { style.floatOffsetY = v / 20 }
                    if frame["w:xAlign"] == "center", frame["w:x"] == nil { style.alignment = .center }
                } else if case let frames = unwrapped(node, "w:tr").flatMap({ unwrapped($0, "w:tc") }).flatMap({ unwrapped($0, "w:p") })
                            .map({ $0.first("w:pPr")?.first("w:framePr") }),
                          !frames.isEmpty, let frame = frames[0], frame["w:vAnchor"] == "page", frame["w:hAnchor"] == "page",
                          frame["w:wrap"] == "notBeside", frame["w:yAlign"] == nil, frame["w:xAlign"] == nil,
                          let fx = Double(frame["w:x"] ?? ""), let fy = Double(frame["w:y"] ?? ""),
                          Set(frames.map { $0.map { PptxXML.serialize($0) } ?? "" }).count == 1 {
                    // (Set in a frame placed on the page, the same way:
                    // the ICS and CCS lines of a standard's cover, zh-cd8987db
                    // — x 68.6, y 28.4 from the page's edge in Word's print,
                    // where ours flowed from the margin.)
                    style.pageAnchored = true
                    style.pageOffsetY = fy / 20
                    style.floatX = fx / 20
                    style.floatXAnchor = "page"
                }
                // A spacing of ZERO is still a statement: Word then rules each
                // cell on its own rather than collapsing shared edges, and
                // every row of an HTML-converted table stands a border
                // taller (bug57031's SAS tables, 2.2% -> 0.3% with the
                // table's zero written back; the rows' own add nothing).
                if let sp = node.first("w:tblPr")?.first("w:tblCellSpacing"), (sp["w:type"] ?? "dxa") == "dxa",
                   let w = Double(sp["w:w"] ?? ""), w >= 0 {
                    style.cellSpacing = w / 20
                }
                // The preferred width: HTML-converted tables say 100% and
                // their grid says less (bug65649's came back narrower).
                if let tw = node.first("w:tblPr")?.first("w:tblW"), let w = Double(tw["w:w"] ?? ""), w > 0 {
                    switch tw["w:type"] ?? "auto" {
                    case "pct": style.widthPercent = w / 50
                    case "dxa": style.width = w / 20
                    default: break
                    }
                }
                for (r, tr) in unwrapped(node, "w:tr").enumerated() {
                    if let h = tr.first("w:trPr")?.first("w:trHeight"), let v = Double(h["w:val"] ?? ""), v > 0 {
                        style.rowHeights[r] = v / 20
                        // An exact height stays exact: a comparison table of
                        // exact rows clips its cells, and at "at least" the
                        // copy ran 12 pages to the original's 9.
                        if h["w:hRule"] == "exact" { style.rowsExactHeight.insert(r) }
                    }
                    if let c = tr.first("w:trPr")?.first("w:cantSplit"), !_isOff(c) { style.rowsCantSplit.insert(r) }
                    // (A row's own cell spacing of none: zh-147bdae0's
                    // commitment tables state 0 and most of their rows
                    // nil, and those rows step a line apart in Word's print
                    // — 21.1pt a one-line row, ours 21.6, the 0.5pt line
                    // taken twice — where its first rows, 0 again, stand
                    // their lines in pairs.)
                    if style.cellSpacing != nil,
                       let sp = tr.first("w:trPr")?.first("w:tblCellSpacing") ?? tr.first("w:tblPrEx")?.first("w:tblCellSpacing"),
                       sp["w:type"] == "nil" {
                        style.rowsUnspaced.insert(r)
                    }
                    if let v = Int(tr.first("w:trPr")?.first("w:gridBefore")?["w:val"] ?? ""), v > 0 { style.rowsGridBefore[r] = v }
                    // Its cell spacing, borders and cell margins (the table's own
                    // and each cell's go back beside them).
                    if let ex = tr.first("w:tblPrEx") {
                        let kept = ["w:tblCellSpacing", "w:tblBorders", "w:tblCellMar"].compactMap { ex.first($0) }.map { PptxXML.serialize($0) }.joined()
                        if !kept.isEmpty { style.rowExceptions[r] = "<w:tblPrEx>" + kept + "</w:tblPrEx>" }
                    }
                }
                // Cells without a stated width autofit to their content.
                let widthless = cells.filter { c in
                    let w = c.first("w:tcPr")?.first("w:tcW")
                    return w == nil || w?["w:type"] == "auto"
                }.count
                if !cells.isEmpty, widthless * 2 > cells.count, !style.fixedLayout { style.autoCellWidths = true }
                if !cells.isEmpty, widthless == cells.count, style.width == nil, style.widthPercent == nil, !style.fixedLayout { style.contentFit = true }
                // (… and one whose stated cells are whole columns of one
                // width in twips, the rest auto: those columns keep their
                // width and the others are fitted — zh-72da925e's rain
                // tables, a 794-twip rank column beside six auto ones, are
                // 39.6/46.1/57.1/45.9/57.3/51.9/57.1pt in Word's print, the
                // year columns widened past a grid that parted "2001" / "年".)
                if !cells.isEmpty, !style.contentFit, widthless * 2 > cells.count, style.width == nil, style.widthPercent == nil, !style.fixedLayout {
                    var fixed: [Int: Double] = [:], auto = Set<Int>(), mixed = false
                    for tr in unwrapped(node, "w:tr") {
                        var col = Int(tr.first("w:trPr")?.first("w:gridBefore")?["w:val"] ?? "") ?? 0
                        for tc in unwrapped(tr, "w:tc") {
                            let span = max(1, Int(tc.first("w:tcPr")?.first("w:gridSpan")?["w:val"] ?? "") ?? 1)
                            let w = tc.first("w:tcPr")?.first("w:tcW")
                            if w == nil || w?["w:type"] == "auto" {
                                auto.formUnion(col ..< col + span)
                            } else if w?["w:type"] == "dxa", span == 1, let v = Double(w?["w:w"] ?? ""), v > 0, fixed[col].map({ $0 == v / 20 }) ?? true {
                                fixed[col] = v / 20
                            } else { mixed = true }
                            col += span
                        }
                    }
                    if !mixed, !fixed.isEmpty, auto.isDisjoint(with: fixed.keys) {
                        style.contentFit = true
                        style.contentFitFixed = fixed
                    }
                }
                // (A spaced table of a stated share whose cells state shares
                // of it, column by column: zh-045c5a75's article table,
                // 85% with cells of 12% and 2% and one auto.)
                if style.widthPercent != nil, (style.cellSpacing ?? 0) > 0, !style.fixedLayout {
                    var shares: [Int: Double] = [:], noWrap = Set<Int>(), mixed = false
                    for tr in unwrapped(node, "w:tr") {
                        var col = Int(tr.first("w:trPr")?.first("w:gridBefore")?["w:val"] ?? "") ?? 0
                        for tc in unwrapped(tr, "w:tc") {
                            let span = max(1, Int(tc.first("w:tcPr")?.first("w:gridSpan")?["w:val"] ?? "") ?? 1)
                            let w = tc.first("w:tcPr")?.first("w:tcW")
                            if w?["w:type"] == "pct", span == 1, let v = Double((w?["w:w"] ?? "").replacingAll("%", with: "")) {
                                let share = (w?["w:w"] ?? "").hasSuffix("%") ? v : v / 50
                                if let had = shares[col], abs(had - share) > 0.01 { mixed = true }
                                shares[col] = share
                                if tc.first("w:tcPr")?.first("w:noWrap") != nil { noWrap.insert(col) }
                            } else if w != nil, w?["w:type"] != "auto" { mixed = true }
                            col += span
                        }
                    }
                    if !mixed, !shares.isEmpty { style.columnPercents = shares; style.noWrapColumns = noWrap }
                }
                if style != TableStyle() { tableStyles[id] = style }
                // vMerge: "restart" opens a span in a column; a bare vMerge
                // continues it, and that cell's (empty) content is dropped.
                var openSpan: [Int: Range<Int>] = [:]   // column → the spanning cell's paragraphs
                let rowCount = unwrapped(node, "w:tr").count
                let gridCount = tableColumns[id]?.count ?? Int.max
                for (r, tr) in unwrapped(node, "w:tr").enumerated() {
                    // (A row's cells start after the grid columns it leaves
                    // empty: zh-51af781b's scoring table switches from a
                    // first cell spanning 5 + 840 twips to gridBefore 1 and
                    // an 840 cell at row 165, and ours set each number in
                    // the 5-twip column a character a line and each
                    // description in the number's — 70 pages to Word's 65.)
                    var column = style.rowsGridBefore[r] ?? 0
                    for tc in unwrapped(tr, "w:tc") {
                        let tcPr = tc.first("w:tcPr")
                        let span = max(1, Int(tcPr?.first("w:gridSpan")?["w:val"] ?? "1") ?? 1)
                        var restart = false
                        if let v = tcPr?.first("w:vMerge") {
                            if v["w:val"] == "restart" {
                                restart = true
                            } else if let range = openSpan[column], range.upperBound <= paragraphs.count {
                                // Every paragraph of the cell carries the span,
                                // and this row's own stated sides.
                                var contEdges = _edges(tcPr, "w:tcBorders")
                                contEdges?.insideH = nil; contEdges?.insideV = nil
                                let contXML = tcPr?.first("w:tcBorders").map { PptxXML.serialize($0) }
                                // Its own (empty) paragraphs, as written — when
                                // that is all it holds and they name no part.
                                let blocks = tc.children.filter { $0.name != "w:tcPr" }
                                var contContent: String? = nil
                                if !blocks.isEmpty, blocks.allSatisfy({ $0.name == "w:p" }) {
                                    let xml = blocks.map { PptxXML.serialize($0) }.joined()
                                    if !xml.containsSubstring(" r:") && !xml.containsSubstring("<w:drawing") && !xml.containsSubstring("<w:pict") { contContent = xml }
                                }
                                // … and read, for the height they ask of a row
                                // that has no cell of its own (`RichLayout`).
                                var contParagraphs: [RichParagraph] = []
                                if contContent != nil {
                                    for block in blocks where block.first("w:pPr")?.first("w:numPr") == nil {
                                        contParagraphs += _paragraphs(block, cellBase, styleByDocx, styleNums, sheet, kindByNum, rels, media, indent, notes, cellChar,
                                                                      { id in chainOver(id, cellBase, cellRootBase) }).map(\.paragraph)
                                    }
                                }
                                for k in range {
                                    paragraphs[k].cell?.rowSpan += 1
                                    paragraphs[k].cell?.continuationEdges.append(contEdges)
                                    paragraphs[k].cell?.continuationBordersXML.append(contXML)
                                    paragraphs[k].cell?.continuationContentXML.append(contContent)
                                    paragraphs[k].cell?.continuationParagraphs.append(contParagraphs)
                                }
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
                        // The cell's own borders, when they differ from the
                        // table's verdict: nil sides inside a ruled table.
                        // The cell's own sides, where they differ from what
                        // the table gives that position (an outer side on
                        // the rim, an inside one elsewhere).
                        // (A row's own borders — `w:tblPrEx` — stand for its
                        // cells' unstated sides: form_footnotes' last table
                        // rules nothing inside, its rows rule every line
                        // between them, and its rows stood a rule short.)
                        var rowSides: XNode? = nil
                        if let rex = tr.first("w:tblPrEx")?.first("w:tblBorders") {
                            let lastRowHere = r == rowCount - 1, lastColHere = column + span >= gridCount
                            let said = tcPr?.first("w:tcBorders")
                            let made = XNode(name: "w:tcBorders", attrs: [:])
                            for (side, from) in [("top", r == 0 ? "top" : "insideH"), ("left", column == 0 ? "left" : "insideV"),
                                                 ("bottom", lastRowHere ? "bottom" : "insideH"), ("right", lastColHere ? "right" : "insideV")] {
                                guard said?.first("w:" + side) == nil, let e = rex.first("w:" + from) else { continue }
                                made.children.append(XNode(name: "w:" + side, attrs: e.attrs))
                            }
                            if !made.children.isEmpty { rowSides = made }
                        }
                        // (The header row's own lines from the table style's
                        // `firstRow`, where the cell states none: zh-61aaad09's
                        // "浅色网格" header rules its foot 2.25pt, drawn so in
                        // Word's print and the two rows either side of it each
                        // half that taller; ours drew 1pt and stood 1.2 short.
                        // Not the foot of a cell merged on down: Word ends the
                        // merged "销售方式" cell on the inside line.)
                        if r == 0, firstRowOn, let hb = cond.headerBorders {
                            let said = tcPr?.first("w:tcBorders")
                            let mergesOn = tcPr?.first("w:vMerge")?["w:val"] == "restart"
                            let made = rowSides ?? XNode(name: "w:tcBorders", attrs: [:])
                            for side in ["top", "left", "bottom", "right"] where !(side == "bottom" && mergesOn) {
                                guard said?.first("w:" + side) == nil, made.first("w:" + side) == nil, let e = hb.first("w:" + side) else { continue }
                                made.children.append(XNode(name: "w:" + side, attrs: e.attrs))
                            }
                            if !made.children.isEmpty { rowSides = made }
                        }
                        let sidesPr: XNode? = {
                            guard let rowSides else { return tcPr }
                            let merged = XNode(name: "w:tcBorders", attrs: [:])
                            merged.children = (tcPr?.first("w:tcBorders")?.children ?? []) + rowSides.children
                            let pr = XNode(name: "w:tcPr", attrs: [:])
                            pr.children = [merged]
                            return pr
                        }()
                        var ownEdges: BorderEdges? = nil
                        if var own = _edges(sidesPr, "w:tcBorders") {
                            own.insideH = nil; own.insideV = nil
                            if style.bordersFromCells {
                                // Every stated side stays: the writer puts
                                // no table-level borders under them.
                                ownEdges = own
                            } else {
                            let te = style.edges ?? BorderEdges()
                            let lastRow = r == rowCount - 1, lastCol = column + span >= gridCount
                            // A cell ruled at its own width keeps the sides it
                            // draws even where the table draws them too — the
                            // width is the difference (form_footnotes' heading
                            // cell: 2.25pt over the table's 1.5pt).
                            let ownWidth = _borders(tcPr, "w:tcBorders")?.width
                            let wider = ownWidth != nil && ownWidth != (style.borderWidth ?? 0.5)
                            if wider {
                                if own.top == false, own.top == (r == 0 ? te.top : te.insideH) ?? style.borders { own.top = nil }
                                if own.left == false, own.left == (column == 0 ? te.left : te.insideV) ?? style.borders { own.left = nil }
                                if own.bottom == false, own.bottom == (lastRow ? te.bottom : te.insideH) ?? style.borders { own.bottom = nil }
                                if own.right == false, own.right == (lastCol ? te.right : te.insideV) ?? style.borders { own.right = nil }
                            } else {
                            if own.top == (r == 0 ? te.top : te.insideH) ?? style.borders { own.top = nil }
                            if own.left == (column == 0 ? te.left : te.insideV) ?? style.borders { own.left = nil }
                            if own.bottom == (lastRow ? te.bottom : te.insideH) ?? style.borders { own.bottom = nil }
                            if own.right == (lastCol ? te.right : te.insideV) ?? style.borders { own.right = nil }
                            }
                            if !own.isEmpty { ownEdges = own }
                            }
                        }
                        let vAlign = tcPr?.first("w:vAlign")?["w:val"].flatMap { ["center", "bottom"].contains($0) ? $0 : nil }
                        currentCell = CellRef(table: id, row: r, column: column, span: span, fill: fill, edges: ownEdges, verticalAlign: vAlign)
                        currentCell?.bordersXML = tcPr?.first("w:tcBorders").map { PptxXML.serialize($0) }
                        currentCell?.rowBordersXML = rowSides.map { PptxXML.serialize($0) }
                        currentCell?.marginsXML = tcPr?.first("w:tcMar").map { PptxXML.serialize($0) }
                        // (Its own margins, over the table's: zh-6cd1befe's
                        // list of emergency departments narrows its cells'
                        // margins to 51 twips where the table says 108, and
                        // "生物灾害指因病" at 10pt fills its 70.5pt line in
                        // Word's print; at the table's margins ours held six.)
                        if tcPr?.first("w:tcMar") != nil {
                            let m = _cellMargins(tcPr, "w:tcMar").under(margins)
                            currentCell?.padding = EdgeInsets(left: m.left ?? 5.4, top: m.top ?? 0, right: m.right ?? 5.4, bottom: m.bottom ?? 0)
                        } else if !cellMars.isEmpty, cellMar.top != nil || cellMar.left != nil || cellMar.bottom != nil || cellMar.right != nil {
                            // (And one that states none, where the table's
                            // margins were taken from what most cells say,
                            // has the table's own: drawing.docx's article
                            // rows zero their cells' margins but one, whose
                            // 5.25pt above and below the table's 105 twips
                            // give — its articles stood 5pt high of Word's.)
                            // (Its row's own exception first: the logo row
                            // above them zeroes its margins in `w:tblPrEx`.)
                            let m = _cellMargins(tr.first("w:tblPrEx")).under(_cellMargins(node.first("w:tblPr")))
                                .under(styled).under(defaultMargins).under(_Margins.word)
                            currentCell?.padding = EdgeInsets(left: m.left ?? 5.4, top: m.top ?? 0, right: m.right ?? 5.4, bottom: m.bottom ?? 0)
                        } else if case let ex = _cellMargins(tr.first("w:tblPrEx")), ex.top != nil || ex.left != nil || ex.bottom != nil || ex.right != nil {
                            // (A row's own margins — `w:tblPrEx` — over the
                            // table's, for a cell that states none: zh-64044a1d's
                            // task tables say 28 twips a side and every row 108,
                            // and Word's print sets the duty column's text 5.4pt
                            // in, where ours at 1.4 held a character more a line.)
                            let m = ex.under(margins)
                            currentCell?.padding = EdgeInsets(left: m.left ?? 5.4, top: m.top ?? 0, right: m.right ?? 5.4, bottom: m.bottom ?? 0)
                        }
                        let keptCell = ["w:noWrap", "w:tcFitText", "w:hideMark"].compactMap { tcPr?.first($0) }.map { PptxXML.serialize($0) }.joined()
                        currentCell?.keptPropertiesXML = keptCell.isEmpty ? nil : keptCell
                        if let grid = tableColumns[id], column + span <= grid.count {
                            currentCell?.widthXML = tcPr?.first("w:tcW").map { PptxXML.serialize($0) }
                            currentCell?.widthKeptUnder = grid[column ..< column + span].map { Int(($0 * 20).rounded()) }.reduce(0, +)
                        }
                        currentCell?.bordersKeptUnder = style.borders
                        // The cell's own line width, over the table's.
                        if let w = _borders(tcPr, "w:tcBorders")?.width, w != (style.borderWidth ?? 0.5) { currentCell?.borderWidth = w }
                        // Text turned a quarter (Word's w:textDirection);
                        // its vertical writing keeps ideographs upright.
                        let direction = tcPr?.first("w:textDirection")?["w:val"]
                        switch direction {
                        case "tbRl", "tbRlV", "tbLrV":
                            currentCell?.textDirection = .down
                            currentCell?.uprightIdeographs = true
                        case "btLr": currentCell?.textDirection = .up
                        default: break
                        }
                        // (lrTbV is a horizontal cell — its text runs left to
                        // right as any, only East Asian characters turned
                        // where a vertical layout would stand them: zh-e0ca7252's
                        // equipment list, every cell lrTbV, has rows of a
                        // 12pt line in Word's print, where ours turned them
                        // and its 29 empty rows were 4pt apiece. Kept, so the
                        // save writes it back.)
                        if direction != nil, currentCell?.textDirection != .horizontal || direction == "lrTbV" { currentCell?.textDirectionValue = direction }
                        cellChar = r == 0 && firstRowOn ? (cond.headerChar ?? CharStyle())
                            : (column == 0 && firstColOn ? (cond.firstColChar ?? CharStyle()) : CharStyle())
                        notes.cellSizeFromTable = false
                        if cellChar.fontSize == nil, !normalStatesSize, let size = tableStyleSize { cellChar.fontSize = size; notes.cellSizeFromTable = true }
                        let before = paragraphs.count
                        for child in tc.children { walkBlock(child, indent: indent, depth: depth + 1) }
                        if paragraphs.count == before { emit(RichParagraph(style: cellBase)) }
                        else { flagMarkUnderNestedTable(tc, since: before) }
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
            case "w:bookmarkStart":
                if let name = node["w:name"], name != "_GoBack" { notes.pendingBookmarks.append(name) }
            case "w:commentRangeStart":
                // A range may open or close between paragraphs
                // (WordWithAttachments), not only inside one.
                if notes.kept["word/comments.xml"] != nil, let id = node["w:id"] { notes.openComments.append(id); notes.seenComments.insert(id) }
            case "w:commentRangeEnd":
                if let id = node["w:id"] { notes.openComments.removeAll { $0 == id } }
            case "w:sectPr":
                pageSetup = _pageSetup(node)
            default:
                break
            }
        }
        for child in body.children { walkBlock(child, indent: 0) }
        recordingBody = false
        // A section of columns that a continuous section follows on the
        // same page, its columns filled by column breaks, is set as a row
        // of a borderless table: one cell a column, the columns' gaps
        // between them — the layout has one column count for the whole
        // document. zh-a0e932c2's "12 | 大肠菌群 | GB 4789.3 大肠菌群
        // 平板计数法" row of three unequal columns had taken a page a
        // column. The section's end stays a top-level paragraph of its
        // own, empty (it takes no room), so the sections count as they
        // did; the markup is kept for the save (`KeptTable`, id "kc…").
        do {
            var out: [RichParagraph] = []
            out.reserveCapacity(paragraphs.count + 8)
            var start = 0
            // (The document's own last section too, where it follows others
            // on their page: zh-8f9b19f4 ends in a continuous section of
            // three columns, "填报人：" | "审核人：" | "负责人：", which Word
            // prints as one line and ours as a page each.)
            let finalSect = body.first("w:sectPr")
            let finalColumns = finalSect.flatMap { sect -> String? in
                guard sect.first("w:type")?["w:val"] == "continuous" else { return nil }
                return PptxXML.serialize(sect)
            }
            let finalPage = finalSect.flatMap { _pageSetup($0) }
            for (i, para) in paragraphs.enumerated() {
                out.append(para)
                let final = para.style.sectionXML == nil && i == paragraphs.count - 1 && start > 0 && finalColumns != nil
                guard para.cell == nil, para.style.sectionXML != nil || final else { continue }
                defer { start = i + 1 }
                // (… or one that follows another on its page itself, a
                // page starting after it: zh-b8de3ae2's "資料來源" | " ",
                // a column break into a second column of 422pt before a
                // section of its own page, has the space in the second
                // column at the note's height in Word's print, where ours
                // took the break for a page — a blank page, every page
                // after it one late.)
                let opensOnItsPage = start > 0 && para.style.sectionXML.flatMap { XNode.parse(Data($0.utf8)) }?
                    .descendant("w:type")?["w:val"] == "continuous"
                guard para.style.sectionBreaksPage == false || final || opensOnItsPage, let sx = para.style.sectionXML ?? finalColumns,
                      let gaps = _sectionColumns(sx, final ? finalPage : para.style.sectionPage), gaps.count > 1,
                      paragraphs[start ... i].allSatisfy({ $0.cell == nil }) else { continue }
                var columns: [[RichParagraph]] = [[]]
                for k in start ... i {
                    var q = paragraphs[k]
                    if k > start, q.style.columnBreak, q.style.pageBreakBefore {
                        // (A paragraph that is only the break opens the next
                        // column with its line, where a page's would stay on
                        // the page before: zh-6cd1befe's "附件3" | (break) |
                        // "应急保障职责部门任务分配表" has the break's empty
                        // line at the second column's head in Word's print,
                        // the title under it, 20.7pt lower than ours.)
                        var carried: RichParagraph? = nil
                        if q.style.breakEndsPrevious, let prev = columns[columns.count - 1].last, prev.text.isEmpty, prev.image == nil,
                           columns[columns.count - 1].count > 1 {
                            carried = columns[columns.count - 1].removeLast()
                        }
                        columns.append(carried.map { [$0] } ?? [])
                        q.style.pageBreakBefore = false
                        q.style.columnBreak = false
                        q.style.breakEndsPrevious = false
                        q.style.breakRunPropertiesXML = nil
                    }
                    columns[columns.count - 1].append(q)
                }
                guard columns.count == gaps.count, (start ... i).allSatisfy({ bodyNodes[$0] != nil }) else { continue }
                // (Only where every paragraph's markup can be kept for the save:
                // one that names a part the package does not hold — LibreOffice's
                // tdf123163-1 has a picture with no media in it — has none, and
                // was left out of the kept markup, text and all.)
                var captured = Set<ObjectIdentifier>()
                guard (start ... i).allSatisfy({ k in
                    let node = bodyNodes[k]!
                    return !captured.insert(ObjectIdentifier(node)).inserted || _keptFragment(node, notes) != nil
                }) else { continue }
                out.removeLast(i - start + 1)
                tableCount += 1
                let id = "t\(tableCount)"
                keptTableCount += 1
                let kid = "kc\(keptTableCount)"
                var widths: [Double] = []
                let firstOut = out.count
                // (The section's end: its text in the cell, its break
                // after the table — and an empty one not in the cell at
                // all, as it takes no room in Word: zh-a0e932c2's put a
                // line under "法" and the table after the row 12pt low.)
                if let last = columns[columns.count - 1].last, last.text.isEmpty, last.image == nil, columns[columns.count - 1].count > 1 {
                    columns[columns.count - 1].removeLast()
                }
                for (c, column) in columns.enumerated() {
                    for var q in column {
                        q.style.sectionXML = nil; q.style.sectionRels = []; q.style.sectionPage = nil; q.style.sectionBreaksPage = nil
                        q.cell = CellRef(table: id, row: 0, column: c * 2)
                        out.append(q)
                    }
                    widths.append(gaps[c].width)
                    if c < columns.count - 1 {
                        var gap = RichParagraph(style: column.last?.style ?? RichParagraphStyle())
                        gap.style.sectionXML = nil; gap.style.sectionPage = nil; gap.style.sectionBreaksPage = nil
                        // (None of its indents: in the narrow gap a column's
                        // last paragraph's 56pt indent widened the gap, and
                        // zh-a0e932c2's second column stood 16pt right.)
                        gap.style.indentLeft = 0; gap.style.indentRight = 0; gap.style.firstLineIndent = 0
                        for key in ["w:leftChars", "w:startChars", "w:rightChars", "w:endChars", "w:hangingChars", "w:firstLineChars"] { gap.style.eastAsian[key] = nil }
                        gap.cell = CellRef(table: id, row: 0, column: c * 2 + 1)
                        out.append(gap)
                        widths.append(gaps[c].space)
                    }
                }
                if !final {
                    var mark = RichParagraph(style: para.style)
                    mark.style.pageBreakBefore = false
                    mark.style.columnBreak = false
                    mark.style.breakEndsPrevious = false
                    mark.style.breakRunPropertiesXML = nil
                    out.append(mark)
                }
                tableColumns[id] = widths
                var ts = TableStyle()
                ts.borders = false
                ts.sectionColumns = true
                ts.cellMarginTop = 0; ts.cellMarginLeft = 0; ts.cellMarginBottom = 0; ts.cellMarginRight = 0
                tableStyles[id] = ts
                var xml = "", kept: [KeptRel] = []
                var seenNodes = Set<ObjectIdentifier>()
                for k in start ... i {
                    let node = bodyNodes[k]!
                    guard seenNodes.insert(ObjectIdentifier(node)).inserted, let frag = _keptFragment(node, notes) else { continue }
                    xml += frag.xml
                    for r in frag.rels where !kept.contains(where: { $0.id == r.id }) { kept.append(r) }
                }
                for k in firstOut ..< out.count { out[k].keptTable = kid }
                keptTables[kid] = KeptTable(xml: xml, rels: kept, texts: out[firstOut...].map(\.text))
            }
            paragraphs = out
        }
        // The caret must be able to leave a table that ends the document.
        if paragraphs.isEmpty || paragraphs.last?.cell != nil { paragraphs.append(RichParagraph()) }
        // The kept headers and footers again as paragraphs, read like the
        // body (each part by its own relationships), for the layout.
        var headerFooters: [RichHeaderFooter] = []
        do {
            let bodyParagraphs = paragraphs, bodyRels = rels, bodyInfo = notes.rels
            // Section by section: what each names, and what it does
            // not it has from the one before — type by type, so a
            // section that names only a first page's footer goes on
            // with the earlier default one.
            var earlier: [XNode] = []
            func sections(_ n: XNode) {
                for c in n.children {
                    if c.name == "w:p", let sp = c.first("w:pPr")?.first("w:sectPr") { earlier.append(sp) }
                    else if c.name != "w:p", c.name != "w:sectPr" { sections(c) }
                }
            }
            sections(body)
            var named: [String: (kind: KeptHeaderFooter.Kind, type: String, part: String)] = [:]
            var perSection: [[String: (kind: KeptHeaderFooter.Kind, type: String, part: String)]] = []
            for sect in earlier {
                for ref in sect.children where ref.name == "w:headerReference" || ref.name == "w:footerReference" {
                    let kind: KeptHeaderFooter.Kind = ref.name == "w:headerReference" ? .header : .footer
                    let type = ref["w:type"].map { $0 == "odd" ? "default" : $0 } ?? "default"
                    guard ["default", "first", "even"].contains(type),
                          let rid = ref["r:id"], let target = relInfo[rid]?.target, !(relInfo[rid]?.external ?? false) else { continue }
                    named["\(kind.rawValue)|\(type)"] = (kind, type, _resolvePath("word", target))
                }
                perSection.append(named)
            }
            for k in keptHeaderFooters { named["\(k.kind.rawValue)|\(k.type)"] = (k.kind, k.type, k.part) }
            perSection.append(named)
            // (Counted as the layout counts them; where the two differ
            // the last section's stand for every page.)
            var marks = 0
            for (i, p) in bodyParagraphs.enumerated() where p.cell == nil && p.style.sectionPage != nil && i < bodyParagraphs.count - 1 { marks += 1 }
            let numbered = marks == earlier.count
            if !numbered { perSection = [named] }
            var read: [String: [RichParagraph]] = [:]
            func paragraphsOf(_ path: String) -> [RichParagraph] {
                if let hit = read[path] { return hit }
                read[path] = []
                // (A phantom part — see below — is Word's empty header or
                // footer: its built-in style, Normal set single with
                // nothing after.)
                // (A header's first line is in that style and its second
                // in Normal, spacing and all: Word's two marks stand 13.5pt
                // apart at 11pt, and its body starts 11.9pt under the
                // second's line — Normal's 1.15 lines and 10pt after. A
                // footer is the one line in that style: as Normal, the
                // page held a line fewer than Word's.)
                let phantom: Data? = path == "phantom:mark" ? Data("<w:hdr xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:p/></w:hdr>".utf8)
                    : path.hasPrefix("phantom:") ? Data((
                    "<w:\(path.hasSuffix("header") ? "hdr" : "ftr") xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">"
                    + "<w:p><w:pPr><w:spacing w:after=\"0\" w:line=\"240\" w:lineRule=\"auto\"/></w:pPr></w:p>"
                    + (path.hasSuffix("header") ? "<w:p/>" : "")
                    + "</w:\(path.hasSuffix("header") ? "hdr" : "ftr")>").utf8) : nil
                guard let data = phantom ?? part(path), let node = XNode.parse(data) else { return [] }
                _inheritSpace(node)
                // (Their theme font references too: zh-a4b0f6ea's page
                // numbers are `majorEastAsia`, 宋体, in a footer.)
                _resolveThemeFonts(node, theme)
                var comps = path.split(separator: "/").map(String.init)
                let file = comps.popLast() ?? ""
                let dir = comps.joined(separator: "/")
                rels = [:]
                var info: [String: KeptRel] = [:]
                if let relsData = part(dir + "/_rels/" + file + ".rels"), let relsNode = XNode.parse(relsData) {
                    for r in relsNode.all("Relationship") {
                        guard let id = r["Id"], let target = r["Target"] else { continue }
                        rels[id] = target
                        info[id] = KeptRel(id: id, type: r["Type"] ?? "", target: target, external: r["TargetMode"] == "External")
                    }
                }
                notes.rels = info
                notes.inHeaderFooter = true
                paragraphs = []
                currentCell = nil
                pendingPageBreak = false
                for child in node.children { walkBlock(child, indent: 0) }
                notes.inHeaderFooter = false
                read[path] = paragraphs
                return paragraphs
            }
            for (s, entries) in perSection.enumerated() {
                for key in entries.keys.sorted() {
                    guard let hf = entries[key] else { continue }
                    var made = paragraphsOf(hf.part)
                    // (And a header it has ends in one more empty Normal
                    // paragraph: lab `5f` (zh-5f9b6549's package, Word 16,
                    // 2026-10-22) — its two empty header marks are followed
                    // by a 12pt Normal one, 67.3 to 80.6, and the body starts
                    // under it, 8.6pt below its 72pt margin; with Normal at
                    // 24pt that mark is 24pt, and without the background it
                    // is gone and the body starts at the margin. The footer
                    // stays as it is.)
                    if hf.kind == .header, !made.isEmpty, root.first("w:background") != nil, !Self.wordOnWindows { made += paragraphsOf("phantom:mark") }
                    if !made.isEmpty {
                        headerFooters.append(RichHeaderFooter(kind: hf.kind, type: hf.type, paragraphs: made, section: numbered ? s : nil))
                    }
                }
            }
            // A document with a background (`w:background`, never
            // printed) is laid out by Word as if it had a header of two
            // empty paragraphs and a footer of one wherever it has none: lab
            // `bg1`/`bg2` (bib-chernigovka's package, Word 16,
            // 2026-10-15) — with the background Word's print holds two
            // empty header marks and a footer mark and the body runs
            // 85.7 to 783.8 down the page; without it, no marks and 68.2
            // to 793. bib-chernigovka matched none of Word's lines, each
            // page's text 18 to 50pt higher than Word's. (So do 61991
            // and 51921-Word-Crash067, whose margins happen to hold it.)
            // (Word for Mac's only: Word for Windows lays such a file out
            // with no marks at all — its prints (word-win) of zh-b875d786,
            // zh-c599aaa1, zh-15f67ef1 and zh-4adfcce2 start the body at
            // the margin, 7 to 29pt above the Mac's.)
            if root.first("w:background") != nil, !Self.wordOnWindows {
                for kind in [KeptHeaderFooter.Kind.header, .footer] where !headerFooters.contains(where: { $0.kind == kind }) {
                    let made = paragraphsOf(kind == .header ? "phantom:header" : "phantom:footer")
                    if !made.isEmpty { headerFooters.append(RichHeaderFooter(kind: kind, type: "default", paragraphs: made)) }
                }
            }
            paragraphs = bodyParagraphs
            rels = bodyRels
            notes.rels = bodyInfo
            currentCell = nil
            pendingPageBreak = false
        }
        // The footnotes, each read like the body, its own mark showing
        // the number the body's mark was given.
        var footnoteParagraphs: [Int: [RichParagraph]] = [:]
        var footnoteSeparator: [RichParagraph] = []
        if notes.footnotes, let data = part("word/footnotes.xml"), let root = XNode.parse(data) {
            _resolveThemeFonts(root, theme)
            let bodyParagraphs = paragraphs, bodyRels = rels, bodyInfo = notes.rels
            rels = [:]
            var info: [String: KeptRel] = [:]
            if let relsData = part("word/_rels/footnotes.xml.rels"), let relsNode = XNode.parse(relsData) {
                for r in relsNode.all("Relationship") {
                    guard let id = r["Id"], let target = r["Target"] else { continue }
                    rels[id] = target
                    info[id] = KeptRel(id: id, type: r["Type"] ?? "", target: target, external: r["TargetMode"] == "External")
                }
            }
            notes.rels = info
            notes.inHeaderFooter = true
            let saved = (notes.seenFootnotes, notes.seenEndnotes)
            for note in root.all("w:footnote") {
                guard let id = Int(note["w:id"] ?? "") else { continue }
                let type = note["w:type"] ?? "normal"
                guard type == "normal" || type == "separator" else { continue }
                guard type == "separator" || notes.footnoteNumbers[id] != nil else { continue }
                notes.currentNote = notes.footnoteNumbers[id]
                paragraphs = []
                currentCell = nil
                pendingPageBreak = false
                for child in note.children { walkBlock(child, indent: 0) }
                if type == "separator" { footnoteSeparator = paragraphs } else { footnoteParagraphs[id] = paragraphs }
            }
            notes.currentNote = nil
            (notes.seenFootnotes, notes.seenEndnotes) = saved
            notes.inHeaderFooter = false
            paragraphs = bodyParagraphs
            rels = bodyRels
            notes.rels = bodyInfo
            currentCell = nil
            pendingPageBreak = false
        }
        // The endnotes, the same way: set after the body's last paragraph.
        var endnoteParagraphs: [Int: [RichParagraph]] = [:]
        var endnoteSeparator: [RichParagraph] = []
        if notes.endnotes, let data = part("word/endnotes.xml"), let root = XNode.parse(data) {
            _resolveThemeFonts(root, theme)
            let bodyParagraphs = paragraphs, bodyRels = rels, bodyInfo = notes.rels
            rels = [:]
            var info: [String: KeptRel] = [:]
            if let relsData = part("word/_rels/endnotes.xml.rels"), let relsNode = XNode.parse(relsData) {
                for r in relsNode.all("Relationship") {
                    guard let id = r["Id"], let target = r["Target"] else { continue }
                    rels[id] = target
                    info[id] = KeptRel(id: id, type: r["Type"] ?? "", target: target, external: r["TargetMode"] == "External")
                }
            }
            notes.rels = info
            notes.inHeaderFooter = true
            let saved = (notes.seenFootnotes, notes.seenEndnotes)
            for note in root.all("w:endnote") {
                guard let id = Int(note["w:id"] ?? "") else { continue }
                let type = note["w:type"] ?? "normal"
                guard type == "normal" || type == "separator" else { continue }
                guard type == "separator" || notes.endnoteNumbers[id] != nil else { continue }
                notes.currentNoteLabel = notes.endnoteNumbers[id].map { notes.label($0, footnote: false) }
                paragraphs = []
                currentCell = nil
                pendingPageBreak = false
                for child in note.children { walkBlock(child, indent: 0) }
                if type == "separator" { endnoteSeparator = paragraphs } else { endnoteParagraphs[id] = paragraphs }
            }
            notes.currentNoteLabel = nil
            (notes.seenFootnotes, notes.seenEndnotes) = saved
            notes.inHeaderFooter = false
            paragraphs = bodyParagraphs
            rels = bodyRels
            notes.rels = bodyInfo
            currentCell = nil
            pendingPageBreak = false
        }
        var document = RichDocument(paragraphs: paragraphs)
        document.headerFooters = headerFooters
        document.footnotes = footnoteParagraphs
        document.footnoteSeparator = footnoteSeparator
        document.endnotes = endnoteParagraphs
        document.endnoteSeparator = endnoteSeparator
        document.tableColumns = tableColumns
        document.tableStyles = tableStyles
        document.styles = sheet
        document.styleAliases = styleAliases
        document.keptCharacterStyles = keptCharacterStyles
        document.keptCharacterStyleIds = keptCharacterStyleIds
        document.readFromFile = true
        document.fileFonts = _declaredFonts(docData).union(_declaredFonts(part("word/styles.xml")))
        document.listFormats = listFormats
        document.listCounterOf = listCounterOf
        document.listRestarts = listRestarts
        if let bg = root.first("w:background"), let frag = _keptFragment(bg, notes) {
            document.backgroundXML = frag.xml
            document.backgroundRels = frag.rels
        }
        document.keptParts = notes.kept
        document.keptPartTypes = notes.keptTypes
        document.keptTables = keptTables
        document.keptHeaderFooters = keptHeaderFooters
        document.titlePage = titlePage
        document.evenAndOddHeaders = evenAndOddHeaders
        document.widowControlSuspended = footerFramed
        document.keptCompat = keptCompat
        document.defaultTabStop = defaultTabStop
        if let pb = body.first("w:sectPr")?.first("w:pgBorders") { document.pageBordersXML = PptxXML.serialize(pb) }
        if let sect = body.first("w:sectPr") {
            if let grid = sect.first("w:docGrid") {
                document.docGridXML = PptxXML.serialize(grid)
                if let type = grid["w:type"], type == "lines" || type == "linesAndChars", let pitch = Double(grid["w:linePitch"] ?? ""), pitch > 0 {
                    document.lineGridPitch = pitch / 20
                }
                // (A grid of characters that adds nothing to them is a grid
                // all the same: its lines hold whole characters — zh-18cb2079,
                // linesAndChars with no charSpace, sets 27 of 16pt in a
                // 442pt column in Word's print, where ours squeezed three
                // marks for a 28th. A hair stands for none.)
                if grid["w:type"] == "linesAndChars" {
                    let space = Double(grid["w:charSpace"] ?? "") ?? 0
                    document.characterGridSpace = space != 0 ? space / 4096 : 1e-6
                }
            }
            document.sectionTypeXML = sect.first("w:type").map { PptxXML.serialize($0) }
            if let cols = sect.first("w:cols") {
                document.columnsXML = PptxXML.serialize(cols)
                document.columnsKeptUnder = max(1, Int(cols["w:num"] ?? "1") ?? 1)
            }
            document.gutterTwips = sect.first("w:pgMar")?["w:gutter"].flatMap { Int($0) }.flatMap { $0 > 0 ? $0 : nil }
            let lead = ["w:lnNumType", "w:pgNumType"].compactMap { sect.first($0) }.map { PptxXML.serialize($0) }.joined()
            let tail = ["w:vAlign", "w:textDirection", "w:bidi", "w:rtlGutter"].compactMap { sect.first($0) }.map { PptxXML.serialize($0) }.joined()
            document.sectionLeadXML = lead.isEmpty ? nil : lead
            if let num = sect.first("w:pgNumType") {
                document.pageNumberStart = Int(num["w:start"] ?? "")
                document.pageNumberFormat = num["w:fmt"]
            }
            document.sectionTailXML = tail.isEmpty ? nil : tail
        }
        // (A file with no settings at all, or no styles, is set by the
        // East Asian rules: Word reads it as one of its older documents.)
        if part("word/settings.xml") == nil { document.usesEastAsianLayout = true }
        if let table = part("word/fontTable.xml").flatMap(XNode.parse) {
            var charsets: [String: String] = [:]
            for font in table.all("w:font") {
                guard let name = font["w:name"], name.unicodeScalars.contains(where: { $0.value >= 0x2E80 }),
                      let charset = font.first("w:charset")?["w:val"] else { continue }
                // (Where the table repeats a name, its East Asian entry over
                // a charset-00 one, whichever comes first: zh-01bbcd4d lists
                // 方正仿宋简体 as GB2312, then as charset 00 with no PANOSE,
                // and Word sets its digits in YaHei, an East Asian face's
                // stand-in — ours took the second for a Latin face's;
                // zh-3f871b7d lists 仿宋_GB2312 as 00, then 86, and Word's
                // print is the East Asian face's.)
                if charsets[name] == nil || charsets[name] == "00" { charsets[name] = charset }
            }
            if !charsets.isEmpty { OfficeFonts.noteFontTable(charsets) }
            OfficeFonts.noteEmbedded(table.all("w:font").compactMap { font in
                font.first("w:embedRegular") != nil || font.first("w:embedBold") != nil ? font["w:name"] : nil
            })
            // The East Asian faces themselves (only those: the Latin ones
            // a file embeds are Word's own, which the shipped clones match
            // to the unit), drawn in their own glyphs.
            var faceTargets: [String: String] = [:]
            if let relRoot = part("word/_rels/fontTable.xml.rels").flatMap(XNode.parse) {
                for r in relRoot.all("Relationship") {
                    if let id = r["Id"], let target = r["Target"] { faceTargets[id] = target }
                }
            }
            var faces: [String: String] = [:]
            for font in table.all("w:font") {
                // (And, in Word — for Windows and for the Mac alike — one with
                // a Latin name whose entry names an East Asian charset, for its
                // line: zh-1cfb652b's GWZT-EN, charset 86 — see `OfficeFonts.face`.)
                guard let name = font["w:name"],
                      OfficeFonts.isEastAsianFace(name) || (Self.wordOnWindows || Self.wordOnMac) && ["86", "88", "80", "81"].contains(font.first("w:charset")?["w:val"]?.uppercased() ?? ""),
                      let embed = font.first("w:embedRegular") ?? font.first("w:embedBold"),
                      let rid = embed["r:id"], let key = embed["w:fontKey"], let target = faceTargets[rid] else { continue }
                let path = target.hasPrefix("/") ? String(target.dropFirst()) : "word/" + target
                guard let raw = part(path), let data = OfficeFonts.deobfuscate(raw, key: key),
                      let family = OfficeFonts.loadEmbedded(data) else { continue }
                faces[name] = family
                if OfficeFonts.mapsToZeroAdvance(data, 0x300C) { document.uncompressedFaces.insert(name) }
            }
            OfficeFonts.noteEmbeddedFaces(faces)
            var alts: [String: String] = [:]
            var entries: [String: OfficeFonts.FontEntry] = [:]
            var entryCharsets: [String: String] = [:]
            for font in table.all("w:font") {
                guard let name = font["w:name"] else { continue }
                // (An East Asian entry over a charset-00 one for a repeated
                // name: see the charsets above.)
                let charset = font.first("w:charset")?["w:val"] ?? ""
                // (Whichever entry is kept, the last one's family: Word for
                // Mac's, `FontEntry.lastFamily`.)
                if entries[name] != nil { entries[name]!.lastFamily = font.first("w:family")?["w:val"] ?? "auto" }
                if entries[name] != nil, charset == "00" || entryCharsets[name] != "00" { continue }
                entryCharsets[name] = charset
                let alt = font.first("w:altName")?["w:val"]
                if let alt, !alt.isEmpty { alts[name] = alt }
                let panose = font.first("w:panose1")?["w:val"] ?? ""
                let sig = font.first("w:sig")
                entries[name] = OfficeFonts.FontEntry(alt: alt, family: font.first("w:family")?["w:val"] ?? "auto",
                                                      panoseZero: !panose.isEmpty && panose.allSatisfy { $0 == "0" }, charset: charset,
                                                      usb0: sig?["w:usb0"].flatMap { UInt32($0, radix: 16) },
                                                      usb1: sig?["w:usb1"].flatMap { UInt32($0, radix: 16) })
            }
            OfficeFonts.noteAltNames(alts)
            OfficeFonts.noteFontEntries(entries)
        } else {
            OfficeFonts.noteEmbedded([])
            OfficeFonts.noteEmbeddedFaces([:])
            OfficeFonts.noteAltNames([:])
            OfficeFonts.noteFontEntries([:])
        }
        // The HTML blocks' margins, by the id a paragraph names (only a
        // block's own: drawing.docx's banner block, 0.75pt over and 3.75
        // under, inside a body block of 7.5pt all round, stands 4.5pt
        // taller in Word's print, the body's margins nowhere).
        if let web = part("word/webSettings.xml").flatMap(XNode.parse) {
            func walk(_ node: XNode) {
                for div in node.all("w:div") {
                    if let id = div["w:id"] {
                        let top = Double(div.first("w:marTop")?["w:val"] ?? "") ?? 0
                        let bottom = Double(div.first("w:marBottom")?["w:val"] ?? "") ?? 0
                        if top > 0 || bottom > 0 { document.divMargins[id] = DivMargins(top: top / 20, bottom: bottom / 20) }
                    }
                    if let children = div.first("w:divsChild") { walk(children) }
                }
            }
            if let divs = web.first("w:divs") { walk(divs) }
        }
        if let settings = part("word/settings.xml").flatMap(XNode.parse) {
            document.themeFontLangXML = settings.first("w:themeFontLang").map { PptxXML.serialize($0) }
            document.characterSpacingControl = settings.first("w:characterSpacingControl")?["w:val"]
            document.kernsPunctuation = settings.first("w:noPunctuationKerning").map { _isOff($0) } ?? true
            document.htmlAutoSpacing = !(settings.first("w:compat")?.first("w:doNotUseHTMLParagraphAutoSpacing").map { !_isOff($0) } ?? false)
            document.usesEastAsianLayout = settings.first("w:compat")?.first("w:useFELayout").map { !_isOff($0) }
                ?? (part("word/styles.xml") == nil)
            document.indentNotNumberingTabStop = settings.first("w:compat")?.first("w:doNotUseIndentAsNumberingTabStop").map { !_isOff($0) } ?? false
            document.balancesSpaceWidth = settings.first("w:compat")?.first("w:balanceSingleByteDoubleByteWidth").map { !_isOff($0) } ?? false
            document.underlinesTrailingSpaces = settings.first("w:compat")?.first("w:ulTrailSpace").map { !_isOff($0) } ?? false
            document.spacesForUnderline = settings.first("w:compat")?.first("w:spaceForUL").map { !_isOff($0) } ?? false
            document.adjustsLineHeightInTable = settings.first("w:compat")?.first("w:adjustLineHeightInTable").map { !_isOff($0) } ?? false
            document.hangsHalf = settings.first("w:compat")?.first("w:useAltKinsokuLineBreakRules").map { !_isOff($0) } ?? false
            document.breakRulesOnlyForEastAsian = settings.first("w:compat")?.first("w:doNotUseEastAsianBreakRules").map { !_isOff($0) } ?? false
            document.compatibilityMode = settings.first("w:compat")?.all("w:compatSetting")
                .first { $0["w:name"] == "compatibilityMode" }.flatMap { Int($0["w:val"] ?? "") }
            // (A file that names no compatibility mode — with a w:compat block
            // or without, as Word for Windows' labs `compat` a, b: fdo63164-1
            // with none and with an empty one — hangs a line's last full stop
            // or comma past the margin, and is set by the East Asian rules
            // where its settings do not say.)
            if document.compatibilityMode == nil, settings.first("w:compat")?.first("w:useFELayout") == nil {
                document.hangsLatinStops = part("word/styles.xml") != nil
                document.usesEastAsianLayout = document.usesEastAsianLayout || document.hangsLatinStops
            }
            document.flipsMirrorIndents = !(settings.first("w:compat")?.all("w:compatSetting")
                .contains { $0["w:name"] == "doNotFlipMirrorIndents" && ["1", "true", "on"].contains($0["w:val"] ?? "") } ?? false)
            document.addsParagraphSpacing = settings.first("w:compat")?.first("w:doNotUseHTMLParagraphAutoSpacing").map { !_isOff($0) } ?? false
            let margins = ["w:mirrorMargins", "w:gutterAtTop"].compactMap { settings.first($0) }.map { PptxXML.serialize($0) }.joined()
            document.marginSettingsXML = margins.isEmpty ? nil : margins
            for name in _keptSettingNames.flatMap({ $0 }) {
                if let n = settings.first(name) { document.keptSettings[name] = PptxXML.serialize(n) }
            }
        }
        if let styles = part("word/styles.xml").flatMap(XNode.parse) {
            // The defaults' language, or Normal's over it — each of its
            // three by itself: zh-63a571aa's Normal says only
            // `w:bidi="ar-SA"`, its East Asian text the defaults' zh-TW,
            // whose centred "。" keeps its em before "」" in Word's print;
            // ours took no East Asian language and closed it up.
            // (A Latin face named for East Asian text in the defaults turns
            // Word for Windows' punctuation compression off: labs tcd/q/x
            // (windows-1, Word for Windows, zh-cd48112c's package) — its
            // rPrDefault says eastAsia "Times New Roman", and every "，",
            // "、", "“" and "”" is a whole em in its print; with 宋体 there
            // the same paragraph squeezes its marks and takes a character
            // more a line. Its languages, swapped every way, changed
            // nothing.)
            if let ea = styles.first("w:docDefaults")?.first("w:rPrDefault")?.first("w:rPr")?.first("w:rFonts")?["w:eastAsia"],
               !OfficeFonts.isEastAsianFace(ea),
               ["times new roman", "times", "arial", "calibri", "cambria", "ms serif", "verdana", "tahoma", "helvetica", "courier new", "segoe ui", "georgia"]
                .contains(ea.trimmingWhitespace().lowercased()) {
                document.eastAsianDefaultFaceIsLatin = true
            }
            let normal = styles.all("w:style").first { $0["w:type"] == "paragraph" && ($0["w:default"] == "1" || $0["w:styleId"] == "Normal") }
            let own = normal?.first("w:rPr")?.first("w:lang")
            let defaults = styles.first("w:docDefaults")?.first("w:rPrDefault")?.first("w:rPr")?.first("w:lang")
            // (`RichDocument.joinsHanAfterSpace`.)
            let defaultEastAsia = styles.first("w:docDefaults")?.first("w:rPrDefault")?.first("w:rPr")?.first("w:rFonts")?["w:eastAsiaTheme"]
            document.joinsHanAfterSpace = document.compatibilityMode == nil
                && ["minorHAnsi", "majorHAnsi", "minorAscii", "majorAscii"].contains(defaultEastAsia ?? "")
            if let own, let defaults {
                document.defaultLangXML = PptxXML.serialize(XNode(name: own.name, attrs: defaults.attrs.merging(own.attrs) { _, mine in mine }))
            } else if let lang = own ?? defaults {
                document.defaultLangXML = PptxXML.serialize(lang)
            }
        }
        // Header/footer: the section's default references, text with the
        // PAGE/NUMPAGES fields kept as placeholders.
        if let sect = body.first("w:sectPr") {
            for ref in sect.all("w:headerReference") where ref["w:type"] == "default" || ref["w:type"] == "odd" || ref["w:type"] == nil {
                if let rid = ref["r:id"], let target = rels[rid], let data = media(target),
                   let node = XNode.parse(data) {
                    document.header = _fieldText(node)
                }
            }
            for ref in sect.all("w:footerReference") where ref["w:type"] == "default" || ref["w:type"] == "odd" || ref["w:type"] == nil {
                if let rid = ref["r:id"], let target = rels[rid], let data = media(target),
                   let node = XNode.parse(data) {
                    document.footer = _fieldText(node)
                }
            }
        }
        return DocxDocument(document: document, pageSetup: pageSetup)
    }

    /// Plain-text inline controls showing one named placeholder share its
    /// first cached value. Word does this even across paragraphs (55966
    /// and the placeholder labs); a filled control does not participate.
    /// Block controls have a separate refresh behavior, so keep their
    /// cached paragraphs. The glossary's default text is not what Word
    /// displays when the inline controls already carry a cached value.
    private static func _reuseInlinePlaceholders(_ body: XNode) {
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
    /// The circled number an `eq \o\ac(○,N)` field draws (N from 1 to
    /// 20), or nil for any other field.
    static func _ringedNumber(_ instr: String) -> String? {
        let compact = instr.filter { !$0.isWhitespace }
        guard compact.lowercased().hasPrefix("eq\\o\\ac("), compact.hasSuffix(")") else { return nil }
        let inner = compact.dropFirst("eq\\o\\ac(".count).dropLast()
        let parts = inner.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 2, ["○", "◯"].contains(String(parts[0])), let n = Int(parts[1]), (1 ... 20).contains(n),
              let u = Unicode.Scalar(0x2460 + n - 1) else { return nil }
        return String(Character(u))
    }

    static func _isPageField(_ instr: String) -> Bool {
        let word = instr.trimmingWhitespace(newlines: true).uppercased().split(separator: " ").first.map(String.init) ?? ""
        return word == "PAGE" || word == "NUMPAGES" || word == "SECTIONPAGES"
    }

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
    /// East Asian paragraph markup carried in `RichParagraphStyle.eastAsian`
    /// (schema order): the switches, and the character- and line-unit
    /// measures of `w:ind` and `w:spacing`.
    /// Settings kept as written (`RichDocument.keptSettings`), in four
    /// groups by where the schema puts them.
    /// `OFFICE_WORD_FONTS=windows`: laid out as Word for Windows does where
    /// it differs from Word for Mac (the background's header marks).
    static let wordOnWindows = ProcessInfo.processInfo.environment["OFFICE_WORD_FONTS"] == "windows"
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
                shadowDrop = max(0, y)
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
        guard let shape = group.all("v:shape").first(where: { $0.first("v:textbox") != nil }) ?? group.all("v:rect").first(where: { $0.first("v:textbox") != nil }),
              let textbox = shape.first("v:textbox") else { return nil }
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
    /// `v:shapetype`'s `textboxrect` (among `types`, by id) where that
    /// is plain numbers, else VML's own for the type (`o:spt`) — nil for
    /// a rectangle or a type not known here. The rounded ones inset by
    /// 0.2929 of their corner (`adj`, 2700 of 21600 for the alternate
    /// process, 5400 for the round rectangle).
    static func _vmlTextRect(_ node: XNode, types: [XNode]) -> Rect? {
        guard let shape = node.name == "v:shape" ? node : node.descendant("v:shape") else { return nil }
        let typeId = shape["type"].map { $0.hasPrefix("#") ? String($0.dropFirst()) : $0 }
        if let id = typeId, let type = types.first(where: { $0["id"] == id }),
           let raw = type.first("v:path")?["textboxrect"]?.split(separator: ";").first {
            let v = raw.split(separator: ",").compactMap { Double($0.trimmingWhitespace()) }
            let cs = (type["coordsize"] ?? "21600,21600").split(separator: ",").compactMap { Double($0.trimmingWhitespace()) }
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
    static func _vmlTextPlaces(_ group: XNode, types: [XNode] = []) -> [(content: XNode, place: Rect, atFoot: Bool)] {
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
        var out: [(content: XNode, place: Rect, atFoot: Bool)] = []
        // A group's children in its own coordinates → points in the outermost.
        func walk(_ group: XNode, _ map: @escaping (Rect) -> Rect) {
            let origin = pair(group["coordorigin"], (0, 0)), size = pair(group["coordsize"], (1000, 1000))
            guard size.0 > 0, size.1 > 0 else { return }
            for child in group.children {
                let sh = style(child)
                guard let x = sh["left"].flatMap({ Double($0) }), let y = sh["top"].flatMap({ Double($0) }),
                      let w = sh["width"].flatMap({ Double($0) }), let h = sh["height"].flatMap({ Double($0) }) else { continue }
                var r = map(Rect.fromLTWH(x - origin.0, y - origin.1, w, h))
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
                                sh["v-text-anchor"]?.hasPrefix("bottom") == true))
                }
            }
        }
        let size = pair(group["coordsize"], (1000, 1000))
        guard size.0 > 0, size.1 > 0 else { return [] }
        walk(group) { r in Rect.fromLTWH(r.left * gw / size.0, r.top * gh / size.1, r.width * gw / size.0, r.height * gh / size.1) }
        return out
    }

    /// Where an anchored drawing floats (`wp:anchor`: its two positions
    /// and its wrapping), or nil for one in the line. A VML shape floats
    /// when its style positions it absolutely — the outermost one: a
    /// drawing canvas in the line (`v:group`, WordWithAttachments'
    /// "Словарь" box) holds shapes placed absolutely in it, and floated
    /// by its text box it took no room.
    static func _float(_ node: XNode) -> ImageFloat? {
        if let anchor = node.name == "wp:anchor" ? node : node.descendant("wp:anchor") {
            var f = ImageFloat()
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
                if let v = Double(h.first("wp:posOffset")?.text ?? "") { f.x = v / 12700 }
                f.horizontalAlign = h.first("wp:align")?.text
            }
            if let v = position("wp:positionV") {
                f.verticalFrom = v["relativeFrom"] ?? "paragraph"
                if let o = Double(v.first("wp:posOffset")?.text ?? "") { f.y = o / 12700 }
                f.verticalAlign = v.first("wp:align")?.text
            }
            f.takesRoom = anchor.first("wp:wrapTopAndBottom") != nil
            f.wraps = ["wp:wrapSquare", "wp:wrapTight", "wp:wrapThrough"].contains { anchor.first($0) != nil }
            if let w = ["wp:wrapSquare", "wp:wrapTight", "wp:wrapThrough"].lazy.compactMap({ anchor.first($0) }).first,
               let side = w["wrapText"], side == "left" || side == "right" { f.wrapSide = side }
            Self._bandPage(&f)
            if let b = Double(anchor.first("wp:effectExtent")?["b"] ?? "") { f.effectBottom = b / 12700 }
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
            return f
        }
        // (Not for a drawing the file puts in the line, `wp:inline`, whose
        // VML fallback says "position:absolute" all the same: lo
        // tdf147485's logo, drawn one height above its line.)
        if node.descendant("wp:inline") != nil { return nil }
        if let shape = _vmlTop(node), let st = shape["style"], st.containsSubstring("position:absolute") {
            var f = ImageFloat()
            for pair in st.split(separator: ";") {
                let kv = pair.split(separator: ":", maxSplits: 1)
                guard kv.count == 2 else { continue }
                let key = kv[0].trimmingWhitespace(), value = String(kv[1]).trimmingWhitespace()
                switch key {
                case "margin-left": if let v = _length(value) { f.x = v }
                case "margin-top": if let v = _length(value) { f.y = v }
                case "mso-position-horizontal-relative": f.horizontalFrom = value == "text" ? "column" : value
                case "mso-position-vertical-relative": f.verticalFrom = value == "text" ? "paragraph" : value
                case "mso-position-horizontal": if value != "absolute" { f.horizontalAlign = value }
                case "mso-position-vertical": if value != "absolute" { f.verticalAlign = value }
                case "mso-wrap-distance-top": if let v = _length(value) { f.distanceTop = v }
                case "mso-wrap-distance-bottom": if let v = _length(value) { f.distanceBottom = v }
                default: break
                }
            }
            f.takesRoom = shape.first("w10:wrap")?["type"] == "topAndBottom"
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
        func paragraph(_ ap: XNode) -> XNode {
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
            if !spacing.isEmpty { pPr.append(el("w:spacing", spacing)) }
            let jc = ["ctr": "center", "r": "right", "l": "left", "just": "both", "dist": "distribute"][props?["algn"] ?? "l"] ?? "left"
            pPr.append(el("w:jc", ["w:val": jc]))
            func runProps(_ rPr: XNode?) -> XNode {
                var out: [XNode] = []
                var fonts: [String: String] = [:]
                if let f = rPr?.first("a:latin")?["typeface"], !f.hasPrefix("+") { fonts["w:ascii"] = f; fonts["w:hAnsi"] = f }
                if let f = rPr?.first("a:ea")?["typeface"], !f.hasPrefix("+") { fonts["w:eastAsia"] = f }
                if let f = rPr?.first("a:cs")?["typeface"], !f.hasPrefix("+") { fonts["w:cs"] = f }
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
                                              el("wps:txbx", [:], [el("w:txbxContent", [:], body.all("a:p").map(paragraph))]), bodyPr]))
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

    /// Half a shape's outline width (points), which Word adds to its
    /// text's insets whether or not the outline is drawn (see the text
    /// box reader); none where the outline states no width.
    static func _halfOutline(_ spPr: XNode?) -> Double {
        Double(spPr?.first("a:ln")?["w"] ?? "").map { $0 / 12700 / 2 } ?? 0
    }

    /// `w:spacing`/`w:ind` markup with the kept line- and character-unit
    /// attributes added (an element is made for them when there is none).
    private static func _withEastAsian(_ xml: String, _ element: String, _ attrs: [String], _ style: RichParagraphStyle) -> String {
        let extra = attrs.compactMap { a in style.eastAsian[a].map { " \(a)=\"\(_esc($0))\"" } }.joined()
        if extra.isEmpty { return xml }
        if xml.isEmpty { return "<\(element)\(extra)/>" }
        return xml.replacingAll("<\(element)", with: "<\(element)\(extra)")
    }

    /// `w:tabs` for a paragraph (or a style) whose stops are `stops`, over
    /// the style under it: its own stops, and a "clear" for each of the
    /// style's it does not have.
    private static func _tabsXML(_ stops: [TabStop], under: [TabStop]) -> String {
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

    private static func _eastAsianSwitchesXML(_ style: RichParagraphStyle) -> String {
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
        var color: Color? = nil
        if let hex = e["w:color"], hex.lowercased() != "auto", hex.count == 6, let v = Int(hex, radix: 16) {
            color = Color(argb: 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF)
        }
        var l = BorderLine(width: max(0.25, sz / 8), color: color, space: Double(e["w:space"] ?? "0") ?? 0)
        if let v = e["w:val"], v != "single" { l.style = v }
        return l
    }

    private static func _paragraphProps(_ pPr: XNode, into style: inout RichParagraphStyle, direct: Bool = false) {
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
        if let shd = pPr.first("w:shd"), let hex = shd["w:fill"], hex.lowercased() != "auto", hex.count == 6, let v = Int(hex, radix: 16) {
            style.fill = Color(argb: 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF)
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
                f.verticalAlign = node["w:yAlign"]
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
                style.eastAsian["w:indentStored"] = together && direct ? "1" : nil
            }
            for a in attrs { if let v = n[a], Int(v) != nil { style.eastAsian[a] = v } }
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
            let b = ParagraphBorders(top: line("w:top"), bottom: line("w:bottom"), left: line("w:left"), right: line("w:right"))
            style.borders = b.isEmpty ? nil : b
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
        switch sect.first("w:type")?["w:val"] {
        case "oddPage": setup.sectionStartParity = .odd
        case "evenPage": setup.sectionStartParity = .even
        default: break
        }
        setup.orientStated = sz["w:orient"] != nil
        if let t = sect.first("w:titlePg"), !_isOff(t) { setup.titlePage = true }
        if let num = sect.first("w:pgNumType") {
            setup.pageNumberStart = Int(num["w:start"] ?? "")
            setup.pageNumberFormat = num["w:fmt"]
        }
        if let mar = sect.first("w:pgMar") {
            setup.marginTop = Double(mar["w:top"] ?? "1440").map { abs($0) / 20 } ?? 72
            setup.marginBottom = Double(mar["w:bottom"] ?? "1440").map { abs($0) / 20 } ?? 72
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
        if let cols = sect.first("w:cols") {
            if let n = Int(cols["w:num"] ?? ""), n > 1 { setup.columns = n }
            // (Unequal columns state their gaps on each w:col: zh-25c4de17's
            // two say 425 there and nothing on w:cols, and Word sets them
            // 21.25pt apart — Word's 36pt default made each 7.4pt narrower
            // and its questions wrap a line early.)
            if let space = Double(cols["w:space"] ?? cols.first("w:col")?["w:space"] ?? "") { setup.columnGap = space / 20 }
        }
        if let grid = sect.first("w:docGrid") {
            if let type = grid["w:type"], type == "lines" || type == "linesAndChars", let pitch = Double(grid["w:linePitch"] ?? ""), pitch > 0 {
                setup.lineGridPitch = pitch / 20
            }
            if grid["w:type"] == "linesAndChars" {
                let space = Double(grid["w:charSpace"] ?? "") ?? 0
                setup.characterGridSpace = space != 0 ? space / 4096 : 1e-6
            }
        }
        return setup
    }

    private struct _Built {
        var paragraph: RichParagraph
        var pageBreakAfter: Bool
        /// That break is a `w:br` character (not a section's), in a run
        /// with these properties.
        var breakCharacter = false
        var breakRPr: String? = nil
        var breakColumn = false   // ... and a column break
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
        fileprivate var seenFootnotes = 0, seenEndnotes = 0
        /// The number each footnote's mark was given in the body, by id;
        /// and, while a note's own text is read, its number for its
        /// `w:footnoteRef`.
        var footnoteNumbers: [Int: Int] = [:], endnoteNumbers: [Int: Int] = [:]
        var currentNote: Int? = nil
        /// An endnote's own mark, in its numbering's form ("i").
        var currentNoteLabel: String? = nil
        var endnoteFormat = "lowerRoman", footnoteFormat = "decimal"
        func label(_ n: Int, footnote: Bool) -> String {
            switch footnote ? footnoteFormat : endnoteFormat {
            case "lowerRoman": return ListNumberFormat.lowerRoman.string(n)
            case "upperRoman": return ListNumberFormat.upperRoman.string(n)
            case "lowerLetter": return ListNumberFormat.lowerLetter.string(n)
            case "upperLetter": return ListNumberFormat.upperLetter.string(n)
            default: return String(n)
            }
        }
        var rels: [String: KeptRel]
        /// Reading a header or footer part: its page fields stay fields
        /// (the layout fills them for each page).
        var inHeaderFooter = false
        /// Reading a text box's paragraphs (a box inside a box is not read).
        var inTextBox = false
        /// The cell's run base takes its size from the table's style
        /// (`tableSizes`): a paragraph whose own style states one keeps that.
        var cellSizeFromTable = false
        /// A text box whose text holds a table, by its attachment's id:
        /// its `w:txbxContent`, for the body's reader to read again with
        /// its tables (this reader sets paragraphs only).
        var boxTables: [String: XNode] = [:]
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
        /// The fields open at this point of the walk, innermost last (a
        /// contents field spans paragraphs and holds a page reference per
        /// line): each one's instruction, whether its result has begun,
        /// and its number in the document (`CharStyle.fieldResult`).
        var fields: [(instr: String, result: Bool, id: Int)] = []
        /// The look of each field's code (its first instruction run), by id.
        var fieldCodeStyle: [Int: CharStyle] = [:]
        var fieldCount = 0
        /// Whether the code of the field being read was reformatted under
        /// change tracking: its result's first run says so
        /// (`CharStyle.fieldCodeChanged`).
        var fieldCodeChanged = false
        /// Every comment id whose range has been opened (a reference run
        /// for one of these ends a range; any other is a point comment).
        var seenComments = Set<String>()
        /// Character styles (w:rStyle on a run), each as its chain of run
        /// properties from the root style down, applied under the run's
        /// own. drawing.docx's dates wear a Tahoma 7.5pt shaded style and
        /// its headings a bold 14pt one; both came back as plain text.
        var charStyleChains: [String: [XNode]] = [:]
        /// `w:splitPgBreakAndParaMark` before 2013's layout: the mark of a
        /// paragraph that ends in a page break goes to the next page.
        var marksFollowBreaks = false
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
        var width: Double? = nil
        var style: String? = nil   // w:val when drawn and not "single"
    }

    /// A table style's conditional formatting, the parts the editor shows.
    struct _Cond {
        var headerFill: Color? = nil
        var headerChar: CharStyle? = nil
        var firstColChar: CharStyle? = nil
        var band1: Color? = nil
        var band2: Color? = nil
        /// The header row's cell borders (`firstRow`'s `w:tcBorders`).
        var headerBorders: XNode? = nil
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
    private static func _borders(_ pr: XNode?, _ tag: String) -> _Borders? {
        guard let b = pr?.first(tag), !b.children.isEmpty else { return nil }
        let drawn = b.children.filter { !["nil", "none"].contains($0["w:val"] ?? "nil") }
        guard let first = drawn.first else { return _Borders(on: false, color: nil) }
        var color: Color? = nil
        if let hex = drawn.first(where: { ($0["w:color"] ?? "auto").lowercased() != "auto" })?["w:color"] ?? first["w:color"],
           hex.lowercased() != "auto", hex.count == 6, let v = Int(hex, radix: 16) {
            color = Color(argb: 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF)
        }
        let width = Double(first["w:sz"] ?? "").map { max(0.25, $0 / 8) }
        let style = first["w:val"].flatMap { $0 == "single" ? nil : $0 }
        return _Borders(on: true, color: color, width: width, style: style)
    }

    /// The sides a `w:tblBorders`/`w:tcBorders` names: false for nil or
    /// none, true for a drawn line, nil for a side it does not mention.
    private static func _edges(_ pr: XNode?, _ tag: String) -> BorderEdges? {
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
    /// and endnotes, each with its rels and whatever those reach (metric
    /// picture in a note) — kept verbatim so a save keeps the notes the
    /// body still references.
    private static func _keptParts(_ entries: [ZipEntry], _ part: (String) -> Data?) -> [String: Data] {
        var kept: [String: Data] = [:]
        // Only a part that parses is kept: a damaged one would make the
        // saved file as unopenable as the original.
        for e in entries where e.name.hasPrefix("word/theme/") && e.name.hasSuffix(".xml") && _wellFormed(e.data) {
            kept[e.name] = e.data
        }
        // The web settings: the margins of the HTML blocks paragraphs name
        // by w:divId (drawing.docx's last banner sits 4.5pt lower for one).
        // Kept only for a document that names one: the part says nothing
        // else a page shows.
        if let web = part("word/webSettings.xml"), _wellFormed(web),
           part("word/document.xml").map({ String(decoding: $0, as: UTF8.self).containsSubstring("<w:divId") }) == true {
            kept["word/webSettings.xml"] = web
        }
        // (And the font table: what Word substitutes for a face the machine
        // lacks is chosen by the family, pitch and alternate name stated
        // there, and a Chinese document names faces few machines have.)
        for name in ["footnotes", "endnotes", "fontTable"] {
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
        var isEmpty: Bool { major == nil && minor == nil && majorEastAsia == nil && minorEastAsia == nil }
        /// The face a reference (`minorHAnsi`, `majorEastAsia`, …) names.
        func face(_ ref: String) -> String? {
            let major = ref.hasPrefix("major")
            if ref.hasSuffix("EastAsia") { return major ? majorEastAsia : minorEastAsia }
            if ref.hasSuffix("Bidi") { return nil }
            return major ? self.major : minor
        }
    }

    private static func _themeFonts(_ entries: [ZipEntry]) -> ThemeFonts {
        guard let e = entries.first(where: { $0.name.hasPrefix("word/theme/") && $0.name.hasSuffix(".xml") }),
              let root = XNode.parse(e.data), let scheme = root.descendant("a:fontScheme") else { return ThemeFonts() }
        let lang = entries.first(where: { $0.name == "word/settings.xml" }).flatMap { XNode.parse($0.data) }?
            .first("w:themeFontLang")?["w:eastAsia"]?.lowercased()
        let script: String? = switch lang {
        case "zh-cn", "zh-sg": "Hans"
        case "zh-tw", "zh-hk", "zh-mo": "Hant"
        case "ja-jp": "Jpan"
        case "ko-kr": "Hang"
        default: nil
        }
        func latin(_ name: String) -> String? {
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
        return ThemeFonts(major: latin("a:majorFont"), minor: latin("a:minorFont"),
                          majorEastAsia: eastAsian("a:majorFont"), minorEastAsia: eastAsian("a:minorFont"))
    }

    /// Rewrites every `w:rFonts` under `node` whose ascii/hAnsi face is a
    /// theme reference into the face itself.
    /// A style's `w:styleId` and `w:type` are both optional, and Word fills
    /// them in: no type is a paragraph style, and a style with no id is
    /// looked up by its name. 60329's `EmptyCellLayoutStyle` (1pt, no id, no
    /// type) is what every empty cell's paragraph wears; skipping it set
    /// those cells in Normal's 10pt + 10pt after, grew every table, and
    /// cost the copy a fourth page.
    private static func _normaliseStyleIds(_ styles: XNode) {
        for style in styles.all("w:style") {
            if style.attrs["w:type"] == nil { style.attrs["w:type"] = "paragraph" }
            if style.attrs["w:styleId"] == nil, let name = style.first("w:name")?["w:val"] { style.attrs["w:styleId"] = name }
        }
    }

    private static func _resolveThemeFonts(_ root: XNode, _ theme: ThemeFonts) {
        guard !theme.isEmpty else { return }
        var stack = [root]   // iterative: a fuzzer's tree is deeper than the call stack
        while let node = stack.popLast() {
            if node.name == "w:rFonts" {
                for (ref, attr) in [("w:asciiTheme", "w:ascii"), ("w:hAnsiTheme", "w:hAnsi"), ("w:eastAsiaTheme", "w:eastAsia")] {
                    guard let t = node.attrs[ref] else { continue }
                    if let face = theme.face(t) { node.attrs[attr] = face }
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
                                    _ styleIds: [String: String], _ styleNums: [String: (numId: String, ilvl: Int, left: Double?, first: Double?)],
                                    _ sheet: RichStyleSheet,
                                    _ nums: [String: [Int: ListKind]],
                                    _ rels: [String: String], _ media: (String) -> Data?,
                                    _ indent: Double, _ notes: _Shared, _ cellChar: CharStyle = CharStyle(),
                                    _ cellResolve: ((String) -> RichParagraphStyle?)? = nil) -> [_Built] {
        var style = base
        var sectionBreakAfter = false
        // (The table style's size stands under the paragraph's own style:
        // zh-e2dc9dce's flow table, styled at 10pt, sets its "01 標題壹"
        // headings at that style's 14pt in Word's print.)
        var cellChar = cellChar
        if notes.cellSizeFromTable, let id = p.first("w:pPr")?.first("w:pStyle")?["w:val"], let ours = styleIds[id],
           sheet[ours]?.char.fontSize != nil {
            cellChar.fontSize = nil
        }
        // The paragraph mark's look (w:pPr/w:rPr): an empty paragraph is
        // as tall as its mark's font — a 28pt mark is a 28pt spacer. Word
        // honours it in every spelling (probed 2026-10-09 with 30 marks of
        // 28pt: END lands on page two; the 2026-10-08 probe that said
        // otherwise was wrong). bib-chernigovka's cover is 7 such spacers
        // at 16pt, and without them its first table ran onto page one.
        var markStyle: CharStyle? = nil
        var styleBreak = false
        if let pPr = p.first("w:pPr") {
            // The named style's props first, then the paragraph's own.
            if let id = pPr.first("w:pStyle")?["w:val"], let ours = styleIds[id] {
                sheet.apply(ours, to: &style)
                // (`apply` keeps the paragraph's break, as an edit that
                // restyles one must; read from the file, the style's is
                // the paragraph's too — see `_paragraphProps`.)
                if sheet[ours]?.paragraph.pageBreakBefore == true, !style.pageBreakBefore { style.pageBreakBefore = true; styleBreak = true }
                if let inCell = cellResolve?(id) {
                    let named = style.named, heading = style.heading
                    style = inCell
                    style.named = named
                    style.heading = heading
                }
            }
            // (A paragraph that says it is in no list — `w:numId` 0 — takes
            // no left, hanging or first-line indent from its style: lab
            // `lc2` (Word for Windows, zh-15428325's package), its style
            // "table of figures" at leftChars 200 hangingChars 200, sets the
            // paragraph's lines at the margin and its first two characters
            // in, where the same paragraph without the `w:numPr` keeps the
            // style's two; the corpus print has its lines so.)
            if pPr.first("w:numPr")?.first("w:numId")?["w:val"] == "0" {
                style.indentLeft = 0
                style.firstLineIndent = 0
                for key in ["w:leftChars", "w:startChars", "w:hangingChars", "w:firstLineChars"] { style.eastAsian[key] = nil }
            }
            _paragraphProps(pPr, into: &style, direct: true)
            if let g = pPr.first("w:snapToGrid") { style.ownGridOff = _isOff(g) }
            style.indentLeft += indent
            // (A moved paragraph's mark too: `w:moveFrom` is a deleted mark and
            // `w:moveTo` an inserted one, a move's two ends. LibreOffice's
            // tdf104797: the moved-from paragraph is gone from Word's print with
            // markup and its balloon ends "…duplicated?¶"; ours kept it as an
            // empty line and the body stood 17pt low.)
            if let rPr = pPr.first("w:rPr"),
               let rev = rPr.first("w:del") ?? rPr.first("w:moveFrom") ?? rPr.first("w:ins") ?? rPr.first("w:moveTo") {
                let to = rev.name == "w:ins" || rev.name == "w:moveTo"
                style.markRevision = RevisionMark(kind: to ? .inserted : .deleted, author: rev["w:author"] ?? "", date: rev["w:date"] ?? "",
                                                  moved: rev.name.hasPrefix("w:move"))
            }
            if let rPr = pPr.first("w:rPr") { markStyle = _charStyle(rPr, base: cellChar) }
            if markStyle?.hidden == true { style.markHidden = true }
            style.mark = markStyle
            // The paragraph's own numbering, else its style's (a numbered
            // heading style: 65099's "1.1.1 Acronyms").
            var num: (numId: String, ilvl: Int)? = nil
            var styleLeft: Double? = nil, styleFirst: Double? = nil
            if let numPr = pPr.first("w:numPr") {
                num = (numPr.first("w:numId")?["w:val"] ?? "", Int(numPr.first("w:ilvl")?["w:val"] ?? "0") ?? 0)
            } else if let id = pPr.first("w:pStyle")?["w:val"], let n = styleNums[id] {
                num = (n.numId, n.ilvl)
                styleLeft = n.left; styleFirst = n.first
            }
            if let (numId, ilvl) = num {
                if numId != "0" {
                    style.list = nums[numId]?[ilvl] ?? nums[numId]?[0] ?? .bullet
                    style.listLevel = min(8, ilvl)
                    style.listId = numId
                    // The list's own indent replaces the style's — unless
                    // the paragraph states a left of its own, which Word
                    // puts above the level's.
                    let ownLeft = style.indentLeft - indent
                    style.indentLeft = indent
                    style.listIndentLeft = styleLeft
                    style.listFirstLine = styleFirst
                    if let ind = pPr.first("w:ind"), let v = Double(ind["w:left"] ?? ind["w:start"] ?? "") {
                        style.listIndentLeft = v / 20
                    }
                    if let ind = pPr.first("w:ind") {
                        if let v = Double(ind["w:hanging"] ?? "") { style.listFirstLine = -v / 20 }
                        else if let v = Double(ind["w:firstLine"] ?? "") { style.listFirstLine = v / 20 }
                    }
                    // (Neither the paragraph nor its level giving a left,
                    // the item keeps its style's — Word takes each of the
                    // indent's attributes from where it is given: zh-ea70c30e's
                    // "(c)" items, Body Text Indent 2 at 1440 over a level
                    // of firstLine 720 alone and a paragraph of hanging 720,
                    // stand at 72pt with their labels at 36 in Word's print;
                    // ours were at the margin.)
                    if style.listIndentLeft == nil, notes.listFormats[numId]?[ilvl]?.indentLeft == nil, ownLeft != 0 {
                        style.listIndentLeft = ownLeft
                    }
                }
            }
            if pPr.first("w:pageBreakBefore") != nil, !_isOff(pPr.first("w:pageBreakBefore")!) {
                style.pageBreakBefore = true
            }
            // (Not a break before a paragraph that is only a section's end,
            // with no run in it: zh-499adba6's contents section ends in an
            // empty Heading 2, and Word's print has no page for it — the
            // next section's page is the break; ours set it on a page alone.
            // A direct w:pageBreakBefore too: zh-ae2dd08d's landscape
            // 附表三 section ends in such a paragraph, and Word goes on to
            // the portrait 附表四 with no page between; ours printed one
            // with only its footer, and every page after was one late.)
            if style.pageBreakBefore, pPr.first("w:sectPr") != nil {
                func hasRun(_ n: XNode) -> Bool { n.children.contains { $0.name == "w:r" || hasRun($0) } }
                if !p.children.contains(where: { $0.name != "w:pPr" && ($0.name == "w:r" || hasRun($0)) }) { style.pageBreakBefore = false }
            }
            // A section ending here (its sectPr sits in this paragraph's
            // properties) starts the next on a new page unless continuous;
            // the section's own headers and page size are not kept, the
            // break is — Headers.docx had come back as one page of three.
            if let sect = pPr.first("w:sectPr") {
                // Whether a page breaks here is the NEXT section's type to
                // say (noted on the node by `read`): a section's w:type is
                // how that section starts. Read off this one's own, a
                // cover section before a "continuous" body pushed the
                // body to page two (a Lin'an draft, 22% over 17 pages).
                let breaks = sect.attrs.removeValue(forKey: "x-next-breaks").map { $0 == "1" }
                    ?? ((sect.first("w:type")?["w:val"] ?? "nextPage") != "continuous")
                if breaks { sectionBreakAfter = true }
                style.sectionBreaksPage = breaks
                // The section's own page size, margins and columns, kept
                // for the file (bug65649: 15 sections, some landscape);
                // with the header and footer parts it names — the sections
                // after it that name none inherit them (a Yunnan county
                // notice whose last section states no header lost the
                // letterhead line on all 18 pages).
                // (A reference to a part the package does not hold goes.)
                sect.children.removeAll { ref in
                    guard ref.name == "w:headerReference" || ref.name == "w:footerReference" else { return false }
                    guard let rel = ref["r:id"].flatMap({ notes.rels[$0] }), !rel.external else { return true }
                    return notes.part(_resolvePath("word", rel.target)) == nil
                }
                style.sectionPage = _pageSetup(sect)
                let named = sect.children.contains { $0.name == "w:headerReference" || $0.name == "w:footerReference" }
                if named, let frag = _keptFragment(sect, notes) {
                    style.sectionXML = frag.xml
                    style.sectionRels = frag.rels
                } else {
                    sect.children.removeAll { $0.name == "w:headerReference" || $0.name == "w:footerReference" }
                    style.sectionXML = PptxXML.serialize(sect)
                }
            }
        }

        var built: [_Built] = []
        var text = ""
        var runs: [Run] = []
        var positionalTabs: [Int: TabStop.Alignment] = [:]
        var inlineImages: [String: ImageAttachment] = [:]
        var leadingBreak = false   // the paragraph opens with a page break
        var leadingColumnBreak = false   // ... and that break is a column break
        var leadingBreakRPr: String? = nil   // ... in a run with these properties
        var splitBefore = false   // the text being read is the rest of a split w:p
        func flush(pageBreakAfter: Bool) {
            var para: RichParagraph
            if inlineImages.count == 1, text == RichParagraph.inlineImageCharacter, let only = inlineImages.values.first {
                // A paragraph that is one picture and nothing else: the
                // editor's picture paragraph, with its handles.
                para = RichParagraph(image: only, style: style)
                // A paragraph of one ANCHORED picture has no text on its
                // line: its mark's font is its height, as for an empty one
                // (bib-chernigovka's title box sat in a 16pt paragraph).
                if let mark = markStyle, only.sourceXML?.containsSubstring("<wp:anchor") == true { para.runs[0].style = mark }
            } else {
                if text.isEmpty, inlineImages.isEmpty, markStyle != nil || !notes.openComments.isEmpty {
                    // An empty paragraph takes its mark's look as its one
                    // run's style (its height); one inside a comment range
                    // carries the range too, or the writer would close
                    // and reopen it.
                    var cs = markStyle ?? cellChar
                    if !notes.openComments.isEmpty { cs.comments = notes.openComments }
                    para = RichParagraph(text: "", charStyle: cs, style: style)
                } else {
                    para = RichParagraph(text: text, runs: runs.isEmpty ? nil : runs, style: style)
                }
                para.inlineImages = inlineImages
            }
            para.style.positionalTabs = positionalTabs
            para.style.continuesParagraph = splitBefore
            splitBefore = false
            para.normalize()
            para.bookmarks = notes.pendingBookmarks
            notes.pendingBookmarks = []
            built.append(_Built(paragraph: para, pageBreakAfter: pageBreakAfter))
            text = ""
            runs = []
            positionalTabs = [:]
            inlineImages = [:]
            style.pageBreakBefore = false
        }
        /// A picture or object in the line, where the text has it.
        var runPropertiesXML: String? = nil   // of the run being walked, for a picture in it
        var runRaised: Double? = nil          // its `w:position`, for a picture or object in it
        var runFrame: BorderLine? = nil   // ... and its character border, a line of one
        func addInline(_ att: ImageAttachment) {
            var att = att
            att.sourceRunPropertiesXML = runPropertiesXML
            if att.float == nil, att.sourceXML?.containsSubstring("<wp:anchor") != true { att.frame = runFrame }
            inlineImages[att.id] = att
            var cs = CharStyle()
            cs.inlineImage = att.id
            cs.raised = runRaised
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
            notes.shapeTypes += node.descendants("v:shapetype")
            // (A Word drawing canvas, `wpc:wpc`, holds its groups and shapes
            // side by side, in the canvas's own units; only the first group
            // was read. They are one group of the canvas's size: zh-f47b8a74
            // p58's flowchart printed one box of its twenty.)
            if let canvas = node.descendant("wpc:wpc"), canvas.descendant("wpg:wgp") != nil || canvas.descendant("wps:wsp") != nil,
               !canvas.children.contains(where: { $0.name == "wpg:wgp" && $0.attrs["synthetic"] != nil }),
               let extent = node.descendant("wp:extent"), let cx = extent["cx"], let cy = extent["cy"] {
                // (Its groups are nested ones in the group they make: `wpg:grpSp`.)
                let kept: [XNode] = canvas.children.filter { ["wpg:wgp", "wps:wsp"].contains($0.name) }.map { child in
                    guard child.name == "wpg:wgp" else { return child }
                    let nested = XNode(name: "wpg:grpSp", attrs: child.attrs)
                    nested.children = child.children
                    return nested
                }
                if !kept.isEmpty {
                    func el(_ name: String, _ attrs: [String: String] = [:], _ children: [XNode] = []) -> XNode {
                        let n = XNode(name: name, attrs: attrs)
                        n.children = children
                        return n
                    }
                    let frame = el("a:xfrm", [:], [el("a:off", ["x": "0", "y": "0"]), el("a:ext", ["cx": cx, "cy": cy]),
                                                   el("a:chOff", ["x": "0", "y": "0"]), el("a:chExt", ["cx": cx, "cy": cy])])
                    let group = el("wpg:wgp", ["synthetic": "1"], [el("wpg:cNvGrpSpPr"), el("wpg:grpSpPr", [:], [frame])] + kept)
                    canvas.children = canvas.children.filter { !["wpg:wgp", "wps:wsp"].contains($0.name) } + [group]
                }
            }
            var w = 300.0, h = 200.0
            var isRule = false
            if let extent = node.descendant("wp:extent"),
               let cx = Double(extent["cx"] ?? ""), let cy = Double(extent["cy"] ?? ""), cx >= 0, cy >= 0, cx > 0 || cy > 0 {
                // (One of them may be nothing: a level line is no height.)
                w = cx / 12700
                h = cy / 12700
            } else if let shape = _vmlTop(node), shape.name != "v:line", let st = shape["style"] {
                for pair in st.split(separator: ";") {
                    let kv = pair.split(separator: ":", maxSplits: 1)
                    guard kv.count == 2, let v = _length(String(kv[1])), v > 0 else { continue }
                    if kv[0].trimmingWhitespace() == "width" { w = v } else if kv[0].trimmingWhitespace() == "height" { h = v }
                }
                // (A horizontal rule — an HTML page's <hr>, `o:hr` — is a
                // line of its height across the column, its width 0 in the
                // file; read as 300 by 200, bug57031's took a 200pt box and
                // pushed its SAS tables a page on.)
                if shape["o:hr"] == "t" {
                    // (… and its line is a line of text: Word gives the
                    // paragraph its text's height whatever the rule's —
                    // lab `hr`, rules of 1.5, 2.25 and 6pt each in a line
                    // of Arial 10's 11.5 — and draws the rule across its
                    // middle. "hr", which the layout sets no taller than
                    // its text.)
                    w = 0.01
                    h = 0.01
                    isRule = true
                }
                // (A VML picture is set at whole points: zh-64044a1d's flow
                // charts, 410.5 by 396.45 and 419.85 by 417.95 in their
                // styles, are 410 by 396 and 420 by 418 in Word's print —
                // and at 396 the first fits 22 pitches of its 18pt grid
                // exactly, where 396.45 took a 23rd and set its caption and
                // page 18pt low.)
                if !isRule, shape.first("v:imagedata") != nil, node.descendant("v:textbox") == nil {
                    w = max(1, (w - 0.001).rounded())
                    h = max(1, (h - 0.001).rounded())
                }
            }
            guard let frag = _keptFragment(node, notes) else { return nil }   // a part it names is missing
            var att = ImageAttachment(data: Data(), width: w, height: h, name: isRule ? "hr" : node.name)
            // (Its effect extent, as a picture's: its line holds that too.
            // zh-547fc43c's 233.75pt chart and 1.75pt of effects take 16
            // pitches of a 15.6pt grid in Word's print, not 15.)
            if let effect = node.descendant("wp:inline")?.first("wp:effectExtent") {
                att.effectLeft = max(0, (Double(effect["l"] ?? "") ?? 0) / 12700)
                att.effectRight = max(0, (Double(effect["r"] ?? "") ?? 0) / 12700)
                att.effectTop = max(0, (Double(effect["t"] ?? "") ?? 0) / 12700)
                att.effectBottom = max(0, (Double(effect["b"] ?? "") ?? 0) / 12700)
            }
            att.sourceXML = frag.xml
            att.sourceRels = frag.rels
            // (A SmartArt diagram is read as the group of shapes Word drew
            // it as, after its markup is kept for the save: zh-77079ee8's
            // organisation chart — 22 boxes and connectors in its drawing
            // part — printed nothing at all.)
            if let ids = node.descendant("dgm:relIds"), let graphic = node.descendant("a:graphicData"),
               let dm = ids["r:dm"].flatMap({ notes.rels[$0] }), !dm.external,
               let model = notes.part(_resolvePath("word", dm.target)).flatMap(XNode.parse),
               let rid = model.descendant("dsp:dataModelExt")?["relId"], let rel = notes.rels[rid], !rel.external,
               let drawing = notes.part(_resolvePath("word", rel.target)).flatMap(XNode.parse),
               let group = Self._diagramGroup(drawing, cx: w * 12700, cy: h * 12700) {
                graphic.children = [group]
                graphic.attrs["uri"] = "http://schemas.microsoft.com/office/word/2010/wordprocessingGroup"
            }
            att.float = _float(node)
            // (WordArt — a VML textpath — in its line, under Word for
            // Windows: the line holds more than the shape's box, by its
            // outline's weight and its shadow's drop, the larger of the
            // two; `_wordArtExtra` has lab wae's numbers, measured from
            // the box. Lab wa4's, measured from ours, put WordArt's
            // effect too high by a 1pt outline and by any shadow:
            // WordWithAttachments' p1 stood 2.5pt high after its three
            // titles and took its p2 icon.)
            if Self.wordOnWindows, att.float == nil, let shape = Self._vmlTop(node), let extra = Self._wordArtExtra(shape, types: notes.shapeTypes) {
                att.effectTop += extra
            }
            // (A level line — no height — takes no room in the line whatever
            // its wrapping: zh-f47b8a74's red rules under its letterhead,
            // two lines wrapped top and bottom in an empty paragraph, are
            // drawn in Word's print over that paragraph's own 28pt line;
            // set in the line at their size they made it none, drew
            // nothing, and every line after stood 30pt high.)
            if h == 0, att.float?.takesRoom == true { att.float?.takesRoom = false }
            // A straight line or a plain box, drawn by the layout: its
            // line's width and colour (`a:ln`), and a solid fill.
            // (Not a group's: its first child's shape is not the group's —
            // see `WriterGroups`.)
            if node.descendant("wpg:wgp") == nil, let sp = node.descendant("wps:spPr"), let geom = sp.first("a:prstGeom")?["prst"],
               ["line", "straightConnector1", "rect"].contains(geom) {
                // (A theme's colour too: 60316's divider is accent2, grey in
                // Word's print, where ours fell back to black.)
                let themeTarget = notes.rels.values.first(where: { $0.type.hasSuffix("/theme") && !$0.external })?.target ?? "theme/theme1.xml"
                let colors = ColorContext(theme: PptxTheme(notes.part(_resolvePath("word", themeTarget)).flatMap { XNode.parse($0) }))
                func rgb(_ n: XNode?) -> Color? {
                    guard let fill = n?.first("a:solidFill") else { return nil }
                    if let hex = fill.first("a:srgbClr")?["val"], let v = Int64(hex, radix: 16) { return Color(0xFF00_0000 | v) }
                    return fill.first("a:schemeClr") != nil ? colors.color(in: fill) : nil
                }
                let ln = sp.first("a:ln")
                var outline = ShapeOutline(kind: geom == "rect" ? .box : .line,
                                           color: ln?.first("a:noFill") != nil ? nil : (rgb(ln) ?? (ln != nil ? Color(0xFF000000) : nil)),
                                           width: (Double(ln?["w"] ?? "") ?? 9525) / 12700)
                outline.fill = rgb(sp)
                outline.flipped = sp.first("a:xfrm")?["flipV"] == "1"
                // Its effects (F14, Word's print): a colour laid over the fill
                // and blended into it, a blur, an inner shadow.
                if geom == "rect", let effects = sp.first("a:effectLst") {
                    func effectColor(_ n: XNode?) -> Color? {
                        guard let n else { return nil }
                        if let c = n.first("a:scrgbClr") {
                            // (Linear 0-100000 per channel, to sRGB.)
                            func ch(_ k: String) -> Int64 {
                                let l = max(0, min(1, (Double(c[k] ?? "") ?? 0) / 100_000))
                                let v = l <= 0.0031308 ? 12.92 * l : 1.055 * pow(l, 1 / 2.4) - 0.055
                                return Int64((v * 255).rounded())
                            }
                            let alpha = (Double(c.first("a:alpha")?["val"] ?? "") ?? 100_000) / 100_000
                            return Color(Int64((alpha * 255).rounded()) << 24 | ch("r") << 16 | ch("g") << 8 | ch("b"))
                        }
                        return colors.color(in: n)
                    }
                    if let o = effects.first("a:fillOverlay"), let base = outline.fill, let over = effectColor(o.first("a:solidFill")) {
                        let mode = o["blend"] ?? "over"
                        func blend(_ b: Int, _ o: Int) -> Double {
                            let b = Double(b) / 255, o = Double(o) / 255
                            switch mode {
                            case "mult": return b * o
                            case "screen": return 1 - (1 - b) * (1 - o)
                            case "darken": return min(b, o)
                            case "lighten": return max(b, o)
                            default: return o
                            }
                        }
                        let a = Double(over.alpha) / 255
                        func mix(_ b: Int, _ o: Int) -> Int64 { Int64(((blend(b, o) * a + Double(b) / 255 * (1 - a)) * 255).rounded()) }
                        outline.fill = Color(Int64(base.alpha) << 24 | mix(base.red, over.red) << 16 | mix(base.green, over.green) << 8 | mix(base.blue, over.blue))
                    }
                    if let r = Double(effects.first("a:blur")?["rad"] ?? ""), r > 0 { outline.blur = r / 12700 }
                    if let sh = effects.first("a:innerShdw"), let c = effectColor(sh) {
                        let dist = (Double(sh["dist"] ?? "") ?? 0) / 12700, dir = (Double(sh["dir"] ?? "") ?? 0) / 60000 * .pi / 180
                        outline.innerShadow = (c, dist * cos(dir), dist * sin(dir), (Double(sh["blurRad"] ?? "") ?? 0) / 12700)
                    }
                }
                if outline.color != nil || outline.fill != nil { att.outline = outline }
            }
            // Warped text belongs to the shape painter, with its rotation
            // and fitted envelope. Read its styles through the same Word
            // reader, but leave the body's notes and field state alone.
            var drawingWordArt: [ObjectIdentifier: WriterGroups.DrawingWordArt] = [:]
            if !notes.inTextBox, node.descendant("wpg:wgp") != nil || att.outline == nil {
                let saved = (notes.seenFootnotes, notes.seenEndnotes, notes.openComments, notes.pendingBookmarks, notes.fields,
                             notes.seenComments, notes.fieldShown)
                notes.inTextBox = true
                defer {
                    notes.inTextBox = false
                    (notes.seenFootnotes, notes.seenEndnotes, notes.openComments, notes.pendingBookmarks, notes.fields,
                     notes.seenComments, notes.fieldShown) = saved
                }
                for shape in node.descendants("wps:wsp") {
                    guard let warp = WriterGroups.textWarp(shape), let content = shape.first("wps:txbx")?.first("w:txbxContent") else { continue }
                    notes.fields = []
                    let paragraphs = content.all("w:p").flatMap {
                        _paragraphs($0, base, styleIds, styleNums, sheet, nums, rels, media, 0, notes, CharStyle(), nil).map(\.paragraph)
                    }
                    if paragraphs.contains(where: { !$0.text.isEmpty }) {
                        let body = shape.first("wps:bodyPr")
                        func inset(_ name: String, _ fallback: Double) -> Double { Double(body?[name] ?? "").map { $0 / 12700 } ?? fallback }
                        let insets = EdgeInsets.fromLTRB(inset("lIns", 7.2), inset("tIns", 3.6), inset("rIns", 7.2), inset("bIns", 3.6))
                        drawingWordArt[ObjectIdentifier(shape)] = WriterGroups.DrawingWordArt(warp: warp, paragraphs: paragraphs, styles: sheet, insets: insets)
                    }
                }
            }
            func textBoxContent(_ n: XNode) -> XNode? {
                if drawingWordArt[ObjectIdentifier(n)] != nil { return nil }
                if n.name == "w:txbxContent" { return n }
                for child in n.children { if let content = textBoxContent(child) { return content } }
                return nil
            }
            // A text box's text, for the layout to set in it: the
            // drawing's (`wps:txbx`), or its VML twin's.
            if !notes.inTextBox, let content = textBoxContent(node) {
                notes.inTextBox = true
                // (The box's markup is kept whole and written back as it
                // was: reading its text again must leave no mark on what
                // the body's own reading counts — notes, comments,
                // bookmarks, open fields.)
                let saved = (notes.seenFootnotes, notes.seenEndnotes, notes.openComments, notes.pendingBookmarks, notes.fields,
                             notes.seenComments, notes.fieldShown)
                defer {
                    (notes.seenFootnotes, notes.seenEndnotes, notes.openComments, notes.pendingBookmarks, notes.fields,
                     notes.seenComments, notes.fieldShown) = saved
                }
                notes.fields = []
                var inside: [RichParagraph] = []
                var holdsTable = false
                func read(_ content: XNode) {
                    var stack = Array(content.children.reversed())
                    while let n = stack.popLast() {
                        if n.name == "w:p" {
                            // (A text box's paragraphs take nothing of the
                            // table its anchor stands in: zh-e2dc9dce's
                            // flow-chart boxes, anchored in cells of a table
                            // styled at 10pt, print at the defaults' 12pt —
                            // lab `ts`, Word for Mac.)
                            for b in _paragraphs(n, base, styleIds, styleNums, sheet, nums, rels, media, 0, notes, CharStyle(), nil) { inside.append(b.paragraph) }
                        } else if n.name != "w:tbl" {
                            stack.append(contentsOf: n.children.reversed())
                        } else {
                            holdsTable = true
                        }
                    }
                }
                read(content)
                // (A group of text boxes one above another, as wide as
                // the group: each box's text from its own place in it.
                // 60316's résumé sidebar is a name box over an address box
                // whose text stands at its foot; only the first was read.)
                var parts: [RichTextBox.Part] = []
                var perPart = false
                if let group = node.descendant("wpg:wgp") {
                    // (The boxes of the groups in it too, each at its place
                    // in the group: zh-ae2dd08d p21's flowchart nests its
                    // boxes two groups deep, and ours read only the first
                    // box's text, set across the whole group.)
                    let placed = Self._groupTextBoxes(group).filter { drawingWordArt[ObjectIdentifier($0.box)] == nil }
                    let boxes = placed.map(\.box)
                    let gx = group.first("wpg:grpSpPr")?.first("a:xfrm")
                    let ext = Double(gx?.first("a:ext")?["cy"] ?? "") ?? 0, chExt = Double(gx?.first("a:chExt")?["cy"] ?? "") ?? 0
                    let k = chExt > 0 && ext > 0 ? ext / chExt : 1
                    let widths = placed.map(\.place.width)
                    let lefts = placed.map(\.place.left)
                    if boxes.count > 1, boxes[0].descendant("w:txbxContent") === content,
                       Set(widths).count == 1, Set(lefts).count == 1, widths[0] > 0 {
                        // (From the group's own origin, `a:chOff`: zh-799c91cd's
                        // envelope stamp box, 850 units under "掛號" in a group
                        // whose children start at 851, stood 40pt low.)
                        let oy = Double(gx?.first("a:chOff")?["y"] ?? "") ?? 0
                        // (Each box's text under its own top inset, where the
                        // box as a whole takes the first's: the stamp box's
                        // 3.6pt under "掛號"'s none stood its text 3.8pt high.)
                        func topInset(_ b: XNode) -> Double { (Double(b.first("wps:bodyPr")?["tIns"] ?? "").map { $0 / 12700 } ?? 3.6) + Self._halfOutline(b.first("wps:spPr")) }
                        let firstInset = topInset(boxes[0])
                        for (b, place) in placed.dropFirst() {
                            let first = inside.count
                            read(b.descendant("w:txbxContent")!)
                            parts.append(RichTextBox.Part(first: first, top: (place.top - oy) * k / 12700 + topInset(b) - firstInset,
                                                          height: place.height * k / 12700,
                                                          atFoot: b.first("wps:bodyPr")?["anchor"] == "b"))
                        }
                    } else if !boxes.isEmpty, boxes.count > 1 || !drawingWordArt.isEmpty
                                || (placed[0].place.top - (Double(gx?.first("a:chOff")?["y"] ?? "") ?? 0) > 1),
                              boxes[0].descendant("w:txbxContent") === content {
                        // (A single box lower in its group is one of these too:
                        // lo tdf126426's white box at the foot of a page-size
                        // photo set its line at the group's top.)
                        // (Boxes of other widths or places: each box's text
                        // in its own column of the group, from its own top —
                        // its shape's place, the preset's text rectangle and
                        // its insets. shapes-with-text's group is an arrow
                        // with "A group of shapes" in it and a text box
                        // under it: the arrow's text stood at the group's
                        // left, 85pt from Word's, and the box's was never
                        // read.)
                        perPart = true
                        let kx = Double(gx?.first("a:chExt")?["cx"] ?? "").flatMap { c in Double(gx?.first("a:ext")?["cx"] ?? "").map { c > 0 ? $0 / c : 1 } } ?? 1
                        let ox = Double(gx?.first("a:chOff")?["x"] ?? "") ?? 0, oy = Double(gx?.first("a:chOff")?["y"] ?? "") ?? 0
                        let groupWidth = (Double(gx?.first("a:ext")?["cx"] ?? "") ?? 0) / 12700
                        for (n, (b, place)) in placed.enumerated() {
                            let x = (place.left - ox) * kx / 12700
                            let y = (place.top - oy) * k / 12700
                            let w = place.width * kx / 12700
                            let h = place.height * k / 12700
                            let body = b.first("wps:bodyPr")
                            var l = Double(body?["lIns"] ?? "").map { $0 / 12700 } ?? 7.2, t = Double(body?["tIns"] ?? "").map { $0 / 12700 } ?? 3.6
                            var r = Double(body?["rIns"] ?? "").map { $0 / 12700 } ?? 7.2, bottom = Double(body?["bIns"] ?? "").map { $0 / 12700 } ?? 3.6
                            let half = Self._halfOutline(b.first("wps:spPr"))
                            l += half; t += half; r += half; bottom += half
                            if let geom = b.first("wps:spPr")?.first("a:prstGeom"), let prst = geom["prst"], prst != "rect", w > 0, h > 0,
                               let g = PresetGeometry.geometry(prst, width: w * 12700, height: h * 12700, adjustments: PresetGeometry.adjustments(geom)),
                               let rect = g.textRect {
                                l += rect.left * w; t += rect.top * h
                                r += (1 - rect.right) * w; bottom += (1 - rect.bottom) * h
                            } else if let geom = b.first("wps:spPr")?.first("a:custGeom"), w > 0, h > 0,
                                      // (A freeform's own text rectangle, its `a:rect` over
                                      // its guides: zh-ae2dd08d's flowchart diamonds wrap
                                      // "是否通過TTQS評核" in their middle half in Word's
                                      // print, three lines where the whole box held one.)
                                      let rect = FreeformGeometry.parse(geom, width: w * 12700, height: h * 12700)?.textRect {
                                l += rect.left * w; t += rect.top * h
                                r += (1 - rect.right) * w; bottom += (1 - rect.bottom) * h
                            }
                            let first = n == 0 ? 0 : inside.count
                            if n > 0 { read(b.descendant("w:txbxContent")!) }
                            for q in first ..< inside.count {
                                inside[q].style.indentLeft += x + l
                                inside[q].style.indentRight += max(0, groupWidth - (x + w) + r)
                                inside[q].style.boxInsetRight = r
                            }
                            // (Or in its middle: zh-77079ee8's organisation chart, a
                            // SmartArt whose boxes centre "工作圈" and the
                            // one-line "工作" over "服務組" in Word's print.)
                            parts.append(RichTextBox.Part(first: first, top: y + t, height: max(0, h - t - bottom), atFoot: body?["anchor"] == "b",
                                                          inMiddle: body?["anchor"] == "ctr"))
                        }
                    }
                } else if let group = Self._vmlTop(node), group.name == "v:group",
                          case let places = Self._vmlTextPlaces(group, types: notes.shapeTypes), places.count > 1, places[0].content === content {
                    // (A VML group of text boxes alike: each box's text at its
                    // own place in the group. zh-6e6b9821 p3's flowchart is a
                    // group of eleven boxes and ten arrows; ours set the first
                    // box's text across the group and read no other.)
                    perPart = true
                    for (n, b) in places.enumerated() {
                        let first = n == 0 ? 0 : inside.count
                        if n > 0 { read(b.content) }
                        for q in first ..< inside.count {
                            inside[q].style.indentLeft += b.place.left
                            inside[q].style.indentRight += max(0, att.width - b.place.right)
                        }
                        parts.append(RichTextBox.Part(first: first, top: b.place.top, height: max(0, b.place.height), atFoot: b.atFoot))
                    }
                }
                notes.inTextBox = false
                // (Or empty, where it is fitted to its text's height: as
                // tall as its empty lines — see `RichTextBox.fitsHeight`.)
                let fitsHeight = (node.descendant("v:textbox")?["style"] ?? "").containsSubstring("mso-fit-shape-to-text:t")
                    && !(((node.name == "v:shape" ? node : node.descendant("v:shape"))?["style"] ?? "").containsSubstring("mso-wrap-style:none"))
                if inside.contains(where: { !$0.text.isEmpty }) || (holdsTable && parts.isEmpty) || (fitsHeight && !inside.isEmpty && parts.isEmpty) {
                    var box = RichTextBox(paragraphs: inside)
                    if holdsTable, parts.isEmpty { notes.boxTables[att.id] = content }
                    box.parts = parts
                    if perPart {
                        // (Each part carries its own place: the group's
                        // box has no insets of its own.)
                        box.insetLeft = 0; box.insetTop = 0; box.insetRight = 0; box.insetBottom = 0
                    } else if let body = node.descendant("wps:bodyPr") {
                        box.hasFixedFrame = body.first("a:noAutofit") != nil
                        if let anchor = body["anchor"], anchor == "ctr" || anchor == "b" { box.anchor = anchor }
                        box.fitsText = body["wrap"] == "none" && body.first("a:spAutoFit") != nil
                        box.fitsOnce = box.fitsText
                        box.fitsAsDrawing = box.fitsText
                        if let v = Double(body["lIns"] ?? "") { box.insetLeft = v / 12700 }
                        if let v = Double(body["tIns"] ?? "") { box.insetTop = v / 12700 }
                        if let v = Double(body["rIns"] ?? "") { box.insetRight = v / 12700 }
                        if let v = Double(body["bIns"] ?? "") { box.insetBottom = v / 12700 }
                        // (And half its outline's width, drawn or not: lab
                        // `c60` (Word for Windows, 60316's package) moves
                        // the text of a box with no fill to its outline
                        // 0.24pt down and right for a 0.5pt one, 0.96 for
                        // 2pt, 3.96 for 8pt, and not at all with none —
                        // 60316's "Allison" line, 0.24 under the same line
                        // set in the body.)
                        let half = Self._halfOutline(node.descendant("wps:spPr"))
                        box.insetLeft += half; box.insetTop += half; box.insetRight += half; box.insetBottom += half
                        // (Turned text: zh-b24b396a's drawing labels "20",
                        // "36" and "297" are `vert270` boxes 10.5pt wide and
                        // 21 tall, read upward in Word's print; across, "297"
                        // wrapped in the 10.5pt.)
                        // (And `eaVert`, East Asian vertical writing: down as
                        // `vert`, an ideograph upright in it. zh-c4f2be3b's
                        // landscape pages number themselves in an `eaVert`
                        // box at the page's left, "- 33 -" reading down in
                        // Word's print; ours set it across.)
                        switch body["vert"] {
                        case "vert270": box.textDirection = .up
                        case "vert": box.textDirection = .down
                        case "eaVert": box.textDirection = .down; box.uprightIdeographs = true
                        default: break
                        }
                        // (A shape that is not a rectangle sets its text in
                        // the preset's text rectangle, as Slides does: Word
                        // wraps shapes-with-text's "An ellipse with text
                        // inside" in the ellipse's inscribed box, two lines
                        // where the whole box held one.)
                        if let geom = node.descendant("a:prstGeom"), let prst = geom["prst"], prst != "rect",
                           att.width > 0, att.height > 0,
                           let g = PresetGeometry.geometry(prst, width: att.width * 12700, height: att.height * 12700,
                                                           adjustments: PresetGeometry.adjustments(geom)),
                           let r = g.textRect {
                            box.insetLeft += r.left * att.width
                            box.insetTop += r.top * att.height
                            box.insetRight += (1 - r.right) * att.width
                            box.insetBottom += (1 - r.bottom) * att.height
                        } else if node.descendant("a:prstGeom") == nil, let geom = node.descendant("a:custGeom"),
                                  att.width > 0, att.height > 0,
                                  let r = FreeformGeometry.parse(geom, width: att.width * 12700, height: att.height * 12700)?.textRect {
                            box.insetLeft += r.left * att.width
                            box.insetTop += r.top * att.height
                            box.insetRight += (1 - r.right) * att.width
                            box.insetBottom += (1 - r.bottom) * att.height
                        }
                    } else if let group = Self._vmlTop(node), group.name == "v:group", let place = Self._vmlTextPlace(group) {
                        // (A text box in a VML group: its text at the box's
                        // own place in the group, inside its insets.)
                        for q in box.paragraphs.indices {
                            box.paragraphs[q].style.indentLeft += place.left
                            box.paragraphs[q].style.indentRight += max(0, att.width - place.right)
                        }
                        box.parts = [RichTextBox.Part(first: 0, top: place.top, height: max(0, place.bottom - place.top), atFoot: false)]
                        box.insetLeft = 0; box.insetTop = 0; box.insetRight = 0; box.insetBottom = 0
                    } else if let textbox = node.descendant("v:textbox"), let inset = textbox["inset"] {
                        // (A `v:rect` as well as a `v:shape`: zh-e02b0479's footer page
                        // number is a 144pt rect, centred, wrap none and fitted to its
                        // text, which Word for Windows centres as the "1" alone; ours
                        // centred the 144pt and set the "1" at its left, 72pt off.)
                        let shapeStyle = (node.name == "v:shape" || node.name == "v:rect" ? node
                            : node.descendant("v:shape") ?? node.descendant("v:rect"))?["style"] ?? ""
                        box.fitsText = shapeStyle.containsSubstring("mso-wrap-style:none")
                            && (textbox["style"] ?? "").containsSubstring("mso-fit-shape-to-text:t")
                        box.fitsOnce = box.fitsText   // (lab `vf`: sized once, as DrawingML's)
                        let parts = inset.split(separator: ",", omittingEmptySubsequences: false).map { _length(String($0).trimmingWhitespace()) }
                        if parts.count > 0, let v = parts[0] { box.insetLeft = v }
                        if parts.count > 1, let v = parts[1] { box.insetTop = v }
                        if parts.count > 2, let v = parts[2] { box.insetRight = v }
                        if parts.count > 3, let v = parts[3] { box.insetBottom = v }
                    }
                    // (Turned text in VML: the textbox's `layout-flow:vertical` reads
                    // down, as DrawingML's `vert`, and with `mso-layout-flow-alt:
                    // bottom-to-top` upward, as `vert270`; `vertical-ideographic`
                    // is `eaVert`. LibreOffice's btlr-frame-vml reads "Vertical
                    // Text" upward in Word's print; ours set it across, two lines.)
                    if !perPart, node.descendant("wps:bodyPr") == nil, let flow = node.descendant("v:textbox")?["style"] {
                        if flow.containsSubstring("layout-flow:vertical-ideographic") { box.textDirection = .down; box.uprightIdeographs = true }
                        else if flow.containsSubstring("layout-flow:vertical") {
                            box.textDirection = flow.containsSubstring("mso-layout-flow-alt:bottom-to-top") ? .up : .down
                        }
                    }
                    // (A lone VML shape that is not a rectangle sets its text
                    // in its type's text rectangle, as one in a group does —
                    // the file's `v:shapetype`, else VML's own: zh-60c80728
                    // p35's flowchart is 22 lone "alternate process" boxes
                    // (o:spt 176, inset 0, no shapetype in the file), and
                    // Word's print sets "由港区专" a line in the 54.25pt one at
                    // 10.5pt, where the whole width took "由港区专项".)
                    if !perPart, node.descendant("wps:bodyPr") == nil, Self._vmlTop(node)?.name != "v:group",
                       att.width > 0, att.height > 0, let r = Self._vmlTextRect(node, types: notes.shapeTypes) {
                        box.insetLeft += r.left * att.width
                        box.insetTop += r.top * att.height
                        box.insetRight += (1 - r.right) * att.width
                        box.insetBottom += (1 - r.bottom) * att.height
                    }
                    // (A box fitted to its text's height: zh-a78d52e7's
                    // second paragraph holds a 78.75pt one round an empty
                    // paragraph, and Word's print gives the line a text
                    // line's height.)
                    if !box.fitsText, fitsHeight { box.fitsHeight = true }
                    att.textBox = box
                }
            }
            // An embedded object's picture, a WMF or EMF its VML names
            // (`WriterMetafiles`): the icon and caption of an attached
            // file, or the first page of a document.
            if att.textBox == nil, let rid = node.descendant("v:imagedata")?["r:id"], let rel = notes.rels[rid], !rel.external,
               let data = notes.part(_resolvePath("word", rel.target)) {
                // (A VML picture of pixels — `w:pict`'s `v:imagedata`, a
                // PNG or JPEG — is that picture: zh-64044a1d's nine charts
                // and photos printed as nothing.)
                if !WriterMetafiles.register(data, for: att.id), !Metafile.isMetafile(data), Self._isRasterImage(data) {
                    att.data = data
                    att.name = rel.target.lastPathComponent
                }
            }
            // A group's lines and boxes, each in its place (`WriterGroups`);
            // and a shape alone that the outline above does not draw — an
            // ellipse, a triangle, a box filled from the theme
            // (shapes-with-text's, whose white text stood on nothing).
            // (And a lone line with an arrow at an end, which the outline
            // draws without: zh-2e7ef069's flowchart connectors, each a
            // `wps:wsp` line with `a:tailEnd type="arrow"`, printed as bare
            // lines.)
            let arrowed = node.descendant("wpg:wgp") == nil && (node.descendant("wps:spPr")?.first("a:ln").map { ln in
                [ln.first("a:headEnd"), ln.first("a:tailEnd")].contains { ($0?["type"]).map { $0 != "none" } ?? false }
            } ?? false)
            if arrowed, att.outline?.kind == .line { att.outline = nil }
            if let group = node.descendant("wpg:wgp") ?? (att.outline == nil ? node.descendant("wps:wsp") : nil) {
                let themeTarget = notes.rels.values.first(where: { $0.type.hasSuffix("/theme") && !$0.external })?.target ?? "theme/theme1.xml"
                WriterGroups.register(group, for: att.id, themePart: notes.part(_resolvePath("word", themeTarget)), wordArt: drawingWordArt,
                                      picture: { rid in
                    guard let rel = notes.rels[rid], !rel.external, let data = notes.part(_resolvePath("word", rel.target)),
                          Self._isRasterImage(data) else { return nil }
                    return data
                })
            } else if node.descendant("wpg:wgp") == nil, let group = _vmlTop(node), group.name == "v:group" {
                // (A VML group's lines and boxes likewise: zh-6e6b9821's
                // flowchart printed its text alone, no arrows or edges.)
                WriterGroups.registerVML(group, types: notes.shapeTypes, for: att.id, picture: { rid in
                    guard let rel = notes.rels[rid], !rel.external, let data = notes.part(_resolvePath("word", rel.target)),
                          Self._isRasterImage(data) else { return nil }
                    return data
                })
            } else if node.descendant("wpg:wgp") == nil, node.descendant("wps:wsp") == nil, att.outline == nil,
                      let shape = _vmlTop(node), ["v:rect", "v:roundrect", "v:oval", "v:shape"].contains(shape.name),
                      !(shape.first("v:imagedata").map { $0["r:id"] != nil || $0["o:relid"] != nil } ?? false) {
                // (A VML shape alone: its edges and fill — zh-7773163d's
                // framed steps on p35 printed their text alone.)
                WriterGroups.registerVMLShape(shape, types: notes.shapeTypes, for: att.id)
            }
            // A chart: its part read and drawn as Slides does one
            // (`WriterCharts`), in the document's theme.
            if let rid = node.descendant("c:chart")?["r:id"], let rel = notes.rels[rid], !rel.external,
               let data = notes.part(_resolvePath("word", rel.target)), let space = XNode.parse(data) {
                let themeTarget = notes.rels.values.first(where: { $0.type.hasSuffix("/theme") && !$0.external })?.target ?? "theme/theme1.xml"
                // (With the chart part's own theme override, for its faces.)
                var comps = _resolvePath("word", rel.target).split(separator: "/").map(String.init)
                let file = comps.popLast() ?? ""
                let dir = comps.joined(separator: "/")
                let over = notes.part(dir + "/_rels/" + file + ".rels").flatMap(XNode.parse)?.all("Relationship")
                    .first(where: { ($0["Type"] ?? "").hasSuffix("/themeOverride") && $0["TargetMode"] != "External" })?["Target"]
                    .flatMap { notes.part(_resolvePath(dir, $0)) }
                WriterCharts.register(space, for: att.id, themePart: notes.part(_resolvePath("word", themeTarget)), themeOverride: over)
            }
            // A box-and-whisker chart (Office 2016's chartex part), drawn
            // on a column chart's axes, or a sunburst: named by `cx:chart`
            // (by `c:chart` it is read above, as chartex names its own).
            if node.descendant("c:chart") == nil, let space = boxWhisker(node) {
                let themeTarget = notes.rels.values.first(where: { $0.type.hasSuffix("/theme") && !$0.external })?.target ?? "theme/theme1.xml"
                WriterCharts.register(space, for: att.id, themePart: notes.part(_resolvePath("word", themeTarget)))
            }
            return att
        }
        /// The chartex part a drawing names (`cx:chart`, or `c:chart` in
        /// a chartex `a:graphicData`), where it is a chart this app draws
        /// (`ChartXML.readWordChartex`: box-and-whisker, sunburst).
        func boxWhisker(_ node: XNode) -> XNode? {
            guard let rid = (node.descendant("cx:chart") ?? node.descendant("c:chart"))?["r:id"], let rel = notes.rels[rid], !rel.external,
                  let data = notes.part(_resolvePath("word", rel.target)), let space = XNode.parse(data),
                  ChartXML.readWordChartex(space) != nil else { return nil }
            return space
        }
        func addImage(_ drawing: XNode) {
            // (A group of a picture and shapes — lo tdf126426's photo under a
            // white text box — is a drawing, not the picture its first
            // `a:blip` is: its boxes' text was drawn nowhere.)
            if drawing.descendant("wpg:wgp") != nil, drawing.descendant("wps:wsp") != nil, drawing.descendant("pic:pic") != nil {
                addObject(drawing)
                return
            }
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
                if Metafile.isMetafile(data) { WriterMetafiles.register(data, for: att.id) }
                // (Turned, a photo taken sideways: a quarter turn makes
                // its box as tall as it was wide — zh-37b6536f.)
                if let rot = drawing.descendant("a:graphic")?.descendant("a:xfrm")?["rot"].flatMap({ Double($0) }) {
                    att.rotation = rot / 60000
                }
                addInline(att)
                return
            }
            // An inline picture keeps its markup too (effectExtent, docPr,
            // crop), used while the editor has not resized it.
            var att = ImageAttachment(data: data, width: w, height: h, name: target.lastPathComponent)
            if let effect = drawing.descendant("wp:effectExtent") {
                att.effectLeft = max(0, (Double(effect["l"] ?? "") ?? 0) / 12700)
                att.effectRight = max(0, (Double(effect["r"] ?? "") ?? 0) / 12700)
                att.effectTop = max(0, (Double(effect["t"] ?? "") ?? 0) / 12700)
                att.effectBottom = max(0, (Double(effect["b"] ?? "") ?? 0) / 12700)
            }
            if let frag = _keptFragment(drawing, notes) {
                att.sourceXML = frag.xml
                att.sourceRels = frag.rels
                att.sourceWidth = w
                att.sourceHeight = h
            }
            // (A picture that is a WMF or EMF is played as an object's
            // is (`WriterMetafiles`); no image codec reads it. zh-8d72961c's
            // page 2 is one, its Arabic and Latin text in ExtTextOutW
            // records, and printed as the grey stand-in.)
            if Metafile.isMetafile(data) { WriterMetafiles.register(data, for: att.id) }
            addInline(att)
        }
        func addText(_ s: String, _ cs: CharStyle) {
            guard !s.isEmpty else { return }
            text += s
            runs.append(Run(length: s.utf16.count, style: cs))
        }
        var pendingCheckbox: Bool? = nil   // a FORMCHECKBOX field's state, from its begin
        var pendingDropdown: String? = nil // a FORMDROPDOWN field's chosen entry, from its begin
        func walkRun(_ r: XNode, link: String?, revision: RevisionMark? = nil) {
            var cs = cellChar
            cs.link = link
            cs.revision = revision
            cs.comments = notes.openComments
            // Text that is a page reference's result stays one: Word
            // brings these up to date when it prints, and a contents page
            // of plain numbers kept the ones the file was saved with (a
            // Kinmen emergency plan listed its chapters 5 to 46 pages
            // early). Other fields stay the text they show.
            if let f = notes.fields.last, f.result {
                cs.fieldResult = f.id
                let instr = f.instr.trimmingWhitespace(newlines: true)
                if instr.uppercased().hasPrefix("PAGEREF ") { cs.field = instr }
                else if notes.inHeaderFooter, DocxFormat._isPageField(instr) {
                    // (A page number Word works out again as it prints, in
                    // its code's look unless the code keeps the result's
                    // with \* MERGEFORMAT: zh-7773163d's folio, a PAGE field
                    // whose code run is Times 12pt and whose result run says
                    // nothing, prints at 12pt; ours took the result run's
                    // default, 9.2pt and 8.5pt low.)
                    if !instr.uppercased().containsSubstring("MERGEFORMAT"), let code = notes.fieldCodeStyle[f.id] {
                        let id = cs.fieldResult, link = cs.link, revision = cs.revision, comments = cs.comments
                        cs = code
                        cs.fieldResult = id
                        cs.link = link
                        cs.revision = revision
                        cs.comments = comments
                    }
                    cs.field = instr; notes.fieldShown = true
                }
            }
            // (Its style reference would name an id the save may rename.)
            runPropertiesXML = r.first("w:rPr").flatMap { $0.first("w:rStyle") == nil && !$0.children.isEmpty ? PptxXML.serialize($0) : nil }
            runFrame = r.first("w:rPr")?.first("w:bdr").flatMap(_borderLine).flatMap { $0.width > 0 ? $0 : nil }
            defer { runPropertiesXML = nil; runFrame = nil; runRaised = nil }
            if let rPr = r.first("w:rPr") {
                // The run's character style first, then its own properties.
                let runText = r.children.filter { $0.name == "w:t" }.map(\.text).joined()
                let complex = runText.unicodeScalars.contains {
                    (0x0590...0x08FF).contains($0.value) || (0xFB1D...0xFDFF).contains($0.value) || (0xFE70...0xFEFF).contains($0.value)
                }
                if let id = rPr.first("w:rStyle")?["w:val"], let chain = notes.charStyleChains[id] {
                    for styled in chain { cs = _charStyle(styled, base: cs, complexText: complex) }
                }
                cs = _charStyle(rPr, base: cs, complexText: complex)
            }
            // A link the file does not underline (no Hyperlink character
            // style on its run, or one that says so): the save names the
            // style again, so the run has to say "none" over it —
            // bug59058's green reference numbers came back underlined.
            if link != nil, !cs.underline { cs.off.insert(.underline) }
            runRaised = cs.raised
            for child in r.children {
                switch child.name {
                case "w:t":
                    if notes.fieldCodeChanged, notes.fields.last?.result == true {
                        var first = cs
                        first.fieldCodeChanged = true
                        addText(_runText(child), first)
                        notes.fieldCodeChanged = false
                    } else {
                        addText(_runText(child), cs)
                    }
                case "w:fldChar":
                    if cs.formatChange != nil, child["w:fldCharType"] != "end", notes.fields.last.map({ !$0.result }) ?? true {
                        notes.fieldCodeChanged = true
                    }
                    if child["w:fldCharType"] == "end" { notes.fieldCodeChanged = false }
                    switch child["w:fldCharType"] {
                    case "begin":
                        notes.fieldCount += 1
                        notes.fields.append((instr: "", result: false, id: notes.fieldCount)); notes.fieldShown = false
                    case "separate": if !notes.fields.isEmpty { notes.fields[notes.fields.count - 1].result = true }
                    case "end":
                        // (A page field with no result yet shows a number
                        // all the same.)
                        if notes.inHeaderFooter, !notes.fieldShown, let f = notes.fields.last {
                            let instr = f.instr.trimmingWhitespace(newlines: true)
                            if DocxFormat._isPageField(instr) {
                                var shown = cs
                                shown.field = instr
                                addText("1", shown)
                            }
                        }
                        // (An EQ field that rings a number, `eq \o\ac(○,1)`,
                        // with no result written: Word draws the two
                        // overlaid, an em wide — the circled number.
                        // zh-e0ca7252's 27 "○1".."○4" open lines of its
                        // insurance clauses; dropped, each line took two
                        // characters more and its pages ran ahead.)
                        if let f = notes.fields.last, !f.result, let ringed = DocxFormat._ringedNumber(f.instr) {
                            var shown = cs
                            shown.field = f.instr.trimmingWhitespace(newlines: true)
                            addText(ringed, shown)
                        }
                        if !notes.fields.isEmpty { notes.fields.removeLast() }
                    default: break
                    }
                    // A form checkbox has no result text: it is the box
                    // itself, shown as a glyph (form_footnotes' 29 boxes).
                    // A drop-down form field shows its chosen entry, and has
                    // no result text of its own: zh-cd8987db's cover picks
                    // "（征求意见稿）", the fourth of its list, which Word
                    // prints and ours had left out.
                    if child["w:fldCharType"] == "begin", let list = child.first("w:ffData")?.first("w:ddList") {
                        let entries = list.all("w:listEntry").compactMap { $0["w:val"] }
                        let chosen = Int(list.first("w:result")?["w:val"] ?? list.first("w:default")?["w:val"] ?? "0") ?? 0
                        pendingDropdown = chosen >= 0 && chosen < entries.count ? entries[chosen] : nil
                    }
                    if child["w:fldCharType"] == "begin", let box = child.first("w:ffData")?.first("w:checkBox") {
                        let on = box.first("w:checked").map { !_isOff($0) } ?? (box.first("w:default")?["w:val"] == "1")
                        pendingCheckbox = on
                    }
                case "w:instrText":
                    if let f = notes.fields.last, !f.result {
                        notes.fields[notes.fields.count - 1].instr += child.text
                        if notes.fieldCodeStyle[f.id] == nil, !child.text.trimmingWhitespace(newlines: true).isEmpty { notes.fieldCodeStyle[f.id] = cs }
                    }
                    if cs.formatChange != nil { notes.fieldCodeChanged = true }
                    if let on = pendingCheckbox, child.text.uppercased().containsSubstring("FORMCHECKBOX") {
                        addText(on ? "\u{2612}" : "\u{2610}", cs)
                        pendingCheckbox = nil
                    }
                    if let entry = pendingDropdown, child.text.uppercased().containsSubstring("FORMDROPDOWN") {
                        addText(entry, cs)
                        pendingDropdown = nil
                    }
                case "w:commentReference":
                    // A comment with no range (comment.docx's LibreOffice
                    // comment) anchors at a point: a zero-width run carries
                    // it, so the balloon survives the save.
                    if notes.kept["word/comments.xml"] != nil, let id = child["w:id"], !notes.seenComments.contains(id) {
                        notes.seenComments.insert(id)
                        var point = cs
                        point.comments = cs.comments + [id]
                        addText("\u{200B}", point)
                    }
                case "w:delText": addText(child.text, cs)
                case "w:tab": addText("\t", cs)
                // A positional tab (a header's or footer's "right of the
                // margin"): a tab the layout sends to its place on the
                // margins, whatever stops lie before it (bug57031's "Page
                // 2 of 14", whose right ptab is the line's first tab).
                case "w:ptab":
                    let alignment: TabStop.Alignment = child["w:alignment"] == "right" ? .right
                        : child["w:alignment"] == "center" ? .center : .left
                    if child["w:relativeTo"] != "indent" {
                        positionalTabs[text.utf16.filter { $0 == 0x09 }.count] = alignment
                    }
                    addText("\t", cs)
                case "w:br" where child["w:type"] == "page" && cellResolve != nil:
                    // A page break in a table cell is nothing: zh-8112041b's
                    // form title opens its cell with two, and Word's print
                    // sets it on the cell's first line, under the page's
                    // empty paragraphs, where ours split an empty line off.
                    break
                case "w:br":
                    // A page break ends the paragraph; a line break stays
                    // inside it, as Shift+Return's does — splitting it added a
                    // paragraph (and its spacing) on every soft break.
                    // (A column break opening a paragraph is the same on a
                    // page of one column: read as a line break, a Changhua
                    // grant notice's outline began on the page before.)
                    let opensWithColumnBreak = child["w:type"] == "column" && text.isEmpty && inlineImages.isEmpty && built.isEmpty && !leadingBreak
                    if opensWithColumnBreak { leadingColumnBreak = true }
                    if text.isEmpty, inlineImages.isEmpty, built.isEmpty, !leadingBreak { leadingBreakRPr = runPropertiesXML }
                    if child["w:type"] == "page" || opensWithColumnBreak {
                        // A break that OPENS its paragraph is the paragraph
                        // starting a page: split off, it left an empty
                        // paragraph before the break, and where the page was
                        // full that paragraph took a page of its own (a
                        // blank page three in a Fujian plan of four pages).
                        // (Decided at the paragraph's end: a paragraph that is
                        // ONLY the break keeps its line on the page before.)
                        if text.isEmpty, inlineImages.isEmpty, built.isEmpty, !leadingBreak { leadingBreak = true }
                        else {
                            flush(pageBreakAfter: true)
                            built[built.count - 1].breakCharacter = true; built[built.count - 1].breakRPr = runPropertiesXML
                            splitBefore = true
                        }
                    } else { addText("\n", cs) }
                case "w:noBreakHyphen": addText("\u{2011}", cs)
                case "w:softHyphen": addText("\u{00AD}", cs)
                case "w:ruby":
                    // Ruby over its base (furigana over kanji): the base is
                    // the run's text, in its own runs' looks, and the ruby
                    // rides on their style, to be drawn over them. 61470's
                    // "東京" under "とうきょう" was dropped whole, and its
                    // page came out blank.
                    guard let baseNode = child.first("w:rubyBase") else { break }
                    let pr = child.first("w:rubyPr"), rt = child.first("w:rt")
                    let rubyText = (rt?.all("w:r") ?? []).flatMap { $0.children.filter { $0.name == "w:t" } }.map(_runText).joined()
                    let ruby = RubyText(text: rubyText,
                                        size: (Double(pr?.first("w:hps")?["w:val"] ?? "") ?? 0) / 2,
                                        raise: (Double(pr?.first("w:hpsRaise")?["w:val"] ?? "") ?? 0) / 2,
                                        align: pr?.first("w:rubyAlign")?["w:val"],
                                        group: text.utf16.count,
                                        xml: [pr, rt].compactMap { $0.map { PptxXML.serialize($0) } }.joined())
                    for br in baseNode.all("w:r") {
                        var look = cs
                        if let rPr = br.first("w:rPr") {
                            if let id = rPr.first("w:rStyle")?["w:val"], let chain = notes.charStyleChains[id] {
                                for styled in chain { look = _charStyle(styled, base: look, complexText: false) }
                            }
                            look = _charStyle(rPr, base: look, complexText: false)
                        }
                        look.ruby = ruby
                        for t in br.children where t.name == "w:t" { addText(_runText(t), look) }
                    }
                case "w:sym":
                    // A symbol: the character means its glyph only in the
                    // named font (Symbol F094 is a box), so the run takes it.
                    if let code = child["w:char"], let v = UInt32(code, radix: 16), let sc = UnicodeScalar(v) {
                        var sym = cs
                        if let font = child["w:font"], !font.isEmpty { sym.fontFamily = font }
                        addText(String(Character(sc)), sym)
                    }
                case "w:drawing", "w:pict":
                    // (An empty one is nothing: bug59058's `<w:pict/>`
                    // before a table is no mark on Word's print and takes
                    // no room there, where its 300 by 200 stand-in set
                    // the table 187pt low.)
                    guard !child.children.isEmpty else { break }
                    addImage(child)
                case "w:object":
                    addObject(child)
                case "mc:AlternateContent":
                    // A Choice this app cannot draw — Word 2016's charts,
                    // `cx` — is the picture of it the Fallback holds:
                    // chartex's six charts took no room at all.
                    // A box-and-whisker chart or a sunburst is drawn as Word
                    // draws it, its text text (chartex's: 8 lines of Word's
                    // print, and the sunburst's 16).
                    let requires = (child.first("mc:Choice")?["Requires"] ?? "").split(separator: " ")
                    if requires.contains("cx"), let drawing = child.first("mc:Choice")?.first("w:drawing"),
                       boxWhisker(drawing) != nil {
                        addObject(drawing)
                    } else if requires.contains("cx"), let drawing = child.first("mc:Fallback")?.first("w:drawing"),
                       drawing.descendant("a:blip") != nil {
                        addImage(drawing)
                    } else {
                        addObject(child)
                    }
                case "w:footnoteReference", "w:endnoteReference":
                    // The mark: its number as superscript text, tagged with
                    // the note it stands for so the writer puts the
                    // reference back. Word numbers marks in order of
                    // appearance; a custom mark (customMarkFollows) is the
                    // run's own text and needs no number.
                    let footnote = child.name == "w:footnoteReference"
                    guard footnote ? notes.footnotes : notes.endnotes, let id = Int(child["w:id"] ?? "") else { break }
                    // (Raised as its run says — its "footnote reference"
                    // style, most often: zh-7a16a243's marks are in runs
                    // that name no style, and Word's print sets "5" at the
                    // text's size on the line, 9.6pt wide where ours, raised
                    // and small, took 5.8 and a character more a line.)
                    var mark = cs
                    mark.note = NoteReference(kind: footnote ? .footnote : .endnote, id: id)
                    if child["w:customMarkFollows"] == "1" || child["w:customMarkFollows"] == "true" {
                        addText("\u{200B}", mark)
                    } else {
                        let n = notes.next(footnote: footnote)
                        if footnote, !notes.inTextBox, notes.footnoteNumbers[id] == nil { notes.footnoteNumbers[id] = n }
                        if !footnote, !notes.inTextBox, notes.endnoteNumbers[id] == nil { notes.endnoteNumbers[id] = n }
                        addText(notes.label(n, footnote: footnote), mark)
                    }
                case "w:footnoteRef":
                    // A note's own mark, in the note: its number.
                    if let n = notes.currentNote { addText(String(n), cs) }
                case "w:endnoteRef":
                    if let label = notes.currentNoteLabel { addText(label, cs) }
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
                    // (Text moved away stays moved away, whatever was done
                    // to it before.)
                    // (Both changes are kept, as Tika-792 prints them: an
                    // insertion moved away is gone, a deletion in moved
                    // text's new place leaves the place marked.)
                    if var r = revision, r.moved, r.kind == .deleted {
                        if child.name == "w:ins" { r.nested = true }
                        walkInline(child, link: link, revision: r); break
                    }
                    let mark = RevisionMark(kind: child.name == "w:ins" ? .inserted : .deleted,
                                            author: child["w:author"] ?? "", date: child["w:date"] ?? "",
                                            nested: child.name == "w:del" && revision?.moved == true && revision?.kind == .inserted)
                    walkInline(child, link: link, revision: mark)
                case "w:moveTo", "w:moveFrom":
                    // Moved text: at its new place an insertion, at its old
                    // one a deletion, as Word shows them (Tika-792's; they
                    // were skipped, and the text was gone from the page and
                    // from a save).
                    let mark = RevisionMark(kind: child.name == "w:moveTo" ? .inserted : .deleted,
                                            author: child["w:author"] ?? "", date: child["w:date"] ?? "", moved: true)
                    walkInline(child, link: link, revision: mark)
                case "w:fldSimple" where notes.inHeaderFooter && DocxFormat._isPageField(child["w:instr"] ?? ""):
                    notes.fieldCount += 1
                    notes.fields.append((instr: child["w:instr"] ?? "", result: true, id: notes.fieldCount))
                    walkInline(child, link: link, revision: revision)
                    notes.fields.removeLast()
                case "w:smartTag", "w:sdtContent", "w:sdt", "w:fldSimple", "w:customXml":
                    walkInline(child, link: link, revision: revision)
                case "m:oMathPara", "m:oMath":
                    // An equation: kept as the file wrote it, and drawn by
                    // `WriterMath` at the size it lays out to.
                    if let frag = _keptFragment(child, notes) {
                        var att = ImageAttachment(data: Data(), width: 1, height: 1, name: child.name)
                        att.sourceXML = frag.xml
                        att.sourceRels = frag.rels
                        // (Its runs' size where they say none: the paragraph's —
                        // its mark's, its style's, Normal's. zh-db07d44e's
                        // cell equation is 12pt in Word's print, Normal's, and
                        // breaks where 11 would hold a piece more.)
                        var mathSize: Double = 11
                        if let n = sheet["Normal"]?.char.fontSize { mathSize = n }
                        if let named = style.named, let n = sheet[named]?.char.fontSize { mathSize = n }
                        if let n = cellChar.fontSize { mathSize = n }
                        if let n = markStyle?.fontSize { mathSize = n }
                        if let m = WriterMath.register(child, for: att.id, size: mathSize) {
                            att.width = m.width
                            att.height = m.height
                            att.baseline = m.baseline
                        }
                        addInline(att)
                    }
                case "w:commentRangeStart":
                    if notes.kept["word/comments.xml"] != nil, let id = child["w:id"] { notes.openComments.append(id); notes.seenComments.insert(id) }
                case "w:commentRangeEnd":
                    if let id = child["w:id"] { notes.openComments.removeAll { $0 == id } }
                case "w:bookmarkStart":
                    if let name = child["w:name"], name != "_GoBack" { notes.pendingBookmarks.append(name) }
                case "w:pPr", "w:proofErr", "w:bookmarkEnd":
                    break
                default: break
                }
            }
        }
        walkInline(p, link: nil)
        // (A display equation stands centred — Word's `m:jc` centerGroup,
        // its default — whatever its paragraph's own alignment.)
        if let display = p.first("m:oMathPara") {
            switch display.first("m:oMathParaPr")?.first("m:jc")?["m:val"] {
            case "left": style.alignment = .left
            case "right": style.alignment = .right
            default: style.alignment = .center
            }
        }
        else if p.children.contains(where: { $0.name == "m:oMath" }),
                p.children.allSatisfy({ ["w:pPr", "w:proofErr", "w:bookmarkStart", "w:bookmarkEnd", "m:oMath"].contains($0.name) }) {
            // (A paragraph that holds nothing but a bare `m:oMath` is a
            // display equation to Word too, centred like an `m:oMathPara`:
            // LibreOffice's tdf169843, whose ℝ stands at the page's middle
            // in Word's print and at the left margin in ours.)
            style.alignment = .center
        }
        if leadingBreak {
            // (A break followed by floating objects alone is a break too:
            // the objects stand with the paragraph's start, on the page
            // before, and the new page shows nothing for the mark — lab
            // `ab` (Word 16, zh-021b8feb's p14 paragraph: a page break and
            // a box "附表" 16.5pt down) sets the box at p14's foot, and the
            // next paragraph where it stands after a break alone; ours set
            // the box on p15 over a line of the mark, 20.7pt, and the
            // table after it ran onto a 19th page.)
            let floatsOnly = !inlineImages.isEmpty && inlineImages.values.allSatisfy { $0.float.map { !$0.takesRoom } ?? false }
            if built.isEmpty, text.unicodeScalars.allSatisfy({ $0.value == 0xFFFC }), inlineImages.isEmpty || floatsOnly {
                flush(pageBreakAfter: true)
                built[built.count - 1].breakCharacter = true; built[built.count - 1].breakRPr = leadingBreakRPr
                built[built.count - 1].breakColumn = leadingColumnBreak
                splitBefore = true   // (what follows the break is the same paragraph's: see where the body is written)
            }
            else if built.isEmpty { style.pageBreakBefore = true; style.pageBreakInline = true; style.columnBreak = leadingColumnBreak; style.breakRunPropertiesXML = leadingBreakRPr }
            else {
                built[0].paragraph.style.pageBreakBefore = true; built[0].paragraph.style.pageBreakInline = true
                built[0].paragraph.style.columnBreak = leadingColumnBreak; built[0].paragraph.style.breakRunPropertiesXML = leadingBreakRPr
            }
        }
        if text.isEmpty, inlineImages.isEmpty, let last = built.last, last.pageBreakAfter,
           !(notes.marksFollowBreaks && last.breakCharacter && !last.breakColumn) {
            // The paragraph ended with its page break: Word shows nothing
            // for its mark on the new page (SampleDoc's page two began
            // a line down), so no empty paragraph for it — the break
            // still lands on the next paragraph.
            // (Unless the file says the mark goes there, as Word's
            // `w:splitPgBreakAndParaMark` does before 2013's layout:
            // zh-64044a1d's annexes each follow a paragraph of a page
            // break alone, and Word's print opens their pages with the
            // mark's empty line — ours stood a line high, 36pt with the
            // heading's space before.)
            if sectionBreakAfter { built[built.count - 1].pageBreakAfter = true }
        } else {
            flush(pageBreakAfter: sectionBreakAfter)
        }
        return built
    }

    /// `w:rFonts` for a look: the Latin face in ascii and hAnsi, and in
    /// the complex-script slot too unless the file named another face
    /// there — rtl.docx's Arabic is set in its w:cs face, and with the
    /// Latin one written over it Word substituted a wider font and
    /// wrapped every paragraph elsewhere.
    private static func _rFontsXML(_ s: CharStyle, fileFonts: Set<String>, eastAsiaDefault: Bool = false) -> String {
        let latin = s.fontFamily.map { fileFonts.contains($0) ? $0 : OfficeFonts.exportName($0) }
        var attrs = ""
        if let latin { attrs += " w:ascii=\"\(_esc(latin))\" w:hAnsi=\"\(_esc(s.hAnsiFontFamily ?? latin))\"" }
        else if let h = s.hAnsiFontFamily { attrs += " w:hAnsi=\"\(_esc(h))\"" }
        if let hint = s.fontHint { attrs += " w:hint=\"\(_esc(hint))\"" }
        if let cs = s.complexFontFamily ?? latin { attrs += " w:cs=\"\(_esc(cs))\"" }
        if let ea = s.eastAsiaFontFamily ?? (eastAsiaDefault ? latin : nil) { attrs += " w:eastAsia=\"\(_esc(ea))\"" }
        return attrs.isEmpty ? "" : "<w:rFonts\(attrs)/>"
    }

    /// A run's properties (CT_RPr children, in schema order). A switch
    /// the run turns off explicitly (`off`) is written as off: a false
    /// alone means "inherit" (drawing.docx's "b w:val=0" runs under a
    /// bold heading 3 came back bold; 52288's plain runs under a bold
    /// style must not come back un-bold).
    private static func _rPrXML(_ s: CharStyle, fileFonts: Set<String> = [], changeId: Int? = nil) -> String {
        var rPr = ""
        func off(_ tag: String, _ sw: CharSwitches) -> String { s.off.contains(sw) ? "<w:\(tag) w:val=\"0\"/>" : "" }
    rPr += _rFontsXML(s, fileFonts: fileFonts)
    if s.bold { rPr += "<w:b/><w:bCs/>" } else { rPr += off("b", .bold) }
    if s.italic { rPr += "<w:i/><w:iCs/>" } else { rPr += off("i", .italic) }
    if s.caps { rPr += "<w:caps/>" } else { rPr += off("caps", .caps) }
    if s.hidden { rPr += "<w:vanish/>" } else { rPr += off("vanish", .hidden) }
    if s.smallCaps { rPr += "<w:smallCaps/>" } else { rPr += off("smallCaps", .smallCaps) }
    if s.underline { rPr += "<w:u w:val=\"single\"/>" } else if s.off.contains(.underline) { rPr += "<w:u w:val=\"none\"/>" }
    if s.strikethrough { rPr += "<w:strike/>" } else { rPr += off("strike", .strikethrough) }
    if let color = s.color { rPr += "<w:color w:val=\"\(_hex(color))\"/>" }
    if let ls = s.letterSpacing, ls != 0 { rPr += "<w:spacing w:val=\"\(Int((ls * 20).rounded()))\"/>" }
    if let k = s.kerningFrom { rPr += "<w:kern w:val=\"\(Int((k * 2).rounded()))\"/>" }
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
    if let fc = s.formatChange, let id = changeId {
        rPr += "<w:rPrChange w:id=\"\(id)\" w:author=\"\(_esc(fc.author.isEmpty ? "Author" : fc.author))\"\(fc.date.isEmpty ? "" : " w:date=\"\(_esc(fc.date))\"")>\(fc.oldRPrXML)</w:rPrChange>"
    }
    if s.rightToLeft { rPr += "<w:rtl/>" }
    if let kept = s.keptXML { rPr += kept }
        return rPr
    }

    /// How deep `w:tbl` elements nest under `node` (iterative; a fuzzer's
    /// 5,000-level table must not recurse).
    /// A section's columns from its `w:cols` (`sectionXML`), each one's
    /// width and the gap after it in points — the file's own where its
    /// columns are unequal, else equal shares of the text width. Nil for
    /// one column.
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

    static func _keptFragment(_ node: XNode, _ notes: _Shared) -> (xml: String, rels: [KeptRel])? {
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
    private static func _bordersXML(_ b: ParagraphBorders) -> String {
        func edge(_ name: String, _ l: BorderLine?) -> String {
            guard let l else { return "" }
            let color = l.color.map { _hex($0) } ?? "auto"
            return "<w:\(name) w:val=\"\(_esc(l.style ?? "single"))\" w:sz=\"\(Int((l.width * 8).rounded()))\" w:space=\"\(Int(l.space.rounded()))\" w:color=\"\(color)\"/>"
        }
        return "<w:pBdr>" + edge("top", b.top) + edge("left", b.left) + edge("bottom", b.bottom) + edge("right", b.right) + "</w:pBdr>"
    }

    /// `<w:spacing>` with the style's before, after and line, all of them
    /// (a paragraph that says nothing takes the file's defaults, which
    /// need not be ours). Twips and 240ths, rounded — truncation drifted
    /// 1.08 lines to 258/240 and on down with every save.
    /// `under` is the paragraph style's spacing: auto spacing the style
    /// turns on and the paragraph turns off is written as off (drawing's
    /// "after 240, afterAutospacing 0" under an auto-spaced style).
    static func _spacingXML(_ s: RichParagraphStyle, under: RichParagraphStyle? = nil) -> String {
        var spacing = ""
        // Zero included, when the paragraph's style has space before: a
        // Heading 6 spacer that says before 0 came back with the style's
        // 2pt, which moved the rest of form_footnotes' first page.
        if s.spaceBefore > 0 || (under?.spaceBefore ?? 0) > 0 { spacing += " w:before=\"\(Int((s.spaceBefore * 20).rounded()))\"" }
        if s.spaceBeforeAuto { spacing += " w:beforeAutospacing=\"1\"" } else if under?.spaceBeforeAuto ?? false { spacing += " w:beforeAutospacing=\"0\"" }
        spacing += " w:after=\"\(Int((s.spaceAfter * 20).rounded()))\""
        if s.spaceAfterAuto { spacing += " w:afterAutospacing=\"1\"" } else if under?.spaceAfterAuto ?? false { spacing += " w:afterAutospacing=\"0\"" }
        if s.lineCollapsed, s.lineHeightPoints == nil {
            spacing += " w:line=\"0\" w:lineRule=\"auto\""
        } else if let pts = s.lineHeightPoints {
            spacing += " w:line=\"\(Int((pts * 20).rounded()))\" w:lineRule=\"\(s.lineHeightIsMinimum ? "atLeast" : "exact")\""
        } else {
            spacing += " w:line=\"\(Int((s.lineSpacing * 240).rounded()))\" w:lineRule=\"auto\""
        }
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
    private static func _inheritSpace(_ node: XNode, _ preserve: Bool = false) {
        let here = node["xml:space"].map { $0 == "preserve" } ?? preserve
        if node.name == "w:t" || node.name == "w:instrText" || node.name == "w:delText" {
            if here, node["xml:space"] == nil { node.attrs["xml:space"] = "preserve" }
            return
        }
        for child in node.children { _inheritSpace(child, here) }
    }

    private static func _runText(_ t: XNode) -> String {
        if t["xml:space"] == "preserve" { return t.text }
        let ws: Set<Character> = [" ", "\t", "\n", "\r", "\r\n"]
        var text = Substring(t.text)
        while let f = text.first, ws.contains(f) { text.removeFirst() }
        while let l = text.last, ws.contains(l) { text.removeLast() }
        return String(text)
    }

    private static func _isOff(_ node: XNode) -> Bool {
        switch node["w:val"] {
        case "0", "false", "off": return true
        default: return false
        }
    }

    /// `complexText` says whether the run's characters are complex-script
    /// ones (Arabic, Hebrew, ...): Word applies w:bCs/w:iCs/w:szCs to those
    /// characters only, so a Latin "Reino de España" inside an Arabic
    /// paragraph stays plain. nil falls back to the run's w:rtl.
    private static func _charStyle(_ rPr: XNode, base: CharStyle, complexText: Bool? = nil) -> CharStyle {
        var cs = base
        // Complex-script bold, italic and size (w:bCs, w:iCs, w:szCs) are
        // what a right-to-left run is set in; rtl.docx's Arabic headings
        // say bCs alone and came back plain.
        var sawB = false, sawI = false, sawSz = false
        // Kept properties by name, so a run's own replaces its style's.
        var keptRun: [String: String] = [:]
        var bCs: Bool? = nil, iCs: Bool? = nil, szCs: Double? = nil
        for child in rPr.children {
            switch child.name {
            case "w:bCs": bCs = !_isOff(child)
            case "w:iCs": iCs = !_isOff(child)
            case "w:szCs": szCs = Double(child["w:val"] ?? "").map { $0 / 2 }
            case "w:rPrChange":
                cs.formatChange = FormatChange(author: child["w:author"] ?? "", date: child["w:date"] ?? "",
                                               oldRPrXML: child.first("w:rPr").map { PptxXML.serialize($0) } ?? "<w:rPr/>")
            case "w:b": sawB = true; cs.bold = !_isOff(child); if cs.bold { cs.off.remove(.bold) } else { cs.off.insert(.bold) }
            case "w:i": sawI = true; cs.italic = !_isOff(child); if cs.italic { cs.off.remove(.italic) } else { cs.off.insert(.italic) }
            case "w:u": cs.underline = child["w:val"] != "none"; if cs.underline { cs.off.remove(.underline) } else { cs.off.insert(.underline) }
            case "w:strike", "w:dstrike": cs.strikethrough = !_isOff(child); if cs.strikethrough { cs.off.remove(.strikethrough) } else { cs.off.insert(.strikethrough) }
            case "w:caps": cs.caps = !_isOff(child); if cs.caps { cs.off.remove(.caps) } else { cs.off.insert(.caps) }
            case "w:vanish": cs.hidden = !_isOff(child); if cs.hidden { cs.off.remove(.hidden) } else { cs.off.insert(.hidden) }
            case "w:spacing": if let v = Double(child["w:val"] ?? "") { cs.letterSpacing = v / 20 }
            case "w:rtl": cs.rightToLeft = !_isOff(child)
            case "w:kern": if let v = Double(child["w:val"] ?? "") { cs.kerningFrom = v / 2 }
            // (`w:cs`, the run's text taken as complex script, kept for
            // the layout too: see `RichLayout`'s wide spaces.)
            case "w:w", "w:position", "w:bdr", "w:lang", "w:em", "w:fitText", "w:snapToGrid", "w:eastAsianLayout", "w:cs":
                if child.name == "w:position", let v = Double(child["w:val"] ?? "") { cs.raised = v / 2 }
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
                // A slot the element leaves out is inherited, not cleared
                // (a style's lone w:cs must not drop its Latin face).
                // The Latin face is w:ascii's. A run that names only w:hAnsi
                // (Chinese text usually does, beside w:eastAsia) keeps its
                // inherited ascii face: its digits and letters stay in
                // Times, and came back in the East Asian face otherwise.
                if let f = _family(child["w:ascii"] ?? "") { cs.fontFamily = f }
                if let f = _family(child["w:cs"] ?? "") { cs.complexFontFamily = f }
                if let h = _family(child["w:hAnsi"] ?? "") { cs.hAnsiFontFamily = h == cs.fontFamily ? nil : h }
                else if child["w:ascii"] != nil, child["w:hAnsi"] == nil, base.hAnsiFontFamily == nil, base.fontFamily != nil, base.fontFamily != cs.fontFamily {
                    cs.hAnsiFontFamily = base.fontFamily   // ascii alone: hAnsi stays the inherited face
                }
                if let h = child["w:hint"] { cs.fontHint = h }
                if let f = _family(child["w:eastAsia"] ?? "") { cs.eastAsiaFontFamily = f }
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
            cs.keptXML = ["w:bdr", "w:w", "w:position", "w:fitText", "w:cs", "w:em", "w:lang", "w:eastAsianLayout", "w:snapToGrid"].compactMap { all[$0] }.joined()
        }
        if complexText ?? cs.rightToLeft {
            if !sawB, let b = bCs { cs.bold = b; if b { cs.off.remove(.bold) } else { cs.off.insert(.bold) } }
            if !sawI, let i = iCs { cs.italic = i; if i { cs.off.remove(.italic) } else { cs.off.insert(.italic) } }
            if !sawSz, let z = szCs { cs.fontSize = z }
        }
        return cs
    }

    /// A `CharStyle.keptXML` taken apart again, by element name.
    private static func _keptRunProperties(_ xml: String?) -> [String: String] {
        guard let xml, let node = XNode.parse(Data(("<x xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">" + xml + "</x>").utf8)) else { return [:] }
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

    private static func _highlight(_ name: String) -> Color? {
        highlightNames.first { $0.0 == name }?.1
    }

    /// The font name as the file has it. Kept, not mapped: the face it
    /// draws with is `OfficeFonts.substitute`'s choice at render time, and
    /// the name goes back out unchanged on save.
    /// Every family a part names in a `w:rFonts` (ascii and hAnsi).
    private static func _declaredFonts(_ data: Data?) -> Set<String> {
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
        func commentsAfter(_ index: Int, _ runIndex: Int) -> [String] {
            let p = doc.paragraphs[index]
            if let next = p.runs[(runIndex + 1)...].first(where: { $0.length > 0 }) { return next.style.comments }
            guard index + 1 < doc.paragraphs.count else { return [] }
            let np = doc.paragraphs[index + 1]
            return (np.runs.first(where: { $0.length > 0 }) ?? np.runs.first)?.style.comments ?? []
        }
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
        /// A kept fragment with its relationships under fresh ids and its
        /// drawings' docPr ids made unique.
        func keptFragmentXML(_ xml: String, _ rels: [KeptRel]) -> String {
            var frag = _renumberDocPr(xml, next: &keptDocPrCount)
            for rel in rels {
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
        func paragraphXML(_ index: Int) -> String {
            let p = doc.paragraphs[index]
            var body = ""
            var pPr = ""
            if let h = p.style.heading { pPr += "<w:pStyle w:val=\"Heading\(min(h, 6))\"/>" }
            else if let n = p.style.named, doc.styles[n] != nil { pPr += "<w:pStyle w:val=\"\(_esc(n))\"/>" }
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
            if p.style.fill == nil, ownStyle?.fill != nil { pPr += "<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"auto\"/>" }
            if let fill = p.style.fill { pPr += "<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"\(_hex(fill))\"/>" }
            if p.style.rightToLeft { pPr += "<w:bidi/>" }
            else if p.style.named.flatMap({ doc.styles[$0] })?.paragraph.rightToLeft ?? false { pPr += "<w:bidi w:val=\"0\"/>" }
            pPr += _tabsXML(p.style.tabStops, under: ownStyle?.tabStops ?? [])
            // Spacing spelled out on every paragraph, so that Word and we
            // lay the file out alike whatever its defaults say.
            pPr += _eastAsianSwitchesXML(p.style)
            pPr += _withEastAsian(_spacingXML(p.style, under: (p.style.heading.flatMap { doc.styles["Heading\(min($0, 6))"] } ?? p.style.named.flatMap { doc.styles[$0] })?.paragraph), "w:spacing", _eastAsianSpacing, p.style)
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
            pPr += _withEastAsian(ind.isEmpty ? "" : "<w:ind\(ind)/>", "w:ind", _eastAsianIndents, p.style)
            if p.style.contextualSpacing { pPr += "<w:contextualSpacing/>" }
            switch p.style.alignment {
            case .left:
                // Left under a style that centres has to say so.
                if let a = sheetEntry?.paragraph.alignment, a != .left { pPr += "<w:jc w:val=\"left\"/>" }
            case .center: pPr += "<w:jc w:val=\"center\"/>"
            case .right: pPr += "<w:jc w:val=\"right\"/>"
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
                revisionCount += 1
                let tag = rev.kind == .inserted ? "w:ins" : "w:del"
                markRPr += "<\(tag) w:id=\"\(revisionCount)\" w:author=\"\(_esc(rev.author.isEmpty ? "Author" : rev.author))\"\(rev.date.isEmpty ? "" : " w:date=\"\(_esc(rev.date))\"")/>"
            }
            let anchorOnly = p.image?.sourceXML?.containsSubstring("<wp:anchor") ?? false
            if p.text.isEmpty, p.image == nil || anchorOnly, let first = p.runs.first {
                markRPr += _rPrXML(first.style, fileFonts: doc.fileFonts)
            } else if let mark = p.style.mark {
                // The mark's own look on a paragraph with text: a list
                // number is formatted with it, and a hidden mark over
                // hidden text makes Word show no line and no border.
                markRPr += _rPrXML(mark, fileFonts: doc.fileFonts)
            } else if p.style.markHidden {
                markRPr += "<w:vanish/>"
            }
            if !markRPr.isEmpty { pPr += "<w:rPr>\(markRPr)</w:rPr>" }
            if let sect = p.style.sectionXML, p.cell == nil, index < doc.paragraphs.count - 1 { pPr += keptFragmentXML(sect, p.style.sectionRels) }
            body += "<w:p><w:pPr>\(pPr)</w:pPr>"
            for name in p.bookmarks where writtenBookmarks.insert(name).inserted {
                // (Numbered clear of any a kept table's own XML carries.)
                let id = 100_000 + writtenBookmarks.count
                body += "<w:bookmarkStart w:id=\"\(id)\" w:name=\"\(_esc(name))\"/><w:bookmarkEnd w:id=\"\(id)\"/>"
            }
            var fieldBefore: String? = nil   // the field the run before this one was the result of
            if inlineBreak {
                // In its own run's look: an indent counted in characters
                // is measured by the paragraph's first run, which the
                // break is (a 1.5-character indent under a 16pt title came
                // back 6pt short behind a bare break).
                body += "<w:r>\(p.style.breakRunPropertiesXML ?? "")<w:br w:type=\"\(columnBreak ? "column" : "page")\"/></w:r>"
            }
            /// A picture or kept object as a run's content.
            func drawingXML(_ image: ImageAttachment) -> String {
                let unresized = image.sourceWidth == nil || (image.sourceWidth == image.width && image.sourceHeight == image.height)
                // (An equation stands in the paragraph itself, not in a run.)
                if let xml = image.sourceXML, image.name == "m:oMath" || image.name == "m:oMathPara" {
                    return keptFragmentXML(xml, image.sourceRels)
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
                let cx = Int(image.width * 12700), cy = Int(image.height * 12700)
                return "<w:r><w:drawing><wp:inline distT=\"0\" distB=\"0\" distL=\"0\" distR=\"0\"><wp:extent cx=\"\(cx)\" cy=\"\(cy)\"/><wp:docPr id=\"\(n)\" name=\"Picture \(n)\"/><a:graphic xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\"><a:graphicData uri=\"http://schemas.openxmlformats.org/drawingml/2006/picture\"><pic:pic xmlns:pic=\"http://schemas.openxmlformats.org/drawingml/2006/picture\"><pic:nvPicPr><pic:cNvPr id=\"0\" name=\"\(name)\"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed=\"\(rid)\"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"\(cx)\" cy=\"\(cy)\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r>"
            }
            if let image = p.image {
                body += drawingXML(image) + "</w:p>"
                return body
            }
            var pos = 0
            let utf16 = p.text.utf16
            for (runIndex, run) in p.runs.enumerated() where run.length > 0 {
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
                if s.formatChange != nil { revisionCount += 1; changeId = revisionCount }
                var rPr = _rPrXML(s, fileFonts: doc.fileFonts, changeId: changeId)
                if let note = s.note, doc.keptParts[note.kind == .footnote ? "word/footnotes.xml" : "word/endnotes.xml"] != nil {
                    // The mark's number is Word's to show; the run carries
                    // only the reference (and its custom mark text, if any),
                    // with its own look — size and font decide where the
                    // line wraps.
                    let tag = note.kind == .footnote ? "w:footnoteReference" : "w:endnoteReference"
                    let st = doc.keptCharacterStyleIds[note.kind == .footnote ? "footnote reference" : "endnote reference"]
                        ?? (note.kind == .footnote ? "FootnoteReference" : "EndnoteReference")
                    let custom = piece.filter { $0 != "\u{200B}" && !$0.isNumber }
                    // (A mark the file set on the baseline keeps it, under
                    // the reference style's superscript.)
                    if s.script != .superscript { rPr += "<w:vertAlign w:val=\"baseline\"/>" }
                    body += "<w:r><w:rPr><w:rStyle w:val=\"\(st)\"/>\(rPr)</w:rPr>"
                    body += custom.isEmpty ? "<\(tag) w:id=\"\(note.id)\"/>" : "<\(tag) w:customMarkFollows=\"1\" w:id=\"\(note.id)\"/>\(_text(custom))"
                    body += "</w:r>"
                    continue
                }
                if s.link != nil { rPr = "<w:rStyle w:val=\"\(_esc(doc.keptCharacterStyleIds["hyperlink"] ?? "Hyperlink"))\"/>" + rPr }
                let rPrXML = rPr.isEmpty ? "" : "<w:rPr>\(rPr)</w:rPr>"
                var runXML = ""
                let isBox: (Character) -> Bool = { $0 == "\u{2610}" || $0 == "\u{2612}" }
                if s.revision?.kind != .deleted, piece.contains(where: isBox) {
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
                if let instr = s.field {
                    // One field per result: a result in two looks is still
                    // one number, and Word writes all of it afresh.
                    if fieldBefore == instr { continue }
                    runXML = "<w:r>\(rPrXML)<w:fldChar w:fldCharType=\"begin\"/></w:r><w:r>\(rPrXML)<w:instrText xml:space=\"preserve\"> \(_esc(instr)) </w:instrText></w:r><w:r>\(rPrXML)<w:fldChar w:fldCharType=\"separate\"/></w:r>\(runXML)<w:r>\(rPrXML)<w:fldChar w:fldCharType=\"end\"/></w:r>"
                }
                fieldBefore = s.field
                if let rev = s.revision {
                    revisionCount += 1
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
                if let link = s.link {
                    if link.hasPrefix("#") {
                        body += "<w:hyperlink w:anchor=\"\(_esc(String(link.dropFirst())))\">\(runXML)</w:hyperlink>"
                    } else {
                        body += "<w:hyperlink r:id=\"\(relId(for: link))\">\(runXML)</w:hyperlink>"
                    }
                } else {
                    body += runXML
                }
                if commentsKept { body += closeComments(except: commentsAfter(index, runIndex)) }
            }
            if breakRidesOnPrevious(index + 1) {
                let next = doc.paragraphs[index + 1].style
                body += "<w:r>\(next.breakRunPropertiesXML ?? "")<w:br w:type=\"\(next.columnBreak ? "column" : "page")\"/></w:r>"
            }
            if commentsKept, index == doc.paragraphs.count - 1 { body += closeComments(except: []) }
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
            if !style.bordersFromCells { xml += "<w:tblBorders>" }
            for (side, own) in [("top", e.top), ("left", e.left), ("bottom", e.bottom), ("right", e.right), ("insideH", e.insideH), ("insideV", e.insideV)] where !style.bordersFromCells {
                let val = style.edgeStyles[side].map { _esc($0) } ?? borderVal
                let sz = style.edgeWidths[side].map { Int(($0 * 8).rounded()) } ?? borderSz
                xml += (own ?? style.borders) ? "<w:\(side) w:val=\"\(val)\" w:sz=\"\(sz)\" w:space=\"0\" w:color=\"\(borderColor)\"/>"
                                              : "<w:\(side) w:val=\"none\" w:sz=\"0\" w:space=\"0\" w:color=\"auto\"/>"
            }
            if !style.bordersFromCells { xml += "</w:tblBorders>" }
            if style.fixedLayout { xml += "<w:tblLayout w:type=\"fixed\"/>" }
            let margins: [(String, Double?)] = [("top", style.cellMarginTop), ("left", style.cellMarginLeft),
                                                ("bottom", style.cellMarginBottom), ("right", style.cellMarginRight)]
            if let kept = style.keptCellMarginsXML, style.keptCellMarginsUnder == margins.map(\.1) {
                xml += kept
            } else if margins.contains(where: { $0.1 != nil }) {
                xml += "<w:tblCellMar>"
                for (side, v) in margins { if let v { xml += "<w:\(side) w:w=\"\(Int((v * 20).rounded()))\" w:type=\"dxa\"/>" } }
                xml += "</w:tblCellMar>"
            }
            xml += "<w:tblLook w:val=\"04A0\"/></w:tblPr><w:tblGrid>"
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
                    if let fill = ref?.fill { xml += "<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"\(_hex(fill))\"/>" }
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
                            for g in group { xml += paragraphXML(g) }
                            endedWithTable = false
                            continue
                        }
                        xml += paragraphXML(k)
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
                body += t.xml
                i = t.end
            } else {
                let xml = paragraphXML(i)
                // (The rest of a paragraph a page break split goes back into
                // it: the break ended the one before as its last run, and the
                // text after it is the same w:p. Written as two, the first's
                // mark read back as a paragraph of its own and every save
                // added one — LibreOffice's tdf123636_newlinePageBreak,
                // two paragraphs, then three.)
                if doc.paragraphs[i].style.continuesParagraph, breakRidesOnPrevious(i), body.hasSuffix("</w:p>"),
                   xml.hasPrefix("<w:p><w:pPr>"), let end = xml.range(of: "</w:pPr>") {
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
            ZipEntry(name: "word/styles.xml", data: Data(_stylesPart(doc.styles, notes: !doc.keptParts.isEmpty, aliases: doc.styleAliases, fileFonts: doc.fileFonts, fromFile: doc.readFromFile,
                                                                         characterStyles: doc.keptCharacterStyles, characterStyleIds: doc.keptCharacterStyleIds)
                .replacingAll("<w:lang w:val=\"en-US\"/>", with: doc.defaultLangXML ?? "<w:lang w:val=\"en-US\"/>").utf8)),
            ZipEntry(name: "word/numbering.xml", data: Data(_numberingPart(numKinds, numFormats, bulletId: bulletId, decimalId: decimalId,
                                                                                         counterOf: Dictionary(uniqueKeysWithValues: numIds.compactMap { k, v in doc.listCounterOf[k].map { (v, $0) } }),
                                                                                         restarts: Dictionary(uniqueKeysWithValues: numIds.compactMap { k, v in doc.listRestarts[k].map { (v, $0) } })).utf8)),
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
        let tabbed = template.contains("\t" as Character)
        let jc = tabbed
            ? "<w:pPr><w:tabs><w:tab w:val=\"center\" w:pos=\"\(Int((width * 10).rounded()))\"/><w:tab w:val=\"right\" w:pos=\"\(Int((width * 20).rounded()))\"/></w:tabs></w:pPr>"
            : (center ? "<w:pPr><w:jc w:val=\"center\"/></w:pPr>" : "")
        return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<\(tag) xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><w:p>\(jc)\(runs)</w:p></\(tag)>"
    }

    private static func _text(_ s: String) -> String {
        // Tabs and line breaks are elements, not characters — and so are
        // the optional and the non-breaking hyphen: the character U+00AD
        // in a w:t is not a break opportunity to Word, so bug65649's
        // "Техни-ческому" stayed whole and its autofit column grew by
        // the half word (three pages over 180).
        var out = ""
        var buf = ""
        func flush() {
            if !buf.isEmpty { out += "<w:t xml:space=\"preserve\">\(_esc(buf))</w:t>"; buf = "" }
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

    private static func _esc(_ s: String) -> String {
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
    private static func _stylesPart(_ sheet: RichStyleSheet, notes: Bool = false, aliases: [String: String] = [:], fileFonts: Set<String> = [], fromFile: Bool = false,
                                    characterStyles: [String: String] = [:], characterStyleIds: [String: String] = [:]) -> String {
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
            if let fill = entry.paragraph.fill { out += "<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"\(_hex(fill))\"/>" }
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
            if entry.char.underline { out += "<w:u w:val=\"single\"/>" }
            if entry.char.strikethrough { out += "<w:strike/>" }
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
        if characterStyleIds["hyperlink"] == nil, characterStyles["Hyperlink"] == nil {
        out += "<w:style w:type=\"character\" w:styleId=\"Hyperlink\"><w:name w:val=\"Hyperlink\"/><w:rPr><w:color w:val=\"0563C1\"/><w:u w:val=\"single\"/></w:rPr></w:style>"
        }
        // Word's default table style, as Word writes it. Without it Word
        // (in its legacy layout mode) set form_footnotes' tables 5pt to
        // the right of the original's: 12.3% -> 9.9% with it.
        out += "<w:style w:type=\"table\" w:default=\"1\" w:styleId=\"TableNormal\"><w:name w:val=\"Normal Table\"/><w:uiPriority w:val=\"99\"/><w:semiHidden/><w:unhideWhenUsed/><w:tblPr><w:tblInd w:w=\"0\" w:type=\"dxa\"/><w:tblCellMar><w:top w:w=\"0\" w:type=\"dxa\"/><w:left w:w=\"108\" w:type=\"dxa\"/><w:bottom w:w=\"0\" w:type=\"dxa\"/><w:right w:w=\"108\" w:type=\"dxa\"/></w:tblCellMar></w:tblPr></w:style>"
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
    private static func _numberingPart(_ kinds: [Int: ListKind], _ formats: [Int: [Int: ListLevelFormat]],
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
