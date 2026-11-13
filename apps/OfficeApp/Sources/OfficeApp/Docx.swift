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

// MARK: - A small DOM

final class XNode {
    let name: String
    var attrs: [String: String]
    var children: [XNode] = []
    var text = ""
    /// A table laid out right to left (`w:bidiVisual`) is walked as this mirrored copy
    /// (its columns in reverse order); the original is what a save keeps.
    var mirroredFrom: XNode? = nil

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
        if _plainUTF8(bytes), let root = MiniXML.parse(bytes) { return _strictMeasures(root, data) }
        return parseSystem(data).map { _strictMeasures($0, data) }
        #endif
    }

    /// A strict (ISO) WordprocessingML part gives its measures with a unit
    /// ("419.60pt", "2.5cm") where the transitional one gives twips (or
    /// half-points for a size): LibreOffice's tdf82065_Ind_start_strict has
    /// its page, margins and indents so, and they were read as nothing —
    /// the paragraph on a letter page with no indent. Put into twips here,
    /// once, where the part is read.
    private static let _strictTwipAttributes: Set<String> = [
        "w:w", "w:h", "w:top", "w:bottom", "w:left", "w:right", "w:start", "w:end", "w:header", "w:footer", "w:gutter",
        "w:hanging", "w:firstLine", "w:before", "w:after", "w:pos", "w:space", "w:firstLine", "w:tblpX", "w:tblpY",
    ]
    private static func _strictMeasures(_ root: XNode, _ data: Data) -> XNode {
        // A strict chart or drawing part spells its percentages "65%" where
        // the transitional one has 65000 (thousandths): the colour
        // modifiers read nothing from "65%" and left a chart's text and
        // lines black (lo-6e71a4d5: no axis labels, no title, black grid).
        if data.prefix(4096).range(of: Data("purl.oclc.org/ooxml/drawingml".utf8)) != nil {
            func percents(_ n: XNode) {
                for (key, value) in n.attrs where value.hasSuffix("%") && value.count <= 12 {
                    if let v = Double(value.dropLast()) { n.attrs[key] = String(Int((v * 1000).rounded())) }
                }
                for c in n.children { percents(c) }
            }
            percents(root)
        }
        guard data.prefix(4096).range(of: Data("ooxml/wordprocessingml/main".utf8)) != nil,
              data.prefix(4096).range(of: Data("purl.oclc.org".utf8)) != nil else { return root }
        func convert(_ raw: String, per: Double) -> String? {
            let units: [(String, Double)] = [("pt", 1), ("pc", 12), ("pi", 12), ("in", 72), ("cm", 72 / 2.54), ("mm", 72 / 25.4)]
            for (u, k) in units where raw.hasSuffix(u) {
                guard let v = Double(raw.dropLast(u.count)) else { return nil }
                return String(Int((v * k * per).rounded()))
            }
            return nil
        }
        func walk(_ n: XNode) {
            for (key, value) in n.attrs where value.count > 2 {
                if _strictTwipAttributes.contains(key), let t = convert(value, per: 20) { n.attrs[key] = t }
                else if key == "w:sz" || key == "w:szCs", let t = convert(value, per: 2) { n.attrs[key] = t }
            }
            for c in n.children { walk(c) }
        }
        walk(root)
        return root
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

/// The column widths (pt) every row of a table states in twips, when each row is whole
/// single-span dxa cells of one width list; nil otherwise.
@inline(never)
func _statedCellColumns(_ node: XNode, count: Int) -> [Double]? {
    var widths: [Double]? = nil
    for tr in node.all("w:tr") {
        var row: [Double] = []
        for tc in tr.all("w:tc") {
            let w = tc.first("w:tcPr")?.first("w:tcW")
            guard w?["w:type"] == "dxa", let v = Double(w?["w:w"] ?? ""), v > 0, tc.first("w:tcPr")?.first("w:gridSpan") == nil,
                  tr.first("w:trPr")?.first("w:gridBefore") == nil else { return nil }
            row.append(v / 20)
        }
        if row.count != count { return nil }
        if let f = widths { if f != row { return nil } } else { widths = row }
    }
    return widths
}


/// An auto-width table, or one whose stated width (dxa) is the cells' own total: the cells rule.
/// (jpn-z21461406-0d8cbc: tblW 10000 over cells of 2000 / 3500 / 2000 / 2500 and a grid of 100 x 4.)
@inline(never)
func _cellsAgreeWithTableWidth(_ node: XNode, cells: Double) -> Bool {
    let w = node.first("w:tblPr")?.first("w:tblW")
    let type = w?["w:type"] ?? "auto"
    if type == "auto" { return true }
    guard type == "dxa", let v = Double(w?["w:w"] ?? "") else { return false }
    return abs(v / 20 - cells) <= 0.5
}

struct DocxDocument {
    var document: RichDocument
    var pageSetup: PageSetup?
}

enum DocxFormat {
    enum DocxError: Error { case noDocumentPart, badXML(String) }

    // MARK: Reading

    /// A width that is a share of the page's or margins' (`wp14:sizeRelH`,
    /// `pctWidth` in thousandths of a percent) is that share of the section's
    /// page or text area in Word, whatever extent the file also states:
    /// LibreOffice's tdf92724 pull quote says 2360930 EMU (185.9pt) and 40% of
    /// the margins (180.5pt), and Word sets its text in the 166.1pt the share
    /// leaves; ours took the extent's 171.5 and ran a word longer on five of
    /// its lines. The extent is rewritten in the markup, before the drawing is
    /// read, so every reader of it agrees. Each section's own page.
    static func _applyShareWidths(_ root: XNode) {
        guard let body = root.first("w:body") else { return }
        var pending: [XNode] = []
        for child in body.children {
            if child.name == "w:sectPr" { _resolveShareWidths(pending, child); pending = []; continue }
            pending += child.descendants("wp:anchor")
            if child.name == "w:p", let sect = child.first("w:pPr")?.first("w:sectPr") { _resolveShareWidths(pending, sect); pending = [] }
        }
    }

    /// Ids of the footnotes that open a section whose footnotePr says
    /// numRestart eachSect: Word numbers that section's notes from 1 again
    /// (471e57de: the second section's note prints "1", ours "2").
    @inline(never)
    static func _footnoteRestartIDs(_ body: XNode) -> Set<Int> {
        var out: Set<Int> = []
        var first: Int? = nil
        func close(_ sect: XNode?) {
            guard sect != nil else { return }
            if let f = first, sect?.first("w:footnotePr")?.first("w:numRestart")?["w:val"] == "eachSect" { out.insert(f) }
            first = nil
        }
        func walk(_ n: XNode) {
            if n.name == "w:footnoteReference", first == nil, let id = Int(n["w:id"] ?? "") { first = id }
            if n.name == "w:p" {
                for c in n.children where c.name != "w:pPr" { walk(c) }
                close(n.first("w:pPr")?.first("w:sectPr"))
                return
            }
            for c in n.children { walk(c) }
        }
        for c in body.children {
            if c.name == "w:sectPr" { close(c); continue }
            walk(c)
        }
        return out
    }

    /// The share widths of `anchors`, on `sect`'s page. A header's or footer's
    /// are on the last section's (lo-9c6cc479's footer rule, 100% of the margins:
    /// 446.6pt in Word's print, the 468pt extent here).
    static func _resolveShareWidths(_ anchors: [XNode], _ sect: XNode?) {
        guard !anchors.isEmpty, let sect, let sz = sect.first("w:pgSz"), let mar = sect.first("w:pgMar"),
              let w = Double(sz["w:w"] ?? ""), let l = Double(mar["w:left"] ?? ""), let r = Double(mar["w:right"] ?? "") else { return }
        let gutter = Double(mar["w:gutter"] ?? "") ?? 0
        for anchor in anchors {
            guard let rel = anchor.first("wp14:sizeRelH"), let pct = Double(rel.first("wp14:pctWidth")?.text ?? ""), pct > 0,
                  let extent = anchor.first("wp:extent"), let cx = extent["cx"], Double(cx) != nil else { continue }
            let span: Double
            switch rel["relativeFrom"] ?? "" {
            case "margin": span = w - l - r - gutter
            case "page": span = w
            default: continue
            }
            let emu = String(Int((span / 20 * 12700 * pct / 100_000).rounded()))
            extent.attrs["cx"] = emu
            for ext in anchor.descendants("a:ext") where ext["cx"] == cx { ext.attrs["cx"] = emu }
        }
    }

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
                case 0x2D, 0x2013, 0x2012: return total + (c.value == 0x2D ? 0.333 : 0.5)
                case 0x2014: return total + 1
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
                // (A drop cap held in a content control, tdf109308: the control
                // is Word's own bracket round the letter, and the paragraph is
                // a drop cap all the same.)
                if p.name == "w:p", p.first("w:pPr")?.first("w:framePr")?["w:dropCap"] == "drop", p.children.contains(where: { $0.name == "w:sdt" }) {
                    RuleTrace.hit("dropcap-in-content-control")
                    p.children = p.children.flatMap { $0.name == "w:sdt" ? ($0.first("w:sdtContent")?.children ?? []) : [$0] }
                }
                if p.name == "w:p", i + 1 < kids.count, kids[i + 1].name == "w:p",
                   let pPr = p.first("w:pPr"), let frame = pPr.first("w:framePr"), ["drop", "margin"].contains(frame["w:dropCap"] ?? ""),
                   let lines = Double(frame["w:lines"] ?? ""), lines >= 2,
                   let spacing = pPr.first("w:spacing"), spacing["w:lineRule"] == "exact", let line = Double(spacing["w:line"] ?? ""), line > 0,
                   // (More than one run is one cap word where they are all of one look:
                   // tdf109316_dropCaps' "L" and "liquam", 77pt.)
                   p.children.filter({ $0.name != "w:pPr" && $0.name != "w:r" }).isEmpty,
                   case let capRuns = p.children.filter({ $0.name == "w:r" }), !capRuns.isEmpty,
                   capRuns.allSatisfy({ r in r.children.filter { $0.name != "w:rPr" && $0.name != "w:t" }.isEmpty && r.all("w:t").count == 1
                       && r.first("w:rPr").map(PptxXML.serialize) == capRuns[0].first("w:rPr").map(PptxXML.serialize) }),
                   let run = capRuns.first, case let capText = capRuns.compactMap({ $0.first("w:t")?.text }).joined(), !capText.isEmpty,
                   case let host = kids[i + 1], host.first("w:pPr")?.first("w:framePr") == nil {
                    let height = line / 20                      // points: the lines' height
                    let pitch = height / lines
                    // (Word's size: the lines above the last, over the face's
                    // cap height, and the text's own cap height on top.)
                    let capHeight = 0.655
                    var hostSize = 11.0
                    if let r = host.children.first(where: { $0.name == "w:r" }),
                       let sz = r.first("w:rPr")?.first("w:sz")?["w:val"].flatMap(Double.init) { hostSize = sz / 2 }
                    // (The cap run's own size wins: lo tdf150200's dash caps say
                    // 130 and 137.5pt, and Word's print has them so; the lines'
                    // size is for a cap that names none.)
                    let ownSize = run.first("w:rPr")?.first("w:sz")?["w:val"].flatMap(Double.init).map { $0 / 2 }
                    let size = ownSize ?? hostSize + (lines - 1) * pitch / capHeight
                    let capWidth = em(capText) * size
                    let halfPoints = Int((size * 2).rounded())
                    // (Word for Windows sets a cap that names its own size a point lower: lab dropcap, hyphen,
                    // en dash, figure dash and "L" at 130 and 137.5pt, and a hyphen at 50 and 80, a 39.9pt exact
                    // line raised -5.5pt — every baseline 37.58 from the paragraph's top where this had 36.6.)
                    let lowered = DocxFormat.wordOnWindows && ownSize != nil
                    if lowered { RuleTrace.hit("dropcap-with-its-own-size-sits-a-point-lower") }
                    let baseline = height - 0.25 * pitch + (lowered ? 1.0 : 0)        // the last line's baseline, from the box's top
                    let exact = Int((baseline / 0.8 * 20).rounded())
                    let rPrInner = (run.first("w:rPr")?.children ?? []).filter { $0.name != "w:sz" && $0.name != "w:szCs" && !(ownSize != nil && $0.name == "w:position") }
                        .map { PptxXML.serialize($0) }.joined()
                    let esc = capText.replacingAll("&", with: "&amp;").replacingAll("<", with: "&lt;")
                    // (A drop "in the margin" hangs outside the column, its right
                    // edge a space short of it, no text beside it: lo
                    // tdf109316_dropCaps' "I", 3 lines of 41pt, stands at x 23
                    // in a column from 57 in Word's print.)
                    let inMargin = frame["w:dropCap"] == "margin"
                    let marginWidth = capText.unicodeScalars.reduce(0.0) { $0 + ($1.value == 0x49 ? 0.333 : em(String($1))) } * size
                    let emu = Int(height * 12700)
                    // (One capital letter in Times is its own advance wide: tdf109308's "L" at 57.5pt, 35.1.)
                    let timesCaps: [Double] = [0.722, 0.667, 0.667, 0.722, 0.611, 0.556, 0.722, 0.722, 0.333, 0.389, 0.722, 0.611, 0.889, 0.722, 0.722, 0.556, 0.722, 0.667, 0.556, 0.611, 0.722, 0.722, 0.944, 0.722, 0.722, 0.611]
                    let exactCap: Double? = capText.unicodeScalars.count == 1 && (0x41...0x5A).contains(capText.unicodeScalars.first!.value)
                        ? timesCaps[Int(capText.unicodeScalars.first!.value) - 0x41] * size : nil
                    if exactCap != nil { RuleTrace.hit("dropcap-box-is-the-capital-wide") }
                    let emuW = exactCap.map { Int($0 * 12700) } ?? max(emu, Int(capWidth * (capText.count > 1 ? 1.05 : 1.5) * 12700))   // (room for the cap's own width: the box takes the text's, no more than its extent)
                    let ns = "xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" xmlns:wp=\"http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:wps=\"http://schemas.microsoft.com/office/word/2010/wordprocessingShape\""
                    let hSpacePoints: Double = (Double(frame["w:hSpace"] ?? "") ?? 0) / 20
                    let distRight: Int = Int(hSpacePoints * 12700)
                    let xml = "<w:r \(ns)><w:drawing><wp:anchor distT=\"0\" distB=\"0\" distL=\"0\" distR=\"\(distRight)\" simplePos=\"0\" relativeHeight=\"0\" behindDoc=\"0\" locked=\"0\" layoutInCell=\"1\" allowOverlap=\"1\"><wp:simplePos x=\"0\" y=\"0\"/><wp:positionH relativeFrom=\"column\"><wp:posOffset>\(inMargin ? -Int((marginWidth + hSpacePoints) * 12700) : 0)</wp:posOffset></wp:positionH><wp:positionV relativeFrom=\"paragraph\"><wp:posOffset>0</wp:posOffset></wp:positionV><wp:extent cx=\"\(emuW)\" cy=\"\(emu)\"/><wp:effectExtent l=\"0\" t=\"0\" r=\"0\" b=\"0\"/><wp:wrapSquare wrapText=\"bothSides\"/><wp:docPr id=\"1\" name=\"Drop cap\"/><wp:cNvGraphicFramePr/><a:graphic><a:graphicData uri=\"http://schemas.microsoft.com/office/word/2010/wordprocessingShape\"><wps:wsp><wps:cNvSpPr txBox=\"1\"/><wps:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"\(emuW)\" cy=\"\(emu)\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom><a:noFill/><a:ln><a:noFill/></a:ln></wps:spPr><wps:txbx><w:txbxContent><w:p><w:pPr><w:spacing w:before=\"0\" w:after=\"0\" w:line=\"\(exact)\" w:lineRule=\"exact\"/></w:pPr><w:r><w:rPr>\(rPrInner)<w:sz w:val=\"\(halfPoints)\"/><w:szCs w:val=\"\(halfPoints)\"/></w:rPr><w:t xml:space=\"preserve\">\(esc)</w:t></w:r></w:p></w:txbxContent></wps:txbx><wps:bodyPr wrap=\"none\" lIns=\"0\" tIns=\"0\" rIns=\"0\" bIns=\"0\" anchor=\"t\"><a:spAutoFit/></wps:bodyPr></wps:wsp></a:graphicData></a:graphic></wp:anchor></w:drawing></w:r>"
                    if let drawing = XNode.parse(Data(xml.utf8)) {
                        let at = host.children.firstIndex(where: { $0.name != "w:pPr" }) ?? host.children.count
                        host.children.insert(drawing, at: at)
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

    /// Word's text frames. A run of paragraphs holding one `w:framePr` that is
    /// anchored to the text (`w:vAnchor="text"`), with a width, a height and a
    /// place below its paragraph (`w:y`), is a box that stands there and has
    /// the paragraph after it set round it (`w:wrap` "around") or clear of it
    /// ("notBeside"): an anchored text box. Here it is written into the
    /// paragraph after the run as one — read as any anchored text box, and
    /// laid out beside it by the layout's wrapping — and the frame's own
    /// paragraphs go. (lo tdf133924: Word's print sets "Around" 71pt and
    /// "notBeside" 273pt under the text's top, the text round the one and over
    /// and under the other; ours set both frames before the text.)
    /// A table whose every cell paragraph carries the one frame, of the text's
    /// anchor and "auto" wrap, an offset down and nothing else: Word floats it as
    /// a table placed by the text, `w:tblpY` down from the paragraph after it,
    /// and sets that text first, at the top (LibreOffice's tdf164474: "Some text"
    /// at 30.5 over the table's row at 59.4; ours set the row first and the text
    /// under it). The frame is written as the table's own floating position, and
    /// taken off the paragraphs (the table's, and the one after it that carries
    /// the same frame).
    static func _floatFramedTables(_ root: XNode) {
        guard let body = root.first("w:body") else { return }
        func cellParagraphs(_ tbl: XNode) -> [XNode] {
            tbl.all("w:tr").flatMap { $0.all("w:tc") }.flatMap { $0.all("w:p") }
        }
        var i = 0
        while i < body.children.count {
            defer { i += 1 }
            let tbl = body.children[i]
            guard tbl.name == "w:tbl", let pr = tbl.first("w:tblPr"), pr.first("w:tblpPr") == nil else { continue }
            let paragraphs = cellParagraphs(tbl)
            guard !paragraphs.isEmpty else { continue }
            let frames = paragraphs.map { $0.first("w:pPr")?.first("w:framePr") }
            guard let frame = frames[0], frames.allSatisfy({ $0 != nil }),
                  Set(frames.map { PptxXML.serialize($0!) }).count == 1,
                  frame["w:vAnchor"] == nil || frame["w:vAnchor"] == "text",
                  frame["w:hAnchor"] == nil || frame["w:hAnchor"] == "text",
                  frame["w:wrap"] == nil || frame["w:wrap"] == "auto" || frame["w:wrap"] == "around",
                  frame["w:x"] == nil, frame["w:xAlign"] == nil, frame["w:yAlign"] == nil, frame["w:w"] == nil, frame["w:h"] == nil,
                  frame["w:dropCap"] == nil, let y = Int(frame["w:y"] ?? ""), y > 0 else { continue }
            let signature = PptxXML.serialize(frame)
            for p in paragraphs { p.first("w:pPr")?.children.removeAll { $0.name == "w:framePr" } }
            if i + 1 < body.children.count, body.children[i + 1].name == "w:p",
               let f = body.children[i + 1].first("w:pPr")?.first("w:framePr"), PptxXML.serialize(f) == signature {
                body.children[i + 1].first("w:pPr")?.children.removeAll { $0.name == "w:framePr" }
            }
            let pos = XNode(name: "w:tblpPr", attrs: ["w:vertAnchor": "text", "w:horzAnchor": "text", "w:tblpY": String(y)])
            pr.children.insert(pos, at: 0)
        }
    }

    static func _foldFrames(_ root: XNode) {
        // (A frame whose text runs turned, `w:textDirection` btLr or tbRl, on
        // the page or margin: a box of the size it says, the text in it
        // turned, where the layout set it across a narrow column — lo
        // frame-direction's two 44pt-wide frames, 820pt tall, and
        // tdf154703_framePrTextDirection's 21.6 by 116 one centred on the page.)
        func turned(_ p: XNode) -> String? {
            guard let d = p.first("w:pPr")?.first("w:textDirection")?["w:val"] else { return nil }
            return ["btLr": "vert270", "tbRl": "vert"][d]
        }
        func frameOf(_ p: XNode) -> XNode? {
            if p.name == "w:p", let f = p.first("w:pPr")?.first("w:framePr"), f["w:dropCap"] == nil, turned(p) != nil || f["w:yAlign"] != nil,
               ["page", "margin"].contains(f["w:vAnchor"] ?? ""), Double(f["w:w"] ?? "").map({ $0 > 0 }) == true,
               Double(f["w:h"] ?? "").map({ $0 > 0 }) == true, f["w:y"] != nil || f["w:yAlign"] != nil,
               f["w:wrap"] == "around", p.descendant("w:ins") == nil, p.descendant("w:del") == nil { return f }
            // (A frame of no stated size, set by the text at the page's outer or inner
            // edge: a page-margin note, LibreOffice's CT-with-frame "0123" — in Word's
            // print it stands at the right of the page, level with the next paragraph's
            // top, in the margin beside no text, and that paragraph keeps its place; ours
            // set it as a line of the text and the paragraph under it, 11pt low.)
            if p.name == "w:p", let f = p.first("w:pPr")?.first("w:framePr"), f["w:dropCap"] == nil, f["w:w"] == nil, f["w:h"] == nil,
               f["w:vAnchor"] == "text", f["w:hAnchor"] == "page", f["w:xAlign"] == "outside" || f["w:xAlign"] == "inside",
               f["w:wrap"] == "around", f["w:y"] != nil, f["w:yAlign"] == nil, p.descendant("w:ins") == nil, p.descendant("w:del") == nil { return f }
            // (A frame of no stated size that text does not go round, set at the
            // margin's right edge: a page number in LibreOffice's sdt+framePr —
            // Word's print has its "1" at the right margin on the next paragraph's
            // line, taking no line of its own; ours set it at the left on a line
            // of its own and pushed the text down.)
            if p.name == "w:p", let f = p.first("w:pPr")?.first("w:framePr"), f["w:dropCap"] == nil, f["w:w"] == nil, f["w:h"] == nil,
               f["w:vAnchor"] == "text", f["w:hAnchor"] == "margin", f["w:xAlign"] == "right",
               f["w:wrap"] == "none", f["w:y"] != nil, f["w:yAlign"] == nil, p.descendant("w:ins") == nil, p.descendant("w:del") == nil { return f }
            // (A frame of no stated size, at an x on the page beside the text: its
            // box stands at that x whatever column the text is in, as wide as the
            // column — LibreOffice's tdf135035, in a column section of three.)
            if p.name == "w:p", let f = p.first("w:pPr")?.first("w:framePr"), f["w:dropCap"] == nil, f["w:w"] == nil, f["w:h"] == nil,
               f["w:vAnchor"] == "text", f["w:hAnchor"] == "page", f["w:xAlign"] == nil, Double(f["w:x"] ?? "") != nil,
               f["w:wrap"] == "around", f["w:y"] != nil, f["w:yAlign"] == nil, p.descendant("w:ins") == nil, p.descendant("w:del") == nil { return f }
            guard p.name == "w:p", let f = p.first("w:pPr")?.first("w:framePr"), f["w:dropCap"] == nil,
                  f["w:vAnchor"] == "text", Double(f["w:w"] ?? "").map({ $0 > 0 }) == true,
                  Double(f["w:h"] ?? "").map({ $0 > 0 }) == true, f["w:y"] != nil, f["w:yAlign"] == nil,
                  f["w:wrap"] == "around" || f["w:wrap"] == "notBeside" else { return nil }
            // (Not a frame whose text is tracked: lo tdf125894's inserted and deleted
            // paragraphs stand in Word's print as one line from the margin, not in
            // the frame's width. And "notBeside" only among frames that text goes
            // round, below: one set at the foot of a paragraph's own line —
            // tdf105035_framePrC's, 28pt down — is set right by the flow's own
            // offset; it is the frames that text goes round that the flow gets
            // wrong, and the ones set beside them tdf133924's.)
            if p.descendant("w:ins") != nil || p.descendant("w:del") != nil { return nil }
            return f
        }
        func signature(_ f: XNode) -> String { PptxXML.serialize(f) }
        guard let body = root.first("w:body") else { return }
        // (A one-cell table whose paragraph carries the frame its neighbours carry is part
        // of that frame: lo fdo60957-2's "G", between the frame's "F" and "H", is set in the
        // frame at x 317 in Word's print; ours left the table in the body at x 65. Set as
        // the frame's paragraph, which loses the table's rules and shading.)
        if RichTextTheme.wordWindowsPages {
            func sig(_ n: XNode?) -> String? { n?.name == "w:p" ? n?.first("w:pPr")?.first("w:framePr").map { signature($0) } : nil }
            for (k, n) in body.children.enumerated() where n.name == "w:tbl" && k > 0 && k + 1 < body.children.count {
                let rows = n.children.filter { $0.name == "w:tr" }
                guard rows.count == 1, case let cells = rows[0].children.filter({ $0.name == "w:tc" }), cells.count == 1,
                      case let ps = cells[0].children.filter({ $0.name == "w:p" }), ps.count == 1,
                      cells[0].children.filter({ $0.name == "w:tbl" }).isEmpty,
                      let mine = sig(ps[0]), sig(body.children[k - 1]) == mine, sig(body.children[k + 1]) == mine else { continue }
                RuleTrace.hit("docx-one-cell-table-in-a-frame-is-the-frame's-paragraph")
                body.children[k] = ps[0]
            }
        }
        // (A framed page number in a content control, LibreOffice's sdt+framePr: the
        // control brackets the paragraph and is no part of its frame.)
        body.children = body.children.flatMap { n -> [XNode] in
            guard n.name == "w:sdt", let content = n.first("w:sdtContent"), !content.children.isEmpty,
                  content.children.allSatisfy({ $0.name == "w:p" && frameOf($0)?["w:wrap"] == "none" }) else { return [n] }
            RuleTrace.hit("docx-frame-in-content-control")
            return content.children
        }
        var out: [XNode] = []
        let kids = body.children
        var i = 0
        while i < kids.count {
            guard frameOf(kids[i]) != nil else { out.append(kids[i]); i += 1; continue }
            // (Every run of frames before one paragraph is anchored to it: runs of
            // paragraphs of one frame, one after another.)
            var runs: [(frame: XNode, range: Range<Int>)] = []
            var j = i
            while j < kids.count, let frame = frameOf(kids[j]) {
                var k = j
                while k < kids.count, let f = frameOf(kids[k]), signature(f) == signature(frame) { k += 1 }
                runs.append((frame, j ..< k)); j = k
            }
            // (A bookmark's end between the frame and its paragraph is no paragraph: LibreOffice's
            // tdf107119, "This is a frame" and the text round it, has one.)
            var h = j
            while h < kids.count, kids[h].name == "w:bookmarkStart" || kids[h].name == "w:bookmarkEnd" { h += 1 }
            guard runs.contains(where: { $0.frame["w:wrap"] == "around" || $0.frame["w:wrap"] == "none" }),
                  h < kids.count, kids[h].name == "w:p", kids[h].first("w:pPr")?.first("w:framePr") == nil else {
                out.append(contentsOf: kids[i ..< j]); i = j; continue
            }
            let host = kids[h]
            var drawings: [XNode] = []
            var kept: [XNode] = []
            for (frame, range) in runs {
                var w = Int((Double(frame["w:w"] ?? "") ?? 0) * 635), h = Int((Double(frame["w:h"] ?? "") ?? 0) * 635)
                let sizedByColumn = w == 0 && h == 0 && frame["w:hAnchor"] == "page" && frame["w:x"] != nil && frame["w:xAlign"] == nil
                    && frame["w:vAnchor"] == "text" && kids[range.lowerBound].descendant("w:t") != nil
                var columnPoints = 0.0
                if sizedByColumn {
                    // (The column the section sets: the page less its margins, less the
                    // gaps, over the columns — the section that ends at or after the frame.)
                    var sect: XNode? = nil
                    var q = range.lowerBound
                    while q < kids.count, sect == nil { sect = kids[q].first("w:pPr")?.first("w:sectPr") ?? (kids[q].name == "w:sectPr" ? kids[q] : nil); q += 1 }
                    if let sect, let size = sect.first("w:pgSz"), let mar = sect.first("w:pgMar"),
                       let pw = Double(size["w:w"] ?? ""), let l = Double(mar["w:left"] ?? ""), let r = Double(mar["w:right"] ?? "") {
                        let n = max(1, Double(sect.first("w:cols")?["w:num"] ?? "") ?? 1)
                        let gap = Double(sect.first("w:cols")?["w:space"] ?? "") ?? 720
                        columnPoints = ((pw - l - r - gap * (n - 1)) / n) / 20
                    }
                }
                if sizedByColumn, columnPoints > 0 {
                    // (Its lines wrap at the column, its borders outside the text.)
                    RuleTrace.hit("docx-frame-without-size-is-a-column-wide-box")
                    w = Int((columnPoints + 3.5) * 12700); h = Int(14 * 12700)
                } else if w == 0, h == 0 {
                    // (Sized by its text: the characters at the run's size, and the exact line.)
                    let pPr = kids[range.lowerBound].first("w:pPr")
                    let chars = kids[range.lowerBound].descendants("w:t").reduce(0) { $0 + ($1.text.count) }
                    let size = (Double(kids[range.lowerBound].descendant("w:sz")?["w:val"] ?? "") ?? 20) / 2
                    let line = pPr?.first("w:spacing").flatMap { $0["w:lineRule"] == "exact" ? Double($0["w:line"] ?? "") : nil }.map { $0 / 20 } ?? size * 1.2
                    w = Int(Double(max(1, chars)) * size * 0.6 * 12700); h = Int(line * 12700)
                }
                let y = Int((Double(frame["w:y"] ?? "") ?? 0) * 635)
                let direction = turned(kids[range.lowerBound])
                // (Or aligned on the page, text not turned: lo tdf36117_verticalAdjustment's
                // 116pt by 450pt frame, centred on the page at x 360, which the
                // body goes round in Word's print and the layout sets in the flow.)
                let onPage = ["page", "margin"].contains(frame["w:vAnchor"] ?? "")
                let relV = onPage ? (frame["w:vAnchor"] ?? "page") : "paragraph"
                let vertical = onPage && frame["w:yAlign"] != nil && frame["w:yAlign"] != "inline"
                    ? "<wp:align>\(frame["w:yAlign"]!)</wp:align>" : "<wp:posOffset>\(y)</wp:posOffset>"
                // (A border on a side of the frame takes its `w:space` and twice its
                // width, and a little more, off the room beside it, on top of
                // `w:hSpace`: lab fr2 (Word for Windows, tdf154703's frame,
                // sz 6 / 12 and space 7 / 14 over hSpace 0, 1000 and 2552) ends
                // the lines 9.1, 11.0 and 16.2pt short of where hSpace alone puts
                // them: space + 2 x width + 0.6.)
                func borderGive(_ side: String) -> Double {
                    guard let b = kids[range.lowerBound].first("w:pPr")?.first("w:pBdr")?.first(side), (b["w:val"] ?? "none") != "none",
                          (b["w:val"] ?? "nil") != "nil" else { return 0 }
                    return (Double(b["w:space"] ?? "") ?? 0) + 2 * (Double(b["w:sz"] ?? "") ?? 0) / 8 + 0.6
                }
                let hSpaceL = Int(((Double(frame["w:hSpace"] ?? "") ?? 0) / 20 + borderGive("w:left")) * 12700)
                let hSpaceR = Int(((Double(frame["w:hSpace"] ?? "") ?? 0) / 20 + borderGive("w:right")) * 12700)
                let vSpace = Int((Double(frame["w:vSpace"] ?? "") ?? 0) * 635)
                let relH = ["page": "page", "margin": "margin"][frame["w:hAnchor"] ?? ""] ?? "column"
                let horizontal: String
                if let a = frame["w:xAlign"] { horizontal = "<wp:align>\(a)</wp:align>" }
                else {
                    // (The text, not its border, is at the x.)
                    let inset = 0.0
                    horizontal = "<wp:posOffset>\(Int(((Double(frame["w:x"] ?? "") ?? 0) / 20 - inset) * 12700))</wp:posOffset>"
                }
                let wrap = frame["w:wrap"] == "none" ? "<wp:wrapNone/>" : frame["w:wrap"] == "notBeside" ? "<wp:wrapTopAndBottom/>" : "<wp:wrapSquare wrapText=\"bothSides\"/>"
                let ns = "xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" xmlns:wp=\"http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:wps=\"http://schemas.microsoft.com/office/word/2010/wordprocessingShape\""
                let xml = "<w:r \(ns)><w:drawing><wp:anchor distT=\"\(vSpace)\" distB=\"\(vSpace)\" distL=\"\(hSpaceL)\" distR=\"\(hSpaceR)\" simplePos=\"0\" relativeHeight=\"0\" behindDoc=\"0\" locked=\"0\" layoutInCell=\"1\" allowOverlap=\"1\"><wp:simplePos x=\"0\" y=\"0\"/><wp:positionH relativeFrom=\"\(relH)\">\(horizontal)</wp:positionH><wp:positionV relativeFrom=\"\(relV)\">\(vertical)</wp:positionV><wp:extent cx=\"\(w)\" cy=\"\(h)\"/><wp:effectExtent l=\"0\" t=\"0\" r=\"0\" b=\"0\"/>\(wrap)<wp:docPr id=\"1\" name=\"Frame\"/><wp:cNvGraphicFramePr/><a:graphic><a:graphicData uri=\"http://schemas.microsoft.com/office/word/2010/wordprocessingShape\"><wps:wsp><wps:cNvSpPr txBox=\"1\"/><wps:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"\(w)\" cy=\"\(h)\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom><a:noFill/><a:ln><a:noFill/></a:ln></wps:spPr><wps:txbx><w:txbxContent/></wps:txbx><wps:bodyPr wrap=\"square\"\(direction.map { " vert=\"\($0)\"" } ?? "") lIns=\"0\" tIns=\"0\" rIns=\"0\" bIns=\"0\" anchor=\"t\">\(sizedByColumn && columnPoints > 0 ? "<a:spAutoFit/>" : "<a:noAutofit/>")</wps:bodyPr></wps:wsp></a:graphicData></a:graphic></wp:anchor></w:drawing></w:r>"
                guard let drawing = XNode.parse(Data(xml.utf8)), let content = drawing.descendant("w:txbxContent") else {
                    kept.append(contentsOf: kids[range]); continue
                }
                for k in range {
                    let p = kids[k]
                    p.first("w:pPr")?.children.removeAll { $0.name == "w:framePr" || (direction != nil && $0.name == "w:textDirection") }
                    content.children.append(p)
                }
                // (A lone empty paragraph with a border, in a frame of stated height: Word
                // draws the box the frame's height, and an empty paragraph here is no
                // taller than a line, or nothing at all: lo-dd3d953e. A line of the frame's
                // height makes the box that tall.)
                if range.count == 1, let p = content.children.first, p.descendant("w:r") == nil,
                   let pPr = p.first("w:pPr"), pPr.first("w:pBdr") != nil, pPr.first("w:spacing") == nil,
                   let fh = Double(frame["w:h"] ?? ""), fh > 0, frame["w:hRule"] != "auto" {
                    // (The box is the line plus each side's width and space, so they come off it;
                    // and a paragraph with no run paints no border in a text box, so it gets a space.)
                    func give(_ side: String) -> Double {
                        guard let b = pPr.first("w:pBdr")?.first(side), (b["w:val"] ?? "none") != "none", (b["w:val"] ?? "nil") != "nil" else { return 0 }
                        return (Double(b["w:space"] ?? "") ?? 0) + (Double(b["w:sz"] ?? "") ?? 0) / 8
                    }
                    let line = Int(max(20, fh - 20 * (give("w:top") + give("w:bottom"))))
                    let w = "xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\""
                    if let sp = XNode.parse(Data("<w:spacing \(w) w:line=\"\(line)\" w:lineRule=\"exact\" w:before=\"0\" w:after=\"0\"/>".utf8)),
                       let run = XNode.parse(Data("<w:r \(w)><w:t xml:space=\"preserve\"> </w:t></w:r>".utf8)) {
                        pPr.children.append(sp)
                        p.children.append(run)
                    }
                }
                drawings.append(drawing)
            }
            out.append(contentsOf: kept)
            out.append(contentsOf: kids[j ..< h])
            var at = host.children.firstIndex(where: { $0.name != "w:pPr" }) ?? host.children.count
            for d in drawings { host.children.insert(d, at: at); at += 1 }
            out.append(host)
            i = h + 1
        }
        body.children = out
    }

    /// The chart a drawing is itself: its `c:chart` outside any text box's content
    /// and outside an alternate content's fallback. A chart in a text box's
    /// paragraph is that paragraph's inline object (the text box is the drawing, its
    /// insets and all), and the fallback holds the same chart again: lo fdo78474's
    /// chart drew over the whole frame and chart-size's twice.
    static func _ownChartRid(_ node: XNode) -> String? {
        for child in node.children {
            if child.name == "w:txbxContent" || child.name == "mc:Fallback" { continue }
            if child.name == "c:chart", let rid = child["r:id"] { return rid }
            if let found = _ownChartRid(child) { return found }
        }
        return nil
    }

    /// A section break whose paragraph mark stands while a field's CODE is still open — the field has begun and
    /// not yet separated — is not one: Word keeps the text running, lo-8928a1e9's IF fields wrapped round two of
    /// them, 1 page in its print where ours had 3. (One in a field's result stands: lo-9bb072ca's continuous
    /// breaks inside fields keep their sections.) The break is taken out of the markup, before anything reads
    /// the sections.
    static func _dropSectionBreaksInsideFields(_ root: XNode) {
        guard let body = root.first("w:body") else { return }
        var open: [Bool] = []   // each open field: still in its code
        for p in body.descendants("w:p") {
            for mark in p.descendants("w:fldChar") {
                switch mark["w:fldCharType"] {
                case "begin": open.append(true)
                case "separate": if !open.isEmpty { open[open.count - 1] = false }
                case "end": if !open.isEmpty { open.removeLast() }
                default: break
                }
            }
            if open.contains(true), let pPr = p.first("w:pPr"), let at = pPr.children.firstIndex(where: { $0.name == "w:sectPr" }) {
                RuleTrace.hit("section-break-inside-a-field-code-is-ignored")
                pPr.children.remove(at: at)
            }
        }
    }

    /// An IF field that spans body blocks (paragraphs, tables) and shows nothing: Word works out the condition and
    /// shows the true or the false text; when that text is empty, everything the field wraps is gone, the table
    /// inside it too (lo-8928a1e9: `IF ="BASEDMAFAC" "Garantie` + a table + `"""` has no left operand, so the
    /// comparison is false and the false text is empty; 1 page and no table in Word's print). Only a top-level IF
    /// with literal operands whose code never separates; a nested field or any text inside a string counts as
    /// something shown, so a field that might show something stays as it is.
    static func _hideEmptyIfFields(_ root: XNode) {
        guard let body = root.first("w:body") else { return }
        func evaluate(_ code: String) -> Bool? {   // true = the field shows nothing
            let c = Array(code)
            var i = 0
            func skip() { while i < c.count, c[i] == " " || c[i] == "\n" || c[i] == "\t" { i += 1 } }
            func quoted() -> String? {
                guard i < c.count, c[i] == "\"" else { return nil }
                i += 1
                var out = ""
                while i < c.count, c[i] != "\"" { out.append(c[i]); i += 1 }
                guard i < c.count else { return nil }
                i += 1
                return out
            }
            let ops: Set<Character> = ["=", "<", ">"]
            func operand() -> String? {
                skip()
                if let q = quoted() { return q }
                var out = ""
                while i < c.count, c[i] != " ", !ops.contains(c[i]), c[i] != "\"" { out.append(c[i]); i += 1 }
                return out
            }
            skip()
            guard i + 2 <= c.count, String(c[i ..< i + 2]).uppercased() == "IF" else { return nil }
            i += 2
            guard let left = operand() else { return nil }
            skip()
            var op = ""
            while i < c.count, ops.contains(c[i]) { op.append(c[i]); i += 1 }
            guard ["=", "<>", "<", ">", "<=", ">="].contains(op), let right = operand() else { return nil }
            skip()
            guard let yes = quoted() else { return nil }
            skip()
            let no = i < c.count ? quoted() : ""
            guard let no else { return nil }
            let marker: Character = "\u{1}"
            guard !left.contains(marker), !right.contains(marker) else { return nil }
            let cmp: Bool
            if let a = Double(left), let b = Double(right) {
                switch op { case "=": cmp = a == b; case "<>": cmp = a != b; case "<": cmp = a < b; case ">": cmp = a > b; case "<=": cmp = a <= b; default: cmp = a >= b }
            } else {
                let a = left.lowercased(), b = right.lowercased()
                switch op { case "=": cmp = a == b; case "<>": cmp = a != b; case "<": cmp = a < b; case ">": cmp = a > b; case "<=": cmp = a <= b; default: cmp = a >= b }
            }
            return (cmp ? yes : no).isEmpty
        }
        var depth = 0
        var begin: (block: Int, run: XNode)?
        var code = ""
        var separated = false
        var found: [(from: (block: Int, run: XNode), to: (block: Int, run: XNode))] = []
        for (bi, block) in body.children.enumerated() {
            if block.name == "w:tbl" { if depth == 1 { code += "\u{1}" }; continue }
            guard block.name == "w:p" else { continue }
            for run in block.children where run.name == "w:r" {
                for c in run.children {
                    if c.name == "w:fldChar" {
                        switch c["w:fldCharType"] {
                        case "begin":
                            depth += 1
                            if depth == 1 { begin = (bi, run); code = ""; separated = false } else if depth == 2 { code += "\u{1}" }
                        case "separate": if depth == 1 { separated = true }
                        case "end":
                            if depth == 1, let b = begin, !separated, b.block != bi, evaluate(code) == true { found.append((b, (bi, run))) }
                            depth = max(0, depth - 1)
                        default: break
                        }
                    } else if depth == 1, !separated {
                        if c.name == "w:instrText" { code += c.text }
                        else if c.name == "w:t" || c.name == "w:drawing" || c.name == "w:tab" || c.name == "w:br" { code += "\u{1}" }
                    }
                }
            }
            if depth == 1, !separated { code += "\u{1}" }   // (a paragraph mark inside the code is text too)
        }
        // Back to front, so the indexes of the earlier fields stay true.
        for (from, to) in found.reversed() {
            guard let first = body.children[from.block...].first, let last = body.children.indices.contains(to.block) ? body.children[to.block] : nil,
                  first.name == "w:p", last.name == "w:p",
                  let a = first.children.firstIndex(where: { $0 === from.run }), let z = last.children.firstIndex(where: { $0 === to.run }) else { continue }
            RuleTrace.hit("empty-if-field-hides-what-it-wraps")
            let head = Array(first.children[..<a].filter { $0.name != "w:pPr" })
            let tail = Array(last.children[(z + 1)...])
            last.children = last.children.filter { $0.name == "w:pPr" } + head + tail
            body.children.removeSubrange(from.block ..< to.block)
        }
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
        _hoistTablesOutOfParagraphs(root)
        _dropSectionBreaksInsideFields(root)
        _hideEmptyIfFields(root)
        _renumberSequences(root)
        _refreshReferences(root)
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
        Self._foldFrames(root)
        Self._floatFramedTables(root)
        // A Word document as an alt-chunk: its blocks stand where the chunk
        // does, and its section breaks with them, on paper of Word's default
        // (Letter, an inch all round) whatever the chunk's own pgSz says;
        // its closing section is the outer document's. (lo alt-chunk: Word
        // prints "inner doc, first para" under the outer text on a Letter
        // page and "inner doc, last para" on the A4 page after it; the chunk
        // is read before the section breaks are told how the next starts.)
        for (i, node) in body.children.enumerated().reversed() where node.name == "w:altChunk" {
            guard let id = node["r:id"], let rel = relInfo[id], !rel.external, rel.target.lowercased().hasSuffix(".docx"),
                  let data = part(_resolvePath("word", rel.target)), let inner = Self._innerBody(data) else { continue }
            RuleTrace.hit("docx-alt-chunk-is-blocks")
            let blocks = inner.children.filter { $0.name != "w:sectPr" }
            for sect in blocks.flatMap({ $0.descendants("w:sectPr") }) {
                sect.children.removeAll { $0.name == "w:pgSz" || $0.name == "w:pgMar" }
                sect.children.insert(XNode(name: "w:pgSz", attrs: ["w:w": "12240", "w:h": "15840"]), at: 0)
                sect.children.insert(XNode(name: "w:pgMar", attrs: ["w:top": "1440", "w:right": "1440", "w:bottom": "1440", "w:left": "1440", "w:header": "720", "w:footer": "720", "w:gutter": "0"]), at: 1)
            }
            body.children.replaceSubrange(i ... i, with: blocks)
        }
        Self._applyShareWidths(root)
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
                func vertical(_ s: XNode) -> String { "\(s.first("w:pgMar")?["w:top"] ?? "")/\(s.first("w:pgMar")?["w:bottom"] ?? "")" }
                if !breaks, vertical(next) != vertical(sect) { sect.attrs["x-next-vmargins"] = "1" }
            }
        }
        // (A section of columns that a continuous section follows, and that has
        // no paragraph of its own after it: the body ends on the paragraph that
        // closes the columns. Word has a last paragraph mark there all the same,
        // and the columns are balanced above it: LibreOffice's tdf103931, six
        // lines of text in three columns of two in Word's print, in one column
        // in ours, which had no paragraph for the break to be at.)
        if let last = body.children.last, last.name == "w:sectPr", (last.first("w:type")?["w:val"] ?? "") == "continuous",
           body.children.count >= 2, case let before = body.children[body.children.count - 2], before.name == "w:p",
           let closing = before.first("w:pPr")?.first("w:sectPr"), Int(closing.first("w:cols")?["w:num"] ?? "") ?? 1 > 1,
           closing.first("w:pgSz")?["w:w"] == last.first("w:pgSz")?["w:w"], closing.first("w:pgSz")?["w:h"] == last.first("w:pgSz")?["w:h"] {
            RuleTrace.hit("docx-last-paragraph-after-the-columns")
            body.children.insert(XNode(name: "w:p", attrs: [:]), at: body.children.count - 1)
        }
        for extra in root.all("w:body").dropFirst() {
            let at = body.children.lastIndex { $0.name == "w:sectPr" } ?? body.children.count
            body.children.insert(contentsOf: extra.children.filter { $0.name != "w:sectPr" }, at: at)
        }
        _reuseInlinePlaceholders(body)
        _bindCoreProperties(body, part: part)
        let notes = _Shared(kept: kept, rels: relInfo, rootNS: rootNS, part: part, contentType: contentType)
        notes.footnoteRestarts = Self._footnoteRestartIDs(body)
        notes.bookmarkNames = Set(body.descendants("w:bookmarkStart").compactMap { $0["w:name"]?.lowercased() })
        // (Those of the other parts too, by their text: a reference into a
        // note or a header finds its name there.)
        var otherParts = ""
        for (name, data) in kept where name.hasPrefix("word/") && name.hasSuffix(".xml") && name != "word/document.xml" && !name.containsSubstring("/_rels/") {
            if name.containsSubstring("header") || name.containsSubstring("footer") || name.containsSubstring("notes") {
                otherParts += String(decoding: data, as: UTF8.self)
            }
        }
        notes.keptBookmarkText = otherParts
        // How note marks are numbered: Word's endnotes count "i, ii, iii"
        // unless the settings say otherwise, its footnotes "1, 2, 3"
        // (endnotes.docx and Bug54849 show "i" in Word's print).
        if let settings = part("word/settings.xml").flatMap(XNode.parse) {
            if let f = settings.first("w:endnotePr")?.first("w:numFmt")?["w:val"] { notes.endnoteFormat = f }
            if let f = settings.first("w:footnotePr")?.first("w:numFmt")?["w:val"] { notes.footnoteFormat = f }
        }
        notes.hasColumns = body.descendants("w:cols").contains { (Int($0["w:num"] ?? "") ?? 1) > 1 }
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
            titlePage = _on(sect.first("w:titlePg"))
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
            // (An on/off element: w:val="false" or "0" or "off" is off; 5ff3d0's
            // settings say so, and every even page lost its header.)
            evenAndOddHeaders = part("word/settings.xml").map { data -> Bool in
                let xml = String(decoding: data, as: UTF8.self)
                guard let at = xml.rangeOfSubstring("<w:evenAndOddHeaders") else { return false }
                let rest = xml[at.upperBound...]
                let tag = rest[..<(rest.firstIndex(of: ">") ?? rest.endIndex)]
                return !["w:val=\"false\"", "w:val=\"0\"", "w:val=\"off\""].contains(where: { String(tag).containsSubstring($0) })
            } ?? false
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
        _themeColors = _themePalette(entries)
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
        // The same with the style's first-row paragraph look on top.
        var headerBases: [String: RichParagraphStyle] = [:]
        var headerRootBases: [String: RichParagraphStyle] = [:]
        var docBase = base
        // Cell margins by table style, each side from the style's chain
        // down to the default table style, then Word's own (0, 5.4pt).
        var tableMargins: [String: _Margins] = [:]
        var defaultMargins = _Margins()
        // Whether a table style draws borders (Table Grid does, Normal Table
        // does not): a table that says nothing itself takes its style's word.
        var tableBorders: [String: _Borders] = [:]
        // A table style's own indent (twips), down its w:basedOn chain.
        var tableIndents: [String: Double] = [:]
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
        // A table style's other run properties, by its chain (its own over
        // its parent's), and what the Normal style states of its own: the
        // table's stand under the paragraph's style, over the defaults.
        var tableChars: [String: CharStyle] = [:]
        var normalStatedChar = CharStyle()
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
            var allTableStyles: [String: XNode] = [:]
            for style in styles.all("w:style") where style["w:type"] == "table" {
                if let id = style["w:styleId"] { allTableStyles[id] = style }
            }
            for style in styles.all("w:style") where style["w:type"] == "table" {
                guard let id = style["w:styleId"] else { continue }
                // (A table style says its paragraph look over the style it is
                // based on: ECC Table - red header has none of its own and
                // takes "before 3 pt" from ECC Table - clean. Word's rows in
                // 2179cebe stand 2.3 pt apart, ours 8.9 with the defaults.)
                var chain: [XNode] = [], seenT = Set<String>(), curT: String? = id
                while let c = curT, !seenT.contains(c), let n = allTableStyles[c] {
                    seenT.insert(c)
                    chain.insert(n, at: 0)
                    curT = n.first("w:basedOn")?["w:val"]
                }
                var ps = base
                var rootPs = docBase
                for n in chain {
                    if let pPr = n.first("w:pPr") { _paragraphProps(pPr, into: &ps); _paragraphProps(pPr, into: &rootPs) }
                }
                tableBases[id] = ps
                tableRootBases[id] = rootPs
                var hps = ps, hroot = rootPs, hasHeaderPPr = false
                for n in chain {
                    for part in n.all("w:tblStylePr") where part["w:type"] == "firstRow" {
                        if let pPr = part.first("w:pPr") { _paragraphProps(pPr, into: &hps); _paragraphProps(pPr, into: &hroot); hasHeaderPPr = true }
                    }
                }
                if hasHeaderPPr { headerBases[id] = hps; headerRootBases[id] = hroot }
                tableNodes[id] = style
                tableEdges[id] = _edges(style.first("w:tblPr"), "w:tblBorders")
                tableSides[id] = style.first("w:tblPr")?.first("w:tblBorders")
                if style.first("w:tblPr")?.first("w:tblLayout")?["w:type"] == "fixed" {
                    fixedTableStyles.insert(id)
                    if style["w:default"] == "1" { defaultTableFixed = true }
                }
                if style["w:default"] == "1" {
                    defaultMargins = _defaultStyleMargins(style)
                    defaultBorders = _borders(style.first("w:tblPr"), "w:tblBorders")
                }
            }
            // (A styles part with no default table style leaves a table no cell
            // margin: Word's 5.4pt is Normal Table's, which a file saved by
            // Word carries and some exporters' do not. Lab tableorigin (Word
            // for Windows): with no table style at all the letters stand
            // 0.5pt from the rule and the left rule on the margin, in every
            // mode — a table is set out by its left cell margin, here 0.)
            if !tableNodes.values.contains(where: { $0["w:default"] == "1" }) {
                RuleTrace.hit("no-default-table-style-no-margin")
                defaultMargins = _Margins(top: 0, left: 0, bottom: 0, right: 0)
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
                var seen = Set<String>(), cur: String? = id
                while let c = cur, !seen.contains(c), let node = tableNodes[c] {
                    seen.insert(c)
                    if let ind = node.first("w:tblPr")?.first("w:tblInd"), (ind["w:type"] ?? "dxa") == "dxa", let w = Double(ind["w:w"] ?? "") {
                        tableIndents[id] = w
                        break
                    }
                    cur = node.first("w:basedOn")?["w:val"]
                }
            }
            for id in tableNodes.keys {
                var cond = _Cond(), seen = Set<String>(), cur: String? = id
                while let c = cur, !seen.contains(c), let node = tableNodes[c] {
                    seen.insert(c)
                    if cond.cellVAlign == nil, let v = node.first("w:tcPr")?.first("w:vAlign")?["w:val"], v == "center" || v == "bottom" { cond.cellVAlign = v }
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
                            if cond.headerVAlign == nil, let v = part.first("w:tcPr")?.first("w:vAlign")?["w:val"], v == "center" || v == "bottom" { cond.headerVAlign = v }
                            if let h = part.first("w:trPr")?.first("w:tblHeader"), !_isOff(h) { cond.headerRepeats = true }
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
            if let normal = styles.all("w:style").first(where: { style in
                style["w:type"] == "paragraph" && (style["w:default"] == "1" || style["w:styleId"] == "Normal") }),
               let rPr = normal.first("w:rPr") {
                normalStatedChar = _charStyle(rPr, base: CharStyle())
            }
            for id in tableNodes.keys {
                var chain: [XNode] = [], seen = Set<String>(), cur: String? = id
                while let c = cur, !seen.contains(c), let node = tableNodes[c] {
                    seen.insert(c)
                    chain.append(node)
                    cur = node.first("w:basedOn")?["w:val"]
                }
                var cs = CharStyle()
                for node in chain.reversed() { if let rPr = node.first("w:rPr") { cs = _charStyle(rPr, base: cs) } }
                tableChars[id] = cs
            }
            for id in tableNodes.keys {
                var m = _Margins(), seen = Set<String>(), cur: String? = id
                while let c = cur, !seen.contains(c), let node = tableNodes[c] {
                    seen.insert(c)
                    m = m.under(node["w:default"] == "1" ? _defaultStyleMargins(node) : _cellMargins(node.first("w:tblPr")))
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
            for style in styles.all("w:style") {
                if let name = style.first("w:name")?["w:val"] { notes.styleNames.insert(name.lowercased()) }
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
                // A style that turns the list OFF (numId 0) over a parent that
                // carries one does not take the left indent and hanging the parent
                // wrote beside its numbering: tdf132752's "Hinweis3" (numId 0, no
                // w:ind) stands at the margin in Word's print, though "Anleitung"
                // under it says left 2697, and "Hinweis1" (numId 0, its own left
                // and right) takes no hanging from it. The right indent stays
                // (Hinweis3 wraps in 284pt, Anleitung's 3340 twips from the right).
                if style.first("w:pPr")?.first("w:numPr")?.first("w:numId")?["w:val"] == "0",
                   let parent = style.first("w:basedOn")?["w:val"] {
                    var seenUp = Set<String>(), up: String? = parent, numbered = false
                    while let c = up, !seenUp.contains(c), let node = paragraphStyles[c] {
                        seenUp.insert(c)
                        if let v = node.first("w:pPr")?.first("w:numPr")?.first("w:numId")?["w:val"] { numbered = v != "0"; break }
                        up = node.first("w:basedOn")?["w:val"]
                    }
                    if numbered {
                        r.paragraph.indentLeft = docBase.indentLeft
                        r.paragraph.firstLineIndent = docBase.firstLineIndent
                    }
                }
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
                // 2003-era default), not the 11pt of a fresh document. One
                // whose styles part has no run defaults at all (LibreOffice's
                // empty w:styles: tdf108496, tdf132752, four more) is Word's own
                // Normal, as with no styles part: 12pt.
                // A file that names no face anywhere, and carries no theme, is set in Times New Roman:
                // lo tdf109308_dropCapNumbered's print is TimesNewRomanPSMT.
                if cs.fontFamily == nil, styles.first("w:docDefaults")?.first("w:rPrDefault")?.first("w:rPr")?.first("w:rFonts") == nil,
                   !styles.all("w:style").contains(where: { $0.first("w:rPr")?.first("w:rFonts") != nil
                       && (part("word/theme/theme1.xml") == nil || $0["w:default"] == "1") }),
                   // With a theme, Word keeps the theme face unless the file states (empty) run
                   // defaults itself (Google Docs, kor c9baf7); LibreOffice files with no
                   // w:docDefaults at all draw the theme's Calibri (lo-8882730a, lo-029954d7).
                   part("word/theme/theme1.xml") == nil || styles.first("w:docDefaults") != nil {
                    cs.fontFamily = "Times New Roman"
                    RuleTrace.hit("no-fonts-named-times")
                    // Its Hangul is Batang in Word for Windows, line 1.31 em (batch B 9b36b8: 8 pages,
                    // ours 10 with Malgun's 1.73 em); a file with no Hangul keeps the default.
                    if cs.eastAsiaFontFamily == nil, let d = part("word/document.xml"),
                       String(decoding: d, as: UTF8.self).unicodeScalars.contains(where: { $0.value >= 0xAC00 && $0.value <= 0xD7A3 }) {
                        cs.eastAsiaFontFamily = "Batang"
                        RuleTrace.hit("no-fonts-named-batang")
                    }
                }
                if cs.fontSize == nil {
                    if styles.first("w:docDefaults")?.first("w:rPrDefault") == nil {
                        cs.fontSize = 12
                    } else {
                        cs.fontSize = 10
                    }
                }
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
                        let face = lvl.first("w:rPr")?.first("w:rFonts")?["w:ascii"]?.lowercased()
                        let wingdings = face == "wingdings"
                        switch ch.value {
                        // (Wingdings' own shapes where the level names that face — Word's prints
                        // draw them: "n" a black square, "u" a diamond, the box at 0xA8, "o" a white
                        // square, 0x9E a small dot. Symbol's 0xA8 is a diamond suit, not this.)
                        case 0xF06E where wingdings: glyph = "\u{25FC}"
                        case 0xF075 where wingdings: glyph = "\u{25C6}"
                        case 0xF0A8 where wingdings: glyph = "\u{25FB}"
                        case 0xF06F where wingdings: glyph = "\u{25A1}"
                        case 0xF09E where wingdings: glyph = "\u{00B7}"
                        case 0xF0B7, 0x2022: glyph = "\u{2022}"
                        case 0xF06F: glyph = "\u{25E6}"
                        case 0xF0A7, 0x25AA: glyph = "\u{25AA}"
                        // (Wingdings "l", the round bullet: "⚫" in a Word print's text,
                        // and a round dot where the default bullet is a small one.)
                        case 0xF06C: glyph = "\u{26AB}"
                        case 0xF0D8, 0x27A2: glyph = "\u{27A2}"
                        case 0xF0FC, 0x2713: glyph = "\u{2713}"
                        case 0xF076, 0x2756: glyph = "\u{2756}"
                        case 0xE000 ... 0xF8FF: glyph = ListLevelFormat.defaultBullet(ilvl)
                        default: glyph = raw
                        }
                        // A picture bullet (`w:lvlPicBulletId`) is an image in Word's print,
                        // never a glyph: lo-ca9b51bc's "下文…" line reads "下文…" there, not "⚫下文…".
                        let picture = lvl.first("w:lvlPicBulletId") != nil
                        formats[ilvl] = ListLevelFormat(text: picture ? "\u{200B}" : glyph, format: .bullet)
                        if picture { formats[ilvl]!.pictureBullet = true }
                        else if glyph != raw { formats[ilvl]!.rawText = raw; formats[ilvl]!.rawTextGlyph = glyph }
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
                        if !kept.children.isEmpty, !formats[ilvl]!.pictureBullet { formats[ilvl]!.numberRPrXML = PptxXML.serialize(kept) }
                    }
                    if let suff = lvl.first("w:suff")?["w:val"] { formats[ilvl]!.suffix = suff }
                    // No label, no tab after it: 3922c734's empty-label items start at the
                    // margin in Word; a tab there ran to the next default stop (65 pt in).
                    else if lvl.first("w:lvlText")?["w:val"] == "" { formats[ilvl]!.suffix = "nothing" }
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
        var afterCentredFloat = -1
        var afterCentredFloatCell: CellRef? = nil
        var pendingBreakCharacter = false   // ... made by a break character, in a run with these properties
        var pendingBreakRPr: String? = nil
        var pendingBreakColumn = false
        var tableColumns: [String: [Double]] = [:]
        var tableStyles: [String: TableStyle] = [:]
        var tableCount = 0
        var currentCell: CellRef? = nil
        var rowExcepted = false   // the row of `currentCell` states its own cell margins (w:tblPrEx)
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
            if afterCentredFloat == paragraphs.count, afterCentredFloatCell == currentCell, p.cell == nil || p.cell == currentCell { p.style.besideFloat = true }
            afterCentredFloat = -1
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
                // (A plain hidden mark, no style separator: the joined paragraph
                // is set as the second is — merge_hidden_redline's centred "abc"
                // and the left "def" print as one line set left in Word's.)
                // (Its alignment only: zh-621d8756's hidden mark and the empty
                // paragraph after it differ in line spacing, where the first's
                // stands.)
                if !paragraphs[i].style.markSpecVanish, !p.style.markHidden, paragraphs[i].style.alignment != p.style.alignment {
                    RuleTrace.hit("hidden-mark-joins-second")
                    paragraphs[i].style.alignment = p.style.alignment
                }
                let bookmarkOffset = paragraphs[i].length
                paragraphs[i].bookmarkMarkers += p.bookmarkMarkers.map {
                    RichBookmarkMarker(id: $0.id, name: $0.name, offset: bookmarkOffset + $0.offset)
                }
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
        var inWrapperBody = false
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
            // (Word for Windows' lab nb, zh-cb57eaad's last outer table: the empty mark under a nested table
            // adds nothing to the cell, whatever its size, grid or row — the outer cell closes 0.72pt, a rule,
            // under the nested table's foot. Left out, where the cell has the table's own paragraphs before it;
            // set at zero height it still made the row 14pt taller, and the final line went to a page of its own.)
            if Self.wordOnWindows, paragraphs.count - 1 > first, paragraphs[last].cell != nil, paragraphs[last - 1].cell == paragraphs[last].cell { paragraphs.removeLast() }
        }
        func walkBlock(_ source: XNode, indent: Double, depth: Int = 0) {
            // (A table with w:bidiVisual runs its first column at the right edge: Word's
            // ara-z8215570 header has the Urdu title cell right, the date left; walked
            // in file order ours drew them the other way round.)
            let node = Self._mirroredTable(source)
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
                    // the same document has a page 3 of the picture alone.
                    // And only where the margins stay: a continuous section with
                    // other top or bottom margins keeps the break — LibreOffice's
                    // tdf149555, "Seriously" and a page break before a contents
                    // section of 1422 twips on top for 5982, has the contents
                    // on Word's page 2; ours ran them on under it.)
                    let sectionsOwn = Self.wordOnWindows && currentCell == nil && !p.breakColumn && p.paragraph.style.sectionXML != nil
                        && p.paragraph.style.sectionBreaksPage == false && !p.sectionMarginsChange
                    if p.pageBreakAfter, !sectionsOwn { emit(p.paragraph); pendingPageBreak = true; pendingBreakCharacter = p.breakCharacter; pendingBreakRPr = p.breakRPr; pendingBreakColumn = p.breakColumn } else if p.pageBreakAfter, p.breakCharacter { var q = p.paragraph; q.style.ignoredSectionPageBreak = true; emit(q) } else { emit(p.paragraph) }
                }
                if recordingBody, currentCell == nil { for k in first ..< paragraphs.count { bodyNodes[k] = node } }
                // (A line break that clears opens a paragraph after a table floating over the text: the
                // line is the one level with the table, and the text after it stands under the table.
                // LibreOffice's fdo76248, "*Projections" after Table 5: 499.5 in Word's print, the table's
                // foot, where ours set it and the paragraphs after in the 218pt beside it.)
                if Self.wordOnWindows, currentCell == nil, first > 0, first < paragraphs.count, let above = paragraphs[first - 1].cell,
                   tableStyles[above.table]?.floatsOverText == true, paragraphs[first].image == nil, paragraphs[first].text.hasPrefix("\n"), paragraphs[first].text.utf16.count > 1,
                   let run = node.children.first(where: { $0.name == "w:r" }),
                   let br = run.children.first(where: { $0.name != "w:rPr" }), br.name == "w:br",
                   (br["w:type"] ?? "textWrapping") == "textWrapping", ["all", "left", "right"].contains(br["w:clear"] ?? "") {
                    paragraphs[first].text.removeFirst()
                    if !paragraphs[first].runs.isEmpty {
                        if paragraphs[first].runs[0].length > 1 { paragraphs[first].runs[0].length -= 1 } else { paragraphs[first].runs.removeFirst() }
                    }
                    paragraphs[first].style.clearsFloat = true
                }
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
                        let counts = (notes.seenFootnotes, notes.seenEndnotes, notes.openComments, notes.pendingBookmarks, notes.pendingBookmarkMarkers, notes.fields,
                                      notes.seenComments, notes.fieldShown)
                        paragraphs = []; currentCell = nil; recordingBody = false; pendingPageBreak = false
                        cellChar = CharStyle()
                        notes.inTextBox = true
                        for child in content.children { walkBlock(child, indent: 0, depth: 1) }
                        notes.inTextBox = false
                        let inner = paragraphs
                        (paragraphs, currentCell, cellChar, cellBase, cellRootBase, recordingBody,
                         pendingPageBreak, pendingBreakCharacter, pendingBreakRPr, pendingBreakColumn) = saved
                        (notes.seenFootnotes, notes.seenEndnotes, notes.openComments, notes.pendingBookmarks, notes.pendingBookmarkMarkers, notes.fields,
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
            case "w:tbl" where currentCell != nil && depth < maxNesting && Self._isTallNarrowFloat(node):
                // (See `_isTallNarrowFloat`: its rows are paragraphs of the
                // cell, set in from its sides where the float stands, each
                // as tall as its row asks, and kept whole at a page's foot.)
                let before = paragraphs.count
                var keptId: String? = nil
                if _nestingDepth(node) <= 6, let frag = _keptFragment(node, notes) {
                    keptTableCount += 1
                    keptId = "kt\(keptTableCount)"
                    keptTables[keptId!] = KeptTable(xml: frag.xml, rels: frag.rels, texts: [])
                }
                let pos = node.first("w:tblPr")?.first("w:tblpPr")
                let gridW = (Double(node.first("w:tblGrid")?.all("w:gridCol").first?["w:w"] ?? "") ?? 0) / 20
                var wide = gridW
                if let w = node.first("w:tblPr")?.first("w:tblW"), (w["w:type"] ?? "dxa") == "dxa", let v = Double(w["w:w"] ?? ""), v > 0 { wide = v / 20 }
                var cellWide = 0.0
                if let c = currentCell, let cols = tableColumns[c.table] {
                    cellWide = cols.dropFirst(c.column).prefix(c.span).reduce(0, +)
                }
                var left = 0.0, right = 0.0
                if cellWide > wide + 1 {
                    switch pos?["w:tblpXSpec"] {
                    case "center"?: left = (cellWide - wide) / 2
                    case "right"?, "outside"?: left = cellWide - wide
                    case "left"?, "inside"?: left = 0
                    default: left = min(max(0, (Double(pos?["w:tblpX"] ?? "") ?? 0) / 20), cellWide - wide)
                    }
                    right = cellWide - wide - left
                }
                let tableMargins = _cellMargins(node.first("w:tblPr"))
                // (Each row is a rule's width taller at its head, and the
                // table stands its tblpY under the paragraph it floats by:
                // Word's print of floattable-in-inlinetable has the first
                // line 5.9pt under the cell's, the tblpY 5.4 and the rule
                // 0.5, and the row on the next page 0.5 under its margin.)
                func rule(_ name: String) -> Double {
                    guard let b = node.first("w:tblPr")?.first("w:tblBorders")?.first(name), (b["w:val"] ?? "none") != "none",
                          let sz = Double(b["w:sz"] ?? "") else { return 0 }
                    return sz / 8
                }
                var rowNumber = 0
                for tr in unwrapped(node, "w:tr") {
                    defer { rowNumber += 1 }
                    for tc in unwrapped(tr, "w:tc") {
                        let first = paragraphs.count
                        for child in tc.children { walkBlock(child, indent: indent, depth: depth + 1) }
                        guard paragraphs.count > first else { continue }
                        let m = _cellMargins(tc.first("w:tcPr"), "w:tcMar").under(tableMargins)
                        paragraphs[first].style.spaceBefore += (m.top ?? 0) + rule(rowNumber == 0 ? "w:top" : "w:insideH")
                            + (rowNumber == 0 && pos?["w:vertAnchor"] == "text" ? max(0, (Double(pos?["w:tblpY"] ?? "") ?? 0) / 20) : 0)
                        paragraphs[paragraphs.count - 1].style.spaceAfter += m.bottom ?? 0
                        let least = (tr.first("w:trPr")?.first("w:trHeight")).flatMap { h in h["w:hRule"] == "exact" ? nil : Double(h["w:val"] ?? "").map { $0 / 20 } }
                        for k in first ..< paragraphs.count {
                            paragraphs[k].style.indentLeft += left
                            paragraphs[k].style.indentRight += right
                            if pos?["w:tblpXSpec"] == "center" { paragraphs[k].style.centredFloat = true }
                            if let least, least < 500 {
                                paragraphs[k].style.keepLines = true
                                if k < paragraphs.count - 1 { paragraphs[k].style.keepNext = true }
                            }
                        }
                        if let least, least > 0 {
                            paragraphs[paragraphs.count - 1].style.blockMinHeight = least
                            paragraphs[paragraphs.count - 1].style.blockParagraphs = paragraphs.count - first
                        }
                    }
                }
                if let kid = keptId {
                    if paragraphs.count == before { emit(RichParagraph(style: cellBase)) }
                    for k in before ..< paragraphs.count { paragraphs[k].keptTable = kid }
                    keptTables[kid]!.texts = paragraphs[before...].map(\.text)
                }
                if pos?["w:tblpXSpec"] == "center", pos?["w:vertAnchor"] == "text", paragraphs.count > before { afterCentredFloat = paragraphs.count; afterCentredFloatCell = currentCell }
            case "w:tbl" where currentCell != nil && depth < maxNesting && (_nestingDepth(node) == 1 || Self._formHoldingATable(node))
                                // (Not a single row of as many paragraphs as a page holds: a block does not part inside a row,
                                // and one of 75 lines ran 40pt past the foot with the rest of its lines
                                // lost. Lab nt1, Word for Windows: such a row parts at the foot like any.)
                                && !(unwrapped(node, "w:tr").count == 1 && node.descendants("w:p").count >= 50)
                                && ((unwrapped(node, "w:tr").count <= 15 && textLength(node) <= 600)
                                    || (unwrapped(node, "w:tr").count > 15 && (node.first("w:tblGrid")?.all("w:gridCol").count ?? 1) >= 2)
                                    // (Or a list of short rows, one column: LibreOffice's tdf170620, 56 rows
                                    // of 14 characters, parts between its rows as Word's does.)
                                    || (unwrapped(node, "w:tr").count > 15 && textLength(node) <= 40 * unwrapped(node, "w:tr").count)):
                // A small table in a cell, with none in it, is a table of
                // its own: read as a document is, and set in its cell as a
                // block as tall as it lays out (`RichTextBox.growsToFit`).
                // Flattened, zh-454e2e29's form of five columns — "姓名",
                // "職稱", "職務編號"… — stood as a column of lines 36pt
                // apart. (A long one is still flattened below: a block
                // does not part across pages, and 60329's protocol text,
                // 2,235 characters in a three-row table in a cell, ran to
                // six pages for it.) Its markup is kept for the save.
                let outerExcepted = rowExcepted
                let saved = (paragraphs, currentCell, cellChar, cellBase, cellRootBase)
                paragraphs = []
                currentCell = nil
                walkBlock(node, indent: 0, depth: depth + 1)
                let inner = paragraphs
                (paragraphs, currentCell, cellChar, cellBase, cellRootBase) = saved
                let ids = Set(inner.compactMap { $0.cell?.table })
                var box = RichTextBox(paragraphs: inner)
                box.insetLeft = 0; box.insetTop = 0; box.insetRight = 0; box.insetBottom = 0
                // (Word for Windows' labs T0-T2: the cell that holds a table is taller by that table's own
                // cell margins, top and bottom, once more — lo-eb12e7d4's groups stand 2.8pt, the 28 twips
                // of a pair, short of its print.)
                if let outer = saved.1, outerExcepted, (outer.padding?.top ?? 0) == 0, (outer.padding?.bottom ?? 0) == 0, node.first("w:tblPr")?.first("w:tblpPr") == nil, node.descendants("w:drawing").isEmpty, let tcMar = node.descendants("w:tcMar").first {
                    let pr = XNode(name: "w:tcPr", attrs: [:]); pr.children = [tcMar]
                    let m = _cellMargins(pr, "w:tcMar")
                    box.insetBottom = (m.top ?? 0) + (m.bottom ?? 0)
                }
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
                    if let l = Double(pos["w:leftFromText"] ?? "") { f.distanceLeft = l / 20 }
                    if let r = Double(pos["w:rightFromText"] ?? "") { f.distanceRight = r / 20 }
                    f.againstText = pos["w:vertAnchor"] == "text"
                    f.fromCellTop = pos["w:vertAnchor"] == "page" || pos["w:vertAnchor"] == "margin"
                    f.fromCellText = pos["w:horzAnchor"] == "margin"
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
                // (Word for Windows' labs T0-T2: the cell that holds a table is taller by that table's own
                // cell margins, top and bottom, once more — lo-eb12e7d4's groups stand 2.8pt, the 28 twips
                // of a pair, short of its print.)
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
                            for child in tc.children { walkBlock(child, indent: indent, depth: depth + 1) }
                            guard paragraphs.count > first else { continue }
                            flagMarkUnderNestedTable(tc, since: first)
                            let m = _cellMargins(tc.first("w:tcPr"), "w:tcMar").under(tableMargins)
                            // (The nested table's own left cell margin and left border put its text in
                            // from the outer cell's: lo-c7082c66's middle table stands 5.6pt in, even in
                            // compat mode 11, and lo-5c5eb1f7's frames in nested cells 5.65pt. This
                            // replaces the flat 18pt the children used to be handed, which was 12pt too much.)
                            let edge = (node.first("w:tblPr")?.first("w:tblBorders")?.first("w:left")).flatMap { b -> Double? in
                                (b["w:val"] ?? "none") == "none" ? nil : Double(b["w:sz"] ?? "").map { $0 / 16 } } ?? 0
                            let lead = (m.left ?? 5.4) + edge
                            // (A float centred in the cell stands at the middle of the cell, as its margins are the same both sides:
                            // lo-c7082c66's, 277.1 in Word's print, was 283 with the left margin added.)
                            for k in first ..< paragraphs.count where paragraphs[k].cell == currentCell && !paragraphs[k].style.centredFloat { paragraphs[k].style.indentLeft += lead }
                            // (A table floating by the text keeps its right distance from the text out of the room its
                            // lines have: lo-660753a9's middle table, 141 twips each side, sets "before the inner
                            // table" in a cell 7pt narrower, and its inner table's "inner table row 1" in two lines.)
                            if let fp = node.first("w:tblPr")?.first("w:tblpPr"), fp["w:vertAnchor"] == "text" {
                                let gap = (Double(fp["w:rightFromText"] ?? "") ?? 0) / 20
                                for k in first ..< paragraphs.count where paragraphs[k].cell == currentCell && !paragraphs[k].style.centredFloat { paragraphs[k].style.indentRight += gap }
                            }
                            // (Its top margin and top line stand again over a part of it that goes over a
                            // page — see `RichParagraphStyle.nestedTopRepeat`; not over its first paragraph,
                            // which brings its own space. The cell's own line, else the table's: Word for
                            // Windows' lab nt1 sets three nested levels 6.12pt each under their 5.65 margins
                            // and 0.5pt lines, and 15.0pt for 0 + 0.5, 10 + 1.5 and 3 + none.)
                            func line(_ name: String, _ fallback: String) -> Double {
                                let b = tc.first("w:tcPr")?.first("w:tcBorders")?.first(name) ?? node.first("w:tblPr")?.first("w:tblBorders")?.first(fallback)
                                guard let b, (b["w:val"] ?? "none") != "none" else { return 0 }
                                return Double(b["w:sz"] ?? "").map { $0 / 8 } ?? 0
                            }
                            let topEdge = line("w:top", r == 0 ? "w:top" : "w:insideH")
                            let bottomEdge = line("w:bottom", r == rows.count - 1 ? "w:bottom" : "w:insideH")
                            for k in (first + 1) ..< max(first + 1, paragraphs.count) where paragraphs[k].cell == currentCell {
                                paragraphs[k].style.nestedTopRepeat += (m.top ?? 0) + topEdge
                            }
                            for k in first ..< max(first, paragraphs.count - 1) where paragraphs[k].cell == currentCell {
                                paragraphs[k].style.nestedBottomRepeat += (m.bottom ?? 0) + bottomEdge
                            }
                            paragraphs[first].style.spaceBefore += (m.top ?? 0) + topEdge + spacing * (r == 0 ? 2 : 1)
                            paragraphs[paragraphs.count - 1].style.spaceAfter += (m.bottom ?? 0) + bottomEdge + spacing * (r == rows.count - 1 ? 2 : 1)
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
                        inWrapperBody = true
                        for child in children { walkBlock(child, indent: indent, depth: depth) }
                        inWrapperBody = false
                        guard paragraphs.count > first else { continue }
                        // (A row of one paragraph keeps the height the row
                        // was given as that line's least: 60329's 9pt
                        // spacer row holds a 1pt empty mark, and Word's
                        // print has the 9pt between its tables.)
                        // (An empty cell whose end mark the file hides (`w:hideMark`)
                        // asks nothing of its row, as in a table's own rows: the row is
                        // its stated height, or none. Lab ebb4 (Word, 2026-11-08): the
                        // two 150-twip rows of ebb4a037's wrapper are 7.5 each with the
                        // height and 0 without, where a 9.65 pt mark line held them.)
                        if paragraphs.count == first + 1, !children.contains(where: { $0.name == "w:tbl" }),
                           paragraphs[first].text.isEmpty, paragraphs[first].image == nil, paragraphs[first].inlineImages.isEmpty,
                           _on(tc.first("w:tcPr")?.first("w:hideMark")),
                           tr.first("w:trPr")?.first("w:trHeight")?["w:hRule"] != "exact" {
                            let v = (tr.first("w:trPr")?.first("w:trHeight")).flatMap { Double($0["w:val"] ?? "") } ?? 0
                            paragraphs[first].style.lineHeightPoints = max(v / 20, 0.05)
                            paragraphs[first].style.lineHeightIsMinimum = false
                        } else
                        if paragraphs.count == first + 1, !children.contains(where: { $0.name == "w:tbl" }),
                           let h = tr.first("w:trPr")?.first("w:trHeight"), h["w:hRule"] != "exact",
                           let v = Double(h["w:val"] ?? ""), v > 0,
                           paragraphs[first].style.lineHeightPoints == nil || paragraphs[first].style.lineHeightIsMinimum {
                            paragraphs[first].style.lineHeightPoints = max(paragraphs[first].style.lineHeightPoints ?? 0, v / 20)
                            paragraphs[first].style.lineHeightIsMinimum = true
                        }
                        let m = _cellMargins(tc.first("w:tcPr"), "w:tcMar").under(tableMargins)
                        // (Over the first paragraph that takes room in the flow: a table
                        // floating by the text opening the cell has none, and its rows
                        // would give the space away — floattable-del-empty's heading
                        // stands 2.25pt over where Word's does.)
                        var lead = first
                        while lead < paragraphs.count - 1, let c = paragraphs[lead].cell,
                              tableStyles[c.table]?.floatsOverText == true, tableStyles[c.table]?.pageAnchored == false { lead += 1 }
                        if paragraphs[lead].cell != nil, let c = paragraphs[lead].cell, tableStyles[c.table]?.floatsOverText == true { lead = first }
                        // (And its automatic space before is the cell's top, none:
                        // the heading under the table stands at the cell's head.)
                        // (Word sets that table a second margin down, from the cell's
                        // content: the 69pt table of floattable-del-empty stands 4.5pt
                        // under where the flow reached, twice the wrapper's 2.25.)
                        if lead != first {
                            var moved = Set<String>()
                            for k in first ..< lead {
                                if let c = paragraphs[k].cell, var st = tableStyles[c.table], st.floatsOverText, !st.pageAnchored, moved.insert(c.table).inserted {
                                    st.floatOffsetY = (st.floatOffsetY ?? 0) + (Self.wordOnWindows ? 1 : 2) * (m.top ?? 0)
                                    tableStyles[c.table] = st
                                }
                            }
                        }
                        if lead != first, paragraphs[lead].style.spaceBeforeAuto {
                            paragraphs[lead].style.spaceBeforeAuto = false
                            paragraphs[lead].style.spaceBefore = 0
                        }
                        if Self.wordOnWindows, let tw = node.first("w:tblPr")?.first("w:tblW"), (tw["w:type"] ?? "") == "dxa",
                           let dxa = Double(tw["w:w"] ?? ""), tc.first("w:tcPr")?.first("w:tcW").map({ ($0["w:type"] ?? "auto") == "auto" }) ?? true {
                            let room = dxa / 20 - (tableMargins.left ?? 0) - (tableMargins.right ?? 0)
                            for k in first ..< paragraphs.count where paragraphs[k].cell == nil && paragraphs[k].image == nil { paragraphs[k].style.wrapperRoom = room }
                        }
                        paragraphs[lead].style.spaceBefore += (m.top ?? 0) + spacing * (r == 0 ? 2 : 1)
                        // (Its automatic space after is the cell's foot, none, as in any
                        // cell: floattable-del-empty's last "NormalWeb" paragraph of a
                        // wrapper stands 17pt over the rule under it in Word's print,
                        // ours 28.7.)
                        if paragraphs[paragraphs.count - 1].style.spaceAfterAuto, paragraphs[paragraphs.count - 1].style.list == nil {
                            paragraphs[paragraphs.count - 1].style.spaceAfterAuto = false
                            paragraphs[paragraphs.count - 1].style.spaceAfter = 0
                        }
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
                // (Cells wider than the grid column they stand in make the column wider, in a table
                // that fits its content: Word's print of the lab tw1 has each column as wide as its
                // widest cell, 6381 + 6381 under a 4536 + 1845 grid, and the whole scaled down to the
                // text when it is wider. LibreOffice's tdf79329.)
                if let cols = tableColumns[id], node.first("w:tblPr")?.first("w:tblLayout")?["w:type"] != "fixed",
                   !(node.first("w:tblPr")?.first("w:tblStyle")?["w:val"].map { fixedTableStyles.contains($0) } ?? defaultTableFixed),
                   (node.first("w:tblPr")?.first("w:tblW")?["w:type"] ?? "auto") == "auto" {
                    var widest = cols
                    var wider = false
                    // (Only where a row is far wider than the grid — nearly twice: lo-a197b7a8's three 4428-twip cells under an 8812 grid, 1.5 times, keep the grid in Word's print; a grid Word wrote is its own
                    // layout of the columns, and cells wider than it are preferences it overruled.)
                    let gridTotal = cols.reduce(0, +)
                    for tr in unwrapped(node, "w:tr") where tr.first("w:trPr")?.first("w:gridBefore") == nil {
                        var col = 0
                        var rowTotal = 0.0
                        for tc in unwrapped(tr, "w:tc") {
                            let w = tc.first("w:tcPr")?.first("w:tcW")
                            if w?["w:type"] == "dxa", let v = Double(w?["w:w"] ?? "") { rowTotal += v / 20 }
                        }
                        guard rowTotal > gridTotal * 1.75 else { continue }
                        for tc in unwrapped(tr, "w:tc") {
                            let span = max(1, Int(tc.first("w:tcPr")?.first("w:gridSpan")?["w:val"] ?? "") ?? 1)
                            let w = tc.first("w:tcPr")?.first("w:tcW")
                            if span == 1, col < widest.count, w?["w:type"] == "dxa", let v = Double(w?["w:w"] ?? ""), v / 20 > widest[col] + 1 {
                                widest[col] = v / 20
                                wider = true
                            }
                            col += span
                        }
                    }
                    if wider { tableColumns[id] = widest }
                    // (A table nested in a cell takes its columns from its cells' stated
                    // widths, scaled to the room its grid has: lo-5c5eb1f7's header table,
                    // cells of 1266 and 7868 twips over a grid of 1253 and 5354, has its
                    // first column 45pt in Word's print, 1266 of 9134 of the grid's
                    // 330pt, where the grid's own gave 62.7.)
                    else if currentCell != nil || depth > 0, let first = unwrapped(node, "w:tr").first, first.first("w:trPr")?.first("w:gridBefore") == nil {
                        var widths: [Double] = []
                        var ok = true
                        for tc in unwrapped(first, "w:tc") {
                            let w = tc.first("w:tcPr")?.first("w:tcW")
                            guard w?["w:type"] == "dxa", let v = Double(w?["w:w"] ?? ""), v > 0, tc.first("w:tcPr")?.first("w:gridSpan") == nil else { ok = false; break }
                            widths.append(v / 20)
                        }
                        let total = widths.reduce(0, +)
                        if ok, widths.count == cols.count, total > gridTotal * 1.05 {
                            tableColumns[id] = widths.map { $0 / total * gridTotal }
                        }
                    }
                }
                // (An auto-width table whose grid is an equal split, a converter's stand-in, while
                // every row's cells state the same widths in twips: Word lays the columns out by those
                // cells, not by the grid. jpn-z20806500-dacd38: a grid of 3427 x 3 under cells of
                // 1728 / 6048 / 2304, its columns at 59.4 / 145.8 / 448.3 pt in Word's print.)
                // (Fixed layout too: jpn-z22667840-bc5fb7's python-docx table, grid 3293 x 3 under cells
                // of 3168 / 2016 / 4464 and tblLayout fixed, has its edges by the cells in Word's print.)
                if let cols = tableColumns[id], cols.count > 1, (cols.max() ?? 0) - (cols.min() ?? 0) <= 0.1,
                   let cw = _statedCellColumns(node, count: cols.count),
                   _cellsAgreeWithTableWidth(node, cells: cw.reduce(0, +)) {
                    tableColumns[id] = cw
                }
                // (A fixed table of a stated share whose cells all state widths, each row the
                // same, a little under its grid: Word rules the cells' widths, not the grid.
                // zh-4a90bb2f's table, 6306 pct of a 442pt column over a grid of 11267 twips,
                // cells 1914 5515 939 1336 1464 = 11168: rules at 95.8 and 371.8pt from the left
                // edge in Word's print, the cells' 95.7 and 371.5, the grid's 96.6 and 372.7.)
                if let cols = tableColumns[id], node.first("w:tblPr")?.first("w:tblLayout")?["w:type"] == "fixed",
                   node.first("w:tblPr")?.first("w:tblW")?["w:type"] == "pct" {
                    var widths: [Double]? = nil
                    var same = true
                    for tr in unwrapped(node, "w:tr") {
                        var row: [Double] = []
                        // (Rows with merged cells are left out: the whole-width rows state their own.)
                        if tr.first("w:trPr")?.first("w:gridBefore") != nil || unwrapped(tr, "w:tc").contains(where: { $0.first("w:tcPr")?.first("w:gridSpan") != nil }) { continue }
                        for tc in unwrapped(tr, "w:tc") {
                            let w = tc.first("w:tcPr")?.first("w:tcW")
                            guard w?["w:type"] == "dxa", let v = Double(w?["w:w"] ?? ""), v > 0 else { same = false; break }
                            row.append(v / 20)
                        }
                        if !same || row.count != cols.count { same = false; break }
                        if let first = widths { if first != row { same = false; break } } else { widths = row }
                    }
                    if same, let w = widths {
                        let total = w.reduce(0, +), gridTotal = cols.reduce(0, +)
                        if total < gridTotal - 1, total > gridTotal * 0.95 { tableColumns[id] = w }
                    }
                }
                // (A table with no grid at all has its first row's cells for one:
                // LibreOffice's floattable-nested-3tables, tables of 2000-twip
                // cells, wraps "before the middle table:" in them in Word's print.)
                if tableColumns[id] == nil, node.first("w:tblGrid") == nil, let first = unwrapped(node, "w:tr").first,
                   first.first("w:trPr")?.first("w:gridBefore") == nil {
                    var widths: [Double] = []
                    var ok = true
                    for tc in unwrapped(first, "w:tc") {
                        let w = tc.first("w:tcPr")?.first("w:tcW")
                        let span = max(1, Int(tc.first("w:tcPr")?.first("w:gridSpan")?["w:val"] ?? "") ?? 1)
                        guard w?["w:type"] == "dxa", let v = Double(w?["w:w"] ?? ""), v > 0 else { ok = false; break }
                        widths += Array(repeating: v / 20 / Double(span), count: span)
                    }
                    if ok, !widths.isEmpty { tableColumns[id] = widths }
                }
                var style = TableStyle()
                // The table's own borders, else its style's, else none —
                // 64 of the corpus's 109 tables say nothing and have none.
                // Tables converted from HTML say it per cell instead
                // (bug65649's 5,734-cell table, bug59058, table-indent):
                // what most cells say wins, with their colour.
                let styledBorders = node.first("w:tblPr")?.first("w:tblStyle")?["w:val"].flatMap { tableBorders[$0] }
                let cells = unwrapped(node, "w:tr").flatMap { unwrapped($0, "w:tc") }
                let lostEdges = _lostCellEdges(rows: unwrapped(node, "w:tr").map { unwrapped($0, "w:tc") })
                let cellSaid = cells.compactMap { _borders($0.first("w:tcPr"), "w:tcBorders", lost: lostEdges[ObjectIdentifier($0)] ?? []) }
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
                var repeating = unwrapped(node, "w:tr").prefix { _on($0.first("w:trPr")?.first("w:tblHeader")) }.count
                // The style's conditional parts, as w:tblLook switches them
                // on (attributes in 2010 files, bits of w:val in 2007's).
                let cond = node.first("w:tblPr")?.first("w:tblStyle")?["w:val"].flatMap { tableConds[$0] } ?? _Cond()
                let tableStyleSize = node.first("w:tblPr")?.first("w:tblStyle")?["w:val"].flatMap { tableSizes[$0] }
                let tableStyleChar = node.first("w:tblPr")?.first("w:tblStyle")?["w:val"].flatMap { tableChars[$0] }
                let look = node.first("w:tblPr")?.first("w:tblLook")
                let lookVal = look.flatMap { Int($0["w:val"] ?? "", radix: 16) } ?? 0x04A0
                let firstRowOn = look?["w:firstRow"].map { $0 != "0" } ?? (lookVal & 0x0020 != 0)
                // (A style whose first row repeats does so in every table of
                // it that has a header row on: LibreOffice's fdo78904_fileHang,
                // 12 tables of "Table with Header", repeats "Account /
                // Description / Permissions" at the head of its next page in
                // Word's print, with no tblHeader in the file's rows.)
                if repeating == 0, firstRowOn, cond.headerRepeats { repeating = 1 }
                if repeating > 0 { style.headerRow = true; style.headerRowCount = repeating }
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
                var cellMar = cellMars.count * 2 >= cells.count && !cellMars.isEmpty
                    ? _cellMargins(cellMars[0].first("w:tcPr"), "w:tcMar") : _Margins()
                // (A side that more than half of them state: a margin one cell
                // alone gives its right is its own — lo tdf160077_layoutInCellB's
                // first cell, right 720 beside a second that says nothing of it,
                // took 36pt off the second's lines, which wrapped a word early.)
                let statedBy = cellMars.map { _cellMargins($0.first("w:tcPr"), "w:tcMar") }
                if statedBy.filter({ $0.top != nil }).count * 2 <= cells.count { cellMar.top = nil }
                if statedBy.filter({ $0.left != nil }).count * 2 <= cells.count { cellMar.left = nil }
                if statedBy.filter({ $0.bottom != nil }).count * 2 <= cells.count { cellMar.bottom = nil }
                if statedBy.filter({ $0.right != nil }).count * 2 <= cells.count { cellMar.right = nil }
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
                // (A table read out of a frame's wrapper is a nested table
                // all the same: Word sets it out by nothing — lab nestmargin.)
                if inWrapperBody, Self.wordOnWindows { style.textOutdent = 0; style.textOutdentRight = 0; style.inWrapperCell = true }
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
                    // (A table nested in a cell never starts left of the cell's text edge in
                    // Word for Windows, either compat mode: lab nest51 prints tblInd -120, -60
                    // and 0 all at the edge, +60 and +120 that far in. zh-/lo-51b81ccd's -60.)
                    style.indent = Self.wordOnWindows && (currentCell != nil || depth > 0) ? max(0, w / 20) : w / 20
                } else if node.first("w:tblPr")?.first("w:tblInd") == nil,
                          let w = node.first("w:tblPr")?.first("w:tblStyle")?["w:val"].flatMap({ tableIndents[$0] }) {
                    // (Or its style's: LibreOffice's NumberedList, a table style that
                    // indents by 360 twips for a list, stands 41pt in from the margin
                    // in Word's print and stood at it.)
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
                    if pos["w:tblpYSpec"] == "bottom", pos["w:tblpY"] == nil { style.pageAnchored = true; style.bottomAligned = true }
                    style.keptPosition = PptxXML.serialize(pos)
                        + (node.first("w:tblPr")?.first("w:tblOverlap").map { PptxXML.serialize($0) } ?? "")
                    // (No `w:vertAnchor` is the text's, the schema's default: LibreOffice's fdo68607, `w:tblpY` 495
                    // and none, stands 24.75pt under the margin in Word for Windows' print, where ours stood at it.)
                    let vertText = (pos["w:vertAnchor"] ?? "text") == "text"
                    if vertText, pos["w:tblpYSpec"] == nil, let v = Double(pos["w:tblpY"] ?? ""), v > 0 {
                        if pos["w:vertAnchor"] == nil { style.marginOffsetY = v / 20 } else { style.floatOffsetY = v / 20 }
                    }
                    // (`w:tblpYSpec="top"` with no anchor stated stands at the margin's top, over the empty
                    // paragraph before it: LibreOffice's lo-0dd5bc0a, a cover-page SDT; Word's print has it 26pt
                    // higher than ours, which set it under that paragraph.)
                    if let v = Double(pos["w:bottomFromText"] ?? ""), v > 0, style.floatOffsetY != nil, pos["w:tblpYSpec"] == nil { style.floatBottomGap = v / 20 }
                    if pos["w:tblpYSpec"] == "top", pos["w:vertAnchor"] == nil || pos["w:vertAnchor"] == "margin", pos["w:tblpY"] == nil {
                        style.marginOffsetY = 0
                    }
                    // (A table placed "inside" the text's line takes no room in it either: LibreOffice's
                    // tdf-less lo-4c84a541 has "After table1" level with it in Word's print.)
                    if vertText, pos["w:tblpYSpec"] == nil || pos["w:tblpYSpec"] == "inside" { style.floatsOverText = true }
                    // (A drawing the table holds that is not laid out in its cell.)
                    if node.descendants("wp:anchor").contains(where: { $0["layoutInCell"] == "0" }) { style.shapesLeaveCell = true }
                    if vertText, pos["w:tblpYSpec"] == nil, let v = Double(pos["w:tblpY"] ?? ""), v < 0 {
                        style.floatRaiseY = -v / 20
                    }
                    if pos["w:tblpXSpec"] == nil, let v = Double(pos["w:tblpX"] ?? "") {
                        style.floatX = v / 20
                        style.floatXAnchor = pos["w:horzAnchor"] ?? "text"
                    } else if let spec = pos["w:tblpXSpec"], (pos["w:horzAnchor"] ?? "text") != "page" || (spec == "center" && DocxFormat.wordOnWindows) {
                        // (Centred on the PAGE, as zh-a4e8599d p3's: its first rule at 67.8 in Word's print, the middle of 595pt
                        // for 460pt of table, where ours stood at the margin, 84.6. On a page of equal margins the two middles are one.)
                        // Or aligned in its margin or column, a table wider
                        // than it standing out on both sides: zh-0243e7fc
                        // p11's 539pt form, centred on its 415pt margin, has
                        // its first column's text at 54pt in Word's print,
                        // where ours, at the margin, stood at 115.
                        if spec == "center" { style.alignment = .center }
                        if spec == "right" { style.alignment = .right }
                        style.floatXAnchor = pos["w:horzAnchor"] ?? "text"   // (read only for the table's x in columns)
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
                // (A percentage-width table keeps the grid Word saved, which is Word's own fit; only an
                // equal-split grid, as Pandoc writes, says nothing: zh-6d402586 and lo-2c85bb1477d36796 hold theirs.)
                let gridCols = node.first("w:tblGrid")?.all("w:gridCol").compactMap { Double($0["w:w"] ?? "") } ?? []
                let equalGrid = gridCols.count > 1 && (gridCols.max() ?? 0) - (gridCols.min() ?? 0) <= 2
                if !cells.isEmpty, widthless == cells.count, style.width == nil, !style.fixedLayout, style.widthPercent == nil || equalGrid { style.contentFit = true }
                // (A table of a width in twips over an equal-split grid is content-fitted too, to that width: lab atcol1.)
                if !cells.isEmpty, widthless == cells.count, style.width != nil, style.widthPercent == nil, equalGrid, !style.fixedLayout { style.contentFit = true }
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
                if style.widthPercent != nil, !style.fixedLayout {
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
                                if _on(tc.first("w:tcPr")?.first("w:noWrap")) { noWrap.insert(col) }
                            } else if span > 1, w?["w:type"] == "pct", (style.cellSpacing ?? 0) == 0 {
                                // (A cell across columns says nothing of any one.)
                            } else if w != nil, w?["w:type"] != "auto" { mixed = true }
                            col += span
                        }
                    }
                    // (A table of no cell spacing keeps its shares only: its no-wrap columns are the layout's
                    // wrap rule for spaced tables (`noWrapColumns`), and eleven documents' unspaced pct
                    // tables moved when they were set on those too.)
                    if !mixed, !shares.isEmpty {
                        style.columnPercents = shares
                        if (style.cellSpacing ?? 0) > 0 { style.noWrapColumns = noWrap }
                    }
                }
                if style != TableStyle() { tableStyles[id] = style }
                // vMerge: "restart" opens a span in a column; a bare vMerge
                // continues it, and that cell's (empty) content is dropped.
                var openSpan: [Int: Range<Int>] = [:]   // column → the spanning cell's paragraphs
                let rowCount = unwrapped(node, "w:tr").count
                let gridCount = tableColumns[id]?.count ?? Int.max
                // (A cell merged down into a row sets that row's top and
                // bottom margins where its own are the larger: lab `rgap`
                // (Word for Windows, zh-147bdae0's p19 table alone) — row 2's
                // continued "其他參與人員" states no margins and takes the
                // table's 108 twips above and below, every other cell says 0,
                // and Word sets the row's text 5.4pt lower and the row 5.4pt
                // deeper; with the continued cell's margins 0, or the
                // table's, it does not. Ours set the row as its own cells say.)
                let tableStart = paragraphs.count
                var continuedMargins: [Int: (top: Double, bottom: Double)] = [:]
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
                                // (Its margins, as an own cell's are read below.)
                                let m = tcPr?.first("w:tcMar") != nil ? _cellMargins(tcPr, "w:tcMar").under(margins)
                                    : !cellMars.isEmpty && (cellMar.top != nil || cellMar.left != nil || cellMar.bottom != nil || cellMar.right != nil)
                                    ? _cellMargins(tr.first("w:tblPrEx")).under(_cellMargins(node.first("w:tblPr"))).under(styled).under(defaultMargins).under(_Margins.word)
                                    : _cellMargins(tr.first("w:tblPrEx")).under(margins)
                                let was = continuedMargins[r] ?? (0, 0)
                                continuedMargins[r] = (max(was.top, m.top ?? 0), max(was.bottom, m.bottom ?? 0))
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
                                // A rule with no w:sz: Word prints a hairline
                                // and the row does not grow (463426 page 8).
                                if e["w:sz"] == nil, e["w:val"] != "nil", e["w:val"] != "none" { continue }
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
                        // (A cell with no vAlign of its own takes its table style's: jpn-z22306877-1047a4's Table1.)
                        let vAlign = tcPr?.first("w:vAlign")?["w:val"].flatMap { ["center", "bottom"].contains($0) ? $0 : nil } ?? (tcPr?.first("w:vAlign") == nil ? ((r == 0 && firstRowOn ? cond.headerVAlign : nil) ?? cond.cellVAlign) : nil)
                        currentCell = CellRef(table: id, row: r, column: column, span: span, fill: fill, edges: ownEdges, verticalAlign: vAlign)
                        rowExcepted = tr.first("w:tblPrEx")?.first("w:tblCellMar") != nil
                        if let rev = tcPr?.first("w:cellDel") ?? tcPr?.first("w:cellIns") {
                            currentCell?.revision = RevisionMark(kind: rev.name == "w:cellIns" ? .inserted : .deleted, author: rev["w:author"] ?? "",
                                                                 date: rev["w:date"] ?? "", moved: false)
                        }
                        currentCell?.bordersXML = tcPr?.first("w:tcBorders").map { PptxXML.serialize($0) }
                        // A side the cell rules at a width of its own is drawn
                        // at that width, in its colour (auto is black):
                        // zh-cec9d337's outer frame is 2.25pt over the
                        // table's 0.5pt, stated by its rows' `w:tblPrEx`.
                        if RichTextTheme.wordWindowsPages, let tb = sidesPr?.first("w:tcBorders") {
                            func own(_ names: [String]) -> CellRef.CellLine? {
                                for n in names {
                                    guard let e = tb.first(n), !["nil", "none"].contains(e["w:val"] ?? "nil"), let sz = Double(e["w:sz"] ?? "") else { continue }
                                    let width = max(0.25, sz / 8)
                                    // (A table whose width came from its cells' own lines draws each cell's side as it states it:
                                    // lo-c657ba7d's rows say 4.5pt navy on some sides and 1pt on others, the table's width the
                                    // 4.5 they mostly name, so those sides were left to the table's edges and drew nothing;
                                    // Word's print has the heavy rules between the rows.)
                                    guard (e["w:val"] ?? "single") == "single", width != (style.borderWidth ?? 0.5) || (style.bordersFromCells && width > 1) else { return nil }
                                    var color = Color(0xFF000000)
                                    if let hex = e["w:color"], hex.lowercased() != "auto", hex.count == 6, let v = Int(hex, radix: 16) {
                                        color = Color(argb: 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF)
                                    }
                                    return CellRef.CellLine(width: width, color: color)
                                }
                                return nil
                            }
                            currentCell?.borders.top = own(["w:top"])
                            currentCell?.borders.left = own(["w:left", "w:start"])
                            currentCell?.borders.bottom = own(["w:bottom"])
                            currentCell?.borders.right = own(["w:right", "w:end"])
                        }
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
                        // (The strict spelling "lr" turns the text up in Word's
                        // print — LibreOffice's tdf79272_strictDxa: "USA" in a
                        // 34.55pt column runs bottom to top, where ours set it
                        // flat and made the column 41pt.)
                        case "btLr", "lr": currentCell?.textDirection = .up
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
                        if let sid = node.first("w:tblPr")?.first("w:tblStyle")?["w:val"] {
                            if r == 0, firstRowOn, let hb = headerBases[sid], let hr = headerRootBases[sid] { cellBase = hb; cellRootBase = hr }
                            else if let tb = tableBases[sid], let tr = tableRootBases[sid] { cellBase = tb; cellRootBase = tr }
                        }
                        notes.cellSizeFromTable = false
                        if cellChar.fontSize == nil, !normalStatesSize, let size = tableStyleSize { cellChar.fontSize = size; notes.cellSizeFromTable = true }
                        notes.cellCharFromTable = tableStyleChar.map { _takeTableChar(&cellChar, $0, normal: normalStatedChar) } ?? []
                        let before = paragraphs.count
                        for child in tc.children { walkBlock(child, indent: indent, depth: depth + 1) }
                        if paragraphs.count == before { emit(RichParagraph(style: cellBase)) }
                        else { flagMarkUnderNestedTable(tc, since: before) }
                        if restart { openSpan[column] = before ..< paragraphs.count }
                        column += span
                    }
                }
                // (A merged cell's own foot is in its last row, and that
                // row's margin is its own continuation's: zh-147bdae0's
                // centred "其他參與人員" stands 2.7pt higher in Word's print,
                // half the 5.4 its continued part takes off below.)
                for k in tableStart ..< paragraphs.count {
                    guard let cell = paragraphs[k].cell, cell.table == id else { continue }
                    if let t = continuedMargins[cell.row]?.top, t > 0 { paragraphs[k].cell?.rowMarginTop = t }
                    if let b = continuedMargins[cell.row + max(1, cell.rowSpan) - 1]?.bottom, b > 0 { paragraphs[k].cell?.rowMarginBottom = b }
                }
                currentCell = nil
                cellChar = CharStyle()
            case "w:sdt":
                if let content = node.first("w:sdtContent") {
                    for child in content.children { walkBlock(child, indent: indent) }
                }
            case "w:bookmarkStart":
                if let name = node["w:name"], name != "_GoBack" {
                    notes.pendingBookmarks.append(name)
                    if let id = node["w:id"] { notes.pendingBookmarkMarkers.append(RichBookmarkMarker(id: id, name: name, offset: 0)) }
                }
            case "w:bookmarkEnd":
                if let id = node["w:id"] {
                    if notes.pendingBookmarkMarkers.contains(where: { $0.id == id }) {
                        notes.pendingBookmarkMarkers.append(RichBookmarkMarker(id: id, offset: 0))
                    } else if !paragraphs.isEmpty {
                        let i = paragraphs.count - 1
                        paragraphs[i].bookmarkMarkers.append(RichBookmarkMarker(id: id, offset: paragraphs[i].length))
                    }
                }
            case "w:commentRangeStart":
                // A range may open or close between paragraphs
                // (WordWithAttachments), not only inside one.
                if notes.kept["word/comments.xml"] != nil, let id = node["w:id"] { notes.openComments.append(id); notes.seenComments.insert(id) }
            case "w:commentRangeEnd":
                if let id = node["w:id"] { notes.openComments.removeAll { $0 == id } }
            case "w:sectPr":
                pageSetup = _pageSetup(node, notes)
            case "w:altChunk":
                // An HTML chunk, as Word imports it: paragraphs of the markup's
                // text in Times New Roman 12, 14pt of auto spacing either side
                // (lo alt-chunk-html: "HTML AltChunk" 13.3pt tall, 31.4 under the
                // line before it and 27.4 over the line after, in Word's print).
                if let id = node["r:id"], let rel = notes.rels[id], !rel.external,
                   ["html", "htm", "xhtml"].contains(rel.target.split(separator: ".").last.map { $0.lowercased() } ?? ""),
                   let data = part(_resolvePath("word", rel.target)) {
                    RuleTrace.hit("html-alt-chunk-is-paragraphs")
                    for text in Self._htmlParagraphs(String(decoding: data, as: UTF8.self)) {
                        let run = XNode(name: "w:r", attrs: [:])
                        let rPr = XNode(name: "w:rPr", attrs: [:])
                        rPr.children = [XNode(name: "w:rFonts", attrs: ["w:ascii": "Times New Roman", "w:hAnsi": "Times New Roman", "w:cs": "Times New Roman"]),
                                        XNode(name: "w:sz", attrs: ["w:val": "24"])]
                        let t = XNode(name: "w:t", attrs: ["xml:space": "preserve"])
                        t.text = text
                        run.children = [rPr, t]
                        let pPr = XNode(name: "w:pPr", attrs: [:])
                        pPr.children = [XNode(name: "w:spacing", attrs: ["w:before": "280", "w:after": "280"])]
                        let para = XNode(name: "w:p", attrs: [:])
                        para.children = [pPr, run]
                        walkBlock(para, indent: indent, depth: depth)
                    }
                }
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
                        // (When the paragraph opening the column is that empty
                        // line itself — the reader keeps the break's mark as a
                        // paragraph of its own — the one before it is only
                        // taken out of the first column, not carried on: set
                        // twice, the title stood 26pt low in zh-6cd1befe, and
                        // left in the first column its line ran zh-8f9b19f4's
                        // section 8pt long.)
                        let opensWithItsMark = q.text.isEmpty && q.image == nil && notes.columnMarksFollow
                        if q.style.breakEndsPrevious, let prev = columns[columns.count - 1].last, prev.text.isEmpty, prev.image == nil,
                           columns[columns.count - 1].count > 1 {
                            let taken = columns[columns.count - 1].removeLast()
                            if !opensWithItsMark { carried = taken }
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
        // (Not after a section's columns set as a table: that is no table in
        // Word, its last column's paragraph ends the page, and the line added
        // here ran past a page foot of no margin onto a page of its own —
        // zh-8f9b19f4's landscape last page, 14 pages for Word's 13.)
        if paragraphs.isEmpty || (paragraphs.last?.cell.map({ tableStyles[$0.table]?.sectionColumns != true }) ?? false) { paragraphs.append(RichParagraph()) }
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
                _bindCoreProperties(node, part: part)
                // (Their theme font references too: zh-a4b0f6ea's page
                // numbers are `majorEastAsia`, 宋体, in a footer.)
                _resolveThemeFonts(node, theme)
                Self._resolveShareWidths(node.descendants("wp:anchor"), body.first("w:sectPr") ?? earlier.last)
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
                guard type == "separator" || notes.footnoteNumbers[id] != nil || notes.customFootnotes.contains(id) else { continue }
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
                guard type == "separator" || notes.endnoteNumbers[id] != nil || notes.customEndnotes.contains(id) else { continue }
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
        document.endnotesAtSectionEnd = part("word/settings.xml").flatMap(XNode.parse)?.first("w:endnotePr")?.first("w:pos")?["w:val"] == "sectEnd"
        // (Endnotes too long to stand under the last paragraph run on over the pages after it, as Word's do — urd-z8387389's
        // 58 notes are three pages of its 12 — so they are flowed as paragraphs of their own, in the order of their marks,
        // after a separator line's height. The painter that sets short ones under the last paragraph drops any that do not
        // fit it whole.)
        if !document.endnotesAtSectionEnd, !endnoteParagraphs.isEmpty {
            var order: [Int] = []
            for p in paragraphs { for run in p.runs { if let n = run.style.note, n.kind == .endnote, endnoteParagraphs[n.id] != nil, !order.contains(n.id) { order.append(n.id) } } }
            let characters = order.reduce(0) { $0 + (endnoteParagraphs[$1] ?? []).reduce(0) { $0 + $1.text.utf16.count } }
            if characters > 1500 {
                RuleTrace.hit("endnotes-flowed-after-body")
                var flowed: [RichParagraph] = []
                for var p in endnoteSeparator { p.flowedEndnote = -1; flowed.append(p) }
                for id in order { for var p in endnoteParagraphs[id] ?? [] { p.flowedEndnote = id; flowed.append(p) } }
                document.paragraphs.append(contentsOf: flowed)
                document.endnotes = [:]
            }
        }
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
            if let tc = bg["w:themeColor"] {
                // (Word prints the theme slot, not the w:color fallback; a tint or shade moves its HSL lightness, and
                // with both present only the tint shows: lab bg 1-6, accent2 ED7D31 -> F7CAAC / C45911 / F4B083.)
                if let v = _themeBackground(tc, tint: bg["w:themeTint"], shade: bg["w:themeShade"]), v != 0xFFFFFF { document.backgroundColor = v }
            } else if let c = bg["w:color"], c.count == 6, let v = UInt32(c, radix: 16), v != 0xFFFFFF { document.backgroundColor = v }
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
                let verticalDoc = ["tbRl", "tbRlV"].contains(sect.first("w:textDirection")?["w:val"] ?? "")
                if let type = grid["w:type"], type == "lines" || type == "linesAndChars" || (type == "snapToChars" && verticalDoc), let pitch = Double(grid["w:linePitch"] ?? ""), pitch > 0 {
                    document.lineGridPitch = pitch / 20
                }
                // (A grid of characters that adds nothing to them is a grid
                // all the same: its lines hold whole characters — zh-18cb2079,
                // linesAndChars with no charSpace, sets 27 of 16pt in a
                // 442pt column in Word's print, where ours squeezed three
                // marks for a 28th. A hair stands for none.)
                if grid["w:type"] == "linesAndChars" || (grid["w:type"] == "snapToChars" && ["tbRl", "tbRlV"].contains(sect.first("w:textDirection")?["w:val"] ?? "")) {
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
                document.chapterStyle = Int(num["w:chapStyle"] ?? "")
                document.chapterSeparator = num["w:chapSep"]
            }
            document.sectionTailXML = tail.isEmpty ? nil : tail
        }
        // (A file with no settings at all, or no styles, is set by the
        // East Asian rules: Word reads it as one of its older documents.)
        if part("word/settings.xml") == nil { document.usesEastAsianLayout = true }
        // (Kana in the body text, UTF-8 E3 81..83 xx: a Japanese document whatever its language tag says.)
        do {
            var kana = false
            var prev: UInt8 = 0
            for byte in docData {
                if prev == 0xE3, byte >= 0x81, byte <= 0x83 { kana = true; break }
                prev = byte
            }
            document.hasKana = kana
        }
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
            // (The Latin faces a file embeds that Word for Windows lacks: all four styles under one family.
            // jpn-z22306877's Libre Baskerville and Crimson Text, which Word prints.)
            if Self.wordOnWindows {
                for font in table.all("w:font") {
                    guard let name = font["w:name"], OfficeFonts.embeddedLatinWanted(name), faces[name] == nil else { continue }
                    var family: String? = nil
                    for tag in ["w:embedRegular", "w:embedBold", "w:embedItalic", "w:embedBoldItalic"] {
                        guard let embed = font.first(tag), let rid = embed["r:id"], let key = embed["w:fontKey"], let target = faceTargets[rid] else { continue }
                        let path = target.hasPrefix("/") ? String(target.dropFirst()) : "word/" + target
                        guard let raw = part(path), let data = OfficeFonts.deobfuscate(raw, key: key),
                              OfficeFonts.coversLatinLetters(data),
                              let f = OfficeFonts.loadEmbedded(data, sharedFamily: "Starling Embedded Latin " + name) else { continue }
                        family = f
                    }
                    if let family { faces[name] = family }
                }
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
            document.fontCharsets = Dictionary(entryCharsets.map { ($0.key.trimmingWhitespace().lowercased(), $0.value) }, uniquingKeysWith: { a, _ in a })
            document.fontUsb0 = Dictionary(entries.compactMap { e in e.value.usb0.map { (e.key.trimmingWhitespace().lowercased(), $0) } }, uniquingKeysWith: { a, _ in a })
            document.fontAlternates = Dictionary(alts.map { ($0.key.trimmingWhitespace().lowercased(), $0.value.trimmingWhitespace().lowercased()) }, uniquingKeysWith: { a, _ in a })
            OfficeFonts.noteAltNames(alts)
            OfficeFonts.noteFontEntries(entries)
            document.hasIndicText = Self._hasIndicBytes(docData)
            OfficeFonts.noteIndicText(document.hasIndicText)
        } else {
            OfficeFonts.noteEmbedded([])
            OfficeFonts.noteEmbeddedFaces([:])
            OfficeFonts.noteAltNames([:])
            OfficeFonts.noteFontEntries([:])
            OfficeFonts.noteIndicText(false)
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
        var legacyNoFE = false
        if let settings = part("word/settings.xml").flatMap(XNode.parse) {
            legacyNoFE = settings.first("w:compat")?.first("w:useFELayout") == nil
            document.themeFontLangXML = settings.first("w:themeFontLang").map { PptxXML.serialize($0) }
            document.characterSpacingControl = settings.first("w:characterSpacingControl")?["w:val"]
            document.kernsPunctuation = settings.first("w:noPunctuationKerning").map { _isOff($0) } ?? true
            document.htmlAutoSpacing = !(settings.first("w:compat")?.first("w:doNotUseHTMLParagraphAutoSpacing").map { !_isOff($0) } ?? false)
            document.usesEastAsianLayout = settings.first("w:compat")?.first("w:useFELayout").map { !_isOff($0) }
                ?? (part("word/styles.xml") == nil)
            document.doesNotExpandShiftReturn = settings.first("w:compat")?.first("w:doNotExpandShiftReturn").map { !_isOff($0) } ?? false
            document.indentNotNumberingTabStop = settings.first("w:compat")?.first("w:doNotUseIndentAsNumberingTabStop").map { !_isOff($0) } ?? false
            document.balancesSpaceWidth = settings.first("w:compat")?.first("w:balanceSingleByteDoubleByteWidth").map { !_isOff($0) } ?? false
            document.underlinesTrailingSpaces = settings.first("w:compat")?.first("w:ulTrailSpace").map { !_isOff($0) } ?? false
            document.spacesForUnderline = settings.first("w:compat")?.first("w:spaceForUL").map { !_isOff($0) } ?? false
            document.adjustsLineHeightInTable = settings.first("w:compat")?.first("w:adjustLineHeightInTable").map { !_isOff($0) } ?? false
            document.leavesColumnsUnbalanced = settings.first("w:compat")?.first("w:noColumnBalance").map { !_isOff($0) } ?? false
            document.suppressesTopSpacing = settings.first("w:compat")?.first("w:suppressTopSpacing").map { !_isOff($0) } ?? false
            document.hangsHalf = settings.first("w:compat")?.first("w:useAltKinsokuLineBreakRules").map { !_isOff($0) } ?? false
            document.breakRulesOnlyForEastAsian = settings.first("w:compat")?.first("w:doNotUseEastAsianBreakRules").map { !_isOff($0) } ?? false
            document.doNotBreakWrappedTables = settings.first("w:compat")?.first("w:doNotBreakWrappedTables").map { !_isOff($0) } ?? false
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
        } else if part("word/settings.xml") == nil, part("word/styles.xml") != nil {
            // (A file with no settings part names no compatibility mode either; a copy of
            // jpn-z23823926-b2a8e5 with an empty w:compat added went from 55.4 to 99.0.)
            document.hangsLatinStops = true
            document.usesEastAsianLayout = true
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
                // (Not where the body itself names an East Asian language on a run:
                // docx-79737edb's runs say ja-JP/ko-KR/zh-CN and Word keeps its line-start ban.)
                if let d = part("word/document.xml"), String(decoding: d, as: UTF8.self).containsSubstring("<w:lang ") {
                    document.bodyStatesLang = true
                }
            }
            let normal = styles.all("w:style").first { $0["w:type"] == "paragraph" && ($0["w:default"] == "1" || $0["w:styleId"] == "Normal") }
            let own = normal?.first("w:rPr")?.first("w:lang")
            let defaults = styles.first("w:docDefaults")?.first("w:rPrDefault")?.first("w:rPr")?.first("w:lang")
            // (`RichDocument.joinsHanAfterSpace`.)
            // (hangsLatinStops is set only for a file with no compatibility mode and
            // no useFELayout: WPS and Chinese Word files carry useFELayout and keep a Han run whole.)
            // (A theme East Asian font keeps the rule for a file that does carry useFELayout: zh-7773163d.)
            let defaultEastAsia = styles.first("w:docDefaults")?.first("w:rPrDefault")?.first("w:rPr")?.first("w:rFonts")?["w:eastAsiaTheme"]
            // (Word-win prints of dx2 6ddc0960, 236cd3ae, f8ff8a48, 2a9d6c3a: a compat 12 file without
            // useFELayout also breaks after "3. " when the Han text after it overflows.)
            // (Mode 12 only: the four dx2 files with this behaviour are all compat 12; zh-202582e2, compat 14 with the same
            // en-US languages, breaks inside the Han stretch.)
            let legacyCompat = document.compatibilityMode == 12 && legacyNoFE
            document.joinsHanAfterSpace = legacyCompat || document.compatibilityMode == nil
                && (document.hangsLatinStops || ["minorHAnsi", "majorHAnsi", "minorAscii", "majorAscii"].contains(defaultEastAsia ?? ""))
            if let own, let defaults {
                document.defaultLangXML = PptxXML.serialize(XNode(name: own.name, attrs: defaults.attrs.merging(own.attrs) { _, mine in mine }))
            } else if let lang = own ?? defaults {
                document.defaultLangXML = PptxXML.serialize(lang)
            }
            // (Lab hang3, compat 14: Word hangs a Latin line-end , . ; ) } only with eastAsia zh-CN AND the minorEastAsia theme face;
            // either one removed, or both, and the stop wraps.)
            document.hangsStopsMinorEA = defaultEastAsia == "minorEastAsia"
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

    /// A content control bound to a core property (the title, the author
    /// …: a cover page's) shows the property, not what the file cached —
    /// and its placeholder text where the property is empty. Lab-free:
    /// lo-9106c8eca7363cbc (fdo67013), a header's "Title" control cached
    /// "Sample Doc 002" over an empty `dc:title`; Word's print has
    /// "[Type the document title]".
    private static func _bindCoreProperties(_ root: XNode, part: (String) -> Data?) {
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
        func walk(_ node: XNode) {
            if node.name == "w:p" { titleFields(node) }
            if node.name == "w:sdt", let pr = node.first("w:sdtPr"), let bind = pr.first("w:dataBinding"),
               bind["w:storeItemID"]?.uppercased() == "{6C3C8BC8-F283-45AE-878A-BAB7291924A1}",
               let xpath = bind["w:xpath"], let last = xpath.split(separator: "/").last,
               let content = node.first("w:sdtContent") {
                let local = String(last.split(separator: "[").first ?? "").split(separator: ":").last.map(String.init) ?? ""
                if core == nil { core = .some(part("docProps/core.xml").flatMap(XNode.parse)) }
                guard let props = core ?? nil else { return }
                var value = props.children.first { $0.name.hasSuffix(":" + local) }?.text ?? ""
                value = value.trimmingWhitespace(newlines: true)
                var placeholderRun: XNode?
                if value.isEmpty {
                    guard let name = pr.first("w:placeholder")?.first("w:docPart")?["w:val"], !name.isEmpty else { return }
                    if glossary == nil { glossary = .some(part("word/glossary/document.xml").flatMap(XNode.parse)) }
                    guard let g = glossary ?? nil,
                          let docPart = (g.first("w:docParts")?.all("w:docPart") ?? []).first(where: { $0.first("w:docPartPr")?.first("w:name")?["w:val"] == name }),
                          let body = docPart.first("w:docPartBody") else { return }
                    var shown: [XNode] = []
                    texts(body, &shown)
                    value = shown.map { $0.text }.joined()
                    if value.isEmpty { return }
                    placeholderRun = body.descendants("w:r").first
                }
                var runs: [XNode] = []
                texts(content, &runs)
                guard let first = runs.first else { return }
                RuleTrace.hit("core-bound-control-shows-the-property")
                first.text = value
                // (The placeholder shows in its own formatting, not that of the text the control held:
                // lo-c657ba7d's title, bold orange "Communication digitale" in the file, is "[Titre du
                // document]" in the glossary's plain 16pt black in Word's print.)
                if let ph = placeholderRun, let run = content.descendants("w:r").first(where: { $0.children.contains { $0 === first } }) {
                    run.children.removeAll { $0.name == "w:rPr" }
                    if let rpr = ph.first("w:rPr") { run.children.insert(rpr, at: 0) }
                }
                for r in runs.dropFirst() { r.text = "" }
                return
            }
            for child in node.children { walk(child) }
        }
        walk(root)
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
    private static func _preservesField(_ instr: String) -> Bool {
        let word = instr.split(whereSeparator: { $0.isWhitespace }).first?.uppercased() ?? ""
        return ["AUTHOR", "DATE", "DOCPROPERTY"].contains(word)
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
        // (A VML ellipse sets its text in the inscribed rectangle, as the
        // type 3 shape does: lo-ff3b52d1's oval, Word's text 15.4pt in.)
        if node.name == "v:oval" || (node.descendant("v:shape") == nil && node.descendant("v:oval") != nil) {
            return Rect.fromLTRB(3163 / 21600, 3163 / 21600, 18437 / 21600, 18437 / 21600)
        }
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
        let topGroup = group
        func walk(_ group: XNode, _ map: @escaping (Rect) -> Rect) {
            let origin = pair(group["coordorigin"], (0, 0)), size = pair(group["coordsize"], (1000, 1000))
            guard size.0 > 0, size.1 > 0 else { return }
            for child in group.children {
                let sh = style(child)
                guard let x = sh["left"].flatMap({ Double($0) }), let y = sh["top"].flatMap({ Double($0) }),
                      let w = sh["width"].flatMap({ Double($0) }), let h = sh["height"].flatMap({ Double($0) }) else { continue }
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
                                sh["v-text-anchor"]?.hasPrefix("bottom") == true))
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
            f.wraps = ["wp:wrapSquare", "wp:wrapTight", "wp:wrapThrough"].contains { anchor.first($0) != nil }
            f.wrapsTight = anchor.first("wp:wrapTight") != nil || anchor.first("wp:wrapThrough") != nil
            if let w = ["wp:wrapSquare", "wp:wrapTight", "wp:wrapThrough"].lazy.compactMap({ anchor.first($0) }).first,
               let side = w["wrapText"], side == "left" || side == "right" || side == "largest" { f.wrapSide = side }
            // (A tight wrap's polygon with a cut corner at the top: the right edge reaches its full
            // reach a few points down, and a line over that stretch is held in by less than the
            // box. lo tdf163575: 1072 of 21600 down on a 181pt picture, Word's first line at 190.4
            // over a picture ending at 199.9.)
            if let tight = anchor.first("wp:wrapTight"), let polygon = tight.first("wp:wrapPolygon"), let ext = anchor.first("wp:extent"),
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
            }
            Self._bandPage(&f)
            if let b = Double(anchor.first("wp:effectExtent")?["b"] ?? "") { f.effectBottom = b / 12700 }
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
                case "mso-position-horizontal-relative": f.horizontalFrom = value == "text" ? "column" : value
                case "mso-position-vertical-relative": f.verticalFrom = value == "text" ? "paragraph" : value
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
        // (A fill written with a leading "#" — `#ff00ff`, as lo-f17a56168c9e's Title
        // style has it — prints as that colour in Word.)
        if let shd = pPr.first("w:shd"), let raw = shd["w:fill"], case let hex = raw.hasPrefix("#") ? String(raw.dropFirst()) : raw,
           hex.lowercased() != "auto", hex.count == 6, let v = Int(hex, radix: 16) {
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
            let b = ParagraphBorders(top: side("w:top", old?.top), bottom: side("w:bottom", old?.bottom), left: side("w:left", old?.left), right: side("w:right", old?.right))
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

    private static func _pageSetup(_ sect: XNode, _ notes: _Shared? = nil) -> PageSetup? {
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
            numbering.start = Int(ln["w:start"] ?? "") ?? 1
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
        if let cols = sect.first("w:cols") {
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
        }
        // (A right-to-left section sets its columns from the right: its first
        // column is the rightmost, lo-998868b6's "RTL 1".)
        if let bidi = sect.first("w:bidi"), bidi["w:val"] != "0", bidi["w:val"] != "false", setup.columns > 1 { setup.rtlColumns = true }
        if let grid = sect.first("w:docGrid") {
            // (A top-to-bottom section's snapToChars grid also holds its columns to linePitch: dx2 4427518d's print steps 33.7 pt, 671 twips.)
            let verticalSection = ["tbRl", "tbRlV"].contains(sect.first("w:textDirection")?["w:val"] ?? "")
            if let type = grid["w:type"], type == "lines" || type == "linesAndChars" || (type == "snapToChars" && verticalSection), let pitch = Double(grid["w:linePitch"] ?? ""), pitch > 0 {
                setup.lineGridPitch = pitch / 20
            }
            if grid["w:type"] == "linesAndChars" || (grid["w:type"] == "snapToChars" && ["tbRl", "tbRlV"].contains(sect.first("w:textDirection")?["w:val"] ?? "")) {
                let space = Double(grid["w:charSpace"] ?? "") ?? 0
                setup.characterGridSpace = space != 0 ? space / 4096 : 1e-6
            }
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
    private static func _headerWrapLeft(_ sect: XNode, _ setup: PageSetup, _ notes: _Shared) -> Double {
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

    private struct _Built {
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
        fileprivate var seenFootnotes = 0, seenEndnotes = 0
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
        /// The cell's run base's other properties taken from the table's
        /// style (`_takeTableChar`), which a paragraph style stating its own
        /// takes back.
        var cellCharFromTable = Set<String>()
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
        var pendingBookmarkMarkers: [RichBookmarkMarker] = []
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
        var fieldCount = 0
        /// Every style's name, lowercased, and the fields whose STYLEREF
        /// error has been written: a STYLEREF naming no style prints Word's
        /// error, not the result it was saved with.
        var styleNames = Set<String>()
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
            if footnote { if footnoteRestarts.contains(id) { seenFootnotes = 0 }; seenFootnotes += 1; return seenFootnotes }
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
        /// The style's own cell vertical alignment (`w:tcPr/w:vAlign`, centre or bottom).
        var cellVAlign: String? = nil
        /// The firstRow part's own cell vertical alignment (acd729's pandoc "Table").
        var headerVAlign: String? = nil
        var headerChar: CharStyle? = nil
        var firstColChar: CharStyle? = nil
        var band1: Color? = nil
        var band2: Color? = nil
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
    private static func _borders(_ pr: XNode?, _ tag: String, lost: Set<String> = []) -> _Borders? {
        guard let b = pr?.first(tag), !b.children.isEmpty else { return nil }
        let drawn = b.children.filter { !["nil", "none"].contains($0["w:val"] ?? "nil") }
        guard let first = drawn.first else { return _Borders(on: false, color: nil) }
        var color: Color? = nil
        // An edge the neighbour's edge beats names no colour for the cell.
        let kept = drawn.filter { !lost.contains($0.name) }
        if let hex = kept.first(where: { ($0["w:color"] ?? "auto").lowercased() != "auto" })?["w:color"] ?? kept.first?["w:color"],
           hex.lowercased() != "auto", hex.count == 6, let v = Int(hex, radix: 16) {
            color = Color(argb: 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF)
        }
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
    private static func _lostCellEdges(rows: [[XNode]]) -> [ObjectIdentifier: Set<String>] {
        func rank(_ e: XNode) -> (Double, Double)? {
            guard !["nil", "none"].contains(e["w:val"] ?? "nil") else { return nil }
            let w = Double(e["w:sz"] ?? "") ?? 0
            let c = (e["w:color"] ?? "auto").lowercased()
            var lum = 0.0
            if c.count == 6, let v = Int(c, radix: 16) {
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

    /// The cell margins of the DEFAULT table style. Word ignores a default style's
    /// zero left and right (lab fitedge c00-c05, Windows prints: a table whose
    /// style is the default one with margins 0 is set out by 5.4 pt all the
    /// same, in compat 14 and 15, schema order or not); a non-default style's
    /// zero is honoured (zh-dc9cfa34, zh-147bdae0).
    private static func _defaultStyleMargins(_ style: XNode) -> _Margins {
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

    private static func _themeFonts(_ entries: [ZipEntry]) -> ThemeFonts {
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
        default: nil
        }
        func complex(_ name: String) -> String? {
            guard let font = scheme.first(name) else { return nil }
            if let f = font.first("a:cs")?["typeface"], !f.isEmpty { return f }
            if let bidiScript, let f = font.all("a:font").first(where: { $0["script"] == bidiScript })?["typeface"], !f.isEmpty { return f }
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
    private static func _renumberSequences(_ root: XNode) {
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
    private static func _refreshReferences(_ root: XNode) {
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
    private static func _hoistTablesOutOfParagraphs(_ root: XNode) {
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

    private static func _normaliseStyleIds(_ styles: XNode) {
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

    private static func _resolveThemeFonts(_ root: XNode, _ theme: ThemeFonts) {
        guard !theme.isEmpty else { return }
        var stack = [root]   // iterative: a fuzzer's tree is deeper than the call stack
        while let node = stack.popLast() {
            if node.name == "w:rFonts" {
                for (ref, attr) in [("w:asciiTheme", "w:ascii"), ("w:hAnsiTheme", "w:hAnsi"), ("w:eastAsiaTheme", "w:eastAsia"), ("w:cstheme", "w:cs")] {
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
        var sectionMarginsChange = false
        // (The table style's size stands under the paragraph's own style:
        // zh-e2dc9dce's flow table, styled at 10pt, sets its "01 標題壹"
        // headings at that style's 14pt in Word's print.)
        var cellChar = cellChar
        if notes.cellSizeFromTable, let id = p.first("w:pPr")?.first("w:pStyle")?["w:val"], let ours = styleIds[id],
           sheet[ours]?.char.fontSize != nil {
            cellChar.fontSize = nil
        }
        if !notes.cellCharFromTable.isEmpty, let id = p.first("w:pPr")?.first("w:pStyle")?["w:val"], let ours = styleIds[id],
           let named = sheet[ours]?.char {
            _dropTableChar(&cellChar, stated: named, took: notes.cellCharFromTable)
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
            // (A paragraph whose first run only opens a field and has no size of
            // its own: Word counts its first-line characters in the style's
            // size, not the first text's — zh-c2c92639 p8, "4.1" 3.1 pt in.)
            if let r0 = p.first("w:r"), r0.first("w:fldChar") != nil, r0.first("w:rPr")?.first("w:sz") == nil {
                style.eastAsian["w:fieldFirst"] = "1"
            }
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
            if let change = pPr.first("w:pPrChange") {
                style.propertyChange = FormatChange(author: change["w:author"] ?? "", date: change["w:date"] ?? "",
                                                    oldRPrXML: change.first("w:pPr").map { PptxXML.serialize($0) } ?? "")
            }
            if let rPr = pPr.first("w:rPr") {
                // (The mark's character style first, then its own properties, as a run's:
                // tdf158597's "Char style mark" is plain text over an Emphasis 16pt mark,
                // and Word's line stands as tall as the mark.)
                var mark = cellChar
                if let id = rPr.first("w:rStyle")?["w:val"], let chain = notes.charStyleChains[id] {
                    for styled in chain { mark = _charStyle(styled, base: mark) }
                }
                markStyle = _charStyle(rPr, base: mark)
            }
            if markStyle?.hidden == true { style.markHidden = true }
            if style.markHidden, _on(pPr.first("w:rPr")?.first("w:specVanish")) { style.markSpecVanish = true }
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
            // (A numbered paragraph that holds nothing but a page break prints no label in Word for Windows:
            // zh-7488a70f's empty "六、" item before "肆、討論事項" (numId 24, only <w:br w:type="page"/>) is a
            // blank line at the paragraph's own position in the print, and ours set "六、" 8.5pt lower.)
            let onlyPageBreak = DocxFormat.wordOnWindows && p.descendant("w:br").map { $0["w:type"] == "page" } == true
                && p.descendants("w:t").allSatisfy { $0.text.allSatisfy { $0 == " " || $0 == "\n" } }
                && p.descendant("w:drawing") == nil && p.descendant("w:pict") == nil && p.descendant("w:tab") == nil
            if let (numId, ilvl) = num, !onlyPageBreak {
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
                    // (A level and a paragraph that state no first line, the
                    // paragraph saying a count of none, leave the style's twips
                    // in force: zh-60173bb6's "(2)" items start 27.8pt in.)
                    if DocxFormat.wordOnWindows, style.listFirstLine == nil, style.firstLineIndent > 0,
                       pPr.first("w:ind")?["w:firstLineChars"] == "0", pPr.first("w:ind")?["w:firstLine"] == nil,
                       notes.listFormats[numId]?[ilvl]?.hanging == nil {
                        RuleTrace.hit("word-list-item-keeps-the-styles-first-line")
                        style.listFirstLine = style.firstLineIndent
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
                sectionMarginsChange = sect.attrs.removeValue(forKey: "x-next-vmargins") == "1"
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
        var bookmarkMarkers: [RichBookmarkMarker] = []
        var runs: [Run] = []
        var positionalTabs: [Int: TabStop.Alignment] = [:]
        var inlineImages: [String: ImageAttachment] = [:]
        var leadingBreak = false   // the paragraph opens with a page break
        var cellBreakOpens = false   // …in a table cell, where the break itself is dropped
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
                // (An empty cell paragraph under a table style that sets the size is as tall as that
                // size, not Normal's: lo-7c394e05's 8pt cells under a 12pt Normal.)
                let emptyInStyledCell = markStyle == nil && notes.cellSizeFromTable && cellChar.fontSize != nil
                if text.isEmpty, inlineImages.isEmpty, markStyle != nil || emptyInStyledCell || !notes.openComments.isEmpty {
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
            para.bookmarkMarkers = notes.pendingBookmarkMarkers + bookmarkMarkers
            notes.pendingBookmarkMarkers = []
            bookmarkMarkers = []
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
        var runRevision: RevisionMark? = nil  // the change it is in (`w:del`, `w:ins`), for a picture or object in it
        var runFrame: BorderLine? = nil   // ... and its character border, a line of one
        func addInline(_ att: ImageAttachment) {
            var att = att
            att.sourceRunPropertiesXML = runPropertiesXML
            if att.float == nil, att.sourceXML?.containsSubstring("<wp:anchor") != true { att.frame = runFrame }
            inlineImages[att.id] = att
            var cs = CharStyle()
            cs.inlineImage = att.id
            cs.raised = runRaised
            cs.revision = runRevision
            addText(RichParagraph.inlineImageCharacter, cs)
        }
        /// A drawing that is not a picture (a chart, a shape, a diagram), an
        /// embedded object, a VML picture: kept as the file wrote it, with
        /// the parts it names, and shown as an empty box of its size.
        func addObject(_ node: XNode) {
            if var att = objectAttachment(node) { att.inset = Self._canvasInset(node); addInline(att) }
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
                // (Not for Word for Windows' print, which keeps zh-64044a1d's figure at 396.3 — its cell line is
                // the 23 pitches, 414pt, that 396.45 needs, 9.3pt above the picture and 9.4 below — and 410.4 wide.)
                if !isRule, !RichTextTheme.wordWindowsPages, shape.first("v:imagedata") != nil, node.descendant("v:textbox") == nil {
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
               let model = notes.part(_resolvePath("word", dm.target)).flatMap(XNode.parse) {
                var group: XNode? = nil
                if let rid = model.descendant("dsp:dataModelExt")?["relId"], let rel = notes.rels[rid], !rel.external,
                   let drawing = notes.part(_resolvePath("word", rel.target)).flatMap(XNode.parse) {
                    group = Self._diagramGroup(drawing, cx: w * 12700, cy: h * 12700)
                }
                // (No drawing part, as in a file LibreOffice wrote: laid out
                // here from the data and the layout definition, as the deck
                // reader does, and read as the same group of shapes —
                // fdo79822's process diagram printed nothing.)
                if group == nil, let lo = ids["r:lo"].flatMap({ notes.rels[$0] }), !lo.external,
                   let layoutDef = notes.part(_resolvePath("word", lo.target)).flatMap(XNode.parse) {
                    func part(_ key: String) -> XNode? {
                        ids[key].flatMap { notes.rels[$0] }.flatMap { $0.external ? nil : notes.part(_resolvePath("word", $0.target)) }.flatMap(XNode.parse)
                    }
                    if let tree = DiagramLayout.render(data: model, layout: layoutDef, colors: part("r:cs"), style: part("r:qs"),
                                                       frame: Rect.fromLTWH(0, 0, w, h), word: true) {
                        func renamed(_ n: XNode) -> XNode {
                            let c = XNode(name: n.name.hasPrefix("p:") ? "dsp:" + n.name.dropFirst(2) : n.name, attrs: n.attrs)
                            c.text = n.text
                            c.children = n.children.map(renamed)
                            return c
                        }
                        let drawing = XNode(name: "dsp:drawing", attrs: [:])
                        drawing.children = [renamed(tree)]
                        group = Self._diagramGroup(drawing, cx: w * 12700, cy: h * 12700)
                    }
                }
                if let group {
                    graphic.children = [group]
                    graphic.attrs["uri"] = "http://schemas.microsoft.com/office/word/2010/wordprocessingGroup"
                }
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
                    // (An `a:alpha` child is how much of it shows: 0 draws nothing.)
                    func shown(_ c: Color, _ n: XNode?) -> Color {
                        guard RichTextTheme.wordWindowsPages, let a = n?.first("a:alpha")?["val"].flatMap(Double.init) else { return c }
                        return Color((Int64((max(0, min(1, a / 100_000)) * Double(c.alpha)).rounded()) << 24) | Int64(c.value & 0xFFFFFF))
                    }
                    if let clr = fill.first("a:srgbClr"), let hex = clr["val"], let v = Int64(hex, radix: 16) { return shown(Color(0xFF00_0000 | v), clr) }
                    // (A system colour, e.g. window = white: its lastClr.)
                    if let clr = fill.first("a:sysClr"), let hex = clr["lastClr"], let v = Int64(hex, radix: 16) { return shown(Color(0xFF00_0000 | v), clr) }
                    return fill.first("a:schemeClr") != nil ? colors.color(in: fill).map { shown($0, fill.first("a:schemeClr")) } : nil
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
                let saved = (notes.seenFootnotes, notes.seenEndnotes, notes.openComments, notes.pendingBookmarks, notes.pendingBookmarkMarkers, notes.fields,
                             notes.seenComments, notes.fieldShown)
                notes.inTextBox = true
                defer {
                    notes.inTextBox = false
                    (notes.seenFootnotes, notes.seenEndnotes, notes.openComments, notes.pendingBookmarks, notes.pendingBookmarkMarkers, notes.fields,
                     notes.seenComments, notes.fieldShown) = saved
                }
                for shape in node.descendants("wps:wsp") {
                    guard let warp = WriterGroups.textWarp(shape),
                          // (Word for Windows sets a slanted text box that is turned as plain glyphs, turned: zh-b24b396a's
                          // "（全宗名称）" — see `RichTextBox.Part.rotation`.)
                          !(Self.wordOnWindows && warp.preset == "textSlantDown" && shape.first("wps:spPr")?.first("a:xfrm")?["rot"] != nil),
                          let content = shape.first("wps:txbx")?.first("w:txbxContent") else { continue }
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
                // (The VML twin of a drawing whose text is warped is that text again, plain.)
                if n.name == "mc:Fallback", !drawingWordArt.isEmpty { return nil }
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
                let saved = (notes.seenFootnotes, notes.seenEndnotes, notes.openComments, notes.pendingBookmarks, notes.pendingBookmarkMarkers, notes.fields,
                             notes.seenComments, notes.fieldShown)
                defer {
                    (notes.seenFootnotes, notes.seenEndnotes, notes.openComments, notes.pendingBookmarks, notes.pendingBookmarkMarkers, notes.fields,
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
                var ownShape: XNode? = nil   // the shape in a drawing group that holds this text
                if let group = node.descendant("wpg:wgp") {
                    // (The boxes of the groups in it too, each at its place
                    // in the group: zh-ae2dd08d p21's flowchart nests its
                    // boxes two groups deep, and ours read only the first
                    // box's text, set across the whole group.)
                    let placed = Self._groupTextBoxes(group).filter { drawingWordArt[ObjectIdentifier($0.box)] == nil }
                    let boxes = placed.map(\.box)
                    ownShape = boxes.first(where: { $0.descendant("w:txbxContent") === content })
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
                                // (A list's number and text stand at its own left: moved with the box's.)
                                if let own = inside[q].style.listIndentLeft { inside[q].style.listIndentLeft = own + x + l }
                                inside[q].style.indentRight += max(0, groupWidth - (x + w) + r)
                                inside[q].style.boxInsetRight = r
                            }
                            // (Or in its middle: zh-77079ee8's organisation chart, a
                            // SmartArt whose boxes centre "工作圈" and the
                            // one-line "工作" over "服務組" in Word's print.)
                            var part = RichTextBox.Part(first: first, top: y + t, height: max(0, h - t - bottom), atFoot: body?["anchor"] == "b",
                                                        inMiddle: body?["anchor"] == "ctr")
                            // (A box turned in its group: about its middle, in the
                            // frame's place.)
                            if Self.wordOnWindows, let rot = b.first("wps:spPr")?.first("a:xfrm")?["rot"].flatMap({ Double($0) }), rot != 0 {
                                part.rotation = rot / 60000
                                part.pivotX = x + w / 2
                                part.pivotY = y + h / 2
                            }
                            parts.append(part)
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
                            if let own = inside[q].style.listIndentLeft { inside[q].style.listIndentLeft = own + b.place.left }
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
                // (A picture or a chart is a box's content too: fdo78474's three boxes
                // hold one each and no text, and were dropped as empty.)
                if inside.contains(where: { !$0.text.isEmpty || $0.image != nil || !$0.inlineImages.isEmpty }) || (holdsTable && parts.isEmpty) || (fitsHeight && !inside.isEmpty && parts.isEmpty) {
                    var box = RichTextBox(paragraphs: inside)
                    if holdsTable, parts.isEmpty { notes.boxTables[att.id] = content }
                    box.parts = parts
                    if perPart {
                        // (Each part carries its own place: the group's
                        // box has no insets of its own.)
                        box.insetLeft = 0; box.insetTop = 0; box.insetRight = 0; box.insetBottom = 0
                    } else if let body = ownShape?.first("wps:bodyPr") ?? node.descendant("wps:bodyPr") {
                        // (Its own insets, not the first shape's of the group: zh-bdae17c0 p69's outline box is
                        // a text box of none after a border line of the default 3.6pt, and its text stood 3.9 low.)
                        box.hasFixedFrame = body.first("a:noAutofit") != nil
                        if let anchor = body["anchor"], anchor == "ctr" || anchor == "b" { box.anchor = anchor }
                        // (Not where the body says `upright`: its text stays level in the turned shape, as
                        // zh-b24b396a's "（文件正面）" does in Word's print.)
                        if body["upright"] != "1", let rot = node.descendant("wps:spPr")?.first("a:xfrm")?["rot"].flatMap({ Double($0) }) { box.shapeRotation = rot / 60000 }
                        box.fitsText = body["wrap"] == "none" && body.first("a:spAutoFit") != nil
                        box.fitsOnce = box.fitsText
                        box.autoHeight = body["wrap"] != "none" && body.first("a:spAutoFit") != nil
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
                        let half = Self._halfOutline(ownShape?.first("wps:spPr") ?? node.descendant("wps:spPr"))
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
                        let shapeStyle = (node.name == "v:shape" || node.name == "v:rect" || (node.name == "v:oval" && RichTextTheme.wordWindowsPages) ? node
                            : node.descendant("v:shape") ?? node.descendant("v:rect") ?? (RichTextTheme.wordWindowsPages ? node.descendant("v:oval") : nil))?["style"] ?? ""
                        // (… and without it, in Word for Windows' print: lo-ff3b52d1's rect and oval,
                        // `mso-wrap-style:none` and nothing else, are drawn 77.3pt wide for a text
                        // 76.6 wide, and 102.3 for the oval's 140 declared; lab oval.)
                        box.fitsText = shapeStyle.containsSubstring("mso-wrap-style:none")
                            && ((textbox["style"] ?? "").containsSubstring("mso-fit-shape-to-text:t") || RichTextTheme.wordWindowsPages)
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
                    // (… and a lone VML shape that says `v-text-anchor:middle` or
                    // `bottom` sets its text there: lo-ff3b52d1's oval.)
                    if !perPart, node.descendant("wps:bodyPr") == nil, Self._vmlTop(node)?.name != "v:group", box.anchor == nil,
                       RichTextTheme.wordWindowsPages,
                       let shape = ["v:oval", "v:rect"].lazy.compactMap({ n in node.name == n ? node : node.descendant(n) }).first,
                       let shapeStyle = shape["style"] {
                        if shapeStyle.containsSubstring("v-text-anchor:middle") { box.anchor = "ctr"; box.hasFixedFrame = true }
                        else if shapeStyle.containsSubstring("v-text-anchor:bottom") { box.anchor = "b"; box.hasFixedFrame = true }
                    }
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
                    att.isDropCap = node.descendant("wp:docPr")?["name"] == "Drop cap"
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
                    att.crop = Self._pictureCrop(node)
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
            // A drawing the file hides (`wp:docPr hidden="1"`) is not printed:
            // lo-14656c7f's anchored rectangle was drawn over Word's first lines.
            // It is still kept and written back; it just has no outline or group to paint.
            let hiddenDrawing = ["1", "true"].contains(node.descendant("wp:docPr")?["hidden"] ?? "")
            if hiddenDrawing { att.outline = nil; RuleTrace.hit("hidden-drawing-not-painted") }
            if !hiddenDrawing, let group = node.descendant("wpg:wgp") ?? (att.outline == nil ? node.descendant("wps:wsp") : nil) {
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
            // (A chart in a group's `wpg:graphicFrame` is the group's, drawn in
            // its place there, registered by its part: `WriterGroups`.)
            for frame in node.descendants("wpg:graphicFrame") {
                guard let rid = frame.descendant("c:chart")?["r:id"], let rel = notes.rels[rid], !rel.external,
                      let data = notes.part(_resolvePath("word", rel.target)), let space = XNode.parse(data) else { continue }
                let themeTarget = notes.rels.values.first(where: { $0.type.hasSuffix("/theme") && !$0.external })?.target ?? "theme/theme1.xml"
                WriterCharts.register(space, for: att.id + "#" + rid, themePart: notes.part(_resolvePath("word", themeTarget)))
            }
            if node.descendant("wpg:graphicFrame") == nil, let rid = Self._ownChartRid(node), let rel = notes.rels[rid], !rel.external,
               let data = notes.part(_resolvePath("word", rel.target)), let space = XNode.parse(data) {
                let themeTarget = notes.rels.values.first(where: { $0.type.hasSuffix("/theme") && !$0.external })?.target ?? "theme/theme1.xml"
                // (With the chart part's own theme override, for its faces.)
                var comps = _resolvePath("word", rel.target).split(separator: "/").map(String.init)
                let file = comps.popLast() ?? ""
                let dir = comps.joined(separator: "/")
                let over = notes.part(dir + "/_rels/" + file + ".rels").flatMap(XNode.parse)?.all("Relationship")
                    .first(where: { ($0["Type"] ?? "").hasSuffix("/themeOverride") && $0["TargetMode"] != "External" })?["Target"]
                    .flatMap { notes.part(_resolvePath(dir, $0)) }
                let shapes = notes.part(dir + "/_rels/" + file + ".rels").flatMap(XNode.parse)?.all("Relationship")
                    .first(where: { ($0["Type"] ?? "").hasSuffix("/chartUserShapes") && $0["TargetMode"] != "External" })?["Target"]
                    .flatMap { notes.part(_resolvePath(dir, $0)) }.flatMap(XNode.parse)
                WriterCharts.register(space, for: att.id, themePart: notes.part(_resolvePath("word", themeTarget)), themeOverride: over, userShapes: shapes)
            }
            // A box-and-whisker chart (Office 2016's chartex part), drawn
            // on a column chart's axes, or a sunburst: named by `cx:chart`
            // (by `c:chart` it is read above, as chartex names its own).
            if Self._ownChartRid(node) == nil, node.descendant("c:chart") == nil, let space = boxWhisker(node) {
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
            // (A text box's own picture is not the box's: tdf48658's header is
            // a transparent VML box holding a table, whose first cell has a
            // small inline picture; read as that picture, the box drew the
            // picture alone and none of its table.)
            func blipOutsideBoxes(_ n: XNode) -> XNode? {
                if n.name == "w:txbxContent" { return nil }
                if n.name == "a:blip" { return n }
                for child in n.children { if let hit = blipOutsideBoxes(child) { return hit } }
                return nil
            }
            if drawing.descendant("w:txbxContent") != nil, blipOutsideBoxes(drawing) == nil {
                RuleTrace.hit("box-picture-is-the-boxs-content")
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
                att.crop = Self._pictureCrop(drawing)
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
            att.crop = Self._pictureCrop(drawing)
            att.inset = Self._canvasInset(drawing)
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
            for id in cs.comments { notes.carriedComments.insert(id) }
            var cs = cs
            if s == "\u{B7}" { cs.loneDot = true }
            runs.append(Run(length: s.utf16.count, style: cs))
        }
        var pendingCheckbox: Bool? = nil   // a FORMCHECKBOX field's state, from its begin
        var pendingDropdown: String? = nil // a FORMDROPDOWN field's chosen entry, from its begin
        func walkRun(_ r: XNode, link: String?, revision: RevisionMark? = nil) {
            var cs = cellChar
            cs.link = link
            cs.revision = revision
            cs.comments = notes.openComments
            notes.anchoredComments.formUnion(notes.openComments)
            var missingReference: Int? = nil
            // Text that is a page reference's result stays one: Word
            // brings these up to date when it prints, and a contents page
            // of plain numbers kept the ones the file was saved with (a
            // Kinmen emergency plan listed its chapters 5 to 46 pages
            // early). Other fields stay the text they show.
            if let f = notes.fields.last, f.result {
                cs.fieldResult = f.id
                let instr = f.instr.trimmingWhitespace(newlines: true)
                if Self._preservesField(instr) {
                    cs.preservedField = instr
                    cs.preservedFieldProperties = f.properties
                }
                if instr.uppercased().hasPrefix("PAGEREF ") {
                    cs.field = instr
                    // (A page reference to a bookmark the file does not have:
                    // Word brings the field up to date as it prints and shows
                    // its error where the number was. lo tdf164905's contents
                    // page has 39 such lines, "ERROR! BOOKMARK NOT DEFINED."
                    // in Word's print, 39 of 54 references.)
                    let target = instr.split(separator: " ", omittingEmptySubsequences: true).dropFirst().first
                        .map { String($0.filter { $0 != "\"" }).lowercased() }
                    if let target, !target.isEmpty, !target.hasPrefix("\\"), !notes.bookmarkNames.isEmpty, !notes.bookmarkNames.contains(target) {
                        missingReference = f.id
                    }
                }
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
            runRevision = revision?.kind == .deleted ? revision : nil
            defer { runPropertiesXML = nil; runFrame = nil; runRaised = nil; runRevision = nil }
            if let rPr = r.first("w:rPr") {
                // The run's character style first, then its own properties.
                let runText = r.children.filter { $0.name == "w:t" }.map(\.text).joined()
                // (A run flagged w:rtl whose text is digits and marks, no letters, is complex
                // script too: Word sets heb-z5059159's "1" in the szCs 12, not the sz 11.)
                let rtlRun = _on(rPr.first("w:rtl")) && !runText.isEmpty && !runText.unicodeScalars.contains { ($0.value | 0x20) >= 0x61 && ($0.value | 0x20) <= 0x7A }
                let csFlag = _on(rPr.first("w:cs"))
                let complexSize = runText.unicodeScalars.contains {
                    (0x0590...0x08FF).contains($0.value) || (0xFB1D...0xFDFF).contains($0.value) || (0xFE70...0xFEFF).contains($0.value)
                        // (Devanagari, Bengali, Gurmukhi and Gujarati: 375919ba's sz 16 / szCs 14 prints at 14, Word's Mangal. Tamil and Telugu do not:
                        // cef2f7bd's Telugu title, sz 14 / szCs 10, prints at 14.)
                        // (Only with the w:cs flag: a run without it prints at sz, lab cssz; 80152175's Bengali, 87097d3e's Hindi.)
                        || (csFlag && (0x0900...0x0B7F).contains($0.value))
                } || rtlRun
                // (Tamil takes bCs/iCs but not szCs: da732dfb's sz 14 / szCs 20 subtitle prints at 14 in Word. Only a run with no Latin letters.)
                let tamilOnly = !runText.unicodeScalars.contains { ($0.value | 0x20) >= 0x61 && ($0.value | 0x20) <= 0x7A } && runText.unicodeScalars.contains { (0x0B80...0x0BFF).contains($0.value) }
                let complex = complexSize || tamilOnly
                let indicOnly = !runText.isEmpty && !runText.unicodeScalars.contains { ($0.value | 0x20) >= 0x61 && ($0.value | 0x20) <= 0x7A }
                    && runText.unicodeScalars.contains { (0x0900...0x0B7F).contains($0.value) }
                // (Not the Hyperlink character style inside a table of contents:
                // Word prints its entries in the TOC paragraph's own look, black
                // and plain, whatever the runs name.)
                let inContents = notes.fields.contains { $0.instr.uppercased().trimmingWhitespace(newlines: true).hasPrefix("TOC") }
                if let id = rPr.first("w:rStyle")?["w:val"], let chain = notes.charStyleChains[id], !(inContents && id.lowercased() == "hyperlink") {
                    for styled in chain { cs = _charStyle(styled, base: cs, complexText: complex, complexSize: complexSize, indicOnly: indicOnly) }
                }
                cs = _charStyle(rPr, base: cs, complexText: complex, complexSize: complexSize, indicOnly: indicOnly)
                // (The same where the weight comes from the PARAGRAPH style: dx2 f0001d05's Title (b, no bCs), a Kokila run with w:cs and no weight of its own, prints regular.)
                if indicOnly, _on(rPr.first("w:cs")), rPr.first("w:b") == nil, rPr.first("w:bCs") == nil, !cs.bold,
                   let n = style.named, sheet[n]?.char.boldWithoutBCs == true { cs.off.insert(.bold) }
            }
            // (A page number kept in its result's look with \* MERGEFORMAT keeps its weight and
            // loses the rest of it: lab pgf (Word for Windows, 2026-11-02) — an Arial Bold 15.5pt
            // superscript result prints Arial Bold 10pt on the baseline, only the "/" beside it
            // raised; lo-198cd200's footer.)
            if notes.inHeaderFooter, let f = notes.fields.last, f.result, DocxFormat._isPageField(f.instr), f.instr.uppercased().containsSubstring("MERGEFORMAT"),
               cs.script != .normal {
                // (A superscript's shrunk size stays, its raise does not: 15.5pt prints 10.)
                RuleTrace.hit("page-field-result-with-mergeformat-keeps-bold-only")
                cs.script = .normal
                cs.fontSize = cs.fontSize.map { $0 * 0.65 }
            }
            // A link the file does not underline (no Hyperlink character
            // style on its run, or one that says so): the save names the
            // style again, so the run has to say "none" over it —
            // bug59058's green reference numbers came back underlined.
            if link != nil, !cs.underline { cs.off.insert(.underline) }
            // (And the link stays a link, in the text's own colour.)
            if link != nil, cs.color == nil,
               notes.fields.contains(where: { $0.instr.uppercased().trimmingWhitespace(newlines: true).hasPrefix("TOC") }) {
                cs.color = Color(0xFF000000)
            }
            runRaised = cs.raised
            for child in r.children {
                switch child.name {
                case "w:t":
                    // (A STYLEREF that names no style of the file — lo
                    // tdf149089's "标题 1" over a style called "heading 1" —
                    // is Word's error in bold, 9pt in its header, where
                    // the result saved with it was the heading's text.)
                    if let f = notes.fields.last, f.result, f.instr.uppercased().trimmingWhitespace(newlines: true).hasPrefix("STYLEREF"),
                       let name = Self._styleRefName(f.instr), !notes.styleNames.contains(name.lowercased()) {
                        if notes.styleRefShown.insert(f.id).inserted {
                            var bold = cs
                            bold.bold = true
                            bold.off.remove(.bold)
                            addText("Error! Use the Home tab to apply \(name) to the text that you want to appear here.", bold)
                        }
                        break
                    }
                    // A reference to a bookmark the document lacks: Word brings
                    // it up to date as it prints, and the result is its error
                    // (tdf170672's two REF fields over a missing _Ref name stand
                    // as "Error! Reference source not found." twice, two lines
                    // in the cell where the file's cached "4.1" and heading took
                    // four).
                    if let f = notes.fields.last, f.result, let name = DocxFormat._missingReference(f.instr, notes.bookmarkNames, notes.keptBookmarkText) {
                        _ = name
                        if notes.referenceErrors.insert(f.id).inserted { addText("Error! Reference source not found.", cs) }
                        continue
                    }
                    if let id = missingReference {
                        if notes.missingReferenceShown.insert(id).inserted {
                            RuleTrace.hit("pageref-bookmark-not-defined")
                            addText("Error! Bookmark not defined.", cs)
                        }
                    } else if notes.fieldCodeChanged, notes.fields.last?.result == true {
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
                        notes.fields.append((instr: "", result: false, id: notes.fieldCount,
                                             properties: child.attrs.filter { $0.key == "w:fldLock" || $0.key == "w:dirty" })); notes.fieldShown = false
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
                        if let f = notes.fields.last, !f.result, let shownText = DocxFormat._ifFieldResult(f.instr) {
                            RuleTrace.hit("if-field-shows-its-branch")
                            var shown = cs
                            shown.field = f.instr.trimmingWhitespace(newlines: true)
                            if !shownText.isEmpty { addText(shownText, shown) }
                        }
                        if let f = notes.fields.last, !f.result, let ringed = DocxFormat._ringedNumber(f.instr) {
                            // (The kept ring of an overstrike takes the code's own run style, 12 pt here,
                            // not the closing marker's bare one.)
                            var shown = ringed.unicodeScalars.first.map { (0x2460 ... 0x2473).contains($0.value) } == true ? cs : (notes.fieldCodeStyle[f.id] ?? cs)
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
                        var box = cs; box.formBox = true
                        addText(on ? "\u{2612}" : "\u{2610}", box)
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
                    if notes.kept["word/comments.xml"] != nil, let id = child["w:id"], !notes.seenComments.contains(id) || !notes.carriedComments.contains(id) {
                        notes.seenComments.insert(id)
                        var point = cs
                        point.comments = cs.comments + [id]
                        addText("\u{200B}", point)
                    }
                case "w:delText": addText(child.text, cs)
                case "w:tab":
                    // (A tab in a field's code, between its begin and
                    // separate, is part of the instruction and shows
                    // nowhere: LibreOffice's fdo73596_RunInStyle INDEX field
                    // has `\e "<tab>"` there, and the tab took a line of its
                    // own in the paragraph that opens the field.)
                    if let f = notes.fields.last, !f.result { notes.fields[notes.fields.count - 1].instr += "\t" } else { addText("\t", cs) }
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
                    if text.isEmpty, inlineImages.isEmpty, built.isEmpty { cellBreakOpens = true }
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
                    } else if child["w:type"] == "column", notes.hasColumns, !(text.isEmpty && inlineImages.isEmpty && built.isEmpty) {
                        // (In the middle of a paragraph, on a page of columns,
                        // a column break takes the rest of the paragraph to
                        // the next column — the next page from the last:
                        // LibreOffice's tdf153964_topMarginAfterBreak14.)
                        flush(pageBreakAfter: true)
                        built[built.count - 1].breakCharacter = true; built[built.count - 1].breakRPr = runPropertiesXML
                        built[built.count - 1].breakColumn = true
                        splitBefore = true
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
                    // (A VML polyline alone — LibreOffice's FDO76248, a
                    // vertical rule over a table, `points` and no size —
                    // is not a box: read as the 300 by 200 stand-in it
                    // wrapped the text beside it in a grey square and sent
                    // 10 lines of page 3 to the right. It takes no room and
                    // wraps nothing in Word's print.)
                    if child.name == "w:pict", child.descendant("v:polyline") != nil,
                       child.descendant("v:textbox") == nil, child.descendant("v:imagedata") == nil { break }
                    // (A horizontal rule is a block: after text in the same paragraph Word sets it on a line of its own,
                    // numbered and a line tall. fd00b5's four, 47.8 to 79.2 by a break before each, no rebuild.)
                    if DocxFormat.wordOnWindows, child.name == "w:pict", child.descendant("v:rect")?["o:hr"] == "t",
                       !(text.isEmpty && inlineImages.isEmpty && built.isEmpty), !text.hasSuffix("\n") { addText("\n", cs) }
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
                        if !notes.inTextBox { if footnote { notes.customFootnotes.insert(id) } else { notes.customEndnotes.insert(id) } }
                    } else {
                        let n = notes.next(footnote: footnote, id: id)
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
                    // Word appends the bookmark to an external Target URL
                    // (MS-OI29500 2.1.521), even with r:id present.
                    let external = child["r:id"].flatMap { rels[$0] }
                    let target = external.map { $0 + (child["w:anchor"].map { "#\($0)" } ?? "") }
                        ?? child["w:anchor"].map { "#\($0)" }
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
                case "w:fldSimple" where Self._preservesField(child["w:instr"] ?? "") || notes.inHeaderFooter && DocxFormat._isPageField(child["w:instr"] ?? ""):
                    notes.fieldCount += 1
                    notes.fields.append((instr: child["w:instr"] ?? "", result: true, id: notes.fieldCount,
                                         properties: child.attrs.filter { $0.key == "w:fldLock" || $0.key == "w:dirty" }))
                    walkInline(child, link: link, revision: revision)
                    notes.fields.removeLast()
                case "w:smartTag", "w:sdtContent", "w:sdt", "w:fldSimple", "w:customXml":
                    walkInline(child, link: link, revision: revision)
                case "m:oMathPara", "m:oMath":
                    // (A comment whose reference stands inside the equation, its
                    // range empty, anchors at the equation: tdf170236's
                    // "Commented [A1]: Hello World!" balloon is in Word's print.)
                    if notes.kept["word/comments.xml"] != nil {
                        var stack: [XNode] = child.children.reversed()
                        while let n = stack.popLast() {
                            if n.name == "w:commentReference", let id = n["w:id"], !notes.anchoredComments.contains(id) {
                                notes.anchoredComments.insert(id)
                                RuleTrace.hit("comment-in-equation")
                                var point = cellChar
                                point.comments = [id]
                                addText("\u{200B}", point)
                            } else { stack.append(contentsOf: n.children.reversed()) }
                        }
                    }
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
                        var whole: (Double, Double)? = nil
                        if let m = WriterMath.register(child, for: att.id, size: mathSize, natural: { whole = $0 }) {
                            if child.name == "m:oMath", let w = whole { att.naturalExtent = (w.0, w.1) }
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
                    if let name = child["w:name"], name != "_GoBack" {
                        notes.pendingBookmarks.append(name)
                        if let id = child["w:id"] { bookmarkMarkers.append(RichBookmarkMarker(id: id, name: name, offset: text.utf16.count)) }
                    }
                case "w:bookmarkEnd":
                    if let id = child["w:id"] { bookmarkMarkers.append(RichBookmarkMarker(id: id, offset: text.utf16.count)) }
                case "w:pPr", "w:proofErr":
                    break
                default: break
                }
            }
        }
        walkInline(p, link: nil)
        // (A run of tabs that opens the paragraph, in a size of its own: the
        // line takes the text's, not the tab's. lo tdf164905's contents
        // entries open with a tab run of Calibri 11 and set their text in
        // 9pt Arial; Word's lines stand 16.35pt apart, the 9pt line and the
        // 6pt between, where ours took the 11pt tab's taller line and ran
        // 0.2pt a paragraph long.)
        if runs.count > 1, runs[0].style.fontSize != nil, runs[0].style.fontSize != runs[1].style.fontSize,
           runs[1].style.inlineImage == nil, text.utf16.prefix(runs[0].length).allSatisfy({ $0 == 0x09 }),
           !text.utf16.dropFirst(runs[0].length).prefix(runs[1].length).contains(0x09) {
            RuleTrace.hit("leading-tab-takes-text-size")
            runs[0].style.fontSize = runs[1].style.fontSize
            runs[0].style.fontFamily = runs[1].style.fontFamily
        }
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
        if cellBreakOpens { style.cellBreakOpens = true }
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
            // (Not after a COLUMN break with objects: the paragraph's own line opens the
            // next column, its objects with it — lo tdf153592's three columns
            // each open with the break and a text box's anchor, and Word's
            // print gives the 2nd and 3rd a line before their text, and draws
            // the boxes, which ours dropped.)
            let pageBreakAlone = built.isEmpty && text.unicodeScalars.allSatisfy({ $0.value == 0xFFFC }) && (inlineImages.isEmpty || floatsOnly)
            let columnWithObjects = leadingColumnBreak && !inlineImages.isEmpty
            if pageBreakAlone, columnWithObjects { RuleTrace.hit("column-break-keeps-its-paragraph-line") }
            if pageBreakAlone, !columnWithObjects {
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
           !(notes.marksFollowBreaks && last.breakCharacter && !last.breakColumn),
           !(Self.wordOnWindows && notes.hasColumns && notes.columnMarksFollow && last.breakCharacter && last.breakColumn) {
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
            let markFollows = text.isEmpty && inlineImages.isEmpty && notes.marksFollowBreaks && (built.last.map { $0.pageBreakAfter && $0.breakCharacter && !$0.breakColumn } ?? false)
            flush(pageBreakAfter: sectionBreakAfter)
            if markFollows, built.count > 1 { built[built.count - 1].paragraph.style.markFollowsBreak = true }
        }
        if sectionMarginsChange, !built.isEmpty { built[built.count - 1].sectionMarginsChange = true }
        if built.count > 1 { for k in 0 ..< built.count - 1 { Self._sectionMarkStaysOnTheLastPiece(&built[k].paragraph) } }
        return built
    }

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
        // (A line separator typed into the text is no break to Word: it
        // prints a blank half an em wide and the line runs on —
        // LibreOffice's tdf152983-1-min, two of them in a 12pt paragraph,
        // 6pt each in Word's print. The layout's own breaks are U+2028, so
        // it is set as the en space, which is that wide.)
        let raw = t.text.containsSubstring("\u{2028}") ? t.text.replacingAll("\u{2028}", with: "\u{2002}") : t.text
        if t["xml:space"] == "preserve" { return raw }
        let ws: Set<Character> = [" ", "\t", "\n", "\r", "\r\n"]
        var text = Substring(raw)
        while let f = text.first, ws.contains(f) { text.removeFirst() }
        while let l = text.last, ws.contains(l) { text.removeLast() }
        return String(text)
    }

    /// An on/off element: present counts as on unless w:val is false, 0 or off.
    static func _on(_ node: XNode?) -> Bool {
        guard let node = node else { return false }
        return !_isOff(node)
    }

    private static func _isOff(_ node: XNode) -> Bool {
        switch node["w:val"] {
        case "0", "false", "off": return true
        default: return false
        }
    }

    /// The theme's colours by scheme name ("accent2", "dk1", ...), set when a document is read.
    nonisolated(unsafe) private static var _themeColors: [String: (Int, Int, Int)] = [:]

    private static func _themePalette(_ entries: [ZipEntry]) -> [String: (Int, Int, Int)] {
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
    private static func _themeBackground(_ slot: String, tint: String?, shade: String?) -> UInt32? {
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
    private static func _w14Color(_ node: XNode) -> (Int, Int, Int)? {
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
    private static let _tableCharKeys: [(String, WritableKeyPath<CharStyle, String?>)] = [
        ("ascii", \.fontFamily), ("hAnsi", \.hAnsiFontFamily), ("eastAsia", \.eastAsiaFontFamily),
        ("cs", \.complexFontFamily), ("hint", \.fontHint),
    ]
    private static let _tableCharNumbers: [(String, WritableKeyPath<CharStyle, Double?>)] = [
        ("kern", \.kerningFrom), ("spacing", \.letterSpacing), ("w", \.horizontalScale), ("position", \.raised),
    ]
    private static func _takeTableChar(_ cell: inout CharStyle, _ table: CharStyle, normal: CharStyle) -> Set<String> {
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
    private static func _dropTableChar(_ cell: inout CharStyle, stated named: CharStyle, took: Set<String>) {
        for (name, k) in _tableCharKeys where took.contains(name) && named[keyPath: k] != nil { cell[keyPath: k] = nil }
        for (name, k) in _tableCharNumbers where took.contains(name) && named[keyPath: k] != nil { cell[keyPath: k] = nil }
        if took.contains("color"), named.color != nil || named.off.contains(.autoColor) { cell.color = nil }
    }

    private static func _charStyle(_ rPr: XNode, base: CharStyle, complexText: Bool? = nil, complexSize: Bool? = nil, indicOnly: Bool = false) -> CharStyle {
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
            case "w14:glow":
                // (Word's glow: `w14:rad` in EMU, the colour a child with
                // an optional alpha in thousandths of a percent. Drawn as
                // the slide runs' glow is.)
                if let c = child.children.first(where: { $0.name == "w14:srgbClr" || $0.name == "w14:schemeClr" }), let rgb = _w14Color(c) {
                    let alpha = c.first("w14:alpha").flatMap { Double($0["w14:val"] ?? "") }.map { $0 / 100000 } ?? 1
                    // (Word draws none at all for a glow of alpha 100%: its lab print of wordglow.docx.)
                    if alpha >= 1 { break }
                    var glow = CharShadow(color: Color(argb: Int((alpha * 255).rounded()), rgb.0, rgb.1, rgb.2),
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
                }
            case "w14:textFill":
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
                    cs.off.insert(.autoColor)
                }
                if cs.color != nil { cs.off.remove(.autoColor) }
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
                if _family(child["w:ascii"] ?? "") != nil, child["w:hAnsi"] == nil { cs.hAnsiNamedAsAscii = false }
                if let h = _family(child["w:hAnsi"] ?? "") { cs.hAnsiFontFamily = (h == cs.fontFamily && child["w:ascii"] != nil) ? nil : h; cs.hAnsiNamedAsAscii = h == cs.fontFamily }
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
        if let z = szCs { cs.complexFontSize = z }
        if bCs != nil { cs.boldWithoutBCs = false } else if sawB { cs.boldWithoutBCs = cs.bold }
        if complexText ?? cs.rightToLeft {
            // (A complex run's weight is its bCs even when the run also states b: af19d946's Heading3 run, b 0 / bCs, prints Devanagari in Nirmala UI Bold.)
            if let b = bCs { cs.bold = b; if b { cs.off.remove(.bold) } else { cs.off.insert(.bold) } }
            // (A run of Devanagari, Bengali, Gurmukhi or Gujarati letters only that carries the w:cs flag and states b with no bCs keeps the weight it inherited (a run without the flag, as in xd 77d6ca49's Nirmala UI, is bold): Word
            // prints dx2-class xd 745490897f9f's bold-marked Kokila words in regular Kokila.)
            else if indicOnly, cs.bold, sawB ? !base.bold : cs.boldWithoutBCs, _on(rPr.first("w:cs")) { cs.bold = false; if base.off.contains(.bold) { cs.off.insert(.bold) } else { cs.off.remove(.bold) } }
            if !sawI, let i = iCs { cs.italic = i; if i { cs.off.remove(.italic) } else { cs.off.insert(.italic) } }
            // (The same for the slant: dx2 f0001d05's w:i + w:cs Kokila words (no iCs) print in upright Kokila, the face's regular widths.)
            else if indicOnly, sawI, iCs == nil, cs.italic, !base.italic, _on(rPr.first("w:cs")) { cs.italic = false; if base.off.contains(.italic) { cs.off.insert(.italic) } else { cs.off.remove(.italic) } }
            if !(complexSize ?? true) {}
            else if !sawSz, let z = szCs ?? cs.complexFontSize { cs.fontSize = z }
            // (A complex run that gives both sizes is set at szCs: the Arabic of ara-z4399437's even-page header, sz 9 / szCs 11, prints at 11.)
            else if sawSz, let z = szCs { cs.fontSize = z }
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
    /// Whether the document part holds Devanagari to Malayalam text (UTF-8 lead bytes E0 A4 to E0 B5).
    private static func _hasIndicBytes(_ data: Data) -> Bool {
        let bytes = [UInt8](data)
        var i = 0
        while i + 1 < bytes.count { if bytes[i] == 0xE0, bytes[i + 1] >= 0xA4, bytes[i + 1] <= 0xB5 { return true }; i += 1 }
        return false
    }
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

    static func write(_ source: RichDocument, pageSetup: PageSetup) throws -> Data {
        var doc = source
        doc.paragraphs.removeAll { $0.flowedEndnote != nil }
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
        func paragraphXML(_ index: Int) -> String {
            var p = doc.paragraphs[index]
            // Boundaries can fall inside a normalized run. Split only the
            // serialization view, keeping the document's run invariants.
            let cuts = Set(p.bookmarkMarkers.map { max(0, min($0.offset, p.length)) })
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
            for name in p.bookmarks where !rangedBookmarkNames.contains(name) && writtenBookmarks.insert(name).inserted {
                // (Numbered clear of any a kept table's own XML carries.)
                repeat { nextPointBookmarkID += 1 } while rangedBookmarkIDs.contains(String(nextPointBookmarkID))
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
                body += bookmarkXML(at: pos)
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
                if commentsKept { body += closeComments(except: commentsAfter(index, runIndex, in: p)) }
            }
            body += bookmarkXML(at: p.length)
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
