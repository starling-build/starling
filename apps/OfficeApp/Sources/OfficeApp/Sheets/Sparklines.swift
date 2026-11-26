// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Sparklines: a tiny line, column or win/loss chart that lives in one cell.
// Excel keeps them in the sheet's extLst, in an x14:sparklineGroups ext. A
// group has the look (type, colours, which points are marked) and a list of
// sparklines: each a data range and the one cell that shows it.
//
// The sheet's extLst is kept as text (Worksheet.keptElements). Only the
// sparkline ext is rewritten here; every other ext stays as it was.

import Flutter
import FlutterSwiftBridge
import Foundation
import OfficeText

struct SparklineGroup: Equatable {
    enum Kind: String { case line, column, winLoss = "stacked" }

    /// Every attribute of x14:sparklineGroup as the file had it, so the ones
    /// not modelled here (rightToLeft, dateAxis...) go back unchanged.
    var attrs: [String: String] = [:]
    /// The x14:color* children in order: (local name, attributes).
    var colors: [(name: String, attrs: [String: String])] = []
    /// The group's date axis range, when it has one (an xm:f beside the colours).
    var dateAxis: String? = nil
    /// Data range text (as `Sheet1!A1:E1`) and the cell that shows it.
    var items: [(f: String, cell: CellAddress)] = []

    static func == (a: SparklineGroup, b: SparklineGroup) -> Bool {
        a.attrs == b.attrs && a.dateAxis == b.dateAxis
            && a.colors.count == b.colors.count && zip(a.colors, b.colors).allSatisfy { $0.name == $1.name && $0.attrs == $1.attrs }
            && a.items.count == b.items.count && zip(a.items, b.items).allSatisfy { $0.f == $1.f && $0.cell == $1.cell }
    }

    var kind: Kind {
        get { Kind(rawValue: attrs["type"] ?? "") ?? .line }
        set { if newValue == .line { attrs["type"] = nil } else { attrs["type"] = newValue.rawValue } }
    }
    func flag(_ k: String) -> Bool { attrs[k] == "1" || attrs[k] == "true" }
    mutating func set(_ k: String, _ on: Bool) { attrs[k] = on ? "1" : nil }
    var lineWeight: Double {
        get { attrs["lineWeight"].flatMap { Double($0) } ?? 0.75 }
        set { attrs["lineWeight"] = newValue == 0.75 ? nil : Sparklines.num(newValue) }
    }
    /// "gap" (the default), "zero" or "span".
    var emptyAs: String {
        get { attrs["displayEmptyCellsAs"] ?? "zero" }
        set { attrs["displayEmptyCellsAs"] = newValue }
    }
    /// "individual" (default), "group" or "custom".
    var minType: String { attrs["minAxisType"] ?? "individual" }
    var maxType: String { attrs["maxAxisType"] ?? "individual" }
    var manualMin: Double? { attrs["manualMin"].flatMap { Double($0) } }
    var manualMax: Double? { attrs["manualMax"].flatMap { Double($0) } }

    func color(_ name: String) -> [String: String]? { colors.first { $0.name == name }?.attrs }
    mutating func setColor(_ name: String, rgb: UInt32) {
        let a = ["rgb": "FF" + Sparklines.hex6(rgb)]
        if let i = colors.firstIndex(where: { $0.name == name }) { colors[i].attrs = a } else { colors.append((name, a)) }
    }

    /// Excel's own starting look for a new group.
    static func new(kind: Kind) -> SparklineGroup {
        var g = SparklineGroup()
        g.kind = kind
        g.attrs["displayEmptyCellsAs"] = "gap"
        g.colors = [
            ("colorSeries", ["theme": "4", "tint": "-0.499984740745262"]),
            ("colorNegative", ["theme": "5"]),
            ("colorAxis", ["rgb": "FF000000"]),
            ("colorMarkers", ["theme": "4", "tint": "-0.499984740745262"]),
            ("colorFirst", ["theme": "4", "tint": "0.39997558519241921"]),
            ("colorLast", ["theme": "4", "tint": "0.39997558519241921"]),
            ("colorHigh", ["theme": "4"]),
            ("colorLow", ["theme": "4"]),
        ]
        return g
    }
}

enum Sparklines {
    static let uri = "{05C60535-1F16-4fd2-B633-F4F36F0B64E0}"
    static let x14 = "http://schemas.microsoft.com/office/spreadsheetml/2009/9/main"
    static let xm = "http://schemas.microsoft.com/office/excel/2006/main"
    static let colorOrder = ["colorSeries", "colorNegative", "colorAxis", "colorMarkers", "colorFirst", "colorLast", "colorHigh", "colorLow"]
    /// Attributes in the order Excel writes them.
    static let attrOrder = ["manualMax", "manualMin", "lineWeight", "type", "dateAxis", "displayEmptyCellsAs", "markers", "high", "low",
                            "first", "last", "negative", "displayXAxis", "displayHidden", "minAxisType", "maxAxisType", "rightToLeft"]

    static func defaultColor(_ name: String) -> [String: String] {
        switch name {
        case "colorNegative": return ["theme": "5"]
        case "colorAxis": return ["rgb": "FF000000"]
        case "colorFirst", "colorLast": return ["theme": "4", "tint": "0.39997558519241921"]
        case "colorHigh", "colorLow": return ["theme": "4"]
        default: return ["theme": "4", "tint": "-0.499984740745262"]
        }
    }

    static func num(_ d: Double) -> String {
        if d == d.rounded(), abs(d) < 1e15 { return String(Int64(d)) }
        return "\(d)"
    }
    static func hex6(_ v: UInt32) -> String {
        let digits = Array("0123456789ABCDEF")
        var s = ""
        for shift in stride(from: 20, through: 0, by: -4) { s.append(digits[Int((v >> UInt32(shift)) & 0xF)]) }
        return s
    }

    // MARK: Reading

    /// The sparkline groups in a sheet's kept extLst text.
    static func groups(inExtLst text: String?) -> [SparklineGroup] {
        guard let text, text.containsSubstring("sparklineGroup"),
              let root = XNode.parse(Data(text.utf8)) else { return [] }
        var out: [SparklineGroup] = []
        for ext in root.kids("ext") where ext["uri"]?.uppercased() == uri.uppercased() {
            for gs in ext.kids("sparklineGroups") { for gn in gs.kids("sparklineGroup") { out.append(_group(gn)) } }
        }
        return out
    }

    private static func _local(_ s: String) -> String { s.split(separator: ":").last.map(String.init) ?? s }

    private static func _group(_ n: XNode) -> SparklineGroup {
        var g = SparklineGroup()
        for (k, v) in n.attrs where !k.hasPrefix("xmlns") { g.attrs[_local(k)] = v }
        for c in n.children {
            let name = _local(c.name)
            if name.hasPrefix("color") {
                var a: [String: String] = [:]
                for (k, v) in c.attrs { a[_local(k)] = v }
                g.colors.append((name, a))
            } else if name == "f" { g.dateAxis = c.text }
        }
        if let list = n.child("sparklines") {
            for s in list.kids("sparkline") {
                guard let f = s.child("f")?.text, let sq = s.child("sqref")?.text,
                      let cell = CellAddress(sq.sparkTrim) else { continue }
                g.items.append((f.sparkTrim, cell))
            }
        }
        return g
    }

    // MARK: Writing

    static func xml(_ groups: [SparklineGroup]) -> String {
        var s = "<ext uri=\"\(uri)\" xmlns:x14=\"\(x14)\"><x14:sparklineGroups xmlns:xm=\"\(xm)\">"
        for g in groups {
            s += "<x14:sparklineGroup"
            for k in attrOrder { if let v = g.attrs[k] { s += " \(k)=\"\(esc(v))\"" } }
            for k in g.attrs.keys.sorted() where !attrOrder.contains(k) { s += " \(k)=\"\(esc(g.attrs[k] ?? ""))\"" }
            s += ">"
            let known = colorOrder.compactMap { n in g.colors.first { $0.name == n } }
            let other = g.colors.filter { !colorOrder.contains($0.name) }
            for c in known + other {
                s += "<x14:\(c.name)"
                for k in c.attrs.keys.sorted() { s += " \(k)=\"\(esc(c.attrs[k] ?? ""))\"" }
                s += "/>"
            }
            if let d = g.dateAxis { s += "<xm:f>\(esc(d))</xm:f>" }
            s += "<x14:sparklines>"
            for it in g.items { s += "<x14:sparkline><xm:f>\(esc(it.f))</xm:f><xm:sqref>\(it.cell.a1)</xm:sqref></x14:sparkline>" }
            s += "</x14:sparklines></x14:sparklineGroup>"
        }
        return s + "</x14:sparklineGroups></ext>"
    }

    private static func esc(_ t: String) -> String {
        var o = ""
        for ch in t {
            switch ch {
            case "&": o += "&amp;"
            case "<": o += "&lt;"
            case ">": o += "&gt;"
            case "\"": o += "&quot;"
            default: o.append(ch)
            }
        }
        return o
    }

    /// The extLst text with its sparkline ext replaced by `groups` (dropped
    /// when there are none; the other exts untouched). nil when nothing is left.
    static func extLst(replacing old: String?, with groups: [SparklineGroup]) -> String? {
        var exts: [String] = []
        var at = -1
        if let old {
            var rest = old
            while let open = rest.rangeOfSubstring("<ext "), let close = rest.rangeOfSubstring("</ext>", in: open.upperBound ..< rest.endIndex) {
                let ext = String(rest[open.lowerBound ..< close.upperBound])
                if ext.containsSubstring(uri) || ext.containsSubstring(uri.lowercased()) { if at < 0 { at = exts.count } } else { exts.append(ext) }
                rest = String(rest[close.upperBound...])
            }
        }
        if !groups.isEmpty { exts.insert(xml(groups), at: at < 0 ? exts.count : min(at, exts.count)) }
        return exts.isEmpty ? nil : "<extLst>" + exts.joined() + "</extLst>"
    }

    /// The extLst text less any sparkline ext that holds no group; nil when
    /// nothing is left. Excel refuses a sheet whose x14:sparklineGroups is
    /// empty (0x800A03EC, repair or not), so a save never writes one, even
    /// when the file came with it.
    static func withoutEmptySparklineExt(_ text: String) -> String? {
        guard text.containsSubstring("sparklineGroups") else { return text }
        var t = text, from = t.startIndex
        while let open = t.findRange(of: "<ext ", in: from ..< t.endIndex), let close = t.findRange(of: "</ext>", in: open.upperBound ..< t.endIndex) {
            let ext = String(t[open.lowerBound ..< close.upperBound])
            if ext.containsSubstring("sparklineGroups"), !ext.containsSubstring("sparklineGroup "), !ext.containsSubstring("sparklineGroup>") {
                t.removeSubrange(open.lowerBound ..< close.upperBound); from = open.lowerBound
            } else { from = close.upperBound }
        }
        return t.containsSubstring("<ext ") ? t : nil
    }

    // MARK: Drawing

    enum Shape {
        case line([Offset], weight: Double)
        case dot(Offset, role: String)
        case bar(Rect, role: String)
        case axis(y: Double)
    }

    /// What one sparkline draws, in the cell's own coordinates (0,0 top left).
    /// `values` has nil for a cell with no number; `lo`/`hi` are the vertical
    /// range (the sparkline's own, or the group's, or the user's).
    static func layout(_ g: SparklineGroup, values: [Double?], lo: Double, hi: Double, width: Double, height: Double) -> [Shape] {
        let padX = min(4.0, width * 0.1), padY = min(4.0, height * 0.15)
        let x0 = padX, x1 = width - padX, y0 = padY, y1 = height - padY
        guard x1 > x0, y1 > y0, !values.isEmpty else { return [] }
        let n = values.count
        // The vertical range: a column or win/loss always includes zero.
        var lo = lo, hi = hi
        if g.kind != .line { lo = min(lo, 0); hi = max(hi, 0) }
        if hi == lo { hi += 1; lo -= 1 }
        func y(_ v: Double) -> Double { y1 - (v - lo) / (hi - lo) * (y1 - y0) }
        var shapes: [Shape] = []
        let nums = values.compactMap { $0 }
        let hiV = nums.max(), loV = nums.min()
        let firstI = values.firstIndex { $0 != nil }, lastI = values.lastIndex { $0 != nil }
        func role(_ i: Int, _ v: Double) -> String? {
            if g.flag("high"), v == hiV, i == values.firstIndex(where: { $0 == hiV }) { return "colorHigh" }
            if g.flag("low"), v == loV, i == values.firstIndex(where: { $0 == loV }) { return "colorLow" }
            if g.flag("first"), i == firstI { return "colorFirst" }
            if g.flag("last"), i == lastI { return "colorLast" }
            if g.flag("negative"), v < 0 { return "colorNegative" }
            return nil
        }
        if g.flag("displayXAxis"), g.kind != .winLoss, lo < 0, hi > 0 { shapes.append(.axis(y: y(0))) }
        switch g.kind {
        case .line:
            let step = n > 1 ? (x1 - x0) / Double(n - 1) : 0
            func px(_ i: Int) -> Double { n > 1 ? x0 + step * Double(i) : (x0 + x1) / 2 }
            // Runs of points: a gap breaks the line, "zero" counts it as 0, "span" joins across it.
            var runs: [[Offset]] = [[]]
            for (i, v) in values.enumerated() {
                if let v { runs[runs.count - 1].append(Offset(px(i), y(v))) }
                else if g.emptyAs == "zero" { runs[runs.count - 1].append(Offset(px(i), y(0))) }
                else if g.emptyAs != "span", !runs[runs.count - 1].isEmpty { runs.append([]) }
            }
            for r in runs where r.count > 1 { shapes.append(.line(r, weight: g.lineWeight)) }
            for (i, v) in values.enumerated() {
                guard let v else { continue }
                if let r = role(i, v) { shapes.append(.dot(Offset(px(i), y(v)), role: r)) }
                else if g.flag("markers") { shapes.append(.dot(Offset(px(i), y(v)), role: "colorMarkers")) }
            }
        case .column:
            let slot = (x1 - x0) / Double(n), w = max(1, slot * 0.7)
            let base = y(0)
            for (i, v) in values.enumerated() {
                let v = v ?? (g.emptyAs == "zero" ? 0 : nil)
                guard let v else { continue }
                let cx = x0 + slot * (Double(i) + 0.5)
                let top = y(v)
                // (A zero or the smallest bar still shows a hair of colour.)
                let r = Rect.fromLTRB(cx - w / 2, min(top, base), cx + w / 2, max(top, base) + (top == base ? 1 : 0))
                shapes.append(.bar(r, role: role(i, v) ?? "colorSeries"))
            }
        case .winLoss:
            let slot = (x1 - x0) / Double(n), w = max(1, slot * 0.7)
            let mid = (y0 + y1) / 2, half = (y1 - y0) * 0.45
            for (i, v) in values.enumerated() {
                guard let v, v != 0 else { continue }
                let cx = x0 + slot * (Double(i) + 0.5)
                let r = v > 0 ? Rect.fromLTRB(cx - w / 2, mid - half, cx + w / 2, mid - 0.5)
                              : Rect.fromLTRB(cx - w / 2, mid + 0.5, cx + w / 2, mid + half)
                shapes.append(.bar(r, role: role(i, v) ?? (v < 0 && g.flag("negative") ? "colorNegative" : "colorSeries")))
            }
        }
        return shapes
    }
}

extension Sparklines {
    static func paint(_ look: SparkLook, _ canvas: any Canvas, in r: Rect, zoom: Double) {
        let shapes = layout(look.group, values: look.values, lo: look.lo, hi: look.hi, width: r.width / zoom, height: r.height / zoom)
        let p = Paint()
        func color(_ role: String) -> Color { Color(Int64(0xFF00_0000) | Int64(look.colors[role] ?? 0x376092)) }
        func pt(_ o: Offset) -> Offset { Offset(r.left + o.dx * zoom, r.top + o.dy * zoom) }
        for s in shapes {
            switch s {
            case .axis(let y):
                p.style = .stroke; p.strokeWidth = 1; p.color = color("colorAxis")
                canvas.drawLine(Offset(r.left + 2 * zoom, r.top + y * zoom), Offset(r.right - 2 * zoom, r.top + y * zoom), p)
            case .line(let pts, let weight):
                let path = Path()
                for (i, q) in pts.enumerated() { let o = pt(q); if i == 0 { path.moveTo(o.dx, o.dy) } else { path.lineTo(o.dx, o.dy) } }
                p.style = .stroke; p.strokeWidth = max(1, weight * 4 / 3 * zoom); p.color = color("colorSeries")
                canvas.drawPath(path, p)
            case .dot(let c, let role):
                p.style = .fill; p.color = color(role)
                canvas.drawCircle(pt(c), 2.2 * zoom, p)
            case .bar(let b, let role):
                p.style = .fill; p.color = color(role)
                canvas.drawRect(Rect.fromLTRB(r.left + b.left * zoom, r.top + b.top * zoom, r.left + b.right * zoom, r.top + b.bottom * zoom), p)
            }
        }
    }
}

private extension String {
    var sparkTrim: String {
        var s = Substring(self)
        while let c = s.first, c == " " || c == "\n" || c == "\t" || c == "\r" { s = s.dropFirst() }
        while let c = s.last, c == " " || c == "\n" || c == "\t" || c == "\r" { s = s.dropLast() }
        return String(s)
    }
}
