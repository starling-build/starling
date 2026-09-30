// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The ribbon: Word's tab strip (File, Home, Insert, Draw, Layout,
// References, Review, View) over one row of groups per tab. File is not a
// tab but the door to Backstage. The Home tab is complete; Insert, Layout
// and View carry what the document model supports today; Draw, References
// and Review are placeholders that keep the strip Word-shaped.

import Flutter
import FlutterSwiftBridge
import FluentSystemIcons
import Foundation

enum RibbonTab: Int, CaseIterable {
    case home, insert, draw, layout, references, review, view
    /// Contextual: shown while a picture is selected or the caret is in a
    /// table, as Word does.
    case pictureFormat, tableLayout

    var title: String {
        switch self {
        case .home: return "Home"
        case .insert: return "Insert"
        case .draw: return "Draw"
        case .layout: return "Layout"
        case .references: return "References"
        case .review: return "Review"
        case .view: return "View"
        case .pictureFormat: return "Picture Format"
        case .tableLayout: return "Table Layout"
        }
    }

    var isContextual: Bool { self == .pictureFormat || self == .tableLayout }
}

final class Ribbon: StatelessWidget {
    let session: OfficeSession
    let tab: RibbonTab
    let collapsed: Bool
    let onTab: (RibbonTab) -> Void
    let onCollapse: () -> Void

    init(session: OfficeSession, tab: RibbonTab, collapsed: Bool,
         onTab: @escaping (RibbonTab) -> Void, onCollapse: @escaping () -> Void) {
        self.session = session
        self.tab = tab
        self.collapsed = collapsed
        self.onTab = onTab
        self.onCollapse = onCollapse
        super.init()
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        var children: [Widget] = [_strip(fluent)]
        if !collapsed {
            children.append(SizedBox(
                width: nil, height: Chrome.ribbonHeight,
                child: DecoratedBox(
                    decoration: BoxDecoration(
                        color: fluent.resources.layerFillColorDefault,
                        border: Border(bottom: BorderSide(color: fluent.resources.dividerStrokeColorDefault, width: 1))),
                    child: Row(crossAxisAlignment: .stretch, children: _groups(fluent) + [
                        Expanded(child: SizedBox(width: 0, height: 0, child: nil)),
                        _collapseButton(fluent),
                    ]))))
        }
        return Column(crossAxisAlignment: .stretch, children: children)
    }

    // MARK: Tab strip

    private func _strip(_ fluent: FluentThemeData) -> Widget {
        var items: [Widget] = [_fileTab(fluent)]
        for t in RibbonTab.allCases where !t.isContextual
            || (t == .pictureFormat && session.summary.imageIndex != nil)
            || (t == .tableLayout && session.summary.inCell) {
            items.append(_tab(t, fluent))
        }
        return Padding(padding: EdgeInsets(left: 8, top: 2, right: 8, bottom: 0),
                       child: Row(crossAxisAlignment: .end, children: items))
    }

    private func _fileTab(_ fluent: FluentThemeData) -> Widget {
        let accent = fluent.accentColor.defaultBrushFor(fluent.brightness)
        return GestureDetector(
            onTap: { [session] in session.onBackstage?(true) },
            child: Padding(padding: EdgeInsets(left: 0, top: 0, right: 6, bottom: 4), child: DecoratedBox(
                decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.all(Radius(circular: 4))),
                child: Padding(padding: EdgeInsets(left: 14, top: 5, right: 14, bottom: 5),
                               child: Text("File", style: fluent.typography.body?.copyWith(
                                   color: fluent.resources.textOnAccentFillColorPrimary))))))
    }

    private func _tab(_ t: RibbonTab, _ fluent: FluentThemeData) -> Widget {
        let selected = t == tab && !collapsed
        let accent = fluent.accentColor.defaultBrushFor(fluent.brightness)
        let underline = selected ? accent : Color(0x00000000)
        return GestureDetector(
            onTap: { [onTab, onCollapse, collapsed] in
                if collapsed { onCollapse() }
                onTab(t)
            },
            child: Padding(padding: EdgeInsets(left: 2, top: 0, right: 2, bottom: 0), child: Column(
                mainAxisAlignment: .end, crossAxisAlignment: .center, children: [
                    Padding(padding: EdgeInsets(left: 10, top: 6, right: 10, bottom: 4),
                            child: Text(t.title, style: selected
                                ? fluent.typography.bodyStrong
                                : fluent.typography.body)),
                    SizedBox(width: 36, height: 3, child: DecoratedBox(decoration: BoxDecoration(
                        color: underline, borderRadius: BorderRadius.all(Radius(circular: 2))))),
                ])))
    }

    private func _collapseButton(_ fluent: FluentThemeData) -> Widget {
        Padding(padding: EdgeInsets(left: 4, top: 4, right: 8, bottom: 4), child: Column(
            mainAxisAlignment: .end, children: [
                Chrome.icon(FluentSystemIcons.chevronUp, "Collapse the ribbon", fluent, action: onCollapse),
            ]))
    }

    // MARK: Groups per tab

    private func _groups(_ fluent: FluentThemeData) -> [Widget] {
        switch tab {
        case .home: return _home(fluent)
        case .insert: return _insert(fluent)
        case .layout: return _layout(fluent)
        case .view: return _view(fluent)
        case .pictureFormat: return _pictureFormat(fluent)
        case .tableLayout: return _tableLayout(fluent)
        case .draw: return _placeholder(fluent, "Drawing", ["Pen", "Highlighter", "Eraser"])
        case .references: return _placeholder(fluent, "Table of Contents", ["Table of Contents", "Footnote", "Citation"])
        case .review: return _placeholder(fluent, "Proofing", ["Spelling", "Word Count", "Track Changes"])
        }
    }

    private func _placeholder(_ fluent: FluentThemeData, _ label: String, _ names: [String]) -> [Widget] {
        [Chrome.group(label, fluent, names.map { name in
            Chrome.big(FluentSystemIcons.document, name, fluent, enabled: false, action: {})
        })]
    }

    // MARK: Home

    private func _home(_ fluent: FluentThemeData) -> [Widget] {
        let c = session.controller
        let s = session.summary
        let clipboard = Chrome.group("Clipboard", fluent, [
            Chrome.big(FluentSystemIcons.paste, "Paste", fluent) { [session] in session.onStatus?("Paste: press \(KeyModifiers.primary == .meta ? "⌘" : "Ctrl+")V in the document") },
            Chrome.gap(2),
            Chrome.rows([
                Chrome.small(FluentSystemIcons.cut, "Cut", fluent, enabled: s.hasSelection) { [session] in
                    if let t = c.cutSelection() { Clipboard.setData(ClipboardData(text: t)) }
                    session.onStatus?("Cut")
                },
                Chrome.small(FluentSystemIcons.copy, "Copy", fluent, enabled: s.hasSelection) { [session] in
                    if let t = c.copySelection() { Clipboard.setData(ClipboardData(text: t)) }
                    session.onStatus?("Copied")
                },
                Chrome.small(FluentSystemIcons.paintBrush, "Format Painter", fluent, enabled: false) {},
            ]),
        ])

        let sizes: [Double] = [8, 9, 10, 11, 12, 14, 16, 18, 20, 24, 28, 36, 48, 72]
        let currentSize = session.effectiveFontSize
        let fontRow1 = Chrome.row([
            SizedBox(width: 172, height: nil, child: ComboBox<String>(
                value: session.effectiveFontFamily,
                items: OfficeFonts.families.map { f in
                    ComboBoxItem<String>(value: f, child: Text(f, style: fluent.typography.body?.copyWith(color: nil)))
                },
                onChanged: { f in c.setFontFamily(f) })),
            Chrome.gap(),
            SizedBox(width: 72, height: nil, child: ComboBox<Double>(
                value: sizes.contains(currentSize) ? currentSize : nil,
                items: sizes.map { n in ComboBoxItem<Double>(value: n, child: Text(Self._fmt(n))) },
                onChanged: { n in if let n { c.setFontSize(n) } },
                placeholder: Text(Self._fmt(currentSize)))),
            Chrome.gap(),
            Chrome.icon(FluentSystemIcons.textFontSize, "Grow Font", fluent) { [session] in c.stepFontSize(1, base: session.effectiveFontSize) },
            Chrome.icon(FluentSystemIcons.textFont, "Shrink Font", fluent) { [session] in c.stepFontSize(-1, base: session.effectiveFontSize) },
            Chrome.icon(FluentSystemIcons.textChangeCase, "Change Case", fluent, enabled: false) {},
            Chrome.icon(FluentSystemIcons.textClearFormatting, "Clear All Formatting", fluent) { c.clearFormatting() },
        ])
        let fontRow2 = Chrome.row([
            Chrome.toggle(FluentSystemIcons.textBold, "Bold (⌘B)", s.bold, fluent) { c.toggleBold() },
            Chrome.toggle(FluentSystemIcons.textItalic, "Italic (⌘I)", s.italic, fluent) { c.toggleItalic() },
            Chrome.toggle(FluentSystemIcons.textUnderline, "Underline (⌘U)", s.underline, fluent) { c.toggleUnderline() },
            Chrome.toggle(FluentSystemIcons.textStrikethrough, "Strikethrough", s.strikethrough, fluent) { c.toggleStrikethrough() },
            Chrome.toggle(FluentSystemIcons.textSubscript, "Subscript", s.subscript, fluent) { c.setScript(.subscript) },
            Chrome.toggle(FluentSystemIcons.textSuperscript, "Superscript", s.superscript, fluent) { c.setScript(.superscript) },
            Chrome.gap(2),
            Chrome.colorMenu(FluentSystemIcons.highlight, "Text Highlight Color", fluent,
                             colors: OfficeColors.highlight, none: "No Color") { color in c.setHighlight(color) },
            Chrome.colorMenu(FluentSystemIcons.textColor, "Font Color", fluent,
                             colors: OfficeColors.text, none: "Automatic") { color in c.setTextColor(color) },
        ])
        let font = Chrome.group("Font", fluent, [Chrome.rows([fontRow1, Chrome.vgap(4), fontRow2])])

        let spacingChoices: [(String, () -> Void)] = [1.0, 1.15, 1.5, 2.0, 2.5, 3.0].map { m in
            (String(format: "%.2f", m), { c.setLineSpacing(m) })
        }
        let paraRow1 = Chrome.row([
            Chrome.toggle(FluentSystemIcons.bulletList, "Bullets", s.list == .bullet, fluent) { c.toggleList(.bullet) },
            Chrome.toggle(FluentSystemIcons.numberList, "Numbering", s.list == .numbered, fluent) { c.toggleList(.numbered) },
            Chrome.gap(2),
            Chrome.icon(FluentSystemIcons.indentDecrease, "Decrease Indent", fluent) { c.indent(-1) },
            Chrome.icon(FluentSystemIcons.indentIncrease, "Increase Indent", fluent) { c.indent(1) },
            Chrome.gap(2),
            Chrome.icon(FluentSystemIcons.paragraphMarks, "Show/Hide ¶", fluent, enabled: false) {},
        ])
        let paraRow2 = Chrome.row([
            Chrome.toggle(FluentSystemIcons.alignLeft, "Align Left", s.alignment == .left, fluent) { c.setAlignment(.left) },
            Chrome.toggle(FluentSystemIcons.alignCenter, "Center", s.alignment == .center, fluent) { c.setAlignment(.center) },
            Chrome.toggle(FluentSystemIcons.alignRight, "Align Right", s.alignment == .right, fluent) { c.setAlignment(.right) },
            Chrome.toggle(FluentSystemIcons.alignJustify, "Justify", s.alignment == .justify, fluent) { c.setAlignment(.justify) },
            Chrome.gap(2),
            Chrome.menu(nil, Icon(FluentSystemIcons.lineSpacing, size: Chrome.iconSize,
                                  color: fluent.resources.textFillColorPrimary), fluent, spacingChoices),
        ])
        let paragraph = Chrome.group("Paragraph", fluent, [Chrome.rows([paraRow1, Chrome.vgap(4), paraRow2])])

        // The gallery: four tiles, then every style of the sheet in a menu.
        let sheet = c.document.styles
        var tiles: [Widget] = []
        for id in [RichNamedStyle.normalId, "Title", RichNamedStyle.headingId(1), RichNamedStyle.headingId(2)] {
            guard let entry = sheet[id] else { continue }
            tiles.append(_styleTile(entry, s.styleId == id, fluent) { c.setNamedStyle(id) })
        }
        let more: [MenuFlyoutItemBase] = sheet.styles.map { entry in
            MenuFlyoutItem(text: Text(entry.name, style: _preview(entry, fluent, cap: 13)),
                           leading: Icon(s.styleId == entry.id ? FluentSystemIcons.check : FluentSystemIcons.textT,
                                         size: Chrome.iconSize, color: fluent.resources.textFillColorPrimary),
                           onPressed: { c.setNamedStyle(entry.id) })
        }
        tiles.append(Tooltip(message: "All styles", child: DropDownButton(
            leading: Icon(FluentSystemIcons.paintBrush, size: Chrome.iconSize, color: fluent.resources.textFillColorPrimary),
            items: more)))
        let styles = Chrome.group("Styles", fluent, tiles)

        let editing = Chrome.group("Editing", fluent, [Chrome.rows([
            Chrome.small(FluentSystemIcons.search, "Find", fluent) { [session] in session.onFind?(false) },
            Chrome.small(FluentSystemIcons.textGrammarWand, "Replace", fluent) { [session] in session.onFind?(true) },
            Chrome.small(FluentSystemIcons.textT, "Select All", fluent) { c.selectAll() },
        ])])

        return [clipboard, font, paragraph, styles, editing]
    }

    /// A gallery tile: the style's look on "AaBb", its name under it.
    private func _styleTile(_ entry: RichNamedStyle, _ on: Bool, _ fluent: FluentThemeData,
                            action: @escaping () -> Void) -> Widget {
        let look = _preview(entry, fluent, cap: 18, onAccent: on)
        return Padding(padding: EdgeInsets(left: 0, top: 0, right: 4, bottom: 0),
                child: SizedBox(width: 80, height: 56, child: ToggleButton(
                    checked: on, onChanged: { _ in action() },
                    child: Column(mainAxisAlignment: .center, crossAxisAlignment: .center, children: [
                        Text(entry.id == RichNamedStyle.normalId ? "AaBbCc" : "AaBb", style: look),
                        Chrome.vgap(2),
                        Text(entry.name, style: fluent.typography.caption?.copyWith(
                            color: on ? fluent.resources.textOnAccentFillColorPrimary : nil),
                             softWrap: false),
                    ]))))
    }

    /// The style's character look, sized to fit chrome.
    private func _preview(_ entry: RichNamedStyle, _ fluent: FluentThemeData, cap: Double,
                          onAccent: Bool = false) -> Flutter.TextStyle {
        let size = min(cap, (entry.char.fontSize ?? session.theme.fontSize) * 0.85)
        let color = onAccent ? fluent.resources.textOnAccentFillColorPrimary
            : entry.char.color ?? fluent.resources.textFillColorPrimary
        return Flutter.TextStyle(color: color, fontSize: max(9, size),
                                 fontWeight: entry.char.bold ? .bold : .normal,
                                 fontStyle: entry.char.italic ? .italic : .normal,
                                 fontFamily: entry.char.fontFamily ?? session.theme.fontFamily)
    }

    private static func _fmt(_ n: Double) -> String {
        n == n.rounded() ? String(Int(n)) : String(format: "%.1f", n)
    }

    // MARK: Insert

    private func _insert(_ fluent: FluentThemeData) -> [Widget] {
        let c = session.controller
        let symbols: [(String, () -> Void)] = [("— Em dash", "—"), ("– En dash", "–"), ("… Ellipsis", "…"),
                                                ("© Copyright", "©"), ("® Registered", "®"), ("™ Trademark", "™"),
                                                ("• Bullet", "•"), ("§ Section", "§"), ("° Degree", "°"),
                                                ("€ Euro", "€"), ("£ Pound", "£"), ("¥ Yen", "¥")]
            .map { name, ch in (name, { c.insertText(ch) }) }
        return [
            Chrome.group("Pages", fluent, [
                Chrome.big(FluentSystemIcons.pageBreak, "Page Break", fluent) { c.insertPageBreak() },
            ]),
            Chrome.group("Tables", fluent, [_tableMenu(fluent)]),
            Chrome.group("Illustrations", fluent, [
                Chrome.big(FluentSystemIcons.image, "Pictures", fluent) { [session] in session.onInsertPicture?() },
                Chrome.big(FluentSystemIcons.shapes, "Shapes", fluent, enabled: false) {},
            ]),
            Chrome.group("Links", fluent, [
                Chrome.big(FluentSystemIcons.link, "Link", fluent) { [session] in session.onLink?() },
            ]),
            Chrome.group("Header & Footer", fluent, [Chrome.rows([
                Chrome.small(FluentSystemIcons.header, "Header", fluent) { [session] in session.onHeaderFooter?() },
                Chrome.small(FluentSystemIcons.footer, "Footer", fluent) { [session] in session.onHeaderFooter?() },
                Chrome.small(FluentSystemIcons.pageNumber, "Page Number", fluent) { c.togglePageNumbers() },
            ])]),
            Chrome.group("Text", fluent, [Chrome.rows([
                Chrome.small(FluentSystemIcons.document, "Date & Time", fluent) { [session] in
                    let f = DateFormatter()
                    f.dateStyle = .long
                    f.timeStyle = .none
                    c.insertText(f.string(from: Date()))
                    session.onStatus?("Inserted today's date")
                },
                Chrome.small(FluentSystemIcons.textT, "Text Box", fluent, enabled: false) {},
            ])]),
            Chrome.group("Symbols", fluent, [
                Chrome.menu(Text("Symbol"), Icon(FluentSystemIcons.symbols, size: Chrome.iconSize,
                                                 color: fluent.resources.textFillColorPrimary), fluent, symbols),
            ]),
        ]
    }

    /// Insert → Table: preset sizes, then the row commands and Delete
    /// Table, which light up inside a table.
    private func _tableMenu(_ fluent: FluentThemeData) -> Widget {
        let c = session.controller
        let inCell = c.isInCell
        var items: [MenuFlyoutItemBase] = []
        for (rows, cols) in [(2, 2), (3, 3), (4, 4), (3, 2), (5, 3)] {
            items.append(MenuFlyoutItem(text: Text("Insert \(rows) × \(cols) Table"),
                                        onPressed: { [session] in
                                            c.insertTable(rows: rows, columns: cols)
                                            session.onStatus?("Inserted a \(rows) × \(cols) table")
                                        }))
        }
        items.append(MenuFlyoutSeparator())
        items.append(MenuFlyoutItem(text: Text("Insert Row Above"), onPressed: inCell ? { c.insertRow(below: false) } : nil))
        items.append(MenuFlyoutItem(text: Text("Insert Row Below"), onPressed: inCell ? { c.insertRow(below: true) } : nil))
        items.append(MenuFlyoutItem(text: Text("Delete Row"), onPressed: inCell ? { c.deleteRow() } : nil))
        items.append(MenuFlyoutSeparator())
        items.append(MenuFlyoutItem(text: Text("Delete Table"), onPressed: inCell ? { c.deleteTable() } : nil))
        return DropDownButton(
            title: Text("Table"),
            leading: Icon(FluentSystemIcons.table, size: Chrome.iconSize, color: fluent.resources.textFillColorPrimary),
            items: items)
    }

    // MARK: Table Layout

    private func _tableLayout(_ fluent: FluentThemeData) -> [Widget] {
        let c = session.controller
        let rows = Chrome.group("Rows & Columns", fluent, [
            Chrome.rows([
                Chrome.small(FluentSystemIcons.chevronUp, "Insert Above", fluent) { c.insertRow(below: false) },
                Chrome.small(FluentSystemIcons.chevronDown, "Insert Below", fluent) { c.insertRow(below: true) },
                Chrome.small(FluentSystemIcons.delete, "Delete Row", fluent) { c.deleteRow() },
            ]),
            Chrome.gap(8),
            Chrome.rows([
                Chrome.small(FluentSystemIcons.chevronLeft, "Insert Left", fluent) { c.insertColumn(after: false) },
                Chrome.small(FluentSystemIcons.chevronRight, "Insert Right", fluent) { c.insertColumn(after: true) },
                Chrome.small(FluentSystemIcons.delete, "Delete Column", fluent) { c.deleteColumn() },
            ]),
        ])
        let size = Chrome.group("Cell Size", fluent, [
            Chrome.big(FluentSystemIcons.columns, "Distribute Columns", fluent) { c.distributeColumns() },
        ])
        let table = Chrome.group("Table", fluent, [
            Chrome.big(FluentSystemIcons.delete, "Delete Table", fluent) { c.deleteTable() },
        ])
        return [rows, size, table]
    }

    // MARK: Picture Format

    private func _pictureFormat(_ fluent: FluentThemeData) -> [Widget] {
        let c = session.controller
        let s = session.summary
        guard let i = s.imageIndex, let image = c.document.paragraphs[i].image else { return [] }
        let aspect = image.height / max(1, image.width)
        let size = Chrome.group("Size", fluent, [
            Chrome.rows([
                _spinner("Width", image.width, fluent, step: 6) { v in
                    c.setImageSize(at: i, width: v, height: v * aspect)
                },
                Chrome.vgap(2),
                _spinner("Height", image.height, fluent, step: 6) { v in
                    c.setImageSize(at: i, width: v / max(0.01, aspect), height: v)
                },
            ]),
            Chrome.gap(8),
            Chrome.rows([
                Chrome.small(FluentSystemIcons.pageFit, "Fit to Width", fluent) { [session] in
                    let w = session.pageSetup.contentWidth
                    c.setImageSize(at: i, width: w, height: w * aspect)
                },
                Chrome.small(FluentSystemIcons.image, "Original Size", fluent, enabled: s.imageHasNatural) {
                    if let nw = image.naturalWidth, let nh = image.naturalHeight {
                        c.setImageSize(at: i, width: nw, height: nh)
                    }
                },
                Chrome.small(FluentSystemIcons.zoomOut, "Half Size", fluent) {
                    c.setImageSize(at: i, width: image.width / 2, height: image.height / 2)
                },
            ]),
        ])
        let arrange = Chrome.group("Arrange", fluent, [
            Chrome.big(FluentSystemIcons.alignLeft, "Left", fluent) { c.setAlignment(.left) },
            Chrome.big(FluentSystemIcons.alignCenter, "Center", fluent) { c.setAlignment(.center) },
            Chrome.big(FluentSystemIcons.alignRight, "Right", fluent) { c.setAlignment(.right) },
        ])
        let remove = Chrome.group("Picture", fluent, [
            Chrome.big(FluentSystemIcons.delete, "Delete", fluent) { c.deleteForward() },
        ])
        return [size, arrange, remove]
    }

    // MARK: Layout

    private func _layout(_ fluent: FluentThemeData) -> [Widget] {
        let c = session.controller
        let setup = session.pageSetup
        func margins(_ name: String, _ v: Double, _ h: Double) -> (String, () -> Void) {
            (name, { [session] in
                var p = session.pageSetup
                p.marginTop = v; p.marginBottom = v; p.marginLeft = h; p.marginRight = h
                session.onPageSetup?(p)
            })
        }
        let marginChoices = [margins("Normal (1\")", 72, 72), margins("Narrow (0.5\")", 36, 36),
                             margins("Moderate (1\" × 0.75\")", 72, 54), margins("Wide (1\" × 2\")", 72, 144)]
        let orientation: [(String, () -> Void)] = [
            ("Portrait", { [session] in if session.pageSetup.isLandscape { session.onPageSetup?(session.pageSetup.rotated()) } }),
            ("Landscape", { [session] in if !session.pageSetup.isLandscape { session.onPageSetup?(session.pageSetup.rotated()) } }),
        ]
        func paper(_ name: String, _ base: PageSetup) -> (String, () -> Void) {
            (name, { [session] in
                var p = base
                p.marginTop = session.pageSetup.marginTop; p.marginBottom = session.pageSetup.marginBottom
                p.marginLeft = session.pageSetup.marginLeft; p.marginRight = session.pageSetup.marginRight
                session.onPageSetup?(session.pageSetup.isLandscape ? p.rotated() : p)
            })
        }
        let sizes = [paper("Letter (8.5 × 11 in)", .letter), paper("A4 (210 × 297 mm)", .a4),
                     paper("Legal (8.5 × 14 in)", PageSetup(width: 612, height: 1008))]
        let ps = c.currentParagraphStyle
        let pageSetup = Chrome.group("Page Setup", fluent, [
            Chrome.rows([
                Chrome.menu(Text("Margins"), Icon(FluentSystemIcons.margins, size: Chrome.iconSize,
                                                  color: fluent.resources.textFillColorPrimary), fluent, marginChoices),
                Chrome.vgap(2),
                Chrome.menu(Text(setup.isLandscape ? "Landscape" : "Portrait"),
                            Icon(FluentSystemIcons.orientation, size: Chrome.iconSize,
                                 color: fluent.resources.textFillColorPrimary), fluent, orientation),
            ]),
            Chrome.gap(),
            Chrome.rows([
                Chrome.menu(Text("Size"), Icon(FluentSystemIcons.onePage, size: Chrome.iconSize,
                                               color: fluent.resources.textFillColorPrimary), fluent, sizes),
                Chrome.vgap(2),
                Chrome.menu(Text("Columns"), Icon(FluentSystemIcons.columns, size: Chrome.iconSize,
                                                  color: fluent.resources.textFillColorPrimary), fluent,
                            [("One", {})]),
            ]),
        ])
        let paragraph = Chrome.group("Paragraph", fluent, [
            Chrome.rows([
                _spinner("Indent Left", ps.indentLeft, fluent, step: 18) { v in c.setIndents(left: v) },
                Chrome.vgap(2),
                _spinner("Indent Right", ps.indentRight, fluent, step: 18) { v in c.setIndents(right: v) },
            ]),
            Chrome.gap(8),
            Chrome.rows([
                _spinner("Space Before", ps.spaceBefore, fluent, step: 6) { v in c.setParagraphSpacing(before: v) },
                Chrome.vgap(2),
                _spinner("Space After", ps.spaceAfter, fluent, step: 6) { v in c.setParagraphSpacing(after: v) },
            ]),
        ])
        return [pageSetup, paragraph]
    }

    /// A labelled value with −/+ buttons: NumberBox without typing, which
    /// keeps keyboard focus in the document.
    private func _spinner(_ label: String, _ value: Double, _ fluent: FluentThemeData, step: Double,
                          onChanged: @escaping (Double) -> Void) -> Widget {
        Chrome.row([
            SizedBox(width: 84, height: nil, child: Text(label, style: fluent.typography.caption)),
            Chrome.icon(FluentSystemIcons.chevronDown, "Less", fluent) { onChanged(max(0, value - step)) },
            SizedBox(width: 44, height: nil, child: Text("\(Int(value.rounded())) pt", style: fluent.typography.caption)),
            Chrome.icon(FluentSystemIcons.chevronUp, "More", fluent) { onChanged(value + step) },
        ])
    }

    // MARK: View

    private func _view(_ fluent: FluentThemeData) -> [Widget] {
        let views = Chrome.group("Views", fluent, [
            _viewTile(FluentSystemIcons.onePage, "Print Layout", session.viewMode == .printLayout, fluent) { [session] in session.onViewMode?(.printLayout) },
            _viewTile(FluentSystemIcons.document, "Web Layout", session.viewMode == .webLayout, fluent) { [session] in session.onViewMode?(.webLayout) },
            _viewTile(FluentSystemIcons.readMode, "Read Mode", session.viewMode == .readMode, fluent) { [session] in session.onViewMode?(.readMode) },
        ])
        let show = Chrome.group("Show", fluent, [
            Chrome.textToggle("Ruler", session.showRuler, fluent) { [session] in session.onToggleRuler?() },
            Chrome.gap(),
            Chrome.textToggle("Navigation Pane", session.showNavigation, fluent) { [session] in session.onToggleNavigation?() },
        ])
        let zoom = Chrome.group("Zoom", fluent, [
            Chrome.big(FluentSystemIcons.zoomIn, "Zoom In", fluent) { [session] in session.onZoom?(session.zoom + 0.1) },
            Chrome.big(FluentSystemIcons.zoomOut, "Zoom Out", fluent) { [session] in session.onZoom?(session.zoom - 0.1) },
            Chrome.big(FluentSystemIcons.pageFit, "100%", fluent) { [session] in session.onZoom?(1.0) },
        ])
        return [views, show, zoom]
    }

    private func _viewTile(_ icon: IconData, _ label: String, _ on: Bool, _ fluent: FluentThemeData,
                           action: @escaping () -> Void) -> Widget {
        let color = on ? fluent.resources.textOnAccentFillColorPrimary : fluent.resources.textFillColorPrimary
        return Padding(padding: EdgeInsets(left: 0, top: 0, right: 4, bottom: 0), child: ToggleButton(
            checked: on, onChanged: { _ in action() },
            child: Column(mainAxisAlignment: .center, crossAxisAlignment: .center, children: [
                Icon(icon, size: Chrome.bigIconSize, color: color),
                Chrome.vgap(4),
                Text(label, style: fluent.typography.caption?.copyWith(color: color)),
            ])))
    }
}
