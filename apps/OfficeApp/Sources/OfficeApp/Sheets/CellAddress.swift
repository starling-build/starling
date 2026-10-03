// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Cell addresses: A1, $B$2, A1:C10, whole columns (A:C) and rows (3:5),
// sheet-qualified ('Q1 Budget'!B4). Rows and columns are zero-based here
// and one-based / lettered in text, as Excel shows them. Excel's limits
// (1,048,576 rows, 16,384 columns — XFD) bound everything; both fit a
// 32-bit Int, which is what the wasm build has.

/// A cell's position on a sheet, zero-based.
struct CellAddress: Hashable, Comparable, Sendable {
    var row: Int
    var col: Int

    static let maxRows = 1_048_576
    static let maxCols = 16_384

    init(row: Int, col: Int) {
        self.row = row
        self.col = col
    }

    /// "B3" → (row 2, col 1). Absolute markers are accepted and ignored.
    init?(_ text: String) {
        guard let r = CellRefText.parse(Substring(text)), r.rest.isEmpty,
              let row = r.row, let col = r.col else { return nil }
        self.init(row: row, col: col)
    }

    var a1: String { CellAddress.columnName(col) + String(row + 1) }

    static func < (a: CellAddress, b: CellAddress) -> Bool {
        a.row != b.row ? a.row < b.row : a.col < b.col
    }

    /// 0 → "A", 25 → "Z", 26 → "AA", 16383 → "XFD".
    static func columnName(_ col: Int) -> String {
        var n = col + 1
        var out: [Character] = []
        while n > 0 {
            let r = (n - 1) % 26
            out.append(Character(UnicodeScalar(UInt8(65 + r))))
            n = (n - 1) / 26
        }
        return String(out.reversed())
    }

    /// "A" → 0, "xfd" → 16383; nil for anything else.
    static func columnIndex(_ letters: Substring) -> Int? {
        guard !letters.isEmpty, letters.count <= 3 else { return nil }
        var n = 0
        for ch in letters {
            guard let a = ch.asciiValue else { return nil }
            let up = a >= 97 ? a - 32 : a
            guard up >= 65 && up <= 90 else { return nil }
            n = n * 26 + Int(up - 64)
        }
        let col = n - 1
        return col < maxCols ? col : nil
    }
}

/// A rectangle of cells, inclusive at both ends.
struct CellRange: Hashable, Sendable {
    var top: Int
    var left: Int
    var bottom: Int
    var right: Int

    init(top: Int, left: Int, bottom: Int, right: Int) {
        self.top = min(top, bottom)
        self.bottom = max(top, bottom)
        self.left = min(left, right)
        self.right = max(left, right)
    }

    init(_ a: CellAddress, _ b: CellAddress) {
        self.init(top: a.row, left: a.col, bottom: b.row, right: b.col)
    }

    init(_ a: CellAddress) { self.init(a, a) }

    var topLeft: CellAddress { CellAddress(row: top, col: left) }
    var bottomRight: CellAddress { CellAddress(row: bottom, col: right) }
    var rows: Int { bottom - top + 1 }
    var cols: Int { right - left + 1 }
    var isSingle: Bool { top == bottom && left == right }

    func contains(_ a: CellAddress) -> Bool {
        a.row >= top && a.row <= bottom && a.col >= left && a.col <= right
    }

    func intersects(_ o: CellRange) -> Bool {
        !(o.right < left || o.left > right || o.bottom < top || o.top > bottom)
    }

    /// The cells both ranges cover; nil when they share none.
    func intersection(_ o: CellRange) -> CellRange? {
        guard intersects(o) else { return nil }
        return CellRange(top: max(top, o.top), left: max(left, o.left), bottom: min(bottom, o.bottom), right: min(right, o.right))
    }

    /// "A1:C3", or "B2" for a single cell; whole columns and rows as
    /// "A:C" and "3:5".
    var a1: String {
        if top == 0 && bottom == CellAddress.maxRows - 1 {
            return CellAddress.columnName(left) + ":" + CellAddress.columnName(right)
        }
        if left == 0 && right == CellAddress.maxCols - 1 {
            return "\(top + 1):\(bottom + 1)"
        }
        if isSingle { return topLeft.a1 }
        return topLeft.a1 + ":" + bottomRight.a1
    }

    init?(_ text: String) {
        let parts = text.split(separator: ":", maxSplits: 1)
        if parts.count == 1 {
            guard let a = CellAddress(String(parts[0])) else { return nil }
            self.init(a)
            return
        }
        guard let a = CellRefText.parse(parts[0]), a.rest.isEmpty,
              let b = CellRefText.parse(parts[1]), b.rest.isEmpty else { return nil }
        switch (a.row, a.col, b.row, b.col) {
        case let (r1?, c1?, r2?, c2?): self.init(top: r1, left: c1, bottom: r2, right: c2)
        case let (nil, c1?, nil, c2?): self.init(top: 0, left: c1, bottom: CellAddress.maxRows - 1, right: c2)
        case let (r1?, nil, r2?, nil): self.init(top: r1, left: 0, bottom: r2, right: CellAddress.maxCols - 1)
        default: return nil
        }
    }
}

/// The text form of one end of a reference: optional `$`, letters,
/// optional `$`, digits — either half may be missing for whole
/// columns/rows. Shared by the address parsers and the formula tokenizer.
enum CellRefText {
    struct Parsed {
        var row: Int?
        var col: Int?
        var rowAbs: Bool
        var colAbs: Bool
        var rest: Substring
    }

    static func parse(_ s: Substring) -> Parsed? {
        var i = s.startIndex
        var colAbs = false, rowAbs = false
        if i < s.endIndex, s[i] == "$" { colAbs = true; i = s.index(after: i) }
        let lettersStart = i
        while i < s.endIndex, let a = s[i].asciiValue, (a >= 65 && a <= 90) || (a >= 97 && a <= 122) {
            i = s.index(after: i)
        }
        let letters = s[lettersStart ..< i]
        var col: Int? = nil
        if !letters.isEmpty {
            guard let c = CellAddress.columnIndex(letters) else { return nil }
            col = c
        } else if colAbs {
            // "$3" — the $ belonged to the row.
            colAbs = false
            rowAbs = true
        }
        if i < s.endIndex, s[i] == "$" {
            guard !rowAbs else { return nil }
            rowAbs = true
            i = s.index(after: i)
        }
        let digitsStart = i
        while i < s.endIndex, let a = s[i].asciiValue, a >= 48 && a <= 57 { i = s.index(after: i) }
        let digits = s[digitsStart ..< i]
        var row: Int? = nil
        if !digits.isEmpty {
            guard digits.count <= 7, let n = Int(digits), n >= 1, n <= CellAddress.maxRows else { return nil }
            row = n - 1
        } else if rowAbs && col != nil && letters.isEmpty == false {
            return nil  // "A$" alone
        }
        if row == nil && col == nil { return nil }
        return Parsed(row: row, col: col, rowAbs: rowAbs, colAbs: colAbs, rest: s[i...])
    }
}
