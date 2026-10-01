// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Pictures and charts a workbook carries, drawn over the grid. They are
// read from the sheet's drawing part (`xl/drawings/drawingN.xml`) for
// display only: the package keeps every drawing, chart and media part as
// it was, so a save writes them back untouched.
//
// A chart is Slides' `Chart`, read by the same `ChartXML`, but its numbers
// come from the cells its series point at (`Sheet1!$B$2:$B$5`) whenever
// they resolve — edit the data and the chart follows, as in Excel. The
// part's cached values stand in for a reference that does not resolve.
//
// Not yet: shapes and text boxes (`xdr:sp`), groups, and moving drawings
// or their references when rows and columns are inserted or deleted (the
// file's anchors would then disagree with the screen).

import Flutter
import FlutterSwiftBridge
import Foundation

/// Where a drawing sits: a cell corner plus an offset in points.
struct SheetMarker: Equatable, Sendable {
    var col: Int
    var colOff: Double
    var row: Int
    var rowOff: Double
}

enum SheetAnchor: Equatable, Sendable {
    /// Corner to corner, moving and sizing with the cells (Excel's default).
    case twoCell(from: SheetMarker, to: SheetMarker)
    /// A corner and a size in points.
    case oneCell(from: SheetMarker, width: Double, height: Double)
    /// A position and size in points from the sheet's top-left.
    case absolute(x: Double, y: Double, width: Double, height: Double)
}

/// A chart and the cells its series read.
struct SheetChart: Equatable {
    var chart: Chart
    /// Per series: the formula text of its name, categories and values.
    var refs: [(name: String?, cat: String?, val: String?)]

    static func == (a: SheetChart, b: SheetChart) -> Bool {
        a.chart == b.chart && a.refs.count == b.refs.count
            && zip(a.refs, b.refs).allSatisfy { $0.name == $1.name && $0.cat == $1.cat && $0.val == $1.val }
    }
}

struct SheetDrawing: Equatable {
    enum Kind: Equatable {
        /// The media part's path (the decode cache's key) and its bytes.
        case picture(path: String, data: Data)
        case chart(SheetChart)
    }
    var name: String
    var anchor: SheetAnchor
    var kind: Kind
}

enum SheetDrawingsXML {
    private static let emuPerPt = 12700.0

    /// The drawings on one sheet: its `drawing` relationship's part.
    static func read(sheetPath: String, parts: [String: Data], colors: ColorContext) -> [SheetDrawing] {
        let sheetRels = _relTargets(parts, of: sheetPath)
        guard let sheet = parts[sheetPath].flatMap({ XNode.parse($0) }),
              let rid = sheet.child("drawing")?["r:id"], let drawingPath = sheetRels[rid],
              let root = parts[drawingPath].flatMap({ XNode.parse($0) }) else { return [] }
        let rels = _relTargets(parts, of: drawingPath)
        var out: [SheetDrawing] = []
        for el in root.children {
            let anchor: SheetAnchor
            switch el.name.split(separator: ":").last ?? "" {
            case "twoCellAnchor":
                guard let from = el.child("from").flatMap(_marker), let to = el.child("to").flatMap(_marker) else { continue }
                anchor = .twoCell(from: from, to: to)
            case "oneCellAnchor":
                guard let from = el.child("from").flatMap(_marker), let ext = el.child("ext") else { continue }
                anchor = .oneCell(from: from, width: _emu(ext["cx"]), height: _emu(ext["cy"]))
            case "absoluteAnchor":
                guard let pos = el.child("pos"), let ext = el.child("ext") else { continue }
                anchor = .absolute(x: _emu(pos["x"]), y: _emu(pos["y"]), width: _emu(ext["cx"]), height: _emu(ext["cy"]))
            default: continue
            }
            if let pic = el.child("pic") {
                guard let embed = pic.child("blipFill")?.child("blip")?["r:embed"], let path = rels[embed],
                      let data = parts[path] else { continue }
                let name = pic.child("nvPicPr")?.child("cNvPr")?["name"] ?? "Picture"
                out.append(SheetDrawing(name: name, anchor: anchor, kind: .picture(path: path, data: data)))
            } else if let frame = el.child("graphicFrame") {
                guard let ref = _chartRef(frame), let path = rels[ref],
                      let space = parts[path].flatMap({ XNode.parse($0) }),
                      let chart = ChartXML.read(space, color: { colors.color(in: $0) }) else { continue }
                let name = frame.child("nvGraphicFramePr")?.child("cNvPr")?["name"] ?? "Chart"
                out.append(SheetDrawing(name: name, anchor: anchor, kind: .chart(SheetChart(chart: chart, refs: _refs(space)))))
            }
        }
        return out
    }

    /// The chart a graphic frame shows: `a:graphic/a:graphicData/c:chart@r:id`.
    private static func _chartRef(_ frame: XNode) -> String? {
        guard let data = frame.child("graphic")?.child("graphicData") else { return nil }
        return data.child("chart")?["r:id"]
    }

    private static func _refs(_ space: XNode) -> [(name: String?, cat: String?, val: String?)] {
        guard let plot = space.child("chart")?.child("plotArea"),
              let kind = plot.children.first(where: { $0.name.hasSuffix("Chart") }) else { return [] }
        return kind.kids("ser").map { ser in
            func f(_ el: XNode?) -> String? {
                guard let el else { return nil }
                for holder in ["numRef", "strRef", "multiLvlStrRef"] {
                    if let t = el.child(holder)?.child("f")?.text, !t.isEmpty { return t }
                }
                return nil
            }
            return (f(ser.child("tx")), f(ser.child("cat") ?? ser.child("xVal")), f(ser.child("val") ?? ser.child("yVal")))
        }
    }

    private static func _marker(_ n: XNode) -> SheetMarker? {
        guard let col = Int(n.child("col")?.text ?? ""), let row = Int(n.child("row")?.text ?? "") else { return nil }
        return SheetMarker(col: col, colOff: _emu(n.child("colOff")?.text), row: row, rowOff: _emu(n.child("rowOff")?.text))
    }

    private static func _emu(_ s: String?) -> Double { (Double(s ?? "") ?? 0) / emuPerPt }

    /// A part's relationships: id → resolved part path.
    static func _relTargets(_ parts: [String: Data], of part: String) -> [String: String] {
        let dir = part.deletingLastPathComponent
        return Xlsx._rels(parts[Xlsx._relsPath(part)], base: dir.isEmpty ? "" : dir + "/")
    }
}

/// The theme a workbook's charts draw with: its colours and body font.
extension DeckTheme {
    /// Office's default theme (2013–2022), what a workbook without one uses.
    static let office: DeckTheme = {
        var t = DeckTheme()
        t.name = "Office"
        t.text = Color(0xFF000000)
        t.accents = [Color(0xFF4472C4), Color(0xFFED7D31), Color(0xFFA5A5A5),
                     Color(0xFFFFC000), Color(0xFF5B9BD5), Color(0xFF70AD47)]
        return t
    }()

    init(xlsxTheme root: XNode?) {
        self = .office
        let t = PptxTheme(root)
        if let dk = t.colors["dk1"] { text = dk }
        if let lt = t.colors["lt1"] { background = lt }
        bodyFont = t.minor
        headingFont = t.major
        let accents = (1 ... 6).compactMap { t.colors["accent\($0)"] }
        if accents.count == 6 { self.accents = accents }
    }
}

extension WorkbookController {
    /// A chart with its series' numbers, names and categories read from
    /// the cells they reference, where those resolve.
    func liveChart(_ sc: SheetChart) -> Chart {
        var c = sc.chart
        for (i, ref) in sc.refs.enumerated() where i < c.series.count {
            if let f = ref.val, let cells = _refValues(f) {
                c.series[i].values = cells.map { $0.number }
            }
            if let f = ref.name, let cells = _refValues(f), let first = cells.first {
                c.series[i].name = _shown(first)
            }
            if i == 0, let f = ref.cat, let cells = _refValues(f) {
                c.categories = cells.map(_shown)
            }
        }
        let n = max(c.categories.count, c.series.map(\.values.count).max() ?? 0)
        if c.categories.count < n { c.categories += (c.categories.count ..< n).map { "\($0 + 1)" } }
        for i in c.series.indices where c.series[i].values.count < n {
            c.series[i].values += Array(repeating: nil, count: n - c.series[i].values.count)
        }
        return c
    }

    private func _shown(_ v: CellValue) -> String {
        NumberFormat.display(v, "General", width: 255).text
    }

    /// The values of `Sheet1!$B$2:$B$5`, row by row, or nil when it does
    /// not name a range on a sheet of this workbook.
    func _refValues(_ formula: String) -> [CellValue]? {
        guard let expr = try? Formula.parse("=" + formula), case .ref(let r) = expr, let name = r.sheet,
              let si = book.sheets.firstIndex(where: { $0.name.lowercased() == name.lowercased() }) else { return nil }
        let range = r.range
        guard range.rows * range.cols <= 10_000 else { return nil }
        return engine.values(si, range, includeEmpty: true)
    }
}
