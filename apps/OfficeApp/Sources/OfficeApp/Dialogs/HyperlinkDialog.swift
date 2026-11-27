// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Insert Hyperlink (U-LINK-1): one dialog for the three apps. An address, or
// a place in this file (Writer: bookmark or heading, Slides: a slide,
// Sheets: a cell or a name), the text to show and a screen tip. The app
// hands in the places and takes the result through `apply`, which makes it
// one undo step.

import Flutter
import FlutterSwiftBridge

/// A place in this file a link can point at.
struct HyperlinkPlace: Equatable {
    let id: String
    let title: String
    /// "Heading 2", "Bookmark", "Slide 3", "Cell"…
    let kind: String
}

struct HyperlinkHooks {
    /// Heading over the list: "Place in this document", "Slide", "Cell or name".
    var placesLabel = "Place in this document"
    var places: [HyperlinkPlace] = []
    /// Sheets and Slides may have no separate display text.
    var hasDisplayText = true
    var address = ""
    var displayText = ""
    var tip = ""
    /// The caret is on a link: shows Remove Link.
    var canRemove = false
    /// address (already made absolute), place id, text to show, tip. Returns "" when done, else a message.
    var apply: (String, String?, String, String) -> String
    var remove: () -> Void = {}
}

enum HyperlinkAddress {
    /// A bare host becomes https, a bare address mailto; a path, "#bookmark" and anything with a scheme stay.
    static func normalize(_ raw: String) -> String {
        let url = raw.trimmingWhitespace()
        if url.isEmpty || url.containsSubstring("://") || url.hasPrefix("mailto:") || url.hasPrefix("#") { return url }
        if url.containsSubstring("@") && !url.containsSubstring("/") && !url.containsSubstring(" ") { return "mailto:" + url }
        return "https://" + url
    }
}

final class HyperlinkDialog: StatefulWidget {
    let hooks: HyperlinkHooks
    let onClose: () -> Void
    init(hooks: HyperlinkHooks, onClose: @escaping () -> Void) {
        self.hooks = hooks
        self.onClose = onClose
        super.init()
    }
    override func createState() -> State<StatefulWidget> { HyperlinkDialogState() }
}

final class HyperlinkDialogState: State<StatefulWidget> {
    private var _w: HyperlinkDialog { widget as! HyperlinkDialog }
    private let _address = TextEditingController()
    private let _text = TextEditingController()
    private let _tip = TextEditingController()
    private(set) var place: String? = nil
    private(set) var status = ""

    override func initState() {
        super.initState()
        _address.text = _w.hooks.address
        _text.text = _w.hooks.displayText
        _tip.text = _w.hooks.tip
    }

    override func dispose() {
        _address.dispose(); _text.dispose(); _tip.dispose()
        super.dispose()
    }

    func ok() {
        let h = _w.hooks
        let typed = _address.text.trimmingWhitespace()
        if place == nil && typed.isEmpty { setState { status = "Type an address or pick a place" }; return }
        let addr = place == nil ? HyperlinkAddress.normalize(typed) : ""
        let err = h.apply(addr, place, _text.text, _tip.text)
        if err.isEmpty { _w.onClose() } else { setState { status = err } }
    }

    func pick(_ id: String?) {
        setState {
            place = id
            status = ""
            if id != nil { _address.text = "" }
        }
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let h = _w.hooks
        func label(_ t: String) -> Widget { SizedBox(width: 110, height: nil, child: Text(t, style: fluent.typography.body)) }
        func field(_ c: TextEditingController, _ key: String, autofocus: Bool = false) -> Widget {
            Expanded(child: SizedBox(width: nil, height: Chrome.fieldHeight, child: PKeyed(key, FluentTextBox(
                controller: c, onChanged: { [weak self] _ in if !c.text.isEmpty { self?.place = nil } },
                onSubmitted: { [weak self] _ in self?.ok() }, autofocus: autofocus))))
        }
        let gap = SizedBox(width: nil, height: 10, child: nil)
        var page: [Widget] = [
            Row(crossAxisAlignment: .center, children: [label("Address"), field(_address, "link-address", autofocus: true)]),
        ]
        if !h.places.isEmpty {
            page.append(gap)
            page.append(Text(h.placesLabel, style: fluent.typography.bodyStrong))
            page.append(SizedBox(width: nil, height: 4, child: nil))
            var rows: [Widget] = []
            for p in h.places {
                let on = place == p.id
                rows.append(PKeyed("link-place-\(p.id)", Button(onPressed: { [weak self] in self?.pick(on ? nil : p.id) },
                    child: Text((on ? "● " : "") + p.title + "  (" + p.kind + ")", style: fluent.typography.body))))
            }
            page.append(SizedBox(width: nil, height: 140, child: SingleChildScrollView(
                child: Column(crossAxisAlignment: .start, children: rows))))
        }
        if h.hasDisplayText {
            page.append(gap)
            page.append(Row(crossAxisAlignment: .center, children: [label("Text to display"), field(_text, "link-text")]))
        }
        page.append(gap)
        page.append(Row(crossAxisAlignment: .center, children: [label("Screen tip"), field(_tip, "link-tip")]))
        if h.canRemove {
            page.append(gap)
            page.append(Button(onPressed: { [weak self] in self?._w.hooks.remove(); self?._w.onClose() },
                               child: Text("Remove Link")))
        }
        if !status.isEmpty {
            page.append(gap)
            page.append(Text(status, style: fluent.typography.body?.copyWith(color: fluent.resources.textFillColorSecondary)))
        }
        return DialogShell(title: "Insert Hyperlink", page: Column(crossAxisAlignment: .stretch, children: page),
                           okLabel: "OK", cancelLabel: "Cancel", width: 520,
                           onOK: { [weak self] in self?.ok() }, onCancel: { [weak self] in self?._w.onClose() })
    }
}
