// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Print and PDF: the active sheet's used area, cut into pages the way
// Excel cuts it — Letter portrait with its Normal margins unless the
// file's page setup says otherwise, columns and rows never split, pages
// numbered down then over, no gridlines or headings unless asked. Each
// page is the grid's own region painter in printing mode (one pixel per
// point, no headers or panes), so a page shows exactly what the screen
// shows, charts and pictures included.

import Flutter
import FlutterSwiftBridge
import Foundation

struct SheetPrintSetup: Equatable {
    var paper = Size(612, 792)          // Letter, in points
    var landscape = false
    /// Excel's Normal margins: 0.7 in at the sides, 0.75 in top and bottom.
    var left = 50.4, right = 50.4, top = 54.0, bottom = 54.0
    /// `pageSetup@scale`, in percent.
    var scale = 100.0
    /// Fit to this many pages wide / tall (0: as many as it takes), when
    /// the sheet asks to fit (`sheetPr/pageSetUpPr@fitToPage`).
    var fitWidth: Int? = nil
    var fitHeight: Int? = nil
    var gridlines = false
    /// `printOptions@headings`: the column letters and row numbers print
    /// too, along the top and left of every page.
    var headings = false
    var centerHorizontally = false
    var centerVertically = false
    /// `pageMargins@header`/`@footer`: the header's top and the footer's
    /// bottom, from the paper's edge. Excel's Normal: 0.3 in.
    var headerMargin = 21.6, footerMargin = 21.6
    var headerFooter = HeaderFooter()
    /// `pageSetup@pageOrder="overThenDown"`.
    var overThenDown = false
    /// `pageSetup@firstPageNumber`, when `useFirstPageNumber` is set.
    var firstPageNumber = 1
    /// Manual page breaks: the rows (columns) a new page starts on,
    /// zero-based as cells are one-based (`<brk id=…>`).
    var rowBreaks: Set<Int> = []
    var colBreaks: Set<Int> = []

    var pageSize: Size { landscape ? Size(paper.height, paper.width) : paper }

    /// The setup a sheet's file carried, from the elements kept as written.
    static func read(_ ws: Worksheet) -> SheetPrintSetup {
        var s = SheetPrintSetup()
        func node(_ name: String) -> XNode? {
            ws.keptElements.first { $0.name == name }.flatMap { XNode.parse(Data($0.text.utf8)) }
        }
        if let m = node("pageMargins") {
            func inch(_ k: String, _ d: Double) -> Double { (Double(m[k] ?? "") ?? d / 72) * 72 }
            s.left = inch("left", s.left); s.right = inch("right", s.right)
            s.top = inch("top", s.top); s.bottom = inch("bottom", s.bottom)
            s.headerMargin = inch("header", s.headerMargin); s.footerMargin = inch("footer", s.footerMargin)
        }
        let fit = node("sheetPr")?.child("pageSetUpPr")?["fitToPage"] == "1"
        if let p = node("pageSetup") {
            // Windows' paper numbers (DMPAPER_*): Letter, Tabloid, Legal,
            // Executive, A3, A4 (and A4 Small), A5, B4 and B5 (JIS), A6.
            let papers: [Int: Size] = [1: Size(612, 792), 2: Size(612, 792), 3: Size(792, 1224), 5: Size(612, 1008),
                                       7: Size(522, 756), 8: Size(841.89, 1190.55), 9: Size(595.28, 841.89),
                                       10: Size(595.28, 841.89), 11: Size(419.53, 595.28), 12: Size(728.5, 1031.81),
                                       13: Size(515.91, 728.5), 70: Size(297.64, 419.53)]
            // (With usePrinterDefaults set false Excel takes the printer's paper,
            // not the sheet's: nine of the corpus say A4 that way and print Letter.)
            let printers = p["usePrinterDefaults"] == "false" || p["usePrinterDefaults"] == "0"
            if !printers, let n = Int(p["paperSize"] ?? ""), let size = papers[n] { s.paper = size }
            s.landscape = p["orientation"] == "landscape"
            if let v = Double(p["scale"] ?? ""), v >= 10, v <= 400 { s.scale = v }
            s.overThenDown = p["pageOrder"] == "overThenDown"
            if p["useFirstPageNumber"] == "1" || p["useFirstPageNumber"] == "true",
               let n = Int(p["firstPageNumber"] ?? "") { s.firstPageNumber = n }
            if fit {
                s.fitWidth = Int(p["fitToWidth"] ?? "") ?? 1
                s.fitHeight = Int(p["fitToHeight"] ?? "") ?? 1
            }
        } else if fit {
            s.fitWidth = 1; s.fitHeight = 1
        }
        if let o = node("printOptions") {
            s.gridlines = o["gridLines"] == "1" || o["gridLines"] == "true"
            s.headings = o["headings"] == "1" || o["headings"] == "true"
            s.centerHorizontally = o["horizontalCentered"] == "1"
            s.centerVertically = o["verticalCentered"] == "1"
        }
        if let h = node("headerFooter") { s.headerFooter = HeaderFooter.read(h) }
        func breaks(_ name: String) -> Set<Int> {
            Set((node(name)?.kids("brk") ?? []).compactMap { Int($0["id"] ?? "") })
        }
        s.rowBreaks = breaks("rowBreaks"); s.colBreaks = breaks("colBreaks")
        return s
    }
}

/// One printed page: the columns and rows it shows.
struct SheetPage: Equatable {
    var cols: [Int]
    var rows: [Int]
}

enum SheetPrintLayout {
    /// What prints: from A1 — Excel's pages start there however far in
    /// the first cell is — to the last cell holding a value or a visible
    /// format (fill or border), widened to take in drawings.
    static func usedArea(_ ws: Worksheet, book: Workbook) -> CellRange? {
        var top = Int.max, left = Int.max, bottom = -1, right = -1
        func take(_ row: Int, _ col: Int) {
            top = min(top, row); left = min(left, col); bottom = max(bottom, row); right = max(right, col)
        }
        for (a, c) in ws.cells {
            if !c.value.isEmpty { take(a.row, a.col); continue }
            let st = book.style(c.style)
            if st.fill != nil || st.borders != CellStyle.Borders() { take(a.row, a.col) }
        }
        // A row someone gave a height is part of the sheet in use, cells or
        // none: an empty one below the last cell still takes its room on paper.
        for (r, h) in ws.rowHeights where h > 0 && !ws.fittedRows.contains(r) && !ws.cells.isEmpty { top = min(top, r); bottom = max(bottom, r) }
        // A merged area is something to print though its cells are empty:
        // Excel gives a sheet of nothing but merges its page.
        for m in ws.merges { take(m.top, m.left); take(m.bottom, m.right) }
        // A drawing prints whole, however it is anchored: every cell its
        // frame touches — the one its far corner only reaches the edge of
        // too, which is the cell Excel's anchor names for that corner.
        for d in ws.drawings where !d.hidden {
            var f = ws.frame(d.anchor)
            guard f.width > 0, f.height > 0 else { continue }
            // A turned shape covers what its turned outline covers, which is
            // not what its anchor spans.
            if case .shape(let shape) = d.kind, shape.rotation != 0 {
                let r = shape.unturned(Rect.fromLTWH(f.x, f.y, f.width, f.height))
                let a = shape.rotation * .pi / 180
                let w = abs(r.width * cos(a)) + abs(r.height * sin(a)), h = abs(r.width * sin(a)) + abs(r.height * cos(a))
                f = (max(0, r.center.dx - w / 2), max(0, r.center.dy - h / 2), w, h)
            }
            let a = ws.marker(x: f.x, y: f.y), b = ws.marker(x: f.x + f.width, y: f.y + f.height)
            take(a.row, a.col); take(b.row, b.col)
        }
        for o in ws.objects where !o.screenOnly {
            let f = ws.frame(o.anchor)
            guard f.width > 0, f.height > 0 else { continue }
            let a = ws.marker(x: f.x, y: f.y), b = ws.marker(x: f.x + f.width, y: f.y + f.height)
            take(a.row, a.col); take(b.row, b.col)
        }
        // A row formatted as a whole (a fill or borders on the row itself)
        // prints across the columns in use, cells or no cells.
        for r in ws.rowAttrs.keys {
            guard let s = ws.rowStyle(r) else { continue }
            let st = book.style(s)
            if st.fill != nil || st.borders != CellStyle.Borders() { top = min(top, r); bottom = max(bottom, r) }
        }
        guard bottom >= 0 else { return nil }
        return CellRange(top: 0, left: 0, bottom: bottom, right: max(0, right))
    }

    /// The sheet's print areas and repeated titles, from the file's
    /// built-in names (`_xlnm.Print_Area`, `_xlnm.Print_Titles`).
    static func printNames(_ book: Workbook, sheet: Int) -> (areas: [CellRange], titleRows: ClosedRange<Int>?, titleCols: ClosedRange<Int>?) {
        var areas: [CellRange] = []
        var rows: ClosedRange<Int>? = nil, cols: ClosedRange<Int>? = nil
        for n in book.fileNames where n.localSheet == sheet {
            for part in n.text.split(separator: ",") {
                guard let e = try? Formula.parse("=" + part), case .ref(let r) = e else { continue }
                let end = r.end ?? r.start
                if n.name == "_xlnm.Print_Area" {
                    areas.append(r.range)
                } else if n.name == "_xlnm.Print_Titles" {
                    if r.start.col == nil, let a = r.start.row, let b = end.row { rows = min(a, b) ... max(a, b) }
                    if r.start.row == nil, let a = r.start.col, let b = end.col { cols = min(a, b) ... max(a, b) }
                }
            }
        }
        return (areas, rows, cols)
    }

    /// Cut `area` into pages. `width`/`height` give a column's or row's
    /// size in points (0 for hidden). Returns the pages, down then over
    /// (over then down when the setup says so), and the scale they print
    /// at. A manual break starts a page whatever room is left.
    /// `titleWidth`/`titleHeight`: the repeated title columns and rows, in
    /// points, kept free on every page.
    static func pages(area: CellRange, setup: SheetPrintSetup, titleWidth: Double = 0, titleHeight: Double = 0,
                      width: (Int) -> Double, height: (Int) -> Double) -> (pages: [SheetPage], scale: Double) {
        let page = setup.pageSize
        let availW0 = max(36, page.width - setup.left - setup.right)
        let availH0 = max(36, page.height - setup.top - setup.bottom)
        let cols = (area.left ... area.right).filter { width($0) > 0 }
        let rows = (area.top ... area.bottom).filter { height($0) > 0 }
        guard !cols.isEmpty, !rows.isEmpty else { return ([], 1) }
        var s = setup.scale / 100
        if setup.fitWidth != nil || setup.fitHeight != nil {
            // Fit only ever shrinks, never past 10%, as Excel's.
            s = 1
            let totalW = cols.reduce(0) { $0 + width($1) }, totalH = rows.reduce(0) { $0 + height($1) }
            if let n = setup.fitWidth, n > 0 { s = min(s, availW0 * Double(n) / (totalW + titleWidth * Double(n))) }
            if let n = setup.fitHeight, n > 0 { s = min(s, availH0 * Double(n) / (totalH + titleHeight * Double(n))) }
            // Excel's fit is a whole percent, the largest at which the pages
            // asked for hold everything.
            s = max(0.1, (s * 100).rounded(.down) / 100)
        }
        func bands(_ items: [Int], _ size: (Int) -> Double, _ avail: Double, _ breaks: Set<Int>) -> [[Int]] {
            var out: [[Int]] = [[]]
            var used = 0.0
            for i in items {
                let w = size(i) * s
                if !out[out.count - 1].isEmpty && (used + w > avail + 0.01 || breaks.contains(i)) { out.append([]); used = 0 }
                out[out.count - 1].append(i)
                used += w
            }
            return out
        }
        var colBands: [[Int]] = [], rowBands: [[Int]] = []
        while true {
            let availW = max(18, availW0 - titleWidth * s), availH = max(18, availH0 - titleHeight * s)
            // (Fitting ignores manual breaks: they are for the unfitted sheet.)
            let fitting = setup.fitWidth != nil || setup.fitHeight != nil
            colBands = bands(cols, width, availW, fitting ? [] : setup.colBreaks)
            rowBands = bands(rows, height, availH, fitting ? [] : setup.rowBreaks)
            // Rows and columns do not split, so the arithmetic's scale can
            // still be a page over: a percent less until it is not.
            let over = (setup.fitWidth.map { $0 > 0 && colBands.count > $0 } ?? false)
                || (setup.fitHeight.map { $0 > 0 && rowBands.count > $0 } ?? false)
            guard over, s > 0.1 else { break }
            s = max(0.1, s - 0.01)
        }
        var pages: [SheetPage] = []
        if setup.overThenDown {
            for rb in rowBands { for cb in colBands { pages.append(SheetPage(cols: cb, rows: rb)) } }
        } else {
            for cb in colBands { for rb in rowBands { pages.append(SheetPage(cols: cb, rows: rb)) } }
        }
        return (pages, s)
    }
}

extension SheetGridState {
    /// The active sheet as PDF pages — or, with `wholeBook`, every visible
    /// sheet in tab order, as Excel's "Entire Workbook" prints: one job,
    /// its pages numbered and counted across the sheets. False when there
    /// is nothing to print or the file could not be written. `maxPages`
    /// stops a runaway sheet (the rendering gate's cap).
    @MainActor
    func writePdf(to path: String, title: String, filePath: String? = nil,
                  wholeBook: Bool = false, maxPages: Int? = nil) async -> Bool {
        let c = controller
        let book = c.book
        let savedSheet = c.activeSheet
        let savedX = scrollX, savedY = scrollY
        printing = true
        defer {
            printing = false
            if c.activeSheet != savedSheet { c.activeSheet = savedSheet }
            scrollX = savedX; scrollY = savedY
        }
        /// One sheet's part of the job: what it prints and how it is cut.
        struct Part {
            var sheet: Int
            var setup: SheetPrintSetup
            var names: (areas: [CellRange], titleRows: ClosedRange<Int>?, titleCols: ClosedRange<Int>?)
            var jobs: [(pages: [SheetPage], scale: Double)]
        }
        var parts: [Part] = []
        let indices = wholeBook ? book.sheets.indices.filter { !book.sheets[$0].hidden } : [savedSheet]
        for si in indices {
            if c.activeSheet != si { c.activeSheet = si }
            let ws = c.sheet
            if ws.isChartSheet {
                // A chart sheet is one page, its chart filling it.
                guard ws.drawings.contains(where: { $0.isChart && !$0.hidden }) else { continue }
                var setup = SheetPrintSetup.read(ws)
                if !ws.keptElements.contains(where: { $0.name == "pageSetup" && $0.text.contains("orientation=") }) { setup.landscape = true }
                parts.append(Part(sheet: si, setup: setup, names: ([], nil, nil), jobs: [([SheetPage(cols: [], rows: [])], 1)]))
                continue
            }
            guard var used = SheetPrintLayout.usedArea(ws, book: book) else { continue }
            // Text running over empty cells prints to its end, as Excel's does:
            // the columns it crosses are part of what prints.
            for (a, cell) in ws.cells where cell.value.isText {
                guard let reach = textReach(a, cell, ws: ws, book: book) else { continue }
                used.left = min(used.left, reach.lowerBound); used.right = max(used.right, reach.upperBound)
            }
            let names = SheetPrintLayout.printNames(book, sheet: si)
            // A print area prints instead of the used one (each of several on
            // its own pages); a whole-column or whole-row area stops where the
            // sheet does.
            let areas = names.areas.isEmpty ? [used] : names.areas.map { a in
                CellRange(top: a.top, left: a.left, bottom: min(a.bottom, max(a.top, used.bottom)), right: min(a.right, max(a.left, used.right)))
            }
            await _preloadPictures(ws)
            let setup = SheetPrintSetup.read(ws)
            let ca = cols, ra = rows   // in points while printing
            let head = _headingSize(setup, lastRow: areas.map(\.bottom).max() ?? 0)
            let titleH = (names.titleRows.map { $0.reduce(0) { $0 + ra.size($1) } } ?? 0) + head.height
            let titleW = (names.titleCols.map { $0.reduce(0) { $0 + ca.size($1) } } ?? 0) + head.width
            // Every area's pages first: page numbers and the count run across
            // all of them.
            let jobs = areas.map { area in
                SheetPrintLayout.pages(area: area, setup: setup, titleWidth: titleW, titleHeight: titleH,
                                       width: { ca.size($0) }, height: { ra.size($0) })
            }
            parts.append(Part(sheet: si, setup: setup, names: names, jobs: jobs))
        }
        let pageCount = parts.reduce(0) { $0 + $1.jobs.reduce(0) { $0 + $1.pages.count } }
        guard pageCount > 0 else { return false }
        var out: [PdfDocument.Page] = []
        for part in parts {
            if let maxPages, out.count >= maxPages { break }
            if c.activeSheet != part.sheet { c.activeSheet = part.sheet }
            _paintPart(sheet: part.sheet, setup: part.setup, names: part.names, jobs: part.jobs, pageCount: pageCount,
                       title: title, filePath: filePath, maxPages: maxPages, into: &out)
        }
        return PdfDocument.write(to: path, pages: out, title: title, author: PdfExport.authorName())
    }

    /// The room printed headings take: a default row's height above the
    /// cells, and to their left the row numbers' digits (three at least)
    /// and a cell's padding, in the default font's — Excel's own strip,
    /// 23.4 pt wide in Verdana 10. Nothing when the sheet prints none.
    private func _headingSize(_ setup: SheetPrintSetup, lastRow: Int) -> Size {
        guard setup.headings else { return Size(0, 0) }
        let book = controller.book
        let m = SheetPrintMetrics.of(family: book.defaultFontName ?? OfficeFonts.defaultFamily, size: book.defaultFontSize ?? 11)
        return Size((Double(max(3, String(lastRow + 1).count)) + 0.65) * m.digit, m.defaultRow)
    }

    /// The active sheet's pages, appended to `out`.
    private func _paintPart(sheet: Int, setup: SheetPrintSetup,
                            names: (areas: [CellRange], titleRows: ClosedRange<Int>?, titleCols: ClosedRange<Int>?),
                            jobs: [(pages: [SheetPage], scale: Double)], pageCount: Int,
                            title: String, filePath: String?, maxPages: Int?, into out: inout [PdfDocument.Page]) {
        let c = controller
        let ws = c.sheet, book = c.book
        if ws.isChartSheet {
            _paintChartSheet(ws, setup: setup, pageCount: pageCount, title: title, filePath: filePath, maxPages: maxPages, into: &out)
            return
        }
        let ca = cols, ra = rows   // in points while printing
        let titleRows = names.titleRows.map { Array($0).filter { ra.size($0) > 0 } } ?? []
        let titleCols = names.titleCols.map { Array($0).filter { ca.size($0) > 0 } } ?? []
        let titleH = titleRows.reduce(0) { $0 + ra.size($1) }, titleW = titleCols.reduce(0) { $0 + ca.size($1) }
        let head = _headingSize(setup, lastRow: jobs.flatMap { $0.pages }.compactMap { $0.rows.last }.max() ?? 0)
        let size = setup.pageSize
        // (Excel prints its gridlines black.)
        let colors = _Colors(ink: Color(0xFF000000), paper: Color(0xFFFFFFFF), grid: Color(0xFF000000), showGrid: setup.gridlines)
        let charts = ws.drawings.map { d -> Chart? in
            if case .chart(let sc) = d.kind { return c.liveChart(sc) }
            return nil
        }
        var fields = HeaderFooterText.Fields(pages: pageCount, file: title, sheet: ws.name,
                                             path: filePath.map { $0.deletingLastPathComponent } ?? "")
        let hfStyle = book.style(0)
        let hfFont = GridTextStyle(family: OfficeFonts.substitute(book.fontName(hfStyle)),
                                   size: book.fontSize(hfStyle), color: Int64(0xFF000000))
        for (pages, s) in jobs {
            for page in pages {
                if let maxPages, out.count >= maxPages { return }
                guard let c0 = page.cols.first, let c1 = page.cols.last, let r0 = page.rows.first, let r1 = page.rows.last else { continue }
                // Titles repeat on pages that do not already show them.
                let tRows = titleRows.last.map { r0 > $0 } ?? false ? titleRows : []
                let tCols = titleCols.last.map { c0 > $0 } ?? false ? titleCols : []
                let tx = (tCols.isEmpty ? 0 : titleW) + head.width, ty = (tRows.isEmpty ? 0 : titleH) + head.height
                let bandW = ca.start(c1) + ca.size(c1) - ca.start(c0) + tx
                let bandH = ra.start(r1) + ra.size(r1) - ra.start(r0) + ty
                let recorder = NativePictureRecorder()
                let canvas = NativeCanvas(recorder: recorder, cullRect: Rect.fromLTWH(0, 0, size.width, size.height))
                var ox = setup.left, oy = setup.top
                let availW = size.width - setup.left - setup.right, availH = size.height - setup.top - setup.bottom
                if setup.centerHorizontally { ox += max(0, (availW - bandW * s) / 2) }
                if setup.centerVertically { oy += max(0, (availH - bandH * s) / 2) }
                canvas.save()
                canvas.translate(ox, oy)
                canvas.scale(s, s)
                /// One block of rows and columns with its top-left at (x, y).
                func band(_ rs: [Int], _ cs: [Int], _ x: Double, _ y: Double) {
                    guard let br0 = rs.first, let br1 = rs.last, let bc0 = cs.first, let bc1 = cs.last else { return }
                    scrollX = ca.start(bc0) - x
                    scrollY = ra.start(br0) - y
                    let clip = Rect.fromLTWH(x, y, ca.start(bc1) + ca.size(bc1) - ca.start(bc0), ra.start(br1) + ra.size(br1) - ra.start(br0))
                    let view = CellRange(top: br0, left: bc0, bottom: br1, right: bc1)
                    var covered: Set<CellAddress> = []
                    var merges: [CellRange] = []
                    for m in ws.merges where m.intersects(view) && m.rows * m.cols <= 100_000 {
                        merges.append(m)
                        for rr in m.top ... m.bottom { for cc in m.left ... m.right where !(rr == m.top && cc == m.left) {
                            covered.insert(CellAddress(row: rr, col: cc))
                        } }
                    }
                    canvas.save()
                    canvas.clipRect(clip)
                    _paintRegion(canvas, rows: rs, cols: cs, clip: clip, ws: ws, book: book, merges: merges, covered: covered, colors: colors)
                    for (i, d) in ws.drawings.enumerated() {
                        let r = drawingRect(d.anchor)
                        guard r.overlaps(clip), !d.hidden else { continue }
                        _paintDrawing(canvas, d, chart: charts[i], in: r, theme: book.chartTheme)
                    }
                    _paintObjects(canvas, ws, clip: clip)
                    canvas.restore()
                }
                band(tRows, tCols, head.width, head.height)
                band(tRows, page.cols, tx, head.height)
                band(page.rows, tCols, head.width, ty)
                band(page.rows, page.cols, tx, ty)
                if setup.headings {
                    // The strips: a ruled cell per column and per row, its
                    // letter or number centred, in the default font.
                    let rule = Paint()
                    rule.style = .stroke
                    rule.strokeWidth = 0.75
                    rule.color = Color(0xFF000000)
                    func label(_ text: String, in r: Rect) {
                        canvas.drawRect(r, rule)
                        let tp = TextPainter(text: TextSpan(text: text, style: hfFont.flutter), textAlign: .center, textDirection: .ltr)
                        tp.layout(minWidth: 0, maxWidth: .infinity)
                        canvas.save()
                        canvas.clipRect(r)
                        tp.paint(canvas, Offset(r.left + (r.width - tp.width) / 2, r.top + (r.height - tp.height) / 2))
                        canvas.restore()
                        tp.dispose()
                    }
                    canvas.drawRect(Rect.fromLTWH(0, 0, head.width, head.height), rule)
                    var x = head.width
                    for col in tCols + page.cols {
                        label(CellAddress.columnName(col), in: Rect.fromLTWH(x, 0, ca.size(col), head.height))
                        x += ca.size(col)
                    }
                    var y = head.height
                    for row in tRows + page.rows {
                        label(String(row + 1), in: Rect.fromLTWH(0, y, head.width, ra.size(row)))
                        y += ra.size(row)
                    }
                }
                canvas.restore()
                fields.page = setup.firstPageNumber + out.count
                _paintHeaderFooter(canvas, setup: setup, fields: fields, position: out.count + 1, base: hfFont, size: size)
                out.append(PdfDocument.Page(picture: recorder.endRecording(), width: size.width, height: size.height))
            }
        }
    }

    /// A chart sheet's page: the chart between the margins, in from them
    /// by as much as the drawing stands in from the sheet's corner (Excel's
    /// 2.7 pt), landscape unless the sheet says otherwise.
    private func _paintChartSheet(_ ws: Worksheet, setup: SheetPrintSetup, pageCount: Int, title: String, filePath: String?,
                                  maxPages: Int?, into out: inout [PdfDocument.Page]) {
        if let maxPages, out.count >= maxPages { return }
        guard let d = ws.drawings.first(where: { $0.isChart && !$0.hidden }), case .chart(let sc) = d.kind else { return }
        let book = controller.book
        let size = setup.pageSize
        var inset = 0.0
        if case .absolute(let x, _, _, _) = d.anchor { inset = min(18, max(0, x)) }
        let r = Rect.fromLTRB(setup.left + inset, setup.top + inset, size.width - setup.right - inset, size.height - setup.bottom - inset)
        let recorder = NativePictureRecorder()
        let canvas = NativeCanvas(recorder: recorder, cullRect: Rect.fromLTWH(0, 0, size.width, size.height))
        _paintDrawing(canvas, d, chart: controller.liveChart(sc), in: r, theme: book.chartTheme)
        var fields = HeaderFooterText.Fields(pages: pageCount, file: title, sheet: ws.name,
                                             path: filePath.map { $0.deletingLastPathComponent } ?? "")
        fields.page = setup.firstPageNumber + out.count
        let st = book.style(0)
        let font = GridTextStyle(family: OfficeFonts.substitute(book.fontName(st)), size: book.fontSize(st), color: Int64(0xFF000000))
        _paintHeaderFooter(canvas, setup: setup, fields: fields, position: out.count + 1, base: font, size: size)
        out.append(PdfDocument.Page(picture: recorder.endRecording(), width: size.width, height: size.height))
    }

    /// The page's header along the top margin and footer along the bottom:
    /// left, centre and right sections between the side margins. `position`
    /// is the page's place in the job, from 1, which picks the first/even
    /// variant; `fields.page` is the number printed.
    private func _paintHeaderFooter(_ canvas: any Canvas, setup: SheetPrintSetup, fields: HeaderFooterText.Fields,
                                    position: Int, base: GridTextStyle, size: Size) {
        let hf = setup.headerFooter
        guard !hf.isEmpty else { return }
        func span(_ runs: [HeaderFooterText.Run]) -> TextSpan {
            TextSpan(children: runs.map { r in
                var st = base
                st.bold = r.style.bold; st.italic = r.style.italic
                st.underline = r.style.underline; st.strike = r.style.strike
                if let n = r.style.size { st.size = n }
                if let f = r.style.family { st.family = OfficeFonts.substitute(f) }
                if let c = r.style.color { st.color = c }
                return TextSpan(text: r.text, style: st.flutter)
            }, style: base.flutter)
        }
        let innerW = size.width - setup.left - setup.right
        func paint(_ text: String, top: Double?, bottom: Double?) {
            guard !text.isEmpty else { return }
            let sections = HeaderFooterText.parse(text)
            for (i, items) in [sections.left, sections.center, sections.right].enumerated() where !items.isEmpty {
                let tp = TextPainter(text: span(HeaderFooterText.runs(items, fields: fields)),
                                     textAlign: i == 0 ? .left : i == 1 ? .center : .right, textDirection: .ltr)
                tp.layout(minWidth: 0, maxWidth: .infinity)
                let x = i == 0 ? setup.left : i == 1 ? setup.left + (innerW - tp.width) / 2 : size.width - setup.right - tp.width
                let y = top ?? (bottom! - tp.height)
                tp.paint(canvas, Offset(x, y))
                tp.dispose()
            }
        }
        paint(hf.header(page: position), top: setup.headerMargin, bottom: nil)
        paint(hf.footer(page: position), top: nil, bottom: size.height - setup.footerMargin)
    }

    /// Decode every picture first: a page records what is decoded now.
    /// Awaited, not started and polled for: an export waits exactly as
    /// long as the decode takes, and not at all for one that failed.
    @MainActor
    private func _preloadPictures(_ ws: Worksheet) async {
        var pictures: [(String, Data)] = ws.drawings.compactMap { d in
            if case .picture(let key, let data) = d.kind { return (key, data) }
            return nil
        }
        pictures += ws.objects.compactMap { o in
            if case .preview(let key, let data) = o.kind { return (key, data) }
            return nil
        }
        for (key, data) in pictures {
            // A metafile is played, not decoded — but the bitmaps it draws are.
            if let played = _metafile(key, data) {
                for bitmap in played.bitmaps { await _decodeNow(bitmap.id, bitmap.data) }
            } else {
                await _decodeNow(key, data)
            }
        }
    }
}
