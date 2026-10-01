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

    private func _design(_ deck: DeckController, _ fluent: FluentThemeData) -> [Widget] {
        let wide = abs(deck.slideSize.width / deck.slideSize.height - 16.0 / 9.0) < 0.01
        return [
            Chrome.group("Themes", fluent, [
                Chrome.bigToggle(FluentSystemIcons.personalize, deck.theme.name, true, fluent) {},
            ]),
            Chrome.group("Customize", fluent, [
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
        [
            Chrome.group("Transition to This Slide", fluent, [
                Chrome.bigToggle(FluentSystemIcons.onePage, "None", true, fluent) {},
            ]),
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

    private func _slidesView(_ fluent: FluentThemeData) -> [Widget] {
        [
            Chrome.group("Presentation Views", fluent, [
                Chrome.bigToggle(FluentSystemIcons.onePage, "Normal", true, fluent) {},
            ]),
        ]
    }
}
