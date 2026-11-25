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
    private nonisolated(unsafe) static var started = false
    /// The last snapshot's nodes, so a press by index runs the handler it described. Main thread only.
    private nonisolated(unsafe) static var last: [SemanticsSnapshotNode] = []

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
        let rc = atspi_bridge_start(&host, appName)
        if rc == 0 { started = true }
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
            if n.isTextField { st |= 1 << UInt64(ATSPI_BRIDGE_STATE_EDITABLE)
                                   | 1 << UInt64(ATSPI_BRIDGE_STATE_FOCUSABLE) }
            node.states = st
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
