import OfficeText
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
        try read(entries: try Zip.read(data))
    }

    /// The same reader over parts already unpacked (a zip's entries, or parts
    /// the .xls reader built from BIFF records).
    static func read(entries zipEntries: [ZipEntry]) throws -> Workbook {
        let entries = zipEntries.map { e -> ZipEntry in
            var d = _unprefixMain(e.data)
            // Style tables are read by position; a font or xf wrapped in
            // mc:AlternateContent (Hancom's HCell) would otherwise vanish and
            // shift every index after it.
            if e.name.lowercased().hasSuffix("styles.xml") { d = _resolveAlternateContent(d) }
            // (A part named with backslashes and in lower case —
            // "xl\worksheets\sheet1.xml", 49609's — is the part all the
            // same: Excel opens it.)
            return ZipEntry(name: e.name.replacingAll("\\", with: "/"), data: d)
        }
        var parts: [String: Data] = [:]
        for e in entries { parts[e.name] = e.data }
        func xml(_ name: String) -> XNode? { _part(parts, name).flatMap { XNode.parse($0) } }

        guard let wbNode = xml("xl/workbook.xml") else { throw ReadError.notAWorkbook }
        let wbRels = _rels(_part(parts, "xl/_rels/workbook.xml.rels"), base: "xl/")
        let book = Workbook(sheets: [])
        book.package = entries
        if let p = wbNode.child("workbookProtection") { book.workbookProtection = p.attrs }
        if let pr = wbNode.child("workbookPr") { book.date1904 = pr["date1904"] == "1" || pr["date1904"] == "true" }
        if let cp = wbNode.child("calcPr") {
            book.iterate = cp["iterate"] == "1" || cp["iterate"] == "true"
            if let n = cp["iterateCount"].flatMap(Int.init) { book.iterateCount = n }
            if let d = cp["iterateDelta"].flatMap(Double.init) { book.iterateDelta = d }
        }

        // Theme colours, for fills and fonts that name a slot.
        let themeNode = xml("xl/theme/theme1.xml")
        let theme = _themeColors(themeNode)
        book.themeColors = theme
        let themeFonts = _themeFonts(themeNode)
        let themeless = themeNode == nil
        // Shared strings.
        var sst: [String] = []
        var sstScripts: Set<Int> = []
        var sstRuns: [Int: [RichRun]] = [:]
        var sstRaw: [Int: String] = [:]
        if let s = xml("xl/sharedStrings.xml") {
            for si in s.kids("si") {
                // (Rich text with a raised or lowered run: its row's fit is Excel's own.)
                if si.kids("r").contains(where: { ["superscript", "subscript"].contains($0.child("rPr")?.child("vertAlign")?["val"] ?? "") }) {
                    sstScripts.insert(sst.count)
                }
                let runs = si.kids("r")
                if runs.count > 1, runs.contains(where: { $0.child("rPr") != nil }) {
                    sstRuns[sst.count] = runs.map { _richRun($0, theme: theme, themeFonts: themeFonts, themeless: themeless) }
                }
                // (A rich string is kept as the file wrote it, run properties, phonetic guides and all, for a save that leaves its cell's text alone.)
                if !si.kids("r").isEmpty || si.child("rPh") != nil, let raw = _siXML(si) { sstRaw[sst.count] = raw }
                sst.append(_text(si))
            }
        }
        // Styles: one CellStyle per cellXfs entry, in order, so a cell's
        // `s` is its index in the book's table.
        if let st = xml("xl/styles.xml") {
            book.styles = _styles(st, theme: theme, themeFonts: themeFonts, themeless: themeless)
            // The default font: the one a cell with no style of its own has.
            if let f = _defaultFont(st) {
                if let n = _fontName(f, themeFonts, themeless: themeless), !n.isEmpty, n != OfficeFonts.defaultFamily { book.defaultFontName = n }
                // (A Normal font named for a face of its own but set in the theme's: its name is the face Excel fitted the rows in.)
                if f.child("scheme")?["val"] != nil, let named = f.child("name")?["val"], !named.isEmpty, named != book.defaultFontName ?? OfficeFonts.defaultFamily, SheetPrintMetrics.fitsRowsInOwnFace(named) { book.defaultFontOwnName = named }
                book.defaultFontBold = f.child("b").map { $0["val"] != "0" && $0["val"] != "false" } ?? false
                if let z = f.child("sz").flatMap({ Double($0["val"] ?? "") }), z > 0, z != 11 { book.defaultFontSize = z }
            }
            for i in book.styles.indices { book.styles[i].baseXf = i }
            book.styleSource = _part(parts, "xl/styles.xml").map(_styleSource)
            if book.styles.isEmpty { book.styles = [.plain] }
            book.dxfs = (st.child("dxfs")?.kids("dxf") ?? []).map { _dxf($0, theme: theme) }
            for ts in st.child("tableStyles")?.kids("tableStyle") ?? [] {
                guard let name = ts["name"] else { continue }
                var parts: [String: Int] = [:]
                for e in ts.kids("tableStyleElement") {
                    if let type = e["type"], let d = e["dxfId"].flatMap(Int.init) { parts[type] = d }
                }
                book.tableStyles[name] = parts
            }
        }
        // (No font at all and no theme — 47889's empty styleSheet, 56278
        // with no styles part — prints in Calibri 11, rows at 14.52, in the
        // 200% Excel prints (build 20527); the older prints showed Aptos
        // Narrow 15.24 for these books.)
        if let raw = _part(parts, "xl/styles.xml") {
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
        // Each sheet's part as it was parsed, without its cells: what the
        // readers of its drawings, objects and tables look through. They
        // parsed the part again, each of them — an 18 MB sheet four times.
        var sheetRoots: [String: XNode] = [:]
        for s in wbNode.child("sheets")?.kids("sheet") ?? [] {
            // (The relationships namespace under any prefix: 49609 writes
            // d3p1:id.)
            let rid = s["r:id"] ?? s.attrs.first { $0.key.hasSuffix(":id") }?.value
            guard let name = s["name"], let rid, let path = wbRels[rid] else { continue }
            let ws = Worksheet(name: name)
            ws.origin = path
            ws.sheetId = Int(s["sheetId"] ?? "")
            if let raw = _part(parts, path) { sheetRoots[path] = try _readSheet(raw, into: ws, sst: sst, sstScripts: sstScripts, sstRuns: sstRuns, sstRaw: sstRaw, book: book) }
            if s["state"] == "hidden" || s["state"] == "veryHidden" { ws.hidden = true }
            if s["state"] == "veryHidden" { ws.veryHidden = true }
            book.sheets.append(ws)
        }
        // Pictures and charts, drawn from the file's own parts.
        let themeRoot = xml("xl/theme/theme1.xml")
        if themeRoot != nil { book.chartTheme = DeckTheme(xlsxTheme: themeRoot) }
        let colors = ColorContext(theme: PptxTheme(themeRoot))
        for ws in book.sheets {
            if let path = ws.origin {
                (ws.drawings, ws.drawingPart, ws.drawingRoot) = SheetDrawingsXML.read(sheetPath: path, parts: parts, colors: colors, sheet: sheetRoots[path])
                ws.objects = SheetObjectsXML.read(sheetPath: path, parts: parts, sheet: sheetRoots[path])
                ws.headerPictures = SheetDrawingsXML.readHeaderPictures(sheetPath: path, parts: parts, sheet: sheetRoots[path])
                // (A legacy shape placed in points, not cells, held to the
                // cells under it, so that it prints where they print.)
                for i in ws.objects.indices {
                    if case .absolute(let x, let y, let w, let h) = ws.objects[i].anchor {
                        ws.objects[i].anchor = ws.anchor(x: x, y: y, width: w, height: h)
                    }
                }
                ws.tables = TablesXML.read(sheetPath: path, parts: parts, sheet: sheetRoots[path])
                ws.pivots = PivotsXML.read(sheetPath: path, parts: parts)
                // (Excel refills an empty header cell as it opens the file,
                // and prints the name: lo-TableEmptyHeaders' "Column1",
                // "Column2".)
                _fillTableHeaders(ws)
                (ws.notes, ws.noteParts) = NotesXML.read(sheetPath: path, parts: parts)
                for r in _relList(_part(parts, _relsPath(path))) where r.type.hasSuffix("/hyperlink") { ws.linkTargets[r.id] = r.target }
            }
        }
        if book.sheets.isEmpty { book.sheets = [Worksheet(name: "Sheet1")] }
        book.activeTab = min(max(0, activeTab), book.sheets.count - 1)
        // One selected tab is just the open sheet; several are a group, as Excel opens it.
        if book.sheets.filter(\.tabSelected).count < 2 || !book.sheets[book.activeTab].tabSelected {
            for ws in book.sheets { ws.tabSelected = false }
        }

        // The values saved from linked workbooks, in the order [1], [2]... name them.
        for ref in wbNode.child("externalReferences")?.kids("externalReference") ?? [] {
            var ext = ExternalBook()
            if let rid = ref["id"] ?? ref.attrs.first(where: { $0.key.hasSuffix(":id") })?.value,
               let path = wbRels[rid] {
                let relPath = path.replacingAll("externalLinks/", with: "externalLinks/_rels/") + ".rels"
                if let rels = _part(parts, relPath).flatMap({ XNode.parse($0) }),
                   let t = rels.kids("Relationship").first?["Target"] {
                    ext.file = String(t.split(separator: "/").last ?? "")
                }
                if let root = xml(path), let eb = root.child("externalBook") {
                    ext.sheetNames = (eb.child("sheetNames")?.kids("sheetName") ?? []).map { $0["val"] ?? "" }
                    for n in eb.child("definedNames")?.kids("definedName") ?? [] {
                        if let name = n["name"], let to = n["refersTo"] { ext.names[name.uppercased()] = to }
                    }
                    for sd in eb.child("sheetDataSet")?.kids("sheetData") ?? [] {
                        let si = Int(sd["sheetId"] ?? "") ?? 0
                        for row in sd.kids("row") {
                            for c in row.kids("cell") {
                                guard let a = c["r"].flatMap({ CellAddress($0) }) else { continue }
                                let v = c.child("v")?.text
                                let value: CellValue
                                switch c["t"] ?? "n" {
                                case "str", "s": value = .text(v ?? "")
                                case "b": value = .bool(v == "1")
                                case "e": value = .error(ExcelError(rawValue: v ?? "") ?? .value)
                                default: value = v.flatMap { Double($0) }.map { .number($0) } ?? .empty
                                }
                                ext.cells[si, default: [:]][a] = value
                            }
                        }
                    }
                }
            }
            book.externals.append(ext)
        }

        // Defined names (print areas and other built-ins are not formulas to
        // evaluate). A sheet's own name is read from `fileNames` by that
        // sheet; the book's table has it only where the book has none.
        var bookWide = Set<String>()
        for n in wbNode.child("definedNames")?.kids("definedName") ?? [] {
            guard let name = n["name"] else { continue }
            var attrs = n.attrs
            attrs["name"] = nil
            let local = attrs.removeValue(forKey: "localSheetId").flatMap { Int($0) }
            book.fileNames.append(DefinedName(name: name, localSheet: local, attrs: attrs, text: n.text))
            guard !name.hasPrefix("_xlnm.") else { continue }
            let key = name.uppercased()
            if local == nil { bookWide.insert(key) } else if bookWide.contains(key) { continue }
            book.names[key] = n.text
            book.nameSpellings[key] = name
        }
        return book
    }

    /// `<autoFilter ref><filterColumn colId><filters blank><filter val/>…`.
    /// Value lists are modelled; any other kind of column filter (custom,
    /// top 10, dynamic, colour, date groups) or a sort state keeps the
    /// whole element as written, until the filter is changed here.
    private static func _readAutoFilter(_ node: XNode, range: CellRange, raw: String?, book: Workbook) -> AutoFilter {
        var af = AutoFilter(range: range)
        var modelled = node.kids("sortState").isEmpty
        for fc in node.kids("filterColumn") {
            guard let id = Int(fc["colId"] ?? ""), fc.children.count == 1, let body = fc.children.first else { modelled = false; continue }
            let col = range.left + id
            switch body.name {
            case "filters":
                guard fc.kids("filters").count == 1, body.kids("dateGroupItem").isEmpty else { modelled = false; continue }
                var allowed = Set(body.kids("filter").compactMap { $0["val"] })
                if body["blank"] == "1" { allowed.insert("") }
                af.columns[col] = allowed
            case "customFilters":
                let cs = body.kids("customFilter").map { FilterCondition(op: $0["operator"] ?? "equal", value: $0["val"] ?? "") }
                guard (1 ... 2).contains(cs.count) else { modelled = false; continue }
                af.rules[col] = .compare(cs[0], and: body["and"] == "1", cs.count > 1 ? cs[1] : nil)
            case "top10":
                guard let n = Int(body["val"] ?? ""), n >= 1 else { modelled = false; continue }
                af.rules[col] = .top(top: body["top"] != "0", percent: body["percent"] == "1", count: n)
            case "dynamicFilter":
                let t = body["type"] ?? ""
                if t == "aboveAverage" || t == "belowAverage" { af.rules[col] = .average(above: t == "aboveAverage") }
                else if FilterRule.periods.contains(t) { af.rules[col] = .period(t) }
                else { modelled = false }
            case "colorFilter":
                let fill = body["cellColor"] != "0"
                guard let i = Int(body["dxfId"] ?? ""), i >= 0, i < book.dxfs.count,
                      let rgb = fill ? book.dxfs[i].fill : book.dxfs[i].color else { modelled = false; continue }
                af.rules[col] = .color(fill: fill, rgb & 0xFFFFFF)
            default: modelled = false
            }
        }
        if !modelled { af.raw = raw }
        return af
    }

    /// OFFICE_XLSX_SCAN=0 reads every sheet row as a tree again (A/B switch).
    nonisolated(unsafe) static var scanCells = ProcessInfo.processInfo.environment["OFFICE_XLSX_SCAN"] != "0"

    /// Returns the part's root with `sheetData` left out (see `sheetRoots`).
    @discardableResult
    private static func _readSheet(_ raw: Data, into ws: Worksheet, sst: [String], sstScripts: Set<Int> = [], sstRuns: [Int: [RichRun]] = [:], sstRaw: [Int: String] = [:],
                                   book: Workbook) throws -> XNode {
        let bytes = [UInt8](raw)
        // The elements we do not model, kept as their original text.
        let split = RawXML.split(bytes)
        ws.rootTag = split.rootStart
        let modeled: Set<String> = ["dimension", "sheetViews", "sheetFormatPr", "cols", "sheetData", "mergeCells", "autoFilter"]
        for (name, text) in split.children where !modeled.contains(name) {
            ws.keptElements.append((name, text))
        }
        // The rows are not in this tree: they are read as they go by, below.
        guard let part = XNode.parse(raw, listUnder: "sheetData", of: "row") else { throw ReadError.badPart(ws.origin ?? ws.name) }
        let root = part.root
        if let node = root.child("autoFilter"), let ref = node["ref"], let range = CellRange(ref) {
            ws.autoFilter = _readAutoFilter(node, range: range, raw: split.children.first { $0.name == "autoFilter" }?.text, book: book)
        }

        if let pr = root.child("sheetPr"), let tab = pr.child("tabColor")?["rgb"] { ws.tabColor = tab }
        // Frozen panes and the selection.
        ws.hasView = root.child("sheetViews")?.child("sheetView") != nil
        if let view = root.child("sheetViews")?.kids("sheetView").first {
            if let pane = view.child("pane"), pane["state"] == "frozen" || pane["state"] == "frozenSplit" {
                ws.freezeCols = Int(Double(pane["xSplit"] ?? "0") ?? 0)
                ws.freezeRows = Int(Double(pane["ySplit"] ?? "0") ?? 0)
            } else if let pane = view.child("pane") {
                // A split: the divider is a position, not a cell count, so it is kept as the file wrote it.
                ws.splitPane = pane.attrs
            }
            // Every selection as the file wrote it (a pane each, activeCellId, ranges), for the save to hand back.
            ws.splitSelections = view.kids("selection").map(\.attrs)
            ws.selectionFreeze = ws.freezeRows > 0 || ws.freezeCols > 0 ? (ws.freezeRows > 0 ? 1 : 0) + (ws.freezeCols > 0 ? 2 : 0) : 0
            if let sel = view.kids("selection").last, let a = sel["activeCell"].flatMap({ CellAddress($0) }) { ws.savedActive = a }
            if view["showGridLines"] == "0" || view["showGridLines"] == "false" { ws.showGridlines = false }
            ws.tabSelected = view["tabSelected"] == "1"
            ws.viewAttrs = view.attrs.filter { !["tabSelected", "showGridLines", "workbookViewId"].contains($0.key) }
        }
        // Column widths are in characters of the default font's widest
        // digit (7 px for Calibri 11) plus 5 px of padding. A sheet's own
        // default is `defaultColWidth` in those characters, or else
        // `baseColWidth` (8) digits and the padding, taken up to a multiple
        // of 8 px: 64 px for Calibri 11, 72 for a face whose digit is 8.
        let digit = book.digitWidth
        ws.digitWidth = digit
        let format = root.child("sheetFormatPr")
        if let f = format {
            if let h = Double(f["defaultRowHeight"] ?? "") { ws.defaultRowHeightPt = h }
            ws.customDefaultRowHeight = f["customHeight"] == "1" || f["customHeight"] == "true"
            ws.formatPrAttrs = f.attrs.filter { $0.key != "defaultRowHeight" }
        }
        if let w = Double(format?["defaultColWidth"] ?? ""), w > 0 {
            ws.defaultColWidthPt = _charsToPoints(w, digit: digit)
            ws.defaultColWidthChars = w
        } else {
            let base = Double(format?["baseColWidth"] ?? "") ?? 8
            ws.defaultColWidthPt = ((base * digit + 5) / 8).rounded(.up) * 8 * 0.75
        }
        for col in root.child("cols")?.kids("col") ?? [] {
            guard let lo = Int(col["min"] ?? ""), let hi = Int(col["max"] ?? "") else { continue }
            let extra = col.attrs.filter { !["min", "max", "width", "customWidth", "hidden"].contains($0.key) }
            if !extra.isEmpty { ws.colAttrRuns.append((lo - 1, min(hi, CellAddress.maxCols) - 1, extra)) }
            // Hidden columns keep their widths, for when they are shown again.
            let hidden = col["hidden"] == "1" || col["hidden"] == "true"
            if hidden, hi - lo <= 2000 {
                for c in lo ... hi where c >= 1 && c <= CellAddress.maxCols { ws.hiddenCols.insert(c - 1) }
            } else if hidden, lo >= 1, lo <= hi {
                ws.hiddenColRuns.append((lo - 1) ... (min(hi, CellAddress.maxCols) - 1))
                if let w = Double(col["width"] ?? ""), w > 0 { ws.hiddenRunChars[lo - 1] = w }
            }
            guard let w = Double(col["width"] ?? "") else { continue }
            let pt = w == 0 ? 0 : _charsToPoints(w, digit: digit)
            // A run over the whole sheet (a default width) is not 16k entries.
            if hi - lo > 2000 { if !hidden && w > 0 { ws.defaultColWidthPt = pt; ws.defaultColWidthChars = w }; continue }
            // (Every width the file states is kept, the default's own too:
            // on paper a width is its characters, and 11.43 of them is the
            // 80 px default of a baseColWidth 10 at 96 dpi but prints 64.3
            // pt where the default prints 60.2 — lo-forum-mso-de-104083's
            // column D, all to its right 3.9 pt left of Excel's.)
            for c in lo ... hi where c >= 1 && c <= CellAddress.maxCols {
                ws.colWidths[c - 1] = pt; if w > 0 { ws.colWidthChars[c - 1] = w }
            }
        }
        // Cells.
        var shared: [String: (CellAddress, FormulaExpr)] = [:]
        var spillAreas: [(CellAddress, CellRange)] = []
        var cells: [CellAddress: Cell] = [:]
        var rowIndex = 0
        // Room for every cell at once: a dictionary grown a cell at a time
        // is rehashed a dozen times over on its way to a million. (Counted
        // in the bytes — "<c " and "<c>" — which is near enough.)
        var cellTags = 0
        var k = 0
        while k + 2 < bytes.count {
            if bytes[k] == UInt8(ascii: "<"), bytes[k + 1] == UInt8(ascii: "c"),
               bytes[k + 2] == UInt8(ascii: " ") || bytes[k + 2] == UInt8(ascii: ">") { cellTags += 1; k += 3 } else { k += 1 }
        }
        cells.reserveCapacity(cellTags)
        var rowsSeen: Set<Int> = []
        var spanText: [Int: String] = [:]
        func rowSetup(_ row: XNode) {
            rowIndex = Int(row["r"] ?? "").map { $0 - 1 } ?? rowIndex
            var rowExtra = row.attrs.filter { !["r", "ht", "customHeight", "hidden", "spans"].contains($0.key) }
            if let sp = row["spans"] { spanText[rowIndex] = sp }
            if !rowExtra.isEmpty { ws.rowAttrs[rowIndex] = rowExtra }
            if ["1", "true"].contains(row["customFormat"] ?? ""), let span = row["spans"],
               let end = span.split(separator: ":").last.flatMap({ Int($0) }), end > 0, end <= 1024 {
                // (Every <c> counts, the bare ones the model does not keep.)
                var at = 0
                let present = Set(row.kids("c").map { c -> Int in
                    let col = c["r"].flatMap { CellAddress($0)?.col } ?? at
                    at = col + 1
                    return col
                })
                let gaps = (0 ..< end).filter { !present.contains($0) }
                if !gaps.isEmpty { ws.rowSpanGaps[rowIndex] = gaps }
            }
            let setHeight = row["customHeight"] == "1" || row["customHeight"] == "true"
            if row["ht"] != nil, !setHeight { ws.fittedRows.insert(rowIndex) }
            // `ht` is the row's height whether or not it is marked custom (a
            // larger font makes a taller row without the flag).
            // A row a filter hid keeps its height; one hidden by hand is height 0.
            // A height someone set is kept though it is the sheet's default:
            // the default is a fit, and on paper a fit and a set height differ
            // (lo-tdf113271's 460 rows set to its default 15 pt print at 15.24,
            // not the fitted 14.52 — a page more than ours).
            // (xsd:boolean: LibreOffice writes "true" where Excel writes "1".)
            let rowHidden = row["hidden"] == "1" || row["hidden"] == "true"
            rowsSeen.insert(rowIndex)
            if rowHidden, let af = ws.autoFilter, rowIndex > af.range.top, rowIndex <= af.range.bottom {
                ws.filteredRows.insert(rowIndex)
                if let h = Double(row["ht"] ?? ""), setHeight || abs(h - ws.defaultRowHeightPt) > 0.01 { ws.rowHeights[rowIndex] = h }
            } else if rowHidden {
                // Hidden by hand or by a collapsed group: its height kept for when it shows again.
                ws.hiddenRows.insert(rowIndex)
                if let h = Double(row["ht"] ?? ""), setHeight || abs(h - ws.defaultRowHeightPt) > 0.01 { ws.rowHeights[rowIndex] = h }
            }
            else if let h = Double(row["ht"] ?? ""), setHeight || abs(h - ws.defaultRowHeightPt) > 0.01 { ws.rowHeights[rowIndex] = h }
        }
        var colIndex = 0
        func cellBody(_ c: MiniXML.XlsxCell) {
                let a = c.r.flatMap { CellAddress($0) } ?? CellAddress(row: rowIndex, col: colIndex)
                colIndex = a.col + 1
                let styleIndex = Int(c.s ?? "0") ?? 0
                let t = c.t ?? "n"
                let vText: String? = c.hasV ? c.v : nil
                var value: CellValue = .empty
                switch t {
                case "s":
                    // (A stored index may carry blanks: bug69769's "2 ".)
                    let sstIndex = Int((vText ?? "").trimmingSpaces())
                    value = sstIndex.flatMap { $0 >= 0 && $0 < sst.count ? CellValue.text(sst[$0]) : nil } ?? .empty
                    if let i = sstIndex, sstScripts.contains(i) { ws.scriptRows.insert(a.row) }
                    if let i = sstIndex, let runs = sstRuns[i] { ws.richText[a] = runs }
                    if let i = sstIndex, let raw = sstRaw[i], i < sst.count { ws.richRaw[a] = (sst[i], raw) }
                // (An inline string with nothing in it is still a string, the empty
                // one: a cell with a value, which Excel prints the sheet as far as.)
                case "inlineStr": value = .text(c.inlineNode.map { _text($0) } ?? "")
                case "str": value = .text(vText ?? "")
                case "b": value = .bool(vText == "1" || vText == "true")
                case "e": value = .error(ExcelError(rawValue: vText ?? "") ?? .value)
                // (An ISO 8601 date, "1990-01-01" or with a time: the strict format's
                // date cell. It becomes the date's serial number.)
                case "d": value = vText.flatMap { Xlsx._isoDateSerial($0) }.map { .number($0) } ?? .empty
                // (Excel reads a number stored with blanks around it: lo-tdf124525's
                // "    0.0402000000" cells print as 0.0402, not as nothing.)
                default: value = vText.flatMap { Double($0.drop(while: { $0 == " " || $0 == "\n" || $0 == "\t" })) }.map { .number($0) } ?? .empty
                }
                var cell = Cell(input: nil)
                cell.style = styleIndex < book.styles.count ? styleIndex : 0
                // (Turned text is fitted by its length, which only the file's
                // fit has: lo-forum-mso-en4-134670's headings' 196.5 pt.)
                // (A row the file stores no height for is fitted on load, as Excel does: only a stored one is kept.)
                if book.styles[cell.style].rotation != 0, !value.isEmpty, ws.fittedRows.contains(a.row) || ws.rowHeights[a.row] != nil { ws.scriptRows.insert(a.row) }
                for (k, v) in c.kept { cell.keptAttrs[k] = v }
                if c.hasF {
                    // As the file wrote it, for when it cannot be read.
                    // (Made only for a formula that cannot be: one in a
                    // thousand, and this was a string built for every one.)
                    func rawF() -> String {
                        var s = "<f"
                        var attrs = c.fExtra
                        if let v = c.fT { attrs.append(("t", v)) }
                        if let v = c.fSi { attrs.append(("si", v)) }
                        if let v = c.fRef { attrs.append(("ref", v)) }
                        for (k, v) in attrs.sorted(by: { $0.0 < $1.0 }) { s += " \(k)=\"\(_esc(v))\"" }
                        return c.fText.isEmpty ? s + "/>" : s + ">" + _esc(c.fText) + "</f>"
                    }
                    var expr: FormulaExpr? = nil
                    if c.fT == "shared", let si = c.fSi {
                        if !c.fText.isEmpty, let e = try? Formula.parse(c.fText) {
                            expr = _unprefix(e)
                            shared[si] = (a, expr!)
                        } else if let (anchor, master) = shared[si] {
                            expr = Formula.shifted(master, rows: a.row - anchor.row, cols: a.col - anchor.col)
                        }
                    } else if !c.fText.isEmpty {
                        expr = (try? Formula.parse(c.fText)).map(_unprefix)
                        if c.fT == "array" { cell.arrayRef = c.fRef ?? a.a1 }
                    }
                    if let expr {
                        cell.formula = expr
                        cell.cached = c.hasV ? value : nil
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
                        cell.input = c.fText.isEmpty ? NumberFormat.display(value, "General", width: 255).text : "=" + c.fText
                        cell.value = value
                        cell.cached = value
                        cell.rawFormula = rawF()
                    }
                } else {
                    cell.value = value
                    // A text constant that starts with "=" stays text (lo-tdf162093's "=myData[#Headers]"):
                    // typed, it would be "'=abc", and that is its input here.
                    if case .text(let t) = value, t.hasPrefix("="), t.count > 1 { cell.input = "'" + t }
                }
                if cell.value.isEmpty && cell.formula == nil && cell.style == 0 && cell.input.isEmpty { return }
                cells[a] = cell
            }
        // The cells are read straight from the part's bytes (MiniXML.scanCells), a cell it does not recognise as a
        // tree, in its place; OFFICE_XLSX_SCAN=0 reads every row as a tree, as before.
        if Self.scanCells, let raw = part.bytes {
            MiniXML.scanRows(named: "row", ofRootChild: "sheetData", in: raw) { row, element, inside in
                // (The span test reads every <c>, the bare ones too: that row is read as a tree.)
                let full: XNode? = ["1", "true"].contains(row["customFormat"] ?? "") ? MiniXML.parse(Array(raw[element])) : nil
                rowSetup(full ?? row)
                colIndex = 0
                if let full { for c in full.kids("c") { cellBody(MiniXML.XlsxCell(node: c)) } }
                else { MiniXML.scanCells(in: raw, body: inside, cellBody) }
                rowIndex += 1
            }
        } else {
            part.forEach { row in
                rowSetup(row)
                colIndex = 0
                for c in row.kids("c") { cellBody(MiniXML.XlsxCell(node: c)) }
                rowIndex += 1
            }
        }
        // A row left with no cell keeps the span the file gave it (nothing to compute one from); the rest are computed on save.
        if !spanText.isEmpty {
            let withCells = Set(cells.keys.map(\.row))
            for (r, sp) in spanText where !withCells.contains(r) { ws.rowAttrs[r, default: [:]]["spans"] = sp }
        }
        // A sheet whose rows are hidden by default (zeroHeight): only the rows
        // the file lists show. pt-734a1b506b's Índice lists rows 1-35 and
        // 48-53, and Excel prints 621 pt of it, not the 800 of all 53.
        if ["1", "true"].contains(format?["zeroHeight"] ?? ""), let last = rowsSeen.max(), last < 20000 {
            for r in 0 ..< last where !rowsSeen.contains(r) { ws.hiddenRows.insert(r) }
        }
        // The spill values an array formula left in the file go: computing it
        // puts them back (where the formula cannot be computed, they stay).
        for (anchor, r) in spillAreas {
            for row in r.top ... r.bottom {
                for col in r.left ... r.right {
                    let a = CellAddress(row: row, col: col)
                    guard a != anchor, let c = cells[a], c.formula == nil, c.rawFormula == nil else { continue }
                    if !c.value.isEmpty { ws.fileSpill[a] = c.value }
                    if c.style == 0 { cells[a] = nil } else { cells[a]?.value = .empty; cells[a]?.input = "" }
                }
            }
        }
        ws.cells = cells
        for m in root.child("mergeCells")?.kids("mergeCell") ?? [] {
            if let r = m["ref"].flatMap({ CellRange($0) }) { ws.merges.append(r) }
        }
        let light = XNode(name: root.name, attrs: root.attrs)
        light.children = root.children.filter { $0.name != "sheetData" }
        return light
    }

    /// A stored column width (characters of the default font's widest
    /// digit — `digit` pixels, 7 for Calibri 11 — padding included) as
    /// points, and back: ECMA-376 18.3.1.13's formulas, which round-trip to
    /// the pixel.
    static func _charsToPoints(_ w: Double, digit: Double = 7) -> Double {
        ((256 * w + (128.0 / digit).rounded(.down)) / 256 * digit).rounded(.down) * 0.75
    }
    /// A column's width for the file: as the file had it while unchanged.
    static func _widthChars(_ ws: Worksheet, _ col: Int, _ pt: Double) -> Double {
        if let w = ws.colWidthChars[col], _charsToPoints(w, digit: ws.digitWidth) == pt { return w }
        return _pointsToChars(pt, digit: ws.digitWidth)
    }

    /// What Excel's dialogs call a width: the characters that fit, without
    /// the 5 px of padding the file's width includes (stored 20.7109375 is 20).
    static func _displayChars(points pt: Double, digit: Double = 7) -> Double {
        let px = (pt / 0.75).rounded()
        return (((px - 5) / digit) * 100).rounded() / 100
    }
    /// Points for a width typed as characters: the file's width is
    /// trunc((chars * digit + 5) / digit * 256) / 256, as Excel writes it.
    static func _pointsForDisplayChars(_ chars: Double, digit: Double = 7) -> Double {
        let stored = ((chars * digit + 5) / digit * 256).rounded(.down) / 256
        return _charsToPoints(stored, digit: digit)
    }

    static func _pointsToChars(_ pt: Double, digit: Double = 7) -> Double {
        let px = (pt / 0.75).rounded()
        return (px / digit * 256).rounded(.down) / 256
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
    /// A rich string's run: its text and its `rPr`'s font. A run with no
    /// `rPr` is the cell's font throughout; one with a `rPr` gives its
    /// whole font, what it leaves out being off (as Excel reads it).
    static func _richRun(_ r: XNode, theme: [UInt32], themeFonts: (minor: String?, major: String?), themeless: Bool) -> RichRun {
        var run = RichRun(text: r.child("t")?.text ?? "")
        guard let pr = r.child("rPr") else { return run }
        func on(_ name: String) -> Bool { pr.child(name).map { $0["val"] != "0" && $0["val"] != "false" } ?? false }
        run.bold = on("b"); run.italic = on("i"); run.strike = on("strike")
        run.underline = pr.child("u").map { $0["val"] != "none" } ?? false
        run.size = pr.child("sz").flatMap { Double($0["val"] ?? "") }
        let named = pr.child("rFont")?["val"]
        let builtin = false
        switch pr.child("scheme")?["val"] {
        case "minor": run.fontName = themeFonts.minor ?? (builtin ? "Aptos Narrow" : named)
        case "major": run.fontName = themeFonts.major ?? (builtin ? "Aptos Display" : named)
        default: run.fontName = named
        }
        run.color = pr.child("color").flatMap { _color($0, theme: theme) }
        switch pr.child("vertAlign")?["val"] {
        case "superscript": run.script = 1
        case "subscript": run.script = -1
        default: break
        }
        return run
    }

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

    private struct _Font { var bold = false, italic = false, underline = false, accounting = 0, strike = false, script = 0
        var size: Double? = nil, name: String? = nil, color: UInt32? = nil }

    /// A font's face. One of the theme's (`scheme` minor or major) is the
    /// theme's Latin face, whatever its `name` says: Excel sets 51519's
    /// "宋体" in Calibri — its columns, rows and Latin text — and a dozen
    /// other East Asian workbooks' fonts the same way (their names are the
    /// writer's locale's face, their themes Calibri). A book with no theme
    /// part prints its minor-scheme "Calibri" in Calibri (the 200% prints,
    /// build 20527; the older prints showed Aptos Narrow 15.24 pt rows).
    static func _fontName(_ f: XNode, _ themeFonts: (minor: String?, major: String?), themeless: Bool = false) -> String? {
        let named = f.child("name")?["val"]
        let builtin = false
        switch f.child("scheme")?["val"] {
        case "minor": return themeFonts.minor ?? (builtin ? "Aptos Narrow" : named)
        case "major": return themeFonts.major ?? (builtin ? "Aptos Display" : named)
        default: return named
        }
    }

    /// The book's default font: the one cellXfs' first entry — the style
    /// of every cell the file has no record of — names, which is the first
    /// font in all but a few files. bug66675's names its second, an empty
    /// `<font/>`, which Excel takes as Calibri 11 (its rows print at 14.52,
    /// where its first font, of a theme-less book's minor scheme, would be
    /// Aptos Narrow's 15.24).
    static func _defaultFont(_ st: XNode) -> XNode? {
        let fonts = st.child("fonts")?.kids("font") ?? []
        if let id = st.child("cellXfs")?.kids("xf").first?["fontId"].flatMap(Int.init), id < fonts.count { return fonts[id] }
        return fonts.first
    }

    /// The theme's Latin faces, body (minor) and headings (major).
    static func _themeFonts(_ t: XNode?) -> (minor: String?, major: String?) {
        func latin(_ name: String) -> String? {
            guard let f = t?.descendant("a:" + name) ?? t?.descendant(name),
                  let face = f.child("latin")?["typeface"], !face.isEmpty else { return nil }
            return face
        }
        return (latin("minorFont"), latin("majorFont"))
    }

    static func _styles(_ st: XNode, theme: [UInt32], themeFonts: (minor: String?, major: String?) = (nil, nil), themeless: Bool = false) -> [CellStyle] {
        // (A palette of the book's own: indexed colours are its entries, de-48adcf794a's input-cell fill indexed 43 is FFFFCC there, FFFF99 in the default.)
        let own = st.child("colors")?.child("indexedColors")?.kids("rgbColor").compactMap { $0["rgb"].flatMap { UInt32($0.suffix(6), radix: 16) } } ?? []
        customIndexed = own.count >= 56 ? own : nil
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
            font.accounting = ["singleAccounting": 1, "doubleAccounting": 2][f.child("u")?["val"] ?? ""] ?? 0
            font.strike = f.child("strike").map { $0["val"] != "0" && $0["val"] != "false" } ?? false
            font.script = ["superscript": 1, "subscript": -1][f.child("vertAlign")?["val"] ?? ""] ?? 0
            font.size = f.child("sz").flatMap { Double($0["val"] ?? "") }
            font.name = _fontName(f, themeFonts, themeless: themeless)
            font.color = f.child("color").flatMap { _color($0, theme: theme) }
            fonts.append(font)
        }
        // (Measured against the default font, `_defaultFont`'s.)
        let first = st.child("cellXfs")?.kids("xf").first?["fontId"].flatMap(Int.init) ?? 0
        let base = (first < fonts.count ? fonts[first] : fonts.first) ?? _Font()
        var fills: [UInt32?] = []
        // A pattern prints as fine lines or dots of its colour over its
        // background — black over white where it names neither — and is
        // drawn here as the colour they average to: FillWithoutColor's
        // "lightUp" cells, grey in Excel's print, were white.
        let coverage: [String: Double] = [
            "gray0625": 0.0625, "gray125": 0.125, "lightGray": 0.25, "mediumGray": 0.5, "darkGray": 0.75,
            "lightHorizontal": 0.25, "lightVertical": 0.25, "lightDown": 0.25, "lightUp": 0.25, "lightGrid": 0.44, "lightTrellis": 0.25,
            "darkHorizontal": 0.5, "darkVertical": 0.5, "darkDown": 0.5, "darkUp": 0.5, "darkGrid": 0.5, "darkTrellis": 0.75,
        ]
        for f in st.child("fills")?.kids("fill") ?? [] {
            if let p = f.child("patternFill"), p["patternType"] == "solid" {
                fills.append(p.child("fgColor").flatMap { _color($0, theme: theme) })
            } else if let p = f.child("patternFill"), let k = coverage[p["patternType"] ?? ""] {
                func auto(_ c: XNode?) -> Bool { c == nil || ["64", "65"].contains(c?["indexed"] ?? "") && c?["rgb"] == nil && c?["theme"] == nil }
                let fg: UInt32 = auto(p.child("fgColor")) ? 0x000000 : p.child("fgColor").flatMap { _color($0, theme: theme) } ?? 0x000000
                let bg: UInt32 = auto(p.child("bgColor")) ? 0xFFFFFF : p.child("bgColor").flatMap { _color($0, theme: theme) } ?? 0xFFFFFF
                fills.append(CFEvaluator._mix(bg, fg, k))
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
        let linkXf = st.child("cellStyles")?.kids("cellStyle").first { $0["builtinId"] == "8" }?["xfId"]
        for xf in st.child("cellXfs")?.kids("xf") ?? [] {
            var s = CellStyle()
            if let linkXf, xf["xfId"] == linkXf { s.linkStyle = true }
            if xf["pivotButton"] == "1" { s.pivotButton = true }
            if let id = Int(xf["numFmtId"] ?? "0") { s.numberFormat = formats[id] ?? "General" }
            if let fi = Int(xf["fontId"] ?? "0"), fi < fonts.count {
                let f = fonts[fi]
                s.bold = f.bold; s.italic = f.italic; s.underline = f.underline; s.accounting = f.accounting; s.strike = f.strike; s.script = f.script
                // The default font is the theme's: left nil, so a new face follows it.
                if f.name != base.name { s.fontName = f.name }
                if f.size != base.size { s.fontSize = f.size }
                if let c = f.color, c != 0x000000 { s.color = c }
            }
            if let fi = Int(xf["fillId"] ?? "0"), fi < fills.count { s.fill = fills[fi] }
            if let bi = Int(xf["borderId"] ?? "0"), bi < borders.count { s.borders = borders[bi] }
            if let al = xf.child("alignment") {
                var justified = false
                switch al["horizontal"] {
                case "left": s.hAlign = .left
                case "center", "centerContinuous": s.hAlign = .center
                case "right": s.hAlign = .right
                case "justify", "distributed": s.hAlign = .left; justified = true; s.justify = al["horizontal"] == "justify"   // Excel breaks justified text into lines like a wrapped cell
                default: break
                }
                switch al["vertical"] {
                case "top": s.vAlign = .top
                case "center": s.vAlign = .center
                default: break
                }
                s.wrap = al["wrapText"] == "1" || al["wrapText"] == "true" || justified
                s.readingOrder = Int(al["readingOrder"] ?? "") ?? 0
                s.indent = max(0, min(250, Int(al["indent"] ?? "") ?? 0))
                s.rotation = Int(al["textRotation"] ?? "") ?? 0
            }
            if let pr = xf.child("protection") {
                s.locked = pr["locked"] != "0" && pr["locked"] != "false"
                s.formulaHidden = pr["hidden"] == "1" || pr["hidden"] == "true"
            }
            out.append(s)
        }
        return out
    }

    /// A <color> as 0xRRGGBB: rgb, a theme slot with its tint, or a
    /// legacy palette index; nil for "automatic".
    /// `<dxf>`: font, fill, borders and number format, as far as they are set. A solid fill's
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
        x.numberFormat = d.child("numFmt")?["formatCode"]
        for side in ["left", "right", "top", "bottom", "horizontal", "vertical"] {
            guard let b = d.child("border")?.child(side), let style = b["style"], style != "none" else { continue }
            x.borders[side] = b.child("color").flatMap { _color($0, theme: theme) } ?? 0
        }
        return x
    }

    static func _color(_ c: XNode, theme: [UInt32]) -> UInt32? {
        var rgb: UInt32? = nil
        // A theme slot before an rgb the same element also gives: Excel
        // prints lo-tdf113271's `<color theme="1" rgb="FFFFFF"/>` black.
        if let t = c["theme"].flatMap({ Int($0) }), t < theme.count { rgb = theme[t] }
        else if let s = c["rgb"], let v = UInt32(s.suffix(6), radix: 16) { rgb = v }
        else if let i = c["indexed"].flatMap({ Int($0) }), i < _indexed.count { rgb = customIndexed.flatMap { i < $0.count ? $0[i] : nil } ?? _indexed[i] }
        guard var v = rgb else { return nil }
        if let tint = c["tint"].flatMap({ Double($0) }), tint != 0 { v = _tinted(v, tint) }
        return v
    }

    /// A colour with a theme tint: its luminance moved toward black (a
    /// negative tint) or white, in HSL as Excel moves it — not each channel
    /// scaled, which greys a colour: lo-tdf171828's "Background 2, darker
    /// 25%" over the 2007 theme's EEECE1 is Excel's olive C4BD97, where
    /// scaling the channels made B2B1A9.
    static func _tinted(_ v: UInt32, _ tint: Double) -> UInt32 {
        let r = Double((v >> 16) & 0xFF) / 255, g = Double((v >> 8) & 0xFF) / 255, b = Double(v & 0xFF) / 255
        let hi = max(r, g, b), lo = min(r, g, b)
        var l = (hi + lo) / 2
        var h = 0.0, s = 0.0
        if hi > lo {
            let d = hi - lo
            s = l > 0.5 ? d / (2 - hi - lo) : d / (hi + lo)
            if hi == r { h = (g - b) / d + (g < b ? 6 : 0) } else if hi == g { h = (b - r) / d + 2 } else { h = (r - g) / d + 4 }
            h /= 6
        }
        l = tint < 0 ? l * (1 + tint) : l * (1 - tint) + tint
        func channel(_ t0: Double) -> UInt32 {
            var t = t0
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            let q = l < 0.5 ? l * (1 + s) : l + s - l * s, p = 2 * l - q
            let x: Double
            if t < 1.0 / 6 { x = p + (q - p) * 6 * t } else if t < 0.5 { x = q } else if t < 2.0 / 3 { x = p + (q - p) * (2.0 / 3 - t) * 6 } else { x = p }
            return UInt32(max(0, min(255, (x * 255).rounded())))
        }
        if s == 0 { let x = UInt32(max(0, min(255, (l * 255).rounded()))); return (x << 16) | (x << 8) | x }
        return (channel(h + 1.0 / 3) << 16) | (channel(h) << 8) | channel(h - 1.0 / 3)
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

    /// The palette the book being read gives (`indexedColors`), set as its styles are read.
    nonisolated(unsafe) static var customIndexed: [UInt32]? = nil
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

    /// A table's header cells must hold its column names, or Excel repairs
    /// the file: an empty one gets the name the part will carry, "Column"
    /// and its place (Excel itself refills such a cell with "Column1" at once).
    static func _fillTableHeaders(_ ws: Worksheet) {
        for t in ws.tables where t.headerRow {
            var used = Set<String>()
            for (i, col) in (t.ref.left ... t.ref.right).enumerated() {
                let a = CellAddress(row: t.ref.top, col: col)
                let raw = NumberFormat.display(ws.value(a), "General", width: 255).text
                // (A header of blank spaces stays as the file has it: chart-auto_marker_excel10's " ".)
                if !raw.isEmpty { used.insert(raw.trimmingWhitespace().lowercased()); continue }
                var name = "Column\(i + 1)", n = 2
                while used.contains(name.lowercased()) { name = "Column\(i + 1)\(n)"; n += 1 }
                used.insert(name.lowercased())
                var cell = ws.cells[a] ?? Cell(input: "")
                cell.input = name; cell.value = .text(name); cell.formula = nil
                ws.cells[a] = cell
            }
        }
    }

    // MARK: Writing

    static func write(_ book: Workbook) throws -> Data {
        for ws in book.sheets { _fillTableHeaders(ws) }
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
        var droppedTables = Set<String>()
        var tablePartsOverride: [Int: String] = [:]
        // Tables made here: the part each gets, and its id (unique in the book).
        var newTableParts: [String: (path: String, id: Int)] = [:]
        var nextTableId = 1 + (originalParts.filter { $0.key.hasPrefix("xl/tables/") && $0.key.hasSuffix(".xml") }
            .map { XNode.parse($0.value).flatMap { Int($0["id"] ?? "") } ?? 0 }.max() ?? 0)
        // Pivot tables made here: their parts, numbered past the file's.
        var madePivots: [MadePivotParts] = []
        // A file's pivot edited here is written afresh: the parts the file had for it (and its cache) go.
        var droppedPivotParts = Set<String>(), droppedCachePaths = Set<String>(), droppedCacheIds = Set<Int>()
        var cacheOf: [String: Int] = [:]
        var nextCacheId = 1 + ((originalParts["xl/workbook.xml"].flatMap { XNode.parse($0) }?.child("pivotCaches")?.kids("pivotCache") ?? [])
            .compactMap { Int($0["cacheId"] ?? "") }.max() ?? 0)
        func freshPart(_ dir: String, _ base: String) -> String {
            var n = 1
            while taken.contains("\(dir)/\(base)\(n).xml") || originalParts["\(dir)/\(base)\(n).xml"] != nil { n += 1 }
            taken.insert("\(dir)/\(base)\(n).xml")
            return "\(dir)/\(base)\(n).xml"
        }
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
            // A table deleted with all its rows: its part, relationship and
            // <tablePart> go, or Excel repairs the file.
            if !ws.removedTables.isEmpty || ws.tables.contains(where: \.isNew) {
                let base = String(paths[i].prefix(upTo: paths[i].lastIndex(of: "/").map { paths[i].index(after: $0) } ?? paths[i].startIndex))
                var text = ws.keptElements.first { $0.name == "tableParts" }?.text ?? ""
                for t in ws.removedTables {
                    droppedTables.insert(t.path)
                    for r in rels where r.type.hasSuffix("/table") && _resolve(r.target, base: base) == t.path {
                        rels.removeAll { $0.id == r.id }
                        changed = true
                        text = text.replacingAll("<tablePart r:id=\"\(r.id)\"/>", with: "")
                    }
                }
                for (j, t) in ws.tables.enumerated() where t.isNew {
                    var n = 1
                    while taken.contains("xl/tables/table\(n).xml") || originalParts["xl/tables/table\(n).xml"] != nil { n += 1 }
                    let path = "xl/tables/table\(n).xml"
                    taken.insert(path)
                    newTableParts["\(i)/\(j)"] = (path, nextTableId)
                    nextTableId += 1
                    let rid = Xlsx._freshId(rels)
                    rels.append((rid, "http://schemas.openxmlformats.org/officeDocument/2006/relationships/table", "../tables/table\(n).xml"))
                    changed = true
                    if text.isEmpty { text = "<tableParts count=\"0\"></tableParts>" }
                    if let at = text.findRange(of: "</tableParts>")?.lowerBound { text.insert(contentsOf: "<tablePart r:id=\"\(rid)\"/>", at: at) }
                }
                let left = text.components(separatedBy: "<tablePart ").count - 1
                if left == 0 { text = "" } else if let c = text.findRange(of: " count=\""), let q = text.findRange(of: "\"", in: c.upperBound ..< text.endIndex) {
                    text.replaceSubrange(c.upperBound ..< q.lowerBound, with: "\(left)")
                }
                tablePartsOverride[i] = text
            }
            // Pivot tables made here: the part, and the sheet's relationship to it.
            for p in ws.pivots {
                guard let spec = p.made, let source = p.source, let src = PivotSource.read(source, book: book),
                      PivotCalc.problem(spec, src) == nil else { continue }
                let key = src.sheet + "!" + src.ref.a1
                var m = MadePivotParts(sheet: i, spec: spec, src: src, location: p.ref, style: p.style ?? "PivotStyleLight16",
                                       table: freshPart("xl/pivotTables", "pivotTable"), cache: freshPart("xl/pivotCache", "pivotCacheDefinition"),
                                       records: freshPart("xl/pivotCache", "pivotCacheRecords"), cacheId: nextCacheId, workbookRel: "")
                var reusedId = false
                if let old = p.path, let oldCache = p.cachePath {
                    droppedPivotParts.insert(old); droppedPivotParts.insert(_relsPath(old))
                    droppedPivotParts.insert(oldCache); droppedPivotParts.insert(_relsPath(oldCache)); droppedCachePaths.insert(oldCache)
                    for r in _relList(originalParts[_relsPath(oldCache)]) where r.type.hasSuffix("/pivotCacheRecords") {
                        droppedPivotParts.insert(_resolve(r.target, base: "xl/pivotCache/"))
                    }
                    let base = String(paths[i].prefix(upTo: paths[i].lastIndex(of: "/").map { paths[i].index(after: $0) } ?? paths[i].startIndex))
                    for r in rels where r.type.hasSuffix("/pivotTable") && _resolve(r.target, base: base) == old { rels.removeAll { $0.id == r.id } }
                    if let id = p.cacheId, cacheOf[key] == nil { m.cacheId = id; droppedCacheIds.insert(id); reusedId = true }
                }
                if let o = cacheOf[key] {
                    // freshPart reserved names for a cache this pivot will not write; the owner's are used.
                    m.cache = madePivots[o].cache; m.records = madePivots[o].records; m.cacheId = madePivots[o].cacheId; m.ownsCache = false
                } else {
                    cacheOf[key] = madePivots.count
                    if !reusedId { nextCacheId += 1 }
                }
                rels.append((Xlsx._freshId(rels), "http://schemas.openxmlformats.org/officeDocument/2006/relationships/pivotTable",
                             "../pivotTables/" + String(m.table.dropFirst("xl/pivotTables/".count))))
                changed = true
                madePivots.append(m)
            }
            // Links made here: their addresses join the sheet's relationships.
            for (id, url) in ws.linkTargets.sorted(by: { $0.key < $1.key }) where !rels.contains(where: { $0.id == id }) {
                rels.append((id, "http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink", url))
                changed = true
            }
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
            if let e = tablePartsOverride[i] { extra["tableParts"] = e }
            if let e = noteParts[i].element { extra["legacyDrawing"] = e }
            sheetXML.append(_sheetXML(ws, book: book, selected: i == book.activeTab || ws.tabSelected, extra: extra, dynamicCm: dynamicCm,
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
            if let r = rels.first(where: { _resolve($0.target, base: "xl/") == p && ($0.type.hasSuffix("/worksheet") || $0.type.hasSuffix("/chartsheet")) }) {
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
        // A new workbook (nothing opened from a file) carries the standard Office theme, as Excel's own do. An
        // opened file keeps the theme it came with, or none: giving a theme-less one a theme would change its fonts.
        if original.isEmpty && !rels.contains(where: { $0.type.hasSuffix("/theme") }) {
            rels.append((_freshId(rels), "http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme", "theme/theme1.xml"))
        }
        let stylesPath = rels.first { $0.type.hasSuffix("/styles") }.map { _resolve($0.target, base: "xl/") } ?? "xl/styles.xml"
        let sstPath = rels.first { $0.type.hasSuffix("/sharedStrings") }.map { _resolve($0.target, base: "xl/") } ?? "xl/sharedStrings.xml"

        rels.removeAll { r in r.type.hasSuffix("/pivotCacheDefinition") && droppedCachePaths.contains(_resolve(r.target, base: "xl/")) }
        var cacheUnion: [Int: Set<Int>] = [:]
        for m in madePivots { cacheUnion[m.cacheId, default: []].formUnion(m.spec.rows + m.spec.cols + m.spec.filters.map(\.field)) }
        for k in madePivots.indices { madePivots[k].cacheFields = cacheUnion[madePivots[k].cacheId] ?? [] }
        for k in madePivots.indices where madePivots[k].ownsCache {
            let id = _freshId(rels)
            rels.append((id, "http://schemas.openxmlformats.org/officeDocument/2006/relationships/pivotCacheDefinition",
                         String(madePivots[k].cache.dropFirst("xl/".count))))
            madePivots[k].workbookRel = id
        }
        var generated: [String: Data] = [:]
        for k in madePivots.indices { for (path, data) in madePivots[k].parts() { generated[path] = Data(data.utf8) } }
        for (k, v) in PivotsXML.patched(sheets: book.sheets, parts: originalParts) { generated[k] = v }
        generated["xl/workbook.xml"] = Data(_workbookXML(book, ids: sheetIds, original: originalParts["xl/workbook.xml"], newCaches: madePivots.filter(\.ownsCache).map { ($0.cacheId, $0.workbookRel) }, droppedCacheIds: droppedCacheIds).utf8)
        generated["xl/_rels/workbook.xml.rels"] = Data(_relsXML(rels).utf8)
        // A chart sheet is not edited here: its own part stays as it was (a worksheet body
        // inside a chartsheet root is not a file Excel opens as a chart sheet).
        for (i, p) in paths.enumerated() where !(book.sheets[i].isChartSheet && originalParts[p] != nil) { generated[p] = Data(sheetXML[i].utf8) }
        generated[stylesPath] = Data(_stylesXML(book).utf8)
        if newMetadata { generated["xl/metadata.xml"] = Data(_dynamicArrayMetadata.utf8) }
        generated[sstPath] = Data(_sstXML(sst).utf8)
        // Tables: rewritten whenever their header cells or range could have
        // changed, which is any save (names must match the cells exactly).
        var newTableTypes: [(String, String)] = []
        for (i, ws) in book.sheets.enumerated() {
            for (j, t) in ws.tables.enumerated() {
                var t = t
                if t.isNew, let np = newTableParts["\(i)/\(j)"] {
                    t.path = np.path
                    newTableTypes.append(("/" + np.path, "application/vnd.openxmlformats-officedocument.spreadsheetml.table+xml"))
                }
                guard let original = originalParts[t.path] ?? (newTableParts["\(i)/\(j)"].map { TablesXML.newPart(t, id: $0.id) }) else { continue }
                generated[t.path] = TablesXML.write(t, original: original, header: { col in
                    let v = ws.value(CellAddress(row: t.ref.top, col: col))
                    return NumberFormat.display(v, book.style(ws.cells[CellAddress(row: t.ref.top, col: col)]?.style ?? 0).numberFormat,
                                                width: 255).text
                })
            }
        }
        var extraTypes: [(String, String)] = newTableTypes
        for m in madePivots {
            extraTypes.append(("/" + m.table, "application/vnd.openxmlformats-officedocument.spreadsheetml.pivotTable+xml"))
            guard m.ownsCache else { continue }
            extraTypes.append(("/" + m.cache, "application/vnd.openxmlformats-officedocument.spreadsheetml.pivotCacheDefinition+xml"))
            extraTypes.append(("/" + m.records, "application/vnd.openxmlformats-officedocument.spreadsheetml.pivotCacheRecords+xml"))
        }
        if original.isEmpty {
            generated["xl/theme/theme1.xml"] = Data(DocxFormat._defaultThemePart().utf8)
            extraTypes.append(("/xl/theme/theme1.xml", "application/vnd.openxmlformats-officedocument.theme+xml"))
        }
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
        dropped.formUnion(droppedTables)
        dropped.formUnion(droppedPivotParts)
        // A package built from an .xls has no content-type list of its own: type the
        // chart and drawing parts it holds, and the picture extensions, or Excel refuses the file.
        for name in Set(originalParts.keys).union(generated.keys) where !dropped.contains(name) {
            if name.hasPrefix("xl/charts/chart"), name.hasSuffix(".xml") { extraTypes.append(("/" + name, SheetDrawingsXML.chartType)) }
            else if name.hasPrefix("xl/drawings/drawing"), name.hasSuffix(".xml") { extraTypes.append(("/" + name, SheetDrawingsXML.drawingType)) }
        }
        generated["[Content_Types].xml"] = Data(_contentTypes(originalParts["[Content_Types].xml"],
                                                              sheets: paths, styles: stylesPath, sst: sstPath, dropped: dropped,
                                                              extra: extraTypes,
                                                              mediaExtensions: Set(Set(originalParts.keys).union(generated.keys).filter { $0.hasPrefix("xl/media/") }
                                                                  .compactMap { $0.split(separator: ".").last.map { String($0).lowercased() } })).utf8)
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
        _relList(_part(parts, "xl/_rels/workbook.xml.rels")).filter { $0.type.hasSuffix("/worksheet") }.map { _resolve($0.target, base: "xl/") }
    }

    /// A part by its name, whatever its case: part names in a package are
    /// case-insensitive, and chart-tdf100084's Sheet1.xml has its
    /// relationships in _rels/sheet1.xml.rels — its two charts were lost.
    static func _part(_ parts: [String: Data], _ name: String) -> Data? {
        if let d = parts[name] { return d }
        let low = name.lowercased()
        return parts.first { $0.key.lowercased() == low }?.value
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
        for r in rels {
            // A hyperlink target is an address, not a part: Excel needs it marked External.
            let mode = r.type.hasSuffix("/hyperlink") ? " TargetMode=\"External\"" : ""
            s += "<Relationship Id=\"\(_esc(r.id))\" Type=\"\(_esc(r.type))\" Target=\"\(_esc(r.target))\"\(mode)/>"
        }
        return s + "</Relationships>"
    }

    private static let _rootRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>
    """

    private static func _contentTypes(_ original: Data?, sheets: [String], styles: String, sst: String, dropped: Set<String>,
                                      extra: [(String, String)] = [], mediaExtensions: Set<String> = []) -> String {
        var defaults: [(String, String)] = [("rels", "application/vnd.openxmlformats-package.relationships+xml"), ("xml", "application/xml")]
        var overrides: [(String, String)] = []
        if let original, let root = XNode.parse(original) {
            defaults = root.kids("Default").compactMap { d in d["Extension"].flatMap { e in d["ContentType"].map { (e, $0) } } }
            overrides = root.kids("Override").compactMap { o in o["PartName"].flatMap { p in o["ContentType"].map { (p, $0) } } }
        }
        overrides.removeAll { dropped.contains(String($0.0.dropFirst())) }
        for (e, t) in [("png", "image/png"), ("jpeg", "image/jpeg"), ("jpg", "image/jpeg"), ("gif", "image/gif"), ("bmp", "image/bmp"),
                       ("emf", "image/x-emf"), ("wmf", "image/x-wmf"), ("tiff", "image/tiff")]
        where !defaults.contains(where: { $0.0.lowercased() == e }) && mediaExtensions.contains(e) {
            defaults.append((e, t))
        }
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

    private static func _workbookXML(_ book: Workbook, ids: [String], original: Data?, newCaches: [(Int, String)] = [], droppedCacheIds: Set<Int> = []) -> String {
        let cacheItems = newCaches.map { "<pivotCache cacheId=\"\($0.0)\" r:id=\"\($0.1)\"/>" }.joined()
        var wrotePivotCaches = newCaches.isEmpty
        var sheets = "<sheets>"
        // Each sheet keeps the id it was read with (pivot caches and external references can name it); a new
        // sheet, or a clashing one, gets the next id nobody uses.
        var taken = Set<Int>(), sheetIds: [Int] = []
        for ws in book.sheets {
            if let id = ws.sheetId, id > 0, !taken.contains(id) { taken.insert(id); sheetIds.append(id) } else { sheetIds.append(0) }
        }
        var nextId = (taken.max() ?? 0) + 1
        for i in sheetIds.indices where sheetIds[i] == 0 { sheetIds[i] = nextId; nextId += 1 }
        for (i, ws) in book.sheets.enumerated() {
            sheets += "<sheet name=\"\(_esc(ws.name))\" sheetId=\"\(sheetIds[i])\"" + (ws.veryHidden ? " state=\"veryHidden\"" : ws.hidden ? " state=\"hidden\"" : "") + " r:id=\"\(ids[i])\"/>"
        }
        sheets += "</sheets>"
        // (A book with pivot tables leaves out the full recalculation on load: Excel refreshes those on load, and
        // none of Excel's own pivot files ask for both.)
        let calc = "<calcPr calcId=\"191029\"" + (book.sheets.contains { !$0.pivots.isEmpty } ? "" : " fullCalcOnLoad=\"1\"")
            + (book.iterate ? " iterate=\"1\" iterateCount=\"\(book.iterateCount)\" iterateDelta=\"\(_num(book.iterateDelta))\"" : "") + "/>"
        let prot = book.workbookProtection.map { a in "<workbookProtection" + a.keys.sorted().map { " \($0)=\"\(_esc(a[$0] ?? ""))\"" }.joined() + "/>" } ?? ""
        // The original's other elements (workbookPr, bookViews, definedNames,
        // pivot caches, extLst…) stay, in their places.
        if let original {
            let split = RawXML.split([UInt8](original))
            var body = ""
            var wroteSheets = false, wroteCalc = false, wroteProt = false
            let names = _definedNamesXML(book)
            var wroteNames = false
            for (name, text) in split.children {
                switch name {
                case "sheets": body += (wroteProt ? "" : prot) + sheets + (split.children.contains { $0.name == "definedNames" } ? "" : names); wroteSheets = true
                case "definedNames": body += names; wroteNames = true
                case "calcPr": body += calc; wroteCalc = true
                case "workbookProtection": body += prot; wroteProt = true
                case "bookViews": body += (wroteProt ? "" : prot) + _bookViews(text, active: book.activeTab); wroteProt = true
                case "pivotCaches" where !newCaches.isEmpty:
                    if let end = text.findRange(of: "</pivotCaches>", backwards: true) {
                        var t = text
                        for id in droppedCacheIds.sorted() {
                            if let a = t.findRange(of: "<pivotCache cacheId=\"\(id)\""), let e = t.findRange(of: "/>", in: a.upperBound ..< t.endIndex) {
                                t.removeSubrange(a.lowerBound ..< e.upperBound)
                            }
                        }
                        let end = t.findRange(of: "</pivotCaches>", backwards: true) ?? end
                        t.insert(contentsOf: cacheItems, at: end.lowerBound); body += t
                    } else { body += "<pivotCaches>" + cacheItems + "</pivotCaches>" }
                    wrotePivotCaches = true
                default:
                    if !wrotePivotCaches && ["smartTagPr", "smartTagTypes", "webPublishing", "fileRecoveryPr", "webPublishObjects", "extLst"].contains(name) {
                        if !wroteCalc { body += calc; wroteCalc = true }
                        body += "<pivotCaches>" + cacheItems + "</pivotCaches>"
                        wrotePivotCaches = true
                    }
                    if name == "definedNames" || name == "extLst" || name == "pivotCaches" || name == "webPublishing"
                        || name == "fileRecoveryPr" || name == "webPublishObjects" || name == "oleSize" || name == "customWorkbookViews" {
                        if !wroteCalc && (name != "definedNames") { body += calc; wroteCalc = true }
                    }
                    body += text
                }
            }
            if !wroteSheets { body = sheets + (wroteNames ? "" : names) + body }
            if !wroteCalc { body += calc }
            if !wrotePivotCaches { body += "<pivotCaches>" + cacheItems + "</pivotCaches>" }
            return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n" + _withRels(split.rootStart) + body + "</" + split.rootName + ">"
        }
        let names = _definedNamesXML(book)
        return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\">" + prot + "<bookViews><workbookView activeTab=\"\(book.activeTab)\"/></bookViews>" + sheets + names + calc + (newCaches.isEmpty ? "" : "<pivotCaches>" + cacheItems + "</pivotCaches>") + "</workbook>"
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
            let sig = (ws.freezeRows > 0 ? 1 : 0) + (ws.freezeCols > 0 ? 2 : 0)
            if sig == ws.selectionFreeze, let kept = _selectionsXML(ws.splitSelections, activePane: pane, active: active) { view += kept }
            else { view += "<selection pane=\"\(pane)\" activeCell=\"\(active.a1)\" sqref=\"\(active.a1)\"/>" }
        } else if let split = ws.splitPane {
            view += "<pane" + split.sorted { $0.key < $1.key }.map { " \($0.key)=\"\(_esc($0.value))\"" }.joined() + "/>"
            let activePane = split["activePane"] ?? "topLeft"
            for var sel in ws.splitSelections {
                if (sel["pane"] ?? "topLeft") == activePane { sel["activeCell"] = active.a1; sel["sqref"] = active.a1 }
                view += "<selection" + sel.sorted { $0.key < $1.key }.map { " \($0.key)=\"\(_esc($0.value))\"" }.joined() + "/>"
            }
        } else if ws.selectionFreeze == 0, let kept = _selectionsXML(ws.splitSelections, activePane: "topLeft", active: active) {
            view += kept
        } else {
            view += "<selection activeCell=\"\(active.a1)\" sqref=\"\(active.a1)\"/>"
        }
        view += "</sheetView></sheetViews>"
        generated["sheetViews"] = view
        // A default width the user changed (Format > Default Width) is written; one the file gave stays as it wrote it.
        var formatAttrs = ws.formatPrAttrs.filter { $0.key != "defaultRowHeight" }
        let readBack: Double = {
            if let w = Double(formatAttrs["defaultColWidth"] ?? ""), w > 0 { return _charsToPoints(w, digit: ws.digitWidth) }
            let base = Double(formatAttrs["baseColWidth"] ?? "") ?? 8
            return ((base * ws.digitWidth + 5) / 8).rounded(.up) * 8 * 0.75
        }()
        if abs(readBack - ws.defaultColWidthPt) > 0.01 { formatAttrs["defaultColWidth"] = _num(_pointsToChars(ws.defaultColWidthPt, digit: ws.digitWidth)) }
        generated["sheetFormatPr"] = "<sheetFormatPr" + formatAttrs.sorted { $0.key < $1.key }
            .map { " \($0.key)=\"\(_esc($0.value))\"" }.joined() + " defaultRowHeight=\"\(_num(ws.defaultRowHeightPt))\"/>"
        // Columns: segments where the width and the file's other attributes
        // (style, outline level…) are all the same.
        if !ws.colAttrRuns.isEmpty || !ws.hiddenCols.isEmpty || !ws.hiddenColRuns.isEmpty {
            var points = Set<Int>()
            for r in ws.colAttrRuns { points.insert(r.lo); points.insert(r.hi + 1) }
            for k in ws.hiddenCols { points.insert(k); points.insert(k + 1) }
            for r in ws.hiddenColRuns { points.insert(r.lowerBound); points.insert(r.upperBound + 1) }
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
                let hidden = ws.hiddenCols.contains(start) || ws.hiddenColRuns.contains { $0.contains(start) }
                if let w = ws.colWidths[start] {
                    key += " width=\"\(_num(_widthChars(ws, start, w)))\"" + (w == 0 || hidden ? " hidden=\"1\"" : "") + " customWidth=\"1\""
                } else if !attrs.isEmpty || hidden {
                    let own = ws.hiddenColRuns.first { $0.contains(start) }.flatMap { ws.hiddenRunChars[$0.lowerBound] }
                    let d = own ?? ws.defaultColWidthChars.flatMap { _charsToPoints($0, digit: ws.digitWidth) == ws.defaultColWidthPt ? $0 : nil }
                        ?? _pointsToChars(ws.defaultColWidthPt, digit: ws.digitWidth)
                    key += " width=\"\(_num(d))\"" + (hidden ? " hidden=\"1\"" : "")
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
        // The file's own values for an array formula's other cells, where ours left one blank.
        if !ws.fileSpill.isEmpty {
            let arrays = ws.cells.values.compactMap { $0.arrayRef.flatMap { CellRange($0) } }
            for (a, v) in ws.fileSpill where ws.spilled[a] == nil && ws.cells[a]?.value.isEmpty ?? true && ws.cells[a]?.formula == nil
                && arrays.contains(where: { $0.contains(a) }) {
                if let i = byRow[a.row]?.firstIndex(where: { $0.0 == a }) {
                    byRow[a.row]![i].1.value = v
                } else {
                    var c = Cell(input: ""); c.value = v
                    byRow[a.row, default: []].append((a, c))
                }
            }
        }
        let rows = Set(byRow.keys).union(ws.rowHeights.keys).union(ws.filteredRows).union(ws.hiddenRows).union(ws.rowAttrs.keys).sorted()
        var data = "<sheetData>"
        for r in rows {
            data += "<row r=\"\(r + 1)\""
            if let h = ws.rowHeights[r] { data += h == 0 ? " hidden=\"1\"" : " ht=\"\(_num(h))\"" + (ws.fittedRows.contains(r) ? "" : " customHeight=\"1\"") }
            if (ws.filteredRows.contains(r) || ws.hiddenRows.contains(r)) && ws.rowHeights[r] != 0 { data += " hidden=\"1\"" }
            let cells = (byRow[r] ?? []).sorted { $0.0.col < $1.0.col }
            let ownSpan = !cells.isEmpty || ws.rowSpanGaps[r] != nil
            for (k, v) in (ws.rowAttrs[r] ?? [:]).sorted(by: { $0.key < $1.key }) where !(k == "spans" && ownSpan) { data += " \(k)=\"\(_esc(v))\"" }
            // `spans` is Excel's hint of the columns a row touches; the bare formatted cells a customFormat row
            // spans (rowSpanGaps) count too, since printing reads them.
            let spanCols = cells.map(\.0.col) + (ws.rowSpanGaps[r] ?? [])
            if let lo = spanCols.min(), let hi = spanCols.max() { data += " spans=\"\(lo + 1):\(hi + 1)\"" }
            if cells.isEmpty { data += "/>"; continue }
            data += ">"
            for (a, c) in cells { data += _cellXML(a, c, dynamicCm: dynamicCm, rich: ws.richRaw[a], stringIndex: stringIndex) }
            data += "</row>"
        }
        generated["sheetData"] = data + "</sheetData>"
        if !ws.merges.isEmpty {
            generated["mergeCells"] = "<mergeCells count=\"\(ws.merges.count)\">" + ws.merges.map { "<mergeCell ref=\"\($0.a1)\"/>" }.joined() + "</mergeCells>"
        }
        if let af = ws.autoFilter {
            var cutoffs: [Int: Double] = [:]
            for (col, rule) in af.rules {
                guard case .top(let top, let percent, let n) = rule, af.range.rows > 1 else { continue }
                let nums = (af.range.top + 1 ... af.range.bottom).compactMap { ws.value(CellAddress(row: $0, col: col)).number }
                    .sorted(by: top ? { $0 > $1 } : { $0 < $1 })
                if !nums.isEmpty { cutoffs[col] = nums[min(percent ? max(1, nums.count * n / 100) : n, nums.count) - 1] }
            }
            generated["autoFilter"] = af.raw ?? _autoFilterXML(af, book: book, cutoffs: cutoffs)
        }
        var kept: [String: [String]] = [:]
        for (name, text) in ws.keptElements {
            if name == "extLst" { if let t = Sparklines.withoutEmptySparklineExt(text) { kept[name, default: []].append(t) }; continue }
            kept[name, default: []].append(text)
        }
        if let tab = ws.tabColor, kept["sheetPr"] == nil { generated["sheetPr"] = "<sheetPr><tabColor rgb=\"\(_esc(tab))\"/></sheetPr>" }
        var body = ""
        for name in sheetOrder {
            if let g = generated[name] { body += g }
            for t in kept[name] ?? [] where generated[name] == nil { body += t }
        }
        // Anything not in the schema list (a vendor element) goes last but before extLst.
        for (name, text) in ws.keptElements where !sheetOrder.contains(name) { body += text }
        let root = _withRels(ws.rootTag ?? "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\">")
        let rootName = root.dropFirst().prefix { $0 != " " && $0 != ">" && $0 != "\n" && $0 != "\t" && $0 != "\r" }
        return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n" + root + body + "</\(rootName)>"
    }

    private static func _autoFilterXML(_ af: AutoFilter, book: Workbook, cutoffs: [Int: Double] = [:]) -> String {
        guard af.isActive else { return "<autoFilter ref=\"\(af.range.a1)\"/>" }
        var s = "<autoFilter ref=\"\(af.range.a1)\">"
        for col in Set(af.columns.keys).union(af.rules.keys).sorted() {
            s += "<filterColumn colId=\"\(col - af.range.left)\">"
            if let allowed = af.columns[col] {
                s += "<filters" + (allowed.contains("") ? " blank=\"1\"" : "")
                let vals = allowed.filter { !$0.isEmpty }.sorted()
                s += vals.isEmpty ? "/>" : ">" + vals.map { "<filter val=\"\(_esc($0))\"/>" }.joined() + "</filters>"
            } else if let rule = af.rules[col] {
                func cond(_ c: FilterCondition) -> String {
                    "<customFilter" + (c.op == "equal" ? "" : " operator=\"\(c.op)\"") + " val=\"\(_esc(c.value))\"/>"
                }
                switch rule {
                case .compare(let a, let isAnd, let b):
                    s += "<customFilters" + (b != nil && isAnd ? " and=\"1\"" : "") + ">" + cond(a) + (b.map(cond) ?? "") + "</customFilters>"
                case .top(let top, let percent, let n):
                    s += "<top10" + (top ? "" : " top=\"0\"") + (percent ? " percent=\"1\"" : "") + " val=\"\(n)\""
                        + (cutoffs[col].map { " filterVal=\"\(_num($0))\"" } ?? "") + "/>"
                case .average(let above): s += "<dynamicFilter type=\"\(above ? "aboveAverage" : "belowAverage")\"/>"
                case .period(let p): s += "<dynamicFilter type=\"\(p)\"/>"
                case .color(let fill, let rgb):
                    let i = book.dxfs.firstIndex { (fill ? $0.fill : $0.color).map { $0 & 0xFFFFFF } == rgb & 0xFFFFFF } ?? 0
                    s += "<colorFilter dxfId=\"\(i)\"" + (fill ? "" : " cellColor=\"0\"") + "/>"
                }
            }
            s += "</filterColumn>"
        }
        return s + "</autoFilter>"
    }

    /// The metadata part Excel 365 writes for dynamic arrays: one XLDAPR
    /// type, one cell-metadata entry (cm="1").
    /// A part written with a prefix for SpreadsheetML's main namespace
    /// (`<x:worksheet xmlns:x="…/main"><x:row>` — some generators do),
    /// rewritten to the default namespace, so the pieces kept verbatim
    /// from it and the elements written fresh agree. Left as is, our
    /// `<row>` inside the kept `<x:worksheet>` is in no namespace at all,
    /// and Excel repairs the file.
    static func _unprefixMain(_ data: Data) -> Data {
        let main = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
        guard data.count > 5, data.starts(with: [0xEF, 0xBB, 0xBF]) || data.first == UInt8(ascii: "<"),
              var text = String(data: data, encoding: .utf8) else { return data }
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        // The root element's name and its prefix.
        var i = text.startIndex
        while let lt = text[i...].firstIndex(of: "<") {
            let next = text.index(after: lt)
            guard next < text.endIndex else { return data }
            if text[next] == "?" || text[next] == "!" { i = next; continue }
            let nameEnd = text[next...].firstIndex { $0 == " " || $0 == ">" || $0 == "/" } ?? text.endIndex
            let name = text[next ..< nameEnd]
            guard let colon = name.firstIndex(of: ":") else { return data }
            let prefix = String(name[..<colon])
            let close = text[lt...].firstIndex(of: ">") ?? text.endIndex
            let rootTag = text[lt ..< close]
            guard rootTag.containsSubstring("xmlns:\(prefix)=\"\(main)\"") else { return data }
            var out = text
                .replacingAll("<\(prefix):", with: "<")
                .replacingAll("</\(prefix):", with: "</")
                .replacingAll(" xmlns:\(prefix)=\"\(main)\"", with: "")
            // The default namespace, declared on the root.
            if let r = out.findRange(of: "<" + String(name[name.index(after: colon)...])) {
                out.insert(contentsOf: " xmlns=\"\(main)\"", at: r.upperBound)
            }
            return Data(out.utf8)
        }
        return data
    }

    /// A kept root tag with the relationships namespace declared, which the
    /// r:id attributes written here need; some generators declare it on the
    /// element instead (`<sheet … xmlns:r="…"/>`), which the kept root lacks.
    static func _withRels(_ root: String) -> String {
        guard !root.containsSubstring("xmlns:r="), let close = root.lastIndex(of: ">") else { return root }
        var r = root
        let at = r[r.index(before: close)] == "/" ? r.index(before: close) : close
        r.insert(contentsOf: " xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"", at: at)
        return r
    }

    /// Markup compatibility resolved the way a reader without the extension
    /// does: each mc:AlternateContent becomes its mc:Fallback's content (or
    /// nothing).
    static func _resolveAlternateContent(_ data: Data) -> Data {
        guard var text = String(data: data, encoding: .utf8), text.containsSubstring("<mc:AlternateContent") else { return data }
        while let open = text.findRange(of: "<mc:AlternateContent") {
            guard let end = text.findRange(of: "</mc:AlternateContent>", in: open.upperBound ..< text.endIndex) else { break }
            let block = String(text[open.lowerBound ..< end.upperBound])
            var replacement = ""
            if let fb = block.findRange(of: "<mc:Fallback"), let fbTag = block[fb.lowerBound...].firstIndex(of: ">"),
               let fbEnd = block.findRange(of: "</mc:Fallback>", in: fbTag ..< block.endIndex) {
                replacement = block[fb.lowerBound ..< fbTag].hasSuffix("/") ? "" : String(block[block.index(after: fbTag) ..< fbEnd.lowerBound])
            }
            text.replaceSubrange(open.lowerBound ..< end.upperBound, with: replacement)
        }
        return Data(text.utf8)
    }

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

    private static func _cellXML(_ a: CellAddress, _ c: Cell, dynamicCm: Int? = nil, rich: (text: String, xml: String)? = nil, stringIndex: (String) -> Int) -> String {
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
            // (A rich string whose text the user has not touched goes back as it was read.)
            if let rich, rich.text == t { return s + " t=\"s\"><v>\(stringIndex(_richMark + rich.xml))</v></c>" }
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

    /// Marks a shared-string entry that is a rich string's own XML, not plain text.
    static let _richMark = "\u{1}rich\u{1}"

    /// The inside of a shared string item as the file wrote it, or nil where it cannot be written back faithfully.
    static func _siXML(_ si: XNode) -> String? {
        func out(_ n: XNode) -> String? {
            if n.name.contains(":" as Character) { return nil }
            var a = n.attrs.keys.sorted().map { " \($0)=\"\(_esc(n.attrs[$0]!))\"" }.joined()
            if n.name == "t", n.attrs["xml:space"] == nil, n.text.first == " " || n.text.last == " " || n.text.containsSubstring("\n") { a += " xml:space=\"preserve\"" }
            var inner = ""
            for c in n.children { guard let x = out(c) else { return nil }; inner += x }
            return "<\(n.name)\(a)>" + inner + _esc(n.text) + "</\(n.name)>"
        }
        var all = ""
        for c in si.children { guard let x = out(c) else { return nil }; all += x }
        return all
    }

    private static func _sstXML(_ sst: [String]) -> String {
        var s = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<sst xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" count=\"\(sst.count)\" uniqueCount=\"\(sst.count)\">"
        for t in sst {
            if t.hasPrefix(_richMark) { s += "<si>\(t.dropFirst(_richMark.count))</si>"; continue }
            let space = t.first == " " || t.last == " " || t.containsSubstring("\n") ? " xml:space=\"preserve\"" : ""
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
        var styleXfs = src?.cellStyleXfs, styleNames = src?.cellStyles
        var linkXfId: String? = nil, newLinkXf: String? = nil
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
            // The font this one was derived from, child by child: what the change left alone (a theme colour and its
            // tint, the family, charset and scheme, a double underline, a script) is written as the file had it.
            var baseFont: [String: String] = [:]
            if let base, let fid = Int(base.xf.attrs["fontId"] ?? "0"), fid < fonts.count {
                for (name, text) in RawXML.split(Array(fonts[fid].utf8)).children { baseFont[name] = text }
            }
            let sameFace = base.map { $0.style.fontName == st.fontName } ?? false
            var font = "<font>"
            if st.bold { font += "<b/>" }
            if st.italic { font += "<i/>" }
            if st.strike { font += "<strike/>" }
            if st.underline {
                if let b = base, b.style.underline, b.style.accounting == st.accounting, let u = baseFont["u"] { font += u } else { font += "<u/>" }
            }
            if st.script != 0, let b = base, b.style.script == st.script, let v = baseFont["vertAlign"] { font += v }
            font += "<sz val=\"\(_num(book.fontSize(st) >= 1 ? book.fontSize(st) : 11))\"/>"
            if let b = base, b.style.color == st.color, let c = baseFont["color"] { font += c }
            else { font += st.color.map { "<color rgb=\"FF\(_hex($0))\"/>" } ?? "<color theme=\"1\"/>" }
            font += "<name val=\"\(_esc(book.fontName(st)))\"/>"
            font += sameFace ? (baseFont["family"] ?? "<family val=\"2\"/>") : "<family val=\"2\"/>"
            if sameFace { font += (baseFont["charset"] ?? "") + (baseFont["scheme"] ?? "") }
            else if st.fontName == nil && book.defaultFontName == nil { font += "<scheme val=\"minor\"/>" }
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
            // A side the change left alone (same line, kind and colour) is written as the file had it: theme colour, tint.
            var baseSides: [String: String] = [:]
            if let base, let bid = Int(base.xf.attrs["borderId"] ?? "0"), bid < borders.count {
                for (name, text) in RawXML.split(Array(borders[bid].utf8)).children { baseSides[name] = text }
            }
            func side(_ name: String, _ on: Bool) -> String {
                guard on else { return "<\(name)/>" }
                if let base, let kept = baseSides[name] {
                    let bb = base.style.borders
                    let was: Bool = name == "left" ? bb.left : name == "right" ? bb.right : name == "top" ? bb.top : bb.bottom
                    if was, bb.kinds[name] == b.kinds[name], bb.colors[name] == b.colors[name] { return kept }
                }
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
            var xfId = base?.xf.attrs["xfId"] ?? "0"
            if st.linkStyle {
                if linkXfId == nil {
                    // The file's own Hyperlink cell style (builtinId 8), or one added after the others.
                    if let id = styleNames.flatMap({ XNode.parse(Data($0.utf8)) })?.kids("cellStyle").first(where: { $0["builtinId"] == "8" })?["xfId"] { linkXfId = id }
                    else {
                        let count = styleXfs.flatMap { XNode.parse(Data($0.utf8)) }.map { $0.kids("xf").count } ?? 1
                        linkXfId = "\(count)"
                        newLinkXf = "<xf numFmtId=\"0\" fontId=\"\(fontId)\" fillId=\"0\" borderId=\"0\" applyNumberFormat=\"0\" applyFill=\"0\" applyBorder=\"0\" applyAlignment=\"0\" applyProtection=\"0\"/>"
                    }
                }
                xfId = linkXfId ?? "0"
            }
            var xf = "<xf numFmtId=\"\(fmtId)\" fontId=\"\(fontId)\" fillId=\"\(fillId)\" borderId=\"\(borderId)\" xfId=\"\(xfId)\""
            if st.pivotButton { xf += " pivotButton=\"1\"" }
            if fmtId != 0 { xf += " applyNumberFormat=\"1\"" }
            if fontId != 0 { xf += " applyFont=\"1\"" }
            if fillId != 0 { xf += " applyFill=\"1\"" }
            if borderId != 0 { xf += " applyBorder=\"1\"" }
            var align = ""
            switch st.hAlign { case .left: align += st.justify ? " horizontal=\"justify\"" : " horizontal=\"left\""; case .center: align += " horizontal=\"center\""; case .right: align += " horizontal=\"right\""; case .general: break }
            switch st.vAlign { case .top: align += " vertical=\"top\""; case .center: align += " vertical=\"center\""; case .bottom: break }
            if st.wrap { align += " wrapText=\"1\"" }
            if st.indent > 0 { align += " indent=\"\(st.indent)\"" }
            if st.rotation != 0 { align += " textRotation=\"\(st.rotation)\"" }
            // Alignment the change left alone keeps its indent, rotation…
            var alignment = align.isEmpty ? "" : "<alignment\(align)/>"
            if let base, st.hAlign == base.style.hAlign, st.vAlign == base.style.vAlign, st.wrap == base.style.wrap, st.justify == base.style.justify,
               st.indent == base.style.indent, st.rotation == base.style.rotation {
                alignment = base.xf.alignment ?? ""
            }
            var protection = base?.xf.protection ?? ""
            if st.locked != (base?.style.locked ?? true) || st.formulaHidden != (base?.style.formulaHidden ?? false) {
                protection = st.locked && !st.formulaHidden ? "" : "<protection" + (st.locked ? "" : " locked=\"0\"") + (st.formulaHidden ? " hidden=\"1\"" : "") + "/>"
            }
            if !protection.isEmpty { xf += " applyProtection=\"1\"" }
            let inner = alignment + protection
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
        func bumped(_ text: String, adding item: String, before close: String) -> String {
            var t = text
            if let r = t.findRange(of: " count=\""), let q = t.findRange(of: "\"", in: r.upperBound ..< t.endIndex), let n = Int(t[r.upperBound ..< q.lowerBound]) {
                t.replaceSubrange(r.upperBound ..< q.lowerBound, with: "\(n + 1)")
            }
            if let c = t.findRange(of: close) { t.insert(contentsOf: item, at: c.lowerBound) }
            return t
        }
        if let x = newLinkXf {
            styleXfs = bumped(styleXfs ?? "<cellStyleXfs count=\"1\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\"/></cellStyleXfs>", adding: x, before: "</cellStyleXfs>")
            styleNames = bumped(styleNames ?? "<cellStyles count=\"1\"><cellStyle name=\"Normal\" xfId=\"0\" builtinId=\"0\"/></cellStyles>",
                                adding: "<cellStyle name=\"Hyperlink\" xfId=\"\(linkXfId ?? "1")\" builtinId=\"8\"/>", before: "</cellStyles>")
        }
        s += styleXfs ?? "<cellStyleXfs count=\"1\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\"/></cellStyleXfs>"
        s += open("cellXfs", xfs.count) + xfs.joined() + "</cellXfs>"
        s += styleNames ?? "<cellStyles count=\"1\"><cellStyle name=\"Normal\" xfId=\"0\" builtinId=\"0\"/></cellStyles>"
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

    /// "yyyy-mm-dd" or "yyyy-mm-ddThh:mm[:ss]" as a date serial; nil when it is neither.
    static func _isoDateSerial(_ text: String) -> Double? {
        let t = text.trimmingSpaces()
        let parts = t.split(separator: "T", omittingEmptySubsequences: false).map(String.init)
        let d = parts[0].split(separator: "-", omittingEmptySubsequences: false).map { Int($0) }
        guard parts.count <= 2, d.count == 3, let y = d[0], let m = d[1], let day = d[2],
              m >= 1, m <= 12, day >= 1, day <= 31 else { return nil }
        var serial = ExcelDate.serial(y, m, day)
        if parts.count == 2 {
            let hms = parts[1].prefix(while: { $0 != "Z" && $0 != "+" }).split(separator: ":").map { Double($0) }
            guard hms.count >= 2, let h = hms[0], let mi = hms[1] else { return nil }
            serial += (h * 3600 + mi * 60 + (hms.count > 2 ? (hms[2] ?? 0) : 0)) / 86400
        }
        return serial
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

/// The selections a file carried (one per pane, activeCellId, ranges), handed back on save. The one in `activePane` follows the
/// active cell if that moved; nil when none belongs to that pane (the caller writes a fresh one).
func _selectionsXML(_ sels: [[String: String]], activePane: String, active: CellAddress) -> String? {
    // (A lone selection that names no pane is the file's whole view, whatever pane the frozen split makes active.)
    let lone = sels.count == 1 && sels[0]["pane"] == nil
    guard lone || sels.contains(where: { ($0["pane"] ?? "topLeft") == activePane }) else { return nil }
    var out = ""
    let last = lone ? 0 : sels.lastIndex { ($0["pane"] ?? "topLeft") == activePane }
    for (i, var sel) in sels.enumerated() {
        if i == last, (sel["activeCell"] ?? "A1") != active.a1 {
            sel["activeCell"] = active.a1; sel["sqref"] = active.a1; sel["activeCellId"] = nil
        }
        out += "<selection" + sel.sorted { $0.key < $1.key }.map { " \($0.key)=\"\(Xlsx._esc($0.value))\"" }.joined() + "/>"
    }
    return out
}
