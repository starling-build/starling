// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Comma- and tab-separated values: RFC 4180 quoting (fields in double
// quotes, "" for a quote, line breaks inside quotes), CRLF or LF. Reading
// types each field as if it had been typed into the cell; writing gives
// each cell's displayed text, as Excel's "CSV (Comma delimited)" does.

enum Csv {
    static func parse(_ text: String, separator: Character = ",") -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var i = text.startIndex
        var sawAny = false
        while i < text.endIndex {
            let ch = text[i]
            sawAny = true
            if inQuotes {
                if ch == "\"" {
                    let n = text.index(after: i)
                    if n < text.endIndex, text[n] == "\"" { field.append("\""); i = text.index(after: n); continue }
                    inQuotes = false
                } else {
                    field.append(ch)
                }
            } else if ch == "\"" && field.isEmpty {
                inQuotes = true
            } else if ch == separator {
                row.append(field); field = ""
            } else if ch == "\n" || ch == "\r" || ch == "\r\n" {
                row.append(field); field = ""
                rows.append(row); row = []
                if ch == "\r" {
                    let n = text.index(after: i)
                    if n < text.endIndex, text[n] == "\n" { i = n }
                }
            } else {
                field.append(ch)
            }
            i = text.index(after: i)
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        else if !sawAny { return [] }
        return rows
    }

    /// A workbook's sheet from CSV text.
    static func read(_ text: String, name: String = "Sheet1") -> Workbook {
        let book = Workbook(sheets: [Worksheet(name: name)])
        let c = WorkbookController()
        c.load(book)
        var items: [(CellAddress, String)] = []
        let rows = parse(text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text,
                         separator: _sniff(text))
        for (r, row) in rows.enumerated() where r < CellAddress.maxRows {
            for (col, field) in row.enumerated() where col < CellAddress.maxCols && !field.isEmpty {
                items.append((CellAddress(row: r, col: col), field))
            }
        }
        c.setInputs(items)
        return c.book
    }

    /// Commas unless the first line has more tabs or semicolons.
    private static func _sniff(_ text: String) -> Character {
        let first = text.prefix { $0 != "\n" && $0 != "\r" }
        let commas = first.filter { $0 == "," }.count
        let tabs = first.filter { $0 == "\t" }.count
        let semis = first.filter { $0 == ";" }.count
        if tabs > commas && tabs >= semis { return "\t" }
        if semis > commas { return ";" }
        return ","
    }

    static func write(_ sheet: Worksheet, book: Workbook, separator: Character = ",") -> String {
        guard !sheet.cells.isEmpty else { return "" }
        let used = sheet.usedExtent
        var out = ""
        for r in 0 ... used.row {
            var fields: [String] = []
            for col in 0 ... used.col {
                let a = CellAddress(row: r, col: col)
                guard let cell = sheet.cells[a] else { fields.append(""); continue }
                var s = NumberFormat.display(cell.value, book.style(cell.style).numberFormat, width: 255).text
                if case .number(let n) = cell.value, book.style(cell.style).numberFormat == "General" { s = NumberFormat.full(n) }
                if s.contains(separator) || s.contains("\"") || s.contains("\n") || s.contains("\r") {
                    s = "\"" + s.replacingAll("\"", with: "\"\"") + "\""
                }
                fields.append(s)
            }
            out += fields.joined(separator: String(separator)) + "\r\n"
        }
        return out
    }
}
