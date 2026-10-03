// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The ribbon's tabs for a workbook: Home (clipboard, font, alignment,
// number, editing), Insert, Formulas, Data and View. Each button acts on
// the selection through the workbook's controller; the few that need the
// grid (the clipboard, starting a formula in the editor) go through
// `WorkbookController.onCommand`, which the shell points at the grid.

import Flutter
import FlutterSwiftBridge
import FluentSystemIcons
import Foundation

/// What the ribbon asks of the grid.
enum SheetCommand {
    case cut, copy, paste
    case startFormula(String)      // "=SUM(" into the editor, the selection's range filled in
    case zoom(Double)
    case toggleGridlines
    case status(String)
    case editNote                  // Review → New/Edit Note: the editor beside the active cell
}

extension Ribbon {
    func sheetsGroups(_ fluent: FluentThemeData) -> [Widget]? {
        guard let wb = session.workbook else { return nil }
        switch tab {
        case .home: return _sheetsHome(wb, fluent)
        case .insert: return [_chartsGroup(wb, fluent), _functionsGroup(wb, fluent)]
        case .formulas: return [_autoSumGroup(wb, fluent), _functionsGroup(wb, fluent)]
        case .data: return [_sortGroup(wb, fluent), _outlineGroup(wb, fluent)]
        case .view: return [_sheetsZoomGroup(wb, fluent)]
        case .review: return [_notesGroup(wb, fluent)]
        default: return nil
        }
    }

    private func _sheetsHome(_ wb: WorkbookController, _ fluent: FluentThemeData) -> [Widget] {
        let st = wb.style(at: wb.active)
        let sizes: [Double] = [8, 9, 10, 11, 12, 14, 16, 18, 20, 24, 28, 36, 48, 72]
        let family = st.fontName ?? OfficeFonts.defaultFamily
        let size = st.fontSize ?? 11
        let clipboard = Chrome.group("Clipboard", fluent, [
            Chrome.big(FluentSystemIcons.paste, "Paste", fluent) { wb.onCommand?(.paste) },
            Chrome.rows([
                Chrome.small(FluentSystemIcons.cut, "Cut", fluent) { wb.onCommand?(.cut) },
                Chrome.small(FluentSystemIcons.copy, "Copy", fluent) { wb.onCommand?(.copy) },
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
                    onChanged: { f in if let f { wb.setStyle { $0.fontName = f } } })),
                Chrome.gap(),
                SizedBox(width: 64, height: nil, child: ComboBox<Double>(
                    value: sizes.contains(size) ? size : nil,
                    items: sizes.map { n in ComboBoxItem<Double>(value: n, child: Text(n == n.rounded() ? "\(Int(n))" : "\(n)")) },
                    onChanged: { n in if let n { wb.setStyle { $0.fontSize = n } } },
                    placeholder: Text("\(Int(size))"))),
            ]),
            Chrome.vgap(4),
            Chrome.row([
                Chrome.toggle(FluentSystemIcons.textBold, "Bold (⌘B)", st.bold, fluent) { wb.setStyle { $0.bold.toggle() } },
                Chrome.toggle(FluentSystemIcons.textItalic, "Italic (⌘I)", st.italic, fluent) { wb.setStyle { $0.italic.toggle() } },
                Chrome.toggle(FluentSystemIcons.textUnderline, "Underline (⌘U)", st.underline, fluent) { wb.setStyle { $0.underline.toggle() } },
                Chrome.toggle(FluentSystemIcons.textStrikethrough, "Strikethrough", st.strike, fluent) { wb.setStyle { $0.strike.toggle() } },
                Chrome.gap(4),
                Chrome.menu(nil, Icon(FluentSystemIcons.grid, size: Chrome.iconSize, color: fluent.resources.textFillColorPrimary), fluent, [
                    ("All Borders", { wb.setStyle { $0.borders = .init(top: true, left: true, bottom: true, right: true) } }),
                    ("Bottom Border", { wb.setStyle { $0.borders.bottom = true } }),
                    ("Top Border", { wb.setStyle { $0.borders.top = true } }),
                    ("No Border", { wb.setStyle { $0.borders = .init() } }),
                ]),
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
                    wb.setStyle { $0.hAlign = $0.hAlign == .left ? .general : .left }
                },
                Chrome.toggle(FluentSystemIcons.alignCenter, "Center", st.hAlign == .center, fluent) {
                    wb.setStyle { $0.hAlign = $0.hAlign == .center ? .general : .center }
                },
                Chrome.toggle(FluentSystemIcons.alignRight, "Align Right", st.hAlign == .right, fluent) {
                    wb.setStyle { $0.hAlign = $0.hAlign == .right ? .general : .right }
                },
            ]),
            Chrome.vgap(4),
            Chrome.row([
                Chrome.textToggle("Wrap Text", st.wrap, fluent, style: fluent.typography.caption) { wb.setStyle { $0.wrap.toggle() } },
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
                MenuFlyoutItem(text: Text("Insert Sheet Rows"), onPressed: { wb.insertAtSelection(.rows) }),
                MenuFlyoutItem(text: Text("Insert Sheet Columns"), onPressed: { wb.insertAtSelection(.cols) }),
                MenuFlyoutItem(text: Text("Insert Sheet"), onPressed: { wb.addSheet() }),
            ]),
            Chrome.menuButton(FluentSystemIcons.delete, "Delete", "Delete cells", fluent, items: [
                MenuFlyoutItem(text: Text("Delete Sheet Rows"), onPressed: { wb.deleteAtSelection(.rows) }),
                MenuFlyoutItem(text: Text("Delete Sheet Columns"), onPressed: { wb.deleteAtSelection(.cols) }),
                MenuFlyoutItem(text: Text("Delete Sheet"), onPressed: wb.book.sheets.count > 1 ? { wb.deleteSheet(wb.activeSheet) } : nil),
            ]),
        ])])
        let editing = Chrome.group("Editing", fluent, [Chrome.rows([
            Chrome.small(FluentSystemIcons.mathFormula, "AutoSum", fluent) { Self._autoSum(wb) },
            Chrome.menu(Text("Fill", style: fluent.typography.caption), Icon(FluentSystemIcons.grid, size: Chrome.iconSize,
                        color: fluent.resources.textFillColorPrimary), fluent, [
                ("Down (⌘D)", { wb.fillDown() }),
                ("Right (⌘R)", { wb.fillRight() }),
            ]),
            Chrome.menu(Text("Clear", style: fluent.typography.caption), Icon(FluentSystemIcons.textClearFormatting, size: Chrome.iconSize,
                        color: fluent.resources.textFillColorPrimary), fluent, [
                ("Clear All", { wb.clearContents(); wb.setStyle { $0 = .plain } }),
                ("Clear Formats", { wb.setStyle { $0 = .plain } }),
                ("Clear Contents", { wb.clearContents() }),
            ]),
        ]), Chrome.rows([
            Chrome.small(FluentSystemIcons.search, "Find", fluent) { [session] in session.onFind?(false) },
            Chrome.small(FluentSystemIcons.textGrammarWand, "Replace", fluent) { [session] in session.onFind?(true) },
        ])])
        return [clipboard, font, alignment, number, cells, editing]
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
        return Chrome.group("Charts", fluent, [
            Chrome.rows([button(.column), button(.bar), button(.line)]),
            Chrome.rows([button(.pie), button(.area), button(.scatter)]),
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
        ]), Chrome.bigToggle(FluentSystemIcons.grid, "Filter", wb.sheet.autoFilter != nil, fluent) { wb.toggleAutoFilter() },
        Chrome.rows([
            Chrome.small(FluentSystemIcons.close, "Clear", fluent) { wb.clearFilters() },
            Chrome.small(FluentSystemIcons.refresh, "Reapply", fluent) { wb.structural { wb.reapplyFilter() } },
        ])])
    }

    private func _outlineGroup(_ wb: WorkbookController, _ fluent: FluentThemeData) -> Widget {
        Chrome.group("Outline", fluent, [Chrome.rows([
            Chrome.small(FluentSystemIcons.indentIncrease, "Group", fluent) { wb.group(true) },
            Chrome.small(FluentSystemIcons.indentDecrease, "Ungroup", fluent) { wb.group(false) },
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
                wb.structural { wb.sheet.showGridlines.toggle() }
            },
            Chrome.big(FluentSystemIcons.zoomIn, "Zoom In", fluent) { wb.onCommand?(.zoom(1.1)) },
            Chrome.big(FluentSystemIcons.zoomOut, "Zoom Out", fluent) { wb.onCommand?(.zoom(1 / 1.1)) },
            Chrome.big(FluentSystemIcons.grid, "100%", fluent) { wb.onCommand?(.zoom(0)) },
        ])
    }
}
