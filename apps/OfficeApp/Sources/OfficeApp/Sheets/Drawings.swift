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
    /// Set when the file's own chart was turned between column and bar here:
    /// the save patches that part's direction and keeps all its formatting.
    var retype: ChartType? = nil
    /// The chart's 3D, stock or bubble form, set here (see ChartVariant); the save applies it after `retype`.
    var variant: ChartVariant? = nil
    /// A title or legend changed here on the file's own chart: the save patches those two elements of its part.
    var titleEdit: ChartPartEdit? = nil
    var legendEdit: ChartPartEdit? = nil
    var catTitleEdit: ChartPartEdit? = nil
    var valTitleEdit: ChartPartEdit? = nil
    /// Select Data on the file's own chart: its series as they are now (which of the part's each came from, and the cells they read); the save rewrites the part's series to match.
    var seriesEdit: [ChartSeriesRef]? = nil
    /// Colours set in Format Data Series on the file's own chart, by the part's series; the save patches them in before the series are rewritten.
    var colorEdit: [ChartColorEdit] = []
    /// Data Labels set on the file's own chart; the save patches its labels.
    var labelEdit: ChartLabelEdit? = nil
    /// Axis options set on the file's own chart; the save patches its value axis.
    var axisEdit: ChartAxisEdit? = nil
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
    /// A pivot chart's field buttons (`c14:dropZonesVisible`): Excel prints them in the chart.
    var pivotButtons = false
    /// The pivot's column fields, the names on the series buttons at the chart's right.
    var pivotSeries: [String] = []

    static func == (a: SheetChart, b: SheetChart) -> Bool {
        a.chart == b.chart && a.path == b.path && a.titleEdit == b.titleEdit && a.colorEdit == b.colorEdit && a.labelEdit == b.labelEdit && a.axisEdit == b.axisEdit && a.legendEdit == b.legendEdit && a.catTitleEdit == b.catTitleEdit && a.valTitleEdit == b.valTitleEdit && a.seriesEdit == b.seriesEdit && a.formulas == b.formulas && a.refs.count == b.refs.count
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
    /// `cNvPr@descr`: the alt text a screen reader says. `rawDescr` is what the file had.
    var descr: String? = nil
    var rawDescr: String? = nil
    /// `cNvPr@title`, the alt text's short title; `rawTitle` is what the file had.
    var title: String? = nil
    var rawTitle: String? = nil

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
                d.descr = pic.child("nvPicPr")?.child("cNvPr")?["descr"]
                d.rawDescr = d.descr
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
                sc.pivotButtons = sc.pivot && space.descendant("c14:dropZonesVisible")?["val"] == "1"
                if sc.pivotButtons, let src = space.descendant("c:pivotSource")?.first("c:name")?.text {
                    sc.pivotSeries = _pivotColumnFields(parts, pivotName: src.split(separator: "!").last.map(String.init) ?? src)
                }
                sc.categoryFormat = axis.flatMap { ["0", "false"].contains($0["sourceLinked"] ?? "1") ? $0["formatCode"] : nil }
                for f in _formulas(space) { sc.formulas[f] = f }
                d.kind = .chart(sc)
                d.relId = ref
            } else if let frame = el.child("graphicFrame") ?? el.child("AlternateContent")?.child("Choice")?.child("graphicFrame"),
                      let diagram = _diagram(frame, rels: rels, parts: parts) {
                // (A SmartArt diagram: the shapes Excel drew it as, in its drawing part, read as a group
                // — lo-tdf83671's Venn printed nothing.)
                d.name = frame.child("nvGraphicFramePr")?.child("cNvPr")?["name"] ?? "Diagram"
                var shape = SheetShape.readGroup(diagram.group, colors: colors)
                shape.native = true
                shape.fill = diagram.background.flatMap { $0.child("solidFill") }.flatMap { colors.color(in: $0) }
                d.kind = .shape(shape)
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
            d.descr = named?["descr"]; d.rawDescr = d.descr
            d.title = named?["title"]; d.rawTitle = d.title
            d.hidden = named?["hidden"] == "1" || named?["hidden"] == "true"
            if let p = el.child("clientData")?["fPrintsWithSheet"], p == "0" || p == "false" { d.screenOnly = true }
            out.append(d)
        }
        return (out, drawingPath, split.rootStart)
    }

    /// The shapes of a SmartArt diagram in a graphic frame (`dgm:relIds`): its data part's `dsp:dataModelExt`
    /// names the drawing part Excel wrote, whose shapes lie in the frame's own space (from 0, 0, in EMU,
    /// at their size: Excel prints them unscaled in the frame's corner), read as a group. A shape's text
    /// has its own box (`dsp:txXfrm`), so it goes in a shape of its own after the shape's outline.
    private static func _diagram(_ frame: XNode, rels: [String: String], parts: [String: Data]) -> (group: XNode, background: XNode?)? {
        guard let ids = frame.child("graphic")?.child("graphicData")?.child("relIds"), let dm = ids["r:dm"],
              let dataPath = rels[dm], let data = parts[dataPath].flatMap({ XNode.parse($0) }),
              let rid = data.descendant("dsp:dataModelExt")?["relId"], let drawingPath = rels[rid],
              let drawing = parts[drawingPath].flatMap({ XNode.parse($0) }),
              let tree = drawing.descendant("dsp:spTree") else { return nil }
        func local(_ n: XNode) -> String { n.name.split(separator: ":").last.map(String.init) ?? "" }
        var right = 0.0, bottom = 0.0
        var members: [XNode] = []
        for sp in tree.children where ["sp", "grpSp", "cxnSp"].contains(local(sp)) {
            guard let x = sp.child("spPr")?.child("xfrm") ?? sp.child("grpSpPr")?.child("xfrm"),
                  let off = x.child("off"), let ext = x.child("ext") else { continue }
            right = max(right, (Double(off["x"] ?? "") ?? 0) + (Double(ext["cx"] ?? "") ?? 0))
            bottom = max(bottom, (Double(off["y"] ?? "") ?? 0) + (Double(ext["cy"] ?? "") ?? 0))
            if local(sp) == "sp", let tx = sp.child("txXfrm"), let body = sp.child("txBody") {
                let outline = XNode(name: sp.name, attrs: sp.attrs)
                outline.children = sp.children.filter { $0 !== body && $0 !== tx }
                let text = XNode(name: sp.name, attrs: sp.attrs)
                let pr = XNode(name: "spPr", attrs: [:])
                let xf = XNode(name: "xfrm", attrs: [:])
                xf.children = tx.children
                let geom = XNode(name: "prstGeom", attrs: ["prst": "rect"])
                let none = XNode(name: "noFill", attrs: [:]), ln = XNode(name: "ln", attrs: [:])
                ln.children = [XNode(name: "noFill", attrs: [:])]
                pr.children = [xf, geom, none, ln]
                text.children = [pr, body] + (sp.child("style").map { [$0] } ?? [])
                members += [outline, text]
                if let o = tx.child("off"), let e = tx.child("ext") {
                    right = max(right, (Double(o["x"] ?? "") ?? 0) + (Double(e["cx"] ?? "") ?? 0))
                    bottom = max(bottom, (Double(o["y"] ?? "") ?? 0) + (Double(e["cy"] ?? "") ?? 0))
                }
            } else {
                members.append(sp)
            }
        }
        guard right > 0, bottom > 0 else { return nil }
        let grp = XNode(name: "grpSp", attrs: [:])
        let pr = XNode(name: "grpSpPr", attrs: [:])
        let x = XNode(name: "xfrm", attrs: [:])
        x.children = [XNode(name: "chOff", attrs: ["x": "0", "y": "0"]), XNode(name: "chExt", attrs: ["cx": String(Int(right)), "cy": String(Int(bottom))])]
        pr.children = [x]
        grp.children = [pr] + members
        return (grp, data.child("bg"))
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

    /// The names of a pivot table's column fields (its series), from the cache's field names.
    static func _pivotColumnFields(_ parts: [String: Data], pivotName: String) -> [String] {
        for path in parts.keys.sorted() where path.hasPrefix("xl/pivotTables/pivotTable") && path.hasSuffix(".xml") {
            guard let root = parts[path].flatMap({ XNode.parse($0) }), root["name"] == pivotName else { continue }
            let xs = (root.child("colFields")?.all("field") ?? []).compactMap { Int($0["x"] ?? "") }
            guard let cache = _relTargets(parts, of: path).values.first(where: { $0.containsSubstring("pivotCacheDefinition") }),
                  let def = parts[cache].flatMap({ XNode.parse($0) }), let fields = def.child("cacheFields")?.all("cacheField") else { return [] }
            return xs.compactMap { $0 >= 0 && $0 < fields.count ? fields[$0]["name"] : nil }
        }
        return []
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
        if pivot {
            // The field buttons name the pivot's value field (the cell above-left of the
            // series names) and its category field (the cell over the categories).
            if pivotButtons, let ref = refs.first, let cf = ref.cat, let nf = ref.name {
                func cell(_ formula: String) -> (Int, CellRange)? {
                    guard let expr = try? Formula.parse("=" + formula), case .ref(let r) = expr, let name = r.sheet,
                          let si = book.sheet(named: name) else { return nil }
                    return (si, r.range)
                }
                func text(_ si: Int, _ row: Int, _ col: Int) -> String? {
                    guard row >= 0, col >= 0 else { return nil }
                    let a = CellRange(top: row, left: col, bottom: row, right: col)
                    return engine.values(si, a, includeEmpty: true).first.map { NumberFormat.display($0, "General", width: 255).text.trimmingWhitespace() }
                }
                if let (si, cr) = cell(cf), let (_, nr) = cell(nf),
                   let top = text(si, nr.top, cr.left), let bottom = text(si, cr.top - 1, cr.left), !top.isEmpty, !bottom.isEmpty {
                    c.pivotButtons = [top, bottom]
                    c.pivotSeries = pivotSeries
                }
            }
            return c
        }
        func resolve(_ formula: String) -> (sheet: Int, range: CellRange)? {
            // (Or a defined name for one: a `cx:` chart's _xlchart.v1.0.)
            let formula = book.names[formula.uppercased()] ?? formula
            guard let expr = try? Formula.parse("=" + formula), case .ref(let r) = expr, let name = r.sheet,
                  let si = book.sheet(named: name) else { return nil }
            guard r.range.area <= 10_000 else { return nil }
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
        func shownCells(_ formula: String, own: String? = nil, monthStarts: Bool = false) -> [String]? {
            guard let (si, range) = resolve(formula) else { return nil }
            if c.type == .scatter { return engine.values(si, range, includeEmpty: true).map(shown) }
            let ws = book.sheets[si]
            let cells = engine.values(si, range, includeEmpty: true)
            var out: [String] = [], k = 0, lastMonth = ""
            for row in range.top ... range.bottom {
                for col in range.left ... range.right where k < cells.count {
                    let a = CellAddress(row: row, col: col)
                    let code = own ?? book.style(ws.cells[a]?.style ?? ws.defaultStyle(at: a)).numberFormat
                    if monthStarts, let serial = cells[k].number {
                        // (A date axis on a month base unit names each month once, at its first date: chart-tdf134118's 1-May 1-Jun 1-Jul.)
                        let ym = chartNumberText(serial, "yyyy-mm")
                        let day = Double(chartNumberText(serial, "d")) ?? 1
                        out.append(ym == lastMonth ? "" : NumberFormat.display(.number(serial - (day - 1)), code, width: 255).text.trimmingWhitespace())
                        lastMonth = ym; k += 1; continue
                    }
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
            if i == 0, let f = ref.cat, let cells = shownCells(f, own: categoryFormat, monthStarts: c.monthBaseDates) { c.categories = cells }
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
            if case .chart(let sc) = d.kind, let path = sc.path, sc.formulasChanged || sc.retype != nil || sc.variant != nil || sc.titleEdit != nil || sc.legendEdit != nil || sc.catTitleEdit != nil || sc.valTitleEdit != nil || sc.seriesEdit != nil || !sc.colorEdit.isEmpty || sc.labelEdit != nil || sc.axisEdit != nil, let bytes = original[path] {
                // The file's own chart, its references moved with the cells.
                var xml = String(decoding: bytes, as: UTF8.self)
                if sc.formulasChanged { xml = _rewriteFormulas(xml, sc.formulas) }
                if !sc.colorEdit.isEmpty { xml = ChartPartPatch.colors(xml, sc.colorEdit) }
                if let e = sc.seriesEdit { xml = ChartPartPatch.series(xml, e) }
                if let e = sc.labelEdit { xml = ChartPartPatch.labels(xml, e) }
                if let e = sc.axisEdit { xml = ChartPartPatch.valueAxis(xml, e) }
                if sc.retype != nil { xml = ChartPartType.retype(xml, to: sc.chart) ?? xml }
                if let v = sc.variant { xml = ChartPartType.apply(xml, v, type: sc.chart.type) ?? xml }
                if let e = sc.titleEdit { xml = ChartPartPatch.title(xml, e) }
                if let e = sc.legendEdit { xml = ChartPartPatch.legend(xml, e) }
                if let e = sc.catTitleEdit { xml = ChartPartPatch.axisTitle(xml, .category, e) }
                if let e = sc.valTitleEdit { xml = ChartPartPatch.axisTitle(xml, .value, e) }
                out.parts[path] = Data(xml.utf8)
            }
            if let raw = d.raw {
                let raw = d.descr == d.rawDescr && d.title == d.rawTitle ? raw : _patchAlt(raw, d.descr, d.title)
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
            case .picture(let path, let data):
                // A picture put in here carries its bytes: the media part is new.
                if original[path] == nil, !path.isEmpty { out.parts[path] = data; taken.insert(path) }
                let id = d.relId.flatMap { id in rels.contains { $0.id == id } ? id : nil } ?? relTo("image", path)
                let alt = _altAttrs(d)
                content = "<xdr:pic><xdr:nvPicPr><xdr:cNvPr id=\"\(shapeId)\" name=\"\(name)\"\(alt)/><xdr:cNvPicPr><a:picLocks noChangeAspect=\"1\"/></xdr:cNvPicPr></xdr:nvPicPr>"
                    + "<xdr:blipFill><a:blip r:embed=\"\(id)\"/><a:stretch><a:fillRect/></a:stretch></xdr:blipFill>"
                    + "<xdr:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"0\" cy=\"0\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></xdr:spPr></xdr:pic>"
            case .chart(let sc):
                let id: String
                if sc.path != nil, let rid = d.relId, rels.contains(where: { $0.id == rid }) {
                    id = rid
                } else {
                    let chartPath = fresh("xl/charts/", "chart")
                    var space = chartSpace(sc, live: live(sc))
                    if let v = sc.variant { space = ChartPartType.apply(space, v, type: sc.chart.type) ?? space }
                    out.parts[chartPath] = Data(space.utf8)
                    out.overrides.append(("/" + chartPath, chartType))
                    id = relTo("chart", chartPath)
                }
                content = "<xdr:graphicFrame macro=\"\"><xdr:nvGraphicFramePr><xdr:cNvPr id=\"\(shapeId)\" name=\"\(name)\"\(_altAttrs(d))/><xdr:cNvGraphicFramePr/></xdr:nvGraphicFramePr>"
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

    /// `raw` with the alt text of its first `cNvPr` set (or taken off when nil or empty).
    static func _altAttrs(_ d: SheetDrawing) -> String {
        var a = ""
        if let x = d.descr, !x.isEmpty { a += " descr=\"\(Xlsx._esc(x))\"" }
        if let x = d.title, !x.isEmpty { a += " title=\"\(Xlsx._esc(x))\"" }
        return a
    }

    static func _patchAlt(_ raw: String, _ descr: String?, _ title: String?) -> String {
        guard let s = raw.rangeOfSubstring("<xdr:cNvPr") ?? raw.rangeOfSubstring("<cNvPr"),
              let e = raw.rangeOfSubstring(">", in: s.upperBound..<raw.endIndex) else { return raw }
        var tag = String(raw[s.lowerBound..<e.lowerBound])
        if let a = tag.rangeOfSubstring(" descr=\""), let q = tag.rangeOfSubstring("\"", in: a.upperBound..<tag.endIndex) {
            tag.removeSubrange(a.lowerBound..<q.upperBound)
        }
        if let a = tag.rangeOfSubstring(" title=\""), let q = tag.rangeOfSubstring("\"", in: a.upperBound..<tag.endIndex) {
            tag.removeSubrange(a.lowerBound..<q.upperBound)
        }
        var selfClosing = false
        if tag.hasSuffix("/") { tag.removeLast(); selfClosing = true }
        if let d = descr, !d.isEmpty { tag += " descr=\"\(Xlsx._esc(d))\"" }
        if let t = title, !t.isEmpty { tag += " title=\"\(Xlsx._esc(t))\"" }
        return String(raw[raw.startIndex..<s.lowerBound]) + tag + (selfClosing ? "/" : "") + String(raw[e.lowerBound...])
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
        // Inside the printable width when it fits there (Excel prints a chart over the page edge on 2 pages), never over the data.
        // A sheet that states no default column width gets Excel's own, 51 pt where we assume 48 (Excel's check of a new chart: left 160.2, width 381 for our 151.2 and 360), so the fit is tested at that scale.
        let printable = SheetPrintSetup.read(ws).printableWidth
        let grow = ws.formatPrAttrs["defaultColWidth"] == nil ? 51.0 / 48.0 : 1.0
        let dataEdge = ws.point(SheetMarker(col: r.right + 1, colOff: 0, row: r.top, rowOff: 0)).x
        func place(_ x: Double, _ y: Double) -> (SheetAnchor, Bool) {
            // (Offsets in whole EMU, as the file holds them, so it reads back as written.)
            func emu(_ m: SheetMarker) -> SheetMarker { SheetMarker(col: m.col, colOff: (m.colOff * 12700).rounded() / 12700, row: m.row, rowOff: (m.rowOff * 12700).rounded() / 12700) }
            var a = ws.anchor(x: x, y: y, width: 360, height: 216)
            if case .twoCell(let from, let to) = a { a = .twoCell(from: emu(from), to: emu(to)) }
            let f = ws.frame(a)
            return (a, (f.x + f.width) * grow <= printable)
        }
        var (anchor, fits) = place(corner.x, corner.y)
        if !fits {
            // Beside the data when it fits there; else under it, from the data's left edge, so it never crosses the page edge.
            var x = printable / grow - 360
            for _ in 0 ..< 4 where x >= dataEdge {
                let (a, ok) = place(x, corner.y)
                if ok { anchor = a; fits = true; break }
                x -= 1
            }
            if !fits {
                let below = ws.point(SheetMarker(col: r.left, colOff: 0, row: r.bottom + 2, rowOff: 0))
                var bx = below.x
                for _ in 0 ..< 6 {
                    let (a, ok) = place(bx, below.y)
                    anchor = a
                    if ok || bx <= 0 { break }
                    bx = max(0, bx - 8)
                }
            }
        }
        let n = ws.drawings.filter(\.isChart).count + 1
        structural {
            ws.drawings.append(SheetDrawing(name: "Chart \(n)", anchor: anchor, kind: .chart(sc)))
            ws.drawingsEdited = true
        }
        selectedDrawing = ws.drawings.count - 1
        _notify(selectionOnly: true)
        return true
    }

    /// Insert → Picture: an image of `width` × `height` points, placed at the top-left of the
    /// view (the active cell's corner), selected. The bytes are kept to be written as a media part.
    @discardableResult
    func insertPicture(name: String, data: Data, width: Double, height: Double) -> Bool {
        let ws = sheet
        guard let ext = Self._imageExtension(data), width > 0, height > 0 else {
            onCommand?(.status("That file is not a picture Sheets can place"))
            return false
        }
        // Down to a page-friendly size, keeping the shape (Excel fits a big picture to the window).
        let k = min(1, 480 / width, 360 / height)
        var n = 1
        while ws.drawings.contains(where: { if case .picture(let p, _) = $0.kind { return p == "xl/media/starling-image\(n).\(ext)" }; return false }) { n += 1 }
        let path = "xl/media/starling-image\(n).\(ext)"
        let corner = ws.point(SheetMarker(col: active.col, colOff: 0, row: active.row, rowOff: 0))
        let anchor = ws.anchor(x: corner.x, y: corner.y, width: width * k, height: height * k)
        let count = ws.drawings.filter { if case .picture = $0.kind { return true }; return false }.count + 1
        structural {
            ws.drawings.append(SheetDrawing(name: "Picture \(count)", anchor: anchor, kind: .picture(path: path, data: data)))
            ws.drawingsEdited = true
        }
        selectedDrawing = ws.drawings.count - 1
        _notify(selectionOnly: true)
        return true
    }

    /// The file extension of an image by its first bytes; nil when it is not one Excel keeps.
    static func _imageExtension(_ d: Data) -> String? {
        let b = [UInt8](d.prefix(12))
        if b.count >= 8, b[0] == 0x89, b[1] == 0x50, b[2] == 0x4E, b[3] == 0x47 { return "png" }
        if b.count >= 3, b[0] == 0xFF, b[1] == 0xD8, b[2] == 0xFF { return "jpeg" }
        if b.count >= 4, b[0] == 0x47, b[1] == 0x49, b[2] == 0x46, b[3] == 0x38 { return "gif" }
        if b.count >= 2, b[0] == 0x42, b[1] == 0x4D { return "bmp" }
        return nil
    }

    /// Alt text and title of a picture, chart or shape (one undo step).
    func setDrawingAlt(_ index: Int, _ text: String, title: String = "") {
        let ws = sheet
        guard ws.drawings.indices.contains(index), ws.drawings[index].kind != .other,
              (ws.drawings[index].descr ?? "") != text || (ws.drawings[index].title ?? "") != title else { return }
        structural {
            ws.drawings[index].descr = text.isEmpty ? nil : text
            ws.drawings[index].title = title.isEmpty ? nil : title
            ws.drawingsEdited = true
        }
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

    /// Move several drawings at once, each to a frame in points (one undo step); each `from` is the anchor it had before a live drag.
    func setDrawingFrames(_ items: [(index: Int, x: Double, y: Double, width: Double, height: Double, from: SheetAnchor)]) {
        let ws = sheet
        let items = items.filter { ws.drawings.indices.contains($0.index) }
        guard !items.isEmpty else { return }
        for i in items { ws.drawings[i.index].anchor = i.from }
        let anchors = items.map { ws.anchor(x: max(0, $0.x), y: max(0, $0.y), width: max(8, $0.width), height: max(8, $0.height)) }
        guard zip(items, anchors).contains(where: { ws.drawings[$0.index].anchor != $1 }) else { return }
        structural {
            for (i, a) in zip(items, anchors) { ws.drawings[i.index].anchor = a }
            ws.drawingsEdited = true
        }
    }

    /// Delete every selected chart and picture (one undo step).
    func deleteSelectedDrawings() {
        let ws = sheet
        let gone = selectedDrawingIndexes.filter { ws.drawings.indices.contains($0) && ws.drawings[$0].kind != .other }
        guard !gone.isEmpty else { return }
        structural {
            for i in gone.sorted(by: >) { ws.drawings.remove(at: i) }
            ws.drawingsEdited = true
        }
        selectedDrawing = nil
        _notify(selectionOnly: true)
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

    /// Change one chart made here (Chart Design). A chart that came from the
    /// file keeps its own part, which these edits would not reach: it is
    /// refused with a notice rather than changed on screen and lost on save.
    @discardableResult
    func editChart(_ index: Int, _ change: (inout Chart) -> Void) -> Bool {
        let ws = sheet
        guard ws.drawings.indices.contains(index), case .chart(var sc) = ws.drawings[index].kind else { return false }
        var chart = sc.chart
        change(&chart)
        guard chart != sc.chart else { return false }
        if sc.path != nil {
            // The file's own chart: its part is patched on save, only for what changed.
            if chart.title != sc.chart.title || chart.autoTitle != sc.chart.autoTitle {
                sc.titleEdit = chart.title.map { .set($0) } ?? .remove
            }
            if chart.categoryAxisTitle != sc.chart.categoryAxisTitle { sc.catTitleEdit = chart.categoryAxisTitle.map { .set($0) } ?? .remove }
            if chart.valueAxisTitle != sc.chart.valueAxisTitle { sc.valTitleEdit = chart.valueAxisTitle.map { .set($0) } ?? .remove }
            if chart.legend != sc.chart.legend || chart.legendPosition != sc.chart.legendPosition {
                sc.legendEdit = chart.legend ? .set(chart.legendPosition) : .remove
            }
        }
        sc.chart = chart
        structural {
            ws.drawings[index].kind = .chart(sc)
            ws.drawings[index].raw = nil
            ws.drawingsEdited = true
        }
        selectedDrawing = index
        return true
    }

    /// Chart Design → Add Chart Element → Chart Title: a text, or nil for none.
    func setChartTitle(_ index: Int, _ title: String?) {
        editChart(index) { $0.title = title; $0.autoTitle = false }
    }

    /// Chart Design → Select Data: the series as they read now (for a file's chart, each with its place in the part).
    func chartSeries(_ index: Int) -> [ChartSeriesRef]? {
        guard sheet.drawings.indices.contains(index), case .chart(let sc) = sheet.drawings[index].kind, _canEditSeries(sc) else { return nil }
        if let e = sc.seriesEdit { return e }
        return sc.refs.indices.map { ChartSeriesRef(source: $0, name: sc.refs[$0].name, cat: sc.refs[$0].cat, val: sc.refs[$0].val) }
    }
    private func _canEditSeries(_ sc: SheetChart) -> Bool {
        !sc.pivot && sc.chart.boxes == nil && sc.chart.sunburst == nil && sc.chart.histogram == nil && !(sc.path ?? "").containsSubstring("chartEx")
            && sc.refs.count == sc.chart.series.count
    }
    /// Whether a text reads as a reference to cells of a sheet in this book.
    func isChartRef(_ text: String) -> Bool {
        guard let e = try? Formula.parse("=" + text), case .ref(let r) = e, let n = r.sheet else { return false }
        return book.sheet(named: n) != nil
    }
    /// Select Data: the chart's series made to be `list` (one undo step). A series keeps what it has (colours, line, markers) and
    /// changes only the cells it reads; one left out goes; a new one starts plain. Nothing happens for a list with a bad reference.
    @discardableResult
    func setChartSeries(_ index: Int, _ list: [ChartSeriesRef]) -> Bool {
        let ws = sheet
        guard ws.drawings.indices.contains(index), case .chart(var sc) = ws.drawings[index].kind, _canEditSeries(sc),
              let before = chartSeries(index), list != before, !list.isEmpty else { return false }
        for r in list { for t in [r.name, r.cat, r.val] { if let t, !isChartRef(t) { return false } }; if r.val == nil { return false } }
        if sc.path != nil {
            // The part's series stay in their order: kept ones ascend, each once.
            let kept = list.compactMap(\.source)
            guard kept == kept.sorted(), Set(kept).count == kept.count else { return false }
        }
        var series: [ChartSeries] = []
        for (n, r) in list.enumerated() {
            if let s = r.source, let at = before.firstIndex(where: { $0.source == s }), sc.chart.series.indices.contains(at) { series.append(sc.chart.series[at]) }
            else if sc.path == nil, let at = r.source, sc.chart.series.indices.contains(at) { series.append(sc.chart.series[at]) }
            else { series.append(ChartSeries(name: "Series\(n + 1)", values: [])) }
        }
        if sc.path == nil {
            // A series keeps its own number (c:idx) when another is removed, so its automatic colour stays; a new one takes the next free number.
            var keep: [Int?] = list.map { r in r.source.flatMap { at in sc.chart.series.indices.contains(at) ? (sc.chart.series[at].autoIndex ?? at) : nil } }
            var next = (keep.compactMap { $0 }.max() ?? -1) + 1
            for k in keep.indices where keep[k] == nil { keep[k] = next; next += 1 }
            for k in series.indices { series[k].autoIndex = keep[k] }
        }
        sc.chart.series = series
        sc.refs = list.map { (name: $0.name, cat: $0.cat, val: $0.val) }
        if sc.path != nil { sc.seriesEdit = list } else { sc.chart.series = series }
        structural {
            ws.drawings[index].kind = .chart(sc)
            ws.drawings[index].raw = nil
            ws.drawingsEdited = true
        }
        selectedDrawing = index
        return true
    }

    /// Format Data Series: what can be coloured on a chart, each with the colour it has now (nil follows the theme or its number).
    struct ChartColorTarget { var title: String; var series: Int; var point: Int?; var color: Color?; var themed: Bool }
    /// A series (by its place in the part for a file's chart, in the chart for one made here) and, for the first series of a bar, column, area or pie chart, its points.
    func chartColorTargets(_ index: Int) -> (series: [ChartColorTarget], points: [ChartColorTarget])? {
        guard sheet.drawings.indices.contains(index), case .chart(let sc) = sheet.drawings[index].kind, _canEditSeries(sc) else { return nil }
        let list = chartSeries(index) ?? []
        var series: [ChartColorTarget] = []
        for (n, s) in sc.chart.series.enumerated() {
            let key: Int
            if sc.path != nil { guard list.indices.contains(n), let src = list[n].source else { continue }; key = src } else { key = n }
            if sc.chart.type.isPie { continue }
            series.append(ChartColorTarget(title: s.name.isEmpty ? "Series \(n + 1)" : s.name, series: key, point: nil, color: s.color, themed: s.color == nil && s.scheme != nil))
        }
        var points: [ChartColorTarget] = []
        let t = sc.chart.type
        if t == .column || t == .bar || t == .area || t.isPie, let first = series.first, let s0 = sc.chart.series.first {
            for (p, name) in sc.chart.categories.enumerated().prefix(40) {
                points.append(ChartColorTarget(title: name.isEmpty ? "Point \(p + 1)" : name, series: first.series, point: p, color: sc.chart.pointColors[p], themed: false))
            }
            _ = s0
        }
        return (series, points)
    }
    /// Format Data Series: a series' (or one point's) colour, nil for automatic (one undo step).
    @discardableResult
    func setChartColor(_ index: Int, series key: Int, point: Int?, color: Color?) -> Bool {
        setChartColor(index, series: key, point: point, choice: color.map { .rgb(UInt32(truncatingIfNeeded: $0.value) & 0xFFFFFF) } ?? .automatic)
    }
    /// The same from the colour picker: a theme pick is written as a scheme colour (with its lumMod / lumOff) so a new theme recolours it.
    static let schemeSlots = ["bg1", "tx1", "bg2", "tx2", "accent1", "accent2", "accent3", "accent4", "accent5", "accent6"]
    @discardableResult
    func setChartColor(_ index: Int, series key: Int, point: Int?, choice: ColorChoice) -> Bool {
        let ws = sheet
        var edit = ChartColorEdit(series: key, point: point, hex: nil)
        var color: Color? = nil
        switch choice {
        case .automatic, .none: break
        case .rgb(let c): color = Color(Int64(0xFF000000 | c)); edit.hex = color.map { PptxText.hex($0) }
        case .theme(let slot, let mod, let off):
            guard Self.schemeSlots.indices.contains(slot), let c = choice.resolved(theme: ColorMath.officeTheme) else { return false }
            color = Color(Int64(0xFF000000 | c)); edit.scheme = Self.schemeSlots[slot]; edit.lumMod = mod; edit.lumOff = off
        }
        let xml = edit.element
        guard ws.drawings.indices.contains(index), case .chart(var sc) = ws.drawings[index].kind, _canEditSeries(sc) else { return false }
        var at = key
        if sc.path != nil {
            guard let list = chartSeries(index), let n = list.firstIndex(where: { $0.source == key }) else { return false }
            at = n
        }
        guard sc.chart.series.indices.contains(at) else { return false }
        if let p = point {
            guard at == 0 else { return false }
            sc.chart.pointColors[p] = color
            sc.chart.pointColorXML[p] = edit.scheme != nil ? xml : nil
            if color == nil { sc.chart.pointColors.removeValue(forKey: p) }
        } else if !sc.chart.type.isPie {
            sc.chart.series[at].color = color
            sc.chart.series[at].scheme = nil
            sc.chart.series[at].colorXML = edit.scheme != nil ? xml : nil
        } else { return false }
        if sc.path != nil {
            sc.colorEdit.removeAll { $0.series == key && $0.point == point }
            sc.colorEdit.append(edit)
        }
        structural {
            ws.drawings[index].kind = .chart(sc)
            ws.drawings[index].raw = nil
            ws.drawingsEdited = true
        }
        selectedDrawing = index
        return true
    }

    /// Data Labels: what this chart's labels can show and where they can stand, with what they do now.
    struct ChartLabelOptions { var edit: ChartLabelEdit; var canCategory: Bool; var canSeries: Bool; var canPercent: Bool; var positions: [String] }
    func chartLabelOptions(_ index: Int) -> ChartLabelOptions? {
        guard sheet.drawings.indices.contains(index), case .chart(let sc) = sheet.drawings[index].kind,
              sc.chart.boxes == nil, sc.chart.sunburst == nil, sc.chart.histogram == nil, !(sc.path ?? "").containsSubstring("chartEx") else { return nil }
        let c = sc.chart, t = c.type
        var e = sc.chart.labelEdit ?? ChartLabelEdit()
        if c.labelEdit == nil {
            e.show = c.dataLabels || c.pieLabels != nil
            if let l = c.pieLabels { e.value = l.value || !(l.series || l.category || l.percent); e.category = l.category; e.series = l.series; e.percent = l.percent; e.position = l.position }
            else { e.position = c.barLabelPos; e.category = c.fileLabelCategory; e.series = c.fileLabelSeries }
        }
        let pie = t.isPie, bars = t == .column || t == .bar
        let tag = pie ? (t == .pie ? "pieChart" : "doughnutChart") : bars ? "barChart" : ""
        return ChartLabelOptions(edit: e, canCategory: pie || bars, canSeries: pie || bars, canPercent: pie,
                                 positions: ChartLabelEdit.positions(group: tag, stacked: c.stacked || c.percent))
    }
    /// The value axis options now: lowest and highest value, major unit, number format (nil = automatic / linked to the cells).
    func chartAxisOptions(_ index: Int) -> ChartAxisEdit? {
        guard sheet.drawings.indices.contains(index), case .chart(let sc) = sheet.drawings[index].kind,
              sc.chart.type.hasAxes, sc.chart.boxes == nil, sc.chart.histogram == nil, !(sc.path ?? "").containsSubstring("chartEx") else { return nil }
        if let e = sc.axisEdit { return e }
        let c = sc.chart
        return ChartAxisEdit(min: c.valueMin, max: c.valueMax, major: c.valueStep, format: c.valueFormat)
    }
    /// Axis options: the value axis scale and number format (one undo step).
    @discardableResult
    func setChartAxis(_ index: Int, _ e: ChartAxisEdit) -> Bool {
        guard chartAxisOptions(index) != nil, case .chart(var sc) = sheet.drawings[index].kind else { return false }
        var clean = e
        if let lo = clean.min, let hi = clean.max, lo >= hi { clean.min = nil; clean.max = nil }
        if let f = clean.format, f.isEmpty || f.lowercased() == "general" { clean.format = nil }
        if let m = clean.major, m <= 0 { clean.major = nil }
        var c = sc.chart
        c.valueMin = clean.min; c.valueMax = clean.max; c.valueStep = clean.major; c.valueFormat = clean.format
        guard c != sc.chart || sc.path != nil else { return false }
        sc.chart = c
        if sc.path != nil { sc.axisEdit = clean }
        let ws = sheet
        structural {
            ws.drawings[index].kind = .chart(sc)
            ws.drawings[index].raw = nil
            ws.drawingsEdited = true
        }
        selectedDrawing = index
        return true
    }

    /// Data Labels: show or hide the labels, what they say and where they stand (one undo step).
    @discardableResult
    func setChartLabels(_ index: Int, _ wanted: ChartLabelEdit) -> Bool {
        let ws = sheet
        guard let o = chartLabelOptions(index), case .chart(var sc) = ws.drawings[index].kind else { return false }
        var e = wanted
        if !o.canCategory { e.category = false }
        if !o.canSeries { e.series = false }
        if !o.canPercent { e.percent = false }
        if let p = e.position, !o.positions.contains(p) { e.position = nil }
        if e.show, !(e.value || e.category || e.series || e.percent) { e.value = true }
        var c = sc.chart
        c.labelEdit = e
        c.dataLabels = e.show
        if c.type.isPie {
            let outside = e.position == "outEnd" || e.position == "bestFit"
            c.pieLabelsAround = e.show && outside
            if e.show, e.category || e.series || e.percent || outside {
                var l = Chart.PieLabels()
                l.series = e.series; l.category = e.category; l.value = e.value; l.percent = e.percent
                l.outside = outside; l.fitted = e.position == "bestFit"; l.position = e.position
                c.pieLabels = l
            } else { c.pieLabels = nil }
        } else if c.type == .column || c.type == .bar {
            c.barLabelPos = e.position
            for j in c.series.indices {
                c.series[j].labelParts = [:]
                guard e.show, e.category || e.series else { continue }
                for i in c.categories.indices {
                    var parts: [String] = []
                    if e.series { parts.append(c.series[j].name) }
                    if e.category { parts.append(ChartSeries.labelCategoryMark) }
                    if e.value { parts.append(ChartSeries.labelValueMark) }
                    var joined: [String] = []
                    for (n, x) in parts.enumerated() { if n > 0 { joined.append(", ") }; joined.append(x) }
                    c.series[j].labelParts[i] = joined
                }
            }
        }
        guard c != sc.chart || sc.path != nil else { return false }
        sc.chart = c
        if sc.path != nil { sc.labelEdit = e }
        structural {
            ws.drawings[index].kind = .chart(sc)
            ws.drawings[index].raw = nil
            ws.drawingsEdited = true
        }
        selectedDrawing = index
        return true
    }

    /// Chart Design → Add Chart Element → Legend: its side ("b", "t", "r", "l"), or nil for none.
    /// Both axis titles at once (nil takes one off); nothing on a chart without axes.
    func setChartAxisTitles(_ index: Int, category: String?, value: String?) {
        editChart(index) { guard $0.type.hasAxes else { return }; $0.categoryAxisTitle = category; $0.valueAxisTitle = value; $0.sizeNewAxisTitles() }
    }
    /// The chart title and both axis titles in one edit (one undo step); nil takes one off. An axis title is left alone on a chart without axes.
    func setChartTitles(_ index: Int, title: String?, category: String?, value: String?) {
        editChart(index) {
            $0.title = title; $0.autoTitle = false
            if $0.type.hasAxes { $0.categoryAxisTitle = category; $0.valueAxisTitle = value; $0.sizeNewAxisTitles() }
        }
    }
    func setChartLegend(_ index: Int, position: String?) {
        editChart(index) {
            $0.legend = position != nil
            if let position { $0.legendPosition = position }
        }
    }

    /// Change a chart's kind; its part is then written afresh.
    func setChartType(_ index: Int, _ type: ChartType) {
        let ws = sheet
        guard ws.drawings.indices.contains(index), case .chart(var sc) = ws.drawings[index].kind else { return }
        let part0 = sc.path.flatMap { p in book.package?.first(where: { $0.name == p }) }
        let fromVariant = sc.variant != nil || part0.map { ChartPartType.hasVariant(String(decoding: $0.data, as: UTF8.self)) } == true
        guard sc.chart.type != type || fromVariant else { return }
        sc.variant = nil
        if sc.path != nil {
            // The file's own chart: its part is converted in place (ChartPartType), so what the model does not hold
            // stays. A part that cannot be (3D, stock, bubble) is refused, saying so.
            let converted = sc.chart.converted(to: type)
            let part = book.package?.first(where: { $0.name == sc.path })
            guard let part, ChartPartType.retype(String(decoding: part.data, as: UTF8.self), to: converted) != nil else {
                chartNotice = "This chart came from the file; changing it to \(type.name) would drop its formatting."
                _notify()
                return
            }
            sc.chart = sc.chart.converted(to: type)
            sc.chart.setForm(nil)
            sc.retype = type
            structural {
                ws.drawings[index].kind = .chart(sc)
                ws.drawingsEdited = true
            }
            selectedDrawing = index
            return
        }
        sc.chart = sc.chart.converted(to: type)
            sc.chart.setForm(nil)
        if type == .pie { sc.chart.legend = true }
        sc.path = nil
        structural {
            ws.drawings[index].kind = .chart(sc)
            ws.drawings[index].raw = nil
            ws.drawingsEdited = true
        }
        selectedDrawing = index
    }

    /// The roles a stock chart still lacks of series (open, high, low, close in that order) on chart `index`.
    func stockRolesMissing(_ index: Int, ohlc: Bool) -> [String] {
        guard sheet.drawings.indices.contains(index), case .chart(let sc) = sheet.drawings[index].kind else { return [] }
        let roles = ohlc ? ["Open", "High", "Low", "Close"] : ["High", "Low", "Close"]
        return Array(roles.dropFirst(sc.chart.series.count))
    }

    /// A range as the user typed it, qualified with the current sheet where it names none; nil where it is no range.
    func chartRange(_ text: String) -> (formula: String, values: [Double?])? {
        var t = text.trimmingWhitespace()
        if t.hasPrefix("=") { t.removeFirst() }
        if !t.containsSubstring("!") { t = "'" + sheet.name.replacingAll("'", with: "''") + "'!" + t }
        guard let expr = try? Formula.parse("=" + t), case .ref(let r) = expr, let name = r.sheet, let si = book.sheet(named: name),
              r.range.area <= 10_000 else { return nil }
        return (t, engine.values(si, r.range, includeEmpty: true).map { $0.number })
    }

    /// A numeric range of the right length to offer as a series' bubble sizes: that series' own values.
    func suggestedBubbleSizes(_ index: Int, series: Int = 0) -> String {
        guard sheet.drawings.indices.contains(index), case .chart(let sc) = sheet.drawings[index].kind,
              sc.refs.indices.contains(series) else { return "" }
        return sc.refs[series].val ?? ""
    }

    /// The labels of the size boxes: one per series.
    func bubbleSizeRoles(_ index: Int) -> [String] {
        guard sheet.drawings.indices.contains(index), case .chart(let sc) = sheet.drawings[index].kind else { return [] }
        return sc.chart.series.enumerated().map { "Sizes for " + ($0.element.name.isEmpty ? "series \($0.offset + 1)" : $0.element.name) }
    }

    /// Chart `index` as its 3D, stock or bubble form. Stock takes the chart's series in order (`extra` are the ranges of
    /// roles it lacks); bubble takes the ranges of the sizes. Returns false, with `chartNotice` saying why, where it cannot.
    @discardableResult
    func setChartVariant(_ index: Int, _ v: ChartVariant) -> Bool {
        let ws = sheet
        guard ws.drawings.indices.contains(index), case .chart(let first) = ws.drawings[index].kind else { return false }
        var target = first.chart.type
        var series: [ChartSeries] = [], refs: [(name: String?, cat: String?, val: String?)] = []
        switch v {
        case .threeD:
            guard [.column, .bar, .line, .area, .pie].contains(target) else {
                chartNotice = "A \(target.name) chart has no 3-D form."; _notify(); return false
            }
        case .stock(let ohlc, let extra):
            target = .line
            let need = (ohlc ? 4 : 3) - first.chart.series.count
            guard need <= extra.count, first.chart.series.count + extra.count >= (ohlc ? 4 : 3) else {
                chartNotice = "A stock chart needs \(ohlc ? "open, high, low and close" : "high, low and close") series."; _notify(); return false
            }
            let roles = ohlc ? ["Open", "High", "Low", "Close"] : ["High", "Low", "Close"]
            for (k, r) in extra.enumerated() {
                guard let range = chartRange(r) else { chartNotice = "\(r) is not a range of cells."; _notify(); return false }
                series.append(ChartSeries(name: roles[min(roles.count - 1, first.chart.series.count + k)], values: range.values))
                refs.append((name: nil, cat: first.refs.first?.cat, val: range.formula))
            }
        case .bubble(let sizes):
            target = .scatter
            guard !sizes.isEmpty, !sizes.contains(where: { chartRange($0) == nil }) else {
                chartNotice = "The bubble sizes need a range of cells."; _notify(); return false
            }
            // Excel draws nothing when a size is missing or the sizes are fewer than the values.
            let want = first.chart.series.map { $0.values.count }.max() ?? 0
            for r in sizes {
                guard let range = chartRange(r) else { continue }
                if range.values.contains(where: { $0 == nil }) {
                    chartNotice = "\(r) has cells that are empty or not numbers; every bubble needs a numeric size."; _notify(); return false
                }
                if range.values.count != want {
                    chartNotice = "\(r) has \(range.values.count) cells but the chart has \(want) values; the sizes need the same count."; _notify(); return false
                }
            }
        }
        if first.chart.type != target || first.variant != nil || first.path != nil { setChartType(index, target) }
        guard case .chart(var sc) = ws.drawings[index].kind else { return false }
        var variant = v
        if case .stock(let o, let extra) = v { variant = .stock(ohlc: o, extra: extra.compactMap { chartRange($0)?.formula }) }
        if case .bubble(let sizes) = v {
            variant = .bubble(sizes: sizes.compactMap { chartRange($0)?.formula })
        }
        sc.variant = variant
        sc.chart.setForm(variant)      // (it clears the sizes: they are set after)
        if case .bubble(let sizes) = v {
            for i in sc.chart.series.indices {
                let r = sizes[min(i, sizes.count - 1)]
                sc.chart.series[i].bubbleSizes = chartRange(r)?.values
            }
        }
        sc.chart.series += series
        sc.refs += refs
        if sc.path != nil, sc.retype == nil { sc.retype = target }
        structural {
            ws.drawings[index].kind = .chart(sc)
            ws.drawingsEdited = true
        }
        selectedDrawing = index
        return true
    }
}

/// A picture the header or footer shows (`&G`): its bytes and the size the VML gives it, in points.
struct HeaderPicture: Equatable {
    var path: String
    var data: Data
    var width: Double
    var height: Double
}

extension SheetDrawingsXML {
    private static func _all(_ n: XNode, _ local: String) -> [XNode] {
        n.children.flatMap { ($0.name.split(separator: ":").last.map(String.init) == local ? [$0] : []) + _all($0, local) }
    }

    /// The header/footer pictures a sheet's `legacyDrawingHF` part holds.
    static func readHeaderPictures(sheetPath: String, parts: [String: Data], sheet: XNode?) -> [String: HeaderPicture] {
        guard let sheet = sheet ?? parts[sheetPath].flatMap({ XNode.parse($0) }),
              let rid = sheet.child("legacyDrawingHF")?["r:id"], let vmlPath = _relTargets(parts, of: sheetPath)[rid],
              let bytes = parts[vmlPath], let root = XNode.parse(bytes) else { return [:] }
        let rels = _relTargets(parts, of: vmlPath)
        var out: [String: HeaderPicture] = [:]
        for shape in _all(root, "shape") {
            guard let id = shape["id"], ["LH", "CH", "RH", "LF", "CF", "RF"].contains(id),
                  let image = _all(shape, "imagedata").first, let rel = image["o:relid"], let path = rels[rel], let data = parts[path] else { continue }
            var width = 0.0, height = 0.0
            for item in (shape["style"] ?? "").split(separator: ";") {
                let kv = item.split(separator: ":", maxSplits: 1).map { String($0).trimmingWhitespace() }
                guard kv.count == 2 else { continue }
                let v = Double(kv[1].replacingAll("pt", with: "")) ?? 0
                if kv[0] == "width" { width = v } else if kv[0] == "height" { height = v }
            }
            if width > 0, height > 0 { out[id] = HeaderPicture(path: path, data: data, width: width, height: height) }
        }
        return out
    }
}

extension Chart {
    /// Axis titles typed here are Excel's: 10 pt bold, not the unformatted 20 pt default that would squeeze the plot.
    mutating func sizeNewAxisTitles() {
        if categoryAxisTitle != nil, categoryAxisTitleSize == nil { categoryAxisTitleSize = 10 }
        if valueAxisTitle != nil, valueAxisTitleSize == nil { valueAxisTitleSize = 10 }
        if categoryAxisTitle != nil || valueAxisTitle != nil, axisTitleSize == nil { axisTitleBold = true; axisTitleBoldOut = true }
    }
}
