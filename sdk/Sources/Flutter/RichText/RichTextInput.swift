// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The editable's connection to the platform's text-input plugin over
// `flutter/textinput` (JSON method codec), for what key events cannot
// carry: composed input (Chinese, Japanese, Korean), dead keys, macOS
// press-and-hold accents and the emoji picker. The client's text is the
// caret paragraph alone; every local change re-sends the editing state,
// and every update from the plugin is diffed against the paragraph and
// applied as a replacement, with the composing range kept for the
// underline. Off unless STARLING_IME is set until it has been seen
// working with an input source; with it on, typed characters come from
// the plugin, so the key path must decline them (see RichEditable).

import FlutterSwiftBridge
import Foundation

public final class RichTextInputConnection {
    public static let channel = "flutter/textinput"
    /// Whether editables connect at all.
    public nonisolated(unsafe) static var enabled: Bool = ProcessInfo.processInfo.environment["STARLING_IME"] != nil

    private static var _nextClient = 1
    private let _clientId: Int
    private unowned let _controller: RichDocumentController
    private var _attached = false
    private var _applying = false
    private var _lastSent: (paragraph: Int, text: String, base: Int, extent: Int)? = nil

    public init(controller: RichDocumentController) {
        _controller = controller
        _clientId = Self._nextClient
        Self._nextClient += 1
    }

    public var isAttached: Bool { _attached }

    /// Focus gained: become the platform's text-input client.
    public func attach() {
        guard Self.enabled, !_attached else { return }
        _attached = true
        MainActor.assumeIsolated {
            channelBuffers.setListener(Self.channel) { [weak self] data, reply in
                self?._handle(data)
                reply(nil)
            }
        }
        let config: [String: Any] = [
            "inputType": ["name": "TextInputType.multiline", "signed": NSNull(), "decimal": NSNull()],
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

    /// Focus lost: let go of the plugin.
    public func detach() {
        guard _attached else { return }
        _attached = false
        _send("TextInput.clearClient", nil)
        _send("TextInput.hide", nil)
        MainActor.assumeIsolated { channelBuffers.clearListener(Self.channel) }
        _lastSent = nil
        _controller.composingRange = nil
    }

    /// Tell the plugin the caret paragraph's text and selection, when
    /// they differ from what it last heard.
    public func sync(force: Bool = false) {
        guard _attached, !_applying else { return }
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
        guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let method = json["method"] as? String else { return }
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
    }

    /// The plugin's whole state for the paragraph: diff against ours by
    /// common prefix and suffix, replace the middle, take its selection
    /// and composing range.
    private func _apply(_ state: [String: Any]) {
        guard let text = state["text"] as? String else { return }
        let p = _controller.selection.focus.paragraph
        guard p < _controller.document.paragraphs.count, !_controller.document.paragraphs[p].isImage else { return }
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
            let piece = String(utf16CodeUnits: Array(new[prefix ..< new.count - suffix]), count: new.count - suffix - prefix)
            _controller.replaceText(in: p, prefix ..< old.count - suffix, with: piece)
        }
        let length = new.count
        let base = min(length, max(0, state["selectionBase"] as? Int ?? length))
        let extent = min(length, max(0, state["selectionExtent"] as? Int ?? length))
        _controller.selection = RichSelection(anchor: RichPosition(paragraph: p, offset: base),
                                              focus: RichPosition(paragraph: p, offset: extent))
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

    private func _send(_ method: String, _ args: Any?) {
        var body: [String: Any] = ["method": method]
        body["args"] = args ?? NSNull()
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        PlatformDispatcher.instance.sendPlatformMessage(Self.channel, data) { _ in }
    }
}
