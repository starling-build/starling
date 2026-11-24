// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-PR-1: the Page Setup dialog. `PageSetupForm` holds what the boxes show
// (text, as typed) and turns it into one `PageSetupChange`; a box holding
// something that is not a number is reported, never silently dropped.

import Flutter
import OfficeText
import FlutterSwiftBridge
import FluentSystemIcons
import Foundation

struct PageSetupForm {
    static let papers: [(Int, String)] = [
        (1, "Letter"), (5, "Legal"), (3, "Tabloid"), (7, "Executive"),
        (8, "A3"), (9, "A4"), (11, "A5"), (13, "B5 (JIS)"),
    ]
    var landscape: Bool
    var paper: Int
    var fit: Bool
    var scale: String, wide: String, tall: String
    var left: String, right: String, top: String, bottom: String, header: String, footer: String
    var centerH: Bool, centerV: Bool, gridlines: Bool, headings: Bool, overThenDown: Bool

    /// The boxes as the sheet has them now.
    init(_ s: SheetPrintSetup, paper number: Int) {
        func inch(_ pt: Double) -> String { Self.text((pt / 72 * 100).rounded() / 100) }
        landscape = s.landscape; paper = number
        fit = s.fitWidth != nil || s.fitHeight != nil
        scale = Self.text(s.scale.rounded())
        wide = String(s.fitWidth ?? 1); tall = String(s.fitHeight ?? 1)
        left = inch(s.left); right = inch(s.right); top = inch(s.top); bottom = inch(s.bottom)
        header = inch(s.headerMargin); footer = inch(s.footerMargin)
        centerH = s.centerHorizontally; centerV = s.centerVertically
        gridlines = s.gridlines; headings = s.headings; overThenDown = s.overThenDown
    }

    static func text(_ d: Double) -> String { d == d.rounded() ? String(Int(d)) : String(d) }

    /// The change to apply, or the message to show.
    func change() -> (PageSetupChange?, String?) {
        func inches(_ s: String, _ what: String) -> Double? {
            guard let v = Double(s.trimmingSpaces()), v >= 0, v <= 20 else { return nil }
            return v
        }
        var c = PageSetupChange()
        c.landscape = landscape; c.paperSize = paper
        if fit {
            guard let w = Int(wide.trimmingSpaces()), w >= 0, w <= 999 else { return (nil, "Pages wide must be a whole number") }
            guard let t = Int(tall.trimmingSpaces()), t >= 0, t <= 999 else { return (nil, "Pages tall must be a whole number") }
            c.fitWide = w; c.fitTall = t
        } else {
            guard let p = Int(scale.trimmingSpaces()), p >= 10, p <= 400 else { return (nil, "Scale must be between 10 and 400 percent") }
            c.scale = p
        }
        let named: [(String, String)] = [("Left", left), ("Right", right), ("Top", top), ("Bottom", bottom), ("Header", header), ("Footer", footer)]
        var v: [Double] = []
        for (n, s) in named {
            guard let d = inches(s, n) else { return (nil, "\(n) margin must be a number of inches") }
            v.append(d)
        }
        c.left = v[0]; c.right = v[1]; c.top = v[2]; c.bottom = v[3]; c.header = v[4]; c.footer = v[5]
        c.centerHorizontally = centerH; c.centerVertically = centerV
        c.gridlines = gridlines; c.headings = headings; c.overThenDown = overThenDown
        return (c, nil)
    }
}

/// The dialog's content: three groups of boxes (Page, Margins, Sheet) and OK/Cancel.
final class PageSetupPanel: StatefulWidget {
    let form: PageSetupForm
    let onApply: (PageSetupChange) -> Void
    let onClose: () -> Void
    init(form: PageSetupForm, onApply: @escaping (PageSetupChange) -> Void, onClose: @escaping () -> Void) {
        self.form = form; self.onApply = onApply; self.onClose = onClose
        super.init()
    }
    override func createState() -> State<StatefulWidget> { PageSetupPanelState() }
}

final class PageSetupPanelState: State<StatefulWidget> {
    private var _w: PageSetupPanel { widget as! PageSetupPanel }
    var form: PageSetupForm!
    var message = ""
    var boxes: [String: TextEditingController] = [:]

    override func initState() {
        super.initState()
        form = _w.form
        for (k, v) in [("scale", form.scale), ("wide", form.wide), ("tall", form.tall), ("left", form.left), ("right", form.right),
                       ("top", form.top), ("bottom", form.bottom), ("header", form.header), ("footer", form.footer)] {
            boxes[k] = TextEditingController(text: v)
        }
    }

    func apply() {
        func t(_ k: String) -> String { boxes[k]?.text ?? "" }
        form.scale = t("scale"); form.wide = t("wide"); form.tall = t("tall")
        form.left = t("left"); form.right = t("right"); form.top = t("top"); form.bottom = t("bottom")
        form.header = t("header"); form.footer = t("footer")
        let (c, err) = form.change()
        if let c { _w.onApply(c); _w.onClose() } else { setState { message = err ?? "" } }
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        func box(_ k: String, _ label: String) -> Widget {
            Padding(padding: EdgeInsets(left: 0, top: 3, right: 12, bottom: 3), child: Row(children: [
                SizedBox(width: 70, height: nil, child: Text(label, style: fluent.typography.body)),
                SizedBox(width: 70, height: 30, child: FluentTextBox(key: ValueKey("pagesetup-\(k)"), controller: boxes[k]!,
                                                                    onSubmitted: { [weak self] _ in self?.apply() })),
            ]))
        }
        func check(_ k: String, _ label: String, _ on: Bool, _ set: @escaping (Bool) -> Void) -> Widget {
            Padding(padding: EdgeInsets(left: 0, top: 3, right: 0, bottom: 3), child: Checkbox(
                key: ValueKey("pagesetup-\(k)"), checked: on, onChanged: { [weak self] v in self?.setState { set(v ?? false) } },
                content: Text(label)))
        }
        func heading(_ s: String) -> Widget {
            Padding(padding: EdgeInsets(left: 0, top: 10, right: 0, bottom: 4), child: Text(s, style: fluent.typography.bodyStrong))
        }
        return Padding(padding: EdgeInsets(left: 16, top: 16, right: 16, bottom: 16), child: Column(mainAxisSize: .min, crossAxisAlignment: .start, children: [
            heading("Page"),
            Row(children: [
                ComboBox<Bool>(key: ValueKey("pagesetup-orientation"), value: form.landscape,
                               items: [ComboBoxItem<Bool>(value: false, child: Text("Portrait")),
                                       ComboBoxItem<Bool>(value: true, child: Text("Landscape"))],
                               onChanged: { [weak self] v in self?.setState { self?.form.landscape = v ?? false } }),
                Chrome.gap(12),
                ComboBox<Int>(key: ValueKey("pagesetup-paper"), value: form.paper,
                              items: PageSetupForm.papers.map { ComboBoxItem<Int>(value: $0.0, child: Text($0.1)) },
                              onChanged: { [weak self] v in if let v { self?.setState { self?.form.paper = v } } }),
            ]),
            Chrome.gap(6),
            Row(children: [
                Checkbox(key: ValueKey("pagesetup-fit"), checked: form.fit,
                         onChanged: { [weak self] v in self?.setState { self?.form.fit = v ?? false } },
                         content: Text("Fit to pages")),
            ]),
            form.fit
                ? Row(children: [box("wide", "Wide"), box("tall", "Tall")])
                : box("scale", "Scale %"),
            heading("Margins (inches)"),
            Row(children: [box("top", "Top"), box("bottom", "Bottom")]),
            Row(children: [box("left", "Left"), box("right", "Right")]),
            Row(children: [box("header", "Header"), box("footer", "Footer")]),
            check("centerH", "Center horizontally on the page", form.centerH) { self.form.centerH = $0 },
            check("centerV", "Center vertically on the page", form.centerV) { self.form.centerV = $0 },
            heading("Sheet"),
            check("gridlines", "Print gridlines", form.gridlines) { self.form.gridlines = $0 },
            check("headings", "Print row and column headings", form.headings) { self.form.headings = $0 },
            check("overThenDown", "Pages run across, then down", form.overThenDown) { self.form.overThenDown = $0 },
            Chrome.gap(8),
            Text(message, style: fluent.typography.caption),
            Row(mainAxisAlignment: .end, children: [
                FilledButton(key: ValueKey("pagesetup-ok"), onPressed: { [weak self] in self?.apply() }, child: Text("OK")),
                Chrome.gap(6),
                Button(key: ValueKey("pagesetup-cancel"), onPressed: _w.onClose, child: Text("Cancel")),
            ]),
        ]))
    }
}
