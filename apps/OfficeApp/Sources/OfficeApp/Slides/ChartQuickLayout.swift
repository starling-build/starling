// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Chart Design > Quick Layout: Office's gallery of layouts for a bar or column chart, each as Word applies it (Word's own
// ApplyLayout on a bar and a column chart, lab wobql): the title, legend and where it sits, the axis titles, the value
// gridlines, the gap between categories and the overlap of their bars, and the data labels. The two kinds have their
// own lists (a column chart has a Layout 8 a bar chart lacks, so its 9 to 11 are the bar's 8 to 10). Each layout sets
// every one of those, so applying one after another gives the same chart as applying the second alone; a title or axis
// title the chart already has keeps its text. Layout 2 hides the value axis (Word deletes it: its scale stays, its labels
// and their room go) and labels every bar; Layout 5 puts a data table under the plot. No layout is offered for other
// chart types (Word's lists for those were not measured).

struct ChartQuickLayout: Equatable {
    enum Labels: Equatable {
        case none
        /// Every series' values, at 9 pt.
        case all
        /// Only the last series' values, inside the end of its bars, at 9 pt.
        case lastInside
    }

    let name: String
    let title: Bool
    /// The legend's side ("r", "t", "b", "l"); nil where the layout has no legend.
    let legend: String?
    let valueTitle: Bool
    let categoryTitle: Bool
    let valueGrid: Bool
    /// `c:gapWidth`, and `c:overlap` (0 where Word leaves it out); a stacked chart keeps its own overlap.
    let gap: Int
    let overlap: Int
    let labels: Labels
    /// The value axis shows (`c:delete` 0); Layout 2 deletes it.
    let valueAxis: Bool
    /// A data table under the plot (`c:dTable`, every rule and the keys, as Word adds it).
    let dataTable: Bool

    private init(_ name: String, title: Bool, legend: String?, valueTitle: Bool = false, categoryTitle: Bool = false,
                 grid: Bool = true, gap: Int = 150, overlap: Int = 0, labels: Labels = .none, valueAxis: Bool = true,
                 dataTable: Bool = false) {
        self.name = name; self.title = title; self.legend = legend
        self.valueTitle = valueTitle; self.categoryTitle = categoryTitle
        self.valueGrid = grid; self.gap = gap; self.overlap = overlap; self.labels = labels
        self.valueAxis = valueAxis; self.dataTable = dataTable
    }

    /// Word's Layout 2: title, legend at the top, no value axis or gridlines, every series' values.
    private static let layout2 = ChartQuickLayout("Layout 2", title: true, legend: "t", grid: false, overlap: -25, labels: .all,
                                                  valueAxis: false)

    static let bar: [ChartQuickLayout] = [
        ChartQuickLayout("Layout 1", title: true, legend: "r"),
        layout2,
        ChartQuickLayout("Layout 3", title: true, legend: "b", gap: 75, overlap: -25),
        ChartQuickLayout("Layout 4", title: false, legend: "b", grid: false, gap: 75, labels: .all),
        ChartQuickLayout("Layout 5", title: true, legend: nil, dataTable: true),
        ChartQuickLayout("Layout 6", title: true, legend: nil, valueTitle: true),
        ChartQuickLayout("Layout 7", title: false, legend: "r", valueTitle: true, categoryTitle: true, gap: 300),
        ChartQuickLayout("Layout 8", title: true, legend: "r", valueTitle: true, categoryTitle: true),
        ChartQuickLayout("Layout 9", title: true, legend: "r", gap: 75, overlap: 40, labels: .lastInside),
        ChartQuickLayout("Layout 10", title: false, legend: "r"),
    ]

    static let column: [ChartQuickLayout] = [
        ChartQuickLayout("Layout 1", title: true, legend: "r"),
        layout2,
        ChartQuickLayout("Layout 3", title: true, legend: "b", gap: 75, overlap: -25),
        ChartQuickLayout("Layout 4", title: false, legend: "b", grid: false, gap: 75, labels: .all),
        ChartQuickLayout("Layout 5", title: true, legend: nil, valueTitle: true, dataTable: true),
        ChartQuickLayout("Layout 6", title: true, legend: nil, valueTitle: true),
        ChartQuickLayout("Layout 7", title: false, legend: "r", valueTitle: true, categoryTitle: true, gap: 300),
        ChartQuickLayout("Layout 8", title: true, legend: nil, valueTitle: true, categoryTitle: true, grid: false, gap: 0),
        ChartQuickLayout("Layout 9", title: true, legend: "r", valueTitle: true, categoryTitle: true),
        ChartQuickLayout("Layout 10", title: true, legend: "r", gap: 75, overlap: 40, labels: .lastInside),
        ChartQuickLayout("Layout 11", title: false, legend: "r"),
    ]

    /// The layouts offered for `chart`: empty where its type has no measured list.
    static func layouts(for chart: Chart) -> [ChartQuickLayout] {
        switch chart.type {
        case .bar: return bar
        case .column: return column
        default: return []
        }
    }

    /// What the layout turns on, for its menu entry.
    var summary: String {
        var parts: [String] = []
        if title { parts.append("title") }
        if let legend { parts.append("legend " + (["r": "right", "t": "top", "b": "bottom", "l": "left"][legend] ?? legend)) }
        if valueTitle && categoryTitle { parts.append("axis titles") } else if valueTitle { parts.append("value axis title") }
        if !valueAxis { parts.append("no value axis") }
        if !valueGrid { parts.append("no gridlines") }
        switch labels {
        case .none: break
        case .all: parts.append("data labels")
        case .lastInside: parts.append("labels on the last series")
        }
        if dataTable { parts.append("data table") }
        return parts.isEmpty ? "no elements" : parts.joined(separator: ", ")
    }

    /// `chart` with this layout's elements.
    func applied(to chart: Chart) -> Chart {
        var c = chart
        c.title = title ? (c.title ?? (c.series.count == 1 ? c.series[0].name : "Chart Title")) : nil
        c.legend = legend != nil
        if let legend { c.legendPosition = legend }
        c.valueAxisTitle = valueTitle ? (c.valueAxisTitle ?? "Axis Title") : nil
        c.categoryAxisTitle = categoryTitle ? (c.categoryAxisTitle ?? "Axis Title") : nil
        c.valueGrid = valueGrid
        c.valueAxisDeleted = !valueAxis
        // (A table the chart already has keeps its own look.)
        c.dataTable = dataTable ? (c.dataTable ?? DataTable(size: 9, lineWidth: 0.75, squareKeys: true)) : nil
        c.gapWidth = gap
        if !c.stacked && !c.percent { c.overlap = overlap }
        c.dataLabels = labels != .none
        let last = c.series.count - 1
        for i in c.series.indices {
            switch labels {
            case .none:
                c.series[i].labelsShown = true; c.series[i].labelPos = nil; c.series[i].labelSize = nil
            case .all:
                c.series[i].labelsShown = true; c.series[i].labelPos = nil; c.series[i].labelSize = 9
            case .lastInside:
                c.series[i].labelsShown = i == last
                c.series[i].labelPos = i == last ? "inEnd" : nil
                c.series[i].labelSize = i == last ? 9 : nil
            }
        }
        return c
    }

    /// Whether `chart` already shows exactly this layout's elements.
    func matches(_ chart: Chart) -> Bool { applied(to: chart) == chart }
}
