// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import OfficeText

/// W-FD-1d: the document's properties (docProps/core.xml): title, subject, author, keywords, comments, last saved by,
/// created and modified. The part is kept as the file had it; only the elements the app knows are edited, in place.
enum DocProperties {
    /// The element for a property: its prefix and local name.
    static let element: [String: (prefix: String, local: String)] = [
        "title": ("dc", "title"), "subject": ("dc", "subject"), "creator": ("dc", "creator"), "description": ("dc", "description"),
        "keywords": ("cp", "keywords"), "lastModifiedBy": ("cp", "lastModifiedBy"),
        "created": ("dcterms", "created"), "modified": ("dcterms", "modified"),
    ]

    static let empty = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<cp:coreProperties xmlns:cp=\"http://schemas.openxmlformats.org/package/2006/metadata/core-properties\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:dcterms=\"http://purl.org/dc/terms/\" xmlns:dcmitype=\"http://purl.org/dc/dcmitype/\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"></cp:coreProperties>"

    static func escape(_ s: String) -> String {
        s.replacingAll("&", with: "&amp;").replacingAll("<", with: "&lt;").replacingAll(">", with: "&gt;")
    }

    /// The part's XML with `key` set to `value` (the element made where it was missing).
    static func setting(_ key: String, to value: String, in xml: String) -> String {
        guard let e = element[key] else { return xml }
        let body = key == "created" || key == "modified" ? "<\(e.prefix):\(e.local) xsi:type=\"dcterms:W3CDTF\">\(escape(value))</\(e.prefix):\(e.local)>"
                                                           : "<\(e.prefix):\(e.local)>\(escape(value))</\(e.prefix):\(e.local)>"
        var out = xml
        for prefix in ["dc", "cp", "dcterms"] {
            let open = "<\(prefix):\(e.local)"
            guard let r = out.rangeOfSubstring(open) else { continue }
            let after = out[r.upperBound...]
            guard let c = after.first, c == ">" || c == " " || c == "/" else { continue }
            if let close = out.rangeOfSubstring("</\(prefix):\(e.local)>", in: r.upperBound ..< out.endIndex) {
                out.replaceSubrange(r.lowerBound ..< close.upperBound, with: body)
            } else if let end = out.rangeOfSubstring("/>", in: r.upperBound ..< out.endIndex) {
                out.replaceSubrange(r.lowerBound ..< end.upperBound, with: body)
            } else { continue }
            return out
        }
        if let end = out.rangeOfSubstring("</cp:coreProperties>") { out.replaceSubrange(end.lowerBound ..< end.lowerBound, with: body) }
        return out
    }

    /// W3CDTF in UTC: OFFICE_NOW when set (tests), else the machine's clock.
    static func stamp() -> String {
        func two(_ n: Int) -> String { n < 10 ? "0\(n)" : String(n) }
        #if canImport(Glibc) || canImport(Darwin)
        var c: (Int, Int, Int, Int, Int, Int)?
        if let p = getenv("OFFICE_NOW"), let k = FieldClock.parse(String(cString: p)) { c = (k.year, k.month, k.day, k.hour, k.minute, k.second) }
        else {
            var t = time(nil); var tmv = tm()
            if gmtime_r(&t, &tmv) != nil { c = (Int(tmv.tm_year) + 1900, Int(tmv.tm_mon) + 1, Int(tmv.tm_mday), Int(tmv.tm_hour), Int(tmv.tm_min), Int(tmv.tm_sec)) }
        }
        if let c { return "\(c.0)-\(two(c.1))-\(two(c.2))T\(two(c.3)):\(two(c.4)):\(two(c.5))Z" }
        #endif
        return "2000-01-01T00:00:00Z"
    }

    /// The signed-in user's name, "" where there is none (the web).
    static func userName() -> String {
        #if canImport(Glibc) || canImport(Darwin)
        let env = ProcessInfo.processInfo.environment
        return env["OFFICE_USER"] ?? env["USER"] ?? env["USERNAME"] ?? ""
        #else
        return ""
        #endif
    }
}

extension RichDocument {
    /// A property of the document (`title`, `subject`, `creator`, `keywords`, `description`, `lastModifiedBy`).
    func property(_ key: String) -> String { FieldEvaluator.properties(keptParts: keptParts)[key] ?? "" }

    /// Set a property in docProps/core.xml (the part, its content type and its link made if the document had none).
    mutating func setProperty(_ key: String, _ value: String) {
        let xml = keptParts["docProps/core.xml"].map { String(decoding: $0, as: UTF8.self) } ?? DocProperties.empty
        keptParts["docProps/core.xml"] = Data(DocProperties.setting(key, to: value, in: xml).utf8)
        keptPartTypes["docProps/core.xml"] = "application/vnd.openxmlformats-package.core-properties+xml"
        if !keptRootRels.contains(where: { $0.type.hasSuffix("core-properties") }) {
            keptRootRels.append(KeptRel(id: "", type: "http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties",
                                        target: "docProps/core.xml", external: false))
        }
    }

    /// What a save does to the properties: modified now, last saved by the user; created and author for a document
    /// that had no properties yet.
    mutating func stampSaved() {
        let user = DocProperties.userName(), now = DocProperties.stamp()
        if property("created").isEmpty {
            setProperty("created", now)
            if property("creator").isEmpty, !user.isEmpty { setProperty("creator", user) }
        }
        setProperty("modified", now)
        if !user.isEmpty { setProperty("lastModifiedBy", user) }
    }
}

extension RichDocumentController {
    /// File → Info → Properties: the values the dialog holds, in one undo step (an unchanged one is left alone).
    func setProperties(_ values: [String: String]) {
        guard !readOnly else { return }
        var doc = document
        for (k, v) in values where doc.property(k) != v { doc.setProperty(k, v) }
        let old = PropertyParts(document), new = PropertyParts(doc)
        guard old != new else { return }
        edit { perform(.setProperties(new: new, old: old)) }
    }
}
