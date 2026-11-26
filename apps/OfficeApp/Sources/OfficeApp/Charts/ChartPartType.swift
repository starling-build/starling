// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-CH-3: Change Chart Type on a chart that came from a file. The first chart group of the part becomes the new
// type's, its series keep their cells and (where the type paints series alike) their look; every other element of
// the part stays as the file wrote it. Slides and Sheets both patch through this.

import Foundation

enum ChartPartType {
    /// The part `xml` with its first chart group made `chart.type`'s (`chart` is the chart as it now stands, its series
    /// and type new); nil when the part cannot be converted without losing what it holds (3D, stock and bubble groups).
    static func retype(_ xml: String, to chart: Chart) -> String? {
        guard let parsed = XNode.parse(Data(xml.utf8)) else { return nil }
        // Column <-> bar keeps every byte: only the bars' direction and the axes' sides change.
        let existing = groups(ChartXML.canonical(parsed).first("c:chart")?.first("c:plotArea") ?? parsed)
        if !hasVariant(xml), chart.type == .column || chart.type == .bar, existing.count == 1, existing[0].name == "c:barChart" {
            return swapBars(xml, chart.type)
        }
        let space = ChartXML.canonical(parsed)
        flatten(space)
        guard space.name == "c:chartSpace", let plot = space.first("c:chart")?.first("c:plotArea"), convert(plot, to: chart) else { return nil }
        return PptxXML.serialize(space)
    }

    static let groupNames: Set<String> = ["c:barChart", "c:lineChart", "c:areaChart", "c:pieChart", "c:doughnutChart",
                                                  "c:scatterChart", "c:radarChart", "c:bar3DChart", "c:line3DChart",
                                                  "c:area3DChart", "c:pie3DChart", "c:stockChart", "c:bubbleChart"]

    static func groups(_ plot: XNode) -> [XNode] { plot.children.filter { groupNames.contains($0.name) } }

    /// The series' name, categories and values as the file wrote them (a type change keeps the data and its cells).
    static func carry(_ ser: XNode, from old: XNode, scatter: Bool) {
        if let tx = old.first("c:tx") { ser.children.append(copy(tx)) }
        let x = old.first("c:cat") ?? old.first("c:xVal"), y = old.first("c:val") ?? old.first("c:yVal")
        if let x { let n = copy(x); n.name = scatter ? "c:xVal" : "c:cat"; ser.children.append(n) }
        if let y { let n = copy(y); n.name = scatter ? "c:yVal" : "c:val"; ser.children.append(n) }
    }

    static func copy(_ n: XNode) -> XNode {
        let c = XNode(name: n.name, attrs: n.attrs)
        c.text = n.text
        c.children = n.children.map(copy)
        return c
    }


    static func node(_ name: String, _ attrs: [String: String] = [:]) -> XNode { XNode(name: name, attrs: attrs) }

    /// The first chart group becomes the new type's, its series rebuilt from `c` (their colours stay on a type that
    /// paints series alike); axes added or dropped as the type needs. Other groups of a combination chart stay.
    static func convert(_ plot: XNode, to c: Chart) -> Bool {
        let gs = groups(plot)
        guard let group = gs.first, !gs.contains(where: { variantGroups.contains($0.name) }) else { return false }
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
        // A pie keeps every series in the part (Excel draws the first and keeps the rest, so a switch back loses nothing).
        let wanted = (c.type.isPie ? Array(0..<oldSers.count) : Array(0..<c.series.count)).filter { $0 < oldSers.count }
        let keepsLook = !(c.type.isPie || group.name == "c:pieChart" || group.name == "c:doughnutChart" || c.type == .scatter || group.name == "c:scatterChart")
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
                            node("c:axPos", ["val": c.type == .bar ? "l" : "b"]), node("c:majorTickMark", ["val": "out"]),
                            node("c:minorTickMark", ["val": "none"]), node("c:tickLblPos", ["val": "nextTo"]), node("c:crossAx", ["val": b])]
            cat.children[1].children = [node("c:orientation", ["val": "minMax"])]
            let val = node("c:valAx")
            val.children = [node("c:axId", ["val": b]), node("c:scaling"), node("c:delete", ["val": "0"]),
                            node("c:axPos", ["val": c.type == .bar ? "b" : "l"]), node("c:majorGridlines"), node("c:majorTickMark", ["val": "out"]),
                            node("c:minorTickMark", ["val": "none"]), node("c:tickLblPos", ["val": "nextTo"]), node("c:crossAx", ["val": a])]
            val.children[1].children = [node("c:orientation", ["val": "minMax"])]
            let i = (plot.children.lastIndex { groupNames.contains($0.name) } ?? 0) + 1
            plot.children.insert(contentsOf: [cat, val], at: i)
        }
        retagScatterAxes(plot, group: g, scatter: c.type == .scatter)
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

    /// A scatter's two axes are both value axes (x at the bottom); every other type's first is a category axis.
    static func retagScatterAxes(_ plot: XNode, group g: XNode, scatter: Bool) {
        let ids = g.all("c:axId").compactMap { $0["val"] }
        guard let xid = ids.first else { return }
        let catOnly: Set<String> = ["c:auto", "c:lblAlgn", "c:lblOffset", "c:noMultiLvlLbl"]
        for ax in plot.children where ids.contains(ax.first("c:axId")?["val"] ?? "") {
            if scatter, ax.name == "c:catAx" || ax.name == "c:dateAx" {
                ax.name = "c:valAx"
                ax.children.removeAll { catOnly.contains($0.name) || $0.name == "c:baseTimeUnit" || $0.name == "c:majorTimeUnit" }
                if ax.first("c:crossBetween") == nil {
                    let at = (ax.children.lastIndex { ["c:crossAx", "c:crosses", "c:crossesAt"].contains($0.name) } ?? ax.children.count - 1) + 1
                    ax.children.insert(node("c:crossBetween", ["val": "midCat"]), at: at)
                }
                if ax.first("c:axId")?["val"] == xid { ax.first("c:axPos")?.attrs["val"] = "b" }
            } else if !scatter, ax.name == "c:valAx", ax.first("c:axId")?["val"] == xid {
                ax.name = "c:catAx"
                ax.children.removeAll { $0.name == "c:crossBetween" || $0.name == "c:majorUnit" || $0.name == "c:minorUnit" }
                let at = (ax.children.lastIndex { ["c:crossAx", "c:crosses", "c:crossesAt"].contains($0.name) } ?? ax.children.count - 1) + 1
                ax.children.insert(contentsOf: [node("c:auto", ["val": "1"]), node("c:lblAlgn", ["val": "ctr"]),
                                                node("c:lblOffset", ["val": "100"]), node("c:noMultiLvlLbl", ["val": "0"])], at: at)
            }
        }
    }

    /// Column <-> bar in a chart part: the bars' direction and where each axis sits.
    static func swapBars(_ xml: String, _ type: ChartType) -> String {
        let col = type == .column
        var x = xml.replacingAll("<c:barDir val=\"\(col ? "bar" : "col")\"/>", with: "<c:barDir val=\"\(col ? "col" : "bar")\"/>")
        func swap(_ tag: String, _ from: String, _ to: String) {
            guard let r = x.rangeOfSubstring("<c:\(tag)>"), let e = x.rangeOfSubstring("</c:\(tag)>", in: r.upperBound..<x.endIndex) else { return }
            let body = x[r.upperBound..<e.lowerBound].replacingAll("<c:axPos val=\"\(from)\"/>", with: "<c:axPos val=\"\(to)\"/>")
            x.replaceSubrange(r.upperBound..<e.lowerBound, with: body)
        }
        swap("catAx", col ? "l" : "b", col ? "b" : "l")
        swap("valAx", col ? "b" : "l", col ? "l" : "b")
        return x
    }
}
