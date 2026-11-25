// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// S-CH-1: a chart that came from a file keeps its own chart part when the user edits it. The edit changes only what
// the user touched (title, legend, data, type) in the part's XML; every other element (fonts, colours, axes,
// gridlines, labels, shapes) stays as the file wrote it. Only the data edit also needs a new embedded workbook, so
// PowerPoint's "Edit Data" opens what the chart shows.

import Foundation

enum ChartPartPatcher {
    struct Result {
        var xml: String
        /// The cells of the embedded workbook the data edit changed; the rest of the workbook is the user's.
        var writes: [CellWrite]
    }

    struct CellWrite {
        enum Value { case text(String), number(Double), empty }
        var sheet: String
        var row: Int
        var col: Int
        var value: Value
    }

    /// `data` (the chart's embedded workbook as the file wrote it) with `writes` made in it and nothing else
    /// touched: other sheets, formulas, formats and names go through the Sheets reader and writer. nil leaves
    /// the workbook as it was.
    static func apply(_ writes: [CellWrite], to data: Data) -> Data? {
        guard !writes.isEmpty, let book = try? Xlsx.read(data) else { return nil }
        for w in writes {
            guard let ws = book.sheets.first(where: { $0.name.lowercased() == w.sheet.lowercased() }) else { continue }
            let a = CellAddress(row: w.row, col: w.col)
            let style = ws.cells[a]?.style ?? 0
            switch w.value {
            case .text(let t): ws.cells[a] = Cell(input: t, value: .text(t), style: style)
            case .number(let n): ws.cells[a] = Cell(input: ChartXML.number(n), value: .number(n), style: style)
            case .empty: if style == 0 { ws.cells[a] = nil } else { ws.cells[a] = Cell(input: "", value: .empty, style: style) }
            }
        }
        return try? Xlsx.write(book)
    }

    /// The part `xml` with the differences between `old` (as read) and `new` applied; nil when nothing differs
    /// that this patcher knows, or the part cannot be patched (the caller then writes a chart of its own).
    static func patch(_ xml: String, old: Chart, new: Chart) -> Result? {
        guard let parsed = XNode.parse(Data(xml.utf8)) else { return nil }
        let space = ChartXML.canonical(parsed)
        guard space.name == "c:chartSpace", let chart = space.first("c:chart"), let plot = chart.first("c:plotArea") else { return nil }
        var writes: [CellWrite] = []
        let dataChanged = old.categories != new.categories || old.series.map(\.name) != new.series.map(\.name)
            || old.series.map(\.values) != new.series.map(\.values)
        if old.type != new.type {
            guard convert(plot, to: new) else { return nil }
        }
        if dataChanged {
            guard rewriteData(plot, new, covered: old.series.count, writes: &writes) else { return nil }
        }
        if old.title != new.title { setTitle(chart, new.title, base: space.first("c:txPr")?.descendant("a:defRPr")) }
        if old.legend != new.legend || old.legendPosition != new.legendPosition { setLegend(chart, plot, new) }
        return Result(xml: PptxXML.serialize(space), writes: writes)
    }

    // MARK: Title and legend

    static func setTitle(_ chart: XNode, _ title: String?, base: XNode? = nil) {
        let existing = chart.first("c:title")
        func flag(_ deleted: Bool) {
            if let f = chart.first("c:autoTitleDeleted") { f.attrs["val"] = deleted ? "1" : "0" }
            else {
                let i = chart.children.firstIndex { $0.name == "c:plotArea" } ?? chart.children.count
                chart.children.insert(XNode(name: "c:autoTitleDeleted", attrs: ["val": deleted ? "1" : "0"]), at: i)
            }
        }
        guard let title else {
            chart.children.removeAll { $0.name == "c:title" }
            flag(true)
            return
        }
        if let existing, let p = existing.descendant("a:p"), let run = p.first("a:r"), let t = run.first("a:t") {
            // The first run keeps its look; the words are the new ones, later runs go.
            t.text = title
            p.children.removeAll { $0.name == "a:r" && $0 !== run }
            for extra in existing.descendants("a:p").dropFirst() { extra.children.removeAll { $0.name == "a:r" } }
        } else {
            // No words yet: PowerPoint's own default look, in the chart's font; the title's other parts stay.
            let node = existing ?? XNode(name: "c:title", attrs: [:])
            let tx = XNode(name: "c:tx", attrs: [:]), rich = XNode(name: "c:rich", attrs: [:])
            let p = XNode(name: "a:p", attrs: [:]), r = XNode(name: "a:r", attrs: [:]), t = XNode(name: "a:t", attrs: [:])
            t.text = title
            let def = XNode(name: "a:defRPr", attrs: [:])
            if let own = node.first("c:txPr")?.descendant("a:defRPr") { def.attrs = own.attrs; def.children = own.children.map(copy) }
            else {
                def.attrs = ["sz": "1862", "b": "0", "i": "0", "u": "none", "strike": "noStrike", "kern": "1200", "baseline": "0"]
                let fill = XNode(name: "a:solidFill", attrs: [:]), clr = XNode(name: "a:schemeClr", attrs: ["val": "tx1"])
                clr.children = [XNode(name: "a:lumMod", attrs: ["val": "65000"]), XNode(name: "a:lumOff", attrs: ["val": "35000"])]
                fill.children = [clr]
                def.children = [fill]
                for face in ["a:latin", "a:ea", "a:cs"] { if let f = base?.first(face) { def.children.append(copy(f)) } }
            }
            let ppr = XNode(name: "a:pPr", attrs: [:]); ppr.children = [def]
            let rpr = XNode(name: "a:rPr", attrs: def.attrs); rpr.children = def.children.map(copy)
            r.children = [rpr, t]; p.children = [ppr, r]
            rich.children = [XNode(name: "a:bodyPr", attrs: [:]), XNode(name: "a:lstStyle", attrs: [:]), p]
            tx.children = [rich]
            node.children.removeAll { $0.name == "c:tx" }
            node.children.insert(tx, at: 0)
            if node.first("c:overlay") == nil {
                let at = node.children.firstIndex { ["c:spPr", "c:txPr", "c:extLst"].contains($0.name) } ?? node.children.count
                node.children.insert(XNode(name: "c:overlay", attrs: ["val": "0"]), at: at)
            }
            if existing == nil { chart.children.insert(node, at: 0) }
        }
        flag(false)
    }

    static func setLegend(_ chart: XNode, _ plot: XNode, _ new: Chart) {
        guard new.legend else { chart.children.removeAll { $0.name == "c:legend" }; return }
        if let legend = chart.first("c:legend") {
            if let pos = legend.first("c:legendPos") { pos.attrs["val"] = new.legendPosition }
            else { legend.children.insert(XNode(name: "c:legendPos", attrs: ["val": new.legendPosition]), at: 0) }
            return
        }
        let legend = XNode(name: "c:legend", attrs: [:])
        legend.children = [XNode(name: "c:legendPos", attrs: ["val": new.legendPosition]), XNode(name: "c:overlay", attrs: ["val": "0"])]
        let i = (chart.children.firstIndex { $0 === plot } ?? chart.children.count - 1) + 1
        chart.children.insert(legend, at: i)
    }

    // MARK: Data

    private static let groupNames: Set<String> = ["c:barChart", "c:lineChart", "c:areaChart", "c:pieChart", "c:doughnutChart",
                                                  "c:scatterChart", "c:radarChart", "c:bar3DChart", "c:line3DChart",
                                                  "c:area3DChart", "c:pie3DChart", "c:stockChart", "c:bubbleChart"]

    private static func groups(_ plot: XNode) -> [XNode] { plot.children.filter { groupNames.contains($0.name) } }

    private static func col(_ i: Int) -> String { ChartXML.column(i) }

    private static func ref(_ name: String, _ f: String, strings: [String], text: Bool) -> XNode {
        let node = XNode(name: name, attrs: [:])
        let fn = XNode(name: "c:f", attrs: [:]); fn.text = f
        let cacheName = text ? "c:strCache" : "c:numCache"
        let cache = XNode(name: cacheName, attrs: [:])
        if !text {
            let fc = XNode(name: "c:formatCode", attrs: [:]); fc.text = "General"
            cache.children.append(fc)
        }
        cache.children.append(XNode(name: "c:ptCount", attrs: ["val": "\(strings.count)"]))
        for (i, s) in strings.enumerated() where !(s.isEmpty && !text) {
            let pt = XNode(name: "c:pt", attrs: ["idx": "\(i)"]), v = XNode(name: "c:v", attrs: [:])
            v.text = s
            pt.children = [v]
            cache.children.append(pt)
        }
        node.children = [fn, cache]
        return node
    }

    /// Replaces (or inserts before `before`'s first present name) the child `name` of `ser`.
    private static func put(_ ser: XNode, _ name: String, _ node: XNode, before: [String]) {
        node.name = name
        if let i = ser.children.firstIndex(where: { $0.name == name }) { ser.children[i] = node; return }
        let at = ser.children.firstIndex { before.contains($0.name) } ?? ser.children.count
        ser.children.insert(node, at: at)
    }

    /// A reference "Sheet!$C$2:$C$5" read from a formula.
    struct Span {
        var sheetText: String
        var sheet: String
        var c0: Int, r0: Int, c1: Int, r1: Int
        init?(_ f: String) {
            guard let bang = f.lastIndex(of: "!") else { return nil }
            sheetText = String(f[..<bang])
            var name = sheetText
            if name.hasPrefix("'"), name.hasSuffix("'"), name.count >= 2 {
                name = String(name.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
            }
            sheet = name
            let cells = f[f.index(after: bang)...].split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            guard cells.count <= 2, let a = CellAddress(cells[0]), let z = cells.count == 2 ? CellAddress(cells[1]) : a else { return nil }
            c0 = a.col; r0 = a.row; c1 = z.col; r1 = z.row
        }
        init(sheetText: String, sheet: String, c0: Int, r0: Int, c1: Int, r1: Int) {
            self.sheetText = sheetText; self.sheet = sheet; self.c0 = c0; self.r0 = r0; self.c1 = c1; self.r1 = r1
        }
        var text: String {
            let first = "$\(ChartXML.column(c0))$\(r0 + 1)"
            return sheetText + "!" + (c0 == c1 && r0 == r1 ? first : first + ":$\(ChartXML.column(c1))$\(r1 + 1)")
        }
        var isRow: Bool { r0 == r1 && c1 > c0 }
        /// The same start with `n` cells, along its own direction (down for a single cell).
        func resized(_ n: Int) -> Span {
            var s = self
            if isRow { s.c1 = c0 + max(n, 1) - 1 } else { s.r1 = r0 + max(n, 1) - 1; s.c1 = c0 }
            return s
        }
        func cell(_ i: Int) -> (row: Int, col: Int) { isRow ? (r0, c0 + i) : (r0 + i, c0) }
        var count: Int { isRow ? c1 - c0 + 1 : r1 - r0 + 1 }
    }

    private static func span(_ ser: XNode, _ name: String) -> Span? {
        guard let f = ser.first(name)?.descendant("c:f")?.text else { return nil }
        return Span(f)
    }

    /// Where new series go: the columns after the chart's own, on the sheet its values live on.
    private struct Alloc {
        var sheetText: String
        var sheet: String
        var nextCol: Int
        var row0: Int
        var cat: Span?
    }

    /// Writes `values` into `sp` (a span resized to them), clearing the old span's cells past the new end.
    private static func write(_ values: [CellWrite.Value], old: Span?, into sp: Span, _ out: inout [CellWrite]) {
        for (i, v) in values.enumerated() {
            let c = sp.cell(i)
            out.append(CellWrite(sheet: sp.sheet, row: c.row, col: c.col, value: v))
        }
        if let old, old.sheet == sp.sheet, old.count > values.count {
            for i in values.count ..< old.count {
                let c = old.cell(i)
                out.append(CellWrite(sheet: old.sheet, row: c.row, col: c.col, value: .empty))
            }
        }
    }

    private static func literal(_ name: String, _ strings: [String], text: Bool) -> XNode {
        let node = XNode(name: name, attrs: [:])
        if !text {
            let fc = XNode(name: "c:formatCode", attrs: [:]); fc.text = "General"
            node.children.append(fc)
        }
        node.children.append(XNode(name: "c:ptCount", attrs: ["val": "\(strings.count)"]))
        for (i, s) in strings.enumerated() where !(s.isEmpty && !text) {
            let pt = XNode(name: "c:pt", attrs: ["idx": "\(i)"]), v = XNode(name: "c:v", attrs: [:])
            v.text = s
            pt.children = [v]
            node.children.append(pt)
        }
        return node
    }

    /// One series' name, categories and values rewritten in place: its own cells (resized to the new length) where
    /// it has them, new columns (`alloc`) where it has none; the cell changes go to `writes`.
    private static func fill(_ ser: XNode, index i: Int, _ c: Chart, scatter: Bool, alloc: inout Alloc, writes: inout [CellWrite]) {
        let n = c.categories.count
        let s = c.series[i]
        let vName = scatter ? "c:yVal" : "c:val", cName = scatter ? "c:xVal" : "c:cat"
        let oldVal = span(ser, vName), oldCat = span(ser, cName), oldTx = span(ser, "c:tx")
        let fmt = ser.first(vName)?.descendant("c:formatCode")?.text
        // Values.
        var valSpan = oldVal?.resized(n)
        if valSpan == nil, oldVal == nil, ser.first(vName) == nil || ser.first(vName)?.descendant("c:f") == nil, alloc.cat != nil {
            let col = alloc.nextCol; alloc.nextCol += 1
            valSpan = Span(sheetText: alloc.sheetText, sheet: alloc.sheet, c0: col, r0: alloc.row0, c1: col, r1: alloc.row0).resized(n)
        }
        let values = (0 ..< n).map { r in r < s.values.count ? s.values[r] : nil }
        let valStrings = values.map { $0.map { ChartXML.number($0) } ?? "" }
        let vNode = XNode(name: vName, attrs: [:])
        if let vs = valSpan {
            vNode.children = [ref("c:numRef", vs.text, strings: valStrings, text: false)]
            if let fmt { vNode.first("c:numRef")?.first("c:numCache")?.first("c:formatCode")?.text = fmt }
            write(values.map { $0.map { .number($0) } ?? .empty }, old: oldVal, into: vs, &writes)
        } else {
            vNode.children = [literal("c:numLit", valStrings, text: false)]
        }
        // Name: its own cell, else the one above the values, else literal text.
        // A series the file never named stays unnamed (PowerPoint numbers it by position), unless the user named it.
        let unnamed = ser.first("c:tx") == nil && s.name == "Series\(i + 1)"
        let tx = XNode(name: "c:tx", attrs: [:])
        var nameSpan = oldTx
        if nameSpan == nil, let vs = valSpan, oldVal == nil || oldTx != nil {
            if vs.isRow { if vs.c0 > 0 { nameSpan = Span(sheetText: vs.sheetText, sheet: vs.sheet, c0: vs.c0 - 1, r0: vs.r0, c1: vs.c0 - 1, r1: vs.r0) } }
            else if vs.r0 > 0 { nameSpan = Span(sheetText: vs.sheetText, sheet: vs.sheet, c0: vs.c0, r0: vs.r0 - 1, c1: vs.c0, r1: vs.r0 - 1) }
        }
        if let ns = nameSpan {
            tx.children = [ref("c:strRef", ns.text, strings: [s.name], text: true)]
            writes.append(CellWrite(sheet: ns.sheet, row: ns.r0, col: ns.c0, value: .text(s.name)))
        } else {
            let v = XNode(name: "c:v", attrs: [:]); v.text = s.name
            tx.children = [v]
        }
        if !unnamed {
            put(ser, "c:tx", tx, before: ["c:spPr", "c:invertIfNegative", "c:marker", "c:dPt", "c:dLbls", "c:trendline", "c:errBars",
                                          "c:cat", "c:val", "c:xVal", "c:yVal", "c:smooth"])
        }
        // Categories (or x values): shared by the series, so a new series reuses the first one's cells.
        let catSpan = (oldCat ?? alloc.cat)?.resized(n)
        let cNode = XNode(name: cName, attrs: [:])
        let catStrings = scatter ? c.categories.indices.map { ChartXML.number(c.x($0)) } : c.categories
        if let cs = catSpan {
            cNode.children = [ref(scatter ? "c:numRef" : "c:strRef", cs.text, strings: catStrings, text: !scatter)]
            if oldCat != nil || i == 0 {
                write(scatter ? c.categories.indices.map { .number(c.x($0)) } : c.categories.map { .text($0) }, old: oldCat, into: cs, &writes)
            }
        } else {
            cNode.children = [literal(scatter ? "c:numLit" : "c:strLit", catStrings, text: !scatter)]
        }
        put(ser, cName, cNode, before: scatter ? ["c:yVal", "c:smooth"] : ["c:val", "c:smooth"])
        put(ser, vName, vNode, before: ["c:smooth", "c:shape"])
        if alloc.cat == nil { alloc.cat = catSpan }
    }

    /// The series' name, categories and values as the file wrote them (a type change keeps the data and its cells).
    private static func carry(_ ser: XNode, from old: XNode, scatter: Bool) {
        if let tx = old.first("c:tx") { ser.children.append(copy(tx)) }
        let x = old.first("c:cat") ?? old.first("c:xVal"), y = old.first("c:val") ?? old.first("c:yVal")
        if let x { let n = copy(x); n.name = scatter ? "c:xVal" : "c:cat"; ser.children.append(n) }
        if let y { let n = copy(y); n.name = scatter ? "c:yVal" : "c:val"; ser.children.append(n) }
    }

    private static func copy(_ n: XNode) -> XNode {
        let c = XNode(name: n.name, attrs: n.attrs)
        c.text = n.text
        c.children = n.children.map(copy)
        return c
    }

    /// The same type, new data: each series keeps its own look; extra series are cloned from the last (without its
    /// colour, so the style's next one shows), fewer drop the last ones.
    private static func rewriteData(_ plot: XNode, _ c: Chart, covered: Int, writes: inout [CellWrite]) -> Bool {
        let gs = groups(plot)
        guard !gs.isEmpty, !gs.contains(where: { ["c:stockChart", "c:bubbleChart"].contains($0.name) }) else { return false }
        let wanted = c.type.isPie ? Array(c.series.prefix(1)) : c.series
        let scatter = c.type == .scatter
        var all: [(group: XNode, ser: XNode)] = []
        for g in gs { for s in g.all("c:ser") { all.append((g, s)) } }
        // Series the app did not read (a second chart group) are not its to rewrite: they stay as they are.
        let rest = covered > 0 && covered < all.count ? Array(all[covered...]) : []
        if !rest.isEmpty { all = Array(all[..<covered]) }
        guard let template = all.last else { return false }
        let vName = scatter ? "c:yVal" : "c:val"
        var alloc = Alloc(sheetText: "Sheet1", sheet: "Sheet1", nextCol: 1, row0: 1, cat: nil)
        if let tv = span(template.ser, vName) {
            alloc.sheetText = tv.sheetText; alloc.sheet = tv.sheet; alloc.row0 = tv.r0
            let spans = (all + rest).compactMap { span($0.ser, vName) }.filter { $0.sheet == tv.sheet }
            alloc.nextCol = (spans.map { max($0.c1, $0.c0) }.max() ?? tv.c1) + 1
            alloc.cat = span(template.ser, scatter ? "c:xVal" : "c:cat")
        }
        // Drop the extra ones.
        if all.count > wanted.count {
            for (g, s) in all[wanted.count...] { g.children.removeAll { $0 === s } }
            all = Array(all[..<wanted.count])
        }
        while all.count < wanted.count {
            let clone = copy(template.ser)
            clone.children.removeAll { ["c:spPr", "c:dPt", "c:dLbls", "c:trendline", "c:errBars", "c:marker", "c:extLst",
                                        "c:tx", "c:cat", "c:val", "c:xVal", "c:yVal"].contains($0.name) }
            var top = -1
            for g in groups(plot) { for e in g.all("c:ser") {
                top = max(top, Int(e.first("c:idx")?["val"] ?? "") ?? -1, Int(e.first("c:order")?["val"] ?? "") ?? -1)
            } }
            clone.first("c:idx")?.attrs["val"] = "\(top + 1)"
            clone.first("c:order")?.attrs["val"] = "\(top + 1)"
            let at = (template.group.children.lastIndex { $0.name == "c:ser" } ?? template.group.children.count - 1) + 1
            template.group.children.insert(clone, at: at)
            all.append((template.group, clone))
        }
        var shown = c
        shown.series = wanted
        for (i, e) in all.enumerated() { fill(e.ser, index: i, shown, scatter: scatter, alloc: &alloc, writes: &writes) }
        return true
    }

    // MARK: Type

    private static func node(_ name: String, _ attrs: [String: String] = [:]) -> XNode { XNode(name: name, attrs: attrs) }

    /// The first chart group becomes the new type's, its series rebuilt from `c` (their colours stay on a type that
    /// paints series alike); axes added or dropped as the type needs. Other groups of a combination chart stay.
    private static func convert(_ plot: XNode, to c: Chart) -> Bool {
        let gs = groups(plot)
        guard let group = gs.first, !gs.contains(where: { ["c:stockChart", "c:bubbleChart", "c:bar3DChart", "c:line3DChart",
                                                          "c:area3DChart", "c:pie3DChart"].contains($0.name) }) else { return false }
        // Old axes referenced by the group, to reuse when the new type has axes too.
        let oldAx = group.all("c:axId").compactMap { $0["val"] }
        let name: String
        switch c.type {
        case .column, .bar: name = "c:barChart"
        case .line: name = "c:lineChart"
        case .area: name = "c:areaChart"
        case .pie: name = "c:pieChart"
        case .doughnut: name = "c:doughnutChart"
        case .scatter: name = "c:scatterChart"
        case .radar: name = "c:radarChart"
        }
        let oldSers = group.all("c:ser")
        let wanted = c.type.isPie ? Array(c.series.prefix(1)) : c.series
        var shown = c; shown.series = wanted
        let keepsLook = !(c.type.isPie || group.name == "c:pieChart" || group.name == "c:doughnutChart" || c.type == .scatter || group.name == "c:scatterChart")
        // A pie shows one series, so the others have no cells of their own to carry over.
        guard oldSers.count >= wanted.count else { return false }
        var sers: [XNode] = []
        for i in wanted.indices {
            let ser = node("c:ser")
            ser.children = [node("c:idx", ["val": oldSers[i].first("c:idx")?["val"] ?? "\(i)"]),
                            node("c:order", ["val": oldSers[i].first("c:order")?["val"] ?? "\(i)"])]
            if keepsLook, i < oldSers.count, let sp = oldSers[i].first("c:spPr") {
                let spc = copy(sp)
                // A line type draws with the series' line, an area or bar with its fill.
                if c.type == .line || c.type == .radar, spc.first("a:ln") == nil, let fill = spc.first("a:solidFill") {
                    let ln = node("a:ln", ["w": "28575", "cap": "rnd"]); ln.children = [copy(fill), node("a:round")]
                    spc.children = [ln]
                }
                ser.children.append(spc)
            }
            carry(ser, from: oldSers[i], scatter: c.type == .scatter)
            if c.type == .line || c.type == .scatter { ser.children.append(node("c:smooth", ["val": "0"])) }
            sers.append(ser)
        }
        let g = node(name)
        func axIds() -> [XNode] { c.type.isPie ? [] : [node("c:axId", ["val": oldAx.first ?? "111111111"]), node("c:axId", ["val": oldAx.dropFirst().first ?? "222222222"])] }
        switch c.type {
        case .column, .bar:
            g.children = [node("c:barDir", ["val": c.type == .bar ? "bar" : "col"]), node("c:grouping", ["val": "clustered"]),
                          node("c:varyColors", ["val": "0"])] + sers + [node("c:gapWidth", ["val": "219"])] + axIds()
        case .line:
            g.children = [node("c:grouping", ["val": "standard"]), node("c:varyColors", ["val": "0"])] + sers + [node("c:marker", ["val": "1"])] + axIds()
        case .area:
            g.children = [node("c:grouping", ["val": "standard"]), node("c:varyColors", ["val": "0"])] + sers + axIds()
        case .pie:
            g.children = [node("c:varyColors", ["val": "1"])] + sers + [node("c:firstSliceAng", ["val": "0"])]
        case .doughnut:
            g.children = [node("c:varyColors", ["val": "1"])] + sers + [node("c:firstSliceAng", ["val": "0"]), node("c:holeSize", ["val": "50"])]
        case .scatter:
            g.children = [node("c:scatterStyle", ["val": "lineMarker"]), node("c:varyColors", ["val": "0"])] + sers + axIds()
        case .radar:
            g.children = [node("c:radarStyle", ["val": "marker"]), node("c:varyColors", ["val": "0"])] + sers + axIds()
        }
        guard let at = plot.children.firstIndex(where: { $0 === group }) else { return false }
        plot.children[at] = g
        // Axes: drop for a pie; for a type that needs them and the plot lacks them, add the usual pair.
        let hasAxes = plot.children.contains { ["c:catAx", "c:valAx", "c:dateAx", "c:serAx"].contains($0.name) }
        if c.type.isPie {
            if gs.count == 1 { plot.children.removeAll { ["c:catAx", "c:valAx", "c:dateAx", "c:serAx"].contains($0.name) } }
        } else if !hasAxes {
            let a = "111111111", b = "222222222"
            let cat = c.type == .scatter ? node("c:valAx") : node("c:catAx")
            cat.children = [node("c:axId", ["val": a]), node("c:scaling"), node("c:delete", ["val": "0"]),
                            node("c:axPos", ["val": c.type == .bar ? "l" : "b"]), node("c:crossAx", ["val": b])]
            cat.children[1].children = [node("c:orientation", ["val": "minMax"])]
            let val = node("c:valAx")
            val.children = [node("c:axId", ["val": b]), node("c:scaling"), node("c:delete", ["val": "0"]),
                            node("c:axPos", ["val": c.type == .bar ? "b" : "l"]), node("c:majorGridlines"), node("c:crossAx", ["val": a])]
            val.children[1].children = [node("c:orientation", ["val": "minMax"])]
            let i = (plot.children.lastIndex { groupNames.contains($0.name) } ?? 0) + 1
            plot.children.insert(contentsOf: [cat, val], at: i)
        }
        // A bar chart's category axis stands at the left, its value axis at the bottom (and the other way for a column).
        if c.type == .bar || c.type == .column {
            let own = Set(g.all("c:axId").compactMap { $0["val"] })
            for ax in plot.children where (ax.name == "c:catAx" || ax.name == "c:valAx") && own.contains(ax.first("c:axId")?["val"] ?? "") {
                if let pos = ax.first("c:axPos") {
                    let vertical = (ax.name == "c:catAx") == (c.type == .bar)
                    pos.attrs["val"] = vertical ? "l" : "b"
                }
            }
        }
        return true
    }
}
