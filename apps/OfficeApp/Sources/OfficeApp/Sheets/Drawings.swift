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
// Shapes, text boxes and groups are SheetShapes.swift. Anchors follow
// inserted and deleted rows and columns (Restructure.swift), and a moved
// or resized drawing has its anchor rewritten on save.

import Flutter
import OfficeText
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
    /// The chart part it was read from; nil for one made here, whose part
    /// is written from `chart` and `refs` on save.
    var path: String? = nil
    /// Every `<c:f>` in that part (series, titles, labels…): as read → as
    /// it reads now, after rows, columns or sheets moved. A save rewrites
    /// the part's references through it and keeps everything else.
    var formulas: [String: String] = [:]
    var formulasChanged: Bool { formulas.contains { $0.key != $0.value } }
    /// The category axis' own number format, where it is not its source's
    /// (`sourceLinked="0"`): live categories are shown in it rather than
    /// in their cells' formats.
    var categoryFormat: String? = nil
    /// A pivot chart (`c:pivotSource`): drawn from its cache, which holds
    /// the pivot's rows without its totals. Its references run over the
    /// table's cells, grand total included: lo-forum-mso-de-104083's 53
    /// weeks read live as 54 bars, the last the year's total, and every
    /// week stood a sliver under an axis twenty times too tall.
    var pivot = false

    static func == (a: SheetChart, b: SheetChart) -> Bool {
        a.chart == b.chart && a.path == b.path && a.formulas == b.formulas && a.refs.count == b.refs.count
            && zip(a.refs, b.refs).allSatisfy { $0.name == $1.name && $0.cat == $1.cat && $0.val == $1.val }
    }
}

struct SheetDrawing: Equatable {
    enum Kind: Equatable {
        /// The media part's path (the decode cache's key) and its bytes.
        case picture(path: String, data: Data)
        case chart(SheetChart)
        /// A shape or text box (its XML always written back as read).
        case shape(SheetShape)
        /// A group or anything else not modelled: not
        /// drawn, and written back exactly as read.
        case other
    }
    var name: String
    var anchor: SheetAnchor
    var kind: Kind
    /// The anchor element as the file wrote it, and the anchor it had then:
    /// written back verbatim while the drawing has not moved.
    var raw: String? = nil
    var rawAnchor: SheetAnchor? = nil
    /// The drawing part's relationship to its picture or chart.
    var relId: String? = nil
    /// `cNvPr@hidden`: in the file, and neither drawn nor printed.
    var hidden = false
    /// `clientData@fPrintsWithSheet` false: drawn on screen, left off paper
    /// (lo-tdf91332's green freeform, which Excel's print has not).
    /// A picture's crop (`a:srcRect`): the share of the image cut from
    /// its left, top, right and bottom — lo-cell-anchored-hidden-shapes'
    /// logo is the middle quarter of its image.
    var crop: [Double]? = nil
    /// A picture's turn (`a:xfrm@rot`), in degrees clockwise.
    var rotation = 0.0
    var screenOnly = false

    var isChart: Bool { if case .chart = kind { return true } else { return false } }
}

enum SheetDrawingsXML {
    private static let emuPerPt = 12700.0

    /// The drawings on one sheet (its `drawing` relationship's part), and
    /// that part's path and root tag.
    static func read(sheetPath: String, parts: [String: Data], colors: ColorContext, sheet: XNode? = nil)
        -> (drawings: [SheetDrawing], part: String?, root: String?) {
        let sheetRels = _relTargets(parts, of: sheetPath)
        guard let sheet = sheet ?? parts[sheetPath].flatMap({ XNode.parse($0) }),
              let rid = sheet.child("drawing")?["r:id"], let drawingPath = sheetRels[rid],
              let bytes = parts[drawingPath], let root = XNode.parse(bytes) else { return ([], nil, nil) }
        let rels = _relTargets(parts, of: drawingPath)
        let split = RawXML.split([UInt8](bytes))
        let raws = split.children.count == root.children.count ? split.children.map(\.text) : nil
        var out: [SheetDrawing] = []
        for (index, el) in root.children.enumerated() {
            let raw = raws?[index]
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
            default:
                // mc:AlternateContent and the like: kept, never drawn or moved.
                if let raw { out.append(SheetDrawing(name: "", anchor: .absolute(x: 0, y: 0, width: 0, height: 0), kind: .other, raw: raw)) }
                continue
            }
            var d = SheetDrawing(name: "", anchor: anchor, kind: .other, raw: raw, rawAnchor: anchor)
            if let pic = el.child("pic"), let embed = pic.child("blipFill")?.child("blip")?["r:embed"],
               let path = rels[embed], let data = parts[path] {
                d.name = pic.child("nvPicPr")?.child("cNvPr")?["name"] ?? "Picture"
                d.kind = .picture(path: path, data: data)
                d.relId = embed
                d.rotation = (Double(pic.child("spPr")?.child("xfrm")?["rot"] ?? "") ?? 0) / 60_000
                if let src = pic.child("blipFill")?.child("srcRect") {
                    let c = ["l", "t", "r", "b"].map { max(0, Double(src[$0] ?? "") ?? 0) / 100_000 }
                    if c.contains(where: { $0 > 0 }), c[0] + c[2] < 1, c[1] + c[3] < 1 { d.crop = c }
                }
            } else if let frame = el.child("graphicFrame") ?? el.child("AlternateContent")?.child("Choice")?.child("graphicFrame"),
                      let ref = _chartRef(frame), let path = rels[ref],
                      let space = parts[path].flatMap({ XNode.parse($0) }).map(ChartXML.canonical),
                      // (An Excel 2016 chart, `cx:`, stands in mc:Choice with
                      // its picture in mc:Fallback: chart-clusteredColumn's.)
                      let chart = space.name.hasSuffix("chartSpace") && space.name.hasPrefix("cx:")
                        ? ChartXML.readChartex(space, color: { colors.color(in: $0) }) : ChartXML.read(space, allowEmpty: true, color: { colors.color(in: $0) }) {
                d.name = frame.child("nvGraphicFramePr")?.child("cNvPr")?["name"] ?? "Chart"
                var sc = SheetChart(chart: chart, refs: space.name.hasPrefix("cx:") ? _chartexRefs(space) : _refs(space), path: path)
                let axis = space.descendant("c:catAx")?.first("c:numFmt") ?? space.descendant("c:dateAx")?.first("c:numFmt")
                sc.pivot = space.descendant("c:pivotSource") != nil
                sc.categoryFormat = axis.flatMap { ["0", "false"].contains($0["sourceLinked"] ?? "1") ? $0["formatCode"] : nil }
                for f in _formulas(space) { sc.formulas[f] = f }
                d.kind = .chart(sc)
                d.relId = ref
            } else if let sp = el.child("sp") ?? el.child("cxnSp") {
                d.name = (sp.child("nvSpPr") ?? sp.child("nvCxnSpPr"))?.child("cNvPr")?["name"] ?? "Shape"
                d.kind = .shape(SheetShape.read(sp, colors: colors))
            } else if let grp = el.child("grpSp") {
                d.name = grp.child("nvGrpSpPr")?.child("cNvPr")?["name"] ?? "Group"
                d.kind = .shape(SheetShape.readGroup(grp, colors: colors))
            } else if raw == nil {
                continue
            }
            let named = (el.child("pic")?.child("nvPicPr") ?? el.child("graphicFrame")?.child("nvGraphicFramePr")
                ?? el.child("sp")?.child("nvSpPr") ?? el.child("cxnSp")?.child("nvCxnSpPr") ?? el.child("grpSp")?.child("nvGrpSpPr"))?.child("cNvPr")
            d.hidden = named?["hidden"] == "1" || named?["hidden"] == "true"
            if let p = el.child("clientData")?["fPrintsWithSheet"], p == "0" || p == "false" { d.screenOnly = true }
            out.append(d)
        }
        return (out, drawingPath, split.rootStart)
    }

    /// The text of every `c:f` in a chart part.
    private static func _formulas(_ n: XNode) -> [String] {
        var out: [String] = []
        func walk(_ n: XNode) {
            if n.name == "c:f" || n.name.hasSuffix(":f") && n.name.hasPrefix("c") { if !n.text.isEmpty { out.append(n.text) } }
            for c in n.children { walk(c) }
        }
        walk(n)
        return out
    }

    /// The chart a graphic frame shows: `a:graphic/a:graphicData/c:chart@r:id`.
    private static func _chartRef(_ frame: XNode) -> String? {
        guard let data = frame.child("graphic")?.child("graphicData") else { return nil }
        return data.child("chart")?["r:id"]
    }

    /// A `cx:` chart's series' formulas: each one's data's values and
    /// categories (`cx:numDim`, `cx:strDim`), often a hidden defined name
    /// (`_xlchart.v1.0`).
    private static func _chartexRefs(_ space: XNode) -> [(name: String?, cat: String?, val: String?)] {
        var data: [String: XNode] = [:]
        for d in space.first("cx:chartData")?.all("cx:data") ?? [] { data[d["id"] ?? ""] = d }
        let series = space.first("cx:chart")?.first("cx:plotArea")?.first("cx:plotAreaRegion")?.all("cx:series") ?? []
        return series.map { ser in
            let d = data[ser.first("cx:dataId")?["val"] ?? ""]
            func f(_ dims: [XNode]?, _ type: String) -> String? {
                dims?.first { $0["type"] == type }?.first("cx:f")?.text
            }
            let dims = (d?.all("cx:numDim") ?? []) + (d?.all("cx:strDim") ?? [])
            // (A sunburst's or treemap's values are its sizes.)
            return (ser.first("cx:tx")?.first("cx:txData")?.first("cx:f")?.text, f(dims, "cat"), f(dims, "val") ?? f(dims, "size"))
        }
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

    static func _marker(_ n: XNode) -> SheetMarker? {
        guard let col = Int(n.child("col")?.text ?? ""), let row = Int(n.child("row")?.text ?? "") else { return nil }
        return SheetMarker(col: col, colOff: _emu(n.child("colOff")?.text), row: row, rowOff: _emu(n.child("rowOff")?.text))
    }

    private static func _emu(_ s: String?) -> Double { (Double(s ?? "") ?? 0) / emuPerPt }

    /// A part's relationships: id → resolved part path.
    static func _relTargets(_ parts: [String: Data], of part: String) -> [String: String] {
        let dir = part.deletingLastPathComponent
        return Xlsx._rels(Xlsx._part(parts, Xlsx._relsPath(part)), base: dir.isEmpty ? "" : dir + "/")
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

extension SheetChart {
    /// The chart with its series' numbers, names and categories read from
    /// the cells they reference, where those resolve.
    func live(book: Workbook, engine: CalcEngine) -> Chart {
        var c = chart
        if pivot { return c }
        func resolve(_ formula: String) -> (sheet: Int, range: CellRange)? {
            // (Or a defined name for one: a `cx:` chart's _xlchart.v1.0.)
            let formula = book.names[formula.uppercased()] ?? formula
            guard let expr = try? Formula.parse("=" + formula), case .ref(let r) = expr, let name = r.sheet,
                  let si = book.sheet(named: name) else { return nil }
            guard r.range.rows * r.range.cols <= 10_000 else { return nil }
            return (si, r.range)
        }
        func values(_ formula: String) -> [CellValue]? {
            guard let (si, range) = resolve(formula) else { return nil }
            return engine.values(si, range, includeEmpty: true)
        }
        func shown(_ v: CellValue) -> String { NumberFormat.display(v, "General", width: 255).text }
        // Names and categories as their cells show them: lo-forum-mso-de-
        // 104083's weeks are 1-53 under "KW "00, labelled KW 01-KW 53 by
        // Excel (its cache says so) and 1-53 by ours.
        // (A scatter chart's x are numbers, read back from these; an axis
        // with its own format shows them in that, as the cache path does.)
        func shownCells(_ formula: String, own: String? = nil) -> [String]? {
            guard let (si, range) = resolve(formula) else { return nil }
            if c.type == .scatter { return engine.values(si, range, includeEmpty: true).map(shown) }
            let ws = book.sheets[si]
            let cells = engine.values(si, range, includeEmpty: true)
            var out: [String] = [], k = 0
            for row in range.top ... range.bottom {
                for col in range.left ... range.right where k < cells.count {
                    let a = CellAddress(row: row, col: col)
                    let code = own ?? book.style(ws.cells[a]?.style ?? ws.defaultStyle(at: a)).numberFormat
                    out.append(NumberFormat.display(cells[k], code, width: 255).text.trimmingWhitespace())
                    k += 1
                }
            }
            return out
        }
        // A box-and-whisker chart's boxes from its cells: each series'
        // values grouped by the category beside each, the categories in
        // the order they first come.
        // A sunburst's tree from its cells: a column to each level, top
        // first; a level left blank under a name is still that name (the
        // way its table is written, each parent once), and a row ends at
        // its first blank after that (chart-sunburst's Best / First / A…).
        if c.sunburst != nil, let ref = refs.first, let cf = ref.cat, let vf = ref.val,
           let (si, range) = resolve(cf), let sizes = values(vf) {
            let cells = engine.values(si, range, includeEmpty: true)
            let width = range.right - range.left + 1
            var paths: [[String]] = [], prev: [String] = []
            for r in 0 ..< range.bottom - range.top + 1 {
                let row = (0 ..< width).map { j in cells[safe: r * width + j].map(shown)?.trimmingWhitespace() ?? "" }
                guard let first = row.firstIndex(where: { !$0.isEmpty }) else { paths.append([]); continue }
                var path = Array(prev.prefix(first))
                for name in row[first...] { if name.isEmpty { break }; path.append(name) }
                paths.append(path)
                prev = path
            }
            c.sunburst = ChartXML.sunburstTree(paths: paths, values: sizes.map { $0.number ?? 0 })
            c.categories = c.sunburst?.map(\.name) ?? []
            if !c.series.isEmpty { c.series[0].values = c.sunburst?.map(\.value) ?? [] }
            return c
        }
        if c.boxes != nil {
            var categories: [String] = []
            var grouped: [[String: [Double]]] = []
            for (i, ref) in refs.enumerated() where i < c.series.count {
                var by: [String: [Double]] = [:]
                if let f = ref.val, let cells = values(f) {
                    let cats = ref.cat.flatMap { shownCells($0) } ?? []
                    for (k, v) in cells.enumerated() {
                        guard let n = v.number, n.isFinite else { continue }
                        let name = cats[safe: k] ?? ""
                        if !categories.contains(name) { categories.append(name) }
                        by[name, default: []].append(n)
                    }
                }
                if let f = ref.name, let cells = shownCells(f), let first = cells.first { c.series[i].name = first }
                grouped.append(by)
            }
            if !categories.isEmpty {
                c.categories = categories
                c.boxes = grouped.map { by in categories.map { (by[$0] ?? []).sorted() } }
                for (i, by) in grouped.enumerated() where i < c.series.count {
                    c.series[i].values = categories.map { (by[$0] ?? []).isEmpty ? nil : ChartXML.quartile((by[$0] ?? []).sorted(), 0.5, inclusive: false) }
                }
            } else if c.categories.isEmpty {
                // (Nothing cached and nothing read: no boxes to draw.)
                c.series = []
            }
            return c
        }
        // A histogram's samples counted into its bins.
        if c.histogram != nil {
            if let f = refs.first?.val, let cells = values(f) { c.applyHistogram(cells.compactMap { $0.number }) }
            return c
        }
        for (i, ref) in refs.enumerated() where i < c.series.count {
            if let f = ref.val, let cells = values(f) { c.series[i].values = cells.map { $0.number } }
            if let f = ref.name, let cells = shownCells(f), let first = cells.first { c.series[i].name = first }
            if i == 0, let f = ref.cat, let cells = shownCells(f, own: categoryFormat) { c.categories = cells }
        }
        let n = max(c.categories.count, c.series.map(\.values.count).max() ?? 0)
        if c.categories.count < n { c.categories += (c.categories.count ..< n).map { "\($0 + 1)" } }
        for i in c.series.indices where c.series[i].values.count < n {
            c.series[i].values += Array(repeating: nil, count: n - c.series[i].values.count)
        }
        return c
    }
}

extension WorkbookController {
    func liveChart(_ sc: SheetChart) -> Chart { sc.live(book: book, engine: engine) }
}

// MARK: - Writing

/// What saving one sheet's edited drawings adds to the package.
struct DrawingParts {
    var parts: [String: Data] = [:]
    /// Content-type overrides for new parts.
    var overrides: [(String, String)] = []
    /// Parts to leave out (a drawing part whose drawings were all deleted).
    var dropped: Set<String> = []
    /// The sheet's `<drawing>` element: nil keeps the kept one, "" drops it.
    var element: String? = nil
}

extension SheetDrawingsXML {
    static let drawingType = "application/vnd.openxmlformats-officedocument.drawing+xml"
    static let chartType = "application/vnd.openxmlformats-officedocument.drawingml.chart+xml"
    private static let relBase = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    private static let ns = "xmlns:xdr=\"http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\""

    /// The parts for a sheet whose drawings changed here. `taken` holds
    /// every part name already in use and gains the new ones.
    static func write(_ ws: Worksheet, sheetPath: String, live: (SheetChart) -> Chart,
                      original: [String: Data], taken: inout Set<String>,
                      sheetRels: inout [(id: String, type: String, target: String)], relsChanged: inout Bool) -> DrawingParts {
        var out = DrawingParts()
        guard ws.drawingsEdited else { return out }
        let existing = sheetRels.first { $0.type.hasSuffix("/drawing") }
        if ws.drawings.isEmpty {
            if let existing, let part = ws.drawingPart {
                sheetRels.removeAll { $0.id == existing.id }
                relsChanged = true
                out.dropped = [part, Xlsx._relsPath(part)]
            }
            out.element = ""
            return out
        }
        func fresh(_ dir: String, _ stem: String) -> String {
            var n = 1
            while taken.contains("\(dir)\(stem)\(n).xml") || original["\(dir)\(stem)\(n).xml"] != nil { n += 1 }
            let p = "\(dir)\(stem)\(n).xml"
            taken.insert(p)
            return p
        }
        let partIsNew = ws.drawingPart == nil || existing == nil
        let part = partIsNew ? fresh("xl/drawings/", "drawing") : ws.drawingPart!
        var rels = partIsNew ? [] : Xlsx._relList(original[Xlsx._relsPath(part)])
        func relTo(_ type: String, _ target: String) -> String {
            let rel = "../" + String(target.dropFirst("xl/".count))
            if let r = rels.first(where: { $0.type.hasSuffix("/" + type) && $0.target == rel }) { return r.id }
            let id = Xlsx._freshId(rels)
            rels.append((id, "\(relBase)/\(type)", rel))
            return id
        }
        var body = ""
        var shapeId = 2
        for d in ws.drawings {
            shapeId += 1
            if case .chart(let sc) = d.kind, let path = sc.path, sc.formulasChanged, let bytes = original[path] {
                // The file's own chart, its references moved with the cells.
                out.parts[path] = Data(_rewriteFormulas(String(decoding: bytes, as: UTF8.self), sc.formulas).utf8)
            }
            if let raw = d.raw {
                if d.kind == .other || d.rawAnchor == d.anchor {
                    body += raw
                    continue
                }
                // Moved: the file's own anchor element, with new corners.
                if case .twoCell(let from, let to) = d.anchor, let patched = _patchMarkers(raw, from, to) {
                    body += patched
                    continue
                }
            }
            let name = Xlsx._esc(d.name.isEmpty ? (d.isChart ? "Chart \(shapeId)" : "Picture \(shapeId)") : d.name)
            var content: String
            switch d.kind {
            case .other, .shape: continue      // kept by their raw text above
            case .picture(let path, _):
                let id = d.relId.flatMap { id in rels.contains { $0.id == id } ? id : nil } ?? relTo("image", path)
                content = "<xdr:pic><xdr:nvPicPr><xdr:cNvPr id=\"\(shapeId)\" name=\"\(name)\"/><xdr:cNvPicPr><a:picLocks noChangeAspect=\"1\"/></xdr:cNvPicPr></xdr:nvPicPr>"
                    + "<xdr:blipFill><a:blip r:embed=\"\(id)\"/><a:stretch><a:fillRect/></a:stretch></xdr:blipFill>"
                    + "<xdr:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"0\" cy=\"0\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></xdr:spPr></xdr:pic>"
            case .chart(let sc):
                let id: String
                if sc.path != nil, let rid = d.relId, rels.contains(where: { $0.id == rid }) {
                    id = rid
                } else {
                    let chartPath = fresh("xl/charts/", "chart")
                    out.parts[chartPath] = Data(chartSpace(sc, live: live(sc)).utf8)
                    out.overrides.append(("/" + chartPath, chartType))
                    id = relTo("chart", chartPath)
                }
                content = "<xdr:graphicFrame macro=\"\"><xdr:nvGraphicFramePr><xdr:cNvPr id=\"\(shapeId)\" name=\"\(name)\"/><xdr:cNvGraphicFramePr/></xdr:nvGraphicFramePr>"
                    + "<xdr:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"0\" cy=\"0\"/></xdr:xfrm><a:graphic><a:graphicData uri=\"http://schemas.openxmlformats.org/drawingml/2006/chart\">"
                    + "<c:chart xmlns:c=\"http://schemas.openxmlformats.org/drawingml/2006/chart\" r:id=\"\(id)\"/></a:graphicData></a:graphic></xdr:graphicFrame>"
            }
            body += _anchorXML(d.anchor, content: content)
        }
        let root = (partIsNew ? nil : ws.drawingRoot) ?? "<xdr:wsDr \(ns)>"
        let rootName = root.dropFirst().prefix { !" >\n\t\r/".contains($0) }
        out.parts[part] = Data(("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n" + root + body + "</\(rootName)>").utf8)
        out.parts[Xlsx._relsPath(part)] = Data(Xlsx._relsXML(rels).utf8)
        if partIsNew {
            out.overrides.append(("/" + part, drawingType))
            let id = Xlsx._freshId(sheetRels)
            sheetRels.removeAll { $0.type.hasSuffix("/drawing") }
            sheetRels.append((id, "\(relBase)/drawing", "../" + String(part.dropFirst("xl/".count))))
            relsChanged = true
            out.element = "<drawing xmlns:r=\"\(relBase)\" r:id=\"\(id)\"/>"
        }
        return out
    }

    /// `raw` (a twoCellAnchor) with its from/to markers replaced; nil when
    /// it is not a corner-to-corner anchor.
    static func _patchMarkers(_ raw: String, _ from: SheetMarker, _ to: SheetMarker) -> String? {
        let tag = raw.dropFirst().prefix { !" >\n\t\r/".contains($0) }
        guard tag.hasSuffix("twoCellAnchor") else { return nil }
        let prefix = tag.containsSubstring(":") ? String(tag.split(separator: ":")[0]) + ":" : ""
        func marker(_ name: String, _ m: SheetMarker) -> String {
            "<\(prefix)\(name)><\(prefix)col>\(m.col)</\(prefix)col><\(prefix)colOff>\(Int((m.colOff * emuPerPt).rounded()))</\(prefix)colOff>"
                + "<\(prefix)row>\(m.row)</\(prefix)row><\(prefix)rowOff>\(Int((m.rowOff * emuPerPt).rounded()))</\(prefix)rowOff></\(prefix)\(name)>"
        }
        var s = raw
        for (name, m) in [("from", from), ("to", to)] {
            guard let a = s.findRange(of: "<\(prefix)\(name)>"), let b = s.findRange(of: "</\(prefix)\(name)>", in: a.upperBound ..< s.endIndex) else { return nil }
            s.replaceSubrange(a.lowerBound ..< b.upperBound, with: marker(name, m))
        }
        return s
    }

    /// A chart part with each `<c:f>` mapped through `formulas`.
    static func _rewriteFormulas(_ xml: String, _ formulas: [String: String]) -> String {
        var out = ""
        var at = xml.startIndex
        while let a = xml.findRange(of: "<c:f>", in: at ..< xml.endIndex),
              let b = xml.findRange(of: "</c:f>", in: a.upperBound ..< xml.endIndex) {
            let inner = String(xml[a.upperBound ..< b.lowerBound])
            let text = inner.replacingAll("&lt;", with: "<").replacingAll("&gt;", with: ">").replacingAll("&quot;", with: "\"")
                .replacingAll("&apos;", with: "'").replacingAll("&amp;", with: "&")
            out += xml[at ..< a.upperBound]
            out += formulas[text].map { $0 == text ? inner : Xlsx._esc($0) } ?? inner
            at = b.lowerBound
        }
        return out + xml[at...]
    }

    /// Corner to corner, moving and sizing with its cells (Excel's default
    /// for a chart; a moved picture keeps its aspect through its locks).
    private static func _anchorXML(_ a: SheetAnchor, content: String) -> String {
        func marker(_ tag: String, _ m: SheetMarker) -> String {
            "<xdr:\(tag)><xdr:col>\(m.col)</xdr:col><xdr:colOff>\(Int((m.colOff * emuPerPt).rounded()))</xdr:colOff>"
                + "<xdr:row>\(m.row)</xdr:row><xdr:rowOff>\(Int((m.rowOff * emuPerPt).rounded()))</xdr:rowOff></xdr:\(tag)>"
        }
        switch a {
        case .twoCell(let from, let to):
            return "<xdr:twoCellAnchor \(ns)>" + marker("from", from) + marker("to", to) + content + "<xdr:clientData/></xdr:twoCellAnchor>"
        case .oneCell(let from, let w, let h):
            return "<xdr:oneCellAnchor \(ns)>" + marker("from", from)
                + "<xdr:ext cx=\"\(Int((w * emuPerPt).rounded()))\" cy=\"\(Int((h * emuPerPt).rounded()))\"/>" + content + "<xdr:clientData/></xdr:oneCellAnchor>"
        case .absolute(let x, let y, let w, let h):
            return "<xdr:absoluteAnchor \(ns)><xdr:pos x=\"\(Int((x * emuPerPt).rounded()))\" y=\"\(Int((y * emuPerPt).rounded()))\"/>"
                + "<xdr:ext cx=\"\(Int((w * emuPerPt).rounded()))\" cy=\"\(Int((h * emuPerPt).rounded()))\"/>" + content + "<xdr:clientData/></xdr:absoluteAnchor>"
        }
    }

    /// A chart part for a workbook: Slides' writer, pointed at the chart's
    /// own cells instead of an embedded table, at Excel's text sizes, and
    /// with Excel's white, outlined chart area.
    static func chartSpace(_ sc: SheetChart, live: Chart) -> String {
        var x = ChartXML.chartSpace(live)
        if let a = x.findRange(of: "<c:externalData"), let b = x.findRange(of: "</c:externalData>") {
            x.removeSubrange(a.lowerBound ..< b.upperBound)
        }
        // (Excel's chart area for one that has none of its own, or the bare
        // one Slides' writer gives a chart of this app's.)
        let excelArea = "<c:spPr><a:solidFill><a:schemeClr val=\"bg1\"/></a:solidFill><a:ln w=\"9525\" cap=\"flat\" cmpd=\"sng\" algn=\"ctr\"><a:solidFill><a:schemeClr val=\"tx1\"><a:lumMod val=\"15000\"/><a:lumOff val=\"85000\"/></a:schemeClr></a:solidFill><a:round/></a:ln></c:spPr>"
        if x.containsSubstring("</c:chart><c:spPr><a:noFill/><a:ln><a:noFill/></a:ln></c:spPr>") {
            x = x.replacingAll("</c:chart><c:spPr><a:noFill/><a:ln><a:noFill/></a:ln></c:spPr>", with: "</c:chart>" + excelArea)
        } else if !x.containsSubstring("</c:chart><c:spPr>") {
            x = x.replacingAll("</c:chart>", with: "</c:chart>" + excelArea)
        }
        x = x.replacingAll("sz=\"1862\"", with: "sz=\"1400\"").replacingAll("sz=\"1330\"", with: "sz=\"1000\"")
            .replacingAll("sz=\"1200\"", with: "sz=\"900\"")
        // Each series in turn: its name, categories and values.
        var out = ""
        var at = x.startIndex
        var i = 0
        while let open = x.findRange(of: "<c:ser>", in: at ..< x.endIndex),
              let close = x.findRange(of: "</c:ser>", in: open.upperBound ..< x.endIndex) {
            out += x[at ..< open.lowerBound]
            var ser = String(x[open.lowerBound ..< close.upperBound])
            let ref = i < sc.refs.count ? sc.refs[i] : (name: nil, cat: nil, val: nil)
            if let f = ref.name { ser = _setF(ser, in: "c:tx", f) }
            else if i < live.series.count { ser = _replace(ser, "c:tx", with: "<c:tx><c:v>\(Xlsx._esc(live.series[i].name))</c:v></c:tx>") }
            for tag in ["c:cat", "c:xVal"] where ser.containsSubstring("<\(tag)>") {
                if let f = ref.cat { ser = _setF(ser, in: tag, f) } else { ser = _replace(ser, tag, with: "") }
            }
            for tag in ["c:val", "c:yVal"] where ser.containsSubstring("<\(tag)>") {
                if let f = ref.val { ser = _setF(ser, in: tag, f) }
            }
            out += ser
            at = close.upperBound
            i += 1
        }
        return out + x[at...]
    }

    /// `<tag>…<c:f>old</c:f>…</tag>` with `f` in place of old.
    private static func _setF(_ s: String, in tag: String, _ f: String) -> String {
        guard let t = s.findRange(of: "<\(tag)>"), let a = s.findRange(of: "<c:f>", in: t.upperBound ..< s.endIndex),
              let b = s.findRange(of: "</c:f>", in: a.upperBound ..< s.endIndex) else { return s }
        return String(s[..<a.upperBound]) + Xlsx._esc(f) + String(s[b.lowerBound...])
    }

    private static func _replace(_ s: String, _ tag: String, with new: String) -> String {
        guard let a = s.findRange(of: "<\(tag)>"), let b = s.findRange(of: "</\(tag)>", in: a.upperBound ..< s.endIndex) else { return s }
        return String(s[..<a.lowerBound]) + new + String(s[b.upperBound...])
    }
}

// MARK: - Editing

extension Worksheet {
    /// The cell corner plus offset at a point (in points from A1's corner).
    func marker(x: Double, y: Double) -> SheetMarker {
        func walk(_ v: Double, _ size: (Int) -> Double, _ limit: Int) -> (Int, Double) {
            var i = 0, at = 0.0
            while i < limit - 1 {
                let s = size(i)
                if v < at + s { break }   // a hidden (0) one never holds a point
                at += s
                i += 1
            }
            return (i, max(0, v - at))
        }
        let (c, dx) = walk(max(0, x), { self.isColHidden($0) ? 0 : self.colWidth($0) }, CellAddress.maxCols)
        let (r, dy) = walk(max(0, y), { self.isRowHidden($0) ? 0 : self.rowHeight($0) }, CellAddress.maxRows)
        return SheetMarker(col: c, colOff: dx, row: r, rowOff: dy)
    }

    /// Where a marker is, in points from A1's corner.
    func point(_ m: SheetMarker) -> (x: Double, y: Double) {
        // (An offset past its cell's far edge stops there, as Excel's does.)
        var x = isColHidden(m.col) ? 0 : min(m.colOff, colWidth(m.col))
        var y = isRowHidden(m.row) ? 0 : min(m.rowOff, rowHeight(m.row))
        for c in 0 ..< m.col where !isColHidden(c) { x += colWidth(c) }
        for r in 0 ..< m.row where !isRowHidden(r) { y += rowHeight(r) }
        return (x, y)
    }

    /// A drawing's frame in points from A1's corner.
    func frame(_ a: SheetAnchor) -> (x: Double, y: Double, width: Double, height: Double) {
        switch a {
        case .twoCell(let from, let to):
            let p = point(from), q = point(to)
            return (p.x, p.y, max(0, q.x - p.x), max(0, q.y - p.y))
        case .oneCell(let from, let w, let h):
            let p = point(from)
            return (p.x, p.y, w, h)
        case .absolute(let x, let y, let w, let h):
            return (x, y, w, h)
        }
    }

    /// The anchor for a frame in points: corner to corner.
    func anchor(x: Double, y: Double, width: Double, height: Double) -> SheetAnchor {
        .twoCell(from: marker(x: x, y: y), to: marker(x: x + width, y: y + height))
    }
}

extension WorkbookController {
    /// Insert → Chart: the selection (or the table around the active cell)
    /// as a chart of `type`, Excel's way — a text top row names the series,
    /// a text first column gives the categories, series run down the
    /// longer side — placed beside the data and selected.
    @discardableResult
    func insertChart(_ type: ChartType) -> Bool {
        let ws = sheet
        var r = selection.isSingle ? currentRegion(active) : selection
        let used = ws.usedExtent
        r = CellRange(top: r.top, left: r.left, bottom: max(r.top, min(r.bottom, used.row)), right: max(r.left, min(r.right, used.col)))
        func v(_ row: Int, _ col: Int) -> CellValue { ws.value(CellAddress(row: row, col: col)) }
        let hasHeader = r.rows > 1 && (r.left ... r.right).allSatisfy { v(r.top, $0).isText || v(r.top, $0).isEmpty }
        let dataTop = hasHeader ? r.top + 1 : r.top
        let firstColLabels = r.cols > 1 && (type == .scatter
            || (dataTop ... r.bottom).allSatisfy { v($0, r.left).isText || v($0, r.left).isEmpty })
        let dataLeft = firstColLabels ? r.left + 1 : r.left
        guard (dataTop ... r.bottom).contains(where: { row in (dataLeft ... r.right).contains { v(row, $0).number != nil } }) else {
            onCommand?(.status("Select a range with numbers to chart"))
            return false
        }
        let sheetName = Formula.quoteSheet(ws.name) + "!"
        func cell(_ row: Int, _ col: Int) -> String { sheetName + "$\(CellAddress.columnName(col))$\(row + 1)" }
        func span(_ r0: Int, _ c0: Int, _ r1: Int, _ c1: Int) -> String { cell(r0, c0) + ":$\(CellAddress.columnName(c1))$\(r1 + 1)" }
        var refs: [(name: String?, cat: String?, val: String?)] = []
        let byColumns = r.bottom - dataTop + 1 >= r.right - dataLeft + 1
        if byColumns {
            for col in dataLeft ... r.right {
                refs.append((hasHeader ? cell(r.top, col) : nil, firstColLabels ? span(dataTop, r.left, r.bottom, r.left) : nil,
                             span(dataTop, col, r.bottom, col)))
            }
        } else {
            for row in dataTop ... r.bottom {
                refs.append((firstColLabels ? cell(row, r.left) : nil, hasHeader ? span(r.top, dataLeft, r.top, r.right) : nil,
                             span(row, dataLeft, row, r.right)))
            }
        }
        if type == .pie { refs = Array(refs.prefix(1)) }
        var chart = Chart(type: type, title: nil, categories: [],
                          series: refs.indices.map { ChartSeries(name: "Series\($0 + 1)", values: []) })
        // (Excel's white, outlined chart area: written as such on save.)
        chart.areaNoFill = false; chart.areaNoLine = false
        chart.legend = refs.count > 1 || type == .pie
        var sc = SheetChart(chart: chart, refs: refs)
        let live = liveChart(sc)
        sc.chart.title = live.series.count == 1 ? live.series[0].name : "Chart Title"
        // 5 × 3 inches (Excel's size), a column clear of the data, level with its top.
        let corner = ws.point(SheetMarker(col: r.right + 2, colOff: 0, row: r.top, rowOff: 0))
        let anchor = ws.anchor(x: corner.x, y: corner.y, width: 360, height: 216)
        let n = ws.drawings.filter(\.isChart).count + 1
        structural {
            ws.drawings.append(SheetDrawing(name: "Chart \(n)", anchor: anchor, kind: .chart(sc)))
            ws.drawingsEdited = true
        }
        selectedDrawing = ws.drawings.count - 1
        _notify(selectionOnly: true)
        return true
    }

    /// Move or resize a drawing to a frame in points (one undo step).
    func setDrawingFrame(_ index: Int, x: Double, y: Double, width: Double, height: Double, from old: SheetAnchor? = nil) {
        let ws = sheet
        guard ws.drawings.indices.contains(index) else { return }
        if let old { ws.drawings[index].anchor = old }
        let anchor = ws.anchor(x: max(0, x), y: max(0, y), width: max(8, width), height: max(8, height))
        guard anchor != ws.drawings[index].anchor else { return }
        structural {
            ws.drawings[index].anchor = anchor
            ws.drawingsEdited = true
        }
        selectedDrawing = index
    }

    func deleteDrawing(_ index: Int) {
        let ws = sheet
        guard ws.drawings.indices.contains(index), ws.drawings[index].kind != .other else { return }
        structural {
            ws.drawings.remove(at: index)
            ws.drawingsEdited = true
        }
        selectedDrawing = nil
        _notify(selectionOnly: true)
    }

    /// Change a chart's kind; its part is then written afresh.
    func setChartType(_ index: Int, _ type: ChartType) {
        let ws = sheet
        guard ws.drawings.indices.contains(index), case .chart(var sc) = ws.drawings[index].kind, sc.chart.type != type else { return }
        sc.chart = sc.chart.converted(to: type)
        if type == .pie { sc.chart.legend = true }
        sc.path = nil
        structural {
            ws.drawings[index].kind = .chart(sc)
            ws.drawings[index].raw = nil
            ws.drawingsEdited = true
        }
        selectedDrawing = index
    }
}
