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
    var name: String
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
    /// The relationships of a .rels part. A writer that prefixes the package namespace (`ns0:Relationship`, Python's ElementTree
    /// default; xb fas-z22832287 and its embedded Vazirmatn) is read the same as an unprefixed one.
    func relationships() -> [XNode] { children.filter { $0.name == "Relationship" || $0.name.hasSuffix(":Relationship") } }
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

    /// A table nested more than 63 deep is cut off (Word's own limit is that many levels): every later
    /// pass walks the tree by recursion, one native frame or more per level, and deep-table-cell (5000
    /// levels) overflowed the web build's small stack. Walked with a list, not by recursion.
    static func _capTableNesting(_ root: XNode) {
        var pending: [(XNode, Int)] = [(root, 0)]
        while let (node, depth) = pending.popLast() {
            let isTable = node.name == "w:tbl" || node.name == "tbl"
            if isTable && depth >= 63 {
                // (Its place in the cell is an empty paragraph: a cell must end in one.)
                node.name = "w:p"; node.attrs = [:]
                // (Taken apart with a list too: freeing a 5000-deep chain recurses once per level.)
                var dismantle = node.children
                node.children = []
                while let n = dismantle.popLast() { dismantle.append(contentsOf: n.children); n.children = [] }
                continue
            }
            for c in node.children { pending.append((c, isTable ? depth + 1 : depth)) }
        }
    }

    /// The system's parser, with prefixes kept ("w:p") — which is what the
    /// OOXML parts use consistently and saves resolving namespaces. What
    /// `parse` falls back on.
    /// An element written without a prefix under `xmlns="…/wordprocessingml/2006/main"`
    /// is a WordprocessingML element all the same (a generator that wrote
    /// `<drawing xmlns="…main">` inside its `w:r`): the reader looks for the
    /// `w:` spelling, so give it that name.
    static func _prefixDefaultMain(_ n: XNode, _ inMain: Bool) {
        var inMain = inMain
        if let d = n.attrs["xmlns"] { inMain = d == "http://schemas.openxmlformats.org/wordprocessingml/2006/main" }
        if inMain, n.name.firstIndex(of: ":") == nil { n.name = "w:" + n.name }
        for c in n.children { _prefixDefaultMain(c, inMain) }
    }

    static func parseSystem(_ data: Data) -> XNode? {
        let root = _parseSystemRaw(data)
        if let root { _capTableNesting(root); _prefixDefaultMain(root, false) }
        return root
    }

    static func _parseSystemRaw(_ data: Data) -> XNode? {
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
        if _plainUTF8(bytes), let root = MiniXML.parse(bytes) { _capTableNesting(root); _prefixDefaultMain(root, false); return _strictMeasures(root, data) }
        return parseSystem(data).map { _strictMeasures($0, data) }
        #endif
    }

    /// A strict (ISO) WordprocessingML part gives its measures with a unit
    /// ("419.60pt", "2.5cm") where the transitional one gives twips (or
    /// half-points for a size): LibreOffice's tdf82065_Ind_start_strict has
    /// its page, margins and indents so, and they were read as nothing —
    /// the paragraph on a letter page with no indent. Put into twips here,
    /// once, where the part is read.
    static let _strictTwipAttributes: Set<String> = [
        "w:w", "w:h", "w:top", "w:bottom", "w:left", "w:right", "w:start", "w:end", "w:header", "w:footer", "w:gutter",
        "w:hanging", "w:firstLine", "w:before", "w:after", "w:pos", "w:space", "w:firstLine", "w:tblpX", "w:tblpY",
    ]
    static func _strictMeasures(_ root: XNode, _ data: Data) -> XNode {
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
        // A run size with a fraction of a half point ("40.5", "19.2") is read
        // by Word as its whole part: 40 (20 pt), 19 (9.5 pt), 25.5 as 25
        // (12.5 pt). The prints of sa2 cb623f0a and dx2 8afcc2c4/53e31548
        // show 20.04, 9.48 and 12.48 pt (PDF sizes run 0.04 over).
        if data.prefix(4096).range(of: Data("/wordprocessingml/".utf8)) != nil {
            func wholeHalfPoints(_ n: XNode) {
                if n.name == "w:sz" || n.name == "w:szCs", let v = n.attrs["w:val"], v.utf8.contains(UInt8(ascii: ".")),
                   let d = Double(v), d >= 0 { n.attrs["w:val"] = String(Int(d)) }
                for c in n.children { wholeHalfPoints(c) }
            }
            wholeHalfPoints(root)
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
        /// The part's bytes when this app's own reader took it (so the items can be scanned in place), else nil.
        var bytes: [UInt8]? = nil
    }

    static func parse(_ data: Data, listUnder parent: String, of item: String) -> ListPart? {
        let bytes = [UInt8](data)
        var own = true
        #if !os(WASI)
        own = !_systemOnly && _plainUTF8(bytes)
        #endif
        if own, let root = MiniXML.parse(bytes, emptying: parent) {
            return ListPart(root: root, forEach: { each in MiniXML.children(named: item, ofRootChild: parent, in: bytes, each) }, bytes: bytes)
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
    static let _systemOnly = ProcessInfo.processInfo.environment["OFFICE_XML"] == "system"

    /// Whether this app's own reader can take the part.
    static func _plainUTF8(_ b: [UInt8]) -> Bool {
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
    final class _Builder: NSObject, XMLParserDelegate {
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
func _statedCellColumns(_ node: XNode, count: Int, widest: Bool = false) -> [Double]? {
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
        if let f = widths { if f != row { if widest { widths = zip(f, row).map { max($0, $1) } } else { return nil } } } else { widths = row }
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
