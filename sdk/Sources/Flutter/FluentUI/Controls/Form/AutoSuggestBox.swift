// Ported from: fluent_ui/lib/src/controls/form/auto_suggest_box.dart (simplified)
//
// A text input with a suggestion dropdown. As the user types, matching items
// are filtered and displayed in a flyout below the input. Selecting an item
// populates the text field.

import FlutterSwiftBridge

// MARK: - AutoSuggestBoxItem

/// A single suggestion item for an `AutoSuggestBox`.
///
/// Each item has a `value` string used for filtering and display, plus an
/// optional `child` widget for custom rendering. When no `child` is provided,
/// the item renders as a simple `Text` widget.
public class AutoSuggestBoxItem {
    /// The string value of this item, used for default filtering and display.
    public let value: String

    /// An optional custom widget for rendering this item. If nil, a `Text`
    /// widget displaying `value` is used.
    public let child: Widget?

    /// Called when this item is tapped, before `onSelected` on the parent.
    public let onTap: (() -> Void)?

    /// Creates an auto suggest box item.
    public init(
        value: String,
        child: Widget? = nil,
        onTap: (() -> Void)? = nil
    ) {
        self.value = value
        self.child = child
        self.onTap = onTap
    }
}

// MARK: - AutoSuggestBox

/// A Fluent UI auto-suggest text input.
///
/// Displays a `FluentTextBox` that, as the user types, shows a dropdown
/// flyout of filtered suggestion items. The user can select an item to
/// populate the text field.
///
/// Usage:
/// ```swift
/// AutoSuggestBox(
///     items: [
///         AutoSuggestBoxItem(value: "Apple"),
///         AutoSuggestBoxItem(value: "Banana"),
///         AutoSuggestBoxItem(value: "Cherry"),
///     ],
///     onSelected: { item in
///         print("Selected: \(item.value)")
///     }
/// )
/// ```
public class AutoSuggestBox: StatefulWidget {
    /// Controls the text being edited. If nil, an internal controller is created.
    public let controller: TextEditingController?

    /// The suggestion items to filter and display.
    public let items: [AutoSuggestBoxItem]

    /// Called when the text in the text box changes.
    public let onChanged: ((String) -> Void)?

    /// Called when the user selects a suggestion item.
    public let onSelected: ((AutoSuggestBoxItem) -> Void)?

    /// A custom filter function. Receives the current query string and the item,
    /// and returns true if the item should be shown. If nil, a default
    /// case-insensitive contains filter is used.
    public let filterFn: ((String, AutoSuggestBoxItem) -> Bool)?

    /// Placeholder text displayed when the text field is empty.
    public let placeholderText: String?

    /// Whether the text box is enabled.
    public let enabled: Bool

    /// The placement for the suggestion flyout. Defaults to `.bottom`.
    public let placement: FlyoutPlacement

    /// The maximum number of visible suggestions before scrolling.
    public let maxSuggestionsHeight: Double

    /// The text style for the text box.
    public let style: TextStyle?

    /// The decoration for the text box.
    public let decoration: BoxDecoration?

    /// A widget displayed before the text (prefix).
    public let leadingIcon: Widget?

    /// A widget displayed after the text (suffix / trailing icon).
    public let trailingIcon: Widget?

    /// Whether to clear the text field when an item is selected.
    public let clearOnSelect: Bool

    /// Creates a Fluent UI auto suggest box.
    public init(
        key: (any Key)? = nil,
        controller: TextEditingController? = nil,
        items: [AutoSuggestBoxItem] = [],
        onChanged: ((String) -> Void)? = nil,
        onSelected: ((AutoSuggestBoxItem) -> Void)? = nil,
        filterFn: ((String, AutoSuggestBoxItem) -> Bool)? = nil,
        placeholderText: String? = nil,
        enabled: Bool = true,
        placement: FlyoutPlacement = .bottom,
        maxSuggestionsHeight: Double = 300,
        style: TextStyle? = nil,
        decoration: BoxDecoration? = nil,
        leadingIcon: Widget? = nil,
        trailingIcon: Widget? = nil,
        clearOnSelect: Bool = false
    ) {
        self.controller = controller
        self.items = items
        self.onChanged = onChanged
        self.onSelected = onSelected
        self.filterFn = filterFn
        self.placeholderText = placeholderText
        self.enabled = enabled
        self.placement = placement
        self.maxSuggestionsHeight = maxSuggestionsHeight
        self.style = style
        self.decoration = decoration
        self.leadingIcon = leadingIcon
        self.trailingIcon = trailingIcon
        self.clearOnSelect = clearOnSelect
        super.init(key: key)
    }

    public override func createState() -> State<StatefulWidget> {
        return _AutoSuggestBoxState()
    }
}

// MARK: - _AutoSuggestBoxState

class _AutoSuggestBoxState: State<StatefulWidget> {
    private let _flyoutController = FlyoutController()

    /// Internal controller created when the user doesn't provide one.
    private var _controller: TextEditingController?

    /// The effective controller (user-provided or internal).
    private var _effectiveController: TextEditingController {
        return autoSuggestBox.controller ?? _controller!
    }

    /// The currently filtered suggestion items.
    private var _filteredItems: [AutoSuggestBoxItem] = []

    /// Listener reference for controller changes.
    private var _boundListener: VoidCallback?

    private var autoSuggestBox: AutoSuggestBox {
        return widget as! AutoSuggestBox
    }

    override func initState() {
        super.initState()
        if autoSuggestBox.controller == nil {
            _controller = TextEditingController()
        }
        _boundListener = { [weak self] in
            self?._onTextChanged()
        }
        _effectiveController.addListener(_boundListener!)
        _updateFilteredItems(_effectiveController.text)
    }

    override func dispose() {
        if let listener = _boundListener {
            _effectiveController.removeListener(listener)
        }
        _flyoutController.closeFlyout()
        _controller?.dispose()
        _controller = nil
        super.dispose()
    }

    override func didUpdateWidget(_ oldWidget: StatefulWidget) {
        super.didUpdateWidget(oldWidget)
        let oldASB = oldWidget as! AutoSuggestBox
        if autoSuggestBox.controller !== oldASB.controller {
            if let listener = _boundListener {
                (oldASB.controller ?? _controller)?.removeListener(listener)
            }
            if autoSuggestBox.controller == nil && _controller == nil {
                _controller = TextEditingController()
            }
            if let listener = _boundListener {
                _effectiveController.addListener(listener)
            }
        }
    }

    // MARK: - Filtering

    private func _onTextChanged() {
        let query = _effectiveController.text
        autoSuggestBox.onChanged?(query)
        _updateFilteredItems(query)
        _updateFlyout()
        setState {}
    }

    private func _updateFilteredItems(_ query: String) {
        if query.isEmpty {
            _filteredItems = []
            return
        }

        let filter = autoSuggestBox.filterFn ?? _defaultFilter
        _filteredItems = autoSuggestBox.items.filter { item in
            filter(query, item)
        }
    }

    private func _defaultFilter(_ query: String, _ item: AutoSuggestBoxItem) -> Bool {
        return item.value.lowercased().containsSubstring(query.lowercased())
    }

    // MARK: - Flyout Management

    private func _updateFlyout() {
        if _filteredItems.isEmpty {
            _flyoutController.closeFlyout()
            return
        }

        if _flyoutController.isOpen {
            // Close and reopen to update content
            _flyoutController.closeFlyout()
        }

        _flyoutController.showFlyout(
            builder: { [self] context in
                _buildSuggestionsList(context)
            },
            barrierDismissible: true,
            barrierColor: nil,
            placement: autoSuggestBox.placement,
            additionalOffset: 4.0
        )
    }

    private func _selectItem(_ item: AutoSuggestBoxItem) {
        item.onTap?()
        autoSuggestBox.onSelected?(item)

        if autoSuggestBox.clearOnSelect {
            _effectiveController.text = ""
        } else {
            // Remove listener temporarily so setting text doesn't re-trigger filtering
            if let listener = _boundListener {
                _effectiveController.removeListener(listener)
            }
            _effectiveController.text = item.value
            if let listener = _boundListener {
                _effectiveController.addListener(listener)
            }
        }

        _flyoutController.closeFlyout()
        _filteredItems = []
        setState {}
    }

    // MARK: - Build Suggestions

    private func _buildSuggestionsList(_ context: any BuildContext) -> Widget {
        let theme = FluentTheme.of(context)

        let itemWidgets: [Widget] = _filteredItems.map { item in
            Padding(
                padding: EdgeInsets(left: 4, top: 2, right: 4, bottom: 2),
                child: FlyoutListTile(
                    onPressed: { [self] in
                        _selectItem(item)
                    },
                    text: item.child ?? Text(
                        item.value,
                        style: TextStyle(
                            color: theme.resources.textFillColorPrimary,
                            fontSize: 14
                        )
                    ),
                    margin: EdgeInsets(),
                    selected: false,
                    showSelectedIndicator: false
                )
            )
        }

        let column: Widget = Column(
            mainAxisSize: .min,
            crossAxisAlignment: .stretch,
            children: itemWidgets
        )

        let constrained: Widget = ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: autoSuggestBox.maxSuggestionsHeight
            ),
            child: column
        )

        return FlyoutContent(
            child: constrained,
            padding: EdgeInsets(top: 2, bottom: 2),
            elevation: 8.0
        )
    }

    // MARK: - Build

    override func build(_ context: any BuildContext) -> Widget {
        let textBox: Widget = FluentTextBox(
            controller: _effectiveController,
            placeholderText: autoSuggestBox.placeholderText,
            enabled: autoSuggestBox.enabled,
            style: autoSuggestBox.style,
            decoration: autoSuggestBox.decoration,
            prefix: autoSuggestBox.leadingIcon,
            suffix: autoSuggestBox.trailingIcon
        )

        return FlyoutTarget(
            controller: _flyoutController,
            child: textBox
        )
    }
}
