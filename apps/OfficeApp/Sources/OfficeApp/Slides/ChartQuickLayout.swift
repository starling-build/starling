// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Chart Design > Quick Layout: the layouts of Office's gallery that set only the chart's elements (its title, legend and
// where the legend sits, axis titles, data labels). Each layout turns every one of those on or off, so applying one
// after another gives the same chart as applying the second alone; a title or axis title the chart already has keeps
// its text. Layouts that also hide an axis, add a data table or close the bar gaps are not offered.

struct ChartQuickLayout: Equatable {
    let name: String
    let title: Bool
    /// The legend's side ("r", "t", "b", "l"); nil where the layout has no legend.
    let legend: String?
    let axisTitles: Bool
    let dataLabels: Bool

    static let all: [ChartQuickLayout] = [
        ChartQuickLayout(name: "Layout 1", title: true, legend: "r", axisTitles: false, dataLabels: false),
        ChartQuickLayout(name: "Layout 3", title: true, legend: "b", axisTitles: false, dataLabels: false),
        ChartQuickLayout(name: "Layout 4", title: false, legend: "b", axisTitles: false, dataLabels: true),
        ChartQuickLayout(name: "Layout 7", title: false, legend: "r", axisTitles: true, dataLabels: false),
        ChartQuickLayout(name: "Layout 9", title: true, legend: "r", axisTitles: true, dataLabels: false),
        ChartQuickLayout(name: "Layout 11", title: false, legend: "r", axisTitles: false, dataLabels: false),
    ]

    /// What the layout turns on, for its menu entry.
    var summary: String {
        var parts: [String] = []
        if title { parts.append("title") }
        if let legend { parts.append("legend " + (["r": "right", "t": "top", "b": "bottom", "l": "left"][legend] ?? legend)) }
        if axisTitles { parts.append("axis titles") }
        if dataLabels { parts.append("data labels") }
        return parts.isEmpty ? "no elements" : parts.joined(separator: ", ")
    }

    /// `chart` with this layout's elements; axis titles only on a chart that has axes.
    func applied(to chart: Chart) -> Chart {
        var c = chart
        c.title = title ? (c.title ?? (c.series.count == 1 ? c.series[0].name : "Chart Title")) : nil
        c.legend = legend != nil
        if let legend { c.legendPosition = legend }
        if c.type.hasAxes {
            c.valueAxisTitle = axisTitles ? (c.valueAxisTitle ?? "Axis Title") : nil
            c.categoryAxisTitle = axisTitles ? (c.categoryAxisTitle ?? "Axis Title") : nil
        }
        c.dataLabels = dataLabels
        return c
    }

    /// Whether `chart` already shows exactly this layout's elements.
    func matches(_ chart: Chart) -> Bool { applied(to: chart) == chart }
}
