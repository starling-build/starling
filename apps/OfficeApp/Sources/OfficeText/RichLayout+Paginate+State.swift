// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// RichLayout, part "Paginate": the state `_paginate` shares between its steps. These were local variables of one
// 5,700-line function with nested functions; they live here so the steps can be methods in their own files
// (a pure move: no behaviour changed).

import Flutter
import FlutterSwiftBridge
import Foundation

struct _PState {
    let start: Int
    let settled: Int
    let pinPass: Bool
    init(start: Int, settled: Int, pinPass: Bool) { self.start = start; self.settled = settled; self.pinPass = pinPass }
    // (A float that wraps, set where its anchor puts it, over content
    // set before that anchor on its page: Word leaves the float there
    // and moves that content out from under it — zh-06c46ba9's
    // "分工表格式" box, anchored under a table row parted onto page 70,
    // stands where the row's foot puts its paragraph, and the row's
    // part stands under the box. Found here, such a float is pinned:
    // the pages are set once more with it in place from its page's
    // top (`_pinnedFloats`).)
    var pinnedAnew: Bool = false
    var pushedAnew: Bool = false
    var bandPushLast: Int = -1
    var bandPushDelta: Double = 0.0
    var bandPushPage: Int = -1
    var bandPushTop: Double = 0.0
    var contentH: Double = 1.0
    var page: Int = 0
    var y: Double = 0.0
    // Paragraphs set again under a page-placed table they would reach
    // into (see where a table's first row is placed), and its table.
    var deferredUnder: [PagePiece] = []
    // A floating table anchored to the text after it: where it began,
    // for that paragraph (see below).
    var textFloatTop: (table: String, page: Int, y: Double, down: Double, chained: Bool)? = nil
    // Where the table a paragraph may stand beside, at the right margin, ends on its page: the lines
    // that follow the anchor go on past the room above the table while they stand level with it.
    var besideChainEnd: Double? = nil
    // The paragraph set over a floating table's offset that does not fit
    // in what is left of it: its lines that do stand above the table (to
    // `limit`, on the page), the rest where the flow went on (`back`).
    var floatHold: (limit: Double, back: Double)? = nil
    // The text place the last text-anchored floating table hung from.
    var floatRunBase: (table: String, page: Int, y: Double)? = nil
    // A table held at its `_floatPin` above where the text before it now ends: that end.
    var pinnedFrom: (table: String, page: Int, y: Double)? = nil
    // (A floating table kept with its anchor whose offset takes it past
    // the margin: its first row stands there.)
    var keptPastFoot: String? = nil
    // The last empty paragraph the compat 14 carry rule looked at: where it began, and on which page.
    var lastEmptyAt: (i: Int, page: Int, y: Double)? = nil
    var bottomTablePage: (table: String, page: Int)? = nil
    var deferredTable: String? = nil
    // A table placed against the page further down than the text has
    // come: where the text stood, to go on from there round it.
    var tableReturn: (table: String, y: Double, page: Int, top: Double)? = nil
    // The room left over a page-anchored table on its first page, when the table ran on to
    // later pages: the empty paragraphs after it take it, as Word flows them from where the
    // table's anchor stood (they are blank, so only their room counts).
    var roomOverTable: Double? = nil
    var roomOverTableName: String? = nil
    var besideEmpties: (top: Double, sum: Double)? = nil
    // (A table placed against the page that was set up to the page's edge: its table and the edge, in pixels.)
    var pageEdgeClamp: (table: String, edge: Double)? = nil
    var tableBands: [(top: Double, bottom: Double, owner: Int)] = []
    var topPinnedOwners: Set<Int> = Set<Int>()  // owners whose own picture sits at offset 0 from the paragraph, no space above it
    var pictureBands: [(top: Double, bottom: Double, owner: Int)] = []
    // (Tops of the bands of page-anchored tables with a strip free to their right: empty paragraphs stand beside them.)
    var stripBandTops: Set<Double> = Set<Double>()
    var narrowBands: [(top: Double, bottom: Double, owner: Int, left: Double, right: Double)] = []
    // A page whose columns were balanced at a continuous section break:
    // its physical page and where the next section's columns start.
    var columnFloor: (physical: Int, y: Double)? = nil
    var besideTable: (bottom: Double, page: Int)? = nil
    // (Set with the bottom of a table whose anchor paragraph stands above it: the empty paragraphs after it go under the table too.)
    var anchorAboveBottom: Double? = nil
    var reordered: Bool = false
    var i: Int = 0
    // A page is as tall as its section's content: the section of the
    // paragraph that opens it.
    var pageFresh: Bool = true   // no paragraph has been set on this page yet, not even an empty one
    // Where the flow stood before a frame placed on the page (see
    // below), and the page it is on.
    var frameReturn: (y: Double, page: Int)? = nil
    // (Where a frame text does not go beside ends on its page: the flow goes on from there.)
    var frameFoot: (y: Double, page: Int, top: Double)? = nil
    var resumeCursor: Double? = nil
    // The previous result, to splice back in once the flow past the
    // change lands where it did before.
    var oldPieces: [PagePiece] = []
    var oldPages: [[PagePiece]] = []
    var oldStart: [Int] = []
    var restarted: Bool = false
    var oldNotes: [Int: [Int]] = [:]
    var oldCuts: [Int: (id: Int, keep: Double)] = [:]
    var oldCarries: [Int: (id: Int, from: Double)] = [:]
    // (The pins of the pages set again are found again; those of the
    // pages kept stand, and so do their floats' shifts.)
    var shelvedPins: [String: (pin: (page: Int, top: Double, bottom: Double, left: Double, right: Double, anchorY: Double), shift: Double?)] = [:]
    var prevContentH: Double = 0
    var prevY: Double = 0.0   // how far down the page before was filled
    var prevPartBottom: Double? = nil   // where the part of a row that parted there ends, when a cell runs on below it
    // The floating pictures on this page that text wraps round: page
    // y, and x from the column's edge.
    var bands: [(top: Double, bottom: Double, left: Double, right: Double)] = []
    // Pictures placed from the margin or the page at a fixed height, wrapped square and leaving no room at either side:
    // the paragraphs after their anchor keep clear of them (the anchor's own is sent under by the rule below).
    var fixedBands: [(top: Double, bottom: Double, left: Double, right: Double)] = []
    var tightBandBottoms: [Double] = []   // feet of the wrapTight/Through boxes' bands
    // The pinned floats' bands on this page (in `bands` too), which a
    // table's rows keep clear of as well.
    var pinBands: [(top: Double, bottom: Double, left: Double, right: Double)] = []
    // The paragraphs of nothing but floating pictures set on this
    // page since the last with text (`_anchorsOnly`).
    var anchorRun: [Int] = []
    // A paragraph of no height that ends a section stands on its page:
    // the page is not empty (see the section rule in the loop).
    var markOnPage: Bool = false
    // A line on this page hangs past its foot (by its grid's overhang).
    var overfull: Bool = false
    // Where the flow stands past the foot by an off-grid multiple's
    // extra alone, as by space after: not over-full (see below).
    var spacedPast: Double? = nil
    // Footnotes at this page's foot, whose room the page's text gives
    // up (Word's, under its rules): the notes of the paragraph or row
    // being set (`placing`, of paragraphs `placingRange`) go on with
    // it to the next page where none of it stays on this one.
    // (A page of columns of one section sets its notes as it sets its
    // text, each under the column its mark stands in: the column's own
    // room, a note too long for it parted on to the same column of the
    // next page. Word's labs fn-cols-long2 and -short.)
    var slotNotes: Bool = false
    var notesOn: Bool = false
    var pageNotes: [Int] = []
    var placing: [Int] = []
    var placingRange: Range<Int> = 0 ..< 0
    // The notes of paragraphs that keep with the next, whose room
    // Word reserves only when the first paragraph after them that
    // does not keep is set (labs `fn44`, `fn44k`, `fn44k2`, `fn44k3`
    // from bug65649's package, Word 16, 2026-10-15: with its filler
    // unkept both notes stand at the page's foot and the 4-line
    // paragraph that no longer fits goes over; with every paragraph
    // kept the page fills with text and both notes go to the next
    // page's foot; with the chain ending at the paragraph, that one
    // is set and the notes take what is left — the first parted
    // over the pages, the second whole on the next). A note that
    // does not fit what is left goes to the next page, and those
    // after it with it (bug65649's page 3: the whole file keeps,
    // and footnote 2 stands at page 4's foot under 3.7 whole and
    // 3.8's first line; ours had sent 3.7 over). Parting a note
    // over two pages is not done: it goes over whole.
    var pendingNotes: [Int] = []
    // (The notes of a table row whose marks stand in a part of it a
    // later page holds: reserved on that page as `splitRow` sets the
    // part — see where a row's notes are placed.)
    var rowPending: [Int] = []
    // (The note this page parts, set at its foot to `keep`.)
    var pageCut: (id: Int, keep: Double)? = nil
    // (Where a column ends at the line marking the note it parts.)
    var cutEnds: Double? = nil
    var omittedHeadHeight: [String: Double] = [:]
    // A table row too tall for what is left of the page parts over
    // the page's foot, as Word parts it (prints of 2026-10-13): where
    // one line at least of one of its cells fits — no widow or orphan
    // is kept in a cell — each cell is cut under its own last line
    // that fits, and each goes on from the top of the next page.
    // Not a row Word may not split (`w:cantSplit`), a repeated
    // header row, or one with merged or turned cells.
    // Where a cell's paragraph may part at a page's foot: under any
    // of its lines, as Word parts it before its 2013 layout, which
    // keeps no widow or orphan in a table; from that layout on a
    // paragraph with widow control (Word's default) parts only with
    // two lines on each side — a row with room for one line of each
    // cell goes to the next page whole (prints of 2026-10-13, modes
    // 14 and 15).
    // The rule under a row is the next row's, and wants its room on
    // the row's page all the same: a row fits a page with the line
    // below it, and a row parted at the foot is closed there with
    // one. (Prints of 2026-10-13: a line with 0.45pt under it at
    // the foot goes over where the rules are half a point, with
    // 1.05 where they are a point and a half, and stays with 0.1
    // where there are none.) The table's last row has its own.
    // The line under each row of a table, from the cells that end
    // there: what `ruleUnder` asks for a row whose first cell is
    // merged on down past it.
    var linesUnderRows: [String: [Int: Double]] = [:]
    var wentOver: Bool = false   // `splitRow` moved its row to a new page and left it to the caller
}
