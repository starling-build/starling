// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// W-FN-1: the Footnote and Endnote dialog. Where the notes stand, their number format, the first number and when
// the numbering restarts, for footnotes or for endnotes; a custom mark; Convert (footnotes to endnotes, back, or swap).
// Insert applies the settings and puts a note at the caret; Apply only applies them.

import Flutter
import FlutterSwiftBridge
import OfficeText

private final class NoteKeyed: StatelessWidget {
    let child: Widget
    init(_ id: String, _ child: Widget) { self.child = child; super.init(key: ValueKey(id)) }
    override func build(_ context: any BuildContext) -> Widget { child }
}

final class FootnoteDialog: StatefulWidget {
    let current: (NoteReference.Kind) -> NoteOptions
    /// The settings applied to the whole document, or (true) to the caret's section only.
    let onApply: (NoteReference.Kind, NoteOptions, Bool) -> Void
    /// Insert: the settings applied, then a note of the kind at the caret (with the custom mark when one is typed).
    let onInsert: (NoteReference.Kind, NoteOptions, String?, Bool) -> Void
    let onConvert: (NoteConversion) -> Void
    /// How many footnotes and endnotes the document has (Convert offers only what there is to convert).
    let counts: (footnotes: Int, endnotes: Int)
    let onCancel: () -> Void
    /// Whether the caret's section states the kind's options of its own (the dialog then opens on "This section").
    let sectionOwns: (NoteReference.Kind) -> Bool
    init(current: @escaping (NoteReference.Kind) -> NoteOptions, onApply: @escaping (NoteReference.Kind, NoteOptions, Bool) -> Void,
         onInsert: @escaping (NoteReference.Kind, NoteOptions, String?, Bool) -> Void = { _, _, _, _ in },
         onConvert: @escaping (NoteConversion) -> Void = { _ in }, counts: (footnotes: Int, endnotes: Int) = (0, 0),
         sectionOwns: @escaping (NoteReference.Kind) -> Bool = { _ in false }, onCancel: @escaping () -> Void) {
        self.current = current; self.onApply = onApply; self.onInsert = onInsert; self.onConvert = onConvert
        self.counts = counts; self.onCancel = onCancel; self.sectionOwns = sectionOwns
        super.init()
    }
    override func createState() -> State<StatefulWidget> { FootnoteDialogState() }
}

final class FootnoteDialogState: State<StatefulWidget> {
    private var _w: FootnoteDialog { widget as! FootnoteDialog }
    private(set) var kind: NoteReference.Kind = .footnote
    private(set) var options = NoteOptions.defaults(.footnote)
    private let _start = TextEditingController()
    private let _custom = TextEditingController()
    /// The Convert Notes choices showing, and the one picked.
    private(set) var converting = false
    private(set) var conversion = NoteConversion.footnotesToEndnotes
    /// Apply changes to: the caret's section only (false: the whole document).
    private(set) var thisSection = false

    override func initState() {
        super.initState()
        options = _w.current(kind)
        thisSection = _w.sectionOwns(kind)
        _start.text = String(options.start)
    }

    func commit() {
        if let n = Int(_start.text.trimmingWhitespace(newlines: true)) { options.start = max(1, min(16383, n)) }
        _start.text = String(options.start)
    }

    private func _switch(to k: NoteReference.Kind) {
        guard k != kind else { return }
        setState { kind = k; options = _w.current(k); thisSection = _w.sectionOwns(k); _start.text = String(options.start) }
    }

    func _customForTesting(_ t: String) { _custom.text = t }
    /// The Insert button (a tap by its label finds the ribbon's Insert tab first).
    func _insertForTesting() { commit(); _w.onInsert(kind, options, customMark, thisSection) }

    var customMark: String? {
        let t = _custom.text.trimmingWhitespace(newlines: true)
        return t.isEmpty ? nil : t
    }

    private func _conversions() -> [(String, NoteConversion)] {
        var out: [(String, NoteConversion)] = []
        if _w.counts.footnotes > 0 { out.append(("Convert all footnotes to endnotes", .footnotesToEndnotes)) }
        if _w.counts.endnotes > 0 { out.append(("Convert all endnotes to footnotes", .endnotesToFootnotes)) }
        if _w.counts.footnotes > 0, _w.counts.endnotes > 0 { out.append(("Swap footnotes and endnotes", .swap)) }
        return out
    }

    /// Convert…: the choices, the first that applies picked.
    func openConvert() {
        guard let first = _conversions().first else { return }
        setState { converting = true; conversion = first.1 }
    }

    private func _convertPage() -> Widget {
        Column(crossAxisAlignment: .start, children: _conversions().map { name, value in
            Padding(padding: EdgeInsets(left: 0, top: 4, right: 0, bottom: 4), child: Checkbox(
                checked: conversion == value,
                onChanged: { [weak self] v in if v == true { self?.setState { self?.conversion = value } } },
                content: Text(name)))
        })
    }

    override func build(_ context: any BuildContext) -> Widget {
        if converting {
            return DialogShell(title: "Convert Notes", page: _convertPage(), width: 420,
                               onOK: { [weak self] in guard let self else { return }; self._w.onConvert(self.conversion) },
                               onCancel: { [weak self] in self?.setState { self?.converting = false } })
        }
        func choices<T: Equatable>(_ items: [(String, T)], _ current: T, _ set: @escaping (inout NoteOptions, T) -> Void) -> Widget {
            Row(crossAxisAlignment: .center, children: items.map { name, value in
                Padding(padding: EdgeInsets(left: 0, top: 4, right: 12, bottom: 4), child: Checkbox(
                    checked: current == value,
                    onChanged: { [weak self] v in if v == true { self?.setState { if let self { set(&self.options, value) } } } },
                    content: Text(name)))
            })
        }
        func heading(_ s: String) -> Widget { Padding(padding: EdgeInsets(left: 0, top: 10, right: 0, bottom: 0), child: Text(s)) }
        let positions: [(String, String)] = kind == .footnote ? [("Bottom of page", "pageBottom"), ("Below text", "beneathText")]
            : [("End of document", "docEnd"), ("End of section", "sectEnd")]
        let formats: [(String, ListNumberFormat)] = [("1, 2, 3", .decimal), ("a, b, c", .lowerLetter), ("A, B, C", .upperLetter),
                                                     ("i, ii, iii", .lowerRoman), ("I, II, III", .upperRoman)]
        let restarts: [(String, String)] = [("Continuous", "continuous"), ("Restart each section", "eachSect")]
            + (kind == .footnote ? [("Restart each page", "eachPage")] : [])
        let page = Column(crossAxisAlignment: .start, children: [
            Text("Location"),
            Row(crossAxisAlignment: .center, children: [
                Padding(padding: EdgeInsets(left: 0, top: 4, right: 12, bottom: 4), child: Checkbox(
                    checked: kind == .footnote, onChanged: { [weak self] v in if v == true { self?._switch(to: .footnote) } },
                    content: Text("Footnotes"))),
                Padding(padding: EdgeInsets(left: 0, top: 4, right: 12, bottom: 4), child: Checkbox(
                    checked: kind == .endnote, onChanged: { [weak self] v in if v == true { self?._switch(to: .endnote) } },
                    content: Text("Endnotes"))),
                NoteKeyed("note-convert", Button(onPressed: _conversions().isEmpty ? nil : { [weak self] in self?.openConvert() },
                                                 child: Text("Convert…"))),
            ]),
            choices(positions, options.position) { $0.position = $1 },
            heading("Number format"),
            choices(formats, options.format) { $0.format = $1 },
            Padding(padding: EdgeInsets(left: 0, top: 6, right: 0, bottom: 0), child: Row(crossAxisAlignment: .center, children: [
                SizedBox(width: 110, height: nil, child: Text("Custom mark")),
                SizedBox(width: 80, height: Chrome.fieldHeight, child: NoteKeyed("note-custom", FluentTextBox(controller: _custom))),
            ])),
            Padding(padding: EdgeInsets(left: 0, top: 6, right: 0, bottom: 4), child: Row(crossAxisAlignment: .center, children: [
                SizedBox(width: 110, height: nil, child: Text("Start at")),
                SizedBox(width: 80, height: Chrome.fieldHeight, child: NoteKeyed("note-start", FluentTextBox(
                    controller: _start, onSubmitted: { [weak self] _ in self?.commit() },
                    onFocusChanged: { [weak self] f in if !f { self?.commit() } }))),
            ])),
            heading("Numbering"),
            choices(restarts, options.restart) { $0.restart = $1 },
            heading("Apply changes to"),
            Row(crossAxisAlignment: .center, children: [("Whole document", false), ("This section", true)].map { name, value in
                Padding(padding: EdgeInsets(left: 0, top: 4, right: 12, bottom: 4), child: NoteKeyed(value ? "note-scope-section" : "note-scope-document", Checkbox(
                    checked: thisSection == value,
                    onChanged: { [weak self] v in if v == true { self?.setState { self?.thisSection = value } } },
                    content: Text(name))))
            }),
        ])
        let shell = DialogShell(title: "Footnote and Endnote", page: page, okLabel: "Insert", width: 560,
                                onOK: { [weak self] in
                                    guard let self else { return }
                                    self.commit(); self._w.onInsert(self.kind, self.options, self.customMark, self.thisSection)
                                },
                                onCancel: { [weak self] in self?._w.onCancel() })
        shell.middle = ("Apply", { [weak self] in guard let self else { return }; self.commit(); self._w.onApply(self.kind, self.options, self.thisSection) })
        return shell
    }
}
