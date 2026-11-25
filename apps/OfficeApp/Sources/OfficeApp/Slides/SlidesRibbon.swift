// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The ribbon's tabs for a deck: Home, Insert, Design, Transitions, Slide
// Show, Review, View. The Font and Paragraph groups are Writer's own,
// pointed at the text being edited.

import Flutter
import OfficeText
import FlutterSwiftBridge
import FluentSystemIcons
import Foundation

extension Ribbon {
    /// The groups for a Slides tab; nil hands the tab back to Writer's
    /// (Review is shared).
    func slidesGroups(_ fluent: FluentThemeData) -> [Widget]? {
        guard let deck = session.deck else { return nil }
        switch tab {
        case .home: return _slidesHome(deck, fluent)
        case .insert: return _slidesInsert(deck, fluent)
        case .design: return _design(deck, fluent)
        case .transitions: return _transitions(deck, fluent)
        case .slideShow: return _slideShowTab(deck, fluent)
        case .view: return _slidesView(fluent)
        case .pictureFormat: return _slidePictureFormat(deck, fluent)
        case .chartDesign: return _chartDesign(deck, fluent)
        case .tableDesign: return _slideTableDesign(deck, fluent)
        case .animations: return _animationsTab(deck, fluent)
        default: return nil
        }
    }

    private func _layoutItems(_ fluent: FluentThemeData, current: SlideLayoutKind?,
                              _ pick: @escaping (SlideLayoutKind) -> Void) -> [MenuFlyoutItemBase] {
        SlideLayoutKind.allCases.map { kind in
            MenuFlyoutItem(text: Text(kind.name),
                           leading: Icon(current == kind ? FluentSystemIcons.check : FluentSystemIcons.onePage,
                                         size: Chrome.iconSize, color: fluent.resources.textFillColorPrimary),
                           onPressed: { pick(kind) })
        }
    }

    /// What the Layout button offers: the deck's own layouts when it came from
    /// a file that carries some, else our seven.
    private func _slideLayoutItems(_ deck: DeckController, _ fluent: FluentThemeData) -> [MenuFlyoutItemBase] {
        let own = deck.fileLayouts
        guard !own.isEmpty else {
            return _layoutItems(fluent, current: deck.currentSlide.layout) { kind in deck.applyLayout(kind, to: deck.current) }
        }
        let currentPart = deck.currentSlide.layoutPart
        var items: [MenuFlyoutItemBase] = own.map { layout in
            MenuFlyoutItem(text: Padding(key: ValueKey("slides.layout.\(layout.index)"), padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 0), child: Text(layout.name)),
                           leading: Icon(currentPart == layout.part ? FluentSystemIcons.check : FluentSystemIcons.onePage,
                                         size: Chrome.iconSize, color: fluent.resources.textFillColorPrimary),
                           onPressed: { deck.applyFileLayout(layout.part, to: deck.current) })
        }
        // Reset: the slide's placeholders go back to the layout's own place and look; the text stays.
        items.append(MenuFlyoutItem(text: Padding(key: ValueKey("slides.reset"), padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 0), child: Text("Reset slide to its layout")),
                                    leading: Icon(FluentSystemIcons.undo, size: Chrome.iconSize,
                                                  color: fluent.resources.textFillColorPrimary),
                                    onPressed: currentPart == nil ? nil : { deck.applyFileLayout(currentPart!, to: deck.current) }))
        return items
    }

    private func _slidesGroup(_ deck: DeckController, _ fluent: FluentThemeData) -> Widget {
        Chrome.group("Slides", fluent, [
            Chrome.big(FluentSystemIcons.add, "New Slide", fluent) { deck.addSlide() },
            FlatButton(child: Chrome.chevron(fluent), tip: "New Slide layouts", width: 16, height: 58,
                       menu: _layoutItems(fluent, current: nil) { kind in deck.addSlide(kind) }),
            Chrome.gap(2),
            Chrome.rows([
                Chrome.menuButton(FluentSystemIcons.grid, "Layout", "Slide layout", fluent,
                                  items: _slideLayoutItems(deck, fluent)),
                Chrome.small(FluentSystemIcons.copy, "Duplicate", fluent) { deck.duplicateSlide(deck.current) },
                Chrome.small(FluentSystemIcons.delete, "Delete", fluent, enabled: deck.slides.count > 1) {
                    deck.deleteSlide(deck.current)
                },
            ]),
        ])
    }

    private func _slidesHome(_ deck: DeckController, _ fluent: FluentThemeData) -> [Widget] {
        let fp = fontAndParagraphGroups(fluent)
        let editing = Chrome.group("Editing", fluent, [Chrome.rows([
            Chrome.small(FluentSystemIcons.textT, "Select All", fluent) { [session] in session.controller.selectAll() },
            Chrome.small(FluentSystemIcons.numberList, "Selection Pane", fluent) { [session] in session.onSelectionPane?() },
            // A finger has no Shift: while this is on, a tap adds a shape to the selection or takes it out.
            Chrome.small(FluentSystemIcons.check, "Select Multiple", fluent, checked: deck.selectMultiple) { deck.setSelectMultiple(!deck.selectMultiple) },
        ])])
        return [clipboardGroup(fluent), _slidesGroup(deck, fluent), fp[0], fp[1], _drawingGroup(deck, fluent), editing]
    }

    private func _shapeItems(_ fluent: FluentThemeData) -> [MenuFlyoutItemBase] {
        ShapeGallery.groups.map { group in
            MenuFlyoutSubItem(text: Text(group.name), items: group.presets.map { preset in
                MenuFlyoutItem(text: Text(preset.name),
                               leading: Icon(FluentSystemIcons.shapes, size: Chrome.iconSize,
                                             color: fluent.resources.textFillColorPrimary),
                               onPressed: { [session] in session.onInsertShape?(preset) })
            })
        }
    }

    /// Shapes, Arrange, Shape Fill and Shape Outline — PowerPoint's Drawing
    /// group, acting on the selected shapes.
    private func _drawingGroup(_ deck: DeckController, _ fluent: FluentThemeData) -> Widget {
        let some = !deck.selection.isEmpty
        let arrange: [MenuFlyoutItemBase] = [
            MenuFlyoutItem(text: Text("Bring to Front"), onPressed: some ? { deck.arrange(.front) } : nil),
            MenuFlyoutItem(text: Text("Send to Back"), onPressed: some ? { deck.arrange(.back) } : nil),
            MenuFlyoutItem(text: Text("Bring Forward"), onPressed: some ? { deck.arrange(.forward) } : nil),
            MenuFlyoutItem(text: Text("Send Backward"), onPressed: some ? { deck.arrange(.backward) } : nil),
            MenuFlyoutSeparator(),
            MenuFlyoutItem(text: Text("Group"), onPressed: deck.canGroup ? { deck.groupSelection() } : nil),
            MenuFlyoutItem(text: Text("Ungroup"), onPressed: deck.canUngroup ? { deck.ungroupSelection() } : nil),
            MenuFlyoutSeparator(),
            MenuFlyoutItem(text: Text("Rotate Right 90°"), onPressed: some ? { deck.rotateSelection(by: 90) } : nil),
            MenuFlyoutItem(text: Text("Rotate Left 90°"), onPressed: some ? { deck.rotateSelection(by: -90) } : nil),
            MenuFlyoutItem(text: Text("Flip Vertical"), onPressed: some ? { deck.flipSelection(horizontal: false) } : nil),
            MenuFlyoutItem(text: Text("Flip Horizontal"), onPressed: some ? { deck.flipSelection(horizontal: true) } : nil),
            MenuFlyoutSeparator(),
            MenuFlyoutItem(text: Text("Align Left"), onPressed: some ? { deck.align(.left) } : nil),
            MenuFlyoutItem(text: Text("Align Center"), onPressed: some ? { deck.align(.center) } : nil),
            MenuFlyoutItem(text: Text("Align Right"), onPressed: some ? { deck.align(.right) } : nil),
            MenuFlyoutItem(text: Text("Align Top"), onPressed: some ? { deck.align(.top) } : nil),
            MenuFlyoutItem(text: Text("Align Middle"), onPressed: some ? { deck.align(.middle) } : nil),
            MenuFlyoutItem(text: Text("Align Bottom"), onPressed: some ? { deck.align(.bottom) } : nil),
            MenuFlyoutSeparator(),
            MenuFlyoutItem(key: ValueKey("arrange.reroute"), text: Text("Reroute Connectors"),
                           onPressed: deck.reroutableLines.isEmpty ? nil : { deck.rerouteConnectors() }),
            MenuFlyoutSeparator(),
            MenuFlyoutItem(text: Text("Format Shape…"), onPressed: some ? { [session] in session.onFormatShape?() } : nil),
        ]
        let palette = Self.shapeColors(deck.theme)
        return Chrome.group("Drawing", fluent, [Chrome.rows([
            Chrome.row([
                Chrome.menuButton(FluentSystemIcons.shapes, "Shapes", "Insert a shape", fluent, items: _shapeItems(fluent)),
                Chrome.menuButton(FluentSystemIcons.grid, "Arrange", "Order and align", fluent, items: arrange),
            ]),
            Chrome.vgap(4),
            Chrome.row([
                _shapeColorMenu(FluentSystemIcons.paintBrush, "Shape Fill", deck, fluent, outline: false),
                _shapeColorMenu(FluentSystemIcons.edit, "Shape Outline", deck, fluent, outline: true),
            ]),
            Chrome.vgap(4),
            Chrome.row([
                Chrome.menuButton(FluentSystemIcons.textEffects, "Shape Effects", "Shadow, glow, reflection, soft edges, bevel",
                                  fluent, items: _effectItems(deck, fluent)),
                Chrome.small(FluentSystemIcons.textT, "Text Options", fluent) { [session] in session.onTextOptions?() },
            ]),
        ])])
    }

    /// Shape Effects: PowerPoint's presets for shadow, glow, reflection, soft edges and bevel.
    private func _effectItems(_ deck: DeckController, _ fluent: FluentThemeData) -> [MenuFlyoutItemBase] {
        let some = !deck.selection.isEmpty
        func item(_ id: String, _ text: String, _ act: @escaping () -> Void) -> MenuFlyoutItem {
            MenuFlyoutItem(key: ValueKey(id), text: Text(text), onPressed: some ? act : nil)
        }
        let shadows: [MenuFlyoutItemBase] = [item("fx.shadow.none", "No Shadow") { deck.setShadow(nil) }]
            + ShapeEffectPresets.shadows.enumerated().map { i, sh in
                item("fx.shadow.\(i)", sh.name) { deck.setShadow(ShapeEffectPresets.shadow(angle: sh.angle)) } }
        let glows: [MenuFlyoutItemBase] = [item("fx.glow.none", "No Glow") { deck.setGlow(radius: nil, color: nil) }]
            + ShapeEffectPresets.glowSizes.map { size in
                MenuFlyoutSubItem(text: Text("Glow: \(Int(size)) point"), items: deck.theme.accents.prefix(6).enumerated().map { i, c in
                    item("fx.glow.\(Int(size)).\(i)", "Accent \(i + 1)") {
                        deck.setGlow(radius: size, color: ShapeEffectPresets.glowColor(c)) } })
            }
        let reflections: [MenuFlyoutItemBase] = [item("fx.reflection.none", "No Reflection") { deck.setReflection(nil) }]
            + ShapeEffectPresets.reflections.enumerated().map { i, r in
                item("fx.reflection.\(i)", r.name) {
                    deck.setReflection(ShapeEffectPresets.reflection(r)) } }
        let soft: [MenuFlyoutItemBase] = [item("fx.soft.none", "No Soft Edges") { deck.setSoftEdge(nil) }]
            + ShapeEffectPresets.softEdgeSizes.map { r in
                item("fx.soft.\(r)", "\(r == r.rounded() ? String(Int(r)) : String(r)) Point") { deck.setSoftEdge(r) } }
        let bevels: [MenuFlyoutItemBase] = [item("fx.bevel.none", "No Bevel") { deck.setBevel(nil) }]
            + ShapeEffectPresets.bevels.map { b in
                item("fx.bevel.\(b.preset)", b.name) { deck.setBevel(ShapeBevel(width: 6, height: 6, preset: b.preset)) } }
        return [
            item("fx.clear", "No Effects") { deck.clearEffects() },
            MenuFlyoutSeparator(),
            MenuFlyoutSubItem(text: Text("Shadow"), items: shadows),
            MenuFlyoutSubItem(text: Text("Reflection"), items: reflections),
            MenuFlyoutSubItem(text: Text("Glow"), items: glows),
            MenuFlyoutSubItem(text: Text("Soft Edges"), items: soft),
            MenuFlyoutSubItem(text: Text("Bevel"), items: bevels),
        ]
    }

    /// The theme's accents first, then the neutrals and standard colours.
    static func shapeColors(_ theme: DeckTheme) -> [(String, Color)] {
        let names = ["Accent 1", "Accent 2", "Accent 3", "Accent 4", "Accent 5", "Accent 6"]
        return zip(names, theme.accents).map { ($0, $1) } + [
            ("White", Color(0xFFFFFFFF)), ("Light Gray", Color(0xFFD9D9D9)), ("Gray", Color(0xFF7F7F7F)),
            ("Black", Color(0xFF000000)), ("Red", Color(0xFFC00000)), ("Orange", Color(0xFFFFC000)),
            ("Green", Color(0xFF00B050)), ("Blue", Color(0xFF0070C0)), ("Purple", Color(0xFF7030A0)),
        ]
    }

    /// Shape Fill / Shape Outline: the shared colour picker in a drop-down.
    private func _shapeColorMenu(_ icon: IconData, _ tip: String, _ deck: DeckController, _ fluent: FluentThemeData,
                                 outline: Bool) -> Widget {
        var items: [MenuFlyoutItemBase] = [
            ColorGridMenuItem(theme: deck.theme.slots, recent: deck.recentShapeColors.list,
                              noneLabel: outline ? "No Outline" : "No Fill",
                              onChoose: { deck.applyShapeColor($0, outline: outline) },
                              onMore: { [session] in session.onMoreShapeColor?(outline) },
                              onEyedropper: { deck.eyedropperFor = outline }),
        ]
            func entry(_ id: String, _ label: String, _ run: @escaping () -> Void) -> MenuFlyoutItem {
                MenuFlyoutItem(text: Padding(key: ValueKey(id), padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 0), child: Text(label)),
                               onPressed: deck.selection.isEmpty ? nil : run)
            }
        if !outline {
            let ink = Color(Int64(deck.theme.slots[1]) | 0xFF00_0000)
            let patterns: [(String, String)] = [("Light upward diagonal", "ltUpDiag"), ("Wide upward diagonal", "wdUpDiag"),
                ("Horizontal lines", "ltHorz"), ("Vertical lines", "ltVert"), ("Grid", "smGrid"), ("Dotted grid", "dotGrid"),
                ("Checker board", "smCheck"), ("5 percent", "pct5"), ("25 percent", "pct25"), ("50 percent", "pct50")]
            items.append(entry("shape-fill-picture", "Picture…") { [session] in session.onShapeFillPicture?(false) })
            items.append(entry("shape-fill-texture", "Texture…") { [session] in session.onShapeFillPicture?(true) })
            items.append(MenuFlyoutSubItem(text: Text("Pattern"), items: patterns.map { name, preset in
                entry("shape-fill-pattern-\(preset)", name) { deck.setPatternFill(preset, foreground: ink, background: Color(0xFFFFFFFF)) }
            }))
        }
        if outline {
            let weights: [Double] = [0.25, 0.5, 0.75, 1, 1.5, 2.25, 3, 4.5, 6]
            items.append(MenuFlyoutSubItem(text: Text("Weight"), items: weights.map { w in
                entry("shape-weight-\(w)", "\(w) pt") { deck.setOutlineWidth(w) }
            }))
            items.append(MenuFlyoutSubItem(text: Text("Dashes"), items: FormatShapePaneState.dashStyles.map { dash, name in
                entry("shape-dash-\(dash ?? "solid")", name) { deck.setOutlineDash(dash) }
            }))
            let heads: [(String?, String)] = [(nil, "None"), ("triangle", "Arrow"), ("arrow", "Open arrow"), ("stealth", "Stealth arrow"),
                                              ("diamond", "Diamond"), ("oval", "Oval")]
            for (start, label) in [(true, "Arrow start"), (false, "Arrow end")] {
                items.append(MenuFlyoutSubItem(text: Text(label), items: heads.map { kind, name in
                    entry("shape-\(start ? "head" : "tail")-\(kind ?? "none")", name) { deck.setLineEnd(start: start, kind: kind) }
                }))
            }
        }
        return Chrome.menuButton(icon, nil, tip, fluent, items: items)
    }

    private func _slidesInsert(_ deck: DeckController, _ fluent: FluentThemeData) -> [Widget] {
        [
            _slidesGroup(deck, fluent),
            Chrome.group("Links", fluent, [
                Chrome.big(FluentSystemIcons.link, "Link", fluent) { [session] in session.onLink?() },
            ]),
            Chrome.group("Text", fluent, [
                Chrome.big(FluentSystemIcons.textT, "Text Box", fluent) { [session] in session.onInsertTextBox?() },
                Chrome.big(FluentSystemIcons.header, "Header & Footer", fluent) { [session] in session.onHeaderFooter?() },
            ]),
            Chrome.group("Tables", fluent, [
                FlatButton(child: Padding(padding: EdgeInsets(left: 6, top: 2, right: 6, bottom: 2),
                    child: Column(mainAxisAlignment: .center, crossAxisAlignment: .center, children: [
                        Icon(FluentSystemIcons.table, size: Chrome.bigIconSize, color: fluent.resources.textFillColorPrimary),
                        Chrome.vgap(4),
                        Text("Table", style: fluent.typography.caption),
                    ])), tip: "Insert a table", width: nil, height: Chrome.rowHeight * 2 + 6,
                    menu: [(2, 2), (3, 2), (3, 3), (4, 3), (4, 4), (5, 4), (6, 5)].map { r, c in
                        MenuFlyoutItem(text: Text("\(c) × \(r) table"), onPressed: { [session] in session.onInsertTable?(r, c) })
                    }),
            ]),
            Chrome.group("Symbols", fluent, [
                Chrome.big(FluentSystemIcons.textT, "Symbol", fluent) { [session] in session.onSymbolDialog?() },
            ]),
            Chrome.group("Images", fluent, [
                Chrome.big(FluentSystemIcons.image, "Pictures", fluent) { [session] in session.onInsertPicture?() },
            ]),
            Chrome.group("Media", fluent, [
                Chrome.big(FluentSystemIcons.image, "Video", fluent) { [session] in session.onInsertMedia?(true) },
                Chrome.big(FluentSystemIcons.image, "Audio", fluent) { [session] in session.onInsertMedia?(false) },
            ]),
            Chrome.group("Charts", fluent, [
                FlatButton(child: Padding(padding: EdgeInsets(left: 6, top: 2, right: 6, bottom: 2),
                    child: Column(mainAxisAlignment: .center, crossAxisAlignment: .center, children: [
                        Icon(FluentSystemIcons.chartColumn, size: Chrome.bigIconSize, color: fluent.resources.textFillColorPrimary),
                        Chrome.vgap(4),
                        Text("Chart", style: fluent.typography.caption),
                    ])), tip: "Insert a chart", width: nil, height: Chrome.rowHeight * 2 + 6,
                    menu: _chartTypeItems(fluent, current: nil) { [session] type in
                        deck.addChart(type)
                        session.onChartData?(true)
                    }),
            ]),
            Chrome.group("Illustrations", fluent, [
                FlatButton(child: Padding(padding: EdgeInsets(left: 6, top: 2, right: 6, bottom: 2),
                    child: Column(mainAxisAlignment: .center, crossAxisAlignment: .center, children: [
                        Icon(FluentSystemIcons.shapes, size: Chrome.bigIconSize, color: fluent.resources.textFillColorPrimary),
                        Chrome.vgap(4),
                        Text("Shapes", style: fluent.typography.caption),
                    ])), tip: "Insert a shape", width: nil, height: Chrome.rowHeight * 2 + 6, menu: _shapeItems(fluent)),
            ]),
        ]
    }

    /// A theme as a tile: its background, "Aa" in its heading font and
    /// colour, and its first accents as dots.
    private func _themeTile(_ t: DeckTheme, on: Bool, _ fluent: FluentThemeData, _ action: @escaping () -> Void) -> Widget {
        let dots: [Widget] = t.accents.prefix(4).map { c in
            Padding(padding: EdgeInsets(left: 1.5, top: 0, right: 1.5, bottom: 0), child: SizedBox(width: 7, height: 7, child: DecoratedBox(
                decoration: BoxDecoration(color: c, borderRadius: BorderRadius.all(Radius(circular: 3.5))),
                child: SizedBox(expand: ()))))
        }
        let face = DecoratedBox(
            decoration: BoxDecoration(color: t.background,
                                      border: Border.all(color: on ? fluent.accentColor.defaultBrushFor(fluent.brightness)
                                                                 : fluent.resources.controlStrokeColorDefault, width: on ? 2 : 1),
                                      borderRadius: BorderRadius.all(Radius(circular: 3))),
            child: SizedBox(width: 64, height: 40, child: Column(mainAxisAlignment: .center, crossAxisAlignment: .center, children: [
                Text("Aa", style: Flutter.TextStyle(color: t.text, fontSize: 15,
                                                    fontFamily: OfficeFonts.substitute(t.headingFont))),
                Chrome.vgap(2),
                Row(mainAxisSize: .min, children: dots),
            ])))
        return FlatButton(child: Column(mainAxisAlignment: .center, crossAxisAlignment: .center, children: [
            face, Chrome.vgap(3), Text(t.name, style: fluent.typography.caption),
        ]), tip: "\(t.name) theme", checked: false, width: 76, height: Chrome.rowHeight * 2 + 6, action: action)
    }

    private func _design(_ deck: DeckController, _ fluent: FluentThemeData) -> [Widget] {
        let wide = abs(deck.slideSize.width / deck.slideSize.height - 16.0 / 9.0) < 0.01
        let palette = Self.shapeColors(deck.theme)
        var background: [MenuFlyoutItemBase] = [
            MenuFlyoutItem(text: Text("Format Background…"), onPressed: { [session] in session.onFormatBackground?() }),
            MenuFlyoutSeparator(),
            MenuFlyoutItem(text: Text("Theme Background"), onPressed: { deck.setBackground(nil) }),
            MenuFlyoutSeparator(),
        ]
        for (name, color) in palette {
            background.append(MenuFlyoutItem(text: Text(name), leading: Chrome.swatch(color, fluent),
                                             onPressed: { deck.setBackground(SlideFill(color: color)) }))
        }
        let a = deck.theme.accents
        background += [
            MenuFlyoutSeparator(),
            MenuFlyoutItem(text: Text("Gradient: Light"), onPressed: {
                deck.setBackground(SlideFill(color: Color(0xFFFFFFFF), stops: [
                    .init(position: 0, color: Color(0xFFFFFFFF)), .init(position: 1, color: Color(0xFFE6ECF2))], angle: 90))
            }),
            MenuFlyoutItem(text: Text("Gradient: Accent"), onPressed: {
                deck.setBackground(SlideFill(color: a[0], stops: [
                    .init(position: 0, color: a[0]), .init(position: 1, color: DeckController.darker(a[0]))], angle: 90))
            }),
            MenuFlyoutItem(text: Text("Picture…"), onPressed: { [session] in session.onBackgroundPicture?() }),
            MenuFlyoutSeparator(),
            MenuFlyoutItem(text: Text("Apply to All Slides"), onPressed: {
                deck.setBackground(deck.currentSlide.background, all: true)
            }),
        ]
        return [
            Chrome.group("Themes", fluent, DeckTheme.presets.map { t in
                _themeTile(t, on: deck.theme.name == t.name, fluent) { deck.applyTheme(t) }
            }),
            Chrome.group("Customize", fluent, [Chrome.rows([
                Chrome.menuButton(FluentSystemIcons.paintBrush, "Format Background", "Slide background", fluent, items: background),
            ])]),
            Chrome.group("Size", fluent, [
                Chrome.menuButton(FluentSystemIcons.pageFit, "Slide Size", "Slide Size", fluent, items: [
                    MenuFlyoutItem(text: Text("Standard (4:3)"),
                                   leading: Icon(wide ? FluentSystemIcons.onePage : FluentSystemIcons.check,
                                                 size: Chrome.iconSize, color: fluent.resources.textFillColorPrimary),
                                   onPressed: { [session] in session.onSlideSize?(Size(720, 540)) }),
                    MenuFlyoutItem(text: Text("Widescreen (16:9)"),
                                   leading: Icon(wide ? FluentSystemIcons.check : FluentSystemIcons.onePage,
                                                 size: Chrome.iconSize, color: fluent.resources.textFillColorPrimary),
                                   onPressed: { [session] in session.onSlideSize?(Size(960, 540)) }),
                    MenuFlyoutItem(text: Text("Custom Slide Size…"), onPressed: { [session] in session.onSlideSize?(nil) }),
                ]),
            ]),
        ]
    }

    private func _transitions(_ deck: DeckController, _ fluent: FluentThemeData) -> [Widget] {
        let t = deck.currentSlide.transition
        let icons: [SlideTransition.Kind: IconData] = [.none: FluentSystemIcons.close, .fade: FluentSystemIcons.brightness,
                                                       .push: FluentSystemIcons.forward, .wipe: FluentSystemIcons.textClearFormatting,
                                                       .cover: FluentSystemIcons.onePage, .pull: FluentSystemIcons.onePage,
                                                       .split: FluentSystemIcons.window, .zoom: FluentSystemIcons.desktop]
        let kinds: [Widget] = SlideTransition.Kind.allCases.map { kind in
            Chrome.bigToggle(icons[kind] ?? FluentSystemIcons.onePage, SlideTransition(kind: kind).name,
                             t.kind == kind && t.raw == nil, fluent) { deck.setTransition(kind) }
        }
        func option(_ name: String, _ on: Bool, _ act: @escaping () -> Void) -> MenuFlyoutItem {
            MenuFlyoutItem(text: Text(name),
                           leading: Icon(on ? FluentSystemIcons.check : FluentSystemIcons.forward, size: Chrome.iconSize,
                                         color: fluent.resources.textFillColorPrimary),
                           onPressed: act)
        }
        let directions: [(String, SlideTransition.Direction)] = [
            ("From Right", .left), ("From Left", .right), ("From Bottom", .up), ("From Top", .down),
        ]
        var options: [MenuFlyoutItemBase] = []
        switch t.kind {
        case .push, .wipe, .cover, .pull:
            options = directions.map { name, dir in option(name, t.direction == dir) { deck.setTransition(direction: dir) } }
        case .split:
            options = [option("Vertical In", t.vertical && t.inward) { deck.setTransition(vertical: true, inward: true) },
                       option("Vertical Out", t.vertical && !t.inward) { deck.setTransition(vertical: true, inward: false) },
                       option("Horizontal In", !t.vertical && t.inward) { deck.setTransition(vertical: false, inward: true) },
                       option("Horizontal Out", !t.vertical && !t.inward) { deck.setTransition(vertical: false, inward: false) }]
        case .zoom:
            options = [option("In", t.zoomIn) { deck.setTransition(zoomIn: true) },
                       option("Out", !t.zoomIn) { deck.setTransition(zoomIn: false) }]
        case .none, .fade:
            options = [MenuFlyoutItem(text: Text("No options"), onPressed: nil)]
        }
        let after = t.advanceAfter
        return [
            Chrome.group("Transition to This Slide", fluent, kinds + [
                Chrome.gap(4),
                Chrome.rows([Chrome.menuButton(FluentSystemIcons.settings, "Effect Options", "Effect Options", fluent, items: options)]),
            ]),
            Chrome.group("Timing", fluent, [Chrome.rows([
                // Stepped in hundredths of a second, shown in seconds like the
                // Animations tab's ("0.5 s", not "50 cs").
                Chrome.spinner("Duration", t.duration * 100, fluent, step: 25, minimum: 10,
                               shown: ChartPainter.label(t.duration, percent: false) + " s") { v in
                    deck.setTransition(duration: v / 100)
                },
                Chrome.small(FluentSystemIcons.copy, "Apply To All", fluent) { deck.setTransition(all: true) },
            ])]),
            Chrome.group("Advance Slide", fluent, [Chrome.rows([
                Chrome.small(t.advanceOnClick ? FluentSystemIcons.check : FluentSystemIcons.close, "On Mouse Click", fluent) {
                    deck.setTransition(advanceOnClick: !t.advanceOnClick)
                },
                Chrome.small(after != nil ? FluentSystemIcons.check : FluentSystemIcons.close, "After", fluent) {
                    deck.setTransition(advanceAfter: .some(after == nil ? 5 : nil))
                },
                Chrome.spinner("Seconds", after ?? 0, fluent, step: 1, unit: "s", minimum: 0,
                               shown: after == nil ? "Off" : ChartPainter.label(after!, percent: false) + " s") { v in
                    deck.setTransition(advanceAfter: .some(v))
                },
            ])]),
        ]
    }

    private func _slideShowTab(_ deck: DeckController, _ fluent: FluentThemeData) -> [Widget] {
        [
            Chrome.group("Start Slide Show", fluent, [
                Chrome.big(FluentSystemIcons.desktop, "From Beginning", fluent) { [session] in session.onSlideShow?(false) },
                Chrome.big(FluentSystemIcons.window, "From Current Slide", fluent) { [session] in session.onSlideShow?(true) },
                Chrome.big(FluentSystemIcons.laptop, "Presenter View", fluent) { [session] in session.onPresenterView?() },
                Chrome.big(FluentSystemIcons.bulletList, "Custom Slide Show", fluent) { [session] in session.onCustomShows?() },
            ]),
            Chrome.group("Set Up", fluent, [
                Chrome.big(FluentSystemIcons.settings, "Set Up Slide Show", fluent) { [session] in session.onSetUpShow?() },
                Chrome.big(deck.currentSlide.hidden ? FluentSystemIcons.check : FluentSystemIcons.pinOff,
                           "Hide Slide", fluent) { [deck] in deck.toggleHidden(deck.current) },
                Chrome.big(FluentSystemIcons.clock, "Rehearse Timings", fluent) { [session] in session.onRehearse?() },
            ]),
        ]
    }

    /// PowerPoint's Animations tab, for entrances: preview, the gallery,
    /// effect options, timing, the pane and order.
    private func _animationsTab(_ deck: DeckController, _ fluent: FluentThemeData) -> [Widget] {
        let selected = deck.selectedAnimations
        let first = selected.first
        let ink = fluent.resources.textFillColorPrimary
        let preview = Chrome.group("Preview", fluent, [
            Chrome.big(FluentSystemIcons.readMode, "Preview", fluent) { [session] in session.onSlideShow?(true) },
        ])
        guard deck.canAnimate else {
            return [preview, Chrome.group("Animation", fluent, [
                Padding(padding: EdgeInsets(left: 8, top: 0, right: 8, bottom: 0), child: SizedBox(width: 260, height: nil, child: Text(
                    "This slide's animations come from the file and are kept as they are — this app does not edit them.",
                    style: fluent.typography.caption))),
            ])]
        }
        func effectIcon(_ e: ShapeAnimation.Effect?) -> IconData {
            switch e {
            case nil: return FluentSystemIcons.close
            case .appear?: return FluentSystemIcons.bolt
            case .fade?: return FluentSystemIcons.brightness
            case .flyIn?: return FluentSystemIcons.up
            case .wipe?: return FluentSystemIcons.paintBrush
            case .zoom?: return FluentSystemIcons.zoomIn
            }
        }
        let anySelected = !deck.selection.isEmpty
        var gallery: [Widget] = [
            Chrome.bigToggle(effectIcon(nil), "None", anySelected && selected.isEmpty, fluent) { deck.setEntrance(nil) },
        ]
        for e in ShapeAnimation.Effect.allCases {
            gallery.append(Chrome.bigToggle(effectIcon(e), e.name, first?.effect == e, fluent) { deck.setEntrance(e) })
        }
        var options: [MenuFlyoutItemBase] = []
        if let f = first, f.effect.hasDirection {
            options += ShapeAnimation.Direction.allCases.map { d in
                MenuFlyoutItem(text: Text(d.name),
                               leading: Icon(f.direction == d ? FluentSystemIcons.check : FluentSystemIcons.up,
                                             size: Chrome.iconSize, color: ink),
                               onPressed: { deck.editAnimations { $0.direction = d } })
            }
        }
        if deck.selection.contains(where: { $0.text != nil }), first != nil {
            let byParagraph = deck.selectionByParagraph
            options += [
                MenuFlyoutItem(text: Text("As One Object"),
                               leading: Icon(byParagraph ? FluentSystemIcons.shapes : FluentSystemIcons.check, size: Chrome.iconSize, color: ink),
                               onPressed: { deck.setByParagraph(false) }),
                MenuFlyoutItem(text: Text("By Paragraph"),
                               leading: Icon(byParagraph ? FluentSystemIcons.check : FluentSystemIcons.bulletList, size: Chrome.iconSize, color: ink),
                               onPressed: { deck.setByParagraph(true) }),
            ]
        }
        func seconds(_ v: Double) -> String { ChartPainter.label(v, percent: false) + " s" }
        let timing = Chrome.group("Timing", fluent, [Chrome.rows([
            Chrome.menuButton(FluentSystemIcons.clock, "Start: \(first?.start.name ?? "On Click")", "When the animation starts", fluent,
                              items: ShapeAnimation.Start.allCases.map { st in
                                  MenuFlyoutItem(text: Text(st.name),
                                                 leading: Icon(first?.start == st ? FluentSystemIcons.check : FluentSystemIcons.clock,
                                                               size: Chrome.iconSize, color: ink),
                                                 onPressed: { deck.editAnimations { $0.start = st } })
                              }),
            Chrome.menuButton(FluentSystemIcons.history, "Duration: \(seconds(first?.duration ?? 0.5))", "How long it takes", fluent,
                              items: [0.25, 0.5, 0.75, 1, 1.5, 2, 3].map { v in
                                  MenuFlyoutItem(text: Text(seconds(v)), onPressed: { deck.editAnimations { $0.duration = v } })
                              }),
        ]), Chrome.rows([
            Chrome.menuButton(FluentSystemIcons.history, "Delay: \(seconds(first?.delay ?? 0))", "A pause before it starts", fluent,
                              items: [0, 0.25, 0.5, 1, 2, 3].map { v in
                                  MenuFlyoutItem(text: Text(seconds(v)), onPressed: { deck.editAnimations { $0.delay = v } })
                              }),
        ])])
        let index = first.flatMap { f in deck.currentSlide.animations.firstIndex(of: f) }
        let order = Chrome.group("Order", fluent, [Chrome.rows([
            Chrome.small(FluentSystemIcons.chevronUp, "Move Earlier", fluent, enabled: (index ?? 0) > 0) {
                if let i = index { deck.moveAnimation(i, by: -1) }
            },
            Chrome.small(FluentSystemIcons.chevronDown, "Move Later", fluent,
                         enabled: index.map { $0 < deck.currentSlide.animations.count - 1 } ?? false) {
                if let i = index { deck.moveAnimation(i, by: 1) }
            },
        ])])
        return [
            preview,
            Chrome.group("Animation", fluent, gallery + [
                Chrome.menuButton(FluentSystemIcons.settings, "Effect Options", "Direction and sequence", fluent, items: options),
            ]),
            timing,
            Chrome.group("Advanced", fluent, [
                Chrome.big(FluentSystemIcons.numberList, "Animation Pane", fluent) { [session] in session.onAnimationPane?() },
            ]),
            order,
        ]
    }

    private func _chartTypeItems(_ fluent: FluentThemeData, current: ChartType?,
                                 _ pick: @escaping (ChartType) -> Void) -> [MenuFlyoutItemBase] {
        ChartType.allCases.map { type in
            MenuFlyoutItem(text: Text(type.name),
                           leading: Icon(current == type ? FluentSystemIcons.check : type.icon,
                                         size: Chrome.iconSize, color: fluent.resources.textFillColorPrimary),
                           onPressed: { pick(type) })
        }
    }

    /// The selected chart's tab: its kind, its data, the parts it shows.
    private func _chartDesign(_ deck: DeckController, _ fluent: FluentThemeData) -> [Widget] {
        guard let shape = deck.selectedChart, let chart = shape.chart else { return [] }
        func set(_ edit: @escaping (inout Chart) -> Void) -> () -> Void {
            { var c = chart; edit(&c); deck.setChart(shape, c) }
        }
        let axes = chart.type.hasAxes
        let stackable = [.column, .bar, .line, .area].contains(chart.type)
        let groupings: [(String, Bool, Bool)] = [("Clustered", false, false), ("Stacked", true, false), ("100% Stacked", true, true)]
        return [
            Chrome.group("Type", fluent, [
                FlatButton(child: Padding(padding: EdgeInsets(left: 6, top: 2, right: 6, bottom: 2),
                    child: Column(mainAxisAlignment: .center, crossAxisAlignment: .center, children: [
                        Icon(chart.type.icon, size: Chrome.bigIconSize, color: fluent.resources.textFillColorPrimary),
                        Chrome.vgap(4),
                        Text("Change Chart Type", style: fluent.typography.caption),
                    ])), tip: "Change the kind of chart", width: nil, height: Chrome.rowHeight * 2 + 6,
                    menu: _chartTypeItems(fluent, current: chart.type) { type in
                        deck.setChart(shape, chart.converted(to: type))
                    }),
            ]),
            Chrome.group("Data", fluent, [
                Chrome.big(FluentSystemIcons.tableEdit, "Edit Data", fluent) { [session] in session.onChartData?(true) },
            ]),
            Chrome.group("Chart Elements", fluent, [
                Chrome.rows([
                    Chrome.small(chart.title != nil ? FluentSystemIcons.check : FluentSystemIcons.textT, "Chart Title", fluent,
                                 action: set { $0.title = $0.title == nil ? ($0.series.count == 1 ? $0.series[0].name : "Chart Title") : nil }),
                    Chrome.small(chart.legend ? FluentSystemIcons.check : FluentSystemIcons.bulletList, "Legend", fluent,
                                 action: set { $0.legend.toggle() }),
                    Chrome.small(chart.dataLabels ? FluentSystemIcons.check : FluentSystemIcons.pageNumber, "Data Labels", fluent,
                                 action: set { $0.dataLabels.toggle() }),
                ]),
                Chrome.rows([
                    Chrome.small(chart.valueAxisTitle != nil ? FluentSystemIcons.check : FluentSystemIcons.textT, "Axis Titles", fluent,
                                 enabled: axes, action: set { c in
                                     let on = c.valueAxisTitle != nil
                                     c.valueAxisTitle = on ? nil : "Axis Title"
                                     c.categoryAxisTitle = on ? nil : "Axis Title"
                                 }),
                    Chrome.menuButton(FluentSystemIcons.chartColumn, "Grouping", "Clustered or stacked", fluent,
                                      items: stackable ? groupings.map { name, stacked, percent in
                                          MenuFlyoutItem(text: Text(name),
                                                         leading: Icon(chart.stacked == stacked && chart.percent == percent
                                                                       ? FluentSystemIcons.check : chart.type.icon,
                                                                       size: Chrome.iconSize, color: fluent.resources.textFillColorPrimary),
                                                         onPressed: set { $0.stacked = stacked; $0.percent = percent })
                                      } : []),
                ]),
            ]),
            Chrome.group("Arrange", fluent, [Chrome.rows([
                Chrome.small(FluentSystemIcons.delete, "Delete Chart", fluent) { deck.deleteSelection() },
            ])]),
        ]
    }

    private func _slidePictureFormat(_ deck: DeckController, _ fluent: FluentThemeData) -> [Widget] {
        let crops: [(String, Double)] = [("Square", 1), ("4:3", 4.0 / 3), ("3:2", 1.5), ("16:9", 16.0 / 9), ("3:4 Portrait", 0.75)]
        return [
            Chrome.group("Adjust", fluent, [
                Chrome.big(FluentSystemIcons.refresh, "Reset Picture", fluent) { deck.resetPictures() },
                Chrome.big(FluentSystemIcons.info, "Alt Text", fluent) { [session] in session.onAltText?() },
            ]),
            Chrome.group("Size", fluent, [Chrome.rows([
                Chrome.menuButton(FluentSystemIcons.pageFit, "Crop to Aspect", "Crop the picture to a shape", fluent,
                                  items: crops.map { name, ratio in
                                      MenuFlyoutItem(text: Text(name), onPressed: { deck.cropPictures(aspect: ratio) })
                                  }),
            ])]),
            Chrome.group("Arrange", fluent, [Chrome.rows([
                Chrome.small(FluentSystemIcons.chevronUp, "Bring to Front", fluent) { deck.arrange(.front) },
                Chrome.small(FluentSystemIcons.chevronDown, "Send to Back", fluent) { deck.arrange(.back) },
            ])]),
        ]
    }

    private func _slidesView(_ fluent: FluentThemeData) -> [Widget] {
        [
            Chrome.group("Presentation Views", fluent, [
                Chrome.bigToggle(FluentSystemIcons.onePage, "Normal", !session.slidesSorter && !session.slidesOutline && !(session.deck?.notesPageView ?? false), fluent) { [session] in
                    session.onSlidesView?(false)
                },
                Padding(key: ValueKey("view.outline"), padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 0),
                        child: Chrome.bigToggle(FluentSystemIcons.document, "Outline View", session.slidesOutline && !session.slidesSorter, fluent) { [session] in
                    session.onSlidesOutline?()
                }),
                Padding(key: ValueKey("view.notesPage"), padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 0),
                        child: Chrome.bigToggle(FluentSystemIcons.document, "Notes Page", (session.deck?.notesPageView ?? false) && !session.slidesSorter, fluent) { [session] in
                    session.onSlidesNotesPage?()
                }),
                Chrome.bigToggle(FluentSystemIcons.grid, "Slide Sorter", session.slidesSorter, fluent) { [session] in
                    session.onSlidesView?(true)
                },
            ]),
            Chrome.group("Zoom", fluent, [
                Padding(key: ValueKey("view.zoomIn"), padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 0), child: Chrome.big(FluentSystemIcons.zoomIn, "Zoom In", fluent) { [session] in session.deck?.stepViewZoom(1) }),
                Padding(key: ValueKey("view.zoomOut"), padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 0), child: Chrome.big(FluentSystemIcons.zoomOut, "Zoom Out", fluent) { [session] in session.deck?.stepViewZoom(-1) }),
                Padding(key: ValueKey("view.fit"), padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 0), child: Chrome.big(FluentSystemIcons.pageFit, "Fit to Window", fluent) { [session] in session.deck?.fitView() }),
            ]),
        ]
    }
}

extension Ribbon {
    /// Table Design: the table's header row and banded rows, each one undo step.
    func _slideTableDesign(_ deck: DeckController, _ fluent: FluentThemeData) -> [Widget] {
        let o = deck.selectedTableOptions ?? DeckController.TableOptions()
        let shading = Chrome.colorMenu(FluentSystemIcons.highlight, "Shading", fluent,
                                       colors: OfficeColors.highlight, none: "No Shading", title: "Shading") { col in
            // The cells the user selected; with no cell selection, the whole table.
            let t = deck.selection.first?.text
            let block = t.flatMap { $0.selection.block ?? ($0.selection.isCollapsed ? nil : $0.targetCellBlock) }
            deck.setTableShading(col, block: block)
        }
        var looks: [(String, DeckController.TableLook)] = [("No Style, Table Grid", .plain)]
        for i in 0 ..< min(6, deck.theme.accents.count) { looks.append(("Medium Style 2 - Accent \(i + 1)", .accent(i))) }
        func menu(_ title: String, _ tip: String, _ looks: [(String, DeckController.TableLook, Color?)]) -> Widget {
            Chrome.menuButton(FluentSystemIcons.grid, title, tip, fluent,
                items: looks.map { name, look, swatch in
                    MenuFlyoutItem(text: Text(name), leading: SizedBox(width: 14, height: 14, child: DecoratedBox(decoration: BoxDecoration(
                                       color: swatch ?? deck.tableLookColor(look) ?? Color(0xFFFFFFFF),
                                       border: Border.all(color: fluent.resources.controlStrokeColorDefault, width: 1)))),
                                   onPressed: { deck.applyTableLook(look) }) as MenuFlyoutItemBase })
        }
        let styles = menu("Table Styles", "Choose a table style", looks.map { ($0.0, $0.1, nil) })
        // The built-in families, as PowerPoint groups them: Themed, Light, Medium (1, 3, 4), Dark.
        func family(_ word: String) -> [(String, DeckController.TableLook, Color?)] {
            var out: [(String, DeckController.TableLook, Color?)] = []
            for (name, plain, accents) in PptxTemplates.builtinTableStyleFamilyList where name.hasPrefix(word) && name != "Medium Style 2" {
                if let plain { out.append((name, .builtin(plain), word == "Dark" ? Color(0xFF404040) : Color(0xFFFFFFFF))) }
                // Dark Style 2 has three ids, each for a PAIR of accents (1/2, 3/4, 5/6): header and body take one each.
                let paired = accents.count == 3
                for (i, id) in accents.enumerated() {
                    let a = paired ? i * 2 : i
                    guard a < deck.theme.accents.count else { continue }
                    let label = paired ? "Accent \(a + 1)/Accent \(a + 2)" : "Accent \(a + 1)"
                    out.append(("\(name) - \(label)", .builtin(id), deck.theme.accents[a]))
                }
            }
            return out
        }
        let more = [menu("Themed", "Themed table styles", family("Themed")), menu("Light", "Light table styles", family("Light")),
                    menu("Medium", "Medium table styles", family("Medium")), menu("Dark", "Dark table styles", family("Dark"))]
        // Borders and the pen: the cells the user selected, else the whole table.
        func block() -> CellBlock? {
            let t = deck.selection.first?.text
            return t.flatMap { $0.selection.block ?? ($0.selection.isCollapsed ? nil : $0.targetCellBlock) }
        }
        func lay(_ sides: Set<DeckController.TableBorderSide>, erase: Bool = false) -> () -> Void {
            { deck.setTableBorders(sides, line: erase ? nil : deck.tablePen.line, block: block()) }
        }
        let outside: Set<DeckController.TableBorderSide> = [.top, .bottom, .left, .right]
        let borderItems: [MenuFlyoutItemBase] = [
            MenuFlyoutItem(text: Text("Bottom Border"), onPressed: lay([.bottom])),
            MenuFlyoutItem(text: Text("Top Border"), onPressed: lay([.top])),
            MenuFlyoutItem(text: Text("Left Border"), onPressed: lay([.left])),
            MenuFlyoutItem(text: Text("Right Border"), onPressed: lay([.right])),
            MenuFlyoutSeparator(),
            MenuFlyoutItem(text: Text("No Border"), onPressed: lay(Set(DeckController.TableBorderSide.allCases), erase: true)),
            MenuFlyoutItem(text: Text("All Borders"), onPressed: lay(Set(DeckController.TableBorderSide.allCases))),
            MenuFlyoutItem(text: Text("Outside Borders"), onPressed: lay(outside)),
            MenuFlyoutItem(text: Text("Inside Borders"), onPressed: lay([.insideH, .insideV])),
            MenuFlyoutItem(text: Text("Inside Horizontal Border"), onPressed: lay([.insideH])),
            MenuFlyoutItem(text: Text("Inside Vertical Border"), onPressed: lay([.insideV])),
        ]
        let dashItems: [MenuFlyoutItemBase] = DeckController.penDashes.map { d in
            MenuFlyoutItem(text: Text((deck.tablePen.dash == d.name ? "✓ " : "") + d.label), onPressed: { deck.tablePen.dash = d.name; deck.notifyViewChanged() }) }
        let weightItems: [MenuFlyoutItemBase] = DeckController.penWeights.map { w in
            let label = w == w.rounded() ? "\(Int(w))" : "\(w)"
            return MenuFlyoutItem(text: Text((deck.tablePen.width == w ? "✓ " : "") + label + " pt"), onPressed: { deck.tablePen.width = w; deck.notifyViewChanged() }) }
        let penColor = Chrome.colorMenu(FluentSystemIcons.textColor, "Pen Color", fluent,
                                        colors: OfficeColors.text, none: "Automatic") { col in
            deck.tablePen.color = col ?? Color(0xFF000000); deck.notifyViewChanged() }
        let bordersGroup = Chrome.group("Draw Borders", fluent, [
            Chrome.rows([Chrome.menuButton(FluentSystemIcons.table, "Borders", "Borders", fluent, items: borderItems),
                         Chrome.menuButton(nil, "Pen Style", "Pen style", fluent, items: dashItems),
                         Chrome.menuButton(nil, "Pen Weight", "Pen weight", fluent, items: weightItems)]),
            Chrome.gap(8),
            Chrome.rows([penColor,
                         Chrome.textToggle("Draw Borders", deck.tableTool == .draw, fluent) { deck.tableTool = deck.tableTool == .draw ? .none : .draw },
                         Chrome.textToggle("Eraser", deck.tableTool == .erase, fluent) { deck.tableTool = deck.tableTool == .erase ? .none : .erase }]),
            Chrome.gap(8),
            Chrome.rows([Chrome.textToggle("Reset to Table Style", false, fluent) { deck.resetTableToStyle(block: block()) }]),
        ])
        return [Chrome.group("Table Styles", fluent, [Chrome.rows([styles, shading]), Chrome.rows(Array(more.prefix(2))), Chrome.rows(Array(more.suffix(2)))]),
                Chrome.group("Table Style Options", fluent, [
            Chrome.rows([
                Chrome.textToggle("Header Row", o.headerRow, fluent) { var n = o; n.headerRow.toggle(); deck.setTableOptions(n) },
                Chrome.textToggle("Total Row", o.totalRow, fluent) { var n = o; n.totalRow.toggle(); deck.setTableOptions(n) },
                Chrome.textToggle("Banded Rows", o.bandedRows, fluent) { var n = o; n.bandedRows.toggle(); deck.setTableOptions(n) },
            ]),
            Chrome.rows([
                Chrome.textToggle("First Column", o.firstColumn, fluent) { var n = o; n.firstColumn.toggle(); deck.setTableOptions(n) },
                Chrome.textToggle("Last Column", o.lastColumn, fluent) { var n = o; n.lastColumn.toggle(); deck.setTableOptions(n) },
                Chrome.textToggle("Banded Columns", o.bandedColumns, fluent) { var n = o; n.bandedColumns.toggle(); deck.setTableOptions(n) },
            ]),
        ]), bordersGroup]
    }
}
