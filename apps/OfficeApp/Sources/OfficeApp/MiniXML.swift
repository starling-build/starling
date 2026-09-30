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

    private struct Parser {
        let b: [UInt8]
        var i = 0
        init(_ bytes: [UInt8]) { b = bytes }

        var atEnd: Bool { i >= b.count }
        func peek(_ s: String) -> Bool { b[i...].starts(with: s.utf8) }
        mutating func skipSpace() { while !atEnd, [0x20, 0x09, 0x0A, 0x0D].contains(b[i]) { i += 1 } }
        mutating func skip(past marker: String) {
            let m = Array(marker.utf8)
            while i + m.count <= b.count {
                if b[i..<i + m.count].elementsEqual(m) { i += m.count; return }
                i += 1
            }
            i = b.count
        }

        mutating func document() -> XNode? {
            var root: XNode?
            var stack: [XNode] = []
            while !atEnd {
                if b[i] != UInt8(ascii: "<") {
                    let start = i
                    while !atEnd, b[i] != UInt8(ascii: "<") { i += 1 }
                    if let top = stack.last { top.text += decode(b[start..<i]) }
                    continue
                }
                if peek("<?") { skip(past: "?>"); continue }
                if peek("<!--") { skip(past: "-->"); continue }
                if peek("<![CDATA[") {
                    i += 9
                    let start = i
                    skip(past: "]]>")
                    if let top = stack.last { top.text += String(decoding: b[start..<max(start, i - 3)], as: UTF8.self) }
                    continue
                }
                if peek("<!") { skip(past: ">"); continue }
                if peek("</") {
                    i += 2
                    skip(past: ">")
                    _ = stack.popLast()
                    continue
                }
                i += 1
                let name = readName()
                var attrs: [String: String] = [:]
                var selfClosing = false
                while true {
                    skipSpace()
                    guard !atEnd else { return root }
                    if b[i] == UInt8(ascii: ">") { i += 1; break }
                    if peek("/>") { i += 2; selfClosing = true; break }
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
                            value = decode(b[start..<i])
                            if !atEnd { i += 1 }
                        }
                    }
                    attrs[key] = value
                }
                let node = XNode(name: name, attrs: attrs)
                if let parent = stack.last { parent.children.append(node) } else if root == nil { root = node }
                if !selfClosing { stack.append(node) }
            }
            return root
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

        /// Text with entity and character references resolved.
        func decode(_ slice: ArraySlice<UInt8>) -> String {
            guard slice.contains(UInt8(ascii: "&")) else { return String(decoding: slice, as: UTF8.self) }
            var out: [UInt8] = []
            var j = slice.startIndex
            while j < slice.endIndex {
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
