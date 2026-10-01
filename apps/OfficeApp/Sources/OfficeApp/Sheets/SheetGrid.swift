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
    let overrides: [(Int, Double)]   // sorted by index

    init(def: Double, overrides: [Int: Double], scale: Double) {
        self.def = def * scale
        self.overrides = overrides.map { ($0.key, $0.value * scale) }.sorted { $0.0 < $1.0 }
    }

    func size(_ i: Int) -> Double {
        for (k, s) in overrides { if k == i { return s }; if k > i { break } }
        return def
    }

    /// Distance from index 0's start to index `i`'s start.
    func start(_ i: Int) -> Double {
        var x = Double(i) * def
        for (k, s) in overrides { if k >= i { break }; x += s - def }
        return x
    }

    /// The index whose span contains `x` (x ≥ 0).
    func index(at x: Double) -> Int {
        var pos = 0.0, idx = 0
        for (k, s) in overrides {
            let span = Double(k - idx) * def
            if x < pos + span { return idx + Int((x - pos) / def) }
            pos += span
            if x < pos + s { return k }
            pos += s
            idx = k + 1
        }
        return idx + Int(max(0, x - pos) / def)
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

final class SheetGrid: StatefulWidget {
    let controller: WorkbookController
    let zoom: Double
    /// The editor's text changed (the formula bar mirrors it), or nil when
    /// editing ended.
    let onEditText: (String?) -> Void
    /// A chord the grid does not handle itself (the shell's ⌘S, ⌘O…).
    let onShortcut: (Character, KeyChordTracker) -> Bool
    let onStatus: (String) -> Void

    init(key: (any Key)? = nil, controller: WorkbookController, zoom: Double,
         onEditText: @escaping (String?) -> Void,
         onShortcut: @escaping (Character, KeyChordTracker) -> Bool,
         onStatus: @escaping (String) -> Void) {
        self.controller = controller
        self.zoom = zoom
        self.onEditText = onEditText
        self.onShortcut = onShortcut
        self.onStatus = onStatus
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
    let texts = _TextCache()

    private enum _Drag {
        case cells
        case columns(anchor: Int)
        case rows(anchor: Int)
        case resizeColumn(col: Int, startX: Double, startWidth: Double)
        case resizeRow(row: Int, startY: Double, startHeight: Double)
    }

    private var _w: SheetGrid { widget as! SheetGrid }
    var controller: WorkbookController { _w.controller }

    /// Logical pixels per point at the current zoom (Excel's 96 dpi).
    var scale: Double { 96.0 / 72.0 * _w.zoom }
    var headerWidth: Double { (40 + Double(max(0, String(_lastVisibleRow + 1).count - 3)) * 8) * _w.zoom }
    var headerHeight: Double { 20 * _w.zoom }
    private var _lastVisibleRow = 0

    var cols: GridAxis { GridAxis(def: controller.sheet.defaultColWidthPt, overrides: controller.sheet.colWidths, scale: scale) }
    var rows: GridAxis { GridAxis(def: controller.sheet.defaultRowHeightPt, overrides: controller.sheet.rowHeights, scale: scale) }

    override func initState() {
        super.initState()
        _painter = _GridPainter(state: self, repaint: _repaint)
        focus.onKeyData = { [weak self] k in self?._key(k) ?? false }
        focus.onFocusChange = { [weak self] _ in self?._chords.reset(); self?._repaint.notifyListeners() }
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

    /// A position inside this view (local) as a cell, or nil over headers.
    func cell(atLocal p: Offset) -> CellAddress {
        let c = cols.index(at: max(0, p.dx - headerWidth + scrollX))
        let r = rows.index(at: max(0, p.dy - headerHeight + scrollY))
        return CellAddress(row: min(r, CellAddress.maxRows - 1), col: min(c, CellAddress.maxCols - 1))
    }

    /// A cell's rectangle in local coordinates.
    func rect(_ a: CellAddress) -> Rect {
        let ca = cols, ra = rows
        return Rect.fromLTWH(headerWidth + ca.start(a.col) - scrollX, headerHeight + ra.start(a.row) - scrollY,
                             ca.size(a.col), ra.size(a.row))
    }

    func rect(_ r: CellRange) -> Rect {
        let a = rect(r.topLeft), b = rect(r.bottomRight)
        return Rect.fromLTRB(a.left, a.top, b.right, b.bottom)
    }

    /// Scroll so the cell is fully in view.
    func reveal(_ a: CellAddress) {
        let ca = cols, ra = rows
        let viewW = size.width - headerWidth, viewH = size.height - headerHeight
        guard viewW > 0, viewH > 0 else { return }
        let x0 = ca.start(a.col), x1 = x0 + ca.size(a.col)
        let y0 = ra.start(a.row), y1 = y0 + ra.size(a.row)
        if x0 < scrollX { scrollX = x0 } else if x1 > scrollX + viewW { scrollX = min(x0, x1 - viewW) }
        if y0 < scrollY { scrollY = y0 } else if y1 > scrollY + viewH { scrollY = min(y0, y1 - viewH) }
        _repaint.notifyListeners()
    }

    private func _scroll(by dx: Double, _ dy: Double) {
        scrollX = max(0, scrollX + dx)
        scrollY = max(0, scrollY + dy)
        let maxX = cols.start(CellAddress.maxCols) - (size.width - headerWidth)
        let maxY = rows.start(CellAddress.maxRows) - (size.height - headerHeight)
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

    private func _key(_ k: KeyData) -> Bool {
        if _chords.track(k) { return false }
        guard k.type != .up else { return false }
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
            case "c" where edit == nil: copySelection(); return true
            case "x" where edit == nil: copySelection(); c.clearContents(); return true
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
                if let t = _chords.typedText(k) { _insert(t); return true }
                return false
            }
        }

        switch named {
        case .left, .right, .up, .down: _move(named); return true
        case .enter: c.advance(rows: _chords.shift ? -1 : 1, cols: 0); reveal(c.active); return true
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
        case .escape: return false
        default:
            if let t = _chords.typedText(k) { beginEdit(replace: t); return true }
            return false
        }
    }

    private func _move(_ named: NamedKey) {
        let c = controller
        let (dr, dc): (Int, Int) = named == .up ? (-1, 0) : named == .down ? (1, 0) : named == .left ? (0, -1) : (0, 1)
        let from = _chords.shift ? c._extentEnd : c.active
        var to = CellAddress(row: from.row + dr, col: from.col + dc)
        if _chords.primary || _chords.control { to = c.edge(from: from, rows: dr, cols: dc) }
        c.select(to, extend: _chords.shift)
        reveal(to)
    }

    // MARK: Clipboard

    /// The selection as tab-separated values, as every spreadsheet reads it.
    func copySelection() {
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
        Clipboard.setData(ClipboardData(text: lines.joined(separator: "\n") + "\n"))
        _w.onStatus("Copied \(r.rows > 1 || r.cols > 1 ? r.a1 : r.topLeft.a1)")
    }

    func paste() {
        Clipboard.getData(Clipboard.kTextPlain) { [weak self] data in
            guard let text = data?.text, !text.isEmpty else { return }
            DispatchQueue.main.async {
                guard let self, self.mounted else { return }
                if self.edit != nil {
                    self._insert(text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).first.map(String.init) ?? "")
                    return
                }
                let rows = Csv.parse(text, separator: "\t")
                let c = self.controller
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
        // Column header: select columns, or resize at a border.
        if p.dy < headerHeight && p.dx >= headerWidth {
            let x = p.dx - headerWidth + scrollX
            let col = cols.index(at: x)
            let edgeLeft = cols.start(col), edgeRight = edgeLeft + cols.size(col)
            if abs(x - edgeRight) <= 4 || (col > 0 && abs(x - edgeLeft) <= 4) {
                let target = abs(x - edgeRight) <= 4 ? col : col - 1
                commitEdit()
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
            let y = p.dy - headerHeight + scrollY
            let row = rows.index(at: y)
            let edgeBottom = rows.start(row) + rows.size(row)
            if abs(y - edgeBottom) <= 3 {
                commitEdit()
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
        // A click in a formula being typed would point at cells (X3);
        // for now a click elsewhere commits it.
        if let ed = edit {
            if ed.cell == a { return }
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

    private func _move(_ e: PointerEvent) {
        guard let d = _drag else { return }
        let p = _local(e)
        let c = controller
        switch d {
        case .cells:
            let a = cell(atLocal: p)
            if a != c._extentEnd { c.select(a, extend: true); _autoScroll(p) }
        case .columns(let anchor):
            let col = cols.index(at: max(0, p.dx - headerWidth + scrollX))
            c.select(range: CellRange(top: 0, left: anchor, bottom: CellAddress.maxRows - 1, right: col),
                     active: c.active)
        case .rows(let anchor):
            let row = rows.index(at: max(0, p.dy - headerHeight + scrollY))
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
        }
    }

    private func _up(_ e: PointerEvent) {
        _move(e)
        if case .resizeColumn(let col, _, _)? = _drag { controller.setColumnWidth(col, controller.sheet.colWidth(col)) }
        if case .resizeRow(let row, _, _)? = _drag { controller.setRowHeight(row, controller.sheet.rowHeight(row)) }
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

        let p = Paint()
        p.style = .fill
        p.color = paper
        canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), p)

        // The visible window.
        let firstCol = ca.index(at: scrollX), firstRow = ra.index(at: scrollY)
        var lastCol = firstCol, lastRow = firstRow
        while lastCol < CellAddress.maxCols - 1, hw + ca.start(lastCol + 1) - scrollX < size.width { lastCol += 1 }
        while lastRow < CellAddress.maxRows - 1, hh + ra.start(lastRow + 1) - scrollY < size.height { lastRow += 1 }
        _lastVisibleRow = lastRow
        let x0 = hw + ca.start(firstCol) - scrollX, y0 = hh + ra.start(firstRow) - scrollY
        var xs: [Double] = [], ys: [Double] = []
        var x = x0
        for col in firstCol ... lastCol { xs.append(x); x += ca.size(col) }
        xs.append(x)
        var y = y0
        for row in firstRow ... lastRow { ys.append(y); y += ra.size(row) }
        ys.append(y)

        canvas.save()
        canvas.clipRect(Rect.fromLTRB(hw, hh, size.width, size.height))

        // The styled cells in view: looked up by position, so a sheet of a
        // hundred thousand cells costs what is on screen, not what is in it.
        var styled: [(CellAddress, CellStyle)] = []
        for row in firstRow ... lastRow {
            for col in firstCol ... lastCol {
                let a = CellAddress(row: row, col: col)
                if let cell = ws.cells[a], cell.style != 0 { styled.append((a, book.style(cell.style))) }
            }
        }
        // Fills.
        for (a, st) in styled {
            if let f = st.fill {
                p.color = Color(Int64(0xFF00_0000) | Int64(f))
                canvas.drawRect(Rect.fromLTRB(xs[a.col - firstCol], ys[a.row - firstRow], xs[a.col - firstCol + 1], ys[a.row - firstRow + 1]), p)
            }
        }

        // Gridlines.
        let line = Paint()
        line.style = .stroke
        line.strokeWidth = 1
        line.color = gridColor
        for gx in xs { canvas.drawLine(Offset(gx.rounded() - 0.5, hh), Offset(gx.rounded() - 0.5, size.height), line) }
        for gy in ys { canvas.drawLine(Offset(hw, gy.rounded() - 0.5), Offset(size.width, gy.rounded() - 0.5), line) }

        // Values, with text spilling into empty neighbours as Excel does.
        let editing = edit?.cell
        for row in firstRow ... lastRow {
            for col in firstCol ... lastCol {
                let a = CellAddress(row: row, col: col)
                guard a != editing, let cell = ws.cells[a], !cell.value.isEmpty else { continue }
                _paintCell(canvas, a, cell, ws: ws, book: book, xs: xs, ys: ys, firstCol: firstCol, firstRow: firstRow,
                           lastCol: lastCol, ink: ink)
            }
        }
        // A long text left of the window still spills into it.
        if firstCol > 0 {
            for row in firstRow ... lastRow {
                var col = firstCol - 1
                while col >= max(0, firstCol - 8) {
                    let a = CellAddress(row: row, col: col)
                    if let cell = ws.cells[a], !cell.value.isEmpty {
                        if cell.value.isText {
                            _paintCell(canvas, a, cell, ws: ws, book: book, xs: xs, ys: ys, firstCol: firstCol, firstRow: firstRow,
                                       lastCol: lastCol, ink: ink)
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
        border.color = ink
        for (a, st) in styled {
            let b = st.borders
            guard b.top || b.left || b.bottom || b.right else { continue }
            let l = xs[a.col - firstCol].rounded() - 0.5, r = xs[a.col - firstCol + 1].rounded() - 0.5
            let t = ys[a.row - firstRow].rounded() - 0.5, bt = ys[a.row - firstRow + 1].rounded() - 0.5
            if b.top { canvas.drawLine(Offset(l, t), Offset(r, t), border) }
            if b.bottom { canvas.drawLine(Offset(l, bt), Offset(r, bt), border) }
            if b.left { canvas.drawLine(Offset(l, t), Offset(l, bt), border) }
            if b.right { canvas.drawLine(Offset(r, t), Offset(r, bt), border) }
        }

        // Selection.
        let sel = c.selection
        if sel.right >= firstCol, sel.left <= lastCol, sel.bottom >= firstRow, sel.top <= lastRow {
            let r = rect(sel)
            if !sel.isSingle {
                p.color = accent.withAlpha(36)
                canvas.drawRect(r, p)
                // The active cell stays white inside the tint.
                p.color = paper
                canvas.drawRect(rect(c.active).deflate(1), p)
                if let cell = ws.cells[c.active], !cell.value.isEmpty, c.active != editing {
                    _paintCell(canvas, c.active, cell, ws: ws, book: book, xs: xs, ys: ys, firstCol: firstCol, firstRow: firstRow,
                               lastCol: lastCol, ink: ink)
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

        // The editor.
        if let e = edit {
            _paintEditor(canvas, e, ink: ink, paper: paper, accent: accent, size: size)
        }
        canvas.restore()

        // Headers.
        p.color = headerFill
        canvas.drawRect(Rect.fromLTWH(0, 0, size.width, hh), p)
        canvas.drawRect(Rect.fromLTWH(0, 0, hw, size.height), p)
        let headStyle = GridTextStyle(family: SelawikFontName.regular, size: 11 * _w.zoom, color: Int64(headerInk.value))
        let headStrong = GridTextStyle(family: SelawikFontName.regular, size: 11 * _w.zoom, bold: true, color: Int64(accent.value))
        let wholeCols = sel.top == 0 && sel.bottom == CellAddress.maxRows - 1
        let wholeRows = sel.left == 0 && sel.right == CellAddress.maxCols - 1
        canvas.save()
        canvas.clipRect(Rect.fromLTRB(hw, 0, size.width, hh))
        for (i, col) in (firstCol ... lastCol).enumerated() {
            let on = col >= sel.left && col <= sel.right
            if on {
                p.color = wholeCols ? accent.withAlpha(60) : (dark ? Color(0xFF3A3A3A) : Color(0xFFE0E0E0))
                canvas.drawRect(Rect.fromLTRB(xs[i], 0, xs[i + 1], hh), p)
                p.color = accent
                canvas.drawRect(Rect.fromLTRB(xs[i], hh - 2, xs[i + 1], hh), p)
            }
            let tp = texts.painter(CellAddress.columnName(col), on ? headStrong : headStyle)
            if xs[i + 1] - xs[i] > tp.width + 2 {
                tp.paint(canvas, Offset(((xs[i] + xs[i + 1]) / 2 - tp.width / 2).rounded(), ((hh - tp.height) / 2).rounded()))
            }
            canvas.drawLine(Offset(xs[i + 1].rounded() - 0.5, 0), Offset(xs[i + 1].rounded() - 0.5, hh), line)
        }
        canvas.restore()
        canvas.save()
        canvas.clipRect(Rect.fromLTRB(0, hh, hw, size.height))
        for (i, row) in (firstRow ... lastRow).enumerated() {
            let on = row >= sel.top && row <= sel.bottom
            if on {
                p.color = wholeRows ? accent.withAlpha(60) : (dark ? Color(0xFF3A3A3A) : Color(0xFFE0E0E0))
                canvas.drawRect(Rect.fromLTRB(0, ys[i], hw, ys[i + 1]), p)
                p.color = accent
                canvas.drawRect(Rect.fromLTRB(hw - 2, ys[i], hw, ys[i + 1]), p)
            }
            let tp = texts.painter(String(row + 1), on ? headStrong : headStyle)
            if ys[i + 1] - ys[i] > tp.height - 2 {
                tp.paint(canvas, Offset((hw - 6 - tp.width).rounded(), ((ys[i] + ys[i + 1]) / 2 - tp.height / 2).rounded()))
            }
            canvas.drawLine(Offset(0, ys[i + 1].rounded() - 0.5), Offset(hw, ys[i + 1].rounded() - 0.5), line)
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

    private func _paintCell(_ canvas: any Canvas, _ a: CellAddress, _ cell: Cell, ws: Worksheet, book: Workbook,
                            xs: [Double], ys: [Double], firstCol: Int, firstRow: Int, lastCol: Int, ink: Color) {
        let st = book.style(cell.style)
        let ca = cols
        let ri = a.row - firstRow
        let left: Double, right: Double
        if a.col >= firstCol {
            left = xs[a.col - firstCol]; right = xs[a.col - firstCol + 1]
        } else {
            left = headerWidth + ca.start(a.col) - scrollX; right = left + ca.size(a.col)
        }
        let top = ys[ri], bottom = ys[ri + 1]
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
        var tp = texts.painter(text, style)
        // A number too wide for its cell is ####, never cut.
        if case .number = cell.value, tp.width > width - pad * 2 {
            let hashes = max(1, Int((width - pad * 2) / max(1, texts.painter("#", style).width)))
            text = String(repeating: "#", count: hashes)
            color = nil
            tp = texts.painter(text, style)
        }
        // Text spills over empty neighbours.
        var clipLeft = left, clipRight = right
        if cell.value.isText && tp.width > width - pad * 2 && !st.wrap {
            if align == .left || align == .general {
                var col = a.col + 1
                while col <= lastCol + 8, ws.cells[CellAddress(row: a.row, col: col)]?.value.isEmpty ?? true,
                      clipRight - left < tp.width + pad * 2 {
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
    }
    private var _cache: [Key: TextPainter] = [:]

    func painter(_ text: String, _ style: GridTextStyle, maxWidth: Double = .infinity) -> TextPainter {
        let k = Key(text: text, style: style)
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
