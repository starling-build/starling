import Foundation

/// One level of a sort: a column (a sheet column number) and a direction.
struct SortKey: Equatable {
    var col: Int
    var ascending: Bool = true
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
    func sortRange(_ range: CellRange, keys: [SortKey], hasHeader: Bool) -> SortProblem? {
        if refuses("sort") { return nil }
        guard !keys.isEmpty else { return .noKeys }
        guard keys.allSatisfy({ $0.col >= range.left && $0.col <= range.right }) else { return .keyOutside }
        let top = hasHeader ? range.top + 1 : range.top
        guard range.bottom > top else { return .nothingToSort }
        let data = CellRange(top: top, left: range.left, bottom: range.bottom, right: range.right)
        if sheet.merges.contains(where: { $0.intersects(data) }) { return .mergedCells }
        structural {
            sortRows(data, keys: keys)
            if sheet.autoFilter != nil { reapplyFilter() }
        }
        return nil
    }
}
