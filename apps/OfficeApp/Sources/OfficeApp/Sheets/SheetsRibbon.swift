// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The ribbon's tabs for a workbook: Home (clipboard, font, alignment,
// number, editing), Insert, Formulas, Data and View. Each button acts on
// the selection through the workbook's controller; the few that need the
// grid (the clipboard, starting a formula in the editor) go through
// `WorkbookController.onCommand`, which the shell points at the grid.

import Flutter
import OfficeText
import FlutterSwiftBridge
import FluentSystemIcons
import Foundation

/// What the ribbon asks of the grid.
enum SheetCommand {
    case cut, copy, paste, pasteSpecial, formatPainter
    case symbol                    // Insert → Symbol: the shared picker
    case startFormula(String)      // "=SUM(" into the editor, the selection's range filled in
    case zoom(Double)
    case toggleGridlines
    case status(String)
    case cellsDialog(insert: Bool)   // Insert / Delete Cells…
    case sizeDialog(SizeKind)        // Row Height…, Column Width…, Default Width…
    case conditionalFormat         // Home → Conditional Formatting
    case conditionalRules          // Home → Conditional Formatting → Manage Rules
    case dataValidation            // Data → Data Validation
    case consolidate               // Data → Consolidate
    case fillSeries                // Home → Fill → Series
    case scenarioManager           // Data → What-If Analysis → Scenario Manager
    case chartTitles(Int)          // Chart Design → Edit Titles
    case dataTable                 // Data → What-If Analysis → Data Table
    case chartSeries(Int)          // Chart Design → Select Data
    case chartColors(Int)          // Chart Design → Format Data Series
    case chartAxis(Int)            // Chart Design → Axis Options
    case chartLabels(Int)          // Chart Design → Add Chart Element → Data Labels
    case chartForm(ChartFormKind)  // Insert → Charts: Stock or Bubble, asking for the data the chart lacks
    case sparklineDialog(SparklineGroup.Kind?)   // Insert → Sparklines: make them, or (nil) change the ones under the active cell
    case goalSeek                  // Data → What-If Analysis → Goal Seek
    case removeDuplicates          // Data → Remove Duplicates
    case textToColumns             // Data → Text to Columns
    case subtotal                  // Data → Subtotal
    case sortDialog                // Data → Sort…
    case insertPivotTable          // Insert → PivotTable
    case tableDialog               // Insert → Table: create one, or the options of the table at the cell
    case columnFilter(col: Int, kind: String)   // a filter dropdown's Number/Text/Date/Colour Filters…
    case nameManager               // Formulas → Name Manager
    case createNames               // Formulas → Create from Selection
    case useName(String)           // Formulas → Use in Formula: the name into the formula being typed
    case protectSheetDialog        // Review → Protect Sheet / Unprotect Sheet
    case protectWorkbookDialog     // Review → Protect Workbook / Unprotect Workbook
    case pageSetup                 // Layout → Page Setup: the dialog
    case insertPicture             // Insert → Pictures: choose an image file and place it
    case altText                   // Insert → Alt Text: the selected picture's description
    case editNote                  // Review → New/Edit Note: the editor beside the active cell
}

extension Ribbon {
    func sheetsGroups(_ fluent: FluentThemeData) -> [Widget]? {
        guard let wb = session.workbook else { return nil }
        switch tab {
        case .home: return _sheetsHome(wb, fluent)
        case .insert: return [_tablesGroup(wb, fluent), _illustrationsGroup(wb, fluent), _chartsGroup(wb, fluent), _sparklinesGroup(wb, fluent), _functionsGroup(wb, fluent), _symbolsGroup(wb, fluent)]
        case .formulas: return [_autoSumGroup(wb, fluent), _functionsGroup(wb, fluent), _namesGroup(wb, fluent)]
        case .data: return [_sortGroup(wb, fluent), _dataToolsGroup(wb, fluent), _outlineGroup(wb, fluent)]
        case .layout: return [_pageSetupGroup(wb, fluent), _scaleToFitGroup(wb, fluent), _sheetOptionsGroup(wb, fluent)]
        case .view: return [_sheetsZoomGroup(wb, fluent)]
        case .review: return [_notesGroup(wb, fluent), _protectGroup(wb, fluent)]
        default: return nil
        }
    }

    private func _sheetsHome(_ wb: WorkbookController, _ fluent: FluentThemeData) -> [Widget] {
        let st = wb.style(at: wb.active)
        let sizes: [Double] = [8, 9, 10, 11, 12, 14, 16, 18, 20, 24, 28, 36, 48, 72]
        let family = wb.book.fontName(st)
        let size = wb.book.fontSize(st)
        let clipboard = Chrome.group("Clipboard", fluent, [
            Chrome.big(FluentSystemIcons.paste, "Paste", fluent) { wb.onCommand?(.paste) },
            Chrome.rows([
                Chrome.small(FluentSystemIcons.cut, "Cut", fluent) { wb.onCommand?(.cut) },
                Chrome.small(FluentSystemIcons.copy, "Copy", fluent) { wb.onCommand?(.copy) },
                Chrome.small(FluentSystemIcons.paste, "Paste Special", fluent) { wb.onCommand?(.pasteSpecial) },
                Chrome.small(FluentSystemIcons.paste, wb.painterSource == nil ? "Format Painter" : "Painter: pick cells", fluent) { wb.onCommand?(.formatPainter) },
            ]),
        ])
        let colors: [(String, Color)] = [
            ("Black", Color(0xFF000000)), ("White", Color(0xFFFFFFFF)), ("Dark Gray", Color(0xFF595959)),
            ("Light Gray", Color(0xFFD9D9D9)), ("Dark Red", Color(0xFFC00000)), ("Red", Color(0xFFFF0000)),
            ("Orange", Color(0xFFFFC000)), ("Yellow", Color(0xFFFFFF00)), ("Light Green", Color(0xFF92D050)),
            ("Green", Color(0xFF00B050)), ("Light Blue", Color(0xFF00B0F0)), ("Blue", Color(0xFF0070C0)),
            ("Dark Blue", Color(0xFF002060)), ("Purple", Color(0xFF7030A0)),
        ]
        func rgb(_ c: Color?) -> UInt32? { c.map { UInt32(truncatingIfNeeded: $0.value) & 0xFFFFFF } }
        let font = Chrome.group("Font", fluent, [Chrome.rows([
            Chrome.row([
                SizedBox(width: 140, height: nil, child: ComboBox<String>(
                    value: family,
                    items: OfficeFonts.families(including: family).map { f in
                        ComboBoxItem<String>(value: f, child: Text(f, style: fluent.typography.body?.copyWith(color: nil)))
                    },
                    onChanged: { f in if let f { wb.setStyle { $0.fontName = f } } }, semanticLabel: "Font")),
                Chrome.gap(),
                SizedBox(width: 64, height: nil, child: ComboBox<Double>(
                    value: sizes.contains(size) ? size : nil,
                    items: sizes.map { n in ComboBoxItem<Double>(value: n, child: Text(n == n.rounded() ? "\(Int(n))" : "\(n)")) },
                    onChanged: { n in if let n { wb.setStyle { $0.fontSize = n } } },
                    placeholder: Text("\(Int(size))"), semanticLabel: "Font Size")),
            ]),
            Chrome.vgap(4),
            Chrome.row([
                Chrome.toggle(FluentSystemIcons.textBold, "Bold (⌘B)".keys, st.bold, fluent) { wb.toggleStyle(\.bold) },
                Chrome.toggle(FluentSystemIcons.textItalic, "Italic (⌘I)".keys, st.italic, fluent) { wb.toggleStyle(\.italic) },
                Chrome.toggle(FluentSystemIcons.textUnderline, "Underline (⌘U)".keys, st.underline, fluent) { wb.toggleStyle(\.underline) },
                Chrome.toggle(FluentSystemIcons.textStrikethrough, "Strikethrough", st.strike, fluent) { wb.toggleStyle(\.strike) },
                Chrome.gap(4),
                Chrome.menu(nil, Icon(FluentSystemIcons.grid, size: Chrome.iconSize, color: fluent.resources.textFillColorPrimary), fluent, [
                    ("All Borders", { wb.setStyle { $0.borders = .init(top: true, left: true, bottom: true, right: true) } }),
                    ("Bottom Border", { wb.setStyle { $0.borders.bottom = true } }),
                    ("Top Border", { wb.setStyle { $0.borders.top = true } }),
                    ("No Border", { wb.setStyle { $0.borders = .init() } }),
                ], tip: "Borders"),
                Chrome.colorMenu(FluentSystemIcons.paintBrush, "Fill Color", fluent, colors: colors, none: "No Fill") { c in
                    wb.setStyle { $0.fill = rgb(c) }
                },
                Chrome.colorMenu(FluentSystemIcons.textColor, "Font Color", fluent, colors: colors, none: "Automatic") { c in
                    wb.setStyle { $0.color = rgb(c) }
                },
            ]),
        ])])
        let alignment = Chrome.group("Alignment", fluent, [Chrome.rows([
            Chrome.row([
                Chrome.toggle(FluentSystemIcons.alignLeft, "Align Left", st.hAlign == .left, fluent) {
                    wb.toggleAlign(.left)
                },
                Chrome.toggle(FluentSystemIcons.alignCenter, "Center", st.hAlign == .center, fluent) {
                    wb.toggleAlign(.center)
                },
                Chrome.toggle(FluentSystemIcons.alignRight, "Align Right", st.hAlign == .right, fluent) {
                    wb.toggleAlign(.right)
                },
            ]),
            Chrome.vgap(4),
            Chrome.row([
                Chrome.textToggle("Wrap Text", st.wrap, fluent, style: fluent.typography.caption) { wb.toggleStyle(\.wrap) },
                Chrome.textToggle("Merge & Center", wb.sheet.merges.contains(wb.selection), fluent, style: fluent.typography.caption) { wb.toggleMerge() },
                Chrome.menu(Text("Vertical", style: fluent.typography.caption), nil, fluent, [
                    ("Top", { wb.setStyle { $0.vAlign = .top } }),
                    ("Middle", { wb.setStyle { $0.vAlign = .center } }),
                    ("Bottom", { wb.setStyle { $0.vAlign = .bottom } }),
                ]),
            ]),
        ])])
        let formats: [(String, String)] = [
            ("General", "General"), ("Number", "0.00"), ("Currency", "$#,##0.00"),
            ("Accounting", "_($* #,##0.00_);_($* (#,##0.00);_($* \"-\"??_);_(@_)"),
            ("Short Date", "m/d/yyyy"), ("Long Date", "dddd, mmmm d, yyyy"), ("Time", "h:mm:ss AM/PM"),
            ("Percentage", "0.00%"), ("Scientific", "0.00E+00"), ("Text", "@"),
        ]
        let currentName = formats.first { $0.1 == st.numberFormat }?.0 ?? "Custom"
        let number = Chrome.group("Number", fluent, [Chrome.rows([
            Chrome.row([
                Chrome.menu(Text(currentName, style: fluent.typography.body), nil, fluent,
                            formats.map { name, code in (name, { wb.setStyle { $0.numberFormat = code } }) }),
            ]),
            Chrome.vgap(4),
            Chrome.row([
                FlatButton(child: Text("$", style: fluent.typography.bodyStrong), tip: "Currency") { wb.setStyle { $0.numberFormat = "$#,##0.00" } },
                FlatButton(child: Text("%", style: fluent.typography.bodyStrong), tip: "Percent Style") { wb.setStyle { $0.numberFormat = "0%" } },
                FlatButton(child: Text(",", style: fluent.typography.bodyStrong), tip: "Comma Style") { wb.setStyle { $0.numberFormat = "#,##0.00" } },
                FlatButton(child: Text(".0+", style: fluent.typography.caption), tip: "Increase Decimal") {
                    wb.setStyle { $0.numberFormat = Self._decimals($0.numberFormat, wb, +1) }
                },
                FlatButton(child: Text(".0−", style: fluent.typography.caption), tip: "Decrease Decimal") {
                    wb.setStyle { $0.numberFormat = Self._decimals($0.numberFormat, wb, -1) }
                },
            ]),
        ])])
        let cells = Chrome.group("Cells", fluent, [Chrome.rows([
            Chrome.menuButton(FluentSystemIcons.add, "Insert", "Insert cells", fluent, items: [
                MenuFlyoutItem(text: Text("Insert Cells…"), onPressed: { wb.onCommand?(.cellsDialog(insert: true)) }),
                MenuFlyoutItem(text: Text("Insert Sheet Rows"), onPressed: { wb.insertAtSelection(.rows) }),
                MenuFlyoutItem(text: Text("Insert Sheet Columns"), onPressed: { wb.insertAtSelection(.cols) }),
                MenuFlyoutItem(text: Text("Insert Sheet"), onPressed: { wb.addSheet() }),
            ]),
            Chrome.menuButton(FluentSystemIcons.delete, "Delete", "Delete cells", fluent, items: [
                MenuFlyoutItem(text: Text("Delete Cells…"), onPressed: { wb.onCommand?(.cellsDialog(insert: false)) }),
                MenuFlyoutItem(text: Text("Delete Sheet Rows"), onPressed: { wb.deleteAtSelection(.rows) }),
                MenuFlyoutItem(text: Text("Delete Sheet Columns"), onPressed: { wb.deleteAtSelection(.cols) }),
                MenuFlyoutItem(text: Text("Delete Sheet"), onPressed: wb.book.sheets.count > 1 ? { wb.requestDeleteSheet(wb.activeSheet) } : nil),
            ]),
            Chrome.menuButton(FluentSystemIcons.ruler, "Format", "Format cells size", fluent, items: [
                MenuFlyoutItem(text: Text("Row Height…"), onPressed: { wb.onCommand?(.sizeDialog(.rowHeight)) }),
                MenuFlyoutItem(text: Text("Column Width…"), onPressed: { wb.onCommand?(.sizeDialog(.columnWidth)) }),
                MenuFlyoutItem(text: Text("Default Width…"), onPressed: { wb.onCommand?(.sizeDialog(.defaultWidth)) }),
            ]),
        ])])
        let styles = Chrome.group("Styles", fluent, [
            Chrome.menuButton(FluentSystemIcons.paintBrush, "Conditional Formatting", "Conditional formatting", fluent, items: [
                MenuFlyoutItem(text: Text("New Rule…"), onPressed: { wb.onCommand?(.conditionalFormat) }),
                MenuFlyoutItem(text: Text("Manage Rules…"), onPressed: { wb.onCommand?(.conditionalRules) }),
            ]),
        ])
        let editing = Chrome.group("Editing", fluent, [Chrome.rows([
            Chrome.small(FluentSystemIcons.mathFormula, "AutoSum", fluent) { Self._autoSum(wb) },
            Chrome.menu(Text("Fill", style: fluent.typography.caption), Icon(FluentSystemIcons.grid, size: Chrome.iconSize,
                        color: fluent.resources.textFillColorPrimary), fluent, [
                ("Down (⌘D)".keys, { wb.fillDown() }),
                ("Right (⌘R)".keys, { wb.fillRight() }),
                ("Up", { wb.fillUp() }),
                ("Left", { wb.fillLeft() }),
                ("Series…", { wb.onCommand?(.fillSeries) }),
            ]),
            Chrome.menu(Text("Clear", style: fluent.typography.caption), Icon(FluentSystemIcons.textClearFormatting, size: Chrome.iconSize,
                        color: fluent.resources.textFillColorPrimary), fluent, [
                ("Clear All", { wb.clearAll() }),
                ("Clear Formats", { wb.setStyle { $0 = .plain } }),
                ("Clear Contents", { wb.clearContents() }),
                ("Clear Comments", { wb.clearComments() }),
                ("Clear Hyperlinks", { wb.removeLink(wb.selection) }),
            ], keyPrefix: "sheets.clear"),
        ]), Chrome.rows([
            Chrome.small(FluentSystemIcons.search, "Find", fluent) { [session] in session.onFind?(false) },
            Chrome.small(FluentSystemIcons.textGrammarWand, "Replace", fluent) { [session] in session.onFind?(true) },
        ])])
        return [clipboard, font, alignment, number, styles, cells, editing]
    }

    /// One more or one fewer decimal place in a format (General becomes
    /// 0.0 from the active cell's value, as Excel's buttons do).
    static func _decimals(_ code: String, _ wb: WorkbookController, _ step: Int) -> String {
        var c = code
        if c == "General" {
            var places = 0
            if case .number(let n) = wb.sheet.value(wb.active) {
                let s = NumberFormat.general(n)
                places = s.split(separator: ".").count > 1 ? s.split(separator: ".")[1].count : 0
            }
            c = places == 0 ? "0" : "0." + String(repeating: "0", count: places)
        }
        // Change the zeros after the first decimal point of each section.
        let sections = NumberFormat._sections(c).map { s -> String in
            guard let dot = s.firstIndex(of: ".") else {
                guard step > 0, let lastZero = s.lastIndex(where: { $0 == "0" || $0 == "#" }) else { return s }
                var t = s; t.insert(contentsOf: ".0", at: t.index(after: lastZero)); return t
            }
            var end = s.index(after: dot)
            while end < s.endIndex, s[end] == "0" || s[end] == "#" { end = s.index(after: end) }
            let count = s.distance(from: s.index(after: dot), to: end)
            let n = max(0, count + step)
            return String(s[..<dot]) + (n == 0 ? "" : "." + String(repeating: "0", count: n)) + String(s[end...])
        }
        return sections.joined(separator: ";")
    }

    /// AutoSum: =SUM over the numbers above the active cell (or left of
    /// it). The total takes the summed cells' number format, as Excel's does,
    /// when they agree on one and the cell has none of its own.
    static func _autoSum(_ wb: WorkbookController) {
        let a = wb.active
        func isNum(_ x: CellAddress) -> Bool { wb.sheet.value(x).number != nil }
        func start(_ r: CellRange) {
            let addresses = (r.top ... r.bottom).flatMap { row in (r.left ... r.right).map { CellAddress(row: row, col: $0) } }
            let formats = Set(addresses.map { wb.book.style(wb.sheet.cells[$0]?.style ?? 0).numberFormat })
            if formats.count == 1, let f = formats.first, f != "General",
               wb.book.style(wb.sheet.cells[a]?.style ?? 0).numberFormat == "General" {
                wb.setStyle({ $0.numberFormat = f }, range: CellRange(a))
            }
            wb.onCommand?(.startFormula("=SUM(" + r.a1 + ")"))
        }
        var top = a.row
        while top > 0, isNum(CellAddress(row: top - 1, col: a.col)) { top -= 1 }
        if top < a.row {
            start(CellRange(top: top, left: a.col, bottom: a.row - 1, right: a.col))
            return
        }
        var left = a.col
        while left > 0, isNum(CellAddress(row: a.row, col: left - 1)) { left -= 1 }
        if left < a.col {
            start(CellRange(top: a.row, left: left, bottom: a.row, right: a.col - 1))
            return
        }
        wb.onCommand?(.startFormula("=SUM("))
    }

    private func _namesGroup(_ wb: WorkbookController, _ fluent: FluentThemeData) -> Widget {
        Chrome.group("Defined Names", fluent, [
            Chrome.big(FluentSystemIcons.rename, "Name Manager", fluent) { wb.onCommand?(.nameManager) },
            Chrome.big(FluentSystemIcons.rename, "Create from Selection", fluent) { wb.onCommand?(.createNames) },
            Chrome.menu(Text("Use in Formula", style: fluent.typography.caption), nil, fluent,
                        wb.definedNameEntries().filter { $0.scopeSheet == nil || $0.scopeSheet == wb.activeSheet }
                            .map { e in (e.name, { wb.onCommand?(.useName(e.name)) }) }
                        + [("Name Manager…", { wb.onCommand?(.nameManager) })]),
        ])
    }

    private func _autoSumGroup(_ wb: WorkbookController, _ fluent: FluentThemeData) -> Widget {
        Chrome.group("Function Library", fluent, [
            Chrome.big(FluentSystemIcons.mathFormula, "AutoSum", fluent) { Self._autoSum(wb) },
        ])
    }

    private func _functionsGroup(_ wb: WorkbookController, _ fluent: FluentThemeData) -> Widget {
        let groups: [(String, [String])] = [
            ("Math", ["SUM", "AVERAGE", "MIN", "MAX", "COUNT", "ROUND", "SUMIF", "SUMIFS", "SUMPRODUCT", "MOD", "ABS"]),
            ("Logical", ["IF", "IFS", "IFERROR", "AND", "OR", "NOT"]),
            ("Lookup", ["VLOOKUP", "XLOOKUP", "INDEX", "MATCH", "HLOOKUP"]),
            ("Text", ["CONCAT", "TEXTJOIN", "LEFT", "RIGHT", "MID", "LEN", "TRIM", "UPPER", "LOWER", "TEXT", "SUBSTITUTE"]),
            ("Date & Time", ["TODAY", "NOW", "DATE", "YEAR", "MONTH", "DAY", "EDATE", "EOMONTH", "NETWORKDAYS"]),
            ("Financial", ["PMT", "FV", "PV", "NPV"]),
        ]
        return Chrome.group("Functions", fluent, [Chrome.rows([
            Chrome.row(groups.prefix(3).map { name, fns in
                Chrome.menu(Text(name, style: fluent.typography.caption), nil, fluent,
                            fns.map { f in (f, { wb.onCommand?(.startFormula("=" + f + "(")) }) })
            }),
            Chrome.vgap(4),
            Chrome.row(groups.dropFirst(3).map { name, fns in
                Chrome.menu(Text(name, style: fluent.typography.caption), nil, fluent,
                            fns.map { f in (f, { wb.onCommand?(.startFormula("=" + f + "(")) }) })
            }),
        ])])
    }

    /// Insert → Symbols.
    private func _symbolsGroup(_ wb: WorkbookController, _ fluent: FluentThemeData) -> Widget {
        Chrome.group("Symbols", fluent, [
            Chrome.big(FluentSystemIcons.add, "Symbol", fluent) { wb.onCommand?(.symbol) },
        ])
    }

    /// Insert → Charts: a chart of the selection; with a chart selected,
    /// that chart becomes the kind clicked (as Excel's buttons do).
    private func _chartsGroup(_ wb: WorkbookController, _ fluent: FluentThemeData) -> Widget {
        func button(_ t: ChartType) -> Widget {
            Chrome.small(t.icon, t.name, fluent) {
                if let i = wb.selectedDrawing, wb.sheet.drawings.indices.contains(i), wb.sheet.drawings[i].isChart {
                    wb.setChartType(i, t)
                } else {
                    wb.insertChart(t)
                }
            }
        }
        func form(_ icon: IconData, _ name: String, _ kind: ChartFormKind?) -> Widget {
            Chrome.small(icon, name, fluent) {
                if wb.selectedDrawing == nil || !(wb.selectedDrawing.map { wb.sheet.drawings.indices.contains($0) && wb.sheet.drawings[$0].isChart } ?? false) {
                    wb.insertChart(kind == nil ? .column : .line)
                }
                guard let i = wb.selectedDrawing else { return }
                if let kind { wb.onCommand?(.chartForm(kind)) } else { wb.setChartVariant(i, .threeD) }
            }
        }
        var parts: [Widget] = [
            Chrome.rows([button(.column), button(.bar), button(.line)]),
            Chrome.rows([button(.pie), button(.area), button(.scatter)]),
            Chrome.rows([form(ChartType.column.icon, "3-D", nil), form(ChartType.line.icon, "Stock", .stock(ohlc: false)),
                         form(ChartType.scatter.icon, "Bubble", .bubble)]),
            Chrome.rows([form(ChartType.line.icon, "Open-High-Low-Close", .stock(ohlc: true))]),
        ]
        // Chart Design, with a chart selected: its title and legend.
        if let i = wb.selectedDrawing, wb.sheet.drawings.indices.contains(i), case .chart(let sc) = wb.sheet.drawings[i].kind {
            let c = sc.chart
            parts.append(Chrome.rows([
                Chrome.textToggle("Chart Title", c.title != nil, fluent, style: fluent.typography.caption) {
                    wb.setChartTitle(i, c.title == nil ? "Chart Title" : nil)
                },
                Chrome.textToggle("Select Data", false, fluent, style: fluent.typography.caption) { wb.onCommand?(.chartSeries(i)) },
                Chrome.textToggle("Series Colours", false, fluent, style: fluent.typography.caption) { wb.onCommand?(.chartColors(i)) },
                Chrome.textToggle("Axis Options", c.valueMin != nil || c.valueMax != nil || c.valueStep != nil || c.valueFormat != nil, fluent, style: fluent.typography.caption) { wb.onCommand?(.chartAxis(i)) },
                Chrome.textToggle("Data Labels", c.dataLabels || c.pieLabels != nil, fluent, style: fluent.typography.caption) { wb.onCommand?(.chartLabels(i)) },
                Chrome.textToggle("Edit Titles", false, fluent, style: fluent.typography.caption) { wb.onCommand?(.chartTitles(i)) },
                Chrome.textToggle("Axis Titles", c.categoryAxisTitle != nil || c.valueAxisTitle != nil, fluent, style: fluent.typography.caption) {
                    let on = c.categoryAxisTitle != nil || c.valueAxisTitle != nil
                    wb.setChartAxisTitles(i, category: on ? nil : "Axis Title", value: on ? nil : "Axis Title")
                },
                Chrome.textToggle("Legend", c.legend, fluent, style: fluent.typography.caption) {
                    wb.setChartLegend(i, position: c.legend ? nil : (c.legendPosition.isEmpty ? "b" : c.legendPosition))
                },
            ]))
            parts.append(Chrome.rows(["b": "Legend Bottom", "r": "Legend Right", "t": "Legend Top"].sorted { $0.value < $1.value }.map { side in
                Chrome.textToggle(side.value, c.legend && c.legendPosition == side.key, fluent, style: fluent.typography.caption) {
                    wb.setChartLegend(i, position: side.key)
                }
            }))
        }
        return Chrome.group("Charts", fluent, parts)
    }

    /// Insert → Pictures; Alt Text once a picture is selected.
    private func _illustrationsGroup(_ wb: WorkbookController, _ fluent: FluentThemeData) -> Widget {
        var items: [Widget] = [Chrome.big(FluentSystemIcons.image, "Pictures", fluent) { wb.onCommand?(.insertPicture) }]
        if let i = wb.selectedDrawing, wb.sheet.drawings.indices.contains(i), wb.sheet.drawings[i].kind != .other {
            items.append(Chrome.big(FluentSystemIcons.image, "Alt Text", fluent) { wb.onCommand?(.altText) })
        }
        if wb.selectedDrawing != nil {
            // A finger has no Shift: while this is on, a tap on another chart or picture picks it along with this one.
            items.append(Chrome.small(FluentSystemIcons.check, "Select Multiple", fluent, checked: wb.selectMultiple) {
                wb.selectMultiple.toggle()
                wb._notify(selectionOnly: true)
            })
        }
        return Chrome.group("Illustrations", fluent, items)
    }

    private func _sparklinesGroup(_ wb: WorkbookController, _ fluent: FluentThemeData) -> Widget {
        var items: [Widget] = [
            Chrome.big(ChartType.line.icon, "Line", fluent) { wb.onCommand?(.sparklineDialog(.line)) },
            Chrome.big(ChartType.column.icon, "Column", fluent) { wb.onCommand?(.sparklineDialog(.column)) },
            Chrome.big(ChartType.bar.icon, "Win/Loss", fluent) { wb.onCommand?(.sparklineDialog(.winLoss)) },
        ]
        if wb.sparklineAt(wb.active) != nil { items.append(Chrome.big(ChartType.line.icon, "Edit Sparklines", fluent) { wb.onCommand?(.sparklineDialog(nil)) }) }
        return Chrome.group("Sparklines", fluent, items)
    }

    private func _tablesGroup(_ wb: WorkbookController, _ fluent: FluentThemeData) -> Widget {
        Chrome.group("Tables", fluent, [
            Chrome.big(FluentSystemIcons.grid, "PivotTable", fluent) { wb.onCommand?(.insertPivotTable) },
            Chrome.big(FluentSystemIcons.grid, "Table", fluent) { wb.onCommand?(.tableDialog) },
        ])
    }

    private func _protectGroup(_ wb: WorkbookController, _ fluent: FluentThemeData) -> Widget {
        Chrome.group("Protect", fluent, [
            Chrome.big(FluentSystemIcons.lock, wb.protection() != nil ? "Unprotect Sheet" : "Protect Sheet", fluent) { wb.onCommand?(.protectSheetDialog) },
            Chrome.big(FluentSystemIcons.lock, wb.book.structureLocked ? "Unprotect Workbook" : "Protect Workbook", fluent) { wb.onCommand?(.protectWorkbookDialog) },
        ])
    }

    private func _notesGroup(_ wb: WorkbookController, _ fluent: FluentThemeData) -> Widget {
        let has = wb.note(at: wb.active) != nil
        return Chrome.group("Notes", fluent, [
            Chrome.big(FluentSystemIcons.comment, has ? "Edit Note" : "New Note", fluent) { wb.onCommand?(.editNote) },
            Chrome.rows([
                Chrome.small(FluentSystemIcons.delete, "Delete", fluent) { wb.deleteNote(at: wb.active) },
                Chrome.small(FluentSystemIcons.chevronUp, "Previous", fluent) { wb.goToNote(-1) },
                Chrome.small(FluentSystemIcons.chevronDown, "Next", fluent) { wb.goToNote(1) },
            ]),
        ])
    }

    private func _sortGroup(_ wb: WorkbookController, _ fluent: FluentThemeData) -> Widget {
        Chrome.group("Sort & Filter", fluent, [Chrome.rows([
            Chrome.small(FluentSystemIcons.sort, "Sort A to Z", fluent) { wb.sortSelection(ascending: true) },
            Chrome.small(FluentSystemIcons.sort, "Sort Z to A", fluent) { wb.sortSelection(ascending: false) },
            Chrome.small(FluentSystemIcons.sort, "Sort…", fluent) { wb.onCommand?(.sortDialog) },
        ]), Chrome.bigToggle(FluentSystemIcons.grid, "Filter", wb.sheet.autoFilter != nil, fluent) { wb.toggleAutoFilter() },
        Chrome.rows([
            Chrome.small(FluentSystemIcons.close, "Clear", fluent) { wb.clearFilters() },
            Chrome.small(FluentSystemIcons.refresh, "Reapply", fluent) { wb.structural { wb.reapplyFilter() } },
        ])])
    }

    private func _dataToolsGroup(_ wb: WorkbookController, _ fluent: FluentThemeData) -> Widget {
        Chrome.group("Data Tools", fluent, [
            Chrome.big(FluentSystemIcons.check, "Data Validation", fluent) { wb.onCommand?(.dataValidation) },
            Chrome.big(FluentSystemIcons.delete, "Remove Duplicates", fluent) { wb.onCommand?(.removeDuplicates) },
            Chrome.big(FluentSystemIcons.columns, "Text to Columns", fluent) { wb.onCommand?(.textToColumns) },
            Chrome.big(FluentSystemIcons.numberList, "Subtotal", fluent) { wb.onCommand?(.subtotal) },
            Chrome.big(FluentSystemIcons.numberList, "Consolidate", fluent) { wb.onCommand?(.consolidate) },
            Chrome.big(FluentSystemIcons.numberList, "Scenario Manager", fluent) { wb.onCommand?(.scenarioManager) },
            Chrome.big(FluentSystemIcons.grid, "Refresh PivotTables", fluent) {
                let n = wb.refreshPivots()
                wb.onCommand?(.status(n == 0 ? "No PivotTables here Excel did not make in a way this app can refresh (Excel refreshes the others)" : "\(n) PivotTable\(n == 1 ? "" : "s") refreshed"))
            },
            Chrome.rows([
                Chrome.small(FluentSystemIcons.check, "Circle Invalid Data", fluent) {
                    let n = wb.circleInvalidData()
                    wb.onCommand?(.status(n == 0 ? "No invalid data found" : "\(n) invalid cell\(n == 1 ? "" : "s") circled"))
                },
                Chrome.small(FluentSystemIcons.close, "Clear Validation Circles", fluent) { wb.clearValidationCircles() },
            ]),
            Chrome.big(FluentSystemIcons.check, "Goal Seek", fluent) { wb.onCommand?(.goalSeek) },
            Chrome.big(FluentSystemIcons.table, "Data Table", fluent) { wb.onCommand?(.dataTable) },
        ])
    }

    private func _outlineGroup(_ wb: WorkbookController, _ fluent: FluentThemeData) -> Widget {
        Chrome.group("Outline", fluent, [Chrome.rows([
            Chrome.small(FluentSystemIcons.indentIncrease, "Group", fluent) { wb.group(true) },
            Chrome.small(FluentSystemIcons.indentDecrease, "Ungroup", fluent) { wb.group(false) },
        ])])
    }

    private func _pageSetupGroup(_ wb: WorkbookController, _ fluent: FluentThemeData) -> Widget {
        let setup = SheetPrintSetup.read(wb.sheet)
        let landscape = setup.landscape
        // Excel's three margin presets, in inches: top/bottom, left/right, header/footer.
        func margins(_ name: String, _ tb: Double, _ lr: Double, _ hf: Double) -> MenuFlyoutItem {
            MenuFlyoutItem(text: Text(name), onPressed: {
                wb.setPageSetup(PageSetupChange(left: lr, right: lr, top: tb, bottom: tb, header: hf, footer: hf))
            })
        }
        let paper = wb.paperNumber
        let sizes: [MenuFlyoutItemBase] = PageSetupForm.papers.map { n, name in
            MenuFlyoutItem(text: Text(n == paper ? "\u{2713} " + name : name), onPressed: { wb.setPageSetup(PageSetupChange(paperSize: n)) })
        } + [MenuFlyoutItem(text: Text("More Paper Sizes…"), onPressed: { wb.onCommand?(.pageSetup) })]
        let hasArea = !SheetPrintLayout.printNames(wb.book, sheet: wb.activeSheet).areas.isEmpty
        return Chrome.group("Page Setup", fluent, [
            Chrome.menuButton(FluentSystemIcons.grid, "Margins", "Page margins", fluent, items: [
                margins("Normal", 0.75, 0.7, 0.3), margins("Wide", 1, 1, 0.5), margins("Narrow", 0.75, 0.25, 0.3),
                MenuFlyoutItem(text: Text("Custom Margins…"), onPressed: { wb.onCommand?(.pageSetup) }),
            ]),
            Chrome.menuButton(FluentSystemIcons.grid, "Orientation", landscape ? "Landscape" : "Portrait", fluent, items: [
                MenuFlyoutItem(text: Text("Portrait"), onPressed: { wb.setPageSetup(PageSetupChange(landscape: false)) }),
                MenuFlyoutItem(text: Text("Landscape"), onPressed: { wb.setPageSetup(PageSetupChange(landscape: true)) }),
            ]),
            Chrome.menuButton(FluentSystemIcons.grid, "Size", "Paper size", fluent, items: sizes),
            Chrome.menuButton(FluentSystemIcons.grid, "Print Area", "What part of the sheet prints", fluent, items: [
                MenuFlyoutItem(text: Text("Set Print Area"), onPressed: { wb.setPrintArea(wb.selection) }),
            ] + (hasArea ? [MenuFlyoutItem(text: Text("Clear Print Area"), onPressed: { wb.setPrintArea(nil) })] : [])),
            Chrome.menuButton(FluentSystemIcons.grid, "Breaks", "Page breaks", fluent, items: [
                MenuFlyoutItem(text: Text("Insert Page Break"), onPressed: { wb.insertPageBreak(row: wb.active.row, col: wb.active.col) }),
                MenuFlyoutItem(text: Text("Remove Page Break"), onPressed: { wb.removePageBreak(row: wb.active.row, col: wb.active.col) }),
                MenuFlyoutItem(text: Text("Reset All Page Breaks"), onPressed: { wb.resetPageBreaks() }),
            ]),
            Chrome.big(FluentSystemIcons.grid, "Print Titles", fluent) { wb.onCommand?(.pageSetup) },
            Chrome.big(FluentSystemIcons.grid, "Page Setup", fluent) { wb.onCommand?(.pageSetup) },
        ])
    }

    /// Scale to Fit: pages wide, pages tall (Automatic = as many as it takes) and the
    /// scale, which applies only while both are Automatic, as in Excel.
    private func _scaleToFitGroup(_ wb: WorkbookController, _ fluent: FluentThemeData) -> Widget {
        let setup = SheetPrintSetup.read(wb.sheet)
        let fitting = setup.fitWidth != nil || setup.fitHeight != nil
        let wide = fitting ? setup.fitWidth ?? 1 : 0, tall = fitting ? setup.fitHeight ?? 1 : 0
        func pages(_ n: Int) -> String { n == 0 ? "Automatic" : n == 1 ? "1 page" : "\(n) pages" }
        func items(_ width: Bool) -> [MenuFlyoutItemBase] {
            (0...9).map { n in
                MenuFlyoutItem(text: Text(pages(n)), onPressed: {
                    wb.setPageSetup(SheetPrintLayout.fitChange(wide: width ? n : wide, tall: width ? tall : n,
                                                               scale: Int(setup.scale.rounded())))
                })
            } + [MenuFlyoutItem(text: Text("More Pages…"), onPressed: { wb.onCommand?(.pageSetup) })]
        }
        return Chrome.group("Scale to Fit", fluent, [Chrome.rows([
            Chrome.menuButton(nil, "Width: " + pages(wide), "Pages wide", fluent, items: items(true)),
            Chrome.menuButton(nil, "Height: " + pages(tall), "Pages tall", fluent, items: items(false)),
            Chrome.spinner("Scale", setup.scale, fluent, step: 5, unit: "%", minimum: 10) { v in
                // Excel greys the scale while a fit is set.
                if !fitting { wb.setPageSetup(PageSetupChange(scale: Int(min(400, v).rounded()))) }
            },
        ])])
    }

    /// Sheet Options: gridlines and headings, on screen (View) and on paper (Print).
    private func _sheetOptionsGroup(_ wb: WorkbookController, _ fluent: FluentThemeData) -> Widget {
        let setup = SheetPrintSetup.read(wb.sheet)
        let cap = fluent.typography.caption
        return Chrome.group("Sheet Options", fluent, [Chrome.rows([
            Chrome.textToggle("View Gridlines", wb.sheet.showGridlines, fluent, style: cap) { wb.toggleGridlines() },
            Chrome.textToggle("Print Gridlines", setup.gridlines, fluent, style: cap) {
                wb.setPageSetup(PageSetupChange(gridlines: !setup.gridlines))
            },
        ]), Chrome.rows([
            Chrome.textToggle("View Headings", wb.sheet.showHeadings, fluent, style: cap) { wb.toggleHeadings() },
            Chrome.textToggle("Print Headings", setup.headings, fluent, style: cap) {
                wb.setPageSetup(PageSetupChange(headings: !setup.headings))
            },
        ])])
    }

    private func _sheetsZoomGroup(_ wb: WorkbookController, _ fluent: FluentThemeData) -> Widget {
        let frozen = wb.sheet.freezeRows > 0 || wb.sheet.freezeCols > 0
        return Chrome.group("Window", fluent, [
            Chrome.menuButton(FluentSystemIcons.grid, "Freeze Panes", "Keep rows and columns in view", fluent, items: [
                MenuFlyoutItem(text: Text(frozen ? "Unfreeze Panes" : "Freeze Panes"), onPressed: {
                    wb.freeze(at: frozen ? CellAddress(row: 0, col: 0) : wb.active)
                }),
                MenuFlyoutItem(text: Text("Freeze Top Row"), onPressed: { wb.freeze(at: CellAddress(row: 1, col: 0)) }),
                MenuFlyoutItem(text: Text("Freeze First Column"), onPressed: { wb.freeze(at: CellAddress(row: 0, col: 1)) }),
            ]),
            Chrome.textToggle("Gridlines", wb.sheet.showGridlines, fluent, style: fluent.typography.caption) {
                wb.toggleGridlines()
            },
            Chrome.textToggle("Headings", wb.sheet.showHeadings, fluent, style: fluent.typography.caption) { wb.toggleHeadings() },
            Chrome.textToggle("Show Formulas", wb.sheet.showFormulas, fluent, style: fluent.typography.caption) { wb.toggleShowFormulas() },
            Chrome.textToggle("Sheet Right-to-Left", wb.sheet.rightToLeft, fluent, style: fluent.typography.caption) { wb.toggleRightToLeft() },
            Chrome.textToggle("Page Break Preview", wb.breakPreview, fluent, style: fluent.typography.caption) {
                wb.breakPreview.toggle(); wb._notify()
            },
            Chrome.big(FluentSystemIcons.zoomIn, "Zoom In", fluent) { wb.onCommand?(.zoom(1.1)) },
            Chrome.big(FluentSystemIcons.zoomOut, "Zoom Out", fluent) { wb.onCommand?(.zoom(1 / 1.1)) },
            Chrome.big(FluentSystemIcons.grid, "100%", fluent) { wb.onCommand?(.zoom(0)) },
        ])
    }
}
