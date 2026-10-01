// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The sheet elements kept as the file wrote them that still name cells:
// conditional formats, data validations, hyperlinks, ignored-error marks
// and protected ranges. When rows or columns move, their ranges (`sqref`,
// `ref`) and formulas (`<formula>`, `<formula1>`, `<formula2>`) move
// with the cells; an element left covering nothing is dropped, as Excel
// drops it. Everything else in them is untouched text.
//
// The x14 versions inside extLst (conditional formats, validations,
// sparklines) are reached too: `<xm:sqref>` with the cells, `<xm:f>` through
// the formula rewriter (so a sparkline reading another sheet follows it).
// Manual page breaks (`rowBreaks`/`colBreaks`) move with their rows/columns.

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

    /// extLst's `<xm:sqref>` ranges mapped (an element left with none keeps
    /// its old text — the x14 parts are never dropped piecemeal).
    static func shiftExtRanges(_ text: String, range: (CellRange) -> CellRange?) -> String {
        _mapTag(text, "xm:sqref") { inner in
            let mapped = inner.split(separator: " ").compactMap { part -> String? in
                guard let r = CellRange(String(part)) else { return String(part) }
                return range(r).map { $0.isSingle ? $0.topLeft.a1 : $0.a1 }
            }
            return mapped.isEmpty ? inner : mapped.joined(separator: " ")
        }
    }

    /// extLst's `<xm:f>` formulas mapped reference by reference.
    static func shiftExtFormulas(_ text: String, ref: (FormulaRef) -> FormulaRef?) -> String {
        _mapTag(text, "xm:f") { inner in
            let f = inner.replacingAll("&lt;", with: "<").replacingAll("&gt;", with: ">").replacingAll("&quot;", with: "\"")
                .replacingAll("&apos;", with: "'").replacingAll("&amp;", with: "&")
            guard let e = try? Formula.parse("=" + f) else { return inner }
            let g = Formula.mapRefs(e, ref)
            return g == e ? inner : Xlsx._esc(Formula.print(g))
        }
    }

    /// `<brk id="N" …/>` in rowBreaks/colBreaks: N is the row (column)
    /// the break comes before, zero-based as cells are one-based.
    static func shiftBreaks(_ text: String, moved: (Int) -> Int?) -> String? {
        var s = ""
        var at = text.startIndex
        var count = 0
        while let a = text.findRange(of: "<brk ", in: at ..< text.endIndex),
              let b = text.findRange(of: "/>", in: a.upperBound ..< text.endIndex) {
            s += text[at ..< a.lowerBound]
            at = b.upperBound
            var brk = String(text[a.lowerBound ..< b.upperBound])
            if let i0 = brk.findRange(of: " id=\""), let i1 = brk.findRange(of: "\"", in: i0.upperBound ..< brk.endIndex),
               let id = Int(brk[i0.upperBound ..< i1.lowerBound]) {
                guard let n = moved(id) else { continue }
                brk.replaceSubrange(i0.upperBound ..< i1.lowerBound, with: "\(n)")
            }
            count += 1
            s += brk
        }
        s += text[at...]
        guard count > 0 else { return nil }
        for attr in [" count=\"", " manualBreakCount=\""] {
            if let r = s.findRange(of: attr), let q = s.findRange(of: "\"", in: r.upperBound ..< s.endIndex) {
                s.replaceSubrange(r.upperBound ..< q.lowerBound, with: "\(count)")
            }
        }
        return s
    }

    private static func _mapTag(_ text: String, _ tag: String, _ f: (String) -> String) -> String {
        var s = ""
        var at = text.startIndex
        while let a = text.findRange(of: "<\(tag)>", in: at ..< text.endIndex),
              let b = text.findRange(of: "</\(tag)>", in: a.upperBound ..< text.endIndex) {
            s += text[at ..< a.upperBound]
            s += f(String(text[a.upperBound ..< b.lowerBound]))
            at = b.lowerBound
        }
        return s + text[at...]
    }
}
