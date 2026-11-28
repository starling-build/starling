// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// W-FD-3: Insert > Cross-reference. Reference type (Heading, Bookmark, Footnote, Endnote, a caption label), what to
// insert (its text, page number, number, "above"/"below"), "Insert as hyperlink", and the item. Insert puts a REF,
// PAGEREF or NOTEREF field at the caret showing its result now; F9 brings it up to date later.

import Flutter
import FlutterSwiftBridge
import OfficeText

final class CrossReferenceDialog: StatefulWidget {
    let controller: RichDocumentController
    /// The page label of a body paragraph, and the page count (from the shell's layout).
    let pageOf: (Int) -> String?
    let pageCount: Int
    let onDone: (_ inserted: Bool) -> Void

    init(controller: RichDocumentController, pageOf: @escaping (Int) -> String?, pageCount: Int, onDone: @escaping (Bool) -> Void) {
        self.controller = controller; self.pageOf = pageOf; self.pageCount = pageCount; self.onDone = onDone
        super.init()
    }
    override func createState() -> State<StatefulWidget> { CrossReferenceDialogState() }
}

final class CrossReferenceDialogState: State<StatefulWidget> {
    typealias C = RichDocumentController
    private var _w: CrossReferenceDialog { widget as! CrossReferenceDialog }
    private(set) var types: [C.CrossReferenceType] = []
    private(set) var type: C.CrossReferenceType = .heading
    private(set) var kind: C.CrossReferenceKind = .text
    private(set) var items: [C.CrossReferenceItem] = []
    private(set) var picked = 0
    private(set) var link = true

    override func initState() {
        super.initState()
        types = _w.controller.crossReferenceTypes()
        pick(.heading)
    }

    func pick(_ t: C.CrossReferenceType) {
        type = t
        if !t.kinds.contains(kind) { kind = t.kinds[0] }
        items = _w.controller.crossReferenceItems(t)
        picked = 0
    }

    func insert() {
        guard picked < items.count else { return }
        let ok = _w.controller.insertCrossReference(type, kind, items[picked], link: link, pageOf: _w.pageOf, pageCount: _w.pageCount)
        _w.onDone(ok)
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let typeRow: [Widget] = types.map { t in
            PKeyed("xr-type-\(t.title)", Chrome.textToggle(t.title, t == type, fluent, action: { [weak self] in self?.setState { self?.pick(t) } }))
        }
        let kindRow: [Widget] = type.kinds.map { k in
            PKeyed("xr-kind-\(k.title(type))", Chrome.textToggle(k.title(type), k == kind, fluent,
                                                              action: { [weak self] in self?.setState { self?.kind = k } }))
        }
        var rows: [Widget] = []
        for (i, item) in items.enumerated() {
            rows.append(PKeyed("xr-item-\(i)", GestureDetector(onTap: { [weak self] in self?.setState { self?.picked = i } }, child:
                ColoredBox(color: i == picked ? Color(0xFFCCE4F7) : Color(0x00000000), child:
                    Padding(padding: EdgeInsets(left: 8, top: 3, right: 8, bottom: 3), child:
                        Text(item.title, style: fluent.typography.body, maxLines: 1))))))
        }
        if rows.isEmpty { rows.append(Text("(none in this document)", style: fluent.typography.caption)) }
        let page: Widget = Column(crossAxisAlignment: .stretch, children: [
            Text("Reference type:", style: fluent.typography.body),
            SizedBox(width: nil, height: 4),
            Wrap(spacing: 6, runSpacing: 6, children: typeRow),
            SizedBox(width: nil, height: 10),
            Text("Insert reference to:", style: fluent.typography.body),
            SizedBox(width: nil, height: 4),
            Wrap(spacing: 6, runSpacing: 6, children: kindRow),
            SizedBox(width: nil, height: 10),
            PKeyed("xr-link", Checkbox(checked: link, onChanged: { [weak self] v in self?.setState { self?.link = v ?? false } },
                                       content: Text("Insert as hyperlink", style: fluent.typography.body))),
            SizedBox(width: nil, height: 10),
            Text("For which \(type.title.lowercased()):", style: fluent.typography.body),
            SizedBox(width: nil, height: 4),
            SizedBox(width: nil, height: 180, child: SingleChildScrollView(child: Column(crossAxisAlignment: .stretch, children: rows))),
        ])
        return DialogShell(title: "Cross-reference", page: page, okLabel: "Insert", cancelLabel: "Close",
                           okEnabled: picked < items.count, width: 520,
                           onOK: { [weak self] in self?.insert() },
                           onCancel: { [weak self] in self?._w.onDone(false) })
    }
}
