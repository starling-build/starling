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
    case column, bar, line, pie, area, scatter, doughnut, radar

    var name: String {
        switch self {
        case .column: return "Column"
        case .bar: return "Bar"
        case .line: return "Line"
        case .pie: return "Pie"
        case .area: return "Area"
        case .scatter: return "Scatter"
        case .doughnut: return "Doughnut"
        case .radar: return "Radar"
        }
    }

    var hasAxes: Bool { !isPie }
    /// Wedges of one series: a pie, or a doughnut (a pie with a hole).
    var isPie: Bool { self == .pie || self == .doughnut }

    var icon: IconData {
        switch self {
        case .column: return FluentSystemIcons.chartColumn
        case .bar: return FluentSystemIcons.chartBar
        case .line: return FluentSystemIcons.chartLine
        case .pie: return FluentSystemIcons.chartPie
        case .area: return FluentSystemIcons.chartArea
        case .scatter: return FluentSystemIcons.chartScatter
        case .doughnut: return FluentSystemIcons.chartPie
        case .radar: return FluentSystemIcons.chartLine
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
    /// A scatter series whose points are joined by its line (the file gave
    /// the series a line, or the chart's style is one with lines).
    var joined = false
    /// Labels whose text is another row of the sheet's ("Value From
    /// Cells": `c15:datalabelsRange`), by point, as the file last had
    /// them; and the size, weight and colour the series' labels are set in.
    var cellLabels: [Int: String] = [:]
    var labelSize: Double? = nil
    var labelBold = false
    var labelColor: Color? = nil
    /// The outline round a bar or slice (`c:spPr/a:ln`), and its width in
    /// points; nil is none.
    var outline: Color? = nil
    var outlineWidth = 0.75
    /// A line series' marks (`c:marker`): the symbol ("circle", "square",
    /// "diamond", "triangle"…; nil or "none" is none), its size in points
    /// and colours, the points that show none (`c:dPt` with symbol none),
    /// and whether the line between them is hidden (`a:ln/a:noFill`).
    var marker: String? = nil
    var markerSize = 5.0
    var markerFill: Color? = nil
    var markerLine: Color? = nil
    var unmarked: Set<Int> = []
    var lineHidden = false
}

struct Chart: Equatable {
    var type: ChartType
    /// Shown above the plot; nil for none.
    var title: String?
    /// The title's own size in points, weight and colour where the file
    /// gives them (its first run's, else the title's default run
    /// properties); nil is PowerPoint's default for a chart title.
    var titleSize: Double? = nil
    var titleBold = false
    var titleColor: Color? = nil
    /// The first column of the data: category names, or for a scatter
    /// chart the x values.
    var categories: [String]
    var series: [ChartSeries]
    var legend = true
    /// `c:legendPos`: "b" below the plot (what a new chart gets), "t" above,
    /// "r", "l" or "tr" beside it, one entry to a line.
    var legendPosition = "b"
    /// The legend's text size in points where the file gives one
    /// (`c:legend/c:txPr`); nil is the default, 12.
    var legendSize: Double? = nil
    var dataLabels = false
    /// `c:grouping`: clustered/standard, stacked or percentStacked.
    var stacked = false
    var percent = false
    var categoryAxisTitle: String? = nil
    var valueAxisTitle: String? = nil
    /// The value axis's labels' size in points where the file gives one
    /// (`c:valAx/c:txPr`); nil is the default, 12. It also decides how
    /// many marks the axis has room for.
    var valueLabelSize: Double? = nil
    /// The category axis's labels' size and weight where the file gives
    /// them (`c:catAx/c:txPr`); nil is the default, 12.
    var categoryLabelSize: Double? = nil
    var categoryLabelBold = false
    /// The turn the file gives the category labels (`c:txPr/a:bodyPr rot`),
    /// degrees, anticlockwise positive: 45 for aascu 5864's country names.
    /// nil where it gives none, and the labels are set aslant only when
    /// they do not fit.
    var categoryLabelTurn: Double? = nil
    /// The axes' label colours where the file gives them, and whether the
    /// value axis's are bold.
    var categoryLabelColor: Color? = nil
    var valueLabelColor: Color? = nil
    var valueLabelBold = false
    /// The plot area's border and the value gridlines' colour and width
    /// (points), where the file gives them.
    var plotBorder: Color? = nil
    var plotBorderWidth = 0.75
    var gridColor: Color? = nil
    var gridWidth: Double? = nil
    /// The value axis's number format, an Excel format code ("#,##0"),
    /// where the file gives one other than General: the axis's own, or —
    /// "linked to source" — the one its first series' numbers came with.
    var valueFormat: String? = nil
    /// A bar chart's spacing as the file set it, in percent of a bar:
    /// the gap between categories and the overlap of a category's bars.
    /// Nil is PowerPoint's default (219 and -27; 150 and 100 stacked).
    var gapWidth: Int? = nil
    var overlap: Int? = nil
    /// A doughnut's hole, in percent of its diameter (`c:holeSize`).
    var holeSize = 50
    /// A radar chart's series filled (`c:radarStyle val="filled"`), not
    /// lines.
    var radarFilled = false
    /// A column chart's series drawn as lines over the columns, on the same
    /// axes (a combination: a `c:barChart` and a `c:lineChart` sharing
    /// theirs — aascu 5864's 1995 graduation rates as red dots over the
    /// 2005 columns).
    var lineSeries: [ChartSeries] = []
    /// The legend's own place (`c:legend/c:layout/c:manualLayout`, edge
    /// mode), as fractions of the chart's frame: entries in a row in it,
    /// the plot keeping its room. nil: beside the plot by `legendPosition`.
    var legendBox: Rect? = nil
    /// A 3-D pie's tilt toward the viewer (`c:view3D/c:rotX`, degrees): drawn
    /// as a disc seen from above at that angle, its rim showing below. nil
    /// is a flat pie.
    var pieTilt: Double? = nil
    /// How far a 3-D pie's slices are pulled out (`c:explosion`, the
    /// largest of the series' and its points'), as a fraction of the
    /// radius: the pie is that much smaller, to leave them room.
    var pieExplosion: Double = 0
    /// A 3-D bar or column chart's view (`c:view3D` rotX, rotY, degrees):
    /// each bar a box, its top and side showing, in a box of its own — a
    /// floor and walls one category deep (`depthPercent` of it), the bars
    /// standing in the middle of that depth with `gapDepth` of their own
    /// depth about them. nil is flat.
    var barView: BarView? = nil
    struct BarView: Equatable { var x: Double; var y: Double; var depth: Double = 1; var gapDepth: Double = 1.5 }
    /// The value axis's bounds and step where the file fixes them
    /// (`c:scaling/c:min`, `c:max`, `c:majorUnit`); nil is automatic.
    var valueMin: Double? = nil
    var valueMax: Double? = nil
    var valueStep: Double? = nil
    /// The data labels' number format where it is not General: the
    /// labels' own (`c:dLbls/c:numFmt`), else the numbers' (`formatCode`).
    var labelFormat: String? = nil
    /// Where the file places the plot (`c:plotArea/c:layout/c:manualLayout`
    /// in edge mode): fractions of the chart's frame, and whether that is
    /// the plot itself (`inner`) or the plot with its axis labels.
    var plotLayout: Rect? = nil
    var plotLayoutInner = false
    /// Office 2007's chart style (`c:style`, 1–48): eight columns of
    /// colour — greys, the accents, then one accent each in shades — by
    /// six rows of effects. nil for none (PowerPoint's default, 2).
    var style: Int? = nil
    /// The accent (1–6) a monochrome style shades every series from.
    var monochromeAccent: Int? {
        guard let s = style, (1 ... 48).contains(s) else { return nil }
        let column = (s - 1) % 8
        return column >= 2 ? column - 1 : nil
    }
    /// A pie's slices in their own colours (`c:dPt`), by index.
    var pointColors: [Int: Color] = [:]
    /// The chart's own text size (`c:chartSpace/c:txPr`) where it is not
    /// the usual 12: what its labels and legend are set in when they say
    /// nothing, and an unsized title 1.2 times it.
    var textSize: Double? = nil
    /// The chart's text colour (`c:chartSpace/c:txPr`) and its legend's
    /// (`c:legend/c:txPr`), where the file gives them. `plainText`: the
    /// chart gives its text no colour at all, and it is the theme's text
    /// colour — POI's 2007-style charts are black in PowerPoint's print;
    /// otherwise (a new chart, PowerPoint 2013's own) it is that colour
    /// at 65%, which the file spells `tx1` lumMod 65% lumOff 35%.
    var textColor: Color? = nil
    /// The face the chart names for its text (`c:chartSpace/c:txPr`) and
    /// for its title, where they name one rather than the theme's.
    var font: String? = nil
    var titleFont: String? = nil
    var legendColor: Color? = nil
    var legendBold = false
    var plainText = false
    /// The labels' and legend's size where nothing says one: PowerPoint
    /// 2013's 12 pt for a chart that colours its text (as a new chart
    /// does), the 2007 default of 10 for one that says nothing at all —
    /// aascu 5864's children's-skills charts, 10 pt in PowerPoint's print.
    var baseTextSize: Double { textSize ?? (plainText && !styled2013 ? 10 : 12) }
    /// Text anywhere in the chart set in PowerPoint 2013's grey (`tx1` at
    /// lumMod 65%): a chart of that kind, whose unstated sizes are 12. A
    /// new chart is one (and is written so).
    var styled2013 = true
    /// The plot area's own fill (`c:plotArea/c:spPr`).
    var plotFill: Color? = nil
    /// The chart area's own fill and outline (`c:chartSpace/c:spPr`), or
    /// `noFill`/`noLine` where it says there is none — what this app writes
    /// for a chart of its own, and so the default. A file that gives no
    /// `c:spPr` has neither (a sheet's chart is then white with a light grey
    /// edge, Excel's look). Written back as read.
    var areaFill: Color? = nil
    var areaNoFill = true
    var areaLine: Color? = nil
    var areaLineWidth: Double? = nil
    var areaNoLine = true
    /// A pie's or doughnut's labels where the file asks more of them than
    /// their values inside the slices (`c:dLbls`): what they say — series,
    /// category, value, percent, joined by the separator — whether they
    /// stand outside (`outEnd`, `bestFit`), each point's own move
    /// (`c:dLbl/c:layout`, fractions of the chart's frame), their box and
    /// their leader lines. nil: the plain labels `dataLabels` asks for.
    struct PieLabels: Equatable {
        var series = false, category = false, value = false, percent = false
        var separator: String? = nil
        var outside = false
        var moves: [Int: [Double]] = [:]
        /// A point's own text size, from its label's own rich text.
        var sizes: [Int: Double] = [:]
        var fill: Color? = nil
        var line: Color? = nil
        var lineWidth = 0.75
        var leaders = false
        var leaderColor: Color? = nil
        var leaderWidth = 0.75
    }
    var pieLabels: PieLabels? = nil

    /// The chart with every text size the file states times `f`, those it
    /// leaves to the default as they are. A sheet's chart is painted at
    /// three quarters of the page's scale, which makes PowerPoint's default
    /// sizes Excel's (18.6 and 12 pt against 14 and 9); a size the file
    /// states Excel prints as stated — 45544's 16 pt title at 14.4 on a
    /// 90% page, where ours made 10.8 — so the sheet scales those back.
    func statedTextScaled(by f: Double) -> Chart {
        var c = self
        c.titleSize = titleSize.map { $0 * f }
        c.legendSize = legendSize.map { $0 * f }
        c.valueLabelSize = valueLabelSize.map { $0 * f }
        c.categoryLabelSize = categoryLabelSize.map { $0 * f }
        c.textSize = textSize.map { $0 * f }
        for i in c.series.indices { c.series[i].labelSize = series[i].labelSize.map { $0 * f } }
        if var l = pieLabels {
            l.sizes = l.sizes.mapValues { $0 * f }
            c.pieLabels = l
        }
        return c
    }
    /// The value axis draws its gridlines (`c:majorGridlines`).
    var valueGrid = true
    /// An axis the file deletes (`c:delete`): no labels, no room for them.
    var valueAxisDeleted = false
    /// The axes' tick marks stand outside them (`c:majorTickMark` "out" or
    /// "cross"), and the labels stand that much further off.
    var valueTicksOut = false
    /// The chart names an Office chart style (`c:style`): one an Office
    /// application wrote, not LibreOffice.
    var officeStyled = true
    var categoryTicksOut = false
    var categoryAxisDeleted = false

    var gap: Double { Double(gapWidth ?? (stacked ? 150 : 219)) / 100 }
    var overlapFraction: Double { Double(overlap ?? (stacked ? 100 : -27)) / 100 }

    /// PowerPoint's sample data for a freshly inserted chart of `type`.
    static func sample(_ type: ChartType) -> Chart {
        switch type {
        case .pie, .doughnut:
            return Chart(type: type, title: "Sales", categories: ["1st Qtr", "2nd Qtr", "3rd Qtr", "4th Qtr"],
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
        if t.isPie || t == .scatter { c.stacked = false; c.percent = false }
        return c
    }

    /// Series colour `i` against `accents`.
    func color(series i: Int, accents: [Color]) -> Color {
        let s = i < series.count ? series[i] : nil
        if let c = s?.color { return c }
        if let scheme = s?.scheme, scheme.hasPrefix("accent"), let n = Int(scheme.dropFirst(6)), (1 ... 6).contains(n) {
            return accents[n - 1]
        }
        if let k = monochromeAccent { return Self.monochrome(i, of: series.count, accents[k - 1]) }
        return Self.cycle(i, accents)
    }

    /// Slice `i`'s colour: its own, else its style's or the cycle's.
    func pointColor(_ i: Int, accents: [Color]) -> Color {
        if let c = pointColors[i] { return c }
        if let k = monochromeAccent { return Self.monochrome(i, of: categories.count, accents[k - 1]) }
        return Self.cycle(i, accents)
    }

    /// Item `i` of `n` in a monochrome style: shades of the accent for the
    /// first half, tints for the second, in linear light, by 1 − 0.56 of
    /// its place out from the middle (−1 to 1) — the cooper deck's four
    /// series are the accent shaded to 0.58 and 0.85 and tinted to 0.86
    /// and 0.575, to a level each.
    static func monochrome(_ i: Int, of n: Int, _ accent: Color) -> Color {
        guard n > 1 else { return accent }
        let place = Double(2 * i + 1) / Double(n) - 1
        let f = 1 - 0.56 * abs(place)
        func lin(_ c: Int) -> Double { let v = Double(c) / 255; return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        func srgb(_ l: Double) -> Int { let c = l <= 0.0031308 ? l * 12.92 : 1.055 * pow(l, 1 / 2.4) - 0.055; return Int((max(0, min(1, c)) * 255).rounded()) }
        func ch(_ shift: Int) -> Int {
            let l = lin(Int((accent.value >> Int64(shift)) & 0xFF))
            return srgb(place < 0 ? l * f : 1 - (1 - l) * f)
        }
        return Color(0xFF00_0000 | Int64((ch(16) << 16) | (ch(8) << 8) | ch(0)))
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
    /// (radar, stock, surface, combinations) — kept as an object then. A 3-D
    /// chart is drawn as its flat kind, a pie-of-pie as its pie, a bubble
    /// chart as its points: the data where it belongs, without the depth.
    /// `allowEmpty`: a chart with no series is still a chart (Excel draws
    /// its empty frame, and gives it its room on the page).
    static func read(_ space: XNode, allowEmpty: Bool = false, color: (XNode) -> Color?) -> Chart? {
        guard let chart = space.first("c:chart"), let plot = chart.first("c:plotArea") else { return nil }
        let kinds = plot.children.filter { $0.name.hasPrefix("c:") && $0.name.hasSuffix("Chart") }
        // A combination this app draws: columns (or bars) with lines over
        // them, both on one pair of axes.
        var overlay: XNode? = nil
        var main = kinds.first
        if kinds.count == 2, let bar = kinds.first(where: { $0.name == "c:barChart" }),
           let line = kinds.first(where: { $0.name == "c:lineChart" }),
           Set(bar.all("c:axId").compactMap { $0["val"] }) == Set(line.all("c:axId").compactMap { $0["val"] }) {
            main = bar
            overlay = line
        } else if kinds.count != 1 {
            return nil
        }
        guard let el = main else { return nil }
        let type: ChartType
        switch el.name {
        case "c:barChart", "c:bar3DChart": type = el.first("c:barDir")?["val"] == "bar" ? .bar : .column
        case "c:lineChart", "c:line3DChart": type = .line
        // (A stock chart is read as the lines its series are — Excel's
        // high-low-close sets their lines and markers to none, so its
        // axes, labels and legend stand where they belong and its bars
        // are not drawn; chartex's was a grey box.)
        case "c:stockChart": type = .line
        case "c:pieChart", "c:pie3DChart", "c:ofPieChart": type = .pie
        case "c:doughnutChart": type = .doughnut
        case "c:areaChart", "c:area3DChart": type = .area
        case "c:scatterChart", "c:bubbleChart": type = .scatter
        case "c:radarChart": type = .radar
        default: return nil
        }
        let grouping = el.first("c:grouping")?["val"] ?? "standard"
        var categories: [String] = []
        var series: [ChartSeries] = []
        var pointColors: [Int: Color] = [:]
        var named = false
        for ser in el.all("c:ser") {
            let name = ser.first("c:tx").map { _texts($0, "c:v").joined() } ?? "Series \(series.count + 1)"
            if series.isEmpty { named = ser.first("c:tx") != nil }
            let cat = ser.first("c:cat") ?? ser.first("c:xVal")
            let val = ser.first("c:val") ?? ser.first("c:yVal")
            var names = cat.map(_points) ?? []
            // (Numbers named by a format — dates, most often — are shown
            // in it: chartex's radar chart has days 37261 to 37265 in a
            // m/d/yyyy cache, which Word prints as 1/5/2002 to 1/9/2002.
            // The axis' own format wins where it is not the source's.)
            if type != .scatter, let cache = cat?.descendant("c:numCache") {
                let axis = space.descendant("c:catAx")?.first("c:numFmt") ?? space.descendant("c:dateAx")?.first("c:numFmt")
                let own = axis.flatMap { ["0", "false"].contains($0["sourceLinked"] ?? "1") ? $0["formatCode"] : nil }
                if let code = own ?? cache.first("c:formatCode")?.text, !code.isEmpty, code.lowercased() != "general" {
                    names = names.map { name in
                        name.flatMap { Double($0.trimmingWhitespace()) }.map { NumberFormat.format($0, code, width: 40).text.trimmingWhitespace() } ?? name
                    }
                }
            }
            if categories.count < names.count {
                categories = names.enumerated().map { $0.element ?? (categories.indices.contains($0.offset) ? categories[$0.offset] : "") }
            }
            let values = (val.map(_points) ?? []).map { $0.flatMap { Double($0.trimmingWhitespace()) } }
            var s = ChartSeries(name: name, values: values)
            let pr = ser.first("c:spPr")
            if type != .line, type != .scatter, type != .radar, let ln = pr?.first("a:ln"), let f = ln.first("a:solidFill") {
                s.outline = color(f)
                s.outlineWidth = ln["w"].flatMap(Double.init).map { $0 / 12700 } ?? 0.75
            }
            if type == .scatter {
                let style = el.first("c:scatterStyle")?["val"] ?? "marker"
                let ln = pr?.first("a:ln")
                s.joined = ln.map { $0.first("a:noFill") == nil } ?? (style != "marker" && style != "none")
            }
            let fill = type == .line ? pr?.first("a:ln")?.first("a:solidFill")
                : type == .scatter ? ser.first("c:marker")?.first("c:spPr")?.first("a:solidFill") ?? pr?.first("a:ln")?.first("a:solidFill") ?? pr?.first("a:solidFill")
                : pr?.first("a:solidFill")
            // Labels from cells: shown where the series' labels say so, with
            // the text the file cached for each point.
            if let d = ser.first("c:dLbls"), d.descendant("c15:showDataLabelsRange")?["val"] == "1",
               let cache = ser.descendant("c15:dlblRangeCache") {
                for pt in cache.all("c:pt") {
                    if let i = pt["idx"].flatMap(Int.init), let v = pt.first("c:v")?.text, !v.isEmpty { s.cellLabels[i] = v }
                }
                if let run = d.first("c:txPr")?.descendant("a:defRPr") {
                    s.labelSize = run["sz"].flatMap(Double.init).map { $0 / 100 }
                    s.labelBold = ["1", "true"].contains(run["b"] ?? "")
                    if let f = run.first("a:solidFill") { s.labelColor = color(f) }
                }
            }
            // The labels' own look where they give one (aascu 5864's
            // census chart: 14 pt bold), the chart type's labels' else.
            if s.labelSize == nil, let run = (ser.first("c:dLbls") ?? el.first("c:dLbls"))?.first("c:txPr")?.descendant("a:defRPr") {
                s.labelSize = run["sz"].flatMap(Double.init).map { $0 / 100 }
                s.labelBold = ["1", "true"].contains(run["b"] ?? "")
                if let f = run.first("a:solidFill") { s.labelColor = color(f) }
            }
            if series.isEmpty {
                for pt in ser.all("c:dPt") {
                    // (The theme's own cycle is left to follow the theme.)
                    if let i = pt.first("c:idx")?["val"].flatMap(Int.init),
                       let f = pt.first("c:spPr")?.first("a:solidFill"),
                       !(f.first("a:schemeClr").map { _isCycle($0, i) } ?? false), let c = color(f) { pointColors[i] = c }
                }
            }
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
        guard !series.isEmpty || allowEmpty else { return nil }
        // The lines over the columns, with their marks.
        var lines: [ChartSeries] = []
        for ser in overlay?.all("c:ser") ?? [] {
            let name = ser.first("c:tx").map { _texts($0, "c:v").joined() } ?? "Series \(series.count + lines.count + 1)"
            let values = (ser.first("c:val").map(_points) ?? []).map { $0.flatMap { Double($0.trimmingWhitespace()) } }
            var s = ChartSeries(name: name, values: values)
            let ln = ser.first("c:spPr")?.first("a:ln")
            s.lineHidden = ln?.has("a:noFill") ?? false
            if let f = ln?.first("a:solidFill") { s.color = color(f) }
            if let m = ser.first("c:marker") {
                s.marker = m.first("c:symbol")?["val"]
                s.markerSize = m.first("c:size")?["val"].flatMap(Double.init) ?? 5
                if let f = m.first("c:spPr")?.first("a:solidFill") { s.markerFill = color(f) }
                if let f = m.first("c:spPr")?.first("a:ln")?.first("a:solidFill") { s.markerLine = color(f) }
            }
            for pt in ser.all("c:dPt") where pt.first("c:marker")?.first("c:symbol")?["val"] == "none" {
                if let i = pt.first("c:idx")?["val"].flatMap(Int.init) { s.unmarked.insert(i) }
            }
            lines.append(s)
        }
        let n = max(categories.count, series.map(\.values.count).max() ?? 0)
        if categories.count < n { categories += (categories.count ..< n).map { "\($0 + 1)" } }
        for i in series.indices where series[i].values.count < n {
            series[i].values += Array(repeating: nil, count: n - series[i].values.count)
        }

        var title: String? = nil
        let deleted = chart.first("c:autoTitleDeleted")?["val"] == "1"
        var titleSize: Double? = nil, titleBold = false, titleColor: Color? = nil, titleFace: String? = nil
        if let t = chart.first("c:title") {
            // Line by line: a paragraph, or a break inside one, starts a new line.
            let paragraphs = t.first("c:tx")?.first("c:rich")?.all("a:p") ?? []
            let text = paragraphs.isEmpty ? _texts(t, "a:t").joined() : paragraphs.map { p in
                p.children.map { $0.name == "a:br" ? "\n" : $0.name == "a:r" ? ($0.first("a:t")?.text ?? "") : "" }.joined()
            }.joined(separator: "\n")
            // (A lone series titles its chart by its name — and one with
            // no name gives "Chart Title": zh-37b6536f's pie in Word's
            // print, where ours read "Series 1".)
            title = text.isEmpty ? (series.count == 1 && named ? series[0].name : "Chart Title") : text
            // Its look: the first run's, over the paragraph's default run
            // properties, over the title's own (`c:txPr`).
            let run = paragraphs.first?.first("a:r")?.first("a:rPr")
            let defaults = [paragraphs.first?.first("a:pPr")?.first("a:defRPr"),
                            t.first("c:txPr")?.first("a:p")?.first("a:pPr")?.first("a:defRPr")]
            let layers = ([run] + defaults).compactMap { $0 }
            // (18.62 pt is the default, PowerPoint's and what this app writes.)
            titleSize = layers.lazy.compactMap { $0["sz"].flatMap(Double.init) }.first.flatMap { $0 == 1862 ? nil : $0 / 100 }
            // (Bold where nothing says: the five decks of an 18 pt chart
            // whose title says nothing show it bold at 22.)
            titleBold = (layers + [space.first("c:txPr")?.descendant("a:defRPr")].compactMap { $0 }).lazy.compactMap { $0["b"] }.first.map { $0 == "1" || $0 == "true" } ?? true
            for layer in layers where titleColor == nil {
                if let fill = layer.first("a:solidFill") { titleColor = color(fill) }
            }
            titleFace = layers.lazy.compactMap { $0.first("a:latin")?["typeface"] }.first
        } else if !deleted && series.count == 1 && lines.isEmpty && named {
            // (A series with no name of its own gives no title: aascu
            // 5864's census chart has none in PowerPoint, where ours read
            // "Series 1".)
            title = series[0].name
        }
        let spaceRun = space.first("c:txPr")?.descendant("a:defRPr")
        var c = Chart(type: type, title: title, categories: categories, series: series)
        c.lineSeries = lines.map { l in
            var l = l
            if l.values.count < n { l.values += Array(repeating: nil, count: n - l.values.count) }
            return l
        }
        if let sz = spaceRun?["sz"].flatMap(Double.init), sz > 0, sz != 1200, sz != 1197 { c.textSize = sz / 100 }
        func greyText(_ n: XNode) -> Bool {
            if n.name == "a:lumMod", n["val"] == "65000" { return true }
            return n.children.contains(where: greyText)
        }
        c.styled2013 = greyText(space)
        c.officeStyled = space.descendant("c:style") != nil
        if let f = spaceRun?.first("a:solidFill") {
            let mods = f.first("a:schemeClr").map { n in n.children.map { "\($0.name)=\($0["val"] ?? "")" }.sorted() } ?? []
            let standard = f.first("a:schemeClr")?["val"] == "tx1" && mods == ["a:lumMod=65000", "a:lumOff=35000"].sorted()
            if !standard { c.textColor = color(f) }
        } else {
            c.plainText = true
        }
        c.titleSize = titleSize
        c.titleBold = titleBold
        c.titleColor = titleColor
        // (A theme slot, "+mn-lt", is the theme's face: none of its own.)
        func face(_ f: String?) -> String? { f.flatMap { $0.hasPrefix("+") || $0.isEmpty ? nil : $0 } }
        c.font = face(spaceRun?.first("a:latin")?["typeface"])
        c.titleFont = face(titleFace) ?? c.font
        c.legend = chart.first("c:legend") != nil
        // (Absent, the schema's default is the right.)
        if let l = chart.first("c:legend") {
            c.legendPosition = l.first("c:legendPos")?["val"] ?? "r"
            if let sz = l.first("c:txPr")?.descendant("a:defRPr")?["sz"].flatMap(Double.init), sz > 0, sz != 1200, sz != 1197 {
                c.legendSize = sz / 100
            }
            if let f = l.first("c:txPr")?.descendant("a:defRPr")?.first("a:solidFill") { c.legendColor = color(f) }
            c.legendBold = ["1", "true"].contains(l.first("c:txPr")?.descendant("a:defRPr")?["b"] ?? "")
            if let m = l.first("c:layout")?.first("c:manualLayout"),
               (m.first("c:xMode")?["val"] ?? "factor") == "edge", (m.first("c:yMode")?["val"] ?? "factor") == "edge",
               let x = m.first("c:x")?["val"].flatMap(Double.init), let y = m.first("c:y")?["val"].flatMap(Double.init),
               let w = m.first("c:w")?["val"].flatMap(Double.init), let h = m.first("c:h")?["val"].flatMap(Double.init), w > 0, h > 0 {
                c.legendBox = Rect.fromLTWH(x, y, w, h)
            }
        }
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
        if type == .doughnut, let hole = el.first("c:holeSize")?["val"].flatMap(Int.init) { c.holeSize = hole }
        if type == .pie || type == .doughnut, let ser = el.first("c:ser"), let d = ser.first("c:dLbls") ?? el.first("c:dLbls") {
            func on(_ n: XNode?, _ name: String) -> Bool { ["1", "true"].contains(n?.first(name)?["val"] ?? "") }
            var l = Chart.PieLabels()
            l.series = on(d, "c:showSerName"); l.category = on(d, "c:showCatName")
            l.value = on(d, "c:showVal"); l.percent = on(d, "c:showPercent")
            l.separator = d.first("c:separator")?.text
            let pos = d.first("c:dLblPos")?["val"]
            l.outside = pos == "outEnd" || pos == "bestFit"
            for one in d.all("c:dLbl") {
                guard let i = one.first("c:idx")?["val"].flatMap(Int.init) else { continue }
                if one.first("c:dLblPos").map({ ["outEnd", "bestFit"].contains($0["val"] ?? "") }) == true { l.outside = true }
                if let sz = one.first("c:tx")?.descendant("a:rPr")?["sz"].flatMap(Double.init) { l.sizes[i] = sz / 100 }
                if let m = one.first("c:layout")?.first("c:manualLayout"),
                   let x = m.first("c:x")?["val"].flatMap(Double.init), let y = m.first("c:y")?["val"].flatMap(Double.init) {
                    l.moves[i] = [x, y]
                }
            }
            if let sp = d.first("c:spPr") {
                if let f = sp.first("a:solidFill") { l.fill = color(f) }
                if let ln = sp.first("a:ln"), let f = ln.first("a:solidFill") {
                    l.line = color(f)
                    l.lineWidth = ln["w"].flatMap(Double.init).map { $0 / 12700 } ?? 0.75
                }
            }
            l.leaders = on(d, "c:showLeaderLines")
            if let ln = (d.first("c:leaderLines") ?? d.descendant("c15:leaderLines"))?.first("c:spPr")?.first("a:ln") {
                if let f = ln.first("a:solidFill") { l.leaderColor = color(f) }
                l.leaderWidth = ln["w"].flatMap(Double.init).map { $0 / 12700 } ?? 0.75
            }
            // Only what the plain labels do not already draw.
            if l.series || l.category || l.percent || l.outside || !l.moves.isEmpty || l.fill != nil { c.pieLabels = l }
        }
        if type == .radar { c.radarFilled = el.first("c:radarStyle")?["val"] == "filled" }
        if el.name == "c:bar3DChart" {
            let v = chart.first("c:view3D")
            c.barView = Chart.BarView(x: v?.first("c:rotX")?["val"].flatMap(Double.init) ?? 15,
                                      y: v?.first("c:rotY")?["val"].flatMap(Double.init) ?? 20,
                                      depth: (v?.first("c:depthPercent")?["val"].flatMap(Double.init) ?? 100) / 100,
                                      gapDepth: (el.first("c:gapDepth")?["val"].flatMap(Double.init) ?? 150) / 100)
        }
        if el.name == "c:pie3DChart" {
            // (No rotX is 15°: Excel draws 45544's pies the same with none
            // and with 15, and fits them otherwise at 30 and 60.)
            c.pieTilt = chart.first("c:view3D")?.first("c:rotX")?["val"].flatMap(Double.init) ?? 15
            let pulls = el.all("c:ser").flatMap { ser in
                ([ser.first("c:explosion")] + ser.all("c:dPt").map { $0.first("c:explosion") }).compactMap { $0?["val"].flatMap(Double.init) }
            }
            c.pieExplosion = max(0, pulls.max() ?? 0) / 100
        }
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
        let valueAxis = type == .scatter ? axes.first { ["l", "r"].contains($0.first("c:axPos")?["val"] ?? "") }
            : axes.first { $0.name == "c:valAx" }
        if let sz = valueAxis?.first("c:txPr")?.descendant("a:defRPr")?["sz"].flatMap(Double.init), sz > 0, sz != 1200, sz != 1197 {
            c.valueLabelSize = sz / 100
        }
        let categoryAxis = type == .scatter ? axes.first { ["b", "t"].contains($0.first("c:axPos")?["val"] ?? "") }
            : axes.first { $0.name != "c:valAx" }
        c.categoryTicksOut = ["out", "cross"].contains(categoryAxis?.first("c:majorTickMark")?["val"] ?? "")
        if let run = categoryAxis?.first("c:txPr")?.descendant("a:defRPr") {
            if let sz = run["sz"].flatMap(Double.init), sz > 0, sz != 1200, sz != 1197 { c.categoryLabelSize = sz / 100 }
            c.categoryLabelBold = ["1", "true"].contains(run["b"] ?? "")
            if let f = run.first("a:solidFill") { c.categoryLabelColor = color(f) }
        }
        if let run = valueAxis?.first("c:txPr")?.descendant("a:defRPr") {
            c.valueLabelBold = ["1", "true"].contains(run["b"] ?? "")
            if let f = run.first("a:solidFill") { c.valueLabelColor = color(f) }
        }
        // (-60000000 is the charts' "automatic", PowerPoint's own default.)
        if let rot = categoryAxis?.first("c:txPr")?.first("a:bodyPr")?["rot"].flatMap(Double.init), abs(rot) <= 5_400_000 {
            c.categoryLabelTurn = -rot / 60000
        }
        c.pointColors = pointColors
        let styleNode = space.first("c:style") ?? space.first("mc:AlternateContent")?.first("mc:Fallback")?.first("c:style")
        // (Kept where it colours the chart its own way: a monochrome one.)
        c.style = styleNode?["val"].flatMap(Int.init)
        if c.monochromeAccent == nil { c.style = nil }
        if let m = plot.first("c:layout")?.first("c:manualLayout"),
           (m.first("c:xMode")?["val"] ?? "factor") == "edge", (m.first("c:yMode")?["val"] ?? "factor") == "edge",
           let x = m.first("c:x")?["val"].flatMap(Double.init), let y = m.first("c:y")?["val"].flatMap(Double.init),
           let w = m.first("c:w")?["val"].flatMap(Double.init), let h = m.first("c:h")?["val"].flatMap(Double.init),
           w > 0.05, h > 0.05 {
            c.plotLayout = Rect.fromLTWH(x, y, w, h)
            c.plotLayoutInner = m.first("c:layoutTarget")?["val"] == "inner"
        }
        let labelFmt = el.first("c:dLbls")?.first("c:numFmt") ?? el.first("c:ser")?.first("c:dLbls")?.first("c:numFmt")
        let labelCode = labelFmt.flatMap { ["1", "true"].contains($0["sourceLinked"] ?? "") ? nil : $0["formatCode"] }
            ?? el.first("c:ser")?.first("c:val")?.descendant("c:formatCode")?.text
        if let code = labelCode, !code.isEmpty, code.lowercased() != "general" { c.labelFormat = code }
        if let f = plot.first("c:spPr")?.first("a:solidFill") { c.plotFill = color(f) }
        c.areaNoFill = false; c.areaNoLine = false
        if let sp = space.first("c:spPr") {
            if let f = sp.first("a:solidFill") { c.areaFill = color(f) } else if sp.first("a:noFill") != nil { c.areaNoFill = true }
            if let ln = sp.first("a:ln") {
                if let f = ln.first("a:solidFill") {
                    c.areaLine = color(f)
                    c.areaLineWidth = ln["w"].flatMap(Double.init).map { $0 / 12700 }
                } else if ln.first("a:noFill") != nil { c.areaNoLine = true }
            }
        }
        if let ln = plot.first("c:spPr")?.first("a:ln"), let f = ln.first("a:solidFill") {
            c.plotBorder = color(f)
            c.plotBorderWidth = ln["w"].flatMap(Double.init).map { $0 / 12700 } ?? 0.75
        }
        // (Not the standard light grey, `tx1` at 15%, which is the look
        // drawn when the file gives none — and what a save writes.)
        if let ln = valueAxis?.first("c:majorGridlines")?.first("c:spPr")?.first("a:ln"),
           let f = ln.first("a:solidFill"), f.children.first?.children.isEmpty ?? false, let g = color(f) {
            c.gridColor = g
            c.gridWidth = ln["w"].flatMap(Double.init).map { $0 / 12700 }
        }
        if let valueAxis {
            c.valueGrid = valueAxis.first("c:majorGridlines") != nil
            c.valueAxisDeleted = ["1", "true"].contains(valueAxis.first("c:delete")?["val"] ?? "")
            c.valueTicksOut = ["out", "cross"].contains(valueAxis.first("c:majorTickMark")?["val"] ?? "")
        }
        c.categoryAxisDeleted = ["1", "true"].contains(categoryAxis?.first("c:delete")?["val"] ?? "")
        if let scaling = valueAxis?.first("c:scaling") {
            c.valueMin = scaling.first("c:min")?["val"].flatMap(Double.init)
            c.valueMax = scaling.first("c:max")?["val"].flatMap(Double.init)
        }
        c.valueStep = valueAxis?.first("c:majorUnit")?["val"].flatMap(Double.init).flatMap { $0 > 0 ? $0 : nil }
        if let fmt = valueAxis?.first("c:numFmt") {
            let linked = ["1", "true"].contains(fmt["sourceLinked"] ?? "")
            let source = plot.descendant("c:val")?.descendant("c:formatCode")?.text
            let code = (linked ? source : nil) ?? fmt["formatCode"] ?? ""
            if !code.isEmpty, code.lowercased() != "general" { c.valueFormat = code }
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

    private static func _rich(_ text: String, size: Int?, rotated: Bool = false, bold: Bool = false, color: Color? = nil) -> String {
        let body = rotated ? "<a:bodyPr rot=\"-5400000\" vert=\"horz\"/>" : "<a:bodyPr/>"
        let fill = color.map { "<a:solidFill><a:srgbClr val=\"\(PptxText.hex($0))\"/></a:solidFill>" } ?? ""
        let def = size.map { "<a:pPr><a:defRPr sz=\"\($0)\" b=\"\(bold ? 1 : 0)\">\(fill)</a:defRPr></a:pPr>" } ?? ""
        // A line of the title is a paragraph of its own.
        let paragraphs = text.split(separator: "\n", omittingEmptySubsequences: false).map {
            "<a:p>\(def)<a:r><a:rPr lang=\"en-US\"/><a:t>\(_esc(String($0)))</a:t></a:r></a:p>"
        }.joined()
        return "<c:title><c:tx><c:rich>\(body)<a:lstStyle/>\(paragraphs)</c:rich></c:tx><c:overlay val=\"0\"/></c:title>"
    }

    private static let _gridLine = "<a:ln w=\"9525\" cap=\"flat\" cmpd=\"sng\" algn=\"ctr\"><a:solidFill><a:schemeClr val=\"tx1\"><a:lumMod val=\"15000\"/><a:lumOff val=\"85000\"/></a:schemeClr></a:solidFill><a:round/></a:ln>"

    private static func _solid(_ chart: Chart, _ i: Int) -> String {
        let s = chart.series[i]
        if let c = s.color { return "<a:solidFill><a:srgbClr val=\"\(PptxText.hex(c))\"/></a:solidFill>" }
        if let scheme = s.scheme { return "<a:solidFill><a:schemeClr val=\"\(scheme)\"/></a:solidFill>" }
        // A monochrome style colours the series itself: no fill of its own.
        if chart.monochromeAccent != nil { return "" }
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
        let seriesList = c.type.isPie ? Array(c.series.prefix(1)) : c.series
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
                let join = c.series[i].joined ? _solid(c, i) : "<a:noFill/>"
                sers += "<c:ser>\(head)<c:spPr><a:ln w=\"\(c.series[i].joined ? 19050 : 25400)\" cap=\"rnd\">\(join)<a:round/></a:ln></c:spPr><c:marker><c:symbol val=\"circle\"/><c:size val=\"5\"/><c:spPr>\(_solid(c, i))<a:ln w=\"9525\">\(_solid(c, i))</a:ln></c:spPr></c:marker><c:xVal>\(catCache)</c:xVal><c:yVal>\(val)</c:yVal><c:smooth val=\"0\"/></c:ser>"
            case .radar:
                let look = c.radarFilled ? "\(_solid(c, i))<a:ln><a:noFill/></a:ln>" : "<a:ln w=\"28575\" cap=\"rnd\">\(_solid(c, i))<a:round/></a:ln>"
                sers += "<c:ser>\(head)<c:spPr>\(look)</c:spPr><c:marker><c:symbol val=\"none\"/></c:marker><c:cat>\(catCache)</c:cat><c:val>\(val)</c:val></c:ser>"
            case .pie, .doughnut:
                var dpts = ""
                for p in 0 ..< n {
                    let own = c.pointColors[p].map { "<a:solidFill><a:srgbClr val=\"\(PptxText.hex($0))\"/></a:solidFill>" }
                    dpts += "<c:dPt><c:idx val=\"\(p)\"/><c:bubble3D val=\"0\"/><c:spPr>\(own ?? _cycleFill(p))<a:ln w=\"19050\"><a:solidFill><a:schemeClr val=\"lt1\"/></a:solidFill></a:ln></c:spPr></c:dPt>"
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
        case .radar:
            plot = "<c:radarChart><c:radarStyle val=\"\(c.radarFilled ? "filled" : "marker")\"/><c:varyColors val=\"0\"/>\(sers)\(labels)\(ax)</c:radarChart>"
        case .doughnut:
            plot = "<c:doughnutChart><c:varyColors val=\"1\"/>\(sers)\(labels)<c:firstSliceAng val=\"0\"/><c:holeSize val=\"\(c.holeSize)\"/></c:doughnutChart>"
        }
        // A combination's lines, on the columns' axes (their numbers as
        // literals: they are not in the chart's sheet).
        if c.type == .column || c.type == .bar, !c.lineSeries.isEmpty {
            var lsers = ""
            for (j, l) in c.lineSeries.enumerated() {
                let i = c.series.count + j
                let pts = l.values.enumerated().compactMap { k, v in v.map { "<c:pt idx=\"\(k)\"><c:v>\($0)</c:v></c:pt>" } }.joined()
                let ink = l.color.map { "<a:solidFill><a:srgbClr val=\"\(PptxText.hex($0))\"/></a:solidFill>" }
                    ?? "<a:solidFill><a:schemeClr val=\"accent\(i % 6 + 1)\"/></a:solidFill>"
                let line = l.lineHidden ? "<a:ln><a:noFill/></a:ln>" : "<a:ln w=\"28575\" cap=\"rnd\">\(ink)<a:round/></a:ln>"
                var mark = "<c:marker><c:symbol val=\"none\"/></c:marker>"
                if let sym = l.marker, sym != "none" {
                    let fill = l.markerFill.map { "<a:solidFill><a:srgbClr val=\"\(PptxText.hex($0))\"/></a:solidFill>" } ?? ink
                    let edge = l.markerLine.map { "<a:ln><a:solidFill><a:srgbClr val=\"\(PptxText.hex($0))\"/></a:solidFill></a:ln>" } ?? ""
                    mark = "<c:marker><c:symbol val=\"\(sym)\"/><c:size val=\"\(Int(l.markerSize.rounded()))\"/><c:spPr>\(fill)\(edge)</c:spPr></c:marker>"
                }
                let unmarked = l.unmarked.sorted().map { "<c:dPt><c:idx val=\"\($0)\"/><c:marker><c:symbol val=\"none\"/></c:marker></c:dPt>" }.joined()
                lsers += "<c:ser><c:idx val=\"\(i)\"/><c:order val=\"\(i)\"/><c:tx><c:v>\(_esc(l.name))</c:v></c:tx><c:spPr>\(line)</c:spPr>\(mark)\(unmarked)<c:val><c:numLit><c:ptCount val=\"\(l.values.count)\"/>\(pts)</c:numLit></c:val><c:smooth val=\"0\"/></c:ser>"
            }
            plot += "<c:lineChart><c:grouping val=\"standard\"/><c:varyColors val=\"0\"/>\(lsers)<c:marker val=\"1\"/>\(ax)</c:lineChart>"
        }
        if c.type.hasAxes {
            let catTitle = c.categoryAxisTitle.map { _rich($0, size: 1330, rotated: c.type == .bar) } ?? ""
            let valTitle = c.valueAxisTitle.map { _rich($0, size: 1330, rotated: c.type != .bar) } ?? ""
            let catPos = c.type == .bar ? "l" : "b", valPos = c.type == .bar ? "b" : "l"
            let tail = "<c:majorTickMark val=\"none\"/><c:minorTickMark val=\"none\"/><c:tickLblPos val=\"nextTo\"/>"
            let format = c.percent ? "0%" : "General"
            let bounds = (c.valueMax.map { "<c:max val=\"\($0)\"/>" } ?? "") + (c.valueMin.map { "<c:min val=\"\($0)\"/>" } ?? "")
            let unit = c.valueStep.map { "<c:majorUnit val=\"\($0)\"/>" } ?? ""
            let valAx = "<c:valAx><c:axId val=\"500000002\"/><c:scaling><c:orientation val=\"minMax\"/>\(bounds)</c:scaling><c:delete val=\"\(c.valueAxisDeleted ? 1 : 0)\"/><c:axPos val=\"\(valPos)\"/>\(c.valueGrid ? "<c:majorGridlines><c:spPr>\(_gridLine)</c:spPr></c:majorGridlines>" : "")\(valTitle)<c:numFmt formatCode=\"\(format)\" sourceLinked=\"1\"/>\(tail)<c:spPr><a:noFill/><a:ln><a:noFill/></a:ln></c:spPr><c:crossAx val=\"500000001\"/><c:crosses val=\"autoZero\"/><c:crossBetween val=\"\(c.type == .scatter || c.type == .area ? "midCat" : "between")\"/>\(unit)</c:valAx>"
            if c.type == .scatter {
                plot += "<c:valAx><c:axId val=\"500000001\"/><c:scaling><c:orientation val=\"minMax\"/></c:scaling><c:delete val=\"0\"/><c:axPos val=\"b\"/><c:majorGridlines><c:spPr>\(_gridLine)</c:spPr></c:majorGridlines>\(catTitle)<c:numFmt formatCode=\"General\" sourceLinked=\"1\"/>\(tail)<c:spPr><a:noFill/>\(_gridLine)</c:spPr><c:crossAx val=\"500000002\"/><c:crosses val=\"autoZero\"/><c:crossBetween val=\"midCat\"/></c:valAx>"
            } else {
                plot += "<c:catAx><c:axId val=\"500000001\"/><c:scaling><c:orientation val=\"minMax\"/></c:scaling><c:delete val=\"\(c.categoryAxisDeleted ? 1 : 0)\"/><c:axPos val=\"\(catPos)\"/>\(catTitle)<c:numFmt formatCode=\"General\" sourceLinked=\"1\"/>\(tail)<c:spPr><a:noFill/>\(_gridLine)</c:spPr><c:crossAx val=\"500000002\"/><c:crosses val=\"autoZero\"/><c:auto val=\"1\"/><c:lblAlgn val=\"ctr\"/><c:lblOffset val=\"100\"/><c:noMultiLvlLbl val=\"0\"/></c:catAx>"
            }
            plot += valAx
        }
        let title = c.title.map {
            _rich($0, size: c.titleSize.map { Int(($0 * 100).rounded()) } ?? 1862, bold: c.titleBold, color: c.titleColor)
        } ?? ""
        let plotFill = c.plotFill.map { "<c:spPr><a:solidFill><a:srgbClr val=\"\(PptxText.hex($0))\"/></a:solidFill></c:spPr>" } ?? ""
        // The chart area as the chart has it (no fill and no line, for one
        // of this app's own; nothing at all where the file gave nothing).
        let areaFillXML = c.areaFill.map { "<a:solidFill><a:srgbClr val=\"\(PptxText.hex($0))\"/></a:solidFill>" } ?? (c.areaNoFill ? "<a:noFill/>" : "")
        let areaLineXML = c.areaLine.map { line in
            "<a:ln\(c.areaLineWidth.map { " w=\"\(Int(($0 * 12700).rounded()))\"" } ?? "")><a:solidFill><a:srgbClr val=\"\(PptxText.hex(line))\"/></a:solidFill></a:ln>"
        } ?? (c.areaNoLine ? "<a:ln><a:noFill/></a:ln>" : "")
        let areaXML = areaFillXML.isEmpty && areaLineXML.isEmpty ? "" : "<c:spPr>\(areaFillXML)\(areaLineXML)</c:spPr>"
        let legend = c.legend ? "<c:legend><c:legendPos val=\"\(c.legendPosition)\"/><c:overlay val=\"0\"/></c:legend>" : ""
        let ink = c.textColor.map { "<a:solidFill><a:srgbClr val=\"\(PptxText.hex($0))\"/></a:solidFill>" }
            ?? (c.plainText ? "" : "<a:solidFill><a:schemeClr val=\"tx1\"><a:lumMod val=\"65000\"/><a:lumOff val=\"35000\"/></a:schemeClr></a:solidFill>")
        let text = "<c:txPr><a:bodyPr/><a:lstStyle/><a:p><a:pPr><a:defRPr sz=\"\(Int(((c.textSize ?? 12) * 100).rounded()))\">\(ink)</a:defRPr></a:pPr><a:endParaRPr lang=\"en-US\"/></a:p></c:txPr>"
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <c:chartSpace xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><c:date1904 val="0"/><c:lang val="en-US"/><c:roundedCorners val="0"/>\(c.style.map { "<c:style val=\"\($0)\"/>" } ?? (c.officeStyled ? "<c:style val=\"2\"/>" : ""))<c:chart>\(title)<c:autoTitleDeleted val="\(c.title == nil ? 1 : 0)"/><c:plotArea><c:layout/>\(plot)\(plotFill)</c:plotArea>\(legend)<c:plotVisOnly val="1"/><c:dispBlanksAs val="gap"/></c:chart>\(areaXML)\(text)<c:externalData r:id="rId1"><c:autoUpdate val="0"/></c:externalData></c:chartSpace>
        """
    }

    /// The chart's data as a one-sheet workbook: categories down column A,
    /// a series per column from B, names in row 1 — the table PowerPoint's
    /// Edit Data opens.
    static func workbook(_ c: Chart) throws -> Data {
        func cell(_ ref: String, _ s: String) -> String {
            "<c r=\"\(ref)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(_esc(s))</t></is></c>"
        }
        let seriesList = c.type.isPie ? Array(c.series.prefix(1)) : c.series
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
    /// The faces a chart's text falls back to for a character its own
    /// face lacks, as body text's: on Linux the engine has none without
    /// them, and zh-37b6536f's Chinese legend printed as boxes.
    static var glyphFallback: [String]? { RichTextTheme.glyphFallback.isEmpty ? nil : RichTextTheme.glyphFallback }

    static func paint(_ c: Chart, _ canvas: any Canvas, _ r: Rect, pxPerPt k: Double, theme: DeckTheme) {
        guard r.width > 4, r.height > 4, !c.series.isEmpty else { return }
        // The text in the file's colour, else the theme's text colour:
        // a chart that says nothing (POI's radar-chart, a 2007 style) is
        // black in PowerPoint's print. A 2013 chart's grey is the file's
        // own, on each part's text.
        let ink = c.textColor ?? (c.plainText ? theme.text : _mix(theme.text, theme.background, 0.65))
        let grid = _mix(theme.text, theme.background, 0.15)
        // (LIBRE_OFFICE-100610's charts say Calibri in an Arial theme, and
        // PowerPoint sets them in Calibri.)
        let font = OfficeFonts.substitute(c.font ?? theme.bodyFont)
        // Letters one by one, as PowerPoint sets them: no "ﬁ" in "Defined".
        let plain = [FontFeature("liga", 0), FontFeature("clig", 0)]
        func styled(_ s: String, _ size: Double, _ maxWidth: Double, bold: Bool, color: Color? = nil) -> TextPainter {
            let tp = TextPainter(text: TextSpan(text: s, style: Flutter.TextStyle(
                color: color ?? ink, fontSize: max(3, size * k), fontWeight: bold ? .bold : .normal,
                fontFeatures: plain, fontFamily: font, fontFamilyFallback: Self.glyphFallback)),
                textAlign: .center, textDirection: .ltr)   // (a label broken in two centres each line)
            tp.layout(minWidth: 0, maxWidth: max(1, maxWidth))
            return tp
        }
        func text(_ s: String, _ size: Double, _ maxWidth: Double = .infinity) -> TextPainter {
            styled(s, size, maxWidth, bold: false)
        }
        canvas.save()
        canvas.clipRect(r)
        // (A 2007-style chart sits 6.5 pt in at the left and bottom, where
        // a newer one keeps 9: line-, bar- and scatter-chart's labels stand
        // 2.5 pt further out in PowerPoint's print.)
        let old = c.plainText && !c.styled2013 && c.officeStyled
        var area = Rect.fromLTRB(r.left + (old ? 6.5 : 9) * k, r.top + 9 * k, r.right - 9 * k, r.bottom - (old ? 6.5 : 9) * k)

        if let title = c.title, !title.isEmpty {
            // In the file's size, weight and colour where it gives them,
            // each line centred.
            let tp = TextPainter(text: TextSpan(text: title, style: Flutter.TextStyle(
                color: c.titleColor ?? ink, fontSize: max(3, (c.titleSize ?? c.textSize.map { ($0 * 1.2).rounded() } ?? 18.6) * k),
                fontWeight: c.titleBold ? .bold : .normal, fontFeatures: plain,
                fontFamily: OfficeFonts.substitute(c.titleFont ?? theme.bodyFont), fontFamilyFallback: Self.glyphFallback)),
                textAlign: .center, textDirection: .ltr)
            tp.layout(minWidth: 0, maxWidth: max(1, area.width))
            // (Two points higher than the area's edge: where PowerPoint's sits.)
            tp.paint(canvas, Offset(area.center.dx - tp.width / 2, area.top - 2 * k))
            // (Gaps from PowerPoint's own default chart, chart-slide-bg:
            // title to plot 3.6, plot to its category labels 7.6, labels to
            // the legend 8.4, the legend 1.2 above the margin, value labels
            // 8.5 from the plot — each where its text sits on the page.)
            area = Rect.fromLTRB(area.left, area.top + tp.height + 3.6 * k, area.right, area.bottom)
            tp.dispose()
        }

        // The legend: one row of key + name, centred, wrapped when wide.
        let pie = c.type.isPie
        if c.legend {
            let names = pie ? c.categories : c.series.map(\.name) + c.lineSeries.map(\.name)
            // In the legend's own size, its keys and gaps in proportion.
            let size = c.legendSize ?? c.baseTextSize, m = size / 12
            var entries = names.enumerated().map { (i: $0.offset, tp: styled($0.element, size, .infinity, bold: c.legendBold, color: c.legendColor)) }
            // (9.5 between a row's entries on a newer chart: chart-slide-bg's
            // legend pitches 58.6 pt in PowerPoint's print, ours 60.9 at 12.)
            let key = 7 * k * m, gap = 4 * k * m, spacing = (c.styled2013 ? 9.5 : 12) * k * m
            // Beside the plot (`legendPos` r, l, tr): a column, an entry to
            // a line, in the middle of the side; above or below: rows.
            let box = c.legendBox.map { Rect.fromLTWH(r.left + $0.left * r.width, r.top + $0.top * r.height, $0.width * r.width, $0.height * r.height) }
            let beside = box == nil && ["r", "l", "tr"].contains(c.legendPosition)
            // A column beside stacked columns (or areas) reads as the stack
            // does, the last series — the top of it — first.
            if beside, c.stacked, c.type == .column || c.type == .area { entries.reverse() }
            // And a bar chart's, at any side, as its bars run: series 1 at
            // the bottom, listed last (LIBRE_OFFICE-100610-0's five).
            if c.type == .bar, !c.stacked { entries.reverse() }
            var lines: [[(i: Int, tp: TextPainter)]] = [[]]
            var lineW = 0.0
            for e in entries {
                let w = key + gap + e.tp.width
                if lineW > 0, beside || lineW + spacing + w > (box?.width ?? area.width) { lines.append([]); lineW = 0 }
                lineW += (lineW > 0 ? spacing : 0) + w
                lines[lines.count - 1].append(e)
            }
            // (An entry to a line: PowerPoint's 9 pt entries are 16.9 pt apart.)
            let textH = entries.map(\.tp.height).max() ?? size * k
            let lineH = beside ? textH + 6 * k : textH
            let columnW = (entries.map(\.tp.width).max() ?? 0) + key + gap
            var y: Double, columnX = 0.0
            if let box {
                // In its own place, the plot's room untouched.
                y = box.center.dy - lineH * Double(lines.count) / 2
            } else if beside {
                y = c.legendPosition == "tr" ? area.top : area.center.dy - lineH * Double(lines.count) / 2
                if c.legendPosition == "l" {
                    columnX = area.left
                    area = Rect.fromLTRB(area.left + columnW + 12 * k, area.top, area.right, area.bottom)
                } else {
                    columnX = area.right - columnW
                    // (17.3 to the legend's keys: the 2007-style line,
                    // scatter, radar and bar charts' plots end 5.3 pt
                    // short of where 12 left them, in PowerPoint's print.)
                    let apart = !pie && !c.styled2013 ? 17.3 : 12
                    area = Rect.fromLTRB(area.left, area.top, columnX - apart * k, area.bottom)
                }
            } else if c.legendPosition == "t" {
                y = area.top
                area = Rect.fromLTRB(area.left, y + lineH * Double(lines.count) + 6 * k, area.right, area.bottom)
            } else {
                y = area.bottom - 1.2 * k - lineH * Double(lines.count)
                area = Rect.fromLTRB(area.left, area.top, area.right, y - 8.4 * k)
            }
            for line in lines {
                let w = line.reduce(0.0) { $0 + key + gap + $1.tp.width } + spacing * Double(max(0, line.count - 1))
                var x = beside ? columnX : (box?.center.dx ?? area.center.dx) - w / 2
                for e in line {
                    let p = Paint()
                    p.style = .fill
                    p.isAntiAlias = true
                    if !pie, e.i >= c.series.count {
                        // A combination's line: its mark, on its line unless
                        // that is hidden.
                        let l = c.lineSeries[e.i - c.series.count]
                        let colour = l.color ?? c.color(series: e.i, accents: theme.accents)
                        let mid = Offset(x + key / 2, y + lineH / 2)
                        if !l.lineHidden {
                            p.style = .stroke
                            p.strokeWidth = 2.25 * k
                            p.color = colour
                            canvas.drawLine(Offset(x - 2 * k, mid.dy), Offset(x + key + 2 * k, mid.dy), p)
                        }
                        Self._mark(l, at: mid, k: k, colour: colour, canvas)
                        e.tp.paint(canvas, Offset(x + key + gap, y + (lineH - e.tp.height) / 2))
                        x += key + gap + e.tp.width + spacing
                        continue
                    }
                    p.color = pie ? c.pointColor(e.i, accents: theme.accents) : c.color(series: e.i, accents: theme.accents)
                    if c.type == .line || (c.type == .radar && !c.radarFilled) {
                        p.style = .stroke
                        p.strokeWidth = 2.25 * k
                        canvas.drawLine(Offset(x - 2 * k, y + lineH / 2), Offset(x + key + 2 * k, y + lineH / 2), p)
                    } else if c.type == .scatter {
                        canvas.drawCircle(Offset(x + key / 2, y + lineH / 2), 2.5 * k, p)
                    } else {
                        canvas.drawRect(Rect.fromLTWH(x, y + (lineH - key) / 2, key, key), p)
                    }
                    e.tp.paint(canvas, Offset(x + key + gap, y + (lineH - e.tp.height) / 2))
                    x += key + gap + e.tp.width + spacing
                }
                y += lineH
            }
            for line in lines { for e in line { e.tp.dispose() } }
        }

        if pie, let l = c.plotLayout {
            area = Rect.fromLTWH(r.left + l.left * r.width, r.top + l.top * r.height, l.width * r.width, l.height * r.height)
        }
        if c.type == .radar {
            _radar(c, canvas, area, k: k, theme: theme, grid: c.gridColor ?? grid,
                   text: { styled($0, $1, $2, bold: false, color: c.valueLabelColor) },
                   categoryText: { styled($0, $1, $2, bold: c.categoryLabelBold, color: c.categoryLabelColor) })
        } else if pie, let tilt = c.pieTilt {
            // A 3-D pie's plot is the box the tilted disc stands in, a
            // little inside the room left to it (LIBRE_OFFICE-100610-0's
            // grey plots, 345 × 196 pt where ours had 401 × 235) — or the
            // box the file places itself (`inner`), as it is: 45544's pies
            // are 187.5 × 69 pt in Excel's print, inside a box of 195.5 ×
            // 72.2, where ours were 99 × 58.
            let inner = c.plotLayout != nil && c.plotLayoutInner ? area
                : Rect.fromLTRB(area.left + area.width * 0.07, area.top + area.height * 0.085,
                                area.right - area.width * 0.07, area.bottom - area.height * 0.085)
            if let f = c.plotFill {
                let p = Paint()
                p.style = .fill
                p.color = f
                canvas.drawRect(inner, p)
            }
            _pie3D(c, canvas, inner, tilt: tilt, k: k, theme: theme, frame: r, ink: ink)
        } else if pie {
            if let f = c.plotFill {
                // A pie's plot is the square it stands in.
                let p = Paint()
                p.style = .fill
                p.color = f
                canvas.drawRect(Rect.fromCircle(center: area.center, radius: min(area.width, area.height) / 2), p)
            }
            _pie(c, canvas, area, k: k, theme: theme, text: text, frame: r, ink: ink)
        } else {
            _axes(c, canvas, area, frame: r, k: k, theme: theme, grid: c.gridColor ?? grid, text: text,
                  categoryText: { styled($0, $1, $2, bold: c.categoryLabelBold, color: c.categoryLabelColor) },
                  valueText: { styled($0, $1, $2, bold: c.valueLabelBold, color: c.valueLabelColor) })
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
    /// The step is the smallest of 1, 2, 5 × a power of ten that marks the
    /// axis in no more than `intervals` steps. Nine is PowerPoint's, by
    /// every axis of its pages looked at: 0 to 1,600 in 200s (eight; 100s
    /// would be sixteen), 0 to 600 in 100s (six; 50s twelve), 0 to 6 in
    /// ones (halves twelve), 0 to 10 in twos (ones ten) — and 0 to 9 in
    /// ones (line-chart's 8.2, where eight made it 0 to 10 in twos).
    static func scale(_ lo0: Double, _ hi0: Double, intervals: Int = 9) -> (lo: Double, hi: Double, step: Double) {
        var lo = min(0, lo0), hi = max(0, hi0)
        if hi == lo { hi = lo + 1 }
        let span = hi - lo
        if hi > 0 { hi += span * 0.05 }
        if lo < 0 { lo -= span * 0.05 }
        let rough = (hi - lo) / Double(max(1, intervals))
        let mag = pow(10, floor(log10(rough)))
        let norm = rough / mag
        let step = (norm <= 1 ? 1 : norm <= 2 ? 2 : norm <= 5 ? 5 : 10) * mag
        return (floor(lo / step) * step, ceil(hi / step) * step, step)
    }

    /// An axis with bounds or a step the file fixes; what it leaves open
    /// is automatic. The step for fixed bounds keeps to ten intervals at
    /// most, round numbers: aascu 5864's 0 to 1 goes by 0.1, as
    /// PowerPoint's, where eight made it 0.2.
    static func fixedScale(auto: (lo: Double, hi: Double, step: Double), min lo0: Double?, max hi0: Double?,
                           step step0: Double?) -> (lo: Double, hi: Double, step: Double) {
        var lo = lo0 ?? auto.lo, hi = hi0 ?? auto.hi
        if hi <= lo { lo = auto.lo; hi = auto.hi }
        var step = auto.step
        if let s = step0 {
            step = s
        } else if lo0 != nil || hi0 != nil {
            let rough = (hi - lo) / 10
            let mag = pow(10, floor(log10(rough)))
            let norm = rough / mag
            step = (norm <= 1 + 1e-9 ? 1 : norm <= 2 ? 2 : norm <= 5 ? 5 : 10) * mag
        }
        // Open ends rounded out to the step; at most a hundred marks.
        if lo0 == nil { lo = floor(lo / step + 1e-9) * step }
        if hi0 == nil { hi = ceil(hi / step - 1e-9) * step }
        if (hi - lo) / step > 100 { step = (hi - lo) / 10 }
        return (lo, hi, step)
    }

    /// A data label: the value in the labels' number format where they
    /// have one ("0": 80, where the plain number is 79.63).
    static func dataLabel(_ c: Chart, _ v: Double) -> String {
        guard let code = c.labelFormat else { return label(v, percent: false) }
        let shown = NumberFormat.format(v, code, width: 40).text.trimmingWhitespace()
        return shown.isEmpty ? label(v, percent: false) : shown
    }

    static func label(_ v: Double, percent: Bool) -> String {
        if percent { return "\(Int((v * 100).rounded()))%" }
        if abs(v - v.rounded()) < 1e-9 { return String(Int(v.rounded())) }
        var s = String(printf: "%.2f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    private static func _axes(_ c: Chart, _ canvas: any Canvas, _ area0: Rect, frame: Rect, k: Double, theme: DeckTheme,
                              grid: Color, text: (String, Double, Double) -> TextPainter,
                              categoryText: (String, Double, Double) -> TextPainter,
                              valueText: (String, Double, Double) -> TextPainter) {
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
        // (The lines over a combination's columns share the axis.)
        for v in c.lineSeries.flatMap({ $0.values.compactMap { $0 } }) { lo = min(lo, v); hi = max(hi, v) }
        let labelSize = c.valueLabelSize ?? c.baseTextSize
        // (Settled here and captured as constants: the Windows
        // toolchain's optimizer (Swift 6.2.3) fails SIL verification on
        // a tuple `var` that the closures below capture — "Lexical
        // borrows of SILBoxTypes must be of vars or captures" — and the
        // release build dies with exception 3.)
        // (A value axis across the page — a bar chart's — keeps to eight:
        // its labels stand side by side, and bar-chart's 8.2 runs 0 to 10
        // in twos there where the same data up the page goes by ones.)
        var valueScale = c.percent ? (lo: 0.0, hi: 1.0, step: 0.1) : scale(lo, hi, intervals: c.type == .bar ? 8 : 9)
        if c.valueMin != nil || c.valueMax != nil || c.valueStep != nil {
            valueScale = fixedScale(auto: valueScale, min: c.valueMin, max: c.valueMax, step: c.valueStep)
        }
        let sc = valueScale
        var xScale = (lo: 0.0, hi: Double(n), step: 1.0)
        if c.type == .scatter {
            let x = (0 ..< n).map { c.x($0) }
            xScale = scale(x.min() ?? 0, x.max() ?? 1, intervals: 8)
        }
        let xs = xScale
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

        // Where the file places the plot: itself (`inner`), or a box the
        // plot and its labels share — aascu 5864's census chart stands at
        // 9%/3%, 91% × 76% of its frame, ours under a title band.
        let placed = c.plotLayout.map {
            Rect.fromLTWH(frame.left + $0.left * frame.width, frame.top + $0.top * frame.height,
                          $0.width * frame.width, $0.height * frame.height)
        }
        if let placed, !c.plotLayoutInner { area = placed }
        // Tick labels: values along one axis, categories (or x values) along the other.
        let ticks = Array(stride(from: sc.lo, through: sc.hi + sc.step * 1e-6, by: sc.step))
        // In the axis's own number format where it has one: "1,600", and
        // an accounting format's "-" for nought. (Its padding is a cell's.)
        func valueLabel(_ v: Double) -> String {
            guard let code = c.valueFormat, !c.percent else { return label(v, percent: c.percent) }
            let shown = NumberFormat.format(v, code, width: 40).text.trimmingWhitespace()
            return shown.isEmpty ? label(v, percent: false) : shown
        }
        let valueLabels = ticks.map { valueText(c.valueAxisDeleted ? "" : valueLabel($0), labelSize, .infinity) }
        let catSize = c.categoryLabelSize ?? c.baseTextSize
        var catLabels: [TextPainter]
        // Categories too long for their slot even word by word are set
        // aslant, a quarter of a right angle up to the right and ending
        // at their tick, as PowerPoint sets them (aascu 5864's country
        // names); we had broken them inside words.
        var aslant = false
        var slant = Double.pi / 4
        if c.type == .scatter {
            catLabels = Array(stride(from: xs.lo, through: xs.hi + xs.step / 2, by: xs.step)).map { categoryText(label($0, percent: false), catSize, .infinity) }
        } else {
            let along = placed.flatMap { c.plotLayoutInner ? $0 : nil } ?? area
            // (Across, the room the value labels take beside the plot is
            // not the categories': cooper's "African American" breaks in
            // two in PowerPoint's print, in a slot a fifth of the plot.)
            let beside = horizontal || (placed != nil && c.plotLayoutInner) ? 0
                : (valueLabels.map(\.width).max() ?? 0) + (c.styled2013 ? 8.5 : 11.1) * k + 4 * k
            let slot = ((horizontal ? along.height : along.width) - beside) / Double(n)
            catLabels = c.categories.map { categoryText(c.categoryAxisDeleted ? "" : $0, catSize, horizontal ? area.width * 0.3 : max(slot - 2 * k, 8 * k)) }
            if !horizontal, c.type != .area, !c.categoryAxisDeleted, let turn = c.categoryLabelTurn {
                // As the file says: turned (up to a quarter, either way) or
                // level.
                if turn != 0 {
                    aslant = true
                    slant = min(90, abs(turn)) * .pi / 180
                    for t in catLabels { t.dispose() }
                    catLabels = c.categories.map { categoryText($0, catSize, .infinity) }
                }
            } else if !horizontal, c.type != .area, !c.categoryAxisDeleted {
                let room = max(slot - 2 * k, 8 * k)
                let words = c.categories.flatMap { $0.split(separator: " ").map(String.init) }
                let widest = words.map { w -> Double in
                    let t = categoryText(w, catSize, .infinity)
                    defer { t.dispose() }
                    return t.width
                }.max() ?? 0
                if widest > room {
                    aslant = true
                    for t in catLabels { t.dispose() }
                    catLabels = c.categories.map { categoryText($0, catSize, .infinity) }
                }
            }
        }
        // An aslant label's drop below its tick.
        func drop(_ t: TextPainter) -> Double { t.width * sin(slant) + t.height * cos(slant) }
        let lineH = valueLabels.first?.height ?? 12 * k
        var plot: Rect
        // Outward tick marks push the labels off: further beside the axis
        // (5.6 pt on line- and scatter-chart's value axis, 8.8 on
        // bar-chart's categories) and 3.7 below it, in PowerPoint's print
        // against charts with none.
        let besideOut = (horizontal ? c.categoryTicksOut : c.valueTicksOut) ? (horizontal ? 8.8 : 5.6) * k : 0
        let belowOut = (horizontal ? c.valueTicksOut : c.categoryTicksOut) ? 3.7 * k : 0
        if horizontal {
            let left = (catLabels.map(\.width).max() ?? 0) + 6 * k + besideOut
            plot = Rect.fromLTRB(area.left + left, area.top + 2 * k, area.right - (valueLabels.last?.width ?? 0) / 2,
                                 area.bottom - lineH - 4 * k - belowOut)
        } else {
            // (A 2007-style chart's plot starts 2.6 pt further off its
            // value labels — line- and scatter-chart's at 152.3, the
            // labels where ours are.)
            var left = (valueLabels.map(\.width).max() ?? 0) + (c.styled2013 ? 8.5 : 11.1) * k + besideOut
            let tallest = aslant ? (catLabels.map(drop).max() ?? lineH) : (catLabels.map(\.height).max() ?? lineH)
            let bottom = tallest + 7.6 * k + belowOut
            // Labels centred on the plot's edges (an area's first and last
            // categories, a scatter's end ticks) need half their width free.
            let edges = c.type == .scatter || c.type == .area
            var right = edges ? (catLabels.last?.width ?? 0) / 2 : 4 * k
            if edges { left = max(left, (catLabels.first?.width ?? 0) / 2); right = max(right, 4 * k) }
            plot = Rect.fromLTRB(area.left + left, area.top + lineH / 2, area.right - right, area.bottom - bottom)
        }
        if let placed, c.plotLayoutInner { plot = placed }
        // A 3-D chart stands in a box whose floor and walls run back, up
        // and to the right, one category deep: the plot is its front, and
        // the room behind it is taken out of the area (aascu 5864's
        // census columns: 9.5 pt across and 7.5 up, its categories 28 pt
        // apart, in PowerPoint's print).
        let depthAt: (Double) -> Offset = { thick in
            guard let v = c.barView else { return .zero }
            return Offset(thick * sin(abs(v.y) * .pi / 180), thick * sin(abs(v.x) * .pi / 180))
        }
        var box = Offset.zero
        if let v = c.barView, c.type == .column || c.type == .bar {
            let whole = plot
            for _ in 0 ..< 3 {
                let slot = (horizontal ? plot.height : plot.width) / Double(max(1, n))
                box = depthAt(slot * v.depth)
                plot = Rect.fromLTRB(whole.left, whole.top + box.dy, whole.right - box.dx, whole.bottom)
            }
        }
        guard plot.width > 4, plot.height > 4 else {
            for t in valueLabels + catLabels { t.dispose() }
            return
        }
        if let f = c.plotFill {
            let p = Paint()
            p.style = .fill
            p.color = f
            canvas.drawRect(plot, p)
        }
        if let b = c.plotBorder {
            let p = Paint()
            p.style = .stroke
            p.strokeWidth = max(0.25, c.plotBorderWidth * k)
            p.color = b
            canvas.drawRect(plot, p)
        }
        func vpos(_ v: Double) -> Double {
            let t = (v - sc.lo) / (sc.hi - sc.lo)
            return horizontal ? plot.left + t * plot.width : plot.bottom - t * plot.height
        }
        let gridPaint = Paint()
        gridPaint.style = .stroke
        gridPaint.strokeWidth = max(0.5, (c.gridWidth ?? 0.75) * k)
        gridPaint.color = grid
        for (i, v) in ticks.enumerated() {
            let p = vpos(v)
            let tp = valueLabels[i]
            if horizontal {
                if c.valueGrid {
                    if box != .zero {
                        // Across the floor, then up the back wall.
                        canvas.drawLine(Offset(p, plot.bottom), Offset(p + box.dx, plot.bottom - box.dy), gridPaint)
                        canvas.drawLine(Offset(p + box.dx, plot.top - box.dy), Offset(p + box.dx, plot.bottom - box.dy), gridPaint)
                    } else {
                        canvas.drawLine(Offset(p, plot.top), Offset(p, plot.bottom), gridPaint)
                    }
                }
                tp.paint(canvas, Offset(p - tp.width / 2, plot.bottom + 4 * k + belowOut))
            } else {
                if c.valueGrid {
                    if box != .zero {
                        // Back along the side wall, then across the back.
                        canvas.drawLine(Offset(plot.left, p), Offset(plot.left + box.dx, p - box.dy), gridPaint)
                        canvas.drawLine(Offset(plot.left + box.dx, p - box.dy), Offset(plot.right + box.dx, p - box.dy), gridPaint)
                    } else {
                        canvas.drawLine(Offset(plot.left, p), Offset(plot.right, p), gridPaint)
                    }
                }
                // (A newer chart's labels stand 2.5 pt further off the
                // plot than the room left for them: chart-slide-bg's and
                // its three like it, at 166.5 where ours were at 169, the
                // plot where PowerPoint's is.)
                let further = c.styled2013 ? 2.5 * k : 2.6 * k
                // (A 2007-style chart's stand with their middles 1.45 pt
                // above their lines, line- and scatter-chart's 18 pt
                // labels. A newer chart's are measured so too, and came
                // out no nearer raised.)
                let lift = c.styled2013 ? 0 : 1.45 * k
                tp.paint(canvas, Offset(plot.left - 8.5 * k - besideOut - further - tp.width, p - tp.height / 2 - lift))
            }
        }
        // The category axis line, at zero.
        let zero = vpos(max(sc.lo, min(sc.hi, 0)))
        if c.type == .scatter {
            let xTicks = Array(stride(from: xs.lo, through: xs.hi + xs.step / 2, by: xs.step))
            for (i, v) in xTicks.enumerated() {
                let x = plot.left + (v - xs.lo) / (xs.hi - xs.lo) * plot.width
                canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), gridPaint)
                if i < catLabels.count { catLabels[i].paint(canvas, Offset(x - catLabels[i].width / 2, plot.bottom + 4 * k + belowOut)) }
            }
        } else if horizontal {
            canvas.drawLine(Offset(zero, plot.top), Offset(zero, plot.bottom), gridPaint)
            if box != .zero {
                // The box's edges at zero: its back, and across its top.
                canvas.drawLine(Offset(zero, plot.top), Offset(zero + box.dx, plot.top - box.dy), gridPaint)
                canvas.drawLine(Offset(zero, plot.bottom), Offset(zero + box.dx, plot.bottom - box.dy), gridPaint)
                canvas.drawLine(Offset(zero + box.dx, plot.top - box.dy), Offset(zero + box.dx, plot.bottom - box.dy), gridPaint)
            }
            let slot = plot.height / Double(n)
            for (i, tp) in catLabels.enumerated() {
                // Category 1 at the bottom, as PowerPoint draws a bar chart.
                let cy = plot.bottom - (Double(i) + 0.5) * slot
                tp.paint(canvas, Offset(plot.left - 8.5 * k - besideOut - tp.width, cy - tp.height / 2))
            }
        } else {
            canvas.drawLine(Offset(plot.left, zero), Offset(plot.right, zero), gridPaint)
            if box != .zero {
                // The floor's other edges: its sides and its back.
                canvas.drawLine(Offset(plot.left, zero), Offset(plot.left + box.dx, zero - box.dy), gridPaint)
                canvas.drawLine(Offset(plot.right, zero), Offset(plot.right + box.dx, zero - box.dy), gridPaint)
                canvas.drawLine(Offset(plot.left + box.dx, zero - box.dy), Offset(plot.right + box.dx, zero - box.dy), gridPaint)
            }
            let slot = plot.width / Double(n)
            for (i, tp) in catLabels.enumerated() {
                let cx = c.type == .area && n > 1 ? plot.left + Double(i) * plot.width / Double(n - 1) : plot.left + (Double(i) + 0.5) * slot
                if aslant {
                    // Its end's middle at the tick, the rest down to the left.
                    canvas.save()
                    canvas.translate(cx, plot.bottom + 7.6 * k + belowOut)
                    canvas.rotate(-slant)
                    tp.paint(canvas, Offset(-tp.width, -tp.height / 2))
                    canvas.restore()
                } else {
                    tp.paint(canvas, Offset(cx - tp.width / 2, plot.bottom + 7.6 * k + belowOut))
                }
            }
        }
        for t in valueLabels + catLabels { t.dispose() }

        var labels: [(String, Offset, Int)] = []
        // Labels from cells, each with the bar it stands in the end of.
        var cellLabels: [(text: String, bar: Rect, series: ChartSeries)] = []
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

        // Fixed bounds may cut a value off: what lies past them is cut at
        // the plot's edge.
        let clipped = c.valueMin != nil || c.valueMax != nil
        if clipped { canvas.save(); canvas.clipRect(plot) }
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
                    var rect: Rect
                    if horizontal {
                        let top = centre + group / 2 - Double(j) * step - bar
                        rect = Rect.fromLTRB(min(p0, p1), top, max(p0, p1), top + bar)
                        labels.append((dataLabel(c, raw), Offset(c.stacked ? rect.center.dx : max(p0, p1) + 3 * k, rect.center.dy), j))
                    } else {
                        let left = centre - group / 2 + Double(j) * step
                        rect = Rect.fromLTRB(left, min(p0, p1), left + bar, max(p0, p1))
                        labels.append((dataLabel(c, raw), Offset(rect.center.dx, c.stacked ? rect.center.dy : min(p0, p1) - 8 * k), j))
                    }
                    // In a 3-D box, the bar stands in the middle of its
                    // depth, its own depth a 1 + gapDepth share of it.
                    var d = Offset.zero
                    if let v = c.barView, box != .zero {
                        let own = 1 / (1 + v.gapDepth)
                        d = Offset(box.dx * own, box.dy * own)
                        let back = Offset(box.dx * (1 - own) / 2, box.dy * (1 - own) / 2)
                        rect = rect.shift(Offset(back.dx, -back.dy))
                        if let last = labels.popLast() { labels.append((last.0, Offset(last.1.dx + back.dx, last.1.dy - back.dy), last.2)) }
                    }
                    canvas.drawRect(rect, fill)
                    if c.barView != nil {
                        // The box's top and right side, darker, as
                        // PowerPoint's print of LIBRE_OFFICE-100610-0 has
                        // them, turned by the view's angles; the top 0.757
                        // of the colour, the side 0.64.
                        let base = fill.color
                        let top = Path()
                        top.moveTo(rect.left, rect.top); top.lineTo(rect.left + d.dx, rect.top - d.dy)
                        top.lineTo(rect.right + d.dx, rect.top - d.dy); top.lineTo(rect.right, rect.top); top.close()
                        fill.color = Self._scaled(base, 0.757)
                        canvas.drawPath(top, fill)
                        let side = Path()
                        side.moveTo(rect.right, rect.top); side.lineTo(rect.right + d.dx, rect.top - d.dy)
                        side.lineTo(rect.right + d.dx, rect.bottom - d.dy); side.lineTo(rect.right, rect.bottom); side.close()
                        fill.color = Self._scaled(base, 0.64)
                        canvas.drawPath(side, fill)
                        fill.color = base
                    }
                    if let o = c.series[j].outline {
                        let line = Paint()
                        line.style = .stroke
                        line.strokeWidth = max(0.25, c.series[j].outlineWidth * k)
                        line.color = o
                        canvas.drawRect(rect, line)
                    }
                    if let t = c.series[j].cellLabels[i] { cellLabels.append((t, rect, c.series[j])) }
                }
            }
            // A combination's lines over the columns: each through its
            // categories' middles, with its marks.
            if !horizontal {
                for (j, l) in c.lineSeries.enumerated() {
                    let colour = l.color ?? c.color(series: c.series.count + j, accents: theme.accents)
                    func at(_ i: Int) -> Offset? {
                        guard let v = l.values[safe: i] ?? nil else { return nil }
                        return Offset(plot.left + (Double(i) + 0.5) * slot, vpos(v))
                    }
                    if !l.lineHidden {
                        let path = Path()
                        var pen = false
                        for i in 0 ..< n {
                            guard let q = at(i) else { pen = false; continue }
                            if pen { path.lineTo(q.dx, q.dy) } else { path.moveTo(q.dx, q.dy); pen = true }
                        }
                        let p = Paint()
                        p.style = .stroke
                        p.isAntiAlias = true
                        p.strokeWidth = max(0.5, 2.25 * k)
                        p.color = colour
                        canvas.drawPath(path, p)
                    }
                    for i in 0 ..< n where !l.unmarked.contains(i) {
                        guard let q = at(i) else { continue }
                        Self._mark(l, at: q, k: k, colour: colour, canvas)
                    }
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
                    labels.append((dataLabel(c, raw), Offset(xAt(i), vpos(v) - 9 * k), j))
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
                if c.series[j].joined {
                    // The series' line under its points, broken at a blank.
                    let p = Paint()
                    p.style = .stroke
                    p.isAntiAlias = true
                    p.strokeWidth = max(1, 1.5 * k)
                    p.strokeCap = .round
                    p.strokeJoin = .round
                    p.color = fill.color
                    let path = Path()
                    var pen = false
                    for i in 0 ..< n {
                        guard let v = c.series[j].values[safe: i] ?? nil else { pen = false; continue }
                        let x = plot.left + (c.x(i) - xs.lo) / (xs.hi - xs.lo) * plot.width
                        if pen { path.lineTo(x, vpos(v)) } else { path.moveTo(x, vpos(v)); pen = true }
                    }
                    canvas.drawPath(path, p)
                }
                for i in 0 ..< n {
                    guard let v = c.series[j].values[safe: i] ?? nil else { continue }
                    let x = plot.left + (c.x(i) - xs.lo) / (xs.hi - xs.lo) * plot.width
                    canvas.drawCircle(Offset(x, vpos(v)), max(1.5, 2.5 * k), fill)
                    labels.append((dataLabel(c, v), Offset(x, vpos(v) - 9 * k), j))
                }
            }
        case .pie, .doughnut, .radar:
            break
        }
        if clipped { canvas.restore() }
        for l in cellLabels {
            // Inside the end of its bar (`dLblPos inEnd`), in the series'
            // own label look.
            let tp = TextPainter(text: TextSpan(text: l.text, style: Flutter.TextStyle(
                color: l.series.labelColor ?? theme.text, fontSize: max(3, (l.series.labelSize ?? 12) * k),
                fontWeight: l.series.labelBold ? .bold : .normal, fontFamily: OfficeFonts.substitute(c.font ?? theme.bodyFont), fontFamilyFallback: Self.glyphFallback)),
                textDirection: .ltr)
            tp.layout(minWidth: 0, maxWidth: .infinity)
            let at = horizontal ? Offset(l.bar.right - tp.width - 3 * k, l.bar.center.dy - tp.height / 2)
                : Offset(l.bar.center.dx - tp.width / 2, l.bar.top + 3.4 * k)
            tp.paint(canvas, at)
            tp.dispose()
        }
        if c.dataLabels {
            for (s, at, j) in labels {
                // In the series' own label look where it has one.
                let ser = c.series[j]
                let tp = ser.labelSize == nil && !ser.labelBold && ser.labelColor == nil ? text(s, c.baseTextSize, .infinity)
                    : { () -> TextPainter in
                        let t = TextPainter(text: TextSpan(text: s, style: Flutter.TextStyle(
                            color: ser.labelColor ?? c.textColor ?? (c.plainText ? theme.text : _mix(theme.text, theme.background, 0.65)),
                            fontSize: max(3, (ser.labelSize ?? c.baseTextSize) * k), fontWeight: ser.labelBold ? .bold : .normal,
                            fontFamily: OfficeFonts.substitute(c.font ?? theme.bodyFont), fontFamilyFallback: Self.glyphFallback)), textDirection: .ltr)
                        t.layout(minWidth: 0, maxWidth: .infinity)
                        return t
                    }()
                let dx = horizontal && !c.stacked ? 0 : tp.width / 2
                tp.paint(canvas, Offset(at.dx - dx, at.dy - tp.height / 2))
                tp.dispose()
            }
        }
    }

    private static func _pie(_ c: Chart, _ canvas: any Canvas, _ area: Rect, k: Double, theme: DeckTheme,
                             text: (String, Double, Double) -> TextPainter, frame: Rect? = nil, ink: Color? = nil) {
        let values = c.series[0].values.map { max(0, $0 ?? 0) }
        let sum = values.reduce(0, +)
        guard sum > 0 else { return }
        // (0.97 of the room: pie-chart's, under a title beside a legend,
        // is 131 pt in PowerPoint's print, and chart_pt_color_bg1's bare
        // ring 159 — both that share of the frame inside its margin.)
        let radius = min(area.width, area.height) / 2 * 0.97
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
        var placed: [(index: Int, mid: Double, value: Double, color: Color)] = []
        // A doughnut's wedges are rings: the hole shows what is behind.
        let hole = c.type == .doughnut ? radius * Double(max(0, min(90, c.holeSize))) / 100 : 0
        let inner = Rect.fromCircle(center: centre, radius: hole)
        for (i, v) in values.enumerated() where v > 0 {
            let sweep = v / sum * 2 * .pi
            let color = c.pointColor(i, accents: theme.accents)
            fill.color = color
            if hole > 0 {
                let ring = Path()
                ring.arcTo(oval, angle, sweep, true)
                ring.arcTo(inner, angle + sweep, -sweep, false)
                ring.close()
                canvas.drawPath(ring, fill)
                canvas.drawPath(ring, edge)
            } else {
                canvas.drawArc(oval, angle, sweep, true, fill)
                canvas.drawArc(oval, angle, sweep, true, edge)
            }
            let mid = angle + sweep / 2
            let at = hole > 0 ? (radius + hole) / 2 : radius * 0.7
            labels.append((dataLabel(c, c.series[0].values[i] ?? 0),
                           Offset(centre.dx + cos(mid) * at, centre.dy + sin(mid) * at), color))
            placed.append((i, mid, v, color))
            angle += sweep
        }
        if let l = c.pieLabels {
            _pieLabels(c, l, canvas, frame: frame ?? area, slices: placed, centre: centre, rx: radius, ry: radius, inner: hole,
                       k: k, theme: theme, ink: ink ?? theme.text)
        } else if c.dataLabels {
            for (s, at, wedge) in labels {
                // Inside the wedge: white on a dark one, ink on a light one.
                let v = wedge.value
                let luma = 0.299 * Double((v >> 16) & 0xFF) + 0.587 * Double((v >> 8) & 0xFF) + 0.114 * Double(v & 0xFF)
                let tp = TextPainter(text: TextSpan(text: s, style: Flutter.TextStyle(
                    color: luma < 150 ? Color(0xFFFFFFFF) : Color(0xFF404040), fontSize: max(3, (c.baseTextSize) * k),
                    fontFamily: OfficeFonts.substitute(c.font ?? theme.bodyFont), fontFamilyFallback: Self.glyphFallback)), textDirection: .ltr)
                tp.layout(minWidth: 0, maxWidth: .infinity)
                tp.paint(canvas, Offset(at.dx - tp.width / 2, at.dy - tp.height / 2))
                tp.dispose()
            }
        }
    }
}

extension ChartPainter {
    /// A line series' mark at `q`: its symbol at its size, filled and
    /// outlined in its colours.
    static func _mark(_ l: ChartSeries, at q: Offset, k: Double, colour: Color, _ canvas: any Canvas) {
        guard let symbol = l.marker, symbol != "none" else { return }
        let r = max(1, l.markerSize * k / 2)
        let shape = Path()
        switch symbol {
        case "square": shape.addRect(Rect.fromLTRB(q.dx - r, q.dy - r, q.dx + r, q.dy + r))
        case "diamond":
            shape.moveTo(q.dx, q.dy - r); shape.lineTo(q.dx + r, q.dy); shape.lineTo(q.dx, q.dy + r); shape.lineTo(q.dx - r, q.dy); shape.close()
        case "triangle":
            shape.moveTo(q.dx, q.dy - r); shape.lineTo(q.dx + r, q.dy + r); shape.lineTo(q.dx - r, q.dy + r); shape.close()
        default: shape.addOval(Rect.fromLTRB(q.dx - r, q.dy - r, q.dx + r, q.dy + r))
        }
        let p = Paint()
        p.isAntiAlias = true
        p.style = .fill
        p.color = l.markerFill ?? colour
        canvas.drawPath(shape, p)
        p.style = .stroke
        p.strokeWidth = max(0.5, 0.75 * k)
        p.color = l.markerLine ?? l.markerFill ?? colour
        canvas.drawPath(shape, p)
    }

    /// A radar chart: a spoke for each category from the middle, rings of
    /// the value axis's steps joining the spokes, and each series a closed
    /// line (or a filled shape) through its values, category 1 at the top
    /// and the rest clockwise — POI's radar-chart as PowerPoint draws it.
    static func _radar(_ c: Chart, _ canvas: any Canvas, _ area: Rect, k: Double, theme: DeckTheme, grid: Color,
                       text: (String, Double, Double) -> TextPainter,
                       categoryText: (String, Double, Double) -> TextPainter) {
        let n = c.categories.count
        guard n >= 3 else { return }
        let values = c.series.flatMap { $0.values.compactMap { $0 } }
        let auto = scale(min(0, values.min() ?? 0), values.max() ?? 1, intervals: 8)
        let sc = fixedScale(auto: auto, min: c.valueMin, max: c.valueMax, step: c.valueStep)
        let labelSize = c.valueLabelSize ?? c.baseTextSize
        let catSize = c.categoryLabelSize ?? c.baseTextSize
        let catLabels = c.categories.map { categoryText(c.categoryAxisDeleted ? "" : $0, catSize, .infinity) }
        let room = (catLabels.map(\.height).max() ?? 12 * k) + 4 * k
        let wide = (catLabels.map(\.width).max() ?? 0) + 4 * k
        let radius = max(4, min(area.width / 2 - wide, area.height / 2 - room))
        let centre = area.center
        func point(_ i: Int, _ r: Double) -> Offset {
            let a = -Double.pi / 2 + Double(i) * 2 * .pi / Double(n)
            return Offset(centre.dx + cos(a) * r, centre.dy + sin(a) * r)
        }
        func r(_ v: Double) -> Double { radius * (v - sc.lo) / max(1e-9, sc.hi - sc.lo) }
        let gridPaint = Paint()
        gridPaint.style = .stroke
        gridPaint.strokeWidth = max(0.5, (c.gridWidth ?? 0.75) * k)
        gridPaint.color = grid
        // The spokes, then a ring at each step.
        for i in 0 ..< n { canvas.drawLine(centre, point(i, radius), gridPaint) }
        let ticks = Array(stride(from: sc.lo, through: sc.hi + sc.step * 1e-6, by: sc.step))
        if c.valueGrid {
            for v in ticks where v > sc.lo {
                let ring = Path()
                let p0 = point(0, r(v))
                ring.moveTo(p0.dx, p0.dy)
                for i in 1 ..< n { let q = point(i, r(v)); ring.lineTo(q.dx, q.dy) }
                ring.close()
                canvas.drawPath(ring, gridPaint)
            }
        }
        // The value axis's labels up the first spoke, to its left.
        if !c.valueAxisDeleted {
            for v in ticks {
                let tp = text(label(v, percent: c.percent), labelSize, .infinity)
                let at = point(0, r(v))
                tp.paint(canvas, Offset(at.dx - 4 * k - tp.width, at.dy - tp.height / 2))
                tp.dispose()
            }
        }
        // The categories outside the spokes' ends.
        for (i, tp) in catLabels.enumerated() {
            let a = -Double.pi / 2 + Double(i) * 2 * .pi / Double(n)
            let end = point(i, radius + 3 * k)
            let dx = cos(a), dy = sin(a)
            let x = abs(dx) < 0.2 ? end.dx - tp.width / 2 : dx > 0 ? end.dx : end.dx - tp.width
            let y = abs(dy) < 0.2 ? end.dy - tp.height / 2 : dy > 0 ? end.dy : end.dy - tp.height
            tp.paint(canvas, Offset(x, y))
            tp.dispose()
        }
        // The series.
        for (j, series) in c.series.enumerated() {
            let path = Path()
            var started = false
            for i in 0 ..< n {
                guard let v = series.values[safe: i] ?? nil else { continue }
                let q = point(i, r(v))
                if started { path.lineTo(q.dx, q.dy) } else { path.moveTo(q.dx, q.dy); started = true }
            }
            guard started else { continue }
            path.close()
            let p = Paint()
            p.isAntiAlias = true
            p.color = c.color(series: j, accents: theme.accents)
            if c.radarFilled {
                p.style = .fill
            } else {
                p.style = .stroke
                p.strokeWidth = max(0.5, 2.25 * k)
                p.strokeJoin = .round
            }
            canvas.drawPath(path, p)
        }
    }

    /// A colour's channels times `f`.
    static func _scaled(_ c: Color, _ f: Double) -> Color {
        let v = c.value
        func ch(_ sh: Int) -> Int64 { Int64((Double((v >> sh) & 0xFF) * f).rounded()) }
        return Color(Int64(0xFF00_0000) | ch(16) << 16 | ch(8) << 8 | ch(0))
    }

    /// A 3-D pie: the disc tilted by `tilt` degrees, its rim showing below
    /// in each slice's colour darkened toward the front — as PowerPoint's
    /// print of LIBRE_OFFICE-100610-0 has it at 30°: the disc 0.473 as
    /// tall as wide, the rim 0.228 of the radius deep, filling 94% of the
    /// plot's width or 97% of its height, the rim 0.575 of the colour at
    /// the front and 0.875 at the sides.
    static func _pie3D(_ c: Chart, _ canvas: any Canvas, _ plot: Rect, tilt: Double, k: Double, theme: DeckTheme,
                       frame: Rect? = nil, ink: Color? = nil) {
        let values = c.series[0].values.map { max(0, $0 ?? 0) }
        let sum = values.reduce(0, +)
        guard sum > 0 else { return }
        let squash = sin(max(5, min(90, tilt)) * .pi / 180) * 0.946
        let deep = 0.228
        let rx = min(plot.width * 0.941 / 2, plot.height * 0.972 / (2 * squash + deep)) / (1 + c.pieExplosion)
        let ry = rx * squash, depth = rx * deep
        let centre = Offset(plot.center.dx, plot.center.dy - depth / 2)
        func at(_ a: Double, _ drop: Double = 0) -> Offset { Offset(centre.dx + cos(a) * rx, centre.dy + sin(a) * ry + drop) }
        // The slices, clockwise from twelve o'clock.
        var slices: [(from: Double, to: Double, color: Color, value: Double)] = []
        var angle = -Double.pi / 2
        for (i, v) in values.enumerated() where v > 0 {
            let sweep = v / sum * 2 * .pi
            slices.append((angle, angle + sweep, c.pointColor(i, accents: theme.accents), v))
            angle += sweep
        }
        let fill = Paint()
        fill.style = .fill
        fill.isAntiAlias = true
        // The rim: the front half (angles 0…π, below the centre), in steps
        // a few degrees wide, each shaded for the way it faces.
        func scaled(_ c: Color, _ f: Double) -> Color {
            let v = c.value
            func ch(_ sh: Int) -> Int64 { Int64((Double((v >> sh) & 0xFF) * f).rounded()) }
            return Color(Int64(0xFF00_0000) | ch(16) << 16 | ch(8) << 8 | ch(0))
        }
        for s in slices {
            var a = s.from
            while a < s.to {
                let b = min(s.to, a + 3 * .pi / 180)
                // The same part of the circle a turn on, where it shows.
                for turn in [-2 * Double.pi, 0, 2 * Double.pi] {
                    // (Each step a little past the next, so no seam shows
                    // between them; the next one covers the overlap.)
                    let lo = max(a + turn, 0), hi = min(b + turn + 0.01, .pi)
                    guard hi > lo else { continue }
                    let p = Path()
                    let p0 = at(lo)
                    p.moveTo(p0.dx, p0.dy)
                    let steps = max(1, Int((hi - lo) / (0.5 * .pi / 180)))
                    for j in 1 ... steps { let q = at(lo + (hi - lo) * Double(j) / Double(steps)); p.lineTo(q.dx, q.dy) }
                    for j in stride(from: steps, through: 0, by: -1) {
                        let q = at(lo + (hi - lo) * Double(j) / Double(steps), depth); p.lineTo(q.dx, q.dy)
                    }
                    p.close()
                    fill.color = scaled(s.color, 0.575 + 0.3 * abs(cos((lo + hi) / 2)))
                    canvas.drawPath(p, fill)
                }
                a = b
            }
        }
        // The top: each slice a wedge of the ellipse.
        let edge = Paint()
        edge.style = .stroke
        edge.isAntiAlias = true
        edge.strokeWidth = max(0.5, 1 * k)
        edge.color = theme.background
        for s in slices {
            let p = Path()
            p.moveTo(centre.dx, centre.dy)
            let steps = max(2, Int((s.to - s.from) / (1 * .pi / 180)))
            for j in 0 ... steps { let q = at(s.from + (s.to - s.from) * Double(j) / Double(steps)); p.lineTo(q.dx, q.dy) }
            p.close()
            fill.color = s.color
            canvas.drawPath(p, fill)
            canvas.drawPath(p, edge)
        }
        if let l = c.pieLabels {
            var placed: [(index: Int, mid: Double, value: Double, color: Color)] = []
            var a = -Double.pi / 2
            for (i, v) in values.enumerated() where v > 0 {
                let sweep = v / sum * 2 * .pi
                placed.append((i, a + sweep / 2, v, c.pointColor(i, accents: theme.accents)))
                a += sweep
            }
            _pieLabels(c, l, canvas, frame: frame ?? plot, slices: placed, centre: centre, rx: rx, ry: ry, inner: 0,
                       k: k, theme: theme, ink: ink ?? theme.text)
        } else if c.dataLabels {
            for s in slices {
                let mid = (s.from + s.to) / 2
                let pt = Offset(centre.dx + cos(mid) * rx * 0.7, centre.dy + sin(mid) * ry * 0.7)
                let v = s.color.value
                let luma = 0.299 * Double((v >> 16) & 0xFF) + 0.587 * Double((v >> 8) & 0xFF) + 0.114 * Double(v & 0xFF)
                let tp = TextPainter(text: TextSpan(text: dataLabel(c, s.value), style: Flutter.TextStyle(
                    color: luma < 150 ? Color(0xFFFFFFFF) : Color(0xFF404040), fontSize: max(3, (c.baseTextSize) * k),
                    fontFamily: OfficeFonts.substitute(c.font ?? theme.bodyFont), fontFamilyFallback: Self.glyphFallback)), textDirection: .ltr)
                tp.layout(minWidth: 0, maxWidth: .infinity)
                tp.paint(canvas, Offset(pt.dx - tp.width / 2, pt.dy - tp.height / 2))
                tp.dispose()
            }
        }
    }

    /// A pie's or doughnut's labels as `Chart.pieLabels` sets them: each
    /// at its slice's middle — outside the pie, beside it, for `outEnd`
    /// and `bestFit`, else halfway into the slice (the ring, for a
    /// doughnut) — moved by its own layout's fraction of the chart's
    /// frame, in its box, and tied to its slice by a leader line once it
    /// has left it. `slices`: each point's index, middle angle, value and
    /// colour; `rx`, `ry` the pie's radii (`ry` smaller when tilted),
    /// `inner` the doughnut's hole's.
    static func _pieLabels(_ c: Chart, _ l: Chart.PieLabels, _ canvas: any Canvas, frame: Rect,
                           slices: [(index: Int, mid: Double, value: Double, color: Color)],
                           centre: Offset, rx: Double, ry: Double, inner: Double, k: Double, theme: DeckTheme, ink: Color) {
        let sum = slices.reduce(0) { $0 + $1.value }
        guard sum > 0 else { return }
        for s in slices {
            let size = max(3, (l.sizes[s.index] ?? c.series[0].labelSize ?? c.baseTextSize) * k)
            var parts: [String] = []
            if l.series { parts.append(c.series[0].name) }
            if l.category, s.index < c.categories.count { parts.append(c.categories[s.index]) }
            if l.value { parts.append(dataLabel(c, s.value)) }
            if l.percent {
                let share = s.value / sum
                if let code = c.labelFormat, code.contains("%") {
                    parts.append(NumberFormat.format(share, code, width: 40).text.trimmingWhitespace())
                } else { parts.append("\(Int((share * 100).rounded()))%") }
            }
            guard !parts.isEmpty else { continue }
            let text = parts.joined(separator: l.separator ?? (parts.count > 1 ? "; " : ""))
            let dark = { () -> Bool in
                let v = s.color.value
                return 0.299 * Double((v >> 16) & 0xFF) + 0.587 * Double((v >> 8) & 0xFF) + 0.114 * Double(v & 0xFF) < 150
            }()
            let colour = c.series[0].labelColor ?? (l.outside || l.fill != nil ? ink : dark ? Color(0xFFFFFFFF) : Color(0xFF404040))
            let tp = TextPainter(text: TextSpan(text: text, style: Flutter.TextStyle(
                color: colour, fontSize: size, fontWeight: c.series[0].labelBold ? .bold : .normal,
                fontFamily: OfficeFonts.substitute(c.font ?? theme.bodyFont), fontFamilyFallback: Self.glyphFallback)), textAlign: .center, textDirection: .ltr)
            // (Excel wraps a long label at about a fifth of the chart's width:
            // 45544's "Finance - Investment Banking" is three lines.)
            tp.layout(minWidth: 0, maxWidth: max(20 * k, frame.width * 0.2))
            let pad = 3 * k
            let w = tp.width + pad * 2, h = tp.height + pad
            let dx = cos(s.mid), dy = sin(s.mid)
            // Where the label stands before its own move: its box's middle.
            var at: Offset
            if l.outside {
                let gap = 4 * k
                let edge = Offset(centre.dx + dx * rx, centre.dy + dy * ry)
                at = Offset(edge.dx + dx * gap + (dx >= 0 ? w / 2 : -w / 2), edge.dy + dy * gap + dy * h / 2)
            } else {
                let r = inner > 0 ? (rx + inner) / 2 : rx * 0.7
                at = Offset(centre.dx + dx * r, centre.dy + dy * r * (ry / max(rx, 1)))
            }
            let moved = l.moves[s.index]
            if let m = moved { at = Offset(at.dx + m[0] * frame.width, at.dy + m[1] * frame.height) }
            let box = Rect.fromLTWH(at.dx - w / 2, at.dy - h / 2, w, h)
            // The leader: from the slice's outer edge to the box's nearest
            // point, where the label has left its slice.
            if l.leaders, moved != nil || l.outside {
                let from = Offset(centre.dx + dx * rx, centre.dy + dy * ry)
                let to = Offset(min(max(from.dx, box.left), box.right), min(max(from.dy, box.top), box.bottom))
                if hypot(to.dx - from.dx, to.dy - from.dy) > 2 * k {
                    let p = Paint()
                    p.style = .stroke
                    p.isAntiAlias = true
                    p.strokeWidth = max(0.5, l.leaderWidth * k)
                    p.color = l.leaderColor ?? ink
                    canvas.drawLine(from, to, p)
                }
            }
            if let f = l.fill {
                let p = Paint()
                p.style = .fill
                p.color = f
                canvas.drawRect(box, p)
            }
            if let line = l.line {
                let p = Paint()
                p.style = .stroke
                p.strokeWidth = max(0.5, l.lineWidth * k)
                p.color = line
                canvas.drawRect(box, p)
            }
            tp.paint(canvas, Offset(box.left + pad, box.top + pad / 2))
            tp.dispose()
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
