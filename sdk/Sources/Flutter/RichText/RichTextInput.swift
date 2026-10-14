// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The editable's connection to the platform's text-input plugin over
// `flutter/textinput` (JSON method codec), for what key events cannot
// carry: composed input (Chinese, Japanese, Korean), dead keys, macOS
// press-and-hold accents and the emoji picker. The client's text is the
// caret paragraph alone; every local change re-sends the editing state,
// and every update from the plugin is diffed against the paragraph and
// applied as a replacement, with the composing range kept for the
// underline. On by default on macOS, where it has been seen working with
// Pinyin, dead keys and plain typing (2026-10-13; STARLING_IME=0 turns it
// off); elsewhere off unless STARLING_IME is set, because a host with no
// text-input plugin behind the channel would type nothing at all: with
// the connection on, typed characters come from the plugin, so the key
// path declines them (see RichEditable).

import FlutterSwiftBridge
import Foundation

public final class RichTextInputConnection {
    public static let channel = "flutter/textinput"
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

    private static var _nextClient = 1
    private let _clientId: Int
    private unowned let _controller: RichDocumentController
    private var _attached = false
    private var _applying = false
    private var _syncing = false
    private var _lastSent: (paragraph: Int, text: String, base: Int, extent: Int)? = nil

    public init(controller: RichDocumentController) {
        _controller = controller
        _clientId = Self._nextClient
        Self._nextClient += 1
    }

    public var isAttached: Bool { _attached }

    /// Focus gained: become the platform's text-input client.
    private static let _debug = ProcessInfo.processInfo.environment["STARLING_IME_DEBUG"] != nil
    private static func _log(_ s: String) { if _debug { FileHandle.standardError.write(Data(("[ime] " + s + "\n").utf8)) } }

    public func attach() {
        guard Self.enabled, !_attached else { return }
        Self._log("attach sender=\(PlatformDispatcher.instance.platformMessageSender != nil)")
        _attached = true
        MainActor.assumeIsolated {
            channelBuffers.setListener(Self.channel) { [weak self] data, reply in
                self?._handle(data)
                reply(nil)
            }
        }
        let config: [String: Any] = [
            "inputType": ["name": "TextInputType.multiline", "signed": Self._null, "decimal": Self._null],
            "inputAction": "TextInputAction.newline",
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
        _send("TextInput.setClient", [_clientId, config])
        sync(force: true)
        _send("TextInput.show", nil)
    }

    /// Ask the plugin to be the responder again. On macOS the host makes
    /// the Flutter view first responder when the window shows, which is
    /// after the first attach: the plugin's text-input context is then
    /// inactive, plain keys still arrive (the view forwards them), but no
    /// input method can compose. A click re-asserts it.
    public func show() {
        guard _attached else { return }
        _send("TextInput.show", nil)
    }

    /// Where the caret is, for the input method's candidate window: the
    /// editable's size and transform to the view, and the caret's box in
    /// the editable's coordinates. Sent only when something moved — the
    /// editable calls this from every paint, blinks included.
    public func setCaretRect(_ rect: Rect, editableSize: Size, transform: Matrix4) {
        guard _attached else { return }
        if let last = _lastCaret, last.rect == rect, last.size == editableSize, last.transform == transform { return }
        _lastCaret = (rect, editableSize, transform)
        _send("TextInput.setEditableSizeAndTransform",
              ["width": editableSize.width, "height": editableSize.height, "transform": transform.storage])
        _send("TextInput.setCaretRect", ["x": rect.left, "y": rect.top, "width": rect.width, "height": rect.height])
    }
    private var _lastCaret: (rect: Rect, size: Size, transform: Matrix4)? = nil

    /// Focus lost: let go of the plugin.
    public func detach() {
        guard _attached else { return }
        _attached = false
        _lastCaret = nil
        _send("TextInput.clearClient", nil)
        _send("TextInput.hide", nil)
        MainActor.assumeIsolated { channelBuffers.clearListener(Self.channel) }
        _lastSent = nil
        _controller.composingRange = nil
    }

    /// Tell the plugin the caret paragraph's text and selection, when
    /// they differ from what it last heard.
    public func sync(force: Bool = false) {
        guard _attached, !_applying, !_syncing else { return }
        _syncing = true
        defer { _syncing = false }
        // A local change while an input method composes — a click
        // elsewhere, a toolbar button — ends the composition: the plugin
        // discards its marked text on seeing no composing range, the
        // underline goes, and the key path takes keys again. Left in place,
        // the stale range kept declining keys, so End and Enter went to the
        // plugin instead (seen 2026-10-13).
        if _controller.composingRange != nil { _controller.composingRange = nil }
        let sel = _controller.selection
        let p = sel.focus.paragraph
        guard p < _controller.document.paragraphs.count else { return }
        let para = _controller.document.paragraphs[p]
        let base = sel.anchor.paragraph == p ? sel.anchor.offset : sel.focus.offset
        let extent = sel.focus.offset
        if !force, let last = _lastSent, last.paragraph == p, last.text == para.text, last.base == base, last.extent == extent {
            return
        }
        _lastSent = (p, para.text, base, extent)
        var state: [String: Any] = [
            "text": para.text,
            "selectionBase": base,
            "selectionExtent": extent,
            "selectionAffinity": "TextAffinity.downstream",
            "selectionIsDirectional": false,
            "composingBase": -1,
            "composingExtent": -1,
        ]
        if let c = _controller.composingRange, c.paragraph == p {
            state["composingBase"] = c.range.lowerBound
            state["composingExtent"] = c.range.upperBound
        }
        _send("TextInput.setEditingState", state)
    }

    // MARK: Incoming

    private func _handle(_ data: Data?) {
        #if os(WASI)
        return
        #else
        guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let method = json["method"] as? String else { return }
        Self._log("recv \(method) \(String(data: data, encoding: .utf8)?.prefix(200) ?? "")")
        let args = json["args"]
        switch method {
        case "TextInputClient.updateEditingState":
            guard let list = args as? [Any], list.count >= 2, (list[0] as? Int) == _clientId,
                  let state = list[1] as? [String: Any] else { return }
            _apply(state)
        case "TextInputClient.updateEditingStateWithTag":
            guard let list = args as? [Any], list.count >= 2, (list[0] as? Int) == _clientId,
                  let states = list[1] as? [String: Any], let state = states.values.first as? [String: Any] else { return }
            _apply(state)
        case "TextInputClient.performAction":
            guard let list = args as? [Any], list.count >= 2, (list[0] as? Int) == _clientId,
                  let action = list[1] as? String else { return }
            if action == "TextInputAction.newline" {
                _controller.composingRange = nil
                _controller.insertParagraphBreak()
                sync(force: true)
            }
        case "TextInputClient.onConnectionClosed":
            _attached = false
            _controller.composingRange = nil
        default:
            break
        }
        #endif
    }

    /// The plugin's whole state for the paragraph: diff against ours by
    /// common prefix and suffix, replace the middle, take its selection
    /// and composing range.
    private func _apply(_ state: [String: Any]) {
        guard var text = state["text"] as? String else { return }
        let p = _controller.selection.focus.paragraph
        guard p < _controller.document.paragraphs.count, !_controller.document.paragraphs[p].isImage else { return }
        // Before reporting the newline action the plugin puts a "\n" into
        // its own text (a multiline client), and reports that text first.
        // A paragraph holds no newline: it is dropped here, the selection
        // pulled back over it, and the action that follows splits the
        // paragraph at the caret. Kept, it drew as a blank line on top of
        // the split.
        var base = state["selectionBase"] as? Int ?? text.utf16.count
        var extent = state["selectionExtent"] as? Int ?? text.utf16.count
        if text.contains("\n") {
            let u = Array(text.utf16)
            base -= u[0 ..< min(max(base, 0), u.count)].filter { $0 == 10 }.count
            extent -= u[0 ..< min(max(extent, 0), u.count)].filter { $0 == 10 }.count
            text = String(decoding: u.filter { $0 != 10 }, as: UTF16.self)
        }
        let old = Array(_controller.document.paragraphs[p].text.utf16)
        let new = Array(text.utf16)
        var prefix = 0
        while prefix < old.count, prefix < new.count, old[prefix] == new[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < old.count - prefix, suffix < new.count - prefix,
              old[old.count - 1 - suffix] == new[new.count - 1 - suffix] { suffix += 1 }
        _applying = true
        defer { _applying = false }
        if prefix + suffix < old.count || prefix + suffix < new.count {
            let piece = String(decoding: new[prefix ..< new.count - suffix], as: UTF16.self)
            _controller.replaceText(in: p, prefix ..< old.count - suffix, with: piece)
        }
        let length = new.count
        base = min(length, max(0, base))
        extent = min(length, max(0, extent))
        // The plugin's edits are typing: a pending ⌘B outlives them, as it
        // outlives a typed run. The selection it reports can differ from
        // where the replacement left the caret — Pinyin rewrites "shij" as
        // "shi j", so the diff inserts mid-text and the caret then jumps to
        // the end — and that counted as a caret move, which drops the
        // pending style: 世界 typed after ⌘B came out in the previous
        // word's bold (seen 2026-10-13).
        let pending = _controller.typingStyle
        _controller.selection = RichSelection(anchor: RichPosition(paragraph: p, offset: base),
                                              focus: RichPosition(paragraph: p, offset: extent))
        _controller.typingStyle = pending
        let cb = state["composingBase"] as? Int ?? -1
        let ce = state["composingExtent"] as? Int ?? -1
        if cb >= 0, ce > cb, ce <= length {
            _controller.composingRange = (p, cb ..< ce)
        } else {
            _controller.composingRange = nil
        }
        _lastSent = (p, text, base, extent)
    }

    // MARK: Outgoing

    /// JSON `null` for the method codec (`NSNull` is legacy Foundation,
    /// which the web build does not link).
    private static var _null: Any {
        #if os(WASI)
        return Optional<Int>.none as Any
        #else
        return NSNull()
        #endif
    }

    private func _send(_ method: String, _ args: Any?) {
        #if !os(WASI)
        var body: [String: Any] = ["method": method]
        body["args"] = args ?? Self._null
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        Self._log("send \(method) sender=\(PlatformDispatcher.instance.platformMessageSender != nil) \(String(data: data, encoding: .utf8)?.prefix(160) ?? "")")
        PlatformDispatcher.instance.sendPlatformMessage(Self.channel, data) { _ in }
        #endif
    }
}
