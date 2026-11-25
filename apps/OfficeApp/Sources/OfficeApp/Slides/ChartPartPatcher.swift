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
        /// The data changed: the embedded workbook must be rebuilt to match the chart's new formulas.
        var workbook: Bool
    }

    /// The part `xml` with the differences between `old` (as read) and `new` applied; nil when nothing differs
    /// that this patcher knows, or the part cannot be patched (the caller then writes a chart of its own).
    static func patch(_ xml: String, old: Chart, new: Chart) -> Result? {
        guard let parsed = XNode.parse(Data(xml.utf8)) else { return nil }
        let space = ChartXML.canonical(parsed)
        guard space.name == "c:chartSpace", let chart = space.first("c:chart"), let plot = chart.first("c:plotArea") else { return nil }
        var workbook = false
        let dataChanged = old.categories != new.categories || old.series.map(\.name) != new.series.map(\.name)
            || old.series.map(\.values) != new.series.map(\.values)
        if old.type != new.type {
            guard convert(plot, to: new) else { return nil }
            workbook = true
        } else if dataChanged {
            guard rewriteData(plot, new, covered: old.series.count) else { return nil }
            workbook = true
        }
        if old.title != new.title { setTitle(chart, new.title) }
        if old.legend != new.legend || old.legendPosition != new.legendPosition { setLegend(chart, plot, new) }
        return Result(xml: PptxXML.serialize(space), workbook: workbook)
    }

    // MARK: Title and legend

    static func setTitle(_ chart: XNode, _ title: String?) {
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
            let node = XNode(name: "c:title", attrs: [:])
            let tx = XNode(name: "c:tx", attrs: [:]), rich = XNode(name: "c:rich", attrs: [:])
            let p = XNode(name: "a:p", attrs: [:]), r = XNode(name: "a:r", attrs: [:]), t = XNode(name: "a:t", attrs: [:])
            t.text = title
            r.children = [t]; p.children = [r]
            rich.children = [XNode(name: "a:bodyPr", attrs: [:]), XNode(name: "a:lstStyle", attrs: [:]), p]
            tx.children = [rich]
            node.children = [tx, XNode(name: "c:overlay", attrs: ["val": "0"])]
            chart.children.removeAll { $0.name == "c:title" }
            chart.children.insert(node, at: 0)
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

    /// One series' name, categories and values rewritten to the layout of the workbook `ChartXML.workbook` writes.
    private static func fill(_ ser: XNode, index i: Int, _ c: Chart, scatter: Bool) {
        let last = c.categories.count + 1
        let s = c.series[i]
        ser.first("c:idx")?.attrs["val"] = "\(i)"
        ser.first("c:order")?.attrs["val"] = "\(i)"
        let tx = XNode(name: "c:tx", attrs: [:])
        tx.children = [ref("c:strRef", "Sheet1!$\(col(i + 1))$1", strings: [s.name], text: true)]
        put(ser, "c:tx", tx, before: ["c:spPr", "c:invertIfNegative", "c:marker", "c:dPt", "c:dLbls", "c:trendline", "c:errBars",
                                      "c:cat", "c:val", "c:xVal", "c:yVal", "c:smooth"])
        let values = (0 ..< c.categories.count).map { r in r < s.values.count ? s.values[r].map { ChartXML.number($0) } ?? "" : "" }
        let vals = ref("c:numRef", "Sheet1!$\(col(i + 1))$2:$\(col(i + 1))$\(last)", strings: values, text: false)
        if scatter {
            let x = ref("c:numRef", "Sheet1!$A$2:$A$\(last)", strings: c.categories.indices.map { ChartXML.number(c.x($0)) }, text: false)
            let xv = XNode(name: "c:xVal", attrs: [:]); xv.children = [x]
            let yv = XNode(name: "c:yVal", attrs: [:]); yv.children = [vals]
            put(ser, "c:xVal", xv, before: ["c:yVal", "c:smooth"])
            put(ser, "c:yVal", yv, before: ["c:smooth"])
        } else {
            let cat = XNode(name: "c:cat", attrs: [:])
            cat.children = [ref("c:strRef", "Sheet1!$A$2:$A$\(last)", strings: c.categories, text: true)]
            let val = XNode(name: "c:val", attrs: [:]); val.children = [vals]
            put(ser, "c:cat", cat, before: ["c:val", "c:smooth"])
            put(ser, "c:val", val, before: ["c:smooth", "c:shape"])
        }
    }

    private static func copy(_ n: XNode) -> XNode {
        let c = XNode(name: n.name, attrs: n.attrs)
        c.text = n.text
        c.children = n.children.map(copy)
        return c
    }

    /// The same type, new data: each series keeps its own look; extra series are cloned from the last (without its
    /// colour, so the style's next one shows), fewer drop the last ones.
    private static func rewriteData(_ plot: XNode, _ c: Chart, covered: Int) -> Bool {
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
        // Drop the extra ones.
        if all.count > wanted.count {
            for (g, s) in all[wanted.count...] { g.children.removeAll { $0 === s } }
            all = Array(all[..<wanted.count])
        }
        while all.count < wanted.count {
            let clone = copy(template.ser)
            clone.children.removeAll { ["c:spPr", "c:dPt", "c:dLbls", "c:trendline", "c:errBars", "c:marker", "c:extLst"].contains($0.name) }
            let at = (template.group.children.lastIndex { $0.name == "c:ser" } ?? template.group.children.count - 1) + 1
            template.group.children.insert(clone, at: at)
            all.append((template.group, clone))
        }
        var shown = c
        shown.series = wanted
        for (i, e) in all.enumerated() { fill(e.ser, index: i, shown, scatter: scatter) }
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
        var sers: [XNode] = []
        for i in wanted.indices {
            let ser = node("c:ser")
            ser.children = [node("c:idx", ["val": "\(i)"]), node("c:order", ["val": "\(i)"])]
            if keepsLook, i < oldSers.count, let sp = oldSers[i].first("c:spPr") {
                let spc = copy(sp)
                // A line type draws with the series' line, an area or bar with its fill.
                if c.type == .line || c.type == .radar, spc.first("a:ln") == nil, let fill = spc.first("a:solidFill") {
                    let ln = node("a:ln", ["w": "28575", "cap": "rnd"]); ln.children = [copy(fill), node("a:round")]
                    spc.children = [ln]
                }
                ser.children.append(spc)
            }
            fill(ser, index: i, shown, scatter: c.type == .scatter)
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
            for ax in plot.children where ax.name == "c:catAx" || ax.name == "c:valAx" {
                if let pos = ax.first("c:axPos") {
                    let vertical = (ax.name == "c:catAx") == (c.type == .bar)
                    pos.attrs["val"] = vertical ? "l" : "b"
                }
            }
        }
        return true
    }
}
