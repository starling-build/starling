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
import OfficeText
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
    /// `pageSetup@blackAndWhite`.
    var blackAndWhite = false
    /// `pageSetup@pageOrder="overThenDown"`.
    var overThenDown = false
    /// `pageSetup@firstPageNumber`, when `useFirstPageNumber` is set.
    var firstPageNumber = 1
    /// Manual page breaks: the rows (columns) a new page starts on,
    /// zero-based as cells are one-based (`<brk id=…>`).
    var rowBreaks: Set<Int> = []
    var colBreaks: Set<Int> = []

    var pageSize: Size { landscape ? Size(paper.height, paper.width) : paper }
    /// The page's width between its side margins.
    var printableWidth: Double { max(36, pageSize.width - left - right) }

    /// The setup a sheet's file carried, from the elements kept as written.
    static func read(_ ws: Worksheet) -> SheetPrintSetup {
        var s = SheetPrintSetup()
        func node(_ name: String) -> XNode? {
            ws.keptElements.first { $0.name == name }.flatMap { XNode.parse(Data($0.text.utf8)) }
        }
        if let m = node("pageMargins") {
            func inch(_ k: String, _ d: Double) -> Double { (Double(m[k] ?? "") ?? d / 72) * 72 }
            // (A left margin no narrower than eight printer dots: at "0"
            // Excel's cells and frame stand 0.96 pt in from the paper's
            // edge — 49609's, lo-tdf131575's, lo-autofilter-colors' and
            // lo-tdf145054's, where ours stood at it. A top margin of 0
            // is 0.)
            s.left = max(0.96, inch("left", s.left)); s.right = inch("right", s.right)
            s.top = inch("top", s.top); s.bottom = inch("bottom", s.bottom)
            s.headerMargin = inch("header", s.headerMargin); s.footerMargin = inch("footer", s.footerMargin)
        }
        // (xsd:boolean: "true" as well as "1" — LibreOffice writes the first.)
        func yes(_ v: String?) -> Bool { v == "1" || v == "true" }
        let fit = yes(node("sheetPr")?.child("pageSetUpPr")?["fitToPage"])
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
            s.blackAndWhite = yes(p["blackAndWhite"])
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
            s.centerHorizontally = yes(o["horizontalCentered"])
            s.centerVertically = yes(o["verticalCentered"])
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
        // (A cell in a hidden row or column is not there to print, and does
        // not stretch the sheet to where it is.)
        for (a, c) in ws.cells where !ws.isRowHidden(a.row) && !ws.isColHidden(a.col) {
            if !c.value.isEmpty { take(a.row, a.col); continue }
            let st = book.style(c.style)
            if st.fill != nil || st.borders != CellStyle.Borders() { take(a.row, a.col) }
        }
        // What an array formula spills into its neighbours is there to print
        // as much as a cell's own value.
        for (a, v) in ws.spilled where !v.isEmpty { take(a.row, a.col) }
        // A merged area is something to print though its cells are empty:
        // Excel gives a sheet of nothing but merges its page.
        for m in ws.merges where m.rows * m.cols <= 100_000 {
            // (Not one that is wholly in hidden rows or columns.)
            guard (m.top ... m.bottom).contains(where: { !ws.isRowHidden($0) }),
                  (m.left ... m.right).contains(where: { !ws.isColHidden($0) }) else { continue }
            take(m.top, m.left); take(m.bottom, m.right)
        }
        // A drawing prints whole, however it is anchored: every cell its
        // frame touches — the one its far corner only reaches the edge of
        // too, which is the cell Excel's anchor names for that corner.
        for d in ws.drawings where !d.hidden && !d.screenOnly {
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
        // A table prints whole in its style's fills and rules, empty or not
        // (lo-TableEmptyHeaders: one empty header row, a table to row 16,
        // and Excel's page is all sixteen rows of it).
        for t in ws.tables where t.style != nil {
            take(t.ref.top, t.ref.left); take(t.ref.bottom, t.ref.right)
        }
        // A row formatted as a whole (a fill or borders on the row itself)
        // prints across the columns in use, cells or no cells.
        for r in ws.rowAttrs.keys {
            guard let s = ws.rowStyle(r) else { continue }
            let st = book.style(s)
            if st.fill != nil || st.borders != CellStyle.Borders() {
                top = min(top, r); bottom = max(bottom, r)
                // Across the row's span, the cells it has no record of take
                // the row's format; a visible one prints (FormatConditionTests'
                // row 1 to H, where lo-user_defined_function's rows record
                // every cell of theirs in their own formats).
                if let c = ws.rowSpanGaps[r]?.last(where: { !ws.isColHidden($0) }) { right = max(right, c) }
            }
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
                    // (A file that names the same area twice prints it once.)
                    if !areas.contains(r.range) { areas.append(r.range) }
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
    /// points, kept free on every page — on every page that starts after
    /// them, given `titleColsEnd`/`titleRowsEnd` (the last title column or
    /// row): a page that shows them as its own does not repeat them, and
    /// has only `headWidth`/`headHeight` (the printed headings) kept free.
    /// lo-tdf113271's first page holds row 1, its title, once: 42 rows
    /// under it, as every page has, where ours kept room for it twice.
    static func pages(area: CellRange, setup: SheetPrintSetup, titleWidth: Double = 0, titleHeight: Double = 0,
                      titleColsEnd: Int? = nil, titleRowsEnd: Int? = nil, headWidth: Double = 0, headHeight: Double = 0,
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
        func bands(_ items: [Int], _ size: (Int) -> Double, _ avail: Double, _ breaks: Set<Int>,
                   own: (end: Int?, room: Double)) -> [[Int]] {
            var out: [[Int]] = [[]]
            var used = 0.0
            // (The room of a band that starts on or before the last title.)
            func room(_ first: Int) -> Double { own.end.map { first <= $0 } ?? false ? own.room : avail }
            for i in items {
                let w = size(i) * s
                if let first = out[out.count - 1].first, used + w > room(first) + 0.01 || breaks.contains(i) { out.append([]); used = 0 }
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
            // (Columns leave the same at a page's side: a lab of 230-dot columns
            // fits 18 with 12 dots to spare, 17 with 6 or none.)
            let side = 8.0 * 72 / 600
            colBands = bands(cols, width, availW - side, fitting ? [] : setup.colBreaks,
                             own: (titleColsEnd, max(18, availW0 - headWidth * s) - side))
            // (A page's rows leave 8 of the printer's dots free at its foot:
            // labs of 100-dot rows on 5,700 dots of room, Excel 16, 2026-10-16
            // — 57 rows fit with 8 dots to spare and not with 7, nor exactly.
            // lo-tdf113271's pages after the first, 5 dots short of that, hold
            // a row fewer than ours did.)
            let foot = 8.0 * 72 / 600
            rowBands = bands(rows, height, availH - foot, fitting ? [] : setup.rowBreaks,
                             own: (titleRowsEnd, max(18, availH0 - headHeight * s) - foot))
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
            printRowScale = 0
            printColumnMax = 0
            printMono = false
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
                if !ws.keptElements.contains(where: { $0.name == "pageSetup" && $0.text.containsSubstring("orientation=") }) { setup.landscape = true }
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
            // its own pages); it stops where the sheet does going down, and
            // going across only when it is whole rows: StructuredRefs-lots-
            // with-lookups' List!A5:L121 is fitted to its width with the empty
            // K and L, at Excel's 65% where ours left them out and made 75%.
            let areas = names.areas.isEmpty ? [used] : names.areas.map { a in
                CellRange(top: a.top, left: a.left, bottom: min(a.bottom, max(a.top, used.bottom)),
                          right: a.right == CellAddress.maxCols - 1 ? max(a.left, used.right) : a.right)
            }
            await _preloadPictures(ws)
            let setup = SheetPrintSetup.read(ws)
            printRowScale = setup.fitWidth == nil && setup.fitHeight == nil ? setup.scale / 100 : 0
            printMono = setup.blackAndWhite
            printColumnMax = setup.fitWidth == nil && setup.fitHeight == nil ? setup.printableWidth / (setup.scale / 100) : 0
            let ca = cols, ra = rows   // in points while printing
            let head = _headingSize(setup, lastRow: areas.map(\.bottom).max() ?? 0)
            let titleH = (names.titleRows.map { $0.reduce(0) { $0 + ra.size($1) } } ?? 0) + head.height
            let titleW = (names.titleCols.map { $0.reduce(0) { $0 + ca.size($1) } } ?? 0) + head.width
            // Every area's pages first: page numbers and the count run across
            // all of them.
            let jobs = areas.map { area -> (pages: [SheetPage], scale: Double) in
                let job = SheetPrintLayout.pages(area: area, setup: setup, titleWidth: titleW, titleHeight: titleH,
                                                 titleColsEnd: names.titleCols?.upperBound, titleRowsEnd: names.titleRows?.upperBound,
                                                 headWidth: head.width, headHeight: head.height,
                                                 width: { ca.size($0) }, height: { ra.size($0) })
                // (With titles repeating, no page is blank: Excel prints them all.)
                if names.titleRows != nil || names.titleCols != nil { return job }
                return (_withoutTrailingBlanks(job.pages, ws: ws, book: book, overThenDown: setup.overThenDown), job.scale)
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

    /// The pages without the blank ones Excel leaves out: those after the
    /// last page that has anything on it — a value, a fill or border, a
    /// merged area, a drawing, text running in from a neighbour. A blank
    /// page between printed ones stays, and the first always does.
    private func _withoutTrailingBlanks(_ pages: [SheetPage], ws: Worksheet, book: Workbook, overThenDown: Bool) -> [SheetPage] {
        guard pages.count > 1 else { return pages }
        // Each row and column to the band it prints in.
        var rowBands: [[Int]] = [], colBands: [[Int]] = []
        for p in pages {
            if !rowBands.contains(p.rows) { rowBands.append(p.rows) }
            if !colBands.contains(p.cols) { colBands.append(p.cols) }
        }
        var rowBand: [Int: Int] = [:], colBand: [Int: Int] = [:]
        for (i, b) in rowBands.enumerated() { for r in b { rowBand[r] = i } }
        for (i, b) in colBands.enumerated() { for c in b { colBand[c] = i } }
        var filled: Set<[Int]> = []   // [row band, column band]
        func fill(_ range: CellRange) {
            let rs = Set((range.top ... range.bottom).compactMap { rowBand[$0] }), cs = Set((range.left ... range.right).compactMap { colBand[$0] })
            for r in rs { for c in cs { filled.insert([r, c]) } }
        }
        for (a, cell) in ws.cells {
            guard let r = rowBand[a.row], let c = colBand[a.col] else { continue }
            if !cell.value.isEmpty {
                filled.insert([r, c])
                if cell.value.isText, let reach = textReach(a, cell, ws: ws, book: book) {
                    fill(CellRange(top: a.row, left: reach.lowerBound, bottom: a.row, right: reach.upperBound))
                }
            } else if cell.style != 0 {
                let st = book.style(cell.style)
                if st.fill != nil || st.borders != CellStyle.Borders() { filled.insert([r, c]) }
            }
        }
        for (a, v) in ws.spilled where !v.isEmpty { fill(CellRange(top: a.row, left: a.col, bottom: a.row, right: a.col)) }
        // (A row formatted as a whole is on every page across it.)
        for row in ws.rowAttrs.keys {
            guard let r = rowBand[row], let style = ws.rowStyle(row) else { continue }
            let st = book.style(style)
            if st.fill != nil || st.borders != CellStyle.Borders() { for c in colBands.indices { filled.insert([r, c]) } }
        }
        for m in ws.merges where m.rows * m.cols <= 100_000 { fill(m) }
        func cover(_ anchor: SheetAnchor) {
            let f = ws.frame(anchor)
            guard f.width > 0, f.height > 0 else { return }
            let a = ws.marker(x: f.x, y: f.y), b = ws.marker(x: f.x + f.width, y: f.y + f.height)
            fill(CellRange(top: a.row, left: a.col, bottom: b.row, right: b.col))
        }
        for d in ws.drawings where !d.hidden && !d.screenOnly { cover(d.anchor) }
        for o in ws.objects where !o.screenOnly { cover(o.anchor) }
        // Only from the end: a blank page with a printed one after it stays.
        var kept = pages
        while kept.count > 1, let last = kept.last,
              let r = rowBands.firstIndex(of: last.rows), let c = colBands.firstIndex(of: last.cols), !filled.contains([r, c]) {
            kept.removeLast()
        }
        return kept
    }

    /// The room printed headings take: a default row's height above the
    /// cells, and to their left the row numbers' digits (three at least)
    /// and 0.42 of the default font's size, in the default font's — Excel's
    /// own strip, 23.4 pt wide in Verdana 10, 16.7 in Arial 8
    /// (lo-tdf131575), 17.1 in Microsoft Sans Serif 8.25 (49609), where
    /// three digits and two thirds of one made 16.2 and 16.6. Nothing when
    /// the sheet prints none.
    private func _headingSize(_ setup: SheetPrintSetup, lastRow: Int) -> Size {
        guard setup.headings else { return Size(0, 0) }
        let book = controller.book
        let size = book.defaultFontSize ?? 11
        let m = SheetPrintMetrics.of(family: book.defaultFontName ?? OfficeFonts.defaultFamily, size: size, bold: book.defaultFontBold)
        return Size(Double(max(3, String(lastRow + 1).count)) * m.digit + 0.42 * size, m.defaultRow)
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
        // (A fitted sheet's rows are whole dots at the scale its pages came
        // out at, as a scaled one's are: lo-tdf58243's 30.75 pt rows step
        // 15.12 at 51% in Excel's print, 126 dots, where ours, unrounded,
        // stepped 15.18 and stood 1.2 low by its page's foot.)
        printRowScale = setup.fitWidth == nil && setup.fitHeight == nil ? setup.scale / 100 : jobs.count == 1 ? jobs[0].scale : 0
        printMono = setup.blackAndWhite
        printColumnMax = setup.fitWidth == nil && setup.fitHeight == nil ? setup.printableWidth / (setup.scale / 100) : 0
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
        let hfFont = GridTextStyle(family: OfficeFonts.sheetFace(book.fontName(hfStyle)),
                                   size: book.fontSize(hfStyle), color: Int64(0xFF000000))
        for (pages, s) in jobs {
            printTextScale = s
            defer { printTextScale = 0 }
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
                // (The cells four printer dots, 0.48 pt, in from the margins
                // and down from them, the drawings not: Excel's first fills
                // at (+0.48, +0.48) from ours in 140 of the 210 workbooks
                // whose page 1 has one — any face, any size; those that
                // were not had a drawing first, which stood where ours did.
                // Not along an axis the page is centred on: there ours stood
                // where Excel's did, or 0.4 right — AverageTaxRates', Tables'
                // and lo-tdf58243's pages, centred, 2.8, 1.8 and 1.8% worse
                // for it, where simple-monthly-budget's, centred across
                // only, came 0.48 nearer down. Across a centred page the
                // cells stand as far the other way: Excel centres them as if
                // 0.96 wider, from its left — the first fills of eleven such
                // pages, at any scale (lo-bnc762542's 36%, 45544's 100%),
                // 0.24 to 0.55 pt left of where plain centring put ours.)
                let inset = 0.48
                // (Down a centred page likewise, as if 0.96 taller: AverageTaxRates'
                // rules, centred both ways, stand 0.48 above plain centring's.)
                let insetX = setup.centerHorizontally ? -inset : inset, insetY = setup.centerVertically ? -inset : inset
                var ox = setup.left + insetX, oy = setup.top + insetY
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
                        let r = drawingRect(d.anchor).shift(Offset(-insetX / s, -insetY / s))
                        // (Nor one set not to print: chart-tdf140489's "Tip"
                        // callout, which the pages' extent already left out.)
                        guard r.overlaps(clip), !d.hidden, !d.screenOnly else { continue }
                        _paintDrawing(canvas, d, chart: charts[i], in: r, theme: book.chartTheme)
                    }
                    canvas.save()
                    canvas.translate(-insetX / s, -insetY / s)
                    _paintObjects(canvas, ws, clip: clip.shift(Offset(insetX / s, insetY / s)))
                    canvas.restore()
                    canvas.restore()
                }
                band(tRows, tCols, head.width, head.height)
                band(tRows, page.cols, tx, head.height)
                band(page.rows, tCols, head.width, ty)
                band(page.rows, page.cols, tx, ty)
                if setup.headings {
                    // The strips: a ruled cell per column and per row, its
                    // letter or number centred across it and at its foot,
                    // in the default font (NumberFormatTests' "2" at the
                    // foot of its 26 pt row, where ours stood in the middle)
                    // — set as a centred cell's text is, at a cell's foot
                    // and four printer dots right of the middle: the
                    // headings of twelve workbooks stood 0.6 to 2 pt lower
                    // in their own style, where their cells' text was on
                    // Excel's baselines.
                    let rule = Paint()
                    rule.style = .stroke
                    rule.strokeWidth = 0.96   // eight printer dots, as Excel rules its headings
                    rule.color = Color(0xFF000000)
                    let headStyle = _textStyle(book.style(0), color: nil, ink: Color(0xFF000000))
                    let centre = 4 * 72 / 600 * scale / s
                    // (The column letters four dots lower again: 0.5 to 0.7 pt
                    // over Excel's in Verdana, Arial and Calibri, where the
                    // row numbers were on its baselines.)
                    func label(_ text: String, in r: Rect, drop: Double = 0) {
                        canvas.drawRect(r, rule)
                        let tp = texts.painter(text, headStyle)
                        canvas.save()
                        canvas.clipRect(r)
                        tp.paint(canvas, Offset(r.left + (r.width - tp.width) / 2 + centre, r.bottom - tp.height - 1 + drop))
                        canvas.restore()
                    }
                    canvas.drawRect(Rect.fromLTWH(0, 0, head.width, head.height), rule)
                    var x = head.width
                    for col in tCols + page.cols {
                        label(CellAddress.columnName(col), in: Rect.fromLTWH(x, 0, ca.size(col), head.height), drop: centre)
                        x += ca.size(col)
                    }
                    var y = head.height
                    for row in tRows + page.rows {
                        label(String(row + 1), in: Rect.fromLTWH(0, y, head.width, ra.size(row)))
                        y += ra.size(row)
                    }
                }
                if setup.headings || setup.gridlines {
                    // A frame round all of it, eight printer dots inside its
                    // edge at any scale (DateFormatTests' black right and
                    // foot, where ours ended in a gridline; lo-tdf100034's
                    // gridlines alone, lo-tdf167019's at 85%).
                    let frame = Paint()
                    frame.style = .stroke
                    frame.strokeWidth = 0.96 / s
                    frame.color = Color(0xFF000000)
                    let h = frame.strokeWidth / 2
                    canvas.drawRect(Rect.fromLTRB(h, h, bandW - h, bandH - h), frame)
                }
                canvas.restore()
                fields.page = setup.firstPageNumber + out.count
                _paintHeaderFooter(canvas, setup: setup, fields: fields, position: out.count + 1, base: hfFont, size: size, scale: s)
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
        let font = GridTextStyle(family: OfficeFonts.sheetFace(book.fontName(st)), size: book.fontSize(st), color: Int64(0xFF000000))
        _paintHeaderFooter(canvas, setup: setup, fields: fields, position: out.count + 1, base: font, size: size)
        out.append(PdfDocument.Page(picture: recorder.endRecording(), width: size.width, height: size.height))
    }

    /// The page's header along the top margin and footer along the bottom:
    /// left, centre and right sections between the side margins. `position`
    /// is the page's place in the job, from 1, which picks the first/even
    /// variant; `fields.page` is the number printed.
    private func _paintHeaderFooter(_ canvas: any Canvas, setup: SheetPrintSetup, fields: HeaderFooterText.Fields,
                                    position: Int, base: GridTextStyle, size: Size, scale: Double = 1) {
        let hf = setup.headerFooter
        guard !hf.isEmpty else { return }
        let k = hf.scaleWithDoc ? scale : 1
        var base = base
        base.size *= k
        func span(_ runs: [HeaderFooterText.Run]) -> TextSpan {
            TextSpan(children: runs.map { r in
                var st = base
                st.bold = r.style.bold; st.italic = r.style.italic
                st.underline = r.style.underline; st.strike = r.style.strike
                if let n = r.style.size { st.size = n * k }
                if let f = r.style.family { st.family = OfficeFonts.sheetFace(f) }
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
                // Excel's header stands 1.2 pt below its margin's line, its
                // footer 1.75 above: on the first pages of the corpus a header
                // at Times 12 is 12.18 under the header margin (ours 11.0),
                // Arial 9.96 10.14 (ours 9.0); a footer's baseline 4.64 over
                // the footer margin at Times 12 (ours 3.05), 3.92 at Arial
                // 9.96 (2.05), 4.8 at Calibri 11.04 (3.0).
                let y = top.map { $0 + 1.2 } ?? (bottom! - tp.height - 1.75)
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
