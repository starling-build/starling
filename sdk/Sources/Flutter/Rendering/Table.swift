// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Table layout model types: column width strategies, parent data, vertical
/// alignment enum, and the RenderTable render object.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/table.dart`

import FlutterSwiftBridge

// MARK: - TableCellParentData

/// Parent data used by `RenderTable` for its children.
///
/// **Dart Source:** `table.dart:16-31`
public class TableCellParentData: BoxParentData {
    /// Where this cell should be placed vertically.
    ///
    /// When using `TableCellVerticalAlignment.baseline`, the text baseline must
    /// be set as well.
    ///
    /// **Dart Source:** `table.dart:20`
    public var verticalAlignment: TableCellVerticalAlignment?

    /// The column that the child was in the last time it was laid out.
    ///
    /// **Dart Source:** `table.dart:23`
    public var x: Int?

    /// The row that the child was in the last time it was laid out.
    ///
    /// **Dart Source:** `table.dart:26`
    public var y: Int?

    /// **Dart Source:** `table.dart:29-30`
    public override var description: String {
        let alignment = verticalAlignment.map { "\($0)" } ?? "default vertical alignment"
        return "\(super.description); \(alignment)"
    }
}

// MARK: - TableColumnWidth Protocol

/// Base protocol to describe how wide a column in a `RenderTable` should be.
///
/// To size a column to a specific number of pixels, use a `FixedColumnWidth`.
/// This is the cheapest way to size a column.
///
/// Other algorithms that are relatively cheap include `FlexColumnWidth`, which
/// distributes the space equally among the flexible columns,
/// `FractionColumnWidth`, which sizes a column based on the size of the
/// table's container.
///
/// **Dart Source:** `table.dart:43-84`
public protocol TableColumnWidth {
    /// The smallest width that the column can have.
    ///
    /// The `cells` argument provides all the cells in the table for this column.
    /// Walking the cells is by definition O(N), so algorithms that do that
    /// should be considered expensive.
    ///
    /// The `containerWidth` argument is the `maxWidth` of the incoming
    /// constraints for the table, and might be infinite.
    ///
    /// **Dart Source:** `table.dart:56`
    func minIntrinsicWidth(cells: [RenderBox], containerWidth: Double) -> Double

    /// The ideal width that the column should have. This must be equal
    /// to or greater than the `minIntrinsicWidth`. The column might be
    /// bigger than this width, e.g. if the column is flexible or if the
    /// table's width ends up being forced to be bigger than the sum of
    /// all the maxIntrinsicWidth values.
    ///
    /// The `cells` argument provides all the cells in the table for this column.
    ///
    /// The `containerWidth` argument is the `maxWidth` of the incoming
    /// constraints for the table, and might be infinite.
    ///
    /// **Dart Source:** `table.dart:70`
    func maxIntrinsicWidth(cells: [RenderBox], containerWidth: Double) -> Double

    /// The flex factor to apply to the cell if there is any room left
    /// over when laying out the table. The remaining space is
    /// distributed to any columns with flex in proportion to their flex
    /// value (higher values get more space).
    ///
    /// The `cells` argument provides all the cells in the table for this column.
    ///
    /// **Dart Source:** `table.dart:80`
    func flex(cells: [RenderBox]) -> Double?
}

/// Default implementation for `flex` returning nil.
///
/// **Dart Source:** `table.dart:80`
extension TableColumnWidth {
    public func flex(cells: [RenderBox]) -> Double? {
        return nil
    }
}

// MARK: - IntrinsicColumnWidth

/// Sizes the column according to the intrinsic dimensions of all the
/// cells in that column.
///
/// This is a very expensive way to size a column.
///
/// A flex value can be provided. If specified (and non-nil), the
/// column will participate in the distribution of remaining space
/// once all the non-flexible columns have been sized.
///
/// **Dart Source:** `table.dart:94-131`
public class IntrinsicColumnWidth: TableColumnWidth {
    /// Creates a column width based on intrinsic sizing.
    ///
    /// This sizing algorithm is very expensive.
    ///
    /// The `flex` argument specifies the flex factor to apply to the column if
    /// there is any room left over when laying out the table. If `flex` is
    /// nil (the default), the table will not distribute any extra space to the
    /// column.
    ///
    /// **Dart Source:** `table.dart:103`
    public init(flex: Double? = nil) {
        self._flex = flex
    }

    /// **Dart Source:** `table.dart:123`
    private let _flex: Double?

    /// **Dart Source:** `table.dart:106-112`
    public func minIntrinsicWidth(cells: [RenderBox], containerWidth: Double) -> Double {
        var result = 0.0
        for cell in cells {
            result = max(result, cell.getMinIntrinsicWidth(.infinity))
        }
        return result
    }

    /// **Dart Source:** `table.dart:115-121`
    public func maxIntrinsicWidth(cells: [RenderBox], containerWidth: Double) -> Double {
        var result = 0.0
        for cell in cells {
            result = max(result, cell.getMaxIntrinsicWidth(.infinity))
        }
        return result
    }

    /// **Dart Source:** `table.dart:126`
    public func flex(cells: [RenderBox]) -> Double? {
        return _flex
    }
}

// MARK: - FixedColumnWidth

/// Sizes the column to a specific number of pixels.
///
/// This is the cheapest way to size a column.
///
/// **Dart Source:** `table.dart:136-156`
public class FixedColumnWidth: TableColumnWidth {
    /// Creates a column width based on a fixed number of logical pixels.
    ///
    /// **Dart Source:** `table.dart:138`
    public init(_ value: Double) {
        self.value = value
    }

    /// The width the column should occupy in logical pixels.
    ///
    /// **Dart Source:** `table.dart:141`
    public let value: Double

    /// **Dart Source:** `table.dart:144-146`
    public func minIntrinsicWidth(cells: [RenderBox], containerWidth: Double) -> Double {
        return value
    }

    /// **Dart Source:** `table.dart:149-151`
    public func maxIntrinsicWidth(cells: [RenderBox], containerWidth: Double) -> Double {
        return value
    }
}

// MARK: - FractionColumnWidth

/// Sizes the column to a fraction of the table's constraints' maxWidth.
///
/// This is a cheap way to size a column.
///
/// **Dart Source:** `table.dart:161-188`
public class FractionColumnWidth: TableColumnWidth {
    /// Creates a column width based on a fraction of the table's constraints'
    /// maxWidth.
    ///
    /// **Dart Source:** `table.dart:164`
    public init(_ value: Double) {
        self.value = value
    }

    /// The fraction of the table's constraints' maxWidth that this column should
    /// occupy.
    ///
    /// **Dart Source:** `table.dart:168`
    public let value: Double

    /// **Dart Source:** `table.dart:171-176`
    public func minIntrinsicWidth(cells: [RenderBox], containerWidth: Double) -> Double {
        if !containerWidth.isFinite {
            return 0.0
        }
        return value * containerWidth
    }

    /// **Dart Source:** `table.dart:179-184`
    public func maxIntrinsicWidth(cells: [RenderBox], containerWidth: Double) -> Double {
        if !containerWidth.isFinite {
            return 0.0
        }
        return value * containerWidth
    }
}

// MARK: - FlexColumnWidth

/// Sizes the column by taking a part of the remaining space once all
/// the other columns have been laid out.
///
/// For example, if two columns have a `FlexColumnWidth`, then half the
/// space will go to one and half the space will go to the other.
///
/// This is a cheap way to size a column.
///
/// **Dart Source:** `table.dart:197-223`
public class FlexColumnWidth: TableColumnWidth {
    /// Creates a column width based on a fraction of the remaining space once all
    /// the other columns have been laid out.
    ///
    /// **Dart Source:** `table.dart:200`
    public init(_ value: Double = 1.0) {
        self.value = value
    }

    /// The fraction of the remaining space once all the other columns have
    /// been laid out that this column should occupy.
    ///
    /// **Dart Source:** `table.dart:205`
    public let value: Double

    /// **Dart Source:** `table.dart:207-209`
    public func minIntrinsicWidth(cells: [RenderBox], containerWidth: Double) -> Double {
        return 0.0
    }

    /// **Dart Source:** `table.dart:212-214`
    public func maxIntrinsicWidth(cells: [RenderBox], containerWidth: Double) -> Double {
        return 0.0
    }

    /// **Dart Source:** `table.dart:217-219`
    public func flex(cells: [RenderBox]) -> Double? {
        return value
    }
}

// MARK: - MaxColumnWidth

/// Sizes the column such that it is the size that is the maximum of
/// two column width specifications.
///
/// For example, to have a column be 10% of the container width or
/// 100px, whichever is bigger, you could use:
///
///     MaxColumnWidth(FixedColumnWidth(100.0), FractionColumnWidth(0.1))
///
/// Both specifications are evaluated, so if either specification is
/// expensive, so is this.
///
/// **Dart Source:** `table.dart:235-275`
public class MaxColumnWidth: TableColumnWidth {
    /// Creates a column width that is the maximum of two other column widths.
    ///
    /// **Dart Source:** `table.dart:237`
    public init(_ a: any TableColumnWidth, _ b: any TableColumnWidth) {
        self.a = a
        self.b = b
    }

    /// A lower bound for the width of this column.
    ///
    /// **Dart Source:** `table.dart:240`
    public let a: any TableColumnWidth

    /// Another lower bound for the width of this column.
    ///
    /// **Dart Source:** `table.dart:243`
    public let b: any TableColumnWidth

    /// **Dart Source:** `table.dart:246-251`
    public func minIntrinsicWidth(cells: [RenderBox], containerWidth: Double) -> Double {
        return max(
            a.minIntrinsicWidth(cells: cells, containerWidth: containerWidth),
            b.minIntrinsicWidth(cells: cells, containerWidth: containerWidth)
        )
    }

    /// **Dart Source:** `table.dart:254-259`
    public func maxIntrinsicWidth(cells: [RenderBox], containerWidth: Double) -> Double {
        return max(
            a.maxIntrinsicWidth(cells: cells, containerWidth: containerWidth),
            b.maxIntrinsicWidth(cells: cells, containerWidth: containerWidth)
        )
    }

    /// **Dart Source:** `table.dart:262-271`
    public func flex(cells: [RenderBox]) -> Double? {
        let aFlex = a.flex(cells: cells)
        let bFlex = b.flex(cells: cells)
        if aFlex == nil {
            return bFlex
        } else if bFlex == nil {
            return aFlex
        }
        return Swift.max(aFlex!, bFlex!)
    }
}

// MARK: - MinColumnWidth

/// Sizes the column such that it is the size that is the minimum of
/// two column width specifications.
///
/// For example, to have a column be 10% of the container width but
/// never bigger than 100px, you could use:
///
///     MinColumnWidth(FixedColumnWidth(100.0), FractionColumnWidth(0.1))
///
/// Both specifications are evaluated, so if either specification is
/// expensive, so is this.
///
/// **Dart Source:** `table.dart:287-327`
public class MinColumnWidth: TableColumnWidth {
    /// Creates a column width that is the minimum of two other column widths.
    ///
    /// **Dart Source:** `table.dart:289`
    public init(_ a: any TableColumnWidth, _ b: any TableColumnWidth) {
        self.a = a
        self.b = b
    }

    /// An upper bound for the width of this column.
    ///
    /// **Dart Source:** `table.dart:292`
    public let a: any TableColumnWidth

    /// Another upper bound for the width of this column.
    ///
    /// **Dart Source:** `table.dart:295`
    public let b: any TableColumnWidth

    /// **Dart Source:** `table.dart:298-303`
    public func minIntrinsicWidth(cells: [RenderBox], containerWidth: Double) -> Double {
        return min(
            a.minIntrinsicWidth(cells: cells, containerWidth: containerWidth),
            b.minIntrinsicWidth(cells: cells, containerWidth: containerWidth)
        )
    }

    /// **Dart Source:** `table.dart:306-311`
    public func maxIntrinsicWidth(cells: [RenderBox], containerWidth: Double) -> Double {
        return min(
            a.maxIntrinsicWidth(cells: cells, containerWidth: containerWidth),
            b.maxIntrinsicWidth(cells: cells, containerWidth: containerWidth)
        )
    }

    /// **Dart Source:** `table.dart:314-323`
    public func flex(cells: [RenderBox]) -> Double? {
        let aFlex = a.flex(cells: cells)
        let bFlex = b.flex(cells: cells)
        if aFlex == nil {
            return bFlex
        } else if bFlex == nil {
            return aFlex
        }
        return Swift.min(aFlex!, bFlex!)
    }
}

// MARK: - TableCellVerticalAlignment

/// Vertical alignment options for cells in `RenderTable` objects.
///
/// This is specified using `TableCellParentData` objects on the
/// `RenderObject.parentData` of the children of the `RenderTable`.
///
/// **Dart Source:** `table.dart:333-358`
public enum TableCellVerticalAlignment {
    /// Cells with this alignment are placed with their top at the top of the row.
    ///
    /// **Dart Source:** `table.dart:335`
    case top

    /// Cells with this alignment are vertically centered in the row.
    ///
    /// **Dart Source:** `table.dart:338`
    case middle

    /// Cells with this alignment are placed with their bottom at the bottom of
    /// the row.
    ///
    /// **Dart Source:** `table.dart:341`
    case bottom

    /// Cells with this alignment are aligned such that they all share the same
    /// baseline. Cells with no baseline are top-aligned instead. The baseline
    /// used is specified by `RenderTable.textBaseline`. It is not valid to use
    /// the baseline value if `RenderTable.textBaseline` is not specified.
    ///
    /// This vertical alignment is relatively expensive because it causes the
    /// table to compute the baseline for each cell in the row.
    ///
    /// **Dart Source:** `table.dart:350`
    case baseline

    /// Cells with this alignment are sized to be as tall as the row, then made
    /// to fit the row. If all the cells have this alignment, then the row will
    /// have zero height.
    ///
    /// **Dart Source:** `table.dart:354`
    case fill

    /// Cells with this alignment are sized to be the same height as the tallest
    /// cell in the row.
    ///
    /// **Dart Source:** `table.dart:357`
    case intrinsicHeight
}

// MARK: - RenderTable

/// A table where the columns and rows are sized to fit the contents of the
/// cells.
///
/// `RenderTable` manages its own children array (not using a linked list).
/// The children are stored in a flat array indexed as `x + y * columns`.
///
/// **Dart Source:** `table.dart:361-1556`
public class RenderTable: RenderBox {

    /// Creates a table render object.
    ///
    /// - Parameters:
    ///   - columns: Must be non-negative. If nil, inferred from `children`.
    ///   - rows: Must be non-negative. If nil, defaults to 0.
    ///   - columnWidths: Map of column indices to width strategies. Defaults to
    ///     empty.
    ///   - defaultColumnWidth: Default width strategy for columns not in
    ///     `columnWidths`. Defaults to `FlexColumnWidth()`.
    ///   - textDirection: The direction in which the columns are ordered.
    ///   - border: The style to use when painting the boundary and interior
    ///     divisions of the table.
    ///   - defaultVerticalAlignment: How cells that do not explicitly specify a
    ///     vertical alignment are aligned vertically.
    ///   - textBaseline: The text baseline to use when aligning rows using
    ///     `TableCellVerticalAlignment.baseline`.
    ///   - children: A 2D array of children. If non-nil, `rows` must be nil.
    ///
    /// **Dart Source:** `table.dart:373-399`
    public init(
        columns: Int? = nil,
        rows: Int? = nil,
        columnWidths: [Int: any TableColumnWidth]? = nil,
        defaultColumnWidth: any TableColumnWidth = FlexColumnWidth(),
        textDirection: TextDirection,
        border: TableBorder? = nil,
        defaultVerticalAlignment: TableCellVerticalAlignment = .top,
        textBaseline: TextBaseline? = nil,
        children: [[RenderBox]]? = nil
    ) {
        assert(columns == nil || columns! >= 0)
        assert(rows == nil || rows! >= 0)
        assert(rows == nil || children == nil)

        self._columns = columns ?? (children != nil && !children!.isEmpty ? children!.first!.count : 0)
        self._rows = rows ?? 0
        self._columnWidths = columnWidths ?? [:]
        self._defaultColumnWidth = defaultColumnWidth
        self._textDirection = textDirection
        self._border = border
        self._defaultVerticalAlignment = defaultVerticalAlignment
        self._textBaseline = textBaseline
        super.init()
        self._children = Array<RenderBox?>(repeating: nil, count: _columns * _rows)
        children?.forEach { addRow(cells: $0) }
    }

    // MARK: - Children Storage

    /// Children are stored in row-major order.
    /// `_children.count` must be `rows * columns`.
    ///
    /// **Dart Source:** `table.dart:404`
    private var _children: [RenderBox?] = []

    // MARK: - Columns

    /// The number of vertical alignment lines in this table.
    ///
    /// Changing the number of columns will remove any children that no longer
    /// fit in the table.
    ///
    /// Changing the number of columns is an expensive operation because the
    /// table needs to rearrange its internal representation.
    ///
    /// **Dart Source:** `table.dart:413-441`
    public var columns: Int {
        get { _columns }
        set {
            assert(newValue >= 0)
            if newValue == _columns {
                return
            }
            let oldColumns = _columns
            let oldChildren = _children
            _columns = newValue
            _children = Array<RenderBox?>(repeating: nil, count: _columns * _rows)
            let columnsToCopy = min(_columns, oldColumns)
            for y in 0..<_rows {
                for x in 0..<columnsToCopy {
                    _children[x + y * _columns] = oldChildren[x + y * oldColumns]
                }
            }
            if oldColumns > _columns {
                for y in 0..<_rows {
                    for x in _columns..<oldColumns {
                        let xy = x + y * oldColumns
                        if let child = oldChildren[xy] {
                            dropChild(child)
                        }
                    }
                }
            }
            markNeedsLayout()
        }
    }
    private var _columns: Int

    // MARK: - Rows

    /// The number of horizontal alignment lines in this table.
    ///
    /// Changing the number of rows will remove any children that no longer fit
    /// in the table.
    ///
    /// **Dart Source:** `table.dart:447-464`
    public var rows: Int {
        get { _rows }
        set {
            assert(newValue >= 0)
            if newValue == _rows {
                return
            }
            if _rows > newValue {
                for xy in (_columns * newValue)..<_children.count {
                    if let child = _children[xy] {
                        dropChild(child)
                    }
                }
            }
            _rows = newValue
            _children = {
                var resized = Array<RenderBox?>(repeating: nil, count: _columns * _rows)
                let copyCount = min(resized.count, _children.count)
                for i in 0..<copyCount {
                    resized[i] = _children[i]
                }
                return resized
            }()
            markNeedsLayout()
        }
    }
    private var _rows: Int

    // MARK: - Column Widths

    /// How the horizontal extents of the columns of this table should be
    /// determined.
    ///
    /// If the map has no entry for a given column, the table uses the
    /// `defaultColumnWidth` instead.
    ///
    /// The layout performance of the table depends critically on which column
    /// sizing algorithms are used here. In particular, `IntrinsicColumnWidth` is
    /// quite expensive because it needs to measure each cell in the column to
    /// determine the intrinsic size of the column.
    ///
    /// **Dart Source:** `table.dart:479-491`
    public var columnWidths: [Int: any TableColumnWidth]? {
        get { _columnWidths }
        set {
            if _columnWidths.isEmpty && newValue == nil {
                return
            }
            _columnWidths = newValue ?? [:]
            markNeedsLayout()
        }
    }
    private var _columnWidths: [Int: any TableColumnWidth]

    /// Determines how the width of column with the given index is determined.
    ///
    /// **Dart Source:** `table.dart:494-500`
    public func setColumnWidth(_ column: Int, _ value: any TableColumnWidth) {
        _columnWidths[column] = value
        markNeedsLayout()
    }

    // MARK: - Default Column Width

    /// How to determine the widths of columns that don't have an explicit
    /// sizing algorithm.
    ///
    /// Specifically, the `defaultColumnWidth` is used for column `i` if
    /// `columnWidths[i]` is nil.
    ///
    /// **Dart Source:** `table.dart:506-514`
    public var defaultColumnWidth: any TableColumnWidth {
        get { _defaultColumnWidth }
        set {
            _defaultColumnWidth = newValue
            markNeedsLayout()
        }
    }
    private var _defaultColumnWidth: any TableColumnWidth

    // MARK: - Text Direction

    /// The direction in which the columns are ordered.
    ///
    /// **Dart Source:** `table.dart:517-525`
    public var textDirection: TextDirection {
        get { _textDirection }
        set {
            if _textDirection == newValue {
                return
            }
            _textDirection = newValue
            markNeedsLayout()
        }
    }
    private var _textDirection: TextDirection

    // MARK: - Border

    /// The style to use when painting the boundary and interior divisions of the
    /// table.
    ///
    /// **Dart Source:** `table.dart:528-536`
    public var border: TableBorder? {
        get { _border }
        set {
            if _border == newValue {
                return
            }
            _border = newValue
            markNeedsPaint()
        }
    }
    private var _border: TableBorder?

    // MARK: - Default Vertical Alignment

    /// How cells that do not explicitly specify a vertical alignment are aligned
    /// vertically.
    ///
    /// **Dart Source:** `table.dart:578-586`
    public var defaultVerticalAlignment: TableCellVerticalAlignment {
        get { _defaultVerticalAlignment }
        set {
            if _defaultVerticalAlignment == newValue {
                return
            }
            _defaultVerticalAlignment = newValue
            markNeedsLayout()
        }
    }
    private var _defaultVerticalAlignment: TableCellVerticalAlignment

    // MARK: - Text Baseline

    /// The text baseline to use when aligning rows using
    /// `TableCellVerticalAlignment.baseline`.
    ///
    /// **Dart Source:** `table.dart:589-597`
    public var textBaseline: TextBaseline? {
        get { _textBaseline }
        set {
            if _textBaseline == newValue {
                return
            }
            _textBaseline = newValue
            markNeedsLayout()
        }
    }
    private var _textBaseline: TextBaseline?

    // MARK: - Setup Parent Data

    /// Sets up `TableCellParentData` for children.
    ///
    /// **Dart Source:** `table.dart:600-604`
    public override func setupParentData(_ child: RenderObject) {
        if !(child.parentData is TableCellParentData) {
            child.parentData = TableCellParentData()
        }
    }

    // MARK: - Child Management

    /// Replaces the children of this table with the given cells.
    ///
    /// The cells are divided into the specified number of columns before
    /// replacing the existing children.
    ///
    /// If the new cells contain any existing children of the table, those
    /// children are moved to their new location in the table rather than
    /// removed from the table and re-added.
    ///
    /// **Dart Source:** `table.dart:799-860`
    public func setFlatChildren(columns: Int, cells: [RenderBox?]) {
        assert(columns >= 0)
        // Consider the case of a newly empty table.
        if columns == 0 || cells.isEmpty {
            assert(cells.isEmpty)
            _columns = columns
            if _children.isEmpty {
                assert(_rows == 0)
                return
            }
            for oldChild in _children {
                if let child = oldChild {
                    dropChild(child)
                }
            }
            _rows = 0
            _children = []
            markNeedsLayout()
            return
        }
        assert(cells.count % columns == 0)
        // Fill a set with the cells that are moving (it's important not
        // to dropChild a child that's remaining with us, because that
        // would clear their parentData field).
        var lostChildren = Set<ObjectIdentifier>()
        var lostChildMap: [ObjectIdentifier: RenderBox] = [:]
        for y in 0..<_rows {
            for x in 0..<_columns {
                let xyOld = x + y * _columns
                let xyNew = x + y * columns
                if let oldChild = _children[xyOld] {
                    if x >= columns || xyNew >= cells.count || _children[xyOld] !== cells[xyNew] {
                        let id = ObjectIdentifier(oldChild)
                        lostChildren.insert(id)
                        lostChildMap[id] = oldChild
                    }
                }
            }
        }
        // Adopt cells that are arriving, and cross cells that are just moving
        // off our list of lostChildren.
        var y = 0
        while y * columns < cells.count {
            for x in 0..<columns {
                let xyNew = x + y * columns
                let xyOld = x + y * _columns
                if let newChild = cells[xyNew] {
                    if x >= _columns || y >= _rows || _children[xyOld] !== newChild {
                        let id = ObjectIdentifier(newChild)
                        if lostChildren.remove(id) != nil {
                            lostChildMap.removeValue(forKey: id)
                        } else {
                            adoptChild(newChild)
                        }
                    }
                }
            }
            y += 1
        }
        // Drop all the lost children.
        for id in lostChildren {
            if let child = lostChildMap[id] {
                dropChild(child)
            }
        }
        // Update our internal values.
        _columns = columns
        _rows = cells.count / columns
        _children = Array(cells)
        assert(_children.count == _rows * _columns)
        markNeedsLayout()
    }

    /// Replaces the children of this table with the given cells.
    ///
    /// **Dart Source:** `table.dart:863-879`
    public func setChildren(cells: [[RenderBox]]?) {
        // TODO(ianh): Make this smarter, like setFlatChildren
        guard let cells = cells else {
            setFlatChildren(columns: 0, cells: [])
            return
        }
        for oldChild in _children {
            if let child = oldChild {
                dropChild(child)
            }
        }
        _children = []
        _columns = cells.isEmpty ? 0 : cells.first!.count
        _rows = 0
        for row in cells {
            addRow(cells: row)
        }
        assert(_children.count == _rows * _columns)
    }

    /// Adds a row to the end of the table.
    ///
    /// The newly added children must not already have parents.
    ///
    /// **Dart Source:** `table.dart:884-895`
    public func addRow(cells: [RenderBox?]) {
        assert(cells.count == _columns)
        assert(_children.count == _rows * _columns)
        _rows += 1
        _children.append(contentsOf: cells)
        for cell in cells {
            if let cell = cell {
                adoptChild(cell)
            }
        }
        markNeedsLayout()
    }

    /// Replaces the child at the given position with the given child.
    ///
    /// If the given child is already located at the given position, this function
    /// does not modify the table. Otherwise, the given child must not already
    /// have a parent.
    ///
    /// **Dart Source:** `table.dart:902-917`
    public func setChild(x: Int, y: Int, value: RenderBox?) {
        assert(x >= 0 && x < _columns && y >= 0 && y < _rows)
        assert(_children.count == _rows * _columns)
        let xy = x + y * _columns
        let oldChild = _children[xy]
        if oldChild === value {
            return
        }
        if let oldChild = oldChild {
            dropChild(oldChild)
        }
        _children[xy] = value
        if let value = value {
            adoptChild(value)
        }
    }

    // MARK: - Child Adoption / Drop

    // adoptChild/dropChild are inherited from RenderObject base class.
    // They set child.parent, call setupParentData, and markNeedsLayout.

    // MARK: - Attach / Detach

    /// Called when the object is attached to a pipeline owner.
    ///
    /// **Dart Source:** `table.dart:920-925`
    // attach/detach: `RenderObject` recurses through `visitChildren`, which
    // covers every cell (`table.dart:920-939` do the same walk by hand).

    // MARK: - Visit Children

    /// Visits each non-nil child.
    ///
    /// **Dart Source:** `table.dart:942-949`
    public override func visitChildren(_ visitor: RenderObjectVisitor) {
        assert(_children.count == _rows * _columns)
        for child in _children {
            if let child = child {
                visitor(child)
            }
        }
    }

    // MARK: - Column / Row Helper Methods

    /// Returns the list of cells in the given column.
    ///
    /// This is useful for column width computations.
    internal func column(_ x: Int) -> [RenderBox] {
        var result: [RenderBox] = []
        for y in 0..<_rows {
            let child = _children[x + y * _columns]
            if let child = child {
                result.append(child)
            }
        }
        return result
    }

    /// Returns the list of cells in the given row.
    ///
    /// This is useful for row height computations.
    internal func row(_ y: Int) -> [RenderBox] {
        var result: [RenderBox] = []
        for x in 0..<_columns {
            let child = _children[x + y * _columns]
            if let child = child {
                result.append(child)
            }
        }
        return result
    }

    // MARK: - Layout

    /// Computes the minimum intrinsic width of the table.
    ///
    /// Returns the sum of the minimum intrinsic widths of all columns.
    ///
    /// **Dart Source:** `table.dart:958-967`
    public override func computeMinIntrinsicWidth(_ height: Double) -> Double {
        assert(_children.count == _rows * _columns)
        var totalMinWidth = 0.0
        for x in 0..<_columns {
            let columnWidth = _columnWidths[x] ?? _defaultColumnWidth
            let columnCells = column(x)
            totalMinWidth += columnWidth.minIntrinsicWidth(cells: columnCells, containerWidth: .infinity)
        }
        return totalMinWidth
    }

    /// Computes the maximum intrinsic width of the table.
    ///
    /// Returns the sum of the maximum intrinsic widths of all columns.
    ///
    /// **Dart Source:** `table.dart:970-978`
    public override func computeMaxIntrinsicWidth(_ height: Double) -> Double {
        assert(_children.count == _rows * _columns)
        var totalMaxWidth = 0.0
        for x in 0..<_columns {
            let columnWidth = _columnWidths[x] ?? _defaultColumnWidth
            let columnCells = column(x)
            totalMaxWidth += columnWidth.maxIntrinsicWidth(cells: columnCells, containerWidth: .infinity)
        }
        return totalMaxWidth
    }

    /// Computes the minimum intrinsic height of the table.
    ///
    /// First computes column widths, then sums up the max intrinsic
    /// height of each row.
    ///
    /// **Dart Source:** `table.dart:982-1000`
    public override func computeMinIntrinsicHeight(_ width: Double) -> Double {
        assert(_children.count == _rows * _columns)
        let widths = _computeColumnWidths(constraints: BoxConstraints.tightForFinite(width: width))
        var rowTop = 0.0
        for y in 0..<_rows {
            var rowHeight = 0.0
            for x in 0..<_columns {
                let xy = x + y * _columns
                if let child = _children[xy] {
                    rowHeight = max(rowHeight, child.getMaxIntrinsicHeight(widths[x]))
                }
            }
            rowTop += rowHeight
        }
        return rowTop
    }

    /// Computes the maximum intrinsic height of the table.
    ///
    /// For tables, this is the same as the minimum intrinsic height.
    ///
    /// **Dart Source:** `table.dart:1003-1005`
    public override func computeMaxIntrinsicHeight(_ width: Double) -> Double {
        return getMinIntrinsicHeight(width)
    }

    /// The baseline distance for the first row, used for baseline alignment.
    ///
    /// **Dart Source:** `table.dart:1007`
    private var _baselineDistance: Double?

    /// Returns the distance to the actual baseline.
    ///
    /// **Dart Source:** `table.dart:1008-1014`
    public override func computeDistanceToActualBaseline(_ baseline: TextBaseline) -> Double? {
        return _baselineDistance
    }

    /// Computes the column widths for the table using the column width strategies.
    ///
    /// The algorithm proceeds in four steps:
    /// 1. Apply ideal widths (maxIntrinsicWidth) and collect flex information
    /// 2. Grow flex columns so the table reaches the target width
    /// 3. If no flex columns, grow all columns evenly to reach minWidth
    /// 4. Shrink columns proportionally if the table exceeds maxWidth
    ///
    /// **Dart Source:** `table.dart:1049-1216`
    private func _computeColumnWidths(constraints: BoxConstraints) -> [Double] {
        assert(_children.count == _rows * _columns)

        // 1. Apply ideal widths, and collect information we'll need later
        var widths = [Double](repeating: 0.0, count: _columns)
        var minWidths = [Double](repeating: 0.0, count: _columns)
        var flexes = [Double?](repeating: nil, count: _columns)
        var tableWidth = 0.0
        var unflexedTableWidth = 0.0
        var totalFlex = 0.0

        for x in 0..<_columns {
            let columnWidth = _columnWidths[x] ?? _defaultColumnWidth
            let columnCells = column(x)

            // Apply ideal width (maxIntrinsicWidth)
            let maxIntrinsicWidth = columnWidth.maxIntrinsicWidth(
                cells: columnCells,
                containerWidth: constraints.maxWidth
            )
            assert(maxIntrinsicWidth.isFinite)
            assert(maxIntrinsicWidth >= 0.0)
            widths[x] = maxIntrinsicWidth
            tableWidth += maxIntrinsicWidth

            // Collect min width information
            let minIntrinsicWidth = columnWidth.minIntrinsicWidth(
                cells: columnCells,
                containerWidth: constraints.maxWidth
            )
            assert(minIntrinsicWidth.isFinite)
            assert(minIntrinsicWidth >= 0.0)
            minWidths[x] = minIntrinsicWidth
            assert(maxIntrinsicWidth >= minIntrinsicWidth)

            // Collect flex information
            let flex = columnWidth.flex(cells: columnCells)
            if let flex = flex {
                assert(flex.isFinite)
                assert(flex > 0.0)
                flexes[x] = flex
                totalFlex += flex
            } else {
                unflexedTableWidth += maxIntrinsicWidth
            }
        }

        let maxWidthConstraint = constraints.maxWidth
        let minWidthConstraint = constraints.minWidth

        // 2. Grow flex columns so the table has the maxWidth (if finite) or minWidth (if not)
        if totalFlex > 0.0 {
            let targetWidth: Double
            if maxWidthConstraint.isFinite {
                targetWidth = maxWidthConstraint
            } else {
                targetWidth = minWidthConstraint
            }
            if tableWidth < targetWidth {
                let remainingWidth = targetWidth - unflexedTableWidth
                assert(remainingWidth.isFinite)
                assert(remainingWidth >= 0.0)
                for x in 0..<_columns {
                    if flexes[x] != nil {
                        let flexedWidth = remainingWidth * flexes[x]! / totalFlex
                        assert(flexedWidth.isFinite)
                        assert(flexedWidth >= 0.0)
                        if widths[x] < flexedWidth {
                            let delta = flexedWidth - widths[x]
                            tableWidth += delta
                            widths[x] = flexedWidth
                        }
                    }
                }
                assert(tableWidth + precisionErrorTolerance >= targetWidth)
            }
        }
        // Step 2 and 3 are mutually exclusive
        // 3. If there were no flex columns, grow the table to the minWidth
        else if tableWidth < minWidthConstraint {
            let delta = (minWidthConstraint - tableWidth) / Double(_columns)
            for x in 0..<_columns {
                widths[x] = widths[x] + delta
            }
            tableWidth = minWidthConstraint
        }

        // Beyond this point, unflexedTableWidth is no longer valid

        // 4. Apply the maximum width of the table, shrinking columns as
        //    necessary, applying minimum column widths as we go
        if tableWidth > maxWidthConstraint {
            var deficit = tableWidth - maxWidthConstraint
            var availableColumns = _columns

            // Shrink flex columns proportionally first
            while deficit > precisionErrorTolerance && totalFlex > precisionErrorTolerance {
                var newTotalFlex = 0.0
                for x in 0..<_columns {
                    if flexes[x] != nil {
                        let newWidth = widths[x] - deficit * flexes[x]! / totalFlex
                        assert(newWidth.isFinite)
                        if newWidth <= minWidths[x] {
                            // Shrank to minimum
                            deficit -= widths[x] - minWidths[x]
                            widths[x] = minWidths[x]
                            flexes[x] = nil
                            availableColumns -= 1
                        } else {
                            deficit -= widths[x] - newWidth
                            widths[x] = newWidth
                            newTotalFlex += flexes[x]!
                        }
                        assert(widths[x] >= 0.0)
                    }
                }
                totalFlex = newTotalFlex
            }

            // Then shrink non-minimum columns evenly
            while deficit > precisionErrorTolerance && availableColumns > 0 {
                let delta = deficit / Double(availableColumns)
                assert(delta != 0)
                var newAvailableColumns = 0
                for x in 0..<_columns {
                    let availableDelta = widths[x] - minWidths[x]
                    if availableDelta > 0.0 {
                        if availableDelta <= delta {
                            // Shrank to minimum
                            deficit -= widths[x] - minWidths[x]
                            widths[x] = minWidths[x]
                        } else {
                            deficit -= delta
                            widths[x] = widths[x] - delta
                            newAvailableColumns += 1
                        }
                    }
                }
                availableColumns = newAvailableColumns
            }
        }
        return widths
    }

    // MARK: - Table Geometry Cache

    /// Cumulative row top positions (length == rows + 1 after layout).
    ///
    /// **Dart Source:** `table.dart:1219`
    private var _rowTops: [Double] = []

    /// Column left positions, accounting for text direction.
    ///
    /// **Dart Source:** `table.dart:1220`
    private var _columnLefts: [Double]?

    /// The computed table width from the last layout pass.
    ///
    /// **Dart Source:** `table.dart:1221`
    private var _tableWidth: Double = 0.0

    /// Returns the position and dimensions of the box that the given
    /// row covers, in this render object's coordinate space (so the
    /// left coordinate is always 0.0).
    ///
    /// The row being queried must exist.
    /// This is only valid after layout.
    ///
    /// **Dart Source:** `table.dart:1230-1235`
    public func getRowBox(_ row: Int) -> Rect {
        assert(row >= 0)
        assert(row < _rows)
        return Rect.fromLTRB(0.0, _rowTops[row], size.width, _rowTops[row + 1])
    }

    /// Lays out the table: computes column widths, lays out cells, computes
    /// row heights (with baseline alignment), and positions each cell.
    ///
    /// **Dart Source:** `table.dart:1310-1430`
    public override func performLayout() {
        let constraints = self.boxConstraints
        let rows = self._rows
        let columns = self._columns
        assert(_children.count == rows * columns)

        if rows * columns == 0 {
            _tableWidth = 0.0
            size = constraints.constrain(Size.zero)
            return
        }

        let widths = _computeColumnWidths(constraints: constraints)
        var positions = [Double](repeating: 0.0, count: columns)

        switch _textDirection {
        case .rtl:
            positions[columns - 1] = 0.0
            for x in stride(from: columns - 2, through: 0, by: -1) {
                positions[x] = positions[x + 1] + widths[x + 1]
            }
            _columnLefts = positions.reversed()
            _tableWidth = positions[0] + widths[0]
        case .ltr:
            positions[0] = 0.0
            for x in 1..<columns {
                positions[x] = positions[x - 1] + widths[x - 1]
            }
            _columnLefts = positions
            _tableWidth = positions[columns - 1] + widths[columns - 1]
        }

        _rowTops.removeAll()
        _baselineDistance = nil

        // Lay out each row
        var rowTop = 0.0
        for y in 0..<rows {
            _rowTops.append(rowTop)
            var rowHeight = 0.0
            var haveBaseline = false
            var beforeBaselineDistance = 0.0
            var afterBaselineDistance = 0.0
            var baselines = [Double](repeating: 0.0, count: columns)

            // First pass: layout cells and compute row height
            for x in 0..<columns {
                let xy = x + y * columns
                if let child = _children[xy] {
                    let childParentData = child.parentData as! TableCellParentData
                    childParentData.x = x
                    childParentData.y = y
                    let vertAlignment = childParentData.verticalAlignment ?? _defaultVerticalAlignment
                    switch vertAlignment {
                    case .baseline:
                        assert(
                            _textBaseline != nil,
                            "An explicit textBaseline is required when using baseline alignment."
                        )
                        child.layout(
                            BoxConstraints.tightFor(width: widths[x]),
                            parentUsesSize: true
                        )
                        let childBaseline = child.getDistanceToBaseline(
                            _textBaseline!,
                            onlyReal: true
                        )
                        if let childBaseline = childBaseline {
                            beforeBaselineDistance = max(beforeBaselineDistance, childBaseline)
                            afterBaselineDistance = max(
                                afterBaselineDistance,
                                child.size.height - childBaseline
                            )
                            baselines[x] = childBaseline
                            haveBaseline = true
                        } else {
                            rowHeight = max(rowHeight, child.size.height)
                            childParentData.offset = Offset(positions[x], rowTop)
                        }
                    case .top, .middle, .bottom, .intrinsicHeight:
                        child.layout(
                            BoxConstraints.tightFor(width: widths[x]),
                            parentUsesSize: true
                        )
                        rowHeight = max(rowHeight, child.size.height)
                    case .fill:
                        break
                    }
                }
            }

            if haveBaseline {
                if y == 0 {
                    _baselineDistance = beforeBaselineDistance
                }
                rowHeight = max(rowHeight, beforeBaselineDistance + afterBaselineDistance)
            }

            // Second pass: position cells based on vertical alignment
            for x in 0..<columns {
                let xy = x + y * columns
                if let child = _children[xy] {
                    let childParentData = child.parentData as! TableCellParentData
                    let vertAlignment = childParentData.verticalAlignment ?? _defaultVerticalAlignment
                    switch vertAlignment {
                    case .baseline:
                        childParentData.offset = Offset(
                            positions[x],
                            rowTop + beforeBaselineDistance - baselines[x]
                        )
                    case .top:
                        childParentData.offset = Offset(positions[x], rowTop)
                    case .middle:
                        childParentData.offset = Offset(
                            positions[x],
                            rowTop + (rowHeight - child.size.height) / 2.0
                        )
                    case .bottom:
                        childParentData.offset = Offset(
                            positions[x],
                            rowTop + rowHeight - child.size.height
                        )
                    case .fill, .intrinsicHeight:
                        child.layout(
                            BoxConstraints.tightFor(width: widths[x], height: rowHeight)
                        )
                        childParentData.offset = Offset(positions[x], rowTop)
                    }
                }
            }
            rowTop += rowHeight
        }

        _rowTops.append(rowTop)
        size = constraints.constrain(Size(_tableWidth, rowTop))
        assert(_rowTops.count == rows + 1)
    }

    // MARK: - Hit Testing

    /// Hit tests the children of the table in reverse order.
    ///
    /// Returns true if a child was hit.
    ///
    /// **Dart Source:** `table.dart:1433-1453`
    public override func hitTestChildren(
        _ result: BoxHitTestResult,
        position: Offset
    ) -> Bool {
        assert(_children.count == _rows * _columns)
        for index in stride(from: _children.count - 1, through: 0, by: -1) {
            if let child = _children[index] {
                let childParentData = child.parentData as! BoxParentData
                let isHit = result.addWithPaintOffset(
                    offset: childParentData.offset,
                    position: position,
                    hitTest: { (result: BoxHitTestResult, transformed: Offset) -> Bool in
                        return child.hitTest(result, position: transformed)
                    }
                )
                if isHit {
                    return true
                }
            }
        }
        return false
    }

    // MARK: - Paint

    /// Paints the table's children and border.
    ///
    /// Each child is painted at its offset. Then, if a border is specified,
    /// it is painted using `TableBorder.paint`.
    ///
    /// **Dart Source:** `table.dart:1456-1506`
    public override func paint(_ context: PaintingContext, _ offset: Offset) {
        assert(_children.count == _rows * _columns)
        if _rows * _columns == 0 {
            if let border = _border {
                let borderRect = Rect.fromLTWH(offset.dx, offset.dy, _tableWidth, 0.0)
                border.paint(
                    context.canvas,
                    borderRect,
                    rows: [],
                    columns: []
                )
            }
            return
        }
        assert(_rowTops.count == _rows + 1)

        // Paint children
        for index in 0..<_children.count {
            if let child = _children[index] {
                let childParentData = child.parentData as! BoxParentData
                context.paintChild(child, childParentData.offset + offset)
            }
        }

        // Paint border
        assert(_rows == _rowTops.count - 1)
        assert(_columns == _columnLefts!.count)
        if let border = _border {
            let borderRect = Rect.fromLTWH(
                offset.dx,
                offset.dy,
                _tableWidth,
                _rowTops.last!
            )
            let rowDividers = Array(_rowTops[1..<(_rowTops.count - 1)])
            let columnDividers = Array(_columnLefts![1...])
            border.paint(context.canvas, borderRect, rows: rowDividers, columns: columnDividers)
        }
    }

    // MARK: - Cell Rect

    /// Returns the `Rect` for a given cell specified by column and row.
    ///
    /// This is only valid after layout.
    ///
    /// **Dart Source:** (utility method)
    public func rect(col: Int, row: Int) -> Rect {
        assert(_columnLefts != nil && _columnLefts!.count == _columns)
        assert(_rowTops.count == _rows + 1)
        assert(col >= 0 && col < _columns)
        assert(row >= 0 && row < _rows)
        let left = _columnLefts![col]
        let right: Double
        if col + 1 < _columns {
            right = _columnLefts![col + 1]
        } else {
            right = _tableWidth
        }
        return Rect.fromLTRB(left, _rowTops[row], right, _rowTops[row + 1])
    }

    // MARK: - Diagnostics

    /// Adds table-specific properties to the diagnostics tree.
    ///
    /// **Dart Source:** `table.dart:1509-1533`
    public func debugFillProperties(_ properties: DiagnosticPropertiesBuilder) {
        // TODO: Call super.debugFillProperties(properties) once available on RenderBox.
        properties.add(
            DiagnosticsProperty<String>("border", _border.map { String(describing: $0) })
        )
        properties.add(
            DiagnosticsProperty<String>(
                "specified column widths",
                _columnWidths.isEmpty ? nil : String(describing: _columnWidths)
            )
        )
        properties.add(
            DiagnosticsProperty<String>(
                "default column width",
                String(describing: _defaultColumnWidth)
            )
        )
        properties.add(
            DiagnosticsProperty<String>("table size", "\(_columns)\u{00D7}\(_rows)")
        )
        properties.add(
            DiagnosticsProperty<String>(
                "column offsets",
                _columnLefts.map { String(describing: $0) },
                defaultValue: nil
            )
        )
        properties.add(
            DiagnosticsProperty<String>(
                "row offsets",
                String(describing: _rowTops),
                defaultValue: nil
            )
        )
    }
}

// MARK: - _Index

/// Simple (column, row) index pair for cell identification.
///
/// **Dart Source:** `table.dart:1558-1562`
private struct _Index: Hashable {
    let x: Int
    let y: Int

    init(_ y: Int, _ x: Int) {
        self.x = x
        self.y = y
    }
}
