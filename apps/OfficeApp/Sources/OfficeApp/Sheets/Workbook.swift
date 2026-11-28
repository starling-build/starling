import OfficeText
// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The workbook model: sheets of sparse cells, each holding what was typed,
// its parsed formula and its current value. Values are Excel's: numbers
// are Doubles, dates are numbers with a date format, errors are values.

/// Excel's error values, which are values like any other — a formula
/// can test for them, and they propagate through arithmetic.
enum ExcelError: String, Hashable, Sendable, CaseIterable, Error {
    case null = "#NULL!"
    case div0 = "#DIV/0!"
    case value = "#VALUE!"
    case ref = "#REF!"
    case name = "#NAME?"
    case num = "#NUM!"
    case na = "#N/A"
    /// A dynamic array with something in the way of its spill.
    case spill = "#SPILL!"
    /// A calculation with no result to give (FILTER keeping nothing).
    case calc = "#CALC!"
}

enum CellValue: Hashable, Sendable {
    case empty
    case number(Double)
    case text(String)
    case bool(Bool)
    case error(ExcelError)

    var isEmpty: Bool { if case .empty = self { return true }; return false }
    var number: Double? { if case .number(let n) = self { return n }; return nil }
    var error: ExcelError? { if case .error(let e) = self { return e }; return nil }
}

/// How a cell is drawn: an index into the workbook's style table.
struct CellStyle: Hashable, Sendable {
    var bold = false
    var italic = false
    /// Any underline; off takes the kind (double, accounting) with it, as Ctrl+U does in Excel.
    var underline = false { didSet { if !underline { doubleUnderline = false; accounting = 0 } } }
    /// A plain double underline (`u val="double"`); the accounting double is `accounting == 2`.
    var doubleUnderline = false
    /// The cell wears the built-in Hyperlink cell style (`cellStyle` builtinId 8).
    var linkStyle = false
    /// A pivot's field button (the page field's name, the Row and Column Labels headings): `pivotButton="1"` on the xf.
    var pivotButton = false
    /// The underline is an accounting one: 1 single, 2 double (they sit at
    /// the cell's foot, and make its row taller).
    var accounting = 0
    /// Excel's Underline list, as the font's `u` names it: nil (None), "single", "double",
    /// "singleAccounting" or "doubleAccounting".
    var underlineKind: String? {
        get {
            guard underline else { return nil }
            return accounting == 1 ? "singleAccounting" : accounting == 2 ? "doubleAccounting" : doubleUnderline ? "double" : "single"
        }
        set {
            underline = newValue != nil
            doubleUnderline = newValue == "double"
            accounting = newValue == "singleAccounting" ? 1 : newValue == "doubleAccounting" ? 2 : 0
        }
    }
    var strike = false
    /// The font's `vertAlign`: 1 superscript, -1 subscript.
    var script = 0
    var fontName: String? = nil
    var fontSize: Double? = nil
    var color: UInt32? = nil       // 0xRRGGBB
    var fill: UInt32? = nil        // 0xRRGGBB
    var hAlign: HAlign = .general
    var vAlign: VAlign = .bottom
    var wrap = false
    /// `alignment@shrinkToFit`: text too wide for its cell is drawn small enough to fit on one line (wrapping wins over it, as in Excel).
    var shrink = false
    /// `alignment@horizontal="justify"`: wrapped lines but the last spread to the cell's width (the alignment itself stays left).
    var justify = false
    /// `alignment@readingOrder`: 0 context (the first strong letter of the text sets the direction), 1 left to right, 2 right to left.
    var readingOrder = 0
    /// Indent levels (`alignment@indent`), each three spaces of the
    /// workbook's default font: left-aligned text in from the left, right-
    /// aligned in from the right.
    var indent = 0
    /// `alignment@textRotation`: 1-90 degrees up, 91-180 down (90 + the
    /// degrees), 255 stacked. Drawn so far are 90 and 180, text turned a
    /// quarter; written back with the alignment it came in.
    var rotation = 0
    var numberFormat = "General"
    /// `protection@locked` (a locked cell refuses edits once its sheet is protected) and `@hidden` (its formula is not shown).
    var locked = true
    var formulaHidden = false
    var borders = Borders()
    /// The file's cell format this one is, or was derived from: whatever
    /// the model does not hold (border kinds and colours, pattern fills,
    /// theme colours, indents, protection, the named style) comes from it.
    var baseXf: Int? = nil

    enum HAlign: String, Hashable, Sendable { case general, left, center, right }
    enum VAlign: String, Hashable, Sendable { case top, center, bottom }

    struct Borders: Hashable, Sendable {
        var top = false, left = false, bottom = false, right = false
        /// A side's line as the file drew it — thin, medium, thick, double,
        /// dashed, dotted, hair… — and its colour; absent: thin, automatic.
        var kinds: [String: String] = [:]
        var colors: [String: UInt32] = [:]
    }

    static let plain = CellStyle()
}

/// A run of a rich string (a shared string's `r`): its text, and the font
/// its `rPr` gives — nil where it gives none and the cell's font holds.
struct RichRun: Hashable, Sendable {
    var text: String
    var bold: Bool? = nil, italic: Bool? = nil, underline: Bool? = nil, strike: Bool? = nil
    var size: Double? = nil
    var fontName: String? = nil
    var color: UInt32? = nil
    /// 1 raised (superscript), -1 lowered (subscript).
    var script = 0
}

/// The fields a cell rarely has, read only by save, the formula bar and a few editing paths: kept apart so copying a Cell (every read of
/// one copies it) retains one reference, not five. Immutable: a write replaces the whole object, so no two cells ever share an edit.
final class CellExtra: @unchecked Sendable {
    let input: String?
    let arrayRef: String?
    let rawFormula: String?
    let spillRange: CellRange?
    let keptAttrs: [String: String]
    init(input: String? = nil, arrayRef: String? = nil, rawFormula: String? = nil, spillRange: CellRange? = nil, keptAttrs: [String: String] = [:]) {
        self.input = input; self.arrayRef = arrayRef; self.rawFormula = rawFormula; self.spillRange = spillRange; self.keptAttrs = keptAttrs
    }
    var isBlank: Bool { input == nil && arrayRef == nil && rawFormula == nil && spillRange == nil && keptAttrs.isEmpty }
}

struct Cell: Sendable {
    /// What was typed, as shown in the formula bar: "12", "=A1*2", "Total".
    /// Not stored by the loader (a string for every number cell and every formula was most of its allocations): while unset, a
    /// formula's text is its parsed formula's and a constant's is its value's.
    var input: String {
        get {
            if let i = _x?.input { return i }
            if let f = formula { return Formula.text(f) }
            return Cell.text(of: value)
        }
        set { _set(input: .some(newValue)) }
    }
    static func text(of v: CellValue) -> String {
        switch v {
        case .text(let s): return s
        case .bool(let b): return b ? "TRUE" : "FALSE"
        case .error(let e): return e.rawValue
        case .number(let n): return NumberFormat.full(n)
        case .empty: return ""
        }
    }
    /// Parsed when `input` starts with "=".
    var formula: FormulaExpr? = nil
    /// The current value: the constant, or the formula's last result.
    var value: CellValue = .empty {
        willSet { if _x?.input == nil, formula == nil, !value.isEmpty { _set(input: .some(Cell.text(of: value))) } }
    }
    var style: Int = 0
    /// The value a file carried for this formula. Kept when our engine
    /// cannot compute it (a function we do not have), so the cell shows
    /// what Excel last computed instead of #NAME?.
    var cached: CellValue? = nil
    /// A dynamic-array formula (typed here, or an array formula from a
    /// file): an array result spills into the cells below and right,
    /// operators work element by element. A file's other formulas keep
    /// Excel's implicit intersection, as they were written for it.
    var dynamic = false
    private var _x: CellExtra? = nil

    /// An array formula's range, as the file had it (t="array" ref=…).
    var arrayRef: String? {
        get { _x?.arrayRef }
        set { _set(arrayRef: .some(newValue)) }
    }
    /// A formula this engine cannot read (structured references, syntax it
    /// lacks), or a shared one depending on such: the file's `<f>` element,
    /// written back exactly until the cell is edited. Its value is the
    /// file's cached result.
    var rawFormula: String? {
        get { _x?.rawFormula }
        set { _set(rawFormula: .some(newValue)) }
    }
    /// The range its result spilled over, this cell at its top-left.
    var spillRange: CellRange? {
        get { _x?.spillRange }
        set { _set(spillRange: .some(newValue)) }
    }
    /// The file's vm / cm / ph on this cell — an image in the cell, a
    /// linked data type, other metadata — written back until it is edited.
    var keptAttrs: [String: String] {
        get { _x?.keptAttrs ?? [:] }
        set { _set(keptAttrs: newValue) }
    }

    private mutating func _set(input: String?? = nil, arrayRef: String?? = nil, rawFormula: String?? = nil, spillRange: CellRange?? = nil,
                               keptAttrs: [String: String]? = nil) {
        let o = _x
        let n = CellExtra(input: input ?? o?.input, arrayRef: arrayRef ?? o?.arrayRef, rawFormula: rawFormula ?? o?.rawFormula,
                          spillRange: spillRange ?? o?.spillRange, keptAttrs: keptAttrs ?? o?.keptAttrs ?? [:])
        _x = n.isBlank ? nil : n
    }

    init(input: String? = "", formula: FormulaExpr? = nil, value: CellValue = .empty, style: Int = 0, cached: CellValue? = nil,
         arrayRef: String? = nil, rawFormula: String? = nil, dynamic: Bool = false, spillRange: CellRange? = nil, keptAttrs: [String: String] = [:]) {
        self.formula = formula; self.value = value; self.style = style; self.cached = cached; self.dynamic = dynamic
        let x = CellExtra(input: input, arrayRef: arrayRef, rawFormula: rawFormula, spillRange: spillRange, keptAttrs: keptAttrs)
        self._x = x.isBlank ? nil : x
    }

    var isFormula: Bool { formula != nil || input.hasPrefix("=") }
}

final class Worksheet {
    var name: String
    var cells: [CellAddress: Cell] = [:] {
        didSet { _extent = nil }
    }
    private var _extent: CellAddress? = nil
    /// Column widths and row heights in points, where not the default.
    var colWidths: [Int: Double] = [:] { didSet { layoutVersion &+= 1 } }
    var rowHeights: [Int: Double] = [:] { didSet { layoutVersion &+= 1 } }
    /// Columns widened only to show a typed date or number: still Excel's
    /// "not set by hand", so the next one that does not fit widens them again.
    var widenedCols: Set<Int> = []
    var freezeRows = 0
    var freezeCols = 0
    var merges: [CellRange] = []

    /// Excel's defaults for Calibri 11: 8.43 characters (64 px) wide,
    /// 15 pt (20 px) high.
    static let defaultColWidth = 48.0
    static let defaultRowHeight = 15.0

    init(name: String) { self.name = name }

    func colWidth(_ c: Int) -> Double { colWidths[c] ?? defaultColWidthPt }
    func rowHeight(_ r: Int) -> Double { rowHeights[r] ?? defaultRowHeightPt }

    func value(_ a: CellAddress) -> CellValue { cells[a]?.value ?? .empty }

    /// The used area: from A1 to the furthest cell that holds anything.
    /// Cached: ranges ask for it on every evaluation.
    var usedExtent: CellAddress {
        if let e = _extent { return e }
        var r = 0, c = 0
        for a in cells.keys { r = max(r, a.row); c = max(c, a.col) }
        let e = CellAddress(row: r, col: c)
        _extent = e
        return e
    }

    /// Where this sheet came from in an .xlsx (xl/worksheets/sheet3.xml),
    /// and the elements of it we do not model, written back as they were:
    /// drawings, tables, conditional formats, data validations…
    var origin: String? = nil
    /// A chart sheet: no cells, one chart, a page of its own on paper.
    var isChartSheet: Bool { origin?.containsSubstring("/chartsheets/") ?? false }
    var keptElements: [(name: String, text: String)] = []
    /// The sheet's root start tag as the file wrote it (its namespaces,
    /// which kept elements may use).
    var rootTag: String? = nil
    var tabColor: String? = nil
    var hidden = false
    /// Hidden so that only code can show it again (state="veryHidden").
    var veryHidden = false
    /// The sheetId the file gave it, kept on save (nil for a sheet made here).
    var sheetId: Int? = nil
    var showGridlines = true
    /// Part of a selected group of sheets (tabSelected on several sheetViews).
    var tabSelected = false
    /// The view settings the sheet's own `sheetView` carries, kept in `viewAttrs` so they save as read.
    /// Zoom in percent (10 to 400); 100 is the default and is not written.
    var zoomPercent: Int {
        get { viewAttrs["zoomScale"].flatMap { Int($0) } ?? 100 }
        set {
            let z = max(10, min(400, newValue))
            if z == 100 { viewAttrs["zoomScale"] = nil; viewAttrs["zoomScaleNormal"] = nil }
            else { viewAttrs["zoomScale"] = String(z); viewAttrs["zoomScaleNormal"] = String(z) }
        }
    }
    /// Row numbers and column letters (Excel's "Headings").
    var showHeadings: Bool {
        get { viewAttrs["showRowColHeaders"] != "0" }
        set { viewAttrs["showRowColHeaders"] = newValue ? nil : "0" }
    }
    /// Cells show their formulas, not their results (Ctrl+`).
    var showFormulas: Bool {
        get { viewAttrs["showFormulas"] == "1" }
        set { viewAttrs["showFormulas"] = newValue ? "1" : nil }
    }
    /// Right-to-left sheet: column A at the right edge.
    var rightToLeft: Bool {
        get { viewAttrs["rightToLeft"] == "1" }
        set { viewAttrs["rightToLeft"] = newValue ? "1" : nil }
    }
    /// The active cell as saved, restored on open and written on save.
    var savedActive: CellAddress? = nil
    /// The sheet's default sizes, in points.
    var defaultColWidthPt = Worksheet.defaultColWidth { didSet { layoutVersion &+= 1 } }
    var defaultRowHeightPt = Worksheet.defaultRowHeight { didSet { layoutVersion &+= 1 } }
    var autoFilter: AutoFilter? = nil
    /// Pictures and charts, for display (the file's parts are kept as is).
    var drawings: [SheetDrawing] = []
    /// The pictures of the header and footer (`legacyDrawingHF`), by the VML shape's id: LH, CH, RH, LF, CF, RF.
    var headerPictures: [String: HeaderPicture] = [:]
    /// The drawing part the file kept them in, and its root tag (with the
    /// namespaces kept anchors use).
    var drawingPart: String? = nil
    var drawingRoot: String? = nil
    /// The drawings were added to, moved or deleted here: the part is
    /// written from the model on save (unchanged ones verbatim).
    var drawingsEdited = false
    /// Embedded objects and controls, for display (SheetObjects.swift).
    var objects: [SheetObject] = []
    /// `<col>` attributes besides width and hidden — a column's style,
    /// outline level, collapsed — by run (zero-based, inclusive).
    var colAttrRuns: [(lo: Int, hi: Int, attrs: [String: String])] = [] { didSet { layoutVersion &+= 1 } }
    /// Column widths as the file wrote them, in characters: written back
    /// exactly while the width is unchanged (points round to whole pixels).
    var colWidthChars: [Int: Double] = [:]
    var defaultColWidthChars: Double? = nil
    /// Rows whose height the file gave without calling it set
    /// (`customHeight`): Excel's own fit to their content, and the sheet's
    /// default height where the file calls THAT set. Printing scales the
    /// two kinds differently (SheetPrintMetrics).
    var fittedRows: Set<Int> = []
    var customDefaultRowHeight = false
    /// The pixels in one of those characters: the workbook's default
    /// font's widest digit (`Workbook.digitWidth`).
    var digitWidth = 7.0
    /// `<row>` attributes besides its height and hidden: style (s with
    /// customFormat), outline level, collapsed, thick borders…
    var rowAttrs: [Int: [String: String]] = [:] { didSet { layoutVersion &+= 1 } }
    /// `<sheetFormatPr>`'s other attributes: base and default column
    /// width, outline levels, zero-height rows.
    var formatPrAttrs: [String: String] = [:]
    /// The sheet view's other attributes — zoom, scroll position, show
    /// zeros, right to left, page layout view — written back as read.
    var viewAttrs: [String: String] = [:]
    /// A split (not frozen) pane as the file had it: `pane`'s attributes and each `selection`'s, written back while the sheet has no frozen pane.
    var splitPane: [String: String]? = nil
    var splitSelections: [[String: String]] = []
    /// 0, or which freeze (1 rows, 2 columns, 3 both) the file's `splitSelections` were written under.
    var selectionFreeze = 0
    /// Whether the file gave the sheet a view (`sheetView`) at all. Excel
    /// prints a sheet without one with its set row heights halved — labs
    /// of 20 pt rows, Excel 16, 2026-10-15: 9.72 pt on paper, 19.32 with an
    /// empty `<sheetView workbookViewId="0"/>` (bug62181, 83 rows a page).
    var hasView = true
    /// Rows holding rich text with a superscript or subscript run, whose
    /// height Excel fits taller than their fonts' line: their fit, as the
    /// file has it, is kept (45544's "Number of Hires⁽¹⁾" header rows).
    /// Rows of turned text (`CellStyle.rotation`) likewise.
    var scriptRows: Set<Int> = []
    /// Cells holding a rich string, as its runs. Drawn so only while their
    /// text is still the cell's (an edit leaves them behind).
    var richText: [CellAddress: [RichRun]] = [:]
    /// A rich string's own XML (its runs' properties, phonetic guides) with the plain text it held: written back as read while the cell's text is still that.
    var richRaw: [CellAddress: (text: String, xml: String)] = [:]
    /// A formatted row's span as the file gave it (`spans`): the columns
    /// in it the file has no cell for. Excel makes them cells in the row's
    /// format, and a fill or border there prints (FormatConditionTests'
    /// yellow row 1, cells A–D, spans 1:8, puts columns E–H on a page of
    /// their own).
    var rowSpanGaps: [Int: [Int]] = [:]

    /// The style a new cell at `a` takes: its row's when the row is
    /// formatted, else its column's, as Excel does.
    func defaultStyle(at a: CellAddress) -> Int {
        if let r = rowAttrs[a.row], r["customFormat"] == "1", let s = r["s"].flatMap({ Int($0) }) { return s }
        return colStyle(a.col) ?? 0
    }

    func colStyle(_ col: Int) -> Int? {
        colAttrRuns.last { $0.lo <= col && col <= $0.hi && $0.attrs["style"] != nil }.flatMap { $0.attrs["style"].flatMap { Int($0) } }
    }

    func rowStyle(_ row: Int) -> Int? {
        guard let r = rowAttrs[row], r["customFormat"] == "1" else { return nil }
        return r["s"].flatMap { Int($0) }
    }

    /// Values dynamic arrays spilled into otherwise empty cells: shown and
    /// read like the cells' own, written to the file beside their formula.
    var spilled: [CellAddress: CellValue] = [:]
    /// What the file held in the cells of an array formula's range other than its first (Excel's last result): written back where
    /// our own result leaves a cell blank, so a viewer that does not recalculate still shows the file's values.
    var fileSpill: [CellAddress: CellValue] = [:]
    /// Excel tables on the sheet (their parts are kept; see Tables.swift).
    var tables: [SheetTable] = []
    /// Pivot tables on the sheet, for their styles (the parts are kept).
    var pivots: [SheetPivot] = []
    /// Tables deleted with all their rows or columns: their parts, their
    /// relationship and their `<tablePart>` go on save.
    var removedTables: [SheetTable] = []
    /// Notes on cells, and the parts they came from (see Notes.swift).
    var notes: [SheetNote] = []
    /// The sheet's hyperlink relationships: id → URL.
    var linkTargets: [String: String] = [:]
    var noteParts = SheetNoteParts()
    /// Rows the filter hides (kept apart from rowHeights, so each keeps its height).
    var filteredRows: Set<Int> = [] { didSet { layoutVersion &+= 1 } }
    /// Rows hidden by hand or by a collapsed group: kept apart from their
    /// heights, so showing them again gives each its own height back.
    var hiddenRows: Set<Int> = [] { didSet { layoutVersion &+= 1 } }

    /// Columns hidden by hand or by a collapsed group, apart from their widths.
    var hiddenCols: Set<Int> = [] { didSet { layoutVersion &+= 1 } }
    func isColHidden(_ c: Int) -> Bool { hiddenCols.contains(c) || colWidths[c] == 0 || hiddenColRuns.contains { $0.contains(c) } }
    /// Hidden runs too long to list column by column (FillWithoutColor's
    /// G to the sheet's end).
    var hiddenColRuns: [ClosedRange<Int>] = []
    /// A hidden run's own width in characters, by the run's first column, so showing it again changes no layout.
    var hiddenRunChars: [Int: Double] = [:]

    /// Hidden for any reason: filtered, hidden, or height 0.
    func isRowHidden(_ r: Int) -> Bool { filteredRows.contains(r) || hiddenRows.contains(r) || rowHeights[r] == 0 }
    func outlineLevel(row r: Int) -> Int { rowAttrs[r]?["outlineLevel"].flatMap { Int($0) } ?? 0 }
    /// Bumped by anything that moves rows or columns on screen, so the grid
    /// can keep its geometry between paints.
    private(set) var layoutVersion = 0

    /// A copy of every property: an undo step's snapshot. The cell
    /// dictionary is copy-on-write, so this is cheap until one side changes.
    func copy() -> Worksheet {
        let s = Worksheet(name: name)
        s.cells = cells
        s.colWidths = colWidths
        s.rowHeights = rowHeights
        s.freezeRows = freezeRows
        s.freezeCols = freezeCols
        s.merges = merges
        s.origin = origin
        s.keptElements = keptElements
        s.rootTag = rootTag
        s.tabColor = tabColor
        s.hidden = hidden
        s.veryHidden = veryHidden
        s.sheetId = sheetId
        s.showGridlines = showGridlines
        s.savedActive = savedActive
        s.defaultColWidthPt = defaultColWidthPt
        s.defaultRowHeightPt = defaultRowHeightPt
        s.autoFilter = autoFilter
        s.drawings = drawings
        s.objects = objects
        s.drawingPart = drawingPart
        s.drawingRoot = drawingRoot
        s.drawingsEdited = drawingsEdited
        s.spilled = spilled
        s.fileSpill = fileSpill
        s.colAttrRuns = colAttrRuns
        s.colWidthChars = colWidthChars
        s.widenedCols = widenedCols
        s.defaultColWidthChars = defaultColWidthChars
        s.digitWidth = digitWidth
        s.fittedRows = fittedRows
        s.customDefaultRowHeight = customDefaultRowHeight
        s.rowAttrs = rowAttrs
        s.formatPrAttrs = formatPrAttrs
        s.viewAttrs = viewAttrs
        s.splitPane = splitPane
        s.splitSelections = splitSelections
        s.selectionFreeze = selectionFreeze
        s.hasView = hasView
        s.scriptRows = scriptRows
        s.richText = richText
        s.richRaw = richRaw
        s.rowSpanGaps = rowSpanGaps
        s.hiddenColRuns = hiddenColRuns
        s.hiddenRunChars = hiddenRunChars
        s.tables = tables
        s.pivots = pivots
        s.removedTables = removedTables
        s.notes = notes
        s.linkTargets = linkTargets
        s.noteParts = noteParts
        s.filteredRows = filteredRows
        s.hiddenRows = hiddenRows
        s.hiddenCols = hiddenCols
        return s
    }
}

final class Workbook {
    var sheets: [Worksheet]
    var styles: [CellStyle] = [.plain]
    /// The file's default font (its first one, the Normal style's) where
    /// that is not Calibri 11: a style whose `fontName`/`fontSize` is nil
    /// draws in it, and column widths are counted in its digits.
    var defaultFontName: String? = nil
    var defaultFontSize: Double? = nil
    var defaultFontBold = false
    /// The Normal font's own face where it is a theme (scheme) font of another name.
    var defaultFontOwnName: String? = nil
    func fontName(_ st: CellStyle) -> String { st.fontName ?? defaultFontName ?? OfficeFonts.defaultFamily }
    func fontSize(_ st: CellStyle) -> Double { st.fontSize ?? defaultFontSize ?? 11 }
    /// The widest digit of the default font, in pixels at 96 dpi — the
    /// unit of a stored column width (7 for Calibri 11).
    var digitWidth: Double { Workbook.digitWidth(family: defaultFontName ?? OfficeFonts.defaultFamily, size: defaultFontSize ?? 11) }

    /// A digit's width in pixels as Excel counts it: the face's advance at
    /// the size, in whole pixels. The faces are Windows' own, by name — what
    /// the shipped clones measure is not the question, since the file's
    /// widths were written against these. An East Asian face's digits are
    /// half its cell, rounded up (its bitmap strikes): 8 px for
    /// MS PGothic 11 and SimSun 11, where 72 px is the default column.
    static func digitWidth(family: String, size: Double) -> Double {
        let px = size * 96 / 72
        let n = family.trimmingWhitespace().lowercased()
        let advances: [String: Double] = [
            "calibri": 0.507, "calibri light": 0.507, "carlito": 0.507, "aptos": 0.52, "aptos narrow": 0.5,
            "arial": 0.556, "helvetica": 0.556, "liberation sans": 0.556, "arimo": 0.556, "ms sans serif": 0.556,
            "microsoft sans serif": 0.556, "arial narrow": 0.456, "arial unicode ms": 0.556,
            "verdana": 0.636, "tahoma": 0.546, "segoe ui": 0.539, "trebuchet ms": 0.524, "century gothic": 0.554,
            "times new roman": 0.5, "liberation serif": 0.5, "times": 0.5, "georgia": 0.614, "cambria": 0.554,
            "garamond": 0.469, "book antiqua": 0.5, "palatino linotype": 0.5, "comic sans ms": 0.61,
            "courier new": 0.6, "liberation mono": 0.6, "courier": 0.6, "consolas": 0.55, "lucida console": 0.603,
            "malgun gothic": 0.55, "yu gothic": 0.55, "dengxian": 0.53, "microsoft yahei": 0.58, "meiryo": 0.6,
            "meiryo ui": 0.56,
        ]
        if let a = advances[n] { return max(1, (px * a).rounded()) }
        // Excel's own widest digit for the Korean bitmap-strike faces at 9 to
        // 12 pt, read from its column widths (lab/dotumcols print, 2026-11-24):
        // not whole pixels, and not half the cell.
        let koDigits: [String: [Double]] = [   // 9, 10, 11, 12 pt
            "dotum": [6.5, 8, 8.5, 9.5], "돋움": [6.5, 8, 8.5, 9.5],
            "gulim": [6.5, 8, 8.5, 9], "굴림": [6.5, 8, 8.5, 9],
            "batang": [6, 8, 8.5, 9.5], "바탕": [6, 8, 8.5, 9.5],
            "dotumche": [6, 7, 7.5, 8], "돋움체": [6, 7, 7.5, 8],
        ]
        if let t = koDigits[n], size == size.rounded(), size >= 9, size <= 12 { return t[Int(size) - 9] }
        let eastAsian = ["gothic", "mincho", "simsun", "simhei", "mingliu", "gulim", "dotum", "batang", "fangsong", "kaiti"]
        if n.unicodeScalars.contains(where: { $0.value > 0x2E7F }) || eastAsian.contains(where: { n.containsSubstring($0) }) {
            return max(1, (px.rounded() / 2).rounded(.up))
        }
        return max(1, (px * 0.556).rounded())
    }
    /// Other workbooks this one links to, with the values the file saved
    /// of them (xl/externalLinks): read as Excel does until a refresh.
    var externals: [ExternalBook] = []
    var names: [String: String] = [:]   // defined name (uppercased) → "Sheet1!$A$1:$B$4"
    /// The names as the file spelled them, for writing back.
    var nameSpellings: [String: String] = [:]
    /// The file's own styles.xml pieces, so its cell formats are written
    /// back exactly as read (see Xlsx._stylesXML).
    var styleSource: StyleSource? = nil

    /// The .xlsx package it was read from: every part, so a save keeps
    /// what the model does not (charts, drawings, themes, pivot caches).
    var package: [ZipEntry]? = nil
    /// The sheet that was in front when the file was saved.
    var activeTab = 0
    /// workbookView showComments: "commIndAndComment" is Review > Show All Notes on, "commNone" hides the red
    /// triangles too; nil (Excel's default, "commIndicator") shows a note only on hover.
    var showComments: String? = nil
    /// Dates count from 1904 (workbookPr date1904): kept as read.
    var date1904 = false
    /// calcPr iterate: circular references compute iteratively, up to
    /// iterateCount times or until no cell moves by more than iterateDelta.
    var iterate = false
    var iterateCount = 100
    var iterateDelta = 0.001
    /// workbookProtection lockStructure: sheets cannot be added, deleted,
    /// renamed, hidden or shown.
    var structureLocked: Bool {
        get { workbookProtection?["lockStructure"] == "1" || workbookProtection?["lockStructure"] == "true" }
        set { var a = workbookProtection ?? [:]; a["lockStructure"] = newValue ? "1" : nil; workbookProtection = a.isEmpty ? nil : a }
    }
    /// The `workbookProtection` element's attributes as the file had them (nil: none), kept so a save writes them back.
    var workbookProtection: [String: String]? = nil
    /// Every defined name the file had, built-ins (print areas, filter
    /// ranges) and sheet-local ones included, in order: what a save writes,
    /// with references kept current as rows, columns and sheets move.
    var fileNames: [DefinedName] = []
    /// styles.xml's parts the model does not rebuild — `dxfs` (the formats
    /// conditional formatting and tables point at), `tableStyles`,
    /// `colors`, `extLst` — written back as the file had them.
    var keptStyleParts: [String: String] = [:]
    /// Those differential formats, read for drawing conditional formats.
    var dxfs: [DxfStyle] = []
    /// The file's own table styles (`tableStyles`): by name, each part of a
    /// table it formats (wholeTable, headerRow, firstRowStripe…) and the
    /// differential format it gives that part.
    var tableStyles: [String: [String: Int]] = [:]
    /// The theme's twelve colour slots (lt1, dk1, lt2, dk2, accent1–6, links).
    var themeColors: [UInt32] = Xlsx._themeColors(nil)
    /// What charts draw with: the file's theme, or Office's.
    var chartTheme = DeckTheme.office

    init(sheets: [Worksheet] = [Worksheet(name: "Sheet1")]) {
        self.sheets = sheets
    }

    /// A defined name's formula, as `sheet` reads it: that sheet's own
    /// name of it (`localSheetId`), else the book's. `Sheet!Name` is the
    /// named sheet's. (lo-named-ranges-global's Sheet1 reads its own
    /// Local1, 3, where the book's table held another sheet's, 5.)
    func nameText(_ n: String, sheet: Int? = nil) -> String? {
        var bare = n, home = sheet
        if let bang = n.lastIndex(of: "!") {
            bare = String(n[n.index(after: bang)...])
            var s = String(n[..<bang])
            if s.hasPrefix("'"), s.hasSuffix("'"), s.count >= 2 { s = String(s.dropFirst().dropLast()).replacingAll("''", with: "'") }
            home = self.sheet(named: s)
        }
        let key = bare.uppercased()
        if let home, let own = fileNames.last(where: { $0.localSheet == home && $0.name.uppercased() == key }) { return own.text }
        return names[key]
    }

    func sheet(named name: String) -> Int? {
        let n = name.lowercased()
        // A remembered index is trusted only after the sheet at it still has that name.
        if let i = _sheetIndexCache[n], i < sheets.count, sheets[i].name.lowercased() == n { return i }
        let r = sheets.firstIndex { $0.name.lowercased() == n }
        if let r { _sheetIndexCache[n] = r }
        return r
    }
    private var _sheetIndexCache: [String: Int] = [:]

    /// The index of a style, added to the table if new.
    func styleIndex(_ s: CellStyle) -> Int {
        // Back to exactly the file's format it came from: that one, as read.
        if let b = s.baseXf, b < styles.count, styles[b] == s { return b }
        if let i = styles.firstIndex(of: s) { return i }
        // A style with no origin that one of the file's formats matches
        // (Clear Formats → Normal): that format, as the file had it.
        if s.baseXf == nil, let i = styles.indices.first(where: { styles[$0].baseXf == $0 && { var t = s; t.baseXf = $0; return t == styles[$0] }($0) }) {
            return i
        }
        styles.append(s)
        return styles.count - 1
    }

    func style(_ i: Int) -> CellStyle { i >= 0 && i < styles.count ? styles[i] : .plain }

    /// A name for a new sheet: Sheet2, Sheet3, …
    func nextSheetName() -> String {
        var n = sheets.count + 1
        while sheet(named: "Sheet\(n)") != nil { n += 1 }
        return "Sheet\(n)"
    }
}

/// One `<definedName>`: its name, scope, other attributes and formula.
struct DefinedName: Equatable, Sendable {
    var name: String
    /// `localSheetId`: the sheet (by position) it belongs to, or nil for the book.
    var localSheet: Int?
    /// hidden, comment, function… written back as read.
    var attrs: [String: String]
    var text: String

    var isBuiltIn: Bool { name.hasPrefix("_xlnm.") }
}

/// A differential format: only what it sets overrides the cell's own.
struct DxfStyle: Equatable, Sendable {
    var bold: Bool? = nil
    var italic: Bool? = nil
    var underline: Bool? = nil
    var strike: Bool? = nil
    var color: UInt32? = nil
    var fill: UInt32? = nil
    /// The number format the rule shows its cells in (`dxf/numFmt`).
    var numberFormat: String? = nil
    /// Rules by side — left, right, top, bottom, and horizontal and
    /// vertical between the cells of what it formats — and their colour.
    var borders: [String: UInt32] = [:]
}

/// A styles.xml as read: its numFmts, fonts, fills and borders as written,
/// its named styles, and each cell format's attributes and children.
struct StyleSource: Sendable {
    struct Xf: Sendable {
        var attrs: [String: String]
        var alignment: String?
        var protection: String?
        var extra: String               // any other children (extLst), as written
        var raw = ""                    // the whole element, as written
    }
    var numFmts: [(id: Int, code: String, raw: String)] = []
    var fonts: [String] = []
    var fills: [String] = []
    var borders: [String] = []
    /// The container start tags as written (they can carry x14ac:knownFonts…).
    var tags: [String: String] = [:]
    var cellStyleXfs: String? = nil
    var cellStyles: String? = nil
    var xfs: [Xf] = []
}


/// One externalLink part: the linked file's name, its sheets, its defined
/// names (uppercased → refersTo) and the cells it saved.
struct ExternalBook: Sendable {
    var file: String = ""
    var sheetNames: [String] = []
    var names: [String: String] = [:]
    var cells: [Int: [CellAddress: CellValue]] = [:]

    func sheetIndex(_ name: String) -> Int? {
        sheetNames.firstIndex { $0.lowercased() == name.lowercased() }
    }
}

