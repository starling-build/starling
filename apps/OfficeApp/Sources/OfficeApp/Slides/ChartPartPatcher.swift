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
            guard ChartPartType.convert(plot, to: new) else { return nil }
        }
        // Clustered, stacked or 100% stacked (the conversion above writes a plain grouping).
        if (old.type != new.type && (new.stacked || new.percent)) || old.stacked != new.stacked || old.percent != new.percent {
            guard grouping(plot, stacked: new.stacked, percent: new.percent) else { return nil }
        }
        if old.valueGrid != new.valueGrid { valueGrid(plot, new.valueGrid) }
        if old.gapWidth != new.gapWidth || old.overlap != new.overlap { spacing(plot, new) }
        // Labels set series by series (a Quick Layout's size, position, or labels on one series only).
        let perSeries = old.series.count == new.series.count && zip(old.series, new.series).contains {
            $0.labelsShown != $1.labelsShown || $0.labelPos != $1.labelPos || $0.labelSize != $1.labelSize
        }
        if perSeries { seriesLabels(plot, new) }
        if dataChanged {
            guard rewriteData(plot, new, covered: old.series.count, writes: &writes) else { return nil }
        }
        // Title and legend: the shared patches (Charts/ChartPartPatch) on the part's text.
        var out = PptxXML.serialize(space)
        if old.title != new.title { out = ChartPartPatch.title(out, new.title.map { .set($0) } ?? .remove, style: .powerPoint) }
        if old.legend != new.legend || old.legendPosition != new.legendPosition {
            out = ChartPartPatch.legend(out, new.legend ? .set(new.legendPosition) : .remove)
        }
        if old.dataLabels != new.dataLabels && !perSeries { out = ChartPartPatch.labels(out, ChartLabelEdit(show: new.dataLabels)) }
        if old.valueAxisTitle != new.valueAxisTitle {
            out = ChartPartPatch.axisTitle(out, .value, new.valueAxisTitle.map { .set($0) } ?? .remove)
        }
        if old.categoryAxisTitle != new.categoryAxisTitle {
            out = ChartPartPatch.axisTitle(out, .category, new.categoryAxisTitle.map { .set($0) } ?? .remove)
        }
        return Result(xml: out, writes: writes)
    }

    /// The first chart group's `c:grouping` set to clustered (standard), stacked or 100% stacked. A bar or column group
    /// stacks its bars on one another with `c:overlap` 100, as Office writes it, and a clustered one loses the overlap.
    /// false where the group has no grouping to set (pie, scatter, radar).
    static func grouping(_ plot: XNode, stacked: Bool, percent: Bool) -> Bool {
        guard let group = ChartPartType.groups(plot).first,
              ["c:barChart", "c:lineChart", "c:areaChart"].contains(group.name) else { return !stacked && !percent }
        let bar = group.name == "c:barChart"
        let val = percent ? "percentStacked" : stacked ? "stacked" : (bar ? "clustered" : "standard")
        if let g = group.first("c:grouping") { g.attrs["val"] = val } else {
            let at = (group.children.firstIndex { $0.name == "c:barDir" }).map { $0 + 1 } ?? 0
            group.children.insert(ChartPartType.node("c:grouping", ["val": val]), at: at)
        }
        guard bar else { return true }
        group.children.removeAll { $0.name == "c:overlap" }
        if stacked || percent {
            let at = (group.children.firstIndex { $0.name == "c:gapWidth" }).map { $0 + 1 }
                ?? group.children.firstIndex { ["c:serLines", "c:axId", "c:extLst"].contains($0.name) } ?? group.children.count
            group.children.insert(ChartPartType.node("c:overlap", ["val": "100"]), at: at)
        }
        return true
    }

    /// The value axis' major gridlines added (bare, as Office writes a new one: the theme draws them) or removed.
    static func valueGrid(_ plot: XNode, _ on: Bool) {
        for ax in plot.children where ax.name == "c:valAx" {
            if !on { ax.children.removeAll { $0.name == "c:majorGridlines" }; continue }
            guard ax.first("c:majorGridlines") == nil else { continue }
            let at = (ax.children.firstIndex { $0.name == "c:axPos" }).map { $0 + 1 } ?? ax.children.count
            ax.children.insert(ChartPartType.node("c:majorGridlines", [:]), at: at)
        }
    }

    /// A bar or column group's gap width and overlap as `c` has them (an overlap of 0 is left out, as Word writes it).
    static func spacing(_ plot: XNode, _ c: Chart) {
        guard let group = ChartPartType.groups(plot).first, group.name == "c:barChart" else { return }
        let gap = c.gapWidth ?? (c.stacked ? 150 : 219), overlap = c.overlap ?? (c.stacked ? 100 : -27)
        group.children.removeAll { $0.name == "c:gapWidth" || $0.name == "c:overlap" }
        var at = group.children.firstIndex { ["c:serLines", "c:axId", "c:extLst"].contains($0.name) } ?? group.children.count
        group.children.insert(ChartPartType.node("c:gapWidth", ["val": String(gap)]), at: at)
        at += 1
        if overlap != 0 { group.children.insert(ChartPartType.node("c:overlap", ["val": String(overlap)]), at: at) }
    }

    /// Each series' own labels as `c` has them: shown with its position and size (the text as Word's chart style writes
    /// it), or deleted where other series show theirs; the number format and fill a series' labels had stay. The group's
    /// own `c:dLbls` goes, every series saying for itself.
    static func seriesLabels(_ plot: XNode, _ c: Chart) {
        guard let group = ChartPartType.groups(plot).first else { return }
        let n = ChartPartType.node
        func val(_ name: String, _ v: String) -> XNode { n(name, ["val": v]) }
        for (k, ser) in group.all("c:ser").enumerated() where k < c.series.count {
            let s = c.series[k], old = ser.first("c:dLbls")
            ser.children.removeAll { $0.name == "c:dLbls" }
            guard c.dataLabels else { continue }
            let d = n("c:dLbls", [:])
            if s.labelsShown {
                d.children += [old?.first("c:numFmt"), old?.first("c:spPr")].compactMap { $0 }
                if let size = s.labelSize {
                    let run = n("a:defRPr", ["sz": String(Int((size * 100).rounded())), "b": "0", "i": "0", "u": "none",
                                             "strike": "noStrike", "kern": "1200", "baseline": "0"])
                    let scheme = n("a:schemeClr", ["val": "tx1"])
                    scheme.children = [val("a:lumMod", "75000"), val("a:lumOff", "25000")]
                    let fill = n("a:solidFill", [:]); fill.children = [scheme]
                    run.children = [fill, n("a:latin", ["typeface": "+mn-lt"]), n("a:ea", ["typeface": "+mn-ea"]), n("a:cs", ["typeface": "+mn-cs"])]
                    let pPr = n("a:pPr", [:]); pPr.children = [run]
                    let para = n("a:p", [:]); para.children = [pPr, n("a:endParaRPr", ["lang": "en-US"])]
                    let tx = n("c:txPr", [:]); tx.children = [n("a:bodyPr", [:]), n("a:lstStyle", [:]), para]
                    d.children.append(tx)
                } else if let t = old?.first("c:txPr") { d.children.append(t) }
                if let pos = s.labelPos { d.children.append(val("c:dLblPos", pos)) }
                d.children += [val("c:showLegendKey", "0"), val("c:showVal", "1"), val("c:showCatName", "0"), val("c:showSerName", "0"),
                               val("c:showPercent", "0"), val("c:showBubbleSize", "0")]
            } else {
                d.children = [val("c:delete", "1")]
            }
            put(ser, "c:dLbls", d, before: ["c:trendline", "c:errBars", "c:cat", "c:val", "c:xVal", "c:yVal", "c:smooth", "c:shape", "c:extLst"])
        }
        group.children.removeAll { $0.name == "c:dLbls" }
    }

    // MARK: Data



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
                name = String(name.dropFirst().dropLast()).replacingAll("''", with: "'")
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
        // A multi-level category axis keeps its levels: the names are its inner level (the last column of its cells, or the
        // last row where the categories run across), the outer levels stay as they are, cut to the new count.
        if !scatter, let multi = ser.first("c:cat")?.first("c:multiLvlStrRef"), let f = multi.first("c:f"), let sp = Span(f.text),
           let cache = multi.first("c:multiLvlStrCache") {
            let oldCount = cache.first("c:ptCount")?["val"].flatMap(Int.init) ?? (sp.r1 - sp.r0 + 1)
            let down = sp.r1 - sp.r0 + 1 == oldCount || sp.c1 - sp.c0 + 1 != oldCount
            var ns = sp
            if down { ns.r1 = sp.r0 + max(n, 1) - 1 } else { ns.c1 = sp.c0 + max(n, 1) - 1 }
            f.text = ns.text
            cache.first("c:ptCount")?.attrs["val"] = "\(n)"
            for (k, lvl) in cache.all("c:lvl").enumerated() {
                if k == 0 {
                    lvl.children = lvl.children.filter { $0.name != "c:pt" }
                    for (j, name) in c.categories.enumerated() {
                        let pt = XNode(name: "c:pt", attrs: ["idx": "\(j)"]), v = XNode(name: "c:v", attrs: [:])
                        v.text = name
                        pt.children = [v]
                        lvl.children.append(pt)
                    }
                } else {
                    lvl.children = lvl.children.filter { $0.name != "c:pt" || ($0["idx"].flatMap(Int.init) ?? 0) < n }
                }
            }
            let inner = down ? Span(sheetText: sp.sheetText, sheet: sp.sheet, c0: sp.c1, r0: sp.r0, c1: sp.c1, r1: sp.r0 + max(n, 1) - 1)
                             : Span(sheetText: sp.sheetText, sheet: sp.sheet, c0: sp.c0, r0: sp.r1, c1: sp.c0 + max(n, 1) - 1, r1: sp.r1)
            let oldInner = down ? Span(sheetText: sp.sheetText, sheet: sp.sheet, c0: sp.c1, r0: sp.r0, c1: sp.c1, r1: sp.r1)
                                : Span(sheetText: sp.sheetText, sheet: sp.sheet, c0: sp.c0, r0: sp.r1, c1: sp.c1, r1: sp.r1)
            write(c.categories.map { .text($0) }, old: oldInner, into: inner, &writes)
            put(ser, vName, vNode, before: ["c:smooth", "c:shape"])
            if alloc.cat == nil { alloc.cat = inner }
            return
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


    /// The same type, new data: each series keeps its own look; extra series are cloned from the last (without its
    /// colour, so the style's next one shows), fewer drop the last ones.
    private static func rewriteData(_ plot: XNode, _ c: Chart, covered: Int, writes: inout [CellWrite]) -> Bool {
        let gs = ChartPartType.groups(plot)
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
            let clone = ChartPartType.copy(template.ser)
            clone.children.removeAll { ["c:spPr", "c:dPt", "c:dLbls", "c:trendline", "c:errBars", "c:marker", "c:extLst",
                                        "c:tx", "c:cat", "c:val", "c:xVal", "c:yVal"].contains($0.name) }
            var top = -1
            for g in ChartPartType.groups(plot) { for e in g.all("c:ser") {
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

}
