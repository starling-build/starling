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
