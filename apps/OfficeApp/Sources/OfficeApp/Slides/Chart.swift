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
import OfficeText
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
    /// The numbers' own format (`c:val`'s `c:formatCode`) where it is
    /// not General: how a data table shows them ("48.95%").
    var format: String? = nil
    /// A colour the file set as itself; nil follows the theme.
    var color: Color? = nil
    /// The series' own number (`c:idx`) where it is not its place: the
    /// theme's colour it takes when it sets none (47813's Sine and Cosine,
    /// idx 1 and 2, red and green where first and second were blue and red).
    var autoIndex: Int? = nil
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
    /// A combination's line with its values by its points (`c:dLbls`
    /// showVal, above them), and where single ones are moved
    /// (`c:dLbl/c:layout`, fractions of the chart's frame): zh-547fc43c's
    /// growth rates over its columns in Word's print.
    var valueLabels = false
    var labelNudges: [Int: Offset] = [:]
    /// Where those labels stand by their points (`c:dLblPos`): nil is
    /// Excel's default for a line, to the right ("r").
    var labelPos: String? = nil
    /// Those labels' own number format (`c:dLbls/c:numFmt`, not linked
    /// to the source); else they show the line's numbers' (`format`).
    var labelCode: String? = nil
}

struct Chart: Equatable {
    var type: ChartType
    /// Shown above the plot; nil for none.
    var title: String?
    /// The title's own size in points, weight and colour where the file
    /// gives them (its first run's, else the title's default run
    /// properties); nil is PowerPoint's default for a chart title.
    var titleSize: Double? = nil
    /// A size of a title's later paragraph where it differs from the
    /// first's, by line of `title` (aascu 5864's 14 pt titles with a 12 pt
    /// line under them).
    var titleLineSizes: [Int: Double] = [:]
    var titleBold = false
    var titleColor: Color? = nil
    /// The title's own box (`c:title/c:spPr`): its fill, and its outline
    /// and that line's width in points; nil is none.
    var titleFill: Color? = nil
    var titleLine: Color? = nil
    var titleLineWidth = 0.75
    /// Its dash (`a:prstDash`, nil solid) and round ends (`cap="rnd"`).
    var titleLineDash: String? = nil
    var titleLineRound = false
    /// The first column of the data: category names, or for a scatter
    /// chart the x values.
    var categories: [String]
    var series: [ChartSeries]
    var legend = true
    /// `c:legendPos`: "b" below the plot (what a new chart gets), "t" above,
    /// "r", "l" or "tr" beside it, one entry to a line.
    var legendPosition = "b"
    /// The legend's entries the file deletes (`c:legendEntry/c:delete`):
    /// series, or a pie's points, by index — not drawn.
    var hiddenLegendEntries: Set<Int> = []
    /// The legend's text size in points where the file gives one
    /// (`c:legend/c:txPr`); nil is the default, 12.
    var legendSize: Double? = nil
    var dataLabels = false
    /// `c:grouping`: clustered/standard, stacked or percentStacked.
    var stacked = false
    var percent = false
    var categoryAxisTitle: String? = nil
    var valueAxisTitle: String? = nil
    /// The axis titles' size where their text says nothing at all of its
    /// look (`bareTitles`); nil is the usual.
    var axisTitleSize: Double? = nil
    /// An axis title the file places itself (`c:title/c:layout`, edge-mode
    /// x and y of the chart's frame), set across and in its own size: the
    /// unit over zh-547fc43c's charts, "亿元" at their top left in Word's
    /// print. nil takes a band beside the plot.
    var categoryAxisTitleAt: PlacedAxisTitle? = nil
    var valueAxisTitleAt: PlacedAxisTitle? = nil
    /// A value axis' title the file sets across (`a:bodyPr rot="0"`) and does not place: a block of centred
    /// lines at the left, where it is usually turned.
    var valueAxisTitleAcross = false
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
    /// The value axis `lineSeries` stand on where it is not the columns'
    /// (a combination's second value axis, at the right); nil: they share
    /// the columns'.
    var secondValueAxis: SecondValueAxis? = nil
    /// A table of the numbers under the plot (`c:dTable`): the
    /// categories over its columns, a row for each series (columns,
    /// then lines) with its key and name before it. nil: none.
    var dataTable: DataTable? = nil
    /// The legend's own place (`c:legend/c:layout/c:manualLayout`, edge
    /// mode), as fractions of the chart's frame: entries in a row in it,
    /// the plot keeping its room. nil: beside the plot by `legendPosition`.
    var legendBox: Rect? = nil
    /// The title's own place (`c:title/c:layout/c:manualLayout`, edge
    /// mode): its box's top left, as fractions of the chart's frame, the
    /// plot keeping its room. nil: centred at the top.
    var titleAt: Offset? = nil
    /// A 3-D pie's tilt toward the viewer (`c:view3D/c:rotX`, degrees): drawn
    /// as a disc seen from above at that angle, its rim showing below. nil
    /// is a flat pie.
    var pieTilt: Double? = nil
    /// A 3-D pie's turn (`c:view3D/c:rotY`, degrees): its first slice
    /// starts that far clockwise from twelve o'clock. Lab p3dfit (Word for
    /// Mac, zh-27a874b7's chart 2): a slice turned by it to three or nine
    /// o'clock prints there, its label with it; ours started at twelve.
    var pieTurn = 0.0
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
    /// A surface chart (`c:surface3DChart`, `c:surfaceChart`): its series'
    /// values a grid over its categories, drawn as a surface seen at
    /// `surfaceView` (rotX, rotY, degrees), each face in its value band's
    /// colour (`_surface`). Read as an area chart otherwise.
    var surface = false
    var surfaceView = Offset(15, 20)
    struct BarView: Equatable {
        var x: Double; var y: Double; var depth: Double = 1; var gapDepth: Double = 1.5
        /// The floor's and back wall's edges are drawn; not where both
        /// say no line (`c:floor`, `c:backWall` `a:ln/a:noFill`) —
        /// LIBRE_OFFICE-100610's survey bars stand in no box at all in
        /// PowerPoint's print.
        var walled = true
    }
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
    /// A pie of pie or bar of pie (`c:ofPieChart`): which points leave the
    /// main pie for the second plot, which stands beside it.
    var ofPie: OfPie? = nil
    struct OfPie: Equatable {
        var bar = false
        /// The points in the second plot, by index.
        var second: Set<Int> = []
        /// Its size, a share of the main pie's (`c:secondPieSize`, 75%).
        var size = 0.75
    }
    /// A bar chart of one series whose points each take a colour of
    /// their own (`c:varyColors`): they cycle as a pie's slices do, and
    /// the legend names the categories, as a pie's does
    /// (chart-DataTable-MultipleLegendEntriesForOneDataSeries' twelve).
    var variedPoints = false
    /// An Excel 2016 waterfall (`layoutId="waterfall"`): its one series'
    /// values are steps, each column floating from the running total
    /// before it to the one after, save these points, totals, which stand
    /// on zero. nil for any other chart. `waterfallConnectors`: a thin
    /// line from each column's end to the next one's start.
    var waterfallTotals: Set<Int>? = nil
    var waterfallConnectors = false
    /// An Excel 2016 histogram (clustered columns, binned): its one
    /// series' samples counted into bins, the bins its categories.
    var histogram: HistogramBins? = nil
    /// A pareto (`layoutId="paretoLine"` over a histogram): its bins
    /// largest first, and a line of their running share on a second axis,
    /// 0% to 100%.
    var pareto = false

    /// Counts samples `xs` into the histogram's bins, and for a pareto
    /// orders them and draws its line.
    mutating func applyHistogram(_ xs: [Double]) {
        guard let spec = histogram, !series.isEmpty else { return }
        var b = spec.bins(xs)
        if pareto {
            let order = b.counts.indices.sorted { b.counts[$0] > b.counts[$1] || (b.counts[$0] == b.counts[$1] && $0 < $1) }
            b = (order.map { b.labels[$0] }, order.map { b.counts[$0] })
            let total = b.counts.reduce(0, +)
            var run = 0.0
            let shares: [Double?] = b.counts.map { run += $0; return total > 0 ? run / total : nil }
            lineSeries = [ChartSeries(name: "", values: shares)]
            secondValueAxis = SecondValueAxis(format: "0%", min: 0, max: 1, step: 0.1)
        }
        categories = b.labels
        series[0].values = b.counts
    }

    /// A histogram's binning (`cx:binning`): a bin's width (nil: Scott's
    /// rule, as Excel's automatic bins), and the edges below and above
    /// which the rest fall in one bin each.
    struct HistogramBins: Equatable {
        var size: Double? = nil
        var underflow: Double? = nil
        var overflow: Double? = nil

        /// The bins of samples `xs`: their labels and counts, as Excel
        /// prints them — "[10, 13.9]" first, "(13.9, 17.8]" after, "≤ 11"
        /// and "> 14" for the ends (chart-SimpleHistogram, chart-tdf163727's).
        func bins(_ xs: [Double]) -> (labels: [String], counts: [Double]) {
            guard let lo0 = xs.min(), let hi0 = xs.max() else { return ([], []) }
            func show(_ v: Double) -> String { ChartPainter.label(v, percent: false) }
            let lo = underflow ?? lo0, hi = overflow ?? hi0
            var width = size ?? 0
            if width <= 0 {
                // Scott's: 3.5 standard deviations over the cube root of the
                // count, to two figures (3.937 is 3.9 in Excel's labels).
                let n = Double(xs.count), mean = xs.reduce(0, +) / n
                let sd = n > 1 ? (xs.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / (n - 1)).squareRoot() : 0
                let raw = 3.5 * sd / pow(n, 1.0 / 3)
                if raw > 0 {
                    let mag = pow(10, floor(log10(raw)) - 1)
                    width = (raw / mag).rounded() * mag
                } else {
                    width = 1
                }
            }
            var labels: [String] = [], counts: [Double] = []
            if let u = underflow { labels.append("≤ \(show(u))"); counts.append(Double(xs.filter { $0 <= u }.count)) }
            var edge = lo
            var first = underflow == nil
            repeat {
                // (The last a whole bin's width, past the largest sample,
                // unless an overflow bin takes the rest: "(13.94, 17.88]"
                // over samples to 15, chart-pareto-gapwidth's "(8, 11.5]"
                // to 9, in Excel's prints.)
                let top = overflow == nil ? edge + width : min(edge + width, hi)
                labels.append((first ? "[" : "(") + "\(show(edge)), \(show(top))]")
                counts.append(Double(xs.filter { (first ? $0 >= edge : $0 > edge) && $0 <= top }.count))
                first = false
                edge = top
            } while edge < hi - 1e-9 && labels.count < 1000
            if let o = overflow { labels.append("> \(show(o))"); counts.append(Double(xs.filter { $0 > o }.count)) }
            return (labels, counts)
        }
    }

    /// An Excel 2016 funnel (`layoutId="funnel"`): its one series' values
    /// as bars centred across the plot, top first, with no value axis.
    var funnel = false
    /// An Excel 2016 sunburst (`layoutId="sunburst"`): its points as a
    /// tree, a ring to each level of it, each node the sum of the points
    /// under it. nil for any other chart.
    var sunburst: [SunburstNode]? = nil
    struct SunburstNode: Equatable {
        var name: String
        var value = 0.0
        /// Its top-level branch's place in the file, which picks the
        /// accent every wedge of that branch is filled with.
        var color = 0
        var children: [SunburstNode] = []
    }
    /// An Excel 2016 treemap (`layoutId="treemap"`): the `sunburst` tree
    /// drawn as nested rectangles instead of rings.
    var treemap = false

    /// A waterfall's columns, by point: where each starts and ends.
    var waterfallSpans: [(from: Double, to: Double)] {
        guard let totals = waterfallTotals, let s = series.first else { return [] }
        var run = 0.0
        return s.values.enumerated().map { i, v in
            let v = v ?? 0
            if totals.contains(i) { run = v; return (0, v) }
            defer { run += v }
            return (run, run + v)
        }
    }
    /// A box-and-whisker chart (Office 2016's `cx:` part, series laid out
    /// "boxWhisker"): each series' samples, category by category, drawn
    /// as boxes on a column chart's axes. nil for any other chart.
    var boxes: [[[Double]]]? = nil
    /// The room between categories, a share of a category's boxes
    /// (`cx:catScaling gapWidth`); the quartiles' method, and whether the
    /// mean's mark and the outliers are drawn.
    var boxGap = 1.0
    /// Read from a chartex part (`cx:`), which Word lays out closer to its
    /// frame than a `c:` chart.
    var chartex = false
    /// Its text marked Chinese, Japanese or Korean (`lang` on a run's
    /// properties): Word sets such a chart's labels higher
    /// (`_wordLabelRise`).
    var eastAsianText = false
    /// Its East Asian text is set as Word for Windows sets a theme with no
    /// East Asian face: in MS Mincho, and Microsoft JhengHei for what
    /// Mincho lacks (`OfficeFonts.windowsMinchoCovers`) — so a data
    /// table's rows stand on those faces' lines (`_tableRows`).
    var windowsMinchoText = false
    /// … and its title too: not where the title's runs say Traditional
    /// Chinese, which Word for Windows sets in PMingLiU (zh-b8de3ae2's
    /// eleven titles, `lang="zh-TW"`, in its print).
    var windowsMinchoTitle = false
    /// Its East Asian text is set as Word for Mac sets a theme with no
    /// East Asian face: in the theme's Simplified Chinese face (`a:font
    /// script="Hans"`, 宋体 where it names none), where the platform's
    /// fallback would take YaHei — a line 1.32 em tall to SimSun's 1.15.
    /// Word for Mac's prints of zh-27a874b7's, zh-d62da4dd's and
    /// zh-61aaad09's charts, their themes' `a:ea` "" and Hans 宋体: every
    /// label's names in SimSun, a 3-line 10pt label 36.1pt tall where
    /// ours, in YaHei, stood 37.6; zh-b8de3ae2's pie under a theme
    /// override whose Hans face is 等线: its labels in DengXian.
    var macSimplifiedFace: String? = nil
    /// … and text whose runs say Traditional Chinese (`lang="zh-TW"`) in
    /// its Hant face: zh-b8de3ae2's titles and its labels' zh-TW fields
    /// in PMingLiU (新細明體) in Word for Mac's print, beside the same
    /// chart's untagged axes in SimSun.
    var macTraditionalFace: String? = nil
    /// Its title's runs say Traditional Chinese (`macTraditionalFace`).
    var titleTraditional = false
    var boxInclusive = false
    var boxMeans = true
    var boxOutliers = true
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
    /// A gradient the chart area is filled with instead (drawn, not yet
    /// written back: `areaFill` holds its first stop).
    var areaGradient: SlideFill? = nil
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
        /// Outside only for a best fit (`bestFit`), which a 3-D pie
        /// keeps inside its slices.
        var fitted = false
        var moves: [Int: [Double]] = [:]
        /// A point's own text size, from its label's own rich text.
        var sizes: [Int: Double] = [:]
        /// A point's label as the file writes it (`c:dLbl/c:tx/c:rich`),
        /// shown as it stands: zh-61aaad09's pie says "109646, 15.85%".
        var texts: [Int: String] = [:]
        /// The points whose own rich text says Traditional Chinese
        /// (`Chart.macTraditionalFace`).
        var traditional: Set<Int> = []
        var fill: Color? = nil
        var line: Color? = nil
        var lineWidth = 0.75
        var leaders = false
        var leaderColor: Color? = nil
        var leaderWidth = 0.75
    }
    var pieLabels: PieLabels? = nil
    /// A pie's labels stand round it (shown, at a best fit, the outer end
    /// or where nothing says: Excel's default): the room they take.
    var pieLabelsAround = false

    /// The chart with every text size the file states times `f`, those it
    /// leaves to the default as they are. A sheet's chart is painted at
    /// three quarters of the page's scale, which makes PowerPoint's default
    /// sizes Excel's (18.6 and 12 pt against 14 and 9); a size the file
    /// states Excel prints as stated — 45544's 16 pt title at 14.4 on a
    /// 90% page, where ours made 10.8 — so the sheet scales those back.
    func statedTextScaled(by f: Double) -> Chart {
        var c = self
        c.titleSize = titleSize.map { $0 * f }
        c.titleLineSizes = titleLineSizes.mapValues { $0 * f }
        c.legendSize = legendSize.map { $0 * f }
        c.valueLabelSize = valueLabelSize.map { $0 * f }
        c.categoryLabelSize = categoryLabelSize.map { $0 * f }
        c.textSize = textSize.map { $0 * f }
        c.axisTitleSize = axisTitleSize.map { $0 * f }
        // (And the title's box's line, which is as stated too:
        // chart-tdf135184's 3 pt.)
        c.titleLineWidth = titleLineWidth * f
        for i in c.series.indices { c.series[i].labelSize = series[i].labelSize.map { $0 * f } }
        // (A data table's own size too: chart-DataTable-Multiple…'s 9 pt,
        // which stood 6.8 on the sheet.)
        if var t = dataTable {
            t.size = t.size.map { $0 * f }
            t.lineWidth = t.lineWidth.map { $0 * f }
            c.dataTable = t
        }
        if var l = pieLabels {
            l.sizes = l.sizes.mapValues { $0 * f }
            c.pieLabels = l
        }
        return c
    }
    /// The value axis draws its gridlines (`c:majorGridlines`).
    var valueGrid = true
    /// A scatter chart's gridlines up from its X axis (`c:majorGridlines`
    /// on the bottom or top `c:valAx`).
    var scatterXGrid = true
    /// An axis the file deletes (`c:delete`): no labels, no room for them.
    var valueAxisDeleted = false
    /// The axes' tick marks stand outside them (`c:majorTickMark` "out" or
    /// "cross"), and the labels stand that much further off.
    var valueTicksOut = false
    /// The chart names an Office chart style (`c:style`): one an Office
    /// application wrote, not LibreOffice.
    var officeStyled = true
    /// Painted on a slide (set by the slide painter), where a few of
    /// PowerPoint's measures differ from Word's and Excel's.
    var onSlide = false
    /// Printed on a sheet (set by the sheet's painter), where Excel's
    /// measures are its own.
    var onSheet = false
    /// A stock chart's lines from each category's highest value to its
    /// lowest (`c:hiLowLines`): their colour (nil, the text's) and width.
    var highLowLines: HighLowLines? = nil
    var categoryTicksOut = false
    var categoryAxisDeleted = false
    /// The axes' own lines are drawn (no `a:ln/a:noFill` in their
    /// `c:spPr`). Not the value axis' of a new chart, which is written
    /// without one.
    var valueLine = false
    var categoryLine = true
    /// `c:catAx/c:tickLblPos` low: the category labels at the plot's foot
    /// however far below zero its values go. Otherwise (`nextTo`, the
    /// default) they stand by the axis, at zero: chart-invertIfNeg_bar's
    /// under its zero line, mid-plot, where ours were at the foot.
    var categoryLabelsLow = false
    /// A combination whose columns stand on the right-hand value axis and
    /// its lines on the left (chart-testCombinedChartAxis): the category
    /// axis crosses the lines' axis, whose scale this app does not keep.
    var columnsOnRight = false

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
        let s = i < series.count ? series[i] : lineSeries[safe: i - series.count]
        if let c = s?.color { return c }
        if let scheme = s?.scheme, scheme.hasPrefix("accent"), let n = Int(scheme.dropFirst(6)), (1 ... 6).contains(n) {
            return accents[n - 1]
        }
        if let k = monochromeAccent { return Self.monochrome(i, of: series.count, accents[k - 1]) }
        return Self.cycle(s?.autoIndex ?? i, accents)
    }

    /// Series `i`'s line where the file gives it no colour of its own: in
    /// a 2007-style chart on a slide, the colour shaded to 95% (in linear
    /// light) and saturated 105%, as Office 2007's chart styles draw a
    /// line — line-chart's 4F81BD series prints 4A7EBB, and so do radar-
    /// chart's line and the rims of scatter-chart's marks.
    func lineColor(series i: Int, accents: [Color]) -> Color {
        let base = color(series: i, accents: accents)
        guard onSlide, !styled2013, officeStyled, i < series.count, series[i].color == nil, series[i].scheme == nil else { return base }
        func lin(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        func srgb(_ l: Double) -> Double { l <= 0.0031308 ? l * 12.92 : 1.055 * pow(l, 1 / 2.4) - 0.055 }
        let r = srgb(lin(Double((base.value >> 16) & 0xFF) / 255) * 0.95)
        let g = srgb(lin(Double((base.value >> 8) & 0xFF) / 255) * 0.95)
        let b = srgb(lin(Double(base.value & 0xFF) / 255) * 0.95)
        // Saturation by 105%, in HSL.
        let hi = max(r, g, b), lo = min(r, g, b), l = (hi + lo) / 2
        guard hi > lo else { return Color(0xFF00_0000 | Int64((Int((r * 255).rounded()) << 16) | (Int((g * 255).rounded()) << 8) | Int((b * 255).rounded()))) }
        let d = hi - lo, sat = l > 0.5 ? d / (2 - hi - lo) : d / (hi + lo)
        let s2 = min(1, sat * 1.05)
        func out(_ c: Double) -> Int {
            // Each channel's distance from the lightness, scaled as the
            // saturation is (the hue and lightness kept).
            let span = l > 0.5 ? s2 * (2 - 2 * l) : s2 * 2 * l
            let old = l > 0.5 ? sat * (2 - 2 * l) : sat * 2 * l
            let v = old > 0 ? l + (c - l) * span / old : c
            return Int((max(0, min(1, v)) * 255).rounded())
        }
        return Color(0xFF00_0000 | Int64((out(r) << 16) | (out(g) << 8) | out(b)))
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
    /// A box-and-whisker chart in a `cx:chartSpace` (Word and Excel 2016's
    /// chartex part): its series' samples grouped by category, on a column
    /// chart's axes, in a 2013-style chart's text (14 pt title, 9 pt labels,
    /// grey). nil for any other `cx:` chart — its Fallback picture stands.
    static func readBoxWhisker(_ space: XNode) -> Chart? {
        guard let chart = space.first("cx:chart"),
              let region = chart.first("cx:plotArea")?.first("cx:plotAreaRegion") else { return nil }
        let all = region.all("cx:series")
        guard !all.isEmpty, all.allSatisfy({ $0["layoutId"] == "boxWhisker" }) else { return nil }
        func points(_ dim: XNode?) -> [String?] {
            guard let lvl = dim?.first("cx:lvl") else { return [] }
            var out = [String?](repeating: nil, count: min(1_000_000, max(0, Int(lvl["ptCount"] ?? "") ?? 0)))
            for pt in lvl.all("cx:pt") {
                guard let i = Int(pt["idx"] ?? ""), i >= 0, i < 1_000_000 else { continue }
                if i >= out.count { out += [String?](repeating: nil, count: i - out.count + 1) }
                out[i] = pt.text
            }
            return out
        }
        var data: [String: (cats: [String?], vals: [String?])] = [:]
        for d in space.first("cx:chartData")?.all("cx:data") ?? [] {
            let cat = d.all("cx:strDim").first { $0["type"] == "cat" } ?? d.first("cx:strDim")
            let val = d.all("cx:numDim").first { $0["type"] == "val" } ?? d.first("cx:numDim")
            data[d["id"] ?? ""] = (points(cat), points(val))
        }
        var categories: [String] = []
        var grouped: [[String: [Double]]] = []
        var names: [String] = []
        for (j, series) in all.enumerated() {
            guard let d = data[series.first("cx:dataId")?["val"] ?? ""] else { return nil }
            var by: [String: [Double]] = [:]
            for (i, raw) in d.vals.enumerated() {
                guard let v = raw.flatMap({ Double($0.trimmingWhitespace()) }), v.isFinite else { continue }
                let name = (d.cats[safe: i] ?? nil) ?? ""
                if !categories.contains(name) { categories.append(name) }
                by[name, default: []].append(v)
            }
            grouped.append(by)
            names.append(series.first("cx:tx")?.descendant("cx:v")?.text ?? "Series\(j + 1)")
        }
        // (No points cached is a chart still where its data is a formula, a
        // sheet's to fill: chart-boxWhisker's three names, _xlchart.v1.*.)
        guard !categories.isEmpty || space.descendant("cx:f") != nil else { return nil }
        let boxes = grouped.map { by in categories.map { (by[$0] ?? []).sorted() } }
        // The series' values, for what reads them: each box's median.
        let series = zip(names, boxes).map { name, cats in
            ChartSeries(name: name, values: cats.map { $0.isEmpty ? nil : Self.quartile($0, 0.5, inclusive: false) })
        }
        var title: String? = nil
        if let t = chart.first("cx:title") {
            var runs: [String] = []
            func collect(_ n: XNode) {
                if n.name == "a:t" { runs.append(n.text) }
                n.children.forEach(collect)
            }
            collect(t)
            // (A title with no text of its own reads "Chart Title":
            // chart-pareto-gapwidth's in Excel's print,
            // lo-forum-mso-de-138303's waterfall's in PowerPoint's.)
            title = runs.isEmpty && t.descendant("cx:tx") == nil ? "Chart Title" : runs.joined()
        }
        var c = Chart(type: .column, title: title, categories: categories, series: series)
        c.boxes = boxes
        c.chartex = true
        c.legend = chart.first("cx:legend") != nil
        c.textSize = 9
        c.titleSize = 14
        if let gap = chart.first("cx:plotArea")?.all("cx:axis").compactMap({ $0.first("cx:catScaling")?["gapWidth"] }).first,
           let g = Double(gap), g >= 0 { c.boxGap = g }
        let layout = all[0].first("cx:layoutPr")
        c.boxInclusive = layout?.first("cx:statistics")?["quartileMethod"] == "inclusive"
        c.boxMeans = layout?.first("cx:visibility")?["meanMarker"] != "0"
        c.boxOutliers = layout?.first("cx:visibility")?["outliers"] != "0"
        return c
    }

    /// The `cx:` charts Word's documents draw as Word does: box-and-
    /// whisker and sunburst. nil for the rest, whose Fallback picture
    /// stands.
    static func readWordChartex(_ space: XNode) -> Chart? {
        readBoxWhisker(space) ?? readSunburst(space)
    }

    /// Excel 2016's sunburst (`layoutId="sunburst"`): each point's
    /// categories, the file's last level outermost, a path down the tree
    /// to its first empty name, points under one name summed into one
    /// wedge (chartex's three branches of stems and leaves). Its names
    /// are its labels where `cx:dataLabels` shows them.
    /// `allowEmpty`: a chart whose points are only in the sheet (no
    /// cache: chart-sunburst.xlsx's `_xlchart` names), its tree to be
    /// built from the cells (`sunburstTree`).
    /// `treemap`: an Excel 2016 treemap's tree too, read the same way
    /// (chart-treemap.xlsx's).
    static func readSunburst(_ space: XNode, allowEmpty: Bool = false, treemap: Bool = false) -> Chart? {
        guard let chart = space.first("cx:chart"),
              let ser = chart.first("cx:plotArea")?.first("cx:plotAreaRegion")?.all("cx:series").first,
              ser["layoutId"] == "sunburst" || (treemap && ser["layoutId"] == "treemap"),
              let d = (space.first("cx:chartData")?.all("cx:data") ?? []).first(where: { $0["id"] == ser.first("cx:dataId")?["val"] })
        else { return nil }
        func points(_ lvl: XNode?) -> [String?] {
            guard let lvl else { return [] }
            var out = [String?](repeating: nil, count: min(100_000, max(0, Int(lvl["ptCount"] ?? "") ?? 0)))
            for pt in lvl.all("cx:pt") {
                guard let i = Int(pt["idx"] ?? ""), i >= 0, i < 100_000 else { continue }
                if i >= out.count { out += [String?](repeating: nil, count: i - out.count + 1) }
                out[i] = pt.text
            }
            return out
        }
        let levels = (d.all("cx:strDim").first { $0["type"] == "cat" } ?? d.first("cx:strDim"))?.all("cx:lvl").map(points) ?? []
        let sizes = points((d.all("cx:numDim").first { $0["type"] == "size" } ?? d.first("cx:numDim"))?.first("cx:lvl"))
        var paths: [[String]] = [], values: [Double] = []
        for (i, raw) in sizes.enumerated() {
            guard let v = raw.flatMap({ Double($0.trimmingWhitespace()) }) else { continue }
            var path: [String] = []
            for lvl in levels.reversed() {
                guard let name = lvl[safe: i] ?? nil, !name.isEmpty else { break }
                path.append(name)
            }
            paths.append(path); values.append(v)
        }
        let roots = sunburstTree(paths: paths, values: values)
        guard !roots.isEmpty || allowEmpty else { return nil }
        var title: String? = nil
        if let t = chart.first("cx:title") {
            var runs: [String] = []
            func collect(_ n: XNode) {
                if n.name == "a:t" { runs.append(n.text) }
                n.children.forEach(collect)
            }
            collect(t)
            // (A title with no text of its own reads "Chart Title":
            // chart-pareto-gapwidth's in Excel's print,
            // lo-forum-mso-de-138303's waterfall's in PowerPoint's.)
            title = runs.isEmpty && t.descendant("cx:tx") == nil ? "Chart Title" : runs.joined()
        }
        var c = Chart(type: .pie, title: title, categories: roots.map(\.name),
                      series: [ChartSeries(name: ser.first("cx:tx")?.descendant("cx:v")?.text ?? "Series1", values: roots.map(\.value))])
        c.sunburst = roots
        c.treemap = ser["layoutId"] == "treemap"
        c.chartex = true
        c.legend = chart.first("cx:legend") != nil
        c.dataLabels = ser.first("cx:dataLabels").map { $0.first("cx:visibility")?["categoryName"] != "0" } ?? false
        c.textSize = 9
        c.titleSize = 14
        return c
    }

    /// A chart in a `cx:chartSpace` this app draws: box-and-whisker, or
    /// plain clustered columns. nil for the rest (histograms, waterfalls,
    /// funnels, maps…).
    static func readChartex(_ space: XNode) -> Chart? {
        readBoxWhisker(space) ?? readClusteredColumn(space) ?? readWaterfall(space) ?? readFunnel(space) ?? readHistogram(space)
            ?? readSunburst(space, allowEmpty: true, treemap: true)
    }

    /// A sunburst's tree: each point down its path of names, top level
    /// first, each node the sum of the points under it; the larger first,
    /// as Word lays the wedges out (chartex's 258, 165, 154 clockwise from
    /// twelve), a tie in the file's order.
    static func sunburstTree(paths: [[String]], values: [Double]) -> [Chart.SunburstNode] {
        func add(_ path: ArraySlice<String>, _ v: Double, to nodes: inout [Chart.SunburstNode]) {
            guard let name = path.first else { return }
            let i = nodes.firstIndex { $0.name == name } ?? nodes.count
            if i == nodes.count { nodes.append(Chart.SunburstNode(name: name, color: i)) }
            nodes[i].value += v
            add(path.dropFirst(), v, to: &nodes[i].children)
        }
        var roots: [Chart.SunburstNode] = []
        for (path, v) in zip(paths, values) where v.isFinite && v > 0 { add(path[...], v, to: &roots) }
        func sorted(_ nodes: [Chart.SunburstNode]) -> [Chart.SunburstNode] {
            nodes.enumerated().sorted { $0.element.value > $1.element.value || ($0.element.value == $1.element.value && $0.offset < $1.offset) }
                .map { var n = $0.element; n.children = sorted(n.children); return n }
        }
        return sorted(roots)
    }

    /// Excel 2016's histogram: clustered columns binned (`cx:binning`),
    /// its samples counted where they are cached, else when the sheet
    /// fills them (chart-SimpleHistogram's).
    static func readHistogram(_ space: XNode) -> Chart? {
        let all = space.first("cx:chart")?.first("cx:plotArea")?.first("cx:plotAreaRegion")?.all("cx:series") ?? []
        // (A pareto's line is a series of its own, of no data: its bars'.)
        let pareto = all.count == 2 && all[1]["layoutId"] == "paretoLine"
        let sers = pareto ? [all[0]] : all
        guard sers.count == 1, sers[0]["layoutId"] == "clusteredColumn",
              let binning = sers[0].first("cx:layoutPr")?.first("cx:binning"),
              var c = readClusteredColumn(space, binned: true, only: pareto ? 1 : nil) else { return nil }
        c.pareto = pareto
        var spec = Chart.HistogramBins()
        spec.size = binning.first("cx:binSize")?["val"].flatMap(Double.init)
        spec.underflow = binning["underflow"].flatMap(Double.init)
        spec.overflow = binning["overflow"].flatMap(Double.init)
        c.histogram = spec
        if let xs = c.series.first?.values.compactMap({ $0 }), !xs.isEmpty { c.applyHistogram(xs) }
        c.legend = pareto && space.first("cx:chart")?.first("cx:legend") != nil
        return c
    }

    /// Excel 2016's funnel (`layoutId="funnel"`): its points the clustered
    /// columns' way, drawn as a funnel (chart-color_funnel's).
    static func readFunnel(_ space: XNode) -> Chart? {
        guard var c = readClusteredColumn(space, layout: "funnel") else { return nil }
        c.funnel = true
        c.legend = false
        return c
    }

    /// A sheet's `cx:` chart: as `readChartex`, framed as Excel frames
    /// one, its own area fill and edge where it gives them (chart-
    /// waterfall2's gradient). Colours through `color`.
    static func readChartex(_ space: XNode, color: (XNode) -> Color?) -> Chart? {
        guard var c = readChartex(space) else { return nil }
        c.areaNoFill = false; c.areaNoLine = false
        // (Each series' own fill and edge: chart-color_funnel's orange
        // bars edged in green.)
        let sers = space.first("cx:chart")?.first("cx:plotArea")?.first("cx:plotAreaRegion")?.all("cx:series") ?? []
        for (j, ser) in sers.enumerated() where j < c.series.count && c.boxes == nil {
            guard let sp = ser.first("cx:spPr") else { continue }
            if let f = sp.first("a:solidFill") { c.series[j].color = color(f) }
            if let ln = sp.first("a:ln"), let f = ln.first("a:solidFill") {
                c.series[j].outline = color(f)
                c.series[j].outlineWidth = ln["w"].flatMap(Double.init).map { $0 / 12700 } ?? 0.75
            }
        }
        if let sp = space.first("cx:spPr") {
            if let f = sp.first("a:solidFill") { c.areaFill = color(f) } else if sp.first("a:noFill") != nil { c.areaNoFill = true }
            else if let g = sp.first("a:gradFill") {
                let stops = (g.first("a:gsLst")?.all("a:gs") ?? []).compactMap { gs -> SlideFill.GradientStop? in
                    color(gs).map { SlideFill.GradientStop(position: (gs["pos"].flatMap(Double.init) ?? 0) / 100000, color: $0) }
                }.sorted { $0.position < $1.position }
                c.areaFill = stops.first?.color
                if stops.count > 1 {
                    var f = SlideFill(color: stops[0].color, stops: stops,
                                      angle: (g.first("a:lin")?["ang"].flatMap(Double.init) ?? 5_400_000) / 60000)
                    f.scaled = ["1", "true"].contains(g.first("a:lin")?["scaled"] ?? "")
                    c.areaGradient = f
                }
            }
            if let ln = sp.first("a:ln") {
                if let f = ln.first("a:solidFill") { c.areaLine = color(f) } else if ln.first("a:noFill") != nil { c.areaNoLine = true }
            }
        }
        return c
    }

    /// Excel 2016's waterfall (`layoutId="waterfall"`): its one series of
    /// steps, the points `cx:subtotals` names standing as totals, as a
    /// column chart's axes and text draw it (chart-waterfall's).
    static func readWaterfall(_ space: XNode) -> Chart? {
        guard let chart = space.first("cx:chart"),
              let ser = chart.first("cx:plotArea")?.first("cx:plotAreaRegion")?.all("cx:series").first,
              ser["layoutId"] == "waterfall" else { return nil }
        // (Its points the clustered columns' way: cached, or a formula the
        // sheet fills.)
        guard var c = readClusteredColumn(space, layout: "waterfall") else { return nil }
        let layout = ser.first("cx:layoutPr")
        c.waterfallTotals = Set((layout?.first("cx:subtotals")?.all("cx:idx") ?? []).compactMap { $0["val"].flatMap(Int.init) })
        c.waterfallConnectors = layout?.first("cx:visibility")?["connectorLines"] == "1"
        c.legend = chart.first("cx:legend") != nil
        return c
    }

    /// Excel 2016's clustered columns (`layoutId="clusteredColumn"`) with
    /// no binning — a histogram's layout is the same name, binned: each
    /// series' values over its categories, as a `c:` column chart draws
    /// them, in a 2013-style chart's text (chart-clusteredColumn's).
    static func readClusteredColumn(_ space: XNode, layout: String = "clusteredColumn", binned: Bool = false, only: Int? = nil) -> Chart? {
        guard let chart = space.first("cx:chart"),
              let region = chart.first("cx:plotArea")?.first("cx:plotAreaRegion") else { return nil }
        let all = Array(region.all("cx:series").prefix(only ?? Int.max))
        guard !all.isEmpty, all.allSatisfy({ $0["layoutId"] == layout && ($0.first("cx:layoutPr")?.first("cx:binning") == nil) != binned
            && $0.first("cx:layoutPr")?.first("cx:aggregation") == nil }) else { return nil }
        func points(_ dim: XNode?) -> [String?] {
            guard let lvl = dim?.first("cx:lvl") else { return [] }
            var out = [String?](repeating: nil, count: min(100_000, max(0, Int(lvl["ptCount"] ?? "") ?? 0)))
            for pt in lvl.all("cx:pt") {
                guard let i = Int(pt["idx"] ?? ""), i >= 0, i < 100_000 else { continue }
                if i >= out.count { out += [String?](repeating: nil, count: i - out.count + 1) }
                out[i] = pt.text
            }
            return out
        }
        var data: [String: (cats: [String?], vals: [String?])] = [:]
        for d in space.first("cx:chartData")?.all("cx:data") ?? [] {
            let cat = d.all("cx:strDim").first { $0["type"] == "cat" } ?? d.all("cx:numDim").first { $0["type"] == "cat" }
            let val = d.all("cx:numDim").first { $0["type"] == "val" }
            data[d["id"] ?? ""] = (points(cat), points(val))
        }
        var categories: [String] = []
        var series: [ChartSeries] = []
        for (j, ser) in all.enumerated() {
            guard let d = data[ser.first("cx:dataId")?["val"] ?? ""] else { return nil }
            let values = d.vals.map { $0.flatMap { Double($0.trimmingWhitespace()) } }
            if categories.isEmpty { categories = (0 ..< values.count).map { (d.cats[safe: $0] ?? nil) ?? String($0 + 1) } }
            series.append(ChartSeries(name: ser.first("cx:tx")?.descendant("cx:v")?.text ?? "Series\(j + 1)", values: values))
        }
        // (No points cached is a chart still, its cells read live:
        // chart-clusteredColumn's data is a name, _xlchart.v1.0, and no
        // more.)
        guard !categories.isEmpty || space.descendant("cx:f") != nil else { return nil }
        var title: String? = nil
        if let t = chart.first("cx:title") {
            var runs: [String] = []
            func collect(_ n: XNode) {
                if n.name == "a:t" { runs.append(n.text) }
                n.children.forEach(collect)
            }
            collect(t)
            // (A title with no text of its own reads "Chart Title":
            // chart-pareto-gapwidth's in Excel's print,
            // lo-forum-mso-de-138303's waterfall's in PowerPoint's.)
            title = runs.isEmpty && t.descendant("cx:tx") == nil ? "Chart Title" : runs.joined()
        }
        var c = Chart(type: .column, title: title, categories: categories, series: series)
        c.chartex = true
        c.legend = chart.first("cx:legend") != nil
        c.textSize = 9
        c.titleSize = 14
        c.dataLabels = all.contains { $0.first("cx:dataLabels")?.first("cx:visibility")?["value"] == "1" }
        // (Its legend where it says, chart-clusteredColumn's at the top;
        // its category labels at the plot's foot, below its columns under
        // zero, as Excel prints a `cx:` chart's.)
        if let pos = chart.first("cx:legend")?["pos"] { c.legendPosition = pos }
        c.categoryLabelsLow = true
        // (Excel's own frame: white, a light grey edge.)
        c.areaNoFill = false; c.areaNoLine = false
        if let gap = chart.first("cx:plotArea")?.all("cx:axis").compactMap({ $0.first("cx:catScaling")?["gapWidth"] }).first,
           let g = Double(gap), g >= 0 { c.gapWidth = Int(g * 100) }
        return c
    }

    /// The `p` quartile of sorted `xs`: Excel's QUARTILE.EXC, a point
    /// p (n + 1) along, or with `inclusive` QUARTILE.INC's p (n - 1) + 1.
    static func quartile(_ xs: [Double], _ p: Double, inclusive: Bool) -> Double {
        guard let lo = xs.first, let hi = xs.last else { return 0 }
        let n = Double(xs.count)
        let at = inclusive ? p * (n - 1) + 1 : p * (n + 1)
        if at <= 1 { return lo }
        if at >= n { return hi }
        let k = Int(at.rounded(.down))
        return xs[k - 1] + (at - Double(k)) * (xs[k] - xs[k - 1])
    }

    /// The chart in a `c:chartSpace`, or nil for one this app cannot draw
    /// (radar, stock, surface, combinations) — kept as an object then. A 3-D
    /// chart is drawn as its flat kind, a pie-of-pie as its pie, a bubble
    /// chart as its points: the data where it belongs, without the depth.
    /// `allowEmpty`: a chart with no series is still a chart (Excel draws
    /// its empty frame, and gives it its room on the page).
    /// A chart part with the usual prefixes (`c:`, `a:`, `r:`, `cx:`…)
    /// on names it spells in other ones, or in none: openpyxl writes its
    /// charts in the default namespace (`<chartSpace xmlns=…>`), and
    /// chart-tdf119138's four were not drawn at all.
    static func canonical(_ space: XNode) -> XNode {
        guard !["c:chartSpace", "cx:chartSpace"].contains(space.name) else { return space }
        return space.withPrefixes([
            "http://schemas.openxmlformats.org/drawingml/2006/chart": "c",
            "http://schemas.openxmlformats.org/drawingml/2006/main": "a",
            "http://schemas.openxmlformats.org/officeDocument/2006/relationships": "r",
            "http://schemas.microsoft.com/office/drawing/2014/chartex": "cx",
            "http://schemas.microsoft.com/office/drawing/2007/8/2/chart": "c14",
            "http://schemas.microsoft.com/office/drawing/2012/chart": "c15",
            "http://schemas.openxmlformats.org/markup-compatibility/2006": "mc",
        ])
    }

    static func read(_ space: XNode, allowEmpty: Bool = false, color: (XNode) -> Color?) -> Chart? {
        guard let chart = space.first("c:chart"), let plot = chart.first("c:plotArea") else { return nil }
        let kinds = plot.children.filter { $0.name.hasPrefix("c:") && $0.name.hasSuffix("Chart") }
        // A combination this app draws: columns (or bars) with lines over
        // them, both on one pair of axes.
        var overlay: XNode? = nil
        var secondAxis: XNode? = nil
        var main = kinds.first
        var merged: [XNode] = []
        var columnsOnRight = false
        if kinds.count == 2, let bar = kinds.first(where: { $0.name == "c:barChart" }),
           let line = kinds.first(where: { $0.name == "c:lineChart" }) {
            let barAxes = Set(bar.all("c:axId").compactMap { $0["val"] })
            let lineAxes = Set(line.all("c:axId").compactMap { $0["val"] })
            // (… or the lines on a value axis of their own, at the right:
            // zh-2a241df1's complaint counts in columns, their shares as
            // a line on 0% to 60%.)
            if barAxes != lineAxes {
                guard bar.first("c:barDir")?["val"] != "bar",
                      let own = plot.all("c:valAx").first(where: { lineAxes.contains($0.first("c:axId")?["val"] ?? "") && !barAxes.contains($0.first("c:axId")?["val"] ?? "") })
                else { return nil }
                secondAxis = own
            }
            main = bar
            overlay = line
            columnsOnRight = plot.all("c:valAx").contains { ax in
                barAxes.contains(ax.first("c:axId")?["val"] ?? "") && (ax.first("c:axPos")?["val"] == "r" || ax.first("c:crosses")?["val"] == "max")
            } && barAxes != lineAxes
        } else if kinds.count > 1, kinds.allSatisfy({ $0.name == "c:barChart" }),
                  Set(kinds.map { Set($0.all("c:axId").compactMap { $0["val"] }) }).count == 1,
                  Set(kinds.map { $0.first("c:barDir")?["val"] ?? "bar" }).count == 1,
                  Set(kinds.map { $0.first("c:grouping")?["val"] ?? "clustered" }).count == 1 {
            // Column groups on one pair of axes, alike: one group of all
            // their series (chart-tdf100084's two, a series each).
            merged = Array(kinds.dropFirst())
        } else if kinds.count == 2, kinds.allSatisfy({ $0.name == "c:lineChart" }) {
            // Lines over lines, the second group on a value axis of its own
            // at the right (chart-add_series_secondary_axis): drawn as a
            // combination's lines are.
            let firstAxes = Set(kinds[0].all("c:axId").compactMap { $0["val"] })
            let secondAxes = Set(kinds[1].all("c:axId").compactMap { $0["val"] })
            guard firstAxes != secondAxes,
                  let own = plot.all("c:valAx").first(where: { secondAxes.contains($0.first("c:axId")?["val"] ?? "") && !firstAxes.contains($0.first("c:axId")?["val"] ?? "") })
            else { return nil }
            secondAxis = own
            overlay = kinds[1]
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
        case "c:surface3DChart", "c:surfaceChart": type = .area
        default: return nil
        }
        let grouping = el.first("c:grouping")?["val"] ?? "standard"
        var categories: [String] = []
        var series: [ChartSeries] = []
        var pointColors: [Int: Color] = [:]
        var named = false
        for ser in el.all("c:ser") + merged.flatMap({ $0.all("c:ser") }) {
            // (A series with no name is "Series1", no space, as Office names it:
            // chart-testDataseriesOverlapStackedChart's legend.)
            let name = ser.first("c:tx").map { _texts($0, "c:v").joined() } ?? "Series\(series.count + 1)"
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
            s.format = Self._format(val)
            if let k = ser.first("c:idx")?["val"].flatMap(Int.init), k != series.count { s.autoIndex = k }
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
            // (A line hidden, and its marks: chartex's stock chart sets its
            // three series' lines to none, Close marked by 3pt dots.)
            // (A line shown, its marks too: chart-add_series_secondary_axis'
            // circles on each point.)
            if type == .line {
                s.lineHidden = pr?.first("a:ln")?.has("a:noFill") == true
                // (A shown line's "none" is no marker at all, as it was
                // before its marks were read: what this app writes for one,
                // and what a round trip must give back.)
                if let m = ser.first("c:marker"), s.lineHidden || m.first("c:symbol")?["val"] != "none" {
                    s.marker = m.first("c:symbol")?["val"]
                    s.markerSize = m.first("c:size")?["val"].flatMap(Double.init) ?? 5
                    if let f = m.first("c:spPr")?.first("a:solidFill") { s.markerFill = color(f) }
                    if let f = m.first("c:spPr")?.first("a:ln")?.first("a:solidFill") { s.markerLine = color(f) }
                }
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
                    // A gradient as the colour it comes to over the slice
                    // (LIBRE_OFFICE-128382-0's pale 3-D pie, drawn in the
                    // accents themselves).
                    else if let i = pt.first("c:idx")?["val"].flatMap(Int.init),
                            let g = pt.first("c:spPr")?.first("a:gradFill"), let c = _meanColor(g, color) { pointColors[i] = c }
                }
            }
            if let fill {
                let index = s.autoIndex ?? series.count
                if let scheme = fill.first("a:schemeClr"), _isCycle(scheme, index) {
                    // The theme's own colour for this series: follows the theme.
                } else if let scheme = fill.first("a:schemeClr"), scheme.children.isEmpty {
                    s.scheme = scheme["val"]
                } else {
                    s.color = color(fill)
                }
            } else if type != .line, type != .scatter, let g = pr?.first("a:gradFill") {
                s.color = _meanColor(g, color)
            }
            // (Its labels moved one by one, as a combination's line's are:
            // zh-b8de3ae2's 3-D bars' close values, apart in Word's print,
            // stood over each other.)
            for one in ser.first("c:dLbls")?.all("c:dLbl") ?? [] {
                guard let i = one.first("c:idx")?["val"].flatMap(Int.init), let m = one.first("c:layout")?.first("c:manualLayout"),
                      let x = m.first("c:x")?["val"].flatMap(Double.init), let y = m.first("c:y")?["val"].flatMap(Double.init) else { continue }
                s.labelNudges[i] = Offset(x, y)
            }
            series.append(s)
        }
        guard !series.isEmpty || allowEmpty else { return nil }
        // The lines over the columns, with their marks.
        var lines: [ChartSeries] = []
        for ser in overlay?.all("c:ser") ?? [] {
            let name = ser.first("c:tx").map { _texts($0, "c:v").joined() } ?? "Series\(series.count + lines.count + 1)"
            let values = (ser.first("c:val").map(_points) ?? []).map { $0.flatMap { Double($0.trimmingWhitespace()) } }
            var s = ChartSeries(name: name, values: values)
            s.format = Self._format(ser.first("c:val"))
            if let k = ser.first("c:idx")?["val"].flatMap(Int.init), k != series.count + lines.count { s.autoIndex = k }
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
            // Its values, where its labels (else its chart's) show them.
            let own = ser.first("c:dLbls"), group = overlay?.first("c:dLbls")
            s.valueLabels = (own?.first("c:showVal") ?? group?.first("c:showVal"))?["val"] == "1"
                && own?.first("c:delete")?["val"] != "1"
            s.labelPos = (own?.first("c:dLblPos") ?? group?.first("c:dLblPos"))?["val"]
            if s.valueLabels, let d = own {
                if let f = d.first("c:numFmt"), !["1", "true"].contains(f["sourceLinked"] ?? ""), let code = f["formatCode"],
                   !code.isEmpty, code.lowercased() != "general" { s.labelCode = code }
                for one in d.all("c:dLbl") {
                    guard let i = one.first("c:idx")?["val"].flatMap(Int.init), let m = one.first("c:layout")?.first("c:manualLayout"),
                          let x = m.first("c:x")?["val"].flatMap(Double.init), let y = m.first("c:y")?["val"].flatMap(Double.init) else { continue }
                    s.labelNudges[i] = Offset(x, y)
                }
                if let run = d.first("c:txPr")?.descendant("a:defRPr") {
                    s.labelSize = run["sz"].flatMap(Double.init).map { $0 / 100 }
                    s.labelBold = ["1", "true"].contains(run["b"] ?? "")
                    if let f = run.first("a:solidFill") { s.labelColor = color(f) }
                }
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
        var titleLineSizes: [Int: Double] = [:]
        var titleAt: Offset? = nil
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
            if let m = t.first("c:layout")?.first("c:manualLayout"),
               (m.first("c:xMode")?["val"] ?? "factor") == "edge", (m.first("c:yMode")?["val"] ?? "factor") == "edge",
               let x = m.first("c:x")?["val"].flatMap(Double.init), let y = m.first("c:y")?["val"].flatMap(Double.init) {
                titleAt = Offset(x, y)
            }
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
            // Text that says nothing of its look, nor does the chart: the
            // run's own defaults, 18 pt and not bold (openpyxl's titles,
            // chart-tdf119138's, in Excel's print).
            if Self._bare(t, in: space) { titleSize = 18; titleBold = false }
            for layer in layers where titleColor == nil {
                if let fill = layer.first("a:solidFill") { titleColor = color(fill) }
            }
            titleFace = layers.lazy.compactMap { $0.first("a:latin")?["typeface"] }.first
            // A later paragraph in a size of its own: every line it makes.
            if let first = titleSize, !paragraphs.isEmpty {
                var line = 0
                for p in paragraphs {
                    let lines = 1 + p.children.filter { $0.name == "a:br" }.count
                    if let sz = p.first("a:r")?.first("a:rPr")?["sz"].flatMap(Double.init).map({ $0 / 100 }), sz != first {
                        for k in line ..< line + lines { titleLineSizes[k] = sz }
                    }
                    line += lines
                }
            }
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
        if let axis = secondAxis {
            var second = SecondValueAxis()
            second.deleted = ["1", "true"].contains(axis.first("c:delete")?["val"] ?? "")
            if let fmt = axis.first("c:numFmt") {
                let linked = ["1", "true"].contains(fmt["sourceLinked"] ?? "")
                let source = overlay?.descendant("c:val")?.descendant("c:formatCode")?.text
                let code = (linked ? source : nil) ?? fmt["formatCode"] ?? ""
                if !code.isEmpty, code.lowercased() != "general" { second.format = code }
            }
            if let scaling = axis.first("c:scaling") {
                second.min = scaling.first("c:min")?["val"].flatMap(Double.init)
                second.max = scaling.first("c:max")?["val"].flatMap(Double.init)
            }
            second.step = axis.first("c:majorUnit")?["val"].flatMap(Double.init).flatMap { $0 > 0 ? $0 : nil }
            c.secondValueAxis = second
        }
        if let h = el.first("c:hiLowLines") {
            let ln = h.first("c:spPr")?.first("a:ln")
            if ln?.has("a:noFill") != true {
                c.highLowLines = HighLowLines(color: ln?.first("a:solidFill").flatMap(color),
                                              width: ln?["w"].flatMap(Double.init).map { $0 / 12700 } ?? 0.75)
            }
        }
        if let d = plot.first("c:dTable") {
            func on(_ name: String) -> Bool { !["0", "false"].contains(d.first(name)?["val"] ?? "1") }
            var t = DataTable()
            t.horizontalRules = on("c:showHorzBorder"); t.verticalRules = on("c:showVertBorder")
            t.outline = on("c:showOutline"); t.keys = on("c:showKeys")
            t.size = d.first("c:txPr")?.descendant("a:defRPr")?["sz"].flatMap(Double.init).map { $0 / 100 }
            if let sp = d.first("c:spPr") {
                t.squareKeys = true
                if let ln = sp.first("a:ln") {
                    if let f = ln.first("a:solidFill") { t.lineColor = color(f) }
                    t.lineWidth = ln["w"].flatMap(Double.init).map { $0 / 12700 }
                }
            }
            c.dataTable = t
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
        c.titleLineSizes = titleLineSizes
        c.titleAt = titleAt
        c.titleBold = titleBold
        c.titleColor = titleColor
        if let sp = chart.first("c:title")?.first("c:spPr") {
            c.titleFill = sp.first("a:solidFill").flatMap(color)
            if let ln = sp.first("a:ln"), let f = ln.first("a:solidFill") {
                c.titleLine = color(f)
                c.titleLineWidth = ln["w"].flatMap(Double.init).map { $0 / 12700 } ?? 0.75
                c.titleLineDash = PptxReader.dash(ln)
                c.titleLineRound = ln["cap"] == "rnd"
            }
        }
        // (A theme slot, "+mn-lt", is the theme's face: none of its own.)
        func face(_ f: String?) -> String? { f.flatMap { $0.hasPrefix("+") || $0.isEmpty ? nil : $0 } }
        c.font = face(spaceRun?.first("a:latin")?["typeface"])
        func eastAsian(_ n: XNode) -> Bool {
            if n.name == "a:defRPr" || n.name == "a:rPr", let l = n["lang"]?.lowercased(),
               l.hasPrefix("zh") || l.hasPrefix("ja") || l.hasPrefix("ko") { return true }
            return n.children.contains { eastAsian($0) }
        }
        c.eastAsianText = eastAsian(space)
        c.titleFont = face(titleFace) ?? c.font
        c.legend = chart.first("c:legend") != nil
        // (Absent, the schema's default is the right.)
        // (A deleted entry is not drawn: the Word showcase's F04 and
        // chart-deleted_legend_entry2, whose "First" Word and Excel leave out.)
        for e in chart.first("c:legend")?.all("c:legendEntry") ?? [] where e.first("c:delete")?["val"] == "1" {
            if let i = e.first("c:idx")?["val"].flatMap(Int.init) { c.hiddenLegendEntries.insert(i) }
        }
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
        // A series' own labels stand in for the chart's: deleted there, it
        // has none, whatever the chart says (chart-DataTable-Multiple…'s
        // one series deletes them under a chart that shows values).
        c.dataLabels = el.all("c:ser").contains { ser in
            guard let d = ser.first("c:dLbls") else { return shows(el.first("c:dLbls")) }
            if ["1", "true"].contains(d.first("c:delete")?["val"] ?? "") { return false }
            return d.first("c:showVal") == nil && d.first("c:showPercent") == nil ? shows(el.first("c:dLbls")) : shows(d)
        }
        if type == .doughnut, let hole = el.first("c:holeSize")?["val"].flatMap(Int.init) { c.holeSize = hole }
        if type == .pie || type == .doughnut, let ser = el.first("c:ser"), let d = ser.first("c:dLbls") ?? el.first("c:dLbls") {
            func on(_ n: XNode?, _ name: String) -> Bool { ["1", "true"].contains(n?.first(name)?["val"] ?? "") }
            c.pieLabelsAround = type == .pie && d.first("c:delete")?["val"] != "1"
                && ["c:showVal", "c:showPercent", "c:showCatName", "c:showSerName"].contains { on(d, $0) }
                && !["ctr", "inEnd", "inBase"].contains(d.first("c:dLblPos")?["val"] ?? "bestFit")
            var l = Chart.PieLabels()
            l.series = on(d, "c:showSerName"); l.category = on(d, "c:showCatName")
            l.value = on(d, "c:showVal"); l.percent = on(d, "c:showPercent")
            l.separator = d.first("c:separator")?.text
            // (None written is a best fit, Excel's default for a pie:
            // zh-d62da4dd's 3-D pies give no position, and Word's print of
            // them with their moves taken out, lab p3d, sets the big slices'
            // labels inside and the small ones' beside them on leaders.)
            let pos = d.first("c:dLblPos")?["val"] ?? (type == .pie ? "bestFit" : nil)
            l.outside = pos == "outEnd" || pos == "bestFit"
            var ends = pos == "outEnd"
            for one in d.all("c:dLbl") {
                guard let i = one.first("c:idx")?["val"].flatMap(Int.init) else { continue }
                if let p = one.first("c:dLblPos")?["val"], ["outEnd", "bestFit"].contains(p) {
                    l.outside = true
                    if p == "outEnd" { ends = true }
                }
                if let sz = one.first("c:tx")?.descendant("a:rPr")?["sz"].flatMap(Double.init) { l.sizes[i] = sz / 100 }
                if let rich = one.first("c:tx")?.first("c:rich") {
                    // (A field — the category's name, the value — kept as a
                    // mark the label fills in: zh-b8de3ae2's bar of pie says
                    // "[類別名稱], 0.93%" and "規費收入, [值]", Word's print
                    // "審查費, 0.93%" and "規費收入, 46.05%".)
                    let text = rich.all("a:p").map { para in
                        para.children.map { run -> String in
                            if run.name == "a:fld", let mark = Self._fieldMarks[run["type"] ?? ""] { return mark }
                            return _texts(run, "a:t").joined()
                        }.joined()
                    }.joined(separator: "\n")
                    if !text.isEmpty { l.texts[i] = text }
                    if Self._traditional(rich) { l.traditional.insert(i) }
                }
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
            l.fitted = l.outside && !ends
            l.leaders = on(d, "c:showLeaderLines")
            if let ln = (d.first("c:leaderLines") ?? d.descendant("c15:leaderLines"))?.first("c:spPr")?.first("a:ln") {
                if let f = ln.first("a:solidFill") { l.leaderColor = color(f) }
                l.leaderWidth = ln["w"].flatMap(Double.init).map { $0 / 12700 } ?? 0.75
            }
            // Only what the plain labels do not already draw.
            if l.series || l.category || l.percent || l.outside || !l.moves.isEmpty || l.fill != nil || !l.texts.isEmpty { c.pieLabels = l }
        }
        if type == .radar { c.radarFilled = el.first("c:radarStyle")?["val"] == "filled" }
        if el.name == "c:surface3DChart" || el.name == "c:surfaceChart" {
            c.surface = true
            let v = chart.first("c:view3D")
            // (A flat surface chart is seen from straight above.)
            c.surfaceView = el.name == "c:surfaceChart" ? Offset(90, 0)
                : Offset(v?.first("c:rotX")?["val"].flatMap(Double.init) ?? 15, v?.first("c:rotY")?["val"].flatMap(Double.init) ?? 20)
        }
        if el.name == "c:bar3DChart" {
            let v = chart.first("c:view3D")
            c.barView = Chart.BarView(x: v?.first("c:rotX")?["val"].flatMap(Double.init) ?? 15,
                                      y: v?.first("c:rotY")?["val"].flatMap(Double.init) ?? 20,
                                      depth: (v?.first("c:depthPercent")?["val"].flatMap(Double.init) ?? 100) / 100,
                                      gapDepth: (el.first("c:gapDepth")?["val"].flatMap(Double.init) ?? 150) / 100)
            func unlined(_ tag: String) -> Bool { chart.first(tag)?.first("c:spPr")?.first("a:ln")?.first("a:noFill") != nil }
            c.barView?.walled = !(unlined("c:floor") && unlined("c:backWall"))
        }
        if el.name == "c:pie3DChart" {
            // (No rotX is 15°: Excel draws 45544's pies the same with none
            // and with 15, and fits them otherwise at 30 and 60.)
            c.pieTilt = chart.first("c:view3D")?.first("c:rotX")?["val"].flatMap(Double.init) ?? 15
            c.pieTurn = chart.first("c:view3D")?.first("c:rotY")?["val"].flatMap(Double.init) ?? 0
            let pulls = el.all("c:ser").flatMap { ser in
                ([ser.first("c:explosion")] + ser.all("c:dPt").map { $0.first("c:explosion") }).compactMap { $0?["val"].flatMap(Double.init) }
            }
            c.pieExplosion = max(0, pulls.max() ?? 0) / 100
        }
        func axisTitle(_ ax: XNode?) -> String? {
            guard let t = ax?.first("c:title") else { return nil }
            let s = _texts(t, "a:t").joined()
            // (A title of its own text that is empty prints nothing, but
            // keeps its room beside the plot: 64450's two axes, where ours
            // said "Axis Title" — and with no title at all its plot stood
            // further out than Excel's. No text at all is the default's.)
            if s.isEmpty, t.first("c:tx")?.first("c:rich") != nil { return " " }
            return s.isEmpty ? "Axis Title" : s
        }
        // (Placed: edge-mode x and y, read across where its text is not
        // turned — `a:bodyPr rot="0"`.)
        func placed(_ ax: XNode?) -> PlacedAxisTitle? {
            guard let t = ax?.first("c:title"), let m = t.first("c:layout")?.first("c:manualLayout"),
                  (m.first("c:xMode")?["val"] ?? "factor") == "edge", (m.first("c:yMode")?["val"] ?? "factor") == "edge",
                  let x = m.first("c:x")?["val"].flatMap(Double.init), let y = m.first("c:y")?["val"].flatMap(Double.init),
                  t.descendant("a:bodyPr")?["rot"] == "0" else { return nil }
            let size = (t.descendant("a:rPr") ?? t.descendant("a:defRPr"))?["sz"].flatMap(Double.init).map { $0 / 100 }
            return PlacedAxisTitle(at: Offset(x, y), size: size)
        }
        let axes = plot.children.filter { ["c:catAx", "c:valAx", "c:dateAx"].contains($0.name) }
        let titledCategory = type == .scatter ? axes.first { ["b", "t"].contains($0.first("c:axPos")?["val"] ?? "") } : axes.first { $0.name != "c:valAx" }
        let titledValue = type == .scatter ? axes.first { ["l", "r"].contains($0.first("c:axPos")?["val"] ?? "") } : axes.first { $0.name == "c:valAx" }
        c.categoryAxisTitle = axisTitle(titledCategory)
        c.valueAxisTitle = axisTitle(titledValue)
        if let t = titledValue?.first("c:title") ?? titledCategory?.first("c:title"), Self._bare(t, in: space) { c.axisTitleSize = 18 }
        c.categoryAxisTitleAt = c.categoryAxisTitle == nil ? nil : placed(titledCategory)
        c.valueAxisTitleAt = c.valueAxisTitle == nil ? nil : placed(titledValue)
        c.valueAxisTitleAcross = c.valueAxisTitle != nil && c.valueAxisTitleAt == nil && titledValue?.first("c:title")?.descendant("a:bodyPr")?["rot"] == "0"
        let valueAxis = type == .scatter ? axes.first { ["l", "r"].contains($0.first("c:axPos")?["val"] ?? "") }
            : axes.first { $0.name == "c:valAx" }
        if let sz = valueAxis?.first("c:txPr")?.descendant("a:defRPr")?["sz"].flatMap(Double.init), sz > 0, sz != 1200, sz != 1197 {
            c.valueLabelSize = sz / 100
        }
        let categoryAxis = type == .scatter ? axes.first { ["b", "t"].contains($0.first("c:axPos")?["val"] ?? "") }
            : axes.first { $0.name != "c:valAx" }
        c.categoryTicksOut = ["out", "cross"].contains(categoryAxis?.first("c:majorTickMark")?["val"] ?? "")
        if type == .scatter, let categoryAxis { c.scatterXGrid = categoryAxis.first("c:majorGridlines") != nil }
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
        if el.name == "c:ofPieChart", let values = c.series.first?.values {
            c.ofPie = Self._ofPie(el, values: values)
        }
        c.variedPoints = (type == .bar || type == .column) && c.series.count == 1 && c.lineSeries.isEmpty
            && ["1", "true"].contains(el.first("c:varyColors")?["val"] ?? "")
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
            // (chart-tdf100084's white to 9999CC, across one chart and back
            // across the other, as `a:lin`'s angle turns it.)
            else if let g = sp.first("a:gradFill") {
                let stops = (g.first("a:gsLst")?.all("a:gs") ?? []).compactMap { gs -> SlideFill.GradientStop? in
                    color(gs).map { SlideFill.GradientStop(position: (gs["pos"].flatMap(Double.init) ?? 0) / 100000, color: $0) }
                }.sorted { $0.position < $1.position }
                c.areaFill = stops.first?.color
                if stops.count > 1 {
                    var f = SlideFill(color: stops[0].color, stops: stops,
                                      angle: (g.first("a:lin")?["ang"].flatMap(Double.init) ?? 5_400_000) / 60000)
                    f.scaled = ["1", "true"].contains(g.first("a:lin")?["scaled"] ?? "")
                    c.areaGradient = f
                }
            }
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
            c.valueLine = valueAxis.first("c:spPr")?.first("a:ln")?.first("a:noFill") == nil
        }
        c.categoryAxisDeleted = ["1", "true"].contains(categoryAxis?.first("c:delete")?["val"] ?? "")
        c.categoryLine = categoryAxis?.first("c:spPr")?.first("a:ln")?.first("a:noFill") == nil
        c.categoryLabelsLow = categoryAxis?.first("c:tickLblPos")?["val"] == "low"
        c.columnsOnRight = columnsOnRight
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
    /// A title's text without a word on its look — no run, paragraph or
    /// title properties, and none for the chart.
    static func _bare(_ t: XNode, in space: XNode) -> Bool {
        t.first("c:tx")?.first("c:rich") != nil && t.descendant("a:rPr") == nil && t.descendant("a:defRPr") == nil
            && t.first("c:txPr") == nil && space.first("c:txPr") == nil
    }

    /// Which points of a pie of pie go to its second plot (`c:splitType`):
    /// the last so many (`pos`), those under a value or a percent, or the
    /// ones the file lists (`cust`). With none said, the last third:
    /// Excel's prints of chart-pieOfPieChart (two of six) and
    /// chart-barOfPieChart (three of nine).
    static func _ofPie(_ el: XNode, values: [Double?]) -> Chart.OfPie {
        var o = Chart.OfPie()
        o.bar = el.first("c:ofPieType")?["val"] == "bar"
        if let size = el.first("c:secondPieSize")?["val"].flatMap(Double.init) { o.size = max(0.05, min(2, size / 100)) }
        let n = values.count
        let at = el.first("c:splitPos")?["val"].flatMap(Double.init)
        let sum = values.reduce(0) { $0 + max(0, $1 ?? 0) }
        switch el.first("c:splitType")?["val"] ?? "auto" {
        case "val":
            o.second = Set(values.indices.filter { (values[$0] ?? 0) < (at ?? 0) })
        case "percent":
            o.second = Set(values.indices.filter { sum > 0 && (values[$0] ?? 0) / sum * 100 < (at ?? 0) })
        case "cust":
            o.second = Set((el.first("c:custSplit")?.all("c:secondPiePt") ?? []).compactMap { $0["val"].flatMap(Int.init) })
        case "pos" where at != nil:
            o.second = Set(max(0, n - Int(max(0, min(Double(n), at!)))) ..< n)
        default:
            o.second = Set(max(0, n - Int((Double(n) / 3).rounded())) ..< n)
        }
        // (Never all of them: the main pie keeps one.)
        if o.second.count >= n { o.second.remove(0) }
        return o
    }

    /// A gradient's mean colour: its stops joined by straight runs, the
    /// first and last held to the ends.
    static func _meanColor(_ g: XNode, _ color: (XNode) -> Color?) -> Color? {
        let stops = (g.first("a:gsLst")?.all("a:gs") ?? []).compactMap { gs -> (Double, Color)? in
            color(gs).map { (min(1, max(0, (gs["pos"].flatMap(Double.init) ?? 0) / 100000)), $0) }
        }.sorted { $0.0 < $1.0 }
        guard let first = stops.first, let last = stops.last else { return nil }
        var sum = [0.0, 0.0, 0.0, 0.0]
        func add(_ c: Color, _ w: Double) {
            let v = Int(c.value)
            for (k, s) in [24, 16, 8, 0].enumerated() { sum[k] += Double((v >> s) & 0xFF) * w }
        }
        add(first.1, first.0)
        add(last.1, 1 - last.0)
        for (a, b) in zip(stops, stops.dropFirst()) {
            let w = (b.0 - a.0) / 2
            add(a.1, w); add(b.1, w)
        }
        let total = first.0 + (1 - last.0) + (last.0 - first.0)
        guard total > 0 else { return first.1 }
        let ch = sum.map { Int64(max(0, min(255, ($0 / total).rounded()))) }
        return Color(ch[0] << 24 | ch[1] << 16 | ch[2] << 8 | ch[3])
    }

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
    /// A series' numbers' format where it is not General (`c:formatCode`).
    private static func _format(_ val: XNode?) -> String? {
        guard let code = val?.descendant("c:formatCode")?.text.trimmingWhitespace(), !code.isEmpty, code.lowercased() != "general" else { return nil }
        return code
    }

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

    /// A data label's fields (`a:fld type`), as the marks `_pieLabels`
    /// fills in.
    /// Whether `n`'s runs say Traditional Chinese (`lang="zh-TW"`, zh-HK,
    /// zh-MO): a run's own, not the paragraph's end mark — zh-b8de3ae2's
    /// axes, `endParaRPr lang="zh-TW"`, are in Word for Mac's Hans face.
    static func _traditional(_ n: XNode) -> Bool {
        if n.name == "a:rPr" || n.name == "a:defRPr", let l = n["lang"]?.lowercased(), ["zh-tw", "zh-hk", "zh-mo"].contains(l) { return true }
        return n.children.contains { _traditional($0) }
    }
    static let _fieldMarks = ["CATEGORYNAME": "\u{E000}c", "VALUE": "\u{E000}v", "SERIESNAME": "\u{E000}s", "PERCENTAGE": "\u{E000}p"]

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
        return _cycleFill(s.autoIndex ?? i)
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
            let head = "<c:idx val=\"\(s.autoIndex ?? i)\"/><c:order val=\"\(i)\"/>\(tx)"
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
        // (A pie's says where its labels stand, as it was read: inside,
        // as this app draws plain ones, or round it.)
        let labels = !c.dataLabels ? "" : c.type.isPie
            ? _labels.replacingAll("<c:showLegendKey", with: "<c:dLblPos val=\"\(c.pieLabelsAround ? "bestFit" : "ctr")\"/><c:showLegendKey")
            : _labels
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
                plot += "<c:valAx><c:axId val=\"500000001\"/><c:scaling><c:orientation val=\"minMax\"/></c:scaling><c:delete val=\"0\"/><c:axPos val=\"b\"/>\(c.scatterXGrid ? "<c:majorGridlines><c:spPr>\(_gridLine)</c:spPr></c:majorGridlines>" : "")\(catTitle)<c:numFmt formatCode=\"General\" sourceLinked=\"1\"/>\(tail)<c:spPr><a:noFill/>\(_gridLine)</c:spPr><c:crossAx val=\"500000002\"/><c:crosses val=\"autoZero\"/><c:crossBetween val=\"midCat\"/></c:valAx>"
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
    /// The fallback for `c`'s own text (`Chart.macSimplifiedFace`), its
    /// Traditional Chinese text's where `traditional`.
    /// A label's text as Word for Windows sets it where the chart's East
    /// Asian text is MS Mincho's (`Chart.windowsMinchoText`): its Chinese
    /// on Mincho's line, 1.3 em, and JhengHei's 1.729 where Mincho lacks a
    /// character — not the platform fallback's, 1.4 em. Word for Windows'
    /// print of zh-27a874b7's chart 2: "香港" over "44" and "11%" at 9.96pt,
    /// its first baseline 12.48 over the second (ours 12.9), the label
    /// 1.1pt shorter than ours and so inside its 11% slice, where ours
    /// stood outside.
    static func labelSpan(_ c: Chart, _ text: String, _ style: Flutter.TextStyle) -> TextSpan {
        guard c.windowsMinchoText, let covers = OfficeFonts.windowsMinchoCovers,
              text.unicodeScalars.contains(where: { (0x2E80 ... 0x9FFF).contains($0.value) }) else { return TextSpan(text: text, style: style) }
        var runs: [(String, Double?)] = []
        for ch in text {
            let cjk = ch.unicodeScalars.first.map { (0x2E80 ... 0x9FFF).contains($0.value) } ?? false
            let h: Double? = cjk ? (ch.unicodeScalars.allSatisfy { covers.contains($0.value) } ? 1.3 : 1.3301 * 1.3) : nil
            if let last = runs.last, last.1 == h { runs[runs.count - 1].0.append(ch) } else { runs.append((String(ch), h)) }
        }
        return TextSpan(children: runs.map { TextSpan(text: $0.0, style: $0.1.map { Flutter.TextStyle(height: $0) }) }, style: style)
    }

    static func glyphFallback(_ c: Chart, traditional: Bool = false) -> [String]? {
        guard let face = (traditional ? c.macTraditionalFace : nil) ?? c.macSimplifiedFace else { return glyphFallback }
        return [face] + RichTextTheme.glyphFallback
    }

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
        func styled(_ s: String, _ size: Double, _ maxWidth: Double, bold: Bool, color: Color? = nil, align: TextAlign = .center) -> TextPainter {
            let tp = TextPainter(text: TextSpan(text: s, style: Flutter.TextStyle(
                color: color ?? ink, fontSize: max(3, size * k), fontWeight: bold ? .bold : .normal,
                fontFeatures: plain, fontFamily: font, fontFamilyFallback: Self.glyphFallback(c))),
                textAlign: align, textDirection: .ltr)   // (a label broken in two centres each line)
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
        // 2.5 pt further out in PowerPoint's print. With its legend below,
        // 8.2: see the legend.)
        let old = c.plainText && !c.styled2013 && c.officeStyled
        // (A chartex chart's title stands 2.2 pt higher than a `c:`
        // chart's, its plot's foot 4.4 nearer the frame: chartex's
        // box-and-whisker chart in Word's print, the title's baseline 18.7
        // under the frame's top where a `c:` chart's is about 21.)
        // (A newer chart on a slide with no legend under it keeps 6.9 pt
        // at its foot: tdf149985's and tdf114821's category labels print
        // 2.1 pt lower than 9 put them; one with a legend there keeps 9,
        // chart-slide-bg's labels where PowerPoint's are.)
        let foot = c.onSlide && !(c.legend && c.legendPosition == "b") ? 6.9 : 9.0
        var area = Rect.fromLTRB(r.left + (old ? 6.5 : 9) * k, r.top + (c.chartex ? 6.8 : 9) * k, r.right - 9 * k,
                                 r.bottom - (old ? (c.onSlide && c.legend && c.legendPosition == "b" ? 8.2 : 6.5) : c.chartex ? 4.6 : foot) * k)

        let titled = !(c.title ?? "").isEmpty
        var placed: (TextPainter, Offset)? = nil
        if let title = c.title, !title.isEmpty {
            // In the file's size, weight and colour where it gives them,
            // each line centred. (A Word document's chart that gives no size anywhere: 10pt, as
            // Word's print of fdo78474's "Sales" and the rest of its text.)
            let titleStyle = Flutter.TextStyle(
                color: c.titleColor ?? ink, fontSize: max(3, (c.titleSize ?? c.textSize.map { ($0 * 1.2).rounded() } ?? (!c.onSlide && !c.onSheet && !c.chartex ? 10 : 18.6)) * k),
                fontWeight: c.titleBold ? .bold : .normal, fontFeatures: plain,
                fontFamily: OfficeFonts.substitute(c.titleFont ?? theme.bodyFont), fontFamilyFallback: Self.glyphFallback(c, traditional: c.titleTraditional))
            // (A line in a size of its own, as its own span.)
            let span: TextSpan
            if c.titleLineSizes.isEmpty {
                span = TextSpan(text: title, style: titleStyle)
            } else {
                let lines = title.components(separatedBy: "\n")
                span = TextSpan(children: lines.enumerated().map { i, line in
                    TextSpan(text: line + (i < lines.count - 1 ? "\n" : ""),
                             style: c.titleLineSizes[i].map { Flutter.TextStyle(fontSize: max(3, $0 * k)) })
                }, style: titleStyle)
            }
            // (As wide as its longest line, wrapped or not: a title placed
            // by the file stands its widest line 3 pt into its box, and a
            // wrapped one as wide as the room it wrapped in stood aascu
            // 5864's 12 and 19 pt right of PowerPoint's.)
            let tp = TextPainter(text: span, textAlign: .center, textDirection: .ltr, textWidthBasis: .longestLine)
            // No wider than four fifths of the chart: aascu 5864's 20 pt
            // title breaks before "at" in PowerPoint's print, its first
            // line 535 pt of a 696 pt chart, "at" taking it past 557.
            // (Word's too, beside Excel's: tdf122014's 14pt title in a 432pt
            // chart wraps before "left" in Word for Windows' print, its first
            // line 340.5pt wide; ours took "left when" on it, 397pt.)
            tp.layout(minWidth: 0, maxWidth: max(1, c.onSlide || !c.onSheet ? min(area.width, 0.8 * r.width) : area.width))
            // (Where Word for Windows sets the theme's text in Mincho, a
            // title line holding a character Mincho lacks is JhengHei's,
            // 1.729 em to Mincho's 1.3 (`_tableRows`): it grows by the
            // difference, its text half of it lower. Word for Windows'
            // print of zh-13d11e99's theme-faced "主动公开信数量" at 14pt,
            // "动" in JhengHei: its baseline 3.67 and the plot's top 6.34
            // under Word for Mac's, which sets it all in SimSun.)
            var grown = 0.0
            if c.windowsMinchoTitle, c.titleFont == nil, c.titleAt == nil, let covers = OfficeFonts.windowsMinchoCovers {
                let units = Array(title.utf16)
                var start = 0
                repeat {
                    let range = tp.getLineBoundary(TextPosition(offset: start))
                    let end = max(start + 1, min(units.count, range.end))
                    let line = String(decoding: units[start ..< end], as: UTF16.self)
                    if line.unicodeScalars.contains(where: { (0x2E80 ... 0x9FFF).contains($0.value) && !covers.contains($0.value) }) {
                        grown += (1.3301 * 1.3 - 1.3) * (c.titleLineSizes.isEmpty ? titleStyle.fontSize ?? 0 : c.titleLineSizes.values.max()! * k)
                    }
                    start = end
                } while start < units.count
            }
            // (Where Word for Mac sets it in the theme's East Asian face, a
            // title holding Chinese is on that face's East Asian line, its
            // text at the line's baseline: lab `ctitle`, zh-13d11e99's 14pt
            // "主动公开信数量" in SimSun, 1.293 em, its baseline 1.017 em
            // under the line's top — where SimSun's own line, an em, set
            // ours and its plot 3.3 high, 4.8 at 24pt.)
            var drop: Double? = nil
            if c.titleFont == nil, c.titleAt == nil,
               let face = (c.titleTraditional ? c.macTraditionalFace : nil) ?? c.macSimplifiedFace,
               title.unicodeScalars.contains(where: { (0x2E80 ... 0x9FFF).contains($0.value) }),
               let line = OfficeFonts.eastAsianLine(face, bold: c.titleBold) {
                let size = c.titleLineSizes.isEmpty ? titleStyle.fontSize ?? 0 : c.titleLineSizes.values.max()! * k
                for (i, m) in tp.computeLineMetrics().enumerated() {
                    grown += line.height * size - m.height
                    if i == 0 { drop = line.baseline * size - m.ascent }
                }
            }
            // (Two points higher than the area's edge: where PowerPoint's
            // sits. Or where the file places its box, 3 pt in and 1.5
            // down, over the plot: LIBRE_OFFICE-100610's bar charts'
            // titles, across their bars.)
            // Its box, where it has one: 3 pt beside the text and 1.5 over
            // and under it (chart-tdf161607's black box ruled in red round
            // its 40 pt title, in Excel's print).
            if let at = c.titleAt {
                placed = (tp, Offset(r.left + at.dx * r.width + 3 * k, r.top + at.dy * r.height + 1.5 * k))
            } else {
                // (On a sheet 2.5 pt lower, and the plot under it with it:
                // Excel's prints of eight titled charts, 13 to 40 pt, stand
                // 2.2 to 3.0 lower than ours did, their plots' tops 3 to 4.)
                if c.onSheet { area = Rect.fromLTRB(area.left, area.top + 3.4 * k, area.right, area.bottom) }
                // (An Excel 2016 chart's 0.43 pt higher, its plot not:
                // twelve `cx:` charts' titles' baselines in Excel's print,
                // 18.76 under the frame's top in chart-sunburst's. Not 2.4
                // lower, as the glyphs' tops measured against our box's
                // once had it: 2.83 under Excel's, all twelve.)
                let o = Offset(area.center.dx - tp.width / 2, area.top - 2 * k + (drop ?? grown / 2) + (c.onSheet && c.chartex ? -0.43 * k / 0.75 : 0))
                Self._titleBox(c, canvas, around: Rect.fromLTWH(o.dx, o.dy, tp.width, tp.height), k: k)
                tp.paint(canvas, o)
            }
            // (Gaps from PowerPoint's own default chart, chart-slide-bg:
            // title to plot 3.6, plot to its category labels 7.6, labels to
            // the legend 8.4, the legend 1.2 above the margin, value labels
            // 8.5 from the plot — each where its text sits on the page.)
            // (A chartex chart's plot 2 pt nearer: 12.8 under the title's
            // baseline in Word's print of chartex's, a `c:` chart's 14.9.)
            // (A pie on a slide stands 7 under it: pie-chart's, its top
            // 2.75 pt lower in PowerPoint's print and the pie 3.25 smaller.)
            let pieOnSlide = c.onSlide && c.type == .pie && c.ofPie == nil && c.pieTilt == nil
            area = Rect.fromLTRB(area.left, area.top + tp.height + grown + (c.chartex ? 1.6 : pieOnSlide ? 6.95 : 3.6) * k, area.right, area.bottom)
            if placed == nil { tp.dispose() }
        }

        // The legend: one row of key + name, centred, wrapped when wide.
        let pie = c.type.isPie
        if c.legend {
            // (A waterfall's: its rises, falls and totals.)
            let waterfall = c.waterfallTotals.map { ["Increase", "Decrease"] + ($0.isEmpty ? [] : ["Total"]) }
            let byPoint = (pie || c.variedPoints || waterfall != nil) && !c.surface
            // (A surface's legend is its value bands: "0-4", "4-8"…)
            let names = c.surface ? Self._surfaceBands(c).map { "\(label($0.lo, percent: false))-\(label($0.hi, percent: false))" }
                : waterfall ?? (byPoint ? c.categories : c.series.map(\.name) + c.lineSeries.map(\.name))
            // In the legend's own size, its keys and gaps in proportion.
            let size = c.legendSize ?? c.baseTextSize, m = size / 12
            var entries = names.enumerated().filter { !c.hiddenLegendEntries.contains($0.offset) }
                .map { (i: $0.offset, tp: styled($0.element, size, .infinity, bold: c.legendBold, color: c.legendColor)) }
            // (9.5 between a row's entries on a newer chart: chart-slide-bg's
            // legend pitches 58.6 pt in PowerPoint's print, ours 60.9 at 12.)
            // Beside the plot (`legendPos` r, l, tr): a column, an entry to
            // a line, in the middle of the side; above or below: rows.
            let box = c.legendBox.map { Rect.fromLTWH(r.left + $0.left * r.width, r.top + $0.top * r.height, $0.width * r.width, $0.height * r.height) }
            let beside = box == nil && ["r", "l", "tr"].contains(c.legendPosition)
            // (A newer chart's row on a slide as PowerPoint prints chart-
            // slide-bg's 12 pt legend: a key 6.57 square, 2.92 before its
            // name, 11.2 between entries, the key's foot half a point
            // under the baseline — 1.3 lower than a key centred on the
            // line, as ours stood. Not a column beside the plot:
            // tdf149985's went +0.25 so. A 2007-style chart's keys are the
            // same, cooper's 10 pt legend's 5.47 square and 2.4 before
            // their names, its entries 13.9 apart at 12 pt, the keys
            // where a centred one stands.)
            let printed = c.onSlide && !beside
            // (Beside the plot too: aascu 5864's 20 pt column's keys 10.98
            // square, tdf149985's 9 pt 4.94, 2.92 at 12 before the names.)
            let key = (c.onSlide ? 6.57 : 7) * k * m, gap = (c.onSlide ? 2.92 : 4) * k * m
            let spacing = (printed ? (c.styled2013 ? 11.2 : 13.9) : c.styled2013 ? 9.5 : 12) * k * m
            let keyDrop = printed && c.styled2013 ? 1.3 * k * m : 0
            // A line's key is a stroke 19.2 pt long whatever the text's
            // size, ending 2 pt before its name; in a row, 3.6 more before
            // it (chartex's line and radar charts in Word's print: their
            // 9 pt entries pitch 60.3, a bar chart's 44.1). A column keeps
            // its width, the line reaching out of it: line-chart's 18 pt
            // legend in PowerPoint's print, its plot where ours was.
            let lineKeys = c.type == .line || (c.type == .radar && !c.radarFilled)
            // Room before an entry's name.
            let lead = lineKeys && !beside ? 24.8 * k : key + gap
            // (In a place of its own a name wider than the place wraps
            // within it, set left: zh-61aaad09's pie legend, 26% of the
            // chart's width, sets "实体投诉举报" as "实体投诉" / "举报" in Word's
            // print.)
            if let box {
                entries = entries.map { e in
                    guard lead + e.tp.width > box.width + 0.01 else { return e }
                    e.tp.dispose()
                    return (i: e.i, tp: styled(names[e.i], size, max(size * k, box.width - lead), bold: c.legendBold, color: c.legendColor, align: .left))
                }
            }
            // A column beside stacked columns (or areas) reads as the stack
            // does, the last series — the top of it — first.
            if beside, c.stacked, c.type == .column || c.type == .area { entries.reverse() }
            // And a bar chart's, at any side, as its bars run: series 1 at
            // the bottom, listed last (LIBRE_OFFICE-100610-0's five).
            if c.type == .bar, !c.stacked { entries.reverse() }
            var lines: [[(i: Int, tp: TextPainter)]] = [[]]
            var lineW = 0.0
            for e in entries {
                let w = lead + e.tp.width
                if lineW > 0, beside || lineW + spacing + w > (box?.width ?? area.width) { lines.append([]); lineW = 0 }
                lineW += (lineW > 0 ? spacing : 0) + w
                lines[lines.count - 1].append(e)
            }
            // (An entry to a line: PowerPoint's 9 pt entries are 16.9 pt apart.)
            // (A line of the chart's Latin face, whatever the names' script:
            // zh-37b6536f's Chinese entries, 9pt, stand 16.8 apart in Word's
            // print — Calibri's line and the gap — where the CJK fallback's
            // taller line set ours 19.05 apart.)
            let latin = styled("X", size, .infinity, bold: c.legendBold, color: c.legendColor)
            let textH = entries.isEmpty ? size * k : latin.height
            latin.dispose()
            let lineH = beside ? textH + 6 * k : textH
            // (Each line as tall as its tallest name, a wrapped one too.)
            var lineHs = lines.map { line in max(lineH, line.map { $0.tp.height }.max() ?? 0) }
            // (A place of its own taller than its lines shares its height
            // among them: zh-61aaad09's two entries, in a box 94% of the
            // chart's height, stand 57pt apart in Word's print, each in the
            // middle of its half.)
            if let box, lineHs.reduce(0, +) < box.height, !lines.isEmpty {
                lineHs = lines.map { _ in box.height / Double(lines.count) }
            }
            let linesH = lineHs.reduce(0, +)
            let columnW = (entries.map(\.tp.width).max() ?? 0) + lead
            var y: Double, columnX = 0.0
            if let box {
                // In its own place, the plot's room untouched — unless the
                // plot is left to Word's layout and the legend is set below
                // (or above) it: the plot still gives up the row it would
                // have had (lo-a14e916b's legend, at the right, with
                // `legendPos` b: Word's plot ends 18pt higher than ours).
                y = box.center.dy - linesH / 2
                if !pie, !c.onSlide, !c.onSheet, c.plotLayout == nil, c.legendPosition == "b" {
                    RuleTrace.hit("legend-box-keeps-its-row-below-the-plot")
                    area = Rect.fromLTRB(area.left, area.top, area.right,
                                         area.bottom - 1.2 * k - lineH - 8.4 * k)
                }
            } else if beside {
                y = c.legendPosition == "tr" ? area.top : area.center.dy - lineH * Double(lines.count) / 2
                if c.legendPosition == "l" {
                    columnX = area.left
                    area = Rect.fromLTRB(area.left + columnW + 12 * k, area.top, area.right, area.bottom)
                } else {
                    // (A point further in than the plot's margin on a slide:
                    // the names end 9.8 and 10.2 pt short of the frame in
                    // tdf149985's and aascu 5864's columns.)
                    columnX = area.right - columnW - (c.onSlide ? 1 : 0) * k
                    // (17.3 to the legend's keys: the 2007-style line,
                    // scatter, radar and bar charts' plots end 5.3 pt
                    // short of where 12 left them, in PowerPoint's print.)
                    let apart = !pie && !c.styled2013 ? 17.3 : 12
                    // (The plot ends where it did with the 7 pt keys and 4 pt
                    // gap these gaps were measured with: its edge is
                    // PowerPoint's, the column's keys moved within it.)
                    let measured = (entries.map(\.tp.width).max() ?? 0) + 11 * k * m
                    area = Rect.fromLTRB(area.left, area.top, area.right - measured - apart * k, area.bottom)
                }
            } else if c.legendPosition == "t" {
                // (Under a title, 4.3 further off it than a plot would
                // be: in Word's print a legend's baseline is 22.2 pt under
                // a 14 pt title's, chartex's radar's and its column
                // chart's moved to the top, where ours was 17.9. With no
                // title the legend is where ours was, 17 under the
                // frame's top.)
                // (A `cx:` chart's on a sheet 3.71 pt lower again under its
                // title, and its plot 6.37 further off it: chart-
                // clusteredColumn's and chart-waterfall's in Excel's print,
                // the legend's baseline 23.06 under the title's, the plot's
                // top 60.6 under the frame's.)
                let sheetCx = titled && c.onSheet && c.chartex ? k / 0.75 : 0
                y = area.top + (titled ? 4.3 * k : 0) + 3.71 * sheetCx
                area = Rect.fromLTRB(area.left, y + lineH * Double(lines.count) + 6 * k + 6.37 * sheetCx, area.right, area.bottom)
            } else {
                // (A 2007-style chart's on a slide 8.2 pt off the frame's
                // foot, not 6.5, and its plot 9.55 above it: cooper's two
                // 10 pt legends 1.7 pt higher in PowerPoint's print, their
                // plots 2.9.)
                // (On a sheet 2.2 pt higher, and the plot's foot 4.43 higher:
                // Excel's prints of nine charts with the legend below.)
                let pt = c.onSheet ? k / 0.75 : 0
                y = area.bottom - 1.2 * k - lineH * Double(lines.count) - 2.2 * pt
                area = Rect.fromLTRB(area.left, area.top, area.right, y - (printed && old ? 9.55 : 8.4) * k - 2.23 * pt)
            }
            for (n, line) in lines.enumerated() {
                let lineH = lineHs[n]
                let w = line.reduce(0.0) { $0 + lead + $1.tp.width } + spacing * Double(max(0, line.count - 1))
                // (A row on a slide stands 0.19 of its size right of the
                // frame's middle: chart-slide-bg's 12 pt legend 2.37 pt in
                // PowerPoint's print, cooper's 10 pt ones 1.76 and 1.74 —
                // theirs a 2007-style chart's, whose area is not centred.)
                let middle = printed ? r.center.dx + 2.28 * k * m : area.center.dx
                var x = beside ? columnX : (box?.center.dx ?? middle) - w / 2
                for e in line {
                    let p = Paint()
                    p.style = .fill
                    p.isAntiAlias = true
                    if !byPoint, e.i >= c.series.count {
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
                    p.color = waterfall != nil ? c.color(series: e.i, accents: theme.accents)
                        : byPoint ? c.pointColor(e.i, accents: theme.accents)
                        : lineKeys ? c.lineColor(series: e.i, accents: theme.accents) : c.color(series: e.i, accents: theme.accents)
                    if lineKeys, !pie, e.i < c.series.count, c.series[e.i].lineHidden {
                        // (A series with no line: its mark alone, if any.)
                        Self._mark(c.series[e.i], at: Offset(x + lead - 11.6 * k, y + lineH / 2), k: k, colour: p.color, canvas)
                    } else if lineKeys {
                        p.style = .stroke
                        p.strokeWidth = 2.25 * k
                        canvas.drawLine(Offset(x + lead - 21.2 * k, y + lineH / 2), Offset(x + lead - 2 * k, y + lineH / 2), p)
                    } else if c.type == .scatter {
                        canvas.drawCircle(Offset(x + key / 2, y + lineH / 2), 2.5 * k, p)
                    } else {
                        canvas.drawRect(Rect.fromLTWH(x, y + (lineH - key) / 2 + keyDrop, key, key), p)
                    }
                    e.tp.paint(canvas, Offset(x + lead, y + (lineH - e.tp.height) / 2))
                    x += lead + e.tp.width + spacing
                }
                y += lineH
            }
            for line in lines { for e in line { e.tp.dispose() } }
        }

        if pie, let l = c.plotLayout {
            area = Rect.fromLTWH(r.left + l.left * r.width, r.top + l.top * r.height, l.width * r.width, l.height * r.height)
        }
        if c.surface {
            _surface(c, canvas, area, k: k, theme: theme, grid: c.gridColor ?? grid,
                     text: { styled($0, $1, $2, bold: false, color: c.valueLabelColor) })
        } else if let nodes = c.sunburst, c.treemap {
            _treemap(c, nodes, canvas, area, k: k, theme: theme,
                     text: { styled($0, $1, $2, bold: false, color: theme.background) })
        } else if let nodes = c.sunburst {
            _sunburst(c, nodes, canvas, area, k: k, theme: theme,
                      text: { styled($0, $1, $2, bold: false, color: theme.background) })
        } else if c.type == .radar {
            _radar(c, canvas, area, k: k, theme: theme, grid: c.gridColor ?? (c.onSlide && !c.styled2013 && c.officeStyled ? Color(0xFF868686) : grid),
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
        if let (tp, at) = placed {
            Self._titleBox(c, canvas, around: Rect.fromLTWH(at.dx, at.dy, tp.width, tp.height), k: k)
            tp.paint(canvas, at)
            tp.dispose()
        }
        canvas.restore()
    }

    /// The title's box, where it has one: 3 pt beside the text and 1.5
    /// over and under it (chart-tdf161607's black box ruled in red round
    /// its 40 pt title, in Excel's print).
    static func _titleBox(_ c: Chart, _ canvas: any Canvas, around text: Rect, k: Double) {
        guard c.titleFill != nil || c.titleLine != nil else { return }
        let b = Rect.fromLTRB(text.left - 4 * k, text.top - 2 * k, text.right + 4 * k, text.bottom + 2 * k)
        let p = Paint()
        p.isAntiAlias = true
        if let f = c.titleFill { p.style = .fill; p.color = f; canvas.drawRect(b, p) }
        if let l = c.titleLine {
            p.style = .stroke; p.color = l; p.strokeWidth = max(0.25, c.titleLineWidth * k)
            if c.titleLineRound { p.strokeCap = .round; p.strokeJoin = .round }
            let path = Path()
            path.addRect(b)
            canvas.drawPath(SlidePainter.dashed(path, c.titleLineDash, width: p.strokeWidth, capped: c.titleLineRound), p)
        }
    }

    private static func _mix(_ a: Color, _ b: Color, _ t: Double) -> Color {
        func ch(_ v: Int, _ s: Int) -> Int { (v >> s) & 0xFF }
        func m(_ s: Int) -> Int { Int((Double(ch(a.value, s)) * t + Double(ch(b.value, s)) * (1 - t)).rounded()) }
        return Color(0xFF00_0000 | Int64((m(16) << 16) | (m(8) << 8) | m(0)))
    }

    /// The data table's rows, the categories' first, then a series' each.
    /// 1.64 em apiece: Word for Mac's print of zh-2a241df1's two tables,
    /// 16.4pt at 10pt. Where Word for Windows sets the text in Mincho and
    /// JhengHei (`Chart.windowsMinchoText`), 3.4pt and the row's deepest
    /// label, line by line wrapped as drawn: Mincho's line (1.3 em) or,
    /// for a line holding a character Mincho lacks, JhengHei's (1.729 em).
    /// Word for Windows' prints: zh-2a241df1's "2022年" rows 16.4 at 10pt
    /// and its "举报"/"总" categories' and "同比增长率" rows 20.4 and 20.6;
    /// zh-61aaad09's rows 17.6 at 11pt and its wrapped "投诉举报总量"
    /// categories 36.8 (a JhengHei line and a Mincho one).
    static func _tableRows(_ c: Chart, size: Double, k: Double, slot: Double, text: (String, Double, Double) -> TextPainter) -> [Double] {
        let count = c.series.count + c.lineSeries.count + 1
        // (Word for Mac wraps a category as Word for Windows does, each
        // line past the first its face's East Asian line deeper: zh-
        // 61aaad09's 11pt "投诉举报总" / "量" in SimSun, 14.4 apart in its print.)
        if !c.windowsMinchoText, let face = c.macSimplifiedFace, let line = OfficeFonts.eastAsianLine(face) {
            var rows = Array(repeating: 1.64 * size * k, count: count)
            let lines = c.categories.map { s -> Int in
                let tp = text(s, size, max(1, slot - 7.2 * k))
                defer { tp.dispose() }
                return tp.computeLineMetrics().count
            }.max() ?? 1
            rows[0] += Double(max(0, lines - 1)) * line.height * size * k
            return rows
        }
        guard c.windowsMinchoText, let covers = OfficeFonts.windowsMinchoCovers else {
            return Array(repeating: 1.64 * size * k, count: count)
        }
        func depth(_ s: String, _ width: Double) -> Double {
            let tp = text(s, size, width)
            defer { tp.dispose() }
            let units = Array(s.utf16)
            var total = 0.0, start = 0
            repeat {
                let range = tp.getLineBoundary(TextPosition(offset: start))
                let end = max(start + 1, min(units.count, range.end))
                let line = String(decoding: units[start ..< end], as: UTF16.self)
                let lacks = line.unicodeScalars.contains { (0x2E80 ... 0x9FFF).contains($0.value) && !covers.contains($0.value) }
                total += (lacks ? 1.3301 * 1.3 : 1.3) * size * k
                start = end
            } while start < units.count
            return total
        }
        // (A category wraps inside its column less 3.6pt a side: Word for
        // Windows breaks zh-61aaad09's 11pt "投诉举报总量" after five in a
        // 71pt column.)
        var rows = [3.4 * k + (c.categories.map { depth($0, max(1, slot - 7.2 * k)) }.max() ?? 1.3 * size * k)]
        for s in c.series + c.lineSeries {
            let values = s.values.compactMap { $0 }.map { label($0, percent: false) }
            rows.append(3.4 * k + ([depth(s.name, .infinity)] + values.map { depth($0, slot) }).max()!)
        }
        return rows
    }

    /// A data table under `plot` (see `Chart.dataTable`): the categories
    /// over the plot's columns, then a row for each series — its key and
    /// name from `left`, its numbers centred under their categories — in
    /// grey rules.
    private static func _dataTable(_ c: Chart, _ dt: DataTable, _ canvas: any Canvas, plot: Rect, top: Double, rows heights: [Double], left: Double,
                                   size: Double, n: Int, k: Double, theme: DeckTheme, text: (String, Double, Double) -> TextPainter) {
        let rows = c.series.map { ($0, c.type == .line) } + c.lineSeries.map { ($0, true) }
        /// Row `j`'s top (0 the categories') and height.
        func rowTop(_ j: Int) -> Double { top + heights.prefix(j).reduce(0, +) }
        func rowHeight(_ j: Int) -> Double { heights[safe: j] ?? heights.last ?? 0 }
        let bottom = rowTop(heights.count)
        let slot = plot.width / Double(max(1, n))
        // Each row's text on one baseline, 0.27 em under the row's middle,
        // whatever its face: Word's print of zh-2a241df1's tables sets
        // Calibri digits and SimSun names 10.9pt into a 16.4pt row at
        // 10pt, where centring each line's own box set the digits 0.7pt
        // and the names (a YaHei-tall line) 1.3pt lower.
        // (Under Word for Windows' faces, a label of several lines
        // centred as a block: zh-61aaad09's wrapped categories.)
        func textTop(_ tp: TextPainter, _ j: Int) -> Double {
            let lines = c.windowsMinchoText || c.macSimplifiedFace != nil ? tp.computeLineMetrics().count : 1
            return rowTop(j) + rowHeight(j) / 2 + 0.27 * size * k - tp.computeDistanceToActualBaseline(.alphabetic)
                - (tp.height - tp.height / Double(max(1, lines))) / 2
        }
        func centred(_ s: String, _ cx: Double, _ j: Int) {
            let tp = text(s, size, j == 0 && (c.windowsMinchoText || c.macSimplifiedFace != nil) ? max(1, slot - 7.2 * k) : slot)
            tp.paint(canvas, Offset(cx - tp.width / 2, textTop(tp, j)))
            tp.dispose()
        }
        for i in 0 ..< n { centred(c.categories[safe: i] ?? "", plot.left + (Double(i) + 0.5) * slot, 0) }
        let fill = Paint()
        fill.style = .fill
        fill.isAntiAlias = true
        // (A table that states its lines sets its square keys in its own
        // text's ems: Excel's 9 pt print of chart-DataTable-Multiple…, its
        // key 4.94 square, 3.2 in and the name 10.3, where F10's 10 pt
        // in Word are 5.49, 3.5 and 11.4.)
        // (A line's key is as long in points on a sheet: chart-
        // ChartDataTable's names 24.5 pt in, in Excel's print.)
        let e = dt.squareKeys ? size / 10 * k : k, u = c.onSheet ? k / 0.75 : k
        for (j, (s, line)) in rows.enumerated() {
            let y = rowTop(j + 1), row = rowHeight(j + 1)
            let colour = s.color ?? c.color(series: j, accents: theme.accents)
            var x = left + (dt.squareKeys && !line ? 3.5 * e : 3.2 * u)
            if dt.keys {
                if line {
                    let p = Paint()
                    p.style = .stroke
                    p.isAntiAlias = true
                    p.strokeWidth = max(0.5, 2.25 * k)
                    p.color = colour
                    canvas.drawLine(Offset(x, y + row / 2), Offset(x + 19.2 * u, y + row / 2), p)
                } else {
                    fill.color = colour
                    canvas.drawRect(Rect.fromLTWH(x, y + row / 2 - 2.75 * e, (dt.squareKeys ? 5.5 : 19.2) * e, 5.5 * e), fill)
                }
                x += dt.squareKeys && !line ? 7.9 * e : 21.2 * u
            }
            let name = text(s.name, size, .infinity)
            name.paint(canvas, Offset(x, textTop(name, j + 1)))
            name.dispose()
            for i in 0 ..< n {
                guard let v = s.values[safe: i] ?? nil else { continue }
                let shown = s.format.map { NumberFormat.format(v, $0, width: 40).text.trimmingWhitespace() } ?? ""
                centred(shown.isEmpty ? label(v, percent: false) : shown, plot.left + (Double(i) + 0.5) * slot, j + 1)
            }
        }
        let rule = Paint()
        rule.style = .stroke
        rule.strokeWidth = max(0.5, 0.75 * k)
        rule.color = dt.lineColor ?? _mix(theme.text, theme.background, 0.46)
        if let w = dt.lineWidth { rule.strokeWidth = max(0.5, w * k) }
        // Across: under the categories' row and between the series'; the
        // categories' row starts at the plot, the series' at their names.
        if dt.horizontalRules {
            for j in 1 ... rows.count { canvas.drawLine(Offset(left, rowTop(j)), Offset(plot.right, rowTop(j)), rule) }
        }
        if dt.verticalRules {
            for i in 1 ..< max(1, n) { canvas.drawLine(Offset(plot.left + Double(i) * slot, top), Offset(plot.left + Double(i) * slot, bottom), rule) }
            canvas.drawLine(Offset(plot.left, top), Offset(plot.left, bottom), rule)
        }
        if dt.outline {
            canvas.drawLine(Offset(plot.left, top), Offset(plot.right, top), rule)
            canvas.drawLine(Offset(plot.right, top), Offset(plot.right, bottom), rule)
            canvas.drawLine(Offset(left, rowTop(1)), Offset(left, bottom), rule)
            canvas.drawLine(Offset(left, bottom), Offset(plot.right, bottom), rule)
        }
    }

    /// Round axis bounds and a step, Excel's way: about five to ten
    /// gridlines, 5% headroom above the data.
    /// The step is the smallest of 1, 2, 5 × a power of ten that marks the
    /// axis in no more than `intervals` steps. Ten up the page: Word's
    /// prints of zh-2a241df1's charts (Excel's engine) run 435,043 to
    /// 500,000 by 50,000 (nine made it 100,000), 360,760 to 400,000 by
    /// 50,000, and 49% and 55% to 60% by 10%; PowerPoint's agree — 0 to
    /// 1,600 in 200s, 0 to 600 in 100s, 0 to 6 in ones, 0 to 9 in ones
    /// (line-chart's 8.2, where eight made it 0 to 10 in twos) — and no
    /// deck's axis tells nine from ten. Across the page, eight.
    static func scale(_ lo0: Double, _ hi0: Double, intervals: Int = 10, headroom: Double = 0.05) -> (lo: Double, hi: Double, step: Double) {
        if let s = _offZero(lo0, hi0, intervals: intervals) { return s }
        var lo = min(0, lo0), hi = max(0, hi0)
        if hi == lo { hi = lo + 1 }
        let span = hi - lo
        if hi > 0 { hi += span * headroom }
        if lo < 0 { lo -= span * headroom }
        let rough = (hi - lo) / Double(max(1, intervals))
        let mag = pow(10, floor(log10(rough)))
        let norm = rough / mag
        let step = (norm <= 1 ? 1 : norm <= 2 ? 2 : norm <= 5 ? 5 : 10) * mag
        return (floor(lo / step) * step, ceil(hi / step) * step, step)
    }

    /// Excel's automatic axis leaves zero out where the values lie close
    /// together: all of one sign, the nearest to zero more than 5/6 of the
    /// farthest. It then starts half their spread short of the nearest and
    /// runs 5% past the farthest, rounded out to its step. zh-b8de3ae2's
    /// rates 92.05 to 94.99 run 90.5 to 95.5 by 0.5 in Word's print; ours
    /// ran 0 to 100 and the line lay flat along the top. (Against a fixed
    /// far end where the file gives one: zh-547fc43c's 28.35 to 33.5 under
    /// a maximum of 40 start at 0, as Word's.)
    static func _offZero(_ lo0: Double, _ hi0: Double, intervals: Int) -> (lo: Double, hi: Double, step: Double)? {
        let neg = hi0 < 0
        let a = neg ? -hi0 : lo0, b = neg ? -lo0 : hi0
        // (Not strictly: lo-60124a3f's area, 5 and 6, runs 4.4 to 6.2 by 0.2 in
        // Word's print, 5 being exactly five sixths of 6.)
        guard a > 0, b > a, a >= b * 5 / 6 - 1e-9 else { return nil }
        let d = b - a
        // (5% of the run from where the axis starts, not of the values'
        // spread: zh-b8de3ae2's chart 10 rates, 84.97 to 99.22, run 75 to
        // 105 on its right axis in Word's print — 99.22 + 5% of 21.4 is
        // 100.29 — where ours stopped at 100.)
        let lo = a - d / 2, hi = b + (b - lo) * 0.05
        let rough = (hi - lo) / Double(max(1, intervals))
        let mag = pow(10, floor(log10(rough)))
        let norm = rough / mag
        let step = (norm <= 1 ? 1 : norm <= 2 ? 2 : norm <= 5 ? 5 : 10) * mag
        let l = floor(lo / step) * step, h = ceil(hi / step) * step
        return neg ? (-h, -l, step) : (l, h, step)
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

    /// An axis tick in the General format: as many decimals as the value needs
    /// (the ticks are multiples of a nice step, so ten are all there are).
    /// Word's print of tdf130969 (axis 0.35781 to 0.3579 by 0.00001) reads
    /// "0.35781 … 0.3579", where `label`'s two decimals made every one "0.36".
    static func tickLabel(_ v: Double) -> String {
        if abs(v - v.rounded()) < 1e-9 { return String(Int(v.rounded())) }
        var s = String(printf: "%.10f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s == "-0" ? "0" : s
    }

    static func label(_ v: Double, percent: Bool) -> String {
        if percent { return "\(Int((v * 100).rounded()))%" }
        if abs(v - v.rounded()) < 1e-9 { return String(Int(v.rounded())) }
        var s = String(printf: "%.2f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    /// A funnel: its categories down the left, the first at the top, and
    /// each value a bar centred across the room left, as wide as it is of
    /// the largest, its value inside it in white (chart-color_funnel's).
    private static func _funnel(_ c: Chart, _ canvas: any Canvas, _ area: Rect, k: Double, theme: DeckTheme,
                                categoryText: (String, Double, Double) -> TextPainter) {
        guard let s = c.series.first else { return }
        let n = c.categories.count
        let labels = c.categories.map { categoryText($0, c.categoryLabelSize ?? c.baseTextSize, .infinity) }
        defer { labels.forEach { $0.dispose() } }
        let left = area.left + (labels.map(\.width).max() ?? 0) + 6 * k
        let plot = Rect.fromLTRB(left, area.top, area.right, area.bottom)
        let slot = plot.height / Double(n)
        let bar = slot / (1 + c.gap)
        let widest = s.values.compactMap { $0 }.map(abs).max() ?? 0
        let fill = Paint()
        fill.style = .fill
        fill.isAntiAlias = true
        fill.color = s.color ?? c.color(series: 0, accents: theme.accents)
        let edge = Paint()
        edge.style = .stroke
        edge.strokeWidth = max(0.25, s.outlineWidth * k)
        for i in 0 ..< n {
            let cy = plot.top + (Double(i) + 0.5) * slot
            labels[i].paint(canvas, Offset(left - 6 * k - labels[i].width, cy - labels[i].height / 2))
            guard widest > 0, let v = s.values[safe: i] ?? nil else { continue }
            let w = abs(v) / widest * plot.width
            let r = Rect.fromLTWH(plot.center.dx - w / 2, cy - bar / 2, w, bar)
            canvas.drawRect(r, fill)
            if let o = s.outline { edge.color = o; canvas.drawRect(r.deflate(edge.strokeWidth / 2), edge) }
            if c.dataLabels {
                let tp = TextPainter(text: TextSpan(text: dataLabel(c, v), style: Flutter.TextStyle(
                    color: Color(0xFFFFFFFF), fontSize: max(3, c.baseTextSize * k),
                    fontFamily: OfficeFonts.substitute(c.font ?? theme.bodyFont), fontFamilyFallback: Self.glyphFallback(c))), textDirection: .ltr)
                tp.layout(minWidth: 0, maxWidth: .infinity)
                tp.paint(canvas, Offset(r.center.dx - tp.width / 2, cy - tp.height / 2))
                tp.dispose()
            }
        }
    }

    private static func _axes(_ c: Chart, _ canvas: any Canvas, _ area0: Rect, frame: Rect, k: Double, theme: DeckTheme,
                              grid: Color, text: (String, Double, Double) -> TextPainter,
                              categoryText: (String, Double, Double) -> TextPainter,
                              valueText: (String, Double, Double) -> TextPainter) {
        let n = c.categories.count
        guard n > 0 else { return }
        if c.funnel {
            _funnel(c, canvas, area0, k: k, theme: theme, categoryText: categoryText)
            return
        }
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
        // (The lines over a combination's columns share the axis — unless
        // they stand on one of their own.)
        if c.secondValueAxis == nil {
            for v in c.lineSeries.flatMap({ $0.values.compactMap { $0 } }) { lo = min(lo, v); hi = max(hi, v) }
        }
        // (A box chart's axis spans every sample, its outliers too.)
        for v in (c.boxes ?? []).joined().joined() { lo = min(lo, v); hi = max(hi, v) }
        // (A waterfall's, its running total and zero, not its steps:
        // chart-waterfall's -6 is no point below zero, and its axis starts
        // at 0 in Excel's print.)
        if c.waterfallTotals != nil {
            lo = 0; hi = 0
            for s in c.waterfallSpans { lo = min(lo, s.from, s.to); hi = max(hi, s.from, s.to) }
        }
        let labelSize = c.valueLabelSize ?? c.baseTextSize
        // (Settled here and captured as constants: the Windows
        // toolchain's optimizer (Swift 6.2.3) fails SIL verification on
        // a tuple `var` that the closures below capture — "Lexical
        // borrows of SILBoxTypes must be of vars or captures" — and the
        // release build dies with exception 3.)
        // (A value axis across the page — a bar chart's — takes a step for
        // each three of its labels' ems, ten at most: its labels stand side
        // by side. bar-chart's 8.2 on 394pt of 18pt labels runs 0 to 10 in
        // twos in PowerPoint's print, where the same data up the page goes
        // by ones; showcase F03's 9.2 on 486pt of 10pt labels runs 0 to 10
        // by ones in Word for Windows', where eight steps made it twos.)
        // (Over a data table the plot is short, and its value axis takes
        // as many steps as its labels have room for, a label's height
        // each: zh-61aaad09's 45pt plot over its table goes 0 to 800000 in
        // 200000s and 0 to 80% in 20s in Word's print, where ten steps
        // stood ours a third of a label apart.)
        let tableSteps: Int? = {
            guard let dt = c.dataTable, !horizontal, c.type != .scatter, !c.type.isPie else { return nil }
            // (On rows of 1.64 em whatever their faces: the steps were read
            // off Word for Mac's prints, and Word for Windows' zh-61aaad09
            // keeps the same four over its taller table.)
            let row = 1.64 * (dt.size ?? c.baseTextSize) * k
            let room = area0.height - Double(c.series.count + c.lineSeries.count + 1) * row
            return max(2, min(10, Int(room / (labelSize * k))))
        }()
        // (A 3-D bar chart's axis has no headroom: zh-b8de3ae2's four, Word's
        // print, run 107,660 to 120,000, 410,306 to 450,000, 130.3M to 140M
        // and 383.3M to 400M — the last 450M with the 5% a flat chart takes.)
        let acrossSteps: Int? = horizontal ? max(2, min(10, Int(area0.width / (3 * labelSize * k)))) : nil
        // (A short chart in a Word document keeps its ticks 15pt apart at least, as many steps as
        // its plot has room for: chart-in-footer's 41pt plot goes 0, 5, 10 and tdf82824's 64pt one
        // 0 to 40 by tens in Word's print, where ours ran 0 to 6 by ones and 0 to 35 by fives;
        // the LO charts' 175pt plots keep ten.)
        let writerSteps: Int? = {
            guard !c.onSlide, !c.onSheet, !c.chartex, !horizontal, c.type != .scatter, !c.type.isPie else { return nil }
            let catLine = 1.22 * (c.categoryLabelSize ?? c.baseTextSize) * k
            var room = area0.height - (0.61 * labelSize * k + catLine + 3.2 * k)
            if c.categoryAxisTitle != nil { room -= (1.22 * (c.axisTitleSize ?? 13.3) + 4) * k }
            return max(2, min(10, Int(room / (15 * k))))
        }()
        var valueScale = c.percent ? (lo: 0.0, hi: 1.0, step: 0.1) : scale(lo, max(hi, c.valueMax ?? hi), intervals: tableSteps ?? acrossSteps ?? writerSteps ?? 10,
                                                                          headroom: c.barView != nil ? 0 : 0.05)
        if c.valueMin != nil || c.valueMax != nil || c.valueStep != nil {
            valueScale = fixedScale(auto: valueScale, min: c.valueMin, max: c.valueMax, step: c.valueStep)
        }
        // An axis the file deletes, with no gridlines to show its steps,
        // runs to the data and a twentieth past it, not rounded out to a
        // step: LIBRE_OFFICE-100610's 3-D bars reach 6 of 6.3 and 14 of
        // 14.7 in PowerPoint's print, where ours stopped at 6 of 7.
        if c.valueAxisDeleted, !c.valueGrid, !c.percent {
            let lo0 = min(0, lo), hi0 = max(0, hi), span = hi0 - lo0
            if span > 0 {
                if c.valueMax == nil { valueScale.hi = hi0 + (hi0 > 0 ? span * 0.05 : 0) }
                if c.valueMin == nil { valueScale.lo = lo0 - (lo0 < 0 ? span * 0.05 : 0) }
            }
        }
        let sc = valueScale
        // Category labels by an axis that crosses above the plot's foot.
        // (Nor on an Office 2016 chart, whose labels stand at the foot:
        // chartex.docx's box-and-whisker categories in Word's print, which
        // this put through its boxes.)
        // (Not where the columns stand on the other axis: chart-
        // testCombinedChartAxis' go below their zero, and its labels stay
        // at the foot of the lines' axis.)
        let atZero = !c.categoryLabelsLow && !c.categoryAxisDeleted && c.type != .scatter && !horizontal && sc.lo < 0
            && c.dataTable == nil && !c.columnsOnRight && !c.chartex
        // The lines' own axis, scaled as the first is, by their values.
        var secondScale: (lo: Double, hi: Double, step: Double)? = nil
        if let second = c.secondValueAxis, !horizontal {
            let all = c.lineSeries.flatMap { $0.values.compactMap { $0 } }
            var s2 = scale(all.min() ?? 0, max(all.max() ?? 1, second.max ?? -Double.infinity), intervals: tableSteps ?? 10)
            if second.min != nil || second.max != nil || second.step != nil {
                s2 = fixedScale(auto: s2, min: second.min, max: second.max, step: second.step)
            }
            secondScale = s2
        }
        var xScale = (lo: 0.0, hi: Double(n), step: 1.0)
        if c.type == .scatter {
            let x = (0 ..< n).map { c.x($0) }
            xScale = scale(x.min() ?? 0, x.max() ?? 1, intervals: 8)
        }
        let xs = xScale
        var area = area0
        // Axis titles take a band at the side and bottom — or, placed by
        // the file, stand there across, taking none: Word sets the text
        // 3 pt in, its glyphs' tops 2.9 down (zh-547fc43c's "亿元" and
        // "万吨", 10 and 10.5 pt, over three charts of its print).
        let titleSize = c.axisTitleSize ?? 13.3
        for (t, placed) in [(c.valueAxisTitle, c.valueAxisTitleAt), (c.categoryAxisTitle, c.categoryAxisTitleAt)] {
            guard let t, let placed else { continue }
            let tp = text(t, placed.size ?? titleSize, .infinity)
            let top = tp.computeLineMetrics().first.map { $0.baseline - $0.ascent } ?? 0
            tp.paint(canvas, Offset(frame.left + placed.at.dx * frame.width + 3 * k, frame.top + placed.at.dy * frame.height + 2.9 * k - top))
            tp.dispose()
        }
        if let t = c.valueAxisTitle, c.valueAxisTitleAt == nil {
            // (No longer than four fifths of the chart in Word: lo-948cd424's category
            // axis title, "In Word the default length of the axis title box is about to
            // 80% of the length of the chart area.", breaks in two in its print.)
            let writerChart = !c.onSlide && !c.onSheet
            let tp = text(t, titleSize, min(horizontal ? area.width : area.height, writerChart ? 0.8 * (horizontal ? frame.width : frame.height) : .infinity))
            if horizontal {
                tp.paint(canvas, Offset(area.center.dx - tp.width / 2, area.bottom - tp.height))
                area = Rect.fromLTRB(area.left, area.top, area.right, area.bottom - tp.height - 4 * k)
            } else if c.valueAxisTitleAcross, writerChart {
                // (Across, in a Word document: lines centred in a block the widest line and ten points wide,
                // from the area's left, its middle over the plot's; they break at 18% of the chart — lo-6b6ece9c's
                // "Horizontal, long axis title which breaks" in three lines, 66.7pt the widest, the plot starting
                // 93.8 from the area's left in Word's print.)
                let across = text(t, titleSize, 0.18 * frame.width)
                let widest = across.computeLineMetrics().map(\.width).max() ?? across.width
                let block = widest + 10 * k
                // (Over the plot's middle, not the area's: the plot's top is half a label under the area's,
                // its foot a label line and 3.2 over it. And the plot starts 3pt past the block.)
                let plotTop = 0.61 * labelSize * k, plotFoot = 1.22 * (c.categoryLabelSize ?? c.baseTextSize) * k + 3.2 * k
                across.paint(canvas, Offset(area.left + block / 2 - across.width / 2, area.center.dy + (plotTop - plotFoot) / 2 - across.height / 2))
                area = Rect.fromLTRB(area.left + block + 3 * k, area.top, area.right, area.bottom)
                across.dispose()
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
        if let t = c.categoryAxisTitle, c.categoryAxisTitleAt == nil {
            let tp = text(t, titleSize, min(horizontal ? area.height : area.width, !c.onSlide && !c.onSheet ? 0.8 * (horizontal ? frame.height : frame.width) : .infinity))
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
        // (Not a plot placed itself over a data table: Word lays that one
        // out as if unplaced — zh-61aaad09's columns, "inner" at 17%/9%,
        // 71% × 70% of a 415 × 137pt frame, stand 164.8-450.6 × 281.9-326.9
        // in its print, the table's rows to the frame's foot under them,
        // where the placed rect ran the plot down over the table.)
        let placed = c.dataTable != nil && c.plotLayoutInner ? nil : c.plotLayout.map {
            Rect.fromLTWH(frame.left + $0.left * frame.width, frame.top + $0.top * frame.height,
                          $0.width * frame.width, $0.height * frame.height)
        }
        if let placed, !c.plotLayoutInner { area = placed }
        // Tick labels: values along one axis, categories (or x values) along the other.
        let ticks = Array(stride(from: sc.lo, through: sc.hi + sc.step * 1e-6, by: sc.step))
        // In the axis's own number format where it has one: "1,600", and
        // an accounting format's "-" for nought. (Its padding is a cell's.)
        func valueLabel(_ v: Double) -> String {
            guard let code = c.valueFormat, !c.percent else { return c.percent ? label(v, percent: true) : tickLabel(v) }
            let shown = NumberFormat.format(v, code, width: 40).text.trimmingWhitespace()
            return shown.isEmpty ? tickLabel(v) : shown
        }
        let valueLabels = ticks.map { valueText(c.valueAxisDeleted ? "" : valueLabel($0), labelSize, .infinity) }
        // The second axis' labels, in its own format ("60.00%").
        let secondTicks = secondScale.map { s2 in Array(stride(from: s2.lo, through: s2.hi + s2.step * 1e-6, by: s2.step)) } ?? []
        let secondLabels: [TextPainter] = secondTicks.map { v in
            let code = c.secondValueAxis?.format
            let shown = code.map { NumberFormat.format(v, $0, width: 40).text.trimmingWhitespace() } ?? label(v, percent: false)
            return valueText(c.secondValueAxis?.deleted == true ? "" : (shown.isEmpty ? label(v, percent: false) : shown), labelSize, .infinity)
        }
        let catSize = c.categoryLabelSize ?? c.baseTextSize
        var catLabels: [TextPainter]
        // Categories too long for their slot even word by word are set
        // aslant, a quarter of a right angle up to the right and ending
        // at their tick, as PowerPoint sets them (aascu 5864's country
        // names); we had broken them inside words.
        var aslant = false
        var slant = Double.pi / 4
        // Turned clockwise (`rot` above zero): from the tick down to the
        // right, where turned the other way it ends at the tick.
        var clockwise = false
        // Only every so many labels shown (one, the first, of each run).
        var every = 1
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
                    clockwise = turn < 0
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
                    // Slots thinner than a line even turned: upright, one
                    // label to each font size of room (47813's 720
                    // categories in 0.66 pt slots, 1, 17, 33… at 10 pt in
                    // Excel's print; ours ran into one black band).
                    if slot < catSize * k {
                        slant = .pi / 2
                        every = Int((catSize * k / slot).rounded(.up))
                    }
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
        // against charts with none. Those are 2007-style charts: a
        // 2013-style chart's labels stand where they would without ticks
        // (chartex's stock chart printed by Word with its axes' ticks
        // out and none: not a label moves).
        let ticksPush = !c.styled2013
        // (A 2013-style chart in a Word document: its plot and labels sit by their own insets,
        // measured on ten LibreOffice test charts against Word for Windows' prints.)
        let word = !c.onSlide && !c.onSheet && !c.chartex && c.styled2013
        // (Its foot as well where nothing but the category labels stands there: a legend or
        // an axis title under the plot takes the foot's room its own way.)
        let wordFoot = word && !(c.legend && c.legendPosition == "b") && c.categoryAxisTitle == nil && c.categoryAxisTitleAt == nil
        let besideOut = ticksPush && (horizontal ? c.categoryTicksOut : c.valueTicksOut) ? (horizontal ? 8.8 : 5.6) * k : 0
        let belowOut = ticksPush && (horizontal ? c.valueTicksOut : c.categoryTicksOut) ? 3.7 * k : 0
        if horizontal {
            // (A 2007-style slide chart's plot stands 1.9 pt further right
            // and 3.8 pt higher at the bottom: bar-chart's in PowerPoint's
            // print, its labels where ours were.)
            let old2007 = c.plainText && !c.styled2013 && c.officeStyled
            let left = (catLabels.map(\.width).max() ?? 0) + (old2007 ? 7.9 : 6) * k + besideOut
            // (A 2013-style chart's top stands off the title as a column
            // chart's does, half a label line, though no label overhangs
            // it: 61745's bar chart's plot is 17 pt under its title's
            // baseline in Word's print, as its column chart's is. A
            // 2007-style one's starts 7 pt down: bar-chart's, at 156.4
            // in PowerPoint's print.)
            plot = Rect.fromLTRB(area.left + left, area.top + (c.styled2013 ? lineH / 2 : (old2007 ? 7 : 2) * k),
                                 area.right - (valueLabels.last?.width ?? 0) / 2,
                                 area.bottom - lineH - (old2007 ? 7.8 : 4) * k - belowOut)
        } else {
            // (A 2007-style chart's plot starts 2.6 pt further off its
            // value labels — line- and scatter-chart's at 152.3, the
            // labels where ours are.)
            var left = (valueLabels.map(\.width).max() ?? 0) + (c.styled2013 ? 8.5 : 11.1) * k + besideOut - (word ? 2.5 * k : 0)
            let tallest = aslant ? (catLabels.map(drop).max() ?? lineH) : (catLabels.map(\.height).max() ?? lineH)
            // (Labels by an axis above the foot take no room below it.)
            // (A `cx:` chart's on a sheet 2.53 pt higher, its labels with
            // it: their baselines 7.98 pt over the frame's foot in Excel's
            // prints of histograms, Pareto charts and waterfalls, ours 5.45.
            // Not a box plot's, already higher than Excel's.)
            let bottom = (atZero ? 4 * k : tallest + 7.6 * k + belowOut) - (wordFoot ? 4.4 * k : 0) + (c.onSheet && c.chartex && c.boxes == nil ? 2.53 * k / 0.75 : 0)
            // Labels centred on the plot's edges (an area's first and last
            // categories, a scatter's end ticks) need half their width free.
            let edges = c.type == .scatter || c.type == .area
            // (2.1 on a newer chart on a slide: chart-slide-bg's plot ends
            // 11.1 pt inside its frame in PowerPoint's print, its four
            // categories 151.3 apart, ours 150.9. Not against a legend
            // beside it: tdf149985's, +0.11 so.)
            let legendBeside = c.legend && c.legendBox == nil && ["r", "l", "tr"].contains(c.legendPosition)
            var right = edges ? (catLabels.last?.width ?? 0) / 2 : ((c.onSlide || word) && c.styled2013 && !legendBeside ? 2.1 : 4) * k
            if edges { left = max(left, (catLabels.first?.width ?? 0) / 2); right = max(right, 4 * k) }
            // (The second axis' labels take a band at the right, as the
            // first's do at the left.)
            if !secondLabels.isEmpty { right = max(right, (secondLabels.map(\.width).max() ?? 0) + 10 * k) }
            // (On a sheet the plot stands 1.72 pt further in at the left,
            // its labels with it, and 1.25 at the right: Excel's prints of
            // 40 column, line and scatter charts, alike at 286 to 800 pt
            // wide. A 2007-style chart's left edge was where Excel's is,
            // chart-chart's and fdo54361's labels. Not a chartex chart's:
            // its own.)
            if c.onSheet && !c.chartex {
                if c.styled2013 { left += 1.72 * k / 0.75 }
                if secondLabels.isEmpty { right += 1.25 * k / 0.75 }
            }
            // (A 2013-style chart on a slide starts 1.5 pt lower:
            // chart-slide-bg's top gridline at 100.5 in PowerPoint's
            // print, where ours stood at 99; its three like charts and
            // tdf149985's the same. A titled 2007-style one, a point
            // lower: line- and scatter-chart's top gridline at 161.35 in
            // its print, ours at 160.43. Cooper's untitled ones stand
            // 3.8 pt higher than ours instead, not followed: one deck.)
            // (On a sheet a titled chart's plot starts 2.57 pt lower, under
            // a title where ours is, and an untitled one 1.25 higher, 1.62
            // in a 2007-style chart: Excel's prints of 70 column, line and
            // scatter charts, their feet where ours are. A titled `cx:`
            // chart's, 0.45: four histograms and box plots, 31.8 pt under
            // the frame's top.)
            let pt = k / 0.75
            let titled = !(c.title ?? "").isEmpty && c.titleAt == nil
            let lower = c.onSlide ? (c.styled2013 ? 1.5 : c.title != nil ? 1.0 : 0) * k
                : c.onSheet ? (titled ? (c.chartex ? 0.45 : c.styled2013 ? 2.57 : 2.05) : (c.styled2013 ? -1.25 : -1.62)) * pt : 0
            plot = Rect.fromLTRB(area.left + left, area.top + lineH / 2 + lower, area.right - right, area.bottom - bottom)
        }
        // A data table takes the foot of the frame, a row for the
        // categories and one for each series, and the room before the
        // plot that its keys and names need. (Word's print of
        // zh-2a241df1's two charts, 10pt: rows 16.4pt, the categories'
        // 16.1, the last 4.9pt over the frame's foot; the names' column
        // 17pt in from its left, the key 3.2 into it, 19.2 long, the name
        // 2 after it and 2.5 clear of the plot.)
        var table: (top: Double, rows: [Double], left: Double, size: Double)? = nil
        if let dt = c.dataTable, !horizontal, c.type != .scatter, !c.type.isPie {
            let size = dt.size ?? c.baseTextSize
            let names = (c.series + c.lineSeries).map { text($0.name, size, .infinity) }
            let square = dt.squareKeys && c.type != .line && c.lineSeries.isEmpty
            let e = size / 10 * k, u = c.onSheet ? k / 0.75 : k
            let column = (dt.keys ? (square ? 11.4 * e : 24.4 * u) : 3.2 * u) + (names.map(\.width).max() ?? 0) + (square ? 2.4 * e : 2.5 * u)
            for t in names { t.dispose() }
            // (Over a legend at the foot, the table stops where the
            // legend's band begins: chart-ChartDataTable's in Excel's print.)
            // (A manual plot layout over a table: Word reads its width
            // alone — the plot w of the frame wide — and every side stands
            // 5pt further out: the plot 6.7 under the frame's top, the
            // table's foot on the frame's, its left edge 12 in. Lab on
            // zh-61aaad09's chart (Windows 01QbbApP): its x, y and h moved
            // nothing; with no layout the sides are as below.)
            let manual = c.plotLayout
            let foot = c.legend && c.legendBox == nil && c.legendPosition == "b" ? area.bottom : frame.bottom - (manual != nil ? 0 : 4.9 * k)
            // (On a sheet, in points: Excel's print of chart-DataTable-
            // Multiple…'s table 4.2 pt further in than 17 px.)
            let left = max(plot.left, frame.left + (manual != nil ? 12 : 17) * (c.onSheet ? k / 0.75 : k) + column)
            let right = manual.map { min(plot.right + 5 * k, left + $0.width * frame.width) } ?? plot.right
            let rows = Self._tableRows(c, size: size, k: k, slot: (right - left) / Double(max(1, n)), text: text)
            let top = foot - rows.reduce(0, +)
            // (Its plot's top 11.1pt under the frame's in both, where ours
            // stood half a label line under the area's, 4.3 lower: so
            // measured only with a table.)
            // (On a sheet too, 11.1 pt: chart-ChartDataTable's in Excel's
            // print, where 11.1 px stood 2.6 pt high.)
            let head = c.title?.isEmpty == false ? plot.top : frame.top + (manual != nil ? 6.7 : 11.1) * (c.onSheet ? k / 0.75 : k)
            plot = Rect.fromLTRB(left, head, right, top)
            table = (top, rows, plot.left - column, size)
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
                // Each bar as deep as it is wide, in a box `gapDepth` more:
                // aascu 5864's one series, its bars 11.2 pt wide, stand in a
                // box 28 deep, its category; LIBRE_OFFICE-100610's four
                // abreast with no gap, 46.5 wide, are 46.5 deep in its print
                // (15.5 across, 12 up), where a category's depth made them
                // four times that.
                let slot = (horizontal ? plot.height : plot.width) / Double(max(1, n))
                let lanes = c.stacked ? 1.0 : Double(max(1, c.series.count))
                let pitch = c.stacked ? 0 : 1 - c.overlapFraction
                let bar = slot / (1 + (lanes - 1) * pitch + c.gap)
                box = depthAt(bar * (1 + v.gapDepth) * v.depth)
                plot = Rect.fromLTRB(whole.left, whole.top + box.dy, whole.right - box.dx, whole.bottom)
            }
        }
        guard plot.width > 4, plot.height > 4 else {
            for t in valueLabels + catLabels + secondLabels { t.dispose() }
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
        // A 2007-style chart on a slide, as Office 2007 draws one the file
        // leaves unstyled: its gridlines, both axes' lines and their
        // outward ticks, 5.7 pt long, all 0.75 pt of #868686 (line-chart's
        // print), where a newer chart's gridlines are 15% grey and its axes
        // bare.
        let classic = c.onSlide && !c.styled2013 && c.officeStyled && box == .zero
        let gridPaint = Paint()
        gridPaint.style = .stroke
        gridPaint.strokeWidth = max(0.5, (c.gridWidth ?? 0.75) * k)
        gridPaint.color = classic && c.gridColor == nil ? Color(0xFF868686) : grid
        let axisPaint = Paint()
        axisPaint.style = .stroke
        axisPaint.strokeWidth = max(0.5, 0.75 * k)
        axisPaint.color = Color(0xFF868686)
        let tick = 5.7 * k
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
                // (Where the plot's foot left them: a 2007-style chart's
                // plot ends 7.8 pt over them, and they stay at the frame's
                // foot — bar-chart's at 401.4 in PowerPoint's print, where
                // ours had risen with the plot to 397.8.)
                let under = (c.plainText && !c.styled2013 && c.officeStyled ? 7.8 : 4) * k
                tp.paint(canvas, Offset(p - tp.width / 2, plot.bottom + under + belowOut))
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
                let further = word ? 0 : c.styled2013 ? 2.5 * k : 2.6 * k
                // (A 2007-style chart's stand with their middles 1.45 pt
                // above their lines, line- and scatter-chart's 18 pt
                // labels. A newer chart's are measured so too, and came
                // out no nearer raised.)
                // (A newer one's on a slide, 1.25 pt above theirs: its plot
                // stands 1.5 pt lower there, and chart-slide-bg's labels
                // print 1.1 to 1.5 above where that put them.)
                let lift = c.styled2013 ? (c.onSlide ? 1.25 * k : 0) : 1.45 * k
                tp.paint(canvas, Offset(plot.left - 8.5 * k - besideOut - further - tp.width, p - tp.height / 2 - lift))
            }
        }
        // The second axis' labels, beside the plot's right edge.
        func vpos2(_ v: Double) -> Double {
            guard let s2 = secondScale else { return vpos(v) }
            return plot.bottom - (v - s2.lo) / (s2.hi - s2.lo) * plot.height
        }
        // (Raised as the first axis' are: Word's print of zh-2a241df1 sets
        // "60.00%" on the line of "500000", where ours stood 1.5pt lower.)
        let lift2 = c.styled2013 ? 0 : 1.45 * k
        for (i, v) in secondTicks.enumerated() {
            let tp = secondLabels[i]
            tp.paint(canvas, Offset(plot.right + 6 * k, vpos2(v) - tp.height / 2 - lift2))
        }
        for t in secondLabels { t.dispose() }
        // The category axis line, at zero.
        let zero = vpos(max(sc.lo, min(sc.hi, 0)))
        if classic {
            // The category ticks: at a scatter's x steps, else between
            // the categories and at both ends.
            var cats: [Double] = []
            if c.type == .scatter {
                for v in stride(from: xs.lo, through: xs.hi + xs.step / 2, by: xs.step) {
                    cats.append(plot.left + (v - xs.lo) / (xs.hi - xs.lo) * plot.width)
                }
            } else {
                let m = Double(max(1, n))
                for i in 0 ... max(1, n) {
                    let t = Double(i) / m
                    cats.append(horizontal ? plot.bottom - t * plot.height : plot.left + t * plot.width)
                }
            }
            if horizontal {
                if c.valueLine, !c.valueAxisDeleted {
                    canvas.drawLine(Offset(plot.left, plot.bottom), Offset(plot.right, plot.bottom), axisPaint)
                    if c.valueTicksOut { for v in ticks { canvas.drawLine(Offset(vpos(v), plot.bottom), Offset(vpos(v), plot.bottom + tick), axisPaint) } }
                }
                if c.categoryLine, !c.categoryAxisDeleted, c.categoryTicksOut {
                    for y in cats { canvas.drawLine(Offset(zero - tick, y), Offset(zero, y), axisPaint) }
                }
            } else {
                if c.valueLine, !c.valueAxisDeleted {
                    canvas.drawLine(Offset(plot.left, plot.top), Offset(plot.left, plot.bottom), axisPaint)
                    if c.valueTicksOut { for v in ticks { canvas.drawLine(Offset(plot.left - tick, vpos(v)), Offset(plot.left, vpos(v)), axisPaint) } }
                }
                if c.categoryLine, !c.categoryAxisDeleted, c.categoryTicksOut {
                    for x in cats { canvas.drawLine(Offset(x, zero), Offset(x, zero + tick), axisPaint) }
                }
            }
        }
        if c.type == .scatter {
            let xTicks = Array(stride(from: xs.lo, through: xs.hi + xs.step / 2, by: xs.step))
            for (i, v) in xTicks.enumerated() {
                let x = plot.left + (v - xs.lo) / (xs.hi - xs.lo) * plot.width
                // (Where the X axis has them: scatter-chart's has none.)
                if c.scatterXGrid { canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), gridPaint) }
                // (A 2007-style one's 7.6 pt under, as a line chart's:
                // scatter-chart's printed 3.5 pt lower than 4 put them.)
                let under = (classic ? 7.6 : 4) * k
                if i < catLabels.count { catLabels[i].paint(canvas, Offset(x - catLabels[i].width / 2, plot.bottom + under + belowOut)) }
            }
        } else if horizontal {
            // (Not where the file deletes the axis: LIBRE_OFFICE-100610's.)
            if !c.categoryAxisDeleted { canvas.drawLine(Offset(zero, plot.top), Offset(zero, plot.bottom), gridPaint) }
            if box != .zero, c.barView?.walled != false {
                // The box's edges at zero: its back, and across its top.
                canvas.drawLine(Offset(zero, plot.top), Offset(zero + box.dx, plot.top - box.dy), gridPaint)
                canvas.drawLine(Offset(zero, plot.bottom), Offset(zero + box.dx, plot.bottom - box.dy), gridPaint)
                canvas.drawLine(Offset(zero + box.dx, plot.top - box.dy), Offset(zero + box.dx, plot.bottom - box.dy), gridPaint)
            }
            let slot = plot.height / Double(n)
            for (i, tp) in catLabels.enumerated() {
                // Category 1 at the bottom, as PowerPoint draws a bar chart.
                // (A 2007-style chart's stand 1.45 pt above their bands'
                // middles, as its value labels above their lines.)
                let cy = plot.bottom - (Double(i) + 0.5) * slot - (c.plainText && !c.styled2013 && c.officeStyled ? 1.45 * k : 0)
                tp.paint(canvas, Offset(plot.left - 8.5 * k - besideOut - tp.width, cy - tp.height / 2))
            }
        } else {
            if !c.categoryAxisDeleted { canvas.drawLine(Offset(plot.left, zero), Offset(plot.right, zero), gridPaint) }
            if box != .zero, c.barView?.walled != false {
                // The floor's other edges: its sides and its back.
                canvas.drawLine(Offset(plot.left, zero), Offset(plot.left + box.dx, zero - box.dy), gridPaint)
                canvas.drawLine(Offset(plot.right, zero), Offset(plot.right + box.dx, zero - box.dy), gridPaint)
                canvas.drawLine(Offset(plot.left + box.dx, zero - box.dy), Offset(plot.right + box.dx, zero - box.dy), gridPaint)
            }
            let slot = plot.width / Double(n)
            let foot = atZero ? zero : plot.bottom
            for (i, tp) in catLabels.enumerated() where table == nil && i % every == 0 {
                let cx = c.type == .area && n > 1 ? plot.left + Double(i) * plot.width / Double(n - 1) : plot.left + (Double(i) + 0.5) * slot
                if aslant {
                    // Its end's middle at the tick, the rest down to the left
                    // — or, turned clockwise, its start's middle there and
                    // the rest down to the right (chart-chart-text-can-
                    // overlap's 45°).
                    canvas.save()
                    canvas.translate(cx, foot + (wordFoot ? 5.7 : 7.6) * k + belowOut - Self._wordLabelRise(c, catSize) * k)
                    canvas.rotate(clockwise ? slant : -slant)
                    tp.paint(canvas, Offset(clockwise ? 0 : -tp.width, -tp.height / 2))
                    canvas.restore()
                } else {
                    tp.paint(canvas, Offset(cx - tp.width / 2, foot + (wordFoot ? 5.7 : 7.6) * k + belowOut - Self._wordLabelRise(c, catSize) * k))
                }
            }
        }
        for t in valueLabels + catLabels { t.dispose() }
        if let table, let dt = c.dataTable {
            Self._dataTable(c, dt, canvas, plot: plot, top: table.top, rows: table.rows, left: table.left, size: table.size,
                            n: n, k: k, theme: theme, text: text)
        }

        var labels: [(String, Offset, Int)] = []
        /// A bar's label moved as the file says (`ChartSeries.labelNudges`,
        /// fractions of the frame).
        func nudge(_ j: Int, _ i: Int) -> Offset {
            c.series[safe: j]?.labelNudges[i].map { Offset($0.dx * frame.width, $0.dy * frame.height) } ?? .zero
        }
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
        // A combination's lines, over its columns or its own lines: each
        // through its categories' middles, with its marks, on the second
        // value axis where it has one.
        func paintOverlayLines() {
            let slot = plot.width / Double(max(1, n))
            for (j, l) in c.lineSeries.enumerated() {
                let colour = l.color ?? c.color(series: c.series.count + j, accents: theme.accents)
                func at(_ i: Int) -> Offset? {
                    guard let v = l.values[safe: i] ?? nil else { return nil }
                    return Offset(plot.left + (Double(i) + 0.5) * slot, vpos2(v))
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
                // Its values above its points, in its labels' look,
                // single ones moved where the file moves them: each
                // label's foot 6.5 pt over its point (zh-547fc43c's 10 pt
                // rates in Word's print; centred 9 pt over, as a line
                // chart's, they stood 4 pt low).
                if l.valueLabels {
                    for i in 0 ..< n {
                        guard let q = at(i), let v = l.values[safe: i] ?? nil else { continue }
                        // (In the line's own format, not the columns': zh-b8de3ae2's
                        // rates are General, 92.05 in Word's print, under columns
                        // in "#,##0" that made ours "92".)
                        let code = l.labelCode ?? l.format
                        let shown = code.map { NumberFormat.format(v, $0, width: 40).text.trimmingWhitespace() } ?? ""
                        let tp = TextPainter(text: TextSpan(text: shown.isEmpty ? label(v, percent: false) : shown, style: Flutter.TextStyle(
                            color: l.labelColor ?? c.textColor ?? (c.plainText ? theme.text : _mix(theme.text, theme.background, 0.65)),
                            fontSize: max(3, (l.labelSize ?? c.baseTextSize) * k), fontWeight: l.labelBold ? .bold : .normal,
                            fontFamily: OfficeFonts.substitute(c.font ?? theme.bodyFont), fontFamilyFallback: Self.glyphFallback(c))), textDirection: .ltr)
                        tp.layout(minWidth: 0, maxWidth: .infinity)
                        let nudge = l.labelNudges[i].map { Offset($0.dx * frame.width, $0.dy * frame.height) } ?? .zero
                        // (To the right where the file gives no place, a line's
                        // default: zh-b8de3ae2's rates over its columns, no
                        // dLblPos, in Word for Windows' print — 9pt, the text's
                        // origin 8.45 right of its point and its baseline 3.03
                        // under it; ours stood over the point, 14 high and 21
                        // left.)
                        if (l.labelPos ?? "r") == "r", let line = tp.computeLineMetrics().first {
                            tp.paint(canvas, Offset(q.dx + 8.45 * k + nudge.dx, q.dy + 3.03 / 9 * max(3, (l.labelSize ?? c.baseTextSize) * k) - line.baseline + nudge.dy))
                        } else {
                            tp.paint(canvas, Offset(q.dx - tp.width / 2 + nudge.dx, q.dy - 6.5 * k - tp.height + nudge.dy))
                        }
                        tp.dispose()
                    }
                }
            }
        }
        switch c.type {
        case .column where c.boxes != nil:
            Self._boxes(c, canvas, plot, k: k, theme: theme, vpos: vpos)
        case .column where c.waterfallTotals != nil && !horizontal:
            // A waterfall: each column from the running total before it to
            // the one after, a total from zero; rising in the first colour,
            // falling in the second, totals in the third; its value over a
            // rise and under a fall; and, where it says, a thin rule from
            // each column's end to the next one's start.
            let slot = plot.width / Double(n)
            let bar = slot / (1 + c.gap)
            let spans = c.waterfallSpans
            let totals = c.waterfallTotals ?? []
            for (i, s) in spans.enumerated() {
                let x = plot.left + Double(i) * slot + (slot - bar) / 2
                let top = vpos(max(s.from, s.to)), foot = vpos(min(s.from, s.to))
                fill.color = c.color(series: totals.contains(i) ? 2 : s.to >= s.from ? 0 : 1, accents: theme.accents)
                canvas.drawRect(Rect.fromLTRB(x, top, x + bar, max(top + 0.5, foot)), fill)
                if c.dataLabels, let v = c.series.first?.values[safe: i] ?? nil {
                    labels.append((dataLabel(c, v), Offset(x + bar / 2, s.to >= s.from ? top - 9 * k : foot + 9 * k), 0))
                }
                if c.waterfallConnectors, i + 1 < spans.count {
                    let line = Paint()
                    line.style = .stroke
                    line.strokeWidth = max(0.25, 0.75 * k)
                    line.color = gridPaint.color
                    canvas.drawLine(Offset(x + bar, vpos(s.to)), Offset(x + slot, vpos(s.to)), line)
                }
            }
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
                    // A bar of the first series in its own colour (`c:dPt`),
                    // as chart-DataTable-Multiple…'s six bars are.
                    fill.color = c.variedPoints ? c.pointColor(i, accents: theme.accents)
                        : (j == 0 ? c.pointColors[i] : nil) ?? c.color(series: j, accents: theme.accents)
                    let p0 = vpos(a), p1 = vpos(b)
                    var rect: Rect
                    if horizontal {
                        let top = centre + group / 2 - Double(j) * step - bar
                        rect = Rect.fromLTRB(min(p0, p1), top, max(p0, p1), top + bar)
                        labels.append((dataLabel(c, raw), Offset(c.stacked ? rect.center.dx : max(p0, p1) + 3 * k, rect.center.dy) + nudge(j, i), j))
                    } else {
                        let left = centre - group / 2 + Double(j) * step
                        rect = Rect.fromLTRB(left, min(p0, p1), left + bar, max(p0, p1))
                        // Past the bar's end, as far off as the label is
                        // large: under a bar that runs down from the axis.
                        // (aascu 5864's 18 pt labels stand 14.3 pt over a
                        // bar's top and 16.9 under a falling one's foot in
                        // PowerPoint's print, 0.79 and 0.94 of their size;
                        // ours stood 8 over every bar, the −1.4 and −2.1
                        // on the axis line.)
                        let size = c.series[j].labelSize ?? c.baseTextSize
                        // (In a document too, under a falling bar's foot: zh-b8de3ae2's
                        // chart 10, every column below zero, has "-21,376,664" and
                        // "-10,160,557" under their columns' feet in Word's print,
                        // where ours set them all over the axis line.)
                        let off = c.onSlide ? (p1 > p0 ? 0.94 : -0.79) * size * k : p1 > p0 ? 0.94 * size * k : -8 * k
                        labels.append((dataLabel(c, raw), Offset(rect.center.dx, c.stacked ? rect.center.dy
                            : (off > 0 ? max(p0, p1) : min(p0, p1)) + off) + nudge(j, i), j))
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
            if !horizontal { paintOverlayLines() }
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
                    // (An area's stand in the middle of the area under the point, over the axis' foot
                    // or the series below: lo-60124a3f's 5 and 6 over 4.4 to 6.2 in Word's print.)
                    let y = c.type == .area ? (vpos(v) + min(vpos(c.stacked && j > 0 ? (tops[j - 1][i] ?? 0) : 0), plot.bottom)) / 2 : vpos(v) - 9 * k
                    labels.append((dataLabel(c, raw), Offset(xAt(i), y), j))
                }
                if c.stacked { for i in 0 ..< n { base[i] = row[i] ?? base[i] } }
                tops.append(row)
            }
            // A stock chart's high-low lines, under its series: each
            // category's highest value to its lowest.
            if let h = c.highLowLines, c.type == .line {
                let p = Paint()
                p.style = .stroke
                p.strokeWidth = max(0.5, h.width * k)
                p.color = h.color ?? theme.text
                for i in 0 ..< n {
                    let vs = (0 ..< s).compactMap { tops[$0][safe: i] ?? nil }
                    guard let lo = vs.min(), let hi = vs.max(), hi > lo else { continue }
                    canvas.drawLine(Offset(xAt(i), vpos(hi)), Offset(xAt(i), vpos(lo)), p)
                }
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
                } else if c.series[j].lineHidden {
                    // (Its line none: its marks alone, where it has any.)
                    for i in 0 ..< n {
                        guard let v = tops[j][i] else { continue }
                        Self._mark(c.series[j], at: Offset(xAt(i), vpos(v)), k: k, colour: color, canvas)
                    }
                } else {
                    let p = Paint()
                    p.style = .stroke
                    p.isAntiAlias = true
                    p.strokeWidth = max(1, 2.25 * k)
                    p.strokeCap = .round
                    p.strokeJoin = .round
                    p.color = c.lineColor(series: j, accents: theme.accents)
                    let path = Path()
                    var pen = false
                    for i in 0 ..< n {
                        guard let v = tops[j][i] else { pen = false; continue }
                        if pen { path.lineTo(xAt(i), vpos(v)) } else { path.moveTo(xAt(i), vpos(v)); pen = true }
                    }
                    canvas.drawPath(path, p)
                    // Its marks over its line, where it names them
                    // (chart-add_series_secondary_axis' circles).
                    if c.type == .line {
                        for i in 0 ..< n where !c.series[j].unmarked.contains(i) {
                            guard let v = tops[j][i] else { continue }
                            Self._mark(c.series[j], at: Offset(xAt(i), vpos(v)), k: k, colour: color, canvas)
                        }
                    }
                }
            }
            if c.type == .line, !horizontal { paintOverlayLines() }
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
                    if c.onSlide, !c.styled2013, c.officeStyled {
                        let rim = Paint()
                        rim.style = .stroke
                        rim.isAntiAlias = true
                        rim.strokeWidth = max(0.25, 0.75 * k)
                        rim.color = c.lineColor(series: j, accents: theme.accents)
                        canvas.drawCircle(Offset(x, vpos(v)), max(1.5, 2.5 * k), rim)
                    }
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
                fontWeight: l.series.labelBold ? .bold : .normal, fontFamily: OfficeFonts.substitute(c.font ?? theme.bodyFont), fontFamilyFallback: Self.glyphFallback(c))),
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
                            fontFamily: OfficeFonts.substitute(c.font ?? theme.bodyFont), fontFamilyFallback: Self.glyphFallback(c))), textDirection: .ltr)
                        t.layout(minWidth: 0, maxWidth: .infinity)
                        return t
                    }()
                let dx = horizontal && !c.stacked ? 0 : tp.width / 2
                let rise = horizontal ? 0 : Self._wordLabelRise(c, ser.labelSize ?? c.baseTextSize) * k
                tp.paint(canvas, Offset(at.dx - dx, at.dy - tp.height / 2 - rise))
                tp.dispose()
            }
        }
    }

    /// How much higher, in points, Word stands a `c:` chart's column value
    /// labels and category labels than ours when its text is marked
    /// Chinese, Japanese or Korean (`eastAsianText`): zh-547fc43c's
    /// (lang="zh-CN") print them 2.4 to 2.8 pt over ours at 10 pt Calibri
    /// and 3.2 over at 10.5 pt 宋体, where chartex's (no lang) stand where
    /// ours do. Word sets 宋体, 黑体 and Calibri there alike (the Windows
    /// box's lab, the chart's faces swapped, its lang kept); the larger
    /// step for a square East Asian face is ours, its digits drawn in
    /// Liberation Sans where Calibri's are in Carlito. Not a chartex
    /// chart, and not on a slide.
    static func _wordLabelRise(_ c: Chart, _ size: Double) -> Double {
        guard !c.onSlide, !c.chartex, c.eastAsianText else { return 0 }
        let f = c.font?.trimmingWhitespace().lowercased() ?? ""
        let square = ["宋体", "simsun", "新宋体", "nsimsun", "黑体", "simhei", "楷体", "kaiti", "仿宋", "fangsong",
                      "細明體", "mingliu", "新細明體", "pmingliu"]
        return (square.contains(f) ? 0.3 : 0.25) * size
    }

    private static func _pie(_ c: Chart, _ canvas: any Canvas, _ area: Rect, k: Double, theme: DeckTheme,
                             text: (String, Double, Double) -> TextPainter, frame: Rect? = nil, ink: Color? = nil) {
        if c.ofPie != nil, c.type == .pie {
            _ofPie(c, canvas, area, k: k, theme: theme, frame: frame ?? area, ink: ink ?? theme.text)
            return
        }
        let values = c.series[0].values.map { max(0, $0 ?? 0) }
        let sum = values.reduce(0, +)
        guard sum > 0 else { return }
        // (0.97 of the room: pie-chart's, under a title beside a legend,
        // is 131 pt in PowerPoint's print, and chart_pt_color_bg1's bare
        // ring 159 — both that share of the frame inside its margin.)
        var radius = min(area.width, area.height) / 2 * 0.97
        // On a sheet, a line of the labels' less each side where they
        // stand round the pie: Excel's prints of five labelled pies are
        // 8.5 to 17 pt smaller a side than ours were, the unlabelled
        // ones as ours (chart-tdf133376, -tdf134978, -tdfPieNumFormat).
        // (Not where the file places the plot itself: the pie fills
        // that, chart-incorrect_label_position's and -piechart_outside's.)
        if c.onSheet, c.pieLabelsAround, c.plotLayout == nil {
            radius = max(radius / 2, radius - 1.25 * (c.series[0].labelSize ?? c.baseTextSize) * k)
        }
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
        // (No rims in a 2007-style chart on a slide: pie-chart's slices
        // meet edge to edge in PowerPoint's print, fills alone.)
        if c.onSlide, !c.styled2013, c.officeStyled { edge.color = Color(0x00000000) }
        // The series' own outline round each slice where it gives one
        // (chart-tdf161607's ring ruled 2.25 pt green).
        if let line = c.series[0].outline {
            edge.color = line
            edge.strokeWidth = max(0.25, c.series[0].outlineWidth * k)
        }
        var labels: [(String, Offset, Color)] = []
        var placed: [(index: Int, mid: Double, value: Double, color: Color)] = []
        // A doughnut's wedges are rings: the hole shows what is behind.
        let hole = c.type == .doughnut ? radius * Double(max(0, min(90, c.holeSize))) / 100 : 0
        let inner = Rect.fromCircle(center: centre, radius: hole)
        // (A doughnut of several series is a ring for each, the first
        // innermost, sharing the band between the hole and the rim: the
        // Word showcase's F07, three thin rings round a 65% hole in Word's
        // print, where ours drew the first series alone.)
        if c.type == .doughnut, c.series.count > 1, hole > 0 {
            let band = (radius - hole) / Double(c.series.count)
            for (j, ser) in c.series.enumerated() {
                let vals = ser.values.map { max(0, $0 ?? 0) }
                let total = vals.reduce(0, +)
                guard total > 0 else { continue }
                let outer = Rect.fromCircle(center: centre, radius: hole + band * Double(j + 1))
                let within = Rect.fromCircle(center: centre, radius: hole + band * Double(j))
                var a = angle
                for (i, v) in vals.enumerated() where v > 0 {
                    let sweep = v / total * 2 * .pi
                    fill.color = c.pointColor(i, accents: theme.accents)
                    let ring = Path()
                    ring.arcTo(outer, a, sweep, true)
                    ring.arcTo(within, a + sweep, -sweep, false)
                    ring.close()
                    canvas.drawPath(ring, fill)
                    canvas.drawPath(ring, edge)
                    a += sweep
                }
            }
            return
        }
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
                    fontFamily: OfficeFonts.substitute(c.font ?? theme.bodyFont), fontFamilyFallback: Self.glyphFallback(c))), textDirection: .ltr)
                tp.layout(minWidth: 0, maxWidth: .infinity)
                tp.paint(canvas, Offset(at.dx - tp.width / 2, at.dy - tp.height / 2))
                tp.dispose()
            }
        }
    }
}

extension ChartPainter {
    /// A sunburst, as Word prints chartex's: the hole and each level a
    /// ring as wide, the circle 220 pt across where the plot left 222
    /// under the title — its top 1.35 above the plot's, its foot 3.15
    /// above it; the first level innermost, each node's wedge its share
    /// of its parent's, the larger first clockwise from twelve o'clock,
    /// in its branch's accent and ruled in the background at 0.75 pt.
    /// A name runs along its wedge's radius, never upside down, in
    /// white 8.4 pt broken to four fifths of the ring, its lines'
    /// middle 2.1 pt under the ring's — where the wedge's inner arc
    /// holds its lines and 3 pt more (Leaf 3's 16.2 pt does a line, Leaf
    /// 2's 10.8 and Leaf 10's 21.7, two lines, do not).
    static func _sunburst(_ c: Chart, _ nodes: [Chart.SunburstNode], _ canvas: any Canvas, _ area: Rect, k: Double, theme: DeckTheme,
                          text: (String, Double, Double) -> TextPainter) {
        func depth(_ n: [Chart.SunburstNode]) -> Int { n.isEmpty ? 0 : 1 + (n.map { depth($0.children) }.max() ?? 0) }
        let top = area.top - 1.35 * k, bottom = area.bottom - 3.15 * k
        let radius = min(area.width, bottom - top) / 2
        guard radius > 0 else { return }
        let centre = Offset(area.center.dx, (top + bottom) / 2)
        let ring = radius / Double(depth(nodes) + 1)
        let fill = Paint()
        fill.style = .fill
        fill.isAntiAlias = true
        let edge = Paint()
        edge.style = .stroke
        edge.isAntiAlias = true
        edge.strokeWidth = max(0.25, 0.75 * k)
        edge.color = theme.background
        var labels: [(name: String, level: Int, from: Double, sweep: Double)] = []
        func draw(_ nodes: [Chart.SunburstNode], level: Int, from: Double, sweep: Double, total: Double, color: Int?) {
            guard total > 0 else { return }
            var angle = from
            for n in nodes where n.value > 0 {
                let s = n.value / total * sweep
                let accent = color ?? n.color
                fill.color = theme.accents.isEmpty ? Color(0xFF808080) : theme.accents[accent % theme.accents.count]
                let inner = ring * Double(level + 1), outer = inner + ring
                let wedge = Path()
                wedge.arcTo(Rect.fromCircle(center: centre, radius: outer), angle, s, true)
                wedge.arcTo(Rect.fromCircle(center: centre, radius: inner), angle + s, -s, false)
                wedge.close()
                canvas.drawPath(wedge, fill)
                canvas.drawPath(wedge, edge)
                labels.append((n.name, level, angle, s))
                draw(n.children, level: level + 1, from: angle, sweep: s, total: n.value, color: accent)
                angle += s
            }
        }
        draw(nodes, level: 0, from: -.pi / 2, sweep: 2 * .pi, total: nodes.reduce(0) { $0 + max(0, $1.value) }, color: nil)
        guard c.dataLabels else { return }
        for l in labels {
            let tp = text(l.name, 8.4, 0.8 * ring)
            defer { tp.dispose() }
            let inner = ring * Double(l.level + 1)
            guard l.sweep * inner >= tp.height + 3 * k else { continue }
            let mid = l.from + l.sweep / 2, at = inner + ring / 2
            canvas.save()
            canvas.translate(centre.dx + cos(mid) * at, centre.dy + sin(mid) * at)
            canvas.rotate(cos(mid) >= 0 ? mid : mid + .pi)
            tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2 + 2.1 * k))
            canvas.restore()
        }
    }

    /// A treemap, as Excel prints chart-treemap's: each level's nodes,
    /// the larger first, in strips across their parent's box, top to
    /// bottom, a strip taking the next node while that does not worsen
    /// its boxes' mean aspect, and taking the whole next strip where one
    /// strip of both is squarer than the two (First's A, D and C in one
    /// row, not A and D over a sliver of C). Only the leaves are filled,
    /// in their branch's accent, ruled in the background at 1.5 pt; a
    /// leaf's name in its foot's left corner, a top-level branch's in its
    /// box's top left, 3.8 pt in.
    static func _treemap(_ c: Chart, _ nodes: [Chart.SunburstNode], _ canvas: any Canvas, _ area: Rect, k: Double, theme: DeckTheme,
                         text: (String, Double, Double) -> TextPainter) {
        // (A sheet's k is three quarters of a point's.)
        let pt = c.onSheet ? k / 0.75 : k
        // (The boxes 5.8 pt inside the frame at the sides and foot, and
        // 0.67 lower than the room under the title: Excel's print of
        // chart-treemap, where ours stood 6.75 in and 3.45 off its foot.)
        let area = c.onSheet ? Rect.fromLTRB(area.left - 0.95 * pt, area.top + 0.67 * pt, area.right + 0.95 * pt, area.bottom - 2.43 * pt) : area
        func aspect(_ areas: ArraySlice<Double>, across width: Double) -> Double {
            let h = areas.reduce(0, +) / width
            guard h > 0 else { return .infinity }
            return areas.reduce(0) { $0 + max($1 / h / h, h * h / max($1, 1e-9)) } / Double(areas.count)
        }
        func strips(_ values: [Double], in box: Rect) -> [Rect] {
            let total = values.reduce(0, +)
            guard total > 0, box.width > 0, box.height > 0 else { return values.map { _ in .zero } }
            let areas = values.map { $0 / total * box.width * box.height }
            func grow(_ i: Int) -> Int {
                var j = i + 1
                while j < areas.count, aspect(areas[i ... j], across: box.width) <= aspect(areas[i ..< j], across: box.width) { j += 1 }
                return j
            }
            var out: [Rect] = [], i = 0, y = box.top
            while i < areas.count {
                var j = grow(i)
                while j < areas.count {
                    let next = grow(j)
                    let apart = (aspect(areas[i ..< j], across: box.width) * Double(j - i)
                        + aspect(areas[j ..< next], across: box.width) * Double(next - j)) / Double(next - i)
                    guard aspect(areas[i ..< next], across: box.width) < apart else { break }
                    j = next
                }
                let h = areas[i ..< j].reduce(0, +) / box.width
                var x = box.left
                for a in areas[i ..< j] {
                    out.append(Rect.fromLTWH(x, y, a / h, h))
                    x += a / h
                }
                y += h
                i = j
            }
            return out
        }
        let fill = Paint()
        fill.style = .fill
        fill.isAntiAlias = true
        let edge = Paint()
        edge.style = .stroke
        edge.isAntiAlias = true
        edge.strokeWidth = max(0.25, 1.5 * pt)
        edge.color = theme.background
        var labels: [(name: String, box: Rect, top: Bool)] = []
        func draw(_ nodes: [Chart.SunburstNode], in box: Rect, level: Int, color: Int?) {
            let shown = nodes.filter { $0.value > 0 }
            for (n, r) in zip(shown, strips(shown.map(\.value), in: box)) {
                let accent = color ?? n.color
                if n.children.isEmpty {
                    fill.color = theme.accents.isEmpty ? Color(0xFF808080) : theme.accents[accent % theme.accents.count]
                    canvas.drawRect(r, fill)
                    canvas.drawRect(r, edge)
                    labels.append((n.name, r, false))
                } else {
                    draw(n.children, in: r, level: level + 1, color: accent)
                    if level == 0 { labels.append((n.name, r, true)) }
                }
            }
        }
        draw(nodes, in: area, level: 0, color: nil)
        guard c.dataLabels else { return }
        // (Their glyphs 1.35 pt lower than a line's box 3.8 pt in would
        // put them: B's and Best's in Excel's print.)
        let inset = 3.8 * pt, drop = 1.35 * pt
        for l in labels {
            let tp = text(l.name, c.textSize ?? 9, max(1, l.box.width - 2 * inset))
            defer { tp.dispose() }
            guard tp.width <= l.box.width - 2 * inset + 0.5, tp.height <= l.box.height - 2 * inset else { continue }
            tp.paint(canvas, Offset(l.box.left + inset, (l.top ? l.box.top + inset : l.box.bottom - inset - tp.height) + drop))
        }
    }
}

extension ChartPainter {
    /// A pie of pie or bar of pie: the main pie with one slice for the
    /// points moved out, centred at three o'clock and facing the second
    /// plot, its own points running on clockwise from it; the second plot
    /// beside it, a pie starting where the main pie's points start, or a
    /// bar stacked from the top, `size` of the main pie's height (half
    /// that wide). The two side by side, a gap between of about two
    /// thirds of the second plot's width, centred in the room. So Excel's prints of chart-pieOfPieChart2
    /// (second pie from 85.7°, half its 171.4° "other" slice) and
    /// chart-barOfPieChart (a 145.2 by 72.6 bar beside a 193.6 pie, 48.4
    /// apart).
    static func _ofPie(_ c: Chart, _ canvas: any Canvas, _ area: Rect, k: Double, theme: DeckTheme, frame: Rect, ink: Color) {
        guard let o = c.ofPie, let series = c.series.first else { return }
        let values = series.values.map { max(0, $0 ?? 0) }
        let sum = values.reduce(0, +)
        let moved = values.indices.filter { o.second.contains($0) }
        let other = moved.reduce(0.0) { $0 + values[$1] }
        guard sum > 0 else { return }
        let width2 = o.bar ? o.size / 2 : o.size, gap = 0.65 * width2
        // (0.87 of what a pie alone would take of the room, across or
        // down: both prints' pies, the bar of pie's held by the height
        // and the pie of pie's by the width.)
        let d = 0.87 * min(area.height * 0.97, area.width / (1 + width2 + gap))
        let left = area.center.dx - d * (1 + width2 + gap) / 2
        let centre = Offset(left + d / 2, area.center.dy)
        let fill = Paint()
        fill.style = .fill
        fill.isAntiAlias = true
        let edge = Paint()
        edge.style = .stroke
        edge.isAntiAlias = true
        edge.strokeWidth = max(0.5, 1.5 * k)
        edge.color = theme.background
        if c.onSlide, !c.styled2013, c.officeStyled { edge.color = Color(0x00000000) }
        func slice(_ oval: Rect, _ from: Double, _ sweep: Double, _ color: Color) {
            fill.color = color
            canvas.drawArc(oval, from, sweep, true, fill)
            canvas.drawArc(oval, from, sweep, true, edge)
        }
        // The main pie.
        let oval = Rect.fromCircle(center: centre, radius: d / 2)
        let half = other / sum * .pi
        var angle = half
        var labelled: [(index: Int, mid: Double, value: Double, color: Color)] = []
        for i in values.indices where !o.second.contains(i) && values[i] > 0 {
            let sweep = values[i] / sum * 2 * .pi
            slice(oval, angle, sweep, c.pointColor(i, accents: theme.accents))
            labelled.append((i, angle + sweep / 2, values[i], c.pointColor(i, accents: theme.accents)))
            angle += sweep
        }
        if other > 0 {
            slice(oval, -half, 2 * half, series.color ?? c.pointColor(values.count, accents: theme.accents))
            // (The slice the second plot stands for is the point after the
            // last, its label's index: zh-b8de3ae2's "規費收入, [值]".)
            labelled.append((values.count, 0, other, series.color ?? c.pointColor(values.count, accents: theme.accents)))
        }
        // Its labels, as a pie's (`_pieLabels`).
        if let l = c.pieLabels {
            _pieLabels(c, l, canvas, frame: frame, slices: labelled, centre: centre, rx: d / 2, ry: d / 2, inner: 0, k: k, theme: theme, ink: ink)
        }
        // The second plot.
        guard other > 0 else { return }
        let x2 = left + d * (1 + gap)
        if o.bar {
            let h = d * o.size, w = d * width2
            var top = centre.dy - h / 2
            var segments: [Int: Rect] = [:]
            for i in moved where values[i] > 0 {
                let part = values[i] / other * h
                let r = Rect.fromLTWH(x2, top, w, part)
                fill.color = c.pointColor(i, accents: theme.accents)
                canvas.drawRect(r, fill)
                canvas.drawRect(r, edge)
                segments[i] = r
                top += part
            }
            // The bar's labels from their segments' middles, then moved as
            // the file says, no leaders (zh-b8de3ae2's in Word's print).
            if var l = c.pieLabels {
                l.outside = false
                l.fitted = false
                l.leaders = false
                for (i, r) in segments {
                    _pieLabels(c, l, canvas, frame: frame, slices: [(i, 0, values[i], c.pointColor(i, accents: theme.accents))],
                               centre: r.center, rx: 1, ry: 1, inner: 0, k: k, theme: theme, ink: ink, point: { _, _ in r.center })
                }
            }
        } else {
            let r2 = d * o.size / 2
            let oval2 = Rect.fromCircle(center: Offset(x2 + r2, centre.dy), radius: r2)
            var a = half
            for i in moved where values[i] > 0 {
                let sweep = values[i] / other * 2 * .pi
                slice(oval2, a, sweep, c.pointColor(i, accents: theme.accents))
                a += sweep
            }
        }
    }

    /// A surface chart's value bands, from 0 (or the least value, if under
    /// it) to the greatest value rounded out, a step of the axis apart
    /// (the file's major unit, else the automatic one).
    static func _surfaceBands(_ c: Chart) -> [(lo: Double, hi: Double)] {
        let values = c.series.flatMap { $0.values.compactMap { $0 } }
        guard let top = values.max() else { return [] }
        let low = min(0, values.min() ?? 0)
        let step = c.valueStep ?? scale(low, top, intervals: 5).step
        guard step > 0 else { return [] }
        var bands: [(Double, Double)] = []
        var lo = (low / step).rounded(.down) * step
        while lo < top - 1e-9, bands.count < 12 {
            bands.append((lo, lo + step))
            lo += step
        }
        return bands
    }

    /// A surface chart, as Excel draws one: its categories along the front,
    /// its series going back, each value the surface's height there, seen
    /// at the chart's rotations — each cell two triangles in the colour of
    /// the band its values fall in, drawn far to near, with the rows', the
    /// series' and the value steps' labels. (The Word showcase's F09, a
    /// grey box before.) Its walls and the bands' exact boundaries inside a
    /// face are not drawn.
    static func _surface(_ c: Chart, _ canvas: any Canvas, _ area: Rect, k: Double, theme: DeckTheme, grid: Color,
                         text: (String, Double, Double) -> TextPainter) {
        let rows = c.categories.count, cols = c.series.count
        let bands = _surfaceBands(c)
        guard rows >= 2, cols >= 2, let first = bands.first, let last = bands.last else { return }
        let lo = first.lo, hi = last.hi, span = max(1e-9, hi - lo)
        func value(_ i: Int, _ j: Int) -> Double { c.series[j].values[safe: i].flatMap { $0 } ?? lo }
        let rx = c.surfaceView.dx * .pi / 180, ry = c.surfaceView.dy * .pi / 180
        // The unit box, x across the categories, z back through the series,
        // y up the values (half as tall as it is wide), turned about the
        // vertical by rotY and tipped toward the viewer by rotX.
        func project(_ x: Double, _ y: Double, _ z: Double) -> (Offset, Double) {
            let X = x - 0.5, Y = (y - 0.5) * 0.5, Z = z - 0.5
            let x1 = X * cos(ry) + Z * sin(ry), z1 = -X * sin(ry) + Z * cos(ry)
            // (Seen from above: what stands further back stands higher, and
            // is further from the eye.)
            let sy = Y * cos(rx) + z1 * sin(rx), depth = z1 * cos(rx) - Y * sin(rx)
            return (Offset(x1, -sy), depth)
        }
        var corners: [Offset] = []
        for x in [0.0, 1] { for y in [0.0, 1] { for z in [0.0, 1] { corners.append(project(x, y, z).0) } } }
        let minX = corners.map(\.dx).min()!, maxX = corners.map(\.dx).max()!
        let minY = corners.map(\.dy).min()!, maxY = corners.map(\.dy).max()!
        let size = c.valueLabelSize ?? c.baseTextSize
        let pad = 3 * size * k
        let room = Rect.fromLTRB(area.left + pad, area.top + size * k, area.right - pad, area.bottom - 2 * size * k)
        let fit = min(room.width / max(1e-9, maxX - minX), room.height / max(1e-9, maxY - minY))
        let origin = Offset(room.center.dx - (minX + maxX) / 2 * fit, room.center.dy - (minY + maxY) / 2 * fit)
        func at(_ x: Double, _ y: Double, _ z: Double) -> (Offset, Double) {
            let (p, d) = project(x, y, z)
            return (Offset(origin.dx + p.dx * fit, origin.dy + p.dy * fit), d)
        }
        func point(_ i: Int, _ j: Int) -> (Offset, Double, Double) {
            let v = value(i, j)
            let (p, d) = at(Double(i) / Double(rows - 1), (v - lo) / span, Double(j) / Double(cols - 1))
            return (p, d, v)
        }
        // The floor's grid and the value steps up the back left edge.
        let rule = Paint()
        rule.style = .stroke
        rule.isAntiAlias = true
        rule.strokeWidth = max(0.5, 0.75 * k)
        rule.color = grid
        for b in bands.map(\.lo) + [hi] {
            let y = (b - lo) / span
            let a = at(0, y, 1).0, m = at(1, y, 1).0
            canvas.drawLine(a, m, rule)
            let tp = text(label(b, percent: false), size, .infinity)
            let p = at(0, y, 0).0
            tp.paint(canvas, Offset(p.dx - tp.width - 4 * k, p.dy - tp.height / 2))
            tp.dispose()
        }
        typealias Vertex = (p: Offset, v: Double)
        var triangles: [([Vertex], Double)] = []
        for i in 0 ..< rows - 1 {
            for j in 0 ..< cols - 1 {
                let a = point(i, j), b = point(i + 1, j), d = point(i, j + 1), e = point(i + 1, j + 1)
                for t in [[a, b, e], [a, e, d]] {
                    triangles.append((t.map { ($0.0, $0.2) }, t.map(\.1).reduce(0, +) / 3))
                }
            }
        }
        /// The part of a face whose values lie on one side of `level`
        /// (above it where `above`), the edges cut where the value crosses
        /// it, linearly — Sutherland and Hodgman's clip on the value.
        func clip(_ poly: [Vertex], _ level: Double, above: Bool) -> [Vertex] {
            guard !poly.isEmpty else { return [] }
            func inside(_ x: Vertex) -> Bool { above ? x.v >= level : x.v <= level }
            var out: [Vertex] = []
            for n in poly.indices {
                let cur = poly[n], next = poly[(n + 1) % poly.count]
                if inside(cur) { out.append(cur) }
                if inside(cur) != inside(next), next.v != cur.v {
                    let t = (level - cur.v) / (next.v - cur.v)
                    out.append((Offset(cur.p.dx + (next.p.dx - cur.p.dx) * t, cur.p.dy + (next.p.dy - cur.p.dy) * t), level))
                }
            }
            return out
        }
        let fill = Paint()
        fill.style = .fill
        fill.isAntiAlias = true
        let edge = Paint()
        edge.style = .stroke
        edge.isAntiAlias = true
        edge.strokeWidth = max(0.25, 0.5 * k)
        // Far to near; each face split at the bands' bounds, each piece in
        // its band's colour (the showcase's peak, 16-20 in Word's print).
        for (tri, _) in triangles.sorted(by: { $0.1 > $1.1 }) {
            for (n, b) in bands.enumerated() {
                let piece = clip(clip(tri, b.lo, above: true), b.hi, above: false)
                guard piece.count >= 3 else { continue }
                fill.color = c.color(series: n, accents: theme.accents)
                edge.color = fill.color
                let path = Path()
                path.moveTo(piece[0].p.dx, piece[0].p.dy)
                for q in piece.dropFirst() { path.lineTo(q.p.dx, q.p.dy) }
                path.close()
                canvas.drawPath(path, fill)
                canvas.drawPath(path, edge)
            }
        }
        // The rows along the front edge, the series along the right one.
        for i in 0 ..< rows {
            let tp = text(c.categories[i], size, .infinity)
            let p = at(Double(i) / Double(rows - 1), 0, 0).0
            tp.paint(canvas, Offset(p.dx - tp.width / 2, p.dy + 3 * k))
            tp.dispose()
        }
        for j in 0 ..< cols {
            let tp = text(c.series[j].name, size, .infinity)
            let p = at(1, 0, Double(j) / Double(cols - 1)).0
            tp.paint(canvas, Offset(p.dx + 4 * k, p.dy - tp.height / 2))
            tp.dispose()
        }
    }

    /// A line series' mark at `q`: its symbol at its size, filled and
    /// outlined in its colours.
    static func _mark(_ l: ChartSeries, at q: Offset, k: Double, colour: Color, _ canvas: any Canvas) {
        guard let symbol = l.marker, symbol != "none" else { return }
        let r = max(1, l.markerSize * k / 2)
        let shape = Path()
        switch symbol {
        case "square": shape.addRect(Rect.fromLTRB(q.dx - r, q.dy - r, q.dx + r, q.dy + r))
        // (Office's "dot" is a short dash: chartex's Close marks, and its
        // legend's key, in Word's print.)
        case "dot": shape.addRect(Rect.fromLTRB(q.dx - r, q.dy - r / 4, q.dx + r, q.dy + r / 4))
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
        // The whole circle the spokes reach stands in the area, with 1.2
        // label lines and 3 pt over it and 1.2 under it, above a foot
        // 6.5 pt off the frame (a 2013-style chart's area ends 9 off it).
        // So chartex's five-spoke radar, its lower labels beside their
        // spokes, in Word's print with its legend at the top, the foot
        // and none (radius 81.9 and 93.4, centre within 0.7), and
        // radar-chart's four spokes in PowerPoint's (108.9, 0.3).
        let lineH = catLabels.map(\.height).max() ?? 12 * k
        let over = 1.2 * lineH + 3 * k, under = 1.2 * lineH - (c.styled2013 ? 2.5 * k : 0)
        let wide = (catLabels.map(\.width).max() ?? 0) + 4 * k
        let radius = max(4, min(area.width / 2 - wide, (area.height - over - under) / 2))
        let centre = Offset(area.center.dx, area.top + over + radius)
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
        // The value axis's labels up the first spoke, to its left, as far
        // off it as they are tall (radar-chart's 18 pt labels end 18.1 pt
        // from it in PowerPoint's print, chartex's 9 pt 9.1 in Word's).
        if !c.valueAxisDeleted {
            for v in ticks {
                let tp = text(label(v, percent: c.percent), labelSize, .infinity)
                let at = point(0, r(v))
                tp.paint(canvas, Offset(at.dx - labelSize * k - tp.width, at.dy - tp.height / 2))
                tp.dispose()
            }
        }
        // The categories outside the spokes' ends: above or below an end
        // straight up or down, beside any other, centred on it (chartex's
        // five in Word's print, the lower two level with their ends).
        for (i, tp) in catLabels.enumerated() {
            let a = -Double.pi / 2 + Double(i) * 2 * .pi / Double(n)
            let end = point(i, radius + 3 * k)
            let dx = cos(a), dy = sin(a)
            let x = abs(dx) < 0.2 ? end.dx - tp.width / 2 : dx > 0 ? end.dx : end.dx - tp.width
            let y = abs(dx) >= 0.2 ? end.dy - tp.height / 2 : dy > 0 ? end.dy : end.dy - tp.height
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
            p.color = c.radarFilled ? c.color(series: j, accents: theme.accents) : c.lineColor(series: j, accents: theme.accents)
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
    /// A box-and-whisker chart's boxes, as Word's print of chartex's draws
    /// them: a category's boxes take its slot over 1 + the gap, 1.12 of a
    /// box apart (20.2 pt boxes at 22.6 in its 132.3 pt slots); each in
    /// its series' colour, outlined in 0.8 of it, from the lower quartile
    /// to the upper with the median across; whiskers to the furthest
    /// samples within 1.5 of the box's height of it, capped 6 pt wide;
    /// the mean a 6 pt cross; samples past the whiskers 3 pt dots.
    static func _boxes(_ c: Chart, _ canvas: any Canvas, _ plot: Rect, k: Double, theme: DeckTheme,
                       vpos: (Double) -> Double) {
        guard let boxes = c.boxes else { return }
        let n = max(1, c.categories.count), s = Double(max(1, boxes.count))
        let slot = plot.width / Double(n)
        let group = slot / (1 + c.boxGap)
        let w = group / (s + (s - 1) * 0.12), pitch = w * 1.12
        let fill = Paint()
        fill.style = .fill
        fill.isAntiAlias = true
        let line = Paint()
        line.style = .stroke
        line.isAntiAlias = true
        line.strokeWidth = max(0.25, 0.75 * k)
        for (j, cats) in boxes.enumerated() {
            let colour = c.color(series: j, accents: theme.accents)
            fill.color = colour
            line.color = Self._scaled(colour, 0.8)
            for (i, xs) in cats.enumerated() where !xs.isEmpty {
                let q1 = ChartXML.quartile(xs, 0.25, inclusive: c.boxInclusive)
                let q2 = ChartXML.quartile(xs, 0.5, inclusive: c.boxInclusive)
                let q3 = ChartXML.quartile(xs, 0.75, inclusive: c.boxInclusive)
                let reach = 1.5 * (q3 - q1)
                let inside = xs.filter { $0 >= q1 - reach && $0 <= q3 + reach }
                let left = plot.left + (Double(i) + 0.5) * slot - group / 2 + Double(j) * pitch
                let mid = left + w / 2, cap = 3 * k
                if let lo = inside.first, let hi = inside.last {
                    canvas.drawLine(Offset(mid, vpos(q1)), Offset(mid, vpos(lo)), line)
                    canvas.drawLine(Offset(mid - cap, vpos(lo)), Offset(mid + cap, vpos(lo)), line)
                    canvas.drawLine(Offset(mid, vpos(q3)), Offset(mid, vpos(hi)), line)
                    canvas.drawLine(Offset(mid - cap, vpos(hi)), Offset(mid + cap, vpos(hi)), line)
                }
                let box = Rect.fromLTRB(left, vpos(q3), left + w, vpos(q1))
                canvas.drawRect(box, fill)
                canvas.drawRect(box, line)
                canvas.drawLine(Offset(left, vpos(q2)), Offset(left + w, vpos(q2)), line)
                if c.boxMeans {
                    let m = vpos(xs.reduce(0, +) / Double(xs.count))
                    canvas.drawLine(Offset(mid - cap, m - cap), Offset(mid + cap, m + cap), line)
                    canvas.drawLine(Offset(mid - cap, m + cap), Offset(mid + cap, m - cap), line)
                }
                if c.boxOutliers {
                    for v in xs where v < q1 - reach || v > q3 + reach {
                        canvas.drawCircle(Offset(mid, vpos(v)), 1.5 * k, fill)
                        canvas.drawCircle(Offset(mid, vpos(v)), 1.5 * k, line)
                    }
                }
            }
        }
    }

    static func _scaled(_ c: Color, _ f: Double) -> Color {
        let v = c.value
        func ch(_ sh: Int) -> Int64 { Int64((Double((v >> sh) & 0xFF) * f).rounded()) }
        return Color(Int64(0xFF00_0000) | ch(16) << 16 | ch(8) << 8 | ch(0))
    }

    /// A 3-D pie: the disc tilted by `tilt` degrees and seen in
    /// perspective, its rim showing below, lit from the left — as
    /// PowerPoint's print of LIBRE_OFFICE-100610-0 has it at 30°: the eye
    /// 4.8 radii off, so the centre stands 0.41 of the way down the top
    /// (not half), the top 0.468 as tall as wide, the rim 0.275 of the
    /// radius deep; the whole filling 94% of the plot's width or 97% of
    /// its height; the rim 0.85 of the colour at the left, 0.54 at the
    /// front and 0.41 from a little right of it on.
    static func _pie3D(_ c: Chart, _ canvas: any Canvas, _ plot: Rect, tilt: Double, k: Double, theme: DeckTheme,
                       frame: Rect? = nil, ink: Color? = nil) {
        let values = c.series[0].values.map { max(0, $0 ?? 0) }
        let sum = values.reduce(0, +)
        guard sum > 0 else { return }
        let al = max(5, min(90, tilt)) * .pi / 180
        let eye = 4.8, deep = 0.275
        // (Taller than the eye's 30° makes it: PowerPoint's top is 0.468
        // as tall as wide, the view's 0.509.)
        let squash = 0.92
        // A point of the disc at angle `a` (0 to the right, a quarter
        // turn toward the viewer), `f` of the radius out and `h` radii
        // down, on a disc of radius 1 centred on 0.
        func unit(_ a: Double, _ f: Double, _ h: Double) -> (x: Double, y: Double) {
            let x = f * cos(a), z = -f * sin(a)
            let d = eye + z * cos(al) + h * sin(al)
            return (x / d, -(z * sin(al) - h * cos(al)) / d * squash)
        }
        var lo = (x: Double.infinity, y: Double.infinity), hi = (x: -Double.infinity, y: -Double.infinity)
        for j in 0 ..< 360 {
            for h in [0, deep] {
                let q = unit(Double(j) * .pi / 180, 1, h)
                lo = (min(lo.x, q.x), min(lo.y, q.y)); hi = (max(hi.x, q.x), max(hi.y, q.y))
            }
        }
        // (Where no label stands outside it, bigger by 1.16: Word keeps a
        // band for outside labels whatever they say. Labs p3dplot and
        // p3dplot2 (Word for Windows, zh-27a874b7's chart 1): 322 x 186
        // with no labels or with them inside or centred, 277 x 160.5 with
        // them best fit or outside — one, three or all six, two to six
        // ideographs, one line or three; the same 1.16 at rotX 15 and 50
        // and under a title. Ours, its labels' size whatever they were,
        // is Word's with them outside.)
        let unbanded = frame != nil && !c.onSlide && !c.onSheet && c.plotLayout == nil && !c.legend && !c.pieLabelsAround
        let scale = min(plot.width * 0.941 / (hi.x - lo.x), plot.height * 0.972 / (hi.y - lo.y)) / (1 + c.pieExplosion) * (unbanded ? 1.16 : 1)
        let origin = Offset(plot.center.dx - scale * (lo.x + hi.x) / 2, plot.center.dy - scale * (lo.y + hi.y) / 2)
        // (Drawn, where Word lays it out itself — no title, no legend, no
        // layout of the file's — on the frame's middle and 1.5pt over it,
        // its labels where they were: lab p3dplot (Word for Windows,
        // zh-27a874b7's two charts, rotX 30), the pie as seen at 303.0 and
        // 205.8 in a frame 102.7-503.3 x 99.3-315.3, 302.0 and 499.0 in
        // 109.9-494.3 x 391.9-608.6, where ours stood 1.2 left and 2.7 low;
        // its labels, though, stand where ours did — moved with the pie,
        // all seventeen of chart 2's went 2.8 high.)
        let drawn: Offset = {
            guard let f = frame, !c.onSlide, !c.onSheet, c.plotLayout == nil, !c.legend, (c.title ?? "").isEmpty, abs(tilt - 30) < 0.5 else { return .zero }
            return Offset(f.center.dx - (origin.dx + scale * (lo.x + hi.x) / 2), f.center.dy - 1.5 * k - (origin.dy + scale * (lo.y + hi.y) / 2))
        }()
        canvas.save()
        canvas.translate(drawn.dx, drawn.dy)
        func at(_ a: Double, _ f: Double = 1, _ h: Double = 0) -> Offset {
            let q = unit(a, f, h)
            return Offset(origin.dx + q.x * scale, origin.dy + q.y * scale)
        }
        let centre = at(0, 0)
        // The slices, clockwise from twelve o'clock.
        var slices: [(from: Double, to: Double, color: Color, value: Double)] = []
        var angle = -Double.pi / 2 + c.pieTurn * .pi / 180
        for (i, v) in values.enumerated() where v > 0 {
            let sweep = v / sum * 2 * .pi
            slices.append((angle, angle + sweep, c.pointColor(i, accents: theme.accents), v))
            angle += sweep
        }
        let fill = Paint()
        fill.style = .fill
        fill.isAntiAlias = true
        func scaled(_ c: Color, _ f: Double) -> Color {
            let v = c.value
            func ch(_ sh: Int) -> Int64 { Int64((Double((v >> sh) & 0xFF) * f).rounded()) }
            return Color(Int64(0xFF00_0000) | ch(16) << 16 | ch(8) << 8 | ch(0))
        }
        // The rim: the part of it that faces the eye — less than the front
        // half, the eye being near — in steps a few degrees wide, each
        // shaded for the way it faces.
        let side = asin(min(1, 1 / (eye * cos(al))))
        for s in slices {
            var a = s.from
            while a < s.to {
                let b = min(s.to, a + 3 * .pi / 180)
                // The same part of the circle a turn on, where it shows.
                for turn in [-2 * Double.pi, 0, 2 * Double.pi] {
                    // (Each step a little past the next, so no seam shows
                    // between them; the next one covers the overlap.)
                    let lo = max(a + turn, side), hi = min(b + turn + 0.01, .pi - side)
                    guard hi > lo else { continue }
                    let p = Path()
                    let p0 = at(lo)
                    p.moveTo(p0.dx, p0.dy)
                    let steps = max(1, Int((hi - lo) / (0.5 * .pi / 180)))
                    for j in 1 ... steps { let q = at(lo + (hi - lo) * Double(j) / Double(steps)); p.lineTo(q.dx, q.dy) }
                    for j in stride(from: steps, through: 0, by: -1) {
                        let q = at(lo + (hi - lo) * Double(j) / Double(steps), 1, deep); p.lineTo(q.dx, q.dy)
                    }
                    p.close()
                    let facing = .pi / 2 - (lo + hi) / 2
                    fill.color = scaled(s.color, 0.41 + 0.44 * max(0, cos(facing + 70 * .pi / 180)))
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
        canvas.restore()
        let rx = (at(0).dx - at(.pi).dx) / 2, ry = (at(.pi / 2).dy - at(-.pi / 2).dy) / 2
        if var l = c.pieLabels {
            var placed: [(index: Int, mid: Double, value: Double, color: Color)] = []
            var a = -Double.pi / 2 + c.pieTurn * .pi / 180
            for (i, v) in values.enumerated() where v > 0 {
                let sweep = v / sum * 2 * .pi
                placed.append((i, a + sweep / 2, v, c.pointColor(i, accents: theme.accents)))
                a += sweep
            }
            _pieLabels(c, l, canvas, frame: frame ?? plot, slices: placed, centre: centre, rx: rx, ry: ry, inner: 0,
                       k: k, theme: theme, ink: ink ?? theme.text,
                       // (From outside, a front slice's edge is its wall's foot:
                       // lab tpie (windows-1, zh-d62da4dd's chart1, rotX 30) sets
                       // "經濟", at three o'clock, a wall's depth lower than the
                       // top face's edge would, its file's move taken off.)
                       // (A label the file does not move, from a little past
                       // three and nine o'clock only: lab p3dside's 香港 stands
                       // by the top's edge with its middle at 90-97.4° and by
                       // the wall's foot at 99.7°, the same at 270° and 265°.
                       // zh-27a874b7's moved "經濟", 95.9°, is moved from the foot.)
                       point: { a, f in at(a, f, f >= 1 && sin(a) > sin(8.5 * .pi / 180) ? deep : 0) },
                       movedEdge: { a in at(a, 1, sin(a) > 0 ? deep : 0) })
        } else if c.dataLabels {
            for s in slices {
                let pt = at((s.from + s.to) / 2, 0.7)
                let v = s.color.value
                let luma = 0.299 * Double((v >> 16) & 0xFF) + 0.587 * Double((v >> 8) & 0xFF) + 0.114 * Double(v & 0xFF)
                let tp = TextPainter(text: TextSpan(text: dataLabel(c, s.value), style: Flutter.TextStyle(
                    color: luma < 150 ? Color(0xFFFFFFFF) : Color(0xFF404040), fontSize: max(3, (c.baseTextSize) * k),
                    fontFamily: OfficeFonts.substitute(c.font ?? theme.bodyFont), fontFamilyFallback: Self.glyphFallback(c))), textDirection: .ltr)
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
    /// Whole percentages that add up to 100, by largest remainder: each
    /// share's floor, then a point each to the largest remainders until the
    /// sum is 100 — ties to the smaller value. Word's prints of zh-d62da4dd's
    /// pies: 50 of 400 is "12%" (12.5, the rest going to three 0.75s), and
    /// of seven slices at x.75 with six points to give, 103's 25.75 is the
    /// one left "25%". (Smaller value or later point: the file cannot tell.)
    static func wholePercents(_ points: [(key: Int, value: Double)]) -> [Int: Int] {
        let sum = points.reduce(0) { $0 + max(0, $1.value) }
        guard sum > 0 else { return [:] }
        var out: [Int: Int] = [:]
        var rest: [(key: Int, frac: Double, value: Double, order: Int)] = []
        for (n, p) in points.enumerated() {
            let exact = max(0, p.value) / sum * 100
            out[p.key] = Int(exact.rounded(.down))
            rest.append((p.key, exact - exact.rounded(.down), p.value, n))
        }
        var left = 100 - out.values.reduce(0, +)
        let ordered = rest.sorted { a, b in
            if abs(a.frac - b.frac) > 1e-9 { return a.frac > b.frac }
            return a.value != b.value ? a.value < b.value : a.order < b.order
        }
        for r in ordered where left > 0 {
            out[r.key, default: 0] += 1
            left -= 1
        }
        return out
    }

    static func _pieLabels(_ c: Chart, _ l: Chart.PieLabels, _ canvas: any Canvas, frame: Rect,
                           slices: [(index: Int, mid: Double, value: Double, color: Color)],
                           centre: Offset, rx: Double, ry: Double, inner: Double, k: Double, theme: DeckTheme, ink: Color,
                           point: ((Double, Double) -> Offset)? = nil, movedEdge: ((Double) -> Offset)? = nil) {
        // A point `f` of the radius out along angle `a`: on the flat
        // ellipse, or where a 3-D pie's perspective puts it.
        func on(_ a: Double, _ f: Double) -> Offset {
            point?(a, f) ?? Offset(centre.dx + cos(a) * rx * f, centre.dy + sin(a) * ry * f)
        }
        let sum = slices.reduce(0) { $0 + $1.value }
        guard sum > 0 else { return }
        let whole = Self.wholePercents(slices.map { (key: $0.index, value: $0.value) })
        for s in slices {
            let size = max(3, (l.sizes[s.index] ?? c.series[0].labelSize ?? c.baseTextSize) * k)
            var parts: [String] = []
            if l.series { parts.append(c.series[0].name) }
            if l.category, s.index < c.categories.count { parts.append(c.categories[s.index]) }
            if l.value { parts.append(dataLabel(c, s.value)) }
            if l.percent {
                let share = s.value / sum
                if let code = c.labelFormat, code.containsSubstring("%") {
                    parts.append(NumberFormat.format(share, code, width: 40).text.trimmingWhitespace())
                } else { parts.append("\(whole[s.index] ?? Int((share * 100).rounded()))%") }
            }
            guard !parts.isEmpty || l.texts[s.index] != nil else { continue }
            let text = l.texts[s.index].map { own in
                own.replacingAll("\u{E000}c", with: s.index < c.categories.count ? c.categories[s.index] : "")
                    .replacingAll("\u{E000}v", with: dataLabel(c, s.value))
                    .replacingAll("\u{E000}s", with: c.series[0].name)
                    .replacingAll("\u{E000}p", with: "\(whole[s.index] ?? Int((s.value / sum * 100).rounded()))%")
            // (", " where the chart's text is Chinese, Japanese or Korean:
            // zh-b8de3ae2's "其他收入, 16.39%" in Word's print; and in a Word document's chart
            // whatever its text: lo-f9b9a8fc47c97aa6's "datalabel1, 2".)
            } ?? parts.joined(separator: l.separator ?? (parts.count > 1 ? (c.eastAsianText || (!c.onSlide && !c.onSheet) ? ", " : "; ") : ""))
            let dark = { () -> Bool in
                let v = s.color.value
                return 0.299 * Double((v >> 16) & 0xFF) + 0.587 * Double((v >> 8) & 0xFF) + 0.114 * Double(v & 0xFF) < 150
            }()
            let colour = c.series[0].labelColor ?? (l.outside || l.fitted || l.fill != nil ? ink : dark ? Color(0xFFFFFFFF) : Color(0xFF404040))
            let tp = TextPainter(text: Self.labelSpan(c, text, Flutter.TextStyle(
                color: colour, fontSize: size, fontWeight: c.series[0].labelBold ? .bold : .normal,
                fontFamily: OfficeFonts.substitute(c.font ?? theme.bodyFont),
                fontFamilyFallback: Self.glyphFallback(c, traditional: l.traditional.contains(s.index)))), textAlign: .center, textDirection: .ltr)
            // (Excel wraps a long label at about a fifth of the chart's width:
            // 45544's "Finance - Investment Banking" is three lines.)
            tp.layout(minWidth: 0, maxWidth: max(20 * k, frame.width * 0.2))
            // (And a one-line label a little narrower: past 0.1857 of the
            // chart's width it wraps too. zh-b8de3ae2's bar of pie, 538.5pt
            // wide, keeps "補助及協助收入, 2.35%" (99.9pt at 10pt) on one line in
            // Word's print and wraps "罰款及賠償收入, 0.64%" (100.0) after its
            // comma. A label that wraps already keeps the fifth's box.)
            if tp.computeLineMetrics().count == 1, tp.width > max(20 * k, frame.width * 0.1857) {
                tp.layout(minWidth: 0, maxWidth: max(20 * k, frame.width * 0.1857))
            }
            let pad = 3 * k
            let w = tp.width + pad * 2, h = tp.height + pad
            let dx = cos(s.mid), dy = sin(s.mid)
            // Where the label stands before its own move: its box's middle.
            var at: Offset
            // (A best fit is decided label by label: inside where its box
            // fits in its slice, else outside. zh-61aaad09's pie, one label
            // moved by its own layout: "582054, 84.15%" stands inside its
            // 303° slice in Word's print, where ours took it out under the
            // pie and past the frame's foot; "109646, 15.85%", whose 57°
            // slice cannot hold it, goes out and its move brings it back.)
            let share = s.value / sum
            // (As far out as it fits, from 0.6 of the radius in: Word's
            // stands 0.41 out.)
            // (A label the file moves is moved from beside its slice, fit
            // or not: zh-d62da4dd's "經濟" stands inside its 53% slice in
            // lab p3d, its move taken out, and its move of -24% of the
            // frame lands it where Word's print has it only from outside;
            // "文化"'s from beside its slice in both.)
            let insideAt: Offset? = {
                guard l.fitted, l.outside, inner == 0, l.moves[s.index] == nil else { return nil }
                // (On a 3-D pie its text's own box, no margin, within its
                // slice's wedge of the top face as the eye sees it, as far
                // out along the slice's middle as it fits: lab p3dfit
                // (Word for Mac, zh-27a874b7's chart 2, rotX 30, the probe's
                // label alone, 32 x 36pt) — inside from 15% at three and
                // nine o'clock, 0.78 of the radius out, from 6% at six and
                // from 12% at twelve, 0.52 out; all 32 of its decisions
                // this test's. A one-line label stands 0.84-0.89 out.
                // Before, every label of an unmoved 3-D pie stood inside.)
                // (Where it fits on the middle only nearer in than 0.7, it
                // stands on the straight line from the centre at the
                // middle's angle as the page sees it, as far out as it
                // fits: lab p3dout (Word for Mac, zh-27a874b7's chart 2, no
                // moves, turned by rotY 0/90/180/270), three-line labels on
                // back slices — 美國 25.8% at 46° and 316°, 其他 14% at 335°
                // — within 4pt of that, 17-25pt from the middle at 0.56-0.64;
                // labels that fit from 0.76 out (one-line ones, 丹麥's,
                // 香港's, the solo probes of p3dfit) stand on the middle.)
                if let point {
                    let tw = tp.width, th = tp.height
                    let a0 = s.mid - share * .pi, a1 = s.mid + share * .pi
                    let n = max(4, Int((a1 - a0) / (.pi / 180)))
                    let wedge = [point(0, 0)] + (0 ... n).map { point(a0 + (a1 - a0) * Double($0) / Double(n), 0.9999) }
                    func contains(_ q: Offset) -> Bool {
                        var inside = false
                        var j = wedge.count - 1
                        for i in 0 ..< wedge.count {
                            let p1 = wedge[i], p2 = wedge[j]
                            if (p1.dy > q.dy) != (p2.dy > q.dy), q.dx < (p2.dx - p1.dx) * (q.dy - p1.dy) / (p2.dy - p1.dy) + p1.dx { inside.toggle() }
                            j = i
                        }
                        return inside
                    }
                    func fits(_ c0: Offset) -> Bool {
                        [(-tw / 2, -th / 2), (tw / 2, -th / 2), (-tw / 2, th / 2), (tw / 2, th / 2)].allSatisfy { contains(Offset(c0.dx + $0.0, c0.dy + $0.1)) }
                    }
                    if let f = stride(from: 0.98, through: 0.7, by: -0.02).first(where: { fits(on(s.mid, $0)) }) { return on(s.mid, f) }
                    // (A front slice holds it on less: there it is enough that
                    // the middles of its box's four sides, the box standing
                    // 0.76 of the way out along the slice's middle, lie in the
                    // slice — where Word's print has it. Lab p3dside (Word for
                    // Mac, zh-27a874b7's chart 2, the 香港 probe at 6-16% and its
                    // middle at 60-165° and the mirror 195-270°, 83 decisions,
                    // all this test's): a 33 x 36pt label inside a 6% slice at
                    // 165° and 8% at 150°, 10% at 135°, where its box's corners
                    // overhang the slice by up to 5pt; at 3 and 9 o'clock and
                    // up to 10° past them its corners still have to fit.)
                    if sin(s.mid) > sin(10 * .pi / 180) {
                        let c0 = on(s.mid, 0.76)
                        if [(-tw / 2, 0.0), (tw / 2, 0.0), (0.0, -th / 2), (0.0, th / 2)].allSatisfy({ contains(Offset(c0.dx + $0.0, c0.dy + $0.1)) }) { return c0 }
                    }
                    let c = on(s.mid, 0)
                    if let d = stride(from: max(rx, ry), through: 0, by: -0.25 * k).first(where: { fits(Offset(c.dx + cos(s.mid) * $0, c.dy + sin(s.mid) * $0)) }) {
                        return Offset(c.dx + cos(s.mid) * d, c.dy + sin(s.mid) * d)
                    }
                    return stride(from: 0.68, through: 0.0, by: -0.02).first(where: { fits(on(s.mid, $0)) }).map { on(s.mid, $0) }
                }
                let half = share * .pi
                return stride(from: 0.6, through: 0.3, by: -0.05).first(where: { f in
                    let c0 = on(s.mid, f)
                    return [(-w / 2, -h / 2), (w / 2, -h / 2), (-w / 2, h / 2), (w / 2, h / 2)].allSatisfy { cx, cy in
                        let x = (c0.dx + cx - centre.dx) / max(rx, 1), y = (c0.dy + cy - centre.dy) / max(ry, 1)
                        guard hypot(x, y) < 1 else { return false }
                        var d = atan2(y, x) - s.mid
                        while d > .pi { d -= 2 * .pi }
                        while d < -.pi { d += 2 * .pi }
                        return abs(d) < half
                    }
                }).map { on(s.mid, $0) }
            }()
            let fitsInside = insideAt != nil
            if let p = insideAt {
                at = p
            } else if l.outside {
                let gap = 4 * k
                // (Where the file moves it, from `movedEdge`'s point when
                // given: a 3-D pie's.)
                let edge = l.moves[s.index] != nil ? movedEdge?(s.mid) ?? on(s.mid, 1) : on(s.mid, 1)
                // (Centred on its slice where it stands over or under it, within
                // about ten degrees of upright: lab tpie's "建築", 0.75% at
                // twelve o'clock, in Word's print, where ours stood a half
                // width left; "金融", 13° off upright, keeps the half width.)
                at = Offset(edge.dx + dx * gap + (abs(dx) < 0.15 ? 0 : dx >= 0 ? w / 2 : -w / 2), edge.dy + dy * gap + dy * h / 2)
            } else {
                // (A 3-D pie's 0.9 of the way out: the survey's.)
                at = on(s.mid, inner > 0 ? (1 + inner / max(rx, 1)) / 2 : point != nil ? 0.9 : 0.7)
            }
            let moved = l.moves[s.index]
            if let m = moved {
                // Word moves a flat pie's label from its default position
                // already fitted into the chart frame. In zh-61aaad09 the
                // outside default reaches above the frame: moving it before
                // clamping loses 9.7pt of the stated downward move. Fresh
                // Word controls at 1%, 15.85% and 35% keep the same 14.16pt
                // move from that fitted default. A 3-D pie's too: Word for
                // Windows' print of zh-27a874b7's chart 2 has "馬來西亞", moved
                // up 27pt from under its 5.8% front slice, where its default
                // box stood inside the frame's foot (ours 14pt low, the
                // default past the frame). Other chart hosts retain their
                // separately measured paths.
                if l.fitted, c.type == .pie, c.ofPie == nil, !c.onSlide, !c.onSheet {
                    at = Offset(min(max(at.dx, frame.left + w / 2), frame.right - w / 2),
                                min(max(at.dy, frame.top + h / 2), frame.bottom - h / 2))
                }
                at = Offset(at.dx + m[0] * frame.width, at.dy + m[1] * frame.height)
            }
            // (Kept inside the frame: Word's labels over a 3-D pie's top
            // stand under the frame's edge in lab p3d, where ours were cut.)
            if l.fitted {
                at = Offset(min(max(at.dx, frame.left + w / 2), frame.right - w / 2),
                            min(max(at.dy, frame.top + h / 2), frame.bottom - h / 2))
            }
            let box = Rect.fromLTWH(at.dx - w / 2, at.dy - h / 2, w, h)
            let leftOut = l.outside && !fitsInside
            // The leader: from the slice's outer edge to the box's nearest
            // point, where the label has left its slice.
            if l.leaders, moved != nil || leftOut {
                let from = on(s.mid, 1)
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

/// A chart's second value axis (`Chart.secondValueAxis`): its own number
/// format and bounds, labelled at the plot's right unless deleted.
/// A chart's data table (`Chart.dataTable`): which of its rules are
/// drawn, whether each row shows its series' key, and its text size.
struct DataTable: Equatable {
    var horizontalRules = true
    var verticalRules = true
    var outline = true
    var keys = true
    var size: Double? = nil
    /// The table's own lines (`c:dTable/c:spPr/a:ln`), where it states them.
    var lineColor: Color? = nil
    var lineWidth: Double? = nil
    /// A table that states its own look — what Office 2013's templates
    /// write — keys its bars with a square, 5.5pt, 3.5 in and 2.4 before
    /// the name (the Word showcase's F10 in Word's print); a 2007 one with
    /// a bar 19.2 long (zh-2a241df1's).
    var squareKeys = false
}

/// Where a placed axis title stands (`Chart.categoryAxisTitleAt`), and
/// its size in points where the file gives one.
struct PlacedAxisTitle: Equatable {
    var at: Offset
    var size: Double? = nil
}

/// A stock chart's high-low lines (`Chart.highLowLines`).
struct HighLowLines: Equatable {
    var color: Color? = nil
    var width = 0.75
}

struct SecondValueAxis: Equatable {
    var format: String? = nil
    var deleted = false
    var min: Double? = nil
    var max: Double? = nil
    var step: Double? = nil
}
