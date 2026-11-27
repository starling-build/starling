// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The one Find and Replace / Go To dialog (U-shared, U-FR-1), on DialogShell. Writer, Slides
// and Sheets each hand it a `FindHooks`: what "next", "replace" and "replace all" do in that
// app's model, the scopes it offers, and what Go To means there. The dialog owns the query,
// the options and the pattern; it never touches a model.

import Flutter
import FlutterSwiftBridge
import OfficeText

struct FindHooks {
    /// The label of the whole-word / entire-cell option.
    var wholeLabel = "Find whole words only"
    /// True in Sheets: the option means the whole cell, so it sets `entireCell`.
    var wholeIsEntireCell = false
    /// "Search in": empty hides the choice (Writer, Slides); Sheets offers Sheet and Workbook.
    var scopes: [String] = []
    /// Each returns the status line to show ("" for none). `scope` indexes `scopes`.
    var findNext: (_ pattern: TextPattern, _ scope: Int, _ backwards: Bool) -> String
    var replace: (_ pattern: TextPattern, _ template: String, _ scope: Int) -> String
    var replaceAll: (_ pattern: TextPattern, _ template: String, _ scope: Int) -> String
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
    private(set) var status = ""
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
        let s = _w.hooks.findNext(p, scope, backwards)
        setState { status = s }
        ScreenReader.announce(s)
    }

    func replaceOne() {
        guard let p = pattern() else { return }
        let s = _w.hooks.replace(p, _replacement.text, scope)
        setState { status = s }
        ScreenReader.announce(s)
    }

    func replaceEvery() {
        guard let p = pattern() else { return }
        let s = _w.hooks.replaceAll(p, _replacement.text, scope)
        setState { status = s }
        ScreenReader.announce(s)
    }

    func goTo() {
        guard let hook = _w.hooks.goTo else { return }
        let err = hook(_goTo.text)
        if err == nil { _w.onClose() } else { setState { status = err ?? "" } }
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
        if !h.scopes.isEmpty {
            page.append(gap)
            page.append(Row(crossAxisAlignment: .center, children: [label("Search in"),
                SizedBox(width: 190, height: nil, child: ComboBox<String>(
                    value: h.scopes[min(scope, h.scopes.count - 1)],
                    items: h.scopes.map { ComboBoxItem<String>(value: $0, child: Text($0, style: fluent.typography.body)) },
                    onChanged: { [weak self] v in
                        guard let self, let v, let i = h.scopes.firstIndex(of: v) else { return }
                        self.setState { self.scope = i }
                    }))]))
        }
        page.append(gap)
        page.append(Row(children: [
            Button(onPressed: { [weak self] in self?.next(backwards: true) }, child: Text("Find Previous")),
            SizedBox(width: 8, height: nil, child: nil),
            Button(onPressed: { [weak self] in self?.replaceOne() }, child: Text("Replace")),
            SizedBox(width: 8, height: nil, child: nil),
            Button(onPressed: { [weak self] in self?.replaceEvery() }, child: Text("Replace All")),
        ]))
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
