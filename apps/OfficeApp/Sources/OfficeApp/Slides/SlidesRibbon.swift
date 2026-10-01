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
        return [clipboardGroup(fluent), _slidesGroup(deck, fluent), fp[0], fp[1], editing]
    }

    private func _slidesInsert(_ deck: DeckController, _ fluent: FluentThemeData) -> [Widget] {
        [
            _slidesGroup(deck, fluent),
            Chrome.group("Text", fluent, [
                Chrome.big(FluentSystemIcons.textT, "Text Box", fluent) { [session] in session.onInsertTextBox?() },
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
