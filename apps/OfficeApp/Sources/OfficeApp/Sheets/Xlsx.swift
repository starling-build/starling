// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// SpreadsheetML (.xlsx): read into the workbook model and write back.
//
// Reading takes values, formulas (shared ones expanded, cached results
// kept), shared and inline strings, the styles the model has (fonts,
// fills with theme colours and tints, borders, alignment, number
// formats), column widths, row heights, merges, frozen panes, defined
// names. Writing regenerates what the model owns — the workbook, each
// sheet, the shared strings and the styles — and copies every other part
// of the original package as it was: charts, drawings, pictures, tables,
// themes, pivot caches. Inside a sheet, the elements the model does not
// read (conditional formats, validations, hyperlinks, page setup, the
// drawing that anchors a chart) are kept as their original text and
// written back in schema order. calcChain is dropped and the workbook
// asks Excel to recalculate on load, so nothing stale survives an edit.

import Foundation

enum Xlsx {
    enum ReadError: Error { case notAWorkbook, badPart(String) }

    // MARK: Reading

    static func read(_ data: Data) throws -> Workbook {
        let entries = try Zip.read(data)
        var parts: [String: Data] = [:]
        for e in entries { parts[e.name] = e.data }
        func xml(_ name: String) -> XNode? { parts[name].flatMap { XNode.parse($0) } }

        guard let wbNode = xml("xl/workbook.xml") else { throw ReadError.notAWorkbook }
        let wbRels = _rels(parts["xl/_rels/workbook.xml.rels"], base: "xl/")
        let book = Workbook(sheets: [])
        book.package = entries
        if let pr = wbNode.child("workbookPr") { book.date1904 = pr["date1904"] == "1" || pr["date1904"] == "true" }

        // Theme colours, for fills and fonts that name a slot.
        let theme = _themeColors(xml("xl/theme/theme1.xml"))
        book.themeColors = theme
        // Shared strings.
        var sst: [String] = []
        if let s = xml("xl/sharedStrings.xml") {
            for si in s.kids("si") { sst.append(_text(si)) }
        }
        // Styles: one CellStyle per cellXfs entry, in order, so a cell's
        // `s` is its index in the book's table.
        if let st = xml("xl/styles.xml") {
            book.styles = _styles(st, theme: theme)
            for i in book.styles.indices { book.styles[i].baseXf = i }
            book.styleSource = parts["xl/styles.xml"].map(_styleSource)
            if book.styles.isEmpty { book.styles = [.plain] }
            book.dxfs = (st.child("dxfs")?.kids("dxf") ?? []).map { _dxf($0, theme: theme) }
        }
        if let raw = parts["xl/styles.xml"] {
            let split = RawXML.split([UInt8](raw))
            for (name, text) in split.children where ["dxfs", "tableStyles", "colors", "extLst"].contains(name) {
                book.keptStyleParts[name] = text
            }
            // Its root tag declares the prefixes those parts use (x14, x15…).
            if split.rootName.hasSuffix("styleSheet") { book.keptStyleParts["root"] = split.rootStart }
        }

        // Sheets, in tab order.
        var activeTab = 0
        if let view = wbNode.child("bookViews")?.kids("workbookView").first, let a = Int(view["activeTab"] ?? "") { activeTab = a }
        for s in wbNode.child("sheets")?.kids("sheet") ?? [] {
            guard let name = s["name"], let rid = s["r:id"], let path = wbRels[rid] else { continue }
            let ws = Worksheet(name: name)
            ws.origin = path
            if let raw = parts[path] { try _readSheet(raw, into: ws, sst: sst, book: book) }
            if s["state"] == "hidden" || s["state"] == "veryHidden" { ws.hidden = true }
            book.sheets.append(ws)
        }
        // Pictures and charts, drawn from the file's own parts.
        let themeRoot = xml("xl/theme/theme1.xml")
        if themeRoot != nil { book.chartTheme = DeckTheme(xlsxTheme: themeRoot) }
        let colors = ColorContext(theme: PptxTheme(themeRoot))
        for ws in book.sheets {
            if let path = ws.origin {
                (ws.drawings, ws.drawingPart, ws.drawingRoot) = SheetDrawingsXML.read(sheetPath: path, parts: parts, colors: colors)
                ws.tables = TablesXML.read(sheetPath: path, parts: parts)
                (ws.notes, ws.noteParts) = NotesXML.read(sheetPath: path, parts: parts)
                for r in _relList(parts[_relsPath(path)]) where r.type.hasSuffix("/hyperlink") { ws.linkTargets[r.id] = r.target }
            }
        }
        if book.sheets.isEmpty { book.sheets = [Worksheet(name: "Sheet1")] }
        book.activeTab = min(max(0, activeTab), book.sheets.count - 1)

        // Defined names (print areas and other built-ins are not formulas to evaluate).
        for n in wbNode.child("definedNames")?.kids("definedName") ?? [] {
            guard let name = n["name"] else { continue }
            var attrs = n.attrs
            attrs["name"] = nil
            let local = attrs.removeValue(forKey: "localSheetId").flatMap { Int($0) }
            book.fileNames.append(DefinedName(name: name, localSheet: local, attrs: attrs, text: n.text))
            guard !name.hasPrefix("_xlnm.") else { continue }
            book.names[name.uppercased()] = n.text
            book.nameSpellings[name.uppercased()] = name
        }
        return book
    }

    /// `<autoFilter ref><filterColumn colId><filters blank><filter val/>…`.
    /// Value lists are modelled; any other kind of column filter (custom,
    /// top 10, dynamic, colour, date groups) or a sort state keeps the
    /// whole element as written, until the filter is changed here.
    private static func _readAutoFilter(_ node: XNode, range: CellRange, raw: String?) -> AutoFilter {
        var af = AutoFilter(range: range)
        var modelled = node.kids("sortState").isEmpty
        for fc in node.kids("filterColumn") {
            guard let id = Int(fc["colId"] ?? "") else { modelled = false; continue }
            guard let filters = fc.child("filters"), fc.kids("filters").count == 1,
                  filters.kids("dateGroupItem").isEmpty else { modelled = false; continue }
            var allowed = Set(filters.kids("filter").compactMap { $0["val"] })
            if filters["blank"] == "1" { allowed.insert("") }
            af.columns[range.left + id] = allowed
        }
        if !modelled { af.raw = raw }
        return af
    }

    private static func _readSheet(_ raw: Data, into ws: Worksheet, sst: [String], book: Workbook) throws {
        let bytes = [UInt8](raw)
        // The elements we do not model, kept as their original text.
        let split = RawXML.split(bytes)
        ws.rootTag = split.rootStart
        let modeled: Set<String> = ["dimension", "sheetViews", "sheetFormatPr", "cols", "sheetData", "mergeCells", "autoFilter"]
        for (name, text) in split.children where !modeled.contains(name) {
            ws.keptElements.append((name, text))
        }
        guard let root = XNode.parse(raw) else { throw ReadError.badPart(ws.origin ?? ws.name) }
        if let node = root.child("autoFilter"), let ref = node["ref"], let range = CellRange(ref) {
            ws.autoFilter = _readAutoFilter(node, range: range, raw: split.children.first { $0.name == "autoFilter" }?.text)
        }

        if let pr = root.child("sheetPr"), let tab = pr.child("tabColor")?["rgb"] { ws.tabColor = tab }
        // Frozen panes and the selection.
        if let view = root.child("sheetViews")?.kids("sheetView").first {
            if let pane = view.child("pane"), pane["state"] == "frozen" || pane["state"] == "frozenSplit" {
                ws.freezeCols = Int(Double(pane["xSplit"] ?? "0") ?? 0)
                ws.freezeRows = Int(Double(pane["ySplit"] ?? "0") ?? 0)
            }
            if let sel = view.kids("selection").last, let a = sel["activeCell"].flatMap({ CellAddress($0) }) { ws.savedActive = a }
            if view["showGridLines"] == "0" { ws.showGridlines = false }
            ws.viewAttrs = view.attrs.filter { !["tabSelected", "showGridLines", "workbookViewId"].contains($0.key) }
        }
        if let f = root.child("sheetFormatPr") {
            if let h = Double(f["defaultRowHeight"] ?? "") { ws.defaultRowHeightPt = h }
            ws.formatPrAttrs = f.attrs.filter { $0.key != "defaultRowHeight" }
        }
        // Column widths are in characters of the default font's widest
        // digit (7 px for Calibri 11) plus 5 px of padding.
        for col in root.child("cols")?.kids("col") ?? [] {
            guard let lo = Int(col["min"] ?? ""), let hi = Int(col["max"] ?? "") else { continue }
            let extra = col.attrs.filter { !["min", "max", "width", "customWidth", "hidden"].contains($0.key) }
            if !extra.isEmpty { ws.colAttrRuns.append((lo - 1, min(hi, CellAddress.maxCols) - 1, extra)) }
            let hidden = col["hidden"] == "1"
            guard let w = Double(col["width"] ?? "") ?? (hidden ? 0 : nil) else { continue }
            let pt = hidden ? 0 : _charsToPoints(w)
            // A run over the whole sheet (a default width) is not 16k entries.
            if hi - lo > 2000 { if !hidden { ws.defaultColWidthPt = pt; ws.defaultColWidthChars = w }; continue }
            for c in lo ... hi where c >= 1 && c <= CellAddress.maxCols {
                if abs(pt - Worksheet.defaultColWidth) > 0.01 || hidden { ws.colWidths[c - 1] = pt; if !hidden { ws.colWidthChars[c - 1] = w } }
            }
        }
        // Cells.
        var shared: [String: (CellAddress, FormulaExpr)] = [:]
        var spillAreas: [(CellAddress, CellRange)] = []
        var cells: [CellAddress: Cell] = [:]
        var rowIndex = 0
        for row in root.child("sheetData")?.kids("row") ?? [] {
            rowIndex = Int(row["r"] ?? "").map { $0 - 1 } ?? rowIndex
            let rowExtra = row.attrs.filter { !["r", "ht", "customHeight", "hidden", "spans"].contains($0.key) }
            if !rowExtra.isEmpty { ws.rowAttrs[rowIndex] = rowExtra }
            // `ht` is the row's height whether or not it is marked custom (a
            // larger font makes a taller row without the flag).
            // A row a filter hid keeps its height; one hidden by hand is height 0.
            if row["hidden"] == "1", let af = ws.autoFilter, rowIndex > af.range.top, rowIndex <= af.range.bottom {
                ws.filteredRows.insert(rowIndex)
                if let h = Double(row["ht"] ?? ""), abs(h - ws.defaultRowHeightPt) > 0.01 { ws.rowHeights[rowIndex] = h }
            } else if row["hidden"] == "1" { ws.rowHeights[rowIndex] = 0 }
            else if let h = Double(row["ht"] ?? ""), abs(h - ws.defaultRowHeightPt) > 0.01 { ws.rowHeights[rowIndex] = h }
            var colIndex = 0
            for c in row.kids("c") {
                let a = c["r"].flatMap { CellAddress($0) } ?? CellAddress(row: rowIndex, col: colIndex)
                colIndex = a.col + 1
                let styleIndex = Int(c["s"] ?? "0") ?? 0
                let t = c["t"] ?? "n"
                let vText = c.child("v")?.text
                var value: CellValue = .empty
                switch t {
                case "s": value = Int(vText ?? "").flatMap { $0 < sst.count ? CellValue.text(sst[$0]) : nil } ?? .empty
                case "inlineStr": value = c.child("is").map { .text(_text($0)) } ?? .empty
                case "str": value = .text(vText ?? "")
                case "b": value = .bool(vText == "1")
                case "e": value = .error(ExcelError(rawValue: vText ?? "") ?? .value)
                default: value = vText.flatMap { Double($0) }.map { .number($0) } ?? .empty
                }
                var cell = Cell(input: "")
                cell.style = styleIndex < book.styles.count ? styleIndex : 0
                for k in ["vm", "cm", "ph"] { if let v = c[k] { cell.keptAttrs[k] = v } }
                if let f = c.child("f") {
                    // As the file wrote it, for when it cannot be read.
                    let rawF: String = {
                        var s = "<f"
                        for (k, v) in f.attrs.sorted(by: { $0.key < $1.key }) { s += " \(k)=\"\(_esc(v))\"" }
                        return f.text.isEmpty ? s + "/>" : s + ">" + _esc(f.text) + "</f>"
                    }()
                    var expr: FormulaExpr? = nil
                    if f["t"] == "shared", let si = f["si"] {
                        if !f.text.isEmpty, let e = try? Formula.parse(f.text) {
                            expr = _unprefix(e)
                            shared[si] = (a, expr!)
                        } else if let (anchor, master) = shared[si] {
                            expr = Formula.shifted(master, rows: a.row - anchor.row, cols: a.col - anchor.col)
                        }
                    } else if !f.text.isEmpty {
                        expr = (try? Formula.parse(f.text)).map(_unprefix)
                        if f["t"] == "array" { cell.arrayRef = f["ref"] ?? a.a1 }
                    }
                    if let expr {
                        cell.formula = expr
                        cell.input = Formula.text(expr)
                        cell.cached = value
                        cell.value = value
                        // An array formula computes here: a dynamic one, whose
                        // range's other cells are its last spill (recomputed).
                        if let ref = cell.arrayRef, !Formula.usesUnknownFunction(expr) {
                            cell.dynamic = true
                            if let r = CellRange(ref), !r.isSingle { spillAreas.append((a, r)) }
                        }
                    } else {
                        // A formula we cannot parse (or a shared one built on
                        // one): its result stays, and its <f> goes back as it was.
                        cell.input = f.text.isEmpty ? NumberFormat.display(value, "General", width: 255).text : "=" + f.text
                        cell.value = value
                        cell.cached = value
                        cell.rawFormula = rawF
                    }
                } else {
                    cell.value = value
                    switch value {
                    case .text(let s): cell.input = s
                    case .bool(let b): cell.input = b ? "TRUE" : "FALSE"
                    case .error(let e): cell.input = e.rawValue
                    case .number(let n): cell.input = NumberFormat.full(n)
                    case .empty: break
                    }
                }
                if cell.value.isEmpty && cell.formula == nil && cell.style == 0 && cell.input.isEmpty { continue }
                cells[a] = cell
            }
            rowIndex += 1
        }
        // The spill values an array formula left in the file go: computing it
        // puts them back (where the formula cannot be computed, they stay).
        for (anchor, r) in spillAreas {
            for row in r.top ... r.bottom {
                for col in r.left ... r.right {
                    let a = CellAddress(row: row, col: col)
                    guard a != anchor, let c = cells[a], c.formula == nil, c.rawFormula == nil else { continue }
                    if c.style == 0 { cells[a] = nil } else { cells[a]?.value = .empty; cells[a]?.input = "" }
                }
            }
        }
        ws.cells = cells
        for m in root.child("mergeCells")?.kids("mergeCell") ?? [] {
            if let r = m["ref"].flatMap({ CellRange($0) }) { ws.merges.append(r) }
        }
    }

    /// A stored column width (characters of the default font's widest
    /// digit, 7 px for Calibri 11, padding included) as points, and back —
    /// ECMA-376 18.3.1.13's formulas, which round-trip to the pixel.
    static func _charsToPoints(_ w: Double) -> Double {
        ((256 * w + (128.0 / 7).rounded(.down)) / 256 * 7).rounded(.down) * 0.75
    }
    /// A column's width for the file: as the file had it while unchanged.
    static func _widthChars(_ ws: Worksheet, _ col: Int, _ pt: Double) -> Double {
        if let w = ws.colWidthChars[col], _charsToPoints(w) == pt { return w }
        return _pointsToChars(pt)
    }

    static func _pointsToChars(_ pt: Double) -> Double {
        let px = (pt / 0.75).rounded()
        return (px / 7 * 256).rounded(.down) / 256
    }

    /// Strip the _xlfn. prefixes newer functions carry in files.
    static func _unprefix(_ e: FormulaExpr) -> FormulaExpr {
        _mapCalls(e) { Formula.unprefixed($0) }
    }

    static func _mapCalls(_ e: FormulaExpr, _ f: (String) -> String) -> FormulaExpr {
        switch e {
        case .call(let n, let args): return .call(f(n), args.map { _mapCalls($0, f) })
        case .negate(let x): return .negate(_mapCalls(x, f))
        case .plus(let x): return .plus(_mapCalls(x, f))
        case .percent(let x): return .percent(_mapCalls(x, f))
        case .paren(let x): return .paren(_mapCalls(x, f))
        case .binary(let op, let a, let b): return .binary(op, _mapCalls(a, f), _mapCalls(b, f))
        default: return e
        }
    }

    /// Functions Excel writes with the _xlfn. prefix (added after 2007).
    static let prefixed: Set<String> = [
        "XLOOKUP", "XMATCH", "IFS", "IFNA", "XOR", "CONCAT", "TEXTJOIN", "SWITCH", "MAXIFS", "MINIFS",
        "STDEV.S", "STDEV.P", "VAR.S", "VAR.P", "DAYS", "FILTER", "SORT", "SORTBY", "UNIQUE", "SEQUENCE",
        "LET", "LAMBDA", "SINGLE", "VSTACK", "HSTACK", "TAKE", "DROP", "CHOOSEROWS", "CHOOSECOLS",
        "TOCOL", "TOROW", "WRAPROWS", "WRAPCOLS", "TEXTSPLIT", "CEILING.MATH", "FLOOR.MATH", "ISOWEEKNUM", "NUMBERVALUE", "TEXTBEFORE", "TEXTAFTER",
    ]

    /// The text of an <si> or <is>: its <t>, or its runs' <t>s joined.
    static func _text(_ n: XNode) -> String {
        if let t = n.child("t") { return t.text }
        return n.kids("r").compactMap { $0.child("t")?.text }.joined()
    }

    /// A relationships part as id → absolute part path.
    static func _rels(_ data: Data?, base: String) -> [String: String] {
        guard let data, let root = XNode.parse(data) else { return [:] }
        var out: [String: String] = [:]
        for r in root.kids("Relationship") {
            guard let id = r["Id"], let target = r["Target"], r["TargetMode"] != "External" else { continue }
            out[id] = _resolve(target, base: base)
        }
        return out
    }

    static func _resolve(_ target: String, base: String) -> String {
        if target.hasPrefix("/") { return String(target.dropFirst()) }
        var parts = base.split(separator: "/").map(String.init)
        for seg in target.split(separator: "/") {
            if seg == ".." { if !parts.isEmpty { parts.removeLast() } } else if seg != "." { parts.append(String(seg)) }
        }
        return parts.joined(separator: "/")
    }

    // MARK: Styles

    /// Excel's built-in number formats, by id.
    static let builtinFormats: [Int: String] = [
        0: "General", 1: "0", 2: "0.00", 3: "#,##0", 4: "#,##0.00", 9: "0%", 10: "0.00%", 11: "0.00E+00",
        12: "# ?/?", 13: "# ??/??", 14: "m/d/yyyy", 15: "d-mmm-yy", 16: "d-mmm", 17: "mmm-yy",
        18: "h:mm AM/PM", 19: "h:mm:ss AM/PM", 20: "h:mm", 21: "h:mm:ss", 22: "m/d/yyyy h:mm",
        37: "#,##0 ;(#,##0)", 38: "#,##0 ;[Red](#,##0)", 39: "#,##0.00;(#,##0.00)", 40: "#,##0.00;[Red](#,##0.00)",
        44: "_($* #,##0.00_);_($* (#,##0.00);_($* \"-\"??_);_(@_)",
        45: "mm:ss", 46: "[h]:mm:ss", 47: "mmss.0", 48: "##0.0E+0", 49: "@",
        5: "$#,##0_);($#,##0)", 6: "$#,##0_);[Red]($#,##0)", 7: "$#,##0.00_);($#,##0.00)", 8: "$#,##0.00_);[Red]($#,##0.00)",
        41: "_(* #,##0_);_(* (#,##0);_(* \"-\"_);_(@_)", 42: "_($* #,##0_);_($* (#,##0);_($* \"-\"_);_(@_)",
        43: "_(* #,##0.00_);_(* (#,##0.00);_(* \"-\"??_);_(@_)",
    ]

    private struct _Font { var bold = false, italic = false, underline = false, strike = false
        var size: Double? = nil, name: String? = nil, color: UInt32? = nil }

    static func _styles(_ st: XNode, theme: [UInt32]) -> [CellStyle] {
        var formats = builtinFormats
        for nf in st.child("numFmts")?.kids("numFmt") ?? [] {
            if let id = Int(nf["numFmtId"] ?? ""), let code = nf["formatCode"] { formats[id] = code }
        }
        var fonts: [_Font] = []
        for f in st.child("fonts")?.kids("font") ?? [] {
            var font = _Font()
            font.bold = f.child("b").map { $0["val"] != "0" && $0["val"] != "false" } ?? false
            font.italic = f.child("i").map { $0["val"] != "0" && $0["val"] != "false" } ?? false
            font.underline = f.child("u").map { $0["val"] != "none" } ?? false
            font.strike = f.child("strike").map { $0["val"] != "0" && $0["val"] != "false" } ?? false
            font.size = f.child("sz").flatMap { Double($0["val"] ?? "") }
            font.name = f.child("name")?["val"]
            font.color = f.child("color").flatMap { _color($0, theme: theme) }
            fonts.append(font)
        }
        let base = fonts.first ?? _Font()
        var fills: [UInt32?] = []
        for f in st.child("fills")?.kids("fill") ?? [] {
            if let p = f.child("patternFill"), p["patternType"] == "solid" {
                fills.append(p.child("fgColor").flatMap { _color($0, theme: theme) })
            } else { fills.append(nil) }
        }
        var borders: [CellStyle.Borders] = []
        for b in st.child("borders")?.kids("border") ?? [] {
            func has(_ side: String) -> Bool { b.child(side).map { $0["style"] != nil && $0["style"] != "none" } ?? false }
            var bd = CellStyle.Borders(top: has("top"), left: has("left"), bottom: has("bottom"), right: has("right"))
            for side in ["top", "left", "bottom", "right"] where has(side) {
                let n = b.child(side)!
                if let k = n["style"], k != "thin" { bd.kinds[side] = k }
                if let c = n.child("color").flatMap({ _color($0, theme: theme) }), c != 0 { bd.colors[side] = c }
            }
            borders.append(bd)
        }
        var out: [CellStyle] = []
        for xf in st.child("cellXfs")?.kids("xf") ?? [] {
            var s = CellStyle()
            if let id = Int(xf["numFmtId"] ?? "0") { s.numberFormat = formats[id] ?? "General" }
            if let fi = Int(xf["fontId"] ?? "0"), fi < fonts.count {
                let f = fonts[fi]
                s.bold = f.bold; s.italic = f.italic; s.underline = f.underline; s.strike = f.strike
                // The default font is the theme's: left nil, so a new face follows it.
                if f.name != base.name { s.fontName = f.name }
                if f.size != base.size { s.fontSize = f.size }
                if let c = f.color, c != 0x000000 { s.color = c }
            }
            if let fi = Int(xf["fillId"] ?? "0"), fi < fills.count { s.fill = fills[fi] }
            if let bi = Int(xf["borderId"] ?? "0"), bi < borders.count { s.borders = borders[bi] }
            if let al = xf.child("alignment") {
                switch al["horizontal"] {
                case "left": s.hAlign = .left
                case "center", "centerContinuous": s.hAlign = .center
                case "right": s.hAlign = .right
                default: break
                }
                switch al["vertical"] {
                case "top": s.vAlign = .top
                case "center": s.vAlign = .center
                default: break
                }
                s.wrap = al["wrapText"] == "1" || al["wrapText"] == "true"
            }
            out.append(s)
        }
        return out
    }

    /// A <color> as 0xRRGGBB: rgb, a theme slot with its tint, or a
    /// legacy palette index; nil for "automatic".
    /// `<dxf>`: font and fill, as far as they are set. A solid fill's
    /// colour is its bgColor here, unlike a cell's.
    static func _dxf(_ d: XNode, theme: [UInt32]) -> DxfStyle {
        var x = DxfStyle()
        if let f = d.child("font") {
            func on(_ n: String) -> Bool? { f.child(n).map { $0["val"] != "0" && $0["val"] != "false" } }
            x.bold = on("b"); x.italic = on("i"); x.strike = on("strike")
            if let u = f.child("u") { x.underline = u["val"] != "none" }
            if let c = f.child("color") { x.color = _color(c, theme: theme) }
        }
        if let p = d.child("fill")?.child("patternFill") {
            if let c = p.child("bgColor") ?? p.child("fgColor") { x.fill = _color(c, theme: theme) }
        }
        return x
    }

    static func _color(_ c: XNode, theme: [UInt32]) -> UInt32? {
        var rgb: UInt32? = nil
        if let s = c["rgb"], let v = UInt32(s.suffix(6), radix: 16) { rgb = v }
        else if let t = c["theme"].flatMap({ Int($0) }), t < theme.count { rgb = theme[t] }
        else if let i = c["indexed"].flatMap({ Int($0) }), i < _indexed.count { rgb = _indexed[i] }
        guard var v = rgb else { return nil }
        if let tint = c["tint"].flatMap({ Double($0) }), tint != 0 {
            func ch(_ x: UInt32) -> UInt32 {
                let d = Double(x)
                return UInt32(max(0, min(255, (tint < 0 ? d * (1 + tint) : d + (255 - d) * tint).rounded())))
            }
            v = (ch((v >> 16) & 0xFF) << 16) | (ch((v >> 8) & 0xFF) << 8) | ch(v & 0xFF)
        }
        return v
    }

    /// Excel's theme slots in the order cells name them (lt1, dk1, lt2,
    /// dk2, accent1–6, hlink, folHlink), from the file's theme or Office's.
    static func _themeColors(_ t: XNode?) -> [UInt32] {
        let office: [UInt32] = [0xFFFFFF, 0x000000, 0xE7E6E6, 0x44546A, 0x4472C4, 0xED7D31, 0xA5A5A5, 0xFFC000,
                                0x5B9BD5, 0x70AD47, 0x0563C1, 0x954F72]
        guard let scheme = t?.descendant("a:clrScheme") ?? t?.descendant("clrScheme") else { return office }
        func val(_ name: String) -> UInt32? {
            guard let n = scheme.child(name) else { return nil }
            if let s = n.child("srgbClr")?["val"] { return UInt32(s, radix: 16) }
            if let s = n.child("sysClr")?["lastClr"] { return UInt32(s, radix: 16) }
            return nil
        }
        let order = ["lt1", "dk1", "lt2", "dk2", "accent1", "accent2", "accent3", "accent4", "accent5", "accent6", "hlink", "folHlink"]
        return order.enumerated().map { val($0.element) ?? office[$0.offset] }
    }

    static let _indexed: [UInt32] = [
        0x000000, 0xFFFFFF, 0xFF0000, 0x00FF00, 0x0000FF, 0xFFFF00, 0xFF00FF, 0x00FFFF,
        0x000000, 0xFFFFFF, 0xFF0000, 0x00FF00, 0x0000FF, 0xFFFF00, 0xFF00FF, 0x00FFFF,
        0x800000, 0x008000, 0x000080, 0x808000, 0x800080, 0x008080, 0xC0C0C0, 0x808080,
        0x9999FF, 0x993366, 0xFFFFCC, 0xCCFFFF, 0x660066, 0xFF8080, 0x0066CC, 0xCCCCFF,
        0x000080, 0xFF00FF, 0xFFFF00, 0x00FFFF, 0x800080, 0x800000, 0x008080, 0x0000FF,
        0x00CCFF, 0xCCFFFF, 0xCCFFCC, 0xFFFF99, 0x99CCFF, 0xFF99CC, 0xCC99FF, 0xFFCC99,
        0x3366FF, 0x33CCCC, 0x99CC00, 0xFFCC00, 0xFF9900, 0xFF6600, 0x666699, 0x969696,
        0x003366, 0x339966, 0x003300, 0x333300, 0x993300, 0x993366, 0x333399, 0x333333,
    ]

    // MARK: Writing

    static func write(_ book: Workbook) throws -> Data {
        var out: [ZipEntry] = []
        let original = book.package ?? []
        var originalParts: [String: Data] = [:]
        for e in original { originalParts[e.name] = e.data }

        // Where each sheet goes: its own part if it came from the file, a
        // fresh name otherwise.
        var used = Set(book.sheets.compactMap { $0.origin })
        var paths: [String] = []
        var n = 1
        for ws in book.sheets {
            if let o = ws.origin, originalParts[o] != nil { paths.append(o); continue }
            while used.contains("xl/worksheets/sheet\(n).xml") || originalParts["xl/worksheets/sheet\(n).xml"] != nil { n += 1 }
            let p = "xl/worksheets/sheet\(n).xml"
            used.insert(p); paths.append(p)
        }
        // Original sheets that were deleted take their rels with them.
        let originalSheetPaths = Set(_sheetPaths(originalParts))
        let removed = originalSheetPaths.subtracting(paths)

        // Shared strings and styles are rebuilt from the model.
        var sst: [String] = []
        var sstIndex: [String: Int] = [:]
        func stringIndex(_ s: String) -> Int {
            if let i = sstIndex[s] { return i }
            sst.append(s); sstIndex[s] = sst.count - 1
            return sst.count - 1
        }
        // Drawings changed here: their parts first, since a new one adds a
        // <drawing> element to its sheet.
        var taken = Set(originalParts.keys).union(paths)
        var drawingParts: [DrawingParts] = []
        var noteParts: [NoteParts] = []
        var sheetRelParts: [String: Data] = [:]
        let calc: CalcEngine? = book.sheets.contains(where: \.drawingsEdited) ? CalcEngine(book) : nil
        calc?.storedValuesOnly = true
        for (i, ws) in book.sheets.enumerated() {
            // One relationship list per sheet, shared by whatever adds to it.
            var rels = _relList(originalParts[_relsPath(paths[i])])
            var changed = false
            drawingParts.append(SheetDrawingsXML.write(ws, sheetPath: paths[i], live: { sc in
                calc.map { sc.live(book: book, engine: $0) } ?? sc.chart
            }, original: originalParts, taken: &taken, sheetRels: &rels, relsChanged: &changed))
            noteParts.append(NotesXML.write(ws, sheetPath: paths[i], original: originalParts, taken: &taken,
                                            sheetRels: &rels, relsChanged: &changed))
            if changed { sheetRelParts[_relsPath(paths[i])] = Data(_relsXML(rels).utf8) }
        }
        // Excel 365 marks a dynamic-array formula with cell metadata (cm=…)
        // pointing at an XLDAPR entry in xl/metadata.xml: the file's own
        // entry when it has one, else a part made for it.
        let hasDynamic = book.sheets.contains { $0.cells.values.contains { $0.dynamic && $0.formula != nil && ($0.spillRange != nil || $0.arrayRef != nil) } }
        let originalWorkbookRels = _relList(originalParts["xl/_rels/workbook.xml.rels"])
        let metadataPath = originalWorkbookRels.first { $0.type.hasSuffix("/sheetMetadata") }.map { _resolve($0.target, base: "xl/") }
        var dynamicCm: Int? = nil
        var newMetadata = false
        if hasDynamic {
            if let path = metadataPath {
                dynamicCm = originalParts[path].flatMap(_dynamicArrayCm)
            } else {
                dynamicCm = 1
                newMetadata = true
            }
        }
        var sheetXML: [String] = []
        for (i, ws) in book.sheets.enumerated() {
            var extra: [String: String] = [:]
            if let e = drawingParts[i].element { extra["drawing"] = e }
            if let e = noteParts[i].element { extra["legacyDrawing"] = e }
            sheetXML.append(_sheetXML(ws, book: book, selected: i == book.activeTab, extra: extra, dynamicCm: dynamicCm,
                                      stringIndex: stringIndex))
        }

        // The workbook part and its relationships.
        var rels = _relList(originalParts["xl/_rels/workbook.xml.rels"])
        rels.removeAll { r in
            r.type.hasSuffix("/calcChain") ||
            (r.type.hasSuffix("/worksheet") && removed.contains(_resolve(r.target, base: "xl/")))
        }
        var sheetIds: [String] = []
        for p in paths {
            if let r = rels.first(where: { _resolve($0.target, base: "xl/") == p && $0.type.hasSuffix("/worksheet") }) {
                sheetIds.append(r.id)
            } else {
                let id = _freshId(rels)
                rels.append((id, "http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet",
                             String(p.dropFirst("xl/".count))))
                sheetIds.append(id)
            }
        }
        if newMetadata {
            rels.append((_freshId(rels), "http://schemas.openxmlformats.org/officeDocument/2006/relationships/sheetMetadata", "metadata.xml"))
        }
        if !rels.contains(where: { $0.type.hasSuffix("/styles") }) {
            rels.append((_freshId(rels), "http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles", "styles.xml"))
        }
        if !rels.contains(where: { $0.type.hasSuffix("/sharedStrings") }) {
            rels.append((_freshId(rels), "http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings", "sharedStrings.xml"))
        }
        let stylesPath = rels.first { $0.type.hasSuffix("/styles") }.map { _resolve($0.target, base: "xl/") } ?? "xl/styles.xml"
        let sstPath = rels.first { $0.type.hasSuffix("/sharedStrings") }.map { _resolve($0.target, base: "xl/") } ?? "xl/sharedStrings.xml"

        var generated: [String: Data] = [:]
        generated["xl/workbook.xml"] = Data(_workbookXML(book, ids: sheetIds, original: originalParts["xl/workbook.xml"]).utf8)
        generated["xl/_rels/workbook.xml.rels"] = Data(_relsXML(rels).utf8)
        for (i, p) in paths.enumerated() { generated[p] = Data(sheetXML[i].utf8) }
        generated[stylesPath] = Data(_stylesXML(book).utf8)
        if newMetadata { generated["xl/metadata.xml"] = Data(_dynamicArrayMetadata.utf8) }
        generated[sstPath] = Data(_sstXML(sst).utf8)
        // Tables: rewritten whenever their header cells or range could have
        // changed, which is any save (names must match the cells exactly).
        for ws in book.sheets {
            for t in ws.tables {
                guard let original = originalParts[t.path] else { continue }
                generated[t.path] = TablesXML.write(t, original: original, header: { col in
                    let v = ws.value(CellAddress(row: t.ref.top, col: col))
                    return NumberFormat.display(v, book.style(ws.cells[CellAddress(row: t.ref.top, col: col)]?.style ?? 0).numberFormat,
                                                width: 255).text
                })
            }
        }
        var extraTypes: [(String, String)] = []
        var droppedDrawings = Set<String>()
        for d in drawingParts {
            generated.merge(d.parts) { $1 }
            extraTypes += d.overrides
            droppedDrawings.formUnion(d.dropped)
        }
        for n in noteParts {
            generated.merge(n.parts) { $1 }
            extraTypes += n.overrides
        }
        if newMetadata { extraTypes.append(("/xl/metadata.xml", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheetMetadata+xml")) }
        generated.merge(sheetRelParts) { $1 }

        // Content types: the original's, with the parts we added and without
        // the ones we dropped.
        var dropped = removed
        for p in removed { dropped.insert(_relsPath(p)) }
        dropped.formUnion(originalParts.keys.filter { $0.hasSuffix("calcChain.xml") })
        dropped.formUnion(droppedDrawings)
        generated["[Content_Types].xml"] = Data(_contentTypes(originalParts["[Content_Types].xml"],
                                                              sheets: paths, styles: stylesPath, sst: sstPath, dropped: dropped,
                                                              extra: extraTypes).utf8)
        if originalParts["_rels/.rels"] == nil { generated["_rels/.rels"] = Data(_rootRels.utf8) }

        // Everything: the original parts in their order (replaced where
        // regenerated), then the new ones.
        var written = Set<String>()
        for e in original where !dropped.contains(e.name) {
            out.append(ZipEntry(name: e.name, data: generated[e.name] ?? e.data))
            written.insert(e.name)
        }
        let order = ["[Content_Types].xml", "_rels/.rels", "xl/workbook.xml", "xl/_rels/workbook.xml.rels"]
        for name in order + generated.keys.sorted() where !written.contains(name) {
            guard let d = generated[name] else { continue }
            out.append(ZipEntry(name: name, data: d))
            written.insert(name)
        }
        return try Zip.write(out)
    }

    private static func _sheetPaths(_ parts: [String: Data]) -> [String] {
        _relList(parts["xl/_rels/workbook.xml.rels"]).filter { $0.type.hasSuffix("/worksheet") }.map { _resolve($0.target, base: "xl/") }
    }

    static func _relsPath(_ part: String) -> String {
        let dir = part.deletingLastPathComponent
        return (dir.isEmpty ? "" : dir + "/") + "_rels/" + part.lastPathComponent + ".rels"
    }

    static func _relList(_ data: Data?) -> [(id: String, type: String, target: String)] {
        guard let data, let root = XNode.parse(data) else { return [] }
        return root.kids("Relationship").compactMap { r in
            guard let id = r["Id"], let type = r["Type"], let target = r["Target"] else { return nil }
            return (id, type, target)
        }
    }

    static func _freshId(_ rels: [(id: String, type: String, target: String)]) -> String {
        var n = rels.count + 1
        while rels.contains(where: { $0.id == "rId\(n)" }) { n += 1 }
        return "rId\(n)"
    }

    static func _relsXML(_ rels: [(id: String, type: String, target: String)]) -> String {
        var s = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
        for r in rels { s += "<Relationship Id=\"\(_esc(r.id))\" Type=\"\(_esc(r.type))\" Target=\"\(_esc(r.target))\"/>" }
        return s + "</Relationships>"
    }

    private static let _rootRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>
    """

    private static func _contentTypes(_ original: Data?, sheets: [String], styles: String, sst: String, dropped: Set<String>,
                                      extra: [(String, String)] = []) -> String {
        var defaults: [(String, String)] = [("rels", "application/vnd.openxmlformats-package.relationships+xml"), ("xml", "application/xml")]
        var overrides: [(String, String)] = []
        if let original, let root = XNode.parse(original) {
            defaults = root.kids("Default").compactMap { d in d["Extension"].flatMap { e in d["ContentType"].map { (e, $0) } } }
            overrides = root.kids("Override").compactMap { o in o["PartName"].flatMap { p in o["ContentType"].map { (p, $0) } } }
        }
        overrides.removeAll { dropped.contains(String($0.0.dropFirst())) }
        func ensure(_ part: String, _ type: String) {
            if !overrides.contains(where: { $0.0 == "/" + part }) { overrides.append(("/" + part, type)) }
        }
        ensure("xl/workbook.xml", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml")
        for p in sheets { ensure(p, "application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml") }
        ensure(styles, "application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml")
        ensure(sst, "application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml")
        for (p, t) in extra { ensure(String(p.dropFirst()), t) }
        var s = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">"
        for (e, t) in defaults { s += "<Default Extension=\"\(_esc(e))\" ContentType=\"\(_esc(t))\"/>" }
        for (p, t) in overrides { s += "<Override PartName=\"\(_esc(p))\" ContentType=\"\(_esc(t))\"/>" }
        return s + "</Types>"
    }

    private static func _workbookXML(_ book: Workbook, ids: [String], original: Data?) -> String {
        var sheets = "<sheets>"
        for (i, ws) in book.sheets.enumerated() {
            sheets += "<sheet name=\"\(_esc(ws.name))\" sheetId=\"\(i + 1)\"" + (ws.hidden ? " state=\"hidden\"" : "") + " r:id=\"\(ids[i])\"/>"
        }
        sheets += "</sheets>"
        let calc = "<calcPr calcId=\"191029\" fullCalcOnLoad=\"1\"/>"
        // The original's other elements (workbookPr, bookViews, definedNames,
        // pivot caches, extLst…) stay, in their places.
        if let original {
            let split = RawXML.split([UInt8](original))
            var body = ""
            var wroteSheets = false, wroteCalc = false
            let names = _definedNamesXML(book)
            var wroteNames = false
            for (name, text) in split.children {
                switch name {
                case "sheets": body += sheets + (split.children.contains { $0.name == "definedNames" } ? "" : names); wroteSheets = true
                case "definedNames": body += names; wroteNames = true
                case "calcPr": body += calc; wroteCalc = true
                case "bookViews": body += _bookViews(text, active: book.activeTab)
                default:
                    if name == "definedNames" || name == "extLst" || name == "pivotCaches" || name == "webPublishing"
                        || name == "fileRecoveryPr" || name == "webPublishObjects" || name == "oleSize" || name == "customWorkbookViews" {
                        if !wroteCalc && (name != "definedNames") { body += calc; wroteCalc = true }
                    }
                    body += text
                }
            }
            if !wroteSheets { body = sheets + (wroteNames ? "" : names) + body }
            if !wroteCalc { body += calc }
            return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n" + split.rootStart + body + "</" + split.rootName + ">"
        }
        let names = _definedNamesXML(book)
        return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><bookViews><workbookView activeTab=\"\(book.activeTab)\"/></bookViews>" + sheets + names + calc + "</workbook>"
    }

    /// The file's names in order — a book-wide one with its current formula,
    /// a built-in or sheet-local one as kept current — then names new here.
    static func _definedNamesXML(_ book: Workbook) -> String {
        var out = ""
        var seen = Set<String>()
        for n in book.fileNames {
            var text = n.text
            if n.localSheet == nil && !n.isBuiltIn {
                guard let current = book.names[n.name.uppercased()] else { continue }   // deleted
                text = current
                seen.insert(n.name.uppercased())
            }
            var attrs = " name=\"\(_esc(n.name))\""
            for (k, v) in n.attrs.sorted(by: { $0.key < $1.key }) { attrs += " \(k)=\"\(_esc(v))\"" }
            if let l = n.localSheet { attrs += " localSheetId=\"\(l)\"" }
            out += "<definedName\(attrs)>\(_esc(text))</definedName>"
        }
        for (k, v) in book.names.sorted(by: { $0.key < $1.key }) where !seen.contains(k) && !book.fileNames.contains(where: { $0.name.uppercased() == k }) {
            out += "<definedName name=\"\(_esc(book.nameSpellings[k] ?? k))\">\(_esc(v))</definedName>"
        }
        return out.isEmpty ? "" : "<definedNames>" + out + "</definedNames>"
    }

    /// The original bookViews with activeTab set.
    private static func _bookViews(_ text: String, active: Int) -> String {
        guard let start = text.findRange(of: "<workbookView") else { return text }
        let tagEnd = text[start.upperBound...].firstIndex(of: ">") ?? text.endIndex
        var tag = String(text[start.lowerBound ..< tagEnd])
        if let r = tag.findRange(of: " activeTab=\"") {
            let close = tag[r.upperBound...].firstIndex(of: "\"") ?? tag.endIndex
            tag.replaceSubrange(r.lowerBound ..< tag.index(after: close), with: " activeTab=\"\(active)\"")
        } else if tag.hasSuffix("/") {
            tag.removeLast()
            tag += " activeTab=\"\(active)\"/"
        } else {
            tag += " activeTab=\"\(active)\""
        }
        return String(text[..<start.lowerBound]) + tag + String(text[tagEnd...])
    }

    // MARK: Sheet

    /// Schema order of a worksheet's children (CT_Worksheet), so kept
    /// elements go back where Excel expects them.
    static let sheetOrder = [
        "sheetPr", "dimension", "sheetViews", "sheetFormatPr", "cols", "sheetData", "sheetCalcPr", "sheetProtection",
        "protectedRanges", "scenarios", "autoFilter", "sortState", "dataConsolidate", "customSheetViews", "mergeCells",
        "phoneticPr", "conditionalFormatting", "dataValidations", "hyperlinks", "printOptions", "pageMargins",
        "pageSetup", "headerFooter", "rowBreaks", "colBreaks", "customProperties", "cellWatches", "ignoredErrors",
        "smartTags", "drawing", "legacyDrawing", "legacyDrawingHF", "drawingHF", "picture", "oleObjects", "controls",
        "webPublishItems", "tableParts", "extLst",
    ]

    private static func _sheetXML(_ ws: Worksheet, book: Workbook, selected: Bool, extra: [String: String] = [:],
                                  dynamicCm: Int? = nil, stringIndex: (String) -> Int) -> String {
        var generated = extra
        let used = ws.usedExtent
        generated["dimension"] = "<dimension ref=\"\(ws.cells.isEmpty ? "A1" : CellRange(CellAddress(row: 0, col: 0), used).a1)\"/>"
        // Views: the selection, frozen panes, gridlines.
        var view = "<sheetViews><sheetView" + (selected ? " tabSelected=\"1\"" : "") + (ws.showGridlines ? "" : " showGridLines=\"0\"")
            + ws.viewAttrs.sorted { $0.key < $1.key }.map { " \($0.key)=\"\(_esc($0.value))\"" }.joined() + " workbookViewId=\"0\">"
        let active = ws.savedActive ?? CellAddress(row: 0, col: 0)
        if ws.freezeRows > 0 || ws.freezeCols > 0 {
            let tl = CellAddress(row: ws.freezeRows, col: ws.freezeCols).a1
            let pane = ws.freezeRows > 0 && ws.freezeCols > 0 ? "bottomRight" : (ws.freezeRows > 0 ? "bottomLeft" : "topRight")
            view += "<pane" + (ws.freezeCols > 0 ? " xSplit=\"\(ws.freezeCols)\"" : "") + (ws.freezeRows > 0 ? " ySplit=\"\(ws.freezeRows)\"" : "")
                + " topLeftCell=\"\(tl)\" activePane=\"\(pane)\" state=\"frozen\"/>"
            view += "<selection pane=\"\(pane)\" activeCell=\"\(active.a1)\" sqref=\"\(active.a1)\"/>"
        } else {
            view += "<selection activeCell=\"\(active.a1)\" sqref=\"\(active.a1)\"/>"
        }
        view += "</sheetView></sheetViews>"
        generated["sheetViews"] = view
        generated["sheetFormatPr"] = "<sheetFormatPr" + ws.formatPrAttrs.filter { $0.key != "defaultRowHeight" }.sorted { $0.key < $1.key }
            .map { " \($0.key)=\"\(_esc($0.value))\"" }.joined() + " defaultRowHeight=\"\(_num(ws.defaultRowHeightPt))\"/>"
        // Columns: segments where the width and the file's other attributes
        // (style, outline level…) are all the same.
        if !ws.colAttrRuns.isEmpty {
            var points = Set<Int>()
            for r in ws.colAttrRuns { points.insert(r.lo); points.insert(r.hi + 1) }
            for k in ws.colWidths.keys { points.insert(k); points.insert(k + 1) }
            let sorted = points.sorted()
            var cols = "<cols>"
            var pending: (lo: Int, hi: Int, key: String)? = nil
            func flush() { if let p = pending { cols += "<col min=\"\(p.lo + 1)\" max=\"\(p.hi + 1)\"\(p.key)/>" }; pending = nil }
            for (k, start) in sorted.enumerated() where k + 1 < sorted.count {
                let end = sorted[k + 1] - 1
                var attrs: [String: String] = [:]
                for r in ws.colAttrRuns where r.lo <= start && start <= r.hi { attrs.merge(r.attrs) { $1 } }
                var key = ""
                if let w = ws.colWidths[start] {
                    key += " width=\"\(_num(_widthChars(ws, start, w)))\"" + (w == 0 ? " hidden=\"1\"" : "") + " customWidth=\"1\""
                } else if !attrs.isEmpty {
                    let d = ws.defaultColWidthChars.flatMap { _charsToPoints($0) == ws.defaultColWidthPt ? $0 : nil } ?? _pointsToChars(ws.defaultColWidthPt)
                    key += " width=\"\(_num(d))\""
                }
                for (name, v) in attrs.sorted(by: { $0.key < $1.key }) { key += " \(name)=\"\(_esc(v))\"" }
                if key.isEmpty { flush(); continue }
                if let p = pending, p.key == key, p.hi + 1 == start { pending = (p.lo, end, key) } else { flush(); pending = (start, end, key) }
            }
            flush()
            generated["cols"] = cols + "</cols>"
        } else if !ws.colWidths.isEmpty {
            var cols = "<cols>"
            let keys = ws.colWidths.keys.sorted()
            var i = 0
            while i < keys.count {
                var j = i
                let w = ws.colWidths[keys[i]]!
                let chars = _widthChars(ws, keys[i], w)
                while j + 1 < keys.count, keys[j + 1] == keys[j] + 1, ws.colWidths[keys[j + 1]] == w, _widthChars(ws, keys[j + 1], w) == chars { j += 1 }
                cols += "<col min=\"\(keys[i] + 1)\" max=\"\(keys[j] + 1)\" width=\"\(_num(chars))\""
                    + (w == 0 ? " hidden=\"1\"" : "") + " customWidth=\"1\"/>"
                i = j + 1
            }
            generated["cols"] = cols + "</cols>"
        }
        // Rows and cells.
        var byRow: [Int: [(CellAddress, Cell)]] = [:]
        for (a, c) in ws.cells { byRow[a.row, default: []].append((a, c)) }
        // Spilled values are written as the cells' values, as Excel writes them.
        for (a, v) in ws.spilled {
            if let i = byRow[a.row]?.firstIndex(where: { $0.0 == a }) {
                var c = byRow[a.row]![i].1
                if c.value.isEmpty && c.formula == nil { c.value = v; byRow[a.row]![i].1 = c }
            } else {
                var c = Cell(input: "")
                c.value = v
                byRow[a.row, default: []].append((a, c))
            }
        }
        let rows = Set(byRow.keys).union(ws.rowHeights.keys).union(ws.filteredRows).union(ws.rowAttrs.keys).sorted()
        var data = "<sheetData>"
        for r in rows {
            data += "<row r=\"\(r + 1)\""
            if let h = ws.rowHeights[r] { data += h == 0 ? " hidden=\"1\"" : " ht=\"\(_num(h))\" customHeight=\"1\"" }
            if ws.filteredRows.contains(r) && ws.rowHeights[r] != 0 { data += " hidden=\"1\"" }
            for (k, v) in (ws.rowAttrs[r] ?? [:]).sorted(by: { $0.key < $1.key }) { data += " \(k)=\"\(_esc(v))\"" }
            let cells = (byRow[r] ?? []).sorted { $0.0.col < $1.0.col }
            if cells.isEmpty { data += "/>"; continue }
            data += ">"
            for (a, c) in cells { data += _cellXML(a, c, dynamicCm: dynamicCm, stringIndex: stringIndex) }
            data += "</row>"
        }
        generated["sheetData"] = data + "</sheetData>"
        if !ws.merges.isEmpty {
            generated["mergeCells"] = "<mergeCells count=\"\(ws.merges.count)\">" + ws.merges.map { "<mergeCell ref=\"\($0.a1)\"/>" }.joined() + "</mergeCells>"
        }
        if let af = ws.autoFilter { generated["autoFilter"] = af.raw ?? _autoFilterXML(af) }
        var kept: [String: [String]] = [:]
        for (name, text) in ws.keptElements { kept[name, default: []].append(text) }
        if let tab = ws.tabColor, kept["sheetPr"] == nil { generated["sheetPr"] = "<sheetPr><tabColor rgb=\"\(_esc(tab))\"/></sheetPr>" }
        var body = ""
        for name in sheetOrder {
            if let g = generated[name] { body += g }
            for t in kept[name] ?? [] where generated[name] == nil { body += t }
        }
        // Anything not in the schema list (a vendor element) goes last but before extLst.
        for (name, text) in ws.keptElements where !sheetOrder.contains(name) { body += text }
        let root = ws.rootTag ?? "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\">"
        let rootName = root.dropFirst().prefix { $0 != " " && $0 != ">" && $0 != "\n" && $0 != "\t" && $0 != "\r" }
        return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n" + root + body + "</\(rootName)>"
    }

    private static func _autoFilterXML(_ af: AutoFilter) -> String {
        guard !af.columns.isEmpty else { return "<autoFilter ref=\"\(af.range.a1)\"/>" }
        var s = "<autoFilter ref=\"\(af.range.a1)\">"
        for (col, allowed) in af.columns.sorted(by: { $0.key < $1.key }) {
            s += "<filterColumn colId=\"\(col - af.range.left)\"><filters" + (allowed.contains("") ? " blank=\"1\"" : "")
            let vals = allowed.filter { !$0.isEmpty }.sorted()
            s += vals.isEmpty ? "/>" : ">" + vals.map { "<filter val=\"\(_esc($0))\"/>" }.joined() + "</filters>"
            s += "</filterColumn>"
        }
        return s + "</autoFilter>"
    }

    /// The metadata part Excel 365 writes for dynamic arrays: one XLDAPR
    /// type, one cell-metadata entry (cm="1").
    static let _dynamicArrayMetadata = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<metadata xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:xda=\"http://schemas.microsoft.com/office/spreadsheetml/2017/dynamicarray\"><metadataTypes count=\"1\"><metadataType name=\"XLDAPR\" minSupportedVersion=\"120000\" copy=\"1\" pasteAll=\"1\" pasteValues=\"1\" merge=\"1\" splitFirst=\"1\" rowColShift=\"1\" clearFormats=\"1\" clearComments=\"1\" assign=\"1\" coerce=\"1\" cellMeta=\"1\"/></metadataTypes><futureMetadata name=\"XLDAPR\" count=\"1\"><bk><extLst><ext uri=\"{bdbb8cdc-fa1e-496e-a857-3c3f30c029c3}\"><xda:dynamicArrayProperties fDynamic=\"1\" fCollapsed=\"0\"/></ext></extLst></bk></futureMetadata><cellMetadata count=\"1\"><bk><rc t=\"1\" v=\"0\"/></bk></cellMetadata></metadata>"

    /// The cm value a file's own metadata part uses for dynamic arrays:
    /// the cellMetadata entry whose record names the XLDAPR type.
    static func _dynamicArrayCm(_ data: Data) -> Int? {
        guard let root = XNode.parse(data) else { return nil }
        guard let t = root.child("metadataTypes")?.kids("metadataType").firstIndex(where: { $0["name"] == "XLDAPR" }) else { return nil }
        for (i, bk) in (root.child("cellMetadata")?.kids("bk") ?? []).enumerated() {
            if bk.kids("rc").contains(where: { $0["t"] == "\(t + 1)" }) { return i + 1 }
        }
        return nil
    }

    private static func _cellXML(_ a: CellAddress, _ c: Cell, dynamicCm: Int? = nil, stringIndex: (String) -> Int) -> String {
        var s = "<c r=\"\(a.a1)\"" + (c.style != 0 ? " s=\"\(c.style)\"" : "")
        var attrs = c.keptAttrs
        if let cm = dynamicCm, c.dynamic, c.formula != nil, c.spillRange != nil || c.arrayRef != nil { attrs["cm"] = "\(cm)" }
        for (k, v) in attrs.sorted(by: { $0.key < $1.key }) { s += " \(k)=\"\(_esc(v))\"" }
        if c.formula == nil, let raw = c.rawFormula {
            switch c.value {
            case .text(let t): return s + " t=\"str\">\(raw)<v>\(_esc(t))</v></c>"
            case .bool(let b): return s + " t=\"b\">\(raw)<v>\(b ? 1 : 0)</v></c>"
            case .error(let e): return s + " t=\"e\">\(raw)<v>\(_esc(e.rawValue))</v></c>"
            case .number(let n): return s + ">\(raw)<v>\(_num(n))</v></c>"
            case .empty: return s + ">\(raw)</c>"
            }
        }
        if let f = c.formula {
            let text = Formula.print(_mapCalls(f) { prefixed.contains($0.uppercased()) ? "_xlfn." + $0 : $0 })
            switch c.value {
            case .text(let t): s += " t=\"str\"><f\(_arrayAttrs(c))>\(_esc(text))</f><v>\(_esc(t))</v></c>"
            case .bool(let b): s += " t=\"b\"><f\(_arrayAttrs(c))>\(_esc(text))</f><v>\(b ? 1 : 0)</v></c>"
            case .error(let e): s += " t=\"e\"><f\(_arrayAttrs(c))>\(_esc(text))</f><v>\(_esc(e.rawValue))</v></c>"
            case .number(let n): s += "><f\(_arrayAttrs(c))>\(_esc(text))</f><v>\(_num(n))</v></c>"
            case .empty: s += "><f\(_arrayAttrs(c))>\(_esc(text))</f></c>"
            }
            return s
        }
        switch c.value {
        case .empty:
            // A formula we could not parse is kept as typed.
            if c.input.hasPrefix("=") && c.input.count > 1 { return s + "><f>\(_esc(String(c.input.dropFirst())))</f></c>" }
            return s + "/>"
        case .number(let n): return s + "><v>\(_num(n))</v></c>"
        case .text(let t):
            if c.input.hasPrefix("=") && c.input.count > 1 {
                return s + " t=\"str\"><f>\(_esc(String(c.input.dropFirst())))</f><v>\(_esc(t))</v></c>"
            }
            return s + " t=\"s\"><v>\(stringIndex(t))</v></c>"
        case .bool(let b): return s + " t=\"b\"><v>\(b ? 1 : 0)</v></c>"
        case .error(let e): return s + " t=\"e\"><v>\(_esc(e.rawValue))</v></c>"
        }
    }

    private static func _arrayAttrs(_ c: Cell) -> String {
        // A spill is written as an array formula over its range: every Excel
        // shows its values there.
        (c.spillRange?.a1 ?? c.arrayRef).map { " t=\"array\" ref=\"\(_esc($0))\"" } ?? ""
    }

    /// A number as Excel writes it: shortest round-trip, no trailing .0.
    static func _num(_ n: Double) -> String {
        if n == n.rounded(), abs(n) < 1e15 { return String(Int64(n)) }
        return "\(n)"
    }

    private static func _sstXML(_ sst: [String]) -> String {
        var s = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<sst xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" count=\"\(sst.count)\" uniqueCount=\"\(sst.count)\">"
        for t in sst {
            let space = t.first == " " || t.last == " " || t.contains("\n") ? " xml:space=\"preserve\"" : ""
            s += "<si><t\(space)>\(_esc(t))</t></si>"
        }
        return s + "</sst>"
    }

    /// The pieces of a styles.xml to write back as they were.
    static func _styleSource(_ data: Data) -> StyleSource {
        var src = StyleSource()
        let split = RawXML.split([UInt8](data))
        func kids(_ name: String) -> [(name: String, text: String)] {
            guard let t = split.children.first(where: { $0.name == name })?.text else { return [] }
            let inner = RawXML.split([UInt8](t.utf8))
            src.tags[name] = inner.rootStart.hasSuffix("/>") ? String(inner.rootStart.dropLast(2)) + ">" : inner.rootStart
            return inner.children
        }
        for k in kids("numFmts") where k.name == "numFmt" {
            if let n = XNode.parse(Data(k.text.utf8)), let id = Int(n["numFmtId"] ?? ""), let code = n["formatCode"] { src.numFmts.append((id, code, k.text)) }
        }
        src.fonts = kids("fonts").filter { $0.name == "font" }.map(\.text)
        src.fills = kids("fills").filter { $0.name == "fill" }.map(\.text)
        src.borders = kids("borders").filter { $0.name == "border" }.map(\.text)
        src.cellStyleXfs = split.children.first { $0.name == "cellStyleXfs" }?.text
        src.cellStyles = split.children.first { $0.name == "cellStyles" }?.text
        for k in kids("cellXfs") where k.name == "xf" {
            guard let n = XNode.parse(Data(k.text.utf8)) else { src.xfs.append(StyleSource.Xf(attrs: [:], extra: "", raw: k.text)); continue }
            let inner = RawXML.split([UInt8](k.text.utf8)).children
            src.xfs.append(StyleSource.Xf(attrs: n.attrs,
                                          alignment: inner.first { $0.name == "alignment" }?.text,
                                          protection: inner.first { $0.name == "protection" }?.text,
                                          extra: inner.filter { $0.name != "alignment" && $0.name != "protection" }.map(\.text).joined(),
                                          raw: k.text))
        }
        return src
    }

    private static func _stylesXML(_ book: Workbook) -> String {
        let reverseBuiltin = Dictionary(builtinFormats.map { ($0.value, $0.key) }, uniquingKeysWith: { min($0, $1) })
        var custom: [String: Int] = [:]
        var fonts: [String] = [], fills: [String] = [], borders: [String] = []
        func index(_ list: inout [String], _ item: String) -> Int {
            if let i = list.firstIndex(of: item) { return i }
            list.append(item); return list.count - 1
        }
        let src = book.styleSource
        if let src, !src.fonts.isEmpty {
            // The file's own, first and as written: its formats point at them.
            fonts = src.fonts; fills = src.fills; borders = src.borders
            for f in src.numFmts { custom[f.code] = f.id }
        } else {
            // The default font first, and Excel's two required fills.
            _ = index(&fonts, "<font><sz val=\"11\"/><color theme=\"1\"/><name val=\"Calibri\"/><family val=\"2\"/><scheme val=\"minor\"/></font>")
            _ = index(&fills, "<fill><patternFill patternType=\"none\"/></fill>")
            _ = index(&fills, "<fill><patternFill patternType=\"gray125\"/></fill>")
            _ = index(&borders, "<border><left/><right/><top/><bottom/><diagonal/></border>")
        }
        let fileCustom = Set(custom.values)
        var nextFmt = max(163, custom.values.max() ?? 163) + 1
        var xfs: [String] = []
        for (i, st) in book.styles.enumerated() {
            // A format the file had, unchanged: exactly as it was.
            if let src, i < src.xfs.count, st.baseXf == i {
                xfs.append(src.xfs[i].raw)
                continue
            }
            // One made here: from the format it was derived from, every part the
            // change did not touch is kept as the file had it.
            let base: (style: CellStyle, xf: StyleSource.Xf)? = st.baseXf.flatMap { b in
                guard let src, b < src.xfs.count, b < book.styles.count else { return nil }
                return (book.styles[b], src.xfs[b])
            }
            var font = "<font>"
            if st.bold { font += "<b/>" }
            if st.italic { font += "<i/>" }
            if st.strike { font += "<strike/>" }
            if st.underline { font += "<u/>" }
            font += "<sz val=\"\(_num(st.fontSize ?? 11))\"/>"
            font += st.color.map { "<color rgb=\"FF\(_hex($0))\"/>" } ?? "<color theme=\"1\"/>"
            font += "<name val=\"\(_esc(st.fontName ?? "Calibri"))\"/><family val=\"2\"/>"
            if st.fontName == nil { font += "<scheme val=\"minor\"/>" }
            font += "</font>"
            func same(_ a: CellStyle, _ b: CellStyle, _ keys: [PartialKeyPath<CellStyle>]) -> Bool {
                keys.allSatisfy { k in String(describing: a[keyPath: k]) == String(describing: b[keyPath: k]) }
            }
            let fontKeys: [PartialKeyPath<CellStyle>] = [\.bold, \.italic, \.underline, \.strike, \.fontName, \.fontSize, \.color]
            var fontId = 0, fillId = 0, borderId = 0
            if let base, same(st, base.style, fontKeys), let f = Int(base.xf.attrs["fontId"] ?? "0") { fontId = f }
            else { fontId = index(&fonts, font) }
            if let base, st.fill == base.style.fill, let f = Int(base.xf.attrs["fillId"] ?? "0") { fillId = f }
            else { fillId = st.fill.map { index(&fills, "<fill><patternFill patternType=\"solid\"><fgColor rgb=\"FF\(_hex($0))\"/><bgColor indexed=\"64\"/></patternFill></fill>") } ?? 0 }
            let b = st.borders
            func side(_ name: String, _ on: Bool) -> String {
                guard on else { return "<\(name)/>" }
                let color = b.colors[name].map { "<color rgb=\"FF\(_hex($0))\"/>" } ?? "<color indexed=\"64\"/>"
                return "<\(name) style=\"\(b.kinds[name] ?? "thin")\">\(color)</\(name)>"
            }
            if let base, st.borders == base.style.borders, let f = Int(base.xf.attrs["borderId"] ?? "0") { borderId = f }
            else { borderId = index(&borders, "<border>" + side("left", b.left) + side("right", b.right) + side("top", b.top) + side("bottom", b.bottom) + "<diagonal/></border>") }
            var fmtId = reverseBuiltin[st.numberFormat] ?? -1
            if let base, st.numberFormat == base.style.numberFormat, let f = Int(base.xf.attrs["numFmtId"] ?? "") { fmtId = f }
            if fmtId < 0 {
                if let c = custom[st.numberFormat] { fmtId = c } else { fmtId = nextFmt; nextFmt += 1; custom[st.numberFormat] = fmtId }
            }
            let xfId = base?.xf.attrs["xfId"] ?? "0"
            var xf = "<xf numFmtId=\"\(fmtId)\" fontId=\"\(fontId)\" fillId=\"\(fillId)\" borderId=\"\(borderId)\" xfId=\"\(xfId)\""
            if fmtId != 0 { xf += " applyNumberFormat=\"1\"" }
            if fontId != 0 { xf += " applyFont=\"1\"" }
            if fillId != 0 { xf += " applyFill=\"1\"" }
            if borderId != 0 { xf += " applyBorder=\"1\"" }
            var align = ""
            switch st.hAlign { case .left: align += " horizontal=\"left\""; case .center: align += " horizontal=\"center\""; case .right: align += " horizontal=\"right\""; case .general: break }
            switch st.vAlign { case .top: align += " vertical=\"top\""; case .center: align += " vertical=\"center\""; case .bottom: break }
            if st.wrap { align += " wrapText=\"1\"" }
            // Alignment the change left alone keeps its indent, rotation…
            var alignment = align.isEmpty ? "" : "<alignment\(align)/>"
            if let base, st.hAlign == base.style.hAlign, st.vAlign == base.style.vAlign, st.wrap == base.style.wrap {
                alignment = base.xf.alignment ?? ""
            }
            let inner = alignment + (base?.xf.protection ?? "")
            xf += inner.isEmpty ? "/>" : (alignment.isEmpty ? "" : " applyAlignment=\"1\"") + ">" + inner + "</xf>"
            xfs.append(xf)
        }
        var s = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
            + (book.keptStyleParts["root"].flatMap { $0.hasPrefix("<styleSheet") ? $0 : nil }
               ?? "<styleSheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">")
        /// The file's start tag for a list, its count brought up to date.
        func open(_ name: String, _ count: Int) -> String {
            guard var tag = src?.tags[name] else { return "<\(name) count=\"\(count)\">" }
            if let r = tag.findRange(of: " count=\""), let q = tag.findRange(of: "\"", in: r.upperBound ..< tag.endIndex) {
                tag.replaceSubrange(r.upperBound ..< q.lowerBound, with: "\(count)")
            } else {
                tag.insert(contentsOf: " count=\"\(count)\"", at: tag.index(before: tag.endIndex))
            }
            return tag
        }
        if !custom.isEmpty {
            s += open("numFmts", custom.count)
            for f in src?.numFmts ?? [] { s += f.raw }
            for (code, id) in custom.sorted(by: { $0.value < $1.value }) where !fileCustom.contains(id) {
                s += "<numFmt numFmtId=\"\(id)\" formatCode=\"\(_esc(code))\"/>"
            }
            s += "</numFmts>"
        }
        s += open("fonts", fonts.count) + fonts.joined() + "</fonts>"
        s += open("fills", fills.count) + fills.joined() + "</fills>"
        s += open("borders", borders.count) + borders.joined() + "</borders>"
        s += src?.cellStyleXfs ?? "<cellStyleXfs count=\"1\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\"/></cellStyleXfs>"
        s += open("cellXfs", xfs.count) + xfs.joined() + "</cellXfs>"
        s += src?.cellStyles ?? "<cellStyles count=\"1\"><cellStyle name=\"Normal\" xfId=\"0\" builtinId=\"0\"/></cellStyles>"
        // The file's own differential formats, table styles, palette and
        // extensions, in schema order (conditional formats point at dxfs by index).
        s += book.keptStyleParts["dxfs"] ?? "<dxfs count=\"0\"/>"
        s += book.keptStyleParts["tableStyles"] ?? "<tableStyles count=\"0\" defaultTableStyle=\"TableStyleMedium2\" defaultPivotStyle=\"PivotStyleLight16\"/>"
        s += book.keptStyleParts["colors"] ?? ""
        s += book.keptStyleParts["extLst"] ?? ""
        return s + "</styleSheet>"
    }

    private static func _hex(_ v: UInt32) -> String {
        let digits = Array("0123456789ABCDEF")
        var out = ""
        for shift in stride(from: 20, through: 0, by: -4) { out.append(digits[Int((v >> UInt32(shift)) & 0xF)]) }
        return out
    }

    static func _esc(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            default: out.append(ch)
            }
        }
        return out
    }
}

/// A shallow, exact split of an XML document: the root's start tag as
/// written (namespaces included) and each top-level child's original
/// text. Used to keep what the model does not read byte for byte.
enum RawXML {
    struct Split {
        var rootStart: String
        var rootName: String
        var children: [(name: String, text: String)]
    }

    static func split(_ b: [UInt8]) -> Split {
        var i = 0
        let n = b.count
        func skipMisc() {
            while i < n {
                if b[i] == 0x3C, i + 1 < n, b[i + 1] == 0x3F { // <?
                    while i + 1 < n, !(b[i] == 0x3F && b[i + 1] == 0x3E) { i += 1 }
                    i += 2
                } else if b[i] == 0x3C, i + 3 < n, b[i + 1] == 0x21, b[i + 2] == 0x2D { // <!--
                    while i + 2 < n, !(b[i] == 0x2D && b[i + 1] == 0x2D && b[i + 2] == 0x3E) { i += 1 }
                    i += 3
                } else if b[i] == 0x3C { return } else { i += 1 }
            }
        }
        func tagEnd(_ from: Int) -> Int {
            var j = from, quote: UInt8 = 0
            while j < n {
                if quote != 0 { if b[j] == quote { quote = 0 } }
                else if b[j] == 0x22 || b[j] == 0x27 { quote = b[j] }
                else if b[j] == 0x3E { return j }
                j += 1
            }
            return n - 1
        }
        func name(at j: Int) -> String {
            var k = j
            while k < n, ![0x20, 0x09, 0x0A, 0x0D, 0x3E, 0x2F].contains(b[k]) { k += 1 }
            return String(decoding: b[j ..< k], as: UTF8.self)
        }
        skipMisc()
        let rootStartAt = i
        let rootEnd = tagEnd(i)
        let rootName = name(at: i + 1)
        let rootStart = String(decoding: b[rootStartAt ... rootEnd], as: UTF8.self)
        i = rootEnd + 1
        var children: [(String, String)] = []
        while i < n {
            // Find the next top-level element.
            while i < n, b[i] != 0x3C { i += 1 }
            guard i + 1 < n else { break }
            if b[i + 1] == 0x2F { break }                         // </root>
            if b[i + 1] == 0x21 || b[i + 1] == 0x3F { skipMisc(); continue }
            let start = i
            let full = name(at: i + 1)
            let local = full.split(separator: ":").last.map(String.init) ?? full
            var depth = 0
            var j = i
            while j < n {
                guard b[j] == 0x3C else { j += 1; continue }
                if j + 3 < n, b[j + 1] == 0x21, b[j + 2] == 0x2D { // comment
                    while j + 2 < n, !(b[j] == 0x2D && b[j + 1] == 0x2D && b[j + 2] == 0x3E) { j += 1 }
                    j += 3; continue
                }
                if j + 8 < n, b[j + 1] == 0x21, b[j + 2] == 0x5B { // <![CDATA[
                    while j + 2 < n, !(b[j] == 0x5D && b[j + 1] == 0x5D && b[j + 2] == 0x3E) { j += 1 }
                    j += 3; continue
                }
                let e = tagEnd(j)
                if b[j + 1] == 0x2F { depth -= 1 }
                else if b[e - 1] != 0x2F { depth += 1 }
                j = e + 1
                if depth == 0 { break }
            }
            children.append((local, String(decoding: b[start ..< j], as: UTF8.self)))
            i = j
        }
        return Split(rootStart: rootStart, rootName: rootName, children: children)
    }
}

extension XNode {
    /// A child by local name, whatever prefix the file used (x:c or c).
    func child(_ local: String) -> XNode? {
        children.first { $0.name == local || $0.name.hasSuffix(":" + local) }
    }

    func kids(_ local: String) -> [XNode] {
        children.filter { $0.name == local || $0.name.hasSuffix(":" + local) }
    }
}
