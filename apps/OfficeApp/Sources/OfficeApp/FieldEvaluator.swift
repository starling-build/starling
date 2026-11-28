// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// W-FD-1: what a field shows when it is brought up to date (F9). DATE and TIME show the clock's moment in
// their picture (English names, the app's own Date & Time); AUTHOR, TITLE and the like show the document's
// properties. A field this does not know keeps what it showed.

import Foundation
import OfficeText

enum FieldEvaluator {
    /// The core property each field word shows.
    static let propertyOf: [String: String] = [
        "AUTHOR": "creator", "TITLE": "title", "SUBJECT": "subject", "KEYWORDS": "keywords",
        "COMMENTS": "description", "LASTSAVEDBY": "lastModifiedBy",
    ]

    /// The document's core properties by element name (`creator`, `title`...), from the kept `docProps/core.xml`.
    static func properties(keptParts: [String: Data]) -> [String: String] {
        guard let data = keptParts["docProps/core.xml"], let root = XNode.parse(data) else { return [:] }
        var out: [String: String] = [:]
        for c in root.children {
            guard let local = c.name.split(separator: ":").last else { continue }
            out[String(local)] = c.text.trimmingWhitespace(newlines: true)
        }
        return out
    }

    /// The text for `instruction`, or nil to leave `shown` as it is.
    /// `path`: the document's file (FILENAME shows its name, with `\p` the whole path); nil while it has none.
    static func evaluate(_ instruction: String, shown: String, clock: FieldClock?, properties: [String: String],
                         path: String? = nil) -> String? {
        let words = instruction.split(whereSeparator: { $0 == " " || $0 == "\t" })
        let word = words.first?.uppercased() ?? ""
        if word == "DATE" || word == "TIME" { return clock?.text(instr: instruction, cached: shown, english: true) }
        if word == "FILENAME" {
            guard let path, !path.isEmpty else { return nil }
            if words.contains(where: { $0.lowercased() == "\\p" }) { return path }
            return path.split(separator: "/").last.map(String.init) ?? path
        }
        if let key = propertyOf[word], let value = properties[key] { return value.isEmpty ? nil : value }
        return nil
    }
}

extension RichDocumentController {
    /// Insert → Date & Time: the formatted moment as plain text, or (automatic) a DATE / TIME field F9 can refresh.
    func insertDateTime(picture: String, automatic: Bool, clock: FieldClock?) {
        let shown = clock?.format(picture: picture, english: true) ?? picture
        guard automatic else { insertText(shown); return }
        let isTime = picture.contains("h" as Character) || picture.contains("H" as Character)
        insertField(" \(isTime ? "TIME" : "DATE") \\@ \"\(picture)\" ", result: shown)
    }
}
