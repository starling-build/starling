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
    var color: CellFieldEdit<UInt32?> = .keep
    var fill: CellFieldEdit<UInt32?> = .keep
    var hAlign: CellFieldEdit<CellStyle.HAlign> = .keep
    var vAlign: CellFieldEdit<CellStyle.VAlign> = .keep
    var wrap: CellFieldEdit<Bool> = .keep
    var borderTop: CellFieldEdit<Bool> = .keep
    var borderLeft: CellFieldEdit<Bool> = .keep
    var borderBottom: CellFieldEdit<Bool> = .keep
    var borderRight: CellFieldEdit<Bool> = .keep

    var isEmpty: Bool { self == CellFormatEdit() }

    /// The fields of `style`, to start the dialog from.
    static func start(of style: CellStyle) -> CellFormatEdit.Values { Values(style) }

    /// The dialog's working values, read from a cell's format.
    struct Values: Equatable {
        var numberFormat: String
        var fontName: String?
        var fontSize: Double?
        var bold: Bool, italic: Bool, underline: Bool, strike: Bool
        var color: UInt32?, fill: UInt32?
        var hAlign: CellStyle.HAlign, vAlign: CellStyle.VAlign
        var wrap: Bool
        var top: Bool, left: Bool, bottom: Bool, right: Bool
        init(_ s: CellStyle) {
            numberFormat = s.numberFormat; fontName = s.fontName; fontSize = s.fontSize
            bold = s.bold; italic = s.italic; underline = s.underline; strike = s.strike
            color = s.color; fill = s.fill; hAlign = s.hAlign; vAlign = s.vAlign; wrap = s.wrap
            top = s.borders.top; left = s.borders.left; bottom = s.borders.bottom; right = s.borders.right
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
        e.color = .diff(new.color, from: old.color); e.fill = .diff(new.fill, from: old.fill)
        e.hAlign = .diff(new.hAlign, from: old.hAlign); e.vAlign = .diff(new.vAlign, from: old.vAlign)
        e.wrap = .diff(new.wrap, from: old.wrap)
        e.borderTop = .diff(new.top, from: old.top); e.borderLeft = .diff(new.left, from: old.left)
        e.borderBottom = .diff(new.bottom, from: old.bottom); e.borderRight = .diff(new.right, from: old.right)
        return e
    }

    func apply(to s: inout CellStyle) {
        numberFormat.apply(&s.numberFormat)
        fontName.apply(&s.fontName); fontSize.apply(&s.fontSize)
        bold.apply(&s.bold); italic.apply(&s.italic); underline.apply(&s.underline); strike.apply(&s.strike)
        color.apply(&s.color); fill.apply(&s.fill)
        hAlign.apply(&s.hAlign); vAlign.apply(&s.vAlign); wrap.apply(&s.wrap)
        Self._side(borderTop, "top", &s.borders, \.top)
        Self._side(borderLeft, "left", &s.borders, \.left)
        Self._side(borderBottom, "bottom", &s.borders, \.bottom)
        Self._side(borderRight, "right", &s.borders, \.right)
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
