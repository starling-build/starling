import FlutterSwiftBridge
// A flat reading of the semantics of a widget tree, for tests and the agent endpoint:
// one entry per annotated node, in tree order, with Merge and Exclude applied.
// (Flutter's incremental semantics compiler is not ported; this is the snapshot walker.)

public struct SemanticsSnapshotNode {
    public var label: String
    public var hint: String
    public var value: String
    public var isButton: Bool
    public var isTextField: Bool
    public var isHeader: Bool
    /// The node's role when it says one (`.tab` for a tab).
    public var role: SemanticsRole = .none
    public var isChecked: Bool?
    public var isToggled: Bool?
    public var isSelected: Bool?
    public var isEnabled: Bool?
    public var isFocused: Bool?
    /// The selection in UTF-16 units of `value` (caret = extent), when the node is a text field that says.
    public var selection: (base: Int, extent: Int)? = nil
    public var canTap: Bool
    public var tap: VoidCallback?
    /// Where the node is in view coordinates (nil when it has no box).
    public var frame: (x: Double, y: Double, width: Double, height: Double)? = nil
    /// Assistive technology moving the caret (UTF-16 units of `value`), and replacing a UTF-16 range of it.
    public var setSelection: SetSelectionHandler? = nil
    public var replaceRange: ((Int, Int, String) -> Void)? = nil
}

public enum SemanticsSnapshot {
    public static func build(from root: Element) -> [SemanticsSnapshotNode] {
        var out: [SemanticsSnapshotNode] = []
        walk(root, &out)
        return out
    }

    private static func config(of e: Element) -> (RenderObject, SemanticsConfiguration)? {
        guard let roe = e as? RenderObjectElement, let ro = roe.renderObject else { return nil }
        let cfg = SemanticsConfiguration()
        ro.describeSemanticsConfiguration(cfg)
        return (ro, cfg)
    }

    private static func walk(_ e: Element, _ out: inout [SemanticsSnapshotNode]) {
        if let (ro, cfg) = config(of: e) {
            if let x = ro as? RenderExcludeSemantics, x.excluding { return }
            if let a = ro as? RenderSemanticsAnnotations, a.excludeSemantics {
                if cfg.hasBeenAnnotated { out.append(node(cfg, mergedLabel: nil, ro: ro)) }
                return
            }
            if cfg.isMergingSemanticsOfDescendants {
                var parts: [String] = []
                var tap: VoidCallback? = cfg.onTap
                var merged = cfg
                collect(e, &parts, &tap, &merged, isRoot: true)
                out.append(node(merged, mergedLabel: parts.joined(separator: " "), tap: tap, ro: ro))
                return
            }
            if cfg.hasBeenAnnotated, !(cfg.label.isEmpty && cfg.onTap == nil && cfg.value.isEmpty && !cfg.isTextField && !cfg.isButton) {
                out.append(node(cfg, mergedLabel: nil, ro: ro))
            }
        }
        e.visitChildElements { walk($0, &out) }
    }

    /// Gathers the labels and the first tap action below a merge point.
    private static func collect(_ e: Element, _ parts: inout [String], _ tap: inout VoidCallback?,
                                _ merged: inout SemanticsConfiguration, isRoot: Bool) {
        if let (ro, cfg) = config(of: e) {
            if let x = ro as? RenderExcludeSemantics, x.excluding { return }
            if !isRoot {
                if !cfg.label.isEmpty { parts.append(cfg.label) }
                if tap == nil { tap = cfg.onTap }
                if cfg.isButton { merged.isButton = true }
                if cfg.isTextField { merged.isTextField = true }
                if merged.role == .none { merged.role = cfg.role }
                if merged.isFocused == nil { merged.isFocused = cfg.isFocused }
                if merged.isEnabled == nil { merged.isEnabled = cfg.isEnabled }
                if merged.isSelected == nil { merged.isSelected = cfg.isSelected }
                if merged.isChecked == nil { merged.isChecked = cfg.isChecked }
                if merged.isToggled == nil { merged.isToggled = cfg.isToggled }
                if merged.value.isEmpty, !cfg.value.isEmpty { merged.value = cfg.value }
            } else if !cfg.label.isEmpty { parts.append(cfg.label) }
            if let a = ro as? RenderSemanticsAnnotations, a.excludeSemantics { return }
        }
        e.visitChildElements { collect($0, &parts, &tap, &merged, isRoot: false) }
    }

    private static func node(_ c: SemanticsConfiguration, mergedLabel: String?, tap: VoidCallback? = nil, ro: RenderObject? = nil) -> SemanticsSnapshotNode {
        let t = tap ?? c.onTap
        var label = c.label
        if let m = mergedLabel, !m.isEmpty { label = label.isEmpty ? m : label }
        var frame: (x: Double, y: Double, width: Double, height: Double)? = nil
        if let box = ro as? RenderBox, box.hasSize {
            let o = box.localToGlobal(Offset(0, 0))
            frame = (Double(o.dx), Double(o.dy), Double(box.size.width), Double(box.size.height))
        }
        return SemanticsSnapshotNode(
            label: label, hint: c.hint, value: c.value, isButton: c.isButton, isTextField: c.isTextField,
            isHeader: c.isHeader, role: c.role, isChecked: c.isChecked, isToggled: c.isToggled, isSelected: c.isSelected,
            isEnabled: c.isEnabled, isFocused: c.isFocused, selection: c.textSelection.map { (Int($0.baseOffset), Int($0.extentOffset)) },
            canTap: t != nil, tap: t, frame: frame,
            setSelection: c.onSetSelection, replaceRange: c.onReplaceRange)
    }
}
