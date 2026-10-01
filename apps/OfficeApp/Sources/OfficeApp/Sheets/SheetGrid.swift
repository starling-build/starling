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
enum GridMenuArea { case cells, columns, rows }

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

    init(key: (any Key)? = nil, controller: WorkbookController, zoom: Double,
         onEditText: @escaping (String?) -> Void,
         onShortcut: @escaping (Character, KeyChordTracker) -> Bool,
         onStatus: @escaping (String) -> Void,
         onContextMenu: @escaping (Offset, GridMenuArea) -> Void = { _, _ in },
         onFilterMenu: @escaping (Offset, Int) -> Void = { _, _ in }) {
        self.controller = controller
        self.zoom = zoom
        self.onEditText = onEditText
        self.onShortcut = onShortcut
        self.onStatus = onStatus
        self.onContextMenu = onContextMenu
        self.onFilterMenu = onFilterMenu
        super.init(key: key)
    }

    override func createState() -> State<StatefulWidget> { SheetGridState() }
}

final class SheetGridState: State<StatefulWidget> {
    let focus = FocusNode(debugLabel: "sheet grid")
    private let _chords = KeyChordTracker()
    private let _repaint = ChangeNotifier()
    private var _painter: _GridPainter! = nil
    private weak var _box: RenderBox?
    private(set) var size = Size.zero
    /// Scroll offset of the cell area, in logical pixels.
    private(set) var scrollX = 0.0
    private(set) var scrollY = 0.0
    private(set) var edit: CellEdit? = nil
    private var _drag: _Drag? = nil
    private var _lastClick: (cell: CellAddress, at: Double)? = nil
    /// The last press on a header border (column or row, and which), for
    /// double-click autofit.
    private var _lastBorder: (axis: WorkbookController.Axis, index: Int, at: Double)? = nil
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
    }
    /// The fill handle's outline while it is dragged.
    private(set) var fillTarget: CellRange? = nil
    /// The app's own clipboard: exact cells, formulas and formats.
    private static var _clip: WorkbookController.Clip? = nil

    private var _w: SheetGrid { widget as! SheetGrid }
    var controller: WorkbookController { _w.controller }

    /// Logical pixels per point at the current zoom (Excel's 96 dpi).
    var scale: Double { 96.0 / 72.0 * _w.zoom }
    var headerWidth: Double { (40 + Double(max(0, String(_lastVisibleRow + 1).count - 3)) * 8) * _w.zoom }
    var headerHeight: Double { 20 * _w.zoom }
    private var _lastVisibleRow = 0

    var cols: GridAxis { _axes().cols }
    var rows: GridAxis { _axes().rows }
    /// The axes, rebuilt only when the sheet's sizes, hidden rows or the zoom change.
    private var _axisCache: (sheet: ObjectIdentifier, version: Int, scale: Double, cols: GridAxis, rows: GridAxis)? = nil

    private func _axes() -> (cols: GridAxis, rows: GridAxis) {
        let ws = controller.sheet
        let id = ObjectIdentifier(ws)
        if let c = _axisCache, c.sheet == id, c.version == ws.layoutVersion, c.scale == scale { return (c.cols, c.rows) }
        let cols = GridAxis(def: ws.defaultColWidthPt, overrides: ws.colWidths, scale: scale)
        let rows = GridAxis(def: ws.defaultRowHeightPt, overrides: ws.rowHeights, hidden: ws.filteredRows, scale: scale)
        _axisCache = (id, ws.layoutVersion, scale, cols, rows)
        return (cols, rows)
    }

    override func initState() {
        super.initState()
        _painter = _GridPainter(state: self, repaint: _repaint)
        focus.onKeyData = { [weak self] k in self?._key(k) ?? false }
        focus.onFocusChange = { [weak self] _ in self?._chords.reset(); self?._repaint.notifyListeners() }
        // The sheet in front now: a change of sheet resets the scroll, and the
        // first notification must not read as one (it reset a scrolled view
        // under the first click).
        _lastSheet = controller.activeSheet
        controller.addListener({ [weak self] in self?._modelChanged() }, owner: self)
        focus.requestFocus()
    }

    override func dispose() {
        controller.removeListeners(owner: self)
        focus.dispose()
        texts.clear()
        super.dispose()
    }

    private var _lastSheet = -1

    private func _modelChanged() {
        if controller.activeSheet != _lastSheet {
            _lastSheet = controller.activeSheet
            scrollX = 0; scrollY = 0
            if edit != nil { cancelEdit() }
        }
        _repaint.notifyListeners()
    }

    // MARK: Geometry

    /// Frozen rows and columns: they stay put while the rest scrolls.
    var frozenRows: Int { controller.sheet.freezeRows }
    var frozenCols: Int { controller.sheet.freezeCols }
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

    /// A filter dropdown: a square in the header cell's bottom-right corner.
    func filterButton(_ a: CellAddress) -> Rect {
        let r = rect(a)
        let side = max(0, min(r.height - 2, 16 * _w.zoom, r.width - 2))
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
        let a = controller.active
        let text = replace ?? controller.input(a)
        edit = CellEdit(cell: a, text: Array(text), caret: text.count, enterMode: replace != nil)
        reveal(a)
        _w.onEditText(text)
        _repaint.notifyListeners()
    }

    /// Put the editor's text into the cell. Returns false if nothing was being edited.
    @discardableResult
    func commitEdit() -> Bool {
        guard let e = edit else { return false }
        edit = nil
        _pointRef = nil
        var text = String(e.text)
        // Excel closes the parentheses a formula left open.
        if text.hasPrefix("=") {
            let open = text.filter { $0 == "(" }.count - text.filter { $0 == ")" }.count
            if open > 0 { text += String(repeating: ")", count: open) }
        }
        if text != controller.input(e.cell) { controller.setInput(text, at: e.cell) }
        if let v = controller.sheet.cells[e.cell]?.value, case .text(let s) = v, s.hasPrefix("="), text.hasPrefix("=") {
            _w.onStatus("There's a problem with this formula")
        }
        _w.onEditText(nil)
        _repaint.notifyListeners()
        return true
    }

    func cancelEdit() {
        guard edit != nil else { return }
        edit = nil
        _pointRef = nil
        _w.onEditText(nil)
        _repaint.notifyListeners()
    }

    /// The formula bar changed the text while the cell is being edited.
    func setEditText(_ s: String) {
        if edit == nil { edit = CellEdit(cell: controller.active, text: [], caret: 0, enterMode: false) }
        edit!.text = Array(s)
        edit!.caret = edit!.text.count
        _repaint.notifyListeners()
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
        // A double click is two clicks with nothing between them.
        _lastClick = nil
        let named = KeyChordTracker.named(k.logical)
        let c = controller

        // Chords first.
        if _chords.primary, let letter = KeyChordTracker.letter(k.logical) {
            switch letter {
            case "z" where edit == nil: _chords.shift ? c.redo() : c.undo(); return true
            case "y" where edit == nil: c.redo(); return true
            case "a" where edit == nil:
                c.select(range: CellRange(top: 0, left: 0, bottom: CellAddress.maxRows - 1, right: CellAddress.maxCols - 1),
                         active: c.active)
                return true
            case "b" where edit == nil: c.setStyle { $0.bold.toggle() }; return true
            case "i" where edit == nil: c.setStyle { $0.italic.toggle() }; return true
            case "u" where edit == nil: c.setStyle { $0.underline.toggle() }; return true
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
                if let t = _chords.typedText(k) { _pointRef = nil; _insert(t); return true }
                return false
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
        case .pageDown, .pageUp:
            let rowsPerPage = max(1, Int((size.height - headerHeight) / max(1, rows.def)) - 1)
            let d = named == .pageDown ? rowsPerPage : -rowsPerPage
            c.select(CellAddress(row: c.active.row + d, col: c.active.col), extend: _chords.shift)
            scrollY = max(0, scrollY + Double(d) * rows.def)
            reveal(c.active); return true
        case .function(2): beginEdit(); return true
        case .delete: c.clearContents(); return true
        case .backspace: beginEdit(replace: ""); return true
        case .escape: return _w.onShortcut("\u{1B}", _chords)  // the shell closes its find bar
        default:
            if let t = _chords.typedText(k) { beginEdit(replace: t); return true }
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
                    if clip.cut { Self._clip = nil }
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
            c.select(range: CellRange(top: 0, left: col, bottom: CellAddress.maxRows - 1, right: col),
                     active: CellAddress(row: scrollY > 0 ? rows.index(at: scrollY) : 0, col: col))
            _drag = .columns(anchor: col)
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
            c.select(range: CellRange(top: row, left: 0, bottom: row, right: CellAddress.maxCols - 1),
                     active: CellAddress(row: row, col: scrollX > 0 ? cols.index(at: scrollX) : 0))
            _drag = .rows(anchor: row)
            return
        }
        if p.dx < headerWidth && p.dy < headerHeight {
            commitEdit()
            c.select(range: CellRange(top: 0, left: 0, bottom: CellAddress.maxRows - 1, right: CellAddress.maxCols - 1), active: c.active)
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
            let size = st.fontSize ?? 11
            if axis == .cols {
                if st.wrap && cell.value.isText { continue }
                // The full text: autofit is how long numbers stop being ####.
                let text = NumberFormat.display(cell.value, st.numberFormat, width: 255).text
                let w = (texts.painter(text, tstyle).width + 4 * _w.zoom) / scale + 1.5
                best[a.col] = max(best[a.col] ?? 0, w)
            } else {
                // Calibri 11 is 15pt in Excel; other sizes scale with it.
                var lines = 1.0
                if st.wrap && cell.value.isText {
                    let text = NumberFormat.display(cell.value, st.numberFormat, width: 255).text
                    let width = cols.size(a.col) - 4 * _w.zoom
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
            c.select(range: CellRange(top: 0, left: anchor, bottom: CellAddress.maxRows - 1, right: col),
                     active: c.active)
        case .rows(let anchor):
            let row = self.row(atLocal: p.dy)
            c.select(range: CellRange(top: anchor, left: 0, bottom: row, right: CellAddress.maxCols - 1),
                     active: c.active)
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
            onPointerPanZoomUpdate: { [weak self] e in self?._pan(e) },
            onPointerSignal: { [weak self] e in self?._signal(e) },
            behavior: .opaque,
            child: ClipRect(child: CustomPaint(painter: _painter, child: SizedBox(expand: ())))))
    }

    // MARK: Paint

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
        let headStyle = GridTextStyle(family: SelawikFontName.regular, size: 11 * _w.zoom, color: Int64(headerInk.value))
        let headStrong = GridTextStyle(family: SelawikFontName.regular, size: 11 * _w.zoom, bold: true, color: Int64(accent.value))
        let headFiltered = GridTextStyle(family: SelawikFontName.regular, size: 11 * _w.zoom, color: Int64(0xFF2F6FDF))
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
                canvas.drawRect(Rect.fromLTRB(x0, 0, x1, hh), p)
                p.color = accent
                canvas.drawRect(Rect.fromLTRB(x0, hh - 2, x1, hh), p)
            }
            let tp = texts.painter(CellAddress.columnName(col), on ? headStrong : headStyle)
            if x1 - x0 > tp.width + 2 {
                tp.paint(canvas, Offset(((x0 + x1) / 2 - tp.width / 2).rounded(), ((hh - tp.height) / 2).rounded()))
            }
            canvas.drawLine(Offset(x1.rounded() - 0.5, 0), Offset(x1.rounded() - 0.5, hh), line)
        }
        canvas.restore()
        canvas.save()
        canvas.clipRect(Rect.fromLTRB(0, hh, hw, size.height))
        for row in allR {
            let y0 = rowY(row), y1 = y0 + ra.size(row)
            if fr > 0 && row >= fr && y0 < hh + fh { continue }
            let on = row >= sel.top && row <= sel.bottom
            if on {
                p.color = wholeRows ? accent.withAlpha(60) : (dark ? Color(0xFF3A3A3A) : Color(0xFFE0E0E0))
                canvas.drawRect(Rect.fromLTRB(0, y0, hw, y1), p)
                p.color = accent
                canvas.drawRect(Rect.fromLTRB(hw - 2, y0, hw, y1), p)
            }
            // A filtered table's row numbers are blue, as Excel shows that rows are hidden.
            let filtered = filterActive && row > ws.autoFilter!.range.top && row <= ws.autoFilter!.range.bottom
            let tp = texts.painter(String(row + 1), on ? headStrong : filtered ? headFiltered : headStyle)
            if y1 - y0 > tp.height - 2 {
                tp.paint(canvas, Offset((hw - 6 - tp.width).rounded(), ((y0 + y1) / 2 - tp.height / 2).rounded()))
            }
            canvas.drawLine(Offset(0, y1.rounded() - 0.5), Offset(hw, y1.rounded() - 0.5), line)
        }
        canvas.restore()
        line.color = dark ? Color(0xFF4A4A4A) : Color(0xFFC8C8C8)
        canvas.drawLine(Offset(0, hh - 0.5), Offset(size.width, hh - 0.5), line)
        canvas.drawLine(Offset(hw - 0.5, 0), Offset(hw - 0.5, size.height), line)
        // The corner: a triangle that selects everything.
        p.color = dark ? Color(0xFF5A5A5A) : Color(0xFFBDBDBD)
        let path = Path()
        path.moveTo(hw - 4, hh - 14 * _w.zoom)
        path.lineTo(hw - 4, hh - 4)
        path.lineTo(hw - 14 * _w.zoom, hh - 4)
        path.close()
        canvas.drawPath(path, p)
    }

    private struct _Colors {
        let ink: Color, paper: Color, grid: Color
        let showGrid: Bool
    }

    /// One pane of the grid: the given rows and columns, already clipped.
    private func _paintRegion(_ canvas: any Canvas, rows rs: [Int], cols cs: [Int], clip: Rect,
                              ws: Worksheet, book: Workbook, merges: [CellRange], covered: Set<CellAddress>, colors: _Colors) {
        let ca = cols, ra = rows
        let p = Paint()
        p.style = .fill
        let editing = edit?.cell
        // Styled cells, looked up by position: what is on screen, not what is in the sheet.
        var styled: [(CellAddress, CellStyle)] = []
        for row in rs { for col in cs {
            let a = CellAddress(row: row, col: col)
            if let cell = ws.cells[a], cell.style != 0 { styled.append((a, book.style(cell.style))) }
        } }
        for (a, st) in styled where !covered.contains(a) {
            if let f = st.fill {
                p.color = Color(Int64(0xFF00_0000) | Int64(f))
                let m = merges.first { $0.topLeft == a }
                canvas.drawRect(m.map { rect($0) } ?? rect(a), p)
            }
        }
        // Gridlines, then merged areas painted over the lines inside them.
        if colors.showGrid {
            let line = Paint()
            line.style = .stroke
            line.strokeWidth = 1
            line.color = colors.grid
            for col in cs {
                let x = (colX(col) + ca.size(col)).rounded() - 0.5
                canvas.drawLine(Offset(x, clip.top), Offset(x, clip.bottom), line)
            }
            for row in rs {
                let y = (rowY(row) + ra.size(row)).rounded() - 0.5
                canvas.drawLine(Offset(clip.left, y), Offset(clip.right, y), line)
            }
        }
        for m in merges {
            let r = rect(m)
            let st = book.style(ws.cells[m.topLeft]?.style ?? 0)
            p.color = st.fill.map { Color(Int64(0xFF00_0000) | Int64($0)) } ?? colors.paper
            canvas.drawRect(Rect.fromLTRB(r.left + 0.5, r.top + 0.5, r.right - 1, r.bottom - 1), p)
        }
        // Values.
        for row in rs { for col in cs {
            let a = CellAddress(row: row, col: col)
            guard a != editing, !covered.contains(a), let cell = ws.cells[a], !cell.value.isEmpty else { continue }
            if let m = merges.first(where: { $0.topLeft == a }) {
                _paintCell(canvas, a, cell, in: rect(m), spill: false, ws: ws, book: book, ink: colors.ink)
            } else {
                _paintCell(canvas, a, cell, in: rect(a), spill: true, ws: ws, book: book, ink: colors.ink)
            }
        } }
        // Merged areas whose top-left is out of this pane still draw their text.
        for m in merges where !(rs.contains(m.top) && cs.contains(m.left)) {
            if let cell = ws.cells[m.topLeft], !cell.value.isEmpty, m.topLeft != editing {
                _paintCell(canvas, m.topLeft, cell, in: rect(m), spill: false, ws: ws, book: book, ink: colors.ink)
            }
        }
        // A long text left of the pane still spills into it.
        if let first = cs.first, first > 0 {
            for row in rs {
                var col = first - 1
                while col >= max(0, first - 8) {
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
            let l = r.left.rounded() - 0.5, rr = r.right.rounded() - 0.5
            let t = r.top.rounded() - 0.5, bt = r.bottom.rounded() - 0.5
            if b.top { canvas.drawLine(Offset(l, t), Offset(rr, t), border) }
            if b.bottom { canvas.drawLine(Offset(l, bt), Offset(rr, bt), border) }
            if b.left { canvas.drawLine(Offset(l, t), Offset(l, bt), border) }
            if b.right { canvas.drawLine(Offset(rr, t), Offset(rr, bt), border) }
        }
        // Filter dropdowns: ▾, or a funnel on a column that filters.
        if let af = ws.autoFilter, rs.contains(af.range.top) {
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
    private func _textStyle(_ st: CellStyle, color: UInt32?, ink: Color) -> GridTextStyle {
        let c = (color ?? st.color).map { Int64(0xFF00_0000) | Int64($0) } ?? Int64(ink.value)
        return GridTextStyle(family: OfficeFonts.substitute(st.fontName ?? OfficeFonts.defaultFamily),
                             size: (st.fontSize ?? 11) * scale * Self.excelTextScale, bold: st.bold, italic: st.italic,
                             underline: st.underline, strike: st.strike, color: c)
    }

    private func _paintCell(_ canvas: any Canvas, _ a: CellAddress, _ cell: Cell, in r: Rect, spill: Bool,
                            ws: Worksheet, book: Workbook, ink: Color) {
        let st = book.style(cell.style)
        let ca = cols
        let left = r.left, right = r.right, top = r.top, bottom = r.bottom
        let width = right - left
        guard width > 2 else { return }
        let chars = max(1, Int(width / (7 * _w.zoom)))
        var (text, color) = NumberFormat.display(cell.value, st.numberFormat, width: chars)
        let style = _textStyle(st, color: color, ink: ink)
        var align = st.hAlign
        if align == .general {
            switch cell.value {
            case .number: align = .right
            case .bool, .error: align = .center
            default: align = .left
            }
        }
        let pad = 2 * _w.zoom   // Excel's cell margin
        // Wrapped text: lines within the cell's width, never spilling.
        let wraps = st.wrap && cell.value.isText
        var tp = texts.painter(text, style, maxWidth: wraps ? max(1, width - pad * 2) : .infinity)
        // A number too wide for its cell is ####, never cut.
        if case .number = cell.value, tp.width > width - pad * 2 {
            let hashes = max(1, Int((width - pad * 2) / max(1, texts.painter("#", style).width)))
            text = String(repeating: "#", count: hashes)
            color = nil
            tp = texts.painter(text, style)
        }
        // Text spills over empty neighbours.
        var clipLeft = left, clipRight = right
        if spill && cell.value.isText && tp.width > width - pad * 2 && !wraps {
            if align == .left || align == .general {
                var col = a.col + 1
                while col < CellAddress.maxCols, ws.cells[CellAddress(row: a.row, col: col)]?.value.isEmpty ?? true,
                      clipRight - left < tp.width + pad * 2, col <= a.col + 30 {
                    clipRight += ca.size(col); col += 1
                }
            } else if align == .right {
                var col = a.col - 1
                while col >= 0, ws.cells[CellAddress(row: a.row, col: col)]?.value.isEmpty ?? true,
                      right - clipLeft < tp.width + pad * 2 {
                    clipLeft -= ca.size(col); col -= 1
                }
            }
        }
        let tx: Double
        switch align {
        case .right: tx = right - pad - tp.width
        case .center: tx = left + (width - tp.width) / 2
        default: tx = left + pad
        }
        let ty: Double
        switch st.vAlign {
        case .top: ty = top + 1
        case .center: ty = top + (bottom - top - tp.height) / 2
        case .bottom: ty = bottom - tp.height - 1
        }
        canvas.save()
        canvas.clipRect(Rect.fromLTRB(clipLeft + 1, top, clipRight - 1, bottom))
        tp.paint(canvas, Offset(tx.rounded(), ty.rounded()))
        canvas.restore()
    }

    private func _paintEditor(_ canvas: any Canvas, _ e: CellEdit, ink: Color, paper: Color, accent: Color, size: Size) {
        let r = rect(e.cell)
        let st = controller.style(at: e.cell)
        var style = _textStyle(st, color: nil, ink: ink)
        if e.text.first == "=" { style.family = OfficeFonts.substitute("Calibri") }
        let text = String(e.text)
        let tp = texts.painter(text.isEmpty ? " " : text, style)
        let pad = 2 * _w.zoom
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
        // The caret.
        let before = e.caret == 0 ? 0 : texts.painter(String(e.text[0 ..< e.caret]), style).width
        p.color = ink
        canvas.drawRect(Rect.fromLTWH((box.left + pad + before).rounded(), ty + 1, 1.5, max(1, tp.height - 2)), p)
        canvas.restore()
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

    var flutter: Flutter.TextStyle {
        var decorations: [TextDecoration] = []
        if underline { decorations.append(.underline) }
        if strike { decorations.append(.lineThrough) }
        return Flutter.TextStyle(color: Color(color), fontSize: size,
                                 fontWeight: bold ? .bold : .normal, fontStyle: italic ? .italic : .normal,
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
    }
    private var _cache: [Key: TextPainter] = [:]

    func painter(_ text: String, _ style: GridTextStyle, maxWidth: Double = .infinity) -> TextPainter {
        let k = Key(text: text, style: style, width: maxWidth.isFinite ? Int(maxWidth) : -1)
        if let tp = _cache[k] { return tp }
        if _cache.count > 4000 { clear() }
        let tp = TextPainter(text: TextSpan(text: text, style: style.flutter), textDirection: .ltr)
        tp.layout(minWidth: 0, maxWidth: maxWidth)
        _cache[k] = tp
        return tp
    }

    func clear() {
        for tp in _cache.values { tp.dispose() }
        _cache.removeAll()
    }
}
