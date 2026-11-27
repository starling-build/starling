// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// A length box with units (U-shared): the value is kept in points, shown and
// typed in the unit the dialog uses (in, cm, mm, pt, px, or lines), and a
// typed value in another unit ("2 cm" in an inches box) is converted, as a
// user expects. `LengthUnit` is the model (parse, format, step); `UnitSpinner`
// is the box with its up and down buttons.

import Flutter
import FlutterSwiftBridge

enum LengthUnit: CaseIterable {
    case inch, cm, mm, pt, px, line

    /// Points in one of this unit. A line is the paragraph's own line height.
    func points(lineHeight: Double) -> Double {
        switch self {
        case .inch: return 72
        case .cm: return 72 / 2.54
        case .mm: return 72 / 25.4
        case .pt: return 1
        case .px: return 0.75
        case .line: return lineHeight
        }
    }

    var suffix: String {
        switch self {
        case .inch: return "in"
        case .cm: return "cm"
        case .mm: return "mm"
        case .pt: return "pt"
        case .px: return "px"
        case .line: return "li"
        }
    }

    /// What one press of the up button adds, in this unit.
    var step: Double {
        switch self {
        case .inch, .cm: return 0.1
        case .mm, .pt, .px: return 1
        case .line: return 0.5
        }
    }

    /// Decimal places shown.
    var decimals: Int {
        switch self {
        case .inch, .cm: return 2
        case .mm, .pt, .px, .line: return 1
        }
    }

    /// The unit a typed suffix names, or nil.
    static func named(_ s: String) -> LengthUnit? {
        switch s {
        case "in", "inch", "inches", "\"", "”": return .inch
        case "cm", "centimeter", "centimeters", "centimetre", "centimetres": return .cm
        case "mm", "millimeter", "millimeters", "millimetre", "millimetres": return .mm
        case "pt", "point", "points": return .pt
        case "px", "pixel", "pixels": return .px
        case "li", "line", "lines", "ln": return .line
        default: return nil
        }
    }

    /// Points from typed text: a number with an optional unit ("1.5", "1,5 cm", "12pt", "2\""). A bare number is in
    /// `unit`. Nil when the text is not a length.
    static func parse(_ text: String, default unit: LengthUnit, lineHeight: Double = 12) -> Double? {
        let t = text.trimmingWhitespace().lowercased()
        var number = "", rest = Substring(t)
        while let c = rest.first, c.isASCII, c.isNumber || c == "." || c == "," || (number.isEmpty && (c == "-" || c == "+")) {
            number.append(c == "," ? "." : c)
            rest = rest.dropFirst()
        }
        guard let v = Double(number) else { return nil }
        let suffix = rest.trimmingWhitespace()
        let u = suffix.isEmpty ? unit : (named(suffix) ?? unit)
        if !suffix.isEmpty && named(suffix) == nil { return nil }
        return v * u.points(lineHeight: lineHeight)
    }

    /// "1.5 cm": `points` shown in this unit, to its decimals, trailing zeros dropped.
    func format(points: Double, lineHeight: Double = 12) -> String {
        let v = points / self.points(lineHeight: lineHeight)
        var scale = 1.0
        for _ in 0..<decimals { scale *= 10 }
        let r = (v * scale).rounded() / scale
        var s = String(r)
        if s.hasSuffix(".0") { s.removeLast(2) }
        return s + " " + suffix
    }

    /// `points` moved one step up (or down), clamped to [min, max] and rounded to the unit's decimals so
    /// repeated presses do not drift.
    func stepped(points: Double, up: Bool, min lo: Double, max hi: Double, lineHeight: Double = 12) -> Double {
        let per = self.points(lineHeight: lineHeight)
        var scale = 1.0
        for _ in 0..<decimals { scale *= 10 }
        let v = ((points / per + (up ? step : -step)) * scale).rounded() / scale
        return Swift.min(hi, Swift.max(lo, v * per))
    }
}

final class UnitSpinner: StatefulWidget {
    let points: Double
    let unit: LengthUnit
    let min: Double
    let max: Double
    let lineHeight: Double
    let width: Double
    let onChanged: (Double) -> Void

    init(points: Double, unit: LengthUnit, min: Double = 0, max: Double = 1584, lineHeight: Double = 12,
         width: Double = 110, onChanged: @escaping (Double) -> Void) {
        self.points = points
        self.unit = unit
        self.min = min
        self.max = max
        self.lineHeight = lineHeight
        self.width = width
        self.onChanged = onChanged
        super.init()
    }

    override func createState() -> State<StatefulWidget> { UnitSpinnerState() }
}

final class UnitSpinnerState: State<StatefulWidget> {
    private var _w: UnitSpinner { widget as! UnitSpinner }
    private let _text = TextEditingController()

    private func shown() -> String { _w.unit.format(points: _w.points, lineHeight: _w.lineHeight) }

    override func initState() {
        super.initState()
        _text.text = shown()
    }

    override func didUpdateWidget(_ old: StatefulWidget) {
        super.didUpdateWidget(old)
        _text.text = shown()
    }

    /// Takes the typed text: a length in range becomes the value; anything else puts the old value back.
    func commit() {
        if let p = LengthUnit.parse(_text.text, default: _w.unit, lineHeight: _w.lineHeight) {
            let clamped = Swift.min(_w.max, Swift.max(_w.min, p))
            _w.onChanged(clamped)
            _text.text = _w.unit.format(points: clamped, lineHeight: _w.lineHeight)
        } else {
            _text.text = shown()
        }
    }

    private func bump(_ up: Bool) {
        _w.onChanged(_w.unit.stepped(points: _w.points, up: up, min: _w.min, max: _w.max, lineHeight: _w.lineHeight))
    }

    override func build(_ context: any BuildContext) -> Widget {
        func button(_ glyph: String, _ tip: String, _ up: Bool) -> Widget {
            Tooltip(message: tip, child: GestureDetector(onTap: { [weak self] in self?.bump(up) }, behavior: .opaque,
                child: SizedBox(width: 22, height: 15, child: Center(child: Text(glyph)))))
        }
        return Row(mainAxisSize: .min, children: [
            SizedBox(width: _w.width, height: Chrome.fieldHeight, child: FluentTextBox(
                controller: _text,
                onSubmitted: { [weak self] _ in self?.commit() },
                onFocusChanged: { [weak self] focused in if !focused { self?.commit() } })),
            Column(mainAxisSize: .min, children: [button("▲", "Increase", true), button("▼", "Decrease", false)]),
        ])
    }
}
