// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The one Find and Replace / Go To dialog (U-shared, U-FR-1), on DialogShell. Writer, Slides
// and Sheets each hand it a `FindHooks`: what "next", "replace" and "replace all" do in that
// app's model, the scopes it offers, and what Go To means there. The dialog owns the query,
// the options and the pattern; it never touches a model.

import Flutter
import FlutterSwiftBridge
import OfficeText

/// Where the dialog asks the app to look: the "Search in" scope and, where offered,
/// Excel's "Look in" and "Search" (by rows or by columns) choices, as indexes.
struct FindWhere: Equatable, Sendable {
    var scope = 0
    var lookIn = 0
    var byColumns = false
}

/// One line of the Find All list.
struct FindListHit {
    var place: String
    var cell: String
    var value: String
    var formula: String
    var go: () -> Void
}

struct FindHooks {
    /// The label of the whole-word / entire-cell option.
    var wholeLabel = "Find whole words only"
    /// True in Sheets: the option means the whole cell, so it sets `entireCell`.
    var wholeIsEntireCell = false
    /// "Search in": empty hides the choice (Writer, Slides); Sheets offers Sheet and Workbook.
    var scopes: [String] = []
    /// "Look in" (Sheets: Formulas, Values, Notes) and "Search" (By Rows, By Columns): empty hides each.
    var lookIns: [String] = []
    var orders: [String] = []
    /// Each returns the status line to show ("" for none).
    var findNext: (_ pattern: TextPattern, _ where: FindWhere, _ backwards: Bool) -> String
    var replace: (_ pattern: TextPattern, _ template: String, _ where: FindWhere) -> String
    var replaceAll: (_ pattern: TextPattern, _ template: String, _ where: FindWhere) -> String
    /// Find All: every match, listed under the buttons; nil hides the button.
    var findAll: ((_ pattern: TextPattern, _ where: FindWhere) -> [FindListHit])? = nil
    /// Go To: nil when it worked, else what was wrong with the text typed.
    var goTo: ((String) -> String?)? = nil
    var goToLabel = "Go to"
    var goToHint = ""
}

final class FindReplaceDialog: StatefulWidget {
    let initialQuery: String
    let hooks: FindHooks
    let onClose: () -> Void
    init(initialQuery: String, hooks: FindHooks, onClose: @escaping () -> Void) {
        self.initialQuery = initialQuery
        self.hooks = hooks
        self.onClose = onClose
        super.init()
    }
    override func createState() -> State<StatefulWidget> { FindReplaceDialogState() }
}

final class FindReplaceDialogState: State<StatefulWidget> {
    private var _w: FindReplaceDialog { widget as! FindReplaceDialog }
    private let _query = TextEditingController()
    private let _replacement = TextEditingController()
    private let _goTo = TextEditingController()
    private(set) var matchCase = false
    private(set) var whole = false
    private(set) var modeIndex = 0
    private(set) var scope = 0
    private(set) var lookIn = 0
    private(set) var order = 0
    private(set) var status = ""
    /// The last Find All list; nil before the first.
    private(set) var hits: [FindListHit]? = nil
    static let modes = ["Normal", "Wildcards", "Regular expression"]

    override func initState() {
        super.initState()
        _query.text = _w.initialQuery
    }

    override func dispose() {
        _query.dispose()
        _replacement.dispose()
        _goTo.dispose()
        super.dispose()
    }

    var place: FindWhere { FindWhere(scope: scope, lookIn: lookIn, byColumns: order == 1) }

    var options: FindOptions {
        FindOptions(matchCase: matchCase, wholeWord: whole && !_w.hooks.wholeIsEntireCell,
                    entireCell: whole && _w.hooks.wholeIsEntireCell,
                    mode: [FindMode.plain, .wildcards, .regex][modeIndex])
    }

    /// The pattern for what is typed, or the reason it cannot be one (shown as the status).
    private func pattern() -> TextPattern? {
        do { return try TextPattern(_query.text, options) } catch {
            setState { status = "\(error)" }
            return nil
        }
    }

    func next(backwards: Bool = false) {
        guard let p = pattern() else { return }
        let s = _w.hooks.findNext(p, place, backwards)
        setState { status = s }
        ScreenReader.announce(s)
    }

    func replaceOne() {
        guard let p = pattern() else { return }
        let s = _w.hooks.replace(p, _replacement.text, place)
        setState { status = s }
        ScreenReader.announce(s)
    }

    func replaceEvery() {
        guard let p = pattern() else { return }
        let s = _w.hooks.replaceAll(p, _replacement.text, place)
        setState { status = s }
        ScreenReader.announce(s)
    }

    /// Find All: list every match under the buttons; a line goes to its cell.
    func listAll() {
        guard let hook = _w.hooks.findAll, let p = pattern() else { return }
        let found = hook(p, place)
        let s = found.isEmpty ? "No matches" : found.count == 1 ? "1 cell found" : "\(found.count) cells found"
        setState { hits = found; status = s }
        ScreenReader.announce(s)
    }

    func goTo() {
        guard let hook = _w.hooks.goTo else { return }
        let err = hook(_goTo.text)
        if err == nil { _w.onClose() } else { setState { status = err ?? "" } }
    }

    /// The Find All list, Excel's columns: where, cell, value, formula. A click goes to the cell.
    private func _list(_ hits: [FindListHit], _ fluent: FluentThemeData) -> Widget {
        let body = fluent.typography.body
        func line(_ a: String, _ b: String, _ c: String, _ d: String, bold: Bool = false) -> Widget {
            let st = bold ? body?.copyWith(fontWeight: .w600) : body
            func cell(_ t: String, _ w: Double?) -> Widget {
                let tx = Text(t, style: st, overflow: .ellipsis, maxLines: 1)
                return w.map { SizedBox(width: $0, height: nil, child: tx) } ?? Expanded(child: tx)
            }
            return Padding(padding: EdgeInsets(left: 6, top: 3, right: 6, bottom: 3),
                           child: Row(children: [cell(a, 110), cell(b, 60), cell(c, 140), cell(d, nil)]))
        }
        let rows: [Widget] = hits.map { hit in
            let label = "\(hit.place) \(hit.cell) \(hit.value)"
            return KeyboardRow(label: label, activate: hit.go,
                               child: GestureDetector(onTap: hit.go, behavior: .opaque, child: line(hit.place, hit.cell, hit.value, hit.formula)))
        }
        return Column(crossAxisAlignment: .stretch, children: [
            line("Sheet", "Cell", "Value", "Formula", bold: true),
            SizedBox(width: nil, height: 120, child: SingleChildScrollView(child: Column(crossAxisAlignment: .stretch, children: rows))),
        ])
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let h = _w.hooks
        func label(_ t: String) -> Widget { SizedBox(width: 90, height: nil, child: Text(t, style: fluent.typography.body)) }
        func field(_ c: TextEditingController, _ key: String, submit: @escaping () -> Void, autofocus: Bool = false) -> Widget {
            Expanded(child: SizedBox(width: nil, height: Chrome.fieldHeight, child: PKeyed(key, FluentTextBox(
                controller: c, onSubmitted: { _ in submit() }, autofocus: autofocus))))
        }
        let gap = SizedBox(width: nil, height: 10, child: nil)
        var page: [Widget] = [
            Row(crossAxisAlignment: .center, children: [label("Find what"),
                field(_query, "fr-query", submit: { [weak self] in self?.next() }, autofocus: true)]),
            gap,
            Row(crossAxisAlignment: .center, children: [label("Replace with"),
                field(_replacement, "fr-replace", submit: { [weak self] in self?.replaceOne() })]),
            gap,
            Checkbox(checked: matchCase, onChanged: { [weak self] v in self?.setState { self?.matchCase = v ?? false } },
                     content: Text("Match case", style: fluent.typography.body)),
            Checkbox(checked: whole, onChanged: { [weak self] v in self?.setState { self?.whole = v ?? false } },
                     content: Text(h.wholeLabel, style: fluent.typography.body)),
            gap,
            Row(crossAxisAlignment: .center, children: [label("Match using"),
                SizedBox(width: 190, height: nil, child: ComboBox<String>(
                    value: Self.modes[modeIndex],
                    items: Self.modes.map { ComboBoxItem<String>(value: $0, child: Text($0, style: fluent.typography.body)) },
                    onChanged: { [weak self] v in
                        guard let self, let v, let i = Self.modes.firstIndex(of: v) else { return }
                        self.setState { self.modeIndex = i }
                    }))]),
        ]
        func choice(_ name: String, _ items: [String], _ at: Int, _ set: @escaping (FindReplaceDialogState, Int) -> Void) {
            guard !items.isEmpty else { return }
            page.append(gap)
            page.append(Row(crossAxisAlignment: .center, children: [label(name),
                SizedBox(width: 190, height: nil, child: ComboBox<String>(
                    value: items[min(at, items.count - 1)],
                    items: items.map { ComboBoxItem<String>(value: $0, child: Text($0, style: fluent.typography.body)) },
                    onChanged: { [weak self] v in
                        guard let self, let v, let i = items.firstIndex(of: v) else { return }
                        self.setState { set(self, i) }
                    }))]))
        }
        choice("Search in", h.scopes, scope) { $0.scope = $1 }
        choice("Search", h.orders, order) { $0.order = $1 }
        choice("Look in", h.lookIns, lookIn) { $0.lookIn = $1 }
        page.append(gap)
        page.append(Row(children: [
            Button(onPressed: { [weak self] in self?.next(backwards: true) }, child: Text("Find Previous")),
            SizedBox(width: 8, height: nil, child: nil),
            Button(onPressed: { [weak self] in self?.replaceOne() }, child: Text("Replace")),
            SizedBox(width: 8, height: nil, child: nil),
            Button(onPressed: { [weak self] in self?.replaceEvery() }, child: Text("Replace All")),
        ] + (h.findAll == nil ? [] : [
            SizedBox(width: 8, height: nil, child: nil),
            Button(onPressed: { [weak self] in self?.listAll() }, child: Text("Find All")),
        ])))
        if let hits {
            page.append(gap)
            page.append(_list(hits, fluent))
        }
        if h.goTo != nil {
            page.append(SizedBox(width: nil, height: 14, child: nil))
            page.append(Row(crossAxisAlignment: .center, children: [label(h.goToLabel),
                field(_goTo, "fr-goto", submit: { [weak self] in self?.goTo() }),
                SizedBox(width: 8, height: nil, child: nil),
                Button(onPressed: { [weak self] in self?.goTo() }, child: Text("Go"))]))
            if !h.goToHint.isEmpty {
                page.append(Padding(padding: EdgeInsets(left: 90, top: 2, right: 0, bottom: 0),
                                    child: Text(h.goToHint, style: fluent.typography.caption?.copyWith(color: fluent.resources.textFillColorSecondary))))
            }
        }
        page.append(SizedBox(width: nil, height: 10, child: nil))
        page.append(Text(status, style: fluent.typography.caption?.copyWith(color: fluent.resources.textFillColorSecondary)))
        return DialogShell(title: "Find and Replace", page: Column(crossAxisAlignment: .stretch, children: page),
                           okLabel: "Find Next", cancelLabel: "Close", width: 520,
                           onOK: { [weak self] in self?.next() }, onCancel: _w.onClose)
    }
}
