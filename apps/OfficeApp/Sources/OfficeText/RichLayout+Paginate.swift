// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// RichLayout, part "Paginate": moved out of RichLayout.swift by test/tools/split-richlayout.py (a pure move, so that
// the parts compile side by side).

import Flutter
import FlutterSwiftBridge
import Foundation

extension RichLayout {

    /// Cut the flow into pages. A paragraph that straddles a page boundary
    /// is split between lines (its painter is painted twice, clipped), so
    /// the breakable positions inside a block are the bottoms of its lines.
    func _paginate(_ document: RichDocument, from start: Int = 0, settled: Int = Int.max, pinPass: Bool = false) {
        var pgs = _PState(start: start, settled: settled, pinPass: pinPass)
        _lineDropSeen.removeAll()
        // (A float that wraps, set where its anchor puts it, over content
        // set before that anchor on its page: Word leaves the float there
        // and moves that content out from under it — zh-06c46ba9's
        // "分工表格式" box, anchored under a table row parted onto page 70,
        // stands where the row's foot puts its paragraph, and the row's
        // part stands under the box. Found here, such a float is pinned:
        // the pages are set once more with it in place from its page's
        // top (`_pinnedFloats`).)
        if !pgs.pinPass { _columnPushed = _columnPushed.filter { $0 < pgs.start } }
        defer {
            if theme.wordRules, !pgs.pinPass, pgs.pinnedAnew || pgs.pushedAnew { _paginate(document, from: pgs.start, settled: pgs.settled, pinPass: true) }
        }
        // Paragraphs set again under a page-placed table they would reach
        // into (see where a table's first row is placed), and its table.
        // A floating table anchored to the text after it: where it began,
        // for that paragraph (see below).
        // Where the table a paragraph may stand beside, at the right margin, ends on its page: the lines
        // that follow the anchor go on past the room above the table while they stand level with it.
        // The paragraph set over a floating table's offset that does not fit
        // in what is left of it: its lines that do stand above the table (to
        // `limit`, on the page), the rest where the flow went on (`back`).
        // The text place the last text-anchored floating table hung from.
        // A table held at its `_floatPin` above where the text before it now ends: that end.
        // (A floating table kept with its anchor whose offset takes it past
        // the margin: its first row stands there.)
        // The last empty paragraph the compat 14 carry rule looked at: where it began, and on which page.
        // A table placed against the page further down than the text has
        // come: where the text stood, to go on from there round it.
        // The room left over a page-anchored table on its first page, when the table ran on to
        // later pages: the empty paragraphs after it take it, as Word flows them from where the
        // table's anchor stood (they are blank, so only their room counts).
        // (A table placed against the page that was set up to the page's edge: its table and the edge, in pixels.)
        // (Tops of the bands of page-anchored tables with a strip free to their right: empty paragraphs stand beside them.)
        // A page whose columns were balanced at a continuous section break:
        // its physical page and where the next section's columns start.
        // (Set with the bottom of a table whose anchor paragraph stands above it: the empty paragraphs after it go under the table too.)
        // A page is as tall as its section's content: the section of the
        // paragraph that opens it.
        // Where the flow stood before a frame placed on the page (see
        // below), and the page it is on.
        // (Where a frame text does not go beside ends on its page: the flow goes on from there.)
        // The previous result, to splice back in once the flow past the
        // change lands where it did before.
        pgs.oldPieces = _allPieces
        pgs.oldPages = _pages
        pgs.oldStart = _pieceStart
        // Restart on the page where the first changed paragraph begins,
        // from that page's first piece; the pages before it are kept.
        if pgs.start > 0, pgs.start < count, _pieceStart.count == count + 1, _pieceStart[pgs.start] < _allPieces.count,
           case let p0 = _allPieces[_pieceStart[pgs.start]].page,
           // (Columns flowed by the paginator restart on their physical page's first column: the floor
           // a section's columns start at, and the balanced blocks, belong to the page, not to the column.)
           case let p = RichTextTheme.sectionColumnsFlow && _columns > 1 ? p0 - p0 % _columns : p0, p > 0, p < _pages.count,
           let first = _pages[p].first(where: { !$0.repeated }), first.part == .all {
            pgs.page = p
            pgs.i = first.paragraph
            pgs.resumeCursor = first.flowTop
            pgs.restarted = true
            _pages.removeSubrange(p...)
            _pages.append([])
            _pages[p].reserveCapacity(32)
            if let k = _allPieces.firstIndex(where: { $0.paragraph == pgs.i && $0.flowTop >= first.flowTop - 0.01 }) {
                _allPieces.removeSubrange(k...)
            } else {
                _allPieces.removeAll(keepingCapacity: true)
            }
        } else {
            _pages = [[]]
            _pages[0].reserveCapacity(32)
            _allPieces.removeAll(keepingCapacity: true)
        }
        pgs.oldNotes = _pageNotes
        _pageNotes = _pageNotes.filter { $0.key < pgs.page }
        pgs.oldCuts = _noteCutOut
        pgs.oldCarries = _noteCarryIn
        _noteCutOut = _noteCutOut.filter { $0.key < pgs.page }
        _noteCarryIn = _noteCarryIn.filter { $0.key < pgs.page }
        // (The pins of the pages set again are found again; those of the
        // pages kept stand, and so do their floats' shifts.)
        if !pgs.pinPass {
            for (id, pin) in _pinnedFloats where pin.page >= pgs.page {
                pgs.shelvedPins[id] = (pin, _floatShiftY[id])
                _floatShiftY[id] = nil
                _pinnedFloats[id] = nil
            }
        }
        pgs.prevContentH = pgs.contentH
        // The floating pictures on this page that text wraps round: page
        // y, and x from the column's edge.
        // Pictures placed from the margin or the page at a fixed height, wrapped square and leaving no room at either side:
        // the paragraphs after their anchor keep clear of them (the anchor's own is sent under by the rule below).
        // The pinned floats' bands on this page (in `bands` too), which a
        // table's rows keep clear of as well.
        // The paragraphs of nothing but floating pictures set on this
        // page since the last with text (`_anchorsOnly`).
        // A paragraph of no height that ends a section stands on its page:
        // the page is not empty (see the section rule in the loop).
        // A line on this page hangs past its foot (by its grid's overhang).
        // Where the flow stands past the foot by an off-grid multiple's
        // extra alone, as by space after: not over-full (see below).
        // Footnotes at this page's foot, whose room the page's text gives
        // up (Word's, under its rules): the notes of the paragraph or row
        // being set (`placing`, of paragraphs `placingRange`) go on with
        // it to the next page where none of it stays on this one.
        // (A page of columns of one section sets its notes as it sets its
        // text, each under the column its mark stands in: the column's own
        // room, a note too long for it parted on to the same column of the
        // next page. Word's labs fn-cols-long2 and -short.)
        pgs.slotNotes = theme.wordRules && RichTextTheme.wordWindowsPages && _columns > 1 && !_perSection && !document.footnotes.isEmpty
        _slotNotes = pgs.slotNotes
        pgs.notesOn = theme.wordRules && !document.footnotes.isEmpty && (_columns == 1 || pgs.slotNotes)
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
        // (The notes of a table row whose marks stand in a part of it a
        // later page holds: reserved on that page as `splitRow` sets the
        // part — see where a row's notes are placed.)
        // (The note this page parts, set at its foot to `keep`.)
        // (Where a column ends at the line marking the note it parts.)
        _pg_loadPins(&pgs, document)
        _blankPages = _blankPages.filter { $0 < pgs.page / _columns }
        _numberedBlankPages = _numberedBlankPages.filter { $0 < pgs.page / _columns }
        if pgs.restarted {
            // (The page restarted on keeps its section.)
            let insets = _bodyInsets(page: pgs.page / _columns, document)
            pgs.contentH = max(1, _px(pageSetup(forPage: pgs.page / _columns).height) - insets.top - insets.bottom - (_columns > 1 ? _columnNoteReserve[pgs.page] ?? 0 : 0))
        } else {
            _pageSection.removeAll(keepingCapacity: true)
            _pageHeaderSection = [:]
            _pg_openPage(&pgs, document)
            _pg_addHeaderBand(&pgs, document)
        }
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
        while pgs.i < count {
            var sectionBreakHandled = false
            // An odd/even section may begin with a table, so enforce its
            // side before either the table-row or paragraph path. Word's
            // zh-291fcea7 leaves page 8 completely blank before its form.
            // A stated numbering restart instead rounds that first number
            // up to the requested side; it does not itself add a page.
            if theme.wordRules, pgs.resumeCursor == nil, pgs.i > 0, pgs.i < _sectionOf.count,
               _sectionOf[pgs.i] != _sectionOf[pgs.i - 1],
               let parity = _setup(ofParagraph: pgs.i).sectionStartParity {
                if pgs.y > 0.01 || !_pages[pgs.page].isEmpty || pgs.markOnPage { _pg_newPage(&pgs, document) }
                while pgs.page % _columns != 0 { _pg_newPage(&pgs, document) }
                if document.paragraphs[pgs.i].style.pageBreakTwice { _pg_newPage(&pgs, document) }
                let physical = pgs.page / _columns
                if physical > 0, _sectionNumberStart(_sectionOf[pgs.i], document) == nil,
                   (_pageNumberOf(physical - 1, document) + 1) % 2 != parity.rawValue {
                    _blankPages.insert(physical)
                    _numberedBlankPages.insert(physical)
                    repeat { _pg_newPage(&pgs, document) } while pgs.page % _columns != 0
                }
                // A page-anchored table can move y down before the row's
                // break check. That offset is not content before this
                // section: its already-handled break must not fire again.
                sectionBreakHandled = true
            }
            // (Under the table they were moved below, once it has ended.)
            if !pgs.deferredUnder.isEmpty, _cells[pgs.i]?.table != pgs.deferredTable { _pg_placeDeferred(&pgs, document) }
            // (After a table placed further down the page, the text goes on
            // from where it stood, the table a band it keeps clear of:
            // zh-10eab555's issuing line, a table 702.9pt down page 2, has
            // the contents' title and lines over it in Word's print, down
            // to 677; ours set them under it, on page 3.)
            if let back = pgs.tableReturn, _cells[pgs.i]?.table != back.table {
                pgs.tableReturn = nil
                if back.page != pgs.page, theme.wordRules, RichTextTheme.wordWindowsPages, back.top - back.y > 0.01,
                   document.tableStyles[back.table]?.pageOffsetY != nil {
                    pgs.roomOverTable = back.top - back.y
                    pgs.roomOverTableName = back.table
                }
                if back.page == pgs.page, pgs.y > back.top {
                    // (No band for a table wholly outside the text's width — in
                    // the margin beside it: tdf92157's address block, 467.9pt
                    // from the page's edge against a text area ending at 454.4,
                    // leaves the letter's table at its place in Word's print.)
                    let left = _tableLeft(back.table, document)
                    let beside = theme.wordRules && (left >= (_tableFlowWidth[back.table] ?? width) - 0.01
                        || left + (_columnWidths[back.table] ?? []).reduce(0, +) <= 0.01)
                    if !beside {
                        pgs.tableBands.append((top: back.top, bottom: pgs.y, owner: -1))
                        if RichTextTheme.wordWindowsPages, document.tableStyles[back.table]?.pageAnchored == true,
                           _tableLeftRoom(back.table, document) >= _px(18) || (_tableFlowWidth[back.table] ?? width) - (left + (_columnWidths[back.table] ?? []).reduce(0, +)) >= _px(12) {
                            // (A strip at the table's right, or the room at its left: blank lines stand beside it, dx2 f22ada3a's
                            // date table at x 417 with eight blanks at the left margin.)
                            pgs.stripBandTops.insert(back.top)
                        }
                    }
                    pgs.y = back.y
                }
            }
            // (Empty paragraphs after a floating table go down the room
            // beside it, from the top of its part on the page: zh-38758b14's
            // scoring table, tblpX 3756 twips on a landscape page and three
            // pages long, has the fourteen empty paragraphs after it in the
            // 100pt to its left on its last page in Word's print, and
            // "附件2：" at the next page's top; ours set them under it, a
            // page of their own. Text keeps under it. So do paragraphs of
            // spaces alone, and a table centred on the page with 22pt to
            // its left: zh-6e6b9821 p2 has the "    " and the five empty
            // paragraphs after its centred 354pt table in that room, and
            // "16." under the table on the same page; ours set them under
            // it, and "16." went over.)
            // (A paragraph of one anchored picture has no line of its own to keep under the
            // table: it is as blank as an empty one. LibreOffice's tdf164500, the logo's
            // paragraph after the table, stands beside it in Word's print.)
            func blank(_ p: RichParagraph) -> Bool {
                guard let image = p.image else { return !p.text.contains { $0 != " " } }
                return RichTextTheme.wordWindowsPages && !p.text.contains { $0 != " " && $0 != "\u{FFFC}" }
                    && image.sourceXML?.containsSubstring("<wp:anchor") == true
            }
            if let beside = pgs.besideTable {
                let p = document.paragraphs[pgs.i]
                if beside.page != pgs.page || pgs.y >= beside.bottom - 0.01 { pgs.besideTable = nil }
                else if let c = _cells[pgs.i], pgs.i > 0, _cells[pgs.i - 1] == nil, blank(document.paragraphs[pgs.i - 1]), let ts = document.tableStyles[c.table], ts.floatsOverText, ts.floatRaiseY != nil || ts.floatOffsetY != nil, ts.keptPosition != nil, theme.wordRules, RichTextTheme.wordWindowsPages, ts.keptPosition?.containsSubstring("tblOverlap w:val=\"never\"") != true {
                    // (A floating table whose anchor stood beside the one above is set from there: lo-e998b55c.)
                    RuleTrace.hit("floating-table-set-from-an-anchor-beside-the-float-above")
                    pgs.besideTable = nil
                }
                else if (_cells[pgs.i] != nil && !(_cells[pgs.i].map { _narrowBesideFloat($0.table, document) } ?? false)) || (_cells[pgs.i] == nil && !((blank(p) && pgs.anchorAboveBottom != beside.bottom) || (pgs.i < _besideLead.count && _besideLead[pgs.i] > 0))) { pgs.y = beside.bottom; pgs.besideTable = nil }
            }
            // (A table floating in the left margin, wholly outside the text's width, takes no room of
            // the text's: the paragraph after it stands at its top, beside it. Word for Windows' print of
            // LibreOffice's floattable-anchorpos: "D" at 290 beside "C"'s table, 76pt wide and 98pt left of
            // the text; ours set it under the table, at 413.)
            if theme.wordRules, RichTextTheme.wordWindowsPages, pgs.besideTable == nil, pgs.i > 0, _cells[pgs.i] == nil, !blank(document.paragraphs[pgs.i]),
               _cells[pgs.i - 1] != nil {
                // (Over the tables just before it — a page-anchored one between does not stand in the way.)
                var seen: Set<String> = []
                var j = pgs.i - 1
                while j >= 0, let d = _cells[j] { seen.insert(d.table); j -= 1 }
                for prev in seen {
                    guard let ts = document.tableStyles[prev], ts.floatsOverText, !ts.pageAnchored, ts.keptPosition != nil,
                          _tableLeft(prev, document) + (_columnWidths[prev] ?? []).reduce(0, +) <= 0.01,
                          let top = _pages[pgs.page].filter({ _cells[$0.paragraph]?.table == prev }).map(\.pageY).min(), top < pgs.y - 0.01 else { continue }
                    pgs.y = top
                    break
                }
            }
            // (An ordinary table straight after a floating one that keeps text off (tblOverlap never), fitting in the
            // room at its right, starts level with it and stands beside it — `_besideWideFloatShift` sets it across:
            // Word's print of LibreOffice's lo-ce0d5e6d, two 387pt tables side by side on one page, ours one under the
            // other and over onto a second.)
            if theme.wordRules, RichTextTheme.wordWindowsPages, pgs.besideTable == nil, pgs.i > 0, let c = _cells[pgs.i], let prev = _cells[pgs.i - 1]?.table,
               prev != c.table, _tableFirstParagraph[c.table] == pgs.i, _besideWideFloatShift(c.table, document) != nil,
               let top = _pages[pgs.page].filter({ _cells[$0.paragraph]?.table == prev && !$0.repeated }).map(\.pageY).min(), top < pgs.y - 0.01 {
                RuleTrace.hit("word-table-after-a-float-stands-beside-it-where-it-fits")
                pgs.besideTable = (pgs.y, pgs.page)
                pgs.y = top
            }
            // (The paragraph after a floating table that hangs from the text is the table's anchor: the table
            // stands its offset below that paragraph's top. Where the table is as wide as the text, the anchor
            // keeps its own place above it, its text level with the table's anchor line, and what follows goes under the table. sa1 764f4d8e: "TERMO DE
            // DESISTÊNCIA" at 121.4 in Word's print, its form table tblpY 694 twips under it; ours set it under
            // the table, at 695.)
            if theme.wordRules, RichTextTheme.wordWindowsPages, pgs.besideTable == nil, pgs.resumeCursor == nil, pgs.i > 0, pgs.i < _heights.count,
               _cells[pgs.i] == nil, !blank(document.paragraphs[pgs.i]), !_pageBreak[pgs.i],
               let prev = _cells[pgs.i - 1]?.table, _floatLeavesNoStrip(prev, pgs.i, document),
               let ts = document.tableStyles[prev], ts.floatsOverText, !ts.pageAnchored, let down = ts.floatOffsetY, down > 0,
               let fb = pgs.floatRunBase, fb.table == prev, fb.page == pgs.page, fb.y < pgs.y - 0.01,
               // (The paragraph, from its first line's top to the end of its space after, has to fit in the offset,
               // else the table pushes it under the table: Word prints, lab764.)
               _heights[pgs.i] - (pgs.i < _spaceBefore.count ? _spaceBefore[pgs.i] : 0) <= _px(down) + 0.01 {
                RuleTrace.hit("word-anchor-paragraph-of-a-full-width-floating-table-keeps-its-place-above-it")
                pgs.besideTable = (pgs.y, pgs.page)
                pgs.anchorAboveBottom = pgs.y
                pgs.y = fb.y - (pgs.i < _spaceBefore.count ? _spaceBefore[pgs.i] : 0)
            }
            // (A table as wide as the text leaves no strip: what follows goes under
            // it, not up at its anchor — 6e6d8e9e's blank lines after its sections.)
            if theme.wordRules, pgs.besideTable == nil, pgs.i > 0, _cells[pgs.i] == nil, let prev = _cells[pgs.i - 1]?.table,
               !((_floatLeavesNoStrip(prev, pgs.i, document) && _floatFollowsFloat(prev, document)) || _floatStripNarrowerThanIndent(prev, pgs.i, document) || _floatWiderThanFlow(prev, pgs.i, document)),
               blank(document.paragraphs[pgs.i]) || (pgs.i < _besideLead.count && _besideLead[pgs.i] > 0) || _splitMarginFloatBeside(prev, pgs.i, pgs.page, document) || _splitPageFloatBeside(prev, pgs.i, pgs.page, document),
               let ts = document.tableStyles[prev], ts.floatOffsetY != nil || (ts.floatRaiseY != nil && _markBesideOffsetFloat(prev, pgs.i, document)) || (pgs.i < _besideLead.count && _besideLead[pgs.i] > 0) || _anchorBesideLeftTable(prev, pgs.i, document) || _splitMarginFloatBeside(prev, pgs.i, pgs.page, document) || _splitPageFloatBeside(prev, pgs.i, pgs.page, document), !ts.pageAnchored || _splitPageFloatBeside(prev, pgs.i, pgs.page, document), ts.keptPosition != nil,
               (pgs.i < _besideLead.count && _besideLead[pgs.i] > 0) || _splitMarginFloatBeside(prev, pgs.i, pgs.page, document) || _splitPageFloatBeside(prev, pgs.i, pgs.page, document) || _tableLeft(prev, document) - _px(9) - _px(_setup(ofParagraph: pgs.i).headerWrapLeft) >= _px(18) || _stripBesideLeftTable(prev, pgs.i, document) || _anchorBesideLeftTable(prev, pgs.i, document) || _markBesideOffsetFloat(prev, pgs.i, document),
               case let firstPage = _beside_firstPage(of: prev, upTo: pgs.page, text: pgs.i < _besideLead.count && _besideLead[pgs.i] > 0 && !blank(document.paragraphs[pgs.i])),
               // (… but only where the text does not fit whole beside those rows and goes on
               // over the page: a line or a few that fit stand on the table's last page, as in
               // Word's print of LibreOffice's lo-9cc5d6ef "AB" and lo-eba386b0.)
               case let startPage = firstPage == pgs.page - 1 && pgs.i < _heights.count
                   && ((_pages[firstPage].contains(where: { _cells[$0.paragraph] == nil })
                       && _heights[pgs.i] > pgs.contentH - (_pages[firstPage].filter({ _cells[$0.paragraph]?.table == prev && !$0.repeated }).map(\.pageY).min() ?? 0) + 0.01)
                       // (Nor where the table has nothing on this page: its last row ended past the first
                       // page's foot and the page opened after it is empty of it. lo-853c06a0, two 91pt rows
                       // on a 166pt page: "Anchor paragraph." stands beside A1 on page 1 in Word's print.)
                       || (theme.wordRules && RichTextTheme.wordWindowsPages && !_pages[pgs.page].contains(where: { _cells[$0.paragraph]?.table == prev }))) ? firstPage : pgs.page,
               let top = _pages[startPage].filter({ _cells[$0.paragraph]?.table == prev && (startPage == pgs.page || !$0.repeated) }).map(\.pageY).min(), top < pgs.y - 0.01 || startPage < pgs.page {
                // (Text beside a table whose rows run over two pages starts on
                // the page of its FIRST rows, level with the table's top: Word's
                // print of LibreOffice's floattable-wrap-on-all-pages. It goes on
                // from there to the next page, beside the rest of the table.)
                if startPage < pgs.page { RuleTrace.hit("text-beside-a-split-floating-table-starts-on-its-first-page") }
                pgs.besideTable = (pgs.y, pgs.page)
                pgs.page = startPage
                pgs.y = top
                // (Beside the rest of a page-anchored table that ran over: from the page's top, as in Word's print
                // of f42177d2, not level with the table's top.)
                if startPage == pgs.page, _splitPageFloatBeside(prev, pgs.i, pgs.page, document) { RuleTrace.hit("f42177d2-text-beside-a-split-page-anchored-table-starts-at-the-page-top"); pgs.y = 0 }
                // From the line the table hangs from, where its first row
                // is on this page: its tblpY stands it lower than that,
                // and Word's first empty line beside zh-6e6b9821's table
                // is that 8pt above the table's top.
                var first = pgs.i - 1
                while first > 0, _cells[first - 1]?.table == prev { first -= 1 }
                if _pages[pgs.page].contains(where: { $0.paragraph == first }), let down = ts.floatOffsetY {
                    pgs.y = max(_pages[pgs.page].map(\.pageY).min() ?? 0, top - _px(down))
                }
                // (A line the table hangs from, after a paragraph framed against the page whose top stands
                // inside the first line's place and whose foot is over the table's top, stands 4.9pt under
                // the frame's top, not at the margin: Word for Windows' labs b88 (lo-88b29958), the text
                // paragraph's baseline 176.7 / 187.0 / 196.7 for frames at 75 / 85.25 / 95pt, and none for
                // a frame above the margin (50), or one reaching the table (107.5).)
                if theme.wordRules, RichTextTheme.wordWindowsPages, first > 0, _cells[first - 1] == nil, first - 1 < _heights.count,
                   case let fp = document.paragraphs[first - 1], fp.cell == nil, let frame = fp.style.frame,
                   frame.verticalAnchor == "page", frame.horizontalAnchor == "page", frame.verticalAlign == nil,
                   _pages[pgs.page].contains(where: { $0.paragraph == first }) {
                    let marginTop = _pxMarginTop(pgs.page)
                    let frameTop = _px(frame.y) - marginTop
                    if frameTop >= -0.01, frameTop < _heights[first] - 0.01 || frameTop < _px(47), frameTop + _heights[first - 1] <= top + 0.01 {
                        RuleTrace.hit("word-line-after-a-page-framed-paragraph-stands-under-the-frames-top")
                        pgs.y = max(pgs.y, frameTop + _px(4.9 + 5.35))
                    }
                }
                // (An anchor beside a float that is raised stands one line under the
                // line that float hangs from: its own table is 12.9pt under the
                // first's top in Word's print of lo-e998b55c, not level with it.)
                if ts.floatOffsetY == nil, first > 0, first - 1 < _heights.count, _anchorBesideLeftTable(prev, pgs.i, document) {
                    pgs.y = top + _px(ts.floatRaiseY ?? 0) + _heights[first - 1]
                }
                // (A table held above where the text before it ends: what follows goes on from
                // that end, beside the table still. lo-f48e444e's second paragraph at 170.2,
                // under the first's four lines, in Word's print.)
                if let pf = pgs.pinnedFrom, pf.table == prev, pf.page == pgs.page { pgs.y = max(pgs.y, pf.y) }
            }
            // (Not under the switch with columns: splicing the old pieces back in lost the lines
            // of a paragraph that stood in the second column slot; dx2 6e956549's page 3 ran 26 lines short.)
            // Converged: this paragraph starts on the same page at the same
            // y as before and nothing below has changed, so the old pieces
            // and pages from here on are still right.
            if pgs.restarted, !(RichTextTheme.sectionColumnsFlow && _columns > 1), !pgs.reordered, pgs.i > pgs.settled, pgs.resumeCursor == nil, pgs.oldStart.count == count + 1,
               pgs.oldStart[pgs.i] < pgs.oldPieces.count, case let old = pgs.oldPieces[pgs.oldStart[pgs.i]],
               old.page == pgs.page, abs(old.pageY - pgs.y) < 0.01, abs(old.flowTop - _tops[pgs.i]) < 0.01,
               pgs.page < pgs.oldPages.count {
                _allPieces.append(contentsOf: pgs.oldPieces[pgs.oldStart[pgs.i]...])
                _pages[pgs.page].append(contentsOf: pgs.oldPages[pgs.page].filter { $0.paragraph >= pgs.i })
                if pgs.page + 1 < pgs.oldPages.count { _pages.append(contentsOf: pgs.oldPages[(pgs.page + 1)...]) }
                // (The pages taken back keep their pinned floats.)
                for (id, kept) in pgs.shelvedPins where kept.pin.page >= pgs.page && _pinnedFloats[id] == nil {
                    _pinnedFloats[id] = kept.pin
                    _floatShiftY[id] = kept.shift
                }
                if pgs.notesOn {
                    pgs.pageNotes = pgs.oldNotes[pgs.page] ?? pgs.pageNotes
                    for (k, v) in pgs.oldNotes where k > pgs.page { _pageNotes[k] = v }
                    for (k, v) in pgs.oldCuts where k >= pgs.page { _noteCutOut[k] = v }
                    for (k, v) in pgs.oldCarries where k > pgs.page { _noteCarryIn[k] = v }
                    pgs.pageCut = nil
                }
                break
            }
            if pgs.notesOn {
                var end = pgs.i + 1
                if let c = _cells[pgs.i] { while end < count, let d = _cells[end], d.table == c.table, d.row == c.row { end += 1 } }
                if pgs.placingRange != pgs.i ..< end {
                    if !pgs.rowPending.isEmpty { _pg_reserveNotes(&pgs, document, pgs.rowPending); pgs.rowPending = [] }
                    pgs.placingRange = pgs.i ..< end
                    pgs.placing = pgs.placingRange.flatMap { _footnotes(in: $0, document) }
                }
                if _cells[pgs.i] == nil, document.paragraphs[pgs.i].style.keepNext {
                    for id in pgs.placing where !pgs.pendingNotes.contains(id) && !pgs.pageNotes.contains(id) { pgs.pendingNotes.append(id) }
                } else if pgs.pendingNotes.isEmpty {
                    // (A body paragraph's note is set on this page only
                    // with the line that marks it: one whose line goes over
                    // goes with it — see `newPage`. zh-424775e4's page 9
                    // keeps three lines of the paragraph whose fourth marks
                    // footnote 2, which stands on page 10 in Word's print.)
                    if theme.wordRules, _cells[pgs.i] == nil, pgs.placing.count > 0 {
                        var here: [Int] = []
                        var room = 0.0
                        let width = _pg_noteWidth(&pgs, document)
                        for id in pgs.placing where !pgs.pageNotes.contains(id) {
                            guard var mark = _footnoteMarkLine(pgs.i, id, document), let note = _note(id, width: width, document) else { here.append(id); continue }
                            // (On a page of columns the mark's line is the whole line it
                            // stands in, a raised mark's box ending above its foot.)
                            if pgs.slotNotes {
                                let g = geometry(pgs.i)
                                if let lb = Self._lineBottoms(g.painter).map({ $0 + g.textTop }).first(where: { $0 >= mark.bottom - 0.5 }) { mark.bottom = max(mark.bottom, lb) }
                            }
                            room += note.height + (pgs.pageNotes.isEmpty && here.isEmpty ? _note(-1, width: width, document)?.height ?? 0 : 0)
                            if pgs.y + (mark.bottom - _tops[pgs.i]) + room > pgs.contentH + 0.01 {
                                // (Unless what is left under the mark's line
                                // holds a line of it or more: the note parts
                                // there, the rest first at the next page's
                                // foot. zh-344a8d08's footnote 3, three lines
                                // marked in page 4's last, has two there in
                                // Word's print and the third on page 5; ours
                                // took the mark's line over with it, and the
                                // line before, two lines short a page.)
                                let left = pgs.contentH - (pgs.y + (mark.bottom - _tops[pgs.i])) - (room - note.height)
                                if pgs.pageCut == nil, let keep = _noteCuts(id, width: width, document).last(where: { $0 <= left + 0.01 }) {
                                    pgs.pageCut = (id, keep)
                                    here.append(id)
                                    if pgs.slotNotes { pgs.cutEnds = pgs.y + (mark.bottom - _tops[pgs.i]) }
                                    // (A note that parts leaves the foot of the next page to its rest, and a later note
                                    // cannot begin there: the line marking the next one,
                                    // when it stands below this mark's, goes over with
                                    // it. xd e50792c2's footnote 7 parts pages 13/14 in
                                    // Word's print and the lines marking 8 open page 14;
                                    // ours kept them and set 8 first on page 14, a page
                                    // short in all.)
                                    if theme.wordRules, !pgs.slotNotes, let next = pgs.placing.first(where: { !here.contains($0) && !pgs.pageNotes.contains($0) }),
                                       let m2 = _footnoteMarkLine(pgs.i, next, document), m2.top > mark.top + 0.5 {
                                        pgs.contentH = max(1, min(pgs.contentH, pgs.y + (m2.bottom - _tops[pgs.i]) + room - note.height + keep))
                                    }
                                } else if mark.top > _tops[pgs.i] + 0.5 || pgs.y > 0.01 {
                                    // (With no line of it there, the mark's line
                                    // goes over with it: the page ends over that
                                    // line. zh-c15af02e's footnote 1, one line,
                                    // marked in the line that would end page 5,
                                    // opens page 6's foot in Word's print with
                                    // that line at page 6's head; ours kept the
                                    // line on page 5 and the note went over
                                    // alone, and every page after ran a line
                                    // ahead.)
                                    // (Over that line — not over it less the
                                    // room of the notes taken before it, which
                                    // `reserveNotes` takes off the foot next:
                                    // zh-7a16a243's page 12 ends with the line
                                    // marking notes 15 and 16 in Word's print,
                                    // note 17's line first on page 13; the room
                                    // of 15 and 16, counted twice, sent their
                                    // line over too, and twelve pages ran a
                                    // line behind.)
                                    pgs.contentH = max(1, min(pgs.contentH, pgs.y + (mark.top - _tops[pgs.i]) + (here.isEmpty ? 0 : room - note.height)))
                                }
                                for later in pgs.placing where !here.contains(later) && !pgs.pageNotes.contains(later) && !pgs.pendingNotes.contains(later) { pgs.pendingNotes.append(later) }
                                break
                            }
                            here.append(id)
                        }
                        _pg_reserveNotes(&pgs, document, here)
                        if let end = pgs.cutEnds { pgs.contentH = max(1, min(pgs.contentH, end + 0.5)); pgs.cutEnds = nil }
                    } else if theme.wordRules, let c0 = _cells[pgs.i], pgs.placing.count > 0 {
                        // (A row's notes likewise: on this page those marked
                        // in lines of the row this page holds, the rest with
                        // the parts of it that hold their marks — zh-499adba6
                        // is a book set in a one-column table, a chapter a
                        // row, and Word sets its footnotes 1-8, marked on
                        // page 5, at page 5's foot; ours reserved the room
                        // for them at page 3's, where the row began, and the
                        // pages after ran six lines early.)
                        var here: [Int] = []
                        var room = 0.0
                        let width = _pg_noteWidth(&pgs, document)
                        for id in pgs.placing where !pgs.pageNotes.contains(id) {
                            guard pgs.rowPending.isEmpty, let k = pgs.placingRange.first(where: { _footnotes(in: $0, document).contains(id) }),
                                  let mark = _footnoteMarkLine(k, id, document), let note = _note(id, width: width, document) else {
                                if pgs.rowPending.isEmpty { here.append(id) } else { pgs.rowPending.append(id) }
                                continue
                            }
                            room += note.height + (pgs.pageNotes.isEmpty && here.isEmpty ? _note(-1, width: width, document)?.height ?? 0 : 0)
                            if pgs.y + (mark.bottom - c0.rowTop) + room > pgs.contentH + 0.01 {
                                // (As under a body paragraph's mark: the note
                                // parts where a line of it fits under its
                                // mark's line, else the page ends over that
                                // line and the note goes over with it. Left
                                // for later, the note of a row that fits whole
                                // without it was reserved only after the row
                                // was set: zh-499adba6's book is a table, a
                                // paragraph a row, and its footnote 11, marked
                                // in the second line of the row "在重要政策領域…"
                                // near page 90's foot, parts there in Word's
                                // print, the row with it; ours set the row's
                                // seven lines whole and the note's 134pt over
                                // the last five.)
                                let left = pgs.contentH - (pgs.y + (mark.bottom - c0.rowTop)) - (room - note.height)
                                if pgs.pageCut == nil, let keep = _noteCuts(id, width: width, document).last(where: { $0 <= left + 0.01 }) {
                                    pgs.pageCut = (id, keep)
                                    here.append(id)
                                } else {
                                    if pgs.y > 0.01 || mark.top > c0.rowTop + 0.5 {
                                        // (The row's part ends over that line with its closing rule under it, which is not room the cut asks for.)
                                        pgs.contentH = max(1, min(pgs.contentH, pgs.y + (mark.top - c0.rowTop) + _pg_ruleUnder(&pgs, document, c0, parted: true) + (here.isEmpty ? 0 : room - note.height)))
                                    }
                                    pgs.rowPending.append(id)
                                }
                                for later in pgs.placing where !here.contains(later) && !pgs.pageNotes.contains(later) && !pgs.rowPending.contains(later) { pgs.rowPending.append(later) }
                                break
                            }
                            here.append(id)
                        }
                        _pg_reserveNotes(&pgs, document, here)
                    } else {
                        _pg_reserveNotes(&pgs, document, pgs.placing)
                    }
                } else {
                    var ids = pgs.pendingNotes
                    pgs.pendingNotes = []
                    for id in pgs.placing where !ids.contains(id) { ids.append(id) }
                    _pg_reserveNotes(&pgs, document, ids, deferring: true)
                }
            }
            // (An ordinary table, set under a paragraph, that has no room beside a box wrapped square
            // which the paragraphs above anchor, is set under the box's foot, its bottom distance and all:
            // Word's print of xa gv-d4270b921d, a 468pt table under a 186pt logo box, the table's top
            // border at the box's foot plus 3.6pt; ours set it at the blank line, under the box's body.)
            if theme.wordRules, RichTextTheme.wordWindowsPages, pgs.resumeCursor == nil, pgs.i > 0, !pgs.bands.isEmpty, let c = _cells[pgs.i], _cells[pgs.i - 1] == nil,
               _tableFirstParagraph[c.table] == pgs.i, document.tableStyles[c.table]?.floatsOverText != true,
               case let tableWidth = (_columnWidths[c.table] ?? []).reduce(0, +), tableWidth > 0 {
                var steps = 0
                while steps < 8, let band = pgs.bands.filter({ $0.top < pgs.y + 0.5 && $0.bottom > pgs.y + 0.5 }).min(by: { $0.bottom < $1.bottom }) {
                    let column = _flowWidth(pgs.i)
                    let room = band.left < -1000 ? column - band.right : (band.right > 1000 ? band.left : max(band.left, column - band.right))
                    guard tableWidth > room + 0.01 else { break }
                    RuleTrace.hit("word-table-with-no-room-beside-a-square-box-stands-under-it")
                    pgs.y = band.bottom; steps += 1
                }
            }
            if let c = _cells[pgs.i] {
                _pg_tableRow(&pgs, document, c, sectionBreakHandled)
                continue
            }
            defer { pgs.i += 1 }
            let top = _tops[pgs.i]
            let bottom = top + _heights[pgs.i]
            // (One of no height takes its place on the page all the same.)
            if bottom - top < 0.01 { pgs.pageFresh = false }
            // A section of one empty paragraph has a page of its own, and
            // the next section starts on the page after it — Word leaves
            // that page blank (zh-06c46ba9's page 2). A page break just
            // before a section's end is that same break, not a second one:
            // the empty paragraph that ends the section stays on the page
            // the break ends. Lab `es` (`body54.py`), in two packages,
            // 2026-10-14, all six cases; it replaces a mode-14 rule for
            // zh-9e08ed28 (which is the second case) and accounts for
            // zh-ae655121 too.
            let st0 = document.paragraphs[pgs.i].style
            let endsSection = theme.wordRules && bottom - top < 0.01 && st0.sectionXML != nil && st0.sectionBreaksPage == true
            let breakIsTheSections = endsSection && st0.breakEndsPrevious && !st0.pageBreakInline
            // A page break and the section's mark in one paragraph (the
            // break carried to the paragraph after, `breakEndsPrevious`):
            // the mark stays on the page the break ends where a line of
            // the paragraph fits there; else it takes a page of the
            // section it ends, and the next section the page after. Lab
            // `lb`, from zh-1a3c7aa0's package, modes 12 and 15: under a
            // filler leaving R points the next section opens on page 2
            // from R = 43 and on page 3 below it, whatever the paragraph's
            // space after — its footer took 27.4 of that, leaving one
            // 15.6pt line; with the paragraph's exact 28.9pt line, from
            // R = 65 and not at 56. zh-1a3c7aa0's page 11.
            if theme.wordRules, endsSection, pgs.resumeCursor == nil, pgs.y > 0.01, _columns == 1, pgs.i + 1 < count,
               document.paragraphs[pgs.i + 1].style.breakEndsPrevious, _pageBreak[pgs.i + 1],
               !document.paragraphs[pgs.i + 1].style.pageBreakInline,
               pgs.contentH - pgs.y < _markLineHeight(pgs.i, document) - 0.01 {
                _pg_newPage(&pgs, document)
            }
            // (Empty paragraphs after a page-anchored table that ran over to a later page, with room
            // beside it, stand beside its part on its LAST page from the page's top, and what follows goes
            // under both: Word's prints of labs ftempty (empties at the p2 top beside the table, heading
            // under them) and ftfull (a full-width table: they stand under it as usual); dx2 9baed400 p32,
            // the heading at 72 + the four empties + its own drop = 210.5 as in Word.)
            if pgs.roomOverTable != nil, let tn = pgs.roomOverTableName {
                let pp = document.paragraphs[pgs.i]
                if _cells[pgs.i] == nil, pgs.resumeCursor == nil, pp.text.isEmpty, pp.image == nil, pp.inlineImages.isEmpty, pp.style.frameXML == nil,
                   !_pageBreak[pgs.i], pp.style.sectionXML == nil, !_floatLeavesNoStrip(tn, pgs.i, document),
                   let top = _pages[pgs.page].filter({ _cells[$0.paragraph]?.table == tn && !$0.repeated }).map(\.pageY).min() {
                    RuleTrace.hit("word-empties-after-a-page-anchored-table-stand-beside-its-last-page")
                    pgs.besideEmpties = (top, (pgs.besideEmpties?.sum ?? 0) + _heights[pgs.i])
                    continue
                }
                pgs.roomOverTable = nil
                pgs.roomOverTableName = nil
            }
            if let b = pgs.besideEmpties {
                pgs.besideEmpties = nil
                pgs.y = max(pgs.y, b.top + b.sum)
            }
            // (In a compat 15 file the empties after the first, which stand past the foot, go with it: lab
            // compat1415b, 11pt lines with 10 after and 16pt left, put the first on the page and the
            // second table at the next page's head under none of them; a first that does not fit
            // goes over with the rest, as in compat 14.)
            if theme.wordRules, RichTextTheme.wordWindowsPages, (document.compatibilityMode ?? 12) >= 15, pgs.resumeCursor == nil, pgs.y >= pgs.contentH - 0.01,
               _columns == 1, pgs.i > 0, _cells[pgs.i - 1] == nil, document.paragraphs[pgs.i - 1].text.isEmpty, document.paragraphs[pgs.i].text.isEmpty,
               document.paragraphs[pgs.i].image == nil, document.paragraphs[pgs.i].style.frameXML == nil, !_pageBreak[pgs.i] {
                var k = pgs.i
                while k < count, _cells[k] == nil, document.paragraphs[k].text.isEmpty { k += 1 }
                if k < count, _cells[k] != nil, Self._followsFloatingTable(k, _cells[k]!.table, document: document, cells: _cells) {
                    RuleTrace.hit("compat15-empties-past-the-foot-before-a-floating-table-are-absorbed")
                    pgs.y += _heights[pgs.i]
                    continue
                }
            }
            // (An empty paragraph between two tables floating by the text, in a compat 14 file: Word
            // carries it to the next page unless its space after fits there too — lab compat1415b,
            // Calibri 11pt lines 15.4 over 10 after on a page with 16pt left: both empties go to the
            // next page and the second table stands under them, where 0 after leaves the first one.)
            var emptyBegins = pgs.y
            if let last = pgs.lastEmptyAt, last.i == pgs.i - 1, last.page == pgs.page { emptyBegins = max(pgs.y, last.y + _heights[pgs.i - 1]) }
            // (An empty paragraph above a table that asks for the body's foot (tblpYSpec bottom) must clear the table's
            // top with its space after, else Word carries it to the next page: sa1 74e2ec8f's cover, four empties
            // of 25.4pt over a full-width bottom table, Word's prints keep three and carry the fourth, even with the table
            // 3pt higher; with 0 after all four stay.)
            if theme.wordRules, RichTextTheme.wordWindowsPages, pgs.resumeCursor == nil, pgs.y > 0.01, (document.compatibilityMode ?? 12) < 15,
               _columns == 1, document.paragraphs[pgs.i].text.isEmpty, document.paragraphs[pgs.i].image == nil, document.paragraphs[pgs.i].style.frameXML == nil,
               !_pageBreak[pgs.i], _cells[pgs.i] == nil {
                // (The table stands after the empties in the file, or before them: its first cell is the first
                // non-empty paragraph in either direction.)
                var k = pgs.i
                while k < count, _cells[k] == nil, document.paragraphs[k].text.isEmpty, document.paragraphs[k].image == nil { k += 1 }
                var cell = k < count ? _cells[k] : nil
                if cell == nil || document.tableStyles[cell!.table]?.bottomAligned != true {
                    var j = pgs.i - 1
                    while j >= 0, _cells[j] == nil, document.paragraphs[j].text.isEmpty, document.paragraphs[j].image == nil { j -= 1 }
                    cell = j >= 0 ? _cells[j] : nil
                    if let c = cell, j >= 0, pgs.bottomTablePage?.table == c.table, pgs.bottomTablePage?.page == pgs.page, document.tableStyles[c.table]?.bottomAligned == true {
                        var f = j
                        while f > 0, let d = _cells[f - 1], d.table == c.table { f -= 1 }
                        cell = _cells[f]
                    } else { cell = nil }
                }
                if let c = cell, document.tableStyles[c.table]?.bottomAligned == true {
                    var bottom = c.rowTop + c.ownRowHeight, m = 0
                    while m < count {
                        if let d = _cells[m], d.table == c.table { bottom = max(bottom, d.rowTop + d.ownRowHeight) }
                        m += 1
                    }
                    let height = bottom - c.rowTop
                    let pst = document.paragraphs[pgs.i].style
                    if height < pgs.contentH, Self._needs(_heights[pgs.i], _px(pst.spaceAfter), pst.lineSpacing) > pgs.contentH - height - emptyBegins + 0.01 {
                        RuleTrace.hit("word-empty-above-a-bottom-table-clears-its-top-with-its-space-after")
                        _pg_newPage(&pgs, document)
                    }
                }
            }
            if theme.wordRules, RichTextTheme.wordWindowsPages, pgs.resumeCursor == nil, pgs.y > 0.01,
               // (Compat 15 carries a lone empty between the tables, lab compat1415b after2; of two or more the ones past the foot are absorbed.)
               (document.compatibilityMode ?? 12) < 15 || (pgs.i > 0 && _cells[pgs.i - 1] != nil && pgs.i + 1 < count && _cells[pgs.i + 1] != nil),
               _columns == 1, document.paragraphs[pgs.i].text.isEmpty, document.paragraphs[pgs.i].image == nil, document.paragraphs[pgs.i].style.frameXML == nil,
               case let pst = document.paragraphs[pgs.i].style, case let after = _px(pst.spaceAfter),
               // (Its line counts as a single one, Word's multiple hanging below the foot like the leading.)
               Self._needs(_heights[pgs.i], after, pst.lineSpacing) > pgs.contentH - emptyBegins + 0.01, !_pageBreak[pgs.i],
               // (A line that stands over a floating table's offset, in the room above the table, is not at the foot:
               // sa1 5e813226's five empties under a text-anchored table with tblpY 798: Word sets the first two over
               // the table and the third under it on the page, the other two carried; ours carried from the second.)
               !(pgs.textFloatTop.map { $0.chained && $0.page == pgs.page && pgs.frameReturn == nil && _heights[pgs.i] <= $0.down + 0.01 } ?? false) {
                var k = pgs.i
                while k < count, _cells[k] == nil, document.paragraphs[k].text.isEmpty { k += 1 }
                if k < count, _cells[k] != nil, Self._followsFloatingTable(k, _cells[k]!.table, document: document, cells: _cells) {
                    RuleTrace.hit("compat14-empty-between-floating-tables-carries-with-its-space-after")
                    _pg_newPage(&pgs, document)
                }
            }
            // (An empty line that stands over a floating table's offset does not move the flow under the table on.)
            if _cells[pgs.i] == nil, document.paragraphs[pgs.i].text.isEmpty {
                pgs.lastEmptyAt = RichTextTheme.wordWindowsPages && (pgs.textFloatTop.map { $0.chained && $0.page == pgs.page && pgs.frameReturn == nil && _heights[pgs.i] <= $0.down + 0.01 } ?? false) ? nil : (pgs.i, pgs.page, pgs.y)
            }
            // (A paragraph that is only the break, carried to a page of its
            // own because no line of it fit at the foot under a table,
            // stays on the page it ends where the table reached the foot,
            // or all but a quarter of the line (ours stands a few points
            // off Word's) — not where more was left: zh-6043ad90's
            // landscape table leaves 11.9pt of the paragraph's 37.2 line,
            // and Word's page 3 is the break's alone, "第二部分" on page 4;
            // ours kept it under the table, a page early. Where a little was
            // left there — after text Word does give it the page, zh-a4b0f6ea and
            // zh-c8eb6e92 have those blank pages, and so does zh-0aac9d1a's
            // page 10 under a table that left 24.7pt of a 31.2pt line: Word leaves it there and opens the next page with
            // what follows — zh-60c80728's page 25 ends in a table 2.9pt
            // over the foot and an empty paragraph with the break, and
            // Word's page 26 begins "7.2"; ours had the empty paragraph on
            // a page 26 of its own, and "7.2" on 27.)
            if theme.wordRules, _pageBreak[pgs.i], document.paragraphs[pgs.i].style.breakEndsPrevious, !document.paragraphs[pgs.i].style.pageBreakInline,
               pgs.resumeCursor == nil, pgs.page > 0, pgs.i > 1, document.paragraphs[pgs.i - 1].text.isEmpty, document.paragraphs[pgs.i - 1].cell == nil,
               document.paragraphs[pgs.i - 2].cell != nil,
               _pages[pgs.page].count == 1, let was = _pages[pgs.page].first, was.paragraph == pgs.i - 1, was.pageY < 0.01,
               // (Where the table reached the foot or all but a point or two
               // of it, not a quarter of the line short: lab brk, zh-0aac9d1a's
               // page 7, a table 3.4pt above the foot in Word's print and in
               // ours, and Word gives the break's 31.2pt line page 8, a blank
               // one; zh-60c80728's page 25 table ends 1.3pt above it in both,
               // and Word keeps the break there.)
               pgs.prevContentH - pgs.prevY < _px(2.5),
               let at = _allPieces.lastIndex(where: { $0.paragraph == pgs.i - 1 && $0.page == pgs.page }) {
                var only = PagePiece(paragraph: was.paragraph, flowTop: was.flowTop, flowBottom: was.flowBottom, page: pgs.page - 1, pageY: pgs.contentH)
                only.part = was.part
                _pages[pgs.page].removeAll()
                _pages[pgs.page - 1].append(only)
                _allPieces[at] = only
                pgs.y = 0
                pgs.pageFresh = true
                pgs.markOnPage = false
            }
            // (Where text follows the break in its paragraph, the empty
            // part before it needs no room at all: it stands at the foot of
            // the page the break ends, its floats with it — lab brk's rule
            // (windows, zh-0aac9d1a and zh-167ee06c: a break opening a
            // paragraph with text after it ends the page where it stands).
            // zh-6d402586's notice ends p28 at its last line, and the next
            // paragraph is a page-placed note, a page break and the next
            // notice: Word keeps the note on p28 and opens p29 with the
            // notice; ours gave the note's empty line page 29 alone.)
            // (Not where that paragraph was itself opened by a break:
            // tdf92724's text box stands in an empty paragraph after a page
            // break and "Contents" has a break of its own — the box keeps
            // page 2, and "Contents" has page 3.)
            if theme.wordRules, _pageBreak[pgs.i], document.paragraphs[pgs.i].style.breakEndsPrevious, !document.paragraphs[pgs.i].style.pageBreakInline,
               pgs.resumeCursor == nil, pgs.page > 0, pgs.i > 0, !_pageBreak[pgs.i - 1], case let before = document.paragraphs[pgs.i - 1], before.cell == nil,
               before.text.unicodeScalars.allSatisfy({ $0.value == 0xFFFC }),
               before.image.map({ $0.float != nil }) ?? !before.inlineImages.isEmpty,
               before.inlineImages.values.allSatisfy({ $0.float != nil }),
               case let after = document.paragraphs[pgs.i], !after.text.isEmpty || !after.inlineImages.isEmpty || after.image != nil,
               _pages[pgs.page].count == 1, let was = _pages[pgs.page].first, was.paragraph == pgs.i - 1, was.pageY < 0.01,
               let at = _allPieces.lastIndex(where: { $0.paragraph == pgs.i - 1 && $0.page == pgs.page }) {
                var only = PagePiece(paragraph: was.paragraph, flowTop: was.flowTop, flowBottom: was.flowBottom, page: pgs.page - 1, pageY: pgs.contentH)
                only.part = was.part
                _pages[pgs.page].removeAll()
                _pages[pgs.page - 1].append(only)
                _allPieces[at] = only
                pgs.y = 0
                pgs.pageFresh = true
                pgs.markOnPage = false
            }
            // Columns balanced at a continuous section break: Word sets
            // the section before it in columns of even length on the page
            // the break is on, and the next section under them. zh-b5359de4
            // p4: the preface's last lines stand half in each column in
            // Word's print, its contents under them, 44.3pt higher than
            // ours, which filled the first column and went on in the second.
            // (Plain paragraphs only: no table rows, no notes on the page.)
            let nb = _perSection && pgs.i > 0 ? _columnsOf(paragraph: pgs.i - 1) : _columns
            var balancedHere = false
            if theme.wordRules, nb > 1, !(_perSection && document.leavesColumnsUnbalanced), !_pageBreak[pgs.i], pgs.i > 0, pgs.i < _sectionOf.count, _sectionOf[pgs.i] != _sectionOf[pgs.i - 1],
               _cells[pgs.i] == nil || RichTextTheme.sectionColumnsFlow, pgs.resumeCursor == nil, !pgs.notesOn || pgs.pageNotes.isEmpty {
                let first = (pgs.page / _columns) * _columns
                var seq: [PagePiece] = []
                // (Through the last column of the page, not just the one being set:
                // an earlier section's balanced block stands in all of them —
                // tdf139336's second three-column section, under the first's.)
                let lastPage = max(pgs.page, min(first + _columns - 1, _pages.count - 1))
                for s in first ... lastPage { seq += _pages[s] }
                // (A section that began partway down the page balances its
                // own pieces, under those of the sections above it.)
                // (A section that holds a column break has its columns made by
                // the breaks: balancing would move what follows the break back
                // into the first column. dx2 9331dd51's title block, "Stručan rad"
                // opening the second column at the first column's top.)
                let ownBreaks = theme.wordRules && RichTextTheme.sectionColumnsFlow && seq.contains(where: { $0.paragraph < document.paragraphs.count && _sectionOf[$0.paragraph] == _sectionOf[pgs.i - 1] && document.paragraphs[$0.paragraph].style.columnBreak && document.paragraphs[$0.paragraph].style.pageBreakBefore })
                var head: [PagePiece] = []
                if _perSection, let before = seq.first.map({ _sectionOf[$0.paragraph] }), before != _sectionOf[pgs.i - 1] {
                    head = seq.filter { _sectionOf[$0.paragraph] != _sectionOf[pgs.i - 1] }
                }
                let base = head.map { $0.pageY + $0.height }.max() ?? 0
                // (A table of one column in the block is its rows, set one under
                // another like paragraphs: they part between the columns as
                // paragraphs do. lo-eb12e7d4 p15's 6.1.1-6.1.3 rows, over the
                // columns' even length in Word's print.)
                let wide = Set(seq.compactMap { _cells[$0.paragraph] }.filter { $0.column > 0 || $0.span > 1 }.map(\.table))
                let oneColumnTables = Set(seq.compactMap { _cells[$0.paragraph]?.table }).subtracting(wide)
                let tail = Array(_allPieces.suffix(seq.count))
                if !ownBreaks, seq.count > head.count, tail == seq || Set(tail.map(\.paragraph)) == Set(seq.map(\.paragraph)),
                   seq.allSatisfy({ head.contains($0) || ((_cells[$0.paragraph].map { document.tableStyles[$0.table]?.floatsOverText == true || oneColumnTables.contains($0.table) } ?? true) && !$0.repeated && $0.part == .all) }) {
                    // (A floating table in the block stands where it is, a band the
                    // columns run around: lo-a998edda's A1–A4 in two columns are 2
                    // and 2 in Word's print, the table across both, the fourth
                    // line under it.)
                    let bandsHere = seq.filter { _cells[$0.paragraph] != nil && !oneColumnTables.contains(_cells[$0.paragraph]!.table) }
                    let total = (first ... lastPage).reduce(0.0) { acc, s in acc + ((_pages[s].filter { p in !head.contains(where: { $0 == p }) }).map { $0.pageY + $0.height }.max().map { $0 - base } ?? 0) }
                    // (The space after the block's last paragraph is not a column's length:
                    // sa1 978697fd's three one-line items, 1+1+1 in Word's print, were
                    // 2+1 here with the last item's 8pt counted in the even length.)
                    let lastAfter = theme.wordRules && pgs.i >= 1 && seq.contains(where: { $0.paragraph == pgs.i - 1 }) && _cells[pgs.i - 1] == nil ? _px(document.paragraphs[pgs.i - 1].style.spaceAfter) : 0
                    let target = max(0, total - lastAfter) / Double(nb)
                    var out: [[PagePiece]] = Array(repeating: [], count: nb)
                    var c = 0, cy = 0.0
                    var lastBottom: [Int: Double] = [:]
                    for piece in seq where !head.contains(where: { $0 == piece }) && (_cells[piece.paragraph] == nil || oneColumnTables.contains(_cells[piece.paragraph]!.table)) {
                        let gap = max(0, piece.pageY - (lastBottom[piece.page] ?? base))
                        lastBottom[piece.page] = piece.pageY + piece.height
                        var top = cy > 0.01 ? cy + gap : 0
                        var rest = (from: piece.flowTop, to: piece.flowBottom)
                        if !bandsHere.isEmpty, theme.wordRules {
                            let h = rest.to - rest.from
                            for band in bandsHere.sorted(by: { $0.pageY < $1.pageY }) where top + base + h > band.pageY + 0.01 && top + base < band.pageY + band.height - 0.01 {
                                top = band.pageY + band.height - base
                            }
                        }
                        while true {
                            // (A piece that starts at the even length starts the
                            // next column: zh-b5359de4's cover, two empty 36pt
                            // lines in two columns, one in each in Word's print —
                            // its title one line down; ours cut the second at its
                            // own line and stood the title two down.)
                            if c < nb - 1, top > 0.01, top >= target - 0.5 {
                                c += 1; top = 0; cy = 0
                                continue
                            }
                            if c == nb - 1 || top + (rest.to - rest.from) <= target + 0.5 {
                                out[c].append(PagePiece(paragraph: piece.paragraph, flowTop: rest.from, flowBottom: rest.to, page: first + c, pageY: base + top))
                                cy = top + (rest.to - rest.from)
                                break
                            }
                            // (The first columns at least as long as the rest:
                            // the first line that reaches the even length ends
                            // the column.)
                            let g = geometry(piece.paragraph)
                            let bottoms = Self._lineBottoms(g.painter).map { g.textTop + $0 }
                            let cuts = bottoms.filter { $0 > rest.from + 0.5 && $0 < rest.to - 0.5 }
                            // (Only the paragraph's last line reaches the even length:
                            // the column ends after the whole paragraph, as Word sets
                            // it, not with its last line alone at the next column's
                            // top: cab6d785's 3-line, 4-line and 5-line paragraphs in
                            // two columns are 7 and 6 lines in Word's print, ours 6
                            // and 7.)
                            if theme.wordRules, c < nb - 1, top > 0.01, !cuts.contains(where: { top + ($0 - rest.from) >= target - 0.5 }),
                               base + top + (rest.to - rest.from) <= pgs.contentH + 0.01 {
                                RuleTrace.hit("column-balance-ends-after-the-whole-paragraph")
                                out[c].append(PagePiece(paragraph: piece.paragraph, flowTop: rest.from, flowBottom: rest.to, page: first + c, pageY: base + top))
                                c += 1; cy = 0
                                break
                            }
                            // (A two-line paragraph is not split one and one between
                            // balanced columns: widow control keeps it whole at the
                            // next column's top, as Word sets 48e5a592's bullet.)
                            if theme.wordRules, c < nb - 1, top > 0.01, cuts.count == 1, rest.from == piece.flowTop,
                               document.paragraphs[piece.paragraph].style.widowControl, !document.widowControlSuspended {
                                RuleTrace.hit("column-balance-keeps-a-two-line-paragraph-whole")
                                c += 1; top = 0; cy = 0
                                continue
                            }
                            if let cut = cuts.first(where: { top + ($0 - rest.from) >= target - 0.5 }) ?? cuts.last,
                               base + top + (cut - rest.from) <= pgs.contentH + 0.01 {
                                // (At its last line the paragraph ends here, the
                                // space under that line with it: zh-b5359de4's empty
                                // 36pt cover paragraphs, a line of 54.2 in 62.2, sent
                                // that 8pt on as a piece and the next column started
                                // under it.)
                                if let lastLine = bottoms.last, abs(cut - lastLine) < 0.01,
                                   base + top + (rest.to - rest.from) <= pgs.contentH + 0.01 {
                                    out[c].append(PagePiece(paragraph: piece.paragraph, flowTop: rest.from, flowBottom: rest.to, page: first + c, pageY: base + top))
                                    c += 1; cy = 0
                                    break
                                }
                                out[c].append(PagePiece(paragraph: piece.paragraph, flowTop: rest.from, flowBottom: cut, page: first + c, pageY: base + top))
                                rest = (cut, rest.to)
                            } else if top < 0.01 || ((_perSection || !bandsHere.isEmpty) && top < target - 0.5) {
                                // (A line that starts before the even length
                                // ends the column, as the first line that
                                // reaches it does in a paragraph of several:
                                // tdf139336's eight lines in three columns
                                // are 3, 3 and 2 in Word's print.)
                                out[c].append(PagePiece(paragraph: piece.paragraph, flowTop: rest.from, flowBottom: rest.to, page: first + c, pageY: base + top))
                                cy = top + (rest.to - rest.from)
                                c += 1; cy = 0
                                break
                            }
                            c += 1
                            top = 0
                            cy = 0
                        }
                    }
                    // (A band already in `head`, a table of the section above, stays there: set again it was drawn once per balance.)
                    out[0] += head.isEmpty ? bandsHere : bandsHere.filter { b in !head.contains(where: { $0 == b }) }
                    let blockBottom = out.map { $0.map { $0.pageY + $0.height }.max() ?? 0 }.max() ?? 0
                    if blockBottom <= pgs.contentH + 0.01 {
                        _allPieces.removeLast(seq.count)
                        while _pages.count < first + _columns { _pages.append([]) }
                        for k in 0 ..< nb where first + k <= max(pgs.page, first + _columns - 1) { _pages[first + k] = head.filter { $0.page == first + k } + out[k] }
                        _allPieces.append(contentsOf: (head + out.flatMap { $0 }).sorted { ($0.paragraph, $0.flowTop) < ($1.paragraph, $1.flowTop) })
                        pgs.page = first
                        pgs.y = blockBottom
                        pgs.columnFloor = (first / _columns, blockBottom)
                        balancedHere = true
                    }
                }
                // (Its columns stay as the breaks made them; the next section goes
                // on under the longest, as under a balanced block.)
                if ownBreaks, !balancedHere, seq.count > head.count {
                    // (A paragraph that holds only a column break: its mark falls in the column
                    // the break opens, so it does not lengthen the column it stands in.)
                    let holdsBreak: (Int) -> Bool = { k in
                        k + 1 < document.paragraphs.count && document.paragraphs[k].text.isEmpty && document.paragraphs[k].cell == nil
                            && document.paragraphs[k + 1].style.columnBreak && document.paragraphs[k + 1].style.pageBreakBefore
                            && document.paragraphs[k + 1].style.breakEndsPrevious
                    }
                    let blockBottom = seq.filter { !holdsBreak($0.paragraph) }.map { $0.pageY + $0.height }.max() ?? 0
                    if blockBottom <= pgs.contentH + 0.01 {
                        pgs.page = first
                        pgs.y = blockBottom
                        pgs.columnFloor = (first / _columns, blockBottom)
                        balancedHere = true
                    }
                }
            }
            // (A section of fewer columns than the slot it would continue in,
            // when the columns above were not balanced: it starts on the
            // next page's first column, never in a later column slot, where
            // it would paint a column to the right.)
            if _perSection, theme.wordRules, !balancedHere, pgs.i > 0, pgs.i < _sectionOf.count, _sectionOf[pgs.i] != _sectionOf[pgs.i - 1],
               pgs.resumeCursor == nil, _columnsOf(paragraph: pgs.i) < _columns, pgs.page % _columns >= _columnsOf(paragraph: pgs.i),
     _setup(ofParagraph: pgs.i - 1).columnSpec != nil {   // unequal columns only: a later slot there paints off the page; equal ones continue in the slot
                repeat { _pg_newPage(&pgs, document) } while pgs.page % _columns >= _columnsOf(paragraph: pgs.i)
            }
            // (A section of columns that starts partway down a page: its
            // columns start there, the second under the first's top, not
            // at the page's.)
            if _perSection, theme.wordRules, !balancedHere, !_pageBreak[pgs.i], pgs.i > 0, pgs.i < _sectionOf.count, _sectionOf[pgs.i] != _sectionOf[pgs.i - 1],
               _columnsOf(paragraph: pgs.i) > 1, pgs.y > 0.01, pgs.resumeCursor == nil, pgs.page % _columns == 0 {
                pgs.columnFloor = (pgs.page / _columns, pgs.y)
            }
            // (A page break that opens the document's first paragraph is a
            // blank first page in Word: LibreOffice's
            // tdf153964_topMarginAfterBreak14 prints six pages for four of
            // ours. The paragraph property of the same name does nothing
            // there, which is why only the break inside the paragraph counts.)
            let opensTheDocument = theme.wordRules && RichTextTheme.wordWindowsPages && pgs.i == 0 && pgs.page == 0
                && document.paragraphs[pgs.i].style.pageBreakInline && !document.paragraphs[pgs.i].style.columnBreak
            if _pageBreak[pgs.i] && !sectionBreakHandled && !breakIsTheSections && (pgs.y > 0 || !_pages[pgs.page].isEmpty || pgs.markOnPage || opensTheDocument) && pgs.resumeCursor == nil {
                // (A page the line before hung past the foot of has no
                // room for the break's own line: that line takes a page
                // of its own, and the break ends that one too — a blank
                // page. Lab `gf` replayed in Word for Windows, 2026-10-14:
                // a 16pt line on 36pt of grid kept 31.75 to 35pt above the
                // foot, then "[break]测试", sets 测试 on page 3; with 36pt
                // left, on page 2. zh-6d1afa56's empty page 23.)
                if theme.wordRules, document.paragraphs[pgs.i].style.pageBreakInline, !document.paragraphs[pgs.i].style.columnBreak,
                   pgs.overfull || (pgs.y > pgs.contentH + 0.01 && pgs.spacedPast.map { abs($0 - pgs.y) > 0.01 } ?? true) {
                    _pg_newPage(&pgs, document)
                }
                _pg_newPage(&pgs, document)
                // (In columns a page break, or a section's, goes on to the
                // next page, not the next column: only a column break
                // does that. zh-b5359de4's preface section, after a cover
                // that runs into page 2's first column, opens Word's page
                // 3; ours set it in page 2's second column and went on a
                // column ahead of Word's.)
                if theme.wordRules, _columns > 1, !document.paragraphs[pgs.i].style.columnBreak {
                    while pgs.page % _columns != 0 { _pg_newPage(&pgs, document) }
                }
                if theme.wordRules, document.paragraphs[pgs.i].style.pageBreakTwice { _pg_newPage(&pgs, document) }
            }
            // A float that bands its page (`ImageFloat.bandsPage`): the text
            // keeps off it, and what of the page's text before its anchor
            // reaches into it goes under it, as under a table placed on the
            // page. (After the paragraph's own break: zh-fe536967's
            // photo is anchored at a section's start.)
            if theme.wordRules, RichTextTheme.wordWindowsPages, pgs.resumeCursor == nil, _columns > 1, pgs.y > 0.01, _cells[pgs.i] == nil, _columnPushed.contains(pgs.i) { _pg_newPage(&pgs, document) }
            // (A column's anchor paragraph whose own band, at the column's
            // top, would push the column's text down until the paragraph no
            // longer fits goes to the next column with its band: Word never
            // shows the picture where its paragraph is not. LibreOffice's
            // fdo43573-2-min, page 8: a 3-line paragraph at the foot of
            // column 2 anchors an 87x35pt picture 2.1pt under the top
            // margin; Word sets the paragraph and the picture on page 9,
            // ours set the picture over page 8's column and the paragraph
            // under it.)
            if theme.wordRules, RichTextTheme.wordWindowsPages, pgs.resumeCursor == nil, _columns > 1, _cells[pgs.i] == nil, pgs.deferredUnder.isEmpty, pgs.y > 0.01,
               !document.paragraphs[pgs.i].text.isEmpty {
                let own = (pgs.i < _floatImages.count ? _floatImages[pgs.i].map { [$0] } ?? [] : []) + (pgs.i < _inline.count ? _inline[pgs.i] : [])
                let physical = pgs.page / _columns
                let insetTop = physical < _pageInsetTop.count ? _pageInsetTop[physical] : 0
                var bandBottom = 0.0
                for image in own {
                    guard let f = image.float, f.bandsPage, f.verticalFrom != "paragraph", f.verticalAlign == nil, image.height > 0 else { continue }
                    let onPage = _px(f.y) - (f.verticalFrom == "margin" ? 0 : insetTop)
                    let top = onPage - _px(f.distanceTop)
                    if top <= _px(8) { bandBottom = max(bandBottom, onPage + _px(image.height + f.distanceBottom)) }
                }
                if bandBottom > 0, bandBottom <= pgs.contentH / 2, let first = _pages[pgs.page].first(where: { _cells[$0.paragraph] == nil && !$0.repeated }), first.pageY < bandBottom {
                    let bottoms = Self._lineBottoms(geometry(pgs.i).painter)
                    let need = bottoms.count <= 3 ? (bottoms.last ?? 0) : (bottoms.count >= 2 ? bottoms[1] : (bottoms.first ?? 0))
                    let colEnd = _pages[pgs.page].last.map { $0.pageY + $0.flowBottom - $0.flowTop } ?? pgs.y
                    if colEnd + (bandBottom - first.pageY) + need > pgs.contentH + 0.01 {
                        // (Word's prints, six variants of the document: the column before then
                        // loses its last paragraph to this one's top — "L (links) = geel" —
                        // when the paragraph and its picture were sent on; not when the picture
                        // is absent, or the paragraph still fits its first line.)
                        if !pgs.pinPass, pgs.page % _columns > 0, let prev = _pages[pgs.page - 1].last, !prev.repeated, _cells[prev.paragraph] == nil,
                           !_columnPushed.contains(prev.paragraph), _allPieces.filter({ $0.paragraph == prev.paragraph }).count == 1 {
                            _columnPushed.insert(prev.paragraph)
                            pgs.pushedAnew = true
                        }
                        _pg_newPage(&pgs, document)
                    }
                }
            }
            if theme.wordRules, pgs.resumeCursor == nil, _cells[pgs.i] == nil, pgs.deferredUnder.isEmpty {
                let images = (pgs.i < _floatImages.count ? _floatImages[pgs.i].map { [$0] } ?? [] : []) + (pgs.i < _inline.count ? _inline[pgs.i] : [])
                // (Pictures wrapped square, set side by side from one paragraph so that together they leave no strip a character
                // wide across the column: a later paragraph's line stands under them, an empty one too — dx2 es ebe45609's two
                // photos, 26.5 and 212.9pt in, 187 and 194pt wide, leave 17pt and 9.4pt; Word sets the empty lines after them
                // under the photos' foot, not beside them.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, _cells[pgs.i] == nil {
                    var boxes: [(l: Double, r: Double, top: Double, bottom: Double)] = []
                    let inner = _flowWidth(pgs.i)
                    for image in images {
                        guard image.textBox == nil, let f = image.float, f.wraps, !f.takesRoom, f.wrapSide == nil, f.verticalFrom == "paragraph", f.verticalAlign == nil,
                              f.horizontalAlign == nil, f.horizontalFrom == "column", image.width > 0, image.height > 0 else { continue }
                        let x = _px(f.x), w = min(_px(image.width), inner)
                        boxes.append((x - _px(f.distanceLeft ?? 9), x + w + _px(f.distanceRight ?? 9), pgs.y + _px(f.y) - _px(f.distanceTop),
                                      pgs.y + _px(f.y) + _px(image.height + f.effectBottom + f.distanceBottom)))
                    }
                    if boxes.count > 1 {
                        var widest = 0.0, edge = 0.0
                        for b in boxes.sorted(by: { $0.l < $1.l }) { widest = max(widest, b.l - edge); edge = max(edge, b.r) }
                        widest = max(widest, inner - edge)
                        let top = boxes.map(\.top).min() ?? 0, bottom = boxes.map(\.bottom).max() ?? 0
                        let me = pgs.i
                        pgs.narrowBands.removeAll(where: { $0.owner >= me })
                        if bottom > top, bottom > 0.01 { pgs.narrowBands.append((top, bottom, me, widest, widest)) }
                    }
                }
                for image in images {
                    // (A picture centred in its column, wrapped on both sides, with room at each side for less than
                    // three ems: the text of a later paragraph whose first unit does not fit at either side stands
                    // under it. Word's lab capwrap: a caption opening with a bracket sets nothing beside the picture
                    // at any gap, one opening with an ideograph sets one ideograph a row on each side only while it
                    // fits, and a line starts at the left piece: where its first unit does not fit there it goes under, as in 817e3a79's caption (room 32.2 each side, first line indented 32); the first line clear of the picture is the next row of the page's own pitch.)
                    if theme.wordRules, RichTextTheme.wordWindowsPages, let f = image.float, f.wraps, !f.takesRoom, f.wrapSide == nil,
                       f.verticalFrom == "paragraph", f.verticalAlign == nil, f.horizontalAlign == "center", f.horizontalFrom == "column",
                       _cells[pgs.i] == nil, image.width > 0, image.height > 0 {
                        let inner = _flowWidth(pgs.i), w = _px(image.width), x = (inner - w) / 2
                        let l = x - _px(f.distanceLeft ?? 9), r = inner - (x + w) - _px(f.distanceRight ?? 9)
                        let top = pgs.y + _px(f.y) - _px(f.distanceTop), bottom = pgs.y + _px(f.y) + _px(image.height + f.effectBottom + f.distanceBottom)
                        let cutAt = pgs.i; pgs.narrowBands.removeAll(where: { $0.owner >= cutAt })
                        if bottom > top, bottom > 0.01 { pgs.narrowBands.append((top, bottom, pgs.i, l, r)) }
                    }
                    guard let f = image.float, f.bandsPage else { continue }
                    let physical = pgs.page / _columns
                    let insetTop = physical < _pageInsetTop.count ? _pageInsetTop[physical] : 0
                    let mine = f.verticalFrom == "paragraph"
                    // (The paragraph after one that an earlier float's band pushed down stands under the band
                    // too, and its own box, set top and bottom from it, is measured from where the pushed
                    // paragraph would have stood: Word's print of dx2 87097d3e puts the third chart, 364.5pt
                    // from its paragraph, at the frame top under the second chart's band (Word 480.5 for the third chart), not 364.5pt below the pushed line.)
                    var carried = 0.0
                    if RichTextTheme.wordWindowsPages, mine, f.verticalAlign == nil, pgs.bandPushLast == pgs.i - 1, pgs.bandPushPage == pgs.page, pgs.bandPushDelta > 0.01, _cells[pgs.i] == nil {
                        carried = max(pgs.bandPushDelta, pgs.y - pgs.bandPushTop)
                        RuleTrace.hit("word-paragraph-after-a-pushed-one-keeps-its-box-at-the-unpushed-anchor")
                        // (A box so carried that its drawn frame would end past the text foot is raised until it ends
                        // at the foot: Word's print of dx2 87097d3e ends the third chart at 778.1, the page's bottom
                        // margin, where ours ended 6.5pt past it.)
                        let overFoot = pgs.y - carried + _px(f.y) + _bodyBoxHeight(image, document) - pgs.contentH
                        if overFoot > 0.01 { carried += overFoot; RuleTrace.hit("word-carried-box-ends-at-the-foot") }
                        _floatShiftY[image.id] = -carried
                        pgs.bandPushLast = pgs.i
                    }
                    var onPage = mine ? pgs.y - carried + _px(f.y) : _px(f.y) - (f.verticalFrom == "margin" ? 0 : insetTop)
                    var top = onPage - _px(f.distanceTop), bottom = onPage + _px(image.height + f.distanceBottom)
                    // (A picture the text goes over and under, set from its paragraph, whose foot would pass the
                    // page's foot while it would fit whole on a page of its own: Word sets the paragraph and the
                    // picture on the next page, the text after it under the picture there. sa2 0278f198's page 3,
                    // a 241pt picture 16.6pt under an empty line near the foot: Word's page 4 opens with it, ours
                    // let it run off page 3 and set the text of page 4 258pt too high.)
                    if theme.wordRules, RichTextTheme.wordWindowsPages, mine, f.verticalAlign == nil, !f.wraps, f.y >= 0, _columns <= 1,
                       pgs.resumeCursor == nil, _cells[pgs.i] == nil, pgs.y > 0.01, carried == 0, image.height > 0,
                       bottom > pgs.contentH + 0.01, _px(f.y) + _px(image.height + f.distanceBottom) <= pgs.contentH {
                        RuleTrace.hit("word-top-and-bottom-picture-past-the-foot-goes-with-its-paragraph-to-the-next-page")
                        _pg_newPage(&pgs, document)
                        onPage = pgs.y + _px(f.y)
                        top = onPage - _px(f.distanceTop); bottom = onPage + _px(image.height + f.distanceBottom)
                    }
                    guard bottom > 0.01, top < pgs.contentH - 0.01, !(mine && image.height <= 0) else { continue }
                    // (Its own paragraph keeps its place: the band is under
                    // what follows it, as the title over zh-6d402586's box.)
                    pgs.tableBands.append((top: top, bottom: bottom, owner: mine ? pgs.i : -1))
                    if mine, abs(f.y) < 0.01, f.distanceTop < 0.01 { pgs.topPinnedOwners.insert(pgs.i) }
                    pgs.pictureBands.append((top: top, bottom: bottom, owner: mine ? pgs.i : -1))
                    var moved: [PagePiece] = []
                    // (A hair above its own line, -0.9pt as in lo-eb12e7d4's 137pt picture: the
                    // line before it is not under the picture — Word sets it where it stood and
                    // the picture after it, at the paragraph's first place.)
                    let moveTop = mine && RichTextTheme.wordWindowsPages && f.y < -0.3 && f.y > -2 ? max(top, pgs.y) : top
                    while let last = _pages[pgs.page].last, last.paragraph < pgs.i, _cells[last.paragraph] == nil, !last.repeated,
                          last.pageY + (last.flowBottom - last.flowTop) > moveTop + 0.01 {
                        moved.insert(_pages[pgs.page].removeLast(), at: 0)
                        if let k = _allPieces.lastIndex(of: moved[0]) { _allPieces.remove(at: k) }
                        if last.pageY <= moveTop + 0.01 { break }
                    }
                    if !moved.isEmpty {
                        pgs.reordered = true
                        pgs.y = max(top, bottom)
                        pgs.deferredUnder = moved
                        _pg_placeDeferred(&pgs, document)
                    } else if !(mine && RichTextTheme.wordWindowsPages), pgs.y > top - 0.01, pgs.y < bottom {
                        // (Not its own paragraph, with the float at its top: the line goes under the
                        // float, the paragraph stays — LibreOffice's tdf137850, a text box wrapped
                        // top and bottom at offset 0, stands at the margin in Word's print, not
                        // under its own height.)
                        pgs.y = bottom
                    }
                }
            }
            // Under odd and even headers, a section that numbers its pages
            // afresh opens on its first number's side: where that number
            // is odd as the page before's was (or even as it was), Word
            // leaves a page blank, with no header or footer, between them.
            // Lab `sec` (zh-1a3c7aa0's package, Word for Windows,
            // 2026-10-14): after page "1" a section from 1 opens on the
            // third page, after "2" on the second; after "3" a section from
            // 1 opens a page later and one numbered on, or from 2, does not;
            // without `w:evenAndOddHeaders` none does.
            // (In columns the pages are virtual, a page being `_columns` of them: the
            // rule reads the physical page. dx2 9331dd51's title section, its
            // next one numbered from 91 after page 1, leaves Word's page 2 blank.)
            if theme.wordRules, document.evenAndOddHeaders, pgs.resumeCursor == nil, pgs.i > 0, pgs.page >= _columns,
               pgs.page % _columns == 0, _columns == 1 || RichTextTheme.sectionColumnsFlow,
               pgs.y < 0.01, _pages[pgs.page].isEmpty, pgs.i < _sectionOf.count, _sectionOf[pgs.i] != _sectionOf[pgs.i - 1],
               let first = _sectionNumberStart(_sectionOf[pgs.i], document),
               (first - _pageNumberOf(pgs.page / _columns - 1, document)) % 2 == 0 {
                _blankPages.insert(pgs.page / _columns)
                repeat { _pg_newPage(&pgs, document) } while pgs.page % _columns != 0
            }
            if endsSection { pgs.markOnPage = true }
            // (A paragraph under a table whose header was left off a page
            // for want of room stands as if it were there: its height still
            // counts, and the paragraph goes to the next page when it would
            // not fit under it — lo Cool16066: "END OF DOCUMENT" under the
            // 40-line row at page 2's top, 14pt of text with 169pt left, is
            // page 3's only line in Word's print.)
            if theme.wordRules, pgs.i > 0, _cells[pgs.i] == nil, pgs.resumeCursor == nil, pgs.y > 0.01, let before = _cells[pgs.i - 1],
               let head = pgs.omittedHeadHeight[before.table], pgs.y + head > pgs.contentH + 0.01 {
                _pg_newPage(&pgs, document)
            }
            // The document's final empty paragraph under a table that has
            // reached its third page goes to a page of its own, whatever room
            // is left (a table ending on its second page keeps it beside it):
            // Word's lab prints of lo-28f9b886 (amd-5 lab A).
            if theme.wordRules, RichTextTheme.wordWindowsPages, pgs.i > 0, pgs.i == document.paragraphs.count - 1, _cells[pgs.i] == nil,
               pgs.resumeCursor == nil, pgs.y > 0.01, document.paragraphs[pgs.i].text.isEmpty, let before = _cells[pgs.i - 1], _pg_headerRows(&pgs, document, before.table) > 0, let first = _tableFirstParagraph[before.table],
               // (… with repeated header rows over a quarter of the page: the lab's two, 213pt, made the table
               // reach its third page; the 90 long tables of the corpus with a one-line header keep it beside them.)
               case let headTop = _cells[first]?.rowTop ?? 0,
               (first ..< pgs.i).reduce(0.0, { acc, k in
                   guard let d = _cells[k], d.table == before.table, d.row < _pg_headerRows(&pgs, document, before.table) else { return acc }
                   return max(acc, d.rowTop + d.ownRowHeight - headTop)
               }) > pgs.contentH * 0.25,
               (0 ... pgs.page).filter({ pg in _pages[pg].contains(where: { _cells[$0.paragraph]?.table == before.table && !$0.repeated }) }).count >= 3 {
                _pg_newPage(&pgs, document)
            }
            // this paragraph, any kept run after it, and the start of
            // what follows them go to the next page together when this
            // page has no room for all of it.
            // The run is moved from its start only, and whole: a member
            // after the first stays with the one before it, so a run that
            // starts a page is set from there as it falls, however long
            // (zh-64044a1d's headings 3 and 4 all keep with the next,
            // from heading 1; capped at eight and weighed again at each
            // member, the run put one item on each page where Word fills
            // them). A run that starts lower goes over when it does not
            // fit what is left, though no page could hold it: Word sets
            // zh-64044a1d's "五、名詞定義" and its run of thirty items on
            // a new page under half a page of room.
            if theme.wordRules, pgs.resumeCursor == nil, pgs.y > 0.01, document.paragraphs[pgs.i].style.keepNext,
               // (A table's row whose text keeps with the next carries
               // the run through: bug65649's place-and-date table.)
               !(pgs.i > 0 && document.paragraphs[pgs.i - 1].style.keepNext) {
                // Word asks of a kept paragraph only that the first lines
                // of the next stand on its page; a page's foot that falls
                // inside a member's own lines breaks no keep. So the run
                // moves — from its first member, the keeps cascading back
                // — only where the foot falls at a member's end with the
                // next member's start (its first line; two, under widow
                // control; all of a short or kept-together paragraph; a
                // row) not fitting after it. zh-64044a1d: its headings 1
                // to 4 all keep, so every run reaches to the chapter's
                // end — Word fills page 72 with one, the foot falling in
                // the lines of an item, and sends another to page 63 from
                // half a page of room, the foot falling between two.
                // (Whether a member must stand on one page whole: kept
                // together, one line, or short under widow control.)
                func whole(_ k: Int) -> Bool {
                    let st = document.paragraphs[k].style
                    let lines = geometry(k).painter.computeLineMetrics()
                    return st.keepLines || lines.count <= 1 || (st.widowControl && !document.widowControlSuspended && lines.count <= 3)
                }
                func start(_ k: Int, trailing: Bool = false) -> Double {
                    if let c = _cells[k] {
                        // (A row that may part asks only for its first
                        // line in each cell: Word sets zh-64044a1d's
                        // "附件五" heading at page 88's foot with the
                        // first two lines of its form's five-line title
                        // row, and parts the row there.)
                        // (A header row never parts, so a kept heading asks for all of it: jpn-z22667840-bc5fb7's
                        // "5 国際基準との照合結果", 31pt of room under it and a 33pt header row, opens page 5 in Word's print.)
                        if theme.wordRules, let ts = document.tableStyles[c.table], ts.headerRow, c.row < ts.headerRowCount, c.ownRowHeight <= pgs.contentH + 0.01 {
                            RuleTrace.hit("word-kept-heading-asks-the-whole-header-row")
                            return c.ownRowHeight
                        }
                        guard theme.wordRules, document.tableStyles[c.table]?.rowsCantSplit.contains(c.row) != true,
                              !(document.tableStyles[c.table]?.rowsExactHeight.contains(c.row) == true && c.ownRowHeight <= pgs.contentH + 0.01) else { return c.ownRowHeight }
                        var need = 0.0
                        var j = k
                        while j < count, let d = _cells[j], d.table == c.table, d.row == c.row {
                            if j == k || _cells[j - 1]?.column != d.column {
                                let g = geometry(j)
                                let bottoms = Self._lineBottoms(g.painter)
                                // (A picture is its cell's first line whole:
                                // zh-64044a1d's flow charts stand alone in a
                                // table's first row under a run of kept
                                // headings, and Word takes "八、參考資料" and
                                // its two items to the chart's page; measured
                                // by the painter's first line the chart was
                                // a line tall, and the headings stayed behind.)
                                let firstLine = document.paragraphs[j].image != nil ? _heights[j] : (bottoms.first ?? _heights[j])
                                need = max(need, (g.textTop - g.top) + firstLine + d.pad.top + d.pad.bottom)
                            }
                            j += 1
                        }
                        return need > 0 ? min(need, c.ownRowHeight) : c.ownRowHeight
                    }
                    let st = document.paragraphs[k].style
                    let g = geometry(k)
                    let bottoms = Self._lineBottoms(g.painter)
                    // (All of it, but its space after, which may stand past
                    // the foot as under a line set on its own: zh-64044a1d's
                    // "二、適用範圍" run, thirteen kept paragraphs, ends in
                    // "(九)其他應變處理…", 27pt with its 9 after, and Word
                    // sets it at page 41's foot with 1.1pt short of that.)
                    // (A paragraph that opens with its own page break asks the page it follows for the
                    // break's line only, down to the baseline: the text after the break is on the next
                    // page. Word fits dx2 43e0fe21's empty heading and the break line that follows it
                    // 4.2pt past page 3's foot, and ours sent both on, a blank page 4.)
                    if let reach = _breakLineReach(st, g) { return reach }
                    if whole(k) {
                        // (A member the run's last one asks for, a line set on
                        // its own, may reach past the foot by the same
                        // overhang as one whose lines part there: zh-34a6519a's
                        // "3.2.2 防汛較大（Ⅲ級）事件" and the one line under it,
                        // 1.5-spaced on a grid of 15.6, end 1.9pt past p14's
                        // foot by their extra, and Word sets both there, p15
                        // opening with "（1）"; ours sent the heading on.)
                        var extra = 0.0
                        if trailing, bottoms.count <= 1, theme.wordRules, pgs.pageNotes.isEmpty, k < _overhang.count {
                            extra = _overhang[k]
                            if k < _lineOverhang.count, let last = _lineOverhang[k].last { extra = max(extra, last) }
                        }
                        return theme.wordRules ? min(_heights[k], (g.textTop - g.top) + (bottoms.last ?? _heights[k])) - extra : _heights[k]
                    }
                    let n = min(bottoms.count - 1, st.widowControl && !document.widowControlSuspended ? 1 : 0)
                    // (Its last line there may reach past the foot as it
                    // would set on its own — see the overhang below:
                    // zh-34a6519a's "5.2.3 防台风Ⅱ级应急响应" keeps with a
                    // 1.5-spaced paragraph whose first line ends 2.9pt past
                    // p28's foot by its extra, and Word sets both there;
                    // ours took the line's extra as room it needed and sent
                    // the heading on.)
                    var reach = theme.wordRules && pgs.pageNotes.isEmpty && k < _overhang.count ? _overhang[k] : 0
                    if theme.wordRules, pgs.pageNotes.isEmpty, k < _lineOverhang.count, n < _lineOverhang[k].count { reach = max(reach, _lineOverhang[k][n]) }
                    return (g.textTop - g.top) + bottoms[n] - reach
                }
                // (A run of ONE kept member and a one-line paragraph after it
                // is weighed as set: the heading's space before shared with the
                // paragraph above's space after is on the page once, and the
                // line may reach past the foot by its overhang. zh-34a6519a's
                // "3.2.2 防汛較大（Ⅲ級）事件", 6pt before over 8 after, and the
                // 1.5-spaced line under it end 1.9pt past p14's foot and stay in
                // Word's print. Longer runs keep the stricter sum: zh-64044a1d's
                // and zh-c34269bd's fall 28 and 44 points with either credit.)
                let sharedNow = pgs.i > 0 && _cells[pgs.i - 1] == nil ? min(pgs.y, max(0, _tops[pgs.i - 1] + _heights[pgs.i - 1] - top)) : 0
                func weigh(_ room: Double) -> Bool {
                var cum = 0.0
                var k = pgs.i
                var violated = false
                var ended = false   // the run ends with a section: nothing is kept across its break
                while k < count, _cells[k] == nil, document.paragraphs[k].style.keepNext {
                    // (A member that opens its own page ends the run: nothing before it is kept
                    // with it. dx2 4df3282e's "Service scenarios" stays at page 7's foot in Word's
                    // print, with "Technology assessment" (page break before) after it.)
                    if theme.wordRules, RichTextTheme.wordWindowsPages, k > pgs.i, document.paragraphs[k].style.pageBreakBefore || _pageBreak[k] { break }
                    if cum + _heights[k] <= room + 0.01 {
                        cum += _heights[k]
                        // (A member that ends a section ends the run: Word
                        // keeps nothing with what the next section begins
                        // with — zh-64044a1d's "(二)金湖鎮災害應變中心標準
                        // 作業程序" ends page 72 and its section, and the
                        // flow chart that opens the next stays there.)
                        if document.paragraphs[k].style.sectionXML != nil { ended = true; k += 1; break }
                        k += 1
                        continue
                    }
                    // (A first member that must stand whole and does not
                    // fit what is left would stay only by reaching past
                    // the foot, and the next member then cannot follow it:
                    // the run goes over. zh-64044a1d's "【後勤財務組】" heading,
                    // two kept lines 99pt with its space, has 89.4 under
                    // figure 6 on page 40; Word opens page 41 with it and
                    // "一、目的", ours kept it by its last line's overhang
                    // and sent "目的" on alone, and ran a page behind.)
                    // (Nor a whole first member that fits by its lines but not
                    // with its space after: the next member's start then
                    // has no room on the page, and the run goes over all
                    // the same. zh-64044a1d's "(七)上班上課情形", one 18pt
                    // line and 9 after under 25.9pt of room, opens page 29
                    // in Word's print with the five kept headings after
                    // it; ours kept it at page 28's foot alone.)
                    // (A later member that must stand whole and fits by its lines but not with its space
                    // after leaves the next member no room either: the run goes over. dx2 5c72dd63's
                    // "Hold dig opdateret" under the list beside the logo, 0.2pt short, with the
                    // paragraph after it, opens page 5 in Word's print with the chain.)
                    // (The run is measured as the flow places it, the space two neighbours share
                    // counted once: zh-64044a1d's thirteen kept members of style 3 (180 before and after)
                    // overlap by 18pt, and Word keeps them on page 44 where their plain sum overran.)
                    // (Only when no earlier member can split: Word breaks inside the latest one that can, keeping
                    // each member's last line with the next one's first. dx2 8714e66e's "High Intensity" run,
                    // 9pt over by its flow, splits "ECC Report 272" across pages 3 and 4 and keeps the heading with it.)
                    violated = k > pgs.i ? cum + start(k) > room + 0.01
                        || (theme.wordRules && RichTextTheme.wordWindowsPages && _cells[k] == nil && k + 1 < count && whole(k) && document.paragraphs[k].style.sectionXML == nil
                            && _tops[k] + _heights[k] - _tops[pgs.i] > room + 0.01
                            && (pgs.i..<k).allSatisfy { whole($0) })
                        : _cells[pgs.i] == nil && whole(pgs.i) && _heights[pgs.i] <= pgs.contentH + 0.01
                            && (start(pgs.i) > room + 0.01 || (pgs.i + 1 < count && document.paragraphs[pgs.i].style.sectionXML == nil))
                    break
                }
                if !violated, !ended, k < count, k > pgs.i, (_cells[k] != nil || !document.paragraphs[k].style.keepNext) {
                    let single = k == pgs.i + 1 && _cells[k] == nil && !document.paragraphs[k].style.keepNext
                    // (The notes of the kept members stand at this page's foot with them: Word's print of c2104d44 sends
                    // a heading with a footnote mark, kept with its paragraph, to the next page where the note
                    // and the paragraph's first line do not both fit under it.)
                    var noteRoom = 0.0
                    if theme.wordRules, pgs.notesOn, RichTextTheme.wordWindowsPages, !pgs.slotNotes {
                        var seen: [Int] = []
                        for m in pgs.i ..< k {
                            for id in _footnotes(in: m, document) where !pgs.pageNotes.contains(id) && !seen.contains(id) {
                                guard let note = _note(id, width: _pg_noteWidth(&pgs, document), document) else { continue }
                                if seen.isEmpty && pgs.pageNotes.isEmpty { noteRoom += _note(-1, width: _pg_noteWidth(&pgs, document), document)?.height ?? 0 }
                                noteRoom += note.height
                                seen.append(id)
                            }
                        }
                        if noteRoom > 0 { RuleTrace.hit("word-kept-heading-counts-its-notes") }
                    }
                    violated = cum + start(k, trailing: single) + noteRoom > room + (single ? sharedNow : 0) + 0.01
                    // (Where the last kept member can part, the page's foot may fall inside its lines: Word keeps only its
                    // last line with the paragraph after, so the member parts and the run stands on if the members before it
                    // and its own first lines fit. gv-95df15ab58's four-line "The only exceptions…" heading, 128 short of
                    // the paragraph's start, sets two lines on page 8 and two on page 9 in Word's print.)
                    if violated, theme.wordRules, RichTextTheme.wordWindowsPages, k - 1 >= pgs.i, _cells[k - 1] == nil, _cells[k] == nil, !whole(k - 1),
                       cum - _heights[k - 1] + start(k - 1) + noteRoom <= room + 0.01 {
                        RuleTrace.hit("word-kept-last-member-parts-at-the-foot")
                        violated = false
                        let bt = Self._lineBottoms(geometry(k - 1).painter)
                        let lastLine = bt.count > 1 ? bt[bt.count - 1] - bt[bt.count - 2] : 0
                        pgs.tailHold = (paragraph: k - 1, page: pgs.page, give: max(cum + start(k, trailing: single) + noteRoom - room, lastLine))
                    }
                }
                    return violated
                }
                pgs.tailHold = nil
                var violated = weigh(pgs.contentH - pgs.y)
                if violated {
                    pgs.tailHold = nil
                    _pg_newPage(&pgs, document)
                    // (The run weighed again where it landed: sent into a
                    // column that cannot hold it either, it goes on to the
                    // next page, as in Word's print of lab col2flow, where
                    // "目录" and the two kept empties above it open page 3
                    // and ours left 152pt of column 1 empty above them.)
                    if theme.wordRules, _columns > 1, pgs.page % _columns != 0, weigh(pgs.contentH - pgs.y) {
                        while pgs.page % _columns != 0 { _pg_newPage(&pgs, document) }
                    }
                }
            }
            // The space it shares with the paragraph above (`_sharedSpace`)
            // is on the page once, as it is in the flow.
            if pgs.i > 0, _cells[pgs.i - 1] == nil, pgs.y > 0.01, pgs.resumeCursor == nil {
                pgs.y -= min(pgs.y, max(0, _tops[pgs.i - 1] + _heights[pgs.i - 1] - top))
            }
            // (Whether a page's head takes this paragraph's space before
            // off — see where the paragraph is set.)
            // (A box's top line and the room under it stay: lab bdr2, b2, BBB's 40pt before
            // goes at the page's top and its box opens there, text 7pt under it.)
            let boxRoom = theme.wordRules && RichTextTheme.wordWindowsPages && (document.compatibilityMode ?? 12) >= 14 && (document.paragraphs[pgs.i].style.continuesParagraph || document.paragraphs[pgs.i].style.pageBreakInline || !_pageBreak[pgs.i] || (document.paragraphs[pgs.i].style.pageBreakBefore && !document.paragraphs[pgs.i].style.breakEndsPrevious) || _afterBareBreak(pgs.i, document)) && !_bordersJoin(pgs.i - 1, pgs.i, document) && !_emptyBreakFragment(pgs.i, document)
                ? document.paragraphs[pgs.i].style.borders?.top.map { _px($0.space + Self._ruleRoom($0.style, $0.width)) } ?? 0 : 0
            let lead = pgs.i < _floatPush.count ? max(0, _spaceBefore[pgs.i] - _floatPush[pgs.i] - boxRoom) : 0
            var leavesLead = false
            if theme.wordRules, lead > 0.01, (pgs.resumeCursor ?? top) <= top + 0.01 {
                let st = document.paragraphs[pgs.i].style
                // (A section's first paragraph that opens with a column break
                // loses it all the same: zh-b8de3ae2 p15, 3pt, compat 15.)
                let newSection = pgs.i > 0 && document.paragraphs[pgs.i - 1].style.sectionXML != nil && !(st.columnBreak && (document.compatibilityMode ?? 12) >= 15)
                let ownBreak = _pageBreak[pgs.i] && !st.pageBreakInline && !st.breakEndsPrevious
                // (One its own page break opens keeps it before 2013's layout
                // only: lab brk2 (Word for Windows) — zh-ae2dd08d's heading
                // keeps its 6pt in mode 12 and drops it in 15, and so does
                // zh-604e21e5's "附件2：報告書內容大綱" (mode 15, 9pt) in its
                // fresh print, where ours stood p30 9pt low.)
                let inlineKeeps = st.pageBreakInline && !(RichTextTheme.wordWindowsPages && (document.compatibilityMode ?? 12) >= 15)
                leavesLead = !newSection && !inlineKeeps && !(ownBreak && (document.compatibilityMode ?? 12) < 15)
                // (The mark of a paragraph that ended in its page break,
                // where the file splits break and mark: its line on the new
                // page keeps the 6pt before — lo tdf151704's page 2 opens
                // at 20.4 in Word's print, the table 32.7, where ours
                // stood 6.3pt high.)
                if leavesLead, pgs.page > 0, !newSection, pgs.y < 0.01, _headerWrapHoldsTop(page: pgs.page, document) {
                    leavesLead = false; RuleTrace.hit("word-header-wrap-holds-page-top-heading-space-before")
                }
                if leavesLead, st.markFollowsBreak { leavesLead = false; RuleTrace.hit("word-split-break-mark-keeps-its-space-before") }
            }
            // How much of it a page's head takes off, for where a line
            // under a float first stands (below): zh-27a874b7's chart
            // anchor opens a section under the last one's 9pt after, so
            // its 9pt before goes and its line stands over the chart;
            // zh-d62da4dd's, under none, keeps it, and the line goes
            // under (lab t3d, Word for Windows).
            var headSkip = 0.0
            if theme.wordRules, pgs.y < 0.01, pgs.page > 0, lead > 0.01, (pgs.resumeCursor ?? top) <= top + 0.01 {
                if leavesLead { headSkip = pgs.pageFresh ? lead : 0 }
                else if pgs.i > 0, _cells[pgs.i - 1] == nil, !document.paragraphs[pgs.i].style.markFollowsBreak { headSkip = min(lead, _spacing(pgs.i - 1, document).after) }
            }
            // Pictures that text wraps round (2026-10-14, zh-37b6536f's
            // photographs, from Word's print):
            // - a paragraph with less than an em beside the pictures over
            //   its top, either side, goes below them — empty ones too: a
            //   row of two photos across the column has the next anchor
            //   under it, where beside one narrower photo eleven empty
            //   paragraphs stand in the 43pt left over;
            // - a paragraph whose own picture would run past the page's
            //   foot goes to the next page with it;
            // - a picture that would lie over one already on the page
            //   stands to its right (the second of two photos of a row,
            //   anchored 10pt left of the column, is drawn beside the
            //   first).
            var pictureProbe: ((Double, Double) -> Double?)? = nil
            if theme.wordRules, pgs.resumeCursor == nil, _cells[pgs.i] == nil {
                let column = _flowWidth(pgs.i)
                let gap = _px(9)
                // (An empty paragraph — or one of floating objects' places
                // alone — asks half an em: zh-d62da4dd's empty paragraphs
                // stand in the 10.95pt a tight-wrapped chart leaves at the
                // column's left in Word's print (12pt); zh-37b6536f's under
                // its row of photos, which leaves 5.0, go under it.)
                let bare = document.paragraphs[pgs.i].text.unicodeScalars.allSatisfy { $0.value == 0xFFFC || $0 == " " }
                // (A list paragraph's first line asks its label's room as well,
                // and starts at the label: zh-f2ca3070's "二、 共同工作空間",
                // its label slot 27pt, starting 21pt in, has 24pt left of a
                // tight-wrapped price list and 38 right of it, and Word sets
                // it under the picture — a line that meets the picture's top
                // 5pt down, its own top above it.)
                let listed = !bare && RichTextTheme.wordWindowsPages ? _listIndents(document.paragraphs[pgs.i], document) : nil
                let label = listed.map { _px($0.hanging) } ?? 0
                let lineStart = listed.map { max(0, _px($0.left - $0.hanging)) } ?? 0
                var em = _px(document.paragraphs[pgs.i].runs.first?.style.fontSize ?? theme.fontSize) * (bare ? 0.5 : 1) + label
                // (A line of text needs its first unbreakable piece to fit the strip: Word's print
                // (lab ebe-strip) sends "Probe text line" under pictures that leave 17.6 and 22 pt
                // although the empty line stands in the 22.)
                if !bare, RichTextTheme.wordWindowsPages, let r0 = document.paragraphs[pgs.i].runs.first {
                    var piece = ""
                    for u in document.paragraphs[pgs.i].text.unicodeScalars {
                        if u.value == 0xFFFC { continue }
                        if u == " " || u == "\t" || u == "\n" { if piece.isEmpty { continue }; break }
                        piece.unicodeScalars.append(u)
                        if u.value >= 0x2E80 || u == "-" || u == "/" { break }
                    }
                    if !piece.isEmpty {
                        let st = theme.textStyle(for: r0.style, in: document.paragraphs[pgs.i].style, normal: document.styles[RichNamedStyle.normalId]?.char, scale: 1)
                        var need = _px(_wordWidth(st, piece)) + label
                        // (A piece wider than the whole column breaks by character wherever it stands, so it asks the strip for one
                        // character only: sa1 62904a12's 100 underscores stand beside the picture in Word's print, not under it.)
                        if need > column, let c = piece.first { need = _px(_wordWidth(st, String(c))) + label }
                        em = max(em, need)
                    }
                }
                // (Over any of the line, not only its top: an empty
                // anchor's line that a photo starts 16pt down went under
                // the photo in Word's print.)
                func noRoom(at at: Double, height: Double = 0, _ extra: [(top: Double, bottom: Double, left: Double, right: Double)]) -> Double? {
                    let over = (pgs.bands + pgs.fixedBands + extra).filter { $0.top < at + max(0.02, height) - 0.01 && $0.bottom > at + 0.01 }
                    guard !over.isEmpty else { return nil }
                    // The widest stretch of the column no picture covers.
                    var spans = over.map { (max(0, $0.left - gap), min(column, $0.right + gap)) }.sorted { $0.0 < $1.0 }
                    var widest = 0.0, edge = lineStart
                    for s in spans { widest = max(widest, s.0 - edge); edge = max(edge, s.1) }
                    widest = max(widest, column - edge)
                    spans.removeAll()
                    return widest < em ? over.map(\.bottom).min() : nil
                }
                pictureProbe = { at, height in noRoom(at: at, height: height, pgs.pictureBands.filter { $0.owner != pgs.i }.map { (top: $0.top, bottom: $0.bottom, left: 0, right: column) }) }
                var guardSteps = 0
                // (Word tries the line where it first stood, then a step
                // down at a time — its line less the grid's half of the
                // room under the text, and its space before — and takes
                // the first try whose top is clear of the float's foot:
                // lab t3d (windows-1, Word for Windows), zh-27a874b7's
                // title "圖1" (16pt bold JhengHei, single, an 18pt grid),
                // first at 108, stands at 108 + k x 31.84 — 299.1, 330.9,
                // 330.9, 330.9, 362.7 as the chart's foot moves 298.8 to
                // 334.8 — (36 + 27.66) / 2 a step; ours set it at the foot.
                // The half is the face of its first characters', not the
                // smallest on the line. Not with a push of its own. Word
                // for Windows' lines only: see `pushUnder`.)
                // (An empty anchor line of a multiple above one, whose own picture is wrapped square from the
                // paragraph, is sent under an earlier picture by the anchor run below, its own picture kept where
                // the paragraph stood: 9bde52's second chart, 437 in Word's print, stood on the next page.)
                let keepsOwnPicture = theme.wordRules && RichTextTheme.wordWindowsPages && _anchorsOnly(pgs.i, document)
                    && document.paragraphs[pgs.i].style.lineSpacing > 1.001 && document.paragraphs[pgs.i].style.lineHeightPoints == nil
                    && document.paragraphs[pgs.i].image?.float.map { $0.wraps && !$0.takesRoom && !$0.bandsPage && $0.verticalFrom == "paragraph" } == true
                if theme.wordRules, !keepsOwnPicture, pgs.i < _floatPush.count, _floatPush[pgs.i] < 0.01, noRoom(at: pgs.y, []) != nil,
                   let line = Self._lineBottoms(geometry(pgs.i).painter).first,
                   case let step = lead + line - _firstLineGridHalf(pgs.i, document), step > 1 {
                    var t = pgs.y + lead - headSkip
                    while let below = noRoom(at: t, []), guardSteps < 20 {
                        t += max(1, ((below - t) / step - 0.001).rounded(.up)) * step
                        guardSteps += 1
                    }
                    pgs.y = max(pgs.y, t - lead)
                } else {
                    // (In Word for Windows, over any of the first line: zh-e51c31a7's
                    // "以下欄位由交通部填寫" starts 1.3pt above the foot-wide
                    // form box (外框1, 511pt, wrapped square, 14.35pt under its
                    // anchor's top) and stands under the box in Word's print,
                    // its table after it; ours set it under the box's top, the
                    // two drawn over each other. Word for Mac sets it there, as
                    // ours did.)
                    // (From Word 2013's layout only the text of a multiple's line meets a picture, not its extra:
                    // lab pwsplit, a picture's top at the text's foot leaves the line over it.)
                    func textOnlyExtra(_ line: Double) -> Double {
                        let st = document.paragraphs[pgs.i].style
                        return RichTextTheme.wordWindowsPages && (document.compatibilityMode ?? 12) >= 15 && st.lineSpacing > 1.001
                            && st.lineHeightPoints == nil ? line * (1 - 1 / st.lineSpacing) : 0
                    }
                    let reach = RichTextTheme.wordWindowsPages
                        ? (Self._lineBottoms(geometry(pgs.i).painter).first.map { $0 + (geometry(pgs.i).textTop - geometry(pgs.i).top) - textOnlyExtra($0) } ?? 0) : 0
                    // (A list paragraph's whole first line meets the picture, and
                    // steps a line and its space before at a time, as Word does:
                    // zh-f2ca3070's heading, first at 285, stands at 376.7 under a
                    // picture ending 361.8, 4 steps of 23.)
                    let firstHeight = label > 0 ? (Self._lineBottoms(geometry(pgs.i).painter).first ?? 0) : 0
                    if label > 0, firstHeight + lead > 1 {
                        let step = firstHeight + lead
                        // (Word 2010's mode: a list item whose later lines would reach a picture that leaves no room beside it
                        // goes under the picture whole, its first line clear of it or not: lab pic-wrap c14, a 509pt square
                        // picture, the item's first line 4pt above it, stands at the picture's foot with the lines after it.)
                        let reachAll = firstHeight - textOnlyExtra(firstHeight)
                        while let below = noRoom(at: pgs.y + lead, height: reachAll, []), guardSteps < 20 {
                            pgs.y += max(1, ((below - pgs.y - lead) / step - 0.001).rounded(.up)) * step
                            guardSteps += 1
                        }
                    } else if !keepsOwnPicture {
                        let stoodAt = pgs.y
                        let topWasInBand = noRoom(at: stoodAt, []) != nil || noRoom(at: stoodAt + lead, []) != nil
                        // (A line that meets a tight or through box's band goes down a whole line at a time from where
                        // it stood, to the first try whose top is clear of the band's foot, as in the first branch:
                        // Word's print of lab b80-step stands a 12pt title 15.84pt lower each time the box's foot
                        // passes the line's grid, not 3.6pt under the foot.)
                        let lineStep = (Self._lineBottoms(geometry(pgs.i).painter).first ?? 0) / (document.paragraphs[pgs.i].style.lineHeightPoints != nil ? 1 : max(1, document.paragraphs[pgs.i].style.lineSpacing))
                        while let below = noRoom(at: pgs.y, height: reach, []), guardSteps < 20 {
                            if RichTextTheme.wordWindowsPages, lineStep > 1, pgs.tightBandBottoms.contains(where: { abs($0 - below) < 0.02 }) {
                                pgs.y += max(1, ((below - pgs.y) / lineStep - 0.001).rounded(.up)) * lineStep
                            } else { pgs.y = below }
                            guardSteps += 1
                        }
                        // (What meets the box is the paragraph, its space before
                        // and all, and what stands clear of it is the LINE: Word's
                        // print of lo-61f8f967 (para-upper-margin-fly-intersect,
                        // 28.35pt before) sets the second paragraph's line at the
                        // wrapSquare box's foot, 172 (170.25 and the line's ascent),
                        // its space before overlapping the box; ours set it that
                        // far again lower, at 199.)
                        if theme.wordRules, RichTextTheme.wordWindowsPages, pgs.y > stoodAt + 0.01, lead > 0.01, topWasInBand {
                            RuleTrace.hit("word-box-pushed-paragraph-stands-its-line-at-the-foot")
                            pgs.y = max(stoodAt, pgs.y - lead)
                        }
                    }
                }
                // (A table placed down the page keeps the whole of a line
                // off it, not only the line's top: zh-10eab555's contents
                // line 17, which would reach into the issuing table, goes
                // under it — and so to page 3 — in Word's print.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, !pgs.narrowBands.isEmpty, _cells[pgs.i] == nil, document.paragraphs[pgs.i].image.map({ $0.float != nil }) ?? true {
                    let q = document.paragraphs[pgs.i]
                    let size = _px(q.runs.first?.style.fontSize ?? theme.fontSize)
                    let opens = q.text.first.map { "（(【《「『〈［｛".contains($0) } ?? false
                    // (An empty paragraph's line, beside pictures of an earlier paragraph, needs a strip of about 20pt, whatever its size: Word's
                    // prints of lab ebe-ls, the 11pt mark's line pushed under at a 19pt strip and kept at 20pt, and a 16pt one kept at 22pt.)
                    let unit = q.text.isEmpty ? _px(20) : size * (opens ? 2 : 1)
                    let first = q.style.indentLeft + max(0, firstLineIndent(q, document))
                    let lineBottoms = Self._lineBottoms(geometry(pgs.i).painter)
                    let step = (lineBottoms.first ?? _heights[pgs.i]) + (geometry(pgs.i).textTop - geometry(pgs.i).top)
                    var guardNarrow = 0
                    let noGrid = RichTextTheme.wordWindowsPages && _grid(pgs.i, document).pitch == nil
                    while step > 0.5, guardNarrow < 40,
                          let band = pgs.narrowBands.first(where: { $0.owner < pgs.i && $0.top < pgs.y + step - 0.01 && $0.bottom > pgs.y + 0.01 && $0.left - _px(first) < unit }) {
                        RuleTrace.hit("word-line-with-no-room-beside-a-centred-picture-stands-under-it")
                        // (Without a line grid Word lands the pushed line exactly at the pictures' foot, not a step of its own height
                        // past it: dx2 es ebe45609's Símbolos line, 711.70 in Word's print; with a grid the steps stay, 817e3a79.)
                        if noGrid { pgs.y = max(pgs.y, band.bottom) } else {
                            pgs.y += max(1, ((band.bottom - pgs.y) / step - 0.001).rounded(.up)) * step
                        }
                        guardNarrow += 1
                    }
                }
                var pushedByTableBand = false
                if !pgs.tableBands.isEmpty {
                    // The lower half of grid leading is outside the text's
                    // collision extent. In 291f's page-anchored table controls,
                    // the 36pt-grid anchor still stands above an 87.95pt table:
                    // its glyphs end before the table although the grid does not.
                    // Explicit line heights retain their stated extent.
                    // Use every face on this line, as at a page foot. Taking
                    // only the first run's half lets a later, larger face
                    // overlap the table; mixed 12/24pt controls rule that out.
                    // Keep multiline paragraphs on their existing path until
                    // later lines can be flowed around these page-wide bands.
                    let style = document.paragraphs[pgs.i].style
                    let lineBottoms = Self._lineBottoms(geometry(pgs.i).painter)
                    let gridHalf = lineBottoms.count == 1 && style.lineHeightPoints == nil
                        && style.eastAsian["w:snapToGrid"] != "0" && _grid(pgs.i, document).pitch != nil
                        && pgs.i < _overhang.count ? _overhang[pgs.i] : 0
                    // (A paragraph that anchors a float of its own stands its line
                    // by the line alone: its box reaches down over the float, and
                    // the float is not a text line to keep off an earlier band —
                    // lo's c4c60fcb, a chart group anchored in an empty line above
                    // a text box's band, went to the next page.)
                    let ownsBand = pgs.tableBands.contains { $0.owner == pgs.i }
                    let lineFull0 = (lineBottoms.first.map { $0 + (ownsBand ? 0 : geometry(pgs.i).textTop - geometry(pgs.i).top) } ?? _heights[pgs.i]) - gridHalf
                    // (From Word 2013's layout only the text of a multiple's line meets a picture's band, not its extra: lab pwsplit, c15 top and bottom.)
                    var textOnlyCut = 0.0
                    if theme.wordRules, RichTextTheme.wordWindowsPages, !ownsBand, (document.compatibilityMode ?? 12) >= 15, style.lineSpacing > 1.001,
                       style.lineHeightPoints == nil, let first = lineBottoms.first, !document.paragraphs[pgs.i].text.isEmpty {
                        textOnlyCut = first * (1 - 1 / style.lineSpacing)
                    }
                    let line = lineFull0
                    let yBeforeBands = pgs.y
                    let blankBeside = !pgs.stripBandTops.isEmpty && document.paragraphs[pgs.i].image == nil && _cells[pgs.i] == nil
                        && !document.paragraphs[pgs.i].text.contains { $0 != " " }
                    // (An empty anchor line whose own picture, wrapped top and bottom, starts at the paragraph's top is set
                    // under it, its space before kept and added: Word's print, lab tbempty3/4 — the line of 14.7pt at the
                    // picture's foot plus its before, 0 to 18pt; sa1 c4f2b4bd's title stood 23pt too high.)
                    let ownBandPushes = theme.wordRules && RichTextTheme.wordWindowsPages && ownsBand && pgs.topPinnedOwners.contains(pgs.i) && _anchorsOnly(pgs.i, document)
                        && _cells[pgs.i] == nil && pgs.resumeCursor == nil
                    while let band = pgs.tableBands.first(where: { band in
                        let reach = line - (textOnlyCut > 0 && pgs.pictureBands.contains(where: { $0.top == band.top && $0.bottom == band.bottom && $0.owner == band.owner }) ? textOnlyCut : 0)
                        return (band.owner != pgs.i || (ownBandPushes && abs(band.top - pgs.y) < 0.5)) && band.top < pgs.y + reach - 0.01 && band.bottom > pgs.y + 0.01
                        && !(blankBeside && pgs.stripBandTops.contains(band.top)) }), guardSteps < 40 {
                        if textOnlyCut > 0 { RuleTrace.hit("word-multiple-line-meets-a-picture-by-its-text-only") }
                        // (In a column that is not the last, what meets a picture wrapped top and
                        // bottom that an earlier paragraph of text anchors in the column goes on in the
                        // next column, not under the picture: lab f43/g43 (Word for Windows,
                        // lo-eb12e7d4's p13) — 4.3 stands at column 2's top with the picture
                        // up to 72pt higher and 95pt of column 1 free under it, and a line of
                        // 4.2 the picture would be over goes with it.)
                        if theme.wordRules, RichTextTheme.wordWindowsPages, _columns > 1, !RichTextTheme.sectionColumnsFlow || _columnsOf(paragraph: pgs.i) > 1, pgs.page % _columns < _columns - 1,
                           band.owner >= 0, band.owner < pgs.i, !_anchorsOnly(band.owner, document), pgs.resumeCursor == nil, pgs.y > 0.01 {
                            RuleTrace.hit("word-column-text-meeting-a-band-goes-to-the-next-column")
                            _pg_newPage(&pgs, document)
                            break
                        }
                        pgs.y = band.bottom; guardSteps += 1
                        if band.owner < 0 { pushedByTableBand = true }
                    }
                    if pushedByTableBand { pgs.y -= _tableBandSharedSpace(pgs.i, document) }
                    if theme.wordRules, pgs.y > yBeforeBands + 0.01, _cells[pgs.i] == nil { pgs.bandPushLast = pgs.i; pgs.bandPushDelta = pgs.y - yBeforeBands; pgs.bandPushPage = pgs.page; pgs.bandPushTop = yBeforeBands - lead }
                    // (A paragraph, with text or not, that sets a box top and bottom from itself and goes under an earlier
                    // box's band keeps its box at the place it stood before: Word's lab ttb 1-4 print the second
                    // box at 97 + 300, the line at 344 under the first; ours drew it at 344 + 300.)
                    if theme.wordRules, RichTextTheme.wordWindowsPages, ownsBand, pgs.y > yBeforeBands + 0.01, _cells[pgs.i] == nil {
                        for image in (pgs.i < _floatImages.count ? _floatImages[pgs.i].map { [$0] } ?? [] : []) + (pgs.i < _inline.count ? _inline[pgs.i] : []) {
                            guard let f = image.float, f.bandsPage, f.verticalFrom == "paragraph", f.verticalAlign == nil else { continue }
                            RuleTrace.hit("word-empty-paragraph-under-a-band-keeps-its-own-box-at-the-unpushed-anchor")
                            _floatShiftY[image.id] = -(pgs.y - yBeforeBands)
                        }
                    }
                }
                // (Not for an empty paragraph that only ends a section: it
                // takes no room, and stays on the full page, as in Word's
                // print — zh-12c4f07a's contents fill page 2 to its last
                // empty line, and a page opened at their section break took
                // their 56.7pt margins where Word's page 3 has the next
                // section's 90. A page the break itself opens, blank, is
                // still that section's: zh-7488a70f's page 2.)
                let ender = theme.wordRules && _heights[pgs.i] == 0 && document.paragraphs[pgs.i].style.sectionXML != nil
                    && document.paragraphs[pgs.i].cell == nil && document.paragraphs[pgs.i].text.isEmpty
                // (A paragraph of a page-anchored frame that began on this page stands where
                // the frame puts it, past the foot or not: the 4th line of OGC's cover block,
                // frame y 693pt, text foot 720pt, stays on page 1 in Word's print; xd 8948a622.)
                let inPlacedFrame = theme.wordRules && document.paragraphs[pgs.i].style.frameXML != nil && pgs.frameReturn?.page == pgs.page
                if inPlacedFrame, pgs.y > pgs.contentH - 0.01 { RuleTrace.hit("word-frame-continuation-stays-on-its-page-past-the-foot") }
                if pgs.y > pgs.contentH - 0.01, !ender, !inPlacedFrame { _pg_newPage(&pgs, document) }
                // (An empty paragraph at a column's foot, the paragraph after it too long for what
                // is left, and a table next whose cell holds a picture wrapped top and bottom: Word's
                // print carries the empty paragraph to the top of the next column with them — lab
                // ef4/ef5, from lo-eb12e7d4's page 14, where it moved only with that picture, not a
                // square-wrapped or an inline one, and the column after it stood 17pt lower. Only seen with the table
                // exactly two paragraphs on, and the paragraph between them: the labs did not try a gap of two or a keep-with-next chain.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, _columns > 1, pgs.y > 0.01, !ender, _cells[pgs.i] == nil,
                   document.paragraphs[pgs.i].text.isEmpty, document.paragraphs[pgs.i].image == nil, document.paragraphs[pgs.i].inlineImages.isEmpty,
                   pgs.i + 2 < count, _cells[pgs.i + 1] == nil, !document.paragraphs[pgs.i + 1].text.isEmpty, _cells[pgs.i + 2] != nil,
                   pgs.contentH - (pgs.y + _heights[pgs.i]) < _heights[pgs.i + 1] {
                    let table = _cells[pgs.i + 2]!.table
                    var topAndBottom = false
                    var k = pgs.i + 2
                    while k < count, let cell = _cells[k], cell.table == table, cell.row == 0 {
                        for image in Array(document.paragraphs[k].inlineImages.inOrder) + (document.paragraphs[k].image.map { [$0] } ?? []) {
                            if let float = image.float, float.takesRoom || float.bandsPage, !float.wraps { topAndBottom = true }
                        }
                        k += 1
                    }
                    if topAndBottom {
                        RuleTrace.hit("word-empty-paragraph-before-a-top-and-bottom-picture-table-goes-with-it-to-the-next-column")
                        _pg_newPage(&pgs, document)
                    }
                }
                var mine = _wrapBoxes(pgs.i)
                // (Word's print of lab pic-wrap, c14 and sa2 78bf1be7: a 509pt picture, 6.5pt in from the margin of a 522pt
                // column, wrapped square, from the margin; the list items after it go under it whole, not over it. A picture
                // with 26pt at its side keeps text beside it there, so the test is for less than that at each side.)
                if theme.wordRules, RichTextTheme.wordWindowsPages {
                    var own: [ImageAttachment] = []
                    if pgs.i < _floatImages.count, let image = _floatImages[pgs.i] { own.append(image) }
                    if pgs.i < _inline.count { own += _inline[pgs.i] }
                    for image in own {
                        guard let float = image.float, float.wraps, !float.wrapsTight, !float.takesRoom, !float.bandsPage, float.verticalAlign == nil,
                              float.heightShare == nil, float.verticalFrom == "margin", float.horizontalFrom == "margin", float.wrapSide == nil,
                              !image.data.isEmpty || image.outline != nil, _cells[pgs.i] == nil else { continue }
                        let r = _floatRect(float, image, geometry(pgs.i), pgs.i)
                        guard max(0, r.left) < _px(24), _flowWidth(pgs.i) - r.right < _px(24) else { continue }
                        let t = _px(float.y)
                        let line = image.data.isEmpty ? _px(float.effectBottom) : 0
                        fixedBandsAdd: do {
                            pgs.fixedBands.append((t - _px(float.distanceTop), t + _bodyBoxHeight(image, document) + line + _px(float.distanceBottom), r.left, r.right))
                        }
                        RuleTrace.hit("word-wide-margin-square-picture-takes-the-column-after-its-anchor")
                    }
                }
                for box in mine { if let dy = _floatShiftY[box.id] { _floatShiftY[box.id] = nil; let r = box.rect; mine = mine.map { $0.id == box.id ? ($0.id, Rect.fromLTWH(r.left, r.top - dy, r.width, r.height), $0.above, $0.below) : $0 } } }
                // (A box of the paragraph's own that the page fixes — a text box
                // wrapped square, placed from the page or its margin, the
                // full column wide — and that the paragraph's first line
                // meets, space before and all, sends the paragraph under it,
                // and its space before is set again there: lo tdf116486's
                // "TEST", 175pt before, its line 274 to 285 and the box 283
                // to 299, stands at 474 in Word's print, 299 + 175; ours
                // stood at 274, over the box's own text.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, _anchorsOnly(pgs.i, document) == false,
                   !document.paragraphs[pgs.i].text.isEmpty, lead > 0.01 {
                    var fixed: [(top: Double, bottom: Double, left: Double, right: Double)] = []
                    var own: [ImageAttachment] = []
                    if pgs.i < _floatImages.count, let image = _floatImages[pgs.i] { own.append(image) }
                    if pgs.i < _inline.count { own += _inline[pgs.i] }
                    for image in own {
                        guard let float = image.float, float.wraps, !float.takesRoom, float.verticalAlign == nil, float.heightShare == nil,
                              float.verticalFrom == "page" || float.verticalFrom == "margin", float.horizontalFrom != "character",
                              image.textBox != nil || !image.data.isEmpty || image.outline != nil else { continue }
                        let r = _floatRect(float, image, geometry(pgs.i), pgs.i)
                        let t = _px(float.y) - (float.verticalFrom == "page" ? _pxMarginTop(pgs.page) : 0)
                        // (A line shape of no height, wrapped square from the margin across the column: the line under it is
                        // sent below its stroke, effect extent and all. aab5ab3d's cover rule, Word 10.5pt lower.)
                        let line = image.outline != nil && image.data.isEmpty && image.textBox == nil ? _px(float.effectBottom) : 0
                        fixed.append((t - _px(float.distanceTop), t + _bodyBoxHeight(image, document) + line + _px(float.distanceBottom), r.left, r.right))
                    }
                    if !fixed.isEmpty {
                        let reach = Self._lineBottoms(geometry(pgs.i).painter).first.map { $0 + (geometry(pgs.i).textTop - geometry(pgs.i).top) } ?? 0
                        let kept = pgs.bands
                        pgs.bands = []
                        var steps = 0
                        while let below = noRoom(at: pgs.y, height: reach, fixed), steps < 20, below > pgs.y + 0.01 {
                            pgs.y = below; steps += 1
                            RuleTrace.hit("word-own-fixed-box-sends-its-paragraph-under")
                        }
                        pgs.bands = kept
                    }
                }
                if !mine.isEmpty {
                    // (On Windows Word, a paragraph-anchored wrapping float positioned strictly below
                    // its anchor paragraph — e.g. a cover logo placed in the bottom margin — stays on
                    // its page up to the physical page edge, mirroring Word's floating-table rule; a
                    // float overlapping or above its paragraph still moves when its foot passes
                    // `contentH`: sa1 7770c637, dx2 b5237383 vs zh-f47b8a74, d618a7eb, zh-06c46ba9.)
                    let physical = pgs.page / _columns
                    let pageBottom = _px(pageSetup(forPage: physical).height) - _pxMarginTop(physical)
                    let paraFoot = top + _heights[pgs.i]
                    if pgs.y > 0.01, mine.contains(where: {
                        guard _pinnedFloats[$0.id]?.page != pgs.page else { return false }
                        let limit = theme.wordRules && RichTextTheme.wordWindowsPages && $0.rect.top > paraFoot + 0.5 ? pageBottom : pgs.contentH
                        return pgs.y + $0.rect.bottom - top > limit + 0.5
                    }) { _pg_newPage(&pgs, document) }
                    var placed: [(top: Double, bottom: Double, left: Double, right: Double)] = []
                    for box in mine {
                        var r = (top: pgs.y + box.rect.top - top - box.above, bottom: pgs.y + box.rect.bottom - top + box.below, left: box.rect.left, right: box.rect.right)
                        // (Pinned: where the first setting put it, its band
                        // already on the page, drawn there however far its
                        // paragraph has moved since.)
                        if let pin = _pinnedFloats[box.id], pin.page == pgs.page {
                            let moved = pgs.y - pin.anchorY
                            _floatShiftY[box.id] = abs(moved) > 0.01 ? -moved : nil
                            continue
                        }
                        // (Found over a table's row set before its anchor
                        // on this page: a table does not wrap.)
                        if theme.wordRules, !pgs.pinPass,
                           _pages[pgs.page].contains(where: { piece in
                               !piece.repeated && piece.part != .rules && piece.paragraph < pgs.i && _cells[piece.paragraph] != nil
                                   && piece.pageY < r.bottom - 0.5 && piece.pageY + (piece.flowBottom - piece.flowTop) > r.top + 0.5
                           }) {
                            _pinnedFloats[box.id] = (pgs.page, r.top, r.bottom, r.left, r.right, pgs.y)
                            pgs.pinnedAnew = true
                        }
                        let before = _floatShift[box.id] ?? 0
                        r.left -= before; r.right -= before
                        var shift = 0.0
                        // (A float only grazing another does not move: tdf128207's four charts, in a
                        // grid of two by two, `allowOverlap` 1, the right-hand pair 8.5 twips into
                        // each other from the wrap polygon, kept their columns in Word's print.)
                        // (Its own left and right, not the open side run out to the column's edge: lo-697c2375's
                        // blue box, text on its right, 90pt tall at 286 across and 157 down, overlapped the orange one
                        // above it by that run, was moved a column's width away and not drawn; Word's print has it at
                        // 286, and the green box after it 51pt higher than ours.)
                        let span = _wrapOwnSpan[box.id].map { ($0.left - before, $0.right - before) } ?? (r.left, r.right)
                        // (With `allowOverlap` 1 a float is left over another anchored in its own paragraph,
                        // behind the text or in front, any wrap; one over an earlier paragraph's is moved clear.
                        // Windows' labs overlap and overlap2, and lo-6f698ba2's Caption frame.)
                        let ownFloat = ((pgs.i < _floatImages.count ? [_floatImages[pgs.i]].compactMap { $0 } : []) + (pgs.i < _inline.count ? _inline[pgs.i] : []))
                            .first { $0.id == box.id && ($0.sourceXML?.containsSubstring("allowOverlap=\"1\"") ?? false) }
                        let allowsOverlap = theme.wordRules && RichTextTheme.wordWindowsPages && ownFloat != nil
                        // (Only an offset the file gives, along the column: an aligned float has none to keep.)
                        let keptOffset = allowsOverlap && ownFloat?.float?.horizontalAlign == nil && ownFloat?.float?.horizontalFrom == "column"
                        // (Not one set from where its host line starts: that already clears the wrapped pictures before it, and Word lets the
                        // rest of it lie over them: 4fbb6e32's picture, 207 to 365, over the one at 105 to 332.)
                        for b in (allowsOverlap ? pgs.bands : pgs.bands + placed) where !_hostLineSet.contains(box.id) && b.top < r.bottom - 10 && b.bottom > r.top + 10
                            && b.left < span.1 + shift - 0.5 && b.right > span.0 + shift + 0.5 && span.0 + shift < b.right {
                            // (Moved clear it lands at the other's right edge PLUS its own offset along the column: windows' overlap2.)
                            shift = max(shift, b.right - span.0 + (keptOffset ? r.left : 0))
                        }
                        // (One moved clear that would leave the page stays where it is put: lo-6f698ba2's frame, 361 to 539,
                        // over an earlier paragraph's picture in Word's print.)
                        if keptOffset, shift > 0.5, r.right + shift > pageRect(pgs.page).width - _pxMarginLeft(pgs.page) + 0.5 { shift = 0 }
                        _floatShift[box.id] = shift > 0.5 ? shift : nil
                        r.left += shift; r.right += shift
                        placed.append(r)
                    }
                    pgs.bands += placed
                    if RichTextTheme.wordWindowsPages {
                        for (n, box) in mine.enumerated() where n < placed.count {
                            let own = ((pgs.i < _floatImages.count ? [_floatImages[pgs.i]].compactMap { $0 } : []) + (pgs.i < _inline.count ? _inline[pgs.i] : []))
                            if own.contains(where: { $0.id == box.id && $0.float?.wrapsTight == true }) { pgs.tightBandBottoms.append(placed[n].bottom) }
                        }
                    }
                }
                // Lines of picture-only paragraphs that the pictures now
                // leave no room — this one's and those just above it —
                // go under them, one after another; their pictures stay
                // where their paragraphs first stood. (Word's print of
                // zh-37b6536f: two photos anchored in two empty
                // paragraphs, the second moved clear of the first, and
                // both empty lines under the pair, the text after them.)
                if _anchorsOnly(pgs.i, document) {
                    pgs.anchorRun.append(pgs.i)
                    func lineTop(_ k: Int) -> Double? {
                        if k == pgs.i { return pgs.y + _spaceBefore[k] - headSkip }
                        guard let piece = _pages[pgs.page].last(where: { $0.paragraph == k && $0.part == .all }) else { return nil }
                        return piece.pageY + (_tops[k] + _spaceBefore[k] - piece.flowTop)
                    }
                    func lineHeight(_ k: Int) -> Double { _heights[k] - _spaceBefore[k] }
                    // (The line alone meets the picture, not its space
                    // after: zh-27a874b7's empty anchor, 27pt under a chart
                    // 27.3 down, stays over it. Not a picture's own
                    // paragraph, whose band stands from its text's top:
                    // zh-f47b8a74's "第  页共  页" box goes over its line.)
                    func meets(_ k: Int) -> Double {
                        // (A line of a multiple above one, beside its own picture wrapped square from the paragraph:
                        // the text's line alone meets it, not the multiple's extra — 9bde52's empty anchor, an
                        // 18pt grid line at 1.15, 20.7pt, over a chart 19.3 down, stays in Word's print.)
                        if theme.wordRules, RichTextTheme.wordWindowsPages, case let m = document.paragraphs[k].style.lineSpacing, m > 1.001,
                           document.paragraphs[k].style.lineHeightPoints == nil,
                           let f = document.paragraphs[k].image?.float, f.wraps, !f.takesRoom, !f.bandsPage, f.verticalFrom == "paragraph" {
                            return max(0.02, (lineHeight(k) - _spacing(k, document).after) / m)
                        }
                        return theme.wordRules && document.paragraphs[k].image == nil
                            ? max(0.02, lineHeight(k) - _spacing(k, document).after) : lineHeight(k)
                    }
                    if let first = pgs.anchorRun.firstIndex(where: { k in lineTop(k).map { noRoom(at: $0, height: meets(k), []) != nil } ?? false }),
                       var at = lineTop(pgs.anchorRun[first]) {
                        var steps = 0
                        let started = at
                        while let below = noRoom(at: at, height: meets(pgs.anchorRun[first]), []), steps < 20 { at = below; steps += 1 }
                        // (A line that heads its page and, set under the picture, would end past
                        // the page's foot stays where it stands, as Word's print of zh-b3e8dec4's
                        // 672pt pictures: each one's page holds the picture at its anchor and
                        // the next picture's page follows — ours sent the line to the next page
                        // and drew the picture there, 600pt above it.)
                        if theme.wordRules, RichTextTheme.wordWindowsPages, started <= 0.01 + headSkip, pgs.anchorRun[first] == pgs.i,
                           at + lineHeight(pgs.i) > pgs.contentH + 0.01 {
                            at = started
                        }
                        for k in pgs.anchorRun[first...] {
                            guard let old = lineTop(k) else { continue }
                            let delta = at - old
                            at += lineHeight(k)
                            guard delta > 0.01 else { continue }
                            for image in document.paragraphs[k].inlineImages.values { _floatShiftY[image.id] = -delta }
                            if let image = document.paragraphs[k].image { _floatShiftY[image.id] = -delta }
                            if k == pgs.i {
                                // (Off the page's head, the line keeps all
                                // of its space before.)
                                pgs.y += delta - headSkip
                            } else {
                                for n in _pages[pgs.page].indices where _pages[pgs.page][n].paragraph == k {
                                    let moved = _pages[pgs.page][n]
                                    _pages[pgs.page][n] = PagePiece(paragraph: moved.paragraph, flowTop: moved.flowTop, flowBottom: moved.flowBottom,
                                                                page: moved.page, pageY: moved.pageY + delta)
                                    if let m = _allPieces.lastIndex(of: moved) { _allPieces[m] = _pages[pgs.page][n] }
                                }
                            }
                        }
                    }
                } else if !document.paragraphs[pgs.i].text.isEmpty {
                    pgs.anchorRun.removeAll()
                }
            }
            var cursor = pgs.resumeCursor ?? top
            pgs.resumeCursor = nil
            var cuts: [Double]? = nil   // lazily computed line bottoms
            // A paragraph that heads a page leaves its space before
            // behind, as Word sets it (prints of 2026-10-13, modes 14 and
            // 15): where the page before filled up, and after a break
            // character — an empty paragraph's space as well, though its
            // line stays. The space counts toward whether the paragraph
            // fits the page it would not head: a line with room for
            // itself and not for its space goes over, and stands there
            // without it. Kept: the document's first paragraph's, a new
            // section's, that of a paragraph which itself begins with
            // the break character (one that ends the paragraph above
            // leaves it behind), and — before the 2013 layout only —
            // that of a paragraph with `w:pageBreakBefore`. And only
            // the page's first paragraph leaves it: one under
            // paragraphs of no height — hidden ones, after a section's
            // break — keeps its space (zh-90e0cea8's appendix heading).
            // A frame placed on the page (`w:framePr` anchored to the page,
            // at a y it states): set there, and the flow goes on from where
            // it stood — a frame takes no room. A run of paragraphs with one
            // frame is one frame. zh-90e0cea8's standard cover is all
            // frames, each at its own height on the page; set in the flow,
            // "2022-02-18 发布" stood 168pt above Word's.
            let ownFrame = document.paragraphs[pgs.i].style.frameXML
            let frameStarts = theme.wordRules && _cells[pgs.i] == nil && ownFrame != nil
                && !(pgs.i > 0 && document.paragraphs[pgs.i - 1].style.frameXML == ownFrame)
            // (The first paragraph of the flow after such a frame — not another
            // frame, not a table's — stands under it, or on the next page.)
            if let foot = pgs.frameFoot, ownFrame == nil, _cells[pgs.i] == nil {
                // (A frame set from the text below, of an exact height, leaves the
                // paragraphs that end over it where they are: the flow goes under
                // it from the first that would meet it.)
                if foot.top > 0, foot.page == pgs.page, pgs.i < _heights.count, pgs.y + _heights[pgs.i] <= foot.top - 0.5 {
                    // stays pending
                } else {
                    if foot.page == pgs.page { pgs.y = max(pgs.y, foot.y) }
                    pgs.frameFoot = nil
                }
            }
            // (Frames of an exact height, wrapped "notBeside" and set from the text, are
            // anchored to the paragraph after them, not to each other: lo's
            // tdf105035_framePrC sets a title frame and an authors frame, both 28.4pt
            // down, over each other, the "Abstract" line above them and the body under
            // both. Each is set where the flow stands plus its offset, and takes no
            // room; the flow goes under the lower foot from the first line that
            // would meet it.)
            if frameStarts, theme.wordRules, RichTextTheme.wordWindowsPages, let f = document.paragraphs[pgs.i].style.frame,
               f.verticalAnchor == "text", f.verticalAlign == nil, let xml = document.paragraphs[pgs.i].style.frameXML,
               xml.containsSubstring("w:wrap=\"notBeside\""), xml.containsSubstring("w:hRule=\"exact\""),
               let hAt = xml.firstRange(of: "w:h=\""), let hh = Double(xml[hAt.upperBound...].prefix { $0 != "\"" }), hh > 0,
               document.paragraphs[pgs.i].image == nil {
                var v = 0.0
                if let at = xml.firstRange(of: "w:vSpace=\""), let n = Double(xml[at.upperBound...].prefix { $0 != "\"" }) { v = n / 20 }
                let target = pgs.y + _px(f.y)
                if target < pgs.contentH - 0.01 {
                    RuleTrace.hit("exact-text-frame-hangs-from-the-flow-below-it")
                    if pgs.frameReturn == nil || pgs.frameReturn!.page != pgs.page { pgs.frameReturn = (pgs.y, pgs.page) }
                    pgs.y = target
                    let foot = target + _px(hh / 20 + v)
                    pgs.frameFoot = (max(foot, pgs.frameFoot?.page == pgs.page ? pgs.frameFoot!.y : 0), pgs.page, min(target, pgs.frameFoot?.page == pgs.page ? pgs.frameFoot!.top : target))
                }
            } else
            if frameStarts, let f = document.paragraphs[pgs.i].style.frame, Self._framePlaced(f), Self._onThePage(document.paragraphs[pgs.i].style) {
                let physical = pgs.page / _columns
                let insetTop = physical < _pageInsetTop.count ? _pageInsetTop[physical] : 0
                // (A frame on the margin from the text's top: the cover's
                // "山东省市场监督管理局 发布", 751pt under the margin, stood
                // in the flow at the page's head.)
                var target = f.verticalAnchor == "margin" ? _px(f.y) : _px(f.y) - insetTop
                // (Aligned on the margins, by the height it states: the
                // frame of LibreOffice's tdf112287 has yAlign bottom and
                // stands at the foot of the text area in Word's print.)
                if let a = f.verticalAlign, let h = f.height {
                    target = a == "top" ? 0 : a == "center" ? (pgs.contentH - _px(h)) / 2 : pgs.contentH - _px(h)
                }
                // (A page-anchored frame that holds one drawing in its line
                // and nothing else stands its drawing at the frame's y less
                // the page's top margin — lab frame, Word for Windows, 20
                // prints: lo tdf147485's logo, frame y 49.8, margin 27,
                // drawn from 22.8, whatever the frame's or drawing's height.)
                let framed = document.paragraphs[pgs.i]
                if theme.wordRules, f.verticalAnchor == "page",
                   framed.image.map({ $0.float == nil }) ?? (!framed.inlineImages.isEmpty && framed.text.unicodeScalars.allSatisfy({ $0.value == 0xFFFC })
                                                            && framed.inlineImages.values.allSatisfy({ $0.float == nil })) {
                    target -= insetTop
                }
                if target > -insetTop, target < pgs.contentH - 0.01 {
                    if pgs.frameReturn == nil || pgs.frameReturn!.page != pgs.page { pgs.frameReturn = (pgs.y, pgs.page) }
                    pgs.y = target
                    // (A frame text is not set beside, of a height it states
                    // exactly: the flow after it starts under it — lo
                    // tdf104394_lostTextbox's 237pt box on a 298pt page
                    // sends "Pushed to page 2 by the framed text." to page 2
                    // in Word's print; ours set it at the top of page 1.)
                    let xml = document.paragraphs[pgs.i].style.frameXML ?? ""
                    func number(_ key: String) -> Double? {
                        guard let r = xml.firstRange(of: key + "=\"") else { return nil }
                        return Double(xml[r.upperBound...].prefix { $0 != "\"" })
                    }
                    // (Wrapped "around" with no strip of text width left beside it: Word keeps the
                    // text below, as for notBeside. sa1 b0e39b18's 324pt frame, 17pt between its
                    // right edge and a page-anchored frame, has "Person Filing" 28pt lower.)
                    var noStrip = false
                    if RichTextTheme.wordWindowsPages, xml.containsSubstring("w:wrap=\"around\""), let w = number("w:w"), let x = number("w:x"), let h = number("w:h") {
                        let setup = pageSetup(forPage: pgs.page)
                        let pageAnchored = xml.containsSubstring("w:hAnchor=\"page\"")
                        let hs = (number("w:hSpace") ?? 0) / 20
                        let left0 = x / 20 - (pageAnchored ? setup.marginLeft : 0)
                        let right0 = left0 + w / 20
                        let topPg = (xml.containsSubstring("w:vAnchor=\"page\"") ? 0 : setup.marginTop) + (number("w:y") ?? 0) / 20
                        var rightEdge = setup.columnWidth
                        for (j, q) in document.paragraphs.enumerated() where j != pgs.i {
                            guard let qx = q.style.frameXML, qx.containsSubstring("w:hAnchor=\"page\""), qx.containsSubstring("w:vAnchor=\"page\""),
                                  qx.containsSubstring("w:hRule=\"exact\"") else { continue }
                            func qn(_ key: String) -> Double? {
                                guard let r = qx.firstRange(of: key + "=\"") else { return nil }
                                return Double(qx[r.upperBound...].prefix { $0 != "\"" })
                            }
                            guard let ox = qn("w:x"), let oy = qn("w:y"), let oh = qn("w:h") else { continue }
                            let oLeft = ox / 20 - setup.marginLeft - ((qn("w:hSpace") ?? 0) / 20)
                            if oLeft >= right0, oy / 20 < topPg + h / 20, oy / 20 + oh / 20 > topPg { rightEdge = min(rightEdge, oLeft) }
                        }
                        noStrip = max(rightEdge - right0 - hs, left0 - hs) < 36
                    }
                    if xml.containsSubstring("w:wrap=\"notBeside\"") || noStrip, xml.containsSubstring("w:hRule=\"exact\""), let h = number("w:h"), h > 0 {
                        pgs.frameFoot = (target + _px(h / 20 + 2 * (number("w:vSpace") ?? 0) / 20), pgs.page, 0)
                    }
                }
            }
            // The paragraph a floating table is anchored to stands where the
            // table began, the table its offset below that paragraph's top:
            // zh-fb482d33's roster (tblpY 430 twips, full width) has its
            // anchor, an empty 12pt line, above it in Word's print — a lab's
            // "Y" there stands at the table's place, the "X" after it under
            // the table — where ours set the anchor under the table too, and
            // the section's last lines went to a page of their own.
            // (And the paragraphs after it, while they fit in what is left
            // of the offset: zh-8699644f's targets table, tblpY 764 twips,
            // has three empty 12pt lines in its 38.2pt over it in Word's
            // print and "二、重点任务" under it, still on page 1; ours set
            // the first two under the table, and the heading went over.)
            if let tf = pgs.textFloatTop {
                pgs.textFloatTop = nil
                // (A paragraph with the strip beside a table at the right margin to itself stays level with
                // it as long as the table lasts: lo-717ff943's bullets, tdf97090.)
                let alongside = pgs.i > 0 && (tf.chained || _cells[pgs.i - 1]?.table == tf.table) && (pgs.besideChainEnd.map { tf.y + 0.01 < $0 } ?? false)
                    && _cells[pgs.i] == nil && _besideIndent(pgs.i, document.paragraphs[pgs.i], document)?.right == true
                    // (A blank line, or one of spaces only, keeps its own height and moves the flow on:
                    // dx2 9dc455a3's two lines of spaces and the empty mark after "Tarikh Proses", beside
                    // a table at the right with tblpY, stand 12.8pt apart in Word's print.)
                    && document.paragraphs[pgs.i].text.contains(where: { $0 != " " && $0 != "\t" })
                // (The lines stacked beside the table before a blank one have moved the flow on.)
                if theme.wordRules, tf.chained, tf.page == pgs.page, pgs.frameReturn == nil, _cells[pgs.i] == nil, tf.y > pgs.y + 0.01,
                   !document.paragraphs[pgs.i].text.contains(where: { $0 != " " && $0 != "\t" }) {
                    pgs.y = tf.y
                } else if theme.wordRules, RichTextTheme.wordWindowsPages, tf.chained, tf.page == pgs.page, pgs.frameReturn == nil, _cells[pgs.i] == nil, tf.y > pgs.y + 0.01,
                          !alongside, let end = pgs.besideChainEnd, tf.y >= end - 0.01 {
                    // (The strip beside the table used up, the paragraph after it goes on under the lines stacked there.)
                    RuleTrace.hit("word-text-after-the-strip-beside-a-floating-table-goes-on-under-it")
                    pgs.y = tf.y
                }
                // (The document's first block, a table floating by the text: its anchor is the paragraph after it, which
                // stands at the page's top where the table's offset is measured from, and the flow goes on under that
                // line, not under the offset. sa2 299ec051, tblpY 438 twips, seven empty lines and "Fuente" after it:
                // Word's print has the empties 25.4pt apart from the margin and "Fuente" at 244.3, ours 266.3.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, !tf.chained, pgs.i > 0, _cells[pgs.i - 1]?.table == tf.table, _cells[pgs.i] == nil,
                   tf.page == pgs.page, pgs.frameReturn == nil, !_pageBreak[pgs.i], bottom - top > tf.down + 0.01, tf.y < 0.01,
                   // (A table with room beside it: one as wide as the text sets the lines under it.)
                   let across = _columnWidths[tf.table]?.reduce(0, +), across < _flowWidth(pgs.i) - _px(40),
                   { () -> Bool in
                       var k = pgs.i - 1
                       while k > 0, _cells[k - 1]?.table == tf.table { k -= 1 }
                       // (On a later page too: the anchor stands at the page's top where the offset is measured from. sa2 bf81a10c: the caption
                       // "4. Grado..." with its clearing break, 57pt against a 52.6pt offset, stood in the room beside its table, 52pt low.)
                       return k == 0 || pgs.page > 0
                   }() {
                    RuleTrace.hit("word-first-block-floating-table-anchor-stands-at-the-top")
                    pgs.y = tf.y
                }
                if theme.wordRules, pgs.i > 0, tf.chained || _cells[pgs.i - 1]?.table == tf.table, _cells[pgs.i] == nil, tf.page == pgs.page,
                   !(_floatLeavesNoStrip(tf.table, pgs.i, document) && _floatFollowsFloat(tf.table, document)), pgs.frameReturn == nil, !_pageBreak[pgs.i], bottom - top <= tf.down + 0.01 || alongside {
                    pgs.frameReturn = (pgs.y, pgs.page)
                    pgs.y = tf.y
                    pgs.textFloatTop = (tf.table, pgs.page, tf.y + (bottom - top), tf.down - (bottom - top), true)
                }
                // (A paragraph too tall for what is left of the offset parts
                // there: the lines that fit stand over the table, the rest
                // under it. LibreOffice's tdf124675, tblpY 2340 twips under
                // three paragraphs of 100pt: the first line of the fourth
                // stands at 136.7 in Word's print, its second under the
                // table; ours set both under it.)
                else if theme.wordRules, RichTextTheme.wordWindowsPages, pgs.i > 0, tf.chained || _cells[pgs.i - 1]?.table == tf.table,
                        _cells[pgs.i] == nil, tf.page == pgs.page, pgs.frameReturn == nil, !_pageBreak[pgs.i], pgs.resumeCursor == nil,
                        tf.down > 0.01, bottom - top > tf.down + 0.01, document.paragraphs[pgs.i].image == nil,
                        // (A table with room beside it sets text there instead.)
                        let across = _columnWidths[tf.table]?.reduce(0, +), across >= _flowWidth(pgs.i) - _px(40),
                        _besideIndent(pgs.i, document.paragraphs[pgs.i], document) == nil,
                        // (Only where a line stands over the table and another goes under:
                        // all of its lines over it, and just its space after under, leaves
                        // it where it was.)
                        case let g = geometry(pgs.i), case let cs = Self._lineBottoms(g.painter).map({ g.textTop + $0 + (pgs.i < _firstLineLift.count ? _firstLineLift[pgs.i] : 0) }),
                        cs.count >= 2, cs[0] - top <= tf.down + 0.01 {
                    pgs.frameReturn = (pgs.y, pgs.page)
                    pgs.floatHold = .init(limit: tf.y + tf.down, back: pgs.y, source: .table)
                    pgs.y = tf.y
                }
                // (Held in by a header picture's strip, a line under a floating table is
                // stepped down from the anchor's line at its own pitch until it clears
                // the table, not set at its foot: Word's print of tdf38575 (lab bis)
                // has the blank after the anchor 269.2, the table's foot 261.3, in
                // slots of 13.8 from the anchor's 131.1; with the table cut to two
                // paragraphs 213.9 for a foot of 211.9.)
                else if theme.wordRules, RichTextTheme.wordWindowsPages, pgs.i > 0, tf.chained, _cells[pgs.i] == nil, tf.page == pgs.page, pgs.frameReturn == nil,
                        _setup(ofParagraph: pgs.i).headerWrapLeft > 0, bottom - top > 0.01, pgs.y > tf.y + 0.01 {
                    RuleTrace.hit("header-wrap-line-under-floating-table-steps")
                    let step = bottom - top
                    pgs.y = tf.y + (((pgs.y - tf.y) / step) - 0.001).rounded(.up) * step
                }
            }
            defer { pgs.floatHold = nil }
            defer {
                if let back = pgs.frameReturn, !(pgs.i + 1 < count && ownFrame != nil && document.paragraphs[pgs.i + 1].style.frameXML == ownFrame) {
                    if back.page == pgs.page { pgs.y = back.y }
                    pgs.frameReturn = nil
                }
            }
            // A paragraph that ends its section and holds only floating
            // objects takes no room (see `_layoutParagraph`), but stands on
            // its page all the same, its objects with it: zh-6d402586's
            // annexes are each a section of one such paragraph — a page's
            // picture and its "附件1" box — and Word draws them on the
            // annex's page; ours gave the paragraph no piece, and the page
            // stood blank.
            if theme.wordRules, bottom - top < 0.01, _cells[pgs.i] == nil, document.paragraphs[pgs.i].style.sectionXML != nil,
               (pgs.i < _floatImages.count && _floatImages[pgs.i] != nil) || (pgs.i < _inline.count && _inline[pgs.i].contains { $0.float != nil }) {
                _pg_add(&pgs, document, PagePiece(paragraph: pgs.i, flowTop: top, flowBottom: top, page: pgs.page, pageY: pgs.y))
            }
            // (An empty mark of a continuous section that does not fit what
            // is left of the page takes none of it there, and opens no page:
            // zh-b8de3ae2's p9 ends in "資料來源：本所會計室" at 779 and the five
            // empty marks after it — the 4- and 2-column sections between —
            // stand nowhere in Word for Windows' print, p10 opening with
            // "表2". Where they fit they take their room, as under its
            // chart 10; see `_layoutParagraph`.)
            if RichTextTheme.wordWindowsPages, theme.wordRules, pgs.resumeCursor == nil, _cells[pgs.i] == nil,
               case let mark = document.paragraphs[pgs.i], mark.text.isEmpty, mark.image == nil, mark.style.sectionXML != nil,
               mark.style.sectionBreaksPage == false, bottom - cursor > pgs.contentH - pgs.y + 0.01 {
                _pg_add(&pgs, document, PagePiece(paragraph: pgs.i, flowTop: top, flowBottom: top, page: pgs.page, pageY: pgs.y))
                cursor = bottom
            }
            // (A document with `suppressTopSpacing` stands an exact line (over 12pt) that opens a page
            // by the flow, not by a break, as high as one that opens by a break: 0.8 x (height - 12pt)
            // off the top of the first line, the paragraph's other lines with it. Lab exacttop,
            // Word for Windows; xb 46bc4851's p9 stood 6.4pt low. Taken off the flow here;
            // `_layoutParagraph` does it for the document's first and a break's.)
            var naturalRise = 0.0
            if theme.wordRules, RichTextTheme.wordWindowsPages, document.suppressesTopSpacing, pgs.resumeCursor == nil,
               _cells[pgs.i] == nil, pgs.i > 0, !_pageBreak[pgs.i],
               let h = document.paragraphs[pgs.i].style.lineHeightPoints, h > 12 {
                naturalRise = _px(document.paragraphs[pgs.i].style.lineHeightIsMinimum ? h - 9.4 : 0.8 * (h - 12))
            }
            while cursor < bottom - 0.01 {
                if leavesLead, pgs.pageFresh, pgs.y < 0.01, pgs.page > 0, cursor <= top + 0.01 { cursor = min(bottom, top + lead) }
                // (A paragraph at the top of a column, by a column break or by the flow,
                // in a section that starts in the middle of the page, holds none of its
                // space before there: lo/dx2 99cfc555's Abstract, and "2. Nguyên liệu", 3pt.)
                else if theme.wordRules, RichTextTheme.wordWindowsPages, pgs.pageFresh, pgs.page > 0, pgs.resumeCursor == nil, lead > 0.01, cursor <= top + 0.01,
                        pgs.y >= 0.01, _cells[pgs.i] == nil {
                    RuleTrace.hit("column-break-paragraph-drops-its-space-before-at-column-top")
                    cursor = min(bottom, top + lead)
                }
                // (Space kept at a page's top is less the space after of
                // the paragraph that ended the page before: the two are
                // one gap to Word, and the part of it the last page left
                // behind is not set again. A heading of 18pt before under
                // `w:pageBreakBefore`, after Body Text's 6pt after, starts
                // 12pt down; 9pt before, 3; 6 or less, none — at 12, 16
                // and 20pt, labs `hd`..`hm`, 2026-10-14; without that
                // after, all of it.)
                else if theme.wordRules, !leavesLead, pgs.y < 0.01, pgs.page > 0, cursor <= top + 0.01, lead > 0.01,
                        pgs.i > 0, _cells[pgs.i - 1] == nil, !document.paragraphs[pgs.i].style.markFollowsBreak {
                    let prevAfter = _spacing(pgs.i - 1, document).after
                    if prevAfter > 0.01 { cursor = min(bottom, top + min(lead, prevAfter)) }
                }
                if naturalRise > 0, pgs.y < 0.01, pgs.page > 0, cursor <= top + lead + 0.01 {
                    RuleTrace.hit("suppress-top-spacing-raises-a-natural-page-first-exact-line")
                    cursor = min(bottom, cursor + naturalRise)
                    naturalRise = 0
                    if cursor >= bottom - 0.01 { break }
                }
                // (A paragraph that meets a picture with no room beside it goes line by line, in Word's print
                // (lab pwsplit, compat 14 and 15): the lines that stand clear of it stay over it, the first
                // that meets it and all after it go to the picture's foot, the paragraph's flow unbroken. What
                // counts of a line is its whole box in Word 2010's layout, its text alone (not a multiple's
                // extra) from 2013's: a picture's top at the text's foot leaves the line over it.)
                if _lineDropSeen.insert(pgs.i).inserted { _lineDropWant[pgs.i] = nil }
                if let probe = pictureProbe, pgs.floatHold == nil, theme.wordRules, RichTextTheme.wordWindowsPages, pgs.frameReturn == nil, _columns == 1,
                   _cells[pgs.i] == nil, document.paragraphs[pgs.i].image == nil,
                   !document.paragraphs[pgs.i].text.isEmpty, _besideOwn(pgs.i, document.paragraphs[pgs.i], document) == nil {
                    let g = geometry(pgs.i)
                    let lift = pgs.i < _firstLineLift.count ? _firstLineLift[pgs.i] : 0
                    let lines = Self._lineBottoms(g.painter).map { g.textTop + $0 + lift }
                    let st = document.paragraphs[pgs.i].style
                    let textOnly = (document.compatibilityMode ?? 12) >= 15 && st.lineSpacing > 1.001 && st.lineHeightPoints == nil
                    var prev = g.textTop + lift
                    var firstRemaining: Int? = nil
                    var restartOnNewPage = false
                    for (k, c) in lines.enumerated() {
                        defer { prev = c }
                        if c <= cursor + 0.01 { continue }
                        if firstRemaining == nil { firstRemaining = k }
                        let h = c - prev
                        // (Word 2010's layout counts the paragraph's space after in its last line's box: lab pwsplit3,
                        // an item's third line stays over a picture whose top is 8pt, the space after, below its foot.)
                        let afterShare = (document.compatibilityMode ?? 12) < 15 && k == lines.count - 1 ? _spacing(pgs.i, document).after : 0
                        let measure = (textOnly ? h / st.lineSpacing : h) + afterShare
                        let lineTop = pgs.y + (prev - cursor)
                        guard probe(lineTop, measure) != nil else { continue }
                        if k == firstRemaining { break }
                        var back = lineTop, steps = 0
                        while let below = probe(back, measure), steps < 20 {
                            // (Word's lab tightstep J: a tight box's foot is met by whole lines of the paragraph's own grid.)
                            if RichTextTheme.wordWindowsPages, h > 1, pgs.tightBandBottoms.contains(where: { abs($0 - below) < 0.02 }) {
                                back += max(1, ((below - back) / h - 0.001).rounded(.up)) * h
                            } else { back = below }
                            steps += 1
                        }
                        // (One line left above the picture while the rest goes on to the next page is an orphan, which
                        // widow control forbids: lab pwsplit2 foot r2, the three-line item goes whole to page 2.)
                        // (Lab pwsplit4, compat 15: widow control or keep-lines on, a split that spills lines below the
                        // picture onto the next page and leaves one line above it, or one line spilled, takes the
                        // whole paragraph to the next page; keep-lines takes it whole whatever the counts.)
                        if pgs.resumeCursor == nil {
                            let above = k - (firstRemaining ?? k)
                            var fit = 0
                            for j in k..<lines.count where back + (lines[j] - lines[k - 1]) <= pgs.contentH + 0.01 { fit += 1 }
                            let spill = lines.count - k - fit
                            let wc = st.widowControl && !document.widowControlSuspended
                            if spill > 0, st.keepLines || (wc && (above == 1 || spill == 1 || (above == 0 && lines.count >= 2))) {
                                RuleTrace.hit("word-widow-or-keep-lines-takes-a-paragraph-parted-by-a-picture-to-the-next-page")
                                _pg_newPage(&pgs, document)
                                restartOnNewPage = true
                                break
                            }
                        }
                        RuleTrace.hit("word-paragraph-parts-around-a-picture")
                        pgs.floatHold = .init(limit: lineTop + 0.05, back: back, source: .picture)
                        if k > 0, back - lineTop > 0.01 {
                            RuleTrace.hit("word-lines-carried-past-a-picture-are-set-beside-a-second-one-where-they-stand")
                            _lineDropWant[pgs.i] = (k, 0)
                        }
                        break
                    }
                    // (The paragraph went whole to the next page: its space before at that page's top goes by the
                    // page-top rules above, so run the loop again from the top.)
                    if restartOnNewPage { continue }
                }
                let tailGive = pgs.tailHold.map { $0.paragraph == pgs.i && $0.page == pgs.page ? $0.give : 0 } ?? 0
                let available = (pgs.floatHold?.limit ?? pgs.contentH) - pgs.y - tailGive
                let rest = bottom - cursor
                // (The last line may reach past the foot by its grid's
                // overhang.)
                // (A frame placed on the page stands where it is placed,
                // past the foot or not: zh-9db183d5's cover issuer, a 29.2pt
                // frame 751pt under a margin of -338 twips, ends 6.6pt under
                // the text's foot and stays on the cover in Word's print;
                // ours took it, and a page of its own, to page 2.)
                let placedFrame = theme.wordRules && ownFrame != nil && pgs.frameReturn?.page == pgs.page
                // (Not into the footnotes: over a page's notes the line ends
                // above them. zh-c15af02e's page 6, 45.7pt lines on a grid
                // over a one-line note, holds thirteen in Word's print; the
                // fourteenth reaches 4.3pt into the separator's line, and
                // its overhang let ours keep it.)
                // (Nor over notes already taken off the foot of a page of columns' slot, which the page
                // holds though none is set yet: sa1 978697fd's page 4, a note's 37.8pt off the
                // foot, ends its paragraph a line sooner in Word's print than the overhang let ours.)
                let reservedNotes = _columns > 1 && (_columnNoteReserve[pgs.page] ?? 0) > 0
                let overhang = placedFrame ? .infinity : theme.wordRules && pgs.i < _overhang.count && pgs.pageNotes.isEmpty && !reservedNotes ? _overhang[pgs.i] : 0
                let lineOverhangs = !placedFrame && theme.wordRules && pgs.pageNotes.isEmpty && !reservedNotes && pgs.i < _lineOverhang.count ? _lineOverhang[pgs.i] : []
                // (The reach of line `k` past the foot: its own faces'.)
                func reach(_ k: Int) -> Double { k >= 0 && k < lineOverhangs.count ? max(overhang, lineOverhangs[k]) : overhang }
                // (A last line that is empty — only the paragraph mark, after a trailing line break —
                // is set though it hangs past the foot; any line with text must fit. Word for
                // Windows, lab lh3: lo-f5c618c5's 37-line paragraph, 36 line breaks, exact 13pt, keeps
                // its empty 37th line 0.75pt past the foot — and 1.85pt in a page 1pt shorter — on
                // page 1; with a letter on that line, or one more line after it, it goes on.)
                let emptyTail: Double = {
                    guard theme.wordRules, RichTextTheme.wordWindowsPages, document.paragraphs[pgs.i].cell == nil, let last = document.paragraphs[pgs.i].text.last,
                          last == "\n" || last == "\u{2028}" || last == "\u{000B}" else { return 0 }
                    return _px(3)
                }()
                // (Word sets a line where it ends on the foot or above —
                // in binary floating point: lab `ef`, Word 16, 2026-10-18,
                // exact lines of 20 and 27pt fill a page whose text is
                // 38 and 28 of them to the twip, and 20.85pt, which binary
                // cannot hold, fits 36 with a twip to spare and 35 with
                // none (lab `pf`: 33 of them likewise). So a tie goes to
                // the line only where its exact height is whole quarter
                // points (whole multiples of 5 twips). zh-289155d6's lines
                // of 27 and 28pt end on page 1's foot and stay there in
                // Word's print; ours took each page's last to the next.)
                let tieFits: Bool = {
                    let st = document.paragraphs[pgs.i].style
                    // (An "at least" line ties too in Word for Windows,
                    // where every line of the paragraph is its minimum:
                    // bug59058's page 28 ends in eight lines of
                    // at-least 15pt Times that fill the page to the twip,
                    // and Word for Windows keeps the eighth (word-win);
                    // Word for Mac takes it over, as ours did.)
                    guard let h = st.lineHeightPoints else { return false }
                    if st.lineHeightIsMinimum {
                        guard RichTextTheme.wordWindowsPages,
                              geometry(pgs.i).painter.computeLineMetrics().allSatisfy({ abs($0.height - _px(h)) < _px(0.01) }) else { return false }
                    }
                    let quarters = h * 4
                    return abs(quarters - quarters.rounded()) < 0.0001
                }()
                // (On a line grid the reach past the foot is Word's own sum,
                // and a twip over it still fits: zh-7b125a21's "B. 只能依照…",
                // 10.5pt 宋体 on a 15.6pt grid, reaches 0.005pt past what
                // its 1.3 em leaves and is page 1's last line in Word's
                // print; ours took it, and a line a page after it, over.)
                let slack = theme.wordRules && overhang > 0 && overhang.isFinite ? _px(0.05)
                    : theme.wordRules && !tieFits ? -_px(0.025) : 0.01
                // (A picture's line, not its space after: Word for Windows keeps
                // 0aca9a91's second 281.25pt picture, list paragraph, 1.5pt
                // after, on page 1 where the picture's line ends 0.4pt above
                // the foot and its space after stands past it; ours took it
                // to page 2 and every later picture one page off.)
                let pictureAfter: Double = theme.wordRules && RichTextTheme.wordWindowsPages && document.paragraphs[pgs.i].cell == nil
                    && (document.paragraphs[pgs.i].image != nil || _inlinePictureOnly(pgs.i, document)) ? _spacing(pgs.i, document).after : 0
                // (Word measures a line in whole twips, to the nearest: a part of a twip
                // under a half, that an auto-height line has past the last whole one,
                // does not count at the foot; ba88be26's 13pt Times line, over by
                // more, goes to the next page. 8b5747ec's Arial Narrow 12 heading is 13.77pt, 275.4
                // twips, and ends 0.4 twip past the foot; lab12 keeps it there
                // and moves it from 2 twips.)
                // (One line, with text: a blank line or a second line is left out; the
                // wide A/B showed Word moves a space-only line, and a 2-line Hebrew
                // paragraph, whole to the next page. The heading's own space after
                // stands past the foot, so its line is tested at its cut below.)
                func twipAllow(_ over: Double) -> Double {
                    guard theme.wordRules, RichTextTheme.wordWindowsPages, document.paragraphs[pgs.i].style.lineHeightPoints == nil,
                          document.paragraphs[pgs.i].cell == nil, cursor <= top + 0.01,
                          over > 0, over < _px(1.0 / 20),
                          document.paragraphs[pgs.i].text.unicodeScalars.contains(where: { $0 != " " && $0 != "\u{FFFC}" && $0 != "\n" && $0 != "\t" })
                    else { return 0 }
                    let lm = geometry(pgs.i).painter.computeLineMetrics()
                    guard lm.count == 1, let h = lm.last?.height else { return 0 }
                    let tw = h / _px(1.0 / 20)
                    let frac = tw - tw.rounded(.down) < 0.5 ? (tw - tw.rounded(.down)) * _px(1.0 / 20) : 0
                    return over <= frac + 0.001 ? over + max(0, -slack) : 0
                }
                let twipFrac = twipAllow(rest - pictureAfter - (available + reach(lineOverhangs.count - 1) + emptyTail))
                if rest - pictureAfter <= available + slack + reach(lineOverhangs.count - 1) + emptyTail + twipFrac {
                    // (The line, not its space after: that may stand past the foot.)
                    // (Nor, off the grid, a multiple's extra under its
                    // text, which Word stands past the foot as it does
                    // space after: zh-167ee06c's 1.5-spaced " " in
                    // JhengHei UI Light, 34.68pt, stands 4.3pt past page
                    // 6's foot in Word for Windows' print, and the page
                    // break opening the next paragraph opens page 7 — lab
                    // t178; ours called the page over-full and left page
                    // 7 blank.)
                    var spacing = false
                    if rest > available + 0.01, case let g = geometry(pgs.i), let line = Self._lineBottoms(g.painter).last {
                        let st = document.paragraphs[pgs.i].style
                        let offGrid = document.paragraphs[pgs.i].cell == nil
                            && !(st.eastAsian["w:snapToGrid"] != "0" && _grid(pgs.i, document).pitch != nil)
                        let extra = theme.wordRules && offGrid && st.lineHeightPoints == nil
                            && st.lineSpacing - theme.lineSpacingReduction > 1.001 && pgs.i < _overhang.count ? _overhang[pgs.i] : 0
                        if g.textTop + line - extra - cursor > available + 0.01, !placedFrame { pgs.overfull = true } else if g.textTop + line - extra - cursor > available + 0.01 {} else { spacing = extra > 0 }
                    }
                    _pg_add(&pgs, document, PagePiece(paragraph: pgs.i, flowTop: cursor, flowBottom: bottom,
                                                  page: pgs.page, pageY: pgs.y))
                    pgs.y += rest
                    if spacing || (pictureAfter > 0 && rest > available + 0.01) { pgs.spacedPast = pgs.y }
                    cursor = bottom
                    break
                }
                if cuts == nil {
                    let g = geometry(pgs.i)
                    let lift = pgs.i < _firstLineLift.count ? _firstLineLift[pgs.i] : 0
                    cuts = Self._lineBottoms(g.painter).map { g.textTop + $0 + lift }
                    if Self.debugPagination {
                        let m = g.painter.computeLineMetrics()
                        let desc = "para \(pgs.i) top \(g.top) textTop \(g.textTop) bottom \(g.bottom) painterH \(g.painter.height) lines \(m.count) heights \(m.map { $0.height }) baselines \(m.map { $0.baseline }) asc/desc \(m.first.map { "\($0.ascent)/\($0.descent)" } ?? "-") cursor \(cursor) y \(pgs.y) available \(available)\n"
                        FileHandle.standardError.write(Data(desc.utf8))
                    }
                }
                // The lowest cut that still fits.
                var cut: Double? = nil
                // (A box parted at the foot closes under its last line there: the
                // bottom rule's room comes off what the part may take. 8b283c4d's
                // red box, p27: its two-line paragraph's first line, 752.5 on the
                // baseline, is Word's p28 start, where a plain line stands to 752.7.)
                let partFoot: Double = theme.wordRules && RichTextTheme.wordWindowsPages
                    ? document.paragraphs[pgs.i].style.borders?.bottom.map { _px($0.space + Self._ruleRoom($0.style, $0.width)) } ?? 0 : 0
                // (A paragraph's bottom rule lies under its last line, before the space after: the last
                // line fits only with the rule's gap and width above the foot. 5e813226's Title heading,
                // 26pt Cambria, line ends 0.8pt above page 9's foot and its 1.5pt rule 0.7pt past it:
                // Word's print starts page 10 with it.)
                let lastFoot: Double = partFoot > 0 && !_bordersJoin(pgs.i, pgs.i + 1, document) ? partFoot : 0
                // (Over a page's footnotes the last line's space after must fit above the separator too: Word for Windows
                // keeps iv) of 58192c08 on page 5 with 0 pt after and sends it to page 6 with 3 pt, lab fnbreak v6/v7;
                // compat 14 keeps it, lab fncompat m14-v0/m14-v7. A paragraph that carries a note itself keeps its line: f0ca0950 p4 caption.)
                let afterOnNotes: Double = theme.wordRules && RichTextTheme.wordWindowsPages && (document.compatibilityMode ?? 12) >= 15 && !pgs.pageNotes.isEmpty && pgs.placing.isEmpty && document.paragraphs[pgs.i].cell == nil ? _spacing(pgs.i, document).after : 0
                // (A Tamil paragraph's marked-line surplus is under its last line and Word fits it with the line, only the space after standing past the foot: dx2 a347c3b3 page 4, three marked lines whose last ends 3 pt above the foot but whose surplus does not, go whole to page 5.)
                let tamilFoot = _tamilMarkedLinesExtra(pgs.i, document.paragraphs[pgs.i], document, geometry(pgs.i).painter)
                for (k, c) in cuts!.enumerated() where c > cursor + 0.01 && c - cursor <= available + slack + reach(k) + (k == cuts!.count - 1 ? emptyTail + twipAllow(c - cursor - (available + reach(k) + emptyTail)) - lastFoot - afterOnNotes - (k == cuts!.count - 1 ? tamilFoot : 0) : -partFoot) { cut = c }
                // (A picture's paragraph goes whole or to the next page: its
                // one cut is its empty line's, under the picture's top, and
                // took all of the picture into whatever room was left. Widow
                // control kept that from happening; zh-547fc43c's Normal turns
                // it off, and its 234pt chart hung 113pt past page 2's foot
                // where Word starts page 3 with it.)
                // (An inline picture alone in its paragraph likewise: a flowchart
                // canvas on a lines grid is whole pitches tall, and its painter's
                // one line is a pitch, so the cut above took it at the foot as a
                // sliver: jpn-z19171856-2c8799's pages 4 and 8 came out empty.)
                if theme.wordRules, pgs.y > 0.01, document.paragraphs[pgs.i].image != nil || _inlinePictureOnly(pgs.i, document), cursor <= top + 0.01,
                   bottom - _spacing(pgs.i, document).after - cursor > available + slack + overhang { cut = nil }
                // (So does a paragraph of floating objects alone: its
                // painter's line is its anchors', under a point tall, where
                // the paragraph stands an empty line — cut there, the
                // sliver stayed at the foot as if the rest were its space
                // after, and its objects, drawn only with it whole, were
                // lost. zh-b24b396a's figure D2/D3, 36 groups anchored in
                // one paragraph that Word starts page 13 with, drew none.)
                if theme.wordRules, pgs.y > 0.01, cursor <= top + 0.01, _anchorsOnly(pgs.i, document),
                   bottom - _spacing(pgs.i, document).after - cursor > available + slack + overhang { cut = nil }
                // (Over a floating table's offset only a real part counts: where
                // just the paragraph's space after does not fit, the paragraph
                // goes under the table whole, as it did before it could part.)
                if pgs.floatHold != nil, let c = cut, let last = cuts!.last, c >= last - 0.01 { cut = nil }
                // Word's rules for where a paragraph may part: not at all
                // (`w:keepLines`), or — its widow and orphan control,
                // which is on unless the paragraph says otherwise — with
                // two lines at least on each side.
                // (At a page's top too, for its widow control alone: a paragraph that
                // fills a page and leaves one line for the next gives that page
                // a line to keep company: tdf136952's p2, 17 lines, ends with
                // two on p3 in Word's print, where ours left one.)
                let atTop = !(pgs.y > 0.01 || cursor > top + 0.01)
                if theme.wordRules, pgs.floatHold == nil, let chosen = cut {
                    let st = document.paragraphs[pgs.i].style
                    let all = cuts!
                    let first = all.firstIndex(where: { $0 > cursor + 0.01 }) ?? 0
                    let last = all.lastIndex(where: { $0 <= chosen + 0.01 }) ?? first
                    var keep = last - first + 1
                    // (Kept whole where its lines all fit and only its space
                    // after does not: zh-64044a1d's one-line "資料來源：本計畫
                    // 整理。", its style's `w:keepLines` and 18pt after, ends
                    // p34 under its figure in Word for Windows' print, the
                    // space past the foot; ours sent it to p35, and the 66
                    // lines after it a page down.)
                    if atTop {
                        if st.widowControl, !st.keepLines, !document.widowControlSuspended, all.count - 1 - last == 1, keep >= 3 { keep -= 1 }
                    } else if st.keepLines, bottom - top <= pgs.contentH + 0.01 {
                        if last < all.count - 1 { keep = 0 }
                    } else if st.widowControl, !document.widowControlSuspended,
                              // (A wrapper table's text is a cell's, set as the body is: before
                              // Word's 2013 layout a cell keeps no widow or orphan —
                              // floattable-del-empty's last paragraph of page 5, two lines,
                              // parts after its first in Word's print.)
                              !(RichTextTheme.wordWindowsPages && (document.compatibilityMode ?? 12) < 15
                                && document.paragraphs[pgs.i].keptTable?.hasPrefix("kc") == true) {
                        let besideStripC14 = RichTextTheme.wordWindowsPages && (document.compatibilityMode ?? 12) < 15 && first == 0
                            && last < all.count - 1 && document.paragraphs[pgs.i].image == nil && document.paragraphs[pgs.i].cell == nil
                            && (_besideFar[pgs.i] != nil || _besideOwn(pgs.i, document.paragraphs[pgs.i], document) != nil)
                        if all.count - 1 - last == 1, !(besideStripC14 && keep == 1) { keep -= 1 }
                        // (An orphan only where lines go on: the whole of
                        // a one-line paragraph fits, though its space
                        // after does not — bug59058's thirteenth empty
                        // paragraph under a table, 15.4pt of line in
                        // 17.3pt left, stays at the foot in Word. Not a
                        // picture's paragraph, whose cuts are its empty
                        // line's and not the picture's: bug57031's 360pt
                        // chart then started at page 1's foot.)
                        // (Before Word's 2013 layout a paragraph whose first line stands beside a picture's strip at the
                        // foot parts after that line: no orphan control there. lab6883, compat 14: one line at
                        // page 1's foot, in the strip, whatever the wrapping and the widow setting; at compat 15 the
                        // whole paragraph goes on.)
                        let aloneBesideStrip = besideStripC14 && keep == 1
                        if aloneBesideStrip { RuleTrace.hit("word-compat14-orphan-line-beside-a-picture-strip-stays-at-the-foot") }
                        else if cursor <= top + 0.01, keep < 2, last < all.count - 1 || document.paragraphs[pgs.i].image != nil { keep = 0 }
                    }
                    // (Nor does a page end with a line its automatic hyphenation parted a word at, in Word for
                    // Windows: lab `pf` (lo-000463df's styles, an 8-line paragraph whose lines 2 and 5 end "…ti-")
                    // never leaves 2 or 5 of its lines at the foot, at any spacing or space before — one fewer, and
                    // under widow control none for 2; with line breaks there instead, 5 stay. lo-000463df's
                    // paragraph 37 so: none of it on page 2 in Word's print, one with widow control off.)
                    if RichTextTheme.wordWindowsPages, keep > 0, first + keep < all.count, let shown = _hyphenShown[pgs.i], !shown.isEmpty,
                       let g = Optional(geometry(pgs.i)), pgs.i < _inserts.count {
                        let starts = _lineStarts(g.painter, _OffsetMap(lead: _lead(pgs.i), inserts: _inserts[pgs.i]), count: document.paragraphs[pgs.i].text.utf16.count)
                        let next = first + keep
                        if next < starts.count, shown.contains(starts[next]), _hyphenPoints[pgs.i]?.contains(starts[next]) == true {
                            keep -= 1
                            if st.widowControl, !document.widowControlSuspended, !atTop, keep < 2 { keep = 0 }
                        }
                    }
                    if keep <= 0 {
                        // (Only where a new page gives it more room.)
                        if pgs.y > 0.01 { cut = nil }
                    } else {
                        cut = all[first + keep - 1]
                    }
                }
                // (A picture's line taller than the page, at a page's top: its
                // cut is the grid's pitch under the picture's top, and the page
                // took that sliver; Word keeps the picture whole, over the foot.)
                if theme.wordRules, cut != nil, pgs.y <= 0.01, cursor <= top + 0.01, (document.paragraphs[pgs.i].image != nil || _inlinePictureOnly(pgs.i, document)),
                   bottom - _spacing(pgs.i, document).after - cursor > available + slack + overhang {
                    _pg_add(&pgs, document, PagePiece(paragraph: pgs.i, flowTop: cursor, flowBottom: bottom, page: pgs.page, pageY: pgs.y))
                    cursor = bottom
                    pgs.y = pgs.contentH
                    break
                }
                if let cut {
                    if cut - cursor > available + 0.01, !placedFrame { pgs.overfull = true }
                    _pg_add(&pgs, document, PagePiece(paragraph: pgs.i, flowTop: cursor, flowBottom: cut,
                                                  page: pgs.page, pageY: pgs.y))
                    cursor = cut
                    // (Where the cut is under the paragraph's last line,
                    // what is left is its space after: Word leaves that at
                    // the page's foot, and the next page starts with the
                    // next paragraph — carried over, it set zh-a4b0f6ea's
                    // page 8 heading 8pt low.)
                    if theme.wordRules, let lastLine = cuts!.last, cut >= lastLine - 0.01 {
                        cursor = bottom
                        pgs.y = pgs.contentH
                        break
                    }
                    if let hold = pgs.floatHold { pgs.y = hold.back; pgs.floatHold = nil; pgs.frameReturn = nil } else { _pg_newPage(&pgs, document) }
                } else if pgs.floatHold != nil {
                    // Nothing fits over the table: all of it goes under.
                    pgs.y = pgs.floatHold!.back; pgs.floatHold = nil; pgs.frameReturn = nil
                } else if pgs.y > 0.01, theme.wordRules, RichTextTheme.wordWindowsPages, document.paragraphs[pgs.i].text.isEmpty,
                          document.paragraphs[pgs.i].image == nil, pgs.i + 1 < count, document.paragraphs[pgs.i + 1].style.markFollowsBreak,
                          _pageBreak[pgs.i + 1], bottom - cursor <= pgs.contentH - pgs.y + _px(2.5) {
                    // (A line that holds only a page break, hung a little past the foot
                    // (the length of a line's leading), stays on its page and the break
                    // ends it: lo floattable-header's 13.8pt line at 761.6, the foot at
                    // 788.2, is page 1's last in Word's print; ours took it to a page
                    // of its own and the table after it to the page after, 10 pages
                    // for 8.)
                    RuleTrace.hit("page-break-line-hangs-past-the-foot")
                    _pg_add(&pgs, document, PagePiece(paragraph: pgs.i, flowTop: cursor, flowBottom: bottom, page: pgs.page, pageY: pgs.y))
                    cursor = bottom
                    pgs.y = pgs.contentH
                    break
                } else if pgs.y > 0.01 {
                    // Nothing fits in what is left of this page: start a new one.
                    _pg_newPage(&pgs, document)
                } else {
                    // A single line taller than a page: place it and overflow.
                    // (A picture's paragraph whole, the line under the picture
                    // too: zh-6d402586's "參考資料1", a 749pt picture on a page
                    // of 698, is page 26 in Word's print, its mark and section
                    // break with it, and "參考資料2" page 27; ours carried the
                    // 9pt under the picture to a page 27 of its own, and the
                    // next section went to 28.)
                    let pictureOnly = document.paragraphs[pgs.i].image != nil || _inlinePictureOnly(pgs.i, document)
                    let next = theme.wordRules && pictureOnly ? bottom
                        : cuts!.first(where: { $0 > cursor + 0.01 }) ?? bottom
                    _pg_add(&pgs, document, PagePiece(paragraph: pgs.i, flowTop: cursor, flowBottom: next,
                                                  page: pgs.page, pageY: pgs.y))
                    cursor = next
                    if theme.wordRules, pictureOnly {
                        // (The page is full; what follows opens the next one.)
                        pgs.y = pgs.contentH
                        break
                    }
                    _pg_newPage(&pgs, document)
                }
            }
        }
        if !pgs.deferredUnder.isEmpty { _pg_placeDeferred(&pgs, document) }
        if pgs.notesOn {
            // (Notes still waiting at the end — every paragraph kept to
            // the last — stand at the last page's foot.)
            if !pgs.pendingNotes.isEmpty { _pg_reserveNotes(&pgs, document, pgs.pendingNotes); pgs.pendingNotes = [] }
            if !pgs.rowPending.isEmpty { _pg_reserveNotes(&pgs, document, pgs.rowPending); pgs.rowPending = [] }
            _pageNotes[pgs.page] = pgs.pageNotes
        }
        if _pages.count > 1 && _pages[_pages.count - 1].isEmpty { _pages.removeLast() }
        // Each page's top on the canvas, under the pages before it.
        let physicalPages = max(1, (_pages.count + _columns - 1) / _columns)
        while _pageSection.count < physicalPages { _pageSection.append(_pageSection.last ?? max(0, _sectionSetups.count - 1)) }
        if _pageSection.count > physicalPages { _pageSection.removeSubrange(physicalPages...) }
        while _pageInsetTop.count < physicalPages { _pageInsetTop.append(_px(pageSetup(forPage: _pageInsetTop.count).marginTop)) }
        if _pageInsetTop.count > physicalPages { _pageInsetTop.removeSubrange(physicalPages...) }
        _pageTops = []
        var pageTop = 0.0
        for k in 0 ..< physicalPages {
            _pageTops.append(pageTop)
            pageTop += _pxPageH(k) + _pxGap
        }
        // Pieces came out in paragraph order (a row's members are contiguous
        // and a paragraph's cuts consecutive), so one flat array indexed by
        // start replaces an array per paragraph.
        if _pieceStart.count != count + 1 { _pieceStart = Array(repeating: 0, count: count + 1) }
        var k = 0
        for para in 0 ... count {
            while k < _allPieces.count, _allPieces[k].paragraph < para { k += 1 }
            _pieceStart[para] = k
        }
        // Footnotes of a page of columns (Word's print, lo-9749f2b5): they
        // stand at the page's foot in the page's columns, set after the
        // text. Only placed here, not yet reserved off the text's room.
        if theme.wordRules, RichTextTheme.wordWindowsPages, _columns > 1, !document.footnotes.isEmpty, !pgs.slotNotes {
            _pageNotes = [:]
            _noteColumn = [:]
            // (A paragraph cut over pages keeps the notes whose marks stand
            // in its lines on the page; the flow positions of its pieces run
            // from the paragraph's own first.)
            var origin: [Int: Double] = [:], cuts: [Int: Int] = [:]
            for slot in _pages.indices { for piece in _pages[slot] where !piece.repeated {
                origin[piece.paragraph] = min(origin[piece.paragraph] ?? .infinity, piece.flowTop)
                cuts[piece.paragraph, default: 0] += 1
            } }
            for slot in _pages.indices {
                let phys = slot / _columns
                for piece in _pages[slot] where !piece.repeated {
                    for id in _footnotes(in: piece.paragraph, document) {
                        if cuts[piece.paragraph, default: 1] > 1, _cells[piece.paragraph] == nil,
                           let top = _footnoteMarkTop(piece.paragraph, id, document) {
                            // (A page of sections keeps the flow's own positions, the mark's as well as the pieces': f7341551's
                            // footnotes 1-10, marked on cut paragraphs of its two-column section, stood on no page.)
                            let o = _perSection ? 0 : origin[piece.paragraph] ?? 0
                            if top < piece.flowTop - o - 0.01 || top >= piece.flowBottom - o - 0.01 { continue }
                        }
                        if _pageNotes[phys]?.contains(id) != true { _pageNotes[phys, default: []].append(id); _noteColumn[id] = slot % _columns }
                    }
                }
            }
            // (Notes stand in the order of their marks in the file.)
            for k in Array(_pageNotes.keys) { _pageNotes[k]?.sort() }
            // Each page's columns, and the room its notes take off them.
            var needed: [Int: Double] = [:]
            _columnNoteGeometry = [:]
            for (phys, ids) in _pageNotes {
                let paras = (phys * _columns ..< min((phys + 1) * _columns, _pages.count)).flatMap { _pages[$0].filter { !$0.repeated }.map { $0.paragraph } }
                guard let first = paras.first(where: { _cells[$0] == nil }) ?? paras.first else { continue }
                let same = Set(paras.map { _columnsOf(paragraph: $0) }).count == 1
                // (A page of sections that differ keeps the page's own setup: the
                // columns and margin its first notes stand in, lo-9749f2b5.)
                let s = same ? _setup(ofParagraph: first) : pageSetup(forPage: phys)
                let geo = (columns: max(1, s.columns), width: _px(s.columnWidth), stride: _px(s.columnWidth + s.columnGap),
                           left: same ? _pxColumnLeft(phys, column: 0, paragraph: first) : _pxMarginLeft(phys), perColumn: false)
                _columnNoteGeometry[phys] = geo
                // (Word shares a page's notes out over its columns in order, whole, whatever column their marks stand in
                // (f7341551 pages 5-9: 311 to 635 of 642 lines), and holds the tallest column's room off every column: the notes stand
                // at the page's foot, so a line that would cross their rule goes on. sa1 978697fd's page 5,
                // a one-line note at 702pt, parts "Para el 2013" whole to page 6 in Word's print.)
                if theme.wordRules, let lay = _columnNoteLayout(phys, ids, document), lay.height > 0 {
                    for c in 0 ..< _columns { needed[phys * _columns + c] = lay.height + lay.separator }
                }
            }
            // (Shortening a column moves marks, and with them notes, to
            // other columns, so the rooms can chase each other; from the
            // third round they only grow, which settles.)
            let raw = needed
            if _columnNoteRounds >= 2 { for (k, v) in _columnNoteRaw { needed[k] = max(needed[k] ?? 0, v) } }
            _columnNoteRaw = _columnNoteRounds >= 2 ? needed : raw
            if needed != _columnNoteReserve, _columnNoteRounds < 10 {
                _columnNoteReserve = needed
                _columnNoteRounds += 1
                RuleTrace.hit("footnotes-under-the-columns-take-their-room")
                _paginate(document)
                return
            }
            _columnNoteRounds = 0
        } else if !_columnNoteReserve.isEmpty {
            _columnNoteReserve = [:]
        }
        _pagesValid = true
    }

    /// `STARLING_RICHTEXT_PERF=1` also prints page-break decisions.
    public static let debugPagination = ProcessInfo.processInfo.environment["STARLING_RICHTEXT_PERF"] != nil
    /// `STARLING_RICHTEXT_FIT=<text>`: the East Asian line fitting of
    /// every paragraph that contains the text, stretch by stretch, on
    /// standard error (points) — where a line of ours and of Word's end
    /// a character apart, this says which rule let it on. Every such
    /// paragraph's width against its column's, too.
    /// How far past the right margin Word still honours a right tab stop (lab tabr: 452 twips measured, none refused).
    static let _tabPastMargin = 22.6
    /// Word for Windows before 2013's layout (compat 14 and under) ends a tab stop's text AT the stop, however far past the margin
    /// (lab tabpast14: stops 0 to 568 twips past, right, centre and left alike; compat 15 clamps them).
    static func _honoursStopsPastMargin(_ d: RichDocument) -> Bool {
        RichTextTheme.wordWindowsPages && (d.compatibilityMode ?? 12) < 15
    }
    /// How far a tall floating table (text- or page-anchored) can rise to bring a straddling line to the page edge: 0.4 cm
    /// (Word's print of labs tblstrip8: lifts to 10.92, none from 11.4).
    static let floatingTableLiftLimit = 11.34
    static let debugFit = ProcessInfo.processInfo.environment["STARLING_RICHTEXT_FIT"]
    /// A machine-readable record of each over-the-margin decision in `_fitEastAsianLines`, to stderr: test/tools/fit-decisions.py joins them with Word's lines.
    static let debugFitLog = ProcessInfo.processInfo.environment["STARLING_FIT_LOG"] != nil
    static let debugWidthCheck = ProcessInfo.processInfo.environment["STARLING_FIT_WIDTH_CHECK"] != nil
    /// `STARLING_RICHTEXT_ROWS=<page>`: each table row set on that page,
    /// to stderr (see `_paginate`).
    static let debugRows = ProcessInfo.processInfo.environment["STARLING_RICHTEXT_ROWS"].flatMap { Int($0) }
    /// `STARLING_RICHTEXT_AUTOFIT=1`: each autofit table a cell's
    /// narrowest setting re-fits (`_autofit`), its cells over their room
    /// and the widths it comes to, to stderr (points).
    static let debugAutofit = ProcessInfo.processInfo.environment["STARLING_RICHTEXT_AUTOFIT"] != nil

    /// The room a cell's rule of this style and width (points) takes:
    /// a double line three widths; a thin line, a gap and a thick one
    /// the width and the other two's — Word's print of zh-06c46ba9's
    /// "thinThickSmallGap" at 1.5pt is a 0.72 line, a 0.72 gap and a
    /// 1.44 line, 2.88 in all, and its rows are that much taller.
    static func _ruleRoom(_ style: String?, _ width: Double) -> Double {
        switch style {
        case "double": return width * 3
        // (A triple rule: three lines and two gaps of the width, 5 widths. xa-style sa1 5393bae9's 0.5pt "triple" table rows are 2.5pt taller in Word's print.)
        case "triple": return width * 5
        case "thinThickSmallGap", "thickThinSmallGap": return width + 1.5
        // (Word's print of xa gv-d4270b921d's 3pt table top: a 0.69 line, 0.83 gap, 2.9 line, 0.83 gap, 0.69 line, 5.9pt in all.)
        case "thinThickThinSmallGap": return width + 3
        case "thinThickMediumGap", "thickThinMediumGap": return width * 2
        // (Word's print of dx2 5b919053's 3pt threeDEngrave table top: 6.0pt from the outer edge to the first row, 1.4 + 3.0 + 1.4 of lines
        // and a hairline; the first row and all below it sit 2.8pt lower than a single 3pt rule would put them.)
        case "threeDEngrave", "threeDEmboss": return width * 2
        case "thinThickLargeGap", "thickThinLargeGap": return width + 2.25
        default: return width
        }
    }

    /// The lines a rule of this style is drawn as, from the side of the
    /// text outward: where each starts (points from the rule's inner
    /// edge) and its width. A single line is one; a double two of the
    /// width a width apart; a thin-and-thick one its width and a 0.75pt
    /// line, the thick by the text for thinThick and outside it for
    /// thickThin (zh-69bbcc3c's letterhead rule in Word's print: 2.16,
    /// a 0.72 gap, 0.72), the gap what `_ruleRoom` leaves.
    static func _ruleLines(_ style: String?, _ width: Double) -> [(at: Double, width: Double)] {
        let thin = 0.75, gap = max(0, _ruleRoom(style, width) - width - thin)
        switch style {
        case "double": return [(0, width), (2 * width, width)]
        case "triple": return [(0, width), (2 * width, width), (4 * width, width)]
        case "threeDEngrave", "threeDEmboss": return [(0, 0.47 * width), (0.47 * width, width), (1.47 * width, 0.47 * width)]
        case "thinThickThinSmallGap": return [(0, thin), (thin + 0.75, width), (thin + 0.75 + width + 0.75, thin)]
        case "thinThickSmallGap", "thinThickMediumGap", "thinThickLargeGap": return [(0, width), (width + gap, thin)]
        case "thickThinSmallGap", "thickThinMediumGap", "thickThinLargeGap": return [(0, thin), (thin + gap, width)]
        default: return [(0, width)]
        }
    }

    public var isPaged: Bool { pageSetup != nil }

    /// The page, counted from 1, a paragraph starts on — for a table of
    /// contents with page numbers. Nil unpaged, or before `ensureLaidOut`.
    public func pageNumber(ofParagraph i: Int) -> Int? {
        guard isPaged, i >= 0, i < count, _pieceStart.count == count + 1 else { return nil }
        let pieces = _allPieces[_pieceStart[i] ..< _pieceStart[i + 1]]
        guard let piece = pieces.first(where: { $0.part != .rules && !$0.repeated }) ?? pieces.first else { return nil }
        return piece.page / _columns + 1
    }
    /// `_pages` holds one entry per column slot; a page has `columns` of them.
    public var pageCount: Int { isPaged ? max(1, (_pages.count + _columns - 1) / _columns) : 1 }
    /// Per column slot (page × columns + column), in flow order.
    public var pieces: [[PagePiece]] { _pages }

    /// The laid-out document, one text line per line: `p<page> ¶<paragraph>
    /// <height> |<text>|`, after a first line with the page count. Two
    /// layouts that agree — native and browser, before and after a save —
    /// produce identical text, and where they differ, `diff` says which
    /// line broke elsewhere. Heights are line advances (the room pagination
    /// consumes), in logical pixels to a tenth, not a fallback font's ink metrics.
    public func lineDump(_ document: RichDocument) -> String {
        ensureLaidOut(document)
        var out = "pages \(pageCount)\n"
        for i in 0 ..< count {
            let para = document.paragraphs[i]
            let g = geometry(i)
            let pieces = _pieceStart.count == count + 1 ? _allPieces[_pieceStart[i] ..< _pieceStart[i + 1]] : []
            func page(atFlow y: Double) -> Int {
                let piece = pieces.first { $0.part != .rules && y < $0.flowBottom - 0.01 } ?? pieces.last
                return piece.map { $0.page / _columns + 1 } ?? 0
            }
            // The block: its height with the spacing around the text, and
            // where the text starts inside it — what pagination sums.
            out += "¶\(i) block \(_tenth(g.height)) text@\(_tenth(g.textTop - g.top))\n"
            if para.isImage {
                out += "p\(page(atFlow: g.textTop)) ¶\(i) \(_tenth(g.height)) |<image>|\n"
                continue
            }
            let utf16 = para.text.utf16
            var y = g.textTop
            var start = 0
            let lines = g.painter.computeLineMetrics()
            let map = _map(i)
            let bottoms = Self._lineBottoms(g.painter)
            let first = y
            var k = 0
            for line in lines {
                let r = g.painter.getLineBoundary(TextPosition(offset: map.painter(start)))
                let end = max(start, min(map.paragraph(r.end), para.length))
                let a = utf16.index(utf16.startIndex, offsetBy: start)
                let b = utf16.index(utf16.startIndex, offsetBy: end)
                let text = (String(utf16[a ..< b]) ?? "").trimmingWhitespace()
                // A forced strut keeps the line's advance even when a
                // fallback font has a taller ascent/descent. Those raw
                // metrics differ across CoreText and FreeType (Carlito's
                // missing U+2010 in word-boringcrypto), but set no extra
                // room. Report the same advance used to page the line.
                let bottom = k < bottoms.count ? bottoms[k] : y - first + line.height
                out += "p\(page(atFlow: y)) ¶\(i) \(_tenth(first + bottom - y)) |\(text)|\n"
                y = first + bottom
                k += 1
                start = end
                if start >= para.length { break }
            }
            if lines.isEmpty { out += "p\(page(atFlow: y)) ¶\(i) \(_tenth(g.painter.height)) ||\n" }
        }
        return out
    }

    func _tenth(_ v: Double) -> String {
        let t = Int((v * 10).rounded())
        return "\(t / 10).\(t % 10)"
    }

    /// Page `p`'s rectangle on the canvas.
    public func pageRect(_ p: Int) -> Rect {
        let top = p >= 0 && p < _pageTops.count ? _pageTops[p] : Double(p) * (_pxPageH(p) + _pxGap)
        return Rect.fromLTWH(0, top, _pxPageW(p), _pxPageH(p))
    }

    /// The canvas: the page column when paged, else the flow itself.
    public var canvasSize: Size {
        guard isPaged else { return Size(width, totalHeight) }
        let last = pageRect(pageCount - 1)
        return Size((0 ..< pageCount).reduce(0.0) { max($0, _pxPageW($1)) }, last.bottom)
    }

    /// Page index under canvas y (clamped).
    public func page(atCanvasY y: Double) -> Int {
        guard isPaged else { return 0 }
        var p = 0
        while p + 1 < pageCount, p + 1 < _pageTops.count, y >= _pageTops[p + 1] - _pxGap / 2 { p += 1 }
        return max(0, min(pageCount - 1, p))
    }

    /// Flow rectangle → canvas rectangles (one, unless it straddles pieces).
    public func canvasRects(_ r: Rect) -> [Rect] {
        guard isPaged else { return [r] }
        // By the rect's middle, not its top edge: a rect is never taller
        // than its paragraph, and a sub-pixel overshoot at either edge must
        // not hand it to a neighbour whose pieces then clip it to a sliver.
        let i = paragraphIndex(atY: r.height > 0 ? (r.top + r.bottom) / 2 : r.top)
        var out: [Rect] = []
        let pieces = i + 1 < _pieceStart.count ? Array(_allPieces[_pieceStart[i] ..< _pieceStart[i + 1]]) : []
        for piece in pieces where piece.part != .rules {
            let lo = max(r.top, piece.flowTop)
            let hi = min(r.bottom, piece.flowBottom)
            let inside = r.height <= 0 ? (r.top >= piece.flowTop && r.top < piece.flowBottom + 0.01) : hi > lo
            if !inside { continue }
            let page = piece.page / _columns
            let dy = pageRect(page).top + _pxMarginTop(page) + piece.pageY - piece.flowTop
            let dx = _pxColumnLeft(page, column: piece.page % _columns, paragraph: piece.paragraph)
            out.append(Rect.fromLTRB(r.left + dx, lo + dy, r.right + dx, max(hi, lo) + dy))
        }
        if out.isEmpty, let piece = pieces.last ?? _pages.last?.last {
            // Past the last cut (a caret in trailing space-after): pin to the
            // piece's page.
            let page = piece.page / _columns
            let dy = pageRect(page).top + _pxMarginTop(page) + piece.pageY - piece.flowTop
            let dx = _pxColumnLeft(page, column: piece.page % _columns, paragraph: piece.paragraph)
            out.append(Rect.fromLTRB(r.left + dx, r.top + dy, r.right + dx, r.bottom + dy))
        }
        return out
    }

    /// Canvas point → flow point. Points in a page's margins or in the gap
    /// snap to the nearest content on that page.
    public func flowPoint(_ p: Offset) -> Offset {
        guard isPaged else { return p }
        let page = self.page(atCanvasY: p.dy)
        let localY = p.dy - pageRect(page).top - _pxMarginTop(page)
        // The column under x, then the point relative to it.
        let column = max(0, min(_columns - 1, Int(floor((p.dx - _pxMarginLeft(page)) / max(1, _pxColumnStride(page))))))
        let x = p.dx - _pxMarginLeft(page) - Double(column) * _pxColumnStride(page)
        let slot = page * _columns + column
        let pieces = _pages.indices.contains(slot) ? _pages[slot] : []
        guard let first = pieces.first, let last = pieces.last else {
            return Offset(x, totalHeight)
        }
        if localY <= first.pageY { return Offset(x, first.flowTop + max(0, localY - first.pageY)) }
        for piece in pieces where piece.part != .rules && localY < piece.pageY + piece.height {
            return Offset(x, piece.flowTop + (localY - piece.pageY))
        }
        return Offset(x, last.flowBottom - 0.01)
    }

    public func canvasCaretRect(_ pos: RichPosition, _ document: RichDocument) -> Rect {
        canvasRects(caretRect(pos, document)).first!
    }

    public func canvasSelectionRects(_ sel: RichSelection, _ document: RichDocument) -> [Rect] {
        selectionRects(sel, document).flatMap { canvasRects($0) }
    }

    public func canvasPosition(at p: Offset, _ document: RichDocument) -> RichPosition {
        position(at: flowPoint(p), document)
    }

    func _renumberLists(_ document: RichDocument) {
        _listLabels = RichListNumbering.labels(document)
        _listValid = true
    }

    /// Paragraph `i`'s space before and after, in pixels, without its
    /// borders: none against a neighbour of the same style under
    /// contextual spacing, Word's 14pt where it is automatic.
    /// Whether paragraph `i` is the empty mark that ends a cell under a
    /// table nested in it (`RichTextBox.growsToFit`): Word gives it no
    /// room at all, line or spacing. bug65738's cell of a two-row nested
    /// table ends 2.75pt under the table in Word's print; ours stood a
    /// line and its 10pt after lower, and the row with it (lab, Word 16,
    /// 2026-10-15: with "after" typed in the mark's paragraph, the row
    /// grows by that line and its spacing, 26pt).
    func _markUnderNestedTable(_ i: Int, _ document: RichDocument) -> Bool {
        guard theme.wordRules, i > 0, i < document.paragraphs.count else { return false }
        let p = document.paragraphs[i]
        guard let c = p.cell, p.text.isEmpty, p.image == nil,
              document.paragraphs[i - 1].cell == c,
              document.paragraphs[i - 1].image?.textBox?.growsToFit == true else { return false }
        return i + 1 >= document.paragraphs.count || document.paragraphs[i + 1].cell != c
    }

    func _spacing(_ i: Int, _ document: RichDocument) -> (before: Double, after: Double) {
        let p = document.paragraphs[i]
        // A table nested in a cell has no paragraph's spacing, nor has
        // the empty mark under it (bug65738: 10pt after each in ours).
        if theme.wordRules, p.cell != nil, p.image?.textBox?.growsToFit == true || _markUnderNestedTable(i, document) {
            return (0, 0)
        }
        let style = p.style
        // Word's auto spacing: 14pt, none between items of a list.
        // (None between two items of one list; the first item, under a
        // paragraph of no list or another, keeps the web's 14pt — Word
        // sets bug59058's first reference 30pt under its "References"
        // (9pt after), its others 24 apart, where ours gave the first
        // none and stood it 5pt high.)
        // (One list: the same numbering where the file names one, of any
        // level — delins's bullets of numId 1 and the nested one of
        // numId 2 under them stand 14pt apart in Word's print, where ours
        // took them for one list, both being bullets, and set none.)
        func oneList(_ a: RichParagraphStyle, _ b: RichParagraphStyle) -> Bool {
            guard a.list != nil, b.list != nil else { return false }
            if let x = a.listId, let y = b.listId { return x == y }
            return a.list == b.list
        }
        let autoGap = style.list == nil || !(i > 0 && oneList(document.paragraphs[i - 1].style, style)) ? 14.0 : 0.0
        // Contextual spacing: no space against a neighbour of the same style.
        func sameStyle(_ j: Int) -> Bool {
            guard j >= 0, j < document.paragraphs.count else { return false }
            let o = document.paragraphs[j].style
            // (Word compares the paragraph style alone: a bulleted List
            // Paragraph and a numbered one under it share no space —
            // POI's Numbering — and nor do a numbered paragraph of no
            // named style and the plain one under it: bug65649's
            // "1. Предмет аукциона…" keeps its 10pt after from
            // "Начальная (максимальная) цена контракта" in Word's print,
            // which ours set 10pt down, and every line of the page with
            // it. A list of the editor's own, unstyled, still goes by
            // its kind.)
            if theme.wordRules, document.readFromFile, o.named == style.named, o.heading == style.heading,
               document.paragraphs[j].cell == p.cell {
                return true
            }
            // (Two list items either side of a cell's edge are not alike,
            // whatever their kinds: zh-06c46ba9's "（二）現況分析", a
            // numbered List Paragraph under a table whose last paragraph
            // is one too, keeps its 6pt before in Word's print.)
            if theme.wordRules, document.readFromFile, o.list != nil, style.list != nil,
               document.paragraphs[j].cell != p.cell {
                return false
            }
            // (A List Paragraph with a number, then a table whose first cell holds a List Paragraph without one: Word's contextual
            // spacing goes by the style alone, so the 10 pt after is gone before the table; dx2 254ca33b: ours 9.9 pt low from there. Only into the table, and not in right-to-left script: 7d58f74e's Persian table keeps its gap, and the edge after a table (zh-bdae17c0) was never measured.)
            if theme.wordRules, RichTextTheme.wordWindowsPages, document.readFromFile, o.named != nil, o.named == style.named, o.heading == style.heading,
               j > i, style.list != nil, o.list == nil, p.cell == nil, document.paragraphs[j].cell != nil,
               !document.paragraphs[j].text.unicodeScalars.contains(where: { $0.value >= 0x0590 && $0.value <= 0x08FF }) {
                RuleTrace.hit("word-contextual-spacing-across-list-and-table-edge")
                return true
            }
            // (A paragraph's space after, contextual, stands before the next CELL's paragraph of the same style: contextual spacing
            // looks inside one cell only. xd 7d58f74e p2's header row of List Paragraph cells, 10 pt after, is 29.5 pt in Word's print, ours 19.5.)
            if theme.wordRules, RichTextTheme.wordWindowsPages, document.readFromFile, j > i, let a = p.cell, let b = document.paragraphs[j].cell, a != b,
               !(style.spaceAfterAuto || o.spaceBeforeAuto) {
                RuleTrace.hit("word-contextual-spacing-stays-across-a-cell-edge")
                return false
            }
            return o.named == style.named && o.heading == style.heading
                && (o.list == style.list || (theme.wordRules && style.named != nil && o.list != nil && style.list != nil
                    && document.paragraphs[j].cell == p.cell))
        }
        // A list made here, in a document that was not read from a file,
        // is saved in Word's List Paragraph — whose spacing is contextual.
        // It is laid out so from the start: it used to sit loose until
        // saved, and come back tight.
        let contextual = style.contextualSpacing
            || theme.wordRules && style.list != nil && style.named == nil && !document.readFromFile
        // (Across a cell's edge the space it counts in lines stays:
        // zh-fec5fa30's header cells, contextual over half a line before
        // and after, make a row of 51.2pt in Word's print — two 16pt
        // lines and both halves of the 18pt pitch — where ours took the
        // space away, 44.7. zh-1a3c7aa0's cells, contextual over web
        // spacing in points, lose theirs as before: kept, it ran 93 pages
        // to Word's 90.)
        func keepsLines(_ j: Int, _ key: String) -> Bool {
            guard theme.wordRules, j >= 0, j < document.paragraphs.count, let a = p.cell, let b = document.paragraphs[j].cell, a != b else { return false }
            return Double(style.eastAsian[key] ?? "").map { $0 != 0 } ?? false
        }
        let skipBefore = contextual && sameStyle(i - 1) && !keepsLines(i - 1, "w:beforeLines") || theme.omitsLeadingSpace && i == 0
        // (Word for Windows takes a contextual paragraph's space after
        // away before the next ROW's paragraph too, whatever its style —
        // lab rk (Windows 01QbbApP), lo-c8e4ecd8's title row: a lone
        // paragraph of 24pt after, contextual, over a Heading2 row sits
        // 12.3 above it (the heading's own before), 36.3 without the
        // flag; over a Normal row 2.3 against 26.3. Floating or not.)
        func nextRow(_ j: Int) -> Bool {
            guard theme.wordRules, RichTextTheme.wordWindowsPages, j >= 0, j < document.paragraphs.count,
                  document.paragraphs[j].keptTable == nil, p.keptTable == nil,
                  let a = p.cell, let b = document.paragraphs[j].cell else { return false }
            return a.table == b.table && b.row >= a.row + a.rowSpan
        }
        // (Word for Windows, mode 14, xd 80c852b0 p2: a contextual list item over a table whose first cell's paragraph
        // is the same style gives its space after up too, 8pt, though the cell paragraph is no list item.)
        let intoTable = theme.wordRules && RichTextTheme.wordWindowsPages && contextual && p.cell == nil && style.named != nil
            && i + 1 < document.paragraphs.count && document.paragraphs[i + 1].cell != nil && document.paragraphs[i + 1].keptTable == nil
            && document.paragraphs[i + 1].style.named == style.named && document.paragraphs[i + 1].style.heading == style.heading
        let skipAfter = contextual && (sameStyle(i + 1) || nextRow(i + 1) || intoTable) && !keepsLines(i + 1, "w:afterLines")
        // Automatic spacing is the web's, unless the document says its
        // own numbers stand: see `RichDocument.htmlAutoSpacing`.
        let web = !theme.wordRules || document.htmlAutoSpacing
        // Spacing counted in lines (`w:beforeLines`, `w:afterLines`:
        // hundredths of the grid's line pitch, or of 12 points where
        // lines keep to no grid) outranks the measure beside it.
        func inLines(_ s: RichParagraphStyle, _ key: String) -> Double? {
            guard theme.wordRules, let v = Double(s.eastAsian[key] ?? ""), v != 0 else { return nil }
            return v / 100 * (_grid(i, document).pitch ?? 12)
        }
        // (Paragraph `j`'s: an item's automatic space after is none only
        // where an item of its own list follows it.)
        func spaceAfter(_ j: Int) -> Double {
            let s = document.paragraphs[j].style
            let listGoesOn = j + 1 < document.paragraphs.count && oneList(s, document.paragraphs[j + 1].style)
                && !(theme.wordRules && document.paragraphs[j + 1].cell != document.paragraphs[j].cell)
            return web && s.spaceAfterAuto ? (s.list == nil || !listGoesOn ? 14.0 : 0.0) : inLines(s, "w:afterLines") ?? s.spaceAfter
        }
        var spaceBefore = web && style.spaceBeforeAuto ? autoGap : inLines(style, "w:beforeLines") ?? style.spaceBefore
        // (An empty paragraph that is a whole continuous section of its own — it ends
        // the section, and the one before it ended just above — has no space before in
        // Word's print: zh-b8de3ae2 p25's two (7.55pt and 3pt) stand the text after them
        // 10.4pt high, nine lines matched.)
        if theme.wordRules, i > 0, p.text.isEmpty, style.sectionPage != nil,
           document.paragraphs[i - 1].style.sectionPage != nil, document.paragraphs[i - 1].style.sectionBreaksPage != true { spaceBefore = 0 }
        // (Automatic spacing gives way at a cell's edges, as a web page's
        // does: none before a cell's first paragraph, none after its
        // last — zh-a4b0f6ea's cover form, whose every cell is auto
        // spaced, has its title row 14pt shorter in Word's print.)
        // (But a list's last item keeps its space after, as a list in
        // a cell of a web page keeps its bottom margin: zh-147bdae0's
        // numbered commitments stand 14pt over their cells' bottom
        // lines in Word's print, the next row's text 36pt under their
        // last line, where its one-paragraph cells have none — the
        // item's space before at the cell's top goes as any does.)
        var dropAfter = false
        if theme.wordRules, web, let c = p.cell {
            if style.spaceBeforeAuto, i == 0 || document.paragraphs[i - 1].cell != c { spaceBefore = 0 }
            if style.spaceAfterAuto, style.list == nil, i + 1 >= document.paragraphs.count || document.paragraphs[i + 1].cell != c { dropAfter = true }
        }
        // (A paragraph that follows only paragraphs Word shows nothing of is the
        // document's first: dx2 813a5d38's hidden first paragraph, then a heading of auto
        // space before, stood 14pt low in ours, 88.9 in Word's print.)
        var firstShown = i == 0
        if !firstShown, theme.wordRules, web, p.cell == nil {
            firstShown = (0..<i).allSatisfy { _vanishes(document.paragraphs[$0], document) }
        }
        if theme.wordRules, web {
            if firstShown {
                if style.spaceBeforeAuto { spaceBefore = 0 }
            } else if i - 1 < document.paragraphs.count {
                // (In a cell, where the layout shares no space between
                // two paragraphs: `_sharedSpace` is the body's.)
                let above = document.paragraphs[i - 1]
                if p.cell != nil, above.cell == p.cell, style.spaceBeforeAuto || above.style.spaceAfterAuto {
                    spaceBefore = max(0, spaceBefore - spaceAfter(i - 1))
                }
                // (A paragraph of automatic space before that states no space before of its own, straight under a table, has none (the zh files that state one keep the gap):
                // lo-b8885ba2's closing paragraph, a line break then its text, stands at the
                // table's foot in Word's print (276.3 under a table ending 275.8), where ours
                // set it 14pt down and the text a line low.)
                if RichTextTheme.wordWindowsPages, p.cell == nil, above.cell != nil, style.spaceBeforeAuto, style.spaceBefore == 0, spaceBefore > 0 {
                    RuleTrace.hit("word-auto-space-before-under-a-table-is-none")
                    spaceBefore = 0
                }
            }
        }
        // The space two paragraphs share is the upper one's to give up:
        // where contextual spacing takes its space after away, what of
        // this one's space before lay over it goes with it (a title with
        // contextual spacing, then an empty paragraph with 14pt before:
        // nothing between them in Word's print, 2026-10-13).
        if theme.wordRules, theme.collapsesParagraphSpacing, !document.addsParagraphSpacing, i > 0, p.cell == nil,
           i - 1 < document.paragraphs.count, document.paragraphs[i - 1].cell == nil {
            let a = document.paragraphs[i - 1].style
            if a.contextualSpacing, a.named == style.named, a.heading == style.heading,
               a.list == style.list || (style.named != nil && a.list != nil && style.list != nil) {
                spaceBefore = max(0, spaceBefore - spaceAfter(i - 1))
            }
        }
        // (In a table cell the same: lab 80b2f61a, Word's print: a heading
        // with contextual spacing and Normal's 10pt after, then a paragraph
        // of 7pt before in the cell: no gap between them, where ours kept
        // the 7pt and ran the table 7pt a section too tall.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, theme.collapsesParagraphSpacing, !document.addsParagraphSpacing, i > 0, p.cell != nil,
           i - 1 < document.paragraphs.count, document.paragraphs[i - 1].cell == p.cell {
            let a = document.paragraphs[i - 1].style
            if a.contextualSpacing, a.named == style.named, a.heading == style.heading, a.list == style.list, spaceAfter(i - 1) > spaceBefore {
                RuleTrace.hit("word-contextual-spacing-in-a-cell-takes-the-space-before")
                spaceBefore = max(0, spaceBefore - spaceAfter(i - 1))
            }
        }
        // (An empty paragraph that only ends a section takes no room — see
        // `_layoutParagraph` — but its space after is still taken off the
        // space before of the paragraph that follows it: lab `t165` (Windows
        // 01QbbApP, Word for Windows, zh-8f9b19f4's package): p13's "附件5:",
        // 4.3pt before under a sectPr-only paragraph of Normal's 8pt after,
        // stands with none — 20pt before stands 12 down, and the break's
        // after set to 0 gives the 4.3 back. Ours set it 4.27 low.)
        // (Or of the first paragraph of the row a section's columns are
        // set as — `TableStyle.sectionColumns`: p13's "附件5:" is one.)
        // (Where the section it ends is set in one column. A section of
        // columns ends, in Word, under its taller column's last paragraph's
        // space after too — lab t165b (windows), zh-b5359de4's two columns
        // then its "TOC 标题1" of 24pt before: with p74's after 0, the TOC
        // stands 6.84 higher — and the break's 8 still comes off the 24;
        // ours ends the columns at their last line, which gives up about
        // the same, so there the two are left together. They part where
        // the taller column's last paragraph has no after, or the next
        // paragraph's before is under the break's after: such a document
        // wants both, the rule here and the columns' end — t165b's
        // package and markers are ready to lab it.)
        // (And only where the next section goes on on the same page: one
        // the break opens a page for keeps its space before — zh-34a6519a's
        // "1总则" and zh-64044a1d's "壹、前言" stand their whole before under
        // the page's top in Word's print.)
        if theme.wordRules, i > 0, case let above = document.paragraphs[i - 1], above.cell == nil, !p.style.pageBreakBefore,
           p.cell.map({ document.tableStyles[$0.table]?.sectionColumns == true }) ?? true,
           above.text.isEmpty, above.image == nil, above.style.sectionXML != nil {
            spaceBefore = max(0, spaceBefore - spaceAfter(i - 1))
        }
        // An HTML block's margins: its top over its first paragraph, its
        // bottom under its last (`RichDocument.divMargins`).
        var divTop = 0.0, divBottom = 0.0
        if theme.wordRules, let div = style.divId, let m = document.divMargins[div] {
            if i == 0 || document.paragraphs[i - 1].style.divId != div { divTop = m.top }
            if i + 1 >= document.paragraphs.count || document.paragraphs[i + 1].style.divId != div { divBottom = m.bottom }
        }
        let k = spacingFollowsFont ? fontScale : 1
        if p.cell != nil, i < 60, i > 20 { FileHandle.standardError.write("DBG \(i) row=\(p.cell!.row) ctx=\(contextual) skipA=\(skipAfter) drop=\(dropAfter) after=\(spaceAfter(i)) \n".data(using: .utf8)!) }
        return ((skipBefore ? 0 : _px(spaceBefore * k)) + _px(divTop),
                (skipAfter || dropAfter ? 0 : _px(spaceAfter(i) * k)) + _px(divBottom))
    }

    /// The sheet's Normal look, for `RichTextTheme.textStyle`.
    func _normalChar(_ document: RichDocument) -> CharStyle? { document.styles[RichNamedStyle.normalId]?.char }
    /// Whether a paragraph mark's complex-script size is set and differs from its size (the mark's own, its style's, Normal's).
    func _markSzCsDiffers(_ mark: CharStyle, named: RichNamedStyle?, document: RichDocument) -> Bool {
        guard let f = mark.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize, f > 0.5,
              let z = mark.complexFontSize ?? named?.char.complexFontSize ?? _normalChar(document)?.complexFontSize, z > 0.5 else { return false }
        return abs(z - f) > 0.01
    }

    /// How much of body paragraph `i`'s space before lies over the space
    /// after the body paragraph above it: the smaller of the two, so the
    /// larger alone separates them. None across a border, a page break
    /// or a table's edge.
    func _sharedSpace(_ i: Int, _ document: RichDocument) -> Double {
        guard theme.collapsesParagraphSpacing, !document.addsParagraphSpacing,
              i > 0, i < document.paragraphs.count, _cells[i] == nil else { return 0 }
        // (With the paragraph above that shows: one Word hides whole
        // takes no room and parts nothing. drawing.docx's "ИА Regnum"
        // (12pt before) stands 14pt under the text above it (14 after)
        // in Word's print, an empty paragraph of a hidden mark between
        // them; ours had both, 12pt more, and page 11 lost its foot.)
        var above = i - 1
        while above > 0, _vanishes(document.paragraphs[above], document) { above -= 1 }
        guard _cells[above] == nil else { return 0 }
        let style = document.paragraphs[i].style
        // (Across a paragraph's border too: lab `sp3` in bug59058's
        // package, Word 16, 2026-10-15 — 9pt after over 9pt before is
        // 9 between the lines' 15, a bottom line on the first or a top
        // one on the second adds its own width and `w:space` and no
        // more: 24.00, 24.48, 25.44 with both, 28.56 with a line 4pt
        // off. bug59058's "Abstract", ruled under, had its 9 and the
        // body's 9 both, and page 24 lost its last line.)
        guard !style.pageBreakBefore else { return 0 }
        // (An empty paragraph that only ends a section takes no room, its space before with it, so
        // it lays none over the one above's after: lo-373ee508's heading, 6pt after, then the
        // section's mark of 6 before — 6 between the lines it numbers in Word's print, ours 0.)
        if theme.wordRules, document.paragraphs[i].text.isEmpty, document.paragraphs[i].image == nil, style.sectionXML != nil { return 0 }
        // (Nor over the space after one that only ends a section: `_spacing` already takes that
        // off this one's space before, so it comes off once. lo-563123f3's "C", 12pt before under
        // a continuous section's mark of 10 after: 111.9 in Word's print, lab sect563b, ours 109.9.
        // The section's column count and break type change nothing: lab sect5359, Word's print.)
        if theme.wordRules, _heights[above] == 0, document.paragraphs[above].text.isEmpty, document.paragraphs[above].image == nil,
           document.paragraphs[above].style.sectionXML != nil { return 0 }
        let shared = min(_spacing(above, document).after, _spacing(i, document).before)
        return theme.wordRules ? shared : shared.rounded(.down)
    }

    /// A paragraph a page-anchored table's band pushes down stands its space
    /// before less the space after of the paragraph above it (lab dbfl, Word
    /// for Windows, dbd695fe: before 0/6/24 pt under an after of 6 stand
    /// 0/0/18 pt below the table's foot; before 12 under after 0 and 12 stand
    /// 12 and 0). Ours laid the whole before over the band.
    @inline(never)
    func _tableBandSharedSpace(_ i: Int, _ document: RichDocument) -> Double {
        guard theme.wordRules, RichTextTheme.wordWindowsPages, i > 0, i < document.paragraphs.count,
              document.paragraphs[i].cell == nil, document.paragraphs[i - 1].cell == nil,
              !document.paragraphs[i].style.pageBreakBefore, i < _spaceBefore.count else { return 0 }
        return max(0, min(_spaceBefore[i], _spacing(i - 1, document).after))
    }

    /// `_sharedSpace` in a cell: how much of cell paragraph `k`'s space
    /// before lies over the space after the paragraph above it in the
    /// same cell. drawing.docx's "Ведомости и МАЗАЙ" and "Вкратце", two
    /// headings of 12pt before and 3 after in an HTML table's cell, are
    /// 12pt apart in Word's print, and every line under them in the
    /// cell stood 3pt low. (Automatic spacing has had its share taken in
    /// `_spacing`.)
    func _cellSharedSpace(_ k: Int, _ document: RichDocument) -> Double {
        guard theme.wordRules, theme.collapsesParagraphSpacing, !document.addsParagraphSpacing,
              k > 0, k < document.paragraphs.count, let c = document.paragraphs[k].cell,
              document.paragraphs[k - 1].cell == c else { return 0 }
        let above = document.paragraphs[k - 1].style, style = document.paragraphs[k].style
        if document.htmlAutoSpacing, above.spaceAfterAuto || style.spaceBeforeAuto { return 0 }
        guard !style.pageBreakBefore else { return 0 }
        return min(_spacing(k - 1, document).after, _spacing(k, document).before).rounded(.down)
    }

    /// Where a list paragraph's text and number stand, in points, when
    /// the file says: the text at the level's left indent (the
    /// paragraph's own above it) and the number that far back from it —
    /// 65099's "1.1.1" heading is a third level whose text is at 36pt,
    /// not at three levels' worth. nil for a list of the editor's own,
    /// which takes `theme.listIndent` a level.
    func _listIndents(_ p: RichParagraph, _ document: RichDocument) -> (left: Double, hanging: Double)? {
        guard p.style.list != nil else { return nil }
        let level = p.style.listId.flatMap { document.listFormats[$0]?[p.style.listLevel] }
        guard let left = p.style.listIndentLeft ?? level?.indentLeft else { return nil }
        return (left, p.style.listFirstLine.map { -$0 } ?? level?.hanging ?? 0)
    }

    /// The offsets automatic hyphenation may part the paragraph's words at:
    /// when the document sets `w:autoHyphenation`, the paragraph does not
    /// suppress it, and a pattern list is bundled for the run's language.
    func _autoHyphenPoints(_ p: RichParagraph, _ document: RichDocument) -> Set<Int> {
        guard theme.wordRules, p.style.eastAsian["w:suppressAutoHyphens"] != "1",
              let setting = document.keptSettings["w:autoHyphenation"], !setting.containsSubstring("w:val=\"0\""), !setting.containsSubstring("w:val=\"false\""),
              !p.text.isEmpty else { return [] }
        let noCaps = document.keptSettings["w:doNotHyphenateCaps"].map { !$0.containsSubstring("w:val=\"0\"") && !$0.containsSubstring("w:val=\"false\"") } ?? false
        func language(_ xml: String?) -> String? {
            guard let xml, let r = xml.rangeOfSubstring("<w:lang ") else { return nil }
            let rest = String(xml[r.upperBound...])
            guard let v = rest.rangeOfSubstring("w:val=\"") else { return nil }
            let tail = rest[v.upperBound...]
            return tail.firstIndex(of: "\"").map { String(tail[..<$0]) }
        }
        let fallback = language(document.defaultLangXML) ?? "en-US"
        var langs: [(Range<Int>, String)] = []
        var at = 0
        for run in p.runs {
            langs.append((at ..< at + run.length, language(run.style.keptXML) ?? fallback))
            at += run.length
        }
        func lang(at k: Int) -> String { langs.first(where: { $0.0.contains(k) })?.1 ?? fallback }
        var out = Set<Int>()
        var word: [Character] = []
        var start = 0
        var k = 0
        func finish() {
            defer { word = [] }
            guard word.count >= 5 else { return }
            if noCaps, !word.contains(where: { $0.isLowercase }) { return }
            // (A Latin word in an East Asian run (zh, ja, ko) goes by English's — not a
            // Dutch or German one, whose dictionaries the print's box lacks: zh-147bdae0's URLs, in
            // zh-TW runs, part as "Con-tent" and "in-dex" in Word's print.)
            guard let h = Hyphenator.forLanguage(lang(at: start)) ?? (word.allSatisfy { $0.isASCII } && ["zh", "ja", "ko"].contains(where: { lang(at: start).lowercased().hasPrefix($0) }) ? Hyphenator.forLanguage("en-US") : nil) else { return }
            var lens: [Int] = [0]
            for ch in word { lens.append(lens.last! + ch.utf16.count) }
            for c in h.breaks(word) { out.insert(start + lens[c]) }
        }
        for ch in p.text {
            // (An East Asian character is no letter of a word here: it
            // parts the Latin words beside it. zh-147bdae0's "…利用CTP平台"
            // went to the English patterns as one word and was parted
            // "利用CT-P平台" at a line's end, a three-letter "CTP" Word
            // keeps whole.)
            if ch.isLetter, (ch.unicodeScalars.first?.value ?? 0) < 0x2E80 {
                if word.isEmpty { start = k }
                word.append(ch)
            } else { finish() }
            k += ch.utf16.count
        }
        finish()
        return out
    }

    /// Word lets a closing run of ideographic spaces hang past the line: lines that would hold nothing
    /// else are not made (8b283c4d's "政治家" + 59 U+3000 is one line in Word's print, ours two, the
    /// first stretched). Where a paragraph's last lines start inside that run, it is set again with
    /// the run from the first such line on at no width.
    @inline(never) func _cutTrailingSpaces(_ i: Int, _ p: RichParagraph, _ document: RichDocument) {
        guard theme.wordRules, RichTextTheme.wordWindowsPages, let painter = _painters[i], i < _inserts.count else { return }
        let units = Array(p.text.utf16)
        var run = units.count
        while run > 0, units[run - 1] == 0xFFFC { run -= 1 }
        guard run > 0, units[run - 1] == 0x3000 else { return }
        while run > 0, units[run - 1] == 0x3000 { run -= 1 }
        guard run > 0, units[..<run].contains(where: { $0 != 0x20 && $0 != 0x09 && $0 != 0x0A }) else { return }
        let starts = _lineStarts(painter, _OffsetMap(lead: _lead(i), inserts: _inserts[i]), count: units.count)
        guard starts.contains(where: { $0 > run }) else { return }
        _trailCut[i] = run
        _layoutParagraphOnce(i, p, document)
    }

    func _layoutParagraph(_ i: Int, _ p: RichParagraph, _ document: RichDocument) {
        let automatic = _autoHyphenPoints(p, document)
        _hyphenPoints[i] = automatic.isEmpty ? nil : automatic
        _trailCut[i] = nil
        _hanChunks[i] = nil
        _layoutParagraphOnce(i, p, document)
        _hanPieceMoves(i, p, document)
        _cutTrailingSpaces(i, p, document)
        // Soft hyphens (and the points automatic hyphenation may use): the
        // lines that end at one show a hyphen, which takes
        // room, so the paragraph is set again with those drawn until the set
        // of lines ending at one no longer changes (a few rounds at most).
        guard theme.wordRules, !automatic.isEmpty || p.text.utf16.contains(0x00AD) else { _hyphenShown[i] = nil; return }
        let units = Array(p.text.utf16)
        let limit = document.keptSettings["w:consecutiveHyphenLimit"].flatMap { x -> Int? in
            guard let r = x.rangeOfSubstring("w:val=\"") else { return nil }
            return Int(x[r.upperBound...].prefix(while: { $0.isNumber }))
        } ?? 0
        for _ in 0 ..< 8 {
            guard let painter = _painters[i], i < _inserts.count else { return }
            let starts = Set(_lineStarts(painter, _OffsetMap(lead: _lead(i), inserts: _inserts[i]), count: units.count))
            var want = Set<Int>()
            for k in 0 ..< units.count where units[k] == 0x00AD && starts.contains(k + 1) { want.insert(k) }
            for k in automatic where starts.contains(k) { want.insert(k) }
            // (w:consecutiveHyphenLimit: no more lines in a row end at a
            // hyphen than it says — lab hy: 1 and 2 hold exactly.)
            if limit > 0 {
                let order = _lineStarts(painter, _OffsetMap(lead: _lead(i), inserts: _inserts[i]), count: units.count)
                var run = 0
                var dropped = false
                for n in 1 ..< max(1, order.count) {
                    if want.contains(order[n]) || (order[n] > 0 && units[order[n] - 1] == 0x00AD && want.contains(order[n] - 1)) {
                        run += 1
                        if run > limit, let a = _hyphenPoints[i], a.contains(order[n]) {
                            _hyphenPoints[i]?.remove(order[n]); want.remove(order[n]); dropped = true; run = 0
                        }
                    } else { run = 0 }
                }
                if dropped { _hyphenShown[i] = want; _layoutParagraphOnce(i, p, document); continue }
            }
            if want == (_hyphenShown[i] ?? []) { return }
            _hyphenShown[i] = want
            _layoutParagraphOnce(i, p, document)
        }
    }
}

extension RichLayout {
    /// What a paragraph that opens with a page break (not a column break) asks of the page before it,
    /// for a keep chain: its first line down to the baseline. Nil elsewhere.
    @inline(never)
    func _breakLineReach(_ st: RichParagraphStyle, _ g: ParagraphGeometry) -> Double? {
        guard theme.wordRules, RichTextTheme.wordWindowsPages, st.pageBreakInline, !st.columnBreak,
              let base = g.painter.computeLineMetrics().first?.baseline else { return nil }
        return (g.textTop - g.top) + base
    }
}

extension RichLayout {
    /// True when a floating table spans the text's whole width and the next
    /// element is a plain paragraph or a table that does not float.
    /// A strip at a left-set floating table's right that is narrower than the paragraph's own right indent holds no
    /// line of it: what follows goes under the table (sa1 770498eb's empty paragraphs, indent 26.8pt against the 21.5pt
    /// left of a 403pt table, stand under it in Word's print).
    @inline(never)
    func _floatStripNarrowerThanIndent(_ table: String, _ i: Int, _ document: RichDocument) -> Bool {
        guard theme.wordRules, RichTextTheme.wordWindowsPages, _cells[i] == nil, i < document.paragraphs.count else { return false }
        let left = _tableLeft(table, document)
        // (A table standing right of the text's left edge leaves its strip at the LEFT, less the 9pt the text keeps
        // from it: the indent that must fit there is the paragraph's left-hand one, its END indent in a right-to-left
        // paragraph. xd c7b72657: two empties, end indent 35.5pt against 37.8 - 9 = 28.8, stand under the table in Word.)
        if left >= _px(12), (_tableFlowWidth[table] ?? width) - (left + (_columnWidths[table] ?? []).reduce(0, +)) < _px(12) {
            let st = document.paragraphs[i].style
            let side = st.rightToLeft ? st.indentRight : st.indentLeft
            guard side > 0.01, _px(side) > left - _px(9) + 0.01 else { return false }
            RuleTrace.hit("word-float-strip-narrower-than-the-paragraphs-left-indent-leaves-no-strip")
            return true
        }
        let indent = document.paragraphs[i].style.indentRight
        guard indent > 0.01 else { return false }
        let strip = (_tableFlowWidth[table] ?? width) - (left + (_columnWidths[table] ?? []).reduce(0, +))
        guard left < _px(12), strip > 0, _px(indent) > strip + 0.01 else { return false }
        RuleTrace.hit("word-float-strip-narrower-than-the-paragraphs-right-indent-leaves-no-strip")
        return true
    }

    /// A table floating by the text that is WIDER than the text column (it overhangs its right edge): there is no strip
    /// beside it at all, so the whitespace-only paragraph after it goes under it, not up at its anchor line. sa1 5393bae9:
    /// "1. ANTECEDENTES" 204.5 in Word's print, 190.0 in ours (the 12pt mark's line left beside the 438pt table in a 427.7pt column).
    @inline(never)
    func _floatWiderThanFlow(_ table: String, _ i: Int, _ document: RichDocument) -> Bool {
        guard theme.wordRules, RichTextTheme.wordWindowsPages, _cells[i] == nil else { return false }
        let left = _tableLeft(table, document)
        let flow = _tableFlowWidth[table] ?? width
        let sum = (_columnWidths[table] ?? []).reduce(0, +)
        guard left < _px(12), flow - (left + sum) < -0.01 else { return false }
        RuleTrace.hit("word-float-wider-than-the-column-leaves-no-strip-for-the-mark-after-it")
        return true
    }

    @inline(never)
    func _floatLeavesNoStrip(_ table: String, _ i: Int, _ document: RichDocument) -> Bool {
        guard theme.wordRules, _cells[i] == nil else { return false }
        let left = _tableLeft(table, document)
        let flow = _tableFlowWidth[table] ?? width
        let sum = (_columnWidths[table] ?? []).reduce(0, +)
        return max(left, flow - (left + sum)) < _px(12)
    }
}

extension RichLayout {
    /// True when the floating table directly follows another floating table
    /// (two stacked floats: their anchor paragraph stands under both).
    @inline(never)
    func _floatFollowsFloat(_ table: String, _ document: RichDocument) -> Bool {
        guard let j = _cells.firstIndex(where: { $0?.table == table }), j > 0,
              let pt = _cells[j - 1]?.table, pt != table else { return false }
        return document.tableStyles[pt]?.floatOffsetY != nil
    }
}

extension RichLayout {
    /// Where, in body coordinates, Word for Windows lets a floating table's top stand at the lowest: the footer
    /// distance and the line of an empty footer paragraph up from the page's foot (lab ovl2 autow: 777pt of 841.9
    /// with footer 992 twips and a 10.5pt line).
    @inline(never)
    func _floatFootLimit(_ i: Int, page: Int, _ document: RichDocument) -> Double {
        let setup = pageSetup(forPage: page / _columns)
        return _px(setup.height - setup.footerDistance) - _markLineHeight(i, document, single: true) - _bodyInsets(page: page / _columns, document).top
    }
}

extension RichLayout {
    /// A paragraph whose only content is inline pictures (and spaces).
    @inline(never)
    func _inlinePictureOnly(_ i: Int, _ document: RichDocument) -> Bool {
        let p = document.paragraphs[i]
        return !p.inlineImages.isEmpty && p.text.unicodeScalars.allSatisfy { $0.value == 0xFFFC || $0 == " " }
    }
}

extension RichLayout {
    /// The room at a floating table's left that a line can stand in: its left edge less the
    /// distance it asks (`w:leftFromText`). Word's print of lab tblroom: a line stands beside the
    /// table only where its own content fits in that room (MARK, 39.5pt wide, at 51pt free and
    /// not at 31; an empty paragraph at 21pt free and not at 11; the 18 used is the middle of what gv's 16.15pt
    /// free, where Word keeps its blanks below, and the lab's 21 leave open), so gv-fbcf1434e7's table at
    /// 96pt (text from 71, distance 9) has 16pt free and keeps the blank lines below it, where
    /// dx2 f22ada3a's has 346.
    func _tableLeftRoom(_ table: String, _ document: RichDocument) -> Double {
        var dist = 0.0
        if let kept = document.tableStyles[table]?.keptPosition, let r = kept.rangeOfSubstring("w:leftFromText=\"") {
            dist = Double(kept[r.upperBound...].prefix { $0 == "-" || $0.isNumber }) ?? 0
        }
        return _tableLeft(table, document) - _px(dist / 20)
    }
}
