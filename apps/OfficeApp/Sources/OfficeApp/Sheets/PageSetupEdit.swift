// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-PR-1: editing a sheet's page setup. The setup lives in the elements the
// sheet keeps as written (pageMargins, pageSetup, printOptions, sheetPr); an
// edit changes only the attributes it names, so the printer's own settings,
// DPI, copies and everything else the file carried stay as they were.

import Foundation

/// What a page-setup dialog can change. A nil field is left as it is.
struct PageSetupChange: Equatable {
    var landscape: Bool? = nil
    /// Windows paper number (1 Letter, 9 A4, ...).
    var paperSize: Int? = nil
    /// Inches.
    var left: Double? = nil, right: Double? = nil, top: Double? = nil, bottom: Double? = nil
    var header: Double? = nil, footer: Double? = nil
    /// Percent, 10...400; turns fit-to-pages off.
    var scale: Int? = nil
    /// Fit to N pages wide and tall (0 = as many as it takes); replaces the scale.
    var fitWide: Int? = nil, fitTall: Int? = nil
    var gridlines: Bool? = nil, headings: Bool? = nil
    var centerHorizontally: Bool? = nil, centerVertically: Bool? = nil
    var overThenDown: Bool? = nil
    var headerFooter: HeaderFooter? = nil
}

enum PageSetupEdit {
    /// `element` with its start tag's attributes set (value) or removed (nil). Creates `<name/>` when absent.
    static func setAttributes(_ element: String?, name: String, _ attrs: [(String, String?)]) -> String {
        var text = element ?? "<\(name)/>"
        guard let open = text.firstIndex(of: "<"), let close = text.firstIndex(of: ">") else { return text }
        var tag = String(text[text.index(after: open)..<close])
        let selfClosing = tag.hasSuffix("/")
        if selfClosing { tag.removeLast() }
        // Split "name a="1" b='2'" into the name and its attributes, in order.
        var rest = Substring(tag)
        let nameEnd = rest.firstIndex { $0 == " " || $0 == "\n" || $0 == "\t" } ?? rest.endIndex
        let elementName = String(rest[rest.startIndex..<nameEnd])
        rest = rest[nameEnd...]
        var pairs: [(String, String)] = []
        while let eq = rest.firstIndex(of: "=") {
            let key = rest[rest.startIndex..<eq].trimmingSpaces()
            let after = rest[rest.index(after: eq)...]
            guard let q = after.first, q == "\"" || q == "'", let end = after.dropFirst().firstIndex(of: q) else { break }
            pairs.append((key, String(after[after.index(after: after.startIndex)..<end])))
            rest = after[after.index(after: end)...]
        }
        for (k, v) in attrs {
            if let i = pairs.firstIndex(where: { $0.0 == k }) {
                if let v { pairs[i].1 = v } else { pairs.remove(at: i) }
            } else if let v { pairs.append((k, v)) }
        }
        let attrText = pairs.map { " \($0.0)=\"\($0.1)\"" }.joined()
        let newTag = "<" + elementName + attrText + (selfClosing ? "/>" : ">")
        text.replaceSubrange(open...close, with: newTag)
        return text
    }
}

private extension Substring {
    func trimmingSpaces() -> String { String(self).split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).joined() }
}

extension Worksheet {
    func applyPageSetup(_ c: PageSetupChange) {
        if let hf = c.headerFooter {
            keptElements.removeAll { $0.name == "headerFooter" }
            if let x = hf.xml() { keptElements.append(("headerFooter", x)) }
        }
        func edit(_ name: String, _ attrs: [(String, String?)]) {
            guard !attrs.isEmpty else { return }
            if let i = keptElements.firstIndex(where: { $0.name == name }) {
                keptElements[i].text = PageSetupEdit.setAttributes(keptElements[i].text, name: name, attrs)
            } else if attrs.contains(where: { $0.1 != nil }) {
                keptElements.append((name, PageSetupEdit.setAttributes(nil, name: name, attrs)))
            }
        }
        func inch(_ v: Double) -> String { "\((v * 1000).rounded() / 1000)" }
        func flag(_ b: Bool) -> String? { b ? "1" : nil }
        var margins: [(String, String?)] = []
        if let v = c.left { margins.append(("left", inch(v))) }
        if let v = c.right { margins.append(("right", inch(v))) }
        if let v = c.top { margins.append(("top", inch(v))) }
        if let v = c.bottom { margins.append(("bottom", inch(v))) }
        if let v = c.header { margins.append(("header", inch(v))) }
        if let v = c.footer { margins.append(("footer", inch(v))) }
        if !margins.isEmpty {
            // pageMargins needs all six; fill the ones the file had not written with Excel's Normal.
            let have = keptElements.first { $0.name == "pageMargins" }?.text ?? ""
            for (k, d) in [("left", 0.7), ("right", 0.7), ("top", 0.75), ("bottom", 0.75), ("header", 0.3), ("footer", 0.3)]
            where !margins.contains(where: { $0.0 == k }) && !have.containsSubstring(" \(k)=") { margins.append((k, inch(d))) }
            edit("pageMargins", margins)
        }
        var setup: [(String, String?)] = []
        if let v = c.landscape { setup.append(("orientation", v ? "landscape" : "portrait")) }
        if let v = c.paperSize { setup.append(("paperSize", String(v))); setup.append(("usePrinterDefaults", nil)) }
        if let v = c.overThenDown { setup.append(("pageOrder", v ? "overThenDown" : "downThenOver")) }
        var fit: Bool? = nil
        if let s = c.scale { setup.append(("scale", String(min(400, max(10, s))))); fit = false }
        if c.fitWide != nil || c.fitTall != nil {
            setup.append(("fitToWidth", c.fitWide.map { String(max(0, $0)) } ?? "1"))
            setup.append(("fitToHeight", c.fitTall.map { String(max(0, $0)) } ?? "1"))
            fit = true
        }
        edit("pageSetup", setup)
        if let fit {
            let i = keptElements.firstIndex { $0.name == "sheetPr" }
            let sp = i.map { keptElements[$0].text } ?? "<sheetPr/>"
            keptElements.removeAll { $0.name == "sheetPr" }
            keptElements.append(("sheetPr", Self._withFitToPage(sp, fit)))
        }
        var opts: [(String, String?)] = []
        if let v = c.gridlines { opts.append(("gridLines", flag(v))) }
        if let v = c.headings { opts.append(("headings", flag(v))) }
        if let v = c.centerHorizontally { opts.append(("horizontalCentered", flag(v))) }
        if let v = c.centerVertically { opts.append(("verticalCentered", flag(v))) }
        edit("printOptions", opts)
    }

    /// `<pageSetUpPr fitToPage=…/>` inside a sheetPr, which also holds the tab colour and outline settings.
    static func _withFitToPage(_ sheetPr: String, _ fit: Bool) -> String {
        var s = sheetPr
        if let r = s.rangeOfSubstring("<pageSetUpPr") , let e = s.rangeOfSubstring("/>", in: r.upperBound..<s.endIndex) {
            let tag = String(s[r.lowerBound..<e.upperBound])
            s.replaceSubrange(r.lowerBound..<e.upperBound, with: PageSetupEdit.setAttributes(tag, name: "pageSetUpPr", [("fitToPage", fit ? "1" : nil)]))
            return s
        }
        guard fit else { return s }
        if s.hasSuffix("/>") { return String(s.dropLast(2)) + "><pageSetUpPr fitToPage=\"1\"/></sheetPr>" }
        // Schema order inside sheetPr: tabColor, outlinePr, pageSetUpPr.
        if let e = s.rangeOfSubstring("</sheetPr>") { s.replaceSubrange(e, with: "<pageSetUpPr fitToPage=\"1\"/></sheetPr>") }
        return s
    }
}

extension WorkbookController {
    /// One undoable change to the active sheet's page setup.
    func setPageSetup(_ change: PageSetupChange, printNames: PageSetupForm.PrintNames? = nil) {
        let ws = sheet
        structural {
            ws.applyPageSetup(change)
            if let n = printNames { _printNames(area: n.area, rows: n.rows, cols: n.cols) }
        }
    }
}

extension String {
    func trimmingSpaces() -> String { split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).joined() }
}

extension WorkbookController {
    /// The sheet's Windows paper number (Letter if the file names none).
    var paperNumber: Int {
        let el = sheet.keptElements.first { $0.name == "pageSetup" }
        guard let t = el?.text, let r = t.rangeOfSubstring("paperSize=\"") else { return 1 }
        let digits = t[r.upperBound...].prefix { $0.isNumber }
        return Int(digits) ?? 1
    }
}

// MARK: Print area and titles (the sheet's built-in defined names)

extension WorkbookController {
    private func _builtIn(_ name: String, _ text: String?) {
        let i = activeSheet
        book.fileNames.removeAll { $0.name == name && $0.localSheet == i }
        if let text { book.fileNames.append(DefinedName(name: name, localSheet: i, attrs: [:], text: text)) }
    }
    private var _quotedSheet: String { "'" + sheet.name.replacingAll("'", with: "''") + "'" }

    /// The print area: one range, or nil to print the whole sheet again.
    func setPrintArea(_ r: CellRange?) { structural { _printNames(area: r, rows: nil, cols: nil, titles: false) } }

    fileprivate func _printNames(area r: CellRange?, rows: ClosedRange<Int>?, cols: ClosedRange<Int>?, titles: Bool = true) {
        if let r {
            let a = CellAddress.columnName(r.left), b = CellAddress.columnName(r.right)
            _builtIn("_xlnm.Print_Area", "\(_quotedSheet)!$\(a)$\(r.top + 1):$\(b)$\(r.bottom + 1)")
        } else { _builtIn("_xlnm.Print_Area", nil) }
        if titles { _titles(rows: rows, cols: cols) }
    }

    /// Rows and columns that repeat on every page (zero-based, inclusive); nil for none.
    func setPrintTitles(rows: ClosedRange<Int>?, cols: ClosedRange<Int>?) { structural { _titles(rows: rows, cols: cols) } }

    fileprivate func _titles(rows: ClosedRange<Int>?, cols: ClosedRange<Int>?) {
        do {
            var parts: [String] = []
            if let c = cols { parts.append("\(_quotedSheet)!$\(CellAddress.columnName(c.lowerBound)):$\(CellAddress.columnName(c.upperBound))") }
            if let r = rows { parts.append("\(_quotedSheet)!$\(r.lowerBound + 1):$\(r.upperBound + 1)") }
            _builtIn("_xlnm.Print_Titles", parts.isEmpty ? nil : parts.joined(separator: ","))
        }
    }
}

/// Manual page breaks: `<brk id="N"/>` breaks above 0-based row N (left of column N).
enum PageBreakEdit {
    static func ids(_ xml: String?) -> [Int] {
        guard let x = xml else { return [] }
        var out: [Int] = []
        var rest = x
        while let r = rest.rangeOfSubstring("<brk ") {
            rest = String(rest[r.upperBound...])
            if let a = rest.rangeOfSubstring("id=\"") {
                let tail = String(rest[a.upperBound...])
                if let n = Int(tail.prefix { $0.isNumber }) { out.append(n) }
            }
        }
        return out
    }
    static func xml(_ name: String, _ ids: [Int], max: Int) -> String? {
        let s = Set(ids).sorted()
        if s.isEmpty { return nil }
        let items = s.map { "<brk id=\"\($0)\" max=\"\(max)\" man=\"1\"/>" }.joined()
        return "<\(name) count=\"\(s.count)\" manualBreakCount=\"\(s.count)\">\(items)</\(name)>"
    }
}

extension Worksheet {
    func setBreaks(_ name: String, _ ids: [Int], max: Int) {
        keptElements.removeAll { $0.name == name }
        if let x = PageBreakEdit.xml(name, ids, max: max) { keptElements.append((name, x)) }
    }
    func breakIds(_ name: String) -> [Int] { PageBreakEdit.ids(keptElements.first { $0.name == name }?.text) }
}

extension WorkbookController {
    /// Break the page above `row` and left of `col` (0-based). Row/col 0 add nothing on that axis.
    func insertPageBreak(row: Int, col: Int) {
        let ws = sheet
        structural {
            if row > 0 { ws.setBreaks("rowBreaks", ws.breakIds("rowBreaks") + [row], max: 16383) }
            if col > 0 { ws.setBreaks("colBreaks", ws.breakIds("colBreaks") + [col], max: 1048575) }
        }
    }
    /// Take away the breaks at `row` and `col`.
    func removePageBreak(row: Int, col: Int) {
        let ws = sheet
        structural {
            ws.setBreaks("rowBreaks", ws.breakIds("rowBreaks").filter { $0 != row }, max: 16383)
            ws.setBreaks("colBreaks", ws.breakIds("colBreaks").filter { $0 != col }, max: 1048575)
        }
    }
    func resetPageBreaks() {
        let ws = sheet
        structural { ws.setBreaks("rowBreaks", [], max: 0); ws.setBreaks("colBreaks", [], max: 0) }
    }
}
