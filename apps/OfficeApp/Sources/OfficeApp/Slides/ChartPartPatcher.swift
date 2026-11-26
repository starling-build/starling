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
        if dataChanged {
            guard rewriteData(plot, new, covered: old.series.count, writes: &writes) else { return nil }
        }
        // Title and legend: the shared patches (Charts/ChartPartPatch) on the part's text.
        var out = PptxXML.serialize(space)
        if old.title != new.title { out = ChartPartPatch.title(out, new.title.map { .set($0) } ?? .remove, style: .powerPoint) }
        if old.legend != new.legend || old.legendPosition != new.legendPosition {
            out = ChartPartPatch.legend(out, new.legend ? .set(new.legendPosition) : .remove)
        }
        return Result(xml: out, writes: writes)
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
