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
private final class PKeyed: StatelessWidget {
    let child: Widget
    init(_ id: String, _ child: Widget) { self.child = child; super.init(key: ValueKey(id)) }
    override func build(_ context: any BuildContext) -> Widget { child }
}

enum ParagraphSpecial { case none, firstLine, hanging }
enum ParagraphLineKind { case single, oneHalf, double, multiple, atLeast, exactly }

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

    init(_ s: RichParagraphStyle) {
        alignment = s.alignment; left = s.indentLeft; right = s.indentRight
        special = s.firstLineIndent < 0 ? .hanging : s.firstLineIndent > 0 ? .firstLine : .none
        by = abs(s.firstLineIndent)
        before = s.spaceBefore; after = s.spaceAfter
        multiple = s.lineSpacing; points = 12
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
                     spaceBefore: before, spaceAfter: after, lineRule: rule)
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

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
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
            lineRows.append(row("Multiple of", [SizedBox(width: 90, height: 30, child: PKeyed("pa-multiple", FluentTextBox(
                controller: _multiple, onSubmitted: { [weak self] _ in self?.commitMultiple() },
                onFocusChanged: { [weak self] f in if !f { self?.commitMultiple() } })))]))
        } else if v.line == .atLeast || v.line == .exactly {
            lineRows.append(row(v.line == .atLeast ? "At least" : "Exactly", [
                PKeyed("pa-points", UnitSpinner(points: v.points, unit: .pt, min: 1, max: 1584, width: 90) { [weak self] n in
                    self?.setState { self?.v.points = n } })]))
        }
        let page = Column(crossAxisAlignment: .start, children: [
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
        ] + lineRows)
        return DialogShell(title: "Paragraph", page: page, width: 480,
                           onOK: { [weak self] in guard let self else { return }; self._w.onOK(self.v.format) },
                           onCancel: { [weak self] in self?._w.onCancel() })
    }
}
