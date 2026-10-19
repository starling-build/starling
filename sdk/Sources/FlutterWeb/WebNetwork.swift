// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The network in a tab: the browser's fetch and WebSocket, reached through
// the page (web/host/starling.js), answered by callback. Same-origin
// requests carry the session cookie, so an app talking to the server that
// served it needs no credentials of its own. The address bar is here too:
// a route pushed into history, and the user's back/forward reported.

import CSkwasm
import Flutter
import Foundation

public enum WebHTTP {
    public struct Response {
        /// 0 when the request never reached a server (offline, CORS, DNS);
        /// `body` then holds the browser's error text.
        public let status: Int
        public let headers: [String: String]
        public let body: Data
        public var ok: Bool { (200 ..< 300).contains(status) }
    }

    nonisolated(unsafe) private static var pending: [UInt32: (Response) -> Void] = [:]
    nonisolated(unsafe) private static var nextID: UInt32 = 1

    /// Start a request; the completion runs on the main thread when the
    /// browser has the whole response.
    public static func request(_ method: String, _ url: String, headers: [String: String] = [:],
                               body: Data? = nil, _ completion: @escaping (Response) -> Void) {
        let id = nextID
        nextID &+= 1
        if nextID == 0 { nextID = 1 }
        pending[id] = completion
        var method = method
        var url = url
        var headerLines = headers.map { "\($0.key): \($0.value)" }.sorted().joined(separator: "\n")
        let body = body ?? Data()
        method.withUTF8 { m in
            url.withUTF8 { u in
                headerLines.withUTF8 { h in
                    body.withUnsafeBytes { b in
                        starling_host_http_request(id, m.baseAddress, UInt32(m.count), u.baseAddress, UInt32(u.count),
                                                   h.baseAddress, UInt32(h.count), b.baseAddress, UInt32(b.count))
                    }
                }
            }
        }
    }

    static func done(_ id: UInt32, _ response: Response) {
        guard let completion = pending.removeValue(forKey: id) else { return }
        completion(response)
    }
}

/// One WebSocket. Events arrive on the main thread.
public final class WebSocketClient {
    public enum Event {
        case opened
        case text(String)
        case binary(Data)
        case closed(String)
        case failed(String)
    }

    nonisolated(unsafe) private static var open: [UInt32: WebSocketClient] = [:]
    nonisolated(unsafe) private static var nextID: UInt32 = 1

    private let id: UInt32
    private let handler: (Event) -> Void
    public private(set) var isOpen = false

    public init(url: String, _ handler: @escaping (Event) -> Void) {
        id = WebSocketClient.nextID
        WebSocketClient.nextID &+= 1
        if WebSocketClient.nextID == 0 { WebSocketClient.nextID = 1 }
        self.handler = handler
        WebSocketClient.open[id] = self
        var url = url
        url.withUTF8 { starling_host_socket_open(id, $0.baseAddress, UInt32($0.count)) }
    }

    public func send(_ text: String) {
        var text = text
        text.withUTF8 { starling_host_socket_send(id, $0.baseAddress, UInt32($0.count), 1) }
    }

    public func send(_ data: Data) {
        data.withUnsafeBytes { starling_host_socket_send(id, $0.baseAddress, UInt32($0.count), 0) }
    }

    public func close() {
        starling_host_socket_close(id)
        WebSocketClient.open.removeValue(forKey: id)
    }

    static func event(_ id: UInt32, _ kind: Int32, _ payload: Data?) {
        guard let socket = open[id] else { return }
        let text = payload.map { String(decoding: $0, as: UTF8.self) } ?? ""
        switch kind {
        case 0: socket.isOpen = true; socket.handler(.opened)
        case 1: socket.handler(.text(text))
        case 2: socket.handler(.binary(payload ?? Data()))
        case 3: socket.isOpen = false; open.removeValue(forKey: id); socket.handler(.closed(text))
        default: socket.handler(.failed(text))
        }
    }
}

/// The system clipboard through the page (navigator.clipboard): text and
/// HTML out, text in. Installed as `Clipboard.provider` by WebHost.
public final class WebClipboard: ClipboardProvider {
    nonisolated(unsafe) public static let shared = WebClipboard()
    private var pending: [UInt32: (String?) -> Void] = [:]
    private var nextID: UInt32 = 1

    public func setText(_ text: String) { setData(ClipboardData(text: text)) }

    public func setData(_ data: ClipboardData) {
        var text = data.text ?? ""
        var html = data.html ?? ""
        text.withUTF8 { t in
            html.withUTF8 { h in
                starling_host_clipboard_write(t.baseAddress, UInt32(t.count), h.baseAddress, UInt32(h.count))
            }
        }
    }

    public func getText(_ completion: @escaping (String?) -> Void) {
        let id = nextID
        nextID &+= 1
        pending[id] = completion
        starling_host_clipboard_read(id)
    }

    public func getData(_ completion: @escaping (ClipboardData?) -> Void) {
        getText { text in completion(text.map { ClipboardData(text: $0) }) }
    }

    func deliver(_ id: UInt32, _ text: String?) {
        pending.removeValue(forKey: id)?(text)
    }

    /// The tab's own address (what the address bar shows now) onto the
    /// clipboard: a link to the open page, fragment and all.
    public static func copyLocation() { starling_host_copy_location() }
}

@_expose(wasm, "starling_clipboard_text")
@_cdecl("starling_clipboard_text")
func starlingClipboardText(_ id: UInt32, _ bytes: UnsafePointer<UInt8>?, _ count: Int32) {
    var text: String? = nil
    if let bytes, count > 0 {
        text = String(decoding: UnsafeBufferPointer(start: bytes, count: Int(count)), as: UTF8.self)
    }
    WebClipboard.shared.deliver(id, text)
}

/// What the page keeps beside the canvas for screen readers and crawlers.
public enum WebAccessibility {
    /// The open document's text: each line a paragraph, with its heading
    /// level (0 for none, 1-3). Replaces what the shell page carried.
    public static func setDocumentText(_ lines: [(level: Int, text: String)]) {
        var joined = lines.map { "\($0.level)\t\($0.text)" }.joined(separator: "\n")
        joined.withUTF8 { starling_host_set_document_text($0.baseAddress, UInt32($0.count)) }
    }
}

/// The tab's URL, as a route the app owns.
public enum WebHistory {
    /// Called with the new route when the user goes back or forward.
    nonisolated(unsafe) public static var onRouteChanged: ((String) -> Void)?

    public static func push(_ route: String, replace: Bool = false) {
        var route = route
        route.withUTF8 { starling_host_push_route($0.baseAddress, UInt32($0.count), replace ? 1 : 0) }
    }
}

// MARK: - The page's answers

/// Spaces and tabs off both ends (the web Foundation has no CharacterSet).
private func trimmed(_ s: Substring) -> String {
    var a = s.startIndex, b = s.endIndex
    while a < b, s[a] == " " || s[a] == "\t" { a = s.index(after: a) }
    while b > a, s[s.index(before: b)] == " " || s[s.index(before: b)] == "\t" { b = s.index(before: b) }
    return String(s[a ..< b])
}

private func takeBytes(_ pointer: UnsafeMutableRawPointer?, _ count: Int32) -> Data? {
    defer { pointer?.deallocate() }
    guard let pointer, count > 0 else { return nil }
    return Data(bytes: pointer, count: Int(count))
}

@_expose(wasm, "starling_http_done")
@_cdecl("starling_http_done")
func starlingHTTPDone(_ id: UInt32, _ status: Int32,
                      _ headers: UnsafeMutableRawPointer?, _ headersCount: Int32,
                      _ body: UnsafeMutableRawPointer?, _ bodyCount: Int32) {
    let headerText = takeBytes(headers, headersCount).map { String(decoding: $0, as: UTF8.self) } ?? ""
    var parsed: [String: String] = [:]
    for line in headerText.split(separator: "\n") {
        guard let colon = line.firstIndex(of: ":") else { continue }
        parsed[trimmed(line[..<colon]).lowercased()] = trimmed(line[line.index(after: colon)...])
    }
    WebHTTP.done(id, WebHTTP.Response(status: Int(status), headers: parsed, body: takeBytes(body, bodyCount) ?? Data()))
}

@_expose(wasm, "starling_socket_event")
@_cdecl("starling_socket_event")
func starlingSocketEvent(_ id: UInt32, _ kind: Int32, _ bytes: UnsafeMutableRawPointer?, _ count: Int32) {
    WebSocketClient.event(id, kind, takeBytes(bytes, count))
}

@_expose(wasm, "starling_route_changed")
@_cdecl("starling_route_changed")
func starlingRouteChanged(_ bytes: UnsafePointer<UInt8>?, _ count: Int32) {
    guard let bytes, count > 0 else { return }
    WebHistory.onRouteChanged?(String(decoding: UnsafeBufferPointer(start: bytes, count: Int(count)), as: UTF8.self))
}
