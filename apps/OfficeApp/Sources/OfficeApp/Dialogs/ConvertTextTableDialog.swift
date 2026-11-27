// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// W-TB-9: Convert Text to Table and Convert Table to Text. What separates the pieces, and for the paragraph
// separator how many columns the table gets.

import Flutter
import FlutterSwiftBridge
import OfficeText

struct ConvertTextTableValues: Equatable {
    enum Kind: Equatable { case paragraph, tab, comma, other }
    var kind: Kind = .tab
    var other = "-"
    var columns = 2

    /// The separator the controller takes; an empty "other" box reads as a hyphen, as in Word's default.
    var separator: RichDocumentController.TextTableSeparator {
        switch kind {
        case .paragraph: return .paragraph
        case .tab: return .tab
        case .comma: return .comma
        case .other: return .other(other.first ?? "-")
        }
    }
}

final class ConvertTextTableDialog: StatefulWidget {
    let toTable: Bool
    let initial: ConvertTextTableValues
    let onOK: (ConvertTextTableValues) -> Void
    let onCancel: () -> Void
    init(toTable: Bool, initial: ConvertTextTableValues = ConvertTextTableValues(),
         onOK: @escaping (ConvertTextTableValues) -> Void, onCancel: @escaping () -> Void) {
        self.toTable = toTable; self.initial = initial; self.onOK = onOK; self.onCancel = onCancel
        super.init()
    }
    override func createState() -> State<StatefulWidget> { ConvertTextTableDialogState() }
}

final class ConvertTextTableDialogState: State<StatefulWidget> {
    private var _w: ConvertTextTableDialog { widget as! ConvertTextTableDialog }
    private(set) var v = ConvertTextTableValues()
    private let _columns = TextEditingController()
    private let _other = TextEditingController()

    override func initState() {
        super.initState()
        v = _w.initial
        _columns.text = String(v.columns)
        _other.text = v.other
    }

    func commit() {
        if let n = InsertTableValues.clamp(_columns.text, InsertTableValues.maxColumns) { v.columns = n }
        _columns.text = String(v.columns)
        v.other = String(_other.text.prefix(1))
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        func choice(_ id: String, _ label: String, _ k: ConvertTextTableValues.Kind) -> Widget {
            PKeyed(id, Chrome.textToggle(label, v.kind == k, fluent, action: { [weak self] in self?.setState { self?.v.kind = k } }))
        }
        func box(_ id: String, _ label: String, _ c: TextEditingController, width: Double) -> Widget {
            Padding(padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 8), child: Row(crossAxisAlignment: .center, children: [
                SizedBox(width: 130, height: nil, child: Text(label)),
                PKeyed(id, SizedBox(width: width, height: Chrome.fieldHeight, child: FluentTextBox(
                    controller: c, onSubmitted: { [weak self] _ in self?.commit() },
                    onFocusChanged: { [weak self] f in if !f { self?.commit() } }))),
            ]))
        }
        var children: [Widget] = [
            Padding(padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 8), child: Text(
                _w.toTable ? "Separate text at" : "Separate text with")),
            choice("ct-paragraph", "Paragraph marks", .paragraph),
            choice("ct-tab", "Tabs", .tab),
            choice("ct-comma", "Commas", .comma),
            choice("ct-other", "Other", .other),
        ]
        if v.kind == .other { children.append(box("ct-other-box", "Other character", _other, width: 50)) }
        if _w.toTable, v.kind == .paragraph { children.append(box("ct-columns", "Number of columns", _columns, width: 70)) }
        return DialogShell(title: _w.toTable ? "Convert Text to Table" : "Convert Table to Text",
                           page: Column(crossAxisAlignment: .start, children: children), width: 400,
                           onOK: { [weak self] in guard let self else { return }; self.commit(); self._w.onOK(self.v) },
                           onCancel: { [weak self] in self?._w.onCancel() })
    }
}
