// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Hyperlinks: the sheet's kept `<hyperlinks>` (URLs through its
// relationships, places in the workbook through `location`) and
// HYPERLINK() formulas. ⌘-click follows one — a URL opens in the browser,
// a place selects it — as a plain click stays the selection.

import Foundation

enum SheetLink: Equatable {
    case url(String)
    /// `Sheet2!A1`, `'My Sheet'!B3:C4` or a defined name.
    case place(String)
}

extension WorkbookController {
    /// The link on a cell, if any.
    func link(at a: CellAddress) -> SheetLink? {
        let ws = sheet
        if let f = ws.cells[a]?.formula, case .call(let name, let args) = f, name.uppercased() == "HYPERLINK", let first = args.first {
            let target = engine.scalar(engine.evaluate(first, EvalContext(engine: engine, sheet: activeSheet, cell: a)),
                                       EvalContext(engine: engine, sheet: activeSheet, cell: a))
            let text = NumberFormat.display(target, "General", width: 255).text
            guard !text.isEmpty else { return nil }
            return text.hasPrefix("#") ? .place(String(text.dropFirst())) : .url(text)
        }
        for (name, text) in ws.keptElements where name == "hyperlinks" {
            guard let root = XNode.parse(Data(text.utf8)) else { continue }
            for h in root.kids("hyperlink") {
                guard let ref = h["ref"], let r = CellRange(ref), r.contains(a) else { continue }
                if let id = h["r:id"], let url = ws.linkTargets[id] {
                    let loc = h["location"].map { "#" + $0 } ?? ""
                    return .url(url + loc)
                }
                if let loc = h["location"], !loc.isEmpty { return .place(loc) }
            }
        }
        return nil
    }

    /// Select a place a link names. False when it names nothing here.
    @discardableResult
    func go(to place: String) -> Bool {
        if let e = try? Formula.parse("=" + place), case .ref(let r) = e {
            let si = r.sheet.flatMap { book.sheet(named: $0) } ?? activeSheet
            if si != activeSheet { activeSheet = si }
            select(range: r.range, active: r.range.topLeft)
            return true
        }
        if let target = book.names[place.uppercased()], let e = try? Formula.parse("=" + target), case .ref(let r) = e {
            if let s = r.sheet.flatMap({ book.sheet(named: $0) }), s != activeSheet { activeSheet = s }
            select(range: r.range, active: r.range.topLeft)
            return true
        }
        return false
    }
}
