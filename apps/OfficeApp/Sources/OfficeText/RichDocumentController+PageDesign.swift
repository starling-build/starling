// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// W-PG-3: Design > Page Color and Page Borders, and the whole-document step the watermark uses.

import Foundation

extension RichDocumentController {
    /// Swap in a whole new document as one undo step (a change that rewrites parts the editor keeps as XML, such as a
    /// watermark in every header). The caret stays where it was, clamped into the new text.
    public func replaceDocument(with new: RichDocument) {
        guard new != document else { return }
        edit { perform(.replaceDocument(old: document, new: new)) }
        moveTo(document.clamped(selection.focus), extend: false)
    }

    /// Design > Page Color: a plain `w:background` colour (0xRRGGBB), or none. One undo step.
    public func setPageColor(_ color: UInt32?) {
        var d = document
        d.backgroundColor = color.flatMap { $0 == 0xFFFFFF ? nil : $0 }
        if let c = d.backgroundColor {
            d.backgroundXML = "<w:background w:color=\"\(RichDocumentController._hex6(c))\"/>"
        } else {
            d.backgroundXML = nil
        }
        d.backgroundRels = []
        replaceDocument(with: d)
    }

    static func _hex6(_ c: UInt32) -> String {
        let digits = Array("0123456789ABCDEF")
        return String((0 ..< 6).reversed().map { digits[Int((c >> (UInt32($0) * 4)) & 0xF)] })
    }

    /// What Design > Page Borders' "Apply to" offers.
    public enum PageBordersScope: Int, CaseIterable, Sendable {
        case wholeDocument, thisSection, thisSectionFirstPage, thisSectionAllButFirst
        public var title: String {
            switch self {
            case .wholeDocument: return "Whole document"
            case .thisSection: return "This section"
            case .thisSectionFirstPage: return "This section - First page only"
            case .thisSectionAllButFirst: return "This section - All except first page"
            }
        }
    }

    /// The page borders of the section holding the caret, as the dialog shows them (nil: none).
    public func sectionPageBorders() -> PageBorders? {
        let mark = sectionMark(containing: selection.focus.paragraph)
        let xml = mark < 0 ? document.pageBordersXML : PageBorders.ofSection(document.paragraphs[mark].style.sectionXML, document)
        return xml.flatMap(PageBorders.init(xml:))
    }

    /// Design > Page Borders: `borders` (nil or no sides: none) on the sections `scope` names. One undo step.
    public func setPageBorders(_ borders: PageBorders?, scope: PageBordersScope) {
        var b = borders
        switch scope {
        case .thisSectionFirstPage: b?.display = "firstPage"
        case .thisSectionAllButFirst: b?.display = "notFirstPage"
        case .wholeDocument, .thisSection: b?.display = nil
        }
        let xml = b.flatMap { $0.sides.isEmpty ? nil : $0.xml }
        var d = document
        let mark = sectionMark(containing: selection.focus.paragraph)
        if scope == .wholeDocument || mark < 0 { d.pageBordersXML = xml }
        for (i, p) in d.paragraphs.enumerated() where p.cell == nil && p.style.sectionPage != nil && i < d.paragraphs.count - 1 {
            guard let sect = p.style.sectionXML else { continue }
            let asLast = sect.containsSubstring(Self.sectionAsLast)
            if scope == .wholeDocument || i == mark {
                // A section made by a break in the last one is written as a copy of it: "none" needs its own mark there.
                d.paragraphs[i].style.sectionXML = PageBorders.replacing(in: sect, with: xml ?? (asLast && scope != .wholeDocument ? PageBorders.none : nil))
            } else if mark < 0, asLast, PageBorders.element(in: sect) == nil {
                // Only the last section changes: a copy of it keeps the borders it had.
                d.paragraphs[i].style.sectionXML = PageBorders.replacing(in: sect, with: document.pageBordersXML ?? PageBorders.none)
            }
        }
        replaceDocument(with: d)
    }

    /// Layout > Line Numbers on the caret's section (nil: none). One undo step. `lastSetup` is the last section's page.
    public func setLineNumbers(_ numbering: LineNumbering?, lastSetup: PageSetup) {
        let mark = sectionMark(containing: selection.focus.paragraph)
        var page = (mark < 0 ? (document.lastSectionPage ?? lastSetup) : (document.paragraphs[mark].style.sectionPage ?? lastSetup))
        page.lineNumbers = numbering
        guard let old = mark < 0 ? (document.lastSectionPage ?? lastSetup) : document.paragraphs[mark].style.sectionPage, old != page else { return }
        edit { perform(.setSectionPage(mark, old: old, new: page)) }
    }

    /// Layout > Line Numbers > Suppress for Current Paragraph: flips `w:suppressLineNumbers` on the selected paragraphs.
    public var lineNumbersSuppressed: Bool {
        document.paragraphs[document.clamped(selection.focus).paragraph].style.eastAsian["w:suppressLineNumbers"].map { $0 != "0" && $0 != "false" } ?? false
    }
    public func toggleSuppressLineNumbers() {
        let on = !lineNumbersSuppressed
        applyParagraphStyle { $0.eastAsian["w:suppressLineNumbers"] = on ? "1" : nil }
    }
}

/// A section's page borders as Word's dialog edits them: one line style, width and colour, on some of the four sides,
/// each its distance from the text or the page edge.
public struct PageBorders: Equatable, Sendable {
    public enum Side: String, CaseIterable, Sendable {
        case top, left, bottom, right
        public var title: String { self == .top ? "Top" : self == .left ? "Left" : self == .bottom ? "Bottom" : "Right" }
    }
    /// `w:val`: "single", "double", "dotted", "dashed", "thick", "thinThickSmallGap"…
    public var style = "single"
    /// `w:sz`, eighths of a point.
    public var width = 4
    /// 0xRRGGBB, nil for automatic.
    public var color: UInt32? = nil
    public var sides: Set<Side> = Set(Side.allCases)
    /// `w:space` by side, in points.
    public var space: [Side: Int] = [.top: 24, .left: 24, .bottom: 24, .right: 24]
    /// `w:offsetFrom`: "page" (Word's default for a new border) or "text".
    public var offsetFrom = "page"
    /// `w:display`: nil (all pages), "firstPage" or "notFirstPage".
    public var display: String? = nil
    public var shadow = false
    public init() {}

    /// Word's defaults for a distance measured from `offsetFrom`.
    public static func defaultSpace(from: String) -> [Side: Int] {
        from == "text" ? [.top: 1, .bottom: 1, .left: 4, .right: 4] : [.top: 24, .left: 24, .bottom: 24, .right: 24]
    }

    public var xml: String {
        var el = "<w:pgBorders"
        if offsetFrom == "page" { el += " w:offsetFrom=\"page\"" }
        if let display { el += " w:display=\"\(display)\"" }
        el += ">"
        for s in Side.allCases where sides.contains(s) {
            el += "<w:\(s.rawValue) w:val=\"\(style)\" w:sz=\"\(width)\" w:space=\"\(space[s] ?? 24)\" w:color=\"\(color.map(RichDocumentController._hex6) ?? "auto")\""
            if shadow, s == .bottom || s == .right { el += " w:shadow=\"1\"" }
            el += "/>"
        }
        return el + "</w:pgBorders>"
    }

    /// Read back from a `w:pgBorders` element (the first side present gives the line).
    public init?(xml: String) {
        guard xml.containsSubstring("<w:pgBorders") else { return nil }
        func attr(_ tag: Substring, _ key: String) -> String? {
            guard let r = tag.rangeOfSubstring(" \(key)=\""), let q = tag[r.upperBound...].firstIndex(of: "\"") else { return nil }
            return String(tag[r.upperBound ..< q])
        }
        guard let open = xml.rangeOfSubstring("<w:pgBorders"), let gt = xml[open.upperBound...].firstIndex(of: ">") else { return nil }
        let head = xml[open.lowerBound ... gt]
        offsetFrom = attr(head, "w:offsetFrom") ?? "text"
        display = attr(head, "w:display")
        space = [:]
        sides = []
        var first = true
        for s in Side.allCases {
            guard let r = xml.rangeOfSubstring("<w:\(s.rawValue) "), let end = xml[r.upperBound...].firstIndex(of: ">") else { continue }
            let tag = xml[r.lowerBound ... end]
            let val = attr(tag, "w:val") ?? "single"
            guard val != "none", val != "nil" else { continue }
            sides.insert(s)
            space[s] = Int(attr(tag, "w:space") ?? "") ?? 0
            if first {
                first = false
                style = val
                width = Int(attr(tag, "w:sz") ?? "") ?? 4
                color = attr(tag, "w:color").flatMap { $0 == "auto" ? nil : UInt32($0, radix: 16) }
                shadow = attr(tag, "w:shadow").map { $0 == "1" || $0 == "true" || $0 == "on" } ?? false
            }
        }
    }

    /// The `w:pgBorders` element inside a section's XML.
    /// Stands for "no borders" in a section that is otherwise written as a copy of the last one; never written to a file.
    public static let none = "<w:pgBorders x-none=\"1\"/>"

    /// The `w:pgBorders` a section mark's `sectionXML` gives its section, or nil for none: its own element, else, for a
    /// section made by a break in the last one, the last section's.
    public static func ofSection(_ sect: String?, _ document: RichDocument) -> String? {
        guard let sect else { return nil }
        if let own = element(in: sect) { return own == none ? nil : own }
        return sect.containsSubstring(RichDocumentController.sectionAsLast) ? document.pageBordersXML : nil
    }

    public static func element(in sect: String) -> String? {
        guard let r = sect.rangeOfSubstring("<w:pgBorders"), let gt = sect[r.upperBound...].firstIndex(of: ">") else { return nil }
        if sect[sect.index(before: gt)] == "/" { return String(sect[r.lowerBound ... gt]) }
        guard let e = sect.rangeOfSubstring("</w:pgBorders>") else { return nil }
        return String(sect[r.lowerBound ..< e.upperBound])
    }

    /// A section's XML with its page borders replaced by `xml` (nil: removed), put after the margins and paper source.
    public static func replacing(in sect: String, with xml: String?) -> String {
        var s = sect
        if let old = element(in: s), let r = s.rangeOfSubstring(old) {
            s.replaceSubrange(r, with: xml ?? "")
            return s
        }
        guard let xml else { return s }
        for name in ["w:paperSrc", "w:pgMar", "w:pgSz"] {
            if let r = s.rangeOfSubstring("<\(name)"), let gt = s[r.upperBound...].firstIndex(of: ">") {
                var end = s.index(after: gt)
                if s[s.index(before: gt)] != "/", let close = s[gt...].rangeOfSubstring("</\(name)>") { end = close.upperBound }
                s.insert(contentsOf: xml, at: end)
                return s
            }
        }
        if let r = s.rangeOfSubstring("<w:sectPr"), let gt = s[r.upperBound...].firstIndex(of: ">"), s[s.index(before: gt)] != "/" {
            s.insert(contentsOf: xml, at: s.index(after: gt))
        }
        return s
    }
}
