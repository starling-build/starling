// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Flutter

/// A small semantic view of a document, shared by generated HTML and the live
/// reader's text layer. It never accepts document-authored HTML.
struct SiteReaderText: Codable {
    struct Span: Codable {
        var text: String
        var link: String?
    }
    struct Paragraph: Codable {
        var id: UInt32?
        var level: Int
        var spans: [Span]
    }
    struct Downloads: Codable {
        var pdf: String
        var docx: String
    }
    var version = 1
    var title: String?
    var paragraphs: [Paragraph]
    var downloads: Downloads?

    init(document: RichDocument, title: String? = nil, route: String? = nil, downloads: (pdf: String, docx: String)? = nil) {
        self.title = title
        self.downloads = downloads.map { Downloads(pdf: $0.pdf, docx: $0.docx) }
        let ids = Set(document.paragraphs.map(\.id).filter { $0 != 0 })
        var bookmarks: [String: UInt32] = [:]
        for paragraph in document.paragraphs where paragraph.id != 0 {
            for name in paragraph.bookmarks where bookmarks[name] == nil { bookmarks[name] = paragraph.id }
        }
        var seen = Set<UInt32>()
        paragraphs = document.paragraphs.map { paragraph in
            let id = paragraph.id != 0 && seen.insert(paragraph.id).inserted ? paragraph.id : nil
            let level = paragraph.style.named == "Title" ? 1 : (paragraph.style.heading.map { min(3, max(1, $0)) } ?? 0)
            let units = Array(paragraph.text.utf16)
            var spans: [Span] = []
            var offset = 0
            var valid = true
            for run in paragraph.runs {
                guard run.length >= 0, run.length <= units.count - offset else { valid = false; break }
                let end = offset + run.length
                // A malformed format boundary must not split a surrogate pair.
                if end > 0 && end < units.count && (0xD800...0xDBFF).contains(units[end - 1]) && (0xDC00...0xDFFF).contains(units[end]) {
                    valid = false; break
                }
                let text = String(decoding: units[offset..<end], as: UTF16.self)
                if !text.isEmpty { spans.append(Span(text: text, link: Self.link(run.style.link, bookmarks: bookmarks, ids: ids, route: route))) }
                offset = end
            }
            if !valid || offset != units.count { spans = [Span(text: paragraph.text, link: nil)] }
            return Paragraph(id: id, level: level, spans: spans)
        }
    }

    private static func link(_ input: String?, bookmarks: [String: UInt32], ids: Set<UInt32>, route: String?) -> String? {
        guard let input else { return nil }
        let value = input.trimmingWhitespace()
        guard !value.isEmpty, !value.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else { return nil }
        if value.hasPrefix("#") {
            // A fragment alone resolves against the shell's <base>, which is
            // the publication root. Include the page route for nested pages.
            let prefix = route ?? ""
            guard prefix.isEmpty || (prefix.hasPrefix("/") && !prefix.hasPrefix("//")
                && !prefix.contains(where: { $0 == "\\" || $0 == "?" || $0 == "#" })
                && !prefix.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 })) else { return nil }
            let name = String(value.dropFirst())
            if let id = bookmarks[name] { return prefix + "#p=\(id)" }
            if name.hasPrefix("p="), let id = UInt32(name.dropFirst(2)), ids.contains(id) { return prefix + "#p=\(id)" }
            return nil
        }
        // Relative file references need an import mapping before they can be
        // promised as website links. Retain their text until that exists.
        guard let url = URLComponents(string: value), let scheme = url.scheme?.lowercased(),
              ["http", "https", "mailto"].contains(scheme) else { return nil }
        if scheme != "mailto", url.host?.isEmpty != false { return nil }
        return url.url?.absoluteString
    }

    func json() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    var html: String {
        paragraphs.map { paragraph in
            let tag = (1...3).contains(paragraph.level) ? "h\(paragraph.level)" : "p"
            let anchor = paragraph.id.map { " id=\"p=\($0)\"" } ?? ""
            let spans = paragraph.spans.map { span -> String in
                let text = Self.escape(span.text)
                return span.link.map { "<a href=\"\(Self.escape($0))\">\(text)</a>" } ?? text
            }.joined()
            return "<\(tag)\(anchor)>\(spans)</\(tag)>"
        }.joined(separator: "\n")
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
