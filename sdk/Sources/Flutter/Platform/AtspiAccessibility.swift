#if os(Linux)
import AtspiBridge
import Foundation
import Glibc

/// Makes the app visible to screen readers on Linux (AT-SPI over the accessibility bus).
///
/// It publishes the same semantics snapshot the agent endpoint uses: every node with a label becomes
/// an accessible object under one application root. A client's "press" runs the widget's own tap
/// handler on the main thread. Off unless `STARLING_ATSPI=1` (or `start` is called), because it
/// opens a connection to the accessibility bus.
public final class AtspiAccessibility: @unchecked Sendable {
    public nonisolated(unsafe) static var rootElementProvider: (() -> Element?)? = nil
    /// The window's top-left on the screen, when the app knows it (a Wayland client does not; the shell can say).
    public nonisolated(unsafe) static var windowOrigin: (() -> (x: Int, y: Int)?)? = nil
    private nonisolated(unsafe) static var started = false
    /// The last snapshot's nodes, so a press by index runs the handler it described. Main thread only.
    private nonisolated(unsafe) static var last: [SemanticsSnapshotNode] = []

    /// The shell writes each window's position to `$XDG_RUNTIME_DIR/starling-window-origin/<pid>` ("x y").
    static func originFromShell() -> (x: Int, y: Int)? {
        guard let dir = ProcessInfo.processInfo.environment["XDG_RUNTIME_DIR"],
              let text = try? String(contentsOfFile: dir + "/starling-window-origin/\(getpid())", encoding: .utf8)
        else { return nil }
        let parts = text.split(whereSeparator: { $0 == " " || $0 == "\n" }).compactMap { Int($0) }
        return parts.count == 2 ? (parts[0], parts[1]) : nil
    }

    public static func startIfConfigured() {
        guard ProcessInfo.processInfo.environment["STARLING_ATSPI"] == "1" else { return }
        _ = start(appName: "starling")
    }

    /// Returns 0 on success, a negative code when the bus or sd-bus is missing.
    @discardableResult
    public static func start(appName: String, provider: (() -> Element?)? = nil) -> Int32 {
        if let provider { rootElementProvider = provider }
        if started { return 0 }
        var host = atspi_bridge_host()
        host.ctx = nil
        host.snapshot = { _, out in AtspiAccessibility.snapshotForBridge(out) }
        host.press = { _, index in AtspiAccessibility.pressForBridge(Int(index)) }
        host.edit = { _, index, op, a, b, s in
            AtspiAccessibility.editForBridge(Int(index), op, a, b, s.map { String(cString: $0) })
        }
        host.origin = { _, x, y in
            guard let o = AtspiAccessibility.windowOrigin?() ?? AtspiAccessibility.originFromShell() else { return 0 }
            x?.pointee = Int32(o.x); y?.pointee = Int32(o.y)
            return 1
        }
        let rc = atspi_bridge_start(&host, appName)
        if rc == 0 {
            started = true
            ScreenReader.sink = { text, priority in _ = atspi_bridge_announce(text, priority == .assertive ? 1 : 0) }
        }
        return rc
    }

    public static func busName() -> String? {
        atspi_bridge_bus_name().map { String(cString: $0) }
    }

    private static func onMain<T>(_ body: () -> T) -> T {
        Thread.isMainThread ? body() : DispatchQueue.main.sync(execute: body)
    }

    private static func snapshotForBridge(_ out: UnsafeMutablePointer<UnsafeMutablePointer<atspi_bridge_node>?>?) -> Int32 {
        let nodes: [SemanticsSnapshotNode] = onMain {
            guard let root = rootElementProvider?() else { last = []; return [] }
            last = SemanticsSnapshot.build(from: root).filter { !$0.label.isEmpty || $0.isTextField }
            return last
        }
        guard let out, !nodes.isEmpty,
              let buf = malloc(nodes.count * MemoryLayout<atspi_bridge_node>.stride)?
                .bindMemory(to: atspi_bridge_node.self, capacity: nodes.count) else {
            out?.pointee = nil
            return 0
        }
        for (i, n) in nodes.enumerated() {
            var node = atspi_bridge_node()
            node.name = UnsafePointer(strdup(n.label))
            node.description = n.hint.isEmpty ? nil : UnsafePointer(strdup(n.hint))
            node.role = Int32(role(of: n))
            node.can_press = n.canTap ? 1 : 0
            var st: UInt64 = (1 << UInt64(ATSPI_BRIDGE_STATE_VISIBLE))
                | (1 << UInt64(ATSPI_BRIDGE_STATE_SHOWING))
            if n.isEnabled != false {
                st |= 1 << UInt64(ATSPI_BRIDGE_STATE_ENABLED)
                    | 1 << UInt64(ATSPI_BRIDGE_STATE_SENSITIVE)
            }
            if n.isChecked == true { st |= 1 << UInt64(ATSPI_BRIDGE_STATE_CHECKED) }
            if n.isToggled == true { st |= 1 << UInt64(ATSPI_BRIDGE_STATE_PRESSED) }
            if n.isSelected == true { st |= 1 << UInt64(ATSPI_BRIDGE_STATE_SELECTED) }
            if n.isFocused == true { st |= 1 << UInt64(ATSPI_BRIDGE_STATE_FOCUSED) }
            if n.isTextField { st |= 1 << UInt64(ATSPI_BRIDGE_STATE_EDITABLE)
                                   | 1 << UInt64(ATSPI_BRIDGE_STATE_FOCUSABLE) }
            node.states = st
            node.can_edit = n.isTextField && (n.replaceRange != nil || n.setSelection != nil) ? 1 : 0
            node.caret = -1
            if n.isTextField {
                node.text = UnsafePointer(strdup(n.value))
                let units = Array(n.value.utf16)
                func chars(_ u16: Int) -> Int32 {
                    let cut = max(0, min(u16, units.count))
                    return Int32(String(decoding: units[0..<cut], as: UTF16.self).unicodeScalars.count)
                }
                if let sel = n.selection {
                    node.caret = chars(sel.extent)
                    node.sel_start = chars(sel.base); node.sel_end = chars(sel.extent)
                }
            }
            if let f = n.frame {
                node.x = Int32(f.x.rounded()); node.y = Int32(f.y.rounded())
                node.w = Int32(f.width.rounded()); node.h = Int32(f.height.rounded())
            }
            (buf + i).initialize(to: node)
        }
        out.pointee = buf
        return Int32(nodes.count)
    }

    private static func role(of n: SemanticsSnapshotNode) -> Int {
        if n.isTextField { return Int(ATSPI_BRIDGE_ROLE_ENTRY) }
        if n.isHeader { return Int(ATSPI_BRIDGE_ROLE_HEADING) }
        if n.isChecked != nil { return Int(ATSPI_BRIDGE_ROLE_CHECK_BOX) }
        if n.isToggled != nil { return Int(ATSPI_BRIDGE_ROLE_TOGGLE_BUTTON) }
        if n.isButton || n.canTap { return Int(ATSPI_BRIDGE_ROLE_PUSH_BUTTON) }
        return Int(ATSPI_BRIDGE_ROLE_LABEL)
    }

    /// A screen reader typing into, deleting from or moving the caret in a text node. Offsets arrive in
    /// characters; the node's handlers want UTF-16 units of its value.
    private static func editForBridge(_ index: Int, _ op: Int32, _ a: Int32, _ b: Int32, _ text: String?) -> Int32 {
        onMain {
            guard index >= 0, index < last.count, last[index].isTextField else { return 0 }
            let n = last[index]
            let scalars = Array(n.value.unicodeScalars)
            func u16(_ cp: Int32) -> Int {
                scalars[0..<max(0, min(Int(cp), scalars.count))].reduce(0) { $0 + String($1).utf16.count }
            }
            let insert = text ?? ""
            switch op {
            case 1, 2, 5:
                guard let replace = n.replaceRange else { return 0 }
                let (lo, hi) = op == 5 ? (0, n.value.utf16.count) : (u16(min(a, b)), u16(max(a, b)))
                replace(lo, hi, op == 2 ? "" : insert)
                // The caret follows what was typed (or sits where the deletion was).
                let caret = lo + (op == 2 ? 0 : insert.utf16.count)
                n.setSelection?(TextSelection(baseOffset: caret, extentOffset: caret))
                return 1
            case 3:
                guard let set = n.setSelection else { return 0 }
                set(TextSelection(baseOffset: u16(a), extentOffset: u16(a)))
                return 1
            case 4:
                guard let set = n.setSelection else { return 0 }
                set(TextSelection(baseOffset: u16(a), extentOffset: u16(b)))
                return 1
            default:
                return 0
            }
        }
    }

    private static func pressForBridge(_ index: Int) -> Int32 {
        onMain {
            // The bridge indexes the list it last received, which is `last` (filtered the same way).
            guard index >= 0, index < last.count, let tap = last[index].tap else { return 0 }
            tap()
            return 1
        }
    }
}
#endif
