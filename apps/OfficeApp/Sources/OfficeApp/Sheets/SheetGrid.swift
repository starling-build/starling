// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The grid: one CustomPaint draws the visible window of a sheet — row and
// column headers, gridlines, values, the selection — straight from the
// model, so a screen of cells costs one paint, not thousands of widgets.
// The framework has no 2D viewport, so scrolling is this view's own
// offset, moved by the wheel, the trackpad and the keyboard.
//
// Editing is drawn here too, as Excel has it: typing on a selected cell
// replaces it ("Enter" mode: the arrows commit and move), F2 or a double
// click edits what is there ("Edit" mode: the arrows move the caret).
// One focus node takes every key, so there is no hand-off between a
// grid and an editor widget to get wrong.

import Flutter
import OfficeText
import FlutterSwiftBridge
import FluentSystemIcons
import Foundation

/// Sizes along one axis: a default, and the rows or columns that differ.
struct GridAxis {
    let def: Double
    /// The indices with their own size, ascending, their sizes, and how far
    /// each one starts from where it would at the default size.
    private let _keys: [Int]
    private let _sizes: [Double]
    private let _shift: [Double]

    init(def: Double, overrides: [Int: Double], hidden: Set<Int> = [], scale: Double) {
        self.def = def * scale
        var all = overrides
        for i in hidden { all[i] = 0 }
        let sorted = all.sorted { $0.key < $1.key }
        _keys = sorted.map(\.key)
        _sizes = sorted.map { $0.value * scale }
        var shift: [Double] = []
        shift.reserveCapacity(sorted.count)
        var acc = 0.0
        for s in _sizes { shift.append(acc); acc += s - self.def }
        _shift = shift
    }

    /// The first position in `_keys` at or past `i`.
    private func _lower(_ i: Int) -> Int {
        var lo = 0, hi = _keys.count
        while lo < hi { let mid = (lo + hi) / 2; if _keys[mid] < i { lo = mid + 1 } else { hi = mid } }
        return lo
    }

    func size(_ i: Int) -> Double {
        let n = _lower(i)
        return n < _keys.count && _keys[n] == i ? _sizes[n] : def
    }

    /// Distance from index 0's start to index `i`'s start.
    func start(_ i: Int) -> Double {
        let n = _lower(i)
        let extra = n < _keys.count ? _shift[n] : (_keys.isEmpty ? 0 : _shift[n - 1] + _sizes[n - 1] - def)
        return Double(i) * def + extra
    }

    /// The index whose span contains `x` (x ≥ 0). Zero-sized (hidden)
    /// indices contain nothing.
    func index(at x: Double) -> Int {
        // The last override starting at or before x.
        var lo = 0, hi = _keys.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if Double(_keys[mid]) * def + _shift[mid] <= x { lo = mid + 1 } else { hi = mid }
        }
        guard lo > 0 else { return Int(max(0, x) / def) }
        let n = lo - 1
        let s = Double(_keys[n]) * def + _shift[n]
        if x < s + _sizes[n] { return _keys[n] }
        return _keys[n] + 1 + Int((x - s - _sizes[n]) / def)
    }
}

/// The cell being edited.
struct CellEdit {
    var cell: CellAddress
    var text: [Character]
    var caret: Int
    /// Typing replaced the cell: the arrows commit and move on.
    var enterMode: Bool
}

/// Where a right click landed: the menu differs for headers.
enum GridMenuArea: Equatable { case cells, columns, rows, drawing(Int) }

final class SheetGrid: StatefulWidget {
    let controller: WorkbookController
    let zoom: Double
    /// The editor's text changed (the formula bar mirrors it), or nil when
    /// editing ended.
    let onEditText: (String?) -> Void
    /// A chord the grid does not handle itself (the shell's ⌘S, ⌘O…).
    let onShortcut: (Character, KeyChordTracker) -> Bool
    let onStatus: (String) -> Void
    /// A right click, at a global position, after the selection was
    /// moved under it (when it was not already inside).
    let onContextMenu: (Offset, GridMenuArea) -> Void
    /// A filter dropdown was pressed: where to open its menu (global), and the column.
    let onFilterMenu: (Offset, Int) -> Void
    /// A validation list's arrow was pressed: where (global), the cell, its choices.
    let onListMenu: (Offset, CellAddress, [String]) -> Void

    init(key: (any Key)? = nil, controller: WorkbookController, zoom: Double,
         onEditText: @escaping (String?) -> Void,
         onShortcut: @escaping (Character, KeyChordTracker) -> Bool,
         onStatus: @escaping (String) -> Void,
         onContextMenu: @escaping (Offset, GridMenuArea) -> Void = { _, _ in },
         onFilterMenu: @escaping (Offset, Int) -> Void = { _, _ in },
         onListMenu: @escaping (Offset, CellAddress, [String]) -> Void = { _, _, _ in }) {
        self.controller = controller
        self.zoom = zoom
        self.onEditText = onEditText
        self.onShortcut = onShortcut
        self.onStatus = onStatus
        self.onContextMenu = onContextMenu
        self.onFilterMenu = onFilterMenu
        self.onListMenu = onListMenu
        super.init(key: key)
    }

    override func createState() -> State<StatefulWidget> { SheetGridState() }
}

final class SheetGridState: State<StatefulWidget>, TextInputClient {
    let focus = FocusNode(debugLabel: "sheet grid")
    private let _chords = KeyChordTracker()
    /// The platform's text-input plugin, for composed input (Chinese…),
    /// dead keys and press-and-hold accents: attached while the grid has
    /// focus. Its edits open the cell as typing does; with it attached the
    /// typed characters arrive from it and `_key` declines them.
    private var _ime: TextInputConnection? = nil
    /// The input method's marked text in the editor, underlined.
    private var _composing: Range<Int>? = nil
    private let _repaint = ChangeNotifier()
    private var _painter: _GridPainter! = nil
    private weak var _box: RenderBox?
    private(set) var size = Size.zero
    /// Scroll offset of the cell area, in logical pixels.
    var scrollX = 0.0
    var scrollY = 0.0
    private(set) var edit: CellEdit? = nil
    private var _drag: _Drag? = nil
    private var _lastClick: (cell: CellAddress, at: Double)? = nil
    /// The noted cell under the pointer: its note shows beside it.
    private var _hoverNote: CellAddress? = nil
    /// The last press on a header border (column or row, and which), for
    /// double-click autofit.
    private var _lastBorder: (axis: WorkbookController.Axis, index: Int, at: Double)? = nil
    /// The last press on the fill handle (double-click fills down), and
    /// where this one began: the fill follows the pointer only once it has
    /// moved, since the handle's grip reaches past the selection's edge and
    /// a click there used to fill the next cell over.
    private var _lastFillPress: Double? = nil
    private var _fillFrom: Offset? = nil
    let texts = _TextCache()

    private enum _Drag {
        case cells
        case columns(anchor: Int)
        case rows(anchor: Int)
        case resizeColumn(col: Int, startX: Double, startWidth: Double)
        case resizeRow(row: Int, startY: Double, startHeight: Double)
        /// The fill handle: the range it would fill so far.
        case fill(target: CellRange)
        /// Pointing at cells for a formula being typed: where the
        /// reference text starts in the editor, and the anchor cell.
        case point(textStart: Int, anchor: CellAddress)
        /// Moving (handle nil) or resizing a picture or chart: its frame in
        /// points and its anchor when the drag began, and where it began.
        case drawing(index: Int, handle: Int?, frame: (x: Double, y: Double, width: Double, height: Double),
                     anchor: SheetAnchor, start: Offset)
    }
    /// The fill handle's outline while it is dragged.
    private(set) var fillTarget: CellRange? = nil
    /// The cells last copied or cut, framed with dashes until they are
    /// pasted (a cut), Escape is pressed or the sheet is edited, as Excel
    /// frames them: there was no sign of what ⌘V would paste.
    private(set) var marquee: (sheet: Int, range: CellRange)? = nil
    /// The app's own clipboard: exact cells, formulas and formats.
    private static var _clip: WorkbookController.Clip? = nil

    private var _w: SheetGrid { widget as! SheetGrid }
    /// The workbook of a grid that is in no tree: `--sheet-pdf` prints
    /// through the grid's own painter without a window.
    private var _headless: WorkbookController? = nil
    convenience init(headless controller: WorkbookController) {
        self.init()
        _headless = controller
    }
    var controller: WorkbookController { _headless ?? _w.controller }

    /// Logical pixels per point at the current zoom (Excel's 96 dpi).
    var scale: Double { 96.0 / 72.0 * zoom }
    /// Set while a page is printed: one pixel per point (a zoom of 0.75),
    /// and no headers, panes, editor or filter dropdowns.
    var printing = false
    var zoom: Double { printing ? 0.75 : _w.zoom }
    var headerWidth: Double { printing ? 0 : outlineWidth + (40 + Double(max(0, String(_lastVisibleRow + 1).count - 3)) * 8) * zoom }
    /// The outline gutters, left of the row numbers and above the column
    /// letters: a lane per level, and one more for the last level button.
    var outlineWidth: Double { _gutter(_outline().rowLevel) }
    var outlineHeight: Double { _gutter(_outline().colLevel) }
    private func _gutter(_ levels: Int) -> Double { printing || levels == 0 ? 0 : (Double(levels + 1) * 14 + 4) * zoom }

    private struct _Outline { var rowLevel = 0, colLevel = 0; var rowGroups: [OutlineGroup] = [], colGroups: [OutlineGroup] = [] }
    private var _outlineCache: (sheet: ObjectIdentifier, version: Int, outline: _Outline)? = nil
    private func _outline() -> _Outline {
        let ws = controller.sheet
        let id = ObjectIdentifier(ws)
        if let c = _outlineCache, c.sheet == id, c.version == ws.layoutVersion { return c.outline }
        var o = _Outline()
        o.rowGroups = ws.outlineGroups(.rows)
        o.colGroups = ws.outlineGroups(.cols)
        o.rowLevel = o.rowGroups.map(\.level).max() ?? 0
        o.colLevel = o.colGroups.map(\.level).max() ?? 0
        _outlineCache = (id, ws.layoutVersion, o)
        return o
    }

    /// A point given along the axis (y for rows) and across it (into the gutter).
    private func _at(_ axis: WorkbookController.Axis, along: Double, across: Double) -> Offset {
        axis == .rows ? Offset(across, along) : Offset(along, across)
    }
    private func _start(_ axis: WorkbookController.Axis, _ i: Int) -> Double { axis == .rows ? rowY(i) : colX(i) }
    private func _size(_ axis: WorkbookController.Axis, _ i: Int) -> Double { axis == .rows ? rows.size(i) : cols.size(i) }

    /// A group's +/− box, centred in its level's lane at the summary.
    func outlineBox(_ g: OutlineGroup, _ axis: WorkbookController.Axis = .rows) -> Rect? {
        guard (axis == .rows ? outlineWidth : outlineHeight) > 0, _size(axis, g.summary) > 0 else { return nil }
        let c = _at(axis, along: _start(axis, g.summary) + _size(axis, g.summary) / 2, across: (2 + 14 * Double(g.level - 1) + 7) * zoom)
        return Rect.fromLTWH(c.dx - 5 * zoom, c.dy - 5 * zoom, 10 * zoom, 10 * zoom)
    }

    /// Level button `k` (1-based): the rows' in a line beside the column
    /// letters, the columns' in a stack beside the row numbers.
    func outlineLevelButton(_ k: Int, _ axis: WorkbookController.Axis = .rows) -> Rect {
        let across = (2 + 14 * Double(k - 1) + 1) * zoom
        let along = axis == .rows ? outlineHeight + 4 * zoom : (outlineWidth + headerWidth) / 2 - 6 * zoom
        let o = _at(axis, along: along, across: across)
        return Rect.fromLTWH(o.dx, o.dy, 12 * zoom, 12 * zoom)
    }
    var headerHeight: Double { printing ? 0 : outlineHeight + 20 * zoom }
    private var _lastVisibleRow = 0

    var cols: GridAxis { _axes().cols }
    var rows: GridAxis { _axes().rows }
    /// The axes, rebuilt only when the sheet's sizes, hidden rows or the zoom change.
    private var _axisCache: (sheet: ObjectIdentifier, version: Int, scale: Double, printing: Bool, rowScale: Double, colMax: Double, cols: GridAxis, rows: GridAxis)? = nil
    /// The sheet's print scale while it is cut into pages and painted: on
    /// paper each row is a whole number of the printer's dots at that scale
    /// (45544's default rows at 90% are 93 dots, 11.16 pt, where 103 × 0.9
    /// made 11.12 and a row more fitted on its chart's page; 57523's Calibri
    /// 10 rows at 100% are 111 dots, 13.32 pt, not 13.37). 0 — on screen,
    /// or a sheet fitted to its pages, whose scale is not known yet —
    /// leaves the rows as they are.
    var printRowScale = 0.0
    /// The widest a column prints, in points before the page's scale: the
    /// page's width between its margins. Excel's print cuts a wider column
    /// down to it, and wraps its text in what is left (a lab of columns of
    /// 92, 100 and 120 Calibri 11 characters, Excel 16, 2026-10-27: each
    /// 511.2 pt between margins of 0.7 in on Letter, 468 between 1 in, the
    /// same lines in all three; FillWithoutColor's User Guide, 96.3
    /// characters, 543 pt in ours). 0 — on screen, or a sheet fitted to its
    /// pages — leaves them as they are.
    var printColumnMax = 0.0
    /// The sheet prints in black and white (`pageSetup@blackAndWhite`): no
    /// fills, its text and rules black.
    var printMono = false
    /// The page's scale while its cells are painted, 0 otherwise: what
    /// a cell's font is sized for on the printer (`_paintCell`).
    var printTextScale = 0.0

    private func _axes() -> (cols: GridAxis, rows: GridAxis) {
        let ws = controller.sheet
        let id = ObjectIdentifier(ws)
        if let c = _axisCache, c.sheet == id, c.version == ws.layoutVersion, c.scale == scale, c.printing == printing,
           c.rowScale == printRowScale, c.colMax == printColumnMax { return (c.cols, c.rows) }
        let cols: GridAxis, rows: GridAxis
        if printing {
            // On paper the sheet has the printer's sizes, not the screen's: a
            // column is its characters in the printer's digits, a row the
            // printer's line or a set height scaled by it (SheetPrintMetrics).
            let book = controller.book
            let m = SheetPrintMetrics.of(family: book.defaultFontName ?? OfficeFonts.defaultFamily, size: book.defaultFontSize ?? 11, bold: book.defaultFontBold,
                                         baseColWidth: Double(ws.formatPrAttrs["baseColWidth"] ?? "") ?? 8)
            let widths = Dictionary(uniqueKeysWithValues: ws.colWidths.map { ($0.key, $0.value == 0 ? 0 : m.column(Xlsx._widthChars(ws, $0.key, $0.value))) })
            let fitted = ws.customDefaultRowHeight || ws.defaultRowHeightPt <= 0 ? m.rowScale : m.defaultRow / ws.defaultRowHeightPt
            // The rows Excel fits again: every one whose height is only a fit
            // — Excel keeps no such height, fitting the row afresh from its
            // fonts (a lab's 30 pt rows of Arial 10 print at 12.36 with
            // customHeight absent, "0" or "false", and 29.04 with "1";
            // bug66675's 18 pt rows of Arial 7 at Calibri 11's 14.52) — and,
            // where the sheet does not set its default height, those nobody
            // sized.
            let refits: (Int) -> Bool = { r in
                ws.fittedRows.contains(r) || (!ws.customDefaultRowHeight && ws.rowHeights[r] == nil)
            }
            // (A sheet the file gives no view prints its set heights halved:
            // `Worksheet.hasView`.)
            let setScale = ws.hasView ? m.rowScale : m.rowScale / 2
            var heights = Dictionary(uniqueKeysWithValues: ws.rowHeights.compactMap { (r, h) -> (Int, Double)? in
                let fit = ws.fittedRows.contains(r)
                if fit, h > 0 { return (r, ws.scriptRows.contains(r) ? h * fitted : m.defaultRow) }
                return (r, fit ? h * fitted : SheetPrintMetrics.setRow(h, scale: setScale))
            })
            // A row fitted afresh is as tall as its tallest font's line —
            // fitted on the screen, then printed (`fittedRow`) — its empty
            // formatted cells counted, and shorter than the default font's
            // where every font in it is smaller: 57523's unsized rows of
            // Calibri 10 print at 13.32 pt in a Calibri 11 book, whatever
            // the sheet's defaultRowHeight says.
            var lines: [Int: Double] = [:]   // by style
            func line(_ style: Int) -> Double {
                if let known = lines[style] { return known }
                let l = style == 0 ? m.defaultRow : Self._fittedLine(book.style(style), m, book)
                lines[style] = l
                return l
            }
            // The cells it has no record of count too, in the font they
            // would take: the row's style, else their column's — and the
            // default font's where some column has none. 57523's columns
            // are Calibri 10 to the last, so its rows are; bug66675's
            // stop at P, and its rows of Arial 9 print at Calibri 11's
            // 14.52 (made 20 pt, they grow to 25.5).
            var blank = 0.0
            do {
                var covered = 0, next = 0
                for run in ws.colAttrRuns.filter({ $0.attrs["style"] != nil }).sorted(by: { $0.lo < $1.lo }) {
                    blank = max(blank, line(Int(run.attrs["style"] ?? "") ?? 0))
                    let lo = max(run.lo, next)
                    if run.hi >= lo { covered += run.hi - lo + 1; next = run.hi + 1 }
                }
                if covered < CellAddress.maxCols { blank = max(blank, m.defaultRow) }
            }
            // A row the file has no record of: the sheet's default height
            // where it sets one, else fitted as the empty cells in it are,
            // in their columns' fonts — FormulaSheetRange's rows 5-9, under
            // a column of bold Arial 10, print at its 12.72, and
            // NumberFormatTests' gaps under its Lucida Sans Typewriter
            // columns at that face's 13.32.
            let unsized = ws.customDefaultRowHeight ? SheetPrintMetrics.setRow(ws.defaultRowHeightPt, scale: m.rowScale) : blank
            // A merged cell that wraps is no part of its rows' fit:
            // bug66675's dates of Arial 12, merged across A:D, sit in rows
            // of 14.52, and their rows grow to Arial's 15.24 once Wrap Text
            // is off (Tables' merged titles, which do not wrap, are as
            // tall as their fonts).
            var merged: [Int: [CellRange]] = [:]   // by row
            for g in ws.merges where g.top != g.bottom || g.left != g.right {
                for r in g.top...min(g.bottom, g.top + 1000) { merged[r, default: []].append(g) }
            }
            var fit: [Int: Double] = [:]     // by row
            for (a, cell) in ws.cells where refits(a.row) {
                // (Nor is one merged down over rows, wrapping or not:
                // LIBRE_OFFICE-128382-0's date of Calibri 14 in D22:D23
                // leaves both rows at Calibri 11's 14.52 in Excel's print.)
                if let g = merged[a.row]?.first(where: { $0.contains(a) }),
                   g.top != g.bottom || book.style(ws.cells[g.topLeft]?.style ?? cell.style).wrap { continue }
                let l = line(cell.style)
                if l > fit[a.row] ?? 0 { fit[a.row] = l }
            }
            for r in Set(fit.keys).union(ws.fittedRows) {
                let floor = ws.rowStyle(r).map(line) ?? blank
                // A row with a medium or thick border at its foot or head
                // (`thickBot`, `thickTop`) is a screen pixel taller for each:
                // Excel_file_with_trash_item's rows of medium borders, written
                // 15.75 for 15, print at 14.88 for 14.52 — 39 of the 192-dpi
                // screen's pixels for 38.
                let thick = ["thickBot", "thickTop"].filter { ["1", "true"].contains(ws.rowAttrs[r]?[$0] ?? "") }.count
                fit[r] = max(fit[r] ?? 0, floor) + Double(thick) * 72 / 192 * m.rowScale
            }
            for (r, line) in fit {
                // (A row of super- or subscript keeps the file's fit: `Worksheet.scriptRows`.)
                if heights[r] == 0 { continue }
                if ws.scriptRows.contains(r), let h = heights[r], h >= line { continue }
                if abs(line - unsized) > 0.01 || heights[r] != nil { heights[r] = line }
            }
            let dots = printRowScale * 600 / 72
            func whole(_ h: Double) -> Double { printRowScale == 0 || h <= 0 ? h : (h * dots).rounded() / dots }
            func most(_ w: Double) -> Double { printColumnMax > 0 ? min(w, printColumnMax) : w }
            // (A column in whole printer dots too, each its own: 49609's
            // 8.33 characters of Microsoft Sans Serif 8.25 are 316.67 dots,
            // and its rules in Excel's print stand 317.04 apart.)
            cols = GridAxis(def: most(whole(ws.defaultColWidthChars.map { m.column($0) } ?? m.defaultChars * m.digit)),
                            overrides: widths.mapValues { most(whole($0)) }, hidden: ws.hiddenCols, scale: scale)
            do {
                // And as tall as its wrapped text's lines, in the column's width:
                // so many of its font's fitted lines. (Excel fits a wrapped row
                // afresh too: LIBRE_OFFICE-116306-0's row written 105 pt, seven
                // lines of 15, prints six of Calibri's 14.52, 87.12 pt.)
                for (a, cell) in ws.cells where cell.style != 0 && refits(a.row) && cell.value.isText {
                    guard ws.fittedRows.contains(a.row) || ws.customDefaultRowHeight || ws.fittedRows.isEmpty else { continue }
                    let st = book.style(cell.style)
                    guard st.wrap, !ws.merges.contains(where: { $0.contains(a) }), cols.size(a.col) > 0 else { continue }
                    // (In the column as wide as it is on the screen, where
                    // Excel fits it, narrower than on paper: lo-tdf100034's
                    // note of 127 characters in a column of 106 is two lines
                    // there, its row 30 pt, and one line on the page.)
                    let chars = ws.colWidths[a.col].map { Xlsx._widthChars(ws, a.col, $0) } ?? ws.defaultColWidthChars ?? m.defaultChars
                    // Less the cell's padding, as a General number's room is:
                    // two quarter digits and a pixel of the 192-dpi screen
                    // (CVLKRA-KYC's 7-character remarks break "alphan|umeric"
                    // in Excel's print, 36.0 pt wide where ours was 36.4).
                    let pad = (2 * (m.screenDigit / 4).rounded(.up) + 1) * 72 / 192
                    let width = (m.screenColumn(chars) - pad) * scale
                    guard width > 4 else { continue }
                    let text = NumberFormat.display(cell.value, st.numberFormat, width: 255).text
                    // (An empty string is its font's one line, given above:
                    // measured, it made two, and bug66675's spacer rows of
                    // empty wrapping cells printed nearly twice as tall.)
                    guard !text.isEmpty else { continue }
                    let style = _textStyle(st, color: nil, ink: Color(0xFF00_0000))
                    // (Line breaks at the end draw nothing but are lines to the
                    // fit: LIBRE_OFFICE-116306-0's rows keep theirs.)
                    let one = texts.painter("X", style).height
                    let trailing = Double(text.reversed().prefix { $0 == "\n" }.count)
                    let lines = texts.painter(text, style, maxWidth: width).height + trailing * one
                    // (Text that wraps to one line is its font's line, which the
                    // fonts above have given the row: lo-pivottable_invalid_formats'
                    // wrapping one-line rows print at Arial 10's 12.36, where
                    // this measure made them 12.5 and lost a row a page.)
                    guard lines > one * 1.5 else { continue }
                    let tall = (lines / one).rounded() * Self._fittedLine(st, m, book)
                    if tall > heights[a.row] ?? m.defaultRow { heights[a.row] = tall }
                }
            }
            // (A default height the sheet sets is a set height: cut down to
            // whole printer dots as any other. picture.xlsx's 14 pt rows are
            // 118 dots, 14.16, in Excel's print; rounded, 119 put its picture's
            // foot 3.4 pt low.)
            rows = GridAxis(def: whole(unsized),
                            overrides: heights.mapValues(whole), hidden: ws.filteredRows.union(ws.hiddenRows), scale: scale)
        } else {
            cols = GridAxis(def: ws.defaultColWidthPt, overrides: ws.colWidths, hidden: ws.hiddenCols, scale: scale)
            // A row nobody sized is as tall as its wrapped text, as Excel
            // fits it when Wrap Text goes on or the text changes. It was
            // fitted on paper only: on screen a wrapped cell kept its one
            // line's height and showed the last line of its text alone
            // (seen 2026-10-13).
            var heights = ws.rowHeights
            let book = controller.book
            let wrapping = Set(book.styles.indices.filter { book.styles[$0].wrap })
            if !wrapping.isEmpty {
                for (a, cell) in ws.cells where wrapping.contains(cell.style) && ws.rowHeights[a.row] == nil && cell.value.isText {
                    if ws.merges.contains(where: { $0.contains(a) }) { continue }
                    let st = book.style(cell.style)
                    let width = cols.size(a.col) - 4 * zoom
                    guard width > 4 else { continue }
                    let text = NumberFormat.display(cell.value, st.numberFormat, width: 255).text
                    let tall = texts.painter(text, _textStyle(st, color: nil, ink: Color(0xFF00_0000)), maxWidth: width).height / scale + 1.5
                    if tall > ws.defaultRowHeightPt, tall > heights[a.row] ?? 0 { heights[a.row] = tall }
                }
            }
            rows = GridAxis(def: ws.defaultRowHeightPt, overrides: heights, hidden: ws.filteredRows.union(ws.hiddenRows), scale: scale)
        }
        _axisCache = (id, ws.layoutVersion, scale, printing, printRowScale, printColumnMax, cols, rows)
        return (cols, rows)
    }

    override func initState() {
        super.initState()
        _painter = _GridPainter(state: self, repaint: _repaint)
        focus.onKeyData = { [weak self] k in self?._key(k) ?? false }
        focus.onFocusChange = { [weak self] focused in
            guard let self else { return }
            self._chords.reset()
            if focused { self._ime?.attach() } else { self._ime?.detach() }
            self._repaint.notifyListeners()
        }
        if TextInputChannel.enabled { _ime = TextInputConnection(client: self) }
        // The sheet in front now: a change of sheet resets the scroll, and the
        // first notification must not read as one (it reset a scrolled view
        // under the first click).
        _lastSheet = controller.activeSheet
        controller.addListener({ [weak self] in self?._modelChanged() }, owner: self)
        focus.requestFocus()
    }

    override func dispose() {
        _ime?.detach()
        _ime = nil
        controller.removeListeners(owner: self)
        focus.dispose()
        texts.clear()
        for image in _images.values { image.dispose() }
        _images.removeAll()
        super.dispose()
    }

    private var _lastSheet = -1

    private func _modelChanged() {
        if controller.activeSheet != _lastSheet {
            _lastSheet = controller.activeSheet
            scrollX = 0; scrollY = 0
            if edit != nil { cancelEdit() }
        }
        // (Rows fitted to wrapped text follow the text: a cell's value or
        // its style changing is no change of the sheet's sizes.)
        if controller.book.styles.contains(where: { $0.wrap }) { _axisCache = nil }
        _repaint.notifyListeners()
    }

    // MARK: Geometry

    /// Frozen rows and columns: they stay put while the rest scrolls.
    var frozenRows: Int { printing ? 0 : controller.sheet.freezeRows }
    var frozenCols: Int { printing ? 0 : controller.sheet.freezeCols }
    var frozenWidth: Double { cols.start(frozenCols) }
    var frozenHeight: Double { rows.start(frozenRows) }

    /// The column under a local x (right of the row headers).
    func col(atLocal x: Double) -> Int {
        let ca = cols
        let fw = ca.start(frozenCols)
        let dx = max(0, x - headerWidth)
        let c = dx < fw ? ca.index(at: dx) : ca.index(at: fw + scrollX + (dx - fw))
        return min(c, CellAddress.maxCols - 1)
    }

    func row(atLocal y: Double) -> Int {
        let ra = rows
        let fh = ra.start(frozenRows)
        let dy = max(0, y - headerHeight)
        let r = dy < fh ? ra.index(at: dy) : ra.index(at: fh + scrollY + (dy - fh))
        return min(r, CellAddress.maxRows - 1)
    }

    /// A column's left edge in local coordinates (frozen ones never move).
    func colX(_ c: Int) -> Double {
        let ca = cols
        return headerWidth + ca.start(c) - (c >= frozenCols ? scrollX : 0)
    }

    func rowY(_ r: Int) -> Double {
        let ra = rows
        return headerHeight + ra.start(r) - (r >= frozenRows ? scrollY : 0)
    }

    /// A position inside this view (local) as a cell.
    func cell(atLocal p: Offset) -> CellAddress {
        CellAddress(row: row(atLocal: p.dy), col: col(atLocal: p.dx))
    }

    /// A cell's rectangle in local coordinates.
    func rect(_ a: CellAddress) -> Rect {
        Rect.fromLTWH(colX(a.col), rowY(a.row), cols.size(a.col), rows.size(a.row))
    }

    func rect(_ r: CellRange) -> Rect {
        let a = rect(r.topLeft), b = rect(r.bottomRight)
        return Rect.fromLTRB(a.left, a.top, b.right, b.bottom)
    }

    /// The picture or chart under a local point, topmost first, and which
    /// of the selected one's handles (0 top-left, clockwise to 7 left) it is on.
    private func _drawingHit(_ p: Offset) -> (index: Int, handle: Int?)? {
        guard p.dx >= headerWidth, p.dy >= headerHeight else { return nil }
        let ws = controller.sheet
        if let sel = controller.selectedDrawing, ws.drawings.indices.contains(sel) {
            for (h, q) in _handles(drawingRect(ws.drawings[sel].anchor)).enumerated() where (q - p).distance <= 6 {
                return (sel, h)
            }
        }
        for i in ws.drawings.indices.reversed() where ws.drawings[i].kind != .other {
            if drawingRect(ws.drawings[i].anchor).contains(p) { return (i, nil) }
        }
        return nil
    }

    private func _handles(_ r: Rect) -> [Offset] {
        let cx = r.center.dx, cy = r.center.dy
        return [Offset(r.left, r.top), Offset(cx, r.top), Offset(r.right, r.top), Offset(r.right, cy),
                Offset(r.right, r.bottom), Offset(cx, r.bottom), Offset(r.left, r.bottom), Offset(r.left, cy)]
    }

    /// The selected drawing's frame and handles.
    private func _paintDrawingSelection(_ canvas: any Canvas, accent: Color) {
        let ws = controller.sheet
        guard !printing, let i = controller.selectedDrawing, ws.drawings.indices.contains(i) else { return }
        let r = drawingRect(ws.drawings[i].anchor)
        let p = Paint()
        p.style = .stroke
        p.strokeWidth = 1
        p.color = accent
        canvas.drawRect(r, p)
        for q in _handles(r) {
            p.style = .fill
            p.color = Color(0xFFFFFFFF)
            canvas.drawCircle(q, 4, p)
            p.style = .stroke
            p.color = accent
            canvas.drawCircle(q, 4, p)
        }
    }

    /// Where a drawing's anchor puts it on screen.
    func drawingRect(_ anchor: SheetAnchor) -> Rect {
        // An offset is its points into its cell — never past it (Excel holds
        // a corner inside the cell it names). On paper it is scaled as the
        // screen is: across, by the printer's digit over the 192 dpi
        // screen's (a column's own scale, its padding aside), and down by
        // the row scale — not by its cell's share, a column's padding
        // being the same few pixels at any width. Calibri 11's 47 dots
        // over 15 px is 1.003: chart-treemap's frame 12.75 pt into a 51.13
        // pt column F and 36.75 into M, 318.9 to 700.74 in Excel's print,
        // where a share put ours at 319.66 to 703.18. Calibri 10's 42 over
        // 14 is 0.96: 53568's 3 to 31.8 pt into B, 27.65 pt wide.
        let ws = controller.sheet, ca = cols, ra = rows
        var across = 1.0, down = 1.0
        if printing {
            let book = controller.book
            let m = SheetPrintMetrics.of(family: book.defaultFontName ?? OfficeFonts.defaultFamily, size: book.defaultFontSize ?? 11, bold: book.defaultFontBold)
            across = m.digit / (m.screenDigit * 72 / 192)
            down = m.rowScale
        }
        func at(_ m: SheetMarker) -> Offset {
            let w = ws.colWidth(m.col), h = ws.rowHeight(m.row)
            return Offset(colX(m.col) + (w > 0 ? min(m.colOff * across * scale, ca.size(m.col)) : 0),
                          rowY(m.row) + (h > 0 ? min(m.rowOff * down * scale, ra.size(m.row)) : 0))
        }
        switch anchor {
        case .twoCell(let from, let to):
            let a = at(from), b = at(to)
            return Rect.fromLTRB(a.dx, a.dy, max(a.dx, b.dx), max(a.dy, b.dy))
        case .oneCell(let from, let w, let h):
            // (Its size as it says, not scaled as an offset is: scaled,
            // chart-tdf119138's and -tdf100084's charts printed larger
            // than Excel's, lo-tdf139763ShapeAnchor's shapes no longer
            // exact.)
            let a = at(from)
            return Rect.fromLTWH(a.dx, a.dy, w * scale, h * scale)
        case .absolute(let x, let y, let w, let h):
            return Rect.fromLTWH(headerWidth + x * scale - scrollX, headerHeight + y * scale - scrollY, w * scale, h * scale)
        }
    }

    func _paintDrawing(_ canvas: any Canvas, _ d: SheetDrawing, chart: Chart?, in r: Rect, theme: DeckTheme) {
        guard r.width > 1, r.height > 1 else { return }
        switch d.kind {
        case .other: return
        case .shape(let shape):
            shape.paint(canvas, in: shape.unturned(r), pxPerPt: scale, font: OfficeFonts.drawn(theme.bodyFont))
        case .picture(let path, let data):
            // A turned picture: its anchor holds the turned box, its sides
            // swapped between 45° and 135° (lo-twoCellAnchor_editAs_oneCell's
            // at 240°, a 330 by 352 pt box in Excel's print, where ours drew
            // it upright in 218 by 284).
            guard d.rotation != 0 else { _paintPicture(canvas, path, data, in: r, crop: d.crop); return }
            let turn = (d.rotation.truncatingRemainder(dividingBy: 180) + 180).truncatingRemainder(dividingBy: 180)
            let box = turn >= 45 && turn < 135 ? Rect.fromCenter(center: r.center, width: r.height, height: r.width) : r
            canvas.save()
            canvas.translate(r.center.dx, r.center.dy)
            canvas.rotate(d.rotation * .pi / 180)
            canvas.translate(-r.center.dx, -r.center.dy)
            _paintPicture(canvas, path, data, in: box, crop: d.crop)
            canvas.restore()
        case .chart:
            guard let chart else { return }
            // Excel's chart area: its own fill and outline where the chart
            // gives them (chart-tdf161607's grey "Background 2, darker 50%"
            // with a black edge), else the theme's background with a light
            // grey edge.
            let p = Paint()
            p.style = .fill
            if !chart.areaNoFill {
                p.color = chart.areaFill ?? theme.background
                if let g = chart.areaGradient, let shader = SlidePainter.gradientShader(g, r) { p.shader = shader }
                canvas.drawRect(r, p)
                p.shader = nil
            }
            if !chart.areaNoLine {
                p.style = .stroke
                let w = chart.areaLineWidth.map { $0 * scale } ?? 1
                p.strokeWidth = w
                p.color = chart.areaLine ?? Color(0xFFD9D9D9)
                canvas.drawRect(r.deflate(w / 2), p)
            }
            // Excel's chart text is three quarters of PowerPoint's (14pt
            // titles, 9pt labels against 18.6 and 12), the painter's sizes.
            // (A size the chart states is printed as stated: `statedTextScaled`.)
            // A 2007-style chart that says nothing of its text prints it at
            // 10 pt and its title at 18, as PowerPoint does, not three
            // quarters of that (47813, chart-rAngAx, WithChart: 10 pt in
            // Excel's print, ours 7.5).
            var stated = chart.statedTextScaled(by: 4.0 / 3)
            stated.onSheet = true
            if stated.textSize == nil, stated.plainText, !stated.styled2013 {
                stated.textSize = 10 * 4.0 / 3
                if stated.titleSize == nil { stated.titleSize = 18 * 4.0 / 3 }
            }
            // Nothing of it outside its area, as Excel draws none: 45540's
            // pie labels set below the frame printed over the cells there.
            if !chart.series.isEmpty {
                canvas.save()
                canvas.clipRect(r)
                ChartPainter.paint(stated, canvas, r, pxPerPt: scale * 0.75, theme: theme)
                canvas.restore()
            }
        }
    }

    /// A picture's bytes into `r`: a bitmap through the codec, a metafile
    /// (WMF, EMF — what an embedded object's picture usually is) played.
    private func _paintPicture(_ canvas: any Canvas, _ path: String, _ data: Data, in r: Rect, crop: [Double]? = nil) {
        if let played = _metafile(path, data) {
            played.paint(canvas, in: r, image: { self._image($0.id, $0.data) }, font: { OfficeFonts.drawn($0) })
        } else if !Metafile.isMetafile(data), let image = _image(path, data) {
            let w = Double(image.width), h = Double(image.height)
            let src = crop.map { Rect.fromLTRB($0[0] * w, $0[1] * h, w - $0[2] * w, h - $0[3] * h) } ?? Rect.fromLTWH(0, 0, w, h)
            canvas.drawImageRect(image, src, r, Paint())
        }
    }

    /// Embedded objects and controls: each one's picture, or the form
    /// control drawn.
    func _paintObjects(_ canvas: any Canvas, _ ws: Worksheet, clip: Rect) {
        for o in ws.objects where !(printing && o.screenOnly) {
            let r = drawingRect(o.anchor)
            guard r.width > 1, r.height > 1, r.overlaps(clip) else { continue }
            switch o.kind {
            case .preview(let path, let data):
                _paintPicture(canvas, path, data, in: r)
                if o.framed {
                    let rule = Paint()
                    rule.style = .stroke
                    rule.strokeWidth = 0.75 * scale
                    rule.color = Color(0xFF000000)
                    canvas.drawRect(r, rule)
                }
            case .control(let control): control.paint(canvas, in: r, pt: scale)
            }
        }
    }

    /// Metafiles, parsed once each; nil for one that draws nothing read here.
    private var _metafiles: [String: Metafile?] = [:]
    func _metafile(_ key: String, _ data: Data) -> Metafile? {
        guard Metafile.isMetafile(data) else { return nil }
        _ = _imagesOfThisBook()
        if let known = _metafiles[key] { return known }
        let played = Metafile(data, id: key)
        _metafiles[key] = .some(played)
        return played
    }

    private var _images: [String: Image] = [:]
    private var _decoding: Set<String> = []
    /// The workbook the cache is of: its keys are part names, and every
    /// workbook has an `xl/media/image1.png`.
    private var _imagesBook: ObjectIdentifier? = nil

    /// The open workbook, with the cache emptied of any other's pictures.
    private func _imagesOfThisBook() -> ObjectIdentifier {
        let book = ObjectIdentifier(controller.book)
        if _imagesBook != book {
            for image in _images.values { image.dispose() }
            _images.removeAll(); _decoding.removeAll(); _metafiles.removeAll()
            _imagesBook = book
        }
        return book
    }

    /// A picture, decoded once; nil (and a repaint later) while it decodes.
    func _image(_ key: String, _ data: Data) -> Image? {
        let book = _imagesOfThisBook()
        if let image = _images[key] { return image }
        guard !_decoding.contains(key) else { return nil }
        _decoding.insert(key)
        let bytes = [UInt8](data)
        Task { @MainActor [weak self] in
            var decoded: Image? = nil
            if let codec = try? await instantiateImageCodec(bytes) {
                decoded = (try? await codec.getNextFrame())?.image
                codec.dispose()
            }
            guard let self, self.mounted || self._headless != nil, self._imagesBook == book else { decoded?.dispose(); return }
            self._decoding.remove(key)
            if let decoded {
                if self._images[key] == nil { self._images[key] = decoded } else { decoded.dispose() }
                self._repaint.notifyListeners()
            }
        }
        return nil
    }

    /// The picture decoded and waited for (an export's way in).
    @MainActor
    func _decodeNow(_ key: String, _ data: Data) async {
        // (The cache is this workbook's from here on: left unclaimed, the
        // first page painted would empty it of what was decoded for it.)
        _ = _imagesOfThisBook()
        guard _images[key] == nil else { return }
        var decoded: Image? = nil
        if let codec = try? await instantiateImageCodec([UInt8](data)) {
            decoded = (try? await codec.getNextFrame())?.image
            codec.dispose()
        }
        guard let decoded else { return }
        if _images[key] == nil { _images[key] = decoded } else { decoded.dispose() }
    }

    /// A cell's top-right corner in global coordinates (where a note opens).
    func globalTopRight(of a: CellAddress) -> Offset {
        let r = rect(a)
        let local = Offset(r.right + 8, r.top)
        return _box?.localToGlobal(local) ?? local
    }

    /// A validation list's arrow: a button just right of the active cell.
    func listButton() -> Rect? {
        let c = controller
        guard !printing, edit == nil, c.selectedDrawing == nil, let rule = c.validation(at: c.active),
              rule.type == "list", rule.arrow else { return nil }
        let r = rect(c.active)
        return Rect.fromLTWH(r.right + 1, r.top, min(16 * zoom, max(10, r.height)), r.height)
    }

    /// A filter dropdown: a square in the header cell's bottom-right corner.
    func filterButton(_ a: CellAddress) -> Rect {
        let r = rect(a)
        let side = max(0, min(r.height - 2, 16 * zoom, r.width - 2))
        return Rect.fromLTWH(r.right - side - 1, r.bottom - side - 1, side, side)
    }

    /// Scroll so the cell is fully in view (frozen cells always are).
    func reveal(_ a: CellAddress) {
        let ca = cols, ra = rows
        let fw = ca.start(frozenCols), fh = ra.start(frozenRows)
        let viewW = size.width - headerWidth - fw, viewH = size.height - headerHeight - fh
        guard viewW > 0, viewH > 0 else { return }
        if a.col >= frozenCols {
            let x0 = ca.start(a.col) - fw, x1 = x0 + ca.size(a.col)
            if x0 < scrollX { scrollX = x0 } else if x1 > scrollX + viewW { scrollX = min(x0, x1 - viewW) }
        }
        if a.row >= frozenRows {
            let y0 = ra.start(a.row) - fh, y1 = y0 + ra.size(a.row)
            if y0 < scrollY { scrollY = y0 } else if y1 > scrollY + viewH { scrollY = min(y0, y1 - viewH) }
        }
        _repaint.notifyListeners()
    }

    private func _scroll(by dx: Double, _ dy: Double) {
        let ca = cols, ra = rows
        scrollX = max(0, scrollX + dx)
        scrollY = max(0, scrollY + dy)
        let maxX = ca.start(CellAddress.maxCols) - ca.start(frozenCols) - (size.width - headerWidth - ca.start(frozenCols))
        let maxY = ra.start(CellAddress.maxRows) - ra.start(frozenRows) - (size.height - headerHeight - ra.start(frozenRows))
        scrollX = min(scrollX, max(0, maxX))
        scrollY = min(scrollY, max(0, maxY))
        _repaint.notifyListeners()
    }

    // MARK: Editing

    /// Start editing the active cell: with `replace`, typing replaces it
    /// (Enter mode); otherwise the caret goes at the end of what is there.
    func beginEdit(replace: String? = nil) {
        marquee = nil
        let a = controller.active
        // A locked cell on a protected sheet does not open for editing.
        if controller.protection() != nil && controller.isLocked(a) {
            _w.onStatus(WorkbookController.protectedMessage)
            return
        }
        let text = replace ?? controller.input(a)
        edit = CellEdit(cell: a, text: Array(text), caret: text.count, enterMode: replace != nil)
        reveal(a)
        _w.onEditText(text)
        _repaint.notifyListeners()
        _ime?.sync()
    }

    /// Put the editor's text into the cell. Returns false if nothing was being edited.
    @discardableResult
    func commitEdit() -> Bool {
        guard let e = edit else { return false }
        edit = nil
        _composing = nil
        _pointRef = nil
        _ime?.sync()
        var text = String(e.text)
        // Excel closes the parentheses a formula left open.
        if text.hasPrefix("=") {
            let open = text.filter { $0 == "(" }.count - text.filter { $0 == ")" }.count
            if open > 0 { text += String(repeating: ")", count: open) }
        }
        // Data validation: an entry its rule refuses is not made (Excel's
        // Stop alert, answered Cancel); a Warning or Information alert lets
        // it in and says so; formulas are not checked.
        var verdict: String? = nil
        if text != controller.input(e.cell), !text.hasPrefix("=") {
            let value = text.isEmpty ? CellValue.empty : (InputParser.parse(text)?.value ?? .text(text))
            if let v = controller.validationVerdict(value, at: e.cell) {
                if v.refused {
                    _w.onStatus(v.message)
                    _w.onEditText(nil)
                    _repaint.notifyListeners()
                    return true
                }
                verdict = v.message
            }
        }
        if text != controller.input(e.cell) {
            controller.setInput(text, at: e.cell)
            _widenForNumber(e.cell)
            controller.growTable(toInclude: e.cell)
        }
        if let verdict { _w.onStatus(verdict) }
        if let v = controller.sheet.cells[e.cell]?.value, case .text(let s) = v, s.hasPrefix("="), text.hasPrefix("=") {
            _w.onStatus("There's a problem with this formula")
        }
        _w.onEditText(nil)
        _repaint.notifyListeners()
        return true
    }

    /// A date or formatted number typed into a column still at its default
    /// width widens the column to show it, as Excel does, rather than
    /// ######## (=TODAY() in a fresh sheet). General numbers shorten
    /// instead, and a column given a width keeps it.
    private func _widenForNumber(_ a: CellAddress) {
        let c = controller, ws = c.sheet
        guard ws.colWidths[a.col] == nil || ws.widenedCols.contains(a.col), let cell = ws.cells[a], case .number = cell.value else { return }
        let st = c.book.style(cell.style)
        guard st.numberFormat != "General", !c.sheet.merges.contains(where: { $0.contains(a) && $0.cols > 1 }) else { return }
        let text = NumberFormat.display(cell.value, st.numberFormat, width: 255).text
        let w = (texts.painter(text, _textStyle(st, color: nil, ink: Color(0xFF00_0000))).width + 4 * zoom) / scale + 1.5
        guard w > ws.colWidth(a.col) else { return }
        ws.colWidths[a.col] = (w * 4).rounded(.up) / 4
        ws.widenedCols.insert(a.col)
    }

    /// A frame of dashes two pixels wide on a light underlay, drawn only
    /// where it is in view (a whole column's frame is a million rows long).
    private func _dashedFrame(_ canvas: any Canvas, _ r: Rect, view: Rect, ink: Color, under: Color) {
        let p = Paint()
        p.style = .fill
        func line(_ fixed: Double, _ from: Double, _ to: Double, horizontal: Bool) {
            let lo = horizontal ? view.left : view.top, hi = horizontal ? view.right : view.bottom
            let flo = horizontal ? view.top : view.left, fhi = horizontal ? view.bottom : view.right
            guard fixed >= flo - 1, fixed <= fhi + 1 else { return }
            let a = max(from, lo), b = min(to, hi)
            guard b > a else { return }
            func bar(_ s: Double, _ e: Double) {
                canvas.drawRect(horizontal ? Rect.fromLTRB(s, fixed - 1, e, fixed + 1) : Rect.fromLTRB(fixed - 1, s, fixed + 1, e), p)
            }
            p.color = under
            bar(a, b)
            p.color = ink
            var x = from + ((a - from) / 8).rounded(.down) * 8
            while x < b { bar(max(x, a), min(x + 4, b)); x += 8 }
        }
        line(r.top, r.left, r.right, horizontal: true)
        line(r.bottom, r.left, r.right, horizontal: true)
        line(r.left, r.top, r.bottom, horizontal: false)
        line(r.right, r.top, r.bottom, horizontal: false)
    }

    func cancelEdit() {
        guard edit != nil else { return }
        edit = nil
        _composing = nil
        _pointRef = nil
        _ime?.sync()
        _w.onEditText(nil)
        _repaint.notifyListeners()
    }

    /// The formula bar changed the text while the cell is being edited.
    func setEditText(_ s: String) {
        if edit == nil { edit = CellEdit(cell: controller.active, text: [], caret: 0, enterMode: false) }
        edit!.text = Array(s)
        edit!.caret = edit!.text.count
        _repaint.notifyListeners()
        _ime?.sync()
    }

    // MARK: Text input (IME)

    /// The editor as the plugin sees it: nothing while no cell is open.
    var textInputValue: TextEditingValue {
        get {
            guard let e = edit else { return TextEditingValue(text: "", selection: TextSelection(offset: 0)) }
            let c = _composing.map { TextRange(start: $0.lowerBound, end: $0.upperBound) } ?? TextRange.empty
            return TextEditingValue(text: String(e.text), selection: TextSelection(offset: e.caret), composing: c)
        }
        set {
            if edit == nil {
                // The first character typed opens the cell, replacing it,
                // as it does from the key path.
                if newValue.text.isEmpty { return }
                beginEdit(replace: "")
                guard edit != nil else { _ime?.sync(force: true); return }
            }
            var e = edit!
            e.text = Array(newValue.text)
            let sel = newValue.selection
            e.caret = sel.isValid ? min(max(0, sel.extentOffset), e.text.count) : e.text.count
            edit = e
            let c = newValue.composing
            _composing = c.isValid && !c.isCollapsed ? max(0, c.start) ..< min(c.end, e.text.count) : nil
            _pointRef = nil
            _w.onEditText(String(e.text))
            _repaint.notifyListeners()
        }
    }

    private func _insert(_ s: String) {
        guard var e = edit else { return }
        let chars = Array(s)
        e.text.insert(contentsOf: chars, at: e.caret)
        e.caret += chars.count
        edit = e
        _w.onEditText(String(e.text))
        _repaint.notifyListeners()
    }

    // MARK: Keys

    /// F4: the reference at the caret cycles A1 → $A$1 → A$1 → $A1 → A1.
    private func _cycleAbsolute() {
        guard var e = edit, e.text.first == "=" else { return }
        let chars = e.text
        // The reference ending at (or containing) the caret.
        var end = e.caret
        while end < chars.count, chars[end].isLetter || chars[end].isNumber || chars[end] == "$" { end += 1 }
        var start = min(e.caret, chars.count)
        while start > 0, chars[start - 1].isLetter || chars[start - 1].isNumber || chars[start - 1] == "$" { start -= 1 }
        let token = String(chars[start ..< end])
        guard let p = CellRefText.parse(Substring(token)), p.rest.isEmpty, let row = p.row, let col = p.col else { return }
        let (colAbs, rowAbs): (Bool, Bool)
        switch (p.colAbs, p.rowAbs) {
        case (false, false): (colAbs, rowAbs) = (true, true)
        case (true, true): (colAbs, rowAbs) = (false, true)
        case (false, true): (colAbs, rowAbs) = (true, false)
        default: (colAbs, rowAbs) = (false, false)
        }
        let next = RefEnd(row: row, col: col, rowAbs: rowAbs, colAbs: colAbs).text
        e.text.replaceSubrange(start ..< end, with: Array(next))
        e.caret = start + next.count
        edit = e
        _w.onEditText(String(e.text))
        _repaint.notifyListeners()
    }

    private func _key(_ k: KeyData) -> Bool {
        if _chords.track(k) { return false }
        guard k.type != .up else { return false }
        // While an input method composes, every key is its: Enter commits
        // the candidate, Escape cancels, arrows move inside the marked
        // text, Backspace shortens it.
        if _ime?.isComposing == true { return false }
        let handled = _keyUnchorded(k)
        // What the key did to the editor, the plugin hears (a key the
        // plugin had — typed text — it reported itself).
        if handled { _ime?.sync() }
        return handled
    }

    private func _keyUnchorded(_ k: KeyData) -> Bool {
        // A double click is two clicks with nothing between them.
        _lastClick = nil
        let named = KeyChordTracker.named(k.logical)
        let c = controller

        // ⌃; today's date, ⌃⇧; the time, typed into the cell as Excel puts
        // them (the editor opens with it, as if typed).
        if _chords.control || _chords.primary, k.logical == 0x3B || k.logical == 0x3A {
            let now = ExcelDate.now()
            let text = _chords.shift || k.logical == 0x3A
                ? NumberFormat.format(now - now.rounded(.down), "h:mm AM/PM").text
                : NumberFormat.format(now.rounded(.down), "m/d/yyyy").text
            if edit != nil { _pointRef = nil; _insert(text) } else { beginEdit(replace: text) }
            return true
        }
        // ⇧Space the selection's whole rows, ⌃Space its whole columns, both
        // the sheet — not a space typed into the cell.
        if edit == nil, k.logical == 0x20, _chords.shift || _chords.control || _chords.primary {
            let sel = c.selection
            let rows = _chords.shift, cols = _chords.control || _chords.primary
            c.select(range: CellRange(top: cols ? 0 : sel.top, left: rows ? 0 : sel.left,
                                      bottom: cols ? CellAddress.maxRows - 1 : sel.bottom,
                                      right: rows ? CellAddress.maxCols - 1 : sel.right),
                     active: c.active)
            return true
        }

        // Chords first.
        if _chords.primary, let letter = KeyChordTracker.letter(k.logical) {
            switch letter {
            case "z" where edit == nil: _chords.shift ? c.redo() : c.undo(); return true
            case "y" where edit == nil: c.redo(); return true
            case "a" where edit == nil:
                c.select(range: CellRange(top: 0, left: 0, bottom: CellAddress.maxRows - 1, right: CellAddress.maxCols - 1),
                         active: c.active)
                return true
            case "b" where edit == nil: c.toggleStyle(\.bold); return true
            case "i" where edit == nil: c.toggleStyle(\.italic); return true
            case "u" where edit == nil: c.toggleStyle(\.underline); return true
            case "c" where edit == nil: copySelection(cut: false); return true
            case "x" where edit == nil: copySelection(cut: true); return true
            case "d" where edit == nil: c.fillDown(); return true
            case "r" where edit == nil: c.fillRight(); return true
            case "v":
                paste()
                return true
            default:
                if _w.onShortcut(letter, _chords) { return true }
                return false
            }
        }

        if var e = edit {
            switch named {
            case .enter where _chords.alt:
                // Alt+Enter: a line break inside the cell, as Excel's (which
                // turns its Wrap Text on; setInputs does).
                _pointRef = nil; _insert("\n"); return true
            case .enter where _chords.control || (_chords.primary && !_chords.shift):
                // ⌃↩ / ⌘↩: what was typed goes into every selected cell.
                let text = String(e.text)
                cancelEdit()
                c.fillSelection(with: text)
                return true
            case .function(4):
                _cycleAbsolute()
                return true
            case .enter:
                commitEdit()
                c.advance(rows: _chords.shift ? -1 : 1, cols: 0)
                reveal(c.active)
                return true
            case .tab:
                commitEdit()
                c.advance(rows: 0, cols: _chords.shift ? -1 : 1)
                reveal(c.active)
                return true
            case .escape:
                cancelEdit(); return true
            case .backspace:
                if e.caret > 0 { e.text.remove(at: e.caret - 1); e.caret -= 1 }
                edit = e; _w.onEditText(String(e.text)); _repaint.notifyListeners(); return true
            case .delete:
                if e.caret < e.text.count { e.text.remove(at: e.caret) }
                edit = e; _w.onEditText(String(e.text)); _repaint.notifyListeners(); return true
            case .left, .right, .up, .down:
                if e.enterMode && (pointing || _pointRef != nil) {
                    _pointWithArrow(named)
                    return true
                }
                if e.enterMode {
                    commitEdit()
                    _move(named)
                    return true
                }
                if named == .left { e.caret = max(0, e.caret - 1) }
                if named == .right { e.caret = min(e.text.count, e.caret + 1) }
                edit = e; _repaint.notifyListeners(); return true
            case .home: e.caret = 0; edit = e; _repaint.notifyListeners(); return true
            case .end: e.caret = e.text.count; edit = e; _repaint.notifyListeners(); return true
            case .function(2): e.enterMode.toggle(); edit = e; return true
            default:
                if let t = _chords.typedText(k) {
                    // With the text-input plugin connected the characters
                    // arrive from it (composed, accented, or plain);
                    // declining the key is what lets the plugin have it.
                    if _ime?.isAttached == true { return false }
                    _pointRef = nil; _insert(t); return true
                }
                return false
            }
        }

        // A picture or chart selected: Delete removes it, Escape goes back to
        // the cells, and typing does nothing (as Excel).
        if let d = c.selectedDrawing {
            switch named {
            case .delete, .backspace: c.deleteDrawing(d); return true
            case .escape: c.select(c.active); return true
            case .left, .right, .up, .down: c.select(c.active)
            default: if _chords.typedText(k) != nil { return true }
            }
        }
        switch named {
        case .left, .right, .up, .down: _move(named); return true
        case .enter:
            c.advance(rows: _chords.shift ? -1 : 1, cols: 0)
            var guardSteps = 10_000
            while rows.size(c.active.row) == 0, c.active.row > 0, guardSteps > 0 {
                c.advance(rows: _chords.shift ? -1 : 1, cols: 0); guardSteps -= 1
            }
            reveal(c.active); return true
        case .tab: c.advance(rows: 0, cols: _chords.shift ? -1 : 1); reveal(c.active); return true
        case .home:
            c.select(CellAddress(row: _chords.primary || _chords.control ? 0 : c.active.row, col: 0), extend: _chords.shift)
            reveal(c.active); return true
        case .end where _chords.primary || _chords.control:
            // ⌃End: the last cell in use — the bottom row and right column
            // that hold anything, as Excel's.
            let last = c.sheet.usedExtent
            c.select(last, extend: _chords.shift)
            reveal(last); return true
        case .pageDown where _chords.control || _chords.primary, .pageUp where _chords.control || _chords.primary:
            // ⌃PgDn / ⌃PgUp: the next or previous sheet shown, as Excel's.
            let sheets = c.book.sheets
            let step = named == .pageDown ? 1 : -1
            var j = c.activeSheet + step
            while sheets.indices.contains(j), sheets[j].hidden { j += step }
            if sheets.indices.contains(j) { c.activeSheet = j }
            return true
        case .pageDown, .pageUp:
            let rowsPerPage = max(1, Int((size.height - headerHeight) / max(1, rows.def)) - 1)
            let d = named == .pageDown ? rowsPerPage : -rowsPerPage
            c.select(CellAddress(row: c.active.row + d, col: c.active.col), extend: _chords.shift)
            scrollY = max(0, scrollY + Double(d) * rows.def)
            reveal(c.active); return true
        case .function(2): beginEdit(); return true
        case .delete: marquee = nil; c.clearContents(); return true
        case .backspace: beginEdit(replace: ""); return true
        case .escape:
            // Escape lets go of the copied cells first, as Excel's does.
            if marquee != nil { marquee = nil; _repaint.notifyListeners(); return true }
            return _w.onShortcut("\u{1B}", _chords)  // the shell closes its find bar
        default:
            if let t = _chords.typedText(k) {
                if _ime?.isAttached == true { return false }
                beginEdit(replace: t); return true
            }
            return false
        }
    }

    /// An arrow in Point mode: a reference to the cell next to the one
    /// pointed at (or to the edited cell), replacing the last one inserted.
    private var _pointRef: (start: Int, cell: CellAddress)? = nil

    private func _pointWithArrow(_ named: NamedKey) {
        guard var e = edit else { return }
        let (dr, dc): (Int, Int) = named == .up ? (-1, 0) : named == .down ? (1, 0) : named == .left ? (0, -1) : (0, 1)
        let from = _pointRef?.cell ?? e.cell
        let to = CellAddress(row: max(0, from.row + dr), col: max(0, from.col + dc))
        let start = _pointRef?.start ?? e.caret
        e.text.replaceSubrange(start ..< e.caret, with: Array(to.a1))
        e.caret = start + to.a1.count
        edit = e
        _pointRef = (start, to)
        _w.onEditText(String(e.text))
        reveal(to)
    }

    private func _move(_ named: NamedKey) {
        let c = controller
        let (dr, dc): (Int, Int) = named == .up ? (-1, 0) : named == .down ? (1, 0) : named == .left ? (0, -1) : (0, 1)
        let from = _chords.shift ? c._extentEnd : c.active
        var to = CellAddress(row: from.row + dr, col: from.col + dc)
        if _chords.primary || _chords.control { to = c.edge(from: from, rows: dr, cols: dc) }
        // Hidden rows and columns are stepped over.
        let ra = rows, ca = cols
        while dr != 0, to.row > 0, to.row < CellAddress.maxRows - 1, ra.size(to.row) == 0 { to.row += dr }
        while dc != 0, to.col > 0, to.col < CellAddress.maxCols - 1, ca.size(to.col) == 0 { to.col += dc }
        c.select(to, extend: _chords.shift)
        reveal(to)
    }

    // MARK: Clipboard

    /// The selection as tab-separated values, as every spreadsheet reads it.
    func copySelection(cut: Bool = false) {
        let c = controller
        let r = c.selection
        let used = c.sheet.usedExtent
        let bottom = min(r.bottom, max(r.top, used.row)), right = min(r.right, max(r.left, used.col))
        var lines: [String] = []
        for row in r.top ... bottom {
            var fields: [String] = []
            for col in r.left ... right {
                let a = CellAddress(row: row, col: col)
                let v = c.sheet.value(a)
                let shown = NumberFormat.display(v, c.style(at: a).numberFormat, width: 255).text
                fields.append(shown.containsSubstring("\t") || shown.containsSubstring("\n")
                              ? "\"" + shown.replacingAll("\"", with: "\"\"") + "\"" : shown)
            }
            lines.append(fields.joined(separator: "\t"))
        }
        let text = lines.joined(separator: "\n") + "\n"
        // Other apps get the table as HTML too: Writer, Mail and Word paste
        // it as a table with its formatting.
        let html = HtmlTable.render(c, r, rows: r.top ... bottom, cols: r.left ... right)
        Clipboard.setData(ClipboardData(text: text, html: html))
        // Inside the app a paste is exact; a cut moves on paste, as Excel's does.
        Self._clip = c.clip(cut: cut, text: text)
        marquee = (c.activeSheet, r)
        _w.onStatus((cut ? "Cut " : "Copied ") + (r.rows > 1 || r.cols > 1 ? r.a1 : r.topLeft.a1) + (cut ? " — paste to move it" : ""))
        _repaint.notifyListeners()
    }

    func paste() {
        Clipboard.getData(Clipboard.kAll) { [weak self] data in
            let html = data?.html
            guard let text = data?.text ?? (html == nil ? nil : ""), !(text.isEmpty && html == nil) else { return }
            DispatchQueue.main.async {
                guard let self, self.mounted else { return }
                if self.edit != nil {
                    self._insert(text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).first.map(String.init) ?? "")
                    return
                }
                let c = self.controller
                // Our own copy (the system clipboard still holds what we put
                // there): paste the cells themselves.
                if let clip = Self._clip, clip.text == text {
                    c.paste(clip)
                    if clip.cut { Self._clip = nil; self.marquee = nil }
                    self.reveal(c.active)
                    return
                }
                // Another app's table, with its formatting.
                if let html, let table = HtmlTable.parse(html) {
                    c.pasteTable(table)
                    return
                }
                let rows = Csv.parse(text, separator: "\t")
                let origin = c.selection.topLeft
                var items: [(CellAddress, String)] = []
                for (i, row) in rows.enumerated() {
                    for (j, field) in row.enumerated() {
                        items.append((CellAddress(row: origin.row + i, col: origin.col + j), field))
                    }
                }
                guard !items.isEmpty else { return }
                c.setInputs(items)
                let h = rows.count, w = rows.map(\.count).max() ?? 1
                c.select(range: CellRange(top: origin.row, left: origin.col, bottom: origin.row + h - 1, right: origin.col + w - 1),
                         active: origin)
            }
        }
    }

    // MARK: Pointer

    private func _local(_ e: PointerEvent) -> Offset { _box?.globalToLocal(e.position) ?? e.position }

    private func _down(_ e: PointerEvent) {
        focus.requestFocus()
        let p = _local(e)
        let c = controller
        if e.buttons & kSecondaryMouseButton != 0 {
            _secondaryDown(e, at: p)
            return
        }
        // The outline gutters: level buttons and +/− boxes.
        if p.dx < outlineWidth || p.dy < outlineHeight {
            commitEdit()
            let o = _outline()
            for (axis, level, groups) in [(WorkbookController.Axis.rows, o.rowLevel, o.rowGroups), (.cols, o.colLevel, o.colGroups)] where level > 0 {
                if let k = (1 ... level + 1).first(where: { outlineLevelButton($0, axis).inflate(2).contains(p) }) {
                    c.showOutlineLevel(k, axis)
                    return
                }
                if let g = groups.first(where: { outlineBox($0, axis)?.inflate(3).contains(p) ?? false }) {
                    c.toggleGroup(g, axis)
                    return
                }
            }
            return
        }
        // Column header: select columns, or resize at a border.
        if p.dy < headerHeight && p.dx >= headerWidth {
            let col = self.col(atLocal: p.dx)
            let edgeLeft = colX(col), edgeRight = edgeLeft + cols.size(col)
            if abs(p.dx - edgeRight) <= 4 || (col > 0 && abs(p.dx - edgeLeft) <= 4) {
                let target = abs(p.dx - edgeRight) <= 4 ? col : col - 1
                commitEdit()
                if _isBorderDoubleClick(.cols, target) { autofit(.cols, target); return }
                _drag = .resizeColumn(col: target, startX: p.dx, startWidth: cols.size(target))
                return
            }
            commitEdit()
            // Shift extends from the selection's anchor column, as Excel's does.
            let anchorCol = _chords.shift ? c.anchor.col : col
            c.select(range: CellRange(top: 0, left: min(anchorCol, col), bottom: CellAddress.maxRows - 1, right: max(anchorCol, col)),
                     active: _chords.shift ? c.active : CellAddress(row: scrollY > 0 ? rows.index(at: scrollY) : 0, col: col))
            _drag = .columns(anchor: anchorCol)
            return
        }
        if p.dx < headerWidth && p.dy >= headerHeight {
            let row = self.row(atLocal: p.dy)
            let edgeBottom = rowY(row) + rows.size(row)
            if abs(p.dy - edgeBottom) <= 3 {
                commitEdit()
                if _isBorderDoubleClick(.rows, row) { autofit(.rows, row); return }
                _drag = .resizeRow(row: row, startY: p.dy, startHeight: rows.size(row))
                return
            }
            commitEdit()
            let anchorRow = _chords.shift ? c.anchor.row : row
            c.select(range: CellRange(top: min(anchorRow, row), left: 0, bottom: max(anchorRow, row), right: CellAddress.maxCols - 1),
                     active: _chords.shift ? c.active : CellAddress(row: row, col: scrollX > 0 ? cols.index(at: scrollX) : 0))
            _drag = .rows(anchor: anchorRow)
            return
        }
        if p.dx < headerWidth && p.dy < headerHeight {
            commitEdit()
            c.select(range: CellRange(top: 0, left: 0, bottom: CellAddress.maxRows - 1, right: CellAddress.maxCols - 1), active: c.active)
            return
        }
        // A validation list's arrow.
        if let b = listButton(), b.contains(p), let choices = c.validationChoices(at: c.active) {
            let origin = _box?.localToGlobal(Offset(b.left - rect(c.active).width, b.bottom)) ?? Offset(b.left, b.bottom)
            _w.onListMenu(origin, c.active, choices)
            return
        }
        // Pictures and charts sit over the cells: they take the press first.
        if let hit = _drawingHit(p) {
            commitEdit()
            c.selectedDrawing = hit.index
            c._notify(selectionOnly: true)
            let ws = c.sheet
            _drag = .drawing(index: hit.index, handle: hit.handle, frame: ws.frame(ws.drawings[hit.index].anchor),
                             anchor: ws.drawings[hit.index].anchor, start: p)
            return
        }
        let a = cell(atLocal: p)
        // A filter's dropdown on its header row.
        if let af = c.sheet.autoFilter, a.row == af.range.top, a.col >= af.range.left, a.col <= af.range.right,
           filterButton(a).inflate(1).contains(p) {
            commitEdit()
            let b = filterButton(a)
            let origin = _box?.localToGlobal(Offset(b.left, b.bottom)) ?? Offset(b.left, b.bottom)
            _w.onFilterMenu(origin, a.col)
            return
        }
        // The fill handle: the small square at the selection's corner.
        if edit == nil {
            let sel = rect(c.selection)
            if abs(p.dx - sel.right) <= 5 && abs(p.dy - sel.bottom) <= 5 {
                let now = Date().timeIntervalSince1970
                if let last = _lastFillPress, now - last < 0.4 {
                    _lastFillPress = nil
                    if !c.autoFillDown() { _w.onStatus("Nothing beside the selection to fill down along") }
                    return
                }
                _lastFillPress = now
                _fillFrom = p
                _drag = .fill(target: c.selection)
                return
            }
        }
        if let ed = edit {
            if ed.cell == a { return }
            // Typing a formula and at a place a reference can go: the click
            // points at the cell (a drag at a range), as Excel's Point mode.
            if pointing || _pointRef != nil {
                var e = edit!
                let start = _pointRef?.start ?? e.caret
                e.text.replaceSubrange(start ..< e.caret, with: Array(a.a1))
                e.caret = start + a.a1.count
                edit = e
                _pointRef = (start, a)
                _w.onEditText(String(e.text))
                _drag = .point(textStart: start, anchor: a)
                _repaint.notifyListeners()
                return
            }
            commitEdit()
        }
        // ⌘-click on a link follows it; a plain click selects, as everywhere.
        if _chords.primary && edit == nil, let link = c.link(at: a) {
            switch link {
            case .url(let u):
                let lower = u.lowercased()
                if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("mailto:") {
                    hostOpenURL?(u)
                    _w.onStatus("Opening \(u)")
                } else {
                    _w.onStatus("Links to \(u) are not opened from here")
                }
            case .place(let p):
                if !c.go(to: p) { _w.onStatus("Reference isn't valid: \(p)") } else { reveal(c.active) }
            }
            return
        }
        // Double click, detected by hand (onDoubleTap kills taps on DRM).
        let now = Date().timeIntervalSince1970
        if let last = _lastClick, last.cell == a, now - last.at < 0.4 {
            _lastClick = nil
            c.select(a)
            beginEdit()
            return
        }
        _lastClick = (a, now)
        c.select(a, extend: _chords.shift)
        _drag = .cells
    }

    private func _isBorderDoubleClick(_ axis: WorkbookController.Axis, _ index: Int) -> Bool {
        let now = Date().timeIntervalSince1970
        if let last = _lastBorder, last.axis == axis, last.index == index, now - last.at < 0.4 {
            _lastBorder = nil
            return true
        }
        _lastBorder = (axis, index, now)
        return false
    }

    /// A right click: inside the selection it keeps it (Excel acts on the
    /// whole selection); outside, it selects what is under the pointer
    /// first. Headers select whole rows or columns.
    private func _secondaryDown(_ e: PointerEvent, at p: Offset) {
        let c = controller
        commitEdit()
        _lastClick = nil
        let sel = c.selection
        let wholeCols = sel.top == 0 && sel.bottom == CellAddress.maxRows - 1
        let wholeRows = sel.left == 0 && sel.right == CellAddress.maxCols - 1
        if p.dx < outlineWidth || p.dy < outlineHeight { return }
        if p.dy < headerHeight && p.dx >= headerWidth {
            let col = self.col(atLocal: p.dx)
            if !(wholeCols && col >= sel.left && col <= sel.right) {
                c.select(range: CellRange(top: 0, left: col, bottom: CellAddress.maxRows - 1, right: col),
                         active: CellAddress(row: scrollY > 0 ? rows.index(at: scrollY) : 0, col: col))
            }
            _w.onContextMenu(e.position, .columns)
            return
        }
        if p.dx < headerWidth && p.dy >= headerHeight {
            let row = self.row(atLocal: p.dy)
            if !(wholeRows && row >= sel.top && row <= sel.bottom) {
                c.select(range: CellRange(top: row, left: 0, bottom: row, right: CellAddress.maxCols - 1),
                         active: CellAddress(row: row, col: scrollX > 0 ? cols.index(at: scrollX) : 0))
            }
            _w.onContextMenu(e.position, .rows)
            return
        }
        guard p.dx >= headerWidth && p.dy >= headerHeight else { return }
        if let hit = _drawingHit(p) {
            c.selectedDrawing = hit.index
            c._notify(selectionOnly: true)
            _w.onContextMenu(e.position, .drawing(hit.index))
            return
        }
        let a = cell(atLocal: p)
        if !sel.contains(a) { c.select(a) }
        _w.onContextMenu(e.position, wholeCols && sel.contains(a) ? .columns : wholeRows && sel.contains(a) ? .rows : .cells)
    }

    // MARK: Autofit

    /// Double-click on a header border: the column as wide as its widest
    /// value, or the row as tall as its tallest — for every selected
    /// whole column (row) when the one clicked is among them, as Excel.
    func autofit(_ axis: WorkbookController.Axis, _ index: Int) {
        let c = controller
        let sel = c.selection
        var targets = [index]
        if axis == .cols, sel.top == 0, sel.bottom == CellAddress.maxRows - 1, index >= sel.left, index <= sel.right {
            targets = Array(sel.left ... sel.right)
        }
        if axis == .rows, sel.left == 0, sel.right == CellAddress.maxCols - 1, index >= sel.top, index <= sel.bottom {
            targets = Array(sel.top ... sel.bottom)
        }
        let want = Set(targets)
        let ws = c.sheet
        // Cells under a merge are not measured (Excel ignores them too).
        let merged = ws.merges.filter { $0.rows > 1 || $0.cols > 1 }
        var best: [Int: Double] = [:]
        for (a, cell) in ws.cells where want.contains(axis == .cols ? a.col : a.row) && !cell.value.isEmpty {
            if merged.contains(where: { $0.contains(a) }) { continue }
            let st = c.book.style(cell.style)
            let tstyle = _textStyle(st, color: nil, ink: Color(0xFF00_0000))
            let size = c.book.fontSize(st)
            if axis == .cols {
                if st.wrap && cell.value.isText { continue }
                // The full text: autofit is how long numbers stop being ####.
                let text = NumberFormat.display(cell.value, st.numberFormat, width: 255).text
                let w = (texts.painter(text, tstyle).width + 4 * zoom) / scale + 1.5
                best[a.col] = max(best[a.col] ?? 0, w)
            } else {
                // Calibri 11 is 15pt in Excel; other sizes scale with it.
                var lines = 1.0
                if st.wrap && cell.value.isText {
                    let text = NumberFormat.display(cell.value, st.numberFormat, width: 255).text
                    let width = cols.size(a.col) - 4 * zoom
                    let tp = texts.painter(text, tstyle, maxWidth: max(1, width))
                    let one = texts.painter("X", tstyle).height
                    lines = max(1, (tp.height / max(1, one)).rounded())
                }
                best[a.row] = max(best[a.row] ?? 0, lines * size * 15 / 11)
            }
        }
        c.structural {
            for t in targets {
                if axis == .cols {
                    // An empty column goes back to the sheet's default width.
                    if let w = best[t] { ws.colWidths[t] = (w * 4).rounded(.up) / 4 } else { ws.colWidths[t] = nil }
                    ws.widenedCols.remove(t)
                } else {
                    if let h = best[t] { ws.rowHeights[t] = (h * 4).rounded(.up) / 4 } else { ws.rowHeights[t] = nil }
                }
            }
        }
        _repaint.notifyListeners()
    }

    private func _move(_ e: PointerEvent) {
        guard let d = _drag else { return }
        let p = _local(e)
        let c = controller
        switch d {
        case .cells:
            let a = cell(atLocal: p)
            if a != c._extentEnd { c.select(a, extend: true); _autoScroll(p) }
        case .columns(let anchor):
            let col = self.col(atLocal: p.dx)
            c.select(range: CellRange(top: 0, left: min(anchor, col), bottom: CellAddress.maxRows - 1, right: max(anchor, col)),
                     active: c.active)
        case .rows(let anchor):
            let row = self.row(atLocal: p.dy)
            c.select(range: CellRange(top: min(anchor, row), left: 0, bottom: max(anchor, row), right: CellAddress.maxCols - 1),
                     active: c.active)
        case .drawing(let index, let handle, let f, _, let start):
            let dx = (p.dx - start.dx) / scale, dy = (p.dy - start.dy) / scale
            var x = f.x, y = f.y, r = f.x + f.width, b = f.y + f.height
            if let h = handle {
                if [0, 6, 7].contains(h) { x = min(r - 8, x + dx) }
                if [2, 3, 4].contains(h) { r = max(x + 8, r + dx) }
                if [0, 1, 2].contains(h) { y = min(b - 8, y + dy) }
                if [4, 5, 6].contains(h) { b = max(y + 8, b + dy) }
            } else {
                x += dx; y += dy; r += dx; b += dy
                if x < 0 { r -= x; x = 0 }
                if y < 0 { b -= y; y = 0 }
            }
            let ws = c.sheet
            if ws.drawings.indices.contains(index) {
                // Live, without an undo step per pixel: committed on release.
                ws.drawings[index].anchor = ws.anchor(x: x, y: y, width: r - x, height: b - y)
                _repaint.notifyListeners()
            }
        case .resizeColumn(let col, let startX, let startWidth):
            let w = max(0, startWidth + p.dx - startX)
            // Live, without an undo step per pixel: the model is set on release.
            c.sheet.colWidths[col] = w / scale
            _repaint.notifyListeners()
        case .resizeRow(let row, let startY, let startHeight):
            let h = max(0, startHeight + p.dy - startY)
            c.sheet.rowHeights[row] = h / scale
            _repaint.notifyListeners()
        case .fill:
            if let from = _fillFrom {
                guard (p.dx - from.dx) * (p.dx - from.dx) + (p.dy - from.dy) * (p.dy - from.dy) >= 16 else { return }
                _fillFrom = nil
            }
            // Down/up or across, whichever the pointer has gone further in.
            let sel = c.selection
            let a = cell(atLocal: p)
            let dRow = a.row > sel.bottom ? a.row - sel.bottom : (a.row < sel.top ? a.row - sel.top : 0)
            let dCol = a.col > sel.right ? a.col - sel.right : (a.col < sel.left ? a.col - sel.left : 0)
            var t = sel
            if abs(dRow) >= abs(dCol) {
                if dRow > 0 { t.bottom = a.row } else if dRow < 0 { t.top = a.row }
            } else {
                if dCol > 0 { t.right = a.col } else if dCol < 0 { t.left = a.col }
            }
            _drag = .fill(target: t)
            fillTarget = t
            _autoScroll(p)
            _repaint.notifyListeners()
        case .point(let start, let anchor):
            guard var e = edit else { return }
            let a = cell(atLocal: p)
            let ref = a == anchor ? anchor.a1 : CellRange(anchor, a).a1
            e.text.replaceSubrange(start ..< e.caret, with: Array(ref))
            e.caret = start + ref.count
            edit = e
            _w.onEditText(String(e.text))
            _repaint.notifyListeners()
        }
    }

    /// Whether a click (or an arrow) should insert a reference: a formula
    /// is being typed and the caret follows an operator, "(" or ",".
    var pointing: Bool {
        guard let e = edit, e.text.first == "=", e.caret == e.text.count else { return false }
        guard let last = e.text.last else { return false }
        return "=(,+-*/^&<>:;".contains(last)
    }

    private func _up(_ e: PointerEvent) {
        _move(e)
        if case .drawing(let index, _, _, let old, _)? = _drag {
            let ws = controller.sheet
            if ws.drawings.indices.contains(index) {
                let f = ws.frame(ws.drawings[index].anchor)
                controller.setDrawingFrame(index, x: f.x, y: f.y, width: f.width, height: f.height, from: old)
            }
        }
        if case .fill(let target)? = _drag {
            fillTarget = nil
            if target != controller.selection { controller.fillSeries(to: target) }
        }
        if case .resizeColumn(let col, _, let startWidth)? = _drag {
            controller.setColumnWidth(col, controller.sheet.colWidth(col), from: startWidth / scale)
        }
        if case .resizeRow(let row, _, let startHeight)? = _drag {
            controller.setRowHeight(row, controller.sheet.rowHeight(row), from: startHeight / scale)
        }
        _drag = nil
    }

    private func _autoScroll(_ p: Offset) {
        var dx = 0.0, dy = 0.0
        if p.dx > size.width - 8 { dx = cols.def }
        if p.dx < headerWidth + 8, scrollX > 0 { dx = -cols.def }
        if p.dy > size.height - 8 { dy = rows.def }
        if p.dy < headerHeight + 8, scrollY > 0 { dy = -rows.def }
        if dx != 0 || dy != 0 { _scroll(by: dx, dy) }
    }

    private func _hover(_ e: PointerEvent) {
        let p = _local(e)
        var hit: CellAddress? = nil
        if p.dx >= headerWidth, p.dy >= headerHeight, !controller.sheet.notes.isEmpty {
            let a = cell(atLocal: p)
            if controller.sheet.notes.contains(where: { $0.at == a }) { hit = a }
        }
        if hit != _hoverNote { _hoverNote = hit; _repaint.notifyListeners() }
    }

    /// The hovered cell's note: a pale yellow box to its right, author first.
    private func _paintNote(_ canvas: any Canvas, ink: Color) {
        guard let a = _hoverNote, let note = controller.sheet.notes.first(where: { $0.at == a }) else { return }
        let r = rect(a)
        let width = 200 * zoom, pad = 6 * zoom
        let body = GridTextStyle(family: OfficeFonts.drawn("Segoe UI"), size: 12 * zoom, color: Int64(0xFF00_0000))
        var head = body
        head.bold = true
        // A threaded comment's legacy copy starts with Excel's own banner; show the words.
        var text = note.text
        if let range = text.findRange(of: "Comment:\n") ?? text.findRange(of: "Comment:\r\n") {
            text = String(text[range.upperBound...])
        }
        // Excel writes the author into the note itself ("Ada:" then a line
        // break): that first line is the bold heading, not a second one.
        var heading = note.author.isEmpty ? nil : note.author + ":"
        if let h = heading, text.hasPrefix(h) {
            text = String(text.dropFirst(h.count))
        } else if !note.author.isEmpty {
            heading = nil
            if let nl = text.firstIndex(of: "\n"), text[..<nl].hasSuffix(":") {
                heading = String(text[..<nl]); text = String(text[text.index(after: nl)...])
            } else {
                heading = note.author + ":"
            }
        }
        let author = heading.map { texts.painter($0, head, maxWidth: width - pad * 2) }
        let tp = texts.painter(text.trimmingWhitespace(), body, maxWidth: width - pad * 2)
        let height = pad * 2 + (author?.height ?? 0) + tp.height
        var box = Rect.fromLTWH(r.right + 8 * zoom, r.top, width, height)
        if box.right > size.width { box = Rect.fromLTWH(max(headerWidth, r.left - 8 * zoom - width), r.top, width, height) }
        if box.bottom > size.height { box = box.translate(0, size.height - box.bottom) }
        let p = Paint()
        p.style = .fill
        p.color = Color(0xFFFFFFE1)
        canvas.drawRect(box, p)
        p.style = .stroke
        p.strokeWidth = 1
        p.color = Color(0xFF7F7F7F)
        canvas.drawRect(box.deflate(0.5), p)
        canvas.drawLine(Offset(r.right - 1, r.top + 1), Offset(box.left, box.top + 6 * zoom), p)
        var y = box.top + pad
        if let author { author.paint(canvas, Offset(box.left + pad, y)); y += author.height }
        tp.paint(canvas, Offset(box.left + pad, y))
    }

    /// The active cell's validation input message: a pale yellow box
    /// under it, title in bold, as Excel shows it until the selection moves.
    private func _paintPrompt(_ canvas: any Canvas) {
        let c = controller
        guard !printing, edit == nil, c.selectedDrawing == nil, let prompt = c.validationPrompt(at: c.active) else { return }
        let r = rect(c.active)
        guard r.bottom > headerHeight, r.right > headerWidth else { return }
        let width = 200 * zoom, pad = 6 * zoom
        let body = GridTextStyle(family: OfficeFonts.drawn("Segoe UI"), size: 12 * zoom, color: Int64(0xFF00_0000))
        var head = body
        head.bold = true
        let title = prompt.title.isEmpty ? nil : texts.painter(prompt.title, head, maxWidth: width - pad * 2)
        let tp = prompt.text.isEmpty ? nil : texts.painter(prompt.text, body, maxWidth: width - pad * 2)
        let height = pad * 2 + (title?.height ?? 0) + (tp?.height ?? 0) + (title != nil && tp != nil ? 2 * zoom : 0)
        var box = Rect.fromLTWH(r.left + 12 * zoom, r.bottom + 4 * zoom, width, height)
        if box.right > size.width { box = box.translate(size.width - box.right, 0) }
        if box.bottom > size.height { box = Rect.fromLTWH(box.left, r.top - 4 * zoom - height, width, height) }
        let p = Paint()
        p.style = .fill
        p.color = Color(0xFFFFFFE1)
        canvas.drawRect(box, p)
        p.style = .stroke
        p.strokeWidth = 1
        p.color = Color(0xFF7F7F7F)
        canvas.drawRect(box.deflate(0.5), p)
        var y = box.top + pad
        if let title { title.paint(canvas, Offset(box.left + pad, y)); y += title.height + 2 * zoom }
        tp?.paint(canvas, Offset(box.left + pad, y))
    }

    private func _signal(_ e: PointerSignalEvent) {
        guard let s = e as? PointerScrollEvent else { return }
        // Shift turns the wheel sideways, as everywhere on the desktop.
        if _chords.shift && s.scrollDelta.dx == 0 { _scroll(by: s.scrollDelta.dy, 0) }
        else { _scroll(by: s.scrollDelta.dx, s.scrollDelta.dy) }
    }

    private func _pan(_ e: PointerPanZoomUpdateEvent) {
        _scroll(by: -e.panDelta.dx, -e.panDelta.dy)
    }

    // MARK: Build

    override func build(_ context: any BuildContext) -> Widget {
        _painter.fluent = FluentTheme.of(context)
        return SizeReporter(onSize: { [weak self] s in
            guard let self, self.mounted, s != self.size else { return }
            self.size = s
            self._repaint.notifyListeners()
        }, onBox: { [weak self] box in self?._box = box }, child: Listener(
            onPointerDown: { [weak self] e in self?._down(e) },
            onPointerMove: { [weak self] e in self?._move(e) },
            onPointerUp: { [weak self] e in self?._up(e) },
            onPointerHover: { [weak self] e in self?._hover(e) },
            onPointerPanZoomUpdate: { [weak self] e in self?._pan(e) },
            onPointerSignal: { [weak self] e in self?._signal(e) },
            behavior: .opaque,
            child: ClipRect(child: CustomPaint(painter: _painter, child: SizedBox(expand: ())))))
    }

    // MARK: Paint

    /// The first screen of the active sheet through the window's own
    /// painter, with no window (`--read-bench`): at the printing scale,
    /// since the zoom is the widget's.
    func paintFirstScreen(_ size: Size) {
        printing = true
        defer { printing = false }
        let recorder = NativePictureRecorder()
        let canvas = NativeCanvas(recorder: recorder, cullRect: Rect.fromLTWH(0, 0, size.width, size.height))
        paint(canvas, size, fluent: nil)
        _ = recorder.endRecording()
    }

    fileprivate func paint(_ canvas: any Canvas, _ size: Size, fluent: FluentThemeData?) {
        let c = controller
        let ws = c.sheet
        let book = c.book
        let dark = fluent?.brightness == .dark
        let ink = dark ? Color(0xFFF0F0F0) : Color(0xFF1B1B1B)
        let paper = dark ? Color(0xFF1F1F1F) : Color(0xFFFFFFFF)
        let gridColor = dark ? Color(0xFF3A3A3A) : Color(0xFFE1E1E1)
        let headerFill = dark ? Color(0xFF2B2B2B) : Color(0xFFF5F5F5)
        let headerInk = dark ? Color(0xFFC8C8C8) : Color(0xFF616161)
        let accent = fluent?.accentColor.defaultBrushFor(fluent?.brightness ?? .light) ?? Color(0xFF217346)
        let ca = cols, ra = rows
        let hw = headerWidth, hh = headerHeight
        let fc = frozenCols, fr = frozenRows
        let fw = ca.start(fc), fh = ra.start(fr)
        let colors = _Colors(ink: ink, paper: paper, grid: gridColor, showGrid: ws.showGridlines)

        let p = Paint()
        p.style = .fill
        p.color = paper
        canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), p)

        // What is in view: the frozen rows/columns, then the scrolled ones.
        var frozenC: [Int] = [], scrolledC: [Int] = []
        for col in 0 ..< fc where colX(col) < size.width { frozenC.append(col) }
        var col = ca.index(at: fw + scrollX)
        while col < CellAddress.maxCols, colX(col) < size.width { if ca.size(col) > 0 { scrolledC.append(col) }; col += 1 }
        var frozenR: [Int] = [], scrolledR: [Int] = []
        for row in 0 ..< fr where rowY(row) < size.height { frozenR.append(row) }
        var row = ra.index(at: fh + scrollY)
        while row < CellAddress.maxRows, rowY(row) < size.height { if ra.size(row) > 0 { scrolledR.append(row) }; row += 1 }
        _lastVisibleRow = scrolledR.last ?? frozenR.last ?? 0
        let allC = frozenC + scrolledC, allR = frozenR + scrolledR

        // Merged areas in view: the top-left cell draws over the whole.
        var covered: Set<CellAddress> = []
        var merges: [CellRange] = []
        if let r0 = allR.first, let r1 = allR.max(), let c0 = allC.first, let c1 = allC.max() {
            let view = CellRange(top: r0, left: c0, bottom: r1, right: c1)
            for m in ws.merges where m.intersects(view) && m.rows * m.cols <= 100_000 {
                merges.append(m)
                for rr in m.top ... m.bottom { for cc in m.left ... m.right where !(rr == m.top && cc == m.left) {
                    covered.insert(CellAddress(row: rr, col: cc))
                } }
            }
        }

        let regions: [([Int], [Int], Rect)] = [
            (scrolledR, scrolledC, Rect.fromLTRB(hw + fw, hh + fh, size.width, size.height)),
            (frozenR, scrolledC, Rect.fromLTRB(hw + fw, hh, size.width, hh + fh)),
            (scrolledR, frozenC, Rect.fromLTRB(hw, hh + fh, hw + fw, size.height)),
            (frozenR, frozenC, Rect.fromLTRB(hw, hh, hw + fw, hh + fh)),
        ]
        for (rs, cs, clip) in regions where !rs.isEmpty && !cs.isEmpty && clip.width > 0 && clip.height > 0 {
            canvas.save()
            canvas.clipRect(clip)
            _paintRegion(canvas, rows: rs, cols: cs, clip: clip, ws: ws, book: book, merges: merges, covered: covered, colors: colors)
            canvas.restore()
        }
        canvas.save()
        canvas.clipRect(Rect.fromLTRB(hw, hh, size.width, size.height))
        // Selection.
        let sel = c.selection
        let editing = edit?.cell
        do {
            let r = rect(sel)
            // A merged area is one cell: no tint for it alone.
            if !sel.isSingle && !ws.merges.contains(sel) {
                p.color = accent.withAlpha(36)
                canvas.drawRect(r, p)
                // The active cell keeps its own background inside the tint.
                let act = merges.first { $0.contains(c.active) }.map { rect($0) } ?? rect(c.active)
                p.color = book.style(ws.cells[c.active]?.style ?? 0).fill.map { Color(Int64(0xFF00_0000) | Int64($0)) } ?? paper
                canvas.drawRect(act.deflate(1), p)
                if let cell = ws.cells[c.active], !cell.value.isEmpty, c.active != editing {
                    _paintCell(canvas, c.active, cell, in: act, spill: false, ws: ws, book: book, ink: ink)
                }
            }
            let frame = Paint()
            frame.style = .stroke
            frame.strokeWidth = 2
            frame.color = accent
            canvas.drawRect(Rect.fromLTRB(r.left.rounded(), r.top.rounded(), r.right.rounded() - 1, r.bottom.rounded() - 1), frame)
            // The fill handle.
            p.color = accent
            canvas.drawRect(Rect.fromLTWH(r.right.rounded() - 4, r.bottom.rounded() - 4, 6, 6), p)
            p.color = paper
            canvas.drawRect(Rect.fromLTWH(r.right.rounded() - 5, r.bottom.rounded() - 5, 1, 7), p)
            canvas.drawRect(Rect.fromLTWH(r.right.rounded() - 5, r.bottom.rounded() - 5, 7, 1), p)
        }
        // The fill handle's target.
        if let t = fillTarget {
            let outline = Paint()
            outline.style = .stroke
            outline.strokeWidth = 1
            outline.color = dark ? Color(0xFFBDBDBD) : Color(0xFF616161)
            let r = rect(t)
            canvas.drawRect(Rect.fromLTRB(r.left.rounded() + 0.5, r.top.rounded() + 0.5, r.right.rounded() - 0.5, r.bottom.rounded() - 0.5), outline)
        }
        // The copied cells' dashed frame.
        if let m = marquee, m.sheet == controller.activeSheet {
            let r = rect(m.range)
            _dashedFrame(canvas, Rect.fromLTRB(r.left.rounded(), r.top.rounded(), r.right.rounded() - 1, r.bottom.rounded() - 1),
                         view: Rect.fromLTRB(hw, hh, size.width, size.height), ink: accent, under: paper)
        }
        // Pictures and charts float over the cells and their selection, pane by pane.
        if !ws.drawings.isEmpty || !ws.objects.isEmpty {
            let charts = ws.drawings.map { d -> Chart? in
                if case .chart(let sc) = d.kind { return controller.liveChart(sc) }
                return nil
            }
            for (rs, cs, clip) in regions where !rs.isEmpty && !cs.isEmpty && clip.width > 0 && clip.height > 0 {
                canvas.save()
                canvas.clipRect(clip)
                for (i, d) in ws.drawings.enumerated() {
                    let r = drawingRect(d.anchor)
                    guard r.overlaps(clip), !d.hidden, !(printing && d.screenOnly) else { continue }
                    _paintDrawing(canvas, d, chart: charts[i], in: r, theme: book.chartTheme)
                }
                _paintObjects(canvas, ws, clip: clip)
                canvas.restore()
            }
        }

        // The active cell in a spill: the whole spilled range outlined, as Excel does.
        if !ws.spilled.isEmpty || ws.cells[c.active]?.spillRange != nil {
            let act = c.active
            let spill = ws.cells[act]?.spillRange
                ?? ws.cells.values.lazy.compactMap(\.spillRange).first { $0.contains(act) }
            if let spill {
                let r = rect(spill)
                let edge = Paint()
                edge.style = .stroke
                edge.strokeWidth = 1
                edge.color = Color(0xFF2F6FDF)
                canvas.drawRect(Rect.fromLTRB(r.left.rounded() + 0.5, r.top.rounded() + 0.5, r.right.rounded() - 0.5, r.bottom.rounded() - 0.5), edge)
            }
        }
        _paintDrawingSelection(canvas, accent: accent)
        if let b = listButton() {
            p.color = dark ? Color(0xFF3A3A3A) : Color(0xFFF3F3F3)
            canvas.drawRect(b, p)
            let edge = Paint()
            edge.style = .stroke
            edge.strokeWidth = 1
            edge.color = dark ? Color(0xFF6A6A6A) : Color(0xFFABABAB)
            canvas.drawRect(b.deflate(0.5), edge)
            let tri = Path()
            let cx = b.center.dx, cy = b.center.dy, u = b.width / 16
            tri.moveTo(cx - 4 * u, cy - 2 * u); tri.lineTo(cx + 4 * u, cy - 2 * u); tri.lineTo(cx, cy + 2.5 * u); tri.close()
            p.color = ink
            canvas.drawPath(tri, p)
        }
        _paintNote(canvas, ink: ink)
        _paintPrompt(canvas)
        // The freeze lines.
        let freeze = Paint()
        freeze.style = .stroke
        freeze.strokeWidth = 1
        freeze.color = dark ? Color(0xFF8A8A8A) : Color(0xFF9E9E9E)
        if fc > 0 { canvas.drawLine(Offset((hw + fw).rounded() - 0.5, hh), Offset((hw + fw).rounded() - 0.5, size.height), freeze) }
        if fr > 0 { canvas.drawLine(Offset(hw, (hh + fh).rounded() - 0.5), Offset(size.width, (hh + fh).rounded() - 0.5), freeze) }
        // The editor.
        if let e = edit {
            _paintEditor(canvas, e, ink: ink, paper: paper, accent: accent, size: size)
        }
        canvas.restore()

        // Headers.
        let line = Paint()
        line.style = .stroke
        line.strokeWidth = 1
        line.color = gridColor
        p.color = headerFill
        canvas.drawRect(Rect.fromLTWH(0, 0, size.width, hh), p)
        canvas.drawRect(Rect.fromLTWH(0, 0, hw, size.height), p)
        let headStyle = GridTextStyle(family: SelawikFontName.regular, size: 11 * zoom, color: Int64(headerInk.value))
        let headStrong = GridTextStyle(family: SelawikFontName.regular, size: 11 * zoom, bold: true, color: Int64(accent.value))
        let headFiltered = GridTextStyle(family: SelawikFontName.regular, size: 11 * zoom, color: Int64(0xFF2F6FDF))
        let filterActive = !(ws.autoFilter?.columns.isEmpty ?? true)
        let wholeCols = sel.top == 0 && sel.bottom == CellAddress.maxRows - 1
        let wholeRows = sel.left == 0 && sel.right == CellAddress.maxCols - 1
        canvas.save()
        canvas.clipRect(Rect.fromLTRB(hw, 0, size.width, hh))
        for col in allC {
            let x0 = colX(col), x1 = x0 + ca.size(col)
            if fc > 0 && col >= fc && x0 < hw + fw { continue }
            let on = col >= sel.left && col <= sel.right
            if on {
                p.color = wholeCols ? accent.withAlpha(60) : (dark ? Color(0xFF3A3A3A) : Color(0xFFE0E0E0))
                canvas.drawRect(Rect.fromLTRB(x0, outlineHeight, x1, hh), p)
                p.color = accent
                canvas.drawRect(Rect.fromLTRB(x0, hh - 2, x1, hh), p)
            }
            let tp = texts.painter(CellAddress.columnName(col), on ? headStrong : headStyle)
            if x1 - x0 > tp.width + 2 {
                tp.paint(canvas, Offset(((x0 + x1) / 2 - tp.width / 2).rounded(), (outlineHeight + (hh - outlineHeight - tp.height) / 2).rounded()))
            }
            canvas.drawLine(Offset(x1.rounded() - 0.5, outlineHeight), Offset(x1.rounded() - 0.5, hh), line)
        }
        _paintOutline(canvas, size, .cols, ink: headerInk, line: dark ? Color(0xFF6A6A6A) : Color(0xFF9E9E9E), paper: paper)
        canvas.restore()
        canvas.save()
        canvas.clipRect(Rect.fromLTRB(0, hh, hw, size.height))
        for row in allR {
            let y0 = rowY(row), y1 = y0 + ra.size(row)
            if fr > 0 && row >= fr && y0 < hh + fh { continue }
            let on = row >= sel.top && row <= sel.bottom
            if on {
                p.color = wholeRows ? accent.withAlpha(60) : (dark ? Color(0xFF3A3A3A) : Color(0xFFE0E0E0))
                canvas.drawRect(Rect.fromLTRB(outlineWidth, y0, hw, y1), p)
                p.color = accent
                canvas.drawRect(Rect.fromLTRB(hw - 2, y0, hw, y1), p)
            }
            // A filtered table's row numbers are blue, as Excel shows that rows are hidden.
            let filtered = filterActive && row > ws.autoFilter!.range.top && row <= ws.autoFilter!.range.bottom
            let tp = texts.painter(String(row + 1), on ? headStrong : filtered ? headFiltered : headStyle)
            if y1 - y0 > tp.height - 2 {
                tp.paint(canvas, Offset((hw - 6 - tp.width).rounded(), ((y0 + y1) / 2 - tp.height / 2).rounded()))
            }
            canvas.drawLine(Offset(outlineWidth, y1.rounded() - 0.5), Offset(hw, y1.rounded() - 0.5), line)
        }
        _paintOutline(canvas, size, .rows, ink: headerInk, line: dark ? Color(0xFF6A6A6A) : Color(0xFF9E9E9E), paper: paper)
        canvas.restore()
        line.color = dark ? Color(0xFF4A4A4A) : Color(0xFFC8C8C8)
        canvas.drawLine(Offset(0, hh - 0.5), Offset(size.width, hh - 0.5), line)
        canvas.drawLine(Offset(hw - 0.5, 0), Offset(hw - 0.5, size.height), line)
        let o = _outline()
        if outlineWidth > 0 { canvas.drawLine(Offset(outlineWidth - 0.5, 0), Offset(outlineWidth - 0.5, size.height), line) }
        if outlineHeight > 0 { canvas.drawLine(Offset(0, outlineHeight - 0.5), Offset(size.width, outlineHeight - 0.5), line) }
        let box = Paint()
        box.style = .stroke
        box.strokeWidth = 1
        box.color = headerInk
        for (axis, level) in [(WorkbookController.Axis.rows, o.rowLevel), (.cols, o.colLevel)] where level > 0 {
            for k in 1 ... level + 1 {
                let b = outlineLevelButton(k, axis)
                canvas.drawRect(Rect.fromLTRB(b.left.rounded() + 0.5, b.top.rounded() + 0.5, b.right.rounded() - 0.5, b.bottom.rounded() - 0.5), box)
                let tp = texts.painter("\(k)", GridTextStyle(family: SelawikFontName.regular, size: 9 * zoom, color: Int64(headerInk.value)))
                tp.paint(canvas, Offset((b.center.dx - tp.width / 2).rounded(), (b.center.dy - tp.height / 2).rounded()))
            }
        }
        // The corner: a triangle that selects everything.
        p.color = dark ? Color(0xFF5A5A5A) : Color(0xFFBDBDBD)
        let path = Path()
        path.moveTo(hw - 4, hh - 14 * zoom)
        path.lineTo(hw - 4, hh - 4)
        path.lineTo(hw - 14 * zoom, hh - 4)
        path.close()
        canvas.drawPath(path, p)
    }

    /// A gutter's brackets: a line beside each open group, ending in a tick
    /// at its far end, and the +/− box at its summary row (column).
    private func _paintOutline(_ canvas: any Canvas, _ size: Size, _ axis: WorkbookController.Axis, ink: Color, line: Color, paper: Color) {
        let groups = axis == .rows ? _outline().rowGroups : _outline().colGroups
        guard !groups.isEmpty, (axis == .rows ? outlineWidth : outlineHeight) > 0 else { return }
        let ws = controller.sheet
        // The span of the axis the gutter covers.
        let lo = axis == .rows ? headerHeight : headerWidth
        let hi = axis == .rows ? size.height : size.width
        let stroke = Paint()
        stroke.style = .stroke
        stroke.strokeWidth = 1
        stroke.color = line
        let fill = Paint()
        fill.style = .fill
        fill.color = paper
        func seg(_ a0: Double, _ c0: Double, _ a1: Double, _ c1: Double) {
            canvas.drawLine(_at(axis, along: a0, across: c0), _at(axis, along: a1, across: c1), stroke)
        }
        for g in groups {
            guard let b = outlineBox(g, axis) else { continue }
            let (bLo, bHi) = axis == .rows ? (b.top, b.bottom) : (b.left, b.right)
            let lane = (axis == .rows ? b.center.dx : b.center.dy).rounded() + 0.5
            let collapsed = ws.isCollapsed(g, axis)
            if !collapsed {
                let first = _start(axis, g.span.lowerBound) + 2 * zoom
                let last = _start(axis, g.span.upperBound) + _size(axis, g.span.upperBound) - 2 * zoom
                if last > lo && first < hi {
                    let after = g.summary > g.span.upperBound
                    // The bracket runs from the far end of the span to the box.
                    let far = after ? first : last
                    seg(after ? bLo : bHi, lane, after ? max(far, lo) : min(far, hi), lane)
                    if far > lo && far < hi { seg(far.rounded() + 0.5, lane, far.rounded() + 0.5, lane + 4 * zoom) }
                }
            }
            guard bHi > lo, bLo < hi else { continue }
            let r = Rect.fromLTRB(b.left.rounded() + 0.5, b.top.rounded() + 0.5, b.right.rounded() - 0.5, b.bottom.rounded() - 0.5)
            canvas.drawRect(r, fill)
            canvas.drawRect(r, stroke)
            stroke.color = ink
            canvas.drawLine(Offset(r.left + 2 * zoom, r.center.dy), Offset(r.right - 2 * zoom, r.center.dy), stroke)
            if collapsed { canvas.drawLine(Offset(r.center.dx, r.top + 2 * zoom), Offset(r.center.dx, r.bottom - 2 * zoom), stroke) }
            stroke.color = line
        }
    }

    /// Fills, in reading order, each run of one colour along a row drawn as
    /// one rect: cell by cell, anti-aliasing leaves a pale seam at every
    /// edge between two (lo-pivottable_invalid_formats' table header),
    /// and Excel's page has a rect per run. A run continues down the rows
    /// it spans alike, as one rect too (54288's grey blocks, one rect each
    /// in Excel's print, showed a seam under every row of ours).
    private func _fillRuns(_ canvas: any Canvas, _ p: Paint, _ fills: [(Rect, UInt32)]) {
        var runs: [(Rect, UInt32)] = []
        var open: [String: Int] = [:]   // left, right and colour → the run whose foot is open
        var i = 0
        while i < fills.count {
            var r = fills[i].0
            let f = fills[i].1
            var j = i + 1
            while j < fills.count, fills[j].1 == f, fills[j].0.top == r.top, fills[j].0.bottom == r.bottom,
                  abs(fills[j].0.left - r.right) < 0.01 {
                r = Rect.fromLTRB(r.left, r.top, fills[j].0.right, r.bottom)
                j += 1
            }
            let key = "\((r.left * 100).rounded()) \((r.right * 100).rounded()) \(f)"
            if let k = open[key], abs(runs[k].0.bottom - r.top) < 0.01 {
                runs[k].0 = Rect.fromLTRB(r.left, runs[k].0.top, r.right, r.bottom)
            } else {
                open[key] = runs.count
                runs.append((r, f))
            }
            i = j
        }
        for (r, f) in runs {
            p.color = Color(Int64(0xFF00_0000) | Int64(f))
            canvas.drawRect(r, p)
        }
    }

    struct _Colors {
        let ink: Color, paper: Color, grid: Color
        let showGrid: Bool
    }

    /// One pane of the grid: the given rows and columns, already clipped.
    func _paintRegion(_ canvas: any Canvas, rows rs: [Int], cols cs: [Int], clip: Rect,
                              ws: Worksheet, book: Workbook, merges: [CellRange], covered: Set<CellAddress>, colors: _Colors) {
        let ca = cols, ra = rows
        let p = Paint()
        p.style = .fill
        let editing = printing ? nil : edit?.cell
        let mono = printing && printMono
        // Styled cells, looked up by position: what is on screen, not what is in the sheet.
        var styled: [(CellAddress, CellStyle)] = []
        for row in rs { for col in cs {
            let a = CellAddress(row: row, col: col)
            if let cell = ws.cells[a], cell.style != 0 { styled.append((a, book.style(cell.style))) }
        } }
        // A formatted column's or row's fill, under its cells' own.
        if !ws.colAttrRuns.isEmpty || !ws.rowAttrs.isEmpty {
            for col in cs {
                guard !mono, let st = ws.colStyle(col), let f = book.style(st).fill else { continue }
                p.color = Color(Int64(0xFF00_0000) | Int64(f))
                canvas.drawRect(Rect.fromLTRB(colX(col), clip.top, colX(col) + ca.size(col), clip.bottom), p)
            }
            for row in rs {
                guard !mono, let st = ws.rowStyle(row), let f = book.style(st).fill else { continue }
                p.color = Color(Int64(0xFF00_0000) | Int64(f))
                canvas.drawRect(Rect.fromLTRB(clip.left, rowY(row), clip.right, rowY(row) + ra.size(row)), p)
            }
        }
        // Tables' built-in styles, under everything the cells set themselves.
        var tableLooks: [CellAddress: TableCellLook] = [:]
        if !ws.tables.isEmpty || !ws.pivots.isEmpty, let r0 = rs.first, let r1 = rs.last, let c0 = cs.first, let c1 = cs.last {
            let view = CellRange(top: min(r0, r1), left: min(c0, c1), bottom: max(r0, r1), right: max(c0, c1))
            for pv in ws.pivots where pv.ref.intersects(view) {
                for row in rs where row >= pv.ref.top && row <= pv.ref.bottom {
                    for col in cs where col >= pv.ref.left && col <= pv.ref.right {
                        let a = CellAddress(row: row, col: col)
                        if let look = PivotStyles.look(pv, a, theme: book.themeColors) { tableLooks[a] = look }
                    }
                }
            }
            for t in ws.tables where t.ref.intersects(view) {
                for row in rs where row >= t.ref.top && row <= t.ref.bottom {
                    for col in cs where col >= t.ref.left && col <= t.ref.right {
                        let a = CellAddress(row: row, col: col)
                        if let look = TableStyles.look(t, a, theme: book.themeColors, book: book) { tableLooks[a] = look }
                    }
                }
            }
            if !mono {
                _fillRuns(canvas, p, rs.flatMap { row in cs.compactMap { col in
                    let a = CellAddress(row: row, col: col)
                    return tableLooks[a]?.fill.map { (rect(a), $0) }
                } })
            }
        }
        if !mono {
            _fillRuns(canvas, p, styled.compactMap { a, st in
                guard !covered.contains(a), let f = st.fill else { return nil }
                return (merges.first { $0.topLeft == a }.map { rect($0) } ?? rect(a), f)
            })
        }
        // Conditional formats: fills over the cells' own, bars and fonts below.
        var looks: [CellAddress: CFLook] = [:]
        if let cf = controller.conditionalFormats() {
            for row in rs { for col in cs {
                let a = CellAddress(row: row, col: col)
                if !covered.contains(a), let look = cf.look(a) { looks[a] = look }
            } }
        }
        for (a, look) in looks {
            guard !mono, let f = look.dxf.fill ?? look.fill else { continue }
            p.color = Color(Int64(0xFF00_0000) | Int64(f))
            canvas.drawRect(merges.first { $0.topLeft == a }.map { rect($0) } ?? rect(a), p)
        }
        // Gridlines, then merged areas painted over the lines inside them.
        if colors.showGrid {
            let line = Paint()
            line.style = .stroke
            // (On paper one printer dot, as Excel prints them: 0.12 pt.)
            line.strokeWidth = printing ? 72.0 / 600 : 1
            line.color = colors.grid
            // A text that runs over its neighbours runs over the lines between
            // them too: no gridline is drawn through it.
            var crossed: [Int: Set<Int>] = [:]   // column → the rows whose right edge a text crosses
            let shown = Set(rs)
            for (a, cell) in ws.cells where cell.value.isText && shown.contains(a.row) {
                guard let reach = textReach(a, cell, ws: ws, book: book) else { continue }
                for col in reach.lowerBound ..< reach.upperBound { crossed[col, default: []].insert(a.row) }
            }
            for col in cs {
                let x = printing ? colX(col) + ca.size(col) : (colX(col) + ca.size(col)).rounded() - 0.5
                guard let rows = crossed[col] else {
                    canvas.drawLine(Offset(x, clip.top), Offset(x, clip.bottom), line)
                    continue
                }
                for row in rs where !rows.contains(row) {
                    canvas.drawLine(Offset(x, rowY(row)), Offset(x, rowY(row) + ra.size(row)), line)
                }
            }
            for row in rs {
                let y = printing ? rowY(row) + ra.size(row) : (rowY(row) + ra.size(row)).rounded() - 0.5
                canvas.drawLine(Offset(clip.left, y), Offset(clip.right, y), line)
            }
        }
        for m in merges {
            let r = rect(m)
            let st = book.style(ws.cells[m.topLeft]?.style ?? 0)
            p.color = (mono ? nil : st.fill).map { Color(Int64(0xFF00_0000) | Int64($0)) } ?? colors.paper
            canvas.drawRect(Rect.fromLTRB(r.left + 0.5, r.top + 0.5, r.right - 1, r.bottom - 1), p)
        }
        // Tables' lines, over the gridlines.
        if !tableLooks.isEmpty {
            let line = Paint()
            line.style = .stroke
            line.strokeWidth = printing ? 0.96 : 1
            for (a, look) in tableLooks {
                let r = rect(a)
                // (On paper where the cell's edge is, as cell borders are:
                // a page has no pixels to round to.)
                let l = printing ? r.left : r.left.rounded() - 0.5, rr = printing ? r.right : r.right.rounded() - 0.5
                let t = printing ? r.top : r.top.rounded() - 0.5, b = printing ? r.bottom : r.bottom.rounded() - 0.5
                if let c = look.bottom { line.color = Color(Int64(0xFF00_0000) | Int64(c)); canvas.drawLine(Offset(l, b), Offset(rr, b), line) }
                if let c = look.top { line.color = Color(Int64(0xFF00_0000) | Int64(c)); canvas.drawLine(Offset(l, t), Offset(rr, t), line) }
                if let c = look.left { line.color = Color(Int64(0xFF00_0000) | Int64(c)); canvas.drawLine(Offset(l, t), Offset(l, b), line) }
                if let c = look.right { line.color = Color(Int64(0xFF00_0000) | Int64(c)); canvas.drawLine(Offset(rr, t), Offset(rr, b), line) }
            }
        }
        // Data bars, under the values.
        for (a, look) in looks {
            guard let bar = look.bar else { continue }
            let r = rect(a)
            let inset = 2 * zoom
            p.color = Color(Int64(0xFF00_0000) | Int64(bar.color))
            canvas.drawRect(Rect.fromLTWH(r.left + inset, r.top + inset, max(0, (r.width - 2 * inset) * bar.fraction),
                                          max(0, r.height - 2 * inset - 1)), p)
        }
        // Icon sets, at the cell's left edge.
        for (a, look) in looks {
            guard let icon = look.icon else { continue }
            let r = rect(a)
            let side = min(r.height - 4 * zoom, 12 * zoom)
            guard side > 3 else { continue }
            IconSets.paint(icon.set, icon.index, canvas, in: Rect.fromLTWH(r.left + 3 * zoom, r.center.dy - side / 2, side, side))
        }
        // Values.
        for row in rs { for col in cs {
            let a = CellAddress(row: row, col: col)
            // A dynamic array's spilled value shows in an otherwise empty cell, in that cell's format.
            var spilledCell: Cell? = nil
            if let v = ws.spilled[a], ws.cells[a].map({ $0.value.isEmpty && $0.formula == nil }) ?? true {
                var c = ws.cells[a] ?? Cell(input: "")
                c.value = v
                spilledCell = c
            }
            guard a != editing, !covered.contains(a), let cell = spilledCell ?? ws.cells[a], !cell.value.isEmpty else { continue }
            if let icon = looks[a]?.icon, !icon.showValue { continue }   // "Show Icon Only"
            if cell.value == .number(0), ws.viewAttrs["showZeros"] == "0" { continue }   // the sheet hides zeros
            var cf = looks[a]?.dxf
            if let tl = tableLooks[a] {
                // The table's font where the cell sets none of its own.
                let own = book.style(cell.style)
                var d = cf ?? DxfStyle()
                if d.bold == nil, tl.bold, !own.bold { d.bold = true }
                if d.color == nil, own.color == nil { d.color = tl.color }
                cf = d
            }
            if let m = merges.first(where: { $0.topLeft == a }) {
                _paintCell(canvas, a, cell, in: rect(m), spill: false, ws: ws, book: book, ink: colors.ink, cf: cf)
            } else {
                _paintCell(canvas, a, cell, in: rect(a), spill: true, ws: ws, book: book, ink: colors.ink, cf: cf)
            }
        } }
        // Notes: a red triangle in the cell's top-right corner.
        if !ws.notes.isEmpty && !printing {
            let tri = Paint()
            tri.style = .fill
            tri.color = Color(0xFFD00000)
            let rows = Set(rs), cols = Set(cs)
            for n in ws.notes {
                guard let a = n.at, rows.contains(a.row), cols.contains(a.col) else { continue }
                let r = merges.first { $0.topLeft == a }.map { rect($0) } ?? rect(a)
                let k = 5 * zoom
                let path = Path()
                path.moveTo(r.right - k - 1, r.top)
                path.lineTo(r.right - 1, r.top)
                path.lineTo(r.right - 1, r.top + k)
                path.close()
                canvas.drawPath(path, tri)
            }
        }
        // Merged areas whose top-left is out of this pane still draw their text.
        for m in merges where !(rs.contains(m.top) && cs.contains(m.left)) {
            if let cell = ws.cells[m.topLeft], !cell.value.isEmpty, m.topLeft != editing {
                _paintCell(canvas, m.topLeft, cell, in: rect(m), spill: false, ws: ws, book: book, ink: colors.ink)
            }
        }
        // A long text left of the pane still spills into it — on paper from
        // as far back as a text runs (lo-cell-value's crosses ten pages).
        if let first = cs.first, first > 0 {
            for row in rs {
                var col = first - 1
                while col >= max(0, first - (printing ? 255 : 8)) {
                    let a = CellAddress(row: row, col: col)
                    if let cell = ws.cells[a], !cell.value.isEmpty {
                        if cell.value.isText && !covered.contains(a) {
                            _paintCell(canvas, a, cell, in: rect(a), spill: true, ws: ws, book: book, ink: colors.ink)
                        }
                        break
                    }
                    col -= 1
                }
            }
        }
        // Borders.
        let border = Paint()
        border.style = .stroke
        border.strokeWidth = 1
        border.color = colors.ink
        for (a, st) in styled {
            let b = st.borders
            guard b.top || b.left || b.bottom || b.right else { continue }
            let r = rect(a)
            let l = printing ? r.left : r.left.rounded() - 0.5, rr = printing ? r.right : r.right.rounded() - 0.5
            let t = printing ? r.top : r.top.rounded() - 0.5, bt = printing ? r.bottom : r.bottom.rounded() - 0.5
            /// One side as the file drew it: thicker, doubled, dashed or dotted.
            func line(_ side: String, _ a: Offset, _ z: Offset, inward: Offset) {
                let kind = b.kinds[side] ?? "thin"
                border.color = (printing && printMono ? nil : b.colors[side]).map { Color(Int64(0xFF00_0000) | Int64($0)) } ?? colors.ink
                // (On paper 8, 16 and 24 printer dots, as Excel prints them.)
                border.strokeWidth = (kind == "medium" || kind.hasPrefix("medium") ? 2 : kind == "thick" ? 3 : 1) * (printing ? 0.96 : 1)
                // A hair line is one printer dot on paper, solid (54206's
                // grid of them, 0.12 pt in Excel's print, where ours drew
                // 0.96 at half strength); a faint pixel on a screen.
                if kind == "hair" {
                    if printing { border.strokeWidth = 72.0 / 600 } else { border.color = border.color.withAlpha(140) }
                }
                if kind == "double" {
                    canvas.drawLine(a, z, border)
                    canvas.drawLine(a + inward * 2, z + inward * 2, border)
                    return
                }
                if printing, let pattern = Self._printDashes[kind.hasPrefix("slant") ? "mediumDashDot" : kind] {
                    // On paper Excel's own runs, on and off in printer dots
                    // (lo-cell-borders' lab of every kind, measured at 600 dpi).
                    if kind.hasPrefix("slant") { border.strokeWidth = 2 * 0.96 }
                    let length = (z - a).distance
                    guard length > 0 else { return }
                    let step = (z - a) / length
                    var at = 0.0, i = 0
                    while at < length {
                        let run = pattern[i % pattern.count] * 72 / 600
                        if i % 2 == 0 { canvas.drawLine(a + step * at, a + step * min(length, at + run), border) }
                        at += run; i += 1
                    }
                    return
                }
                if kind.containsSubstring("ash") || kind.containsSubstring("otted") {
                    // Dashes and dots, drawn as short runs along the side.
                    let dash = kind.containsSubstring("otted") ? 1.0 : 3.0, gap = kind.containsSubstring("otted") ? 2.0 : 2.0
                    let length = (z - a).distance
                    guard length > 0 else { return }
                    let step = (z - a) / length
                    var at = 0.0
                    while at < length {
                        canvas.drawLine(a + step * at, a + step * min(length, at + dash), border)
                        at += dash + gap
                    }
                    return
                }
                canvas.drawLine(a, z, border)
            }
            // Inside a merged area there are no cells to rule between: a side
            // draws only where it is the area's own edge.
            let m = merges.isEmpty ? nil : merges.first { $0.contains(a) }
            if b.top, m.map({ $0.top == a.row }) ?? true { line("top", Offset(l, t), Offset(rr, t), inward: Offset(0, 1)) }
            if b.bottom, m.map({ $0.bottom == a.row }) ?? true { line("bottom", Offset(l, bt), Offset(rr, bt), inward: Offset(0, -1)) }
            if b.left, m.map({ $0.left == a.col }) ?? true { line("left", Offset(l, t), Offset(l, bt), inward: Offset(1, 0)) }
            if b.right, m.map({ $0.right == a.col }) ?? true { line("right", Offset(rr, t), Offset(rr, bt), inward: Offset(-1, 0)) }
        }
        // Filter dropdowns: ▾, or a funnel on a column that filters.
        if !printing, let af = ws.autoFilter, rs.contains(af.range.top) {
            for col in cs where col >= af.range.left && col <= af.range.right {
                let b = filterButton(CellAddress(row: af.range.top, col: col))
                guard b.width >= 6 else { continue }
                let box = Rect.fromLTRB(b.left.rounded() + 0.5, b.top.rounded() + 0.5, b.right.rounded() - 0.5, b.bottom.rounded() - 0.5)
                p.color = colors.paper
                canvas.drawRect(box, p)
                border.color = colors.grid.withAlpha(255)
                canvas.drawRect(box, border)
                let cx = box.center.dx, cy = box.center.dy, u = box.width / 16
                let glyph = Path()
                p.color = colors.ink
                if af.columns[col] != nil {
                    // A funnel: a wide triangle over a short stem.
                    glyph.moveTo(cx - 5 * u, cy - 4 * u)
                    glyph.lineTo(cx + 5 * u, cy - 4 * u)
                    glyph.lineTo(cx + 1 * u, cy + 0.5 * u)
                    glyph.lineTo(cx + 1 * u, cy + 4.5 * u)
                    glyph.lineTo(cx - 1 * u, cy + 3.5 * u)
                    glyph.lineTo(cx - 1 * u, cy + 0.5 * u)
                } else {
                    glyph.moveTo(cx - 4 * u, cy - 2 * u)
                    glyph.lineTo(cx + 4 * u, cy - 2 * u)
                    glyph.lineTo(cx, cy + 2.5 * u)
                }
                glyph.close()
                canvas.drawPath(glyph, p)
            }
        }
    }

    /// Excel lays cells out with hinted, whole-pixel glyphs: a Calibri 11
    /// digit is exactly 7 px at 96 dpi, the unit column widths are defined
    /// in. Carlito's unhinted digit is 7.43 px, so text drawn at the
    /// nominal size runs ~6% wider than Excel's and a number that fits
    /// there shows #### here. Cell text is drawn at the size that makes a
    /// digit 7 px.
    static let excelTextScale = 7.0 / 7.43

    /// The text style a cell draws with.
    func _textStyle(_ st: CellStyle, color: UInt32?, ink: Color) -> GridTextStyle {
        let c = printing && printMono ? Int64(0xFF00_0000) : (color ?? st.color).map { Int64(0xFF00_0000) | Int64($0) } ?? Int64(ink.value)
        let book = controller.book
        // (On a page, its printer dots and its face's hinted widths:
        // Arial's and Times' in their clones, which have their advances,
        // and those of the faces Windows draws in their own files — Arial's
        // for a face it has no file for, which it draws in Arial.)
        let dots = printing && printTextScale > 0 ? printTextScale / scale * 600 / 72 : 0
        let face = OfficeFonts.sheetFace(book.fontName(st))
        var hint = ""
        if dots > 0 {
            var name = book.fontName(st).trimmingWhitespace().lowercased()
            if face == "Arial" { name = "arial" }
            let key = name + (st.bold ? " bold" : "") + (st.italic ? " italic" : "")
            if SheetHinting.has(key), name == "arial" || name == "times new roman" || OfficeFonts.sheetFaceIsOwn(name) { hint = key }
        }
        return GridTextStyle(family: face,
                             size: book.fontSize(st) * scale * (printing ? 1 : Self.excelTextScale), bold: st.bold, italic: st.italic,
                             underline: st.underline, strike: st.strike, color: c, dots: dots, hint: hint)
    }

    private func _paintCell(_ canvas: any Canvas, _ a: CellAddress, _ cell: Cell, in r: Rect, spill: Bool,
                            ws: Worksheet, book: Workbook, ink: Color, cf: DxfStyle? = nil) {
        var st = book.style(cell.style)
        if let d = cf {
            // A conditional format's font settings over the cell's own.
            if let v = d.bold { st.bold = v }
            if let v = d.italic { st.italic = v }
            if let v = d.underline { st.underline = v }
            if let v = d.strike { st.strike = v }
            if let v = d.color { st.color = v }
            // (And its number format: lo-new_cond_format_test's top three
            // in 0.00, "2.00" where the rest show "2".)
            if let v = d.numberFormat { st.numberFormat = v }
        }
        let ca = cols
        let left = r.left, right = r.right, top = r.top, bottom = r.bottom
        let width = right - left
        guard width > 2 else { return }
        // How many characters the cell holds, which a General number is
        // rounded to: its width in the default font's digits, less the
        // column's padding — on paper the printer's digits (lo-Sparklines'
        // 8.43-character columns print 3.337809 and -6.10523, eight
        // characters, where the screen's 7 px a digit made room for nine).
        let chars: Int
        if printing {
            let m = SheetPrintMetrics.of(family: book.defaultFontName ?? OfficeFonts.defaultFamily, size: book.defaultFontSize ?? 11, bold: book.defaultFontBold)
            let padding = (2 * (m.screenDigit / 4).rounded(.up) + 1) / m.screenDigit
            chars = max(1, Int(width / m.digit - padding + 1e-6))
        } else {
            chars = max(1, Int(width / (7 * zoom)))
        }
        var (text, color) = NumberFormat.display(cell.value, st.numberFormat, width: chars, pads: true)
        if cell.value.isText { text = Self.shown(text) }
        let style = _textStyle(st, color: color, ink: ink)
        // Pads before the text (`_W0`, Accounting's `_(@_)`) are a gap of
        // their characters' width ahead of it. (Spaced out as `_TextCache`
        // spaces the rest, the text after them was drawn half the spacing
        // late: the pad lab's `_W0` stood 3.6 pt right of Excel's.)
        var lead = 0.0
        while text.first == NumberFormat.padMark, let x = text.dropFirst().first {
            lead += texts.painter(String(x), style).width
            text = String(text.dropFirst(2))
        }
        if st.rotation == 90 || st.rotation == 180 {
            _paintTurned(canvas, text, style, st, up: st.rotation == 90, in: r, book: book)
            return
        }
        var align = st.hAlign
        if align == .general {
            switch cell.value {
            // (A number in a cell formatted Text stands at the left, as its
            // text would: lo-tdf153767's postal codes.)
            case .number: align = NumberFormat.isText(st.numberFormat) ? .left : .right
            case .bool, .error: align = .center
            default: align = .left
            }
        }
        let pad = 2 * zoom   // Excel's cell margin
        // Wrapped text: lines within the cell's width, never spilling.
        let wraps = st.wrap && cell.value.isText
        let lineAlign: TextAlign = align == .center ? .center : align == .right ? .right : .left
        var tp = texts.painter(text, style, maxWidth: wraps ? max(1, width - pad * 2) : .infinity, align: wraps ? lineAlign : .left)
        // A number too wide for its cell is ####, never cut.
        if case .number = cell.value, lead + tp.width > width - pad * 2 {
            let hashes = max(1, Int((width - pad * 2) / max(1, texts.painter("#", style).width)))
            text = String(repeating: "#", count: hashes)
            color = nil
            lead = 0
            tp = texts.painter(text, style)
        }
        // An indent: so many three-space steps of the workbook's default
        // font, in from the side the text is aligned to (a lab of indents 1-4
        // in Calibri 11, Arial 10 and Times 9: 7.56, 8.28 and 6.84 pt a step).
        var inset = 0.0
        if st.indent > 0, st.hAlign == .left || st.hAlign == .right {
            let base = _textStyle(book.style(0), color: nil, ink: ink)
            inset = Double(st.indent) * max(0, texts.painter("X   X", base).width - texts.painter("XX", base).width)
        }
        // Text spills over empty neighbours, as far as it reaches from its
        // indent (chart-tdf140489's "Deferred Tax", in two steps from A1's
        // edge, was cut at the last column its width alone needed).
        var clipLeft = left, clipRight = right
        if spill && cell.value.isText && tp.width > width - pad * 2 && !wraps {
            if align == .left || align == .general {
                var col = a.col + 1
                while col < CellAddress.maxCols, ws.cells[CellAddress(row: a.row, col: col)]?.value.isEmpty ?? true,
                      clipRight - left < tp.width + pad * 2 + inset, col <= a.col + (printing ? 255 : 30) {
                    clipRight += ca.size(col); col += 1
                }
            } else if align == .right {
                var col = a.col - 1
                while col >= 0, ws.cells[CellAddress(row: a.row, col: col)]?.value.isEmpty ?? true,
                      right - clipLeft < tp.width + pad * 2 + inset {
                    clipLeft -= ca.size(col); col -= 1
                }
            } else if align == .center {
                // Centred, half of what it lacks to each side, as far as
                // that side's neighbours are empty (lo-tdf171828's I14 runs
                // over H and J).
                let side = (tp.width + pad * 2 - width) / 2
                var col = a.col - 1
                while col >= 0, left - clipLeft < side, ws.cells[CellAddress(row: a.row, col: col)]?.value.isEmpty ?? true {
                    clipLeft -= ca.size(col); col -= 1
                }
                col = a.col + 1
                while col < CellAddress.maxCols, col <= a.col + (printing ? 255 : 30), clipRight - right < side,
                      ws.cells[CellAddress(row: a.row, col: col)]?.value.isEmpty ?? true {
                    clipRight += ca.size(col); col += 1
                }
            }
        }
        // On paper the text stands in from its side half a point and a
        // quarter of its font's digit (the gridline lab, Excel 16: five
        // faces at ten sizes, 1.50 pt for Calibri 8 to 4.26 for Verdana 24,
        // within a printer dot), where ours stood a flat 1.5. (Wrapping
        // keeps the cell's margin `pad`: its widths are Excel's.) The
        // right side the same: a lab of right-aligned 3750 had measured it
        // 0.34 to 0.43 under the left, against cells that stood 0.48 left
        // of Excel's (SheetPrint's inset) — with the cells in place,
        // bug62181's right-aligned numbers stood 0.45 right of Excel's.
        let margin = printing
            ? 0.48 + SheetPrintMetrics.of(family: book.fontName(st), size: book.fontSize(st), bold: st.bold).digit / 4
            : pad
        let rightMargin = margin
        // And centred text four printer dots right of the middle: 0.45 pt
        // on the median in Excel's prints of 56 workbooks, merged or not, at
        // page scales 53% to 100% alike, and of a General TRUE or #N/A in 27
        // of 30. (lo-ceiling-floor's stood in the middle — and its
        // right-aligned numbers 0.33 right of Excel's: its columns, open.)
        let centre = printing && printTextScale > 0 ? 4 * 72 / 600 * scale / printTextScale : 0
        let tx: Double
        switch align {
        case .right: tx = right - rightMargin - inset - tp.width
        case .center: tx = left + (width - lead - tp.width) / 2 + lead + centre
        default: tx = left + margin + inset + lead
        }
        // On paper a merged area centres its text four printer dots higher
        // than a lone cell does: Tables' "PRSI Liability" over its "GROSS",
        // simple-monthly-budget's "Balance", style-alternate-content's
        // labels, 0.48 pt in Excel's prints at 80% and at 100%. (A merge
        // set at its foot stands where a lone cell's text does.)
        let lift = printing && !spill && printTextScale > 0 ? 4 * 72 / 600 * scale / printTextScale : 0
        let ty: Double
        switch st.vAlign {
        case .top: ty = printing ? _printTop(st, book, ws, row: a.row, tp, top: top, bottom: bottom, .top) : top + 1
        case .center: ty = (printing ? _printTop(st, book, ws, row: a.row, tp, top: top, bottom: bottom, .center) : top + (bottom - top - tp.height) / 2) - lift
        case .bottom: ty = printing ? _footTop(st, book, ws, row: a.row, tp, bottom: bottom) : bottom - tp.height - 1
        }
        canvas.save()
        canvas.clipRect(Rect.fromLTRB(clipLeft + 1, top, clipRight - 1, bottom))
        // (Whole pixels on a screen; on paper a page has no pixels, and a
        // row's rounding would show as uneven lines of text.)
        func at(_ x: Double) -> Offset { printing ? Offset(x, ty) : Offset(x.rounded(), ty.rounded()) }
        // A format that fills its cell (`*x`) spans it, whatever the
        // alignment: what is before the fill at the left, what is after it
        // at the right, the character repeated between — Accounting's "$"
        // at the cell's left edge and its number at the right, where ours
        // were side by side (LIBRE_OFFICE-128382-0).
        if !wraps, tp.width <= width - pad * 2, let parts = NumberFormat.fillParts(cell.value, st.numberFormat, width: chars, pads: true) {
            let lp = texts.painter(parts.left, style), rp = texts.painter(parts.right, style)
            let x0 = left + margin + lp.width, x1 = right - rightMargin - rp.width
            if parts.fill != " ", x1 > x0 {
                let one = texts.painter(String(parts.fill), style).width
                if one > 0 {
                    let fp = texts.painter(String(repeating: String(parts.fill), count: Int((x1 - x0) / one)), style)
                    fp.paint(canvas, at(x1 - fp.width))
                }
            }
            lp.paint(canvas, at(left + margin))
            rp.paint(canvas, at(x1))
            canvas.restore()
            return
        }
        // Wrapped lines on paper are their font's fitted line apart, the
        // line a row of it is fitted to, not the face's own: Arial 10's
        // 12.36 pt (lo-tdf159581_optimalRowHeight, ours 11.0), Calibri
        // 11's 14.52 (52716, ours 13.0), in Excel's prints of 26
        // workbooks. The line the alignment holds — the last at the foot,
        // the first at the head, the middle in the centre — stands where
        // one line would (52716's last lines with their rows' numbers).
        if printing && wraps {
            let lines = texts._breakLines(NumberFormat.unpad(text), style, max(1, width - pad * 2))
                .split(separator: "\n", omittingEmptySubsequences: false)
            if lines.count > 1 {
                let m = SheetPrintMetrics.of(family: book.defaultFontName ?? OfficeFonts.defaultFamily, size: book.defaultFontSize ?? 11, bold: book.defaultFontBold)
                let pitch = Self._fittedLine(st, m, book) * scale
                let one = texts.painter("X", style).height, n = Double(lines.count - 1)
                let y0: Double
                switch st.vAlign {
                case .top: y0 = _printTop(st, book, ws, row: a.row, texts.painter("X", style), top: top, bottom: bottom, .top)
                case .center: y0 = _printTop(st, book, ws, row: a.row, texts.painter("X", style), top: top, bottom: bottom, .center) - n / 2 * pitch - lift
                case .bottom: y0 = _footTop(st, book, ws, row: a.row, texts.painter("X", style), bottom: bottom) - n * pitch
                }
                for (i, line) in lines.enumerated() {
                    let lp = texts.painter(String(line), style)
                    let x: Double
                    switch align {
                    case .right: x = right - rightMargin - inset - lp.width
                    case .center: x = left + (width - lead - lp.width) / 2 + lead + centre
                    default: x = left + margin + inset + lead
                    }
                    lp.paint(canvas, Offset(x, y0 + Double(i) * pitch))
                }
                canvas.restore()
                return
            }
        }
        // A rich string on one line: run by run, each in its own font, on
        // the line's baseline. A raised or lowered run is two thirds of its
        // size, raised half its em — 45540_classic_Header's "Number of
        // Hires⁽¹⁾", Arial Bold 10 at 90%: 6.0 pt on the page, 37 dots of 75
        // up. (Lowered: its face's 0.14 em, not yet seen in a print.) A cell
        // whose font is raised is one such run, and so is a run with no font
        // of its own in it (the same workbook's "⁽¹⁾  Eleven students…").
        let runs: [RichRun]? = {
            if let r = ws.richText[a], case .text(let raw) = cell.value, raw == text, r.map(\.text).joined() == text { return r }
            return st.script != 0 ? [RichRun(text: text)] : nil
        }()
        if let runs, lead == 0, !text.isEmpty, !text.containsSubstring("\n") {
            let plain = texts.painter(text, style)
            if !wraps || plain.width <= width - pad * 2 {
                let line: Double
                switch lineAlign {
                case .center: line = tx + (tp.width - plain.width) / 2
                case .right: line = tx + tp.width - plain.width
                default: line = tx
                }
                let base = ty + plain.computeDistanceToActualBaseline(.alphabetic)
                let parts = runs.map { run -> (TextPainter, Double) in
                    var rs = st
                    if run.bold != nil {
                        rs.bold = run.bold ?? false; rs.italic = run.italic ?? false
                        rs.underline = run.underline ?? false; rs.strike = run.strike ?? false
                    }
                    if let f = run.fontName { rs.fontName = f }
                    if let z = run.size { rs.fontSize = z }
                    if let c = run.color { rs.color = c }
                    var s = _textStyle(rs, color: color, ink: ink)
                    let em = s.size, script = run.bold == nil ? st.script : run.script
                    if script != 0 { s.size = em * 2 / 3 }
                    let rp = texts.painter(run.text, s)
                    let shift = script > 0 ? em / 2 : script < 0 ? -em * 0.14 : 0
                    return (rp, base - rp.computeDistanceToActualBaseline(.alphabetic) - shift)
                }
                let total = parts.reduce(0) { $0 + $1.0.width }
                var x: Double
                switch align {
                case .center: x = line + (plain.width - total) / 2
                case .right: x = line + plain.width - total
                default: x = line
                }
                for (rp, y) in parts {
                    rp.paint(canvas, printing ? Offset(x, y) : Offset(x.rounded(), y.rounded()))
                    x += rp.width
                }
                canvas.restore()
                return
            }
        }
        tp.paint(canvas, at(tx))
        canvas.restore()
    }

    /// A cell's font's line on paper, in points: the row Excel fits to
    /// it in this workbook (`m`, the metrics of its default font).
    /// (Bold counts where the face's bold has a line of its own, though the
    /// style names neither face nor size: FormulaSheetRange's bold Arial 10
    /// labels fit its rows at 35 screen pixels, 12.72 pt, not Arial's 12.36.)
    static func _fittedLine(_ st: CellStyle, _ m: SheetPrintMetrics, _ book: Workbook) -> Double {
        st.fontName == nil && st.fontSize == nil && st.bold == book.defaultFontBold ? m.defaultRow
            : m.fittedRow(SheetPrintMetrics.of(family: book.fontName(st), size: book.fontSize(st), bold: st.bold))
    }

    /// On paper, where a line of text set at a cell's foot has its top:
    /// Excel stands it in a box its font's fitted line high, the baseline
    /// that face's ascent down from the box's head and the box on the
    /// foot — or the box of the font the row's empty cells take, where
    /// that is the taller below its baseline: the row's style, else their
    /// columns', else the default font (as a row is fitted). So the
    /// baseline is no part of the face's own descent: in the baseline lab
    /// (Excel 16, set rows of 20 and 30 pt) it stood 4.02 above the foot
    /// for every face of 8 to 11 pt in a Calibri 11 book (Calibri 12:
    /// 4.5, 14: 4.98, 18: 6.3), and 3.42, 3.18, 3.06 and 2.82 in books of
    /// Calibri 9, Arial 10, Verdana 10 and Microsoft Sans Serif 8.25 —
    /// fitted line less ascent, to within 0.15 — where ours stood its
    /// descent and a pixel above it, 3.0 for most faces of 8 to 10 pt,
    /// 2.0 for Microsoft Sans Serif. bug62181's Arial 9, in rows styled
    /// Arial 9 in an Arial 10 book, stand at Arial 9's 3.1, not 3.31.
    func _footTop(_ st: CellStyle, _ book: Workbook, _ ws: Worksheet, row: Int, _ tp: TextPainter, bottom: Double) -> Double {
        _printTop(st, book, ws, row: row, tp, top: bottom, bottom: bottom, .bottom)
    }

    /// Where a line of text has its top on paper, by the vertical
    /// alignment, from the same box as `_footTop`'s (the fitted line, the
    /// baseline K over its foot). Set at the head, the box stands four
    /// printer dots under the row's top; centred, four dots under the
    /// middle: in the alignment lab (Arial 10, Calibri 11 and 9,
    /// Microsoft Sans Serif 8.25 books; rows of 30, 20 and their fit) a
    /// head's baseline stood F − K + 0.48 under the row's top and a
    /// centre's (H − F)/2 + F − K + 0.48, all to within 0.06 — where ours
    /// stood a point and the rounded ascent down, up to 1 pt low.
    func _printTop(_ st: CellStyle, _ book: Workbook, _ ws: Worksheet, row: Int, _ tp: TextPainter,
                   top: Double, bottom: Double, _ align: CellStyle.VAlign) -> Double {
        let m = SheetPrintMetrics.of(family: book.defaultFontName ?? OfficeFonts.defaultFamily, size: book.defaultFontSize ?? 11, bold: book.defaultFontBold)
        // A style's fitted line less its face's ascent, the ascent taken up
        // to whole dots of the printer's 600 dpi: the face's own ascent
        // where it is known, the painter's where not. (Uncut, the corpus's
        // Calibri 11 text stood 0.11 high in Excel's prints of 118
        // workbooks and its Arial 10 0.15 high in 40; cut, 3.96 and 3.24.)
        // (And the ascent so cut: the box's part over its baseline.)
        func box(_ s: CellStyle, _ p: @autoclosure () -> TextPainter) -> (below: Double, above: Double) {
            let a = SheetPrintMetrics.ascent(family: book.fontName(s)).map { $0 * book.fontSize(s) }
                ?? p().computeDistanceToActualBaseline(.alphabetic) / scale
            let up = (a * 600 / 72).rounded(.up) * 72 / 600
            return ((Self._fittedLine(s, m, book) - up) * scale, up * scale)
        }
        func box(_ style: Int) -> (below: Double, above: Double) {
            let s = book.style(style)
            return box(s, texts.painter("X", _textStyle(s, color: nil, ink: Color(0xFF00_0000))))
        }
        func most(_ a: (below: Double, above: Double), _ b: (below: Double, above: Double)) -> (below: Double, above: Double) {
            (max(a.below, b.below), max(a.above, b.above))
        }
        var empty: (below: Double, above: Double)
        if let rs = ws.rowStyle(row) {
            empty = box(rs)
        } else {
            empty = (-.infinity, -.infinity)
            var covered = 0, next = 0
            for run in ws.colAttrRuns.filter({ $0.attrs["style"] != nil }).sorted(by: { $0.lo < $1.lo }) {
                empty = most(empty, box(Int(run.attrs["style"] ?? "") ?? 0))
                let lo = max(run.lo, next)
                if run.hi >= lo { covered += run.hi - lo + 1; next = run.hi + 1 }
            }
            if covered < CellAddress.maxCols { empty = most(empty, box(0)) }
        }
        let own = box(st, tp), k = most(own, empty).below
        let dots4 = 4 * 72 / 600 * scale / (printTextScale > 0 ? printTextScale : 1)
        let baseline: Double
        switch align {
        // (A head's box is the cell's own: a Lucida Sans Typewriter cell set
        // at its head stands 10.02 under the top in a Verdana book, with or
        // without Verdana beside it, where Verdana's stand 10.38.)
        case .top: baseline = top + dots4 + own.above
        // A middle is the font's own: its ascent and descent (Windows'),
        // each up to whole dots, about the middle — whatever the row's
        // other fonts or the book's. Calibri 11 centred in a row of Calibri
        // 30, by row style, column style or an empty cell, stands where it
        // does alone in Excel's print; Calibri 8, 14 and 20, Arial 8,
        // Verdana 10 and Lucida Sans Typewriter 10, in Calibri 11 and
        // Verdana 10 books, as the default fonts of four books, stand
        // within 0.07 of that less 0.06 (labs of 39, 30 and 20 pt rows,
        // Excel 16 at 100%, 2026-10-27; the corpus's references, at 200%,
        // put Calibri 11 at 3.78, Arial 10 at 3.48, as so rounded).
        // FillWithoutColor's centred notice, in a row styled Calibri 30,
        // stood 6 pt low by the row's box.
        case .center:
            let size = book.fontSize(st)
            if let a = SheetPrintMetrics.ascent(family: book.fontName(st)), let d = SheetPrintMetrics.descent(family: book.fontName(st)) {
                func dots(_ v: Double) -> Double { (v * size * 600 / 72 - 1e-6).rounded(.up) * 72 / 600 }
                baseline = (top + bottom) / 2 + (dots(a) - dots(d)) / 2 * scale
            } else {
                baseline = (top + bottom) / 2 + (own.above - own.below) / 2 + dots4
            }
        case .bottom: baseline = bottom - k
        }
        // (The painter draws its baseline its ascent down to the whole
        // point, 10 for Calibri 11's 10.47, whatever it reports.)
        return baseline - tp.computeDistanceToActualBaseline(.alphabetic).rounded()
    }

    /// Text turned a quarter: up (`textRotation` 90, read from the foot)
    /// or down (180, from the head). It is laid out as level text in the
    /// cell turned on its side: its lines run along the cell's height,
    /// placed along it by the vertical alignment, and the horizontal
    /// alignment stacks them across. lo-tdf119292's A1, left and wrapped,
    /// goes up from the foot at the left; its C1, right and top, down from
    /// the head at the right; both are cut at the far side, a line and a
    /// half each. General text stands at its foot side (47737's headings,
    /// at the right).
    private func _paintTurned(_ canvas: any Canvas, _ text: String, _ style: GridTextStyle, _ st: CellStyle,
                              up: Bool, in r: Rect, book: Workbook) {
        guard !text.isEmpty else { return }
        let pad = 2 * zoom
        let long = r.height, across = r.width
        let along: TextAlign
        switch st.vAlign {
        case .center: along = .center
        case .bottom: along = up ? .left : .right
        case .top: along = up ? .right : .left
        }
        // (Wrapped a little shorter than level text: LIBRE_OFFICE-128382-0's
        // 72.6 pt merge wraps "and a vertical", 67.2 pt, and not
        // "(B15:E19) and", 69.4.)
        let broken = st.wrap ? texts._breakLines(NumberFormat.unpad(text), style, max(1, long - pad * 2 - 1.25 * scale)) : text
        let lines = broken.split(separator: "\n", omittingEmptySubsequences: false).map { texts.painter(String($0), style) }
        // Each line its font's fitted line on paper, as Excel spaces them
        // (15.6 pt for 128382's Calibri Bold 12, where a layout's is 13).
        let one = lines.first?.height ?? 0
        let pitch: Double
        if printing {
            let book = controller.book
            let m = SheetPrintMetrics.of(family: book.defaultFontName ?? OfficeFonts.defaultFamily, size: book.defaultFontSize ?? 11, bold: book.defaultFontBold)
            pitch = max(one, m.fittedRow(SheetPrintMetrics.of(family: book.fontName(st), size: book.fontSize(st), bold: st.bold)) * scale)
        } else {
            pitch = one
        }
        let margin = printing
            ? 0.48 + SheetPrintMetrics.of(family: book.fontName(st), size: book.fontSize(st), bold: st.bold).digit / 4
            : pad
        // Across: the side the glyphs' tops face (the left going up, the
        // right going down) is the turned cell's head.
        let thick = Double(lines.count) * pitch
        let y0: Double
        switch st.hAlign {
        case .center: y0 = (across - thick) / 2
        case .left where up, .right where !up: y0 = 1
        default: y0 = across - thick - 1
        }
        canvas.save()
        canvas.clipRect(r)
        if up {
            canvas.translate(r.left, r.bottom)
            canvas.rotate(-.pi / 2)
        } else {
            canvas.translate(r.right, r.top)
            canvas.rotate(.pi / 2)
        }
        for (i, tp) in lines.enumerated() {
            let x: Double
            switch along {
            case .center: x = (long - tp.width) / 2
            case .right: x = long - margin - tp.width
            default: x = margin
            }
            // (A line stands at the foot of its pitch.)
            tp.paint(canvas, Offset(x, y0 + Double(i + 1) * pitch - tp.height))
        }
        canvas.restore()
    }

    /// What a cell shows of its text: the first 1,024 characters, as
    /// Excel's grid does (the formula bar has the rest). lo-cell-value's
    /// 2,472 run over ten printed pages to the 1,024th and stop there.
    static func shown(_ text: String) -> String {
        text.count > 1024 ? String(text.prefix(1024)) : text
    }

    /// A dashed or dotted border's runs on paper, on and off, in printer
    /// dots from the side's start: dotted 4 and 4, dashed 24 and 8, a
    /// dash 72, a dot 24 and the gaps 24 (lo-cell-borders in Excel's print).
    static let _printDashes: [String: [Double]] = [
        "dotted": [4, 4], "dashed": [24, 8], "dashDot": [24, 24, 72, 24], "dashDotDot": [24, 24, 72, 24, 24, 24],
        "mediumDashed": [72, 24], "mediumDashDot": [24, 24, 72, 24], "mediumDashDotDot": [24, 24, 72, 24, 24, 24],
    ]

    /// The columns a text too long for its cell runs over, as `_paintCell`
    /// lets it: empty neighbours to the right of left-aligned text, to the
    /// left of right-aligned, to both sides of centred. Nil when it stays
    /// in its own cell.
    func textReach(_ a: CellAddress, _ cell: Cell, ws: Worksheet, book: Workbook) -> ClosedRange<Int>? {
        guard case .text(let raw) = cell.value else { return nil }
        let st = book.style(cell.style)
        let ca = cols
        let width = ca.size(a.col)
        // (Cheaply first: no glyph is half as wide again as its size, so a
        // text that short fits. This was a fifth — the narrowest a glyph is,
        // the wrong bound — and let only text five times too long run over:
        // NumberFormatTests' "Improper Fractions" in column D printed no
        // column E, where Excel prints five pages of it.)
        guard width > 0, !st.wrap, st.rotation != 90, st.rotation != 180, Double(raw.count) * book.fontSize(st) * scale * 1.5 > width else { return nil }
        if ws.merges.contains(where: { $0.contains(a) }) { return nil }
        let text = Self.shown(NumberFormat.display(cell.value, st.numberFormat, width: 255).text)
        var need = texts.painter(text, _textStyle(st, color: nil, ink: Color(0xFF00_0000))).width + 4 * zoom
        if st.indent > 0, st.hAlign == .left || st.hAlign == .right {
            let base = _textStyle(book.style(0), color: nil, ink: Color(0xFF00_0000))
            need += Double(st.indent) * max(0, texts.painter("X   X", base).width - texts.painter("XX", base).width)
        }
        guard need > width else { return nil }
        var have = width, lo = a.col, hi = a.col
        if st.hAlign == .center {
            let side = (need - width) / 2
            var l = 0.0, r = 0.0
            while lo > 0, l < side, ws.cells[CellAddress(row: a.row, col: lo - 1)]?.value.isEmpty ?? true {
                lo -= 1; l += ca.size(lo)
            }
            while hi < CellAddress.maxCols - 1, hi < a.col + 255, r < side,
                  ws.cells[CellAddress(row: a.row, col: hi + 1)]?.value.isEmpty ?? true {
                hi += 1; r += ca.size(hi)
            }
        } else if st.hAlign == .right {
            while lo > 0, have < need, ws.cells[CellAddress(row: a.row, col: lo - 1)]?.value.isEmpty ?? true {
                lo -= 1; have += ca.size(lo)
            }
        } else {
            while hi < CellAddress.maxCols - 1, hi < a.col + 255, have < need,
                  ws.cells[CellAddress(row: a.row, col: hi + 1)]?.value.isEmpty ?? true {
                hi += 1; have += ca.size(hi)
            }
        }
        return lo == hi ? nil : lo ... hi
    }

    private func _paintEditor(_ canvas: any Canvas, _ e: CellEdit, ink: Color, paper: Color, accent: Color, size: Size) {
        let r = rect(e.cell)
        let st = controller.style(at: e.cell)
        var style = _textStyle(st, color: nil, ink: ink)
        if e.text.first == "=" { style.family = OfficeFonts.drawn("Calibri") }
        let text = String(e.text)
        let tp = texts.painter(text.isEmpty ? " " : text, style)
        let pad = 2 * zoom
        // The editor grows to the right to show what is typed, as Excel's does.
        let w = max(r.width, min(size.width - r.left - 2, tp.width + pad * 2 + 4))
        let box = Rect.fromLTWH(r.left, r.top, w, r.height)
        let p = Paint()
        p.style = .fill
        p.color = paper
        canvas.drawRect(box, p)
        let frame = Paint()
        frame.style = .stroke
        frame.strokeWidth = 2
        frame.color = accent
        canvas.drawRect(Rect.fromLTRB(box.left.rounded(), box.top.rounded(), box.right.rounded() - 1, box.bottom.rounded() - 1), frame)
        let ty = box.bottom - tp.height - 1
        canvas.save()
        canvas.clipRect(box.deflate(1))
        if !text.isEmpty { tp.paint(canvas, Offset(box.left + pad, ty.rounded())) }
        // The input method's marked text, underlined.
        if let c = _composing, c.upperBound <= e.text.count, c.lowerBound < c.upperBound {
            let x0 = c.lowerBound == 0 ? 0 : texts.painter(String(e.text[0 ..< c.lowerBound]), style).width
            let x1 = texts.painter(String(e.text[0 ..< c.upperBound]), style).width
            p.color = ink
            canvas.drawRect(Rect.fromLTWH(box.left + pad + x0, ty + tp.height - 1, x1 - x0, 1), p)
        }
        // The caret.
        let before = e.caret == 0 ? 0 : texts.painter(String(e.text[0 ..< e.caret]), style).width
        p.color = ink
        canvas.drawRect(Rect.fromLTWH((box.left + pad + before).rounded(), ty + 1, 1.5, max(1, tp.height - 2)), p)
        canvas.restore()
        // Where the caret is, for the input method's candidate window.
        if let ime = _ime, ime.isAttached, let rb = _box ?? (context?.findRenderObject() as? RenderBox) {
            ime.setCaretRect(Rect.fromLTWH(box.left + pad + before, ty, 1.5, tp.height),
                             editableSize: size, transform: rb.getTransformTo(nil as RenderObject?))
        }
    }
}

private final class _GridPainter: CustomPainter {
    unowned let state: SheetGridState
    var fluent: FluentThemeData? = nil

    init(state: SheetGridState, repaint: any Listenable) {
        self.state = state
        super.init(repaint: repaint)
    }

    override func paint(_ canvas: any Canvas, _ size: Size) {
        state.paint(canvas, size, fluent: fluent)
    }

    override func shouldRepaint(_ oldDelegate: CustomPainter) -> Bool { true }
}

/// A cell's font, hashable, so laid-out text can be cached by it.
struct GridTextStyle: Hashable {
    var family: String
    var size: Double
    var bold = false
    var italic = false
    var underline = false
    var strike = false
    var color: Int64
    /// On a page, the printer's dots in a unit of its layout; 0 on a
    /// screen. Excel prints a font a whole number of 600-dpi dots an em
    /// (Calibri 11 at 11.04 pt, 92 dots; Arial and Times 10 at 9.96, 83)
    /// and each character a whole number of dots on from the last: Lucida
    /// Sans Typewriter 10 steps 50 dots, its 0.6 em of 83 being 49.8, and
    /// Verdana's digits 53 (52.77). `_TextCache` sets each character so.
    var dots = 0.0
    /// The face whose hinted widths it is set to (`SheetHinting`), where
    /// what draws it has that face's advances; "" for none.
    var hint = ""

    var flutter: Flutter.TextStyle {
        var decorations: [TextDecoration] = []
        if underline { decorations.append(.underline) }
        if strike { decorations.append(.lineThrough) }
        // Unkerned, as Excel sets a cell: kerned, Calibri's "UPDATE" fit
        // a line of CVLKRA's Remarks column that Excel's (36.3 pt, the
        // column less 3) is 0.3 pt too narrow for, and wraps as "UPDAT".
        // And letter by letter: Excel draws no ligature, where Carlito
        // joined lo-forum-mso-de-104083's "Werkauftrag" at "ft" and
        // "Position" at "ti".
        return Flutter.TextStyle(color: Color(color), fontSize: size,
                                 fontWeight: bold ? .bold : .normal, fontStyle: italic ? .italic : .normal,
                                 fontFeatures: [FontFeature("kern", 0), FontFeature("liga", 0), FontFeature("clig", 0)],
                                 decoration: decorations.isEmpty ? TextDecoration.none : TextDecoration.combine(decorations),
                                 fontFamily: family)
    }
}

/// Laid-out text for the grid, kept across frames: a screen of cells
/// repaints on every scroll, and laying out the same strings again each
/// time is most of the cost. Evicted wholesale when it grows large.
final class _TextCache {
    private struct Key: Hashable {
        let text: String
        let style: GridTextStyle
        let width: Int   // the wrap width in whole pixels; -1 for none
        let align: TextAlign
    }
    private var _cache: [Key: TextPainter] = [:]

    /// `align` matters only to wrapped text: it is how its lines sit
    /// against each other inside the paragraph.
    func painter(_ text: String, _ style: GridTextStyle, maxWidth: Double = .infinity, align: TextAlign = .left) -> TextPainter {
        let k = Key(text: text, style: style, width: maxWidth.isFinite ? Int(maxWidth) : -1, align: align)
        if let tp = _cache[k] { return tp }
        if _cache.count > 4000 { clear() }
        let lines = maxWidth.isFinite ? _breakLines(NumberFormat.unpad(text), style, maxWidth) : text
        let tp = TextPainter(text: _span(lines, style), textAlign: align, textDirection: .ltr)
        tp.layout(minWidth: 0, maxWidth: maxWidth)
        _cache[k] = tp
        return tp
    }

    /// The text as one span, or as runs where a format pads it (`_x`, as
    /// `NumberFormat` marks it): each pad a space spaced out to x's width,
    /// blank on the page and nothing in its text but the space.
    private func _span(_ text: String, _ style: GridTextStyle) -> TextSpan {
        guard text.contains(NumberFormat.padMark) else {
            return _spaces(text, style) ? TextSpan(children: _spaced(text, style)) : TextSpan(text: text, style: style.flutter)
        }
        // (A lone space measures as its advance only between letters.)
        let space = _measure("a a", style) - _measure("aa", style)
        var spans: [InlineSpan] = [], run = "", padding = false
        for ch in text {
            if padding {
                if !run.isEmpty { spans += _spaced(run, style); run = "" }
                spans.append(TextSpan(text: " ", style: style.flutter.copyWith(letterSpacing: _width(String(ch), style) - space)))
                padding = false
            } else if ch == NumberFormat.padMark {
                padding = true
            } else {
                run.append(ch)
            }
        }
        if !run.isEmpty { spans += _spaced(run, style) }
        return TextSpan(children: spans)
    }

    /// The face's own widths, where its stand-in has other ones: Verdana's,
    /// drawn in DejaVu Sans (a few per cent wider in its letters, narrower
    /// in its space — the format tests' lines ran past Excel's), in ems.
    private func _own(_ ch: Character, _ style: GridTextStyle) -> Double? {
        guard style.family == OfficeFonts.verdana, ch.unicodeScalars.count == 1, let v = ch.unicodeScalars.first?.value else { return nil }
        if v >= 0x20, v <= 0x7E { return (style.bold ? OfficeFonts.verdanaBoldAdvances : OfficeFonts.verdanaAdvances)[Int(v - 0x20)] }
        return (style.bold ? OfficeFonts.verdanaBoldOtherAdvances : OfficeFonts.verdanaOtherAdvances)[v]
    }
    /// Whether `run` is set character by character: in a face with its
    /// own widths, or on a page (`GridTextStyle.dots`) — save where its
    /// script joins or stacks its letters, which only the whole run shapes.
    private func _spaces(_ run: String, _ style: GridTextStyle) -> Bool {
        guard style.family == OfficeFonts.verdana || style.dots > 0 else { return false }
        return !run.unicodeScalars.contains { v in
            let x = v.value
            return (0x0300 ... 0x036F).contains(x) || (0x0590 ... 0x0DFF).contains(x) || (0x0E00 ... 0x0FFF).contains(x)
                || (0x1000 ... 0x109F).contains(x) || (0x1780 ... 0x17FF).contains(x) || (0x200C ... 0x200F).contains(x)
                || (0xFB1D ... 0xFDFF).contains(x) || (0xFE70 ... 0xFEFF).contains(x)
        }
    }

    /// One character's advance as set: its face's own, or the stand-in's
    /// (`natural`); on a page, at the font's whole dots an em, to the
    /// whole dot, or its face's hinted width there.
    private func _advance(_ ch: Character, _ natural: Double, _ style: GridTextStyle) -> Double {
        let a = _own(ch, style).map { $0 * style.size } ?? natural
        guard style.dots > 0, style.size > 0 else { return a }
        let em = (style.size * style.dots).rounded()
        let hinted = style.hint.isEmpty ? 0 : SheetHinting.departure(style.hint, em: Int(em), ch)
        return ((a / style.size * em).rounded() + Double(hinted)) / style.dots
    }

    /// A run as spans, each character spaced out (or in) to its advance.
    private func _spaced(_ run: String, _ style: GridTextStyle) -> [InlineSpan] {
        guard _spaces(run, style) else { return [TextSpan(text: run, style: style.flutter)] }
        // (A lone space measures as its advance only between letters.)
        let space = _measure("a a", style) - _measure("aa", style)
        return run.map { ch -> InlineSpan in
            let natural = ch == " " ? space : _measure(String(ch), style)
            let a = _advance(ch, natural, style)
            return TextSpan(text: String(ch), style: a == natural ? style.flutter : style.flutter.copyWith(letterSpacing: a - natural))
        }
    }

    /// Wrapped text broken where Excel breaks it: a word that does not
    /// fit goes to the next line whole, and only a word longer than a
    /// line is cut, at the last character that fits, its rest going on
    /// the next line with what follows ("updatin" / "g the"). Left to
    /// the paragraph, a long word was cut wherever the line it met
    /// stopped — "are upd" / "ating" — and CVLKRA's narrow Remarks
    /// column wrapped to other lines and other heights than Excel's.
    func _breakLines(_ text: String, _ style: GridTextStyle, _ maxWidth: Double) -> String {
        var out: [String] = []
        for paragraph in text.split(separator: "\n", omittingEmptySubsequences: false) {
            // The places a line may end: at a space, and after a hyphen
            // ("Non-" / "Individual").
            var pieces: [(sep: String, text: Substring)] = []
            for (i, word) in paragraph.split(separator: " ", omittingEmptySubsequences: false).enumerated() {
                var rest = word, first = true
                repeat {
                    var end = rest.endIndex
                    if let h = rest.firstIndex(of: "-"), rest.index(after: h) < rest.endIndex { end = rest.index(after: h) }
                    pieces.append((first && i > 0 ? " " : "", rest[..<end]))
                    rest = rest[end...]; first = false
                } while !rest.isEmpty
            }
            var line = "", lineWidth = 0.0
            // (Spaces where a line breaks are not carried to the next: chart-
            // tdf159450's "Lion …… dd …… XYZ" starts its second line at XYZ.)
            var broken = false
            for (k, piece) in pieces.enumerated() {
                if broken && line.isEmpty {
                    if piece.text.isEmpty { continue }
                } else if k > 0 {
                    let w = _width(piece.sep + piece.text, style)
                    if lineWidth + w <= maxWidth { line += piece.sep + piece.text; lineWidth += w; continue }
                    if !line.isEmpty { out.append(line) }
                    line = ""; lineWidth = 0; broken = true
                    if piece.text.isEmpty { continue }
                }
                var rest = piece.text
                while !rest.isEmpty {
                    let w = _width(String(rest), style)
                    if lineWidth + w <= maxWidth { line += rest; lineWidth += w; break }
                    if !line.isEmpty { out.append(line); line = ""; lineWidth = 0; continue }
                    // Longer than a line: as many characters as fit, one at least.
                    var cut = rest.index(after: rest.startIndex)
                    while cut < rest.endIndex {
                        let next = rest.index(after: cut)
                        if _width(String(rest[..<next]), style) > maxWidth { break }
                        cut = next
                    }
                    out.append(String(rest[..<cut])); rest = rest[cut...]
                }
            }
            out.append(line)
        }
        // (A line break at the end makes no line: lo-tdf118668's
        // "41.49618,52.892124⏎" stands at the foot of its cell in Excel's
        // print, where an empty last line held it a line up.)
        while out.count > 1, out.last?.isEmpty == true { out.removeLast() }
        return out.joined(separator: "\n")
    }

    private var _widths: [Key: Double] = [:]
    /// The width `s` is set to: each character's advance, where it is
    /// set character by character.
    private func _width(_ s: String, _ style: GridTextStyle) -> Double {
        guard _spaces(s, style) else { return _measure(s, style) }
        let space = s.containsSubstring(" ") ? _measure("a a", style) - _measure("aa", style) : 0
        return s.reduce(0) { $0 + _advance($1, $1 == " " ? space : _measure(String($1), style), style) }
    }
    /// The stand-in's own width of `s`.
    private func _measure(_ s: String, _ style: GridTextStyle) -> Double {
        let k = Key(text: s, style: style, width: -1, align: .left)
        if let w = _widths[k] { return w }
        if _widths.count > 20000 { _widths.removeAll() }
        let tp = TextPainter(text: TextSpan(text: s, style: style.flutter), textDirection: .ltr)
        tp.layout()
        let w = tp.width
        tp.dispose()
        _widths[k] = w
        return w
    }

    func clear() {
        for tp in _cache.values { tp.dispose() }
        _cache.removeAll()
        _widths.removeAll()
    }
}
