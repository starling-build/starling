// Ported from: fluent_ui/lib/src/controls/navigation/tree_view.dart

import FlutterSwiftBridge

// MARK: - Constants

private let _kTreeViewWhiteSpace: Double = 8.0
private let _kTreeViewItemHeight: Double = 36.0
private let _kTreeViewIndent: Double = 28.0
private let _kTreeViewNarrowIndent: Double = 20.0
private let _kExpandIconSize: Double = 12.0

// MARK: - TreeViewSelectionMode

/// The selection mode of a `TreeView`.
public enum TreeViewSelectionMode {
    /// Selection is disabled.
    case none

    /// Only a single item can be selected at a time.
    case single

    /// Multiple items can be selected, with checkboxes shown next to each item.
    case multiple
}

// MARK: - TreeViewItem

/// An item displayed in a `TreeView` hierarchy.
///
/// Each item represents a node in the tree and can contain child items
/// for hierarchical structure.
public class TreeViewItem {
    /// The main content of the item. Usually a `Text` widget.
    public let content: Widget

    /// Nested child items for hierarchical structure.
    public var children: [TreeViewItem]

    /// Whether the item is currently expanded (showing children).
    /// Has no effect if `children` is empty.
    public var expanded: Bool

    /// Whether the item is currently selected.
    public var selected: Bool

    /// An optional widget displayed before the content (usually an icon).
    public let leading: Widget?

    /// An optional/arbitrary value associated with the item.
    public let value: AnyObject?

    /// Whether this item's children can be collapsed by user input.
    public let collapsable: Bool

    /// The parent item, if any. Set internally during tree building.
    public var parent: TreeViewItem?

    /// Creates a tree view item.
    public init(
        content: Widget,
        children: [TreeViewItem] = [],
        expanded: Bool? = nil,
        selected: Bool = false,
        leading: Widget? = nil,
        value: AnyObject? = nil,
        collapsable: Bool = true
    ) {
        self.content = content
        self.children = children
        self.expanded = expanded ?? !children.isEmpty
        self.selected = selected
        self.leading = leading
        self.value = value
        self.collapsable = collapsable
    }

    /// Whether this node has children and can be expanded.
    public var isExpandable: Bool {
        return !children.isEmpty
    }

    /// The depth of this item in the tree hierarchy.
    /// Root items have a depth of 0.
    public var depth: Int {
        var count = 0
        var current = parent
        while current != nil {
            count += 1
            current = current?.parent
        }
        return count
    }
}

// MARK: - TreeView

/// A hierarchical list with expanding and collapsing nodes.
///
/// `TreeView` displays nested items in a tree structure, using indentation
/// and icons to show parent-child relationships. It supports single and
/// multiple selection modes.
public class TreeView: StatefulWidget {
    /// The root items of the tree view.
    public let items: [TreeViewItem]

    /// The current selection mode.
    public let selectionMode: TreeViewSelectionMode

    /// Called when an item is invoked (pressed).
    public let onItemInvoked: ((TreeViewItem) -> Void)?

    /// Called when the selection changes.
    public let onSelectionChanged: (([TreeViewItem]) -> Void)?

    /// Whether to use narrow spacing for a more compact tree.
    public let narrowSpacing: Bool

    /// Creates a tree view.
    public init(
        key: (any Key)? = nil,
        items: [TreeViewItem],
        selectionMode: TreeViewSelectionMode = .none,
        onItemInvoked: ((TreeViewItem) -> Void)? = nil,
        onSelectionChanged: (([TreeViewItem]) -> Void)? = nil,
        narrowSpacing: Bool = false
    ) {
        self.items = items
        self.selectionMode = selectionMode
        self.onItemInvoked = onItemInvoked
        self.onSelectionChanged = onSelectionChanged
        self.narrowSpacing = narrowSpacing
        super.init(key: key)
    }

    public override func createState() -> State<StatefulWidget> {
        return _TreeViewState()
    }
}

// MARK: - _TreeViewState

class _TreeViewState: State<StatefulWidget> {

    private var treeView: TreeView {
        return widget as! TreeView
    }

    override func initState() {
        super.initState()
        _buildParentReferences(treeView.items, parent: nil)
    }

    /// Sets up parent references for all items recursively.
    private func _buildParentReferences(_ items: [TreeViewItem], parent: TreeViewItem?) {
        for item in items {
            item.parent = parent
            _buildParentReferences(item.children, parent: item)
        }
    }

    override func build(_ context: any BuildContext) -> Widget {
        // Flatten the tree into a visible list
        var flatItems: [TreeViewItem] = []
        _flattenItems(treeView.items, into: &flatItems)

        // Build the column of items
        var itemWidgets: [Widget] = []
        for item in flatItems {
            itemWidgets.append(
                _buildTreeItem(context, item: item)
            )
        }

        return Column(
            mainAxisSize: .min,
            crossAxisAlignment: .stretch,
            children: itemWidgets
        )
    }

    /// Flattens the tree into a list of visible items.
    private func _flattenItems(_ items: [TreeViewItem], into result: inout [TreeViewItem]) {
        for item in items {
            result.append(item)
            if item.expanded && !item.children.isEmpty {
                _flattenItems(item.children, into: &result)
            }
        }
    }

    // MARK: - Tree Item Builder

    private func _buildTreeItem(_ context: any BuildContext, item: TreeViewItem) -> Widget {
        let theme = FluentTheme.of(context)
        let res = theme.resources
        let w = treeView
        let indent = w.narrowSpacing ? _kTreeViewNarrowIndent : _kTreeViewIndent
        let itemHeight = w.narrowSpacing ? 28.0 : _kTreeViewItemHeight

        return HoverButton(
            builder: { [self] context, states in
                // Background color
                let bgColor: Color = {
                    if item.selected && w.selectionMode != .none {
                        return theme.accentColor.defaultBrushFor(theme.brightness).withOpacity(0.1)
                    } else if states.isPressed {
                        return res.subtleFillColorTertiary
                    } else if states.isHovered {
                        return res.subtleFillColorSecondary
                    } else {
                        return res.subtleFillColorTransparent
                    }
                }()

                // Foreground color
                let fgColor: Color = {
                    if states.isDisabled {
                        return res.textFillColorDisabled
                    } else {
                        return res.textFillColorPrimary
                    }
                }()

                // Build row content
                var rowChildren: [Widget] = []

                // Indentation
                let indentWidth = Double(item.depth) * indent
                if indentWidth > 0 {
                    rowChildren.append(SizedBox(width: indentWidth))
                }

                // Expand/collapse chevron
                if item.isExpandable {
                                        let chevronButton: Widget = SizedBox(
                        width: indent,
                        height: itemHeight,
                        child: Center(
                            child: FluentGlyph(item.expanded ? .chevronDown : .chevronRight,
                                        size: _kExpandIconSize, color: fgColor)
                        )
                    )
                    rowChildren.append(chevronButton)
                } else {
                    // Spacer for alignment (leaf nodes)
                    let hasSiblingsWithChildren = _hasSiblingsWithChildren(item)
                    if hasSiblingsWithChildren {
                        rowChildren.append(SizedBox(width: indent))
                    } else {
                        rowChildren.append(SizedBox(width: _kTreeViewWhiteSpace))
                    }
                }

                // Selection checkbox (for multiple selection mode)
                if w.selectionMode == .multiple {
                                        let checkColor = item.selected
                        ? theme.activeColor
                        : Color(0x00000000)
                    let checkBg = item.selected
                        ? theme.accentColor.defaultBrushFor(theme.brightness)
                        : Color(0x00000000)
                    let checkBorderColor = item.selected
                        ? theme.accentColor.defaultBrushFor(theme.brightness)
                        : res.controlStrongStrokeColorDefault

                    let checkbox: Widget = _TreeDecoratedBox(
                        decoration: BoxDecoration(
                            color: checkBg,
                            border: Border.all(color: checkBorderColor),
                            borderRadius: BorderRadius.circular(3)
                        ),
                        child: SizedBox(
                            width: 18,
                            height: 18,
                            child: Center(
                                child: FluentGlyph(.check, size: 11, color: checkColor)
                            )
                        )
                    )

                    rowChildren.append(
                        Padding(
                            padding: EdgeInsets(left: 0, top: 0, right: 8, bottom: 0),
                            child: checkbox
                        )
                    )
                }

                // Leading widget
                if let leading = item.leading {
                    rowChildren.append(
                        Padding(
                            padding: EdgeInsets(left: 0, top: 0, right: 8, bottom: 0),
                            child: IconTheme(
                                data: IconThemeData(size: 16, color: fgColor),
                                child: leading
                            )
                        )
                    )
                }

                // Content
                rowChildren.append(
                    Expanded(
                        child: DefaultTextStyle(
                            style: TextStyle(color: fgColor, fontSize: 14),
                            child: item.content
                        )
                    )
                )

                // Item row with background
                var result: Widget = _TreeDecoratedBox(
                    decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(4)
                    ),
                    child: SizedBox(
                        height: itemHeight,
                        child: Padding(
                            padding: EdgeInsets(left: _kTreeViewWhiteSpace, top: 0, right: _kTreeViewWhiteSpace, bottom: 0),
                            child: Row(children: rowChildren)
                        )
                    )
                )

                // Selection indicator (accent bar on left side for single selection)
                if item.selected && w.selectionMode == .single {
                    let indicator: Widget = _TreeDecoratedBox(
                        decoration: BoxDecoration(
                            color: theme.accentColor.defaultBrushFor(theme.brightness),
                            borderRadius: BorderRadius.circular(1.5)
                        ),
                        child: SizedBox(
                            width: 3,
                            height: itemHeight * 0.5
                        )
                    )

                    result = Row(
                        children: [
                            indicator,
                            Expanded(child: result),
                        ]
                    )
                }

                return Padding(
                    padding: EdgeInsets(left: 2, top: 1, right: 2, bottom: 1),
                    child: result
                )
            },
            onPressed: { [weak self] in
                guard let self = self else { return }
                self._handleItemPressed(item)
            }
        )
    }

    /// Checks if any sibling (or itself) has children.
    private func _hasSiblingsWithChildren(_ item: TreeViewItem) -> Bool {
        let siblings: [TreeViewItem]
        if let parent = item.parent {
            siblings = parent.children
        } else {
            siblings = treeView.items
        }
        return siblings.contains { $0.isExpandable }
    }

    // MARK: - Interaction Handlers

    private func _handleItemPressed(_ item: TreeViewItem) {
        let w = treeView

        // Toggle expand/collapse if expandable
        if item.isExpandable && item.collapsable {
            setState {
                item.expanded = !item.expanded
            }
        }

        // Handle selection
        switch w.selectionMode {
        case .none:
            break
        case .single:
            setState {
                self._deselectAll(w.items)
                item.selected = true
            }
            w.onSelectionChanged?([item])
        case .multiple:
            setState {
                item.selected = !item.selected
                self._setSelectionRecursive(item.children, selected: item.selected)
            }
            var selectedItems: [TreeViewItem] = []
            _gatherSelectedItems(w.items, into: &selectedItems)
            w.onSelectionChanged?(selectedItems)
        }

        // Invoke callback
        w.onItemInvoked?(item)
    }

    /// Deselects all items recursively.
    private func _deselectAll(_ items: [TreeViewItem]) {
        for item in items {
            item.selected = false
            _deselectAll(item.children)
        }
    }

    /// Sets the selected state for all items recursively.
    private func _setSelectionRecursive(_ items: [TreeViewItem], selected: Bool) {
        for item in items {
            item.selected = selected
            _setSelectionRecursive(item.children, selected: selected)
        }
    }

    /// Gathers all currently selected items into a list.
    private func _gatherSelectedItems(_ items: [TreeViewItem], into result: inout [TreeViewItem]) {
        for item in items {
            if item.selected {
                result.append(item)
            }
            _gatherSelectedItems(item.children, into: &result)
        }
    }
}

// MARK: - _TreeDecoratedBox (private helper)

/// A widget that paints a `Decoration` behind its child.
private class _TreeDecoratedBox: SingleChildRenderObjectWidget {
    let decoration: Decoration

    init(
        key: (any Key)? = nil,
        decoration: Decoration,
        child: Widget? = nil
    ) {
        self.decoration = decoration
        super.init(key: key, child: child)
    }

    override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        return RenderDecoratedBox(decoration: decoration)
    }

    override func updateRenderObject(_ context: any BuildContext, renderObject: RenderObject) {
        let ro = renderObject as! RenderDecoratedBox
        ro.decoration = decoration
    }
}

// MARK: - TreeViewThemeData

/// Theme data for `TreeView` widgets.
public class TreeViewThemeData {
    /// The background color of the tree view.
    public let backgroundColor: Color?

    /// The color of the selection indicator.
    public let selectionIndicatorColor: Color?

    /// The indent amount per level.
    public let indent: Double?

    /// The height of each item.
    public let itemHeight: Double?

    /// The padding applied to each item.
    public let itemPadding: EdgeInsets?

    public init(
        backgroundColor: Color? = nil,
        selectionIndicatorColor: Color? = nil,
        indent: Double? = nil,
        itemHeight: Double? = nil,
        itemPadding: EdgeInsets? = nil
    ) {
        self.backgroundColor = backgroundColor
        self.selectionIndicatorColor = selectionIndicatorColor
        self.indent = indent
        self.itemHeight = itemHeight
        self.itemPadding = itemPadding
    }

    /// Creates the standard theme data based on the given theme.
    public static func standard(_ theme: FluentThemeData) -> TreeViewThemeData {
        return TreeViewThemeData(
            indent: _kTreeViewIndent,
            itemHeight: _kTreeViewItemHeight
        )
    }

    /// Merge this theme data with another, with the other taking precedence.
    public func merge(_ other: TreeViewThemeData?) -> TreeViewThemeData {
        guard let other = other else { return self }
        return TreeViewThemeData(
            backgroundColor: other.backgroundColor ?? backgroundColor,
            selectionIndicatorColor: other.selectionIndicatorColor ?? selectionIndicatorColor,
            indent: other.indent ?? indent,
            itemHeight: other.itemHeight ?? itemHeight,
            itemPadding: other.itemPadding ?? itemPadding
        )
    }
}

// MARK: - TreeViewTheme

/// An inherited theme that controls how descendant `TreeView` widgets look.
public class TreeViewTheme: InheritedTheme {
    /// The theme data for the tree view theme.
    public let data: TreeViewThemeData

    public init(key: (any Key)? = nil, data: TreeViewThemeData, child: Widget) {
        self.data = data
        super.init(key: key, child: child)
    }

    /// Returns the closest `TreeViewThemeData` which encloses the given context.
    public static func of(_ context: any BuildContext) -> TreeViewThemeData {
        let theme = FluentTheme.of(context)
        let inherited = context.dependOnInheritedWidgetOfExactType(TreeViewTheme.self)
        return TreeViewThemeData.standard(theme).merge(inherited?.data)
    }

    public override func updateShouldNotify(_ oldWidget: InheritedWidget) -> Bool {
        guard let old = oldWidget as? TreeViewTheme else { return true }
        return data !== old.data
    }

    public override func wrap(_ context: any BuildContext, _ child: Widget) -> Widget {
        return TreeViewTheme(data: data, child: child)
    }
}
