// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge
import Foundation

/// A deck that exercises the writer's new-deck path: every layout, typed
/// text in every placeholder, drawn shapes with text, a rotated one, a line,
/// a hidden slide and notes. `OfficeApp --deck-sample` and the tests use it.
enum SlidesSample {
    static func make() -> DeckController {
        let deck = DeckController()
        func type(_ shape: SlideShape?, _ text: String) {
            guard let c = shape?.text else { return }
            for (i, line) in text.components(separatedBy: "\n").enumerated() {
                if i > 0 { c.insertParagraphBreak() }
                c.insertText(line)
            }
        }
        let title = deck.currentSlide
        type(title.shapes.first { $0.role == .ctrTitle }, "Quarterly review")
        type(title.shapes.first { $0.role == .subTitle }, "Starling team, October 2026")
        title.notes.insertText("Open with the numbers.")

        let content = deck.addSlide(.titleAndContent)
        type(content.shapes.first { $0.role == .title }, "What shipped")
        type(content.shapes.first { $0.role == .body }, "Writer opens and saves docx\nSlides starts today\nEngine debt paid")

        let section = deck.addSlide(.sectionHeader)
        type(section.shapes.first { $0.role == .title }, "Next quarter")
        type(section.shapes.first { $0.role == .body }, "Plans and risks")

        let two = deck.addSlide(.twoContent)
        type(two.shapes.first { $0.role == .title }, "Two columns")
        let bodies = two.shapes.filter { $0.role == .body }
        type(bodies.first, "Left one\nLeft two")
        type(bodies.last, "Right one")

        let comparison = deck.addSlide(.comparison)
        type(comparison.shapes.first { $0.role == .title }, "Before and after")
        let cbodies = comparison.shapes.filter { $0.role == .body }
        for (i, s) in cbodies.enumerated() { type(s, ["Before", "Slow builds", "After", "Fast builds"][i]) }

        let drawing = deck.addSlide(.titleOnly)
        type(drawing.shapes.first { $0.role == .title }, "Shapes")
        let box = deck.addShape(.roundRect)
        box.frame = Rect.fromLTWH(96, 160, 240, 120)
        type(box, "Rounded")
        let star = deck.addShape(.star5)
        star.frame = Rect.fromLTWH(420, 150, 140, 140)
        star.rotation = 15
        let line = deck.addShape(.line)
        line.frame = Rect.fromLTRB(96, 360, 560, 420)
        let tb = deck.addTextBox(at: Rect.fromLTWH(600, 380, 260, 40))
        type(tb, "A text box")
        drawing.notes.insertText("Point at the star.")

        let blank = deck.addSlide(.blank)
        deck.toggleHidden(deck.slides.firstIndex { $0 === blank }!)
        deck.select(0)
        return deck
    }
}
