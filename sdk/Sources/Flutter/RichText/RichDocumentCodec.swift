// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The document as bytes, losslessly: what a server stores between edits
// (docs/plans/wiki.md), what a test compares, what crosses a process
// boundary. Every model type is `Codable` by synthesis; this file holds the
// two things synthesis cannot give — a `Color`, whose type lives in the
// bridge, and the paragraph identities a stored document must have — and
// the schema number that lets a reader refuse what it does not know.

import FlutterSwiftBridge
import Foundation

extension Color: Codable {
    // ARGB32, the way the file formats carry a colour: every colour the
    // readers make is eight bits a channel, so this is lossless for them
    // and compact for the wire. A wide-gamut colour would round. Through
    // Int64, never Int: an opaque colour is above Int32.max, and Int is 32
    // bits on wasm — `Int(UInt32)` trapped there on the first page with a
    // colour (2026-10-19).
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        self.init(try c.decode(Int64.self))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(Int64(toARGB32()))
    }
}

extension EdgeInsets: Codable {
    private enum Key: String, CodingKey { case left, top, right, bottom }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        self.init(left: try c.decode(Double.self, forKey: .left), top: try c.decode(Double.self, forKey: .top),
                  right: try c.decode(Double.self, forKey: .right), bottom: try c.decode(Double.self, forKey: .bottom))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        try c.encode(left, forKey: .left)
        try c.encode(top, forKey: .top)
        try c.encode(right, forKey: .right)
        try c.encode(bottom, forKey: .bottom)
    }
}

extension RichDocument {
    /// Give every paragraph without an id a fresh one, unique in this
    /// document. Idempotent: ids already set stay.
    public mutating func assignParagraphIDs() {
        var taken = Set(paragraphs.lazy.map(\.id).filter { $0 != 0 })
        for i in paragraphs.indices where paragraphs[i].id == 0 {
            var v = RichParagraph.freshID()
            while taken.contains(v) { v = RichParagraph.freshID() }
            taken.insert(v)
            paragraphs[i].id = v
        }
    }

    /// Whether every paragraph has an id and no two share one.
    public var paragraphIDsAreUnique: Bool {
        var seen = Set<UInt32>()
        for p in paragraphs {
            if p.id == 0 || !seen.insert(p.id).inserted { return false }
        }
        return true
    }
}

/// The stored form: a schema number and the document. The number goes up
/// when a reader of the old form could misread the new one; adding a
/// field with a default does not count, since the decoder fills it.
public struct RichDocumentEnvelope: Codable, Sendable {
    public static let currentSchema = 1

    public var schema: Int
    public var document: RichDocument
    /// The page the document was laid out for, when it came from a file
    /// that had one; nil is "flow only" (an older envelope, or a page made
    /// from text). A paged reader uses it; the decoder fills nil.
    public var pageSetup: PageSetup? = nil

    public init(document: RichDocument, pageSetup: PageSetup? = nil) {
        self.schema = RichDocumentEnvelope.currentSchema
        self.document = document
        self.pageSetup = pageSetup
    }

    public enum Failure: Error, CustomStringConvertible {
        case unknownSchema(Int)
        public var description: String {
            switch self {
            case .unknownSchema(let n): return "document schema \(n) is newer than this reader (\(RichDocumentEnvelope.currentSchema))"
            }
        }
    }

    /// JSON, keys sorted so two encodings of one document are one string.
    public static func encode(_ document: RichDocument, pageSetup: PageSetup? = nil) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        // Floating-point edge values a layout can produce must survive.
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return try encoder.encode(RichDocumentEnvelope(document: document, pageSetup: pageSetup))
    }

    public static func decode(_ data: Data) throws -> RichDocument {
        try decodeEnvelope(data).document
    }

    /// The whole stored form: the document and, when stored, its page setup.
    public static func decodeEnvelope(_ data: Data) throws -> RichDocumentEnvelope {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        let envelope = try decoder.decode(RichDocumentEnvelope.self, from: data)
        guard envelope.schema <= currentSchema else { throw Failure.unknownSchema(envelope.schema) }
        return envelope
    }
}
