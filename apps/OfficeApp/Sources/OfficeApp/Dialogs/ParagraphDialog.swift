// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// W-PA-1: the Paragraph dialog. Every setting of a paragraph's layout in one place:
// alignment, left/right indent, first-line or hanging indent, space before/after,
// and the line height (single / 1.5 / double / a multiple / at least / exactly).
// OK applies all of it as one undoable step (`setParagraphFormat`).

import Flutter
import FlutterSwiftBridge
import OfficeText

/// Gives a control a stable id so a test (and a driver) can reach it.
final class PKeyed: StatelessWidget {
    let child: Widget
    init(_ id: String, _ child: Widget) { self.child = child; super.init(key: ValueKey(id)) }
    override func build(_ context: any BuildContext) -> Widget { child }
}

enum ParagraphSpecial { case none, firstLine, hanging }
enum ParagraphLineKind { case single, oneHalf, double, multiple, atLeast, exactly }

/// The kinds of tab the Tabs page offers. A bar is Word's own kind: it draws a rule, no text stops at it.
enum TabKind: CaseIterable {
    case left, center, right, decimal, bar
    var title: String { ["Left", "Center", "Right", "Decimal", "Bar"][TabKind.allCases.firstIndex(of: self)!] }
    var id: String { ["left", "center", "right", "decimal", "bar"][TabKind.allCases.firstIndex(of: self)!] }
    init(_ t: TabStop) {
        if t.rawKind == "bar" { self = .bar; return }
        switch t.alignment { case .left: self = .left; case .center: self = .center
        case .right: self = .right; case .decimal: self = .decimal }
    }
}

/// The fill drawn before a tab.
enum TabLeader: CaseIterable {
    case none, dots, dashes, line
    var title: String { ["None", "Dots", "Dashes", "Line"][TabLeader.allCases.firstIndex(of: self)!] }
    var id: String { ["none", "dots", "dashes", "line"][TabLeader.allCases.firstIndex(of: self)!] }
    var word: String? { [nil, "dot", "hyphen", "underscore"][TabLeader.allCases.firstIndex(of: self)!] }
    init(_ t: TabStop) {
        switch t.leader { case "dot"?: self = .dots; case "hyphen"?: self = .dashes
        case "underscore"?, "heavy"?: self = .line; default: self = .none }
    }
}

/// The tab stops under edit: Set puts a stop at a position (replacing the one there), Clear takes it away.
struct TabStopEditor: Equatable {
    var stops: [TabStop]
    static let same = 0.5   // points: two positions this close are one stop

    func index(at pos: Double) -> Int? { stops.firstIndex { abs($0.position - pos) < Self.same } }

    mutating func set(at pos: Double, kind: TabKind, leader: TabLeader) {
        guard pos >= 0 else { return }
        var t = TabStop(position: pos, alignment: kind == .bar ? .left : TabStop.Alignment(rawValue: TabKind.allCases.firstIndex(of: kind)!)!)
        t.rawKind = kind == .bar ? "bar" : nil
        t.leader = leader.word
        if let i = index(at: pos) { stops[i] = t } else { stops.append(t) }
        stops.sort { $0.position < $1.position }
    }
    mutating func clear(at pos: Double) { if let i = index(at: pos) { stops.remove(at: i) } }
    mutating func clearAll() { stops = [] }
}

/// The dialog's values, kept apart from the widgets so they can be made from a style and turned back into one.
struct ParagraphDialogValues: Equatable {
    var alignment: ParagraphAlignment
    var left: Double, right: Double
    var special: ParagraphSpecial
    var by: Double
    var before: Double, after: Double
    var line: ParagraphLineKind
    var multiple: Double
    var points: Double
    var tabs: TabStopEditor
    /// "Don't add space between paragraphs of the same style".
    var contextual: Bool
    /// W-PA-2, the Line and Page Breaks page.
    var widow: Bool, keepNext: Bool, keepLines: Bool, breakBefore: Bool, noLineNumbers: Bool, noHyphens: Bool

    init(_ s: RichParagraphStyle) {
        contextual = s.contextualSpacing
        widow = s.widowControl; keepNext = s.keepNext; keepLines = s.keepLines
        breakBefore = s.pageBreakBefore && !s.pageBreakInline
        noLineNumbers = s.eastAsian["w:suppressLineNumbers"] == "1"; noHyphens = s.eastAsian["w:suppressAutoHyphens"] == "1"
        alignment = s.alignment; left = s.indentLeft; right = s.indentRight
        special = s.firstLineIndent < 0 ? .hanging : s.firstLineIndent > 0 ? .firstLine : .none
        by = abs(s.firstLineIndent)
        before = s.spaceBefore; after = s.spaceAfter
        multiple = s.lineSpacing; points = 12
        tabs = TabStopEditor(stops: s.tabStops)
        if let p = s.lineHeightPoints {
            line = s.lineHeightIsMinimum ? .atLeast : .exactly; points = p
        } else if abs(s.lineSpacing - 1) < 0.005 { line = .single }
        else if abs(s.lineSpacing - 1.5) < 0.005 { line = .oneHalf }
        else if abs(s.lineSpacing - 2) < 0.005 { line = .double }
        else { line = .multiple }
    }

    var format: RichDocumentController.ParagraphFormat {
        let rule: RichDocumentController.LineRule
        switch line {
        case .single: rule = .multiple(1)
        case .oneHalf: rule = .multiple(1.5)
        case .double: rule = .multiple(2)
        case .multiple: rule = .multiple(multiple)
        case .atLeast: rule = .atLeast(points)
        case .exactly: rule = .exactly(points)
        }
        let first = special == .none ? 0 : special == .hanging ? -by : by
        return .init(alignment: alignment, indentLeft: left, indentRight: right, firstLineIndent: first,
                     spaceBefore: before, spaceAfter: after, lineRule: rule, tabStops: tabs.stops, contextualSpacing: contextual,
                     widowControl: widow, keepNext: keepNext, keepLines: keepLines, pageBreakBefore: breakBefore,
                     suppressLineNumbers: noLineNumbers, noHyphenation: noHyphens)
    }

    /// The format with only the break boxes changed since `base` said: over a selection of many paragraphs,
    /// an untouched box leaves each paragraph's own setting (one heading's keep with next, another's page break).
    func format(since base: ParagraphDialogValues) -> RichDocumentController.ParagraphFormat {
        var f = format
        if widow == base.widow { f.widowControl = nil }
        if keepNext == base.keepNext { f.keepNext = nil }
        if keepLines == base.keepLines { f.keepLines = nil }
        if breakBefore == base.breakBefore { f.pageBreakBefore = nil }
        if noLineNumbers == base.noLineNumbers { f.suppressLineNumbers = nil }
        if noHyphens == base.noHyphens { f.noHyphenation = nil }
        return f
    }
}

final class ParagraphDialog: StatefulWidget {
    let initial: RichParagraphStyle
    let unit: LengthUnit
    let onOK: (RichDocumentController.ParagraphFormat) -> Void
    let onCancel: () -> Void
    init(initial: RichParagraphStyle, unit: LengthUnit = .inch,
         onOK: @escaping (RichDocumentController.ParagraphFormat) -> Void, onCancel: @escaping () -> Void) {
        self.initial = initial; self.unit = unit; self.onOK = onOK; self.onCancel = onCancel
        super.init()
    }
    override func createState() -> State<StatefulWidget> { ParagraphDialogState() }
}

final class ParagraphDialogState: State<StatefulWidget> {
    private var _w: ParagraphDialog { widget as! ParagraphDialog }
    private(set) var v = ParagraphDialogValues(RichParagraphStyle())
    private let _multiple = TextEditingController()
    /// The Tabs page is showing instead of the paragraph page; its edits belong to `v` and apply with OK here.
    private(set) var showTabs = false
    /// Word's two pages: Indents and Spacing, Line and Page Breaks.
    private(set) var showBreaks = false
    private var _tabsBefore: TabStopEditor?
    private var _tabPos = 36.0, _tabKind = TabKind.left, _tabLeader = TabLeader.none

    override func initState() {
        super.initState()
        v = ParagraphDialogValues(_w.initial)
        _multiple.text = Self.number(v.multiple)
    }

    private static func number(_ d: Double) -> String {
        let r = (d * 100).rounded() / 100
        return r == r.rounded() ? String(Int(r)) : String(r)
    }

    private func commitMultiple() {
        if let m = Double(_multiple.text.trimmingWhitespace()), m >= 0.1, m <= 20 { setState { self.v.multiple = m } }
        else { _multiple.text = Self.number(v.multiple) }
    }

    private func tabsPage(_ fluent: FluentThemeData) -> Widget {
        func choice(_ id: String, _ label: String, _ on: Bool, _ action: @escaping () -> Void) -> Widget {
            PKeyed(id, Chrome.textToggle(label, on, fluent, action: action))
        }
        func row(_ label: String, _ items: [Widget]) -> Widget {
            Padding(padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 8), child: Row(crossAxisAlignment: .center, children:
                [SizedBox(width: 90, height: nil, child: Text(label))] + items))
        }
        let unit = _w.unit
        var list: [Widget] = v.tabs.stops.isEmpty ? [Text("No tab stops set")] : []
        for (i, t) in v.tabs.stops.enumerated() {
            let kind = TabKind(t), lead = TabLeader(t)
            let label = "\(unit.format(points: t.position, lineHeight: 12))  \(kind.title)" + (lead == .none ? "" : "  \(lead.title)")
            list.append(choice("tb-row-\(i)", label, v.tabs.index(at: _tabPos) == i) { [weak self] in
                self?.setState { self?._tabPos = t.position; self?._tabKind = kind; self?._tabLeader = lead } })
        }
        return Column(crossAxisAlignment: .start, children: [
            Padding(padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 8), child: Column(crossAxisAlignment: .start, children: [Text("Tab stops")] + list)),
            row("Position", [PKeyed("tb-pos", UnitSpinner(points: _tabPos, unit: unit, min: 0, max: 1584, width: 90) { [weak self] n in
                self?.setState { self?._tabPos = n } })]),
            row("Alignment", TabKind.allCases.map { k in choice("tb-kind-\(k.id)", k.title, _tabKind == k) { [weak self] in self?.setState { self?._tabKind = k } } }),
            row("Leader", TabLeader.allCases.map { l in choice("tb-leader-\(l.id)", l.title, _tabLeader == l) { [weak self] in self?.setState { self?._tabLeader = l } } }),
            row("", [
                choice("tb-set", "Set", false) { [weak self] in
                    guard let self else { return }
                    self.setState { self.v.tabs.set(at: self._tabPos, kind: self._tabKind, leader: self._tabLeader) } },
                choice("tb-clear", "Clear", false) { [weak self] in
                    guard let self else { return }
                    self.setState { self.v.tabs.clear(at: self._tabPos) } },
                choice("tb-clear-all", "Clear All", false) { [weak self] in self?.setState { self?.v.tabs.clearAll() } },
            ]),
        ])
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        if showTabs {
            return DialogShell(title: "Tabs", page: tabsPage(fluent), width: 480,
                               onOK: { [weak self] in self?.setState { self?.showTabs = false } },
                               onCancel: { [weak self] in
                                   self?.setState { if let b = self?._tabsBefore { self?.v.tabs = b }; self?.showTabs = false } })
        }
        let unit = _w.unit
        func choice(_ id: String, _ label: String, _ on: Bool, _ action: @escaping () -> Void) -> Widget {
            PKeyed(id, Chrome.textToggle(label, on, fluent, action: action))
        }
        func spin(_ id: String, _ label: String, _ pts: Double, max: Double = 1584, min: Double = 0,
                  _ set: @escaping (Double) -> Void) -> Widget {
            Padding(padding: EdgeInsets(left: 0, top: 0, right: 12, bottom: 8), child: Column(crossAxisAlignment: .start, children: [
                Text(label), Chrome.vgap(2),
                PKeyed(id, UnitSpinner(points: pts, unit: unit, min: min, max: max, width: 90) { [weak self] n in
                    self?.setState { set(n) } }),
            ]))
        }
        func row(_ label: String, _ items: [Widget]) -> Widget {
            Padding(padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 8), child: Row(crossAxisAlignment: .center, children:
                [SizedBox(width: 90, height: nil, child: Text(label))] + items))
        }
        let aligns: [(String, String, ParagraphAlignment)] = [
            ("pa-align-left", "Left", .left), ("pa-align-center", "Centered", .center),
            ("pa-align-right", "Right", .right), ("pa-align-justify", "Justified", .justify)]
        let lines: [(String, String, ParagraphLineKind)] = [
            ("pa-line-single", "Single", .single), ("pa-line-1.5", "1.5 lines", .oneHalf), ("pa-line-double", "Double", .double),
            ("pa-line-multiple", "Multiple", .multiple), ("pa-line-atleast", "At least", .atLeast), ("pa-line-exactly", "Exactly", .exactly)]
        var lineRows: [Widget] = [
            row("Line spacing", lines.prefix(3).map { id, t, k in choice(id, t, v.line == k) { [weak self] in self?.setState { self?.v.line = k } } }),
            row("", lines.suffix(3).map { id, t, k in choice(id, t, v.line == k) { [weak self] in self?.setState { self?.v.line = k } } }),
        ]
        if v.line == .multiple {
            lineRows.append(row("Multiple of", [SizedBox(width: 90, height: Chrome.fieldHeight, child: PKeyed("pa-multiple", FluentTextBox(
                controller: _multiple, onSubmitted: { [weak self] _ in self?.commitMultiple() },
                onFocusChanged: { [weak self] f in if !f { self?.commitMultiple() } })))]))
        } else if v.line == .atLeast || v.line == .exactly {
            lineRows.append(row(v.line == .atLeast ? "At least" : "Exactly", [
                PKeyed("pa-points", UnitSpinner(points: v.points, unit: .pt, min: 1, max: 1584, width: 90) { [weak self] n in
                    self?.setState { self?.v.points = n } })]))
        }
        let pages = Padding(padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 12), child: Row(children: [
            choice("pa-page-indents", "Indents and Spacing", !showBreaks) { [weak self] in self?.setState { self?.showBreaks = false } },
            choice("pa-page-breaks", "Line and Page Breaks", showBreaks) { [weak self] in self?.setState { self?.showBreaks = true } },
        ]))
        if showBreaks {
            func box(_ id: String, _ label: String, _ on: Bool, _ set: @escaping (Bool) -> Void) -> Widget {
                Padding(padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 8), child: PKeyed(id, Checkbox(
                    checked: on, onChanged: { [weak self] c in self?.setState { set(c ?? false) } },
                    content: Text(label, style: fluent.typography.body))))
            }
            let breaks = Column(crossAxisAlignment: .start, children: [
                pages,
                Padding(padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 8), child: Text("Pagination", style: fluent.typography.bodyStrong)),
                box("pa-widow", "Widow/Orphan control", v.widow) { [weak self] c in self?.v.widow = c },
                box("pa-keep-next", "Keep with next", v.keepNext) { [weak self] c in self?.v.keepNext = c },
                box("pa-keep-lines", "Keep lines together", v.keepLines) { [weak self] c in self?.v.keepLines = c },
                box("pa-break-before", "Page break before", v.breakBefore) { [weak self] c in self?.v.breakBefore = c },
                Padding(padding: EdgeInsets(left: 0, top: 4, right: 0, bottom: 8), child: Text("Formatting exceptions", style: fluent.typography.bodyStrong)),
                box("pa-no-line-numbers", "Suppress line numbers", v.noLineNumbers) { [weak self] c in self?.v.noLineNumbers = c },
                box("pa-no-hyphens", "Don't hyphenate", v.noHyphens) { [weak self] c in self?.v.noHyphens = c },
            ])
            return DialogShell(title: "Paragraph", page: breaks, width: 480,
                               onOK: { [weak self] in guard let self else { return }; self._w.onOK(self.v.format(since: ParagraphDialogValues(self._w.initial))) },
                               onCancel: { [weak self] in self?._w.onCancel() })
        }
        let page = Column(crossAxisAlignment: .start, children: [
            pages,
            row("Alignment", aligns.map { id, t, a in choice(id, t, v.alignment == a) { [weak self] in self?.setState { self?.v.alignment = a } } }),
            Row(children: [
                spin("pa-left", "Left indent", v.left) { [weak self] n in self?.v.left = n },
                spin("pa-right", "Right indent", v.right) { [weak self] n in self?.v.right = n },
            ]),
            row("Special", [
                choice("pa-special-none", "None", v.special == .none) { [weak self] in self?.setState { self?.v.special = .none } },
                choice("pa-special-first", "First line", v.special == .firstLine) { [weak self] in
                    self?.setState { self?.v.special = .firstLine; if (self?.v.by ?? 0) == 0 { self?.v.by = 36 } } },
                choice("pa-special-hanging", "Hanging", v.special == .hanging) { [weak self] in
                    self?.setState { self?.v.special = .hanging; if (self?.v.by ?? 0) == 0 { self?.v.by = 36 } } },
            ]),
            v.special == .none ? Chrome.gap(0) : spin("pa-by", "By", v.by) { [weak self] n in self?.v.by = n },
            Row(children: [
                spin("pa-before", "Space before", v.before) { [weak self] n in self?.v.before = n },
                spin("pa-after", "Space after", v.after) { [weak self] n in self?.v.after = n },
            ]),
            Padding(padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 8), child: PKeyed("pa-contextual", Checkbox(
                checked: v.contextual, onChanged: { [weak self] c in self?.setState { self?.v.contextual = c ?? false } },
                content: Text("Don't add space between paragraphs of the same style", style: fluent.typography.body)))),
        ] + lineRows + [
            row("", [PKeyed("pa-tabs", Chrome.textToggle("Tabs…", false, fluent) { [weak self] in
                guard let self else { return }
                self.setState {
                    self._tabsBefore = self.v.tabs; self.showTabs = true
                    let first = self.v.tabs.stops.first
                    self._tabPos = first?.position ?? 36
                    self._tabKind = first.map(TabKind.init) ?? .left; self._tabLeader = first.map(TabLeader.init) ?? .none
                } })]),
        ])
        return DialogShell(title: "Paragraph", page: page, width: 480,
                           onOK: { [weak self] in guard let self else { return }; self._w.onOK(self.v.format(since: ParagraphDialogValues(self._w.initial))) },
                           onCancel: { [weak self] in self?._w.onCancel() })
    }
}
