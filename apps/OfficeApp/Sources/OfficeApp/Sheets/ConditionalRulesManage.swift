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
        structural { _removeCFRule(row) }
    }

    /// The whole rule's text range (open tag to its close) in `text`.
    private static func _ruleRange(_ text: String, _ row: CFRuleRow) -> Range<String.Index>? {
        guard let r = _cfTag(text, row.occurrence, ext: row.ext) else { return nil }
        var end = r.upperBound
        let close = row.ext ? "</x14:cfRule>" : "</cfRule>"
        if !text[r].hasSuffix("/>"), let c = text.findRange(of: close, in: r.upperBound ..< text.endIndex) { end = c.upperBound }
        return r.lowerBound ..< end
    }

    /// Take one rule out of the kept XML (inside a caller's undo step). An element left with no rules goes too.
    private func _removeCFRule(_ row: CFRuleRow) {
        guard row.element < sheet.keptElements.count else { return }
        var t = sheet.keptElements[row.element].text
        guard let r = Self._ruleRange(t, row) else { return }
        t.removeSubrange(r)
        if row.ext { t = Self._tidyExt(t) }
        if row.ext ? t.findRange(of: "<ext ") == nil : Self._cfTag(t, 0) == nil { sheet.keptElements.remove(at: row.element) }
        else { sheet.keptElements[row.element].text = t }
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

/// X-DA-3c: a rule as the Edit Rule dialog shows it. Only a rule the dialog can show in full gets one
/// (rewriting it from the form gives the same XML, its look and rank aside), so an edit never drops a setting.
struct CFRuleEdit {
    var spec: CFSpec
    var applies: [CellRange]
    /// The rule's look (dxf) as read; nil for the kinds with no look.
    var dxfId: Int?
    /// The look has borders or a number format the dialog cannot show: it is kept, not offered for change.
    var lookLocked: Bool
}

extension WorkbookController {
    /// `text` ("A1:B4 D2", commas too) as ranges, or nil when any part is not a range.
    static func cfRanges(_ text: String) -> [CellRange]? {
        let parts = text.replacingAll(",", with: " ").split(separator: " ").map { String($0).replacingAll("$", with: "") }
        let out = parts.compactMap { CellRange($0) }
        return out.isEmpty || out.count != parts.count ? nil : out
    }

    private static func _sameXML(_ a: XNode, _ b: XNode, ignoring: Set<String>) -> Bool {
        guard a.name == b.name, a.children.count == b.children.count,
              a.text.trimmingWhitespace() == b.text.trimmingWhitespace() else { return false }
        let ka = a.attrs.filter { !ignoring.contains($0.key) && !$0.key.hasPrefix("xmlns") }
        let kb = b.attrs.filter { !ignoring.contains($0.key) && !$0.key.hasPrefix("xmlns") }
        guard ka == kb else { return false }
        return zip(a.children, b.children).allSatisfy { _sameXML($0, $1, ignoring: []) }
    }

    private static func _rgb(_ n: XNode?) -> UInt32? {
        guard let n = n, n.attrs.count == 1, let v = n["rgb"], v.count == 8 else { return nil }
        return UInt32(v, radix: 16).map { $0 & 0xFFFFFF }   // the form keeps opaque colours; another alpha fails the full-show check
    }

    /// The rule of `row` as the form shows it, or nil when the form cannot carry all of it.
    func conditionalRuleForEdit(_ row: CFRuleRow) -> CFRuleEdit? {
        guard row.element < sheet.keptElements.count, let applies = Self.cfRanges(row.applies),
              let root = XNode.parse(Data(sheet.keptElements[row.element].text.utf8)) else { return nil }
        if row.ext {
            let rules = root.descendants("x14:cfRule")
            guard rules.indices.contains(row.occurrence), let name = rules[row.occurrence].first("x14:iconSet")?["iconSet"],
                  let mine = XNode.parse(Data(IconSets2010.block(name, sqref: row.applies, priority: row.priority).utf8))?.first("x14:cfRule"),
                  Self._sameXML(rules[row.occurrence], mine, ignoring: ["priority", "id", "stopIfTrue"]) else { return nil }
            return CFRuleEdit(spec: CFSpec(kind: .iconSet(name)), applies: applies, dxfId: nil, lookLocked: false)
        }
        let rules = root.kids("cfRule")
        guard rules.indices.contains(row.occurrence) else { return nil }
        let r = rules[row.occurrence]
        let f = r.kids("formula").map(\.text)
        let kind: CFSpec.Kind
        switch r["type"] ?? "" {
        case "cellIs": guard let op = r["operator"], !f.isEmpty else { return nil }; kind = .cellIs(op: op, f[0], f.count > 1 ? f[1] : nil)
        case "expression": guard f.count == 1 else { return nil }; kind = .expression(f[0])
        case "containsText", "notContainsText", "beginsWith", "endsWith":
            guard let t = r["text"] else { return nil }; kind = .text(op: r["type"]!, t)
        case "containsBlanks", "notContainsBlanks": kind = .blanks(r["type"] == "containsBlanks")
        case "containsErrors", "notContainsErrors": kind = .errors(r["type"] == "containsErrors")
        case "top10": kind = .top(rank: Int(r["rank"] ?? "") ?? 0, percent: r["percent"] == "1", bottom: r["bottom"] == "1")
        case "aboveAverage": kind = .average(above: r["aboveAverage"] != "0", equal: r["equalAverage"] == "1")
        case "duplicateValues", "uniqueValues": kind = .duplicates(unique: r["type"] == "uniqueValues")
        case "timePeriod": guard let p = r["timePeriod"] else { return nil }; kind = .timePeriod(p)
        case "colorScale":
            let cs = r.kids("colorScale").first?.kids("color").map { Self._rgb($0) } ?? []
            guard !cs.isEmpty, cs.allSatisfy({ $0 != nil }) else { return nil }; kind = .colorScale(cs.compactMap { $0 })
        case "dataBar": guard let c = Self._rgb(r.kids("dataBar").first?.kids("color").first) else { return nil }; kind = .dataBar(c)
        case "iconSet": kind = .iconSet(r.kids("iconSet").first?["iconSet"] ?? "3TrafficLights1")
        default: return nil
        }
        let spec = CFSpec(kind: kind)
        let built = _cfBody(spec, first: applies[0].topLeft.a1)
        guard built.problem == nil else { return nil }
        let parts = built.body.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        let xml = "<cfRule " + parts[0] + ">" + (parts.count > 1 ? String(parts[1]) : "") + "</cfRule>"
        guard let mine = XNode.parse(Data(xml.utf8)), Self._sameXML(r, mine, ignoring: ["priority", "stopIfTrue", "dxfId"]) else { return nil }
        var dxfId: Int?
        var locked = false
        if built.highlight {
            guard let s = r["dxfId"], let id = Int(s), book.dxfs.indices.contains(id) else { return nil }
            dxfId = id
            locked = book.dxfs[id].numberFormat != nil || !book.dxfs[id].borders.isEmpty
        }
        return CFRuleEdit(spec: spec, applies: applies, dxfId: dxfId, lookLocked: locked)
    }

    /// Edit Rule: put `spec` over `applies` in place of the rule of `row`, at the same rank and Stop If True.
    /// `keepLook` keeps the rule's own look; otherwise `spec.look` becomes a new one. One undo step.
    /// A rule the form cannot show in full is refused, never rewritten.
    func editConditionalRule(_ row: CFRuleRow, _ spec: CFSpec, applies: [CellRange], keepLook: Bool) -> CFProblem? {
        guard !applies.isEmpty else { return .noCells }
        guard let old = conditionalRuleForEdit(row) else { return .notEditable }
        let built = _cfBody(spec, first: applies[0].topLeft.a1)
        if let p = built.problem { return p }
        let sq = applies.map { $0.isSingle ? $0.topLeft.a1 : $0.a1 }.joined(separator: " ")
        var dxfAttr = ""
        if built.highlight {
            if keepLook || old.lookLocked, let id = old.dxfId { dxfAttr = " dxfId=\"\(id)\"" }
            else {
                guard spec.look != DxfStyle() else { return .noLook }
                dxfAttr = " dxfId=\"\(_appendDxf(spec.look))\""
            }
        }
        var ext2010: String?
        if case .iconSet(let name) = spec.kind, IconSets2010.names.contains(name) { ext2010 = name }
        let parts = built.body.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        let rule = "<cfRule " + parts[0] + dxfAttr + " priority=\"\(row.priority)\"" + (row.stopIfTrue ? " stopIfTrue=\"1\"" : "")
            + (parts.count > 1 && !parts[1].isEmpty ? ">" + parts[1] + "</cfRule>" : "/>")
        structural {
            if !row.ext, ext2010 == nil, sq == row.applies, row.element < sheet.keptElements.count,
               let r = Self._ruleRange(sheet.keptElements[row.element].text, row) {
                sheet.keptElements[row.element].text.replaceSubrange(r, with: rule)
                return
            }
            _removeCFRule(row)
            if let name = ext2010 {
                var blk = IconSets2010.block(name, sqref: sq, priority: row.priority)
                if row.stopIfTrue { blk = blk.replacingAll("<x14:cfRule type=\"iconSet\"", with: "<x14:cfRule type=\"iconSet\" stopIfTrue=\"1\"") }
                if let i = sheet.keptElements.firstIndex(where: { $0.name == "extLst" }) {
                    sheet.keptElements[i].text = IconSets2010.inserting(blk, into: sheet.keptElements[i].text)
                } else {
                    sheet.keptElements.append(("extLst", IconSets2010.inserting(blk, into: nil)))
                }
            } else {
                sheet.keptElements.append(("conditionalFormatting", "<conditionalFormatting sqref=\"\(sq)\">\(rule)</conditionalFormatting>"))
            }
        }
        return nil
    }
}
