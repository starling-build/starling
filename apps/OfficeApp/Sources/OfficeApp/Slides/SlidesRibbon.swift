// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The ribbon's tabs for a deck: Home, Insert, Design, Transitions, Slide
// Show, Review, View. The Font and Paragraph groups are Writer's own,
// pointed at the text being edited.

import Flutter
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
        case .slideShow: return _slideShowTab(fluent)
        case .view: return _slidesView(fluent)
        case .pictureFormat: return _slidePictureFormat(deck, fluent)
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

    private func _slidesGroup(_ deck: DeckController, _ fluent: FluentThemeData) -> Widget {
        Chrome.group("Slides", fluent, [
            Chrome.big(FluentSystemIcons.add, "New Slide", fluent) { deck.addSlide() },
            FlatButton(child: Chrome.chevron(fluent), tip: "New Slide layouts", width: 16, height: 58,
                       menu: _layoutItems(fluent, current: nil) { kind in deck.addSlide(kind) }),
            Chrome.gap(2),
            Chrome.rows([
                Chrome.menuButton(FluentSystemIcons.grid, "Layout", "Slide layout", fluent,
                                  items: _layoutItems(fluent, current: deck.currentSlide.layout) { kind in
                                      deck.applyLayout(kind, to: deck.current)
                                  }),
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
        ])])
        return [clipboardGroup(fluent), _slidesGroup(deck, fluent), fp[0], fp[1], _drawingGroup(deck, fluent), editing]
    }

    private func _shapeItems(_ fluent: FluentThemeData) -> [MenuFlyoutItemBase] {
        ShapePreset.allCases.map { preset in
            MenuFlyoutItem(text: Text(preset.name),
                           leading: Icon(FluentSystemIcons.shapes, size: Chrome.iconSize,
                                         color: fluent.resources.textFillColorPrimary),
                           onPressed: { [session] in session.onInsertShape?(preset) })
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
            MenuFlyoutItem(text: Text("Align Left"), onPressed: some ? { deck.align(.left) } : nil),
            MenuFlyoutItem(text: Text("Align Center"), onPressed: some ? { deck.align(.center) } : nil),
            MenuFlyoutItem(text: Text("Align Right"), onPressed: some ? { deck.align(.right) } : nil),
            MenuFlyoutItem(text: Text("Align Top"), onPressed: some ? { deck.align(.top) } : nil),
            MenuFlyoutItem(text: Text("Align Middle"), onPressed: some ? { deck.align(.middle) } : nil),
            MenuFlyoutItem(text: Text("Align Bottom"), onPressed: some ? { deck.align(.bottom) } : nil),
        ]
        let palette = Self.shapeColors(deck.theme)
        return Chrome.group("Drawing", fluent, [Chrome.rows([
            Chrome.row([
                Chrome.menuButton(FluentSystemIcons.shapes, "Shapes", "Insert a shape", fluent, items: _shapeItems(fluent)),
                Chrome.menuButton(FluentSystemIcons.grid, "Arrange", "Order and align", fluent, items: arrange),
            ]),
            Chrome.vgap(4),
            Chrome.row([
                Chrome.colorMenu(FluentSystemIcons.paintBrush, "Shape Fill", fluent, colors: palette,
                                 none: "No Fill") { color in deck.setFill(color) },
                Chrome.colorMenu(FluentSystemIcons.edit, "Shape Outline", fluent, colors: palette,
                                 none: "No Outline") { color in deck.setOutline(color) },
            ]),
        ])])
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

    private func _slidesInsert(_ deck: DeckController, _ fluent: FluentThemeData) -> [Widget] {
        [
            _slidesGroup(deck, fluent),
            Chrome.group("Text", fluent, [
                Chrome.big(FluentSystemIcons.textT, "Text Box", fluent) { [session] in session.onInsertTextBox?() },
            ]),
            Chrome.group("Images", fluent, [
                Chrome.big(FluentSystemIcons.image, "Pictures", fluent) { [session] in session.onInsertPicture?() },
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
                                   onPressed: { deck.setSlideSize(Size(720, 540)) }),
                    MenuFlyoutItem(text: Text("Widescreen (16:9)"),
                                   leading: Icon(wide ? FluentSystemIcons.check : FluentSystemIcons.onePage,
                                                 size: Chrome.iconSize, color: fluent.resources.textFillColorPrimary),
                                   onPressed: { deck.setSlideSize(Size(960, 540)) }),
                ]),
            ]),
        ]
    }

    private func _transitions(_ deck: DeckController, _ fluent: FluentThemeData) -> [Widget] {
        let t = deck.currentSlide.transition
        let icons: [SlideTransition.Kind: IconData] = [.none: FluentSystemIcons.close, .fade: FluentSystemIcons.brightness,
                                                       .push: FluentSystemIcons.forward, .wipe: FluentSystemIcons.textClearFormatting,
                                                       .cover: FluentSystemIcons.onePage]
        let kinds: [Widget] = SlideTransition.Kind.allCases.map { kind in
            Chrome.bigToggle(icons[kind] ?? FluentSystemIcons.onePage, SlideTransition(kind: kind).name,
                             t.kind == kind && t.raw == nil, fluent) { deck.setTransition(kind) }
        }
        let directed = t.kind == .push || t.kind == .wipe || t.kind == .cover
        let directions: [(String, SlideTransition.Direction)] = [
            ("From Right", .left), ("From Left", .right), ("From Bottom", .up), ("From Top", .down),
        ]
        return [
            Chrome.group("Transition to This Slide", fluent, kinds + [
                Chrome.gap(4),
                Chrome.rows([
                    Chrome.menuButton(FluentSystemIcons.settings, "Effect Options", "Direction", fluent,
                                      items: directions.map { name, dir in
                                          MenuFlyoutItem(text: Text(name),
                                                         leading: Icon(t.direction == dir && directed ? FluentSystemIcons.check : FluentSystemIcons.forward,
                                                                       size: Chrome.iconSize, color: fluent.resources.textFillColorPrimary),
                                                         onPressed: directed ? { deck.setTransition(direction: dir) } : nil)
                                      }),
                ]),
            ]),
            Chrome.group("Timing", fluent, [Chrome.rows([
                Chrome.spinner("Duration", t.duration * 100, fluent, step: 25, unit: "cs", minimum: 10) { v in
                    deck.setTransition(duration: v / 100)
                },
                Chrome.small(FluentSystemIcons.copy, "Apply To All", fluent) { deck.setTransition(all: true) },
            ])]),
        ]
    }

    private func _slideShowTab(_ fluent: FluentThemeData) -> [Widget] {
        [
            Chrome.group("Start Slide Show", fluent, [
                Chrome.big(FluentSystemIcons.desktop, "From Beginning", fluent) { [session] in session.onSlideShow?(false) },
                Chrome.big(FluentSystemIcons.window, "From Current Slide", fluent) { [session] in session.onSlideShow?(true) },
            ]),
        ]
    }

    private func _slidePictureFormat(_ deck: DeckController, _ fluent: FluentThemeData) -> [Widget] {
        let crops: [(String, Double)] = [("Square", 1), ("4:3", 4.0 / 3), ("3:2", 1.5), ("16:9", 16.0 / 9), ("3:4 Portrait", 0.75)]
        return [
            Chrome.group("Adjust", fluent, [
                Chrome.big(FluentSystemIcons.refresh, "Reset Picture", fluent) { deck.resetPictures() },
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
                Chrome.bigToggle(FluentSystemIcons.onePage, "Normal", !session.slidesSorter, fluent) { [session] in
                    session.onSlidesView?(false)
                },
                Chrome.bigToggle(FluentSystemIcons.grid, "Slide Sorter", session.slidesSorter, fluent) { [session] in
                    session.onSlidesView?(true)
                },
            ]),
        ]
    }
}
