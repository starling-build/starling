import Foundation

/// One line of the Manage Rules list: a rule of the active sheet, with where it applies and how it ranks.
struct CFRuleRow: Equatable {
    var element: Int          // index in the sheet's kept elements
    var ext: Bool = false     // an x14 rule in the extension list (the 2010 icon sets)
    var occurrence: Int       // which cfRule inside that element
    var priority: Int
    var stopIfTrue: Bool
    var applies: String       // the sqref, as written
    var summary: String       // plain words: "Cell value > 5", "Data bar" …
}

extension WorkbookController {
    /// Open-tag range of the `n`-th `<cfRule` in `text`.
    private static func _cfTag(_ text: String, _ n: Int, ext: Bool = false) -> Range<String.Index>? {
        var from = text.startIndex
        var seen = 0
        while let a = text.findRange(of: ext ? "<x14:cfRule" : "<cfRule", in: from ..< text.endIndex) {
            guard let b = text.findRange(of: ">", in: a.upperBound ..< text.endIndex) else { return nil }
            if seen == n { return a.lowerBound ..< b.upperBound }
            seen += 1
            from = b.upperBound
        }
        return nil
    }

    private static func _attr(_ tag: String, _ name: String) -> String? {
        guard let a = tag.findRange(of: " \(name)=\""),
              let b = tag.findRange(of: "\"", in: a.upperBound ..< tag.endIndex) else { return nil }
        return String(tag[a.upperBound ..< b.lowerBound])
    }

    private static func _setAttr(_ tag: String, _ name: String, _ value: String?) -> String {
        var t = tag
        if let a = t.findRange(of: " \(name)=\""), let b = t.findRange(of: "\"", in: a.upperBound ..< t.endIndex) {
            if let v = value { t.replaceSubrange(a.upperBound ..< b.lowerBound, with: v) }
            else { t.removeSubrange(a.lowerBound ..< b.upperBound) }
        } else if let v = value, let c = t.findRange(of: "<cfRule") ?? t.findRange(of: "<x14:cfRule") {
            t.insert(contentsOf: " \(name)=\"\(v)\"", at: c.upperBound)
        }
        return t
    }

    private static func _cfWords(_ type: String, _ tag: String, _ body: String) -> String {
        let op = _attr(tag, "operator") ?? ""
        func f(_ i: Int) -> String {
            var from = body.startIndex
            var k = 0
            while let a = body.findRange(of: "<formula>", in: from ..< body.endIndex),
                  let b = body.findRange(of: "</formula>", in: a.upperBound ..< body.endIndex) {
                if k == i { return String(body[a.upperBound ..< b.lowerBound]) }
                k += 1; from = b.upperBound
            }
            return ""
        }
        let ops = ["greaterThan": ">", "lessThan": "<", "equal": "=", "notEqual": "<>",
                   "greaterThanOrEqual": ">=", "lessThanOrEqual": "<="]
        switch type {
        case "cellIs":
            if op == "between" { return "Cell value between \(f(0)) and \(f(1))" }
            if op == "notBetween" { return "Cell value not between \(f(0)) and \(f(1))" }
            return "Cell value \(ops[op] ?? op) \(f(0))"
        case "expression": return "Formula: \(f(0))"
        case "containsText": return "Text contains \"\(_attr(tag, "text") ?? "")\""
        case "notContainsText": return "Text does not contain \"\(_attr(tag, "text") ?? "")\""
        case "beginsWith": return "Text begins with \"\(_attr(tag, "text") ?? "")\""
        case "endsWith": return "Text ends with \"\(_attr(tag, "text") ?? "")\""
        case "containsBlanks": return "Blanks"
        case "notContainsBlanks": return "No blanks"
        case "containsErrors": return "Errors"
        case "notContainsErrors": return "No errors"
        case "top10":
            let n = _attr(tag, "rank") ?? "10"
            let pct = _attr(tag, "percent") == "1" ? "%" : ""
            return (_attr(tag, "bottom") == "1" ? "Bottom " : "Top ") + n + pct
        case "aboveAverage": return _attr(tag, "aboveAverage") == "0" ? "Below average" : "Above average"
        case "duplicateValues": return "Duplicate values"
        case "uniqueValues": return "Unique values"
        case "timePeriod": return "Dates: \(_attr(tag, "timePeriod") ?? "today")"
        case "colorScale": return "Colour scale"
        case "dataBar": return "Data bar"
        case "iconSet": return "Icon set"
        default: return type
        }
    }

    /// Every rule of the active sheet, highest priority (lowest number) first.
    func conditionalRuleRows() -> [CFRuleRow] {
        var out: [CFRuleRow] = []
        for (i, e) in sheet.keptElements.enumerated() where e.name == "conditionalFormatting" {
            guard let node = XNode.parse(Data(e.text.utf8)) else { continue }
            let sq = node["sqref"] ?? ""
            var n = 0
            while let r = Self._cfTag(e.text, n) {
                let tag = String(e.text[r])
                let tail = String(e.text[r.upperBound...])
                let body = tail.findRange(of: "</cfRule>").map { String(tail[tail.startIndex ..< $0.lowerBound]) } ?? ""
                let type = Self._attr(tag, "type") ?? ""
                out.append(CFRuleRow(element: i, occurrence: n,
                                     priority: Int(Self._attr(tag, "priority") ?? "") ?? 0,
                                     stopIfTrue: Self._attr(tag, "stopIfTrue") == "1",
                                     applies: sq, summary: Self._cfWords(type, tag, body)))
                n += 1
            }
        }
        for (i, e) in sheet.keptElements.enumerated() where e.name == "extLst" {
            guard let root = XNode.parse(Data(e.text.utf8)) else { continue }
            for (n, r) in root.descendants("x14:cfRule").enumerated() {
                guard r["type"] == "iconSet", let set = r.first("x14:iconSet"), let name = set["iconSet"],
                      IconSets2010.names.contains(name), set["custom"] != "1",
                      let block = root.descendants("x14:conditionalFormatting").first(where: { $0.all("x14:cfRule").contains { $0 === r } }) else { continue }
                out.append(CFRuleRow(element: i, ext: true, occurrence: n, priority: Int(r["priority"] ?? "") ?? 0,
                                     stopIfTrue: r["stopIfTrue"] == "1", applies: block.first("xm:sqref")?.text ?? "", summary: "Icon set"))
            }
        }
        return out.sorted { $0.priority < $1.priority }
    }

    private func _editCFTag(_ row: CFRuleRow, _ change: (String) -> String) {
        guard row.element < sheet.keptElements.count else { return }
        var t = sheet.keptElements[row.element].text
        guard let r = Self._cfTag(t, row.occurrence, ext: row.ext) else { return }
        t.replaceSubrange(r, with: change(String(t[r])))
        sheet.keptElements[row.element].text = t
    }

    /// Delete one rule. An element left with no rules goes too. One undo step.
    func deleteConditionalRule(_ row: CFRuleRow) {
        guard row.element < sheet.keptElements.count else { return }
        structural {
            var t = sheet.keptElements[row.element].text
            guard let r = Self._cfTag(t, row.occurrence, ext: row.ext) else { return }
            var end = r.upperBound
            let close = row.ext ? "</x14:cfRule>" : "</cfRule>"
            if !t[r].hasSuffix("/>"), let c = t.findRange(of: close, in: r.upperBound ..< t.endIndex) { end = c.upperBound }
            t.removeSubrange(r.lowerBound ..< end)
            if row.ext { t = Self._tidyExt(t) }
            if row.ext ? t.findRange(of: "<ext ") == nil : Self._cfTag(t, 0) == nil { sheet.keptElements.remove(at: row.element) }
            else { sheet.keptElements[row.element].text = t }
        }
    }

    /// After an x14 rule left: drop a block with no rule, a container with no rule, then an ext left empty.
    private static func _tidyExt(_ text: String) -> String {
        var t = text
        func drop(_ open: String, _ close: String, unless inner: String) {
            var from = t.startIndex
            while let a = t.findRange(of: open, in: from ..< t.endIndex), let b = t.findRange(of: close, in: a.upperBound ..< t.endIndex) {
                if String(t[a.upperBound ..< b.lowerBound]).findRange(of: inner) == nil {
                    t.removeSubrange(a.lowerBound ..< b.upperBound); from = a.lowerBound
                } else { from = b.upperBound }
            }
        }
        drop("<x14:conditionalFormatting ", "</x14:conditionalFormatting>", unless: "<x14:cfRule")
        drop("<x14:conditionalFormattings>", "</x14:conditionalFormattings>", unless: "<x14:cfRule")
        drop("<ext ", "</ext>", unless: "<")   // only an ext left empty: an x15 or sparkline ext stays
        return t
    }

    /// Swap the priority of `row` with its neighbour above (`up`) or below. One undo step.
    func moveConditionalRule(_ row: CFRuleRow, up: Bool) {
        let rows = conditionalRuleRows()
        guard let i = rows.firstIndex(where: { $0.element == row.element && $0.ext == row.ext && $0.occurrence == row.occurrence }) else { return }
        let j = up ? i - 1 : i + 1
        guard rows.indices.contains(j) else { return }
        let a = rows[i], b = rows[j]
        structural {
            _editCFTag(a) { Self._setAttr($0, "priority", String(b.priority)) }
            _editCFTag(b) { Self._setAttr($0, "priority", String(a.priority)) }
        }
    }

    /// Turn Stop If True on or off for one rule. One undo step.
    func setConditionalStopIfTrue(_ row: CFRuleRow, _ on: Bool) {
        structural { _editCFTag(row) { Self._setAttr($0, "stopIfTrue", on ? "1" : nil) } }
    }
}
