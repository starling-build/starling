// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// W-FD-3: References > Insert Caption. The label (Equation, Figure, Table, or a new one), the caption's own text after
// "Figure 1", above or below the selected item (a table's caption goes by the whole table), and "Exclude label from
// caption". OK inserts a "Caption" paragraph numbered by a SEQ field, one undo step.

import Flutter
import FlutterSwiftBridge
import OfficeText

final class CaptionDialog: StatefulWidget {
    let controller: RichDocumentController
    let onDone: () -> Void

    init(controller: RichDocumentController, onDone: @escaping () -> Void) {
        self.controller = controller; self.onDone = onDone
        super.init()
    }
    override func createState() -> State<StatefulWidget> { CaptionDialogState() }
}

final class CaptionDialogState: State<StatefulWidget> {
    private var _w: CaptionDialog { widget as! CaptionDialog }
    let title = TextEditingController()
    let newLabel = TextEditingController()
    private(set) var labels = RichDocumentController.captionLabels
    private(set) var label = "Figure"
    private(set) var place: RichDocumentController.CaptionPlace = .below
    private(set) var excludeLabel = false

    override func initState() {
        super.initState()
        // A table's caption goes above it, Word's default when the caret is in one.
        let c = _w.controller
        if c.document.paragraphs[c.document.clamped(c.selection.focus).paragraph].cell != nil { label = "Table"; place = .above }
    }

    func insert() {
        _w.controller.insertCaption(label: label, title: title.text, place: place, excludeLabel: excludeLabel)
        _w.onDone()
    }

    func addLabel() {
        let l = newLabel.text
        guard !l.isEmpty, l.first?.isLetter == true else { return }
        setState {
            if !labels.contains(l) { labels.append(l); labels.sort() }
            label = l
            newLabel.text = ""
        }
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let number = _w.controller.nextCaptionNumber(label, place)
        let lead = (excludeLabel ? "" : label + " ") + String(number)
        let labelRow: [Widget] = labels.map { l in
            PKeyed("cap-label-\(l)", Chrome.textToggle(l, l == label, fluent, action: { [weak self] in self?.setState { self?.label = l } }))
        }
        let page: Widget = Column(crossAxisAlignment: .start, children: [
            Text("Caption:", style: fluent.typography.body),
            SizedBox(width: nil, height: 4),
            Row(crossAxisAlignment: .center, children: [
                Text(lead, style: fluent.typography.body),
                SizedBox(width: 4, height: nil),
                Expanded(child: PKeyed("cap-title", SizedBox(width: nil, height: Chrome.fieldHeight, child: FluentTextBox(
                    controller: title, onChanged: { [weak self] _ in self?.setState {} })))),
            ]),
            SizedBox(width: nil, height: 10),
            Text("Label:", style: fluent.typography.body),
            SizedBox(width: nil, height: 4),
            Wrap(spacing: 6, runSpacing: 6, children: labelRow),
            SizedBox(width: nil, height: 10),
            Row(children: [
                Text("Position:  ", style: fluent.typography.body),
                PKeyed("cap-above", Checkbox(checked: place == .above, onChanged: { [weak self] _ in self?.setState { self?.place = .above } },
                                             content: Text("Above selected item", style: fluent.typography.body))),
                SizedBox(width: 12, height: nil),
                PKeyed("cap-below", Checkbox(checked: place == .below, onChanged: { [weak self] _ in self?.setState { self?.place = .below } },
                                             content: Text("Below selected item", style: fluent.typography.body))),
            ]),
            SizedBox(width: nil, height: 8),
            PKeyed("cap-exclude", Checkbox(checked: excludeLabel, onChanged: { [weak self] v in self?.setState { self?.excludeLabel = v ?? false } },
                                           content: Text("Exclude label from caption", style: fluent.typography.body))),
            SizedBox(width: nil, height: 10),
            Row(crossAxisAlignment: .center, children: [
                SizedBox(width: 160, height: Chrome.fieldHeight, child: PKeyed("cap-new-label", FluentTextBox(
                    controller: newLabel, onChanged: { [weak self] _ in self?.setState {} }))),
                SizedBox(width: 8, height: nil),
                PKeyed("cap-add-label", Button(onPressed: newLabel.text.isEmpty ? nil : { [weak self] in self?.addLabel() }, child: Text("New Label"))),
            ]),
        ])
        return DialogShell(title: "Caption", page: page, okEnabled: true, width: 460,
                           onOK: { [weak self] in self?.insert() },
                           onCancel: { [weak self] in self?._w.onDone() })
    }
}
