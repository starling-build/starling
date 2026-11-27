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
    var area: String, titleRows: String, titleCols: String
    var centerH: Bool, centerV: Bool, gridlines: Bool, headings: Bool, overThenDown: Bool
    var hf: HeaderFooter

    /// The boxes as the sheet has them now.
    init(_ s: SheetPrintSetup, paper number: Int, area: CellRange? = nil, titleRows: ClosedRange<Int>? = nil, titleCols: ClosedRange<Int>? = nil) {
        self.area = area.map { "\(CellAddress(row: $0.top, col: $0.left).a1):\(CellAddress(row: $0.bottom, col: $0.right).a1)" } ?? ""
        self.titleRows = titleRows.map { "\($0.lowerBound + 1):\($0.upperBound + 1)" } ?? ""
        self.titleCols = titleCols.map { "\(CellAddress.columnName($0.lowerBound)):\(CellAddress.columnName($0.upperBound))" } ?? ""
        func inch(_ pt: Double) -> String { Self.text((pt / 72 * 100).rounded() / 100) }
        landscape = s.landscape; paper = number
        fit = s.fitWidth != nil || s.fitHeight != nil
        scale = Self.text(s.scale.rounded())
        wide = String(s.fitWidth ?? 1); tall = String(s.fitHeight ?? 1)
        left = inch(s.left); right = inch(s.right); top = inch(s.top); bottom = inch(s.bottom)
        header = inch(s.headerMargin); footer = inch(s.footerMargin)
        centerH = s.centerHorizontally; centerV = s.centerVertically
        gridlines = s.gridlines; headings = s.headings; overThenDown = s.overThenDown
        hf = s.headerFooter
    }

    static func text(_ d: Double) -> String { d == d.rounded() ? String(Int(d)) : String(d) }

    /// What the Sheet group's three boxes name; blank means none.
    struct PrintNames: Equatable {
        var area: CellRange? = nil
        var rows: ClosedRange<Int>? = nil, cols: ClosedRange<Int>? = nil
    }

    /// The print area and repeated titles as typed ("A1:D20", "1:2", "A:B"), or the message to show.
    func names() -> (PrintNames?, String?) {
        func parse(_ text: String, _ what: String) -> (FormulaRef?, String?) {
            let t = text.trimmingSpaces()
            if t.isEmpty { return (nil, nil) }
            guard let e = try? Formula.parse("=" + t), case .ref(let r) = e else { return (nil, "\(what) is not a range such as \(what == "Print area" ? "A1:D20" : what == "Rows to repeat" ? "1:2" : "A:B")") }
            return (r, nil)
        }
        var n = PrintNames()
        let (a, ea) = parse(area, "Print area"); if let ea { return (nil, ea) }
        if let a { n.area = a.range }
        let (r, er) = parse(titleRows, "Rows to repeat"); if let er { return (nil, er) }
        if let r {
            guard r.start.col == nil, let x = r.start.row, let y = (r.end ?? r.start).row else { return (nil, "Rows to repeat is not a range such as 1:2") }
            n.rows = min(x, y) ... max(x, y)
        }
        let (c, ec) = parse(titleCols, "Columns to repeat"); if let ec { return (nil, ec) }
        if let c {
            guard c.start.row == nil, let x = c.start.col, let y = (c.end ?? c.start).col else { return (nil, "Columns to repeat is not a range such as A:B") }
            n.cols = min(x, y) ... max(x, y)
        }
        return (n, nil)
    }

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
        c.headerFooter = hf
        return (c, nil)
    }
}

/// The dialog's content: three groups of boxes (Page, Margins, Sheet) and OK/Cancel.
final class PageSetupPanel: StatefulWidget {
    let form: PageSetupForm
    let onApply: (PageSetupChange, PageSetupForm.PrintNames) -> Void
    let onClose: () -> Void
    init(form: PageSetupForm, onApply: @escaping (PageSetupChange, PageSetupForm.PrintNames) -> Void, onClose: @escaping () -> Void) {
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
    /// The header or footer box the field buttons add to (the last one typed in or chosen).
    var hfTarget = "hfOH"
    static let hfKeys = ["hfOH", "hfOF", "hfEH", "hfEF", "hfFH", "hfFF"]

    override func initState() {
        super.initState()
        form = _w.form
        for (k, v) in [("scale", form.scale), ("wide", form.wide), ("tall", form.tall), ("left", form.left), ("right", form.right),
                       ("top", form.top), ("bottom", form.bottom), ("header", form.header), ("footer", form.footer),
                       ("area", form.area), ("titleRows", form.titleRows), ("titleCols", form.titleCols),
                       ("hfOH", form.hf.oddHeader), ("hfOF", form.hf.oddFooter), ("hfEH", form.hf.evenHeader),
                       ("hfEF", form.hf.evenFooter), ("hfFH", form.hf.firstHeader), ("hfFF", form.hf.firstFooter)] {
            boxes[k] = TextEditingController(text: v)
        }
    }

    func apply() {
        func t(_ k: String) -> String { boxes[k]?.text ?? "" }
        form.scale = t("scale"); form.wide = t("wide"); form.tall = t("tall")
        form.left = t("left"); form.right = t("right"); form.top = t("top"); form.bottom = t("bottom")
        form.header = t("header"); form.footer = t("footer")
        form.area = t("area"); form.titleRows = t("titleRows"); form.titleCols = t("titleCols")
        form.hf.oddHeader = t("hfOH"); form.hf.oddFooter = t("hfOF"); form.hf.evenHeader = t("hfEH")
        form.hf.evenFooter = t("hfEF"); form.hf.firstHeader = t("hfFH"); form.hf.firstFooter = t("hfFF")
        let (c, err) = form.change()
        let (n, nerr) = form.names()
        if let c, let n { _w.onApply(c, n); _w.onClose() } else { setState { message = err ?? nerr ?? "" } }
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        func box(_ k: String, _ label: String) -> Widget {
            Padding(padding: EdgeInsets(left: 0, top: 3, right: 12, bottom: 3), child: Row(children: [
                SizedBox(width: 70, height: nil, child: Text(label, style: fluent.typography.body)),
                SizedBox(width: 70, height: Chrome.fieldHeight, child: FluentTextBox(key: ValueKey("pagesetup-\(k)"), controller: boxes[k]!,
                                                                    onSubmitted: { [weak self] _ in self?.apply() })),
            ]))
        }
        func wideBox(_ k: String, _ label: String) -> Widget {
            Padding(padding: EdgeInsets(left: 0, top: 3, right: 0, bottom: 3), child: Row(children: [
                SizedBox(width: 90, height: nil, child: Text(label, style: fluent.typography.body)),
                SizedBox(width: 150, height: Chrome.fieldHeight, child: FluentTextBox(key: ValueKey("pagesetup-\(k)"), controller: boxes[k]!,
                                                                    onSubmitted: { [weak self] _ in self?.apply() })),
            ]))
        }
        func check(_ k: String, _ label: String, _ on: Bool, _ set: @escaping (Bool) -> Void) -> Widget {
            Padding(padding: EdgeInsets(left: 0, top: 3, right: 0, bottom: 3), child: Checkbox(
                key: ValueKey("pagesetup-\(k)"), checked: on, onChanged: { [weak self] v in self?.setState { set(v ?? false) } },
                content: Text(label)))
        }
        func hfBox(_ k: String, _ label: String) -> Widget {
            Padding(padding: EdgeInsets(left: 0, top: 3, right: 0, bottom: 3), child: Row(children: [
                SizedBox(width: 90, height: nil, child: Text(label, style: fluent.typography.body)),
                // The rest of the dialog's width: a fixed 300 overflowed it by 10.
                Expanded(child: SizedBox(width: nil, height: Chrome.fieldHeight, child: FluentTextBox(key: ValueKey("pagesetup-\(k)"), controller: boxes[k]!,
                                                                     onChanged: { [weak self] _ in self?.hfTarget = k },
                                                                     onSubmitted: { [weak self] _ in self?.apply() }))),
            ]))
        }
        func field(_ id: String, _ label: String, _ code: String) -> Widget {
            Chrome.textToggle(label, false, fluent, action: { [weak self] in
                guard let self, let c = self.boxes[self.hfTarget] else { return }
                c.text += code
                self.setState {}
            })
        }
        func heading(_ s: String) -> Widget {
            Padding(padding: EdgeInsets(left: 0, top: 10, right: 0, bottom: 4), child: Text(s, style: fluent.typography.bodyStrong))
        }
        let content = Padding(padding: EdgeInsets(left: 16, top: 4, right: 16, bottom: 4), child: Column(mainAxisSize: .min, crossAxisAlignment: .start, children: [
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
            heading("Header and footer"),
            Text("Use &L, &C and &R for the left, centre and right parts.", style: fluent.typography.caption),
            hfBox("hfOH", form.hf.differentFirst || form.hf.differentOddEven ? "Header (odd)" : "Header"),
            hfBox("hfOF", form.hf.differentFirst || form.hf.differentOddEven ? "Footer (odd)" : "Footer"),
            form.hf.differentOddEven ? Column(crossAxisAlignment: .start, children: [hfBox("hfEH", "Header (even)"), hfBox("hfEF", "Footer (even)")]) : Chrome.gap(0),
            form.hf.differentFirst ? Column(crossAxisAlignment: .start, children: [hfBox("hfFH", "Header (first)"), hfBox("hfFF", "Footer (first)")]) : Chrome.gap(0),
            Row(children: [
                field("page", "Page", "&P"), field("pages", "Pages", "&N"), field("date", "Date", "&D"),
                field("time", "Time", "&T"), field("file", "File", "&F"), field("sheet", "Sheet", "&A"),
            ]),
            check("hfFirst", "Different first page", form.hf.differentFirst) { self.form.hf.differentFirst = $0 },
            check("hfOddEven", "Different odd and even pages", form.hf.differentOddEven) { self.form.hf.differentOddEven = $0 },
            heading("Sheet"),
            wideBox("area", "Print area"), wideBox("titleRows", "Repeat rows"), wideBox("titleCols", "Repeat cols"),
            check("gridlines", "Print gridlines", form.gridlines) { self.form.gridlines = $0 },
            check("headings", "Print row and column headings", form.headings) { self.form.headings = $0 },
            check("overThenDown", "Pages run across, then down", form.overThenDown) { self.form.overThenDown = $0 },
            Chrome.gap(8),
            Text(message, style: fluent.typography.caption),
        ]))
        return DialogShell(title: "Page Setup", page: SizedBox(width: nil, height: 560, child: SingleChildScrollView(child: content)),
                           width: 460, onOK: { [weak self] in self?.apply() }, onCancel: _w.onClose)
    }
}
