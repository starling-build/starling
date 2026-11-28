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
    /// Format (Word): what the match must look like, and what the replacement is given.
    var format = FindFormat()
    var replaceFormat = FindFormat()
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
    /// Sheets: Special… beside Go, opening Go To Special.
    var goToSpecial: (() -> Void)? = nil
    /// Word (W-ED-2): the Find / Replace / Go To tabs, the prefix, suffix and ignore options,
    /// Special and Format. Off for Slides and Sheets.
    var wordTabs = false
    /// Format's choices: the font names and the paragraph styles (id, name).
    var fonts: [String] = []
    var styles: [(id: String, name: String)] = []
    /// The Go To tab's "Go to what" list, and going: (what, typed text, step: +1 Next, -1 Previous, 0 Go To).
    var goToKinds: [GoToWhat] = []
    var goToWhat: ((GoToWhat, String, Int) -> String?)? = nil
    /// The bookmark names, for the Go To tab's hint.
    var bookmarks: () -> [String] = { [] }
}

final class FindReplaceDialog: StatefulWidget {
    let initialQuery: String
    let hooks: FindHooks
    let onClose: () -> Void
    /// With `hooks.wordTabs`: 0 Find, 1 Replace, 2 Go To.
    let initialTab: Int
    init(initialQuery: String, hooks: FindHooks, initialTab: Int = 1, onClose: @escaping () -> Void) {
        self.initialQuery = initialQuery
        self.initialTab = initialTab
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
    // Word only (hooks.wordTabs).
    private(set) var tab = 1
    private(set) var prefix = false
    private(set) var suffix = false
    private(set) var ignorePunctuation = false
    private(set) var ignoreSpace = false
    private(set) var format = FindFormat()
    private(set) var replaceFormat = FindFormat()
    /// Which box Special and Format work on: 0 Find what, 1 Replace with (the last one clicked).
    private(set) var target = 0
    private(set) var formatOpen = false
    /// Building the invisible Replace tab that sizes the dialog: no keys, no text boxes.
    private var _ghost = false
    private func _k(_ id: String, _ w: Widget) -> Widget { _ghost ? w : PKeyed(id, w) }
    private(set) var goToIndex = 0

    override func initState() {
        super.initState()
        _query.text = _w.initialQuery
        tab = _w.hooks.wordTabs ? min(max(_w.initialTab, 0), 2) : 1
        target = 0
    }

    func setTab(_ t: Int) { setState { tab = t; formatOpen = false; if t == 0 { target = 0 } } }
    func setTarget(_ t: Int) { setState { target = t } }
    /// The two boxes' text (tests, and Special's insertions).
    var queryText: String { get { _query.text } set { _query.text = newValue } }
    var replacementText: String { get { _replacement.text } set { _replacement.text = newValue } }
    /// Format for the box `target` is on (Find what, or Replace with).
    func setFormat(_ f: FindFormat) { setState { if target == 1 { replaceFormat = f } else { format = f } } }
    var targetFormat: FindFormat { target == 1 ? replaceFormat : format }
    func setGoToWhat(_ k: GoToWhat) {
        guard let i = _w.hooks.goToKinds.firstIndex(of: k) else { return }
        setState { goToIndex = i; status = "" }
    }

    /// Special: put a ^ code into the box `target` is on, at its caret.
    func insertSpecial(_ code: String) {
        let c = target == 1 ? _replacement : _query
        let v = c.value
        let lo = v.selection.isValid ? min(v.selection.baseOffset, v.selection.extentOffset) : v.text.utf16.count
        let hi = v.selection.isValid ? max(v.selection.baseOffset, v.selection.extentOffset) : lo
        let u = Array(v.text.utf16)
        let text = (String(decoding: u[0 ..< lo], as: UTF16.self)) + code + String(decoding: u[hi...], as: UTF16.self)
        let at = lo + code.utf16.count
        c.value = TextEditingValue(text: text, selection: TextSelection(baseOffset: at, extentOffset: at))
        setState {}
    }

    /// Word's Special menu: (label, code). Find what offers the search-only codes; wildcards drop the
    /// ones Word refuses there; Replace with adds Find What Text and a page break.
    var specials: [(String, String)] {
        let mode = modeIndex
        var out: [(String, String)] = []
        if target == 0 {
            if mode == 0 { out.append(("Paragraph Mark", "^p")) }
            out.append(("Tab Character", "^t"))
            if mode == 0 { out += [("Any Character", "^?"), ("Any Digit", "^#"), ("Any Letter", "^$")] }
            out.append(("Caret Character", "^^"))
        } else {
            out += [("Paragraph Mark", "^p"), ("Tab Character", "^t"), ("Caret Character", "^^"), ("Find What Text", "^&")]
        }
        out += [("Em Dash", "^+"), ("En Dash", "^="), ("Manual Line Break", "^l")]
        if target == 1 { out.append(("Manual Page Break", "^m")) }
        out += [("Nonbreaking Hyphen", "^~"), ("Nonbreaking Space", "^s"), ("Optional Hyphen", "^-")]
        if target == 0, mode == 0 { out.append(("White Space", "^w")) }
        return out
    }

    func goToStep(_ step: Int) {
        let kinds = _w.hooks.goToKinds
        guard let hook = _w.hooks.goToWhat, !kinds.isEmpty else { return }
        let s = hook(kinds[min(goToIndex, kinds.count - 1)], step == 0 ? _goTo.text : "", step) ?? ""
        setState { status = s }
        if !s.isEmpty { ScreenReader.announce(s) }
    }

    override func dispose() {
        _query.dispose()
        _replacement.dispose()
        _goTo.dispose()
        super.dispose()
    }

    var place: FindWhere {
        FindWhere(scope: scope, lookIn: lookIn, byColumns: order == 1, format: format,
                  replaceFormat: tab == 1 ? replaceFormat : FindFormat())
    }

    var options: FindOptions {
        FindOptions(matchCase: matchCase, wholeWord: whole && !_w.hooks.wholeIsEntireCell,
                    entireCell: whole && _w.hooks.wholeIsEntireCell,
                    mode: [FindMode.plain, .wildcards, .regex][modeIndex],
                    matchPrefix: _w.hooks.wordTabs && prefix, matchSuffix: _w.hooks.wordTabs && suffix,
                    ignorePunctuation: _w.hooks.wordTabs && ignorePunctuation, ignoreSpace: _w.hooks.wordTabs && ignoreSpace)
    }

    /// The pattern for what is typed, or the reason it cannot be one (shown as the status).
    private func pattern() -> TextPattern? {
        // Word: an empty Find what with a format finds any text that has it.
        if _query.text.isEmpty, !format.isEmpty { return TextPattern.anyText(options) }
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

    /// What is wrong with Replace with, shown instead of replacing (Word refuses ^w, ^? and the like there).
    private func replacementOK() -> Bool {
        guard let problem = TextPattern.replacementProblem(_replacement.text, options.mode) else { return true }
        setState { status = problem }
        return false
    }

    func replaceOne() {
        guard replacementOK(), let p = pattern() else { return }
        let s = _w.hooks.replace(p, _replacement.text, place)
        setState { status = s }
        ScreenReader.announce(s)
    }

    func replaceEvery() {
        guard replacementOK(), let p = pattern() else { return }
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
        let body = fluent.typography.body
        let caption = fluent.typography.caption?.copyWith(color: fluent.resources.textFillColorSecondary)
        func label(_ t: String) -> Widget { SizedBox(width: 90, height: nil, child: Text(t, style: body)) }
        func field(_ c: TextEditingController, _ key: String, submit: @escaping () -> Void, autofocus: Bool = false, box: Int? = nil) -> Widget {
            if _ghost { return Expanded(child: SizedBox(width: nil, height: Chrome.fieldHeight, child: nil)) }
            let tb: Widget = _k(key, FluentTextBox(controller: c, onSubmitted: { _ in submit() }, autofocus: autofocus))
            let inner: Widget = box.map { b in Listener(onPointerDown: { [weak self] _ in self?.setTarget(b) }, behavior: .translucent, child: tb) } ?? tb
            return Expanded(child: SizedBox(width: nil, height: Chrome.fieldHeight, child: inner))
        }
        let gap = SizedBox(width: nil, height: 10, child: nil)
        func hgap(_ w: Double = 8) -> Widget { SizedBox(width: w, height: nil, child: nil) }
        func combo(_ key: String, _ items: [String], _ at: Int, width: Double = 190, _ set: @escaping (FindReplaceDialogState, Int) -> Void) -> Widget {
            SizedBox(width: width, height: nil, child: _k(key, ComboBox<String>(
                value: items[min(max(at, 0), items.count - 1)],
                items: items.map { ComboBoxItem<String>(value: $0, child: Text($0, style: body)) },
                onChanged: { [weak self] v in
                    guard let self, let v, let i = items.firstIndex(of: v) else { return }
                    self.setState { set(self, i) }
                })))
        }
        func check(_ key: String, _ text: String, _ on: Bool, _ set: @escaping (FindReplaceDialogState, Bool) -> Void) -> Widget {
            _k(key, Checkbox(checked: on, onChanged: { [weak self] v in guard let self else { return }; self.setState { set(self, v ?? false) } },
                                 content: Text(text, style: body)))
        }
        func makePage(_ tab: Int) -> [Widget] {
            var page: [Widget] = []
            if h.wordTabs {
                func tabButton(_ key: String, _ name: String, _ t: Int) -> Widget {
                    _k(key, Chrome.textToggle(name, tab == t, fluent) { [weak self] in self?.setTab(t) })
                }
                page.append(Padding(padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 12), child: Row(children: [
                    tabButton("fr-tab-find", "Find", 0), tabButton("fr-tab-replace", "Replace", 1),
                ] + (h.goToKinds.isEmpty ? [] : [tabButton("fr-tab-goto", "Go To", 2)]))))
            }
            if tab == 2 {
                page += _goToPage(fluent, label: label, field: field, combo: combo)
            } else {
                page.append(Row(crossAxisAlignment: .center, children: [label("Find what"),
                    field(_query, "fr-query", submit: { [weak self] in self?.next() }, autofocus: true, box: 0)]))
                if !format.isEmpty {
                    page.append(Padding(padding: EdgeInsets(left: 90, top: 2, right: 0, bottom: 0),
                                        child: _k("fr-format-find", Text("Format: " + format.describe(styleName: _styleName), style: caption))))
                }
                if tab == 1 {
                    page.append(gap)
                    page.append(Row(crossAxisAlignment: .center, children: [label("Replace with"),
                        field(_replacement, "fr-replace", submit: { [weak self] in self?.replaceOne() }, box: 1)]))
                    if !replaceFormat.isEmpty {
                        page.append(Padding(padding: EdgeInsets(left: 90, top: 2, right: 0, bottom: 0),
                                            child: _k("fr-format-replace", Text("Format: " + replaceFormat.describe(styleName: _styleName), style: caption))))
                    }
                }
                page.append(gap)
                page.append(check("fr-case", "Match case", matchCase) { $0.matchCase = $1 })
                page.append(check("fr-whole", h.wholeLabel, whole) { $0.whole = $1 })
                if h.wordTabs {
                    page.append(check("fr-prefix", "Match prefix", prefix) { $0.prefix = $1 })
                    page.append(check("fr-suffix", "Match suffix", suffix) { $0.suffix = $1 })
                    page.append(check("fr-ignore-punct", "Ignore punctuation characters", ignorePunctuation) { $0.ignorePunctuation = $1 })
                    page.append(check("fr-ignore-space", "Ignore white-space characters", ignoreSpace) { $0.ignoreSpace = $1 })
                }
                page.append(gap)
                page.append(Row(crossAxisAlignment: .center, children: [label("Match using"),
                    combo("fr-mode", Self.modes, modeIndex) { $0.modeIndex = $1 }]))
                func choice(_ name: String, _ key: String, _ items: [String], _ at: Int, _ set: @escaping (FindReplaceDialogState, Int) -> Void) {
                    guard !items.isEmpty else { return }
                    page.append(gap)
                    page.append(Row(crossAxisAlignment: .center, children: [label(name), combo(key, items, at, set)]))
                }
                choice("Search in", "fr-scope", h.scopes, scope) { $0.scope = $1 }
                choice("Search", "fr-order", h.orders, order) { $0.order = $1 }
                choice("Look in", "fr-lookin", h.lookIns, lookIn) { $0.lookIn = $1 }
                if h.wordTabs {
                    page.append(gap)
                    let box = target == 1 ? "Replace with" : "Find what"
                    page.append(Row(crossAxisAlignment: .center, children: [
                        _k("fr-format", Chrome.textToggle("Format…", formatOpen, fluent) { [weak self] in
                            self?.setState { self?.formatOpen.toggle() } }),
                        hgap(),
                        _k("fr-special", Chrome.menuButton(nil, "Special", nil, fluent, items: specials.map { s in
                            MenuFlyoutItem(text: Padding(key: ValueKey("fr-sp-" + s.1), padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 0), child: Text(s.0)),
                                           onPressed: { [weak self] in self?.insertSpecial(s.1) }) as MenuFlyoutItemBase })),
                        hgap(),
                        _k("fr-no-format", Chrome.textToggle("No Formatting", false, fluent) { [weak self] in self?.setFormat(FindFormat()) }),
                        hgap(12),
                        Text("For: " + box, style: caption),
                    ]))
                    if formatOpen, !_ghost { page.append(_formatPanel(fluent, label: label, combo: combo)) }
                }
                page.append(gap)
                var buttons: [Widget] = [Button(onPressed: { [weak self] in self?.next(backwards: true) }, child: Text("Find Previous"))]
                if tab == 1 {
                    buttons += [hgap(), Button(onPressed: { [weak self] in self?.replaceOne() }, child: Text("Replace")),
                                hgap(), Button(onPressed: { [weak self] in self?.replaceEvery() }, child: Text("Replace All"))]
                }
                if h.findAll != nil {
                    buttons += [hgap(), Button(onPressed: { [weak self] in self?.listAll() }, child: Text("Find All"))]
                }
                page.append(Row(children: buttons))
                if let hits, !_ghost {
                    page.append(gap)
                    page.append(_list(hits, fluent))
                }
                if h.goTo != nil, !h.wordTabs {
                    page.append(SizedBox(width: nil, height: 14, child: nil))
                    page.append(Row(crossAxisAlignment: .center, children: [label(h.goToLabel),
                        field(_goTo, "fr-goto", submit: { [weak self] in self?.goTo() }),
                        hgap(),
                        Button(onPressed: { [weak self] in self?.goTo() }, child: Text("Go"))]
                        + (h.goToSpecial.map { special in [hgap(),
                            Button(key: ValueKey("fr-gotospecial"), onPressed: { [weak self] in self?._w.onClose(); special() }, child: Text("Special…"))] } ?? [])))
                    if !h.goToHint.isEmpty {
                        page.append(Padding(padding: EdgeInsets(left: 90, top: 2, right: 0, bottom: 0), child: Text(h.goToHint, style: caption)))
                    }
                }
            }
            page.append(SizedBox(width: nil, height: 10, child: nil))
            page.append(Text(status, style: caption))
            return page
        }
        let page = makePage(tab)
        // Word keeps the dialog one size on its three tabs: each is laid out over an invisible Replace tab
        // (Format's panel and Find All's list still make it taller, as Word's More does).
        var content: Widget = Column(crossAxisAlignment: .stretch, children: page)
        if h.wordTabs {
            _ghost = true; let sizer = makePage(1); _ghost = false
            content = Stack(children: [content, IgnorePointer(child: ExcludeSemantics(child: Opacity(opacity: 0, child: Column(crossAxisAlignment: .stretch, children: sizer))))])
        }
        if tab == 2 {
            return DialogShell(title: "Find and Replace", page: content,
                               okLabel: _goTo.text.isEmpty ? "Next" : "Go To", cancelLabel: "Close", width: 520,
                               onOK: { [weak self] in guard let self else { return }; self.goToStep(self._goTo.text.isEmpty ? 1 : 0) },
                               onCancel: _w.onClose)
        }
        return DialogShell(title: "Find and Replace", page: content,
                           okLabel: "Find Next", cancelLabel: "Close", width: 520,
                           onOK: { [weak self] in self?.next() }, onCancel: _w.onClose)
    }

    private func _styleName(_ id: String) -> String { _w.hooks.styles.first { $0.id == id }?.name ?? id }

    /// Go To: Go to what, the box, Previous / Next (Go To when something is typed).
    private func _goToPage(_ fluent: FluentThemeData, label: (String) -> Widget,
                           field: (TextEditingController, String, @escaping () -> Void, Bool, Int?) -> Widget,
                           combo: (String, [String], Int, Double, @escaping (FindReplaceDialogState, Int) -> Void) -> Widget) -> [Widget] {
        let kinds = _w.hooks.goToKinds
        let what = kinds[min(goToIndex, kinds.count - 1)]
        let caption = fluent.typography.caption?.copyWith(color: fluent.resources.textFillColorSecondary)
        var hint = "Enter + and - to move relative to the current location. Example: +4 will move forward four items."
        if what == .bookmark {
            let names = _w.hooks.bookmarks()
            hint = names.isEmpty ? "The document has no bookmarks." : "Bookmarks: " + names.joined(separator: ", ")
        }
        return [
            Row(crossAxisAlignment: .center, children: [label("Go to what"),
                combo("fr-goto-what", kinds.map(\.rawValue), goToIndex, 190) { $0.goToIndex = $1; $0.status = "" }]),
            SizedBox(width: nil, height: 10, child: nil),
            Row(crossAxisAlignment: .center, children: [
                SizedBox(width: 160, height: nil, child: Text(what.prompt, style: fluent.typography.body)),
                field(_goTo, "fr-goto", { [weak self] in guard let self else { return }; self.goToStep(self._goTo.text.isEmpty ? 1 : 0) }, true, nil)]),
            Padding(padding: EdgeInsets(left: 160, top: 2, right: 0, bottom: 0), child: Text(hint, style: caption)),
            SizedBox(width: nil, height: 10, child: nil),
            Row(children: [
                PKeyed("fr-goto-prev", Button(onPressed: { [weak self] in self?.goToStep(-1) }, child: Text("Previous"))),
                SizedBox(width: 8, height: nil, child: nil),
                PKeyed("fr-goto-next", Button(onPressed: { [weak self] in self?.goToStep(1) }, child: Text("Next"))),
                SizedBox(width: 8, height: nil, child: nil),
                PKeyed("fr-goto-go", Button(onPressed: { [weak self] in self?.goToStep(0) }, child: Text("Go To"))),
            ]),
        ]
    }

    /// Format: each part Any ("—"), on or off; the font, size and paragraph style. For the box `target` is on.
    private func _formatPanel(_ fluent: FluentThemeData, label: (String) -> Widget,
                              combo: (String, [String], Int, Double, @escaping (FindReplaceDialogState, Int) -> Void) -> Widget) -> Widget {
        let f = targetFormat
        let tri = ["—", "On", "Off"]
        func at(_ v: Bool?) -> Int { v.map { $0 ? 1 : 2 } ?? 0 }
        func val(_ i: Int) -> Bool? { i == 0 ? nil : i == 1 }
        func flag(_ key: String, _ name: String, _ v: Bool?, _ set: @escaping (inout FindFormat, Bool?) -> Void) -> Widget {
            Row(crossAxisAlignment: .center, children: [label(name), combo(key, tri, at(v), 120) { st, i in
                var g = st.targetFormat; set(&g, val(i))
                if st.target == 1 { st.replaceFormat = g } else { st.format = g }
            }])
        }
        let fonts = ["—"] + _w.hooks.fonts
        let sizes = ["—", "8", "9", "10", "10.5", "11", "12", "14", "16", "18", "20", "24", "28", "36", "48", "72"]
        let styles = ["—"] + _w.hooks.styles.map(\.name)
        let sizeText = f.fontSize.map { $0 == $0.rounded() ? String(Int($0)) : String($0) }
        let gap = SizedBox(width: nil, height: 6, child: nil)
        func set(_ st: FindReplaceDialogState, _ change: (inout FindFormat) -> Void) {
            var g = st.targetFormat; change(&g)
            if st.target == 1 { st.replaceFormat = g } else { st.format = g }
        }
        let hooks = _w.hooks
        return Padding(padding: EdgeInsets(left: 0, top: 8, right: 0, bottom: 0), child: Column(crossAxisAlignment: .stretch, children: [
            Row(crossAxisAlignment: .center, children: [label("Font"), combo("fr-fmt-font", fonts, fonts.firstIndex(of: f.fontFamily ?? "—") ?? 0, 190) { st, i in
                set(st) { $0.fontFamily = i == 0 ? nil : hooks.fonts[i - 1] } }]),
            gap,
            Row(crossAxisAlignment: .center, children: [label("Size"), combo("fr-fmt-size", sizes, sizeText.flatMap { sizes.firstIndex(of: $0) } ?? 0, 120) { st, i in
                set(st) { $0.fontSize = i == 0 ? nil : Double(sizes[i]) } }]),
            gap,
            flag("fr-fmt-bold", "Bold", f.bold) { $0.bold = $1 }, gap,
            flag("fr-fmt-italic", "Italic", f.italic) { $0.italic = $1 }, gap,
            flag("fr-fmt-underline", "Underline", f.underline) { $0.underline = $1 }, gap,
            flag("fr-fmt-strike", "Strikethrough", f.strikethrough) { $0.strikethrough = $1 }, gap,
            flag("fr-fmt-highlight", "Highlight", f.highlight) { $0.highlight = $1 }, gap,
            Row(crossAxisAlignment: .center, children: [label("Style"), combo("fr-fmt-style", styles, f.paragraphStyle.flatMap { id in hooks.styles.firstIndex { $0.id == id }.map { $0 + 1 } } ?? 0, 190) { st, i in
                set(st) { $0.paragraphStyle = i == 0 ? nil : hooks.styles[i - 1].id } }]),
        ]))
    }
}
