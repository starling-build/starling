import FlutterSwiftBridge
// What a `Semantics` widget says about its subtree: the plain-value subset of
// SemanticsProperties the first slice needs (label, hint, value, role flags, tap).

public struct SemanticsInfo {
    public var label: String?
    public var hint: String?
    public var value: String?
    public var isButton: Bool
    public var isTextField: Bool
    public var isHeader: Bool
    public var isLink: Bool
    /// What kind of control this is beyond the flags (a tab, a tab bar...).
    public var role: SemanticsRole?
    public var isChecked: Bool?
    public var isToggled: Bool?
    public var isSelected: Bool?
    public var isEnabled: Bool?
    public var isFocused: Bool?
    public var textSelection: TextSelection?
    public var onTap: VoidCallback?
    public var onSetSelection: SetSelectionHandler?
    public var onReplaceRange: ((Int, Int, String) -> Void)?

    public init(label: String? = nil, hint: String? = nil, value: String? = nil,
                isButton: Bool = false, isTextField: Bool = false, isHeader: Bool = false,
                isLink: Bool = false, role: SemanticsRole? = nil, isChecked: Bool? = nil, isToggled: Bool? = nil,
                isSelected: Bool? = nil, isEnabled: Bool? = nil, isFocused: Bool? = nil, textSelection: TextSelection? = nil, onTap: VoidCallback? = nil,
                onSetSelection: SetSelectionHandler? = nil, onReplaceRange: ((Int, Int, String) -> Void)? = nil) {
        self.label = label; self.hint = hint; self.value = value
        self.isButton = isButton; self.isTextField = isTextField; self.isHeader = isHeader
        self.isLink = isLink; self.role = role; self.isChecked = isChecked; self.isToggled = isToggled
        self.isSelected = isSelected; self.isEnabled = isEnabled; self.isFocused = isFocused; self.textSelection = textSelection; self.onTap = onTap
        self.onSetSelection = onSetSelection; self.onReplaceRange = onReplaceRange
    }

    func apply(to config: SemanticsConfiguration) {
        if let label { config.label = label }
        if let hint { config.hint = hint }
        if let value { config.value = value }
        if isButton { config.isButton = true }
        if isTextField { config.isTextField = true }
        if isHeader { config.isHeader = true }
        if isLink { config.isLink = true }
        if let role { config.role = role }
        if let isChecked { config.isChecked = isChecked }
        if let isToggled { config.isToggled = isToggled }
        if let isSelected { config.isSelected = isSelected }
        if let isEnabled { config.isEnabled = isEnabled }
        if let isFocused { config.isFocused = isFocused }
        if let textSelection { config.textSelection = textSelection }
        if let onTap { config.onTap = onTap }
        if let onSetSelection { config.onSetSelection = onSetSelection }
        if let onReplaceRange { config.onReplaceRange = onReplaceRange }
    }
}
