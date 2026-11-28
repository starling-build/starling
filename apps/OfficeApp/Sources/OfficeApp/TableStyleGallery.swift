// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import OfficeText
import FlutterSwiftBridge

/// Table Design > Table Styles (W-TB-4): Word's built-in table styles. A style is added to the document as Word writes it
/// (its theme colours recomputed from the document's theme) and the table names it, so Word draws it as its own. What the
/// style gives each cell (borders, fills, the text's bold and colour) is worked out by the same reader that opens a Word
/// file, so a styled table looks the same here whether it was made here or opened.
enum TableStyleGallery {
    struct Entry: Equatable {
        let id: String
        let name: String
        /// 1-6 for an accent variant, 0 for the plain one.
        let accent: Int
    }

    /// Every controller asks this for a style's look (Table Styles, Table Style Options).
    static func install() {
        if RichDocumentController.sharedTableStyleLookResolver == nil {
            RichDocumentController.sharedTableStyleLookResolver = { resolve($0, table: $1, style: $2, look: $3) }
        }
    }

    /// The gallery's sections, as Word groups them.
    static var groups: [(String, [Entry])] {
        func entries(_ prefix: String) -> [Entry] {
            TableStyleCatalog.families.filter { $0.hasPrefix(prefix) }.flatMap { fam in
                ([fam] + (1 ... 6).map { "\(fam)-Accent\($0)" }).compactMap(entry)
            }
        }
        return [("Plain Tables", TableStyleCatalog.plain.compactMap(entry)), ("Grid Tables", entries("Grid")), ("List Tables", entries("List"))]
    }

    static func entry(_ id: String) -> Entry? {
        guard let x = xml(id) else { return nil }
        var name = attribute(x, "w:name", "w:val") ?? id
        name = name.replacingAll(" Accent ", with: " - Accent ")
        var accent = 0
        if let r = id.rangeOfSubstring("-Accent"), let n = Int(id[r.upperBound...]) { accent = n }
        return Entry(id: id, name: name, accent: accent)
    }

    /// A style's definition as Word writes it. The Accent 2-6 variants are Accent 1's with the accent swapped: Word's
    /// own differ only in that (and in the colours, which `themed` recomputes).
    static func xml(_ id: String) -> String? {
        if let x = TableStyleCatalog.xml[id] { return x }
        // Clear: Word's default table style, which draws nothing (the same definition a save adds).
        if id == "TableNormal" {
            return #"<w:style w:type="table" w:default="1" w:styleId="TableNormal"><w:name w:val="Normal Table"/><w:uiPriority w:val="99"/><w:semiHidden/><w:unhideWhenUsed/><w:tblPr><w:tblInd w:w="0" w:type="dxa"/><w:tblCellMar><w:top w:w="0" w:type="dxa"/><w:left w:w="108" w:type="dxa"/><w:bottom w:w="0" w:type="dxa"/><w:right w:w="108" w:type="dxa"/></w:tblCellMar></w:tblPr></w:style>"#
        }
        guard let r = id.rangeOfSubstring("-Accent"), let n = Int(id[r.upperBound...]), (2 ... 6).contains(n),
              let base = TableStyleCatalog.xml[String(id[..<r.lowerBound]) + "-Accent1"] else { return nil }
        return base.replacingAll("accent1", with: "accent\(n)").replacingAll("Accent1", with: "Accent\(n)")
            .replacingAll("Accent 1", with: "Accent \(n)")
    }

    /// Give the caret's table the style `id`, one undo step.
    static func apply(_ id: String, to c: RichDocumentController) {
        install()
        guard let raw = xml(id) else { return }
        let hasTheme = c.document.keptParts.keys.contains { $0.hasPrefix("word/theme/") }
        c.applyTableStyle(id, xml: themed(raw, palette: palette(of: c.document)),
                          theme: hasTheme ? nil : Data(DocxFormat._defaultThemePart().utf8))
    }

    /// The document's theme colours: its theme part's, else the theme a save writes for it.
    static func palette(of doc: RichDocument) -> [String: (Int, Int, Int)] {
        let parts = doc.keptParts.filter { $0.key.hasPrefix("word/theme/") && $0.key.hasSuffix(".xml") }
            .sorted { ($0.key == NamedTableState.themePath ? "" : $0.key) < ($1.key == NamedTableState.themePath ? "" : $1.key) }
            .map { ZipEntry(name: $0.key, data: $0.value) }
        let p = DocxFormat._themePalette(parts)
        return p.isEmpty ? DocxFormat._themePalette([ZipEntry(name: NamedTableState.themePath, data: Data(DocxFormat._defaultThemePart().utf8))]) : p
    }

    /// The menu swatch: the accent, or the theme's text colour for a plain style.
    static func swatch(_ e: Entry, palette: [String: (Int, Int, Int)]) -> Color {
        guard let c = palette[e.accent == 0 ? "dk1" : "accent\(e.accent)"] else { return Color(0xFF000000) }
        let rgb: Int64 = Int64(c.0) << 16 | Int64(c.1) << 8 | Int64(c.2)
        return Color(0xFF00_0000 | rgb)
    }

    // MARK: Theme colours

    /// `xml` with every theme-linked colour (w:themeFill / w:themeColor and their tints and shades) recomputed from
    /// `palette` into the hex beside it, as Word writes a style into a document of that theme.
    static func themed(_ xml: String, palette: [String: (Int, Int, Int)]) -> String {
        var out = ""
        var rest = Substring(xml)
        while let lt = rest.firstIndex(of: "<") {
            out.append(contentsOf: rest[..<lt])
            guard let gt = rest[lt...].firstIndex(of: ">") else { break }
            let tag = String(rest[lt ... gt])
            out += tag.containsSubstring(" w:theme") ? recolored(tag, palette) : tag
            rest = rest[rest.index(after: gt)...]
        }
        out.append(contentsOf: rest)
        return out
    }

    static func recolored(_ tag: String, _ palette: [String: (Int, Int, Int)]) -> String {
        var t = tag
        if let slot = value(t, "w:themeFill"), let h = hex(slot, tint: value(t, "w:themeFillTint"), shade: value(t, "w:themeFillShade"), palette) {
            t = setting(t, "w:fill", h)
        }
        if let slot = value(t, "w:themeColor"), let h = hex(slot, tint: value(t, "w:themeTint"), shade: value(t, "w:themeShade"), palette) {
            t = setting(t, t.hasPrefix("<w:color ") ? "w:val" : "w:color", h)
        }
        return t
    }

    static func hex(_ slot: String, tint: String?, shade: String?, _ palette: [String: (Int, Int, Int)]) -> String? {
        let name = ["dark1": "dk1", "light1": "lt1", "dark2": "dk2", "light2": "lt2", "hyperlink": "hlink",
                    "followedHyperlink": "folHlink"][slot] ?? slot
        guard let v = DocxFormat._themeBackground(name, tint: tint, shade: shade, palette: palette) else { return nil }
        let s = String(v, radix: 16, uppercase: true)
        return String(repeating: "0", count: max(0, 6 - s.count)) + s
    }

    static func value(_ tag: String, _ name: String) -> String? {
        guard let r = tag.rangeOfSubstring(" \(name)=\""), let e = tag.rangeOfSubstring("\"", in: r.upperBound ..< tag.endIndex) else { return nil }
        return String(tag[r.upperBound ..< e.lowerBound])
    }

    static func setting(_ tag: String, _ name: String, _ v: String) -> String {
        guard let r = tag.rangeOfSubstring(" \(name)=\""), let e = tag.rangeOfSubstring("\"", in: r.upperBound ..< tag.endIndex) else { return tag }
        var t = tag
        t.replaceSubrange(r.upperBound ..< e.lowerBound, with: v)
        return t
    }

    /// The `attr` of the first `<element ...>` in `xml`.
    static func attribute(_ xml: String, _ element: String, _ attr: String) -> String? {
        guard let r = xml.rangeOfSubstring("<\(element) "), let e = xml.rangeOfSubstring(">", in: r.upperBound ..< xml.endIndex) else { return nil }
        return value(String(xml[r.lowerBound ..< e.upperBound]), attr)
    }

    /// The style's own cell shading (its root w:tcPr, outside every conditional part).
    static func rootFill(_ xml: String) -> Color? {
        let root = xml.rangeOfSubstring("<w:tblStylePr").map { String(xml[..<$0.lowerBound]) } ?? xml
        guard let tc = root.rangeOfSubstring("<w:tcPr>") else { return nil }
        let tcPr = String(root[tc.lowerBound...])
        guard let fill = attribute(tcPr, "w:shd", "w:fill"), fill != "auto", let v = Int64(fill, radix: 16) else { return nil }
        return Color(0xFF00_0000 | v)
    }

    // MARK: The look, through the reader

    /// What style `id` (nil: none) gives table `t` of `doc` under Table Style Options `look`: a throwaway document with a
    /// table of the same rows and columns that names the style is saved and read back, and the reader's result taken.
    static func resolve(_ doc: RichDocument, table t: String, style id: String?, look: Int) -> TableStyleLook? {
        let cells = doc.paragraphs.compactMap(\.cell).filter { $0.table == t }
        guard let rows = cells.map({ $0.row + $0.rowSpan }).max() else { return nil }
        let cols = max(doc.tableColumns[t]?.count ?? 0, cells.map { $0.column + $0.span }.max() ?? 1)
        let pc = RichDocumentController(plainText: "")
        pc.insertTable(rows: rows, columns: cols)
        var d = pc.document
        guard let pt = d.paragraphs.compactMap(\.cell).first?.table else { return nil }
        for i in d.paragraphs.indices where d.paragraphs[i].cell != nil {
            d.paragraphs[i].text = "x"
            d.paragraphs[i].runs = [Run(length: 1)]
        }
        d.keptTableStyles = doc.keptTableStyles
        for (k, v) in doc.keptParts where k.hasPrefix("word/theme/") { d.keptParts[k] = v }
        var s = d.tableStyles[pt] ?? TableStyle()
        s.look = look
        s.inheritedBordersKey = s.bordersKey
        d.tableStyles[pt] = s
        d.tableStyleIds[pt] = id
        // The reader keeps a few facts of the file it last read; the document on screen is not this one.
        let saved = (DocxFormat._mathDefaultJc, DocxFormat._exactAtAscent, DocxFormat._latinLangKorean, DocxFormat._bidiLangHebrew, DocxFormat._themeColors)
        defer {
            (DocxFormat._mathDefaultJc, DocxFormat._exactAtAscent, DocxFormat._latinLangKorean, DocxFormat._bidiLangHebrew, DocxFormat._themeColors) = saved
        }
        guard let data = try? DocxFormat.write(d, pageSetup: .letter), let back = try? DocxFormat.read(data).document,
              let bt = back.paragraphs.compactMap(\.cell).first?.table else { return nil }
        var chars = Array(repeating: Array(repeating: CellCharLook(), count: cols), count: rows)
        for p in back.paragraphs {
            guard let c = p.cell, c.table == bt, c.row < rows, c.column < cols, let r = p.runs.first else { continue }
            chars[c.row][c.column] = CellCharLook(r.style)
        }
        var fills = back.tableCondFills[bt]
        if let id, let x = doc.keptTableStyles[id], let base = rootFill(x) {
            var f = fills ?? TableCondFills(byType: [:])
            f.byType["wholeTable"] = base
            fills = f
        }
        return TableStyleLook(borders: back.tableStyles[bt] ?? TableStyle(), fills: fills, chars: chars)
    }
}
