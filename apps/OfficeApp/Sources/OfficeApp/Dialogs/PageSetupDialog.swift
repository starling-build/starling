// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// W-PG-1: the Page Setup dialog. Margins (top, bottom, left, right, and how far the header and
// footer stand from the page edge), orientation, and paper size (presets or a custom width and
// height). "Apply to" says whether the caret's section or every section changes; OK is one undo step
// (`changePageSetup`). Gutter and mirror margins are not offered: the editor cannot save them yet.

import Flutter
import FlutterSwiftBridge
import OfficeText

private final class PSKeyed: StatelessWidget {
    let child: Widget
    init(_ id: String, _ child: Widget) { self.child = child; super.init(key: ValueKey(id)) }
    override func build(_ context: any BuildContext) -> Widget { child }
}

/// The paper sizes the dialog offers, in portrait points (Word's own twip values).
enum PaperSize: CaseIterable {
    case letter, legal, a3, a4, a5, custom
    var title: String { ["Letter", "Legal", "A3", "A4", "A5", "Custom"][PaperSize.allCases.firstIndex(of: self)!] }
    var id: String { ["letter", "legal", "a3", "a4", "a5", "custom"][PaperSize.allCases.firstIndex(of: self)!] }
    var portrait: (Double, Double)? {
        switch self {
        case .letter: return (612, 792)
        case .legal: return (612, 1008)
        case .a3: return (841.9, 1190.55)
        case .a4: return (595.3, 841.9)
        case .a5: return (419.55, 595.3)
        case .custom: return nil
        }
    }
    /// The preset a page is, either way up (within a tenth of a point), else custom.
    init(width: Double, height: Double) {
        let (a, b) = (min(width, height), max(width, height))
        self = PaperSize.allCases.first { s in
            guard let p = s.portrait else { return false }
            return abs(p.0 - a) < 0.1 && abs(p.1 - b) < 0.1
        } ?? .custom
    }
}

struct PageSetupValues: Equatable {
    var width: Double, height: Double
    var top: Double, bottom: Double, left: Double, right: Double
    var header: Double, footer: Double
    var allSections = false
    var options = RichDocumentController.PageOptions(titlePage: false, evenAndOdd: false, pageNumberStart: nil)

    init(_ p: PageSetup) {
        width = p.width; height = p.height
        top = p.marginTop; bottom = p.marginBottom; left = p.marginLeft; right = p.marginRight
        header = p.headerDistance; footer = p.footerDistance
    }
    /// The separators between the chapter number and the page number, as `w:chapSep` names them.
    static let chapterSeparators: [(id: String, label: String)] = [
        ("hyphen", "- (hyphen)"), ("period", ". (period)"), ("colon", ": (colon)"), ("emDash", "\u{2014} (em dash)"), ("enDash", "\u{2013} (en dash)"),
    ]
    /// The page number formats the Layout tab offers, as `w:fmt` names them.
    static let numberFormats: [(id: String, label: String)] = [
        ("decimal", "1, 2, 3"), ("lowerRoman", "i, ii, iii"), ("upperRoman", "I, II, III"),
        ("lowerLetter", "a, b, c"), ("upperLetter", "A, B, C"),
    ]
    var landscape: Bool { width > height }
    var paper: PaperSize { PaperSize(width: width, height: height) }
    mutating func setPaper(_ s: PaperSize) {
        guard let p = s.portrait else { return }
        if landscape { width = p.1; height = p.0 } else { width = p.0; height = p.1 }
    }
    mutating func setLandscape(_ on: Bool) {
        guard on != landscape else { return }
        swap(&width, &height)
    }
    /// The text area must stay a usable size.
    var valid: Bool { width - left - right >= 36 && height - top - bottom >= 36 && width >= 72 && height >= 72 }
    func apply(to p: inout PageSetup) {
        let rotated = (p.width > p.height) != landscape
        p.width = width; p.height = height
        p.marginTop = top; p.marginBottom = bottom; p.marginLeft = left; p.marginRight = right
        p.headerDistance = header; p.footerDistance = footer
        if rotated { p.orientStated = true }
    }
}

final class PageSetupDialog: StatefulWidget {
    let initial: PageSetup
    let sectionCount: Int
    let unit: LengthUnit
    let options: RichDocumentController.PageOptions?
    let onOK: (PageSetupValues) -> Void
    let onCancel: () -> Void
    init(initial: PageSetup, sectionCount: Int = 1, unit: LengthUnit = .inch, options: RichDocumentController.PageOptions? = nil,
         onOK: @escaping (PageSetupValues) -> Void, onCancel: @escaping () -> Void) {
        self.initial = initial; self.sectionCount = sectionCount; self.unit = unit; self.options = options
        self.onOK = onOK; self.onCancel = onCancel
        super.init()
    }
    override func createState() -> State<StatefulWidget> { PageSetupDialogState() }
}

final class PageSetupDialogState: State<StatefulWidget> {
    private var _w: PageSetupDialog { widget as! PageSetupDialog }
    private(set) var v = PageSetupValues(PageSetup.letter)
    private let _startText = TextEditingController()

    override func initState() {
        super.initState()
        v = PageSetupValues(_w.initial)
        if let o = _w.options { v.options = o; _startText.text = o.pageNumberStart.map(String.init) ?? "1" }
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let unit = _w.unit
        func choice(_ id: String, _ label: String, _ on: Bool, _ action: @escaping () -> Void) -> Widget {
            PSKeyed(id, Chrome.textToggle(label, on, fluent, action: action))
        }
        func spin(_ id: String, _ label: String, _ pts: Double, min: Double = 0, max: Double = 1584,
                  _ set: @escaping (Double) -> Void) -> Widget {
            Padding(padding: EdgeInsets(left: 0, top: 0, right: 12, bottom: 8), child: Column(crossAxisAlignment: .start, children: [
                Text(label), Chrome.vgap(2),
                PSKeyed(id, UnitSpinner(points: pts, unit: unit, min: min, max: max, width: 90) { [weak self] n in
                    self?.setState { set(n) } }),
            ]))
        }
        func format(_ f: (id: String, label: String)) -> Widget {
            choice("ps-fmt-\(f.id)", f.label, (v.options.pageNumberFormat ?? "decimal") == f.id) { [weak self] in
                guard let self else { return }
                // Decimal on a file that names no format stays unnamed, so an untouched file saves as it was.
                self.setState { self.v.options.pageNumberFormat = f.id == "decimal" && self.v.options.pageNumberFormat == nil ? nil : f.id }
            }
        }
        func row(_ label: String, _ items: [Widget]) -> Widget {
            Padding(padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 8), child: Row(crossAxisAlignment: .center, children:
                [SizedBox(width: 90, height: nil, child: Text(label))] + items))
        }
        let orientation = row("Orientation", [
            choice("ps-portrait", "Portrait", !v.landscape) { [weak self] in self?.setState { self?.v.setLandscape(false) } },
            choice("ps-landscape", "Landscape", v.landscape) { [weak self] in self?.setState { self?.v.setLandscape(true) } },
        ])
        let applyTo: Widget = _w.sectionCount > 1 ? row("Apply to", [
            choice("ps-this", "This section", !v.allSections) { [weak self] in self?.setState { self?.v.allSections = false } },
            choice("ps-all", "Whole document", v.allSections) { [weak self] in self?.setState { self?.v.allSections = true } },
        ]) : Chrome.gap(0)
        let warning: Widget = v.valid ? Chrome.gap(0)
            : Text("The margins leave no room for text.", style: fluent.typography.caption?.copyWith(color: Color(0xFFC42B1C)))
        let margins = Column(crossAxisAlignment: .start, children: [
            Row(children: [
                spin("ps-top", "Top", v.top) { [weak self] n in self?.v.top = n },
                spin("ps-bottom", "Bottom", v.bottom) { [weak self] n in self?.v.bottom = n },
            ]),
            Row(children: [
                spin("ps-left", "Left", v.left) { [weak self] n in self?.v.left = n },
                spin("ps-right", "Right", v.right) { [weak self] n in self?.v.right = n },
            ]),
            Row(children: [
                spin("ps-header", "Header from top", v.header) { [weak self] n in self?.v.header = n },
                spin("ps-footer", "Footer from bottom", v.footer) { [weak self] n in self?.v.footer = n },
            ]),
            orientation, applyTo, warning,
        ])
        let paper = Column(crossAxisAlignment: .start, children: [
            row("Paper size", PaperSize.allCases.prefix(3).map { s in
                choice("ps-paper-\(s.id)", s.title, v.paper == s) { [weak self] in self?.setState { self?.v.setPaper(s) } } }),
            row("", PaperSize.allCases.suffix(3).map { s in
                choice("ps-paper-\(s.id)", s.title, v.paper == s) { [weak self] in self?.setState { self?.v.setPaper(s) } } }),
            Row(children: [
                spin("ps-width", "Width", v.width, min: 72) { [weak self] n in self?.v.width = n },
                spin("ps-height", "Height", v.height, min: 72) { [weak self] n in self?.v.height = n },
            ]),
            orientation, applyTo, warning,
        ])
        let layout = Column(crossAxisAlignment: .start, children: [
            row("First page", [choice("ps-first", "Different first page", v.options.titlePage) { [weak self] in
                self?.setState { self?.v.options.titlePage.toggle() } }]),
            row("Odd and even", [choice("ps-evenodd", "Different odd and even pages", v.options.evenAndOdd) { [weak self] in
                self?.setState { self?.v.options.evenAndOdd.toggle() } }]),
            row("Numbering", [
                choice("ps-continue", "Continue", v.options.pageNumberStart == nil) { [weak self] in
                    self?.setState { self?.v.options.pageNumberStart = nil } },
                choice("ps-startat", "Start at", v.options.pageNumberStart != nil) { [weak self] in
                    guard let self else { return }
                    self.setState { self.v.options.pageNumberStart = Int(self._startText.text) ?? 1 } },
                SizedBox(width: 60, child: PSKeyed("ps-start", FluentTextBox(controller: _startText, onChanged: { [weak self] t in
                    guard let self, self.v.options.pageNumberStart != nil, let n = Int(t), n >= 0 else { return }
                    self.v.options.pageNumberStart = n
                }))),
            ]),
            // The page numbers' format (Format Page Numbers). A file's other format (East Asian, numberInDash)
            // shows no choice and stays until one is picked.
            row("Format", PageSetupValues.numberFormats.prefix(3).map(format)),
            row("", PageSetupValues.numberFormats.suffix(2).map(format)),
            // Include chapter number: the number of the chapter's heading, then a separator, before the page number.
            row("Chapter", [choice("ps-chapter", "Include chapter number", v.options.chapterStyle != nil) { [weak self] in
                self?.setState {
                    guard let self else { return }
                    if self.v.options.chapterStyle == nil { self.v.options.chapterStyle = 1 }
                    else { self.v.options.chapterStyle = nil; self.v.options.chapterSeparator = nil }
                } }]),
            v.options.chapterStyle == nil ? SizedBox(width: 0, height: 0) : row("", [
                    PSKeyed("ps-chapstyle", SizedBox(width: 120, height: nil, child: ComboBox<Int>(
                        value: v.options.chapterStyle,
                        items: (1...9).map { ComboBoxItem<Int>(value: $0, child: Text("Heading \($0)", style: fluent.typography.body)) },
                        onChanged: { [weak self] n in self?.setState { self?.v.options.chapterStyle = n ?? 1 } }))),
                    SizedBox(width: 12, height: nil),
                    PSKeyed("ps-chapsep", SizedBox(width: 150, height: nil, child: ComboBox<String>(
                        value: v.options.chapterSeparator ?? "hyphen",
                        items: PageSetupValues.chapterSeparators.map { ComboBoxItem<String>(value: $0.id, child: Text($0.label, style: fluent.typography.body)) },
                        onChanged: { [weak self] sep in
                            // Hyphen on a file that names none stays unnamed.
                            self?.setState { self?.v.options.chapterSeparator = sep == "hyphen" && self?.v.options.chapterSeparator == nil ? nil : sep } }))),
                ]),
            applyTo,
        ])
        var tabs = [DialogTab(title: "Margins", page: margins), DialogTab(title: "Paper", page: paper)]
        if _w.options != nil { tabs.append(DialogTab(title: "Layout", page: layout)) }
        return DialogShell(title: "Page Setup",
                           tabs: tabs,
                           okEnabled: v.valid, width: 480,
                           onOK: { [weak self] in guard let self, self.v.valid else { return }; self._w.onOK(self.v) },
                           onCancel: { [weak self] in self?._w.onCancel() })
    }
}
