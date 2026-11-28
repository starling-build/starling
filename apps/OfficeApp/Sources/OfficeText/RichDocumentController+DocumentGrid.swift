// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// W-PG-3: Page Setup's Document Grid tab, as a section's `w:docGrid` and `w:textDirection` say it.
public struct DocumentGrid: Equatable, Sendable {
    /// No grid (Word writes no type), lines only, lines and characters, or text snapped to the character grid.
    public enum Kind: String, CaseIterable, Sendable { case none = "default", lines, linesAndChars, snapToChars }
    public var kind: Kind
    /// The line pitch in twips (`w:linePitch`; Word's default template writes 360, 18 pt).
    public var linePitch: Int
    /// What the grid adds to each Normal-size character, in 4096ths of a point (`w:charSpace`).
    public var charSpace: Int
    /// Text top to bottom, right to left (`w:textDirection` tbRl).
    public var vertical: Bool
    public init(kind: Kind = .none, linePitch: Int = 360, charSpace: Int = 0, vertical: Bool = false) {
        self.kind = kind; self.linePitch = linePitch; self.charSpace = charSpace; self.vertical = vertical
    }
    /// The grid read back from a section's markup (its `w:docGrid` element and the `w:textDirection` near it).
    public init(gridXML: String?, directionXML: String?) {
        let grid = gridXML.flatMap { DocumentGrid._element("w:docGrid", in: $0) }
        kind = grid.flatMap { DocumentGrid._attr("w:type", in: $0) }.flatMap(Kind.init(rawValue:)) ?? .none
        linePitch = grid.flatMap { DocumentGrid._attr("w:linePitch", in: $0) }.flatMap { Int($0) } ?? 360
        charSpace = grid.flatMap { DocumentGrid._attr("w:charSpace", in: $0) }.flatMap { Int($0) } ?? 0
        let direction = directionXML.flatMap { DocumentGrid._element("w:textDirection", in: $0) }.flatMap { DocumentGrid._attr("w:val", in: $0) }
        vertical = direction == "tbRl" || direction == "tbRlV"
    }
    /// The `w:docGrid` element Word writes for it (a grid of no type keeps its line pitch, as Word's does).
    public var xml: String {
        var s = "<w:docGrid"
        if kind != .none { s += " w:type=\"\(kind.rawValue)\"" }
        s += " w:linePitch=\"\(linePitch)\""
        if charSpace != 0 && kind != .none && kind != .lines { s += " w:charSpace=\"\(charSpace)\"" }
        return s + "/>"
    }
    /// The layout's values for a section with this grid, as the reader derives them from the file: the line pitch in
    /// points, what each character gains, and (a horizontal snapToChars grid in one column) the Normal size the cell is
    /// counted at, the cell a whole fraction of the line.
    public func layoutValues(page: PageSetup, normalSize: Double) -> (pitch: Double?, space: Double?, cellBase: Double?) {
        let pitch: Double? = kind != .none && linePitch > 0 ? Double(linePitch) / 20 : nil
        var space: Double? = nil, base: Double? = nil
        if kind == .linesAndChars || (kind == .snapToChars && vertical) {
            space = charSpace != 0 ? Double(charSpace) / 4096 : 1e-6
        }
        let paper = page.physical
        if kind == .snapToChars, !vertical, paper.columns <= 1, normalSize > 0 {
            let width = paper.contentWidth
            let n = (width / (normalSize + Double(charSpace) / 4096)).rounded(.down)
            if n >= 1, width > 0 { space = width / n - normalSize; base = normalSize }
        }
        return (pitch, space, base)
    }

    static func _element(_ name: String, in xml: String) -> Substring? {
        guard let r = xml.rangeOfSubstring("<\(name)") else { return nil }
        let rest = xml[r.lowerBound...]
        guard let end = rest.rangeOfSubstring(">") else { return nil }
        return rest[..<end.upperBound]
    }
    static func _attr(_ name: String, in element: Substring) -> String? {
        guard let r = String(element).rangeOfSubstring(" \(name)=\"") else { return nil }
        let s = String(element)
        let rest = s[r.upperBound...]
        guard let q = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<q])
    }
    /// A sectPr's own markup up to its tracked change (`w:sectPrChange` holds an older sectPr of its own).
    static func _ownEnd(_ xml: String) -> String.Index {
        xml.rangeOfSubstring("<w:sectPrChange")?.lowerBound ?? xml.rangeOfSubstring("</w:sectPr>")?.lowerBound ?? xml.endIndex
    }
    /// The range of a self-closing (or empty) element of the sectPr's own, if it has one.
    static func _ownRange(_ name: String, in xml: String) -> Range<String.Index>? {
        let own = xml[..<_ownEnd(xml)]
        guard let r = String(own).rangeOfSubstring("<\(name)") else { return nil }
        let start = xml.index(xml.startIndex, offsetBy: own.distance(from: own.startIndex, to: r.lowerBound))
        let rest = xml[start...]
        guard let close = rest.rangeOfSubstring(">") else { return nil }
        if rest[..<close.upperBound].hasSuffix("/>") { return start..<close.upperBound }
        guard let end = rest.rangeOfSubstring("</\(name)>") else { return nil }
        return start..<end.upperBound
    }
    /// The sectPr with `element` in place of its own `name`, or (none there) put before the first of `before`;
    /// nil takes it out.
    static func _replacing(_ name: String, with element: String?, before: [String], in xml: String) -> String {
        var out = xml
        if let r = _ownRange(name, in: out) {
            if let element { out.replaceSubrange(r, with: element) } else { out.removeSubrange(r) }
            return out
        }
        guard let element else { return out }
        let own = String(out[..<_ownEnd(out)])
        let at = before.compactMap { own.rangeOfSubstring("<\($0)")?.lowerBound }.min() ?? _ownEnd(out)
        out.insert(contentsOf: element, at: at)
        return out
    }
    /// The textDirection a section keeps when it is vertical (a tbRlV stays so) or loses when it is not.
    static func _direction(_ vertical: Bool, have: String?) -> String? {
        guard vertical else { return nil }
        let val = have.flatMap { _element("w:textDirection", in: $0) }.flatMap { _attr("w:val", in: $0) }
        return "<w:textDirection w:val=\"\(val == "tbRlV" ? "tbRlV" : "tbRl")\"/>"
    }
}

/// The last section's grid as the document holds it (its sectPr is written from these, not kept whole).
public struct LastSectionGrid: Equatable, Sendable {
    public var docGridXML: String?
    public var sectionTailXML: String?
    public var lineGridPitch: Double?
    public var characterGridSpace: Double?
    public var characterGridCellBase: Double?
}

extension RichDocumentController {
    /// The grid of the section `mark` (-1: the last) as Page Setup shows it.
    public func documentGrid(sectionMark mark: Int) -> DocumentGrid {
        if mark < 0 || mark >= document.paragraphs.count { return DocumentGrid(gridXML: document.docGridXML, directionXML: document.sectionTailXML) }
        let own = document.paragraphs[mark].style.sectionXML.map { String($0[..<DocumentGrid._ownEnd($0)]) }
        return DocumentGrid(gridXML: own, directionXML: own)
    }
    /// The grid of the section the caret is in.
    public var documentGrid: DocumentGrid { documentGrid(sectionMark: sectionMark(containing: selection.focus.paragraph)) }

    /// W-PG-3: Page Setup's Document Grid on the caret's section or all of them, one undo step: the grid and the text
    /// direction as the file writes them, and the page turned for a vertical section.
    public func setDocumentGrid(_ grid: DocumentGrid, allSections: Bool, lastSetup: PageSetup) {
        var marks: [Int] = []
        if allSections {
            for i in 0..<document.paragraphs.count where document.paragraphs[i].cell == nil && document.paragraphs[i].style.sectionPage != nil { marks.append(i) }
            marks.append(-1)
        } else {
            marks = [sectionMark(containing: selection.focus.paragraph)]
        }
        guard marks.contains(where: { documentGrid(sectionMark: $0) != grid }) else { return }
        let normal = document.styles[RichNamedStyle.normalId]?.char.fontSize ?? 11
        edit {
            changePageSetup(allSections: allSections, lastSetup: lastSetup) { $0.vertical = grid.vertical }
            for mark in marks where documentGrid(sectionMark: mark) != grid {
                if mark < 0 {
                    let page = document.lastSectionPage ?? lastSetup
                    let old = LastSectionGrid(docGridXML: document.docGridXML, sectionTailXML: document.sectionTailXML, lineGridPitch: document.lineGridPitch,
                                              characterGridSpace: document.characterGridSpace, characterGridCellBase: document.characterGridCellBase)
                    let tail = DocumentGrid._replacing("w:textDirection", with: DocumentGrid._direction(grid.vertical, have: document.sectionTailXML),
                                                       before: ["w:bidi", "w:rtlGutter"], in: document.sectionTailXML ?? "")
                    let values = grid.layoutValues(page: page, normalSize: normal)
                    let new = LastSectionGrid(docGridXML: grid.xml, sectionTailXML: tail.isEmpty ? nil : tail, lineGridPitch: values.pitch,
                                              characterGridSpace: values.space, characterGridCellBase: values.cellBase)
                    perform(.setLastSectionGrid(old: old, new: new))
                } else {
                    let old = document.paragraphs[mark].style
                    var style = old
                    var xml = style.sectionXML ?? "<w:sectPr></w:sectPr>"
                    // (A sectPr of nothing written short opens to take the grid.)
                    if !xml.containsSubstring("</w:sectPr>"), xml.hasSuffix("/>") { xml = String(xml.dropLast(2)) + "></w:sectPr>" }
                    xml = DocumentGrid._replacing("w:textDirection", with: DocumentGrid._direction(grid.vertical, have: String(xml[..<DocumentGrid._ownEnd(xml)])),
                                                  before: ["w:bidi", "w:rtlGutter", "w:docGrid", "w:printerSettings"], in: xml)
                    xml = DocumentGrid._replacing("w:docGrid", with: grid.xml, before: ["w:printerSettings"], in: xml)
                    style.sectionXML = xml
                    if var page = style.sectionPage {
                        let values = grid.layoutValues(page: page, normalSize: normal)
                        page.lineGridPitch = values.pitch; page.characterGridSpace = values.space; page.characterGridCellBase = values.cellBase
                        style.sectionPage = page
                    }
                    perform(.setParagraphStyle(mark, old: old, new: style))
                }
            }
        }
    }
}
