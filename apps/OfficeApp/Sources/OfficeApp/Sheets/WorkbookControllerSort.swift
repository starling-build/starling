import Foundation

/// One level of a sort: a column (a sheet column number) and a direction.
/// What a level sorts on (Excel's "Sort On").
enum SortOn: Equatable {
    case values, cellColor, fontColor
}

/// With `byColumns` (Left to right) `col` is a sheet row number.
struct SortKey: Equatable {
    var col: Int
    var ascending: Bool = true
    var on: SortOn = .values
    /// For a colour level: the colour (nil is "no fill" / "automatic"), and whether its cells go first.
    var color: UInt32? = nil
    var colorOnTop = true
    /// A custom list as the order (Sun, Mon, …); values not in it follow, in the usual order.
    /// Descending reverses the list.
    var custom: [String]? = nil

    /// Excel's built-in custom lists.
    static let builtinLists: [[String]] = [
        ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"],
        ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"],
        ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"],
        ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"],
    ]
}

enum SortProblem: Equatable {
    case nothingToSort, noKeys, keyOutside, mergedCells
    var message: String {
        switch self {
        case .nothingToSort: return "Select two or more rows of data to sort."
        case .noKeys: return "Choose a column to sort by."
        case .keyOutside: return "A sort column is outside the selected cells."
        case .mergedCells: return "Sorting needs cells of the same size. Unmerge the merged cells first."
        }
    }
}

extension WorkbookController {
    /// Sort the rows of `range` by `keys` (first key first). With `hasHeader` the first row stays
    /// put. Formulas shift with their rows. One undo step. Refuses a range with merged cells that
    /// would be torn apart, and a key column outside the range.
    ///
    /// `byColumns` is Left to right: the columns of `range` are reordered, each key's `col` is a row
    /// number, and `hasHeader` keeps the first column (the labels) in place.
    func sortRange(_ range: CellRange, keys: [SortKey], hasHeader: Bool, byColumns: Bool = false, caseSensitive: Bool = false) -> SortProblem? {
        if refuses("sort") { return nil }
        guard !keys.isEmpty else { return .noKeys }
        let data: CellRange
        if byColumns {
            guard keys.allSatisfy({ $0.col >= range.top && $0.col <= range.bottom }) else { return .keyOutside }
            let left = hasHeader ? range.left + 1 : range.left
            guard range.right > left else { return .nothingToSort }
            data = CellRange(top: range.top, left: left, bottom: range.bottom, right: range.right)
        } else {
            guard keys.allSatisfy({ $0.col >= range.left && $0.col <= range.right }) else { return .keyOutside }
            let top = hasHeader ? range.top + 1 : range.top
            guard range.bottom > top else { return .nothingToSort }
            data = CellRange(top: top, left: range.left, bottom: range.bottom, right: range.right)
        }
        if sheet.merges.contains(where: { $0.intersects(data) }) { return .mergedCells }
        structural {
            sortRows(data, keys: keys, byColumns: byColumns, caseSensitive: caseSensitive)
            if sheet.autoFilter != nil { reapplyFilter() }
        }
        return nil
    }
}
