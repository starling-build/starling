// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// A filter dropdown's panel, as Excel's: sort the table by this column,
// clear this column's filter, search the values, tick the ones to show,
// OK. The value rows are a lazy list, which does not rebuild its rows when
// the panel does — so each row listens to the ticks itself.

import Flutter
import FlutterSwiftBridge
import FluentSystemIcons
import Foundation

/// The ticked values, shared by every row of the list.
final class _FilterTicks: ChangeNotifier {
    var checked: Set<String>
    init(_ checked: Set<String>) { self.checked = checked }
    func set(_ value: String, _ on: Bool) {
        if on { checked.insert(value) } else { checked.remove(value) }
        notifyListeners()
    }
    func setAll(_ values: [String], _ on: Bool) {
        if on { checked.formUnion(values) } else { checked.subtract(values) }
        notifyListeners()
    }
}

final class FilterPanel: StatefulWidget {
    let controller: WorkbookController
    let col: Int
    let onClose: () -> Void

    init(controller: WorkbookController, col: Int, onClose: @escaping () -> Void) {
        self.controller = controller
        self.col = col
        self.onClose = onClose
        super.init()
    }

    override func createState() -> State<StatefulWidget> { FilterPanelState() }
}

final class FilterPanelState: State<StatefulWidget> {
    private var _w: FilterPanel { widget as! FilterPanel }
    private var _values: [String] = []
    private var _ticks = _FilterTicks([])
    private let _search = TextEditingController()
    private var _query = ""

    override func initState() {
        super.initState()
        let c = _w.controller
        _values = c.filterValues(col: _w.col)
        let allowed = c.sheet.autoFilter?.columns[_w.col]
        _ticks = _FilterTicks(allowed.map { Set(_values).intersection($0) } ?? Set(_values))
    }

    override func dispose() {
        _search.dispose()
        _ticks.dispose()
        super.dispose()
    }

    private var _shown: [String] {
        _query.isEmpty ? _values : _values.filter { $0.lowercased().containsSubstring(_query.lowercased()) }
    }

    private func _apply() {
        let c = _w.controller
        let shown = _shown
        // With a search, only what matches it and is ticked shows (Excel's
        // default "Select All Search Results").
        var allowed = _query.isEmpty ? _ticks.checked : _ticks.checked.intersection(shown)
        allowed = allowed.intersection(_values)
        c.setFilter(col: _w.col, allowed: allowed.count == _values.count ? nil : allowed)
        _w.onClose()
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let c = _w.controller
        let col = _w.col
        let filtered = c.sheet.autoFilter?.columns[col] != nil
        let header = CellAddress.columnName(col)
        let title = c.filterText(CellAddress(row: c.sheet.autoFilter?.range.top ?? 0, col: col))
        let name = title.isEmpty ? "Column \(header)" : "“\(title)”"
        let close = _w.onClose
        func action(_ icon: IconData, _ label: String, enabled: Bool = true, _ run: @escaping () -> Void) -> Widget {
            FlyoutListTile(onPressed: enabled ? { run(); close() } : nil,
                           icon: Icon(icon, size: 16, color: fluent.resources.textFillColorPrimary),
                           text: Text(label), margin: EdgeInsets(left: 0, top: 0, right: 0, bottom: 1))
        }
        let shown = _shown
        let ticks = _ticks
        let all = AnimatedBuilder(animation: ticks, builder: { _, _ in
            let on = shown.allSatisfy { ticks.checked.contains($0) }
            let some = shown.contains { ticks.checked.contains($0) }
            return Checkbox(checked: on ? true : some ? nil : false,
                            onChanged: { _ in ticks.setAll(shown, !on) },
                            content: Text(self._query.isEmpty ? "(Select All)" : "(Select All Search Results)"))
        })
        let list = ListView(key: ValueKey("filter-\(col)-\(_query)"), itemCount: shown.count) { _, i in
            guard i < shown.count else { return SizedBox(width: 0, height: 0, child: nil) }
            let v = shown[i]
            return AnimatedBuilder(animation: ticks, builder: { _, _ in
                Padding(padding: EdgeInsets(left: 0, top: 3, right: 0, bottom: 3), child: Checkbox(
                    checked: ticks.checked.contains(v),
                    onChanged: { on in ticks.set(v, on ?? false) },
                    content: Text(v.isEmpty ? "(Blanks)" : v, maxLines: 1)))
            })
        }
        return FlyoutContent(
            child: SizedBox(width: 260, height: nil, child: Column(mainAxisSize: .min, crossAxisAlignment: .stretch, children: [
                action(FluentSystemIcons.sort, "Sort A to Z") { c.sortFilter(col: col, ascending: true) },
                action(FluentSystemIcons.sort, "Sort Z to A") { c.sortFilter(col: col, ascending: false) },
                Padding(padding: EdgeInsets(left: 0, top: 4, right: 0, bottom: 4),
                        child: SizedBox(width: nil, height: 1, child: ColoredBox(color: fluent.resources.dividerStrokeColorDefault))),
                action(FluentSystemIcons.close, "Clear Filter From \(name)", enabled: filtered) {
                    c.setFilter(col: col, allowed: nil)
                },
                Chrome.gap(6),
                SizedBox(width: nil, height: 30, child: FluentTextBox(
                    controller: _search, placeholderText: "Search",
                    onChanged: { [weak self] q in self?.setState { self?._query = q } },
                    onSubmitted: { [weak self] _ in self?._apply() })),
                Chrome.gap(6),
                all,
                SizedBox(width: nil, height: min(220, Double(max(1, shown.count)) * 28), child: list),
                Chrome.gap(8),
                Row(mainAxisAlignment: .end, children: [
                    FilledButton(onPressed: { [weak self] in self?._apply() }, child: Text("OK")),
                    Chrome.gap(6),
                    Button(onPressed: close, child: Text("Cancel")),
                ]),
            ])))
    }
}
