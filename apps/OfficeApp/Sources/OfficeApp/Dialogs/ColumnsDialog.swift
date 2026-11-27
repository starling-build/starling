// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// W-PG-2: Layout > Columns > More Columns. Word's presets (One, Two, Three, Left, Right), the number of columns,
// each column's width and the spacing after it, Equal column width, Line between, and Apply to (this section or
// the whole document). OK is one undo step (`changePageSetup`).

import Flutter
import FlutterSwiftBridge
import OfficeText

/// What the Columns dialog holds: column widths and the gaps between them, in points, across a text width.
struct ColumnsValues: Equatable {
    enum Preset: CaseIterable {
        case one, two, three, left, right
        var title: String { ["One", "Two", "Three", "Left", "Right"][Preset.allCases.firstIndex(of: self)!] }
        var id: String { ["one", "two", "three", "left", "right"][Preset.allCases.firstIndex(of: self)!] }
    }
    /// Word holds a column at least half an inch wide.
    static let minWidth = 36.0
    /// The text width the columns share.
    let text: Double
    var widths: [Double]
    /// The spacing after each column but the last.
    var gaps: [Double]
    var equal = true
    var line = false
    var allSections = false

    var count: Int { widths.count }

    init(_ p: PageSetup) {
        text = p.contentWidth
        line = p.columnLine
        let n = max(1, p.columns)
        if n > 1, let spec = p.columnSpec, spec.count == n {
            widths = spec.map(\.width); gaps = spec.dropLast().map(\.gap); equal = false
        } else {
            widths = []; gaps = []
            setCount(n, gap: p.columnGap)
        }
    }

    /// The most columns of the least width the text holds at a gap.
    func maxCount(gap: Double) -> Int { max(1, min(45, Int((text + gap) / (Self.minWidth + gap) + 1e-9))) }

    /// `n` equal columns, `gap` apart (the spacing kept from before).
    mutating func setCount(_ n: Int, gap: Double? = nil) {
        let g = max(0, gap ?? gaps.first ?? 36)
        let n = min(max(1, n), maxCount(gap: g))
        gaps = Array(repeating: g, count: n - 1)
        widths = Array(repeating: (text - g * Double(n - 1)) / Double(n), count: n)
        equal = true
    }

    /// Word's presets: Left and Right are two columns, the narrow one as wide as one of three equal columns.
    mutating func apply(_ preset: Preset) {
        let g = gaps.first ?? 36
        switch preset {
        case .one: setCount(1, gap: g)
        case .two: setCount(2, gap: g)
        case .three: setCount(3, gap: g)
        case .left, .right:
            let narrow = (text - 2 * g) / 3
            let pair = [narrow, text - g - narrow]
            widths = preset == .left ? pair : pair.reversed(); gaps = [g]; equal = false
        }
    }

    var preset: Preset? {
        Preset.allCases.first { p in
            var v = self; v.apply(p)
            return v.equal == equal && v.widths.count == widths.count
                && zip(v.widths + v.gaps, widths + gaps).allSatisfy { abs($0 - $1) < 0.5 }
        }
    }

    mutating func setEqual(_ on: Bool) {
        equal = on
        if on { setCount(count, gap: gaps.first) }
    }

    /// A column's new width. Equal columns all take it and the spacing gives way; else the column beside it does.
    mutating func setWidth(_ k: Int, _ w: Double) {
        guard k < count, count > 1 else { return }
        if equal {
            let n = Double(count)
            let w = min(max(Self.minWidth, w), text / n)
            widths = Array(repeating: w, count: count)
            gaps = Array(repeating: (text - n * w) / (n - 1), count: count - 1)
            return
        }
        let other = k + 1 < count ? k + 1 : k - 1
        let w = min(max(Self.minWidth, w), widths[k] + widths[other] - Self.minWidth)
        widths[other] -= w - widths[k]; widths[k] = w
    }

    /// The spacing after column `k`. Equal columns all take it and narrow to fit; else the next column gives way.
    mutating func setGap(_ k: Int, _ g: Double) {
        guard k < gaps.count else { return }
        if equal {
            let n = Double(count)
            let g = min(max(0, g), (text - n * Self.minWidth) / (n - 1))
            gaps = Array(repeating: g, count: count - 1)
            widths = Array(repeating: (text - g * (n - 1)) / n, count: count)
            return
        }
        let g = min(max(0, g), gaps[k] + widths[k + 1] - Self.minWidth)
        widths[k + 1] -= g - gaps[k]; gaps[k] = g
    }

    func apply(to p: inout PageSetup) {
        p.columns = count
        p.columnLine = line
        if let g = gaps.first { p.columnGap = g }
        p.columnSpec = equal || count < 2 ? nil
            : widths.indices.map { ColumnSpan(width: widths[$0], gap: $0 < gaps.count ? gaps[$0] : 0) }
    }
}

private final class ColKeyed: StatelessWidget {
    let child: Widget
    init(_ id: String, _ child: Widget) { self.child = child; super.init(key: ValueKey(id)) }
    override func build(_ context: any BuildContext) -> Widget { child }
}

final class ColumnsDialog: StatefulWidget {
    let initial: PageSetup
    let sectionCount: Int
    let unit: LengthUnit
    let onOK: (ColumnsValues) -> Void
    let onCancel: () -> Void
    init(initial: PageSetup, sectionCount: Int = 1, unit: LengthUnit = .inch,
         onOK: @escaping (ColumnsValues) -> Void, onCancel: @escaping () -> Void) {
        self.initial = initial; self.sectionCount = sectionCount; self.unit = unit
        self.onOK = onOK; self.onCancel = onCancel
        super.init()
    }
    override func createState() -> State<StatefulWidget> { ColumnsDialogState() }
}

final class ColumnsDialogState: State<StatefulWidget> {
    private var _w: ColumnsDialog { widget as! ColumnsDialog }
    private(set) var v = ColumnsValues(PageSetup.letter)
    private let _count = TextEditingController()

    override func initState() {
        super.initState()
        v = ColumnsValues(_w.initial)
        _count.text = String(v.count)
    }

    func setCount(_ text: String) {
        if let n = Int(text.trimmingWhitespace()), n != v.count { setState { v.setCount(n) } }
        _count.text = String(v.count)
    }

    func choose(_ p: ColumnsValues.Preset) {
        setState { v.apply(p) }
        _count.text = String(v.count)
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let unit = _w.unit
        func toggle(_ id: String, _ label: String, _ on: Bool, _ action: @escaping () -> Void) -> Widget {
            ColKeyed(id, Chrome.textToggle(label, on, fluent, action: action))
        }
        func spin(_ id: String, _ pts: Double, enabled: Bool, _ set: @escaping (Double) -> Void) -> Widget {
            Padding(padding: EdgeInsets(left: 0, top: 0, right: 12, bottom: 6), child: enabled
                ? ColKeyed(id, UnitSpinner(points: pts, unit: unit, min: 0, max: 1584, width: 90) { [weak self] n in self?.setState { set(n) } })
                : SizedBox(width: 90, height: 30, child: Text(unit.format(points: pts))))
        }
        func row(_ items: [Widget]) -> Widget {
            Padding(padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 8), child: Row(crossAxisAlignment: .center, children: items))
        }
        let current = v.preset
        var rows: [Widget] = [
            row(ColumnsValues.Preset.allCases.map { p in toggle("col-\(p.id)", p.title, current == p) { [weak self] in self?.choose(p) } }),
            row([SizedBox(width: 140, height: nil, child: Text("Number of columns")),
                 SizedBox(width: 70, height: 30, child: FluentTextBox(
                    controller: _count, onSubmitted: { [weak self] t in self?.setCount(t) },
                    onFocusChanged: { [weak self] f in if !f, let self { self.setCount(self._count.text) } })),
                 Chrome.gap(16),
                 toggle("col-line", "Line between", v.line) { [weak self] in self?.setState { self?.v.line.toggle() } }]),
            row([SizedBox(width: 50, height: nil, child: Text("Col #")),
                 SizedBox(width: 102, height: nil, child: Text("Width")), Text("Spacing")]),
        ]
        for k in 0 ..< v.count {
            let open = !v.equal || k == 0
            rows.append(Row(crossAxisAlignment: .center, children: [
                SizedBox(width: 50, height: nil, child: Text("\(k + 1):")),
                spin("col-w\(k)", v.widths[k], enabled: open && v.count > 1) { [weak self] n in self?.v.setWidth(k, n) },
                k < v.gaps.count ? spin("col-g\(k)", v.gaps[k], enabled: open) { [weak self] n in self?.v.setGap(k, n) } : Chrome.gap(0),
            ]))
        }
        if v.count > 1 {
            rows.append(toggle("col-equal", "Equal column width", v.equal) { [weak self] in
                self?.setState { if let s = self { s.v.setEqual(!s.v.equal) } } })
        }
        if _w.sectionCount > 1 {
            rows.append(row([SizedBox(width: 90, height: nil, child: Text("Apply to")),
                toggle("col-this", "This section", !v.allSections) { [weak self] in self?.setState { self?.v.allSections = false } },
                toggle("col-all", "Whole document", v.allSections) { [weak self] in self?.setState { self?.v.allSections = true } }]))
        }
        return DialogShell(title: "Columns", page: Column(crossAxisAlignment: .start, children: rows), width: 460,
                           onOK: { [weak self] in guard let self else { return }; self.setCount(self._count.text); self._w.onOK(self.v) },
                           onCancel: { [weak self] in self?._w.onCancel() })
    }
}
