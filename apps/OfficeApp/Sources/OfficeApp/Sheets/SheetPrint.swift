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
            let papers: [Int: Size] = [1: Size(612, 792), 5: Size(612, 1008), 8: Size(841.89, 1190.55),
                                       9: Size(595.28, 841.89), 11: Size(419.53, 595.28)]
            if let n = Int(p["paperSize"] ?? ""), let size = papers[n] { s.paper = size }
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
    /// What prints: from the first to the last cell holding a value or a
    /// visible format (fill or border), widened to take in drawings.
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
        for d in ws.drawings {
            switch d.anchor {
            case .twoCell(let from, let to): take(from.row, from.col); take(to.row, to.col)
            case .oneCell(let from, _, _): take(from.row, from.col)
            case .absolute: break
            }
        }
        guard bottom >= 0 else { return nil }
        return CellRange(top: top, left: left, bottom: bottom, right: right)
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
            s = max(0.1, s * 0.999)   // a hair under, so rounding never spills a page
        }
        let availW = max(18, availW0 - titleWidth * s), availH = max(18, availH0 - titleHeight * s)
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
        let colBands = bands(cols, width, availW, setup.colBreaks), rowBands = bands(rows, height, availH, setup.rowBreaks)
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
    /// The active sheet as PDF pages; false when there is nothing to print
    /// or the file could not be written.
    func writePdf(to path: String, title: String, filePath: String? = nil) async -> Bool {
        let c = controller
        let ws = c.sheet, book = c.book
        guard let used = SheetPrintLayout.usedArea(ws, book: book) else { return false }
        let names = SheetPrintLayout.printNames(book, sheet: c.activeSheet)
        // A print area prints instead of the used one (each of several on
        // its own pages); a whole-column or whole-row area stops where the
        // sheet does.
        let areas = names.areas.isEmpty ? [used] : names.areas.map { a in
            CellRange(top: a.top, left: a.left, bottom: min(a.bottom, max(a.top, used.bottom)), right: min(a.right, max(a.left, used.right)))
        }
        await _preloadPictures(ws)
        let setup = SheetPrintSetup.read(ws)
        let savedX = scrollX, savedY = scrollY
        printing = true
        defer {
            printing = false
            scrollX = savedX; scrollY = savedY
        }
        let ca = cols, ra = rows   // in points while printing
        let titleRows = names.titleRows.map { Array($0).filter { ra.size($0) > 0 } } ?? []
        let titleCols = names.titleCols.map { Array($0).filter { ca.size($0) > 0 } } ?? []
        let titleH = titleRows.reduce(0) { $0 + ra.size($1) }, titleW = titleCols.reduce(0) { $0 + ca.size($1) }
        let size = setup.pageSize
        let colors = _Colors(ink: Color(0xFF000000), paper: Color(0xFFFFFFFF), grid: Color(0xFFBFBFBF), showGrid: setup.gridlines)
        let charts = ws.drawings.map { d -> Chart? in
            if case .chart(let sc) = d.kind { return c.liveChart(sc) }
            return nil
        }
        var out: [PdfDocument.Page] = []
        // Every area's pages first: page numbers and the count run across
        // all of them.
        let jobs = areas.map { area in
            SheetPrintLayout.pages(area: area, setup: setup, titleWidth: titleW, titleHeight: titleH,
                                   width: { ca.size($0) }, height: { ra.size($0) })
        }
        let pageCount = jobs.reduce(0) { $0 + $1.pages.count }
        var fields = HeaderFooterText.Fields(pages: pageCount, file: title, sheet: ws.name,
                                             path: filePath.map { $0.deletingLastPathComponent } ?? "")
        let hfStyle = book.style(0)
        let hfFont = GridTextStyle(family: OfficeFonts.substitute(hfStyle.fontName ?? OfficeFonts.defaultFamily),
                                   size: hfStyle.fontSize ?? 11, color: Int64(0xFF000000))
        for (pages, s) in jobs {
            for page in pages {
                guard let c0 = page.cols.first, let c1 = page.cols.last, let r0 = page.rows.first, let r1 = page.rows.last else { continue }
                // Titles repeat on pages that do not already show them.
                let tRows = titleRows.last.map { r0 > $0 } ?? false ? titleRows : []
                let tCols = titleCols.last.map { c0 > $0 } ?? false ? titleCols : []
                let tx = tCols.isEmpty ? 0 : titleW, ty = tRows.isEmpty ? 0 : titleH
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
                        guard r.overlaps(clip) else { continue }
                        _paintDrawing(canvas, d, chart: charts[i], in: r, theme: book.chartTheme)
                    }
                    canvas.restore()
                }
                band(tRows, tCols, 0, 0)
                band(tRows, page.cols, tx, 0)
                band(page.rows, tCols, 0, ty)
                band(page.rows, page.cols, tx, ty)
                canvas.restore()
                fields.page = setup.firstPageNumber + out.count
                _paintHeaderFooter(canvas, setup: setup, fields: fields, position: out.count + 1, base: hfFont, size: size)
                out.append(PdfDocument.Page(picture: recorder.endRecording(), width: size.width, height: size.height))
            }
        }
        return PdfDocument.write(to: path, pages: out, title: title, author: PdfExport.authorName())
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
    private func _preloadPictures(_ ws: Worksheet) async {
        for d in ws.drawings {
            guard case .picture(let key, let data) = d.kind, _image(key, data) == nil else { continue }
            for _ in 0 ..< 200 {
                try? await Task.sleep(nanoseconds: 10_000_000)
                if _image(key, data) != nil { break }
            }
        }
    }
}
