// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// One edit to a page, as the server sees it (docs/plans/wiki.md W5). The
// Writer's `EditOp` carries styles and paragraphs the server cannot read
// (they are the suite's types); here each op is its POSITIONS — paragraph
// index, UTF-16 offset, length — plus an opaque payload the server passes
// through untouched. Server-ordered OT needs only the positions: it shifts
// a late op past the ones that landed before it, and the payload is what
// the client meant, wherever that now is.

import Foundation

/// JSON the server stores and forwards but never interprets.
public struct Opaque: Codable, Hashable, Sendable {
    public var json: String
    public init(json: String) { self.json = json }
    /// Equal when the JSON means the same (key order is not meaning).
    public static func == (a: Opaque, b: Opaque) -> Bool {
        if a.json == b.json { return true }
        guard let x = JSONValue.parse(a.json), let y = JSONValue.parse(b.json) else { return false }
        return x == y
    }
    public func hash(into h: inout Hasher) { h.combine(JSONValue.parse(json)?.text ?? json) }
    public init(from decoder: Decoder) throws {
        // Whatever JSON stands here, kept verbatim as text.
        let any = try decoder.singleValueContainer().decode(JSONValue.self)
        json = any.text
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(JSONValue.parse(json) ?? .string(json))
    }
}

public enum PageOp: Codable, Hashable, Sendable {
    /// `text` inserted at `offset` of paragraph `para`; `runs` is the
    /// Writer's run list for it (opaque).
    case insertText(para: Int, offset: Int, text: String, runs: Opaque?)
    /// `length` UTF-16 units removed at `offset` of `para`; `removed` is
    /// what was there (text and runs, opaque), for the inverse.
    case deleteText(para: Int, offset: Int, length: Int, removed: Opaque?)
    /// Paragraph `para` cut at `offset`; the tail becomes `para + 1` with
    /// `tailStyle` (opaque).
    case splitParagraph(para: Int, offset: Int, tailStyle: Opaque?)
    /// Paragraph `para + 1` joined onto `para`, whose length before the
    /// join was `headLength`.
    case mergeParagraph(para: Int, headLength: Int, removedStyle: Opaque?)
    /// `count` whole paragraphs inserted before index `at` (`paragraphs`
    /// opaque).
    case insertParagraphs(at: Int, count: Int, paragraphs: Opaque)
    /// `count` whole paragraphs removed from index `at`.
    case removeParagraphs(at: Int, count: Int, paragraphs: Opaque)
    /// A whole-paragraph property: runs, style, picture. Positions: one
    /// paragraph; payload: old and new, opaque.
    case setParagraph(para: Int, what: String, payload: Opaque)
    /// A document-level change (header/footer, a table's columns, a style
    /// sheet entry, …): no positions, never transformed.
    case setDocument(what: String, payload: Opaque)

    /// The paragraph index the op is anchored at, if any.
    public var para: Int? {
        switch self {
        case .insertText(let p, _, _, _), .deleteText(let p, _, _, _), .splitParagraph(let p, _, _),
             .mergeParagraph(let p, _, _), .setParagraph(let p, _, _): return p
        case .insertParagraphs(let at, _, _), .removeParagraphs(let at, _, _): return at
        case .setDocument: return nil
        }
    }
}

/// A minimal JSON tree, enough to carry an opaque payload through Codable
/// without reordering or losing it.
public indirect enum JSONValue: Codable, Hashable, Sendable {
    case null, bool(Bool), number(Double), string(String), array([JSONValue]), object([(String, JSONValue)])

    public static func == (a: JSONValue, b: JSONValue) -> Bool { a.text == b.text }
    public func hash(into h: inout Hasher) { h.combine(text) }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let n = try? c.decode(Double.self) { self = .number(n); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([JSONValue].self) { self = .array(a); return }
        let o = try c.decode([String: JSONValue].self)
        self = .object(o.sorted { $0.key < $1.key }.map { ($0.key, $0.value) })
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(Dictionary(o, uniquingKeysWith: { _, b in b }))
        }
    }

    /// Compact JSON text.
    public var text: String {
        switch self {
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .number(let n): return n == n.rounded() && abs(n) < 1e15 ? String(Int64(n)) : String(n)
        case .string(let s): return JSONValue.quote(s)
        case .array(let a): return "[" + a.map(\.text).joined(separator: ",") + "]"
        case .object(let o): return "{" + o.map { JSONValue.quote($0.0) + ":" + $0.1.text }.joined(separator: ",") + "}"
        }
    }

    static func quote(_ s: String) -> String {
        var out = "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if u.value < 0x20 { out += String(format: "\\u%04x", u.value) } else { out.unicodeScalars.append(u) }
            }
        }
        return out + "\""
    }

    public static func parse(_ text: String) -> JSONValue? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }
}
