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
    public var isChecked: Bool?
    public var isToggled: Bool?
    public var isSelected: Bool?
    public var isEnabled: Bool?
    public var canTap: Bool
    public var tap: VoidCallback?
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
                if cfg.hasBeenAnnotated { out.append(node(cfg, mergedLabel: nil)) }
                return
            }
            if cfg.isMergingSemanticsOfDescendants {
                var parts: [String] = []
                var tap: VoidCallback? = cfg.onTap
                var merged = cfg
                collect(e, &parts, &tap, &merged, isRoot: true)
                out.append(node(merged, mergedLabel: parts.joined(separator: " "), tap: tap))
                return
            }
            if cfg.hasBeenAnnotated, !(cfg.label.isEmpty && cfg.onTap == nil && cfg.value.isEmpty && !cfg.isTextField && !cfg.isButton) {
                out.append(node(cfg, mergedLabel: nil))
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
                if merged.value.isEmpty, !cfg.value.isEmpty { merged.value = cfg.value }
            } else if !cfg.label.isEmpty { parts.append(cfg.label) }
            if let a = ro as? RenderSemanticsAnnotations, a.excludeSemantics { return }
        }
        e.visitChildElements { collect($0, &parts, &tap, &merged, isRoot: false) }
    }

    private static func node(_ c: SemanticsConfiguration, mergedLabel: String?, tap: VoidCallback? = nil) -> SemanticsSnapshotNode {
        let t = tap ?? c.onTap
        var label = c.label
        if let m = mergedLabel, !m.isEmpty { label = label.isEmpty ? m : label }
        return SemanticsSnapshotNode(
            label: label, hint: c.hint, value: c.value, isButton: c.isButton, isTextField: c.isTextField,
            isHeader: c.isHeader, isChecked: c.isChecked, isToggled: c.isToggled, isSelected: c.isSelected,
            isEnabled: c.isEnabled, canTap: t != nil, tap: t)
    }
}
