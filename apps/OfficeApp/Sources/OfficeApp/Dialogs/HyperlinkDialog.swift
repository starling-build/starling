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
    /// The place the link already points at (editing a link), picked when the dialog opens.
    var place: String? = nil
    /// An E-mail Address and Subject pair under the address (Slides): makes "mailto:address?subject=...".
    var hasEmail = false
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

    /// "mailto:" + the address, with "?subject=" when one is given; the subject percent-encoded (UTF-8), as PowerPoint writes it.
    static func mail(_ address: String, subject: String) -> String {
        let to = address.trimmingWhitespace()
        if to.isEmpty { return "" }
        let base = to.hasPrefix("mailto:") ? to : "mailto:" + to
        let sub = subject.trimmingWhitespace()
        return sub.isEmpty ? base : base + "?subject=" + percentEncode(sub)
    }

    /// A mailto link split back into its address and subject (nil when it is not a mailto link).
    static func splitMail(_ link: String) -> (address: String, subject: String)? {
        guard link.lowercased().hasPrefix("mailto:") else { return nil }
        let rest = String(link.dropFirst(7))
        guard let q = rest.firstIndex(of: "?") else { return (rest, "") }
        var subject = ""
        for pair in rest[rest.index(after: q)...].split(separator: "&") where pair.lowercased().hasPrefix("subject=") {
            subject = percentDecode(String(pair.dropFirst(8)))
        }
        return (String(rest[..<q]), subject)
    }

    static func percentEncode(_ s: String) -> String {
        let hex = Array("0123456789ABCDEF")
        var out = ""
        for b in s.utf8 {
            switch b {
            case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x2D, 0x2E, 0x5F, 0x7E: out.append(Character(UnicodeScalar(b)))
            default: out.append("%"); out.append(hex[Int(b >> 4)]); out.append(hex[Int(b & 15)])
            }
        }
        return out
    }

    static func percentDecode(_ s: String) -> String {
        var bytes: [UInt8] = []
        let u = Array(s.utf8)
        var i = 0
        func val(_ c: UInt8) -> UInt8? {
            switch c { case 0x30...0x39: return c - 0x30; case 0x41...0x46: return c - 0x37; case 0x61...0x66: return c - 0x57; default: return nil }
        }
        while i < u.count {
            if u[i] == 0x25, i + 2 < u.count, let h = val(u[i + 1]), let l = val(u[i + 2]) { bytes.append(h << 4 | l); i += 3 }
            else if u[i] == 0x2B { bytes.append(0x20); i += 1 }
            else { bytes.append(u[i]); i += 1 }
        }
        return String(decoding: bytes, as: UTF8.self)
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
    private let _mail = TextEditingController()
    private let _subject = TextEditingController()
    private(set) var place: String? = nil
    private(set) var status = ""

    override func initState() {
        super.initState()
        let h = _w.hooks
        if h.hasEmail, let m = HyperlinkAddress.splitMail(h.address) {
            _mail.text = m.address; _subject.text = m.subject
        } else {
            _address.text = h.address
        }
        _text.text = h.displayText
        _tip.text = h.tip
        place = h.place
    }

    override func dispose() {
        _address.dispose(); _text.dispose(); _tip.dispose(); _mail.dispose(); _subject.dispose()
        super.dispose()
    }

    func ok() {
        let h = _w.hooks
        let typed = _address.text.trimmingWhitespace()
        let mail = h.hasEmail && typed.isEmpty ? HyperlinkAddress.mail(_mail.text, subject: _subject.text) : ""
        if place == nil && typed.isEmpty && mail.isEmpty {
            setState { status = h.hasEmail ? "Type an address, pick a place or type an e-mail address" : "Type an address or pick a place" }
            return
        }
        let addr = place != nil ? "" : mail.isEmpty ? HyperlinkAddress.normalize(typed) : mail
        let err = h.apply(addr, place, _text.text, _tip.text)
        if err.isEmpty { _w.onClose() } else { setState { status = err } }
    }

    func pick(_ id: String?) {
        setState {
            place = id
            status = ""
            if id != nil { _address.text = ""; _mail.text = "" }
        }
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let h = _w.hooks
        func label(_ t: String) -> Widget { SizedBox(width: 110, height: nil, child: Text(t, style: fluent.typography.body)) }
        func field(_ c: TextEditingController, _ key: String, autofocus: Bool = false, clearsPlace: Bool = true) -> Widget {
            Expanded(child: SizedBox(width: nil, height: Chrome.fieldHeight, child: PKeyed(key, FluentTextBox(
                controller: c, onChanged: { [weak self] _ in if clearsPlace, !c.text.isEmpty { self?.setState { self?.place = nil } } },
                onSubmitted: { [weak self] _ in self?.ok() }, autofocus: autofocus))))
        }
        let gap = SizedBox(width: nil, height: 10, child: nil)
        var page: [Widget] = [
            Row(crossAxisAlignment: .center, children: [label("Address"), field(_address, "link-address", autofocus: true)]),
        ]
        if h.hasEmail {
            page.append(gap)
            page.append(Row(crossAxisAlignment: .center, children: [label("E-mail address"), field(_mail, "link-mail")]))
            page.append(SizedBox(width: nil, height: 4, child: nil))
            page.append(Row(crossAxisAlignment: .center, children: [label("Subject"), field(_subject, "link-subject", clearsPlace: false)]))
        }
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
            // Tall enough for the four jumps and three slides of a small deck (Slides) without scrolling.
            page.append(SizedBox(width: nil, height: h.hasEmail ? 200 : 140, child: SingleChildScrollView(
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
        return DialogShell(title: h.canRemove ? "Edit Hyperlink" : "Insert Hyperlink", page: Column(crossAxisAlignment: .stretch, children: page),
                           okLabel: "OK", cancelLabel: "Cancel", width: 520,
                           onOK: { [weak self] in self?.ok() }, onCancel: { [weak self] in self?._w.onClose() })
    }
}
