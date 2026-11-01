#if os(Linux)
import FlutterSwiftBridge
import Foundation
import Glibc

// MARK: - Agent Semantics Endpoint (Murmuration P3 v0)
//
// The semantic layer for first-party child apps: a JSON-lines socket
// (path from $STARLING_AGENT_ENDPOINT, opened by the shell's agent launch
// path) that the shell's agent broker proxies `semantic_tree` and
// `perform_action` to. Agents address the UI by node label and id — no
// coordinates, no pixels.
//
// This is a SNAPSHOT walker, not Flutter's incremental semantics compiler
// (which is not ported): each `semantic_tree` request walks the element
// tree on the main thread, collecting nodes whose render objects annotate
// a fresh SemanticsConfiguration — text labels (RenderParagraph), tap /
// long-press actions (RenderSemanticsGestureHandler), explicit Semantics
// widgets. Action handlers are retained per snapshot so `perform_action`
// invokes the exact closure the widget registered, taking the same code
// path as a human gesture. Node ids are valid until the next snapshot —
// agents re-query after acting.

public final class AgentSemanticsEndpoint: @unchecked Sendable {

    /// Set by _setupWidgetBinding once the root element exists.
    public nonisolated(unsafe) static var rootElementProvider: (() -> Element?)? = nil

    private nonisolated(unsafe) static var shared: AgentSemanticsEndpoint? = nil

    private let path: String
    private var listenFd: Int32 = -1
    /// Last snapshot's action handlers, keyed by node id. Main thread only.
    private var handlers: [Int: [String: SemanticsActionHandler]] = [:]

    private init(path: String) {
        self.path = path
    }

    /// Start the endpoint when the launcher configured one ($STARLING_AGENT_ENDPOINT).
    public static func startIfConfigured() {
        guard shared == nil,
              let path = ProcessInfo.processInfo.environment["STARLING_AGENT_ENDPOINT"],
              !path.isEmpty else { return }
        let ep = AgentSemanticsEndpoint(path: path)
        if ep.start() { shared = ep }
    }

    private func start() -> Bool {
        unlink(path)
        let fd = socket(AF_UNIX,
                        Int32(SOCK_STREAM.rawValue) | Int32(SOCK_CLOEXEC.rawValue), 0)
        guard fd >= 0 else { return false }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path) { pathPtr in
            pathPtr.withMemoryRebound(to: CChar.self, capacity: 108) { buf in
                path.withCString { src in strncpy(buf, src, 107) }
            }
        }
        let bound = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                bind(fd, sa, UInt32(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(fd, 4) == 0 else {
            close(fd)
            return false
        }
        // `perform_action` invokes the widget's real handler — the same code
        // path as a human gesture — so this socket must not be world
        // reachable. The broker gates its proxied calls on window ownership;
        // a mode of 0666 here let anything on the box skip that entirely by
        // connecting straight to the enumerable path.
        chmod(path, 0o600)
        listenFd = fd
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            while let self, self.listenFd >= 0 {
                let client = accept(self.listenFd, nil, nil)
                guard client >= 0 else { break }
                guard Self.peerIsSameUser(client) else { close(client); continue }
                self.serve(client)
            }
        }
        return true
    }

    /// Only this app's own user (or root) may drive the widget tree. The uid
    /// comes from the kernel, so a client cannot claim someone else's.
    private static func peerIsSameUser(_ fd: Int32) -> Bool {
        var cred = ucred()
        var len = socklen_t(MemoryLayout<ucred>.size)
        guard getsockopt(fd, SOL_SOCKET, SO_PEERCRED, &cred, &len) == 0 else {
            return false          // cannot prove the peer — fail closed
        }
        return cred.uid == getuid() || cred.uid == 0
    }

    private func serve(_ fd: Int32) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var pending = Data()
            var buf = [UInt8](repeating: 0, count: 65536)
            while true {
                let n = read(fd, &buf, buf.count)
                if n <= 0 { break }
                pending.append(contentsOf: buf[0..<n])
                while let nl = pending.firstIndex(of: 0x0A) {
                    let line = Data(pending[pending.startIndex..<nl])
                    pending = Data(pending[pending.index(after: nl)...])
                    if !line.isEmpty { self?.handle(line, fd) }
                }
            }
            close(fd)
        }
    }

    private func handle(_ line: Data, _ fd: Int32) {
        guard let req = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              req["op"] is String else {
            Self.reply(fd, ["ok": false, "error": "bad request"])
            return
        }
        // The walk touches the live element/render tree — main thread only.
        let work: () -> Void = { [weak self] in
            guard let self else { return }
            Self.reply(fd, self.perform(req))
        }
        DispatchQueue.main.async(
            execute: unsafeBitCast(work, to: (@Sendable () -> Void).self))
    }

    /// Answer one request. MAIN THREAD ONLY. The socket calls this; the shell
    /// calls it directly (no socket) for its own surfaces.
    ///
    /// Ops: `tree`, `find`, `act` — plus the original `semantic_tree` and
    /// `perform_action`, kept so `test/functional.py` and the broker still work.
    public func perform(_ req: [String: Any]) -> [String: Any] {
        let id = req["id"] ?? NSNull()
        switch req["op"] as? String ?? "" {
        case "tree", "semantic_tree":
            let (nodes, map) = Self.snapshot()
            handlers = map
            return ["id": id, "ok": true, "nodes": nodes]
        case "find":
            let (nodes, map) = Self.snapshot()
            handlers = map
            let role = req["role"] as? String
            let label = req["label"] as? String
            let contains = (req["labelContains"] as? String)?.lowercased()
            let hits = nodes.filter { n in
                if let role, n["role"] as? String != role { return false }
                if let label, n["label"] as? String != label { return false }
                if let contains,
                   !((n["label"] as? String) ?? "").lowercased().contains(contains) {
                    return false
                }
                return true
            }
            return ["id": id, "ok": true, "nodes": hits]
        case "act", "perform_action":
            guard let node = req["node"] as? Int,
                  let action = req["action"] as? String else {
                return ["id": id, "ok": false, "error": "act needs node and action"]
            }
            guard let table = handlers[node] else {
                return ["id": id, "ok": false, "error": "stale node (re-query)"]
            }
            guard let handler = table[action] else {
                return ["id": id, "ok": false,
                        "error": "node has no action \(action); it offers \(table.keys.sorted())"]
            }
            if action == "setText" {
                guard let text = req["arg"] as? String else {
                    return ["id": id, "ok": false, "error": "setText needs a string arg"]
                }
                handler(text)
            } else {
                handler(nil)
            }
            return ["id": id, "ok": true]
        default:
            return ["id": id, "ok": false, "error": "unknown op"]
        }
    }

    /// The in-process endpoint for the shell's own surfaces.
    public static let local = AgentSemanticsEndpoint(path: "")

    private static func reply(_ fd: Int32, _ obj: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(obj),
              let json = try? JSONSerialization.data(withJSONObject: obj) else { return }
        let data = json + Data([0x0A])
        data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
            var off = 0
            while off < buf.count {
                let n = write(fd, buf.baseAddress! + off, buf.count - off)
                if n <= 0 { break }
                off += n
            }
        }
    }

    // MARK: Snapshot walk (main thread)

    /// Walk the element tree, emitting a node for every render object that
    /// says something: a label, or at least one action. A control is usually
    /// several annotated render objects stacked on one rectangle (a `Semantics`
    /// around a `GestureDetector` around the label's text); those fold into one
    /// node so an agent sees one button, not three.
    private static func snapshot() -> ([[String: Any]], [Int: [String: SemanticsActionHandler]]) {
        guard let root = rootElementProvider?() else { return ([], [:]) }

        struct Item {
            var rect: [Double]
            var role = ""
            var label = ""
            var value: String?
            var hint = ""
            var identifier = ""
            var enabled = true
            var focused: Bool?
            var selected = false
            var checked: Bool?
            var handlers: [String: SemanticsActionHandler] = [:]
            var actionOrder: [String] = []
        }
        var items: [Item] = []

        let describable: [(String, SemanticsAction)] = [
            ("tap", .tap), ("longPress", .longPress),
            ("increase", .increase), ("decrease", .decrease),
            ("setText", .setText), ("focus", .focus),
            ("scrollUp", .scrollUp), ("scrollDown", .scrollDown),
        ]

        func roleOf(_ c: SemanticsConfiguration, hasTap: Bool) -> String {
            if !c.agentRole.isEmpty { return c.agentRole }
            if c.isTextField { return "textfield" }
            if c.isSlider { return "slider" }
            if c.isLink { return "link" }
            if c.isButton { return "button" }
            if c.isHeader { return "heading" }
            if c.isImage { return "image" }
            if c.isChecked != nil { return "checkbox" }
            if c.isToggled != nil { return "switch" }
            return hasTap ? "clickable" : ""
        }

        func subtreeLabel(_ element: Element) -> String {
            var parts: [String] = []
            func rec(_ e: Element, _ depth: Int) {
                guard depth < 10, parts.joined(separator: " ").count < 120 else { return }
                if let roe = e as? RenderObjectElement, let ro = roe.renderObject {
                    let cfg = SemanticsConfiguration()
                    ro.describeSemanticsConfiguration(cfg)
                    if !cfg.label.isEmpty { parts.append(cfg.label) }
                }
                e.visitChildElements { rec($0, depth + 1) }
            }
            rec(element, 0)
            return parts.joined(separator: " ")
        }

        // `stack` holds indexes into `items` of the emitting ancestors.
        func walk(_ e: Element, _ stack: [Int]) {
            var stack = stack
            if let roe = e as? RenderObjectElement, let ro = roe.renderObject {
                let cfg = SemanticsConfiguration()
                ro.describeSemanticsConfiguration(cfg)
                if cfg.hasBeenAnnotated {
                    var item = Item(rect: [])
                    for (name, action) in describable {
                        if let h = cfg.getActionHandler(action) {
                            item.handlers[name] = h
                            item.actionOrder.append(name)
                        }
                    }
                    item.label = cfg.label
                    if item.label.isEmpty && !item.handlers.isEmpty
                        && cfg.agentRole.isEmpty && !cfg.isTextField {
                        item.label = subtreeLabel(e)
                    }
                    if !item.label.isEmpty || !item.handlers.isEmpty || !cfg.agentRole.isEmpty {
                        let r = MatrixUtils.transformRect(ro.getTransformTo(nil), ro.paintBounds)
                        item.rect = [r.left, r.top, r.width, r.height]
                        item.role = roleOf(cfg, hasTap: item.handlers["tap"] != nil)
                        if !cfg.value.isEmpty { item.value = cfg.value }
                        item.hint = cfg.hint
                        item.identifier = cfg.identifier
                        item.enabled = cfg.isEnabled ?? true
                        item.focused = cfg.isFocused
                        item.selected = cfg.isSelected
                        item.checked = cfg.isChecked ?? cfg.isToggled
                        // Fold into the nearest emitting ancestor on the same rectangle.
                        if let up = stack.last, items[up].rect == item.rect {
                            var host = items[up]
                            if host.label.isEmpty { host.label = item.label }
                            if host.role.isEmpty || host.role == "clickable" { host.role = item.role.isEmpty ? host.role : item.role }
                            if host.value == nil { host.value = item.value }
                            if host.hint.isEmpty { host.hint = item.hint }
                            if host.identifier.isEmpty { host.identifier = item.identifier }
                            if !item.enabled { host.enabled = false }
                            if host.focused == nil { host.focused = item.focused }
                            host.selected = host.selected || item.selected
                            if host.checked == nil { host.checked = item.checked }
                            for n in item.actionOrder where host.handlers[n] == nil {
                                host.handlers[n] = item.handlers[n]
                                host.actionOrder.append(n)
                            }
                            items[up] = host
                        } else {
                            items.append(item)
                            stack.append(items.count - 1)
                        }
                    }
                }
            }
            let snapshotStack = stack
            e.visitChildElements { walk($0, snapshotStack) }
        }
        walk(root, [])

        var nodes: [[String: Any]] = []
        var actionMap: [Int: [String: SemanticsActionHandler]] = [:]
        for (i, it) in items.enumerated() {
            let id = i + 1
            // A bare label (no role, no actions) is a piece of text.
            let role = it.role.isEmpty ? "text" : it.role
            var node: [String: Any] = [
                "node": id, "role": role, "label": it.label,
                "rect": it.rect, "enabled": it.enabled,
                "selected": it.selected, "actions": it.actionOrder,
            ]
            if let v = it.value { node["value"] = v }
            if !it.hint.isEmpty { node["hint"] = it.hint }
            if !it.identifier.isEmpty { node["id"] = it.identifier }
            if let f = it.focused { node["focused"] = f }
            if let c = it.checked { node["checked"] = c }
            nodes.append(node)
            actionMap[id] = it.handlers
        }
        return (nodes, actionMap)
    }
}
#endif
