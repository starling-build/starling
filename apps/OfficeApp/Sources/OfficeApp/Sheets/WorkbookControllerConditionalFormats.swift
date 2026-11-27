import Foundation

/// What a user sets for a new conditional-format rule. The controller turns it into the
/// file's own `cfRule` text, so rules it did not touch stay byte for byte as read.
struct CFSpec {
    enum Kind {
        case cellIs(op: String, String, String?)        // equal, greaterThan, between, ...
        case expression(String)
        case text(op: String, String)                   // containsText, notContainsText, beginsWith, endsWith
        case blanks(Bool), errors(Bool)
        case top(rank: Int, percent: Bool, bottom: Bool)
        case average(above: Bool, equal: Bool)
        case duplicates(unique: Bool)
        case timePeriod(String)
        case colorScale([UInt32])                       // two or three colours, low to high
        case dataBar(UInt32)
        case iconSet(String)
    }
    var kind: Kind
    /// How matching cells look (the highlight kinds only).
    var look = DxfStyle()
    var stopIfTrue = false
}

enum CFProblem: Equatable {
    case noCells, needsValue, badFormula, noLook, badColors, relativeFormula, notEditable, badRange
    var message: String {
        switch self {
        case .noCells: return "Select the cells first."
        case .needsValue: return "Enter a value for the rule."
        case .badFormula: return "That formula is not valid."
        case .noLook: return "Choose how matching cells should look."
        case .badColors: return "A colour scale needs two or three colours."
        case .relativeFormula: return "Clearing part of this range would change what its formula refers to. Clear the whole range."
        case .notEditable: return "This rule has settings this editor does not cover, so it is kept as it is. Delete it and add a new one to change it."
        case .badRange: return "Applies to must be cell ranges such as A1:B10, separated by spaces or commas."
        }
    }
}

extension WorkbookController {
    /// The rules that touch `range`, by priority.
    func conditionalRules(over range: CellRange) -> [CFRule] {
        ConditionalFormats.rules(sheet, theme: book.themeColors).filter { r in r.ranges.contains { $0.intersects(range) } }
    }

    /// Add a rule over `ranges`, below every existing rule. One undo step.
    func addConditionalFormat(_ spec: CFSpec, on ranges: [CellRange]) -> CFProblem? {
        guard !ranges.isEmpty else { return .noCells }
        let built = _cfBody(spec, first: ranges[0].topLeft.a1)
        if let p = built.problem { return p }
        let highlight = built.highlight, body = built.body
        var dxfAttr = ""
        if highlight {
            guard spec.look != DxfStyle() else { return .noLook }
            dxfAttr = " dxfId=\"\(_appendDxf(spec.look))\""
        }
        let priority = _nextCFPriority()
        if case .iconSet(let name) = spec.kind, IconSets2010.names.contains(name) {
            let sq = ranges.map { $0.isSingle ? $0.topLeft.a1 : $0.a1 }.joined(separator: " ")
            let blk = IconSets2010.block(name, sqref: sq, priority: priority)
            structural {
                if let i = sheet.keptElements.firstIndex(where: { $0.name == "extLst" }) {
                    sheet.keptElements[i].text = IconSets2010.inserting(blk, into: sheet.keptElements[i].text)
                } else {
                    sheet.keptElements.append(("extLst", IconSets2010.inserting(blk, into: nil)))
                }
            }
            return nil
        }
        let parts = body.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        let rule = "<cfRule " + parts[0] + dxfAttr + " priority=\"\(priority)\"" + (spec.stopIfTrue ? " stopIfTrue=\"1\"" : "")
            + (parts.count > 1 && !parts[1].isEmpty ? ">" + parts[1] + "</cfRule>" : "/>")
        let sqref = ranges.map { $0.isSingle ? $0.topLeft.a1 : $0.a1 }.joined(separator: " ")
        structural {
            sheet.keptElements.append(("conditionalFormatting", "<conditionalFormatting sqref=\"\(sqref)\">\(rule)</conditionalFormatting>"))
        }
        return nil
    }

    /// A rule's text for `spec` ("attributes|children"), whether it takes a look (dxf), or what is wrong with it.
    /// `first` is the top-left cell its formulas are written for.
    func _cfBody(_ spec: CFSpec, first: String) -> (body: String, highlight: Bool, problem: CFProblem?) {
        var highlight = true
        var body = ""
        func formula(_ s: String) -> String? {
            let t = s.hasPrefix("=") ? String(s.dropFirst()) : s
            guard !t.isEmpty, (try? Formula.parse("=" + t)) != nil else { return nil }
            return "<formula>\(Xlsx._esc(t))</formula>"
        }
        switch spec.kind {
        case .cellIs(let op, let a, let b):
            guard !a.isEmpty else { return ("", false, .needsValue) }
            guard let f1 = formula(a) else { return ("", false, .badFormula) }
            var f2 = ""
            if op == "between" || op == "notBetween" {
                guard let bb = b, !bb.isEmpty else { return ("", false, .needsValue) }
                guard let f = formula(bb) else { return ("", false, .badFormula) }
                f2 = f
            }
            body = "type=\"cellIs\" operator=\"\(Xlsx._esc(op))\"" + "|" + f1 + f2
        case .expression(let e):
            guard !e.isEmpty else { return ("", false, .needsValue) }
            guard let f = formula(e) else { return ("", false, .badFormula) }
            body = "type=\"expression\"|" + f
        case .text(let op, let t):
            guard !t.isEmpty else { return ("", false, .needsValue) }
            let first = first
            let q = "\"" + t.replacingAll("\"", with: "\"\"") + "\""
            let f: String
            switch op {
            case "beginsWith": f = "LEFT(\(first),LEN(\(q)))=\(q)"
            case "endsWith": f = "RIGHT(\(first),LEN(\(q)))=\(q)"
            case "notContainsText": f = "ISERROR(SEARCH(\(q),\(first)))"
            default: f = "NOT(ISERROR(SEARCH(\(q),\(first))))"
            }
            let o = op == "beginsWith" ? "beginsWith" : op == "endsWith" ? "endsWith" : op == "notContainsText" ? "notContains" : "containsText"
            body = "type=\"\(op == "containsText" || op == "notContainsText" || op == "beginsWith" || op == "endsWith" ? op : "containsText")\" operator=\"\(o)\" text=\"\(Xlsx._esc(t))\"|<formula>\(Xlsx._esc(f))</formula>"
        case .blanks(let yes):
            let first = first
            body = yes ? "type=\"containsBlanks\"|<formula>LEN(TRIM(\(first)))=0</formula>"
                       : "type=\"notContainsBlanks\"|<formula>LEN(TRIM(\(first)))&gt;0</formula>"
        case .errors(let yes):
            let first = first
            body = yes ? "type=\"containsErrors\"|<formula>ISERROR(\(first))</formula>"
                       : "type=\"notContainsErrors\"|<formula>NOT(ISERROR(\(first)))</formula>"
        case .top(let rank, let percent, let bottom):
            guard rank >= 1 else { return ("", false, .needsValue) }
            body = "type=\"top10\" rank=\"\(rank)\"" + (percent ? " percent=\"1\"" : "") + (bottom ? " bottom=\"1\"" : "") + "|"
        case .average(let above, let equal):
            body = "type=\"aboveAverage\"" + (above ? "" : " aboveAverage=\"0\"") + (equal ? " equalAverage=\"1\"" : "") + "|"
        case .duplicates(let unique):
            body = "type=\"\(unique ? "uniqueValues" : "duplicateValues")\"|"
        case .timePeriod(let p):
            let first = first
            body = "type=\"timePeriod\" timePeriod=\"\(Xlsx._esc(p))\"|<formula>\(Self._timePeriodFormula(p, first))</formula>"
        case .colorScale(let colors):
            guard colors.count == 2 || colors.count == 3 else { return ("", false, .badColors) }
            highlight = false
            let cfvo = colors.count == 2 ? "<cfvo type=\"min\"/><cfvo type=\"max\"/>"
                                         : "<cfvo type=\"min\"/><cfvo type=\"percentile\" val=\"50\"/><cfvo type=\"max\"/>"
            body = "type=\"colorScale\"|<colorScale>" + cfvo + colors.map { "<color rgb=\"FF\(Self._hex6($0))\"/>" }.joined() + "</colorScale>"
        case .dataBar(let c):
            highlight = false
            body = "type=\"dataBar\"|<dataBar><cfvo type=\"min\"/><cfvo type=\"max\"/><color rgb=\"FF\(Self._hex6(c))\"/></dataBar>"
        case .iconSet(let name):
            highlight = false
            let n = Int(name.prefix(1)) ?? 3
            var cfvo = "<cfvo type=\"percent\" val=\"0\"/>"
            for i in 1 ..< n { cfvo += "<cfvo type=\"percent\" val=\"\((100 * i + n / 2) / n)\"/>" }   // Excel's own 33/67, 25/50/75
            body = "type=\"iconSet\"|<iconSet iconSet=\"\(Xlsx._esc(name))\">" + cfvo + "</iconSet>"
        }
        return (body, highlight, nil)
    }

    /// Take conditional formats off `ranges`. Rules over other cells stay as they were.
    /// Refuses when cutting a range would move the cell a relative formula is written for.
    func clearConditionalFormats(on ranges: [CellRange]) -> CFProblem? {
        guard !ranges.isEmpty else { return .noCells }
        var plan: [(Int, String?)] = []
        for (i, e) in sheet.keptElements.enumerated() where e.name == "conditionalFormatting" {
            guard let node = XNode.parse(Data(e.text.utf8)), let s = node["sqref"] else { continue }
            let old = s.split(separator: " ").compactMap { CellRange(String($0)) }
            let left = old.flatMap { r in ranges.reduce([r]) { ps, c in ps.flatMap { Self._subtract($0, c) } } }
            if left == old { continue }
            if left.isEmpty { plan.append((i, nil)); continue }
            if left.first?.topLeft != old.first?.topLeft,
               node.kids("cfRule").contains(where: { $0.kids("formula").contains { Self._hasCellRef($0.text) } }) {
                return .relativeFormula
            }
            guard let a = e.text.findRange(of: " sqref=\""), let b = e.text.findRange(of: "\"", in: a.upperBound ..< e.text.endIndex) else { continue }
            var t = e.text
            t.replaceSubrange(a.upperBound ..< b.lowerBound, with: left.map { $0.isSingle ? $0.topLeft.a1 : $0.a1 }.joined(separator: " "))
            plan.append((i, t))
        }
        var extPlan: (Int, String)?
        if let i = sheet.keptElements.firstIndex(where: { $0.name == "extLst" }) {
            let t = IconSets2010.clearing(sheet.keptElements[i].text, ranges)
            if t != sheet.keptElements[i].text { extPlan = (i, t) }
        }
        guard !plan.isEmpty || extPlan != nil else { return nil }
        structural {
            if let (i, t) = extPlan { sheet.keptElements[i].text = t }
            for (i, t) in plan.reversed() {
                if let t = t { sheet.keptElements[i].text = t } else { sheet.keptElements.remove(at: i) }
            }
        }
        return nil
    }

    private static func _hasCellRef(_ f: String) -> Bool {
        f.contains { $0.isLetter } && f.contains { $0.isNumber }
    }

    private static func _hex6(_ c: UInt32) -> String {
        let d = Array("0123456789ABCDEF")
        return (0 ..< 6).map { String(d[Int((c >> UInt32((5 - $0) * 4)) & 0xF)]) }.joined()
    }

    private static func _timePeriodFormula(_ p: String, _ c: String) -> String {
        switch p {
        case "yesterday": return "FLOOR(\(c),1)=TODAY()-1"
        case "tomorrow": return "FLOOR(\(c),1)=TODAY()+1"
        case "last7Days": return "AND(TODAY()-FLOOR(\(c),1)&lt;=6,FLOOR(\(c),1)&lt;=TODAY())"
        case "thisMonth": return "AND(MONTH(\(c))=MONTH(TODAY()),YEAR(\(c))=YEAR(TODAY()))"
        default: return "FLOOR(\(c),1)=TODAY()"
        }
    }

    /// One more than the highest priority anywhere in the sheet's kept XML (extensions share the numbering).
    private func _nextCFPriority() -> Int {
        var top = 0
        for e in sheet.keptElements {
            var from = e.text.startIndex
            while let r = e.text.findRange(of: " priority=\"", in: from ..< e.text.endIndex) {
                if let end = e.text.findRange(of: "\"", in: r.upperBound ..< e.text.endIndex) {
                    top = max(top, Int(e.text[r.upperBound ..< end.lowerBound]) ?? 0)
                    from = end.upperBound
                } else { break }
            }
        }
        return top + 1
    }

    /// Append a look to the file's dxfs and return its index. Never removed, so undo and redo stay valid.
    func _appendDxf(_ d: DxfStyle) -> Int {
        var x = "<dxf>"
        if d.bold != nil || d.italic != nil || d.underline != nil || d.strike != nil || d.color != nil {
            x += "<font>"
            if let b = d.bold { x += b ? "<b/>" : "<b val=\"0\"/>" }
            if let i = d.italic { x += i ? "<i/>" : "<i val=\"0\"/>" }
            if let s = d.strike { x += s ? "<strike/>" : "<strike val=\"0\"/>" }
            if let u = d.underline { x += u ? "<u/>" : "<u val=\"none\"/>" }
            if let c = d.color { x += "<color rgb=\"FF\(Self._hex6(c))\"/>" }
            x += "</font>"
        }
        if let f = d.fill { x += "<fill><patternFill><bgColor rgb=\"FF\(Self._hex6(f))\"/></patternFill></fill>" }
        x += "</dxf>"
        let index = book.dxfs.count
        let cur = book.keptStyleParts["dxfs"] ?? "<dxfs count=\"0\"/>"
        var out: String
        if cur.hasSuffix("/>") {
            out = "<dxfs count=\"1\">" + x + "</dxfs>"
        } else if let end = cur.findRange(of: "</dxfs>", backwards: true) {
            out = cur
            out.replaceSubrange(end.lowerBound ..< end.lowerBound, with: x)
            if let a = out.findRange(of: " count=\""), let b = out.findRange(of: "\"", in: a.upperBound ..< out.endIndex) {
                out.replaceSubrange(a.upperBound ..< b.lowerBound, with: "\(index + 1)")
            }
        } else { out = "<dxfs count=\"1\">" + x + "</dxfs>" }
        book.keptStyleParts["dxfs"] = out
        book.dxfs.append(d)
        return index
    }
}
