// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Charts (docs/plans/slides.md, S6b): the six kinds PowerPoint's Insert
// Chart leads with — column, bar, line, pie, area, scatter — as a value
// the deck snapshots like any other, drawn from its own numbers. A chart
// read from a file comes from its `c:chartSpace` part's cached values; a
// chart written by this app carries that cache plus an embedded workbook
// (a minimal .xlsx) holding the same table, so PowerPoint's Edit Data
// opens on it.

import Flutter
import FlutterSwiftBridge
import FluentSystemIcons
import Foundation

enum ChartType: String, CaseIterable {
    case column, bar, line, pie, area, scatter

    var name: String {
        switch self {
        case .column: return "Column"
        case .bar: return "Bar"
        case .line: return "Line"
        case .pie: return "Pie"
        case .area: return "Area"
        case .scatter: return "Scatter"
        }
    }

    var hasAxes: Bool { self != .pie }

    var icon: IconData {
        switch self {
        case .column: return FluentSystemIcons.chartColumn
        case .bar: return FluentSystemIcons.chartBar
        case .line: return FluentSystemIcons.chartLine
        case .pie: return FluentSystemIcons.chartPie
        case .area: return FluentSystemIcons.chartArea
        case .scatter: return FluentSystemIcons.chartScatter
        }
    }
}

struct ChartSeries: Equatable {
    var name: String
    /// One per category; nil is a blank cell (a gap).
    var values: [Double?]
    /// A colour the file set as itself; nil follows the theme.
    var color: Color? = nil
    /// The theme slot the file named ("accent3"), followed by a new theme.
    var scheme: String? = nil
}

struct Chart: Equatable {
    var type: ChartType
    /// Shown above the plot; nil for none.
    var title: String?
    /// The first column of the data: category names, or for a scatter
    /// chart the x values.
    var categories: [String]
    var series: [ChartSeries]
    var legend = true
    var dataLabels = false
    /// `c:grouping`: clustered/standard, stacked or percentStacked.
    var stacked = false
    var percent = false
    var categoryAxisTitle: String? = nil
    var valueAxisTitle: String? = nil
    /// A bar chart's spacing as the file set it, in percent of a bar:
    /// the gap between categories and the overlap of a category's bars.
    /// Nil is PowerPoint's default (219 and -27; 150 and 100 stacked).
    var gapWidth: Int? = nil
    var overlap: Int? = nil

    var gap: Double { Double(gapWidth ?? (stacked ? 150 : 219)) / 100 }
    var overlapFraction: Double { Double(overlap ?? (stacked ? 100 : -27)) / 100 }

    /// PowerPoint's sample data for a freshly inserted chart of `type`.
    static func sample(_ type: ChartType) -> Chart {
        switch type {
        case .pie:
            return Chart(type: .pie, title: "Sales", categories: ["1st Qtr", "2nd Qtr", "3rd Qtr", "4th Qtr"],
                         series: [ChartSeries(name: "Sales", values: [8.2, 3.2, 1.4, 1.2])])
        case .scatter:
            return Chart(type: .scatter, title: "Y-Values", categories: ["0.7", "1.8", "2.6"],
                         series: [ChartSeries(name: "Y-Values", values: [2.7, 3.2, 0.8])], legend: false)
        default:
            return Chart(type: type, title: "Chart Title",
                         categories: ["Category 1", "Category 2", "Category 3", "Category 4"],
                         series: [ChartSeries(name: "Series 1", values: [4.3, 2.5, 3.5, 4.5]),
                                  ChartSeries(name: "Series 2", values: [2.4, 4.4, 1.8, 2.8]),
                                  ChartSeries(name: "Series 3", values: [2, 2, 3, 5])])
        }
    }

    /// The same data as another kind. A pie keeps only the first series.
    func converted(to t: ChartType) -> Chart {
        var c = self
        c.type = t
        if t == .pie || t == .scatter { c.stacked = false; c.percent = false }
        return c
    }

    /// Series colour `i` against `accents`.
    func color(series i: Int, accents: [Color]) -> Color {
        let s = i < series.count ? series[i] : nil
        if let c = s?.color { return c }
        if let scheme = s?.scheme, scheme.hasPrefix("accent"), let n = Int(scheme.dropFirst(6)), (1 ... 6).contains(n) {
            return accents[n - 1]
        }
        return Self.cycle(i, accents)
    }

    /// PowerPoint's colour cycle: the six accents, then darker and lighter
    /// rounds of them.
    static func cycle(_ i: Int, _ accents: [Color]) -> Color {
        let base = accents[i % accents.count]
        switch (i / accents.count) % 3 {
        case 1: return DeckController.shade(base, 0.6)
        case 2: return DeckController.tint(base, 0.6)
        default: return base
        }
    }

    /// x of category `i` for a scatter chart: its number, or its position.
    func x(_ i: Int) -> Double {
        i < categories.count ? Double(categories[i].trimmingWhitespace()) ?? Double(i + 1) : Double(i + 1)
    }
}

// MARK: - Reading

enum ChartXML {
    /// The chart in a `c:chartSpace`, or nil for one this app cannot draw
    /// (3D, doughnut, radar, stock, combinations) — kept as an object then.
    static func read(_ space: XNode, color: (XNode) -> Color?) -> Chart? {
        guard let chart = space.first("c:chart"), let plot = chart.first("c:plotArea") else { return nil }
        let kinds = plot.children.filter { $0.name.hasPrefix("c:") && $0.name.hasSuffix("Chart") }
        guard kinds.count == 1, let el = kinds.first else { return nil }
        let type: ChartType
        switch el.name {
        case "c:barChart": type = el.first("c:barDir")?["val"] == "bar" ? .bar : .column
        case "c:lineChart": type = .line
        case "c:pieChart": type = .pie
        case "c:areaChart": type = .area
        case "c:scatterChart": type = .scatter
        default: return nil
        }
        let grouping = el.first("c:grouping")?["val"] ?? "standard"
        var categories: [String] = []
        var series: [ChartSeries] = []
        for ser in el.all("c:ser") {
            let name = ser.first("c:tx").map { _texts($0, "c:v").joined() } ?? "Series \(series.count + 1)"
            let cat = ser.first("c:cat") ?? ser.first("c:xVal")
            let val = ser.first("c:val") ?? ser.first("c:yVal")
            let names = cat.map(_points) ?? []
            if categories.count < names.count {
                categories = names.enumerated().map { $0.element ?? (categories.indices.contains($0.offset) ? categories[$0.offset] : "") }
            }
            let values = (val.map(_points) ?? []).map { $0.flatMap { Double($0.trimmingWhitespace()) } }
            var s = ChartSeries(name: name, values: values)
            let pr = ser.first("c:spPr")
            let fill = type == .line ? pr?.first("a:ln")?.first("a:solidFill")
                : type == .scatter ? ser.first("c:marker")?.first("c:spPr")?.first("a:solidFill") ?? pr?.first("a:solidFill")
                : pr?.first("a:solidFill")
            if let fill {
                let index = series.count
                if let scheme = fill.first("a:schemeClr"), _isCycle(scheme, index) {
                    // The theme's own colour for this series: follows the theme.
                } else if let scheme = fill.first("a:schemeClr"), scheme.children.isEmpty {
                    s.scheme = scheme["val"]
                } else {
                    s.color = color(fill)
                }
            }
            series.append(s)
        }
        guard !series.isEmpty else { return nil }
        let n = max(categories.count, series.map(\.values.count).max() ?? 0)
        if categories.count < n { categories += (categories.count ..< n).map { "\($0 + 1)" } }
        for i in series.indices where series[i].values.count < n {
            series[i].values += Array(repeating: nil, count: n - series[i].values.count)
        }

        var title: String? = nil
        let deleted = chart.first("c:autoTitleDeleted")?["val"] == "1"
        if let t = chart.first("c:title") {
            let text = _texts(t, "a:t").joined()
            title = text.isEmpty ? (series.count == 1 ? series[0].name : "Chart Title") : text
        } else if !deleted && series.count == 1 {
            title = series[0].name
        }
        var c = Chart(type: type, title: title, categories: categories, series: series)
        c.legend = chart.first("c:legend") != nil
        c.stacked = grouping == "stacked" || grouping == "percentStacked"
        c.percent = grouping == "percentStacked"
        func shows(_ d: XNode?) -> Bool { d?.first("c:showVal")?["val"] == "1" || d?.first("c:showPercent")?["val"] == "1" }
        if type == .column || type == .bar {
            // Absent, the schema's defaults apply (150 and 0) — not what
            // PowerPoint writes for a new chart.
            c.gapWidth = el.first("c:gapWidth")?["val"].flatMap(Int.init) ?? 150
            c.overlap = el.first("c:overlap")?["val"].flatMap(Int.init) ?? 0
            if c.gapWidth == (c.stacked ? 150 : 219) { c.gapWidth = nil }
            if c.overlap == (c.stacked ? 100 : -27) { c.overlap = nil }
        }
        c.dataLabels = shows(el.first("c:dLbls")) || el.all("c:ser").contains { shows($0.first("c:dLbls")) }
        func axisTitle(_ ax: XNode?) -> String? {
            guard let t = ax?.first("c:title") else { return nil }
            let s = _texts(t, "a:t").joined()
            return s.isEmpty ? "Axis Title" : s
        }
        let axes = plot.children.filter { ["c:catAx", "c:valAx", "c:dateAx"].contains($0.name) }
        if type == .scatter {
            c.categoryAxisTitle = axisTitle(axes.first { ["b", "t"].contains($0.first("c:axPos")?["val"] ?? "") })
            c.valueAxisTitle = axisTitle(axes.first { ["l", "r"].contains($0.first("c:axPos")?["val"] ?? "") })
        } else {
            c.categoryAxisTitle = axisTitle(axes.first { $0.name != "c:valAx" })
            c.valueAxisTitle = axisTitle(axes.first { $0.name == "c:valAx" })
        }
        return c
    }

    /// Whether `scheme` is series `i`'s colour in the default cycle, as
    /// this app (and PowerPoint) writes it: `accent(i mod 6 + 1)`, shaded or
    /// tinted on later rounds.
    private static func _isCycle(_ scheme: XNode, _ i: Int) -> Bool {
        guard scheme["val"] == "accent\(i % 6 + 1)" else { return false }
        let mods = scheme.children.map { "\($0.name)=\($0["val"] ?? "")" }
        switch (i / 6) % 3 {
        case 0: return mods.isEmpty
        case 1: return mods == ["a:shade=60000"]
        default: return mods == ["a:tint=60000"]
        }
    }

    /// The cached points of a `c:cat`/`c:val`-like element, by index.
    private static func _points(_ node: XNode) -> [String?] {
        guard let cache = node.descendant("c:strCache") ?? node.descendant("c:numCache")
            ?? node.descendant("c:strLit") ?? node.descendant("c:numLit") ?? node.descendant("c:lvl") else { return [] }
        let pts = cache.all("c:pt")
        let count = cache.first("c:ptCount")?["val"].flatMap(Int.init)
            ?? ((pts.compactMap { $0["idx"].flatMap(Int.init) }.max() ?? -1) + 1)
        var out = [String?](repeating: nil, count: max(0, min(count, 100_000)))
        for pt in pts {
            guard let i = pt["idx"].flatMap(Int.init), out.indices.contains(i) else { continue }
            out[i] = pt.first("c:v")?.text
        }
        return out
    }

    private static func _texts(_ node: XNode, _ name: String) -> [String] {
        if node.name == name { return [node.text] }
        return node.children.flatMap { _texts($0, name) }
    }

    // MARK: Writing

    static let contentType = "application/vnd.openxmlformats-officedocument.drawingml.chart+xml"
    static let relType = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart"
    static let packageRelType = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/package"
    static let xlsxType = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"

    /// The spreadsheet column for data column `i` (0 = A).
    static func column(_ i: Int) -> String {
        var n = i + 1, s = ""
        while n > 0 { let r = (n - 1) % 26; s = String(UnicodeScalar(65 + r)!) + s; n = (n - 1) / 26 }
        return s
    }

    static func number(_ v: Double) -> String {
        if v == v.rounded(), abs(v) < 1e15 { return String(Int(v)) }
        return "\(v)"
    }

    private static func _esc(_ s: String) -> String { PptxXML.escape(s, attribute: false) }

    private static func _rich(_ text: String, size: Int?, rotated: Bool = false) -> String {
        let body = rotated ? "<a:bodyPr rot=\"-5400000\" vert=\"horz\"/>" : "<a:bodyPr/>"
        let def = size.map { "<a:pPr><a:defRPr sz=\"\($0)\" b=\"0\"/></a:pPr>" } ?? ""
        return "<c:title><c:tx><c:rich>\(body)<a:lstStyle/><a:p>\(def)<a:r><a:rPr lang=\"en-US\"/><a:t>\(_esc(text))</a:t></a:r></a:p></c:rich></c:tx><c:overlay val=\"0\"/></c:title>"
    }

    private static let _gridLine = "<a:ln w=\"9525\" cap=\"flat\" cmpd=\"sng\" algn=\"ctr\"><a:solidFill><a:schemeClr val=\"tx1\"><a:lumMod val=\"15000\"/><a:lumOff val=\"85000\"/></a:schemeClr></a:solidFill><a:round/></a:ln>"

    private static func _solid(_ chart: Chart, _ i: Int) -> String {
        let s = chart.series[i]
        if let c = s.color { return "<a:solidFill><a:srgbClr val=\"\(PptxText.hex(c))\"/></a:solidFill>" }
        if let scheme = s.scheme { return "<a:solidFill><a:schemeClr val=\"\(scheme)\"/></a:solidFill>" }
        return _cycleFill(i)
    }

    /// Colour `i` of the theme's cycle, as theme references.
    private static func _cycleFill(_ i: Int) -> String {
        var mod = ""
        switch (i / 6) % 3 {
        case 1: mod = "<a:shade val=\"60000\"/>"
        case 2: mod = "<a:tint val=\"60000\"/>"
        default: break
        }
        return "<a:solidFill><a:schemeClr val=\"accent\(i % 6 + 1)\">\(mod)</a:schemeClr></a:solidFill>"
    }

    private static let _labels = "<c:dLbls><c:showLegendKey val=\"0\"/><c:showVal val=\"1\"/><c:showCatName val=\"0\"/><c:showSerName val=\"0\"/><c:showPercent val=\"0\"/><c:showBubbleSize val=\"0\"/></c:dLbls>"

    /// The chart part, cached values and all, pointing at its workbook
    /// through relationship `rId1`.
    static func chartSpace(_ c: Chart) -> String {
        let n = c.categories.count
        let last = n + 1
        var sers = ""
        let catRef = "Sheet1!$A$2:$A$\(last)"
        let catCache: String = {
            if c.type == .scatter {
                let pts = c.categories.enumerated().map { "<c:pt idx=\"\($0.offset)\"><c:v>\(number(c.x($0.offset)))</c:v></c:pt>" }.joined()
                return "<c:numRef><c:f>\(catRef)</c:f><c:numCache><c:formatCode>General</c:formatCode><c:ptCount val=\"\(n)\"/>\(pts)</c:numCache></c:numRef>"
            }
            let pts = c.categories.enumerated().map { "<c:pt idx=\"\($0.offset)\"><c:v>\(_esc($0.element))</c:v></c:pt>" }.joined()
            return "<c:strRef><c:f>\(catRef)</c:f><c:strCache><c:ptCount val=\"\(n)\"/>\(pts)</c:strCache></c:strRef>"
        }()
        let seriesList = c.type == .pie ? Array(c.series.prefix(1)) : c.series
        for (i, s) in seriesList.enumerated() {
            let col = column(i + 1)
            let tx = "<c:tx><c:strRef><c:f>Sheet1!$\(col)$1</c:f><c:strCache><c:ptCount val=\"1\"/><c:pt idx=\"0\"><c:v>\(_esc(s.name))</c:v></c:pt></c:strCache></c:strRef></c:tx>"
            let pts = s.values.prefix(n).enumerated().compactMap { p in p.element.map { "<c:pt idx=\"\(p.offset)\"><c:v>\(number($0))</c:v></c:pt>" } }.joined()
            let val = "<c:numRef><c:f>Sheet1!$\(col)$2:$\(col)$\(last)</c:f><c:numCache><c:formatCode>General</c:formatCode><c:ptCount val=\"\(n)\"/>\(pts)</c:numCache></c:numRef>"
            let head = "<c:idx val=\"\(i)\"/><c:order val=\"\(i)\"/>\(tx)"
            switch c.type {
            case .column, .bar:
                sers += "<c:ser>\(head)<c:spPr>\(_solid(c, i))<a:ln><a:noFill/></a:ln></c:spPr><c:invertIfNegative val=\"0\"/><c:cat>\(catCache)</c:cat><c:val>\(val)</c:val></c:ser>"
            case .area:
                sers += "<c:ser>\(head)<c:spPr>\(_solid(c, i))<a:ln><a:noFill/></a:ln></c:spPr><c:cat>\(catCache)</c:cat><c:val>\(val)</c:val></c:ser>"
            case .line:
                sers += "<c:ser>\(head)<c:spPr><a:ln w=\"28575\" cap=\"rnd\">\(_solid(c, i))<a:round/></a:ln></c:spPr><c:marker><c:symbol val=\"none\"/></c:marker><c:cat>\(catCache)</c:cat><c:val>\(val)</c:val><c:smooth val=\"0\"/></c:ser>"
            case .scatter:
                sers += "<c:ser>\(head)<c:spPr><a:ln w=\"25400\" cap=\"rnd\"><a:noFill/><a:round/></a:ln></c:spPr><c:marker><c:symbol val=\"circle\"/><c:size val=\"5\"/><c:spPr>\(_solid(c, i))<a:ln w=\"9525\">\(_solid(c, i))</a:ln></c:spPr></c:marker><c:xVal>\(catCache)</c:xVal><c:yVal>\(val)</c:yVal><c:smooth val=\"0\"/></c:ser>"
            case .pie:
                var dpts = ""
                for p in 0 ..< n {
                    dpts += "<c:dPt><c:idx val=\"\(p)\"/><c:bubble3D val=\"0\"/><c:spPr>\(_cycleFill(p))<a:ln w=\"19050\"><a:solidFill><a:schemeClr val=\"lt1\"/></a:solidFill></a:ln></c:spPr></c:dPt>"
                }
                sers += "<c:ser>\(head)\(dpts)<c:cat>\(catCache)</c:cat><c:val>\(val)</c:val></c:ser>"
            }
        }
        let labels = c.dataLabels ? _labels : ""
        let grouping = c.percent ? "percentStacked" : c.stacked ? "stacked" : (c.type == .column || c.type == .bar ? "clustered" : "standard")
        let ax = "<c:axId val=\"500000001\"/><c:axId val=\"500000002\"/>"
        var plot: String
        switch c.type {
        case .column, .bar:
            let gap = "<c:gapWidth val=\"\(Int((c.gap * 100).rounded()))\"/><c:overlap val=\"\(Int((c.overlapFraction * 100).rounded()))\"/>"
            plot = "<c:barChart><c:barDir val=\"\(c.type == .bar ? "bar" : "col")\"/><c:grouping val=\"\(grouping)\"/><c:varyColors val=\"0\"/>\(sers)\(labels)\(gap)\(ax)</c:barChart>"
        case .line:
            plot = "<c:lineChart><c:grouping val=\"\(grouping)\"/><c:varyColors val=\"0\"/>\(sers)\(labels)<c:marker val=\"1\"/>\(ax)</c:lineChart>"
        case .area:
            plot = "<c:areaChart><c:grouping val=\"\(grouping)\"/><c:varyColors val=\"0\"/>\(sers)\(labels)\(ax)</c:areaChart>"
        case .scatter:
            plot = "<c:scatterChart><c:scatterStyle val=\"lineMarker\"/><c:varyColors val=\"0\"/>\(sers)\(labels)\(ax)</c:scatterChart>"
        case .pie:
            plot = "<c:pieChart><c:varyColors val=\"1\"/>\(sers)\(labels)<c:firstSliceAng val=\"0\"/></c:pieChart>"
        }
        if c.type.hasAxes {
            let catTitle = c.categoryAxisTitle.map { _rich($0, size: 1330, rotated: c.type == .bar) } ?? ""
            let valTitle = c.valueAxisTitle.map { _rich($0, size: 1330, rotated: c.type != .bar) } ?? ""
            let catPos = c.type == .bar ? "l" : "b", valPos = c.type == .bar ? "b" : "l"
            let tail = "<c:majorTickMark val=\"none\"/><c:minorTickMark val=\"none\"/><c:tickLblPos val=\"nextTo\"/>"
            let format = c.percent ? "0%" : "General"
            let valAx = "<c:valAx><c:axId val=\"500000002\"/><c:scaling><c:orientation val=\"minMax\"/></c:scaling><c:delete val=\"0\"/><c:axPos val=\"\(valPos)\"/><c:majorGridlines><c:spPr>\(_gridLine)</c:spPr></c:majorGridlines>\(valTitle)<c:numFmt formatCode=\"\(format)\" sourceLinked=\"1\"/>\(tail)<c:spPr><a:noFill/><a:ln><a:noFill/></a:ln></c:spPr><c:crossAx val=\"500000001\"/><c:crosses val=\"autoZero\"/><c:crossBetween val=\"\(c.type == .scatter || c.type == .area ? "midCat" : "between")\"/></c:valAx>"
            if c.type == .scatter {
                plot += "<c:valAx><c:axId val=\"500000001\"/><c:scaling><c:orientation val=\"minMax\"/></c:scaling><c:delete val=\"0\"/><c:axPos val=\"b\"/><c:majorGridlines><c:spPr>\(_gridLine)</c:spPr></c:majorGridlines>\(catTitle)<c:numFmt formatCode=\"General\" sourceLinked=\"1\"/>\(tail)<c:spPr><a:noFill/>\(_gridLine)</c:spPr><c:crossAx val=\"500000002\"/><c:crosses val=\"autoZero\"/><c:crossBetween val=\"midCat\"/></c:valAx>"
            } else {
                plot += "<c:catAx><c:axId val=\"500000001\"/><c:scaling><c:orientation val=\"minMax\"/></c:scaling><c:delete val=\"0\"/><c:axPos val=\"\(catPos)\"/>\(catTitle)<c:numFmt formatCode=\"General\" sourceLinked=\"1\"/>\(tail)<c:spPr><a:noFill/>\(_gridLine)</c:spPr><c:crossAx val=\"500000002\"/><c:crosses val=\"autoZero\"/><c:auto val=\"1\"/><c:lblAlgn val=\"ctr\"/><c:lblOffset val=\"100\"/><c:noMultiLvlLbl val=\"0\"/></c:catAx>"
            }
            plot += valAx
        }
        let title = c.title.map { _rich($0, size: 1862) } ?? ""
        let legend = c.legend ? "<c:legend><c:legendPos val=\"b\"/><c:overlay val=\"0\"/></c:legend>" : ""
        let text = "<c:txPr><a:bodyPr/><a:lstStyle/><a:p><a:pPr><a:defRPr sz=\"1200\"><a:solidFill><a:schemeClr val=\"tx1\"><a:lumMod val=\"65000\"/><a:lumOff val=\"35000\"/></a:schemeClr></a:solidFill></a:defRPr></a:pPr><a:endParaRPr lang=\"en-US\"/></a:p></c:txPr>"
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <c:chartSpace xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><c:date1904 val="0"/><c:lang val="en-US"/><c:roundedCorners val="0"/><c:chart>\(title)<c:autoTitleDeleted val="\(c.title == nil ? 1 : 0)"/><c:plotArea><c:layout/>\(plot)</c:plotArea>\(legend)<c:plotVisOnly val="1"/><c:dispBlanksAs val="gap"/></c:chart><c:spPr><a:noFill/><a:ln><a:noFill/></a:ln></c:spPr>\(text)<c:externalData r:id="rId1"><c:autoUpdate val="0"/></c:externalData></c:chartSpace>
        """
    }

    /// The chart's data as a one-sheet workbook: categories down column A,
    /// a series per column from B, names in row 1 — the table PowerPoint's
    /// Edit Data opens.
    static func workbook(_ c: Chart) throws -> Data {
        func cell(_ ref: String, _ s: String) -> String {
            "<c r=\"\(ref)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(_esc(s))</t></is></c>"
        }
        let seriesList = c.type == .pie ? Array(c.series.prefix(1)) : c.series
        var rows = "<row r=\"1\">" + seriesList.enumerated().map { cell("\(column($0.offset + 1))1", $0.element.name) }.joined() + "</row>"
        for (r, name) in c.categories.enumerated() {
            let row = r + 2
            var xml = c.type == .scatter ? "<c r=\"A\(row)\"><v>\(number(c.x(r)))</v></c>" : cell("A\(row)", name)
            for (i, s) in seriesList.enumerated() {
                if r < s.values.count, let v = s.values[r] { xml += "<c r=\"\(column(i + 1))\(row)\"><v>\(number(v))</v></c>" }
            }
            rows += "<row r=\"\(row)\">\(xml)</row>"
        }
        let main = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
        let rel = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
        let head = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
        let entries = [
            ZipEntry(name: "[Content_Types].xml", data: Data((head + "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/><Override PartName=\"/xl/worksheets/sheet1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/></Types>").utf8)),
            ZipEntry(name: "_rels/.rels", data: Data((head + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"\(rel)/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>").utf8)),
            ZipEntry(name: "xl/workbook.xml", data: Data((head + "<workbook xmlns=\"\(main)\" xmlns:r=\"\(rel)\"><sheets><sheet name=\"Sheet1\" sheetId=\"1\" r:id=\"rId1\"/></sheets></workbook>").utf8)),
            ZipEntry(name: "xl/_rels/workbook.xml.rels", data: Data((head + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"\(rel)/worksheet\" Target=\"worksheets/sheet1.xml\"/></Relationships>").utf8)),
            ZipEntry(name: "xl/worksheets/sheet1.xml", data: Data((head + "<worksheet xmlns=\"\(main)\" xmlns:r=\"\(rel)\"><sheetData>\(rows)</sheetData></worksheet>").utf8)),
        ]
        return try Zip.write(entries)
    }
}

// MARK: - Drawing

/// Draws a chart into a rectangle, PowerPoint's default look: title on
/// top, legend at the bottom, light horizontal gridlines, no axis lines
/// but the category one, text in the theme's text colour at 65%.
enum ChartPainter {
    static func paint(_ c: Chart, _ canvas: any Canvas, _ r: Rect, pxPerPt k: Double, theme: DeckTheme) {
        guard r.width > 4, r.height > 4, !c.series.isEmpty else { return }
        let ink = _mix(theme.text, theme.background, 0.65)
        let grid = _mix(theme.text, theme.background, 0.15)
        let font = OfficeFonts.substitute(theme.bodyFont)
        func text(_ s: String, _ size: Double, _ maxWidth: Double = .infinity) -> TextPainter {
            let tp = TextPainter(text: TextSpan(text: s, style: Flutter.TextStyle(
                color: ink, fontSize: max(3, size * k), fontFamily: font)), textDirection: .ltr)
            tp.layout(minWidth: 0, maxWidth: max(1, maxWidth))
            return tp
        }
        canvas.save()
        canvas.clipRect(r)
        var area = r.deflate(9 * k)

        if let title = c.title, !title.isEmpty {
            let tp = text(title, 18.6, area.width)
            tp.paint(canvas, Offset(area.center.dx - tp.width / 2, area.top))
            area = Rect.fromLTRB(area.left, area.top + tp.height + 6 * k, area.right, area.bottom)
            tp.dispose()
        }

        // The legend: one row of key + name, centred, wrapped when wide.
        let pie = c.type == .pie
        if c.legend {
            let names = pie ? c.categories : c.series.map(\.name)
            let entries = names.enumerated().map { (i: $0.offset, tp: text($0.element, 12)) }
            let key = 7 * k, gap = 4 * k, spacing = 12 * k
            var lines: [[(i: Int, tp: TextPainter)]] = [[]]
            var lineW = 0.0
            for e in entries {
                let w = key + gap + e.tp.width
                if lineW > 0, lineW + spacing + w > area.width { lines.append([]); lineW = 0 }
                lineW += (lineW > 0 ? spacing : 0) + w
                lines[lines.count - 1].append(e)
            }
            let lineH = (entries.map(\.tp.height).max() ?? 12 * k)
            var y = area.bottom - lineH * Double(lines.count)
            area = Rect.fromLTRB(area.left, area.top, area.right, y - 6 * k)
            for line in lines {
                let w = line.reduce(0.0) { $0 + key + gap + $1.tp.width } + spacing * Double(max(0, line.count - 1))
                var x = area.center.dx - w / 2
                for e in line {
                    let p = Paint()
                    p.style = .fill
                    p.isAntiAlias = true
                    p.color = pie ? Chart.cycle(e.i, theme.accents) : c.color(series: e.i, accents: theme.accents)
                    if c.type == .line {
                        p.style = .stroke
                        p.strokeWidth = 2.25 * k
                        canvas.drawLine(Offset(x - 2 * k, y + lineH / 2), Offset(x + key + 2 * k, y + lineH / 2), p)
                    } else if c.type == .scatter {
                        canvas.drawCircle(Offset(x + key / 2, y + lineH / 2), 2.5 * k, p)
                    } else {
                        canvas.drawRect(Rect.fromLTWH(x, y + (lineH - key) / 2, key, key), p)
                    }
                    e.tp.paint(canvas, Offset(x + key + gap, y))
                    x += key + gap + e.tp.width + spacing
                }
                y += lineH
            }
            for line in lines { for e in line { e.tp.dispose() } }
        }

        if pie {
            _pie(c, canvas, area, k: k, theme: theme, text: text)
        } else {
            _axes(c, canvas, area, k: k, theme: theme, grid: grid, text: text)
        }
        canvas.restore()
    }

    private static func _mix(_ a: Color, _ b: Color, _ t: Double) -> Color {
        func ch(_ v: Int, _ s: Int) -> Int { (v >> s) & 0xFF }
        func m(_ s: Int) -> Int { Int((Double(ch(a.value, s)) * t + Double(ch(b.value, s)) * (1 - t)).rounded()) }
        return Color(0xFF00_0000 | Int64((m(16) << 16) | (m(8) << 8) | m(0)))
    }

    /// Round axis bounds and a step, Excel's way: about five to ten
    /// gridlines, 5% headroom above the data.
    static func scale(_ lo0: Double, _ hi0: Double) -> (lo: Double, hi: Double, step: Double) {
        var lo = min(0, lo0), hi = max(0, hi0)
        if hi == lo { hi = lo + 1 }
        let span = hi - lo
        if hi > 0 { hi += span * 0.05 }
        if lo < 0 { lo -= span * 0.05 }
        let rough = (hi - lo) / 6
        let mag = pow(10, floor(log10(rough)))
        let norm = rough / mag
        let step = (norm <= 1 ? 1 : norm <= 2 ? 2 : norm <= 5 ? 5 : 10) * mag
        return (floor(lo / step) * step, ceil(hi / step) * step, step)
    }

    static func label(_ v: Double, percent: Bool) -> String {
        if percent { return "\(Int((v * 100).rounded()))%" }
        if abs(v - v.rounded()) < 1e-9 { return String(Int(v.rounded())) }
        var s = String(printf: "%.2f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    private static func _axes(_ c: Chart, _ canvas: any Canvas, _ area0: Rect, k: Double, theme: DeckTheme,
                              grid: Color, text: (String, Double, Double) -> TextPainter) {
        let n = c.categories.count
        guard n > 0 else { return }
        let horizontal = c.type == .bar
        // The values the value axis spans: per point, or per stacked total.
        var lo = 0.0, hi = 0.0
        if c.percent {
            hi = 1
        } else if c.stacked {
            for i in 0 ..< n {
                var pos = 0.0, neg = 0.0
                for s in c.series { if let v = s.values[safe: i] ?? nil { if v >= 0 { pos += v } else { neg += v } } }
                hi = max(hi, pos); lo = min(lo, neg)
            }
        } else {
            let all = c.series.flatMap { $0.values.compactMap { $0 } }
            lo = all.min() ?? 0; hi = all.max() ?? 1
        }
        let sc = c.percent ? (lo: 0.0, hi: 1.0, step: 0.1) : scale(lo, hi)
        var xs = (lo: 0.0, hi: Double(n), step: 1.0)
        if c.type == .scatter {
            let x = (0 ..< n).map { c.x($0) }
            xs = scale(x.min() ?? 0, x.max() ?? 1)
        }
        var area = area0
        // Axis titles take a band at the side and bottom.
        let titleSize = 13.3
        if let t = c.valueAxisTitle {
            let tp = text(t, titleSize, horizontal ? area.width : area.height)
            if horizontal {
                tp.paint(canvas, Offset(area.center.dx - tp.width / 2, area.bottom - tp.height))
                area = Rect.fromLTRB(area.left, area.top, area.right, area.bottom - tp.height - 4 * k)
            } else {
                canvas.save()
                canvas.translate(area.left, area.center.dy + tp.width / 2)
                canvas.rotate(-.pi / 2)
                tp.paint(canvas, .zero)
                canvas.restore()
                area = Rect.fromLTRB(area.left + tp.height + 4 * k, area.top, area.right, area.bottom)
            }
            tp.dispose()
        }
        if let t = c.categoryAxisTitle {
            let tp = text(t, titleSize, horizontal ? area.height : area.width)
            if horizontal {
                canvas.save()
                canvas.translate(area.left, area.center.dy + tp.width / 2)
                canvas.rotate(-.pi / 2)
                tp.paint(canvas, .zero)
                canvas.restore()
                area = Rect.fromLTRB(area.left + tp.height + 4 * k, area.top, area.right, area.bottom)
            } else {
                tp.paint(canvas, Offset(area.center.dx - tp.width / 2, area.bottom - tp.height))
                area = Rect.fromLTRB(area.left, area.top, area.right, area.bottom - tp.height - 4 * k)
            }
            tp.dispose()
        }

        // Tick labels: values along one axis, categories (or x values) along the other.
        let ticks = Array(stride(from: sc.lo, through: sc.hi + sc.step / 2, by: sc.step))
        let valueLabels = ticks.map { text(label($0, percent: c.percent), 12, .infinity) }
        let catLabels: [TextPainter]
        if c.type == .scatter {
            catLabels = Array(stride(from: xs.lo, through: xs.hi + xs.step / 2, by: xs.step)).map { text(label($0, percent: false), 12, .infinity) }
        } else {
            let slot = (horizontal ? area.height : area.width) / Double(n)
            catLabels = c.categories.map { text($0, 12, horizontal ? area.width * 0.3 : max(slot - 2 * k, 8 * k)) }
        }
        let lineH = valueLabels.first?.height ?? 12 * k
        let plot: Rect
        if horizontal {
            let left = (catLabels.map(\.width).max() ?? 0) + 6 * k
            plot = Rect.fromLTRB(area.left + left, area.top + 2 * k, area.right - (valueLabels.last?.width ?? 0) / 2,
                                 area.bottom - lineH - 4 * k)
        } else {
            var left = (valueLabels.map(\.width).max() ?? 0) + 6 * k
            let bottom = (catLabels.map(\.height).max() ?? lineH) + 4 * k
            // Labels centred on the plot's edges (an area's first and last
            // categories, a scatter's end ticks) need half their width free.
            let edges = c.type == .scatter || c.type == .area
            var right = edges ? (catLabels.last?.width ?? 0) / 2 : 4 * k
            if edges { left = max(left, (catLabels.first?.width ?? 0) / 2); right = max(right, 4 * k) }
            plot = Rect.fromLTRB(area.left + left, area.top + lineH / 2, area.right - right, area.bottom - bottom)
        }
        guard plot.width > 4, plot.height > 4 else {
            for t in valueLabels + catLabels { t.dispose() }
            return
        }
        func vpos(_ v: Double) -> Double {
            let t = (v - sc.lo) / (sc.hi - sc.lo)
            return horizontal ? plot.left + t * plot.width : plot.bottom - t * plot.height
        }
        let gridPaint = Paint()
        gridPaint.style = .stroke
        gridPaint.strokeWidth = max(0.5, 0.75 * k)
        gridPaint.color = grid
        for (i, v) in ticks.enumerated() {
            let p = vpos(v)
            let tp = valueLabels[i]
            if horizontal {
                canvas.drawLine(Offset(p, plot.top), Offset(p, plot.bottom), gridPaint)
                tp.paint(canvas, Offset(p - tp.width / 2, plot.bottom + 4 * k))
            } else {
                canvas.drawLine(Offset(plot.left, p), Offset(plot.right, p), gridPaint)
                tp.paint(canvas, Offset(plot.left - 6 * k - tp.width, p - tp.height / 2))
            }
        }
        // The category axis line, at zero.
        let zero = vpos(max(sc.lo, min(sc.hi, 0)))
        if c.type == .scatter {
            let xTicks = Array(stride(from: xs.lo, through: xs.hi + xs.step / 2, by: xs.step))
            for (i, v) in xTicks.enumerated() {
                let x = plot.left + (v - xs.lo) / (xs.hi - xs.lo) * plot.width
                canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), gridPaint)
                if i < catLabels.count { catLabels[i].paint(canvas, Offset(x - catLabels[i].width / 2, plot.bottom + 4 * k)) }
            }
        } else if horizontal {
            canvas.drawLine(Offset(zero, plot.top), Offset(zero, plot.bottom), gridPaint)
            let slot = plot.height / Double(n)
            for (i, tp) in catLabels.enumerated() {
                // Category 1 at the bottom, as PowerPoint draws a bar chart.
                let cy = plot.bottom - (Double(i) + 0.5) * slot
                tp.paint(canvas, Offset(plot.left - 6 * k - tp.width, cy - tp.height / 2))
            }
        } else {
            canvas.drawLine(Offset(plot.left, zero), Offset(plot.right, zero), gridPaint)
            let slot = plot.width / Double(n)
            for (i, tp) in catLabels.enumerated() {
                let cx = c.type == .area && n > 1 ? plot.left + Double(i) * plot.width / Double(n - 1) : plot.left + (Double(i) + 0.5) * slot
                tp.paint(canvas, Offset(cx - tp.width / 2, plot.bottom + 4 * k))
            }
        }
        for t in valueLabels + catLabels { t.dispose() }

        var labels: [(String, Offset)] = []
        let fill = Paint()
        fill.style = .fill
        fill.isAntiAlias = true
        let s = c.series.count
        func total(_ i: Int) -> Double {
            c.series.reduce(0.0) { $0 + abs(($1.values[safe: i] ?? nil) ?? 0) }
        }
        func scaled(_ v: Double, _ i: Int) -> Double {
            guard c.percent else { return v }
            let t = total(i)
            return t > 0 ? v / t : 0
        }

        switch c.type {
        case .column, .bar:
            let slot = (horizontal ? plot.height : plot.width) / Double(n)
            // A category's slot holds its bars plus one gap; bars step by
            // (1 - overlap) of a bar, so a stacked chart's sit on one another.
            let lanes = c.stacked ? 1.0 : Double(s)
            let pitch = c.stacked ? 0 : 1 - c.overlapFraction
            let bar = slot / (1 + (lanes - 1) * pitch + c.gap)
            let step = bar * pitch
            let group = bar + (lanes - 1) * step
            for i in 0 ..< n {
                var pos = 0.0, neg = 0.0
                // Series 1 nearest the origin: leftmost in a column group,
                // lowest in a bar group.
                let centre = horizontal ? plot.bottom - (Double(i) + 0.5) * slot : plot.left + (Double(i) + 0.5) * slot
                for j in 0 ..< s {
                    guard let raw = c.series[j].values[safe: i] ?? nil else { continue }
                    let v = scaled(raw, i)
                    var a = 0.0, b = v
                    if c.stacked {
                        if v >= 0 { a = pos; pos += v; b = pos } else { a = neg; neg += v; b = neg }
                    }
                    fill.color = c.color(series: j, accents: theme.accents)
                    let p0 = vpos(a), p1 = vpos(b)
                    let rect: Rect
                    if horizontal {
                        let top = centre + group / 2 - Double(j) * step - bar
                        rect = Rect.fromLTRB(min(p0, p1), top, max(p0, p1), top + bar)
                        labels.append((label(raw, percent: false), Offset(c.stacked ? rect.center.dx : max(p0, p1) + 3 * k, rect.center.dy)))
                    } else {
                        let left = centre - group / 2 + Double(j) * step
                        rect = Rect.fromLTRB(left, min(p0, p1), left + bar, max(p0, p1))
                        labels.append((label(raw, percent: false), Offset(rect.center.dx, c.stacked ? rect.center.dy : min(p0, p1) - 8 * k)))
                    }
                    canvas.drawRect(rect, fill)
                }
            }
        case .line, .area:
            // An area's points sit on the category edges, a line's mid-slot.
            let onEdges = c.type == .area && n > 1
            func xAt(_ i: Int) -> Double {
                let t: Double = onEdges ? Double(i) / Double(n - 1) : (Double(i) + 0.5) / Double(n)
                return plot.left + t * plot.width
            }
            var base = [Double](repeating: 0, count: n)
            var tops: [[Double?]] = []
            for j in 0 ..< s {
                var row: [Double?] = []
                for i in 0 ..< n {
                    guard let raw = c.series[j].values[safe: i] ?? nil else { row.append(c.stacked ? base[i] : nil); continue }
                    let v = scaled(raw, i) + (c.stacked ? base[i] : 0)
                    row.append(v)
                    labels.append((label(raw, percent: false), Offset(xAt(i), vpos(v) - 9 * k)))
                }
                if c.stacked { for i in 0 ..< n { base[i] = row[i] ?? base[i] } }
                tops.append(row)
            }
            // In series order: the first drawn behind the rest; stacked,
            // each sits on the one before.
            for j in 0 ..< s {
                let color = c.color(series: j, accents: theme.accents)
                if c.type == .area {
                    let path = Path()
                    let lower: [Double] = c.stacked && j > 0 ? tops[j - 1].map { $0 ?? 0 } : [Double](repeating: 0, count: n)
                    path.moveTo(xAt(0), vpos(lower[0]))
                    for i in 0 ..< n { path.lineTo(xAt(i), vpos(tops[j][i] ?? lower[i])) }
                    for i in stride(from: n - 1, through: 0, by: -1) { path.lineTo(xAt(i), vpos(lower[i])) }
                    path.close()
                    fill.color = color
                    canvas.drawPath(path, fill)
                } else {
                    let p = Paint()
                    p.style = .stroke
                    p.isAntiAlias = true
                    p.strokeWidth = max(1, 2.25 * k)
                    p.strokeCap = .round
                    p.strokeJoin = .round
                    p.color = color
                    let path = Path()
                    var pen = false
                    for i in 0 ..< n {
                        guard let v = tops[j][i] else { pen = false; continue }
                        if pen { path.lineTo(xAt(i), vpos(v)) } else { path.moveTo(xAt(i), vpos(v)); pen = true }
                    }
                    canvas.drawPath(path, p)
                }
            }
        case .scatter:
            for j in 0 ..< s {
                fill.color = c.color(series: j, accents: theme.accents)
                for i in 0 ..< n {
                    guard let v = c.series[j].values[safe: i] ?? nil else { continue }
                    let x = plot.left + (c.x(i) - xs.lo) / (xs.hi - xs.lo) * plot.width
                    canvas.drawCircle(Offset(x, vpos(v)), max(1.5, 2.5 * k), fill)
                    labels.append((label(v, percent: false), Offset(x, vpos(v) - 9 * k)))
                }
            }
        case .pie:
            break
        }
        if c.dataLabels {
            for (s, at) in labels {
                let tp = text(s, 12, .infinity)
                let dx = horizontal && !c.stacked ? 0 : tp.width / 2
                tp.paint(canvas, Offset(at.dx - dx, at.dy - tp.height / 2))
                tp.dispose()
            }
        }
    }

    private static func _pie(_ c: Chart, _ canvas: any Canvas, _ area: Rect, k: Double, theme: DeckTheme,
                             text: (String, Double, Double) -> TextPainter) {
        let values = c.series[0].values.map { max(0, $0 ?? 0) }
        let sum = values.reduce(0, +)
        guard sum > 0 else { return }
        let radius = min(area.width, area.height) / 2 * 0.92
        let centre = area.center
        let oval = Rect.fromCircle(center: centre, radius: radius)
        var angle = -Double.pi / 2
        let fill = Paint()
        fill.style = .fill
        fill.isAntiAlias = true
        let edge = Paint()
        edge.style = .stroke
        edge.isAntiAlias = true
        edge.strokeWidth = max(0.5, 1.5 * k)
        edge.color = theme.background
        var labels: [(String, Offset, Color)] = []
        for (i, v) in values.enumerated() where v > 0 {
            let sweep = v / sum * 2 * .pi
            let color = Chart.cycle(i, theme.accents)
            fill.color = color
            canvas.drawArc(oval, angle, sweep, true, fill)
            canvas.drawArc(oval, angle, sweep, true, edge)
            let mid = angle + sweep / 2
            labels.append((label(c.series[0].values[i] ?? 0, percent: false),
                           Offset(centre.dx + cos(mid) * radius * 0.7, centre.dy + sin(mid) * radius * 0.7), color))
            angle += sweep
        }
        if c.dataLabels {
            for (s, at, wedge) in labels {
                // Inside the wedge: white on a dark one, ink on a light one.
                let v = wedge.value
                let luma = 0.299 * Double((v >> 16) & 0xFF) + 0.587 * Double((v >> 8) & 0xFF) + 0.114 * Double(v & 0xFF)
                let tp = TextPainter(text: TextSpan(text: s, style: Flutter.TextStyle(
                    color: luma < 150 ? Color(0xFFFFFFFF) : Color(0xFF404040), fontSize: max(3, 12 * k),
                    fontFamily: OfficeFonts.substitute(theme.bodyFont))), textDirection: .ltr)
                tp.layout(minWidth: 0, maxWidth: .infinity)
                tp.paint(canvas, Offset(at.dx - tp.width / 2, at.dy - tp.height / 2))
                tp.dispose()
            }
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
