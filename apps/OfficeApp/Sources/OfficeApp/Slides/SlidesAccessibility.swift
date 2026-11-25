// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import OfficeText

/// What a screen reader sees of the slide canvas: one node for the slide ("Slide 2 of 5") and, inside it,
/// one node per shape in reading order (the slide's own shape order, back to front, as PowerPoint reads it).
/// A shape is named by its alt text, else its name; its value is its text; a tap on it selects it.
enum SlidesAccessibility {
    static func label(of shape: SlideShape) -> String {
        if let alt = shape.altText, !alt.isEmpty { return alt }
        if !shape.name.isEmpty { return shape.name }
        switch shape.kind {
        case .picture: return "Picture"
        case .table: return "Table"
        case .chart: return "Chart"
        default: return "Shape"
        }
    }

    static func text(of shape: SlideShape) -> String {
        shape.text?.document.plainText() ?? ""
    }

    static func slideLabel(_ deck: DeckController) -> String { "Slide \(deck.current + 1) of \(deck.slides.count)" }

    static func wrap(_ shapeLayer: Widget, shape: SlideShape, deck: DeckController) -> Widget {
        Semantics(label: label(of: shape), value: text(of: shape),
                  selected: deck.selection.contains { $0 === shape },
                  onTap: { deck.selectShapes([shape]) }, child: shapeLayer)
    }

    static func wrap(_ canvas: Widget, deck: DeckController) -> Widget {
        Semantics(label: slideLabel(deck), child: canvas)
    }
}
