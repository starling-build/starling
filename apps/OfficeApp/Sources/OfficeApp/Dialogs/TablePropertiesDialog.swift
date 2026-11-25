// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// W-TB-8: Table Properties. Table (alignment, indent, text wrapping), Row (height, may break across
// pages, repeat as header), Column (preferred width) and Cell (vertical alignment, margins, preferred width).

import Flutter
import FlutterSwiftBridge
import OfficeText

/// The dialog's values, read from the caret's table and written back in one step.
struct TablePropertiesValues: Equatable {
    enum Wrap: Equatable { case none, around }
    enum HeightRule: Equatable { case auto, atLeast, exactly }

    var alignment: ParagraphAlignment = .left
    var indent: Double = 0
    var wrap: Wrap = .none
    var heightRule: HeightRule = .auto
    var height: Double = 0
    var mayBreak = true
    var repeatHeader = false
    var columnWidth: Double = 0
    var verticalAlign = "top"
    /// The caret cell's own margins (Cell tab; written as that cell's tcMar) and the table's default ones (Table tab).
    var marginTop: Double = 0, marginBottom: Double = 0, marginLeft: Double = 5.4, marginRight: Double = 5.4
    var tableMarginTop: Double = 0, tableMarginBottom: Double = 0, tableMarginLeft: Double = 5.4, tableMarginRight: Double = 5.4
    private var startCell: [Double] = [], startTable: [Double] = []

    /// What Word writes for a table that text runs around.
    static let aroundPosition = "<w:tblpPr w:leftFromText=\"180\" w:rightFromText=\"180\" w:vertAnchor=\"text\" w:tblpY=\"1\"/>"

    init() {}

    init(of c: RichDocumentController) {
        guard let cell = c.currentCell else { return }
        let t = c.currentTableStyle ?? TableStyle()
        alignment = t.alignment
        indent = t.indent
        wrap = t.keptPosition == nil ? .none : .around
        let row = cell.row
        if let h = t.rowHeights[row] { height = h; heightRule = t.rowsExactHeight.contains(row) ? .exactly : .atLeast }
        mayBreak = !t.rowsCantSplit.contains(row)
        repeatHeader = t.headerRow && row < t.headerRowCount
        let cols = c.document.columnCount(of: cell.table)
        var widths = c.document.tableColumns[cell.table]
        if widths?.count != cols { widths = nil }
        columnWidth = widths.map { cell.column < $0.count ? $0[cell.column] : 0 } ?? 468.0 / Double(max(1, cols))
        verticalAlign = cell.verticalAlign ?? "top"
        tableMarginTop = t.cellMarginTop ?? 0; tableMarginBottom = t.cellMarginBottom ?? 0
        tableMarginLeft = t.cellMarginLeft ?? 5.4; tableMarginRight = t.cellMarginRight ?? 5.4
        marginTop = cell.padding?.top ?? tableMarginTop; marginBottom = cell.padding?.bottom ?? tableMarginBottom
        marginLeft = cell.padding?.left ?? tableMarginLeft; marginRight = cell.padding?.right ?? tableMarginRight
        startCell = [marginTop, marginBottom, marginLeft, marginRight]
        startTable = [tableMarginTop, tableMarginBottom, tableMarginLeft, tableMarginRight]
    }

    func apply(to c: RichDocumentController) {
        guard let cell = c.currentCell, let rows = c.targetRows else { return }
        let new = self
        c.setTableStyle { t in
            t.alignment = new.alignment
            t.indent = new.indent
            if new.wrap == .around { if t.keptPosition == nil { t.keptPosition = Self.aroundPosition } } else { t.keptPosition = nil }
            for r in rows {
                switch new.heightRule {
                case .auto: t.rowHeights[r] = nil; t.rowsExactHeight.remove(r)
                case .atLeast: t.rowHeights[r] = max(1, new.height); t.rowsExactHeight.remove(r)
                case .exactly: t.rowHeights[r] = max(1, new.height); t.rowsExactHeight.insert(r)
                }
                if new.mayBreak { t.rowsCantSplit.remove(r) } else { t.rowsCantSplit.insert(r) }
            }
            // Repeating covers the rows from the top down to this one (Word's header rows are contiguous from the first).
            let last = rows.upperBound
            if new.repeatHeader {
                t.headerRow = true
                t.headerRowCount = max(t.headerRow ? t.headerRowCount : 0, last + 1)
            } else if t.headerRow, rows.lowerBound < t.headerRowCount {
                t.headerRowCount = rows.lowerBound
                if t.headerRowCount == 0 { t.headerRow = false; t.headerRowCount = 1 }
            }
            if [new.tableMarginTop, new.tableMarginBottom, new.tableMarginLeft, new.tableMarginRight] != new.startTable {
                t.cellMarginTop = max(0, new.tableMarginTop); t.cellMarginBottom = max(0, new.tableMarginBottom)
                t.cellMarginLeft = max(0, new.tableMarginLeft); t.cellMarginRight = max(0, new.tableMarginRight)
            }
        }
        let cols = c.document.columnCount(of: cell.table)
        var widths = c.document.tableColumns[cell.table]
        if widths?.count != cols { widths = Array(repeating: 468.0 / Double(max(1, cols)), count: cols) }
        if cell.column < cols, columnWidth >= 1, abs(widths![cell.column] - columnWidth) > 0.01 {
            widths![cell.column] = columnWidth
            c.setTableColumnWidths(cell.table, widths)
        }
        if verticalAlign != (cell.verticalAlign ?? "top") { c.setCellVerticalAlignment(verticalAlign) }
        if [marginTop, marginBottom, marginLeft, marginRight] != startCell {
            c.setCellMargins(top: marginTop, left: marginLeft, bottom: marginBottom, right: marginRight)
        }
    }
}

final class TablePropertiesDialog: StatefulWidget {
    let initial: TablePropertiesValues
    let unit: LengthUnit
    let onOK: (TablePropertiesValues) -> Void
    let onCancel: () -> Void
    init(initial: TablePropertiesValues, unit: LengthUnit = .inch, onOK: @escaping (TablePropertiesValues) -> Void, onCancel: @escaping () -> Void) {
        self.initial = initial; self.unit = unit; self.onOK = onOK; self.onCancel = onCancel
        super.init()
    }
    override func createState() -> State<StatefulWidget> { TablePropertiesDialogState() }
}

final class TablePropertiesDialogState: State<StatefulWidget> {
    private var _w: TablePropertiesDialog { widget as! TablePropertiesDialog }
    private(set) var v = TablePropertiesValues()

    override func initState() {
        super.initState()
        v = _w.initial
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let unit = _w.unit
        func choice(_ id: String, _ label: String, _ on: Bool, _ action: @escaping () -> Void) -> Widget {
            PKeyed(id, Chrome.textToggle(label, on, fluent, action: action))
        }
        func row(_ label: String, _ items: [Widget]) -> Widget {
            Padding(padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 8), child: Row(crossAxisAlignment: .center, children:
                [SizedBox(width: 130, height: nil, child: Text(label))] + items))
        }
        func spin(_ id: String, _ pts: Double, min: Double = 0, max: Double = 1584, _ set: @escaping (Double) -> Void) -> Widget {
            PKeyed(id, UnitSpinner(points: pts, unit: unit, min: min, max: max, width: 90) { [weak self] n in self?.setState { set(n) } })
        }
        let aligns: [(String, String, ParagraphAlignment)] = [("tp-left", "Left", .left), ("tp-center", "Center", .center), ("tp-right", "Right", .right)]
        let table = Column(crossAxisAlignment: .start, children: [
            row("Alignment", aligns.map { id, t, a in choice(id, t, v.alignment == a) { [weak self] in self?.setState { self?.v.alignment = a } } }),
            row("Indent from left", [spin("tp-indent", v.indent, min: -72) { [weak self] n in self?.v.indent = n }]),
            row("Text wrapping", [
                choice("tp-wrap-none", "None", v.wrap == .none) { [weak self] in self?.setState { self?.v.wrap = .none } },
                choice("tp-wrap-around", "Around", v.wrap == .around) { [weak self] in self?.setState { self?.v.wrap = .around } },
            ]),
            row("Default margin top", [spin("tp-tm-top", v.tableMarginTop) { [weak self] n in self?.v.tableMarginTop = n }]),
            row("Default margin bottom", [spin("tp-tm-bottom", v.tableMarginBottom) { [weak self] n in self?.v.tableMarginBottom = n }]),
            row("Default margin left", [spin("tp-tm-left", v.tableMarginLeft) { [weak self] n in self?.v.tableMarginLeft = n }]),
            row("Default margin right", [spin("tp-tm-right", v.tableMarginRight) { [weak self] n in self?.v.tableMarginRight = n }]),
        ])
        let rules: [(String, String, TablePropertiesValues.HeightRule)] = [("tp-h-auto", "Auto", .auto), ("tp-h-least", "At least", .atLeast), ("tp-h-exact", "Exactly", .exactly)]
        var rowChildren: [Widget] = [row("Row height", rules.map { id, t, r in choice(id, t, v.heightRule == r) { [weak self] in
            self?.setState { self?.v.heightRule = r; if r != .auto, (self?.v.height ?? 0) < 1 { self?.v.height = 18 } } } })]
        if v.heightRule != .auto { rowChildren.append(row("Height", [spin("tp-height", v.height, min: 1) { [weak self] n in self?.v.height = n }])) }
        rowChildren.append(row("", [choice("tp-break", "Allow row to break across pages", v.mayBreak) { [weak self] in self?.setState { self?.v.mayBreak.toggle() } }]))
        rowChildren.append(row("", [choice("tp-header", "Repeat as header row at the top of each page", v.repeatHeader) { [weak self] in self?.setState { self?.v.repeatHeader.toggle() } }]))
        let rowPage = Column(crossAxisAlignment: .start, children: rowChildren)
        let columnPage = Column(crossAxisAlignment: .start, children: [
            row("Preferred width", [spin("tp-col-width", v.columnWidth, min: 1) { [weak self] n in self?.v.columnWidth = n }]),
        ])
        let valigns: [(String, String, String)] = [("tp-v-top", "Top", "top"), ("tp-v-center", "Center", "center"), ("tp-v-bottom", "Bottom", "bottom")]
        let cellPage = Column(crossAxisAlignment: .start, children: [
            row("Vertical alignment", valigns.map { id, t, a in choice(id, t, v.verticalAlign == a) { [weak self] in self?.setState { self?.v.verticalAlign = a } } }),
            row("Preferred width", [spin("tp-cell-width", v.columnWidth, min: 1) { [weak self] n in self?.v.columnWidth = n }]),
            row("Margin top", [spin("tp-m-top", v.marginTop) { [weak self] n in self?.v.marginTop = n }]),
            row("Margin bottom", [spin("tp-m-bottom", v.marginBottom) { [weak self] n in self?.v.marginBottom = n }]),
            row("Margin left", [spin("tp-m-left", v.marginLeft) { [weak self] n in self?.v.marginLeft = n }]),
            row("Margin right", [spin("tp-m-right", v.marginRight) { [weak self] n in self?.v.marginRight = n }]),
        ])
        return DialogShell(title: "Table Properties",
                           tabs: [DialogTab(title: "Table", page: table), DialogTab(title: "Row", page: rowPage),
                                  DialogTab(title: "Column", page: columnPage), DialogTab(title: "Cell", page: cellPage)],
                           width: 520,
                           onOK: { [weak self] in guard let self else { return }; self._w.onOK(self.v) },
                           onCancel: { [weak self] in self?._w.onCancel() })
    }
}
