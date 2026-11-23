// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// An XML reader for WordprocessingML, used where FoundationXML is not:
// the web build (docs/plans/wasm.md). Elements, attributes, text, CDATA,
// the five predefined entities and numeric references; comments,
// processing instructions and the DOCTYPE are skipped. No namespaces —
// names keep their prefixes, which is how the docx reader wants them.
// Builds the same XNode tree the XMLParser delegate builds.

enum MiniXML {
    static func parse(_ bytes: [UInt8]) -> XNode? {
        var p = Parser(bytes)
        return p.document()
    }

    /// The tree without what is inside the root's first child named
    /// `local` (whatever its prefix): that child is there, and empty.
    /// With `children(named:ofRootChild:in:_:)` this reads a part whose
    /// bulk is one long list — a sheet's rows — without ever holding the
    /// list as a tree: several objects a cell, most of what opening a
    /// large workbook kept in memory.
    static func parse(_ bytes: [UInt8], emptying local: String) -> XNode? {
        var p = Parser(bytes)
        p.listParent = Array(local.utf8)
        return p.document()
    }

    /// Each child named `item` of the root's first child named `parent`
    /// (both by local name), built on its own, handed over and let go.
    static func children(named item: String, ofRootChild parent: String, in bytes: [UInt8], _ each: (XNode) -> Void) {
        var p = Parser(bytes)
        p.listParent = Array(parent.utf8)
        p.listItem = Array(item.utf8)
        withoutActuallyEscaping(each) { p.each = $0; _ = p.document(); p.each = nil }
    }

    /// What the sheet reader needs of one `<c>`: the same fields whether the cell was read straight from the
    /// bytes (`scanRows`) or came out of a tree (a cell the scanner gave up on).
    struct XlsxCell {
        var r: String? = nil, s: String? = nil, t: String? = nil
        var kept: [(String, String)] = []            // vm, cm, ph
        var hasV = false, v = ""
        var hasF = false
        var fT: String? = nil, fSi: String? = nil, fRef: String? = nil
        var fExtra: [(String, String)] = []          // any other <f> attribute
        var fText = ""
        var inlineNode: XNode? = nil                 // <is>, only from a tree

        /// From a `<c>` node, as the reader always read it.
        init(node c: XNode) {
            r = c["r"]; s = c["s"]; t = c["t"]
            if c.attrs.count > 1 { for (k, val) in c.attrs where k == "vm" || k == "cm" || k == "ph" { kept.append((k, val)) } }
            if let vn = c.child("v") { hasV = true; v = vn.text }
            inlineNode = c.child("is")
            if let f = c.child("f") {
                hasF = true; fT = f["t"]; fSi = f["si"]; fRef = f["ref"]; fText = f.text
                for (k, val) in f.attrs where k != "t" && k != "si" && k != "ref" { fExtra.append((k, val)) }
            }
        }
        init() {}
    }

    /// Each child named `item` of the root's first child named `parent`, as its own start tag (a node with the
    /// attributes only), the byte range of the whole element and the byte range of what is inside it. The
    /// children are NOT built. False when the bytes cannot be read this way (nothing was handed over).
    static func scanRows(named item: String, ofRootChild parent: String, in bytes: [UInt8],
                         _ each: (XNode, Range<Int>, Range<Int>) -> Void) {
        var p = Parser(bytes)
        p.listParent = Array(parent.utf8)
        p.listItem = Array(item.utf8)
        withoutActuallyEscaping(each) { p.rawRow = $0; _ = p.document(); p.rawRow = nil }
    }

    /// The `<c>` elements in `body` (a row's contents), each handed over in order. A cell the scanner does not
    /// recognise exactly is read by the tree parser, in its place.
    /// Cells read on the fast path / read as a tree (a count for OFFICE_XLSX_SCAN_STATS; a plain tally).
    nonisolated(unsafe) static var scanFast = 0
    nonisolated(unsafe) static var scanTree = 0
    static func scanCells(in bytes: [UInt8], body: Range<Int>, _ cell: (XlsxCell) -> Void) {
        var p = Parser(bytes)
        p.scanCells(body: body, cell)
    }

    /// The cells of a row element read as a tree.
    static func treeCells(in bytes: [UInt8], element: Range<Int>) -> [XlsxCell] {
        guard let row = parse(Array(bytes[element])) else { return [] }
        return row.kids("c").map { XlsxCell(node: $0) }
    }

    private struct Parser {
        let b: [UInt8]
        var i = 0
        init(_ bytes: [UInt8]) { b = bytes }

        /// The list left out of the tree (`parse(_:emptying:)`), or — with
        /// `listItem` and `each` — the only thing built.
        var listParent: [UInt8]? = nil
        var listItem: [UInt8]? = nil
        var each: ((XNode) -> Void)? = nil
        /// `scanRows`: the item's start tag as a node, its element range, its body range.
        var rawRow: ((XNode, Range<Int>, Range<Int>) -> Void)? = nil

        /// An open element: its node when it is being built, and whether
        /// it is the list's parent or one of the items handed over.
        private struct Frame {
            var node: XNode?
            var isListParent = false
            var isItem = false
        }

        /// Whether the name in `r` is `local`, with or without a prefix.
        func named(_ r: Range<Int>, _ local: [UInt8]) -> Bool {
            guard r.count >= local.count else { return false }
            let from = r.upperBound - local.count
            guard b[from ..< r.upperBound].elementsEqual(local) else { return false }
            return from == r.lowerBound || b[from - 1] == UInt8(ascii: ":")
        }

        var atEnd: Bool { i >= b.count }
        func peek(_ s: String) -> Bool { b[i...].starts(with: s.utf8) }
        mutating func skipSpace() {
            while i < b.count {
                let c = b[i]
                guard c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D else { return }
                i += 1
            }
        }
        mutating func skip(past marker: String) {
            let m = Array(marker.utf8)
            if m.count == 1 {
                // An end tag's ">" — one for every element in the file.
                let c = m[0]
                while i < b.count { i += 1; if b[i - 1] == c { return } }
                return
            }
            while i + m.count <= b.count {
                if b[i..<i + m.count].elementsEqual(m) { i += m.count; return }
                i += 1
            }
            i = b.count
        }

        mutating func document() -> XNode? {
            var root: XNode?
            var stack: [Frame] = []
            var listSeen = false
            var hoisted: [XNode] = []
            let itemsOnly = listItem != nil
            while !atEnd {
                if b[i] != UInt8(ascii: "<") {
                    let start = i
                    while !atEnd, b[i] != UInt8(ascii: "<") { i += 1 }
                    if let top = stack.last?.node { top.text += decode(b[start..<i]) }
                    continue
                }
                let next: UInt8 = i + 1 < b.count ? b[i + 1] : 0
                if next == UInt8(ascii: "?") { skip(past: "?>"); continue }
                if next == UInt8(ascii: "!"), peek("<!--") { skip(past: "-->"); continue }
                if next == UInt8(ascii: "!"), peek("<![CDATA[") {
                    i += 9
                    let start = i
                    skip(past: "]]>")
                    if let top = stack.last?.node { top.text += String(decoding: b[start..<max(start, i - 3)], as: UTF8.self) }
                    continue
                }
                if next == UInt8(ascii: "!") { skip(past: ">"); continue }
                if next == UInt8(ascii: "/") {
                    i += 2
                    skip(past: ">")
                    if let closed = stack.popLast() {
                        // A paragraph written INSIDE a w:t (malformed export: `<w:r><w:t><w:p>..</w:p></w:t></w:r>`) is a paragraph to Word,
                        // set after the paragraph that holds the run (dx2 ca 0ab6d51b). Hoist it out and set it beside the outer one.
                        if let node = closed.node, node.name == "w:p", !closed.isItem {
                            if let t = stack.last?.node, t.name == "w:t", t.children.last === node {
                                t.children.removeLast(); hoisted.append(node)
                            } else if !hoisted.isEmpty, !stack.contains(where: { $0.node?.name == "w:p" }), let parent = stack.last?.node {
                                // The holding paragraph is set AFTER them (what is left of it once its w:t is cut short): Word puts its blank
                                // line at the foot of the hoisted text (0ab6d51b: 26 pt from the heading to the first hoisted line, not 51).
                                if parent.children.last === node { parent.children.removeLast() }
                                parent.children.append(contentsOf: hoisted); parent.children.append(node); hoisted.removeAll()
                            }
                        }
                        if closed.isItem, let node = closed.node { each?(node) }
                    }
                    continue
                }
                i += 1
                let nameStart = i
                let name = readNameRange()
                // What this element is to the list, and whether it is built.
                var frame = Frame()
                let top = stack.last
                var build = true
                if let parent = listParent {
                    if !listSeen, stack.count == 1, named(name, parent) {
                        listSeen = true
                        frame.isListParent = true
                        build = !itemsOnly
                    } else if itemsOnly {
                        if let top, top.isListParent { frame.isItem = named(name, listItem!); build = frame.isItem }
                        else { build = top?.node != nil }
                    } else {
                        // Under the emptied list nothing is built.
                        build = top == nil || (top!.node != nil && !top!.isListParent)
                    }
                }
                guard build else {
                    // Past the tag, its attributes unread (a ">" may sit
                    // inside a quoted value).
                    var selfClosing = false
                    while !atEnd {
                        let c = b[i]
                        if c == UInt8(ascii: "\"") || c == UInt8(ascii: "'") {
                            i += 1
                            while !atEnd, b[i] != c { i += 1 }
                        } else if c == UInt8(ascii: ">") {
                            selfClosing = i > nameStart && b[i - 1] == UInt8(ascii: "/")
                            i += 1
                            break
                        }
                        i += 1
                    }
                    if !selfClosing { stack.append(frame) }
                    continue
                }
                var attrs: [String: String] = [:]
                var selfClosing = false
                while true {
                    skipSpace()
                    guard !atEnd else { return root }
                    if b[i] == UInt8(ascii: ">") { i += 1; break }
                    if b[i] == UInt8(ascii: "/"), i + 1 < b.count, b[i + 1] == UInt8(ascii: ">") { i += 2; selfClosing = true; break }
                    let key = readName()
                    guard !key.isEmpty else { i += 1; continue }
                    skipSpace()
                    var value = ""
                    if !atEnd, b[i] == UInt8(ascii: "=") {
                        i += 1
                        skipSpace()
                        guard !atEnd else { break }
                        let quote = b[i]
                        if quote == UInt8(ascii: "\"") || quote == UInt8(ascii: "'") {
                            i += 1
                            let start = i
                            while !atEnd, b[i] != quote { i += 1 }
                            value = decode(b[start..<i], attribute: true)
                            if !atEnd { i += 1 }
                        }
                    }
                    attrs[key] = value
                }
                var elementName = String(decoding: b[name], as: UTF8.self)
                // (w:cr, a carriage return, breaks the line as w:br does: dx2 es 613edc1c's notice ends on one and Word's page 2 starts a line lower.)
                if elementName == "w:cr" { elementName = "w:br" }
                let node = XNode(name: elementName, attrs: attrs)
                frame.node = node
                if frame.isItem, let raw = rawRow {
                    let tagStart = nameStart - 1
                    if selfClosing { raw(node, tagStart ..< i, i ..< i); continue }
                    let bodyStart = i
                    guard let (bodyEnd, after) = findEnd(name, from: i) else { i = b.count; continue }
                    i = after
                    raw(node, tagStart ..< after, bodyStart ..< bodyEnd)
                    continue
                }
                if frame.isItem {
                    if selfClosing { each?(node) }
                } else if let parent = top?.node {
                    parent.children.append(node)
                    // (A line break typed INSIDE w:t is a break to Word all the same: dx2 zh 4cac8c37's "...上...<w:br/>抵达后" starts a line at
                    // it, and a break closing a heading gives a blank line. Its place in the text is kept as a private mark; the run reader sets it as "\n".)
                    if parent.name == "w:t", node.name == "w:br" { parent.text += "\u{F8FF}" }
                } else if root == nil, top == nil || !itemsOnly {
                    root = node
                }
                if !selfClosing { stack.append(frame) }
            }
            return root
        }

        /// The end tag that closes the element named `nm`, from `start` (inside it): where it starts and where it
        /// ends. Comments, CDATA and processing instructions are stepped over. Nil when there is none.
        mutating func findEnd(_ nm: Range<Int>, from start: Int) -> (Int, Int)? {
            i = start
            while i < b.count {
                guard let lt = b[i...].firstIndex(of: UInt8(ascii: "<")) else { return nil }
                i = lt
                guard i + 1 < b.count else { return nil }
                let c1 = b[i + 1]
                if c1 == UInt8(ascii: "?") { skip(past: "?>"); continue }
                if c1 == UInt8(ascii: "!") {
                    if peek("<!--") { skip(past: "-->") } else if peek("<![CDATA[") { i += 9; skip(past: "]]>") } else { skip(past: ">") }
                    continue
                }
                if c1 == UInt8(ascii: "/") {
                    let ns = i + 2
                    var e = ns
                    while e < b.count, b[e] != UInt8(ascii: ">") { e += 1 }
                    guard e < b.count else { return nil }
                    var ne = e
                    while ne > ns, b[ne - 1] == 0x20 || b[ne - 1] == 0x09 || b[ne - 1] == 0x0A || b[ne - 1] == 0x0D { ne -= 1 }
                    if b[ns ..< ne].elementsEqual(b[nm]) { let at = i; i = e + 1; return (at, e + 1) }
                    i = e + 1
                    continue
                }
                i += 1
            }
            return nil
        }

        func isSpace(_ c: UInt8) -> Bool { c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D }

        mutating func scanCells(body: Range<Int>, _ cell: (XlsxCell) -> Void) {
            let end = body.upperBound
            i = body.lowerBound
            while true {
                while i < end, b[i] != UInt8(ascii: "<") { i += 1 }
                if i >= end { return }
                guard i + 2 < end, b[i + 1] == UInt8(ascii: "c"),
                      isSpace(b[i + 2]) || b[i + 2] == UInt8(ascii: ">") || b[i + 2] == UInt8(ascii: "/") else {
                    // Not a plain cell: what is left of the row is read as a tree.
                    var wrapped = Array("<row>".utf8)
                    wrapped.append(contentsOf: b[i ..< end])
                    wrapped.append(contentsOf: "</row>".utf8)
                    if let row = MiniXML.parse(wrapped) { for c in row.kids("c") { MiniXML.scanTree += 1; cell(XlsxCell(node: c)) } }
                    return
                }
                let start = i
                if let f = fastCell(end: end) { MiniXML.scanFast += 1; cell(f); continue }
                // Given up on: this one cell, as a tree, then on.
                i = start + 2
                var quote: UInt8 = 0
                var selfClosing = false
                var closed = false
                while i < end {
                    let c = b[i]
                    if quote != 0 { if c == quote { quote = 0 } }
                    else if c == UInt8(ascii: "\"") || c == UInt8(ascii: "'") { quote = c }
                    else if c == UInt8(ascii: ">") { selfClosing = b[i - 1] == UInt8(ascii: "/"); i += 1; closed = true; break }
                    i += 1
                }
                guard closed else { return }
                var after = i
                if !selfClosing {
                    guard let (_, a) = findEnd(start + 1 ..< start + 2, from: i) else { return }
                    after = a
                }
                if let node = MiniXML.parse(Array(b[start ..< after])) { MiniXML.scanTree += 1; cell(XlsxCell(node: node)) }
                i = after
            }
        }

        /// One attribute's value at `i` (after the "="): quoted, decoded as the tree parser does. Nil if not quoted.
        mutating func quotedValue(_ end: Int) -> String? {
            guard i < end else { return nil }
            let q = b[i]
            guard q == UInt8(ascii: "\"") || q == UInt8(ascii: "'") else { return nil }
            i += 1
            let vs = i
            while i < end, b[i] != q { i += 1 }
            guard i < end else { return nil }
            let v = decode(b[vs ..< i], attribute: true)
            i += 1
            return v
        }

        /// A `<c>` read straight from the bytes, or nil when it is anything but the plain shapes (the caller then
        /// reads the cell as a tree, which knows every other shape).
        mutating func fastCell(end: Int) -> XlsxCell? {
            var f = XlsxCell()
            var seen: UInt8 = 0
            i += 2
            while true {
                while i < end, isSpace(b[i]) { i += 1 }
                guard i < end else { return nil }
                if b[i] == UInt8(ascii: ">") { i += 1; break }
                if b[i] == UInt8(ascii: "/") { guard i + 1 < end, b[i + 1] == UInt8(ascii: ">") else { return nil }; i += 2; return f }
                let ns = i
                while i < end, !isSpace(b[i]), b[i] != UInt8(ascii: "="), b[i] != UInt8(ascii: ">"), b[i] != UInt8(ascii: "/") { i += 1 }
                let n = i - ns
                while i < end, isSpace(b[i]) { i += 1 }
                guard i < end, b[i] == UInt8(ascii: "=") else { return nil }
                i += 1
                while i < end, isSpace(b[i]) { i += 1 }
                guard let val = quotedValue(end) else { return nil }
                if n == 1 {
                    switch b[ns] {
                    case UInt8(ascii: "r"): guard seen & 1 == 0 else { return nil }; seen |= 1; f.r = val
                    case UInt8(ascii: "s"): guard seen & 2 == 0 else { return nil }; seen |= 2; f.s = val
                    case UInt8(ascii: "t"): guard seen & 4 == 0 else { return nil }; seen |= 4; f.t = val
                    default: return nil
                    }
                } else if n == 2 {
                    let k = String(decoding: b[ns ..< ns + 2], as: UTF8.self)
                    guard k == "cm" || k == "vm" || k == "ph", !f.kept.contains(where: { $0.0 == k }) else { return nil }
                    f.kept.append((k, val))
                } else { return nil }
            }
            while true {
                while i < end, b[i] != UInt8(ascii: "<") { guard isSpace(b[i]) else { return nil }; i += 1 }
                guard i + 3 < end else { return nil }
                let c1 = b[i + 1]
                if c1 == UInt8(ascii: "/") {
                    guard b[i + 2] == UInt8(ascii: "c"), b[i + 3] == UInt8(ascii: ">") else { return nil }
                    i += 4
                    return f
                }
                if c1 == UInt8(ascii: "v") {
                    guard !f.hasV else { return nil }
                    f.hasV = true
                    if b[i + 2] == UInt8(ascii: "/") { guard b[i + 3] == UInt8(ascii: ">") else { return nil }; i += 4; continue }
                    // <v xml:space="preserve">: the tree reader keeps every character of a text, so the attribute changes nothing.
                    if b[i + 2] == 0x20 {
                        let lit = Array(" xml:space=\"preserve\">".utf8)
                        guard i + 2 + lit.count < end, b[(i + 2) ..< (i + 2 + lit.count)].elementsEqual(lit) else { return nil }
                        i += lit.count - 1
                    }
                    guard b[i + 2] == UInt8(ascii: ">") else { return nil }
                    i += 3
                    let ts = i
                    while i < end, b[i] != UInt8(ascii: "<") { i += 1 }
                    guard i + 3 < end, b[i + 1] == UInt8(ascii: "/"), b[i + 2] == UInt8(ascii: "v"), b[i + 3] == UInt8(ascii: ">") else { return nil }
                    f.v = decode(b[ts ..< i])
                    i += 4
                    continue
                }
                if c1 == UInt8(ascii: "f") {
                    guard !f.hasF else { return nil }
                    f.hasF = true
                    i += 2
                    var fseen: UInt8 = 0
                    var selfClosed = false
                    while true {
                        while i < end, isSpace(b[i]) { i += 1 }
                        guard i < end else { return nil }
                        if b[i] == UInt8(ascii: ">") { i += 1; break }
                        if b[i] == UInt8(ascii: "/") { guard i + 1 < end, b[i + 1] == UInt8(ascii: ">") else { return nil }; i += 2; selfClosed = true; break }
                        let ns = i
                        while i < end, !isSpace(b[i]), b[i] != UInt8(ascii: "="), b[i] != UInt8(ascii: ">"), b[i] != UInt8(ascii: "/") { i += 1 }
                        let k = String(decoding: b[ns ..< i], as: UTF8.self)
                        while i < end, isSpace(b[i]) { i += 1 }
                        guard i < end, b[i] == UInt8(ascii: "=") else { return nil }
                        i += 1
                        while i < end, isSpace(b[i]) { i += 1 }
                        guard let val = quotedValue(end) else { return nil }
                        switch k {
                        case "t": guard fseen & 1 == 0 else { return nil }; fseen |= 1; f.fT = val
                        case "si": guard fseen & 2 == 0 else { return nil }; fseen |= 2; f.fSi = val
                        case "ref": guard fseen & 4 == 0 else { return nil }; fseen |= 4; f.fRef = val
                        default:
                            // Any other plain name (ca, aca, ...) goes to fExtra, as the tree reader does; a prefixed or
                            // repeated name is left to the tree.
                            guard !k.isEmpty, !k.utf8.contains(UInt8(ascii: ":")), !f.fExtra.contains(where: { $0.0 == k }) else { return nil }
                            f.fExtra.append((k, val))
                        }
                    }
                    if selfClosed { continue }
                    let ts = i
                    while i < end, b[i] != UInt8(ascii: "<") { i += 1 }
                    guard i + 3 < end, b[i + 1] == UInt8(ascii: "/"), b[i + 2] == UInt8(ascii: "f"), b[i + 3] == UInt8(ascii: ">") else { return nil }
                    f.fText = decode(b[ts ..< i])
                    i += 4
                    continue
                }
                return nil
            }
        }

        mutating func readNameRange() -> Range<Int> {
            let start = i
            while !atEnd {
                let c = b[i]
                if c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == UInt8(ascii: ">")
                    || c == UInt8(ascii: "/") || c == UInt8(ascii: "=") { break }
                i += 1
            }
            return start ..< i
        }

        mutating func readName() -> String {
            let start = i
            while !atEnd {
                let c = b[i]
                if c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == UInt8(ascii: ">")
                    || c == UInt8(ascii: "/") || c == UInt8(ascii: "=") { break }
                i += 1
            }
            return String(decoding: b[start..<i], as: UTF8.self)
        }

        /// Text with entity and character references resolved, and the
        /// white space a parser normalises before anyone sees it: a line
        /// end written CR LF or CR is one LF (XML 1.0 §2.11), and in an
        /// attribute value a literal tab or line end is a space (§3.3.3).
        /// A character REFERENCE to one of them is kept as written —
        /// which is how a file says it means a carriage return. (A CDATA
        /// section's bytes are not touched: the system's parser hands them
        /// on as they are, and this reads what that reads.)
        func decode(_ slice: ArraySlice<UInt8>, attribute: Bool = false) -> String {
            var plain = true
            for c in slice where c == UInt8(ascii: "&") || c == 0x0D || (attribute && (c == 0x0A || c == 0x09)) { plain = false; break }
            if plain { return String(decoding: slice, as: UTF8.self) }
            var out: [UInt8] = []
            var j = slice.startIndex
            while j < slice.endIndex {
                if slice[j] == 0x0D {
                    out.append(attribute ? 0x20 : 0x0A)
                    j += 1
                    if j < slice.endIndex, slice[j] == 0x0A { j += 1 }
                    continue
                }
                if attribute, slice[j] == 0x0A || slice[j] == 0x09 {
                    out.append(0x20)
                    j += 1
                    continue
                }
                if slice[j] == UInt8(ascii: "&"), let semi = slice[j...].firstIndex(of: UInt8(ascii: ";")), semi - j <= 10 {
                    let ref = String(decoding: slice[(j + 1)..<semi], as: UTF8.self)
                    var scalar: Unicode.Scalar?
                    switch ref {
                    case "lt": scalar = "<"
                    case "gt": scalar = ">"
                    case "amp": scalar = "&"
                    case "quot": scalar = "\""
                    case "apos": scalar = "'"
                    default:
                        if ref.hasPrefix("#x"), let v = UInt32(ref.dropFirst(2), radix: 16) { scalar = Unicode.Scalar(v) }
                        else if ref.hasPrefix("#"), let v = UInt32(ref.dropFirst(1)) { scalar = Unicode.Scalar(v) }
                    }
                    if let scalar {
                        out.append(contentsOf: Array(String(scalar).utf8))
                        j = semi + 1
                        continue
                    }
                }
                out.append(slice[j])
                j += 1
            }
            return String(decoding: out, as: UTF8.self)
        }
    }
}
