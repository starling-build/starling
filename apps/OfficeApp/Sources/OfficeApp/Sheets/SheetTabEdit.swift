// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-SH-1: sheet tabs. Move a sheet, copy a sheet, give a tab a colour: each one undoable change.
import Foundation

extension WorkbookController {
    /// Move sheet `i` so it ends at position `to` (0-based, in the sheet list after the move).
    /// Sheet-local names (print areas and titles) follow their sheets. Returns false if nothing moved.
    @discardableResult
    func moveSheet(_ i: Int, to: Int) -> Bool {
        guard !_structureLockedForTabs(), book.sheets.indices.contains(i), book.sheets.indices.contains(to), i != to else { return false }
        structural {
            let keep = activeSheet
            let sheetObj = book.sheets[i]
            var order = Array(book.sheets.indices)
            order.remove(at: i)
            order.insert(i, at: to)           // order[newPos] = oldIndex
            var newOf = [Int](repeating: 0, count: order.count)
            for (np, old) in order.enumerated() { newOf[old] = np }
            book.sheets.remove(at: i)
            book.sheets.insert(sheetObj, at: to)
            for k in book.fileNames.indices { if let l = book.fileNames[k].localSheet, l < newOf.count { book.fileNames[k].localSheet = newOf[l] } }
            // The sheet that was open stays open, wherever it went.
            activeSheet = newOf[keep]
        }
        return true
    }

    /// Why a sheet cannot be copied yet, or nil. Tables, pivot tables, pictures, charts and notes hold parts
    /// of the file that a second sheet cannot share, so they are refused in plain words rather than dropped.
    func copyBlocker(_ i: Int) -> String? {
        let ws = book.sheets[i]
        if !ws.tables.isEmpty { return "tables" }
        if !ws.pivots.isEmpty { return "pivot tables" }
        if !ws.drawings.isEmpty || !ws.objects.isEmpty || ws.drawingPart != nil { return "pictures, charts or shapes" }
        if !ws.notes.isEmpty { return "notes" }
        return nil
    }

    /// A copy of sheet `i`, placed so it ends at position `at` (nil: right after the original). Named
    /// "Name (2)" and so on. References in it that name the original sheet name the copy.
    @discardableResult
    func copySheet(_ i: Int, at: Int? = nil) -> Bool {
        guard !_structureLockedForTabs(), book.sheets.indices.contains(i) else { return false }
        if let what = copyBlocker(i) {
            onCommand?(.status("This sheet has \(what), which cannot be copied yet."))
            return false
        }
        structural {
            let src = book.sheets[i]
            let dup = src.copy()
            dup.name = Self._copyName(src.name, in: book)
            dup.origin = nil
            dup.hidden = false
            dup.veryHidden = false
            let pos = max(0, min(at ?? i + 1, book.sheets.count))
            book.sheets.insert(dup, at: pos)
            for k in book.fileNames.indices { if let l = book.fileNames[k].localSheet, l >= pos { book.fileNames[k].localSheet = l + 1 } }
            // Its own sheet-local names (print area, titles) are copied for it.
            let own = book.fileNames.filter { $0.localSheet == (i >= pos ? i + 1 : i) }
            for var n in own {
                n.localSheet = pos
                let q = { (x: String) in "'" + x.replacingAll("'", with: "''") + "'!" }
                n.text = n.text.replacingAll(q(src.name), with: "\u{1}").replacingAll(src.name + "!", with: "\u{1}")
                    .replacingAll("\u{1}", with: q(dup.name))
                book.fileNames.append(n)
            }
            // Formulas in the copy that name the original by sheet name now point at the copy.
            let mine = src.name.lowercased()
            for (a, c) in dup.cells {
                guard let expr = c.formula else { continue }
                let g = Formula.mapRefs(expr) { ref in
                    guard ref.sheet?.lowercased() == mine else { return ref }
                    var r = ref; r.sheet = dup.name; return r
                }
                if g != expr { dup.cells[a]?.formula = g; dup.cells[a]?.input = Formula.text(g) }
            }
            _selections.removeAll()
            activeSheet = pos
        }
        return true
    }

    /// "Sheet1 (2)", "Sheet1 (3)"…: the first name not taken (31 characters at most).
    static func _copyName(_ base: String, in book: Workbook) -> String {
        var n = 2
        while true {
            let suffix = " (\(n))"
            let cand = String(base.prefix(31 - suffix.count)) + suffix
            if book.sheet(named: cand) == nil { return cand }
            n += 1
        }
    }

    /// Give sheet `i`'s tab a colour (ARGB hex like "FFC00000") or none.
    func setTabColor(_ i: Int, _ argb: String?) {
        guard book.sheets.indices.contains(i), book.sheets[i].tabColor != argb else { return }
        structural {
            let ws = book.sheets[i]
            ws.tabColor = argb
            let k = ws.keptElements.firstIndex { $0.name == "sheetPr" }
            let text = k.map { ws.keptElements[$0].text } ?? "<sheetPr/>"
            let updated = Self._withTabColor(text, argb)
            if let k { ws.keptElements[k].text = updated }
            else if argb != nil { ws.keptElements.append(("sheetPr", updated)) }
        }
    }

    /// `<tabColor>` is the first child of sheetPr.
    static func _withTabColor(_ sheetPr: String, _ argb: String?) -> String {
        var s = sheetPr
        if let r = s.rangeOfSubstring("<tabColor"), let e = s.rangeOfSubstring("/>", in: r.upperBound..<s.endIndex) {
            s.removeSubrange(r.lowerBound..<e.upperBound)
        }
        guard let argb else { return s }
        let tag = "<tabColor rgb=\"\(argb)\"/>"
        if s.hasSuffix("/>") {
            // "<sheetPr a=b/>" → "<sheetPr a=b><tabColor/></sheetPr>"
            return String(s.dropLast(2)) + ">" + tag + "</sheetPr>"
        }
        if let gt = s.firstIndex(of: ">") { s.insert(contentsOf: tag, at: s.index(after: gt)) }
        return s
    }

    private func _structureLockedForTabs() -> Bool {
        guard book.structureLocked else { return false }
        onCommand?(.status("The workbook's structure is protected: sheets cannot be moved or copied."))
        return true
    }
}
