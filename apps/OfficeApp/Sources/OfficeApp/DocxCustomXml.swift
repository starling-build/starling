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


// Part of the .docx reader/writer: saving what was typed into content controls bound to custom XML parts.

extension DocxFormat {
    /// One element of a small XML scan: where its tags sit in the text.
    private struct _XmlSpan {
        var local: String
        var tagStart: String.Index        // the "<" of the opening tag
        var contentStart: String.Index    // just after the opening tag's ">" (for a self-closing tag: after its "/>")
        var contentEnd: String.Index      // the "<" of the closing tag (for a self-closing tag: = contentStart)
        var selfClosing: Bool
        var children: [Int] = []
    }

    /// The elements of `xml`, document element first (index 0); each lists its child elements by index.
    private static func _scanXml(_ xml: String) -> [_XmlSpan] {
        var spans: [_XmlSpan] = []
        var stack: [Int] = []
        var i = xml.startIndex
        func skip(_ marker: String, from: String.Index) -> String.Index {
            xml.rangeOfSubstring(marker, in: from ..< xml.endIndex)?.upperBound ?? xml.endIndex
        }
        while i < xml.endIndex {
            guard let lt = xml[i...].firstIndex(of: "<") else { break }
            let rest = xml[lt...]
            if rest.hasPrefix("<?") { i = skip("?>", from: lt); continue }
            if rest.hasPrefix("<!--") { i = skip("-->", from: lt); continue }
            if rest.hasPrefix("<![CDATA[") { i = skip("]]>", from: lt); continue }
            if rest.hasPrefix("<!") { i = skip(">", from: lt); continue }
            guard let gt = xml[lt...].firstIndex(of: ">") else { break }
            let after = xml.index(after: gt)
            if rest.hasPrefix("</") {
                if let top = stack.popLast() { spans[top].contentEnd = lt }
                i = after
                continue
            }
            let tag = xml[xml.index(after: lt) ..< gt]
            let selfClosing = tag.hasSuffix("/")
            let nameEnd = tag.firstIndex { $0 == " " || $0 == "/" || $0 == "\n" || $0 == "\t" || $0 == "\r" } ?? tag.endIndex
            let qname = String(tag[tag.startIndex ..< nameEnd])
            let local = String(qname.split(separator: ":").last ?? "")
            let index = spans.count
            spans.append(_XmlSpan(local: local, tagStart: lt, contentStart: after, contentEnd: after, selfClosing: selfClosing))
            if let parent = stack.last { spans[parent].children.append(index) }
            if !selfClosing { stack.append(index) }
            i = after
        }
        return spans
    }

    /// Follow a binding path (`/ns0:root[1]/ns0:a[1]`; prefixes ignored, position 1-based among same-named siblings).
    private static func _spanForPath(_ spans: [_XmlSpan], _ xpath: String) -> Int? {
        guard !spans.isEmpty else { return nil }
        var at = -1
        for (n, step) in xpath.split(separator: "/").map(String.init).enumerated() {
            let name = String(step.split(separator: "[").first ?? "")
            let local = String(name.split(separator: ":").last ?? "")
            var position = 1
            if let open = step.firstIndex(of: "["), let close = step.firstIndex(of: "]"), open < close,
               let k = Int(step[step.index(after: open) ..< close]) { position = k }
            let candidates = n == 0 ? [0] : spans[at].children
            let same = candidates.filter { local == "*" || spans[$0].local == local }
            guard n > 0 || (same.count == 1 && position == 1), position >= 1, position <= same.count else { return nil }
            at = same[position - 1]
        }
        return at >= 0 ? at : nil
    }

    private static func _xmlEscapedText(_ s: String) -> String {
        s.replacingAll("&", with: "&amp;").replacingAll("<", with: "&lt;").replacingAll(">", with: "&gt;")
    }

    /// Save what the user typed into controls bound to custom XML: each bound element of the kept custom XML parts takes
    /// the text its control shows (an edit already made every control on the element agree). An element the part lacks,
    /// or one that holds child elements, is left alone.
    static func _writeBackBoundValues(_ doc: inout RichDocument) {
        var wanted: [(store: String, xpath: String, text: String)] = []
        var seen = Set<String>()
        for p in doc.paragraphs {
            for c in p.customBoundControls where seen.insert(c.store + "|" + c.xpath).inserted && doc.boundLoaded[c.store + "|" + c.xpath] != c.text { wanted.append((c.store, c.xpath, c.text)) }
        }
        guard !wanted.isEmpty else { return }
        for n in 1...64 {
            guard let props = doc.keptParts["customXml/itemProps\(n).xml"].flatMap({ XNode.parse($0) }),
                  let id = props["ds:itemID"]?.uppercased(), let data = doc.keptParts["customXml/item\(n).xml"] else { continue }
            var xml = String(decoding: data, as: UTF8.self)
            var edited = false
            for w in wanted where w.store == id {
                let spans = _scanXml(xml)
                guard let k = _spanForPath(spans, w.xpath), spans[k].children.isEmpty else { continue }
                let span = spans[k]
                let shown = _xmlEscapedText(w.text)
                if span.selfClosing {
                    guard !w.text.isEmpty, let slash = xml[span.tagStart ..< span.contentStart].lastIndex(of: "/") else { continue }
                    let open = String(xml[span.tagStart ..< slash]).trimmingWhitespace(newlines: true)
                    let name = String(open.dropFirst().split(separator: " ").first ?? "")
                    xml.replaceSubrange(slash ..< span.contentStart, with: ">" + shown + "</" + name + ">")
                    edited = true
                } else if String(xml[span.contentStart ..< span.contentEnd]) != shown {
                    xml.replaceSubrange(span.contentStart ..< span.contentEnd, with: shown)
                    edited = true
                }
            }
            if edited { doc.keptParts["customXml/item\(n).xml"] = Data(xml.utf8) }
        }
    }
}
