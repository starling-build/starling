// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Data validation, read from the sheet's kept `<dataValidations>` (the
// XML is written back as the file had it): a list rule gives the active
// cell Excel's dropdown arrow and its choices, and an entry that breaks a
// rule whose error alert is on is refused — the cell keeps what it had and
// the status bar says why (Excel asks Retry/Cancel; this is its Cancel).

import Foundation

struct ValidationRule {
    var ranges: [CellRange]
    var type: String            // list, whole, decimal, textLength, date, time, custom
    var op: String              // between, notBetween, equal, … (not for list/custom)
    var formula1: FormulaExpr?
    var formula2: FormulaExpr?
    var allowBlank: Bool
    /// showErrorMessage: refuse entries that break it.
    var refuses: Bool
    /// showDropDown="1" is Excel's flag for hiding the arrow.
    var arrow: Bool
    var errorTitle: String?
    var error: String?

    var origin: CellAddress { ranges.first?.topLeft ?? CellAddress(row: 0, col: 0) }
    func covers(_ a: CellAddress) -> Bool { ranges.contains { $0.contains(a) } }
}

enum Validations {
    static func rules(_ ws: Worksheet) -> [ValidationRule] {
        var out: [ValidationRule] = []
        for (name, text) in ws.keptElements where name == "dataValidations" {
            guard let root = XNode.parse(Data(text.utf8)) else { continue }
            for v in root.kids("dataValidation") {
                let ranges = (v["sqref"] ?? "").split(separator: " ").compactMap { CellRange(String($0)) }
                guard !ranges.isEmpty else { continue }
                func f(_ n: String) -> FormulaExpr? { v.child(n).flatMap { try? Formula.parse("=" + $0.text) } }
                out.append(ValidationRule(
                    ranges: ranges, type: v["type"] ?? "none", op: v["operator"] ?? "between",
                    formula1: f("formula1"), formula2: f("formula2"),
                    allowBlank: v["allowBlank"] == "1", refuses: v["showErrorMessage"] == "1",
                    arrow: v["showDropDown"] != "1", errorTitle: v["errorTitle"], error: v["error"]))
            }
        }
        return out
    }
}

extension WorkbookController {
    func validation(at a: CellAddress) -> ValidationRule? {
        validationRules.first { $0.covers(a) && $0.type != "none" }
    }

    private func _value(_ e: FormulaExpr?, _ rule: ValidationRule, _ a: CellAddress) -> EvalValue? {
        guard let e else { return nil }
        let shifted = Formula.shifted(e, rows: a.row - rule.origin.row, cols: a.col - rule.origin.col)
        return engine.evaluate(shifted, EvalContext(engine: engine, sheet: activeSheet, cell: a))
    }

    /// A list rule's choices: its quoted items ("a,b,c") or its range's values.
    func validationChoices(at a: CellAddress) -> [String]? {
        guard let rule = validation(at: a), rule.type == "list", let f = rule.formula1 else { return nil }
        if case .text(let s) = f {
            return s.split(separator: ",").map { String($0).trimmingWhitespace() }
        }
        guard let v = _value(f, rule, a) else { return nil }
        let ctx = EvalContext(engine: engine, sheet: activeSheet, cell: a)
        let cells: [CellValue]
        switch v {
        case .range(let si, let r): cells = engine.values(si, r, includeEmpty: false)
        case .array(let rows): cells = rows.flatMap { $0 }
        case .scalar: cells = [engine.scalar(v, ctx)]
        }
        return cells.filter { !$0.isEmpty }.map { NumberFormat.display($0, "General", width: 255).text }
    }

    /// Why `value` may not go into `a`; nil when it may.
    func validationRefusal(_ value: CellValue, at a: CellAddress) -> String? {
        guard let rule = validation(at: a), rule.refuses else { return nil }
        let message = rule.error ?? "This value doesn't match the data validation restrictions defined for this cell."
        if value.isEmpty { return rule.allowBlank || rule.type == "custom" ? nil : message }
        let ctx = EvalContext(engine: engine, sheet: activeSheet, cell: a)
        func scalar(_ e: FormulaExpr?) -> CellValue? { _value(e, rule, a).map { engine.scalar($0, ctx) } }
        switch rule.type {
        case "list":
            guard let choices = validationChoices(at: a) else { return nil }
            let shown = NumberFormat.display(value, "General", width: 255).text.lowercased()
            return choices.contains { $0.lowercased() == shown } ? nil : message
        case "custom":
            // The rule's formula, evaluated as if the value were already there.
            guard let f = rule.formula1 else { return nil }
            let ws = sheet
            let saved = ws.cells[a]
            var probe = saved ?? Cell(input: "")
            probe.formula = nil; probe.value = value
            ws.cells[a] = probe
            engine.recalculate()
            let ok = scalar(f).map { if case .bool(let b) = $0 { return b }; return ($0.number ?? 0) != 0 } ?? true
            ws.cells[a] = saved
            engine.recalculate()
            return ok ? nil : message
        default:
            // whole, decimal, date, time compare the number; textLength the length.
            var n: Double
            if rule.type == "textLength" {
                n = Double(NumberFormat.display(value, "General", width: 255).text.count)
            } else {
                guard let x = value.number else { return message }
                if rule.type == "whole" && x != x.rounded() { return message }
                n = x
            }
            guard let a1 = scalar(rule.formula1)?.number else { return nil }
            let b1 = scalar(rule.formula2)?.number
            let ok: Bool
            switch rule.op {
            case "notBetween": ok = !(n >= min(a1, b1 ?? a1) && n <= max(a1, b1 ?? a1))
            case "equal": ok = n == a1
            case "notEqual": ok = n != a1
            case "greaterThan": ok = n > a1
            case "lessThan": ok = n < a1
            case "greaterThanOrEqual": ok = n >= a1
            case "lessThanOrEqual": ok = n <= a1
            default: ok = n >= min(a1, b1 ?? a1) && n <= max(a1, b1 ?? a1)
            }
            _ = n
            return ok ? nil : message
        }
    }
}
