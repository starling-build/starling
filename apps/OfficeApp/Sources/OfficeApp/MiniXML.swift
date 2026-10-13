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

    private struct Parser {
        let b: [UInt8]
        var i = 0
        init(_ bytes: [UInt8]) { b = bytes }

        /// The list left out of the tree (`parse(_:emptying:)`), or — with
        /// `listItem` and `each` — the only thing built.
        var listParent: [UInt8]? = nil
        var listItem: [UInt8]? = nil
        var each: ((XNode) -> Void)? = nil

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
                    if let closed = stack.popLast(), closed.isItem, let node = closed.node { each?(node) }
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
                let node = XNode(name: String(decoding: b[name], as: UTF8.self), attrs: attrs)
                frame.node = node
                if frame.isItem {
                    if selfClosing { each?(node) }
                } else if let parent = top?.node {
                    parent.children.append(node)
                } else if root == nil, top == nil || !itemsOnly {
                    root = node
                }
                if !selfClosing { stack.append(frame) }
            }
            return root
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
