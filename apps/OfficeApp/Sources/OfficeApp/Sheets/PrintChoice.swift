// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Print what: the active sheet, the entire workbook, or the selection.
import Flutter
import FlutterSwiftBridge

enum PrintWhat: Equatable {
    case activeSheet, entireWorkbook, selection
    var label: String {
        switch self {
        case .activeSheet: return "Active sheet"
        case .entireWorkbook: return "Entire workbook"
        case .selection: return "Selection"
        }
    }
}

final class PrintChoicePanel: StatefulWidget {
    let sheetName: String
    let selectionText: String
    let onPrint: (PrintWhat) -> Void
    let onClose: () -> Void
    init(sheetName: String, selectionText: String, onPrint: @escaping (PrintWhat) -> Void, onClose: @escaping () -> Void) {
        self.sheetName = sheetName; self.selectionText = selectionText
        self.onPrint = onPrint; self.onClose = onClose
        super.init()
    }
    override func createState() -> State<StatefulWidget> { PrintChoicePanelState() }
}

final class PrintChoicePanelState: State<StatefulWidget> {
    private var _w: PrintChoicePanel { widget as! PrintChoicePanel }
    var what: PrintWhat = .activeSheet

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        func line(_ w: PrintWhat, _ detail: String) -> Widget {
            Padding(padding: EdgeInsets(left: 0, top: 3, right: 0, bottom: 3), child: Checkbox(
                key: ValueKey("print-\(w == .activeSheet ? "sheet" : w == .entireWorkbook ? "book" : "selection")"),
                checked: what == w, onChanged: { [weak self] _ in self?.setState { self?.what = w } },
                content: Text("\(w.label) (\(detail))")))
        }
        let content = Padding(padding: EdgeInsets(left: 16, top: 8, right: 16, bottom: 8), child: Column(
            mainAxisSize: .min, crossAxisAlignment: .start, children: [
                Text("Print what", style: fluent.typography.bodyStrong),
                line(.activeSheet, _w.sheetName),
                line(.entireWorkbook, "every visible sheet"),
                line(.selection, _w.selectionText),
            ]))
        return DialogShell(title: "Print Options", page: content, okLabel: "Print", width: 420,
                           onOK: { [weak self] in guard let self else { return }; self._w.onPrint(self.what); self._w.onClose() },
                           onCancel: _w.onClose)
    }
}
