// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// W-FD-2: Custom Table of Contents. Levels shown, the tab leader, right-aligned numbers, hyperlinks.

import Flutter
import FlutterSwiftBridge
import OfficeText

private final class TocKeyed: StatelessWidget {
    let child: Widget
    init(_ id: String, _ child: Widget) { self.child = child; super.init(key: ValueKey(id)) }
    override func build(_ context: any BuildContext) -> Widget { child }
}

final class ContentsDialog: StatefulWidget {
    let onOK: (ContentsOptions) -> Void
    let onCancel: () -> Void
    init(onOK: @escaping (ContentsOptions) -> Void, onCancel: @escaping () -> Void) {
        self.onOK = onOK; self.onCancel = onCancel
        super.init()
    }
    override func createState() -> State<StatefulWidget> { ContentsDialogState() }
}

final class ContentsDialogState: State<StatefulWidget> {
    private var _w: ContentsDialog { widget as! ContentsDialog }
    private(set) var options = ContentsOptions()
    private let _levels = TextEditingController()

    override func initState() {
        super.initState()
        _levels.text = String(options.levels)
    }

    func commit() {
        if let n = Int(_levels.text.trimmingWhitespace(newlines: true)) { options.levels = max(1, min(9, n)) }
        _levels.text = String(options.levels)
    }

    override func build(_ context: any BuildContext) -> Widget {
        func check(_ label: String, _ on: Bool, _ set: @escaping (inout ContentsOptions, Bool) -> Void) -> Widget {
            Padding(padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 6), child: Row(crossAxisAlignment: .center, children: [
                Checkbox(checked: on, onChanged: { [weak self] v in self?.setState { if let self { set(&self.options, v ?? false) } } },
                         content: Text(label)),
            ]))
        }
        let leaders: [(String, String?)] = [("(none)", nil), ("......", "dot"), ("------", "hyphen"), ("______", "underscore")]
        let page = Column(crossAxisAlignment: .start, children: [
            check("Show page numbers", options.showPageNumbers) { $0.showPageNumbers = $1 },
            check("Right align page numbers", options.rightAlignNumbers) { $0.rightAlignNumbers = $1 },
            check("Use hyperlinks", options.hyperlinks) { $0.hyperlinks = $1 },
            Padding(padding: EdgeInsets(left: 0, top: 4, right: 0, bottom: 8), child: Row(crossAxisAlignment: .center, children: [
                SizedBox(width: 130, height: nil, child: Text("Show levels")),
                SizedBox(width: 70, height: Chrome.fieldHeight, child: TocKeyed("toc-levels", FluentTextBox(
                    controller: _levels, onSubmitted: { [weak self] _ in self?.commit() },
                    onFocusChanged: { [weak self] f in if !f { self?.commit() } }))),
            ])),
            Text("Tab leader"),
            Row(crossAxisAlignment: .center, children: leaders.map { name, value in
                Padding(padding: EdgeInsets(left: 0, top: 4, right: 12, bottom: 0), child: Checkbox(
                    checked: options.tabLeader == value,
                    onChanged: { [weak self] v in if v == true { self?.setState { self?.options.tabLeader = value } } },
                    content: Text(name)))
            }),
        ])
        return DialogShell(title: "Table of Contents", page: page, width: 460,
                           onOK: { [weak self] in guard let self else { return }; self.commit(); self._w.onOK(self.options) },
                           onCancel: { [weak self] in self?._w.onCancel() })
    }
}
