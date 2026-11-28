// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// W-FD-1: Insert → Quick Parts → Field. The field names Word lists for a document's own facts (its properties, the
// date and time, the page and page count, the file name), the date and time formats, and "Preserve formatting during
// updates" (Word's \* MERGEFORMAT, on by default). OK inserts the field at the caret, one undo step.

import Flutter
import FlutterSwiftBridge
import OfficeText

final class FieldDialog: StatefulWidget {
    let clock: FieldClock
    let onOK: (_ instruction: String) -> Void
    let onCancel: () -> Void

    /// Word's field names, with the description it shows for each.
    static let fields: [(name: String, about: String)] = [
        ("Author", "The name of the document's author from Document Properties"),
        ("Comments", "The comments from Document Properties"),
        ("Date", "Today's date"),
        ("FileName", "The document's name and location"),
        ("Keywords", "The keywords from Document Properties"),
        ("LastSavedBy", "The name of the user who last saved the document"),
        ("NumPages", "The number of pages in the document"),
        ("Page", "The number of the current page"),
        ("Subject", "The document's subject from Document Properties"),
        ("Time", "The current time"),
        ("Title", "The document's title from Document Properties"),
    ]

    /// The instruction for the field `name` (`Date`) with `picture` (date and time only) and MERGEFORMAT when `preserve`.
    static func instruction(_ name: String, picture: String?, preserve: Bool) -> String {
        var out = " " + name.uppercased() + " "
        if let picture, name == "Date" || name == "Time" { out += "\\@ \"\(picture)\" " }
        if preserve { out += "\\* MERGEFORMAT " }
        return out
    }

    init(clock: FieldClock, onOK: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.clock = clock; self.onOK = onOK; self.onCancel = onCancel
        super.init()
    }
    override func createState() -> State<StatefulWidget> { FieldDialogState() }
}

final class FieldDialogState: State<StatefulWidget> {
    private var _w: FieldDialog { widget as! FieldDialog }
    private(set) var picked = 2
    private(set) var picture = 0
    private(set) var preserve = true

    private func _row(_ text: String, on: Bool, _ tap: @escaping () -> Void, _ fluent: FluentThemeData) -> Widget {
        GestureDetector(onTap: tap, child:
            ColoredBox(color: on ? Color(0xFFCCE4F7) : Color(0x00000000), child:
                Padding(padding: EdgeInsets(left: 8, top: 3, right: 8, bottom: 3), child:
                    Text(text, style: fluent.typography.body))))
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let field = FieldDialog.fields[picked]
        var names: [Widget] = []
        for (i, f) in FieldDialog.fields.enumerated() {
            names.append(_row(f.name, on: i == picked, { [weak self] in self?.setState { self?.picked = i; self?.picture = 0 } }, fluent))
        }
        let pictures = field.name == "Date" ? Array(DateTimeDialog.pictures.prefix(7))
                     : field.name == "Time" ? Array(DateTimeDialog.pictures.suffix(4)) : []
        var right: [Widget] = [
            Text("Description:", style: fluent.typography.body),
            SizedBox(width: nil, height: 4),
            Text(field.about, style: fluent.typography.caption),
            SizedBox(width: nil, height: 10),
        ]
        if !pictures.isEmpty {
            right.append(Text("Date formats:", style: fluent.typography.body))
            right.append(SizedBox(width: nil, height: 4))
            for (i, p) in pictures.enumerated() {
                right.append(_row(_w.clock.format(picture: p, english: true) ?? p, on: i == picture,
                                  { [weak self] in self?.setState { self?.picture = i } }, fluent))
            }
            right.append(SizedBox(width: nil, height: 10))
        }
        right.append(Checkbox(checked: preserve, onChanged: { [weak self] v in self?.setState { self?.preserve = v ?? false } },
                              content: Text("Preserve formatting during updates", style: fluent.typography.body)))
        let code = FieldDialog.instruction(field.name, picture: pictures.isEmpty ? nil : pictures[picture], preserve: preserve)
        right.append(SizedBox(width: nil, height: 10))
        right.append(Text("Field code:" + code, style: fluent.typography.caption))
        let page: Widget = Row(crossAxisAlignment: .start, children: [
            SizedBox(width: 140, height: nil, child: Column(crossAxisAlignment: .stretch, children:
                [Text("Field names:", style: fluent.typography.body), SizedBox(width: nil, height: 4)] + names)),
            SizedBox(width: 16, height: nil),
            Expanded(child: Column(crossAxisAlignment: .start, children: right)),
        ])
        return DialogShell(title: "Field", page: page, okEnabled: true, width: 520,
                           onOK: { [weak self] in self?._w.onOK(code) },
                           onCancel: { [weak self] in self?._w.onCancel() })
    }
}
