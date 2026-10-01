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
    var underline = false
    var strike = false
    var fontName: String? = nil
    var fontSize: Double? = nil
    var color: UInt32? = nil       // 0xRRGGBB
    var fill: UInt32? = nil        // 0xRRGGBB
    var hAlign: HAlign = .general
    var vAlign: VAlign = .bottom
    var wrap = false
    var numberFormat = "General"
    var borders = Borders()

    enum HAlign: String, Hashable, Sendable { case general, left, center, right }
    enum VAlign: String, Hashable, Sendable { case top, center, bottom }

    struct Borders: Hashable, Sendable {
        var top = false, left = false, bottom = false, right = false
    }

    static let plain = CellStyle()
}

struct Cell: Sendable {
    /// What was typed, as shown in the formula bar: "12", "=A1*2", "Total".
    var input: String
    /// Parsed when `input` starts with "=".
    var formula: FormulaExpr? = nil
    /// The current value: the constant, or the formula's last result.
    var value: CellValue = .empty
    var style: Int = 0
    /// The value a file carried for this formula. Kept when our engine
    /// cannot compute it (a function we do not have), so the cell shows
    /// what Excel last computed instead of #NAME?.
    var cached: CellValue? = nil
    /// An array formula's range, as the file had it (t="array" ref=…).
    var arrayRef: String? = nil
    /// A formula this engine cannot read (structured references, syntax it
    /// lacks), or a shared one depending on such: the file's `<f>` element,
    /// written back exactly until the cell is edited. Its value is the
    /// file's cached result.
    var rawFormula: String? = nil
    /// A dynamic-array formula (typed here, or an array formula from a
    /// file): an array result spills into the cells below and right,
    /// operators work element by element. A file's other formulas keep
    /// Excel's implicit intersection, as they were written for it.
    var dynamic = false
    /// The range its result spilled over, this cell at its top-left.
    var spillRange: CellRange? = nil
    /// The file's vm / cm / ph on this cell — an image in the cell, a
    /// linked data type, other metadata — written back until it is edited.
    var keptAttrs: [String: String] = [:]

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
    var keptElements: [(name: String, text: String)] = []
    /// The sheet's root start tag as the file wrote it (its namespaces,
    /// which kept elements may use).
    var rootTag: String? = nil
    var tabColor: String? = nil
    var hidden = false
    var showGridlines = true
    /// The active cell as saved, restored on open and written on save.
    var savedActive: CellAddress? = nil
    /// The sheet's default sizes, in points.
    var defaultColWidthPt = Worksheet.defaultColWidth { didSet { layoutVersion &+= 1 } }
    var defaultRowHeightPt = Worksheet.defaultRowHeight { didSet { layoutVersion &+= 1 } }
    var autoFilter: AutoFilter? = nil
    /// Pictures and charts, for display (the file's parts are kept as is).
    var drawings: [SheetDrawing] = []
    /// The drawing part the file kept them in, and its root tag (with the
    /// namespaces kept anchors use).
    var drawingPart: String? = nil
    var drawingRoot: String? = nil
    /// The drawings were added to, moved or deleted here: the part is
    /// written from the model on save (unchanged ones verbatim).
    var drawingsEdited = false
    /// Values dynamic arrays spilled into otherwise empty cells: shown and
    /// read like the cells' own, written to the file beside their formula.
    var spilled: [CellAddress: CellValue] = [:]
    /// Excel tables on the sheet (their parts are kept; see Tables.swift).
    var tables: [SheetTable] = []
    /// Notes on cells, and the parts they came from (see Notes.swift).
    var notes: [SheetNote] = []
    /// The sheet's hyperlink relationships: id → URL.
    var linkTargets: [String: String] = [:]
    var noteParts = SheetNoteParts()
    /// Rows the filter hides (kept apart from rowHeights, so each keeps its height).
    var filteredRows: Set<Int> = [] { didSet { layoutVersion &+= 1 } }
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
        s.showGridlines = showGridlines
        s.savedActive = savedActive
        s.defaultColWidthPt = defaultColWidthPt
        s.defaultRowHeightPt = defaultRowHeightPt
        s.autoFilter = autoFilter
        s.drawings = drawings
        s.drawingPart = drawingPart
        s.drawingRoot = drawingRoot
        s.drawingsEdited = drawingsEdited
        s.spilled = spilled
        s.tables = tables
        s.notes = notes
        s.linkTargets = linkTargets
        s.noteParts = noteParts
        s.filteredRows = filteredRows
        return s
    }
}

final class Workbook {
    var sheets: [Worksheet]
    var styles: [CellStyle] = [.plain]
    var names: [String: String] = [:]   // defined name (uppercased) → "Sheet1!$A$1:$B$4"
    /// The names as the file spelled them, for writing back.
    var nameSpellings: [String: String] = [:]
    /// The .xlsx package it was read from: every part, so a save keeps
    /// what the model does not (charts, drawings, themes, pivot caches).
    var package: [ZipEntry]? = nil
    /// The sheet that was in front when the file was saved.
    var activeTab = 0
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
    /// The theme's twelve colour slots (lt1, dk1, lt2, dk2, accent1–6, links).
    var themeColors: [UInt32] = Xlsx._themeColors(nil)
    /// What charts draw with: the file's theme, or Office's.
    var chartTheme = DeckTheme.office

    init(sheets: [Worksheet] = [Worksheet(name: "Sheet1")]) {
        self.sheets = sheets
    }

    func sheet(named name: String) -> Int? {
        let n = name.lowercased()
        return sheets.firstIndex { $0.name.lowercased() == n }
    }

    /// The index of a style, added to the table if new.
    func styleIndex(_ s: CellStyle) -> Int {
        if let i = styles.firstIndex(of: s) { return i }
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
}
