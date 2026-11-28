// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Insert, edit and remove a hyperlink (X-LK-1). The sheet's `<hyperlinks>`
// stays the kept raw element (Hyperlinks.swift reads it); this edits that
// text. A web or mail address goes through a relationship the writer adds
// (Xlsx.swift), a place in the workbook is the `location` attribute.

import Foundation

extension WorkbookController {
    /// Link every cell of `range` to `link`; `tip` is the ScreenTip. One
    /// undo step. A cell left empty shows the address as its text.
    func setLink(_ range: CellRange, _ link: SheetLink, tip: String? = nil) {
        let ws = sheet
        let kept = ws.keptElements.first { $0.name == "hyperlinks" }?.text ?? ""
        var entries = Self._linkEntries(kept).filter { !$0.ref.intersects(range) }
        var attrs = "ref=\"\(Xlsx._esc(range.a1))\""
        switch link {
        case .url(let u):
            // `https://x/page#frag` keeps its fragment as the location, as Excel does.
            var url = u, frag: String? = nil
            if let h = u.rangeOfSubstring("#") { url = String(u[u.startIndex..<h.lowerBound]); frag = String(u[h.upperBound...]) }
            var n = 1
            while ws.linkTargets["rIdLink\(n)"] != nil { n += 1 }
            let id = "rIdLink\(n)"
            ws.linkTargets[id] = url
            attrs += " r:id=\"\(id)\""
            if let frag, !frag.isEmpty { attrs += " location=\"\(Xlsx._esc(frag))\"" }
        case .place(let p):
            attrs += " location=\"\(Xlsx._esc(p))\""
        }
        if let tip, !tip.isEmpty { attrs += " tooltip=\"\(Xlsx._esc(tip))\"" }
        entries.append((range, "<hyperlink \(attrs)/>"))
        let shown: String
        switch link { case .url(let u): shown = u; case .place(let p): shown = p }
        for row in range.top...range.bottom {
            for col in range.left...range.right {
                let a = CellAddress(row: row, col: col)
                if (ws.cells[a]?.value.isEmpty ?? true) && ws.cells[a]?.formula == nil { setInput(shown, at: a) }
            }
        }
        _storeLinks(ws, entries, restyle: (range, { st in st.linkStyle = true; st.underline = true; st.color = 0x0563C1 }))
    }

    /// Clear All: contents, formats, comments and links of `r`, in one undo step.
    func clearAll(_ r: CellRange? = nil) {
        if r == nil, _eachRange({ clearAll(selection) }) { return }
        let r = r ?? selection, ws = sheet
        let kept = ws.keptElements.first { $0.name == "hyperlinks" }?.text ?? ""
        let entries = Self._linkEntries(kept)
        let hasLinks = entries.contains { $0.ref.intersects(r) }
        let hasNotes = ws.notes.contains { $0.at.map { r.contains($0) } ?? false }
        let keys = ws.cells.keys.filter { r.contains($0) }
        guard hasLinks || hasNotes || !keys.isEmpty else { return }
        structural {
            for k in keys { ws.cells[k] = nil }
            Self._dropNotes(ws, in: r)
            if hasLinks {
                ws.keptElements.removeAll { $0.name == "hyperlinks" }
                let left = entries.filter { !$0.ref.intersects(r) }
                if !left.isEmpty { ws.keptElements.append(("hyperlinks", "<hyperlinks>" + left.map(\.xml).joined() + "</hyperlinks>")) }
            }
        }
    }

    /// Take the link off every cell of `range` (the text stays).
    func removeLink(_ range: CellRange) {
        let ws = sheet
        let kept = ws.keptElements.first { $0.name == "hyperlinks" }?.text ?? ""
        let all = Self._linkEntries(kept)
        let left = all.filter { !$0.ref.intersects(range) }
        guard left.count != all.count else { return }
        // A cell still wearing the Hyperlink style gives it up; one the user restyled keeps its look.
        _storeLinks(ws, left, restyle: (range, { st in if st.linkStyle { st.linkStyle = false; st.underline = false; st.color = nil } }))
    }

    private func _storeLinks(_ ws: Worksheet, _ entries: [(ref: CellRange, xml: String)],
                             restyle: (range: CellRange, change: (inout CellStyle) -> Void)) {
        structural {
            for row in restyle.range.top...restyle.range.bottom {
                for col in restyle.range.left...restyle.range.right {
                    let a = CellAddress(row: row, col: col)
                    var cell = ws.cells[a] ?? Cell(input: "")
                    if ws.cells[a] == nil { cell.style = ws.defaultStyle(at: a) }
                    var st = book.style(cell.style)
                    restyle.change(&st)
                    cell.style = book.styleIndex(st)
                    ws.cells[a] = cell
                }
            }
            ws.keptElements.removeAll { $0.name == "hyperlinks" }
            if !entries.isEmpty {
                ws.keptElements.append(("hyperlinks", "<hyperlinks>" + entries.map(\.xml).joined() + "</hyperlinks>"))
            }
        }
    }

    /// The `<hyperlink …/>` elements of a kept `<hyperlinks>`, each with its range.
    static func _linkEntries(_ text: String) -> [(ref: CellRange, xml: String)] {
        var out: [(ref: CellRange, xml: String)] = []
        var at = text.startIndex
        while let s = text.rangeOfSubstring("<hyperlink ", in: at..<text.endIndex) {
            guard let e = text.rangeOfSubstring("/>", in: s.upperBound..<text.endIndex) else { break }
            let xml = String(text[s.lowerBound..<e.upperBound])
            at = e.upperBound
            guard let r = xml.rangeOfSubstring("ref=\""), let q = xml.rangeOfSubstring("\"", in: r.upperBound..<xml.endIndex),
                  let range = CellRange(String(xml[r.upperBound..<q.lowerBound])) else { continue }
            out.append((range, xml))
        }
        return out
    }
}
