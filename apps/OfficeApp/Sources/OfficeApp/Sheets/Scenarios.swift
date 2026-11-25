// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-DA-6c: Data → What-If Analysis → Scenario Manager. A scenario is a name, a comment and a set of
// changing cells with the values they take. They live in the sheet's `<scenarios>` element (kept
// verbatim by the file layer), so Excel reads them. Add, Show, Delete and a Summary report sheet;
// every change is one undo step. Attributes this code does not use are kept as they were.

import Foundation

struct ScenarioCell: Equatable {
    var ref: String
    var value: String
    var attrs: [String: String] = [:]      // deleted, undone, numFmtId…
}

struct Scenario: Equatable {
    var name: String
    var comment: String
    var locked = false
    var hidden = false
    var user = "Starling"
    var cells: [ScenarioCell]
    var attrs: [String: String] = [:]      // anything else the file had
}

enum ScenarioProblem: Equatable {
    case noName, duplicate(String), noCells, tooManyCells, hasFormula(String), badCell(String), notFound, locked
    var message: String {
        switch self {
        case .noName: return "Give the scenario a name."
        case .duplicate(let n): return "A scenario named \"\(n)\" already exists."
        case .noCells: return "Pick at least one changing cell."
        case .tooManyCells: return "A scenario can change at most 32 cells."
        case .hasFormula(let a): return "\(a) holds a formula. Changing cells must hold values."
        case .badCell(let t): return "\"\(t)\" is not a cell. Use cells like B3 or B3:B5, separated by commas."
        case .notFound: return "That scenario no longer exists."
        case .locked: return "This scenario is locked and the sheet is protected."
        }
    }
}

enum Scenarios {
    private static let scenarioOrder = ["name", "locked", "hidden", "count", "user", "comment"]
    private static let cellOrder = ["r", "deleted", "undone", "val", "numFmtId"]

    static func parse(_ ws: Worksheet) -> [Scenario] {
        guard let text = ws.keptElements.first(where: { $0.name == "scenarios" })?.text,
              let root = XNode.parse(Data(text.utf8)) else { return [] }
        return root.kids("scenario").map { s in
            var extra = s.attrs
            for k in ["name", "locked", "hidden", "count", "user", "comment"] { extra[k] = nil }
            let cells = s.kids("inputCells").map { c -> ScenarioCell in
                var a = c.attrs; a["r"] = nil; a["val"] = nil
                return ScenarioCell(ref: c["r"] ?? "", value: c["val"] ?? "", attrs: a)
            }
            return Scenario(name: s["name"] ?? "", comment: s["comment"] ?? "", locked: s["locked"] == "1",
                            hidden: s["hidden"] == "1", user: s["user"] ?? "", cells: cells, attrs: extra)
        }
    }

    /// The element for `list`, `rootAttrs` being what the old root carried (current, show).
    static func xml(_ list: [Scenario], rootAttrs: [String: String]) -> String? {
        guard !list.isEmpty else { return nil }
        let refs = list.flatMap { $0.cells.map(\.ref) }
        var seen = Set<String>(), sq: [String] = []
        for r in refs where seen.insert(r).inserted { sq.append(r) }
        var a = rootAttrs
        a["sqref"] = sq.joined(separator: " ")
        if let cur = a["current"], Int(cur).map({ $0 >= list.count }) != false { a["current"] = nil }
        var x = "<scenarios"
        for k in ["current", "show", "sqref"] { if let v = a[k] { x += " \(k)=\"\(Xlsx._esc(v))\"" } }
        x += ">"
        for s in list {
            var at: [String: String] = s.attrs
            at["name"] = s.name; at["count"] = "\(s.cells.count)"
            if s.locked { at["locked"] = "1" }
            if s.hidden { at["hidden"] = "1" }
            if !s.user.isEmpty { at["user"] = s.user }
            if !s.comment.isEmpty { at["comment"] = s.comment }
            x += "<scenario" + attrText(at, scenarioOrder) + ">"
            for c in s.cells {
                var ca = c.attrs; ca["r"] = c.ref; ca["val"] = c.value
                x += "<inputCells" + attrText(ca, cellOrder) + "/>"
            }
            x += "</scenario>"
        }
        return x + "</scenarios>"
    }

    private static func attrText(_ a: [String: String], _ order: [String]) -> String {
        var s = ""
        for k in order { if let v = a[k] { s += " \(k)=\"\(Xlsx._esc(v))\"" } }
        for k in a.keys.sorted() where !order.contains(k) { s += " \(k)=\"\(Xlsx._esc(a[k]!))\"" }
        return s
    }

    /// "B3, B5:B6" → the cells in order, nil entry text when one is not a cell.
    static func cells(_ text: String) -> (cells: [CellAddress], bad: String?) {
        var out: [CellAddress] = []
        for part in text.replacingAll(";", with: ",").split(separator: ",") {
            let t = String(part).trimmingWhitespace().replacingAll("$", with: "").uppercased()
            if t.isEmpty { continue }
            guard let r = CellRange(t) else { return ([], t) }
            for row in r.top ... r.bottom { for col in r.left ... r.right where out.count <= 64 { out.append(CellAddress(row: row, col: col)) } }
        }
        return (out, nil)
    }
}

extension WorkbookController {
    func scenarios() -> [Scenario] { Scenarios.parse(sheet) }

    private func _scenarioRootAttrs() -> [String: String] {
        guard let t = sheet.keptElements.first(where: { $0.name == "scenarios" })?.text, let root = XNode.parse(Data(t.utf8)) else { return [:] }
        return root.attrs
    }

    private func _setScenarios(_ list: [Scenario]) {
        let root = _scenarioRootAttrs()
        let i = sheet.keptElements.firstIndex(where: { $0.name == "scenarios" })
        if let x = Scenarios.xml(list, rootAttrs: root) {
            if let i { sheet.keptElements[i].text = x } else { sheet.keptElements.append(("scenarios", x)) }
        } else if let i { sheet.keptElements.remove(at: i) }
    }

    /// What `a` holds, as a scenario stores it: the number, the text, TRUE/FALSE, or nothing.
    func scenarioValue(_ a: CellAddress) -> String {
        switch sheet.value(a) {
        case .number(let n): return n == n.rounded() && abs(n) < 1e15 ? String(Int(n)) : String(n)
        case .text(let t): return t
        case .bool(let b): return b ? "TRUE" : "FALSE"
        default: return ""
        }
    }

    /// Add (or, with `replacing`, replace) a scenario. `values` pairs each changing cell with the value it takes.
    func addScenario(name: String, comment: String, values: [(CellAddress, String)], replacing old: String? = nil) -> ScenarioProblem? {
        let n = name.trimmingWhitespace()
        guard !n.isEmpty else { return .noName }
        guard !values.isEmpty else { return .noCells }
        guard values.count <= 32 else { return .tooManyCells }
        for (a, _) in values where sheet.cells[a]?.formula != nil { return .hasFormula(a.a1) }
        var list = scenarios()
        if list.contains(where: { $0.name.lowercased() == n.lowercased() && $0.name != old }) { return .duplicate(n) }
        let at = old.flatMap { o in list.firstIndex(where: { $0.name == o }) }
        if let at, list[at].locked, protection() != nil { return .locked }
        var s = Scenario(name: n, comment: comment, cells: values.map { ScenarioCell(ref: $0.0.a1, value: $0.1) })
        if let at { s.locked = list[at].locked; s.hidden = list[at].hidden; s.user = list[at].user; s.attrs = list[at].attrs }
        structural {
            if let at { list[at] = s } else { list.append(s) }
            _setScenarios(list)
        }
        return nil
    }

    func deleteScenario(_ name: String) -> ScenarioProblem? {
        var list = scenarios()
        guard let i = list.firstIndex(where: { $0.name == name }) else { return .notFound }
        if list[i].locked, protection() != nil { return .locked }
        structural { list.remove(at: i); _setScenarios(list) }
        return nil
    }

    /// Put the scenario's values into its cells: one undo step.
    func showScenario(_ name: String) -> ScenarioProblem? {
        guard let s = scenarios().first(where: { $0.name == name }) else { return .notFound }
        var items: [(CellAddress, String)] = []
        for c in s.cells where c.attrs["deleted"] != "1" {
            guard let a = CellAddress(c.ref) else { continue }
            if sheet.cells[a]?.formula != nil { return .hasFormula(a.a1) }
            items.append((a, c.value))
        }
        guard !items.isEmpty else { return .noCells }
        setInputs(items)
        return nil
    }

    /// A new sheet laying the scenarios side by side, with the result cells' values under each.
    /// Returns the sheet's name, or a problem.
    func scenarioSummary(results: [CellAddress]) -> (sheet: String?, problem: ScenarioProblem?) {
        let list = scenarios()
        guard !list.isEmpty else { return (nil, .notFound) }
        let src = sheet
        var changing: [CellAddress] = [], seen = Set<CellAddress>()
        for s in list { for c in s.cells { if let a = CellAddress(c.ref), seen.insert(a).inserted { changing.append(a) } } }
        func val(_ a: CellAddress) -> String { scenarioValue(a) }
        let currentCols: [String] = changing.map(val) + results.map(val)
        // Each scenario's column: apply it, read, put the sheet back.
        let saved = changing.map { ($0, src.cells[$0]) }
        var cols: [[String]] = []
        for s in list {
            for c in s.cells { if let a = CellAddress(c.ref), c.attrs["deleted"] != "1" {
                var cell = src.cells[a] ?? Cell(input: ""); cell.input = c.value; cell.formula = nil
                if let n = Double(c.value) { cell.value = .number(n) } else { cell.value = c.value.isEmpty ? .empty : .text(c.value) }
                src.cells[a] = cell
            } }
            engine.recalculate()
            cols.append(changing.map { a in s.cells.contains { $0.ref == a.a1 } ? val(a) : "" } + results.map(val))
        }
        for (a, c) in saved { src.cells[a] = c }
        engine.recalculate()
        var name = "Scenario Summary", k = 1
        while book.sheet(named: name) != nil { k += 1; name = "Scenario Summary \(k)" }
        if book.structureLocked { onCommand?(.status("The workbook's structure is protected: sheets cannot be added.")); return (nil, nil) }
        structural {
            let fresh = Worksheet(name: name)
            fresh.digitWidth = book.digitWidth
            fresh.defaultColWidthPt = ((8 * fresh.digitWidth + 5) / 8).rounded(.up) * 8 * 0.75
            func put(_ r: Int, _ c: Int, _ t: String, bold: Bool = false) {
                guard !t.isEmpty else { return }
                var cell = Cell(input: t)
                if let n = Double(t) { cell.value = .number(n) } else { cell.value = .text(t) }
                if bold { var st = book.style(0); st.bold = true; cell.style = book.styleIndex(st) }
                fresh.cells[CellAddress(row: r, col: c)] = cell
            }
            put(1, 1, "Scenario Summary", bold: true)
            put(3, 2, "Current Values:", bold: true)
            for (i, s) in list.enumerated() { put(3, 3 + i, s.name, bold: true) }
            put(4, 1, "Changing Cells:", bold: true)
            for (k, a) in changing.enumerated() {
                put(5 + k, 1, a.a1)
                put(5 + k, 2, currentCols[k])
                for i in list.indices { put(5 + k, 3 + i, cols[i][k]) }
            }
            if !results.isEmpty {
                let base = 5 + changing.count
                put(base, 1, "Result Cells:", bold: true)
                for (k, a) in results.enumerated() {
                    put(base + 1 + k, 1, a.a1)
                    put(base + 1 + k, 2, currentCols[changing.count + k])
                    for i in list.indices { put(base + 1 + k, 3 + i, cols[i][changing.count + k]) }
                }
            }
            let at = activeSheet + 1
            book.sheets.insert(fresh, at: at)
            for k in book.fileNames.indices { if let l = book.fileNames[k].localSheet, l >= at { book.fileNames[k].localSheet = l + 1 } }
            activeSheet = at
        }
        return (name, nil)
    }
}
