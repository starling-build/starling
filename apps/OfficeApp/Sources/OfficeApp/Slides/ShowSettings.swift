// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

/// How the slide show runs: the settings of Set Up Slide Show, kept in the
/// file's `ppt/presProps.xml` (`p:showPr`).
struct ShowSettings: Equatable {
    enum Kind: Equatable { case presenter, window, kiosk }
    enum Range: Equatable {
        case all
        /// Slide numbers, 1-based, both inclusive.
        case slides(from: Int, to: Int)
        /// The id of a `CustomShow`.
        case custom(Int)
    }
    var kind = Kind.presenter
    /// Loop continuously until Esc.
    var loop = false
    var range = Range.all
    /// Advance slides by their timings (Rehearse Timings writes them).
    var useTimings = true
    /// Play narration (kept as the file had it).
    var narration = true
}

/// A named list of slides to play in their own order (`p:custShow`).
struct CustomShow: Equatable {
    var id: Int
    var name: String
    /// Slide ids (`SlideState.id`), in play order. A slide may appear twice.
    var slides: [Int]
}

/// One section of the deck (`p14:section`): a named run of slides. Which slides are in it is each slide's own `section` tag; the order here is the order in the deck.
struct SlideSection: Equatable {
    var guid: String
    var name: String
    /// Folded in the thumbnail rail and Slide Sorter. Not saved with the file.
    var collapsed = false
}
