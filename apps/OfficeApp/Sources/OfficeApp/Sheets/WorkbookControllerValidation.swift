// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-DA-4: set and clear data validation as undoable commands. The sheet keeps
// its `dataValidations` element as the file had it, so a rule this code does
// not touch stays byte for byte as read (attributes it does not model, such as
// imeMode, included). Setting a rule on cells first takes those cells out of
// any rule already covering them, rewriting only that rule's `sqref`.

import Foundation

enum ValidationProblem: Error {
    case noCells, needsValue, badFormula, listTooLong, noType

    var message: String {
        switch self {
        case .noCells: return "Pick the cells to validate."
        case .needsValue: return "This rule needs a value to compare with."
        case .badFormula: return "That isn't a valid value or formula."
        case .listTooLong: return "A typed list can hold at most 255 characters."
        case .noType: return "Pick what to allow."
        }
    }
}

extension WorkbookController {
    /// The sheet's validation rules (the ones that restrict something) over `range`.
    func validationRules(over range: CellRange) -> [ValidationRule] {
        validationRules.filter { $0.type != "none" && $0.ranges.contains { $0.intersects(range) } }
    }

    /// A typed list ("Yes, No, Maybe") as the quoted formula Excel stores, or nil when too long.
    static func listFormulaText(_ items: [String]) -> String? {
        let text = items.joined(separator: ",")
        guard text.count <= 255 else { return nil }
        return "\"" + text.replacingAll("\"", with: "\"\"") + "\""
    }

    /// Put `rule` on its `ranges`. One undo step.
    @discardableResult
    func setValidation(_ rule: ValidationRule, formula1 text1: String?, formula2 text2: String? = nil) -> ValidationProblem? {
        guard !rule.ranges.isEmpty else { return .noCells }
        guard rule.type != "none", !rule.type.isEmpty else { return .noType }
        func parse(_ t: String?) -> FormulaExpr?? {
            guard let t else { return .some(nil) }
            var s = t
            while s.first == " " { s.removeFirst() }
            while s.last == " " { s.removeLast() }
            if s.first == "=" { s.removeFirst() }
            if s.isEmpty { return .some(nil) }
            guard let e = try? Formula.parse("=" + s) else { return nil }
            return .some(e)
        }
        guard let f1 = parse(text1) else { return .badFormula }
        guard let f2 = parse(text2) else { return .badFormula }
        if f1 == nil { return .needsValue }
        let twoValues = rule.type != "list" && rule.type != "custom" && (rule.op == "between" || rule.op == "notBetween")
        if twoValues && f2 == nil { return .needsValue }
        var r = rule
        r.formula1 = f1
        r.formula2 = twoValues ? f2 : nil
        structural {
            _takeCellsOutOfValidations(rule.ranges)
            _appendValidation(Self._validationXML(r))
        }
        return nil
    }

    /// Remove validation from `ranges` (Excel's "Clear All"). One undo step.
    func clearValidation(on ranges: [CellRange]) {
        guard !ranges.isEmpty, ranges.contains(where: { r in !validationRules(over: r).isEmpty }) else { return }
        structural { _takeCellsOutOfValidations(ranges) }
    }

    func _takeCellsOutOfValidations(_ cut: [CellRange]) {
        guard let i = sheet.keptElements.firstIndex(where: { $0.name == "dataValidations" }) else { return }
        let split = RawXML.split([UInt8](sheet.keptElements[i].text.utf8))
        var kids: [String] = []
        for kid in split.children {
            guard kid.name == "dataValidation" || kid.name.hasSuffix(":dataValidation"),
                  let (a, b) = Self._sqrefSpan(kid.text) else { kids.append(kid.text); continue }
            let ranges = kid.text[a ..< b].split(separator: " ").compactMap { CellRange(String($0)) }
            let left = ranges.flatMap { r in cut.reduce([r]) { pieces, c in pieces.flatMap { Self._subtract($0, c) } } }
            if left == ranges { kids.append(kid.text); continue }
            guard !left.isEmpty else { continue }
            var t = kid.text
            t.replaceSubrange(a ..< b, with: left.map { $0.isSingle ? $0.topLeft.a1 : $0.a1 }.joined(separator: " "))
            kids.append(t)
        }
        _setValidationKids(kids, root: split.rootStart, name: split.rootName, at: i)
    }

    func _appendValidation(_ xml: String) {
        if let i = sheet.keptElements.firstIndex(where: { $0.name == "dataValidations" }) {
            let split = RawXML.split([UInt8](sheet.keptElements[i].text.utf8))
            _setValidationKids(split.children.map { $0.text } + [xml], root: split.rootStart, name: split.rootName, at: i)
        } else {
            sheet.keptElements.append(("dataValidations", "<dataValidations count=\"1\">" + xml + "</dataValidations>"))
        }
    }

    func _setValidationKids(_ kids: [String], root: String, name: String, at i: Int) {
        guard !kids.isEmpty else { sheet.keptElements.remove(at: i); return }
        var start = root
        if let r = start.findRange(of: " count=\"") {
            let close = start.findRange(of: "\"", in: r.upperBound ..< start.endIndex)?.lowerBound ?? start.endIndex
            start.replaceSubrange(r.upperBound ..< close, with: "\(kids.count)")
        }
        sheet.keptElements[i].text = start + kids.joined() + "</\(name)>"
    }

    /// The text span of a `<dataValidation>`'s sqref value.
    private static func _sqrefSpan(_ s: String) -> (String.Index, String.Index)? {
        guard let tagEnd = s.firstIndex(of: ">"),
              let a = s.findRange(of: " sqref=\"", in: s.startIndex ..< tagEnd),
              let b = s.findRange(of: "\"", in: a.upperBound ..< s.endIndex) else { return nil }
        return (a.upperBound, b.lowerBound)
    }

    /// `r` without `c`: up to four rectangles.
    static func _subtract(_ r: CellRange, _ c: CellRange) -> [CellRange] {
        guard let x = r.intersection(c) else { return [r] }
        var out: [CellRange] = []
        if x.top > r.top { out.append(CellRange(top: r.top, left: r.left, bottom: x.top - 1, right: r.right)) }
        if x.bottom < r.bottom { out.append(CellRange(top: x.bottom + 1, left: r.left, bottom: r.bottom, right: r.right)) }
        if x.left > r.left { out.append(CellRange(top: x.top, left: r.left, bottom: x.bottom, right: x.left - 1)) }
        if x.right < r.right { out.append(CellRange(top: x.top, left: x.right + 1, bottom: x.bottom, right: r.right)) }
        return out
    }

    static func _validationXML(_ r: ValidationRule) -> String {
        var a = " type=\"\(Xlsx._esc(r.type))\""
        if r.type != "list" && r.type != "custom" && r.op != "between" { a += " operator=\"\(Xlsx._esc(r.op))\"" }
        if r.errorStyle != "stop" { a += " errorStyle=\"\(Xlsx._esc(r.errorStyle))\"" }
        if r.allowBlank { a += " allowBlank=\"1\"" }
        if !r.arrow { a += " showDropDown=\"1\"" }
        if r.hasPrompt { a += " showInputMessage=\"1\"" }
        if r.refuses { a += " showErrorMessage=\"1\"" }
        if let t = r.errorTitle, !t.isEmpty { a += " errorTitle=\"\(Xlsx._esc(t))\"" }
        if let t = r.error, !t.isEmpty { a += " error=\"\(Xlsx._esc(t))\"" }
        if r.hasPrompt {
            if let t = r.promptTitle, !t.isEmpty { a += " promptTitle=\"\(Xlsx._esc(t))\"" }
            if let t = r.prompt, !t.isEmpty { a += " prompt=\"\(Xlsx._esc(t))\"" }
        }
        a += " sqref=\"" + r.ranges.map { $0.isSingle ? $0.topLeft.a1 : $0.a1 }.joined(separator: " ") + "\""
        var out = "<dataValidation\(a)>"
        if let f = r.formula1 { out += "<formula1>\(Xlsx._esc(Formula.print(f)))</formula1>" }
        if let f = r.formula2 { out += "<formula2>\(Xlsx._esc(Formula.print(f)))</formula2>" }
        return out + "</dataValidation>"
    }
}
