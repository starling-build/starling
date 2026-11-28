// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// W-FN-1: the Footnote and Endnote dialog. Where the notes stand, their number format, the first number and when
// the numbering restarts, for footnotes or for endnotes.

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
    let onApply: (NoteReference.Kind, NoteOptions) -> Void
    let onCancel: () -> Void
    init(current: @escaping (NoteReference.Kind) -> NoteOptions, onApply: @escaping (NoteReference.Kind, NoteOptions) -> Void,
         onCancel: @escaping () -> Void) {
        self.current = current; self.onApply = onApply; self.onCancel = onCancel
        super.init()
    }
    override func createState() -> State<StatefulWidget> { FootnoteDialogState() }
}

final class FootnoteDialogState: State<StatefulWidget> {
    private var _w: FootnoteDialog { widget as! FootnoteDialog }
    private(set) var kind: NoteReference.Kind = .footnote
    private(set) var options = NoteOptions.defaults(.footnote)
    private let _start = TextEditingController()

    override func initState() {
        super.initState()
        options = _w.current(kind)
        _start.text = String(options.start)
    }

    func commit() {
        if let n = Int(_start.text.trimmingWhitespace(newlines: true)) { options.start = max(1, min(16383, n)) }
        _start.text = String(options.start)
    }

    private func _switch(to k: NoteReference.Kind) {
        guard k != kind else { return }
        setState { kind = k; options = _w.current(k); _start.text = String(options.start) }
    }

    override func build(_ context: any BuildContext) -> Widget {
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
            ]),
            choices(positions, options.position) { $0.position = $1 },
            heading("Number format"),
            choices(formats, options.format) { $0.format = $1 },
            Padding(padding: EdgeInsets(left: 0, top: 6, right: 0, bottom: 4), child: Row(crossAxisAlignment: .center, children: [
                SizedBox(width: 110, height: nil, child: Text("Start at")),
                SizedBox(width: 80, height: Chrome.fieldHeight, child: NoteKeyed("note-start", FluentTextBox(
                    controller: _start, onSubmitted: { [weak self] _ in self?.commit() },
                    onFocusChanged: { [weak self] f in if !f { self?.commit() } }))),
            ])),
            heading("Numbering"),
            choices(restarts, options.restart) { $0.restart = $1 },
        ])
        return DialogShell(title: "Footnote and Endnote", page: page, width: 560,
                           onOK: { [weak self] in guard let self else { return }; self.commit(); self._w.onApply(self.kind, self.options) },
                           onCancel: { [weak self] in self?._w.onCancel() })
    }
}
