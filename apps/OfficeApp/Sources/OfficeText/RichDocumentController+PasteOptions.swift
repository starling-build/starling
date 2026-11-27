// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge

/// What a paste put in, kept so the Paste Options button can redo it another way (W-ED-1).
struct PasteRecord {
    var data: ClipboardData
    var mode: RichDocumentController.PasteMode
    /// The document's revision just after the paste: any later edit, undo or redo retires the record.
    var revision: Int
    /// Where the pasted content ends: the button sits there.
    var end: RichPosition
}

extension RichDocumentController {
    /// The Paste Options after a paste, as Word shows its button: the way the last paste was made and where it
    /// ends, while nothing has changed the document since. Nil hides the button.
    public var pasteOptions: (mode: PasteMode, end: RichPosition)? {
        guard let p = _lastPaste, p.revision == revision else { return nil }
        return (p.mode, p.end)
    }

    /// Whether the last paste can be redone as `mode` (the button's entries that cannot are greyed).
    public func canRepaste(_ mode: PasteMode) -> Bool {
        guard let p = _lastPaste, p.revision == revision else { return false }
        return canPaste(p.data, mode: mode)
    }

    /// Redo the last paste as `mode`: the paste is undone and made again the new way, so one Undo still takes it
    /// all out, as in Word. The button stays, now on the new way.
    public func repaste(_ mode: PasteMode) {
        guard let p = _lastPaste, p.revision == revision, p.mode != mode, canPaste(p.data, mode: mode), canUndo else { return }
        undo()
        paste(data: p.data, mode: mode)
    }

    /// Records a paste made by `data` in `mode` (the keyboard's paste goes round `paste(data:mode:)` and reports
    /// itself here). Nothing is recorded when the paste changed nothing.
    public func notePaste(_ data: ClipboardData, mode: PasteMode, revisionBefore: Int) {
        guard revision != revisionBefore else { return }
        _lastPaste = PasteRecord(data: data, mode: mode, revision: revision, end: selection.focus)
    }
}

/// One "As:" entry of Writer's Paste Special (Ctrl+Alt+V): a clipboard format pasted on its own, as Word lists them.
public enum PasteSpecialFormat: Equatable, Sendable, CaseIterable {
    case html, rtf, unformattedText, picture

    /// Word's own words for each.
    public var label: String {
        switch self {
        case .html: return "HTML Format"
        case .rtf: return "Formatted Text (RTF)"
        case .unformattedText: return "Unformatted Text"
        case .picture: return "Picture (PNG)"
        }
    }

    /// The formats `data` offers, in Word's order (the richest first).
    public static func offered(by data: ClipboardData) -> [PasteSpecialFormat] {
        var out: [PasteSpecialFormat] = []
        if data.html?.isEmpty == false { out.append(.html) }
        if data.rtf?.isEmpty == false { out.append(.rtf) }
        if data.text?.isEmpty == false { out.append(.unformattedText) }
        if data.png.flatMap({ ImageAttachment.pngPixelSize($0) }) != nil { out.append(.picture) }
        return out
    }
}

extension RichDocumentController {
    /// Paste Special: `data` pasted from the one format, in one undo step. The Paste Options button then shows as
    /// after any paste, with every way the whole clipboard offers.
    public func pasteSpecial(_ data: ClipboardData, as format: PasteSpecialFormat) {
        let before = revision
        switch format {
        case .html:
            // Only that format is read: the plain text that matches our own copy would bring the copy instead.
            guard let html = data.html else { return }
            _pasteRich(ClipboardData(text: nil, html: html))
        case .rtf:
            guard let rtf = data.rtf else { return }
            _pasteRich(ClipboardData(text: nil, rtf: rtf))
        case .unformattedText:
            paste(data: data, mode: .textOnly)
        case .picture:
            paste(data: data, mode: .picture)
        }
        notePaste(data, mode: format == .unformattedText ? .textOnly : format == .picture ? .picture : .keepSource, revisionBefore: before)
    }

    private func _pasteRich(_ only: ClipboardData) {
        guard let codec = clipboardCodec, let fragment = codec.decode(only), !fragment.isEmpty, !_selectionLocked() else { return }
        _ = insertFragment(fragment, smart: true)
    }
}
