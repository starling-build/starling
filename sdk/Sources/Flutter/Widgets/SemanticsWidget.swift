// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// `Semantics`: lets a widget say what it is to an agent (or any screen reader)
// — a button, a checkbox that is on, a text field holding "abc" — and what can
// be done to it. Read by `AgentSemanticsEndpoint`'s tree walk.
//
// This is not Dart's `Semantics(properties:)`: the framework's semantics
// pipeline is not wired up, so the widget takes the handful of fields the
// agent surface uses, flat. If the real pipeline is wired later, the fields map
// onto `SemanticsProperties` one for one.

public class Semantics: SingleChildRenderObjectWidget {
    public var label: String?
    public var value: String?
    public var hint: String?
    public var identifier: String?
    /// What kind of thing this is: "button", "checkbox", "radio", "switch",
    /// "textfield", "slider", "link", "header", "tab", "menuitem", "image".
    public var role: String?
    public var enabled: Bool?
    public var checked: Bool?
    public var toggled: Bool?
    public var selected: Bool
    public var focused: Bool?
    public var readOnly: Bool
    public var obscured: Bool
    public var multiline: Bool
    public var container: Bool

    public var onTap: (() -> Void)?
    public var onLongPress: (() -> Void)?
    public var onIncrease: (() -> Void)?
    public var onDecrease: (() -> Void)?
    public var onSetText: ((String) -> Void)?
    public var onFocus: (() -> Void)?
    public var onScrollUp: (() -> Void)?
    public var onScrollDown: (() -> Void)?

    public init(
        key: (any Key)? = nil,
        label: String? = nil, value: String? = nil, hint: String? = nil,
        identifier: String? = nil, role: String? = nil,
        enabled: Bool? = nil, checked: Bool? = nil, toggled: Bool? = nil,
        selected: Bool = false, focused: Bool? = nil, readOnly: Bool = false,
        obscured: Bool = false, multiline: Bool = false, container: Bool = false,
        onTap: (() -> Void)? = nil, onLongPress: (() -> Void)? = nil,
        onIncrease: (() -> Void)? = nil, onDecrease: (() -> Void)? = nil,
        onSetText: ((String) -> Void)? = nil, onFocus: (() -> Void)? = nil,
        onScrollUp: (() -> Void)? = nil, onScrollDown: (() -> Void)? = nil,
        child: Widget? = nil
    ) {
        self.label = label; self.value = value; self.hint = hint
        self.identifier = identifier; self.role = role
        self.enabled = enabled; self.checked = checked; self.toggled = toggled
        self.selected = selected; self.focused = focused; self.readOnly = readOnly
        self.obscured = obscured; self.multiline = multiline; self.container = container
        self.onTap = onTap; self.onLongPress = onLongPress
        self.onIncrease = onIncrease; self.onDecrease = onDecrease
        self.onSetText = onSetText; self.onFocus = onFocus
        self.onScrollUp = onScrollUp; self.onScrollDown = onScrollDown
        super.init(key: key, child: child)
    }

    func apply(to ro: RenderSemanticsAnnotations) {
        ro.container = container
        ro.configure = { [self] c in
            if let label, !label.isEmpty { c.label = label }
            if let value { c.value = value }
            if let hint, !hint.isEmpty { c.hint = hint }
            if let identifier, !identifier.isEmpty { c.identifier = identifier }
            if let enabled { c.isEnabled = enabled }
            if let checked { c.isChecked = checked }
            if let toggled { c.isToggled = toggled }
            if selected { c.isSelected = true }
            if let focused { c.isFocused = focused }
            if readOnly { c.isReadOnly = true }
            if obscured { c.isObscured = true }
            if multiline { c.isMultiline = true }
            switch role {
            case "button", "tab", "menuitem": c.isButton = true
            case "textfield": c.isTextField = true
            case "slider": c.isSlider = true
            case "link": c.isLink = true
            case "header": c.isHeader = true
            case "image": c.isImage = true
            default: break
            }
            // A disabled control offers no actions, as for a human.
            if enabled != false {
                if let onTap { c.onTap = onTap }
                if let onLongPress { c.onLongPress = onLongPress }
                if let onIncrease { c.onIncrease = onIncrease }
                if let onDecrease { c.onDecrease = onDecrease }
                if let onSetText { c.onSetText = onSetText }
                if let onFocus { c.onFocus = onFocus }
                if let onScrollUp { c.onScrollUp = onScrollUp }
                if let onScrollDown { c.onScrollDown = onScrollDown }
            }
            c.agentRole = role ?? ""
        }
        ro.markNeedsSemanticsUpdate()
    }

    public override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        let ro = RenderSemanticsAnnotations(container: container)
        apply(to: ro)
        return ro
    }

    public override func updateRenderObject(_ context: any BuildContext, renderObject: RenderObject) {
        apply(to: renderObject as! RenderSemanticsAnnotations)
    }
}
