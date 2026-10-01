// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The sheet elements kept as the file wrote them that still name cells:
// conditional formats, data validations, hyperlinks, ignored-error marks
// and protected ranges. When rows or columns move, their ranges (`sqref`,
// `ref`) and formulas (`<formula>`, `<formula1>`, `<formula2>`) move
// with the cells; an element left covering nothing is dropped, as Excel
// drops it. Everything else in them is untouched text.
//
// Not reached: the x14 versions inside extLst (`xm:sqref`, `xm:f`).

import Foundation

enum KeptRefs {
    /// The kept elements that hold cell references.
    static let elements: Set<String> = ["conditionalFormatting", "dataValidations", "hyperlinks", "ignoredErrors", "protectedRanges"]

    /// `text` with its ranges and formulas mapped; nil when nothing is left.
    static func shift(_ name: String, _ text: String, range: (CellRange) -> CellRange?, ref: (FormulaRef) -> FormulaRef?) -> String? {
        switch name {
        case "conditionalFormatting":
            return _element(text, range: range, ref: ref)
        case "dataValidations", "hyperlinks", "ignoredErrors", "protectedRanges":
            // A list: each child on its own; the list goes when they all do.
            let split = RawXML.split([UInt8](text.utf8))
            let kids = split.children.compactMap { _element($0.text, range: range, ref: ref) }
            guard !kids.isEmpty else { return nil }
            var start = split.rootStart
            if let r = start.findRange(of: " count=\"") {
                let close = start.findRange(of: "\"", in: r.upperBound ..< start.endIndex)?.lowerBound ?? start.endIndex
                start.replaceSubrange(r.upperBound ..< close, with: "\(kids.count)")
            }
            return start + kids.joined() + "</\(split.rootName)>"
        default:
            return text
        }
    }

    /// One element: its own range attribute, then its formulas.
    private static func _element(_ text: String, range: (CellRange) -> CellRange?, ref: (FormulaRef) -> FormulaRef?) -> String? {
        var s = text
        // The start tag's range attribute (sqref or ref), the first one only.
        guard let tagEnd = s.firstIndex(of: ">") else { return s }
        for attr in [" sqref=\"", " ref=\""] {
            guard let a = s.findRange(of: attr, in: s.startIndex ..< tagEnd),
                  let b = s.findRange(of: "\"", in: a.upperBound ..< s.endIndex) else { continue }
            let ranges = s[a.upperBound ..< b.lowerBound].split(separator: " ").compactMap { part -> String? in
                guard let r = CellRange(String(part)) else { return String(part) }
                return range(r).map { $0.isSingle ? $0.topLeft.a1 : $0.a1 }
            }
            if ranges.isEmpty { return nil }
            s.replaceSubrange(a.upperBound ..< b.lowerBound, with: ranges.joined(separator: " "))
            break
        }
        for tag in ["formula", "formula1", "formula2"] {
            var at = s.startIndex
            while let a = s.findRange(of: "<\(tag)>", in: at ..< s.endIndex),
                  let b = s.findRange(of: "</\(tag)>", in: a.upperBound ..< s.endIndex) {
                let raw = String(s[a.upperBound ..< b.lowerBound])
                let f = raw.replacingAll("&lt;", with: "<").replacingAll("&gt;", with: ">").replacingAll("&quot;", with: "\"")
                    .replacingAll("&apos;", with: "'").replacingAll("&amp;", with: "&")
                var replacement = raw
                if let e = try? Formula.parse("=" + f) {
                    let g = Formula.mapRefs(e, ref)
                    if g != e { replacement = Xlsx._esc(Formula.print(g)) }
                }
                s.replaceSubrange(a.upperBound ..< b.lowerBound, with: replacement)
                at = s.findRange(of: "</\(tag)>", in: a.upperBound ..< s.endIndex)?.upperBound ?? s.endIndex
            }
        }
        return s
    }
}
