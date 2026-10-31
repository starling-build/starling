// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The `flutter/textinput` channel, shared by everything that takes
// composed input (Chinese, Japanese, Korean), dead keys, press-and-hold
// accents and the emoji picker: the rich editor (RichTextInputConnection)
// and the plain fields here — the Fluent text box, Sheets' in-cell
// editor. One client is the platform's at a time, so the channel's
// listener is owned: the field that attached last has it, and a detach
// from an earlier owner leaves it alone (focus can leave one field after
// the next has taken it).
//
// On by default on macOS, where composition has been seen working with
// Pinyin, dead keys and plain typing (2026-10-13; STARLING_IME=0 turns it
// off); elsewhere off unless STARLING_IME is set, because a host with no
// text-input plugin behind the channel would type nothing at all: with
// the connection on, typed characters come from the plugin, so the key
// path declines them.

import FlutterSwiftBridge
import Foundation

public enum TextInputChannel {
    public static let name = "flutter/textinput"

    /// Whether editables connect at all.
    #if os(WASI)
    /// The browser has no text-input plugin behind `flutter/textinput` yet:
    /// composed input there is a follow-up (docs/plans/wasm.md).
    public nonisolated(unsafe) static var enabled: Bool = false
    #elseif os(macOS)
    public nonisolated(unsafe) static var enabled: Bool = ProcessInfo.processInfo.environment["STARLING_IME"] != "0"
    #else
    public nonisolated(unsafe) static var enabled: Bool = ProcessInfo.processInfo.environment["STARLING_IME"] != nil
    #endif

    /// Enabled, and there is an engine to carry the messages: a headless
    /// test has no platform message sender, so no plugin, and a field that
    /// attached there would decline every typed key for a plugin that never
    /// answers.
    public static var available: Bool {
        enabled && PlatformDispatcher.instance.platformMessageSender != nil
    }

    private nonisolated(unsafe) static var _nextClient = 1
    public static func nextClientId() -> Int {
        defer { _nextClient += 1 }
        return _nextClient
    }

    private nonisolated(unsafe) static var _owner: ObjectIdentifier? = nil

    /// Take the channel's listener.
    public static func listen(owner: AnyObject, _ handler: @escaping (Data?) -> Void) {
        _owner = ObjectIdentifier(owner)
        MainActor.assumeIsolated {
            channelBuffers.setListener(name) { data, reply in
                handler(data)
                reply(nil)
            }
        }
    }

    /// Let go of the listener, if it is still this owner's.
    public static func unlisten(owner: AnyObject) {
        guard _owner == ObjectIdentifier(owner) else { return }
        _owner = nil
        MainActor.assumeIsolated { channelBuffers.clearListener(name) }
    }

    static let debug = ProcessInfo.processInfo.environment["STARLING_IME_DEBUG"] != nil
    static func log(_ s: String) {
        if debug { FileHandle.standardError.write(Data(("[ime] " + s + "\n").utf8)) }
    }

    /// JSON `null` for the method codec (`NSNull` is legacy Foundation,
    /// which the web build does not link).
    static var null: Any {
        #if os(WASI)
        return Optional<Int>.none as Any
        #else
        return NSNull()
        #endif
    }

    public static func send(_ method: String, _ args: Any?) {
        #if !os(WASI)
        var body: [String: Any] = ["method": method]
        body["args"] = args ?? null
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        log("send \(method) sender=\(PlatformDispatcher.instance.platformMessageSender != nil) \(String(data: data, encoding: .utf8)?.prefix(160) ?? "")")
        PlatformDispatcher.instance.sendPlatformMessage(name, data) { _ in }
        #endif
    }

    /// A decoded message: its method and the client id and payload of a
    /// `TextInputClient.*` call, or nil for anything else.
    public static func decode(_ data: Data?) -> (method: String, client: Int, payload: Any?)? {
        #if os(WASI)
        return nil
        #else
        guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let method = json["method"] as? String else { return nil }
        log("recv \(method) \(String(data: data, encoding: .utf8)?.prefix(200) ?? "")")
        let list = json["args"] as? [Any]
        return (method, list?.first as? Int ?? -1, list?.count ?? 0 >= 2 ? list?[1] : nil)
        #endif
    }

    /// The client configuration for `TextInput.setClient`.
    public static func config(multiline: Bool) -> [String: Any] {
        [
            "inputType": ["name": multiline ? "TextInputType.multiline" : "TextInputType.text",
                          "signed": null, "decimal": null],
            "inputAction": multiline ? "TextInputAction.newline" : "TextInputAction.done",
            "readOnly": false,
            "obscureText": false,
            "autocorrect": false,
            "enableSuggestions": false,
            "enableDeltaModel": false,
            "textCapitalization": "TextCapitalization.none",
            "keyboardAppearance": "Brightness.light",
            "enableIMEPersonalizedLearning": true,
            "enableInteractiveSelection": true,
        ]
    }
}

/// A plain text field, as the plugin sees it: one string, a selection and
/// a composing range, all in characters (what `TextEditingController`
/// counts in; the connection converts to the plugin's UTF-16 offsets).
/// Setting the value is the plugin's edit — composed, accented or plain —
/// and the field shows it; while the composing range is non-empty an
/// input method owns the keys.
public protocol TextInputClient: AnyObject {
    var textInputValue: TextEditingValue { get set }
    /// The plugin's action key (`TextInputAction.done`, `.newline`).
    func textInputPerformAction(_ action: String)
}

extension TextInputClient {
    public func textInputPerformAction(_ action: String) {}
}

/// A plain field's connection to the platform's text-input plugin. The
/// field attaches on focus, syncs after each local change, and takes the
/// plugin's whole state as its own on every update.
public final class TextInputConnection {
    private let _clientId: Int
    private unowned let _client: TextInputClient
    private var _attached = false
    private var _applying = false
    private var _syncing = false
    private var _lastSent: TextEditingValue? = nil
    private var _lastCaret: (rect: Rect, size: Size, transform: Matrix4)? = nil

    public init(client: TextInputClient) {
        _client = client
        _clientId = TextInputChannel.nextClientId()
    }

    public var isAttached: Bool { _attached }

    /// Whether an input method is composing: every key is its.
    public var isComposing: Bool {
        guard _attached else { return false }
        let c = _client.textInputValue.composing
        return c.isValid && !c.isCollapsed
    }

    /// Focus gained: become the platform's text-input client.
    public func attach(multiline: Bool = false) {
        guard TextInputChannel.available, !_attached else { return }
        _attached = true
        TextInputChannel.listen(owner: self) { [weak self] data in self?._handle(data) }
        TextInputChannel.send("TextInput.setClient", [_clientId, TextInputChannel.config(multiline: multiline)])
        sync(force: true)
        TextInputChannel.send("TextInput.show", nil)
    }

    /// Ask the plugin to be the responder again (a click; see
    /// RichTextInputConnection.show).
    public func show() {
        guard _attached else { return }
        TextInputChannel.send("TextInput.show", nil)
    }

    /// Focus lost: let go of the plugin.
    public func detach() {
        guard _attached else { return }
        _attached = false
        _lastCaret = nil
        _lastSent = nil
        TextInputChannel.send("TextInput.clearClient", nil)
        TextInputChannel.send("TextInput.hide", nil)
        TextInputChannel.unlisten(owner: self)
        let v = _client.textInputValue
        if v.composing.isValid { _client.textInputValue = v.copyWith(composing: TextRange.empty) }
    }

    /// Where the caret is, for the input method's candidate window (see
    /// RichTextInputConnection.setCaretRect). Sent only when it moved.
    public func setCaretRect(_ rect: Rect, editableSize: Size, transform: Matrix4) {
        guard _attached else { return }
        if let last = _lastCaret, last.rect == rect, last.size == editableSize, last.transform == transform { return }
        _lastCaret = (rect, editableSize, transform)
        TextInputChannel.send("TextInput.setEditableSizeAndTransform",
                              ["width": editableSize.width, "height": editableSize.height, "transform": transform.storage])
        TextInputChannel.send("TextInput.setCaretRect", ["x": rect.left, "y": rect.top, "width": rect.width, "height": rect.height])
    }

    /// Tell the plugin the field's text and selection, when they differ
    /// from what it last heard. A local change while an input method
    /// composes ends the composition (the plugin discards its marked text
    /// on seeing no composing range).
    public func sync(force: Bool = false) {
        guard _attached, !_applying, !_syncing else { return }
        _syncing = true
        defer { _syncing = false }
        var v = _client.textInputValue
        if v.composing.isValid {
            v = v.copyWith(composing: TextRange.empty)
            _client.textInputValue = v
        }
        if !force, let last = _lastSent, last == v { return }
        _lastSent = v
        let text = v.text
        let end = text.count
        let base = v.selection.isValid ? min(max(0, v.selection.baseOffset), end) : end
        let extent = v.selection.isValid ? min(max(0, v.selection.extentOffset), end) : end
        TextInputChannel.send("TextInput.setEditingState", [
            "text": text,
            "selectionBase": Self._utf16(text, base),
            "selectionExtent": Self._utf16(text, extent),
            "selectionAffinity": "TextAffinity.downstream",
            "selectionIsDirectional": false,
            "composingBase": -1,
            "composingExtent": -1,
        ] as [String: Any])
    }

    // MARK: Incoming

    private func _handle(_ data: Data?) {
        guard let (method, client, payload) = TextInputChannel.decode(data), client == _clientId else { return }
        switch method {
        case "TextInputClient.updateEditingState":
            if let state = payload as? [String: Any] { _apply(state) }
        case "TextInputClient.updateEditingStateWithTag":
            if let states = payload as? [String: Any], let state = states.values.first as? [String: Any] { _apply(state) }
        case "TextInputClient.performAction":
            if let action = payload as? String { _client.textInputPerformAction(action) }
        case "TextInputClient.onConnectionClosed":
            _attached = false
            _lastSent = nil
            TextInputChannel.unlisten(owner: self)
        default:
            break
        }
    }

    /// The plugin's whole state becomes the field's. A newline the plugin
    /// put in (a multiline client, before its action) stays: the field
    /// decides what to do with it.
    private func _apply(_ state: [String: Any]) {
        guard let text = state["text"] as? String else { return }
        let end = text.utf16.count
        let base = min(end, max(0, state["selectionBase"] as? Int ?? end))
        let extent = min(end, max(0, state["selectionExtent"] as? Int ?? end))
        let cb = state["composingBase"] as? Int ?? -1
        let ce = state["composingExtent"] as? Int ?? -1
        let composing = cb >= 0 && ce > cb && ce <= end
            ? TextRange(start: Self._chars(text, cb), end: Self._chars(text, ce))
            : TextRange.empty
        let value = TextEditingValue(
            text: text,
            selection: TextSelection(baseOffset: Self._chars(text, base), extentOffset: Self._chars(text, extent)),
            composing: composing)
        _applying = true
        defer { _applying = false }
        _client.textInputValue = value
        _lastSent = _client.textInputValue
    }

    // MARK: Offsets

    /// A character offset as a UTF-16 offset.
    private static func _utf16(_ s: String, _ chars: Int) -> Int {
        let i = s.index(s.startIndex, offsetBy: min(chars, s.count))
        return s.utf16.distance(from: s.utf16.startIndex, to: i)
    }

    /// A UTF-16 offset as a character offset.
    private static func _chars(_ s: String, _ utf16: Int) -> Int {
        let i = String.Index(utf16Offset: min(utf16, s.utf16.count), in: s)
        return s.distance(from: s.startIndex, to: i)
    }
}
