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
    case home, insert, layout, review, view
    /// Contextual: shown while a picture is selected or the caret is in a
    /// table, as Word does.
    case pictureFormat, tableLayout
    /// Slides only; contextual while a chart is selected.
    case chartDesign
    /// Slides only.
    case design, transitions, slideShow, animations
    /// Sheets only.
    case formulas, data

    /// The tabs a kind shows, in strip order (contextual ones aside).
    static func strip(for kind: DocumentKind) -> [RibbonTab] {
        switch kind {
        case .document: return [.home, .insert, .layout, .review, .view]
        case .presentation: return [.home, .insert, .design, .transitions, .animations, .slideShow, .review, .view]
        case .workbook: return [.home, .insert, .formulas, .data, .review, .view]
        }
    }

    var title: String {
        switch self {
        case .home: return "Home"
        case .insert: return "Insert"
        case .layout: return "Layout"
        case .review: return "Review"
        case .view: return "View"
        case .pictureFormat: return "Picture Format"
        case .tableLayout: return "Table Layout"
        case .chartDesign: return "Chart Design"
        case .design: return "Design"
        case .transitions: return "Transitions"
        case .slideShow: return "Slide Show"
        case .animations: return "Animations"
        case .formulas: return "Formulas"
        case .data: return "Data"
        }
    }

    var isContextual: Bool { self == .pictureFormat || self == .tableLayout || self == .chartDesign }
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
                        color: OfficeAppearance.surface(fluent),
                        border: Border(bottom: BorderSide(color: OfficeAppearance.border(fluent), width: 1))),
                    child: Row(crossAxisAlignment: .stretch, children: [
                        Expanded(child: SingleChildScrollView(scrollDirection: .horizontal,
                            child: Row(crossAxisAlignment: .stretch, children: _groups(fluent)))),
                        _collapseButton(fluent),
                    ]))))
        }
        return Column(crossAxisAlignment: .stretch, children: children)
    }

    // MARK: Tab strip

    private func _strip(_ fluent: FluentThemeData) -> Widget {
        var items: [Widget] = [_fileTab(fluent)]
        for t in RibbonTab.strip(for: session.kind) { items.append(_tab(t, fluent)) }
        let slidePicture = session.deck?.selection.contains { $0.picture != nil } ?? false
        if session.summary.imageIndex != nil || slidePicture { items.append(_tab(.pictureFormat, fluent)) }
        if session.summary.inCell { items.append(_tab(.tableLayout, fluent)) }
        if session.deck?.selectedChart != nil { items.append(_tab(.chartDesign, fluent)) }
        return ColoredBox(color: OfficeAppearance.surface(fluent),
            child: SizedBox(width: nil, height: 44, child: SingleChildScrollView(scrollDirection: .horizontal,
                child: Padding(padding: EdgeInsets(left: 12, top: 5, right: 12, bottom: 0),
                    child: Row(crossAxisAlignment: .end, children: items)))))
    }

    /// File is a quiet pill in the chrome's own fill, bold like a selected
    /// tab — deliberately not a saturated brand block.
    private func _fileTab(_ fluent: FluentThemeData) -> Widget {
        GestureDetector(
            onTap: { [session] in session.onBackstage?(true) },
            child: Padding(padding: EdgeInsets(left: 0, top: 0, right: 6, bottom: 4), child: DecoratedBox(
                decoration: BoxDecoration(color: fluent.accentColor.defaultBrushFor(fluent.brightness).withOpacity(0.08),
                                          border: Border.all(color: OfficeAppearance.border(fluent), width: 1),
                                          borderRadius: BorderRadius.all(Radius(circular: 4))),
                child: Padding(padding: EdgeInsets(left: 14, top: 5, right: 14, bottom: 5),
                               child: Text("File", style: fluent.typography.bodyStrong?.copyWith(
                                   color: fluent.accentColor.defaultBrushFor(fluent.brightness)))))))
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
                                ? fluent.typography.bodyStrong?.copyWith(color: accent)
                                : fluent.typography.body?.copyWith(color: OfficeAppearance.secondary(fluent)))),
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
        if session.kind == .presentation, let groups = slidesGroups(fluent) { return groups }
        if session.kind == .workbook, let groups = sheetsGroups(fluent) { return groups }
        switch tab {
        case .home: return _home(fluent)
        case .insert: return _insert(fluent)
        case .layout: return _layout(fluent)
        case .view: return _view(fluent)
        case .pictureFormat: return _pictureFormat(fluent)
        case .tableLayout: return _tableLayout(fluent)
        case .review: return _review(fluent)
        case .design, .transitions, .slideShow, .chartDesign, .animations, .formulas, .data: return []
        }
    }

    // MARK: Review

    /// Spelling and Word Count are real; the rest of Word's Review tab
    /// (track changes, comments) and the Draw and References tabs are one
    /// honest note rather than five rows of greyed buttons.
    func _review(_ fluent: FluentThemeData) -> [Widget] {
        let c = session.controller
        let proofing = Chrome.group("Proofing", fluent, [
            Chrome.bigToggle(FluentSystemIcons.textGrammarWand, "Spelling", session.checkSpelling, fluent) { [session] in session.onToggleSpelling?() },
            Chrome.big(FluentSystemIcons.textT, "Word Count", fluent) { [session] in
                let d = c.document
                session.onStatus?("\(d.wordCount) words, \(d.characterCount) characters, \(d.paragraphs.count) paragraphs")
            },
        ])
        let later = Chrome.group("Coming later", fluent, [
            Padding(padding: EdgeInsets(left: 4, top: 6, right: 4, bottom: 0), child: SizedBox(width: 300, height: nil, child: Text(
                "Track changes, comments, footnotes, a table of contents, shapes, text boxes and drawing are not in this build.",
                style: fluent.typography.caption?.copyWith(color: fluent.resources.textFillColorSecondary)))),
        ])
        return [proofing, later]
    }

    // MARK: Home

    private func _home(_ fluent: FluentThemeData) -> [Widget] {
        let c = session.controller
        let s = session.summary
        let fontParagraph = fontAndParagraphGroups(fluent)
        let font = fontParagraph[0]
        let paragraph = fontParagraph[1]
        let clipboard = clipboardGroup(fluent)

        // The gallery: four tiles, then every style of the sheet in a menu.
        let sheet = c.document.styles
        var tiles: [Widget] = []
        for id in [RichNamedStyle.normalId, "Title", RichNamedStyle.headingId(1), RichNamedStyle.headingId(2)] {
            guard let entry = sheet[id] else { continue }
            tiles.append(_styleTile(entry, s.styleId == id, fluent) { c.setNamedStyle(id) })
        }
        var more: [MenuFlyoutItemBase] = sheet.styles.map { entry in
            MenuFlyoutItem(text: Text(entry.name, style: _preview(entry, fluent, cap: Self._menuPreviewCap)),
                           leading: Icon(s.styleId == entry.id ? FluentSystemIcons.check : FluentSystemIcons.textT,
                                         size: Chrome.iconSize, color: fluent.resources.textFillColorPrimary),
                           onPressed: { c.setNamedStyle(entry.id) })
        }
        if let current = sheet[s.styleId] {
            more.append(MenuFlyoutSeparator())
            more.append(MenuFlyoutItem(text: Text("Update \(current.name) to Match Selection"),
                                       onPressed: { [session] in
                                           c.updateStyleToMatchSelection(current.id)
                                           session.onStatus?("\(current.name) now matches the selection")
                                       }))
            more.append(MenuFlyoutItem(text: Text("Modify \(current.name)…"),
                                       onPressed: { [session] in session.onModifyStyle?(current.id) }))
        }
        // The gallery sits in one bordered box, as Word's does.
        let gallery = DecoratedBox(
            decoration: BoxDecoration(border: Border.all(color: OfficeAppearance.border(fluent), width: 1),
                                      borderRadius: BorderRadius.all(Radius(circular: 4))),
            child: Padding(padding: EdgeInsets(left: 2, top: 2, right: 2, bottom: 2),
                           child: Row(mainAxisSize: .min, crossAxisAlignment: .center, children: tiles)))
        let styles = Chrome.group("Styles", fluent, [
            gallery, Chrome.gap(2),
            FlatButton(child: Chrome.chevron(fluent), tip: "All styles", width: 16, height: 58, menu: more),
        ])

        let editing = Chrome.group("Editing", fluent, [Chrome.rows([
            Chrome.small(FluentSystemIcons.search, "Find", fluent) { [session] in session.onFind?(false) },
            Chrome.small(FluentSystemIcons.textGrammarWand, "Replace", fluent) { [session] in session.onFind?(true) },
            Chrome.small(FluentSystemIcons.textT, "Select All", fluent) { c.selectAll() },
        ])])

        return [clipboard, font, paragraph, styles, editing]
    }

    /// Paste, Cut, Copy and Format Painter, acting on the session's text.
    func clipboardGroup(_ fluent: FluentThemeData) -> Widget {
        let c = session.controller
        let s = session.summary
        return Chrome.group("Clipboard", fluent, [
            Chrome.big(FluentSystemIcons.paste, "Paste", fluent) { [session] in session.onPaste?(false) },
            Chrome.gap(2),
            Chrome.rows([
                Chrome.small(FluentSystemIcons.cut, "Cut", fluent, enabled: s.hasSelection) { [session] in
                    if let d = c.cutSelectionData() { Clipboard.setData(d) }
                    session.onStatus?("Cut")
                },
                Chrome.small(FluentSystemIcons.copy, "Copy", fluent, enabled: s.hasSelection) { [session] in
                    if let d = c.copySelectionData() { Clipboard.setData(d) }
                    session.onStatus?("Copied")
                },
                Chrome.small(FluentSystemIcons.paintBrush, s.painting ? "Painting…" : "Format Painter", fluent) { [session] in session.onFormatPainter?() },
            ]),
        ])
    }

    /// Font and Paragraph: Writer's Home groups, shared by Slides, acting on
    /// whatever text the session points at.
    func fontAndParagraphGroups(_ fluent: FluentThemeData) -> [Widget] {
        let c = session.controller
        let s = session.summary
        let sizes: [Double] = [8, 9, 10, 11, 12, 14, 16, 18, 20, 24, 28, 36, 48, 72]
        let currentSize = session.effectiveFontSize
        let fontRow1 = Chrome.row([
            SizedBox(width: 140, height: nil, child: ComboBox<String>(
                value: session.effectiveFontFamily,
                // A document's own font, whatever it is, is shown by name;
                // it draws with the nearest shipped face.
                items: OfficeFonts.families(including: session.effectiveFontFamily).map { f in
                    ComboBoxItem<String>(value: f, child: Text(f, style: fluent.typography.body?.copyWith(color: nil)))
                },
                onChanged: { f in c.setFontFamily(f) })),
            Chrome.gap(),
            SizedBox(width: 72, height: nil, child: ComboBox<Double>(
                value: sizes.contains(currentSize) ? currentSize : nil,
                items: sizes.map { n in ComboBoxItem<Double>(value: n, child: Text(Self._fmt(n))) },
                onChanged: { n in if let n { c.setFontSize(n) } },
                placeholder: Text(Self._fmt(currentSize)))),
            Chrome.gap(6),
            FlatButton(child: Chrome.sizeArrowIcon(up: true, fluent), tip: "Grow Font (⌘])") { [session] in c.stepFontSize(1, base: session.effectiveFontSize) },
            FlatButton(child: Chrome.sizeArrowIcon(up: false, fluent), tip: "Shrink Font (⌘[)") { [session] in c.stepFontSize(-1, base: session.effectiveFontSize) },
            Chrome.gap(2),
            Chrome.menu(nil, Icon(FluentSystemIcons.textChangeCase, size: Chrome.iconSize,
                                  color: fluent.resources.textFillColorPrimary), fluent, [
                ("Sentence case.", { c.changeCase(.sentence) }),
                ("lowercase", { c.changeCase(.lower) }),
                ("UPPERCASE", { c.changeCase(.upper) }),
                ("Capitalize Each Word", { c.changeCase(.capitalizeWords) }),
                ("tOGGLE cASE", { c.changeCase(.toggle) }),
            ]),
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
                             colors: OfficeColors.text, none: "Automatic",
                             more: { [session] in session.onMoreColors?() }) { color in c.setTextColor(color) },
        ])
        let font = Chrome.group("Font", fluent, [Chrome.rows([fontRow1, Chrome.vgap(4), fontRow2])])

        let spacingChoices: [(String, () -> Void)] = [1.0, 1.15, 1.5, 2.0, 2.5, 3.0].map { m in
            (String(printf: "%.2f", m), { c.setLineSpacing(m) })
        }
        let paraRow1 = Chrome.row([
            Chrome.toggle(FluentSystemIcons.bulletList, "Bullets", s.list == .bullet, fluent) { c.toggleList(.bullet) },
            _listLibrary("Bullet Library", ListLevelFormat.bulletLibrary, c, fluent),
            Chrome.toggle(FluentSystemIcons.numberList, "Numbering", s.list == .numbered, fluent) { c.toggleList(.numbered) },
            _listLibrary("Numbering Library", ListLevelFormat.numberingLibrary, c, fluent),
            Chrome.gap(2),
            Chrome.icon(FluentSystemIcons.indentDecrease, "Decrease Indent", fluent) { c.indent(-1) },
            Chrome.icon(FluentSystemIcons.indentIncrease, "Increase Indent", fluent) { c.indent(1) },
            Chrome.gap(2),
            Chrome.toggle(FluentSystemIcons.paragraphMarks, "Show/Hide ¶ (⌘⇧8)", session.showMarks, fluent) { [session] in session.onToggleMarks?() },
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
        return [font, paragraph]
    }

    /// A gallery tile: the style's look on "AaBb", its name under it.
    private func _styleTile(_ entry: RichNamedStyle, _ on: Bool, _ fluent: FluentThemeData,
                            action: @escaping () -> Void) -> Widget {
        let look = _preview(entry, fluent, cap: 18, onAccent: on)
        return FlatButton(child: Column(mainAxisAlignment: .center, crossAxisAlignment: .center, children: [
                        Text("AaBb", style: look),
                        Chrome.vgap(2),
                        Text(entry.name, style: fluent.typography.caption, softWrap: false),
                    ]), checked: on, width: 74, height: 54, action: action)
    }

    /// Menu previews cap at 14pt. This used to be 13 because exactly 14pt
    /// drew with stretched letters — the engine's and the bridge's copies
    /// of Skia handing out the same typeface IDs, fixed in the bridge
    /// (engine: "keep this library's typeface IDs out of the engine's
    /// range"). OFFICE_STYLE_PREVIEW_CAP overrides it for a re-check.
    private static let _menuPreviewCap = Double(ProcessInfo.processInfo.environment["OFFICE_STYLE_PREVIEW_CAP"] ?? "") ?? 14

    /// The style's character look, sized to fit chrome.
    private func _preview(_ entry: RichNamedStyle, _ fluent: FluentThemeData, cap: Double,
                          onAccent: Bool = false) -> Flutter.TextStyle {
        let size = min(cap, (entry.char.fontSize ?? session.theme.fontSize) * 0.85)
        let color = onAccent ? fluent.accentColor.defaultBrushFor(fluent.brightness)
            : entry.char.color ?? OfficeAppearance.ink(fluent)
        return Flutter.TextStyle(color: color, fontSize: max(9, size),
                                 fontWeight: entry.char.bold ? .bold : .normal,
                                 fontStyle: entry.char.italic ? .italic : .normal,
                                 fontFamily: (entry.char.fontFamily ?? session.theme.fontFamily).map(OfficeFonts.substitute))
    }

    private static func _fmt(_ n: Double) -> String {
        n == n.rounded() ? String(Int(n)) : String(printf: "%.1f", n)
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
                    c.insertText(Backstage.todayLongDate())
                    session.onStatus?("Inserted today's date")
                },
            ])]),
            Chrome.group("Symbols", fluent, [
                Chrome.menu(Text("Symbol"), Icon(FluentSystemIcons.symbols, size: Chrome.iconSize,
                                                 color: fluent.resources.textFillColorPrimary), fluent, symbols),
            ]),
        ]
    }

    /// Insert → Table: preset sizes, then the row commands and Delete
    /// Table, which light up inside a table.
    /// The chevron beside Bullets or Numbering: Word's library of formats,
    /// each previewed as its first three items.
    private func _listLibrary(_ tip: String, _ library: [ListLevelFormat],
                              _ c: RichDocumentController, _ fluent: FluentThemeData) -> Widget {
        let level = c.document.paragraphs[c.selection.focus.paragraph].style.listLevel
        let current = c.currentListFormat?.asLibraryEntry(atLevel: level)
        let items: [MenuFlyoutItemBase] = library.map { f in
            let preview = f.format == .bullet ? "\(f.text)  \(f.text)  \(f.text)" : "\(f.sample(1))  \(f.sample(2))  \(f.sample(3))"
            return MenuFlyoutItem(text: Text(preview), onPressed: { c.setListFormat(f) }, selected: f == current)
        }
        return Chrome.splitChevron(tip, fluent, items: items)
    }

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
        return Chrome.menuButton(FluentSystemIcons.table, "Table", nil, fluent, items: items)
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
        let merge = Chrome.group("Merge", fluent, [Chrome.rows([
            Chrome.small(FluentSystemIcons.table, "Merge Cells", fluent,
                         enabled: c.selection.block != nil || c.selectedCellsInRow.count > 1 || c.selectedCellsInColumn.count > 1) { c.mergeCells() },
            Chrome.small(FluentSystemIcons.columns, "Split Cell", fluent,
                         enabled: (c.currentCell?.span ?? 1) > 1 || (c.currentCell?.rowSpan ?? 1) > 1) { c.splitCell() },
        ])])
        let size = Chrome.group("Cell Size", fluent, [
            Chrome.big(FluentSystemIcons.columns, "Distribute Columns", fluent) { c.distributeColumns() },
        ])
        let style = c.currentTableStyle ?? TableStyle()
        let look = Chrome.group("Table Style", fluent, [
            Chrome.bigToggle(FluentSystemIcons.table, "Borders", style.borders, fluent) { c.setTableStyle { $0.borders.toggle() } },
            Chrome.bigToggle(FluentSystemIcons.header, "Header Row", style.headerRow, fluent) { c.setTableStyle { $0.headerRow.toggle() } },
        ])
        let table = Chrome.group("Table", fluent, [
            Chrome.big(FluentSystemIcons.delete, "Delete Table", fluent) { c.deleteTable() },
        ])
        return [rows, merge, size, look, table]
    }

    // MARK: Picture Format

    private func _pictureFormat(_ fluent: FluentThemeData) -> [Widget] {
        let c = session.controller
        let s = session.summary
        guard let i = s.imageIndex, let image = c.document.paragraphs[i].image else { return [] }
        let aspect = image.height / max(1, image.width)
        let size = Chrome.group("Size", fluent, [
            Chrome.rows([
                Chrome.spinner("Width", image.width, fluent, step: 6) { v in
                    c.setImageSize(at: i, width: v, height: v * aspect)
                },
                Chrome.vgap(2),
                Chrome.spinner("Height", image.height, fluent, step: 6) { v in
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
                Chrome.menu(Text(setup.columns > 1 ? "\(setup.columns) Columns" : "Columns"),
                            Icon(FluentSystemIcons.columns, size: Chrome.iconSize,
                                 color: fluent.resources.textFillColorPrimary), fluent,
                            [("One", { [session] in var p = session.pageSetup; p.columns = 1; session.onPageSetup?(p) }),
                             ("Two", { [session] in var p = session.pageSetup; p.columns = 2; session.onPageSetup?(p) }),
                             ("Three", { [session] in var p = session.pageSetup; p.columns = 3; session.onPageSetup?(p) })]),
            ]),
        ])
        let paragraph = Chrome.group("Paragraph", fluent, [
            Chrome.rows([
                Chrome.spinner("Indent Left", ps.indentLeft, fluent, step: 18) { v in c.setIndents(left: v) },
                Chrome.vgap(2),
                Chrome.spinner("Indent Right", ps.indentRight, fluent, step: 18) { v in c.setIndents(right: v) },
            ]),
            Chrome.gap(8),
            Chrome.rows([
                Chrome.spinner("Space Before", ps.spaceBefore, fluent, step: 6) { v in c.setParagraphSpacing(before: v) },
                Chrome.vgap(2),
                Chrome.spinner("Space After", ps.spaceAfter, fluent, step: 6) { v in c.setParagraphSpacing(after: v) },
            ]),
        ])
        return [pageSetup, paragraph]
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
        Chrome.bigToggle(icon, label, on, fluent, action: action)
    }
}
