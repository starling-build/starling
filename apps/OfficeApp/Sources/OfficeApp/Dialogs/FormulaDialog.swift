// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// W-TB-6: Layout > Formula in a table cell. The formula, a number format, and the result it would show.

import Flutter
import FlutterSwiftBridge
import OfficeText

final class FormulaDialog: StatefulWidget {
    let formula: String
    let preview: (String, String) -> String?
    let onOK: (String, String) -> Void
    let onCancel: () -> Void
    init(formula: String, preview: @escaping (String, String) -> String?,
         onOK: @escaping (String, String) -> Void, onCancel: @escaping () -> Void) {
        self.formula = formula; self.preview = preview; self.onOK = onOK; self.onCancel = onCancel
        super.init()
    }
    override func createState() -> State<StatefulWidget> { FormulaDialogState() }
}

final class FormulaDialogState: State<StatefulWidget> {
    private var _w: FormulaDialog { widget as! FormulaDialog }
    private let _formula = TextEditingController()
    private let _picture = TextEditingController()
    static let pictures = ["", "0", "0.00", "#,##0", "#,##0.00", "$#,##0.00;($#,##0.00)", "0%", "0.00%"]

    override func initState() {
        super.initState()
        _formula.text = _w.formula
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        func box(_ id: String, _ label: String, _ c: TextEditingController, width: Double) -> Widget {
            Padding(padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 8), child: Row(crossAxisAlignment: .center, children: [
                SizedBox(width: 110, height: nil, child: Text(label)),
                PKeyed(id, SizedBox(width: width, height: Chrome.fieldHeight, child: FluentTextBox(
                    controller: c, onChanged: { [weak self] _ in self?.setState {} }))),
            ]))
        }
        let shown = _w.preview(_formula.text, _picture.text)
        let pictures: [Widget] = Self.pictures.map { p in
            PKeyed("fm-pic-\(p)", Chrome.textToggle(p.isEmpty ? "(general)" : p, _picture.text == p, fluent,
                                                    action: { [weak self] in self?.setState { self?._picture.text = p } }))
        }
        return DialogShell(title: "Formula", page: Column(crossAxisAlignment: .start, children: [
            box("fm-formula", "Formula", _formula, width: 260),
            box("fm-picture", "Number format", _picture, width: 260),
            Padding(padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 8), child: Text("Common formats")),
            Column(crossAxisAlignment: .start, children: pictures),
            Padding(padding: EdgeInsets(left: 0, top: 8, right: 0, bottom: 0), child: PKeyed("fm-result", Text(
                shown.map { "Result: \($0)" } ?? "This formula cannot be worked out here."))),
        ]), width: 420,
        onOK: { [weak self] in
            guard let self, self._w.preview(self._formula.text, self._picture.text) != nil else { return }
            self._w.onOK(self._formula.text, self._picture.text)
        },
        onCancel: { [weak self] in self?._w.onCancel() })
    }
}
