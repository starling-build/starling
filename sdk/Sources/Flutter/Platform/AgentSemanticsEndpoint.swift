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
              let op = req["op"] as? String else {
            Self.reply(fd, ["ok": false, "error": "bad request"])
            return
        }
        let id = req["id"] ?? NSNull()
        // The walk touches the live element/render tree — main thread only.
        let work: () -> Void = { [weak self] in
            guard let self else { return }
            switch op {
            case "semantic_tree":
                let (nodes, actionMap) = Self.snapshot()
                self.handlers = actionMap
                Self.reply(fd, ["id": id, "ok": true, "nodes": nodes])
            case "perform_action":
                guard let node = req["node"] as? Int,
                      let action = req["action"] as? String,
                      let handler = self.handlers[node]?[action] else {
                    Self.reply(fd, ["id": id, "ok": false,
                                    "error": "no such node/action (snapshot stale? re-query)"])
                    return
                }
                handler(nil)
                Self.reply(fd, ["id": id, "ok": true])
            default:
                Self.reply(fd, ["id": id, "ok": false, "error": "unknown op \(op)"])
            }
        }
        DispatchQueue.main.async(
            execute: unsafeBitCast(work, to: (@Sendable () -> Void).self))
    }

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
    /// annotates a SemanticsConfiguration. Actionable nodes with no label
    /// of their own borrow their subtree's text (mergeSemantics-lite) so
    /// "find the button labeled X" works without explicit Semantics widgets.
    private static func snapshot() -> ([[String: Any]], [Int: [String: SemanticsActionHandler]]) {
        guard let root = rootElementProvider?() else { return ([], [:]) }
        var nodes: [[String: Any]] = []
        var actionMap: [Int: [String: SemanticsActionHandler]] = [:]
        var nextId = 1

        let describable: [(String, SemanticsAction)] = [
            ("tap", .tap),
            ("longPress", .longPress),
            ("increase", .increase),
            ("decrease", .decrease),
        ]

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

        func walk(_ e: Element) {
            if let roe = e as? RenderObjectElement, let ro = roe.renderObject {
                let cfg = SemanticsConfiguration()
                ro.describeSemanticsConfiguration(cfg)
                if cfg.hasBeenAnnotated {
                    var label = cfg.label
                    var actions: [String] = []
                    var nodeHandlers: [String: SemanticsActionHandler] = [:]
                    for (name, action) in describable {
                        if let h = cfg.getActionHandler(action) {
                            actions.append(name)
                            nodeHandlers[name] = h
                        }
                    }
                    if label.isEmpty && !actions.isEmpty {
                        label = subtreeLabel(e)
                    }
                    if !label.isEmpty || !actions.isEmpty {
                        let rect = MatrixUtils.transformRect(
                            ro.getTransformTo(nil), ro.paintBounds)
                        let id = nextId
                        nextId += 1
                        var node: [String: Any] = [
                            "node": id,
                            "label": label,
                            "actions": actions,
                            "rect": [rect.left, rect.top, rect.width, rect.height],
                        ]
                        if !cfg.value.isEmpty { node["value"] = cfg.value }
                        nodes.append(node)
                        actionMap[id] = nodeHandlers
                    }
                }
            }
            e.visitChildElements { walk($0) }
        }
        walk(root)
        return (nodes, actionMap)
    }
}
#endif
