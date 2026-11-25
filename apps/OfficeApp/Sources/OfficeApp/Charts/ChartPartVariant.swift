// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-CH-4: the 3D, stock and bubble forms of a chart, to and from, in the chart's part. The part's first group
// is rebuilt (series keep their cells); a bubble's sizes and a stock's missing series are cell ranges the
// caller asked the user for.

import Foundation

/// A chart form that the model's `ChartType` does not name: the type underneath stays (column, line, scatter...).
enum ChartVariant: Equatable {
    /// The 3D form of the chart's column, bar, line, area or pie.
    case threeD
    /// Open-high-low-close (`ohlc`) or high-low-close, from the chart's series in that order; `extra` are the
    /// ranges (values) of the series it lacked, appended in order.
    case stock(ohlc: Bool, extra: [String])
    /// Each series' bubble sizes: one range per series, or one for all.
    case bubble(sizes: [String])
}

extension ChartPartType {
    static let variantGroups: Set<String> = ["c:bar3DChart", "c:line3DChart", "c:area3DChart", "c:pie3DChart", "c:stockChart", "c:bubbleChart"]

    /// Whether the part holds a 3D, stock or bubble group.
    static func hasVariant(_ xml: String) -> Bool {
        xml.containsSubstring("<c:bar3DChart") || xml.containsSubstring("<c:line3DChart") || xml.containsSubstring("<c:area3DChart")
            || xml.containsSubstring("<c:pie3DChart") || xml.containsSubstring("<c:stockChart") || xml.containsSubstring("<c:bubbleChart")
    }

    /// 3D, stock and bubble groups made the plain groups they are (series, cells and axes kept), so `convert` takes them.
    static func flatten(_ space: XNode) {
        guard let chart = space.first("c:chart"), let plot = chart.first("c:plotArea") else { return }
        for g in groups(plot) where variantGroups.contains(g.name) {
            switch g.name {
            case "c:bar3DChart": g.name = "c:barChart"
            case "c:line3DChart": g.name = "c:lineChart"
            case "c:area3DChart": g.name = "c:areaChart"
            case "c:pie3DChart": g.name = "c:pieChart"
            case "c:stockChart":
                g.name = "c:lineChart"
                for s in g.all("c:ser") { s.children.removeAll { $0.name == "c:spPr" || $0.name == "c:marker" } }
            default: // bubble
                g.name = "c:scatterChart"
                for s in g.all("c:ser") { s.children.removeAll { ["c:bubbleSize", "c:bubble3D", "c:invertIfNegative"].contains($0.name) } }
            }
            g.children.removeAll { ["c:gapDepth", "c:shape", "c:hiLowLines", "c:upDownBars", "c:bubbleScale", "c:showNegBubbles", "c:sizeRepresents", "c:bubble3D"].contains($0.name) }
            // Only two axes belong to a plain group.
            let ids = g.all("c:axId")
            for extra in ids.dropFirst(2) { g.children.removeAll { $0 === extra } }
        }
        plot.children.removeAll { $0.name == "c:serAx" }
        chart.children.removeAll { ["c:view3D", "c:floor", "c:sideWall", "c:backWall"].contains($0.name) }
    }

    /// The part with `variant` applied to its first group, which `type` has already made (the plain column, line,
    /// scatter...); nil where the type has no such form or the data it needs is missing.
    static func apply(_ xml: String, _ variant: ChartVariant, type: ChartType) -> String? {
        guard let parsed = XNode.parse(Data(xml.utf8)) else { return nil }
        let space = ChartXML.canonical(parsed)
        guard space.name == "c:chartSpace", let chart = space.first("c:chart"), let plot = chart.first("c:plotArea"),
              let g = groups(plot).first, let at = plot.children.firstIndex(where: { $0 === g }) else { return nil }
        let sers = g.all("c:ser")
        let ids = g.all("c:axId").compactMap { $0["val"] }
        func axIds(_ extra: String? = nil) -> [XNode] { (ids + (extra.map { [$0] } ?? [])).map { node("c:axId", ["val": $0]) } }
        func strip(_ names: Set<String>) { g.children.removeAll { names.contains($0.name) } }
        switch variant {
        case .threeD:
            var rotX = "15", rotY = "20", right = "1"
            switch g.name {
            case "c:barChart": g.name = "c:bar3DChart"; strip(["c:axId"]); g.children += axIds("0")
            case "c:lineChart", "c:areaChart":
                g.name = g.name == "c:lineChart" ? "c:line3DChart" : "c:area3DChart"
                strip(["c:marker", "c:axId"])
                let sid = "333333333"
                g.children += axIds(sid)
                guard let val = plot.children.first(where: { $0.name == "c:valAx" }) else { return nil }
                let ser = node("c:serAx")
                ser.children = [node("c:axId", ["val": sid]), node("c:scaling"), node("c:delete", ["val": "0"]), node("c:axPos", ["val": "b"]),
                                node("c:majorTickMark", ["val": "out"]), node("c:minorTickMark", ["val": "none"]),
                                node("c:tickLblPos", ["val": "nextTo"]), node("c:crossAx", ["val": val.first("c:axId")?["val"] ?? ""]),
                                node("c:crosses", ["val": "autoZero"])]
                ser.children[1].children = [node("c:orientation", ["val": "minMax"])]
                let last = (plot.children.lastIndex { ["c:catAx", "c:valAx", "c:dateAx"].contains($0.name) } ?? at) + 1
                plot.children.insert(ser, at: last)
            case "c:pieChart":
                g.name = "c:pie3DChart"; strip(["c:firstSliceAng"]); rotX = "30"; rotY = "0"; right = "0"
            default: return nil
            }
            chart.children.removeAll { $0.name == "c:view3D" }
            let v = node("c:view3D")
            v.children = [node("c:rotX", ["val": rotX]), node("c:rotY", ["val": rotY]), node("c:rAngAx", ["val": right])]
            if right == "0" { v.children.append(node("c:perspective", ["val": "30"])) }
            let pi = chart.children.firstIndex(where: { $0 === plot }) ?? chart.children.count
            chart.children.insert(v, at: pi)
        case .stock(let ohlc, let extra):
            guard g.name == "c:lineChart" else { return nil }
            let n = ohlc ? 4 : 3
            let first = sers.first
            var made = sers.map(copy)
            for f in extra {
                let s = node("c:ser")
                let role = ["Open", "High", "Low", "Close"][min(3, made.count + (ohlc ? 0 : 1))]
                let tx = node("c:tx"); let v = node("c:v"); v.text = role; tx.children = [v]
                let val = node("c:val"); let ref = node("c:numRef"); let fx = node("c:f"); fx.text = f
                ref.children = [fx]; val.children = [ref]
                s.children = [tx]
                if let cat = first?.first("c:cat") { s.children.append(copy(cat)) }
                s.children.append(val)
                made.append(s)
            }
            guard made.count >= n else { return nil }
            var out: [XNode] = []
            for (i, old) in made.prefix(n).enumerated() {
                let s = node("c:ser")
                s.children = [node("c:idx", ["val": "\(i)"]), node("c:order", ["val": "\(i)"])]
                if let tx = old.first("c:tx") { s.children.append(copy(tx)) }
                let ln = node("a:ln", ["w": "19050", "cap": "rnd"]); ln.children = [node("a:noFill"), node("a:round")]
                let sp = node("c:spPr"); sp.children = [ln]
                s.children += [sp, { let m = node("c:marker"); m.children = [node("c:symbol", ["val": "none"])]; return m }()]
                for k in ["c:cat", "c:val"] { if let x = old.first(k) { s.children.append(copy(x)) } }
                s.children.append(node("c:smooth", ["val": "0"]))
                out.append(s)
            }
            let hl = node("c:hiLowLines"); let hln = node("a:ln", ["w": "9525"]); let fill = node("a:solidFill"); fill.children = [node("a:srgbClr", ["val": "000000"])]
            hln.children = [fill]; let hsp = node("c:spPr"); hsp.children = [hln]; hl.children = [hsp]
            var kids: [XNode] = out + [hl]
            if ohlc {
                func bar(_ name: String, _ rgb: String) -> XNode {
                    let b = node(name); let sp = node("c:spPr"); let f = node("a:solidFill"); f.children = [node("a:srgbClr", ["val": rgb])]
                    sp.children = [f]; b.children = [sp]; return b
                }
                let ud = node("c:upDownBars"); ud.children = [node("c:gapWidth", ["val": "150"]), bar("c:upBars", "FFFFFF"), bar("c:downBars", "000000")]
                kids.append(ud)
            }
            g.name = "c:stockChart"
            g.children = kids + axIds()
        case .bubble(let sizes):
            guard g.name == "c:scatterChart", !sizes.isEmpty else { return nil }
            for (i, s) in sers.enumerated() {
                s.children.removeAll { $0.name == "c:smooth" || $0.name == "c:marker" }
                let size = node("c:bubbleSize"); let ref = node("c:numRef"); let fx = node("c:f"); fx.text = sizes[min(i, sizes.count - 1)]
                ref.children = [fx]; size.children = [ref]
                s.children += [size, node("c:bubble3D", ["val": "0"])]
            }
            g.name = "c:bubbleChart"
            g.children = [node("c:varyColors", ["val": "0"])] + sers + [node("c:bubbleScale", ["val": "100"]), node("c:showNegBubbles", ["val": "0"])] + axIds()
        }
        _ = type
        return PptxXML.serialize(space)
    }
}

extension Chart {
    /// The model's look of the form (3D view, high-low lines): what the part gets at save, shown meanwhile. nil is the plain chart.
    mutating func setForm(_ v: ChartVariant?) {
        barView = nil; areaView = nil; line3D = false; pieTilt = nil; piePerspective = nil; highLowLines = nil
        for i in series.indices { series[i].bubbleSizes = nil }
        guard let v else { return }
        switch v {
        case .threeD:
            switch type {
            case .column, .bar: barView = BarView(x: 15, y: 20)
            case .area: areaView = BarView(x: 15, y: 20)
            case .line: line3D = true
            case .pie: pieTilt = 30; piePerspective = 30
            default: break
            }
        case .stock: highLowLines = HighLowLines(color: nil, width: 0.75)
        case .bubble: break
        }
    }
}
