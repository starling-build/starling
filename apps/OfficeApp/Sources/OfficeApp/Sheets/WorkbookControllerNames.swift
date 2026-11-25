// X-CE-3: defined names — define, edit, delete — as undoable controller
// commands. The Name Manager dialog and the name box call these; nothing in
// the UI touches `book.names` directly.

import Foundation

/// One name as the Name Manager lists it.
struct NameEntry: Equatable, Sendable {
    var name: String
    /// What it refers to, as written in the file (`Sheet1!$A$1:$B$4`, a constant, a formula).
    var refersTo: String
    /// The sheet it is local to (by position), or nil for the whole workbook.
    var scopeSheet: Int?
    /// Names the file made (print areas, filter ranges) or hid are listed apart and not editable.
    var editable: Bool
}

enum NameProblem: Error, Equatable, Sendable {
    case empty, badStart, badCharacter, looksLikeReference, tooLong, exists, notFound, scopedNotEditable, badFormula

    var message: String {
        switch self {
        case .empty: return "Enter a name."
        case .badStart: return "A name must start with a letter, an underscore or a backslash."
        case .badCharacter: return "A name cannot contain spaces or most punctuation."
        case .looksLikeReference: return "A name cannot look like a cell reference."
        case .tooLong: return "A name can have at most 255 characters."
        case .exists: return "That name already exists."
        case .notFound: return "There is no such name."
        case .scopedNotEditable: return "Names local to one sheet cannot be changed here yet."
        case .badFormula: return "The \"Refers to\" formula is not valid."
        }
    }
}

extension WorkbookController {
    /// Excel's rules for a name: starts with a letter, `_` or `\`; letters, digits, `_`, `.` and `\` after;
    /// not a cell reference (A1, XFD1048576, R1C1, R, C); at most 255 characters.
    static func checkName(_ name: String) -> NameProblem? {
        if name.isEmpty { return .empty }
        if name.count > 255 { return .tooLong }
        guard let first = name.first, first.isLetter || first == "_" || first == "\\" else { return .badStart }
        for ch in name where !(ch.isLetter || ch.isNumber || ch == "_" || ch == "." || ch == "\\") { return .badCharacter }
        let up = name.uppercased()
        if CellAddress(up) != nil { return .looksLikeReference }
        if up == "R" || up == "C" { return .looksLikeReference }
        // R1C1 forms: R, C, R5, C5, R5C5, RC2, R2C.
        let u = Array(up.utf8)
        var i = 0
        func digits() { while i < u.count, u[i] >= 48, u[i] <= 57 { i += 1 } }
        if u.first == 82 {            // R
            i = 1; digits()
            if i == u.count { return .looksLikeReference }
            if u[i] == 67 { i += 1; digits(); if i == u.count { return .looksLikeReference } }
        } else if u.first == 67 {     // C
            i = 1; digits()
            if i == u.count { return .looksLikeReference }
        }
        return nil
    }

    /// The workbook-wide names, then the ones local to a sheet, each with what it refers to.
    func definedNameEntries() -> [NameEntry] {
        var out: [NameEntry] = []
        for n in book.fileNames {
            if n.isBuiltIn { continue }
            let hidden = n.attrs["hidden"] == "1" || n.attrs["hidden"] == "true"
            if n.localSheet == nil {
                guard let text = book.names[n.name.uppercased()] else { continue }
                out.append(NameEntry(name: n.name, refersTo: text, scopeSheet: nil, editable: !hidden))
            } else {
                out.append(NameEntry(name: n.name, refersTo: n.text, scopeSheet: n.localSheet, editable: !hidden))
            }
        }
        // Names made here and not yet in the file's list.
        for (k, v) in book.names.sorted(by: { $0.key < $1.key })
        where !book.fileNames.contains(where: { $0.name.uppercased() == k }) {
            out.append(NameEntry(name: book.nameSpellings[k] ?? k, refersTo: v, scopeSheet: nil, editable: true))
        }
        return out
    }

    /// Define a workbook-wide name. One undo step. Returns the problem, or nil when done.
    @discardableResult
    func defineName(_ name: String, refersTo: String) -> NameProblem? {
        if let p = Self.checkName(name) { return p }
        let key = name.uppercased()
        if book.names[key] != nil { return .exists }
        guard let text = Self.normalisedReference(refersTo) else { return .badFormula }
        structural {
            book.names[key] = text
            book.nameSpellings[key] = name
        }
        return nil
    }

    /// Change a name's spelling and/or what it refers to. Formulas that use the old name are rewritten to the
    /// new spelling, as Excel does. One undo step.
    @discardableResult
    func editName(_ old: String, to name: String, refersTo: String, scope: Int? = nil) -> NameProblem? {
        let oldKey = old.uppercased(), key = name.uppercased()
        if let scope { return _editLocalName(oldKey, to: name, refersTo: refersTo, scope: scope) }
        guard book.names[oldKey] != nil else { return .notFound }
        if let p = Self.checkName(name) { return p }
        if key != oldKey, book.names[key] != nil { return .exists }
        guard let text = Self.normalisedReference(refersTo) else { return .badFormula }
        structural {
            if key != oldKey {
                book.names[oldKey] = nil
                book.nameSpellings[oldKey] = nil
                _renameNameInFormulas(from: oldKey, to: name)
                // The file's entry (comment, hidden…) moves with the name instead of being dropped.
                for i in book.fileNames.indices where book.fileNames[i].localSheet == nil && book.fileNames[i].name.uppercased() == oldKey {
                    book.fileNames[i].name = name
                }
            }
            book.names[key] = text
            book.nameSpellings[key] = name
        }
        return nil
    }

    /// A name local to one sheet: change its spelling and/or what it refers to. Formulas on that sheet are rewritten.
    private func _editLocalName(_ oldKey: String, to name: String, refersTo: String, scope: Int) -> NameProblem? {
        let key = name.uppercased()
        guard let i = book.fileNames.firstIndex(where: { $0.localSheet == scope && $0.name.uppercased() == oldKey }) else { return .notFound }
        if let p = Self.checkName(name) { return p }
        if key != oldKey, book.fileNames.contains(where: { $0.localSheet == scope && $0.name.uppercased() == key }) { return .exists }
        guard let text = Self.normalisedReference(refersTo) else { return .badFormula }
        structural {
            if key != oldKey, scope < book.sheets.count {
                for (a, c) in book.sheets[scope].cells {
                    guard let expr = c.formula else { continue }
                    let g = Self._mapNames(expr) { $0.uppercased() == oldKey ? name : $0 }
                    if g != expr {
                        book.sheets[scope].cells[a]?.formula = g
                        book.sheets[scope].cells[a]?.input = Formula.text(g)
                    }
                }
            }
            book.fileNames[i].name = name
            book.fileNames[i].text = text
        }
        return nil
    }

    /// Delete a workbook-wide name. Formulas that use it keep the text and show #NAME?, as in Excel. One undo step.
    @discardableResult
    func deleteName(_ name: String, scope: Int? = nil) -> NameProblem? {
        let key = name.uppercased()
        if let scope {
            guard book.fileNames.contains(where: { $0.localSheet == scope && $0.name.uppercased() == key }) else { return .notFound }
            structural { book.fileNames.removeAll { $0.localSheet == scope && $0.name.uppercased() == key } }
            return nil
        }
        guard book.names[key] != nil else { return .notFound }
        structural {
            book.names[key] = nil
            book.nameSpellings[key] = nil
        }
        return nil
    }

    /// What a name refers to is a formula without the `=`; accept it typed with one, and refuse text that does not parse.
    static func normalisedReference(_ text: String) -> String? {
        var t = Substring(text)
        while t.first == " " { t.removeFirst() }
        while t.last == " " { t.removeLast() }
        if t.first == "=" { t.removeFirst() }
        if t.isEmpty { return nil }
        guard (try? Formula.parse("=" + t)) != nil else { return nil }
        return String(t)
    }

    /// Where a name box entry that is a defined name points, when it refers to one block of cells.
    func nameTarget(_ text: String) -> (sheet: Int, range: CellRange)? {
        guard var ref = book.names[text.uppercased()] else { return nil }
        if ref.hasPrefix("=") { ref.removeFirst() }
        guard let bang = ref.lastIndex(of: "!") else { return nil }
        var sheetName = String(ref[..<bang])
        if sheetName.hasPrefix("'") && sheetName.hasSuffix("'") && sheetName.count >= 2 {
            sheetName = String(sheetName.dropFirst().dropLast()).replacingAll("''", with: "'")
        }
        guard let si = book.sheet(named: sheetName) else { return nil }
        let cells = String(ref[ref.index(after: bang)...]).replacingAll("$", with: "").uppercased()
        guard let r = CellRange(cells) else { return nil }
        return (si, r)
    }

    /// Typing a new name in the name box names the selection (Excel does the same). One undo step.
    /// The selection as an absolute reference ("Data!$A$1:$B$4"), quoting the sheet name when it needs it.
    func selectionReference() -> String? {
        let r = selection
        func abs(_ a: CellAddress) -> String { "$" + CellAddress.columnName(a.col) + "$" + String(a.row + 1) }
        let cells = r.topLeft == r.bottomRight ? abs(r.topLeft) : abs(r.topLeft) + ":" + abs(r.bottomRight)
        var sheetName = sheet.name
        let plain = !sheetName.isEmpty && sheetName.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
        if !plain { sheetName = "'" + sheetName.replacingAll("'", with: "''") + "'" }
        return sheetName + "!" + cells
    }

    @discardableResult
    func defineNameForSelection(_ name: String) -> NameProblem? {
        defineName(name, refersTo: selectionReference() ?? "")
    }

    private func _renameNameInFormulas(from oldKey: String, to new: String) {
        for ws in book.sheets {
            for (a, c) in ws.cells {
                guard let expr = c.formula else { continue }
                let g = Self._mapNames(expr) { $0.uppercased() == oldKey ? new : $0 }
                if g != expr {
                    ws.cells[a]?.formula = g
                    ws.cells[a]?.input = Formula.text(g)
                }
            }
        }
        for (k, v) in book.names {
            guard let e = try? Formula.parse(v) else { continue }
            let g = Self._mapNames(e) { $0.uppercased() == oldKey ? new : $0 }
            if g != e { book.names[k] = Formula.print(g) }
        }
    }

    /// Every defined-name use in the formula through `f`.
    static func _mapNames(_ e: FormulaExpr, _ f: (String) -> String) -> FormulaExpr {
        switch e {
        case .name(let n): return .name(f(n))
        case .negate(let x): return .negate(_mapNames(x, f))
        case .plus(let x): return .plus(_mapNames(x, f))
        case .percent(let x): return .percent(_mapNames(x, f))
        case .paren(let x): return .paren(_mapNames(x, f))
        case .binary(let op, let a, let b): return .binary(op, _mapNames(a, f), _mapNames(b, f))
        case .call(let n, let args): return .call(n, args.map { _mapNames($0, f) })
        default: return e
        }
    }
}
