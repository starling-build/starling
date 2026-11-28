// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// W-FD-3: Insert > Bookmark (Ctrl+Shift+F5). A name box, the document's bookmarks sorted by name or by location,
// "Hidden bookmarks", and Add (bookmark the selection and close), Delete and Go To, as in Word.

import Flutter
import FlutterSwiftBridge
import OfficeText

final class BookmarkDialog: StatefulWidget {
    let controller: RichDocumentController
    let onClose: () -> Void

    init(controller: RichDocumentController, onClose: @escaping () -> Void) {
        self.controller = controller; self.onClose = onClose
        super.init()
    }
    override func createState() -> State<StatefulWidget> { BookmarkDialogState() }
}

final class BookmarkDialogState: State<StatefulWidget> {
    private var _w: BookmarkDialog { widget as! BookmarkDialog }
    let name = TextEditingController()
    private(set) var byLocation = false
    private(set) var hidden = false

    /// The list as shown: by name (case ignored) or by where each starts.
    var shown: [RichDocumentController.BookmarkEntry] {
        let all = _w.controller.bookmarkEntries().filter { hidden || !$0.hidden }
        return byLocation ? all : all.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    private var _picked: RichDocumentController.BookmarkEntry? {
        let key = name.text.lowercased()
        return shown.first { $0.name.lowercased() == key }
    }

    func add() {
        guard RichDocumentController.isValidBookmarkName(name.text), _w.controller.addBookmark(name.text) else { return }
        _w.onClose()
    }

    func delete() {
        guard let b = _picked else { return }
        _w.controller.deleteBookmark(b.name)
        setState { name.text = "" }
    }

    func goTo() {
        guard let b = _picked else { return }
        _w.controller.goToBookmark(b.name)
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let picked = _picked
        var rows: [Widget] = []
        for b in shown {
            let on = b.name == picked?.name
            rows.append(PKeyed("bm-item-\(b.name)", GestureDetector(onTap: { [weak self] in self?.setState { self?.name.text = b.name } }, child:
                ColoredBox(color: on ? Color(0xFFCCE4F7) : Color(0x00000000), child:
                    Padding(padding: EdgeInsets(left: 8, top: 3, right: 8, bottom: 3), child:
                        Text(b.name, style: fluent.typography.body))))))
        }
        let valid = RichDocumentController.isValidBookmarkName(name.text)
        let page: Widget = Column(crossAxisAlignment: .stretch, children: [
            Text("Bookmark name:", style: fluent.typography.body),
            SizedBox(width: nil, height: 4),
            PKeyed("bm-name", SizedBox(width: nil, height: Chrome.fieldHeight, child: FluentTextBox(
                controller: name, onChanged: { [weak self] _ in self?.setState {} }))),
            SizedBox(width: nil, height: 6),
            SizedBox(width: nil, height: 180, child: SingleChildScrollView(child: Column(crossAxisAlignment: .stretch, children: rows))),
            SizedBox(width: nil, height: 8),
            Row(children: [
                Text("Sort by:  ", style: fluent.typography.body),
                PKeyed("bm-sort-name", Checkbox(checked: !byLocation, onChanged: { [weak self] _ in self?.setState { self?.byLocation = false } },
                                                content: Text("Name", style: fluent.typography.body))),
                SizedBox(width: 12, height: nil),
                PKeyed("bm-sort-location", Checkbox(checked: byLocation, onChanged: { [weak self] _ in self?.setState { self?.byLocation = true } },
                                                    content: Text("Location", style: fluent.typography.body))),
            ]),
            SizedBox(width: nil, height: 6),
            PKeyed("bm-hidden", Checkbox(checked: hidden, onChanged: { [weak self] v in self?.setState { self?.hidden = v ?? false } },
                                         content: Text("Hidden bookmarks", style: fluent.typography.body))),
            SizedBox(width: nil, height: 10),
            Row(children: [
                PKeyed("bm-delete", Button(onPressed: picked == nil ? nil : { [weak self] in self?.delete() }, child: Text("Delete"))),
                SizedBox(width: 8, height: nil),
                PKeyed("bm-goto", Button(onPressed: picked == nil ? nil : { [weak self] in self?.goTo() }, child: Text("Go To"))),
            ]),
        ])
        return DialogShell(title: "Bookmark", page: page, okLabel: "Add", cancelLabel: "Close", okEnabled: valid, width: 380,
                           onOK: { [weak self] in self?.add() },
                           onCancel: { [weak self] in self?._w.onClose() })
    }
}
