// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The rich editor's connection to the platform's text-input plugin over
// `flutter/textinput` (JSON method codec), for what key events cannot
// carry: composed input (Chinese, Japanese, Korean), dead keys, macOS
// press-and-hold accents and the emoji picker. The client's text is the
// caret paragraph alone; every local change re-sends the editing state,
// and every update from the plugin is diffed against the paragraph and
// applied as a replacement, with the composing range kept for the
// underline. The channel, the on/off switch and the listener's ownership
// are TextInputChannel's (Widgets/TextInputConnection.swift), shared with
// the plain fields' TextInputConnection.

import FlutterSwiftBridge
import Foundation

public final class RichTextInputConnection {
    /// Whether editables connect at all (TextInputChannel.enabled).
    public static var enabled: Bool {
        get { TextInputChannel.enabled }
        set { TextInputChannel.enabled = newValue }
    }

    private let _clientId: Int
    private unowned let _controller: RichDocumentController
    private var _attached = false
    private var _applying = false
    private var _syncing = false
    private var _lastSent: (paragraph: Int, text: String, base: Int, extent: Int)? = nil

    public init(controller: RichDocumentController) {
        _controller = controller
        _clientId = TextInputChannel.nextClientId()
    }

    public var isAttached: Bool { _attached }

    /// Focus gained: become the platform's text-input client.
    public func attach() {
        guard TextInputChannel.available, !_attached else { return }
        _attached = true
        TextInputChannel.listen(owner: self) { [weak self] data in self?._handle(data) }
        _send("TextInput.setClient", [_clientId, TextInputChannel.config(multiline: true)])
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
        TextInputChannel.unlisten(owner: self)
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
        guard let (method, client, payload) = TextInputChannel.decode(data), client == _clientId else { return }
        switch method {
        case "TextInputClient.updateEditingState":
            if let state = payload as? [String: Any] { _apply(state) }
        case "TextInputClient.updateEditingStateWithTag":
            if let states = payload as? [String: Any], let state = states.values.first as? [String: Any] { _apply(state) }
        case "TextInputClient.performAction":
            if payload as? String == "TextInputAction.newline" {
                _controller.composingRange = nil
                _controller.insertParagraphBreak()
                sync(force: true)
            }
        case "TextInputClient.onConnectionClosed":
            _attached = false
            _controller.composingRange = nil
            TextInputChannel.unlisten(owner: self)
        default:
            break
        }
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

    private func _send(_ method: String, _ args: Any?) { TextInputChannel.send(method, args) }
}
