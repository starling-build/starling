// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-LK-1: Insert Hyperlink (Ctrl+K), on the shared dialog.
import Flutter
import FlutterSwiftBridge

/// What a typed address means: a place in the workbook, a mail address, or a web address.
enum HyperlinkInput {
    static func link(_ text: String, place: Bool) -> SheetLink? {
        let t = text.trimmingWhitespace()
        guard !t.isEmpty else { return nil }
        if place { return .place(t) }
        if t.containsSubstring("://") || t.hasPrefix("mailto:") || t.hasPrefix("tel:") { return .url(t) }
        if t.containsSubstring("@"), !t.containsSubstring("/") { return .url("mailto:" + t) }
        return .url("https://" + t)
    }
    /// The text of a link, to put back in the field when editing.
    static func text(_ link: SheetLink?) -> (text: String, place: Bool) {
        switch link {
        case .url(let u)?: return (u, false)
        case .place(let p)?: return (p, true)
        case nil: return ("", false)
        }
    }
}

final class HyperlinkPanel: StatefulWidget {
    let current: SheetLink?
    let onDone: (SheetLink, _ tip: String?) -> Void
    let onRemove: (() -> Void)?
    let onClose: () -> Void
    init(current: SheetLink?, onDone: @escaping (SheetLink, String?) -> Void, onRemove: (() -> Void)?, onClose: @escaping () -> Void) {
        self.current = current; self.onDone = onDone; self.onRemove = onRemove; self.onClose = onClose
        super.init()
    }
    override func createState() -> State<StatefulWidget> { HyperlinkPanelState() }
}

final class HyperlinkPanelState: State<StatefulWidget> {
    private var _w: HyperlinkPanel { widget as! HyperlinkPanel }
    private let _address = TextEditingController()
    private let _tip = TextEditingController()
    var place = false
    private var _seeded = false

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        if !_seeded {
            _seeded = true
            let c = HyperlinkInput.text(_w.current)
            _address.text = c.text; place = c.place
        }
        func kind(_ id: String, _ label: String, _ isPlace: Bool) -> Widget {
            SizedBox(key: ValueKey(id), width: nil, height: 28, child: FlatButton(
                child: Padding(padding: EdgeInsets(left: 8, top: 0, right: 8, bottom: 0), child: Text(label)),
                checked: place == isPlace, width: nil, height: 28, alignLeft: true,
                action: { [weak self] in self?.setState { self?.place = isPlace } }))
        }
        var kids: [Widget] = [
            Text(_w.current == nil ? "Insert Hyperlink" : "Edit Hyperlink", style: fluent.typography.bodyStrong),
            kind("link-web", "Existing file or web page, e-mail address", false),
            kind("link-place", "Place in this document (for example Sheet2!A1)", true),
            Text(place ? "Cell reference or name:" : "Address:"),
            SizedBox(key: ValueKey("link-address"), width: nil, height: 30, child: FluentTextBox(controller: _address, onChanged: { _ in })),
            Text("ScreenTip (optional):"),
            SizedBox(key: ValueKey("link-tip"), width: nil, height: 30, child: FluentTextBox(controller: _tip, onChanged: { _ in })),
        ]
        if let remove = _w.onRemove {
            kids.append(SizedBox(key: ValueKey("link-remove"), width: nil, height: 28, child: FlatButton(
                child: Padding(padding: EdgeInsets(left: 8, top: 0, right: 8, bottom: 0), child: Text("Remove Link")),
                checked: false, width: nil, height: 28, alignLeft: true, action: { [weak self] in remove(); self?._w.onClose() })))
        }
        let content = Padding(padding: EdgeInsets(left: 16, top: 8, right: 16, bottom: 8),
                              child: Column(mainAxisSize: .min, crossAxisAlignment: .start, children: kids))
        return DialogShell(title: "Hyperlink", page: content, width: 420,
                           onOK: { [weak self] in
                               guard let self, let link = HyperlinkInput.link(self._address.text, place: self.place) else { return }
                               self._w.onDone(link, self._tip.text.isEmpty ? nil : self._tip.text)
                               self._w.onClose()
                           },
                           onCancel: _w.onClose)
    }
}
