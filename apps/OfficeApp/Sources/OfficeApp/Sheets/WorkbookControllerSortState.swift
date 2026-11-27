// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-DA-1: a sort is saved as Excel saves it, a <sortState> naming the sorted data and one
// <sortCondition> per level, so Excel's Sort dialog and Data → Reapply see the last sort.
// Inside the AutoFilter when the sort is the filter's data, else on the sheet.

import Foundation

extension WorkbookController {
    /// The `<sortState>` for a sort of `data` (header excluded) by `keys`, or nil when a level has
    /// no colour to name ("No Fill" / "Automatic"): Excel names a colour level by a look (dxf).
    func _sortStateXML(_ data: CellRange, keys: [SortKey], byColumns: Bool, caseSensitive: Bool) -> String? {
        var conds = ""
        for k in keys {
            let line = byColumns ? CellRange(top: k.col, left: data.left, bottom: k.col, right: data.right)
                                 : CellRange(top: data.top, left: k.col, bottom: data.bottom, right: k.col)
            var c = "<sortCondition"
            switch k.on {
            case .values:
                if !k.ascending { c += " descending=\"1\"" }
                c += " ref=\"\(line.a1)\""
                if let list = k.custom { c += " customList=\"\(Xlsx._esc(list.joined(separator: ",")))\"" }
            case .cellColor, .fontColor:
                guard let rgb = k.color else { return nil }
                var d = DxfStyle()
                if k.on == .cellColor { d.fill = rgb | 0xFF000000 } else { d.color = rgb | 0xFF000000 }
                if !k.colorOnTop { c += " descending=\"1\"" }
                c += " sortBy=\"\(k.on == .cellColor ? "cellColor" : "fontColor")\" ref=\"\(line.a1)\" dxfId=\"\(_appendDxf(d))\""
            }
            conds += c + "/>"
        }
        return "<sortState" + (byColumns ? " columnSort=\"1\"" : "") + (caseSensitive ? " caseSensitive=\"1\"" : "")
            + " ref=\"\(data.a1)\">" + conds + "</sortState>"
    }

    /// Record the last sort (inside a caller's undo step). A sort of the AutoFilter's data goes in the
    /// filter; any other goes on the sheet. A sort that cannot be named drops the old record rather
    /// than leave one describing a different order.
    func _noteSortState(_ data: CellRange, keys: [SortKey], byColumns: Bool, caseSensitive: Bool) {
        let xml = _sortStateXML(data, keys: keys, byColumns: byColumns, caseSensitive: caseSensitive)
        sheet.keptElements.removeAll { $0.name == "sortState" }
        if var af = sheet.autoFilter, !byColumns, data.top == af.range.top + 1,
           data.left >= af.range.left, data.right <= af.range.right {
            if let raw = af.raw { af.raw = AutoFilter.withSortState(raw, xml) } else { af.sortState = xml }
            sheet.autoFilter = af
        } else if let xml {
            sheet.keptElements.append(("sortState", xml))
        }
    }
}

extension AutoFilter {
    /// The `<sortState>` element in a written `<autoFilter>`, if any.
    static func sortStateRange(_ raw: String) -> Range<String.Index>? {
        guard let a = raw.rangeOfSubstring("<sortState") else { return nil }
        if let e = raw.rangeOfSubstring("</sortState>", in: a.upperBound ..< raw.endIndex) { return a.lowerBound ..< e.upperBound }
        guard let gt = raw.rangeOfSubstring(">", in: a.upperBound ..< raw.endIndex) else { return nil }
        return a.lowerBound ..< gt.upperBound
    }

    /// `raw` with its sort state replaced by `xml` (nil removes it), added last when it had none.
    static func withSortState(_ raw: String, _ xml: String?) -> String {
        if let r = sortStateRange(raw) { return raw.replacingSubrange(r, with: xml ?? "") }
        guard let xml else { return raw }
        if let end = raw.rangeOfSubstring("</autoFilter>") { return raw.replacingSubrange(end.lowerBound ..< end.lowerBound, with: xml) }
        guard raw.hasSuffix("/>") else { return raw }
        return String(raw.dropLast(2)) + ">" + xml + "</autoFilter>"
    }
}
