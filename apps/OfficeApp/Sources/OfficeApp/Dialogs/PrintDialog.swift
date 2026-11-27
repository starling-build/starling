// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The one Print dialog (U-shared, U-PR-1), on DialogShell: which pages (all, the current one,
// the selection, or a typed range like "1-3, 5, 8-"), how many copies, and for Slides what to
// print (slides, notes, handouts). The dialog owns the choices and turns them into a plain list
// of pages; each app's `PrintHooks.print` makes the PDF of exactly those pages and hands it to
// the host's print dialog.

import Flutter
import FlutterSwiftBridge

enum PrintRange: Equatable {
    case all, current, selection, custom
}

enum PrintPlan {
    /// "1-3, 5, 8-" over `total` pages -> [1,2,3,5,8,...,total]; nil if any part is not a page.
    /// Pages keep the order typed (so "5, 1" prints 5 then 1) and repeats are kept.
    static func parse(_ text: String, total: Int) -> [Int]? {
        var out: [Int] = []
        let parts = text.split(separator: ",", omittingEmptySubsequences: false).map { String($0).trimmingWhitespace() }
        if parts.isEmpty || parts.contains(where: { $0.isEmpty }) { return nil }
        for part in parts {
            let ends = part.split(separator: "-", omittingEmptySubsequences: false).map { String($0).trimmingWhitespace() }
            if ends.count == 1 {
                guard let n = Int(ends[0]), (1 ... total).contains(n) else { return nil }
                out.append(n)
            } else if ends.count == 2 {
                let lo = ends[0].isEmpty ? 1 : Int(ends[0])
                let hi = ends[1].isEmpty ? total : Int(ends[1])
                guard let lo, let hi, lo >= 1, hi <= total, lo <= hi, !(ends[0].isEmpty && ends[1].isEmpty) else { return nil }
                out.append(contentsOf: lo ... hi)
            } else { return nil }
        }
        return out
    }

    /// The pages to send: the chosen set, then `copies` full sets one after another (collated).
    static func sheets(_ pages: [Int], copies: Int) -> [Int] {
        (0 ..< max(1, copies)).flatMap { _ in pages }
    }
}

struct PrintHooks {
    var unit = "Pages"                 // "Slides" in Slides
    var total: Int
    var current: Int                   // 1-based
    /// The page count of each output when it differs by output (Sheets: sheet, workbook, selection); `total` otherwise.
    var totals: [Int] = []
    /// Pages the selection covers (1-based), or nil when there is none / the app cannot say.
    var selection: [Int]? = nil
    /// "Print what": empty hides the choice; Slides offers Slides, Notes Pages, Handouts.
    var outputs: [String] = []
    /// False when the host has no print dialog: Print is off and the dialog says why.
    var hostCanPrint = true
    /// Print `pages` (1-based, copies already applied) of output `output`; returns the status line.
    var print: (_ pages: [Int], _ output: Int) -> String
}

extension PrintHooks {
    /// Pages in output `i`.
    func total(of i: Int) -> Int { totals.indices.contains(i) ? totals[i] : total }
}

final class PrintDialog: StatefulWidget {
    let hooks: PrintHooks
    let onClose: () -> Void
    init(hooks: PrintHooks, onClose: @escaping () -> Void) {
        self.hooks = hooks
        self.onClose = onClose
        super.init()
    }
    override func createState() -> State<StatefulWidget> { PrintDialogState() }
}

final class PrintDialogState: State<StatefulWidget> {
    private var _w: PrintDialog { widget as! PrintDialog }
    private let _pages = TextEditingController()
    private let _copies = TextEditingController()
    private(set) var range = PrintRange.all
    private(set) var output = 0
    private(set) var status = ""

    override func initState() {
        super.initState()
        _copies.text = "1"
    }

    override func dispose() {
        _pages.dispose()
        _copies.dispose()
        super.dispose()
    }

    /// The pages the choices name, or why they name none.
    func resolve() -> (pages: [Int], error: String?) {
        let h = _w.hooks
        let total = h.total(of: output)
        let set: [Int]
        switch range {
        case .all: set = total > 0 ? Array(1 ... total) : []
        case .current: set = [min(max(1, h.current), max(1, total))]
        case .selection: set = h.selection ?? []
        case .custom:
            guard let p = PrintPlan.parse(_pages.text, total: total) else {
                return ([], "Type pages like 1-3, 5 (1 to \(total))")
            }
            set = p
        }
        if set.isEmpty { return ([], "Nothing to print") }
        guard let n = Int(_copies.text.trimmingWhitespace()), (1 ... 99).contains(n) else {
            return ([], "Copies must be 1 to 99")
        }
        return (PrintPlan.sheets(set, copies: n), nil)
    }

    func printNow() {
        let h = _w.hooks
        guard h.hostCanPrint else { setState { status = "This host has no print dialog; use File > Export for a PDF" }; return }
        let r = resolve()
        if let e = r.error { setState { status = e }; return }
        let s = h.print(r.pages, output)
        // A good print closes the dialog; the hook says what went wrong otherwise.
        if s.isEmpty { _w.onClose() } else { setState { status = s } }
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let h = _w.hooks
        func label(_ t: String) -> Widget { SizedBox(width: 100, height: nil, child: Text(t, style: fluent.typography.body)) }
        let gap = SizedBox(width: nil, height: 10, child: nil)
        func radio(_ r: PrintRange, _ text: String) -> Widget {
            RadioButton<PrintRange>(value: r, groupValue: range,
                                    onChanged: { [weak self] v in if let v { self?.setState { self?.range = v } } },
                                    content: Text(text, style: fluent.typography.body))
        }
        var page: [Widget] = []
        if !h.outputs.isEmpty {
            page.append(Row(crossAxisAlignment: .center, children: [label("Print what"),
                SizedBox(width: 220, height: nil, child: ComboBox<String>(
                    value: h.outputs[min(output, h.outputs.count - 1)],
                    items: h.outputs.map { ComboBoxItem<String>(value: $0, child: Text($0, style: fluent.typography.body)) },
                    onChanged: { [weak self] v in
                        guard let self, let v, let i = h.outputs.firstIndex(of: v) else { return }
                        self.setState { self.output = i }
                    }))]))
            page.append(gap)
        }
        page.append(Text(h.unit, style: fluent.typography.bodyStrong))
        page.append(radio(.all, "All \(h.total(of: output)) \(h.unit.lowercased())"))
        page.append(radio(.current, "Current (\(h.current))"))
        if let s = h.selection, !s.isEmpty { page.append(radio(.selection, "Selection")) }
        page.append(Row(crossAxisAlignment: .center, children: [radio(.custom, "Range"),
            SizedBox(width: 8, height: nil, child: nil),
            SizedBox(width: 180, height: Chrome.fieldHeight, child: PKeyed("print-pages", FluentTextBox(
                controller: _pages, onChanged: { [weak self] _ in
                    if self?.range != .custom { self?.setState { self?.range = .custom } }
                }, onSubmitted: { [weak self] _ in self?.printNow() })))]))
        page.append(gap)
        page.append(Row(crossAxisAlignment: .center, children: [label("Copies"),
            SizedBox(width: 70, height: Chrome.fieldHeight, child: PKeyed("print-copies", FluentTextBox(
                controller: _copies, onSubmitted: { [weak self] _ in self?.printNow() })))]))
        page.append(SizedBox(width: nil, height: 10, child: nil))
        page.append(Text(status, style: fluent.typography.caption?.copyWith(color: fluent.resources.textFillColorSecondary)))
        return DialogShell(title: "Print options", page: Column(crossAxisAlignment: .stretch, children: page),
                           okLabel: "Print", cancelLabel: "Cancel", width: 440,
                           onOK: { [weak self] in self?.printNow() }, onCancel: _w.onClose)
    }
}
