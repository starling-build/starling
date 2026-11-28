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
        case .shapeFormat: return _slideShapeFormat(deck, fluent)
        case .chartDesign: return _chartDesign(deck, fluent)
        case .slideMaster: return _slideMasterTab(deck, fluent)
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
                Chrome.row([
                    Chrome.menuButton(FluentSystemIcons.grid, "Layout", "Slide layout", fluent,
                                      items: _slideLayoutItems(deck, fluent)),
                    _sectionMenu(deck, fluent),
                ]),
                Chrome.small(FluentSystemIcons.copy, "Duplicate", fluent) { deck.duplicateSlide(deck.current) },
                Chrome.small(FluentSystemIcons.delete, "Delete", fluent, enabled: deck.slides.count > 1) {
                    deck.deleteSlide(deck.current)
                },
            ]),
        ])
    }

    private func _sectionMenu(_ deck: DeckController, _ fluent: FluentThemeData) -> Widget {
        let si = deck.sectionIndex(ofSlide: deck.current)
        func item(_ text: String, enabled: Bool = true, _ act: @escaping () -> Void) -> MenuFlyoutItemBase {
            MenuFlyoutItem(text: Text(text), onPressed: enabled ? act : nil)
        }
        let items: [MenuFlyoutItemBase] = [
            item("Add Section") { [session] in session.onSectionName?(false) },
            item("Rename Section", enabled: si != nil) { [session] in session.onSectionName?(true) },
            item("Remove Section", enabled: si != nil) { if let si { deck.removeSection(si) } },
            item("Remove Section & Slides", enabled: si != nil && deck.sections.count > 1) { if let si { deck.removeSectionAndSlides(si) } },
            item("Remove All Sections", enabled: !deck.sections.isEmpty) { deck.removeAllSections() },
            item("Collapse All", enabled: !deck.sections.isEmpty) { deck.setAllSectionsCollapsed(true) },
            item("Expand All", enabled: !deck.sections.isEmpty) { deck.setAllSectionsCollapsed(false) },
        ]
        return Chrome.menuButton(FluentSystemIcons.bulletList, nil, "Sections", fluent, items: items)
    }

    /// Slide Master: the layouts and placeholders of the open master, and the way out.
    private func _slideMasterTab(_ deck: DeckController, _ fluent: FluentThemeData) -> [Widget] {
        let role = deck.masterPage
        func ph(_ text: String, _ type: String) -> MenuFlyoutItemBase {
            MenuFlyoutItem(text: Text(text), onPressed: { deck.insertMasterPlaceholder(type) })
        }
        return [
            Chrome.group("Edit Master", fluent, [
                Chrome.big(FluentSystemIcons.onePage, "Insert Layout", fluent) { deck.insertLayout() },
                Chrome.rows([
                    Chrome.small(FluentSystemIcons.textT, "Rename", fluent) { [session] in session.onLayoutName?() },
                    Chrome.small(FluentSystemIcons.copy, "Duplicate", fluent) { deck.duplicateLayout() },
                    Chrome.small(FluentSystemIcons.delete, "Delete", fluent) { deck.deleteLayout() },
                ]),
            ]),
            Chrome.group("Master Layout", fluent, [
                Chrome.menuButton(FluentSystemIcons.document, "Insert Placeholder", "Insert Placeholder", fluent, items: [
                    ph("Title", "title"), ph("Text", "body"), ph("Content", "obj"), ph("Picture", "pic"),
                    ph("Date", "dt"), ph("Footer", "ftr"), ph("Slide Number", "sldNum"),
                ]),
            ]),
            Chrome.group("Close", fluent, [
                Chrome.big(FluentSystemIcons.delete, "Close Master View", fluent) { [session] in session.onMasterView?(false) },
            ]),
        ]
    }

    private func _slidesHome(_ deck: DeckController, _ fluent: FluentThemeData) -> [Widget] {
        let fp = fontAndParagraphGroups(fluent)
        let editing = Chrome.group("Editing", fluent, [Chrome.rows([
            Chrome.small(FluentSystemIcons.textT, "Select All", fluent) { [session] in
                if session.onShapeSelectAll?() == true { return }
                session.controller.selectAll()
            },
            Chrome.small(FluentSystemIcons.numberList, "Selection Pane", fluent) { [session] in session.onSelectionPane?() },
            // A finger has no Shift: while this is on, a tap adds a shape to the selection or takes it out.
            Chrome.small(FluentSystemIcons.check, "Select Multiple", fluent, checked: deck.selectMultiple) { deck.setSelectMultiple(!deck.selectMultiple) },
        ])])
        return [clipboardGroup(fluent), _slidesGroup(deck, fluent), fp[0], fp[1], _drawingGroup(deck, fluent), editing]
    }

    private func _shapeItems(_ deck: DeckController, _ fluent: FluentThemeData) -> [MenuFlyoutItemBase] {
        [ShapeGridMenuItem(ink: fluent.resources.textFillColorPrimary, hover: fluent.resources.subtleFillColorSecondary,
                           recent: deck.recentShapes) { [session] preset in
            deck.useRecentShape(preset)
            session.onInsertShape?(preset)
        }]
    }

    /// Shapes, Arrange, Shape Fill and Shape Outline — PowerPoint's Drawing
    /// group, acting on the selected shapes.
    private func _drawingGroup(_ deck: DeckController, _ fluent: FluentThemeData) -> Widget {
        let arrange = _arrangeItems(deck)
        let palette = Self.shapeColors(deck.theme)
        return Chrome.group("Drawing", fluent, [Chrome.rows([
            Chrome.row([
                Chrome.menuButton(FluentSystemIcons.shapes, "Shapes", "Insert a shape", fluent, items: _shapeItems(deck, fluent)),
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

    /// Shape Format: PowerPoint's contextual tab for a selected shape, placeholder or text box (pictures get
    /// Picture Format). Its groups reuse the Drawing group's commands: Insert Shapes, Shape Styles,
    /// Accessibility, Arrange and Size.
    func _slideShapeFormat(_ deck: DeckController, _ fluent: FluentThemeData) -> [Widget] {
        let some = !deck.selection.isEmpty
        let first = deck.selection.first?.frame
        let rotate: [MenuFlyoutItemBase] = [
            MenuFlyoutItem(text: Text("Rotate Right 90°"), onPressed: some ? { deck.rotateSelection(by: 90) } : nil),
            MenuFlyoutItem(text: Text("Rotate Left 90°"), onPressed: some ? { deck.rotateSelection(by: -90) } : nil),
            MenuFlyoutItem(text: Text("Flip Vertical"), onPressed: some ? { deck.flipSelection(horizontal: false) } : nil),
            MenuFlyoutItem(text: Text("Flip Horizontal"), onPressed: some ? { deck.flipSelection(horizontal: true) } : nil),
        ]
        return [
            Chrome.group("Insert Shapes", fluent, [Chrome.rows([
                Chrome.menuButton(FluentSystemIcons.shapes, "Shapes", "Insert a shape", fluent, items: _shapeItems(deck, fluent)),
            ])]),
            Chrome.group("Shape Styles", fluent, [Chrome.menuButton(FluentSystemIcons.paintBrush, "Quick Styles",
                                                                    "Theme Styles: a fill, outline and effect from the theme", fluent,
                                                                    items: [ShapeQuickStyleMenuItem(deck: deck, hover: fluent.resources.subtleFillColorSecondary)]),
                                                  Chrome.rows([
                Chrome.row([
                    _shapeColorMenu(FluentSystemIcons.paintBrush, "Shape Fill", deck, fluent, outline: false),
                    _shapeColorMenu(FluentSystemIcons.edit, "Shape Outline", deck, fluent, outline: true),
                ]),
                Chrome.vgap(4),
                Chrome.menuButton(FluentSystemIcons.textEffects, "Shape Effects", "Shadow, glow, reflection, soft edges, bevel",
                                  fluent, items: _effectItems(deck, fluent)),
            ])]),
            Chrome.group("Accessibility", fluent, [
                Chrome.big(FluentSystemIcons.info, "Alt Text", fluent) { [session] in session.onAltText?() },
            ]),
            Chrome.group("Arrange", fluent, [Chrome.rows([
                Chrome.small(FluentSystemIcons.chevronUp, "Bring Forward", fluent) { deck.arrange(.forward) },
                Chrome.small(FluentSystemIcons.chevronDown, "Send Backward", fluent) { deck.arrange(.backward) },
                Chrome.row([
                    Chrome.menuButton(FluentSystemIcons.grid, "Align", "Order, align and distribute", fluent, items: _arrangeItems(deck)),
                    Chrome.menuButton(FluentSystemIcons.refresh, "Rotate", "Rotate or flip", fluent, items: rotate),
                ]),
            ])]),
            Chrome.group("Size", fluent, [Chrome.rows([
                Padding(key: ValueKey("shapeFormat.height"), padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 0),
                        child: Chrome.spinner("Height", first?.height ?? 0, fluent, step: 6) { v in deck.setSize(height: v) }),
                Chrome.vgap(2),
                Padding(key: ValueKey("shapeFormat.width"), padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 0),
                        child: Chrome.spinner("Width", first?.width ?? 0, fluent, step: 6) { v in deck.setSize(width: v) }),
                Chrome.vgap(2),
                Chrome.small(FluentSystemIcons.settings, "Format Shape…", fluent) { [session] in session.onFormatShape?() },
            ])]),
        ]
    }

    /// The Arrange menu: order, group, rotate, align and distribute the selected shapes.
    private func _arrangeItems(_ deck: DeckController) -> [MenuFlyoutItemBase] {
        let some = !deck.selection.isEmpty
        return [
            MenuFlyoutItem(text: Text("Bring to Front"), onPressed: some ? { deck.arrange(.front) } : nil),
            MenuFlyoutItem(text: Text("Send to Back"), onPressed: some ? { deck.arrange(.back) } : nil),
            MenuFlyoutItem(text: Text("Bring Forward"), onPressed: some ? { deck.arrange(.forward) } : nil),
            MenuFlyoutItem(text: Text("Send Backward"), onPressed: some ? { deck.arrange(.backward) } : nil),
            MenuFlyoutSeparator(),
            MenuFlyoutItem(text: Text("Group"), onPressed: deck.canGroup ? { deck.groupSelection() } : nil),
            MenuFlyoutItem(text: Text("Ungroup"), onPressed: deck.canUngroup ? { deck.ungroupSelection() } : nil),
            MenuFlyoutItem(text: Text("Regroup"), onPressed: deck.canRegroup ? { deck.regroupSelection() } : nil),
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
            MenuFlyoutItem(key: ValueKey("arrange.distributeH"), text: Text("Distribute Horizontally"),
                           onPressed: deck.canDistribute ? { deck.distribute(horizontal: true) } : nil),
            MenuFlyoutItem(key: ValueKey("arrange.distributeV"), text: Text("Distribute Vertically"),
                           onPressed: deck.canDistribute ? { deck.distribute(horizontal: false) } : nil),
            MenuFlyoutSeparator(),
            MenuFlyoutItem(key: ValueKey("arrange.toSlide"), text: Text((deck.alignsBySlide ? "✓ " : "") + "Align to Slide"),
                           onPressed: { deck.setAlignToSlide(true) }),
            MenuFlyoutItem(key: ValueKey("arrange.toSelection"), text: Text((deck.alignsBySlide ? "" : "✓ ") + "Align Selected Objects"),
                           onPressed: deck.selection.count > 1 ? { deck.setAlignToSlide(false) } : nil),
            MenuFlyoutSeparator(),
            MenuFlyoutItem(key: ValueKey("arrange.reroute"), text: Text("Reroute Connectors"),
                           onPressed: deck.reroutableLines.isEmpty ? nil : { deck.rerouteConnectors() }),
            MenuFlyoutSeparator(),
            MenuFlyoutItem(text: Text("Format Shape…"), onPressed: some ? { [session] in session.onFormatShape?() } : nil),
        ]
    }

    /// Shape Effects: PowerPoint's presets for shadow, glow, reflection, soft edges and bevel.
    private func _effectItems(_ deck: DeckController, _ fluent: FluentThemeData, threeD: Bool = true) -> [MenuFlyoutItemBase] {
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
        // 3-D Rotation, grouped as PowerPoint's gallery is: no rotation, then parallel, perspective and oblique.
        let groups: [(String, (String) -> Bool)] = [
            ("Parallel", { $0.hasPrefix("isometric") }), ("Perspective", { $0.hasPrefix("perspective") }),
            ("Oblique", { $0.hasPrefix("oblique") }),
        ]
        let rotations: [MenuFlyoutItemBase] = [item("fx.rotation.orthographicFront", "No Rotation") { deck.setCamera("orthographicFront") }]
            + groups.map { name, test in
                MenuFlyoutSubItem(text: Text(name), items: Extrusion.rotationPresets.filter { test($0.0) }.map { prst, label in
                    item("fx.rotation.\(prst)", label) { deck.setCamera(prst) } })
            }
        return [
            item("fx.clear", "No Effects") { deck.clearEffects() },
            MenuFlyoutSeparator(),
            MenuFlyoutSubItem(text: Text("Shadow"), items: shadows),
            MenuFlyoutSubItem(text: Text("Reflection"), items: reflections),
            MenuFlyoutSubItem(text: Text("Glow"), items: glows),
            MenuFlyoutSubItem(text: Text("Soft Edges"), items: soft),
        ] + (threeD ? [MenuFlyoutSubItem(text: Text("Bevel"), items: bevels),
                       MenuFlyoutSubItem(text: Text("3-D Rotation"), items: rotations)] : [])
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
                                 outline: Bool, arrows: Bool = true) -> Widget {
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
            for (start, label) in arrows ? [(true, "Arrow start"), (false, "Arrow end")] : [] {
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
            Chrome.group("Accessibility", fluent, [
                Chrome.big(FluentSystemIcons.info, "Alt Text", fluent, enabled: !deck.selection.isEmpty) { [session] in session.onAltText?() },
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
                Chrome.big(FluentSystemIcons.video, "Video", fluent) { [session] in session.onInsertMedia?(true) },
                Chrome.big(FluentSystemIcons.music, "Audio", fluent) { [session] in session.onInsertMedia?(false) },
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
                    ])), tip: "Insert a shape", width: nil, height: Chrome.rowHeight * 2 + 6, menu: _shapeItems(deck, fluent)),
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
            options = []
        }
        let after = t.advanceAfter
        return [
            Chrome.group("Transition to This Slide", fluent, kinds + [
                Chrome.gap(4),
                Chrome.rows([Chrome.menuButton(FluentSystemIcons.settings, "Effect Options", "Effect Options", fluent, items: options,
                                                 enabled: !options.isEmpty)]),
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
                Chrome.menuButton(FluentSystemIcons.settings, "Effect Options", "Direction and sequence", fluent, items: options,
                                  enabled: !options.isEmpty),
            ]),
            timing,
            Chrome.group("Advanced", fluent, [
                Chrome.big(FluentSystemIcons.numberList, "Animation Pane", fluent) { [session] in session.onAnimationPane?() },
            ]),
            order,
        ]
    }

    func _chartTypeItems(_ fluent: FluentThemeData, current: ChartType?,
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
        return chartDesignGroups(chart, fluent, theme: deck.theme, set: { deck.setChart(shape, $0) },
                                 altText: { [session] in session.onAltText?() }, delete: { deck.deleteSelection() })
    }

    /// The Chart Design tab of `chart` (Slides' and Word's): its kind, its data, the parts it shows. `set` makes a
    /// changed chart the selected one's; Edit Data opens the host's data pane (`onChartData`).
    func chartDesignGroups(_ chart: Chart, _ fluent: FluentThemeData, theme: DeckTheme, set apply: @escaping (Chart) -> Void,
                           altText: @escaping () -> Void, delete: @escaping () -> Void) -> [Widget] {
        func set(_ edit: @escaping (inout Chart) -> Void) -> () -> Void {
            { var c = chart; edit(&c); apply(c) }
        }
        let axes = chart.type.hasAxes
        let stackable = [.column, .bar, .line, .area].contains(chart.type)
        let groupings: [(String, Bool, Bool)] = [("Clustered", false, false), ("Stacked", true, false), ("100% Stacked", true, true)]
        let layouts = ChartQuickLayout.layouts(for: chart)
        return [
            Chrome.group("Type", fluent, [
                FlatButton(child: Padding(padding: EdgeInsets(left: 6, top: 2, right: 6, bottom: 2),
                    child: Column(mainAxisAlignment: .center, crossAxisAlignment: .center, children: [
                        Icon(chart.type.icon, size: Chrome.bigIconSize, color: fluent.resources.textFillColorPrimary),
                        Chrome.vgap(4),
                        Text("Change Chart Type", style: fluent.typography.caption),
                    ])), tip: "Change the kind of chart", width: nil, height: Chrome.rowHeight * 2 + 6,
                    menu: _chartTypeItems(fluent, current: chart.type) { type in apply(chart.converted(to: type)) }),
            ]),
            Chrome.group("Data", fluent, [
                Chrome.big(FluentSystemIcons.tableEdit, "Edit Data", fluent) { [session] in session.onChartData?(true) },
            ]),
        ] + (layouts.isEmpty ? [] : [
            Chrome.group("Chart Layouts", fluent, [Chrome.rows([
                Chrome.menuButton(FluentSystemIcons.grid, "Quick Layout", "Set the chart's elements in one step", fluent,
                                  items: layouts.map { layout in
                                      MenuFlyoutItem(text: Text(layout.name + "  (" + layout.summary + ")"),
                                                     leading: Icon(layout.matches(chart) ? FluentSystemIcons.check : FluentSystemIcons.grid,
                                                                   size: Chrome.iconSize, color: fluent.resources.textFillColorPrimary),
                                                     onPressed: { apply(layout.applied(to: chart)) })
                                  }),
            ])]),
        ] as [Widget]) + [
            Chrome.group("Chart Styles", fluent, [Chrome.rows([
                Chrome.menuButton(FluentSystemIcons.paintBrush, "Change Colors", "Colour the series from the theme", fluent,
                                  items: _paletteItems(chart, fluent, theme: theme, apply: apply)),
            ])]),
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
                    Chrome.menuButton(FluentSystemIcons.bulletList, "Legend Position", "Where the legend sits", fluent,
                                      items: chart.legend ? [("Right", "r"), ("Top", "t"), ("Left", "l"), ("Bottom", "b")].map { name, pos in
                                          MenuFlyoutItem(text: Text(name),
                                                         leading: Icon(chart.legendPosition == pos ? FluentSystemIcons.check : FluentSystemIcons.bulletList,
                                                                       size: Chrome.iconSize, color: fluent.resources.textFillColorPrimary),
                                                         onPressed: set { $0.legendPosition = pos })
                                      } : []),
                ]),
            ]),
            Chrome.group("Accessibility", fluent, [
                Chrome.big(FluentSystemIcons.info, "Alt Text", fluent, action: altText),
            ]),
            Chrome.group("Arrange", fluent, [Chrome.rows([
                Chrome.small(FluentSystemIcons.delete, "Delete Chart", fluent, action: delete),
            ])]),
        ]
    }

    /// Change Colors: Office's colourful palettes, then its monochromatic ones, each with its first colours, the
    /// current one ticked.
    private func _paletteItems(_ chart: Chart, _ fluent: FluentThemeData, theme: DeckTheme,
                               apply: @escaping (Chart) -> Void) -> [MenuFlyoutItemBase] {
        let accents = theme.accents, dark = theme.text
        func item(_ p: ChartPalette) -> MenuFlyoutItemBase {
            let n = chart.type.isPie ? chart.categories.count : chart.series.count
            let swatches = (0 ..< max(1, min(4, n))).map { i -> Widget in
                let c = ChartPalette.resolve(p.element(i, of: max(1, n)), accents: accents, dark: dark) ?? dark
                return Padding(padding: EdgeInsets(left: 0, top: 0, right: 2, bottom: 0),
                               child: SizedBox(width: 10, height: 10, child: ColoredBox(color: c)))
            }
            let tick: Widget = p.matches(chart, accents: accents, dark: dark)
                ? Icon(FluentSystemIcons.check, size: Chrome.iconSize, color: fluent.resources.textFillColorPrimary)
                : SizedBox(width: Chrome.iconSize, height: Chrome.iconSize)
            return MenuFlyoutItem(text: Text(p.name), leading: Row(mainAxisSize: .min, children: [tick, SizedBox(width: 4)] + swatches),
                                  onPressed: { apply(p.applied(to: chart, accents: accents, dark: dark)) })
        }
        return ChartPalette.colorful.map(item) + [MenuFlyoutSeparator()] + ChartPalette.monochromatic.map(item)
    }

    /// Picture Format > Transparency: PowerPoint's presets, the current one ticked.
    private func _pictureTransparencyMenu(_ deck: DeckController, _ fluent: FluentThemeData) -> Widget {
        let current: Double? = deck.selection.first { $0.picture != nil }.map { (1 - $0.pictureAlpha) * 100 }
        let presets: [Double] = [0, 15, 30, 50, 65, 80, 95]
        let items: [MenuFlyoutItem] = presets.map { (pct: Double) -> MenuFlyoutItem in
            let on = current.map { abs($0 - pct) < 0.5 } ?? false
            let icon = Icon(on ? FluentSystemIcons.check : FluentSystemIcons.brightness,
                            size: Chrome.iconSize, color: fluent.resources.textFillColorPrimary)
            return MenuFlyoutItem(text: Text("Transparency: \(Int(pct))%"), leading: icon,
                                  onPressed: { deck.setPictureTransparency(pct) })
        }
        return Chrome.menuButton(FluentSystemIcons.brightness, "Transparency", "How much of the slide shows through the picture", fluent, items: items)
    }

    /// Picture Format > Corrections: PowerPoint's Brightness/Contrast grid (-40...+40 % in steps of 20 each), and a reset.
    private func _pictureCorrectionsMenu(_ deck: DeckController, _ fluent: FluentThemeData) -> Widget {
        let pic = deck.selection.first { $0.picture != nil }
        let aspect = pic.map { $0.frame.width / max(1, $0.frame.height) } ?? 4.0 / 3
        let grid = CorrectionsGridMenuItem(
            image: { [weak deck] in pic?.picture.flatMap { deck?.pictureImages?.image($0) } }, aspect: aspect,
            current: pic.map { ($0.pictureBrightness * 100, $0.pictureContrast * 100) },
            accent: fluent.accentColor.defaultBrushFor(fluent.brightness), hover: fluent.resources.subtleFillColorSecondary,
            onChoose: { b, c in deck.setPictureCorrection(brightness: b, contrast: c) })
        return Chrome.menuButton(FluentSystemIcons.brightness, "Corrections", "Brightness and contrast of the picture", fluent,
                                 items: pic == nil ? [] : [grid])
    }

    private func _slidePictureFormat(_ deck: DeckController, _ fluent: FluentThemeData) -> [Widget] {
        let crops: [(String, Double)] = [("Square", 1), ("4:3", 4.0 / 3), ("3:2", 1.5), ("16:9", 16.0 / 9), ("3:4 Portrait", 0.75)]
        return [
            Chrome.group("Adjust", fluent, [
                Chrome.big(FluentSystemIcons.image, "Change Picture", fluent) { [session] in session.onChangePicture?() },
                Chrome.big(FluentSystemIcons.refresh, "Reset Picture", fluent) { deck.resetPictures() },
                Chrome.big(FluentSystemIcons.info, "Alt Text", fluent) { [session] in session.onAltText?() },
                _pictureCorrectionsMenu(deck, fluent),
                _pictureTransparencyMenu(deck, fluent),
            ]),
            // Picture Styles: the border (colour, weight, dashes; no arrowheads) and the effects (shadow, glow,
            // reflection, soft edges) a shape has; bevel and 3-D rotation are not offered (pictures do not save scene3d/sp3d yet). (The gallery of PowerPoint's named styles waits on its values.)
            Chrome.group("Picture Styles", fluent, [Chrome.rows([
                _shapeColorMenu(FluentSystemIcons.edit, "Picture Border", deck, fluent, outline: true, arrows: false),
                Chrome.vgap(4),
                Chrome.menuButton(FluentSystemIcons.textEffects, "Picture Effects", "Shadow, glow, reflection, soft edges",
                                  fluent, items: _effectItems(deck, fluent, threeD: false)),
            ])]),
            Chrome.group("Size", fluent, [
                Chrome.bigToggle(FluentSystemIcons.cut, "Crop", deck.cropping != nil, fluent) {
                    if deck.cropping != nil { deck.endCrop() } else { deck.beginCrop() }
                },
                Chrome.rows([
                Chrome.menuButton(FluentSystemIcons.pageFit, "Crop to Aspect", "Crop to an aspect ratio, or fill or fit the frame", fluent,
                                  items: crops.map { name, ratio in
                                      MenuFlyoutItem(text: Text(name), onPressed: { deck.cropPictures(aspect: ratio) })
                                  } + [
                                      MenuFlyoutSeparator(),
                                      MenuFlyoutItem(text: Text("Fill"), onPressed: { deck.cropPictures(fit: false) }),
                                      MenuFlyoutItem(text: Text("Fit"), onPressed: { deck.cropPictures(fit: true) }),
                                  ]),
                Chrome.menuButton(FluentSystemIcons.shapes, "Crop to Shape", "Cut the picture to the outline of a shape", fluent,
                                  items: [ShapeGridMenuItem(ink: fluent.resources.textFillColorPrimary,
                                                            hover: fluent.resources.subtleFillColorSecondary,
                                                            outlinesOnly: true) { preset in deck.setPictureGeometry(preset) }]),
                ]),
            ]),
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
                Padding(key: ValueKey("view.slideMaster"), padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 0),
                        child: Chrome.bigToggle(FluentSystemIcons.document, "Slide Master", session.deck?.inMasterView ?? false, fluent) { [session] in
                    session.onMasterView?(true)
                }),
            ]),
            Chrome.group("Show", fluent, [
                Column(mainAxisSize: .min, crossAxisAlignment: .start, children: [
                    Padding(key: ValueKey("view.ruler"), padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 0), child: Chrome.textToggle("Ruler", session.deck?.showRuler ?? false, fluent) { [session] in
                        if let d = session.deck { d.setShowRuler(!d.showRuler) }
                    }),
                    Padding(key: ValueKey("view.gridlines"), padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 0), child: Chrome.textToggle("Gridlines", session.deck?.showGridlines ?? false, fluent) { [session] in
                        if let d = session.deck { d.setShowGridlines(!d.showGridlines) }
                    }),
                    Padding(key: ValueKey("view.guides"), padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 0), child: Chrome.textToggle("Guides", session.deck?.grid.showGuides ?? false, fluent) { [session] in
                        if let d = session.deck { d.setShowGuides(!d.grid.showGuides) }
                    }),
                ]),
                Padding(key: ValueKey("view.gridSettings"), padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 0), child: Chrome.big(FluentSystemIcons.grid, "Grid Settings", fluent) { [session] in session.onGridDialog?() }),
            ]),
            Chrome.group("Zoom", fluent, [
                Padding(key: ValueKey("view.zoom"), padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 0), child: Chrome.big(FluentSystemIcons.zoomIn, "Zoom", fluent) { [session] in session.onZoomDialog?() }),
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
