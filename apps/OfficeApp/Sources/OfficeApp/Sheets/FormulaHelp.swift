// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-CE-1: what the cell editor shows while a formula is typed. A function-name list under the cell (Tab
// accepts), a tip naming the arguments of the function the caret is in, and each cell reference in its own
// colour (the text and a border on the grid). Pure text work; the grid draws it.

import Foundation

enum FormulaHelp {
    /// The names the list offers: every function the engine can calculate.
    static let functionNames: [String] = SheetFunctions.table.keys.filter { !$0.hasPrefix("_") }.sorted()

    private static func _isNameChar(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" || c == "." }

    /// Whether `caret` sits inside a quoted string.
    private static func _inString(_ t: [Character], _ caret: Int) -> Bool {
        var inside = false
        for c in t[0 ..< min(caret, t.count)] where c == "\"" { inside.toggle() }
        return inside
    }

    struct Completion: Equatable {
        /// Where the typed part of the name starts.
        var start: Int
        var matches: [String]
    }

    /// The names that continue what is typed before the caret: a letter-led word after `=`, an operator, `(`
    /// or `,`. Nil when nothing is being named.
    static func completion(_ t: [Character], caret: Int, limit: Int = 12) -> Completion? {
        guard t.first == "=", caret <= t.count, caret > 1, !_inString(t, caret) else { return nil }
        if caret < t.count, _isNameChar(t[caret]) { return nil }
        var s = caret
        while s > 1, _isNameChar(t[s - 1]) { s -= 1 }
        guard s < caret, t[s].isLetter else { return nil }
        // A word after "!" or "$" is a reference, not a function.
        if s > 0, "!$".contains(t[s - 1]) { return nil }
        let prefix = String(t[s ..< caret]).uppercased()
        // A cell reference being typed (A1, B12) is not a name.
        if CellAddress(prefix) != nil { return nil }
        let m = functionNames.filter { $0.hasPrefix(prefix) }
        guard !m.isEmpty, !(m.count == 1 && m[0] == prefix) else { return nil }
        return Completion(start: s, matches: Array(m.prefix(limit)))
    }

    /// The text after accepting `name`: the typed part replaced by the name and an opening bracket.
    static func accept(_ name: String, in t: [Character], from start: Int, caret: Int) -> (text: [Character], caret: Int) {
        var out = t
        let ins = Array(name + "(")
        out.replaceSubrange(start ..< caret, with: ins)
        return (out, start + ins.count)
    }

    struct Hint: Equatable {
        var name: String
        var signature: [String]
        /// Which argument the caret is in (0-based), clamped to the last one for repeating arguments.
        var index: Int
        var text: String { name + "(" + signature.joined(separator: ", ") + ")" }
    }

    /// The tip for the function whose brackets hold the caret.
    static func hint(_ t: [Character], caret: Int) -> Hint? {
        guard t.first == "=", caret <= t.count else { return nil }
        var depth = 0, commas = 0, i = 0
        // Walk from the start so quotes are read correctly: a stack of (name, commas so far).
        var stack: [(String, Int)] = []
        var inStr = false
        _ = depth; _ = commas
        while i < caret {
            let c = t[i]
            if c == "\"" { inStr.toggle() }
            else if !inStr {
                if c == "(" {
                    var s = i
                    while s > 0, _isNameChar(t[s - 1]) { s -= 1 }
                    stack.append((String(t[s ..< i]).uppercased(), 0))
                } else if c == ")" { if !stack.isEmpty { stack.removeLast() } }
                else if c == "," || c == ";" { if !stack.isEmpty { stack[stack.count - 1].1 += 1 } }
            }
            i += 1
        }
        if inStr { return nil }
        guard let top = stack.last(where: { !$0.0.isEmpty }), let sig = signatures[top.0] else { return nil }
        depth = 0; commas = 0
        return Hint(name: top.0, signature: sig, index: min(top.1, sig.count - 1))
    }

    struct Reference: Equatable {
        var range: Range<Int>
        var cells: CellRange
        var sheet: String?
        var color: Int
    }

    static let palette: [UInt32] = [0xFF2E75B6, 0xFF00B050, 0xFF7030A0, 0xFFC00000, 0xFFED7D31, 0xFF008B8B]

    /// Each cell or range reference in a formula, in the order written, with the colour it is drawn in.
    /// A reference written twice keeps one colour.
    static func references(_ t: [Character]) -> [Reference] {
        guard t.first == "=" else { return [] }
        var out: [Reference] = []
        var seen: [String: Int] = [:]
        var i = 1, inStr = false
        while i < t.count {
            let c = t[i]
            if c == "\"" { inStr.toggle(); i += 1; continue }
            if inStr { i += 1; continue }
            // A word: letters, digits, $, ! and : and ' (a quoted sheet name).
            guard c.isLetter || c == "$" || c == "'" else { i += 1; continue }
            if i > 0, _isNameChar(t[i - 1]) && t[i - 1] != "$" { // the tail of a name or number
                i += 1; while i < t.count, _isNameChar(t[i]) { i += 1 }; continue
            }
            var j = i
            var sheet: String? = nil
            if c == "'" {
                j += 1
                while j < t.count, t[j] != "'" { j += 1 }
                guard j + 1 < t.count, t[j + 1] == "!" else { i += 1; continue }
                sheet = String(t[(i + 1) ..< j]); j += 2
            } else {
                var k = i
                while k < t.count, _isNameChar(t[k]) { k += 1 }
                if k < t.count, t[k] == "!" { sheet = String(t[i ..< k]); j = k + 1 }
            }
            var k = j
            while k < t.count, t[k].isLetter || t[k].isNumber || t[k] == "$" || t[k] == ":" { k += 1 }
            let body = String(t[j ..< k]).replacingAll("$", with: "").uppercased()
            // A function name or word followed by "(" is not a reference.
            if k < t.count, t[k] == "(" { i = k; continue }
            if k < t.count, _isNameChar(t[k]) || t[k] == "." { i = k; continue }
            if let r = CellRange(body) {
                let key = (sheet ?? "") + "!" + body
                let n = seen[key] ?? seen.count
                seen[key] = n
                out.append(Reference(range: i ..< k, cells: r, sheet: sheet, color: Int(palette[n % palette.count])))
            }
            i = max(k, i + 1)
        }
        return out
    }

    /// Argument names for the functions people use most, as Excel's tip shows them (`[x]` is optional).
    static let signatures: [String: [String]] = [
        "SUM": ["number1", "[number2]", "..."], "AVERAGE": ["number1", "[number2]", "..."],
        "MIN": ["number1", "[number2]", "..."], "MAX": ["number1", "[number2]", "..."],
        "COUNT": ["value1", "[value2]", "..."], "COUNTA": ["value1", "[value2]", "..."],
        "COUNTBLANK": ["range"], "PRODUCT": ["number1", "[number2]", "..."],
        "IF": ["logical_test", "[value_if_true]", "[value_if_false]"],
        "IFS": ["logical_test1", "value_if_true1", "..."], "IFERROR": ["value", "value_if_error"],
        "IFNA": ["value", "value_if_na"], "AND": ["logical1", "[logical2]", "..."],
        "OR": ["logical1", "[logical2]", "..."], "NOT": ["logical"],
        "VLOOKUP": ["lookup_value", "table_array", "col_index_num", "[range_lookup]"],
        "HLOOKUP": ["lookup_value", "table_array", "row_index_num", "[range_lookup]"],
        "XLOOKUP": ["lookup_value", "lookup_array", "return_array", "[if_not_found]", "[match_mode]", "[search_mode]"],
        "INDEX": ["array", "row_num", "[column_num]"], "MATCH": ["lookup_value", "lookup_array", "[match_type]"],
        "SUMIF": ["range", "criteria", "[sum_range]"], "COUNTIF": ["range", "criteria"],
        "SUMIFS": ["sum_range", "criteria_range1", "criteria1", "..."],
        "COUNTIFS": ["criteria_range1", "criteria1", "..."],
        "AVERAGEIF": ["range", "criteria", "[average_range]"],
        "ROUND": ["number", "num_digits"], "ROUNDUP": ["number", "num_digits"], "ROUNDDOWN": ["number", "num_digits"],
        "ABS": ["number"], "INT": ["number"], "MOD": ["number", "divisor"], "POWER": ["number", "power"],
        "SQRT": ["number"], "LEFT": ["text", "[num_chars]"], "RIGHT": ["text", "[num_chars]"],
        "MID": ["text", "start_num", "num_chars"], "LEN": ["text"], "TRIM": ["text"],
        "UPPER": ["text"], "LOWER": ["text"], "PROPER": ["text"], "CONCAT": ["text1", "[text2]", "..."],
        "CONCATENATE": ["text1", "[text2]", "..."], "TEXTJOIN": ["delimiter", "ignore_empty", "text1", "..."],
        "TEXT": ["value", "format_text"], "VALUE": ["text"],
        "FIND": ["find_text", "within_text", "[start_num]"], "SEARCH": ["find_text", "within_text", "[start_num]"],
        "SUBSTITUTE": ["text", "old_text", "new_text", "[instance_num]"],
        "REPLACE": ["old_text", "start_num", "num_chars", "new_text"],
        "DATE": ["year", "month", "day"], "TODAY": [], "NOW": [], "YEAR": ["serial_number"],
        "MONTH": ["serial_number"], "DAY": ["serial_number"], "EDATE": ["start_date", "months"],
        "EOMONTH": ["start_date", "months"], "DATEDIF": ["start_date", "end_date", "unit"],
        "NETWORKDAYS": ["start_date", "end_date", "[holidays]"],
        "SUMPRODUCT": ["array1", "[array2]", "..."], "CHOOSE": ["index_num", "value1", "[value2]", "..."],
        "OFFSET": ["reference", "rows", "cols", "[height]", "[width]"], "INDIRECT": ["ref_text", "[a1]"],
        "FILTER": ["array", "include", "[if_empty]"], "SORT": ["array", "[sort_index]", "[sort_order]", "[by_col]"],
        "UNIQUE": ["array", "[by_col]", "[exactly_once]"], "SEQUENCE": ["rows", "[columns]", "[start]", "[step]"],
        "LET": ["name1", "name_value1", "calculation_or_name2", "..."],
        "RAND": [], "RANDBETWEEN": ["bottom", "top"], "ISBLANK": ["value"], "ISNUMBER": ["value"],
        "ISTEXT": ["value"], "ISERROR": ["value"], "PMT": ["rate", "nper", "pv", "[fv]", "[type]"],
        "LARGE": ["array", "k"], "SMALL": ["array", "k"], "RANK": ["number", "ref", "[order]"],
        "MEDIAN": ["number1", "[number2]", "..."], "STDEV": ["number1", "[number2]", "..."],
        "ROW": ["[reference]"], "COLUMN": ["[reference]"], "ROWS": ["array"], "COLUMNS": ["array"],
        "TRANSPOSE": ["array"], "CELL": ["info_type", "[reference]"], "SWITCH": ["expression", "value1", "result1", "..."],
    ]
}
