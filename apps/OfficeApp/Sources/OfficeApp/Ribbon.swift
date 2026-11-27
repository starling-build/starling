// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The ribbon: Word's tab strip (File, Home, Insert, Draw, Layout,
// References, Review, View) over one row of groups per tab. File is not a
// tab but the door to Backstage. The Home tab is complete; Insert, Layout
// and View carry what the document model supports today; Draw, References
// and Review are placeholders that keep the strip Word-shaped.

import Flutter
import OfficeText
import FlutterSwiftBridge
import FluentSystemIcons
import CupertinoIcons
import Foundation

enum RibbonTab: Int, CaseIterable {
    case home, insert, layout, references, review, view
    /// Contextual: shown while a picture is selected or the caret is in a
    /// table, as Word does.
    case pictureFormat, shapeFormat, tableLayout, tableDesign
    /// Slides only; contextual while a chart is selected.
    case chartDesign
    /// Slides only; shown while Slide Master view is open.
    case slideMaster
    /// Slides only.
    case design, transitions, slideShow, animations
    /// Sheets only.
    case formulas, data

    /// The tabs a kind shows, in strip order (contextual ones aside).
    static func strip(for kind: DocumentKind) -> [RibbonTab] {
        switch kind {
        case .document: return [.home, .insert, .layout, .references, .review, .view]
        case .presentation: return [.home, .insert, .design, .transitions, .animations, .slideShow, .review, .view]
        case .workbook: return [.home, .insert, .layout, .formulas, .data, .review, .view]
        }
    }

    var title: String {
        switch self {
        case .home: return "Home"
        case .insert: return "Insert"
        case .layout: return "Layout"
        case .references: return "References"
        case .review: return "Review"
        case .view: return "View"
        case .pictureFormat: return "Picture Format"
        case .shapeFormat: return "Shape Format"
        case .tableLayout: return "Table Layout"
        case .tableDesign: return "Table Design"
        case .chartDesign: return "Chart Design"
        case .slideMaster: return "Slide Master"
        case .design: return "Design"
        case .transitions: return "Transitions"
        case .slideShow: return "Slide Show"
        case .animations: return "Animations"
        case .formulas: return "Formulas"
        case .data: return "Data"
        }
    }

    var isContextual: Bool { self == .pictureFormat || self == .shapeFormat || self == .tableLayout || self == .tableDesign || self == .chartDesign || self == .slideMaster }
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
        KeyboardRegion(name: "ribbon", child: KeyTipLayer(child: _body(context)))
    }

    private func _body(_ context: any BuildContext) -> Widget {
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
                        Expanded(child: RibbonFit(key: ValueKey("\(session.kind)/\(tab)"), groups: _groups(fluent))),
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
        if session.summary.imageIndex != nil || slidePicture { items.append(_tab(session.imageTab, fluent)) }
        if session.deck?.selectedTableOptions != nil { items.append(_tab(.tableDesign, fluent)) }
        if session.summary.inCell { items.append(_tab(.tableDesign, fluent)); items.append(_tab(.tableLayout, fluent)) }
        if session.deck?.selectedChart != nil { items.append(_tab(.chartDesign, fluent)) }
        if session.deck?.inMasterView ?? false { items.insert(_tab(.slideMaster, fluent), at: 1) }
        return ColoredBox(color: OfficeAppearance.surface(fluent),
            child: SizedBox(width: nil, height: OfficeAppearance.rowHeight(44), child: SingleChildScrollView(scrollDirection: .horizontal,
                child: Padding(padding: EdgeInsets(left: 12, top: 5, right: 12, bottom: 0),
                    child: Row(crossAxisAlignment: .end, children: items)))))
    }

    /// File is a quiet pill in the chrome's own fill, bold like a selected
    /// tab — deliberately not a saturated brand block.
    private func _fileTab(_ fluent: FluentThemeData) -> Widget {
        let accent = fluent.accentColor.defaultBrushFor(fluent.brightness)
        return HoverButton(
            builder: { _, states in
                Padding(padding: EdgeInsets(left: 0, top: 0, right: 6, bottom: 4), child: DecoratedBox(
                    decoration: BoxDecoration(color: accent.withOpacity(0.08),
                                              border: Border.all(color: states.contains(.focused) ? accent : OfficeAppearance.border(fluent),
                                                                 width: states.contains(.focused) ? 2 : 1),
                                              borderRadius: BorderRadius.all(Radius(circular: 4))),
                    child: Padding(padding: EdgeInsets(left: 14, top: 5, right: 14, bottom: 5),
                                   child: Text("File", style: fluent.typography.bodyStrong?.copyWith(color: accent)))))
            },
            onPressed: { [session] in session.unsavedPrompt = nil; session.onBackstage?(true) },
            semanticLabel: "File")
    }

    private func _tab(_ t: RibbonTab, _ fluent: FluentThemeData) -> Widget {
        let selected = t == tab && !collapsed
        let accent = fluent.accentColor.defaultBrushFor(fluent.brightness)
        let underline = selected ? accent : Color(0x00000000)
        return HoverButton(
            builder: { _, states in
                let ring = states.contains(.focused)
                return Padding(padding: EdgeInsets(left: 2, top: 0, right: 2, bottom: 0), child: Column(
                    mainAxisAlignment: .end, crossAxisAlignment: .center, children: [
                        DecoratedBox(
                            decoration: BoxDecoration(border: Border.all(color: ring ? accent : Color(0x00000000), width: 2),
                                                      borderRadius: BorderRadius.all(Radius(circular: 4))),
                            child: Padding(padding: EdgeInsets(left: 10, top: 6, right: 10, bottom: 4),
                                           child: Text(t.title, style: selected
                                               ? fluent.typography.bodyStrong?.copyWith(color: accent)
                                               : fluent.typography.body?.copyWith(color: OfficeAppearance.secondary(fluent))))),
                        SizedBox(width: 36, height: 3, child: DecoratedBox(decoration: BoxDecoration(
                            color: underline, borderRadius: BorderRadius.all(Radius(circular: 2))))),
                    ]))
            },
            onPressed: { [onTab, onCollapse, collapsed] in
                if collapsed { onCollapse() }
                onTab(t)
            },
            semanticLabel: t.title)
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
        case .pictureFormat: return _pictureFormat(fluent, shape: session.imageTab == .shapeFormat)
        case .shapeFormat: return _pictureFormat(fluent, shape: true)
        case .tableLayout: return _tableLayout(fluent)
        case .references: return _references(fluent)
        case .review: return _review(fluent)
        case .tableDesign: return session.summary.inCell ? _tableDesign(fluent) : []
        case .design, .transitions, .slideShow, .chartDesign, .slideMaster, .animations, .formulas, .data: return []
        }
    }

    // MARK: References

    /// W-FN-1: footnotes and endnotes. (The other References groups arrive with their own rows.)
    func _references(_ fluent: FluentThemeData) -> [Widget] {
        let automatic1 = ContentsOptions(), automatic2 = ContentsOptions()
        return [Chrome.group("Table of Contents", fluent, [
            Chrome.menuButton(FluentSystemIcons.textT, "Table of Contents", nil, fluent, items: [
                MenuFlyoutItem(text: Text("Automatic Table (dot leader)"), onPressed: { [session] in session.onInsertContents?(automatic1) }),
                MenuFlyoutItem(text: Text("Automatic Table (no leader)"), onPressed: { [session] in
                    var o = automatic2; o.tabLeader = nil; session.onInsertContents?(o) }),
                MenuFlyoutItem(text: Text("Custom Table of Contents…"), onPressed: { [session] in session.onContentsDialog?() }),
            ]),
            Chrome.menuButton(FluentSystemIcons.textT, "Update Table", nil, fluent, items: [
                MenuFlyoutItem(text: Text("Update page numbers only"), onPressed: { [session] in session.onUpdateContents?(true) }),
                MenuFlyoutItem(text: Text("Update entire table"), onPressed: { [session] in session.onUpdateContents?(false) }),
            ]),
        ]), Chrome.group("Footnotes", fluent, [
            Chrome.big(FluentSystemIcons.textT, "Insert Footnote", fluent) { [session] in session.onInsertNote?(.footnote) },
            Chrome.big(FluentSystemIcons.textT, "Insert Endnote", fluent) { [session] in session.onInsertNote?(.endnote) },
            Chrome.big(FluentSystemIcons.textT, "Edit Note", fluent) { [session] in session.onEditNote?() },
        ])]
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
        more.append(MenuFlyoutSeparator())
        more.append(MenuFlyoutItem(text: Text("Create a Style…"),
                                   onPressed: { [session] in session.onNewStyleDialog?() }))
        more.append(MenuFlyoutItem(text: Text("Styles Pane"), onPressed: { [session] in session.onToggleStyles?() }))
        if let current = sheet[s.styleId] {
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
            FlatButton(child: Chrome.chevron(fluent), tip: "All styles", width: 16, height: OfficeAppearance.rowHeight(58), menu: more),
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
            Chrome.big(FluentSystemIcons.paste, "Paste", fluent) { [session] in
                if session.onShapePaste?() == true { return }
                session.onPaste?(false)
            },
            Chrome.splitChevron("Paste Options", fluent, items: [
                MenuFlyoutItem(text: Text("Keep Source Formatting"), onPressed: { [session] in session.onPasteMode?(.keepSource) }),
                MenuFlyoutItem(text: Text("Merge Formatting"), onPressed: { [session] in session.onPasteMode?(.mergeFormatting) }),
                MenuFlyoutItem(text: Text("Picture"), onPressed: { [session] in session.onPasteMode?(.picture) }),
                MenuFlyoutItem(text: Text("Keep Text Only"), onPressed: { [session] in session.onPasteMode?(.textOnly) }),
            ]),
            Chrome.gap(2),
            Chrome.rows([
                Chrome.small(FluentSystemIcons.cut, "Cut", fluent, enabled: s.hasSelection || session.deck?.selection.isEmpty == false) { [session] in
                    if session.deck?.selection.isEmpty == false, session.onShapeCut?() == true { return }
                    if let d = c.cutSelectionData() { Clipboard.setData(d) }
                    session.onStatus?("Cut")
                },
                Chrome.small(FluentSystemIcons.copy, "Copy", fluent, enabled: s.hasSelection || session.deck?.selection.isEmpty == false) { [session] in
                    if session.deck?.selection.isEmpty == false, session.onShapeCopy?() == true { return }
                    if let d = c.copySelectionData() { Clipboard.setData(d) }
                    session.onStatus?("Copied")
                },
            ] + (session.deck != nil ? [] : [   // a deck has no painter yet
                Chrome.small(FluentSystemIcons.paintBrush, s.painting ? "Painting…" : "Format Painter", fluent) { [session] in session.onFormatPainter?() },
            ])),
        ])
    }

    /// Font and Paragraph: Writer's Home groups, shared by Slides, acting on
    /// whatever text the session points at.
    func fontAndParagraphGroups(_ fluent: FluentThemeData) -> [Widget] {
        let c = session.controller
        let s = session.summary
        let sizes: [Double] = [8, 9, 10, 11, 12, 14, 16, 18, 20, 24, 28, 36, 48, 72]
        let currentSize = session.effectiveFontSize
        let fontRow1 = Chrome.row(([
            SizedBox(width: 140, height: nil, child: ComboBox<String>(
                value: session.effectiveFontFamily,
                // A document's own font, whatever it is, is shown by name;
                // it draws with the nearest shipped face.
                items: OfficeFonts.families(including: session.effectiveFontFamily).map { f in
                    ComboBoxItem<String>(value: f, child: Text(f, style: fluent.typography.body?.copyWith(color: nil)))
                },
                onChanged: { f in c.setFontFamily(f) }, semanticLabel: "Font")),
            Chrome.gap(),
            FontSizeBox(size: currentSize, sizes: sizes, onSize: { n in c.setFontSize(n) }),
            Chrome.gap(6),
            FlatButton(child: Chrome.sizeArrowIcon(up: true, fluent), tip: "Grow Font (⌘])".keys, keepsPopupOpen: true) { [session] in c.stepFontSize(1, base: session.effectiveFontSize) },
            FlatButton(child: Chrome.sizeArrowIcon(up: false, fluent), tip: "Shrink Font (⌘[)".keys, keepsPopupOpen: true) { [session] in c.stepFontSize(-1, base: session.effectiveFontSize) },
            Chrome.gap(2),
            Chrome.menu(nil, Icon(FluentSystemIcons.textChangeCase, size: Chrome.iconSize,
                                  color: fluent.resources.textFillColorPrimary), fluent, [
                ("Sentence case.", { c.changeCase(.sentence) }),
                ("lowercase", { c.changeCase(.lower) }),
                ("UPPERCASE", { c.changeCase(.upper) }),
                ("Capitalize Each Word", { c.changeCase(.capitalizeWords) }),
                ("tOGGLE cASE", { c.changeCase(.toggle) }),
            ], tip: "Change Case"),
            Chrome.icon(FluentSystemIcons.textClearFormatting, "Clear All Formatting", fluent) { c.clearFormatting() },
        ] + (session.onFontDialog == nil ? [] : [   // Writer only: Slides has no Font dialog yet
            Chrome.icon(FluentSystemIcons.textFont, "Font… (⌘D)", fluent) { [session] in session.onFontDialog?() },
        ])))
        let fontRow2 = Chrome.row([
            Chrome.toggle(FluentSystemIcons.textBold, "Bold (⌘B)".keys, s.bold, fluent) { c.toggleBold() },
            Chrome.toggle(FluentSystemIcons.textItalic, "Italic (⌘I)".keys, s.italic, fluent) { c.toggleItalic() },
            Chrome.toggle(FluentSystemIcons.textUnderline, "Underline (⌘U)".keys, s.underline, fluent) { c.toggleUnderline() },
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
        } + [("Paragraph Options…", { [session] in session.onParagraphDialog?() })]

        let paraRow1 = Chrome.row([
            Chrome.toggle(FluentSystemIcons.bulletList, "Bullets", s.list == .bullet, fluent) { c.toggleList(.bullet) },
            _listLibrary("Bullet Library", ListLevelFormat.bulletLibrary, c, fluent),
            Chrome.toggle(FluentSystemIcons.numberList, "Numbering", s.list == .numbered, fluent) { c.toggleList(.numbered) },
            _listLibrary("Numbering Library", ListLevelFormat.numberingLibrary, c, fluent),
            Chrome.menuButton(FluentSystemIcons.numberList, "Multilevel List", nil, fluent, items: ListLevelFormat.multilevelLibrary.map { scheme in
                MenuFlyoutItem(text: Text(scheme.name), onPressed: { c.setMultilevelFormat(scheme.levels) })
            }),
            Chrome.gap(2),
            Chrome.icon(FluentSystemIcons.indentDecrease, "Decrease Indent", fluent) { c.indent(-1) },
            Chrome.icon(FluentSystemIcons.indentIncrease, "Increase Indent", fluent) { c.indent(1) },
        ] + (session.deck != nil ? [] : [   // a deck draws no paragraph marks
            Chrome.gap(2),
            Chrome.toggle(FluentSystemIcons.paragraphMarks, "Show/Hide ¶ (⌘⇧8)".keys, session.showMarks, fluent) { [session] in session.onToggleMarks?() },
        ]))
        // W-PA-4: paragraph borders (one thin line in automatic colour; the dialog picks style, width and colour) and shading.
        func paraBorder(_ sides: Set<CellSide>, remove: Bool = false) -> () -> Void {
            { c.setParagraphBorders(sides, remove ? nil : CellBorderLine()) }
        }
        let paraBorderItems: [MenuFlyoutItemBase] = [
            MenuFlyoutItem(text: Text("Bottom Border"), onPressed: paraBorder([.bottom])),
            MenuFlyoutItem(text: Text("Top Border"), onPressed: paraBorder([.top])),
            MenuFlyoutItem(text: Text("Left Border"), onPressed: paraBorder([.left])),
            MenuFlyoutItem(text: Text("Right Border"), onPressed: paraBorder([.right])),
            MenuFlyoutSeparator(),
            MenuFlyoutItem(text: Text("All Borders"), onPressed: paraBorder([.top, .bottom, .left, .right])),
            MenuFlyoutItem(text: Text("Outside Borders"), onPressed: paraBorder([.top, .bottom, .left, .right])),
            MenuFlyoutItem(text: Text("Inside Border"), onPressed: paraBorder([.insideH])),
            MenuFlyoutItem(text: Text("No Border"), onPressed: paraBorder([.top, .bottom, .left, .right, .insideH], remove: true)),
            MenuFlyoutSeparator(),
            MenuFlyoutItem(text: Text("Borders and Shading…"), onPressed: { [session] in session.onBordersShadingDialog?() }),
        ]
        let paraRow2 = Chrome.row([
            Chrome.toggle(FluentSystemIcons.alignLeft, "Align Left", s.alignment == .left, fluent) { c.setAlignment(.left) },
            Chrome.toggle(FluentSystemIcons.alignCenter, "Center", s.alignment == .center, fluent) { c.setAlignment(.center) },
            Chrome.toggle(FluentSystemIcons.alignRight, "Align Right", s.alignment == .right, fluent) { c.setAlignment(.right) },
            Chrome.toggle(FluentSystemIcons.alignJustify, "Justify", s.alignment == .justify, fluent) { c.setAlignment(.justify) },
            Chrome.gap(2),
            Chrome.menu(nil, Icon(FluentSystemIcons.lineSpacing, size: Chrome.iconSize,
                                  color: fluent.resources.textFillColorPrimary), fluent, spacingChoices, tip: "Line Spacing"),
            Chrome.colorMenu(FluentSystemIcons.highlight, "Shading", fluent,
                             colors: OfficeColors.highlight, none: "No Shading") { col in c.setParagraphShading(col) },
            Chrome.menuButton(FluentSystemIcons.table, "Borders", "Borders", fluent, items: paraBorderItems),
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
                    ]), checked: on, width: 74 * SystemDisplay.current.chromeTextScale, height: OfficeAppearance.rowHeight(54), action: action)
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
            : Self._legible(entry.char.color, fluent) ?? OfficeAppearance.ink(fluent)
        return Flutter.TextStyle(color: color, fontSize: max(9, size),
                                 fontWeight: entry.char.bold ? .bold : .normal,
                                 fontStyle: entry.char.italic ? .italic : .normal,
                                 fontFamily: (entry.char.fontFamily ?? session.theme.fontFamily).map(OfficeFonts.drawn))
    }

    /// A style's own colour where it can be read on the chrome. A
    /// document is dark ink on white paper whatever the theme, and the
    /// ribbon in the dark theme is dark too: Title's navy and Subtitle's
    /// grey were all but invisible there (seen 2026-10-13, the gallery
    /// tile and half of the all-styles menu). Such a colour is lifted
    /// towards the chrome's ink, keeping its hue.
    private static func _legible(_ color: Color?, _ fluent: FluentThemeData) -> Color? {
        guard let color, fluent.brightness == .dark, color.computeLuminance() < 0.3 else { return color }
        return Color.lerp(color, OfficeAppearance.ink(fluent), 0.65) ?? color
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
            + [("More Symbols…", { [session] in session.onSymbolDialog?() })]
        let shapeChoices: [(String, () -> Void)] = [("Rectangle", "rect"), ("Rounded Rectangle", "roundRect"), ("Oval", "ellipse"),
                                                    ("Triangle", "triangle"), ("Right Arrow", "rightArrow")]
            .map { name, preset in (name, { [session] in
                // The shape waits for a click or drag on the page, and is made where the user puts it.
                c.pendingShape = { x, y, w, h in
                    TextBoxInsert.makeShape(preset: preset, width: w, height: h, number: TextBoxInsert.nextShapeNumber(in: c.document), page: (x, y))
                }
                session.onStatus?("Click on the page, or drag, to draw the \(name.lowercased())")
            }) }
        return [
            Chrome.group("Pages", fluent, [
                Chrome.big(FluentSystemIcons.pageBreak, "Page Break", fluent) { c.insertPageBreak() },
            ]),
            Chrome.group("Tables", fluent, [_tableMenu(fluent)]),
            Chrome.group("Illustrations", fluent, [
                Chrome.big(FluentSystemIcons.image, "Pictures", fluent) { [session] in session.onInsertPicture?() },
                Chrome.big(FluentSystemIcons.textT, "Text Box", fluent) { [session] in
                    if let box = TextBoxInsert.make() { c.insertImage(box) } else { session.onStatus?("Could not insert a text box") }
                },
                Chrome.menu(Text("Shapes"), Icon(FluentSystemIcons.shapes, size: Chrome.iconSize,
                                                 color: fluent.resources.textFillColorPrimary), fluent, shapeChoices),
                Chrome.menu(Text("WordArt"), Icon(FluentSystemIcons.textT, size: Chrome.iconSize,
                                                  color: fluent.resources.textFillColorPrimary), fluent,
                            TextBoxInsert.wordArtStyles.indices.map { k in (TextBoxInsert.wordArtStyles[k].name, { [session] in
                                if let art = TextBoxInsert.makeWordArt(style: k, number: TextBoxInsert.nextShapeNumber(in: c.document)) { c.insertImage(art) }
                                else { session.onStatus?("Could not insert WordArt") }
                            }) }),
            ]),
            Chrome.group("Links", fluent, [
                Chrome.big(FluentSystemIcons.link, "Link", fluent) { [session] in session.onLink?() },
            ]),
            Chrome.group("Header & Footer", fluent, [Chrome.rows([
                Chrome.small(FluentSystemIcons.header, "Header", fluent) { [session] in session.onHeaderFooter?() },
                Chrome.small(FluentSystemIcons.footer, "Footer", fluent) { [session] in session.onHeaderFooter?() },
                Chrome.small(FluentSystemIcons.pageNumber, "Page Number", fluent) { [session] in if !c.togglePageNumbers() { session.onHeaderFooter?() } },
            ])]),
            Chrome.group("Text", fluent, [Chrome.rows([
                Chrome.small(FluentSystemIcons.document, "Date & Time", fluent) { [session] in session.onDateTimeDialog?() },
                Chrome.menu(Text("Field"), Icon(FluentSystemIcons.document, size: Chrome.iconSize,
                                                color: fluent.resources.textFillColorPrimary), fluent,
                            [("Author", { c.insertField(" AUTHOR ", result: "") }), ("Title", { c.insertField(" TITLE ", result: "") }),
                             ("Subject", { c.insertField(" SUBJECT ", result: "") }), ("Date", { c.insertField(" DATE \\@ \"M/d/yyyy\" ", result: "") }),
                             ("Time", { c.insertField(" TIME \\@ \"h:mm AM/PM\" ", result: "") }),
                             ("Update Fields (F9)", { [session] in session.onUpdateFields?() })]),
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
        var all = items
        all.append(MenuFlyoutSeparator())
        let isBullet = library.allSatisfy { $0.format == .bullet }
        all.append(MenuFlyoutItem(text: Text(isBullet ? "Define New Bullet…" : "Define New Number Format…"),
                                  onPressed: { [session] in session.onListFormatDialog?(isBullet) }))
        if library.contains(where: { $0.format != .bullet }) {
            all.append(MenuFlyoutSeparator())
            all.append(MenuFlyoutItem(text: Text("Restart at 1"), onPressed: c.isNumberedItem ? { c.restartNumbering() } : nil))
            all.append(MenuFlyoutItem(text: Text("Continue Numbering"), onPressed: c.canContinueNumbering ? { c.continueNumbering() } : nil))
            all.append(MenuFlyoutItem(text: Text("Set Numbering Value…"), onPressed: c.isNumberedItem ? { [session] in session.onNumberingValueDialog?() } : nil))
        }
        return Chrome.splitChevron(tip, fluent, items: all)
    }

    private func _tableMenu(_ fluent: FluentThemeData) -> Widget {
        let c = session.controller
        let inCell = c.isInCell
        var items: [MenuFlyoutItemBase] = []
        items.append(TableGridMenuItem(onChoose: { [session] rows, cols in
            c.insertTable(rows: rows, columns: cols)
            session.onStatus?("Inserted a \(cols) × \(rows) table")
        }))
        items.append(MenuFlyoutSeparator())
        items.append(MenuFlyoutItem(text: Text("Insert Table…"), onPressed: { [session] in session.onInsertTableDialog?() }))
        items.append(MenuFlyoutItem(text: Text("Convert Text to Table…"), onPressed: c.canConvertTextToTable ? { [session] in session.onConvertTextTableDialog?(true) } : nil))
        items.append(MenuFlyoutSeparator())
        items.append(MenuFlyoutItem(text: Text("Insert Row Above"), onPressed: inCell ? { c.insertRow(below: false) } : nil))
        items.append(MenuFlyoutItem(text: Text("Insert Row Below"), onPressed: inCell ? { c.insertRow(below: true) } : nil))
        items.append(MenuFlyoutItem(text: Text("Delete Row"), onPressed: inCell ? { c.deleteRow() } : nil))
        items.append(MenuFlyoutSeparator())
        items.append(MenuFlyoutItem(text: Text("Delete Table"), onPressed: inCell ? { c.deleteTable() } : nil))
        return Chrome.menuButton(FluentSystemIcons.table, "Table", nil, fluent, items: items)
    }

    // MARK: Table Layout

    /// Table Design for a Writer table: the Table Style Options (Word's tblLook switches).
    private func _tableDesign(_ fluent: FluentThemeData) -> [Widget] {
        let c = session.controller
        guard let t = c.currentCell?.table else { return [] }
        let look = c.tableLook(of: t)
        func on(_ bit: Int) -> Bool { look & bit != 0 }
        func toggle(_ bit: Int) { c.setTableLook(bit, on: !on(bit)) }
        return [Chrome.group("Table Style Options", fluent, [
            Chrome.rows([
                Chrome.textToggle("Header Row", on(TableLook.firstRow), fluent) { toggle(TableLook.firstRow) },
                Chrome.textToggle("Total Row", on(TableLook.lastRow), fluent) { toggle(TableLook.lastRow) },
                Chrome.textToggle("Banded Rows", !on(TableLook.noRowBands), fluent) { toggle(TableLook.noRowBands) },
            ]),
            Chrome.rows([
                Chrome.textToggle("First Column", on(TableLook.firstColumn), fluent) { toggle(TableLook.firstColumn) },
                Chrome.textToggle("Last Column", on(TableLook.lastColumn), fluent) { toggle(TableLook.lastColumn) },
                Chrome.textToggle("Banded Columns", !on(TableLook.noColumnBands), fluent) { toggle(TableLook.noColumnBands) },
            ]),
        ])]
    }

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
        let select = Chrome.group("Select", fluent, [Chrome.rows([
            Chrome.menuButton(FluentSystemIcons.table, "Select", "Select cells", fluent, items: [
                MenuFlyoutItem(text: Text("Select Row"), onPressed: { c.selectRow() }),
                MenuFlyoutItem(text: Text("Select Column"), onPressed: { c.selectColumn() }),
                MenuFlyoutItem(text: Text("Select Table"), onPressed: { c.selectTable() }),
                MenuFlyoutSeparator(),
                MenuFlyoutItem(text: Text(session.tableTool == "draw" ? "Draw Table ✓" : "Draw Table"), onPressed: { [session] in session.onTableTool?("draw") }),
                MenuFlyoutItem(text: Text(session.tableTool == "erase" ? "Eraser ✓" : "Eraser"), onPressed: { [session] in session.onTableTool?("erase") }),
                MenuFlyoutSeparator(),
                MenuFlyoutItem(text: Text("Table Properties…"), onPressed: { [session] in session.onTablePropertiesDialog?() }),
                MenuFlyoutItem(text: Text("Formula…"), onPressed: c.canInsertFormula ? { [session] in session.onFormulaDialog?() } : nil),
                MenuFlyoutItem(text: Text("Sort…"), onPressed: c.canSortTable ? { [session] in session.onSortTableDialog?() } : nil),
                MenuFlyoutItem(text: Text("Convert Table to Text…"), onPressed: { self.session.onConvertTextTableDialog?(false) }),
            ]),
            Chrome.small(FluentSystemIcons.delete, "Delete Table", fluent) { c.deleteTable() },
            Chrome.menuButton(FluentSystemIcons.table, "Merge", "Merge cells, split cells, split the table", fluent, items: [
                MenuFlyoutItem(text: Text("Merge Cells"), onPressed: {
                    if c.selection.block != nil || c.selectedCellsInRow.count > 1 || c.selectedCellsInColumn.count > 1 { c.mergeCells() } }),
                MenuFlyoutItem(text: Text("Split Cell…"), onPressed: { if c.currentCell != nil { self.session.onSplitCellDialog?() } }),
                MenuFlyoutItem(text: Text("Split Table"), onPressed: { if c.canSplitTable { c.splitTable() } }),
            ]),
        ])])
        let style = c.currentTableStyle ?? TableStyle()
        let row = c.currentCell?.row ?? 0
        let size = Chrome.group("Cell Size", fluent, [
            Chrome.rows([
                Chrome.spinner("Row Height", style.rowHeights[row] ?? 0, fluent, step: 2, shown: style.rowHeights[row].map { "\(Int($0.rounded())) pt" } ?? "Auto") { v in
                    c.setRowHeight(v < 1 ? nil : v, exact: style.rowsExactHeight.contains(row))
                },
                Chrome.vgap(2),
                Chrome.spinner("Indent", style.indent, fluent, step: 6, minimum: -72) { v in c.setTableIndent(v) },
            ]),
            Chrome.rows([
                Chrome.small(FluentSystemIcons.columns, "Distribute Columns", fluent) { c.distributeColumns() },
                Chrome.small(FluentSystemIcons.table, "Distribute Rows", fluent) { c.distributeRows() },
            ]),
        ])
        // Word's nine Align buttons: top / center / bottom by left / center / right.
        let alignItems: [MenuFlyoutItemBase] = [("top", "Top"), ("center", "Center"), ("bottom", "Bottom")].flatMap { v in
            [(ParagraphAlignment.left, "Left"), (.center, "Center"), (.right, "Right")].map { h -> MenuFlyoutItemBase in
                MenuFlyoutItem(text: Text("Align \(v.1) \(h.1)"), onPressed: { c.setCellAlignment(vertical: v.0, horizontal: h.0) })
            }
        }
        let directionItems: [MenuFlyoutItemBase] = [MenuFlyoutSeparator(),
            MenuFlyoutItem(text: Text("Horizontal Text"), onPressed: { c.setCellTextDirection(.horizontal) }),
            MenuFlyoutItem(text: Text("Rotate Text Down"), onPressed: { c.setCellTextDirection(.down) }),
            MenuFlyoutItem(text: Text("Rotate Text Up"), onPressed: { c.setCellTextDirection(.up) }),
        ]
        let tableAlignItems: [MenuFlyoutItemBase] = [
            MenuFlyoutItem(text: Text("Table Left"), onPressed: { c.setTableAlignment(.left) }),
            MenuFlyoutItem(text: Text("Table Center"), onPressed: { c.setTableAlignment(.center) }),
            MenuFlyoutItem(text: Text("Table Right"), onPressed: { c.setTableAlignment(.right) }),
        ]
        func marginItems(_ label: String, _ v: Double) -> MenuFlyoutItem {
            MenuFlyoutItem(text: Text(label), onPressed: { c.setTableCellMargins(top: v == 0 ? 0 : v / 2.7, left: v, bottom: v == 0 ? 0 : v / 2.7, right: v) })
        }
        let marginsItems: [MenuFlyoutItemBase] = [marginItems("Cell Margins: None", 0), marginItems("Cell Margins: Narrow (2.7 pt)", 2.7),
                                                  marginItems("Cell Margins: Normal (5.4 pt)", 5.4), marginItems("Cell Margins: Wide (10.8 pt)", 10.8)]
        let tableWidthItems: [MenuFlyoutItemBase] = [
            MenuFlyoutItem(text: Text("Table Width: Auto"), onPressed: { c.setTableWidth() }),
            MenuFlyoutItem(text: Text("Table Width: 100%"), onPressed: { c.setTableWidth(percent: 100) }),
            MenuFlyoutItem(text: Text("Table Width: 75%"), onPressed: { c.setTableWidth(percent: 75) }),
            MenuFlyoutItem(text: Text("Table Width: 50%"), onPressed: { c.setTableWidth(percent: 50) }),
        ]
        let autoFitItems: [MenuFlyoutItemBase] = [
            MenuFlyoutItem(text: Text("AutoFit to Contents"), onPressed: { c.autoFitTable(.contents) }),
            MenuFlyoutItem(text: Text("AutoFit to Window"), onPressed: { c.autoFitTable(.window) }),
            MenuFlyoutItem(text: Text("Fixed Column Width"), onPressed: { c.autoFitTable(.fixed) }),
        ]
        let alignment = Chrome.group("Alignment", fluent, [
            Chrome.rows([
                Chrome.menuButton(FluentSystemIcons.table, "Cell Alignment", "Vertical alignment of the cell's text", fluent, items: alignItems + directionItems),
                Chrome.menuButton(nil, "Table Alignment", "Where the table stands between the margins", fluent, items: tableAlignItems),
                Chrome.menuButton(nil, "Table Width", "The table's width", fluent, items: tableWidthItems),
            ]),
            Chrome.gap(8),
            Chrome.rows([
                Chrome.menuButton(nil, "Cell Margins", "Margins inside the table's cells", fluent, items: marginsItems),
                Chrome.menuButton(nil, "AutoFit", "Fit the table to its contents, the window, or fixed widths", fluent, items: autoFitItems),
                Chrome.small(FluentSystemIcons.table, style.rowsCantSplit.contains(row) ? "Row Cannot Break" : "Row May Break", fluent) { c.setRowsMayBreak(style.rowsCantSplit.contains(row)) },
            ]),
        ])
        // The pen is read when a menu item is chosen, not when the ribbon builds.
        func apply(_ sides: [CellSide], _ line: CellBorderLine? = nil) -> () -> Void {
            { [session] in
                let l = line ?? session.cellPen
                c.setCellBorders(Dictionary(uniqueKeysWithValues: sides.map { ($0, l) }))
            }
        }
        let borderItems: [MenuFlyoutItemBase] = [
            MenuFlyoutItem(text: Text("Bottom Border"), onPressed: apply([.bottom])),
            MenuFlyoutItem(text: Text("Top Border"), onPressed: apply([.top])),
            MenuFlyoutItem(text: Text("Left Border"), onPressed: apply([.left])),
            MenuFlyoutItem(text: Text("Right Border"), onPressed: apply([.right])),
            MenuFlyoutSeparator(),
            MenuFlyoutItem(text: Text("All Borders"), onPressed: apply(CellSide.allCases)),
            MenuFlyoutItem(text: Text("Outside Borders"), onPressed: apply([.top, .bottom, .left, .right])),
            MenuFlyoutItem(text: Text("Inside Borders"), onPressed: apply([.insideH, .insideV])),
            MenuFlyoutSeparator(),
            MenuFlyoutItem(text: Text("No Border"), onPressed: apply(CellSide.allCases, .none)),
            MenuFlyoutSeparator(),
            MenuFlyoutItem(text: Text("Borders and Shading…"), onPressed: { [session] in session.onBordersShadingDialog?() }),
        ]
        let styleItems: [MenuFlyoutItemBase] = ["single", "double", "dashed", "dotted"].map { st in
            MenuFlyoutItem(text: Text(st.prefix(1).uppercased() + st.dropFirst() + " Line"), onPressed: { [session] in
                session.cellPen.style = st })
        }
        let widthItems: [MenuFlyoutItemBase] = CellBorderLine.widths.map { w in
            MenuFlyoutItem(text: Text("\(widthLabel(w)) pt"), onPressed: { [session] in
                session.cellPen.width = w })
        }
        let penColors = Chrome.colorMenu(FluentSystemIcons.textColor, "Pen Color", fluent,
                                         colors: OfficeColors.text, none: "Automatic") { [session] col in
            session.cellPen.color = col }
        let shading = Chrome.colorMenu(FluentSystemIcons.highlight, "Shading", fluent,
                                       colors: OfficeColors.highlight, none: "No Shading") { col in
            c.setCellShading(col) }
        let borders = Chrome.group("Borders & Shading", fluent, [
            Chrome.rows([
                Chrome.menuButton(FluentSystemIcons.table, "Borders", "Borders", fluent, items: borderItems),
                Chrome.menuButton(nil, "Line Style", "Border line style", fluent, items: styleItems),
                Chrome.menuButton(nil, "Line Width", "Border line width", fluent, items: widthItems),
            ]),
            Chrome.gap(8),
            Chrome.rows([shading, penColors]),
        ])
        let look = Chrome.group("Table Style", fluent, [Chrome.rows([
            Chrome.textToggle("Table Borders", style.borders, fluent) { c.setTableStyle { $0.borders.toggle() } },
            Chrome.textToggle("Header Row", style.headerRow, fluent) { c.setTableStyle { $0.headerRow.toggle() } },
            Chrome.small(FluentSystemIcons.header, style.headerRow ? "Repeat Header: On" : "Repeat Header: Off", fluent) { c.setRepeatedHeaderRows(style.headerRow ? 0 : max(1, row + 1)) },
        ])])
        return [select, rows, size, alignment, borders, look]
    }

    // MARK: Picture Format

    private func _pictureFormat(_ fluent: FluentThemeData, shape: Bool = false) -> [Widget] {
        let c = session.controller
        let s = session.summary
        if let i = s.imageIndex, let id = s.inlineImageID, let image = c.document.paragraphs[i].inlineImages[id] {
            let aspect = image.height / max(1, image.width)
            let size = Chrome.group("Size", fluent, [
                Chrome.rows([
                    Chrome.spinner("Width", image.width, fluent, step: 6) { v in
                        c.setInlineImageSize(in: i, id: id, width: v, height: c.pictureAspectLock ? v * aspect : image.height)
                    },
                    Chrome.vgap(2),
                    Chrome.spinner("Height", image.height, fluent, step: 6) { v in
                        c.setInlineImageSize(in: i, id: id, width: c.pictureAspectLock ? v / max(0.01, aspect) : image.width, height: v)
                    },
                ]),
                Chrome.gap(8),
                Chrome.rows([
                    Chrome.small(FluentSystemIcons.image, "Original Size", fluent, enabled: s.imageHasNatural) {
                        if let nw = image.naturalWidth, let nh = image.naturalHeight {
                            c.setInlineImageSize(in: i, id: id, width: nw, height: nh)
                        }
                    },
                    Chrome.small(FluentSystemIcons.zoomOut, "Half Size", fluent) {
                        c.setInlineImageSize(in: i, id: id, width: image.width / 2, height: image.height / 2)
                    },
                    // A row of the same column (a small button folds to its icon when the tab is tight), not a column of its own.
                    Chrome.small(FluentSystemIcons.lock, "Lock Aspect Ratio", fluent, checked: s.imageAspectLock) { [session] in session.onToggleAspectLock?() },
                ]),
            ])
            let turn = Chrome.group("Rotate", fluent, [
                Chrome.small(CupertinoIcons.rotate_right, "Rotate Right", fluent) { _ = c.rotatePicture(at: i, inline: id, quarters: 1) },
                Chrome.small(CupertinoIcons.rotate_left, "Rotate Left", fluent) { _ = c.rotatePicture(at: i, inline: id, quarters: -1) },
            ])
            let tools = Chrome.group("Adjust", fluent, [
                Chrome.rows([
                    Chrome.small(CupertinoIcons.chat_bubble_text, "Alt Text", fluent) { [session] in session.onPictureDialog?(.altText) },
                    Chrome.small(FluentSystemIcons.pageFit, "Crop", fluent) { [session] in session.onPictureDialog?(.crop) },
                ]),
                Chrome.gap(8),
                Chrome.rows([
                    Chrome.small(CupertinoIcons.photo_on_rectangle, "Change Picture", fluent) { [session] in session.onChangePicture?() },
                    Chrome.small(FluentSystemIcons.zoomOut, "Reset Picture", fluent) { c.resetPicture(at: i, inline: id) },
                ]),
            ])
            let remove = Chrome.group("Picture", fluent, [
                Chrome.big(FluentSystemIcons.delete, "Delete", fluent) { c.deleteForward() },
            ])
            // A shape In Line with Text gets the shape's tools (its fill, outline and words), not a picture's crop and file.
            if shape || image.outline != nil || image.textBox != nil {
                let alt = Chrome.group("Adjust", fluent, [
                    Chrome.small(CupertinoIcons.chat_bubble_text, "Alt Text", fluent) { [session] in session.onPictureDialog?(.altText) },
                ])
                var more: [Widget] = []
                if c.textBoxText(at: i, inline: id) != nil {
                    more.append(Chrome.group("Text Box", fluent, [
                        Chrome.big(FluentSystemIcons.textT, "Edit Text", fluent) { [session] in session.onPictureDialog?(.boxText) },
                    ]))
                }
                if image.outline != nil, image.sourceXML?.containsSubstring("<wps:wsp") == true {
                    more.append(Chrome.group("Shape Styles", fluent, [
                        _shapeColorMenu(FluentSystemIcons.highlight, "Shape Fill", c, i, fluent, outline: false, inline: id),
                        _shapeColorMenu(FluentSystemIcons.textColor, "Shape Outline", c, i, fluent, outline: true, inline: id),
                    ]))
                }
                if c.isInLine(at: i, inline: id) || c.pictureWrap(at: i, inline: id) != nil {
                    more.append(_wrapGroup(c, i, id, c.pictureWrap(at: i, inline: id), fluent))
                }
                return [size, turn] + more + [alt, Chrome.group("Shape", fluent, [
                    Chrome.big(FluentSystemIcons.delete, "Delete", fluent) { c.deleteForward() },
                ])]
            }
            if c.isInLine(at: i, inline: id) || c.pictureWrap(at: i, inline: id) != nil {
                return [size, turn, _wrapGroup(c, i, id, c.pictureWrap(at: i, inline: id), fluent), tools, remove]
            }
            return [size, turn, tools, remove]
        }
        guard let i = s.imageIndex, let image = c.document.paragraphs[i].image else { return [] }
        let aspect = image.height / max(1, image.width)
        let size = Chrome.group("Size", fluent, [
            Chrome.rows([
                Chrome.spinner("Width", image.width, fluent, step: 6) { v in
                    c.setImageSize(at: i, width: v, height: c.pictureAspectLock ? v * aspect : image.height)
                },
                Chrome.vgap(2),
                Chrome.spinner("Height", image.height, fluent, step: 6) { v in
                    c.setImageSize(at: i, width: c.pictureAspectLock ? v / max(0.01, aspect) : image.width, height: v)
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
                Chrome.small(FluentSystemIcons.lock, "Lock Aspect Ratio", fluent, checked: s.imageAspectLock) { [session] in session.onToggleAspectLock?() },
            ]),
        ])
        let arrange = Chrome.group("Arrange", fluent, [
            Chrome.big(FluentSystemIcons.alignLeft, "Left", fluent) { c.setAlignment(.left) },
            Chrome.big(FluentSystemIcons.alignCenter, "Center", fluent) { c.setAlignment(.center) },
            Chrome.big(FluentSystemIcons.alignRight, "Right", fluent) { c.setAlignment(.right) },
        ])
        let turn = Chrome.group("Rotate", fluent, [
            Chrome.small(CupertinoIcons.rotate_right, "Rotate Right", fluent) { _ = c.rotatePicture(at: i, quarters: 1) },
            Chrome.small(CupertinoIcons.rotate_left, "Rotate Left", fluent) { _ = c.rotatePicture(at: i, quarters: -1) },
        ])
        let tools = shape ? Chrome.group("Adjust", fluent, [
            Chrome.small(CupertinoIcons.chat_bubble_text, "Alt Text", fluent) { [session] in session.onPictureDialog?(.altText) },
        ]) : Chrome.group("Adjust", fluent, [
            Chrome.rows([
                Chrome.small(CupertinoIcons.chat_bubble_text, "Alt Text", fluent) { [session] in session.onPictureDialog?(.altText) },
                Chrome.small(FluentSystemIcons.pageFit, "Crop", fluent) { [session] in session.onPictureDialog?(.crop) },
            ]),
            Chrome.gap(8),
            Chrome.rows([
                Chrome.small(CupertinoIcons.photo_on_rectangle, "Change Picture", fluent) { [session] in session.onChangePicture?() },
                Chrome.small(FluentSystemIcons.zoomOut, "Reset Picture", fluent) { c.resetPicture(at: i) },
            ]),
        ])
        let remove = Chrome.group("Picture", fluent, [
            Chrome.big(FluentSystemIcons.delete, "Delete", fluent) { c.deleteForward() },
        ])
        // Layout Options: only a picture that floats has a wrap to choose and a place to nudge.
        var boxGroup: [Widget] = []
        if c.textBoxText(at: i) != nil {
            boxGroup.append(Chrome.group("Text Box", fluent, [
                Chrome.big(FluentSystemIcons.textT, "Edit Text", fluent) { [session] in session.onPictureDialog?(.boxText) },
            ]))
        }
        var styleGroup: [Widget] = []
        if c.document.paragraphs[i].image?.outline != nil, c.document.paragraphs[i].image?.sourceXML?.containsSubstring("<wps:wsp") == true {
            styleGroup.append(Chrome.group("Shape Styles", fluent, [
                _shapeColorMenu(FluentSystemIcons.highlight, "Shape Fill", c, i, fluent, outline: false),
                _shapeColorMenu(FluentSystemIcons.textColor, "Shape Outline", c, i, fluent, outline: true),
            ]))
        }
        var groupWidgets: [Widget] = []
        let picked = c.pickedShapeIndexes
        let pickedImages = picked.compactMap { c.document.paragraphs[$0].image }
        if picked.count >= 2, pickedImages.allSatisfy(ShapeGroups.isGroupable) {
            groupWidgets.append(Chrome.group("Group", fluent, [
                Chrome.big(FluentSystemIcons.shapes, "Group", fluent) { [session] in
                    if let g = ShapeGroups.group(pickedImages, number: TextBoxInsert.nextShapeNumber(in: c.document), parts: c.document.keptParts), c.replaceImageParagraphs(picked, with: [g]) {
                        session.onStatus?("Grouped \(picked.count) shapes")
                    }
                },
            ]))
        } else if let image = c.document.paragraphs[i].image, ShapeGroups.isGroup(image) {
            groupWidgets.append(Chrome.group("Group", fluent, [
                Chrome.big(FluentSystemIcons.shapes, "Ungroup", fluent) { [session] in
                    if let parts = ShapeGroups.ungroup(image, number: TextBoxInsert.nextShapeNumber(in: c.document), parts: c.document.keptParts), c.replaceImageParagraphs([i], with: parts) {
                        session.onStatus?("Ungrouped into \(parts.count) shapes")
                    }
                },
            ]))
        } else if picked.count < 2, let image = c.document.paragraphs[i].image, ShapeGroups.isGroupable(image) {
            groupWidgets.append(Chrome.group("Group", fluent, [
                Chrome.big(FluentSystemIcons.shapes, "Group", fluent, enabled: false) {},
            ]))
        }
        if c.pictureWrap(at: i) != nil {
            // A finger has no Shift: while this is on, a tap on another floating shape picks it to group with this one.
            groupWidgets.append(Chrome.group("Select", fluent, [
                Chrome.small(FluentSystemIcons.check, "Select Multiple", fluent, checked: c.selectMultiple) { c.setSelectMultiple(!c.selectMultiple) },
            ]))
        }
        var floating: [Widget] = []
        if let wrap = c.pictureWrap(at: i) {
            floating.append(_wrapGroup(c, i, nil, wrap, fluent))
            floating.append(Chrome.group("Position", fluent, [
                Chrome.rows([
                    Chrome.small(CupertinoIcons.arrow_left, "Nudge Left", fluent) { _ = c.movePicture(at: i, dx: -6, dy: 0) },
                    Chrome.small(CupertinoIcons.arrow_right, "Nudge Right", fluent) { _ = c.movePicture(at: i, dx: 6, dy: 0) },
                ]),
                Chrome.gap(8),
                Chrome.rows([
                    Chrome.small(CupertinoIcons.arrow_up, "Nudge Up", fluent) { _ = c.movePicture(at: i, dx: 0, dy: -6) },
                    Chrome.small(CupertinoIcons.arrow_down, "Nudge Down", fluent) { _ = c.movePicture(at: i, dx: 0, dy: 6) },
                ]),
                Chrome.gap(8),
                Chrome.rows([
                    // Layout Options' pair: it rides with its paragraph, or stays put on the page as text moves.
                    Chrome.small(CupertinoIcons.text_alignleft, "Move with Text", fluent, checked: c.pictureMovesWithText(at: i) == true) {
                        _ = c.setPictureMovesWithText(at: i, true)
                    },
                    Chrome.small(CupertinoIcons.pin, "Fix Position on Page", fluent, checked: c.pictureMovesWithText(at: i) == false) {
                        _ = c.setPictureMovesWithText(at: i, false)
                    },
                ]),
                Chrome.gap(8),
                // Arrange's stack, as Word's pair of split menus: a step up or down through the floating objects on its side
                // of the text, or to the top or bottom.
                Chrome.rows([
                    Chrome.menuButton(CupertinoIcons.layers_fill, "Bring Forward", nil, fluent, items: [
                        MenuFlyoutItem(text: Text("Bring Forward"), onPressed: { _ = c.arrangePicture(at: i, .forward) }),
                        MenuFlyoutItem(text: Text("Bring to Front"), onPressed: { _ = c.arrangePicture(at: i, .front) }),
                    ]),
                    Chrome.menuButton(CupertinoIcons.layers, "Send Backward", nil, fluent, items: [
                        MenuFlyoutItem(text: Text("Send Backward"), onPressed: { _ = c.arrangePicture(at: i, .backward) }),
                        MenuFlyoutItem(text: Text("Send to Back"), onPressed: { _ = c.arrangePicture(at: i, .back) }),
                    ]),
                ]),
            ]))
        }
        if shape { return styleGroup + boxGroup + groupWidgets + floating + [size, turn, tools, remove] }
        return [size, arrange] + floating + groupWidgets + boxGroup + styleGroup + [turn, tools, remove]
    }

    /// Shape Fill / Shape Outline: the shared colour picker; a theme pick is written as a theme colour.
    /// Layout Options' wraps for the drawing at `i` (or its inline picture `id`): In Line with Text and the six wraps, the
    /// one it has now greyed. `wrap` is nil for one In Line with Text.
    private func _wrapGroup(_ c: RichDocumentController, _ i: Int, _ id: String?, _ wrap: PictureWrap?, _ fluent: FluentThemeData) -> Widget {
        func pick(_ w: PictureWrap) -> Widget {
            let glyph: IconData
            switch w {
            case .square: glyph = CupertinoIcons.rectangle_split_3x1
            case .tight: glyph = CupertinoIcons.square_grid_2x2
            case .through: glyph = CupertinoIcons.layers
            case .topAndBottom: glyph = CupertinoIcons.arrow_up_down
            case .behindText: glyph = CupertinoIcons.square_stack
            default: glyph = CupertinoIcons.rectangle_on_rectangle
            }
            return Chrome.small(glyph, w.title, fluent, enabled: w != wrap) { _ = c.setPictureWrap(at: i, inline: id, w) }
        }
        let inLine = Chrome.small(CupertinoIcons.text_alignleft, "In Line with Text", fluent, enabled: wrap != nil) { _ = c.setInLine(at: i, inline: id) }
        return Chrome.group("Wrap Text", fluent, [
            Chrome.rows([inLine, pick(.square), pick(.tight)]),
            Chrome.gap(8),
            Chrome.rows([pick(.through), pick(.topAndBottom), pick(.behindText)]),
            Chrome.gap(8),
            Chrome.rows([pick(.inFrontOfText)]),
        ])
    }

    private func _shapeColorMenu(_ icon: IconData, _ tip: String, _ c: RichDocumentController, _ i: Int,
                                 _ fluent: FluentThemeData, outline: Bool, inline id: String? = nil) -> Widget {
        Chrome.menuButton(icon, nil, tip, fluent, items: [
            ColorGridMenuItem(theme: ColorMath.officeTheme, recent: [], noneLabel: outline ? "No Outline" : "No Fill",
                              onChoose: { choice in
                guard let rgb = choice.resolved(theme: ColorMath.officeTheme) else { _ = outline ? c.setShapeOutline(at: i, inline: id, nil) : c.setShapeFill(at: i, inline: id, nil); return }
                let color = Color(0xFF00_0000 | Int64(rgb))
                var theme: (slot: Int, lumMod: Int, lumOff: Int)?
                if case .theme(let slot, let mod, let off) = choice { theme = (slot, mod, off) }
                _ = outline ? c.setShapeOutline(at: i, inline: id, color, theme: theme) : c.setShapeFill(at: i, inline: id, color, theme: theme)
            }, onMore: { [session] in session.onMoreColors?() }),
        ])
    }

    // MARK: Layout

    private func _layout(_ fluent: FluentThemeData) -> [Widget] {
        let c = session.controller
        let setup = session.sectionSetup()
        func margins(_ name: String, _ v: Double, _ h: Double) -> (String, () -> Void) {
            (name, { [session] in
                var p = session.sectionSetup()
                p.marginTop = v; p.marginBottom = v; p.marginLeft = h; p.marginRight = h
                session.onPageSetup?(p)
            })
        }
        let customMargins: (String, () -> Void) = ("Custom Margins…", { [session] in session.onPageSetupDialog?() })
        let marginChoices = [margins("Normal (1\")", 72, 72), margins("Narrow (0.5\")", 36, 36),
                             margins("Moderate (1\" × 0.75\")", 72, 54), margins("Wide (1\" × 2\")", 72, 144), customMargins]
        let orientation: [(String, () -> Void)] = [
            ("Portrait", { [session] in if session.sectionSetup().isLandscape { session.onPageSetup?(session.sectionSetup().rotated()) } }),
            ("Landscape", { [session] in if !session.sectionSetup().isLandscape { session.onPageSetup?(session.sectionSetup().rotated()) } }),
        ]
        func paper(_ name: String, _ base: PageSetup) -> (String, () -> Void) {
            (name, { [session] in
                var p = base
                p.marginTop = session.sectionSetup().marginTop; p.marginBottom = session.sectionSetup().marginBottom
                p.marginLeft = session.sectionSetup().marginLeft; p.marginRight = session.sectionSetup().marginRight
                session.onPageSetup?(session.sectionSetup().isLandscape ? p.rotated() : p)
            })
        }
        let sizes: [(String, () -> Void)] = [paper("Letter (8.5 × 11 in)", .letter), paper("A4 (210 × 297 mm)", .a4),
                     paper("Legal (8.5 × 14 in)", PageSetup(width: 612, height: 1008)),
                     ("More Paper Sizes…", { [session] in session.onPageSetupDialog?() })]
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
                            [("One", { [session] in var p = session.sectionSetup(); p.columns = 1; session.onPageSetup?(p) }),
                             ("Two", { [session] in var p = session.sectionSetup(); p.columns = 2; session.onPageSetup?(p) }),
                             ("Three", { [session] in var p = session.sectionSetup(); p.columns = 3; session.onPageSetup?(p) })]),
            ]),
            Chrome.gap(),
            Chrome.rows([
                Chrome.menu(Text("Breaks"), Icon(FluentSystemIcons.pageBreak, size: Chrome.iconSize,
                                                 color: fluent.resources.textFillColorPrimary), fluent,
                            [("Page", { c.insertPageBreak() }),
                             ("Column", { c.insertColumnBreak() }),
                             ("Section: Next Page", { [session] in c.insertSectionBreak(.nextPage, lastSetup: session.pageSetup) }),
                             ("Section: Continuous", { [session] in c.insertSectionBreak(.continuous, lastSetup: session.pageSetup) }),
                             ("Section: Even Page", { [session] in c.insertSectionBreak(.evenPage, lastSetup: session.pageSetup) }),
                             ("Section: Odd Page", { [session] in c.insertSectionBreak(.oddPage, lastSetup: session.pageSetup) })]),
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
