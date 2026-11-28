// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-FM-1: what the Format Cells dialog changes, as data. Every field starts
// as `.keep`; the dialog sets a field only where the user changed it, so a
// selection of cells with different fonts keeps them when only the number
// format is picked. Applied through the controller's one undoable setStyle.

/// One property of a cell format: left as the cell has it, or set.
enum CellFieldEdit<T: Equatable>: Equatable {
    case keep
    case set(T)

    /// `.set(new)` where the user moved the field off its starting value, else `.keep`.
    static func diff(_ new: T, from old: T) -> CellFieldEdit<T> { new == old ? .keep : .set(new) }

    func apply(_ target: inout T) { if case .set(let v) = self { target = v } }
}

struct CellFormatEdit: Equatable {
    var numberFormat: CellFieldEdit<String> = .keep
    var fontName: CellFieldEdit<String?> = .keep
    var fontSize: CellFieldEdit<Double?> = .keep
    var bold: CellFieldEdit<Bool> = .keep
    var italic: CellFieldEdit<Bool> = .keep
    var underline: CellFieldEdit<Bool> = .keep
    var strike: CellFieldEdit<Bool> = .keep
    /// Superscript (1), subscript (-1) or neither (0): the font's `vertAlign`.
    var script: CellFieldEdit<Int> = .keep
    var color: CellFieldEdit<UInt32?> = .keep
    var fill: CellFieldEdit<UInt32?> = .keep
    var hAlign: CellFieldEdit<CellStyle.HAlign> = .keep
    var vAlign: CellFieldEdit<CellStyle.VAlign> = .keep
    var wrap: CellFieldEdit<Bool> = .keep
    var shrink: CellFieldEdit<Bool> = .keep
    var justify: CellFieldEdit<Bool> = .keep
    var indent: CellFieldEdit<Int> = .keep
    var rotation: CellFieldEdit<Int> = .keep
    var borderTop: CellFieldEdit<Bool> = .keep
    var borderLeft: CellFieldEdit<Bool> = .keep
    var borderBottom: CellFieldEdit<Bool> = .keep
    var borderRight: CellFieldEdit<Bool> = .keep
    /// The line style (thin, medium, thick, double, dashed, dotted, hair…) and colour of every side that is drawn once this edit is applied.
    var borderKind: CellFieldEdit<String> = .keep
    var borderColor: CellFieldEdit<UInt32?> = .keep
    var locked: CellFieldEdit<Bool> = .keep
    var formulaHidden: CellFieldEdit<Bool> = .keep

    var isEmpty: Bool { self == CellFormatEdit() }

    /// The fields of `style`, to start the dialog from.
    static func start(of style: CellStyle) -> CellFormatEdit.Values { Values(style) }

    /// The dialog's working values, read from a cell's format.
    struct Values: Equatable {
        var numberFormat: String
        var fontName: String?
        var fontSize: Double?
        var bold: Bool, italic: Bool, underline: Bool, strike: Bool
        var script: Int
        var color: UInt32?, fill: UInt32?
        var hAlign: CellStyle.HAlign, vAlign: CellStyle.VAlign
        var wrap: Bool, shrink: Bool
        var justify: Bool, indent: Int, rotation: Int
        var locked: Bool, formulaHidden: Bool
        var top: Bool, left: Bool, bottom: Bool, right: Bool
        /// The pen: the style and colour of the first drawn side ("thin", automatic when none is drawn).
        var lineKind: String, lineColor: UInt32?
        init(_ s: CellStyle) {
            numberFormat = s.numberFormat; fontName = s.fontName; fontSize = s.fontSize
            bold = s.bold; italic = s.italic; underline = s.underline; strike = s.strike; script = s.script
            color = s.color; fill = s.fill; hAlign = s.hAlign; vAlign = s.vAlign; wrap = s.wrap; shrink = s.shrink
            justify = s.justify; indent = s.indent; rotation = s.rotation
            locked = s.locked; formulaHidden = s.formulaHidden
            top = s.borders.top; left = s.borders.left; bottom = s.borders.bottom; right = s.borders.right
            let b = s.borders
            let first = ["top", "left", "bottom", "right"].first { (name: String) -> Bool in
                switch name { case "top": return b.top; case "left": return b.left; case "bottom": return b.bottom; default: return b.right }
            }
            lineKind = first.flatMap { b.kinds[$0] } ?? "thin"
            lineColor = first.flatMap { b.colors[$0] }
        }
    }

    /// The edit that takes `old` to `new`: only the fields that differ.
    static func between(_ old: Values, _ new: Values) -> CellFormatEdit {
        var e = CellFormatEdit()
        e.numberFormat = .diff(new.numberFormat, from: old.numberFormat)
        e.fontName = .diff(new.fontName, from: old.fontName)
        e.fontSize = .diff(new.fontSize, from: old.fontSize)
        e.bold = .diff(new.bold, from: old.bold); e.italic = .diff(new.italic, from: old.italic)
        e.underline = .diff(new.underline, from: old.underline); e.strike = .diff(new.strike, from: old.strike)
        e.script = .diff(new.script, from: old.script)
        e.color = .diff(new.color, from: old.color); e.fill = .diff(new.fill, from: old.fill)
        e.hAlign = .diff(new.hAlign, from: old.hAlign); e.vAlign = .diff(new.vAlign, from: old.vAlign)
        e.wrap = .diff(new.wrap, from: old.wrap); e.shrink = .diff(new.shrink, from: old.shrink)
        e.justify = .diff(new.justify, from: old.justify); e.indent = .diff(new.indent, from: old.indent)
        e.rotation = .diff(new.rotation, from: old.rotation)
        e.locked = .diff(new.locked, from: old.locked); e.formulaHidden = .diff(new.formulaHidden, from: old.formulaHidden)
        e.borderTop = .diff(new.top, from: old.top); e.borderLeft = .diff(new.left, from: old.left)
        e.borderBottom = .diff(new.bottom, from: old.bottom); e.borderRight = .diff(new.right, from: old.right)
        e.borderKind = .diff(new.lineKind, from: old.lineKind)
        e.borderColor = .diff(new.lineColor, from: old.lineColor)
        return e
    }

    func apply(to s: inout CellStyle) {
        numberFormat.apply(&s.numberFormat)
        fontName.apply(&s.fontName); fontSize.apply(&s.fontSize)
        bold.apply(&s.bold); italic.apply(&s.italic); underline.apply(&s.underline); strike.apply(&s.strike); script.apply(&s.script)
        color.apply(&s.color); fill.apply(&s.fill)
        hAlign.apply(&s.hAlign); vAlign.apply(&s.vAlign); wrap.apply(&s.wrap); shrink.apply(&s.shrink)
        justify.apply(&s.justify); indent.apply(&s.indent); rotation.apply(&s.rotation)
        locked.apply(&s.locked); formulaHidden.apply(&s.formulaHidden)
        Self._side(borderTop, "top", &s.borders, \.top)
        Self._side(borderLeft, "left", &s.borders, \.left)
        Self._side(borderBottom, "bottom", &s.borders, \.bottom)
        Self._side(borderRight, "right", &s.borders, \.right)
        let drawn: [(String, Bool)] = [("top", s.borders.top), ("left", s.borders.left), ("bottom", s.borders.bottom), ("right", s.borders.right)]
        for (name, on) in drawn where on {
            if case .set(let k) = borderKind { s.borders.kinds[name] = k == "thin" ? nil : k }
            if case .set(let c) = borderColor { s.borders.colors[name] = c }
        }
    }

    /// A side turned off also forgets its line kind and colour (a later "on" is a plain thin line); turned on keeps whatever the file drew.
    private static func _side(_ c: CellFieldEdit<Bool>, _ name: String, _ b: inout CellStyle.Borders, _ key: WritableKeyPath<CellStyle.Borders, Bool>) {
        guard case .set(let on) = c else { return }
        b[keyPath: key] = on
        if !on { b.kinds[name] = nil; b.colors[name] = nil }
    }
}

extension WorkbookController {
    /// Format Cells: apply what the dialog changed to the selection, as one undo step.
    func formatCells(_ edit: CellFormatEdit) {
        if edit.isEmpty { return }
        setStyle { edit.apply(to: &$0) }
    }
}
