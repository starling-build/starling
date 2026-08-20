// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0
//
// The decision layer under a permission overlay — milestone 5 of
// docs/plans/ipad-ui.md.
//
// `GridRegions` says what shapes are on screen. This says which of them a UI
// is allowed to put a button on, and exactly what a tap must send. It renders
// nothing and lives in the sdk on purpose: the rule for "may I act on this?"
// must not differ between a phone, a tablet and a desktop window, and the same
// overlay is worth having on all three. Only the drawing is per-platform.
//
// Two rules do all the work here, and both are refusals:
//
//   1. Exactly one choice on screen, or none is offered. A grid with two
//      option lists is a grid we have misread — answering the wrong one is
//      indistinguishable from answering the right one until it is too late.
//   2. The key sent is the digit the program drew, and nothing else. Not a
//      guess from the label, not "the one that says Yes", not an index. If a
//      future prompt puts No first, an overlay that reasoned about meaning
//      would confidently approve it.
//
// What a tap sends was measured, not assumed: a session was driven to a real
// `rm` permission prompt, the byte `1` was written to the pty with no Return
// after it, and the file was gone afterwards. The footer's "Enter to confirm"
// describes the arrow-key path; the digit is accepted on its own.

import Foundation

/// One choice on screen that a UI may act on.
public struct PromptChoice: Equatable, Sendable {
    public let options: [GridOption]
    /// Index into `options` that the program itself is pointing at.
    public let selected: Int
    /// Inclusive grid rows the choice occupies, so a UI can place itself over
    /// the region rather than guessing.
    public let firstRow: Int
    public let lastRow: Int

    public init(options: [GridOption], selected: Int, firstRow: Int, lastRow: Int) {
        self.options = options
        self.selected = selected
        self.firstRow = firstRow
        self.lastRow = lastRow
    }

    /// What to write to the session to pick `option`.
    ///
    /// The literal key, as drawn. This is deliberately not a method on the UI:
    /// there is exactly one place that decides what a tap sends, and it is
    /// here, next to the rule that says why.
    public func keystroke(for option: GridOption) -> String {
        String(option.key)
    }
}

public enum PromptDetector {

    /// The one choice a UI may act on, or nil.
    ///
    /// Nil covers three cases that must stay indistinguishable to the caller,
    /// because all three mean the same thing — *do not draw a button*:
    /// nothing matched, more than one thing matched, or what matched was too
    /// small to be a question. A caller that could tell them apart would
    /// eventually be tempted to treat one as recoverable.
    public static func actionable(_ grid: [[TermCell]]) -> PromptChoice? {
        let lists = GridRegions.detect(grid).compactMap { region -> PromptChoice? in
            guard case .optionList(let selected, let options) = region.kind
            else { return nil }
            return PromptChoice(options: options, selected: selected,
                                firstRow: region.firstRow, lastRow: region.lastRow)
        }
        guard lists.count == 1, let only = lists.first else { return nil }
        // A choice whose selection is out of range is a parse we do not
        // understand well enough to act on, whatever the row count says.
        guard only.selected >= 0, only.selected < only.options.count else { return nil }
        return only
    }
}
