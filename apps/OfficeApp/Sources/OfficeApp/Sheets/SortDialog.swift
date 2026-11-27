// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-DA-1b: the Sort dialog (Data → Sort…). A list of levels, each a column and
// an order; "My data has headers" decides whether the first row stays put and
// names the columns. It opens on the region the quick Sort buttons would use,
// with the headers guess Excel makes. OK sorts through the controller's
// sortRange (one undo step); a refusal (merged cells, protected sheet) shows
// its message and the dialog stays. Each level sorts On cell values, cell
// colour or font colour; a values level's Order is A to Z, Z to A, one of
// Excel's built-in lists either way round, or a list typed in; a colour
// level puts one colour On Top or On Bottom. Options: Left to right (the
// levels are rows) and Case sensitive.

import Flutter
import FlutterSwiftBridge
import Foundation

final class SortDialog: StatefulWidget {
    let controller: WorkbookController
    let range: CellRange
    let hasHeader: Bool
    let onClose: () -> Void

    init(controller: WorkbookController, range: CellRange, hasHeader: Bool, onClose: @escaping () -> Void) {
        self.controller = controller
        self.range = range
        self.hasHeader = hasHeader
        self.onClose = onClose
        super.init()
    }

    override func createState() -> State<StatefulWidget> { SortDialogState() }
}

final class SortDialogState: State<StatefulWidget> {
    private var _w: SortDialog { widget as! SortDialog }
    private(set) var hasHeader = false
    private(set) var byColumns = false
    private(set) var caseSensitive = false
    private(set) var levels: [SortKey] = []
    private(set) var message = ""
    /// The typed list of a level whose Order is "Custom list…" (entries separated by commas).
    private var _typed: [Int: TextEditingController] = [:]

    /// Order codes for a values level: A to Z, Z to A, each built-in list both ways, a typed list.
    static let ascending = 0, descending = 1, typedList = -1
    static func listCode(_ i: Int, ascending: Bool) -> Int { 2 + 2 * i + (ascending ? 0 : 1) }

    override func initState() {
        super.initState()
        hasHeader = _w.hasHeader
        let c = _w.controller
        // Start on the active cell's column when it is inside the region, else the first column.
        let col = (_w.range.left ... _w.range.right).contains(c.active.col) ? c.active.col : _w.range.left
        levels = [SortKey(col: col, ascending: true)]
    }

    /// The lines a level can name: the region's columns, or its rows when sorting left to right.
    var lines: [Int] { byColumns ? Array(_w.range.top ... _w.range.bottom) : Array(_w.range.left ... _w.range.right) }

    /// How a line is named in the list: its header text, or "Column B" / "Row 3" without headers.
    func columnLabel(_ line: Int) -> String {
        if hasHeader {
            let at = byColumns ? CellAddress(row: line, col: _w.range.left) : CellAddress(row: _w.range.top, col: line)
            let text = _w.controller.input(at)
            if !text.isEmpty { return text }
        }
        return byColumns ? "Row \(line + 1)" : "Column " + CellAddress.columnName(line)
    }

    func colors(_ level: Int) -> [UInt32] {
        let k = levels[level]
        guard k.on != .values, k.on != .cellIcon else { return [] }
        return _w.controller.sortColors(_w.range, line: k.col, hasHeader: hasHeader, byColumns: byColumns, fill: k.on == .cellColor)
    }

    func icons(_ level: Int) -> [SortIcon] {
        guard levels[level].on == .cellIcon else { return [] }
        return _w.controller.sortIcons(_w.range, line: levels[level].col, hasHeader: hasHeader, byColumns: byColumns)
    }

    /// The Order combo's value for a values level.
    func orderCode(_ level: Int) -> Int {
        let k = levels[level]
        guard let list = k.custom else { return k.ascending ? Self.ascending : Self.descending }
        if _typed[level] != nil { return Self.typedList }
        if let i = SortKey.builtinLists.firstIndex(of: list) { return Self.listCode(i, ascending: k.ascending) }
        return Self.typedList
    }

    func setHeader(_ on: Bool) { hasHeader = on; message = ""; _refreshColors(); setState {} }
    func setColumn(_ level: Int, _ col: Int) { levels[level].col = col; _refreshColor(level); setState {} }
    func setAscending(_ level: Int, _ on: Bool) { levels[level].ascending = on; setState {} }

    func setSortOn(_ level: Int, _ on: SortOn) {
        levels[level].on = on
        levels[level].custom = nil
        levels[level].ascending = true
        _typed[level] = nil
        _refreshColor(level)
        message = ""; setState {}
    }

    func setOrder(_ level: Int, _ code: Int) {
        switch code {
        case Self.ascending, Self.descending:
            levels[level].custom = nil; levels[level].ascending = code == Self.ascending; _typed[level] = nil
        case Self.typedList:
            levels[level].ascending = true
            if _typed[level] == nil { _typed[level] = TextEditingController() }
            levels[level].custom = []
        default:
            let i = (code - 2) / 2
            levels[level].custom = SortKey.builtinLists[i]; levels[level].ascending = code % 2 == 0; _typed[level] = nil
        }
        message = ""; setState {}
    }

    /// Type a list for a "Custom list…" level.
    func setTypedList(_ level: Int, _ text: String) {
        if _typed[level] == nil { setOrder(level, Self.typedList) }
        _typed[level]?.text = text
    }

    func setColor(_ level: Int, _ rgb: UInt32?) { levels[level].color = rgb; setState {} }
    func setIcon(_ level: Int, _ icon: SortIcon) { levels[level].icon = icon; setState {} }
    func setColorOnTop(_ level: Int, _ top: Bool) { levels[level].colorOnTop = top; setState {} }

    func setByColumns(_ on: Bool) {
        guard on != byColumns else { return }
        byColumns = on
        // The levels named columns and now name rows (or back): start again on the first line.
        levels = [SortKey(col: lines[0], ascending: true)]
        _typed = [:]
        message = ""; setState {}
    }

    func setCaseSensitive(_ on: Bool) { caseSensitive = on; setState {} }

    func addLevel() {
        let used = Set(levels.map { $0.col })
        guard let col = lines.first(where: { !used.contains($0) }) else {
            message = byColumns ? "Every row is already a level." : "Every column is already a level."; setState {}; return
        }
        levels.append(SortKey(col: col, ascending: true)); message = ""; setState {}
    }

    func removeLevel(_ i: Int) {
        guard levels.count > 1, levels.indices.contains(i) else { return }
        levels.remove(at: i)
        // Typed lists follow their level down.
        _typed = Dictionary(uniqueKeysWithValues: _typed.compactMap { k, v in k == i ? nil : (k > i ? k - 1 : k, v) })
        setState {}
    }

    private func _refreshColor(_ level: Int) {
        if levels[level].on == .cellIcon {
            let have = icons(level)
            if levels[level].icon.map({ have.contains($0) }) != true { levels[level].icon = have.first }
        } else { levels[level].icon = nil }
        guard levels[level].on != .values, levels[level].on != .cellIcon else { levels[level].color = nil; return }
        let have = colors(level)
        if levels[level].color.map({ have.contains($0) }) != true { levels[level].color = have.first }
    }

    private func _refreshColors() { for i in levels.indices { _refreshColor(i) } }

    func apply() {
        var keys = levels
        for (i, f) in _typed where keys.indices.contains(i) {
            let items = f.text.split(separator: ",").map { $0.trimmingWhitespace() }.filter { !$0.isEmpty }
            guard !items.isEmpty else { message = "Type the list's entries, separated by commas."; setState {}; return }
            keys[i].custom = items
        }
        if let problem = _w.controller.sortRange(_w.range, keys: keys, hasHeader: hasHeader, byColumns: byColumns, caseSensitive: caseSensitive) {
            message = problem.message
            setState {}
        } else {
            _w.onClose()
        }
    }

    private static func hex(_ c: UInt32) -> String {
        let h = String(c & 0xFFFFFF, radix: 16, uppercase: true)
        return "#" + String(repeating: "0", count: max(0, 6 - h.count)) + h
    }

    private func _swatch(_ c: UInt32, _ fluent: FluentThemeData) -> Widget {
        Row(children: [
            SizedBox(width: 36, height: 14, child: ColoredBox(color: Color(Int64(0xFF00_0000 | (c & 0xFFFFFF))))),
            SizedBox(width: 6, height: nil, child: nil),
            Text(Self.hex(c), style: fluent.typography.caption),
        ])
    }

    private func _orderControls(_ i: Int, _ level: SortKey, _ fluent: FluentThemeData) -> [Widget] {
        if level.on == .values {
            var items = [ComboBoxItem<Int>(value: Self.ascending, child: Text("A to Z")),
                         ComboBoxItem<Int>(value: Self.descending, child: Text("Z to A"))]
            for (n, list) in SortKey.builtinLists.enumerated() {
                items.append(ComboBoxItem<Int>(value: Self.listCode(n, ascending: true), child: Text(list.joined(separator: ", "))))
                items.append(ComboBoxItem<Int>(value: Self.listCode(n, ascending: false), child: Text(list.reversed().joined(separator: ", "))))
            }
            items.append(ComboBoxItem<Int>(value: Self.typedList, child: Text("Custom list…")))
            return [SizedBox(width: 260, height: nil, child: ComboBox<Int>(
                key: ValueKey("sort-order-\(i)"), value: orderCode(i), items: items,
                onChanged: { [weak self] v in if let v { self?.setOrder(i, v) } }))]
        }
        let place = SizedBox(width: 112, height: nil, child: ComboBox<Bool>(
            key: ValueKey("sort-place-\(i)"), value: level.colorOnTop,
            items: [ComboBoxItem<Bool>(value: true, child: Text("On Top")), ComboBoxItem<Bool>(value: false, child: Text("On Bottom"))],
            onChanged: { [weak self] v in if let v { self?.setColorOnTop(i, v) } }))
        if level.on == .cellIcon {
            let have = icons(i)
            guard !have.isEmpty else {
                return [SizedBox(width: 260, height: nil, child: Text("No conditional-format icons here.", style: fluent.typography.caption))]
            }
            return [
                SizedBox(width: 140, height: nil, child: ComboBox<SortIcon>(
                    key: ValueKey("sort-icon-\(i)"), value: level.icon,
                    items: have.map { ic in ComboBoxItem<SortIcon>(value: ic, child: SizedBox(width: 16, height: 16, child: CustomPaint(
                        painter: SortIconPainter(ic), child: SizedBox(expand: ())))) },
                    onChanged: { [weak self] v in if let v { self?.setIcon(i, v) } })),
                SizedBox(width: 8, height: nil, child: nil), place,
            ]
        }
        let have = colors(i)
        guard !have.isEmpty else {
            return [SizedBox(width: 260, height: nil, child: Text(level.on == .cellColor ? "No cell colours here." : "No font colours here.",
                                                               style: fluent.typography.caption))]
        }
        return [
            SizedBox(width: 140, height: nil, child: ComboBox<UInt32>(
                key: ValueKey("sort-color-\(i)"), value: level.color,
                items: have.map { ComboBoxItem<UInt32>(value: $0, child: _swatch($0, fluent)) },
                onChanged: { [weak self] v in if let v { self?.setColor(i, v) } })),
            SizedBox(width: 8, height: nil, child: nil), place,
        ]
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        var rows: [Widget] = [Row(children: [
            SizedBox(width: 64, height: nil, child: nil),
            SizedBox(width: 158, height: nil, child: Text(byColumns ? "Row" : "Column", style: fluent.typography.caption)),
            SizedBox(width: 138, height: nil, child: Text("Sort On", style: fluent.typography.caption)),
            Text("Order", style: fluent.typography.caption),
        ])]
        for (i, level) in levels.enumerated() {
            rows.append(Padding(padding: EdgeInsets(left: 0, top: 4, right: 0, bottom: 4), child: Row(children: [
                SizedBox(width: 64, height: nil, child: Text(i == 0 ? "Sort by" : "Then by", style: fluent.typography.caption)),
                SizedBox(width: 150, height: nil, child: ComboBox<Int>(
                    key: ValueKey("sort-column-\(i)"), value: level.col,
                    items: lines.map { ComboBoxItem<Int>(value: $0, child: Text(columnLabel($0))) },
                    onChanged: { [weak self] v in if let v { self?.setColumn(i, v) } })),
                SizedBox(width: 8, height: nil, child: nil),
                SizedBox(width: 130, height: nil, child: ComboBox<SortOn>(
                    key: ValueKey("sort-on-\(i)"), value: level.on,
                    items: [ComboBoxItem<SortOn>(value: .values, child: Text("Cell Values")),
                            ComboBoxItem<SortOn>(value: .cellColor, child: Text("Cell Color")),
                            ComboBoxItem<SortOn>(value: .fontColor, child: Text("Font Color")),
                            ComboBoxItem<SortOn>(value: .cellIcon, child: Text("Cell Icon"))],
                    onChanged: { [weak self] v in if let v { self?.setSortOn(i, v) } })),
                SizedBox(width: 8, height: nil, child: nil),
            ] + _orderControls(i, level, fluent) + [
                SizedBox(width: 8, height: nil, child: nil),
                Button(key: ValueKey("sort-remove-\(i)"), onPressed: levels.count > 1 ? { [weak self] in self?.removeLevel(i) } : nil, child: Text("Remove")),
            ])))
            if let typed = _typed[i] {
                rows.append(Padding(padding: EdgeInsets(left: 360, top: 0, right: 0, bottom: 4), child: SizedBox(width: 260, height: nil,
                    child: FluentTextBox(key: ValueKey("sort-list-\(i)"), controller: typed, placeholderText: "High, Medium, Low"))))
            }
        }
        let page = Column(mainAxisSize: .min, crossAxisAlignment: .stretch, children: [
            Checkbox(key: ValueKey("sort-has-header"), checked: hasHeader, onChanged: { [weak self] v in self?.setHeader(v ?? false) },
                     content: Text("My data has headers")),
            SizedBox(width: nil, height: 8, child: nil),
        ] + rows + [
            SizedBox(width: nil, height: 6, child: nil),
            Row(children: [Button(key: ValueKey("sort-add-level"), onPressed: { [weak self] in self?.addLevel() }, child: Text("Add Level"))]),
            SizedBox(width: nil, height: 10, child: nil),
            Text("Options", style: fluent.typography.bodyStrong),
            SizedBox(width: nil, height: 4, child: nil),
            Row(children: [
                Checkbox(key: ValueKey("sort-case"), checked: caseSensitive, onChanged: { [weak self] v in self?.setCaseSensitive(v ?? false) },
                         content: Text("Case sensitive")),
                SizedBox(width: 24, height: nil, child: nil),
                Checkbox(key: ValueKey("sort-left-to-right"), checked: byColumns, onChanged: { [weak self] v in self?.setByColumns(v ?? false) },
                         content: Text("Sort left to right")),
            ]),
            SizedBox(width: nil, height: 6, child: nil),
            Text(message, style: fluent.typography.caption?.copyWith(color: Color(0xFFC42B1C))),
        ])
        return DialogShell(title: "Sort", page: page, okLabel: "OK", cancelLabel: "Cancel", width: 760,
                           onOK: { [weak self] in self?.apply() }, onCancel: _w.onClose)
    }
}

/// One conditional-format icon, as the grid draws it, for the Sort dialog's icon list.
final class SortIconPainter: CustomPainter {
    let icon: SortIcon
    init(_ icon: SortIcon) { self.icon = icon; super.init() }
    override func paint(_ canvas: any Canvas, _ size: Size) {
        IconSets.paint(icon.set, icon.index, canvas, in: Rect.fromLTWH(0, 0, size.width, size.height))
    }
    override func shouldRepaint(_ oldDelegate: CustomPainter) -> Bool { (oldDelegate as? SortIconPainter)?.icon != icon }
}
