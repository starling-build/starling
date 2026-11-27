import FlutterSwiftBridge
// Semantics, MergeSemantics, ExcludeSemantics: what a screen reader (or a test) is told about a subtree.

/// Annotates its subtree: a name (`label`), a `hint`, a `value`, a role, a state and a tap action.
public class Semantics: SingleChildRenderObjectWidget {
    public let info: SemanticsInfo
    public let container: Bool
    public let excludeSemantics: Bool

    public init(
        key: (any Key)? = nil,
        label: String? = nil, hint: String? = nil, value: String? = nil,
        button: Bool = false, textField: Bool = false, header: Bool = false, link: Bool = false, role: SemanticsRole? = nil,
        checked: Bool? = nil, toggled: Bool? = nil, selected: Bool? = nil, enabled: Bool? = nil, focused: Bool? = nil, textSelection: TextSelection? = nil,
        onTap: VoidCallback? = nil,
        onSetSelection: SetSelectionHandler? = nil, onReplaceRange: ((Int, Int, String) -> Void)? = nil,
        container: Bool = false, excludeSemantics: Bool = false,
        child: Widget? = nil
    ) {
        self.info = SemanticsInfo(label: label, hint: hint, value: value, isButton: button,
                                  isTextField: textField, isHeader: header, isLink: link, role: role,
                                  isChecked: checked, isToggled: toggled, isSelected: selected,
                                  isEnabled: enabled, isFocused: focused, textSelection: textSelection, onTap: onTap,
                                  onSetSelection: onSetSelection, onReplaceRange: onReplaceRange)
        self.container = container
        self.excludeSemantics = excludeSemantics
        super.init(key: key, child: child)
    }

    public override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        RenderSemanticsAnnotations(container: container, excludeSemantics: excludeSemantics, info: info)
    }

    public override func updateRenderObject(_ context: any BuildContext, renderObject: RenderObject) {
        let ro = renderObject as! RenderSemanticsAnnotations
        ro.info = info
        ro.container = container
        ro.excludeSemantics = excludeSemantics
    }
}

/// Merges the semantics of everything below it into one node (a button and its label read as one).
public class MergeSemantics: SingleChildRenderObjectWidget {
    public override init(key: (any Key)? = nil, child: Widget? = nil) {
        super.init(key: key, child: child)
    }
    public override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        RenderMergeSemantics()
    }
}

/// Hides everything below it from assistive technology (decoration that would only be noise).
public class ExcludeSemantics: SingleChildRenderObjectWidget {
    public let excluding: Bool
    public init(key: (any Key)? = nil, excluding: Bool = true, child: Widget? = nil) {
        self.excluding = excluding
        super.init(key: key, child: child)
    }
    public override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        RenderExcludeSemantics(excluding: excluding)
    }
    public override func updateRenderObject(_ context: any BuildContext, renderObject: RenderObject) {
        (renderObject as! RenderExcludeSemantics).excluding = excluding
    }
}

extension Semantics {
    public convenience init(
        key: (any Key)? = nil,
        label: String? = nil, hint: String? = nil, value: String? = nil,
        button: Bool = false, textField: Bool = false, header: Bool = false, link: Bool = false, role: SemanticsRole? = nil,
        checked: Bool? = nil, toggled: Bool? = nil, selected: Bool? = nil, enabled: Bool? = nil, focused: Bool? = nil, textSelection: TextSelection? = nil,
        onTap: VoidCallback? = nil,
        onSetSelection: SetSelectionHandler? = nil, onReplaceRange: ((Int, Int, String) -> Void)? = nil,
        container: Bool = false, excludeSemantics: Bool = false,
        @ChildBuilder child: () -> Widget
    ) {
        self.init(key: key, label: label, hint: hint, value: value, button: button, textField: textField,
                  header: header, link: link, role: role, checked: checked, toggled: toggled, selected: selected,
                  enabled: enabled, focused: focused, textSelection: textSelection, onTap: onTap, onSetSelection: onSetSelection, onReplaceRange: onReplaceRange, container: container, excludeSemantics: excludeSemantics,
                  child: child())
    }
}

extension MergeSemantics {
    public convenience init(key: (any Key)? = nil, @ChildBuilder child: () -> Widget) {
        self.init(key: key, child: child())
    }
}

extension ExcludeSemantics {
    public convenience init(key: (any Key)? = nil, excluding: Bool = true, @ChildBuilder child: () -> Widget) {
        self.init(key: key, excluding: excluding, child: child())
    }
}
